type resource={id:int;device:int;length:int;live:bool}
type encoder_state=Encoding|Ended
type t={device:int;state:encoder_state;retained:resource list;event_value:int64;capturing:bool}
let empty~device={device;state=Encoding;retained=[];event_value=0L;capturing=false}
let valid t r=r.live&&r.device=t.device
let range length offset size=offset>=0&&size>=0&&offset<=length-size
let copy t~source~source_offset~destination~destination_offset~size=
 if t.state<>Encoding then Error"blit encoder closed"
 else if not(valid t source&&valid t destination)then Error"blit resource stale or cross-device"
 else if not(range source.length source_offset size&&range destination.length destination_offset size)then Error"blit range invalid"
 else Ok{t with retained=source::destination::t.retained}
let signal t value=if Int64.compare value t.event_value<0 then Error"shared event value must be monotonic"else Ok{t with event_value=value}
let begin_capture t=if t.capturing then Error"capture already active"else Ok{t with capturing=true}
let end_capture t=if not t.capturing then Error"capture not active"else Ok{t with capturing=false}
