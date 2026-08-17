# Performance and memory architecture

Prismel is designed for live creative coding and high-density deterministic
offline generation. Public APIs remain immutable; implementation hot paths may
use locally owned mutation and packed storage without exposing mutable aliases.

## Workload classes

| Class | Typical scale | Primary constraint |
|---|---:|---|
| Per-frame interaction | 60–240 updates/s | predictable latency and bounded allocation |
| Dense procedural mesh | 1–100 million vertices/indices | packed memory, linear passes, coarse parallelism |
| Scalar/voxel field | 128³–1024³ samples | streaming/slab memory and parallel field evaluation |
| Offline sequence | thousands of frames | byte determinism and no cumulative cache/resource growth |
| Software raster | millions of samples/frame | allocation-free pixel/sample loops and early rejection |

### SOP graph interaction smoke baseline

The focused graph test includes a 2,001-node/2,000-wire fan-in graph, validates
packed graph cardinality and off-screen tile culling, and materializes one
scene. On Apple M1 arm64, OCaml 5.3.0, Dune 3.24.1, the complete focused test
(including smaller interaction regressions) measured 0.08 s wall time, 30.2 MB
maximum RSS, and 13.4 MB peak footprint on 2026-08-06:

```sh
dune build test/test_pxui_graph.exe
/usr/bin/time -l _build/default/test/test_pxui_graph.exe
```

This is a repeatable scale smoke baseline, not a claim that every wire-heavy
graph has constant frame cost: scene traversal remains O(nodes + wires), while
unchanged graph replacement is an identity fast path and node scene allocation
is restricted to visible tiles.

## Representation rules

- Mesh positions and normals are retained as structure-of-arrays XYZ float
  planes. Core renderer access borrows those planes without copying;
  user-facing list functions and the legacy boxed private view are explicit
  convenience/materialization boundaries, never renderer input. Packed
  generators can transfer plane ownership directly, avoiding a second boxed
  output at peak memory.
- Dense numeric working sets use packed float/integer arrays or Bigarray.
  Record/list forms are acceptable for small control geometry, diagnostics,
  and API boundaries.
- Known-size generators allocate exact output arrays. Variable-size algorithms
  use geometric-growth builders and trim once.
- Topology uses stable integer indices, specialized integer/edge hashes, and
  compact adjacency. Algorithms must not repeatedly recover topology from
  boxed face lists.
- Persistent spatial structures are for incremental/query workloads. Bulk
  construction may use mutable staging and freeze once.
- The interactive SOP graph stores tiles and edges in compact arrays with a
  stable-ID lookup only when graph identity changes. Unchanged frames reuse the
  presentation value directly; parameter graph replacement preserves manual
  tile positions, and scene construction allocates node primitives only for
  tiles intersecting the visible graph bounds. Navigation and node movement do
  no procedural cook work.
- `Voxel3` stores immutable occupancy in 4,096-bit pages keyed by linear cell
  ranges. Persistent edits copy one 512-byte page, while `Voxel3.Builder`
  mutates owned pages and freezes once. `Voxel3.init` evaluates pure dense
  predicates in deterministic parallel page partitions.
- `Svo3` stores sparse occupancy in a shared immutable 8-way trie. Branches use
  an 8-bit child mask plus a compact child array; point lookup and persistent
  edits touch only one root-to-leaf path. A leaf stores the complete Morton
  path, eliding every unary tail below the last actual branch. Bulk construction
  sorts and deduplicates 60-bit Morton paths and freezes the compact trie
  directly, without an eight-slot mutable staging array per temporary node.
- `Iso3.extract` streams deterministic XY-plane windows in two passes. It
  retains exact-sized output and finite-difference normals without the former
  four full XYZ scalar/gradient volumes; fixed ring buffers make temporary
  allocation and auxiliary sampling memory O(XY). Its final positions and
  normals are filled directly into the mesh's packed XYZ planes. `Iso3.Field` evaluates
  built-in constant, sphere, gyroid, and metaball fields directly without
  per-sample point allocation; custom fields borrow one packed XYZ sample per
  domain.
- Extrude, lathe, and sweep generators precompute vertex/index cardinality and
  fill owned arrays directly. Angle-aware smoothing uses indexed triangle
  arrays and scalar normal accumulators rather than materializing face and
  index lists.
- Duplicate-vertex merging uses exact-position hashing at zero tolerance and a
  packed open-addressed spatial-cell table at positive tolerance. Candidate
  chains contain representatives only, preserve the earliest compatible
  source, and still compare every present normal, color, and UV attribute so
  seams are not collapsed. Extreme finite coordinate/epsilon ratios use exact
  float-bit components instead of overflowing the grid index.
- Mesh topology and repair traverse borrowed triangle arrays. Connected
  components are joined directly from edge incidence with union-find, and
  filtering/reorientation fills exact owned index arrays. T-junction repair
  builds one 60-bit Morton-sorted hierarchy with packed subtree bounds over
  finite vertices, performs bounded edge queries, and splits faces iteratively
  in stable source order instead of rescanning every vertex and restarting the
  complete face list per split.
- PDK reverse topology uses packed integer CSR/half-edge planes and a
  specialized open-addressed integer edge table. Geom weld now routes through
  PDK Fuse, cutting the 200,000-point one-domain fixture from 64.5 ms and
  78.9 MB allocated to 50.2 ms and 48.2 MB with identical cardinality.
- Filtered exact PDK orientation predicates expose packed SoA/index calls so
  the certified fast path does not box coordinates. Five million release-build
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
  `PRISMEL_PREDICATE_BENCH_COUNT=1000000
  PRISMEL_PREDICATE_BENCH_REPEATS=5 dune exec --profile release
  tools/bench_predicates.exe`.
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
  classification. Set `PRISMEL_BOOLEAN_SELF=1` to reproduce this mode.

  ```sh
  PRISMEL_BOOLEAN_PAIR_COUNT=50000 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BOOLEAN_GRAIN=1024 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_constraints.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4 for exact scheduling regression.
  ```
- `tools/bench_boolean_seam.exe` isolates packed curve/coincident-facet
  materialization from an already prepared exact complex. On 10,000 isolated
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
  PRISMEL_BOOLEAN_PAIR_COUNT=50000 PRISMEL_BOOLEAN_REPEATS=5 \
  PRISMEL_BOOLEAN_GRAIN=16384 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_seam.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4 for exact scheduling regression.
  ```
- `tools/bench_boolean_arrangement.exe` isolates the formerly quadratic work
  hidden by the ordinary one-cut-per-face refinement fixture. Its source face
  receives many spatially independent exact LPI segments, so required output
  is linear. The prior implementation linearly deduplicated every point, ran
  every segment pair through exact projected predicates, and then tested every
  point against every segment. On 1,000/2,000 cuts it took 114.890/419.879 ms
  and allocated 24,248,488/96,489,504 bytes. Certified two-axis interval
  sweeps plus stable exact sort/canonicalization reduce those medians to
  3.826/8.037 ms, a 30.0x/52.2x speedup, while allocation falls to
  3,404,656/7,110,056 bytes. The exact hashes remain
  `3894907407311697473` and `2548620122607153265`.

  `PRISMEL_BOOLEAN_ORACLE=1` runs the retained unculled traversal through the
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
  PRISMEL_BOOLEAN_SEGMENTS=10000 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_arrangement.exe
  # Add PRISMEL_BOOLEAN_ORACLE=1 for the exact compatibility oracle.
  # Add PRISMEL_BOOLEAN_STABLE_BVH=1 to force the packed indexed path.
  # Add PRISMEL_BOOLEAN_FIXTURE=multiway for coincident-event stress.
  ```
- `tools/bench_boolean_cdt.exe` isolates point insertion, constraint recovery,
  and exact Delaunay repair on one face with many independent constraints. The
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
  PRISMEL_BOOLEAN_SEGMENTS=500 PRISMEL_BOOLEAN_REPEATS=5 \
  PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_cdt.exe
  # Add PRISMEL_BOOLEAN_POINT_SCAN=1 for the exact point-location oracle.
  # Add PRISMEL_BOOLEAN_EDGE_SCAN=1 for exhaustive constraint recovery.
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
  PRISMEL_BOOLEAN_PAIR_COUNT=10000 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BOOLEAN_GRAIN=64 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_refinement.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4.
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
  PRISMEL_BOOLEAN_PAIR_COUNT=50000 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BOOLEAN_GRAIN=256 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_coplanar.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4; do not run the timings concurrently.
  ```
- Complex/radial assembly is measured on 10,000 independent transverse
  triangle pairs (80,000 exact vertices, 70,000 merged facets, 140,000 edges).
  Avoiding per-edge order arrays for one/two-chart edges, caching chart halves,
  using source-face coplanarity, and adding implicit-point identity fast paths
  reduced radial ordering from 264.524 ms and 386,890,640 bytes to 6.586 ms
  and 17,890,184 bytes with unchanged hash `45657678768556593`. Exact angular
  predicates are now paid only by genuine three-or-more-chart bundles.

  ```sh
  PRISMEL_BOOLEAN_PAIR_COUNT=10000 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BOOLEAN_GRAIN=64 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_complex.exe
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
  PRISMEL_BOOLEAN_PAIR_COUNT=10000 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BOOLEAN_GRAIN=256 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_pipeline.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4; the exact hash must match.
  # Set PRISMEL_BOOLEAN_COMPONENT_INDEX=0 for the private exhaustive oracle.
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
  `PRISMEL_BOOLEAN_SELF=1` with `tools/bench_boolean_pipeline.exe` to measure
  the resolved policy.
- `tools/bench_boolean_materialization.exe` isolates exact seam-facet candidate
  marking, strict independent contraction planning, and the complete rounded
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
  PRISMEL_BOOLEAN_PAIR_COUNT=20 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_materialization.exe
  PRISMEL_BOOLEAN_PAIR_COUNT=1 PRISMEL_BOOLEAN_REPEATS=5 \
  PRISMEL_BOOLEAN_COLLAPSE=1 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_materialization.exe
  # Repeat both with PRISMEL_BENCH_DOMAINS=4; hashes must match.
  ```
- Full Boolean payload transfer is isolated by
  `tools/bench_boolean_payload.exe`. The 10,000-disjoint-pair fixture has
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
  PRISMEL_BOOLEAN_PAIR_COUNT=10000 PRISMEL_BOOLEAN_REPEATS=3 \
  PRISMEL_BOOLEAN_GRAIN=256 PRISMEL_BENCH_DOMAINS=1 \
    dune exec --profile release tools/bench_boolean_payload.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4; the exact hash must match. Set
  # PRISMEL_BOOLEAN_EDGE_GROUPS=0 to isolate the no-native-edge schema.
  ```
