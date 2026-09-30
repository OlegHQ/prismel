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
