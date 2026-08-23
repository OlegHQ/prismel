type resource={id:int;device:int;length:int;live:bool}
type state=Encoding|Ended|Committed
type t={device:int;state:state;buffers:(int*resource*int)list;retained:resource list}
val empty:device:int->t
val bind:t->index:int->offset:int->resource->(t,string)result
val dispatch:t->grid:int*int*int->threads:int*int*int->(unit,string)result
val finish:t->(t,string)result
