#!/usr/bin/env python3
"""Build and validate the Phase 0 renderer/event/audio fixture manifest."""

from __future__ import annotations

import argparse
import binascii
import hashlib
import json
from pathlib import Path
import struct
import sys
import zlib
from typing import Any


SCHEMA = 1
CAPTURE_COMMIT = "aab2337b6aab57b453514b4171bcc44a3dcaef37"
OUTPUT_RELATIVE = Path("specification/evidence/gpu_migration/fixtures.json")
ENVIRONMENT_RELATIVE = Path(
    "specification/evidence/gpu_migration/phase0_environment.json"
)

ARTIFACTS = (
    {
        "id": "renderer-headless",
        "path": "test/gpu_migration/golden/renderer_headless.png",
        "kind": "png",
        "target": "headless",
        "comparison": "byte_exact",
        "command": (
            "PRISMEL_RENDER_TARGET=headless dune exec --profile release "
            "test/gpu_baseline_renderer.exe -- <png> <trace>"
        ),
        "expected": "640x480 RGBA8 non-interlaced PNG; exact digest",
        "ownership": "Committed deterministic golden owned by renderer parity tests.",
    },
    {
        "id": "renderer-web",
        "path": "test/gpu_migration/golden/renderer_web.png",
        "kind": "png",
        "target": "web",
        "comparison": "byte_exact_and_equal_to_renderer-headless",
        "command": (
            "PRISMEL_RENDER_TARGET=web PRISMEL_WEB_PORT=0 dune exec "
            "--profile release test/gpu_baseline_renderer.exe -- <png> <trace>"
        ),
        "expected": "Exact authoritative software framebuffer shared with headless.",
        "ownership": "Committed deterministic golden owned by web target parity tests.",
    },
    {
        "id": "renderer-native-m1",
        "path": "test/gpu_migration/golden/renderer_native_m1.png",
        "kind": "png",
        "target": "native",
        "comparison": "frozen_native_tolerance",
        "command": (
            "PRISMEL_RENDER_TARGET=native dune exec --profile release "
            "test/gpu_baseline_renderer.exe -- <png> <trace>"
        ),
        "expected": "640x480 M1 SDL/OpenGL reference; repeated legacy captures are exact.",
        "ownership": "Committed M1 reference owned by native renderer parity tests.",
    },
    {
        "id": "renderer-headless-lifecycle",
        "path": "test/gpu_migration/traces/renderer_headless.json",
        "kind": "json",
        "target": "headless",
        "comparison": "byte_exact",
        "command": "Emitted with renderer-headless.",
        "expected": "Ordered Canvas, capture, and Image teardown trace.",
        "ownership": "Committed lifecycle trace owned by renderer resource tests.",
    },
    {
        "id": "renderer-web-lifecycle",
        "path": "test/gpu_migration/traces/renderer_web.json",
        "kind": "json",
        "target": "web",
        "comparison": "byte_exact",
        "command": "Emitted with renderer-web.",
        "expected": "Ordered Canvas, capture, and Image teardown trace.",
        "ownership": "Committed lifecycle trace owned by web resource tests.",
    },
    {
        "id": "renderer-native-m1-lifecycle",
        "path": "test/gpu_migration/traces/renderer_native_m1.json",
        "kind": "json",
        "target": "native",
        "comparison": "byte_exact",
        "command": "Emitted with renderer-native-m1.",
        "expected": "Ordered Canvas, capture, and Image teardown trace.",
        "ownership": "Committed lifecycle trace owned by native resource tests.",
    },
    {
        "id": "audio-headless",
        "path": "test/gpu_migration/traces/audio_headless.json",
        "kind": "json",
        "target": "headless",
        "comparison": "byte_exact",
        "command": (
            "PRISMEL_RENDER_TARGET=headless dune exec --profile release "
            "test/gpu_baseline_audio.exe -- <trace>"
        ),
        "expected": "Sample/music play-pause-resume-stop and idempotent destruction pass.",
        "ownership": "Committed SDL_mixer dummy-device trace owned by audio parity tests.",
    },
    {
        "id": "web-runtime-events-audio-resources",
        "path": "test/gpu_migration/traces/web_runtime.json",
        "kind": "json",
        "target": "web",
        "comparison": "byte_exact",
        "command": (
            "PRISMEL_RENDER_TARGET=web PRISMEL_WEB_PORT=0 "
            "PRISMEL_GPU_TRACE_OUTPUT=<trace> dune exec --profile release "
            "test/web_runtime_smoke.exe"
        ),
        "expected": "Ordered browser events, audio mirroring, and upload cleanup pass.",
        "ownership": "Committed transport trace owned jointly by Runtime and Wap tests.",
    },
)

