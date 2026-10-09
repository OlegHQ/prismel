# Performance measurement log

Append-only record of measurements taken for [performance.md](performance.md); it is not normative.

## Phase 4 edit and kernel baseline (2026-10-07)

Apple M1, Darwin arm64, eight available cores, OCaml 5.3.0, Dune 3.24.2,
dev profile. Editor benchmarks use one cook domain and dummy SDL video/audio;
each edit measurement includes a `Set_arg` on `g/s0 :points`, followed by a full
editor update with the primary pointer held. There are 200 samples per size.
Timings use `Unix.gettimeofday`, clamped against backward readings within an
edit sample. Phase durations are exclusive of nested phases; total frame time
also includes UI construction, document derivation and allocation/GC overhead.

Commands (build with `_build/default/tools/check.exe` first):

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200 1000 2000
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/test/test_drawing.exe examples/particles/sketch.rays --bench
_build/default/tools/bench_kernel.exe
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 7
```

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.134 | 6.938 | 11.798 | 17,552,070 |
| 1,000 | 7.290 | 35.982 | 63.743 | 74,892,992 |
| 2,000 | 12.523 | 78.056 | 157.429 | 136,882,613 |

| Exclusive phase median ms | 200 | 1,000 | 2,000 |
| --- | ---: | ---: | ---: |
| Print | 0.618 | 3.899 | 12.017 |
| Parse | 0.183 | 0.938 | 2.538 |
| Check | 1.145 | 5.234 | 10.676 |
| Evaluate | 0.218 | 1.808 | 4.400 |
| Lower | 0.934 | 3.921 | 7.910 |
| Project | 0.536 | 3.128 | 6.292 |
| Layout | 0.863 | 5.045 | 11.867 |
| Reduce | 0.030 | 0.151 | 0.321 |
| Cook scheduling/resolve/compile | 0.436 | 4.879 | 8.843 |

The cook phase measures the editor-side cook boundary, including synchronous
awaits when requested. Background cook durations remain the worker's own
reported timings. Individual phase medians do not sum to the total median.

The dynamic 10,000-particle editor frame, with its state fold advancing,
has median 31.690 ms, p95 32.145 ms and 148,126,467 allocated bytes/frame
(10 warm-up frames and 200 measured frames). This measures evaluation, canvas
drawing and the host frame; no GPU presentation is included.

The 1,000 × 1,000 point grid noise-displacement benchmark uses amplitude 0.8,
frequency 0.16, seed 42, grain 16,384 and seven samples after one warm-up.
RDK medians: one domain 55.700 ms / 32,064,368 allocated bytes; eight domains
8.737 ms / 32,075,624 bytes. Both have position hash
`1a9b19459a403094e2683996bd183a75` (MD5 of the marshaled xyz arrays, no sharing).
Every sample checks the hash; the one/eight-domain results are also compared.
The Lisp-kernel comparison remains a Step 4 gate.

Workspace baseline, seven repeats, medians in ms (the tool subtracts standalone
check/evaluation from total lowering for its `lower` column):

| Fixture | Check | Eval | Lower | Cold cook | Lower + cook | Nodes | Eval bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| bloom | 0.091 | 0.115 | 3.579 | 0.599 | 5.107 | 84 | 514808 |
| facade | 0.037 | 0.079 | 1.785 | 0.546 | 2.464 | 69 | 320176 |
| garland | 0.071 | 0.077 | 2.146 | 0.899 | 2.962 | 40 | 347704 |
| kit | 0.064 | 0.033 | 0.965 | 0.086 | 1.113 | 24 | 127096 |
| orrery | 0.050 | 0.148 | 2.389 | 0.377 | 3.125 | 56 | 627288 |
| rosette | 0.044 | 0.046 | 2.218 | 0.375 | 2.649 | 39 | 197640 |
| sunflower | 0.020 | 1.146 | 11.797 | 3.246 | 14.186 | 241 | 4310640 |
| tiles | 0.025 | 0.388 | 7.474 | 0.955 | 9.051 | 193 | 1215432 |
| tree | 0.024 | 0.017 | 1.685 | 0.591 | 2.432 | 27 | 74376 |
| tunnel | 0.023 | 0.022 | 1.617 | 4.375 | 5.688 | 37 | 101488 |
| variations | 0.037 | 0.020 | 0.734 | 0.159 | 0.983 | 30 | 95840 |
| wave | 0.027 | 4.670 | 5.792 | 0.744 | 11.612 | 13 | 16494536 |

At capacity 512, retained entries/payload MB are bloom 52/1.22,
sunflower 241/1.84, wave 13/0.66 and tree 27/0.87, with zero evictions.
Their warm cook times are 0.035, 0.186, 0.031 and 0.021 ms respectively.

## Test validation baseline (2026-10-05)

Apple M1 Mac mini (`Macmini9,1`), 8 cores, 16 GiB, OCaml 5.3.0,
Dune 3.24.2, dev profile, warm build artifacts. These are individual timing
samples, not medians or timing gates. Forced runs set
`SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy`; native smoke uses native drivers.

| Measurement | Before | After |
| --- | ---: | ---: |
| Original full test selection, forced execution | 66.36 s | 47.85 s |
| Studio fracture, isolated, identical checks | 48.98 s | 29.93 s |
| Dependency gate, isolated, identical policy | 4.19 s | 1.23 s |
| Standard selection, forced execution | — | 18.78 s |
| Cached standard validation | — | 0.65 s |
| Cached shipping (`@all`, `@runtest`, `@smoke`, diff check) | — | 1.00 s |
| 20 simultaneous cached standard requests, all completed | Dune lock errors | 12.50 s total |

The full-selection speedup reuses the one-domain fracture session for downstream
material validation while keeping the four-domain fracture cook independent,
and uses standard-library literal searching in the dependency gate. The standard
selection separately makes large/exhaustive fixtures optional and moves real
GPU renderer integration and presentation timeouts to native validation;
its timing is **not** an equivalent-coverage comparison with the original full
selection. Changing code invalidates relevant Dune actions, so cached timings
do not promise subsecond execution of changed tests. The queued-request result
uses an unchanged worktree; each request still asks Dune to validate it.

Reproduce standard timing after `dune build tools/check.exe`:

```sh
/usr/bin/time -p env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  _build/default/tools/check.exe @runtest --force --trace-file=/tmp/rays-tests.trace
/usr/bin/time -p env SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy \
  _build/default/tools/check.exe
/usr/bin/time -p _build/default/tools/check.exe --ship
```

For per-action timing, use Dune's trace reader:
`dune trace cat --chrome-trace --trace-file=/tmp/rays-tests.trace`.
Optional suites and focused aliases are listed in [workflow.md](workflow.md).

### Recheck after pulling dev at `a200ea5`

The 50-commit update rebuilt `@all` and `@check` in 28.63 s. A first forced
run exposed a stale workspace test click and a 27.21 s real-GPU path-tracer
action in the standard selection. The click now dismisses through the status
strip; the native film-step fixture uses a 1200-point window so the new viewport
margins preserve the tested boundary crossing. Path-tracer integration checks
are now optional under `@runtest-native` and `@qualification`; their original
checks passed on this device. This is a selection change, not a GPU speedup.

| Recheck, same machine/profile | Earlier sample | After pull and fixes |
| --- | ---: | ---: |
| Forced standard selection | 18.78 s | 16.50 s |
| Cached standard validation | 0.65 s | 0.58 s |
| Cached shipping | 1.00 s | 0.81 s |
| 20 simultaneous cached standard requests, all passed | 12.50 s total | 11.59 s total |

Final shipping and native film/slot checks passed. Native SOP parity matched
one/four-domain PNGs for 23 graphs. PXUI golden-image checks skipped on this
1x display because their fixtures are 2x; this run does not verify those images.

## Workload classes

### SOP graph interaction smoke baseline

Cluster layout check (2026-09-28), Apple M1, arm64, OCaml 5.3.0,
default Dune profile, UI on the initial domain: three standalone runs of
`_build/default/test/test_main.exe test_pxui_graph_smoke`, after
`dune build test/test_main.exe`. The 2,001-node / 2,000-edge construction and
paint median was 592.405 ms before and 578.215 ms after; allocations were
618,720,816 and 619,691,160 bytes. Before substitutes only the HEAD
`automatic_layout` into the same working tree, retaining the ongoing UI
changes; this is not a comparison with the historical M1 runtime below.
The sample does not establish a speedup. The cube-cage regression checks
separated branches and wire/card collisions, with repeat layout at point
zoom producing the same positions as card zoom. To inspect a finite native
render of that fixture:

```sh
RAYS_LAYOUT_PNG=/tmp/cube-cage-layout.png dune exec test/test_main.exe -- test_pxui_graph
```

The focused graph test includes a 2,001-node/2,000-wire fan-in graph, validates
packed graph cardinality, off-screen node and row culling, and materializes
one scene. `test_pxui_graph_smoke` runs that same check in isolation. The
historical standalone runner measured 0.08 s on 2026-08-06; the consolidated
runner and expanded interaction coverage make that process time unsuitable
for comparing M1. The matched M1 check measures construction and painting
inside the test, excluding executable startup.

```sh
dune build test/test_main.exe
_build/default/test/test_main.exe test_pxui_graph_smoke
```

M1 measurements, 2026-09-27, Apple M1 MacBookAir10,1, 16 GB, arm64,
OCaml 5.3.0, default Dune profile. Before is `af55fffc` in a detached
worktree; both graph benchmarks use the corrected header press, pointer
position before zoom, and release between cases. Timings below are medians
unless marked as a single release or undo. Allocations are decimal MB.

| Check | Before | M1 | Allocation before → M1 |
|---|---:|---:|---:|
| 2,001-node fan-in construction and paint, three runs | 242.494 ms | 228.773 ms | 414.036 → 359.484 MB |
| 100-node static frame, 100 samples | 0.213 ms | 0.224 ms | 1.016 → 0.869 MB/frame |
| 1,000-node static frame | 0.214 ms | 0.267 ms | 0.973 → 1.040 MB/frame |
| 10,000-node static frame | 0.216 ms | 0.261 ms | 0.973 → 1.040 MB/frame |
| 10,000-node wire-hit p99, 10,000 queries | 2.861 µs | 1.192 µs | 41.639 → 9.572 MB total |
| 10,000-node move, ten frames | 0.246 ms | 0.296 ms | 10.004 → 10.997 MB total |
| 19,950-wire single-node release | 10.777 ms | 13.484 ms | 13.939 → 21.772 MB |
| 19,950-wire 100-node release | 11.657 ms | 14.079 ms | 14.251 → 22.133 MB |
| 10,000-node minimum-zoom pan, ten frames | 1.244 ms | 1.352 ms | 38.336 → 45.812 MB total |

The new layout shows 43 nodes in the layered graph viewport, versus 30
before. The wire BVH keeps one leaf per wire; a candidate scans its exact
polyline segments. The largest query sample had ten candidates, versus three
before. A trial with one leaf per segment increased the 19,950-wire release
to about 25 ms and 34 MB, so it was removed. Release still rebuilds the full
wire index; refitting affected leaves is the upgrade if release latency
exceeds the frame budget.

All-points M1: static frames at 100/1,000/10,000 nodes were
0.202/0.228/0.230 ms, allocating 1.016/0.911/0.911 MB/frame. The
10,000-node drag was 0.273 ms; release was 13.229 ms and 21.822 MB.
Minimum-zoom pan was 1.376 ms and remained one native UI batch.

The host benchmark includes scene navigation and history:

| Nodes | Drag before → M1 | Allocation before → M1 | Undo before → M1 (single sample) |
|---|---:|---:|---:|
| 200 | 0.138 → 0.170 ms | 0.563 → 0.589 MB/frame | 0.184 → 0.201 ms |
| 1,000 | 0.137 → 0.158 ms | 0.552 → 0.602 MB/frame | 1.229 → 1.497 ms |
| 2,000 | 0.196 → 0.168 ms | 0.552 → 0.602 MB/frame | 28.428 → 58.090 ms |

Undo restores a complete saved layout and schedules cooking; its large-case
single sample varies substantially between runs (the earlier M1 run was
45.316 ms). It is outside the held-pointer loop. These measurements do not
establish an undo latency guarantee.

M2's ACTIVE-camera bypass guard was measured immediately before and after
the guard on the same machine/profile, with
`dune exec tools/bench_rays_editor.exe -- 2000` (200 held-pointer updates,
UI on the initial domain; seven cook domains, the default on this machine).
Median drag time was 0.164 → 0.162 ms and p95
1.565 → 1.554 ms; allocation was 602,507 → 602,603 bytes/frame. This sample
does not distinguish a timing change; the extra lookup adds 96 bytes/frame.
The one undo sample was 7.639 → 19.009 ms, consistent with the variability
above rather than a latency guarantee.

M2 guide UI and row hover were measured around the guide change using the
same 2,000-node host benchmark, machine, domain count and profile. Median
drag time was 0.185 → 0.175 ms, p95 2.467 → 2.054 ms, and allocation
602,603 → 635,543 bytes/frame. The guide and additional shared row boxes add
32,940 bytes/frame in this sample. The one undo sample was 18.208 → 24.673 ms;
these timings do not establish an improvement. An intermediate strip fitter
remeasured every growing prefix and allocated 711,639 bytes/frame; measuring
each word once removed 76,096 bytes/frame from that intermediate version.
The 2,001-node fan-in smoke allocated
358,455,424 bytes and completed in 0.245 seconds in the focused suite.

```sh
dune exec tools/bench_pxui_graph.exe
dune exec tools/bench_pxui_graph.exe -- --points
dune exec tools/bench_rays_editor.exe -- 200 1000 2000
```

M3's standalone value-lane benchmark now measures 200 scalar SOP rows on the
same M1 MacBook Air / 16 GB, OCaml 5.3.0, dev profile, one initial domain.
Each row controls a one-point parameterized SOP; cooking and rendering are
outside the measurement. Seven samples each resolve 1,000 frames after warm-up;
the reported time is the median of those seven frame averages.

| Lane case | Time per resolution | Allocation per resolution |
|---|---:|---:|
| No drives | 0.000003 ms | 0.096 B |
| 200 static expression drives | 0.000003 ms | 0.096 B |
| 200 rows driven by one Time output | 0.315129 ms | 901,745.696 B |

The two cached cases retain their result. Their 96 B per sample is fixed
measurement overhead; the resolution loop adds no per-call allocation.
Dynamic values rebuild the 200 SOP literal copies and their packed snapshots;
these figures are a baseline, not an improvement claim or a native frame
latency guarantee. After M3 host integration, the same command measured
0.000004 ms / 0.096 B for no drives, the same for cached static drives, and
0.319713 ms / 901,745.696 B for 200 Time drives. The two dynamic timings are
within run-to-run noise; the value lane itself did not change.

The M3 editor frame comparison uses
`dune exec tools/bench_rays_editor.exe -- 2000` on the same machine,
profile and seven cook domains. The M2 guide checkpoint was 0.175 ms median,
2.054 ms p95 and 635,543 B per held-pointer frame. Three M3 runs gave median
times 0.314951, 0.214100 and 0.200033 ms, p95 times 2.651930, 2.565861
and 2.701044 ms, and 679,823 B/frame throughout. The median of
those run medians is 0.214100 ms, with 44,280 B/frame more allocation than the
M2 checkpoint. This measures the full updated UI, including value metadata
and inspector work, rather than isolating the value lane. Single-run timing
and p95 vary, so these numbers are workload observations, not a latency bound.

The shared unchanged-parameter-write path was also measured before and after
its identity guard: 1,000,000 writes to one parameterized one-point SOP on the
same machine/profile/domain, after 100 warm-up writes. Allocation fell from
832 to 672 B/write and all 1,000,000 results retained the original editable
graph, versus none before. Single-run timings were 96.151 and 84.649 ns/write;
they do not establish a timing improvement. The check is in
`lib/procedural/test_edit_graph.ml`; the temporary measurement source is
`/tmp/rays-flow-unchanged-write-bench.ml`, with its temporary Dune stanza
removed after measurement.

M3's named geometry slots were checked with the same 2,001-node/2,000-wire
fan-in smoke. A first pass converted the 2,000-slot name array to a list for
each wire and allocated 582,643,272 B, versus the earlier 358,455,424 B.
Reading names once per consumer reduced the isolated check to 358,611,352 B
and 0.220 s (one run, default Dune profile on the same machine). The
155,928 B allocation difference from the earlier smoke is small; the timing
sample is not evidence of a speed change.

```sh
dune exec tools/bench_flow_value_lane.exe -- 200 1000
```

This is a repeatable scale smoke baseline, not a claim that every wire-heavy
graph has constant frame cost: scene traversal remains O(nodes + wires), while
unchanged graph replacement is an identity fast path and node scene allocation
is restricted to visible tiles.

## Representation rules

- _Continues "RDK reverse topology uses packed integer CSR/half-edge planes…" in performance.md:_
  The former weld path moved
  into RDK Fuse, cutting the 200,000-point one-domain fixture from 64.5 ms and
  78.9 MB allocated to 50.2 ms and 48.2 MB with identical cardinality.
- _Continues "Filtered exact RDK orientation predicates expose packed SoA/index…" in performance.md:_
  Five million release-build
  `orient2d` and `orient3d` calls take 32.814 ms and 61.093 ms respectively,
  with 0 bytes allocated or promoted. Five million exact-feature
  segment/triangle classifications take 334.656 ms; five million generic
  non-coplanar triangle/triangle feature classifications take 1.848 s, both at
  the same zero-allocation floor. Before the packed scratch arena, exact
  edge/edge-degenerate triangle pairs allocated 5,176 bytes/pair,
  deliberately ambiguous `orient2d` allocated 1,024 bytes/call, and
  underflowing `orient3d` allocated 576 bytes/call. The exact homogeneous
  construction baseline, now including certified coordinate intervals, builds
  5,000 LPI points in 4.667 ms at 3,400 bytes per construction and 500 TPI
  points in 1.063 ms at 6,984 bytes per construction.
  Five million mixed explicit/LPI/TPI axis comparisons, projected orientations,
  3D orientations, and projected incircle calls take 48.635, 60.043, 134.121,
  and 151.550 ms respectively, each at zero allocation. Five thousand exactly
  cocircular calls originally took 11.891 ms and allocated 4,776 bytes/call in
  fallback. A reusable domain-local packed limb arena now reduces the
  corresponding 1,000-call release benchmarks to 576.096 bytes/pair for the
  edge/edge classifier, 96.096 bytes/call for `orient2d`, 192.096 for
  `orient3d`, and 0.096 for homogeneous incircle. The remaining 96/192-byte
  floors come from boxed binary64 bit decoding, not per-predicate limb graphs.
  Exact ray-edge and normal-direction calls allocate 0.096 bytes/call versus
  3,248.096 in the retained immutable oracle; radial-dot allocates 0.096 versus
  2,808.096. Arena medians are 2.256, 2.088, and 2.887 ms per 1,000 calls,
  compared with 1.510, 1.513, and 2.172 ms for the allocating reference paths.
  The positive-infinitesimal `(1, epsilon, epsilon^2)` ray-edge and
  normal-direction signs take 1.696 and 1.652 ms per 1,000 exact arena calls
  at 0.096 bytes/call, versus 1.188 and 1.177 ms and 1,616.096 bytes/call for
  their immutable differential oracles. These symbolic signs run only after
  the six cheap exact axis attempts cannot find a non-boundary ray.
  The arena therefore trades roughly 1.3-1.5x arithmetic latency on these
  deliberately exact cases for eliminating 2.8-3.2 KB of heap traffic and
  promotion per call; it is not described as a raw latency win. Retained LPI
  and TPI construction allocations remain an explicit baseline and need a
  job-local packed ancestry representation before dense-degeneracy performance
  can be called production-ready.
  Historical fast-path medians above used three repeats; the arena/reference
  comparison uses five repeats on OCaml 5.3.0, Dune 3.24.0 release profile,
  Linux 6.8 aarch64, four logical cores. Reproduce the current suite with
  `RAYS_PREDICATE_BENCH_COUNT=1000000
  RAYS_PREDICATE_BENCH_REPEATS=5 dune exec --profile release
  tools/bench_predicates.exe`.
- `tools/bench_boolean_pipeline.exe` measures the full pipeline by default.
  Pass `-- <stage>` to select a stage fixture; each stage keeps its own CSV
  columns and environment controls.
- The exact Boolean face-constraint planner is measured independently on
  50,000 spatially disjoint transverse triangle pairs (100,000 constructed
  endpoints). The first eager-exact implementation took 518.837 ms and
  allocated 807,449,056 bytes on one domain. Deferred certified LPI recipes,
  scalar error bounds, and choosing the equivalent edge recipe with the most
  constant components originally reduced the one-domain median to 244.311 ms
  and 373,356,008 bytes. After generalizing the plan to typed A×B/A×A/B×B
  ancestry, the explicit known-clean fast path takes 257.304 ms and
  380,756,056 bytes, still 2.02x faster and 52.8% lower-allocation than the
  eager implementation. It skips both self BVH traversals and borrows the A×B
  candidate arrays directly. The result has identical
  100,000-point/50,000-constraint cardinality and typed-plan hash
  `2426940019405690385`. Four domains take 319.066 ms on this deliberately
  allocation-heavy independent-pair fixture, so exact point construction is
  joined onto one stable stream; only the zero-allocation candidate
  classification runs in parallel. This is an honest current baseline, not a
  production-ready allocation floor: a job-local packed expansion/limb arena
  remains required before dense Boolean construction can claim that status.
  `current_domain_allocated_bytes` in the CSV is meaningful for one-domain
  allocation comparison only.

  The explicit dirty-input fixture contains 20,000 isolated crossing pairs in
  operand A and a disjoint operand B. With A×A resolution enabled it takes
  125.560/134.927 ms on one/four domains, allocates 166,542,000 current-domain
  bytes on one domain, and produces 40,000 points, 20,000 constraints, and
  exact hash `1728718391664390161`. No multicore speedup is claimed: stable
  serial implicit-point construction dominates after parallel exact
  classification. Set `RAYS_BOOLEAN_SELF=1` to reproduce this mode.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=50000 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BOOLEAN_GRAIN=1024 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- constraints
  # Repeat with RAYS_BENCH_DOMAINS=4 for exact scheduling regression.
  ```
- `tools/bench_boolean_pipeline.exe -- seam` isolates packed
  curve/coincident-facet materialization from an already prepared exact
  complex. On 10,000 isolated
  transverse pairs (140,000 complex edges, 10,000 one-edge curves), the
  pre-scheduling baseline took 7.611 ms and allocated 14,688,368 current-domain
  bytes. Before post-rounding verification, the final cutoff path took 7.128
  ms and 14,688,344 bytes on one domain. Exact BVH self-intersection and
  incidence verification raises the current complete-product median to 10.975
  ms and 16,767,864 bytes, with unchanged hash `3618854488424454289`. At
  50,000 pairs (700,000 complex edges, 100,000 curve points), current medians
  are 58.467/71.663 ms on one/four domains and hash identically to
  `4207245964395753361`; the one-domain run allocates 82,965,968 bytes.
  Four-domain current-domain
  allocation is not comparable because worker-domain allocation is excluded.
  Stable facet/edge classification becomes parallel only above the measured
  200,000-element cutoff; deterministic chaining, prefix construction, and
  materialization remain sequential because scheduling them independently did
  not beat their compact linear loops. Verification and materialization
  dominate this isolated fixture, so its four-domain total is slower and no
  end-to-end multicore speedup is claimed. The exact hash, curve ordering, kinds,
  topology, and edge ancestry are also compared with a forced cutoff of one in
  tests. The exact segment-contact predicate itself takes 0.323 ms per 1,000
  coplanar crossings and allocates 576.096 bounded scratch bytes per ambiguous
  contact; broad-phase rejected pairs do not enter it. The 10,000-pair left-self fixture additionally exercises exact
  source-native-edge ancestry. Its first implementation rebuilt three explicit
  point objects per incident source triangle and took 159.941 ms while
  allocating 220,846,360 bytes. Direct explicit-edge/implicit-point arena
  predicates reduce that pre-verification path to 135.946 ms and 31,248,568
  bytes (1.18x faster, 85.8% less allocation). With exact post-rounding
  verification enabled, the current full path is 140.926 ms and 33,328,088
  bytes with unchanged 10,000-curve hash `132536840293735441`. These results
  use OCaml 5.3.0, Dune 3.24.0 release profile, Linux 6.8
  aarch64, and five repeats (the recorded 50,000-pair median uses five).

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=50000 RAYS_BOOLEAN_REPEATS=5 \
  RAYS_BOOLEAN_GRAIN=16384 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- seam
  # Repeat with RAYS_BENCH_DOMAINS=4 for exact scheduling regression.
  ```
- `tools/bench_boolean_pipeline.exe -- arrangement` isolates the formerly
  quadratic work hidden by the ordinary one-cut-per-face refinement fixture.
  Its source face
  receives many spatially independent exact LPI segments, so required output
  is linear. The prior implementation linearly deduplicated every point, ran
  every segment pair through exact projected predicates, and then tested every
  point against every segment. On 1,000/2,000 cuts it took 114.890/419.879 ms
  and allocated 24,248,488/96,489,504 bytes. Certified two-axis interval
  sweeps plus stable exact sort/canonicalization reduce those medians to
  3.826/8.037 ms, a 30.0x/52.2x speedup, while allocation falls to
  3,404,656/7,110,056 bytes. The exact hashes remain
  `3894907407311697473` and `2548620122607153265`.

  `RAYS_BOOLEAN_ORACLE=1` runs the retained unculled traversal through the
  new exact canonicalizer. It takes 89.092/355.096 ms on the same fixtures, so
  the sweep itself is a measured 23.3x/44.2x faster than the in-tree oracle.
  Tests compare sweep and oracle point coordinates, IDs, segment arrays, and
  one/four-domain signatures on sparse, point-contact, and dense multi-way
  cases.

  A 10,000-cut scale run takes 45.309 ms, allocates 39,295,112 bytes, emits
  exactly 20,000 points and 10,000 segments, and hashes to
  `3085918425404531185`. Sparse work is O((segments + points) log n) plus
  conservative candidate/output cardinality. Candidate storage is capped at
  `min(1,000,000, max(4,096, 64*segments))` pairs; an interval-dense face now
  switches to a packed stable-index BVH with linear index/scratch storage.
  Exact online AVL interning and integer-pair incidence deduplication preserve
  first-observation IDs, while bounded two-level event identity prevents one
  multi-way crossing from being constructed once per segment pair.

  The previous 500-way coincident-event path took 821.387 ms, allocated
  902,954,024 bytes, and retained 73,822,528 major bytes. The adaptive path now
  takes 24.764 ms, allocates 31,086,544 bytes, and retains 1,698,024 major
  bytes: 33.2x faster, 29.0x less allocation, and 43.5x less major retention.
  It emits exactly 1,001 points/1,000 subsegments with unchanged hash
  `955025830561048083`. At 1,000 coincident cuts it takes 85.633 ms, allocates
  110,559,312 bytes, emits 2,001 points/2,000 subsegments, and hashes to
  `658760047862303383`; four-domain preparation has the same hash. Forced BVH
  and unculled oracle modes match the adaptive topology exactly.

  O(segments² + segments*points) remains the honest output-sensitive worst
  case because one face can contain quadratically many distinct crossings;
  repeated observations of one event no longer manufacture quadratic retained
  topology. Independent faces remain parallelized by batch refinement;
  mutation inside one face stays local and serial. Reproduce with:

  ```sh
  RAYS_BOOLEAN_SEGMENTS=10000 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- arrangement
  # Add RAYS_BOOLEAN_ORACLE=1 for the exact compatibility oracle.
  # Add RAYS_BOOLEAN_STABLE_BVH=1 to force the packed indexed path.
  # Add RAYS_BOOLEAN_FIXTURE=multiway for coincident-event stress.
  ```
- `tools/bench_boolean_pipeline.exe -- cdt` isolates point insertion,
  constraint recovery, and exact Delaunay repair on one face with many
  independent constraints. The
  rebuild-per-query reference took 123.389/532.621/3,535.072 ms for
  100/200/500 constraints and allocated
  73,730,008/288,972,200/1,776,782,696 bytes. Incremental packed edge
  incidence, adjacency walking, endpoint-fan/triangle-chain constraint tracing,
  certified interval rejection, and a bounded dirty-edge heap reduce those
  medians to 2.154/4.408/11.167 ms: 57.3x/120.8x/316.6x faster. Allocation
  falls to 2,374,240/4,770,088/11,843,776 bytes. On the 500-constraint case,
  major allocation drops from 527,635,952 to 832,904 bytes (633x lower).

  Exact output hashes remain `1419697574691670362`,
  `2197167562701697930`, and `1749227091361358650`. A 64-constraint
  regression compares every triangle and recovered constraint between walking
  and exact-scan point location, traced and exhaustive edge recovery, and
  one/four domains. At 1,000/5,000/10,000 constraints the traced path takes
  23.503/121.018/257.105 ms, allocates
  23,748,488/117,449,408/234,784,520 bytes, and emits exactly
  2,003/10,003/20,003 points and 4,001/20,001/40,001 triangles. Its hashes are
  `3785343169251276810`, `2391623243183762698`, and
  `1854962600882321706`. The 10,000-constraint four-domain preparation run has
  the same hash and takes 298.317 ms; single-face CDT mutation intentionally
  remains serial while independent faces run in parallel.

  The retained 500-constraint exhaustive edge oracle takes 152.602 ms and
  allocates 296,529,856 bytes versus 11.167 ms and 11,843,776 bytes for traced
  recovery, with identical hash `1749227091361358650`. Expected traced recovery
  is proportional to endpoint valence plus crossed edges/flips; a broken local
  invariant deliberately falls back to the O(constraints*active edges) exact
  oracle rather than silently losing a constraint.

  ```sh
  RAYS_BOOLEAN_SEGMENTS=500 RAYS_BOOLEAN_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- cdt
  ```
- Batch exact face arrangement/CDT is measured separately after the global
  constraint plan has been built. On 10,000 independent pairs (20,000 affected
  faces), the current packed-reference refinement takes 292.844 ms on one
  domain and 321.363 ms on four domains, with identical face counts and hash
  `1828363657882557313`. The one-domain pass allocates 583,359,184 bytes;
  this aggregate fixture mostly measures independent one-constraint faces and
  therefore complements, rather than replaces, the dense single-face CDT
  benchmark above. These numbers establish correctness/performance baselines,
  not a production-readiness claim.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=10000 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BOOLEAN_GRAIN=64 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- refinement
  # Repeat with RAYS_BENCH_DOMAINS=4.
  ```
- Exact coplanar overlap is measured on 50,000 spatially independent triangle
  pairs whose intersection is a six-edge polygon (300,000 constructed output
  points/boundaries). Adding certified deferred projected line-line recipes
  reduced the one-domain median from 724.180 ms and 1,691,944,744 allocated
  bytes to 467.986 ms and 1,428,284,296 bytes, with the identical hash
  `37609860528830481` (1.55x faster and 15.6% less allocation). Four domains
  currently take 694.691 ms with the same hash: exact homogeneous fallback and
  GC contention dominate this deliberately symmetric fixture, so this stage
  is deterministic and concurrently partitioned but is not claimed as a
  multicore speedup. The packed expansion/limb arena remains the measured
  prerequisite for that claim. As elsewhere, four-domain
  `current_domain_allocated_bytes` excludes worker-domain minor allocation.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=50000 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BOOLEAN_GRAIN=256 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- coplanar
  # Repeat with RAYS_BENCH_DOMAINS=4; do not run the timings concurrently.
  ```
- Complex/radial assembly is measured on 10,000 independent transverse
  triangle pairs (80,000 exact vertices, 70,000 merged facets, 140,000 edges).
  Avoiding per-edge order arrays for one/two-chart edges, caching chart halves,
  using source-face coplanarity, and adding implicit-point identity fast paths
  reduced radial ordering from 264.524 ms and 386,890,640 bytes to 6.586 ms
  and 17,890,184 bytes with unchanged hash `45657678768556593`. Exact angular
  predicates are now paid only by genuine three-or-more-chart bundles.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=10000 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BOOLEAN_GRAIN=64 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- complex
  ```
- The complete private Boolean pipeline is measured on 10,000 pairs of
  spatially disjoint closed tetrahedra (80,000 output points/facets). It runs
  constraint planning, coplanar planning, refinement, exact complex/radial/
  Weiler construction, exact-axis winding classification, and union
  extraction. Before indexing source components, a one-domain scale run took
  2.082877 s, including 1.115026 s and 327,125,240 bytes in cell
  classification. The packed component AABB tree reduces the current
  exact classifier first to 0.131235 s. Replacing three retained explicit-point
  objects per tested triangle with a packed source/query predicate then reduces
  the retained one-domain medians to 1.094471 s end to end and 0.078776 s /
  145,851,352 bytes for cells. The direct path certifies ordinary projected
  edge and plane signs with conservative error bounds and enters one packed
  exact arena when any sign is uncertain. Relative to the pre-index run this
  is 14.15x faster in cells, 1.90x end to end, and 55.4% lower cell allocation.
  The current exhaustive private oracle, which still pays tree construction so
  it can use the identical component product, takes 0.494387 s in cells versus
  the indexed 0.078776 s, a same-build 6.28x query comparison. Four domains
  take 1.141048 s with a 0.097380 s cell phase.
  Every path emits exactly 80,000 points/facets with hash
  `3059953067660499025`; no multicore speedup is claimed for the still mostly
  serial downstream phases. This removes the aligned-disconnected
  O(components x triangles) behavior on the fixture. The conservative worst
  case remains linear in all overlapping component boxes plus their triangles.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=10000 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BOOLEAN_GRAIN=256 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe
  # Repeat with RAYS_BENCH_DOMAINS=4; the exact hash must match.
  # Set RAYS_BOOLEAN_COMPONENT_INDEX=0 for the private exhaustive oracle.
  ```
- The mandatory post-rounding point-collision and triangle-degeneracy gate was
  measured again on the 1,000-pair disjoint fixture. Its packed hash/dominant-
  projection implementation completes the full pipeline in 0.092291 seconds
  with 100,984,152 current-domain allocated bytes, versus the prior 0.097877
  seconds and 100,468,864 bytes. The deterministic hash remains
  `3722707883293083377`; the 515,288-byte increase is the bounded coordinate
  table and exact validation scratch. The geometry-only path still does not
  construct optional source-barycentric ancestry.
  With the explicit self-intersection policy, a fresh 1,000-pair release run
  takes 88.356 ms with resolution off and 96.650 ms with both per-input passes
  on. The constraint phase is 4.593 versus 11.390 ms and allocates 2,817,416
  versus 4,808,552 current-domain bytes; every downstream cardinality and final
  hash remains exactly `3722707883293083377`. Use
  `RAYS_BOOLEAN_SELF=1` with `tools/bench_boolean_pipeline.exe` to measure
  the resolved policy.
- `tools/bench_boolean_pipeline.exe -- materialization` isolates exact
  seam-facet candidate marking, strict independent contraction planning, and
  the complete rounded
  surface publication guard on replicated overlapping-box arrangements. On 20
  pairs (476 points, 872 facets), fresh three-run release medians are 0.042 ms
  / 19,224 current-domain bytes for 784 candidates and 0.487 ms / 196,960 bytes
  for strict planning on one domain. Four domains take 0.258 ms and 0.515 ms;
  these small passes are deliberately below the useful parallel scale. The
  verified no-collapse batch, dominated by exact surface self-contact and
  coplanar overlay, takes 61.078 ms / 21,897,392 current-domain bytes on one
  domain and 37.669 ms / 10,318,008 on four domains. The current-domain number
  excludes worker minor heaps. Both emit hash `1391454515331433611`.

  The one-pair adversarial one-ULP misalignment fixture enables an actual
  collapse at threshold `0.60000000000000009`: three independent edges are
  removed and the verified output has 17 points/30 facets. Five-run release
  medians are 1.059 ms / 435,832 bytes on one domain and 1.105 ms / 441,080
  bytes on four, with exact hash `3531070770066205063`. Candidate marking is
  O(complex edge incidence + output edge incidence), planning is O(edges log
  edges + local incidence), and verification is O(facets log facets + exact
  contact output). The exact broad-phase worst case remains quadratic when
  every triangle AABB overlaps.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=20 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- materialization
  RAYS_BOOLEAN_PAIR_COUNT=1 RAYS_BOOLEAN_REPEATS=5 \
  RAYS_BOOLEAN_COLLAPSE=1 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- materialization
  # Repeat both with RAYS_BENCH_DOMAINS=4; hashes must match.
  ```
- Full Boolean payload transfer is isolated by
  `tools/bench_boolean_pipeline.exe -- payload`. The 10,000-disjoint-pair
  fixture has
  80,000 output facets and copies primitive Float, Float3, two-value Int-array,
  and group planes; point Float, two-value Float-array, and group planes; and
  vertex normalized Float3, two-value Int-array, and group planes. The current
  fixture also transfers one native edge group through exact directed-edge
  ancestry from all coincident members. Fresh three-run release medians are
  78.800 ms on one domain (6.303 ms primitive, 74.093 ms point/vertex/edge)
  and 63.093 ms on four domains (6.946 ms primitive, 56.147 ms
  point/vertex/edge), a measured 1.25x end-to-end speedup. Both runs produce
  exact hash `3028646201992245325`. Reported current-domain allocation is
  143,600,760/90,407,360 bytes and major allocation is
  32,764,408/32,942,064 bytes; the four-domain current-domain number excludes
  worker minor heaps and is not a total-allocation comparison. Fixed-width and
  CSR interpolation/count/fill and unique-edge membership passes write stable
  disjoint ranges. Point consolidation and ordered-group sorting remain
  deterministic serial work,
  so the measured result, not theoretical pool width, is the concurrency
  claim. For [a] attributes and [g] groups the dense path is O((a+g) * output
  corners + copied CSR values + ordered members log ordered members) time and
  output-sized auxiliary/storage; it does not scan unrelated source topology
  per output corner.

  The benchmark now reports setup separately. The same runs spent
  1.972637/1.994169 seconds preparing the exact solid and the former
  explicit-point path spent 0.871600/0.943200 seconds extracting full ancestry
  on one/four domains. Direct packed source-triangle/implicit-point
  barycentrics and source-edge containment reduce a fresh one-domain ancestry
  extraction to 0.538491 seconds with unchanged payload hash. That pass
  allocates 134,020,112 current-domain bytes and retains 25,139,096 major
  bytes while producing 80,000 facets; with native edge groups disabled it is
  0.536912 seconds, 123,539,576 allocated bytes, and 22,978,656 major bytes.
  The focused exact-arena barycentric takes 0.237 ms per 100 calls and 400.960
  bytes/call versus 0.601 ms and 11,472.960 bytes/call for the retained
  explicit-object oracle: 2.54x faster and 96.5% less allocation.
  Directed-edge ancestry is bounded by three source tokens per coincident
  member and uses explicit-ID fast paths before exact implicit-point line
  tests. Its current selected-facet/member scan is deterministic serial work;
  no ancestry-construction multicore speedup is claimed, and a stable
  count/prefix/fill parallel refactor remains a measured optimization target.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=10000 RAYS_BOOLEAN_REPEATS=3 \
  RAYS_BOOLEAN_GRAIN=256 RAYS_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe -- payload
  # Repeat with RAYS_BENCH_DOMAINS=4; the exact hash must match. Set
  # RAYS_BOOLEAN_EDGE_GROUPS=0 to isolate the no-native-edge schema.
  ```
- The promoted `Rdk.Boolean.run` product boundary is measured end to end by
  `tools/bench_boolean_pipeline.exe -- product`: exact arrangement,
  difference extraction, complete payload/schema transfer, seam construction,
  zero-threshold rounded
  verification, and output publication. On ten independent overlapping box
  pairs (176 points, 312 triangles), nine-run release medians on Linux 6.8
  aarch64, four Apple virtual cores, OCaml 5.3.0 are 42.185 ms on one domain
  and 33.656 ms on four domains (1.25x), including the exact-to-binary64
  point-coalescing pass. Current-domain allocation is
  14,645,480/8,362,952 bytes, promoted allocation is 618,256/634,808 bytes,
  and major allocation is 1,415,880/1,417,208 bytes. Worker minor heaps are
  excluded from the four-domain current-domain figure. Both executions emit
  exact hash `2257223296668761468`; no broader scaling claim is inferred from
  this deliberately small publication-path fixture.

  ```sh
  RAYS_BOOLEAN_PAIR_COUNT=10 RAYS_BOOLEAN_REPEATS=9 \
  RAYS_BOOLEAN_GRAIN=32 RAYS_BENCH_DOMAINS=1 \
    opam exec --switch=. -- dune exec --profile release \
      tools/bench_boolean_pipeline.exe -- product
  # Repeat with RAYS_BENCH_DOMAINS=4; hashes must match.
  ```
- _Continues "The Boolean stability runner's standard-density campaign additionally covers…" in performance.md:_
  Four-domain medians for the repaired bank range from 0.342 s
  (reverse subtraction) to 2.357 s (9,776-primitive Shatter); the measured complete
  24-row campaign peaks at 119,000 KiB RSS. The repaired Shatter formerly
  required 27.137 s and 5.94 GB of current-domain allocation at one domain
  during singleton speculative search; disjoint one-ring batching reduces it
  to 4.567 s and 1.11 GB at one domain, or 2.357 s and 455 MB current-domain
  allocation at four domains. These are pathological repair-path figures.
- _Continues "The fixed-target Fuse planner builds one packed target-cell…" in performance.md:_
  On the
  200,901-query/200,901-target closest-snap fixture (401,802 total input
  points), three fresh-process medians of three Dune dev-profile cooks take
  130.389/54.000 ms on one/four domains (2.41x), allocate
  71.754/50.533 MB, and produce exact hash `684896498266188908` with output
  cardinality `1800901`. One-repeat processes peak at 200,576/200,960 KiB RSS,
  including fixture construction, Dune, hashing, and the OCaml heap. The
  pre-change 321,602-point compatibility baseline was 44.771/40.915 ms and
  65.532/65.613 MB; after adding the dispatch without changing that kernel it
  is 45.029/40.902 ms and 65.532/65.618 MB with the same exact hash
  `1998394940270991636`. Measurements use OCaml 5.3.0, Dune 3.24.0, grain
  16,384, Linux 6.8 aarch64, and four physical cores. Reproduce with
  `RAYS_RDK_OPS_FILTER=fuse_target_closest_snap
  RAYS_RDK_OPS_REPEATS=3 RAYS_BENCH_DOMAINS=1 dune exec
  tools/bench_rdk_ops.exe`, then repeat with four domains.
- _Continues "Same-input Modify Target converts its packed target links…" in performance.md:_
  On 401,802 total points, closest-link fusion with a weighted-average
  point policy takes 173.219/86.186 ms on one/four domains (2.01x), allocates
  144.791/123.066 MB, and produces exact hash `4054786758075175250` with
  cardinality `3400901`. The post-fuse cleanup fixture collapses a 200,901-point
  grid, removes repeated corners and degenerate faces, and compacts unused
  points in 75.976/67.966 ms with 110.756/110.818 MB allocated and exact hash
  `2326966657950004879`. Three-repeat process peak RSS was
  278,144/203,520 KiB and 195,328/200,320 KiB respectively, including fixture
  construction, Dune, hashing, and the OCaml heap. Measurements use OCaml
  5.3.0, Dune 3.24.0's dev profile, grain 16,384, Linux 6.8 aarch64, and four
  physical cores.
  Reproduce using `RAYS_RDK_OPS_FILTER=fuse_modify_target_weighted_pair` or
  `RAYS_RDK_OPS_FILTER=fuse_cleanup_grid_pairs`, three repeats, and one then
  four `RAYS_BENCH_DOMAINS`.
- _Continues "Fuse point-attribute and group rules retain stable cluster…" in performance.md:_
  On a
  401,802-point fixed-target fixture that copies float payload, converts scalar
  integers to concatenated CSR rows, and maps a target-only group, one/four
  domains take 131.672/56.996 ms (2.31x), allocate 81.407/58.096 MB, and
  produce exact hash `4523923909597708345` with cardinality `1800901`.
  Three-repeat process peak RSS is 195,712/203,648 KiB. On the same total point
  count, a Modify Target fixture combining weighted float reduction, integer
  mode, weight-ordered text concatenation, and strict-majority group reduction
  takes 207.744/104.389 ms (1.99x), allocates 212.329/164.361 MB, and produces
  exact hash `2011718227915068739` with cardinality `3400901`; peak RSS is
  203,648/200,576 KiB. The promoted allocation in that fixture includes the
  retained concatenated text output, rather than per-candidate list or option
  garbage. Measurements use the Dune dev profile, OCaml 5.3.0, Dune 3.24.0,
  grain 16,384, Linux 6.8 aarch64, and four physical cores. Reproduce with
  `RAYS_RDK_OPS_FILTER=fuse_target_attribute_rules` or
  `RAYS_RDK_OPS_FILTER=fuse_modify_target_attribute_rules`, three repeats,
  and one then four `RAYS_BENCH_DOMAINS`.
- _Continues "Ray multi-sampling traverses the shared packed collision BVH…" in performance.md:_
  On 200,901 source
  points, 400,000 collision triangles, and eight samples, average position and
  geometric-normal output takes 2600.973/837.613 ms on one/four domains
  (3.11x), allocates 381.365/169.824 MB, and produces exact hash
  `3683760327621035444`. Exact averaged provenance plus `Cd` import takes
  5055.799/1630.292 ms (3.10x), allocates 725.351/327.431 MB, and produces
  exact hash `4210588290262089581`. Peak RSS is 147,116/153,796 KiB and
  225,660/232,948 KiB respectively. The sampled upper-median path takes
  2679.258/874.727 ms, allocates
  552.591/215.368 MB, and produces exact hash `1460998520121358970`; its
  O(samples log samples) fixed-worker heap-sort scratch is the deliberate
  bounded cost. Replacing the prior per-ray recursive
  traversal closure with fixed worker stacks lowered established single-ray
  one/four-domain allocation from 207.768/116.170 MB to 141.879/102.575 MB;
  its exact hash remains `2862479342738221337`. Measurements use OCaml 5.3.0,
  Dune 3.24.0's release profile, grain 16,384, Linux 6.8 aarch64, and four
  physical cores. Reproduce with
  `RAYS_RDK_OPS_FILTER=ray_multisample_position` or
  `RAYS_RDK_OPS_FILTER=ray_multisample_provenance`, three repeats, and one
  then four `RAYS_BENCH_DOMAINS`.
- Point/primitive Attribute Transfer builds one deterministic
  median-partitioned packed spatial index, performs allocation-free bulk
  k-nearest queries, and reuses the source IDs/distances for every payload
  plane. Globally flat dimensions are omitted from its split cycle and large
  disjoint subtrees build in parallel. On the planar 40,401-point k=4 fixture,
  this lowered the prior 98.0/51.1 ms one/four-domain result; after sharing
  one in-place normalized coefficient table across payload components, the
  current result is 38.721/18.063 ms with 4.209/4.217 MB allocated and exact
  hash `2242929486872171700`. The exact-formula Hart kernel takes
  37.953/19.466 ms with the same allocation floor. The 80,000-primitive
  barycenter path takes 132.270/55.041 ms and 10.885 MB; before active-axis
  splitting the same exact hash took 395.116/177.189 ms. Numeric payload planes
  use stable weighted neighbors; integer/text payloads use the closest stable
  ID. Detail payloads are structurally shared without copying.
- _Continues "Attribute Combine fuses the complete ordered layer stack…" in performance.md:_
  Its million-point/four-layer
  float4 fixture takes 171.595/62.474 ms on one/four domains and allocates
  32.008 MB, versus 235.223/111.971 ms and 128.022 MB for four sequential
  one-layer commits with the identical hash. Integer/text cross-input matching
  uses one packed open-address table and mapping rather than boxed hash
  entries; the million-point integer-key fixture takes 59.079/36.377 ms and
  allocates 32.784 MB with exact domain-count output.
- _Continues "Attribute Interpolate resolves mixed-owner fields into specialized packed…" in performance.md:_
  Its current million-destination seven-field fixture takes 186.744/73.114 ms
  on one/four domains with 120.015/120.028 MB allocated, versus
  320.864/132.646 ms for seven separate cooks with the identical hash
  `4556032010648822215`. Opaque integer/float CSR array-row transfer was
  previously rejected; the implemented direct primitive-coordinate path
  takes 60.408/29.095 ms and the explicit point-weight path takes
  72.006/38.918 ms. Both copy into cardinality-exact packed output storage,
  allocate 55.759/55.801 MB or 55.760/55.798 MB, promote no
  words, and produce exact one/four-domain hashes `3814298602230283686` and
  `512519829743690904`. An isolated one-repeat process peaked at
  614,936/614,844 KiB RSS; this includes the common million-destination source,
  targets, computed-weight fixture, correctness prechecks, Dune, and OCaml
  heap, not only the measured array output. Reproduce with
  `RAYS_RDK_OPS_FILTER=attribute_interpolate
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 dune exec --profile
  release tools/bench_rdk_ops.exe`, then repeat with four domains.
- _Continues "Closest-surface Attribute Transfer builds one deterministic packed polygon…" in performance.md:_
  Exact node cardinality,
  reusable triangulation/query scratch, and non-escaping sequential recursion
  reduce the 80,000-triangle index from the first correct 295.7 ms/620.4 MB to
  39.081 ms/21.184 MB on one domain; parallel subtree construction takes
  18.383 ms with the identical hash. Complete mixed-owner transfer to 40,401
  points fell from 348.1 ms/733.3 MB to 74.416 ms/31.209 MB and takes 35.478
  ms on four domains. The 240,000-vertex destination path takes 210.519/77.521
  ms, while a vertex-only payload takes 195.056/71.208 ms. An isolated
  three-repeat four-domain vertex-transfer process peaks at 57,656 KiB RSS.
  Exact geometry and rendered PNG regressions compare one and four domains.
- _Continues "`Attribute_pattern` compiles name selection once into literal, wildcard…" in performance.md:_
  The 1,024-name fixture performs 1,024,000 full-name matches
  in 80.922 ms, allocates 200 bytes in total, promotes no words, and produces
  cardinality 896,000 with hash `1915910070998661393`. Reproduce with
  `RAYS_RDK_OPS_FILTER=attribute_pattern RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec tools/bench_rdk_ops.exe`.
- _Continues "Batch Attribute Delete/Rename compiles patterns before mutation, scans…" in performance.md:_
  On 4,096 attributes with 2,048 matches, seven
  release-profile medians on OCaml 5.3.0/Linux 6.8 aarch64 were 1.354 ms and
  2.627 MB for batch rename versus 174.589 ms and 337.068 MB for repeated exact
  renames (128.9x faster, 128.3x less allocation), and 0.314 ms/0.188 MB for
  batch delete versus 67.351 ms/201.802 MB (214.5x faster, 1,073x less
  allocation). Batch rename preserves source attribute order, unlike the old
  remove-and-append loop, while producing the same owner/name/payload set.
  Four-domain medians were 1.686/0.329 ms with identical semantic hashes
  `955200990875090658`/`2626768148336597705`, so
  these metadata-scale kernels intentionally stay sequential; domain dispatch
  would regress latency. The isolated seven-repeat four-domain process peaked
  at 51,772 KiB RSS including Dune, the runtime, fixtures, and output hashing.
  Reproduce with
  `RAYS_RDK_OPS_FILTER=attribute_lifecycle RAYS_RDK_ATTRIBUTES=4096
  RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then use the `attribute_lifecycle_batch` filter and
  four domains.
- _Continues "Attribute Swap extends the same atomic metadata store…" in performance.md:_
  On 10,000 attributes, 5,000 wildcard Copy
  matches complete in 5.017/5.343 ms on one/four domains, allocate
  11.324/11.324 MB, and produce cardinality 15,000 with exact semantic hash
  `2610032694933915216`. Repeated immutable `Geometry.with_attribute` rebuilds
  take 397.875/563.846 ms and allocate 501.940 MB for the identical set: the
  batch path is 79.3x faster and allocates 97.7% less on one domain. Promoted
  allocation is 2.374 MB and major allocation 2.120 MB on the one-domain batch
  run. Metadata work remains sequential because four-domain dispatch cannot
  expose independent payload ranges and measured slightly slower. Reproduce
  with `RAYS_RDK_OPS_FILTER=attribute_lifecycle
  RAYS_RDK_ATTRIBUTES=10000 RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains.
- _Continues "Connected Poly Extrude precomputes stable region/point associations and…" in performance.md:_
  A first correct general path unconditionally built the full
  target reverse-topology index: on the 40,401-point/80,000-triangle grid it
  took 53.559/53.230 ms and allocated 108.780/107.214 MB on one/four domains.
  Skipping target edge indexing when no edge output is requested reduces the
  same one-division cook to 19.023/16.843 ms and 35.955/34.389 MB, with exact
  hash `2364399450292568690`. Four straight divisions take 20.317/17.656 ms,
  allocate 40.035/38.471 MB, and retain exact hash `4546573959557103075`.
  When native boundary groups are requested, a lightweight stable endpoint
  table replaces the unrelated target point/corner CSR planes; this reduced
  that four-division path from 58.602/58.030 ms and 118.030/116.465 MB to
  38.949/34.273 ms and 60.314/58.750 MB, exact hash
  `4170512633490323959`. The isolated three-repeat four-domain boundary process
  peaks at 87,464 KiB RSS. The serial stable component/association phase limits
  domain scaling on this small fixture; parallel output remains byte-identical.
  Reproduce with `RAYS_RDK_OPS_FILTER=poly_extrude
  RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains.
- _Continues "Poly Fill plans complete one-sided polygon boundary components…" in performance.md:_
  The measured fixture contains 100,000 disconnected
  open boxes: 800,000 input points, 2,000,000 corners, 500,000 source
  primitives, and 400,000 boundary edges, with point `Cd`, vertex `uv`, a
  primitive piece field, ordinary groups, and a native rim group. Five-run
  release medians are:

  | Fill mode | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
  |---|---:|---:|---:|---:|---:|
  | Single Polygon, shared | 215.381 ms | 194.253 ms | 1.11x | 247.908 / 190.236 MB | `2051343833192007422` |
  | concave-safe Triangles, shared | 244.550 ms | 213.055 ms | 1.15x | 284.145 / 219.197 MB | `1491809127108389124` |
  | Triangle Fan, unique | 359.863 ms | 290.621 ms | 1.24x | 487.747 / 346.866 MB | `1323544786701702380` |

  The first correct development-profile path built a complete target reverse
  topology merely to resize source edge groups and retained dense per-output
  center-marker planes. It measured 481.839/447.497 ms and
  697.418/638.293 MB for Single Polygon, 513.627/469.648 ms and
  760.856/693.056 MB for Triangles, and 694.889/632.287 ms and
  1,106.057/966.466 MB for the unique fan. Prefix-stable source edge ordinals,
  exact analytic new-edge counts, source-table checks only for shared ear
  diagonals, and center identity derived from point references reduced the
  equivalent development-profile paths to 219.345/200.869 ms and
  251.108/194.322 MB, 241.617/210.695 ms and 287.346/221.659 MB, and
  356.993/290.185 ms and 490.947/348.595 MB without changing any hash.
  Retiring the last unused loop-edge scratch plane produced the release
  allocations above. Output payload and linear boundary plans dominate remaining allocation;
  stable component union and numbering limit scaling, while loop analysis,
  triangulation, topology/payload fills, and interpolation use disjoint domain
  ranges. The isolated five-repeat four-domain process peaked at 585,196 KiB
  RSS. Reproduce with `RAYS_RDK_OPS_FILTER=poly_fill
  RAYS_RDK_POLY_FILL_BOXES=100000 RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains.
- _Continues "Clean's degeneracy classifier uses a packed triangle fast…" in performance.md:_
  On the
  610,000-point/200,000-triangle fixture with 25,000 zero-area faces, seven
  release medians retain exact hash `237308101545920430`: the former scalar
  path took 34.945/37.424 ms and allocated 28.985/29.000 MB on one/four
  domains; the robust classifier takes 36.555/35.300 ms and allocates
  24.388/24.402 MB. The slight one-domain cost buys correct edge-length-squared
  tolerance and extreme-coordinate behavior; four-domain classification is
  faster and allocation falls 15.8%. Cleanup plus unused-point compaction takes
  77.192/68.279 ms with exact hash `1515528928332167256`.

  The overlap benchmark contains 400,000 triangles in 200,000 rotated duplicate
  classes over 610,000 points. Triangle-specialized canonical signatures,
  stable open-address insertion, and ancestry-preserving deletion take
  46.835/44.145 ms, allocate 49.204/49.222 MB with zero promotion, and produce
  exact hash `4337562777770830957`. The deterministic representative table and
  deletion plan limit scaling; signature preparation and payload fills remain
  parallel. The isolated three-repeat four-domain process peaks at 108,672 KiB
  RSS including source and result. Reproduce both paths with
  `RAYS_RDK_OPS_FILTER=clean RAYS_RDK_OPS_REPEATS=7
  RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe`,
  then repeat with four domains or filter `clean_overlaps`.
- _Continues "Enumerate computes selected counts independently per stable chunk…" in performance.md:_
  On
  1,002,001 points, full enumeration takes 5.45 ms/8.02 MB on one domain and
  1.85 ms/8.04 MB on four; an alternating packed group takes 6.40 ms and 2.56
  ms respectively, with exact hashes across domain counts. Piece-aware
  enumeration assigns stable first-occurrence piece IDs and local ranks in one
  sequential identity pass, then fills owner-sized output ranges in parallel.
  On 1,002,001 points split across 4,093 integer pieces, local element numbering
  takes 18.703/16.500 ms and piece-ID numbering 14.856/12.633 ms on one/four
  domains. Both allocate 16.428/16.445 MB, promote zero bytes, and produce exact
  hashes `181743986586326463` and `1507297164366801964`. A straightforward
  polymorphic-table local-rank baseline takes 47.924/47.047 ms and allocates
  24.147 MB for the identical first hash, so the specialized integer table is
  2.56x faster and allocates 32.0% less on one domain. Text-key local ranking
  takes 62.330/59.099 ms and 32.310/32.327 MB with the same numeric output hash.
  Removing the redundant global-selection count pass improved the correct
  integer path from 20.790/17.535 ms. An isolated four-domain integer run peaks
  at 69,760 KiB RSS, including Dune, source, output, and hashing. Reproduce with
  `RAYS_RDK_OPS_FILTER=enumerate_piece RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains.
- Point Velocity was measured on 1,002,001 points under OCaml 5.3.0 release on
  a four-core aarch64 Linux host. Removing tuple-return sampling and boxed
  vector helpers from the measured loop reduced the packed deformation path
  from 360.724 MB allocated to its 24.052 MB float3 output floor. Five-run
  medians are 17.301 ms on one domain and 5.548 ms on four domains (3.12x
  domain speedup), with zero promoted bytes and exact hash
  `3321439189469037077` in both modes. A straightforward scalar `Array.init`
  reference takes 14.290/18.888 ms and allocates 72.145 MB; the packed path is
  therefore modestly slower on one core but 3.40x faster on four while
  allocating 66.7% less. Integer-ID matching, including a million-entry packed
  open-address table and current-point map, takes 105.367/69.389 ms and
  allocates 67.720/67.747 MB with exact hash `4450966148999797942`.
  Parallelizing its immutable lookup phase reduced the four-domain median from
  99.572 ms. Rest Store structurally shares the position plane and takes
  0.011/0.013 ms with about 3 KB metadata allocation. One isolated full
  four-domain repeat peaked at 135,552 KiB RSS, including both source snapshots,
  reference/ID cases, result hashing, Dune, and the OCaml heap. Reproduce with
  `RAYS_RDK_OPS_FILTER=motion RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, repeat with four domains, and use `/usr/bin/time -v`
  with one repeat for peak RSS.
- Dissolve was measured on a 1,000 by 1,000 quad grid (1,002,001 points,
  4,000,000 corners, and 1,000,000 primitives) under OCaml 5.3.0 release on the
  same four-core aarch64 Linux host. Dissolving every manifold edge to the
  4,000-corner boundary polygon takes 90.568/90.464 ms on one/four domains,
  allocates 64.806 MB, promotes zero bytes, and produces exact hash
  `3098566088433871729`. Removing the now-inline boundary points to a four-corner
  rectangle takes 105.426/102.690 ms, allocates 74.540/74.542 MB, promotes zero
  bytes, and produces exact hash `2525572738818699091`. Stable union/find and
  boundary tracing intentionally remain sequential; parallelism applies to
  payload/group remapping and normal fills, so this topology-only fixture is
  latency-neutral across domain counts rather than advertised as a parallel
  speedup. Density-aware output buffers reduced measured allocation from
  152.642 to 64.806 MB for boundary output and from 162.377 to 74.540 MB for
  inline cleanup; the corresponding one-repeat wall measurements improved from
  118.855 to 97.706 ms and 118.334 to 95.655 ms. The optimized isolated run
  peaked at 597,276 KiB RSS including Dune, the million-quad source, reverse
  topology, both output cases, and hashing. Reproduce with
  `RAYS_RDK_OPS_FILTER=dissolve RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, repeat with four domains, and use `/usr/bin/time -v`
  with one repeat for peak RSS.
- _Continues "Sort builds one stable new-to-old permutation and materializes…" in performance.md:_
  A 1,002,001-point/6,000,000-corner
  X sort takes 193.8 ms on one domain and 171.3 ms on four; an 80,000-primitive
  center-X sort takes 10.9/9.95 ms. Exact hashes cover topology and all payloads.
- _Continues "Duplicate computes output cardinality before allocation, precomputes stable…" in performance.md:_
  Nine materialized copies of the 40,401-point/
  80,000-triangle attributed grid take 134.93 ms on one domain and 24.85 ms on
  four, allocate 41.26 MB, and preserve hash `2456038152415910946`; the
  unrestricted compatibility fast path retains its pre-extension hash and
  allocation floor. Restricting to alternating primitives, copying only their
  referenced points, and emitting eight bounded copy groups produces
  1,963,601 point/corner/primitive elements in 42.44/29.03 ms, allocates
  51.61/51.66 MB with 51.17 MB major allocation, and preserves hash
  `2341744684409956267`. Hoisting the identity inverse-transpose rows from the
  per-normal loop removed 19.72/8.00 MB of transient allocation from the first
  correct version. The selected path
  stores three target-to-source ancestry planes and avoids a second compact or
  merged output geometry. Both hashes are exact across domain counts.
  Reproduce with `RAYS_RDK_OPS_FILTER=duplicate_grid_8` or
  `RAYS_RDK_OPS_FILTER=duplicate_selected_grid_8`,
  `RAYS_RDK_OPS_REPEATS=9`, and `RAYS_BENCH_DOMAINS={1,4}` under the
  release profile.
- _Continues "UV Project partitions primitives into stable ranges so…" in performance.md:_
  Planar projection and transform allocate only the exact two float output
  planes plus roughly 1–6 KB of control data. On a 40,401-point,
  240,000-corner grid, planar projection takes 2.54 ms/3.842 MB on one domain
  and 1.23 ms on four; UV Transform takes 1.26 ms/3.841 MB and 0.64 ms. The
  seam/pole fixture has 130,562 points, 261,120 triangles, and 783,360 corners:
  spherical projection takes 35.0 ms/12.536 MB on one domain and 11.8 ms on
  four, versus 47.2/17.2 ms and 37.604 MB before removing polymorphic float
  comparisons from its inner loop. All modes produce the identical complete
  geometry hash across domain counts. The five-repeat process peaked at
  48.4 MB RSS. On the same 40,401-point/80,000-triangle grid, cold reverse-index
  construction takes 10.8 ms and allocates 36.25 MB (30.47 MB major). With that
  index shared, boundary Edge Group takes 1.40 ms on one domain and 0.56 ms on
  four; the face-angle path now takes 2.98/1.51 ms. Auto Seam takes 9.92/5.85 ms
  and island Unitize 10.44/5.98 ms, down from uncached 21.3/16.8 ms and
  22.2/17.8 ms respectively. Complete output hashes, including native edge
  groups, match across domain counts. Exact-copy edge propagation validates
  copy-major topology in O(vertices + primitives), then writes
  O(selected edges * copies) packed membership with only the final bitset as
  auxiliary storage; it does not build target adjacency. On four copies of the
  same 40,401-point/120,400-edge grid, plain Duplicate takes 61.0 ms/18.34 MB
  on one domain and 16.6 ms/18.34 MB on four; retaining the fully selected
  native edge group takes 65.4 ms/18.40 MB and 20.7 ms/18.40 MB respectively,
  with exact hashes. The previous generic target-index remap took 164.1 ms and
  allocated 183.61 MB on one domain. Reproduce with
  `RAYS_RDK_OPS_FILTER=edge_group_ RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec tools/bench_rdk_ops.exe` for cold/warm edge
  paths, and with
  `RAYS_RDK_OPS_FILTER=uv_ RAYS_RDK_OPS_COLUMNS=200
  RAYS_RDK_OPS_ROWS=200 RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec tools/bench_rdk_ops.exe` and repeat with
  four domains. Measurements used the Dune dev profile, OCaml 5.3.0,
  Linux/aarch64, and four single-thread cores.

  UV Flatten builds corner-chart union-find planes, two boundary neighbors per
  chart vertex, and exactly six directed mean-value entries per triangle.
  Matrix-free diagonally preconditioned conjugate gradient uses stable
  range-local dot products and disjoint sparse matrix-vector output; the
  result is byte-identical across domain counts. Unsupported topology,
  non-convergence, collapsed UV triangles, and flips fail before publishing an
  attribute. The discarded fixed Jacobi baseline took 1.20/0.60 seconds on
  one/four domains at 500 passes and still left the large-grid center
  collapsed; it was not an acceptable fidelity baseline. On the
  40,401-point/80,000-triangle grid, 400 allowed PCG iterations
  at relative residual `1e-7` take 802.7 ms/66.30 MB on one domain and
  402.5 ms/69.98 MB on four. Relaxing the already converged result takes
  25.4/24.6 ms and 65.62/65.65 MB; its reverse-topology/chart assembly
  dominates because no solver iteration is needed. The three-repeat
  four-domain benchmark process peaks at 236.8 MiB RSS. Reproduce with
  `RAYS_RDK_OPS_FILTER=uv_flatten RAYS_RDK_UV_ITERATIONS=400
  RAYS_RDK_OPS_REPEATS=3 RAYS_BENCH_DOMAINS=4
  dune exec tools/bench_rdk_ops.exe`, and replace the filter with `uv_relax`
  for the boundary-preserving path.
- _Continues "Group Promote and fixed-step Group Expand classify disjoint…" in performance.md:_
  The measured 500x500
  triangle grid has 251,001 points, 500,000 primitives, 1,500,000 corners, and
  751,000 unique edges. With a warmed index, grain 16,384, five release-profile
  medians, OCaml 5.3.0/Dune 3.24.0, and the four-core Linux 6.8 aarch64 runner:

  | Group operation | 1 domain | 4 domains | Allocated (1d) | Exact hash |
  |---|---:|---:|---:|---:|
  | point -> primitive, shared edge | 9.060 ms | 3.014 ms | 63,688 B | 2814529521400583635 |
  | point -> primitive integer mask | 7.353 ms | 2.923 ms | 4,001,192 B | 671447967958789223 |
  | point -> edge, both endpoints | 4.739 ms | 1.491 ms | 95,040 B | 1352003519121456719 |
  | point expand, 16 steps | 2.986 ms | 2.379 ms | 541,768 B | 711931004299314690 |
  | point expand + step attribute | 3.116 ms | 2.714 ms | 2,550,096 B | 547810039333989979 |
  | primitive edge-expand, 8 steps | 102.496 ms | 35.228 ms | 565,232 B | 1864981422492917751 |
  | point flood to component | 20.331 ms | 19.879 ms | 2,040,712 B | 595882777167690784 |
  | point flood + distance attribute | 24.047 ms | 23.227 ms | 4,049,040 B | 3816052435515316005 |

  The first correct generic incidence implementation allocated a callback
  closure per destination/neighbor visit. Point-to-primitive promotion took
  15.727 ms and 52.064 MB; direct packed scans reduce it to 9.060 ms and the
  62.5 KB output bitset plus control data. The original sixteen-step point
  dilation fell from 138.716 ms/373.762 MB to 96.981 ms/537.7 KB. Replacing
  its repeated whole-owner scans with the shared bounded multi-source BFS now
  reduces it again to 2.986 ms/541.8 KB while preserving exact membership.
  The step attribute follows the same queue distances. Eight primitive steps fell from
  141.369 ms/381.109 MB to 102.496 ms/565.2 KB. Flood traversal fell from
  24.231 ms/24.129 MB to 20.331 ms/2.041 MB; its required exact-size OCaml
  integer queue dominates and each element enters once. Positive point growth
  retains its initial packed bitset and a visited-cardinality-bounded queue;
  other owners still use one output bitset per executed parallel step. No
  storage is proportional to adjacency visits. Step/distance output adds one
  2,008,008-byte owner plane plus bounded attribute metadata. Flood is
  intentionally serial because a shared frontier would add contention without
  improving this memory-bound fixture. One/four-domain hashes include all
  geometry and group membership and are exact. The isolated processes peaked
  at about 230,400 KiB RSS including source geometry, shared reverse topology,
  benchmark hashing, Dune, and the OCaml heap. Reproduce with
  `RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=500
  RAYS_RDK_OPS_FILTER=group_promote RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains and the
  `group_expand` filter.

  Constrained Group Expand has a separate dense regression because it includes
  boundary compilation and normal-owner mapping. On a 500x300 triangulated
  grid (150,801 points, 300,000 primitives, and 900,000 corners), seven
  release-profile medians with grain 16,384 were:

  | Constrained flood operation | 1 domain | 4 domains | Allocated (1d / 4d) | Exact hash |
  |---|---:|---:|---:|---:|
  | point attribute seam + collision containment + distance | 20.421 ms | 8.977 ms | 2,647,504 / 2,679,264 B | `4272742728285141780` |
  | primitive vertex-normal spread + attribute seam + collision containment + distance | 39.041 ms | 17.178 ms | 12,291,728 / 12,354,520 B | `2768023986287133386` |

  Both domain counts produce byte-identical ordered geometry, groups, and step
  planes. The first correct primitive normal remap allocated three escaping
  float references per target and took 50.615 ms/69,891,712 B on one domain
  (18.860 ms/29,048,888 B reported from the four-domain caller). Using the
  three owned output planes as disjoint accumulation scratch reduced the
  one-domain time by 22.9% and measured allocation by 82.4%, without changing
  fidelity or the result hash. The isolated four-domain primitive run peaked
  at 175,580 KiB RSS including the source, benchmark fixtures, shared topology
  index, Dune, and OCaml heap. These paths are O(elements + incidence +
  selected attribute payload) for constraint compilation and flood traversal;
  scratch is three owner-sized float planes, packed seam/selection bits, and a
  stable owner-sized queue. Reproduce with
  `RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300
  RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1
  RAYS_RDK_OPS_FILTER=group_expand opam exec --switch=. -- dune exec
  --profile release tools/bench_rdk_ops.exe`, then repeat with four domains.
- _Continues "Ordered wildcard Group Promotions preserve rule dependencies serially…" in performance.md:_
  On a
  1,002,001-point/two-million-triangle grid, one rule promoting eight named
  point stripes to eight primitive groups took 285.175/88.137 ms on one/four
  domains (3.24x). Exact geometry/group hashes were
  `2788029539558992156` at both domain counts. Total measured allocation was
  2.028/2.220 MB, of which 2,000,128 bytes is the eight required output
  bitsets; neither run promoted OCaml heap data. Isolated processes peaked at
  938,344/938,244 KiB RSS, dominated by the common million-point catalog
  fixture and cached topology. Reproduce with
  `RAYS_RDK_OPS_FILTER=group_promotions_points_to_primitives_wildcard_8
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains.
- _Continues "Group Promote Boundary composes ordinary conversion with the…" in performance.md:_
  Its first correct implementation materialized
  a temporary integer membership attribute, allocating 16.76--17.30 MB on the
  million-point/two-million-triangle fixture. The production kernel instead
  borrows the immutable selection bitset as a virtual boundary plane. Exact
  hashes are unchanged while allocation falls to 0.755--1.278 MB with zero
  promotion.

  | Boundary promotion | 1 domain | 4 domains | Speedup | Allocation (1d / 4d) | Exact hash |
  |---|---:|---:|---:|---:|---:|
  | primitive -> edge, including unshared | 95.100 ms | 29.731 ms | 3.20x | 1.129 / 1.245 MB | `2434982519447085349` |
  | primitive -> point, including unshared | 105.117 ms | 31.578 ms | 3.33x | 0.755 / 0.850 MB | `1040545337573734187` |
  | primitive attribute seams -> edge | 104.580 ms | 33.702 ms | 3.10x | 1.131 / 1.278 MB | `1821779621274452737` |

  Membership, attribute validation, unique-edge classification, owner
  conversion, and packed intersection are disjoint parallel ranges. The
  isolated four-domain edge process peaked at 941,256 KiB, dominated by the
  common catalog fixture and cached topology. Reproduce with
  `RAYS_RDK_OPS_FILTER=group_promote_boundary
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains.

- _Continues "Group from Attribute Boundary uses the shared reverse-topology…" in performance.md:_

  The release fixture is a 500x500 triangulated grid with 251,001 points,
  500,000 primitives, 1,000,000 corners, and a banded primitive integer
  attribute. With a warmed topology index, five-run medians at grain 16,384
  were 10.337/3.588 ms for native-edge output (2.88x) and 16.001/6.163 ms for
  incident-primitive output (2.60x) on one/four domains. The one-domain runs
  allocated 96,992/159,624 bytes, promoted zero bytes, and had exact hashes
  `4248128253666445085`/`1893038184575030239` at both domain counts. Isolated
  one/four-domain processes peaked at 238,848/238,720 KiB RSS including the
  source geometry, cached reverse topology, Dune, and the OCaml heap.

  ```sh
  RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=500 \
  RAYS_RDK_OPS_FILTER=group_attribute_boundary \
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_rdk_ops.exe
  # Repeat with RAYS_BENCH_DOMAINS=4.
  ```
- Named Group Range/Combine/Invert/Copy use the same 500x500 release fixture
  and warmed topology conditions. Range and Copy fills use stable disjoint
  element/byte ranges; metadata-only Rename/Delete remain deliberately serial
  because their work is proportional to group count rather than element count.

  | Named group operation | 1 domain | 4 domains | Allocated (1d) | Exact hash |
  |---|---:|---:|---:|---:|
  | filtered point range | 2.963 ms | 1.272 ms | 35,368 B | 4364013169145046197 |
  | patterned combine + xor | 0.375 ms | 0.220 ms | 101,640 B | 3699162423690998320 |
  | invert two point groups | 0.174 ms | 0.144 ms | 67,936 B | 839334998168523757 |
  | wildcard metadata rename | 0.018 ms | 0.020 ms | 8,616 B | 3483688696083854235 |
  | patterned metadata delete | 0.016 ms | 0.018 ms | 4,776 B | 2177428364249956390 |
  | copy two point groups by index | 3.031 ms | 1.350 ms | 69,552 B | 3619614573018217634 |
  | copy two point groups by integer attribute | 6.574 ms | 4.052 ms | 6,272,376 B | 2087789192805810812 |

  The first correct attribute-copy implementation used generic chained
  hash-table buckets. It took 30.249/19.840 ms and allocated 18.320/14.925 MB
  on one/four domains. A compact open-addressed table first removed bucket
  nodes, then removed its duplicate key plane: slots now contain only a source
  index and compare against the borrowed immutable attribute storage. The final
  path is 78.3% faster and allocates 65.8% less on one domain, while retaining
  first-source duplicate-key behavior and the exact output hash. Its dominant
  temporary storage is one power-of-two source-index table plus one exact
  target-to-source integer map; all copied group bitsets are required outputs.
  The isolated four-domain, five-repeat attribute-copy process peaked at
  234,624 KiB RSS, including the 2.25-million-component source/target grids,
  benchmark hashing, Dune, and the OCaml heap.

  Reproduce the tranche with `RAYS_RDK_OPS_COLUMNS=500
  RAYS_RDK_OPS_ROWS=500 RAYS_RDK_OPS_FILTER=group_
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains. Use the exact
  `group_copy_points_attribute` filter with `/usr/bin/time -v` for isolated
  resident-memory measurement.
- _Continues "Packed procedural instances retain one SOP prototype plus…" in performance.md:_
  On the 100,000-instance traversal fixture,
  materialization took 54.8–56.1 ms, allocated 61.6 MB, and retained 26.4 MB;
  batched traversal took 15.9–16.3 ms, allocated 46.4 MB, and retained no
  traversal payload, with the identical ordered checksum. Reproduce with
  `RAYS_INSTANCE_BENCH_COUNT=100000 dune exec tools/bench_instances.exe`.
  Measurements used the Dune dev profile, OCaml 5.3.0, Linux/aarch64, four
  single-thread cores; this traversal is sequential and does not invoke SDL.
- _Continues "Copy to Points precomputes one packed scale, complete…" in performance.md:_
  The existing
  102,400-target grid fixture already carries point `N`,
  so it is a direct production regression: the previous orientation-ignoring
  cook measured 78.79 ms and allocated 177.65 MB on one domain. Correct
  complete alignment measures 80.39/47.78 ms and 195.79/195.84 MB on one/four domains,
  with exact cardinality `7418952` and hash `493178525791329886`. The modest
  scalar setup cost is amortized by disjoint parallel copy fills; no SDL state
  enters the kernel. A fixed-width row-major affine 3x3/4x4 `transform`
  attribute overrides that basis and scale. Validation is one packed pass;
  linear planes, matrix translation, pivot adjustment, and scale-normalized
  inverse-transpose cofactors use disjoint target ranges. Singular transforms
  remove copied normals atomically rather than publishing invalid directions.
  The 102,400-matrix box fixture measures 86.84/52.86 ms and allocates
  196.71/187.35 MB on one/four domains, with exact cardinality `7418952` and
  hash `2971098336695328274`; the initial correct sequential preparation was
  85.28/55.18 ms, so pooled preparation improves the multi-domain path without
  changing output. Reproduce the standard path with
  `RAYS_RDK_OPS_FILTER=copy_to_points RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS={1,4} dune exec --profile release
  tools/bench_rdk_ops.exe`, replacing the filter with
  `copy_to_points_transform` for the matrix fixture. Source primitive
  restriction reuses the audited stable deletion/compaction planner once per
  cook; target point restriction remaps selected point facts once, then the
  unchanged copy kernel sees only retained targets. Selecting half of the box
  primitives and alternating points from the same 102,400-target grid measures
  28.27/19.97 ms and 68.32/65.21 MB on one/four domains, with exact
  cardinality `1854756` and hash `931776985239124703`. This avoids per-copy
  selection branches and keeps time/output proportional to selected source
  payload times retained targets. Use filter `copy_to_points_restricted` to
  reproduce it. Three last-match-wins Attributes-from-Target rules on the full
  102,400-target fixture (point float multiply, vertex float2 add, and
  primitive float subtract) measure 138.56/100.17 ms and allocate
  373.85/374.17 MB on one/four domains. Both runs produce exact cardinality
  `7418952` and hash `1491781361630052172`. Fixed and ragged planes are filled
  through stable disjoint output ranges without per-element option boxes;
  allocation includes the complete repeated source payload and the final
  transferred planes. Use filter `copy_to_points_target_attributes` to
  reproduce it. Adding point union, vertex intersection, and primitive
  subtraction target-group rules measures 234.98/119.56 ms and allocates
  375.71/376.19 MB, with the same cardinality and exact hash
  `3019261027278696509`; each group is emitted directly as one parallel packed
  unordered bitset. During the `Nothing` extension, loss of automatic helper
  inlining raised the one-domain attribute fixture to 908.01 MB. Explicit
  always-inlining restored 373.85 MB without changing the hash. Use filter
  `copy_to_points_target_groups` for the combined fixture.
  Piece matching assigns dense source keys once, partitions source and target
  payload in shared passes, cooks only target-referenced batches, merges once,
  and applies deterministic packed point/primitive permutations to restore
  target-major order. Primitive-valued pieces compact referenced points;
  point-valued pieces retain matching free points and reject mixed-value
  primitive membership. The four-piece 103,041-target box fixture measures
  171.36/122.77 ms, allocates 362.37/294.97 MB, and produces cardinality
  `2163861` with exact hash `4154600044073525722` on one/four domains. A
  2,048-unique-primitive source with 16,384 targets measures 15.81/14.67 ms,
  allocates 58.08/56.37 MB, and produces cardinality `114688` with exact hash
  `4369109338172539638`. Major allocations are 235.35/235.40 MB and
  16.53/16.40 MB respectively; promoted allocations stay below 0.07 MB for the
  four-piece case and about 7.1/7.0 MB for the many-piece case. These are Dune
  release-profile OCaml 5.3.0 measurements on Linux/aarch64 with four logical
  CPUs, grain 16,384, and five repetitions. Reproduce with
  `RAYS_RDK_OPS_COLUMNS=64 RAYS_RDK_OPS_ROWS=64
  RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_OPS_FILTER=copy_to_points_piece
  RAYS_BENCH_DOMAINS={1,4} dune exec --profile release
  tools/bench_rdk_ops.exe`.
- _Continues "Curve Carve scans source segments once, computes exact…" in performance.md:_
  Its first scale implementation restarted a linear
  arc search at every retained breakpoint: the 200,001-point fixture exposed
  the resulting O(n²) defect at 12.35 seconds. Direct breakpoint mapping cut
  that to 20.0 ms, and installing the provable copy-local target edge bitset
  without reverse adjacency reduced it to 8.14 ms/17.90 MB on one domain and
  7.11 ms/17.91 MB on four. The primitive-group extension retains that
  all-selected fast path and aliases identical point/corner ancestry planes;
  the unchanged hash now measures 7.64 ms/15.58 MB on one domain and
  7.13 ms/15.59 MB on four while adding scale-safe segment and extreme-value
  interpolation. A mixed 200,001-point curve plus 160,000 unselected
  quads (360,802 points total), carrying a full native edge group, measures
  109.99/105.83 ms and 210.72 MB at one/four domains with exact hash
  `2196969805652410317`. Shared unselected topology requires deterministic
  source/target reverse-edge indexing, so that fixture is planning-bound and
  does not benefit from extra domains. Extracting 100,001 free points from the
  200,001-point attributed curve measures 17.53 ms/28.02 MB on one domain and
  7.92 ms/11.64 MB on four. Stable output-index ranges independently perform
  arc lookup, position interpolation, and payload fills; both runs return hash
  `455318711341606176`. Keeping the inside and both outside pieces of the same
  source initially measured 51.19/43.68 ms and 108.25 MB because the general
  mixed-topology path rebuilt target reverse incidence and separate point and
  corner ancestry. Proving that an all-selected cut owns every output point
  enabled arithmetic target-edge numbering and shared ancestry planes, reducing
  it to 19.59/18.13 ms and 57.66/57.67 MB at one/four domains without changing
  hash `3264112192064555593`. The initial correct 1,024-division Cut planner
  rescanned all 200,001 breakpoints per piece and exposed an O(vertices *
  divisions) failure: 2,914.76 ms and 6,582.78 MB allocated on one domain.
  Monotone binary bounds now make planning O(divisions log vertices) and fill
  only the exact retained ranges. The same fixture measures 10.11/9.38 ms,
  allocates 30.44/30.45 MB with 17.03 MB major allocation and negligible
  promotion, and returns exact one/four-domain cardinality `295482` and hash
  `175348517625681373`. The unchanged one-division all-piece hash remains
  `3264112192064555593` and now measures 11.03/10.46 ms with 38.46/38.48 MB
  allocated. Whole-harness peak RSS was 3,619,444/3,619,628 KiB because
  `bench_rdk_ops` eagerly constructs every fixture; it is not per-operation
  live memory. Measurements used the release profile, OCaml 5.3.0, Linux
  6.8.0/aarch64, and four single-thread cores. Reproduce with
  `RAYS_RDK_OPS_FILTER=curve_carve_divided RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS={1,4} dune exec --profile release
  tools/bench_rdk_ops.exe`. Primitive First/Second U attributes are borrowed
  directly rather than expanded into two per-cook arrays. A 1,000-curve,
  201,000-point varying-parameter fixture measures 6.79/6.66 ms and
  14.19 MB at one/four domains with hash `1882572990968176907`; the ordinary
  no-attribute fast path retains hash `3316149789837505788` and its prior
  allocation floor. Vertex-breakpoint mode uses exact integer ancestry maps:
  the dense retained interval measures 7.73/6.40 ms with hash
  `486281693234160821`, while splitting all 200,000 edges into independent
  curves measures 27.36/18.89 ms and 107.88/63.50 MB with hash
  `1090217027228209054`. The output-heavy point, vertex, attribute, and group
  copies run over stable disjoint ranges; interval snapping and exact
  cardinality planning remain deterministic.

  Ends was measured before broadening the compatibility kernel: shared-seam
  unroll of one 1,002,001-corner closed curve took 13.350/12.574 ms and
  allocated 13.029/8.848 MB at one/four domains, with hash
  `1746403283212006364`. The first general polygon implementation was correct
  but regressed that fixture to 20.357/18.354 ms and 60.225/55.786 MB because
  it built general reverse topology for a unique-corner curve. Cardinality
  planning plus a primitive-local unique-corner edge path reduced the final
  result to 3.881/3.169 ms and 13.029/8.581 MB with the same hash. The new-point
  mode over 100,000 independent quads produces 500,000 points and 500,000
  corners (1,100,000 total point/corner/primitive elements) in 25.952/19.876 ms,
  allocates 81.417/53.952 MB with 41.364/41.380 MB major allocation, and retains
  hash `162055801192148878`. A 400 by 400 shared-point quad grid exercises the
  general ancestry path: replacing a complete second topology index with a
  lightweight target endpoint table reduced allocation from 132.452 MB to
  53.001 MB; the final 159,201-face cook takes 49.227/47.138 ms and retains hash
  `1963371227389512144`. Source/target shared-edge numbering is a serial planning
  dependency, while point, corner, payload, and edge-bitset fills use stable
  disjoint parallel ranges. All Ends hashes match exactly across domain counts.

  Ordered Curve Join processes 1,000 201-point curves (201,000 points) in
  4.885 ms/6.696 MB on one domain and 4.928 ms/6.697 MB on four; at this size its
  stable chain planning is below useful parallel grain. Shared-point inputs
  retain the general reverse-topology fallback. All fixtures carry numeric
  attributes and a fully selected native edge group, and complete hashes match
  across domain counts.

  Explicit endpoint picks use the same allocation-once output and ancestry
  fill after one O(curves) validation/orientation pass. A full-cycle shuffled
  order over the same 1,000 by 201-point source, with alternating authored end
  choices, measures 4.876/4.843 ms and allocates 6.704/6.706 MB on one/four
  domains. It emits 402,001 point/corner/primitive elements with exact hash
  `4405899669469262432`; unlike the spatially continuous ordered fixture, its
  authored bridges deliberately do not weld 999 adjacent endpoints. The
  matching ordered fixture remains 4.885/4.928 ms with its prior hash
  `1479753540783563888`, so the new control does not regress the legacy path.
  The four-domain one-repeat suite peaked at 88,108 KiB RSS. These are
  11-repeat release medians on OCaml 5.3.0, grain 16,384, Linux 6.8 aarch64,
  and four single-threaded Apple CPU cores.

  Global closest-end Join uses a separate 65,537-curve fixture whose input
  order is a full-cycle permutation of a continuous spatial path. The first
  correct removable k-d-tree version measured 144.371 ms and allocated
  316.180 MB. Removing boxed coordinate-return helpers, using `Float.hypot`'s
  no-allocation scale-safe primitive, and keeping widest-extent scratch in
  reusable unboxed float planes reduced the same output; the current
  11-repeat medians are 85.523/85.174 ms
  and 25.248/25.256 MB on one/four domains. Major allocation is
  15.271/15.271 MB, peak RSS is 74,420/74,360 KiB, and both runs retain full
  payload/group/native-edge hash `1380559747436316341`. Greedy ordering is a
  serial dependency, so the nearly equal domain timings are expected; endpoint
  preparation and output/payload copies remain parallel. The 257-curve direct
  regression compares the tree order to an exhaustive all-endpoint oracle.
  Enabling 128-curve subgroups and retaining every original primitive over the
  same source produces 394,248 point/corner/primitive elements in
  109.231/106.873 ms, allocates 69.053/66.968 MB, uses 50.531/50.533 MB major,
  and preserves hash `4452400491292640673`. The output shares the source point
  plane; its added storage is topology, remapped corner/primitive payload, and
  the topology-indexed native-edge union needed for overlapping originals and
  joined curves.
  Reproduce the curve-family fixtures with
  `RAYS_RDK_OPS_FILTER=curve_ RAYS_RDK_CURVE_POINTS=200001
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1
  dune exec tools/bench_rdk_ops.exe`, and the Join-only fixtures with
  `RAYS_RDK_OPS_FILTER=curve_join RAYS_RDK_OPS_REPEATS=11
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`; repeat with four domains.
- PolyLoft was measured on 1,001 closed 1,000-point sections: 1,001,000
  shared input points become 2,000,000 triangles and 6,000,000 corners without
  a copied position plane. Authored-order two-point pairing takes
  250.095/183.579 ms on one/four domains (1.36x) with exact hash
  `2140630329163433337`; authored three-point pairing takes 269.419/180.274 ms
  (1.49x) with hash `270081320839283753`. Both allocate 194.461 MB in the
  one-domain process, of which 194.048/194.121 MB is required major topology,
  ancestry, and plan storage, with zero or negligible promotion. Closest-seam
  three-point mode additionally builds one bounded packed spatial index per
  independent section pair and measures 672.405/323.658 ms (2.08x), with exact
  hash `2336594115402408393`; its one-domain harness allocation is 411.229 MB
  and major allocation 226.166 MB. The four-domain `allocated_bytes` field is
  a calling-domain counter and therefore does not include every worker-domain
  minor allocation; the separately reported process-wide major count is
  226.267 MB. An isolated closest-mode four-domain run peaked at 273,920 KiB
  RSS; authored mode peaked at 236,544 KiB.

  The first correct million-point authored run used polymorphic `max` inside
  distance normalization and boxed hot-loop float intermediates: one repeat
  took 307.857 ms and allocated 386.365 MB for the same final hash. Typed
  `Float.max`, direct boolean distance comparison, cancellation of the common
  three-point perimeter edge, and a zero-tolerance topology-stable fast path
  reduced a comparable final one-repeat run to 269.054 ms and 194.461 MB—12.6%
  faster and 49.7% less allocation. Reproduce the stable medians with
  `RAYS_RDK_OPS_FILTER=poly_loft RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains and use
  `/usr/bin/time -v` with one repeat for peak RSS.
- Skin uses the same 1,001 by 1,000 closed-section fixture but retains one quad
  per segment: 1,001,000 shared points become 1,000,000 polygons and 4,000,000
  corners. Under the OCaml 5.3.0 release profile on the four-core ARM64 Linux
  host, authored seams take 64.078/48.606 ms on one/four domains (1.32x), with
  121.264/98.039 MB harness allocation and exact hash
  `1185213538368565200`. Closest seam/orientation selection takes
  471.551/177.750 ms (2.65x), with 338.032/152.855 MB calling-domain
  allocation and exact hash `4033760677203082832`. The authored four-domain
  process peaks at 165,248 KiB RSS. On the same release build, triangle-only
  authored PolyLoft takes 92.054 ms on four domains and emits 2,000,000 faces
  and 6,000,000 corners, so preserving quads removes one million primitives,
  two million corners, 38.5% of reported allocation, and 47.2% of wall time.
  Reproduce with
  `RAYS_RDK_OPS_FILTER=skin RAYS_RDK_OPS_COLUMNS=1000
  RAYS_RDK_OPS_ROWS=1000 RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains. Use
  `/usr/bin/time -v` and one repeat for peak RSS.
- PolyBridge was measured with 1,000,000 input points and 500,000 generated
  quads while retaining the two selected boundary faces/curves and their
  native edge groups. A single pair of 500,000-edge loops takes
  106.422/106.763 ms on one/four domains with exact hash
  `3425731626861180224`; its ordered traversal and one zipper plan are
  intentionally sequential, while packed remapping still uses the pool. A
  1,000-pair fixture with 500 edges per loop exposes independent plan work and
  takes 102.165/91.849 ms (1.11x), allocating 133.562/123.616 MB in the
  calling-domain counters with hash `4562963049391598617`. Centroid-rank
  pairing takes 115.296/105.471 ms (1.09x), allocates 134.154/122.479 MB, and
  preserves the same exact output hash for the spatially ordered fixture. An
  isolated authored four-domain run peaked at 389,648 KiB RSS, including both
  million-point benchmark inputs and their cached topology indexes.

  The first correct centroid-rank preparation used mutable float references in
  its million-point centroid scan. On the one-domain fixture it took
  129.272 ms and allocated 178.362 MB. Replacing those boxed updates with six
  fixed unboxed float-array cells reduced the same hash to 115.296 ms and
  134.154 MB: 10.8% less wall time and 24.8% less allocation. Component pairing
  itself sorts centroid ranks in O(k log k); it does not use a quadratic greedy
  nearest-component scan. Reproduce with
  `RAYS_RDK_OPS_FILTER=poly_bridge RAYS_RDK_OPS_COLUMNS=1000
  RAYS_RDK_OPS_ROWS=1000 RAYS_RDK_OPS_REPEATS=5
  RAYS_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_rdk_ops.exe`, then repeat with four domains and use
  `/usr/bin/time -v` with one repeat for peak RSS.
- Three-repeat release medians for the divided PolyBridge fixture retain the
  same 1,000,000 boundary points,
  inserts 500,000 midpoint-row points, and emits 1,000,000 quads/4,000,000 new
  corners. One giant pair takes 209.890/195.304 ms on one/four domains with
  278.909/278.958 MB calling-domain allocation and exact hash
  `750105119733076194`. The 1,000-pair form takes 202.811/184.289 ms and
  279.437/197.469 MB with hash `2567031205360025512`. Large single-pair point
  and face-validity fills use stable pool ranges, but ordered boundary tracing,
  exact face compaction, and final boundary-edge remapping remain serial enough
  that this two-row geometry-only case scales by 1.08x; the multi-pair case
  scales by 1.10x.

  A payload fixture adds one million point floats, one million vertex floats,
  and a point group before the same divided cook. It measures
  303.022/246.646 ms (1.23x), allocates 499.777/415.384 MB in the calling-domain
  counters, and preserves hash `3377060408763636413`. The isolated four-domain
  payload process peaks at 564,848 KiB RSS. Interpolation/nearest-owner maps are
  omitted entirely when an owner has no matching attributes or groups; numeric
  packed fills use disjoint ranges. Reproduce these rows with the same command
  above and filters `poly_bridge_single_divided`,
  `poly_bridge_many_divided`, and `poly_bridge_many_divided_payload`.

## Parallel execution

_Continues "Frame performance is qualified with the cleanup plan's…" in performance.md:_
`tools/bench_shattered_renderer.exe` (visible and hidden, release profile,
reporting the live drawable scale), `bench_uniforms`, `bench_scene2_ir`,
`bench_instances`, `bench_pxui` and `bench_pxui_graph`, recorded before and
after a change on the same machine, plus a one-domain versus N-domain output
comparison. The target is p95 at or under 16.67 ms at the display's scale. The
earlier R9–R12 native protocols (frozen 640×480 envelope, one-upload contract,
30-minute stability run) were retired on 2026-09-25 once that target was met;
their tooling lives in git history before that date.

Reproduce the finite shattered-cube native workflow without a backend selector:

```sh
RAYS_SHATTER_FRAMES=1 \
  /usr/bin/time -p dune exec sketches/shattered_cube/main.exe
RAYS_SHATTER_FRAMES=1001 \
  /usr/bin/time -p dune exec sketches/shattered_cube/main.exe
```

## Measurement contract

_Continues "A concave polygon with more than one retained…" in performance.md:_
The regression covers two disconnected retained
fragments, the connected complementary side, primitive ancestry, native cut
edges, two caps on an extruded closed mesh, and exact one/four-domain output.

_Continues "Nested Clip caps keep direction while tracing boundary…" in performance.md:_
At least two
nested components and 64 total boundary tokens use disjoint shared-pool
triangulation slots before a
stable sequential append; exact one/four-domain coverage uses eight hollow
components. A single component is intentionally sequential because each bridge
changes the next visibility polygon.

The release fixture clips 65 closed boxes into one outer contour with 64
oppositely wound square holes: 520 source points and 3689 output-cardinality
units. Three fresh-process medians (three cooks each) are 21.536/21.727 ms and
3.259/3.259 MB allocated for one/four domains, with identical hash
3205380715766440722. The lack of material multicore speedup is expected for
one nested component; ordinary classification, intersection, payload, and
polygon fast paths retain their existing parallel plans.

The complementary independent-component fixture uses sixteen hollow shells
with 64 subdivisions per contour: 270,400 source points and 872,480 output
cardinality units. Three fresh-process medians (three cooks each) take
118.647/82.775 ms and allocate 191.884/190.301 MB for one/four domains, a
1.43x wall-time speedup with identical hash 3987358132378291101. This measures
the disjoint component planner rather than implying that one hole hierarchy is
internally parallel.

The corrected scale fixture has 1,002,001 points, two million triangles, and
6,000,000 corners. Before exact planning, plain one/four-domain Clip took
276.174/273.832 ms and allocated 759.222/759.316 MB; the attributed case took
321.898/285.011 ms and 859.148/859.384 MB. Exact planning produces identical
hashes while taking 240.945/174.607 ms and 532.942/455.425 MB for plain Clip,
and 266.471/196.192 ms and 632.868/556.435 MB for attributed Clip. A float4
custom-coordinate, plane-distance, and clipped-edge-output case takes
541.924/420.652 ms and 1,119.801/1,040.235 MB. The earlier benchmark row was
incorrectly labeled as a million-point input while clipping a 40,401-point
helper grid; it is not used as scale evidence.

_Continues "Typed Clip restriction first promotes the selection once…" in performance.md:_
On the same scale
fixture, selecting the contiguous first third of primitives while carrying the
attribute fixture takes a median 434.681/316.615 ms and allocates
793.385/765.621 MB for one/four domains. Materializing a clipped native-edge
group takes 867.203/732.392 ms and 1,594.573/1,559.907 MB because it also builds
the complete output topology index. The respective deterministic hashes are
4451540838762259033 and 2517369864773722023 for both domain counts. These are
medians of three fresh processes, each reporting the median of three cooks;
the machine/compiler context is the same as the other RDK rows in this file.

```sh
RAYS_RDK_OPS_FILTER=clip_ RAYS_RDK_OPS_REPEATS=3 \
RAYS_RDK_OPS_COLUMNS=1000 RAYS_RDK_OPS_ROWS=1000 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

_Continues "The shared RDK subdivision kernel computes exact child…" in performance.md:_
On
the 40,401-point/80,000-triangle attribute fixture, refreshed five-run release
medians are 67.794/45.713 ms for Loop and 102.178/65.446 ms for Catmull-Clark
at one/four domains. A dense semi-sharp Catmull-Clark fixture is
112.652/65.699 ms; bilinear is 36.949/28.280 ms. The earlier four-domain
baselines were respectively 57.4, 79.3, 90.1, and 38.5 ms. Exact hashes remain
unchanged across domain counts and the planning refactor.

_Continues "Primitive-group refinement partitions selected and unselected topology once…" in performance.md:_
The 40,401-point/80,000-triangle
release fixture measured 45.092/42.126 ms and 90.294 MB allocated for a
contiguous half selection; a boundary-heavy alternating selection measured
78.368/69.726 ms and 180.648 MB. Exact hashes were respectively
`2012308210456171798` and `518621518380473251` at one/four domains. Stable
partition/fan/topology planning limits scaling even though packed position and
payload fills remain parallel. Catmull-Clark on the contiguous selection is
60.233/37.981 ms and 122.303 MB; exact Pull Closed/No Edge Division ancestry
and projection is 71.236/44.817 ms and 136.993 MB; Stitch/No Edge Division is
79.003/71.801 ms and 155.226 MB. Their respective exact hashes are
`1738102442901827305`, `629813708611520190`, and `3137573248193083737`.
The Pull pass avoids a redundant target topology index by scanning stable
primitive corner ranges directly. Stitch pre-counts every bridge triangle,
allocates once, and remaps packed vertex/primitive payloads by stable ancestry.
Folding bridge emission into the initial combine removed a second geometry
materialization and improved the one-domain Stitch baseline from
84.637 ms/167.561 MB to 79.003 ms/155.226 MB without changing its hash.
Pull/Divide Edges with bias 0.75 measures 95.597/85.064 ms and
187.733/174.651 MB at one/four domains; Stitch/Divide Edges measures
92.528/84.267 ms and 187.743/174.650 MB. Their exact hashes are respectively
`3697698291297517219` and `4580811677866533301`. The first divided-edge
prototype measured about 399 MB and 200 ms because it materialized a complete
combined geometry and then welded it. Direct final point, attribute, group,
and topology remapping removed that second snapshot, while direct extraction
from the selected source removed the intermediate unselected copy.
Pull/Triangulate measures 105.583/99.790 ms and 212.563/199.478 MB;
Stitch/Triangulate measures 110.261/94.770 ms and 211.425/198.344 MB. Their
exact one/four-domain hashes are `1771144634972156419` and
`3868299086784368101`. Triangulation touches only surrounding polygons, uses
the shared reusable ear-clipping scratch, preserves original edges/groups, and
does not allocate a temporary corner array for unchanged primitives.
Consistent Stitch/Divide measures 80.425/76.341 ms and 160.110/158.846 MB;
consistent Stitch/Triangulate measures 91.859/84.722 ms and
183.091/181.827 MB. Exact hashes are `2807886286253650657` and
`249501161833618177`. Consistency mode is position-independent and avoids the
adaptive coincidence-weld maps, so it is faster and allocates less despite
retaining every prescribed bridge triangle. Consistent Pull/Triangulate is
107.589/98.021 ms and 211.353/198.259 MB with exact hash
`1351686240886644603`.

_Continues "Second-input crease preparation reuses the source topology index…" in performance.md:_
On the same 40,401-point fixture, five release medians measured:

| Second-input crease case | 1 domain | 4 domains | Allocated 1d/4d | Exact hash |
|---|---:|---:|---:|---:|
| dense vertex attributes | 141.076 ms | 96.156 ms | 256.813/193.785 MB | 2240368469655108917 |
| dense attributes + resulting edge group | 149.133 ms | 99.783 ms | 262.722/199.795 MB | 512181311574988744 |
| sparse 200-edge override | 96.761 ms | 71.249 ms | 214.329/164.443 MB | 2384261217015432874 |

_Continues "The first resulting-group implementation constructed and retained a…" in performance.md:_
It measured
223.609/189.828 ms and 406.677/382.754 MB at one/four domains. Subdivide now
derives the two child ordinals of every source edge while scanning its already
deterministic refinement topology. That cut the measured one-domain group
case by 32% in time and 35% in allocation, and benefits ordinary propagated
native edge groups as well. The direct ordinal plan uses O(output edges)
integer scratch and one final packed bitset; it does not retain the scratch.
The filtered five-repeat four-domain benchmark process peaked at 1,132,032
KiB RSS, but this harness eagerly constructs the complete `bench_rdk_ops`
fixture catalog before applying its output filter, so the number is a process
upper bound rather than isolated Subdivide live memory.

_Continues "Hole refinement uses the complete source adjacency for…" in performance.md:_
Sparse holes (one of every 401 input triangles) measure 110.696/69.177 ms and
177.146/137.571 MB at one/four domains, with exact hash
`316117588020776784`. A 50% alternating hole pattern emits 840,801 total
elements and measures 89.885/55.928 ms and 146.923/111.090 MB, exact hash
`2308137223929356764`. Retaining those same hole descendants emits 1,440,801
elements and measures 103.292/65.256 ms and 176.658/140.839 MB, exact hash
`2631021000821162415`. Thus dense removal saves work proportional to omitted
corner topology without changing the full point/edge stencil cost. Exact
one-/four-domain tests additionally cover recursive holes, Loop, all-hole
zero-topology output, local Stitch closure, crease/result groups, and a
deformed control face whose influence proves holes were not pre-deleted.

_Continues "OpenSubdiv point-boundary policy adds no alternate geometry representation…" in performance.md:_
On the same
attribute-heavy fixture, current five-repeat release medians are:

| Point-boundary policy | 1 domain | 4 domains | Allocated 1d/4d | Output elements | Exact hash |
|---|---:|---:|---:|---:|---:|
| Edge Only (default) | 102.178 ms | 65.446 ms | 176.628/143.392 MB | 1,440,801 | 376865061323882225 |
| Edge and Corner | 102.539 ms | 69.266 ms | 176.628/138.165 MB | 1,440,801 | 3019365180156623813 |
| None | 105.291 ms | 70.406 ms | 176.105/140.237 MB | 1,416,921 | 4379739223844025455 |

The filtered boundary-only four-domain process peaked at 1,180,288 KiB RSS;
as elsewhere in this harness, that is a conservative process bound because
the complete benchmark fixture catalog is constructed before name filtering.
Measurements used OCaml 5.3.0, Dune 3.24.0, release profile, grain 16,384, and
Linux 6.8/aarch64 on four cores. Exact one/four-domain geometry tests cover all
three policies on Catmull-Clark and Loop, ordinary point attributes, recursion,
explicit-hole union, local selection, closed manifolds, and bilinear immunity;
the native render regression composes None with holes and second-input
creases and compares byte-identical PNG output.

_Continues "Face-varying policy classification is cardinality-first and retains exact…" in performance.md:_
A
direct stencil-replay experiment reduced the filtered one-domain process peak
from about 380 MiB to 297 MiB, but regressed mixed-field median time from
152.6 ms to 196.7 ms and increased total allocation from 334.8 MB to
485.3 MB, so it was rejected. Current five-repeat release medians on the same
40,401-point, 1,440,801-output-element fixture are:

| Face-varying case | 1 domain | 4 domains | Allocated 1d/4d | Exact hash |
|---|---:|---:|---:|---:|
| continuous None | 100.321 ms | 64.787 ms | 184.118/146.875 MB | 429426008655497585 |
| continuous Corners Only | 100.882 ms | 69.332 ms | 184.118/143.503 MB | 4186862701813665901 |
| continuous Corners Plus 1 | 100.597 ms | 68.507 ms | 184.118/146.253 MB | 4186862701813665901 |
| continuous Corners Plus 2 | 100.914 ms | 59.807 ms | 184.118/145.397 MB | 4186862701813665901 |
| continuous Boundaries | 101.219 ms | 58.772 ms | 184.118/146.869 MB | 1154938882242345689 |
| continuous Linear All | 95.196 ms | 55.193 ms | 176.628/138.157 MB | 4450550210505620753 |
| fully seamed None | 114.154 ms | 77.978 ms | 204.999/163.981 MB | 1190890693971099377 |
| fully seamed Corners Plus 2 | 110.997 ms | 74.811 ms | 195.399/160.471 MB | 376865061323882225 |
| mixed-region None | 152.556 ms | 100.775 ms | 334.811/260.132 MB | 177903855920259413 |
| mixed-region Corners Plus 2 | 170.897 ms | 110.644 ms | 360.365/281.360 MB | 3568052415005862933 |

Promoted allocation stayed below 23 KB; measured major allocation ranged from
119.8 MB for Linear All to 216.6 MB for the mixed Plus 2 case. Running all ten
filtered cases sequentially with one repeat peaked at 374,584 KiB RSS on one
domain and 463,512 KiB on four; these are process high-water values, not an
isolated cook's live set. Exact one/four-domain regressions cover every policy,
continuous and tuple seams, three-region junctions, concave corners, darts,
crease/corner precedence, Catmull-Clark and Loop, recursion, local selection,
bilinear immunity, cancellation, and byte-identical native rendering.
Measurements used OCaml 5.3.0, Dune 3.24.0, release profile, grain 16,384, and
Linux 6.8/aarch64 on four cores.

_Continues "Smooth Triangles is a branch inside the existing…" in performance.md:_
On a 40,401-point
triangle grid with point color and smoothly constrained vertex UVs, five-repeat
release medians were:

| Catmull-Clark triangle policy | 1 domain | 4 domains | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|
| standard Catmull-Clark | 103.542 ms | 61.490 ms | 186.025/142.377 MB | 122.782/122.789 MB | 4420175619764081105 |
| Smooth Triangles | 105.373 ms | 65.348 ms | 190.809/150.437 MB | 122.782/122.790 MB | 3600355083164985970 |

Promoted allocation remained below 12 KB. Running the two filtered cases once
peaked at 403,620 KiB RSS on one domain and 393,264 KiB on four, including the
benchmark fixture catalog and Dune process. Tests verify exact two-triangle and
triangle/quad masks, point and face-varying fields, default compatibility,
fully sharp precedence, Loop/bilinear immunity, recursive and local cooks,
one/four-domain geometry, and framebuffer parity on the same toolchain above.

_Continues "Uniform and Chaikin creasing share one packed child-edge…" in performance.md:_
On a 40,401-point grid with densely varying
0–4 vertex crease weights and resulting-edge output, five-repeat release
medians were:

| Creasing method | 1 domain | 4 domains | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|
| Uniform (default) | 132.584 ms | 79.727 ms | 303.400/210.216 MB | 138.178/138.214 MB | 1632760353092613440 |
| Chaikin | 130.234 ms | 84.001 ms | 302.824/207.504 MB | 138.179/138.211 MB | 2032098541220815572 |

Promoted allocation stayed below 41 KB. Running both filtered cases once
peaked at 295,332 KiB RSS on one domain and 293,568 KiB on four, including the
fixture catalog and Dune process. Exact regressions cover asymmetric child
weights, side-specific resulting groups, a sub-unit parent retained as a full
crease, parent/child vertex-rule transitions, second-input and local creases,
Loop, recursion, point corners, smoothly constrained FVar data, 120×80
one/four-domain geometry, and byte-identical native rendering.

_Continues "Houdini detail controls add one sequential scan of…" in performance.md:_
To isolate that dispatch from
the unavoidable propagation of five detail fields, the paired fixture gives
both inputs five integer detail attributes and runs otherwise identical
Catmull-Clark/Chaikin refinement with a resulting edge group; only the second
set uses the recognized `osd_*` names. On the same 40,401-point fixture,
five-repeat release medians were:

| Subdivide option source | 1 domain | 4 domains | Allocated 1d/4d | Major 1d/4d | Output elements | Exact hash 1d/4d |
|---|---:|---:|---:|---:|---:|---:|
| explicit controls + inert detail payload | 147.577 ms | 93.406 ms | 302.826/207.723 MB | 138.179/138.213 MB | 1,440,801 | 3923383528131482323 |
| `osd_*` detail overrides | 148.886 ms | 94.263 ms | 302.826/206.888 MB | 138.179/138.211 MB | 1,440,801 | 3235061806261494492 |

The measured dispatch delta was 0.9% on both domain counts and 80 allocated
bytes on the one-domain path; the four-domain allocation difference is
scheduler noise in the opposite direction. Promoted allocation remained below
45 KB. Hashes differ between rows because the preserved detail names differ,
but each row's hash is exact across domain counts. One-repeat filtered harness
RSS peaked at 1,058,796 KiB on one domain and 1,036,420 KiB on four; as with the
other Subdivide figures, the benchmark eagerly retains the complete fixture
catalog, so this is a conservative process high-water mark rather than the
live set of one cook. Exact tests cover all documented integer mappings, both
scheme storage forms and all three tokens, precedence, recursive/local cooks,
malformed controls, field preservation, large one/four-domain output, and
byte-identical framebuffer rendering.

_Continues "The no-second-input all-edge override is not implemented by…" in performance.md:_
A paired 40,401-point fixture compares that direct path with an
authored per-corner value of 3.0; both emit a resulting native edge group and
produce the identical complete geometry hash:

| All-edge sharpness source | 1 domain | 4 domains | Allocated 1d/4d | Major 1d/4d | Output elements | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| authored vertex attribute | 148.409 ms | 94.564 ms | 303.356/209.636 MB | 138.179/138.212 MB | 1,440,801 | 3237429061180838349 |
| direct scalar override | 142.371 ms | 94.053 ms | 291.836/192.485 MB | 138.179/138.212 MB | 1,440,801 | 3237429061180838349 |

Five-repeat release medians show the direct path 4.1% faster on one domain and
0.5% faster on four while avoiding 11.5/17.2 MB of allocation. Promoted
allocation stayed below 39 KB. A one-repeat run containing both cases peaked at
1,155,912 KiB RSS on one domain and 1,038,612 KiB on four; the eager benchmark
catalog makes these conservative process bounds. Exact regressions cover every
source edge, replacement of existing vertex/primitive weights, zero,
recursion, selected-only local application, structured invalid values,
one/four-domain geometry, procedural caching, and framebuffer parity.

_Continues "Point-normal Subdivide retains the same cardinality-first point stencil…" in performance.md:_
On a 40,401-point attributed triangle grid producing
1,440,801 total output elements, nine-repeat release medians were:

| Point-normal policy | 1 domain | 4 domains | Allocated 1d/4d | Major 1d/4d | Exact hash 1d/4d |
|---|---:|---:|---:|---:|---:|
| no input point `N` | 91.725 ms | 56.990 ms | 180.456/141.164 MB | 119.798/119.805 MB | 376865061323882225 |
| interpolate existing point `N` | 106.291 ms | 67.542 ms | 186.236/146.964 MB | 125.577/125.584 MB | 207165435372938504 |
| recompute existing point `N` | 117.539 ms | 74.250 ms | 197.777/155.503 MB | 137.116/137.124 MB | 4372715722947678204 |

All hashes are exact across domain counts. Retaining the required three packed
normal planes adds 5.78 MB over the no-normal baseline; final recomputation
adds one face-vector/normal pass and 11.54 MB on the one-domain measurement.
The same cases speed up by 1.61x, 1.57x, and 1.58x at four domains. Promoted
allocation stayed below 10 KiB. A one-repeat process containing all three
cases peaked at 296,736 KiB RSS on one domain and 323,592 KiB on four,
including the eagerly created benchmark fixture catalog. Exact regressions
cover default non-normalized interpolation, opt-in normalized surface normals,
zero curve/free-point normals, missing-`N` non-creation, recursive/local
cooks, exact one/four-domain geometry, Procedural cache identity, and
byte-identical rendered pixels.

_Continues "Polygon-curve Subdivide uses exact point/stencil/vertex cardinalities and packed…" in performance.md:_
A first correct mixed-family implementation
sent curve-only inputs through extraction, concatenation, and primitive sort;
on the 200,001-point/200,000 two-point-curve fixture that cost 306.220 ms and
526.304 MB allocated for shared curves, or 323.742 ms and 560.154 MB for
independent curves on one domain. The production path now detects whole
curve-only cooks and enters the one-dimensional planner directly. The complete
geometry hashes are unchanged. Nine-repeat release medians after that removal
and disjoint primitive/stencil fills were:

| Curve refinement | 1 domain | 4 domains | Allocated 1d/4d | Major 1d/4d | Output elements | Exact hash 1d/4d |
|---|---:|---:|---:|---:|---:|---:|
| Catmull-Clark shared graph | 91.021 ms | 82.602 ms | 184.095/184.158 MB | 155.190/155.191 MB | 1,200,001 | 3005310147150241906 |
| Catmull-Clark independent curves | 101.362 ms | 94.466 ms | 197.320/197.382 MB | 168.390/168.390 MB | 1,400,000 | 4407673620802799165 |
| Bilinear shared graph (five repeats) | 85.665 ms | 75.742 ms | 177.695/177.752 MB | 148.790/148.791 MB | 1,200,001 | 1279515269836849834 |

The curve-only dispatch optimization reduced one-domain Catmull-Clark wall
time by 70.3% shared and 68.7% independent, and allocation by 65.0%/64.8%.
Independent output is intentionally larger because each of the 400,000 source
corners owns a distinct old point before the midpoint insertion. Promoted
allocation stayed below 2 KiB. A one-repeat process containing both
Catmull-Clark cases peaked at 524,104 KiB RSS on one domain and 512,108 KiB on
four; the harness still constructs its general fixture catalog eagerly.
Measurements used OCaml 5.3.0, Dune 3.24.0, the release profile, grain 16,384,
and the four-core Linux 6.8 aarch64 runner. Exact regressions cover open and
closed curves, shared degree-two smoothing, pinned endpoints, Houdini-style
independence, bilinear and detail overrides, local and recursive refinement,
mixed primitive ordering, free points, every payload/group owner, native edge
ancestry, malformed topology, cancellation, 50,000-segment one/four-domain
geometry, and byte-identical framebuffer output.

Reproduce with:

```sh
RAYS_RDK_OPS_FILTER=subdivide_bilinear_local \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.

RAYS_RDK_OPS_FILTER=subdivide_catmull_second_input \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.

RAYS_RDK_OPS_FILTER=subdivide_catmull_sparse_holes \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=subdivide_catmull_dense_holes \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat both with RAYS_BENCH_DOMAINS=4.

RAYS_RDK_OPS_FILTER=subdivide_catmull_grid_boundary \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

RAYS_RDK_OPS_FILTER=subdivide_catmull_fvar \
RAYS_RDK_OPS_COLUMNS=1 RAYS_RDK_OPS_ROWS=1 \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

RAYS_RDK_OPS_FILTER=subdivide_catmull_triangles \
RAYS_RDK_OPS_COLUMNS=1 RAYS_RDK_OPS_ROWS=1 \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

RAYS_RDK_OPS_FILTER=subdivide_catmull_creasing \
RAYS_RDK_OPS_COLUMNS=1 RAYS_RDK_OPS_ROWS=1 \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

RAYS_RDK_OPS_FILTER=subdivide_catmull_explicit_controls_detail_payload \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=subdivide_catmull_detail_overrides \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat both with RAYS_BENCH_DOMAINS=4; wrap the second in
# /usr/bin/time -v for RSS.

RAYS_RDK_OPS_FILTER=subdivide_catmull_all_edges_ \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

RAYS_RDK_OPS_FILTER=subdivide_catmull_normals \
RAYS_RDK_OPS_REPEATS=9 RAYS_RDK_OPS_COLUMNS=200 \
RAYS_RDK_OPS_ROWS=200 RAYS_BENCH_DOMAINS=1 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use repeats=1 under /usr/bin/time -v
# for the conservative process RSS figure.

RAYS_RDK_OPS_FILTER=subdivide_catmull_curves \
RAYS_RDK_CURVE_POINTS=200001 \
RAYS_RDK_OPS_COLUMNS=200 RAYS_RDK_OPS_ROWS=200 \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=9 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4 and use repeats=1 under /usr/bin/time -v
# for the conservative process RSS figure.

RAYS_RDK_OPS_FILTER=subdivide_bilinear_curves_shared \
RAYS_RDK_CURVE_POINTS=200001 \
RAYS_RDK_OPS_COLUMNS=200 RAYS_RDK_OPS_ROWS=200 \
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

_Continues "Point, vertex, primitive, Blast, and Split filtering share…" in performance.md:_
On the attribute-heavy 240,000-quad
fixture, removing a temporary result tuple reduced one-domain time/allocation
from 45.0 ms/119.4 MB to 35.7 ms/73.2 MB; four domains improved from
32.8 ms/79.1 MB to 27.8 ms/49.7 MB. Output hashes are exact across domains.

_Continues "RDK Convert Line builds the shared reverse-topology index…" in performance.md:_
On
the 1,002,001-point/2,000,000-triangle grid (3,002,000 output lines), the
release command below measured 627.4 ms/316.1 MB allocated on one domain and
298.8 ms/215.5 MB on four; the exact hash was `1159685896482037800` in both
runs. `/usr/bin/time -v` reported a 901,888 KiB process peak for the five-repeat
four-domain harness, including the retained million-point source, reverse
index, output high-water heap, hashing, and Dune. A first finite-distance
validation helper returned `float option` in the edge loop and raised measured
one-domain allocation to 412.2 MB; scalar inlining restored 316.1 MB while
retaining the non-finite-result diagnostic.

_Continues "RDK PolyPath consumes the same cached unique-edge index…" in performance.md:_
Spatial endpoint rewiring
adds O(points + candidate proximity pairs) expected work and O(points) storage;
the spatial hash is linear on sparse neighborhoods, while a deliberately dense
radius can expose quadratically many candidate pairs. It rejects non-finite
positions atomically.

On the same 1,002,001-point/2,000,000-triangle grid with 3,002,000 unique
edges, the first correct implementation copied worst-case graph and path planes
and measured 601.13/568.92 ms with 820.65/820.69 MB allocated at one/four
domains. Borrowing the no-rewire graph removed the second edge hash, but
per-path refs and option closures still raised transient allocation. Reusing
walk state and specializing the dominant one-edge branch path produced the
final 217.67/183.94 ms and 289.22/289.25 MB. Both domain counts return
cardinality `10007997` and exact hash `4605327786602156546`; promoted allocation
is zero. The final operator is 2.8× faster than the measured one-domain
Convert Line materialization baseline while retaining source vertex/primitive
ancestry. The isolated five-repeat four-domain process peaked at 998,940 KiB
RSS, including the million-point source, cached reverse topology, output,
benchmark hashing, Dune, and the OCaml heap.

The same fixture with endpoint connection enabled at exact distance zero
contains no coincident points. Propagating the clustering identity avoids a
redundant second edge hash and measures 319.83/289.57 ms with
362.11/362.14 MB allocated at one/four domains. Its cardinality and hash are
exactly the normal path, proving that enabling a no-op connection policy does
not perturb topology or ordering.

_Continues "Convert Line's Connect Path mode is fused into…" in performance.md:_
On the same
fixture, the correct composed baseline measured 1.168/0.905 s and
1,185.20/1,233.31 MB allocated at one/four domains. The fused operator measured
313.36/302.33 ms and 338.47/338.50 MB: 3.73×/3.00× faster with 71%/73% less
allocation. Both fused domain counts return cardinality `10007997` and exact
hash `402758761000324084`; promoted allocation is zero. The isolated
four-domain harness peaked at 1,047,188 KiB RSS, including the retained source,
reverse index, repeated outputs, hashing, Dune, and the OCaml heap. Optional
path lengths are computed only after final topology and use scale-safe segment
norms plus compensated per-path accumulation.

```sh
RAYS_RDK_OPS_FILTER=poly_path RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=poly_path RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

```sh
RAYS_RDK_OPS_FILTER=convert_line RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=convert_line RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=convert_line_path_fused RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=convert_line_path_fused RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

_Continues "The directed Line source normalizes extreme finite directions…" in performance.md:_
On 1,002,001 points it measured
11.35 ms/32.1 MB on one domain and 8.85 ms/32.1 MB on four, with exact hash
`3766555573609226817`.

_Continues "Circular Sweep/PolyWire now precomputes one sine/cosine cross section…" in performance.md:_
The unchanged 10,001-ring fixture improved from
5.23/5.27 ms at one/four domains to 4.27/4.23 ms without changing hash
`2407863765480717467`. A 120,400-curve point-scaled fixture measured
100.6/83.7 ms and exact hash `1685661557956714237`; enabling oppositely wound
N-gon caps, planar cap UVs, hard vertex normals, and a cap group measured
160.0/131.0 ms with exact hash `2892678817770056258`. The capped output
allocates 488.7 MB of required major payload; the five-repeat four-domain
harness peaked at 1,017,088 KiB including source/index state, output high-water
heap, hashing, and Dune. Scaling is real but memory bandwidth and sequential
attribute materialization dominate after the disjoint curve cook.

The long-spine path is separately measured because partitioning only by curve
cannot parallelize one large input primitive. A 100,001-ring, 12-side spine
started at 84.517/87.193 ms on one/four domains with no multicore speedup and
249.205 MB allocated. Global stable ring and edge planes, parallel explicit-up
projection, and binormal fusion now measure 86.037/80.010 ms with exact
one/four-domain hash `3019630306846948580` and 250.206/248.246 MB allocated.
The fully controlled variant (point scale, snapped seam, authored V/up, caps,
cap group, and payload remapping) measures 145.789/119.431 ms with exact hash
`2382885542052628994`; its 519.163/451.000 MB harness allocation is dominated by required
output and remapped attributes. A three-repeat four-domain run peaked at
441,992 KiB RSS. The ordered rotation-minimizing prefix of a single curve is
intentionally sequential; independent frame projection, rings, topology, UVs,
maps, and multicurve prefixes use disjoint reusable pool ranges.

The variable-resolution fixture has 25,001 source points, divisions cycling
from 6 through 14, endpoint-averaged segment counts cycling from 1 through 3,
point radius scale, and open caps. It emits 2,986,430 total point/corner/face
elements. The first correct general implementation filled topology per curve,
which left a single long spine sequential. Global stable transition ranges now
parallelize that topology without changing hash `2058599888829015206` and
measure 92.008/69.075 ms over eleven release runs on one/four domains (1.33x).
The harness reports 289.891/238.818 MB allocated and 208.150/208.171 MB major;
a separate three-repeat four-domain process peaked at 236,120 KiB RSS. The
fixed-resolution cases above still dispatch directly to their original kernel,
so the new selection/division/segment machinery adds no compatibility-path
cardinality, allocation, or hash change. Measurements used OCaml 5.3.0, Linux
6.8 aarch64, four physical cores, Dune release profile, and grain 16,384.

The segment-placement/UV tranche retains the same 2,986,430-element fixture.
The ordinary variable path now measures 92.810/72.574 ms and
290.290/240.378 MB on one/four domains, within 0.9 ms of the 92.008 ms
pre-feature one-domain baseline after removing a redundant source-edge length
pass. Its exact hash remains `2058599888829015206`. Enabling first/last segment
scales plus custom U/V ranges measures 96.360/69.908 ms, allocates
297.076/246.298 MB, peaks at 237,636 KiB RSS in a separate three-repeat
four-domain process, and preserves exact one/four-domain hash
`3984607635143579421`. Control-only tangent-neighbor and
transition-parameter planes are allocated conditionally, so disabled controls
do not impose their O(rings + transitions) scratch. These three-repeat release
RSS figures and eleven-repeat release medians were collected on the same
OCaml/Linux/four-core machine.

Joint buckling is measured on one 25,001-point alternating sharp polyline with
two longitudinal segments, twelve radial sides, and point-authored maximum
joint scales. Both variants emit 3,600,012 total point/corner/face elements.
The general path without mitigation measures 101.339/79.795 ms on one/four
domains and allocates 334.549/275.710 MB with exact hash
`4388196339880828253`. Exact capped radial miters measure 107.151/83.131 ms,
allocate 344.149/283.814 MB, and preserve exact one/four-domain hash
`2107816651351191467`. A separate three-repeat four-domain process peaked at
269,044 KiB RSS. The additional packed joint-point, distinct-neighbor,
incident-direction, and limit planes exist only when mitigation is enabled;
direct scalar normalization removed two temporary vector tuples per joint.
Ring generation and joint scaling write disjoint stable ranges, while each
curve's ordered tangent/frame prefix remains sequential.

The smooth-run fixture applies 97 point-authored breaks to the same sharp
25,001-point, two-segment, twelve-side source. It emits 3,601,176 total
elements and measures 102.617/81.875 ms on one/four domains, allocating
344.392/284.931 MB with exact hash `3740266745668275405`; the four-domain
eleven-repeat process peaks at 273,308 KiB RSS. Planning adds one ring per
break but no transition face, stores transition endpoints explicitly, and
restarts distinct-neighbor tangent search and frame transport at each packed
run boundary. Output points, transition topology, attributes, and groups still
fill disjoint stable ranges. Max Valence obtains unique selected-edge counts
from the shared packed topology index rather than counting duplicate primitive
incidences.

The per-edge seam fixture uses the 2,986,430-element variable-resolution source
and a complete outgoing-corner integer driver. It measures 103.624/78.526 ms
on one/four domains, allocates 306.693/255.641 MB, peaks at 252,860 KiB RSS,
and preserves exact hash `2516701176577015567`. The extra major payload is the
required remapped vertex driver itself. Transition workers reduce the source
integer independently for each endpoint cardinality and add only bounded
scalar arithmetic to the corner fill; no per-face or per-corner seam scratch is
allocated. Native-edge propagation applies the identical shifted spoke map.

General-profile Sweep has its own two-input benchmark because it performs
variable-profile ancestry and topology work that the precomputed circular
PolyWire kernel does not. The fixture uses one 20,001-point spatial backbone,
one 32-point closed five-lobed profile, distance-weighted twist, alternating
triangles, and normalized vertex UVs. It emits 640,032 points, 1,280,000
triangles, and 3,840,000 corners (cardinality 5,760,032). The first correct
development-profile implementation measured 141.738/96.831 ms on one/four
domains, allocated 657.783/372.467 MB through the harness counter, and promoted
235.696/235.725 MB to the major heap. Removing per-triangle tuples, allocating
ancestry only for payload-bearing owners, and deriving primitive pair/local
coordinates from compact pair prefixes reduced the same development build to
94.061/58.009 ms and 267.384/175.577 MB while preserving hash
`3981213447694709042` exactly.

After replacing per-vertex rotation/quaternion tuples with direct plane writes,
the final OCaml 5.3.0 release build measures 94.992 ms on one domain and 56.209
ms on four (1.69×), with 262.584/170.775 MB allocated, 121.765/121.794 MB major,
and 139,532/143,956 KiB peak RSS. A second quad/cap fixture preserves point and
vertex fields, ordinary groups, and native edge groups from both inputs. Its
3,840,098-element result measures 354.415/308.401 ms, allocates
775.717/663.435 MB, uses 541.768/541.833 MB major, peaks at 548,664/554,916 KiB,
and retains exact hash `3281918545425613217`. Required remapped payload and the
target reverse-topology build dominate this case, so its multicore gain is
1.15×; the evidence does not imply that metadata-heavy edge provenance scales
like the bare surface fill. Measurements used Linux 6.8 aarch64, four physical
cores, Dune's release profile, grain 16,384, and five repeats.

```sh
RAYS_RDK_OPS_FILTER=sweep_general_profile_triangles RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=sweep_general_profile_triangles RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=sweep_general_profile_payload RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=sweep_general_profile_payload RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_smooth_runs RAYS_RDK_OPS_REPEATS=11 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_smooth_runs RAYS_RDK_OPS_REPEATS=11 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_variable_segment_seam \
RAYS_RDK_OPS_REPEATS=11 RAYS_BENCH_DOMAINS=1 \
opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_variable_segment_seam \
RAYS_RDK_OPS_REPEATS=11 RAYS_BENCH_DOMAINS=4 \
opam exec --switch=. -- /usr/bin/time -v \
  dune exec --profile release tools/bench_rdk_ops.exe
```

```sh
RAYS_RDK_OPS_FILTER=line_generator RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=sweep_caps RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_variable RAYS_RDK_OPS_REPEATS=11 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_variable RAYS_RDK_OPS_REPEATS=11 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_sharp_joints RAYS_RDK_OPS_REPEATS=11 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=polywire_sharp_joints RAYS_RDK_OPS_REPEATS=11 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_rdk_ops.exe
```

Resample's compatibility baseline processed a 200,001-point spine into
1,000,001 points in 32.938/31.005 ms on one/four domains, allocated 73.603 MB,
and produced hash `2971143590344181036`; the former per-curve loop could not
split one long primitive. The packed planner retains that exact hash and
73.606/73.631 MB allocation while measuring 36.700/24.233 ms. The small
one-domain generality cost buys a 21.8% four-domain reduction and length-driven
cardinality without adding an O(output log input) search: each stable output
chunk binary-searches only its first source interval, then advances linearly.
The 1,074,510-point maximum-length fixture with U, curve number, coverage
distance, and tangent fields measures 63.972/46.253 ms, allocates
130.549/130.597 MB, and has exact one/four-domain hash
`1048065382090500334`. Its hot loops allocate no per-sample boxes. A
three-repeat four-domain run peaked at 169,212 KiB RSS.

```sh
RAYS_RDK_OPS_FILTER=resample RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=resample RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

_Continues "PolyFrame is topology-linear: every style takes O(points +…" in performance.md:_
Two Edges, Texture UV, and Attribute Gradient respectively measured
61.101/306.398/371.884 ms and allocated 187.772/912.803/1,142.646 MB on one
domain. Direct plane accumulation, scalar derivative components, and hoisted
selection state removed the element boxes. The SideFX parity audit also
corrected Two Edges from `next - previous` to the documented sum of both
point-relative edge vectors; its final hash therefore changes intentionally.
Explicit orthogonal handedness makes raw gradient-bitangent scratch unnecessary
when that output will be reconstructed from normal and tangent. Five-run
release medians are:

| PolyFrame style | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Two Edges | 48.073 ms | 31.658 ms | 1.52x | 51.961 / 51.987 MB | `3123100058409629911` |
| Texture UV, point | 110.741 ms | 59.595 ms | 1.86x | 105.961 / 106.010 MB | `878999954786908287` |
| Attribute Gradient, vertex | 177.802 ms | 89.785 ms | 1.98x | 226.806 / 226.897 MB | `2738302846155992846` |

_Continues "Every final path promoted zero bytes. The remaining…" in performance.md:_
The remaining allocation is the packed
normal/frame output, topology incidence, and style-specific shared scratch;
there is no per-point, per-corner, or per-primitive box in the measured loops.
The isolated five-repeat four-domain process peaked at 511,376 KiB RSS. Exact
geometry hashes match across domain counts, and the procedural framebuffer
regression also matches one versus four domains. Measurements used OCaml
5.3.0, Dune 3.24.0, release profile, grain 16,384, and Linux 6.8/aarch64 on
four cores.

```sh
RAYS_RDK_OPS_FILTER=polyframe RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use /usr/bin/time -v for process RSS.
```

_Continues "Facet Unique Points is O(points + vertices +…" in performance.md:_
On a 200,901-point/1,200,000-corner UV grid, the
ungrouped rows below are final five-run release medians. The new alternating
primitive-group rows are three-run medians on the same machine and profile:

| Facet path | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Unique Points | 52.043 ms | 34.350 ms | 1.52x | 99.604 / 99.774 MB | `52116703184864747` |
| pre normals + unit + Unique Points + reverse | 73.123 ms | 52.962 ms | 1.38x | 142.830 / 143.012 MB | `216472004485794575` |
| alternating primitive group, Unique Points | 47.401 ms | 30.639 ms | 1.55x | 76.532 / 76.688 MB | `862782961673215783` |
| alternating primitive group, pre normals + unit + Unique Points + reverse | 64.417 ms | 49.821 ms | 1.29x | 112.180 / 112.343 MB | `4403351474312899621` |
| Orient Polygons, 400,000 alternating faces | 31.647 ms | 27.683 ms | 1.14x | 26.404 / 26.451 MB | `2365675254808124655` |
| Cusp Polygons, displaced 1,200,000-corner grid | 70.565 ms | 52.022 ms | 1.36x | 84.414 / 84.506 MB | `283124930776590793` |
| Remove Inline Points, 1,200,000 corners + point IDs | 74.776 ms | 46.167 ms | 1.62x | 91.604 / 91.720 MB | `293960505550144756` |
| alternating primitive group, Remove Inline Points | 67.965 ms | 42.688 ms | 1.59x | 102.831 / 102.953 MB | `4428373719769560180` |
| Make Planar, 200,000 warped quads / 800,000 points | 43.070 ms | 29.224 ms | 1.47x | 53.202 / 53.227 MB | `3434920207817674627` |
| alternating primitive group, Make Planar | 31.721 ms | 23.412 ms | 1.35x | 53.228 / 53.254 MB | `348575385667556423` |
| point selection promotion + Unique Points | 42.560 ms | 28.097 ms | 1.51x | 69.458 / 69.607 MB | `214444916378444802` |
| vertex selection promotion + Unique Points | 40.981 ms | 27.653 ms | 1.48x | 69.368 / 69.511 MB | `4122771134891582778` |
| native-edge selection promotion + Unique Points | 42.961 ms | 28.552 ms | 1.50x | 70.411 / 70.554 MB | `3776704403672471336` |
| Consolidate point `N`, 1,200,000 paired points | 462.919 ms | 457.562 ms | 1.01x | 139.159 / 139.231 MB | `885417337606853454` |

_Continues "Orient Polygons is O(vertices + unique edges +…" in performance.md:_
The first correct version unconditionally built a second complete topology
index for edge-group remapping, even when no edge groups existed. It measured
128.615/122.339 ms and allocated 221.681/221.748 MB. Deferring that target
index and identity point map until an edge group exists produced the final row
without changing hash, a 4.58x one-domain time reduction and 8.40x allocation
reduction.

_Continues "Primitive-restricted Unique Points is O(points + vertices +…" in performance.md:_
In the same development-
profile tuning run, the first correct grouped pre-normal + Unique Points +
reverse implementation measured 222.190/196.095 ms and allocated
379.961/380.132 MB at one/four domains; the compact-mask version measured
69.241/48.120 ms and 112.181/112.375 MB, with hashes unchanged. Isolated
grouped Unique Points fell from 144.071 ms and 269.600 MB to 45.589 ms and
76.532 MB at one domain. The table records separate final release-profile
measurements.

_Continues "Typed Facet point and vertex promotion is O(vertices…" in performance.md:_
The measured point/vertex half-range and sparse-edge selections include this
conversion cost, promote zero bytes, and produce identical ordered output at
one and four domains.

_Continues "Remove Inline Points is O(points + corners +…" in performance.md:_
It measured 118.619/62.570 ms and allocated
219.604/130.575 MB at one/four domains. Explicit unboxed comparisons and direct
neighbor enqueue paths produced the final row with the same hash: 1.57x/1.42x
faster and 2.40x/1.42x lower allocation.

_Continues "Consolidate Normals is O(points + neighboring candidates +…" in performance.md:_
The measured regular-pair fixture is
discovery-bound, so four domains do not provide a material speedup. Reusing
the clustering cell planes for cluster IDs, sizes, and CSR cursors reduced the
first correct implementation from 564.021/549.351 ms and 283.159/283.240 MB to
the final row, with the exact hash unchanged: 1.22x/1.20x faster and 2.03x lower
allocation.

_Continues "Make Planar is O(points + corners + primitives…" in performance.md:_
The measured disjoint-quad fixture needs no conflict copies, allocates
only its exact position and per-corner projection/state planes, promotes zero
bytes, and retains the same hash at one and four domains.

_Continues "Every final path promoted zero bytes. The isolated…" in performance.md:_
The isolated five-repeat four-domain
process peaked at 472,664 KiB RSS. Measurements used OCaml 5.3.0, Dune 3.24.0,
release profile, grain 16,384, and Linux 6.8/aarch64 on four cores.

```sh
RAYS_RDK_OPS_FILTER=facet RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use /usr/bin/time -v for process RSS.
```

_Continues "The million-point polygon Circle source replaces its former…" in performance.md:_
The
compatible closed-circle hash remains `1595635405635298122`; release medians
fell from 92.75/88.49 ms to 22.94/13.21 ms at one/four domains, while allocation
fell from 112.23 MB to 32.08 MB. Open, chord-closed, and sliced ellipse modes use
the same O(points) kernel and stable domain-independent ordering.

_Continues "The production Box generator derives every cardinality before…" in performance.md:_
On the same OCaml 5.3.0/Linux aarch64
four-core host, five-run release medians at grain 16,384 are 28.469/19.493 ms
for 523,606 face-local points and 1,040,000 triangles, 9.142/4.242 ms for
520,002 welded surface points with smooth incident-face normals,
50.498/32.698 ms for the same points and 520,000 UV/grouped quads with hard
vertex normals, and 8.939/3.592 ms for a 1,030,301-point volume lattice.
One-domain allocation is 59.484/24.989/117.422/24.741 MB, effectively the exact
published payload; the first correct triangle/quad/lattice implementation used
284.592/379.480/156.123 MB. Complete geometry hashes match across one/four
domains. The 10,000 legacy-box batch also preserves its prior hash while
reducing allocation 49.2%; its tiny boxes intentionally bypass parallel
dispatch.

_Continues "UV Sphere precomputes O(segments+rings) trigonometric tables, fills positions…" in performance.md:_
Its compatible million-point/two-million-
triangle fixture retains exact hash `1383169697053155230` and improves from
87.170/47.487 ms to 66.733/40.679 ms on one/four domains. Allocation remains
the 114.0 MB packed output plus 42 KB of bounded tables/control state.

Advanced five-run release fixtures at grain 16,384 take 86.883/55.808 ms and
165.079 MB for a 502,000-point alternating transformed ellipsoid with three
million vertex-normal/UV corners; 35.423/21.739 ms and 76.633 MB for 500,002
point-normal/UV points and 501,000 logical-pole quads; 52.622/31.680 ms and
120.259 MB for a million-point row/column surface with vertex normals/UVs; and
27.875/16.235 ms and 64.300 MB for 1,004,000 unique points with point normals/
UVs. These allocations are the exact published planes plus bounded tables,
and complete hashes match across domain counts. The isolated four-domain
five-fixture process peaked at 173,640 KiB RSS.

_Continues "Torus precomputes O(rows+columns) trigonometric and normalized-parameter tables, fills…" in performance.md:_
A sequential reference
for the compatible million-point/two-million-triangle result repeated
trigonometry per coordinate and took 174.728/182.901 ms on one/four domains,
allocated 210.002 MB, and produced hash `3747492228246284738`. The production
kernel produces the identical hash in 57.928/38.153 ms while allocating
114.085 MB, effectively its 114.049 MB published payload.

Advanced five-run release fixtures at grain 16,384 take 56.990/39.013 ms and
112.568 MB for 500,000 UV quads with transformed vertex normals;
72.703/50.931 ms and 164.960 MB for a 500,000-point signed partial sweep with
alternating triangles, U/V caps, vertex normals, and UVs; 45.638/28.880 ms and
120.103 MB for a million-point combined row/column surface; and
24.623/15.957 ms and 64.084 MB for one million points with point normals/UVs.
Complete geometry hashes match across one/four domains. The isolated
three-repeat four-domain process peaked at 173,548 KiB including all fixtures,
hashing, Dune, and the OCaml heap.

_Continues "Revolve plans compact axis poles and stable per-profile-edge…" in performance.md:_
A 10,001-corner profile with axis endpoints and
64 angular divisions produces 639,938 points, 1,279,872 alternating triangles,
3,839,616 topology corners, and exact hash `2694885502838977775`. Five-run
release medians at grain 16,384 are 77.592/52.718 ms on one/four domains
(1.47x); measured allocation is 260.572/197.300 MB and major allocation is
177.057/177.074 MB. The required packed arrays dominate both time and memory;
stable edge-range scheduling lets one long profile use all domains instead of
scheduling only by curve.

The full-payload quad fixture additionally remaps point/vertex fields, an
ordinary point group, all native profile edges, and a cap group. Its
3,839,810-element cardinality has exact hash `2198035961325029752` and takes
287.121/271.273 ms; cached unique-edge topology construction and target-edge
classification dominate that row, so it is intentionally not presented as a
strongly scaling kernel. Measured allocation is 674.877/592.850 MB. Isolated
one/four-domain processes containing both rows peaked at 493,500/504,776 KiB.
Reproduce with `RAYS_RDK_OPS_FILTER=revolve
RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 dune exec --profile release
tools/bench_rdk_ops.exe`, then repeat with four domains.

On the same four-core OCaml 5.3.0/Linux aarch64 host, five-run release medians
at grain 16,384 are 64.933/43.582 ms and 152.972 MB for a million-point open
quad tube; 53.969/29.205 ms and 112.578 MB for a 500,000-point capped frustum;
67.520/48.129 ms and 164.985 MB for a 499,501-point capped shared-apex cone;
43.058/23.640 ms and 120.079 MB for a million-point combined row/column output;
and 23.290/17.983 ms and 64.060 MB for one million free points. Allocations are
the exact published planes plus bounded tables/control state, and complete
geometry hashes match across one/four domains. The prior general Sweep-based
million-point cylinder path took 65.925/64.522 ms and allocated 201.021 MB;
the dedicated Tube kernel therefore preserves one-domain latency while cutting
allocation by 23.9% and making the four-domain path 1.48x faster. The final
three-repeat four-domain process peaked at 173,652 KiB including all fixtures,
hashing, Dune, and the OCaml heap.

_Continues "Platonic Solids keeps normalized canonical point, face, and…" in performance.md:_
A 100,000-call icosahedron batch
(1.2 million generated points) improved from the former boxed-coordinate plus
Topology.Builder reference at 83.603 ms and 696.800 MB to 23.459 ms and
266.400 MB, retaining exact hash `108589944924191245`. A 20,000-call transformed
soccer-ball batch with hard vertex normals, black/white primitive color, and
face groups took 49.815 ms and 292.640 MB, hash `4440798644007023453`. Complete
geometry remains identical when the surrounding sketch uses one or four
domains; no misleading per-solid parallel path is created. The final
three-repeat one-domain process peaked at 54,496 KiB including Dune and the
OCaml heap.

On the same host, five-run release medians at grain 16,384 are 42.837/30.393 ms
and 80.006 MB for a compatible 1,000,001-point equal-angle curve;
321.491/113.081 ms and 50.007 MB for four phase-distributed equal-arc curves
totalling 1,000,004 points; and 375.826/147.731 ms and 170.017 MB when the
latter also publishes angle, X/Y/tangent, quaternion orientation, and distance.
Complete hashes match across domain counts. The output-equivalent boxed tuple
plus generic Polyline baseline took 107.229 ms and allocated 128.003 MB, so the
dedicated compatible path is 2.50x faster and allocates 37.5% less. The
three-repeat four-domain advanced process peaked at 178,856 KiB including both
fixtures, hashing, Dune, and the OCaml heap.

_Continues "Attribute Promote materializes at most one packed incidence…" in performance.md:_
Upper median uses three-way introspective selection rather than a
full sort; its million-point detail fixture improved from 424.5 ms to 28.3 ms
with the same 8.02 MB allocation and exact hash `1214810429822179029`. Large
integer mode uses a bounded dense histogram when the observed range justifies
it, improving the same-size fixture from 430.0 ms to 12.14 ms and exact hash
`1214810429822179047`. A single detail reduction cannot expose independent
output ranges, so its one/four-domain times are intentionally equal.

_Continues "Piece promotion assigns deterministic integer/text partitions, constructs one…" in performance.md:_
The 1,002,001-point fixture with 64-point integer pieces improved
from the first packed implementation's 228.4 ms/83.9 MB to 142.3 ms/34.1 MB
on one domain and 52.62 ms/33.0 MB on four, with exact hash
`3372359779053422621`. The five-repeat four-domain harness peaked at 1,229,704
KiB RSS including its retained million-point/two-million-triangle source,
hashing, Dune, and high-water heaps.

_Continues "Plural pattern promotion builds that topology/piece plan once…" in performance.md:_
On a 400x400 grid (160,801 points, 320,000
primitives), promoting and renaming four float point attributes to 5,000
integer-partitioned primitive pieces with Average and grain 2,048 took
41.517/40.050 ms on one/four domains, allocated 52.382/38.597 MB, and produced
cardinality 1,440,801 with exact hash `1347528973856259256`. Four repeated
renamed singular promotions took 137.069/134.585 ms and allocated
115.878/102.127 MB for the identical result. An isolated three-repeat
four-domain shared-plan process peaked at 70,860 KiB RSS.

_Continues "The optional scalar source-index output is fused into…" in performance.md:_
On the same fixture with Maximum, shared promotion without indices took
43.513/37.762 ms and allocated 52.382/38.095 MB. Four value/index pairs took
53.231/43.090 ms and allocated 62.470/49.179 MB, including 10.24 MB of required
index payload, with exact hash `3924845448660289621` across domain counts.
Repeating four singular indexed promotions took 145.357/146.119 ms and
allocated 125.960/112.960 MB for that identical hash. The isolated
three-repeat four-domain indexed process peaked at 81,144 KiB RSS.

_Continues "The production extension keeps tuple provenance shape instead…" in performance.md:_
Text/index
Average uses upper median, Sum concatenates incidence-order bytes, and other
numeric methods use First, matching the documented SideFX policy. Sum performs
a checked byte-count pass followed by one exact string allocation per output;
it does not build per-incidence lists. Five-run release medians on the same
fixture were:

| Attribute Promote path | 1 domain | 4 domains | Allocation (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|
| four float fields + scalar source indices | 57.254 ms | 48.055 ms | 62.474 / 49.269 MB | `1588512353231422235` |
| float4 + four component source indices | 63.397 ms | 53.747 ms | 75.251 / 62.118 MB | `1105309542113901142` |
| text Sum concatenation | 18.448 ms | 7.823 ms | 7.682 / 4.196 MB | `150614732931925070` |

The full geometry hashes agree exactly between domain counts. Single-repeat
processes peaked at 101,376/107,008 KiB RSS for tuple indexing and
55,168/57,728 KiB for text Sum on one/four domains, including the retained
source, hashing, runtime, and harness. Tuple indexing is O(incidences × width)
time with exact O(destinations × width) index output for width at most four.
Text Sum is O(total contributing bytes + incidences) time with required output
strings and O(destinations) length/offset scratch. Both write only disjoint
destination ranges in parallel.

```sh
RAYS_RDK_OPS_FILTER=attribute_promote RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_promote RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_promote_pattern \
RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
RAYS_BENCH_DOMAINS=1 dune exec tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_promote_pattern \
RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
RAYS_BENCH_DOMAINS=4 dune exec tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_promote_pattern_tuple4_indexed_shared \
RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_promote_pattern_text_sum \
RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
```

_Continues "Attribute Blur reuses the topology cache, precomputes optional…" in performance.md:_
Inlining the optional alpha read reduced
the controlled edge fixture from 886.707/274.847 MB allocated on one/four
domains to 30.842/30.866 MB and improved time from 520.786/180.919 ms to
310.318/113.101 ms without changing its then-current hash. Parallel robust
`hypot` edge-metric construction subsequently removed another temporary
7.69 MB and rejects overflowing finite-coordinate differences explicitly.

The release fixture is a 400×400 displaced grid (160,801 points, 320,000
triangles), blurring seven planes (`P` plus `Cd`) for eight iterations at grain
16,384. Uniform connectivity took 179.435/65.915 ms and allocated
19.303/19.330 MB on one/four domains, exact hash
`2662508781939203769`. Inverse-edge-length blur with receiver weights, neighbor
alpha, border pins, and alternating 0.42/-0.44 steps took 314.804/115.240 ms,
allocated 23.150/23.183 MB, and produced exact hash
`239593742033655225`. Major allocation is the required two plane sets plus the
optional packed edge metric; no allocation is proportional to neighbor visits.
The isolated four-domain five-repeat process peaked at 161,308 KiB RSS,
including source and output geometry, topology cache, benchmark hashing, Dune,
and OCaml heap.

```sh
RAYS_RDK_OPS_FILTER=attribute_blur RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_blur RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

_Continues "Attribute Randomize validates/unpacks tuple parameters once, allocates exact…" in performance.md:_
The first correct implementation mixed boxed `int64` values
per sample: the million-point Float4 uniform fixture took 49.696 ms and
allocated 577.155 MB on one domain; normal add with an integer seed attribute
took 208.356 ms and 1,122.244 MB. Moving the indexed mix to immediate native
integers removed allocation proportional to samples without changing the
parallel contract. After adding geometric/custom distributions, retaining a
specialized uniform fill avoided regressing that core path: the final release
results are 30.988/14.525 ms for uniform Float4 and 179.523/58.106 ms for
normal Float4 seed-attribute add on one/four domains. Both allocate
32.067–32.082 MB, the four exact output planes plus small bounded control
storage. Their exact hashes remain respectively `1881595126018569963` and
`1209931956113404212` across domain counts.

The same 1,002,001-point release fixture measures the expanded modes as
follows. Every allocation is the exact output planes plus bounded compiled
distribution/range state; knot/value tables are stored once and there is no
allocation per element, component, sample attempt, or lookup step.

| Attribute Randomize mode | 1 domain | 4 domains | Allocated (4d) | Exact hash |
|---|---:|---:|---:|---:|
| full unit quaternion orientation | 85.385 ms | 30.131 ms | 32.082 MB | 2262254114551114909 |
| 3D unit direction in a 60-degree cone | 103.330 ms | 33.923 ms | 24.065 MB | 4472510635812361783 |
| uniform 3D sphere volume | 65.687 ms | 23.666 ms | 24.064 MB | 995450211601657671 |
| 3D sphere volume, hemisphere cone + 1.5 bias | 140.719 ms | 44.590 ms | 24.065 MB | 1518083225360384198 |
| four weighted discrete Float4 tuples | 40.699 ms | 17.226 ms | 32.082 MB | 3296396949259280514 |
| Float4 fraction attribute through four-knot inverse CDF | 48.449 ms | 19.946 ms | 32.082 MB | 1218457001365439679 |

_Continues "The uniform-volume regression independently checks centered first moments…" in performance.md:_
Fraction tests cover exact endpoints,
weighted boundaries, seed independence, inverse-normal median/tails, malformed
dimensions, and non-finite endpoint rejection.

The 2026-08-03 production extension added raw-sample tail limits,
rotationally-symmetric multivariate Cauchy, weighted text choices, and typed
cross-owner group expansion. On the same 1,002,001-point/two-million-triangle
fixture at grain 2,048, five-run release medians were:

| Extended Attribute Randomize mode | 1 domain | 4 domains | Allocation (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|
| bounded isotropic Cauchy float2 | 143.344 ms | 44.981 ms | 16.060 / 16.142 MB | `1501789240569983406` |
| three weighted primitive text choices | 51.980 ms | 20.369 ms | 16.010 / 16.243 MB | `4093209938784027843` |
| sparse point group expanded to vertex scalar | 67.172 ms | 27.125 ms | 48.894 / 49.943 MB | `2990064052650292689` |
| bounded normal float4 from fraction float4 | 55.894 ms | 21.232 ms | 32.091 / 32.173 MB | `1793519179073514430` |

All hashes agree exactly across domain counts and every final run promoted zero
bytes. Cauchy random sampling is O(elements × dimensions) time and exact tuple
output; its shared denominator produces a multivariate Student-t distribution
with one degree of freedom. Text selection is O(elements × log choices) and
stores one required pointer per destination while sharing the immutable choice
strings. Limits add one component-wise clamp before global scale without
altering the specialized unlimited-uniform path.

The first correct cross-owner prototype reused the general full half-edge
promotion index even for point-to-vertex incidence. A cold four-domain process
took 576.546 ms, allocated 984.633 MB, and peaked at 1,008,476 KiB RSS. The
final shared `Element_selection` kernel maps point-to-vertex membership directly
through the packed corner point plane; point/primitive ordinary conversions use
direct corner scans or the lightweight point-incidence index, and reserve the
full topology index for native-edge sources. The same cold case now takes
25.633 ms, allocates 49.882 MB, and peaks at 246,144 KiB RSS: 22.49x faster,
94.9% less allocation, and 75.6% lower peak RSS with the identical hash.
Single-repeat four-domain Cauchy, text, and bounded-normal processes peaked at
211,328, 211,712, and 226,816 KiB respectively, including all retained source
fixtures, hashing, runtime, and harness state.

```sh
RAYS_RDK_OPS_FILTER=attribute_randomize_cauchy2_bounded \
RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_randomize_text_discrete \
RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_randomize_point_to_vertex_group \
RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
```

Attribute Remap explicit Float4 takes 30.621/13.720 ms and allocates
32.068–32.082 MB. Automatic component range plus a four-knot ramp initially
boxed one float result per component sample, taking 69.505 ms and allocating
159.856 MB on one domain. Inlining the ramp sampler reduced it to
61.006/25.008 ms and 32.072–32.100 MB, with exact hash
`131537071345660268`; explicit remap's exact hash is
`1549552374393416782`. These fixtures contain 1,002,001 points at grain 16,384,
use five medians under the release profile, OCaml 5.3.0/Dune 3.24.0, and the
four-core Linux 6.8 aarch64 runner. The expanded isolated four-domain,
five-repeat orientation process peaked at 223,048 KiB RSS, including the
million-point topology, all source/fraction fixtures, benchmark hashing, Dune,
and the OCaml heap. The earlier isolated Remap process peaked at 191,508 KiB.

```sh
RAYS_RDK_OPS_FILTER=attribute_randomize RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_randomize RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_remap RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_remap RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

_Continues "Peak, Mountain, and topology-preserving normal generation share packed…" in performance.md:_
A first correct Peak loop boxed
per-point change tracking and polymorphic maximum operations, allocating about
72.1 MB for the million-point point-normal fixture; immediate range flags and
an inlined scalar maximum reduce the final path to 24.05--24.06 MB, exactly the
three copied position planes plus bounded range state. The first Mountain fBm
path reused the public closure/recursive helper and allocated about 529 MB on
one domain. One four-scalar scratch array per worker range removes allocation
per sample and octave; with signed height output the final path allocates
32.13--32.15 MB, the three positions and one height plane.

The release fixture has 1,002,001 points, 2,000,000 triangles, grain 16,384,
and five medians. Peak with point `N` and a point mask takes 14.771/10.552 ms
on one/four domains and has exact hash `3517429522847750887`. Six-octave
Mountain with point `N`, a mask, and height output takes 296.311/96.579 ms,
allocates 32.134/32.146 MB, and has exact hash `2870047288594138134`.
Topology-preserving geometric normals take 68.145/50.450 ms, allocate
72.051/72.087 MB, and retain exact hash `3253461948889680712`.

_Continues "Point Jitter uses the same indexed component stream…" in performance.md:_
The first correct implementation allocated a three-sample closure per point:
it took 31.247 ms and allocated 112.227 MB on one domain. Inlining the three
scalar samples removes that hot-loop allocation. The final uniform path takes
16.364/11.729 ms on one/four domains, allocates 24.051/24.064 MB, and exactly
matches the baseline hash `4306816342677270420`. The point-group + mask +
stable-ID + `pscale` fixture takes 17.303/10.745 ms, allocates
24.052/24.065 MB, and has exact hash `1943467239589564005`. These are five-run
release medians on the same 1,002,001-point fixture; the matching hashes across
domain counts are regression requirements, not timing assumptions.

```sh
RAYS_RDK_OPS_FILTER=point_jitter RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=point_jitter RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

Edge Divide is measured on a 300x250 quad grid with 75,551 points, point and
vertex payload, an ordinary point group, every native edge selected, four
resulting segments per edge, and grain 16,384. The first correct implementation
eagerly built discrete representative maps even when only numeric fields used
interpolation, and allocated a reference for each ancestry callback. It took
228.278/190.182 ms and allocated 345.146/345.263 MB in shared mode, and
381.184/288.924 ms with 475.597/475.764 MB in unique mode. Lazy discrete maps
and direct ancestry writes reduce the five-run release medians to
213.315/174.362 ms with 327.111/327.227 MB for shared points and
355.683/272.077 ms with 450.388/450.563 MB for unique points. Promoted bytes
are 1,320/2,672 and 1,352/2,704 respectively; major allocations are
298.124/298.125 MB and 392.633/392.634 MB. Shared mode's output-cardinality
checksum is 1,802,201 with exact hash `23138927581944883`; unique mode's is
2,250,551 with exact hash `430669910521685374`, unchanged across one and four
domains. The remaining bottleneck is the sequential target reverse-topology
index plus unavoidable output construction; disjoint planning and fill ranges
provide 1.22x and 1.31x four-domain speedups without changing ordering.

```sh
RAYS_RDK_OPS_FILTER=edge_divide RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=edge_divide RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "Edge Collapse uses a 500x400 quad grid with…" in performance.md:_
The
first correct composition installed a temporary integer destination field and
sent already-known component links through Fuse's public specified-target
planner. It measured 190.775/179.255 ms and allocated 351.884/336.529 MB on
one/four domains. Directly materializing the packed cluster layout consumed by
the same authoritative Fuse reduction/cleanup kernels removes that duplicate
planning pass. The final five-run release medians are 184.098/165.430 ms,
allocations are 345.804/329.913 MB, promoted bytes are 3,488/17,472, and major
allocations are 272.044/272.058 MB. Output cardinality checksum 1,050,776 and
hash `3813930426841543590` are exact across domain counts. The 1.11x
four-domain speedup is intentionally modest: deterministic union/find is
sequential and the measured path performs output-heavy Fuse cleanup and stable
shared-corner normal accumulation; disjoint packed payload and normal ranges
remain parallel.

```sh
RAYS_RDK_OPS_FILTER=edge_collapse RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=edge_collapse RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "PolyReduce uses a 420x320 alternating-triangle grid (134,400 points…" in performance.md:_
The
first correct adaptive implementation recomputed each incident face plane for
every point and allocated new quadric/validation planes every round. Single-run
release baselines were 1.403/1.312 s on one/four domains with 2.043/1.752 GB
allocated. This pre-normalization baseline used hash
`2819317508756127229`; the final scale-normalized metric intentionally changes
cost ties while remaining exact across domain counts.

_Continues "Precomputing each normalized face plane once per round…" in performance.md:_
Final five-run
release medians are 1.304/1.237 s, allocations are 1.486/1.487 GB, promoted
bytes are 39,832/66,560, and major allocations are 1.134/1.134 GB. Output
cardinality checksum 481,915 and hash `386166488769867098` are exact across
domains. A four-domain `/usr/bin/time -v` run reported 786,748 KiB maximum RSS. The modest
1.06x speedup is honest: plane/quadric and cost formation are parallel, while
global deterministic cost sorting, conflict selection, and seven topology
rebuilds dominate this medium fixture.

_Continues "The original-position variant disables boundary locking and contracts…" in performance.md:_
Its final medians are 1.054/1.001 s with
1.238/1.239 GB allocated, 34,992/50,272 promoted bytes, 909.198/909.213 MB major
allocation, checksum 481,604, and exact hash `3508621272046085748`. These rows
are a production regression baseline, not a claim that adaptive reduction is
allocation-free: a future mutable half-edge priority implementation must beat
both wall time and peak memory while preserving the exact ancestry and
topology-validity matrix.

```sh
RAYS_RDK_OPS_FILTER=poly_reduce RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=poly_reduce RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "Remesh uses the same 420x320 alternating-triangle grid as…" in performance.md:_
The first correct composition called
Edge Divide and general polygon Triangulate as separate immutable snapshots;
the complete projected/diagnostic iteration took 2.167/1.752 s and allocated
1.683/1.576 GB on one/four domains, with about 1.089 GB of major allocation.

Final three-run release medians are:

| Remesh case | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|---:|
| topology iteration + payload | 1.203 s | 1.168 s | 1.03x | 992.827/981.148 MB | 614.189/614.205 MB | 2,021,194 | `2656701640125162895` |
| uniform split/collapse/flip/relax/project + diagnostics | 1.725 s | 1.432 s | 1.20x | 1,145.720/1,092.176 MB | 705.532/705.562 MB | 2,021,194 | `3314318891784832281` |
| three input-point-only relax/project iterations | 1.052 s | 0.601 s | 1.75x | 266.605/210.375 MB | 96.051/96.073 MB | 1,203,688 | `2950596785166156986` |
| triangulate + diagnostics, zero iterations | 39.529 ms | 21.957 ms | 1.80x | 19.664/16.824 MB | 15.379/15.378 MB | 1,203,688 | `4132628764464781101` |

Promoted allocation remains below 72 KiB. One filtered four-domain process
running all four cases peaked at 811,220 KiB RSS, including source/output
geometry, cached topology/BVH data, benchmark hashing, Dune, and the OCaml
heap. Exact hashes include complete ordered topology, every attribute storage,
ordinary/ordered groups, and native-edge groups. Topology phases remain
serially dependent and immutable output construction dominates the full
iteration; parallelism is reserved for disjoint metric, payload, relaxation,
projection, normal, and diagnostic ranges. These are production regression
baselines, not an allocation-free claim.

Measurements use OCaml 5.3.0, Dune 3.24.0, release profile, grain 16,384,
Linux 6.8/aarch64, and four available single-threaded cores. Reproduce with:

```sh
RAYS_RDK_OPS_FILTER=remesh RAYS_RDK_OPS_REPEATS=3 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=remesh RAYS_RDK_OPS_REPEATS=3 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

Boolean Detect is measured on two 240x180 alternating-triangle grids with
86,400 total input points. The crossing case rotates the collision plane and
keeps the candidate set sparse. The dense case translates a coplanar grid by a
fraction of one cell; its broad phase emits 681,156 stable triangle pairs and
stresses projection, narrow-phase classification, deduplication, and packed
ragged output.

The first correct dense path passed triangle coordinates through boxed float
arguments and created local projection/bounds closures for every candidate. It
took 533.151/495.343 ms on one/four domains and allocated
1,024.703/316.682 MB. Range-local 31-float predicate scratch, scalar projected
coordinates, local-frame normalization, and closure-free triangle bounds cut
that allocation without changing output. Final three-run release medians are:

| Boolean Detect case | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|---:|
| crossing grids | 111.482 ms | 76.656 ms | 1.45x | 61.466/44.197 MB | 34.052/34.056 MB | 385,448 | `3871848927355614594` |
| coplanar BVH pair discovery only | 161.633 ms | 74.080 ms | 2.18x | 15.014/13.442 MB | 12.269/12.268 MB | 1,362,312 | `929945351985697603` |
| shifted coplanar full detection | 373.631 ms | 186.484 ms | 2.00x | 79.886/62.610 MB | 52.474/52.479 MB | 385,448 | `1176532439785754640` |
| unordered AxA broad phase | 472.891 ms | 203.883 ms | 2.32x | 31.387/27.716 MB | 25.898/25.896 MB | 2,894,796 | `3807041689991949821` |
| self-crossing AxA full detection | 927.607 ms | 447.480 ms | 2.07x | 101.260/72.444 MB | 62.834/62.844 MB | 770,896 | `3036107863331873987` |

The dense full path reduced allocation by 92.2% on one domain and 80.2% on
four domains relative to the initial implementation. Promoted allocation is
below 9 KiB. Candidate output is grouped by source triangle, and every
parallel pass writes disjoint byte or index ranges; exact geometry and metadata
hashes match across domain counts. The crossing one-domain timing remained
within benchmark noise while allocation fell from 71.701 MB; the measured gain
is the dense-case allocation removal and multicore scaling, not a blanket
single-domain speed claim.

The AxA fixture merges the crossing grids into one immutable geometry. Its
surface index contains both layers; the broad phase emits 1,447,398 unordered
candidate pairs after discarding reverse duplicates and pairs from one source
primitive. Narrow ranges mark shared source point IDs without allocation,
suppress topology-only contacts, and write both directions of retained
primitive pairs into disjoint exact-size rows. This is why AxA retains a 2.07x
four-domain speedup while producing symmetric lists and the same complete hash.

Measurements use OCaml 5.3.0, Dune 3.24.0, release profile, grain 16,384,
Linux 6.8/aarch64, and four physical cores. Reproduce with:

```sh
RAYS_RDK_OPS_FILTER=boolean_detect RAYS_RDK_OPS_COLUMNS=240 \
RAYS_RDK_OPS_ROWS=180 RAYS_RDK_OPS_REPEATS=3 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=boolean_detect RAYS_RDK_OPS_COLUMNS=240 \
RAYS_RDK_OPS_ROWS=180 RAYS_RDK_OPS_REPEATS=3 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "Intersection Analysis measures point/provenance materialization in addition to…" in performance.md:_
Sparse AxB uses two 420x320 grids (268,800
input points), AxA uses two merged 220x160 grids (70,400 points), and the
deliberately dense coplanar fixture uses two shifted 120x90 grids (21,600
points). The curve fixture intersects the 260 row curves of a 360x260 grid
with its 360 column curves: 187,200 input points and 93,600 welded events.
Release-profile five-run medians are:

| Intersection Analysis case | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|---:|
| sparse crossing AxB | 314.793 ms | 191.873 ms | 1.64x | 117.265/111.005 MB | 107.709/107.512 MB | 839 | `2898994521382688982` |
| self-crossing AxA | 578.240 ms | 302.497 ms | 1.91x | 72.940/69.723 MB | 67.678/67.678 MB | 439 | `706826492999258979` |
| shifted coplanar AxB | 352.034 ms | 299.134 ms | 1.18x | 249.491/248.969 MB | 132.445/132.446 MB | 95,080 | `1163995571016836003` |
| row/column curve AxB | 441.228 ms | 325.056 ms | 1.36x | 328.022/269.032 MB | 127.182/127.203 MB | 93,600 | `1475970007679107439` |

The first correct coplanar implementation allocated edge tables and local
coordinate closures per triangle candidate. On the 80x60 development fixture
it allocated 189.870 MB and took 223.845 ms. Fixed edge calls, explicit packed
loads, and inlined scratch helpers reduced that to 116.388 MB and 194.868 ms
without changing the complete geometry hash. Major allocation in the final
dense row is exact candidate/event/provenance payload rather than promoted
candidate-local garbage; promoted allocation remains below 4 KiB.

_Continues "Sparse and self modes scale through BVH and…" in performance.md:_
Dense coplanar output is limited by stable serial spatial welding and
first-incidence provenance aggregation; the 1.18x result is a remaining
parallelization target, not linear multicore scaling. Reproduce a row by
selecting its prefix, for example:

```sh
RAYS_RDK_OPS_FILTER=intersection_analysis_crossing \
RAYS_RDK_OPS_COLUMNS=420 RAYS_RDK_OPS_ROWS=320 \
RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=4 \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "The mixed index replaces the former triangle-only traversal…" in performance.md:_
Its first correct bounds reduction used
generic `Float.min`/`Float.max` calls at every BVH level and measured about
389/221 ms for the sparse row on one/four domains. Direct comparisons in that
hot reduction lowered the final medians to 315/192 ms. Against the preceding
triangle-only recorded baseline, sparse time improved 2.8%/1.3%, self time
improved 19.3%/13.4%, dense coplanar time remained within 0.4%, and all exact
hashes stayed unchanged. Total allocation fell in every triangle fixture;
the mixed index retains explicit piece bounds, so sparse major live bytes rose
while total allocated bytes fell.

The first correct implementation built and retained a complete reverse CSR
topology for the output solely to recover native edge ancestry. In the Dune
dev profile it measured 217.392 ms for chamfer and 679.733 ms for divided
round, allocating 433.521 MB and 1,442.173 MB. Replacing that structure with
the shared lightweight output edge lookup reduced those medians to 165.778 ms
and 481.567 ms, reductions of 23.7% and 29.2%; divided-round allocation fell
22.0%, and its major allocation fell 41.9%. The production kernel retains only
the hash table needed for endpoint-to-edge lookup and sizes profile alias
storage to divided profile points rather than the complete output.

Final five-run release medians are:

| PolyBevel case | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| all-edge chamfer | 165.844 ms | 143.184 ms | 1.16x | 338.320/272.960 MB | 135.755/135.771 MB | `2049759455396905631` |
| divided round + payload | 492.517 ms | 404.717 ms | 1.22x | 1,130.972/785.510 MB | 395.606/395.665 MB | `2436967923713080982` |

Promoted allocation stayed below 21 KiB. A filtered four-domain divided-round
process peaked at 444,656 KiB RSS. Exact hashes and complete ordered geometry
are identical across domain counts. The speedup remains output-bound because
edge eligibility, topological fan decisions, and deterministic corner
junction planning are sequential; position/profile, face, payload, group,
normal, and edge-bit fills use disjoint reusable-pool ranges. Measurements use
OCaml 5.3.0, Dune 3.24.0, Linux 6.8/aarch64, four cores, and grain 16,384.

```sh
RAYS_RDK_OPS_FILTER=poly_bevel RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=poly_bevel RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "Point Split uses a 500x400 quad grid with…" in performance.md:_
The fixture carries a point integer ID, vertex float2 UV
and corner ID, primitive material ID, an alternating point group, a primitive
seam group, and a native group containing every source edge. Unique mode emits
one point per selected corner. The group-only case emits a 1,401,048-element
cardinality checksum; attribute-only and mixed attribute/group cases emit
1,800,000, with matched attributes promoted to points in the latter two.

The first correct development-profile path constructed a complete target
`Topology_index` only to map output native-edge groups. Unique/seam medians were
170.465/230.764 ms, allocations 328.421/440.366 MB, and major allocations
248.301/267.502 MB on one domain. Replacing that target reverse CSR with the
shared lightweight endpoint lookup, and allocating classification planes only
when the selected mode needs them, reduced development medians to
136.756/210.927 ms. Unique allocation fell 50.7% and major allocation 51.6%;
seam allocation fell 32.0% and major allocation 38.3%.

Final five-run release medians are:

| Point Split case | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| every selected corner unique | 136.469 ms | 111.470 ms | 1.22x | 162.019/136.265 MB | 120.300/120.319 MB | `1759525763580531095` |
| primitive-group seam | 147.550 ms | 102.255 ms | 1.44x | 209.633/142.838 MB | 110.318/110.352 MB | `1376946659531591241` |
| attribute seams + point promotion | 208.331 ms | 146.528 ms | 1.42x | 299.566/206.614 MB | 165.101/165.148 MB | `1955015017167342198` |
| mixed attribute/group seams + promotion | 206.079 ms | 147.869 ms | 1.39x | 299.565/206.589 MB | 165.101/165.147 MB | `1955015017167342198` |

Promoted allocation stayed below 53 KiB. A filtered four-domain seam process
peaked at 301,308 KiB RSS. Complete ordered geometry and hashes are identical
across domain counts. The mixed case has the same output as the attribute-only
case because its attribute tuple is already finer than the added Boolean group
component; the group-only case proves the component materially changes
topology. Per-point seam ordering and output prefix sums preserve stable
topology; classification, packed payload/promotion, and edge-group planes use
disjoint ranges. Measurements use OCaml 5.3.0, Dune 3.24.0, Linux 6.8/aarch64,
four cores, and grain 16,384.

```sh
RAYS_RDK_OPS_FILTER=point_split RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=point_split RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

Point Generate is measured in three cardinality-first cases: a no-input
1,000,000-point origin cloud; 100,000 source points producing 600,000 points;
and the same emission with the 100,000 input points retained. The connected
fixture copies point Float, Int, Float3, and two-value Float-array payload,
copies a detail Text field, writes generated grouping and two integer
provenance fields, and uses a point-float count scale. Its cardinality and
complete geometry hash are exact across domain counts.

The first correct development-profile implementation copied both generated
provenance maps after their last payload read. It measured 21.830/18.085 ms and
56.005/56.073 MB allocated for total emission, and 48.843/32.593 ms with
112.083/85.721 MB for connected payload emission on one/four domains. Directly
transferring those already-owned arrays into no-prefix provenance fields
reduced the same-profile cases to 12.992/9.905 ms and 40.005/40.035 MB, and to
43.450/28.477 ms and 102.483/75.829 MB, respectively. Retained-input mode still
needs prefix-combining provenance arrays and deliberately does not use this
optimization.

Final five-run release medians are:

| Point Generate case | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| 1M origin points | 12.896 ms | 10.224 ms | 1.26x | 40.005/40.032 MB | 40.000/40.000 MB | `2425641456680199725` |
| 100k sources -> 600k, copied fixed/ragged payload | 44.138 ms | 26.210 ms | 1.68x | 102.483/76.094 MB | 64.002/64.017 MB | `3618383094568773800` |
| same payload + retained 100k input prefix | 55.723 ms | 36.920 ms | 1.51x | 128.896/98.597 MB | 84.002/84.022 MB | `1367188153682677381` |

Promoted allocation is at most 24 KiB. Planning is input-linear and output
fills write disjoint stable ranges; ragged payload adds work proportional to
copied values. Measurements use OCaml 5.3.0, Dune 3.24.0, Linux 6.8/aarch64,
four single-threaded cores, and grain 16,384.

```sh
RAYS_RDK_OPS_FILTER=point_generate RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=point_generate RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

The first correct development-profile shape loop returned several boxed float
tuples per point and recomputed radical-inverse values and quasi offsets for
every output. Sphere and quasi/velocity cases measured 118.862/72.202 ms and
138.387/84.115 ms on one/four domains, but allocated 354.501/205.748 MB and
564.101/256.085 MB. Replacing tuples with one unboxed float scratch per stable
range, keeping shape ancestry separate, and precomputing quasi sequences only
to the maximum source count reduced the same-profile allocations to
258.506/173.175 MB and 236.908/170.188 MB. Medians became 119.332/62.969 ms
and 124.979/68.074 ms, with unchanged complete geometry hashes. Required
packed output and the temporary authoritative transform bases now dominate;
there is no per-generated-point scratch allocation.

Final five-run release medians are:

| Point Replicate case | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| sphere + copied payload | 118.115 ms | 71.091 ms | 1.66x | 229.705/168.226 MB | 117.682/117.722 MB | `2137438907517278555` |
| line + copied payload | 87.681 ms | 60.386 ms | 1.45x | 220.105/165.707 MB | 117.680/117.717 MB | `291940364058730326` |
| sphere + inverse-transpose `N` and generic-vector transforms | 176.879 ms | 98.253 ms | 1.80x | 342.666/223.065 MB | 139.698/139.755 MB | `3340732060582328136` |
| quasi sphere + velocity synthesis/stretch | 127.604 ms | 72.485 ms | 1.76x | 232.107/171.161 MB | 120.082/120.121 MB | `28852990969694171` |
| sphere + three-vector four-octave fBm | 577.584 ms | 207.263 ms | 2.79x | 229.769/167.771 MB | 117.686/117.725 MB | `187623304489263081` |

The frame-only median is 14.596/13.598 ms and the emission-only median is
43.904/27.228 ms. Promoted allocation remains below 122 KiB. Complete ordered
positions, attributes, groups, and hashes are identical across domain counts;
the visual fixture is also byte-identical. The transformed-vector path copies
two additional output Float3 planes and performs two deterministic frame
passes; its output-sized storage accounts for the increased major allocation,
and its 1.80x four-domain speedup confirms that those passes use disjoint
ranges without per-output tuple allocation. Measurements use OCaml 5.3.0, Dune
3.24.0, Linux 6.8/aarch64, four single-threaded cores, and grain 16,384.

```sh
RAYS_RDK_OPS_FILTER=point_replicate RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=point_replicate RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

Edge Flip is measured on 50,000 disconnected two-triangle patches (200,000
points and 300,000 corners), selecting exactly one manifold diagonal per patch
and carrying vertex float2 payload plus point and native-edge groups. The first
correct implementation validated each selected pair with a fresh polygon
scratch: its five-run release medians were 68.601/65.149 ms and allocations
117.725/111.460 MB on one/four domains. Reusing one bounded scratch per stable
parallel validation block reduced allocations to 112.531/103.404 MB and final
medians to 67.520/66.982 ms. Promoted bytes are 1,936/8,056 and major
allocations 80.491/80.497 MB. Output cardinality checksum 600,000 and hash
`926999786504064952` are exact across domain counts. Topology-index creation
and complete output/ancestry construction dominate this deliberately small-face
workload; parallel validation and remapping primarily preserve scalability for
larger N-gons without changing connectivity or payload order.

```sh
RAYS_RDK_OPS_FILTER=edge_flip RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=edge_flip RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "Edge Cusp selects every edge of a 300x250…" in performance.md:_
The initial five-run release medians
were 98.686/87.625 ms on one/four domains, with 166.016/166.115 MB allocated.
The ownership audit changed native-edge remapping to receive the already-held
source index explicitly. Re-measurement was 100.711/88.798 ms and
166.016/166.121 MB: no material speed or allocation change, confirming the
bounded weak topology-index cache had already prevented a rebuild. The final
output checksum 1,050,000 and hash `1534610466325191131` are exact across
domain counts. Stable union/find and point numbering remain sequential;
position, topology, point payload/group duplication, edge ancestry, face
normal construction, and normalization use deterministic disjoint ranges.

```sh
RAYS_RDK_OPS_FILTER=edge_cusp RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=edge_cusp RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

_Continues "Edge Straighten measures 100,000 independent three-point bends (300,000…" in performance.md:_
The corrected three-seed baseline measured 34.748/35.643 ms and
allocated 104.727/69.740 MB on one/four domains because candidate float tuples
were boxed per component. In-place candidate selection and convergence exits
reduced this to 21.629/23.723 ms and 27.127/46.253 MB. Batching small component
fits then produced final medians of 21.867/15.674 ms and allocations of
27.127/26.061 MB, with zero promoted bytes and 25.500 MB major allocation on
both domain counts. Output checksum 700,000 and hash `1195252365093812429` are
exact. The final four-domain speedup is 1.40x; deterministic union/member
numbering remains sequential while component fitting and point projection are
parallel.

```sh
RAYS_RDK_OPS_FILTER=edge_straighten RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=edge_straighten RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

## Circle from Edges SOP baseline

The dedicated release benchmark covers two one-million-point extremes: 62,500
independent 16-point closed loops, which expose component fitting to the pool,
and one million-point closed loop, which isolates the serial stable moment
reductions while its disjoint final projection remains parallel. Every loop is
non-circular and slightly non-planar. Results are five-run medians at grain
16,384 on OCaml 5.3.0, Dune 3.24.0, Linux 6.8/aarch64, and four Apple CPU
cores. Hashes cover every output position.

| Fixture | 1 domain | 4 domains | Speedup | Current-domain allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| 62,500 independent loops | 79.609 ms | 54.258 ms | 1.47x | 93.001/79.018 MB | 74.001/74.005 MB | `362519991447600667` |
| One large loop | 55.206 ms | 46.783 ms | 1.18x | 66.002/66.016 MB | 66.000/66.000 MB | `4031980600791533435` |

The first correct staged fit returned heap tuples from normalization,
eigensystem, and plane-basis helpers and used a racy load/set pair for the
minimum invalid output point. On the same five-repeat campaign it measured
80.976/53.951 ms and 147.501/93.338 MB for the many-loop fixture, and
55.141/46.354 ms with 66.003/66.016 MB for the single loop. Scalar output
planes for the eigensystem/basis and a compare-and-set atomic minimum preserve
the wall-time floor while cutting many-loop current-domain allocation by 37.0%
on one domain and 15.3% on four. Exact hashes did not change. The four-domain
allocation number excludes worker-domain minor allocation, so one-domain and
major figures are the meaningful memory comparison.

Stable union-find, component numbering, and the point order within each
component remain sequential. Independent component fits and final point
projection use the reusable pool. Consequently, the many-loop case scales by
1.47x while the single-loop fit is intentionally limited by four serial stable
moment passes; changing their reduction tree by domain count would violate the
exact-output contract. The complete benchmark processes peaked at 316,316 KiB
RSS on one domain and 299,436 KiB on four, including both retained million-point
fixtures, output hashing, Dune, and the OCaml runtime.

```sh
RAYS_CIRCLE_EDGE_POINTS=1000000 RAYS_CIRCLE_EDGE_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release \
    tools/bench_circle_from_edges.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

## Graph Color SOP baseline

The dedicated release benchmark covers 999,999 points in 333,333 disconnected
triangles and a 1,000,000-quad connected grid with 1,002,001 points. The first
fixture colors point cliques and exposes independent component scheduling; the
grid colors primitives once by shared polygon edge and once by any shared
point. Results are five-run warm-topology-index medians at grain 16,384 on
OCaml 5.3.0, Dune 3.24.0, Linux 6.8/aarch64, and four Apple CPU cores. Hashes
cover the complete integer output and match exactly across domain counts.

| Fixture | 1 domain | 4 domains | Speedup | Current-domain allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| Disconnected triangle points | 50.582 ms | 29.307 ms | 1.73x | 57.001/57.123 MB | 57.000/57.000 MB | `1757474405289905926` |
| Quad primitives by edge | 90.342 ms | 90.558 ms | 1.00x | 49.001/49.001 MB | 49.000/49.000 MB | `3023817910443667473` |
| Quad primitives by point | 113.442 ms | 113.902 ms | 1.00x | 49.001/49.001 MB | 49.000/49.000 MB | `2608693175212566257` |

Union-find/component discovery and ascending-element greedy order are stable.
Only disconnected components color independently, giving a 1.73x measured
speedup without changing color indices. The connected grids intentionally stay
serial inside their one dependency component; the shared-point case performs
more packed incidence scans because its graph includes diagonal point-touching
faces. No explicit adjacency or per-neighbor boxes are allocated.

An ownership-reuse experiment reduced the disconnected fixture's major scratch
from 57.0 MB to 43.7 MB and the grid from 49.0 MB to 41.0 MB, but repeat A/B
measurement regressed the disconnected medians to 64.8/46.6 ms. The retained
layout therefore spends about 57 bytes per selected point at this extreme to
keep dense component-member, color-mark, and compact component planes cache-
local. The complete two-fixture benchmark processes peaked at about 641 MiB RSS,
including both source geometries, retained topology indices, hashes, Dune, and
the OCaml runtime.

Calls without a cancellation token take a branch-free neighbor-scan path. With
a token, the same ordered scan polls packed corner/incidence ranges every 4,096
entries and component members every 4,096 colors, bounding cancellation latency
for single high-valence or long connected components without changing results.

```sh
RAYS_GRAPH_COLOR_ELEMENTS=1000000 RAYS_GRAPH_COLOR_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release \
    tools/bench_graph_color.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

The deliberately heavier fallback/recompute fixtures generate geometric
normals before and after deformation. Peak takes 136.561/105.007 ms and
Mountain takes 423.140/185.134 ms; their exact hashes are respectively
`1482058233710394922` and `3675202703946158986`. They cumulatively allocate
168.15--168.29 MB across the two normal passes and required output. Direct
stable corner-order point accumulation avoids retaining the much larger full
reverse-topology index solely for normals. The isolated four-domain,
five-repeat Mountain fallback/recompute process peaked at 261,800 KiB RSS,
including source/output geometry, benchmark hashing, Dune, and the OCaml heap.
Its shared-point accumulation is intentionally sequential for byte-exact
floating-point order; face construction, normalization, fBm, displacement,
and independent output fills use the reusable domain pool.
The former procedural render smoke produced byte-identical one/four-domain
160x120 PNGs (SHA-256
`fc98b7188ca058d286a08a819da4c0a4553cad69a447da9eb6ee4a0b12941d7f`,
17,441 bytes). That unbuilt file was removed with the other render smokes;
`test/sop_render_parity.ml` now runs native one/four-domain PNG parity for 23
named SOP graphs under `@runtest-native`.

```sh
RAYS_RDK_OPS_FILTER=peak RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=peak RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=mountain RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=mountain RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

Generalized Measure compiles primitive selection once, allocates the exact
primitive float plane, and writes independent primitive ranges through the
process-wide pool. Triangle-dense area and signed-volume inputs bypass generic
N-gon scratch; concave N-gons still use deterministic ear clipping. The
per-element output plane becomes the owned attribute directly, while optional
detail/throughout totals reduce in stable primitive order.

On the four-core Linux runner (OCaml 5.3.0, Dune 3.24.0, release profile,
grain 16,384, five medians), a 400×400 grid has 160,801 points and 320,000
triangles. The former fan-area baseline took 2.009 ms and allocated 2.561 MB
on one domain, but it is not correct for general concave polygons. The packed
correct area path took 5.427/3.279 ms and allocated 7.687/4.115 MB on one/four
domains; its triangle-fixture geometry hash is exactly the baseline hash
`2847168018130239202`. Adding the detail total took 5.365/3.305 ms.
Perimeter took 7.578/3.775 ms. A 20,001-box, 240,012-triangle signed-volume
fixture took 5.933/3.958 ms and allocated 5.766/2.977 MB. Every one/four-domain
hash was exact. The isolated four-domain five-repeat process peaked at 79,720
KiB RSS, including the fixtures, benchmark hashing, Dune, and OCaml heap.

```sh
RAYS_RDK_OPS_FILTER=measure RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=measure RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_rdk_ops.exe
```

Connectivity uses compact integer parent/rank planes and an integer
root-to-class plane; it performs no polymorphic hashing and assigns class IDs
in first-included-element order. Default primitive connectivity streams corner
incidence directly. Point, seam, and UV modes reuse the process-shared packed
topology index. The dependency-producing union pass is intentionally serial:
parallel writes to shared union-find parents would require an atomic object per
element or nondeterministic races, while stable text output is materialized in
disjoint parallel ranges.

The release fixture is a 500x500 grid with 251,001 points, 500,000 triangles,
grain 16,384, and five medians. The previous correct shared-point primitive
baseline took 34.477/34.504 ms on one/four domains and allocated 22.203 MB.
The packed replacement took 18.590/17.385 ms, allocated 14.509 MB, and retained
the exact geometry hash `3488904335052786360`. Point connectivity with shared
prefixed-text output took 17.023/16.222 ms and allocated 8.284/8.290 MB. Native
seam and continuous vertex-UV modes took 15.529/15.526 ms and
18.405/18.649 ms respectively. Every one/four-domain output hash matched. The
isolated four-domain five-repeat process peaked at 239,680 KiB RSS, including
all five fixtures, cached topology, benchmark hashing, Dune, and the OCaml
heap.

```sh
RAYS_RDK_OPS_FILTER=connectivity RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=connectivity RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
```

Group Find Path prepares one robust relation-weight plane, then runs linear
packed shortest-path searches. Point paths weight native topology edges;
primitive paths use scaled face centroids and the manifold shared-edge dual
graph. Independent start/end pairs use disjoint result slots and the
process-wide domain pool. Routes coupled by shared-element avoidance run in
base order. Query workspaces come from a synchronized pool, bounding live
scratch by active workers instead of total route count.

The release fixture is a 300x300 triangulated grid: 90,601 points and 16 paths.
At grain 16,384 and five medians, independent pair paths took 69.535/27.874 ms
on one/four domains (2.49x) and reported 19.286/9.829 MB allocation. A single
ordered through-path with shared-point avoidance took 54.058/54.234 ms and
reported 19.325/9.895 MB; its dependency chain is intentionally sequential.
The respective exact hashes were `1311998529516673994` and
`4602911275923761527` at both domain counts. Before scratch pooling, the same
one-domain fixtures allocated 62.770/59.914 MB. The isolated cold four-domain
process, including both fixtures, Dune, and the OCaml heap, peaked at
114,432 KiB RSS.

The primitive-dual extension uses the same 300x300 grid with 180,000 faces and
16 independent cross-grid paths. In release profile at grain 16,384, five-run
medians were 169.055/70.390 ms on one/four domains (2.40x). Reported allocation
was 27.445/17.999 MB, with exact hash `1785187313966206317` at both domain
counts; preprocessing alone took 14.729/7.734 ms. Replacing polymorphic float
maximums in the face-centroid loop removed per-corner boxing: the one-domain
full fixture fell from 79.285 MB and 181.932 ms to 27.445 MB and 169.055 ms.
Cold one/four-domain processes peaked at 107,392/115,376 KiB RSS, including
Dune and the OCaml heap.

The representative native procedural scene now includes an ordered
primitive-dual path-driven ridge, point-edge-depth growth, an
boundary-promoted attribute-seam/unshared-edge wire and an
incident-edge-angle-derived selection,
stable polygon boundary-component groups, normal,
non-planarity-, and backface-driven deformation,
and a text-connectivity/name-group round
trip plus bounds-restricted random primitive deformation. One/four-domain
exports were byte-identical at 12,083 bytes with
SHA-256
`9b4d168b71d85c7b9d07eebe9ad88dfd7ef43d3c3345d6e51856a76ff35e2b6b`.

```sh
RAYS_RDK_OPS_FILTER=group_find_path RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=group_find_path RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
```

Group Transfer builds one same-owner map per requested owner and reuses it for
every matching source group. Point mapping uses the packed point tree.
Primitive and native-edge mapping use stable triangle/segment feature planes
and a median-split AABB hierarchy; target entity ranges query in parallel and
packed destination groups fill in disjoint byte ranges. Exact geometric
distance—not barycenter or midpoint distance—covers polygon containment,
triangle crossings, curve crossings, and edge crossings.

The release fixture is a translated 300x300 grid with 90,601 points, 180,000
triangles, and 270,600 unique edges. At grain 16,384 and five medians, point
transfer took 54.456/21.182 ms on one/four domains and allocated
2.921/2.927 MB. An ordered 6,923-point source selection took
55.808/21.109 ms and allocated 3.880/3.886 MB, including the output sequence
and deterministic proximity sort. Exact primitive transfer took
1,467.876/493.303 ms with 79.091/51.575 MB reported allocation, and exact
native-edge transfer took 506.293/181.549 ms with 56.992/56.996 MB. Exact
one/four-domain hashes matched for each case. The isolated four-domain process
peaked at 144,348 KiB RSS with all four fixtures, Dune, and the OCaml heap.

The first correct feature-query implementation returned boxed floats at the
non-inlined candidate boundary: primitive/edge paths allocated
130.293/149.149 MB on one domain. Forcing the scalar distance kernel into its
single query call site removed allocation proportional to candidate visits,
leaving exact feature, hierarchy, mapping, and group planes. No topology or
distance semantics changed.

```sh
RAYS_RDK_OPS_FILTER=group_transfer RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=group_transfer RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
```

Groups from Name classifies names once in stable element order, allocates one
integer owner map, computes the complete dense membership footprint before
allocation, fills exact-size packed buffers by disjoint byte ranges, and
publishes every generated group in one metadata rebuild. Name discovery is
intentionally serial because first-seen ordering and normalization-collision
resolution are observable; dense output materialization and existing-group
union prefill use the reusable pool. The default 4096-group and 256 MiB packed
payload limits prevent an unbounded distinct-string cook.

The 2026-08-02 release-profile fixture contains 1,002,001 points, 64 repeated
valid names, an exact retained group payload of 8,016,064 bytes, grain 16,384,
and five medians. One domain took 21.240 ms and four domains 18.840 ms. Reported
allocation was 32,171,344/32,188,072 bytes, promoted allocation 7,632/7,712
bytes, major allocation 16,106,096/16,106,176 bytes, and both runs produced
hash `29769320617246427`. The full benchmark process peaked at 932,992 KiB RSS
because it also owns the million-point/two-million-triangle catalog grid; the
operator's strict retained group plane is covered separately by its payload
ceiling regression.

```sh
RAYS_RDK_OPS_FILTER=groups_from_name RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use /usr/bin/time -v for process RSS.
```

Name from Groups uses the inverse compact representation path. Its first
correct implementation called bounded membership once per owner element per
group: the same 1,002,001-point/64-group fixture took 167.980/168.424 ms on
one/four domains and allocated 16,068,176/16,084,600 bytes. Borrowing immutable
packed membership and decoding set bits through a fixed 256-entry lookup cut
that to 30.104/26.529 ms (5.58x/6.35x) and 16,061,488/16,076,840 bytes, with
zero promoted allocation and unchanged exact hash `4492166743618885122`.
The final four-domain `/usr/bin/time -v` run took 26.847 ms and peaked at
933,128 KiB RSS including the same unrelated million-point catalog fixture.
Stable overlap resolution remains serial and output text ranges parallelize;
the node is not mislabeled as fully parallel.

```sh
RAYS_RDK_OPS_FILTER=name_from_groups RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

Group Random writes one exact packed output plane by byte and evaluates the
stateless indexed RNG without allocating per element. On the 1,002,001-point,
6,000,000-corner, 2,000,000-triangle grid (five release medians, grain 16,384),
all domain-count hashes matched exactly:

| Random owner | 1 domain | 4 domains | Speedup | Allocated (1d/4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| points | 15.729 ms | 5.212 ms | 3.02x | 128,400 / 139,104 B | 1502542100698521367 |
| points, integer seed attribute | 18.751 ms | 6.140 ms | 3.05x | 129,376 / 140,416 B | 741674098761237833 |
| vertices via referenced points | 63.004 ms | 19.448 ms | 3.24x | 753,160 / 828,712 B | 463783728553111218 |
| primitives | 31.753 ms | 9.282 ms | 3.42x | 253,152 / 278,680 B | 2239194332430174016 |
| native edges | 64.061 ms | 18.996 ms | 3.37x | 378,600 / 414,256 B | 1129442167829773584 |

All five paths reported zero promoted allocation. The complete one-/four-domain
benchmark processes peaked at 941,096/940,912 KiB RSS, dominated by the shared
million-point catalog fixture rather than the 0.125--0.750 MB result planes.

```sh
RAYS_RDK_OPS_FILTER=group_random RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

Group Bounds specializes inclusive box/sphere classification by owner and
writes exact packed byte ranges. Native-edge partial selection uses normalized
segment/AABB separating axes or normalized closest-point sphere distance; a
4,096-segment deterministic regression compares both against independent slab
and closest-point reference implementations, in addition to explicit
`±max_float` crossings.

The first functionally passing scalar implementation exposed float arguments
and polymorphic extrema across hot call boundaries: on the million-point grid,
point box, vertex sphere, partial primitive sphere, and partial edge box paths
took 10.548/125.846/78.716/302.808 ms on one domain and allocated
48.224/422.316/282.218/1,330.040 MB. Typed inline extrema, index-based packed
position helpers, and the allocation-free normalized segment test reduced the
final five-run release medians to:

| Bounds owner | 1 domain | 4 domains | Speedup | Allocated (1d/4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| points, box | 5.905 ms | 2.015 ms | 2.93x | 128,360 / 141,768 B | 4236156032951970607 |
| vertices, sphere | 47.376 ms | 13.182 ms | 3.59x | 753,152 / 830,600 B | 4528769128124633514 |
| primitives, partial sphere | 32.484 ms | 11.688 ms | 2.78x | 253,160 / 277,744 B | 2533917132730828175 |
| native edges, partial box | 47.496 ms | 13.938 ms | 3.41x | 378,592 / 407,120 B | 1789639128692061452 |

Every final path reports zero promoted allocation. Full one-/four-domain
processes peaked at 940,988/933,048 KiB RSS, dominated by the common catalog
fixture; the operator retains only its listed packed group plane.

```sh
RAYS_RDK_OPS_FILTER=group_bounds RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

Group Normal uses normalized SoA geometry directions and exact packed output.
The first correct geometric primitive path retained three full face-normal
planes plus validity bytes: it took 68.005 ms and allocated 50.254 MB on one
domain. Classifying each primitive directly removed that scratch, reducing the
same hash to 54.227 ms and 0.254 MB in the same dev-profile optimization pass.
Geometric point classification reuses face directions but writes packed
membership directly instead of retaining a
second point-direction plane, cutting temporary allocation from 74.178 MB to
50.130 MB without materially changing its 281.688 ms time. Edge classification
retains both planes because endpoint directions are shared by several edges. Five
release medians on the 1,002,001-point/two-million-triangle fixture were:

| Normal mode | 1 domain | 4 domains | Speedup | Allocated (1d/4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| primitives, geometric | 55.326 ms | 18.582 ms | 2.98x | 254,112 / 295,760 B | 766292961723497574 |
| points, geometric | 284.360 ms | 97.771 ms | 2.91x | 50,129,840 / 50,181,648 B | 2998276320699778409 |
| native edges, geometric | 339.048 ms | 115.295 ms | 2.94x | 74,428,088 / 74,513,432 B | 2642970349581848497 |
| points, reused `N` | 12.501 ms | 4.385 ms | 2.85x | 129,640 / 157,904 B | 2998276320699778409 |

All modes reported zero promoted allocation and exact hashes across domain
counts. The isolated four-domain process peaked at 941,136 KiB RSS, dominated
by the common million-point catalog grid and cached topology. The authored
normal path demonstrates the intended realtime amortization boundary.

Group Non-Planar retains only its exact packed primitive result. On a
6,004,001-point bilinear-quad surface deformed by deterministic Mountain, it
classified every polygon in 335.706/105.411 ms on one/four domains (3.18x),
allocated 755,960/927,840 bytes with zero promotion, and produced exact hash
`3774048257159142110`. The isolated four-domain process peaked at 2,682,300 KiB
RSS because the benchmark fixture itself contains 36,004,001 total topology
elements; the operation's measured allocation remains below 0.9 MB. These
measurements used OCaml 5.3.0, the Dune release profile, grain 16,384, and the
four-core Linux 6.8/aarch64 runner.

Group Backface likewise classifies directly from polygon winding into one
packed primitive plane. On the 1,002,001-point/two-million-triangle fixture,
five release medians were 59.491/19.778 ms on one/four domains (3.01x), with
253,688/295,664 bytes allocated, zero promoted allocation, and exact hash
`4182868031845387534`. The isolated four-domain process peaked at 941,252 KiB
RSS, dominated by the common catalog fixture. The kernel is O(vertices) time,
O(1) scratch per primitive, and its only retained auxiliary storage is the
ceil(primitives/8) result bitset.

Incident-Edge Angle initially normalized both vectors and evaluated optional
bounds inside every adjacency comparison. Although functionally correct, the
million-point grid took 509.885 ms and allocated 1,903,704,728 bytes on one
domain. The production kernel now computes each canonical edge direction once
into three packed float planes, changes sign at the shared endpoint, and uses
allocation-free dot comparisons while writing the final edge bitset directly.
On the 1,002,001-point/two-million-triangle grid, five release medians are
184.485/67.170 ms on one/four domains (2.75x), allocating
72,424,696/72,501,680 bytes with zero promotion and exact full-geometry hash
`483681219119422642`. That is 2.76x faster and 26.3x less allocation than the
first correct scalar implementation. The retained scratch is exactly three
eight-byte direction components per 3,001,000 unique edge plus the packed
result; the four-domain process peaks at 933,212 KiB including the common
catalog fixture. Complexity is O(edges + sum(point degree squared)) time and
O(edges) auxiliary memory because SideFX's rule compares each edge against all
others sharing a point.

The existing face-dihedral basis remains separate and does not allocate edge
directions. On the same fixture it takes 81.660/34.373 ms (2.38x), allocates
48,376,800/48,436,736 bytes for shared face directions and packed output, has
zero promotion, and produces exact hash `4244824432032029085` across domain
counts.

Group Edge Depth shares its bounded BFS with positive point Group Expand. On
the 1,002,001-point grid with a full central seed row, depth 16 takes
6.227/6.289 ms on one/four domains, allocates 1,145,760/1,145,960 bytes with
zero promotion, and produces exact hash `3768798821491533615`. Depth 128 takes
30.253/30.507 ms and 8,320,952/8,321,152 bytes with exact hash
`46966495678740863`; work and queue capacity grow with the reached
neighborhood, not depth times total geometry. The traversal intentionally
stays sequential because its sparse stable frontier is faster than atomics or
repeated parallel global scans. On the same million-point fixture, the former
parallel repeated-dilation Group Expand depth-16 path took 394.880/129.139 ms;
the shared BFS now takes 9.870/7.716 ms with the identical hash, a 40.0x
one-domain reduction. Its step-attribute variant fell from
407.863/136.216 ms to 10.692/8.396 ms while preserving its exact hash. The
four-domain benchmark process peaks at 941,420 KiB, dominated by the common
catalog geometry and cached topology.

Group Unshared shares one packed edge-incidence classification across its
native-edge, incident-point, and incident-primitive outputs. On the same
1,002,001-point/two-million-triangle grid, five release medians were:

| Output | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Native edges | 8.480 ms | 2.759 ms | 3.07x | 0.378 / 0.419 MB | `3562499055890456646` |
| Incident points | 24.571 ms | 9.008 ms | 2.73x | 0.504 / 0.558 MB | `1681749199707668283` |
| Incident primitives | 28.929 ms | 9.526 ms | 3.04x | 0.628 / 0.694 MB | `4001880522692313028` |

All three paths had zero promotion and byte-identical full-geometry hashes.
Classification is O(edges); point and primitive conversion additionally visit
their compact incidence once. Native-edge output reuses the classification
bitset directly, while converted outputs retain only their packed result.

Group Boundary Components took 24.168/16.531 ms (1.46x), allocated
16.536/16.587 MB with zero promotion, and produced exact hash
`2905548208608083910`. Stable union-find is intentionally sequential so
component identity cannot depend on work-stealing order; edge classification
and packed per-group output materialization parallelize. The two point-count
integer planes dominate its O(points + boundary bits + output payload)
auxiliary memory. The isolated four-domain process peaked at 933,212 KiB,
including the common million-point catalog fixture, Dune, and the OCaml heap.

Group Range reuses the audited stable connectivity classifier and materializes
local component indices in one linear pass. The classifier now consumes its
locally owned union-find parent/rank storage as the stable class output, and
component sizes become the first-bound plane after local indices are assigned.
This removes two connectivity-sized maps and one component-sized plane.

On the 1,002,001-point/two-million-triangle grid, five release-profile medians
produced:

| Operation | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Global periodic range | 11.886 ms | 4.641 ms | 2.56x | 0.130 / 0.146 MB | `3310314062524435799` |
| Disconnected points | 88.243 ms | 78.552 ms | 1.12x | 17.165 / 17.181 MB | `2250544209884527656` |
| Disconnected primitives | 85.027 ms | 76.970 ms | 1.10x | 42.271 / 42.302 MB | `31913971226352702` |
| Point integer attribute, maximal cuts | 71.375 ms | 49.510 ms | 1.44x | 57.623 / 57.688 MB | `751812281180037666` |
| Primitive integer material regions | 127.312 ms | 90.680 ms | 1.40x | 34.639 / 34.725 MB | `1999822929821485813` |
| Point collision boundary, retained | 128.177 ms | 94.412 ms | 1.36x | 17.543 / 17.609 MB | `1053095748955133645` |

Against the immediately preceding three-repeat baseline, disconnected-point
allocation fell from 33.196/33.211 MB to 17.165/17.181 MB (48.3%) while wall
time rose from 78.577/70.062 ms to 88.243/78.552 ms (12.3%/12.1%). The
primitive path improved from 89.446/81.663 ms to 85.027/76.970 ms
(4.9%/5.7%) while allocation fell from 74.270/74.296 MB to 42.271/42.302 MB
(43.1%). This trade is retained because connected long-running cooks are
memory-bound and the hashes are unchanged. Attribute validation, boundary
classification, and packed output fill parallelize; union-find and stable
component numbering remain serial so region IDs cannot depend on scheduling.

One-repeat runs of all six single-range rows peaked at 937,244/937,268 KiB RSS
on one/four domains, dominated by the shared catalog fixture and cached
topology. Complexity is O(points + vertices + primitives + selected attribute
payload + boundary incidence), with component/local-index planes, two
component-bound planes, configured packed seam/include masks, and one packed
output. Measurements used OCaml 5.3.0, Dune 3.24.0, the release profile, Linux
6.8 aarch64, and four physical cores.

The ordered 16-rule global `group_ranges` benchmark took 82.084/26.044 ms on
one/four domains (3.15x), allocated 2.111/2.309 MB with zero promotion, and
produced exact hash `2577986629024007008`. That allocation is dominated by the
sixteen required one-million-point packed group payloads. One-repeat isolated
runs peaked at 937,352/937,540 KiB RSS. Rules remain ordered because later base,
collision, and merge references may depend on earlier output; the independent
packed fill inside each rule uses the reusable domain pool. For [r] rules,
time is the sum of their individual range/connectivity work and persistent
output is O(r * owner-elements / 8) in the worst case.

```sh
RAYS_RDK_OPS_FILTER=group_normal RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_non_planar RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_backface RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_edges_incident_angle RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_edges_dihedral_angle RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_edge_depth_points RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_unshared RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_boundary_components RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=group_range RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

RDK Reverse was measured on the 1,002,001-point/two-million-triangle grid
(6,000,000 corners), with five release-profile medians. The former sequential
whole-geometry implementation took 61.311/58.188 ms on one/four domains and
allocated 186.018/186.018 MB. Exact-sized owned topology planes and stable
disjoint corner/payload fills reduced the audited implementation to:

| Operation | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Reverse all | 41.905 ms | 31.788 ms | 1.32x | 122.018 / 122.088 MB | `950956516844832509` |
| Shift all by one | 50.169 ms | 32.654 ms | 1.54x | 122.019 / 122.089 MB | `3417685213320867880` |
| Reverse alternating primitive group | 75.930 ms | 63.762 ms | 1.19x | 122.018 / 122.089 MB | `1797118658515838477` |

The full-reversal change is a 31.7% one-domain and 45.4% four-domain wall-time
reduction, with 34.4% less allocation. All cases had byte-identical hashes
across domain counts and zero promoted words in the final measurements. One
repeat of all three cases peaked at 244,288/244,296 KiB RSS on one/four
domains, including the common source geometry, outputs, hashing, Dune, and the
OCaml heap. Reverse and Shift are O(vertices + selected scan + vertex payload)
time and O(vertices + remapped vertex payload) owned output; local selection
adds only the primitive membership already supplied by the caller.

```sh
RAYS_RDK_OPS_FILTER=reverse_ RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env RAYS_RDK_OPS_FILTER=reverse_ \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

RDK Triangulate was measured on a 1,002,001-point/one-million-quad grid
(4,000,000 input corners), with five release-profile medians. The former
sequential implementation took 193.076/189.481 ms on one/four domains,
allocated 458.019 MB, and produced exact hash `1520822849354697608`.
Cardinality-first source ranges, block-owned reusable clipping scratch, and one
block-local emit closure reduced the audited implementation to:

| Operation | Output points + corners + primitives | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| Triangulate all quads | 9,002,001 | 167.796 ms | 100.139 ms | 1.68x | 427.113 / 226.224 MB | `1520822849354697608` |
| Triangulate alternating primitive group | 7,502,001 | 107.948 ms | 62.489 ms | 1.73x | 270.613 / 171.147 MB | `2466371269892443976` |

The full path is 13.1% faster on one domain and 47.1% faster on four than the
baseline, with 6.7% less measured one-domain allocation. Major allocation is
147.07/147.15 MB because exact output topology and source maps dominate; the
remaining four-domain allocation is distributed across worker-domain minor
heaps. Hashes are byte-identical across domain counts. One repeat of both
cases peaked at 983,344/977,440 KiB RSS on one/four domains, including the
million-cell triangle and quad source fixtures, repeated outputs, hashing,
Dune, and the OCaml heap.

Triangulate is O(primitives + sum selected corner_count² + output payload)
time and O(primitives + output vertices) auxiliary/output storage. The
quadratic term is local to each ear-clipped polygon; independent primitive
blocks fill stable disjoint output ranges and cannot alter primitive order.

```sh
RAYS_RDK_OPS_FILTER=triangulate_quads RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env RAYS_RDK_OPS_FILTER=triangulate_quads \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

RDK Normals was measured on a 1,002,001-point/two-million-triangle grid
(6,000,000 corners), with five release-profile medians. Before the production
owner/weighting/selection audit, the compatible point/face-area path took
71.229/51.341 ms on one/four domains, allocated 72.051/72.093 MB, and produced
exact hash `3253461948889680712`. The audited core retains a fused specialization
for that common profile and moves every other mode through the same packed
implementation:

| Operation | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Point, face-area weighting | 63.333 ms | 47.496 ms | 1.33x | 72.051 / 72.092 MB | `3253461948889680712` |
| Point, vertex-angle weighting | 177.847 ms | 161.200 ms | 1.10x | 88.052 / 88.092 MB | `3253461948889680712` |
| Vertex, vertex-angle, smooth | 230.385 ms | 194.549 ms | 1.18x | 232.055 / 232.154 MB | `2683820463808776998` |
| Vertex, vertex-angle, 60-degree cusp | 446.233 ms | 169.031 ms | 2.64x | 256.007 / 256.179 MB | `2683820463808776998` |
| Primitive | 44.256 ms | 22.330 ms | 1.98x | 112.004 / 112.061 MB | `2711170284249389677` |
| Detail | 30.502 ms | 17.515 ms | 1.74x | 48.003 / 48.034 MB | `2278571931501708864` |
| Local missing vertex normals, 60-degree cusp | 533.223 ms | 287.523 ms | 1.85x | 280.809 / 281.118 MB | `2683820463808776998` |

The compatible default is 11.1% faster on one domain and 7.5% faster on four
than its baseline, without raising its 72.048 MB major-allocation floor. All
reported runs had zero promoted words, and every exact hash agrees across
domain counts. Vertex cusp classification precomputes each corner angle once;
its remaining O(sum of squared incident-corner counts) work is local to each
point, uses compact point incidence, and fills deterministic disjoint output
ranges. Smooth point and vertex modes are O(points + corners + output
elements); primitive and detail modes are O(corners + output elements).

Cold construction of the lightweight point-incidence index plus the cusp
result took 533.895/237.575 ms, allocated 368.039/368.214 MB, and peaked at
492,544/492,800 KiB RSS on one/four domains. The full topology index now reuses
that point index rather than rebuilding its primitive and point incidence
planes. Its independent cold regression remains 11.185 ms, 36.246 MB allocated,
30.467 MB major allocation, and the same exact topology hash as before the
split. Warm results above exclude one-time index construction but include all
normal output and hashing work.

```sh
RAYS_RDK_OPS_FILTER=normals_ RAYS_RDK_OPS_REPEATS=5 \
RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  RAYS_RDK_OPS_FILTER=normals_vertex_angle_vertices_cusp60 \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
RAYS_RDK_OPS_FILTER=edge_group_topology_index_cold \
RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_rdk_ops.exe
```

## Selected Transform SOP baseline

Typed Transform was measured on a 500x300 triangulated grid with 150,801
points, 300,000 primitives, 900,000 corners, point normals, and retained point
and primitive selection groups. Seven release-profile medians used grain
16,384 on the four-core Linux 6.8 aarch64/OCaml 5.3.0 runner:

| Transform operation | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Whole geometry + point normals | 4.136 ms | 2.588 ms | 1.60x | 7,243,792 / 7,250,424 B | `2708956205843145110` |
| Direct point group, one third | 3.158 ms | 2.499 ms | 1.26x | 7,244,072 / 7,251,016 B | `1873293194140821756` |
| Primitive group promotion, two fifths | 6.851 ms | 3.760 ms | 1.82x | 7,263,440 / 7,274,184 B | `499134604961687833` |
| Point group + full normal recomputation | 11.457 ms | 8.885 ms | 1.29x | 14,442,472 / 14,454,816 B | `1179657247922872418` |

All hashes include ordered geometry, attributes, and groups and agree exactly
across domain counts. Allocation is the immutable position and normal output
floor; primitive restriction adds only its packed promoted point mask and
control data. One isolated four-domain primitive-selection run peaked at
63,072 KiB RSS including fixture construction, cached incidence, Dune, and the
OCaml heap. Composition is constant work. Selection promotion is O(points +
selected incidence); transformation is O(points + affected normal elements),
uses disjoint stable ranges, and performs no per-element heap allocation.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 \
RAYS_RDK_OPS_FILTER=transform_selected \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

## Soft Transform SOP baseline

Soft Transform used the same 500x300 grid, a single central source point, a
20-unit influence radius, point normals, cubic rolloff, and an emitted point
weight plane. Seven warmed release-profile medians used grain 16,384:

| Distance source | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Packed closest-point radius | 15.565 ms | 11.688 ms | 1.33x | 19,872,584 / 19,350,184 B | `2316545408531800981` |
| Exact geometric edge path | 16.417 ms | 13.668 ms | 1.20x | 21,910,720 / 20,205,752 B | `723873698717865035` |
| Direct authored point weight | 14.371 ms | 14.206 ms | 1.01x | 15,649,888 / 15,668,664 B | `264583665939905200` |

All ordered geometry, normals, retained groups, and falloff planes are exact
across domain counts. Radius indexing and nearest queries, attribute
validation, deformation, falloff materialization, and normal output use stable
parallel ranges. Edge Dijkstra is serial by design because its priority
dependencies are sparse and ordered; the later deformation and normal passes
remain parallel. The first correct edge implementation permitted duplicate
heap entries and took 18.628 ms/29,002,464 B. A fixed point-sized indexed
decrease-key heap reduced it to 16.417 ms/21,910,720 B—11.9% faster and 24.5%
less allocation—with the identical hash. The cold isolated four-domain edge
process peaked at 158,992 KiB RSS and includes source creation plus construction
of the shared topology index; warm medians reuse that immutable index.

Radius work is expected O(selected log selected + points log selected) with
O(points + selected) scratch. Edge work is O((points + visited edges) log
points) and O(points) scratch, bounded early by radius. Direct attributes and
output deformation are O(points). No inner path allocates per point, neighbor,
or heap relaxation.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 \
RAYS_RDK_OPS_FILTER=soft_transform \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

## Distance Along Geometry SOP baseline

Distance Along Geometry used a 500x300 triangulated grid (150,801 points), one
central start point, and grain 16,384 on the same Linux aarch64/OCaml 5.3.0
runner. Seven warmed release-profile medians distinguish full connected-field
work from the radius-bounded real-time path:

| Edge-distance output | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Full raw distance + fixed cubic mask | 42.097 ms | 41.093 ms | 1.02x | 25,567,488 / 12,826,904 B | `485242207308178349` |
| Fixed cubic mask only, bounded at 20 | 6.543 ms | 4.809 ms | 1.36x | 24,360,632 / 11,621,104 B | `2688339049920420978` |
| Full distance + affected maximum quadratic mask | 42.322 ms | 40.541 ms | 1.04x | 23,409,168 / 12,091,768 B | `4103950385774346115` |

The full cases traverse the complete connected grid because raw distance or
maximum normalization needs every reachable value. The mask-only fixed-radius
case stops queue expansion at the radius and is 6.43x faster than the
one-domain full raw-distance case. Dijkstra's dependency-ordered heap remains
serial; packed mask/distance initialization and affected writes use stable
parallel ranges. Every geometry/attribute/group hash is identical across
domain counts. A cold isolated four-domain full run, including fixture and
topology-index construction, peaked at 154,420 KiB RSS; its 138.938 ms and
147,549,000 allocated bytes are deliberately excluded from warmed medians.

Work is O((visited points + visited edges) log points), scratch is O(points),
and each enabled immutable output adds one exact point-sized float plane. The
indexed heap never allocates per relaxation and each point occupies at most one
queue slot.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 \
RAYS_RDK_OPS_FILTER=distance_along \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  RAYS_RDK_OPS_FILTER=distance_along_edge_full_fixed_mask \
  RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
```

## Distance From Geometry SOP baseline

Distance From Geometry used a 500x300 source grid (150,801 points) translated
1.5 units above its original plane, an all-but-every-fifth affected point set,
and a 96x144 UV-sphere reference. Seven warmed release-profile medians used
grain 16,384 on the Linux aarch64/OCaml 5.3.0 runner:

| Reference/query | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Reference points, full raw + fixed cubic mask | 842.207 ms | 307.494 ms | 2.74x | 20,526,576 / 9,458,728 B | `3633148159826570530` |
| Polygon surface, full raw + fixed cubic mask | 663.559 ms | 252.378 ms | 2.63x | 40,933,184 / 18,105,880 B | `2553146708132357293` |
| Polygon surface, bounded mask only at radius 6 | 74.330 ms | 32.985 ms | 2.25x | 38,780,376 / 18,029,392 B | `4063088156542703670` |

All geometry, attribute, and group hashes agree exactly across domain counts.
The mask-only surface cook prunes the BVH at the squared radius and is 8.93x
faster than the one-domain full surface field. Index construction, query
ranges, square-root conversion, affected writes, and immutable output
materialization are included. A cold isolated four-domain full-surface run
peaked at 63,516 KiB RSS and completed in 247.924 ms.

The distance-only surface query was also measured against the existing full
provenance query on a prebuilt index:

| Surface query | 1 domain | 4 domains | Allocated (1d / 4d) | Exact distance hash |
|---|---:|---:|---:|---:|
| Primitive + triangle + barycentrics baseline | 807.913 ms | 289.980 ms | 26,542,408 / 11,865,152 B | `3105812017738822794` |
| Distance-only batch | 782.532 ms | 284.776 ms | 18,097,152 / 7,090,024 B | `3105812017738822794` |

Removing five unused output planes reduced reported allocation by 31.8% on
one domain and 40.2% on four while preserving every distance bit. The first
point-distance specialization returned a boxed float through each recursive
k-d-tree visit: it took 925.283 ms and allocated 1,410,393,104 B. Updating one
owned output slot in place reduced that to 842.207 ms and 20,526,576 B—9.0%
faster and 98.5% less allocation with the identical end-to-end hash. Neither
final traversal allocates per visited point, triangle, or candidate.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 \
RAYS_RDK_OPS_FILTER=distance_from \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  RAYS_RDK_OPS_FILTER=distance_from_surface_full_fixed_mask \
  RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
```

## Distance From Target SOP baseline

Distance From Target used a 500x300 source grid (150,801 points), translated
off the analytic origin, with all but every fifth point affected. Seven warmed
release-profile medians used grain 16,384 on the Linux aarch64/OCaml 5.3.0
runner:

| Projection/output | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Spherical, raw + fixed cubic mask | 3.441 ms | 1.776 ms | 1.94x | 16,169,792 / 7,142,280 B | `1909096818709727321` |
| Cylindrical, fixed cubic mask only | 3.694 ms | 1.307 ms | 2.83x | 17,103,672 / 5,015,584 B | `4578955952943326100` |
| Planar, signed raw + maximum quadratic mask | 4.743 ms | 2.484 ms | 1.91x | 17,865,608 / 7,809,808 B | `2761229398028025238` |

Every geometry, attribute, and group hash agrees exactly across domain counts.
The kernel is O(points): target normalization is hoisted, point fills are
disjoint, and no inner-loop value is boxed. Fixed mask-only cooking allocates
no distance scratch plane; the planar maximum case reuses the enabled raw
output for its deterministic maximum reduction. A cold isolated four-domain
planar maximum run completed in 3.428 ms and the full benchmark process peaked
at 63,644 KiB RSS.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 \
RAYS_RDK_OPS_FILTER=distance_from_target \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  RAYS_RDK_OPS_FILTER=distance_from_target_planar_signed_maximum \
  RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
```

## Extended Sort SOP baseline

Extended Sort used a 500x300 grid (150,801 points). Seven warmed release-
profile medians used grain 16,384 on the Linux aarch64/OCaml 5.3.0 runner:

| Mode | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Seeded random point reorder | 14.541 ms | 11.143 ms | 1.30x | 34,031,160 / 23,576,160 B | `1784063105669112868` |
| Sort Indices by X | 16.609 ms | 18.044 ms | 0.92x | 5,638,392 / 5,642,512 B | `331158885052146126` |
| Reorder by index attribute | 17.086 ms | 11.696 ms | 1.46x | 37,801,752 / 28,399,592 B | `2550686151438781422` |
| Combined Sort Indices, X after Y | 18.264 ms | 17.867 ms | 1.02x | 8,202,256 / 8,206,024 B | `331158885052146126` |
| Points by first vertex order | 25.527 ms | 21.520 ms | 1.19x | 38,462,536 / 29,056,656 B | `1104154926966865620` |
| Points by lowest primitive index | 25.021 ms | 21.291 ms | 1.18x | 38,462,480 / 28,798,464 B | `1104154926966865620` |
| 3D Morton spatial locality | 39.215 ms | 28.087 ms | 1.40x | 63,810,120 / 35,143,576 B | `1868051802001114046` |

All geometry, attribute, and group hashes agree exactly across domain counts.
Random shuffle and index validation are allocation-free-inner-loop O(points);
topology/payload remapping accounts for most random/reorder storage and uses
parallel disjoint ranges. Direct and combined Sort Indices remain dominated by
OCaml's deterministic stable O(n log n) comparison sort, so additional domains
do not materially improve them; the measured result is retained rather than
claiming parallel sorting. Topology keys prepare exact O(vertices) integer
planes; spatial locality fills one Morton plane in parallel before the stable
sort. Combine restores a prior rank in O(points) before
the stable key sort and avoids an intermediate topology rebuild. A cold
isolated four-domain random reorder completed in 13.798 ms and the benchmark
process peaked at 63,784 KiB RSS in the isolated Morton run.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 \
RAYS_RDK_OPS_FILTER=sort_extended \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  RAYS_RDK_OPS_FILTER=sort_extended_spatial_locality \
  RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
```

## Blast by Attribute SOP baseline

Blast by Attribute used a 500x300 triangle grid (150,801 points and 300,000
primitives), grain 16,384, and seven warmed release-profile medians on the
four-core Linux aarch64/OCaml 5.3.0 runner. Point density was a scalar float
field; primitive class was a scalar integer field.

| Mode | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Float range to point group | 0.682 ms | 0.304 ms | 2.24x | 20,072 / 23,776 B | `804528108742742467` |
| Float range to point group, base + invert | 0.880 ms | 0.460 ms | 1.91x | 20,088 / 23,720 B | `1925147360161170814` |
| Float range point delete | 18.769 ms | 16.051 ms | 1.17x | 30,934,480 / 22,303,600 B | `1378320980562805451` |
| Integer threshold primitive delete + compact | 21.431 ms | 17.588 ms | 1.22x | 38,537,000 / 29,388,424 B | `3727790948153474531` |

The pre-existing hand-composed `Group.init` plus Delete baselines were
0.435/0.232 ms, 18.507/16.354 ms, and 20.892/17.730 ms respectively. The
public operation adds finite scalar validation and structured policy checks;
the topology-changing cases remain within measurement noise of direct
composition and preserve identical hashes. The first generic implementation
boxed its numeric condition argument per element: point-group classification
allocated 2,432,896/863,480 bytes and took 0.929/0.390 ms. Specializing the
packed callback by storage and matching a prevalidated interval in place cut
that to 20,072/23,776 bytes and 0.682/0.304 ms. Integer deletion allocation
fell from 43,337,016/31,043,344 bytes to 38,537,000/29,388,424 bytes.

Classification is O(elements), writes one packed selection bit per element,
and performs no per-element heap allocation. Group output otherwise shares the
source geometry. Delete output reuses the measured stable Delete planner, so
its dominant allocation is the required packed topology/payload remap. Every
final geometry/group hash agrees across domain counts. An isolated four-domain
primitive-delete run completed in 19.568 ms including a cold measurement and
the process peaked at 65,664 KiB RSS.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_BENCH_DOMAINS=1 \
RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=blast_by_attribute \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  RAYS_RDK_OPS_FILTER=blast_by_attribute_primitive_delete_compact \
  RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
  RAYS_RDK_OPS_REPEATS=1 RAYS_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
```

## Crease SOP baseline

Crease used a 500x300 quad grid (150,801 points, 600,000 corners, and 300,800
unique edges), every seventh edge selected, grain 16,384, and seven warmed
release-profile medians on the four-core Linux aarch64/OCaml 5.3.0 runner.

| Mode | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Sparse Set | 2.477 ms | 1.129 ms | 2.19x | 4,802,808 / 4,811,992 B | `4516226610260321876` |
| Sparse Add with incident maximum reduction | 5.344 ms | 2.275 ms | 2.35x | 7,898,464 / 7,433,528 B | `2628655416438662740` |
| Sparse Delete | 3.769 ms | 1.543 ms | 2.44x | 4,803,936 / 4,820,776 B | `3670675780221511252` |
| All-edge Set | 1.747 ms | 0.811 ms | 2.15x | 4,802,704 / 4,811,128 B | `4516226610260321876` |
| Sparse Set plus endpoint color | 11.519 ms | 8.092 ms | 1.42x | 31,224,552 / 27,839,840 B | `722016367449837285` |

The former manual per-corner Set workflow measured 3.387/3.651 ms and
13,027,912/13,028,112 bytes. The packed Set kernel is 1.37x faster on one
domain, 3.23x faster on four, and allocates 63% less with the identical hash.
Manual Delete measured 3.756/3.571 ms and 13,027,944/13,028,144 bytes; the new
kernel is 2.31x faster at four domains with the identical hash and 63% less
allocation. Manual Add is retained only as a performance baseline: it edits
incident corners independently and therefore cannot serve as the correctness
oracle for unique-edge maximum reduction.

Set/Delete allocate the exact vertex output plane. Add uses one additional
edge plane; visualization adds four exact vertex color planes and one edge
sharpness plane. Block-local change flags avoid atomics in valid inner loops.
All one/four-domain geometry and framebuffer results are exact. The complete
four-domain benchmark process peaked at 123,160 KiB RSS.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=crease RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

## Attribute Fade SOP baseline

Attribute Fade uses one fused point pass for scalar fade/start/hold sampling,
affine frame retiming, piecewise-linear in/hold/out evaluation, finite/overflow
validation, exact selection preservation, and optional grayscale `Cd`. The
float-plane accessor and ramp sampler are forced inline: before that review the
common selected cook allocated one float box per scalar access and measured
2.632 ms/7,761,160 B on one domain. Inlining removed the inner-loop boxes and
reduced it to 1.815 ms/1,212,088 B without changing the exact hash.

The final 500x300-quad-grid benchmark uses 150,801 points, every seventh point
excluded, three float driver planes, four-knot ramps, frame 137.25, grain
16,384, and seven release medians on the four-core Linux aarch64/OCaml 5.3.0
runner.

| Mode | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|---:|
| Selected four-knot ramps | 1.815 ms | 0.754 ms | 2.41x | 1,212,088 / 1,215,392 B | `3899516654851549430` |
| All/default ramps | 1.366 ms | 0.564 ms | 2.42x | 1,211,992 / 1,215,488 B | `147492431177321602` |
| Selected ramps plus point `Cd` | 3.143 ms | 2.185 ms | 1.44x | 6,038,176 / 6,041,536 B | `3597614511156252915` |

The retained serial unchecked scalar reference measured 1.314/1.322 ms and
3,620,152/3,620,352 B with exact hash `3899516654851549430`. The packed
one-domain cook spends an additional 0.501 ms on complete validation and
cancellation while allocating 66.5% less; the four-domain cook is 1.75x faster
than the reference. Persistent storage is one output float plane, plus four
only for visualization; block diagnostics are `O(ceil(points/grain))` and all
other payload is shared. The four-domain benchmark process peaked at 64,568
KiB RSS. Direct RDK, frame/cache-aware SOP, exact one/four-domain mesh, combined
procedural framebuffer, and dedicated visible 320x240 framebuffer tests cover
the path.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=attribute_fade RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4 and use attribute_fade_reference for the
# retained unchecked scalar reference.
```

## PolyCut SOP baseline

PolyCut classifies source directed edges once, computes exact expanded segment,
fragment, corner, and point cardinalities, and fills stable disjoint output
ranges. Point and vertex payload interpolation is fused through shared packed
ancestry planes. Edge Remove uses a narrower path: because it creates no
points, it shares positions and point/detail payload and emits maximal edge
runs without allocating interpolation or expanded-segment scratch.

The retained pre-kernel reference uses allocation-heavy per-fragment arrays,
lists, flattening, and a serial topology reconstruction. The release fixture
contains 300 independent 501-point curves (150,300 points), a scalar sawtooth
field, grain 16,384, and seven medians on the four-core Linux aarch64/OCaml
5.3.0 runner.

| Mode | 1 domain | 4 domains | Speedup | Allocated (1d / 4d) | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| Edge Remove/crossing | 5.532 ms | 3.479 ms | 1.59x | 8,041,272 / 7,370,168 B | 311,161 | `990841547120428818` |
| Edge Cut/crossing | 16.182 ms | 11.839 ms | 1.37x | 60,616,544 / 37,868,256 B | 352,625 | `3032578540479040296` |
| Edge Cut/change threshold 3 | 21.232 ms | 16.519 ms | 1.29x | 86,496,784 / 53,245,088 B | 533,640 | `722701032308820201` |

The serial reference crossing-removal cook measured 4.321 ms and 11,245,664 B
with the first row's identical complete geometry hash. Four-domain PolyCut is
1.24x faster and allocates 34.5% less; its one-domain cost includes full group,
affinity, finite-field, overflow, cancellation, and ancestry validation. Cut
modes emit two independently owned interpolated endpoints at every interior
break, so their larger persistent output and scratch cardinalities are shown
rather than compared to the remove-only reference. The complete four-domain
three-mode process peaked at 85,048 KiB RSS.

Direct tests cover every detection/strategy family, exact crossing positions,
tuple change subdivision, open/closed/polygon kinds, point compaction and free
point policy, all discrete/ragged owners, ordered and native-edge groups,
malformed and cancellation paths, exact one/four-domain geometry and render
mesh, immutable SOP/cache behavior, and a visible 360x240 pixel regression.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=poly_cut RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4 and use poly_cut_reference for the
# retained serial/list baseline.
```

## Separate Pieces SOP baseline

Separate Pieces compiles integer/text keys once, validates rigid point or
primitive ownership, computes one projection plane, reduces stable per-piece
bounds, and fills only changed position axes. The topology and all unrelated
payload remain shared. Axis-aligned layouts therefore allocate one changed
position plane rather than rebuilding XYZ, while the same-owner float3
translation is the only persistent added payload.

The retained serial reference assumes dense independent primitive curves,
directly derives each point's primitive number, skips topology/owner/finite/
overflow/cancellation checks, and rebuilds through two metadata commits. The
release fixture contains 300 overlapping 501-point curves (150,300 points),
primitive integer IDs, gap `0.01`, grain 16,384, and seven warm-index medians
on the four-core Linux aarch64/OCaml 5.3.0 runner.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| packed, 1 domain | 3.313 ms | 3,700,272 B | 0 B | 3,633,000 B | 300,900 | `3435451684132487927` |
| packed, 4 domains | 2.360 ms | 3,711,256 B | 0 B | 3,633,000 B | 300,900 | `3435451684132487927` |
| unchecked serial reference | 2.640 ms | 13,239,208 B | 352 B | 1,209,984 B | 300,900 | `3435451684132487927` |

The validated path scales 1.40x from one to four domains. Four domains are
1.12x faster than the narrow reference and allocate 72.0% less; the validated
one-domain path is intentionally reported as 1.25x slower than that unchecked
fixture-specific loop. A direct cold four-domain run, including fixture and
topology-index construction, peaked at 50,204 KiB RSS. Exact geometry, render
mesh, and framebuffer equality are tested between one and four domains.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=separate_pieces RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4 and use separate_pieces_reference for
# the serial baseline.
```

## Edge Equalize SOP baseline

Edge Equalize measures 150,000 independent two-point curves (300,000 points)
with repeating lengths from 0.5 through 2.1, average-target policy, grain
16,384, and seven warm-index release medians. The optimized fast path caches
one packed length plane, derives all-edge degrees directly from topology CSR,
parallelizes finite length validation, performs a symmetric disjoint endpoint
fill, and shares Y/Z because the fixture can move only in X.

The pre-implementation serial reference is deliberately narrow: it assumes
the exact fixture topology, reads X only, uses a naive unscaled average, skips
topology affinity, finite/overflow/zero-direction/convergence/cancellation
checks, and copies only X. It establishes the irreducible fixture loop rather
than a production-equivalent implementation. Its different hash reflects the
published RDK scale-safe average, not lost geometry fidelity.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| packed, 1 domain | 5.208 ms | 3,601,408 B | 0 B | 3,600,016 B | 750,000 | `908952120690714776` |
| packed, 4 domains | 3.788 ms | 3,609,096 B | 0 B | 3,600,016 B | 750,000 | `908952120690714776` |
| unchecked serial reference | 0.525 ms | 2,400,384 B | 0 B | 2,400,008 B | 750,000 | `4196933012073036451` |

The first correct production implementation measured 5.767 ms / 10,951,264 B
on one domain and 4.895 ms / 10,955,008 B on four. Removing redundant selected
flags and all-edge degree storage and sharing unchanged coordinate planes cut
allocation by 67.1%; packed length reuse plus parallel validation made the
final four-domain path 22.6% faster. The final path scales 1.37x from one to
four domains. A cold direct executable run, including fixture and topology
index construction, peaked at 71,504 KiB RSS on the four-core Linux aarch64,
OCaml 5.3.0 runner. Exact one/four-domain RDK geometry, SOP render meshes, and
360x240 framebuffer PNGs are regression-tested.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=edge_equalize RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use edge_equalize_reference for the
# deliberately unchecked serial lower bound.
```

## Edge Relax SOP baseline

Edge Relax uses the same 150,000 independent-curve / 300,000-point scale as
Edge Equalize. Source lengths repeat from 0.5 through 2.1 and matching-topology
reference lengths repeat from 0.8 through 1.8. The measured policy is
individual reference lengths, 20 iterations, step 0.5, grain 16,384, and seven
warm-index release medians.

The retained serial reference knows the fixture's two-point primitive layout,
reads only X, applies one symmetric exact correction, and skips topology,
selection, pin, finite, normalization, zero-direction, cancellation, and
normal-invalidation policy. The production path validates two geometries,
stores scale-safe source/reference lengths, and uses the closed-form disjoint
iteration result. Its different exact hash is the published scale-safe metric
policy rather than a fidelity reduction.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| packed, 1 domain | 7.394 ms | 4,801,696 B | 0 B | 4,800,024 B | 750,000 | `1571942082499176816` |
| packed, 4 domains | 4.651 ms | 4,808,640 B | 0 B | 4,800,024 B | 750,000 | `1571942082499176816` |
| unchecked serial reference | 0.564 ms | 2,400,416 B | 0 B | 2,400,008 B | 750,000 | `2152096248340914900` |
| connected, 1 domain (150,000 points, 20 iterations) | 173.275 ms | 8,805,056 B | 0 B | 8,800,064 B | 350,000 | `678064836994170377` |
| connected, 4 domains (150,000 points, 20 iterations) | 86.832 ms | 8,873,176 B | 0 B | 8,800,064 B | 350,000 | `678064836994170377` |

The first correct generic implementation measured 46.129 ms / 126,151,888 B
on one domain and 29.117 ms / 69,537,448 B on four. Closed-form disjoint
constraints, hoisted decay, non-polymorphic float maxima, all-movable topology
incidence reuse, and in-place reference-target scaling made the final
four-domain path 84.0% faster and cut allocation 93.1%. It scales 1.59x from
one to four domains. Replacing boxed per-edge target callbacks with a typed
constant-or-packed target source makes the connected solver's allocation
independent of iterations; the 20-step connected fixture scales 2.00x with
byte-identical output. A cold direct run including fixture/reference creation and
topology-index construction peaked at 75,032 KiB RSS on the four-core Linux
aarch64 / OCaml 5.3.0 runner. Exact connected and disjoint RDK/SOP geometry,
render meshes, and dedicated framebuffer PNGs cover domain-count regression.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=edge_relax RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use edge_relax_reference for the
# deliberately unchecked serial lower bound.
```

## Blend Shapes SOP baseline

Blend Shapes uses one million source points. The position-only row blends one
target and excludes ordinary attributes; the attribute row blends two targets
plus scalar `density`, scalar `mask`, and float3 `Cd`; the masked row applies
the same payload with a target scalar scale mask. Grain is 16,384 and numbers
are seven release-profile medians. The serial reference implements only one
same-cardinality direct-index position target and intentionally omits masks,
IDs, attributes, validation, cancellation, and normalization above unit weight.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| one target positions, 1 domain | 18.467 ms | 24,003,840 B | 0 B | 24,000,024 B | 1,000,000 | `3058586826073456996` |
| one target positions, 4 domains | 9.805 ms | 24,041,824 B | 0 B | 24,000,024 B | 1,000,000 | `3058586826073456996` |
| two targets + fields, 1 domain | 69.627 ms | 64,007,216 B | 0 B | 64,000,064 B | 1,000,000 | `57601285729602360` |
| two targets + fields, 4 domains | 35.324 ms | 64,099,816 B | 0 B | 64,000,064 B | 1,000,000 | `57601285729602360` |
| two targets + fields + masks, 1 domain | 85.459 ms | 72,008,168 B | 0 B | 72,000,072 B | 1,000,000 | `3663501905707757503` |
| two targets + fields + masks, 4 domains | 43.582 ms | 72,125,528 B | 0 B | 72,000,072 B | 1,000,000 | `3663501905707757503` |
| unchecked one-target position reference | 9.437 ms | 24,000,432 B | 0 B | 24,000,024 B | 1,000,000 | `1118236195188590496` |

The first correct point-major implementation measured 36.292 ms /
208,003,624 B for positions, 181.291 ms / 616,006,424 B with two target fields,
and 193.278 ms / 647,011,064 B with masks. Escaping component accessor closures
and accumulator boxes were the dominant defect. The final target-major kernel
initializes each owned output once, computes an optional single normalization
sum plane, and applies targets through stable parallel point passes. This made
the three paths 49.1%, 61.6%, and 55.8% faster while reducing allocation by
88.5%, 89.6%, and 88.9%. The common position path now allocates the exact 24 MB
output planes; fields allocate their exact 64 MB outputs, and masking adds one
8 MB sum plane. Four domains scale 1.88x, 1.97x, and 1.96x with identical
hashes. Direct and SOP tests cover normalized/extrapolating weights, multiple
targets, source/target masks, integer/text IDs, reordered/partial targets,
point restriction, every supported fixed-width point field, stale normals,
malformed inputs, cancellation, exact one/four-domain output, cache identity,
topology sharing, and endpoint-distinct framebuffer output.

```sh
RAYS_RDK_OPS_COLUMNS=1000 RAYS_RDK_OPS_ROWS=1000 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=blend_shapes RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use blend_shapes_reference for the
# deliberately unchecked serial lower bound.
```

## Attribute Composite SOP baseline

Attribute Composite uses three ordered one-million-point inputs. The scalar
Mean row composites one Float field without alpha. The alpha-fields row
composites `P`, one scalar, and one Float4 field with a spatially varying point
alpha, so its exact storage floor is eight 8 MB output planes plus one 8 MB
Mean denominator plane. The Over row folds the scalar field with the same
alpha. Grain is 16,384 and numbers are seven release-profile medians.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| Mean scalar, 1 domain | 13.763 ms | 8,011,552 B | 0 B | 8,000,008 B | 1,000,000 | `1240842533481729218` |
| Mean scalar, 4 domains | 5.511 ms | 8,061,424 B | 0 B | 8,000,008 B | 1,000,000 | `1240842533481729218` |
| Mean alpha + P/scalar/Float4, 1 domain | 148.633 ms | 72,021,664 B | 0 B | 72,000,072 B | 1,000,000 | `1262478998332998410` |
| Mean alpha + P/scalar/Float4, 4 domains | 62.765 ms | 72,507,264 B | 0 B | 72,000,072 B | 1,000,000 | `1262478998332998410` |
| Over scalar, 1 domain | 19.036 ms | 8,013,072 B | 0 B | 8,000,008 B | 1,000,000 | `1308454629395839844` |
| Over scalar, 4 domains | 7.820 ms | 8,087,728 B | 0 B | 8,000,008 B | 1,000,000 | `1308454629395839844` |
| unchecked scalar Mean reference, 1 domain | 2.459 ms | 8,000,784 B | 0 B | 8,000,008 B | 1,000,000 | `2573741958835357403` |

The unchecked reference performs one direct scalar expression and omits
patterns, union discovery, alpha, owner/cardinality/kind/finite validation,
cancellation, structural metadata policy, and generic operation dispatch. The
first correct generic kernel measured 25.795 ms for scalar Mean, 261.748 ms and
456,048,184 B for the alpha-field case, and 28.865 ms for scalar Over. A boxed
per-element effective-weight helper caused the allocation spike. Splitting
alpha/no-alpha paths outside the element loop, then fusing source and
intermediate finite validation into the required accumulation passes, reduced
the three one-domain times by 46.6%, 43.2%, and 34.0%; alpha-field allocation
fell 84.2% to its exact 72 MB major floor. Four domains scale 2.50x, 2.37x, and
2.43x with identical hashes. Direct and SOP tests cover all operations and
owners, patterns, opt-in P, scalar/tuple fields, missing alpha/fields,
kind/cardinality/non-finite failures, cancellation, cache identity, exact
one/four-domain output, topology sharing, and endpoint-distinct framebuffer
output.

```sh
RAYS_RDK_OPS_COLUMNS=1000 RAYS_RDK_OPS_ROWS=1000 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=attribute_composite RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use attribute_composite_reference for
# the deliberately unchecked scalar lower bound.
```

## Attribute Mirror SOP baseline

Attribute Mirror measures one million point Float4 values. Explicit mapping
reads one integer destination-to-source plane and one packed destination group.
The ordinary row emits no optional metadata; the output row additionally emits
the pair integer field and source/destination groups. Plane mode reflects the
negative-X half and performs packed nearest queries against the positive-X half
at tolerance `1e-12`. All numbers are seven-run release-profile medians with
OCaml 5.3.0, Dune 3.24.0, grain 16,384, Linux 6.8/aarch64, and four available
Apple CPU cores.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| explicit map, 1 domain | 32.016 ms | 41,004,760 B | 0 B | 41,000,056 B | 1,000,000 | `3641797497992649622` |
| explicit map, 4 domains | 20.204 ms | 41,026,520 B | 0 B | 41,000,056 B | 1,000,000 | `3641797497992649622` |
| explicit map + outputs, 1 domain | 42.876 ms | 50,256,192 B | 0 B | 50,000,080 B | 1,000,000 | `4418888185184027992` |
| explicit map + outputs, 4 domains | 27.201 ms | 50,310,120 B | 0 B | 50,000,080 B | 1,000,000 | `4418888185184027992` |
| plane nearest, 1 domain | 390.338 ms | 186,009,880 B | 2,784 B | 90,002,952 B | 1,000,000 | `1685776360115969791` |
| plane nearest, 4 domains | 147.139 ms | 137,822,768 B | 20,848 B | 90,021,016 B | 1,000,000 | `1685776360115969791` |
| unchecked explicit-copy reference, 1 domain | 10.313 ms | 32,000,904 B | 0 B | 32,000,032 B | 1,000,000 | `3641797497992649622` |

The unchecked reference knows the exact Float4 field and valid mapping in
advance. It omits attribute-pattern discovery, group/owner/cardinality checks,
mapping validation, general storage dispatch, cancellation, transform/text
policy, and atomic metadata replacement. Its identical hash verifies the
production explicit path against that retained lower bound. The first general
implementation unconditionally allocated pair, source-side, destination-side,
and output-map planes even for an ordinary copy: an exploratory development
profile measured 38.325 ms and 58,000,088 major bytes. Building only the stable
source map plus one destination bit-plane, and materializing pair/source output
metadata only when requested, reduced the ordinary major floor by 29.3% to
41,000,056 bytes. Compacting the plane query set to destination-side elements
adds 4 MB of destination-index/query scratch but reduced the release median from
500.626 to 390.338 ms on one domain and from 179.623 to 147.139 ms on four,
without changing the hash. Four domains improve final explicit mapping by
1.58x and spatial plane matching by 2.65x. The plane path remains intentionally
index-dominated; replacing it with coordinate bucketing would weaken arbitrary
plane/tolerance nearest semantics.

Direct tests cover every storage kind, UV/vector/point transforms, literal text
replacement, source/destination restriction and metadata, point/vertex/
primitive mapping, primitive plane centers, invalid values and cancellation,
no-op topology sharing, and exact one/four-domain output. The SOP suite covers
static cache identity and cook-time group diagnostics. A dedicated asymmetric
surface export compares byte-identical one-/four-domain PNGs and verifies that
the mirrored framebuffer differs from the source.

```sh
RAYS_RDK_OPS_COLUMNS=1000 RAYS_RDK_OPS_ROWS=1000 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=attribute_mirror RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use attribute_mirror_reference for the
# deliberately unchecked copy-only lower bound.
```

## Rewire Vertices SOP baseline

Rewire Vertices uses 999,999 uniquely referenced points/corners arranged as
333,333 triangles. One third of the point-owned integer targets redirect their
corner to the next point. The direct row keeps unused points for an exact
comparison with the retained unchecked topology-copy reference. Cleanup deletes
the newly unused third, deletes the target field, and emits all-corner original
point provenance. Recursive mode follows four-point chains while retaining
point cardinality. Numbers are seven-run release-profile medians with OCaml
5.3.0, Dune 3.24.0, grain 16,384, Linux 6.8/aarch64, and four available Apple
CPU cores.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| direct, 1 domain | 5.724 ms | 11,002,456 B | 0 B | 11,000,024 B | 2,333,331 | `288734399921472577` |
| direct, 4 domains | 3.920 ms | 11,017,616 B | 0 B | 11,000,024 B | 2,333,331 | `288734399921472577` |
| cleanup + provenance, 1 domain | 33.208 ms | 50,336,416 B | 0 B | 50,333,384 B | 1,999,998 | `2351447017972365808` |
| cleanup + provenance, 4 domains | 27.513 ms | 50,392,688 B | 0 B | 50,333,384 B | 1,999,998 | `2351447017972365808` |
| recursive, 1 domain | 17.087 ms | 36,002,656 B | 0 B | 36,000,032 B | 2,333,331 | `3495472325552027740` |
| recursive, 4 domains | 15.147 ms | 36,017,520 B | 0 B | 36,000,032 B | 2,333,331 | `3495472325552027740` |
| unchecked direct reference, 1 domain | 3.612 ms | 11,001,824 B | 0 B | 11,000,024 B | 2,333,331 | `288734399921472577` |

The unchecked reference copies one known topology plane and directly reads one
known valid point integer field. It omits owner-dependent selection promotion,
invalid-target handling, recursion, original-point output, target deletion,
newly-unused cleanup, every-storage point/group compaction, corner-edge group
ancestry, stale-normal policy, validation, and cancellation. Its identical
hash and major floor provide an exact lower bound for direct mode.

The first general implementation measured 8.472 ms on one domain and 15.793 ms
on four because every changed corner contended on one atomic flag. Replacing
that flag with disjoint writes and one stable detection scan produced 7.520 and
7.186 ms. A subsequent allocation audit found owner-selection `Option` closures
being constructed per corner, causing 43,002,432 allocated bytes on one domain.
Hoisting the selection branch outside the corner loop produced the final
5.724/3.920 ms results and the exact 11,000,024-byte major floor with no
promoted garbage. Four domains improve direct, cleanup, and recursive paths by
1.46x, 1.21x, and 1.13x; the remaining recursive functional-graph and cleanup
prefix decisions are intentionally stable sequential passes.

Direct regressions cover point/vertex/primitive targets, promotion from every
typed selection owner including native edges, recursive chains and cycles,
invalid targets, target deletion, provenance, pre-existing free-point
preservation, fixed/ragged payload and group compaction, merged native-edge
union, stale normals, identity, malformed inputs, cancellation, and exact
one-/four-domain output. The SOP suite covers immutable identity, bounded cache
reuse, and cook-time diagnostics; a sculpted-grid export compares byte-identical
one-/four-domain PNGs and requires a visible difference from the source.

```sh
RAYS_RDK_OPS_COLUMNS=1000 RAYS_RDK_OPS_ROWS=1000 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=rewire_vertices RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use rewire_vertices_reference for the
# deliberately unchecked direct lower bound.
```

## Edge Transport SOP baseline

Edge Transport measures a 300,000-point open polygon curve twice: once through
the arbitrary Edge Network planner and once through the linear Each Curve path.
A second fixture contains 30,000 disjoint ten-point curves and measures Each
Curve plus forward and backward Edge Network traversal. Parent Attribute uses
30,000 ten-point trees in both already topologically ordered and reverse-numbered
forms. All runs use grain 16,384, seven release-profile medians, and constant
Total; distance rows scale by robust Euclidean edge length.

The retained serial reference knows it has exactly one forward open curve,
uses direct coordinate subtraction, and omits selection, topology, ownership,
rooting, closed-curve, normalization, cancellation, and finite validation. Its
different hash reflects the production kernel's scale-safe edge metric, not a
change in rendered fidelity.

| Path | Time | Allocated | Promoted | Major | Cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| network single, 1 domain | 20.965 ms | 27,001,776 B | 0 B | 27,000,104 B | 600,001 | `898688424706882948` |
| network single, 4 domains | 18.495 ms | 27,007,664 B | 0 B | 27,000,104 B | 600,001 | `898688424706882948` |
| Each Curve single, 1 domain | 6.024 ms | 2,401,080 B | 0 B | 2,400,008 B | 600,001 | `898688424706882948` |
| Each Curve single, 4 domains | 5.882 ms | 2,401,936 B | 0 B | 2,400,008 B | 600,001 | `898688424706882948` |
| Each Curve 30k curves, 1 domain | 6.475 ms | 6,001,048 B | 0 B | 4,800,016 B | 630,000 | `60481824834182347` |
| Each Curve 30k curves, 4 domains | 2.741 ms | 5,088,952 B | 0 B | 4,800,016 B | 630,000 | `60481824834182347` |
| network 30k components forward, 1 domain | 19.593 ms | 26,731,792 B | 0 B | 26,730,120 B | 630,000 | `1325500647425514973` |
| network 30k components forward, 4 domains | 17.920 ms | 26,736,416 B | 0 B | 26,730,120 B | 630,000 | `1325500647425514973` |
| network 30k components backward, 1 domain | 26.807 ms | 36,331,952 B | 0 B | 36,330,176 B | 630,000 | `2252116270756994525` |
| network 30k components backward, 4 domains | 24.462 ms | 36,343,152 B | 0 B | 36,330,176 B | 630,000 | `2252116270756994525` |
| Parent ordered forward, 1 domain | 3.811 ms | 2,400,880 B | 0 B | 2,400,008 B | 300,000 | `1380434282527042488` |
| Parent ordered forward, 4 domains | 3.824 ms | 2,401,080 B | 0 B | 2,400,008 B | 300,000 | `1380434282527042488` |
| Parent backward, 1 domain | 9.941 ms | 12,001,256 B | 0 B | 12,000,064 B | 300,000 | `3066036653996022544` |
| Parent backward, 4 domains | 8.824 ms | 12,012,528 B | 0 B | 12,000,064 B | 300,000 | `3066036653996022544` |
| Parent unordered forward, 1 domain | 10.906 ms | 14,401,384 B | 0 B | 14,400,072 B | 300,000 | `1601551353367740335` |
| Parent unordered forward, 4 domains | 8.272 ms | 14,416,168 B | 0 B | 14,400,072 B | 300,000 | `1601551353367740335` |
| unchecked curve serial reference | 1.225 ms | 2,400,488 B | 0 B | 2,400,008 B | 600,001 | `2578246034619385251` |
| unchecked Parent ordered reference | 1.145 ms | 2,400,600 B | 0 B | 2,400,008 B | 300,000 | `828081026953739822` |

The first correct network implementation measured 29.478 ms / 29,401,504 B on
one domain and 27.147 ms / 29,407,456 B on four. Removing a redundant constant
input plane and unconditional child-count plane, and recording the chosen tree
edge instead of hashing every parent pair, established the retained single-
network path. The first backward-network extension exposed a different
pre-existing scaling issue: a single global heap interleaved all 30,000
disconnected default-root components. Forward/backward measured 160.492/
169.834 ms on one domain and 159.594/168.152 ms on four. Draining each
independent component through its own heap reduced those times to 19.593/
26.807 ms (8.19x/6.34x) and 17.920/24.462 ms (8.91x/6.87x) without changing
any hash. Explicit multi-source groups retain the global stable heap.

The first correct Parent implementation measured 13.944 ms / 17,041,352 B
forward and 11.480 ms / 34,081,240 B backward on one domain. Borrowing the
validated integer parent plane, eliminating per-parent closures, and streaming
already ordered forward forests brought the common path to 3.811 ms and the
exact 2.40 MB output allocation. The general reverse-numbered planner is
10.906 ms on one domain and 8.272 ms on four; reverse branch evaluation is
9.941/8.824 ms. Hoisting the shared backward candidate evaluator is required:
leaving it nested in the point loop measurably allocated a closure per point.

The dedicated curve path remains the correct choice when primitive order
already supplies the desired traversal and allocates only the exact scalar
output for a single point-owned curve. Independent curves scale 2.36x from one
to four domains with an identical hash. A cold four-domain run from the earlier
network/curve baseline peaked at 97,584 KiB RSS. Direct and SOP tests cover
open/reversed/closed traversal, point and vertex fields, Edge Network/Parent
forward and backward flow, all scalar operations and merge policies, roots,
cycles, restrictions, normalization, malformed ownership/cardinality/finite/
parent inputs, cancellation, and exact one/four-domain output. The dedicated
framebuffer export compares forward and backward reliefs in one and four
domains against a flat control.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=edge_transport RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4; use edge_transport_reference or
# edge_transport_parent_reference for deliberately unchecked serial bounds.
```

## Convex Hull SOP baseline

Convex Hull measures five deterministic packed point distributions: one
million exact duplicates, one million collinear points, a cube containing one
million interior/boundary samples, a 4,096-point Fibonacci sphere whose every
point is extreme, and one million coplanar lattice points. Results are
three-run release-profile medians with OCaml 5.3.0, Dune 3.24.0, grain 16,384,
Linux 6.8/aarch64, and four available Apple CPU cores. Output hashes include
positions and ordered topology.

| Path | Domains | Time | Current-domain allocation | Promoted | Major | Output points/faces | Exact hash |
|---|---:|---:|---:|---:|---:|---:|---:|
| duplicates | 1 | 18.110 ms | 24,779,832 B | 0 B | 24,777,232 B | 1 / 0 | `2245658394896781073` |
| duplicates | 4 | 16.426 ms | 24,794,352 B | 0 B | 24,777,232 B | 1 / 0 | `2245658394896781073` |
| collinear | 1 | 421.834 ms | 320,779,672 B | 312 B | 32,777,552 B | 2 / 1 | `1075584037741368850` |
| collinear | 4 | 449.008 ms | 320,793,608 B | 1,344 B | 32,778,584 B | 2 / 1 | `1075584037741368850` |
| interior-heavy solid | 1 | 552.482 ms | 510,188,872 B | 68,704 B | 251,706,440 B | 9 / 14 | `2535793065159045267` |
| interior-heavy solid | 4 | 408.665 ms | 510,282,376 B | 81,952 B | 251,719,424 B | 9 / 14 | `2535793065159045267` |
| all-extreme sphere | 1 | 21.469 ms | 31,131,648 B | 1,164,336 B | 9,079,168 B | 4,096 / 8,188 | `2566989394337752059` |
| all-extreme sphere | 4 | 23.863 ms | 31,131,648 B | 1,164,336 B | 9,079,168 B | 4,096 / 8,188 | `2566989394337752059` |
| coplanar lattice | 1 | 1.596776 s | 476,933,528 B | 768 B | 64,778,040 B | 4 / 1 | `3561109759947142793` |
| coplanar lattice | 4 | 1.638320 s | 476,944,272 B | 1,784 B | 64,779,056 B | 4 / 1 | `3561109759947142793` |

The complete four-domain campaign peaked at 290,024 KiB RSS; the one-domain
campaign peaked at 275,200 KiB. The first interior-heavy implementation took
139.172 ms and allocated 266,071,984 bytes for only 100,008 points. Assigning
each conflict point to the first exactly visible face instead of scoring every
visible face, replacing boxed hash mixing and closure face scans, releasing
retired conflict arrays, and classifying a live buffer prefix directly reduced
the same fixture to 44.040 ms and 49,941,136 bytes. The topology hash changed
only because the legal conflict-face priority changed; every combinatorial
decision and the published result remain deterministic and exact-predicate
certified.

Four domains improve the million-point interior case by 1.35x. Duplicate,
collinear, planar monotone-chain sorting, and the dependent all-extreme horizon
sequence remain deliberately sequential and do not claim parallel speedup.
The collinear and planar allocation totals include adaptive exact-predicate
fallbacks for genuine zero determinants; they are reported rather than
replaced with a tolerance. Randomized tests verify every input against every
output face with exact predicates, closed incidence and Euler characteristic;
the SOP suite verifies cache identity and exact one/four-domain topology, and
the native framebuffer equals an explicit cube reference byte-for-byte.

```sh
RAYS_HULL_REPEATS=3 RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_convex_hull.exe
# Repeat with RAYS_BENCH_DOMAINS=4 and wrap either command in
# /usr/bin/time -v for peak RSS.
```

## Extract Centroid SOP baseline

Extract Centroid measures a deterministic million-point cloud and a
501,264-point triangle grid with 999,698 primitives. Consecutive triangle
pairs share one primitive integer piece, producing 499,849 unique-point piece
centers. Results are three-run release-profile medians under the same OCaml
5.3.0, Dune 3.24.0, Linux 6.8/aarch64, four-core, and grain-16,384 setup. Hashes
cover every output position and are exact across domain counts.

| Path | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| detail equal-point mass | 11.397 ms | 11.334 ms | 1.01x | 8.002/8.002 MB | 8.000/8.000 MB | `2142381322777950757` |
| detail bounding box | 7.296 ms | 7.237 ms | 1.01x | 8.002/8.002 MB | 8.000/8.000 MB | `2163296439784001847` |
| per-primitive bounding box | 41.348 ms | 24.761 ms | 1.67x | 135.961/79.233 MB | 55.983/56.032 MB | `1441361096299877289` |
| primitive-piece equal-point mass | 456.720 ms | 447.031 ms | 1.02x | 179.174/149.943 MB | 131.166/131.187 MB | `2510410779901382919` |

The first correct 100k-scale primitive-piece implementation used comparison
sorting and measured 66.549 ms with 28.375 MB allocated. Replacing it with a
stable fixed-pass non-negative integer radix sort and specializing integer/text
piece classification so integer identities are not boxed reduced the same
exact hash to 28.954 ms and 17.903 MB: 2.30x faster and 36.9% less allocation. Whole-detail
reductions stay sequential below their single-output grain; per-primitive
fills scale by 1.67x. Piece classification, unique-incidence radix planning,
and prefix construction remain serial and dominate the piece case, while its
center fills are parallel. This is reported as a bottleneck rather than a
parallel speedup claim.

The complete one-domain campaign peaked at 271,020 KiB RSS and four domains at
277,012 KiB. RDK tests cover lower-dimensional and solid hull centers, stable
integer/text identity, detail sharing, malformed input and cancellation; SOP
tests cover cache identity and exact domain output; the native framebuffer is
byte-identical to explicit reference centers.

```sh
RAYS_CENTROID_SIZE=1000000 RAYS_CENTROID_REPEATS=3 \
RAYS_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release tools/bench_extract_centroid.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

## Extract Point from Curve SOP baseline

The dedicated benchmark evaluates 1,001,000 points in 1,000 independently
ordered open polygon curves. Sparse input has one cut per curve; dense input
crosses on every edge; the payload case additionally interpolates one float and
one integer point field, copies an integer primitive field, and emits curve U,
cut count, and curve number. Results are five-run release-profile medians on
OCaml 5.3.0, Dune 3.24.0, Linux 6.8/aarch64, four Apple CPU cores, and grain
16,384. Hashes cover every output position and attribute.

| Path | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Major 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|---:|
| constant sparse, 1,000 cuts | 8.990 ms | 4.975 ms | 1.81x | 0.077/0.079 MB | 0/0 MB | `2773787659351257617` |
| constant dense, 1,000,000 cuts | 30.723 ms | 22.609 ms | 1.36x | 56.021/56.023 MB | 56.016/56.016 MB | `1447278196685623313` |
| varying dense + payload/diagnostics | 56.338 ms | 38.772 ms | 1.45x | 96.073/96.098 MB | 96.016/96.016 MB | `2465483108862112169` |

The first correct implementation boxed helper results in both edge passes,
boxed emitted weights/parameters, and allocated an `Option.iter` closure for
every output cut. Its three-run one-domain medians were 50.976 ms/64.317 MB,
78.192 ms/344.053 MB, and 105.467 ms/384.089 MB for the three rows above.
Inlining only arithmetic helpers was insufficient because the crossing helper
duplicated boxed expressions. Keeping the crossing decision directly in each
loop, writing output planes directly, and matching optional curve U without a
closure reduced the retained medians to the table above: sparse scan is 5.67x
faster, dense scan/materialization is 2.55x faster with 83.7% less allocation,
and the payload case is 1.87x faster with 75.0% less allocation. No promoted
bytes remain. Dense allocation now equals the exact output/provenance planes;
the payload row adds only requested output fields.

A separate one-curve campaign uses 1,000,001 points to prove that parallelism
does not rely on many primitives. Stable grain-sized edge blocks preserve the
same primitive/edge prefix order while exposing classification and fill work to
the shared pool.

| Single long curve | 1 domain | 4 domains | Speedup | Allocated 1d/4d | Exact hash |
|---|---:|---:|---:|---:|---:|
| constant sparse, one cut | 4.540 ms | 1.633 ms | 2.78x | 0.008/0.040 MB | `1239986401956846767` |
| constant dense, 1,000,000 cuts | 30.219 ms | 18.753 ms | 1.61x | 56.008/56.036 MB | `1445075866305253393` |
| varying dense + payload/diagnostics | 55.562 ms | 33.761 ms | 1.65x | 96.013/96.083 MB | `3415398291295564695` |

The 1,000-curve final campaigns peaked at 164,668 KiB RSS on one domain and
165,236 KiB on four; the single-curve campaigns peaked at 164,396/165,236 KiB.
RDK tests cover exact vertices, plateaus, crossings, open endpoints, closed
seams, primitive targets/selections, numeric/discrete/ragged payload, empty and malformed
input, non-finite values, `max_float` interpolation, cancellation, 100,000
small curves, and a 200,001-point blocked curve. SOP tests cover immutable
identity, static caching, current-time invalidation, errors, and exact domain
output. The native framebuffer is byte-identical across one/four domains and
to explicit reference cut points.

```sh
RAYS_EXTRACT_REPEATS=5 RAYS_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release \
  tools/bench_extract_point_curve.exe
# Repeat with RAYS_BENCH_DOMAINS=4. For the long-curve campaign add:
# RAYS_EXTRACT_CURVES=1 RAYS_EXTRACT_POINTS_PER_CURVE=1000001
```

## Workspace benches (W2-W11)

Apple M1, 8 cores, one run, default Dune profile unless noted; every number is a
median sample, not a claim of constant frame cost. Notes and analysis per
milestone are in `specification/workspace/progress.md`.

| Bench | Command | Recorded numbers |
|---|---|---|
| `bench_workspace_lower` | `dune exec tools/bench_workspace_lower.exe` | medians of 21, ms: Bloom check 0.09 / eval 0.12 / lower 1.5 / cook 1.0 (84 nodes); Sunflower 0.02 / 0.85 / 5.2 / 2.4 (241); Tiles 0.02 / 0.30 / 3.2 / 0.90 (193); Wave 0.02 / 3.2 / 7.7 / 0.85 (13). Also the session-capacity table (32 vs 512 entries: Sunflower warm 2.3 ms evicting, 0.21 ms held) |
| `bench_workspace_live` | `dune exec tools/bench_workspace_live.exe -- 600 1` (`BENCH_CASE=wave`, `BENCH_PROBES=1`) | total p50 per frame: Orrery 0.91 ms (52 volatile nodes), Wave 7.3 ms (`Eval.force` of 540 residuals is 5.7 ms of it: the case to watch, recorded not fixed), Sunflower static 0.26 ms, live 4.4 ms |
| `bench_workspace_zone` | `dune build test/test_main.exe && cd _build/default/test && ./test_main.exe bench_workspace_zone` | scatter of N points, a `for` zone over them: N=100 2.4 ms, N=1,000 29 ms, N=4,000 200 ms cold; the recook after one point moved costs about the same (expansion runs per element; 4 misses and N+1 hits with a 16,384-entry session; with the editor default of 512 entries the run misses on every element) |
| `bench_scope_pane` | same, `./test_main.exe bench_scope_pane` | per frame: flat pane over 241 nodes 0.13 ms and 503 KB; workspace pane Sunflower without records 0.26 ms / 696 KB, zone expanded 0.43 ms / 1.0 MB, collapsed 0.08 ms / 191 KB; Orrery 0.53 ms without records, 0.84 ms with live records; one recording evaluation 0.98 ms (Sunflower), 0.15 ms (Orrery), only when the checked source changes |
| `bench_viewport_pick` | same, `./test_main.exe bench_viewport_pick` | Sunflower (8,640 triangles): first pick with the BVH build 11 ms, later picks 0.002 ms, tint 0.7 ms, tint + `to_mesh` 3.9 ms (only when the highlight changes); Bloom (3,888 triangles) 3.7 ms first pick; `Cook.update` idle 0.0002-0.0004 ms |

The BVH build is about 1.3 us per triangle, so a 1M-triangle mesh hitches about a
second at its first click (`ponytail:` in `lib/rays_editor/pick.ml`).

Connection hover (2026-10-01): macOS 26.2, arm64, OCaml 5.3.0, default
Dune profile, UI work on the initial domain. Build `test/test_main.exe`, then
run `../_build/default/test/test_main.exe bench_scope_pane` from `test/`.
Each number below is one wall-time/GC-allocation aggregate of 300 frames after
20 warm-up frames. This measures the shared hit-tree rectangles for wire
segments, including culling, on the same layouts and input:

| Pane | Before ms/frame | After ms/frame | Before bytes/frame | After bytes/frame |
|---|---:|---:|---:|---:|
| Sunflower (240 iterations), no records | 0.281 | 0.318 | 697352 | 813824 |
| Sunflower, expanded zone and records | 0.467 | 0.494 | 1016216 | 1132688 |
| Sunflower, collapsed zone | 0.076 | 0.084 | 191504 | 227512 |
| Orrery, no records | 0.613 | 0.700 | 1505912 | 1729152 |
| Orrery, live records | 0.906 | 0.992 | 2049571 | 2272827 |

The complete editor usability change was measured on the same macOS 26.2 arm64
host, OCaml 5.3.0, default Dune profile, with one cook domain and UI work on the
initial domain. Build `tools/bench_rays_editor.exe`, then run
`_build/default/tools/bench_rays_editor.exe 200`. Each run measures 200 held
pointer updates of a 200-node workspace and one undo. The corrected workload
presses the node header, moves beyond the drag threshold, releases at the final
position and asserts that undo actually steps history. Each run uses its own
temporary preset directory, including the final code's periodic autosaves.

Before is HEAD `a0545f73` with only this corrected benchmark copied into it;
its build uses the pinned SDL 3.4.14 include/library directories. After is the
final editor change. Three standalone runs per version, with no concurrent test
or build process, gave these medians of run statistics:

| Check | Before | After | Bytes/frame before → after |
|---|---:|---:|---:|
| Held drag median | 4.143 ms | 6.325 ms | 5383904 → 6390677 |
| Held drag p95 | 4.589 ms | 6.777 ms | same |
| Undo (one sample/run) | 5.377 ms | 7.715 ms | 6719960 → 7726568 |

This measures the combined controls, connection hit boxes, panel handling,
composition and recovery behavior; it does not isolate a particular feature.
It is a measured cost increase, not a speedup or a native frame latency bound.
The native integration fixture uses 28 UI draw batches with the added header
controls; its fixed budget is 32. Native screenshot checks cover all three
render modes in docked, undocked and authored floating viewports.

The subsequent VIEW graph lookup fix retains the physical-identity fast path and
adds a compiled-root comparison when the lowering was rebuilt. One standalone
200-node benchmark run immediately before and after that fix measured drag
medians of 17.166 → 4.187 ms, p95 of 44.194 → 4.913 ms, and undo of
18.178 → 4.781 ms. Allocation was identical: 6390677 bytes/drag frame and
7726568 bytes/undo. No test or build ran concurrently with either measurement;
the timing variation in this single pair cannot establish a speedup or isolate
the lookup's cost. Use the same benchmark command above to reproduce the check.

## Editor consistency repair (2 October 2026)

macOS 26.2 arm64, OCaml 5.3.0, default Dune profile, one cook domain.
Command: `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200`. The workload is the
200-node held drag and real undo described above. Before reconstructs the
uncommitted tree at the start of this audit on HEAD `a0545f73`; after includes
the consistency fixes. Three alternating before/after pairs ran without
concurrent agent tests or builds. The desktop had other applications running.

| Check (median of run statistics) | Before | After | Bytes before → after |
|---|---:|---:|---:|
| Held drag median | 8.121 ms | 8.217 ms | 6390677 → 6402373 |
| Held drag p95 | 8.653 ms | 9.514 ms | same |
| Undo (one sample/run) | 9.785 ms | 9.786 ms | 7726568 → 7763968 |

Per-run drag medians were 6.381 / 10.340 / 8.121 ms before and
9.679 / 8.217 / 8.069 ms after; undo was 9.010 / 9.813 / 9.785 ms
before and 27.370 / 9.786 / 9.782 ms after. Timing noise prevents a
speedup or isolated regression claim. Allocation increased by 11696 bytes
per drag frame (0.18%) and 37400 bytes per undo (0.48%). This does not measure
path tracing throughput or scenes with many independent object owners.

The disposable baseline needed core SDL binding regeneration against the
installed SDK to pass its clean ABI build; no SDL files were changed in the
main tree. The window-free workload does not exercise the affected pen events.

## Source digest polling — 2 October 2026

Command: `dune exec tools/bench_source_poll.exe -- examples/sop_gallery/gallery.rays`.
Darwin arm64, OCaml 5.3.0, default Dune profile, initial domain, warm filesystem
cache. The largest checked-in `.rays` is 7800 bytes (all checked-in `.rays`
files total 32891 bytes). Five alternating samples of 2000 polls ran without
concurrent agent builds/tests. The reference measures the old unchanged-file
`Unix.stat` operation alone, omitting its small polling-record overhead; the
new measurement calls the actual `Source.poll` and asserts no reload.

| Sample | Stat reference (ms/poll) | Content/digest (ms/poll) |
|---|---:|---:|
| 1 | 0.001863 | 0.056281 |
| 2 | 0.001866 | 0.054431 |
| 3 | 0.001858 | 0.054413 |
| 4 | 0.001887 | 0.054577 |
| 5 | 0.001841 | 0.054358 |
| Median | 0.001863 | 0.054431 |

`Gc.allocated_bytes` measured 152 bytes/poll for the reference and 8672 for
content/digest in every sample. At 2 Hz the new measured work is approximately
0.109 ms and 17344 allocated bytes per second for this file. This supports
reading current small workspaces instead of relying on mtime; it does not
bound latency for large files, cold storage or network filesystems.

## Named-pane ownership lookup — 2 October 2026

Command: `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dune exec tools/bench_named_owner.exe`.
Darwin arm64, OCaml 5.3.0, default Dune profile, one cook domain; no concurrent
builds or tests. Each object owns a distinct one-node SOP graph. Navigation
stays at Scene while a named pane selects the last object's compiled box,
requiring the owner fallback. Five samples each measure 10,000 calls to the
actual public `Editor3.selected_node`, asserting the selected compiled ID.
Parsing, cooking and UI setup are outside the timed interval.

| Objects | Samples (ms/lookup) | Median | Bytes/lookup |
|---|---|---:|---:|
| 1 | 0.000271, 0.000281, 0.000281, 0.000275, 0.000268 | 0.000275 | 1504 |
| 100 | 0.001629, 0.001628, 0.001633, 0.001611, 0.001616 | 0.001628 | 1504 |
| 1000 | 0.015483, 0.015703, 0.015772, 0.015720, 0.015831 | 0.015720 | 1504 |

The current scan remains: three such lookups at 1,000 owners cost about
0.047 ms in this fixture. No index or hot-path behavior changed, so the
before and after algorithm are identical. This measures many small networks,
not arbitrary scene sizes or large individual networks; the existing
`ponytail:` comment retains the upgrade path to a compiled-ID owner index
if a real workload makes the fallback material.

## Live light contexts — 2 October 2026

Command: `SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy dune exec tools/bench_live_lights.exe`.
Before is a disposable archive of HEAD `b39ebd5be2230397ba1caa54b6d0faac8d984ec5`
with the same benchmark added; after is the consistency remediation tree.
macOS arm64, OCaml 5.3.0, default Dune profile, one cook domain, seed 42.
No builds/tests ran during measurement; other desktop applications remained active.
Each run warms ten frames then records five 200-frame sample means at fixed
1/60 s. One or sixteen scene refs share a box SOP but have independent lights.
The static control uses constant intensity/color; live expressions add a sine
pulse. Before accepted those expressions but froze them at zero. After
resolves only recorded light fields. Both versions assert that warm frames
do not call geometry preparation or drawing again.

| Views / fixture | Before sample means (ms/frame) | After sample means (ms/frame) | Before median | After median |
|---|---|---|---:|---:|
| 1 / static | 0.047725, 0.045760, 0.047030, 0.046301, 0.047020 | 0.047306, 0.045905, 0.046335, 0.046285, 0.046071 | 0.047020 | 0.046285 |
| 1 / live | 0.046220, 0.047134, 0.046284, 0.046716, 0.045764 | 0.082275, 0.084610, 0.080769, 0.081500, 0.082239 | 0.046284 | 0.082239 |
| 16 / static | 0.373405, 0.375075, 0.368875, 0.367219, 0.365450 | 0.374185, 0.368274, 0.366640, 0.365781, 0.368046 | 0.368875 | 0.368046 |
| 16 / live | 0.371876, 0.365975, 0.366530, 0.366311, 0.365285 | 0.818855, 0.816405, 0.818086, 0.820365, 0.820615 | 0.366311 | 0.818855 |

`Gc.allocated_bytes` median bytes/frame: before 215898 (1 view) / 1411538
(16 views), for both fixtures; after static 216547 / 1415067 and live
380076 / 2981903. Sample allocation drift comes from periodic editor bookkeeping.
The extra live cost includes light-node parameter application and per-view
scene recomposition; the checked port descriptors are retained at lowering,
and unchanged SOP/prepared/drawing caches remain reused. The fixture uses
`Scene3.empty` geometry drawings: it measures editor CPU composition with
lights, not GPU presentation, path tracing or a general latency bound.
Native rendering validation remains a separate gate.

## Material assignment (2026-10-02)

The new primitive material assignment kernel has no previous implementation
to compare. On the local macOS arm64 host, seven-trial medians in the default
Dune build were 10.348 ms / 12,004,552 allocated bytes for 100,000 primitives
and 19.028 ms / 24,004,552 bytes for 200,000. With a four-domain pool the
100,000-primitive median was 10.497 ms and the same allocations; the assignment
kernel is deliberately sequential. Model information was unavailable under
the session's filesystem/process restrictions.

```sh
dune exec tools/bench_material_assign.exe -- 100000 1
dune exec tools/bench_material_assign.exe -- 200000 1
dune exec tools/bench_material_assign.exe -- 100000 4
```

The benchmark assigns one surface over repeated valid triangle primitives;
it measures only the assignment, including its packed output allocation and
metadata validation. It does not measure Boolean cooking or rendering.

### Editor frame by panel instances (2026-10-05)

`dune exec tools/bench_rays_editor.exe -- --panels 200 800 2000` (window-free, `SDL_VIDEODRIVER=dummy`,
one domain, 300 idle frames with the pointer moving over the viewport; median seconds and bytes
allocated per `Editor3.update`). Layouts differ only in the number of graph panels (a tile over one
graph) and inspectors.

| Layout | 200 nodes | 800 nodes | 2000 nodes |
|---|---|---|---|
| 1 graph, 1 inspector | 1.33 ms, 5.3 MB | 4.88 ms, 17.1 MB | 6.95 ms, 25.6 MB |
| 3 graphs, 1 inspector | 2.58 ms, 9.8 MB | 7.01 ms, 27.0 MB | 11.7 ms, 48.2 MB |
| 1 graph, 2 inspectors | 1.50 ms, 5.7 MB | 5.28 ms, 17.5 MB | 7.05 ms, 26.1 MB |
| 3 graphs, 2 inspectors | 2.78 ms, 10.2 MB | 7.29 ms, 27.4 MB | 12.1 ms, 48.7 MB |

A second inspector costs 0.1 to 0.4 ms. Each further graph panel costs its own canvas, linear in
panels.

The one-graph idle frame was 3.09 ms / 16.0 ms / 23.6 ms (200 / 800 / 2000 nodes) before two fixes
found by sampling it (`sample <pid>` on the running bench):

- `Pxui.Ui.hit_within` walked the hovered box's ancestors with one linear scan of the hit list per
  step, and every card, port and wire of a canvas asks it (`Ui.hovered_within`): quadratic in cards,
  41% of the frame at 800 nodes. The chain of the last key asked about is kept until the hit list is
  rebuilt: 16.0 to 9.8 ms.
- `Pxui.Theme.ports` parsed eight `#rrggbb` texts per call and the canvas calls it per port: the two
  palettes are parsed once. 9.8 to 5.1 ms.

`rays_editor_drag_frame` (`dune exec tools/bench_rays_editor.exe -- 200 1000 2000`) is 1.58 / 6.49 /
10.1 ms after them; at 200 nodes it was 4.0 ms.

The bench graph is layers of `sop/switch`, not `sop/merge`: a merge of two nodes of the layer
before doubles the geometry every layer, 2^30 points at 2000 nodes (1.45 GB of heap after the first
awaited frame at 1200 nodes, and the process killed at 2000). The drag bench also takes a card from
any layer, since a graph this wide opens with its last layer outside the pane.

What a frame still pays per card, whether it changed or not (25 MB allocated per idle frame at 2000
nodes), in the order the sampler shows it: the major GC marking that garbage, polymorphic compare,
the batch's quads for every card and wire, the wire segments, `Printf` for box keys and labels, the
key hashing. Removing those means culling cards outside the pane before they are built and keeping
a card's boxes and wire geometry between frames, which is a change to `Pxui_graph.Scope`'s frame
model and was not started here.

## Phase 4: one checked lowering and one recording evaluation (2026-10-07)

Same machine, profile, commands and sample counts as the Phase 4 baseline
above. `Contexts.of_workspace` now calls `Lower.of_checked`, without rebuilding
the catalog or rechecking the source. Graph probes reuse the recording evaluation
that lowering retains. A rename regression asserts exactly one check, evaluation
and lowering; checked lowering on each of the 12 fixtures asserts zero checks,
one evaluation and one lowering. Fixture plans, instances, results and records
are compared at 0, 0.125, 1.25 and 7, including float bits and the non-recording
reference evaluation.

Function objects in recorded values are compared by their presence; their call
results and numeric payloads are compared exactly. This focused regression does
not replace the whole-item interpreter/IR value and pixel gates.

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.112 | 6.210 | 9.939 | 15,464,262 |
| 1,000 | 7.318 | 31.925 | 57.937 | 66,493,208 |
| 2,000 | 12.631 | 76.226 | 176.190 | 120,477,852 |

The 2,000-node scrub still exceeds its 12.631 ms drag target. This completes
Step 1's shared-check/evaluation subtask, not its literal fast path or the
whole edit-loop gate. There is no claim of a statistically significant speed
improvement at 2,000 nodes from these single benchmark runs.

Exclusive scrub phase medians at 2,000 nodes, ms: print 12.576, parse 2.676,
check 5.766, evaluate 2.803, lower 8.286, project 6.402, layout 12.789,
reduce 0.322, cook boundary 8.864.

Workspace remeasurement (same standalone convenience API, which still checks
its source; its lowering now retains recording data), seven repeats:

| Fixture | Check ms | Eval ms | Lower ms | Cold cook ms | Lower + cook ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| bloom | 0.090 | 0.116 | 3.616 | 1.066 | 5.576 |
| facade | 0.041 | 0.081 | 1.942 | 0.588 | 2.577 |
| garland | 0.072 | 0.077 | 2.488 | 1.025 | 3.211 |
| kit | 0.065 | 0.033 | 0.886 | 0.089 | 1.054 |
| orrery | 0.051 | 0.147 | 2.210 | 0.423 | 3.000 |
| rosette | 0.046 | 0.045 | 2.122 | 0.467 | 3.056 |
| sunflower | 0.021 | 1.159 | 10.796 | 2.276 | 14.689 |
| tiles | 0.028 | 0.348 | 7.585 | 0.906 | 9.331 |
| tree | 0.023 | 0.017 | 2.051 | 0.426 | 2.182 |
| tunnel | 0.013 | 0.022 | 1.610 | 4.630 | 5.910 |
| variations | 0.041 | 0.021 | 0.714 | 0.209 | 1.368 |
| wave | 0.024 | 4.577 | 7.538 | 1.241 | 12.703 |

Node counts, standalone non-recording evaluation bytes, retained entries and
payload MB are unchanged from the baseline. At capacity 512, warm cook medians
are bloom 0.035 ms, sunflower 0.189 ms, wave 0.031 ms and tree 0.020 ms.
Recorded data increases retained evaluator memory (wave live heap after the
capacity-512 cook: 4.73 MB versus 4.02 MB); it replaces a second recording
evaluation in the editor.

## Phase 4: viewport previews outside the document (2026-10-07)

`v` now carries a per-object lexical preview into the cook. It leaves source,
layout and undo history unchanged. Static loops use the selected plan node;
geometry loops add a scratch zone that expands only the selected element.
Nested zones retain their captures and the complete selector tuple. Live
arguments and folds use the environment's frame and fold snapshot. The
authored network stays connected for off-display probes. Preview roots occupy
volatile session slots and are removed from that set when the request changes.
The node flag changes without projection or layout.

Checks cover unused bindings with different captures, nested point loops,
geometry loops inside static loops, piece loops, missing elements, live folds,
one/three-domain exactness, source/history identity, framing and picking. The
full `--ship` check and native Shattered Cube VIEW regression pass. The native
regression now edits the original anonymous result at `@result`; previewing
the box no longer invents a binding for that result.

Same machine, OCaml version, development profile and one-domain editor setup
as above. Commands ran sequentially, with 200 edit samples per size:

```sh
_build/default/tools/bench_rays_editor.exe 200 1000 2000
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 7
```

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.122 | 6.168 | 10.069 | 15,480,086 |
| 1,000 | 7.333 | 33.508 | 62.024 | 66,553,832 |
| 2,000 | 12.415 | 68.178 | 145.885 | 120,594,475 |

The scrub target remains unmet. These single runs do not establish a speed
improvement from the preview change. Exclusive 2,000-node phase medians, ms:
print 10.496, parse 2.733, check 5.329, evaluate 2.766, lower 7.777,
project 6.084, layout 11.763, reduce 0.322, cook boundary 8.535.

| Fixture | Check ms | Eval ms | Lower ms | Cold cook ms | Lower + cook ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| bloom | 0.096 | 0.123 | 3.806 | 1.292 | 5.344 |
| facade | 0.036 | 0.079 | 1.867 | 0.541 | 2.450 |
| garland | 0.074 | 0.077 | 2.353 | 0.872 | 3.464 |
| kit | 0.063 | 0.032 | 1.096 | 0.126 | 1.154 |
| orrery | 0.050 | 0.147 | 2.262 | 0.936 | 2.839 |
| rosette | 0.048 | 0.045 | 2.147 | 0.350 | 2.649 |
| sunflower | 0.019 | 0.959 | 10.679 | 2.574 | 13.221 |
| tiles | 0.024 | 0.325 | 7.859 | 0.932 | 9.376 |
| tree | 0.023 | 0.017 | 1.644 | 0.588 | 2.098 |
| tunnel | 0.013 | 0.022 | 1.645 | 4.802 | 5.598 |
| variations | 0.037 | 0.019 | 0.742 | 0.171 | 0.973 |
| wave | 0.024 | 4.351 | 7.976 | 1.315 | 13.621 |

Node counts, standalone evaluation bytes, retained entries and payload MB
remain unchanged. Capacity-512 warm cooks are bloom 0.035 ms, sunflower
0.190 ms, wave 0.030 ms and tree 0.020 ms.

### Phase 4 catalog literal patch checkpoint (2026-10-07)

Same Apple M1, OCaml 5.3, development profile and one-domain editor setup.
After `--ship`, with no concurrent validation, 200 samples per size:

```sh
_build/default/tools/bench_rays_editor.exe 200 1000 2000
```

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.163 | 1.963 | 3.190 | 6,416,049 |
| 1,000 | 7.156 | 7.396 | 12.870 | 16,819,904 |
| 2,000 | 12.354 | 12.664 | 21.768 | 24,894,176 |

The 2,000-node scrub was 68.178 ms and 120,594,475 bytes/frame at the preview
checkpoint. The strict scrub-at-most-drag target remains unmet at 1,000 and
2,000 nodes. These figures are a single sequential run; raw CSV is
`/tmp/rays-step1-literal-verified-editor.csv`. Exclusive scrub phase medians
for print, parse, check, evaluate, lower, project and layout are all zero;
reduce/cook are 0.024/0.094 ms, 0.133/0.838 ms and 0.290/2.021 ms respectively.
The full frame time includes uninstrumented source patching, document assembly
and painting. Phase zeroes alone do not establish the latency gate.

The source patch preserves authored IDs, repairs spans and patches typed
catalog arguments, using the same parameter validator as the full workspace
check. Static SOP arguments patch all compiled instances, retaining the plan's
topology, records and liveness. The pane changes existing rows and retains
boxes, ports, selection and routes. A bounded patch lineage handles several
edits between frames, undo and changes to literal spelling. Geometry templates,
folds and non-SOP values still use full lowering. The global source/term walks
remain; the broader Step 1 work and its budget are still required.

A temporary cook-boundary profile found 1.865 ms compiling and 3.721 ms after
scheduling at 2,000 nodes. Probe lookup was walking the displayed graph for
each of up to 64 nodes before consulting the compiled table. Looking up the
compiled node first reduced the cook-boundary median from 5.606 to 2.021 ms.
Document network equality now short-circuits at the first changed node and
does not materialize field summaries for physically unchanged nodes.

`test_workspace_doc` compares fast/slow saved bytes, plans, probe records,
projection rows and cooked geometry at one and three domains; it also checks
comments, vector components, static loops, template fallback, invalid choices
and colours, merged edits, undo deltas, spelling-only changes and unchanged
pane geometry. The editor regression checks zero print/parse/check/evaluation/
lower/projection/layout calls. `--ship` passes with the intended API additions
promoted. The full checked-in-file scrub sweep remains outstanding.

### Phase 4 structural projection reuse checkpoint (2026-10-07)

Structural edits now remap layout and validate surviving authored keys without
projecting the whole workspace. The pane compares its graph's authored content,
checked types, live/invariant paths and macro environment before invalidating
its projection. `test_workspace_doc` checks a rename and removal in another
graph, preservation of graph-input layout, and a changed function return type
that invalidates an unchanged caller's projection. The editor test measures
zero projection calls for the unrelated rename. Focused checks and `--ship`
pass; the intended `Syntax.equal` and `Projection.same_graph` API additions are
promoted.

After `--ship`, the same sequential benchmark command and machine/profile as
above, with no concurrent validation, gives:

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.060 | 1.977 | 3.185 | 6,416,049 |
| 1,000 | 7.190 | 7.183 | 13.166 | 16,819,904 |
| 2,000 | 12.354 | 12.313 | 22.199 | 24,894,176 |

Raw CSV: `/tmp/rays-step1-projection-editor.csv`. Print, parse, check, evaluate,
lower, project and layout phase medians remain zero. Reduce/cook medians are
0.025/0.094 ms, 0.135/0.832 ms and 0.293/2.015 ms. This run meets the strict
median target at all three sizes, by only 0.007 ms at 1,000 and 0.041 ms at
2,000. The previous run was slightly above it; the change primarily concerns
structural edits and does not establish a robust scrub latency improvement.
Generic literals, template/fold/non-SOP lowering, text-pane scrubs, full file
coverage and the budget remain to complete Step 1.

### Phase 4 text-pane token scrub checkpoint (2026-10-07)

PXUI now reports the numeric token's pre-edit byte range alongside its live
scrub callback. The pane maps that range through the canonical printer's
form IDs to the innermost source card's `Set_arg`. An applied scrub patches
its cached text and span maps, keeping line breaks until release; release
restores canonical printing. An unapplied draft or stale source retains the
whole-text check/merge path. Saved layout and view metadata receive printed
IDs disjoint from the source, including after structural edits.

`test_text_pane` drives actual pointer gestures in Selection, Graph and
Document tabs. Initial and repeated static SOP scrubs, including a growing
token, have zero print, parse, check, evaluate, lower, project and layout
calls. Saved bytes match the full syntax-edit path; values above the hard
bound leave the document physically unchanged, recovery checks the retained
draft, and one document undo restores the complete drag. Pure token-mapping
checks cover vector components, loop bodies, value bindings, computed
arguments and anonymous cards. The Lisp patch test compares repaired spans
and bytes with the full printer, including UTF-8, comments, string escapes,
multiple edits and rejected overlapping/invalid replacements. PXUI's
interaction test checks the pre-edit token span at one and two pixel scales.

Focused checks and `--ship` pass with the intended APIs promoted. These are
pipeline-call and correctness checks; no new native text-pane latency figure
is claimed. Broader literal/fold/template/non-SOP coverage and the frame
budget remain required.

### Phase 4 authored-call literal scrub checkpoint (2026-10-07)

Numeric Vec3 component edits now retain the fast path across Int/Float
spellings. Boolean vector replacements, including component edits, use
the checker's rejection. Evaluation records the originating syntax ID by
plan node ID, outside the semantic plan. Parameter edits can therefore
patch anonymous nested SOP calls, thread steps, defn copies and graph
overrides without changing plan identities or touching an unrelated call
of the same kind. Recorded functions still use full lowering until their
captured checked bodies can be rebound; this conservative fallback is tested.

`test_workspace_doc` compares these cases with full-path saved bytes, plans
and cooked geometry at one and three domains, with zero check/parse/evaluate/
lower calls for the supported cases. The 12 evaluator fixtures check that
authored IDs align with node IDs, reference their checked source and survive
forcing. `--ship` passes with the intended evaluation metadata API promoted.

After shipping checks, the same sequential command, machine and profile as
the earlier baseline, with no concurrent validation, gives:

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.062 | 1.954 | 3.216 | 6,424,192 |
| 1,000 | 7.191 | 7.078 | 13.069 | 16,860,047 |
| 2,000 | 12.338 | 11.969 | 22.230 | 24,974,319 |

Raw CSV: `/tmp/rays-step1-authored-editor.csv`, from
`SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200 1000 2000`.
Print, parse, check, evaluate, lower, project and layout medians remain zero;
reduce/cook medians are 0.024/0.093, 0.133/0.828 and 0.289/1.993 ms.
The median target is met for this static SOP workload in this run. The
small differences between runs do not establish a robust speed improvement;
generic values, captures, geometry templates, folds, file coverage and the
frame budget remain outstanding.

### Phase 4 open names checkpoint (2026-10-07)

Same Apple M1, OCaml 5.3, development profile, eight available domains and
one-domain editor. These runs are sequential, with no concurrent validation.
The before lowering executable predates the open-name migration; it was run
before rebuilding it. Seven-trial fixture medians:

| Fixture | Check before/after ms | Eval before/after ms | Lower before/after ms | Cold cook before/after ms | Total before/after ms | Nodes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| bloom | 0.103 / 0.092 | 0.133 / 0.123 | 3.984 / 3.562 | 1.202 / 1.201 | 5.817 / 5.656 | 84 |
| facade | 0.038 / 0.037 | 0.090 / 0.085 | 1.926 / 1.778 | 0.628 / 0.584 | 2.533 / 2.445 | 69 |
| garland | 0.077 / 0.074 | 0.087 / 0.084 | 2.312 / 2.167 | 0.846 / 0.825 | 3.139 / 2.881 | 40 |
| kit | 0.071 / 0.065 | 0.034 / 0.033 | 0.936 / 0.907 | 0.089 / 0.084 | 1.176 / 1.153 | 24 |
| orrery | 0.050 / 0.050 | 0.150 / 0.155 | 2.022 / 2.050 | 0.481 / 0.504 | 2.698 / 2.806 | 56 |
| rosette | 0.046 / 0.046 | 0.047 / 0.047 | 2.051 / 2.165 | 0.481 / 0.484 | 2.441 / 2.522 | 39 |
| sunflower | 0.020 / 0.020 | 1.003 / 1.047 | 10.289 / 10.110 | 2.057 / 2.184 | 13.341 / 13.523 | 241 |
| tiles | 0.027 / 0.026 | 0.319 / 0.344 | 7.125 / 7.476 | 0.991 / 0.918 | 8.776 / 9.073 | 193 |
| tree | 0.023 / 0.026 | 0.018 / 0.019 | 1.574 / 1.671 | 0.609 / 0.402 | 2.044 / 2.130 | 27 |
| tunnel | 0.013 / 0.014 | 0.023 / 0.024 | 1.539 / 1.559 | 3.795 / 4.154 | 4.986 / 6.388 | 37 |
| variations | 0.038 / 0.039 | 0.019 / 0.021 | 0.707 / 0.791 | 0.161 / 0.162 | 0.907 / 0.978 | 30 |
| wave | 0.025 / 0.025 | 4.241 / 4.373 | 7.193 / 7.615 | 1.052 / 1.086 | 12.362 / 13.921 | 13 |

Node counts, retained entries, evictions and payload MB match the before run.
Capacity-512 retained entries/payload MB remain bloom 52/1.22, sunflower
241/1.84, wave 13/0.66, tree 27/0.87. Evaluation allocations increase:
bloom 527,736 to 536,896 bytes, sunflower 4,439,440 to 4,500,968, wave
16,914,888 to 17,140,192. An intermediate version allocated more due to a
per-call operator lookup closure; removing it reduced wave from 18,039,584
bytes to the final count. Timing variation does not prove a speed improvement.

The benchmark now also fingerprints cooked positions, topology, attributes,
groups and edge groups, excluding allocation identities and derived caches.
It compares two cold sessions per fixture to check independence from allocation
identities. The before executable did not report cook hashes, so a historical
before/after hash comparison for Step 2 is missing. Current hashes, for the
following steps, are:

| Fixture | Cook hash |
| --- | --- |
| bloom | `dad16cdd4d91e532756c1d0d0667d207` |
| facade | `df9fdd4891bcaf471beeae7f34f26ab5` |
| garland | `bf4f98a940ac9bfe37a0abd2c1100df4` |
| kit | `23ea245dac862ed7b9dda2f8a7649322` |
| orrery | `4e38b6104e25800d415c4d2291337f37` |
| rosette | `18188829904e74c61fd34e367ae74150` |
| sunflower | `59a7b71c83f1057dc32bf6e90babb99d` |
| tiles | `9c7c72bc41d7365e6cd11fe394eb5120` |
| tree | `23e6fdd7f6252e15e705529856f86949` |
| tunnel | `6354bb27591a11d27519c20d0766a9b0` |
| variations | `4c4dda18df1d2cc685970d4e2461ca92` |
| wave | `70c3b661ce4166f563fd5c17329b821c` |

Editor, 200 samples per size, same command as Step 0:

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.081 | 2.048 | 3.275 | 6,549,216 |
| 1,000 | 7.305 | 7.705 | 13.755 | 17,095,263 |
| 2,000 | 12.195 | 12.381 | 22.272 | 25,209,535 |

The strict scrub target is unmet at 1,000 and 2,000 nodes. Print, parse,
check, evaluate, lower, project and layout phase medians remain zero for
this static SOP workload. Reduce/cook medians are 0.025/0.096,
0.138/0.845 and 0.295/2.013 ms. Generic literal, captured function,
non-SOP/template/fold lowering, checked-in-file coverage and budget work
remain required.

Dynamic 10,000-particle median/p95 are 33.344/34.023 ms and allocations are
154,287,359 bytes/frame, versus Step 0's 31.690/32.145 ms and 148,126,467
bytes. RDK 1M-point noise medians are 24.875 ms at one domain and 6.134 ms
at eight domains, allocating 32,064,368 and 32,074,064 bytes. Its xyz hash
remains `1a9b19459a403094e2683996bd183a75` at both domain counts. The RDK
implementation is unchanged; the timings vary from Step 0's 55.700/8.737 ms.

Raw outputs: `/tmp/rays-step2-lower-before.csv`,
`/tmp/rays-step2-lower-after.csv`, `/tmp/rays-step2-editor.csv`,
`/tmp/rays-step2-particles.csv`, `/tmp/rays-step2-kernel.csv`.
`@all` and `@runtest` pass with dummy SDL video/audio; the toy-domain test
checks the checker, evaluator, colored card/menu, editor insertion, help,
completion and reload. The Step 2 `--ship` attempt fails native smoke:
SDL reports that the video driver did not add any displays in this restricted
session. Native presentation remains unverified; the portable run does not
replace it. Existing test hosts also log refused autosave writes to `~/.rays`;
those checks pass, and the new domain test uses a temporary preset directory.

### Phase 4 kernel facts and component cache checkpoint (2026-10-07)

Same Apple M1, OCaml 5.3, development profile, eight available domains and
one-domain editor setup as Step 2. Benchmarks ran sequentially. The before
columns below are the Step 2 checkpoint; the after columns use
`_build/default/tools/bench_workspace_lower.exe
_build/default/specification/workspace/cases 7` after Step 3.

| Fixture | Check before/after ms | Eval before/after ms | Lower before/after ms | Cold cook before/after ms | Total before/after ms | Nodes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| bloom | 0.092 / 0.093 | 0.123 / 0.124 | 3.562 / 3.681 | 1.201 / 1.123 | 5.656 / 5.527 | 84 |
| facade | 0.037 / 0.037 | 0.085 / 0.083 | 1.778 / 1.819 | 0.584 / 0.718 | 2.445 / 2.668 | 69 |
| garland | 0.074 / 0.077 | 0.084 / 0.086 | 2.167 / 2.377 | 0.825 / 0.996 | 2.881 / 3.309 | 40 |
| kit | 0.065 / 0.067 | 0.033 / 0.034 | 0.907 / 1.024 | 0.084 / 0.147 | 1.153 / 1.176 | 24 |
| orrery | 0.050 / 0.051 | 0.155 / 0.155 | 2.050 / 2.262 | 0.504 / 0.525 | 2.806 / 3.004 | 56 |
| rosette | 0.046 / 0.046 | 0.047 / 0.049 | 2.165 / 2.310 | 0.484 / 0.389 | 2.522 / 2.989 | 39 |
| sunflower | 0.020 / 0.020 | 1.047 / 1.144 | 10.110 / 10.791 | 2.184 / 2.379 | 13.523 / 13.618 | 241 |
| tiles | 0.026 / 0.025 | 0.344 / 0.430 | 7.476 / 7.371 | 0.918 / 1.020 | 9.073 / 8.848 | 193 |
| tree | 0.026 / 0.023 | 0.019 / 0.019 | 1.671 / 1.642 | 0.402 / 0.564 | 2.130 / 2.202 | 27 |
| tunnel | 0.014 / 0.014 | 0.024 / 0.024 | 1.559 / 1.590 | 4.154 / 3.605 | 6.388 / 5.464 | 37 |
| variations | 0.039 / 0.038 | 0.021 / 0.020 | 0.791 / 0.773 | 0.162 / 0.158 | 0.978 / 1.021 | 30 |
| wave | 0.025 / 0.026 | 4.373 / 4.285 | 7.615 / 7.624 | 1.086 / 1.120 | 13.921 / 13.276 | 13 |

All twelve cook hashes match the Step 2 table above, as do evaluation
allocations, node counts, retained entries, evictions and payload MB.
Capacity-512 retained entries/payload remain bloom 52/1.22, sunflower
241/1.84, wave 13/0.66 and tree 27/0.87. Their warm medians increase from
0.035/0.182/0.030/0.021 ms to 0.048/0.296/0.036/0.032 ms. Metadata is now
encoded once at node construction, but that does not establish a warm-path
speed improvement. This overhead remains visible in the measurements.

The focused component-cache test proves a color-only upstream edit skips
the transform or normal computation while carrying the fresh color through.
Reads include position/attribute component IDs; topology, groups and
attribute owner/name order remain conservative dependencies. Additions,
removals and reordering recook. Output refresh preserves computed payloads,
untouched owners, output ordering and current inherited diagnostics, including
expanded-zone body diagnostics. The ten annotated preserved-topology factories
keep topology physically and produce identical authored bytes at one/eight
domains. False topology, writes, group mutation and packed output are refused
with traced `E_NODE_FACTS`. LRU payload reference counts are checked after
refresh and eviction; volatile slots retain their existing separate accounting.

Editor command:
`SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
_build/default/tools/bench_rays_editor.exe 200 1000 2000`, 200 samples per size.

| Nodes | Drag median ms before/after | Scrub median ms before/after | Scrub p95 ms after | Scrub bytes/frame after |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.081 / 2.048 | 2.048 / 2.006 | 3.142 | 6,548,133 |
| 1,000 | 7.305 / 7.159 | 7.705 / 7.825 | 12.922 | 17,111,231 |
| 2,000 | 12.195 / 11.942 | 12.381 / 12.311 | 22.470 | 25,274,250 |

The strict median target remains unmet at 1,000 and 2,000 nodes. The seven
print/parse/check/evaluate/lower/project/layout phase medians remain zero for
the static SOP scrub workload. Reduce/cook medians are 0.025/0.095,
0.133/0.843 and 0.290/2.075 ms. Remaining Step 1 paths and the Step 4 IR
are still required; this checkpoint does not satisfy the whole-item gate.

Dynamic particles use
`SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy
_build/default/test/test_drawing.exe examples/particles/sketch.rays --bench`.
Median/p95 are 33.282/34.107 ms versus Step 2's 33.344/34.023, with unchanged
154,287,359 bytes/frame. `tools/bench_kernel.exe` records RDK 1M-point noise
at 25.009 ms on one domain and 5.831 ms on eight, allocating 32,064,368 and
32,074,288 bytes. Both retain hash `1a9b19459a403094e2683996bd183a75`.
The Lisp-kernel comparison is not implemented yet.

Raw outputs: `/tmp/rays-step3-lower-verified.csv`,
`/tmp/rays-step3-editor-encoded.csv`, `/tmp/rays-step3-particles.csv`,
`/tmp/rays-step3-kernel.csv`. Earlier diagnostic measurements remain in
`/tmp/rays-step3-lower-after.csv`, `/tmp/rays-step3-lower-encoded.csv` and
`/tmp/rays-step3-editor.csv`. Window-free `@all` and `@runtest` pass; catalog,
API and generated-ML digest changes are reviewed and promoted. The native
smoke/display gate remains unavailable in this restricted session.

### Phase 4 IR and packed arithmetic checkpoint (2026-10-07)

Same Apple M1, OCaml 5.3 development profile and eight available domains.
`flow_ir` depends only on `flow`, `param`, `rays_math`; the dependency gate
now checks 50 libraries, 51 rules, 16 whitelists and no listed exceptions.
It retains typed counts, frame/event rates, precision, authored provenance
and specialized kernel bodies. Dynamic cardinality origins include instance
identity; distinct overrides cannot fuse by a coincident lexical path.
Sharing excludes catalog calls, state reads and reference closures. Hoisting,
dead-node removal, scalar fusion-group discovery and precision placement have
direct tests. Potentially failing unused bindings remain roots. Group timing,
packed cross-map fusion and SOP-fact-driven placement remain unimplemented.

The value lane prepares programs once per network; existing scalar closures
remain its scalar tier. Supported arithmetic float/vec3 maps compile into
float registers, with 1,024-element blocks distributed by the shared pool.
The current scratch ceiling is 64 registers (512 KiB per block); unsupported
bodies keep reference evaluation. Source and uniform values resolve outside
worker blocks. Probes use the tree walker without a process-wide toggle.
Live packed maps and collecting loops now defer instead of storing residual
boxes as numbers. Reference packed operations budget each block independently
and restore the enclosing counter. Tests admit large arrays and still refuse
an expensive block with `E_EVAL_BUDGET`; element and arithmetic order are unchanged.
`exact` is one identity/readback operator record with graph projection and
`Set_arg` coverage. Direct IR tests reject approximate catalog/export/state/cache
inputs with `E_APPROX_SINK`; there is no approximate Lisp producer.

`_build/default/tools/bench_kernel.exe` reports seven-run medians:

| Body / points | Tier | Domains | Median ms | Bytes, all domains | Hash |
| --- | --- | ---: | ---: | ---: | --- |
| native 2D noise / 1,000,000 | RDK | 1 | 25.003 | 32,064,480 | `1a9b19459a403094e2683996bd183a75` |
| native 2D noise / 1,000,000 | RDK | 8 | 6.543 | 32,108,792 | `1a9b19459a403094e2683996bd183a75` |
| arithmetic map / 1,024 | CPU | 1 | 0.021 | 60,176 | `e63ed5293fa431bf7804f8bfa1502a7e` |
| arithmetic map / 1,024 | CPU | 8 | 0.018 | 60,832 | `e63ed5293fa431bf7804f8bfa1502a7e` |
| arithmetic map / 1,024 | interpreter | 1 | 0.872 | 3,803,944 | `e63ed5293fa431bf7804f8bfa1502a7e` |
| arithmetic map / 65,536 | CPU | 1 | 0.977 | 3,679,904 | `fdde32a21528baae6e80fff535ececcf` |
| arithmetic map / 65,536 | CPU | 8 | 0.290 | 3,725,576 | `fdde32a21528baae6e80fff535ececcf` |
| arithmetic map / 65,536 | interpreter | 1 | 56.503 | 243,272,488 | `fdde32a21528baae6e80fff535ececcf` |
| arithmetic map / 1,000,000 | CPU | 1 | 14.829 | 56,133,648 | `c80bc2db40894ee77065598eb3a721f9` |
| arithmetic map / 1,000,000 | CPU | 8 | 3.454 | 56,841,024 | `c80bc2db40894ee77065598eb3a721f9` |
| arithmetic map / 1,000,000 | interpreter | 1 | 827.721 | 3,712,002,856 | `c80bc2db40894ee77065598eb3a721f9` |

The arithmetic body is `(sin (+ (* x 0.25) t))` at `t=1.25`, over
`array/range`; its hashes match the independent interpreter. Tests compare
every million-element output at one/eight domains. This is not the required
SOP/noise comparison: RDK's existing noise displace samples 2D x/z noise and
moves y, while the planned Lisp example samples 3D positions along normals.
That integration remains required. The new benchmark counts program-wide
allocation with `Gc.stat` outside the timed interval. Earlier checkpoint
`Gc.allocated_bytes` figures count the calling domain; eight-domain allocation
columns are not directly comparable to those earlier figures. Worker scratch
accounts for much of the map's allocation; no zero-allocation claim is made.

Sequential 50-frame wave runs before/after the value-lane integration:
resolve p50 1.259/1.129 ms, total p50 2.568/2.048 ms, total p99 7.431/53.003 ms.
The new cold program preparation remains visible in p99. A contended diagnostic
run was discarded; no broad playback speed claim follows from these short runs.

Editor command is the same window-free `bench_rays_editor.exe 200 1000 2000`
as Step 3, 200 samples per size:

| Nodes | Drag median ms before/after | Scrub median ms before/after | Scrub p95 ms after | Scrub bytes/frame after |
| ---: | ---: | ---: | ---: | ---: |
| 200 | 2.048 / 2.132 | 2.006 / 2.050 | 3.217 | 6,548,077 |
| 1,000 | 7.159 / 7.310 | 7.825 / 8.002 | 13.613 | 17,111,175 |
| 2,000 | 11.942 / 12.080 | 12.311 / 12.542 | 22.779 | 25,274,194 |

The strict target remains unmet at 1,000 and 2,000. Print, parse, check,
evaluate, lower, project and layout phase medians remain zero. Reduce/cook
medians are 0.026/0.099, 0.136/0.859 and 0.299/2.054 ms. Dynamic particles
remain on their existing evaluator path: 33.334/34.123 ms median/p95 and
154,288,351 bytes/frame versus Step 3's 33.282/34.107 and 154,287,359.
Their IR execution/pixel gate remains required.

All twelve static cook hashes and node counts match Step 3. The exact
four-time, one-/eight-domain IR regression includes plan arguments, instance
inputs/results, graph values and records for the twelve fixtures; it does not
yet cover every checked-in `.rays` or exported pixels. The latest full
window-free build/tests pass; intended API additions are reviewed and promoted.
Native presentation remains unverified in this restricted session. Step 4,
remaining Step 1 cases and the whole-item gates are still incomplete.

Raw outputs: `/tmp/rays-step4-kernel-global.csv`,
`/tmp/rays-step4-live-before.txt`, `/tmp/rays-step4-live-final.txt`,
`/tmp/rays-step4-editor.csv`, `/tmp/rays-step4-particles.csv`,
`/tmp/rays-step4-lower.csv`. Earlier calling-domain allocation measurements
are in `/tmp/rays-step4-kernel.csv`; the contended playback diagnostic is
`/tmp/rays-step4-live-after.txt`.

### Phase 4 noise arithmetic and scratch reuse checkpoint (2026-10-07)

Machine/profile: Apple M1, eight available domains, OCaml 5.3.0, Dune dev.
Benchmarks ran serially, without overlapping validation. Seven repetitions
per kernel row, medians; allocations use global `Gc.stat` outside the timed
interval, `(minor_words + major_words - promoted_words) * word_size`.

`noise3` is one immutable declaration in `Flow_ir.Operators`, included by the
SOP/editor workspace host. It takes a finite vec3 and returns raw 0..1
`Noise.sample3` with seed 0. The packed compiler recognizes that declaration
by identity; a custom declaration named `noise3` remains on the interpreter.
Tests cover scalar/packed bits, offsets/alias bounds, partial ranges,
non-finite errors, editor row edits/reload and the CLI's default registration.

The original native noise SOP remains `height_2d`. Its new explicit
`normal_3d` mode evaluates `P + N * (amplitude * noise3(P * frequency))`
without normalizing N. The Lisp schema owns the choice and refreshes facts
from reads P to reads P/N. Both modes invalidate point/vertex N and preserve
topology. Native checks cover missing/wrong-storage N, non-finite input
parameters/results, cancellation and exact one/eight-domain geometry. An
oversized-grain test caught overflowing range-ceiling arithmetic; the shared
RDK point-range scheduler and the noise error buffer now use subtraction
before division. Default range scheduling and valid output arithmetic stay
the same.

Command:

```sh
_build/default/tools/bench_kernel.exe
```

The noise comparison uses one million points, seed 0, amplitude 0.8 and
frequency 0.16. Packed P/N inputs are supplied before timing. The map's
amplitude is `(+ 0.8 (* t 0))` to retain the residual at specialization;
the measured frame is t = 1.25. The warm output of each CPU/interpreter
domain configuration is compared byte for byte with native positions, then
all timed outputs retain the same position hash
`3356f1ee95b997e05ed597b0d1b13d3a`.

| Execution | Domains | Median ms | Allocated bytes, all domains |
|---|---:|---:|---:|
| Native normal_3d | 1 | 30.299902 | 32,072,824 |
| Native normal_3d | 8 | 8.386850 | 32,118,712 |
| Packed Flow CPU | 1 | 59.475183 | 35,952,312 |
| Packed Flow CPU | 8 | 13.952017 | 35,998,240 |
| Reference interpreter | 1 | 2,062.009811 | 9,272,003,224 |
| Reference interpreter | 8 | 2,047.931910 | 9,272,003,224 |

The reference walker remains sequential when run inside an eight-domain
context; that row verifies its bytes, not a parallel interpreter. The CPU
path is about 2.0x native time at one domain and 1.7x at eight for this body.
This measures the arithmetic tier, not the complete SOP attribute pipeline:
`sop/attr`, `sop/with_attr`, attribute conversion and geometry writes still
need integration and their own end-to-end comparison.

The first packed implementation allocated scratch per 1,024-element block:
67.146063/14.512062 ms and 208,360,256/209,067,160 B at one/eight domains.
It now allocates one scratch buffer per stable chunk of sixteen blocks and
reuses it for those blocks. The buffer retains the existing 64-register,
512 KiB ceiling. For this million-point body allocations fell about 83%;
the same all-element tests pass across block/chunk tails. The focused kernel
test uses varying positions and non-unit normals at counts 0, 1, 1,023,
1,024, 2,051 and 16,385, four times and one/eight domains.

The existing million-element sin map now measures 12.341976/3.742933 ms and
11,152,264/11,197,016 B at one/eight domains, with unchanged hash
`c80bc2db40894ee77065598eb3a721f9`. The old height displacement measures
26.278019/7.821083 ms and 32,065,168/32,109,416 B, with unchanged hash
`1a9b19459a403094e2683996bd183a75`. Its small error-buffer allocation is new;
no general native throughput improvement is claimed.

Workspace/editor commands:

```sh
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 7
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200 1000 2000
```

All twelve fixture cook hashes, node counts and evaluation allocations match
the prior arithmetic checkpoint. The catalog now has 160 factories and
1,864 fields; the mode adds one row to Orrery's graph projection. Retained
catalog bytes are 941,536 before / 1,255,528 after workspace catalog construction.

| Nodes | Drag median ms | Scrub median ms | Scrub p95 ms | Scrub bytes/frame |
|---|---:|---:|---:|---:|
| 200 | 2.110958 | 2.115011 | 3.367901 | 6,548,077 |
| 1,000 | 7.448912 | 7.874966 | 13.295889 | 17,111,175 |
| 2,000 | 12.157917 | 12.481928 | 23.070097 | 25,274,194 |

The seven print/parse/check/evaluate/lower/project/layout scrub phase medians
remain zero. The strict scrub target is still unmet at 1,000/2,000 nodes.

`@all` and the affected window-free suites pass: Flow, Flow IR, Flow SOP,
Flow Graph, PXUI Graph, Procedural, RDK, SOP catalog, tools and test/. Intended
API/manifest/CLI digest changes were reviewed and promoted. A full `@runtest`
attempt also reaches three existing offscreen rendering tests (`test_ink`,
`test_scene3_native_lowering`, `test_world_raster`) that cannot start because
this session has no system-default Metal device. Native rendering/pixel
verification remains required. No native test was skipped or relabelled.
Step 4, remaining Step 1 work and the complete whole-item gates remain open.

Raw outputs: `/tmp/rays-step4-noise-kernel.csv` (before scratch reuse),
`/tmp/rays-step4-noise-kernel-reuse.csv` (first reuse run),
`/tmp/rays-step4-noise-kernel-final.csv` (final run with byte comparisons),
`/tmp/rays-step4-noise-lower.csv`, `/tmp/rays-step4-noise-editor.csv`,
`/tmp/rays-step4-noise-validation.log` (full attempt),
`/tmp/rays-step4-noise-focused-validation.log`,
`/tmp/rays-step4-noise-final-validation.log` (affected suites).

### Phase 4 Step 1 closure: the edit-frame gate and the checked-in file sweep (2026-10-07)

Same Apple M1, OCaml 5.3.0, Dune dev profile, eight available domains and
one-domain editor. The benchmark ran alone, before any validation. Command:

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200 1000 2000
```

Step 1's target was readjusted today (owner, 2026-10-07: "readjust gates"):
a scrub changes a value and the recook that value requires is work a layout
drag never does, so the two frames were never comparable whole. The benchmark
now also reports `rays_editor_scrub_edit_frame`, each scrub frame minus its
cook phase, computed per sample. The gate is that row against the drag row,
with the seven print/parse/check/evaluate/lower/project/layout phase medians
at zero. All three sizes meet it in this run; the earlier runs recorded above
met it too under this definition.

| Nodes | Drag median ms | Scrub median ms | Scrub edit median ms | Scrub p95 ms | Cook median ms | Scrub bytes/frame |
|---|---:|---:|---:|---:|---:|---:|
| 200 | 2.057076 | 2.013922 | 1.910210 | 3.164053 | 0.097036 | 6,548,077 |
| 1,000 | 7.200003 | 7.747889 | 6.808043 | 13.220072 | 0.853062 | 17,111,175 |
| 2,000 | 12.143850 | 12.286186 | 10.247231 | 22.436857 | 2.057076 | 25,274,195 |

Reduce medians are 0.024/0.134/0.288 ms. The seven pipeline phase medians
are zero at every size. The undo frame measures 2.597/9.927/17.789 ms.

The file sweep (`test_workspace_doc`, `part_files`) edits every scrubbable
literal of every checked-in `.rays` (numbers by one or a half, Booleans
flipped, the first component of a vector) through the literal path and the
full path and compares saved bytes and refusal codes; literal-path edits must
repeat no print, parse, check or projection, and a patched lowering must
have the full lowering's plan. The "full path" column is the warm cost of
the edit plus `Lower.of_checked` for the literals that fall back.

| File | Literals | Literal path | Lowering patched | Refused by both | Full path | Full path max ms |
|---|---:|---:|---:|---:|---:|---:|
| examples/particles | 4 | 2 | 0 | 0 | 2 | 31.4 |
| sketches/cube_cage | 59 | 57 | 37 | 3 | 2 | 1.6 |
| sketches/flow_terrain | 15 | 14 | 7 | 0 | 1 | 0.2 |
| sketches/shattered_cube | 31 | 30 | 23 | 1 | 0 | |
| sketches/shattered_studio | 62 | 52 | 26 | 6 | 4 | 1.2 |
| sketches/ws_bloom | 28 | 17 | 5 | 2 | 9 | 4.8 |
| sketches/ws_facade | 8 | 8 | 8 | 0 | 0 | |
| sketches/ws_garland | 9 | 1 | 0 | 6 | 2 | 2.7 |
| sketches/ws_kit | 6 | 1 | 0 | 2 | 3 | 1.1 |
| sketches/ws_layout | 22 | 14 | 7 | 1 | 7 | 0.7 |
| sketches/ws_morph | 21 | 18 | 12 | 2 | 1 | 1.8 |
| sketches/ws_orrery | 18 | 11 | 11 | 0 | 7 | 2.5 |
| sketches/ws_rosette | 1 | 1 | 0 | 0 | 0 | |
| sketches/ws_sunflower | 5 | 2 | 2 | 0 | 3 | 12.6 |
| sketches/ws_tiles | 5 | 0 | 0 | 0 | 5 | 8.0 |
| sketches/ws_tree | 7 | 5 | 5 | 0 | 2 | 1.7 |
| sketches/ws_tunnel | 5 | 5 | 5 | 0 | 0 | |
| sketches/ws_variations | 12 | 9 | 7 | 2 | 1 | 0.8 |
| sketches/ws_wave | 4 | 2 | 2 | 0 | 2 | 12.2 |
| specification/pxui-kit/kit | 16 | 7 | 2 | 0 | 9 | 0.5 |

338 literals in 20 files (`sop_gallery` brings its own SOPs and is skipped,
as in `test_scene_sync`). The full path's cost is evaluation and lowering,
not the edit: particles spends 29.9 of its 31.4 ms in `Eval.static` of the
10,000-point draw graph, which a change of `:count` requires whatever path
applies it; the edit itself (print, parse, check) is 0.5 ms there and at
most 0.8 ms in every file. This is why the generic value-literal fast path
and the per-frame budget of Step 1 were dropped (NEXT.md §5): the saving
available is under a millisecond, and skipping the evaluation would hide the
scrub's effect until release.

The sweep found two defects, both fixed with regressions: a same-type literal
that lowering refuses (`attribute_randomize` bounds out of order) came back
as `E_TYPE` on the literal path and `E_LOWER` on the full path, and a
`(ref cage)` graph reference counted as a read of the binding named `cage`,
so `Flow_edit.reorder` refused every full-path parameter edit in the
cube_cage scene graph with a false `E_GRAPH_CYCLE`.

Raw output: `/tmp/rays-step1-closure-editor.csv`; the sweep prints its
table in `dune build @test/test_workspace_doc`.

### Phase 4 cooked attribute kernel checkpoint (2026-10-07)

Apple M1, macOS arm64, OCaml 5.3.0, Dune dev profile, eight available domains.
Seven repetitions per kernel row, median wall time. Allocations use global
`Gc.stat` across domains, outside the timed interval. The final kernel run
had no concurrent repository validation. Other host workloads were active;
editor measurements below show substantial timing variation.

The actual Lisp `sop/with_attr` node now runs the normal-displacement body
through cooked `sop/attr` P/N reads and an RDK position write. The benchmark
prepares it through normal checking/lowering and invokes its cook with the
million-point input, avoiding session cache hits. The reference mode runs
that same node through the independent tree walker. Every warm/timed output
is checked against native positions before reporting; all four Lisp rows
and the native rows share hash `3356f1ee95b997e05ed597b0d1b13d3a`.

```sh
_build/default/tools/bench_kernel.exe --attributes
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 7
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200 1000 2000
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/test/test_drawing.exe examples/particles/sketch.rays --bench
```

| Path, 1M points | Domains | Median ms | Allocated bytes, all domains |
|---|---:|---:|---:|
| Native normal3 noise | 1 | 30.788 | 32,072,824 |
| Native normal3 noise | 8 | 9.586 | 32,117,208 |
| Complete Lisp CPU kernel | 1 | 67.584 | 105,908,272 |
| Complete Lisp CPU kernel | 8 | 26.118 | 105,998,792 |
| Complete Lisp reference | 1 | 1535.832 | 7,264,006,384 |
| Complete Lisp reference | 8 | 1555.345 | 7,264,050,656 |

The first full connection used `Array.init` to convert attributes, then
`Array.for_all` to validate output. It measured 92.487 / 90.219 ms and
249,908,384 / 249,999,912 bytes at one/eight domains; that initial run
also overlapped some validation. Replacing those callbacks with direct
float-array loops reduced measured allocation by about 144 MB per cook.
This comparison establishes the allocation reduction; timing is diagnostic.
The earlier arithmetic-only benchmark remains above and excluded attribute
resolution and geometry writes. Native displacement removes normals;
`with_attr :P` preserves untouched attributes, including N. Tests compare
all native position bits and complete interpreter/CPU geometry bytes.

| Workspace | Check ms | Eval ms | Lower ms | Cook ms | Nodes | Cook hash |
|---|---:|---:|---:|---:|---:|---|
| bloom | 0.093 | 0.125 | 3.788 | 1.058 | 84 | dad16cdd4d91e532756c1d0d0667d207 |
| facade | 0.037 | 0.085 | 1.912 | 0.545 | 69 | df9fdd4891bcaf471beeae7f34f26ab5 |
| garland | 0.078 | 0.095 | 2.483 | 0.786 | 40 | bf4f98a940ac9bfe37a0abd2c1100df4 |
| kit | 0.068 | 0.034 | 1.056 | 0.131 | 24 | 23ea245dac862ed7b9dda2f8a7649322 |
| orrery | 0.051 | 0.155 | 2.295 | 0.386 | 56 | 4e38b6104e25800d415c4d2291337f37 |
| rosette | 0.047 | 0.049 | 2.277 | 0.520 | 39 | 18188829904e74c61fd34e367ae74150 |
| sunflower | 0.020 | 1.138 | 10.764 | 2.668 | 241 | 59a7b71c83f1057dc32bf6e90babb99d |
| tiles | 0.025 | 0.342 | 9.428 | 1.287 | 193 | 9c7c72bc41d7365e6cd11fe394eb5120 |
| tree | 0.025 | 0.019 | 1.976 | 1.218 | 27 | 23e6fdd7f6252e15e705529856f86949 |
| tunnel | 0.015 | 0.025 | 2.096 | 7.371 | 37 | 6354bb27591a11d27519c20d0766a9b0 |
| variations | 0.040 | 0.023 | 0.945 | 0.200 | 30 | 4c4dda18df1d2cc685970d4e2461ca92 |
| wave | 0.026 | 5.373 | 10.351 | 1.415 | 13 | 70c3b661ce4166f563fd5c17329b821c |

All twelve node counts and cook hashes match the preceding checkpoint.
At capacity 512, retained entries / payload MB remain bloom 52/1.22,
sunflower 241/1.84, wave 13/0.66 and tree 27/0.87; none evicts.

| Nodes | First drag / scrub edit ms | Repeat drag / scrub edit ms |
|---|---:|---:|
| 200 | 2.120 / 2.014 | 2.057 / 1.942 |
| 1,000 | 7.379 / 7.554 | 22.286 / 27.587 |
| 2,000 | 12.577 / 22.345 | 24.586 / 19.200 |

Every print/parse/check/evaluate/lower/project/layout phase median is zero.
These runs do not establish the scrub latency gate. Process inspection
found active VM and macOS update processes consuming several CPU cores;
no unrelated process was stopped. The dynamic 10,000-particle frame
measures 75.395 ms median / 107.126 ms p95 and 157,808,506 bytes per frame.
This code does not yet move particle folds to packed CPU execution.

Focused Flow/IR/SOP tests, window-free `@all`/`@runtest`, the promoted API
and sketch list, `--ship`, and a finite native `flow_kernel` run pass.
An offscreen editor capture is `/tmp/rays-flow-kernel.png`.
Remaining whole-item requirements are explicitly listed in `NEXT.md`.

Raw outputs: `/tmp/rays-step4-attributes-kernel.csv` (initial connection),
`/tmp/rays-step4-attributes-kernel-final.csv`,
`/tmp/rays-step4-attributes-lower.csv`,
`/tmp/rays-step4-attributes-editor.csv`,
`/tmp/rays-step4-attributes-editor-repeat.csv`,
`/tmp/rays-step4-attributes-particles.csv`,
`/tmp/rays-step4-attributes-final-validation.log`,
`/tmp/rays-step4-attributes-ship.log`,
`/tmp/rays-step4-attributes-sketch.log`.

## Phase 4 packed iteration and execution fusion checkpoint

2026-10-07, Apple M1 arm64, OCaml 5.3.0, development profile. Seven repetitions,
median wall time and `Gc.stat` allocation across all domains, one million float
elements, `t = 1.25`. Each warm result and timed result is hashed over all value
bytes with sharing removed; the CPU/reference and one/eight-domain hashes agree.
The reference path is the independent walker. Measurements ran without repository
validation alongside them; unrelated host workloads remain outside our control.

```sh
dune build tools/bench_kernel.exe
_build/default/tools/bench_kernel.exe --loops
_build/default/tools/bench_kernel.exe --fusion
```

The loop benchmark's bodies are visible in `tools/bench_kernel.ml`: a sine `for`
and `sum`, and the same ordered recurrence in `fold`, `scan` and `reduce`.
This measures source-array creation and output writing as well as the body.
The reference interpreter allocates boxed values and environments per element.
CPU accumulator instructions run in element order; independent instructions
run once per block. The fixed chunk tree carries the left-fold accumulator,
preserving reference rounding instead of reassociating partial sums.

| Form | CPU 1 / 8 domains, ms | Reference 1 / 8 domains, ms | CPU bytes, 1 domain | Reference bytes, 1 domain | Hash |
|---|---:|---:|---:|---:|---|
| `for` sine | 22.191 / 9.203 | 538.768 / 537.593 | 50,671,016 | 2,552,780,680 | `3cbed96293ed2c595465f725e01b02c8` |
| `sum` sine | 22.282 / 22.452 | 538.635 / 537.879 | 42,671,064 | 2,576,003,536 | `4af8ad6d99a211f41961ef06615e372b` |
| `fold` | 47.461 / 47.424 | 1107.390 / 1105.377 | 61,213,296 | 5,384,003,728 | `296520f8bb9281a5c12d9663ef7eaf91` |
| `scan` | 49.333 / 49.046 | 1116.721 / 1140.210 | 69,213,288 | 5,408,780,840 | `02d85a044c70d0da415949ddf377757a` |
| `reduce` | 44.840 / 45.214 | 1137.930 / 1140.463 | 61,213,328 | 5,448,003,552 | `296520f8bb9281a5c12d9663ef7eaf91` |

The initial register recurrence used an iterator closure per element. Replacing
that with a plain instruction-index loop changes the one-domain `fold` median
from 71.698 to 47.461 ms and allocation from 197,346,168 to 61,213,296 bytes;
`scan` changes from 71.791 to 49.333 ms and 205,346,160 to 69,213,288 bytes.
This does not parallelize the dependent recurrence. The `for` eight-domain
allocation is 50,715,232 bytes; the other loop allocations are unchanged at eight.

Fusion benchmark: `(map square (map sine xs))`, with explicit live frame reads
in both functions, prepared once. The unfused CPU program is prepared with
`Packed.compile ~fusion:false`, retaining its intermediate array. All three
modes hash to `9e563defd6580a2d454cb40a4648d85f`.

| Mode | 1 domain, ms | 8 domains, ms | Bytes, 1 / 8 domains |
|---|---:|---:|---:|
| Fused CPU | 25.943 | 9.910 | 52,704,744 / 52,749,264 |
| Unfused CPU | 33.625 | 12.167 | 62,361,712 / 62,448,912 |
| Reference | 1406.481 | 1403.846 | 6,752,004,568 / 6,752,004,568 |

Fusion proves equal counts before removing materialization: single-input dynamic
chains are safe, multi-input zips require equal static counts. It retains skipped
and shortened consumers' boundaries, so a failing unused producer tail still
reports the reference diagnostic. A group exceeding 64 registers retains its
separate stages. Stages carry authored provenance; group timing/UI reporting is
still required. Static live packed fold/reduce now defers the whole iteration,
preventing per-element residual chains before compilation.

Focused Flow, IR and SOP validation passes. The new runnable regression covers
all numeric packed forms at counts 0, 1, 1023, 1024, 1025, 2051 and 16385,
four times and one/eight domains, including skips, Cartesian order, vector/scalar
accumulators, signed zero, nonfinite errors, correlated-clause fallback, dynamic
counts and fused/unfused parity. The intended packed metadata/profiling API is
reviewed and promoted. `_build/default/tools/check.exe --ship` passes after
the final code review, including native smoke. Packed frame-fold execution,
SOP-fact-guided placement, group timing/tier UI, cooked reference probes, inline
map/function editing and whole-file pixel parity remain required in `NEXT.md`.

Raw outputs: `/tmp/rays-packed-loops.csv`, `/tmp/rays-packed-loops-final.csv`,
`/tmp/rays-packed-fusion.csv`, `/tmp/rays-packed-loops-validation.log`,
`/tmp/rays-packed-fusion-validation.log`,
`/tmp/rays-packed-loops-fusion-ship-final.log`.

## Phase 4 packed frame folds and native drawing checkpoint

2026-10-07, Apple M1 arm64, OCaml 5.3.0, development profile. The complete
10,000-particle editor benchmark follows the same 10 warm frames / 200 measured
frames at 60 Hz and one domain as the earlier cooked-attribute checkpoint.
It ran after validation completed, without another repository workload alongside it.

```sh
dune build test/test_drawing.exe
_build/default/test/test_drawing.exe examples/particles/sketch.rays --bench
_build/default/test/test_drawing.exe examples/particles/sketch.rays /tmp/rays-frame-kernel-native
_build/default/tools/check.exe @lib/flow_ir/runtest @lib/flow/runtest @test/dependency_gate
_build/default/tools/check.exe --ship
```

| Complete editor particle frame | Previous checkpoint | Packed frame folds |
|---|---:|---:|
| Median | 75.395 ms | 2.747 ms |
| p95 | 107.126 ms | 3.205 ms |
| Allocated bytes/frame | 157,808,506 | 9,199,924 |

The interpreter continues to own state cells, source/frame reset, repeated reads
and transaction rollback. Its private packed callback receives current immutable
bindings. Each prepared IR program caches at most 32 register templates in an
atomic immutable list. Supported maps/loops rebind their current sources and
scalar/record uniforms; a changed function body or fused lexical scope needs
fresh specialization. The particle test proves exactly two template compilations
and ten rebindings over six steps. Numeric comparisons, Boolean operations and
`if` cover bounce arithmetic. Eager pure branches that produce an error rerun
the independent reference walker, retaining lazy-branch diagnostics.

Native canvas playback now prepares drawing argument IR once per plan, and
exports prepare once before playback. The drawing path previously called
`Eval.force` directly, so the IR value lane alone could not optimize particles.
The added `sketch_support -> flow_ir` edge is documented in `backend.md` and
enforced by the dependency gate. Static canvas allocation remains 201,007 bytes
per editor frame at both 4 and 10,000 unchanged points in the broad suite.

Frame-fold tests compare every float bit and the complete state stamp at
one/eight domains, including particle position/velocity records, repeated reads,
backward seeks, changing array lengths, scalar/record uniform changes, ordered
scans, Boolean branches, nonfinite diagnostics and rollback after a later failure.
The native gate exports four frames in seven modes: OCaml, the workspace export
twice, prepared CPU at one/eight domains, and independent reference at one/eight
domains. Every PNG matches byte for byte, and the first and fourth frames differ.
Artifacts are under `/tmp/rays-frame-kernel-native`.

Focused Flow/IR/SOP suites, broad editor/drawing tests, the dependency gate and
`--ship` pass, including native smoke. The intended API manifest was reviewed and
promoted. Whole-file pixel coverage, SOP-fact-guided placement, group timing/tier
UI, cooked reference probes and inline map/function editing remain required.

Raw outputs: `/tmp/rays-frame-kernel-integration.log`,
`/tmp/rays-frame-kernel-broad.log` (the reviewed API diff preceded promotion),
`/tmp/rays-frame-kernel-particles.csv`, `/tmp/rays-frame-kernel-native.log`,
`/tmp/rays-frame-kernel-ship.log`.

## Phase 4 inline function and cooked probe checkpoint

2026-10-08, same machine and isolated particle workload as the preceding
checkpoint (10 warm-up frames, 200 measured frames, 10,000 points, one domain).

```sh
_build/default/test/test_drawing.exe examples/particles/sketch.rays --bench
_build/default/tools/check.exe --ship
_build/default/tools/ui_shot.exe sketches/flow_kernel/sketch.rays /tmp/rays-inline-probe-kernel.png 1200 760 4
```

The complete particle editor frame is 2.748013 ms median, 3.402948 ms p95 and
9,199,932 allocated bytes/frame. The preceding frame-fold checkpoint was
2.746820 / 3.205061 ms and 9,199,924 bytes/frame; this measurement retains the
same median performance. It does not replace the pending whole-item benchmarks.

Inline higher-order calls and function zones now share authored paths with
checked terms, edits, the text caret and token scrubs. Ordinary SOP sites retain
their previous identities, and a focused regression distinguishes maps inside
opaque expressions. Tests inspect element 9,999 of a 10,003-element map and
element 16,001 of a cooked 16,386-point attribute map. The latter is exactly
equal to native noise displacement at t=1.25, materializes P/N only twice across
the selector and body footers, keeps source bytes unchanged and changes after a
body edit. Both keyboard and pointer selectors reach indices beyond the capped
records. Packed sparklines sample at most 64 shared reference calls. Probes use
forked fold state and immutable geometry snapshots from the editor's existing
64-target optional cook request.

The pointer regression found zone wire hit boxes above controls: making those
boxes children of the zone keeps them below its controls in the existing PXUI
tree. Projection, probe, text, editor, scene synchronization, cooked attribute
and IR suites pass; `--ship` passes after the reviewed API promotion, including
native smoke. An offscreen editor capture of `flow_kernel` also passes.
SOP-fact-guided placement, group timing/tier UI, the complete checked-in-file
IR/value/pixel sweep and fresh whole-item benchmark/shipping gates remain open.

Raw outputs: `/tmp/rays-inline-probe-focused.log`,
`/tmp/rays-inline-probe-ship.log`, `/tmp/rays-inline-probe-particles.csv`,
`/tmp/rays-inline-probe-shot.log`. Capture: `/tmp/rays-inline-probe-kernel.png`.

## Phase 4 SOP count placement and group reports checkpoint

2026-10-08, same Apple-Silicon machine, OCaml 5.3 development profile and
shared one/eight-domain pool as the preceding checkpoints. The new workload
has one million points, two attribute maps over a grid and a preserving
transform, followed by a two-input map. Each mode includes both attribute
reads; seven measured repetitions follow a warm-up. A host count proof lets
the three stages execute as one register program. The comparison program
retains the previous dynamic-source materialization boundaries.

```sh
_build/default/tools/bench_kernel.exe --attribute-fusion
_build/default/test/test_drawing.exe examples/particles/sketch.rays --bench
_build/default/tools/check.exe --ship
_build/default/tools/ui_shot.exe sketches/flow_kernel/sketch.rays /tmp/rays-profile-kernel.png 1200 760 8
UI_SHOT_DO='click:651,650 key:o key:f' _build/default/tools/ui_shot.exe sketches/flow_kernel/sketch.rays /tmp/rays-profile-group.png 1200 760 8
```

| Mode | Domains | Median ms | Allocated bytes, all domains |
|---|---:|---:|---:|
| Fact-guided fusion | 1 | 53.588867 | 82,296,152 |
| Materialized CPU | 1 | 77.987909 | 135,633,720 |
| Independent interpreter | 1 | 1814.150095 | 8,456,008,448 |
| Fact-guided fusion | 8 | 15.752077 | 82,341,736 |
| Materialized CPU | 8 | 22.717953 | 135,768,008 |
| Independent interpreter | 8 | 1810.534000 | 8,456,008,448 |

All six modes have hash `9b4c8c16c19aaf16097e3ebeb453124e`. These numbers
measure attribute reads and array computation; the preceding complete noise
benchmark remains the evidence for geometry writes and native displacement.

With execution reports enabled, the 10,000-particle editor frame is
2.769947 ms median, 3.505230 ms p95 and 9,204,612 allocated bytes/frame
(10 warm-up, 200 measured frames). The preceding checkpoint was
2.748013 / 3.402948 ms and 9,199,932 bytes/frame. Reports retain at most 512
groups per workspace, use the host clock and atomic snapshots, and do no
per-element instrumentation. Packed durations exclude input materialization
and separately timed nested groups; only the consuming card displays one.

Tests prove actual three-stage fusion across a preserving transform, refusal
across independent/changed/undeclared sources, instantiated point/primitive
facts, typed source-list refusal and exact outputs at four times/one/eight
domains. Profile tests verify replacement, a 512-group capacity, fused timing
and reference-tier reporting. Graph checks preserve host reports/readouts and
verify changed native paint (426 checks). Native captures show CPU badges on
the named function's body cards and a single timing on the consuming map;
the example now includes that graph and its viewport/inspector.
The intended API manifest is reviewed/promoted and `--ship` passes with native
smoke. Whole-file IR/value/pixel coverage and final whole-item benchmark gates
remain open.

Raw outputs: `/tmp/rays-fact-fusion-bench.csv`,
`/tmp/rays-fact-fusion-focused.log`, `/tmp/rays-profile-focused.log`,
`/tmp/rays-profile-particles.csv`, `/tmp/rays-profile-ship.log`,
`/tmp/rays-profile-shot.log`, `/tmp/rays-profile-group-shot.log`.

## Phase 4 whole-item verification (2026-10-08)

Apple M1, Darwin arm64, eight available cores, OCaml 5.3.0, Dune 3.24.2,
development profile. Each benchmark ran alone, after validation/builds ended.
Editor measurements use one domain and dummy SDL video/audio, 200 samples per
size; particles use 10 warm-up and 200 measured frames. Kernel measurements
use one million points, one/eight domains and seven repetitions after warm-up.

```sh
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/tools/bench_rays_editor.exe 200 1000 2000
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy _build/default/test/test_drawing.exe examples/particles/sketch.rays --bench
_build/default/tools/bench_kernel.exe
_build/default/tools/bench_kernel.exe --attributes
_build/default/tools/bench_kernel.exe --attribute-fusion
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 7
```

| Nodes | Step 0 scrub ms | Final drag ms | Final scrub ms | Final scrub edit ms | Final scrub p95 ms | Final scrub bytes/frame |
|---:|---:|---:|---:|---:|---:|---:|
| 200 | 6.938 | 2.027988 | 2.022982 | 1.915693 | 3.192902 | 6,572,693 |
| 1,000 | 35.982 | 7.241964 | 7.369995 | 6.508827 | 13.134956 | 17,160,599 |
| 2,000 | 78.056 | 12.105942 | 12.300968 | 10.289192 | 22.664070 | 25,323,618 |

Every print/parse/check/evaluate/lower/project/layout phase median is zero.
Cook medians are 0.097036/0.849009/2.042055 ms; reduce medians are
0.024080/0.133991/0.285864 ms. The owner's readjusted gate compares each
sample's scrub frame minus its cook with the drag frame, and passes at all
three sizes. It does not claim that changing geometry costs the same as a drag.

The 10,000-particle complete editor frame is 2.711058 ms median, 3.304958 ms
p95 and 9,204,964 bytes/frame, against Step 0's 31.690/32.145 ms and
148,126,467 bytes/frame. This includes the advancing fold, drawing and host
frame; GPU presentation is outside this benchmark.

| Complete noise path | Domains | Median ms | Bytes, all domains |
|---|---:|---:|---:|
| Native normal3 | 1 | 29.849052 | 32,072,824 |
| Native normal3 | 8 | 8.059978 | 32,118,104 |
| Lisp CPU, reads and writes included | 1 | 85.706949 | 106,450,760 |
| Lisp CPU, reads and writes included | 8 | 25.467157 | 106,541,840 |
| Independent interpreter, reads and writes included | 1 | 1,442.040920 | 7,216,006,944 |
| Independent interpreter, reads and writes included | 8 | 1,446.156979 | 7,216,052,344 |

Every warm/timed output matches native position bytes, hash
`3356f1ee95b997e05ed597b0d1b13d3a`. A second complete run in the default
benchmark gives CPU 85.757017/25.326014 ms and interpreter
1,449.026823/1,447.520018 ms. The CPU tier remains slower than native;
the original gate requires the measurement and exact parity, not near-native
speed. Step 0's unchanged height-2D native workload is 25.174856/6.001949 ms
now, versus 55.700/8.737 ms then, with the same
`1a9b19459a403094e2683996bd183a75` hash. That timing difference is not an
algorithm change. Arithmetic-only noise excludes attribute reads/writes and
measures 79.137087/16.911030 ms in this run.

Fact-guided attribute fusion measures 53.303957/15.810013 ms versus
materialized CPU 78.006983/22.730112 ms and interpreter
1,810.596943/1,822.005987 ms, at one/eight domains. Allocations are
82,296,376/82,342,104 B fused and 135,634,664/135,767,624 B materialized.
All modes retain `9b4c8c16c19aaf16097e3ebeb453124e`.

| Fixture | Check ms | Eval ms | Lower ms | Cook ms | Nodes | Eval bytes |
|---|---:|---:|---:|---:|---:|---:|
| bloom | 0.099 | 0.124 | 3.699 | 1.131 | 84 | 537,208 |
| facade | 0.041 | 0.085 | 1.853 | 0.540 | 69 | 335,808 |
| garland | 0.088 | 0.079 | 2.138 | 0.604 | 40 | 364,664 |
| kit | 0.072 | 0.033 | 0.989 | 0.122 | 24 | 132,176 |
| orrery | 0.059 | 0.161 | 2.117 | 0.460 | 56 | 653,768 |
| rosette | 0.052 | 0.048 | 2.081 | 0.334 | 39 | 207,808 |
| sunflower | 0.022 | 1.047 | 10.523 | 2.395 | 241 | 4,501,136 |
| tiles | 0.028 | 0.404 | 7.431 | 1.020 | 193 | 1,271,648 |
| tree | 0.026 | 0.018 | 1.773 | 0.767 | 27 | 77,912 |
| tunnel | 0.015 | 0.025 | 1.552 | 4.111 | 37 | 107,232 |
| variations | 0.041 | 0.021 | 0.780 | 0.156 | 30 | 100,952 |
| wave | 0.030 | 4.300 | 7.797 | 1.048 | 13 | 17,218,984 |

All twelve cook hashes match the Step 2 table above. Node counts and
capacity-512 retained entries/payload MB remain unchanged: bloom 52/1.22,
sunflower 241/1.84, wave 13/0.66, tree 27/0.87, no evictions. Warm cooks
are 0.048/0.256/0.033/0.030 ms respectively.

The whole-file gate checks all 23 `.rays` workspaces (including the added
kernel sketch) and all twelve generated fixtures. A shared private OCaml
check compares independently evaluated static plans, instance identities,
arguments, results, state seeds and every retained record, then all forced
values and complete fold stamps at `0`, `0.125`, `1.25`, `7`, at one/eight
domains. Anonymous function bodies/captures are included in value keys.
Reference lowering interprets actual value drives and attribute writes;
opaque SOPs retain their real native implementation. The gallery and voxel
wall checks run inside their own executables with their actual custom
factories, without replacement catalog declarations.

Native comparisons cover complete cooked geometry/topology/attribute/group
payloads, instance transforms and pixels of every SOP/drawing result at all
four times/domain counts. SOP images use a common bounds-framed camera and
unlit material; authored scene/material/settings values are compared in the
value sweep. Drawing images cover the complete particle 800×600 canvas.
These are program-output comparisons; editor tier/timing decorations are
tested separately and are not expected to match reference-mode UI pixels.

```sh
_build/default/tools/check.exe @test/test_workspace_ir @examples/sop_gallery/runtest @sketches/voxel_wall/runtest
_build/default/tools/check.exe @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels
_build/default/tools/check.exe @check @lib/flow_ir/runtest @test/test_rays_editor @test/test_probe @test/test_workspace_shell
_build/default/tools/check.exe --ship
```

| Requirement | Runnable evidence |
|---|---|
| Timers, status/crash phases and three before/after workloads | `test_phase_timer`, editor/drawing/kernel benchmarks above |
| Same-type literal patch, one check/evaluation, projection reuse, text scrubs | `test_workspace_doc`, `test_text_pane`, editor phase counters |
| Lexical node viewing without source/history edits | `test_workspace_view_native`, loop/piece/live preview regressions |
| Open nominal types/contexts and immutable operator extensions | `test_open_domain`, including painted card, menu insertion and reload |
| Declared regular SOP facts, physical topology and component-cache reuse | `lib/procedural/test_facts`, PPX/catalog manifest checks |
| Typed IR, sharing/hoisting/pruning/fusion, precision legality and placement | `lib/flow_ir/test_ir`, including exact readback and every forbidden sink |
| Packed maps/loops/reductions, ordered accumulators, errors and fusion | `lib/flow_ir/test_packed`, million-element benchmark hashes |
| Actual SOP attribute resolution/writes and fact-guided dynamic fusion | `lib/flow_sop/test_attribute_kernel`, native/CPU/reference noise hashes |
| Packed state folds, template reuse, transactions and particle parity | `test_frame_kernel`, `test_drawing` seven-mode native export |
| Inline function cards/zones, body edits, reference cones beyond record cap | `test_domain`, attribute/probe/text/graph pointer regressions |
| Group timings, tier badges, bounded profiles and instance provenance | IR/packed/PXUI checks and native kernel captures |
| Every workspace/fixture, all values and native output pixels, domains 1/8 | `test_workspace_ir`, the three `test_workspace_pixels` aliases |
| Stable fixture cooks, payload retention, Rand/residual/operator sweeps | workspace benchmark, Flow and SOP/IR extension tests |
| Intended APIs/manifests and native shipping | reviewed API promotion, `--ship` and the native host checks |

The Step 1 exclusions remain the owner's recorded decision: per-graph
checking was unnecessary once the target passed; generic literal/template/fold
fast paths and a frame budget were dropped after the full-file edit sweep.
GPU compilation, approximate producers/readback, machine-code JIT and the
other explicitly deferred roadmap items remain outside Phase 4.

The reviewed reference-execution API is promoted. Final `--ship` passes
(`@all`, `@runtest`, native `@smoke`, `git diff --check`), and the focused native
workspace/host comparisons above pass. This closes the Phase 4 handoff; its
completed `NEXT.md` is removed. The optional full qualification suite is not a
shipping gate: an earlier overly broad alias invocation reached its existing
exhaustive catalog fixture and failed with `switch.input has no perturbable
value`. The focused pixel aliases use separate alias dependencies so they
do not trigger that unrelated qualification sweep.

Raw measurements: `/tmp/rays-final-editor.csv`, `/tmp/rays-final-particles.csv`,
`/tmp/rays-final-kernel.csv`, `/tmp/rays-final-kernel-attributes.csv`,
`/tmp/rays-final-attribute-fusion.csv`, `/tmp/rays-final-lower.csv`.
Checks: `/tmp/rays-final-pixels.log`, `/tmp/rays-final-audit.log`,
`/tmp/rays-final-ship.log`. Native images: `/tmp/rays-workspace-pixels`,
`/tmp/rays-workspace-pixels-sop-gallery`, `/tmp/rays-workspace-pixels-voxel-wall`;
seven-mode particle exports: `/tmp/rays-drawing-export`.
## P4 baseline (2026-10-08)

Apple M1 (arm64 T8103), macOS 27.0.1 (26A434), OCaml 5.3.0,
Dune 3.24.2, development profile, eight available domains. All timed binaries
ran serially after builds completed; five repetitions per grain workload,
seven per workspace evaluation, three per cold branch/zone cook. The
parallel pool is reused. Allocated bytes in the RDK rows are the calling
domain's GC counter; kernel rows report all domains. Raw outputs, including
allocations, promotions, cardinalities and hashes, are retained in
[`performance/p4-baseline-grain.csv`](performance/p4-baseline-grain.csv),
[`performance/p4-baseline-nodes.csv`](performance/p4-baseline-nodes.csv) and
[`performance/p4-baseline-kernel.csv`](performance/p4-baseline-kernel.csv).

```sh
_build/default/tools/bench_workspace_lower.exe --nodes
_build/default/tools/bench_workspace_lower.exe --residuals
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 7
_build/default/tools/bench_workspace_lower.exe --branches 3
_build/default/tools/bench_workspace_lower.exe --loops 3
_build/default/tools/bench_kernel.exe
# Each row below uses --grain, RAYS_RDK_OPS_REPEATS=5,
# RAYS_RDK_BENCH_GRAIN=<grain>, RAYS_BENCH_DOMAINS=<domains>.
# RAYS_RDK_OPS_COLUMNS/ROWS: 99/99, 499/199, 999/999.
_build/default/tools/bench_rdk_ops.exe --grain
```

Per-node rows include summed selected-input points, output points and the
node's own cook seconds (not its upstream dependencies). The bounded timing
table preserves the last actual cook on a cache hit; `stats.last_node`
separately records the latest hit. All 797 cooked-node rows are in the CSV
linked above.

| Fixture | Check ms | Eval ms | Lower ms | Cook ms | Nodes | Eval bytes | Cook hash |
|---|---:|---:|---:|---:|---:|---:|---|
| bloom | 0.095 | 0.119 | 3.883 | 1.171 | 84 | 537208 | dad16cdd4d91e532756c1d0d0667d207 |
| facade | 0.038 | 0.083 | 1.982 | 0.559 | 69 | 335808 | df9fdd4891bcaf471beeae7f34f26ab5 |
| garland | 0.084 | 0.086 | 2.308 | 0.700 | 40 | 364664 | bf4f98a940ac9bfe37a0abd2c1100df4 |
| kit | 0.072 | 0.035 | 1.043 | 0.124 | 24 | 132176 | 23ea245dac862ed7b9dda2f8a7649322 |
| orrery | 0.057 | 0.148 | 2.205 | 0.506 | 56 | 653768 | 4e38b6104e25800d415c4d2291337f37 |
| rosette | 0.050 | 0.048 | 2.386 | 0.350 | 39 | 207808 | 18188829904e74c61fd34e367ae74150 |
| sunflower | 0.022 | 1.098 | 11.028 | 3.343 | 241 | 4501136 | 59a7b71c83f1057dc32bf6e90babb99d |
| tiles | 0.030 | 0.399 | 8.428 | 1.097 | 193 | 1271648 | 9c7c72bc41d7365e6cd11fe394eb5120 |
| tree | 0.024 | 0.019 | 1.736 | 0.640 | 27 | 77912 | 23e6fdd7f6252e15e705529856f86949 |
| tunnel | 0.014 | 0.022 | 1.689 | 4.084 | 37 | 107232 | 6354bb27591a11d27519c20d0766a9b0 |
| variations | 0.039 | 0.019 | 0.808 | 0.200 | 30 | 100952 | 4c4dda18df1d2cc685970d4e2461ca92 |
| wave | 0.029 | 4.639 | 8.483 | 1.187 | 13 | 17218984 | 70c3b661ce4166f563fd5c17329b821c |

Residual views are traversed from results, plan arguments and records, deduplicated
by residual id; nested captures are included. The byte column marshals all
actual immutable views together with `Marshal.Closures`, preserving sharing.
It is an in-process measurement only, never deserialized or used as a cache key.

| Fixture | Residuals | Captured bindings | Read bindings | Marshal view bytes |
|---|---:|---:|---:|---:|
| bloom | 0 | 0 | 0 | 0 |
| facade | 0 | 0 | 0 | 0 |
| garland | 0 | 0 | 0 | 0 |
| kit | 0 | 0 | 0 | 0 |
| orrery | 99 | 1411 | 240 | 35186 |
| rosette | 0 | 0 | 0 | 0 |
| sunflower | 0 | 0 | 0 | 0 |
| tiles | 0 | 0 | 0 | 0 |
| tree | 0 | 0 | 0 | 0 |
| tunnel | 0 | 0 | 0 | 0 |
| variations | 0 | 0 | 0 | 0 |
| wave | 2160 | 14580 | 6480 | 413206 |

| Points | Domains | Grain | Transform ms | Noise ms | Normals ms | Scatter ms | Mountain ms |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 10000 | 1 | 256 | 0.184 | 0.364 | 0.530 | 1.415 | 5.674 |
| 10000 | 1 | 1024 | 0.173 | 0.359 | 0.533 | 1.494 | 5.550 |
| 10000 | 1 | 4096 | 0.166 | 0.373 | 0.526 | 1.425 | 5.551 |
| 10000 | 1 | 16384 | 0.182 | 0.363 | 0.553 | 1.420 | 5.408 |
| 10000 | 1 | 65536 | 0.168 | 0.374 | 0.535 | 1.427 | 5.470 |
| 10000 | 8 | 256 | 0.162 | 0.134 | 0.403 | 0.829 | 1.503 |
| 10000 | 8 | 1024 | 0.118 | 0.174 | 0.416 | 0.732 | 1.287 |
| 10000 | 8 | 4096 | 0.183 | 0.201 | 0.589 | 1.544 | 2.430 |
| 10000 | 8 | 16384 | 0.176 | 0.366 | 0.597 | 1.510 | 5.538 |
| 10000 | 8 | 65536 | 0.178 | 0.393 | 0.571 | 1.470 | 5.507 |
| 100000 | 1 | 256 | 1.503 | 2.556 | 5.429 | 20.029 | 40.595 |
| 100000 | 1 | 1024 | 1.581 | 2.577 | 6.079 | 22.586 | 40.130 |
| 100000 | 1 | 4096 | 1.823 | 2.569 | 7.226 | 20.825 | 40.099 |
| 100000 | 1 | 16384 | 1.652 | 2.848 | 5.727 | 21.981 | 40.207 |
| 100000 | 1 | 65536 | 1.590 | 2.609 | 5.640 | 19.258 | 39.419 |
| 100000 | 8 | 256 | 0.651 | 0.750 | 4.029 | 6.768 | 7.445 |
| 100000 | 8 | 1024 | 0.567 | 0.772 | 3.762 | 7.064 | 7.850 |
| 100000 | 8 | 4096 | 0.693 | 0.933 | 3.800 | 7.482 | 8.867 |
| 100000 | 8 | 16384 | 1.292 | 1.309 | 4.261 | 8.621 | 11.819 |
| 100000 | 8 | 65536 | 1.313 | 1.885 | 4.014 | 15.000 | 27.859 |
| 1000000 | 1 | 256 | 14.988 | 24.690 | 54.658 | 365.863 | 334.069 |
| 1000000 | 1 | 1024 | 14.829 | 24.431 | 55.607 | 356.657 | 327.791 |
| 1000000 | 1 | 4096 | 14.376 | 24.568 | 54.624 | 380.119 | 329.281 |
| 1000000 | 1 | 16384 | 14.589 | 24.056 | 53.402 | 351.079 | 332.263 |
| 1000000 | 1 | 65536 | 14.918 | 24.666 | 56.082 | 377.247 | 328.370 |
| 1000000 | 8 | 256 | 5.323 | 6.962 | 35.472 | 101.923 | 64.105 |
| 1000000 | 8 | 1024 | 4.486 | 5.989 | 34.061 | 99.020 | 63.328 |
| 1000000 | 8 | 4096 | 5.941 | 6.069 | 34.695 | 99.529 | 64.103 |
| 1000000 | 8 | 16384 | 5.099 | 6.375 | 33.741 | 99.081 | 67.720 |
| 1000000 | 8 | 65536 | 4.923 | 6.940 | 35.150 | 105.214 | 77.575 |

Each operation retains one hash across all grains/domain counts at each size.
Transform at grain 1,024 wins 56.1%/12.0% over 16,384 at 100k/1M; noise,
normals, scatter and mountain have no grain clearing 10% at both sizes.
These are the measured inputs to the Step 2 decision, not a claim that one
grain improves every family.

| Cold workload | Points | Domains | Median ms | Calling-domain bytes | Hash |
|---|---:|---:|---:|---:|---|
| Two independent noise chains | 2,000,000 | 1 | 206.397 | 599,645,592 | 67c129ecc130f8881a2eaf92c053b64c |
| Two independent noise chains | 2,000,000 | 8 | 75.943 | 599,976,952 | 67c129ecc130f8881a2eaf92c053b64c |
| 64 piece-list branches | 3,200,000 | 1 | 1156.556 | 1,197,148,680 | 8ef295fbdea12b586200fd1ffcdcb58f |
| 64 piece-list branches | 3,200,000 | 8 | 989.480 | 1,197,989,600 | 8ef295fbdea12b586200fd1ffcdcb58f |

The branch workload has two separately authored 1M-point grids, each with
two noise operations, merged at the root. The zone has 64 two-point curve
pieces; each copies a 25k-point grid to its two points then displaces the
result, yielding exactly 50k points per element. Element roots depend on
their actual cooked piece, so lowering cannot hoist the whole branch away.

The current baseline already parallelizes each RDK operation internally;
these times precede parallel fan-out across input branches and zone elements.
Fixture node counts, eval bytes and cook hashes match Phase 4. Capacity-512
retention remains bloom 52/1.22 MiB, sunflower 241/1.84 MiB, wave 13/0.66 MiB,
tree 27/0.87 MiB, no evictions. Focused Flow and Procedural checks pass.

## P4 residual pruning and costs (2026-10-08)

Same machine, OCaml 5.3.0 and dev profile as the P4 baseline. Static evaluation
is measured alone, without lowering/cooking, with 31 wall-time repetitions and
seven allocation repetitions per fixture. Build first, then run
`_build/default/tools/bench_workspace_lower.exe --eval`. Original and selected
executables use the same harness and checked fixture sources.

The selected residual capture constructs a map by folding its free-name set
and finding each existing lexical binding. The domain-local weak memo avoids
sharing an ephemeron table across domains. The alternative whole-environment
filter was measured before choosing the fold: wave 4.857 ms / 15,339,400 B
versus fold 4.477 ms / 16,259,560 B. The fold is faster but allocates more than
the filter. No cross-evaluation capture cache was added.

| Fixture | Original eval ms | Pruned eval ms | Original bytes | Pruned bytes |
|---|---:|---:|---:|---:|
| bloom | 0.134 | 0.119 | 537208 | 466816 |
| facade | 0.086 | 0.081 | 335808 | 286520 |
| garland | 0.080 | 0.069 | 364664 | 315336 |
| kit | 0.034 | 0.031 | 132176 | 119064 |
| orrery | 0.183 | 0.181 | 653768 | 597832 |
| rosette | 0.050 | 0.042 | 207808 | 176032 |
| sunflower | 1.061 | 0.821 | 4501136 | 3711584 |
| tiles | 0.333 | 0.279 | 1271648 | 1094648 |
| tree | 0.018 | 0.017 | 77912 | 71760 |
| tunnel | 0.023 | 0.021 | 107232 | 97200 |
| variations | 0.020 | 0.017 | 100952 | 87096 |
| wave | 4.065 | 4.477 | 17218984 | 16259560 |

The table records the first isolated original/selected round. Three later
alternating rounds, each still 31 evaluations, confirm the preparation tradeoff:
wave original 4.043/4.116/3.982 ms, selected 4.859/4.585/4.482 ms, with stable
17,218,984/16,259,560 B. Median of round medians is 4.043 -> 4.585 ms (+13.4%).
Sunflower is 0.973/1.107/0.973 -> 0.849/0.823/0.793 ms with the same stable byte
counts above. Raw CSVs are checked in under `specification/performance/` as
`p4-capture-{original,selected}-{1,2,3}.csv`.

Wave static preparation costs about 0.54 ms more for smaller retained captures;
this is not a faster-evaluation claim. Its allocation gate passes, as does
sunflower's. Sunflower has no residuals: a bounded 16-slot distinct-name fast
path in the shared named-argument evaluator removes its temporary count table.
Repeated names and wider signatures retain the existing counted routing path,
including distinct nested call identities. Boundaries 16/17 and repeated
17-slot calls have regressions.

| Fixture | Residuals | Bindings before | Kept/read after | Views before B | Views after B |
|---|---:|---:|---:|---:|---:|
| orrery | 99 | 1411 | 240 | 35186 | 21725 |
| wave | 2160 | 14580 | 6480 | 413206 | 289874 |

All other fixtures have zero residuals. Function captures are left unchanged:
garland has six captured functions / 30 bindings / 12,921 marshalled bytes;
kit has one / seven / 198 B. Neither reaches 10% of its static evaluation
bytes. Marshal is only a measurement of actual views, never a loaded artifact
or semantic key.

Focused Flow, Flow_sop, Flow_ir and workspace IR checks exit 0: all 23 standard
and custom-catalog workspaces, all 12 fixtures, static plans/instances/records
and four live times at one/eight domains preserve exact values and cook hashes.
Native pixel and shipping gates remain subject to actual Metal access; this
section does not mark the full P4 plan shipped.

### Measured CPU placement and grain decision

Run `_build/default/tools/bench_kernel.exe --cost` alone after building.
Seven medians per row; one/eight-domain hashes match exactly. Allocation is
across all participating domains. Raw rows: `performance/p4-step2-cost.csv`.

| Work / tier | Elements | Domains | Median ms | Bytes |
|---|---:|---:|---:|---:|
| Scalar closure | 1 | 1 | 0.000170 | 1328 |
| Scalar interpreter | 1 | 1 | 0.000724 | 3784 |
| Packed map CPU | 1024 | 1 | 0.040054 | 71520 |
| Packed map CPU | 1024 | 8 | 0.043154 | 72176 |
| Packed map interpreter | 1024 | 1 | 0.701904 | 3050448 |
| Packed map CPU | 65536 | 1 | 1.098871 | 767760 |
| Packed map CPU | 65536 | 8 | 0.346899 | 771008 |
| Packed map interpreter | 65536 | 1 | 46.359062 | 195038160 |
| Packed map CPU | 1000000 | 1 | 16.522884 | 11687216 |
| Packed map CPU | 1000000 | 8 | 4.155159 | 11731848 |
| Packed map interpreter | 1000000 | 1 | 710.282087 | 2976003024 |

The one-domain packed endpoints fit CPU fixed cost 23.16 microseconds and
16.50 ns/element. Interpreter cost is 710.28 ns/element; the scalar closure's
fixed cost is 170 ns. Only legal tiers compete. The static packed/interpreter
crossover is 34 elements, and placement and force-time dispatch read the same
table. Counts 0,16,33,34,512,1024,65536 and dynamic Data have focused checks;
small forced maps agree with the independent reference values. Cooked opaque
work stays Cooked and is not compared against a numeric map model. The model
is deliberately one affine row per tier; it does not infer instruction costs.

Retain the existing grain 16,384. Only transform wins at both required sizes
(56.1% at 100k, 12.0% at 1M for grain 1,024). No alternative meets the 10% gate
at both sizes for noise, normals, scatter or mountain. One Context grain
serves this mixed workload, so applying transform's optimum globally is not
supported by the sweep. The 174 RDK API defaults remain unchanged. The
inspector count alongside node timing is covered by the PL probe integration.

## P5 native baseline tool (2026-10-08)

`tools/bench_gpu.exe` measures ten cold MSL library/pipeline compilations and
seven repetitions at 1,024 / 65,536 / 1,000,000 elements, both with and without
readback. It prints compilation, CPU upload/dispatch/readback/total seconds and
the optional native GPU duration. Missing native GPU duration is NaN, never a
substituted CPU timing. Inputs are float32 positions/normals and a seeded
512-entry Perlin permutation; the scalar kernel mirrors the CPU displacement.

The compiler-only boundary passes: `tools/bench_gpu.exe --msl` writes the actual
benchmark source, and Metal 32023.921 (27.1.266.1 toolchain) compiles that source
to AIR with `metal -fmodules-cache-path=/private/tmp/rays-metal-module-cache -c
/private/tmp/p5-baseline-noise.metal -o /private/tmp/p5-baseline-noise.air`, exit 0.
The direct compiler executable is needed here because this process's xcrun
cache does not resolve the user-installed toolchain yet.

Native benchmark startup exits 2: `Ogpu_metal.Device.system_default: Metal has
no system default device`. No GPU timings, numeric tolerance or placement costs
are claimed. The mesh-packing baseline and after rows are in the separate
Scene3 float32 change; native GPU qualification remains outstanding.

## P4 cooked payload boundary (2026-10-08)

Same Apple M1 / OCaml 5.3.0 / dev profile as the baseline. `Session.output`
now carries a `Payload.Geometry` or `Payload.Image`. Geometry operators use
one typed adapter; selective component keys and refresh retain their existing
geometry rules. Images use the same atomic identity allocator as geometry and
contribute one RGBA component (32 bytes per pixel) to retained-byte accounting.
Instance materialization passes image payloads through unchanged. Public image
construction and pixel reads copy storage; the worker producer transfers its
fresh array after validation.

`image/noise` is declared as a cooked image kind with editable width, height,
frequency and seed fields. Its catalog diff contains that one new kind. Value
keys use `image:<id>` because the plan's suggested `i<id>` would collide with
the existing integer key. This spelling change prevents false value parity.

Focused Flow, Flow_sop, Procedural and catalog checks, `@check`, standard
workspace parity and both custom-catalog workspace checks exit 0. The pure
workspace harness now also cooks roots and compares actual payload bytes,
instances, plans, values and records at four times and domains 1/8 across all
23 workspaces and 12 fixtures; previously cooked comparisons ran only under
the native pixel flag. The image regression checks immutable storage, exact
one/eight-domain pixels, physical cache reuse, CLOCK eviction byte accounting,
oversized-entry eviction and `E_PAYLOAD` at a geometry consumer.

Native pixel qualification exits 1 at `Canvas.render`, with the typed
`No_adapter` error. Pixel equivalence and final `--ship` remain unverified;
the API manifest is intentionally left for promotion after branch integration.

Cold producer measurements use seven cooks per row, zero-capacity sessions,
warm shared pools and an excluded full major collection before each cook.
Elapsed time ends before an explicit `Gc.minor`; aggregate allocation uses
`Gc.quick_stat` minor + major - promoted words. Command:
`_build/default/tools/bench_workspace_lower.exe --images`, exit 0; raw rows
are `performance/p4-image-cold.csv`.

| Pixels | 1 domain ms | 8 domains ms | Aggregate allocation 1 / 8 B |
| ---: | ---: | ---: | ---: |
| 16,384 | 0.810 | 0.827 | 2,425,928 / 2,426,920 |
| 262,144 | 15.100 | 7.770 | 37,815,312 / 37,828,112 |
| 1,048,576 | 61.879 | 28.351 | 151,061,592 / 151,109,008 |

All seven repeats and both domain counts have identical pixel hashes. The
largest RGBA component is 33,554,432 bytes; allocation includes the noise
arithmetic and cook metadata, not only retained samples. There was no prior
cooked-image producer, so these are first measurements rather than an
invented before/after speedup.

### P3 drawing baseline (2026-10-08)

Arm64 native macOS workspace, OCaml 5.3.0, Dune dev profile, one domain; same machine as the
preceding M1 measurements (sandbox denied a fresh hardware `sysctl` probe). Command:
`_build/default/tools/bench_drawing.exe`; 800×600, ten warm-up and 200 timed editor updates,
run alone. Input positions are packed vec3 arrays; static and moving rows differ only by `t`.
The 06508899 baseline cannot construct graph nodes inside a packed array loop, and list loops
stop at 4096. Its benchmark-only plural declarations therefore lower the same packed inputs
through N original `Scene.circle`/`Scene.rect`/`Scene.line` calls. That instrumentation adds no
batching or retention; `draw/points` is unchanged. Scene command counts below exclude editor
chrome. Baseline snapshot and CSV: `/private/tmp/rays-p3-baseline` and
`/private/tmp/p3-baseline.csv` during the measurement session. The shipping tool is identical.

| Kind | N | Moving median / p95 (ms) | Moving bytes/frame | Static median / p95 (ms) | Static bytes/frame | Commands |
|---|---:|---:|---:|---:|---:|---:|
| circle | 1000 | 10.816 / 12.416 | 48,190,252 | .037 / .071 | 202,948 | 1000 |
| rect | 1000 | 3.299 / 3.796 | 12,574,332 | .037 / .071 | 202,948 | 1000 |
| line | 1000 | 3.017 / 3.252 | 12,837,555 | .037 / .068 | 202,948 | 1000 |
| points | 1000 | 1.490 / 1.703 | 6,871,900 | .037 / .070 | 202,948 | 1 |
| circle | 10000 | 107.897 / 115.986 | 420,786,836 | .036 / .108 | 202,948 | 10000 |
| rect | 10000 | 22.142 / 25.927 | 64,626,916 | .040 / .126 | 202,948 | 10000 |
| line | 10000 | 13.156 / 16.185 | 41,640,068 | .037 / .111 | 202,948 | 10000 |
| points | 10000 | 2.432 / 3.291 | 9,084,948 | .038 / .147 | 202,948 | 1 |
| circle | 100000 | 1079.915 / 1098.087 | 4,205,140,789 | .038 / .107 | 202,948 | 100000 |
| rect | 100000 | 229.015 / 246.529 | 643,527,892 | .039 / .125 | 202,948 | 100000 |
| line | 100000 | 129.002 / 143.717 | 412,495,661 | .038 / .122 | 202,948 | 100000 |
| points | 100000 | 16.241 / 23.236 | 80,870,102 | .037 / .106 | 202,948 | 1 |

Particle control: `_build/default/test/test_drawing.exe examples/particles/sketch.rays --bench`,
10,000 particles, median 2.991 ms, p95 4.268 ms, 9,204,964 bytes/frame. Independent static Drawing
lowering after retention: 100,000 circles, 1353 bytes/frame, the same Scene identity for 100
repeated frames; this excludes editor chrome. Native upload/draw/pixel gates are implemented
but not verified while OGPU returns `Metal has no system default device`.

P3 after rows, same command and input protocol (core commit 63939edd):

| Kind | N | Moving median / p95 (ms) | Moving bytes/frame | Static median / p95 (ms) | Static bytes/frame | Commands |
|---|---:|---:|---:|---:|---:|---:|
| circle | 1000 | 1.790 / 1.951 | 6,895,076 | .038 / .070 | 203,340 | 1 |
| rect | 1000 | 1.746 / 1.900 | 6,847,124 | .037 / .069 | 203,340 | 1 |
| line | 1000 | 2.078 / 2.311 | 9,158,364 | .039 / .085 | 203,340 | 1 |
| points | 1000 | 1.634 / 1.774 | 6,872,500 | .037 / .070 | 203,340 | 1 |
| circle | 10000 | 4.154 / 4.804 | 7,827,948 | .042 / .158 | 203,340 | 1 |
| rect | 10000 | 4.253 / 5.061 | 7,347,996 | .037 / .125 | 203,340 | 1 |
| line | 10000 | 2.240 / 2.592 | 4,841,484 | .037 / .128 | 203,340 | 1 |
| points | 10000 | 2.515 / 3.682 | 9,085,836 | .039 / .111 | 203,340 | 1 |
| circle | 100000 | 38.897 / 42.091 | 75,529,817 | .038 / .131 | 203,340 | 1 |
| rect | 100000 | 38.620 / 41.912 | 70,724,743 | .037 / .098 | 203,340 | 1 |
| line | 100000 | 14.905 / 17.092 | 44,478,027 | .038 / .119 | 203,340 | 1 |
| points | 100000 | 15.955 / 21.007 | 80,877,878 | .037 / .105 | 203,340 | 1 |

10k circles meet the 16 ms CPU editor-update gate. The 100k-circle row uses 755.3 allocated
bytes/instance, below the particle control's 920.5. All plural shapes emit one command; actual
GPU draw count remains a native qualification gate. Particle after: median 2.831 ms, p95
12.062 ms, 9,204,524 bytes/frame. Its median and allocations improve slightly; its p95 has an
outlier and is recorded without calling it an improvement. `bench_kernel --loops` completed
with every one/eight-domain CPU and interpreter digest equal through one million elements;
raw rows `/private/tmp/p3-kernel-after.txt`. A brief failed compiler lookup overlapped that
long control run, so its timings are not an isolated before/after performance claim.

## P5 Scene3 float32 display mirror (2026-10-08)

Environment: the same arm64 macOS 27.0.1 workspace as the preceding rows,
OCaml 5.3.0, Dune development profile, one initial domain. This sandbox denies
hardware queries and Metal system-device acquisition, so no current Metal
device or GPU timing is reported. These rows measure CPU packing only.

Command after building: `_build/default/tools/bench_scene3_packing.exe 1000000 7`.
Seven cold one-million-point meshes share immutable normal/index planes and
have fresh coordinate planes. Mesh construction and the preceding full major
collection are outside each sample. All other agents pause builds, tests and
timed work for the measurement. Allocation is the median `Gc.allocated_bytes`
delta; p95 is the greatest of seven samples.

| Path | Median ms | p95 ms | Allocated bytes | Vertex payload bytes | Index bytes |
|---|---:|---:|---:|---:|---:|
| Original record view and 68-byte vertex | 80.918 | 91.994 | 296,014,912 | 68,000,000 | 4,000,000 |
| Packed planes and 24+12-byte streams | 33.965 | 35.986 | 136,015,456 | 36,000,000 | 4,000,000 |

The CPU display mirror is 2.38 times faster on this fixture, with 47.1 percent
less vertex payload and 54.1 percent less allocation. It still allocates while
narrowing; no zero-allocation claim is made. CPU mesh data remains float64.
The bounded packing cache compares immutable position/normal/index planes,
mode, and color/UV planes. A color or UV change reuses geometry bytes and its
GPU key and gets a new attribute key. Both GPU streams use existing bounded
resource caches; large compatible draw groups concatenate both streams.

The mirror/component/finite-narrowing test and prepared-resource validation
test pass, as does the dependency gate (50 libraries, 51 rules, no exceptions)
and the public API manifest. Build the checks with
`_build/default/tools/check.exe lib/rays/test_main.exe lib/scene_execution/test_main.exe`,
then run `test_scene3_float32` and `test_prepared_scene3` on those executables.
The new native `test_scene3_float32_native` alias compares the legacy f64
triangle to the float32 triangle, checks color-only upload and pixel
invalidation, and checks a 65-draw coalesced attribute stream. Its current
attempt exits 2 with `Metal has no system default device`; these native checks
and the required gallery pixel comparison are **not verified**. Existing
device-dependent Rays/runtime tests fail at the same acquisition boundary.
The full native shipping gate remains outstanding.

Raw isolated measurements: `/private/tmp/p5-mesh-baseline.csv` and
`/private/tmp/p5-mesh-after.csv`.

After installation of Metal Toolchain 27.1.266.1, Apple Metal compiler
32023.921 compiles all five Scene3 variants (plain, textured, shadow, World,
sun depth) and P3's Ui/shape shader successfully. The module cache is directed
to `/private/tmp/rays-metal-module-cache`; the ordinary user cache is outside
the sandbox's writable roots. Actual Metal device acquisition still returns
`No_adapter` in this session.

The gallery oracle is now runnable through
`@examples/sop_gallery/test_scene3_float32_gallery`. It uses each cooked
gallery mesh's original float64 coordinates, normals and UVs to reconstruct
the old 68-byte vertex layout, renders that and the production mirror with
identical transforms/material/uniforms, and prints the maximum channel
difference and changed-pixel count for each graph at its first frame.
The existing IR/reference and one/eight-domain native comparisons still
require exact equality. The legacy comparison records the accepted display
precision difference; it does not manufacture a tolerance from unavailable
GPU measurements. This oracle is written but its native result remains
outstanding.

## P5 emitter and owned execution checkpoint (2026-10-08)

`flow_gpu` emits the packed register program as float32 Metal source with
one shared operator-name declaration (`Flow.Packed_ops`) read by the checker,
CPU compiler and emitter. Collect/Zip and single-source products are supported;
ordered accumulators, multi-source products and skipped elements are typed
`E_GPU_FORM` refusals. The emitter preserves zero division/modulus, absolute
power/square root, numeric boolean tests and ternary selection. Seeded Perlin
tables and 1–32-octave fBm share the existing CPU permutation.

The checked-in arithmetic, select and seeded-fBm goldens each compile to AIR
with Metal 32023.921, `-Werror` and an isolated module cache, exit 0. All 21
shared operator names have a checked packed-program emission regression.
`@check`, the emitter suite, the dependency gate and a mock ownership-only
pipeline test exit 0. The mock test adds pipeline handles to the portable
mock driver; it does not execute or validate shader numerics. It verifies
same-source reuse across different counts, capacity 64, two evictions after
66 compilations and idempotent release of every pipeline/library pair.

Each runner owns shared buffers and reusable staging bytes, grows geometrically,
writes frame/uniform bytes without dense allocations and uploads immutable
noise tables once. It reacquires the pipeline from its owner on dispatch so
cache eviction cannot leave a runner using a destroyed pipeline. Output handles
are rejected after a later dispatch supersedes them or the owner closes.
Readback explicitly checks finite output and returns fresh packed CPU arrays.
Commands are abandoned on encoding failure. GPU/cache calls reject another
domain. These are implementation properties, not measured zero-allocation or
upload-cost claims; the native repeated-frame buffer gate remains unverified.

`test_run.exe` exits 2 at `Rays_execution.acquire_gpu`, `No_adapter`. The native
oracle is ready for exact small-integer arithmetic/select comparisons and
noise error reporting at 1,024 and 65,536 elements. It deliberately requires
a measured noise tolerance before acceptance. Native reflection, GPU execution,
timings, compile placement below/above 20 ms, and the upload/zero-copy decision
have no qualifying measurements yet. Display-token integration, precision
placement/callbacks and the final million-particle gates are still outstanding.

## Conditional scopes, imports and spreadsheet checkpoint (2026-10-08)

On this arm64 macOS 27.0.1 host, the complete editor's new spreadsheet pane
over 1,000,000 points took 0.489950 ms median, 0.505924 ms p95 and
1,559,198 allocated bytes/frame over 300 idle frames at one domain.
This includes editor reduction, selected-node geometry lookup, owner tabs,
table layout and visible-cell painting; GPU presentation is outside this
headless benchmark. The UI table regression checks that a million-row table
requests at most 20 cells for a 168-point viewport, including after a large
scroll, and that its shared hit list returns the clicked row.

```sh
_build/default/tools/bench_rays_editor.exe --panels 200
```

| Complete idle editor | Nodes | Median ms | p95 ms | Bytes/frame |
|---|---:|---:|---:|---:|
| 1 graph, 1 inspector | 200 | 1.385212 | 1.652002 | 5,387,549 |
| 3 graphs, 1 inspector | 200 | 2.295017 | 2.696037 | 8,077,181 |
| 1 graph, 2 inspectors | 200 | 1.621008 | 1.866102 | 5,791,373 |
| 3 graphs, 2 inspectors | 200 | 2.488136 | 2.816200 | 8,481,341 |
| Spreadsheet | 1,000,000 points | 0.489950 | 0.505924 | 1,559,198 |

Focused checks pass for conditional arm paths, rails, probes over time,
collapse/menu/keyboard gestures and one-step history; imported-file polling,
held reloads, missing/recreated files, read-only refusals, library Open/edit/save,
completion, CLI embedding/dependencies and exact authored-source saves; owner
counts, pane following, tab changes, recooks, table virtualization and layout
round trips. The full `.rays` literal/save sweep and full workspace IR oracle
at four times and one/eight domains pass, including the shared-library pair,
the import fixture and the spreadsheet sketch.

Native verification is still open. `--ship` exits 1 on native Metal/SDL/audio
availability errors and the intended API manifest diff pending integration
promotion. The screenshot commands for `ws_kit` and `ws_spreadsheet` fail with
`Ogpu_metal.Device.system_default: Metal has no system default device` in the
managed sandbox. The conditional token golden refresh and new
`kit_table_1x.png` capture/comparison paths are implemented, but no new native
pixels or goldens were produced. Existing 2x kit goldens are untouched.

Evidence: `/private/tmp/pl-final-ship.log`, `/private/tmp/pl-native-kit.log`,
`/private/tmp/pl-native-spreadsheet.log`, `/private/tmp/pl-native-goldens.log`.
These native gates must pass on a session with an available display/Metal
adapter before the PL item can be marked shipped.
## P4 branch fanout and placement calibration (2026-10-08)

Same Apple M1/macOS/OCaml 5.3.0/Dune 3.24.2 development setup as the P4
baseline. Seven repetitions, pools warm, one or eight domains, grain 16,384;
all builds and other timed runs held. One initial OFF run overlapped a port
build and was discarded. Cache capacity is 512 entries/256 MiB. `learned`
first cooks without timing, then clears payload/cache metadata while retaining
node durations. Completely fresh sessions intentionally stay sequential.

```sh
_build/default/tools/bench_workspace_lower.exe --branches 7 off
_build/default/tools/bench_workspace_lower.exe --branches 7 learned
_build/default/tools/bench_workspace_lower.exe --loops 7 off
_build/default/tools/bench_workspace_lower.exe --loops 7 learned
```

| Workload | Placement | Domains | Median ms | Caller bytes | Program bytes | Fanouts |
|---|---|---:|---:|---:|---:|---:|
| Two chains, 2M points | off | 1 | 203.448 | 599,647,000 | 599,647,288 | 0 |
| Two chains, 2M points | learned | 1 | 208.250 | 599,646,552 | 599,646,840 | 0 |
| Two chains, 2M points | off | 8 | 84.972 | 599,971,944 | 601,315,904 | 0 |
| Two chains, 2M points | learned | 8 | 74.798 | 422,030,096 | 601,439,440 | 1 |
| 64 pieces, 3.2M points | off | 1 | 1318.181 | 1,197,214,904 | 1,197,215,192 | 0 |
| 64 pieces, 3.2M points | learned | 1 | 1360.161 | 1,197,202,152 | 1,197,202,440 | 0 |
| 64 pieces, 3.2M points | off | 8 | 1225.773 | 1,198,075,576 | 1,200,097,624 | 0 |
| 64 pieces, 3.2M points | learned | 8 | 258.914 | 795,290,520 | 1,208,525,328 | 1 |

Both full authored geometry hashes are unchanged from Step 0:
`67c129ecc130f8881a2eaf92c053b64c` (chains) and
`8ef295fbdea12b586200fd1ffcdcb58f` (pieces). Four complete CSVs, including
the hashes, are in `specification/performance/p4-fanout-*.csv`. Program bytes
come from whole-program `quick_stat` counters after an excluded minor
collection; caller bytes alone decrease because work moves to other domains,
not because allocation vanished. The loop's total allocation rises 0.7%.

The first placement implementation gated only the final node's own seconds.
That left the loop entirely sequential (1248.622 ms, zero fanouts): its noise
suffix takes less than 2 ms while its Copy to Points ancestor is expensive.
Placement now sums measured own durations of the uncached physical-node
subtree, stopping at shared memo results and cache hits. The named 2 ms
threshold remains; the source grid is prefetched once in original DFS order.
Read-only cache predictions are memoized within each placement pass. Component
cache refreshes and their unresolved consumers stay inline until their real
output identities are available.

The loop is 4.73x faster than the current eight-domain OFF path and 3.82x
faster than Step 0's eight-domain row. The chains improve 1.14x against the
current OFF path and are close to Step 0 (75.943 ms); their additional 1.5x
target is **not met**. No small-fixture speed or native shipping gate is
claimed by this table.

Focused Procedural and Lru checks pass. Permanent branch checks cover actual
two-worker overlap, one/eight-domain allocating geometry and zone byte
identity, shared ancestors cooked once, exact immutable-plane cache keys and
counters, CLOCK eviction invalidation, volatile/zero-capacity caches, packed
materialization, reused IDs, warm/refresh hits staying inline, learned cheap
suffix placement, diagnostics order and cancellation. Cache keys containing
fresh runtime data IDs are deliberately not compared across separate allocating
runs; immutable shared-plane fixtures exercise exact key equality directly.
Native GPU and shipping checks remain pending in this restricted session.

## Advisory GPU path audit (2026-10-08)

`_build/default/tools/bench_workspace_lower.exe --approx` passes against all
27 actual example/sketch/kit files, including the generated SOP gallery and
voxel wall with their own custom catalogs. The particle workspace reports
six paths: `picture/initial_velocity`, `picture/particles/position`,
`picture/particles/bounced_velocity`, and that map's `#0/:p`, `#0/@result`
and `#0/@result#test` body paths. `sketches/flow_kernel/sketch.rays`
reports `terrain/updated`; every other file reports an empty set.

This set is advisory: it describes supported typed float/Vec3 packed bodies
and their propagated values, including frame uniforms. Actual GPU placement
must also have a compiled packed producer and satisfy the precision passes.
Exact forms, folds, list/filtered maps, unsupported operations, incompatible
parameter annotations, multiple comprehension clauses, catalog-valued
operations and dynamic noise seed/octave parameters are excluded by the
checker regressions. The workspace reference oracle passes at four times
and one/eight domains with this metadata enabled. No approximate GPU result
is claimed by this checker audit.

Evidence: `/private/tmp/p5-approx-paths-final.log`,
`/private/tmp/p5-checker-final.log`, `/private/tmp/p5-checker-validation.log`.

## PL original-checkout comparison and probe correction (2026-10-08)

The original `06508899` binaries and the PL binaries ran in separate
checkouts on the same host, with all other agents' builds and tests stopped.
The complete editor benchmark uses 200 samples at one domain:

```sh
_build/default/tools/bench_rays_editor.exe 200 1000 2000
```

| Nodes | Drag median before/PL ms | Scrub edit median before/PL ms | Drag bytes/frame before/PL |
|---:|---:|---:|---:|
| 200 | 2.175093 / 2.102852 | 2.100945 / 2.140999 | 7,116,010 / 7,121,154 |
| 1,000 | 7.857084 / 7.589102 | 7.178068 / 7.408142 | 21,567,089 / 21,576,553 |
| 2,000 | 12.734890 / 12.851000 | 11.348963 / 11.459112 | 32,928,409 / 32,937,873 |

The scope benchmark revealed repeated forcing: asking for one iteration
previously forced every recorded iteration at that path. `Probe.at` now
forces only the selected tuple, and the arm zones and conditional footer
share the parent's taken-arm result. Both selected-value and taken-arm
memos use the existing 4,096-entry bound. A runnable regression counts
geometry summaries to prove that a repeated selected lookup forces one
tuple only; separate tuples, missing records and changing frame times are
also checked.

The final isolated 300-frame scope runs use the original binary and then
the corrected PL binary, from each checkout's `_build/default/test` directory
(the fixtures there are generated by Dune):

```sh
../lib/pxui_graph/test_main.exe bench_scope_pane
```

| Scope | Before ms/frame | PL ms/frame | Before/PL bytes/frame |
|---|---:|---:|---:|
| Sunflower expanded, records | 0.238 | 0.223 | 853,872 / 853,912 |
| Sunflower collapsed, records | 0.042 | 0.037 | 152,184 / 152,224 |
| Orrery, no records | 0.460 | 0.518 | 1,720,640 / 1,904,584 |
| Orrery, live records | 0.587 | 0.698 | 2,207,192 / 2,654,000 |

The new Orrery conditional-arm UI still costs more than the original rows
and chips. The probe correction removes 172,032 allocated bytes/frame from
the first PL implementation, but the scope's within-noise no-regression
gate remains unmet; this is not evidence to close it. The complete-editor
drag/scrub samples remain close to baseline. Native pixels remain unverified
as recorded above.

Evidence: `/private/tmp/pl-editor-before.log`,
`/private/tmp/pl-editor-after.log`, `/private/tmp/pl-scope-before-isolated.log`,
`/private/tmp/pl-scope-after-isolated.log`, `/private/tmp/pl-probe-fix-check.log`.
An earlier remeasure overlapped another agent's build and was discarded.
## PL image attribute sampler (2026-10-08)

Apple M1, arm64 macOS 27.0.1, OCaml 5.3.0, dev profile. Command from the
isolated clone: `_build/default/lib/procedural/test_attr_from_image.exe --bench`.
All agents confirmed their processes were terminal before the run. One million
Point Float2 UVs sample a 2×2 RGBA image through the actual SOP and an uncached
Session; each trial also copies the public float attribute for reading. After
warmup, seven trials at grain 16,384 gave these wall-time medians:

| Domains | Median | Caller-domain allocation per trial |
|---:|---:|---:|
| 1 | 52.543 ms | 112,015,560 bytes |
| 8 | 14.498 ms | 29,111,616 bytes |

Allocation uses `Gc.allocated_bytes` on the caller; worker allocation is
excluded, so these rows do not demonstrate a reduction in total allocation.
The new operation has no pre-change timing. Every trial compares its complete
float attribute byte-for-byte with the one-domain result. Focused tests also
check channels/luminance, bilinear corner and interior values, clamped UVs,
Float3/custom UV names, single-row/column images, malformed input, cancellation,
typed payload errors, and preservation of position/topology identities.
The generated mixed input signature is checked, projected, connectable and
disconnectable; the actual editor add gesture supplies a real image default.
Final P3 core remeasurement (1a18b6ef, same 10 warm/200 timed frames, dev, one domain,
800×600; all other agent builds/tests/timers held):

| Kind | N | Moving median / p95 (ms) | Moving bytes/frame | Static median / p95 (ms) | Static bytes/frame | Commands |
|---|---:|---:|---:|---:|---:|---:|
| circle | 1000 | 1.897 / 2.162 | 6,999,260 | .040 / .065 | 203,388 | 1 |
| rect | 1000 | 1.863 / 2.088 | 6,951,308 | .039 / .065 | 203,388 | 1 |
| line | 1000 | 2.299 / 2.726 | 9,334,588 | .039 / .064 | 203,388 | 1 |
| points | 1000 | 1.650 / 1.999 | 6,976,684 | .039 / .071 | 203,388 | 1 |
| circle | 10000 | 4.735 / 5.824 | 7,828,108 | .040 / .123 | 203,388 | 1 |
| rect | 10000 | 4.596 / 5.326 | 7,348,156 | .040 / .178 | 203,388 | 1 |
| line | 10000 | 2.891 / 4.017 | 5,001,676 | .040 / .127 | 203,388 | 1 |
| points | 10000 | 2.622 / 7.224 | 9,085,996 | .040 / .164 | 203,388 | 1 |
| circle | 100000 | 43.336 / 50.904 | 75,558,320 | .040 / .122 | 203,388 | 1 |
| rect | 100000 | 43.266 / 53.008 | 70,764,902 | .040 / .108 | 203,388 | 1 |
| line | 100000 | 20.656 / 24.589 | 46,136,860 | .040 / .159 | 203,388 | 1 |
| points | 100000 | 16.610 / 23.316 | 80,908,707 | .040 / .110 | 203,388 | 1 |

Final particle control: 3.091 ms median, 7.265 ms p95, 9,204,988 bytes/frame. Against the
original 2.991 ms / 4.268 ms / 9,204,964 bytes, its median is 3.3% slower and p95 is higher;
the allocation delta is 24 bytes/frame. Do not call this control a speed improvement.
The required circle gates still pass: 10k below 16 ms; 100k at 755.6 bytes/instance versus
the control's 920.5. Separately, retained 100k Drawing lowering is 1393 bytes/frame after the
clock split, below 32768 and independent of editor chrome. CSVs in this session:
`/private/tmp/p3-final-after.csv`, `/private/tmp/p3-final-particles-after.txt`.

All eight source ports (`basic`, `generative`, `noise`, `recursive_rectangles`, `drawing`,
`audio`, `file_dialog`, `pxui`) pass source roundtrip, four synthetic frames, six interpreter/CPU
modes at one/eight domains and an independent authored-parameter comparison with the original
`main.ml` compiled by `tools/port_oracle`. Recursive minimum/maximum depth and large native
integer hashes pass as well. A separate 10k moving-circle workspace passes six-mode command
identity and is included in the native four-PNG export gate.

Native qualification remains pending. `test_shape_batch native` and `ui_shot basic` exit 2
with `Metal has no system default device`; native exports exit 2 at SDL startup with
`The video driver did not add any displays` and macOS display-service XPC errors. The Ui MSL
source compiles offline to AIR with the installed Metal compiler and an explicit writable
module cache. This establishes shader syntax, not raster correctness. Native one-draw/static
zero-upload counters, SDF/reference per-pixel tolerance, particle/port PNG identity, host PNG
capture, all port smoke runs and eight editor layout PNGs must be run with a visible display
and Metal device; no artifact or native passing result is substituted for those gates.

Final validation after the packed-line color declaration correction: `@lib/flow/runtest`,
`@lib/flow_ir/runtest`, `@test_2d_ports`, the pure particle/drawing executable and `@all`
pass. `SDL_AUDIODRIVER=dummy _build/default/tools/check.exe --ship` exits 1: native tests
cannot acquire Metal, smoke cannot initialize a display, and the intended public API diff
awaits promotion after integration as required for worktree changes. The initial shipping
attempt found and fixed `draw/lines :color` rejecting packed RGB arrays at the checker boundary;
the existing colored-line test now passes. Logs: `/private/tmp/p3-final-focused.log`,
`/private/tmp/p3-final-drawing.log`, `/private/tmp/p3-final-ship-fixed.log`.

`@runtest-native` and `@smoke-all` were also attempted and exit 1 at the same native boundaries.
All eight Lisp smoke entries ran and failed before the first frame with no display. Their
locks now refer to the existing root smoke lock, so the added programs run sequentially.
Every port's `ui_shot` was attempted separately; all eight exit 2 with no system default Metal
device and produce no PNG. Logs: `/private/tmp/p3-final-native.log`,
`/private/tmp/p3-final-smoke-all-serial.log`, `/private/tmp/p3-ui-<name>.log`.

## PL scope cost correction (2026-10-08)

Same Apple M1, macOS 27.0.1, OCaml 5.3.0 and development profile as the
original-checkout comparison above. Three alternating original `06508899`/PL
runs used the same generated fixtures, 20 warmup frames and 300 measured
frames per mode. All agents' build, test and compiler processes were stopped
for the complete timing slot. From each checkout's `_build/default/test`:

```sh
../lib/pxui_graph/test_main.exe bench_scope_pane
```

| Scope | Before median ms/frame | PL median ms/frame | Before/PL bytes/frame |
|---|---:|---:|---:|
| Sunflower, no records | 0.212 | 0.187 | 851,608 / 744,712 |
| Sunflower expanded, records | 0.214 | 0.188 | 853,872 / 746,976 |
| Sunflower collapsed, records | 0.035 | 0.033 | 152,184 / 147,168 |
| Orrery, no records | 0.456 | 0.456 | 1,720,640 / 1,691,432 |
| Orrery, live records | 0.579 | 0.561 | 2,207,192 / 2,127,696 |

The paired Orrery samples were, in before/PL ms/frame order:
no-record `0.460/0.455`, `0.456/0.456`, `0.443/0.475`; live-record
`0.569/0.561`, `0.579/0.555`, `0.586/0.589`. The no-record median matches
baseline and the live-record median falls by 3.1%; individual runs remain
noisy. Both modes allocate less than baseline. These isolated samples close
the scope's within-noise no-regression gate that remained open in the earlier
measurement; they do not qualify native pixels or other shipping gates.

The opt-in `RAYS_SCOPE_PROFILE=1` benchmark uses the standard-library allocation
profiler and prints its eight largest sampled stacks per mode. Its callback
allocations distort its timing, so the acceptance runs above leave it unset.
The profile identified per-wire-hit `Printf.sprintf` and idle-frame `Ui.signal`
allocation. Shared wire key generation now builds identical IDs from per-wire
and per-segment prefixes; the press scan runs only on an actual left-button
press. The same boxes, ordering, clipping and shared UI capture remain in use.
Probe footers count raw records without summarizing every tuple and attempt
sparklines only for numeric, boolean or dynamically typed results. Public full
record/series inspection and numeric sparklines retain their existing behavior.
No cache, dependency or reduced conditional-arm presentation was added.

Focused Flow_graph, Probe and graph-pane checks pass, including all 435 pane
checks, a wire-select/disconnect check and counted deferred geometry summaries
showing that a footer and a missing probe do not force unrelated tuples.
Evidence: `/private/tmp/pl-scope-allocation-profile.log`,
`/private/tmp/pl-scope-probe-count-check.log`, and the six paired files
`/private/tmp/pl-scope-{old,new}-final-{0,1,2}.log`.

### P5 emitted-kernel benchmark instrumentation (2026-10-08)

`tools/bench_kernel.exe --gpu` now measures the existing exact CPU/native noise rows,
emitted GPU noise at 1,024/65,536/1,000,000 elements with and without array readback,
and full CPU/GPU editor frames at 10,000/1,000,000 noise-driven circles. Runner upload and
synchronized dispatch share one honest column; the fixed-cost `bench_gpu` tool separates them.
Cold compile, input preparation, GPU duration, readback, allocation, buffer reuse and actual
readback maximum error are reported. Editor GPU policy is explicitly qualification-only;
device-duration deltas include compute, conversion and rendering on the shared device.

Build and `--gpu-check` pass. The latter checks emitted fixtures, exact counts and target
approximate paths, plus exact 1,024-element CPU/native noise equality at one/eight domains.
An isolated `--gpu` attempt exits 2 before any measurement row: no system default Metal device.
The actual backend kind at this point is `Device_lost`, not `No_adapter`; the tool reports the
received kind instead of inventing a classification. Log: `/private/tmp/p5-kernel-gpu-startup.log`.
No GPU compile/upload/dispatch/readback timings, tolerance, allocation gate or CPU/GPU editor
speedup is established by this startup attempt. These measurement gates remain open.

The subsequent adapter-boundary correction maps only the unavailable system-default device
to `No_adapter`; registry-query and other native failures retain `Device_lost`. Its pure
classification check passes every existing Metal error kind. The actual `--gpu` retry exits 2
and prints `No_adapter: Ogpu_metal.Device.system_default: Metal has no system default device`
before any row. Log: `/private/tmp/p5-kernel-gpu-no-adapter.log`. `--gpu-check` remains green.

P5 explicit SOP readback now scopes the neutral backend around the initial-domain
value lane, as well as drawing. Input-independent `(exact (map ...))` producers
can materialize to owned CPU arrays before worker submission; an unwrapped
selected producer is refused with `E_APPROX_SINK`. Attribute-reading cones retain
their existing cooked-input CPU path. `Executor.try_display` leaves the normal
worker path intact when placement is unmeasured or unsupported instead of doing
an unnecessary CPU evaluation on the initial domain. References and exports keep
the independent CPU path. Native cost/tolerance/readback timing remain unverified.
The real-Lisp 2,048-element `test_attribute_kernel` regression passes callback
and readback counts across two live frames, exact positions after one/eight-domain
cooking, unknown-cost CPU placement, scoped qualification, reference/no-backend
CPU behavior and refusal of the unwrapped selected SOP producer. These neutral
callback checks do not execute native shader arithmetic. Focused `@check`,
`@lib/flow_ir/runtest` and `@lib/flow_sop/runtest` pass.

## P3 completion-audit checks (2026-10-08)

The native shape suite now compares independently constructed legacy rectangles with
packed rectangles at 63, 64, 65 and 100,000 instances, requiring exact pixels. The
circle rim gate uses distance from pixel sample centers to the actual integer 32-gon
edges and permits at most one logical pixel. Existing transformed/alpha/stroke/blend
checks and the 100k one-draw/zero-retained-upload assertions remain. The port suite
requires exact legacy pixels for the noise example's opaque integer filled rectangles;
circle, rotated-rectangle and stroked examples retain their recorded edge tolerance.
All eight ports also send Command-S through the editor and check atomic replacement
with unchanged source bytes and comments. Flow IR sweeps every external color/noise
operator's declared arguments and choices without adding a Flow dependency on IR.

The three already-built focused executables (`lib/rays/test_shape_batch.exe`,
`lib/flow_ir/test_ir.exe`, and `test/test_2d_ports.exe`, each from its build directory;
ports use `SDL_AUDIODRIVER=dummy`) exit 0. Logs are
`/private/tmp/p3-audit-shape-pure.log`, `/private/tmp/p3-audit-ir.log`, and
`/private/tmp/p3-audit-ports.log`. The launcher request for
`@lib/rays/test_shape_batch @lib/flow_ir/runtest @test_2d_ports` exits 1 because it also
runs native-dependent Rays test siblings, which cannot acquire Metal; its complete log
is `/private/tmp/p3-audit-focused.log`. No timing rows were produced by this check.

`test_shape_batch.exe native` exits 2 with `Metal has no system default device`
(`/private/tmp/p3-audit-shape-native.log`). The added native assertions are compiled,
but their raster results are unverified. Existing native/export/smoke/layout-PNG gates
and the recorded particle p95 regression remain open; no goldens or tolerances were
relaxed to obtain a passing result.

## PL completion audit: actual scrolling and image ownership (2026-10-08)

The stronger million-row table check exposed a scrolling bug: absolute rows
were siblings of the scrolling extent, so their positions did not move with it.
Rows now belong to that extent. The fixed-size virtual table applies the existing
wheel/trackpad/coast state before choosing its visible range and consumes that
input before layout. Its regression requires a full viewport at the expected
row immediately after a 10,000-row jump, the exact clicked row, continued wheel
motion, trackpad motion and coasting. The earlier temporary 0.194073 ms scroll
row is discarded: it measured a table whose rows had not scrolled.

All agents explicitly held builds/tests/compilers before the isolated run on the
same Apple M1/macOS/OCaml setup. The existing `--panels 200` command now sends
wheel events inside the complete editor's spreadsheet and verifies the selected
source remains one million points. Each spreadsheet row measures 300 warmed
frames at one domain, including reduction, cell formatting, layout and painting;
native presentation is outside this window-free benchmark.

| Full editor, 1,000,000 points | Median ms | p95 ms | Bytes/frame |
|---|---:|---:|---:|
| Idle spreadsheet | 0.513077 | 0.535965 | 1,561,798 |
| Scrolling spreadsheet | 0.524044 | 0.544071 | 1,603,245 |

The workspace oracle reuses production `Workspace_images` ownership and its
scoped initial-domain payload resolver for image roots, drawing images and
Scene3 image textures. Explicit plan/state/frame overrides keep the four-time
IR/reference comparison independent of the owner's default frame. Pure checks
cover live noise and loaded images feeding SOP attributes, drawing commands and
textures at four times on one/eight domains; they verify changing frame overrides
change image bytes and all owned images close exactly once.

That check also found live image constructors becoming residual image roots.
The three existing image declarations now preserve constructor arguments through
their existing non-splicing shape. Real live noise/load/render roots remain typed
deferred image nodes and their live fields force at the requested time. The Flow,
PXUI and editor shell focused suites pass, including spreadsheet retyping and its
save/load round trip. Native image/render/export pixels, screenshots and golden
refreshes remain unverified because the sandbox has no system-default Metal
device; command/resource checks do not qualify those gates.

Evidence: `/private/tmp/pl-oracle-scroll-fixed-build.log`,
`/private/tmp/pl-image-live-final-build.log`, `/private/tmp/pl-image-live-final-pure.log`,
`/private/tmp/pl-spreadsheet-scroll-fixed-isolated.log`.

## P4 noise displacement storage (2026-10-08)

Same Apple M1/macOS/OCaml 5.3.0/Dune 3.24.2 development setup. Two isolated
before/after slots; all agents held builds and other execution. Branch and zone
rows are seven cold trials, one/eight domains, grain 16,384, with an excluded
learning cook and payload clearing for `learned`. Session capacity remains
512 entries/256 MiB. Commands:

```sh
_build/default/tools/bench_workspace_lower.exe --branches 7 off
_build/default/tools/bench_workspace_lower.exe --branches 7 learned
_build/default/tools/bench_workspace_lower.exe --loops 7 learned
_build/default/tools/bench_workspace_lower.exe _build/default/specification/workspace/cases 21
```

Height displacement previously copied all three position planes and allocated
a fourth samples plane. It now borrows immutable X/Z, owns Y, and temporarily
stores samples in Y before applying the original arithmetic against source Y.
Normal displacement keeps three owned outputs and uses Z as its samples plane,
reading original positions from immutable source planes. No public parameter,
topology, normal invalidation, grain, or cache accounting changes.

| Workload | Placement | Domains | Before ms | After ms | Before program bytes | After program bytes |
|---|---|---:|---:|---:|---:|---:|
| Two chains, 2M points | off | 1 | 199.576 | 194.368 | 599,648,696 | 503,648,184 |
| Two chains, 2M points | off | 8 | 76.219 | 76.692 | 601,319,072 | 505,317,696 |
| Two chains, 2M points | learned | 1 | 203.073 | 203.938 | 599,648,472 | 503,647,960 |
| Two chains, 2M points | learned | 8 | 73.731 | 64.264 | 601,441,872 | 505,439,480 |
| 64 pieces, 3.2M points | learned | 1 | 1243.860 | 1285.643 | 1,197,273,136 | 1,120,464,944 |
| 64 pieces, 3.2M points | learned | 8 | 273.888 | 286.322 | 1,208,601,248 | 1,131,795,424 |

The learned eight-domain chain median drops 12.8%, with 16.0% less whole-program
allocation. The loop allocation drops 76.8 MB, while its median rises 3.4% at one
domain and 4.5% at eight; this pair establishes no loop runtime improvement.
The chain remains only 1.19x faster than the current OFF path and 1.18x faster
than Step 0's 75.943 ms: the required additional 1.5x gate is **still unmet**.
The loop remains over 3x faster than Step 0. Both complete authored geometry
hashes remain `67c129ecc130f8881a2eaf92c053b64c` and
`8ef295fbdea12b586200fd1ffcdcb58f` respectively.

The twelve-fixture run uses 21 check/eval/lower trials and seven cook trials,
default eight-domain Context (the old tool heading `cook1` was misleading).
All hashes, node counts, eval allocation, capacity retention/evictions and
payload totals match before/after. Individual small cook medians vary in both
directions, including fixtures without noise displacement, so this pair does
not establish the separate within-noise performance gate. Raw full outputs:
`performance/p4-height-{before,after}-{off,learned,loops}.csv` and
`performance/p4-height-{before,after}-fixtures.txt`.

`@lib/rdk/runtest`, `@lib/procedural/runtest` and `@check` pass. The regression
compares independent scalar height/normal formulas and complete geometry bytes
at one/eight domains, including oversized grain, source immutability,
immutable X/Z sharing, owned Y, preserved topology and normal invalidation.
Native rendering and shipping remain unverified; these CPU measurements do
not establish GPU behavior or close the native gates.

## P3 full static editor allocation investigation (2026-10-08)

The absolute static `Editor.update` gate is **still unmet**. The earlier
203,388-byte full-editor row and the 1,393-byte retained Drawing-only row measure
different boundaries; the latter does not satisfy the 32,768-byte full-update
limit.

On the integrated `ae4bd1c3` checkpoint plus `e689a570` test changes, the existing
`tools/bench_drawing.exe 100000 --static` isolates one row without changing the
editor path: 800×600, one domain, ten warm-up and 200 timed updates, Dune dev,
OCaml 5.3.0, the same arm64 macOS machine as the drawing rows above. Every other
agent held builds, tests, compilers and timers during each measurement.

| Static full editor, 100k circles | Median (ms) | p95 (ms) | Bytes/frame | Picture commands |
|---|---:|---:|---:|---:|
| Before camera decode reuse | .039101 | .062943 | 204,620 | 1 |
| After camera decode reuse | .036001 | .059128 | 176,868 | 1 |

The narrow change saves 27,752 bytes/frame (13.6%). `Viewport3.on_view` reuses its
active-camera decode within the current update. It decodes again if viewport
movement writes a replacement immutable camera node. It adds no persistent
cache and preserves invalid/absent-camera and camera-follow behavior. Existing
workspace-shell camera zoom/multiview tests and window-free editor camera/lens
logic checks pass; the focused alias also supplies their generated fixtures.
The sandbox still denies autosave writes to the user's preferences directory;
these tests report that restriction and exit zero.

`--static --profile` uses the existing standard-library Memprof sampling pattern
at 0.001, with 20-frame call stacks. Its wall time and allocation row are
discarded. Before the fix, 5,142 sampled words grouped by named stack callers
were UI building/other UI work 1,573, other editor work 1,316, camera decoding
1,169, UI painting 853, immutable batch snapshots 104, editor reduction 75,
key routing 48 and UI arrangement 4. These are sampled stack categories, not
exact byte accounting; allocations raised inside arrangement also occur in
the broader categories. Largest concrete sites include the arrangement
closures in `pxui/ui.ml:1497` and `:1515`, paint rectangle/clip tuples in
`:1817–1848`, and layout-label/keymap list rebuilding in
`rays_editor/core_actions.ml:123–151`.

The UI already retains box/layout/hit arrays and reuses its batch builder.
`Ui_batch.Builder.publish` copies the bytes once for the immutable returned
Scene snapshot; `Scene.Private.ui` borrows that snapshot, so there is no second
copy to delete. Removing this copy or skipping painting/input/layout work would
change required behavior. Reaching 32 KiB needs broader allocation work across
the UI and immutable editor update path; this investigation does not claim to
close that gate. Native rendering qualification remains unavailable.

Session evidence: `/private/tmp/p3-static-editor-baseline.csv`,
`/private/tmp/p3-static-editor-camera-after.csv`,
`/private/tmp/p3-static-editor-profile-aggregate.log`,
`/private/tmp/p3-static-camera-shell-alias.log` and
`/private/tmp/p3-static-camera-logic.log`.
## P4 two-dimensional noise plane (2026-10-08)

Same machine, OCaml 5.3.0 development profile, grain 16,384 and bounded session
protocol as the immediately preceding displacement-storage rows. Builds and
focused checks completed before an isolated timing slot; all agents held other
execution. Commands are `bench_workspace_lower.exe --branches 7 learned`,
`--branches 7 off`, and `--loops 7 learned`, followed by a second learned-chain
run. Raw outputs are `performance/p4-noise2d-after-*.csv`; the before rows are
`performance/p4-height-after-*.csv`.

`Noise.sample2` and its packed writer now evaluate only the four lower-plane
corners of the existing three-dimensional Perlin function at Z=0, where the
upper-plane interpolation weight is zero. The general 3D function is unchanged.
The same fade, gradient and lower-plane interpolation operations are reused.
An independent scalar regression compares output float64 bits with the
unchanged `sample3 ~z:0.` over five seeds, signed-zero/integer boundaries,
large coordinates and 100,000 packed samples. Existing scalar/deformation tests
and exact one/eight-domain packed comparison pass.

| Workload | Placement | Domains | Before ms | After ms | Repeat ms |
|---|---|---:|---:|---:|---:|
| Two chains, 2M points | learned | 1 | 203.938 | 162.658 | 162.043 |
| Two chains, 2M points | learned | 8 | 64.264 | 56.753 | 63.550 |
| Two chains, 2M points | off | 1 | 194.368 | 156.236 | — |
| Two chains, 2M points | off | 8 | 76.692 | 66.448 | — |
| 64 pieces, 3.2M points | learned | 1 | 1285.643 | 1366.437 | — |
| 64 pieces, 3.2M points | learned | 8 | 286.322 | 286.067 | — |

The one-domain chain median improves 20.2–20.5%. Eight-domain chain medians
vary materially between the two after runs, so this slot does not establish
a stable parallel speedup. The first after row is 1.34x faster than Step 0's
75.943 ms, and the repeat is 1.20x: the required 1.5x chain gate remains unmet.
The one-domain loop median increases 6.3%, while the eight-domain row is similar;
no loop improvement is claimed. Whole-program allocated bytes remain unchanged
at one domain; multi-domain differences are small scheduler allocations.
Complete chain and loop hashes remain `67c129ecc130f8881a2eaf92c053b64c` and
`8ef295fbdea12b586200fd1ffcdcb58f`. These observations do not close the separate
small-fixture within-noise or native shipping gates.

## P3 UI arrangement allocation follow-up

`Ui.arrange` experiment, same machine/profile, command, input and
ten-warm/200-timed protocol: three alternating saved-703a7113/current executable
runs, all other agents explicitly terminal/held. All six commands exit zero.

| Full static editor, 100k circles | Median trials (ms) | p95 trials (ms) | Bytes/frame in every trial |
|---|---|---|---:|
| Before linked-child loops | .035048 / .036001 / .036001 | .058889 / .071049 / .060081 | 176,868 |
| After linked-child loops | .035048 / .035048 / .035048 | .066996 / .066996 / .062943 | 172,100 |

The allocation saving is 4,768 bytes/frame (2.7%); these small wall-time samples
do not establish a p95 improvement. The two arrangement passes now follow the
existing `b_first`/`b_next` links directly, which lets their float references
remain local rather than escape through per-box callbacks. Canvas transform
scalars are bound individually rather than packed in a six-float tuple. Child
order, float arithmetic, relative/grow sizing, placement and scrolling are
unchanged. No new storage, API, cache or skipped UI/input work is introduced.
The existing `@lib/pxui/test_ui` regression exits zero, covering interaction at
1x/2x, scroll/trackpad behavior, and transformed canvas geometry, IME and hits.
Native pixel parity remains unavailable. The literal 32,768-byte full-editor
allocation gate remains **unmet** (172,100 bytes/frame).

Evidence: `/private/tmp/p3-ui-arrange-before-{1,2,3}.csv`,
`/private/tmp/p3-ui-arrange-after-{1,2,3}.csv` and
`/private/tmp/p3-ui-arrange-check.log`.

The next isolated change moves `Viewport3.navigate`'s `follows` decode behind
the existing look-through/active-camera condition. A normal orbit does not use
that boolean; a look-through still evaluates it and releases relative/fly input
for a fixed camera exactly as before. Existing window-free camera/lens and
workspace-shell camera/multiview regressions exit zero. Three alternating
old/new full static-editor trials (same protocol, all other agents held):

| Full static editor, 100k circles | Median trials (ms) | p95 trials (ms) | Bytes/frame in every trial |
|---|---|---|---:|
| Before navigation short-circuit | .035048 / .035048 / .036001 | .066996 / .070095 / .058889 | 172,100 |
| After navigation short-circuit | .034094 / .034094 / .034094 | .056982 / .061989 / .056028 | 162,876 |

The allocation saving is 9,224 bytes/frame (5.4%). The full 32,768-byte gate
remains **unmet**. All six benchmark commands exit zero. Evidence:
`/private/tmp/p3-camera-navigate-before-{1,2,3}.csv`,
`/private/tmp/p3-camera-navigate-after-{1,2,3}.csv` and
`/private/tmp/p3-camera-navigate-check.log`.

The bottom-up intrinsic-size pass has the same captured-float-reference pattern
as arrangement. First, an `inline always` annotation on the existing child-walk
helper was tested and reverted: all three old and new full-editor trials
allocated exactly 162,876 bytes/frame. No allocation win was observed.

Replacing only the intrinsic-size child callback with the existing linked-child
while loop does save allocation. Its accumulation order and sizing arithmetic
are unchanged; the existing 1x/2x UI interaction, scroll and transformed-canvas
checks exit zero. Three alternating old/new trials, same protocol and exclusive
execution holds, all commands exit zero:

| Full static editor, 100k circles | Median trials (ms) | p95 trials (ms) | Bytes/frame in every trial |
|---|---|---|---:|
| Before intrinsic linked-child loop | .034094 / .034809 / .034094 | .065088 / .055790 / .061989 | 162,876 |
| After intrinsic linked-child loop | .034094 / .034094 / .033855 | .063896 / .052929 / .055075 | 161,740 |

The allocation saving is 1,136 bytes/frame (0.7%). The full 32,768-byte gate
remains **unmet**. Evidence:
`/private/tmp/p3-ui-intrinsic-before-{1,2,3}.csv`,
`/private/tmp/p3-ui-intrinsic-after-{1,2,3}.csv`,
`/private/tmp/p3-ui-intrinsic-check.log` and
`/private/tmp/p3-ui-children-inline-{before,after}-{1,2,3}.csv`.

For boxes with default hit bounds, `paint_all` intersected the identical screen
rectangle and clip twice. The visibility test now reuses its already-computed
clipped-hit extent in that case; custom hit bounds retain the original separate
screen intersection. Existing 1x/2x UI input/layout checks exit zero. Three
alternating exclusive full-editor trials, all six commands exit zero:

| Full static editor, 100k circles | Median trials (ms) | p95 trials (ms) | Bytes/frame in every trial |
|---|---|---|---:|
| Before clipped rectangle reuse | .034094 / .034094 / .034094 | .066996 / .067234 / .063896 | 161,740 |
| After clipped rectangle reuse | .034094 / .034094 / .034094 | .061989 / .055075 / .066042 | 161,308 |

The allocation saving is 432 bytes/frame. No new storage or skipped
painting/input work is introduced. The full 32,768-byte gate remains **unmet**.
Evidence: `/private/tmp/p3-ui-paint-clip-before-{1,2,3}.csv`,
`/private/tmp/p3-ui-paint-clip-after-{1,2,3}.csv` and
`/private/tmp/p3-ui-paint-clip-check.log`.

The next text hot-path change checks the atlas font identity/generation once per
nonempty text run instead of per glyph, in the three existing internal runs
(width, painting and caret placement). Their callbacks contain only internal
glyph, byte-packing and arithmetic work; they do not call user code or mutate
font style. `Font.Private.glyph` retains its runtime domain/lifetime/density
checks on every raster miss. Font hinting changes are still observed by the
next run, and empty width/caret runs do not register an atlas font id.
The existing UTF-8, caret, IME, layout and 1x/2x UI interaction regressions exit
zero. No public API, cache or new storage is added. Native pixel parity remains
unavailable. Three alternating exclusive full-editor trials, all commands zero:

| Full static editor, 100k circles | Median trials (ms) | p95 trials (ms) | Bytes/frame in every trial |
|---|---|---|---:|
| Before per-run font id lookup | .034094 / .033855 / .034094 | .056028 / .066996 / .068903 | 161,308 |
| After per-run font id lookup | .033855 / .032902 / .033140 | .056982 / .064850 / .055075 | 155,620 |

The allocation saving is 5,688 bytes/frame (3.5%). The full 32,768-byte gate
remains **unmet**. Evidence: `/private/tmp/p3-ui-font-id-before-{1,2,3}.csv`,
`/private/tmp/p3-ui-font-id-after-{1,2,3}.csv` and
`/private/tmp/p3-ui-font-id-check.log`.

## P5 native calibration (2026-10-08)

Apple M1 (Metal 4, 4K display at 2x), macOS 27.0, OCaml 5.3.0, Dune dev
profile, one domain unless stated. This process sees the system default Metal
device, so the native rows the earlier sandboxed sessions could not produce
are measured here. Commands: `_build/default/tools/bench_gpu.exe` and
`_build/default/tools/bench_kernel.exe --gpu`, each run alone after a build.

`bench_gpu` now separates float64→float32 packing from the buffer write and
salts each of its ten compile sources with a trailing comment, so the compile
median is a cold Metal source compile rather than a system shader-cache hit
(the unsalted median was 0.064 ms).

| `bench_gpu` row | compile ms | pack ms | write ms | dispatch ms | gpu ms | readback ms | total ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| noise_display 1,024 | 8.223 | 0.013 | 0.001 | 0.155 | 0.006 | 0 | 0.169 |
| noise_display 65,536 | 8.223 | 0.875 | 0.028 | 0.264 | 0.025 | 0 | 1.167 |
| noise_display 1,000,000 | 8.223 | 13.172 | 0.750 | 1.221 | 0.669 | 0 | 15.131 |
| noise_readback 1,000,000 | 8.223 | 13.142 | 0.776 | 1.230 | 0.682 | 16.788 | 31.923 |

Decisions from these rows (P5 Steps 3 and 4): the cold compile median is
under 20 ms, so kernels keep compiling synchronously at preparation time and
no asynchronous library binding is added; the buffer write is 5% of the
1M display total, under the 20% threshold, so the zero-copy `map_buffer`
feature is not added. Packing dominates upload and is OCaml conversion work,
not a copy a mapped view would remove.

`Flow_gpu.Run.dispatch` packed each input float through a per-element call
that boxed the float and its int32 bits. One loop body keeps both unboxed;
readback unpacks the same way. `bench_kernel --gpu`, same machine, before
and after, emitted noise map (two vec3 inputs):

| Emitted GPU noise | Before total ms | After total ms | Before bytes/frame | After bytes/frame |
|---|---:|---:|---:|---:|
| display 1,024 | 0.460 | 0.438 | 118,128 | 19,824 |
| display 65,536 | 2.556 | 1.749 | 6,311,376 | 19,920 |
| display 1,000,000 | 32.261 | 20.215 | 96,019,920 | 19,920 |
| readback 1,000,000 | 53.479 | 28.135 | 228,020,120 | 36,020,064 |

Per-frame allocation no longer scales with the element count on the display
route (Step 4 gate); the readback route allocates the returned float array.
Maximum absolute readback error against the CPU kernel stays 1.9e-6.
Full editor frames at 800×600, ten warm-up and 200 timed updates:

| Editor, noise-driven circles | CPU median ms | GPU median ms | CPU bytes/frame | GPU bytes/frame | CPU upload bytes/frame |
|---|---:|---:|---:|---:|---:|
| 10,000 | 10.124 | 1.480 | 11,956,254 | 283,370 | 880,000 |
| 1,000,000 | 903.351 | 28.568 | 1,163,793,792 | 283,311 | 88,000,000 |

`Flow_ir.Cost` now carries the measured rows: `Gpu` is affine through the
1,024 and 1M display totals (0.438 ms fixed, 19.8 ns/element), `Gpu_readback`
through the readback columns (10 µs, 7.9 ns/element), `Gpu_compile` 8.2 ms.
`Cost.display_sink` is the per-element cost each route adds beyond the
producer, from the editor rows: 886 ns for CPU instance building and upload,
7.6 ns for the resident GPU circle conversion. `Workspace_gpu` installs the
measured backend in production: a display sink takes the GPU when producer
plus sink is cheaper than the CPU kernel plus its sink, which on this device
holds from the 1,024-element floor upward; `(exact x)` readback compares
against the readback row and stays on the CPU kernel here (28 ms against
16.5 ms at 1M). Exports, references and fixed-step runs are unchanged.

## P4 two-chain fan-out: per-node evidence (2026-10-08)

Same machine, idle, `bench_workspace_lower.exe --branches 7 {off,learned}`
and `--loops 7 learned`, then `RAYS_BRANCH_NODE_TIMES=1 --branches 3 off`
for the last cook's per-node durations.

| Workload | Placement | Domains | Median ms |
|---|---|---:|---:|
| Two chains, 2M points | off | 1 | 154.588 |
| Two chains, 2M points | off | 8 | 64.497 |
| Two chains, 2M points | learned | 1 | 162.119 |
| Two chains, 2M points | learned | 8 | 57.936 (repeat 64.061) |
| 64 pieces, 3.2M points | learned | 1 | 1740.515 |
| 64 pieces, 3.2M points | learned | 8 | 266.832 |

| Node (two chains) | 1 domain ms | 8 domains ms |
|---|---:|---:|
| grid (×2) | 19.4 / 19.3 | 7.8 / 9.0 |
| noise_displace (×4) | 14.0 / 13.9 / 14.2 / 13.9 | 4.5 / 3.9 / 4.1 / 4.2 |
| merge 2M points | 58.8 | 40.0 |

At eight domains the serial `merge` of the two million points takes 40 of
the 73 ms cook; each chain's own nodes take 16–17 ms. Fanning the two
chains out can at best hide one chain, 56 ms, which is the measured 57.9 ms.
The loop zone stays 3.7× faster than Step 0's eight-domain row (its gate); the chain gate of 1.5× against
Step 0's 75.943 ms (≤ 50.6 ms) is **not reachable by fan-out** on this
fixture: it needs a parallel or cheaper 2M-point merge in `rdk`, which is
outside P4 Step 3. Hashes are unchanged (`67c129ec…`, `8ef295fb…`). A trial
that replaced the merge's plane copies with one allocation and chunked
parallel blits left the eight-domain merge at 45 ms (40 ms before, within
noise) and was reverted: the merge's cost is not in copying its planes.

## P3 allocation gate reading (2026-10-08)

`P3.md` Step 2 states the gate as "the static 100,000-shape row allocates
under 32,768 bytes/frame like the particle static case
(test_drawing.ml:110-124)", and that reference is the delta bound between the
4-point and 10,000-point static canvases (201,007 bytes/frame absolute,
`large <= small + 32768`). The retained 100,000-circle lowering allocates
1,393 bytes/frame and the assertion is in `test_drawing`. The full static
editor update (155,620 bytes/frame after the per-run font id lookup) is the
whole PXUI editor frame and is recorded as information, not as that gate.

## PXUI parity goldens at 2x (2026-10-08)

This display is 2x, so `kit_zones` and `kit_table` are captured at 2x like
the panel and overlay goldens; each check compares only at its golden
density and a refresh never renames a capture over another density. The panel
and overlay goldens are refreshed for the search prefix and return hint that
dev added after kit rev 3. `@lib/pxui/test_ui_parity` prints four exact rows.

## Native suite on the Apple M1 (2026-10-08)

`dune build @runtest-native` on this machine, after the calibration above:
the shape batch rim gate passes with differing pixels at most 1.414 px
(one pixel per axis) from the reference 32-gon; the emitted noise kernel
records 8.82e-7 (1,024) and 9.89e-5 (65,536) maximum absolute error against
the CPU tier; the recoloured float32 triangle matches its f64 oracle within
one channel (this fixture's shading does not vary with vertex colours, so the
earlier "pixels must change" check was replaced by the oracle); the six-mode
port exports are byte-identical once the native export counts frames from one
like `Workspace.export`. The port-versus-OCaml oracle
records its tolerance from these runs: the SDF rim anti-aliases a true circle
while the reference 32-gon truncates vertices before the drawing's scale, so a
changed pixel may lie within two pixels of an edge in both images (basic frame 0:
348 changed, 5% coverage at 307,139; generative, scale 2: 53,042 changed; a rim
clipped by the canvas has its edge off-canvas), and the SDF stroke notches where
two segments meet (drawing frames 2 and 3: two off-edge pixels at 120,159,
channel difference 52, partial coverage); a moved primitive still differs by a
whole colour far from any edge. The transformed shape comparison allows three pixels (vertex truncation
under the 1.7 scale plus one anti-aliased pixel; the stroked circle reaches 48,42). One check stays red and is not relaxed:
`runtime_native_qualification` reports the same basic hash drift on `dev`
before this work (pre-existing).

## Merge phases and runtime qualification at 2x (2026-10-08)

Temporary timers inside `Mesh_merge.merge_plain` on the two-chain fixture
(one domain, second cook): topology and position copy 55.6 ms, attribute
concatenation 7.2 ms, `of_owned`, groups and `Geometry.create` under
0.1 ms. The copy phase is the three position blits plus the vertex and
primitive index rewrites; it is what a faster merge has to attack.

`runtime_native_qualification` froze its captures for a 1x display: a
4-point window is 4 pixels there and 8 on this 2x display, so its 8-pixel
checkpoints matched the old "resized" constant exactly and the 16-pixel
resize had no record. The frozen hashes are now keyed by drawable extent,
with the 2x captures recorded for all four scenarios (no rendering drift).
The repeated-teardown footprint check still fails here: floors 64,752 and
74,720 KiB over the two 24-lifecycle windows, 9,968 KiB growth against the
4,096 KiB bound (about 415 KiB per lifecycle). It failed on `dev` before this
work; whether it is lazily returned GPU memory at 2x or a leak is open.

## Runtime teardown footprint: SDL window baseline (2026-10-08)

The repeated-teardown plateau failure is not a Rays leak. Probes in the same
qualification executable, 120 lifecycles each, physical footprint floors per
24-lifecycle window on this macOS 27 / SDL3 build:

| Lifecycle | Growth per 24 lifecycles | Per lifecycle |
|---|---:|---:|
| Rays `Runtime.create`/`destroy` (2x2 hidden) | 9,968 KiB | ~415 KiB |
| SDL init video, window + Metal view, quit video | 9,344 KiB | ~390 KiB |
| SDL window + Metal view, video kept initialized | 7,000 KiB | ~290 KiB |
| SDL window only, no Metal view | 6,500 KiB | ~270 KiB |
| SDL window only, with an event pump after destroy | 9,300 KiB | ~390 KiB |

The growth is linear over 240 lifecycles and belongs to SDL3's own window
create/destroy on this system. The check now measures that baseline in the
same process (72 lifecycles of SDL window plus Metal view, video cycled like
the runtime) and fails only when Rays adds more than 4,096 KiB beyond it.
Measured: runtime growth 10,016 KiB, baseline 9,552 KiB, Rays' share
464 KiB over 24 lifecycles (about 19 KiB per lifecycle).
`@lib/runtime/native_qualification/qualification` passes on this machine.

A second merge trial rewrote the vertex and primitive index loops as one
closure per chunk with a tight inner loop. With the context grain the SOP
passes it was slower at both domain counts (one-domain merge 570 ms,
eight-domain 51 ms against 59 and 40 ms) and was reverted; the two-chain
gate stays where the per-node table puts it.

## F2.1 field kernel — unchanged dense baseline (2026-10-08)

The extractor and its scheduling are unchanged. `bench_rdk_iso` now records
individual trials, program-wide `Gc.stat` allocation outside the timed interval,
and a hash of all authored position/normal/topology planes. The executable is
preserved at `/private/tmp/f-iso-before.exe`. Each process performs one excluded
warm-up and seven timed extractions; builds, tests and other measurements were
finished before these sequential runs. Profile: Dune dev, OCaml 5.3.0.
Hardware: arm64 macOS, known M1 workspace; hardware identification unavailable
in this session. Parsing/checking and hashing are outside the wall interval.

```sh
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-before.exe --sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-before.exe --sphere
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-before.exe --raw
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-before.exe --raw
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 /private/tmp/f-iso-before.exe --asymmetric
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-iso-before.exe --asymmetric
```

Raw trials are `specification/performance/f-field-{dense,gyroid,asymmetric}-before-{1,8}.csv`.
Sphere: 64 cells per axis, bounds `[-2,2]`, radius 1, 274,625 samples.
Gyroid preserves the prior scale 1.25, bounds `[-3,3]`, now at 64 cells.
Asymmetric: `(129,256,2)` cells, bounds `[-2,-1.5,-1]`/`[3,2,1.7]`, radius
0.8 centred at `[0.2,-0.3,0.1]`, 100,230 samples. All use smooth normals.

| Fixture | Domains | Median ms | Allocated bytes, all domains | Points | Triangles |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sphere | 1 | 27.842 | 95,195,368 | 85,680 | 28,560 |
| Sphere | 8 | 30.690 | 95,195,600 | 85,680 | 28,560 |
| Gyroid | 1 | 48.816 | 164,457,024 | 406,872 | 135,624 |
| Gyroid | 8 | 53.258 | 164,457,256 | 406,872 | 135,624 |
| Asymmetric | 1 | 13.574 | 64,262,824 | 167,352 | 55,784 |
| Asymmetric | 8 | 15.438 | 64,263,056 | 167,352 | 55,784 |

Every repetition and both domain counts have the same complete hash per fixture:
sphere `2d4641814f8cf4ce991726eb3af5c030`, gyroid
`0bc0e77f0591fa47988639b877f4c600`, asymmetric
`4b19f871788ea3bd06f717eb75e68faf`.

Astra's baseline review: “The baseline is usable: seven stable sphere trials,
identical full hashes, and matching allocations across domains.” The sampled
path alone is unlikely to reach the 10 ms whole-cook gate while its per-plane
marcher stays sequential. After the first planned after run, Astra recommends
profiling the per-cell closures/output reference in `fill_cell`, including
cells emitting no triangles. This is a risk assessment, not a gate verdict.
No field SOP existed for an end-to-end before row. The whole-cook after
measurements, verified reference-hardware gate and final
Astra verdict remain open; no speedup is established here.

## F2.1 field kernel — dense scheduling comparison (2026-10-08)

The sampled evaluator now shares the marcher, and the default plane/slab grain
is 16,384 with a two-chunk sequential cutoff. These after trials still use
the dense callback extractor; they measure scheduling regression, excluding
grid construction and kernel execution. The profile, hardware qualification,
warm-up, seven repetitions, complete hashes and aggregate GC protocol are the
same as the preceding baseline. Run its six commands with
`_build/default/tools/bench_rdk_iso.exe` in place of the preserved executable.
Raw files: `specification/performance/f-field-{dense,gyroid,asymmetric}-after-{1,8}.csv`.

| Fixture | Domains | Before median ms | After median ms | After allocated bytes, all domains |
| --- | ---: | ---: | ---: | ---: |
| Sphere | 1 | 27.842 | 27.863 | 95,195,360 |
| Sphere | 8 | 30.690 | 30.776 | 95,195,592 |
| Gyroid | 1 | 48.816 | 48.983 | 164,457,016 |
| Gyroid | 8 | 53.258 | 53.230 | 164,457,248 |
| Asymmetric | 1 | 13.574 | 13.640 | 64,263,152 |
| Asymmetric | 8 | 15.438 | 13.121 | 64,311,320 |

Every before/after/domain/trial complete hash matches. Astra's review finds
no meaningful improvement or regression for the sequential sphere/gyroid
planes (under 0.4% median changes). The asymmetric eight-domain median improves
15.0%, with after trials spanning 11.60–17.15 ms and about 48 KB additional
scheduler allocation; this does not establish stable latency. Astra approves
keeping the grain and cutoff while proceeding with SOP/grid plumbing. This
is not the whole-cook benchmark and establishes no F2.1 gate verdict.

## F2.1 field kernel — first whole-cook measurements (2026-10-08)

The new single-declaration `sop/iso_surface` invokes the exact packed field
through the neutral bulk Kernel payload. These timings include packed XYZ
grid construction, function preparation/evaluation, sample validation, shared
marching and geometry construction in `Session.cook`. Check/eval/lower,
session creation, `Gc.stat`, hashing and session teardown are outside the
wall interval. Each trial has a fresh zero-capacity session; one excluded
warm-up precedes a full major collection and seven sequential trials per
process. Profile/machine qualification are as above. No build/test/other
benchmark was running during either process.

```sh
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 _build/default/tools/bench_workspace_lower.exe --fields
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 _build/default/tools/bench_workspace_lower.exe --fields
```

| Fixture | Domains | Repetitions | Median whole-cook ms | Median allocated bytes, all domains | Median promoted bytes | Median major bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 64-cell sphere, 274,625 samples | 1 | 7 | 31.998 | 110,103,944 | 21,832 | 16,041,560 |
| 64-cell sphere, 274,625 samples | 8 | 7 | 30.005 | 110,118,208 | 23,824 | 16,043,552 |

Raw trials: `specification/performance/f-field-cook-after-{1,8}.csv`.
All trials/domains return 85,680 points/vertices and 28,560 triangles with
authored-payload hash `8a9c2d382ab7564328783e84a132cef1`. This uses the existing
workspace `cook_hash` serialization (including all attribute/group kinds),
which differs from the earlier extractor benchmark's hash serialization.
Independent tests compare complete geometry bytes to the dense custom sphere,
and all 274,625 compiled samples to the interpreter and independently computed
norms at two times and both domain counts. The eight-domain measurement exceeds
10 ms. Raw results have been sent to Astra for its gate verdict and next
diagnostic protocol. Astra's verdict: “not met, try sampled-marcher phase
profiling.” All seven eight-domain trials exceed 10 ms; reference-M1
qualification is also unavailable. The next measurements isolate the sampled
marcher and, in a temporary attribution build, the slab-wide `fill_cell`
traversal. No marching optimization was approved at that review.

## F2.1 field kernel — sampled marcher attribution (2026-10-08)

Same qualified hardware description/dev profile/OCaml 5.3.0, seven isolated
trials after one excluded warm-up. Scalar sphere samples are constructed
before timing; the wall interval includes only sampled extraction and geometry
construction. The unchanged complete dense sphere hash is required in every
row, and is `2d4641814f8cf4ce991726eb3af5c030` in all trials/domains.

```sh
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sampled-sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sampled-sphere
```

| Domains | Samples | Median sampled-extract ms | Allocated bytes, all domains |
| --- | ---: | ---: | ---: |
| 1 | 274,625 | 22.114 | 86,394,912 |
| 8 | 274,625 | 24.870 | 86,395,144 |

Raw: `specification/performance/f-field-marcher-{1,8}.csv`.
The executables are preserved as `/private/tmp/f-iso-sampled-before.exe`
and, for attribution, `/private/tmp/f-iso-fill-cell-profile.exe`.
The temporary instrumentation patch is
`specification/performance/f-field-emission-instrumentation.patch`: it times
the entire `fill_cell` traversal once per slab and reads coarse GC counters
outside the cell loop, with no forced phase collections. Empty cells are
counted outside that traversal. Its temporary Unix dependency and all counters
are removed from the shipping source (restored byte-for-byte).

```sh
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-fill-cell-profile.exe --sampled-sphere > specification/performance/f-field-emission-extract-1.csv 2> specification/performance/f-field-emission-phase-1.csv
```

Phase CSV columns are phase, accumulated seconds, allocated bytes, empty cells,
total cells; its first row is the excluded warm-up. Across seven timed trials,
median instrumented total extraction is 22.751 ms and 86,420,432 allocated
bytes; slab-wide emission totals 8.872 ms and 80,092,656 bytes. Every trial
has 257,384 empty cells of 262,144, and the complete hash still matches.
These counters attribute time/allocation; they are not shipping performance
evidence, and independently collected medians do not establish exact kernel
cost by subtraction. The uninstrumented marcher and whole-cook rows remain
the performance evidence.

Astra approves one next change: guard `fill_cell` with the already-computed
`counts.(cell) <> 0` before constructing any emission closures. Empty cells
are 98.2% of this lattice, and emission contributes about 92.7% of measured
allocation. Preserve every triangle/normal/prefix-sum expression; first add an
independent ordered plane golden with empty/crossing/empty slabs. Then compare
saved-before/rebuilt-after sampled and whole-cook trials at both domain counts,
plus dense sphere/gyroid/asymmetric regression trials. This design approval
is not a performance or gate verdict.


## F2.1 field kernel — skip empty emission cells (2026-10-08)

The guard uses existing slab counts before constructing any emission closures.
Counting, sampling, gradients, prefix sums, chunking, arithmetic and output
ordering are unchanged. The independent ordered plane golden now checks
empty/crossing/empty slabs against the fixed single-cell result; dense/sampled
sphere/asymmetric smooth/flat parity at three grains and domains 1/8 passes.
The focused typecheck, field, graph and API checks pass.

Same qualified hardware description/dev profile/OCaml 5.3.0, one excluded
warm-up and seven isolated trials per process, zero-capacity whole-cook sessions.
Saved before executables: `/private/tmp/f-iso-empty-before.exe` and
`/private/tmp/f-workspace-empty-before.exe`. Repeat the following for
`RAYS_BENCH_DOMAINS=1`; the before commands use those saved executables in
place of the rebuilt ones:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sampled-sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 _build/default/tools/bench_workspace_lower.exe --fields
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --raw
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --asymmetric
```

| Fixture | Domains | Before median ms | After median ms | Before allocated bytes | After allocated bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sampled marcher | 1 | 23.886 | 17.721 | 86,394,912 | 22,564,192 |
| Whole cook | 1 | 33.808 | 27.603 | 110,103,328 | 46,272,608 |
| Dense sphere | 1 | 28.548 | 23.015 | 95,195,376 | 31,364,656 |
| Dense gyroid | 1 | 49.527 | 49.555 | 164,457,032 | 105,296,400 |
| Dense asymmetric | 1 | 13.667 | 12.485 | 64,263,168 | 49,654,496 |
| Sampled marcher | 8 | 26.074 | 17.529 | 86,395,144 | 22,564,424 |
| Whole cook | 8 | 31.764 | 24.551 | 110,118,168 | 46,286,896 |
| Dense sphere | 8 | 31.327 | 28.834 | 95,195,608 | 31,364,888 |
| Dense gyroid | 8 | 53.975 | 51.720 | 164,457,264 | 105,296,632 |
| Dense asymmetric | 8 | 16.248 | 12.295 | 64,311,208 | 49,703,760 |

Raw: `specification/performance/f-field-empty-{marcher,cook,dense,gyroid,asymmetric}-{before,after}-{1,8}.csv`.
Each file retains all seven wall/allocation/promoted/major/cardinality/hash
rows. Before/after/domain/trial hashes and cardinalities match. The eight-domain
after whole-cook 66.748 ms outlier and gyroid 82.683 ms outlier are retained;
these data do not establish stable latency.

Astra's verdict: “Keep the empty-cell guard. Not met, try counting-phase
attribution.” It removes 63.83 MB per sphere extraction (about 74% of sampled
allocation); the eight-domain sampled median improves 32.8% and whole-cook
median 22.7%. Denser fixtures show no material median regression. The whole
cook still exceeds 10 ms, and reference-M1 qualification remains unavailable.
Next measure both complete `count_slab` passes separately in a temporary
one-domain attribution build, preserving the guard. No counting rewrite,
count volume retention or slab parallelization is approved yet.

## F2.1 field kernel — counting-pass attribution (2026-10-08)

Same hardware caveat/dev profile/OCaml 5.3.0, one domain, one excluded warm-up
and seven isolated trials. The temporary patch
`specification/performance/f-field-count-instrumentation.patch` wraps each
complete `count_slab` call, including cancellation and scheduling, with elapsed
time and coarse GC-counter snapshots. It keeps separate initial-counting and
emission-pass recounting totals, with no callbacks or branches inside the cell
loop and no forced phase collections. The empty-cell guard is retained.
The shipping source and Dune dependencies are restored byte-for-byte afterward.

```sh
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-count-profile.exe --sampled-sphere > specification/performance/f-field-count-extract-1.csv 2> specification/performance/f-field-count-phase-1.csv
```

Phase rows are pass name, accumulated seconds, allocated bytes; the first pair
is the excluded warm-up. Initial counting takes median 3.876 ms, emission-pass
recounting 3.863 ms, both with zero measured phase allocation. Corresponding
instrumented extraction median is 17.002 ms and 22,614,696 allocated bytes.
Every row preserves 85,680 points/vertices, 28,560 triangles and the complete
sphere hash `2d4641814f8cf4ce991726eb3af5c030`. These are attribution figures,
not shipping timings or gate evidence. Restored typecheck, field/probe tests
(including fold-state snapshot isolation) and API checks pass.

Astra approves one next optimization: construct a fixed 256-entry cube-count
table once from the existing tetrahedron table and the same six corner tuples;
combine the unchanged eight classifications into one mask and perform one
lookup. Keep both passes and all other phases unchanged. The independent
regression must exhaust 256 cube masks with explicit corner-to-flat mapping,
plus equality-at-iso values; expected counts come from the number of positive
corners per tetrahedron, not the production table. Save uninstrumented before
executables, collect the same seven-trial one/eight-domain fixture matrix and
send raw rows to Astra. This design approval is not a gate verdict; the
whole-cook median is still above 10 ms and reference-hardware qualification
is still unavailable.

## F2.1 field kernel — cube-count lookup (2026-10-08)

The fixed 256-entry table is derived once from the same sixteen tetrahedron
counts and six ordered corner tuples. Every cell retains its eight `>= iso`
classifications and makes one lookup instead of six. Both counting passes,
streaming planes, sampling, gradients, prefix sums, emission and scheduling
are unchanged. The independent regression exhausts all 256 masks with explicit
corner-to-flat ordering, both positive and exactly-on-iso inside values, and
triangle counts derived from positive-corner cardinality rather than the
production table. The specific empty-surface error, independent ordered plane
goldens and complete smooth/flat normal/topology byte parity remain checked.
`@check @lib/rdk/test_gen @lib/flow_sop/runtest` and benchmark builds pass.

Machine: arm64 macOS, OCaml 5.3.0, dev profile; known M1 workspace but hardware
identification and reference-M1 qualification unavailable in this session.
Seven isolated trials per process, one excluded warm-up, grain 16,384, unchanged
GC policy and zero-capacity whole-cook sessions. Before executables are
`/private/tmp/f-iso-count-before.exe` and `/private/tmp/f-workspace-count-before.exe`.
Repeat at domains 1 and 8; before commands use those saved executables:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sampled-sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 _build/default/tools/bench_workspace_lower.exe --fields
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --raw
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --asymmetric
```

| Fixture | Domains | Before median ms | After median ms | Before allocated bytes | After allocated bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sampled marcher | 1 | 16.839 | 14.586 | 22564192 | 22563024 |
| Sampled marcher | 8 | 17.555 | 15.543 | 22564424 | 22563256 |
| Whole cook | 1 | 26.720 | 24.434 | 46272608 | 46271440 |
| Whole cook | 8 | 23.019 | 20.167 | 46287144 | 46285544 |
| Dense sphere | 1 | 22.598 | 20.464 | 31364656 | 31363488 |
| Dense sphere | 8 | 23.645 | 21.328 | 31364888 | 31363720 |
| Dense gyroid | 1 | 44.154 | 41.488 | 105296400 | 105295232 |
| Dense gyroid | 8 | 46.925 | 44.541 | 105296632 | 105295464 |
| Dense asymmetric | 1 | 12.370 | 11.904 | 49654496 | 49654320 |
| Dense asymmetric | 8 | 13.101 | 12.641 | 49702064 | 49701856 |

Raw: `specification/performance/f-field-count-{marcher,cook,dense,gyroid,asymmetric}-{before,after}-{1,8}.csv`.
All seven trials per file retain promoted/major allocations, cardinalities and
complete geometry hashes; before/after/domain/trial fingerprints match.
Astra's verdict: “Keep the cube-count lookup. Not met, try gradient-phase
attribution.” Eight-domain sampled extraction improves 11.5% and whole cook
12.4%; every fixture median improves in this matrix. The allocation difference
is incidental. Whole cook remains above 10 ms, and reference-hardware
qualification is still unavailable.

## F2.1 field kernel — gradient-phase attribution (2026-10-08)

Same hardware caveat/dev profile/OCaml 5.3.0, one domain, grain 16,384, seven
isolated trials and one excluded warm-up. The temporary patch
`specification/performance/f-field-gradient-instrumentation.patch` wraps complete
XY and Z gradient calls with elapsed time and coarse `Gc.quick_stat` snapshots,
outside element loops and including existing scheduling. Arithmetic, buffer
rotation and call order stay unchanged. The source/Dune dependencies are
restored byte-for-byte; the instrumented executable is archived separately.

```sh
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-gradient-before.exe --sampled-sphere > specification/performance/f-field-gradient-before-1.csv
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-gradient-profile.exe --sampled-sphere > specification/performance/f-field-gradient-extract-1.csv 2> specification/performance/f-field-gradient-phase-1.csv
```

The first pair of phase rows is the excluded warm-up. Median XY time is
1.444 ms, Z 1.090 ms, both with zero measured phase allocation. Instrumented
extraction median is 14.522 ms and 22,622,664 allocated bytes; the isolated
uninstrumented baseline is 14.329 ms and 22,563,024 bytes. Every row retains
the complete sphere hash, 85,680 points/vertices and 28,560 triangles.
These figures attribute phases; they are not a whole-cook gate result. No
gradient optimization has been implemented. Astra recommends leaving gradient
evaluation unchanged: eliminating both phases would still not close the
whole-cook gap. Its verdict remains “not met, try current emission and
residual-phase attribution.” The next approved diagnostic uses the current
guarded/table-based extractor, measuring coarse emission, sampling/finite
validation, prefix sums and output allocation/final geometry construction,
with disjoint intervals. No production algorithm change is approved.

## F2.1 field kernel — current emission and residual attribution (2026-10-08)

Confirmed `Macmini9,1`, Apple M1, eight logical CPUs (`sysctl -n hw.model
machdep.cpu.brand_string hw.logicalcpu`), OCaml 5.3.0, Dune dev profile,
grain 16,384. Seven isolated one-domain sampled 64³ sphere trials and one
excluded warm-up. No builds, tests or other benchmarks ran concurrently.
The temporary coarse phase patch is
`specification/performance/f-field-current-instrumentation.patch`; phases are
disjoint and outside element loops. Source and Dune dependencies were restored
byte-for-byte, then `@check @lib/rdk/test_gen tools/bench_rdk_iso.exe` passed.

```sh
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-current-before.exe --sampled-sphere > specification/performance/f-field-current-before-1.csv
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-iso-current-profile.exe --sampled-sphere > specification/performance/f-field-current-extract-1.csv 2> specification/performance/f-field-current-phase-1.csv
```

| Interval | Median ms | Median allocated bytes |
|---|---:|---:|
| Uninstrumented complete extraction | 14.329 | 22,563,024 |
| Instrumented complete extraction | 15.210 | 22,836,624 |
| Sampling and finite validation | 0.600 | 0 |
| Initial counting | 2.626 | 0 |
| Emission-pass recounting | 2.627 | 0 |
| XY gradients | 1.449 | 0 |
| Z gradients | 1.089 | 0 |
| Prefix sums | 1.884 | 0 |
| Output plane allocation | 0.096 | 4,213,080 |
| Cell emission | 3.612 | 17,180,656 |
| Packed wrappers | 0.001 | 0 |
| Final geometry construction | 0.392 | 686,376 |

The first ten phase rows are warm-up and excluded. Every complete result
retains hash `2d4641814f8cf4ce991726eb3af5c030`, 85,680 points/vertices and
28,560 triangles. Phase medians do not sum to a whole-run median; helper
closures, GC snapshots and report writes also add instrumentation overhead.
These rows establish attribution, not the eight-domain whole-cook gate.
Astra's verdict is “not met, try deterministic slab chunks for sampled
extraction.” Its next design partitions consecutive sampled slabs by at least
16,384 cells per chunk, retains ordered global prefixes and disjoint output
ranges, and owns rotating planes per active worker. Global halo samples must
preserve central Z derivatives at internal chunk seams. Callback extractors
retain their existing scheduling. This algorithm change is approved for a
measured trial, but is not implemented in this checkpoint.

## F2.1 field kernel — deterministic sampled slab chunks (2026-10-09)

Confirmed Macmini9,1, Apple M1, eight logical CPUs, OCaml 5.3.0, Dune dev
profile, grain 16,384. Each file has seven isolated trials after one excluded
warm-up; no builds, tests or other benchmarks ran concurrently. Whole cooks
use zero-capacity sessions and include grid construction, preparation, field
execution, validation, extraction and geometry materialization. Saved before
executables contain the extractor from `46984986`:
`/private/tmp/f-iso-slabs-before.exe` and
`/private/tmp/f-workspace-slabs-before.exe`.

Sampled extraction now partitions consecutive Z slabs into deterministic
chunks containing at least one grain of cells. Every chunk owns counting and
rotating emission scratch; global slab prefixes determine disjoint output
ranges and unchanged output order. Global previous/next halo planes retain
the original central derivatives at chunk seams. The partition is identical
at one/eight domains. Callback extractors retain their existing scheduling.

Repeat the following at domains 1 and 8, using saved executables for before
and rebuilt executables for after; redirect each command to its matching raw
file. GC policy is unchanged.

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sampled-sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 _build/default/tools/bench_workspace_lower.exe --fields
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sampled-gyroid
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --sphere
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 _build/default/tools/bench_rdk_iso.exe --raw
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 _build/default/tools/bench_rdk_iso.exe --asymmetric
```

| Fixture | Domains | Before median ms | After median ms | Before allocated bytes | After allocated bytes |
|---|---:|---:|---:|---:|---:|
| Sampled sphere | 1 | 16.000 | 16.388 | 22563024 | 32194008 |
| Sampled sphere | 8 | 16.889 | 6.873 | 22563256 | 32218192 |
| Whole cook | 1 | 26.424 | 27.030 | 46271440 | 55902424 |
| Whole cook | 8 | 20.954 | 12.937 | 46285640 | 55938640 |
| Sampled gyroid | 1 | 31.154 | 31.020 | 105282768 | 114913752 |
| Sampled gyroid | 8 | 34.515 | 21.538 | 105283000 | 114938488 |
| Dense sphere | 1 | 22.188 | 20.336 | 31363488 | 31393656 |
| Dense sphere | 8 | 23.420 | 21.517 | 31363720 | 31393888 |
| Dense gyroid | 1 | 45.843 | 41.870 | 105295232 | 105325400 |
| Dense gyroid | 8 | 46.943 | 44.757 | 105295464 | 105325632 |
| Dense asymmetric | 1 | 13.123 | 11.876 | 49654320 | 49918888 |
| Dense asymmetric | 8 | 12.972 | 14.452 | 49701248 | 49968224 |

Raw: `specification/performance/f-field-slabs-{marcher,cook,sampled-gyroid,dense,gyroid,asymmetric}-{before,after}-{1,8}.csv`.
All trial/domain/before/after complete hashes and cardinalities match within
each fixture: sampled/dense sphere `2d4641814f8cf4ce991726eb3af5c030`, whole
cook `8a9c2d382ab7564328783e84a132cef1`, sampled/dense gyroid
`0bc0e77f0591fa47988639b877f4c600`, dense asymmetric
`4b19f871788ea3bd06f717eb75e68faf`. The nonlinear seam regression compares
complete geometry, smooth/flat normals and ordering against the unchanged
dense oracle at grains 35, 70, 315 and max_int, one/eight domains; it also
checks nonfinite samples, cancellation and unchanged input storage.

Astra's verdict: “not met, try explicit floating-point parity correction
before further optimization.” Keep slab scheduling: sampled extraction
improves 59.3% and whole cook 38.3% at eight domains. Whole-cook allocation
increases about 9.65 MB and one-domain time increases 2.3%; those costs are
recorded rather than hidden. The dense asymmetric eight-domain control
regresses 11.4% in this matrix. The unchanged strict <10 ms whole-cook gate
remains unmet.

The initial independently sampled asymmetric fixture has a different field:
its lattice arithmetic compiled to separate multiply/add, while RDK compiled
to ARM64 fused multiply-add. Its four original
`f-field-slabs-sampled-asymmetric-{before,after}-{1,8}.csv` files are preserved
as diagnostic evidence, with hash `e94785096d7eaa35e4adbd8b784b9c0b` and
167,352 points/vertices, 55,784 triangles. Their before/after/domain identity
is valid, but they do not establish parity with the dense asymmetric field.
Corrected comparable rows are recorded separately below.

## F2.1 field kernel — explicit rounding parity (2026-10-09)

Same confirmed M1/dev-profile/OCaml 5.3.0/grain 16,384 protocol, seven isolated
trials after one excluded warm-up at each domain count. The original
asymmetric sampled rows remain unchanged. The corrected benchmark explicitly
uses fused multiply-add for lattice coordinates and asserts complete
sampled/dense geometry hash equality during untimed warm-up. Its before
executable was rebuilt with the extractor from `46984986` and the corrected
benchmark; production source was restored byte-for-byte after that build.

The separate production defect is corrected in scalar `length`: opaque
squared components prevent compiler contraction, matching the existing packed
Mul/Add/Sqrt sequence. A new 100,230-sample asymmetric off-centre comparison
against independent Lisp multiply/add/sqrt fails before at sample 0
(`1.9367864366808016` versus `1.9367864366808021`), then passes every float64
bit at t=0/0.25 in reference and packed execution, domains 1/8. Existing
overflow, underflow and untaken-branch checks stay green. SOP and RDK sampling
now spell their existing native fused-coordinate rule explicitly with
`Float.fma`; a separate integration check inspects every coordinate actually
supplied by the SOP at one/eight domains. Interpolation and emitted-position
arithmetic are unchanged. The rounding contract is documented in Flow.

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-iso-rounding-before.exe --sampled-asymmetric
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-iso-rounding-after.exe --sampled-asymmetric
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-rounding-after.exe --fields
```

Repeat at domains 1; redirect to the six corresponding raw files:
`specification/performance/f-field-rounding-sampled-asymmetric-{before,after}-{1,8}.csv`
and `specification/performance/f-field-rounding-cook-after-{1,8}.csv`.

| Fixture | Domains | Before median ms | After median ms | Before allocated bytes | After allocated bytes |
|---|---:|---:|---:|---:|---:|
| Corrected sampled asymmetric | 1 | 9.788 | 10.661 | 46446304 | 50978832 |
| Corrected sampled asymmetric | 8 | 12.850 | 8.227 | 46481904 | 50982280 |
| Current whole cook | 1 | — | 28.312 | — | 55902424 |
| Current whole cook | 8 | — | 13.569 | — | 55939960 |

Every corrected asymmetric trial has dense hash
`4b19f871788ea3bd06f717eb75e68faf`, 167,352 points/vertices and 55,784 triangles.
Whole-cook rows retain `8a9c2d382ab7564328783e84a132cef1`, 85,680 points/vertices
and 28,560 triangles. Corrected asymmetric eight-domain extraction improves
36.0%; one-domain time increases 8.9% and allocation about 4.5 MB. Current
whole-cook rows are fresh measurements, not a paired performance claim for
the rounding correction.

Astra's verdict: “not met, try same-cook SOP phase attribution.” Keep the
rounding corrections and slab scheduling. The strict uninstrumented
eight-domain whole-cook <10.000 ms gate remains unmet. Next approved diagnostic:
four disjoint intervals for grid allocation/filling, complete Kernel.prepare,
runner invocation and complete extraction including final geometry. Coarse
wall/aggregate-GC snapshots only, buffered output outside the cook, trial IDs
joining each phase to its own whole row. Seven trials plus warm-up at both
domain counts, with an isolated uninstrumented comparison; archive the patch
and restore production files byte-for-byte. Independent median subtraction
does not establish where the remaining cost lies. No further algorithm is
approved at this checkpoint.

Validation: focused `@check`, Flow, Flow IR, Flow SOP, RDK generator and
Procedural tests pass (exit 0). `_build/default/tools/check.exe --ship` passes
(exit 0), including dependency/API gates and the 37-standard-file,
two-custom-catalog, 13-fixture workspace sweep at four times and domains 1/8.
The full F5 native/pixel suite subsequently passed (exit 0) on the confirmed
M1, qualifying `8f1f4789`: all three workspace pixel aliases, GPU numerics,
shape-batch/Scene3/canvas checks, editor native checks, gallery float32 parity,
runtime native qualification and UI parity. The workspace sweep verifies
native geometry/image/texture/drawing pixels at four times and domains 1/8.
No golden, tolerance or gate was relaxed.

## F2.1 field kernel — same-cook intrusive GC attribution (2026-10-09)

Confirmed Apple M1/Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev
profile, grain 16,384. Seven isolated trials plus an excluded warm-up at
domains 1/8. Each cook uses a fresh zero-capacity session; parsing, checking
and lowering stay outside it. Temporary instrumentation wraps four disjoint
SOP intervals: packed grid allocation/filling, complete Kernel.prepare,
complete runner invocation and complete sampled extraction/geometry creation.
GC snapshots surround each interval, outside its timer. Rows are buffered and
printed at exit; warm-up has ID -1 and timed phases join to whole-cook IDs 0–6.
The source is restored byte-for-byte after profiling. Reproduction patch:
`specification/performance/f-field-sop-instrumentation.patch`.

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-sop-before.exe --fields > specification/performance/f-field-sop-before-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-sop-profile.exe --fields > specification/performance/f-field-sop-extract-8.csv 2> specification/performance/f-field-sop-phase-8.csv
```

Repeat at domains 1. No builds, tests or other benchmarks run during these
commands. Existing benchmark GC/warm-up policy is unchanged. Every whole row
retains `8a9c2d382ab7564328783e84a132cef1`, 85,680 points/vertices and 28,560
triangles; each process produces 32 phase rows, four warm-up rows excluded.

| Interval | Domains | Median ms | Median allocated bytes |
|---|---:|---:|---:|
| Uninstrumented whole cook | 1 | 27.587 | 55902424 |
| Instrumented whole cook | 1 | 40.884 | 55904888 |
| Grid | 1 | 1.569 | 6591224 |
| Prepare | 1 | 2.075 | 13201520 |
| Kernel | 1 | 6.884 | 3910088 |
| Extract | 1 | 16.250 | 32193936 |
| Uninstrumented whole cook | 8 | 11.136 | 55938336 |
| Instrumented whole cook | 8 | 50.928 | 55940856 |
| Grid | 8 | 1.447 | 6591224 |
| Prepare | 8 | 2.465 | 13201520 |
| Kernel | 8 | 2.183 | 3923352 |
| Extract | 8 | 4.773 | 32216272 |

Intrusive profiling creates substantial pauses outside phase timers. Joining
each whole row to its own four phase rows leaves 13.976–14.230 ms at one
domain and 34.403–152.314 ms at eight domains. All outliers are retained.
These instrumented totals cannot identify expensive session work or choose
the next optimization. Allocation evidence is retained separately as coarse
intrusive profiling; snapshots and reporting allocations add overhead inside
the whole cook. The valid uninstrumented eight-domain median is 11.136 ms,
still above the strict <10 ms gate. Astra's verdict: “not met, try time-only
SOP phase attribution.” Remove all in-cook GC snapshots, keep timestamps,
buffered output and trial IDs, and repeat the paired protocol. Production
algorithms remain unchanged; restored typecheck and field/lattice tests pass.

## F2.1 field kernel — time-only same-cook attribution (2026-10-09)

Same confirmed M1/dev/OCaml/grain/session/warm-up protocol. The revised
temporary patch `specification/performance/f-field-sop-time-instrumentation.patch`
keeps the four intervals and deferred rows, with no GC snapshots inside the
cook. Only the existing benchmark captures whole-cook GC counters outside its
timer. Raw timestamps remain joined by domain/trial; ID -1 is excluded.

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-sop-before.exe --fields > specification/performance/f-field-sop-time-before-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-sop-time-profile.exe --fields > specification/performance/f-field-sop-time-extract-8.csv 2> specification/performance/f-field-sop-time-phase-8.csv
```

Repeat at domains 1; seven isolated trials each, no concurrent builds/tests/
benchmarks. Every whole hash/cardinality remains exact and every phase CSV
has 32 rows including the four excluded warm-up rows.

| Interval | Domains | Median ms | Median whole-cook allocated bytes |
|---|---:|---:|---:|
| Uninstrumented whole cook | 1 | 27.619 | 55902424 |
| Instrumented whole cook | 1 | 28.467 | 55903064 |
| Grid | 1 | 1.551 | — |
| Prepare | 1 | 2.083 | — |
| Kernel | 1 | 6.990 | — |
| Extract | 1 | 17.832 | — |
| Uninstrumented whole cook | 8 | 11.755 | 55938528 |
| Instrumented whole cook | 8 | 12.085 | 55940120 |
| Grid | 8 | 1.555 | — |
| Prepare | 8 | 2.585 | — |
| Kernel | 8 | 2.235 | — |
| Extract | 8 | 5.677 | — |

Actual paired trial totals, rather than subtraction of independent medians:

| Domains | Trial | Whole ms | Sum of its four phases ms | Outside phases ms |
|---|---:|---:|---:|---:|
| 1 | 0 | 29.201984 | 29.185057 | 0.016927 |
| 1 | 1 | 29.408932 | 29.393912 | 0.015020 |
| 1 | 2 | 28.947115 | 28.934001 | 0.013114 |
| 1 | 3 | 28.467178 | 28.452873 | 0.014305 |
| 1 | 4 | 28.312922 | 28.300047 | 0.012875 |
| 1 | 5 | 28.259993 | 28.245211 | 0.014782 |
| 1 | 6 | 28.270960 | 28.256893 | 0.014067 |
| 8 | 0 | 12.673140 | 12.650013 | 0.023127 |
| 8 | 1 | 11.703968 | 11.682987 | 0.020981 |
| 8 | 2 | 12.084961 | 12.063980 | 0.020981 |
| 8 | 3 | 11.903048 | 11.883020 | 0.020028 |
| 8 | 4 | 13.472795 | 13.454199 | 0.018596 |
| 8 | 5 | 11.610031 | 11.563064 | 0.046967 |
| 8 | 6 | 16.283989 | 16.263962 | 0.020027 |

Removing snapshots removes the previous large outside-phase pauses. This is
phase attribution, not a performance change or gate success: the valid
uninstrumented eight-domain median remains 11.755 ms. Preparation and grid
construction are measurable costs alongside kernel execution and extraction.
Raw timing/whole/allocation evidence is retained without truncating outliers.
Production source is restored byte-for-byte; no instrumentation ships.

Astra's verdict: “not met, try allocation-free packed-input validation.”
Preparation's intrusive allocation evidence (13,201,520 bytes) is consistent
with 823,875 coordinate boxes at 16 bytes each (13,182,000 bytes). The approved
trial replaces only Value.validate's packed-array callback with an indexed
finite check, retaining width validation and the existing exact error path.
Add a preconstructed small/large finite Vec3 validation allocation regression
with <4 KB growth, source-byte identity and malformed/nonfinite/final-element
checks. Save the current uninstrumented benchmark; collect seven isolated
whole cooks at domains 1/8 before/after, plus the same time-only attribution
at eight domains. No bypass, cache or scheduling change is approved. The
strict gate remains uninstrumented whole-cook median <10.000 ms, subject to
exactness and Astra's final raw-number verdict.

## F2.1 field kernel — indexed packed-input validation (2026-10-09)

Only the shared packed-array branch of Flow.Value.validate changes: validate
width first, inspect each stored coordinate with an indexed finite check,
and call the original `fin "array input"` only on failure. No bridge bypass,
cache, numerical arithmetic or scheduling change. The regression constructs
all inputs before measuring: small versus 49,152-coordinate finite Vec3
validation must increase allocation by <4 KB. It fails before with 786,384
bytes and passes after. Large Float/Vec2/Vec3/Vec4 inputs retain identical
bytes; NaN and both infinities at every coordinate, including the final one,
retain exact diagnostics. Malformed width still precedes nonfinite failure.
Focused Flow/IR/SOP/Procedural checks pass after the production-source restore.

Confirmed M1/Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev profile,
grain 16,384, seven isolated trials after one excluded warm-up, fresh
zero-capacity sessions, existing GC policy. Before executables contain the
callback validator; after executables contain the indexed validator. Timed
whole cooks include grid/preparation/kernel/extraction/geometry. No builds,
tests or other benchmarks run concurrently. Repeat at domains 1 and 8:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-validate-before.exe --fields > specification/performance/f-field-validate-cook-before-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-validate-after.exe --fields > specification/performance/f-field-validate-cook-after-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-sop-time-profile.exe --fields > specification/performance/f-field-validate-time-extract-before-8.csv 2> specification/performance/f-field-validate-time-phase-before-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-validate-time-profile.exe --fields > specification/performance/f-field-validate-time-extract-after-8.csv 2> specification/performance/f-field-validate-time-phase-after-8.csv
```

The phase runs use the archived time-only patch, no in-cook GC snapshots,
deferred output and warm-up ID -1. Production SOP source is restored
byte-for-byte afterward; no instrumentation ships.

| Uninstrumented whole cook | Before median ms | After median ms | Before allocated bytes | After allocated bytes |
|---|---:|---:|---:|---:|
| One domain | 27.556 | 27.564 | 55902424 | 42720424 |
| Eight domains | 12.350 | 11.300 | 55938896 | 42756616 |

| Eight-domain time-only interval | Before median ms | After median ms |
|---|---:|---:|
| Grid | 1.585 | 1.555 |
| Preparation | 2.569 | 1.859 |
| Kernel | 2.164 | 2.224 |
| Extraction | 5.524 | 5.509 |
| Instrumented whole cook | 11.657 | 11.384 |

Instrumented whole allocations are 55,939,912→42,757,672 bytes. Preparation
time falls about 0.710 ms; numerical/scheduling work is unchanged. The
uninstrumented one-domain time is flat; the eight-domain median falls 8.5%.
One-domain allocation falls exactly 13,182,000 bytes, matching 823,875
eliminated 16-byte float boxes. Every trial retains full hash
`8a9c2d382ab7564328783e84a132cef1`, 85,680 points/vertices and 28,560 triangles;
all raw allocation/promoted/major rows and outliers remain available. Phase
timings are attribution, not gate measurements. The strict uninstrumented
eight-domain <10.000 ms gate remains unmet.

Astra's verdict: “not met, try deterministic row chunks for SOP grid filling
through the shared Parallel pool.” Keep indexed validation: measured
allocation and preparation improve with exact behavior. The next approved
trial partitions complete rows using `rows_per_chunk = 1 + (grain-1)/nx`,
keeps the plain x loop and all three FMA expressions, and schedules chunk
indices through the existing pool when samples/grain >=2. Chunk-local
cancellation state avoids sharing the old mutable stopped ref; join and check
cancellation before preparing the field. Add complete actual-coordinate/mesh
checks on the non-dyadic `(7,5,9)` lattice at grains 97, 240 and max_int,
domains 1/8, with precancellation preventing preparation. Keep all grid work
inside the timed cook. Save-before seven-trial whole cooks at domains 1/8 and
paired time-only attribution at eight domains determine retention; no cache,
dependency or public API change is approved. This grid trial is not yet
implemented at the validation checkpoint.

Validation checkpoint: restored `@check`, focused Flow/IR/SOP/Procedural
tests, `--ship` and `@lib/flow_gpu/runtest-native` all pass (exit 0) on the
confirmed M1. Shipping includes every workspace at four times/domains 1/8;
native GPU numerics retain the existing tolerances. The preceding full F5
pixel/native qualification belongs to `8f1f4789`; this checkpoint changes
only finite-input validation, with complete error/source/field-byte coverage.

## F2.1 field kernel — rejected row-chunk grid trial (2026-10-09)

Confirmed M1/Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev profile,
grain 16,384, seven isolated trials after one excluded warm-up, fresh
zero-capacity sessions and existing GC policy. The trial partitions complete
x-fast rows, computes y/z once per row, preserves the three explicit FMA
expressions, and uses the shared Parallel pool above the two-grain cutoff.
Cancellation is chunk-local and checked after joining. Complete actual
coordinate/mesh tests at domains 1/8, non-dyadic `(7,5,9)` bounds and grains
97, 240 and max_int pass, including precancellation before preparation.

No builds, tests or benchmarks overlap. Repeat whole cooks at domains 1/8:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-grid-before.exe --fields > specification/performance/f-field-grid-cook-before-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-grid-after.exe --fields > specification/performance/f-field-grid-cook-after-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-validate-time-profile.exe --fields > specification/performance/f-field-grid-time-extract-before-8.csv 2> specification/performance/f-field-grid-time-phase-before-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-grid-time-profile.exe --fields > specification/performance/f-field-grid-time-extract-after-8.csv 2> specification/performance/f-field-grid-time-phase-after-8.csv
```

| Uninstrumented whole cook | Before median ms | Trial median ms | Before allocated bytes | Trial allocated bytes |
|---|---:|---:|---:|---:|
| One domain | 27.515 | 30.298 | 42720424 | 42720576 |
| Eight domains | 11.641 | 12.343 | 42756776 | 42770048 |

| Eight-domain time-only interval | Before median ms | Trial median ms |
|---|---:|---:|
| Grid | 1.449 | 0.566 |
| Preparation | 1.851 | 1.880 |
| Kernel | 2.206 | 2.386 |
| Extraction | 5.983 | 10.919 |
| Instrumented whole cook | 11.589 | 15.767 |

Instrumented allocation medians are 42,758,160→42,771,760 bytes. All trials
retain hash `8a9c2d382ab7564328783e84a132cef1`, 85,680 points/vertices and
28,560 triangles. Full raw timing/allocation/promoted/major rows and outliers
are in `specification/performance/f-field-grid-*.csv`. The grid interval
improves, but uninstrumented whole cooking regresses 10.1% at one domain and
6.0% at eight. Slower instrumented extraction identifies an elapsed-time
increase; it does not establish its cause. No gate or tolerance changes.

Astra's verdict: “Revert the row-chunk production change; retain its
regression coverage and raw evidence.” Production SOP source is restored
byte-for-byte. The rejected algorithm is archived in
`f-field-grid-trial.patch`; its time-only instrumentation is archived in
`f-field-grid-time-instrumentation.patch`, applied after that trial patch.
No profiler or rejected scheduling change ships. Restored `@check`,
procedural SOP tests, Flow SOP tests and `--ship` pass (exit 0).

Astra next says “not met, try time-only attribution of bulk preparation into
map construction and IR compilation.” Measure the existing
`E.Private.map_function` and `Attribute_kernel.prepare` calls as children of
the coarse preparation interval, retaining full work inside timed cooking.
No GC snapshots, printing, caching or algorithm changes inside intervals.
Require one child pair per cook, warm-up ID -1 and timed IDs 0..6, child
containment in the parent, exact hashes/counts and the existing malformed/
nonfinite regressions. Run seven isolated restored uninstrumented and
instrumented trials at domains 1/8, archive `f-field-prepare-*` CSVs and
restore both sources byte-for-byte. The strict whole-cook <10 ms gate remains
unmet; the diagnostic is not a performance claim.

## F2.1 field kernel — preparation child attribution (2026-10-09)

Confirmed M1/Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev profile,
grain 16,384, seven isolated trials after one excluded warm-up, fresh
zero-capacity sessions, existing GC policy. Sequential SOP grid filling and
indexed finite validation are retained. No builds, tests, other benchmarks
or agent work run during measurement. Save the uninstrumented executable,
apply `f-field-prepare-time-instrumentation.patch`, build and save the timed
executable, restore both production sources byte-for-byte, then run both
saved executables. Repeat at domains 1/8:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-prepare-before.exe --fields > specification/performance/f-field-prepare-cook-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_F_PREPARE_PHASE_CSV=specification/performance/f-field-prepare-child-8.csv RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-prepare-profile.exe --fields > specification/performance/f-field-prepare-time-cook-8.csv 2> specification/performance/f-field-prepare-parent-8.csv
```

The temporary Function_kernel timer measures the complete existing
`E.Private.map_function` and `Attribute_kernel.prepare` calls, including
input validation and IR compilation respectively. These are children of the
existing coarse preparation interval, never added again to phase totals.
No GC snapshots, printing, caching or algorithm changes inside intervals;
all output is buffered until process exit. Each domain has 32 parent rows
and 16 child rows including warm-up -1 and trials 0..6. Exactly one child
pair is contained in every preparation parent; containment checks use exact
CSV decimal arithmetic to avoid binary float summation artifacts.

| Whole cook | One domain median ms | Eight domains median ms | One domain allocated bytes | Eight domains allocated bytes |
|---|---:|---:|---:|---:|
| Uninstrumented | 29.789 | 16.353 | 42720424 | 42757728 |
| Instrumented | 27.629 | 14.844 | 42721344 | 42757216 |

| Time-only interval | One domain median ms | Eight domains median ms |
|---|---:|---:|
| Grid | 1.610 | 1.578 |
| Preparation parent | 1.861 | 1.884 |
| Map construction child | 1.846 | 1.863 |
| IR preparation child | 0.015 | 0.021 |
| Kernel | 7.244 | 2.291 |
| Extraction | 17.110 | 7.845 |

The complete cook hash is `8a9c2d382ab7564328783e84a132cef1` in every
trial, with 85,680 points/vertices and 28,560 triangles. All allocation,
promoted/major and timing rows, including high whole-cook outliers, are
retained in `specification/performance/f-field-prepare-*.csv`. Map construction
accounts for almost all preparation time; this does not identify the cause
inside that call or explain higher whole-cook times in this batch. Phase
measurements are diagnostic evidence, not a gate result. The unchanged
uninstrumented eight-domain median <10.000 ms gate remains unmet.

The temporary two-source patch is archived; production sources are restored
byte-for-byte. Restored `@check`, Flow tests (including malformed/nonfinite
packed input), Flow SOP tests, procedural SOP tests and the benchmark build
pass (exit 0). Astra's review of these raw numbers determines the next step.

Astra's verdict: “not met, try moving the packed-validation error call outside
its sequential scan.” Source review identifies Value.validate as the map
constructor's sample-sized work. The other constructor operations traverse
the few parameters/bindings. Its native successful loop currently retains a
possible `fin` call inside the body; approve only an ascending finite while
scan followed by the original error helper outside the loop at the first
invalid element. Inspect assembly; a speedup is not assumed. Preserve
width-first checks, first-error behavior and existing allocation/error tests;
add empty arrays and ±0/±maximum finite/±smallest subnormal for all four
packed widths. Save-before seven-trial whole cooks at domains 1/8, then
repeat the eight-domain pair in reverse executable order with separate raw
files because whole timing varies. Repeat parent/child preparation attribution
before/after and restore its source byte-for-byte. Keep only if preparation
improves repeatably without whole-cook regression; otherwise revert. No
scheduling, grid, IR, cache, dependency or gate change is approved.

Preparation attribution checkpoint: `--ship` passes (exit 0) after production
restoration. No profiler ships and no native GPU arithmetic changes.

## F2.1 field kernel — packed finite scan trial (2026-10-09)

The shared packed Value.validate branch retains width-first validation and
ascending first-invalid behavior, but moves the original `fin "array input"`
error call outside the successful sequential scan. No scheduling, grid,
IR, cache, dependency or public API changes. Existing every-coordinate NaN/
±infinity, malformed-width precedence, unchanged storage and bounded
allocation checks remain green. Empty arrays and ±0/±maximum finite/
±smallest subnormal for Float/Vec2/Vec3/Vec4 now also pass before/after.

Confirmed M1/Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev profile,
grain 16,384, seven isolated trials after one excluded warm-up, fresh
zero-capacity sessions and unchanged GC policy. No builds, tests, benchmarks
or other agent work overlap trials. Repeat the first pair at domains 1/8,
then the eight-domain pair in reverse executable order:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-scan-before.exe --fields > specification/performance/f-field-scan-cook-before-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-scan-after.exe --fields > specification/performance/f-field-scan-cook-after-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-scan-after.exe --fields > specification/performance/f-field-scan-cook-reverse-after-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-scan-before.exe --fields > specification/performance/f-field-scan-cook-reverse-before-8.csv
```

| Uninstrumented whole cook | Before median ms | After median ms | Before allocated bytes | After allocated bytes |
|---|---:|---:|---:|---:|
| One domain | 27.539 | 26.272 | 42720424 | 42720424 |
| Eight domains, before then after | 11.948 | 10.417 | 42757464 | 42757168 |
| Eight domains, after then before | 15.840 | 11.280 | 42757872 | 42758120 |

Both eight-domain run orders improve whole cooking, but the unchanged strict
<10.000 ms gate remains unmet. The differing baseline medians limit the
precision of a whole-cook speedup claim; all outliers are retained.

Repeat parent/child attribution with the archived
`f-field-scan-time-instrumentation.patch`, restoring both production sources
byte-for-byte after saving executables. Phase CSVs print 17 significant
digits, sufficient to round-trip the original binary clock durations. Repeat
at domains 1/8:

```sh
RAYS_F_FIELD_PROFILE=1 RAYS_F_PREPARE_PHASE_CSV=specification/performance/f-field-scan-child-before-8.csv RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-scan-profile-before.exe --fields > specification/performance/f-field-scan-time-cook-before-8.csv 2> specification/performance/f-field-scan-parent-before-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_F_PREPARE_PHASE_CSV=specification/performance/f-field-scan-child-after-8.csv RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-scan-profile-precise-after.exe --fields > specification/performance/f-field-scan-time-cook-after-8.csv 2> specification/performance/f-field-scan-parent-after-8.csv
```

| Time-only interval | One domain before ms | One domain after ms | Eight domains before ms | Eight domains after ms |
|---|---:|---:|---:|---:|
| Grid | 1.610 | 1.427 | 1.498 | 1.582 |
| Preparation parent | 1.856 | 0.578 | 1.868 | 0.597 |
| Map construction child | 1.842 | 0.562 | 1.850 | 0.574 |
| IR preparation child | 0.013 | 0.014 | 0.018 | 0.017 |
| Kernel | 7.026 | 7.105 | 2.236 | 2.377 |
| Extraction | 17.194 | 17.149 | 8.018 | 7.359 |
| Instrumented whole cook | 27.760 | 26.450 | 13.881 | 11.974 |

Instrumented allocation medians are unchanged at 42,721,344 bytes at one
domain and 42,758,728→42,758,960 at eight. Preparation improves by about
1.27 ms across both domain counts. Every cook has one child pair within the
parent, using exact rational arithmetic on round-tripped binary durations;
32 parent/16 child rows include warm-up -1 and timed trials 0..6. Children
are never added twice to phase totals. All hashes remain
`8a9c2d382ab7564328783e84a132cef1`, with 85,680 points/vertices and 28,560
triangles. No algorithm or GC changes in diagnostic intervals.

All raw rows are under `specification/performance/f-field-scan-*.csv`.
The initial nine-decimal diagnostic batch is retained as `*-rounded.csv`:
independent decimal rounding produced two one-nanosecond child-sum artifacts.
An attempted overwrite of a read-only saved executable failed, so the next
batch mixed old/new timer formats; those rows are preserved separately as
`*-mixed-precision.csv`. Neither batch is used for the final containment or
attribution table. A fresh uniquely named executable and four complete
17-digit runs provide the table above; no old evidence is overwritten.

`otool -tvV _build/default/lib/flow/.flow.objs/native/flow__Value.o` before/
after shows the successful candidate loop keeps index/array/length in
registers and branches to the error call only after leaving the loop. The
old loop spills/reloads its index around the possible call. Function assembly
excerpts are archived as `f-field-scan-assembly-{before,after}.txt`. This
supports the proposed compiler mechanism; it does not explain unrelated
whole-cook variation. Restored `@check`, Flow/SOP/procedural tests and the
benchmark build pass (exit 0). No profiler ships. Astra's verdict follows.

Astra's verdict: “Keep the sequential validation scan.” Exact input/error/
mesh checks and bounded allocations pass; both whole-cook run orders favor
it, and preparation improves consistently. The <10 ms gate is still unmet.
Next: “not met, try hoisting the SOP grid's y-coordinate calculation per row
and z-coordinate calculation per plane.” Preserve original sequential loops
and cancellation checks, all FMA expressions and inner x indexing. Compute
z once per uncancelled plane and y once per row, with all work inside the
cook. Reuse complete non-dyadic/asymmetric lattice/mesh/cancellation tests,
inspect assembly and allocation for boxing, save-before seven-trial whole
cooks at domains 1/8 and a reverse-order eight-domain pair, and use only
four-phase time attribution (child preparation timers unnecessary). Keep
only with repeatable whole-cook benefit, exactness and no material allocation
or one-domain regression; otherwise revert. No scheduling, cache or API
change is approved.

Sequential scan checkpoint: `--ship` and native GPU numerics
(`@lib/flow_gpu/runtest-native`) pass (exit 0) on the confirmed M1. Shipping
includes full workspace parity at four times/domains 1/8. No tolerances,
goldens or gates were changed.

## F2.1 field kernel — rejected sequential coordinate hoist (2026-10-09)

Astra's trial preserves original sequential loops/cancellation, computes the
unchanged z FMA once per uncancelled plane and y FMA once per row, and stores
those values in the unchanged x-fast inner loop. Existing complete actual
coordinate-bit and mesh tests on large asymmetric/non-dyadic lattices at
one/eight domains, grain cutoffs and precancellation pass. No new redundant
fixture, scheduling, cache, numerical expression or API change. Relocated
`objdump -dr` excerpts in `f-field-hoist-assembly-{before,after}.txt` show the
three FMA call sites in their respective plane/row/x loops; repeated y/z
calls fall from 549,250 to 4,290 on the 65³ grid. Whole allocation is
unchanged at one domain, with no new area-sized boxing.

Confirmed M1/Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev profile,
grain 16,384, seven isolated trials per process after an excluded warm-up,
fresh zero-capacity sessions, existing GC policy. No builds, tests, other
benchmarks or agent work overlap. Repeat the first pair at domains 1/8,
then the eight-domain pair in reverse executable order:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-hoist-before.exe --fields > specification/performance/f-field-hoist-cook-before-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-hoist-after.exe --fields > specification/performance/f-field-hoist-cook-after-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-hoist-after.exe --fields > specification/performance/f-field-hoist-cook-reverse-after-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-hoist-before.exe --fields > specification/performance/f-field-hoist-cook-reverse-before-8.csv
```

| Initial uninstrumented whole cook | Before median ms | Trial median ms | Before allocated bytes | Trial allocated bytes |
|---|---:|---:|---:|---:|
| One domain | 26.338 | 28.200 | 42720424 | 42720424 |
| Eight domains, before then after | 11.572 | 10.791 | 42757352 | 42756784 |
| Eight domains, after then before | 11.153 | 13.566 | 42756640 | 42756984 |

The first eight-domain order improves, but one-domain time regresses 7.1%
and reversed eight-domain time regresses 21.6%. The gate is unmet.

Repeat four-phase attribution at domains 1/8 with buffered output, no GC
snapshots or preparation children, then restore production source:

```sh
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-hoist-time-before.exe --fields > specification/performance/f-field-hoist-time-cook-before-8.csv 2> specification/performance/f-field-hoist-time-phase-before-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-field-hoist-time-after.exe --fields > specification/performance/f-field-hoist-time-cook-after-8.csv 2> specification/performance/f-field-hoist-time-phase-after-8.csv
```

| Time-only interval | One domain before ms | One domain trial ms | Eight domains before ms | Eight domains trial ms |
|---|---:|---:|---:|---:|
| Grid | 1.582 | 0.760 | 1.628 | 0.857 |
| Preparation | 0.595 | 0.591 | 0.596 | 0.648 |
| Kernel | 7.132 | 7.003 | 2.235 | 2.236 |
| Extraction | 18.565 | 17.185 | 10.851 | 7.199 |
| Instrumented whole cook | 28.751 | 25.649 | 15.533 | 10.971 |

Instrumented allocations are 42,721,064 bytes at one domain in both builds
and 42,758,080→42,757,456 at eight. Each phase file retains 32 rows including
warm-up -1 and trials 0..6. Grid attribution improves consistently, while
whole-cook evidence contradicts a repeatable benefit. Attribution cannot
establish why whole timing differs. The temporary patch is archived as
`f-field-hoist-time-instrumentation.patch` (applied after the trial patch).

Astra's first verdict: “Revert the hoist from shipping code for now; preserve
its patch and executable for one controlled repeat.” Production is restored
to `c69c79fd` byte-for-byte; `f-field-hoist-trial.patch` preserves the candidate.
Restored focused checks pass (exit 0). No profiler or hoist ships.

Astra next approved only “not met, try an order-balanced paired repeat of
the unchanged y/z-hoist candidate.” Eight adjacent process pairs per domain
alternate before→after and after→before. Each process preserves all seven
cooks; each executable/domain therefore has 56 measured rows. Domains 1/8
run sequentially with no concurrent work. Every process has its own raw CSV:
`f-field-hoist-paired-{domains}-{pair}-{before,after}.csv`, pair IDs 0..7.
`f-field-hoist-paired-runs.csv` records domains, pair ID, order, position,
executable and raw path; `f-field-hoist-paired-summary.csv` records every
pair, order aggregate and pooled result. No earlier batch is replaced or
selectively combined. Even-count medians average the two middle values.
Each invocation follows this example, varying pair ID/executable/domains:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-hoist-before.exe --fields > specification/performance/f-field-hoist-paired-8-0-before.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-hoist-after.exe --fields > specification/performance/f-field-hoist-paired-8-0-after.csv
```

| Balanced whole cook | Rows per executable | Before median ms | Trial median ms |
|---|---:|---:|---:|
| One domain, before→after groups | 28 | 27.323 | 26.816 |
| One domain, after→before groups | 28 | 26.968 | 26.486 |
| One domain, all rows | 56 | 26.988 | 26.640 |
| Eight domains, before→after groups | 28 | 12.400 | 13.293 |
| Eight domains, after→before groups | 28 | 11.697 | 12.207 |
| Eight domains, all rows | 56 | 11.915 | 12.688 |

Pair-median trial-minus-before deltas, milliseconds, pair order 0..7:
one domain −1.288/−0.617/−0.634/+0.766/−0.833/−0.895/−0.860/−0.754;
eight domains +1.889/+0.407/−1.868/+3.090/−2.118/−1.639/+7.915/−0.226.
Pooled allocation medians are 42,720,424 bytes in both one-domain builds,
and 42,757,536→42,757,552 at eight. Eight domains win four of eight pairs
but lose both order aggregates and the pooled result (+6.49%). The full
predeclared candidate median 12.688 ms misses the strict <10.000 ms gate;
a fast individual pair/process is not the gate dataset.

All initial, instrumented and balanced rows preserve hash
`8a9c2d382ab7564328783e84a132cef1`, 85,680 points/vertices and 28,560
triangles. Every wall/allocation/promotion/major row remains available.
No tolerance, golden or gate is relaxed. Production remains reverted;
Astra's final review determines the next different step.

Astra's final verdict: “Leave the y/z hoist reverted; stop testing that
candidate.” Its eight-domain pooled median regresses 6.49%, and both order
aggregates regress with effectively unchanged allocation. No further repeat
of this candidate is approved.

Next: “not met, try time-only attribution of the sampled extractor's joined
count and emission passes within the whole SOP cook.” On the retained scan
checkpoint, temporarily time caller-side count through its join, prefix/
output allocation/setup, emission through its join, and packed wrapping/
geometry construction. These are children of the coarse extract interval,
not overlapping worker-time sums. No GC snapshots, output inside intervals
or algorithm change. Use round-trip timestamp precision, verify one phase
set/cook with IDs -1,0..6, paired child containment, full hashes/counts and
unchanged cancellation/error paths. Seven isolated retained uninstrumented
and diagnostic cooks at domains 1/8 use the same M1/dev/grain/cache/warmup/GC
settings; keep all raw rows under `f-field-extract-phases-*`, report paired
parent-minus-child residuals and overhead, then restore source and any
temporary Unix linkage in Dune byte-for-byte. No production dependency or
public API change. F1.3/F2.2/F2.3 remain required work; their checks never
overlap benchmark execution.

Rejected-hoist checkpoint: restored focused checks and `--ship` pass
(exit 0). Production source is identical to the native-qualified scan
checkpoint `c69c79fd`; this commit adds only documentation and evidence.

## F2.1 field kernel — joined extractor phase attribution (2026-10-09)

On retained scan checkpoint `d4a4b60b`, temporary caller-side timestamps
measure count through the shared-pool join, prefix/output allocation/setup,
emission through its join, and packed wrapping/geometry construction. These
are children of the existing coarse extraction interval, never overlapping
worker sums. No algorithm, cancellation, GC or error-path changes. Timestamp
output uses 17 significant digits and is buffered until exit. Temporary Unix
linkage and all production sources are restored byte-for-byte. The archived
three-source/Dune patch is `f-field-extract-phases-instrumentation.patch`.

Confirmed M1/Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev profile,
grain 16,384, seven isolated cooks per process after one excluded warm-up,
fresh zero-capacity sessions and existing GC policy. No builds, tests, other
benchmarks or agent work overlap. Save retained and instrumented executables,
restore source, and repeat these commands at domains 1/8:

```sh
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-extract-retained.exe --fields > specification/performance/f-field-extract-phases-cook-8.csv
RAYS_F_FIELD_PROFILE=1 RAYS_F_EXTRACT_PHASE_CSV=specification/performance/f-field-extract-phases-child-8.csv RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-extract-phases.exe --fields > specification/performance/f-field-extract-phases-time-cook-8.csv 2> specification/performance/f-field-extract-phases-parent-8.csv
```

| Whole cook | One domain median ms | Eight domains median ms | One domain allocated bytes | Eight domains allocated bytes |
|---|---:|---:|---:|---:|
| Uninstrumented | 28.687 | 18.417 | 42720424 | 42757352 |
| Instrumented | 26.260 | 12.181 | 42721440 | 42758616 |

| Time-only interval | One domain median ms | Eight domains median ms |
|---|---:|---:|
| Grid | 1.544 | 1.579 |
| Preparation | 0.589 | 0.594 |
| Kernel | 7.026 | 2.277 |
| Extraction parent | 17.161 | 7.898 |
| Count child, through join | 3.632 | 1.330 |
| Prefix/output setup child | 0.073 | 0.084 |
| Emission child, through join | 13.021 | 6.155 |
| Packed/geometry finish child | 0.401 | 0.440 |

All full hashes are `8a9c2d382ab7564328783e84a132cef1`, with 85,680
points/vertices and 28,560 triangles. Each domain has exactly 32 parent and
32 child rows, one phase set per warm-up -1 and trials 0..6. Child sums fit
in the paired extraction parent using exact rational arithmetic on the
round-tripped binary durations. Per-cook parent, child sum and residual are
retained in `f-field-extract-phases-residual.csv`, including warm-up. Timed
residual medians are 0.954 μs at one domain and 1.907 μs at eight.

Observed instrumented-minus-uninstrumented whole median differences are
−2.427 ms at one domain and −6.236 ms at eight; these do not measure a
speedup or isolate wall-time overhead because the separate whole runs vary.
Instrumentation adds 1,016/1,264 median allocated bytes at one/eight domains.
All raw wall/allocation/promotion/major and phase outliers remain in
`specification/performance/f-field-extract-phases-*.csv`. Phase medians are
not summed into a whole median. The strict <10.000 ms gate remains unmet.

Astra's interpretation: joined emission is the largest measured interval;
it includes gradients, the second count pass, local prefixes and triangle
filling, not filling alone. Its verdict is “not met, try writing interpolated
edge positions and normals directly into the existing packed output arrays.”
The approved trial writes each triangle's three edges into disjoint owned
slots, reads them for unchanged cross/outward/flip arithmetic, and swaps both
position/normal slots together if flipped. Flat shading overwrites its three
normal slots as before. Preserve expressions, association, thresholds,
normalization, signed zeros, triangle order/counters/assertions. No edge
reuse, caches, gradients or scheduling changes or new storage.

Before implementation, capture one aggregate full-geometry golden across
all 256 cube masks, inside values 1/equality 0 and smooth/flat shading,
retaining empty-mask errors. Retain nonlinear seams, asymmetry, domains/grains
and saved-before benchmark hashes. Seven isolated before/after trials at
domains 1/8 cover whole SOP cooking and sampled/dense sphere/gyroid/asymmetric
controls; reverse the eight-domain whole pair and repeat joined emission
attribution. Keep only with exact geometry/errors, material allocation
reduction and repeatable whole benefit without material control regression;
otherwise correct/revert. The strict whole-cook <10 ms gate is unchanged.
Restored `@check`, RDK/procedural SOP/Flow SOP checks and benchmark build pass
(exit 0). No diagnostic code or Unix linkage ships.

## F1.3 shared GPU form-check foundation (2026-10-09)

Previously emission owned pure restrictions while placement and display
execution checked only collect/Zip/skip. A marked program with a used
float64 constant outside float32 range could be selected and prepared before
emission refused it. `Packed.gpu_refusals` now supplies those exact checks to
all three callers. Register/octave/float32 facts are shared in `Packed_ops`;
qualification and generation share a fresh output-reachability mask. Ordered
accumulators remain checked across all instructions; constants/noise remain
output-reachable only. Refusal precedence/text are unchanged, and all emitter
goldens remain unchanged. There is no new dependency edge or instruction,
arithmetic, CPU iteration or fusion change.

Correction to the earlier F1.3 audit/design: one-source `for` already emits
successfully because `Private.view` treats a single source as effective Zip,
even if the internal iteration is Product. Preserve that behavior and add a
regression; do not change CPU iteration to fix a nonexistent mismatch.

Astra's verdict: “The foundation diff is correct by inspection.” Its requested
boundary regression is implemented: a marked used-1e39 map remains Cpu_kernel
under zero GPU cost; Qualification display returns Ok None without backend
preparation or dispatch. Restoring only the old placement gate makes that
fixture fail its tier assertion; restoring only the old display gate makes
it fail its display assertion. Both guards are restored and the fixture
passes. Focused emitter checks cover one-source loops, Float/Vec2/Vec4,
32-octave noise, used/unused float32-overflow constants and existing product/
reduction/skip refusals. Mask traversal is bounded by the existing register
limit, with no retained cache or work proportional to array length. This is
correctness groundwork, not a measured frame-performance improvement.

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest @lib/flow_gpu/runtest @tools/api_manifest/runtest
dune promote
```

Focused checks pass (exit 0); the narrow additions to Packed_ops/Packed APIs
are reviewed and intentionally promoted. Backend/Flow specifications describe
the shared actual-program backstop. This does not complete F1.3: declaration
capabilities, diagnostic packed compilation, checker candidate/provenance/
state facts, instantiated capture qualification, inspector reasons and the
full authored actual-catalog audit still require implementation and coverage.

Shared-form-check checkpoint: `--ship` and
`@lib/flow_gpu/runtest-native` pass (exit 0) on the confirmed M1, with the
full workspace sweep at four times/domains 1/8 and unchanged native noise
tolerances. The preceding full F5 pixel/native qualification is explicitly
attributed to `8f1f4789`; final full-scope qualification remains required.

## F2.1 pre-edge complete-geometry regression (2026-10-09)

Before changing shared edge emission, retained marcher `2c9feb3e` captures
one aggregate hash `4efce5e9c56d8d5fb9ead44e339bded7`. Existing independent
six-tetrahedron count checks now cover all 256 masks, inside value 1 and
exact-equality value 0, and both smooth/flat shading (1,024 cases). The
aggregate records smooth/inside/mask plus complete authored geometry bytes
through the existing Rdk_test_support.geometry_bytes helper: positions,
topology, attributes and groups, excluding allocation IDs/derived caches.
Empty results are retained and checked against the existing empty-surface
message. This protects winding, normals, ordering, signed-zero bits and
degenerate cases; cardinality equality alone is insufficient.

The unset expected hash fails and reports the captured retained result;
installing that result passes without an algorithm change. Do not refresh
it merely to accept candidate drift. Native/production emission is unchanged.

```sh
_build/default/tools/check.exe @check @lib/rdk/test_core @lib/procedural/test_sop_nodes tools/bench_rdk_iso.exe tools/bench_workspace_lower.exe
```

Focused checks pass (exit 0). Existing nonlinear seam/asymmetric/domain/grain
regressions remain. The next direct-write trial still needs saved-before
workspace/RDK executables and all Astra-prescribed whole/control/phase
measurements; this test checkpoint makes no performance claim.

The checkpoint also passes `_build/default/tools/check.exe --ship` (exit 0),
including the full build, tests, native smoke examples and whitespace check.

## F2.1 field kernel: direct packed edges (2026-10-09)

Apple M1 (Macmini9,1, eight logical CPUs), OCaml 5.3, Dune dev profile.
Baseline is `696d84bd`, with the aggregate geometry golden captured from
retained `2c9feb3e`. Only shared marching edge emission changes: interpolate
positions/normals directly into the already allocated packed arrays, then
read each triangle's three owned slots for the unchanged winding calculation.
A flip swaps both position and normal slots. Flat-normal arithmetic remains
unchanged. No gradient, sampling, scheduling, storage, cache, public API or
production dependency change. The previous Vec3 records/pairs and winding
tuple were immediately copied and discarded.

Seven measured trials per executable/domain/fixture, excluded warm-up,
shared pool, grain 16,384, unchanged GC settings. Whole cooks use a fresh
zero-capacity Session per cook, warm the pool and one full cook, then perform
one full major collection before the measured sequence. Each trial includes
grid, preparation, kernel and complete extraction; hashes are computed outside
the timer. RDK controls retain their existing warm-up/GC policy. All runs are
isolated: no concurrent builds, tests, or active agents. Every row and outlier
is retained. The reverse eight-domain whole pair runs after then before.

```sh
# Saved both benchmark executables before editing production.
cp _build/default/tools/bench_workspace_lower.exe /private/tmp/f-workspace-edge-before-696d84bd.exe
cp _build/default/tools/bench_rdk_iso.exe /private/tmp/f-rdk-edge-before-696d84bd.exe
# After focused checks/build, saved the candidate under corresponding after names.
for domains in 1 8; do
  RAYS_BENCH_DOMAINS=$domains RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-edge-before-696d84bd.exe --fields > specification/performance/f-field-edge-cook-before-$domains.csv
  for mode in sampled-sphere sampled-gyroid sampled-asymmetric sphere raw asymmetric; do
    RAYS_BENCH_DOMAINS=$domains RAYS_BENCH_REPEATS=7 RAYS_RDK_ISO_RESOLUTION=64 /private/tmp/f-rdk-edge-before-696d84bd.exe --$mode > specification/performance/f-field-edge-$mode-before-$domains.csv
  done
done
# Run the same matrix with after executable/output names, then the reverse pair:
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-edge-after-696d84bd.exe --fields > specification/performance/f-field-edge-cook-reverse-after-8.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 /private/tmp/f-workspace-edge-before-696d84bd.exe --fields > specification/performance/f-field-edge-cook-reverse-before-8.csv
```

Medians (ms; allocation is aggregate bytes across all domains):

| Fixture | Domains | Before ms | After ms | Before bytes | After bytes |
|---|---:|---:|---:|---:|---:|
| Whole sphere SOP | 1 | 26.190996 | 25.660038 | 42,720,424 | 26,994,928 |
| Whole sphere SOP | 8 | 9.758949 | 9.131908 | 42,757,720 | 27,031,480 |
| Whole sphere SOP, reverse order | 8 | 10.291815 | 9.860992 | 42,757,192 | 27,031,320 |
| Sampled sphere | 1 | 16.199827 | 15.541792 | 32,194,008 | 16,468,512 |
| Sampled sphere | 8 | 5.765915 | 4.505873 | 32,217,664 | 16,492,536 |
| Sampled gyroid | 1 | 29.654026 | 29.453993 | 114,913,752 | 40,239,576 |
| Sampled gyroid | 8 | 12.468100 | 7.889986 | 114,939,416 | 40,263,144 |
| Sampled asymmetric | 1 | 10.540009 | 9.574175 | 50,978,832 | 20,243,256 |
| Sampled asymmetric | 8 | 6.936073 | 5.650043 | 50,982,280 | 20,246,704 |
| Dense sphere | 1 | 20.308018 | 19.589901 | 31,393,656 | 15,668,160 |
| Dense sphere | 8 | 21.497011 | 20.071983 | 31,393,888 | 15,668,392 |
| Dense gyroid | 1 | 41.675091 | 41.371107 | 105,325,400 | 30,651,224 |
| Dense gyroid | 8 | 45.075893 | 41.692972 | 105,325,632 | 30,651,456 |
| Dense asymmetric | 1 | 11.899948 | 10.797977 | 49,918,888 | 19,183,312 |
| Dense asymmetric | 8 | 12.394905 | 11.059999 | 49,966,464 | 19,232,264 |

The unchanged complete sphere hash is `8a9c2d382ab7564328783e84a132cef1`,
85,680 points/vertices, 28,560 triangles, 64³ cells and 65³ samples. Gyroid
and asymmetric full hashes/cardinalities also match the saved baseline at
both domains in every row. Sphere/gyroid use 64³ cells; asymmetric uses
(129,256,2) cells and the existing off-centre sphere/non-dyadic bounds.
The committed 1,024-mask golden remains
`4efce5e9c56d8d5fb9ead44e339bded7`; nonlinear seam/asymmetric, grain/domain,
malformed-input, cancellation and source-ownership regressions also pass.
No golden, threshold or tolerance is refreshed.

The identical joined count/setup/emission/finish diagnostic from
`f-field-extract-phases-instrumentation.patch` applies to retained and
candidate sources. Temporary Unix linkage and SOP/RDK timers are restored
byte-for-byte after saving both diagnostic executables. Caller intervals
include joins; worker times are never summed. Emit includes gradients,
second count/local prefixes and triangle filling, not just filling.

```sh
for version in before after; do
  for domains in 1 8; do
    RAYS_BENCH_DOMAINS=$domains RAYS_BENCH_REPEATS=7 RAYS_F_FIELD_PROFILE=1 RAYS_F_EXTRACT_PHASE_CSV=specification/performance/f-field-edge-phases-child-$version-$domains.csv /private/tmp/f-workspace-edge-phases-$version-696d84bd.exe --fields > specification/performance/f-field-edge-phases-cook-$version-$domains.csv 2> specification/performance/f-field-edge-phases-parent-$version-$domains.csv
  done
done
```

| Joined phase | 1 domain before ms | 1 domain after ms | 8 domains before ms | 8 domains after ms |
|---|---:|---:|---:|---:|
| Count | 3.661871 | 3.659010 | 0.727177 | 0.755072 |
| Setup | 0.077963 | 0.082016 | 0.083923 | 0.082970 |
| Emission | 13.145924 | 12.234926 | 4.163980 | 3.610134 |
| Packed wrapping/geometry | 0.406027 | 0.401020 | 0.432968 | 0.479937 |
| Complete extraction parent | 17.448187 | 16.386986 | 5.896091 | 5.198956 |
| Instrumented whole cook | 26.643991 | 25.750875 | 10.092020 | 9.541035 |

All 32 parent/child rows per executable/domain contain warm-up -1 and timed
IDs 0..6, exactly one set per cook. Rational parsing of round-trip timestamps
verifies each child sum is contained in its extraction parent; every residual
is retained in `f-field-edge-phases-residual.csv`. Instrumented whole medians
are 0.453/0.091 ms above the one-domain uninstrumented before/after batches,
and 0.333/0.409 ms above at eight domains. Instrumentation allocation overhead
is 1,016 bytes at one domain and 112/1,704 bytes at eight domains for
before/after. These are separately run batches and include host variability;
this does not establish precise causal timer overhead.

Astra's verdict is **“met”**: keep direct packed edges. Both measured
eight-domain whole-cook after medians are strictly below 10 ms, opposite
orders both improve, one-domain timing improves, all six control medians
improve, and whole-cook allocation falls 15,725,496 bytes (36.8%) at one
domain. Joined emission supports the intended attribution. This establishes
the measured F2.1 gate on this machine/profile, not completion of F1.3,
F2.2/F2.3, a general latency guarantee, or allocation-free rendering. No
further F2.1 optimization is requested.

Focused restored checks pass (exit 0):

```sh
_build/default/tools/check.exe @check @lib/rdk/runtest @lib/procedural/test_sop_nodes @lib/flow_sop/runtest tools/bench_rdk_iso.exe tools/bench_workspace_lower.exe
```

Shipping and full F5 native/pixel validation pass (exit 0) on the M1:

```sh
_build/default/tools/check.exe --ship
_build/default/tools/check.exe @lib/flow_gpu/runtest-native @lib/rays/test_shape_batch_native @lib/rays/test_scene3_float32_native @lib/rays/test_canvas_native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
```

The native sweep includes 37 standard files, two actual custom-catalog
executables and 13 fixtures at four times/domains 1/8, with cooked payloads
and native geometry/image/texture/drawing pixels equal. SOP render parity's
23 graphs also retain one/four-domain PNGs. No display goldens are refreshed.
Production source remains the measured candidate; diagnostics are absent.

After restoring instrumentation, the shipping-built workspace/RDK benchmark
executables have the exact same SHA-256 as the saved uninstrumented candidate:
`1d687fab9d20bcf15f332e4d54a9a460bb551c0433b2570918870dd2c0fcacf8`
and `cde649c5d36faba6dd1d3cfde62b30b9d5e795ed5c69392e604034d288b02ea6`.

## F1.3 explicit packed declaration capability (2026-10-09)

The declaration foundation adds `Packed_ops.extension = Noise3`, an explicit
`Op.t.packed_extension` and `Op.packed_kind`. Packed and scalar IR share this
classifier. Canonical scalar built-ins require declaration identity; operations
without dynamic register instructions still constant-fold. Canonical frame
operations remain accepted, including record/list-valued operations in scalar
IR. The sole intrinsic extension is explicitly declared noise3 with its
existing scalar value/name/vec3-position/int-keyword/float-result contract.
Validation reports E_OP_DECLARATION for a malformed capability and direct
classification also refuses it. A capability asserts intrinsic semantics;
changing a copied declaration's behavior clears it. Color declarations and
the opaque custom-noise fixture clear theirs. External full record constructors
initialize no capability. No new dependency, cache, CPU arithmetic, argument
ordering, register generation, iteration or fusion behavior.

Tests exercise real/counterfeit/copy declarations, malformed position/result/
keyword/name/live capabilities, reverse keyword order, color capability reset,
actual real-noise residual compilation and counterfeit refusal. The existing
packed one/eight-domain matrix adds a folded floor constant in a live map,
including count zero; existing scalar/packed/noise/fallback parity remains.
Focused validation passes (exit 0), emitter goldens unchanged:

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest @lib/flow_gpu/runtest @lib/flow_sop/runtest
_build/default/tools/check.exe @tools/api_manifest/runtest
# Review expected Op/Packed_ops additions, then accept deliberately.
dune promote
```

The first focused runs caught two test compile errors (record-update syntax
and private color declaration access); both are corrected. The manifest check
first fails with precisely the intended two-module API additions, then those
are reviewed/promoted. No numeric or rendering golden changes.

Astra approves this declaration checkpoint: no unintended narrowing or
execution changes, no additional blocking regression. This is a correctness
foundation with no timing/performance claim or new benchmark gate. It does
not complete F1.3: diagnostic compile_result, checker candidate/provenance/state
facts, actual instantiated capture qualification, inspector reasons and the
full authored producer/emitter audit remain open.

Shipping and native GPU validation pass (exit 0) for this checkpoint:

```sh
_build/default/tools/check.exe --ship
_build/default/tools/check.exe @lib/flow_gpu/runtest-native
```

The full workspace IR sweep covers 37 standard files, two actual custom
catalog executables and 13 fixtures at four times/domains 1/8. Native
arithmetic/select/Vec2/Vec4 results are exact at 1,024 and 65,536 elements;
noise maxima are 8.82050105e-7 and 9.88528899e-5 within the existing tolerance.
Full F5
native/pixel qualification of the preceding field optimization belongs to
`97e5f7bf`; final full-scope native/pixel qualification remains required.

## F1.3 diagnostic packed compilation (2026-10-09)

`Packed.compile_result` returns the first actual compilation refusal with
its source span and concrete state/function/capture/type/form/register-limit/
operator/constant/layout reason. Evaluator errors retain their original code
and span (or acquire the nearest expression span when missing). Existing
option compile/template APIs wrap the same implementation. Fatal helper
sites now use a separate diagnostic exception; speculative `Unsupported`
control flow remains for deferred-vector capture projection, unknown counts,
declined child compilation and over-budget fusion. Runtime materialization
still uses the reference fallback on refusal. No arithmetic, register
emission, argument order, iteration, fusion decision or dependency edge changes.

The existing packed matrix checks legacy option/result agreement and identical
successful program views, counts and provenance. Focused cases cover state,
function, capture, type, form, limit, operator and constant refusals with
nonempty messages/spans; exactly 64 versus 65 registers; preserved E_NONFINITE
for a folded constant; deferred Vec2/Vec3/Vec4 record components; and two
individually valid stages whose combined register budget declines fusion
but successfully executes the unfused program. Captures/fusion retain exact
reference parity at four times and one/eight domains. Ordinary evaluation
rejects the nonfinite literal before compilation; its test uses a checked
subterm in the compatible live residual scope to exercise the public API.

Focused validation passes (exit 0):

```sh
_build/default/tools/check.exe @check @lib/flow_ir/runtest @lib/flow_gpu/runtest @lib/flow_sop/runtest
_build/default/tools/check.exe @tools/api_manifest/runtest
# Review the expected single Packed.compile_result binding, then accept it.
dune promote
```

The manifest check initially exits 1 with that intended addition and its
module hash; the diff is reviewed/promoted. Emitter/numeric goldens and
existing tolerances remain unchanged. Astra approves this diagnostic
checkpoint: no missing normal-path refusal translation or fallback regression,
and no additional blocking test needed. The generic Unsupported backstop
remains, with normal fatal helpers providing concrete reasons. This is a
correctness foundation without a performance claim or new benchmark gate.
It does not complete F1.3: checker candidate/provenance/state facts, actual
instantiated capture qualification, inspector reasons and the complete
authored producer/emitter audit remain required.

Shipping and native GPU validation pass (exit 0) on Macmini9,1, Apple M1,
OCaml 5.3/dev:

```sh
_build/default/tools/check.exe --ship
_build/default/tools/check.exe @lib/flow_gpu/runtest-native
```

The complete workspace IR sweep covers 37 standard files, two actual
custom-catalog executables and 13 fixtures at four times/domains 1/8. Native
arithmetic/select/Vec2/Vec4/input results remain exact at 1,024 and 65,536
elements; noise maxima remain 8.82050105e-7 and 9.88528899e-5 within the
unchanged tolerance. This checkpoint's native scope is emitted GPU numerics.
The full F5 native/pixel sweep qualified the preceding field checkpoint
`97e5f7bf`; final full-scope native/pixel qualification is still required.

## F1.3 actual static kernel observation (2026-10-09)

Astra's evaluator-hook design places observation in `ev`'s static branch,
following the existing path/context adjustment and outside the `ev_raw`
Needs_t handler. `Eval.Private.static_with_kernels` factors the existing static
implementation and observes each actual entry into map/reduce/loop/array-sum,
without type filtering. Entirely static and empty maps are observed before
materialization; unsupported list/signature instances remain visible. The
handle captures the exact current checked term, lexical free bindings,
instance and iteration tuple. Definitions and nested forms enter normally;
no deduplication or manufactured untaken visits. An attempted specialization
is observed even if its later Needs_t discards nodes from that attempt.

Observer handles share `Private.map_function`'s existing negative synthetic
ID allocator, moved above the evaluator. They do not increment the ordinary
residual counter or alter function identities/evaluator keys. Live states
explicitly clear the callback, including Packed's capture adapter evaluation.
Static evaluation clears it in Fun.protect on success/error so returned
residual contexts do not retain the observer closure. Ordinary Eval.static
supplies no callback; arithmetic, iteration and materialization are unchanged.
No new dependency or proof cache. This is observation infrastructure, without
a speed claim; definitive qualification/checker provenance, consumer metadata,
inspector reasons and the whole authored producer/emitter audit remain open.

The one evaluator regression compares ordinary and observed results, records,
instances, plan/authored structure and ordinary residual/function identities.
It exercises static/empty/live/list maps, a captured graph input in default
and overridden instances, defn captures, nested iteration tuples, reduce and
array/sum, exact checked-term identity and untaken-branch exclusion. Synthetic
IDs are distinct/negative. A callback's reference eval_term does not recurse
into observation; after return, forcing at 0, 0.125, 1.25 and 7 yields identical
values without another callback.

Focused validation passes (exit 0):

```sh
_build/default/tools/check.exe @check
_build/default/tools/check.exe @check @lib/flow/runtest
_build/default/tools/check.exe @tools/api_manifest/runtest
# Review the single Eval.Private.static_with_kernels binding, then accept it.
dune promote
```

The manifest check first exits 1 with exactly that intended addition and the
Eval module hash; the diff is reviewed/promoted. Existing goldens/tolerances
remain unchanged. Astra approves the observer checkpoint with no blocking
correctness issue; observations include attempted specializations whose
enclosing evaluation later defers, rather than exhaustive execution coverage.
Shipping and native GPU validation pass (exit 0) on Macmini9,1, Apple M1,
OCaml 5.3/dev:

```sh
_build/default/tools/check.exe --ship
_build/default/tools/check.exe @lib/flow_gpu/runtest-native
```

The full workspace IR sweep covers 37 standard files, two actual custom
catalog executables and 13 fixtures at four times/domains 1/8. Native
arithmetic/select/Vec2/Vec4/input results remain exact at 1,024 and 65,536
elements; noise maxima remain 8.82050105e-7 and 9.88528899e-5 within the
unchanged tolerance. This qualifies the observation foundation and existing
evaluation paths, not the still-unimplemented definitive qualification layer.
Final full-scope native/pixel qualification remains required.

## F1.3 actual-capture qualification (2026-10-09)

Machine: Macmini9,1, Apple M1, eight logical CPUs, OCaml 5.3, Dune dev.
This is correctness/eligibility evidence, not a timing benchmark.

The checker now publishes immutable packed candidate/refusal facts and
producer/body provenance independently of precision taint. Its definitive
approximation set starts empty. `Flow_ir.qualify_workspace` observes actual
static captures, compiles with production fusion and applies the shared GPU
form restrictions. Refusal dominates pending ambiguity, which dominates
success; untaken or unassociated producers remain pending. Every qualification
rebuilds from candidates, without proof caches or per-frame compilation.
Lowering and document metadata publication are connected to the inspector and
all existing audit/benchmark consumers. Literal patches share one guarded
physical-form remapper for terms and producer metadata.

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest \
  @lib/flow_gpu/runtest @lib/flow_sop/runtest @test/test_scene_sync \
  @test/test_workspace_doc @test/test_workspace_source @tools/api_manifest/runtest
# Review the five intended API surfaces, then accept their generated diff.
dune promote tools/api_manifest/api_stable.json
_build/default/tools/check.exe @check @lib/flow_ir/runtest
_build/default/tools/bench_kernel.exe --gpu-check
_build/default/tools/bench_workspace_lower.exe --approx
_build/default/tools/check.exe --ship
_build/default/tools/check.exe @lib/flow_gpu/runtest-native
```

Focused executables pass; the first combined run exits 1 only for the intended
API diff, subsequently reviewed/promoted. The final boundary regression run
passes (exit 0). Tests pin capture requalification with unchanged candidates,
failure/ambiguity ordering, source preservation/reuse, generated/repeated/zero
IDs, aliases/bypass, state, empty/static/vector/noise kernels and register
limits. A failed child compilation retains its materialized boundary while
the outer map qualifies; one refused use of a shared callable prevents its
body path qualifying without disqualifying the independent successful root.

The 39-file `--approx` audit passes with each actual catalog, including
sop_gallery and voxel_wall: 23 qualified paths (five particles, six Flow
kernel, twelve Flow particles GPU). Each published dependency has observed
authored producers accepted by fused/unfused compilation and pure emission.
Pending/refused paths are reported explicitly; no unassociated observation
is silently counted as success. Shipping passes (exit 0), including 37
standard files, both actual custom-catalog executables and 13 fixtures,
ordinary/qualified static signature equality and CPU/reference/cooked parity
at four times and domains 1/8. Pure GPU fixtures pass (exit 0).

Native GPU validation passes (exit 0). Arithmetic/select/Vec2/Vec4/Vec4-input
results remain exact at 1,024 and 65,536 elements; noise maximum absolute
errors are 8.82050105e-7 and 9.88528899e-5 within the unchanged tolerance.
No golden, tolerance or performance gate is relaxed. Logs:
`/tmp/rays-f-qualification-{focused-final,boundaries,ship,native,gpu-fixtures,approx}.log`.

Astra approves the implementation and focused checks; its final F1.3 verdict
is “met”. This closes actual-capture eligibility qualification, not F2.2/F2.3
or the full F scope. No performance improvement is claimed. Final full-scope
native/pixel qualification and the field re-gate remain required after the
image/resident work.

## F2.2 image kernel: CPU checkpoint (2026-10-09)

Implementation and raw measurement commit: `4ba82525`.

Machine: Macmini9,1, Apple M1, eight logical CPUs, OCaml 5.3, Dune dev.
Seven isolated warm trials per fixture/size at domains one/eight; no builds,
tests or other agents run during either measurement command.

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_sop/runtest \
  @lib/procedural/runtest @tools/api_manifest/runtest @sketches/runtest \
  test/test_workspace_images.exe test/test_workspace_images_native.exe \
  tools/bench_workspace_lower.exe
# Review/accept the Image_kernel and Image.Private API surfaces and sketch rule.
dune promote tools/api_manifest/api_stable.json sketches/dune.rays.inc
cd test
SDL_VIDEODRIVER=dummy SDL_AUDIODRIVER=dummy ../_build/default/test/test_workspace_images.exe
../_build/default/test/test_workspace_images_native.exe
cd ..
_build/default/tools/check.exe --ship
RAYS_BENCH_DOMAINS=1 RAYS_BENCH_REPEATS=7 \
  _build/default/tools/bench_workspace_lower.exe --image-map \
  > specification/performance/f-image-map-cpu-domains1.csv
RAYS_BENCH_DOMAINS=8 RAYS_BENCH_REPEATS=7 \
  _build/default/tools/bench_workspace_lower.exe --image-map \
  > specification/performance/f-image-map-cpu-domains8.csv
```

| Whole CPU cook | Size | One domain median ms | Eight domains median ms |
|---|---:|---:|---:|
| Gradient | 512² | 10.766029 | 3.033876 |
| Gradient | 1024² | 60.293913 | 11.874914 |
| Gradient | 2048² | 213.590860 | 43.864012 |
| Live capture | 512² | 11.169910 | 3.770113 |
| Live capture | 1024² | 57.817936 | 12.237072 |
| Live capture | 2048² | 219.217062 | 44.734001 |

| Cold grid/program preparation + first cook | Size | One domain ms | Eight domains ms |
|---|---:|---:|---:|
| Gradient | 512² | 15.240192 | 5.321980 |
| Gradient | 1024² | 64.701080 | 21.168947 |
| Gradient | 2048² | 233.356953 | 69.581032 |
| Live capture | 512² | 12.104988 | 4.801989 |
| Live capture | 1024² | 62.089920 | 16.487122 |
| Live capture | 2048² | 221.880913 | 61.650991 |

The pool is warmed before the cold-preparation rows. Warm rows reuse the UV
grid and program, disable session output-cache hits, and time session/context
setup through uncached `Session.cook`, finished `Payload.Image` conversion and
cleanup. Hashing and GC preparation are outside timing. The live fixture
changes its captured time each trial. Each domain CSV contains all 48 raw
samples (six cold rows and 42 warm rows), including all-domain allocation
counts and complete-image hashes. Every corresponding hash matches across
domain counts; live-image hashes change between trials. At 1024², median
allocated bytes are 40,517,576 / 40,608,704 for gradient at domains 1/8 and
41,587,608 / 41,679,800 for the live capture. Only the final output image is
one RGBA8 buffer; packed float output and execution scratch remain temporary
allocations. This is not a constant-allocation CPU claim.

The first measurement command stopped before the live fixture because its
benchmark source returned a function from a `let*` in the function-input
position (`E_FN_ESCAPES`). Its partial gradient rows remain in
`performance/f-image-map-cpu-invalid-fixture.csv`, excluded from the gate.
The corrected fixture captures bias around `image/map`, matching the authored
workspace syntax. Both complete domain commands above then pass (exit 0).

Functional checks pin strict Vec2→Vec4 typing, editable graph zones/rows,
pixel-center orientation on a 387×91 image, scalar reference/packed output,
byte rounding/clipping/nonfinite/cancellation, named functions and lexical
time captures. Byte-backed SOP sampling matches explicit normalized float
sampling at one/eight domains. Workspace tests cover drawing, texture and
SOP consumers at four times/domains 1/8, replan/body-edit/resize with stable
image identity, and balanced creation/destruction. Native 65×3 nested
image/map→draw/image→image/render refreshes for time-dependent callable
captures and for different drawing-fold snapshots at the same frame facts.
State-dependent pixel bodies explicitly retain `E_PACKED_STATE`.

Shipping passes (exit 0), including 38 standard workspaces, both actual custom
catalog executables and 13 fixtures; log:
`/tmp/rays-f-image-map-cpu-ship.log`. Astra's read-only checkpoint review finds
no remaining blocker and its measured **CPU whole-cook gate verdict is PASS**:
both 1024² eight-domain medians are below the unchanged 40 ms gate.

This establishes the prepared CPU producer gate, excluding display upload and
rendering. It does not establish synthetic image GPU eligibility, GPU
conversion/copy, resident/exact ownership, geometry capture resolution in the
workspace, GPU timing/allocation/resource/readback gates, native CPU/GPU
per-channel differences or F2.3. F2.2 and the full F scope remain open.

## F2.2 GPU immutable-input upload checkpoint (2026-10-09)

Machine: Macmini9,1 Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. GPU work runs on the initial domain. Each size has ten warm-up
dispatches and seven isolated trials of 200 completed dispatches. No agents,
builds or tests run during either measurement command.

```sh
_build/default/tools/check.exe @check tools/bench_kernel.exe
# Before: input-upload counters installed, input reuse not installed.
RAYS_BENCH_DOMAINS=1 _build/default/tools/bench_kernel.exe --gpu-uploads \
  > specification/performance/f-image-gpu-uploads-before.csv
# After: same fixture and commands with immutable-input reuse.
RAYS_BENCH_DOMAINS=1 _build/default/tools/bench_kernel.exe --gpu-uploads \
  > specification/performance/f-image-gpu-uploads-after.csv
_build/default/tools/check.exe @check @lib/flow_gpu/runtest \
  @lib/flow_gpu/runtest-native @tools/api_manifest/runtest
```

| Immutable UV → Vec4 runner | Before median ms/frame | After median ms/frame | Before input upload bytes/frame | After input upload bytes/frame |
|---|---:|---:|---:|---:|
| 512² | 1.854100 | 0.237235 | 2,097,152 | 0 |
| 1024² | 7.553384 | 0.682425 | 8,388,608 | 0 |
| 2048² | 28.449996 | 2.063916 | 33,554,432 | 0 |

The fixture uses a packed pixel-center Vec2 UV array and the emitted body
`[uv.x uv.y t 1]`. Preparation and pipeline creation are outside timing.
Every dispatch changes the time uniform, submits and completes GPU work,
and reads the mandatory four-byte finite-status flag. No output-buffer or
texture readback occurs in timed frames. Each trial reports raw wall time,
OCaml allocation, actual successful input writes/bytes and persistent buffer
creations. The latter stays at three total, with no warm creation delta.
Median allocation is 6,529 bytes/frame before and 6,513 after at each size;
this establishes constant OCaml allocation for this prepared runner, not
literal zero allocation. Both raw CSVs contain all 21 trials.

Each input slot retains one immutable source identity and covered byte
length, valid only for its current buffer. A replacement or count change
requires upload. Invalidate the marker before a changed-source write:
a failed write can partially overwrite the previous source. Mark the new
source only after success; buffer replacement and close clear the marker.
Frame uniforms and status reset remain unconditional. The public runner
contract requires replacing arrays rather than mutating uploaded storage.

The mock regression injects a partially completed replacement upload, then
requires reupload of both the previous and replacement arrays. It checks
same-source reuse, changed coverage, buffer growth, failed completion,
float32 overflow, stale outputs and owner/domain cleanup. Native tests
verify same-sized replacement/reversion and changed frame uniforms while
reusing the same source. Existing arithmetic and vector outputs remain exact;
noise remains within its unchanged recorded tolerance. Focused/native checks
pass; the intended API manifest change adds only two private upload counters.

These measurements cover upload reuse and completed producer dispatch only.
They exclude RGBA8 conversion, buffer-to-texture copy, workspace placement,
resident display, frozen exact snapshots and image rendering. The sub-5 ms
F2.2 image gate remains unproven until the completed image route is measured.

Astra reviewed the implementation and both complete raw CSVs. Verdict:
**“Upload checkpoint accepted.”** No ownership or failure-path blocker
remains. The verdict establishes immutable-input reuse only, not the F2.2
GPU image gate.

`_build/default/tools/check.exe --ship` passes (exit 0), including all 38
standard workspaces, both actual custom-catalog executables and 13 fixtures
at four times/domains 1/8. Log: `/tmp/rays-f-gpu-uploads-ship.log`.

## F2.2 image kernel: GPU producer/converter checkpoint (2026-10-09)

Machine: Macmini9,1 Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. GPU execution is on the initial domain. Each fixture/size has ten
warm-up frames followed by seven isolated trials of 200 completed frames.
No agents, tests or builds run during the timing command.

```sh
_build/default/tools/check.exe @check @lib/flow_gpu/runtest \
  @lib/flow_gpu/runtest-native tools/bench_kernel.exe
RAYS_BENCH_DOMAINS=1 _build/default/tools/bench_kernel.exe --image-map-gpu \
  > specification/performance/f-image-map-gpu-converter.csv
_build/default/lib/flow_gpu/test_image_sink_native.exe \
  > specification/performance/f-image-map-gpu-converter-parity.csv
_build/default/tools/check.exe --ship
```

| Producer/converter | 512² median ms/frame | 1024² median ms/frame | 2048² median ms/frame | Allocated bytes/frame at every size |
|---|---:|---:|---:|---:|
| Gradient | 0.605360 | 1.915741 | 4.919800 | 18,121 |
| Live capture | 0.594580 | 1.937801 | 6.020305 | 21,849 |

These are actual authored `image/map` functions prepared by
`Flow_sop.Image_kernel`, retaining its immutable UV grid and packed program.
Each timed frame performs fresh `Packed.Private.prepare`, producer dispatch
and completion including its four-byte finite-status read, RGBA8 conversion,
the existing `Backend.buffer_to_texture` copy, conversion completion, and
`Image_sink.texture` token access. The live fixture changes a captured time
uniform within [0,1) every frame. No session/result cache skips dispatch.
The gradient is deliberately dispatched even though its colors are static.
GC preparation, grid/program preparation and first pipeline/resource creation
are outside warm timing. Device duration covers both submissions and is
supplemental to completed wall time.

Every warm trial records zero runner/sink buffer creations, zero texture
creations and zero input uploads/bytes. Each records 200 status reads and
zero output-buffer readback bytes. The converter reads no buffer/texture
pixels, pinned by the mock command test. OCaml metadata allocation is
constant across the three element counts, rather than literally zero.
The CSV retains all 54 rows: six fresh-owner cold rows, 42 warm trials,
and six resize rows. Readback for the separate native parity command is
outside the performance command.

| Fixture | Cold size | Cold preparation + first conversion ms | Resize dimensions | Grid/program preparation + first resized conversion ms |
|---|---:|---:|---:|---:|
| Gradient | 512² | 72.737217 | 513×512 | 4.867077 |
| Gradient | 1024² | 15.810966 | 1025×1024 | 21.028042 |
| Gradient | 2048² | 57.151079 | 2049×2048 | 88.518143 |
| Live capture | 512² | 31.422853 | 513×512 | 5.434990 |
| Live capture | 1024² | 17.657995 | 1025×1024 | 49.423933 |
| Live capture | 2048² | 66.067934 | 2049×2048 | 73.869944 |

Cold rows each have one sample, not a median; they include grid/program,
emission, pipeline/library creation, source upload, buffer/texture creation
and the first completed output. Native driver caches are retained. Resize
reuses the runner/pipelines, builds the changed UV grid/program, uploads its
new source, grows runner buffers and transactionally replaces sink storage.
Allocation scales in these cold/resize rows and is recorded in the raw CSV.

The converter capability-checks compute, validates device limits and requires
a live width-four output containing exactly width×height pixels. It clamps
finite float32 channels, multiplies by 255 and explicitly rounds ties to
even. Rows use 256-byte alignment; compute and blit share the conversion
submission. A source-buffer read is unnecessary because the producer already
validated finite output. At unchanged dimensions one buffer/texture pair is
reused. Resize retains the old pair until completion, cleans up a failed new
pair, and invalidates borrowed outputs before writes. Close releases its
resources, pipeline and library before the GPU lease.

Native parity covers gradient, live capture, both tie parities and clipping
at 65×3 and times 0/0.5/1. All twelve rows have maximum channel difference
**0**, differing channels **0** and differing pixels **0**. Tests also cover
17×5 resize, source/sink generation invalidation, repeated close and domain
ownership. Mock coverage checks compute→blit order/padding, unchanged reuse,
failed pipeline/texture allocation, dispatch/copy/completion failure cleanup,
transactional resize and no pixel reads. It does not simulate shader math.
Existing native arithmetic/vector tests remain exact and noise retains its
unchanged tolerance. Intended API changes add the owned `Image_sink` module
and two private runner counters; the reviewed manifest is promoted.

Astra's verdict after reviewing all raw rows and the measurement boundary:
**“Producer/converter checkpoint accepted.”** Both 1024² medians are below
5 ms for this prepared producer/converter. This is not the full F2.2 GPU gate:
runtime-image publication, authored qualification/placement, resident 2D/mesh
consumers, frozen exact snapshots and full display-frame allocation are
outside the timer. Connected native parity and F2.3 remain open.

Focused/native checks and `_build/default/tools/check.exe --ship` pass
(exit 0), including all 38 standard workspaces, two actual custom-catalog
executables and 13 fixtures at four times/domains 1/8. Shipping log:
`/tmp/rays-f-gpu-image-sink-ship.log`. The final focused check additionally
pins wrong-domain creation and refusal of scalar runner output.

### F2.2 image kernel: authored qualification checkpoint (2026-10-09)

Machine: Macmini9,1, Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. This checkpoint changes qualification/provenance plumbing, not a
kernel algorithm or measured cost row. It makes no timing improvement claim.
The exact CPU image regression runs at domains 1/8; native GPU qualification
runs on the initial domain, at three times per fixture.

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest @lib/flow_sop/runtest @lib/flow_gpu/runtest @lib/flow_gpu/runtest-native @tools/api_manifest/runtest
dune promote tools/api_manifest/api_stable.json
_build/default/tools/bench_workspace_lower.exe --approx
_build/default/lib/flow_gpu/test_image_sink_native.exe > specification/performance/f-image-map-qualification-parity.csv
_build/default/tools/check.exe --ship
cd test
../_build/default/test/test_workspace_images_native.exe
```

Canonical authored `image/map` producers now enter the existing static
observer and qualification pipeline. Only the actual checked function argument
is evaluated; its instantiated callable and lexical captures are bound to a
representative immutable Vec2 column. Production packed compilation and shared
GPU form checks decide eligibility. Folded constants qualify; unsupported
dynamic operations, state-dependent pixels and used float32-overflow captures
retain their actual refusal. A refusal dominates successful instances in
either order; requalification of finite captures recovers from immutable
candidates. An unconsumed function supplies no image permission.

The synthetic pixel map preserves separate authored path and runtime
instance/site/iteration provenance. Lowering collects transient observations
and retains only an authored path per image plan node. A missing observation
is sticky before or after a successful observation at the same runtime tuple,
independently of the qualifier's authored conclusion. Workspace image owners
retain only `(plan, approx, image_sites)` and invalidate prepared maps on a
binding change. Unknown/unbound provenance stays CPU-only. Qualified internal
pixel programs use the display sink; the image recipe does not taint every
consumer, and exact CPU cooking remains unchanged.

| Native fixture | Dimensions | Times | Maximum channel difference | Differing channels | Differing pixels |
|---|---|---|---:|---:|---:|
| Qualified aliased named-function image | 65×17 | 0, 0.5, 1 | 0 | 0 | 0 |
| Existing gradient/live/tie/clipping converter controls | 65×3 | 0, 0.5, 1 | 0 | 0 | 0 |

The named-function fixture follows actual qualification, `Lower.image_sites`,
`Image_kernel.prepare`, prepared executor selection in Qualification policy,
the production `Flow_gpu.Host`, and completed RGBA8 conversion/copy before
channel comparison to exact CPU output. All fifteen raw rows are in
`specification/performance/f-image-map-qualification-parity.csv`. Pixel reads
occur only for this numerical verification. Mock callbacks separately verify
permission and ownership selection; they do not simulate shader math.
CPU tests preserve full image bytes at one/eight domains and prove an earlier
snapshot survives a later cook. Fused/unfused compiler and emitter checks cover
the representative adaptation; the prepared asymmetric UV grid exercises the
actual executor. The actual-catalog audit covers 40 files including both custom
catalogs, with four qualified paths in `flow_image_kernel`.

Astra's final reviewed verdict is **“Approved.”**
Focused checks, native tests and the qualification audit pass (exit 0). The four
intended public API changes are reviewed and promoted. This does not establish
resident runtime-image publication, exact GPU snapshot boundaries, the full
F2.2 timing/allocation gate or F2.3. The final shipping run passes (exit 0),
including 38 standard workspaces, two actual custom-catalog executables and
13 fixtures at four times/domains 1/8. Shipping log:
`/tmp/rays-f-image-qualification-ship.log`.
The native workspace image executable also passes (exit 0), covering nested
render invalidation, same-frame state changes, exact one/eight-domain Canvas
snapshots and owned-resource close. Its log is
`/tmp/rays-f-image-qualification-workspace-native.log`.

### F2.2 image kernel: borrowed runtime backing checkpoint (2026-10-09)

Machine: Macmini9,1, Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. Mock publication checks and native GPU checks run on the initial
domain; two isolated wrong-domain calls verify refusal. Native fixtures run
once at each of times 0/0.5/1. This is a resource-boundary correctness check,
not a timing benchmark or a revised cost row.

```sh
_build/default/tools/check.exe @check @lib/runtime/resources/runtest @lib/rays/runtest @lib/flow_gpu/runtest-native @lib/rays/test_canvas_native
_build/default/tools/check.exe @lib/rays_pathtracer/test_gpu_film @tools/api_manifest/runtest
_build/default/lib/flow_gpu/test_image_sink_native.exe > specification/performance/f-image-gpu-backing-parity.csv
_build/default/tools/check.exe --ship
```

Private runtime images validate a borrowed GPU callback before publication:
positive/cardinality-safe dimensions, matching RGBA8 depth-one single-sample
storage, sampling and copy-source usages, initial-domain access and a live
texture. Later reads require the same physical texture; expiration or
substitution returns a typed resource error. Replacement preserves identity
and changes dimensions/generation only after validation. No dummy CPU pixels
are allocated. Explicit snapshots own their readback bytes across publication,
resize and destruction. Image destruction drops its borrow; the producer owns
the texture. Successful CPU replacement and every Canvas-copy publication
branch clear GPU backing, including reuse of an earlier Canvas mirror.

| Check | Result |
|---|---|
| Mock constructor, 65×3 and 1024² | Each allocation delta below the 4 KiB regression ceiling |
| Stored CPU bytes at GPU publication | 0 |
| Pixel reads at GPU publication | 0 |
| Qualified named image through publication, 65×17, times 0/0.5/1 | Maximum channel difference 0; differing channels/pixels 0 |
| Earlier converter and qualification controls | All fifteen rows retain zero channel/pixel differences |
| Expired source without image-generation change | Both lower-scene caching and reused Scene rendering refuse; republication produces changed pixels equal to a fresh render |
| Existing native path-tracer film | Compatible publication, zero live-handle delta |

All eighteen raw native rows are in
`specification/performance/f-image-gpu-backing-parity.csv`. Channel verification
explicitly reads pixels; publication itself does not. Image readback counters
count actual successful image reads. Mock tests additionally cover invalid
descriptors, resize, destroyed/substituted sources, failed replacement without
mutation, stable leases, repeated release/destruction, CPU transitions and
complete mock cleanup. Both cache regressions deliberately hold generation
unchanged during expiration, then verify recovery after republication.
Retained replay validation traverses actual 2D, display-list and UI layer
resources, rather than the aggregate resource list that can be empty during
rendering. Native stage generation stamps use those same layer dependencies.
The strengthened native regression initially failed at its changed-pixel
assertion with the old aggregate-only stamp; it now covers ordinary images,
single retained segments and mixed layers. Initial shipping passed before
these final replay corrections; a new shipping run is required for the final
code. Regression log: `/tmp/rays-f-gpu-image-backing-replay-regression.log`;
the corrected focused/native run passes (exit 0) in
`/tmp/rays-f-gpu-image-backing-replay-fixed.log`.
The small/large constructor allocation assertions guard against area-sized
CPU backing; they do not measure complete display-frame allocation.

Astra's final reviewed verdict after the replay corrections is
**“Checkpoint approved.”** Focused/native checks and API validation pass (exit 0). No public
stable manifest change is needed: the changed private Runtime_resources surface
is excluded from that manifest. This does not establish connected workspace
publication, resident mesh/offscreen consumers, deferred exact GPU snapshots,
captured geometry resolution, the full F2.2 timing/allocation gate or F2.3.
Final shipping validation passes (exit 0), including 38 standard workspaces,
two custom-catalog executables and 13 fixtures at four times/domains 1/8.
Log: `/tmp/rays-f-gpu-image-backing-final-ship.log`.

### F2 resident image groundwork: native camera clip depth (2026-10-09)

Machine: Macmini9,1, Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. Correctness checks run on the initial domain; the pure World fixture
bakes at one domain. Each of two native camera cases renders ordinary geometry
twice and a two-instance batch twice into one 32×32 Canvas. No timing or
performance gate is claimed.

```sh
_build/default/tools/check.exe @check @lib/rays/test_scene3_native_lowering @lib/rays/test_canvas_native
_build/default/tools/check.exe @check @lib/rays/runtest @lib/rays/test_canvas_native @lib/rays/test_scene3_native_lowering_native @lib/rays/test_scene3_float32_native @lib/rays/test_world_raster tools/bench_workspace_lower.exe @tools/api_manifest/runtest
```

The real `image/render`→texture→mesh fixture initially uploaded all CPU texture
bytes but returned a black destination. Its source image changed with time.
A diagnostic using far=3 instead of the default 1000 made source/destination
bytes identical, identifying clip-depth clipping. That diagnostic is not the
round-trip performance baseline. Public Camera/Mat4 matrices use [-1,1] depth;
Metal rasterization uses [0,1]. One package-private adapter now converts
`z_native=(z_public+w)/2` at the five camera/shadow boundaries: ordinary MVP,
instance MVP, World background inverse and two authored Shadow3 uploads.
The fitted sun projection and generic native shaders remain unchanged.

| Regression | Evidence |
|---|---|
| Default orthographic, near=0.1/far=1000 | Near/far map to 0/1; visible green plane |
| Perspective at distance 0.15, near=0.1 | Visible green plane; farther red plane does not overwrite it |
| Two-instance batch and repeated Scene | Visible blue pixels, exact replay snapshots |
| Authored shadows and World inverse | Both uploads use native depth; background inverse reconstructs the public near/far points |
| Fitted sun shadow | Existing native shadow/reuse/zero-handle-delta regression passes |
| Float32 triangle | Original maximum channel difference 0; recolor stays within the unchanged ≤1 tolerance and uploads exactly 36 bytes |
| Owned Canvas fixture | Zero native live-handle delta |

Before-fix pure near/far and native visible-pixel assertions both fail in
`/tmp/rays-f-native-camera-depth-before.log`. The corrected focused checks pass
(exit 0) in `/tmp/rays-f-native-camera-depth-final-focused.log`. Making geometry
visible also exposed a test-oracle defect: the recolored float32 entry was
compared to the original colors. Each legacy render now serializes its actual
source and keys the complete immutable payload, since Scene3 vertex-stable
keys intentionally skip geometry byte comparison. The test requires visible
recoloring; its tolerance and packed upload bound are preserved.

Astra's final review says: “Approved this correctness checkpoint; no remaining
blocker found.” Native qualification passes (exit 0) with the command below.
The sweep covers 38 standard workspaces, two custom-catalog executables and
13 fixtures at four times/domains 1/8. All three workspace pixel aliases pass;
PXUI's 2× golden checks skip at the actual 1× display density, with no fixture
refresh. The first command misspelled one alias; its valid checks completed,
then the corrected command passed using those cached results.

```sh
_build/default/tools/check.exe @lib/rays/runtest-native @lib/flow_gpu/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
```

Logs: `/tmp/rays-f-native-camera-depth-full-native.log` (first command),
`/tmp/rays-f-native-camera-depth-qualified.log` (corrected command).
Shipping passes (exit 0): `_build/default/tools/check.exe --ship`, log
`/tmp/rays-f-native-camera-depth-ship.log`. The benchmark restores the default
camera and verifies full source/destination bytes outside its timer before
accepting any raw performance rows. This does not complete F2.2 or F2.3.

### F2.3 image/render round-trip baseline (2026-10-09)

Machine: Macmini9,1, Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. Native rendering and the editor owner use one domain. The benchmark
runs alone, with no builds, tests or active agents, after the camera-depth
correction `3baff757` passes focused, native and shipping checks.

```sh
RAYS_IMAGE_RENDER_BASELINE=1 RAYS_IMAGE_RENDER_REPEATS=7 RAYS_IMAGE_RENDER_FRAMES=20 RAYS_IMAGE_RENDER_WARMUPS=10 _build/default/tools/bench_workspace_lower.exe --images > specification/performance/f-image-render-roundtrip-before.csv 2> /tmp/rays-f-image-render-roundtrip-before.log
```

Each size retains one editor owner, checked plan, evaluation state, mesh,
default orthographic camera and destination Canvas. A live colored rectangle
is rendered through the real `image/render` producer and workspace texture
callback, then sampled by a nearest-filtered matte-white mesh. The timed warm
interval includes producer rendering, CPU image capture/conversion, texture
resolution/upload and completed offscreen mesh rendering. The existing route
creates and destroys a source Canvas per changed frame. Seven trials each
contain twenty completed frames after ten warmups; each trial uses the same
time sequence 0 through 19/20 with unique frame identities. Full major GC and
global allocation snapshots sit outside the timer. Document parsing, static
evaluation, mesh and camera creation precede the cold-owner timer.

Full final source/destination RGBA8 equality and MD5 validation occur outside
timing and allocation measurements. Each warm hash differs from the initial
time-zero hash and is identical across seven trials. Frame counters prove all
twenty destination renders completed; baseline-only assertions require at least
one full RGBA8 destination upload per frame. Image ownership balances at close.

| Size | Warm median ms/frame | Allocated bytes/frame | Destination uploaded bytes/frame | Warm full-byte MD5 |
|---|---:|---:|---:|---|
| 512² | 43.399990 | 67,918,306 | 1,048,576 | `cdc3cea2e1c2d39634538ec65341e790` |
| 1024² | 139.405048 | 250,370,554 | 4,194,304 | `cf67ff4b1a5a6eff98fca9312f3b5a47` |
| 2048² | 514.362109 | 980,179,450 | 16,777,216 | `6a44f30ed4a2757a638cd5062df9c325` |

| Size | Cold owner + frame ms | Cold allocated bytes | Teardown ms | Teardown allocated bytes |
|---|---:|---:|---:|---:|
| 512² | 115.930796 | 78,451,384 | 1.712084 | 33,632 |
| 1024² | 150.013924 | 267,189,944 | 2.427816 | 33,632 |
| 2048² | 530.053854 | 1,022,164,664 | 5.149126 | 33,632 |

Cold and teardown rows are single observations, not medians. Warm allocation
is the median of seven whole-trial allocation totals divided by twenty;
destination uploads equal the full RGBA8 extent at every size and trial.
The CSV also retains the existing seven-trial CPU image/noise controls at
128²/512²/1024² and domains 1/8, with matching hashes across domain counts.
Those controls are not an F2.2 image/map measurement.

Astra's verdict: “Accepted as the F2.3 roundtrip baseline.” This establishes
the current live producer→texture→completed mesh cost and pixel oracle. It
does not establish the resident allocation gate, an after improvement, GPU
image/map performance, resize behavior or GPU resource/readback counters.
The run exits 0. Native stderr includes `Context leak detected, CoreAnalytics
returned false`; this system diagnostic does not establish a Rays resource
leak. Earlier partial black-frame diagnostics are excluded from the accepted
CSV. The next change retains the source Canvas and borrows its completed
texture, then repeats this protocol with the baseline upload assertion disabled.

Raw: `specification/performance/f-image-render-roundtrip-before.csv`;
run log: `/tmp/rays-f-image-render-roundtrip-before.log`.
Reviewed-code `@check tools/bench_workspace_lower.exe` and `--ship` pass
(exit 0); logs `/tmp/rays-f-image-render-baseline-check.log` and
`/tmp/rays-f-image-render-baseline-ship.log`.

### F2 resident image consumers (2026-10-09)

Machine: Macmini9,1, Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. Native producers and consumers run on the initial domain. A single
wrong-domain construction check spawns and joins one test domain. These are
functional parity, ownership and upload/readback checks, not timings.

```sh
_build/default/tools/check.exe @check @lib/rays/runtest @lib/rays_execution/runtest @lib/flow_gpu/runtest @lib/flow_gpu/runtest-native @lib/scene_execution/runtest-native
_build/default/lib/flow_gpu/test_image_sink_native.exe > specification/performance/f-image-resident-consumer-parity.csv 2> /tmp/rays-f-resident-texture-parity.log
_build/default/tools/check.exe @tools/api_manifest/runtest
dune promote tools/api_manifest/api_stable.json
_build/default/tools/check.exe @check @tools/api_manifest/runtest
```

A private Texture backing variant borrows a validated runtime image without
CPU Color arrays or texture ownership. Its stable identity survives image
resize/republication. Pixel extraction, sampling, mipmap generation, subsection
and CPU-level queries explicitly refuse this view until a caller makes an
immutable CPU snapshot. Ordinary CPU Texture behavior remains covered by the
existing Rays texture suite. Native mesh lowering skips CPU levels, binds
`sampled_texture.gpu` and retains image dependencies. Offscreen image lowering
also borrows the successful GPU snapshot, preserving native device validation.
Fresh staging preserves resource errors before image command construction;
cache-hit rendering validates retained layers and mesh dependencies before
replay. Authored geometry is scanned only on uncached staging.

The mixed-layer cache previously froze image source/destination rectangles but
never compared resource dimensions or generations on reuse. It now retains an
exact immutable list of resource ids, identities and generations with its IR;
the byte charge includes seven words per list/three-int-tuple entry. A same-shape
generation change conservatively rebuilds that layer. Cache keys themselves
stay immutable, and existing count/byte capacities remain unchanged.

The native fixture publishes pixel-center gradients at 65×17, times 0.25 and
0.75, then resizes the same image to 17×5 at time 0.5. It renders each through
three retained scene descriptions: a 2D image, a nearest-filtered matte-white
mesh, and a mixed image/mesh scene. The mixed mesh occupies the right half so
old 2D image rectangles remain visible after resize. Each case renders three
times into a 65×17 offscreen Canvas; the third render adds zero uploaded bytes.
Full destination bytes equal a fresh ordinary CPU-image/texture render from
the same GPU producer's explicit verification readback. These nine checks prove
residency versus a GPU→CPU→GPU round-trip oracle, not a float64 producer oracle.

| Check | Result |
|---|---|
| Three scenes × three publications | Maximum channel difference 0; differing channels/pixels 0 |
| Warm consumer upload delta | 0 bytes in each of nine cases |
| Source Image reads during publication/display | 0; one separately requested leased snapshot is counted explicitly |
| Source expiry with unchanged image generation | Typed resource failure; no source readback or CPU fallback |
| Resize | Stable image/view identity; metadata and mixed rectangles refresh |
| CPU-authority transition | Borrowed view refuses CPU fallback until explicitly converted |
| Wrong device | Both image and mesh consumers reject the foreign source; native Scene_execution separately checks typed Cross_device |
| Destruction and ownership | Old leased bytes survive updates/destruction; borrowed texture remains alive until producer close; native handle delta 0 |

Removing the frozen-version guard makes the mixed resize full-byte comparison
fail (exit 1), `/tmp/rays-f-resident-texture-layer-counterfactual.log`. Restoring
the guard passes focused/native checks (exit 0),
`/tmp/rays-f-resident-texture-final-focused.log`. The earlier destruction
diagnostic identified string formatting before the typed checked boundary;
the final fixture covers destroyed 2D and mesh resources. API promotion is
intentional: only Scene.Private's dependency/checked-staging surface and
Texture.Private's borrowed-view constructor/accessor change. The reviewed
manifest passes in `/tmp/rays-f-resident-texture-api-accepted.log`.

The broad suite exposed an existing test lifetime violation in
`test_workspace_shell.run_views`: it closed the editor before staging the
resource-bearing scene to count viewports. Fresh resource validation now
correctly rejects those destroyed UI images. The close predates consolidation
(`ab16bf071`); the unchanged fixture passes at `10038226` before this new
validation. The fixture now stages and checks all four viewports while the
editor is alive, then closes with `Fun.protect`. Astra approves this lifetime
fix; no viewport, golden, tolerance or resource assertion is relaxed.

Astra's verdict: “Approved the resident-consumer checkpoint; no remaining
blocker found.” This approves functional consumer support only. Workspace
GPU publication, resident Canvas production, deferred exact snapshots,
captured-geometry resolution and connected timing/allocation gates remain
pending. Final reviewed-code focused checks and full native qualification pass
(exit 0). Both workspace sweeps cover 38 standard files, two custom-catalog
executables and 13 fixtures at four times/domains 1/8; the native sweep compares
geometry, image, texture and drawing pixels. The 2× PXUI goldens skip at the
actual 1× density; no fixtures are refreshed. The required pre-commit `--ship`
also passes (exit 0).

```sh
_build/default/tools/check.exe @check @test/test_workspace_shell @tools/api_manifest/runtest
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
_build/default/tools/check.exe --ship
```

The first full run fails only at the old closed-editor fixture while both
workspace sweeps complete successfully (`/tmp/rays-f-resident-texture-full.log`).
The corrected fixture passes (`/tmp/rays-f-resident-texture-shell-lifetime.log`);
the full rerun passes (`/tmp/rays-f-resident-texture-full-qualified.log`) with
unchanged expensive sweep results retained by Dune. Shipping log:
`/tmp/rays-f-resident-texture-ship.log`.

Raw: `specification/performance/f-image-resident-consumer-parity.csv` (27 rows:
18 existing producer/publication controls and nine resident consumer cases).
Log: `/tmp/rays-f-resident-texture-parity.log`.

### F2 connected workspace image publication (2026-10-09)

Machine: Macmini9,1, Apple M1, eight logical CPUs; OCaml 5.3.0, Dune dev
profile. GPU resolution/publication and native rendering run on the initial
domain. Independent exact CPU oracles cook at domains 1/8. This checkpoint
measures functional parity and ownership, not timing or allocation gates.

The editor now shares one lazy Workspace_gpu owner with Workspace_images.
Image/map display selection scopes its backend inside resolution, so previews,
Private callbacks and scene texture composition reach the same qualified path.
The chain is Image_kernel.program → Executor.try_display → Host.output →
Image_sink conversion/copy → validated runtime Image → borrowed Texture or
image consumer. Production retains Measured placement and the existing cost
table; only the native fixture explicitly chooses Qualification.

An authored-key entry independently retains optional runtime display and
immutable CPU payloads, each with its own serial/frame/state validity. Exact-first
map cooking creates no runtime Image. Exact requests use Image_kernel.node and
Session.cook and neither read nor replace a resident display. Borrowed Texture
identity remains stable across GPU publication, resize and CPU/GPU transitions.
The display stamp is cleared before attempts and restored only after success;
GPU failures propagate without silently substituting CPU output.

Image sinks key on the authored site, rather than changing runner/output
identity. The owner caches a new sink only after conversion and publication
succeed. Error/exception cleanup closes an uncommitted sink; new creation at 64
is refused, preserving all pinned outputs. A newly created runtime Image is
registered only after its borrowed view validates. Close drops image references,
destroys runtime images, closes sinks and Host, then releases the GPU lease.
Recursive image resolution reserves pending ancestor entries within the same
64-entry bound, including exact-only entries without runtime Images.

Review caught two issues before accepting the checkpoint. Legacy image/render
must resolve CPU child payloads, even if a child already has a resident GPU
display; it now materializes a scoped CPU Image without changing that GPU
image. Other legacy CPU publications must invalidate display validity so
display A → exact B → display A restores A. A new nested rounding regression
uses 0.499999999, whose CPU conversion is 127 while float32 is 128, and checks
the exact rendered bytes against independent domain-1/8 cooking. The resident
child keeps its generation, zero stored CPU bytes and zero Image pixel reads.

```sh
_build/default/tools/check.exe @check @tools/api_manifest/runtest @lib/rays_editor/runtest-native test/test_workspace_images.exe test/test_workspace_images_native.exe
cd _build/default/test
./test_workspace_images.exe > /tmp/rays-f-workspace-gpu-image-final-cpu.log 2>&1
./test_workspace_images_native.exe > /tmp/rays-f-workspace-gpu-image-final-native.log 2>&1
cd ../../..
rg '^test,width|^workspace_gpu_image,' /tmp/rays-f-workspace-gpu-image-final-native.log > specification/performance/f-workspace-image-publication-parity.csv
```

Final focused/API/owner checks pass (exit 0),
`/tmp/rays-f-workspace-gpu-image-final-check.log`. Both actual test executables
pass (exit 0) in the separate logs above. The raw CSV filters the five parity
rows and header from the native executable's output. Width/height are source
dimensions; each mixed image/mesh destination is 65×17. Rows, in order: live
lexical capture at 0/1, body edit/resize to 35×33, GPU return after a 65×3 CPU
placement, and successful static recovery after repeated GPU failure.

| Check | Result |
|---|---|
| Five actual-editor mixed image/mesh renders vs exact CPU-image/Texture oracles | Maximum channel difference 0, differing channels/pixels 0 |
| Warm repeated consumer rendering | Uploaded-byte delta 0 in each case |
| GPU source Image pixel reads | 0 during display and exact CPU requests; mandatory small GPU status reads are separate and are not counted by Image.readbacks |
| Exact-first, exact-after-display and old CPU payloads | No runtime Image on exact-first; same-frame payload reused; old bytes unchanged after update/resize |
| CPU oracle | Exact RGBA8 bytes equal independent session cooking at domains 1/8 |
| Live lexical capture, body edit, odd-size resize, CPU/GPU transitions | Current display; one stable Image and borrowed Texture identity |
| Static GPU execution failure and repeated request | E_KERNEL both times, no stale success; subsequent valid static body renders correctly |
| Nested image/render CPU rounding | 127 at every blue channel; matches independent exact CPU render; resident child untouched |
| Legacy display A → exact B → display A | Original A pixels restored |
| Recursive capacity | 63 exact-only entries reject a new render/new child; child alone can then occupy slot 64; zero runtime Images |

The package-private sink-owner fixture compiles the actual workspace_gpu source
through Dune copy_files, without exposing test mutation hooks. Eighty rejected
shape conversions, eighty rejected new publications and a raised publication
exception leave both the held output and live native handle counts unchanged.
Then 63 more successful keys fill all 64 sink slots; a 65th is rejected while
all prior outputs remain usable. A failed existing-key publication invalidates
its prior output, and retry succeeds at capacity. Owner close restores the
original native handle count. Log:
`/tmp/rays-f-workspace-gpu-image-owner-check.log` (exit 0).

API promotion is intentional: only Editor3.Private.image_plan/image_payload
are added, to qualify the actual owned plan and independently request the
production CPU payload route. Existing public Lisp forms and graph projections
do not change. The manifest passes the final API check.

Astra: “Approved the functional checkpoint; no remaining blocker found.”
Full shipping/F5 qualification passes (exit 0). Both workspace sweeps cover
38 standard files, two custom-catalog executables and 13 fixtures at four
times/domains 1/8; the native sweep checks geometry, image, texture and drawing
pixels. The 2× PXUI goldens remain unqualified at this actual 1× density;
their prior skip is retained by Dune and no fixtures are refreshed.

```sh
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
_build/default/tools/check.exe --ship
```

Logs: `/tmp/rays-f-workspace-gpu-image-full.log` and
`/tmp/rays-f-workspace-gpu-image-ship.log`, both exit 0.
Connected timing/allocation
and the complete size matrix, resident Canvas image/render, explicit frozen
exact GPU snapshots and captured geometry remain open; this checkpoint does
not establish the F2.2 or F2.3 performance gates.

## F2.3 completed-Canvas borrowing boundary (2026-10-09)

Apple M1 Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev. The new
65×3 native fixture runs on the initial domain, with explicit worker-domain
and same-domain OCaml-thread rejection checks. It uses the real native
offscreen producer and image consumer, rather than a mock lifetime flag.

`Canvas.Private.gpu_source` publishes a completed-frame callback checked against
the Canvas publication epoch, runtime generation and physical texture identity.
It expires before later render attempts, including invalid density and failed
late-Clear staging, and before explicit invalidation, CPU mutation or destruction.
Retained Scene replay refuses expired sources even without an Image generation
change. Successful recovery publishes a fresh borrow. CPU captures and snapshot
leases retain their exact bytes through newer rendering and source destruction.

The same-domain thread fixture exposed the shared SDL query accepting any thread
before initialization. The Apple stub now also checks `pthread_main_np()`;
other platforms preserve SDL semantics. SDL tests check main-thread success and
worker-thread rejection before initialization on Apple, and after Video init on
all platforms. Rejected Canvas operations preserve the previously valid source.

| Actual source operation | Successful captures | Successful GPU pixel readbacks |
|---|---:|---:|
| Completed texture borrowed and sampled by another Canvas | 0 | 0 |
| Failed render attempts and explicit invalidation | 0 | 0 |
| CPU pixel mutation | 0 | 1 |
| Subsequent explicit Canvas.to_image | 1 | 2 |
| New GPU frame followed by source destruction | 1 | 2 |

Counters are cumulative within the fixture and count actual successful operations.
Borrowed Images are destroyed before source targets; final live native handles
equal the starting count. Existing 603-frame submission accounting and the
unchanged transient-Scene promotion ceiling also pass.

```sh
_build/default/tools/check.exe @check @lib/sdl3/runtest @lib/runtime/resources/runtest @lib/rays/runtest @lib/rays/test_canvas_native @tools/api_manifest/runtest
_build/default/tools/check.exe @all @runtest @smoke @lib/sdl3/runtest-native @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
_build/default/tools/check.exe --ship
```

Astra approves the Canvas borrowing and Apple guard correction. The API manifest
intentionally adds only Canvas.Private.invalidate/gpu_source/pixel_stats.
This establishes the source/lifetime boundary, not a workspace resident-render
path or an allocation improvement. Workspace ownership, size-dependent cache
invalidation and the matched F2.3 performance gate remain open.

Focused checks and API validation pass (exit 0):
`/tmp/rays-f-retained-canvas-boundary-check.log`. The full shipping/native F5
run passes (exit 0): `/tmp/rays-f-retained-canvas-boundary-full.log`.
Both workspace sweeps cover 38 standard workspaces, two custom-catalog
executables and 13 fixtures at four times/domains 1/8; native geometry, image,
texture and drawing pixels agree. The corrected platform-specific SDL test and
final focused/API checks pass (exit 0):
`/tmp/rays-f-retained-canvas-boundary-final-check.log`.
The 2× PXUI goldens skip at this display's actual 1× density and remain
unqualified; no fixtures or tolerances are changed.

The required pre-commit `--ship` check passes (exit 0):
`/tmp/rays-f-retained-canvas-boundary-ship.log`.

## F2.3 retained workspace Canvas functional checkpoint (2026-10-09)

Apple M1 Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev. Workspace
fixtures use real Metal targets on the initial domain. The dimension fixture
uses the editor's actual lowered plan; the live fixture reloads an authored
`.rays` file through Editor.update. Source dimensions include 65×17 and 35×33;
the mixed 2D/mesh comparison destination is 65×17.

Display image/render retains its same-size source target, publishes completed
borrowed textures under stable authored keys and installs resized targets only
after successful publication. Old callbacks expire before argument forcing,
including failed force/prepare paths. CPU cooking uses a separate temporary
Canvas and leaves resident parent/child publications untouched. Prepared reachable
dimension summaries refresh explicit-size parents of implicit-size children
without invalidating unrelated fixed-size images. Close releases published
Images before retained targets, then GPU sinks/runners/leases.

| Fixture | Evidence |
|---|---|
| Twenty changing same-size display frames | Same Image/Texture identity; target counts remain (2 created, 1 destroyed), with the one earlier explicit CPU capture/readback unchanged |
| Omitted dimensions and explicit-size parent | Target counts (5,0,0,0) → (8,3,0,0); unrelated fixed-size generation unchanged |
| Independent exact snapshots at both sizes | Counts (11,6,3,3) before close → (11,11,3,3) after close; prior CPU bytes unchanged |
| Repeated drawing/argument failures and recovery | No successful publication or target/capture/readback change on failure; old source refuses with typed Destroyed |
| Two failed resized publications | Counts (1,0,0,0) → (2,1,0,0) → (3,2,0,0); close gives (3,3,0,0) |
| Five mixed 2D/mesh CPU round-trip comparisons | Maximum channel difference 0; differing channels 0; differing pixels 0 |
| Fixture teardown | Zero native live-handle delta; no discarded-pixel synchronization |

Count tuples are (targets created, targets destroyed, successful captures,
successful target GPU pixel readbacks). Explicit source Image pixel reads used
by parity comparisons are a separate resource boundary and do not increment
Canvas counters. Three warmed consumer replays add zero destination uploaded bytes.

```sh
_build/default/tools/check.exe @check @tools/api_manifest/runtest test/test_workspace_images.exe test/test_workspace_images_native.exe
(cd _build/default/test && ./test_workspace_images.exe)
(cd _build/default/test && ./test_workspace_images_native.exe)
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
```

Typecheck/API, CPU workspace image tests and actual native image tests pass
(exit 0): `/tmp/rays-f-workspace-retained-canvas-check.log`,
`/tmp/rays-f-workspace-retained-canvas-cpu.log` and
`/tmp/rays-f-workspace-retained-canvas-native.log`. The single new API-manifest
entry is the private actual-source image_render_stats hook. Astra's review:
“Approved the retained-Canvas functional checkpoint; no blocker found.”
Raw parity: `specification/performance/f-workspace-retained-canvas-parity.csv`.
Broad qualification passes (exit 0):
`/tmp/rays-f-workspace-retained-canvas-full.log`. Both complete workspace sweeps
cover 38 standard files, two custom-catalog executables and 13 fixtures at four
times/domains 1/8, including native geometry/image/texture/drawing pixel equality.
The 2× PXUI goldens remain unqualified at the actual 1× density; no fixture or
tolerance is changed. Matched before/after allocation measurements follow below.
This functional checkpoint does
not qualify the connected image/map gate, captured geometry or deferred Lisp
exact-image snapshots.

## F2.3 retained workspace Canvas matched measurement (2026-10-09)

Machine: Apple M1 Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev.
Editor/native rendering uses one domain. Run isolated after full qualification,
with no builds, tests or active agents. The accepted before baseline is
`10038226`; the after uses the same workspace, camera, mesh, destination target,
time sequence and seven trials of twenty completed frames after ten warmups.
The timed interval includes live producer preparation/rendering, borrowed image
publication, texture resolution and completed mesh consumption. Counter snapshots,
source lookup and complete byte/hash comparisons sit outside both timing and
allocation measurements. Source lookup at last_live is checked not to change
publication generation. The original stdout columns are unchanged.

```sh
RAYS_IMAGE_RENDER_REPEATS=7 RAYS_IMAGE_RENDER_FRAMES=20 RAYS_IMAGE_RENDER_WARMUPS=10 _build/default/tools/bench_workspace_lower.exe --images > specification/performance/f-image-render-resident-after.csv 2> /tmp/rays-f-image-render-resident-after.log
rg '^image_render_counters,' /tmp/rays-f-image-render-resident-after.log > specification/performance/f-image-render-resident-counters.csv
```

| Size | Before median ms/frame | After median ms/frame | Before median bytes/frame | After median bytes/frame | Before → after destination upload bytes/frame |
|---|---:|---:|---:|---:|---:|
| 512² | 43.399990 | 0.692904 | 67,918,306 | 85,450 | 1,048,576 → 0 |
| 1024² | 139.405048 | 1.004601 | 250,370,554 | 85,450 | 4,194,304 → 0 |
| 2048² | 514.362109 | 2.203953 | 980,179,450 | 85,450 | 16,777,216 → 0 |

Allocation medians match at every size. Individual early trials range from
84,021 to 84,125 bytes/frame; trials 3–6 are 85,450 at each size. These are
whole-frame allocations, not zero allocation. Every one of the 21 warm trials
has zero actual source target creation/destruction, capture, Canvas readback,
Image readback and destination upload deltas. Cold creates one retained target
without capture/readback; teardown destroys one target without reading discarded
pixels. Each explicit full-byte hash verification performs one source Image
readback outside warm measurement, independently of the source Canvas counter.
Actual source counters in the original before run were unmeasured.

All seven warm MD5s match the corresponding before baseline, and source bytes
equal destination bytes: 512² `cdc3cea2e1c2d39634538ec65341e790`, 1024²
`cf67ff4b1a5a6eff98fca9312f3b5a47`, 2048²
`6a44f30ed4a2757a638cd5062df9c325`. Each differs from its cold time-zero hash.

| Size | After cold owner + frame ms | Cold bytes | Teardown ms | Teardown bytes |
|---|---:|---:|---:|---:|
| 512² | 60.271978 | 17,602,040 | 1.132011 | 53,592 |
| 1024² | 29.478073 | 23,888,680 | 0.972986 | 53,592 |
| 2048² | 34.806967 | 49,054,504 | 1.360893 | 53,592 |

Cold and teardown are single observations. Resize and independent exact CPU
cooks have functional/counter qualification above, not matched timing rows in
this run. CPU image/noise controls remain in the CSV with matching one/eight-domain
hashes; they do not qualify image/map. The connected F2.2 performance matrix,
captured geometry and deferred Lisp exact-image surface remain separate work.

Raw before: `specification/performance/f-image-render-roundtrip-before.csv`.
Raw after/counters: `specification/performance/f-image-render-resident-after.csv`
and `specification/performance/f-image-render-resident-counters.csv`.
Native measurement exits 0: `/tmp/rays-f-image-render-resident-after.log`.
Reviewed counter instrumentation typecheck/API/tool build passes (exit 0):
`/tmp/rays-f-image-render-resident-measure-check.log`.
The required pre-commit shipping check passes (exit 0):
`/tmp/rays-f-workspace-retained-canvas-ship.log`.
Astra's verdict: “F2.3 allocation gate: PASS” for the measured workload.
This qualifies the retained image/render allocation gate across the measured
sizes; it does not complete the deferred Lisp exact-image surface or F2.2.

## F2.2 connected workspace image measurement plumbing (2026-10-09)

Apple M1 Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev. The private
Host counter hook combines current runner totals with counters frozen in the
existing LRU release callback. It retains actual runner creation/release,
pipeline compilation/release, buffer creation, input uploads/bytes, successful
four-byte status reads and explicit output readback bytes. Workspace statistics
add actual sink creation/close and buffer/texture creation, including failed
uncommitted sinks, and preserve Host totals after close. No placement, dispatch,
shader, conversion or cache-policy algorithm changes. Inspection is outside
frame work and requires the initial domain for fresh/live/closed owners.

Native Host regression executes 65 independently prepared producers, forces
eviction, checks all dispatch/upload/buffer totals and the first explicit
4,096-byte readback, then reacquires the original producer. Close preserves
all totals and balances runner/pipeline ownership. The original test's exact
65-creation assumption was incorrect: the existing CLOCK eviction can discard
a newly inserted untouched runner and reacquire it. The regression instead
pins executed status reads exactly and requires creation/release to balance
the actual retained 64 runners. No cache-policy change is made. The workspace
fixture counts 80 failed conversions, 80 failed publications, an exception,
64 committed sinks and failed existing updates: 225 successful sink creations,
225 closes, and 145 buffers/textures each after close. Native handles return
to their starting count.

```sh
_build/default/tools/check.exe @check @lib/flow_gpu/runtest @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @tools/api_manifest/runtest
dune promote
_build/default/tools/check.exe @check @tools/api_manifest/runtest tools/bench_workspace_lower.exe
```

Focused native/pure/API checks pass (exit 0):
`/tmp/rays-f-connected-image-stats-focused.log`. The two intended public
manifest surfaces are Host.Private statistics and Editor3.Private.image_gpu_stats.
Astra approves the accounting as measurement plumbing, with the subsequently
implemented initial-domain guard. This does not establish a performance gate.

The connected benchmark uses actual owner-qualified plans. Both fixtures capture
`bias = t * 0.25`; the live gradient computes its blue channel as
`0.5 + (bias - bias)`, while the changing capture adds bias to uv.x. Dispatch
and Image generation deltas prove the gradient's constant pixels do not hide
a cached display result. Fresh Measured probes record production selection;
the native matrix explicitly selects Qualification. Producer, consumer-only
and complete source-plus-mesh frames have separate rows. Counter/hash/parity
operations remain outside sequential timing/allocation snapshots. Source-file
replan/resize uses the actual Editor.update route, rather than a standalone sink.
Benchmark review and native measurements are complete in the section below.
Broad qualification and pre-commit shipping pass (exit 0); final logs follow.

## F2.2 connected workspace image timing/allocation qualification (2026-10-09)

Machine: Apple M1 Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev.
Native producer/consumer execution uses one domain. Run isolated, without
builds, tests or active agents. Both fixtures use the actual owner-qualified
plan and capture bias = t * 0.25. The gradient retains a genuine live lexical
dependency but constant pixels; successful status-read and publication counters
prove it executes rather than measuring a cached result. The changing capture
adds bias to the red channel. No production placement policy is changed.

```sh
_build/default/tools/check.exe @check @tools/api_manifest/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-connected > specification/performance/f-image-map-connected.csv 2> /tmp/rays-f-image-map-connected.log
rg '^connected_image_counters,' /tmp/rays-f-image-map-connected.log > specification/performance/f-image-map-connected-counters.csv
```

Seven trials of 200 frames follow ten warmups at every size. Each trial uses
bounded times j / 200 and distinct frame identities. The producer timer includes
argument forcing, packed preparation, completed dispatch/status validation,
conversion/buffer-to-texture completion and image/texture availability. Consumer
timing renders an already published image on the retained nearest-filtered mesh;
end-to-end timing resolves a new producer frame then completes that Canvas render.
GC preparation, sequential allocation/counter snapshots, hashes and CPU/native
comparisons sit outside the timer. Consumer cost is measured directly, not
subtracted from unrelated medians.

| Fixture | Size | GPU producer median ms | Producer bytes/frame | Consumer-only median ms | End-to-end median ms | End-to-end bytes/frame |
|---|---:|---:|---:|---:|---:|---:|
| Live-dependency gradient | 512² | 0.587790 | 51,593 | 0.347285 | 0.984905 | 84,649 |
| Live-dependency gradient | 1024² | 1.538370 | 51,593 | 0.593270 | 2.413355 | 84,649 |
| Live-dependency gradient | 2048² | 4.774500 | 51,593 | 1.264100 | 6.608875 | 84,649 |
| Changing capture | 512² | 0.596750 | 43,105 | 0.349175 | 0.991986 | 76,161 |
| Changing capture | 1024² | 1.557695 | 43,105 | 0.595665 | 2.392501 | 76,161 |
| Changing capture | 2048² | 4.840524 | 43,105 | 1.323506 | 6.677926 | 76,161 |

Producer/end-to-end allocation is the listed value at every trial and size,
independent of pixel count across this range; it is not zero OCaml allocation.
Consumer-only allocation medians are 33,073 bytes/frame at every size/fixture
(individual trials 33,071–33,073).

| Exact CPU owner cook | Size | 1-domain median ms | 8-domain median ms | 8-domain median allocated bytes |
|---|---:|---:|---:|---:|
| Live-dependency gradient | 512² | 11.338949 | 4.612923 | 10,586,760 |
| Live-dependency gradient | 1024² | 56.896925 | 13.832092 | 42,228,136 |
| Live-dependency gradient | 2048² | 215.566158 | 46.659946 | 168,799,480 |
| Changing capture | 512² | 11.187077 | 3.503799 | 10,448,256 |
| Changing capture | 1024² | 54.070950 | 13.118982 | 41,696,248 |
| Changing capture | 2048² | 203.433037 | 43.431997 | 166,693,632 |

CPU cooks are seven uncached live requests after preparation/warmup, through
the actual owner payload route including conversion and session cleanup. Every
corresponding complete-byte hash agrees between domains 1 and 8. The unchanged
CPU <40 ms and GPU <5 ms gates concern 1024², not 2048².

All 126 warm counter rows have exactly the expected counts: producer and
end-to-end trials perform 200 mandatory four-byte status reads and publication
generation advances; consumer-only trials perform zero. Persistent runner,
pipeline, sink, buffer and texture creations/releases, input uploads, output
pixel readbacks and destination uploads are zero. Workspace Image/Canvas
creation/destruction/capture/readback totals remain unchanged during those trials.
Sources keep stable Image/Texture identity and zero retained CPU pixel storage.

All 18 full-source comparisons against independently cooked exact CPU results
at domains 1/8 have maximum channel difference 0, differing channels 0 and
differing pixels 0. They cover times 0/0.5 at each square size and source-file
replan/resize to 513×512, 1025×1024 and 2049×2048 at time 0.25. Changing-capture
bytes differ between the two times; gradient bytes remain equal. Each explicit
verification reads the source Image exactly once outside warm measurement,
leaves its display generation unchanged and performs no Host output readback.
Completed nearest-filtered mesh bytes equal the published source bytes.

All six fresh Measured route probes select GPU. These are single selection
observations; repeated timing is Qualification evidence and does not substitute
for production workload calibration. Existing producer/converter rows use a
different measurement boundary; this is the first connected matrix, not a
paired before/after optimization claim.

| Fixture | Size | Cold owner + publication ms | Source replan/resize ms | Teardown ms |
|---|---:|---:|---:|---:|
| Live-dependency gradient | 512² | 7.320881 | 29.718876 | 1.060963 |
| Live-dependency gradient | 1024² | 19.160032 | 80.266953 | 0.831842 |
| Live-dependency gradient | 2048² | 70.925951 | 334.810019 | 1.469851 |
| Changing capture | 512² | 6.987095 | 19.535065 | 0.865936 |
| Changing capture | 1024² | 16.710043 | 74.481010 | 1.487970 |
| Changing capture | 2048² | 57.151079 | 353.077173 | 2.465010 |

Cold/resize/teardown are single observations, with allocation and explicit
verification-read costs retained separately in the raw CSV. Resize includes
actual Editor.update source reconciliation/preparation/publication; writing the
new source precedes measurement. It creates one runner, three runner buffers,
one UV upload and one replacement sink buffer/texture. Close retains all
cumulative counters, balances runner/sink and Image ownership and adds no
source pixel readback. The real per-frame generation and source-storage assertions
are part of the runnable benchmark, not inferred from an isolated converter.

Astra's verdict: “Connected F2.2 timing and allocation gates: PASS for the
measured fixtures.” It reviewed all 264 measurement rows and 168 counter rows.
This accepts the connected performance checkpoint; captured geometry and
deferred Lisp `(exact image)` still prevent F2.2 completion. Full F5 qualification
and pre-commit shipping pass (exit 0).
Native matrix exits 0: `/tmp/rays-f-image-map-connected.log`.
Final tool typecheck/API/build exits 0:
`/tmp/rays-f-connected-image-bench-check.log`.
Raw: `specification/performance/f-image-map-connected.csv` and
`specification/performance/f-image-map-connected-counters.csv`.

```sh
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
_build/default/tools/check.exe --ship
```

Terminal successful logs: `/tmp/rays-f-connected-image-full.log` and
`/tmp/rays-f-connected-image-ship.log`. Native workspace sweeps include standard,
custom and fixture programs at domains 1/8; runtime presentation, gallery and
prepared-command qualification also pass. The actual display is 1×, so 2× UI
goldens remain explicitly unqualified. No tolerance or golden is changed.

## F2.2 captured image geometry foundation (2026-10-09)

This is correctness plumbing, with no new placement policy or performance claim.
`Attribute_kernel.source_origins` extracts the existing point-origin calculation
unchanged, including the source/input count check. `Image_kernel.prepare` stores
the ordered proof before UV allocation; `with_inputs` checks it and shares the
original program/packed UV grid when binding updated compiled inputs. Count or
origin mismatches return `E_DATA_SOURCE` and require preparation again.

`Lower.source_context` uses the captured geometry plan node's actual instance,
including nondefault graph overrides. `source_cone` walks editable inputs from
its compiled source and removes the complement through `Network.remove_nodes`.
This also excludes unrelated drives and image frame callbacks; state declarations
stay conservative. Nested resource resolution must retain the enclosing context.
`Attribute_kernel.materialized_source` is a real Generic geometry consumer,
returning the Session-materialized input with no remaining instance transforms.
It reuses the existing packed-input boundary and does not duplicate expansion.

The focused fixture uses a live box in a nondefault graph override and a pixel
function capturing a reduction of P. The restricted cone resolves without an
image provider, whereas the enclosing network contains an image frame callback.
The first pixel pins the override value independently. Current source updates
change complete image bytes equally at domains 1/8; rebinding physically shares
the original program and equals a freshly prepared CPU kernel. Changed origins,
wrong source counts, absent mappings and out-of-network IDs return typed errors.
A two-transform packed source produces complete geometry bytes identical to
independent `Instance_copy.materialize_instances` at domains 1/8; its captured P
includes both instances and no transforms remain on the consumer output.

Astra: “Approved as a foundation checkpoint, subject to the focused run
completing successfully.” The focused run completed successfully (exit 0):
`/tmp/rays-f-image-capture-foundation-focused.log`.

```sh
_build/default/tools/check.exe @check @lib/flow_sop/runtest @tools/api_manifest/runtest
```

The intended manifest additions are Attribute_kernel source proof/materializing
consumer, Image_kernel.with_inputs and Lower's source context/cone. They are
reviewed and promoted. Broad F5 native qualification and pre-commit shipping pass
(exit 0): `/tmp/rays-f-image-capture-foundation-full.log` and
`/tmp/rays-f-image-capture-foundation-ship.log`. Both workspace IR sweeps cover
38 standard files, two custom catalogs and 13 fixtures at four times/domains 1/8;
the native sweep also compares complete geometry/image/texture/drawing pixels.
Other native GPU, presentation, gallery and UI checks pass. The actual display
is 1×, so 2× UI goldens remain unqualified, with no tolerance or golden changes.

```sh
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
_build/default/tools/check.exe --ship
```

Owner callback context, capture caching/budgets, recursion/freshness and connected
CPU/GPU workspace capture execution remain required. The earlier uncaptured
performance qualification does not establish capture costs.

## F2.2 captured image owner bridge (2026-10-09)

Functional qualification only; no new timing or allocation claim. The owner now
resolves actual live source cones with current callback context, uses the effective
seed/grain/domains for projection and cooking, rebinds unchanged origin proofs,
and bounds retained geometry/flattened arrays to 64 records and 64 MiB. Oversized
captures execute uncached. State snapshots, request recursion and Session cleanup
remain on their established initial-domain/worker boundaries.

The complete CPU executable passes direct nested image-sampling geometry and
stateful sequential-versus-fresh-owner snapshot regressions, matching full image
bytes at domains 1/8 without changing caller state. Native P/Cd captures from two
override instances at times 0/1 have maximum channel difference 0 in all four
cases, exactly four GPU status reads and zero output readback bytes. Mandatory
status reads remain present. Parent captures refresh and the unrelated explicit-
size fixed render retains its generation. Saved CPU payloads remain immutable.
Two actual exported PNGs equal complete independently cooked nested CPU images;
the 0.499999999 channel rounds to CPU127. Export uses reference lowering and CPU
resolution, including nested resources. Ordinary exact payload requests preserve
resident display authority.

Repeated real callback re-entry returns E_IMAGE_CYCLE before any resource
publication, and the same owner subsequently succeeds on the original context.
Caller state and final native handle counts are unchanged. Astra approves the
functional checkpoint once the native executable including PNG equality passes;
that condition is fulfilled. Expanded state/instance coverage, static/changing
capture measurements and the uncaptured
1024-square regression gate remain open. Frozen Lisp `(exact image)` remains open.

Successful focused executables: `/tmp/rays-f-image-capture-owner-cpu.log`,
`/tmp/rays-f-image-capture-owner-native.log`,
`/tmp/rays-f-image-capture-owner-cycle.log`. The intentional API manifest changes
(current callback/resolver context and export factories) are reviewed and promoted.
Broad F5 validation, including the oversized capture qualification, passes
(exit 0; `/tmp/rays-f-image-capture-owner-full-final.log`). This includes the
native GPU/editor/prepared-command tests, workspace pixels, gallery float32,
runtime qualification and PXUI parity. Actual display scale is 1×; 2× goldens
remain unqualified. Pre-commit shipping passes (exit 0;
`/tmp/rays-f-image-capture-owner-ship.log`).

Owner configuration uses a seed/grain-sensitive custom geometry source declaring
Seed/Grain/Domains dependencies. Seeds 17L/49L with grain 257 and domains 1/8 match
independent Image_kernel/Session CPU cooks byte for byte; the observed context
domain count is correct. The 65-source native image (one GPU producer, avoiding
the separate image-count limit) retains 64 source/data records and 78,720 charged
bytes after 65 materializer cooks/flattens. A second producer reuses the first
resolved retained source without further materialization or flattening. Two GPU
dispatches execute. Removing only the metadata ownership guard produces the
expected failed reuse assertion; it is restored before final validation.

The optional qualification allocates one immutable geometry just above 64 MiB.
Only the pixel function changes with time, leaving its source root/projection
unchanged. Two GPU frames produce two materializer cooks/flattens with zero data
records/bytes retained. Returning to a small source and rendering two more frames
adds only one cook/flatten; caching resumes. Four dispatches and full pixel checks
pass, cache sizes are zero after close and final handles are unchanged. This
tests the retained capture-data budget, not total process memory. The work totals
count successful display-capture materialization/flattening; exact CPU source
cooks are separate and do not advance them. Astra: “Approved as a functional
checkpoint; no additional blocker found.” No timing verdict is inferred.

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. These are
deterministic functional fixtures, not timing trials. Commands (run each
executable from its build directory):

```sh
_build/default/tools/check.exe @check @lib/flow_sop/runtest @tools/api_manifest/runtest test/test_workspace_images.exe test/test_workspace_images_native.exe lib/rays_editor/native_qualification/test_workspace_gpu_native.exe
(cd _build/default/test && ./test_workspace_images.exe)
(cd _build/default/test && ./test_workspace_images_native.exe)
(cd _build/default/lib/rays_editor/native_qualification && ./test_workspace_gpu_native.exe)
(cd _build/default/lib/rays_editor/native_qualification && ./test_workspace_gpu_native.exe --capture-budget)
```

Successful oversized run: `/tmp/rays-f-image-capture-owner-oversized.log`.
Counterfactual failed assertion: `/tmp/rays-f-image-capture-owner-budget-without-guard.log`.
Final focused/API run: `/tmp/rays-f-image-capture-owner-focused.log` (exit 0).
The new unstable image_capture_stats hook is intentionally promoted too.

## F2.2 captured workspace image measurement baseline (2026-10-09)

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. Builds, tests
and all other agents were idle for both runs. The existing connected-image
harness accepts eight capture cells: static/changing P/Cd over a 1,024-point
line at 512²/1024²/2048², plus both cases over 65,536 points at 1024². The
point count is independently cooked and checked outside timing; the actual
owner's function captures one `sop/with_attr` source. Static/changing origin
also changes Cd; the live pixel bias forces a completed producer every frame.
P/Cd reduce to uniforms, so these fixtures require no warm captured-array upload.

Each cell uses a fresh Measured-policy route probe, independent CPU whole cooks
at domains 1/8 (seven warm trials), then an actual eight-domain owner under
Qualification for seven 200-frame producer, consumer and combined trials after
ten warmups. Each trial uses distinct frame IDs and identical `t=j/200` values.
Completed producer timing includes owner resolution, source preflight, cook/
flatten work when needed, uniform preparation, native dispatch/status checks,
image conversion/copy and publication. Hashing and explicit readbacks are
outside producer timing; snapshot rows record their own timing. No attribution
interval is deducted. The uncaptured 1024² rerun retains the old one-domain GPU
owners and independent CPU domains 1/8.

```sh
_build/default/tools/check.exe @check tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-captures.csv 2> specification/performance/f-image-map-captures-counters.csv
_build/default/tools/bench_workspace_lower.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-recheck.csv 2> specification/performance/f-image-map-uncaptured-recheck-counters.csv
```

Both runs exit 0. Medians of seven trials, milliseconds and bytes/frame:

| Source | Points | Image | CPU8 whole cook | GPU producer | Consumer | Combined | Producer bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Static P/Cd | 1,024 | 512² | 4.804134 | 1.387216 | 0.377904 | 2.329525 | 2,500,473 |
| Static P/Cd | 1,024 | 1024² | 16.782045 | 2.967625 | 0.627635 | 4.177616 | 2,500,473 |
| Static P/Cd | 1,024 | 2048² | 58.345079 | 6.911695 | 1.635680 | 9.134560 | 2,500,473 |
| Changing P/Cd | 1,024 | 512² | 7.174015 | 1.623709 | 0.358710 | 1.963816 | 2,830,587 |
| Changing P/Cd | 1,024 | 1024² | 17.330885 | 3.094635 | 0.646920 | 4.423985 | 2,830,587 |
| Changing P/Cd | 1,024 | 2048² | 59.405088 | 7.262836 | 1.371676 | 9.441731 | 2,830,587 |
| Static P/Cd | 65,536 | 1024² | 65.782070 | 45.126491 | 0.614245 | 46.771590 | 156,297,081 |
| Changing P/Cd | 65,536 | 1024² | 66.111088 | 48.500581 | 0.610460 | 50.755105 | 169,767,276 |

At 1024² the CPU1 medians are 73.004007/73.645115 ms for the small static/
changing sources and 121.666908/119.116783 ms for the large ones. CPU1/8 hashes
match at every trial. All 24 full capture snapshots (times 0/.5 and resized
1025×1024 or corresponding size) have maximum channel difference 0 and no
differing channels/pixels. Separate channel checks prove the geometry update:
only blue changes with a static source, while red, green and blue change with
a changing source.

The 352 data rows retain cold owner/CPU/probe, all warm trials, explicit reads,
resize/replan and teardown. The 448 counter rows keep Host and capture records
separate. Every warm producer/combined trial executes 200 mandatory status
reads and generations, with no runner/pipeline/sink/buffer/texture creation,
input upload, output readback, source image readback or stored CPU image bytes.
Consumer-only trials perform none of the producer work. Static sources perform
zero new materializer cooks/flattens; changing sources perform 200/400 per
200-frame producer trial. One metadata/data record remains within 64 MiB.
Readback-only verification does not materialize or flatten again. Replan rebuilds
the source, and teardown balances resources and clears capture occupancy.

Allocation is independent of pixel size at fixed source count, while it scales
substantially with source points. The 65,536-point static producer still costs
45 ms with no source cook or flatten. This is evidence of unfinished producer
work; it does not identify the expensive phase without attribution. Both large
source cases exceed the explicit 40 ms CPU8 and 5 ms GPU limits. Astra reviewed
all 440 result rows and 168 warm Host/capture rows of each kind. Verdict:
**small-source 1024² capture cells pass; large-source cells fail**. Pixel-size
allocation independence passes at fixed source count. Changing large-source
allocations have small trial variation; the table records medians. Diagnostic
attribution remains required; this baseline has no accepted optimization.

The uncaptured regression has 88 data and 56 counter rows. CPU8/GPU medians are
13.716936/1.663125 ms (gradient) and 12.020111/1.633930 ms (live lexical capture).
Producer allocation is 33,561/32,433 B/frame; consumer allocation is 33,073.
All six independent complete parity comparisons have maximum difference 0.
Resource/upload/readback and close assertions pass. These reruns preserve the
earlier uncaptured timing gates; Astra accepts both CPU/GPU gate checks without
claiming a timing improvement from the small baseline differences.
The baseline CSVs remain checked in before any subsequent producer change.
Focused benchmark build and pre-commit shipping pass (exit 0;
`/tmp/rays-f-image-map-captures-build.log`,
`/tmp/rays-f-image-map-captures-baseline-ship.log`).

## F2.2 large-source uniform attribution (2026-10-09)

Same Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. Builds,
tests and other agents were idle during diagnostics. Starting from `4d5f3959`,
temporary `Phase_timer` probes aggregate bounded phase names/uniform indices
on the initial domain, preserve exclusive existing timers and add inclusive
nested measurements. A fake-clock regression checks inclusive/exclusive
nesting and exception restoration. No per-frame printing or in-trial GC
snapshot occurs. Each trial prints aggregated rows afterward.

Static/changing 65,536-point sources at 1024² and one uncaptured gradient
control run seven 200-frame producer trials after ten warmups. Independent
CPU1/8 whole cooks preserve the byte oracle; seven CPU8 caller samples are
also recorded. Consumer/combined timing is omitted in this diagnostic matrix;
full native parity, resize/replan, counter and teardown checks remain. Every
CPU8 sample explicitly labels worker internals unobserved, including samples
with initial-domain uniform subwork. No CPU remainder is inferred by
subtracting incomplete worker coverage.

The reproducible temporary patch is
`specification/performance/f-image-map-capture-attribution.patch`. Apply it to
a checkout of `4d5f3959`, then run:

```sh
_build/default/tools/check.exe @check lib/flow/test_phase_timer.exe tools/bench_workspace_lower.exe
_build/default/lib/flow/test_phase_timer.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-capture-attribution-whole.csv 2> specification/performance/f-image-map-capture-attribution-counters.csv
```

The patched harness writes aggregated phases separately to
`specification/performance/f-image-map-capture-attribution.csv`. Build,
fake-clock check and diagnostic run exit 0. All eight modified product/tool/
test files are restored byte for byte afterward. The patch is evidence only;
no probe or new timer API remains in shipping code.

Medians of seven GPU trials, inclusive milliseconds/frame:

| Initial-domain phase | Static 65,536 | Changing 65,536 | Gradient control | Calls/200-frame trial |
|---|---:|---:|---:|---:|
| Whole producer | 42.957189 | 45.413494 | 1.544915 | 1 |
| Owner arguments | 0.000981 | 0.001097 | 0.000598 | 400 |
| Source preflight | 0.008935 | 0.041260 | — | 400 |
| Packed preparation | 41.087186 | 43.220823 | 0.006000 | 200 |
| Source-array evaluation | 0.002692 | 0.003620 | 0.001914 | 200 |
| Uniform 0 | 20.531909 | 22.892056 | 0.001657 | 200 |
| Uniform 1 | 20.546052 | 20.197668 | — | 200 |
| Uniform 2 | 0.001742 | 0.001712 | — | 200 |
| Materialization | — | 2.177452 | — | 200 changing |
| Attribute flatten | — | 0.457065 | — | 400 changing |
| Run packing/upload | 0.005523 | 0.008280 | 0.001692 | 200 |
| Run encoding/completion/status | 1.032089 | 1.272550 | 0.718323 | 200 |
| Sink conversion/copy | 0.803688 | 0.781459 | 0.803946 | 200 |
| Runtime publication | 0.002066 | 0.002794 | 0.000995 | 200 |

Materialization and flattening are nested inside changing uniform evaluation,
and uniforms are nested inside Packed preparation. These inclusive medians
overlap; summing them would count work twice. Source preflight is called twice
because the harness requests Image and Texture. Static counters confirm no
materializer cook or flatten, while changing counters confirm 200/400.

CPU8 caller medians are 61.739922 ms static, 58.990002 ms changing and
12.320042 ms gradient. Observed initial-domain CPU uniforms 0/1 take about
21 ms each in captured cases; worker internals remain unobserved. Instrumented
whole-row allocations are 156,305,812 B/frame static, 169,779,576 B/frame
changing and 38,894 B/frame gradient. These include probe overhead and are
diagnostic, not replacements for baseline allocations or timing gates.

The phase CSV has 378 rows, whole CSV 90 rows and counter CSV 71 rows, plus
their headers. All nine full native comparisons have maximum channel/pixel
difference 0, CPU1/8 bytes match, and reuse/bounds/resize/close assertions pass.
The GPU evidence identifies captured-uniform reference evaluation as the main
cost, with geometry update nested within it. Astra accepts the attribution and
requires one shared uniform-evaluation helper for CPU force/GPU prepare using
the existing evaluator execution hook. Successful packed subterms execute;
compile refusals preserve reference evaluation. Scalar surrounding expressions
stay on the reference path. The actual `(reduce + ...)` also needs narrow
canonical callable specialization: resolve `+` in the actual operation
environment, require packed Binary Add, and retain the existing typed ordered
accumulator behavior, seed and empty-array rules. No name-only recognition,
reassociation or cross-frame cache is allowed.

The required focused matrix covers the canonical callable and explicit lambda,
Vec3 and cancellation-sensitive multi-block floats including signed zero,
changing captures, exact domains 1/8, empty/unsupported/error/nonfinite paths,
state rollback and a custom same-name operation. It must observe packed
execution, since output parity alone would also pass before the change.
After implementation, distinct after CSVs must repeat the unchanged eight-cell
and uncaptured regression matrices. Further optimization requires new
attribution if those still fail. The original failing baseline remains intact;
no optimization or overall captured-source acceptance is claimed here.

Restored-code focused checks (`@check`, `@lib/flow_ir/runtest`, timer executable
and benchmark build), restored timer execution and pre-commit shipping pass
(exit 0; `/tmp/rays-f-image-capture-attribution-restored.log`,
`/tmp/rays-f-image-capture-attribution-ship.log`).

## F2.2 shared packed uniform preparation (2026-10-09)

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. Astra's
attribution design is implemented in the common Packed uniform path, shared by
CPU force and GPU prepare. One evaluator context forces the complete immutable
uniform list using the existing numeric execution hook. Successful packed
subterms execute with the same state/live/element bindings/resolver, fusion,
dynamic settings and cardinality proof; compiler refusals return to reference
evaluation. Surrounding scalar expressions stay on the reference walker.
Small subexpressions compile per preparation, with no cross-frame cache.

The actual authored `(reduce + ...)` receives narrow canonical callable
support. `Op.find` uses the residual's captured operation environment and
requires the existing Binary Add capability. The compiler builds the same
typed accumulator/item addition as an explicit lambda and retains ordered
accumulation, seed/empty-input rules and reference diagnostic fallback. Other
named callables remain interpreted. No accumulator hot-loop change, reduction
reassociation or new GPU operation is included.

The new focused matrix compares full CPU output bytes and prepared uniform bits
at domains 1/8 over empty and 32,769-element sources and three changing live
inputs. It covers canonical addition and equivalent lambdas for float/Vec3,
multi-block cancellation and signed zero, unsupported min, and an unchecked
same-name custom declaration to exercise the compiler's independent guard.
Existing measurement callbacks prove that both CPU force and GPU prepare run
the supported uniform reductions packed; the unsupported/custom forms do not.
Integer 0 seeds retain reference fallback, matching the exact scalar value
constructor (Int for empty input, Float for nonempty float input). A resolver
advances a real fold before an overflow error: both callers return the original
reference diagnostic, restore the state and subsequently recover. Input arrays
remain unchanged. Private evaluator `compiled` control and GPU preparation's
optional measurement callback are the two reviewed/promoted manifest changes.

Focused Flow/IR, benchmark/API build, actual-owner CPU and native tests pass:

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest
_build/default/tools/check.exe @tools/api_manifest/runtest tools/bench_workspace_lower.exe test/test_workspace_images.exe test/test_workspace_images_native.exe
(cd _build/default/test && ./test_workspace_images.exe)
(cd _build/default/test && ./test_workspace_images_native.exe)
```

The benchmark source remains unchanged from `4d5f3959`. After all builds,
tests and other agents became idle, the full eight capture cells and separate
uncaptured 1024² control repeat the same seven CPU1/8 cooks and seven 200-frame
completed GPU/consumer/combined trials after ten warmups:

```sh
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-captures-after.csv 2> specification/performance/f-image-map-captures-after-counters.csv
_build/default/tools/bench_workspace_lower.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-recheck-after.csv 2> specification/performance/f-image-map-uncaptured-recheck-after-counters.csv
```

Both runs exit 0. Seven-trial medians, milliseconds and bytes/frame:

| Source | Points | Image | CPU8 whole cook | GPU producer | Consumer | Combined | Producer bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Static P/Cd | 1,024 | 512² | 5.348921 | 0.832685 | 0.379596 | 1.269675 | 351,305 |
| Static P/Cd | 1,024 | 1024² | 15.635967 | 2.016746 | 0.624655 | 3.119844 | 351,305 |
| Static P/Cd | 1,024 | 2048² | 57.089806 | 5.426325 | 1.640074 | 7.443714 | 351,305 |
| Changing P/Cd | 1,024 | 512² | 5.202055 | 0.979425 | 0.377525 | 1.430690 | 681,579 |
| Changing P/Cd | 1,024 | 1024² | 15.792131 | 2.253026 | 0.622720 | 3.420510 | 681,579 |
| Changing P/Cd | 1,024 | 2048² | 57.624102 | 5.767635 | 1.660985 | 7.909645 | 681,579 |
| Static P/Cd | 65,536 | 1024² | 25.685072 | 9.757650 | 0.631931 | 10.422729 | 7,052,921 |
| Changing P/Cd | 65,536 | 1024² | 25.298119 | 12.211875 | 0.621525 | 12.921420 | 20,522,722 |

Large-source CPU8 before/after medians are 65.782070→25.685072 ms static
and 66.111088→25.298119 ms changing; GPU medians are
45.126491→9.757650 and 48.500581→12.211875 ms. Static large allocation falls
from 156,297,081 to 7,052,921 B/frame. The uncaptured CPU8/GPU medians are
12.253046/1.609435 ms gradient and 11.778116/1.636395 ms live; allocations
33,721/32,593 B/frame are 160 B above the immediately preceding controls.
Pixel-size allocation independence remains exact at fixed 1,024-point count.

All 440 after data rows are retained with resource/capture counters. All 30
full native parity comparisons have maximum channel difference 0 and no
differing channels/pixels; independent CPU1/8 hashes match. Warm geometry
reuse/update counts, status reads/generations, no warm resource creation/
uploads/readbacks, CPU-storage exclusion, resize/replan and teardown pass.
Astra verified the raw rows and all 210 warm Host rows: “The shared preparation
correction is worth retaining.” **CPU gates pass for every measured 1024²
fixture. GPU gates pass for small sources and controls but still fail for both
large sources.** This is a retained correction, not overall F2.2 completion.

Before another optimization, Astra requires new temporary attribution of
uniform preparation/compilation/execution, then seed/source/scratch setup and
the complete ordered chunk traversal. Existing source/materializer/flatten,
dispatch/conversion/publication probes remain. Inclusive phases must not be
summed twice, and worker CPU coverage remains explicitly unobserved. Broad
F5 validation passes (exit 0; `/tmp/rays-f-image-capture-uniform-full.log`),
including the two complete workspace sweeps, native GPU/editor/prepared commands,
workspace pixels, gallery float32, oversized capture and runtime qualification,
and PXUI parity. Actual display is 1×; 2× goldens remain unqualified. Pre-commit
shipping passes (exit 0; `/tmp/rays-f-image-capture-uniform-ship.log`).

## F2.2 ordered uniform traversal attribution (2026-10-09)

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. This second
temporary diagnostic measures the committed shared-uniform implementation at
`64c84473`, before the accumulator write trial below. Astra approved reusing
the original inclusive, domain-local timer and outer ownership/GPU probes.
The current shared helper adds bounded authored-site intervals for complete
uniform preparation, callback compilation/execution, seed evaluation, source
arrays, output/accumulator setup and complete ordered traversal. Traversal
includes per-chunk scratch allocation; it does not isolate instruction work.
There are no instruction, element, block or chunk clocks. Inclusive phases
overlap and must not be summed twice. CPU worker internals remain unobserved.

The reproducible eight-file temporary patch is
`specification/performance/f-image-map-capture-attribution-after.patch`, applied
to `64c84473`. Focused Flow/IR, timer and benchmark checks passed. No other
builds, tests or agents ran during timing. The harness retains static/changing
65,536-point 1024² images and the uncaptured gradient, seven CPU8 caller
samples, seven ×200 completed GPU producer frames after ten warmups, and
the existing correctness/resize/replan/ownership checks:

```sh
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-capture-attribution-after-whole.csv 2> specification/performance/f-image-map-capture-attribution-after-counters.csv
```

The harness separately writes
`specification/performance/f-image-map-capture-attribution-after.csv`.
Seven-trial medians, inclusive milliseconds per completed GPU frame:

| Interval | Static P/Cd | Changing P/Cd |
|---|---:|---:|
| Whole producer | 10.058135 | 12.391540 |
| Packed preparation | 8.018458 | 10.242362 |
| Complete uniform preparation | 8.013679 | 10.236350 |
| P compile | 0.003283 | 0.003169 |
| Cd compile | 0.002608 | 0.005037 |
| P execute | 4.002240 | 6.043152 |
| Cd execute | 3.995267 | 4.173237 |
| P ordered traversal, including scratch | 3.993431 | 3.943491 |
| Cd ordered traversal, including scratch | 3.987672 | 3.972787 |
| P source preparation | 0.001664 | 2.092278 |
| Cd source preparation | 0.000856 | 0.190697 |
| Source preflight (two calls/frame) | 0.006582 | 0.039635 |
| Materialization (nested in P source) | no warm calls | 1.896484 |
| Flatten (two calls/frame, nested) | no warm calls | 0.375942 |
| Completed Run execution | 1.246672 | 1.286684 |
| Sink conversion | 0.752336 | 0.770530 |
| Runtime publication | 0.001128 | 0.002408 |

CPU8 whole-caller medians are 25.202990/24.912834 ms static/changing and
12.874126 ms gradient; CPU worker phases are not qualified by these clocks.
The diagnostic exits 0, preserving 896 phase rows, 90 whole rows, all nine
native parity comparisons at zero difference and all counter assertions.
Production files were restored byte-for-byte, verified against HEAD, then
`@check @lib/flow/runtest @lib/flow_ir/runtest` and the benchmark build passed
(exit 0; `/tmp/rays-f-capture-attribution-restored-build.log`).

Astra verified the attribution: the two ordered reduction traversals account
for roughly 8 ms/frame, while compilation takes only a few microseconds.
Its next approved trial changes only the `Accumulator` instruction's generic
`Array.fill` to an indexed float-array write loop. This allows the compiler
to avoid boxing the changing accumulator for the generic fill; every other
instruction, scheduling decision, reduction order and finite check remains.
No timing gate is established by attribution alone.

## F2.2 indexed accumulator scratch writes (2026-10-09)

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. The complete
product diff changes only `Packed.force`'s `Accumulator` instruction from
generic `Array.fill` to indexed writes. Existing full-byte ordered-uniform,
fold and scan tests cover every scan output, scalar/vector accumulators,
multi-block cancellation, signed zero, changing inputs, empty inputs,
reference errors, rollback and domains 1/8. Focused checks and benchmark build
pass (exit 0; `/tmp/rays-f-image-accumulator-focused.log`).

```sh
_build/default/tools/check.exe @check @lib/flow_ir/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-captures-accumulator-after.csv 2> specification/performance/f-image-map-captures-accumulator-after-counters.csv
_build/default/tools/bench_workspace_lower.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-recheck-accumulator-after.csv 2> specification/performance/f-image-map-uncaptured-recheck-accumulator-after-counters.csv
```

The tool remains unchanged from `4d5f3959`. Before evidence is clean
`64c84473` and its `f-image-map-captures-after*`/uncaptured after rows.
After timing runs alone, with no builds, tests or other agents: seven CPU1/8
cooks, seven ×200 completed producer/consumer/combined frames, ten warmups.
Both commands exit 0. Seven-trial medians, milliseconds and bytes/frame:

| Source | Points | Image | CPU8 whole cook | GPU producer | Consumer | Combined | Producer bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Static P/Cd | 1,024 | 512² | 4.184961 | 0.785331 | 0.441824 | 1.234530 | 253,001 |
| Static P/Cd | 1,024 | 1024² | 15.170097 | 1.807555 | 0.681751 | 2.964259 | 253,001 |
| Static P/Cd | 1,024 | 2048² | 55.599928 | 5.025400 | 1.550926 | 7.137785 | 253,001 |
| Changing P/Cd | 1,024 | 512² | 4.596233 | 0.905244 | 0.430266 | 1.374426 | 583,275 |
| Changing P/Cd | 1,024 | 1024² | 15.722990 | 1.981795 | 0.596865 | 2.938485 | 583,275 |
| Changing P/Cd | 1,024 | 2048² | 56.645870 | 4.883935 | 1.283960 | 6.801164 | 583,275 |
| Static P/Cd | 65,536 | 1024² | 23.262978 | 7.562215 | 0.673035 | 8.017770 | 761,465 |
| Changing P/Cd | 65,536 | 1024² | 22.775888 | 9.956585 | 0.680350 | 10.638089 | 14,231,239 |

Large GPU medians improve 9.757650→7.562215 ms static and
12.211875→9.956585 ms changing. Static large allocation falls exactly
6,291,456 B/frame (two Vec3 reductions ×65,536 elements ×16-byte float
box), from 7,052,921 to 761,465 B/frame. Fixed-source small allocations fall
98,304 B/frame and remain identical at all pixel sizes. Uncaptured CPU8/GPU
medians are 12.090921/1.527954 ms gradient and 11.873960/1.653045 ms live;
33,721/32,593 B allocations are unchanged. The measurements do not establish
a control timing improvement.

All 440 rows are retained. All 30 native parity comparisons have zero channel
or pixel differences, and independent CPU1/8 hashes match. Warm cook/flatten,
resource/generation/status, upload/readback, resize/replan and teardown
assertions pass. Astra reviewed the raw rows: **“Retain the indexed loop.”**
CPU gates and small/control GPU gates pass; **both large-source GPU gates
still fail**. No tolerance, fixture or gate changed.

The next approved action is a third temporary attribution using the same
probes while retaining the indexed loop, plus both reduction instruction
listings/output slots/widths collected through the existing callback outside
timing. No instruction clocks/counters or further hot-loop change are approved.

The full F5 matrix passes (exit 0; `/tmp/rays-f-image-accumulator-full.log`):
`@all @runtest @smoke`, Rays/FlowGPU/editor/prepared-command/test native aliases,
oversized capture and runtime qualification, all workspace pixel aliases,
gallery float32 and PXUI parity. Both workspace sweeps cover 38 standard files,
two custom-catalog executables and 13 fixtures at four times/domains 1/8.
Actual display is 1×; 2× goldens remain unqualified. Pre-commit shipping passes
(exit 0; `/tmp/rays-f-image-accumulator-ship.log`).

## F2.2 remaining ordered traversal attribution (2026-10-09)

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. Astra approved
the third temporary diagnostic on `0f070d3f`, preserving the indexed writes.
It reuses the second probes, with identical inclusive/initial-domain coverage,
static/changing 65,536-point 1024² images, gradient control, seven CPU8 caller
samples and seven ×200 completed producer frames after ten warmups. Scratch
allocation remains inside the complete traversal interval. Worker internals
remain unobserved, and inclusive phases must not be summed twice.

The only added diagnostic captures the actual two reduction programs through
the existing preparation measurement callback. A file-local collector retains
at most those two references during the first GPU preparation, asserts that
both were captured and disarms before warmups/trials. Its zero clock avoids
new clocks inside execution. An at-exit writer formats the program listings
after all measurements; no per-instruction clocks or counters are added.
The first preparation is instrumented and is not timing-gate evidence.
The environment variable is set only for the isolated diagnostic command:

```sh
RAYS_IMAGE_REDUCTION_LISTING=specification/performance/f-image-map-capture-attribution-accumulator-programs.txt _build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-capture-attribution-accumulator-whole.csv 2> specification/performance/f-image-map-capture-attribution-accumulator-counters.csv
```

The harness additionally writes `f-image-map-capture-attribution-accumulator.csv`.
All five raw/patch/listing artifacts share that prefix under
`specification/performance/`. The eight-file patch applies to `0f070d3f`;
production files were restored byte-for-byte against HEAD after timing.
The focused diagnostic build and run exit 0, with nine zero-difference parity
comparisons and all resource/capture/resize/close assertions passing.
No other builds, tests or agents ran during the measurements.

Seven-trial medians, inclusive milliseconds per completed GPU producer frame:

| Interval | Static P/Cd | Changing P/Cd |
|---|---:|---:|
| Whole producer | 7.579745 | 9.980655 |
| Packed preparation | 5.583771 | 7.853714 |
| P ordered traversal, including scratch | 2.772475 | 2.724782 |
| Cd ordered traversal, including scratch | 2.779611 | 2.753351 |
| P execute | 2.780430 | 4.876285 |
| Cd execute | 2.786957 | 2.955486 |
| P compile | 0.003195 | 0.002995 |
| Cd compile | 0.002447 | 0.004680 |
| P source preparation | 0.001732 | 2.139674 |
| Cd source preparation | 0.001284 | 0.187166 |
| Materialization (nested in P source) | no warm calls | 1.948781 |
| Flatten (nested, two calls/frame) | no warm calls | 0.368427 |
| Completed Run execution | 1.233052 | 1.284670 |
| Sink conversion | 0.753514 | 0.776274 |

CPU8 whole-caller medians are 22.897005 ms static, 22.413015 ms changing
and 11.982918 ms gradient. Both captured programs are exactly nine slots:
three independent Input registers, three dependent Accumulator registers and
three dependent Binary Add registers, with output slots 6/7/8 and source
width 3. The existing interpreter scans all nine slots per accumulator step.
This preserves evidence of the remaining traversal cost; it does not approve
a new specialization or close the failing large GPU gates.

Astra approved the capture wiring: “Approved for this diagnostic.” Restored
production `@check @lib/flow/runtest @lib/flow_ir/runtest` and benchmark build
pass (exit 0; `/tmp/rays-f-capture-attribution-accumulator-restored.log`).
Pre-commit shipping passes (exit 0;
`/tmp/rays-f-capture-attribution-accumulator-ship.log`). The complete native
matrix already passed for the unchanged product at `0f070d3f`; this checkpoint
adds evidence and documentation only, with no remaining production probes.

Astra's verdict is **“Attribution accepted.”** Its next approved design is a
local fast path for the exact observed component-wise ordered-add pattern.
Before traversal, one boolean must prove non-collecting Accumulate, one zipped
input of result width 1–4, exactly `3*width` slots in the observed
Input/Accumulator/Binary Add order, matching dependencies and output slots
`2*width+k`. No new instruction, cache field or scheduling change is allowed.
For matching programs the independent input-block execution remains, while
the existing component loop adds the current accumulator directly to its
input scratch register, then performs the existing finite check and assignment.
All seed/skip/source/chunk/empty/fallback behavior remains. Scans, reversed
operands, broadcasting and other trees stay on the current interpreter.

Before implementation, the decisive regression must pin matched scalar and
Vec2/3/4 patterns and reject the nearby `(+ (* a 0.99) x)` form. Full reference
results at domains 1/8 must cover cancellation, signed zero, empty/changing
inputs, nonfinite rollback and integer-seed refusal. After focused checks,
the unchanged eight-cell/control matrices must repeat in isolation against
`0f070d3f`'s uninstrumented 7.562215/9.956585 ms GPU baselines, preserving all
parity/counter/resize/ownership checks. This is an approved design, not an
implemented fast path or measured gate verdict.

## F2.2 proved ordered-add dispatch bypass (2026-10-09)

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. The approved
local fast path recognizes only a non-collecting Accumulate, result width
1–4, exactly one Zip source of the same width, and the complete proved
Input/Accumulator/Binary Add layout, output slots and dependency flags. One
boolean is computed before traversal. Independent input-block loading remains;
matching programs bypass per-element dependent dispatch and add the current
accumulator directly to its input scratch register before the original finite
check and accumulator assignment. Source/seed/skip/chunk/empty/fallback rules
remain. Other programs retain generic packed execution.

Astra approved one shared pure `Packed.Private.ordered_add` predicate for
execution and tests. The single intentional private API manifest entry was
reviewed/promoted. Review caught that the existing `zipped` helper also accepts
single-source Product loops; the final predicate explicitly requires Zip.
The new exact-layout Product-fold regression has the same nine instructions
as the supported Vec3 reduction but is rejected by the predicate.

The expanded uniform matrix checks the predicate through existing measurement
callbacks while comparing full CPU bytes and prepared uniform bits at domains
1/8. It covers canonical addition at all four widths, equivalent lambdas,
multi-block cancellation and signed zero, empty/changing sources, a rejected
nearby recurrence and reversed addition, unsupported/custom operators and the
integer-seed reference path. Full-byte scan and broadcast-fold checks prove
those fallbacks; overflow after a resolver advances a real state fold preserves
the reference diagnostic and rolls back state before recovery. Focused checks
and the benchmark/API build pass (exit 0;
`/tmp/rays-f-image-ordered-add-focused.log`).

```sh
_build/default/tools/check.exe @check @lib/flow_ir/runtest @tools/api_manifest/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-captures-ordered-add-after.csv 2> specification/performance/f-image-map-captures-ordered-add-after-counters.csv
_build/default/tools/bench_workspace_lower.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-recheck-ordered-add-after.csv 2> specification/performance/f-image-map-uncaptured-recheck-ordered-add-after-counters.csv
```

The tool remains unchanged from `4d5f3959`. Before evidence is the
uninstrumented `0f070d3f` accumulator after files. After commands run alone,
with no builds/tests/other agents: seven CPU1/8 cooks and seven ×200 completed
GPU/consumer/combined trials after ten warmups. Both exit 0. Seven-trial
medians, milliseconds and bytes/frame:

| Source | Points | Image | CPU8 whole cook | GPU producer | Consumer | Combined | Producer bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Static P/Cd | 1,024 | 512² | 4.748106 | 0.752275 | 0.380750 | 1.170850 | 253,529 |
| Static P/Cd | 1,024 | 1024² | 15.413046 | 1.788894 | 0.629770 | 2.821105 | 253,529 |
| Static P/Cd | 1,024 | 2048² | 58.767080 | 5.019115 | 1.581655 | 6.954761 | 253,529 |
| Changing P/Cd | 1,024 | 512² | 5.017996 | 0.908440 | 0.377215 | 1.312500 | 583,811 |
| Changing P/Cd | 1,024 | 1024² | 15.599012 | 1.998075 | 0.630361 | 3.082165 | 583,811 |
| Changing P/Cd | 1,024 | 2048² | 57.220936 | 5.292414 | 1.662925 | 7.479236 | 583,811 |
| Static P/Cd | 65,536 | 1024² | 19.203901 | 5.443920 | 0.638815 | 6.611080 | 761,993 |
| Changing P/Cd | 65,536 | 1024² | 19.567013 | 6.654539 | 0.567360 | 7.319130 | 14,232,181 |

Large CPU8 medians improve 23.262978→19.203901 ms static and
22.775888→19.567013 ms changing; GPU medians improve 7.562215→5.443920
and 9.956585→6.654539 ms. The bounded recognizer adds 528 B/frame to static
producer allocations; fixed-source allocation remains identical at all pixel
sizes. Uncaptured CPU8/GPU medians are 12.243986/1.596760 ms gradient and
11.686087/1.625144 ms live; 33,721/32,593 B allocations are unchanged.
No control timing improvement is claimed.

All 440 raw rows are retained. All 30 native parity comparisons have zero
channel/pixel differences and CPU1/8 hashes match. Warm source cook/flatten,
status/generation, resources/uploads/readbacks, CPU storage, resize/replan
and teardown assertions pass. Astra: **“Retain the change.”** CPU gates and
small/control GPU cases pass; **both large GPU cases still miss <5 ms**.
This is a retained optimization, not completed F2.2.

Astra's next approved trial keeps every recognition restriction and adds
`skip=[]`. It branches once per chunk: matching programs read their single
interleaved input directly in ascending element/component order, perform the
same finite-checked addition and accumulator assignment, and allocate no
scratch/index/noise/table storage. Generic chunks regain their original
unconditional dependent execution and output lookup. Seed, source, ordered
chunk, empty and transactional fallback behavior remain. No unrolling,
parallel reduction, reassociation or result cache is allowed.

The required regression extends one Vec3 case to counts 1, 1023, 1024,
1025, 16383, 16384 and 16385, and adds nonfinite failure after a chunk boundary
with exact reference diagnostics and state rollback. All current width,
cancellation/signed-zero, empty/changing and rejected-pattern tests remain.
The unchanged capture/control protocol must produce separate direct-input
after files. If either large GPU median still misses <5 ms, obtain fresh
attribution before broadening. That direct-input trial is not yet implemented.

The complete F5 native/pixel matrix passes (exit 0;
`/tmp/rays-f-image-ordered-add-full.log`), including both workspace sweeps,
native GPU/editor/prepared-command tests, oversized capture and runtime
qualification, all workspace pixel aliases, gallery float32 and PXUI parity.
Actual display is 1×; 2× goldens remain unqualified.

Pre-commit shipping passes (exit 0; `/tmp/rays-f-image-ordered-add-ship.log`).

## F2.2 direct-input ordered accumulation (2026-10-09)

Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev, actual display 1×. The approved
pattern adds a no-skip proof and branches once per ordered chunk. Matching
reductions read their single input in ascending element/component order,
perform the same addition, finite check and accumulator write, and allocate
no chunk scratch, index array, noise scratch or instruction table. Generic
chunks regain their original unconditional dependent execution and output
lookup. Source/seed preparation, chunk ordering, empty result construction and
transactional reference fallback remain unchanged. No unrolling, reassociation,
parallel reduction, result cache or new instruction is added.

The existing all-width, cancellation/signed-zero, empty/changing-input and
fallback matrix remains. One canonical Vec3 case additionally covers counts
1, 1023, 1024, 1025, 16383, 16384 and 16385. The overflow/rollback matrix
retains the two-element case and adds 16,385 elements whose last two values
overflow across the chunk boundary. Both CPU force and GPU preparation return
the original reference diagnostic, retain input bytes, restore state after a
resolver advanced a real fold, and recover in the same frame, at domains 1/8.
Focused checks/build pass (exit 0; `/tmp/rays-f-image-direct-input-focused.log`).
Astra reviewed the actual code and bounds before timing: “Approved for isolated
timing.”

```sh
_build/default/tools/check.exe @check @lib/flow_ir/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-captures-direct-input-after.csv 2> specification/performance/f-image-map-captures-direct-input-after-counters.csv
_build/default/tools/bench_workspace_lower.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-recheck-direct-input-after.csv 2> specification/performance/f-image-map-uncaptured-recheck-direct-input-after-counters.csv
```

The unchanged benchmark compares against `14415764` and its ordered-add after
files, with seven CPU1/8 cooks and seven ×200 completed GPU/consumer/combined
trials after ten warmups. Commands run alone, with no builds/tests/other agents,
and both exit 0. Seven-trial medians, milliseconds and bytes/frame:

| Source | Points | Image | CPU8 whole cook | GPU producer | Consumer | Combined | Producer bytes |
|---|---:|---:|---:|---:|---:|---:|---:|
| Static P/Cd | 1,024 | 512² | 4.099131 | 0.654271 | 0.439640 | 1.108930 | 89,161 |
| Static P/Cd | 1,024 | 1024² | 15.037775 | 1.593555 | 0.673085 | 2.586200 | 89,161 |
| Static P/Cd | 1,024 | 2048² | 55.053949 | 4.480320 | 1.553985 | 6.357424 | 89,161 |
| Changing P/Cd | 1,024 | 512² | 4.324198 | 0.765110 | 0.438120 | 1.230795 | 419,443 |
| Changing P/Cd | 1,024 | 1024² | 14.796972 | 1.776340 | 0.672334 | 2.902880 | 419,443 |
| Changing P/Cd | 1,024 | 2048² | 54.298162 | 4.969710 | 1.512315 | 7.029974 | 419,443 |
| Static P/Cd | 65,536 | 1024² | 17.266035 | 3.510880 | 0.675430 | 5.172775 | 89,161 |
| Changing P/Cd | 65,536 | 1024² | 18.228054 | 6.159385 | 0.626094 | 6.924624 | 13,558,975 |

Large CPU8 medians improve 19.203901→17.266035 ms static and
19.567013→18.228054 ms changing; GPU medians improve 5.443920→3.510880
and 6.654539→6.159385 ms. Static producer allocation is exactly 89,161
B/frame across every measured source/pixel size, eliminating the chunk-scratch
slope. Fixed-source changing allocation remains pixel-size independent.
Uncaptured CPU8/GPU medians are 12.129068/1.591871 ms gradient and
11.545897/1.574425 ms live; 33,721/32,593 B allocations are unchanged.
No control timing improvement is claimed.

All 440 raw rows, all 30 zero-difference native parity comparisons and all 210
warm Host-counter rows are retained; CPU1/8 hashes match. Source work, resource,
status/generation, upload/readback, resize/replan and teardown assertions pass.
Astra: **“Retain the direct-input path.”** All measured CPU8 gates pass.
The large static GPU gate **passes at 3.510880 ms**; the large changing case
**still fails at 6.159385 ms**. Smaller/control GPU cases pass. This does not
complete F2.2 or change any fixture, tolerance or gate.

## F2.2 direct-input source-refresh attribution (2026-10-09)

On the same machine/profile/display, Astra approved fresh attribution before
another optimization. The candidate above retains all product changes. The
eight-file patch adds only temporary probes, with no new instruction capture;
the previously inspected two nine-slot programs remain unchanged. Direct
traversal is labeled separately from generic traversal including scratch,
because matched chunks allocate none. Inclusive phases overlap and must not
be summed twice; CPU worker internals remain explicitly unobserved.

The isolated harness uses static/changing 65,536-point 1024² images plus the
gradient control, seven CPU8 caller samples and seven ×200 completed producer
frames after ten warmups, retaining correctness/ownership/resize checks:

```sh
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-capture-attribution-direct-input-whole.csv 2> specification/performance/f-image-map-capture-attribution-direct-input-counters.csv
```

It additionally writes `f-image-map-capture-attribution-direct-input.csv`.
The reproducible probe-only patch has the same prefix under
`specification/performance/`, applies to the candidate in this checkpoint and
passes `git apply --check` after restoration. The original candidate's Packed/
regression diff and all eight archived production files are preserved
byte-for-byte after removing the probes. Focused diagnostic build and run
exit 0; nine full native parity comparisons have zero differences and all
counters/assertions pass. No builds, tests or other agents run during timing.

Seven-trial medians, inclusive milliseconds per completed GPU producer frame:

| Interval | Static P/Cd | Changing P/Cd |
|---|---:|---:|
| Whole producer | 3.440310 | 6.123780 |
| Packed preparation | 1.652670 | 4.219518 |
| P direct traversal | 0.789125 | 0.584205 |
| Cd direct traversal | 0.790160 | 0.583329 |
| P source preparation | 0.003150 | 2.771025 |
| Cd source preparation | 0.002154 | 0.274242 |
| Materialization (nested in P source) | no warm calls | 2.491270 |
| Flatten (nested, two calls/frame) | no warm calls | 0.543628 |
| Cd construction packed-map traversal (nested in materialization) | no warm calls | 0.649028 |
| P compile | 0.007939 | 0.003650 |
| Cd compile | 0.004208 | 0.005255 |
| Source preflight (two calls/frame) | 0.010160 | 0.043579 |
| Completed Run execution | 0.894736 | 1.036061 |
| Sink conversion | 0.819508 | 0.810062 |

CPU8 whole-caller medians are 18.198013 ms static, 18.316984 ms changing
and 12.657166 ms gradient; worker phases remain unqualified. These diagnostic
numbers identify source refresh as material. They neither substitute for the
uninstrumented gates nor approve another optimization by themselves.

Astra's verdict: **“Attribution accepted.”** Source refresh explains the
remaining changing-source failure. Its next approved action is a targeted
diagnostic split, not an optimization: aggregate the materializer's existing
`Session.node_timings` by `sop/line`, `flow.with_attr` and `flow.capture`, without
changing Session timing; separately time Attribute_kernel.write validation,
interleaved-to-XYZ construction and attribute creation/installation; distinguish
P/Cd flattening while retaining the packed-map probe. Existing node timings
cover worker-executed node work and exclude upstream input cooking; missing
domain-local write probes remain unobserved. Reporting stays outside timed
frame loops, and node timings must not be summed with nested write/map phases.
Repeat the same isolated seven-trial cells and restore the temporary patch.

The inspection target is Attribute_kernel.write's three Array.init callbacks
and the node's Duplicate_input 0 policy. The new evidence must distinguish
storage construction, input preparation and geometry generation before any
change. No cache, dependency or ownership change is approved.

Restored production passes the full F5 native/pixel matrix (exit 0;
`/tmp/rays-f-image-direct-input-full.log`): `@all @runtest @smoke`, all listed
Rays/FlowGPU/editor/prepared-command/test native aliases, oversized capture
and runtime qualification, all workspace pixel aliases, gallery float32 and
PXUI parity. Both workspace sweeps cover 38 standard files, two custom-catalog
executables and 13 fixtures at four times/domains 1/8; the native sweep verifies
geometry/image/texture/drawing pixels. Actual display is 1×; 2× goldens remain
unqualified. No production probes remain.
Pre-commit shipping passes (exit 0; `/tmp/rays-f-image-direct-input-ship.log`).

## F2.2 source-refresh component attribution (2026-10-09)

Machine: Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev profile, actual 1× display.
Candidate: `d7e406b4`, unchanged direct-input product code. Astra approved
reusing existing Session node timings and splitting attribute writing and
flattening before another optimization. The nine-file probe-only patch is
`specification/performance/f-image-map-capture-attribution-source-refresh.patch`.
It adds no product algorithm or instruction. Session samples are collected once
immediately after each successful materializer cook, with exactly one expected
native operation (`line`, `flow.with_attr`, `flow.capture`) asserted. Native
`line` corresponds to Lisp `sop/line`. Node-own timings include worker execution
and exclude input cooks; parallel node durations may overlap. They do not
modify the Phase_timer nesting stack. An external-duration regression verifies
aggregation without subtracting these durations from parent exclusive phases.

Write probes preserve count checking, finite checking, storage construction and
installation order. Missing domain-local write samples remain blank and labeled
unobserved. P and Cd flattening are reported separately. Reporting occurs after
each timed loop, never in the producer's frame. No builds, tests or other agents
run during measurement. The isolated run uses static/changing 65,536-point
1024² images and the gradient control: seven CPU1/8 caller samples and seven
×200 completed GPU producer frames after ten warmups. CPU worker internals
remain unobserved; the GPU materializer's write probes are observed on the
initial domain in all seven changing-source trials.

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest @lib/flow_sop/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-capture-attribution-source-refresh-whole.csv 2> specification/performance/f-image-map-capture-attribution-source-refresh-counters.csv
```

The harness additionally writes `f-image-map-capture-attribution-source-refresh.csv`:
1,050 phase rows, 90 whole-caller rows and 71 counter rows (headers additional).
Nine full native pixel comparisons have zero maximum error/differing channels/
pixels. CPU1/8 hashes and all source-cache/materialization/flatten/resource/
resize/replan/close assertions pass. The diagnostic build and benchmark exit 0.
An initial premeasurement assertion identified the native operation spelling;
that attempt produced no measured rows. The corrected operation-set assertion
passes for all materializer cooks in the retained run.

Seven-trial medians in milliseconds per completed GPU producer frame:

| Interval and coverage | Static P/Cd | Changing P/Cd |
|---|---:|---:|
| Whole caller | 3.429029 | 6.248649 |
| Materialization, initial-domain inclusive | no warm calls | 2.432431 |
| `line`, node own across cook domains | no warm calls | 0.295147 |
| `flow.with_attr`, node own across cook domains | no warm calls | 2.128962 |
| `flow.capture`, node own across cook domains | no warm calls | 0.000290 |
| Attribute count/finite validation, nested | no warm calls | 0.189129 |
| Attribute XYZ storage construction, nested | no warm calls | 0.940881 |
| Attribute creation/installation, nested | no warm calls | 0.001158 |
| Cd packed-map traversal, nested | no warm calls | 0.641835 |
| Cd map source preparation, nested | no warm calls | 0.273716 |
| Cd map output setup, nested | no warm calls | 0.044911 |
| P flatten | no warm calls | 0.263529 |
| Cd flatten | no warm calls | 0.263864 |
| Packed preparation, inclusive | 1.658608 | 4.224846 |
| P ordered direct traversal | 0.794556 | 0.563650 |
| Cd ordered direct traversal | 0.794528 | 0.561979 |
| Completed GPU execution | 0.904018 | 1.080877 |
| Sink conversion | 0.808976 | 0.792496 |

CPU8 whole callers are 17.910004 ms static, 18.834829 ms changing and
12.658834 ms gradient. Gradient GPU producer is 1.533430 ms. Timings overlap:
node-own with_attr includes its map and write phases; materialization includes
node work; packed preparation includes materialization, flattening and reductions.
Do not sum overlapping inclusive intervals or interpret summed node times as
a wall-time remainder. The XYZ construction is a measured contributor, while
installation is small. These instrumented numbers do not establish the
uninstrumented gate or authorize an optimization by themselves.

All nine archived production files are restored byte-for-byte to the candidate;
the saved probe-only patch passes `git apply --check` after restoration. No
production probes remain. Astra: **“Attribution accepted.”** It approves a
narrow non-P write trial: allocate three zeroed float arrays and copy interleaved
XYZ values in one ascending loop, then use the same owned storage constructor
and installation. Count/finite validation stays before allocation; P behavior,
parallelism, caching, storage representation and Duplicate_input policy stay
unchanged. A regression must cover empty/multi-block/distinct XYZ/signed-zero,
domains 1/8, input ownership, count/nonfinite diagnostics and failed-write
immutability. Repeat the unchanged eight-cell capture matrix and 1024² controls
against the direct-input baseline. This design is not implemented in the
attribution checkpoint and makes no performance verdict.

Restored `@check`, Flow/IR/FlowSop focused tests and benchmark build pass (exit 0;
`/tmp/rays-f-image-source-refresh-restored-focused.log`).
Pre-commit shipping passes (exit 0; `/tmp/rays-f-image-source-refresh-ship.log`).
This diagnostic checkpoint changes no product behavior; full F5 native evidence
remains `/tmp/rays-f-image-direct-input-full.log`, on the actual 1× display.

## F2.2 direct XYZ attribute write (2026-10-09)

Machine: Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev profile, actual 1× display.
Baseline: `d7e406b4` direct-input product code, with diagnostic evidence committed
in `e2323f0a`. Astra's source-refresh attribution identified 0.940881 ms/frame
in non-P XYZ storage construction. Its approved trial replaces the three
Array.init callbacks with three zeroed float arrays and one ascending direct
interleaved-to-XYZ copy loop. Count/finite validation stays before allocation,
and the same owned storage constructor and attribute installation follow it.
P writes, parallelism, ownership, representation, caches and Duplicate_input
policy remain unchanged. Astra reviews and approves the production diff.

The focused regression cooks actual Attribute_kernel nodes through Session at
domains 1/8 with empty and 32,769-point arrays. It pins distinct XYZ and signed
zero by Int64 bits and complete geometry bytes, checks the input values and
original geometry stay unchanged, and mutates the caller's array after success
to confirm installed storage is owned. Wrong count retains E_ATTR_COUNT;
infinity retains E_NONFINITE, and failed writes leave original bytes unchanged.
The test passes against the original implementation first (exit 0;
`/tmp/rays-f-image-xyz-write-regression-before.log`), then the candidate with
`@check`, FlowSop tests and benchmark build (exit 0;
`/tmp/rays-f-image-xyz-write-focused.log`). No public API or manifest changes.

The benchmark code and fixtures are unchanged. Run alone, without builds,
tests or active agents: seven CPU samples at domains 1/8, seven ×200 completed
GPU producer/consumer/combined frames per cell after ten warmups. Capture GPU
owners use eight domains; uncaptured controls retain their established one-domain
GPU owner. CPU hash computation and explicit native readbacks stay outside the
warm producer timer. Cold preparation, route qualification, odd-width resize,
replan and close remain separate rows.

```sh
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-captures-xyz-write-after.csv 2> specification/performance/f-image-map-captures-xyz-write-after-counters.csv
_build/default/tools/bench_workspace_lower.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-recheck-xyz-write-after.csv 2> specification/performance/f-image-map-uncaptured-recheck-xyz-write-after-counters.csv
```

All 440 data rows complete (352 capture, 88 control). Thirty full native pixel
comparisons have zero maximum error/differing channels/differing pixels, CPU
domains 1/8 hashes match, and all 210 warm trial rows retain the resource/source
cache/cook/flatten/resize/replan/close assertions. Counter artifacts retain
448 capture and 56 control rows, plus headers.

Seven-trial medians in milliseconds and all-domain allocated B/frame:

| Capture fixture | CPU8 | GPU producer | Consumer | Combined | Producer B/frame |
|---|---:|---:|---:|---:|---:|
| Static 1,024 points, 512² | 4.152060 | 0.670580 | 0.425299 | 1.099535 | 89,161 |
| Static 1,024 points, 1024² | 14.477015 | 1.587850 | 0.666324 | 2.555610 | 89,161 |
| Static 1,024 points, 2048² | 54.420948 | 4.463880 | 1.506850 | 6.354965 | 89,161 |
| Changing 1,024 points, 512² | 4.379988 | 0.767455 | 0.440226 | 1.228945 | 370,195 |
| Changing 1,024 points, 1024² | 14.961004 | 1.760164 | 0.660784 | 2.871341 | 370,195 |
| Changing 1,024 points, 2048² | 54.713964 | 4.933571 | 1.557560 | 7.010920 | 370,195 |
| Static 65,536 points, 1024² | 17.415047 | 3.555745 | 0.676910 | 5.126956 | 89,161 |
| Changing 65,536 points, 1024² | 17.284155 | 6.181384 | 0.678130 | 7.035110 | 10,413,280 |

Large direct-input baseline CPU8/GPU was 17.266035/3.510880 ms static and
18.228054/6.159385 ms changing. Large changing allocation falls from 13,558,975
to 10,413,280 B/frame (about 3.15 MB). Static producer allocation stays exactly
89,161 at all source/pixel sizes. Smaller changing rows range 370,181–370,195
B/frame: pixel-count independent with minor trial variation, not identical
in every row. Uncaptured gradient CPU8/GPU is 12.489080/1.530524 ms and live
capture 11.399984/1.526026 ms; allocations remain 33,721/32,593 B/frame.

Astra: **“Retain the XYZ loop for its allocation reduction.”** There is no
demonstrated large-source GPU timing improvement: 6.159385 →6.181384 ms is
essentially unchanged, and the changing-source <5 ms gate still fails. CPU8,
static-source GPU and smaller-source GPU gates pass. This does not complete
F2.2. Astra authorizes repeating the same source-refresh attribution on the
retained loop, preserving all phase/coverage labels and raw seven-sample
comparisons. That must establish whether XYZ elapsed cost decreased and
another phase offset it, or elapsed cost remained unchanged despite fewer
allocations. No copying, ownership or cache optimization is approved.

Full F5 native/pixel qualification passes (exit 0;
`/tmp/rays-f-image-xyz-write-full.log`):

```sh
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/rays_editor/native_qualification/qualification @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
```

Both complete workspace sweeps cover 38 standard files, two custom-catalog
executables and 13 fixtures at four times/domains 1/8; the native sweep verifies
geometry/image/texture/drawing pixels. Native owner captures, retained Canvas,
failure/recovery, oversized capture, runtime qualification and pixel aliases
pass. Actual display is 1×; 2× goldens remain unqualified. No product probes
are present. This checkpoint remains short of overall F2.2/F.md completion.
Pre-commit shipping passes (exit 0; `/tmp/rays-f-image-xyz-write-ship.log`).

## F2.2 retained XYZ-loop source-refresh attribution (2026-10-09)

Machine: Apple M1 Macmini9,1, OCaml 5.3.0, Dune dev profile, actual 1× display.
Candidate: committed `dce3fefb`. Astra approved repeating the same temporary
source-refresh probes on the retained loop. The production algorithm is unchanged
from that commit; no additional probe family or instruction capture is added.
Session node-own durations cover cook domains and exclude input cooks;
initial-domain write phases and CPU worker-unobserved labels retain their
previous meaning. Exactly one line/with_attr/capture sample is asserted after
each successful materializer cook. Supplied node durations do not affect the
Phase_timer nesting stack. Reporting stays outside timed frame loops.

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest @lib/flow_sop/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-capture-attribution-xyz-write-whole.csv 2> specification/performance/f-image-map-capture-attribution-xyz-write-counters.csv
```

The run additionally writes `f-image-map-capture-attribution-xyz-write.csv`.
The reproducible nine-file probe-only patch has the same prefix with `.patch`.
Static/changing 65,536-point 1024² images and the gradient control use seven
CPU1/8 samples and seven ×200 completed GPU frames after ten warmups, isolated
from builds/tests/active agents. All 1,050 phase rows, 90 caller rows and 71
counter rows complete (headers additional). Nine full native pixel comparisons
have zero error/differing channels/pixels, CPU1/8 hashes match, and all capture/
resource/resize/replan/close assertions pass. Diagnostic build and benchmark
exit 0 (`/tmp/rays-f-image-xyz-write-attribution-build.log`).

Changing-source seven-trial medians, milliseconds per completed GPU frame:

| Interval and coverage | Prior source-refresh diagnostic | Retained XYZ loop |
|---|---:|---:|
| Whole caller | 6.248649 | 6.292236 |
| Materialization, inclusive | 2.432431 | 2.047064 |
| Line, node own across cook domains | 0.295147 | 0.341308 |
| With_attr, node own across cook domains | 2.128962 | 1.697543 |
| Capture, node own across cook domains | 0.000290 | 0.000200 |
| Write validation, nested | 0.189129 | 0.227145 |
| XYZ storage construction, nested | 0.940881 | 0.327947 |
| Attribute installation, nested | 0.001158 | 0.000762 |
| Cd map traversal, nested | 0.641835 | 0.715462 |
| Cd map source preparation, nested | 0.273716 | 0.317236 |
| P flatten | 0.263529 | 0.306879 |
| Cd flatten | 0.263864 | 0.310577 |
| P ordered direct traversal | 0.563650 | 0.678835 |
| Cd ordered direct traversal | 0.561979 | 0.677707 |
| Packed preparation, inclusive | 4.224846 | 4.157250 |
| Completed GPU execution | 1.080877 | 1.235315 |
| Sink conversion | 0.792496 | 0.811477 |

XYZ construction is measurably cheaper in this diagnostic. Other phases are
higher; whole elapsed time remains above the gate. Inclusive intervals overlap,
and medians cannot be summed to form a wall-time decomposition. In particular,
map/write intervals are nested inside with_attr/materialization/preparation.
This evidence makes no claim that the unexplained remainder is copying or that
a copying/ownership optimization is warranted.

Static whole producer is 3.432676 ms versus 3.429029 ms previously, with no
warm materializer/write/flatten calls. Static packed preparation is 1.684387 ms,
P/Cd direct traversal 0.808113/0.810248 ms. Gradient producer is 1.467475 ms
versus 1.533430 ms. CPU8 callers are 17.069101 ms static, 17.332792 ms changing,
12.264967 ms gradient; their worker internals remain explicitly unobserved.

All nine production files are restored byte-for-byte from the fresh committed
candidate archive. The saved probe-only patch passes `git apply --check`; no
production instrumentation remains. Astra's seven-sample review confirms
nonoverlapping XYZ construction ranges: 0.817–0.952 ms before, 0.315–0.401 ms
after. Materialization also falls; other observed phases rise. It makes no whole
GPU improvement claim and retains the changing-source gate as open.

The next approved bounded experiment uses scalar component accumulators only
for the already-recognized width-3 ordered-add path: read x/y/z into local float
references, iterate the same ascending indices, add/finite-check/update x then
y then z, and write the totals back after each successful chunk. Keep other
widths, recognizer restrictions, ordered chunks and reference fallback unchanged.
No reassociation, vectorization, parallel reduction or cached values. The native
compiler's register behavior must be measured rather than presumed. Strengthen
post-chunk overflow separately in x/y/z with unchanged reference diagnostic,
caller/input bytes and recovery; preserve signed zero/cancellation/boundary
coverage. Repeat unchanged isolated eight-cell/control measurements against
the uninstrumented XYZ-write baseline (changing GPU 6.181384 ms). Astra requires
repeatable benefit without regressions before retention. This experiment is
not implemented in this diagnostic checkpoint.

Restored focused checks/build pass (exit 0;
`/tmp/rays-f-image-xyz-write-attribution-restored.log`). Pre-commit shipping
passes (exit 0; `/tmp/rays-f-image-xyz-write-attribution-ship.log`). No product
behavior changes here; `/tmp/rays-f-image-xyz-write-full.log` remains the full
F5 native/pixel evidence for the unchanged committed implementation, actual 1×.

## F3 fresh fan-out baseline (2026-10-09)

Machine: Apple M1 Macmini9,1, eight logical CPUs, OCaml 5.3.0, Dune dev profile.
Production checkpoint: `b93df6a9` (RDK/Session unchanged). Build uses the normal
check launcher after restoring all temporary image probes; preserve the resulting
binary as `/private/tmp/f-merge-before.exe`, SHA256
`198f0d471e8888394518cc450fd204472c63d0bd42d9468987e85f642e3fe4e4`.
Astra confirmed that RAYS_BRANCH_NODE_TIMES only reports existing Session
samples after the whole-cook timer stops; it does not instrument the timed path.
Existing Session timing remains part of the production cook. No extra env-unset
batch is required. Run alone, without builds, tests or active agents.

Seven separate processes per mode, each retaining domain-1/8 rows, stdout and
node reports:

```sh
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-before.exe --branches 1 learned > "specification/performance/f-merge-before-chains-learned-${trial}.csv" 2> "specification/performance/f-merge-before-chains-learned-${trial}-nodes.csv"
done
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-before.exe --branches 1 off > "specification/performance/f-merge-before-chains-off-${trial}.csv" 2> "specification/performance/f-merge-before-chains-off-${trial}-nodes.csv"
done
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-before.exe --loops 1 learned > "specification/performance/f-merge-before-pieces-learned-${trial}.csv" 2> "specification/performance/f-merge-before-pieces-learned-${trial}-nodes.csv"
done
```

Learned runs perform one untimed training cook and clear output caches while
retaining timing knowledge, then measure with the existing pool warmup,
full-major policy and 512-entry/256-MiB Session limits. They are not untrained
cold runs. Placement-off is the separate untrained control. All 21 processes
exit 0; all 42 whole-cook rows retain exact hashes:
chains `67c129ecc130f8881a2eaf92c053b64c`, pieces
`8ef295fbdea12b586200fd1ffcdcb58f`. These hashes cover materialized geometry;
a display-only pieces representation cannot substitute for the chains result.

Seven-process medians (milliseconds; allocation in bytes):

| Mode | Domains | Whole cook | Caller allocation | Program allocation | Fanouts | Root merge own |
|---|---:|---:|---:|---:|---:|---:|
| Learned chains | 1 | 148.324013 | 503,647,672 | 503,647,960 | 0 | 58.411121 |
| Learned chains | 8 | 51.798820 | 374,059,712 | 505,437,232 | 1 | 26.059866 |
| Off chains | 1 | 199.245930 | 503,647,896 | 503,648,184 | 0 | 76.219082 |
| Off chains | 8 | 55.030107 | 503,969,320 | 505,313,904 | 0 | 25.868893 |
| Learned pieces | 1 | 1984.183073 | 1,120,474,624 | 1,120,474,912 | 0 | 114.761114 |
| Learned pieces | 8 | 267.518997 | 785,753,048 | 1,131,801,808 | 1 | 74.564219 |

Node timings are node-own work, not upstream cooks; parallel nodes can overlap.
They diagnose merge cost and do not replace the whole-cook gate. Keep all raw
samples, including the first learned-eight 65.128803 ms. Passing individual
trials do not pass the median gate.

Astra: **“not met, try two-input vertex-index prefilling with Array.concat,
skipping only zero-point-offset rebasing.”** The fresh learned-eight median
exceeds the unchanged 50.600 ms gate by 1.198820 ms. The approved trial remains
bounded to exactly two inputs, fresh concatenated vertex storage and skipping
only prefilled zero-point-offset segments. Nonzero offsets, other arities,
primitive offsets, position/attribute/group work, cancellation and scheduling
stay unchanged. The fixed triangle/free-point/polyline regression must pass
before implementation; retain complete geometry/input bytes at domains 1/8 and
precancellation. Repeat the identical seven-process after matrix and then seven
learned-chain processes for after followed by before in a separate reverse-order
comparison. No measured trial or unreachable verdict is claimed yet.

## F3 vertex-index prefill trial rejected (2026-10-09)

Same Apple M1/OCaml 5.3/Dune dev machine and protocol as the fresh baseline.
Astra approved exactly-two-input vertex-index Array.concat followed by skipping
only prefilled segments with zero point offset. Existing nonzero rebasing,
other arities, primitive offsets, attributes/groups and scheduling remain.
Cancellation is checked before concatenation and at existing input/index
boundaries. The reproducible production-only rejected patch is
`specification/performance/f-merge-vertex-prefill-trial.patch`.

Before changing the implementation, the independent fixed regression passed on
unchanged code (exit 0; `/tmp/rays-f-merge-regression-before.log`, `@check`
and RDK core/mesh tests). It constructs the expected seven-point triangle/free-
point/polyline geometry independently: vertex indices [0;1;2;5;6], offsets
[0;3;5], Polygon/Open_polyline. Five-input empty cases and the equivalent
two-input case pin complete geometry bytes. Free-points followed by triangle
expects [2;3;4], catching zero vertex offset with nonzero point offset. Leading/
trailing empty two-input cases pin prefill behavior. All inputs remain byte-
identical at domains 1/8; precancellation returns cancelled and preserves inputs.
The same regression and full focused RDK/procedural tests pass on the candidate
(exit 0; `/tmp/rays-f-merge-focused.log`). Astra approves its implementation diff.

Preserve `/private/tmp/f-merge-after.exe`, SHA256
`b5b201e334e71c2dc00e1fc2b0eb464455b607c7cfdc8683519c603f981862e3`.
The before executable remains unchanged at its recorded hash. The after run
repeats all seven separate-process modes with RAYS_BRANCH_NODE_TIMES=1, isolated
from builds/tests/active agents; reverse-order learned comparison then runs
seven fresh after processes followed by seven fresh before processes:

```sh
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-after.exe --branches 1 learned > "specification/performance/f-merge-after-chains-learned-${trial}.csv" 2> "specification/performance/f-merge-after-chains-learned-${trial}-nodes.csv"
done
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-after.exe --branches 1 off > "specification/performance/f-merge-after-chains-off-${trial}.csv" 2> "specification/performance/f-merge-after-chains-off-${trial}-nodes.csv"
done
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-after.exe --loops 1 learned > "specification/performance/f-merge-after-pieces-learned-${trial}.csv" 2> "specification/performance/f-merge-after-pieces-learned-${trial}-nodes.csv"
done
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-after.exe --branches 1 learned > "specification/performance/f-merge-reverse-after-chains-learned-${trial}.csv" 2> "specification/performance/f-merge-reverse-after-chains-learned-${trial}-nodes.csv"
done
for trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-before.exe --branches 1 learned > "specification/performance/f-merge-reverse-before-chains-learned-${trial}.csv" 2> "specification/performance/f-merge-reverse-before-chains-learned-${trial}-nodes.csv"
done
```

All 56 processes across baseline/after/reverse batches complete: 112 whole-cook
rows retain fixed chain/piece hashes, cardinalities and fanouts. All 112 stdout/
node CSVs remain, including outliers; no per-node metric substitutes for the
whole-cook gate. Seven-process medians:

| Mode | Domains | Before whole ms | After whole ms | After caller B | After program B | Fanouts | After root merge ms |
|---|---:|---:|---:|---:|---:|---:|---:|
| Learned chains | 1 | 148.324013 | 148.796082 | 503,647,728 | 503,648,016 | 0 | 58.889151 |
| Learned chains | 8 | 51.798820 | 65.582991 | 374,015,976 | 505,177,448 | 1 | 39.048910 |
| Off chains | 1 | 199.245930 | 199.889898 | 503,647,952 | 503,648,240 | 0 | 77.643871 |
| Off chains | 8 | 55.030107 | 66.389084 | 503,925,760 | 505,053,176 | 0 | 36.741018 |
| Learned pieces | 1 | 1984.183073 | 2004.331827 | 1,120,474,648 | 1,120,474,936 | 0 | 121.362925 |
| Learned pieces | 8 | 267.518997 | 264.780045 | 779,593,392 | 1,131,798,432 | 1 | 77.320099 |

| Reverse-order learned chains | Domains | Before whole ms | After whole ms | Before merge ms | After merge ms |
|---|---:|---:|---:|---:|---:|
| After batch followed by before batch | 1 | 148.498058 | 148.794889 | 58.406115 | 58.833122 |
| After batch followed by before batch | 8 | 51.988840 | 71.448088 | 27.842045 | 45.994043 |

Reverse caller/program bytes at eight domains are 374,061,160/505,436,112 before
and 373,998,968/505,176,848 after; at one domain
503,647,672/503,647,960 before and 503,647,728/503,648,016 after.
The substantial eight-domain regression persists in both execution orders;
unchanged output is correctness evidence, not a reason to retain the trial.

Astra: **“not met, revert.”** The Array.concat production change is reverted
byte-for-byte. Keep the independent regression, rejected patch, executables and
raw measurements. `git apply --check` validates the rejected patch against
restored source. F3 remains above 50.600 ms; these results do not establish that
the gate is unreachable.

Astra approves one next diagnostic of restored merge: caller-side time-only
intervals for output-array allocation, position-plane blits, joined vertex-
index rewrites, joined primitive-offset rewrites, kind blits, attribute
concatenation and remaining wrapping/groups/geometry construction, plus the
complete merge interval. Aggregate repeated phases across inputs without
changing order. No GC snapshots, printing or new callbacks inside element
loops. Buffer reports outside measurement and retain round-trip timestamps;
distinguish training from measured cooks. Temporary Unix linkage is diagnostic-
only and must be restored with source byte-for-byte.

Run seven isolated learned-chain processes of the diagnostic executable and
the preserved production baseline under identical settings. Retain whole/node/
phase rows as `f-merge-phases-*`, fixed hashes/cardinalities/fanouts and paired
phase sums contained within their corresponding merge intervals. Report
instrumentation overhead before another optimization. No further trial is
approved yet; the whole learned-eight-domain gate remains 50.600 ms.

Restored `@check`, full RDK/procedural focused tests and benchmark build pass
(exit 0; `/tmp/rays-f-merge-restored-focused.log`). Pre-commit shipping passes
(exit 0; `/tmp/rays-f-merge-restored-ship.log`). The production merge source is
byte-identical to the preceding full F5 native checkpoint, whose actual-1×
evidence remains `/tmp/rays-f-image-xyz-write-full.log`. This checkpoint retains
only the independent regression, rejected patch and measured evidence; no
production optimization or overall F3/F.md completion is claimed.

### F3 restored merge: time-only attribution and next vertex-loop design

2026-10-09, Apple M1 Macmini9,1, OCaml 5.3, Dune dev profile. Seven isolated
learned-chain diagnostic→baseline pairs, domains 1/8 in each process, with no
concurrent agents/builds/tests. Existing untimed training, cache clearing that
retains timing knowledge, pool warmup and full-major collection are unchanged.

```sh
for task_trial in 0 1 2 3 4 5 6; do
  RAYS_BRANCH_NODE_TIMES=1 RAYS_MERGE_PHASES_FILE="specification/performance/f-merge-phases-diagnostic-${task_trial}-phases.csv" /private/tmp/f-merge-phases.exe --branches 1 learned > "specification/performance/f-merge-phases-diagnostic-${task_trial}.csv" 2> "specification/performance/f-merge-phases-diagnostic-${task_trial}-nodes.csv"
  RAYS_BRANCH_NODE_TIMES=1 RAYS_MERGE_PHASES_FILE="specification/performance/f-merge-phases-baseline-${task_trial}-phases.csv" /private/tmp/f-merge-before.exe --branches 1 learned > "specification/performance/f-merge-phases-baseline-${task_trial}.csv" 2> "specification/performance/f-merge-phases-baseline-${task_trial}-nodes.csv"
done
```

The baseline ignores the phase variable and emits no phase file. All 14
processes exit 0; all 28 whole rows keep 2,000,000 points, hash
67c129ecc130f8881a2eaf92c053b64c, and fanouts 0/1 at domains 1/8. All 196 phase
rows are retained. Each training/measured cook has exactly seven phase records;
child intervals sum within complete merge, and measured complete merge fits
inside the corresponding Session root-own interval. Missing/duplicate records,
negative intervals/residuals and buffer overflow fail rather than being dropped
or clamped. The remaining phase is an exclusive residual including metadata,
wrapping, groups, geometry creation and probe bookkeeping, not independent
attribution of those operations. No GC snapshots/printing/new callbacks in
inner loops. Training records are distinct from measured records.

Seven-process medians, milliseconds:

| Metric | Domains 1 | Domains 8 |
|---|---:|---:|
| Production whole cook | 149.086952 | 62.613010 |
| Diagnostic whole cook | 151.123047 | 63.819885 |
| Paired diagnostic-minus-baseline overhead | 2.187967 | 1.014232 |
| Production Session root-own | 58.272839 | 37.170887 |
| Diagnostic Session root-own | 59.142828 | 36.458015 |
| Measured complete merge | 57.885885 | 34.251928 |
| Allocation | 7.495880 | 6.633043 |
| Position blits | 1.575232 | 1.592875 |
| Joined vertex rewrites | 29.390097 | 7.174969 |
| Joined primitive rewrites | 9.824038 | 2.469301 |
| Kind blits | 0.120163 | 0.134945 |
| Attributes | 9.441137 | 6.445885 |
| Remaining residual | 0.010967 | 0.017881 |

Training complete medians are 74.259043/32.706976 ms; allocation
22.696018/14.074087, position 2.200842/1.692295, vertex 30.669928/7.634878,
primitive 10.279894/2.471924, kind 0.210047/0.187159, attributes
8.280993/6.525040 and residual 0.014067/0.015497 ms. Separate phase medians
must never be summed into a synthetic cook time. Complete merge and Session
root-own have different scopes; their difference does not diagnose missing work.

Whole caller/program allocation medians are 503,647,672/503,647,960 B (baseline1),
374,047,304/505,437,688 B (baseline8), 503,652,976/503,653,264 B (diagnostic1),
and 374,060,752/505,441,320 B (diagnostic8). The latest baseline62.613010 ms is
slower than the earlier51.798820/reverse51.988840 ms; retain this context and all
samples. Instrumentation cannot establish the 50.600 ms whole-cook gate.

Preserved diagnostic SHA256:
1319e3a2c2e3476fbea67f9502490a07e41f29c15c6bf8214720b076e9c53cae.
Baseline SHA256 remains
198f0d471e8888394518cc450fd204472c63d0bd42d9468987e85f642e3fe4e4.
`f-merge-phases.patch` preserves the four-file probe. Source/Dune files were
restored byte-for-byte against `/private/tmp/rays-f-merge-phase-probes/original.tar`;
`git apply --check` passes. No temporary Private API or Unix linkage is promoted.
Diagnostic focused build and restored @check/RDK core+mesh/benchmark checks
exit 0 (`/tmp/rays-f-merge-phases-build.log`,
`/tmp/rays-f-merge-phases-restored.log`). Production source remains unchanged.

Astra verdict: **“not met, try chunked vertex-index rewrites with a plain inner
loop, leaving primitive-offset rewrites unchanged.”** This narrower trial uses
new phase evidence. The previous 570 ms attempt remains unexplained because its
implementation was not preserved. Change only vertex rewriting: dispatch stable
grain ranges using existing Parallel.for_ at chunk size1; keep the sequential
cutoff vertices_here/grain<2; compute ends as first+min grain(count-first).
Within each range, use plain integer assignment loops, with cancellation checks
before subranges of at most16,384 elements. No cancellation branch/call inside
the element loop. Keep the OCaml assignment barrier and every other merge phase.
Inspect assembly for direct load/add/store without per-element indirect calls,
allocation or repeated loop-state spills; no speedup is promised.

Extend the independent regression with32,769/16,385-reference open polylines
on small distinct point sets; compare full independently authored bytes and
unchanged inputs at domains1/8, grains257/16,384/65,536/max_int. Existing empty,
free-point and precancelled cases stay. Pass this on baseline before changing
production. Preserve baseline/candidate executables; repeat seven processes per
learned/off/pieces mode and reverse learned order under f-merge-vertex-*.
Repeat temporary before/after phase attribution, restoring source byte-for-byte.
Keep only with exact results and repeatable whole-cook improvement without
material control regression. Only uninstrumented learned-eight whole median
≤50.600 ms meets F3; no defensible unreachable closure exists. Trial pending.

Pre-commit shipping passes (exit 0; `/tmp/rays-f-merge-phases-ship.log`). This
checkpoint records attribution and the approved next design, retaining no
production optimization and making no F3 or overall-completion claim.

### F3 vertex-only chunked-loop trial: rejected, regression localized

2026-10-09, same M1/OCaml5.3/Dune dev setup and unchanged benchmark fixtures.
Astra's approved design is implemented only in vertex rewriting. Stable grain
ranges use Parallel.for_ chunk_size1, cutoff vertices_here/grain<2, overflow-safe
ends and cancellation before subranges of at most16,384 elements. Primitive
rewrites and all allocation/copy/schema/attribute/group work remain unchanged.

The independent regression in test_rdk.ml adds two open polylines with32,769
and16,385 references to small distinct point sets. Expected concatenated indices
and point rebasing are authored independently. Full geometry bytes and unchanged
inputs match at domains1/8, grains257/16,384/65,536/max_int; precancellation
preserves inputs. Existing empty/free-point cases stay. It passes before the
trial (`/tmp/rays-f-merge-vertex-regression-before.log`), after, and restored.
Full @check/RDK/procedural/benchmark focused checks pass on candidate and restored
(`/tmp/rays-f-merge-vertex-focused.log`,
`/tmp/rays-f-merge-vertex-restored-focused.log`), exit0.

Astra approves the implementation and generated-loop condition before timing.
`otool -tvV _build/default/lib/rdk/mesh/.rdk_mesh.objs/native/rdk_mesh__Mesh_merge.o`
produces preserved `f-merge-vertex-inner-loop-arm64.txt`: the normal inner loop
has direct integer load/add/store, register-held index/end, no per-element
callback/allocation/loop-state store. Cancellation is before the subrange.
Bounds checks, runtime polling, closure reloads and dmb ishld remain. This is
code evidence, not a promise of improved time. `f-merge-vertex-trial.patch`
preserves the complete candidate production diff.

Preserved production executables:

| Executable | SHA256 |
|---|---|
| /private/tmp/f-merge-vertex-before.exe | 198f0d471e8888394518cc450fd204472c63d0bd42d9468987e85f642e3fe4e4 |
| /private/tmp/f-merge-vertex-after.exe | 8284d0c53e59a032909d83d2a9966990129ad9aa0b4104c01a7533939e441d37 |

The complete seven-process matrix runs in isolation from builds/tests/active
agents, production before then after per mode; reverse learned order follows:

```sh
for task_kind in before after; do
  for task_mode in chains-learned chains-off pieces-learned; do
    case "$task_mode" in
      chains-learned) task_args='--branches 1 learned';;
      chains-off) task_args='--branches 1 off';;
      pieces-learned) task_args='--loops 1 learned';;
    esac
    for task_trial in 0 1 2 3 4 5 6; do
      RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-vertex-${task_kind}.exe ${=task_args} > "specification/performance/f-merge-vertex-${task_kind}-${task_mode}-${task_trial}.csv" 2> "specification/performance/f-merge-vertex-${task_kind}-${task_mode}-${task_trial}-nodes.csv" || exit $?
    done
  done
 done
for task_kind in after before; do
  for task_trial in 0 1 2 3 4 5 6; do
    RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-vertex-${task_kind}.exe --branches 1 learned > "specification/performance/f-merge-vertex-reverse-${task_kind}-chains-learned-${task_trial}.csv" 2> "specification/performance/f-merge-vertex-reverse-${task_kind}-chains-learned-${task_trial}-nodes.csv" || exit $?
  done
 done
```

This command uses zsh argument splitting. All56 processes exit0; all112 whole
rows pin fixture/mode, both domain rows, point counts, chain/piece hashes and
fanouts. No samples are excluded. Learned runs retain existing untimed training
and clear output caches while retaining timing knowledge. Seven-process medians:

| Mode | Domains | Before whole ms | After whole ms | Before root merge ms | After root merge ms |
|---|---:|---:|---:|---:|---:|
| Learned chains | 1 | 152.101994 | 817.284822 | 59.299946 | 725.937128 |
| Learned chains | 8 | 63.404799 | 59.296131 | 37.958860 | 32.547951 |
| Off chains | 1 | 205.591917 | 911.634922 | 79.107046 | 784.686089 |
| Off chains | 8 | 55.523157 | 63.062906 | 25.458097 | 32.633066 |
| Learned pieces | 1 | 1972.412109 | 4473.544836 | 119.451046 | 1303.678036 |
| Learned pieces | 8 | 258.543015 | 305.453777 | 78.130007 | 84.857225 |
| Reverse learned chains | 1 | 148.737907 | 899.132013 | 57.942152 | 807.601929 |
| Reverse learned chains | 8 | 63.197136 | 69.355011 | 35.804987 | 44.502974 |

Whole caller/program allocation medians, bytes:

| Mode | Domains | Before caller | Before program | After caller | After program |
|---|---:|---:|---:|---:|---:|
| Learned chains | 1 | 503647672 | 503647960 | 503647752 | 503648040 |
| Learned chains | 8 | 374051424 | 505434744 | 373985952 | 505430936 |
| Off chains | 1 | 503647896 | 503648184 | 503647976 | 503648264 |
| Off chains | 8 | 503975464 | 505314376 | 503927024 | 505310896 |
| Learned pieces | 1 | 1120474624 | 1120474912 | 1120476712 | 1120477000 |
| Learned pieces | 8 | 785739360 | 1131804744 | 785611800 | 1131739648 |
| Reverse learned chains | 1 | 503647672 | 503647960 | 503647752 | 503648040 |
| Reverse learned chains | 8 | 374043640 | 505434456 | 373978344 | 505434176 |

Astra: **“not met, revert.”** The substantial one-domain slowdown repeats in
reverse order; eight-domain benefit is inconsistent and above50.600 ms.
One-domain allocation grows only80 B per chains cook, ruling out substantial
per-element boxing as the explanation. No eight-domain-only variant is retained.

Finish the already approved before/after phase comparison, with unchanged
caller-side time-only probes. Baseline diagnostic is byte-identical to the prior
preserved diagnostic. Candidate diagnostic differs only by the approved vertex
loop. Each diagnostic passes @check/RDK core+mesh/benchmark build, exit0
(`/tmp/rays-f-merge-vertex-phase-before-build.log`,
`/tmp/rays-f-merge-vertex-phase-after-build.log`). Preserve executables:

| Executable | SHA256 |
|---|---|
| /private/tmp/f-merge-vertex-phase-before.exe | 1319e3a2c2e3476fbea67f9502490a07e41f29c15c6bf8214720b076e9c53cae |
| /private/tmp/f-merge-vertex-phase-after.exe | 9b3f17b6cc9e8bd3fe635827e6784bfeb157edacfb92bd165bc198c6b4bad96d |

```sh
for task_trial in 0 1 2 3 4 5 6; do
  for task_kind in before after; do
    RAYS_BRANCH_NODE_TIMES=1 RAYS_MERGE_PHASES_FILE="specification/performance/f-merge-vertex-phase-${task_kind}-${task_trial}-phases.csv" /private/tmp/f-merge-vertex-phase-${task_kind}.exe --branches 1 learned > "specification/performance/f-merge-vertex-phase-${task_kind}-${task_trial}.csv" 2> "specification/performance/f-merge-vertex-phase-${task_kind}-${task_trial}-nodes.csv" || exit $?
  done
 done
```

All14 isolated processes exit0, with28 fixed whole rows and392 phase rows.
Every training/measured cook has exactly seven distinct names and expected call
counts. Every sample has nonnegative finite intervals, child sum≤complete;
every measured complete≤Session root-own. All samples/outliers remain. Seven
medians, measured cooks (ms; do not sum separate phase medians):

| Phase | Before 1 | After 1 | Before 8 | After 8 |
|---|---:|---:|---:|---:|
| Complete merge | 59.088945 | 737.746000 | 31.002045 | 38.609028 |
| Allocation | 7.629871 | 7.917881 | 6.649971 | 13.001919 |
| Position blits | 1.578808 | 1.800776 | 1.616955 | 1.634121 |
| Vertex rewrites | 29.999256 | 707.682371 | 7.277250 | 14.573812 |
| Primitive rewrites | 10.023832 | 10.380983 | 2.436876 | 2.379179 |
| Kind blits | 0.121117 | 0.194073 | 0.134945 | 0.129938 |
| Attributes | 9.644032 | 9.572983 | 6.491184 | 6.479979 |
| Remaining residual | 0.010967 | 0.014067 | 0.038862 | 0.046730 |

Training vertex medians1/8 before31.332970/7.666111, after707.224846/13.223171 ms;
training complete76.023817/32.737017 before,752.810955/38.201809 after. These
remain labeled separately. The one-domain slowdown is localized inside vertex
rewriting; allocation and attributes do not explain it. The eight-domain run
also has higher allocation timing, without substantial allocation-byte growth.
The machine-level cause remains unproven.

Diagnostic whole medians1/8 before153.919935/60.307980, after830.646992/67.720175 ms;
Session root-own60.372829/33.061981 before,739.007950/42.027950 after. Whole
caller/program B before1=503652976/503653264, after1=503653056/503653344;
before8=374057624/505444976, after8=373992600/505439488. These diagnostics
attribute the rejection; they never establish the production performance gate.

`f-merge-vertex-phase-after.patch` is probe-only against the preserved candidate;
its apply check passes on candidate source. The existing f-merge-phases.patch
reproduces the baseline diagnostic. All four source/Dune files restore from the
fresh baseline archive byte-for-byte, leaving no production/API/linkage diff.
Both trial/baseline-probe apply checks pass on restored production. Keep the
regression, failed production patch, candidate probe patch, assembly and154 raw
CSV files. This rejection does not establish an unreachable F3 gate.

Pre-commit shipping passes, exit0
(`/tmp/rays-f-merge-vertex-restored-ship.log`). Four restored files also compare
byte-for-byte with the fresh baseline archive. The retained product source is
unchanged from the prior full F5 native checkpoint; the new change is a pure
regression plus failed-trial evidence. No F3 or overall F.md completion is claimed.

Astra audits all392 phase rows/56 cooks and28 measured containment pairs:
**“not met, revert.”** The failed loop remains reverted. Astra approves only
native stack sampling of the preserved production baseline/rejected candidate,
seven alternating-order pairs with unchanged --branches1learned fixture.
Use `/usr/bin/sample "$profile_pid" 10 1 -mayDie -file "$prefix-sample.txt"`,
retain sampler output and cook/sampler exit statuses, verify executable hashes,
and distinguish initial-thread/worker counts and actual coverage. Sampling
aggregates training/measured and both domain counts; it cannot establish phase
timing or the gate. Determine whether stacks remain in rewrite or enter GC/poll/
runtime slow paths; if unresolved, state the limit. No new optimization approved.

### F3 rejected-loop native sampling: loop residency and controlled next trial

2026-10-09, same Apple M1 Macmini9,1, OCaml5.3/Dune dev executables. Production
remains reverted. SHA256 checks immediately before profiling match preserved
baseline198f0d471e8888394518cc450fd204472c63d0bd42d9468987e85f642e3fe4e4 and
candidate8284d0c53e59a032909d83d2a9966990129ad9aa0b4104c01a7533939e441d37.
Seven isolated alternating-order pairs, no builds/tests/active agents:

```sh
for task_trial in 0 1 2 3 4 5 6; do
  if (( task_trial % 2 == 0 )); then task_order=(before after); else task_order=(after before); fi
  for task_kind in $task_order; do
    task_prefix="specification/performance/f-merge-vertex-sample-${task_kind}-${task_trial}"
    RAYS_BRANCH_NODE_TIMES=1 /private/tmp/f-merge-vertex-${task_kind}.exe --branches 1 learned > "$task_prefix.csv" 2> "$task_prefix-nodes.csv" &
    profile_pid=$!
    /usr/bin/sample "$profile_pid" 10 1 -mayDie -file "$task_prefix-sample.txt" > "$task_prefix-sampler.txt" 2>&1
    task_sample_status=$?
    wait "$profile_pid"
    task_cook_status=$?
    echo "kind,trial,pid,sampler_exit,cook_exit" > "$task_prefix-status.csv"
    echo "$task_kind,$task_trial,$profile_pid,$task_sample_status,$task_cook_status" >> "$task_prefix-status.csv"
    if (( task_cook_status != 0 )); then exit "$task_cook_status"; fi
  done
 done
```

All14 cooks and samplers exit0. All28 whole rows preserve chain hash,2M points,
domain1/8 and fanouts0/1. All70 raw files remain, including sampler diagnostics
and statuses. Before0 has an empty callgraph despite successful sampler exit;
retain it and report13 usable profiles. Requested sampling is10 seconds at1ms,
with -mayDie terminating coverage when each short process exits. No measured
wall time from this diagnostic decides a gate.

`f-merge-vertex-sample-counts.csv` preserves per-thread exclusive counts;
`f-merge-vertex-sample-summary.csv` aggregates initial thread and seven threads
with domain_thread_func separately from eight backup-thread bodies. The parser
subtracts immediate-child counts, asserts nonnegative self counts and exact
per-thread sample conservation, and avoids recursive-frame double counting.
Initial-thread counts (samples; not phase timings):

| Trial | Before total | Before vertex callback self | Before GC/interrupt self | After total | After rewrite self | After GC/interrupt self |
|---|---:|---:|---:|---:|---:|---:|
| 0 | 0 (empty) | 0 | 0 | 1698 | 1008 | 44 |
| 1 | 789 | 40 | 43 | 1792 | 1063 | 42 |
| 2 | 778 | 36 | 50 | 1708 | 1016 | 42 |
| 3 | 779 | 40 | 52 | 1788 | 1053 | 54 |
| 4 | 780 | 42 | 49 | 1875 | 1148 | 45 |
| 5 | 789 | 40 | 50 | 1826 | 1103 | 47 |
| 6 | 770 | 45 | 39 | 1794 | 1081 | 43 |

GC/interrupt groups known GC, marking, sweep, collection and interrupt leaf
symbols; the CSV also reports other caml_ runtime leaves, including untimed
hashing. Domain-worker total samples before1..6 are2326–2422 with54–67 vertex
callback leaves; after0..6 are2416–2492 with137–157 rewrite leaves. Idle worker
and backup coverage is retained rather than folded into initial-thread counts.
These profiles aggregate untimed hashing, training, measured cooking and both
domain counts. They cannot turn sample percentages into one-domain phase time.

Astra independently checks the exclusive rewrite counts and linked PC mapping.
Prominent candidate offsets+172 and+188 are captured vertex-offset and target
header loads; +204 is dmb ishld, while +292 is the caml_call_gc slow path.
Samples stay in the native loop, without a sampled runtime callee beneath it.
This resolves the broad loop-vs-runtime distinction; it does not identify the
microarchitectural stall, prove GC never intervened or support unreachable closure.
Astra: **“not met, revert.”** The implementation remains reverted.

Astra approves one controlled next trial: private noncapturing typed helper
`rewrite_vertices (source:int array) (target:int array) point_offset vertex_offset
first last`, marked inline never, containing only the checked ascending integer
assignment loop. Call once per existing cancellation subrange in the rejected
chunked design. Keep its chunking/cancellation, checked accesses and DMB; leave
primitive rewrites and other phases unchanged. This tests captured reloads, not
an established explanation. Before timing, arrays/offsets/index/end must actually
remain in registers without per-element closure loads/calls. Reuse the existing
full-byte32769/16385-reference domain/grain/ownership/precancellation regression.

First run seven isolated alternating-order phase pairs against unchanged
production, keeping all rows/allocations/hashes. Stop and reject if the vertex
catastrophe persists. If it disappears, repeat the complete seven-process
uninstrumented learned/off/pieces and reverse learned matrices at1/8 domains.
Retention compares with production, not the rejected implementation. Only whole
learned-eight median≤50.600 ms with exact hashes and acceptable controls passes.
This next trial remains unimplemented.

Pre-commit shipping passes, exit0
(`/tmp/rays-f-merge-vertex-sampling-ship.log`). Production source/Dune remain
unchanged. This checkpoint adds diagnostic evidence and the next approved design;
no performance or overall completion claim is made.

### F3 explicit integer range helper: early stop after phase regression

2026-10-09, Apple M1 Macmini9,1, OCaml5.3, Dune dev. Implement the approved
private typed inline-never rewrite_vertices helper, called once per existing
≤16,384-element cancellation subrange of the rejected chunked design. No other
merge phase changes. Baseline source is archived fresh in
/private/tmp/rays-f-merge-explicit-baseline.tar; candidate in
/private/tmp/rays-f-merge-explicit-candidate.tar. The production trial is saved
as f-merge-explicit-trial.patch; inner assembly as
f-merge-explicit-inner-loop-arm64.txt.

Full @check/RDK/procedural/benchmark focused validation passes on the candidate
(exit0, /tmp/rays-f-merge-explicit-focused.log), including the existing independent
32769/16385-reference grain257/16384/65536/max_int domain1/8 full-byte,
ownership and precancellation regression. Astra approves both implementation
and the assembly condition before timing. Source/target x0/x1, offsets x2/x3,
index x4 and end x7 remain in registers on the successful inner path. Both
bounds checks, dmb ishld and runtime polling remain. No per-element closure
loads, calls, allocation or spills occur on that path. The registers satisfy
the proposed hypothesis check; that alone is not performance evidence.

Preserved executables (SHA256):

| Executable | SHA256 |
|---|---|
| Production baseline /private/tmp/f-merge-vertex-before.exe | 198f0d471e8888394518cc450fd204472c63d0bd42d9468987e85f642e3fe4e4 |
| Production candidate /private/tmp/f-merge-explicit-after.exe | a90eaff889b961a41c6dd136d74eaab16d3e7691ac635746c481e89bc2bf5340 |
| Baseline diagnostic /private/tmp/f-merge-vertex-phase-before.exe | 1319e3a2c2e3476fbea67f9502490a07e41f29c15c6bf8214720b076e9c53cae |
| Candidate diagnostic /private/tmp/f-merge-explicit-phase-after.exe | 33ba0d4af8652e0e0f1c33847dd68a1247072593d2cc6686dce2530f1df0b603 |

The candidate probe uses the same approved caller-side time-only phases,
training/measured labels, precision, call counts and fail-on-overflow/negative
checks as the baseline. Diagnostic @check/RDK core+mesh/benchmark build passes
(exit0; /tmp/rays-f-merge-explicit-phase-build.log). Four probe source/Dune files
restore byte-for-byte to the current candidate before timing; saved
f-merge-explicit-phase-after.patch applies cleanly to it. No temporary API or
Unix linkage is promoted. Seven isolated alternating-order phase pairs, no
builds/tests/active agents:

```sh
for task_trial in 0 1 2 3 4 5 6; do
  if (( task_trial % 2 == 0 )); then task_order=(before after); else task_order=(after before); fi
  for task_kind in $task_order; do
    if [[ "$task_kind" == before ]]; then task_exe=/private/tmp/f-merge-vertex-phase-before.exe; else task_exe=/private/tmp/f-merge-explicit-phase-after.exe; fi
    RAYS_BRANCH_NODE_TIMES=1 RAYS_MERGE_PHASES_FILE="specification/performance/f-merge-explicit-phase-${task_kind}-${task_trial}-phases.csv" "$task_exe" --branches 1 learned > "specification/performance/f-merge-explicit-phase-${task_kind}-${task_trial}.csv" 2> "specification/performance/f-merge-explicit-phase-${task_kind}-${task_trial}-nodes.csv" || exit $?
  done
 done
```

All14 processes exit0; all28 whole rows retain chain hash
67c129ecc130f8881a2eaf92c053b64c,2M points and fanouts0/1 at domains1/8.
All392 phase rows retain exactly seven names/cook with expected call counts,
nonnegative finite intervals, per-sample sum≤complete and measured complete≤
Session root-own. No samples/outliers are excluded. Seven medians (ms):

| Measured phase | Before 1 | After 1 | Before 8 | After 8 |
|---|---:|---:|---:|---:|
| Complete merge | 58.871031 | 807.116985 | 31.229973 | 38.687944 |
| Allocation | 7.572889 | 7.817030 | 6.357908 | 6.561041 |
| Position blits | 1.574278 | 1.757145 | 1.648903 | 1.628160 |
| Vertex rewrites | 29.943943 | 777.833700 | 7.259846 | 10.388851 |
| Primitive rewrites | 9.998083 | 10.001898 | 2.657890 | 2.451181 |
| Kind blits | 0.121117 | 0.193834 | 0.174999 | 0.128031 |
| Attributes | 9.568214 | 9.490013 | 6.503820 | 6.330967 |
| Remaining residual | 0.010729 | 0.014782 | 0.017166 | 0.041962 |

Training vertex medians1/8: before30.824184/7.652760, after736.407042/10.193825;
training complete before75.666904/32.477856, after780.827045/35.007000.
Training/measured records remain distinct. Never sum separate phase medians.
Diagnostic whole medians1/8 before153.849840/61.465979, after901.137114/67.044973;
Session root-own before60.152054/33.265829, after808.382988/40.699005.
Whole caller/program allocation B before1=503652976/503653264,
after1=503653056/503653344; before8=374065408/505440432,
after8=373973816/505433768. One-domain bytes grow only80 B.

The vertex catastrophe persists with captured-array/offset reloads removed.
That hypothesis is not established as its cause. The approved protocol therefore
stops here: no uninstrumented learned/off/pieces matrix is run for this rejected
trial. Production is restored byte-for-byte from the fresh baseline archive;
all four files compare equal, and the saved production patch applies cleanly.
Retain all42 diagnostic CSVs, trial/probe patches and assembly. Restored full
@check/RDK/procedural/benchmark checks pass (exit0;
/tmp/rays-f-merge-explicit-restored-focused.log). Diagnostics cannot meet the
50.600 ms whole learned-eight gate or prove it unreachable.

Astra verifies all392 phase rows/56 cooks and confirms the vertex medians:
**“not met, revert.”** Stop before the production matrix as specified. The
next approved F3 action is attribute-concatenation attribution by storage kind
and coordinate plane, using restored source/time-only probes. Record attribute
name/owner/kind and input/output lengths outside timers; time existing
concatenate_attribute calls and nest Float2/3/4 plane Array.concat intervals.
Preserve allocation/evaluation order/callbacks, use bounded buffered reports with
overflow failure, and require plane sums≤attribute interval and attribute sums≤
aggregate interval. Distinguish training/measured. Seven isolated alternating
learned diagnostic/baseline pairs at1/8 domains retain all whole/node/phase rows,
allocations/hashes/outliers; restore temporary files byte-for-byte. Attribution
only, no new optimization approved; unchanged whole learned-eight gate≤50.600 ms.

Pre-commit shipping passes, exit0 (`/tmp/rays-f-merge-explicit-ship.log`). The
worktree retains only failed-trial evidence and documentation. No production
change, F3 gate achievement or overall completion is claimed.

### F2.2 scalar Vec3 ordered-add branch: retained static improvement

2026-10-09, Apple M1 Macmini9,1, OCaml5.3, Dune dev, actual1× display. Baseline
is retained XYZ-write production dce3fefb; intervening commits add diagnostics,
tests and documentation, with rejected production changes restored. Implement
only Astra's approved recognized width-3 ordered-add branch: scalar float locals
for x/y/z, ascending element order, finite-check/update x then y then z, and
write three totals back only after successful chunk. Other widths, predicate,
chunk traversal, seed/source handling and reference fallback remain unchanged.
No reassociation/vectorization/parallel reduction/caching. Astra approves diff.

Strengthen the existing test_uniforms rollback fixture for Float and Vec3
x/y/z overflow at counts2/16385 (after chunk boundary), domains1/8, CPU force and
GPU preparation. Check exact reference diagnostics, input bytes, caller stamps,
rollback and successful recovery; recovered prepared uniform bits match reference
sum. Pass on baseline first (exit0;
/tmp/rays-f-image-scalar-vec3-regression-before.log), then candidate. The initial
focused invocation incorrectly included empty @test/test_workspace_lower and
exited1 for that alias, despite executed tests passing. Corrected @check/full
FlowIR/FlowSOP/FlowGPU/benchmark command exits0:
/tmp/rays-f-image-scalar-vec3-focused-corrected.log. No public API/manifest change.

Preserve production diff f-image-scalar-vec3-trial.patch and native loop
f-image-scalar-vec3-loop-arm64.txt. otool of compiled Flow_ir.Packed shows totals
in d12/d14/d16, ascending x/y/z fadd and finite checks, with accumulator stores
after the chunk. No normal-loop float boxing or calls occur; runtime polling
slow paths and checked array accesses remain. Preserved candidate executable
/private/tmp/f-image-scalar-vec3-after.exe SHA256:
7f57dc3c0ee7df36f4c24efbb58fdae0b25f89ebd11fdc4d2b798c88eac05ba5.

Unchanged fixtures and isolated protocol: seven CPU caller samples at1/8 domains;
seven×200 completed GPU producer/consumer/combined frames after ten warmups,
eight-domain capture owner and one-domain uncaptured control owner. No concurrent
builds/tests/active agents. CPU hashes and explicit native readbacks stay outside
warm producer timers; cold publication, parity, resize, replan and close remain
separate rows:

```sh
/private/tmp/f-image-scalar-vec3-after.exe --image-map-captures > specification/performance/f-image-map-captures-scalar-vec3-after.csv 2> specification/performance/f-image-map-captures-scalar-vec3-after-counters.csv
/private/tmp/f-image-scalar-vec3-after.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-recheck-scalar-vec3-after.csv 2> specification/performance/f-image-map-uncaptured-recheck-scalar-vec3-after-counters.csv
```

Both modes exit0. Retain440 data rows (352 capture/88 control),30 native
comparisons with zero maximum error/differing channels/differing pixels, and all
CPU1/8 hash/resource/cook/flatten/resize/replan/close assertions. All210 warm
trial rows have200 frames, no destination uploads and no source-image readbacks.
Counter artifacts have448 capture records/two headers and56 control records/
one header. Seven-trial medians (ms, all-domain producer B/frame):

| Fixture | CPU8 | GPU producer | Consumer | Combined | Producer B |
|---|---:|---:|---:|---:|---:|
| Static1024 points,512² | 4.518032 | 0.651245 | 0.431560 | 1.095630 | 89161 |
| Static1024 points,1024² | 14.573812 | 1.572140 | 0.669611 | 2.529305 | 89161 |
| Static1024 points,2048² | 54.708004 | 4.483265 | 1.543504 | 6.348910 | 89161 |
| Changing1024 points,512² | 4.330873 | 0.754961 | 0.426825 | 1.218365 | 370195 |
| Changing1024 points,1024² | 14.709949 | 1.744375 | 0.669365 | 2.881260 | 370195 |
| Changing1024 points,2048² | 54.460049 | 4.905120 | 1.565270 | 6.973369 | 370195 |
| Static65536 points,1024² | 16.739845 | 2.094190 | 0.663731 | 3.583055 | 89161 |
| Changing65536 points,1024² | 16.317129 | 5.527799 | 0.670545 | 6.560780 | 10413337 |

Large XYZ-write baseline CPU8/GPU producer static17.415047/3.555745 ms,
changing17.284155/6.181384. Uncaptured gradient CPU8/GPU12.115002/1.529535 ms,
33721 B; live capture11.449099/1.534040 ms,32593 B. Static capture89161 B stays
source/pixel-count independent. Changing-large median10413337 B versus
10413280 before is small trial variation, not an allocation reduction claim.

Astra: **“Retain the scalar Vec3 branch.”** Large static seven-sample ranges
3.378–3.679 ms before versus2.067–2.120 ms after do not overlap. Controls,
allocations and all30 parity comparisons remain stable; assembly supports the
intended mechanism. Another unchanged batch is unnecessary for retention.
Changing-source median improves to5.527799 ms, but ranges overlap: do not claim
a precisely repeatable0.654 ms saving there. All seven samples exceed5 ms;
the strict changing-source producer gate remains unmet. The eight-domain CPU
1024² cases pass40 ms. No overall F2.2 or F.md completion is claimed.

Next approved action: fresh source-refresh attribution on this branch with
existing probes/three diagnostic fixtures, seven×200 frames/ten warmups, CPU
caller and node-own timings, P/Cd flattening, write phases/direct reductions,
completed dispatch and conversion. Retain per-trial GC collection-count deltas
only from snapshots outside timing, if available; no per-frame sampling. Counts
may describe variation, not GC elapsed time. Restore probes byte-for-byte; no
further arithmetic/ownership/cache optimization is approved before attribution.

Full F5 native/pixel qualification completes below. Actual display remains1×;
2× goldens are not qualified by this run.

Full F5 native/pixel qualification passes, exit0
(`/tmp/rays-f-image-scalar-vec3-full.log`), with candidate source held fixed:

```sh
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/rays_editor/native_qualification/qualification @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
```

Both complete workspace IR sweeps cover38 standard files,2 actual custom-catalog
executables and13 fixtures at four times/domains1/8. Native image publication,
resident consumers, actual-owner captures, caller-state snapshots, nested source
resolution, capacity64 metadata/data, oversized uncached source, cycle recovery,
Canvas, runtime/presentation and all requested pixel aliases pass. Actual1× only;
2× goldens remain unqualified. No goldens/tolerances/gates are relaxed.

Pre-commit shipping passes, exit0
(`/tmp/rays-f-image-scalar-vec3-ship.log`). Retain the scalar Vec3 branch and
stronger regression with all raw benchmark/assembly artifacts. Changing-source
GPU<5 ms, frozen images, expanded owner coverage, F3 and final audit remain open.

### F2.2 frozen `(exact image)` functional checkpoint (2026-10-09)

Implementation and regressions: `d94b761b`.

The resource owner resolves and validates the current successful display
publication before snapshot lookup. Exact site, plan serial and source
identity/generation/dimensions identify one immutable owned RGBA8 payload and
distinct native image. The existing 64-entry/native-image admissions pin
versions until close; new admission occurs before reading source pixels.
Ordinary CPU image payloads remain independent of GPU display publication.
Explicit snapshot reads are intentional; no warm display measurement includes
them and no timing/allocation gate is claimed by this checkpoint.

Astra: “The functional boundary is acceptable.” Numeric and array exact
semantics, graph image input composition, typed resource/state boundaries and
same-generation source validation remain intact. Focused Flow/graph/SOP checks
pass; static direct/alias/container/called-function/graph-result state cases and
opaque runtime seed/step backstops preserve caller state. Projection input edits
and text round-trip produce the new typed image node.

The native owner test passes: independent CPU blue127, GPU-frozen blue128; same
publication reuses the payload without another read; advance, resize and
identical replan produce distinct versions while the saved composed drawing
Scene renders unchanged bytes. An expired borrowed callback at unchanged source
generation fails twice without readback/allocation; restoring that publication
reuses its snapshot. Nonfinite frame failure rolls back caller state and the
next finite publication recovers. CPU snapshots remain readable after owner
close; resource creation/destruction counts match and native handles return to
baseline.

Both CPU7×3 and qualified GPU65×17 capacity fixtures retain63 frozen versions
plus one mutable source. The65th resource fails twice without another native
image or source read. GPU reads stay63; CPU reads stay0. Saved payload bytes
remain unchanged and cleanup releases every resource. Qualification preserves
the existing1024-element GPU placement floor; the small fixture exercises CPU
snapshot ownership and the larger one exercises GPU readback admission.

Full F5 native/pixel qualification passes, exit0
(`/tmp/rays-f-frozen-exact-full.log`), with candidate source held fixed:

```sh
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/rays_editor/native_qualification/qualification @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
```

Both complete workspace sweeps cover38 standard files,2 actual custom-catalog
executables and13 fixtures at four times/domains1/8. Native owner/capture/Canvas,
oversized-source, runtime and requested pixel checks pass. Ordinary snapshot
consumers additionally cover CPU exact image/map and image/noise through SOP,
drawing and texture command parity at domains1/8. Corrected focused checks pass;
an earlier mixed command reported an undefined `@test/test_workspace_images`
alias, corrected by building and running that existing test executable directly
and completing the full `@runtest` above. Pre-commit shipping passes, exit0
(`/tmp/rays-f-frozen-exact-ship.log`). The teaching README changes a watched
sketch tree, so shipping also reruns and passes the complete38+2+13 workspace
sweep on the final tree. Dependency gate and printing/threading checks pass.
Actual display remains1×;2× goldens remain unqualified.
Changing-source GPU<5 ms, expanded owner coverage, F3 and final audit stay open.

### F2.2 actual packed-owner coverage and graph state identity (2026-10-09)

Implementation and regressions: `78a646f6`.

Apple M1/Macmini9,1, OCaml5.3, Dune dev; native Metal, actual1× display.
These are correctness fixtures at domains1/8, not timing measurements.

```sh
_build/default/tools/check.exe @check lib/flow/test_state.exe
_build/default/lib/flow/test_state.exe
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_sop/runtest @lib/flow_graph/runtest @lib/rays_editor/native_qualification/runtest-native
```

The pure regression fails before the correction
(`/tmp/rays-f-graph-state-before.log`, exit2): live inline graph refs add a
caller-derived state entry instead of reading the referenced static instance.
The shared evaluator now stores its existing cid in each private cell and uses
it for live hits of the normalized graph/override key. The body is reevaluated;
cached static results are not returned. Unknown live keys retain the previous
caller-instance fallback; this is not proof of independent state for arbitrary
dynamic override tuples. Astra approves this bounded correctness fix.

Afterward, compiled and reference tests agree for default inline/bound refs,
two independent known override tuples, repeated/coerced-equivalent refs,
opposite force orders, unchanged private snapshots and static instance identities,
host ticks and value frames (`/tmp/rays-f-graph-state-after.log`, exit0).
Existing L14 geometry instance/node-sharing checks remain green.

Actual packed source inspection proves3 prototype points and2 instances.
The capture oracle computes all6 transformed P values, first/fourth element
order and copied Cd independently of the instance materializer and kernel.
Complete CPU bytes match at domains1/8 under two overrides and time/state changes.
GPU maps and their composed parent renders match complete oracle bytes within
the existing one-channel tolerance; all24 map comparisons measure maximum0.
Same-frame fresh forks and restored caller state refresh correctly. Resident
child CPU storage remains0, warm calls leave source cook/flatten/Host/native
pixel-read counters unchanged, unrelated fixed renders retain identity/generation,
and retained CPU/frozen bytes survive later requests and clean resource close.

The state-driven3→2-point fixture produces `E_ARRAY_RANGE` twice for index2,
invalidates the prior parent publication and leaves caller state, resources and
saved bytes unchanged. A valid same-frame fresh fork recovers its pixels and
native image identity at domains1/8. Cycle recovery additionally rebinds a changed
plan at both domain counts while retaining the old CPU payload.

A negative probe changes only the display source's first materializer creation
to use the unexpanded root. The new packed-owner fixture immediately fails with
`E_ARRAY_RANGE` (`/tmp/rays-f-owner-materializer-negative.log`, exit1).
The saved source is restored byte-for-byte (`cmp`, exit0); restored focused
checks pass (`/tmp/rays-f-owner-materializer-restored.log`, exit0). Final focused
Flow/SOP/graph/native checks after review corrections pass
(`/tmp/rays-f-owner-coverage-focused.log`, exit0). Intentional inspection reads
occur before the warm counters are sampled. Cleanup destroys resource images,
then owner canvases, then GPU storage; creation/destruction counts match and
native handles return to baseline. No gate/tolerance/golden is changed, and no
new performance claim is made. Broad qualification and shipping follow below.

Full F5 native/pixel qualification passes, exit0
(`/tmp/rays-f-owner-coverage-full.log`), with candidate source held fixed:

```sh
_build/default/tools/check.exe @all @runtest @smoke @lib/rays/runtest-native @lib/flow_gpu/runtest-native @lib/rays_editor/runtest-native @lib/rays_editor/native_qualification/qualification @lib/scene_execution/runtest-native @test/runtest-native @test/test_workspace_pixels @examples/sop_gallery/test_workspace_pixels @sketches/voxel_wall/test_workspace_pixels @examples/sop_gallery/test_scene3_float32_gallery @lib/runtime/native_qualification/qualification @lib/pxui/test_ui_parity
```

Both complete workspace sweeps cover38 standard files,2 actual custom-catalog
executables and13 fixtures at four times/domains1/8. Expanded native owner,
oversized capture, retained Canvas, runtime/presentation and requested pixel
checks pass. Pre-commit shipping passes, exit0
(`/tmp/rays-f-owner-coverage-ship.log`). Actual display remains1×;2× goldens
remain unqualified.
Changing-source GPU<5 ms, F3≤50.600 ms and final audit remain open.

### F2.2 scalar Vec3 source-refresh attribution and current production gates (2026-10-09)

Qualification evidence and reproducible probes: `625b8eaf`.

Apple M1/Macmini9,1, OCaml5.3, Dune dev, native Metal, actual1× display.
Production checkpoint186c0e1f (implementation78a646f6); no production optimization
is made in this checkpoint. Astra approves the same temporary nine-file probes
on the retained scalar Vec3 branch, then explicitly requests the ordinary
uninstrumented full matrix before another optimization. Each benchmark runs
alone with no builds/tests/agents.

```sh
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest @lib/flow_sop/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-capture-attribution-scalar-vec3-whole.csv 2> specification/performance/f-image-map-capture-attribution-scalar-vec3-counters.csv
# Restore the nine source files byte-for-byte, rebuild the ordinary harness.
_build/default/tools/check.exe @check @lib/flow/runtest @lib/flow_ir/runtest @lib/flow_sop/runtest tools/bench_workspace_lower.exe
_build/default/tools/bench_workspace_lower.exe --image-map-captures > specification/performance/f-image-map-captures-owner-checkpoint-recheck.csv 2> specification/performance/f-image-map-captures-owner-checkpoint-recheck-counters.csv
_build/default/tools/bench_workspace_lower.exe --image-map-connected-1024 > specification/performance/f-image-map-uncaptured-owner-checkpoint-recheck.csv 2> specification/performance/f-image-map-uncaptured-owner-checkpoint-recheck-counters.csv
```

Diagnostic build and run exit0 (`/tmp/rays-f-scalar-refresh-probes-build.log`).
The saved probe patch is `f-image-map-capture-attribution-scalar-vec3.patch`;
the run additionally writes its phase `.csv` and `-gc.csv`. All1050 phase rows,
90 whole rows,71 counter rows and69 GC rows complete. Three fixtures: static/
changing65536 points at1024² and gradient; CPU1/8 seven warm samples, GPU8
seven×200 completed frames after10 warmups. Nine full native pixel comparisons
have zero differing channels/pixels, CPU1/8 hashes match, and ownership/capture/
resize/replan/close assertions pass.

Changing-source diagnostic medians, ms/frame:

| Interval and coverage | Prior XYZ-loop diagnostic | Scalar Vec3 diagnostic |
|---|---:|---:|
| Complete producer, initial domain | 6.292236 | 4.349805 |
| Packed preparation, inclusive | 4.157250 | 2.473027 |
| Materialization, inclusive | 2.047064 | 1.683940 |
| Line, all-cook-domain node-own | 0.341308 | 0.294302 |
| Write Cd, all-cook-domain node-own | 1.697543 | 1.381015 |
| Validation, initial domain inclusive | 0.227145 | 0.151922 |
| XYZ storage, initial domain inclusive | 0.327947 | 0.253010 |
| P / Cd flatten, initial domain inclusive | 0.306879 / 0.310577 | 0.234637 / 0.233426 |
| P / Cd ordered traversal, initial domain inclusive | 0.678835 / 0.677707 | 0.121803 / 0.121765 |
| Completed execution, inclusive | 1.235315 | 0.980209 |
| Sink conversion, inclusive | 0.811477 | 0.806959 |

These nested/inclusive intervals cannot be added together. Initial-domain clocks
do not observe CPU worker internals; Session node-own durations retain their
separate coverage. Astra checks all105 applicable parent/child relationships;
none violates containment. All21 warm producer counter rows have200 status reads
and no resource creation/upload/output-readback deltas.

Diagnostic changing trials decline5.654016/5.825809/4.696125/4.349805/4.057915/
4.133999/4.033060 ms alongside lower materialization and allocation-related
phases. Per-trial `Gc.quick_stat` snapshots occur after the pre-allocation marker
and before the start clock, then after the end clock and before the post-allocation
marker. Existing `Gc.stat` boundary collections are excluded from those deltas.
The snapshots add diagnostic allocation overhead; sampled counters can lag and
do not measure GC time. Minor counts18/18/18/18/18/19/20, major0/0/0/0/0/1/4,
compactions0; later faster trials have more collections, so these counts do not
establish the timing cause. This diagnostic4.349805 ms is not a gate result.

All nine production files are restored from the fresh archive byte-for-byte
(`cmp`, exit0), including every temporary API and GC/harness probe. The patch
passes `git apply --check`; restored focused checks/rebuild pass, exit0
(`/tmp/rays-f-scalar-refresh-restored.log`). No temporary source change remains.

The requested unchanged ordinary harness then completes the full eight-cell
capture matrix and both1024² controls. Seven repetitions,200 GPU frames per
trial,10 warmups, CPU1/8; producer, consumer and end-to-end clocks stay separate.
All440 data rows,70 CPU domain-hash pairs,30 complete zero-difference native
snapshots,210 warm resource rows and168 capture rows pass. Static sources reuse
capture data; changing sources record200 cooks/400 flattens. Warm uploads,
image readbacks and GPU resource creations remain0. Cold owner/preparation,
resize/replan, snapshot and teardown rows remain in the raw files.

| Fixture | CPU8 ms | GPU producer ms | Consumer ms | End-to-end ms | Producer B/frame |
|---|---:|---:|---:|---:|---:|
| Static1024 points,512² | 5.871058 | 0.586179 | 0.363184 | 1.044865 | 89161 |
| Static1024 points,1024² | 16.512156 | 1.476744 | 0.616235 | 2.383735 | 89161 |
| Static1024 points,2048² | 56.735992 | 4.441091 | 1.348500 | 6.187460 | 89161 |
| Changing1024 points,512² | 6.511927 | 0.732579 | 0.383960 | 1.170195 | 370195 |
| Changing1024 points,1024² | 17.276049 | 1.644295 | 0.613824 | 2.616020 | 370195 |
| Changing1024 points,2048² | 58.954000 | 4.855405 | 1.282926 | 6.776235 | 370195 |
| Static65536 points,1024² | 18.973112 | 1.837995 | 0.616424 | 3.087415 | 89161 |
| Changing65536 points,1024² | 19.464016 | 4.755571 | 0.603240 | 5.575650 | 10413406 |

Uncaptured gradient CPU8/producer13.434172/1.408764 ms,33721 B/frame;
live capture13.276100/1.430500 ms,32593 B/frame. Fixed-source producer allocation
remains independent of pixel count. All existing1024² CPU<40 ms and GPU
producer<5 ms median gates pass; CPU2048² has no40 ms gate.

Astra: **“PASS: close the changing-source GPU median gate for this qualified
configuration.”** Its seven samples are5.581995/5.610975/5.068265/4.568505/
4.755571/4.522350/4.344505 ms: median4.755571, range4.344505–5.610975,
three of seven above5 ms. This is median qualification, not a worst-case
guarantee. The separate end-to-end median5.575650 ms is retained. These are
current qualification results; no measured improvement is attributed to
unchanged performance code. No further optimization or repeat batch is required
to satisfy this median gate. All raw rows/outliers remain in the two
`f-image-map-*-owner-checkpoint-recheck*` matrix/control families above.

The preceding owner's full F5 evidence
(`/tmp/rays-f-owner-coverage-full.log`) applies to the byte-identical production
source. Pre-commit shipping passes, exit0
(`/tmp/rays-f-scalar-refresh-gates-ship.log`). Actual1× only;2× goldens remain
unqualified.
F3≤50.600 ms and the final audit remain open.

### F3 attribute storage-kind attribution (2026-10-09)

Apple M1/Macmini9,1, OCaml5.3, Dune dev; source checkpoint51735051.
No production optimization is applied. Astra approves attribution of existing
attribute concatenation by storage kind and, where present, individual packed
vector planes. The probes preserve the existing argument expressions and
evaluation order. Metadata and reports stay outside individual timers;
separate bounded buffers and nested containment checks fail on overflow or
inconsistent samples. Training and measured cooks remain distinct.

The fresh production baseline executable is preserved before probes:
`/private/tmp/f-merge-attr-baseline-51735051.exe`, SHA256
`1200a25c7ae20f61bbdf9f61f096408ec469453f2ac835e31c9f5486f4e7d9c7`.
The diagnostic executable is `/private/tmp/f-merge-attr-diagnostic-51735051.exe`,
SHA256 `c6ebc1e4328af141f4e30097c4590295b49ea56ba252eb453a5dbc193c457c4d`.
The source archive is `/private/tmp/rays-f-merge-attribute-original-51735051.tar`;
the reproducible four-file probe patch is `f-merge-attributes.patch`.

```sh
_build/default/tools/check.exe @check @lib/rdk/runtest @lib/procedural/runtest tools/bench_workspace_lower.exe
# After diagnostic build/preservation, restore the four files byte-for-byte.
_build/default/tools/check.exe @check @lib/rdk/runtest @lib/procedural/runtest tools/bench_workspace_lower.exe
# Seven pairs, trial0..6; even diagnostic/baseline, odd baseline/diagnostic.
# task_kind selects the preserved executable and matching output prefix.
RAYS_BRANCH_NODE_TIMES=1 \
RAYS_MERGE_PHASES_FILE="${task_prefix}-phases.csv" \
RAYS_MERGE_ATTRIBUTES_FILE="${task_prefix}-attributes.csv" \
"/private/tmp/f-merge-attr-${task_kind}-51735051.exe" --branches 1 learned \
  > "${task_prefix}.csv" 2> "${task_prefix}-nodes.csv"
```

Prefixes are `specification/performance/f-merge-attributes-${task_kind}-${trial}`.
Baseline ignores both diagnostic output variables and produces only whole/node
CSVs. No build, test or agent work runs during the isolated measurement batch.
All14 process exits are0 in `f-merge-attributes-status.csv`; all42 raw CSVs,
including every outlier, are retained. Each process runs domains1/8 with one
measured learned cook after the unchanged untimed learning/cache-clear/pool
warmup protocol. Reporting occurs after the whole-cook timer.

Independent raw validation checks28 whole rows,196 node rows,196 exclusive
phase rows and28 attribute rows. Every geometry hash remains
`67c129ecc130f8881a2eaf92c053b64c`; points2,000,000 and fanouts0/1 at domains1/8.
All seven phases and their original call counts, finite/nonnegative durations,
phase sums within complete merge, and measured merge within merge-own pass.
All four cook/domain samples per trial contain exactly one attribute:
primitive Int `__flow_src`, inputs1,996,002/1,996,002, output3,992,004, one whole
row and no plane row. The attribute interval is contained in the matching
aggregate attribute interval and complete merge. This corrects the older
extra48 MB normals estimate: this fixture has no vector/normal attribute.
Its source-tag output is31,936,032 bytes. Vector-plane probes are present in
the reproducible patch but this fixture does not exercise them.

| Median | Production1 | Production8 | Diagnostic1 | Diagnostic8 |
|---|---:|---:|---:|---:|
| Whole cook, ms | 151.468992 | 51.383018 | 152.385950 | 63.387871 |
| Existing merge-own, ms | 59.101105 | 27.511835 | 60.902119 | 38.489103 |
| Caller allocation, bytes | 503647672 | 374045704 | 503653376 | 374061120 |
| Program allocation, bytes | 503647960 | 505436208 | 503653664 | 505443224 |

Production eight-domain whole samples are55.944920/50.595999/73.501110/
51.383018/49.017906/49.971819/57.826042 ms, range49.017906–73.501110.
Diagnostic eight-domain range48.792124–72.051048 ms. Median paired diagnostic
minus production whole differences are0.710011/10.046005 ms at domains1/8;
they retain scheduling/GC/noise effects and do not isolate pure probe cost.
No timing cause is inferred from these differences.

| Diagnostic measured interval, ms | Domains1 | Domains8 |
|---|---:|---:|
| Complete merge | 59.604168 | 34.710884 |
| Allocation | 7.734060 | 12.983084 |
| Position blits | 1.641989 | 1.631737 |
| Joined vertex rewrites | 30.266047 | 7.218838 |
| Joined primitive rewrites | 10.026932 | 2.422810 |
| Kind blits | 0.123024 | 0.132799 |
| Aggregate attributes | 9.629011 | 6.664991 |
| Source-tag Int concatenation, inclusive | 9.627819 | 6.662130 |
| Remaining metadata/wrapping/groups/construction/probes | 0.010252 | 0.043631 |

Separate medians must not be summed; attribute time nests within aggregate
attributes. Complete training intervals are77.728987/33.506870 ms, with
source-tag concatenation8.607149/6.443024 ms, separately labeled in raw rows.

Diagnostic focused checks/build pass, exit0
(`/tmp/rays-f-merge-attributes-probes-build.log`). All four source files are
restored byte-for-byte from the fresh archive (`cmp`, exit0), and the patch
passes `git apply --check`. Restored full focused checks/rebuild pass, exit0
(`/tmp/rays-f-merge-attributes-restored.log`). No temporary API, Unix dependency
or timer remains in production. The preceding full F5 checkpoint applies to
byte-identical production source. Shipping passes, exit0
(`/tmp/rays-f-merge-attributes-ship.log`).

Astra: **“not met, try constructing newly generated source tags once on the
merged output.”** It audits28 whole and28 attribute rows and corrects its prior
normal estimate. Its next approved trial in shared `Mesh_merge.merge` calls
`merge_plain` on original nonempty-list inputs only for a valid nonblank source
name when no input has that primitive attribute. Allocate the final tag array
once with `source_base`, fill subsequent ranges with `source_base + input_index`,
and append through existing owned-attribute/geometry APIs. This removes temporary
per-input tags and their concatenation; it adds no parallel loop or dependency.
Existing/mixed tags, invalid names and the empty-list case keep the current
path. Empty inputs still consume an index; cancellation is checked before
allocation and every range. Ordering and error precedence are the main risks.

Before implementation, add one independent primitive-rich merge regression with
empty inputs, negative base, full geometry/input bytes at domains1/8, fallback
and cancellation. A one-domain tagged-minus-untagged allocation ceiling of
`8 × output_primitive_count + 4096` bytes must fail current code. Then run the
established seven-process before/after learned/off/pieces matrix and reversed-
order learned comparison using the fresh preserved baseline, retaining all rows
and allocations. The unchanged≤50.600 ms whole learned-eight gate decides;
no optimization or unreachable verdict is claimed at this attribution checkpoint.
