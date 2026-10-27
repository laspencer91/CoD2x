# Volumetric Smoke System by Logan - contact at logan@loganspencer.dev
# Copyright (c) 2026 Logan Spencer. GPL-3.0 + supplied licenses/smoke/NOTICE.md.
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Launch', 'Uninstall', 'Verify')] [string]$Action = 'Install',
    [string]$GameDirectory,
    [ValidatePattern('^mp_[a-z0-9_]{1,28}$')] [string]$Map = 'mp_toujane',
    [ValidateSet('wide', 'wide_fx', 'lively', 'warm', 'soft')] [string]$Look = 'wide',
    [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$bundle = $PSScriptRoot
$receiptName = 'cod2-smoke-test-install.json'
$settingsPath = Join-Path $bundle 'test-installation.json'

function Safe-Path([string]$Root, [string]$Relative) {
    if ($Relative -notmatch '^[A-Za-z0-9_./-]+$' -or
        @($Relative -split '[/\\]' | Where-Object { $_ -in @('', '.', '..') }).Count) {
        throw "Invalid package path: $Relative"
    }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $target = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $target.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path leaves its target directory: $Relative"
    }
    $cursor = $base
    foreach ($part in ($Relative -split '[/\\]')) {
        if ((Test-Path -LiteralPath $cursor) -and
            ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Use a test folder without links or junctions: $cursor"
        }
        $cursor = Join-Path $cursor $part
    }
    if ((Test-Path -LiteralPath $target) -and
        ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Refusing to replace a link: $target"
    }
    return $target
}

function File-Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-RuntimePath([string]$Relative) {
    if ($Relative -ne 'mss32.dll' -and -not $Relative.StartsWith('mapkit-smoke/') -and -not $Relative.StartsWith('mapkit_smoke_test/')) {
        throw "Unexpected runtime destination: $Relative"
    }
}

function Write-Atomic([string]$Path, [byte[]]$Data) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $pending = $Path + '.next.' + [Guid]::NewGuid().ToString('N')
    try {
        [IO.File]::WriteAllBytes($pending, $Data)
        if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($pending, $Path, [NullString]::Value) }
        else { [IO.File]::Move($pending, $Path) }
    } finally {
        if (Test-Path -LiteralPath $pending) { Remove-Item -LiteralPath $pending -Force }
    }
}

function Write-Json([string]$Path, $Value) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 10))
    Write-Atomic $Path $bytes
}

