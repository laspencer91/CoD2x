"""COD2 world collision export for the portable smoke voxelizer.

This prepares offline data only. It does not install hooks, suppress stock FX or run a game.
Includes world brushes, terrain collision and rigid static prop surfaces.
Moving brush models and animated geometry still need runtime handling.
"""

import argparse
import hashlib
import math
import struct
import zlib
from pathlib import Path

from . import bsp, maptext, smoke_geometry
from .definitions import SPAWN_CLASSES
from .files import write_json

# COD2 content bits match the portable occupancy baker's solid/glass/clipshot mask.
CONTENTS_SOLID = 0x1
CONTENTS_GLASS = 0x10
CONTENTS_SKY = 0x800
CONTENTS_CLIPSHOT = 0x2000
SMOKE_CONTENTS_MASK = CONTENTS_SOLID | CONTENTS_GLASS | CONTENTS_CLIPSHOT
SURFACE_SKY = 0x4
SNAPSHOT_MAGIC = b"PSMC"
SNAPSHOT_VERSION = 2
SPAWN_HINT = 2
AXIAL_SIDES = 6

PLANE = struct.Struct("<4f")
BRUSH_SIDE = struct.Struct("<II")
BRUSH = struct.Struct("<HH")
SNAPSHOT_BRUSH = struct.Struct("<6f4I")
HINT = struct.Struct("<3fI")


def extract(data, game=None, *, props="rigid"):
    if props not in ("rigid", "ignore"):
        raise ValueError("Choose rigid or ignore static props for smoke occupancy")
    lumps = bsp.directory(data)

    def payload(index, record_size=None):
        entry = lumps[index]
        if record_size and entry["size"] % record_size:
            raise ValueError(f"BSP lump {int(index)} has truncated records")
        return data[entry["offset"] : entry["offset"] + entry["size"]]

    materials = payload(bsp.Lump.MATERIALS, bsp.MATERIAL_RECORD_SIZE)
    flags = [
        struct.unpack_from("<II", materials, offset + bsp.MATERIAL_NAME_SIZE)
        for offset in range(0, len(materials), bsp.MATERIAL_RECORD_SIZE)
    ]
    planes = list(PLANE.iter_unpack(payload(bsp.Lump.PLANES, PLANE.size)))
    sides = list(BRUSH_SIDE.iter_unpack(payload(bsp.Lump.BRUSH_SIDES, BRUSH_SIDE.size)))
    brushes = list(BRUSH.iter_unpack(payload(bsp.Lump.BRUSHES, BRUSH.size)))
    models = payload(bsp.Lump.MODELS, bsp.MODEL_RECORD_SIZE)
    if not models:
        raise ValueError("Missing COD2 world model")
    first, count = struct.unpack_from("<2i", models, 40)
    if first < 0 or count < 0 or first + count > len(brushes):
        raise ValueError("World brush range is outside the BSP")

    selected = []
    selected_planes = []
    side_at = 0
    skipped = 0
    for index, (side_count, material) in enumerate(brushes):
        if side_count < AXIAL_SIDES or side_at + side_count > len(sides):
            raise ValueError("Invalid COD2 brush side range")
        brush_sides = sides[side_at : side_at + side_count]
        side_at += side_count
        if not first <= index < first + count:
            continue
        if material >= len(flags):
            raise ValueError("Invalid COD2 brush material")
        surface, contents = flags[material]
        if (
            contents & CONTENTS_SKY
            or surface & SURFACE_SKY
            or not contents & SMOKE_CONTENTS_MASK
        ):
            skipped += 1
            continue
        distances = [
            struct.unpack("<f", struct.pack("<I", bits))[0]
            for bits, _ in brush_sides[:AXIAL_SIDES]
        ]
        lo = distances[0::2]
        hi = distances[1::2]
        if not all(math.isfinite(v) for v in distances) or any(
            a >= b for a, b in zip(lo, hi)
        ):
            raise ValueError("Invalid COD2 axial brush bounds")
        first_plane = len(selected_planes)
        for plane_index, _ in brush_sides[AXIAL_SIDES:]:
            if plane_index >= len(planes):
                raise ValueError("Invalid COD2 non-axial brush plane")
            plane = planes[plane_index]
            if (
                not all(math.isfinite(v) for v in plane)
                or sum(v * v for v in plane[:3]) < 1e-12
            ):
                raise ValueError("Invalid COD2 brush plane coordinates")
            selected_planes.append(plane)
        selected.append((*lo, *hi, first_plane, side_count - AXIAL_SIDES, contents, 0))
    if side_at != len(sides):
        raise ValueError("Unreferenced COD2 brush side records")
    if not selected:
        raise ValueError("No solid world brushes available for smoke baking")

    text = payload(bsp.Lump.ENTITIES).rstrip(b"\0").decode("utf8")
    entities = maptext.read(text)
    terrain = smoke_geometry.world_triangles(
        payload, flags, models, SMOKE_CONTENTS_MASK, CONTENTS_SKY, SURFACE_SKY
    )
    props, model_count, asset_hashes = (
        smoke_geometry.prop_triangles(entities, game) if game and props == "rigid" else ([], 0, {})
    )
    hints = []
    for entity in entities:
        keys = entity["keys"]
        if keys.get("classname") not in SPAWN_CLASSES:
            continue
        origin = tuple(map(float, keys.get("origin", "").split()))
        if len(origin) != 3 or not all(math.isfinite(v) for v in origin):
            raise ValueError("Invalid smoke spawn hint")
        hints.append((*origin, SPAWN_HINT))
    return {
        "planes": selected_planes,
        "brushes": selected,
        "hints": hints,
        "triangles": terrain + props,
        "terrainTriangles": len(terrain),
        "propTriangles": len(props),
        "staticModels": model_count,
        "assetHashes": asset_hashes,
        "excluded": {
            "worldClipOrSkyBrushes": skipped,
            "submodelBrushes": len(brushes) - count,
            "xmodels": sum(e["keys"].get("classname") == "misc_model" for e in entities)
            - model_count,
        },
    }


