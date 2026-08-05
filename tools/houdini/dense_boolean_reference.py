#!/usr/bin/env python3
"""Dense clean-room Boolean scale reference using Houdini test geometry.

Pig Head and Rubber Toy are converted to closed polygon surfaces through the
same VDB-remesh network at several voxel sizes.  The authored OBJ operands are
the exact inputs consumed by Prismel's external Boolean benchmark; generated
assets remain machine-local and must not be committed.
"""

import argparse
import hashlib
import json
import os
import statistics
import struct
import sys
import time

import hou


def set_menu(node, name, item):
    parm = node.parm(name)
    if parm is None or item not in parm.parmTemplate().menuItems():
        raise RuntimeError("{} does not expose menu item {!r}".format(name, item))
    parm.set(item)


def set_if_present(node, name, value):
    parm = node.parm(name)
    if parm is not None:
        parm.set(value)


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


def edge_metrics(geometry):
    incidence = {}
    triangle_count = 0
    vertex_count = 0
    signed_volume = 0.0
    for primitive in geometry.iterPrims():
        vertices = list(primitive.vertices())
        points = [vertex.point().number() for vertex in vertices]
        positions = [vertex.point().position() for vertex in vertices]
        vertex_count += len(points)
        triangle_count += max(0, len(points) - 2)
        for index, first in enumerate(points):
            second = points[(index + 1) % len(points)]
            edge = (first, second) if first < second else (second, first)
            incidence[edge] = incidence.get(edge, 0) + 1
        if len(positions) >= 3:
            a = positions[0]
            for index in range(1, len(positions) - 1):
                b = positions[index]
                c = positions[index + 1]
                signed_volume += a.dot(b.cross(c)) / 6.0
    bounds = geometry.boundingBox()
    return {
        "points": geometry.pointCount(),
        "primitives": geometry.primCount(),
        "vertices": vertex_count,
        "triangles": triangle_count,
        "edges": len(incidence),
        "boundary_edges": sum(value == 1 for value in incidence.values()),
        "nonmanifold_edges": sum(value > 2 for value in incidence.values()),
        "odd_incidence_edges": sum(value % 2 != 0 for value in incidence.values()),
        "signed_volume": signed_volume,
        "bounds_min": list(bounds.minvec()),
        "bounds_max": list(bounds.maxvec()),
        "sha256": mesh_signature(geometry),
    }


def validate_closed(name, metrics):
    if metrics["points"] == 0 or metrics["primitives"] == 0:
        raise RuntimeError("{} produced empty geometry".format(name))
    if metrics["boundary_edges"] or metrics["nonmanifold_edges"]:
        raise RuntimeError(
            "{} is not closed two-manifold (boundary={}, nonmanifold={})".format(
                name, metrics["boundary_edges"], metrics["nonmanifold_edges"]
            )
        )


def write_obj(path, geometry):
    with open(path, "w", encoding="utf-8") as stream:
        for point in geometry.iterPoints():
            stream.write("v {:.17g} {:.17g} {:.17g}\n".format(*point.position()))
        for primitive in geometry.iterPrims():
            points = [vertex.point().number() + 1 for vertex in primitive.vertices()]
            if len(points) < 3:
                raise RuntimeError("{} contains a non-polygon primitive".format(path))
            stream.write("f {}\n".format(" ".join(str(point) for point in points)))


def vdb_remesh(network, source_type, name, voxel_size, transform=None):
    source = network.createNode(source_type, node_name=name + "_source")
    set_if_present(source, "difficulty", 1 if source_type == "testgeometry_pighead" else 0)
    set_if_present(source, "addshader", False)
    current = source
    if transform is not None:
        translate, rotate, scale = transform
        xform = network.createNode("xform", node_name=name + "_transform")
        xform.setInput(0, current)
        xform.parmTuple("t").set(translate)
        xform.parmTuple("r").set(rotate)
        xform.parm("scale").set(scale)
        set_if_present(xform, "updatenmls", False)
        current = xform
    vdb = network.createNode("vdbfrompolygons", node_name=name + "_vdb")
    vdb.setInput(0, current)
    vdb.parm("voxelsize").set(voxel_size)
    vdb.parm("builddistance").set(True)
    vdb.parm("buildfog").set(False)
    vdb.parm("useworldspaceunits").set(False)
    vdb.parm("exteriorbandvoxels").set(3)
    vdb.parm("interiorbandvoxels").set(3)
    vdb.parm("fillinterior").set(False)
    vdb.parm("unsigneddist").set(False)
    vdb.parm("preserveholes").set(False)
    convert = network.createNode("convertvdb", node_name=name + "_mesh")
    convert.setInput(0, vdb)
    set_menu(convert, "conversion", "poly")
    convert.parm("isovalue").set(0.0)
    convert.parm("adaptivity").set(0.0)
    convert.parm("internaladaptivity").set(0.0)
    convert.parm("computenormals").set(False)
    convert.parm("transferattributes").set(False)
    convert.parm("sharpenfeatures").set(False)
    divide = network.createNode("divide", node_name=name + "_triangles")
    divide.setInput(0, convert)
    divide.parm("convex").set(True)
    divide.parm("usemaxsides").set(True)
    divide.parm("numsides").set(3)
    divide.parm("planar").set(False)
    divide.parm("noslivers").set(False)
    divide.parm("avoidsmallangles").set(False)
    return divide