- The promoted `Pdk.Boolean.run` product boundary is measured end to end by
  `tools/bench_boolean_product.exe`: exact arrangement, difference extraction,
  complete payload/schema transfer, seam construction, zero-threshold rounded
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
  PRISMEL_BOOLEAN_PAIR_COUNT=10 PRISMEL_BOOLEAN_REPEATS=9 \
  PRISMEL_BOOLEAN_GRAIN=32 PRISMEL_BENCH_DOMAINS=1 \
    opam exec --switch=. -- dune exec --profile release \
      tools/bench_boolean_product.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4; hashes must match.
  ```
- The Hython clean-room scale harness also compares the full release product
  against Houdini 22.0.368 on the same triangulated operands. On an Apple M1
  (8 cores, 16 GiB), macOS 26.2, OCaml 5.3.0, and Dune 3.24.1, the 50-plane
  centered shattered cube takes 0.346 s in Prismel versus a 0.355 s Houdini
  median fresh-node cook. The jittered 50-plane case, which produces about
  176,000 triangles, takes 2.702 s versus 3.006 s. The dense VDB-remeshed
  pig-head/rubber-toy difference remains the open performance gate: at about
  87,000 input triangles Prismel takes 0.308 s versus 0.222 s, and at about
  244,000 input triangles it takes 0.922 s versus 0.443 s. The 244,000-input
  result is closed, exactly identical between one and eight domains, has the
  same 93,721-point/187,446-triangle cardinality as Houdini, and differs by at
  most 2.98e-8 in the canonical triangle-coordinate comparison. Prismel's
  measured 87,000-to-244,000 time exponent is 1.064 and allocation exponent is
  0.954, so the remaining issue is constant work rather than evidence of
  superlinear growth over that interval.

  The next optimization pass must first split
  `verify_unchanged_extraction` into measured materialized-value, closed
  incidence, exact orientation, duplicate-facet, verification-index,
  candidate-traversal, and exact narrow-phase costs. The leading hypothesis is
  redundant construction and traversal of a general whole-output
  `Surface_index` after extraction. Test a verification-specific packed index,
  reuse of extraction ancestry/index data, or safe overlap with independent
  payload work; retain all exact post-rounding orientation, duplicate,
  incidence, and non-adjacent-contact guarantees. Do not accept a faster path
  until output hashes, one/eight-domain identity, closure, canonical surface
  error, and the six-level exponent gate remain unchanged.

  ```sh
  python3 tools/houdini/compare_dense_boolean.py \
    /tmp/prismel-dense-boolean
  python3 tools/houdini/compare_dense_boolean.py \
    /tmp/prismel-dense-boolean --reuse-existing
  ```
- The subdivided noisy-plane shatter reference uses identical ordinary OBJ
  operands in Houdini Apprentice 22.0.368 and `tools/boolean_stress.exe`: a
  2.6-unit cube, 50 quaternion-oriented 4.8-unit grids, two segments per axis,
  deterministic 0.45 center jitter, frequency 0.27, and factor 0.35. Houdini
  Boolean 2.0 (`Shatter`, `Pieces of A`, solid/surface, resolve B, no
  detriangulation) emits 15,360 closed connected pieces, 149,177 points, and
  236,912 triangles with no boundary, odd-incidence, or non-manifold edges. Its
  one-sample fresh-node cook is 3.505992 s. Prismel's one-domain release
  Difference solid/surface cook on those exact OBJ files takes 11.166792 s,
  allocates 4,364,346,248 current-domain bytes, and emits 237,040 shared-seam
  triangles. Thus this fixture is an open topology-parity and 3.19x performance
  gate, not a parity claim. Factor 0.65 is deliberately not the sketch default:
  Houdini's corresponding 14,415-piece result contains one non-manifold edge,
  while Prismel's closed-cell materialization refuses that setting. Reproduce
  the clean reference with the commands below. As a focused segments-control
  fixture, both engines exactly emit 26 pieces, 956 points, and 1,808 triangles
  for five planes, four segments per axis, frequency 0.27, and factor 0.35. A
  higher-curvature interactive fixture with 14 planes, ten segments per axis,
  frequency 0.993, and factor 0.631 also matches Houdini exactly at 463 closed
  connected pieces, 16,876 points, and 31,900 triangles, with no boundary,
  odd-incidence, or non-manifold edges. Its fresh Houdini cook is 0.193572 s on
  the recorded reference machine. PDK's one-domain release median over three
  cooks of the exact Houdini-authored OBJ operands is 1.021848 s with
  448,566,912 current-domain allocated bytes, a measured 5.28x time gap. The
  raw shared-seam PDK result has 4,520 points and the sketch's packed-shard
  split expands it to the matching 16,876 points without recooking the
  Boolean. The sketch assigns every cutter primitive a stable integer ID
  before the Boolean and consumes the kernel's exact primitive ancestry when
  assembling packed shards. It then
  edge-component-splits equal side signatures because curved surfaces can
  produce disconnected regions with the same signature. A floating
  point-to-surface proximity test is not an acceptable ancestry substitute.

  The interactive sketch now measures responsiveness independently from cook
  throughput. On the same Apple M1 (8 logical cores, 16 GiB), OCaml 5.3.0,
  Dune 3.24.1, default dev profile, the in-process 50-plane/two-segment noisy
  shatter produced 15,361 closed cells, 149,228 points, and 237,012 triangles.
  Its background cook/preparation took 11.179 s while the initial-domain UI
  advanced 648 frames; whole-process wall time was 13.586 s with 274% CPU.
  The former synchronous update boundary necessarily advanced zero frames for
  the entire cook. This is a responsiveness result, not a Boolean throughput
  improvement: one foreground domain remains dedicated to the SDL loop, the
  background context reserves one hardware domain, and superseded requests
  are cancelled and discarded.

  ```sh
  time PRISMEL_RENDER_TARGET=headless PRISMEL_SHATTER_FRAMES=1 \
    dune exec sketches/shattered_cube/main.exe
  ```

  ```sh
  "$PRISMEL_HYTHON" tools/houdini/shattered_cube_reference.py \
    /tmp/prismel-wavy-shatter-reference-50-f035 --planes 50 \
    --grid-segments 2 --offset-jitter 0.45 \
    --noise-frequency 0.27 --noise-factor 0.35 --repeats 1
  dune exec --profile release tools/boolean_stress.exe -- \
    --case wavy50_f035 \
    --left-obj /tmp/prismel-wavy-shatter-reference-50-f035/shattered_cube_left.obj \
    --right-obj /tmp/prismel-wavy-shatter-reference-50-f035/shattered_cube_right.obj \
    --operation difference --right-surface \
    --resolve-right-self-intersections --domains 1 --repeats 1 --grain 2
  "$PRISMEL_HYTHON" tools/houdini/shattered_cube_reference.py \
    /tmp/prismel-wavy-shatter-reference-14-s10 --planes 14 \
    --grid-segments 10 --offset-jitter 0.45 \
    --noise-frequency 0.993 --noise-factor 0.631 --repeats 1
  dune exec --profile release tools/boolean_stress.exe -- \
    --case wavy14_s10 \
    --left-obj /tmp/prismel-wavy-shatter-reference-14-s10/shattered_cube_left.obj \
    --right-obj /tmp/prismel-wavy-shatter-reference-14-s10/shattered_cube_right.obj \
    --operation difference --right-surface \
    --resolve-right-self-intersections --domains 1 --repeats 3 --grain 2
  ```
- The Boolean stability runner's standard-density campaign additionally covers
  mandatory binary64 representability repair on an explicitly self-resolved
  seven-torus cutter bank. All 24 products are exact between one and four
  domains. Four-domain medians for the repaired bank range from 0.342 s
  (reverse subtraction) to 2.357 s (9,776-primitive Shatter); the measured complete
  24-row campaign peaks at 119,000 KiB RSS. The repaired Shatter formerly
  required 27.137 s and 5.94 GB of current-domain allocation at one domain
  during singleton speculative search; disjoint one-ring batching reduces it
  to 4.567 s and 1.11 GB at one domain, or 2.357 s and 455 MB current-domain
  allocation at four domains. These are pathological repair-path figures, not
  a broad Houdini comparison.
- Fuse discovers earliest-representative proximity clusters in stable point order. Cluster
  member CSR planes make each numeric reduction independent and parallel while
  preserving the exact source-order summation for every domain count. Its
  expected complexity is O(points + neighboring candidates + payload), with an
  explicitly documented quadratic worst case for a single dense tolerance
  neighborhood.
- Fuse and Facet normal consolidation share that one private packed clustering
  core. Discovery arrays are reused as representative, size, and CSR cursor
  planes after their spatial phase instead of allocating phase-local copies.
- The fixed-target Fuse planner builds one packed target-cell table, then runs
  allocation-free candidate searches over disjoint query ranges. On the
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
  `PRISMEL_PDK_OPS_FILTER=fuse_target_closest_snap
  PRISMEL_PDK_OPS_REPEATS=3 PRISMEL_BENCH_DOMAINS=1 dune exec
  tools/bench_pdk_ops.exe`, then repeat with four domains.
- Same-input Modify Target converts its packed target links into stable
  minimum-root components, then fills exact position, payload, and topology
  ranges. On 401,802 total points, closest-link fusion with a weighted-average
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
  Reproduce using `PRISMEL_PDK_OPS_FILTER=fuse_modify_target_weighted_pair` or
  `PRISMEL_PDK_OPS_FILTER=fuse_cleanup_grid_pairs`, three repeats, and one then
  four `PRISMEL_BENCH_DOMAINS`.
- Fuse point-attribute and group rules retain stable cluster membership and
  ordered output while reducing independent packed planes in parallel. On a
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
  `PRISMEL_PDK_OPS_FILTER=fuse_target_attribute_rules` or
  `PRISMEL_PDK_OPS_FILTER=fuse_modify_target_attribute_rules`, three repeats,
  and one then four `PRISMEL_BENCH_DOMAINS`.
- Ray multi-sampling traverses the shared packed collision BVH with one
  O(samples) result/order scratch set per worker range. It never retains a
  points-by-samples hit matrix: average attribute import performs a second
  deterministic traversal after exact CSR prefix sizing. On 200,901 source
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
  `PRISMEL_PDK_OPS_FILTER=ray_multisample_position` or
  `PRISMEL_PDK_OPS_FILTER=ray_multisample_provenance`, three repeats, and one
  then four `PRISMEL_BENCH_DOMAINS`.
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
- Attribute Combine fuses the complete ordered layer stack into one output
  allocation and one parallel element traversal. Its million-point/four-layer
  float4 fixture takes 171.595/62.474 ms on one/four domains and allocates
  32.008 MB, versus 235.223/111.971 ms and 128.022 MB for four sequential
  one-layer commits with the identical hash. Integer/text cross-input matching
  uses one packed open-address table and mapping rather than boxed hash
  entries; the million-point integer-key fixture takes 59.079/36.377 ms and
  allocates 32.784 MB with exact domain-count output.
- Attribute Interpolate resolves mixed-owner fields into specialized packed
  job sets and shares one primitive-coordinate traversal across all payloads.
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
  `PRISMEL_PDK_OPS_FILTER=attribute_interpolate
  PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=1 dune exec --profile
  release tools/bench_pdk_ops.exe`, then repeat with four domains.
- Closest-surface Attribute Transfer builds one deterministic packed polygon
  AABB hierarchy and reuses primitive/triangle IDs, barycentric coordinates,
  and squared distances for every typed payload plane. Deterministic ear
  clipping retains original primitive/corner IDs. Exact node cardinality,
  reusable triangulation/query scratch, and non-escaping sequential recursion
  reduce the 80,000-triangle index from the first correct 295.7 ms/620.4 MB to
  39.081 ms/21.184 MB on one domain; parallel subtree construction takes
  18.383 ms with the identical hash. Complete mixed-owner transfer to 40,401
  points fell from 348.1 ms/733.3 MB to 74.416 ms/31.209 MB and takes 35.478
  ms on four domains. The 240,000-vertex destination path takes 210.519/77.521
  ms, while a vertex-only payload takes 195.056/71.208 ms. An isolated
  three-repeat four-domain vertex-transfer process peaks at 57,656 KiB RSS.
  Exact geometry and rendered PNG regressions compare one and four domains.
- `Attribute_pattern` compiles name selection once into literal, wildcard, and
  256-bit byte-class atoms. Matching performs no allocation and retains stable
  attribute order. The 1,024-name fixture performs 1,024,000 full-name matches
  in 80.922 ms, allocates 200 bytes in total, promotes no words, and produces
  cardinality 896,000 with hash `1915910070998661393`. Reproduce with
  `PRISMEL_PDK_OPS_FILTER=attribute_pattern PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec tools/bench_pdk_ops.exe`.
- Batch Attribute Delete/Rename compiles patterns before mutation, scans stable
  metadata through owner-local name tables, and commits one attribute array
  while sharing packed payloads. On 4,096 attributes with 2,048 matches, seven
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
  `PRISMEL_PDK_OPS_FILTER=attribute_lifecycle PRISMEL_PDK_ATTRIBUTES=4096
  PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then use the `attribute_lifecycle_batch` filter and
  four domains.
