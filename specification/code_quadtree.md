# Source Strata

`dune exec sketches/code_quadtree/main.exe` opens a native Metal code atlas.
The visual reference is a dense monochrome field of small marks, recursive
branches, and irregular clusters. `T` switches between branching connections
and visible quadtree cells. Scroll zooms around the pointer, click dives into a
file, drag pans, right click backs out, `R` resets, `H` hides the chrome, and
`S` captures the full native framebuffer to `_out/code-quadtree.png`.

## Data and interpretation

The sketch scans source files in sorted relative-path order, excluding build,
dependency, hidden, and symlink entries. It starts one `ocamllsp` subprocess,
initializes hierarchical document-symbol support, then opens, indexes, and
closes each OCaml document. Names, kinds, line ranges, and nested modules,
types, constructors, fields, functions, and values come from actual
`textDocument/documentSymbol` responses. Indexing completes and the language
server shuts down before SDL/Metal starts. `--lsp /path/to/ocamllsp` selects the
executable. A missing server or protocol error fails visibly.

The LSP contract is documented in the [LSP specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#textDocument_documentSymbol);
the server is [OCaml-LSP](https://github.com/ocaml/ocaml-lsp).

Each file occurs once in an asymmetric quadtree. Unequal quadrant budgets and
prefix-summed square-root line weights produce varying subdivision depths.
Within each file, the nested LSP symbol tree receives its own weighted spatial
layout. Internal packing branches are visualization structure; named branches
preserve the server's scope hierarchy. This is a containment/outline view, not
a call graph or reference graph. Hovering a visible symbol reports its actual
name and source range (displayed one-based).

The bottom inspector shows the hovered symbol's LSP kind/name, file, line
range, dot weight, and the first three source lines with line numbers. The
orange outline identifies that same symbol instead of always outlining the
whole file. A file-level hit shows file metadata and its first lines. Moving
into the sidebar/footer clears inspection. The footer reserves its own area,
so source previews do not obscure the atlas. Preview I/O occurs only when the
hover changes files: one current source file is retained, capped at 8 MiB of
input, with an explicit message for unavailable/oversized sources. Restart
to refresh the LSP/source snapshot after editing files.

Terminal halftone density encodes source span. Each glyph has fixed sample IDs
and normalized positions on a 16×16 grid. Zoom projects those same positions
using floating-point coordinates. The 1/4/16/64/256-sample levels fade in
continuously; their identity never depends on the screen-space grid size.
Projected sample count is bounded by glyph size: a two-point glyph uses one
representative, not sixteen overlapping subpixel marks. Full detail appears
at 64 logical points. Positive-density glyphs retain their representative.
Collapsed tree nodes crossfade into children rather than switching abruptly.
Function line marks use a 32-bin line-length profile. These marks
are visual texture, not additional invented symbols. Non-OCaml files remain
visibly hollow and are counted as unindexed. Empty OCaml symbol lists remain
empty; no synthetic functions are created.

The displayed dot weight is `25 + min(64, floor(12 * ln(span + 1)))`, where
`span` is the symbol's source-line span. It controls deterministic sample
occupancy, with a stable representative retained at low detail. It is not a
complexity score or a literal dot count: zoom controls which sample levels are
visible. The inspector and renderer use the same weight function for terminal
symbols. Parent symbols are marked `NESTED SCOPE`; their branches show their
children rather than stippling the parent's own weight.

`_build/code_quadtree/symbols.json` holds one atomically replaced snapshot for
the current root, server executable/version, and schema. Per-file source
digests invalidate changed entries; deleted files disappear on the next scan.
Warm launches still validate all source digests. There is no live watcher or
background editor session: restart to refresh source changes.

## Work and memory bounds

Scanning costs O(source bytes). Indexing cost belongs to OCaml-LSP and is
reported independently. File packing uses prefix weights and binary-search
cuts; its cost is O(F log F), with O(F) tree storage. Symbol packing recursively
partitions sibling arrays: O(S log S) work for broad sibling sets plus actual
scope depth, O(S) retained nodes. Each file also stores a fixed 32-entry profile.
Only one document is open in the server at a time.

Rendering culls whole offscreen subtrees, collapses subpixel nodes, and caps
terminal stipple grids at 16 by 16. Adjacent same-color marks merge in owned,
geometrically growing vertex/index buffers, preserving painter order. Lines
and strokes use the existing shared `Scene_command.Shape2`/`Path` tessellators. The
result is published through `Scene.display_list` with internal clipping and
stable segment identities; text remains the native font path. This is packed
triangle geometry, not hardware instancing. The renderer directly packs long
geometry runs with per-vertex colors before native resource preparation, avoiding
temporary per-color draw/cache work. The immutable artwork is cached
by camera, viewport, and cell mode. Hover and chrome have separate identities,
so pointer movement reuses the dense artwork. One complete scene is also
cached for an unchanged view/window/pointer. Both caches retain only the latest
view. Camera easing snaps to its target, allowing idle reuse.
Camera changes still rebuild visible geometry; the cache does not establish
constant-cost animated zoom. Interactive runs use real elapsed time for camera
easing and native vsync. Finite smoke/benchmark/export runs use the fixed clock
so their inputs remain reproducible.
There are no frame threads, new rasterizers, or public API additions.

## Verification and measurement

```sh
dune runtest lib/prismel_next_execution lib/scene_execution sketches/code_quadtree
dune exec sketches/code_quadtree/test_source_index.exe -- --live
dune exec sketches/code_quadtree/main.exe -- --verify
dune exec sketches/code_quadtree/main.exe -- --index-only
dune exec sketches/code_quadtree/main.exe -- --smoke --frames 600
tools/bench_code_quadtree.sh 120
tools/bench_code_quadtree.sh 60 hover
tools/bench_code_quadtree.sh 120 renderer
dune exec sketches/code_quadtree/main.exe -- --tour --frames 12 --domains 1 --export /tmp/strata-one
dune exec sketches/code_quadtree/main.exe -- --tour --frames 12 --domains 4 --export /tmp/strata-four
```

The pure fixture checks 1–9-file boundaries, exact coverage/picking, determinism,
and nonuniform depth for 1,024 files. The live LSP fixture checks nested scopes,
escaped file URIs, source ranges, cache reuse, source-change invalidation, and
shutdown. Packed marks are compared pixel-for-pixel against ordinary native
Scene rectangles, lines, and strokes, including alpha, clipping, and painter
order, including fractional rectangles against independently tessellated paths.
Both paths return to the same native live-handle count. The mark-field fixture
checks fixed sample identities, normalized positions under zoom and translation,
monotone detail, and continuity across all detail/diameter thresholds.

`--smoke` is a finite 120-frame zoom/pan/reset tour by default. `--frames`
overrides the limit. `--tour` applies the same repeatable motion to exports.
The benchmark compares equivalent ordinary Scene producers (`--reference-draws`)
with the packed producer; both use native Metal. Its native-run timing includes
window startup and teardown, and is not a steady-state GPU frame-time claim.
Wall time, allocation, promoted/major bytes, OCaml heap high-water mark, and
process maximum RSS are reported. See the measured evidence below.
`--hover-bench --zoom 1.45` exercises moving the pointer over a fixed dense view;
`--rebuild-art` supplies the former invalidation behavior on the same binary and
source snapshot. The benchmark reports artwork rebuild count separately.

### Local evidence, 2026-09-21

Working tree based on `2cc4297a`, including pre-existing user edits; this is not
a clean-commit GPU release qualification. Apple M1, arm64, macOS 26.2
(25C56), OCaml 5.3.0, Dune default development profile, one domain. Requested
window: 1440×1000 logical points; the desktop constrained the actual viewport
to 1440×802, captured at 2880×1604 native pixels.

The initial packing stage, before the later zoom/hover refinement,
`tools/bench_code_quadtree.sh 120`, one consecutive run per producer, used the
same 1,866-file snapshot: 1,853 OCaml files, 13 unindexed files, 96,727 LSP
symbols. Both used the same tour, scene reuse policy, dimensions, and native
Metal backend. Warm LSP indexing took 0.45–0.51 seconds. The earlier cold
1,864-file scan took 112.12 seconds; cold and warm figures measure different
operations and slightly different snapshots.

| Metric, total for 120 frames | Ordinary Scene producers | Packed producer |
|---|---:|---:|
| Native-run wall time, including startup/teardown | 15.168 s | 4.278 s |
| Process user CPU time | 14.26 s | 3.63 s |
| Allocated bytes | 30,722,521,496 | 6,878,831,392 |
| Promoted bytes | 3,480,538,320 | 539,903,032 |
| Major allocated bytes, including promotion | 5,036,640,320 | 2,462,345,928 |
| OCaml heap high-water bytes | 1,274,896,296 | 1,030,161,440 |
| Maximum process RSS bytes | 1,512,538,112 | 1,793,572,864 |
| macOS peak memory footprint bytes | 2,773,163,648 | 2,647,907,776 |

This reduces producer CPU work and allocation; it does **not** establish a
60-FPS bound or a lower maximum RSS. Other local runs took 40–49 seconds;
a one-second process sample found 616 of 698 main-thread samples waiting in
`CAMetalLayer nextDrawable`. Presentation stalls remain an observed separate
limit. The dense tour also still has a substantial transient memory footprint.

The focused scene-execution and sketch suites passed, including failure-path
cache invalidation and recovery, native pixel equivalence, and zero handle
deltas. The repository-wide `dune build @all` passed. Both dependency-direction
checks passed, including injected forbidden GPU reverse edges. A live OCaml-LSP
fixture passed nesting/ranges, source-change invalidation, URI escaping, and
shutdown checks.

Three native 12-frame zoom-tour exports (one domain, four domains, one-domain
repeat) were byte-identical for every corresponding PNG. The overview and
zoomed captures were visually inspected. The ordinary runtime performed
120-frame native tours; the underlying Metal regression also covered 600
stable frames and 60 frames with 257 distinct meshes. No 30-minute renderer
qualification or broad release-gate completion is claimed.

Raw measurements, source/executable hashes, and all capture hashes are in
[`evidence/code_quadtree/`](evidence/code_quadtree/).

### Zoom and hover refinement, 2026-09-21

The final comparison uses one binary and one unchanged 1,869-file snapshot
(1,856 OCaml files, 13 unindexed, 96,772 symbols), on the machine/profile above.
Each column is one run, with no concurrent tests or exports. Both renderer
variants include the corrected blend-cache matching and projected-density LOD;
only direct dense-run preparation is toggled. Thus this measures the renderer
change separately from visual LOD changes. Source changes can alter the atlas
layout substantially; timings from earlier snapshots are not exact baselines.

| 120-frame zoom/pan tour | Per-geometry preparation | Direct dense runs |
|---|---:|---:|
| Artwork rebuilds | 92 | 92 |
| Native-run wall time, including startup/teardown | 10.957 s | 7.405 s |
| Process user CPU time | 9.85 s | 6.46 s |
| Allocated bytes | 17,786,719,776 | 7,269,074,232 |
| Promoted bytes | 2,269,928,320 | 818,797,736 |
| Major allocated bytes, including promotion | 5,028,669,400 | 3,541,179,376 |
| OCaml heap high-water bytes | 1,240,990,288 | 1,177,942,408 |
| Maximum process RSS bytes | 2,078,081,024 | 2,186,280,960 |
| macOS peak footprint bytes | 3,223,659,520 | 3,268,862,848 |

| 60-frame moving-hover test, 1.45× zoom | Rebuild on hover | Retain artwork |
|---|---:|---:|
| Artwork rebuilds | 60 | 1 |
| Native-run wall time, including startup/teardown | 5.039 s | 1.983 s |
| Process user CPU time | 5.09 s | 2.00 s |
| Allocated bytes | 5,343,933,592 | 199,033,016 |
| Promoted bytes | 842,894,304 | 25,404,736 |
| Major allocated bytes, including promotion | 2,020,271,904 | 96,496,544 |
| OCaml heap high-water bytes | 818,655,976 | 290,392,520 |
| Maximum process RSS bytes | 1,033,535,488 | 436,404,224 |
| macOS peak footprint bytes | 1,033,294,400 | 435,784,768 |

The renderer comparison reduces allocated bytes by 59%; retaining artwork
reduces hover-test allocation by 96%. Dense animated views still rebuild
geometry and retain a substantial transient footprint. These total-run figures
do not establish a 60-FPS guarantee or lower animated-view maximum RSS.
Hardware instancing has not been introduced.

The final native regression compares 63/64/65/1,024 overlapping primitives
against identity-barrier reference preparation, with alpha/additive blending,
fractional transforms, clipping, repeated frames, 1×/2× backing resolution,
and no live-handle delta. It exposed and now guards against cross-blend batch
reuse. The full build, focused renderer/sketch tests, and both dependency
direction checks passed.

Final four-frame native zoom/pan exports were byte-identical between one domain,
four domains, and the diagnostic reference renderer. Four moving-hover frames
were also byte-identical with artwork retention enabled and disabled. The
1.47× and 2.55× captures were visually inspected. These final captures and the
two controlled benchmark pairs have separate hashes/raw logs in the evidence
directory, alongside the earlier-stage results.

### Hover inspector and retained-scene correction, 2026-09-22

The disappearing-geometry report led to a failing native regression: render
a retained white scene, render a different retained dark scene with the same
local mesh labels, then revisit the white scene. The old trusted-key path
incorrectly reused the dark payload. The corrected lookup requires the exact
immutable uploaded source before bypassing payload checks. Twelve alternations
at both backing scales now preserve exact pixels and leave no native handles.

The full build, focused scene-execution/native-lowering/sketch tests, and both
dependency checks passed. Four deep-zoom moving-hover captures matched exactly
with artwork retention enabled and disabled. Native screenshots verified file
previews and an indexed local-variable preview with its actual source line.
The source-preview fixture checks line ranges/numbers, reuse of the current
file, UTF-8 truncation, and the shared span-to-density scale.

The automatic-scratch benchmark still passes 1,000 frames: 35,579 allocated /
31.7 promoted bytes for 10 draws and 273,627 / 1,777.6 bytes for 84 draws per
frame. The preceding result was 35,419 / 28.6 and 272,283 / 1,597.5 respectively;
the extra source-identity metadata adds about 0.5% allocation. The remembered
CPU source per cache slot is capped by that slot's existing GPU byte budget.
The final 60-frame hover benchmark and source hashes are recorded separately
in `evidence/code_quadtree/inspector_*_2026-09-22.txt`.
