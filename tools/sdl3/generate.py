#!/usr/bin/env python3
"""Generate the pinned SDL3 provenance, API inventory, and ABI assertions."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile
from typing import Any


GENERATOR_VERSION = "prismel-sdl3-clang-inventory-v1"
OUTPUTS = (
    "generated_provenance.ml",
    "generated_inventory.json",
    "generated_layout.json",
    "generated_abi.h",
)

# These are the production-safe entry points wrapped by the initial binding.
# Every other active stable-header symbol remains intentionally private/raw.
SAFE_FUNCTIONS = {
    "SDL_ClearError": "any-thread",
    "SDL_CreateWindow": "main-thread",
    "SDL_DestroyWindow": "main-thread",
    "SDL_GetError": "any-thread",
    "SDL_GetRevision": "any-thread",
    "SDL_GetVersion": "any-thread",
    "SDL_GetWindowFlags": "main-thread",
    "SDL_GetWindowSize": "main-thread",
    "SDL_GetWindowSizeInPixels": "main-thread",
    "SDL_HideWindow": "main-thread",
    "SDL_Init": "main-thread",
    "SDL_InitSubSystem": "main-thread",
    "SDL_IsMainThread": "any-thread",
    "SDL_Metal_CreateView": "main-thread",
    "SDL_Metal_DestroyView": "main-thread",
    "SDL_Metal_GetLayer": "main-thread",
    "SDL_PollEvent": "main-thread",
    "SDL_Quit": "main-thread",
    "SDL_QuitSubSystem": "main-thread",
    "SDL_SetWindowFullscreen": "main-thread",
    "SDL_ShowWindow": "main-thread",
    "SDL_WasInit": "any-thread",
    "SDL_WaitEventTimeout": "main-thread-blocking",
}

LAYOUT_FIELDS: dict[str, tuple[str, ...]] = {
    "SDL_Event": (),
    "SDL_CommonEvent": ("type", "timestamp"),
    "SDL_DisplayEvent": ("type", "timestamp", "displayID", "data1", "data2"),
    "SDL_WindowEvent": ("type", "timestamp", "windowID", "data1", "data2"),
    "SDL_KeyboardEvent": (
        "type", "timestamp", "windowID", "which", "scancode", "key", "mod",
        "raw", "down", "repeat",
    ),
    "SDL_TextEditingEvent": ("type", "timestamp", "windowID", "text", "start", "length"),
    "SDL_TextInputEvent": ("type", "timestamp", "windowID", "text"),
    "SDL_MouseMotionEvent": (
        "type", "timestamp", "windowID", "which", "state", "x", "y", "xrel", "yrel",
    ),
    "SDL_MouseButtonEvent": (
        "type", "timestamp", "windowID", "which", "button", "down", "clicks", "x", "y",
    ),
    "SDL_MouseWheelEvent": (
        "type", "timestamp", "windowID", "which", "x", "y", "direction",
        "mouse_x", "mouse_y", "integer_x", "integer_y",
    ),
    "SDL_TouchFingerEvent": (
        "type", "timestamp", "touchID", "fingerID", "x", "y", "dx", "dy", "pressure",
        "windowID",
    ),
    "SDL_PenMotionEvent": ("type", "timestamp", "windowID", "which", "pen_state", "x", "y"),
    "SDL_PenTouchEvent": (
        "type", "timestamp", "windowID", "which", "pen_state", "x", "y", "eraser", "down",
    ),
    "SDL_PenButtonEvent": (
        "type", "timestamp", "windowID", "which", "pen_state", "x", "y", "button", "down",
    ),
    "SDL_PenAxisEvent": (
        "type", "timestamp", "windowID", "which", "pen_state", "x", "y", "axis", "value",
    ),
    "SDL_GamepadAxisEvent": ("type", "timestamp", "which", "axis", "value"),
    "SDL_GamepadButtonEvent": ("type", "timestamp", "which", "button", "down"),
    "SDL_DropEvent": ("type", "timestamp", "windowID", "x", "y", "source", "data"),
    "SDL_AudioDeviceEvent": ("type", "timestamp", "which", "recording"),
}

ABI_CONSTANTS = (
    "SDL_INIT_AUDIO",
    "SDL_INIT_VIDEO",
    "SDL_INIT_JOYSTICK",
    "SDL_INIT_HAPTIC",
    "SDL_INIT_GAMEPAD",
    "SDL_INIT_EVENTS",
    "SDL_INIT_SENSOR",
    "SDL_INIT_CAMERA",
    "SDL_WINDOW_FULLSCREEN",
    "SDL_WINDOW_HIDDEN",
    "SDL_WINDOW_RESIZABLE",
    "SDL_WINDOW_HIGH_PIXEL_DENSITY",
    "SDL_WINDOW_METAL",
    "SDL_EVENT_QUIT",
    "SDL_EVENT_WINDOW_RESIZED",
    "SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED",
    "SDL_EVENT_KEY_DOWN",
    "SDL_EVENT_KEY_UP",
    "SDL_EVENT_TEXT_EDITING",
    "SDL_EVENT_TEXT_INPUT",
    "SDL_EVENT_MOUSE_MOTION",
    "SDL_EVENT_MOUSE_BUTTON_DOWN",
    "SDL_EVENT_MOUSE_BUTTON_UP",
    "SDL_EVENT_MOUSE_WHEEL",
    "SDL_EVENT_FINGER_DOWN",
    "SDL_EVENT_FINGER_UP",
    "SDL_EVENT_FINGER_MOTION",
    "SDL_EVENT_PEN_MOTION",
    "SDL_EVENT_PEN_DOWN",
    "SDL_EVENT_PEN_UP",
    "SDL_EVENT_PEN_BUTTON_DOWN",
    "SDL_EVENT_PEN_BUTTON_UP",
    "SDL_EVENT_PEN_AXIS",
    "SDL_EVENT_GAMEPAD_AXIS_MOTION",
    "SDL_EVENT_GAMEPAD_BUTTON_DOWN",
    "SDL_EVENT_GAMEPAD_BUTTON_UP",
    "SDL_EVENT_DROP_FILE",
    "SDL_EVENT_DROP_TEXT",
    "SDL_EVENT_DROP_BEGIN",
    "SDL_EVENT_DROP_COMPLETE",
)


class GenerationError(RuntimeError):
    pass


def run(arguments: list[str], *, input_text: str | None = None) -> str:
    completed = subprocess.run(
        arguments,
        input=input_text,
        text=True,
        check=False,
        capture_output=True,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        diagnostic = completed.stderr.strip() or completed.stdout.strip()
        raise GenerationError(
            f"{shlex.join(arguments)} failed ({completed.returncode}): {diagnostic}"
        )
    return completed.stdout


def pkg_config(name: str, argument: str) -> str:
    return run(["pkg-config", argument, name]).strip()


def discovery() -> tuple[Path, Path, list[str]]:
    include_override = os.environ.get("PRISMEL_SDL3_INCLUDE_DIR")
    library_override = os.environ.get("PRISMEL_SDL3_LIB_DIR")
    if include_override:
        include_root = Path(include_override).resolve()
        cflags = [f"-I{include_root}"]
    else:
        include_root = Path(pkg_config("sdl3", "--variable=includedir")).resolve()
        cflags = shlex.split(pkg_config("sdl3", "--cflags"))
    if library_override:
        library_root = Path(library_override).resolve()
    else:
        library_root = Path(pkg_config("sdl3", "--variable=libdir")).resolve()
    header = include_root / "SDL3" / "SDL.h"
    if not header.is_file():
        raise GenerationError(f"SDL3 header not found: {header}")
    return include_root, library_root, cflags


def compiler() -> str:
    return os.environ.get("PRISMEL_SDL3_CLANG", "clang")


def macro_map(clang: str, cflags: list[str]) -> dict[str, str]:
    text = run(
        [clang, *cflags, "-x", "c", "-dM", "-E", "-include", "SDL3/SDL.h", "/dev/null"]
    )
    values: dict[str, str] = {}
    for line in text.splitlines():
        if not line.startswith("#define SDL_"):
            continue
        _, name, *parts = line.split(maxsplit=2)
        values[name] = parts[0] if parts else ""
    return values


def version(macros: dict[str, str]) -> tuple[int, int, int]:
    try:
        return tuple(
            int(macros[name])
            for name in ("SDL_MAJOR_VERSION", "SDL_MINOR_VERSION", "SDL_MICRO_VERSION")
        )  # type: ignore[return-value]
    except (KeyError, ValueError) as error:
        raise GenerationError("SDL version macros are missing or malformed") from error


def header_hashes(include_root: Path) -> tuple[list[dict[str, str]], str]:
    root = include_root / "SDL3"
    entries: list[dict[str, str]] = []
    aggregate = hashlib.sha256()
    for path in sorted(root.glob("*.h")):
        relative = f"SDL3/{path.name}"
        contents = path.read_bytes()
        digest = hashlib.sha256(contents).hexdigest()
        entries.append({"path": relative, "sha256": digest})
        aggregate.update(relative.encode("utf-8"))
        aggregate.update(b"\0")
        aggregate.update(contents)
        aggregate.update(b"\0")
    return entries, aggregate.hexdigest()


def ast_inventory(clang: str, include_root: Path) -> dict[str, list[dict[str, Any]]]:
    ast = json.loads(
        run(
            [
                clang,
                "-isystem",
                str(include_root),
                "-x",
                "c",
                "-fsyntax-only",
                "-Xclang",
                "-ast-dump=json",
                "-include",
                "SDL3/SDL.h",
                "/dev/null",
            ]
        )
    )
    groups: dict[str, dict[str, dict[str, Any]]] = {
        "functions": {},
        "records": {},
        "enums": {},
        "typedefs": {},
    }
    stack = [ast]
    while stack:
        node = stack.pop()
        stack.extend(node.get("inner", ()))
        kind = node.get("kind")
        name = node.get("name")
        if not isinstance(name, str) or not name.startswith("SDL_"):
            continue
        location = node.get("loc", {})
        source = location.get("file")
        if isinstance(source, str) and "/SDL3/" not in source:
            continue
        # Clang deliberately elides a repeated source filename from JSON
        # locations.  An SDL_-prefixed declaration in this translation unit
        # can only originate in the umbrella header; retain it and mark an
        # elided attribution instead of silently dropping the symbol.
        header = (
            "SDL3/" + Path(source).name
            if isinstance(source, str)
            else "SDL3/<clang-elided-source>"
        )
        base = {
            "name": name,
            "header": header,
            "classification": "safe" if name in SAFE_FUNCTIONS else "raw-only",
        }
        if kind == "FunctionDecl":
            base["signature"] = node.get("type", {}).get("qualType", "unknown")
            base["thread"] = SAFE_FUNCTIONS.get(name, "raw-only-not-reviewed")
            groups["functions"][name] = base
        elif kind in ("RecordDecl", "UnionDecl"):
            base["kind"] = (
                "union" if node.get("tagUsed") == "union" else "struct"
            )
            base["fields"] = [
                child.get("name")
                for child in node.get("inner", ())
                if child.get("kind") == "FieldDecl" and child.get("name")
            ]
            groups["records"][name] = base
        elif kind == "EnumDecl":
            base["constants"] = [
                child.get("name")
                for child in node.get("inner", ())
                if child.get("kind") == "EnumConstantDecl" and child.get("name")
            ]
            groups["enums"][name] = base
        elif kind == "TypedefDecl":
            base["underlying"] = node.get("type", {}).get("qualType", "unknown")
            groups["typedefs"][name] = base
    return {
        group: [items[name] for name in sorted(items)]
        for group, items in groups.items()
    }


def compile_layout_probe(
    clang: str, cflags: list[str], library_root: Path
) -> dict[str, Any]:
    lines = [
        "#include <SDL3/SDL.h>",
        "#include <stddef.h>",
        "#include <stdint.h>",
        "#include <stdio.h>",
        "int main(void) {",
        '  printf("{\\\"types\\\":{");',
    ]
    for type_index, (type_name, fields) in enumerate(LAYOUT_FIELDS.items()):
        prefix = "" if type_index == 0 else ","
        lines.append(
            f'  printf("{prefix}\\\"{type_name}\\\":{{\\\"size\\\":%zu,'
            f'\\\"alignment\\\":%zu,\\\"offsets\\\":{{", sizeof({type_name}), '
            f'_Alignof({type_name}));'
        )
        for field_index, field in enumerate(fields):
            field_prefix = "" if field_index == 0 else ","
            lines.append(
                f'  printf("{field_prefix}\\\"{field}\\\":%zu", '
                f'offsetof({type_name}, {field}));'
            )
        lines.append('  printf("}}");')
    lines.append('  printf("},\\\"constants\\\":{");')
    for index, name in enumerate(ABI_CONSTANTS):
        prefix = "" if index == 0 else ","
        lines.append(
            f'  printf("{prefix}\\\"{name}\\\":%llu", '
            f'(unsigned long long)({name}));'
        )
    lines.extend(
        [
            '  printf("},\\\"callback_calling_convention\\\":\\\"default-c\\\"}\\n");',
            "  return 0;",
            "}",
        ]
    )
    source = "\n".join(lines) + "\n"
    with tempfile.TemporaryDirectory(prefix="prismel-sdl3-layout-") as directory:
        root = Path(directory)
        source_path = root / "probe.c"
        executable = root / "probe"
        source_path.write_text(source, encoding="utf-8")
        run(
            [
                clang,
                *cflags,
                str(source_path),
                f"-L{library_root}",
                "-lSDL3",
                "-o",
                str(executable),
            ]
        )
        return json.loads(run([str(executable)]))


def ocaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def provenance_ml(
    header_version: tuple[int, int, int],
    aggregate_hash: str,
    clang_version: str,
    target: str,
    inventory: dict[str, list[dict[str, Any]]],
    layout_hash: str,
) -> str:
    major, minor, patch = header_version
    function_count = len(inventory["functions"])
    safe_count = sum(
        item["classification"] == "safe" for item in inventory["functions"]
    )
    return f"""(* Generated by {GENERATOR_VERSION}; do not edit. *)
