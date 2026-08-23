type object_ref={id:int;device:int;live:bool}
type state=Initial|Recording|Ended|Committed|Complete
type t={device:int;state:state;retained:object_ref list;argument_tables:object_ref list}
let create~device={device;state=Initial;retained=[];argument_tables=[]}
let begin_recording t=if t.state<>Initial then Error"Metal4 buffer already recording"else Ok{t with state=Recording}
let retain t objects=if t.state<>Recording then Error"Metal4 buffer not recording"
 else if List.exists(fun o->not o.live||o.device<>t.device)objects then Error"Metal4 object stale or cross-device"
 else Ok{t with retained=objects@t.retained}
let end_recording t=if t.state<>Recording then Error"Metal4 buffer not recording"else Ok{t with state=Ended}
let commit t=if t.state<>Ended then Error"Metal4 buffer must be ended before commit"else Ok{t with state=Committed}
