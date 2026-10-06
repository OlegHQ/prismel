# RDK measurement log

Append-only record of measurements taken for [rdk.md](rdk.md); it is not normative.

## Implemented operator surface

### Crease authoring

The release benchmark command is:

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
  RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
  RAYS_RDK_OPS_FILTER=crease RAYS_BENCH_DOMAINS=1 \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
  RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
  RAYS_RDK_OPS_FILTER=crease RAYS_BENCH_DOMAINS=4 \
  dune exec --profile=release tools/bench_rdk_ops.exe
```

On the four-core aarch64 CI host with OCaml 5.3.0, a 500 by 300 quad grid has
150,801 points, 600,000 corners, and 300,800 unique edges. Seven-run release
medians at grain 16,384 are:

| Cook | 1 domain | 4 domains | allocated, 1/4 domains |
|---|---:|---:|---:|
| sparse Set | 2.477 ms | 1.129 ms | 4.803 / 4.812 MB |
| sparse Add with incident maximum reduction | 5.344 ms | 2.275 ms | 7.898 / 7.434 MB |
| sparse Delete | 3.769 ms | 1.543 ms | 4.804 / 4.821 MB |
| all-edge Set | 1.747 ms | 0.811 ms | 4.803 / 4.811 MB |
| sparse Set plus endpoint color | 11.519 ms | 8.092 ms | 31.225 / 27.840 MB |

The former manual per-corner Set workflow measured 3.387/3.651 ms and
13.028 MB; the packed kernel is 1.37x faster on one domain and 3.23x faster on
four while allocating 63% less. Manual Delete measured 3.756/3.571 ms and
13.028 MB; the packed result is 2.31x faster at four domains with the identical
hash and 63% less allocation. The manual Add row is not a correctness oracle:
it independently incremented asymmetric incident corners, whereas the new
kernel performs the required unique-edge maximum reduction. The optimized Add
still scales 2.35x from one to four domains. All one/four-domain hashes and
rendered framebuffer bytes match; the complete four-domain benchmark process
peaked at 123,160 KiB RSS.

### Attribute Fade

The release benchmark uses a 500x300 quad grid (150,801 points), every seventh
point excluded, float fade/start/hold fields, four-knot ramps, frame 137.25,
grain 16,384, and seven medians on the four-core Linux aarch64/OCaml 5.3.0
runner:

| Cook | 1 domain | 4 domains | allocated, 1/4 domains | Exact hash |
|---|---:|---:|---:|---:|
| selected four-knot ramps | 1.815 ms | 0.754 ms | 1.212 / 1.215 MB | `3899516654851549430` |
| all points/default ramps | 1.366 ms | 0.564 ms | 1.212 / 1.215 MB | `147492431177321602` |
| selected ramps plus `Cd` | 3.143 ms | 2.185 ms | 6.038 / 6.042 MB | `3597614511156252915` |

The retained manual scalar reference is intentionally unchecked and serial: it
measured 1.314/1.322 ms and allocated 3.620/3.620 MB. The production kernel's
selected-ramp one-domain path pays 0.501 ms for full validation/cancellation,
but allocates 66.5% less; four domains are 1.75x faster than that reference
with the identical result hash. The packed kernel itself scales 2.41x from one
to four domains. Exact one/four-domain attribute, render-mesh, and dedicated
320x240 native-framebuffer regressions pass. The complete four-domain
benchmark process peaked at 64,568 KiB RSS.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=attribute_fade RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4. Use attribute_fade_reference for the
# retained unchecked scalar baseline.
```

### PolyCut

The release fixture contains 300 independent 501-point curves (150,300
points), a scalar sawtooth crossing field, grain 16,384, and seven medians on
the four-core Linux aarch64/OCaml 5.3.0 runner:

| Cook | 1 domain | 4 domains | allocated, 1/4 domains | Output cardinality | Exact hash |
|---|---:|---:|---:|---:|---:|
| edge Remove/crossing | 5.532 ms | 3.479 ms | 8.041 / 7.370 MB | 311,161 | `990841547120428818` |
| edge Cut/crossing | 16.182 ms | 11.839 ms | 60.617 / 37.868 MB | 352,625 | `3032578540479040296` |
| edge Cut/change, threshold 3 | 21.232 ms | 16.519 ms | 86.497 / 53.245 MB | 533,640 | `722701032308820201` |

The retained allocation-heavy serial reference for crossing removal measured
4.321 ms and 11.246 MB. The four-domain packed fast path is 1.24x faster,
allocates 34.5% less, and produces the identical complete geometry hash; it
scales 1.59x from the validated one-domain path. Cut modes necessarily emit
interpolated endpoint and ancestry planes and scale 1.37x/1.29x. The complete
four-domain benchmark process, including all three cooks and Dune/opam runtime,
peaked at 85,048 KiB RSS. Direct RDK, immutable SOP/cache, every-storage,
malformed/cancellation, exact one/four-domain mesh, and visible 360x240
framebuffer regressions cover the operation.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=poly_cut RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4 and use poly_cut_reference for the
# retained serial/list crossing-removal baseline.
```

### Separate Pieces

The release fixture contains 300 overlapping independent 501-point curves
(150,300 points), dense primitive integer identities, gap `0.01`, grain
16,384, and seven warm-index medians on the four-core Linux aarch64/OCaml 5.3.0
runner:

| Cook | Time | Allocated | Cardinality | Exact hash |
|---|---:|---:|---:|---:|
| validated packed, 1 domain | 3.313 ms | 3,700,272 B | 300,900 | `3435451684132487927` |
| validated packed, 4 domains | 2.360 ms | 3,711,256 B | 300,900 | `3435451684132487927` |
| retained unchecked serial reference | 2.640 ms | 13,239,208 B | 300,900 | `3435451684132487927` |

Four domains scale 1.40x from the validated one-domain path and are 1.12x
faster than the narrow serial reference while allocating 72.0% less. The
reference assumes dense primitive-to-point correspondence and omits owner,
topology, finite-value, overflow, and cancellation validation. The direct cold
four-domain process, including fixture and topology-index construction, peaked
at 50,204 KiB RSS. Direct point/primitive, integer/text, Move Back,
malformed/cancellation, exact one/four-domain geometry/mesh, immutable SOP
cache, and visible 360x240 framebuffer regressions cover the operation.

```sh
RAYS_RDK_OPS_COLUMNS=500 RAYS_RDK_OPS_ROWS=300 \
RAYS_RDK_OPS_REPEATS=7 RAYS_RDK_BENCH_GRAIN=16384 \
RAYS_RDK_OPS_FILTER=separate_pieces RAYS_BENCH_DOMAINS=1 \
  opam exec --switch=. -- dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4 and use separate_pieces_reference for
# the retained serial baseline.
```

### Measure Curvature

The release benchmark command is:

```sh
dune build --profile release tools/bench_curvature.exe
RAYS_BENCH_DOMAINS=1 RAYS_CURVATURE_POINTS=1000000 \
  RAYS_CURVATURE_REPEATS=3 _build/default/tools/bench_curvature.exe
RAYS_BENCH_DOMAINS=4 RAYS_CURVATURE_POINTS=1000000 \
  RAYS_CURVATURE_REPEATS=3 _build/default/tools/bench_curvature.exe
```

On the repository benchmark host with OCaml 5.3.0 release profile, a torus with
1,000,000 points, 1,000,000 quads, and 2,000,000 internal triangles produced:

| Workload | 1 domain | 4 domains | Wall reduction | Exact hash |
| --- | ---: | ---: | ---: | ---: |
| Mean only | 0.471 s | 0.300 s | 36.3% | `-5046078577941067272` |
| Six fields, two smoothing steps | 0.643 s | 0.354 s | 45.0% | `8793907604084536345` |

Median calling-domain allocations were respectively 681/434 MB and 897/548
MB; that counter excludes worker-domain minor allocations. Measured major
allocation was about 329 MB for mean and 401 MB for the smoothed six-field
case. A cold one-repeat four-domain process running both workloads peaked at
896,228 KiB RSS. These are baselines for further scratch/CSR compaction, not a
claim of zero allocation.

### Attribute Laplacian

The release benchmark command is:

```sh
dune build --profile release tools/bench_laplacian.exe
RAYS_BENCH_DOMAINS=1 RAYS_LAPLACIAN_POINTS=1000000 \
  RAYS_LAPLACIAN_REPEATS=3 _build/default/tools/bench_laplacian.exe
RAYS_BENCH_DOMAINS=4 RAYS_LAPLACIAN_POINTS=1000000 \
  RAYS_LAPLACIAN_REPEATS=3 _build/default/tools/bench_laplacian.exe