- Attribute Swap extends the same atomic metadata store with geometric-growth
  entries and one final commit. On 10,000 attributes, 5,000 wildcard Copy
  matches complete in 5.017/5.343 ms on one/four domains, allocate
  11.324/11.324 MB, and produce cardinality 15,000 with exact semantic hash
  `2610032694933915216`. Repeated immutable `Geometry.with_attribute` rebuilds
  take 397.875/563.846 ms and allocate 501.940 MB for the identical set: the
  batch path is 79.3x faster and allocates 97.7% less on one domain. Promoted
  allocation is 2.374 MB and major allocation 2.120 MB on the one-domain batch
  run. Metadata work remains sequential because four-domain dispatch cannot
  expose independent payload ranges and measured slightly slower. Reproduce
  with `PRISMEL_PDK_OPS_FILTER=attribute_lifecycle
  PRISMEL_PDK_ATTRIBUTES=10000 PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains.
- Connected Poly Extrude precomputes stable region/point associations and exact
  output cardinalities, then fills packed layer, topology, attribute, and group
  ranges directly. A first correct general path unconditionally built the full
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
  Reproduce with `PRISMEL_PDK_OPS_FILTER=poly_extrude
  PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains.
- Poly Fill plans complete one-sided polygon boundary components once, derives
  every point/corner/primitive cardinality before allocation, and fills stable
  loop ranges directly. The measured fixture contains 100,000 disconnected
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
  RSS. Reproduce with `PRISMEL_PDK_OPS_FILTER=poly_fill
  PRISMEL_PDK_POLY_FILL_BOXES=100000 PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains.
- Clean's degeneracy classifier uses a packed triangle fast path and a robust
  normalized fallback only when finite cross arithmetic overflows. On the
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
  `PRISMEL_PDK_OPS_FILTER=clean PRISMEL_PDK_OPS_REPEATS=7
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe`,
  then repeat with four domains or filter `clean_overlaps`.
- Enumerate computes selected counts independently per stable chunk, scans the
  small chunk-count plane in order, then fills disjoint attribute ranges. The
  integer path allocates only its exact output plus O(chunks) words. On
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
  `PRISMEL_PDK_OPS_FILTER=enumerate_piece PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains.
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
  `PRISMEL_PDK_OPS_FILTER=motion PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, repeat with four domains, and use `/usr/bin/time -v`
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
  `PRISMEL_PDK_OPS_FILTER=dissolve PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, repeat with four domains, and use `/usr/bin/time -v`
  with one repeat for peak RSS.
- Sort builds one stable new-to-old permutation and materializes remapped
  packed output once. Point order applies an inverse map to every corner while
  structurally sharing unchanged vertex/primitive payloads; primitive order
  fills CSR spans and vertex/primitive payloads together while sharing point
  storage. Stable comparison sorting is sequential O(n log n); key preparation
  and disjoint payload fills are parallel. A 1,002,001-point/6,000,000-corner
  X sort takes 193.8 ms on one domain and 171.3 ms on four; an 80,000-primitive
  center-X sort takes 10.9/9.95 ms. Exact hashes cover topology and all payloads.
- Duplicate computes output cardinality before allocation, precomputes stable
  transform powers, and fills copy-major position/topology/normal ranges in
  parallel. Ordinary payloads use bulk replication and groups use packed
  repeated membership. Nine materialized copies of the 40,401-point/
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
  Reproduce with `PRISMEL_PDK_OPS_FILTER=duplicate_grid_8` or
  `PRISMEL_PDK_OPS_FILTER=duplicate_selected_grid_8`,
  `PRISMEL_PDK_OPS_REPEATS=9`, and `PRISMEL_BENCH_DOMAINS={1,4}` under the
  release profile.
- UV Project partitions primitives into stable ranges so every corner is owned
  by exactly one worker; UV Transform partitions its point/vertex owner plane.
  UV Auto Seam computes face normals and edge classifications in parallel into
  byte-packed flags, then assigns deterministic islands with ranked union-find.
  UV Unitize parallelizes edge continuity, primitive bounds, and disjoint UV
  output; its stable island reduction is sequential. Edge Group uses the same
  shared face-normal kernel and now publishes its final packed edge bits
  directly. Incident-edge angles precompute normalized SoA directions once,
  then scan shared-point CSR adjacency without per-pair allocation. A mutex-protected weak cache
  stores at most one reverse index per live immutable topology; cache data does
  not retain its weak topology key.
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
  `PRISMEL_PDK_OPS_FILTER=edge_group_ PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec tools/bench_pdk_ops.exe` for cold/warm edge
  paths, and with
  `PRISMEL_PDK_OPS_FILTER=uv_ PRISMEL_PDK_OPS_COLUMNS=200
  PRISMEL_PDK_OPS_ROWS=200 PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec tools/bench_pdk_ops.exe` and repeat with
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
  `PRISMEL_PDK_OPS_FILTER=uv_flatten PRISMEL_PDK_UV_ITERATIONS=400
  PRISMEL_PDK_OPS_REPEATS=3 PRISMEL_BENCH_DOMAINS=4
  dune exec tools/bench_pdk_ops.exe`, and replace the filter with `uv_relax`
  for the boundary-preserving path.
- Group Promote and fixed-step Group Expand classify disjoint output-byte
  ranges against the same cached reverse topology. The measured 500x500
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
  `PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=500
  PRISMEL_PDK_OPS_FILTER=group_promote PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains and the
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
  `PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300
  PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1
  PRISMEL_PDK_OPS_FILTER=group_expand opam exec --switch=. -- dune exec
  --profile release tools/bench_pdk_ops.exe`, then repeat with four domains.
- Ordered wildcard Group Promotions preserve rule dependencies serially while
  running each matched conversion over disjoint packed ranges. On a
  1,002,001-point/two-million-triangle grid, one rule promoting eight named
  point stripes to eight primitive groups took 285.175/88.137 ms on one/four
  domains (3.24x). Exact geometry/group hashes were
  `2788029539558992156` at both domain counts. Total measured allocation was
  2.028/2.220 MB, of which 2,000,128 bytes is the eight required output
  bitsets; neither run promoted OCaml heap data. Isolated processes peaked at
  938,344/938,244 KiB RSS, dominated by the common million-point catalog
  fixture and cached topology. Reproduce with
  `PRISMEL_PDK_OPS_FILTER=group_promotions_points_to_primitives_wildcard_8
  PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains.
- Group Promote Boundary composes ordinary conversion with the same packed
  attribute-boundary classifier. Its first correct implementation materialized
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
  `PRISMEL_PDK_OPS_FILTER=group_promote_boundary
  PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains.
- Group from Attribute Boundary uses the shared reverse-topology index and one
  packed output edge plane. Selected numeric attribute planes are validated in
  parallel before classification; edge bytes, point bytes, and primitive bytes
  are independent ranges. No temporary storage scales with the number of
  selected attribute boundaries or incidence visits.

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
  PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=500 \
  PRISMEL_PDK_OPS_FILTER=group_attribute_boundary \
  PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_pdk_ops.exe
  # Repeat with PRISMEL_BENCH_DOMAINS=4.
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

  Reproduce the tranche with `PRISMEL_PDK_OPS_COLUMNS=500
  PRISMEL_PDK_OPS_ROWS=500 PRISMEL_PDK_OPS_FILTER=group_
  PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains. Use the exact
  `group_copy_points_attribute` filter with `/usr/bin/time -v` for isolated
  resident-memory measurement.
- Packed procedural instances retain one SOP prototype plus exactly 16 floats
  (128 payload bytes) per transform. `Scene3.instances_array` copies that array
  once, and the renderer traverses one batch descriptor instead of constructing
  a drawing list per frame. On the 100,000-instance traversal fixture,
  materialization took 54.8–56.1 ms, allocated 61.6 MB, and retained 26.4 MB;
  batched traversal took 15.9–16.3 ms, allocated 46.4 MB, and retained no
  traversal payload, with the identical ordered checksum. Reproduce with
  `PRISMEL_INSTANCE_BENCH_COUNT=100000 dune exec tools/bench_instances.exe`.
  Measurements used the Dune dev profile, OCaml 5.3.0, Linux/aarch64, four
  single-thread cores; this traversal is sequential and does not invoke SDL.
- Orphan-point compaction scans topology once, builds stable old/new point
  maps, then remaps positions, point payloads, ordinary/native edge groups, and
  vertex references through disjoint packed ranges. Bounds and Match Size scan only positions;
  Match Size delegates normal handling to the established inverse-transpose
  transform boundary.
- Copy to Points precomputes one packed scale, complete orientation basis, and
  optional pivot-adjusted translation per target, then writes copy-major source
  ranges independently. `orient` takes priority; otherwise scale-safe `N` or
  fallback `v` plus `up` synthesis aligns source +Z/+Y, with a shortest-arc
  fallback that remains stable for zero or parallel up vectors. A post-basis
  `rot`, source-local `pivot`, and additive `trans` complete the standard point
  transform stack without materializing per-copy matrices. The existing
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
  `PRISMEL_PDK_OPS_FILTER=copy_to_points PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS={1,4} dune exec --profile release
  tools/bench_pdk_ops.exe`, replacing the filter with
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
  `PRISMEL_PDK_OPS_COLUMNS=64 PRISMEL_PDK_OPS_ROWS=64
  PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_OPS_FILTER=copy_to_points_piece
  PRISMEL_BENCH_DOMAINS={1,4} dune exec --profile release
  tools/bench_pdk_ops.exe`.
