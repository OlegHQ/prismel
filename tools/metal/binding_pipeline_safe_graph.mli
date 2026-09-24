type device = int
type function_ref = { device:device; id:int }
type descriptor
type pipeline
val descriptor : device -> descriptor
val set_vertex : descriptor -> function_ref option -> (descriptor,string) result
val materialize : descriptor -> (pipeline,string) result
val release_pipeline : pipeline -> unit
val retained_count : descriptor -> int
