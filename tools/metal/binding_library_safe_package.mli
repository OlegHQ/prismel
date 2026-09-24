type attribute={name:string option;index:int;data_type:int64;active:bool;patch:bool;control_point:bool}
type threadgroup={x:int;y:int;z:int}
type compile_options={macros:(string*string)array;required:threadgroup option}
type owned={token:int;device:int;destroyed:bool}
type reflection={bindings:string array;annotation:string option}
type completion_result=Function of owned|Failed of string|Cancelled
type async_state=Pending of owned array|Cancel_requested of owned array|Completed of completion_result
val snapshot_attribute:attribute->attribute
val validate_threadgroup:threadgroup->(threadgroup,string)result
val create_options:macros:(string*string)array->required:threadgroup option->(compile_options,string)result
val validate_owned:device:int->owned->(owned,string)result
val snapshot_reflection:reflection->reflection
val begin_async:owned array->async_state
val cancel:async_state->async_state
val complete:async_state->completion_result->(async_state,string)result
val retained_count:async_state->int
val validate_handoff:unit->unit
