type pass=Transfer|Render|Compute|Acceleration
type access=Read|Write|Read_write
type stage=Transfer_stage|Vertex|Fragment|Compute_stage|Acceleration_stage
type resource_access={resource_id:int64;access:access;stages:stage list}
type description=Begin_encoder|Begin_pass of pass|End_pass of pass|Push_debug of string|Pop_debug|Declare_resource of resource_access|End_encoder|Present
type state=Recording|In_pass of pass|Ended|Presented|Submitted
type t={mutable state:state;mutable debug:string list;mutable commands:description list}
let begin_encoder()={state=Recording;debug=[];commands=[Begin_encoder]}
let state_error operation message=Error(Error.make operation Error.Invalid_state message)
let append value command=value.commands<-command::value.commands
let begin_pass value pass=match value.state with Recording->value.state<-In_pass pass;append value(Begin_pass pass);Ok()|_->state_error"Ogpu.Command.begin_pass""encoder is not ready to begin a pass"
let end_pass value=match value.state with In_pass pass->value.state<-Recording;append value(End_pass pass);Ok()|_->state_error"Ogpu.Command.end_pass""no pass is active"
let push_debug value label=if String.contains label '\000' then Error(Error.make"Ogpu.Command.push_debug"Error.Invalid_argument"debug label contains NUL")else match value.state with Ended|Presented|Submitted->state_error"Ogpu.Command.push_debug""encoder has ended"|Recording|In_pass _->value.debug<-label::value.debug;append value(Push_debug label);Ok()
let pop_debug value=match value.state,value.debug with (Ended|Presented|Submitted),_->state_error"Ogpu.Command.pop_debug""encoder has ended"|_,[]->state_error"Ogpu.Command.pop_debug""debug stack is empty"|_,_::rest->value.debug<-rest;append value Pop_debug;Ok()
let declare_resource value ~resource_id ~access ~stages=match value.state with
  |In_pass _ when resource_id<=0L->Error(Error.make"Ogpu.Command.declare_resource"Error.Invalid_argument"resource id must be positive")
  |In_pass _ when stages=[]->Error(Error.make"Ogpu.Command.declare_resource"Error.Invalid_argument"at least one stage is required")
  |In_pass _ when List.sort_uniq compare stages<>stages->Error(Error.make"Ogpu.Command.declare_resource"Error.Invalid_argument"stages must be sorted and unique")
  |In_pass _->append value(Declare_resource{resource_id;access;stages});Ok()
  |_->state_error"Ogpu.Command.declare_resource""resource access requires an active pass"
let end_encoder value=match value.state,value.debug with Recording,[]->value.state<-Ended;append value End_encoder;Ok()|Recording,_->state_error"Ogpu.Command.end_encoder""debug groups remain open"|In_pass _,_->state_error"Ogpu.Command.end_encoder""a pass remains open"|(Ended|Presented|Submitted),_->state_error"Ogpu.Command.end_encoder""encoder has already ended"
let present value=match value.state with Ended->value.state<-Presented;append value Present;Ok()|_->state_error"Ogpu.Command.present""present requires one newly ended encoder"
let descriptions value=Array.of_list(List.rev value.commands)
let take_for_submission value=match value.state with Ended->value.state<-Submitted;Ok(descriptions value)|_->state_error"Ogpu.Command.take_for_submission""submission requires one newly ended encoder"
