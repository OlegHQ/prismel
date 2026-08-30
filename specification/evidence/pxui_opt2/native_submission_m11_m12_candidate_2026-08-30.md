# Native submission and hidden-work candidate, 2026-08-30

This candidate continues the frozen `OPT2.md` migration. It does not claim
M11, M12, or final qualification complete.

## Changes

- Production mixed-layer rendering no longer materializes the compatibility
  aggregate `Render_ir` before staging its native layers.
- The Metal backend checks the bounded classic submission cache before native
  draw conversion and memoizes bounded retained-plan structural identities.
- Retained ICB owners now hold safe prepared resource sets. Creation validates,
  deduplicates, and retains each invariant resource once; replay reuses the raw
  resource arrays while preserving command-buffer completion ownership.
- Sketch UI suppresses inspector and camera reconciliation/pass execution while
  the complete UI is hidden. Retained runtime state is reconciled when shown.
- Opt-in `PRISMEL_RENDERER_PHASE_PROFILE=1` counters isolate view, native
  staging, lowering, submission, and release allocation.

## Measurements

Commands used the native debug/default profile on the reference Apple M1 with
`DUNE_CONFIG__BACKGROUND_ACTIONS=disabled`, one second warmup, and three seconds
measurement. These shortened diagnostic runs are not M14 qualification.

Visible, 18,278 pieces / 278,368 triangles / 835,104 render vertices:

- 191 frames, 63.55 FPS;
- 15.75 ms median, 19.41 ms p95;
- 214,512,208 bytes allocated, approximately 1.12 MiB/frame.

Hidden, same geometry:

- 349 frames, 116.29 FPS;
- 8.34 ms median, 9.90 ms p95;
- 8,007,240 bytes allocated, approximately 22.9 KiB/frame;
- 6,984 promoted bytes total.

The hidden lane improved from the preceding approximately 24.4 KiB/frame but
still misses the 16 KiB interim end-to-end gate. The visible lane remains far
above the final 8 KiB/frame gate. Memprof attributes the visible remainder
primarily to list assembly, Scene staging, retained argument-buffer validation,
and Metal render-pass submission. No final performance claim is made.

## Retained replay follow-up

Fresh shallow composition spines now match bounded cached native stages through
an explicit Scene-vocabulary comparator. Embedded Scene3 values remain eligible
only when `Scene3.Private.cacheable` accepts them, and every Scene2 resource
generation is rechecked before reuse. A retained replay is attempted before
Scene2/Scene3 lowering; misses fall back to the checked lowering transaction.

The Metal adapter also retains a bounded mapping from a physically reused
portable render command to its validated ICB plan. On a hit it validates that
the plan owner and dependency tokens remain live, creates the current drawable
attachment pass, and reuses the retained draw metadata and ICB. The focused
backend test reuses one physical command for 600 frames and verifies exact
pixels, attachment replacement, invalidation, cache statistics, and zero native
handle delta.

A shortened native visible diagnostic after these changes reported:

- 265 frames over 3.006 seconds, 88.17 FPS;
- 10.92 ms median, 14.27 ms p95;
- 76,657,168 allocated bytes, approximately 282.5 KiB/frame.

This is a substantial improvement over the earlier approximately 1.12 MiB/frame
candidate and now clears the 60 Hz timing envelope in this shortened run. It
still fails the interim 64 KiB/frame and final 8 KiB/frame allocation gates, so
M11 remains open.

After moving invariant ICB resource validation and raw-array construction into
the retained plan owner, the same two-second diagnostic reported:

- 175 frames over 2.003 seconds, 87.37 FPS;
- 10.98 ms median, 13.68 ms p95, 22.97 ms p99;
- 40,137,136 allocated bytes, approximately 229.4 KiB/frame;
- 2,011,640 promoted bytes total.

Compared with the immediately preceding 174-frame run at approximately
278.8 KiB/frame, this removes about 17.7% of steady visible allocation. The
result remains above both M11 allocation gates and is intermediate evidence.

Prepared sets now also carry one completion-owned lifetime into each command
buffer instead of expanding back into one OCaml retention node per resource.
The next two-second diagnostic reported:

- 180 frames over 2.010 seconds, 89.54 FPS;
- 10.61 ms median, 13.66 ms p95, 23.54 ms p99;
- 37,927,960 allocated bytes, approximately 205.8 KiB/frame;
- 1,929,976 promoted bytes total.

This removes another 8.1% from the immediately preceding prepared-array result.
The safe Metal layer rejects destruction while a command owns the set, releases
that ownership on completion, and keeps destruction idempotent. M11 remains
open because the final allocation gate is not met.

