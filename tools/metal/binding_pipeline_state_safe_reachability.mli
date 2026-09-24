type status = Promotable | Blocked of string

type item =
  { id : string
  ; public_operation : string
  ; required_test : string
  ; status : status
  }

val promotable_ids : string list
val item : string -> item
