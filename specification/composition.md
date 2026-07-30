# Rendering composition

## Paths

`Path.t` is immutable geometry built with pipeline-friendly `move_to`,
`line_to`, quadratic and cubic curves, and `close`. Each `move_to` starts a
separate contour. `Scene.path` supplies fill, stroke, curve detail, and an
explicit `Path.Even_odd` (default) or `Path.Non_zero` fill rule. Curves are
flattened only at the raster boundary, so paths remain reusable data.

Fills use a contour-aware scanline rasterizer after applying the current
transform. This supports concave geometry and transparent holes without
painting a fake background shape. Strokes are emitted per contour and never
bridge separate subpaths.

## Scoped clipping

`Scene.clip ~at ~w ~h children` is a scene node. Its rectangle is transformed
to an axis-aligned device-space bound, intersected with any outer clip, and
restored after the children render. This gives nested clipping without leaking
renderer state into later scene nodes.

## Offscreen canvases

`Canvas.t` owns a 32-bit RGBA SDL surface and software renderer. It supports:

- rendering any `Scene.t`;
- reading one pixel or a row-major immutable pixel copy;
- setting or mapping pixels;
- alpha-masking one same-sized canvas with another;
- uploading a snapshot as an `Image.t`;
- copying the current window framebuffer;
- saving the canvas or framebuffer as PNG.

The CPU-backed design is deliberate: it works without OpenGL or a GPU, has
predictable pixel access, and exercises the same implementation in headless CI.
GPU render targets can be introduced later as a separate performance strategy
without weakening this contract.

Canvas dimensions are explicit pixels belonging to that offscreen surface.
They are not implicitly multiplied by the display scale. A scene rendered into
a `256 × 256` canvas therefore produces a `256 × 256` image in visible and
headless execution.

Screen capture is the native-pixel boundary. `Canvas.capture` queries the
active renderer output size, allocates exactly that many RGBA pixels, and reads
the complete framebuffer. `Canvas.save_screen_png` preserves those dimensions.
Consequently, a logical `800 × 600` window with a `(2., 2.)` pixel scale saves
a `1600 × 1200` PNG. Code that needs the current relationship can compare
`Frame.size` with `Frame.drawable_size`.

An alpha mask is explicit and composable:

```ocaml
Canvas.render source source_scene;
Canvas.render mask Scene.[
  clear Color.transparent;
  circle ~at:(128, 128) ~radius:96 ~fill:Color.white ();
];
Canvas.apply_mask ~source ~mask
```

Only mask alpha is used, so colored masks behave predictably.

Canvas and image resources are explicitly owned. `Sketch.run_state` provides
`on_stop`, which runs while SDL is still active:

```ocaml
let stop model =
  Image.destroy model.texture;
  Canvas.destroy model.canvas
```

## Effect boundaries

- `Path` construction and `Scene` construction are pure.
- `Canvas.render`, pixel mutation, uploads, capture, and export are explicit
  effects and initial-domain-only.
- Scene geometry remains in logical coordinates for the window renderer;
  capture alone exposes its native backing pixels.
- `Canvas.pixels` returns a copy; it never exposes SDL-owned memory.
- `Canvas.to_image` returns a new owned texture on every call.
- Capture and export return `result` with backend error messages.

This keeps the common view pure while still making deliberate framebuffer work
available when a sketch needs it.