def configure_boolean(node, operation):
    set_menu(node, "asurface", "solid")
    set_menu(node, "bsurface", "solid")
    node.parm("resolvea").set(False)
    node.parm("resolveb").set(False)
    set_menu(node, "detriangulate", "none")
    node.parm("removeinlinepoints").set(False)
    node.parm("collapsetinyedges").set(False)
    if operation == "difference":
        set_menu(node, "booleanop", "subtract")
        set_menu(node, "subtractchoices", "aminusb")
    elif operation == "intersection":
        set_menu(node, "booleanop", "intersect")
    elif operation == "union":
        set_menu(node, "booleanop", "union")
    else:
        raise RuntimeError("unsupported operation {}".format(operation))


def voxel_label(voxel_size):
    return ("{:.6g}".format(voxel_size)).replace("-", "m").replace(".", "p")


def parse_voxels(value):
    result = [float(item.strip()) for item in value.split(",") if item.strip()]
    if not result or any(value <= 0.0 for value in result):
        raise argparse.ArgumentTypeError("voxel sizes must be positive")
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir")
    parser.add_argument(
        "--voxels",
        type=parse_voxels,
        default=parse_voxels("0.14,0.10,0.075,0.055,0.025,0.015"),
    )
    parser.add_argument("--operation", choices=("difference", "intersection", "union"), default="difference")
    parser.add_argument("--repeats", type=int, default=5)
    parser.add_argument(
        "--reuse-existing",
        action="store_true",
        help="benchmark previously generated OBJ operands without retaining VDB nodes",
    )
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")

    output_dir = os.path.abspath(args.output_dir)
    os.makedirs(output_dir, exist_ok=True)
    hou.hipFile.clear(suppress_save_prompt=True)
    network = hou.node("/obj").createNode("geo", node_name="dense_boolean_reference")
    for child in network.children():
        child.destroy()

    cases = []
    failures = []
    for voxel_size in args.voxels:
        label = voxel_label(voxel_size)
        left_path = os.path.join(output_dir, "dense_boolean_{}_left.obj".format(label))
        right_path = os.path.join(output_dir, "dense_boolean_{}_right.obj".format(label))
        pig_source_metrics = None
        toy_source_metrics = None
        if args.reuse_existing:
            generation_seconds = 0.0
            if not os.path.isfile(left_path) or not os.path.isfile(right_path):
                raise RuntimeError("missing existing operands for voxel {}".format(voxel_size))
        else:
            started = time.perf_counter()
            pig = vdb_remesh(network, "testgeometry_pighead", "pig_" + label, voxel_size)
            toy = vdb_remesh(
                network,
                "testgeometry_rubbertoy",
                "toy_" + label,
                voxel_size,
                transform=((0.28, -0.42, 0.16), (7.0, 23.0, -11.0), 0.92),
            )
            pig_geometry = pig.geometry()
            toy_geometry = toy.geometry()
            generation_seconds = time.perf_counter() - started
            if pig_geometry is None or toy_geometry is None:
                raise RuntimeError("VDB remesh produced no geometry")
            pig_source_metrics = edge_metrics(pig_geometry)
            toy_source_metrics = edge_metrics(toy_geometry)
            validate_closed("pig VDB remesh", pig_source_metrics)
            validate_closed("rubber toy VDB remesh", toy_source_metrics)
            write_obj(left_path, pig_geometry)
            write_obj(right_path, toy_geometry)

        pig_file = network.createNode("file", node_name="pig_file_{}".format(label))
        toy_file = network.createNode("file", node_name="toy_file_{}".format(label))
        pig_file.parm("file").set(left_path)
        toy_file.parm("file").set(right_path)
        pig_file.cook(force=True)
        toy_file.cook(force=True)
        pig_reverse = network.createNode("reverse", node_name="pig_reverse_{}".format(label))
        toy_reverse = network.createNode("reverse", node_name="toy_reverse_{}".format(label))
        pig_reverse.setInput(0, pig_file)
        toy_reverse.setInput(0, toy_file)
        imported_pig = pig_reverse.geometry()
        imported_toy = toy_reverse.geometry()
        pig_metrics = edge_metrics(imported_pig)
        toy_metrics = edge_metrics(imported_toy)
        validate_closed("imported pig input", pig_metrics)
        validate_closed("imported rubber toy input", toy_metrics)
        if pig_source_metrics is not None:
            if (pig_metrics["points"], pig_metrics["primitives"]) != (
                pig_source_metrics["points"], pig_source_metrics["primitives"]
            ):
                raise RuntimeError("OBJ round trip changed pig-head cardinality")
            if (toy_metrics["points"], toy_metrics["primitives"]) != (
                toy_source_metrics["points"], toy_source_metrics["primitives"]
            ):
                raise RuntimeError("OBJ round trip changed rubber-toy cardinality")
            if pig_metrics["sha256"] != pig_source_metrics["sha256"]:
                raise RuntimeError("corrected OBJ round trip changed the pig-head operand")
            if toy_metrics["sha256"] != toy_source_metrics["sha256"]:
                raise RuntimeError("corrected OBJ round trip changed the rubber-toy operand")

        fresh_seconds = []
        fresh_signatures = []
        boolean = None
        cold_geometry = None
        for repeat in range(args.repeats):
            candidate = network.createNode(
                "boolean", node_name="boolean_{}_fresh_{}".format(label, repeat)
            )
            candidate.setInput(0, pig_reverse)
            candidate.setInput(1, toy_reverse)
            configure_boolean(candidate, args.operation)
            fresh_started = time.perf_counter()
            candidate.cook(force=True)
            fresh_geometry = candidate.geometry()
            fresh_seconds.append(time.perf_counter() - fresh_started)
            if fresh_geometry is None:
                raise RuntimeError("Boolean SOP produced no geometry")
            fresh_signatures.append(mesh_signature(fresh_geometry))
            if repeat == 0:
                boolean = candidate
                cold_geometry = fresh_geometry
            else:
                candidate.destroy()
        cold_seconds = fresh_seconds[0]
        if cold_geometry is None:
            raise RuntimeError("Boolean SOP produced no geometry")
        cold_signature = mesh_signature(cold_geometry)
        warm_seconds = []
        warm_signatures = []
        output_geometry = cold_geometry
        for _ in range(args.repeats):
            warm_started = time.perf_counter()
            boolean.cook(force=True)
            output_geometry = boolean.geometry()
            warm_seconds.append(time.perf_counter() - warm_started)
            warm_signatures.append(mesh_signature(output_geometry))
        errors = list(boolean.errors())
        warnings = list(boolean.warnings())
        output_metrics = edge_metrics(output_geometry)
        output_path = os.path.join(
            output_dir, "dense_boolean_{}_houdini.obj".format(label)
        )
        write_obj(output_path, output_geometry)
        try:
            validate_closed("Boolean output", output_metrics)
        except RuntimeError as error:
            failures.append(str(error))
        stable = all(
            signature == cold_signature
            for signature in fresh_signatures + warm_signatures
        )
        if not stable:
            failures.append("voxel {} produced unstable Houdini topology".format(voxel_size))
        if errors:
            failures.extend(errors)
        case = {
            "voxel_size": voxel_size,
            "operation": args.operation,
            "left_obj": left_path,
            "right_obj": right_path,
            "output_obj": output_path,
            "generation_seconds": generation_seconds,
            "cold_boolean_seconds": cold_seconds,
            "fresh_boolean_seconds": fresh_seconds,
            "median_fresh_boolean_seconds": statistics.median(fresh_seconds),
            "warm_boolean_seconds": warm_seconds,
            "median_warm_boolean_seconds": statistics.median(warm_seconds),
            "stable": stable,
            "left": pig_metrics,
            "right": toy_metrics,
            "left_vdb_source_sha256": (
                pig_source_metrics["sha256"] if pig_source_metrics is not None else None
            ),
            "right_vdb_source_sha256": (
                toy_source_metrics["sha256"] if toy_source_metrics is not None else None
            ),
            "output": output_metrics,
            "errors": errors,
            "warnings": warnings,
        }
        cases.append(case)
        print(json.dumps(case, sort_keys=True), flush=True)

    result = {
        "engine": "houdini",
        "engine_version": hou.applicationVersionString(),
        "license": hou.licenseCategory().name(),
        "node_type": "boolean",
        "operation": args.operation,
        "vdb_adaptivity": 0.0,
        "operand_triangulation": {
            "node_type": "divide",
            "convex": True,
            "maximum_sides": 3,
            "planarize": False,
        },
        "obj_file_winding_correction": "reverse_sop_outside_timed_boolean",
        "toy_transform": {
            "translate": [0.28, -0.42, 0.16],
            "rotate_degrees": [7.0, 23.0, -11.0],
            "uniform_scale": 0.92,
        },
        "cases": cases,
        "failures": failures,
    }
    result_path = os.path.join(output_dir, "dense_boolean_houdini.json")
    with open(result_path, "w", encoding="utf-8") as stream:
        json.dump(result, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(result, sort_keys=True))
    hou.releaseLicense()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
