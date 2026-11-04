ProSmoke - installed competitive map occupancy, 2026-11-04

This directory contains DATA ONLY. It does not include maps, extracted geometry,
renderers, launchers or installer scripts. The source BSP files and installed
game archives were not modified. Automatic in-game baking is not implemented.

20 map BSPs were found in the installed zPAM maps v7 archive and standalone Eyza,
Neuville and Sfax archives. All 20 have baked grids bound to those exact BSP bytes.
The inventory records map names, source hashes/CRC32, dimensions and grid hashes.
Static prop meshes are ignored, matching the existing stock bake policy.

FULL COLLISION BOUNDS - 12 MAPS
Use prosmoke_competitive_full.iwd, OR the individual files under full/.
Do not install both combined and individual copies for the same maps.
  mp_eyza_a1
  mp_breakout_tls
  mp_burgundy_fix
  mp_dawnville_fix
  mp_dawnville_sun
  mp_leningrad_mjr
  mp_leningrad_tls
  mp_railyard_mjr
  mp_toujane_fix
  mp_trainstation_bhg
  mp_trainstation_fix
  wawa_3daim (aim training)

CROPPED CANDIDATES - 8 MAPS, BOUNDS REVIEW REQUIRED
These maps exceed the current 16-million-cell cap at full collision bounds and
50 cm precision. Spawn-hint bounds fit without reducing voxel precision.
The generated grids contain all exported spawn hints, but that does NOT prove
coverage of every playable route, rooftop or grenade trajectory. Live gameplay
and bounds review have not been performed. These are not release-approved.
The runtime does not enforce the metadata's review flag: keep these separate
until coverage is reviewed. Do not deploy them blindly to a competitive server.
Individual files: cropped-candidates/
Combined candidate: prosmoke_competitive_cropped_candidates.iwd
  mp_neuville_a1
  mp_sfax
  mp_carentan_bal
  mp_carentan_fix
  mp_chelm_fix
  mp_crossroads
  mp_matmata_fix
  mp_vallente_fix

INSTALLATION FOR TESTING
Close CoD2. Put the chosen occupancy IWD into the active fs_game mod directory,
alongside the mod's other IWDs. For a local ProSmoke mod launch this is the
game's prosmoke folder, selected with fs_game prosmoke. Restart the game fully.
Do not replace the map archive or the stock ProSmoke occupancy file.

CoD2x filters arbitrary archives placed in main. Public 0.1.5's local admission
is specifically for iw_prosmoke_stock.iwd; it does not automatically admit these
new competitive bundles in main. Use an active mod folder and the normal
server-required archive mechanism. With sv_pure 1 the server and clients need
the same occupancy archive in the corresponding active mod folder; normal mod
downloads can supply it. The server must also opt in with:
  sets sv_prosmoke_policy "v1"

The map BSP must match inventory.json. Regenerate grids when the map changes.
Do not leave multiple different grids for the same map in mounted archives.
To undo, close the game and remove only the occupancy IWDs you added.

VALIDATION AND LIMITS
Every individual package has exactly one smokegrid/smokebind/metadata triplet.
Grid format/dimensions, ZIP CRC, grid SHA256 and PSB1 BSP/grid CRC binding were
validated against the actual installed BSP. Combined bundles were re-opened and
all bindings checked. No live map acceptance or new FPS result is claimed.
The current NVIDIA AA renderer candidate has a separate reported corruption
issue; these data packages do not fix or change the renderer.
