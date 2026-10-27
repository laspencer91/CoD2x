"""COD2 IBSP v4 container layout and validation shared by all build stages."""

import struct
from enum import IntEnum
from pathlib import Path

BSP_MAGIC = b"IBSP"
BSP_VERSION = 4
BSP_LUMP_COUNT = 39
BSP_HEADER_SIZE = 8 + BSP_LUMP_COUNT * 8
MATERIAL_RECORD_SIZE = 72
MATERIAL_NAME_SIZE = 64
MODEL_RECORD_SIZE = 48


class Lump(IntEnum):
    MATERIALS = 0
    LIGHTMAPS = 1
    LIGHTGRID_ENTRIES = 2
    LIGHTGRID_COLORS = 3
    PLANES = 4
    BRUSH_SIDES = 5
    BRUSHES = 6
    SURFACES = 7
    DRAW_VERTICES = 8
    DRAW_INDICES = 9
    COLLISION_VERTICES = 29
    COLLISION_TRIANGLES = 31
    COLLISION_PARTITIONS = 33
    COLLISION_AABBS = 34
    MODELS = 35
    ENTITIES = 37


def directory(data):
    if len(data) < BSP_HEADER_SIZE:
        raise ValueError("Truncated COD2 BSP header")
    if data[:4] != BSP_MAGIC or struct.unpack_from("<I", data, 4)[0] != BSP_VERSION:
        raise ValueError("Not a COD2 IBSP v4 map")
    lumps = []
    for index in range(BSP_LUMP_COUNT):
        size, offset = struct.unpack_from("<2I", data, 8 + index * 8)
        if size and offset < BSP_HEADER_SIZE:
            raise ValueError(f"BSP lump {index} overlaps the header")
        if offset + size > len(data):
            raise ValueError(f"BSP lump {index} outside file")
        lumps.append(dict(index=index, size=size, offset=offset))
    spans = sorted(
        (lump["offset"], lump["offset"] + lump["size"], lump["index"])
        for lump in lumps
        if lump["size"]
    )
    for previous, current in zip(spans, spans[1:]):
        if current[0] < previous[1]:
            raise ValueError(f"BSP lumps {previous[2]} and {current[2]} overlap")
    return lumps


def inspect_bsp(path: Path):
    data = path.read_bytes()
    return dict(bytes=len(data), lumps=directory(data))
