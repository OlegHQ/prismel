#!/usr/bin/env python3
"""Clean-room Houdini reference for a cube shattered by oriented planes.

The script authors both operands as ordinary OBJ, feeds those exact files to
Houdini's public Boolean SOP, and emits a machine-readable result summary. The
same OBJ pair is suitable for Prismel's external Boolean stress runner.
"""

import argparse
import hashlib
import json
import math
import os
import statistics
import struct
import sys
import time

import hou


OCAML_INT_MASK = (1 << 63) - 1
OFFSET_STREAM_START = 1 << 30


def rand_float_at(seed, index):
    """Mirror Prismel.Rand.float_at's documented deterministic index stream."""
    keyed = (seed & OCAML_INT_MASK) ^ (
        ((index + 0x11B54A32D192ED03) & OCAML_INT_MASK)
        * 0x1E3779B97F4A7C15
        & OCAML_INT_MASK
    )
    value = keyed ^ (keyed >> 30)
    value = value * 0x3F58476D1CE4E5B9 & OCAML_INT_MASK
    value ^= value >> 27
    value = value * 0x14D049BB133111EB & OCAML_INT_MASK
    value ^= value >> 31
    return (value >> 10) / 9007199254740992.0


def quaternion(seed, index):
    u1 = rand_float_at(seed, index * 3)
    u2 = rand_float_at(seed, index * 3 + 1)
    u3 = rand_float_at(seed, index * 3 + 2)
    a = math.sqrt(1.0 - u1)
    b = math.sqrt(u1)
    tau = 2.0 * math.pi
    value = (
        a * math.sin(tau * u2),
        a * math.cos(tau * u2),
        b * math.sin(tau * u3),
        b * math.cos(tau * u3),
    )
    length = math.sqrt(sum(component * component for component in value))
    return tuple(component / length for component in value)


def rotate(quaternion_value, point):
    qx, qy, qz, qw = quaternion_value
    px, py, pz = point
    xx = qx * qx
    yy = qy * qy
    zz = qz * qz
    xy = qx * qy
    xz = qx * qz
    yz = qy * qz
    wx = qw * qx
    wy = qw * qy
    wz = qw * qz
    return (
        (1.0 - 2.0 * (yy + zz)) * px
        + 2.0 * (xy - wz) * py
        + 2.0 * (xz + wy) * pz,
        2.0 * (xy + wz) * px
        + (1.0 - 2.0 * (xx + zz)) * py
        + 2.0 * (yz - wx) * pz,
        2.0 * (xz - wy) * px
        + 2.0 * (yz + wx) * py
        + (1.0 - 2.0 * (xx + yy)) * pz,
    )


def write_obj(path, points, faces):
    with open(path, "w", encoding="utf-8") as stream:
        for point in points:
            stream.write("v {:.17g} {:.17g} {:.17g}\n".format(*point))
        for face in faces:
            stream.write("f {}\n".format(" ".join(str(index + 1) for index in face)))


def operands(plane_count, seed, cube_size, plane_size, offset_jitter):
    half = cube_size * 0.5
    cube_points = [
        (-half, -half, -half),
        (half, -half, -half),
        (half, half, -half),
        (-half, half, -half),
        (-half, -half, half),
        (half, -half, half),
        (half, half, half),
        (-half, half, half),
    ]
    cube_faces = [
        (0, 3, 2, 1),
        (4, 5, 6, 7),
        (0, 1, 5, 4),
        (3, 7, 6, 2),
        (0, 4, 7, 3),
        (1, 2, 6, 5),
    ]
    plane_half = plane_size * 0.5
    source = [
        (-plane_half, 0.0, -plane_half),
        (plane_half, 0.0, -plane_half),
        (plane_half, 0.0, plane_half),
        (-plane_half, 0.0, plane_half),
    ]
    plane_points = []
    plane_faces = []
    for index in range(plane_count):
        first = len(plane_points)
        orientation = quaternion(seed, index)
        normal = rotate(orientation, (0.0, 1.0, 0.0))
        offset = (
            (2.0 * rand_float_at(seed, OFFSET_STREAM_START + index) - 1.0)
            * offset_jitter
        )
        plane_points.extend(
            tuple(rotated[axis] + normal[axis] * offset for axis in range(3))
            for rotated in (rotate(orientation, point) for point in source)
        )
        plane_faces.append((first, first + 1, first + 2, first + 3))
    return cube_points, cube_faces, plane_points, plane_faces


def edge_metrics(geometry):
    incidence = {}
    for primitive in geometry.iterPrims():
        points = [vertex.point().number() for vertex in primitive.vertices()]
        for index, first in enumerate(points):
            second = points[(index + 1) % len(points)]
            edge = (first, second) if first < second else (second, first)
            incidence[edge] = incidence.get(edge, 0) + 1
    return {
        "boundary_edges": sum(value == 1 for value in incidence.values()),
        "nonmanifold_edges": sum(value > 2 for value in incidence.values()),
        "odd_incidence_edges": sum(value % 2 != 0 for value in incidence.values()),
    }


def mesh_signature(geometry):
    digest = hashlib.sha256()
    digest.update(struct.pack(">QQ", geometry.pointCount(), geometry.primCount()))
    for point in geometry.iterPoints():
        digest.update(struct.pack(">ddd", *point.position()))
    for primitive in geometry.iterPrims():
        points = [vertex.point().number() for vertex in primitive.vertices()]
        digest.update(struct.pack(">Q", len(points)))
        for point in points:
            digest.update(struct.pack(">Q", point))
    return digest.hexdigest()


