type severity=Info|Warning|Error
type category=Validation|Performance|Resource|Submission
type message={sequence:int64;severity:severity;category:category;label:string option;text:string}
type trace=Timestamp of{sequence:int64;label:string;value:int64}|Counter of{sequence:int64;label:string;value:int64}
type t={device:Handle.device;handle:kind Handle.t;mc:int;tc:int;ml:int;mm:int;mutable seq:int64;mutable msgs:message list;mutable trs:trace list;mutable dm:int;mutable dt:int;mutable groups:string list;mutable capture:string option}
and kind
let err op kind text=Result.Error(Error.make op kind text)
let create ~device ~message_capacity ~trace_capacity ~max_label_length ~max_message_length=if Handle.device_destroyed device then err"Ogpu.Diagnostics.create"Error.Stale_handle"device destroyed"else if message_capacity<=0||trace_capacity<=0||max_label_length<=0||max_message_length<=0 then err"Ogpu.Diagnostics.create"Error.Invalid_argument"capacities must be positive"else Ok{device;handle=Handle.create~device;mc=message_capacity;tc=trace_capacity;ml=max_label_length;mm=max_message_length;seq=1L;msgs=[];trs=[];dm=0;dt=0;groups=[];capture=None}
let validate d t=if Handle.device_id d<>Handle.device_id t.device then err"Ogpu.Diagnostics.validate"Error.Cross_device"foreign device"else Handle.validate_for~operation:"Ogpu.Diagnostics.validate"d t.handle
let live op t=Handle.validate~operation:op t.handle
let text max s=s<>""&&String.length s<=max&&not(String.contains s '\000')
let next t=let x=t.seq in t.seq<-Int64.succ x;x
let bound cap xs=if List.length xs<=cap then xs,false else List.tl xs,true
let add_message t ~severity ~category ?label value=let op="Ogpu.Diagnostics.add_message"in match live op t with Result.Error _ as e->e|Ok()when not(text t.mm value)||Option.fold~none:false~some:(fun x->not(text t.ml x))label->err op Error.Invalid_argument"invalid text"|Ok()->let xs,d=bound t.mc(t.msgs@[{sequence=next t;severity;category;label;text=value}])in t.msgs<-xs;if d then t.dm<-t.dm+1;Ok()
let push_debug t s=match live"Ogpu.Diagnostics.push_debug"t with Result.Error _ as e->e|Ok()when not(text t.ml s)->err"Ogpu.Diagnostics.push_debug"Error.Invalid_argument"invalid label"|Ok()->t.groups<-s::t.groups;Ok()
let pop_debug t=match live"Ogpu.Diagnostics.pop_debug"t with Result.Error _ as e->e|Ok()->(match t.groups with []->err"Ogpu.Diagnostics.pop_debug"Error.Invalid_state"empty debug stack"|_::xs->t.groups<-xs;Ok())
let begin_capture t s=match live"Ogpu.Diagnostics.begin_capture"t with Result.Error _ as e->e|Ok()when not(text t.ml s)->err"Ogpu.Diagnostics.begin_capture"Error.Invalid_argument"invalid label"|Ok()->(match t.capture with Some _->err"Ogpu.Diagnostics.begin_capture"Error.Invalid_state"capture active"|None->t.capture<-Some s;Ok())
let end_capture t=match live"Ogpu.Diagnostics.end_capture"t with Result.Error _ as e->e|Ok()->(match t.capture with None->err"Ogpu.Diagnostics.end_capture"Error.Invalid_state"no capture"|Some _->t.capture<-None;Ok())
let trace t label make=let op="Ogpu.Diagnostics.trace"in match live op t with Result.Error _ as e->e|Ok()when not(text t.ml label)->err op Error.Invalid_argument"invalid label"|Ok()->let xs,d=bound t.tc(t.trs@[make(next t)])in t.trs<-xs;if d then t.dt<-t.dt+1;Ok()
let timestamp t ~label value=trace t label(fun sequence->Timestamp{sequence;label;value})
let counter t ~label value=trace t label(fun sequence->Counter{sequence;label;value})
let messages t=t.msgs and traces t=t.trs and dropped_messages t=t.dm and dropped_traces t=t.dt
let clear t=t.msgs<-[];t.trs<-[];t.groups<-[];t.capture<-None
let drain_device_loss=clear
let destroy t=Handle.destroy t.handle
