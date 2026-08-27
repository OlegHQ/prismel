# Low staging compatibility

`Prismel_next_low` preserves the immediate-mode names for color, transform and
clip state, primitives, images, text, rotated diagnostic text, window facts and
window mutations. Calls record immutable `Raster2.Render_ir` commands and the
window delegates to typed runtime-next authority.

The future reviewed break allowlist remains deliberately narrow:

- `Graphics.get_renderer` is removed: no raw renderer exists.
- `Window.get_window`, `Window.get_renderer`, `Window.get_window_flags`,
  `Window.get_renderer_flags`, and `Window.with_gpu_context` are removed:
  native handles, raw flags, and graphics contexts do not cross this boundary.
- Public record fields containing SDL window/renderer/context handles become an
  opaque `Window.t`.

This staging library does not change the existing `Prismel.Low` API or select
it by default.