```

On the same OCaml 5.3.0 release-profile host, a 1,000,000-point,
1,000,000-quad torus with a float3 `P` source produced:

| Workload | 1 domain | 4 domains | Wall reduction | Exact hash |
| --- | ---: | ---: | ---: | ---: |
| Pointwise signed cotangent | 0.471 s | 0.280 s | 40.6% | `-8996758845128957858` |
| Pointwise positive cotangent | 0.475 s | 0.281 s | 40.8% | `7819334971099552542` |
| Uniform neighbor average | 0.165 s | 0.132 s | 19.8% | `6174720405700189381` |

Median calling-domain allocation was 625/391 MB for signed and positive
cotangent, and 73/73 MB for uniform one/four-domain
runs; worker-domain minor allocation is not included in that counter. Major
allocation was about 289 MB for metric modes and 73 MB for uniform. A cold
four-domain process running all three cases once peaked at 826,196 KiB RSS.
Replacing polymorphic float `max` in the positive-cotangent incidence loop
removed 48 MB of measured allocation at 250,000 points without changing its
hash.

### Triangulate 2D

_Continues "`Rdk.Voronoi2.cells` owns bounded pairwise half-plane clipping for ordered…" in rdk.md:_
During migration, a 64-site release benchmark of the
former Geom adapter preserved the ordered cell digest and overlapped clean
`HEAD` timing (0.494–0.495 ms before, 0.497 ms after per call, 500 calls per run).

_Continues "`Rdk.Iso_surface` streams XY slabs while extracting a six-tetrahedra…" in rdk.md:_
The dense RDK gyroid benchmark at 40³ cells emits
52,860 triangles and records position/topology digest `420974040`.
Historical matched release Geom calls (nine repeats, two interleaved pairs)
preserved 158,580 vertices and
full mesh digest `600041751`: one-domain medians are 21.392/22.780 ms on
clean `HEAD` versus 18.652/20.317 ms after the port, with only 496 more
caller-allocated bytes. Four-domain medians are 21.294/37.748 versus
19.747/21.207 ms under variable host scheduling, with the same digest.

With OCaml 5.3.0, Dune 3.24.0's default development profile, grain 16,384,
and the four-core Linux 6.8/aarch64 runner used by the surrounding RDK table,
100,000 deterministic points produced 199,918 triangles in a 0.949-second
median with 65.7 MB current-domain allocation and 1,648 promoted bytes (three
repetitions, one domain).
That allocation figure is the current optimization baseline, not a production
claim. The exact undocumented SideFX numerical regularization profile remains
an explicit parity gate before this node can move out of Partial status.

On the same 100,000-point source whose existing 199,918 triangles carry one
vertex float and one primitive integer field, Keep Primitives produced a stable
399,836-face result in a 1.008-second median with 130.86 MB current-domain
allocation, 3,096 promoted bytes, 88.38 MB major allocation, and topology hash
`2887283567451037009` on one domain. Four domains produced the identical hash
in 0.995 seconds with 121.32 MB current-domain allocation; dependency-ordered
Delaunay construction dominates this adapter workload, so no multicore speedup
is claimed.

On the same 100,000-point seed, disabling original-position restoration
materialized all projected `P` planes and 199,918 triangles in a 0.997-second
median with 94.68 MB current-domain allocation, 3,008 promoted bytes, and
55.20 MB major allocation on one domain. Four domains produced the identical
topology hash `2710672592452761305` in 0.990 seconds with 88.40 MB current-
domain allocation. Delaunay construction remains serial and dominates, so the
parallel materialization does not justify a multicore speedup claim.

On the same 100,000-point seed, recovering one legal long constraint and
repairing 199,918 triangles takes a 0.234-second median with 81.88 MB allocated,
960 promoted bytes, and stable hash `4607585910187537252`.

The exact arrangement benchmark uses two complementary workloads. 100,000
disjoint segments take a 0.0909-second median with 92.50 MB current-domain
allocation, 2,120 promoted bytes, and stable hash `521543672821096657`.
A 256-by-256 crossing grid constructs and deduplicates 65,536 exact split
points in a 0.277-second median with 155.91 MB allocated and stable hash
`331324657301745941`. Before the no-crossing fast path and linear BVH-bound
construction, the disjoint workload took 1.048 seconds, allocated 546.64 MB,
and promoted 98.42 MB on the same process configuration.

One constraint containing 100,000 authored collinear points atomizes into
99,999 edges in a five-run median of 0.135 seconds on one domain and 0.116
seconds on four domains, with stable hash `2878715107207330704`. The
one-domain path allocates 82.40 MB on the calling domain; the four-domain
calling-domain figure is 42.82 MB because worker-domain minor allocation is
not included by `Gc.allocated_bytes`. Before this path existed, the valid
input failed constraint recovery instead of producing a benchmarkable result.

The duplicate-removal adapter benchmark selects 100,000 points at four exact
projected coordinates, with distinct authored Z values. It retains the lowest
selected representative at each coordinate and compacts to four points in a
0.0258-second one-domain median and a 0.0254-second four-domain median. The
packed topology hash is `3186253908326029459` in both modes; calling-domain
allocation is 15.93 MB and 13.84 MB respectively. This is a selective deletion
baseline, not a global Remove Unused Points measurement.

The bounded quality-refinement benchmark starts from a unit square and targets
an edge length of `1.8 / sqrt(100000)`. It emits 66,049 points in a three-run
median of 1.483 seconds on one domain and 1.549 seconds on four domains, with
identical hash `3660410599853783093`. Calling-domain allocation is 1.067 GB and
757.08 MB respectively; promoted allocation is approximately 92.4 MB and major
allocation is 203.9 MB in both modes. Against the pre-workspace one-domain
implementation on the same command, reusable/incremental CDT state, in-place
canonicalization, and allocation-free classification reduced wall time by
2.6%, calling-domain allocation by 7.1%, and major allocation by 20.9%. The lack
of multicore speedup is recorded honestly: serial CDT recovery dominates
this workload, and worker-domain minor allocation is excluded from the four-
domain calling-domain figure. This remains a regression baseline, not a
production claim.

A constrained refinement scale case uses a 10,000-edge closed boundary and a
256-point budget. The former candidate-by-constraint scan took 2.778 seconds
and allocated 7.108 GB on the calling domain; the shared packed bounds index
produces the identical 10,256-point result and hash `5576516039082866` in a
three-run 0.256-second median with 192.87 MB allocated. These use the same
process configuration, a 10.8x wall-time and 36.9x allocation
improvement. Reproduce the scale with `RAYS_REFINEMENT_CONSTRAINTS=10000`.

The regularization benchmark refines the unit square to 8,321 points, then runs
two relaxation steps. The zero-step seed takes a 0.154-second median and
132.55 MB calling-domain allocation; the two-step cook takes 0.282 seconds and
211.52 MB on one domain. Four domains take 0.161 and 0.300 seconds respectively,
so the current serial packed-edge sort and CDT repair dominate at this size and
no speedup is claimed. One and four domains produce exact hashes
`4415231494534350957` before movement and `192142334138055436` after two steps.
These are three-repeat OCaml 5.3 development-profile baselines with
`RAYS_REGULARIZATION_POINTS=10000`.

A steady coordinate-repair benchmark starts from the same canonical
199,918-triangle snapshot with no inserted points or constraints. Rebuilding
incidence on every cook takes 0.228 seconds and allocates 70.48 MB on one
domain. After one unmeasured workspace warm-up, exact-snapshot continuation
takes 0.170 seconds and allocates 21.79 MB, with major allocation falling from
59.29 MB to 10.60 MB. That is 25.3% less wall time, 69.1% less calling-domain
allocation, and 82.1% less major allocation. Four domains take 0.228 and 0.171
seconds respectively with the identical topology hash
`2710672592452761305`; the kernel remains dependency-ordered, so this is
amortized state reuse rather than a parallel speedup claim.

An unblocked hull flood over the 199,918-triangle seed removes the complete
triangulation in a 0.191-second median with 72.48 MB allocated and stable empty
hash `17`. Empty polygon winding classification traverses the same seed in a
0.203-second median with 82.08 MB allocated and the same empty hash.

An explicit triangular constraint over a 100,000-point source cooks in 0.924
milliseconds on one domain and 0.991 milliseconds on four when Ignore
Non-Constraint Points is enabled. It emits one triangle with stable hash
`4798887604116780`, retains the other source points as isolated payload, and
allocates 1.83 MB on the calling domain. The corresponding unrestricted
Delaunay seed alone takes 0.949 seconds, demonstrating that endpoint
prefiltering occurs before the expensive topology construction.

The complete projected-silhouette adapter benchmark starts from the same
100,000 points and their 199,918 authored triangular faces, extracts the hull
silhouette, recovers it, and emits the unchanged triangulation. Its three-run
median is 1.416 seconds on one domain and 1.419 seconds on four domains, with
identical hash `2710672592452761305`. The corresponding allocations are
364.79 MB and 342.94 MB. The measured workload is dominated by the serial
Delaunay and topology-index stages; the four-domain result is retained as an
honest regression baseline rather than presented as a speedup. The complete
one-repeat benchmark process, including every workload in the executable,
peaks at 241,240 KiB RSS on one domain.

Reproduce the baseline with:

```sh
RAYS_DELAUNAY_POINTS=100000 RAYS_DELAUNAY_REPEATS=3 \
  RAYS_REFINEMENT_POINTS=100000 RAYS_REGULARIZATION_POINTS=10000 \
  RAYS_DELAUNAY_DOMAINS=1 \
  dune exec -j 1 tools/bench_delaunay2.exe
```

## Performance contract

### Benchmark evidence

Command (Dune release profile, five medians):

```sh
dune build --profile release tools/bench_rdk_ops.exe
RAYS_BENCH_DOMAINS=1 RAYS_RDK_OPS_REPEATS=5 \
  _build/default/tools/bench_rdk_ops.exe
RAYS_BENCH_DOMAINS=4 RAYS_RDK_OPS_REPEATS=5 \
  _build/default/tools/bench_rdk_ops.exe
