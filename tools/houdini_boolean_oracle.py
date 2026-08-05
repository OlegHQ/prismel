#!/usr/bin/env python3
"""Licensed Houdini Boolean 2.0 oracle for boolean_stress OBJ pairs.

Run this script with the `hython` shipped by Houdini. It intentionally uses
only HOM and the installed Boolean SOP; it is not imported by Prismel.
"""

import argparse
import csv
import math
import os
import sys
import time

import hou


OPERATIONS = {
    "union": ("union",),
    "intersection": ("intersect",),
    "difference": ("subtract", "a-b", "a minus b"),
    "shatter": ("shatter",),
}


def menu_choice(parm, words):
    template = parm.parmTemplate()
    labels = tuple(template.menuLabels())
    items = tuple(template.menuItems())
    for label, item in zip(labels, items):
        normalized = label.strip().lower().replace(" ", "")
        for word in words:
            if word.replace(" ", "") in normalized:
                return item
    raise RuntimeError(
        "parameter {!r} has no choice matching {}; choices are {}".format(
            parm.name(), words, labels
        )
    )


def labeled_parms(node, label):
    return [
        parm
        for parm in node.parms()
        if parm.parmTemplate().label().strip().lower() == label.lower()
    ]


def configure_boolean(node, operation, resolve_left, resolve_right):
    operation_parms = labeled_parms(node, "Operation")
    if len(operation_parms) != 1:
        raise RuntimeError(
            "expected one Boolean Operation parameter, found {}".format(
                [parm.name() for parm in operation_parms]
            )
        )
    operation_parms[0].set(menu_choice(operation_parms[0], OPERATIONS[operation]))

    # Both operands in the Prismel comparison corpus are closed oriented solids.
    # Resolve by menu label rather than undocumented internal token values.
    for parm in labeled_parms(node, "Treat As"):
        parm.set(menu_choice(parm, ("solid",)))

    for parm in labeled_parms(node, "Resolve self-intersections"):
        parm.set(bool(resolve_left))
    for parm in labeled_parms(node, "Remove self-intersections"):
        parm.set(bool(resolve_right))

    # Preserve triangles so polygon-reconstruction policy does not contaminate
    # the geometric and stability comparison.
    for parm in labeled_parms(node, "Detriangulate"):
        parm.set(menu_choice(parm, ("no polygons", "no polygon")))


def edge_metrics(geometry):
    incidence = {}
    finite = True
    volume6 = 0.0
    for point in geometry.iterPoints():
        p = point.position()
        finite = finite and all(math.isfinite(float(p[i])) for i in range(3))
    for primitive in geometry.iterPrims():
        vertices = primitive.vertices()
        if len(vertices) < 3:
            continue
        numbers = [vertex.point().number() for vertex in vertices]
        positions = [vertex.point().position() for vertex in vertices]
        for index, a in enumerate(numbers):
            b = numbers[(index + 1) % len(numbers)]
            edge = (a, b) if a < b else (b, a)
            incidence[edge] = incidence.get(edge, 0) + 1
        origin = positions[0]
        for index in range(1, len(positions) - 1):
            b = positions[index]
            c = positions[index + 1]
            volume6 += (
                float(origin[0]) * (float(b[1]) * float(c[2]) - float(b[2]) * float(c[1]))
                - float(origin[1]) * (float(b[0]) * float(c[2]) - float(b[2]) * float(c[0]))
                + float(origin[2]) * (float(b[0]) * float(c[1]) - float(b[1]) * float(c[0]))
            )
    boundary = sum(1 for count in incidence.values() if count == 1)
    nonmanifold = sum(1 for count in incidence.values() if count > 2)
    odd = sum(1 for count in incidence.values() if count < 2 or count % 2 != 0)
    return finite, boundary, nonmanifold, odd, abs(volume6 / 6.0)


def case_policies(input_dir):
    path = os.path.join(input_dir, "cases.csv")
    if not os.path.isfile(path):
        return {}
    with open(path, newline="", encoding="utf-8") as source:
        return {
            row["case"]: (
                row["resolve_left_self_intersections"].lower() == "true",
                row["resolve_right_self_intersections"].lower() == "true",
            )
            for row in csv.DictReader(source)
        }