Once a retained native ICB plan has passed generation/resource validation, the
Metal queue now advances the portable epoch tracker with an empty command rather
than rebuilding the already-validated portable draw stream. Ordinary and
Command4 passes retain their full portable validation path. The resulting
two-second diagnostic reported:

- 180 frames over 2.011 seconds, 89.52 FPS;
- 10.50 ms median, 13.00 ms p95, 26.05 ms p99;
- 36,084,056 allocated bytes, approximately 195.8 KiB/frame;
- 1,895,296 promoted bytes total.

This is another 4.9% reduction from the immediately preceding run. It remains
intermediate evidence and does not satisfy the M11 allocation gate.

Retained Metal replay now reuses the complete typed native pass when its exact
attachment ID/token vector still matches. Attachment replacement and resize
take the checked reconstruction path and refresh the cached template only after
successful submission. The corresponding two-second diagnostic reported:

- 182 frames over 2.002 seconds, 90.91 FPS;
- 10.34 ms median, 12.59 ms p95, 23.40 ms p99;
- 30,377,936 allocated bytes, approximately 163.0 KiB/frame;
- 1,738,672 promoted bytes total.

The portable queue now retains checked resource/pipeline translations per
physical command instead of retaining only the preceding pass. Its storage is
a fixed 256-slot ring: lookup and eviction allocate no list spine, failed
driver admission does not mutate an entry, and dead/cross-device resources are
still checked on every use. A 301-distinct-command regression proves the exact
256-entry bound. The next two-second diagnostic reported:

- 181 frames over 2.005 seconds, 90.27 FPS;
- 10.47 ms median, 14.03 ms p95, 20.25 ms p99;
- 25,299,544 allocated bytes, approximately 136.5 KiB/frame;
- 1,993,840 promoted bytes total.

The complete-pass reuse and per-command translation cache remove about 30.3%
from the preceding 195.8 KiB/frame result. The M11 allocation gate remains open.

Stable automatic batches now compare exact render-pass state, resource IDs,
draw values, and retained pipeline identities against the admitted preceding
submission. A focused two-batch regression changes only the second batch and
proves that the first command is reused while the second is rebuilt. The
visible benchmark after this slice reported 25,179,096 bytes over 183 frames,
approximately 134.4 KiB/frame; the behavioral isolation is proven, but this
slice did not improve the aggregate allocation result.

Sketch UI status painting now keeps the long status prefix and the short FPS
suffix in separate retained display-list segments. FPS updates therefore
rasterize and replace only the suffix. The next controlled run reported
24,829,952 bytes over 184 frames, approximately 131.8 KiB/frame, with a
10.20 ms median and 13.24 ms p95.

Classic native passes now lazily prepare one validated Metal render-pass
descriptor and optional depth/stencil state after backend cache admission, then
reuse them across unchanged submissions. Direct and Command4 paths preserve
their prior completion-owned or non-classic lifetimes. Cache/resource
invalidation destroys prepared pass metadata atomically, attachment replacement
does not make the attachment an ICB dependency, and ICB preparation failures
release state before ownership transfer. The controlled two-second run
reported:

- 186 frames over 2.005 seconds, 92.77 FPS;
- 9.93 ms median, 13.45 ms p95, 24.35 ms p99;
- 23,852,104 allocated bytes, approximately 125.2 KiB/frame;
- 2,377,152 promoted bytes total.

This is a further 8.3% allocation reduction from the committed 136.5 KiB/frame
candidate, but it still fails the interim and final M11 allocation gates.

The retained native replay cache now uses a fixed 256-slot array with an exact
live length. Lookup, replacement, capacity eviction, resource invalidation, and
stale-plan rejection compact that array in place instead of rebuilding list
spines through `List.partition`, `List.filter`, `List.map`, and
`List.rev_append`. Dependency liveness also runs through a top-level indexed
scan rather than allocating nested per-submission closures. An allocation-stack
profile confirms that the replay-cache partition/reversal sites disappeared.
The following non-profiled controlled run reported:

- 184 frames over 2.009 seconds, 91.58 FPS;
- 10.04 ms median, 14.24 ms p95, 22.74 ms p99;
- 20,630,368 allocated bytes, approximately 109.5 KiB/frame;
- 2,221,480 promoted bytes total.

This removes approximately 12.5% from the preceding 125.2 KiB/frame result.
The cache remains exactly bounded and preserves immediate destruction of
rejected pass metadata, but the stable UI submission still exceeds the M11
final allocation gate.

Retained indirect passes now bind their immutable vertex, fragment, and texture
prepared-resource sets through one private typed Metal transaction. It checks
all three lifetimes and devices before issuing any binding, uses fixed usage and
stage masks, and transfers completion ownership only after all native calls
succeed. This removes three independent validation/result chains without
exposing an unsafe public entry point. The Sketch UI workspace also retains its
header, panel, and splitter scene for an exact pane/collapse state instead of
reconstructing identical Scene nodes on every frame. The controlled combined
run reported:

