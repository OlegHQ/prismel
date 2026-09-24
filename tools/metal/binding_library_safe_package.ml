type attribute={name:string option;index:int;data_type:int64;active:bool;patch:bool;control_point:bool}
type threadgroup={x:int;y:int;z:int}
type compile_options={macros:(string*string)array;required:threadgroup option}
type owned={token:int;device:int;destroyed:bool}
type reflection={bindings:string array;annotation:string option}
type completion_result=Function of owned|Failed of string|Cancelled
type async_state=Pending of owned array|Cancel_requested of owned array|Completed of completion_result

let snapshot_attribute value={value with name=value.name}
let validate_threadgroup value=
 if value.x<=0||value.y<=0||value.z<=0 then Error"threadgroup dimensions must be positive"
 else if value.x>1024||value.y>1024||value.z>1024||value.x>1024/value.y||value.x*value.y>1024/value.z then Error"threadgroup size exceeds safe limit"
 else Ok value
let create_options ~macros ~required=
 let macros=Array.copy macros in
 if Array.exists(fun(k,_)->k=""||String.contains k '\000')macros then Error"invalid macro name"
 else match required with None->Ok{macros;required=None}|Some value->Result.map(fun value->{macros;required=Some value})(validate_threadgroup value)
let validate_owned ~device value=
 if value.destroyed then Error"destroyed library object"else if value.device<>device then Error"library object belongs to another device"else Ok value
let snapshot_reflection value={bindings=Array.copy value.bindings;annotation=value.annotation}
let begin_async retained=Pending(Array.copy retained)
let cancel=function Pending retained->Cancel_requested retained|state->state
let complete state result=
 match state with Completed _->Error"library callback completed more than once"|Cancel_requested _->Ok(Completed Cancelled)|Pending _->Ok(Completed result)
let retained_count=function Pending xs|Cancel_requested xs->Array.length xs|Completed _->0
let validate_handoff()=if List.length Binding_library_header_handoff.callable_ids<>34 then invalid_arg"MTLLibrary callable34 drift"
