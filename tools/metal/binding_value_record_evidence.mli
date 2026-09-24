val expected_layout_digest : string
val is_bound_identifier : string -> bool

val public_marker : Binding_value_record_plan.record -> string
val test_marker : Binding_value_record_plan.record -> string

val bound_ids
  :  inventory:Yojson.Safe.t
  -> public_interface:string
  -> test_source:string
  -> string list
(** Returns the exact 135-ID classification shard only after the pinned layout
    digest and every generated public/test marker have been verified. *)
