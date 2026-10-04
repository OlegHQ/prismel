# Private editor document boundary

This library owns the immutable editable/saved document, sketch settings,
scene object and World layer schemas, validation and presets. It is private
to the Rays package. Keep it independent of PXUI, shell, graph presentation,
sketch_support and rays_editor; test/dependency_gate.ml enforces the
transitive presentation ban. Selection, navigation, cooking and history
commit policy remain in the host. Root repository rules apply.

Levels are `Scene | Inside of int` (an object's network); compounds were deleted in Gap A.

`Workspace_doc` (source, checked, layout by path, settings) and `Layout_by_path`
are UI-free and hold the authored truth of a workspace document; `edit` applies
one `Flow_sop.Flow_edit.op` atomically and rewrites layout keys in the same
step. `Document.workspace` pairs it with its `Lower.t`; `of_workspace` rebuilds
the derived scene and networks (never edit those directly). `Preset` is the
only persisted form: one s-expression file, no version and no older reader.
`Document.dump` is a deterministic text of any document for crash reports and
tests; it is not loadable.

`Contexts` generates the scene, world and settings kinds of a workspace from the object, layer
and settings schemas and builds the document of a workspace (`of_workspace`); add a field to a
schema and it is a keyword. Do not hand-write per-kind Lisp glue there.

`Workspace_doc.editor_graph` resolves the selected named shell layout from
`Layout_by_path.editor` (`(layout (editor "name"))`), defaulting to the first
editor graph. `Contexts.editor` evaluates that graph into `Document.shell` (the `Editor_core.Panels`
tree, the origin of each named or looped panel, the graph a `ui/graph` names, and the scene
objects of each viewport over a non-default scene instance): a `ui/*` call is a `Struct`, so a
new panel kind is a `Flow.Workspace` op, a case in `panel_tree` and a `Panels.panel`.  Origins
come from walking the checked terms beside the values, never from string search.  An evaluation
or tree error refuses the whole document, like any other graph.

`Layout_by_path.panels` saves panel disclosure and in-editor floating bounds beside
the selected layout: `(panel ["studio" "network"] :collapsed false :window [500 80 620 450])`.
These keys remap with source bindings. Unbound loop copies use their tree path.

`Scene_sync` makes the text the truth of the derived scene and World.  Every edit of a derived
object (the inspector, the handles, reparent, rename, delete, hide, the render camera, the World
keys and map drags, the camera following the viewport) still mutates the document's
`Edit_graph`; `reconcile before after` then turns each difference into `Flow_edit` ops on the graph
that declares the object and lowers the new text again (`Doc.reconcile`, called by `Core` after
every frame's derived edits, by `Core.edit_node` and by the camera follow).  Where an object lives is
`Document.homes` (`Bound_at` a binding, `Inline_in` an argument of another home, `Copy` of a loop's
template, `Looped`); an inline call is unfolded into a binding first, and ids are claimed by
home before (operation, label), so a rename keeps the id.  The copies of a loop are one template
(register V4): editing a literal field (or a literal component of a computed vector) of one writes
the template, every copy changes; a field the loop computes is refused with its expression (type
`=(expression)` in the row); deleting a copy is exact at any depth (register L16): `Scene_sync.delete_loops` adds the iteration
tuple (the outermost whose objects all go) to the loop's `:skip`, or the object's place to the `:skip` of
the `scene/merge` that holds it; `Copy.index` is the running iteration index, so the other copies keep their
homes and ids.  No collection rewrite and no confirmation.  A declared object's text is the whole
truth: a field it does not name is the schema's default.  `:parent "label"` and `:active true` are
keywords of the kinds (not fields of the nodes).  A scene graph is authoritative for every object
kind and a world graph for the World: what it does not say is not there (an empty `(scene/merge)`
has no camera and no light, `(world/none)` no World) and the host seeds nothing.  Only a workspace
with no such graph gets the host's camera and lights, one geometry object per `sop` graph and a
World given by `?world`; such an object has no text until its first explicit edit, or its
deletion, writes the scene (or World) graph from all the derived objects (`adopt`);
`~adopt:false` (a camera following the viewport) leaves such edits to the host.  Keep new derived
edits on this path: never write a second write-back.

The scene graph's `scene/root` is not a node of the scene network: `Contexts.of_workspace` reads it
into `Document.root` (`Objects.Root.parameters`, the defaults for a part, over the render size an old
`scene/camera` carries) and `homes.root`; `Scene_sync.root` writes an edit to its call, or the first
edit writes a root over the graph's result (`adopt_root`).  A `scene/world (ref g)` is an object like
the others (its id and home are in `homes.objects`), its layers the world graph `g`
(`homes.world_graph`); an old file's `world/world` is read as the World and written where it is (a read-only legacy: no
checked-in sketch uses it any more, no menu offers it, and `Contexts.of_workspace` reads it unchanged).
`E_SCENE_ROOT`, `E_SCENE_WORLD` and `E_SCENE_CAMERA` are raised by `Contexts.check_scene` while
lowering, so a gesture that would cause one is refused whole.  Deleting an object removes its SOP or
world graph in the same reconciliation when no `(ref g)` or `(ui/graph "g")` reads it.
`Scene_sync.add_geometry` and `add_world` give the ops of one composition gesture.

`Document.view_worlds` lists the viewports over a scene instance whose World differs from the document's:
the node of its `scene/world` and the network of its layers (read from the instance's value, since a
viewport's scene has no term), or none when its merge holds none. They are not in the scene graph and
have no ids; `Contexts.instance_root` reads the `scene/root` of an instance the same way: its settings and
the camera object its `:camera` names (`Document.view_roots`, by viewport key, for the instances that are not
the document's own scene).  `Contexts.of_workspace` keeps `Document.scene` physically when an edit leaves its
objects as they were (`same_network`), so a root's settings or a layout edit do not recompose the views.
