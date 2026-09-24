# Low staging compatibility

`Prismel_low_core` owns native immediate-mode recording primitives for color,
clip state, primitives, images, text, rotated diagnostic text, window facts and
window mutations. Calls record immutable `Scene_command.Render_ir` commands and the
window delegates to typed runtime-next authority.

Persistent windows retain a bounded execution-side snapshot cache. Images are
registered by stable image identity; explicit text and canvas snapshots use a
positive caller-owned resource id. Registration is borrowed: the application
still destroys its resources after the window/session stops.

The future reviewed break allowlist remains deliberately narrow:

- `Graphics.get_renderer` is removed: no raw renderer exists.
- `Window.get_window`, `Window.get_renderer`, `Window.get_window_flags`,
  `Window.get_renderer_flags`, and `Window.with_gpu_context` are removed:
  native handles, raw flags, and graphics contexts do not cross this boundary.
- Public record fields containing SDL window/renderer/context handles become an
  opaque `Window.t`.

This staging library does not change the existing `Prismel.Low` API or select
it by default.
