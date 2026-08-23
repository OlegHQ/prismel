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

Every public native operation requires both OCaml domain zero and the platform
main executor. In an ordinary executable those are the initial OCaml domain and
physical main thread. An embedded XPC service is the narrow exception to the
physical-thread test: `NSXPCListener.serviceListener` hands its main dispatch
executor to `xpc_main`, so the bridge registers only that serialized executor
with OCaml domain zero for the dynamic extent of a request callback. No OCaml
code runs on an NSXPCConnection private queue, and the temporary registration is
removed before returning to XPC. Any other wrong-domain call returns
`Wrong_domain` before entering Metal. The only remaining any-domain native
activity is a custom-block finalizer placing an opaque retained Objective-C
pointer into a fixed 65,536-entry queue; it does not release Objective-C objects
or call back into OCaml. A domain-zero safe entry point drains that queue inside
a coarse autorelease pool.

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
managed, and private buffers; copied and page-aligned no-copy buffer creation;
CPU range transfer and lexical mapped-range handles; textures, shareable private
textures and opaque shared handles, IOSurface-backed textures, buffer-backed
linear textures, texture buffers, and views; samplers; labels; runtime MSL
library compilation with full `NSError` diagnostics; automatic, placement, and
established sparse heaps; macOS-15 residency sets; function lookup;
compute-pipeline creation and limits; command queues and buffers; compute,
resource-state, and narrow buffer-to-texture blit encoding; checked resource
binding and thread dispatch; submission; blocking completion; and command
status/errors.

A `Buffer.Mapping.t` is valid only inside `Buffer.with_mapping`. It exposes
checked copy operations rather than a Bigarray backed by an escaping native
pointer. Retaining the opaque value is harmless: every operation returns
`Destroyed` after the callback leaves, buffer teardown is rejected while the
scope is active, and `Fun.protect` closes the scope on exceptions.

`Buffer.create_copy` passes a checked OCaml byte range to
`newBufferWithBytes:length:options:` and verifies that the returned buffer owns
the requested length and resource modes. The source remains rooted for the
synchronous copy only; later source mutation cannot change the Metal buffer.

`Buffer.External` owns an opaque, zero-initialized, page-aligned single VM
region allocated with `mmap`. Lengths must be positive page multiples, and all
copy access is range-checked in OCaml and again at the native boundary.
`Buffer.create_no_copy` is exclusive: a second borrow, owner access, or owner
destruction is rejected while the safe Metal buffer is live, and private
storage is rejected before Objective-C. The safe buffer retains both its
originating device and VM owner, so neither can be destroyed while the borrow
is live. Metal's deallocator block strongly retains the VM owner until the
native buffer actually relinquishes the borrow; this is necessary because the
qualified M1 may defer the callback past safe handle destruction. The VM owner
uses `munmap`, so 10,000 create/borrow/destroy cycles settle without
allocator-retained page growth. Callback pointer/length mismatches are counted
as a hard ownership failure.

`Texture.descriptor` models all current Metal texture kinds, explicit
dimensions, mip/sample/array counts, storage/cache/hazard modes, usage, GPU
optimization intent, and all 130 concrete, non-deprecated pixel formats in the
pinned SDK: 64 numeric, packed, subsampled, extended-range, depth, stencil, and
stencil-plane formats plus 66 BC, EAC/ETC2, and ASTC block-compressed formats.
The deprecated PVRTC family, `Invalid`, and the Metal 4 unspecialized sentinel
are not presented as concrete resource formats. `Texture.format_layout`
exposes each reviewed format's checked block dimensions and byte size.
`Texture.create` validates positive and bounded dimensions, mip cardinality,
array/kind shape, duplicate usage, multisample structure, view-only formats,
4:2:2 shape, device sample-count support, and the device's explicit
Depth24/Stencil8 capability before entering Objective-C. BC creation is gated
by `supportsBCTextureCompression`; EAC/ETC2 and LDR ASTC require Apple family 2
or Metal 4, HDR ASTC requires Apple family 6 or Metal 4, and compressed volume
textures require the reviewed Apple 3, Mac 2, Metal 3, or Metal 4 feature.
Compressed descriptors reject 1D, multisample, texture-buffer, writable,
atomic, and render-target shapes before native allocation. The bridge then
checks that Metal preserved every observable descriptor property. A native
rejection remains a labeled `Native_error`; it never leaves a partially owned
safe handle.

