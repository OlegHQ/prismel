(** Aggregate plan for the first production-scale handle-backed callable
    generation batch. *)

val methods : Binding_direct_spec.method_entry list
val properties : Binding_direct_spec.property_entry list
val inventory_ids : string list
val safe_device_properties : Binding_direct_spec.property_entry list
val safe_device_identifiers : string list
val is_safe_device_identifier : string -> bool
val capability13_identifiers : string list
val expected_capability13_identifiers : string list
val is_capability13_identifier : string -> bool

val expected_method_count : int
val expected_property_count : int
val expected_declaration_count : int
val expected_owner_count : int

(** Every direct-call schema, shard, and aggregator source covered by binding
    plan provenance. *)
val source_paths : string list

val validate : unit -> unit
