# Local branch validation

Validated on October 27, 2026. No game was launched and nothing was pushed.

- CoD2x bridge built with MinGW32/NASM, `RelWithDebInfo`, and
  `COD2X_SMOKE_TEST_BUILD=1`. All 364 proxy export names/ordinals match the existing bridge.
- The prebuilt MSVC x86 smoke component built successfully. Its 16 compiled shader
  variants load without HLSL; malformed, truncated, duplicate, corrupt and incompatible
  bundles are rejected. Stale loose HLSL cannot override the compiled bundle.
- The implementation workspace passes 118 Python tests and nine native probes.
  Thirteen installer cases include compiled-only setup, updates, preserved backups,
  changed-file rejection and install/uninstall rollback under file locks.
- The eight branch checks pass:
  `python -B -m unittest discover -s smoke/tests -v`.
  They verify prebuilt file/source hashes, 32-bit PE targets, all shader variants,
  data-only occupancy contents and baker imports without Python site packages.
  The package validator also rejects stale BSP bindings and unexpected archive entries.
- All 36 occupancy packages were checked against their original BSP snapshot CRCs
  and grid hashes in the owner workspace. The branch contains generated data only.
- The optional standalone baker regenerated Toujane and the terrain fixture without
  site packages. Both grids match the existing bakes byte for byte. Repeated runs
  reuse their caches. This validates the world/terrain path, not prop occupancy.
- The assembled package's real runtime payload was installed into a disposable
  folder containing a non-executable game stub. Verification passed, and removal
  restored the original bridge and preserved unrelated files. No HLSL was installed.
- Package integrity/hashes and source exclusions were checked. The ZIP contains no
  smoke implementation C++ or HLSL, source archive, original game executable,
  stock renderer, BSPs, textures or models. It includes setup scripts and the optional
  prebuilt voxelizer plus its Python collision-export/package wrapper.

Prebuilt bytes are marked `-text` in `.gitattributes` so Git line-ending conversion
does not invalidate installation hashes. Bridge source hashes normalize CRLF to LF.

## Portable desktop tool

- Tauri 2 Windows x64 release builds successfully; its EXE is approximately 4.6 MiB.
  Frontend type checking and Rust clippy with warnings denied pass.
- Four Rust tests cover map/path rejection, Steam VDF path parsing, bundle hash/path
  validation, and continuing process logs after a non-UTF8 line.
- Three headless browser UI tests pass using a mocked Tauri command interface. Setup,
  Try smoke requests, automatic Steam selection, error recovery, restore cancellation,
  bake requests/results and compact layouts are covered. Screenshots of the Setup
  and Bake screens at 880px and the compact Bake screen at 760px were inspected.
- The assembled portable EXE's read-only `--validate-bundle` check passes against
  the actual package, including the private embedded Python runtime.
- The official Python 3.14.10 Windows x64 embeddable ZIP matches its published
  SHA256. Its isolated interpreter runs the packaged baker without system Python
  or installed site packages. A real Toujane bake matches the distributed grid
  byte for byte and validates the final IWD before publication.
  The Rust backend's Bake operation also completed against that real bundle/map,
  including a temporary output directory with spaces in its name.
- The packaged installer passed check-only, install, verify, launch check-only and
  restore using a disposable non-executable game fixture. Quick Test's real launch
  path correctly rejects the currently running MWR client before launching a game.
- The native tool process starts. Both desktop inspection connections were
  unavailable, so native WebView/dialog interaction and live game launch remain
  acceptance checks. Browser UI fixtures do not substitute for those checks.

The complete test ZIP includes the EXE and supporting files. No app installer,
Node.js, or system Python is required by users; Microsoft WebView2 is required.
The desktop tool is unsigned, with no updater or background service.

Runtime validation now checks only the installer, bridge provenance, GUI and runtime
payload. Missing authoring files cannot block player actions. The regression fixture
checks missing authoring files both when declared in a full manifest and omitted
from a player manifest; actual runtime tampering is still rejected. Authoring is
offered only when its wrapper, interpreter and native baker are all present.
`-PlayerOnly` assembles a separate manifest/ZIP with no `tools/smoke-bake` files.

## Existing-installation flow

Steam and other existing installation folders are accepted by the UI, native
backend and installer. Try smoke checks launch conflicts before installation,
then installs with backups and launches; Authoring is a separate tab.
Three installer regressions exercise the actual runtime payload in a temporary
Steam-shaped folder: check-only performs no writes, Try installs and launches via
a fixture recorder, repeat installation preserves the first client backup, restore
returns its original bytes, and player config/mod files survive. Unsupported renderer
and launch-conflict cases leave the original client untouched. Host process checks
and game launch are isolated in these fixtures; no actual game binary is run.

Live mode-2 particle coverage, additional GPUs, reset/round/killcam behavior,
multi-client authoritative carving, large-volume limits and cropped map bounds
remain acceptance work. These offline checks do not establish player FPS or
competitive readiness. Existing license/attribution terms remain in place; this
local binary-component layout has not been approved for public distribution.

## October 28, 2026 update

Server-tunable shape, bloom and carving; no game was launched.

- `policy.hpp` (identical in the bridge and renderer) gained `height`, `bloom_time`
  and seven `carve_*` fields. Defaults equal the previous fixed values, so `v1`
  behaves as before. The bridge now reads the policy from systeminfo, then serverinfo.
- Renderer rebuilt with MSVC x86. Policy probe passes against all nine look presets,
  including serverinfo-shaped info strings and out-of-range rejection. Carve probe
  passes: class radii follow the policy, `carve_scale=0.5` halves packed bullet holes
  and shrinks the shotgun cone. Growth probe passes: `bloom_time=3` reaches full size
  at 3.000 s on the Toujane grid, height 1.5 and 0.6 change the mature target (5172
  and 827 cells against 2299), and the nominal target matches the core's pressure
  target.
- Bridge rebuilt with MinGW; all 364 proxy exports keep their ordinals and names.
- Not covered offline: a live dedicated server publishing the policy with `sets`,
  mixed systeminfo/serverinfo servers, and the visual result of height and bloom
  changes in game.

## October 28, 2026: ProSmoke rename and drop-in package

No game was launched. The Map Kit names, the desktop tool, the hash manifests and
all license/notice files were removed; the package is now `client/` and `server/`
folders plus three double-click commands.

- Server cvar `sv_prosmoke_policy`, client dvar `prosmoke_resolution`, runtime
  folder `prosmoke\`, renderer `prosmoke.dll`, grids `prosmoke_stock.iwd` and
  `prosmoke_<map>.iwd`, log `%LOCALAPPDATA%\prosmoke\bridge.log`.
- Activation is now the presence of `prosmoke\prosmoke.dll` beside the game
  executable; the receipt file is gone. The activation probe test covers it.
- Renderer and bridge rebuilt after the rename; policy, carve and growth probes
  pass; all 364 proxy exports keep their ordinals and names.
- `smoke/tests` (package layout and names, setup script install/reinstall/update/
  undo/refusals/dry-run launch, activation, baker package validation) pass.
- Still not covered offline: real detection dialogs, a live game launch, and a
  dedicated server publishing the policy with `sets`.
