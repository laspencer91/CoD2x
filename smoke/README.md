# Volumetric smoke test branch

This local branch adds the CoD2x integration and prebuilt smoke runtime. It has not
been pushed or approved for competitive/general-player distribution.

## Contents

- `src/mss32/smoke_diagnostics.*`, `policy.hpp`: the small client bridge and settings.
- `src/mss32/mapkit_reload.*`: optional local Map Kit archive-release/reload bridge.
- `smoke/prebuilt`: ready-to-test binaries, compiled shaders, noise, all 15 stock-map
  occupancy grids, 21 separate optional custom/test occupancy packages and setup scripts.
- `tools/smoke-bake`: optional compiled-map occupancy baker (prebuilt voxelizer plus
  standard-library Python BSP exporter/package wrapper). See its
  [bake and installation instructions](../tools/smoke-bake/README.md#bake-and-install)
  for output paths and where to copy the occupancy IWD.
- `smoke/Build-Test.ps1`: rebuild the CoD2x bridge and assemble a fresh test ZIP using
  the pinned prebuilt smoke component.

The smoke simulation/rendering implementation and shader source stay in the existing
separate workspace. This branch carries the native interface and prebuilt component;
it does not copy the map editor, geometry compiler, lightmapper or source archive.
Existing license and attribution notices are retained. Public distribution/source
availability terms still need to be settled before publishing this binary-component layout.

## Review and test

Send testers `smoke/out/cod2x-smoke-player.zip` (build with
`./smoke/Package-Test.ps1 -PlayerOnly`). It contains only the desktop tool,
setup/restore script, runtime, default smoke look, all 15 stock-map bakes,
compatibility/integrity metadata, short instructions and license notices.
Tests, sources, Python, developer notes and custom-map bakes are excluded.
The full `cod2x-smoke-test.zip` retains authoring tools and optional custom bakes.

Open `CoD2SmokeTool.exe` in the extracted ZIP, check the detected game folder,
and click **Try smoke**. CoD2x must already be installed in the selected CoD2 1.3
folder. The tool checks the CoD2x loader and original sound library before enabling
Try smoke or Launch installed; install/reinstall CoD2x and click Recheck if missing.
Existing installations, including Steam, are supported.
It validates compatibility, backs up replaced client files, installs and launches
Toujane. **Restore original files** returns the previous client. A separate game
copy is optional. The game picker and two main actions are shown first; additional
controls and logs are under **Tools & details**. The full ZIP offers **Map authoring**
there and includes private Python for baking. WebView2 is required. See the
[desktop tool guide](../tools/smoke-tool/README.md). No app installer is used.
The prebuilt EXE in the branch is staged with `tools/smoke-tool/Build-Desktop.ps1`;
it can run player actions directly from `smoke/prebuilt`. Assemble the full ZIP
with `smoke/Package-Test.ps1` to use the baker.

The command-line setup remains available. Read `prebuilt/READ-ME-FIRST.txt` and `prebuilt/TESTING-NOTES.txt`.
Run `prebuilt/Setup-Smoke-Test.cmd`, select your installation's `CoD2MP_s.exe`,
then run `prebuilt/Start-Smoke-Test.cmd`. `Uninstall-Smoke-Test.cmd` restores backed-up
files. No Steam installation is modified by this branch's assembly tools.

The current runtime uses compiled `smoke.shaders`, with no HLSL dependency. Setup
checks file hashes and the supported stock DX9 renderer. Missing/invalid occupancy,
policy or GPU depth capability preserves stock smoke. The experimental particle
mode and latest reliability changes still require live acceptance.

`COD2_SMOKE_DIAGNOSTICS=1` and `COD2_SMOKE_RENDER=1` are explicit test opt-ins supplied
by Start. `COD2_SMOKE_DEV` is cleared; normal tests use packaged, BSP-bound grids.
The existing `sv_mapkit_smoke_policy` remains server-controlled; resolution is local.

The Windows branch build defaults `COD2X_SMOKE_TEST_BUILD=ON`. This disables stable
update checks/download replacement in the test binary, preventing a stable update
from replacing this branch's bridge. No public update endpoint/channel is changed.
Set the option OFF for a build with smoke opt-in disabled and upstream update behavior.

## Build

The bridge uses the upstream 32-bit MinGW/NASM/OpenSSL toolchain. The smoke component
was built separately with MSVC x86 and is supplied prebuilt. Only the bridge is rebuilt
here; no MSVC renderer build or private source checkout is required.

```powershell
.\smoke\Build-Test.ps1 -ToolchainDirectory C:\Toolchains\cod2-mingw -CMake cmake -Ninja ninja
```

The toolchain root must contain `mingw32/bin/gcc.exe`, `mingw32/bin/g++.exe` and
`usr/bin/nasm.exe`. Override `-MsysDirectory` if the required MSYS utilities are elsewhere.
Output is `smoke/out/cod2x-smoke-test.zip` and its SHA256 sidecar. Temporary packaging
files are removed after success. Pass `-KeepExpanded` to retain `smoke/out/package/`;
that explicit mode preserves any previous expanded output for recovery.
The normal upstream CMake target `mss32` also builds the bridge; the helper additionally
stages the DLL, updates package hashes and creates the ZIP. It never installs or launches.

## Remaining work

See the testing notes for details: additional GPU support, complete particle ordering,
large-volume splitting, same-name map rebinding, round/killcam acceptance, authoritative
remote sky-shot transport, competitive admission/integrity and six cropped stock-map
bounds reviews remain open. The occupancy baker is not a lighting or full map compiler.
