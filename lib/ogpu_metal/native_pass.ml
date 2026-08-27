type resource=Buffer of Buffer.t|Texture of Texture.t
type action=Copy_buffer of{source:Buffer.t;source_offset:int64;destination:Buffer.t;destination_offset:int64;length:int64}|Dispatch of{pipeline:Pipeline.t;buffer:Buffer.t;threads:int}
let handle=function Buffer b->Buffer.Private.resource_handle b|Texture t->Texture.Private.resource_handle t
let id resource=Ogpu.Handle.id(handle resource)
let declaration resource~access~stages~owner~resulting_state={Ogpu.Native_pass.resource_id=id resource;resource=handle resource;access;stages;owner;resulting_state}
let error kind message=Error(Ogpu.Error.make"Ogpu_metal.Native_pass.record"kind message)
let validate_resource device=function Buffer b->Result.map(fun _->())(Buffer.descriptor device b)|Texture t->Result.map(fun _->())(Texture.descriptor device t)
let record device command plan~resources callback action=
  let declarations=Ogpu.Native_pass.declarations plan in
  let declared=Array.to_list declarations|>List.map(fun(d:Ogpu.Native_pass.declaration)->d.resource_id)|>List.sort compare and supplied=List.map id resources|>List.sort compare in
  if declared<>supplied then error Ogpu.Error.Invalid_argument"native resources do not exactly match declarations"else
  let rec validate=function []->Ok()|resource::rest->match validate_resource device resource with Error _ as e->e|Ok()->validate rest in
  match validate resources with Error _ as e->e|Ok()->
  if Array.exists(fun transition->match transition.Ogpu.Native_pass.after with Acceleration_read|Acceleration_write->true|_->false)(Ogpu.Native_pass.transitions plan)then error Ogpu.Error.Invalid_argument"acceleration native passes are not mapped by this slice"else
  let callback_result=try Ogpu.Native_pass.execute plan callback with exn->error Ogpu.Error.Invalid_state("native callback raised: "^Printexc.to_string exn)in
  match callback_result with Error _ as e->e|Ok()->match action with
  |Copy_buffer{source;source_offset;destination;destination_offset;length}->Command.copy_buffer command~source~source_offset~destination~destination_offset~length
  |Dispatch{pipeline;buffer;threads}->Command.dispatch command~pipeline~buffer~threads
