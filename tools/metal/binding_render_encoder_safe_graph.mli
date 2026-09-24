type resource={id:int;device:int;length:int;live:bool}
type state=Encoding|Ended|Committed
type t={device:int;state:state;retained:resource list;bound_buffers:(int*resource*int)list}
val empty:device:int->t
val bind_buffer:t->index:int->offset:int->resource->(t,string)result
val use_resources:t->resource list->(t,string)result
val validate_draw:t->vertex_start:int->vertex_count:int->instance_count:int->(unit,string)result
val finish:t->(t,string)result
