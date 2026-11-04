# Assemble smoke/out/prosmoke.zip from smoke/package. Optionally rebuild the CoD2x
# bridge (MinGW) and pull a freshly built renderer in first. Never installs or launches.
[CmdletBinding()]
param(
    [string]$ToolchainDirectory,            # MinGW root with mingw32\bin\gcc.exe and usr\bin\nasm.exe
    [string]$CMake = 'cmake',
    [string]$Ninja = 'ninja',
    [string]$MsysDirectory = 'C:\msys64',
    [string]$RendererDirectory,             # folder with prosmoke.dll, smoke.shaders, noise128.rgba
    [switch]$NoZip
)
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$package = Join-Path $PSScriptRoot 'package'
$client = Join-Path $package 'client'
$runtime = Join-Path $client 'prosmoke'
$server = Join-Path $package 'server'
$provenance = Join-Path $PSScriptRoot 'provenance'
$out = Join-Path $PSScriptRoot 'out'
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Hash-Source([string]$Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $latin1 = [Text.Encoding]::GetEncoding(28591)   # byte-preserving round trip
        $text = $latin1.GetString([IO.File]::ReadAllBytes($Path)).Replace("`r`n", "`n")
        return [BitConverter]::ToString($sha.ComputeHash($latin1.GetBytes($text))).Replace('-', '').ToLowerInvariant()
    } finally { $sha.Dispose() }
}
function Save-Json([string]$Path, $Value) {
    $json = ($Value | ConvertTo-Json -Depth 12).Replace("`r`n", "`n")
    [IO.File]::WriteAllText($Path, $json + "`n", [Text.UTF8Encoding]::new($false))
}

if ($ToolchainDirectory) {
    $toolchain = (Resolve-Path -LiteralPath $ToolchainDirectory).Path
    $compilerDirectory = Join-Path $toolchain 'mingw32\bin'
    $cCompiler = Join-Path $compilerDirectory 'gcc.exe'
    $cppCompiler = Join-Path $compilerDirectory 'g++.exe'
    $assembler = Join-Path $toolchain 'usr\bin\nasm.exe'
    $cmakePath = (Get-Command $CMake -ErrorAction Stop).Source
    $ninjaPath = (Get-Command $Ninja -ErrorAction Stop).Source
    foreach ($path in @($cCompiler, $cppCompiler, $assembler, (Join-Path $source 'tools\openssl_mingw\lib\libcrypto.a'))) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing bridge build input: $path" }
    }
    $build = Join-Path $PSScriptRoot 'build\bridge'
    $previousPath = $env:PATH
    try {
        $env:PATH = "$compilerDirectory;$(Join-Path $toolchain 'usr\bin');$(Join-Path $MsysDirectory 'usr\bin');$previousPath"
        & $cmakePath -S $source -B $build -G Ninja '-DCMAKE_BUILD_TYPE=RelWithDebInfo' '-DCOD2X_SMOKE_TEST_BUILD=ON' `
            "-DCMAKE_MAKE_PROGRAM=$ninjaPath" "-DCMAKE_C_COMPILER=$cCompiler" "-DCMAKE_CXX_COMPILER=$cppCompiler" `
            "-DCMAKE_ASM_NASM_COMPILER=$assembler"
        if ($LASTEXITCODE) { throw 'CoD2x bridge configuration failed.' }
        & $cmakePath --build $build --target mss32 --parallel 4
        if ($LASTEXITCODE) { throw 'CoD2x bridge build failed.' }
    } finally { $env:PATH = $previousPath }
    Copy-Item -LiteralPath (Join-Path $source 'bin\windows\mss32.build.dll') -Destination (Join-Path $client 'mss32.dll') -Force
    Write-Output 'Bridge rebuilt and copied into the package.'
}

if ($RendererDirectory) {
    $renderer = (Resolve-Path -LiteralPath $RendererDirectory).Path
    foreach ($name in @('prosmoke.dll', 'smoke.shaders', 'noise128.rgba')) {
        Copy-Item -LiteralPath (Join-Path $renderer $name) -Destination (Join-Path $runtime $name) -Force
    }
    Write-Output 'Renderer files copied into the package.'
}

# CoD2 mounts main for a normal launch, and prosmoke when fs_game selects it.
# Both paths, and the server copy, must carry the exact same reviewed grids.
$main = Join-Path $client 'main'
[IO.Directory]::CreateDirectory($main) | Out-Null
Copy-Item -LiteralPath (Join-Path $runtime 'prosmoke_stock.iwd') -Destination (Join-Path $main 'iw_prosmoke_stock.iwd') -Force
Copy-Item -LiteralPath (Join-Path $runtime 'prosmoke_stock.iwd') -Destination (Join-Path $server 'prosmoke_stock.iwd') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'competitive-occupancy\prosmoke_competitive_full.iwd') -Destination (Join-Path $server 'prosmoke_competitive_full.iwd') -Force

