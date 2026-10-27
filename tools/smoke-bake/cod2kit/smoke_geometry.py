"""Static surface geometry for the portable smoke collision snapshot."""

import math
import struct

from . import bsp
from .brushes import cross, dot

TRIANGLE = struct.Struct("<9fI")
COLLISION_VERTEX = struct.Struct("<I3f")
COLLISION_TRIANGLE_SIZE = 72
COLLISION_AABB = struct.Struct("<6fHHI")
COLLISION_PARTITION = struct.Struct("<HBBii")


def collision_points(data, offset, vertices):
    indices = struct.unpack_from("<3i", data, offset + 48)
    # CoD2 removes redundant convex-edge vertices and writes -1 for those indices.
    # Its plane plus barycentric U/V planes still describe the complete triangle.
    if any(i < -1 or i >= len(vertices) for i in indices):
        raise ValueError("Invalid collision triangle vertex")
    if -1 not in indices:
        return tuple(v for i in indices for v in vertices[i][1:])
    planes = struct.unpack_from("<12f", data, offset)
    if not all(math.isfinite(v) for v in planes):
        raise ValueError("Non-finite collision triangle planes")
    normal, u, v = planes[:3], planes[4:7], planes[8:11]
    uv, vn, nu = cross(u, v), cross(v, normal), cross(normal, u)
    determinant = dot(normal, uv)
    if not math.isfinite(determinant) or abs(determinant) < 1e-16:
        raise ValueError("Degenerate collision triangle planes")
    points = []
    for index, du, dv in zip(indices, (0, 1, 0), (0, 0, 1)):
        point = (
            vertices[index][1:]
            if index >= 0
            else tuple(
                (
                    planes[3] * uv[axis]
                    + (planes[7] + du) * vn[axis]
                    + (planes[11] + dv) * nu[axis]
                )
                / determinant
                for axis in range(3)
            )
        )
        points.extend(point)
    return tuple(points)


def world_triangles(
    payload, material_flags, model_data, contents_mask, sky_contents, sky_surface
):
    vertices = list(
        COLLISION_VERTEX.iter_unpack(payload(bsp.Lump.COLLISION_VERTICES, 16))
    )
    triangles = payload(bsp.Lump.COLLISION_TRIANGLES, COLLISION_TRIANGLE_SIZE)
    partitions = list(
        COLLISION_PARTITION.iter_unpack(payload(bsp.Lump.COLLISION_PARTITIONS, 12))
    )
    aabbs = list(COLLISION_AABB.iter_unpack(payload(bsp.Lump.COLLISION_AABBS, 32)))
    first = struct.unpack_from("<i", model_data, 32)[0]
    # World collision spans all its leaf trees, before the first brush submodel.
    end = (
        struct.unpack_from("<i", model_data, bsp.MODEL_RECORD_SIZE + 32)[0]
        if len(model_data) > bsp.MODEL_RECORD_SIZE
        else len(aabbs)
    )
    if not 0 <= first <= end <= len(aabbs):
        raise ValueError("Invalid world collision AABB range")
    selected = {}
    for node in aabbs[first:end]:
        material, children, partition = node[6:]
        if children:
            continue
        if material >= len(material_flags) or partition >= len(partitions):
            raise ValueError("Invalid collision material or partition")
        surface, contents = material_flags[material]
        if (
            contents & sky_contents
            or surface & sky_surface
            or not contents & contents_mask
        ):
            continue
        _, count, _, start, _ = partitions[partition]
        if start < 0 or (start + count) * COLLISION_TRIANGLE_SIZE > len(triangles):
            raise ValueError("Invalid collision triangle range")
        for index in range(start, start + count):
            selected[index] = selected.get(index, 0) | contents
    result = []
    for index, contents in sorted(selected.items()):
        points = collision_points(triangles, index * COLLISION_TRIANGLE_SIZE, vertices)
        if not all(math.isfinite(v) for v in points):
            raise ValueError("Non-finite collision vertex")
        result.append((*points, contents))
    return result


def transform(keys):
    origin = tuple(map(float, keys.get("origin", "0 0 0").split()))
    angles = tuple(map(float, keys.get("angles", "0 0 0").split()))
    scale = float(keys.get("modelscale", 1))
    if (
        len(origin) != 3
        or len(angles) != 3
        or scale <= 0
        or not all(math.isfinite(v) for v in (*origin, *angles, scale))
    ):
        raise ValueError("Invalid smoke prop transform")
    pitch, yaw, roll = map(math.radians, angles)
    cp, sp, cy, sy, cr, sr = (
        math.cos(pitch),
        math.sin(pitch),
        math.cos(yaw),
        math.sin(yaw),
        math.cos(roll),
        math.sin(roll),
    )
    axes = (
        (cp * cy, cp * sy, -sp),
        (sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, sr * cp),
        (cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp),
    )

    def apply(point):
        return tuple(
            origin[i] + scale * sum(point[j] * axes[j][i] for j in range(3))
            for i in range(3)
        )

    return apply


def prop_triangles(entities, game):
    raise ValueError("This standalone baker supports world/terrain occupancy only")
