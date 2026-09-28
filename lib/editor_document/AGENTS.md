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
