# Smoke occupancy baker

This is an optional authoring tool. Players do not run it, and all 15 stock MP maps
already have grids in `smoke/prebuilt/runtime/mapkit_smoke_test/mapkit_smoke_stock.iwd`.

The baker takes an existing compiled `.d3dbsp`, extracts solid world brushes and
terrain collision, voxelizes them at 50 cm, and packages the grid with the BSP/grid
CRC binding and public metadata. It does not compile map geometry, bake lighting,
edit materials or change the BSP. It contains no editor and no stock game assets.

Requires Windows and Python 3.10 or later. The voxelizer is prebuilt; the Python
wrapper/exporter uses only the standard library for the supported world-only bake.
No Pillow, game installation or extracted models are required. Static prop meshes
are deliberately ignored so tanks and small objects do not trap smoke.

```powershell
python tools/smoke-bake/bake.py C:\Maps\mp_example.d3dbsp --output C:\Maps\smoke-output
```

Output: `smoke-output/mp_example/mapkit_smoke_mp_example.iwd`. Install that data-only
IWD in the active server mod alongside the exact matching map. Regenerate it whenever
the BSP changes. The native client is still required; occupancy alone does not add smoke.

Default bounds cover the included world collision. If a map is too large for the
16-million-cell limit, the bake fails rather than lowering voxel precision. An explicit
`--bounds hints` produces a spawn-cropped candidate that must be checked against playable
routes, rooftops and grenade trajectories. These bounds are not release-approved automatically.

The temporary `.smoke-work-*` directory is confined to the output folder and removed
after each bake. Final outputs/cache remain there. The tool never installs or launches
CoD2. `bin/cod2smoke-bake.json` records the supplied voxelizer's hash.

The prebuilt voxelizer and smoke runtime retain the supplied license/attribution notices.
Implementation source remains in the owner's separate workspace for this local review.
