(** Production-scale private raw NSString property shard. *)

val entries : Binding_string_spec.entry list
val expected_property_count : int
val expected_getter_count : int
val expected_setter_count : int
val expected_inventory_id_count : int

