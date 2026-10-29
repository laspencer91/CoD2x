"""Build and install smoke occupancy tied to the compiled COD2 map bytes."""

import hashlib
import json
import math
import shutil
import struct
import zipfile
import zlib
from pathlib import Path

from . import smoke_collision
from .files import write_json

BAKER_NAME = "cod2smoke-bake.exe"
GRID_HEADER = struct.Struct("<6I6f4I4Q")
GRID_MAGIC = 0x474D5350
GRID_VERSION = 2
BINDING = struct.Struct("<4sII")
BINDING_MAGIC = b"PSB1"
RUNTIME_DIRECTORY = "prosmoke"
MAX_GRID_BYTES = 16 * 1024 * 1024
CACHE_VERSION = 4
COLLISION_FIELDS = (
    "assetHashes",
    "worldBrushes",
    "terrainTriangles",
    "propTriangles",
    "staticModels",
    "limitations",
)


def inspect_grid(data):
    if len(data) > MAX_GRID_BYTES:
        raise ValueError("Smoke grid exceeds the runtime 16 MiB limit")
    if len(data) < GRID_HEADER.size:
        raise ValueError("Truncated smoke grid header")
    values = GRID_HEADER.unpack_from(data)
    magic, version, header_size, nx, ny, nz = values[:6]
    if (magic, version, header_size) != (GRID_MAGIC, GRID_VERSION, GRID_HEADER.size):
        raise ValueError("Unsupported smoke grid")
    if not all(0 < n <= 65535 for n in (nx, ny, nz)) or nx * ny * nz > 16_000_000:
        raise ValueError("Invalid smoke grid dimensions")
    if header_size + values[-1] != len(data):
        raise ValueError("Invalid smoke grid payload size")
    if not all(math.isfinite(v) for v in values[6:12]) or values[9] <= 0:
        raise ValueError("Invalid smoke grid coordinates")
    if values[-2] > nx * ny * nz:
        raise ValueError("Invalid smoke grid solid cell count")
    return {"dimensions": [nx, ny, nz], "solidCells": values[-2]}


def bake(workspace, source, output, run, progress=print, *, install_loose=True, bounds="hints", props="ignore"):
    if bounds not in ("hints", "collision"):
        raise ValueError("Choose hints or collision smoke bounds")
    if props not in ("rigid", "ignore"):
        raise ValueError("Choose rigid or ignore static props for smoke occupancy")
    workspace, source, output = workspace.resolve(), source.resolve(), output.resolve()
    tool = workspace / "tools/bin" / BAKER_NAME
    if not tool.is_file():
        progress(
            "Smoke grid skipped: native smoke baker is not installed; stock smoke remains available"
        )
        return None
    output.mkdir(parents=True, exist_ok=True)
    snapshot = output / (source.stem + ".smokecol")
    source_data = source.read_bytes()
    grid = output / (source.stem + ".smokegrid")
    temporary = grid.with_suffix(".smokegrid.pending")
    cache_key = {
        "version": CACHE_VERSION,
        "sourceSha256": hashlib.sha256(source_data).hexdigest(),
        "bakerSha256": hashlib.sha256(tool.read_bytes()).hexdigest(),
        "boundsPolicy": bounds,
        "propsMode": props,
    }
    manifest = output / "manifest.json"
    cached = False
    try:
        previous = json.loads(manifest.read_text(encoding="utf8"))
        data = grid.read_bytes()
        cached = (
            previous.get("cacheKey") == cache_key
            and previous.get("gridSha256") == hashlib.sha256(data).hexdigest()
            and all(
                hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest
                for path, digest in previous["assetHashes"].items()
            )
        )
        if cached:
            inspect_grid(data)
            details = {name: previous[name] for name in COLLISION_FIELDS}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        cached = False
    if not cached:
        collision = smoke_collision.export(
            source, snapshot, workspace / "game", data=source_data, bounds=bounds, props=props
        )
        details = {
            name: collision["brushes" if name == "worldBrushes" else name]
            for name in COLLISION_FIELDS
        }
        try:
            run([tool, snapshot, temporary], workspace / "game", progress)
            data = temporary.read_bytes()
            inspect_grid(data)
            temporary.replace(grid)
        finally:
            temporary.unlink(missing_ok=True)
    info = inspect_grid(data)
    header = GRID_HEADER.unpack_from(data)
    coordinates = dict(
        boundsPolicy=bounds,
        propsMode=props,
        boundsSource="collision" if header[14] == 0 else "hints",
        origin=list(header[6:9]),
        cellSize=header[9],
        worldMax=[header[6 + axis] + header[3 + axis] * header[9] for axis in range(3)],
        gridBytes=len(data),
    )
    binding = grid.with_suffix(".smokebind")
    binding_data = BINDING.pack(BINDING_MAGIC, zlib.crc32(source_data), zlib.crc32(data))
    if not binding.is_file() or binding.read_bytes() != binding_data:
        binding.write_bytes(binding_data)
    runtime = workspace / "game" / RUNTIME_DIRECTORY / "grids"
    runtime.mkdir(parents=True, exist_ok=True)
    for artifact in (grid, binding) if install_loose else ():
        destination = runtime / artifact.name
        staged = destination.with_suffix(destination.suffix + ".pending")
        shutil.copy2(artifact, staged)
        staged.replace(destination)
    report = dict(
        **info,
        **coordinates,
        sourceSha256=cache_key["sourceSha256"],
        gridSha256=hashlib.sha256(data).hexdigest(),
        **details,
        installed=str(runtime / grid.name),
        cacheKey=cache_key,
        cached=cached,
    )
    write_json(manifest, report)
    progress(
        f"Smoke occupancy: {info['dimensions']}, {info['solidCells']:,} solid cells, {details['staticModels']} rigid props (cached={cached})"
    )
    return report


def package_grid(package, name, output, report):
    """Ship the validated pair with its map, without workstation paths or assets."""
    def write(entry, data):
        info = zipfile.ZipInfo(entry, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        package.writestr(info, data)

    for suffix in (".smokegrid", ".smokebind"):
        write(f"maps/mp/{name}{suffix}", (output / (name + suffix)).read_bytes())
    public = {
        key: report[key]
        for key in (
            "dimensions",
            "solidCells",
            "sourceSha256",
            "gridSha256",
            "worldBrushes",
            "terrainTriangles",
            "propTriangles",
            "staticModels",
            "limitations",
        )
    }
    public.update(schema=1, map=name)
    public.update({key: report[key] for key in ("boundsPolicy", "propsMode", "boundsSource", "origin", "cellSize", "worldMax", "gridBytes", "boundsReviewRequired") if key in report})
    write(f"maps/mp/{name}.smoke.json", json.dumps(public, indent=2) + "\n")


# Command-line entry point: ../bake.py
