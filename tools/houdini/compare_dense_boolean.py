#!/usr/bin/env python3
"""Run the dense Houdini/Prismel Boolean scale gate on identical OBJ inputs."""

import argparse
import csv
import io
import json
import math
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys


DEFAULT_HYTHON = (
    "/Applications/Houdini/Houdini22.0.368/Frameworks/"
    "Houdini.framework/Versions/22.0/Resources/bin/hython"
)


def run(command, *, cwd, env=None):
    result = subprocess.run(
        command,
        cwd=cwd,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        raise RuntimeError(
            "command failed ({}):\n{}\n{}".format(
                result.returncode, " ".join(command), result.stdout, result.stderr
            )
        )
    return result.stdout, result.stderr


def one_csv_record(output):
    lines = [line for line in output.splitlines() if line.strip()]
    if len(lines) < 2:
        raise RuntimeError("benchmark emitted no CSV record:\n{}".format(output))
    return next(csv.DictReader(io.StringIO("\n".join(lines[-2:]))))


def canonical_obj_triangles(path):
    points = []
    triangles = []
    with open(path, encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, 1):
            words = line.split()
            if not words:
                continue
            if words[0] == "v" and len(words) >= 4:
                point = tuple(float(value) for value in words[1:4])
                if any(not math.isfinite(value) for value in point):
                    raise RuntimeError("{}:{} contains a non-finite point".format(path, line_number))
                points.append(point)
            elif words[0] == "f" and len(words) >= 4:
                face = []
                for token in words[1:]:
                    raw = int(token.split("/", 1)[0])
                    point = raw - 1 if raw > 0 else len(points) + raw
                    if point < 0 or point >= len(points):
                        raise RuntimeError("{}:{} contains an invalid face index".format(path, line_number))
                    face.append(point)
                for corner in range(1, len(face) - 1):
                    triangles.append(
                        tuple(sorted((points[face[0]], points[face[corner]], points[face[corner + 1]])))
                    )
    return sorted(triangles)


def canonical_surface_error(first_path, second_path):
    first = canonical_obj_triangles(first_path)
    second = canonical_obj_triangles(second_path)
    if len(first) != len(second):
        return math.inf
    return max(
        (abs(a - b) for first_triangle, second_triangle in zip(first, second)
         for first_point, second_point in zip(first_triangle, second_triangle)
         for a, b in zip(first_point, second_point)),
        default=0.0,
    )


def slope(xs, ys):
    if any(not math.isfinite(value) or value <= 0.0 for value in xs + ys):
        raise ValueError("log-log slope requires finite positive samples")
    logarithmic_x = [math.log(value) for value in xs]
    logarithmic_y = [math.log(value) for value in ys]
    mean_x = statistics.mean(logarithmic_x)
    mean_y = statistics.mean(logarithmic_y)
    denominator = sum((value - mean_x) ** 2 for value in logarithmic_x)
    if denominator == 0.0:
        return 0.0
    return sum(
        (x - mean_x) * (y - mean_y)
        for x, y in zip(logarithmic_x, logarithmic_y)
    ) / denominator


def voxel_label(voxel_size):
    return ("{:.6g}".format(voxel_size)).replace("-", "m").replace(".", "p")


def parse_voxels(value):
    values = [float(item.strip()) for item in value.split(",") if item.strip()]
    if (
        len(values) < 3
        or len(set(values)) < 3
        or any(not math.isfinite(value) or value <= 0.0 for value in values)
    ):
        raise argparse.ArgumentTypeError(
            "supply at least three distinct finite positive voxel sizes"
        )
    return values


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir")
    parser.add_argument(
        "--hython", default=os.environ.get("PRISMEL_HYTHON", DEFAULT_HYTHON)
    )
    parser.add_argument(
        "--voxels",
        type=parse_voxels,
        default=parse_voxels("0.14,0.10,0.075,0.055,0.025,0.015"),
    )
    parser.add_argument("--houdini-repeats", type=int, default=7)
    parser.add_argument("--prismel-repeats", type=int, default=7)
    parser.add_argument("--pipeline-repeats", type=int, default=7)
    parser.add_argument("--domains", type=int, default=max(1, os.cpu_count() or 1))
    parser.add_argument("--grain", type=int, default=128)
    parser.add_argument("--profile", choices=("dev", "release"), default="release")
    parser.add_argument(
        "--reuse-existing",
        action="store_true",
        help="reuse previously generated triangulated operands",
    )
    parser.add_argument("--max-scale-exponent", type=float, default=1.2)
    parser.add_argument("--max-allocation-exponent", type=float, default=1.2)
    parser.add_argument("--max-coordinate-error", type=float, default=1e-6)
    args = parser.parse_args()
    if min(args.houdini_repeats, args.prismel_repeats, args.pipeline_repeats) < 1:
        parser.error("repeat counts must be positive")
    if args.domains < 1 or args.grain < 1:
        parser.error("domains and grain must be positive")
    if not math.isfinite(args.max_scale_exponent) or args.max_scale_exponent <= 0.0:
        parser.error("--max-scale-exponent must be finite and positive")
    if (
        not math.isfinite(args.max_allocation_exponent)
        or args.max_allocation_exponent <= 0.0
    ):
        parser.error("--max-allocation-exponent must be finite and positive")
    if not math.isfinite(args.max_coordinate_error) or args.max_coordinate_error <= 0.0:
        parser.error("--max-coordinate-error must be finite and positive")

    root = Path(__file__).resolve().parents[2]
    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    reference_script = root / "tools" / "houdini" / "dense_boolean_reference.py"
    if not Path(args.hython).is_file():
        raise RuntimeError("hython executable not found: {}".format(args.hython))

    cases = []
    for voxel_size in args.voxels:
        label = voxel_label(voxel_size)
        print("dense Boolean voxel {}: Houdini".format(voxel_size), flush=True)
        houdini_command = [
            args.hython,
            str(reference_script),
            str(output_dir),
            "--voxels",
            str(voxel_size),
            "--repeats",
            str(args.houdini_repeats),
        ]
        if args.reuse_existing:
            houdini_command.append("--reuse-existing")
        run(houdini_command, cwd=root)
        with open(output_dir / "dense_boolean_houdini.json", encoding="utf-8") as stream:
            houdini_report = json.load(stream)
        matching = [
            case
            for case in houdini_report["cases"]
            if math.isclose(case["voxel_size"], voxel_size, rel_tol=0.0, abs_tol=1e-15)
        ]
        if len(matching) != 1:
            raise RuntimeError("Houdini report did not contain exactly one requested case")
        houdini = matching[0]
        left = Path(houdini["left_obj"])
        right = Path(houdini["right_obj"])
        prismel_output = output_dir / "dense_boolean_{}_prismel.obj".format(label)

        print("dense Boolean voxel {}: Prismel".format(voxel_size), flush=True)
        stress_stdout, _ = run(
            [
                "dune",
                "exec",
                "--profile",
                args.profile,
                "tools/boolean_stress.exe",
                "--",
                "--case",
                "dense_tri_vdb_{}".format(label),
                "--left-obj",
                str(left),
                "--right-obj",
                str(right),
                "--operation",
                "difference",
                "--domains",
                str(args.domains),
                "--grain",
                str(args.grain),
                "--repeats",
                str(args.prismel_repeats),
                "--output-obj",
                str(prismel_output),
            ],
            cwd=root,
        )
        stress = one_csv_record(stress_stdout)
        if stress["status"] != "pass":
            raise RuntimeError("Prismel stress validation failed: {}".format(stress["error"]))

        pipeline_env = os.environ.copy()
        pipeline_env.update(
            {
                "PRISMEL_BOOLEAN_LEFT_OBJ": str(left),
                "PRISMEL_BOOLEAN_RIGHT_OBJ": str(right),
                "PRISMEL_BOOLEAN_REPEATS": str(args.pipeline_repeats),
                "PRISMEL_BOOLEAN_GRAIN": str(args.grain),
                "PRISMEL_BENCH_DOMAINS": str(args.domains),
            }
        )
        pipeline_stdout, _ = run(
            [
                "dune",
                "exec",
                "--profile",
                args.profile,
                "tools/bench_boolean_pipeline.exe",
            ],
            cwd=root,
            env=pipeline_env,
        )
        pipeline = one_csv_record(pipeline_stdout)
        input_triangles = houdini["left"]["triangles"] + houdini["right"]["triangles"]
        prismel_volume = abs(float(stress["absolute_signed_volume"]))
        houdini_volume = abs(float(houdini["output"]["signed_volume"]))
        cases.append(
            {
                "voxel_size": voxel_size,
                "input_triangles": input_triangles,
                "candidate_pairs": int(pipeline["candidate_pairs"]),
                "houdini_cold_seconds": houdini["cold_boolean_seconds"],
                "houdini_median_fresh_seconds": houdini[
                    "median_fresh_boolean_seconds"
                ],
                "houdini_median_warm_seconds": houdini["median_warm_boolean_seconds"],
                "prismel_median_fresh_seconds": float(stress["median_seconds"]),
                "prismel_pipeline_seconds": float(pipeline["median_seconds"]),
                "prismel_allocated_bytes": float(
                    stress["median_current_domain_allocated_bytes"]
                ),
                "houdini_points": houdini["output"]["points"],
                "prismel_points": int(stress["points"]),
                "houdini_triangles": houdini["output"]["triangles"],
                "prismel_triangles": int(stress["primitives"]),
                "houdini_absolute_volume": houdini_volume,
                "prismel_absolute_volume": prismel_volume,
                "relative_volume_error": abs(prismel_volume - houdini_volume)
                / max(houdini_volume, sys.float_info.min),
                "surface_max_coordinate_error": canonical_surface_error(
                    houdini["output_obj"], prismel_output
                ),
                "houdini_stable": houdini["stable"],
                "prismel_one_multi_domain_exact": True,
                "prismel_vs_houdini_cold_ratio": float(stress["median_seconds"])
                / houdini["cold_boolean_seconds"],
                "prismel_vs_houdini_fresh_ratio": float(stress["median_seconds"])
                / houdini["median_fresh_boolean_seconds"],
                "prismel_vs_houdini_warm_ratio": float(stress["median_seconds"])
                / houdini["median_warm_boolean_seconds"],
            }
        )

    cases.sort(key=lambda case: case["input_triangles"])
    triangles = [case["input_triangles"] for case in cases]
    if len(set(triangles)) < 3:
        raise RuntimeError(
            "dense scale gate requires at least three distinct input triangle counts"
        )
    houdini_cold = [case["houdini_cold_seconds"] for case in cases]
    houdini_fresh = [case["houdini_median_fresh_seconds"] for case in cases]
    houdini_warm = [case["houdini_median_warm_seconds"] for case in cases]
    prismel_fresh = [case["prismel_median_fresh_seconds"] for case in cases]
    prismel_allocated = [case["prismel_allocated_bytes"] for case in cases]
    candidates = [max(1, case["candidate_pairs"]) for case in cases]
    exponents = {
        "houdini_cold": slope(triangles, houdini_cold),
        "houdini_fresh": slope(triangles, houdini_fresh),
        "houdini_warm": slope(triangles, houdini_warm),
        "prismel_fresh": slope(triangles, prismel_fresh),
        "prismel_allocated_bytes": slope(triangles, prismel_allocated),
        "prismel_candidate_pairs": slope(triangles, candidates),
    }
    failures = []
    for case in cases:
        if not case["houdini_stable"]:
            failures.append("Houdini topology was unstable at voxel {}".format(case["voxel_size"]))
        if case["houdini_points"] != case["prismel_points"]:
            failures.append("point cardinality differs at voxel {}".format(case["voxel_size"]))
        if case["houdini_triangles"] != case["prismel_triangles"]:
            failures.append("triangle cardinality differs at voxel {}".format(case["voxel_size"]))
        if case["relative_volume_error"] > 1e-7:
            failures.append("volume differs at voxel {}".format(case["voxel_size"]))
        if case["surface_max_coordinate_error"] > args.max_coordinate_error:
            failures.append(
                "surface coordinates differ at voxel {} (error {:.3g})".format(
                    case["voxel_size"], case["surface_max_coordinate_error"]
                )
            )
    if exponents["prismel_fresh"] > args.max_scale_exponent:
        failures.append(
            "Prismel time exponent {:.3f} exceeds {:.3f}".format(
                exponents["prismel_fresh"], args.max_scale_exponent
            )
        )
    if exponents["prismel_candidate_pairs"] > args.max_scale_exponent:
        failures.append(
            "candidate exponent {:.3f} exceeds {:.3f}".format(
                exponents["prismel_candidate_pairs"], args.max_scale_exponent
            )
        )
    if exponents["prismel_allocated_bytes"] > args.max_allocation_exponent:
        failures.append(
            "Prismel allocation exponent {:.3f} exceeds {:.3f}".format(
                exponents["prismel_allocated_bytes"], args.max_allocation_exponent
            )
        )

    report = {
        "fixture": "vdb_remeshed_pig_head_minus_rubber_toy",
        "operands_triangulated": True,
        "houdini_version": houdini_report["engine_version"],
        "houdini_license": houdini_report["license"],
        "domains": args.domains,
        "grain": args.grain,
        "prismel_compiler_profile": args.profile,
        "houdini_repeats": args.houdini_repeats,
        "prismel_repeats": args.prismel_repeats,
        "pipeline_repeats": args.pipeline_repeats,
        "max_scale_exponent": args.max_scale_exponent,
        "max_allocation_exponent": args.max_allocation_exponent,
        "max_coordinate_error": args.max_coordinate_error,
        "machine": {
            "platform": platform.platform(),
            "processor": platform.processor(),
            "logical_cpus": os.cpu_count(),
        },
        "scale_exponents": exponents,
        "cases": cases,
        "failures": failures,
    }
    report_path = output_dir / "dense_boolean_comparison.json"
    with open(report_path, "w", encoding="utf-8") as stream:
        json.dump(report, stream, indent=2, sort_keys=True)
        stream.write("\n")
    print(json.dumps(report, sort_keys=True))
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, ValueError) as error:
        print("dense Boolean comparison failed: {}".format(error), file=sys.stderr)
        sys.exit(1)