function Assert-Stopped([switch]$Launching) {
    # Windows can keep exited game entries visible while another process holds a handle.
    if (-not ('MapkitSmoke.ProcessState' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace MapkitSmoke {
    public static class ProcessState {
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetExitCodeProcess(IntPtr process, out uint code);
        [DllImport("kernel32.dll")]
        static extern bool CloseHandle(IntPtr handle);
        public static bool IsRunning(uint pid) {
            IntPtr handle = OpenProcess(0x1000, false, pid);
            if (handle == IntPtr.Zero) {
                int error = Marshal.GetLastWin32Error();
                if (error == 87) return false;
                throw new Win32Exception(error);
            }
            try {
                uint code;
                if (!GetExitCodeProcess(handle, out code)) throw new Win32Exception(Marshal.GetLastWin32Error());
                return code == 259;
            } finally { CloseHandle(handle); }
        }
    }
}
'@
    }
    $names = @('cod2mp_s.exe')
    if ($Launching) { $names += @('iw3mp.exe', 'iw3sp.exe', 'h1-mod.exe', 'h1_mp64_ship.exe', 'h1_sp64_ship.exe', 'cod4x18_dedrun.exe') }
    $filter = ($names | ForEach-Object { "Name='$_'" }) -join ' OR '
    $running = @(Get-CimInstance Win32_Process -Filter $filter | Where-Object { [MapkitSmoke.ProcessState]::IsRunning($_.ProcessId) })
    if ($running.Count) { throw ('Close these games before continuing: ' + (($running | ForEach-Object { "$($_.Name) ($($_.ProcessId))" }) -join ', ')) }
}

function Read-Receipt([string]$Game) {
    $path = Safe-Path $Game $receiptName
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $receipt = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($receipt.schema -ne 1 -or $receipt.gameDirectory -ne $Game) { throw 'Installation receipt does not match this game folder.' }
    $seen = @{}
    foreach ($file in $receipt.files) {
        Assert-RuntimePath $file.path
        Safe-Path $Game $file.path | Out-Null
        if ($seen.ContainsKey($file.path) -or $file.installedHash -notmatch '^[a-f0-9]{64}$') { throw 'Invalid installation receipt.' }
        $seen[$file.path] = $true
        if ($null -ne $file.backup) {
            if (-not $file.backup.StartsWith('cod2-smoke-test-backups/') -or $file.originalHash -notmatch '^[a-f0-9]{64}$') { throw 'Invalid backup location/hash.' }
            $backup = Safe-Path $Game $file.backup
            if ((File-Hash $backup) -ne $file.originalHash) { throw "Backup is missing or changed: $($file.path)" }
        }
    }
    return $receipt
}

function Assert-OwnedFiles([string]$Game, $Receipt) {
    foreach ($file in $Receipt.files) {
        $hash = File-Hash (Safe-Path $Game $file.path)
        if ($null -ne $hash -and $hash -ne $file.installedHash) {
            throw "Installed file changed since setup: $($file.path). Preserve that change before reinstalling or uninstalling."
        }
    }
}

function Restore-Changes($Changed, $Originals) {
    $errors = @()
    for ($i = $Changed.Count - 1; $i -ge 0; --$i) {
        $path = $Changed[$i]
        try {
            if ($null -eq $Originals[$path]) { Remove-Item -LiteralPath $path -Force }
            else { Write-Atomic $path $Originals[$path] }
        } catch { $errors += "$path : $($_.Exception.Message)" }
    }
    if ($errors.Count) { throw ('Rollback incomplete; retain the backups. ' + ($errors -join '; ')) }
}

try {
    if (-not $GameDirectory -and $Action -ne 'Install' -and (Test-Path -LiteralPath $settingsPath)) {
        $GameDirectory = (Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).gameDirectory
    }
    if (-not $GameDirectory) {
        Add-Type -AssemblyName System.Windows.Forms
        $picker = New-Object System.Windows.Forms.OpenFileDialog
        try {
            $picker.Title = 'Select CoD2MP_s.exe in a separate CoD2 test copy'
            $picker.Filter = 'Call of Duty 2 Multiplayer|CoD2MP_s.exe'
            if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { Write-Output 'Cancelled.'; exit 0 }
            $GameDirectory = [IO.Path]::GetDirectoryName($picker.FileName)
        } finally { $picker.Dispose() }
    }
    $game = [IO.Path]::GetFullPath($GameDirectory).TrimEnd('\')
    if ($game -match '(?i)(^|[\\/])steamapps([\\/]|$)') { throw 'Choose a separate test copy outside the Steam library, for example C:\Games\CoD2-Smoke-Test.' }
    if (-not (Test-Path -LiteralPath (Safe-Path $game 'CoD2MP_s.exe') -PathType Leaf)) { throw 'Choose the game folder containing CoD2MP_s.exe.' }
    $receipt = Read-Receipt $game
    $receiptPath = Safe-Path $game $receiptName

    if ($Action -eq 'Uninstall') {
        if (-not $receipt) { throw 'No smoke test installation was recorded in this folder.' }
        Assert-OwnedFiles $game $receipt
        if ($CheckOnly) { Write-Output 'Uninstall checks passed; no files changed.'; exit 0 }
        Assert-Stopped
        $originals = @{}; $changed = New-Object 'System.Collections.Generic.List[string]'
        try {
            foreach ($file in $receipt.files) {
                $target = Safe-Path $game $file.path
                $originals[$target] = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllBytes($target) } else { $null }
                if ($null -ne $file.backup) { Write-Atomic $target ([IO.File]::ReadAllBytes((Safe-Path $game $file.backup))) }
                elseif (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
                else { continue }
                $changed.Add($target)
            }
            Remove-Item -LiteralPath $receiptPath -Force
        } catch { $problem = $_; Restore-Changes $changed $originals; throw $problem }
        Write-Output 'Smoke test removed and original files restored. Backups and game-created logs/configs are retained.'
        exit 0
    }

    if ($Action -in @('Launch', 'Verify')) {
        if (-not $receipt) { throw 'Run Setup-Smoke-Test.cmd first.' }
        foreach ($file in $receipt.files) {
            if ((File-Hash (Safe-Path $game $file.path)) -ne $file.installedHash) { throw "Installed file is missing or changed: $($file.path)" }
        }
        if ((File-Hash (Safe-Path $game 'gfx_d3d_mp_x86_s.dll')) -ne $receipt.rendererHash) { throw 'The installed game renderer differs from the tested DX9 version.' }
        $quotedGame = '"' + $game + '"'
        $arguments = @('+set', 'fs_basepath', $quotedGame, '+set', 'fs_homepath', $quotedGame,
            '+set', 'fs_game', 'mapkit_smoke_test', '+set', 'sv_punkbuster', '0', '+set', 'cl_punkbuster', '0',
            '+set', 'sv_pure', '0', '+set', 'net_ip', '127.0.0.1', '+set', 'r_rendererPreference', 'dx9',
            '+set', 'r_fullscreen', '0', '+set', 'g_gametype', 'tdm', '+exec', "smoke_look_$Look.cfg", '+devmap', $Map)
        if ($CheckOnly -or $Action -eq 'Verify') { Write-Output ('Installed files verified. Launch arguments: ' + ($arguments -join ' ')); exit 0 }
        Assert-Stopped -Launching
        $saved = @{}
        foreach ($key in @('COD2_SMOKE_DIAGNOSTICS', 'COD2_SMOKE_RENDER', 'COD2_SMOKE_DEV', 'COD2_SMOKE_LOG')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
        try {
            $env:COD2_SMOKE_DIAGNOSTICS = '1'; $env:COD2_SMOKE_RENDER = '1'
            $env:COD2_SMOKE_DEV = $null; $env:COD2_SMOKE_LOG = $null
            Start-Process -FilePath (Safe-Path $game 'CoD2MP_s.exe') -WorkingDirectory $game -ArgumentList $arguments -WindowStyle Normal | Out-Null
        } finally {
            foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
        }
        Write-Output "Started smoke test on $Map."
        exit 0
    }

    $manifest = Get-Content -LiteralPath (Join-Path $bundle 'manifest.json') -Raw | ConvertFrom-Json
    $bridge = Get-Content -LiteralPath (Join-Path $bundle 'provenance/bridge-build.json') -Raw | ConvertFrom-Json
    if ($bridge.rendererSha256 -notmatch '^[a-f0-9]{64}$' -or (File-Hash (Safe-Path $game 'gfx_d3d_mp_x86_s.dll')) -ne $bridge.rendererSha256) { throw 'Unsupported DX9 renderer. No game files were changed.' }
    $payload = @(); $seen = @{}
    foreach ($item in $manifest.files.PSObject.Properties) {
        if (-not $item.Name.StartsWith('runtime/')) { continue }
        $relative = $item.Name.Substring(8)
        Assert-RuntimePath $relative
        if ($seen.ContainsKey($relative)) { throw "Duplicate runtime destination: $relative" }
        $seen[$relative] = $true
        $source = Safe-Path $bundle $item.Name
        Safe-Path $game $relative | Out-Null
        if ($item.Value.sha256 -notmatch '^[a-f0-9]{64}$' -or (File-Hash $source) -ne $item.Value.sha256 -or
            (Get-Item -LiteralPath $source).Length -ne $item.Value.bytes) { throw "Package file is missing or corrupt: $($item.Name)" }
        $payload += [pscustomobject]@{ path = $relative; source = $source; hash = $item.Value.sha256 }
    }
    foreach ($required in @('mss32.dll', 'mapkit-smoke/mapkit_smoke.dll', 'mapkit-smoke/noise128.rgba',
        'mapkit_smoke_test/mapkit_smoke_stock.iwd', 'mapkit_smoke_test/smoke_look_wide.cfg')) {
        if (-not $seen.ContainsKey($required)) { throw "Package is missing a required file: $required" }
    }
    if (-not $seen.ContainsKey('mapkit-smoke/smoke.shaders') -and -not $seen.ContainsKey('mapkit-smoke/smoke.hlsl')) {
        throw 'Package is missing compiled shaders or a development shader source.'
    }
    if ($receipt) { Assert-OwnedFiles $game $receipt }
    if ($CheckOnly) { Write-Output "Setup checks passed for $($payload.Count) files; no files changed."; exit 0 }
    Assert-Stopped
    $backupPrefix = 'cod2-smoke-test-backups/' + [Guid]::NewGuid().ToString('N')
    $entries = @{}; $originals = @{}; $changed = New-Object 'System.Collections.Generic.List[string]'
    if ($receipt) { foreach ($file in $receipt.files) { $entries[$file.path] = $file } }
    try {
        foreach ($file in $payload) {
            $target = Safe-Path $game $file.path
            $data = [IO.File]::ReadAllBytes($file.source)
            $originals[$target] = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllBytes($target) } else { $null }
            if (-not $entries.ContainsKey($file.path)) {
                $backup = $null; $originalHash = $null
                if ($null -ne $originals[$target]) {
                    $originalHash = File-Hash $target; $backup = $backupPrefix + '/' + $file.path
                    Write-Atomic (Safe-Path $game $backup) $originals[$target]
                }
                $entries[$file.path] = [pscustomobject]@{ path = $file.path; backup = $backup; originalHash = $originalHash; installedHash = $file.hash }
            } else { $entries[$file.path].installedHash = $file.hash }
            Write-Atomic $target $data
            $changed.Add($target)
            if ((File-Hash $target) -ne $file.hash) { throw "Copy verification failed: $($file.path)" }
        }
        Write-Json $receiptPath ([ordered]@{ schema = 1; gameDirectory = $game; rendererHash = $bridge.rendererSha256; files = @($entries.Values | Sort-Object path) })
    } catch { $problem = $_; Restore-Changes $changed $originals; throw $problem }
    try { Write-Json $settingsPath @{ gameDirectory = $game } }
    catch { Write-Warning "Installed, but could not remember the folder. Pass -GameDirectory `"$game`" when starting." }
    Write-Output "Installed and verified $($payload.Count) files in $game"
    Write-Output 'Next: double-click Start-Smoke-Test.cmd. Uninstall-Smoke-Test.cmd restores the original files.'
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
