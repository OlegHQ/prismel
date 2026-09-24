# Source Atlas

A native Metal sketch of the repository's source files. Each terminal square is
one real file; the four-way spatial index groups paths in sorted order. Color
marks library, test, sketch, example, and tooling files. Brightness distinguishes
larger files. Directory names and file names appear as their cells grow on
screen. The source tree is scanned once at startup; no language server or
external service is required.

```sh
dune exec sketches/code_quadtree/main.exe
dune exec sketches/code_quadtree/main.exe -- --root /path/to/repository
```

Scroll to zoom toward the pointer. Click a cell to dive into it, drag with the
left or middle button to pan, and right click to step back. `R` or Space resets
the view; `H` or Tab hides the overlay; `S` saves `_out/code-quadtree.png`; Escape
quits. For a clean recording, hide the overlay after an introductory shot.

Finite native validation and one-frame export:

```sh
dune exec sketches/code_quadtree/main.exe -- --smoke
dune exec sketches/code_quadtree/main.exe -- --export /tmp/source-atlas
```

The scanner skips `.git`, `_build`, hidden paths, and vendor directories. It
indexes OCaml, C/C++, Metal, and Dune source files. The quadtree holds O(files)
nodes and culls cells outside the viewport. Tiny cells are drawn as a single
mark; detailed borders and labels appear only above screen-size thresholds.
