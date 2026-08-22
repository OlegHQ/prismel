#!/usr/bin/env python3
"""Run, summarize, and validate the frozen Phase 0 performance suite."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import datetime
import hashlib
import json
import math
import os
from pathlib import Path
import queue
import re
import shlex
import socket
import statistics
import subprocess
import sys
import threading
import time
from typing import Any


SCHEMA = 1
BASELINE_RELATIVE = Path("specification/evidence/gpu_migration/phase0_baseline.json")
ENVIRONMENT_RELATIVE = Path(
    "specification/evidence/gpu_migration/phase0_environment.json"
)
OUTPUT_RELATIVE = Path(
    "specification/evidence/gpu_migration/phase0_performance.json"
)
RENDERER_SCENARIOS = ("basic", "pxui", "canvas", "scene3")
RENDER_TARGETS = ("native", "headless", "web")
SAMPLES = 5
WARMUP_SECONDS = 3.0
MEASURE_SECONDS = 30.0

NUMERIC_METRICS = (
    "frames",
    "wall_seconds",
    "frames_per_second",
    "median_frame_seconds",
    "p95_frame_seconds",
    "p99_frame_seconds",
    "user_seconds",
    "system_seconds",
    "cpu_percent",
    "allocated_bytes",
    "minor_bytes",
    "promoted_bytes",
    "major_bytes",
    "major_collections",
    "ending_heap_bytes",
    "peak_heap_bytes",
    "starting_rss_kib",
    "ending_rss_kib",
    "peak_sampled_rss_kib",
    "external_peak_rss_bytes",
    "legacy_gpu_duration_seconds",
    "legacy_gpu_utilization_percent",
    "legacy_draw_count",
    "legacy_upload_bytes",
    "cook_seconds",
    "pack_seconds",
    "geometry_payload_bytes",
    "packed_payload_bytes",
)


class BenchmarkError(RuntimeError):
    pass


@dataclass(frozen=True)
class Case:
    benchmark: str
    scenario: str
    target: str | None

    @property
    def key(self) -> str:
        target = self.target or "cpu"
        return f"{self.benchmark}:{target}:{self.scenario}"


def cases() -> list[Case]:
    ordinary = [
        Case("renderer", scenario, target)
        for target in RENDER_TARGETS
        for scenario in RENDERER_SCENARIOS
    ]
    return ordinary + [
        Case("shattered_renderer", "shattered-visible", "native"),
        Case("shattered_renderer", "shattered-hidden", "native"),
        Case("shattered_cube", "cook", None),
    ]


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as channel:
        for chunk in iter(lambda: channel.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def command_output(arguments: list[str], *, root: Path) -> str:
    completed = subprocess.run(
        arguments,
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        diagnostic = completed.stderr.strip() or completed.stdout.strip()
        raise BenchmarkError(
            f"{shlex.join(arguments)} failed ({completed.returncode}): {diagnostic}"
        )
    return completed.stdout.strip()


def git_facts(root: Path) -> tuple[str, bool, list[str]]:
    commit = command_output(["git", "rev-parse", "HEAD"], root=root)
    status = command_output(["git", "status", "--porcelain=v1"], root=root)
    modifications = status.splitlines() if status else []
    return commit, bool(modifications), modifications


def condition_lines(arguments: list[str], *, root: Path) -> list[str]:
    completed = subprocess.run(
        arguments,
        cwd=root,
        check=False,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )
    value = completed.stdout.strip() or completed.stderr.strip()
    return value.splitlines() if value else [f"unavailable (exit {completed.returncode})"]


def runtime_conditions(root: Path) -> dict[str, Any]:
    return {
        "captured_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "power": condition_lines(["pmset", "-g", "batt"], root=root),
        "thermal": condition_lines(["pmset", "-g", "therm"], root=root),
    }


def explicit_environment(
    case: Case, *, warmup: float, seconds: float, sample_index: int
) -> dict[str, str]:
    environment = {
        "PRISMEL_BENCH_PROFILE": "release",
        "PRISMEL_RENDERER_BENCH_WARMUP": f"{warmup:g}",
        "PRISMEL_RENDERER_BENCH_SECONDS": f"{seconds:g}",
    }
    if case.target is not None:
        environment["PRISMEL_RENDER_TARGET"] = case.target
    if case.benchmark == "renderer":
        environment["PRISMEL_BENCH_DOMAINS"] = "1"
        if case.target == "web":
            environment["PRISMEL_WEB_PORT"] = "0"
    elif case.benchmark == "shattered_renderer":
        environment["PRISMEL_SHATTER_DOMAINS"] = "1"
        environment["PRISMEL_SHATTER_GRAIN"] = "2"
    else:
        environment["PRISMEL_SHATTER_DOMAINS"] = "7"
        environment["PRISMEL_SHATTER_GRAIN"] = "2"
        environment["PRISMEL_SHATTER_VERIFY_DOMAINS"] = (
            "1" if sample_index == 0 else "0"
        )
    return environment


def executable_arguments(case: Case) -> list[str]:
    if case.benchmark == "renderer":
        return [
            "dune",
            "exec",
            "--profile",
            "release",
            "tools/bench_renderer.exe",
            "--",
            case.scenario,
        ]
    if case.benchmark == "shattered_renderer":
        mode = case.scenario.removeprefix("shattered-")
        return [
            "dune",
            "exec",
            "--profile",
            "release",
            "tools/bench_shattered_renderer.exe",
            "--",
            mode,
        ]
    return [
        "dune",
        "exec",
        "--profile",
        "release",
        "tools/bench_shattered_cube.exe",
    ]


def recorded_command(environment: dict[str, str], arguments: list[str]) -> str:
    assignments = [f"{key}={shlex.quote(value)}" for key, value in environment.items()]
    return " ".join(assignments + ["/usr/bin/time", "-l", shlex.join(arguments)])


def parse_json_line(stdout: str) -> dict[str, Any]:
    for line in reversed(stdout.splitlines()):
        stripped = line.strip()
        if stripped.startswith("{"):
            try:
                value = json.loads(stripped)
            except json.JSONDecodeError:
                continue
            if isinstance(value, dict):
                return value
    raise BenchmarkError(f"benchmark emitted no JSON object; stdout={stdout!r}")


def external_peak_rss(stderr: str) -> int | None:
    match = re.search(r"^\s*(\d+)\s+maximum resident set size\s*$", stderr, re.M)
    return int(match.group(1)) if match else None


def read_exact(channel: socket.socket, length: int) -> bytes:
    chunks: list[bytes] = []
    remaining = length
    while remaining:
        chunk = channel.recv(remaining)
        if not chunk:
            raise EOFError("socket closed")
        chunks.append(chunk)
        remaining -= len(chunk)
    return b"".join(chunks)


def read_until(channel: socket.socket, marker: bytes, limit: int = 2_000_000) -> bytes:
    value = bytearray()
    while marker not in value:
        # Read exactly through the delimiter.  A WebSocket frame may follow the
        # HTTP upgrade in the same TCP packet and must remain in the socket.
        chunk = channel.recv(1)
        if not chunk:
            raise EOFError("socket closed before marker")
        value.extend(chunk)
        if len(value) > limit:
            raise BenchmarkError("HTTP response exceeded safety limit")
    return bytes(value)


def websocket_frame(channel: socket.socket) -> tuple[int, bool, bytes]:
    header = read_exact(channel, 2)
    opcode = header[0] & 0x0F
    final = bool(header[0] & 0x80)
    masked = bool(header[1] & 0x80)
    length = header[1] & 0x7F
    if length == 126:
        length = int.from_bytes(read_exact(channel, 2), "big")
    elif length == 127:
        length = int.from_bytes(read_exact(channel, 8), "big")
    mask = read_exact(channel, 4) if masked else b""
    payload = read_exact(channel, length)
    if masked:
        payload = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
    return opcode, final, payload


def send_frame_ack(channel: socket.socket, frame_id: int) -> None:
    payload = b"\x01\x0d" + frame_id.to_bytes(4, "little", signed=True)
    mask = bytes(((frame_id + index * 37 + 19) & 0xFF) for index in range(4))
    masked = bytes(value ^ mask[index & 3] for index, value in enumerate(payload))
    channel.sendall(bytes((0x82, 0x80 | len(payload))) + mask + masked)


def connect_websocket(port: int) -> socket.socket:
    with socket.create_connection(("127.0.0.1", port), timeout=5.0) as http:
        http.sendall(
            (
                f"GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\n"
                "Connection: close\r\n\r\n"
            ).encode("ascii")
        )
        page = read_until(http, b"</html>").decode("utf-8", errors="replace")
    match = re.search(r'data-token="([^"]+)"', page)
    if not match:
        raise BenchmarkError("web benchmark page omitted its authentication token")
    token = match.group(1)
    channel = socket.create_connection(("127.0.0.1", port), timeout=5.0)
    request = (
        f"GET /ws?token={token} HTTP/1.1\r\n"
        f"Host: 127.0.0.1:{port}\r\n"
        "Upgrade: websocket\r\nConnection: Upgrade\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n\r\n"
    )
    channel.sendall(request.encode("ascii"))
    handshake = read_until(channel, b"\r\n\r\n")
    if not handshake.startswith(b"HTTP/1.1 101"):
        channel.close()
        raise BenchmarkError("web benchmark WebSocket upgrade was rejected")
    channel.settimeout(2.0)
    return channel


def drain_websocket(
    channel: socket.socket,
    stop: threading.Event,
    result: dict[str, Any],
) -> None:
    frames = 0
    acknowledgements = 0
    messages = 0
    payload_bytes = 0
    error: str | None = None
    pending_frame_id: int | None = None
    try:
        while not stop.is_set():
            try:
                opcode, final, payload = websocket_frame(channel)
            except socket.timeout:
                continue
            except EOFError:
                break
            messages += 1
            payload_bytes += len(payload)
            if opcode == 2 and payload.startswith(b"PRSM"):
                frames += 1
                if final or len(payload) < 12:
                    raise BenchmarkError("web frame metadata is malformed")
                pending_frame_id = int.from_bytes(
                    payload[8:12], "little", signed=True
                )
            elif opcode == 0 and final and pending_frame_id is not None:
                send_frame_ack(channel, pending_frame_id)
                acknowledgements += 1
                pending_frame_id = None
            if opcode == 8:
                break
    except Exception as caught:  # surfaced in the parent thread
        if not stop.is_set():
            error = f"{type(caught).__name__}: {caught}"
    finally:
        result.update(
            {
                "frames_received": frames,
                "frame_acknowledgements_sent": acknowledgements,
                "messages_received": messages,
                "payload_bytes_received": payload_bytes,
                "reader_error": error,
            }
        )
        try:
            channel.close()
        except OSError:
            pass


def stream_reader(channel: Any, output: list[str], notices: queue.Queue[str]) -> None:
    for line in iter(channel.readline, ""):
        output.append(line)
        notices.put(line)
    channel.close()


def run_web(
    timed_arguments: list[str], *, root: Path, environment: dict[str, str], timeout: float
) -> tuple[int, str, str, dict[str, Any]]:
    process = subprocess.Popen(
        timed_arguments,
        cwd=root,
        env={**os.environ, **environment},
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert process.stdout is not None and process.stderr is not None
    stdout_lines: list[str] = []
    stderr_lines: list[str] = []
    notices: queue.Queue[str] = queue.Queue()
    stdout_thread = threading.Thread(
        target=stream_reader, args=(process.stdout, stdout_lines, queue.Queue()), daemon=True
    )
    stderr_thread = threading.Thread(
        target=stream_reader, args=(process.stderr, stderr_lines, notices), daemon=True
    )
    stdout_thread.start()
    stderr_thread.start()
    deadline = time.monotonic() + min(timeout, 45.0)
    port: int | None = None
    while port is None and time.monotonic() < deadline:
        if process.poll() is not None and notices.empty():
            break
        try:
            line = notices.get(timeout=0.25)
        except queue.Empty:
            continue
        match = re.search(r"http://0\.0\.0\.0:(\d+)/", line)
        if match:
            port = int(match.group(1))
    if port is None:
        process.kill()
        process.wait()
        stdout_thread.join(timeout=2.0)
        stderr_thread.join(timeout=2.0)
        raise BenchmarkError(
            "web benchmark did not report its listening port; stderr="
            + "".join(stderr_lines)
        )
    channel = connect_websocket(port)
    stop = threading.Event()
    loopback: dict[str, Any] = {"port": "ephemeral"}
    socket_thread = threading.Thread(
        target=drain_websocket, args=(channel, stop, loopback), daemon=True
    )
    socket_thread.start()
    try:
        returncode = process.wait(timeout=timeout)
    except subprocess.TimeoutExpired as error:
        process.kill()
        process.wait()
        raise BenchmarkError("web benchmark exceeded its timeout") from error
    finally:
        stop.set()
        try:
            channel.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
    socket_thread.join(timeout=5.0)
    stdout_thread.join(timeout=5.0)
    stderr_thread.join(timeout=5.0)
    return returncode, "".join(stdout_lines), "".join(stderr_lines), loopback


def run_one(
    case: Case,
    *,
    root: Path,
    commit: str,
    sample_index: int,
    warmup: float,
    seconds: float,
) -> dict[str, Any]:
    environment = explicit_environment(
        case, warmup=warmup, seconds=seconds, sample_index=sample_index
    )
    arguments = executable_arguments(case)
    timed_arguments = ["/usr/bin/time", "-l", *arguments]
    command = recorded_command(environment, arguments)
    print(
        f"[{sample_index + 1}/{SAMPLES}] {case.key}: {command}",
        file=sys.stderr,
        flush=True,
    )
    before = runtime_conditions(root)
    timeout = max(300.0, warmup + seconds + 240.0)
    loopback = None
    if case.target == "web":
        returncode, stdout, stderr, loopback = run_web(
            timed_arguments,
            root=root,
            environment=environment,
            timeout=timeout,
        )
    else:
        completed = subprocess.run(
            timed_arguments,
            cwd=root,
            env={**os.environ, **environment},
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        returncode, stdout, stderr = (
            completed.returncode,
            completed.stdout,
            completed.stderr,
        )
    if returncode != 0:
        raise BenchmarkError(
            f"{case.key} failed ({returncode})\nstdout:\n{stdout}\nstderr:\n{stderr}"
        )
    value = parse_json_line(stdout)
    value["profile"] = "release"
    value["external_peak_rss_bytes"] = external_peak_rss(stderr)
    if loopback is not None:
        if loopback.get("reader_error"):
            raise BenchmarkError(f"web loopback reader failed: {loopback['reader_error']}")
        if loopback.get("frames_received", 0) < 1:
            raise BenchmarkError("web loopback received no framebuffer metadata")
        if loopback.get("frame_acknowledgements_sent") != loopback.get(
            "frames_received"
        ):
            raise BenchmarkError("web loopback did not acknowledge every framebuffer")
        value["web_loopback"] = loopback
    value["evidence"] = {
        "commit": commit,
        "dirty": False,
        "sample_index": sample_index + 1,
        "command": command,
        "explicit_environment": environment,
        "conditions_before": before,
        "conditions_after": runtime_conditions(root),
    }
    return value


def finite_number(value: Any) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def percentile(values: list[float], fraction: float) -> float:
    ordered = sorted(values)
    index = max(0, min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1))
    return ordered[index]


def summarize(runs: list[dict[str, Any]]) -> dict[str, Any]:
    summary: dict[str, Any] = {}
    for metric in NUMERIC_METRICS:
        values = [float(run[metric]) for run in runs if finite_number(run.get(metric))]
        if not values:
            summary[metric] = {"available": False}
            continue
        median = statistics.median(values)
        deviations = [abs(value - median) for value in values]
        summary[metric] = {
            "available": True,
            "samples": len(values),
            "median": median,
            "p95": percentile(values, 0.95),
            "minimum": min(values),
            "maximum": max(values),
            "median_absolute_deviation": statistics.median(deviations),
        }
    return summary


def write_progress(path: Path, value: dict[str, Any]) -> None:
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps(value, sort_keys=True), encoding="utf-8")
    temporary.replace(path)


def load_progress(
    path: Path, commit: str, signature: str
) -> dict[str, list[dict[str, Any]]]:
    if not path.exists():
        return {}
    value = json.loads(path.read_text(encoding="utf-8"))
    if value.get("commit") != commit:
        raise BenchmarkError(f"progress file {path} belongs to another commit")
    if value.get("signature") != signature:
        raise BenchmarkError(f"progress file {path} belongs to another run policy")
    runs = value.get("runs")
    if not isinstance(runs, dict):
        raise BenchmarkError(f"progress file {path} is malformed")
    return runs


def expected_keys() -> set[str]:
    return {case.key for case in cases()}


def validate(root: Path, value: dict[str, Any]) -> list[str]:
    failures: list[str] = []
    baseline = json.loads((root / BASELINE_RELATIVE).read_text(encoding="utf-8"))
    if value.get("schema") != SCHEMA:
        failures.append("unsupported performance evidence schema")
    if value.get("baseline_commit") != baseline.get("baseline_commit"):
        failures.append("performance evidence names the wrong baseline commit")
    if value.get("capture_dirty"):
        failures.append("performance evidence was captured from a dirty worktree")
    if value.get("new_gpu_stuff_sha256") != baseline.get("new_gpu_stuff_sha256"):
        failures.append("performance evidence used a different migration plan")
    groups = value.get("groups", [])
    by_key = {group.get("key"): group for group in groups if isinstance(group, dict)}
    if set(by_key) != expected_keys():
        failures.append(
            f"performance scenario set differs: expected {sorted(expected_keys())}, "
            f"got {sorted(str(key) for key in by_key)}"
        )
    for key in sorted(expected_keys() & set(by_key)):
        group = by_key[key]
        runs = group.get("runs", [])
        if len(runs) < SAMPLES:
            failures.append(f"{key} has {len(runs)} runs, expected at least {SAMPLES}")
            continue
        if group.get("profile") != "release":
            failures.append(f"{key} was not captured in release profile")
        for index, run in enumerate(runs):
            prefix = f"{key} run {index + 1}"
            evidence = run.get("evidence", {})
            if evidence.get("dirty"):
                failures.append(f"{prefix} was dirty")
            if evidence.get("commit") != value.get("capture_commit"):
                failures.append(f"{prefix} names a different capture commit")
            if not evidence.get("command"):
                failures.append(f"{prefix} has no reproduction command")
            if group.get("benchmark") != "shattered_cube":
                if run.get("requested_measure_seconds", 0) < MEASURE_SECONDS:
                    failures.append(f"{prefix} measured for less than 30 seconds")
                if run.get("warmup_seconds", 0) < WARMUP_SECONDS:
                    failures.append(f"{prefix} warmed for less than 3 seconds")
                for metric in (
                    "wall_seconds",
                    "user_seconds",
                    "system_seconds",
                    "median_frame_seconds",
                    "p95_frame_seconds",
                    "p99_frame_seconds",
                    "allocated_bytes",
                    "promoted_bytes",
                    "peak_sampled_rss_kib",
                ):
                    if not finite_number(run.get(metric)):
                        failures.append(f"{prefix} is missing {metric}")
                if group.get("target") == "web" and run.get(
                    "web_loopback", {}
                ).get("frames_received", 0) < 1:
                    failures.append(f"{prefix} did not exercise web frame delivery")
                if group.get("target") == "web":
                    loopback = run.get("web_loopback", {})
                    if loopback.get("frame_acknowledgements_sent") != loopback.get(
                        "frames_received"
                    ):
                        failures.append(
                            f"{prefix} did not acknowledge every delivered frame"
                        )
            if group.get("benchmark") == "shattered_renderer":
                expected = (18_278, 278_368, 835_104)
                observed = (
                    run.get("pieces"),
                    run.get("triangles"),
                    run.get("render_vertices"),
                )
                if observed != expected:
                    failures.append(f"{prefix} cardinality is {observed}, expected {expected}")
        if not isinstance(group.get("summary"), dict):
            failures.append(f"{key} has no aggregate summary")
    cook = by_key.get("shattered_cube:cpu:cook", {}).get("runs", [])
    if cook:
        first = cook[0]
        expected = (18_278, 278_368, 835_104)
        observed = (
            first.get("pieces"),
            first.get("triangles"),
            first.get("render_vertices"),
        )
        if observed != expected:
            failures.append(f"shattered cook cardinality is {observed}, expected {expected}")
        if not any(run.get("one_multi_domain_exact") is True for run in cook):
            failures.append("shattered cook never verified one/multi-domain exactness")
    gaps = value.get("instrumentation_gaps", {})
    for name in ("gpu_duration", "gpu_utilization", "draw_count", "upload_bytes"):
        if not gaps.get(name):
            failures.append(f"legacy instrumentation gap {name} is undocumented")
    return failures


def capture(
    root: Path,
    *,
    selected: list[Case],
    samples: int,
    warmup: float,
    seconds: float,
    resume: bool,
) -> dict[str, Any]:
    baseline_path = root / BASELINE_RELATIVE
    environment_path = root / ENVIRONMENT_RELATIVE
    baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
    commit, dirty, modifications = git_facts(root)
    if dirty:
        raise BenchmarkError(
            "performance evidence must start from a clean worktree: "
            + ", ".join(modifications)
        )
    plan_hash = sha256(root / "NEW_GPU_STUFF.md")
    if plan_hash != baseline["new_gpu_stuff_sha256"]:
        raise BenchmarkError("NEW_GPU_STUFF.md changed after its Phase 0 freeze")
    build = [
        "dune",
        "build",
        "--profile",
        "release",
        "tools/bench_renderer.exe",
        "tools/bench_shattered_renderer.exe",
        "tools/bench_shattered_cube.exe",
    ]
    print(shlex.join(build), file=sys.stderr, flush=True)
    command_output(build, root=root)
    signature_payload = json.dumps(
        {
            "cases": [case.key for case in selected],
            "samples": samples,
            "warmup": warmup,
            "seconds": seconds,
        },
        sort_keys=True,
    ).encode("utf-8")
    signature = hashlib.sha256(signature_payload).hexdigest()[:16]
    progress_path = Path("/tmp") / (
        f"prismel-phase0-performance-{commit}-{signature}.json"
    )
    recorded = load_progress(progress_path, commit, signature) if resume else {}
    for sample_index in range(samples):
        rotated = selected[sample_index % len(selected):] + selected[:sample_index % len(selected)]
        for case in rotated:
            runs = recorded.setdefault(case.key, [])
            if len(runs) > sample_index:
                continue
            run = run_one(
                case,
                root=root,
                commit=commit,
                sample_index=sample_index,
                warmup=warmup,
                seconds=seconds,
            )
            runs.append(run)
            write_progress(
                progress_path,
                {
                    "schema": SCHEMA,
                    "commit": commit,
                    "signature": signature,
                    "runs": recorded,
                },
            )
    groups = []
    for case in selected:
        runs = recorded[case.key][:samples]
        groups.append(
            {
                "key": case.key,
                "benchmark": case.benchmark,
                "scenario": case.scenario,
                "target": case.target,
                "profile": "release",
                "sample_count": len(runs),
                "runs": runs,
                "summary": summarize(runs),
            }
        )
    return {
        "schema": SCHEMA,
        "kind": "phase0_performance",
        "baseline_commit": baseline["baseline_commit"],
        "capture_commit": commit,
        "capture_dirty": False,
        "local_modifications": [],
        "captured_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "new_gpu_stuff_sha256": plan_hash,
        "environment_evidence": {
            "path": str(ENVIRONMENT_RELATIVE),
            "sha256": sha256(environment_path),
        },
        "policy": {
            "profile": "release",
            "samples_per_scenario": samples,
            "warmup_seconds": warmup,
            "interactive_measure_seconds": seconds,
            "interleaved_order": True,
            "build_command": shlex.join(build),
        },
        "instrumentation_gaps": {
            "gpu_duration": (
                "Legacy SDL2/OpenGL and SDL software paths expose no timestamp query; "
                "full Xcode Instruments is absent on the capture host."
            ),
            "gpu_utilization": (
                "powermetrics requires superuser access and full Xcode Metal System "
                "Trace is absent; no privileged measurement was fabricated."
            ),
            "draw_count": (
                "The frozen legacy renderer has no public draw-counter telemetry."
            ),
            "upload_bytes": (
                "The frozen legacy renderer has no public upload-byte telemetry."
            ),
        },
        "groups": groups,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--output", type=Path)
    parser.add_argument("--samples", type=int, default=SAMPLES)
    parser.add_argument("--warmup", type=float, default=WARMUP_SECONDS)
    parser.add_argument("--seconds", type=float, default=MEASURE_SECONDS)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument(
        "--only",
        action="append",
        default=[],
        help="run only case keys containing this value (development captures only)",
    )
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--list", action="store_true")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    output_path = arguments.output or root / OUTPUT_RELATIVE
    selected = cases()
    if arguments.only:
        selected = [
            case for case in selected
            if any(fragment in case.key for fragment in arguments.only)
        ]
    if arguments.list:
        for case in selected:
            print(case.key)
        return 0
    if arguments.check:
        if arguments.output or arguments.only:
            raise BenchmarkError("--check validates only the committed complete evidence")
        if not output_path.exists():
            raise BenchmarkError(f"missing performance evidence: {output_path}")
        value = json.loads(output_path.read_text(encoding="utf-8"))
        failures = validate(root, value)
        if failures:
            raise BenchmarkError("; ".join(failures))
        print("Phase 0 performance evidence is complete")
        return 0
    if not selected:
        raise BenchmarkError("--only selected no benchmark cases")
    complete_capture = (
        not arguments.output
        and not arguments.only
        and arguments.samples == SAMPLES
        and arguments.warmup >= WARMUP_SECONDS
        and arguments.seconds >= MEASURE_SECONDS
    )
    if not complete_capture and arguments.output is None:
        raise BenchmarkError("development captures require --output outside the repository")
    value = capture(
        root,
        selected=selected,
        samples=arguments.samples,
        warmup=arguments.warmup,
        seconds=arguments.seconds,
        resume=arguments.resume,
    )
    if complete_capture:
        failures = validate(root, value)
        if failures:
            raise BenchmarkError("; ".join(failures))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"wrote performance evidence to {output_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (BenchmarkError, OSError, subprocess.TimeoutExpired) as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