Shared and managed texture transfers accept explicit regions, mip levels,
slices, source offsets, row pitches, and image pitches. Region bounds, format
block alignment, cardinality, OCaml byte-buffer limits, and source coverage are
checked in OCaml and defensively repeated at the C boundary through one generic
block-layout path, including partial final blocks at mip edges, exact two-pixel
blocks for packed 4:2:2 formats, and every BC/EAC/ETC2/ASTC block size. Private
and multisample textures reject CPU transfer. Reads initialize the entire
result so Metal's untouched pitch padding cannot expose native memory. Texture
views require
`Pixel_format_view` usage, preserve kind/slice shape, permit the reviewed equal,
linear/sRGB, extended-range/sRGB, compressed linear/sRGB, and
depth-stencil/stencil-plane pairs, and hold their parent alive until explicit
destruction or finalization.

`Texture.minimum_buffer_alignment` distinguishes ordinary 2D linear textures
from the `Texture_buffer` kind and exposes Metal's per-device, per-format
alignment as a checked positive power of two. `Texture.create_from_buffer`
accepts only those two kinds and ordinary numeric or packed color formats;
subsampled and block-compressed formats remain non-linear resources. It requires
depth, array length, mip count, and sample count of one; normalizes and matches
the buffer's storage/cache/hazard modes; gates render-target usage on Apple GPU
family 1; and checks offset, aligned row pitch, pixel-row cardinality, 64-bit
overflow, and the complete pitched span against the buffer before native
creation. The bridge repeats the checks and verifies `buffer`, `bufferOffset`,
and `bufferBytesPerRow`. Standalone device/heap creation rejects the
`Texture_buffer` kind so it cannot silently take a semantically different
allocation path.

The returned texture retains its typed buffer parent, shares that buffer's
purgeability/aliasing state, and preserves the buffer ancestor through texture
views. Buffer destroy, purge, and alias transitions are rejected while any such
texture is live. A texture cannot apply those transitions independently and
directs the caller to its backing buffer. Heap and no-copy external-memory
ancestry therefore remains intact through the complete
texture-to-buffer-to-owner chain.

`Texture.create_shared` is a distinct private-storage allocation path and
verifies Metal's `isShareable` result before exposing the texture. A
`Texture.Shared_handle.t` records the originating device identity and native
handle label, retains that device, and remains importable after the source
texture is destroyed. `Texture.import_shared` accepts only a live handle on the
same device and re-verifies the imported descriptor and sharing state. Source,
handle, and every import have independent explicit/finalizer lifetimes: handle
destruction prevents later imports but does not invalidate imports that already
succeeded. The handle is deliberately opaque; NSSecureCoding is not exposed as
an untyped byte archive.

`Texture.Shared_handle.Xpc` instead provides a typed, bounded cross-process
transport for embedded application XPC services. A connection names the
service and caps request/reply payload bytes; each synchronous call supplies a
bounded operation name, one live shared handle, versioned descriptor metadata,
opaque application bytes, and an explicit bounded timeout. A timeout
invalidates the underlying connection. The service accepts only connections
with the same effective user ID, caps concurrent active requests, validates the
operation, payload, metadata version, format, dimensions, resource modes,
usage, and device registry identity, and exposes a one-shot request. A handler
must call `reply` or `reject` before returning; a return without either, or an
exception, is rejected automatically. Completion releases the incoming safe
handle and a second completion deterministically returns `Destroyed`.

`Xpc.serve` is intended as the terminal entry point of the separately launched
service executable and does not normally return. The Dune conformance target
constructs a real `.app/Contents/XPCServices/*.xpc` bundle using the OCaml
`build_xpc_bundle` executable. Its OCaml client writes `37` into a private
shareable texture, the separately launched OCaml service imports it and writes
`91`, and the client imports the returned handle and observes `91`; the reply
also carries a service PID distinct from the client. Missing-service,
configuration, payload, timeout, rejection, ownership, and stale-handle paths
are exercised without a Python orchestration layer.

`Texture.Io_surface` is a narrow ownership helper rather than a second general
IOSurface binding. The existing OCaml build helper links IOSurface.framework
directly through Dune. It creates checked, automatically aligned single- or
multi-plane surfaces, records the returned allocation and per-plane row layout,
and exposes only lock-bounded byte copies; no native base address escapes into
OCaml. `Texture.create_from_io_surface` accepts one matching ordinary-color 2D
plane in shared/default-cache storage and rejects plane, dimension, pixel-width,
shape, and mode mismatches before Metal. The bridge repeats those checks and
verifies the returned texture's `iosurface` identity and `iosurfacePlane`.

An IOSurface texture retains both its surface owner and creating device, while
views preserve that typed ancestry. The surface therefore cannot be destroyed
while any base texture is live, and purgeability or aliasing cannot be changed
through a texture that does not own its allocation. IOSurface lock/unlock bounds
CPU access but does not replace Metal command synchronization; callers must
still complete or otherwise synchronize GPU use before concurrent CPU access.

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

