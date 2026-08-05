#!/usr/bin/env python3
"""Compare Prismel and licensed Houdini Boolean stress CSV reports."""

import argparse
import csv
import math
import sys


def rows(path):
    result = {}
    with open(path, newline="", encoding="utf-8") as source:
        reader = csv.DictReader(source)
        if reader.fieldnames is None or not {"case", "operation", "status"}.issubset(
            reader.fieldnames
        ):
            raise ValueError("{} is missing case/operation/status columns".format(path))
        for line, row in enumerate(reader, start=2):
            key = (row["case"], row["operation"])
            if not key[0] or not key[1]:
                raise ValueError("{}:{} has an empty case/operation".format(path, line))
            if key in result:
                raise ValueError("{}:{} duplicates {}/{}".format(path, line, *key))
            result[key] = row
    return result


def number(row, *names):
    for name in names:
        value = row.get(name, "")
        if value:
            return float(value)
    raise ValueError("missing numeric column {}".format("/".join(names)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("prismel_csv")
    parser.add_argument("houdini_csv")
    parser.add_argument("--relative-volume-tolerance", type=float, default=1e-7)
    parser.add_argument(
        "--required-operations",
        default="union,intersection,difference,shatter",
        help="comma-separated cross-engine operations required for every case",
    )
    parser.add_argument(
        "--max-slowdown",
        type=float,
        default=None,
        help="optional Prismel/Houdini cook-time release gate",
    )
    args = parser.parse_args()
    if not math.isfinite(args.relative_volume_tolerance) or args.relative_volume_tolerance < 0:
        parser.error("relative volume tolerance must be finite and non-negative")
    if args.max_slowdown is not None and (
        not math.isfinite(args.max_slowdown) or args.max_slowdown <= 0
    ):
        parser.error("max slowdown must be finite and positive")
    required_operations = tuple(
        value.strip() for value in args.required_operations.split(",") if value.strip()
    )
    if not required_operations:
        parser.error("at least one required operation is needed")
    try:
        prismel = rows(args.prismel_csv)
        houdini = rows(args.houdini_csv)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    cases = sorted(
        {case for case, _operation in prismel}.union(
            case for case, _operation in houdini
        )
    )
    if not cases:
        parser.error("reports contain no cases")
    failures = 0
    print("case,operation,status,volume_relative_error,prismel_over_houdini_seconds")
    for key in ((case, operation) for case in cases for operation in required_operations):
        if key not in prismel:
            failures += 1
            print("{},{},fail: missing Prismel row,,".format(*key))
            continue
        if key not in houdini:
            failures += 1
            print("{},{},fail: missing Houdini row,,".format(*key))
            continue
        p = prismel[key]
        h = houdini[key]
        reasons = []
        if p.get("status") != "pass":
            reasons.append("Prismel did not pass")
        if h.get("status") != "pass":
            reasons.append("Houdini oracle did not pass; comparison inconclusive")
        volume_error = math.nan
        slowdown = math.nan
        if not reasons:
            try:
                pv = number(p, "absolute_signed_volume")
                hv = number(h, "absolute_signed_volume")
                ps = number(p, "median_seconds", "seconds")
                hs = number(h, "seconds", "median_seconds")
                if not all(math.isfinite(value) for value in (pv, hv, ps, hs)):
                    raise ValueError("non-finite metric")
                volume_error = abs(pv - hv) / max(1.0, abs(pv), abs(hv))
                slowdown = ps / hs if hs > 0.0 else math.inf
            except (KeyError, TypeError, ValueError) as error:
                reasons.append("malformed metric: {}".format(error))
            if not reasons and volume_error > args.relative_volume_tolerance:
                reasons.append("volume mismatch")
            if (not reasons and args.max_slowdown is not None
                    and slowdown > args.max_slowdown):
                reasons.append("slowdown gate exceeded")
        status = "pass" if not reasons else "fail: " + " | ".join(reasons)
        if reasons:
            failures += 1
        print(
            "{},{},{},{:.9g},{:.9g}".format(
                key[0], key[1], status, volume_error, slowdown
            )
        )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
