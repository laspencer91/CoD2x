# Volumetric Smoke System by Logan - contact at logan@loganspencer.dev
# Copyright (c) 2026 Logan Spencer. GPL-3.0 + supplied licenses/smoke/NOTICE.md.
[CmdletBinding()]
param(
    [ValidateSet('Try', 'Install', 'Launch', 'Uninstall', 'Verify', 'Inspect')] [string]$Action = 'Install',
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
            throw "Game folders using links or junctions are not supported: $cursor"
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

function Get-SteamDirectories([string]$Game) {
    # A Steam library may be on a different drive from the Steam client.
    for ($folder = Get-Item -LiteralPath $Game; $null -ne $folder; $folder = $folder.Parent) {
        if ($folder.Name -eq 'steamapps' -and $folder.Parent) { $folder.Parent.FullName }
    }
    foreach ($entry in @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'InstallPath'),
        @('HKLM:\SOFTWARE\Valve\Steam', 'InstallPath')
    )) {
        try { Get-ItemPropertyValue -LiteralPath $entry[0] -Name $entry[1] -ErrorAction Stop } catch { }
    }
    Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam'
}

function Find-SteamDirectory([string]$Game) {
    foreach ($candidate in @(Get-SteamDirectories $Game)) {
        if (-not [IO.Path]::IsPathRooted($candidate)) { continue }
        $directory = [IO.Path]::GetFullPath($candidate)
        if ((Test-Path -LiteralPath (Join-Path $directory 'steam.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $directory 'Steam.dll') -PathType Leaf)) { return $directory }
    }
    if (($Game -split '[/\\]') -contains 'steamapps') {
        throw 'Steam client files could not be found. Open Steam on this PC, repair its installation if needed, then retry Try smoke.'
    }
    return $null
}

function Test-CoD2xLoader([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ([Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductName -eq 'CoD2x') { return $true }
    # Some upstream/MinGW builds have no readable product-version strings.
    # Recognize their original-library loader and its specific CoD2x error text.
    $data = [IO.File]::ReadAllBytes($Path)
    if ($data.Length -lt 64 -or $data[0] -ne 0x4d -or $data[1] -ne 0x5a) { return $false }
    $text = [Text.Encoding]::ASCII.GetString($data)
    return $text.Contains('mss32_original.dll') -and $text.Contains('CoD2x is not installed correctly.')
}

function Get-CoD2xStatus([string]$Game) {
    if (-not (Test-CoD2xLoader (Safe-Path $Game 'mss32.dll'))) {
        return [ordered]@{ ready = $false; message = 'CoD2x is not installed in this folder. Install CoD2x first, then click Recheck.' }
    }
    $original = Safe-Path $Game 'mss32_original.dll'
    if (-not (Test-Path -LiteralPath $original -PathType Leaf)) {
        return [ordered]@{ ready = $false; message = 'CoD2x installation is incomplete: mss32_original.dll is missing. Reinstall CoD2x, then click Recheck.' }
    }
    $bridge = Get-Content -LiteralPath (Join-Path $bundle 'provenance/bridge-build.json') -Raw | ConvertFrom-Json
    if ($bridge.originalMss32Sha256 -notmatch '^[a-f0-9]{64}$') { throw 'The bundle is missing its CoD2x sound-library compatibility hash. Extract the updated ZIP.' }
    if ((File-Hash $original) -ne $bridge.originalMss32Sha256) {
        return [ordered]@{ ready = $false; message = 'CoD2x sound library is not the supported version. Reinstall CoD2x, then click Recheck.' }
    }
    return [ordered]@{ ready = $true; message = 'CoD2x detected. Your current client will be backed up before smoke is installed.' }
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

function Assert-OwnedFiles([string]$Game, $Receipt, [switch]$Reinstall) {
    foreach ($file in $Receipt.files) {
        $hash = File-Hash (Safe-Path $Game $file.path)
        if ($null -ne $hash -and $hash -ne $file.installedHash) {
            # A normal CoD2x install/update can replace the smoke loader between runs.
            # Reinstall saves that client as the new restoration baseline below.
            if ($Reinstall -and $file.path -eq 'mss32.dll') { continue }
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
            $picker.Title = 'Select your CoD2MP_s.exe'
            $picker.Filter = 'Call of Duty 2 Multiplayer|CoD2MP_s.exe'
            if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { Write-Output 'Cancelled.'; exit 0 }
            $GameDirectory = [IO.Path]::GetDirectoryName($picker.FileName)
        } finally { $picker.Dispose() }
    }
    $game = [IO.Path]::GetFullPath($GameDirectory).TrimEnd('\')
    if (-not (Test-Path -LiteralPath (Safe-Path $game 'CoD2MP_s.exe') -PathType Leaf)) { throw 'Choose the game folder containing CoD2MP_s.exe.' }
    if ($Action -eq 'Inspect') {
        Get-CoD2xStatus $game | ConvertTo-Json -Compress
        exit 0
    }
    if ($Action -in @('Try', 'Install', 'Launch', 'Verify')) {
        $clientStatus = Get-CoD2xStatus $game
        if (-not $clientStatus.ready) { throw $clientStatus.message }
    }
    $receipt = Read-Receipt $game
    $receiptPath = Safe-Path $game $receiptName

    if ($Action -eq 'Try') {
        # Check launch conflicts before replacing anything in the normal game folder.
        Assert-Stopped -Launching
        $null = Find-SteamDirectory $game
        $next = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath,
            '-GameDirectory', $game, '-Map', $Map, '-Look', $Look)
        if ($CheckOnly) {
            & (Join-Path $PSHOME 'powershell.exe') @next -Action Install -CheckOnly
            if ($LASTEXITCODE) { throw 'Compatibility checks failed. No game files were changed.' }
            Write-Output 'Ready to try smoke: install with backups, then launch the selected map.'
            exit 0
        }
        & (Join-Path $PSHOME 'powershell.exe') @next -Action Install
        if ($LASTEXITCODE) { throw 'Smoke installation failed; see the preceding error.' }
        & (Join-Path $PSHOME 'powershell.exe') @next -Action Launch
        if ($LASTEXITCODE) { throw 'Smoke is installed, but the game could not start. Retry Try smoke, or choose Restore original files.' }
        exit 0
    }

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
        if (-not $receipt) { throw 'Smoke is not installed. Click Try smoke first, or run Setup-Smoke-Test.cmd.' }
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
        $steamDirectory = Find-SteamDirectory $game
        $saved = @{}
        foreach ($key in @('PATH', 'COD2_SMOKE_DIAGNOSTICS', 'COD2_SMOKE_RENDER', 'COD2_SMOKE_DEV', 'COD2_SMOKE_LOG')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process') }
        try {
            $env:COD2_SMOKE_DIAGNOSTICS = '1'; $env:COD2_SMOKE_RENDER = '1'
            $env:COD2_SMOKE_DEV = $null; $env:COD2_SMOKE_LOG = $null
            if ($steamDirectory) {
                $env:PATH = $steamDirectory + [IO.Path]::PathSeparator + $saved['PATH']
                Write-Output "Steam client directory added to the game's DLL search path: $steamDirectory"
            }
            Start-Process -FilePath (Safe-Path $game 'CoD2MP_s.exe') -WorkingDirectory $game -ArgumentList $arguments -WindowStyle Normal | Out-Null
        } finally {
            foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
        }
        Write-Output "Requested CoD2 startup on $Map. If the game reports a Steam error, confirm Steam is open and signed in."
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
    if ($receipt) { Assert-OwnedFiles $game $receipt -Reinstall }
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
            $updatedLoader = $file.path -eq 'mss32.dll' -and $entries.ContainsKey($file.path) -and
                $null -ne $originals[$target] -and (File-Hash $target) -ne $entries[$file.path].installedHash
            if (-not $entries.ContainsKey($file.path) -or $updatedLoader) {
                $backup = $null; $originalHash = $null
                if ($null -ne $originals[$target]) {
                    $backup = $backupPrefix + '/' + $file.path
                    Write-Atomic (Safe-Path $game $backup) $originals[$target]
                    $originalHash = File-Hash (Safe-Path $game $backup)
                }
                if ($updatedLoader) {
                    Write-Atomic (Safe-Path $game ($backupPrefix + '/previous-install.json')) ([IO.File]::ReadAllBytes($receiptPath))
                    Write-Output 'Preserved the updated CoD2x loader. Restore original files will return this client; earlier backups are retained.'
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
    Write-Output 'Smoke is ready. Use Try smoke or Launch installed to play; Restore original files reverses setup.'
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
