type pending={id:int64;commands:Command.description array;resource_count:int}
type t={device:Handle.device;max_frames:int;mutable next_id:int64;mutable completed:int64;mutable lost:bool;mutable pending:pending list}
type receipt={id:int64;commands:Command.description array}
let create ?(max_frames=2) device=if max_frames<1||max_frames>3 then Error(Error.make"Ogpu.Submission.create"Error.Invalid_argument"frames in flight must be between 1 and 3")else Ok{device;max_frames;next_id=1L;completed=0L;lost=false;pending=[]}
let in_flight value=List.length value.pending
let retained_resource_count value=List.fold_left(fun n (p:pending)->n+p.resource_count)0 value.pending
let completed_epoch value=value.completed
let pending_descriptions value=value.pending|>List.map(fun(p:pending)->p.id,Array.copy p.commands)|>Array.of_list
let submit value command ~resources=let operation="Ogpu.Submission.submit"in if value.lost||Handle.device_destroyed value.device then Error(Error.make operation Error.Device_lost"queue device is lost")else if in_flight value>=value.max_frames then Error(Error.make operation Error.Capacity"frames-in-flight capacity reached")else match List.find_map(fun resource->match Handle.validate_for ~operation value.device resource with Ok()->None|Error e->Some e)resources with Some error->Error error|None->match Command.take_for_submission command with Error _ as e->e|Ok commands->let id=value.next_id in value.next_id<-Int64.succ id;value.pending<-value.pending@[{id;commands;resource_count=List.length resources}];Ok{id;commands=Array.copy commands}
let complete_through value epoch=let operation="Ogpu.Submission.complete_through"in if epoch<value.completed then Error(Error.make operation Error.Invalid_argument"completion epoch moved backwards")else let last=Int64.pred value.next_id in if epoch>last then Error(Error.make operation Error.Invalid_argument"completion epoch was never submitted")else(value.completed<-epoch;value.pending<-List.filter(fun(p:pending)->p.id>epoch)value.pending;Ok())
let drain value=let last=Int64.pred value.next_id in value.completed<-max value.completed last;value.pending<-[]
let lose_device value=value.lost<-true;drain value
