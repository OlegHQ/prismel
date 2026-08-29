# GPU stack license and generated-source provenance

Prismel source and its handwritten OCaml/C/Objective-C++ bindings are released
under the repository MIT license. This file records the migration-specific
dependency and generated-source boundary; it is not a substitute for the final
release legal review.

| Surface | Distributed material / provenance | External obligation |
| --- | --- | --- |
| SDL3 core/image/ttf/mixer bindings | Prismel-written bindings plus OCaml-generated inventories, ABI facts and provenance hashes. Generated modules identify generator version and pinned headers. | SDL projects use the zlib license. System/shared libraries and their notices remain external dependencies; Prismel does not vendor them here. |
| Metal binding | Prismel-written safe/raw layers, typed Objective-C++ bridge and OCaml-generated inventory/value/direct-call artifacts. `lib/metal/generated_provenance.ml` records the SDK-derived input identity. | Apple SDK headers/frameworks are system build inputs obtainable with the Command Line Tools and are not redistributed by Prismel. Apple platform/tool terms apply to builders and shipped applications. The full IDE and offline shader toolchain are not required. |
| OGPU, OGPU Metal, scene execution, native runtime support, and low core | Original Prismel OCaml source under MIT. | No additional bundled third-party renderer implementation or shader binary is introduced by these libraries. |

Generated binding output is mechanical Prismel source: enum/value mappings,
typed declarations/calls, layouts, inventories and provenance. Generators fail
on stale output and run through Dune. They do not embed SDK header bodies,
vendor framework binaries, or invoke Python glue. Handwritten ownership,
lifetime, validation and callback policy remains distinguishable from generated
mechanics in the source tree.

The repository contains Houdini/Python utilities for clean-room geometry
reference work. They are neither installed GPU code nor inputs to SDL3/Metal
generation. Final Phase 5 evidence must still inventory every installed native
artifact, copied asset, offline shader, license notice and generator version on
the release commit.

`runtime_next_license_manifest.json` is the machine-readable native-runtime inventory.
Its Dune gate checks complete classifications, the MIT/zlib license and Apple
SDK provenance boundaries, and requires an explicit non-bundled declaration
for every staged surface. Final release artifact inspection remains separate.
