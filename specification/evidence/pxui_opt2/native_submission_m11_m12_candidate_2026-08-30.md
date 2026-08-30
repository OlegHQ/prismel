# Native submission and hidden-work candidate, 2026-08-30

This candidate continues the frozen `OPT2.md` migration. It does not claim
M11, M12, or final qualification complete.

## Changes

- Production mixed-layer rendering no longer materializes the compatibility
  aggregate `Render_ir` before staging its native layers.
- The Metal backend checks the bounded classic submission cache before native
  draw conversion and memoizes bounded retained-plan structural identities.
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

## Focused verification

- `lib/ogpu_metal/test_ogpu_metal_backend.exe`: transfer/compute/render 1000,
  retained-plan queues/surface, zero native handle delta.
- `test/test_sketch_ui.exe`: passed.