- 186 frames over 2.008 seconds, 92.65 FPS;
- 9.97 ms median, 12.77 ms p95, 24.60 ms p99;
- 19,439,352 allocated bytes, approximately 102.1 KiB/frame;
- 2,205,000 promoted bytes total.

This removes approximately 6.8% from the preceding 109.5 KiB/frame result.
Exact UI-state cache keys preserve resize and collapse invalidation, while the
ordinary Scene release pass continues to bound automatic text lifetimes. M11
remains open.

The shared Metal initial-domain/main-thread/release-queue preflight now has a
result-returning form used by hot validated encoder setters and retained-set
binding. The public callback form delegates to the same preflight, so error
ordering and release draining are unchanged, while the retained render path no
longer allocates one callback closure per fixed-state call. The next controlled
run reported 19,211,368 allocated bytes over 185 frames, approximately
101.4 KiB/frame, at 92.40 FPS with a 9.94 ms median and 14.14 ms p95. This is a
small additional reduction; M11 remains open.

Status text formatting now follows semantic invalidation instead of preceding
it. Idle cook state, selected-node label, render status, and the 30-frame FPS
sample are compared before any `Printf` or concatenation work; active cook
elapsed time remains part of the key and continues to update. The next
controlled run reported 18,483,408 allocated bytes over 185 frames,
approximately 97.6 KiB/frame, at 92.49 FPS with a 10.10 ms median and 12.50 ms
p95. Allocation profiling no longer reports FPS/status formatting among the top
sites. M11 remains open.

Native Scene staging now retains Scene2 layers independently in a 64-entry,
64 MiB cache keyed by structural scene state and renderer density. A later
layer change therefore reuses the exact immutable IR of unrelated layers; a
focused two-layer regression proves both stable-object reuse and changed-layer
replacement. Only IR is retained. Automatic text/image resources are rebound
from the current frame on every hit, preserving snapshot lease lifetimes and
resource generation checks rather than extending a released text snapshot.

The phase profiler now reports whole-stage hit/miss counts and direct hit-path
bytes only when enabled. A diagnostic run measured 112 bytes for an exact
whole-stage hit and showed that the remaining periodic FPS changes were causing
whole-scene misses. After independent Scene2 layer reuse, the controlled
non-profiled run reported:

- 186 frames over 2.010 seconds, 92.54 FPS;
- 10.12 ms median, 12.93 ms p95, 22.87 ms p99;
- 17,001,904 allocated bytes, approximately 89.3 KiB/frame;
- 1,535,288 promoted bytes total.

This removes approximately 8.5% from the preceding 97.6 KiB/frame result and
proves that changing a UI segment no longer rematerializes unrelated Scene2
payloads. M11 remains open against the final allocation gate.

The classic Metal encoder hot path now validates viewport, scissor, and cull
state with direct control flow. It preserves the checked safe API and exact
error classifications while removing higher-order validation closures and the
temporary six-element float list previously allocated for every viewport.
Five isolated retained Scene3 runs of 300 measured frames each reported an
exactly repeatable 27,330.64 allocated bytes/frame and 23.17--23.36 promoted
bytes/frame. Median frame time ranged from 8.45 to 8.57 ms and p95 from 9.37 to
10.48 ms. The preceding diagnostic was 27,911.92 bytes/frame; this is a small
native-wrapper reduction, not evidence that the M11 final gate is complete.

## Focused verification

- `lib/ogpu_metal/test_ogpu_metal_backend.exe`: transfer/compute/render 1000,
  retained-plan queues/surface, zero native handle delta.
- `lib/ogpu_metal/test_ogpu_metal_render_pass.exe`: list/strip, MSAA,
  Command4 stencil/depth, atomic rejection, and zero native handle delta.
- `lib/ogpu_metal/test_ogpu_metal_submission.exe`: transfer/compute/clear,
  bounded ordering, and zero native handle delta.
- `lib/ogpu_metal/test_scene_execution_metal.exe`: SDL-free exact-pixel draw and
  resize with zero native handle delta.
- `lib/ogpu_metal/test_ogpu_metal_portable_passes.exe`: portable transfer and
  compute graph with zero native handle delta.
- `lib/metal/test_metal_render_encoder_safe.exe`: prepared-resource duplicate
  rejection, command use, retained lifetime, idempotent release, and teardown.
- `lib/ogpu/test_ogpu_backend.exe`: deterministic submit/loss/lifetime
  conformance, stable translation allocation, and exact 256-entry cache bound.
- `test/test_sketch_ui.exe`: passed.
