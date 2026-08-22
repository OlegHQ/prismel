#!/usr/bin/env python3
"""Freeze Prismel's pre-SDL3 public and declared legacy API surfaces."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Iterable


SCHEMA = 1
BASELINE_RELATIVE = Path(
    "specification/evidence/gpu_migration/phase0_baseline.json"
)
STABLE_RELATIVE = Path(
    "specification/evidence/gpu_migration/api_stable.json"
)
LEGACY_RELATIVE = Path(
    "specification/evidence/gpu_migration/api_legacy_sdl.json"
)

STABLE_LIBRARY_DIRS = (
    "prismel",
    "pdk",
    "geom",
    "procedural",
    "pxui",
    "pxui_graph",
    "sop_catalog",
    "sop_ui",
    "sketch",
    "sketch_ui",
    "wap",
)

MIXED_LEGACY = {
    ("prismel", "Font"): ("module:Private", "value:release_renderer"),
    ("prismel", "Image"): ("module:Private",),
}


class ManifestError(RuntimeError):
    pass


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def tokenize_sexp(source: str) -> list[str]:
    tokens: list[str] = []
    index = 0
    while index < len(source):
        character = source[index]
        if character.isspace():
            index += 1
        elif character == ";":
            newline = source.find("\n", index + 1)
            index = len(source) if newline < 0 else newline + 1
        elif character in "()":
            tokens.append(character)
            index += 1
        elif character == '"':
            index += 1
            value: list[str] = []
            escaped = False
            while index < len(source):
                character = source[index]
                index += 1
                if escaped:
                    value.append(character)
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == '"':
                    break
                else:
                    value.append(character)
            else:
                raise ManifestError("unterminated string in Dune file")
            tokens.append("".join(value))
        else:
            stop = index
            while (
                stop < len(source)
                and not source[stop].isspace()
                and source[stop] not in "();"
            ):
                stop += 1
            tokens.append(source[index:stop])
            index = stop
    return tokens


Sexp = str | list["Sexp"]


def parse_sexps(tokens: list[str]) -> list[Sexp]:
    index = 0

    def parse_one() -> Sexp:
        nonlocal index
        if index >= len(tokens):
            raise ManifestError("unexpected end of Dune file")
        token = tokens[index]
        index += 1
        if token == ")":
            raise ManifestError("unexpected closing parenthesis in Dune file")
        if token != "(":
            return token
        values: list[Sexp] = []
        while index < len(tokens) and tokens[index] != ")":
            values.append(parse_one())
        if index >= len(tokens):
            raise ManifestError("unterminated list in Dune file")
        index += 1
        return values

    values: list[Sexp] = []
    while index < len(tokens):
        values.append(parse_one())
    return values


def stanza_field(stanza: list[Sexp], name: str) -> list[Sexp] | None:
    for item in stanza[1:]:
        if isinstance(item, list) and item and item[0] == name:
            return item[1:]
    return None


def flatten_atoms(values: Iterable[Sexp]) -> list[str]:
    result: list[str] = []
    for value in values:
        if isinstance(value, str):
            result.append(value)
        else:
            result.extend(flatten_atoms(value))
    return result


def library_stanza(path: Path) -> list[Sexp]:
    forms = parse_sexps(tokenize_sexp(path.read_text(encoding="utf-8")))
    for form in forms:
        if isinstance(form, list) and form and form[0] == "library":
            return form
    raise ManifestError(f"{path}: no library stanza")


def module_name(stem: str) -> str:
    return stem[0].upper() + stem[1:]


def public_interfaces(root: Path, directory_name: str) -> list[tuple[str, Path]]:
    directory = root / "lib" / directory_name
    stanza = library_stanza(directory / "dune")
    explicit = stanza_field(stanza, "modules")
    if explicit is None:
        stems = {path.stem for path in directory.glob("*.ml") if "." not in path.stem}
        stems.update(
            path.stem for path in directory.glob("*.mli") if "." not in path.stem
        )
    else:
        stems = {
            atom.lower()
            for atom in flatten_atoms(explicit)
            if atom not in {":standard", "\\"} and not atom.startswith(":")
        }
    private = {
        atom.lower()
        for atom in flatten_atoms(stanza_field(stanza, "private_modules") or [])
    }
    sources = {
        path.stem.lower(): path
        for path in directory.glob("*.mli")
        if "." not in path.stem
    }
    interfaces: list[tuple[str, Path]] = []
    for stem in sorted(stems - private):
        source = sources.get(stem.lower())
        if source is None:
            implementation = directory / f"{stem}.ml"
            if implementation.exists():
                raise ManifestError(
                    f"public module {directory_name}.{module_name(stem)} has no .mli"
                )
            continue
        interfaces.append((module_name(source.stem), source))
    return interfaces


def lexical_tokens(source: str) -> list[tuple[str, int, int]]:
    tokens: list[tuple[str, int, int]] = []
    index = 0
    while index < len(source):
        if source.startswith("(*", index):
            depth = 1
            index += 2
            while index < len(source) and depth:
                if source.startswith("(*", index):
                    depth += 1
                    index += 2
                elif source.startswith("*)", index):
                    depth -= 1
                    index += 2
                else:
                    index += 1
            if depth:
                raise ManifestError("unterminated OCaml comment")
        elif source[index].isspace():
            index += 1
        elif source[index] in {'"', "'"}:
            quote = source[index]
            start = index
            index += 1
            escaped = False
            while index < len(source):
                character = source[index]
                index += 1
                if escaped:
                    escaped = False
                elif character == "\\":
                    escaped = True
                elif character == quote:
                    break
            tokens.append((source[start:index], start, index))
        else:
            start = index
            if source[index].isalnum() or source[index] in "_`":
                index += 1
                while index < len(source) and (
                    source[index].isalnum() or source[index] in "_'.`"
                ):
                    index += 1
            else:
                index += 1
                if index < len(source) and source[start:index + 1] in {
                    "->", "=>", ":=", "::", "<=", ">=", "<>", "||", "&&"
                }:
                    index += 1
            tokens.append((source[start:index], start, index))
    return tokens


def module_range(source: str, name: str) -> tuple[int, int]:
    tokens = lexical_tokens(source)
    for index in range(len(tokens) - 3):
        if (
            tokens[index][0] == "module"
            and tokens[index + 1][0] == name
            and tokens[index + 2][0] == ":"
            and tokens[index + 3][0] == "sig"
        ):
            depth = 1
            cursor = index + 4
            while cursor < len(tokens):
                token = tokens[cursor][0]
                if token == "sig":
                    depth += 1
                elif token == "end":
                    depth -= 1
                    if depth == 0:
                        return tokens[index][1], tokens[cursor][2]
                cursor += 1
            raise ManifestError(f"unterminated module {name}")
    raise ManifestError(f"module {name} not found")


def value_range(source: str, name: str) -> tuple[int, int]:
    tokens = lexical_tokens(source)
    starters = {"class", "exception", "external", "include", "module", "type", "val"}
    for index in range(len(tokens) - 1):
        if tokens[index][0] == "val" and tokens[index + 1][0] == name:
            start = tokens[index][1]
            cursor = index + 2
            while cursor < len(tokens):
                if tokens[cursor][0] in starters:
                    return start, tokens[cursor][1]
                cursor += 1
            return start, len(source)
    raise ManifestError(f"value {name} not found")


def selected_range(source: str, selector: str) -> tuple[int, int]:
    kind, name = selector.split(":", 1)
    if kind == "module":
        return module_range(source, name)
    if kind == "value":
        return value_range(source, name)
    raise ManifestError(f"unknown legacy selector {selector}")


def without_ranges(source: str, ranges: Iterable[tuple[int, int]]) -> str:
    result = source
    for start, stop in sorted(ranges, reverse=True):
        result = result[:start] + result[stop:]
    return result


def normalized_api(source: str) -> bytes:
    return " ".join(token for token, _, _ in lexical_tokens(source)).encode("utf-8")


def source_entry(
    root: Path,
    library: str,
    module: str,
    path: Path,
    selectors: tuple[str, ...] = (),
) -> dict[str, object]:
    source_bytes = path.read_bytes()
    source = source_bytes.decode("utf-8")
    filtered = without_ranges(source, (selected_range(source, item) for item in selectors))
    return {
        "library": library,
        "module": module,
        "source": path.relative_to(root).as_posix(),
        "source_bytes": len(source_bytes),
        "source_sha256": sha256_bytes(source_bytes),
        "api_sha256": sha256_bytes(normalized_api(filtered)),
        "excluded_legacy_symbols": list(selectors),
    }


def legacy_entry(
    root: Path,
    surface: str,
    path: Path,
    selectors: tuple[str, ...] = (),
) -> dict[str, object]:
    source_bytes = path.read_bytes()
    source = source_bytes.decode("utf-8")
    selected = source
    if selectors:
        parts = []
        for selector in selectors:
            start, stop = selected_range(source, selector)
            parts.append(source[start:stop])
        selected = "\n".join(parts)
    return {
        "surface": surface,
        "source": path.relative_to(root).as_posix(),
        "source_sha256": sha256_bytes(source_bytes),
        "api_sha256": sha256_bytes(normalized_api(selected)),
        "selectors": list(selectors),
    }


def generate(root: Path) -> tuple[dict[str, object], dict[str, object]]:
    baseline = json.loads((root / BASELINE_RELATIVE).read_text(encoding="utf-8"))
    stable_entries: list[dict[str, object]] = []
    for directory_name in STABLE_LIBRARY_DIRS:
        for module, path in public_interfaces(root, directory_name):
            if (directory_name, module) == ("prismel", "Low"):
                continue
            selectors = MIXED_LEGACY.get((directory_name, module), ())
            stable_entries.append(
                source_entry(root, directory_name, module, path, selectors)
            )
    stable_entries.sort(key=lambda item: (str(item["library"]), str(item["module"])))

    legacy_entries = [
        legacy_entry(root, "Prismel.Low", root / "lib/prismel/low.mli"),
        legacy_entry(root, "Prismel.Low.App", root / "lib/prismel/app.mli"),
        legacy_entry(root, "Prismel.Low.Backend", root / "lib/prismel/backend.mli"),
        legacy_entry(root, "Prismel.Low.Graphics", root / "lib/prismel/graphics.mli"),
        legacy_entry(root, "Prismel.Low.Window", root / "lib/prismel/window.mli"),
        legacy_entry(
            root,
            "Prismel.Image.Private",
            root / "lib/prismel/image.mli",
            ("module:Private",),
        ),
        legacy_entry(
            root,
            "Prismel.Font.Private",
            root / "lib/prismel/font.mli",
            ("module:Private",),
        ),
        legacy_entry(
            root,
            "Prismel.Font.release_renderer",
            root / "lib/prismel/font.mli",
            ("value:release_renderer",),
        ),
    ]
    for module, path in public_interfaces(root, "runtime"):
        legacy_entries.append(legacy_entry(root, f"Runtime.{module}", path))
    legacy_entries.sort(key=lambda item: str(item["surface"]))

    common = {
        "schema": SCHEMA,
        "baseline_commit": baseline["baseline_commit"],
        "baseline_plan_sha256": baseline["new_gpu_stuff_sha256"],
        "generator": "tools/gpu_migration/api_manifest.py",
    }
    stable = {
        **common,
        "kind": "stable_high_level",
        "module_count": len(stable_entries),
        "modules": stable_entries,
    }
    legacy = {
        **common,
        "kind": "declared_legacy_sdl",
        "surface_count": len(legacy_entries),
        "surfaces": legacy_entries,
    }
    return stable, legacy


def encoded(value: dict[str, object]) -> str:
    return json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def check_file(path: Path, expected: str) -> bool:
    if not path.exists():
        print(f"missing generated manifest: {path}", file=sys.stderr)
        return False
    actual = path.read_text(encoding="utf-8")
    if actual != expected:
        print(
            f"stale generated manifest: {path}\n"
            "run tools/gpu_migration/api_manifest.py --write",
            file=sys.stderr,
        )
        return False
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path.cwd())
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    root = arguments.root.resolve()
    stable, legacy = generate(root)
    outputs = (
        (root / STABLE_RELATIVE, encoded(stable)),
        (root / LEGACY_RELATIVE, encoded(legacy)),
    )
    if arguments.write:
        for path, value in outputs:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(value, encoding="utf-8")
        print(
            f"wrote {len(stable['modules'])} stable modules and "
            f"{len(legacy['surfaces'])} legacy surfaces"
        )
        return 0
    return 0 if all(check_file(path, value) for path, value in outputs) else 1


if __name__ == "__main__":
    raise SystemExit(main())
