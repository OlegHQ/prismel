# Metal binding contract

The Metal binding is an ordinary Dune library under `lib/metal`, published as
`prismel.metal`. It is a foundational library beneath `ogpu_metal`; it has no
dependency on SDL3, OGPU, Runtime, Prismel, PXUI, or Wap. Runtime will eventually
combine an SDL3-owned `CAMetalLayer` with this binding through `ogpu_metal`, but
the binding itself never owns an SDL window.

## Generated SDK inventory

`tools/metal/generate_inventory.exe` is an OCaml/Dune tool. It invokes Clang's
Objective-C++ AST dump against the selected macOS SDK, parses the dump in OCaml,
and writes `lib/metal/generated_api_inventory.json` plus compiled provenance.
No Python generator or orchestration layer participates in the build.

The inventory is pinned to macOS SDK 26.5, an arm64 macOS 14.0 deployment
target, and the public headers from Metal.framework plus
`QuartzCore/CAMetalLayer.h`. Header paths, sizes, individual hashes, aggregate
hash, compiler identity, declaration identity, signatures, availability, and
classification-source hash are recorded. Anonymous typedef records and enums
are resolved to their public names, empty Objective-C categories are normalized
to their owning class, and generation fails if a reviewed identifier is absent
or duplicated.

Inventory coverage is incremental and honest. A symbol becomes `bound` only
when the ownership-aware safe layer implements it. Declarations unavailable on
macOS are `scope-excluded`; remaining declarations stay `unreviewed` until the
corresponding Phase 2 slice lands. M1 is not green until the generated inventory
contains no unreviewed in-scope declaration.

## Thread and ownership model

Every public native operation requires both the initial OCaml domain and the
platform main thread. A wrong-domain call returns `Wrong_domain` before entering
Metal. The only any-domain native activity is a custom-block finalizer placing
an opaque retained Objective-C pointer into a fixed 65,536-entry queue; it does
not release Objective-C objects or call back into OCaml. An initial-domain safe
entry point drains that queue inside a coarse autorelease pool.

Objective-C++ stubs compile with ARC. Safe handles are opaque and carry a unique
generation, an atomic destroyed flag, device identity, and parent-dependent
count. Explicit destruction is idempotent. Native access after destruction,
parent teardown with live children, cross-device binding, invalid state, and
bounds or cardinality overflow return typed errors before Objective-C. Blocking
command-buffer completion releases the OCaml runtime lock while its native
handle remains rooted and cannot be concurrently destroyed through the safe
API.

`Metal.Release_queue.stats` exposes queued, dropped, live, total-created,
total-released, and resident-byte facts for qualification. Queue overflow is a
hard typed error rather than silent reclamation on a GC domain.

## Implemented vertical slices

The current safe slices cover device enumeration and capabilities; shared,
managed, and private buffers; CPU range transfer and lexical mapped-range
handles; textures and views; samplers; labels; runtime MSL library compilation
with full `NSError` diagnostics; automatic and placement heaps; function lookup;
compute-pipeline creation and limits; command queues and buffers; compute
encoding and resource binding; checked thread dispatch; submission; blocking
completion; and command status/errors.

A `Buffer.Mapping.t` is valid only inside `Buffer.with_mapping`. It exposes
checked copy operations rather than a Bigarray backed by an escaping native
pointer. Retaining the opaque value is harmless: every operation returns
`Destroyed` after the callback leaves, buffer teardown is rejected while the
scope is active, and `Fun.protect` closes the scope on exceptions.

`Texture.descriptor` models all current Metal texture kinds, explicit
dimensions, mip/sample/array counts, storage/cache/hazard modes, usage, GPU
optimization intent, and a deliberately reviewed set of ordinary color,
floating-point, depth, and stencil formats. `Texture.create` validates positive
and bounded dimensions, mip cardinality, array/kind shape, duplicate usage,
multisample structure, and device sample-count support before entering
Objective-C. The bridge then checks that Metal preserved every observable
descriptor property. A native rejection remains a labeled `Native_error`; it
never leaves a partially owned safe handle.

Shared and managed texture transfers accept explicit regions, mip levels,
slices, source offsets, row pitches, and image pitches. Region bounds, pixel
stride, cardinality, OCaml byte-buffer limits, and source coverage are checked
in OCaml and defensively repeated at the C boundary. Private and multisample
textures reject CPU transfer. Reads initialize the entire result so Metal's
untouched pitch padding cannot expose native memory. Texture views require
`Pixel_format_view` usage, preserve kind/slice shape, currently permit only the
reviewed equal or linear/sRGB format pairs, and hold their parent alive until
explicit destruction or finalization.

`Heap` exposes device size/alignment queries, automatic and explicit-placement
descriptors, live allocation/usage facts, fragmentation queries, and checked
buffer/texture allocation. Heap storage and cache modes must match each child;
the binding normalizes Metal's documented default heap hazard mode to
`Untracked`. Placement offsets are required only for placement heaps and are
checked for negativity, power-of-two alignment, addition overflow, and heap
bounds before Objective-C. A bounded live-allocation ledger rejects overlapping
placement resources until the older resource is destroyed or explicitly made
aliasable. Although Metal reports placement resources as natively aliasable at
creation, `Buffer.make_aliasable` and `Texture.make_aliasable` are the safe
layer's irreversible storage-relinquishment boundary: the old handle rejects
all later data access and its range may then be reused. Automatic-heap storage
can likewise be reused only after that explicit transition. Direct resources,
texture views, resources with live children/mappings/command dependencies, and
resources on a discardable heap reject the transition before Objective-C.