```

Measured on Linux 6.8 aarch64, four single-threaded cores, OCaml 5.3.0 and
Dune 3.24.0. The main grid fixture has 1,002,001 points, 6,000,000 vertices,
and 2,000,000 triangles. Times are medians; allocations include required output
storage.

| Operation | 1 domain | 4 domains | Allocated (4d) | Exact hash |
|---|---:|---:|---:|---:|
| Circle source, closed (1,002,001 points) | 22.94 ms | 13.21 ms | 32.08 MB | 1595635405635298122 |
| Circle source, elliptical open arc (1,002,002 points) | 22.75 ms | 12.04 ms | 32.08 MB | 1225605752256974054 |
| Circle source, custom-plane reversed sliced ellipse (1,002,003 points) | 23.06 ms | 11.51 ms | 32.08 MB | 4305788162832572827 |
| Grid source, regular triangles (1,002,001 points / 2,000,000 triangles) | 42.29 ms | 26.87 ms | 114.22 MB | 3253461948889680712 |
| Grid source, quads (1,002,001 points / 1,000,000 quads) | 29.70 ms | 23.24 ms | 89.18 MB | 664173605796900264 |
| Grid source, rows and columns (2,002 open curves) | 126.65 ms | 28.16 ms | 64.19 MB | 208363250742641765 |
| Grid source, custom orientation + UV + alternating triangles | 47.41 ms | 37.00 ms | 130.27 MB | 2771498784011449356 |
| transform | 16.1 ms | 7.8 ms | 48.1 MB | 4154521212671282630 |
| noise displace | 27.9 ms | 9.3 ms | 32.1 MB | 3788867606196721633 |
| normals, geometric area weighted | 68.1 ms | 50.5 ms | 72.1 MB | 3253461948889680712 |
| Peak, point `N` + mask | 14.8 ms | 10.6 ms | 24.1 MB | 3517429522847750887 |
| Bend + twist + mask + capture | 46.9 ms | 23.8 ms | 32.1 MB | 338536710968759944 |
| Mountain, six-octave fBm + point `N` + height | 296.3 ms | 96.6 ms | 32.1 MB | 2870047288594138134 |
| Point Jitter, uniform component offsets | 16.36 ms | 11.73 ms | 24.05 MB | 4306816342677270420 |
| Point Jitter, group + mask + stable ID + `pscale` | 17.30 ms | 10.75 ms | 24.05 MB | 1943467239589564005 |
| Edge Divide, shared points, 4 segments (75,551-point quad grid) | 213.32 ms | 174.36 ms | 327.23 MB | 23138927581944883 |
| Edge Divide, unique points, 4 segments (75,551-point quad grid) | 355.68 ms | 272.08 ms | 450.56 MB | 430669910521685374 |
| Edge Collapse, sparse centers + cleanup (200,901-point quad grid) | 184.10 ms | 165.43 ms | 329.91 MB | 3813930426841543590 |
| Point Split, unique corners (200,901-point / 800,000-corner quad grid) | 136.47 ms | 111.47 ms | 136.26 MB | 1759525763580531095 |
| Point Split, primitive-group seam (same grid) | 147.55 ms | 102.26 ms | 142.84 MB | 1376946659531591241 |
| Point Split, mixed attribute/group seams + promotion (same grid) | 206.08 ms | 147.87 ms | 206.59 MB | 1955015017167342198 |
| Extract Centroid, primitive AABB (501,264-point / 999,698-triangle grid) | 41.35 ms | 24.76 ms | 79.23 MB | 1441361096299877289 |
| Extract Centroid, 499,849 primitive pieces (same grid) | 456.72 ms | 447.03 ms | 149.94 MB | 2510410779901382919 |
| Extract Point from Curve, 1,000 sparse cuts / 1,001,000 points | 8.99 ms | 4.98 ms | 0.08 MB | 2773787659351257617 |
| Extract Point from Curve, 1,000,000 dense cuts / 1,001,000 points | 30.72 ms | 22.61 ms | 56.02 MB | 1447278196685623313 |
| Extract Point from Curve, dense payload and diagnostics | 56.34 ms | 38.77 ms | 96.10 MB | 2465483108862112169 |
| Ends, shared unroll of one 1,002,001-corner curve | 3.88 ms | 3.17 ms | 13.03 MB | 1746403283212006364 |
| Ends, new-point unroll of 100,000 independent quads | 25.95 ms | 19.88 ms | 81.42 MB | 162055801192148878 |
| Ends, shared-point unroll of 159,201 grid faces | 49.23 ms | 47.14 ms | 53.00 MB | 1963371227389512144 |
| Point Generate, 1M origin points | 12.90 ms | 10.22 ms | 40.03 MB | 2425641456680199725 |
| Point Generate, 100k sources to 600k points with fixed/ragged payload | 44.14 ms | 26.21 ms | 76.09 MB | 3618383094568773800 |
| Point Generate, same payload with 100k retained input points | 55.72 ms | 36.92 ms | 98.60 MB | 1367188153682677381 |
| Point Replicate, sphere + source payload, 100k to 600k | 118.12 ms | 71.09 ms | 168.23 MB | 2137438907517278555 |
| Point Replicate, sphere + two transformed vectors, 100k to 600k | 176.88 ms | 98.25 ms | 223.06 MB | 3340732060582328136 |
| Point Replicate, quasi sphere + velocity, 100k to 600k | 127.60 ms | 72.49 ms | 171.16 MB | 28852990969694171 |
| Point Replicate, four-octave vector fBm, 100k to 600k | 577.58 ms | 207.26 ms | 167.77 MB | 187623304489263081 |
| Dissolve, million-quad grid to boundary polygon | 90.57 ms | 90.46 ms | 64.81 MB | 3098566088433871729 |
| Dissolve + inline cleanup to rectangle | 105.43 ms | 102.69 ms | 74.54 MB | 2525572738818699091 |
| Edge Flip, 50,000 disjoint triangle pairs (200,000 points) | 67.52 ms | 66.98 ms | 103.40 MB | 926999786504064952 |
| Edge Cusp, all triangle edges (75,551 input points / 450,000 output points) | 100.71 ms | 88.80 ms | 166.12 MB | 1534610466325191131 |
| Edge Straighten, 100,000 independent bends (300,000 points) | 21.87 ms | 15.67 ms | 26.06 MB | 1195252365093812429 |
| Circle from Edges, 62,500 independent loops (1,000,000 points) | 79.61 ms | 54.26 ms | 79.02 MB | 362519991447600667 |
| Circle from Edges, one 1,000,000-point loop | 55.21 ms | 46.78 ms | 66.02 MB | 4031980600791533435 |
| Graph Color, 333,333 disconnected triangle point cliques (999,999 points) | 50.58 ms | 29.31 ms | 57.12 MB | 1757474405289905926 |
| Graph Color, connected 1,000,000-quad primitive edge graph | 90.34 ms | 90.56 ms | 49.00 MB | 3023817910443667473 |
| Graph Color, connected 1,000,000-quad primitive point graph | 113.44 ms | 113.90 ms | 49.00 MB | 2608693175212566257 |
| Delaunay2, 100,000 deterministic planar points (199,918 triangles) | 928.28 ms | dependency-ordered topology build | 65.67 MB | 2710672592452761305 |
| Planar CDT, full repair of 199,918 canonical triangles | 228.20 ms | dependency-ordered rebuild | 70.48 MB | 2710672592452761305 |
| Planar CDT, incremental repair of the same snapshot | 170.40 ms | dependency-ordered retained incidence | 21.79 MB | 2710672592452761305 |
| Planar CDT, one long constraint over 199,918 triangles | 232.34 ms | dependency-ordered recovery | 72.28 MB | 4607585910187537252 |
| Planar CDT, unblocked hull flood over 199,918 triangles | 214.33 ms | dependency-ordered adjacency flood | 72.48 MB | 17 |
| Planar CDT, empty polygon-winding classification over 199,918 triangles | 227.58 ms | dependency-ordered winding flood | 82.08 MB | 17 |
| Planar constraints, 100,000 disjoint segments | 91.80 ms | exact arrangement is dependency ordered | 92.50 MB | 521543672821096657 |
| Planar constraints, 256x256 crossing grid (65,536 splits) | 285.33 ms | exact arrangement is dependency ordered | 155.91 MB | 331324657301745941 |
| Edge Equalize, 150,000 independent edges (300,000 points) | 5.21 ms | 3.79 ms | 3.61 MB | 908952120690714776 |
| Edge Relax, 150,000 disjoint reference constraints (300,000 points) | 7.39 ms | 4.65 ms | 4.81 MB | 1571942082499176816 |
| Edge Relax, 50,000 connected two-edge chains (150,000 points, 20 iterations) | 173.28 ms | 86.83 ms | 8.87 MB | 678064836994170377 |
| Blend Shapes, one target / 1M positions | 18.47 ms | 9.81 ms | 24.04 MB | 3058586826073456996 |
| Blend Shapes, two targets / 1M points with fields | 69.63 ms | 35.32 ms | 64.10 MB | 57601285729602360 |
| Blend Shapes, two masked targets / 1M points with fields | 85.46 ms | 43.58 ms | 72.13 MB | 3663501905707757503 |
| Attribute Composite Mean / 1M scalar points, 3 inputs | 13.76 ms | 5.51 ms | 8.06 MB | 1240842533481729218 |
| Attribute Composite Mean / 1M points, alpha + P/scalar/Float4 | 148.63 ms | 62.77 ms | 72.51 MB | 1262478998332998410 |
| Attribute Composite Over / 1M scalar points, 3 inputs | 19.04 ms | 7.82 ms | 8.09 MB | 1308454629395839844 |
| Attribute Mirror explicit map / 1M Float4 points | 32.02 ms | 20.20 ms | 41.00 MB | 3641797497992649622 |
| Attribute Mirror plane nearest / 1M Float4 points | 390.34 ms | 147.14 ms | 90.02 MB | 1685776360115969791 |
| Rewire Vertices direct / 999,999 points and corners | 5.72 ms | 3.92 ms | 11.00 MB | 288734399921472577 |
| Rewire Vertices cleanup + provenance / 999,999 points and corners | 33.21 ms | 27.51 ms | 50.33 MB | 2351447017972365808 |
| Rewire Vertices recursive / 999,999 points and corners | 17.09 ms | 15.15 ms | 36.00 MB | 3495472325552027740 |
| Edge Transport network, one 300,000-point curve | 20.97 ms | 18.50 ms | 27.01 MB | 898688424706882948 |
| Edge Transport Each Curve, one 300,000-point curve | 6.02 ms | 5.88 ms | 2.40 MB | 898688424706882948 |
| Edge Transport Each Curve, 30,000 ten-point curves | 6.48 ms | 2.74 ms | 5.09 MB | 60481824834182347 |
| Edge Transport network forward, 30,000 ten-point components | 19.59 ms | 17.92 ms | 26.74 MB | 1325500647425514973 |
| Edge Transport network backward, 30,000 ten-point components | 26.81 ms | 24.46 ms | 36.34 MB | 2252116270756994525 |
| Edge Transport Parent ordered forward, 30,000 ten-point trees | 3.81 ms | 3.82 ms | 2.40 MB | 1380434282527042488 |
| Edge Transport Parent backward, 30,000 ten-point trees | 9.94 ms | 8.82 ms | 12.01 MB | 3066036653996022544 |
| Edge Transport Parent unordered forward, 30,000 ten-point trees | 10.91 ms | 8.27 ms | 14.42 MB | 1601551353367740335 |
| Scatter, uniform exact million count | 472.2 ms | 192.2 ms | 104.1 MB | 3313061772989346825 |
| Scatter, point density + fields + exact provenance | 1155.1 ms | 433.5 ms | 208.1 MB | 701893968125914561 |
| Smooth, primitive/group boundary, 8 edge-weighted `P Cd` passes (160,801 points) | 164.3 ms | 70.3 ms | 21.9 MB | 3723028380804988092 |
| Ray, cold BVH + vector projection (200,901 points / 400,000 triangles) | 496.53 ms | 197.41 ms | 102.58 MB | 2862479342738221337 |
| Ray, cold BVH + provenance, normal, group, and `Cd` import | 526.80 ms | 223.17 ms | 128.37 MB | 3211764991733354948 |
| Ray, eight-sample average + hit normal | 2600.97 ms | 837.61 ms | 169.82 MB | 3683760327621035444 |
| Ray, eight-sample upper median + hit normal | 2679.26 ms | 874.73 ms | 215.37 MB | 1460998520121358970 |
| Ray, eight-sample average + exact provenance and `Cd` import | 5055.80 ms | 1630.29 ms | 327.43 MB | 4210588290262089581 |
| Grid Snap, all 1,002,001 points + moved group | 28.42 ms | 13.40 ms | 52.75 MB | 1871086277788101636 |
| Grid Snap, alternating point group | 19.15 ms | 12.66 ms | 40.83 MB | 784787563699919619 |
| Grid Snap + Fuse, 321,602 duplicate points | 53.96 ms | 45.76 ms | 92.61 MB | 3746365690112069076 |
| Fuse exact, 321,602 duplicate points | 45.79 ms | 40.58 ms | 65.61 MB | 1998394940270991636 |
| Fuse Modify Target + weighted average, 401,802 points | 173.22 ms | 86.19 ms | 123.07 MB | 4054786758075175250 |
| Fuse cleanup, 200,901-point collapsing grid | 75.98 ms | 67.97 ms | 110.82 MB | 2326966657950004879 |
| Fuse fixed-target attribute/group rules, 401,802 points | 131.67 ms | 57.00 ms | 58.10 MB | 4523923909597708345 |
| Fuse Modify Target mixed attribute/group rules, 401,802 points | 207.74 ms | 104.39 ms | 164.36 MB | 2011718227915068739 |
| Bound, 512³ divided box (1.58M points / 3.15M triangles) | 78.44 ms | 60.67 ms | 180.1 MB | 2440516349802212181 |
| Bound, alternating group + 256×128×64 box | 12.01 ms | 11.96 ms | 13.20 MB | 457191895887099019 |
| Bound sphere, 512×256 | 21.83 ms | 17.26 ms | 21.21 MB | 4575451352596622314 |
| Match Size, contain + point `N` (1,002,001 points) | 31.07 ms | 24.28 ms | 48.13 MB | 1230402708513206392 |
| Match Size, alternating move/bounds group + partial stretch | 28.87 ms | 23.40 ms | 48.13 MB | 3662433404310402415 |
| Match Size, total surface-area fit + point `N` | 65.97 ms | 43.46 ms | 73.60 MB | 1474422832630293872 |
| height color | 10.6 ms | 6.6 ms | 32.1 MB | 3176834444355416740 |
| enumerate 1,002,001 points | 5.45 ms | 1.85 ms | 8.04 MB | 1867714337127167676 |
| enumerate alternating point group | 6.40 ms | 2.56 ms | 8.05 MB | 4171775455324172707 |
| enumerate 4,093 integer pieces, local elements | 18.70 ms | 16.50 ms | 16.44 MB | 181743986586326463 |
| enumerate 4,093 integer pieces, piece IDs | 14.86 ms | 12.63 ms | 16.44 MB | 1507297164366801964 |
| enumerate 4,093 text pieces, local elements | 62.33 ms | 59.10 ms | 32.33 MB | 181743986586326463 |
| sort 1,002,001 points by X | 193.8 ms | 171.3 ms | 184.4 MB | 4320638863800733016 |
| merge pair | 77.3 ms | 51.9 ms | 228.4 MB | 3886660968523129958 |
| Copy to Points, 102,400 normal-aligned box copies | 80.39 ms | 47.78 ms | 195.79 MB | 493178525791329886 |
| Copy to Points, 102,400 affine-matrix box copies | 86.84 ms | 52.86 ms | 196.71 MB | 2971098336695328274 |
| Copy to Points, half source/target restriction | 28.27 ms | 19.97 ms | 68.32 MB | 931776985239124703 |
| Copy to Points, three target-attribute rules | 138.56 ms | 100.17 ms | 374.17 MB | 1491781361630052172 |
| Copy to Points, three target attributes + three target groups | 234.98 ms | 119.56 ms | 376.19 MB | 3019261027278696509 |
| Copy to Points, four pieces / 103,041 targets | 171.36 ms | 122.77 ms | 362.37 / 294.97 MB | 4154600044073525722 |
| Copy to Points, 2,048 pieces / 16,384 targets | 15.81 ms | 14.67 ms | 58.08 / 56.37 MB | 4369109338172539638 |
| poly extrude (80k triangles) | 9.5 ms | 5.7 ms | 46.6 MB | 1964062128815843215 |
| Line source (1,002,001 points) | 11.35 ms | 8.85 ms | 32.1 MB | 3766555573609226817 |
| Curve Join, ordered (1,000 × 201-point curves) | 4.89 ms | 4.93 ms | 6.70 MB | 1479753540783563888 |
| Curve Join, shuffled explicit endpoint picks (1,000 × 201-point curves) | 4.88 ms | 4.84 ms | 6.70 MB | 4405899669469262432 |
| Curve Join, globally closest ends (65,537 scrambled curves) | 85.52 ms | 85.17 ms | 25.25 MB | 1380559747436316341 |
| Curve Join, closest 128-sized subgroups + originals | 109.23 ms | 106.87 ms | 69.05 MB | 4452400491292640673 |
| PolyLoft, authored two-point, 1.001M points / 2M triangles | 250.10 ms | 183.58 ms | 194.46 / 159.85 MB | 2140630329163433337 |
| PolyLoft, authored three-point, 1.001M points / 2M triangles | 269.42 ms | 180.27 ms | 194.46 / 159.30 MB | 270081320839283753 |
| PolyLoft, closest-seam three-point, 1.001M points / 2M triangles | 672.41 ms | 323.66 ms | 411.23 / 215.85 MB | 2336594115402408393 |
| Skin, authored seams, 1.001M points / 1M quads | 64.08 ms | 48.61 ms | 121.26 / 98.04 MB | 1185213538368565200 |
| Skin, closest seams, 1.001M points / 1M quads | 471.55 ms | 177.75 ms | 338.03 / 152.86 MB | 4033760677203082832 |
| PolyBridge, one 500k-edge pair / 500k quads | 106.42 ms | 106.76 ms | 133.35 / 133.37 MB | 3425731626861180224 |
| PolyBridge, 1,000 authored 500-edge pairs / 500k quads | 102.17 ms | 91.85 ms | 133.56 / 123.62 MB | 4562963049391598617 |
| PolyBridge, 1,000 centroid-ranked pairs / 500k quads | 115.30 ms | 105.47 ms | 134.15 / 122.48 MB | 4562963049391598617 |
| PolyBridge, one pair / 2 straight rows / 1M quads | 209.89 ms | 195.30 ms | 278.91 / 278.96 MB | 750105119733076194 |
| PolyBridge, 1,000 pairs / 2 straight rows / 1M quads | 202.81 ms | 184.29 ms | 279.44 / 197.47 MB | 2567031205360025512 |
| PolyBridge, divided + point/vertex payload/group | 303.02 ms | 246.65 ms | 499.78 / 415.38 MB | 3377060408763636413 |
| circular sweep (10k rings) | 4.27 ms | 4.23 ms | 24.9 MB | 2407863765480717467 |
| scaled PolyWire (120,400 two-point curves) | 100.6 ms | 83.7 ms | 317.3 MB | 1685661557956714237 |
| capped scaled PolyWire (120,400 curves) | 160.0 ms | 131.0 ms | 522.8 MB | 2892678817770056258 |
| PolyWire long spine (100,001 rings, 12 sides) | 82.41 ms | 75.99 ms | 250.2 MB | 3019630306846948580 |
| controlled PolyWire long spine (scale/seam/V/up/caps) | 146.06 ms | 120.55 ms | 519.2 MB | 2382885542052628994 |
| variable PolyWire divisions/segments/caps | 92.81 ms | 72.57 ms | 290.3 MB | 2058599888829015206 |
| variable PolyWire segment scales + U/V ranges | 96.36 ms | 69.91 ms | 297.1 MB | 3984607635143579421 |
| PolyWire sharp joints, buckling disabled | 101.34 ms | 79.80 ms | 334.5 MB | 4388196339880828253 |
| PolyWire sharp joints, capped radial miters | 107.15 ms | 83.13 ms | 344.1 MB | 2107816651351191467 |
| PolyWire smooth runs (97 breaks) | 102.62 ms | 81.88 ms | 344.4 MB | 3740266745668275405 |
| variable PolyWire per-edge segment seams | 103.62 ms | 78.53 ms | 306.7 MB | 2516701176577015567 |
| general-profile Sweep (20,001 × 32, alternating triangles) | 94.99 ms | 56.21 ms | 262.6 MB | 3981213447694709042 |
| general-profile Sweep payload/caps/native edges | 354.42 ms | 308.40 ms | 775.7 MB | 3281918545425613217 |
| Resample long spine (200,001 → 1,000,001 points) | 36.70 ms | 24.23 ms | 73.61 MB | 2971143590344181036 |
| length Resample + U/curve/distance/tangent | 63.97 ms | 46.25 ms | 130.55 MB | 1048065382090500334 |
| PolyFrame Two Edges (361,201 points) | 48.07 ms | 31.66 ms | 51.99 MB | 3123100058409629911 |
| PolyFrame Texture UV point frame | 110.74 ms | 59.60 ms | 106.01 MB | 878999954786908287 |
| PolyFrame Attribute Gradient vertex frame | 177.80 ms | 89.79 ms | 226.90 MB | 2738302846155992846 |
| Facet Unique Points (200,901 → 1,200,000 points) | 52.04 ms | 34.35 ms | 99.77 MB | 52116703184864747 |
| Facet pre normals + Unique Points + reverse | 73.12 ms | 52.96 ms | 143.01 MB | 216472004485794575 |
| Facet grouped Unique Points (alternating 200,000 faces) | 47.40 ms | 30.64 ms | 76.69 MB | 862782961673215783 |
| Facet grouped pre normals + Unique Points + reverse | 64.42 ms | 49.82 ms | 112.34 MB | 4403351474312899621 |
| Facet Orient Polygons (400,000 triangles) | 31.65 ms | 27.68 ms | 26.45 MB | 2365675254808124655 |
| Facet Cusp Polygons (1,200,000 corners) | 70.57 ms | 52.02 ms | 84.51 MB | 283124930776590793 |
| Facet Remove Inline Points (1,200,000 corners) | 74.78 ms | 46.17 ms | 91.72 MB | 293960505550144756 |
| Facet grouped Remove Inline Points (alternating 200,000 polygons) | 67.97 ms | 42.69 ms | 102.95 MB | 4428373719769560180 |
| Facet Make Planar (800,000 points) | 43.07 ms | 29.22 ms | 53.23 MB | 3434920207817674627 |
| Facet grouped Make Planar (alternating 100,000 quads) | 31.72 ms | 23.41 ms | 53.25 MB | 348575385667556423 |
| Facet point-selection promotion + Unique Points | 42.56 ms | 28.10 ms | 69.61 MB | 214444916378444802 |
| Facet vertex-selection promotion + Unique Points | 40.98 ms | 27.65 ms | 69.51 MB | 4122771134891582778 |
| Facet edge-selection promotion + Unique Points | 42.96 ms | 28.55 ms | 70.55 MB | 3776704403672471336 |
| Facet Consolidate point `N` (1,200,000 points) | 462.92 ms | 457.56 ms | 139.23 MB | 885417337606853454 |
| Poly Fill Single Polygon, 100,000 holes (800,000 points) | 215.38 ms | 194.25 ms | 190.24 MB | 2051343833192007422 |
| Poly Fill Triangles, 100,000 holes | 244.55 ms | 213.06 ms | 219.20 MB | 1491809127108389124 |
| Poly Fill unique Triangle Fan, 100,000 holes | 359.86 ms | 290.62 ms | 346.87 MB | 1323544786701702380 |
| Convert Line (3,002,000 unique edges + length) | 627.4 ms | 298.8 ms | 215.5 MB | 1159685896482037800 |
| Convert Line fused Connect Path (3,002,000 edges) | 313.36 ms | 302.33 ms | 338.50 MB | 402758761000324084 |
| PolyPath (3,002,000 unique edges, full ancestry) | 217.67 ms | 183.94 ms | 289.25 MB | 4605327786602156546 |
| PolyPath + exact endpoint connection, no welds | 319.83 ms | 289.57 ms | 362.14 MB | 4605327786602156546 |
| integer mode, 1,002,001 points → detail | 12.14 ms | 12.21 ms | 8.02 MB | 1214810429822179047 |
| integer upper median, 1,002,001 points → detail | 28.26 ms | 28.49 ms | 8.02 MB | 1214810429822179029 |
| integer mode in 64-point pieces | 142.3 ms | 52.62 ms | 33.0 MB | 3372359779053422621 |
| unchanged triangle triangulate | 3.5 ms | 3.5 ms | 480 B | 3253461948889680712 |
| cached procedural cook | 0.019 ms | 0.018 ms | 5.2 KB | 3176834444355416740 |

The Scatter rows use `RAYS_RDK_OPS_FILTER=scatter` and
`RAYS_RDK_SCATTER_COUNT=1000000`. After its output contract and indexed
random stream were fixed, the one-domain uniform baseline took 641.5 ms and
allocated 264.2 MB. Replacing returned float tuples/boxed hot-loop values with
range-local unboxed scratch reduced that to 472.2 ms and 104.0 MB, which is the
exact six float output planes, integer `id`, and three triangle alias arrays
plus bounded range metadata. The density/provenance baseline took 1508.3 ms
and 256.0 MB. Avoiding Attribute Interpolate's 6,000,000-entry
vertex-to-primitive reverse map when no primitive field/group is requested
reduced it to 1155.1 ms and 208.0 MB. Final one/four-domain hashes are exact;
promoted allocation is zero in all four final runs.

The Smooth row uses `RAYS_RDK_OPS_FILTER=smooth`. Its input contains 160,801
points and 320,000 triangles, a sparse locked-point group, a patterned
primitive restriction, and group-boundary constraints. The four-domain result
is 2.34x faster with the same exact geometry hash; promoted allocation is zero.
The 21.9 MB allocation is bounded topology-selection metadata plus the two
packed `P`/`Cd` plane sets reused across all eight iterations, rather than
iteration-proportional retained storage.

The Ray rows use `RAYS_RDK_OPS_FILTER=ray` and three release-profile
medians. Each cold cook builds the collision BVH, projects 200,901 source
points against 400,000 triangles, and then materializes requested output. Four
domains are 2.52x faster for one ray, 3.11x faster for eight-ray average, and
3.10x faster when the average path repeats chosen hits to produce exact
provenance and `Cd` import. Geometry hashes are byte-exact across domain
counts. Replacing one recursive traversal closure per ray with fixed worker
stacks reduced final one/four-domain single-ray allocation to 141.879/102.575
MB from 207.768/116.170 MB with the established hash unchanged. Eight-ray
average and its provenance/import path allocate 381.365/169.824 MB and
725.351/327.431 MB; the larger numbers include repeated traversal boxing and
the latter's required 48-slot-per-point average CSR payload rather than a
retained temporary hit matrix. One-repeat processes peak at 147,116/153,796
KiB RSS for position/normal output and 225,660/232,948 KiB with provenance,
including fixture construction, Dune, hashing, and the OCaml heap.

The Grid Snap/Fuse rows use `RAYS_RDK_OPS_FILTER=snap_to_grid` and
`RAYS_RDK_OPS_FILTER=fuse`, with three release-profile medians. Snap-only
position ranges scale 2.12x on the million-point all-selection fixture and
1.51x on its alternating-group fixture. Replacing an eight-byte-per-point
boolean change plane plus a second membership scan with a byte-owned packed
bitset improved the all-selection cook from 33.22/18.51 ms to 28.42/13.40 ms
at one/four domains and removed about 8 MB from its one-domain allocation and
major-live measurements. Exact hashes did not change. Fuse cluster discovery
retains stable earliest-source semantics and is deliberately sequential; its
payload/topology remaps parallelize, so the duplicate fixture gains only
1.13x-1.18x without exposing schedule-dependent cluster IDs. Extracting cluster
discovery into one reusable RDK core also lets its cell, representative, size,
and cursor planes share storage across phases. Exact Fuse fell from the prior
71.60/64.97 ms and 104.2 MB to 45.79/40.58 ms and at most 65.61 MB without
changing its hash.

The Modify Target row uses disjoint halves of two offset 500x400 grids,
closest-target links, pairwise weighted-average reduction, exact post-link
fusion, and full topology/payload hashing. It scales 2.01x with identical
one/four-domain cardinality and hash; one/four-domain allocations are
144.79/123.07 MB. The cleanup row fuses horizontal grid neighbors, removes
sequential duplicate corners and sub-cardinality faces, compacts all unused
points, and retains exact ancestry; it scales 1.12x because stable spatial
cluster discovery and prefix planning remain sequential. Its allocations are
110.76/110.82 MB. Three-repeat process peak RSS was 278,144/203,520 KiB for
Modify Target and 195,328/200,320 KiB for cleanup, including fixture setup,
Dune, hashing, and the OCaml heap. These two new rows use Dune's dev profile on
OCaml 5.3.0, Dune 3.24.0, Linux 6.8 aarch64, and four physical cores. Reproduce with
`RAYS_RDK_OPS_FILTER=fuse_modify_target_weighted_pair` or
`RAYS_RDK_OPS_FILTER=fuse_cleanup_grid_pairs`, plus
`RAYS_RDK_OPS_REPEATS=3 RAYS_BENCH_DOMAINS=1 dune exec
tools/bench_rdk_ops.exe`, then repeat with four domains.

The fixed-target rule row copies one float field, converts one integer scalar
to a one-element CSR row, and propagates a target-only point group through the
already selected closest-target map. It takes 131.672/56.996 ms (2.31x),
allocates 81.407/58.096 MB, promotes at most 8,776 bytes, and has exact
one/four-domain hash `4523923909597708345`. The Modify Target rule row reduces
weighted float, integer mode, weight-ordered text concatenation, and strict
majority group membership across pair components. It takes 207.744/104.389 ms
(1.99x), allocates 212.329/164.361 MB, and has exact hash
`2011718227915068739`; 2.70/1.82 MB promotion is retained two-character string
output rather than per-candidate garbage. Process peak RSS was
195,712/203,648 KiB and 203,648/200,576 KiB respectively. Reproduce with
`RAYS_RDK_OPS_FILTER=fuse_target_attribute_rules` or
`RAYS_RDK_OPS_FILTER=fuse_modify_target_attribute_rules` and the same
three-repeat one/four-domain command above.

The Bound rows use `RAYS_RDK_OPS_FILTER=bound` and three release-profile
medians over 1,002,001 source points. Dense divided-box output scales 1.29x and
the 512×256 sphere scales 1.27x with byte-exact geometry hashes; the cheap
alternating-group fixture intentionally stays sequential and equal-speed after
measurement showed domain scheduling cost more than its 12 ms work. Replacing
UV Sphere's builder plus boxed point retrieval in every triangle with exact SoA
planes reduced sphere allocation from 90.13 MB to 21.19 MB and median time from
32.14 ms to 21.83 ms on one domain, with zero promoted bytes and the same hash.

The Match Size rows use `RAYS_RDK_OPS_FILTER=match_size` and five
release-profile medians. Their fixture has 1,002,001 points, 6,000,000 corners,
2,000,000 triangles, and a point-normal plane. The 48.13 MB allocation is the
required immutable position and normal output plus range metadata; it does not
grow with fit mode or iteration. Contain scales 1.28x, selected stretch 1.23x,
and area fit 1.52x at four domains. Area adds deterministic primitive-measure
planes/scratch and reports 73.60 MB at four domains. All three hashes are exact
across domain counts, and a one-repeat four-domain process containing source,
all three cooks, and the benchmark harness peaked at 222,592 KiB RSS.

The 2026-08-02 packed-array Attribute Promote tranche used three process
medians on a 160,801-point/320,000-triangle grid. Four scalar float fields were
promoted together from points to primitive CSR rows; the result contains
960,000 values per field. Allocated bytes include every required output row,
and Unique Values additionally owns one incidence scratch plane per field.

| Four-field array promotion | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| Array of All | 30.844 ms | 23.281 ms | 102.415 MB | 3195221879676730096 |
| sorted Unique Values | 74.793 ms | 57.144 ms | 266.255 MB | 1267023885901908324 |

Both hashes are identical across domain counts. Array of All is O(incidences)
time and exact output storage. Unique Values is O(incidences × log(max row))
time with O(incidences + destinations) scratch/output offsets; independent
rows sort and fill in disjoint domain ranges. A separate 40,000-element
same-owner piece regression materializes 1.6 million integer values and
compares every CSR offset/value exactly between one and four domains.
Using typed zero-initialized incidence planes instead of a polymorphic
per-slot initializer reduced Array of All allocation by 37.5% and its
one-domain median by 24.2%; Unique Values allocation fell by 18.7%, with the
same hashes.

```sh
RAYS_RDK_OPS_FILTER=attribute_promote_pattern4_array_all \
  RAYS_RDK_OPS_REPEATS=3 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with domains=4 and filter attribute_promote_pattern4_unique_values.
