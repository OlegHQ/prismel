#!/usr/bin/env python3
"""Generate Clang-derived inventories for pinned stable SDL3 extensions."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
from typing import Any


GENERATOR_VERSION = "prismel-sdl3-extension-clang-inventory-v1"
OUTPUTS = (
    "generated_provenance.ml",
    "generated_inventory.json",
    "generated_abi.h",
)

EXTENSIONS = {
    "image": {
        "package": "sdl3-image",
        "directory": "sdl3_image",
        "include": "SDL3_image/SDL_image.h",
        "header_directory": "SDL3_image",
        "symbol_prefix": "IMG_",
        "macro_prefixes": ("IMG_", "SDL_IMAGE_"),
        "version_macros": (
            "SDL_IMAGE_MAJOR_VERSION",
            "SDL_IMAGE_MINOR_VERSION",
            "SDL_IMAGE_MICRO_VERSION",
        ),
        "include_env": "PRISMEL_SDL3_IMAGE_INCLUDE_DIR",
        "safe_functions": {
            "IMG_Version": "any-thread",
            "IMG_Load": "owned-result",
            "IMG_Load_IO": "owned-result-closes-io",
            "IMG_LoadTyped_IO": "owned-result-closes-io",
        },
    },
}


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


def pkg_config(package: str, argument: str) -> str:
    return run(["pkg-config", argument, package]).strip()


def discovery(config: dict[str, Any]) -> tuple[Path, list[str]]:
    include_override = os.environ.get(config["include_env"])
    if include_override:
        include_root = Path(include_override).resolve()
        cflags = [f"-I{include_root}"]
    else:
        include_root = Path(
            pkg_config(config["package"], "--variable=includedir")
        ).resolve()
        cflags = shlex.split(pkg_config(config["package"], "--cflags"))
    header = include_root / config["include"]
    if not header.is_file():
        raise GenerationError(f"extension header not found: {header}")
    return include_root, cflags


def compiler() -> str:
    return os.environ.get("PRISMEL_SDL3_CLANG", "clang")


def macro_map(
    clang: str, cflags: list[str], config: dict[str, Any]
) -> dict[str, str]:
    text = run(
        [
            clang,
            *cflags,
            "-x",
            "c",
            "-dM",
            "-E",
            "-include",
            config["include"],
            "/dev/null",
        ]
    )
    values: dict[str, str] = {}
    for line in text.splitlines():
        if not line.startswith("#define "):
            continue
        _, name, *parts = line.split(maxsplit=2)
        if not name.startswith(config["macro_prefixes"]):
            continue
        values[name] = parts[0] if parts else ""
    return values


def version(macros: dict[str, str], config: dict[str, Any]) -> tuple[int, int, int]:
    try:
        return tuple(int(macros[name]) for name in config["version_macros"])  # type: ignore[return-value]
    except (KeyError, ValueError) as error:
        raise GenerationError("extension version macros are missing or malformed") from error


def header_hashes(
    include_root: Path, config: dict[str, Any]
) -> tuple[list[dict[str, str]], str]:
    root = include_root / config["header_directory"]
    entries: list[dict[str, str]] = []
    aggregate = hashlib.sha256()
    for path in sorted(root.glob("*.h")):
        relative = f"{config['header_directory']}/{path.name}"
        contents = path.read_bytes()
        digest = hashlib.sha256(contents).hexdigest()
        entries.append({"path": relative, "sha256": digest})
        aggregate.update(relative.encode("utf-8"))
        aggregate.update(b"\0")
        aggregate.update(contents)
        aggregate.update(b"\0")
    return entries, aggregate.hexdigest()


def ast_inventory(
    clang: str, cflags: list[str], config: dict[str, Any]
) -> dict[str, list[dict[str, Any]]]:
    ast = json.loads(
        run(
            [
                clang,
                *cflags,
                "-x",
                "c",
                "-fsyntax-only",
                "-Xclang",
                "-ast-dump=json",
                "-include",
                config["include"],
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
    safe_functions = config["safe_functions"]
    prefix = config["symbol_prefix"]
    stack = [ast]
    while stack:
        node = stack.pop()
        stack.extend(node.get("inner", ()))
        kind = node.get("kind")
        name = node.get("name")
        if not isinstance(name, str) or not name.startswith(prefix):
            continue
        location = node.get("loc", {})
        source = location.get("file")
        header = (
            f"{config['header_directory']}/{Path(source).name}"
            if isinstance(source, str)
            else f"{config['header_directory']}/<clang-elided-source>"
        )
        base = {
            "name": name,
            "header": header,
            "classification": "safe" if name in safe_functions else "raw-only",
        }
        if kind == "FunctionDecl":
            base["signature"] = node.get("type", {}).get("qualType", "unknown")
            base["thread"] = safe_functions.get(name, "raw-only-not-reviewed")
            groups["functions"][name] = base
        elif kind in ("RecordDecl", "UnionDecl"):
            base["kind"] = "union" if node.get("tagUsed") == "union" else "struct"
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


def ocaml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def provenance_ml(
    header_version: tuple[int, int, int],
    aggregate_hash: str,
    clang_version: str,
    target: str,
    inventory: dict[str, list[dict[str, Any]]],
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
let stable_headers = {str(minor % 2 == 0 and patch % 2 == 0).lower()}
let header_sha256 = {ocaml_string(aggregate_hash)}
let clang_version = {ocaml_string(clang_version)}
let target_triple = {ocaml_string(target)}
let function_count = {function_count}
let safe_function_count = {safe_count}
"""