def cases(input_dir):
    policies = case_policies(input_dir)
    suffix = "_left.obj"
    for filename in sorted(os.listdir(input_dir)):
        if not filename.endswith(suffix):
            continue
        name = filename[: -len(suffix)]
        left = os.path.join(input_dir, filename)
        right = os.path.join(input_dir, name + "_right.obj")
        if not os.path.isfile(right):
            raise RuntimeError("missing paired input {}".format(right))
        resolve_left, resolve_right = policies.get(name, (False, False))
        yield name, left, right, resolve_left, resolve_right


def run_case(
    network,
    output_dir,
    name,
    left_path,
    right_path,
    operation,
    resolve_left,
    resolve_right,
):
    left = network.createNode("file", node_name="left")
    right = network.createNode("file", node_name="right")
    boolean = network.createNode("boolean", node_name="boolean")
    try:
        left.parm("file").set(left_path)
        right.parm("file").set(right_path)
        boolean.setInput(0, left)
        boolean.setInput(1, right)
        configure_boolean(boolean, operation, resolve_left, resolve_right)
        started = time.perf_counter()
        geometry = boolean.geometry()
        elapsed = time.perf_counter() - started
        errors = tuple(boolean.errors())
        warnings = tuple(boolean.warnings())
        finite, boundary, nonmanifold, odd, volume = edge_metrics(geometry)
        valid_edges = odd == 0 if operation == "shatter" else boundary == 0 and nonmanifold == 0
        status = "pass" if finite and valid_edges and not errors else "fail"
        geometry.saveToFile(os.path.join(output_dir, name + "_" + operation + ".obj"))
        return {
            "case": name,
            "operation": operation,
            "status": status,
            "engine": "houdini",
            "engine_version": hou.applicationVersionString(),
            "seconds": "{:.9f}".format(elapsed),
            "points": geometry.pointCount(),
            "primitives": geometry.primCount(),
            "boundary_edges": boundary,
            "nonmanifold_edges": nonmanifold,
            "odd_incidence_edges": odd,
            "absolute_signed_volume": "{:.17g}".format(volume),
            "warnings": " | ".join(warnings),
            "error": " | ".join(errors),
        }
    finally:
        boolean.destroy()
        right.destroy()
        left.destroy()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir")
    parser.add_argument("output_dir")
    parser.add_argument(
        "--operations",
        default="union,intersection,difference,shatter",
        help="comma-separated common Houdini/Prismel operation names",
    )
    args = parser.parse_args()
    input_dir = os.path.abspath(args.input_dir)
    output_dir = os.path.abspath(args.output_dir)
    os.makedirs(output_dir, exist_ok=True)
    operations = tuple(value.strip() for value in args.operations.split(",") if value.strip())
    unknown = tuple(value for value in operations if value not in OPERATIONS)
    if unknown:
        parser.error("unsupported operation(s): {}".format(", ".join(unknown)))

    hou.hipFile.clear(suppress_save_prompt=True)
    container = hou.node("/obj").createNode("geo", node_name="boolean_oracle")
    for child in container.children():
        child.destroy()
    fields = (
        "case",
        "operation",
        "status",
        "engine",
        "engine_version",
        "seconds",
        "points",
        "primitives",
        "boundary_edges",
        "nonmanifold_edges",
        "odd_incidence_edges",
        "absolute_signed_volume",
        "warnings",
        "error",
    )
    report_path = os.path.join(output_dir, "houdini.csv")
    failures = 0
    with open(report_path, "w", newline="", encoding="utf-8") as report:
        writer = csv.DictWriter(report, fieldnames=fields)
        writer.writeheader()
        for name, left_path, right_path, resolve_left, resolve_right in cases(input_dir):
            for operation in operations:
                try:
                    row = run_case(
                        container,
                        output_dir,
                        name,
                        left_path,
                        right_path,
                        operation,
                        resolve_left,
                        resolve_right,
                    )
                except Exception as error:  # Preserve the whole campaign report.
                    row = {field: "" for field in fields}
                    row.update(
                        case=name,
                        operation=operation,
                        status="error",
                        engine="houdini",
                        engine_version=hou.applicationVersionString(),
                        error=repr(error),
                    )
                if row["status"] != "pass":
                    failures += 1
                writer.writerow(row)
                report.flush()
    hou.releaseLicense()
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