$bridge = Get-Content -LiteralPath (Join-Path $provenance 'bridge-build.json') -Raw | ConvertFrom-Json
$bridge.sha256 = Hash (Join-Path $client 'mss32.dll')
$bridge.sourceHashes | Add-Member -NotePropertyName 'src/mss32/smoke_waits.hpp' -NotePropertyValue '' -Force
$bridge.sourceHashes | Add-Member -NotePropertyName 'src/shared/iwd.cpp' -NotePropertyValue '' -Force
foreach ($entry in $bridge.sourceHashes.PSObject.Properties) { $entry.Value = Hash-Source (Join-Path $source $entry.Name) }
$bridge.adapterSha256 = $bridge.sourceHashes.'src/mss32/smoke_diagnostics.cpp'
$bridge | Add-Member -NotePropertyName localSourceCommit -NotePropertyValue ((& git -C $source rev-parse HEAD).Trim()) -Force
Save-Json (Join-Path $provenance 'bridge-build.json') $bridge
$component = Get-Content -LiteralPath (Join-Path $provenance 'smoke-component.json') -Raw | ConvertFrom-Json
$component.runtimeSha256 = Hash (Join-Path $runtime 'prosmoke.dll')
$component.shadersSha256 = Hash (Join-Path $runtime 'smoke.shaders')
$shaderBytes = [IO.File]::ReadAllBytes((Join-Path $runtime 'smoke.shaders'))
if ($shaderBytes.Length -lt 20 -or [BitConverter]::ToUInt32($shaderBytes, 0) -ne 0x42535350) { throw 'Invalid compiled shader bundle.' }
$component.shaderVariants = [BitConverter]::ToUInt32($shaderBytes, 16)
if ($RendererDirectory -and (Test-Path -LiteralPath (Join-Path $renderer 'manifest.json'))) {
    $rendererBuild = Get-Content -LiteralPath (Join-Path $renderer 'manifest.json') -Raw | ConvertFrom-Json
    foreach ($name in @('prosmoke.dll', 'smoke.shaders', 'noise128.rgba')) {
        if ((Hash (Join-Path $runtime $name)) -ne $rendererBuild.files.$name) { throw "Renderer manifest mismatch: $name" }
    }
    $component | Add-Member -NotePropertyName sourceCommit -NotePropertyValue $rendererBuild.sourceCommit -Force
    $component | Add-Member -NotePropertyName selectedTag -NotePropertyValue $rendererBuild.selectedTag -Force
}
Save-Json (Join-Path $provenance 'smoke-component.json') $component
$adapterText = [IO.File]::ReadAllText((Join-Path $source 'src\mss32\smoke_diagnostics.cpp'))
$versionMatch = [regex]::Match($adapterText, 'kPreviewVersion\[\]\s*=\s*"([^"]+)"')
if (-not $versionMatch.Success) { throw 'Missing preview version in bridge source.' }
Save-Json (Join-Path $runtime 'version.json') ([ordered]@{
    version = $versionMatch.Groups[1].Value
    loaderSha256 = $bridge.sha256
    runtimeSha256 = $component.runtimeSha256
    shadersSha256 = $component.shadersSha256
    shaderVariants = $component.shaderVariants
    shortWaitRequestedUs = 250
})

$requiredFiles = @('README.txt',
    'client\main\iw_prosmoke_stock.iwd',
    'client\mss32.dll', 'client\prosmoke\prosmoke.dll', 'client\prosmoke\smoke.shaders', 'client\prosmoke\noise128.rgba',
    'client\prosmoke\prosmoke_stock.iwd', 'client\prosmoke\prosmoke.cfg', 'client\prosmoke\version.json',
    'server\README-SERVER.txt', 'server\prosmoke_server.cfg', 'server\prosmoke_stock.iwd', 'server\prosmoke_competitive_full.iwd')
foreach ($required in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $package $required) -PathType Leaf)) { throw "Package is missing $required" }
}
$stray = @(Get-ChildItem -LiteralPath $package -Recurse -File | Where-Object {
    $_.FullName.Substring($package.Length + 1) -notin $requiredFiles
})
if ($stray.Count) { throw ('Unexpected files in manual-install package: ' + (($stray | ForEach-Object { $_.FullName }) -join ', ')) }

if (-not $NoZip) {
    [IO.Directory]::CreateDirectory($out) | Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = Join-Path $out 'prosmoke.zip'
    $pending = Join-Path $out ('prosmoke.' + [Guid]::NewGuid().ToString('N') + '.zip')
    [IO.Compression.ZipFile]::CreateFromDirectory($package, $pending, [IO.Compression.CompressionLevel]::Optimal, $false)
    if (Test-Path -LiteralPath $zip) { [IO.File]::Replace($pending, $zip, [NullString]::Value) } else { [IO.File]::Move($pending, $zip) }
    [IO.File]::WriteAllText(($zip + '.sha256'), (Hash $zip) + "  prosmoke.zip`n")
    Write-Output "Package: $zip"
    Write-Output ("SHA256: " + (Hash $zip))
}