Heap children retain the typed heap owner, buffer-backed textures retain their
typed buffer owner, and views retain their typed texture owner, so teardown
with a live descendant is a deterministic
`Parent_has_dependents` error. Automatic resources intentionally report no
placement offset; placement resources round-trip Metal's actual offset.

`Heap.Sparse` implements the established macOS sparse-texture model on macOS 13
or newer devices that report Apple GPU family 6 support. The macOS 13 floor is
required by the binding's explicit page-size query and heap descriptor rather
than inferred from legacy sparse support alone. Sparse heaps require
private/default-cache storage, an explicit 16, 64, or 256 KiB page size
supported by the device, and a heap size that is an exact multiple of that
page. Legacy sparse heaps reject buffers and placement offsets. The binding
preflights each texture kind/format/sample/page
combination through the device tile-layout query before allocation and verifies
that a heap-created texture reports `isSparse`. This includes compressed
EAC/ETC2 and ASTC resources on Apple family 6 or newer; their reported tile
dimensions must remain aligned to the selected format's blocks. Depth and
stencil formats use the same capability query instead of a blanket exclusion.
The qualified M1 accepts `Depth16Unorm`, `Depth32Float`, `Stencil8`, and
`Depth32Float_Stencil8`; its unsupported `Depth24Unorm_Stencil8` path remains
explicitly capability-gated and allocates no safe handle.

`Texture.sparse_info` returns the exact device tile dimensions, page bytes,
first mip in the packed tail, and tail bytes while retaining typed sparse-heap
ancestry. `Resource_state_encoder.update_texture_mapping` accepts tile—not
pixel—coordinates and checks positive cardinality, mip and slice bounds, tile
bounds, packed-tail addressing, device identity, and whether one request can
fit in the heap before Objective-C. A successful map or unmap retains the
texture and ancestor heap until the command buffer reaches a terminal state.
Metal can still fail a mapping silently when concurrent mappings exhaust the
heap; callers that overcommit need a residency-map policy rather than a false
success guarantee from this wrapper.

The conformance path maps a base tile and mip tail, blits initialized bytes
from a checked staging-buffer range into the mapped tile in the same command
buffer, reads the authored texel through a compute shader, unmaps both regions,
and verifies the same shader observes Metal's defined zero result. The narrow
`Blit_encoder.copy_buffer_to_texture` entry point validates source offset,
row/image pitch, total source span, destination mip/slice/region, format stride,
sample count, and device identity before encoding; both resources remain owned
through completion. Bulk/indirect mapping, access-counter residency maps,
mapping moves, and macOS-26.4 placement-sparse buffers and textures remain
unreviewed rather than being conflated with this qualified path.

`Residency_set` availability-gates the macOS 15 API at runtime because the
library deployment target remains macOS 14. A set accepts only typed `Buffer`,
`Texture`, and `Heap` allocations from its creating device. Adds reject stale,
discardable, or alias-relinquished allocations; duplicate bulk arguments fail
before Objective-C. Every accepted member retains its safe owner and ancestor
heap-use token. A pending removal therefore continues to block resource
destruction and heap purge until `Residency_set.commit` applies the native
change and releases that ownership.

Membership queries cross-check the native `containsAllocation`,
`allAllocations`, and `allocationCount` surfaces against the safe ledger. On
the qualified Apple M1, `allAllocations` and `containsAllocation` reflect a
pending removal immediately while `allocationCount` can retain the pre-removal
count until `commit`; the safe `allocation_count` reports current membership
from `allAllocations` and accepts only those two explained native counts. The
same device also accepts a descriptor label but returns `nil` from the created
set's read-only `label`; the binding exposes that observed native value rather
than synthesizing a round trip.

Command queues retain every attached residency set until explicit removal or
queue teardown. Command buffers independently retain every set passed through
`use_residency_set(s)` until terminal status, wait, destruction, or
finalization, so removing a set from its queue cannot invalidate in-flight
work. Single and bulk add/remove/use entry points, manual request/end residency,
commits, allocation footprints, and set footprints are all availability
guarded and exception-translated.

`Sampler.descriptor` covers min/mag/mip filtering, anisotropy, all current
address modes and border colors, normalized coordinates, finite float32 LOD
clamps, comparison, LOD averaging, and argument-buffer support. Invalid
anisotropy, non-finite or inverted clamps, illegal unnormalized-coordinate
combinations, and malformed labels fail before sampler creation. Sparse
placement resources plus a public cross-process IOSurface transport are still
pending; sparse depth/stencil and shared-handle XPC transport are covered, but
this resource slice is therefore progress toward M3 rather than an M3
completion claim.

