# Private editor document boundary

This library owns the immutable editable/saved document, sketch settings,
scene object and World layer schemas, validation and presets. It is private
to the Prismel package. Keep it independent of PXUI, shell, graph presentation,
sketch_support and prismel_editor; test/dependency_gate.ml enforces the
transitive presentation ban. Selection, navigation, cooking and history
commit policy remain in the host. Root repository rules apply.

Compound levels are view-state instance paths. `Document.network` resolves a
path to its shared definition; `Document.with_network` edits that definition
once for every instance, and `resolve_level` falls back to a surviving parent
after undo or load.
Ungroup prunes compiled-id paths that no longer name an instance and carries
the definition's canvas layout onto fresh parent ids.
Value-only compound instances do not require a geometry display; display
validation accepts only nodes with geometry output.
Compound interface defaults use `Flow_sop.Port.literal`; a Vec3 default holds
its three components and presets store the triple under `vec3`.
Geometry interface unexport refuses connected body or instance wires and the
displayed output; removing an idle port rebinds every shared instance by slot
name so remaining wires keep their destinations.
Make unique copies a definition with fresh internal ids, rebinds its interface
factories, and retargets only the selected instance; other instances retain
the original definition.
Renaming a geometry interface port updates the shared definition and every
referencing instance, including named wires and path-keyed canvas layout.
Reordering geometry ports preserves each slot's source by name in every
instance and in the definition's Outputs marker.

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