```

The 2026-08-03 Attribute Promote compatibility tranche retained the same grid
and grain 2,048. Aligned multi-term rename rules are preflighted once; float
tuple extrema preserve one contributing source index per component in a
fixed-width integer CSR row; text/index Average is upper median, Sum is stable
incidence-order concatenation, and other numeric modes fall back to First.

| Promotion path | 1 domain | 4 domains | Allocation (1d / 4d) | Exact hash |
|---|---:|---:|---:|---:|
| four scalar values + indices | 57.254 ms | 48.055 ms | 62.474 / 49.269 MB | 1588512353231422235 |
| float4 + component indices | 63.397 ms | 53.747 ms | 75.251 / 62.118 MB | 1105309542113901142 |
| text Sum | 18.448 ms | 7.823 ms | 7.682 / 4.196 MB | 150614732931925070 |

All are five-run release medians and hashes agree exactly across domain
counts. Tuple component indexing is O(incidences × width) time and exact
O(destinations × width) required output at width at most four. Text Sum uses a
checked byte-count pass and one exact output string per destination, for
O(total contributing bytes + incidences) time and O(destinations) scratch.
Single-repeat process peaks were 101,376/107,008 KiB RSS for tuple indexing and
55,168/57,728 KiB for text Sum on one/four domains, including fixtures and the
benchmark harness.

```sh
RAYS_RDK_OPS_FILTER=attribute_promote_pattern_tuple4_indexed_shared \
  RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_promote_pattern_text_sum \
  RAYS_RDK_OPS_REPEATS=5 RAYS_RDK_BENCH_GRAIN=2048 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
