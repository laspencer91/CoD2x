ProSmoke 0.1.7 preview - manual install for Call of Duty 2 (CoD2x)

Volumetric smoke provides competitive integrity by rendering smoke as a true 3D
volume that exists in the world. It does not suffer from the problems of 2D
billboard smokes that face each player's camera, giving a different view on each
client's screen, nor does smoke density rely on per-billboard opacity.
Bullets carve holes through it. Server enforced smoke configuration.

REQUIREMENTS
  Call of Duty 2 version 1.3 with CoD2x installed (https://github.com/callofduty2x/CoD2x).
  DX7 and DX9 game renderers are supported on a Shader Model 3-capable GPU.
  DX7 with 2x/4x antialiasing has been checked on AMD RX 9060 XT and NVIDIA
  RTX 5080. NVIDIA uses an NVAPI depth copy; AMD uses RESZ. Unsupported depth
  paths retain normal smoke. This does not certify every GPU or driver.
  Steam and disc versions both work.

INSTALL OR UPDATE BY HAND
  This edition contains no installer or launch scripts. Backups are manual.
  1. Close CoD2 and extract the entire ZIP into a new folder.
  2. Find your game folder: the one containing CoD2MP_s.exe. CoD2x must already
     be installed, with its mss32.dll and mss32_original.dll present.
  3. Create a backup folder outside the game folder. Copy the current mss32.dll
     and the complete existing prosmoke folder, if present, into that backup.
     Also keep any older prosmoke-backup folder: it may hold your stock loader.
     Back up main\iw_prosmoke_stock.iwd too if it already exists.
  4. Copy client\mss32.dll into the game folder, replacing mss32.dll.
  5. Copy client\prosmoke into the game folder as prosmoke. Replace the matching
     package files together. If updating, keep your existing prosmoke.cfg.
  6. Copy client\main\iw_prosmoke_stock.iwd into the game's main folder. This
     makes stock-map grids visible during a normal launch, without selecting
     fs_game prosmoke. Keep the matching copy in prosmoke as well. The 0.1.5
     loader admits this exact main archive for installed local games; online
     connections retain CoD2x's server-required archive filtering.
  7. Fully restart CoD2 and join a server with ProSmoke enabled.
  Leave mss32_original.dll untouched. Do not mix renderer/shader versions.

ROLLBACK OR REMOVE
  To undo this update: close CoD2, restore mss32.dll from step 3, and replace the
  installed prosmoke folder with the complete backed-up folder. If no prosmoke
  folder existed before, remove only the new prosmoke folder.
  Restore main\iw_prosmoke_stock.iwd from your backup, or remove that exact
  file if it did not exist before installation. Leave other main files alone.
  To remove ProSmoke entirely: restore a verified stock CoD2x mss32.dll from
  your original backup, or reinstall official CoD2x, then remove prosmoke.
  Restore/remove main\iw_prosmoke_stock.iwd as described above.
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
  3. For the 12 additional competitive maps, including mp_toujane_fix, also
     install server\prosmoke_competitive_full.iwd and distribute that same IWD
     to clients through the server's normal mod downloads or FastDL mirror.
  Details in server\README-SERVER.txt.

  Without the policy line, ProSmoke clients see normal smoke on that server.

LOCAL TESTING
  A local server must opt in too. After starting a local map normally, enter
  /sets sv_prosmoke_policy "v1" in the console, then throw a new smoke. Use
  /prosmoke_status to inspect the active policy, map-grid and renderer state.
  The grid placement above fixes map-data discovery; it does not enable a
  server policy automatically or change online servers' policies.

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
  must support a working DX9 depth-texture path (even in DX7 mode), and the
  map needs an occupancy grid (all 15 stock maps are included). Logs:
    <game>\prosmoke\client.log
    %LOCALAPPDATA%\prosmoke\bridge.log

This is a preview build shared for testing. CoD2x auto-updates are disabled in
this loader so an update cannot silently remove smoke. Restore a verified stock
CoD2x loader, or reinstall official CoD2x, to return to its regular updates.
The 0.1.7 renderer fixes faint scenery-dependent colour inside fully opaque
smoke. It retains NVIDIA MSAA depth copies and stock/zPAM smoke type 2/3
support. Use this package's matching DLL and shader bundle. Noise and map grids
are unchanged. The loader retains local grid-archive mounting.
