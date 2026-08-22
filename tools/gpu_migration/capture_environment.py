#!/usr/bin/env python3
"""Capture sanitized, reproducible Phase 0 GPU baseline environment facts."""

from __future__ import annotations

import argparse
from datetime import datetime
import json
import os
from pathlib import Path
import platform
import subprocess
import sys
from typing import Any


SCHEMA = 1
BASELINE_RELATIVE = Path(
    "specification/evidence/gpu_migration/phase0_baseline.json"
)
OUTPUT_RELATIVE = Path(
    "specification/evidence/gpu_migration/phase0_environment.json"
)
SENSITIVE_FRAGMENTS = ("serial", "uuid", "udid", "hostname", "user_name")


class CaptureError(RuntimeError):
    pass


def command(
    arguments: list[str], *, required: bool = True
) -> tuple[int, str, str]:
    try:
        completed = subprocess.run(
            arguments,
            check=False,
            capture_output=True,
            text=True,
            env=os.environ.copy(),
        )
    except FileNotFoundError as error:
        if required:
            raise CaptureError(f"missing command: {arguments[0]}") from error
        return 127, "", str(error)
    stdout = completed.stdout.strip()
    stderr = completed.stderr.strip()
    if required and completed.returncode != 0:
        diagnostic = stderr or stdout or "no diagnostic"
        raise CaptureError(
            f"{' '.join(arguments)} failed ({completed.returncode}): {diagnostic}"
        )
    return completed.returncode, stdout, stderr


def output(arguments: list[str], *, required: bool = True) -> str:
    return command(arguments, required=required)[1]


def sysctl(name: str) -> str | None:
    status, stdout, _ = command(["sysctl", "-n", name], required=False)
    return stdout if status == 0 and stdout else None


def sw_vers() -> dict[str, str]:
    values: dict[str, str] = {}
    for line in output(["sw_vers"]).splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            values[key.strip()] = value.strip()
    return {
        "name": values.get("ProductName", "unknown"),
        "version": values.get("ProductVersion", "unknown"),
        "build": values.get("BuildVersion", "unknown"),
    }


def safe_hardware() -> dict[str, Any]:
    raw = json.loads(
        output(
            [
                "system_profiler",
                "SPHardwareDataType",
                "SPDisplaysDataType",
                "-json",
            ]
        )
    )
    hardware_items = raw.get("SPHardwareDataType", [])
    hardware = hardware_items[0] if hardware_items else {}
    graphics = []
    for gpu in raw.get("SPDisplaysDataType", []):
        displays = []
        for display in gpu.get("spdisplays_ndrvs", []):
            displays.append(
                {
                    "name": display.get("_name"),
                    "pixels": display.get("_spdisplays_pixels"),
                    "resolution": display.get("_spdisplays_resolution"),
                    "main": display.get("spdisplays_main"),
                    "mirror": display.get("spdisplays_mirror"),
                    "online": display.get("spdisplays_online"),
                }
            )
        graphics.append(
            {
                "model": gpu.get("sppci_model"),
                "cores": gpu.get("sppci_cores"),
                "metal_family": gpu.get("spdisplays_mtlgpufamilysupport"),
                "bus": gpu.get("sppci_bus"),
                "displays": displays,
            }
        )
    return {
        "machine_name": hardware.get("machine_name"),
        "machine_model": hardware.get("machine_model"),
        "chip": hardware.get("chip_type"),
        "physical_memory": hardware.get("physical_memory"),
        "processors": hardware.get("number_processors"),
        "logical_cpu_count": sysctl("hw.logicalcpu"),
        "physical_cpu_count": sysctl("hw.physicalcpu"),
        "memory_bytes": sysctl("hw.memsize"),
        "graphics": graphics,
    }


def first_line(value: str) -> str | None:
    lines = value.splitlines()
    return lines[0] if lines else None


def toolchain() -> dict[str, Any]:
    xcode_path = output(["xcode-select", "-p"])
    xcode_status, xcode_stdout, xcode_stderr = command(
        ["xcodebuild", "-version"], required=False
    )
    metal_status, metal_stdout, metal_stderr = command(
        ["xcrun", "-f", "metal"], required=False
    )
    clang = output(["clang", "--version"])
    return {
        "developer_directory": xcode_path,
        "full_xcode_available": xcode_status == 0 and "Xcode" in xcode_stdout,
        "xcode_version": xcode_stdout if xcode_status == 0 else None,
        "xcode_diagnostic": first_line(xcode_stderr) if xcode_status != 0 else None,
        "macos_sdk_version": output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-version"]
        ),
        "macos_sdk_path": output(
            ["xcrun", "--sdk", "macosx", "--show-sdk-path"]
        ),
        "metal_compiler_available": metal_status == 0,
        "metal_compiler_path": metal_stdout if metal_status == 0 else None,
        "metal_compiler_diagnostic": (
            first_line(metal_stderr) if metal_status != 0 else None
        ),
        "clang": clang.splitlines()[:2],
        "deployment_floor": "macOS 14",
    }


def package_version(name: str) -> str | None:
    status, stdout, _ = command(
        ["opam", "show", "--field=version", name], required=False
    )
    return stdout if status == 0 and stdout else None


def pkg_config_version(name: str) -> str | None:
    status, stdout, _ = command(
        ["pkg-config", "--modversion", name], required=False
    )
    return stdout if status == 0 and stdout else None