```

The 2026-08-02 Unpack tranche was measured separately in the release profile
on the same Linux 6.8 aarch64 four-core environment, OCaml 5.3.0 and Dune
3.24.0, with twenty-one medians. The fixture materializes 4,096 arbitrarily
translated, rotated, and non-uniformly scaled hard-normal boxes carrying a
native edge group: 24 source points and 294,912 output point/vertex/primitive
elements. The legacy baseline transforms every copy and then performs a
general Merge; both transformed paths have the exact hash
`1215420005789118105`.

| Unpack path | 1 domain | 4 domains | Allocated (4d) | Promoted (4d) | Major (4d) |
|---|---:|---:|---:|---:|---:|
| transform-each + Merge baseline | 29.485 ms | 30.513 ms | 68.00 MB | 6.12 MB | 37.68 MB |
| cardinality-first packed Unpack | 6.203 ms | 5.607 ms | 16.90 MB | 2.40 MB | 8.71 MB |
| packed Unpack, transforms disabled | 1.750 ms | 1.301 ms | 6.41 MB | 0 B | 6.37 MB |

The applied-transform kernel is 5.44x faster than the four-domain composition
and reduces allocated bytes by 75.1% without changing output. A three-repeat
four-domain process containing these rows and the dense single-instance rows
peaked at 61,336 KiB RSS.
The single-instance fast path structurally shares topology, groups, native edge
groups, and unchanged attributes. On a 251,001-point/500,000-triangle grid it
produced the same `1082183089858954941` hash as the ordinary transform while
taking 5.307/1.790 ms on one/four domains versus 5.722/2.071 ms, with 12.06 MB
allocated in both paths.
Reproduce it with:

```sh
RAYS_RDK_OPS_FILTER=unpack RAYS_RDK_OPS_REPEATS=21 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