Buffers, base textures, and heaps expose synchronous purgeable-state query and
transition. A transition returns Metal's prior state and immediately queries
the resulting state; this matters because a device may keep a requested
resource nonvolatile. Data access and command binding reject resources or
ancestor heaps whose observed state is `Volatile` or `Empty`. Restoring an empty
resource to `Nonvolatile` permits reinitialization but does not claim its old
contents survived. Heap transitions reject active lexical mappings and tracked
command uses. Command buffers retain each bound resource exactly once until a
terminal status, explicit destruction, or finalization, preventing destroy,
purge, or alias transitions while the GPU may still use it.

Heap children retain the typed heap owner, while views retain their typed
texture owner, so teardown with a live descendant is a deterministic
`Parent_has_dependents` error. Automatic resources intentionally report no
placement offset; placement resources round-trip Metal's actual offset.

`Sampler.descriptor` covers min/mag/mip filtering, anisotropy, all current
address modes and border colors, normalized coordinates, finite float32 LOD
clamps, comparison, LOD averaging, and argument-buffer support. Invalid
anisotropy, non-finite or inverted clamps, illegal unnormalized-coordinate
combinations, and malformed labels fail before sampler creation. Sparse
resources, residency, buffer-backed textures, external ownership, and the
remaining pixel-format capability matrix are still pending; this resource
slice is therefore progress toward M3, not an M3 completion claim.

`test_metal.exe` runs a real M1 compute kernel, wrong-domain and invalid-state
cases, shader diagnostics, buffer and texture bounds/stride/cardinality checks,
texture mip transfer and views, sampler validation, multisample capability
gating, heap alignment and placement, aliasing, purgeability, command-resource
retention, parent ownership, idempotent destruction, stale access, and
GC-finalizer release. The separate ownership stress performs
warm-up followed
by 100,000 measured buffer create/destroy cycles, 100,000 measured
texture/sampler create/destroy cycles, and 10,000 heap/purge/alias/replacement
cycles covering 30,000 measured heap/child-resource handles. Each lane requires
exact created/released balance, zero pending or dropped releases, stable
live-handle count, and bounded settled RSS growth.

`PRISMEL_METAL_SANITIZERS` is parsed by OCaml build configuration and accepts
`address`, `undefined`, or `thread`; ThreadSanitizer is deliberately exclusive,
while AddressSanitizer and UndefinedBehaviorSanitizer may be combined. The same
configuration instruments the ARC bridge, its dynamic bytecode stub, and the
final executable link. `tools/metal/check_memory.exe` rejects sanitizer reports,
nonzero Leaks summaries, and Guard Malloc errors for the conformance and
resource-stress tests. Guard Malloc runs the conformance subset because giving
every stress allocation its own protected VM region would test the tool's
intentional memory amplification rather than Metal lifetime settling.

AddressSanitizer qualification disables its allocation quarantine for the
ownership stress. This keeps the RSS assertion about live Metal/ARC resources
instead of ASan's intentionally retained freed blocks; exact created/released,
queue, and sanitizer checks remain active. ThreadSanitizer uses a larger RSS
tolerance for shadow-memory growth while retaining the same exact handle
balance.

`tools/bench_metal_ffi.exe` is the release-profile M9 baseline. It measures one
Objective-C property query per OCaml call, one batched call containing the same
number of queries, the equivalent loop timed inside Objective-C++, and the
current ownership-aware `Device.info` path. Every sample records wall time,
FFI-call count, minor/major/promoted allocation, collection count, and an exact
checksum. The executable rejects a batched median more than 5% slower than the
native loop. The live timing check runs through the explicit `@metal-bench`
alias, outside Dune's parallel functional/stress suite; ordinary `@runtest`
still validates the frozen machine-readable M9 evidence. This keeps the 5%
comparison under controlled conditions instead of measuring contention from
unrelated tests. The result makes the later descriptor/command batching
decision measurable instead of applying `[@@noalloc]` or per-item calls
speculatively.

The currently selected Command Line Tools include SDK 26.5 headers but not the
`metal` and `metallib` executables. Runtime source compilation is therefore
covered locally; offline `.metallib`, Xcode validation, capture, and archive
qualification remain explicit Phase 2 work requiring the pinned full Xcode
toolchain. This limitation does not weaken or skip any M1-M10 completion gate.

Run the current binding checks with:

```sh
opam exec -- dune runtest lib/metal --force
opam exec -- dune build @all @doc
opam exec -- dune build @metal-bench

PRISMEL_METAL_SANITIZERS=address opam exec -- dune build \
  --build-dir /tmp/prismel-metal-asan \
  lib/metal/test_metal.exe lib/metal/test_metal_stress.exe
opam exec -- dune exec tools/metal/check_memory.exe -- \
  --mode address --artifacts /tmp/prismel-metal-asan/default
opam exec -- dune exec --profile release tools/bench_metal_ffi.exe -- \
  --iterations 1000000 --samples 7 --profile release
```
