type object_ref={id:int;device:int;live:bool}
type state=Initial|Recording|Ended|Committed|Complete
type t={device:int;state:state;retained:object_ref list;argument_tables:object_ref list}
val create:device:int->t
val begin_recording:t->(t,string)result
val retain:t->object_ref list->(t,string)result
val end_recording:t->(t,string)result
val commit:t->(t,string)result