Additional release-profile baseline. Most rows use a
40,401-point/80,000-triangle grid and five medians; the refreshed 2026-08-03
Clip rows use a genuine 1,002,001-point/two-million-triangle grid and three
medians, while the filled sphere row uses its listed 6,050 points:

| Operation | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| packed topology index | 11.1 ms | 11.0 ms | 36.2 MB | 1337935550237066879 |
| point→primitive float3 promote | 4.28 ms | 1.89 ms | 5.8 MB | 3859760677753242117 |
| mirror | 18.3 ms | 17.8 ms | 14.9 MB | 2688318757016851213 |
| exact fuse of duplicated pair | 12.6 ms | 11.6 ms | 27.7 MB | 555257625938432688 |
| packed spatial index | 9.20 ms | 9.20 ms | 0.32 MB | 3559781733544285073 |
| inverse-distance attribute transfer (k=4) | 98.0 ms | 51.1 ms | 4.20 MB | 2242929486872171700 |
| packed triangle surface index | 55.1 ms | 55.5 ms | 164.1 MB | 3473727463466223475 |
| closest-surface attribute transfer | 89.2 ms | 70.7 ms | 174.1 MB | 1224910455216365276 |
| duplicate attributed grid, 8 added copies | 134.93 ms | 24.85 ms | 41.26 MB | 2456038152415910946 |
| duplicate alternating primitives + 8 output groups | 42.44 ms | 29.03 ms | 51.61 MB | 2341744684409956267 |
| sort 80,000 primitives by center X | 10.9 ms | 9.95 ms | 8.75 MB | 1612032759116215344 |
| delete half + compact orphan points | 3.21 ms | 3.22 ms | 6.98 MB | 3918085630900232532 |
| delete half, retain/share point payload | 3.32 ms | 3.35 ms | 3.89 MB | 2417081874446603328 |
| delete left points + destroy touched + compact | 3.88 ms | 3.60 ms | 6.98 MB | 282286150904996980 |
| heal sparse quad corners + attributes | 35.7 ms | 27.8 ms | 73.2 MB | 2052081519948109075 |
| bounding box | 0.126 ms | 0.133 ms | 12.5 KB | 3938091890134867962 |
| match size (contain) | 0.755 ms | 0.552 ms | 1.95 MB | 1220539449090061276 |
| clip half million-point grid | 240.945 ms | 174.607 ms | 532.942 MB | 1457682456804818398 |
| clip half grid + point/vertex/primitive attributes | 266.471 ms | 196.192 ms | 632.868 MB | 503833327352904549 |
| clip custom float4 coordinates + distance + clipped edges | 541.924 ms | 420.652 ms | 1119.801 MB | 3228595801765344543 |
| clip 6,050-point sphere, both sides + split + fill | 3.545 ms | 3.534 ms | 14.005 MB | 2678645509349667123 |
| Loop subdivision + attributes | 67.794 ms | 45.713 ms | 109.878 MB | 858477177421416506 |
| Catmull-Clark subdivision + attributes | 101.949 ms | 64.640 ms | 176.628 MB | 376865061323882225 |
| Catmull-Clark + dense semi-sharp creases | 111.181 ms | 86.596 ms | 245.165 MB | 2240368469655108917 |
| Catmull-Clark + dense second-input crease attributes | 141.076 ms | 96.156 ms | 256.813 MB | 2240368469655108917 |
| Catmull-Clark + dense second-input creases/result group | 149.133 ms | 99.783 ms | 262.722 MB | 512181311574988744 |
| Catmull-Clark + sparse 200-edge second-input override | 96.761 ms | 71.249 ms | 214.329 MB | 2384261217015432874 |
| Catmull-Clark + sparse subdivision holes | 110.696 ms | 69.177 ms | 177.146 MB | 316117588020776784 |
| Catmull-Clark + 50% subdivision holes | 89.885 ms | 55.928 ms | 146.923 MB | 2308137223929356764 |
| Catmull-Clark + 50% retained hole faces | 103.292 ms | 65.256 ms | 176.658 MB | 2631021000821162415 |
| bilinear subdivision | 36.949 ms | 28.280 ms | 87.415 MB | 683821733545155753 |
| bilinear local contiguous half | 45.092 ms | 42.126 ms | 90.294 MB | 2012308210456171798 |
| bilinear local alternating faces | 78.368 ms | 69.726 ms | 180.648 MB | 518621518380473251 |
| Catmull-Clark local contiguous half | 60.233 ms | 37.981 ms | 122.303 MB | 1738102442901827305 |
| Catmull-Clark local Pull/No Edge Division | 71.236 ms | 44.817 ms | 136.993 MB | 629813708611520190 |
| Catmull-Clark local Stitch/No Edge Division | 79.003 ms | 71.801 ms | 155.226 MB | 3137573248193083737 |
| Catmull-Clark local Pull/Divide Edges (bias 0.75) | 95.597 ms | 85.064 ms | 187.733 MB | 3697698291297517219 |
| Catmull-Clark local Stitch/Divide Edges | 92.528 ms | 84.267 ms | 187.743 MB | 4580811677866533301 |
| Catmull-Clark local Pull/Triangulate (bias 0.75) | 105.583 ms | 99.790 ms | 212.563 MB | 1771144634972156419 |
| Catmull-Clark local Stitch/Triangulate | 110.261 ms | 94.770 ms | 211.425 MB | 3868299086784368101 |
| Catmull-Clark local Stitch/Divide, consistent | 80.425 ms | 76.341 ms | 160.110 MB | 2807886286253650657 |
| Catmull-Clark local Stitch/Triangulate, consistent | 91.859 ms | 84.722 ms | 183.091 MB | 249501161833618177 |
| Catmull-Clark local Pull/Triangulate, consistent | 107.589 ms | 98.021 ms | 211.353 MB | 1351686240886644603 |

The 2026-08-02 Attribute Transfer rework was measured again with the same
release profile, machine, five medians, 40,401-point/80,000-triangle source,
and stable exact hashes. Vertex destinations contain 240,000 corners. The quad
index fixture contains 240,000 quads and emits 480,000 internal triangles.

| Transfer/index operation | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| inverse-distance point transfer (k=4) | 38.721 ms | 18.063 ms | 4.209 MB | 2242929486872171700 |
| Hart-kernel point transfer (k=4) | 37.953 ms | 19.466 ms | 4.209 MB | 2242929486872171700 |
| inverse-distance primitive-barycenter transfer (k=4) | 132.270 ms | 55.041 ms | 10.885 MB | 1679080687938051146 |
| triangle-source surface index | 39.081 ms | 18.383 ms | 21.184 MB | 3473727463466223475 |
| quad-source surface index | 262.804 ms | 112.873 ms | 154.497 MB | 1266878950770378852 |
| mixed surface transfer → points | 74.416 ms | 35.478 ms | 31.209 MB | 1224910455216365276 |
| vertex-only surface transfer → vertices | 195.056 ms | 71.208 ms | 69.189 MB | 2960979989216765941 |
| mixed surface transfer → vertices | 210.519 ms | 77.521 ms | 80.711 MB | 3018446810536414038 |
| mixed surface transfer → primitive barycenters | 104.278 ms | 46.787 ms | 42.950 MB | 2391410054704090816 |

The partial source-vertex follow-up used three process medians on the same
40,401-point/80,000-triangle release fixture. Selecting the first half of its
packed corners with the default all-corners rule retained 40,000 triangles.

| Vertex-restricted operation | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| surface index construction | 20.070 ms | 13.823 ms | 12.633 MB | 3187255119519784648 |
| mixed surface transfer → points | 39.459 ms | 29.834 ms | 22.660 MB | 4528112470654217908 |

Both hashes are identical across domain counts. The selection pass reads the
packed vertex bitset directly, writes one byte per candidate triangle plus one
count per stable range, prefix-sums ranges sequentially, and fills exact-size
triangle planes into disjoint slices. Its auxiliary storage is O(candidate
triangles + ranges), construction retains the existing O(t log t) BVH bound,
and transfer queries retain expected O(q log t) time with O(q) output storage.

Reproduce the isolated transfer rows without constructing unrelated fixtures:

