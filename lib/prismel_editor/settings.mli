(** Sketch-owned settings kept in the editor document: a typed
    [Editor_core.Param] record, stored type-erased so the document stays one
    immutable value. The inspector shows them while no node is selected;
    edits are undoable, saved in presets, and passed to [prepare]. *)

type t

val none : t
val make : 'record Editor_core.Param.schema -> 'record -> t

val get : 'record Editor_core.Param.schema -> t -> 'record
(** The stored record read through [schema], matching fields by name.
    Raises [Invalid_argument] when [schema] does not describe it. *)

val fields : t -> Editor_core.Param.field_view list
val apply : t -> (string * Editor_core.Param.value) list ->
  (t * Editor_core.Param.effects, string) result
