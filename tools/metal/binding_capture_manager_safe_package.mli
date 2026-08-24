type destination=Developer_tools|Gpu_trace_document
type source_kind=Device|Command_queue|Scope|Mtl4_command_queue
type source={token:int;device:int;kind:source_kind;destroyed:bool;parent:source option}
type descriptor={source:source;destination:destination;output_url:string option}
type capability={mtl4_capture:bool}
type state=Idle|Starting of descriptor|Active of descriptor
type start_outcome=Started of state|Rolled_back of state*string
val validate_source:capability->source->(source,string)result
val validate_url:destination->string option->(unit,string)result
val create_descriptor:capability:capability->source:source->destination:destination->output_url:string option->(descriptor,string)result
val create_scope:capability:capability->parent:source->token:int->(source,string)result
val set_default_scope:manager_device:int->source->(source option,string)result
val begin_start:state->descriptor->(state,string)result
val finish_start:state->native_result:(unit,string)result->start_outcome
val stop:state->(state,string)result
val retained_parent:state->source option
val validate_handoff:unit->unit