```sh
RAYS_RDK_OPS_FILTER=attribute_transfer_inverse4 \
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with domains=4 and with filters attribute_transfer_kernel4_hart,
# attribute_transfer_primitives,
# attribute_transfer_vertices, attribute_transfer_surface,
# attribute_transfer_surface_vertex_restricted, surface_index, or
# surface_index_vertex_restricted.
```

The filtered harness reports the actual 40,401-point input in its CSV. A
one-repeat Hart-kernel process peaked at 74,840/56,748 KiB RSS on one/four
domains; the one-domain invocation also rebuilt the release executable, while
the four-domain invocation reused it. A
three-repeat four-domain vertex-transfer run under `/usr/bin/time -v` peaked at
57,656 KiB RSS; the isolated process retained no unrelated million-point
benchmark fixtures.

The 2026-08-02 blend/multi-owner follow-up used the same release-profile
40,401-point fixture and seven process medians:

| Transfer operation | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| inverse-distance k=4, zero blend | 40.883 ms | 18.553 ms | 4.208 MB | 2242929486872171700 |
| inverse-distance k=4, smooth blend | 65.578 ms | 29.885 ms | 5.826 MB | 3699952128852573101 |
| four owner-specific calls | 350.280 ms | 138.934 ms | 79.806 MB | 3363025554004648849 |
| one `transfer_all` call | 350.430 ms | 140.190 ms | 79.806 MB | 3363025554004648849 |

The pre-change zero-blend medians were 40.556 ms/19.067 ms and 4.206 MB,
so the shared distance-window and batch-commit path changed one-domain time by
+0.8%, four-domain time by -2.7%, and added only 1,912 fixed bytes while
preserving the exact hash. Blended transfer scales 2.19x from one to four
domains. The multi-owner wrapper is within 1% of the identical explicit
sequence and adds only 480 bytes while replacing four graph-level nodes with
one. A separate
4,096-detail-attribute fixture compares the former repeated immutable install
with the batch commit: 61.910 ms/67.879 MB versus 0.566 ms/1.476 MB, a 109x
wall-time improvement and 97.8% allocation reduction with hash
2630023133807264573. The four-domain multi-owner process peaked at 69,504 KiB
RSS under `/usr/bin/time -v`.

```sh
RAYS_RDK_OPS_FILTER=attribute_transfer_inverse4_blend \
  RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_transfer_all \
  RAYS_BENCH_DOMAINS=4 dune exec --profile release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=attribute_transfer_detail \
  RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
```

The same date's million-point Attribute Copy fixture copied four point fields
(float, int, float2, and float3) with exact hashes. Materializing those planes
took 12.302 ms and allocated 56.003 MB. The identity planner instead shared
their immutable storage in 0.017 ms with 7.0 KB allocated. A genuine
quarter-source cyclic copy took 18.626 ms on one domain and 11.427 ms on four
domains, with exact output hashes. The one-domain filtered process peaked at
166,320 KiB RSS including both million-point fixtures and all source payloads.

```sh
RAYS_RDK_OPS_FILTER=attribute_copy RAYS_RDK_OPS_REPEATS=3 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

The million-point Attribute Combine fixture layers four float4 fields and masks
with the same exact output hash for fused/sequential and one/four-domain runs.

| Combine operation | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| four sequential one-layer commits | 235.223 ms | 111.971 ms | 128.022 MB | 1955258015676273827 |
| one fused four-layer traversal | 171.595 ms | 62.474 ms | 32.008 MB | 1955258015676273827 |
| integer-key matched second input | 59.079 ms | 36.377 ms | 32.784 MB | 3241778002848886381 |

Fusion removes three destination materializations, cuts allocation by 75%, and
scales 2.75x from one to four domains. The matched case includes one exact-size
output, destination map, and bounded-load packed open-address table; replacing
the first boxed hash table reduced measured allocation from 72.395 MB to
32.784 MB. The full filtered one-domain process, including all million-point
source fixtures, peaked at 291,460 KiB RSS.

```sh
RAYS_RDK_OPS_FILTER=attribute_combine RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

The million-destination Attribute Interpolate fixture samples canonical `P`
plus float, int, text, float2, float3, and float4 point fields from one quad.
Seven independent cooks and the fused primitive cook produce exact hash
4556032010648822215 on one and four domains. A second exact hash,
1746913426898666179, covers computed point-number/weight CSR rows and a second
cook driven exclusively by those rows.

| Interpolate operation | 1 domain | 4 domains | Allocated (1d) |
|---|---:|---:|---:|
| seven sequential field cooks | 321.172 ms | 126.213 ms | 120.039 MB |
| one fused primitive traversal | 192.449 ms | 75.214 ms | 120.013 MB |
| fused primitive plus computed CSR rows | 241.901 ms | 111.053 ms | 208.015 MB |
| explicit point-number/weight traversal | 255.502 ms | 105.453 ms | 120.014 MB |
| weighted traversal plus one matched point group | 279.323 ms | 110.786 ms | 120.142 MB |

Fusion avoids six repeated driver/topology/weight traversals and metadata
commits while retaining only the exact final payload storage. The computed
case necessarily allocates two CSR offsets planes and four-number/four-weight
rows in addition to field output. The weighted field cook itself allocates only
the exact 120 MB field payload. Removing destination-local iterator closures
reduced its measured allocation from 560.014 MB to 120.014 MB and wall time
from 326.904 ms to 255.502 ms on one domain. The weighted path scales 2.42x at
four domains and preserves the exact computed-mode hash.
One matched group adds only its exact 125,000-byte membership bitset plus
metadata. The group-inclusive hash is 3149981480280984341 on both domain
counts; byte-owned parallel output reduces its incremental one-domain cost of
24.508 ms to 3.067 ms at four domains.

```sh
RAYS_RDK_OPS_FILTER=attribute_interpolate RAYS_RDK_OPS_REPEATS=3 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile release tools/bench_rdk_ops.exe
# Repeat with RAYS_BENCH_DOMAINS=4.
```

The closest-surface baseline uses the same 80,000-triangle grid, transfers
point `Cd`, vertex `uv`, primitive `density`, and a distance plane to 40,401
offset target points through all-element source/target groups and a smoothstep
blend band. Relative to the first correct tuple-heavy implementation,
packed bounds, exact balanced-node allocation, reusable polygon-triangulation
scratch, range-local query scratch, and non-escaping sequential recursion
reduced surface-index construction from 295.7 ms/620.4 MB to 39.081 ms/21.184
MB and complete point transfer from 348.1 ms/733.3 MB to 74.416 ms/31.209 MB
on one domain. Four domains retain the exact geometry hashes and reduce those
operations to 18.383 ms and 35.478 ms. Global active-axis selection in the
point index reduced the planar k=4 point-transfer baseline from 98.0/51.1 ms;
the current in-place coefficient path takes 38.721/18.063 ms on one/four
domains, and the Hart kernel takes 37.953/19.466 ms. These are five-median
measurements from the same release build; they establish measured production
baselines, not timing thresholds.

_Continues "Clip accepts canonical `P` or scalar/int/float2/float3/float4 point coordinates…" in rdk.md:_
This reduced the million-point attributed case from 321.898/285.011 ms to
266.471/196.192 ms on one/four domains and from 859.148/859.384 MB to
632.868/556.435 MB, with unchanged hashes. Curves, filled caps, and degenerate
repeated-corner polygons use the general builder. Cap tracing is sequential;
output and auxiliary storage are linear except for the explicit pairwise
containment check among cap loops.

_Continues "Subdivision topology indexing, manifold/fan validation, exact stencil-plan construction…" in rdk.md:_
The measured attribute-heavy Catmull-Clark fixture improves 1.32× at four
domains and the dense semi-sharp fixture 1.39×; hashes include topology,
attributes, groups, and ordering and are exact across domain counts. One level
is O(points + edges + vertices + payload) time/storage. Iterated output grows
by the scheme's documented child cardinality and each completed level becomes
unreachable before the next once no caller retains it. Local refinement adds
linear selected/unselected extraction, fan splitting, and stable concatenation.
On the 40,401-point/80,000-triangle fixture, a contiguous half selection is
45.092/42.126 ms and a boundary-heavy alternating selection is 78.368/69.726
ms at one/four domains. Their exact hashes match; stable topology partitioning
and fan planning limit scaling despite parallel payload fills.
On the same contiguous selection, Catmull-Clark Do Not Close is 60.233/37.981
ms, Pull Closed/No Edge Division is 71.236/44.817 ms, and Stitch/No Edge
Division is 79.003/71.801 ms. Exact hashes match across domain counts. Pull
adds 14.690 MB and 11.003 ms to the one-domain median without constructing a
second refined topology index; Stitch adds exact bridge topology and payload
remapping for 32.923 MB and 18.770 ms above Do Not Close. Folding bridge
cardinality and ancestry into the initial combine eliminated a second geometry
materialization, cutting Stitch from 84.637 ms/167.561 MB to
79.003 ms/155.226 MB with the same hash. Pull/Divide Edges measures
95.597/85.064 ms and 187.733 MB at one domain; Stitch/Divide Edges measures
92.528/84.267 ms and 187.743 MB. Both divided paths build the coarse chain
directly from source ancestry and fold explicit point welding into final
packed assembly; their one/four-domain hashes are exact. Pull/Triangulate is
105.583/99.790 ms and Stitch/Triangulate is 110.261/94.770 ms, with
212.563/211.425 MB allocated on one domain and exact hashes
`1771144634972156419`/`3868299086784368101` across domain counts.
Consistent Stitch/Divide is 80.425/76.341 ms with 160.110 MB allocated on one
domain; consistent Stitch/Triangulate is 91.859/84.722 ms with 183.091 MB.
Their exact hashes, `2807886286253650657` and `249501161833618177`, match
across domain counts. Avoiding coincidence maps and geometric ear decisions
makes the stronger stability contract cheaper on this fixture despite
retaining every topology-prescribed bridge face. Consistent Pull/Triangulate
is 107.589/98.021 ms with 211.353 MB allocated on one domain and exact hash
`1351686240886644603`.

_Continues "Deletion planning is stable and sequential; position/attribute/group payload…" in rdk.md:_
Attribute-heavy quad healing improves
1.28× at four domains. Removing a per-primitive tuple from the measured
planning loop cut that fixture from 45.0 ms/119.4 MB to 35.7 ms/73.2 MB on one
domain and from 32.8 ms/79.1 MB to 27.8 ms/49.7 MB on four domains. Primitive
deletion without compaction shares unchanged point payloads and allocates only
3.89 MB for the retained topology/owner maps.

The merge topology fill was the measured bottleneck: the same local benchmark
fell from 0.903 s to 0.049 s at four domains after switching only its disjoint
index/offset adjustment to packed parallel ranges. Output hashes remained
identical. A three-repeat first-cook run peaked at 181,892 KiB RSS.
The extrusion fixture initially allocated 88.1 MB and took 19.8 ms at four
domains; direct cardinality-indexed writes and disjoint primitive ranges cut
that to 46.6 MB and 5.7 ms with the same output hash.

