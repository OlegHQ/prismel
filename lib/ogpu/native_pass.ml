type owner=Ogpu|Native
type resource_state=Undefined|Shader_read|Shader_write|Copy_source|Copy_destination|Acceleration_read|Acceleration_write
type declaration={resource_id:int64;resource:unit Handle.t;access:Command.access;stages:Command.stage list;owner:owner;resulting_state:resource_state}
type transition={resource_id:int64;before:resource_state;after:resource_state}
type plan={declarations:declaration array;transitions:transition array}
type 'scope encoder=Encoder
type callback={run:'scope.'scope encoder->(unit,Error.t)result}
let invalid text=Error(Error.make"Ogpu.Native_pass.create"Error.Invalid_argument text)
let writable=function Command.Write|Read_write->true|Read->false
let state_writes=function Shader_write|Copy_destination|Acceleration_write->true|_->false
let create device ~declarations ~transitions=
  if Array.length declarations=0 then invalid"native pass has no declared resources"else let seen=Hashtbl.create(Array.length declarations)in
  let rec validate i=if i=Array.length declarations then Ok()else let(d:declaration)=declarations.(i)in if d.resource_id<=0L then invalid"resource id must be positive"else if Hashtbl.mem seen d.resource_id then invalid"duplicate resource declaration"else match Handle.validate_for ~operation:"Ogpu.Native_pass.create"device d.resource with Error _ as e->e|Ok()when d.stages=[]->invalid"resource stages are empty"|Ok()when List.sort_uniq compare d.stages<>d.stages->invalid"resource stages must be sorted and unique"|Ok()when state_writes d.resulting_state&&not(writable d.access)->invalid"read-only declaration produces a writable state"|Ok()->Hashtbl.add seen d.resource_id d;validate(i+1)in
  Result.bind(validate 0)(fun()->let rec check i=if i=Array.length transitions then Ok()else let(t:transition)=transitions.(i)in match Hashtbl.find_opt seen t.resource_id with None->invalid"transition references an undeclared resource"|Some d when d.resulting_state<>t.after->invalid"transition result disagrees with declaration"|Some _ when t.before=t.after->invalid"transition does not change state"|Some _->check(i+1)in Result.map(fun()->{declarations=Array.copy declarations;transitions=Array.copy transitions})(check 0))
let execute _plan callback=callback.run Encoder
let declarations plan=Array.copy plan.declarations
let transitions plan=Array.copy plan.transitions
