ProSmoke - volumetric smoke for Call of Duty 2 (CoD2x)

Smoke grenades become real volumes that fill rooms, flow around walls, and get
carved by bullets. Everyone on a server sees the same cloud, tuned by the server.

REQUIREMENTS
  Call of Duty 2 version 1.3 with CoD2x installed (https://github.com/callofduty2x/CoD2x).
  DirectX 9 renderer (the default). Steam and disc versions both work.

CLIENT - two ways
  1. Double-click Setup-Client.cmd. It finds your game folder (or asks you to
     pick it), backs up your CoD2x loader to prosmoke-backup\, and copies the files.
     Undo-Client.cmd puts everything back.
  2. By hand: copy the contents of the client folder into your Call of Duty 2
     folder, next to CoD2MP_s.exe. Say yes to replacing mss32.dll (keep a copy of
     the old one if you want to go back). To remove: restore your old mss32.dll
     and delete the prosmoke folder.

  Smoke is on whenever the prosmoke folder is next to CoD2MP_s.exe. Delete the
  folder to turn it off without touching anything else.

  Play-Local.cmd starts Toujane locally with smoke on. Throw a smoke, shoot it.

SERVER
  Nothing to install on the server for it to work. One line in the server config
  enables smoke for every ProSmoke client, and the same line tunes it:
    sets sv_prosmoke_policy "v1"
  The server folder has a sample config with every field explained and the
  occupancy file that sv_pure servers need. See server\README-SERVER.txt.

  No policy line on the server = normal smoke, so ProSmoke clients can play
  anywhere.

QUALITY
  In the console: /prosmoke_resolution full, half or quarter (default half).

PROBLEMS
  Still see normal smoke? The server must publish the policy line, your GPU
  must support DX9 depth textures (anything from the last 15 years), and the
  map needs an occupancy grid (all 15 stock maps are included). Logs:
    <game>\prosmoke\client.log
    %LOCALAPPDATA%\prosmoke\bridge.log

This is a preview build shared for testing. CoD2x auto-updates are disabled in
this loader so an update cannot silently remove smoke; run Undo-Client.cmd to go
back to the regular CoD2x loader at any time.
