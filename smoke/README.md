# ProSmoke

Volumetric smoke for Call of Duty 2 on CoD2x. Volumetric smoke provides competitive integrity by rendering smoke as a true 3D volume that exists in the world. It does not suffer from the problems of 2D billboard smokes that face each player's camera, giving a different view on each client's screen, nor does smoke density rely on per-billboard opacity. Bullets carve holes through it. Server enforced smoke configuration: look, size, timing and carve sizes come from the
server, so every player sees the same cloud.

## What is in this branch

- `src/mss32/smoke_diagnostics.*`, `smoke_activation.hpp`, `policy.hpp`: the client
  bridge compiled into the CoD2x loader. It loads the renderer, hooks the scene
  render call, forwards bullet traces and passes the server policy through.
- `smoke/package`: the shipped ZIP, exactly as players and admins receive it.
- `smoke/custom-occupancy`: optional occupancy packages for 21 custom/test maps.
- `smoke/competitive-occupancy`: 20 installed competitive/training map bakes,
  including `mp_toujane_fix`; 12 full-collision grids and 8 separate cropped
  candidates requiring bounds review. See its README and inventory before use.
- `smoke/provenance`: hashes tying the shipped binaries to this source and the
  renderer build.
- `tools/smoke-bake`: optional occupancy baker for custom maps (prebuilt voxelizer
  plus standard-library Python). See its [README](../tools/smoke-bake/README.md).

The renderer (`prosmoke.dll`) and its HLSL are built from a separate workspace with
MSVC x86 and shipped prebuilt here. No license or notice files ship; this is a
preview handed to people the author knows.

## Package layout

```
prosmoke.zip
├── README.txt
├── client/                drop the contents into the CoD2 folder
│   ├── main/iw_prosmoke_stock.iwd   grids mounted by a normal game launch
│   ├── mss32.dll          CoD2x loader with the ProSmoke bridge
│   └── prosmoke/
│       ├── prosmoke.dll   renderer
│       ├── smoke.shaders  compiled DX9 shaders
│       ├── noise128.rgba
│       ├── prosmoke_stock.iwd   occupancy grids for all 15 stock maps
│       └── prosmoke.cfg   default policy for the local launch
└── server/
    ├── README-SERVER.txt
    ├── prosmoke_server.cfg  sample policy line, every field explained
    └── prosmoke_stock.iwd   for sv_pure servers
```

## Client

This edition uses manual installation and contains no installer or launcher
scripts. Close CoD2 and back up the current `mss32.dll` and complete `prosmoke`
folder outside the game directory. Keep any original `prosmoke-backup` folder.
Back up an existing `main/iw_prosmoke_stock.iwd` as well.
Copy the contents of `client` beside `CoD2MP_s.exe`, replacing the matching files
together. When updating, preserve your existing `prosmoke.cfg`. CoD2 1.3 and
CoD2x must already be installed; leave `mss32_original.dll` untouched.
Include `client/main/iw_prosmoke_stock.iwd` when copying: CoD2 mounts `main` for
normal launches. The matching IWD under `prosmoke` supports `fs_game prosmoke`.
Fully restart after adding an IWD. A local server still needs an explicit valid
`sv_prosmoke_policy`; map-data installation does not change server policy.

To undo an update, close the game and restore the backed-up loader and complete
runtime folder. To remove ProSmoke entirely, restore a verified stock CoD2x loader
or reinstall official CoD2x, then remove `prosmoke`. A previous ProSmoke preview's
loader is not a stock loader. See `package/README.txt` for complete installation,
rollback and local-test shortcut instructions.
Also restore the backed-up `main/iw_prosmoke_stock.iwd`, or remove that exact file
if it did not exist before the update. Leave all other `main` files alone.

Smoke activates when `prosmoke\prosmoke.dll` exists beside `CoD2MP_s.exe`, so a
manual copy works and deleting the folder turns it off. `COD2_SMOKE_RENDER=0` and
`COD2_SMOKE_DIAGNOSTICS` remain explicit overrides. `prosmoke_resolution`
(full, half, quarter) controls smoke resolution. `prosmoke_shortWait` (default1)
enables the guarded250us game/render fence waits only with a ready smoke renderer,
valid server policy, DX7 and native adaptive GPU sync. Set it to0 for original
wait delays. Unsupported code/timers fall back to native waits. Fence polls,
prediction limits, unrelated sleeps and system timer resolution are unchanged.
The optimization does not install in debug hot-reload builds.

Preview 0.1.5 adds the `main` grid archive and a narrowly scoped loader admission
for that exact archive in installed local games. Remote connections retain the
server-required IWD filtering. The selected v8 renderer is unchanged from 0.1.4;
backups and config preservation remain manual. `client/prosmoke/version.json` identifies the matched
loader/renderer/shader hashes. The renderer comes from `c26ceb0`; experimental
capture/replay shaders and DX11 are excluded. Constant250FPS remains unproven.