def export(source: Path, output: Path, game=None, *, data=None, bounds="hints", props="rigid"):
    if bounds not in ("hints", "collision"):
        raise ValueError("Choose hints or collision smoke bounds")
    if source.resolve() == output.resolve():
        raise ValueError("Smoke output must be separate from the BSP source")
    if data is None:
        data = source.read_bytes()
    collision = extract(data, game, props=props)
    # With no hints the portable baker covers the complete included collision
    # extent. Never crop stock-map routes merely because they lack nearby spawns.
    if bounds == "collision":
        collision["hints"] = []
    name = source.stem.encode("ascii")
    if not 0 < len(name) <= 256:
        raise ValueError("Invalid smoke snapshot map name")
    payload = bytearray(
        SNAPSHOT_MAGIC
        + struct.pack("<II", SNAPSHOT_VERSION, len(name))
        + name
        + struct.pack("<I", zlib.crc32(data))
    )
    for records, record in [
        (collision["planes"], PLANE),
        (collision["brushes"], SNAPSHOT_BRUSH),
        (collision["triangles"], smoke_geometry.TRIANGLE),
        ([], None),
        (collision["hints"], HINT),
    ]:
        payload.extend(struct.pack("<I", len(records)))
        for values in records:
            payload.extend(record.pack(*values))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(payload)
    report = {
        "source": str(source.resolve()),
        "sourceSha256": hashlib.sha256(data).hexdigest(),
        "snapshot": str(output.resolve()),
        "snapshotSha256": hashlib.sha256(payload).hexdigest(),
        "brushes": len(collision["brushes"]),
        "planes": len(collision["planes"]),
        "hints": len(collision["hints"]),
        "terrainTriangles": collision["terrainTriangles"],
        "propTriangles": collision["propTriangles"],
        "staticModels": collision["staticModels"],
        "assetHashes": collision["assetHashes"],
        "excluded": collision["excluded"],
        "boundsPolicy": bounds,
        "propsMode": props,
        "limitations": [
            ("Static prop meshes intentionally excluded from smoke occupancy; world brushes and terrain remain solid. Render depth still occludes smoke against props."
             if props == "ignore" else "Rigid static props use their highest-detail render mesh as conservative surface collision; masked materials and animated props are not validated."),
            "Moving brush entities are excluded. Without --game, static props are excluded.",
        ],
    }
    write_json(output.with_suffix(".json"), report)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bsp", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--game",
        type=Path,
        help="Prepared Map Kit game directory with extracted stock models",
    )
    args = parser.parse_args()
    report = export(args.bsp, args.output, args.game)
    print(
        f"Exported {report['brushes']} world brushes, {report['planes']} planes and {report['hints']} spawn hints to {args.output}"
    )
    print(
        f"Included {report['terrainTriangles']} world collision triangles and {report['propTriangles']} rigid prop triangles; moving geometry remains excluded."
    )


if __name__ == "__main__":
    main()
