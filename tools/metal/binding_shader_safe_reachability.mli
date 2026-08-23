type status = Promotable | Blocked of string
type item = { id:string; public_operation:string; required_test:string; status:status }
val promotable_ids : string list
val items : item list
val blocked : item list
val validate : unit -> unit
