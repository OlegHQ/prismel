# Private editor document boundary

This library owns the immutable editable/saved document, sketch settings,
scene object and World layer schemas, validation and presets. It is private
to the Prismel package. Keep it independent of PXUI, shell, graph presentation,
sketch_support and prismel_editor; test/dependency_gate.ml enforces the
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

`Contexts.editor` evaluates the `editor` graph into `Document.shell` (the `Editor_core.Panels`
tree, the origin of each named or looped panel, the graph a `ui/graph` names, and the scene
objects of each viewport over a non-default scene instance): a `ui/*` call is a `Struct`, so a
new panel kind is a `Flow.Workspace` op, a case in `panel_tree` and a `Panels.panel`.  Origins
come from walking the checked terms beside the values, never from string search.  An evaluation
or tree error refuses the whole document, like any other graph.

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
`=(expression)` in the row); deleting a copy rewrites the loop's collection with `take`/`drop`
(one clause, nothing else of the copy stays), else `reconcile ~whole:true` deletes the whole loop after
the `Confirming` prompt.  A declared object's text is the whole
truth: a field it does not name is the schema's default.  `:parent "label"` and `:active true` are
keywords of the kinds (not fields of the nodes).  A scene graph is authoritative for every object
kind and a world graph for the World: what it does not say is not there (an empty `(scene/merge)`
has no camera and no light, `(world/none)` no World) and the host seeds nothing.  Only a workspace
with no such graph gets the host's camera and lights, one geometry object per `sop` graph and a
World given by `?world`; such an object has no text until its first explicit edit, or its
deletion, writes the scene (or World) graph from all the derived objects (`adopt`);
`~adopt:false` (a camera following the viewport) leaves such edits to the host.  Keep new derived
edits on this path: never write a second write-back.
