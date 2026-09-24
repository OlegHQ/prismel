type resource={id:int;device:int;length:int;live:bool}
type status=Recording|Committed|Complete|Failed
type command={source:resource;source_offset:int;destination:resource;destination_offset:int;size:int}
type t={device:int;status:status;commands:command list;retained:resource list;max_commands:int}
val create:device:int->max_commands:int->(t,string)result
val copy:t->command->(t,string)result
val commit:t->(t,string)result
