type object_ref={id:int;device:int;live:bool}
type graph={device:int;archives:object_ref list;functions:object_ref list;fences:object_ref list;indirect_buffers:object_ref list}
val validate:graph->(unit,string)result
val retained:graph->(object_ref list,string)result
