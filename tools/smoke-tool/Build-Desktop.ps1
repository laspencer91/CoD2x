[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$prebuilt = [IO.Path]::GetFullPath((Join-Path $source 'smoke/prebuilt'))
$work = Join-Path $source 'smoke/build/desktop'
[IO.Directory]::CreateDirectory($work) | Out-Null
Push-Location $PSScriptRoot
try {
    & npm.cmd ci --no-audit --no-fund
    if ($LASTEXITCODE) { throw 'Frontend dependency install failed.' }
    & npm.cmd run build:app
    if ($LASTEXITCODE) { throw 'Desktop build failed.' }
} finally { Pop-Location }

# Official Windows embeddable distribution; no Python installation or pip needed.
$version = '3.14.10'
$expected = '90905e64a840557d8c1bc4f5b74db3d7ee85e3ffb217611cac1c7813acea4159'
$archive = Join-Path $work "python-$version-embed-amd64.zip"
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest -UseBasicParsing -Uri "https://www.python.org/ftp/python/$version/python-$version-embed-amd64.zip" -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected) {
    throw 'Embedded Python download hash mismatch.'
}
$stage = Join-Path $work ('python.next.' + [Guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $archive -DestinationPath $stage
# Explicit paths keep the private interpreter independent of system Python/site packages.
[IO.File]::WriteAllText((Join-Path $stage 'python314._pth'), "python314.zip`n.`n..`n", [Text.UTF8Encoding]::new($false))
$destination = [IO.Path]::GetFullPath((Join-Path $prebuilt 'tools/smoke-bake/python'))
if (-not $destination.StartsWith($prebuilt + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Python snapshot leaves prebuilt directory.' }
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination)) | Out-Null
$unchanged = $false
if (Test-Path -LiteralPath $destination) {
    if ((Get-Item -LiteralPath $destination -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Linked Python snapshot is not supported.' }
    $current = @(Get-ChildItem -LiteralPath $destination -File)
    $fresh = @(Get-ChildItem -LiteralPath $stage -File)
    $unchanged = $current.Count -eq $fresh.Count
    foreach ($file in $fresh) {
        $existing = Join-Path $destination $file.Name
        if (-not (Test-Path -LiteralPath $existing -PathType Leaf) -or
            (Get-FileHash -LiteralPath $existing).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash) {
            $unchanged = $false
            break
        }
    }
}
if ($unchanged) {
    # Remove only this invocation's freshly extracted, hash-pinned archive staging.
    $stagePath = [IO.Path]::GetFullPath($stage)
    $workPath = [IO.Path]::GetFullPath($work)
    if (-not $stagePath.StartsWith($workPath + '\', [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetFileName($stagePath) -notmatch '^python\.next\.[a-f0-9]{32}$') { throw 'Unexpected Python staging directory.' }
    Remove-Item -LiteralPath $stagePath -Recurse -Force
} else {
    if (Test-Path -LiteralPath $destination) {
        [IO.Directory]::Move($destination, (Join-Path $work ('python.previous.' + [Guid]::NewGuid().ToString('N'))))
    }
    [IO.Directory]::Move($stage, $destination)
}
$targetRoot = Join-Path $PSScriptRoot 'src-tauri/target'
if ($env:CARGO_TARGET_DIR) {
    $targetRoot = if ([IO.Path]::IsPathRooted($env:CARGO_TARGET_DIR)) { $env:CARGO_TARGET_DIR }
        else { Join-Path $PSScriptRoot $env:CARGO_TARGET_DIR }
}
Copy-Item -LiteralPath (Join-Path $targetRoot 'release/CoD2SmokeTool.exe') -Destination (Join-Path $prebuilt 'CoD2SmokeTool.exe') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination (Join-Path $prebuilt 'DESKTOP-TOOL.txt') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src/fonts/LICENSE-LibreBaskerville.txt') -Destination (Join-Path $prebuilt 'licenses/LICENSE-LibreBaskerville.txt') -Force
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'node_modules/@fontsource/barlow/LICENSE') -Destination (Join-Path $prebuilt 'licenses/LICENSE-Barlow.txt') -Force
& python (Join-Path $PSScriptRoot 'update-snapshot.py')
if ($LASTEXITCODE) { throw 'Snapshot manifest update failed.' }
Write-Output 'Portable desktop snapshot updated. Run smoke/Package-Test.ps1 to assemble the ZIP.'