def abi_header(
    header_version: tuple[int, int, int], config: dict[str, Any]
) -> str:
    major, minor, patch = header_version
    include = config["include"]
    return f"""/* Generated by {GENERATOR_VERSION}; do not edit. */
#ifndef PRISMEL_SDL3_IMAGE_GENERATED_ABI_H
#define PRISMEL_SDL3_IMAGE_GENERATED_ABI_H
#include <{include}>
#include <SDL3/SDL.h>
_Static_assert(SDL_IMAGE_MAJOR_VERSION == {major}, "SDL3_image major changed");
_Static_assert(SDL_IMAGE_MINOR_VERSION == {minor}, "SDL3_image minor changed");
_Static_assert(SDL_IMAGE_MICRO_VERSION == {patch}, "SDL3_image patch changed");
typedef int (SDLCALL *prismel_img_version_fn)(void);
typedef SDL_Surface * (SDLCALL *prismel_img_load_fn)(const char *);
typedef SDL_Surface * (SDLCALL *prismel_img_load_io_fn)(SDL_IOStream *, bool);
typedef SDL_Surface * (SDLCALL *prismel_img_load_typed_io_fn)(SDL_IOStream *, bool, const char *);
_Static_assert(_Generic(&IMG_Version, prismel_img_version_fn: 1, default: 0),
  "IMG_Version signature/calling convention changed");
_Static_assert(_Generic(&IMG_Load, prismel_img_load_fn: 1, default: 0),
  "IMG_Load signature/calling convention changed");
_Static_assert(_Generic(&IMG_Load_IO, prismel_img_load_io_fn: 1, default: 0),
  "IMG_Load_IO signature/calling convention changed");
_Static_assert(_Generic(&IMG_LoadTyped_IO, prismel_img_load_typed_io_fn: 1, default: 0),
  "IMG_LoadTyped_IO signature/calling convention changed");
#endif
"""


def generate(extension: str) -> dict[str, str]:
    config = EXTENSIONS[extension]
    clang = compiler()
    include_root, cflags = discovery(config)
    macros = macro_map(clang, cflags, config)
    header_version = version(macros, config)
    headers, aggregate_hash = header_hashes(include_root, config)
    inventory_groups = ast_inventory(clang, cflags, config)
    clang_version = run([clang, "--version"]).splitlines()[0]
    target = run([clang, "-dumpmachine"]).strip()
    counts = {
        classification: sum(
            item["classification"] == classification
            for group in inventory_groups.values()
            for item in group
        )
        + (len(macros) if classification == "raw-only" else 0)
        for classification in (
            "safe",
            "raw-only",
            "platform-excluded",
            "not-applicable",
            "unreviewed",
        )
    }
    inventory = {
        "schema": 1,
        "generator": GENERATOR_VERSION,
        "extension": extension,
        "header_version": {
            "major": header_version[0],
            "minor": header_version[1],
            "patch": header_version[2],
        },
        "stable_headers": header_version[1] % 2 == 0
        and header_version[2] % 2 == 0,
        "header_sha256": aggregate_hash,
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
        "classification_counts": counts,
    }
    return {
        "generated_provenance.ml": provenance_ml(
            header_version,
            aggregate_hash,
            clang_version,
            target,
            inventory_groups,
        ),
        "generated_inventory.json": json.dumps(
            inventory, indent=2, sort_keys=True
        )
        + "\n",
        "generated_abi.h": abi_header(header_version, config),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    parser.add_argument("--extension", choices=sorted(EXTENSIONS), required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    config = EXTENSIONS[arguments.extension]
    output_root = arguments.root.resolve() / "lib" / config["directory"]
    generated = generate(arguments.extension)
    if arguments.write:
        output_root.mkdir(parents=True, exist_ok=True)
        for name, contents in generated.items():
            (output_root / name).write_text(contents, encoding="utf-8")
        counts = json.loads(generated["generated_inventory.json"])[
            "classification_counts"
        ]
        print(f"generated SDL3 {arguments.extension} inventory with {counts}")
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
    print(f"SDL3 {arguments.extension} generated inventory is current")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except GenerationError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1)
