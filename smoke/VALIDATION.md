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
- The four branch checks pass:
  `python -B -m unittest discover -s smoke/tests -v`.
  They verify prebuilt file/source hashes, 32-bit PE targets, all shader variants,
  data-only occupancy contents and baker imports without Python site packages.
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

Live mode-2 particle coverage, additional GPUs, reset/round/killcam behavior,
multi-client authoritative carving, large-volume limits and cropped map bounds
remain acceptance work. These offline checks do not establish player FPS or
competitive readiness. Existing license/attribution terms remain in place; this
local binary-component layout has not been approved for public distribution.
