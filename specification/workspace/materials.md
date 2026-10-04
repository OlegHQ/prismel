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

## Reaching and making materials in the editor

The outline (Navigator) groups graphs by `:context`: Scene, Geometry, Materials, World, Layout
(then Settings and Values when present); reusable functions and macros keep their own section. A
material row shows its evaluated colour as a chip (a vector or hex text; white when unset) and
`×N`, the number of graphs reading it. A material or SOP graph nothing reads is dimmed and says
`unused`. The open graph lists what it reads and what reads it as click targets. Typing in the
search field filters across every group. F2 over a graph row renames it and every `(ref ...)` to
it in one `Flow_edit.Rename_graph` (one undo entry; a taken name is refused). Delete over a row
is `Remove_graph`, refused naming the readers while a `(ref ...)` still reads it.

Making: `Space a` at the scene offers **Material** (a new `material` graph, opened; one
"New material" entry); in a SOP graph it offers **Material of...**, a `sop/material` node after
the selection with `:material (ref name)` filled. The inspector shows `:material` as a choice of
the material graphs plus "new material" (the graph and the reference, one entry).

Following (one key for every reference, one key back):

| From | Gesture | Lands in |
|---|---|---|
| a selected node holding `(ref name)` (a `sop/material`: its `:material`) | `i`, or double-click its body | that graph |
| a selected node holding `(ref name)` | `I` | the graph in a floating window, `(ui/floating (ui/graph "name"))` |
| a surface in the viewport | Alt-click | the material graph of that primitive (`shop_materialpath`: the graph of that name, else the one whose `:name` it is) |
| anywhere | `Space j` | a filter over every graph, grouped like the outline; no outline panel needed |
| an outline row, a pick, a new material | click | the graph |
| any of the above | `u` | where you were |

Every follow pushes the level and shown graph onto a back stack (32 deep); `u` pops it, and with
an empty stack goes up to the scene as before. The graph header shows the last three steps of
the route, `scene > shards > cobalt`. Not done: Command-click on a `(ref ...)` in the text pane,
dropping an outline row onto a node or a surface, and colour chips inside the inspector choice.

`sketches/shattered_studio/sketch.plisp` uses 12 noisy sheet cutters for a
Boolean fracture, with piece-seeded groups and four referenced surfaces.
`test/test_materials.ml` covers references, group preservation, render batches,
invalid input, cancellation, and exact domain-count equality, then the editor: outline groups,
chips and use counts, `Space j`, follow and back, double-click, `I`, Alt-click, rename with its
refs, refusal to delete a read material, and `Space a` Material / Material of....
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
