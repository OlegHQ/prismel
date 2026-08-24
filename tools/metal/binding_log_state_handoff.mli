type lane = Mechanical | Callback | Metadata
type item = { id : string; lane : lane; operation : string; tests : string list }
val make : kind:string -> string -> item
val validate : item list -> unit
