# Layer, drawable, and render-pass safety audit

Scope: the current presentation bridge and safe API, excluding callback-token
cleanup (audited separately in `PRESENTATION_CALLBACK_AUDIT.md`). No inventory
entry is promoted by this evidence.

## Required fixes

1. **Layer flag tuple is out of bounds.** `metal_bridge.mm` reads
   `Field(rflags, 5)` for `wantsExtendedDynamicRangeContent`, but both raw
   declarations and both safe call sites pass a five-element tuple. Valid
   indices are 0 through 4. This is an unchecked read of adjacent OCaml heap
   data. Add the EDR boolean to the safe config and raw tuple type/call sites in
   the same atomic change, or remove the native field access until that API is
   integrated. Add a tuple-arity conformance check; never land one side first.

2. **Drawable texture metadata is derived from mutable layer state.** After
   `nextDrawable`, `Drawable.texture` constructs its safe descriptor using the
   layer's current cached width, height, and format. Reconfiguring the layer
   between acquisition and texture lookup changes that cache, but does not
   retroactively change the acquired drawable texture. Query the actual native
   texture width, height, pixel format, array length, sample count, storage mode,
   and usage through a typed native call, or capture proven native metadata at
   acquisition. The safe texture descriptor must describe the texture object,
   not the layer's later desired configuration.

3. **Layer pixel-format validation is incomplete and split across layers.** The
   public config accepts every `Texture.format`, while native code permits only
   numeric 80, 81, and 115. The safe API should reject unsupported layer formats
   as `Invalid_argument` before allocating/configuring a layer, and the native
   bridge should retain a defensive check. If EDR is public, explicitly qualify
   the SDK-supported XR formats (`Bgra10_xr` and `Bgra10_xr_srgb`) with their
   availability rather than silently rejecting them as a native error.

4. **Availability checks are missing.** `maximumDrawableCount`,
   `allowsNextDrawableTimeout`, `displaySyncEnabled`,
   `presentsWithTransaction`, EDR, timed presentation, and minimum-duration
   presentation need the pinned deployment-target guards specified by the
   binding plan. Direct property/message use must not become an unguarded call
   on an older supported OS.

5. **Render-pass dimensions are detached from attachments.** The object only
   sets render-target dimensions/sample count; it owns no color/depth/stencil
   attachment graph and is not accepted by the encoder constructor. Keep these
   declarations unreviewed unless the type is intentionally documented as the
   attachment-free default state. Full descriptor coverage requires borrowed
   attachment ownership, same-device/live checks when consumed, resolve/store
   validation, and retaining attachments through command completion.

## Verified behavior

- `nextDrawable == nil` is represented as typed timeout/unavailability rather
  than a fabricated handle.
- Layer retains its device; drawable retains its layer; a materialized texture
  retains its drawable. Parent destruction is rejected while dependents live.
- Presentation validates command-buffer/drawable device identity and retains
  the drawable through terminal command-buffer status.
- Duplicate presentation is rejected before a second native call, and the
  one-shot flag is initial-domain confined.
- Native allocation paths root OCaml intermediate values with `CAMLlocal` and
  exception paths return structured native errors. The six-versus-five tuple
  mismatch above is the exception and is memory-unsafe.
- Releasing the borrowed texture before the drawable, the drawable before the
  layer, and the layer before the device matches the safe dependency graph.

`test_binding_presentation_snapshot_model.ml` exercises 10,000 resize/format
changes after acquisition, borrowed-texture release ordering, and one-shot
presentation. It specifies that drawable metadata is an acquisition/object
snapshot and must never follow later layer configuration.
