type direction=Upload|Readback
type policy=Copy|Borrow
type state=Pending|Committed of int64|Cancelled
type t={device:Handle.device;handle:ring_kind Handle.t;capacity:int64;alignment:int64;max_slots:int;mutable cursor:int64;mutable next:int64;mutable slots:reservation list;mutable completed:int64}
and reservation={ring:t;index:int64;offset:int64;length:int64;direction:direction;policy:policy;data:bytes option;mutable state:state}
and ring_kind
type snapshot={index:int64;offset:int64;length:int64;direction:direction;policy:policy}
let err op kind msg=Error(Error.make op kind msg)
let power x=x>0L&&Int64.logand x(Int64.pred x)=0L
let create ~device ~capacity ~alignment ~max_slots=if Handle.device_destroyed device then err"Ogpu.Transfer_ring.create"Error.Stale_handle"device destroyed"else if capacity<=0L||not(power alignment)||max_slots<=0 then err"Ogpu.Transfer_ring.create"Error.Invalid_argument"invalid capacity"else Ok{device;handle=Handle.create~device;capacity;alignment;max_slots;cursor=0L;next=1L;slots=[];completed=0L}
let align x a=let m=Int64.pred a in if x>Int64.sub Int64.max_int m then None else Some(Int64.logand(Int64.add x m)(Int64.lognot m))
let overlap o l r=r.state<>Cancelled&&o<Int64.add r.offset r.length&&r.offset<Int64.add o l
let reserve r ~direction ~policy ?bytes ~length ()=let op="Ogpu.Transfer_ring.reserve"in match Handle.validate~operation:op r.handle with Error _ as e->e|Ok()when length<=0L||length>r.capacity->err op Error.Invalid_argument"invalid length"|Ok()when List.length r.slots>=r.max_slots->err op Error.Capacity"slot capacity"|Ok()->(match bytes with Some b when Int64.of_int(Bytes.length b)<length->err op Error.Invalid_argument"source too short"|_->let candidates=[r.cursor;0L]in let rec pick=function []->err op Error.Capacity"ring backpressure"|x::xs->match align x r.alignment with None->pick xs|Some o when o>r.capacity||length>Int64.sub r.capacity o||List.exists(overlap o length)r.slots->pick xs|Some o->let data=match bytes with None->None|Some b->Some(if policy=Copy then Bytes.copy b else b)in let v={ring=r;index=r.next;offset=o;length;direction;policy;data;state=Pending}in r.next<-Int64.succ r.next;r.cursor<-Int64.add o length;r.slots<-r.slots@[v];Ok v in pick candidates)
let live op v=match Handle.validate~operation:op v.ring.handle with Error _ as e->e|Ok()->Ok()
let commit v ~epoch=match live"Ogpu.Transfer_ring.commit"v with Error _ as e->e|Ok()when epoch<=v.ring.completed->err"Ogpu.Transfer_ring.commit"Error.Invalid_argument"epoch already completed"|Ok()->(match v.state with Pending->v.state<-Committed epoch;Ok()|_->err"Ogpu.Transfer_ring.commit"Error.Invalid_state"not pending")
let cancel v=match live"Ogpu.Transfer_ring.cancel"v with Error _ as e->e|Ok()->(match v.state with Pending->v.state<-Cancelled;v.ring.slots<-List.filter((!=)v)v.ring.slots;Ok()|_->err"Ogpu.Transfer_ring.cancel"Error.Invalid_state"not pending")
let reclaim r ~completed_epoch=match Handle.validate~operation:"Ogpu.Transfer_ring.reclaim"r.handle with Error _ as e->e|Ok()when completed_epoch<r.completed->err"Ogpu.Transfer_ring.reclaim"Error.Invalid_argument"epoch moved backwards"|Ok()->r.completed<-completed_epoch;r.slots<-List.filter(function{state=Committed e;_}->e>completed_epoch|_->true)r.slots;Ok()
let snap (v:reservation):snapshot={index=v.index;offset=v.offset;length=v.length;direction=v.direction;policy=v.policy}
let snapshot v=match live"Ogpu.Transfer_ring.snapshot"v with Error _ as e->e|Ok()->(match v.state with Cancelled->err"Ogpu.Transfer_ring.snapshot"Error.Stale_handle"cancelled"|_->Ok(snap v))
let payload v=match snapshot v with Error _ as e->e|Ok _->Ok(Option.map Bytes.copy v.data)
let live_slots r=List.length r.slots
let reservations r=List.map snap r.slots
let validate device r=if Handle.device_id device<>Handle.device_id r.device then err"Ogpu.Transfer_ring.validate"Error.Cross_device"ring belongs to another device"else Handle.validate_for~operation:"Ogpu.Transfer_ring.validate"device r.handle
let destroy r=Handle.destroy r.handle
