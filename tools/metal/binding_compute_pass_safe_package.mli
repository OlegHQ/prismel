type dispatch=Serial|Concurrent
type capability={concurrent_dispatch:bool;max_attachments:int}
type sample_buffer={token:int;device:int;sample_count:int;destroyed:bool}
type attachment={buffer:sample_buffer option;start_index:int;end_index:int}
type descriptor={device:int;dispatch:dispatch;attachments:attachment option array}
val dont_sample:int
val validate_dispatch:capability->dispatch->(dispatch,string)result
val validate_attachment:device:int->attachment->(attachment,string)result
val create_descriptor:capability:capability->device:int->dispatch:dispatch->attachments:attachment option array->(descriptor,string)result
val replace_attachment:descriptor->index:int->attachment option->(descriptor,string)result
val retained_buffers:descriptor->sample_buffer list
val validate_handoff:unit->unit
