# Graphics and scene drawing

New code should build immutable `Scene.t` values and let `Sketch` present them.
`Low.Graphics` remains an immediate-mode compatibility surface for older code,
but both entry points lower into the same SDL3-windowed OGPU/Metal renderer.
The native Metal renderer is the only execution path.

## Drawing vocabulary

The 2D surface includes clear, points, lines and thick lines, rectangles and
rounded rectangles, circles and ellipses, triangles and polygons, polylines,
arcs, pies, Bézier curves, images, loaded-font text, and fixed bitmap diagnostic
text. High-level scene constructors take explicit colors and return pure nodes;
the compatibility functions may use the current color when `?color` is absent.

Later nodes draw over earlier nodes within a scene or immediate frame. Scoped
`Scene.group`, `translate`, `rotate`, `scale`, `clip`, and `blend` preserve
nesting without leaking state to following nodes. Path contour boundaries and
even-odd/non-zero fill rules survive native command lowering.

## Coordinates and density

Coordinates are integer logical points with `(0, 0)` at the top-left, positive X
to the right, and positive Y downward. `Frame.width`, `Frame.height`, scene
geometry, input positions, and PXUI layout share that coordinate system.

`Frame.drawable_size` exposes native Metal drawable pixels and
`Frame.pixel_scale` gives backing pixels per logical point. Application code
must not multiply ordinary drawing or pointer coordinates by this scale. The
runtime converts a logical viewport to drawable edges once at the native
boundary. Capture and export are the explicit backing-pixel operations.

## Images and text

`Scene.image` and the `Low.Graphics.draw_image*` family reference owned
`Image.t` values. The renderer snapshots identity and generation, uploads only
changed content, validates resource lifetime/device identity, and retains the
sampled texture until command completion.

`Scene.text ?size` resolves an installed platform UI font, with
`PRISMEL_UI_FONT` as a portable override. The size is expressed in logical
points; glyphs rasterize at native density and draw at logical dimensions.
Renderer-local text textures use a bounded 256-entry LRU. Empty strings are
safe no-ops.

`Scene.debug_text` and `Low.Graphics.draw_gfx_text` use Prismel's independent
fixed 8×8 diagnostic bitmap. They do not load a system font or depend on a
third-party primitive-font table.

## Native effect boundary

Scene construction is pure. `Scene.render`, `Sketch`, and `Low.App` are effect
boundaries that stage checked render commands, resolve resources, encode Metal
work through OGPU, and present one SDL3 Metal drawable. Native Metal or drawable
unavailability is a typed startup/runtime error; it never selects another
renderer.

Window, event, resource, and presentation operations stay on the initial OCaml
domain. Pure geometry preparation may use `Parallel`, but it joins before
native command recording. Draw ordering and resource lifetime remain
deterministic for a fixed scene and input stream.
