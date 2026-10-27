# Smoke occupancy baker

This is an optional authoring tool. Players do not run it, and all 15 stock MP maps
already have grids in `smoke/prebuilt/runtime/mapkit_smoke_test/mapkit_smoke_stock.iwd`.

The baker takes an existing compiled `.d3dbsp`, extracts solid world brushes and
terrain collision, voxelizes them at 50 cm, and packages the grid with the BSP/grid
CRC binding and public metadata. It does not compile map geometry, bake lighting,
edit materials or change the BSP. It contains no editor and no stock game assets.

The portable ZIP's `CoD2SmokeTool.exe` offers a **Bake occupancy** screen and includes
its own Python runtime. No Python installation is needed when using that interface.
The command below requires Windows and Python 3.10 or later. The voxelizer is prebuilt; the Python
wrapper/exporter uses only the standard library for the supported world-only bake.
No Pillow, game installation or extracted models are required. Static prop meshes
are deliberately ignored so tanks and small objects do not trap smoke.

Radiant `.map` source files are not accepted directly. Compile the map with the
CoD2 map tools first, then bake the resulting `.d3dbsp`. Occupancy is generated
from the compiled collision players actually load.

## Bake and install

Run this from the branch root or the extracted test ZIP root:

```powershell
python tools/smoke-bake/bake.py C:\Maps\mp_example.d3dbsp --output C:\Maps\smoke-output
```

The example writes the installable package to:

```text
C:\Maps\smoke-output\mp_example\mapkit_smoke_mp_example.iwd
```

Copy that `.iwd` into the active CoD2 mod directory (the directory selected by
`fs_game`). Our supplied test launcher uses `mapkit_smoke_test`, so a test copy
installed at `C:\Games\CoD2-Smoke-Test` needs:

```text
C:\Games\CoD2-Smoke-Test\mapkit_smoke_test\mapkit_smoke_mp_example.iwd
```

For another server mod, put the occupancy IWD alongside that mod's other IWDs and
make it available to clients together with the exact matching map. The occupancy
package does not contain the map itself. The optional custom/test occupancy IWDs
supplied in the bundle are installed in the same way.

Keep the IWD intact. It already contains `maps/mp/mp_example.smokegrid`,
`maps/mp/mp_example.smokebind` and `maps/mp/mp_example.smoke.json` in the paths the
runtime expects. Other loose files in the bake output are build/cache artifacts;
they do not need to be installed or distributed.

Close CoD2 before copying the package, then restart with the smoke test launcher
and load the matching map. Regenerate and replace its occupancy IWD whenever the
`.d3dbsp` changes. Avoid retaining older occupancy packages for the same map.
The smoke-enabled native client and server policy are still required; occupancy
alone does not add smoke. The supplied setup already installs stock-map occupancy,
so stock maps do not need to be baked again just to try the test kit.

## Bounds and working files

Default bounds cover the included world collision. If a map is too large for the
16-million-cell limit, the bake fails rather than lowering voxel precision. An explicit
`--bounds hints` produces a spawn-cropped candidate that must be checked against playable
routes, rooftops and grenade trajectories. These bounds are not release-approved automatically.

The temporary `.smoke-work-*` directory is confined to the output folder and removed
after each bake. Final outputs/cache remain there. The tool never installs or launches
CoD2. `bin/cod2smoke-bake.json` records the supplied voxelizer's hash.

The prebuilt voxelizer and smoke runtime retain the supplied license/attribution notices.
Implementation source remains in the owner's separate workspace for this local review.