def brew_versions(names: list[str]) -> dict[str, str | None]:
    versions: dict[str, str | None] = {}
    for name in names:
        status, stdout, _ = command(
            ["brew", "list", "--versions", name], required=False
        )
        versions[name] = stdout or None if status == 0 else None
    return versions


def software() -> dict[str, Any]:
    opam_packages = [
        "ocaml",
        "dune",
        "domainslib",
        "ctypes",
        "ctypes-foreign",
        "tsdl",
        "tsdl-image",
        "tsdl-ttf",
        "tsdl-mixer",
        "conf-sdl2",
        "conf-sdl2-image",
        "conf-sdl2-ttf",
        "conf-sdl2-mixer",
    ]
    pkg_names = [
        "sdl2",
        "SDL2_image",
        "SDL2_ttf",
        "SDL2_mixer",
        "SDL2_gfx",
        "sdl3",
        "SDL3_image",
        "SDL3_ttf",
        "SDL3_mixer",
    ]
    return {
        "ocaml": output(["ocamlc", "-version"]),
        "dune": output(["dune", "--version"]),
        "python": platform.python_version(),
        "opam_packages": {name: package_version(name) for name in opam_packages},
        "pkg_config": {name: pkg_config_version(name) for name in pkg_names},
        "homebrew": brew_versions(
            [
                "sdl2",
                "sdl2_image",
                "sdl2_ttf",
                "sdl2_mixer",
                "sdl2_gfx",
                "sdl3",
                "sdl3_image",
                "sdl3_ttf",
                "sdl3_mixer",
            ]
        ),
    }


def power_and_thermal() -> dict[str, Any]:
    _, battery, battery_error = command(["pmset", "-g", "batt"], required=False)
    _, thermal, thermal_error = command(["pmset", "-g", "therm"], required=False)
    return {
        "power": battery.splitlines() if battery else [battery_error],
        "thermal": thermal.splitlines() if thermal else [thermal_error],
    }


def capture(root: Path) -> dict[str, Any]:
    baseline = json.loads((root / BASELINE_RELATIVE).read_text(encoding="utf-8"))
    head = output(["git", "-C", str(root), "rev-parse", "HEAD"])
    status = output(
        ["git", "-C", str(root), "status", "--porcelain=v1"], required=True
    )
    return {
        "schema": SCHEMA,
        "kind": "phase0_environment",
        "baseline_commit": baseline["baseline_commit"],
        "capture_commit": head,
        "capture_dirty": bool(status),
        "local_modifications": status.splitlines(),
        "captured_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "operating_system": sw_vers(),
        "architecture": platform.machine(),
        "hardware": safe_hardware(),
        "toolchain": toolchain(),
        "software": software(),
        "power_and_thermal": power_and_thermal(),
        "benchmark_policy": {
            "compiler_profile": "release",
            "warm_samples_per_scenario": 5,
            "interactive_sample_seconds": 30,
            "domain_counts": [1, int(sysctl("hw.logicalcpu") or "1")],
            "display_scale": "1x external 1920x1080 baseline display",
        },
        "render_target_environment": {
            "captured_default": os.environ.get("PRISMEL_RENDER_TARGET"),
            "baseline_commands_override_target_explicitly": True,
        },
    }


def sensitive_paths(value: Any, path: str = "$") -> list[str]:
    failures: list[str] = []
    if isinstance(value, dict):
        for key, child in value.items():
            lowered = key.lower()
            if any(fragment in lowered for fragment in SENSITIVE_FRAGMENTS):
                failures.append(f"{path}.{key}")
            failures.extend(sensitive_paths(child, f"{path}.{key}"))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            failures.extend(sensitive_paths(child, f"{path}[{index}]"))
    return failures


def validate(root: Path, value: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    baseline = json.loads((root / BASELINE_RELATIVE).read_text(encoding="utf-8"))
    if value.get("schema") != SCHEMA:
        failures.append("unsupported environment evidence schema")
    if value.get("baseline_commit") != baseline.get("baseline_commit"):
        failures.append("environment evidence names the wrong baseline commit")
    if value.get("capture_dirty"):
        failures.append("environment evidence was captured from a dirty worktree")
    hardware = value.get("hardware", {})
    if not hardware.get("machine_model") or not hardware.get("graphics"):
        failures.append("hardware model or GPU/display facts are missing")
    toolchain_value = value.get("toolchain", {})
    if not toolchain_value.get("macos_sdk_version"):
        failures.append("macOS SDK version is missing")
    software_value = value.get("software", {})
    if not software_value.get("ocaml") or not software_value.get("dune"):
        failures.append("OCaml or Dune version is missing")
    policy = value.get("benchmark_policy", {})
    if policy.get("warm_samples_per_scenario") != 5:
        failures.append("baseline policy must retain five samples per scenario")
    failures.extend(
        f"sensitive machine identity key present at {path}"
        for path in sensitive_paths(value)
    )
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    output_path = root / OUTPUT_RELATIVE
    if arguments.write:
        value = capture(root)
        failures = validate(root, value)
        if failures:
            raise CaptureError("; ".join(failures))
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(
            json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        print(f"wrote sanitized environment evidence to {output_path}")
        return 0
    if not output_path.exists():
        print(f"missing environment evidence: {output_path}", file=sys.stderr)
        return 1
    value = json.loads(output_path.read_text(encoding="utf-8"))
    failures = validate(root, value)
    if failures:
        for failure in failures:
            print(failure, file=sys.stderr)
        return 1
    print("Phase 0 environment evidence is complete and sanitized")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except CaptureError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
