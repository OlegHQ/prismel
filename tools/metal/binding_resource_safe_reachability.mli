type gap =
  | Missing_public_operation
  | Missing_constructor
  | Missing_parent_metadata
  | Missing_completion_retention
  | Missing_capability_test

type status = Promotable | Blocked of gap

type item =
  { id : string
  ; public_operation : string
  ; required_test : string
  ; status : status
  }

val items : item list
val pool_core : string list
val promotable_ids : string list
val blocked : item list
val find : string -> item
val validate : unit -> unit
