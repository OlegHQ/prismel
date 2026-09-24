type resource={id:int;device:int;length:int;live:bool}
type state=Encoding|Ended|Committed
type t={device:int;state:state;retained:resource list;bound_buffers:(int*resource*int)list}
let empty ~device={device;state=Encoding;retained=[];bound_buffers=[]}
let valid_resource t resource = resource.live&&resource.device=t.device
let bind_buffer t ~index ~offset resource =
  if t.state<>Encoding then Error "render encoder is not encoding"
  else if index<0||index>=31 then Error "buffer index out of range"
  else if offset<0||offset>resource.length then Error "buffer offset out of range"
  else if not(valid_resource t resource)then Error "buffer stale or cross-device"
  else
    let remaining=List.filter(fun(i,_,_)->i<>index)t.bound_buffers in
    Ok{t with retained=resource::t.retained;bound_buffers=(index,resource,offset)::remaining}
let use_resources t resources =
  if t.state<>Encoding then Error "render encoder is not encoding"
  else if List.exists(fun r->not(valid_resource t r))resources then Error "resource stale or cross-device"
  else Ok{t with retained=resources@t.retained}
let validate_draw t ~vertex_start ~vertex_count ~instance_count =
  if t.state<>Encoding then Error "render encoder is not encoding"
  else if vertex_start<0||vertex_count<=0||instance_count<=0 then Error "invalid draw range" else Ok()
let finish t=if t.state<>Encoding then Error "render encoder already ended"else Ok{t with state=Ended}
