type object_ref={id:int;device:int;live:bool}
type node={id:int;name:string;function_:object_ref;arguments:int list;dependencies:int list}
type graph={device:int;nodes:node list;output:int;archives:object_ref list;functions:object_ref list}
val validate:graph->(unit,string)result
