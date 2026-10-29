ProSmoke - volumetric smoke for Call of Duty 2 (CoD2x)

Volumetric smoke provides competitive integrity by rendering smoke as a true 3D
volume that exists in the world. It does not suffer from the problems of 2D
billboard smokes that face each player's camera, giving a different view on each
client's screen, nor does smoke density rely on per-billboard opacity.
Bullets carve holes through it. Server enforced smoke configuration.

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

CHECKING IT WORKS
  When a map loads, the console (~ key) prints "ProSmoke: volumetric smoke
  active". If smoke stays normal, a "ProSmoke: ... normal smoke" line says why
  (no policy from the server, no occupancy grid for the map, GPU limitation).
  Type /prosmoke_status at any time for the current state.

SERVER
  1. Add this line to your server config:
       sets sv_prosmoke_policy "v1"
     Fields after v1 tune width, height, bloom time, duration and per-weapon
     carve sizes. server\prosmoke_server.cfg lists them all with their ranges.
  2. If you run sv_pure 1, copy server\prosmoke_stock.iwd into your mod folder.
  Details in server\README-SERVER.txt.

  Without the policy line, ProSmoke clients see normal smoke on that server.

LOCAL TESTING
  Play-Local.cmd runs a local server on Toujane and applies the policy line in
  <game>\prosmoke\prosmoke.cfg. To try other settings, either edit that file
  (Setup-Client.cmd overwrites it when you reinstall), or type in the console
  while playing:
    /set sv_prosmoke_policy "v1 width=1.4 height=1.3 bloom_time=3 carve_scale=0.8"
  Carve changes apply to the next shot. Width, height, bloom and duration
  changes apply once the current clouds have faded. All fields and their
  ranges are listed in server\prosmoke_server.cfg.
  Another map:  Play-Local.cmd -Map mp_burgundy
  Quality:      /prosmoke_resolution full, half or quarter (default half)

PROBLEMS
  Still see normal smoke? Open the console and look for the ProSmoke line, or
  type /prosmoke_status. The server must publish the policy line, your GPU
  must support DX9 depth textures (anything from the last 15 years), and the
  map needs an occupancy grid (all 15 stock maps are included). Logs:
    <game>\prosmoke\client.log
    %LOCALAPPDATA%\prosmoke\bridge.log

This is a preview build shared for testing. CoD2x auto-updates are disabled in
this loader so an update cannot silently remove smoke; run Undo-Client.cmd to go
back to the regular CoD2x loader at any time.