- Curve Carve scans source segments once, computes exact output cardinality,
  maps retained source breakpoints directly, and performs only two O(log n)
  arc-location searches per primitive. Packed position and numeric payload
  fills use disjoint ranges. Its first scale implementation restarted a linear
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
  `bench_pdk_ops` eagerly constructs every fixture; it is not per-operation
  live memory. Measurements used the release profile, OCaml 5.3.0, Linux
  6.8.0/aarch64, and four single-thread cores. Reproduce with
  `PRISMEL_PDK_OPS_FILTER=curve_carve_divided PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS={1,4} dune exec --profile release
  tools/bench_pdk_ops.exe`. Primitive First/Second U attributes are borrowed
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
  `PRISMEL_PDK_OPS_FILTER=curve_ PRISMEL_PDK_CURVE_POINTS=200001
  PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=1
  dune exec tools/bench_pdk_ops.exe`, and the Join-only fixtures with
  `PRISMEL_PDK_OPS_FILTER=curve_join PRISMEL_PDK_OPS_REPEATS=11
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`; repeat with four domains.
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
  `PRISMEL_PDK_OPS_FILTER=poly_loft PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains and use
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
  `PRISMEL_PDK_OPS_FILTER=skin PRISMEL_PDK_OPS_COLUMNS=1000
  PRISMEL_PDK_OPS_ROWS=1000 PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains. Use
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
  `PRISMEL_PDK_OPS_FILTER=poly_bridge PRISMEL_PDK_OPS_COLUMNS=1000
  PRISMEL_PDK_OPS_ROWS=1000 PRISMEL_PDK_OPS_REPEATS=5
  PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
  tools/bench_pdk_ops.exe`, then repeat with four domains and use
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
- CSG streams polygon classification without temporary vertex/type arrays.
  BSP construction and clipping route one polygon at a time, allocate new
  geometry only for actual plane crossings, and use scalar plane math so
  classification does not box float results. Whole-tree collection, inversion,
  and clipping use explicit work stacks to tolerate long convex BSP chains.
- Loop, Butterfly, Catmull-Clark, and Doo-Sabin subdivision share borrowed
  triangle/attribute arrays and sorted edge arrays. Known triangle counts fill
  exact owned index buffers, including backward fills where legacy prepend
  order is observable. Position stencils run directly over packed geometry;
  weighted term graphs are constructed lazily only when color or UV attributes
  need interpolation. Doo-Sabin caches source face normals once per pass.

## Parallel execution

Only pure CPU phases run on Domainslib. Work partitions use stable integer
ranges and disjoint output slices. Scheduling grain is configurable, with a
sequential cutoff chosen from benchmarks. The reusable pool is process-scoped;
creating domains per frame or geometry operation is forbidden.

`Parallel.run` selects and exclusively borrows the cached pool for the complete
operation. Each parallel helper opens a bounded Domainslib task scope and
submits stable contiguous chunks; domain-local pool context is installed once
per chunk rather than once per element. Nested helpers reuse that context and
still honor their sequential grain cutoff. Keeping task scopes at helper
boundaries avoids retaining scheduler state across unrelated algorithm phases.

Parallel candidates include field sampling, point transforms, independent
vertex attributes, classifications, and per-cell geometry counts/fills.
Topology joins, stable prefix sums, output ordering, SDL work, renderer caches,
and resource upload remain deterministic join/initial-domain phases.

Renderer-derived mesh data uses separate smooth/flat weak-key caches, each
with a hard 256-entry insertion-order cap. The cap bounds retained live-scene
metadata while weak keys allow unreachable meshes to disappear earlier.
The software rasterizer retains at most one framebuffer scratch set and reuses
it only for an exact dimension match; a size change replaces the prior scratch
set rather than accumulating resolution-specific framebuffers. Opaque color
attachments use four packed float planes, and the ordinary on-screen path
writes RGBA bytes directly into a reusable upload buffer instead of allocating
one color record per covered or resolved pixel. The default opaque
depth/stencil path uses specialized integer and float comparisons so boxed
polymorphic comparisons cannot leak into the sample loop. Fixed untextured
lighting is collapsed once per transformed vertex rather than rebuilt for
every incident triangle, line segment, or point. The collapsed payload is
consumed directly for all three primitive modes; it is never indexed as though
it still contained one entry per active light.

The SDL upload texture is cached for one renderer and exact viewport size.
Switching renderers or sizes destroys the previous texture, and application or
canvas teardown releases a matching cached texture before its renderer. This
keeps the cache bounded while avoiding a native texture allocation on every
animation frame.

Native untextured fixed-pipeline `Scene3` rendering bypasses that CPU
framebuffer/upload path. One compatibility OpenGL context owns hardware
transform, depth/stencil, lighting, culling, blending, primitive rasterization,
and the window's configured MSAA; SDL's OpenGL renderer remains the 2D/PXUI
compositor. Flat/smooth packed mesh caches use weak keys and retain at most the
current and previous procedural mesh per shading mode. On the Apple M1/macOS
26.2 development machine, the 1024×720 shattered-cube sketch's default 50
noise-deformed two-by-two grids produce 15,361 closed cells and a 237,012-
triangle render mesh. Fresh native processes take 19.43 s for one frame and
32.81 s for 1,001 frames, including the same initial Boolean cook. Subtracting
the one-frame process gives 13.38 s for the following 1,000 frames, or about
74.7 frames/s; this is a workflow
measurement rather than a portable threshold. Reproduce with:

```sh
PRISMEL_RENDER_TARGET=native PRISMEL_SHATTER_FRAMES=1 \
  /usr/bin/time -p dune exec sketches/shattered_cube/main.exe
PRISMEL_RENDER_TARGET=native PRISMEL_SHATTER_FRAMES=1001 \
  /usr/bin/time -p dune exec sketches/shattered_cube/main.exe
```

The web target performs framebuffer readback only while a browser is connected
and caps presentation independently with `PRISMEL_WEB_MAX_FPS` (60 by default).
`PRISMEL_WEB_MAX_MBIT` (2 by default) turns the selected encoded payload size
into a minimum interval, so incompressible content trades cadence for traffic.
`PRISMEL_WEB_MAX_PIXELS` (921600 by default) bounds render/readback/diff work
for large browser windows without shrinking their logical coordinate space.
Readback writes directly into a pooled RGBA Bigarray. Wap suppresses exact
duplicates, losslessly QOI-encodes compressible pixels, and extracts the changed
rectangle between sequential frames. Full frames use a 28-byte metadata
fragment; patches use 44 bytes and update the persistent browser texture in
place. One latest frame plus at most one browser-acknowledged in-flight frame
per bounded client implements backpressure by dropping stale complete frames.
Consecutive identical frames back readback cadence off to one quarter of the
configured ceiling; any browser input immediately restores full cadence.
Browser presentation is aligned to `requestAnimationFrame`, and coalesced
pointer samples share one bounded message rather than one WebSocket frame each.
HTTP connections, WebSocket clients, pooled buffers, input
bytes, uploads, control commands, and registered assets all have explicit
ownership or capacity bounds. The reusable frame pool has both count and byte
ceilings, so resolution churn cannot retain an unbounded set of large backing
buffers. No thread or domain is created per frame.

Offscreen `Framebuffer3` snapshots transfer the rasterizer's fresh color,
depth, and stencil arrays directly. Their borrowed `Texture.t` color attachment
shares the same immutable color backing array, avoiding copy/list/array
round-trips. CPU textures generate mip levels with direct 2×2 channel
accumulators and sample packed immediate RGBA values. The fixed textured
raster path collapses lighting per vertex when separate specular, shaders, fog,
and shadows are absent; it computes perspective UV derivatives and LOD in
scalars and commits packed samples directly to framebuffer component planes.
Visible multisampled rendering resolves opaque samples directly from those
component planes into a reusable native-pixel buffer. It does not materialize
one temporary color record per supersample. Constant-color triangles bypass
barycentric color arithmetic; besides reducing work, this keeps an equivalent
procedural-to-geometry rewrite byte-identical at antialiased edges.

Axis-aligned 2D rectangles, circles, ellipses, and uniformly scaled rounded
rectangles dispatch directly to SDL2_gfx instead of first materializing
polygon point lists. The local SDL2_gfx binding uses compiled C stubs rather
than dynamic Ctypes/libffi invocation. Scalar calls reuse a domain-local
argument array; polygon and Bézier list conversion uses bounded native
temporaries and does not build intermediate OCaml coordinate arrays.

## Measurement contract

`tools/bench_geom.exe` is the repeatable geometry baseline. It reports elapsed
time and GC allocation for representative mesh, field, topology, spatial, CSG,
physics, transform, extrude/lathe/sweep, dense voxel, and sparse-octree
workloads. Benchmarks run with the release profile and record input
cardinalities and domain count.

`tools/bench_wap.exe` reports submitted, published, and suppressed frames,
source and encoded payload bytes, compression ratio, and publish time for a
static UI, moving sprite, and deliberately incompressible noise. Override its
resolution and sample count with `PRISMEL_WAP_BENCH_WIDTH`,
`PRISMEL_WAP_BENCH_HEIGHT`, and `PRISMEL_WAP_BENCH_FRAMES`.

Performance changes require before/after measurements on the same machine and
compiler profile. Correctness tests additionally enforce deterministic output,
expected cardinality, and bounded cache/resource behavior. Timing is diagnostic
unless a stable dedicated benchmark runner is available.

`tools/bench_render.exe` measures the headless software 3D path after warmup.
`PRISMEL_RENDER_BENCH_SIZE`, `PRISMEL_RENDER_BENCH_FRAMES`,
`PRISMEL_RENDER_BENCH_SEGMENTS`, and `PRISMEL_RENDER_BENCH_RINGS` control its
workload; `PRISMEL_RENDER_BENCH_CLEAR_ONLY=1` separates framework overhead from
raster work, while `PRISMEL_RENDER_BENCH_TEXTURED=1` exercises trilinear CPU
texture sampling. `PRISMEL_RENDER_BENCH_SAMPLES` selects the supported MSAA
sample count, and `PRISMEL_RENDER_BENCH_PROGRAMMABLE_FLOOR=1` isolates a large
custom fragment-shader workload. `PRISMEL_RENDER_MEMPROF=1` enables sampled
allocation call stacks for diagnostics and is intentionally excluded from
timing baselines. `tools/compare_floor.exe` verifies that the 3D example's
fixed-path editor grid remains byte-identical to its programmable reference.

`tools/bench_scene2d.exe` measures a retained scene containing a configurable
grid of rectangles, circles, ellipses, and rounded rectangles. It accepts the
shared render size/frame controls plus `PRISMEL_2D_BENCH_COLUMNS` and
`PRISMEL_2D_BENCH_ROWS`; the same memory-profiler switch is available for FFI
and primitive-path allocation audits.

`tools/bench_pxui.exe` measures retained-scene construction and a captured
pointer drag on a configurable large control panel. PXUI keeps O(1) reverse-list
builders but memoizes one ordered widget array; vertical hit testing resolves a
single row arithmetically, so pointer lookup is independent of panel length.
`PRISMEL_PXUI_BENCH_WIDGETS` and `PRISMEL_PXUI_BENCH_REPEATS` control the run.

Every parallelized operation is also exercised inside `Parallel.run ~domains:1`
and with multiple domains. Geometry output must be exactly equal, including
attribute and index ordering. Renderer-facing changes require a headless native
framebuffer or exported-PNG comparison of representative scenes. The existing
deterministic export test compares PNG digests across repeated runs; visual
coverage must grow alongside new renderer features and optimized drawing paths.