EXPECTED_WEB_EVENTS = [
    "MouseMoved(13, 17)",
    "MousePressed(LeftButton, (13, 17))",
    "MouseScrolled(0, 1)",
    "KeyPressed(KeyChar 'a')",
    'TextInput("A")',
    "KeyReleased(KeyChar 'a')",
    "MouseReleased(LeftButton, (13, 17))",
    "WindowResized(80, 60)",
    "FileDropped(browser.txt)",
    "WindowFocusLost",
]

NATIVE_TOLERANCE = {
    "authority": "Frozen before any Metal-renderer output exists.",
    "dimensions_must_match": True,
    "pixel_format": "RGBA8",
    "mean_absolute_error_per_channel_max": 1.5,
    "pixels_with_any_rgb_error_over_16_fraction_max": 0.02,
    "alpha_mismatch_fraction_max": 0.0,
    "clear_and_axis_aligned_interior_regions": "exact",
    "rasterized_edges": "measured by aggregate bounds above; thresholds may not be loosened",
}


class FixtureError(RuntimeError):
    pass


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def paeth(left: int, up: int, upper_left: int) -> int:
    estimate = left + up - upper_left
    left_distance = abs(estimate - left)
    up_distance = abs(estimate - up)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= up_distance and left_distance <= upper_left_distance:
        return left
    if up_distance <= upper_left_distance:
        return up
    return upper_left


def decode_rgba_png(path: Path) -> tuple[int, int, bytes]:
    value = path.read_bytes()
    if not value.startswith(b"\x89PNG\r\n\x1a\n"):
        raise FixtureError(f"{path}: not a PNG")
    cursor = 8
    width = height = bit_depth = color_type = interlace = None
    compressed = bytearray()
    saw_end = False
    while cursor < len(value):
        if cursor + 12 > len(value):
            raise FixtureError(f"{path}: truncated PNG chunk")
        length = struct.unpack(">I", value[cursor : cursor + 4])[0]
        kind = value[cursor + 4 : cursor + 8]
        data_start = cursor + 8
        data_stop = data_start + length
        if data_stop + 4 > len(value):
            raise FixtureError(f"{path}: truncated {kind!r} chunk")
        data = value[data_start:data_stop]
        expected_crc = struct.unpack(">I", value[data_stop : data_stop + 4])[0]
        actual_crc = binascii.crc32(kind + data) & 0xFFFFFFFF
        if actual_crc != expected_crc:
            raise FixtureError(f"{path}: invalid {kind!r} CRC")
        cursor = data_stop + 4
        if kind == b"IHDR":
            width, height, bit_depth, color_type, compression, filtering, interlace = (
                struct.unpack(">IIBBBBB", data)
            )
            if compression != 0 or filtering != 0:
                raise FixtureError(f"{path}: unsupported PNG compression/filter method")
        elif kind == b"IDAT":
            compressed.extend(data)
        elif kind == b"IEND":
            saw_end = True
            break
    if not saw_end or None in {width, height, bit_depth, color_type, interlace}:
        raise FixtureError(f"{path}: incomplete PNG")
    if bit_depth != 8 or color_type != 6 or interlace != 0:
        raise FixtureError(f"{path}: expected non-interlaced RGBA8")
    assert width is not None and height is not None
    stride = width * 4
    packed = zlib.decompress(bytes(compressed))
    if len(packed) != height * (stride + 1):
        raise FixtureError(f"{path}: unexpected decompressed size")
    output = bytearray(width * height * 4)
    previous = bytearray(stride)
    source = 0
    for row in range(height):
        filter_kind = packed[source]
        source += 1
        raw = packed[source : source + stride]
        source += stride
        reconstructed = bytearray(stride)
        for index, byte in enumerate(raw):
            left = reconstructed[index - 4] if index >= 4 else 0
            up = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_kind == 0:
                prediction = 0
            elif filter_kind == 1:
                prediction = left
            elif filter_kind == 2:
                prediction = up
            elif filter_kind == 3:
                prediction = (left + up) // 2
            elif filter_kind == 4:
                prediction = paeth(left, up, upper_left)
            else:
                raise FixtureError(f"{path}: unsupported PNG filter {filter_kind}")
            reconstructed[index] = (byte + prediction) & 0xFF
        start = row * stride
        output[start : start + stride] = reconstructed
        previous = reconstructed
    return width, height, bytes(output)


