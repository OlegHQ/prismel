type resource={id:int;device:int;length:int;live:bool}
type encoder_state=Encoding|Ended
type t={device:int;state:encoder_state;retained:resource list;event_value:int64;capturing:bool}
val empty:device:int->t
val copy:t->source:resource->source_offset:int->destination:resource->destination_offset:int->size:int->(t,string)result
val signal:t->int64->(t,string)result
val begin_capture:t->(t,string)result
val end_capture:t->(t,string)result
