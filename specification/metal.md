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

## Implemented vertical slice

The initial safe slice covers device enumeration and capabilities; shared,
managed, and private buffers; CPU range transfer; labels; runtime MSL library
compilation with full `NSError` diagnostics; function lookup; compute-pipeline
creation and limits; command queues and buffers; compute encoding and resource
binding; checked thread dispatch; submission; blocking completion; and command
status/errors.

`test_metal.exe` runs a real M1 compute kernel, wrong-domain and invalid-state
cases, shader diagnostics, bounds and overflow checks, parent ownership,
idempotent destruction, stale access, and GC-finalizer release. The separate
ownership stress performs 5,000 warm-up cycles and 100,000 measured buffer
create/destroy cycles, requires exact created/released balance, zero pending or
dropped releases, stable live-handle count, and bounded settled RSS growth.

The currently selected Command Line Tools include SDK 26.5 headers but not the
`metal` and `metallib` executables. Runtime source compilation is therefore
covered locally; offline `.metallib`, Xcode validation, capture, and archive
qualification remain explicit Phase 2 work requiring the pinned full Xcode
toolchain. This limitation does not weaken or skip any M1-M10 completion gate.

Run the current binding checks with:

```sh
opam exec -- dune runtest lib/metal --force
opam exec -- dune build @all @doc
```