PDK plane clipping classifies canonical or numeric point-coordinate planes in
parallel. Polygon-only unfilled clipping counts source/side outputs in stable
parallel slots, performs one deterministic prefix, allocates exact corner and
primitive planes, and fills disjoint slices. Curves, caps, and repeated-corner
fallbacks retain the geometric-growth builder; cap-loop topology remains
sequential. Shared-edge token ordering fixes point IDs independently of task
scheduling.

A concave polygon with more than one retained boundary run deliberately leaves
the dense exact planner. Its k clipping endpoints are sorted along their widest
stable plane axis, paired through the source interior, and linked as a compact
chain permutation before output cycles are materialized. This uncommon path is
O(vertices + k log k) time and O(vertices + k) transient storage per affected
polygon; ordinary convex/triangle/quadrilateral workloads allocate none of
that reconstruction scratch. The regression covers two disconnected retained
fragments, the connected complementary side, primitive ancestry, native cut
edges, two caps on an extruded closed mesh, and exact one/four-domain output.

Nested Clip caps keep direction while tracing boundary segments, classify
opposite-winding containment, normalize coordinates around a local anchor,
insert deterministic non-crossing visibility bridges, and ear-clip the weakly
simple ring into ordinary triangles. A packed X-interval sweep rejects
self-intersections and inter-contour touching in O(c log c + i) expected time
for i active bounding-box candidates, with O(c^2) worst case. For c original
contour vertices and h holes in one component, bridging is O(h*c^2) worst case,
the bridged ear pass is O((c + 2h)^2), and scratch/output planning is O(c + h).
Independent contour components remain in stable token order. At least two
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

Typed Clip restriction first promotes the selection once, then marks selected
primitive incidence and only allocates isolation tokens for source points
actually shared across selected and unselected primitives. On the same scale
fixture, selecting the contiguous first third of primitives while carrying the
attribute fixture takes a median 434.681/316.615 ms and allocates
793.385/765.621 MB for one/four domains. Materializing a clipped native-edge
group takes 867.203/732.392 ms and 1,594.573/1,559.907 MB because it also builds
the complete output topology index. The respective deterministic hashes are
4451540838762259033 and 2517369864773722023 for both domain counts. These are
medians of three fresh processes, each reporting the median of three cooks;
the machine/compiler context is the same as the other PDK rows in this file.

```sh
PRISMEL_PDK_OPS_FILTER=clip_ PRISMEL_PDK_OPS_REPEATS=3 \
PRISMEL_PDK_OPS_COLUMNS=1000 PRISMEL_PDK_OPS_ROWS=1000 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
```

The shared PDK subdivision kernel computes exact child cardinalities and one
stable CSR stencil plan per level. Catmull-Clark/bilinear emit four-corner
polygons directly instead of triangulating and rebuilding them; Loop emits four
triangles per source triangle. Face-varying data writes from face-local source
corners, so no seam weld or tuple expansion is hidden in the hot loop. Numeric
planes, including semi-sharp position/point primvars, evaluate in parallel;
topology indexing, full edge/vertex-fan validation, and stable planning remain
sequential only where prefix cardinality or stable topology order requires it.
Exact-sized point-stencil and output-topology ranges fill independently. On
the 40,401-point/80,000-triangle attribute fixture, refreshed five-run release
medians are 67.794/45.713 ms for Loop and 102.178/65.446 ms for Catmull-Clark
at one/four domains. A dense semi-sharp Catmull-Clark fixture is
112.652/65.699 ms; bilinear is 36.949/28.280 ms. The earlier four-domain
baselines were respectively 57.4, 79.3, 90.1, and 38.5 ms. Exact hashes remain
unchanged across domain counts and the planning refactor.

Primitive-group refinement partitions selected and unselected topology once,
retains free points once, and duplicates only boundary points. A union-find
pass splits selected faces that touch only at a point into valid independent
fans without breaking edge-connected stencils. The 40,401-point/80,000-triangle
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

Second-input crease preparation reuses the source topology index when the
topologies are identical. Attribute-driven crease reduction runs once per
unique edge into disjoint slots; a sparse override input instead walks only
its selected primitive incidence and probes the source integer-edge table.
On the same 40,401-point fixture, five release medians measured:

| Second-input crease case | 1 domain | 4 domains | Allocated 1d/4d | Exact hash |
|---|---:|---:|---:|---:|
| dense vertex attributes | 141.076 ms | 96.156 ms | 256.813/193.785 MB | 2240368469655108917 |
| dense attributes + resulting edge group | 149.133 ms | 99.783 ms | 262.722/199.795 MB | 512181311574988744 |
| sparse 200-edge override | 96.761 ms | 71.249 ms | 214.329/164.443 MB | 2384261217015432874 |

The first resulting-group implementation constructed and retained a complete
target reverse-topology index merely to find child edge numbers. It measured
223.609/189.828 ms and 406.677/382.754 MB at one/four domains. Subdivide now
derives the two child ordinals of every source edge while scanning its already
deterministic refinement topology. That cut the measured one-domain group
case by 32% in time and 35% in allocation, and benefits ordinary propagated
native edge groups as well. The direct ordinal plan uses O(output edges)
integer scratch and one final packed bitset; it does not retain the scratch.
The filtered five-repeat four-domain benchmark process peaked at 1,132,032
KiB RSS, but this harness eagerly constructs the complete `bench_pdk_ops`
fixture catalog before applying its output filter, so the number is a process
upper bound rather than isolated Subdivide live memory.

Hole refinement uses the complete source adjacency for stencils while a
primitive-prefix plan allocates and fills only visible descendant topology.
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

OpenSubdiv point-boundary policy adds no alternate geometry representation.
Edge Only and Edge and Corner share the packed subdivision planner; the latter
changes only one-face boundary point stencils. None scans the cached integer
reverse topology, writes packed point/primitive boundary bitsets in cancellable
disjoint byte ranges, and then reuses the ordinary hole path. On the same
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
the headless render regression composes None with holes and second-input
creases and compares byte-identical PNG output.

Face-varying policy classification is cardinality-first and retains exact
source-order summation. Continuous fields reuse the geometry plan; fully split
one-face fields bypass a second reverse-topology index; mixed fields build one
packed value topology and CSR stencil plan shared by every tuple component. A
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
bilinear immunity, cancellation, and byte-identical headless rendering.
Measurements used OCaml 5.3.0, Dune 3.24.0, release profile, grain 16,384, and
Linux 6.8/aarch64 on four cores.

Smooth Triangles is a branch inside the existing Catmull-Clark interior-edge
stencil fill, not an alternate topology pass. It reads the two already indexed
incident face arities, computes the exact 0.470/0.25 interpolated mask, and
writes the same pre-sized CSR slots. Complexity and auxiliary storage remain
O(points + edges + vertices + output stencil terms). On a 40,401-point
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

Uniform and Chaikin creasing share one packed child-edge plan. Each source
point owns the two endpoint slots of its incident edges, so the O(points +
edges) child pass is parallel without atomics. Six O(points) packed rule,
transition, and crease-neighbor planes then encode exact parent/child vertex
masks; positions and every compatible numeric plane reuse them. Resulting
vertex weights and native edge groups consume the same two-E child array rather
than rescanning neighborhoods. On a 40,401-point grid with densely varying
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
one/four-domain geometry, and byte-identical headless rendering.

Houdini detail controls add one sequential scan of the immutable attribute
metadata and five scalar enum resolutions before the existing plan. They do
not add a second topology or per-element branch. To isolate that dispatch from
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

The no-second-input all-edge override is not implemented by first creating a
vertex `creaseweight` field. Its scalar fills the E-entry sharpness plane in
the first refinement plan, after which ordinary residual fields drive deeper
levels. A paired 40,401-point fixture compares that direct path with an
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

Point-normal Subdivide retains the same cardinality-first point stencil used
for `P`; it does not add a topology pass in the default interpolation mode.
Opt-in recomputation runs the shared deterministic area-weighted point-normal
kernel once after the complete recursive/local/mixed cook, rather than once per
subdivision level. On a 40,401-point attributed triangle grid producing
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

Polygon-curve Subdivide uses exact point/stencil/vertex cardinalities and
packed integer topology throughout. A first correct mixed-family implementation
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
PRISMEL_PDK_OPS_FILTER=subdivide_bilinear_local \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_second_input \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_sparse_holes \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=subdivide_catmull_dense_holes \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat both with PRISMEL_BENCH_DOMAINS=4.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_grid_boundary \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_fvar \
PRISMEL_PDK_OPS_COLUMNS=1 PRISMEL_PDK_OPS_ROWS=1 \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_triangles \
PRISMEL_PDK_OPS_COLUMNS=1 PRISMEL_PDK_OPS_ROWS=1 \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_creasing \
PRISMEL_PDK_OPS_COLUMNS=1 PRISMEL_PDK_OPS_ROWS=1 \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_explicit_controls_detail_payload \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=subdivide_catmull_detail_overrides \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat both with PRISMEL_BENCH_DOMAINS=4; wrap the second in
# /usr/bin/time -v for RSS.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_all_edges_ \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; wrap in /usr/bin/time -v for RSS.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_normals \
PRISMEL_PDK_OPS_REPEATS=9 PRISMEL_PDK_OPS_COLUMNS=200 \
PRISMEL_PDK_OPS_ROWS=200 PRISMEL_BENCH_DOMAINS=1 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use repeats=1 under /usr/bin/time -v
# for the conservative process RSS figure.

PRISMEL_PDK_OPS_FILTER=subdivide_catmull_curves \
PRISMEL_PDK_CURVE_POINTS=200001 \
PRISMEL_PDK_OPS_COLUMNS=200 PRISMEL_PDK_OPS_ROWS=200 \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=9 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4 and use repeats=1 under /usr/bin/time -v
# for the conservative process RSS figure.

PRISMEL_PDK_OPS_FILTER=subdivide_bilinear_curves_shared \
PRISMEL_PDK_CURVE_POINTS=200001 \
PRISMEL_PDK_OPS_COLUMNS=200 PRISMEL_PDK_OPS_ROWS=200 \
PRISMEL_BENCH_DOMAINS=1 PRISMEL_PDK_OPS_REPEATS=5 \
dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
```

Point, vertex, primitive, Blast, and Split filtering share one PDK deletion
planner. It counts retained primitives/corners/points before allocation,
materializes each map once, preserves ascending source order, and shares point
positions/attributes/groups when the point map is identity. Healing performs
no tuple/list allocation per primitive. On the attribute-heavy 240,000-quad
fixture, removing a temporary result tuple reduced one-domain time/allocation
from 45.0 ms/119.4 MB to 35.7 ms/73.2 MB; four domains improved from
32.8 ms/79.1 MB to 27.8 ms/49.7 MB. Output hashes are exact across domains.

PDK Convert Line builds the shared reverse-topology index once, filters each
unique edge once, and uses stable 16-bit radix passes to produce canonical
point-number ordering without comparison-sort tuple allocation. It allocates
exact two-corner CSR output, shares point/detail payloads, and fills topology,
primitive lengths, and topology-affine group bytes through disjoint ranges. On
the 1,002,001-point/2,000,000-triangle grid (3,002,000 output lines), the
release command below measured 627.4 ms/316.1 MB allocated on one domain and
298.8 ms/215.5 MB on four; the exact hash was `1159685896482037800` in both
runs. `/usr/bin/time -v` reported a 901,888 KiB process peak for the five-repeat
four-domain harness, including the retained million-point source, reverse
index, output high-water heap, hashing, and Dune. A first finite-distance
validation helper returned `float option` in the edge loop and raised measured
one-domain allocation to 412.2 MB; scalar inlining restored 316.1 MB while
retaining the non-finite-result diagnostic.

PDK PolyPath consumes the same cached unique-edge index but avoids Convert
Line's two-corner primitive for every intermediate edge. With endpoint
connection disabled, the common self-edge-free path borrows the index endpoint
planes directly; only endpoint rewiring allocates an open-addressed deduplication
graph. One sequential stable trace permutation visits every edge exactly once,
while topology and every requested payload plane materialize into disjoint
owned ranges. Optional ancestry planes are omitted when their owner has no
attribute or group. Complexity is O(vertices + unique edges + payload) time and
O(points + unique edges + output + payload) storage. Spatial endpoint rewiring
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

Convert Line's Connect Path mode is fused into that packed graph rather than
materializing and then re-indexing 3,002,000 two-corner primitives. On the same
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
PRISMEL_PDK_OPS_FILTER=poly_path PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=poly_path PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
```