type version = {{ major : int; minor : int; patch : int }}

let generator_version = {ocaml_string(GENERATOR_VERSION)}
let header_version = {{ major = {major}; minor = {minor}; patch = {patch} }}
let header_version_number = {major * 1_000_000 + minor * 1_000 + patch}
let stable_headers = {str(minor % 2 == 0 and patch % 2 == 0).lower()}
let header_aggregate_sha256 = {ocaml_string(aggregate_hash)}
let clang_version = {ocaml_string(clang_version)}
let target_triple = {ocaml_string(target)}
let function_count = {function_count}
let safe_function_count = {safe_count}
let layout_sha256 = {ocaml_string(layout_hash)}
"""


def abi_header(layout: dict[str, Any], header_version: tuple[int, int, int]) -> str:
    major, minor, patch = header_version
    lines = [
        "/* Generated ABI assertions; do not edit. */",
        "#ifndef PRISMEL_SDL3_GENERATED_ABI_H",
        "#define PRISMEL_SDL3_GENERATED_ABI_H",
        "#include <SDL3/SDL.h>",
        "#include <stddef.h>",
        f'_Static_assert(SDL_MAJOR_VERSION == {major}, "SDL major header changed");',
        f'_Static_assert(SDL_MINOR_VERSION == {minor}, "SDL minor header changed");',
        f'_Static_assert(SDL_MICRO_VERSION == {patch}, "SDL patch header changed");',
    ]
    for type_name, facts in layout["types"].items():
        lines.append(
            f'_Static_assert(sizeof({type_name}) == {facts["size"]}, "{type_name} size changed");'
        )
        lines.append(
            f'_Static_assert(_Alignof({type_name}) == {facts["alignment"]}, "{type_name} alignment changed");'
        )
        for field, offset in facts["offsets"].items():
            lines.append(
                f'_Static_assert(offsetof({type_name}, {field}) == {offset}, '
                f'"{type_name}.{field} offset changed");'
            )
    for name, value in layout["constants"].items():
        lines.append(
            f'_Static_assert((unsigned long long)({name}) == {value}ULL, "{name} changed");'
        )
    lines.extend(["#endif", ""])
    return "\n".join(lines)


def generate() -> dict[str, str]:
    clang = compiler()
    include_root, library_root, cflags = discovery()
    macros = macro_map(clang, cflags)
    header_version = version(macros)
    headers, aggregate_hash = header_hashes(include_root)
    inventory_groups = ast_inventory(clang, include_root)
    clang_version = run([clang, "--version"]).splitlines()[0]
    target = run([clang, "-dumpmachine"]).strip()
    inventory = {
        "schema": 1,
        "generator": GENERATOR_VERSION,
        "header_version": {
            "major": header_version[0],
            "minor": header_version[1],
            "patch": header_version[2],
        },
        "stable_headers": header_version[1] % 2 == 0 and header_version[2] % 2 == 0,
        "header_aggregate_sha256": aggregate_hash,
        "compiler": clang_version,
        "target_triple": target,
        "headers": headers,
        **inventory_groups,
        "macros": [
            {
                "name": name,
                "value": macros[name],
                "classification": "raw-only",
            }
            for name in sorted(macros)
        ],
        "classification_counts": {
            classification: sum(
                item["classification"] == classification
                for group in inventory_groups.values()
                for item in group
            )
            + (len(macros) if classification == "raw-only" else 0)
            for classification in ("safe", "raw-only", "platform-excluded", "not-applicable", "unreviewed")
        },
    }
    layout = compile_layout_probe(clang, cflags, library_root)
    layout.update(
        {
            "schema": 1,
            "generator": GENERATOR_VERSION,
            "header_version": inventory["header_version"],
            "header_aggregate_sha256": aggregate_hash,
            "compiler": clang_version,
            "target_triple": target,
        }
    )
    inventory_text = json.dumps(inventory, indent=2, sort_keys=True) + "\n"
    layout_text = json.dumps(layout, indent=2, sort_keys=True) + "\n"
    layout_hash = hashlib.sha256(layout_text.encode("utf-8")).hexdigest()
    return {
        "generated_provenance.ml": provenance_ml(
            header_version,
            aggregate_hash,
            clang_version,
            target,
            inventory_groups,
            layout_hash,
        ),
        "generated_inventory.json": inventory_text,
        "generated_layout.json": layout_text,
        "generated_abi.h": abi_header(layout, header_version),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    output_root = arguments.root.resolve() / "lib" / "sdl3"
    generated = generate()
    if arguments.write:
        output_root.mkdir(parents=True, exist_ok=True)
        for name, contents in generated.items():
            (output_root / name).write_text(contents, encoding="utf-8")
        print(
            f"generated SDL3 inventory with "
            f"{json.loads(generated['generated_inventory.json'])['classification_counts']}"
        )
        return 0
    failures = []
    for name in OUTPUTS:
        path = output_root / name
        expected = generated[name]
        if not path.exists():
            failures.append(f"missing {path}")
        elif path.read_text(encoding="utf-8") != expected:
            failures.append(f"stale {path}")
    if failures:
        raise GenerationError("; ".join(failures))
    print("SDL3 generated provenance, inventory, and ABI assertions are current")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GenerationError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
