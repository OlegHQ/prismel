type owned
type fence = owned
type heap = owned
type resource = owned
type icb
type store_action = Dont_care | Store | Resolve | Store_and_resolve
type backend = { update_fence:int64->int64->int->unit; wait_fence:int64->int64->int->unit;
 depth_store:int64->int->unit; stencil_store:int64->int->unit;
 use_heaps:int64->int64 array->int->unit; use_resources:int64->int64 array->int->int->unit;
 execute_icb:int64->int64->int->int->unit; execute_icb_indirect:int64->int64->int64->int64->unit }
type encoder
val owned : token:int64 -> device:int64 -> owned
val icb : token:int64 -> device:int64 -> max_commands:int -> icb
val encoder : token:int64 -> device:int64 -> backend:backend -> sample_count:int ->
  depth:bool -> stencil:bool -> pipeline_supports_icb:bool -> encoder
val destroy : owned -> (unit,string) result
val update_fence : encoder -> fence -> after_stages:int -> (unit,string) result
val wait_fence : encoder -> fence -> before_stages:int -> (unit,string) result
val set_depth_store : encoder -> store_action -> (unit,string) result
val set_stencil_store : encoder -> store_action -> (unit,string) result
val use_heaps : encoder -> heap list -> stages:int -> (unit,string) result
val use_resources : encoder -> resource list -> usage:int -> stages:int -> (unit,string) result
val execute_icb : encoder -> icb -> location:int -> length:int -> (unit,string) result
val execute_icb_indirect : encoder -> icb -> resource -> offset:int64 -> (unit,string) result
val end_encoding : encoder -> (unit,string) result
val complete : encoder -> unit
