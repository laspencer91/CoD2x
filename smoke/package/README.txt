ProSmoke 0.1.4 preview - manual install edition for Call of Duty 2 (CoD2x)

Volumetric smoke provides competitive integrity by rendering smoke as a true 3D
volume that exists in the world. It does not suffer from the problems of 2D
billboard smokes that face each player's camera, giving a different view on each
client's screen, nor does smoke density rely on per-billboard opacity.
Bullets carve holes through it. Server enforced smoke configuration.

REQUIREMENTS
  Call of Duty 2 version 1.3 with CoD2x installed (https://github.com/callofduty2x/CoD2x).
  DX7 and DX9 game renderers are supported on a Shader Model 3-capable GPU.
  Steam and disc versions both work.

INSTALL OR UPDATE BY HAND
  This edition contains no installer or launch scripts. Backups are manual.
  1. Close CoD2 and extract the entire ZIP into a new folder.
  2. Find your game folder: the one containing CoD2MP_s.exe. CoD2x must already
     be installed, with its mss32.dll and mss32_original.dll present.
  3. Create a backup folder outside the game folder. Copy the current mss32.dll
     and the complete existing prosmoke folder, if present, into that backup.
     Also keep any older prosmoke-backup folder: it may hold your stock loader.
  4. Copy client\mss32.dll into the game folder, replacing mss32.dll.
  5. Copy client\prosmoke into the game folder as prosmoke. Replace the matching
     package files together. If updating, keep your existing prosmoke.cfg.
  6. Start CoD2 normally and join a server with ProSmoke enabled.
  Leave mss32_original.dll untouched. Do not mix renderer/shader versions.

ROLLBACK OR REMOVE
  To undo this update: close CoD2, restore mss32.dll from step 3, and replace the
  installed prosmoke folder with the complete backed-up folder. If no prosmoke
  folder existed before, remove only the new prosmoke folder.
  To remove ProSmoke entirely: restore a verified stock CoD2x mss32.dll from
  your original backup, or reinstall official CoD2x, then remove prosmoke.
  A loader backed up from an earlier ProSmoke preview is not a stock loader.

PERFORMANCE IN THIS PREVIEW
  Includes the selected CPU preparation, depth-aware reconstruction, projected
  scissor and split repair optimizations. The DX7 adaptive GPU-sync path also
  uses shorter blocked waits at two verified native fence-sleep callers.
  Unsupported code or timers retain native waits. Fence checks are preserved.
  /prosmoke_shortWait 0 restores native wait delays; 1 enables the optimization
  when smoke is ready and DX7 adaptive GPU sync is active. Shorter waits can use
  more CPU. /prosmoke_status reports the version, active state and call counts.
  /prosmoke_resolution quarter reduces smoke render resolution; the default
  remains half and existing player preferences are retained.
  Constant 250 FPS at 3440x1440 is not guaranteed. Experimental probe shaders
  and the paused DX11 renderer are not included.

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
  Create a shortcut to CoD2MP_s.exe. Set its "Start in" to the game folder.
  Append these arguments after the quoted executable path in "Target":
    +set fs_game prosmoke +set net_ip 127.0.0.1 +set sv_punkbuster 0 +set cl_punkbuster 0 +set sv_pure 0 +exec prosmoke.cfg +devmap mp_toujane
  This starts a private local listen server with the policy in prosmoke.cfg.
  The pure/PunkBuster settings above are for this local test only.
  To try other settings, edit <game>\prosmoke\prosmoke.cfg, or type in the console:
    /set sv_prosmoke_policy "v1 width=1.4 height=1.3 bloom_time=3 carve_scale=0.8"
  Carve changes apply to the next shot. Width, height, bloom and duration
  changes apply once the current clouds have faded. All fields and their
  ranges are listed in server\prosmoke_server.cfg.
  Another map:  replace mp_toujane with mp_burgundy in the shortcut arguments.
  Quality:      /prosmoke_resolution full, half or quarter (default half)

PROBLEMS
  Still see normal smoke? Open the console and look for the ProSmoke line, or
  type /prosmoke_status. The server must publish the policy line, your GPU
  must support DX9 depth textures (NVIDIA, AMD and Intel from the last 15
  years; anti-aliasing must be off on NVIDIA, r_aaSamples 1), and the
  map needs an occupancy grid (all 15 stock maps are included). Logs:
    <game>\prosmoke\client.log
    %LOCALAPPDATA%\prosmoke\bridge.log

This is a preview build shared for testing. CoD2x auto-updates are disabled in
this loader so an update cannot silently remove smoke. Restore a verified stock
CoD2x loader, or reinstall official CoD2x, to return to its regular updates.
The compiled loader, renderer and shaders are unchanged from 0.1.4 preview.
