type argument = Input of int | Node of int
type node = { id:int; name:string; arguments:argument array; dependencies:int array }
type graph = { function_name:string; nodes:node array; output:int option; attributes:string array }
type owned = { token:int; device:int; destroyed:bool }
type descriptor = { device:int; functions:owned array; archives:owned array; graphs:graph array; options:int64 }
val validate_graph : argument_count:int -> function_name:string -> nodes:node array -> output:int option -> attributes:string array -> (graph,string) result
val validate_owned : device:int -> owned array -> (owned array,string) result
val create_descriptor : device:int -> functions:owned array -> archives:owned array -> graphs:graph array -> options:int64 -> (descriptor,string) result
val replace_graphs : descriptor -> graph array -> descriptor
val validate_handoff : unit -> unit
