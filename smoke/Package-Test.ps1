[CmdletBinding()]
param([string]$BridgeDll)
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
foreach ($entry in $manifest.files.PSObject.Properties) {
    $path = [IO.Path]::GetFullPath((Join-Path $prebuilt $entry.Name))
    if (-not $path.StartsWith($prebuilt + '\', [StringComparison]::OrdinalIgnoreCase) -or (Hash $path) -ne $entry.Value.sha256) {
        throw "Prebuilt input hash/path mismatch: $($entry.Name)"
    }
}
$stage = In-Output (Join-Path $out ('package.next.' + [Guid]::NewGuid().ToString('N')))
[IO.Directory]::CreateDirectory($stage) | Out-Null
foreach ($entry in $manifest.files.PSObject.Properties) {
    $target = In-Output (Join-Path $stage $entry.Name)
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $prebuilt $entry.Name) -Destination $target
}
$toolFiles = @('bake.py', 'Bake-Smoke.cmd', 'README.md', 'bin/cod2smoke-bake.exe', 'bin/cod2smoke-bake.json',
    'cod2kit/__init__.py', 'cod2kit/bsp.py', 'cod2kit/maptext.py', 'cod2kit/smoke_geometry.py',
    'cod2kit/smoke_collision.py', 'cod2kit/brushes.py', 'cod2kit/definitions.py', 'cod2kit/files.py', 'cod2kit/smoke_bake.py')
foreach ($name in $toolFiles) {
    $target = In-Output (Join-Path $stage ('tools/smoke-bake/' + $name))
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $source ('tools/smoke-bake/' + $name)) -Destination $target
}
Copy-Item -LiteralPath $BridgeDll -Destination (Join-Path $stage 'runtime\mss32.dll') -Force
$buildInfo = Get-Content -LiteralPath (Join-Path $stage 'provenance\bridge-build.json') -Raw | ConvertFrom-Json
$buildInfo.sha256 = Hash (Join-Path $stage 'runtime\mss32.dll')
if ($rebuilt) {
    foreach ($entry in $buildInfo.sourceHashes.PSObject.Properties) { $entry.Value = Hash-Source (Join-Path $source $entry.Name) }
}
$buildInfo | Add-Member -NotePropertyName localSourceCommit -NotePropertyValue ((& git -C $source rev-parse HEAD).Trim()) -Force
Save-Json (Join-Path $stage 'provenance\bridge-build.json') $buildInfo
$files = [ordered]@{}
foreach ($file in Get-ChildItem -LiteralPath $stage -File -Recurse | Sort-Object FullName) {
    $name = $file.FullName.Substring($stage.Length + 1).Replace('\', '/')
    if ($name -in @('manifest.json', 'SHA256SUMS.txt')) { continue }
    if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked package input: $name" }
    $files[$name] = [ordered]@{ bytes = $file.Length; sha256 = Hash $file.FullName }
}
$manifest.files = $files
Save-Json (Join-Path $stage 'manifest.json') $manifest
$sums = @($files.Keys | ForEach-Object { "$($files[$_].sha256)  $_" })
$sums += "$(Hash (Join-Path $stage 'manifest.json'))  manifest.json"
[IO.File]::WriteAllText((Join-Path $stage 'SHA256SUMS.txt'), ($sums -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
$package = In-Output (Join-Path $out 'package')
if (Test-Path -LiteralPath $package) {
    $previous = In-Output (Join-Path $out ('package.previous.' + [DateTime]::UtcNow.Ticks))
    [IO.Directory]::Move($package, $previous)
}
[IO.Directory]::Move($stage, $package)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = In-Output (Join-Path $out 'cod2x-smoke-test.zip')
$pending = In-Output (Join-Path $out ('cod2x-smoke-test.next.' + [Guid]::NewGuid().ToString('N') + '.zip'))
[IO.Compression.ZipFile]::CreateFromDirectory($package, $pending, [IO.Compression.CompressionLevel]::Optimal, $false)
if (Test-Path -LiteralPath $zip) { [IO.File]::Replace($pending, $zip, [NullString]::Value) }
else { [IO.File]::Move($pending, $zip) }
[IO.File]::WriteAllText(($zip + '.sha256'), (Hash $zip) + "`n")
Write-Output "Test package: $package"
Write-Output "Test ZIP: $zip"
