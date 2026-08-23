type status = Promotable | Blocked of string
type item =
  { id : string
  ; public_operation : string
  ; required_test : string
  ; status : status
  }
val items : item list
val promotable_ids : string list
val blocked : item list
val validate : unit -> unit