```sh
PRISMEL_PDK_OPS_FILTER=convert_line PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=convert_line PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=convert_line_path_fused PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=convert_line_path_fused PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
```

The directed Line source normalizes extreme finite directions with scaled
arithmetic, allocates its position and optional identity topology planes once,
and fills both in the same disjoint point pass. On 1,002,001 points it measured
11.35 ms/32.1 MB on one domain and 8.85 ms/32.1 MB on four, with exact hash
`3766555573609226817`.

Circular Sweep/PolyWire now precomputes one sine/cosine cross section instead
of evaluating trigonometry at every ring, uses arithmetic primitive offsets,
and partitions independently owned spine curves with a grain derived from
average curve size. The unchanged 10,001-ring fixture improved from
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
PRISMEL_PDK_OPS_FILTER=sweep_general_profile_triangles PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=sweep_general_profile_triangles PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=sweep_general_profile_payload PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=sweep_general_profile_payload PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_smooth_runs PRISMEL_PDK_OPS_REPEATS=11 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_smooth_runs PRISMEL_PDK_OPS_REPEATS=11 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_variable_segment_seam \
PRISMEL_PDK_OPS_REPEATS=11 PRISMEL_BENCH_DOMAINS=1 \
opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_variable_segment_seam \
PRISMEL_PDK_OPS_REPEATS=11 PRISMEL_BENCH_DOMAINS=4 \
opam exec --switch=. -- /usr/bin/time -v \
  dune exec --profile release tools/bench_pdk_ops.exe
```

```sh
PRISMEL_PDK_OPS_FILTER=line_generator PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=sweep_caps PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_variable PRISMEL_PDK_OPS_REPEATS=11 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_variable PRISMEL_PDK_OPS_REPEATS=11 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_sharp_joints PRISMEL_PDK_OPS_REPEATS=11 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=polywire_sharp_joints PRISMEL_PDK_OPS_REPEATS=11 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  /usr/bin/time -v dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=resample PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=resample PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
```

PolyFrame is topology-linear: every style takes O(points + vertices +
primitives) time and O(points + vertices + primitives) auxiliary/output
storage, with a fixed number of packed numeric/index planes. The first runnable
361,201-point implementation returned or retained boxed values in element
loops. Two Edges, Texture UV, and Attribute Gradient respectively measured
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

Every final path promoted zero bytes. The remaining allocation is the packed
normal/frame output, topology incidence, and style-specific shared scratch;
there is no per-point, per-corner, or per-primitive box in the measured loops.
The isolated five-repeat four-domain process peaked at 511,376 KiB RSS. Exact
geometry hashes match across domain counts, and the procedural framebuffer
regression also matches one versus four domains. Measurements used OCaml
5.3.0, Dune 3.24.0, release profile, grain 16,384, and Linux 6.8/aarch64 on
four cores.

```sh
PRISMEL_PDK_OPS_FILTER=polyframe PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use /usr/bin/time -v for process RSS.
```

Facet Unique Points is O(points + vertices + primitives + attribute/group
payload + edge incidences) time and auxiliary/output storage. It derives exact
cardinality before allocation, fills a target-point-to-source-point plane, and
uses it for positions, all eight point storage kinds, and ordered point groups.
Native edge groups use corner ancestry so a selected shared edge expands to
both unshared descendants. On a 200,901-point/1,200,000-corner UV grid, the
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

Orient Polygons is O(vertices + unique edges + primitives + reversed vertex
payload) time and O(topology index + primitives + reversed output) storage.
Stable component BFS remains sequential so orientation cannot depend on work
stealing; only topology/payload materialization uses disjoint parallel ranges.
The first correct version unconditionally built a second complete topology
index for edge-group remapping, even when no edge groups existed. It measured
128.615/122.339 ms and allocated 221.681/221.748 MB. Deferring that target
index and identity point map until an edge group exists produced the final row
without changing hash, a 4.58x one-domain time reduction and 8.40x allocation
reduction.

Primitive-restricted Unique Points is O(points + vertices + primitives +
selected output payload) time. Its selection analysis uses saturated point
incidence, selected-reference, and unselected-reference byte planes instead of
a complete edge/topology index. Selected/unselected corner masks for normal
adjustment are likewise direct packed byte planes. In the same development-
profile tuning run, the first correct grouped pre-normal + Unique Points +
reverse implementation measured 222.190/196.095 ms and allocated
379.961/380.132 MB at one/four domains; the compact-mask version measured
69.241/48.120 ms and 112.181/112.375 MB, with hashes unchanged. Isolated
grouped Unique Points fell from 144.071 ms and 269.600 MB to 45.589 ms and
76.532 MB at one domain. The table records separate final release-profile
measurements.

Typed Facet point and vertex promotion is O(vertices + primitives) time with
one packed primitive bitset; predicates scan each primitive's contiguous corner
range independently. Native-edge promotion additionally builds the standard
O(points + vertices + unique edges) topology index to translate topology-affine
edge ordinals. The promoted mask is then shared by every enabled Facet stage.
The measured point/vertex half-range and sparse-edge selections include this
conversion cost, promote zero bytes, and produce identical ordered output at
one and four domains.

Facet Cusp Polygons is O(primitives + corners + unique edges + output payload)
apart from inverse-Ackermann union/find cost, with O(corners + unique edges +
output) auxiliary/output storage. Face normals and edge classification use
disjoint parallel planes. Stable point/incidence traversal assigns output
numbers, and iterative path compression with deterministic union-by-rank avoids
both scheduler-dependent numbering and recursive stack growth. The cusp stage
preserves the original geometry by identity when no fan splits are required.

Remove Inline Points is O(points + corners + primitives + output payload +
native-edge incidences) time and O(points + corners + primitives + output)
auxiliary/output storage. Its per-primitive cyclic queue is exact-sized; each
deletion schedules at most two adjacent corners, so iterative simplification
remains linear. Classification and target-plane fills use disjoint stable
primitive ranges, while point compaction is a deterministic ordered prefix.
The initial correct hot loop used polymorphic float min/max and allocated a
local enqueue closure per deletion. It measured 118.619/62.570 ms and allocated
219.604/130.575 MB at one/four domains. Explicit unboxed comparisons and direct
neighbor enqueue paths produced the final row with the same hash: 1.57x/1.42x
faster and 2.40x/1.42x lower allocation.

Consolidate Normals is O(points + neighboring candidates + normal elements)
expected time and O(points + clusters + normal output) auxiliary/output
storage, with the same documented quadratic dense-cell worst case as Fuse.
Greedy earliest-representative discovery is stable and intentionally
sequential; point/vertex validation, per-cluster scale-safe reductions, and
disjoint normal fills parallelize. The measured regular-pair fixture is
discovery-bound, so four domains do not provide a material speedup. Reusing
the clustering cell planes for cluster IDs, sizes, and CSR cursors reduced the
first correct implementation from 564.021/549.351 ms and 283.159/283.240 MB to
the final row, with the exact hash unchanged: 1.22x/1.20x faster and 2.03x lower
allocation.

Make Planar is O(points + corners + primitives + output point payload) time and
storage. Scale discovery, centroid/Newell-plane construction, planarity
classification, and projection run independently over stable primitive ranges.
A sequential source-point claim pass assigns deterministic originals or
conflict copies; packed payload materialization then reuses the common ancestry
kernels. The measured disjoint-quad fixture needs no conflict copies, allocates
only its exact position and per-corner projection/state planes, promotes zero
bytes, and retains the same hash at one and four domains.

Every final path promoted zero bytes. The isolated five-repeat four-domain
process peaked at 472,664 KiB RSS. Measurements used OCaml 5.3.0, Dune 3.24.0,
release profile, grain 16,384, and Linux 6.8/aarch64 on four cores.

```sh
PRISMEL_PDK_OPS_FILTER=facet PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use /usr/bin/time -v for process RSS.
```

The million-point polygon Circle source replaces its former boxed-tuple plus
builder pipeline with exact position/index planes filled together. The
compatible closed-circle hash remains `1595635405635298122`; release medians
fell from 92.75/88.49 ms to 22.94/13.21 ms at one/four domains, while allocation
fell from 112.23 MB to 32.08 MB. Open, chord-closed, and sliced ellipse modes use
the same O(points) kernel and stable domain-independent ordering.

The production Box generator derives every cardinality before allocation and
fills packed lattice, surface, topology, normal, UV, and group planes in stable
disjoint ranges. Its integer-coordinate hot helpers avoid boxed float
arguments on the non-Flambda compiler. On the same OCaml 5.3.0/Linux aarch64
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

UV Sphere precomputes O(segments+rings) trigonometric tables, fills positions
and point normals together, and emits fixed proven outward index patterns
instead of evaluating latitude trigonometry per point and recomputing winding
from three positions per triangle. Its compatible million-point/two-million-
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

Torus precomputes O(rows+columns) trigonometric and normalized-parameter
tables, fills positions/point normals together, and writes surface, curve,
cap, normal, and UV planes in disjoint stable ranges. A sequential reference
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

Revolve plans compact axis poles and stable per-profile-edge primitive ranges
before allocating the output. A 10,001-corner profile with axis endpoints and
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
Reproduce with `PRISMEL_PDK_OPS_FILTER=revolve
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=1 dune exec --profile release
tools/bench_pdk_ops.exe`, then repeat with four domains.

Tube precomputes O(rows+columns) radius, height, trigonometric, and normalized-
parameter tables, shares a single point at a zero-radius end, and emits no
degenerate tip ring or quad. Exact output planes cover side topology, optional
independent cap rims, point/vertex normals, UVs, and cap membership; stable
side-band ranges cook in parallel while cap writes remain bounded. Work and
published output are O(rows*columns), with O(rows+columns+parallel ranges)
auxiliary storage.

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

Platonic Solids keeps normalized canonical point, face, and face-normal tables
once at module initialization. Each cook allocates only its fixed packed result
and copies the relevant immutable topology; all forms contain at most 60 points
and 180 corners, so domain dispatch would cost more than the complete cook and
the kernel deliberately remains sequential. A 100,000-call icosahedron batch
(1.2 million generated points) improved from the former boxed-coordinate plus
Topology.Builder reference at 83.603 ms and 696.800 MB to 23.459 ms and
266.400 MB, retaining exact hash `108589944924191245`. A 20,000-call transformed
soccer-ball batch with hard vertex normals, black/white primitive color, and
face groups took 49.815 ms and 292.640 MB, hash `4440798644007023453`. Complete
geometry remains identical when the surrounding sketch uses one or four
domains; no misleading per-solid parallel path is created. The final
three-repeat one-domain process peaked at 54,496 KiB including Dune and the
OCaml heap.

Spiral shares one radius/height/angle/trigonometric table across phase copies
and fills exact-sized packed position, topology, and optional attribute planes
in stable ranges. Equal-arc placement integrates analytic speed in a partition
that includes every ramp knot, then performs ordered prefixing and independent
bounded inversions. Cumulative distance uses fixed 4,096-segment blocks. The
frame loop uses specialized float comparisons and range-local scratch; no
point, frame, quaternion, sample, or distance iteration allocates a box.

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

Attribute Promote materializes at most one packed incidence plane per scalar
component. Upper median uses three-way introspective selection rather than a
full sort; its million-point detail fixture improved from 424.5 ms to 28.3 ms
with the same 8.02 MB allocation and exact hash `1214810429822179029`. Large
integer mode uses a bounded dense histogram when the observed range justifies
it, improving the same-size fixture from 430.0 ms to 12.14 ms and exact hash
`1214810429822179047`. A single detail reduction cannot expose independent
output ranges, so its one/four-domain times are intentionally equal.

Piece promotion assigns deterministic integer/text partitions, constructs one
CSR union of unique ascending source indices, and maps the reduced piece plane
back through disjoint destination ranges. Same-owner identity pieces use a
stable linear CSR build instead of pair sorting; non-identity topology uses
16-bit radix ordering. Incidence-adjusted grain gives large pieces enough work
per task. The 1,002,001-point fixture with 64-point integer pieces improved
from the first packed implementation's 228.4 ms/83.9 MB to 142.3 ms/34.1 MB
on one domain and 52.62 ms/33.0 MB on four, with exact hash
`3372359779053422621`. The five-repeat four-domain harness peaked at 1,229,704
KiB RSS including its retained million-point/two-million-triangle source,
hashing, Dune, and high-water heaps.

Plural pattern promotion builds that topology/piece plan once, then applies
each selected packed payload against it in stable source-attribute order.
Aligned multi-term destination and index capture rewriting is compiled and
preflighted before that plan. Exclusions consume no replacement term, and
later positive matches take precedence; rewrite work is proportional only to
selected attribute-name bytes. On a 400x400 grid (160,801 points, 320,000
primitives), promoting and renaming four float point attributes to 5,000
integer-partitioned primitive pieces with Average and grain 2,048 took
41.517/40.050 ms on one/four domains, allocated 52.382/38.597 MB, and produced
cardinality 1,440,801 with exact hash `1347528973856259256`. Four repeated
renamed singular promotions took 137.069/134.585 ms and allocated
115.878/102.127 MB for the identical result. An isolated three-repeat
four-domain shared-plan process peaked at 70,860 KiB RSS.

The optional scalar source-index output is fused into the first/last/extremum
pass; its only dense retained addition is the required destination integer
plane. On the same fixture with Maximum, shared promotion without indices took
43.513/37.762 ms and allocated 52.382/38.095 MB. Four value/index pairs took
53.231/43.090 ms and allocated 62.470/49.179 MB, including 10.24 MB of required
index payload, with exact hash `3924845448660289621` across domain counts.
Repeating four singular indexed promotions took 145.357/146.119 ms and
allocated 125.960/112.960 MB for that identical hash. The isolated
three-repeat four-domain indexed process peaked at 81,144 KiB RSS.

The production extension keeps tuple provenance shape instead of returning a
single misleading index: float2/3/4 extrema reduce components independently
and publish one fixed-width integer CSR row per destination. Text/index
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
PRISMEL_PDK_OPS_FILTER=attribute_promote PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_promote PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_promote_pattern \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_BENCH_GRAIN=2048 \
PRISMEL_BENCH_DOMAINS=1 dune exec tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_promote_pattern \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_BENCH_GRAIN=2048 \
PRISMEL_BENCH_DOMAINS=4 dune exec tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_promote_pattern_tuple4_indexed_shared \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_BENCH_GRAIN=2048 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_promote_pattern_text_sum \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_BENCH_GRAIN=2048 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
```

