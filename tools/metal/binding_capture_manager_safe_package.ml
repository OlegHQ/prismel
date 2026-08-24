type destination=Developer_tools|Gpu_trace_document
type source_kind=Device|Command_queue|Scope|Mtl4_command_queue
type source={token:int;device:int;kind:source_kind;destroyed:bool;parent:source option}
type descriptor={source:source;destination:destination;output_url:string option}
type capability={mtl4_capture:bool}
type state=Idle|Starting of descriptor|Active of descriptor
type start_outcome=Started of state|Rolled_back of state*string

let validate_source capability source=
 if source.destroyed then Error"destroyed capture source"
 else if source.kind=Mtl4_command_queue&&not capability.mtl4_capture then Error"MTL4 capture is unavailable"
 else Ok source
let validate_url destination output_url=
 match destination,output_url with
 |Developer_tools,None->Ok()|Developer_tools,Some _->Error"developer-tools capture cannot use an output URL"
 |Gpu_trace_document,Some url when url<>""&&not(String.contains url '\000')->Ok()
 |Gpu_trace_document,_->Error"GPU trace capture requires a valid output URL"
let create_descriptor ~capability ~source ~destination ~output_url=
 match validate_source capability source,validate_url destination output_url with Error e,_|_,Error e->Error e|Ok source,Ok()->Ok{source;destination;output_url}
let create_scope ~capability ~parent ~token=
 match validate_source capability parent with Error e->Error e|Ok _ when token<0->Error"invalid capture scope token"|Ok parent->Ok{token;device=parent.device;kind=Scope;destroyed=false;parent=Some parent}
let set_default_scope ~manager_device scope=
 if scope.destroyed then Error"destroyed default capture scope"else if scope.device<>manager_device then Error"default scope belongs to another device"else Ok(Some scope)
let begin_start state descriptor=
 match state with Idle->Ok(Starting descriptor)|Starting _|Active _->Error"a capture is already active"
let finish_start state ~native_result=
 match state,native_result with Starting descriptor,Ok()->Started(Active descriptor)|Starting _,Error error->Rolled_back(Idle,error)|_->Rolled_back(Idle,"capture start state mismatch")
let stop=function Idle->Error"no active capture"|Starting _->Error"capture start is in progress"|Active _->Ok Idle
let retained_parent=function Idle->None|Starting descriptor|Active descriptor->Some descriptor.source
let validate_handoff()=if List.length Binding_capture_manager_tail_handoff.callable_ids<>19 then invalid_arg"CaptureManager callable19 drift"
