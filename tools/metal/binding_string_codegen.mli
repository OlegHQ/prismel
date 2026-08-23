(** Deterministic raw/native emission for receiver-qualified NSString entries. *)

val qualified_entries : unit -> Binding_string_spec.entry list
val ocaml_name : Binding_string_spec.entry -> [ `Getter | `Setter ] -> string
val c_symbol : Binding_string_spec.entry -> [ `Getter | `Setter ] -> string
val render_raw_body : Binding_string_spec.entry list -> string
val render_raw_ml : Binding_string_spec.entry list -> string
val render_raw_mli : Binding_string_spec.entry list -> string
val render_native : Binding_string_spec.entry list -> string