Attribute Blur reuses the topology cache, precomputes optional original-edge
lengths and boundary pins once, and keeps exactly two mutable plane sets for
Jacobi iterations. Each iteration launches stable point ranges once and loops
all selected components inside a range. Neighbor alpha was initially called
through a float-returning closure in the innermost edge/component loop; that
boxed roughly one float per visit. Inlining the optional alpha read reduced
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
PRISMEL_PDK_OPS_FILTER=attribute_blur PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_blur PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
```

Attribute Randomize validates/unpacks tuple parameters once, allocates exact
output planes, and fills stable element/component identities through
`Rand.float_at`. The first correct implementation mixed boxed `int64` values
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

The uniform-volume regression independently checks centered first moments and
the analytic 3D expectation `E[r²] = 3/5`; constrained-volume tests retain that
radial moment while checking cone support and axis bias. Direction/orientation
regressions check unit length and cone containment. Fraction tests cover exact endpoints,
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
PRISMEL_PDK_OPS_FILTER=attribute_randomize_cauchy2_bounded \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_BENCH_GRAIN=2048 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_randomize_text_discrete \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_BENCH_GRAIN=2048 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_randomize_point_to_vertex_group \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_PDK_BENCH_GRAIN=2048 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=attribute_randomize PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_randomize PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_remap PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=attribute_remap PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
```

Peak, Mountain, and topology-preserving normal generation share packed
structure-of-arrays deformation planes. A first correct Peak loop boxed
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

Point Jitter uses the same indexed component stream as the equivalent
Attribute Randomize uniform-add operation, but writes canonical `P` directly.
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
PRISMEL_PDK_OPS_FILTER=point_jitter PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=point_jitter PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=edge_divide PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=edge_divide PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

Edge Collapse uses a 500x400 quad grid with 200,901 points, point/vertex UV and
enumeration payload, point and native-edge groups, sparse disjoint horizontal
edge contractions, degenerate cleanup, and point-normal recomputation. The
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
PRISMEL_PDK_OPS_FILTER=edge_collapse PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=edge_collapse PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

PolyReduce uses a 420x320 alternating-triangle grid (134,400 points and
267,322 input triangles) with vertex UVs, point/primitive enumeration fields,
a point group, a native boundary-edge group, a surviving-face group, strict
boundary preservation, equal-length weighting, and a 40% polygon target. The
first correct adaptive implementation recomputed each incident face plane for
every point and allocated new quadric/validation planes every round. Single-run
release baselines were 1.403/1.312 s on one/four domains with 2.043/1.752 GB
allocated. This pre-normalization baseline used hash
`2819317508756127229`; the final scale-normalized metric intentionally changes
cost ties while remaining exact across domain counts.

Precomputing each normalized face plane once per round removes allocation from
the point-incidence loop. Reusing maximum-capacity packed quadric, face,
cost/incidence, lock, and stamp planes across the seven shrinking contraction
rounds removes the remaining repeated planner buffers; topology/payload output
still allocates new immutable current/next snapshots by design. Final five-run
release medians are 1.304/1.237 s, allocations are 1.486/1.487 GB, promoted
bytes are 39,832/66,560, and major allocations are 1.134/1.134 GB. Output
cardinality checksum 481,915 and hash `386166488769867098` are exact across
domains. A four-domain `/usr/bin/time -v` run reported 786,748 KiB maximum RSS. The modest
1.06x speedup is honest: plane/quadric and cost formation are parallel, while
global deterministic cost sorting, conflict selection, and seven topology
rebuilds dominate this medium fixture.

The original-position variant disables boundary locking and contracts to the
stable lower-numbered endpoint. Its final medians are 1.054/1.001 s with
1.238/1.239 GB allocated, 34,992/50,272 promoted bytes, 909.198/909.213 MB major
allocation, checksum 481,604, and exact hash `3508621272046085748`. These rows
are a production regression baseline, not a claim that adaptive reduction is
allocation-free: a future mutable half-edge priority implementation must beat
both wall time and peak memory while preserving the exact ancestry and
topology-validity matrix.

```sh
PRISMEL_PDK_OPS_FILTER=poly_reduce PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=poly_reduce PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

Remesh uses the same 420x320 alternating-triangle grid as PolyReduce: 134,400
points, 267,322 input triangles, vertex UVs, and point/primitive enumeration
payload. One topology iteration selects 133,661 long edges, creates 268,061
points and 534,644 triangles, then contracts a topology-safe independent set
to 225,234 points and 448,990 triangles. The first correct composition called
Edge Divide and general polygon Triangulate as separate immutable snapshots;
the complete projected/diagnostic iteration took 2.167/1.752 s and allocated
1.683/1.576 GB on one/four domains, with about 1.089 GB of major allocation.

The production path fuses triangle subdivision into one cardinality-planned
output with fixed eight-case topology emission. Point/vertex interpolation,
ordinary and ordered groups, primitive ancestry, and topology-affine native
edges retain the same documented semantics; the all-edge case deliberately
uses the isotropic four-triangle pattern instead of an arbitrary N-gon ear fan.
Edge Collapse now defers native-edge remapping until cleanup has produced the
final topology and composes source-to-cluster and cluster-to-output point maps,
eliminating two reverse-topology indexes and an intermediate edge-group
payload. Projection builds the immutable source BVH once per cook and reuses
exact-sized result planes across iterations.

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
PRISMEL_PDK_OPS_FILTER=remesh PRISMEL_PDK_OPS_REPEATS=3 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=remesh PRISMEL_PDK_OPS_REPEATS=3 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=boolean_detect PRISMEL_PDK_OPS_COLUMNS=240 \
PRISMEL_PDK_OPS_ROWS=180 PRISMEL_PDK_OPS_REPEATS=3 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=boolean_detect PRISMEL_PDK_OPS_COLUMNS=240 \
PRISMEL_PDK_OPS_ROWS=180 PRISMEL_PDK_OPS_REPEATS=3 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

Intersection Analysis measures point/provenance materialization in addition
to mixed-piece traversal. Sparse AxB uses two 420x320 grids (268,800
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

Sparse and self modes scale through BVH and disjoint two-pass narrow-phase
ranges. Dense coplanar output is limited by stable serial spatial welding and
first-incidence provenance aggregation; the 1.18x result is a remaining
parallelization target, not linear multicore scaling. Reproduce a row by
selecting its prefix, for example:

```sh
PRISMEL_PDK_OPS_FILTER=intersection_analysis_crossing \
PRISMEL_PDK_OPS_COLUMNS=420 PRISMEL_PDK_OPS_ROWS=320 \
PRISMEL_PDK_OPS_REPEATS=5 PRISMEL_BENCH_DOMAINS=4 \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

The mixed index replaces the former triangle-only traversal without building
a redundant triangle surface index. Its first correct bounds reduction used
generic `Float.min`/`Float.max` calls at every BVH level and measured about
389/221 ms for the sparse row on one/four domains. Direct comparisons in that
hot reduction lowered the final medians to 315/192 ms. Against the preceding
triangle-only recorded baseline, sparse time improved 2.8%/1.3%, self time
improved 19.3%/13.4%, dense coplanar time remained within 0.4%, and all exact
hashes stayed unchanged. Total allocation fell in every triangle fixture;
the mixed index retains explicit piece bounds, so sparse major live bytes rose
while total allocated bytes fell.

