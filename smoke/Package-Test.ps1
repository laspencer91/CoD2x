[CmdletBinding()]
param([string]$BridgeDll, [switch]$KeepExpanded, [switch]$PlayerOnly)
$ErrorActionPreference = 'Stop'
$rebuilt = $PSBoundParameters.ContainsKey('BridgeDll')
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$prebuilt = Join-Path $PSScriptRoot 'prebuilt'
if (-not $BridgeDll) { $BridgeDll = Join-Path $prebuilt 'runtime\mss32.dll' }
$BridgeDll = (Resolve-Path -LiteralPath $BridgeDll).Path
$out = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'out'))
[IO.Directory]::CreateDirectory($out) | Out-Null
if ((Get-Item -LiteralPath $out -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked smoke/out directory is not supported.' }
function In-Output([string]$Path) {
    $resolved = [IO.Path]::GetFullPath($Path)
    if (-not $resolved.StartsWith($out + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Package output leaves smoke/out.' }
    if ((Test-Path -LiteralPath $resolved) -and ((Get-Item -LiteralPath $resolved -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Linked package output is not supported.'
    }
    return $resolved
}
function Hash([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Remove-NewStage([string]$Path) {
    $target = In-Output $Path
    if ($target -ne $stage -or [IO.Path]::GetFileName($target) -notmatch '^package\.next\.[a-f0-9]{32}$') {
        throw "Only this invocation's freshly created staging directory can be removed."
    }
    $links = @(Get-ChildItem -LiteralPath $target -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
    if ($links.Count) { throw "Refusing to remove linked generated output: $target" }
    Remove-Item -LiteralPath $target -Recurse -Force
}
function Hash-Source([string]$Path) {
    $hash = [Security.Cryptography.SHA256]::Create()
    try {
        $text = [IO.File]::ReadAllText($Path).Replace("`r`n", "`n")
        return [BitConverter]::ToString($hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-', '').ToLowerInvariant()
    } finally { $hash.Dispose() }
}
function Save-Json([string]$Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12) + "`n", [Text.UTF8Encoding]::new($false))
}
$manifest = Get-Content -LiteralPath (Join-Path $prebuilt 'manifest.json') -Raw | ConvertFrom-Json
$playerFiles = @(
    'CoD2SmokeTool.exe', 'Smoke-Test.ps1', 'provenance/bridge-build.json',
    'runtime/mss32.dll', 'runtime/mapkit-smoke/mapkit_smoke.dll',
    'runtime/mapkit-smoke/noise128.rgba', 'runtime/mapkit-smoke/smoke.shaders',
    'runtime/mapkit_smoke_test/mapkit_smoke_stock.iwd',
    'runtime/mapkit_smoke_test/smoke_look_wide.cfg'
)
if ($PlayerOnly) {
    foreach ($name in $playerFiles) {
        if (-not $manifest.files.PSObject.Properties[$name]) { throw "Missing player package input: $name" }
    }
}
foreach ($entry in $manifest.files.PSObject.Properties) {
    $path = [IO.Path]::GetFullPath((Join-Path $prebuilt $entry.Name))
    if (-not $path.StartsWith($prebuilt + '\', [StringComparison]::OrdinalIgnoreCase) -or (Hash $path) -ne $entry.Value.sha256) {
        throw "Prebuilt input hash/path mismatch: $($entry.Name)"
    }
}
$stage = In-Output (Join-Path $out ('package.next.' + [Guid]::NewGuid().ToString('N')))
[IO.Directory]::CreateDirectory($stage) | Out-Null
foreach ($entry in $manifest.files.PSObject.Properties) {
    if ($PlayerOnly -and $entry.Name -notin $playerFiles -and -not $entry.Name.StartsWith('licenses/')) { continue }
    $target = In-Output (Join-Path $stage $entry.Name)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $prebuilt $entry.Name) -Destination $target
}
$toolFiles = @('bake.py', 'Bake-Smoke.cmd', 'README.md', 'bin/cod2smoke-bake.exe', 'bin/cod2smoke-bake.json',
    'cod2kit/__init__.py', 'cod2kit/bsp.py', 'cod2kit/maptext.py', 'cod2kit/smoke_geometry.py',
    'cod2kit/smoke_collision.py', 'cod2kit/brushes.py', 'cod2kit/definitions.py', 'cod2kit/files.py', 'cod2kit/smoke_bake.py')
foreach ($name in $(if (-not $PlayerOnly) { $toolFiles })) {
    $target = In-Output (Join-Path $stage ('tools/smoke-bake/' + $name))
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $source ('tools/smoke-bake/' + $name)) -Destination $target
}
if ($PlayerOnly) {
    Copy-Item -LiteralPath (Join-Path $source 'tools/smoke-tool/PLAYER-README.txt') -Destination (Join-Path $stage 'READ-ME-FIRST.txt') -Force
}
Copy-Item -LiteralPath $BridgeDll -Destination (Join-Path $stage 'runtime\mss32.dll') -Force
$buildInfo = Get-Content -LiteralPath (Join-Path $stage 'provenance\bridge-build.json') -Raw | ConvertFrom-Json
if ($PlayerOnly) {
    if ($buildInfo.rendererSha256 -notmatch '^[a-f0-9]{64}$') { throw 'Missing supported renderer hash.' }
    $buildInfo = [ordered]@{ rendererSha256 = $buildInfo.rendererSha256 }
} else {
    $buildInfo.sha256 = Hash (Join-Path $stage 'runtime\mss32.dll')
    if ($rebuilt) {
        foreach ($entry in $buildInfo.sourceHashes.PSObject.Properties) { $entry.Value = Hash-Source (Join-Path $source $entry.Name) }
    }
    $buildInfo | Add-Member -NotePropertyName localSourceCommit -NotePropertyValue ((& git -C $source rev-parse HEAD).Trim()) -Force
}
Save-Json (Join-Path $stage 'provenance\bridge-build.json') $buildInfo
$files = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName) {
    $name = $file.FullName.Substring($stage.Length + 1).Replace('\', '/')
    if ($name -in @('manifest.json', 'SHA256SUMS.txt')) { continue }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked package input: $name" }
    $files[$name] = [ordered]@{ bytes = $file.Length; sha256 = Hash $file.FullName }
}
if ($PlayerOnly) {
    $manifest = [ordered]@{ schema = 1; purpose = 'cod2-smoke-player-preview'; releaseReady = $false; stockMaps = 15; authoringIncluded = $false; files = $files }
} else {
    $manifest.files = $files
    $manifest | Add-Member -NotePropertyName authoringIncluded -NotePropertyValue $true -Force
}
Save-Json (Join-Path $stage 'manifest.json') $manifest
$sums = @($files.Keys | ForEach-Object { "$($files[$_].sha256)  $_" })
$sums += "$(Hash (Join-Path $stage 'manifest.json'))  manifest.json"
[IO.File]::WriteAllText((Join-Path $stage 'SHA256SUMS.txt'), ($sums -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
Add-Type -AssemblyName System.IO.Compression.FileSystem
$stem = if ($PlayerOnly) { 'cod2x-smoke-player' } else { 'cod2x-smoke-test' }
$zip = In-Output (Join-Path $out ($stem + '.zip'))
$pending = In-Output (Join-Path $out ($stem + '.next.' + [Guid]::NewGuid().ToString('N') + '.zip'))
[IO.Compression.ZipFile]::CreateFromDirectory($stage, $pending, [IO.Compression.CompressionLevel]::Optimal, $false)
if (Test-Path -LiteralPath $zip) { [IO.File]::Replace($pending, $zip, [NullString]::Value) }
else { [IO.File]::Move($pending, $zip) }
[IO.File]::WriteAllText(($zip + '.sha256'), (Hash $zip) + "`n")
if ($KeepExpanded) {
    $folder = if ($PlayerOnly) { 'player' } else { 'package' }
    $package = In-Output (Join-Path $out $folder)
    $previous = $null
    if (Test-Path -LiteralPath $package) {
        $previous = In-Output (Join-Path $out ($folder + '.previous.' + [DateTime]::UtcNow.Ticks))
        [IO.Directory]::Move($package, $previous)
    }
    [IO.Directory]::Move($stage, $package)
    # Expanded output is explicitly requested; preserve its previous copy for recovery.
    Write-Output "Expanded test package: $package"
} else { Remove-NewStage $stage }
Write-Output "Test ZIP: $zip"
