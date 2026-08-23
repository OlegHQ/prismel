(** Audited non-property handle-backed Metal direct calls.

    These entries describe private raw/native generation only.  Their
    behavioral classification does not make them part of the checked public
    API. *)

val entries : Binding_direct_spec.method_entry list
val inventory_ids : string list

val expected_owner_count : int
val expected_method_count : int
val expected_declaration_count : int
val expected_query_count : int
val expected_command_count : int
val expected_blocking_count : int
val expected_process_identity_count : int

(** Validate identifiers, selector arity, signatures, representations,
    behavior classes, availability, and exact aggregate counts. *)
val validate : unit -> unit
