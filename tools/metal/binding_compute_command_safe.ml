type resource={id:int;device:int;length:int;live:bool}
type state=Encoding|Ended|Committed
type t={device:int;state:state;buffers:(int*resource*int)list;retained:resource list}
let empty~device={device;state=Encoding;buffers=[];retained=[]}
let bind t~index~offset resource=
 if t.state<>Encoding then Error"compute encoder is closed"
 else if index<0||index>=31 then Error"buffer index out of range"
 else if not resource.live||resource.device<>t.device then Error"buffer stale or cross-device"
 else if offset<0||offset>resource.length then Error"buffer offset out of range"
 else Ok{t with buffers=(index,resource,offset)::List.filter(fun(i,_,_)->i<>index)t.buffers;retained=resource::t.retained}
let dispatch t~grid:(gx,gy,gz)~threads:(tx,ty,tz)=
 if t.state<>Encoding then Error"compute encoder is closed"
 else if gx<=0||gy<=0||gz<=0||tx<=0||ty<=0||tz<=0 then Error"dispatch dimensions must be positive"
 else if tx>1024/ty||tx*ty>1024/tz then Error"threadgroup exceeds safe limit"else Ok()
let finish t=if t.state<>Encoding then Error"compute encoder already closed"else Ok{t with state=Ended}