def set_menu(node, name, item):
    parm = node.parm(name)
    if parm is None or item not in parm.parmTemplate().menuItems():
        raise RuntimeError("{} does not expose menu item {!r}".format(name, item))
    parm.set(item)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir")
    parser.add_argument("--planes", type=int, default=50)
    parser.add_argument("--seed", type=int, default=7349)
    parser.add_argument("--cube-size", type=float, default=2.6)
    parser.add_argument("--plane-size", type=float, default=4.8)
    parser.add_argument("--offset-jitter", type=float, default=0.0)
    parser.add_argument("--repeats", type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.planes <= 400:
        parser.error("--planes must be between 1 and 400")
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    if not math.isfinite(args.offset_jitter) or args.offset_jitter < 0.0:
        parser.error("--offset-jitter must be finite and non-negative")

    output_dir = os.path.abspath(args.output_dir)
    os.makedirs(output_dir, exist_ok=True)
    left_path = os.path.join(output_dir, "shattered_cube_left.obj")
    right_path = os.path.join(output_dir, "shattered_cube_right.obj")
    output_path = os.path.join(output_dir, "shattered_cube_houdini.obj")
    result_path = os.path.join(output_dir, "shattered_cube_houdini.json")
    left_points, left_faces, right_points, right_faces = operands(
        args.planes, args.seed, args.cube_size, args.plane_size, args.offset_jitter
    )
    write_obj(left_path, left_points, left_faces)
    write_obj(right_path, right_points, right_faces)

    hou.hipFile.clear(suppress_save_prompt=True)
    network = hou.node("/obj").createNode("geo", node_name="shattered_cube_reference")
    for child in network.children():
        child.destroy()
    left = network.createNode("file", node_name="left_cube")
    right = network.createNode("file", node_name="cutting_planes")
    left.parm("file").set(left_path)
    right.parm("file").set(right_path)
    fresh_seconds = []
    fresh_signatures = []
    boolean = None
    geometry = None
    for repeat in range(args.repeats):
        candidate = network.createNode(
            "boolean", node_name="shatter_fresh_{}".format(repeat)
        )
        candidate.setInput(0, left)
        candidate.setInput(1, right)
        set_menu(candidate, "asurface", "solid")
        set_menu(candidate, "bsurface", "surface")
        set_menu(candidate, "booleanop", "shatter")
        set_menu(candidate, "shatterchoices", "apieces")
        set_menu(candidate, "detriangulate", "none")
        candidate.parm("resolvea").set(False)
        candidate.parm("resolveb").set(True)
        started = time.perf_counter()
        candidate.cook(force=True)
        fresh_geometry = candidate.geometry()
        fresh_seconds.append(time.perf_counter() - started)
        if fresh_geometry is None:
            raise RuntimeError("Boolean SOP produced no geometry")
        fresh_signatures.append(mesh_signature(fresh_geometry))
        if repeat == 0:
            boolean = candidate
            geometry = fresh_geometry
        else:
            candidate.destroy()
    cold_seconds = fresh_seconds[0]
    if geometry is None:
        raise RuntimeError("Boolean SOP produced no geometry")
    cold_signature = mesh_signature(geometry)
    warm_seconds = []
    warm_signatures = []
    for _ in range(args.repeats):
        started = time.perf_counter()
        boolean.cook(force=True)
        geometry = boolean.geometry()
        warm_seconds.append(time.perf_counter() - started)
        warm_signatures.append(mesh_signature(geometry))
    errors = list(boolean.errors())
    warnings = list(boolean.warnings())
    geometry.saveToFile(output_path)
    stable = all(
        signature == cold_signature for signature in fresh_signatures + warm_signatures
    )
    result = {
        "engine": "houdini",
        "engine_version": hou.applicationVersionString(),
        "license": hou.licenseCategory().name(),
        "operation": "shatter_pieces_of_a",
        "left_treatment": "solid",
        "right_treatment": "surface",
        "planes": args.planes,
        "seed": args.seed,
        "random_stream": "Prismel.Rand.float_at",
        "cube_size": args.cube_size,
        "plane_size": args.plane_size,
        "offset_jitter": args.offset_jitter,
        "offset_random_stream_start": OFFSET_STREAM_START,
        "cold_boolean_seconds": cold_seconds,
        "fresh_boolean_seconds": fresh_seconds,
        "median_fresh_boolean_seconds": statistics.median(fresh_seconds),
        "warm_boolean_seconds": warm_seconds,
        "median_warm_boolean_seconds": statistics.median(warm_seconds),
        "stable": stable,
        "sha256": mesh_signature(geometry),
        "points": geometry.pointCount(),
        "primitives": geometry.primCount(),
        "errors": errors,
        "warnings": warnings,
    }
    result.update(edge_metrics(geometry))
    with open(result_path, "w", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(result, sort_keys=True))
    hou.releaseLicense()
    failed_topology = (
        result["boundary_edges"] != 0
        or result["nonmanifold_edges"] != 0
        or result["odd_incidence_edges"] != 0
    )
    return 1 if errors or not stable or failed_topology else 0


if __name__ == "__main__":
    sys.exit(main())