The Box-specific benchmark command is:

```sh
RAYS_RDK_OPS_FILTER=box_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=box_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile=release tools/bench_rdk_ops.exe
```

On OCaml 5.3.0/Dune 3.24.0, Linux 6.8 aarch64, four Apple CPU cores, and grain
16,384, five-run release medians were 28.469/19.493 ms for 523,606 face-local
points and 1,040,000 triangles; 9.142/4.242 ms for 520,002 welded surface
points with smooth point normals; 50.498/32.698 ms for the same welded points
and 520,000 quads with hard vertex normals/UV/groups; and 8.939/3.592 ms for a
1,030,301-point volume lattice. Exact hashes respectively remain
`3248985372702655547`, `1256429452418273907`, `825093362255214193`, and
`960043793403492254` across domain counts. Reported one-domain allocations are
59.484, 24.989, 117.422, and 24.741 MB, within bounded control data of their
required packed output. The first correct generic triangle, quad, and lattice
loops allocated 284.592, 379.480, and 156.123 MB by boxing coordinate tuples
and per-cell closures. The compatible 10,000-box batch retains hash
`2906169571501514570`, improves from 6.660/12.170 ms to 4.770/7.102 ms, and
reduces allocation from 67.840 MB to 34.480 MB; it deliberately remains
sequential because each 24-point box is below parallel dispatch grain. The
isolated final four-domain filtered process peaked at 126,188 KiB RSS,
including all five fixtures, hashing, Dune, and the OCaml heap.

The UV Sphere benchmark command is:

```sh
RAYS_RDK_OPS_FILTER=uv_sphere_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=uv_sphere_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile=release tools/bench_rdk_ops.exe
```

On OCaml 5.3.0/Dune 3.24.0, Linux 6.8 aarch64, four Apple CPU cores, and grain
16,384, five-run release medians and one-domain allocations were:

| UV Sphere fixture | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| 1,000,002-point compatible triangles | 66.733 ms | 40.679 ms | 114.044 MB | 1383169697053155230 |
| 502,000-point alternating transformed ellipsoid, vertex N/UV | 86.883 ms | 55.808 ms | 165.079 MB | 2492680085440154034 |
| 500,002-point logical-pole quads, point N/UV | 35.423 ms | 21.739 ms | 76.633 MB | 2746056298211748017 |
| 1,000,002-point rows and columns, vertex N/UV | 52.622 ms | 31.680 ms | 120.259 MB | 561415338382752283 |
| 1,004,000 unique points with point N/UV | 27.875 ms | 16.235 ms | 64.300 MB | 3189576027514060009 |

Every allocation is the published packed payload plus bounded tables/range
state. Before the compatible-path rewrite, the first fixture took
87.170/47.487 ms, allocated 114.002 MB, and had the same exact hash. The final
five-fixture four-domain process peaked at 173,640 KiB RSS including Dune,
hashing, and the OCaml heap.

The Torus benchmark commands are:

```sh
RAYS_RDK_OPS_FILTER=torus_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=torus_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile=release tools/bench_rdk_ops.exe
```

On OCaml 5.3.0/Dune 3.24.0, Linux 6.8 aarch64, four Apple CPU cores, and grain
16,384, five-run release medians and one-domain allocations were:

| Torus fixture | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| 1,000,000-point compatible triangles | 57.928 ms | 38.153 ms | 114.085 MB | 3747492228246284738 |
| 500,000-point transformed quads, vertex N/UV | 56.990 ms | 39.013 ms | 112.568 MB | 2980019896878501511 |
| 500,000-point signed partial alternating surface with U/V caps, vertex N/UV | 72.703 ms | 50.931 ms | 164.960 MB | 2803938180915058581 |
| 1,000,000-point rows and columns, vertex N/UV | 45.638 ms | 28.880 ms | 120.103 MB | 2100000711956294262 |
| 1,000,000 points with point N/UV | 24.623 ms | 15.957 ms | 64.084 MB | 1726628037830314731 |

The output-equivalent sequential reference took 174.728/182.901 ms, allocated
210.002 MB, and retained the compatible hash. The final three-repeat
four-domain process peaked at 173,548 KiB. Rays's polygon subset was audited
against the current [SideFX Torus SOP](https://www.sidefx.com/docs/houdini/nodes/sop/torus.html):
native analytic, single Mesh/NURBS/Bezier, spline-order, and rational
perfect/imperfect modes remain explicit omissions rather than placeholders.

The Tube benchmark commands are:

```sh
RAYS_RDK_OPS_FILTER=tube_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=tube_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile=release tools/bench_rdk_ops.exe
```

On OCaml 5.3.0/Dune 3.24.0, Linux 6.8 aarch64, four Apple CPU cores, and grain
16,384, five-run release medians and one-domain allocations were:

| Tube fixture | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| 1,000,000-point open quads | 64.933 ms | 43.582 ms | 152.972 MB | 59682261814057068 |
| 500,000-point capped frustum, vertex N/UV | 53.969 ms | 29.205 ms | 112.578 MB | 2924452240935117849 |
| 499,501-point capped shared-apex cone, vertex N/UV | 67.520 ms | 48.129 ms | 164.985 MB | 2669512725917615264 |
| 1,000,000-point rows and columns, vertex N/UV | 43.058 ms | 23.640 ms | 120.079 MB | 3051396544248793262 |
| 1,000,000 points with point N/UV | 23.290 ms | 17.983 ms | 64.060 MB | 1765457354861488267 |

The prior general Sweep-based million-point cylinder baseline took
65.925/64.522 ms and allocated 201.021 MB. The dedicated source retains the
same output cardinality while cutting allocation 23.9%, matches its sequential
latency, and is 1.48x faster at four domains. The final three-repeat
four-domain process peaked at 173,652 KiB. Rays's polygon subset was audited
against the current [SideFX Tube SOP](https://www.sidefx.com/docs/houdini/nodes/sop/tube.html):
native analytic Primitive and single Mesh/NURBS/Bezier families, spline U/V
orders and wrap, and rational perfect/imperfect modes remain explicit
omissions.

The Platonic benchmark commands are:

```sh
RAYS_RDK_OPS_FILTER=platonic_generator_reference \
  RAYS_RDK_OPS_REPEATS=5 RAYS_BENCH_DOMAINS=1 \
  dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=platonic_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
```

On OCaml 5.3.0/Dune 3.24.0, Linux 6.8 aarch64, four Apple CPU cores, the
100,000-call icosahedron batch (1.2 million generated points) improved from
83.603 ms and 696.800 MB to 23.459 ms and 266.400 MB with exact hash
`108589944924191245`: 3.56x faster and 61.8% less allocation. A 20,000-call
transformed soccer-ball batch with vertex normals, primitive color, and face
groups took 49.815 ms and 292.640 MB with hash `4440798644007023453`. The final
three-repeat process peaked at 54,496 KiB. The public subset was audited against
the current [SideFX Platonic Solids SOP](https://www.sidefx.com/docs/houdini/nodes/sop/platonic.html):
the mathematical solids and soccer ball are implemented; Houdini's bundled
fixed Utah-teapot test asset is an explicit non-procedural omission.

The Spiral benchmark commands are:

```sh
RAYS_RDK_OPS_FILTER=spiral_generator_reference RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=spiral_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=spiral_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile=release tools/bench_rdk_ops.exe
```

On OCaml 5.3.0/Dune 3.24.0, Linux 6.8 aarch64, four Apple CPU cores, grain
16,384, and five-run release medians:

| Spiral fixture | 1 domain | 4 domains | Allocated (1d) | Exact hash |
|---|---:|---:|---:|---:|
| 1,000,001-point equal-angle Archimedean curve | 42.837 ms | 30.393 ms | 80.006 MB | 3136671808158376137 |
| 1,000,004-point four-copy equal-arc ramped logarithmic curve | 321.491 ms | 113.081 ms | 50.007 MB | 1570677764862568638 |
| Same equal-arc curve with angle, X/Y/tangent, orient, and distance | 375.826 ms | 147.731 ms | 170.017 MB | 3988733468285775559 |

The output-equivalent boxed tuple plus generic Polyline reference took
107.229 ms and allocated 128.003 MB with the first fixture's exact hash. The
dedicated equal-angle kernel is therefore 2.50x faster and allocates 37.5%
less on one domain. The advanced all-attribute result is 2.54x faster on four
domains than one, and its allocation is its packed output plus bounded shared
integration/profile tables. The three-repeat four-domain equal-arc process
peaked at 178,856 KiB RSS including both fixtures, hashing, Dune, and the OCaml
heap. The polygon subset was audited against the current
[SideFX Spiral SOP](https://www.sidefx.com/docs/houdini/nodes/sop/spiral.html):
native NURBS/Bezier curves and curve-order controls remain explicit omissions.

The Grid-specific command is:

```sh
RAYS_RDK_OPS_FILTER=grid_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=grid_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile=release tools/bench_rdk_ops.exe
```

Before the Grid rewrite, the compatible million-point triangle source measured
139.22 ms at one domain and 127.86 ms at four domains. The production kernel's
five-run medians are 42.29 ms and 26.87 ms with the identical
`3253461948889680712` geometry hash: 3.29x and 4.76x faster respectively, with
the four-domain result 1.57x faster than one domain. Required output remains
the allocation floor (114.22 MB for triangles); the four-mode run peaked at
138,744 KiB RSS. Row-major point generation removes per-point division, while
surface/curve topology and offsets use exact disjoint output ranges.

The Circle-specific command is:

```sh
RAYS_RDK_OPS_FILTER=circle_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=1 dune exec --profile=release tools/bench_rdk_ops.exe
RAYS_RDK_OPS_FILTER=circle_generator RAYS_RDK_OPS_REPEATS=5 \
  RAYS_BENCH_DOMAINS=4 dune exec --profile=release tools/bench_rdk_ops.exe
```

The former closed-Circle path generated a boxed tuple array, rebuilt it through
a packed builder, and remained serial: 92.75 ms at one domain, 88.49 ms at four,
and 112.23 MB allocated for 1,002,001 points. The new exact-sized source retains
the identical `1595635405635298122` hash and measures 22.94/13.21 ms: 4.04x
faster at one domain, 6.70x faster at four, and 71.4% less allocation. The
four-domain three-mode run peaked at 54,072 KiB RSS. Independent ellipse,
orientation, and sliced-arc math stays in the same point loop instead of
creating transform or topology intermediates.
