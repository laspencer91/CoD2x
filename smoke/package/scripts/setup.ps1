# ProSmoke client setup for Call of Duty 2 with CoD2x.
# Double-click Setup-Client.cmd, Undo-Client.cmd or Play-Local.cmd next to this folder;
# they run this script. Nothing here downloads or uploads anything.
[CmdletBinding()]
param(
    [ValidateSet('Install', 'Undo', 'Play', 'Check')] [string]$Action = 'Install',
    [string]$GameDirectory,
    [switch]$NoPrompt,   # automation: never open a dialog; uses -GameDirectory or the one detected game folder
    [switch]$DryRun,     # Play: print the launch command instead of starting the game
    [ValidatePattern('^mp_[a-z0-9_]{1,28}$')] [string]$Map = 'mp_toujane'
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$package = Split-Path -Parent $PSScriptRoot                  # the extracted ZIP root
$payload = Join-Path $package 'client\prosmoke'              # files that land in <game>\prosmoke
$packageLoader = Join-Path $package 'client\mss32.dll'        # the ProSmoke CoD2x loader
$backupName = 'prosmoke-backup'
$localData = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { [Environment]::GetFolderPath('LocalApplicationData') }
$stateDirectory = Join-Path $localData 'prosmoke'
$rememberedPath = Join-Path $stateDirectory 'game-directory.txt'

function Say([string]$Text) { Write-Host $Text }
function File-Hash([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Test-CoD2xLoader([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ([Diagnostics.FileVersionInfo]::GetVersionInfo($Path).ProductName -eq 'CoD2x') { return $true }
    $data = [IO.File]::ReadAllBytes($Path)
    if ($data.Length -lt 64 -or $data[0] -ne 0x4d -or $data[1] -ne 0x5a) { return $false }
    $text = [Text.Encoding]::ASCII.GetString($data)
    return $text.Contains('mss32_original.dll') -and $text.Contains('CoD2x is not installed correctly.')
}
function Test-ProSmokeLoader([string]$Path) {
    # Any ProSmoke build of the loader carries the policy cvar name; stock CoD2x loaders do not.
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    return [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($Path)).Contains('sv_prosmoke_policy')
}
function Test-GameFolder([string]$Path) {
    return $Path -and (Test-Path -LiteralPath (Join-Path $Path 'CoD2MP_s.exe') -PathType Leaf)
}
function Registry-Value([string]$Key, [string]$Name) {
    try { return Get-ItemPropertyValue -LiteralPath $Key -Name $Name -ErrorAction Stop } catch { return $null }
}
function Quoted-Pairs([string]$Text) {
    # Steam VDF/ACF files: "key"  "value" lines.
    $pairs = @{}
    foreach ($match in [regex]::Matches($Text, '"([^"]+)"\s+"([^"]+)"')) { $pairs[$match.Groups[1].Value] = $match.Groups[2].Value }
    return $pairs
}
function Find-GameFolders {
    $found = New-Object System.Collections.Generic.List[string]
    $add = { param($candidate) if ($candidate -and (Test-GameFolder $candidate)) {
        $full = [IO.Path]::GetFullPath($candidate).TrimEnd('\')
        if (-not ($found | Where-Object { $_ -ieq $full })) { $found.Add($full) } } }
    if (Test-Path -LiteralPath $rememberedPath) { & $add ((Get-Content -LiteralPath $rememberedPath -Raw).Trim()) }
    foreach ($key in @('HKLM:\SOFTWARE\Activision\Call of Duty 2', 'HKLM:\SOFTWARE\WOW6432Node\Activision\Call of Duty 2')) {
        & $add (Registry-Value $key 'InstallPath')
    }
    $libraries = New-Object System.Collections.Generic.List[string]
    foreach ($steam in @((Registry-Value 'HKCU:\Software\Valve\Steam' 'SteamPath'),
        (Registry-Value 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam'), 'C:\Games\Steam')) {
        if ($steam -and (Test-Path -LiteralPath $steam)) { $libraries.Add($steam) }
    }
    foreach ($steam in @($libraries)) {
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) {
                $libraries.Add($match.Groups[1].Value.Replace('\\', '\'))
            }
        }
    }
    foreach ($library in $libraries) {
        $manifest = Join-Path $library 'steamapps\appmanifest_2630.acf'
        if (Test-Path -LiteralPath $manifest) {
            $install = (Quoted-Pairs (Get-Content -LiteralPath $manifest -Raw))['installdir']
            if ($install -and $install -notmatch '[\\/:]') { & $add (Join-Path $library ('steamapps\common\' + $install)) }
        }
    }
    foreach ($common in @((Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Activision\Call of Duty 2'),
        'C:\Games\Call of Duty 2', 'D:\Games\Call of Duty 2', 'C:\Program Files\Activision\Call of Duty 2')) { & $add $common }
    return @($found)
}
function Ask-YesNo([string]$Text) {
    Add-Type -AssemblyName System.Windows.Forms
    $answer = [Windows.Forms.MessageBox]::Show($Text, 'ProSmoke', [Windows.Forms.MessageBoxButtons]::YesNo, [Windows.Forms.MessageBoxIcon]::Question)
    return $answer -eq [Windows.Forms.DialogResult]::Yes
}
function Pick-GameFolder([string]$Reason) {
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show($Reason + "`n`nIn the next window, pick the folder that contains CoD2MP_s.exe.",
        'ProSmoke', [Windows.Forms.MessageBoxButtons]::OK, [Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    $dialog = New-Object Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Select your Call of Duty 2 folder (the one with CoD2MP_s.exe)'
    $dialog.ShowNewFolderButton = $false
    if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { return $null }
    return $dialog.SelectedPath
}
function Resolve-Game {
    if ($GameDirectory) {
        $full = [IO.Path]::GetFullPath($GameDirectory).TrimEnd('\')
        if (-not (Test-GameFolder $full)) { throw "No CoD2MP_s.exe in $full" }
        return $full
    }
    $candidates = @(Find-GameFolders)   # @() keeps a single hit an array; PowerShell unrolls one-element returns
    if ($NoPrompt) {
        if ($candidates.Count -eq 1) { return $candidates[0] }
        throw ('Pass -GameDirectory when using -NoPrompt. Detected: ' + $(if ($candidates.Count) { $candidates -join '; ' } else { 'nothing' }))
    }
    if ($candidates.Count -eq 1) {
        Say "Found Call of Duty 2 at: $($candidates[0])"
        if (Ask-YesNo "Found Call of Duty 2 at:`n$($candidates[0])`n`nUse this folder?") { return $candidates[0] }
        $reason = 'Choose a different folder.'
    } elseif ($candidates.Count -gt 1) {
        $reason = "Several Call of Duty 2 folders were found:`n" + ($candidates -join "`n")
    } else {
        $reason = 'Call of Duty 2 was not found automatically.'
    }
    $picked = Pick-GameFolder $reason
    if (-not $picked) { throw 'No game folder selected.' }
    $full = [IO.Path]::GetFullPath($picked).TrimEnd('\')
    if (-not (Test-GameFolder $full)) { throw "No CoD2MP_s.exe in $full. Pick the folder that contains the game executable." }
    return $full
}
function Assert-Stopped {
    $running = @(Get-Process -Name 'CoD2MP_s' -ErrorAction SilentlyContinue)
    if ($running.Count) { throw 'Call of Duty 2 is running. Close it and try again.' }
}
function Remember([string]$Game) {
    try {
        [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
        [IO.File]::WriteAllText($rememberedPath, $Game)
    } catch { }
}
function Write-Atomic([string]$Path, [byte[]]$Data) {
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $pending = $Path + '.next'
    [IO.File]::WriteAllBytes($pending, $Data)
    if (Test-Path -LiteralPath $Path) { [IO.File]::Replace($pending, $Path, [NullString]::Value) } else { [IO.File]::Move($pending, $Path) }
}
function Get-Status([string]$Game) {
    $loader = Join-Path $Game 'mss32.dll'
    [pscustomobject]@{
        game = $Game
        cod2x = (Test-CoD2xLoader $loader) -and (Test-Path -LiteralPath (Join-Path $Game 'mss32_original.dll') -PathType Leaf)
        loaderIsProSmoke = Test-ProSmokeLoader $loader                       # any ProSmoke version
        loaderIsCurrent = (File-Hash $loader) -eq (File-Hash $packageLoader)  # this package's build
        runtime = Test-Path -LiteralPath (Join-Path $Game 'prosmoke\prosmoke.dll') -PathType Leaf
        backup = Test-Path -LiteralPath (Join-Path $Game "$backupName\mss32.dll") -PathType Leaf
    }
}
function Find-SteamDirectory([string]$Game) {
    $candidates = @()
    for ($folder = Get-Item -LiteralPath $Game; $null -ne $folder; $folder = $folder.Parent) {
        if ($folder.Name -eq 'steamapps' -and $folder.Parent) { $candidates += $folder.Parent.FullName }
    }
    $candidates += @((Registry-Value 'HKCU:\Software\Valve\Steam' 'SteamPath'), (Registry-Value 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' 'InstallPath'),
        (Join-Path ([Environment]::GetFolderPath('ProgramFilesX86')) 'Steam'))
    foreach ($candidate in $candidates) {
        if (-not $candidate -or -not [IO.Path]::IsPathRooted($candidate)) { continue }
        if ((Test-Path -LiteralPath (Join-Path $candidate 'steam.exe')) -and (Test-Path -LiteralPath (Join-Path $candidate 'Steam.dll'))) { return $candidate }
    }
    return $null
}

try {
    foreach ($required in @($packageLoader, (Join-Path $payload 'prosmoke.dll'), (Join-Path $payload 'smoke.shaders'),
        (Join-Path $payload 'noise128.rgba'), (Join-Path $payload 'prosmoke_stock.iwd'), (Join-Path $payload 'prosmoke.cfg'))) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "The package is incomplete: missing $required. Extract the whole ZIP and keep its folders together." }
    }
    $game = Resolve-Game
    $status = Get-Status $game
    Say "Game folder: $game"

    if ($Action -eq 'Check') {
        Say ("CoD2x installed: " + $status.cod2x)
        Say ("ProSmoke installed: " + ($status.loaderIsProSmoke -and $status.runtime))
        Say ("Backup of original loader present: " + $status.backup)
        exit 0
    }

    if ($Action -eq 'Install') {
        if (-not $status.cod2x -and -not $status.loaderIsProSmoke) {
            throw 'CoD2x is not installed in that folder (mss32.dll is not the CoD2x loader, or mss32_original.dll is missing). Install CoD2x first: https://github.com/callofduty2x/CoD2x'
        }
        Assert-Stopped
        $loader = Join-Path $game 'mss32.dll'
        $backupDirectory = Join-Path $game $backupName
        $backupLoader = Join-Path $backupDirectory 'mss32.dll'
        if (-not $status.loaderIsProSmoke) {
            if ((Test-Path -LiteralPath $backupLoader) -and ((File-Hash $backupLoader) -ne (File-Hash $loader))) {
                # CoD2x was updated since the last install; keep the older backup too.
                Move-Item -LiteralPath $backupLoader -Destination (Join-Path $backupDirectory ('mss32.' + [DateTime]::Now.ToString('yyyyMMdd-HHmmss') + '.dll'))
            }
            if (-not (Test-Path -LiteralPath $backupLoader)) {
                Write-Atomic $backupLoader ([IO.File]::ReadAllBytes($loader))
                Say "Backed up your CoD2x loader to $backupName\mss32.dll"
            }
        } elseif ($status.loaderIsCurrent) { Say 'ProSmoke loader already installed; refreshing files.' }
        else { Say 'Replacing an earlier ProSmoke loader; your original CoD2x backup is kept.' }
        Write-Atomic $loader ([IO.File]::ReadAllBytes($packageLoader))
        $target = Join-Path $game 'prosmoke'
        foreach ($file in Get-ChildItem -LiteralPath $payload -File) {
            Write-Atomic (Join-Path $target $file.Name) ([IO.File]::ReadAllBytes($file.FullName))
        }
        [IO.Directory]::CreateDirectory($backupDirectory) | Out-Null
        $record = [ordered]@{ installed = [DateTime]::Now.ToString('s'); loader = File-Hash $packageLoader; runtime = File-Hash (Join-Path $payload 'prosmoke.dll') }
        [IO.File]::WriteAllText((Join-Path $backupDirectory 'install.json'), ($record | ConvertTo-Json))
        Remember $game
        Say ''
        Say 'ProSmoke installed.'
        Say '  Start Call of Duty 2 normally and join a server that has ProSmoke enabled,'
        Say '  or double-click Play-Local.cmd for a local Toujane with smoke on.'
        Say '  Undo-Client.cmd puts your original CoD2x loader back.'
        exit 0
    }

    if ($Action -eq 'Undo') {
        Assert-Stopped
        $loader = Join-Path $game 'mss32.dll'
        $backupDirectory = Join-Path $game $backupName
        $backupLoader = Join-Path $backupDirectory 'mss32.dll'
        if (Test-Path -LiteralPath $backupLoader) {
            if (-not (Test-CoD2xLoader $backupLoader)) { throw "The backup at $backupLoader is not a CoD2x loader. Reinstall CoD2x instead." }
            if (Test-ProSmokeLoader $backupLoader) { throw "The backup at $backupLoader is itself a ProSmoke loader. Reinstall CoD2x to get the stock loader back." }
            Write-Atomic $loader ([IO.File]::ReadAllBytes($backupLoader))
            Say 'Restored your original CoD2x loader.'
        } elseif ($status.loaderIsProSmoke) {
            throw "No backup found in $backupName. Reinstall CoD2x to replace mss32.dll, then delete the prosmoke folder."
        } else { Say 'The game loader is not the ProSmoke one; leaving mss32.dll alone.' }
        $target = Join-Path $game 'prosmoke'
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force; Say 'Removed the prosmoke folder.' }
        if (Test-Path -LiteralPath $backupDirectory) { Remove-Item -LiteralPath $backupDirectory -Recurse -Force }
        Say 'ProSmoke removed. Game logs and your configs were not touched.'
        exit 0
    }

    if ($Action -eq 'Play') {
        if (-not ($status.loaderIsProSmoke -and $status.runtime)) { throw 'ProSmoke is not installed in that folder. Run Setup-Client.cmd first.' }
        $quoted = '"' + $game + '"'
        $arguments = @('+set', 'fs_basepath', $quoted, '+set', 'fs_homepath', $quoted, '+set', 'fs_game', 'prosmoke',
            '+set', 'sv_punkbuster', '0', '+set', 'cl_punkbuster', '0', '+set', 'sv_pure', '0', '+set', 'net_ip', '127.0.0.1',
            '+set', 'r_rendererPreference', 'dx9', '+set', 'g_gametype', 'tdm', '+exec', 'prosmoke.cfg', '+devmap', $Map)
        if ($DryRun) { Say ('Launch: CoD2MP_s.exe ' + ($arguments -join ' ')); exit 0 }
        Assert-Stopped
        $steam = Find-SteamDirectory $game
        $previousPath = $env:PATH
        try {
            if ($steam) { $env:PATH = $steam + ';' + $previousPath; Say "Steam client folder added to this launch: $steam" }
            Start-Process -FilePath (Join-Path $game 'CoD2MP_s.exe') -WorkingDirectory $game -ArgumentList $arguments | Out-Null
        } finally { $env:PATH = $previousPath }
        Say "Starting Call of Duty 2 on $Map with ProSmoke. Join a team, throw a smoke, shoot through it."
        exit 0
    }
} catch {
    Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