PolyBevel uses 10,000 disconnected attributed boxes: 80,000 points, 60,000
source polygons, 240,000 source corners, and all 120,000 unique edges selected.
The chamfer case emits a 1,460,000-element cardinality checksum. The divided
round case uses four profile divisions plus point/vertex integer payload,
point-distance scale, and generated groups, and emits 4,700,000 elements.

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
PRISMEL_PDK_OPS_FILTER=poly_bevel PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=poly_bevel PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

Point Split uses a 500x400 quad grid with 200,901 points, 200,000 primitives,
and 800,000 corners. The fixture carries a point integer ID, vertex float2 UV
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
PRISMEL_PDK_OPS_FILTER=point_split PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=point_split PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=point_generate PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=point_generate PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
```

Point Replicate uses 100,000 source points and emits 600,000 points. Sources
carry a count-scale Float, stable integer `id`, `pscale`, `N`, `v`, and a
generic Float3 vector; the selected payload is copied and a generated group is
written. A separate diagnostic
measures the canonical four-point instancing bases (400,000 frame points) and
the Point Generate emission stage so transform compatibility overhead remains
visible rather than hidden in one aggregate number.

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
PRISMEL_PDK_OPS_FILTER=point_replicate PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=point_replicate PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=edge_flip PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=edge_flip PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

Edge Cusp selects every edge of a 300x250 triangle grid carrying point normals,
point UV/ID fields, a vertex float2 field, an ordered-capable point group, and
a native edge group. It expands 75,551 input points to 450,000 fan-separated
points while retaining 450,000 corners. The initial five-run release medians
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
PRISMEL_PDK_OPS_FILTER=edge_cusp PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=edge_cusp PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
```

Edge Straighten measures 100,000 independent three-point bends (300,000
points/vertices and 200,000 selected edges) with point integer payload, a point
group, and output native-edge-group creation. The correctness audit found that
a single-axis power seed can be exactly orthogonal to the dominant covariance
eigenvector. The corrected three-seed baseline measured 34.748/35.643 ms and
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
PRISMEL_PDK_OPS_FILTER=edge_straighten PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=edge_straighten PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile=release tools/bench_pdk_ops.exe
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
PRISMEL_CIRCLE_EDGE_POINTS=1000000 PRISMEL_CIRCLE_EDGE_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release \
    tools/bench_circle_from_edges.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
PRISMEL_GRAPH_COLOR_ELEMENTS=1000000 PRISMEL_GRAPH_COLOR_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release \
    tools/bench_graph_color.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
The headless `test/procedural_render_smoke.exe` scene exercises Mountain,
Point Jitter with group/mask/stable-ID/`pscale`, Peak, atomic pattern Attribute
Delete/Rename feeding a visible promoted color,
Edge Divide with a selected native edge group and four shared segments,
Edge Collapse with a seeded native edge group, cleanup, and normal rebuild,
Edge Flip with a selected manifold diagonal and normal rebuild,
Edge Cusp with a selected path, point-fan duplication, and normal rebuild,
Edge Straighten with a selected curved path and output native edge group,
Group Range/Combine/Invert/Delete, Group Expand/Promote, boundary-only
Group Promote with attribute seams, Group Normal,
Group Non-Planar, Group Backface, Group Edge Depth, pairwise Incident-Edge
Angle, Group Unshared, boundary-component groups, connected-region Poly
Extrude with divisions and output groups, Clean winding/group cleanup,
position-independent second-input crease topology with resulting sharpness,
stencil-contributing subdivision holes with visible openings,
and a
Groups-from-Name-selected plus bounds-restricted random
primitive deformation driving visible geometry, sphere-volume
jitter, direction sampling, and inverse-CDF color variation on lit textured
meshes; its one/four-domain 160x120 PNGs are byte-identical (SHA-256
`fc98b7188ca058d286a08a819da4c0a4553cad69a447da9eb6ee4a0b12941d7f`,
17,441 bytes).

```sh
PRISMEL_PDK_OPS_FILTER=peak PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=peak PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=mountain PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=mountain PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=measure PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=measure PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 opam exec --switch=. -- \
  dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=connectivity PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=connectivity PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
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

The representative headless procedural scene now includes an ordered
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
PRISMEL_PDK_OPS_FILTER=group_find_path PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=group_find_path PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=group_transfer PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
PRISMEL_PDK_OPS_FILTER=group_transfer PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=4 dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_FILTER=groups_from_name PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use /usr/bin/time -v for process RSS.
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
PRISMEL_PDK_OPS_FILTER=name_from_groups PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
PRISMEL_PDK_OPS_FILTER=group_random PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
PRISMEL_PDK_OPS_FILTER=group_bounds PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
PRISMEL_PDK_OPS_FILTER=group_normal PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_non_planar PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_backface PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_edges_incident_angle PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_edges_dihedral_angle PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_edge_depth_points PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_unshared PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_boundary_components PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=group_range PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
```

PDK Reverse was measured on the 1,002,001-point/two-million-triangle grid
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
PRISMEL_PDK_OPS_FILTER=reverse_ PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env PRISMEL_PDK_OPS_FILTER=reverse_ \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
```

PDK Triangulate was measured on a 1,002,001-point/one-million-quad grid
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
PRISMEL_PDK_OPS_FILTER=triangulate_quads PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env PRISMEL_PDK_OPS_FILTER=triangulate_quads \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
```

PDK Normals was measured on a 1,002,001-point/two-million-triangle grid
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
PRISMEL_PDK_OPS_FILTER=normals_ PRISMEL_PDK_OPS_REPEATS=5 \
PRISMEL_BENCH_DOMAINS=1 dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  PRISMEL_PDK_OPS_FILTER=normals_vertex_angle_vertices_cusp60 \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
PRISMEL_PDK_OPS_FILTER=edge_group_topology_index_cold \
PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 \
PRISMEL_PDK_OPS_FILTER=transform_selected \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 \
PRISMEL_PDK_OPS_FILTER=soft_transform \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 \
PRISMEL_PDK_OPS_FILTER=distance_along \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  PRISMEL_PDK_OPS_FILTER=distance_along_edge_full_fixed_mask \
  PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 \
PRISMEL_PDK_OPS_FILTER=distance_from \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  PRISMEL_PDK_OPS_FILTER=distance_from_surface_full_fixed_mask \
  PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 \
PRISMEL_PDK_OPS_FILTER=distance_from_target \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  PRISMEL_PDK_OPS_FILTER=distance_from_target_planar_signed_maximum \
  PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 \
PRISMEL_PDK_OPS_FILTER=sort_extended \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  PRISMEL_PDK_OPS_FILTER=sort_extended_spatial_locality \
  PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_BENCH_DOMAINS=1 \
PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=blast_by_attribute \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
/usr/bin/time -v env \
  PRISMEL_PDK_OPS_FILTER=blast_by_attribute_primitive_delete_compact \
  PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
  PRISMEL_PDK_OPS_REPEATS=1 PRISMEL_BENCH_DOMAINS=4 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=crease PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
KiB RSS. Direct PDK, frame/cache-aware SOP, exact one/four-domain mesh, combined
procedural framebuffer, and dedicated visible 320x240 framebuffer tests cover
the path.

```sh
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=attribute_fade PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4 and use attribute_fade_reference for the
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=poly_cut PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4 and use poly_cut_reference for the
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=separate_pieces PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4 and use separate_pieces_reference for
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
published PDK scale-safe average, not lost geometry fidelity.

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
OCaml 5.3.0 runner. Exact one/four-domain PDK geometry, SOP render meshes, and
360x240 framebuffer PNGs are regression-tested.

```sh
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=edge_equalize PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use edge_equalize_reference for the
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
aarch64 / OCaml 5.3.0 runner. Exact connected and disjoint PDK/SOP geometry,
render meshes, and dedicated framebuffer PNGs cover domain-count regression.

```sh
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=edge_relax PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use edge_relax_reference for the
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
PRISMEL_PDK_OPS_COLUMNS=1000 PRISMEL_PDK_OPS_ROWS=1000 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=blend_shapes PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use blend_shapes_reference for the
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
PRISMEL_PDK_OPS_COLUMNS=1000 PRISMEL_PDK_OPS_ROWS=1000 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=attribute_composite PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use attribute_composite_reference for
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
PRISMEL_PDK_OPS_COLUMNS=1000 PRISMEL_PDK_OPS_ROWS=1000 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=attribute_mirror PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use attribute_mirror_reference for the
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
PRISMEL_PDK_OPS_COLUMNS=1000 PRISMEL_PDK_OPS_ROWS=1000 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=rewire_vertices PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use rewire_vertices_reference for the
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
PRISMEL_PDK_OPS_COLUMNS=500 PRISMEL_PDK_OPS_ROWS=300 \
PRISMEL_PDK_OPS_REPEATS=7 PRISMEL_PDK_BENCH_GRAIN=16384 \
PRISMEL_PDK_OPS_FILTER=edge_transport PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_pdk_ops.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4; use edge_transport_reference or
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
the headless framebuffer equals an explicit cube reference byte-for-byte.

```sh
PRISMEL_HULL_REPEATS=3 PRISMEL_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_convex_hull.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4 and wrap either command in
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
277,012 KiB. PDK tests cover lower-dimensional and solid hull centers, stable
integer/text identity, detail sharing, malformed input and cancellation; SOP
tests cover cache identity and exact domain output; the headless framebuffer is
byte-identical to explicit reference centers.

```sh
PRISMEL_CENTROID_SIZE=1000000 PRISMEL_CENTROID_REPEATS=3 \
PRISMEL_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release tools/bench_extract_centroid.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4.
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
PDK tests cover exact vertices, plateaus, crossings, open endpoints, closed
seams, primitive targets/selections, numeric/discrete/ragged payload, empty and malformed
input, non-finite values, `max_float` interpolation, cancellation, 100,000
small curves, and a 200,001-point blocked curve. SOP tests cover immutable
identity, static caching, current-time invalidation, errors, and exact domain
output. The headless framebuffer is byte-identical across one/four domains and
to explicit reference cut points.

```sh
PRISMEL_EXTRACT_REPEATS=5 PRISMEL_BENCH_DOMAINS=1 /usr/bin/time -v \
  opam exec --switch=. -- dune exec --profile release \
  tools/bench_extract_point_curve.exe
# Repeat with PRISMEL_BENCH_DOMAINS=4. For the long-curve campaign add:
# PRISMEL_EXTRACT_CURVES=1 PRISMEL_EXTRACT_POINTS_PER_CURVE=1000001
```

## Hot-path review checklist

1. Confirm asymptotic complexity and identify the dominant allocation.
2. Check whether output size is knowable and allocate exactly when it is.
3. Remove list/array conversion cycles and per-element option/closure boxes.
4. Hoist invariant transforms, materials, light data, and lookup tables.
5. Partition only sufficiently coarse independent work.
6. Verify sequential/parallel byte-identical ordering.
7. Measure elapsed time, minor/major allocation, and live memory.
8. Run correctness, headless, documentation, and diff checks.
