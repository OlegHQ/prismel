type resource={id:int;device:int;length:int;live:bool}
type status=Recording|Committed|Complete|Failed
type command={source:resource;source_offset:int;destination:resource;destination_offset:int;size:int}
type t={device:int;status:status;commands:command list;retained:resource list;max_commands:int}
let create~device~max_commands=if device<0||max_commands<=0 then Error"invalid IO queue"else Ok{device;status=Recording;commands=[];retained=[];max_commands}
let range_ok length offset size=offset>=0&&size>=0&&offset<=length-size
let copy t command=
 if t.status<>Recording then Error"IO command buffer not recording"
 else if List.length t.commands>=t.max_commands then Error"IO command capacity exceeded"
 else if not command.source.live||not command.destination.live||command.source.device<>t.device||command.destination.device<>t.device then Error"IO resource stale or cross-device"
 else if not(range_ok command.source.length command.source_offset command.size&&range_ok command.destination.length command.destination_offset command.size)then Error"IO range out of bounds"
 else Ok{t with commands=command::t.commands;retained=command.source::command.destination::t.retained}
let commit t=if t.status<>Recording then Error"IO command already committed"else Ok{t with status=Committed}
