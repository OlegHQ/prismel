# MTLRenderCommandEncoder M1 evidence map

All 131 method selectors compile as direct typed Objective-C calls in
`test_binding_render_encoder_codegen`. The safe specification partitions the
133 owner declarations into nine exhaustive groups: draw/dispatch 16, stage
binding 71, fixed state 20, store action 6, synchronization 5, residency 8,
indirect commands 2, counter sampling 1, and tile queries 4.

The checked native M1 gate executes conventional pipeline binding, vertex and
fragment byte and buffer bindings, viewport, scissor, cull, winding, fill,
blend color, depth bias, stencil reference, instanced triangle draw, encoder
end, command completion, deterministic pixel readback, and resource retention
until completion. Mesh/object/tile, tessellation, ray-table, counter, ICB,
fence, residency and macOS 26-only paths remain capability-gated integration
work; compile-only evidence is not sufficient to promote them.

Five SDK-deprecated selectors remain in scope but are exposed only as safe
aliases to their staged/barrier replacements: `textureBarrier`, `useHeap:`,
`useHeaps:count:`, `useResource:usage:`, and `useResources:count:usage:`.
