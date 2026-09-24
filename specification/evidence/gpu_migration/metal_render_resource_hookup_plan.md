# Exact-19 classic render resource hookup plan

This plan connects commit `e3b8fda` to the shared Metal handle graph without
changing the 19-ID closure frozen by `c7304d2`. Apply it only after the current
shared acceleration integration is committed. Do not classify an ID before its
safe operation and corresponding rejection/ownership lane pass.

## `lib/metal/metal_bridge.mm`

- Append `Fence` to `Handle_kind`; do not renumber existing kinds.
- Add `device_create_fence`, returning an owned `id<MTLFence>` handle or a
  native error. Fence labels are optional and must be copied as valid UTF-8.
- Add direct typed render calls (no selector strings or `objc_msgSend`):
  `memoryBarrierWithScope:afterStages:beforeStages:`,
  `memoryBarrierWithResources:count:afterStages:beforeStages:`,
  `updateFence:afterStages:`, `waitForFence:beforeStages:`, depth/stencil store
  action and option setters, all four stage-aware residency calls, and both ICB
  execution calls.
- Implement the five deprecated selectors only as safe-layer aliases to the
  modern typed implementations; do not add separate public unsafe entry points.
- Extend render-pass creation with nullable owned depth and stencil textures.
  Validate pixel format, dimensions, sample count, and Render_target usage
  before constructing `MTLRenderPassDescriptor`. A combined depth/stencil
  texture may occupy both attachments without double ownership.
- Convert OCaml arrays to bounded native vectors before calls. Reject empty,
  duplicate, overlong, negative, overflowed, or misaligned ranges before Metal.

## `lib/metal/metal_raw.ml` and `lib/metal/metal_raw.mli`

Add matching typed externals named:

- `device_create_fence`;
- `render_encoder_memory_barrier_scope` and
  `render_encoder_memory_barrier_resources`;
- `render_encoder_update_fence` and `render_encoder_wait_fence`;
- `render_encoder_set_depth_store_action/options` and
  `render_encoder_set_stencil_store_action/options`;
- `render_encoder_use_heap(s)` and `render_encoder_use_resource(s)`, accepting
  explicit stage/usage bitmasks after safe validation;
- `render_encoder_execute_icb_range` and
  `render_encoder_execute_icb_indirect_range`.

Every external maps to a statically typed Objective-C++ body above. The raw
surface remains internal.

## `lib/metal/metal.ml`

- Add owned `fence` with `raw`, `lifetime`, and `device`; expose it through a
  handwritten `Fence` module. Creation attaches the device. Destruction uses
  `destroy_child`, so command retention produces `Parent_has_dependents`.
- Extend `render_encoder` with `depth : texture option` and
  `stencil : texture option`. `Render_encoder.create` validates and retains
  each distinct attachment on its command buffer before native creation;
  unwind every earlier attachment if a later validation/native call fails.
- Extend `command_resource` with `Command_buffer_fence` and
  `Command_buffer_heap`. Resource/ICB/range-buffer reuse existing variants.
  Add exhaustive lifetime/heap accounting cases and identity-deduplicating
  retain helpers. Completion/error/destroy release remains centralized in
  `release_command_resources`.
- Add typed render-stage, barrier-scope, resource-usage, and store-option values.
  Encode only after rejecting zero/unknown bits.
- Add `memory_barrier`, `memory_barrier_resources`, `update_fence`,
  `wait_for_fence`, depth/stencil store action/options, `use_heap(s)`,
  `use_resource(s)`, `execute_indirect_commands`, and
  `execute_indirect_commands_indirect_range`.
- Validation order is: initial domain, encoder open, resource live, same device,
  capability/attachment/pipeline support, duplicate/range/alignment checks,
  native call, then retain. Rejections must not allocate handles or mutate the
  retention graph.
- ICB execution requires a bound render pipeline whose
  internal `support_indirect_commands` flag (materialized from the public
  `support_indirect_command_buffers` pipeline option) is true. Direct ranges satisfy
  `location >= 0`, `length > 0`, and `location + length <= max_command_count`
  without overflow. Indirect range-buffer offsets are nonnegative, 8-byte
  aligned, and leave room for `MTLIndirectCommandBufferExecutionRange`.

## `lib/metal/metal.mli`

- Export abstract owned `Fence` with `create`, `device`, `destroyed`, and
  `destroy` only.
- Extend `Render_encoder.create` with optional `depth` and `stencil` attachments.
- Export only the typed safe operations listed above. Deprecated aliases retain
  modern safe names and semantics; no raw handle or catch-all selector API.

## Tests and Dune

- Add these existing native files as Dune tests:
  `test_metal_render_encoder_sync_native.mm`,
  `test_metal_render_encoder_store_native.mm`,
  `test_metal_render_encoder_residency_native.mm`, and
  `test_metal_render_encoder_icb_native.mm`.
- Extend `test_metal_render_encoder_safe.ml` with wrong-device, destroyed,
  duplicate, missing-attachment, bad stage/usage, bad range/alignment,
  pipeline-without-ICB-support, call-after-end, and no-handle-delta lanes.
- Assert Fence/Heap/resources/ICB/range buffer cannot be destroyed before
  command completion, then can be destroyed after completion. Test native-error
  unwind with no retained dependents.
- Add the resource plan, adapter, and tests to `tools/metal/dune` and generator
  provenance sources. The plan test must remain exactly 19 IDs and five aliases.

## Classification and gates

After every safe lane above passes, append exactly the 19 IDs from
`Binding_render_encoder_resource_plan.entries` to
`Binding_render_encoder_promotion`, regenerate
`lib/metal/generated_api_inventory.json`, and update
`metal_progress_rate.md` in the same integration sequence. Expected movement is
19 `unreviewed` to 19 `bound`; every other count is unchanged.

Run, in order:

```text
opam exec -- dune build lib/metal/metal.cma
opam exec -- dune exec lib/metal/test_metal_render_encoder_safe.exe
opam exec -- dune runtest tools/metal --force
opam exec -- dune runtest lib/metal --force
opam exec -- dune exec lib/metal/test_metal_stress.exe
opam exec -- dune exec tools/metal/generate_inventory.exe -- --root . --check
git diff --exit-code -- lib/metal/generated_api_inventory.json
```

The known struct-plan closure changes only if newly promoted tile/struct IDs
leave its unreviewed candidate set; adjust its frozen expected count from actual
inventory evidence, never to silence an unexplained mismatch.
