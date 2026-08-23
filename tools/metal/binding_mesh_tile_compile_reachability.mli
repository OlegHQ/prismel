type status = Pending_safe_native | Blocked
type item =
  { id : string
  ; safe_operation : string
  ; safe_fixture : string
  ; native_fixture : string
  ; status : status
  }
val items : item list
val pending_ids : string list
val validate : unit -> unit