`test_metal.exe` runs a real M1 compute kernel, wrong-domain and invalid-state
cases, shader diagnostics, copied/no-copy external buffer ownership,
shareable texture/handle/import lifetimes, single- and multi-plane IOSurface
ownership and byte visibility, buffer-backed 2D/texture-buffer creation across
shared/managed/private storage,
configured cache/hazard modes, and shared transfer, buffer and texture bounds,
stride, and cardinality checks, texture mip transfer and views, sampler
validation, multisample capability gating, heap alignment and placement,
aliasing, purgeability, residency
membership/commit/queue/command retention, the complete 130-format matrix,
generic format-block transfers, encoded-block CPU round trips for all 66
capability-supported compressed formats, all 42 bidirectional compressed
linear/sRGB views, compressed private blits and volume creation, Depth24 and BC
capability gating, sparse page and tile capability queries, compressed sparse-tile
alignment, depth/stencil creation, map/blit/read/unmap behavior,
command-resource retention, parent ownership, idempotent destruction, stale
access, and GC-finalizer release. The
separate XPC conformance app exercises a real cross-process shared-texture
mutation and typed transport failures. The separate ownership stress performs
warm-up followed
by 100,000 measured buffer create/destroy cycles, 100,000 measured
texture/sampler create/destroy cycles, 10,000 heap/purge/alias/replacement
cycles covering 30,000 measured heap/child-resource handles, and 10,000
residency add/commit/remove/commit cycles covering 20,000 measured
set/resource handles. Ten thousand sparse heap/color-texture cycles and a
separate 10,000 sparse heap/depth-texture cycles each cover 20,000 measured
handles on the qualified M1. Another 10,000 buffer/linear-texture ownership cycles
cover 20,000 handles; 10,000 shareable-source/handle/import cycles cover 30,000
handles; 10,000 IOSurface/texture cycles cover 20,000 handles; and 10,000
external-memory/no-copy cycles cover 20,000 handles and exact
deferred-deallocator layout. Each lane requires exact
created/released balance, zero pending or dropped releases, stable live-handle
count, and bounded settled RSS growth. The stress executable launches each lane
in a fresh OCaml worker process. This keeps the RSS baseline and Metal resource
budget local to the resource kind under test; the Leaks qualification wraps
each worker directly rather than inspecting only the coordinator process.

`PRISMEL_METAL_SANITIZERS` is parsed by OCaml build configuration and accepts
`address`, `undefined`, or `thread`; ThreadSanitizer is deliberately exclusive,
while AddressSanitizer and UndefinedBehaviorSanitizer may be combined. The same
configuration instruments the ARC bridge, its dynamic bytecode stub, and the
final executable link. `tools/metal/check_memory.exe` rejects sanitizer reports,
nonzero Leaks summaries, and Guard Malloc errors for the conformance and
resource-stress tests. Guard Malloc runs the conformance subset because giving
every stress allocation its own protected VM region would test the tool's
intentional memory amplification rather than Metal lifetime settling.

AddressSanitizer qualification disables its allocation quarantine and uses a
256 MiB per-worker RSS ceiling for the ownership stress. ThreadSanitizer uses a
384 MiB per-worker ceiling, including for the `mmap`/`munmap` external-memory
lane. Those sanitizer ceilings cover measured allocator, shadow-memory, and
Metal-driver metadata high-water marks; they are not the production memory
budget. The ordinary unsanitized workers keep the default 8 MiB limit. Every
mode retains exact handle balance, zero pending or dropped releases, zero
deallocator-layout mismatches, and sanitizer diagnostics.
The separately launched XPC conformance bundle is also built and run under
combined AddressSanitizer/UndefinedBehaviorSanitizer and under ThreadSanitizer;
its 64-call reuse loop requires an exact client live-handle balance.

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
PRISMEL_METAL_SANITIZERS=address,undefined opam exec -- dune build \
  --build-dir /tmp/prismel-metal-xpc-asan \
  lib/metal/metal_xpc_conformance.app
ASAN_OPTIONS=abort_on_error=1:halt_on_error=1 \
UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
  /tmp/prismel-metal-xpc-asan/default/lib/metal/metal_xpc_conformance.app/Contents/MacOS/test_metal_xpc_client
PRISMEL_METAL_SANITIZERS=thread opam exec -- dune build \
  --build-dir /tmp/prismel-metal-xpc-tsan \
  lib/metal/metal_xpc_conformance.app
TSAN_OPTIONS=abort_on_error=1:halt_on_error=1 \
  /tmp/prismel-metal-xpc-tsan/default/lib/metal/metal_xpc_conformance.app/Contents/MacOS/test_metal_xpc_client
opam exec -- dune exec --profile release tools/bench_metal_ffi.exe -- \
  --iterations 1000000 --samples 7 --profile release
```
