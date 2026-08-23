type object_ref={id:int;device:int;live:bool}
type status=Created|Enqueued|Committed|Complete
type t={device:int;status:status;retained:object_ref list;argument_encoder:object_ref option;capture_active:bool}
let create~device={device;status=Created;retained=[];argument_encoder=None;capture_active=false}
let set_argument_encoder t value=if t.status<>Created then Error"submission already started"
 else if not value.live||value.device<>t.device then Error"argument encoder stale or cross-device"
 else Ok{t with argument_encoder=Some value;retained=value::t.retained}
let enqueue t=if t.status<>Created then Error"command buffer already enqueued"else Ok{t with status=Enqueued}
let commit t=match t.status with Created|Enqueued->Ok{t with status=Committed}|_->Error"command buffer already committed"
let complete t=if t.status<>Committed then Error"command buffer not committed"else Ok{t with status=Complete}
