type object_ref={id:int;device:int;live:bool}
type status=Created|Enqueued|Committed|Complete
type t={device:int;status:status;retained:object_ref list;argument_encoder:object_ref option;capture_active:bool}
val create:device:int->t
val set_argument_encoder:t->object_ref->(t,string)result
val enqueue:t->(t,string)result
val commit:t->(t,string)result
val complete:t->(t,string)result
