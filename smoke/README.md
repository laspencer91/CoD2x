# ProSmoke

Volumetric smoke for Call of Duty 2 on CoD2x. Volumetric smoke provides competitive integrity by rendering smoke as a true 3D volume that exists in the world. It does not suffer from the problems of 2D billboard smokes that face each player's camera, giving a different view on each client's screen, nor does smoke density rely on per-billboard opacity. Bullets carve holes through it. Server enforced smoke configuration: look, size, timing and carve sizes come from the
server, so every player sees the same cloud.

## What is in this branch

- `src/mss32/smoke_diagnostics.*`, `smoke_activation.hpp`, `policy.hpp`: the client
  bridge compiled into the CoD2x loader. It loads the renderer, hooks the scene
  render call, forwards bullet traces and passes the server policy through.
- `smoke/package`: the shipped ZIP, exactly as players and admins receive it.
- `smoke/custom-occupancy`: optional occupancy packages for 21 custom/test maps.
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
├── Setup-Client.cmd       finds the game, backs up mss32.dll, copies the client files
├── Undo-Client.cmd        restores the original loader, removes prosmoke\
├── Play-Local.cmd         local Toujane with smoke on
├── scripts/setup.ps1      what the three .cmd files run
├── client/                drop the contents into the CoD2 folder
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

Setup detects the game through the CoD2 registry key, Steam library folders and
the usual install paths. One match asks for confirmation; none or several opens a
folder picker. It refuses folders without CoD2x, refuses while the game runs,
backs up `mss32.dll` into `prosmoke-backup\`, copies the client files and remembers
the folder under `%LOCALAPPDATA%\prosmoke`. A later CoD2x update that replaces
the loader is backed up as the new restore baseline on the next install, keeping
the earlier copy. Undo reverses all of it.

Smoke activates when `prosmoke\prosmoke.dll` exists beside `CoD2MP_s.exe`, so a
manual copy works and deleting the folder turns it off. `COD2_SMOKE_RENDER=0` and
`COD2_SMOKE_DIAGNOSTICS` remain explicit overrides. `prosmoke_resolution`
(full, half, quarter) is the only client-side setting.

The loader is built with `COD2X_SMOKE_TEST_BUILD=ON`, which disables CoD2x's own
update check so a stable update cannot replace it. Undo returns the regular loader.

## Console status

The renderer queues short status lines and the loader prints them in the game console on the engine thread: `ProSmoke: volumetric smoke active` once the depth path is verified for a map, or a `... normal smoke` line naming the reason (missing or invalid `sv_prosmoke_policy`, no occupancy grid for the map, no INTZ/RESZ depth texture, shader or noise load failure). `/prosmoke_status` prints whether the renderer DLL loaded, the policy the client sees, the renderer summary (`map= policy= ready= last=`) and the quality setting. The same lines go to `<game>\prosmoke\client.log`.

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
also builds the bridge.

## Remaining work

Live acceptance on a dedicated server publishing the policy with `sets`, more
GPUs (NVIDIA, AMD, Intel through D3D9On12, DXVK), particle ordering mode 2,
large-volume splitting, same-name map rebinding, round/killcam/demo behaviour,
authoritative remote sky-shot transport, and six cropped stock-map bounds
reviews (Brecourt, Carentan, Decoy, Harbor, Matmata, Rhine). See
[VALIDATION.md](VALIDATION.md) for what has been checked offline.
