type output =
  { ml : string
  ; mli : string
  ; test_ml : string
  ; identifiers : string list
  ; family_count : int
  ; case_count : int
  }

(** Emit the safe, handle-free public value surface for every selected
    explicit and implicit enum. Scope-excluded cases are omitted. *)
val generate :
  explicit:Binding_enum_codegen.selection ->
  implicit:Binding_enum_implicit_codegen.selection ->
  output
