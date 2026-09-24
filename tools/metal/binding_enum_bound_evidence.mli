(** Fail-closed evidence boundary for promoting the generated Metal enum batch.

    The predicates in this module deliberately describe only the two reviewed
    enum plans.  They are suitable for classification only after
    {!validate_inventory} and the generated public/exhaustive-test witnesses
    have passed. *)

val explicit_bound_count : int
val implicit_bound_count : int
val bound_count : int
val excluded_count : int
val case_count : int
val selected_case_count : int

val identifier_sha256 : string
val availability_sha256 : string

val family_names : string list
val excluded_identifiers : string list

val is_selected_identifier : string -> bool
val is_scope_excluded_identifier : string -> bool
val is_bound_identifier : string -> bool

val source_paths : string list