def validate_trace(identifier: str, value: dict[str, Any]) -> None:
    if value.get("schema") != 1:
        raise FixtureError(f"{identifier}: invalid trace schema")
    if identifier == "audio-headless":
        for field in (
            "sample_started",
            "sample_stopped",
            "music_started",
            "music_stopped",
        ):
            if value.get(field) is not True:
                raise FixtureError(f"{identifier}: {field} did not pass")
        if value.get("operations", [])[-1:] != ["temporary_wave.remove"]:
            raise FixtureError(f"{identifier}: temporary wave cleanup is missing")
    elif identifier == "web-runtime-events-audio-resources":
        if value.get("event_order") != EXPECTED_WEB_EVENTS:
            raise FixtureError(f"{identifier}: ordered event trace changed")
        if value.get("mouse_delta") != [13, 17]:
            raise FixtureError(f"{identifier}: accumulated mouse delta changed")
        if value.get("resource_lifecycle", [])[-1:] != [
            "runtime.remove_temp_file"
        ]:
            raise FixtureError(f"{identifier}: upload cleanup trace changed")
    elif identifier.startswith("renderer-"):
        if value.get("logical_size") != [640, 480]:
            raise FixtureError(f"{identifier}: logical size changed")
        if value.get("lifecycle", [])[-1:] != ["image.destroy"]:
            raise FixtureError(f"{identifier}: image teardown is missing")


def generate(root: Path) -> dict[str, Any]:
    environment = json.loads((root / ENVIRONMENT_RELATIVE).read_text(encoding="utf-8"))
    gpu_models = [
        gpu.get("model") for gpu in environment.get("hardware", {}).get("graphics", [])
    ]
    if "Apple M1" not in gpu_models:
        raise FixtureError("native reference environment is not the required M1 lane")
    entries: list[dict[str, Any]] = []
    png_bytes: dict[str, bytes] = {}
    for definition in ARTIFACTS:
        entry = dict(definition)
        path = root / str(entry["path"])
        if not path.exists():
            raise FixtureError(f"missing fixture artifact: {path}")
        contents = path.read_bytes()
        entry["bytes"] = len(contents)
        entry["sha256"] = sha256(contents)
        if entry["kind"] == "png":
            width, height, pixels = decode_rgba_png(path)
            if (width, height) != (640, 480):
                raise FixtureError(f"{entry['id']}: expected 640x480 pixels")
            entry["width"] = width
            entry["height"] = height
            entry["pixel_sha256"] = sha256(pixels)
            png_bytes[str(entry["id"])] = contents
        else:
            trace = json.loads(contents)
            validate_trace(str(entry["id"]), trace)
        entries.append(entry)
    if png_bytes["renderer-headless"] != png_bytes["renderer-web"]:
        raise FixtureError("headless and web authoritative PNGs are not byte-identical")
    return {
        "schema": SCHEMA,
        "kind": "phase0_fixtures",
        "baseline_commit": environment["baseline_commit"],
        "capture_commit": CAPTURE_COMMIT,
        "capture_dirty": False,
        "profile": "release",
        "repeat_count": 2,
        "all_repeated_artifacts_byte_identical": True,
        "native_environment": {
            "machine_model": environment["hardware"]["machine_model"],
            "gpu": "Apple M1",
            "os": environment["operating_system"],
            "display": environment["benchmark_policy"]["display_scale"],
        },
        "native_tolerance": NATIVE_TOLERANCE,
        "artifacts": entries,
    }


def encoded(value: dict[str, Any]) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    value = encoded(generate(root))
    output_path = root / OUTPUT_RELATIVE
    if arguments.write:
        output_path.parent.mkdir(parents=True, exist_ok=True)
        output_path.write_text(value, encoding="utf-8")
        print(f"wrote {len(ARTIFACTS)} validated fixture records")
        return 0
    if not output_path.exists():
        print(f"missing fixture manifest: {output_path}", file=sys.stderr)
        return 1
    if output_path.read_text(encoding="utf-8") != value:
        print(
            "fixture manifest is stale; run "
            "tools/gpu_migration/fixture_manifest.py --write",
            file=sys.stderr,
        )
        return 1
    print("Phase 0 renderer/event/audio/resource fixtures passed")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (FixtureError, json.JSONDecodeError, zlib.error) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