The loader is built with `COD2X_SMOKE_TEST_BUILD=ON`, which disables CoD2x's own
update check so a stable update cannot replace it. Restoring a verified stock
CoD2x loader returns to its normal update behavior.

## Console status

The renderer queues short status lines and the loader prints them in the game console on the engine thread: `ProSmoke: volumetric smoke active` once the depth path is verified for a map, or a `... normal smoke` line naming the reason (missing or invalid `sv_prosmoke_policy`, no occupancy grid for the map, no readable depth buffer, shader or noise load failure). `/prosmoke_status` prints whether the renderer DLL loaded, the policy the client sees, the renderer summary (`gpu= depth= map= policy= ready= last=`) and the quality setting. The same lines go to `<game>\prosmoke\client.log`.

## Server

The server renders nothing. One line in its config publishes the policy to every
client; a stock CoD2x server uses `sets` (serverinfo), a server built from this
branch may use `set` (systeminfo). The client checks systeminfo, then serverinfo.

```text
sets sv_prosmoke_policy "v1 width=1.3 height=1.1 bloom_time=3 carve_scale=0.8"
```

| Field | Default | Range | Effect |
|---|---|---|---|
| `width` | 1.2 | 0.5 to 1.5 | mature cloud radius multiplier |
| `height` | 1.0 | 0.5 to 2.0 | vertical radius and dome, on top of width |
| `bloom_rate` | 512 | 64 to 32768 | new cells per second while growing |
| `bloom_time` | 0 | 0 to 30 | seconds to full size; overrides `bloom_rate` when above 0 |
| `thicken` | 0.5 | 0.05 to 3 | seconds for a reached cell to fill |
| `duration` | 48 | 10 to 90 | cloud lifetime from detonation |
| `fade_time` | 12 | 1 to 30 | final fade; must be below `duration` |
| `carve_scale` | 1.0 | 0.5 to 2.0 | multiplies every carve radius |
| `carve_pistol` | 3 | 1 to 20 | Colt, Luger, Webley, TT-30 |
| `carve_smg` | 3.5 | 1 to 20 | Thompson, Grease Gun, MP40, PPSh, Sten |
| `carve_rifle` | 4.5 | 1 to 20 | MP44, BAR, unmatched weapons |
| `carve_semi` | 4.75 | 1 to 20 | Garand, M1 Carbine, G43, SVT-40 |
| `carve_sniper` | 11 | 1 to 20 | Kar98k, Mosin, Enfield, Springfield, scoped |
| `carve_shotgun` | 6 | 1 to 20 | Trench Gun pellet cone at the muzzle |

The look fields (`density`, `brightness`, `variation`, `shadow_strength`,
`lightgrid_strength`, `edge_softness`, `height_gradient`, `billow_*`, `wisp_*`,
`rise_speed`, `tint_*`, `fx_after_smoke`) are unchanged. `src/mss32/policy.hpp` is
the single list of fields, defaults and limits, and is identical in the renderer.
An invalid or missing line means stock smoke on that server; the client log says why.
Carve values apply to the next shot; width, height, bloom and timing changes wait
for active clouds to drain.

Under `sv_pure 1` the renderer can only read grids from IWDs the server also has,
so `prosmoke_stock.iwd` goes into the server's mod folder and the same file into
the clients' copy of that folder (downloads handle it). Without a mod folder it
goes into `main` renamed with an `iw_` prefix on both sides.

## Build

```powershell
.\smoke\Build-Package.ps1 -ToolchainDirectory <mingw root> -CMake <cmake.exe> -Ninja <ninja.exe> -RendererDirectory <renderer stage>
python -B -m unittest discover -s smoke/tests -v
```

The bridge uses the upstream 32-bit MinGW/NASM/OpenSSL toolchain; the renderer
stage comes from the owner workspace's `build-renderer.ps1`. Both arguments are
optional: without them the script repackages the checked-in binaries. Output is
`smoke/out/prosmoke.zip` with a SHA256 sidecar. The normal CMake target `mss32`
also builds the bridge. Packaging requires the exact manual-install file list
and rejects extra files, including installer and launcher scripts. Build scripts
and developer tools remain in the source repository, outside the player ZIP.

## Remaining work

Live acceptance on a dedicated server publishing the policy with `sets`, more
GPUs (NVIDIA, AMD, Intel through D3D9On12, DXVK), particle ordering mode 2,
large-volume splitting, same-name map rebinding, round/killcam/demo behaviour,
authoritative remote sky-shot transport, and six cropped stock-map bounds
reviews (Brecourt, Carentan, Decoy, Harbor, Matmata, Rhine). See
[VALIDATION.md](VALIDATION.md) for what has been checked offline.
