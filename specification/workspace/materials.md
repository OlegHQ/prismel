# Workspace materials

A `material` graph returns a typed surface value. A SOP graph assigns that
value to all primitives or to a named primitive group:

```lisp
(graph cobalt :context material
  (material/standard :name "cobalt" :color "#2670f5" :roughness 0.3))

(graph sculpture :context sop
  (sop/material (sop/box) :material (ref cobalt)))
```

`material/standard` has `:name` (text), `:color` (RGB vector or hex color),
`:roughness` (0–1), and `:emission` (RGB vector or hex color). Defaults are
an empty name, white, 0.4, and black. Material graphs support the ordinary
value expressions and typed inputs. Their fields are static in the editor;
time-dependent material graphs are refused by its existing context check.

The registered `sop/material` node has one geometry input, `:group`, and
`:material`. A material reference supplies its surface fields. The node also
accepts inline `:color`, `:roughness`, and `:emission`; a text `:material`
names such an inline surface rather than performing a string lookup. Group
assignment preserves unselected primitive surfaces and input geometry. A
missing primitive group or malformed material attribute is a typed error.

The cook stores primitive `shop_materialpath` (text), `material_color`
(float4), `material_roughness` (float), and `material_emission` (float4).
Lowering carries material values into the assignment's numeric parameters;
there is no mutable material registry and no renderer dependency in Flow or
the geometry libraries. Editing a referenced graph changes the cook key.

The generic `.plisp` host prepares `Sketch_support.Surface`. It groups
triangles by surface properties, shares their mesh planes, and applies the
same surfaces in raster and path-traced modes. Raster uses
Blinn–Phong shininess derived from roughness; tracing maps it back to
roughness. Existing `Cd` remains a vertex tint. Explosion moves each whole
piece before the material split, so face groups cannot tear a shard apart.
Packed instance transforms are preserved. Unsupported curve materials return
an error; ordinary curve and point previews remain supported.

`sketches/shattered_studio/sketch.plisp` uses 12 noisy sheet cutters for a
Boolean fracture, with piece-seeded groups and four referenced surfaces.
`test/test_materials.ml` covers references, group preservation, render batches,
invalid input, cancellation, and exact domain-count equality.
`test/test_shattered_studio.ml` checks this particular fracture's closed
manifold pieces, volume conservation, material batches, and domain equality.

An authored scene can be exported on the native Metal host with:

```sh
dune exec tools/render_workspace.exe -- sketches/shattered_studio/sketch.plisp /tmp/shattered-studio.png
```

Optional trailing arguments override sample count and square pixel size.
The tool uses the scene's camera (including depth of field), light objects,
World, and object transforms, stops after the requested samples, and writes
a PNG through the existing layerless native Metal target. It does not need
a display; a missing Metal device is a startup error.
