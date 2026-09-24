# Classic render resource conformance

The remaining owned-resource integration plan is frozen by
`Binding_render_encoder_resource_plan` at 19 `MTLRenderCommandEncoder`
declarations. Promotion remains forbidden until the adapter is connected to
the shared `Metal` handle graph and the following native lanes are Dune tests.

| Group | IDs | Native lane | Required safe evidence |
|---|---:|---|---|
| Fence/barriers | 5 | `lib/metal/test_metal_render_encoder_sync_native.mm` | owned Fence, same-device checks, stage-mask rejection, completion retention |
| Depth/stencil store | 4 | `lib/metal/test_metal_render_encoder_store_native.mm` | attachment ownership/presence, MSAA action validation, post-end rejection |
| Heap/resource residency | 8 | `lib/metal/test_metal_render_encoder_residency_native.mm` | owned Heap/resource lists, duplicate/same-device/usage/stage checks, completion retention |
| Indirect commands | 2 | `lib/metal/test_metal_render_encoder_icb_native.mm` | owned ICB/range buffer, pipeline support, checked ranges/alignment, completion retention |

All four native programs compile and execute on the Apple7/M1 qualification
machine. The ICB lane encodes an actual indirect draw and checks the resulting
pixel; it does not use an empty or uninitialized indirect command. The OCaml
adapter mock verifies that destruction is rejected while any command retains a
resource and succeeds only after completion releases that reference.

The five deprecated selectors (`textureBarrier`, unstaged `useHeap(s)`, and
unstaged `useResource(s)`) are compatibility aliases only. The safe API names
the modern barrier and stage-aware residency operations; aliases may be marked
bound only when they reach those same checked implementations.
