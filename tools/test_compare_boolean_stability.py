#!/usr/bin/env python3
"""Regression tests for the strict Boolean differential report gate."""

import csv
import os
import subprocess
import sys
import tempfile
import unittest


COMPARATOR = os.path.abspath(sys.argv.pop(1))
OPERATIONS = ("union", "intersection", "difference", "shatter")
FIELDS = (
    "case",
    "operation",
    "status",
    "median_seconds",
    "seconds",
    "absolute_signed_volume",
)


def write_report(path, rows):
    with open(path, "w", newline="", encoding="utf-8") as output:
        writer = csv.DictWriter(output, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def passing_rows(engine):
    return [
        {
            "case": "fixture",
            "operation": operation,
            "status": "pass",
            "median_seconds": "0.2" if engine == "prismel" else "",
            "seconds": "" if engine == "prismel" else "0.1",
            "absolute_signed_volume": "1.25",
        }
        for operation in OPERATIONS
    ]


class ComparatorTests(unittest.TestCase):
    def run_reports(self, prismel_rows, houdini_rows):
        with tempfile.TemporaryDirectory(prefix="prismel-boolean-compare-") as root:
            prismel = os.path.join(root, "prismel.csv")
            houdini = os.path.join(root, "houdini.csv")
            write_report(prismel, prismel_rows)
            write_report(houdini, houdini_rows)
            return subprocess.run(
                [sys.executable, COMPARATOR, prismel, houdini],
                check=False,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )

    def test_complete_reports_pass(self):
        result = self.run_reports(passing_rows("prismel"), passing_rows("houdini"))
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual(result.stdout.count("fixture,"), 4)

    def test_missing_required_oracle_row_fails(self):
        result = self.run_reports(
            passing_rows("prismel"), passing_rows("houdini")[:-1]
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("fail: missing Houdini row", result.stdout)

    def test_duplicate_rows_are_rejected(self):
        houdini = passing_rows("houdini")
        result = self.run_reports(
            passing_rows("prismel"), houdini + [dict(houdini[0])]
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("duplicates fixture/union", result.stderr)

    def test_failed_oracle_without_metrics_is_inconclusive_not_a_crash(self):
        houdini = passing_rows("houdini")
        houdini[0] = dict(houdini[0], status="error", seconds="",
            absolute_signed_volume="")
        result = self.run_reports(passing_rows("prismel"), houdini)
        self.assertEqual(result.returncode, 1)
        self.assertIn("comparison inconclusive", result.stdout)

    def test_nonfinite_metrics_fail(self):
        houdini = passing_rows("houdini")
        houdini[0] = dict(houdini[0], absolute_signed_volume="nan")
        result = self.run_reports(passing_rows("prismel"), houdini)
        self.assertEqual(result.returncode, 1)
        self.assertIn("malformed metric: non-finite metric", result.stdout)


if __name__ == "__main__":
    unittest.main()
