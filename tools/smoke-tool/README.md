# CoD2 Smoke Tool

Portable Windows x64 companion for the smoke test kit. Extract the complete ZIP,
then open `CoD2SmokeTool.exe` in its root. Keep the EXE and supporting folders
together. No tool installer, system Python or Node.js is required to use it.
Microsoft Edge WebView2 Runtime is required; this portable build does not install
or download it automatically. There is no updater or background service.

Send testers **cod2x-smoke-player.zip**. It contains the GUI, installer, runtime
and all occupancy packages, with no baker, Python runtime or Python source.
The full **cod2x-smoke-test.zip** additionally includes the map authoring tool.

## Try smoke

1. Extract the complete ZIP and open `CoD2SmokeTool.exe`.
2. Check the detected game folder, or browse to your `CoD2MP_s.exe`.
3. Close CoD clients/servers and click **Try smoke**.

Your existing installation is supported, including Steam. No separate copy or map
bake is required. The tool detects previous selections, common folders, the CoD2
registry entry and Steam libraries, and selects a detected installation automatically.
Try smoke checks for launch conflicts before changing files, validates compatibility,
backs up replaced client files, installs the supplied runtime and stock occupancy,
then launches Toujane locally with DX9 and smoke enabled. Join a team and throw a smoke.
Shoot it to try carving. Visual coverage, particle ordering and FPS still need an
in-game check. An unsupported renderer is rejected before replacing client files.

**Restore original files** returns the client files backed up on the first install.
Repeat installs keep those original backups. Maps, player configs and unrelated
files are not installed over or removed by setup/restoration. Game-created logs and
configs remain. If a game is running or installed files have changed independently,
the tool reports the problem instead of killing the game or overwriting those edits.

The main screen shows the game picker, Try smoke and Restore original files.
**Tools & details** is collapsed until opened or an operation fails. It contains:

- **Check compatibility:** validate the bundle and supported DX9 renderer without
  changing game files.
- **Verify installed:** check the installed runtime hashes and DX9 renderer.
- **Launch installed:** verify the installation and launch the selected map without
  installing. The selected map also applies to the main Try smoke action.

## Authoring: bake occupancy

Open **Tools & details > Map authoring** in the full ZIP. The player ZIP and the
checkout's prebuilt runtime have no authoring entry. Baking files are required only
for Bake; their absence cannot block Try smoke, compatibility checks or restoration.

Choose one or more compiled `mp_*.d3dbsp` maps and an output folder. Radiant `.map`
sources must be compiled first. The tool uses its private embedded Python and
the supplied native voxelizer, with world/terrain collision and full bounds.
It checks tool hashes and validates the output before reporting success. Jobs
run off the UI thread, with an activity log. Only one operation runs at a time.
Wait for an operation to finish before closing the tool.

Output: `<output>/<map>/mapkit_smoke_<map>.iwd`. Keep that IWD intact and copy it
to `<CoD2>/mapkit_smoke_test/`, or the active server mod directory.
Distribute it to clients with the exact matching map. The package contains no
map BSP. Restart CoD2 after copying; regenerate occupancy when the BSP changes.
All 15 stock MP maps already have occupancy in the supplied setup payload.

**Validate bundle** checks files against the included SHA256 manifest. It detects
missing/changed files; it is not a signed authenticity or competitive admission check.
**Copy log** copies the visible activity log. No logs are sent anywhere.

## Build from the local branch

Requires Windows x64, Node.js, Rust with the MSVC build tools, and Python 3.10+
on the build machine. From the branch root:

```powershell
./tools/smoke-tool/Build-Desktop.ps1
./smoke/Package-Test.ps1
./smoke/Package-Test.ps1 -PlayerOnly
```

The build pins the official Python 3.14.10 embeddable archive by SHA256 and
retains its license. The interpreter is isolated from system site packages.
The GUI reuses the Map Kit CoD2 design tokens and Libre Baskerville font (license
included). Its installer actions call `Smoke-Test.ps1`; the baker calls
`tools/smoke-bake/bake.py`. Neither flow requires a rewrite of the smoke runtime.

`CoD2SmokeTool.exe --validate-bundle` performs the read-only bundle check without
opening a window. The application EXE is a local unsigned test build.
`--validate-runtime` checks only player dependencies and also works directly in
the checkout's `smoke/prebuilt` directory. The full authoring ZIP is required for baking.

Development checks:

```powershell
cd tools/smoke-tool
cargo test --manifest-path src-tauri/Cargo.toml
cargo clippy --manifest-path src-tauri/Cargo.toml --all-targets -- -D warnings
npx playwright install chromium
npm run build
npm run test:ui
```

The UI checks use a mocked Tauri command interface in a headless browser, including
screenshots at regular and compact sizes. They do not prove native dialog behavior
or an actual game connection. Test results and build caches are not shipped.
An optional native-backend integration test accepts `COD2_SMOKE_TOOL_TEST_BUNDLE`
(an assembled bundle directory) and `COD2_SMOKE_TOOL_TEST_MAP` (a local BSP path):
`cargo test --manifest-path src-tauri/Cargo.toml real_bundle_bake -- --ignored`.
It creates and removes its own temporary bake output; no game is launched.
