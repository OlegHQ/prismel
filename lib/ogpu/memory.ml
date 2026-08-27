type storage=Shared|Private|Upload|Readback
type access=Read|Write|Read_write
type descriptor={size:int64;alignment:int64;storage:storage;max_allocations:int}
type interval={offset:int64;length:int64}
type heap={device:Handle.device;handle:heap_kind Handle.t;descriptor:descriptor;mutable free:interval list;mutable live:allocation list;mutable maps:mapped list}
and allocation={heap:heap;handle:allocation_kind Handle.t;interval:interval;mutable alias:bool}
and mapped={allocation:allocation;interval:interval;mutable active:bool}
and heap_kind and allocation_kind
let err op kind msg=Error(Error.make op kind msg)
let power x=x>0L&&Int64.logand x(Int64.pred x)=0L
let finish x=Int64.add x.offset x.length
let create ~device d=if Handle.device_destroyed device then err"Ogpu.Memory.create"Error.Stale_handle"device destroyed"else if d.size<=0L||not(power d.alignment)||d.max_allocations<=0 then err"Ogpu.Memory.create"Error.Invalid_argument"invalid descriptor"else Ok{device;handle=Handle.create~device;descriptor=d;free=[{offset=0L;length=d.size}];live=[];maps=[]}
let destroy h=Handle.destroy h.handle
let align x a=let m=Int64.pred a in if x>Int64.sub Int64.max_int m then None else Some(Int64.logand(Int64.add x m)(Int64.lognot m))
let allocate ~device h ~size ~alignment=let op="Ogpu.Memory.allocate"in match Handle.validate_for~operation:op device h.handle with Error _ as e->e|Ok()when size<=0L||size>h.descriptor.size||not(power alignment)||alignment<h.descriptor.alignment->err op Error.Invalid_argument"invalid size/alignment"|Ok()when List.length h.live>=h.descriptor.max_allocations->err op Error.Capacity"allocation capacity"|Ok()->let rec f pre=function []->err op Error.Capacity"no fitting interval"|x::xs->match align x.offset alignment with None->f(x::pre)xs|Some off when off>finish x||size>Int64.sub(finish x)off->f(x::pre)xs|Some off->let tail=Int64.sub(finish x)(Int64.add off size)and head=Int64.sub off x.offset in let parts=(if head=0L then[]else[{offset=x.offset;length=head}])@(if tail=0L then[]else[{offset=Int64.add off size;length=tail}])in h.free<-List.rev_append pre(parts@xs);let a={heap=h;handle=Handle.create~device:h.device;interval={offset=off;length=size};alias=false}in h.live<-a::h.live;Ok a in f[]h.free
let coalesce xs=let xs=List.sort(fun a b->Int64.compare a.offset b.offset)xs in List.fold_left(fun acc x->match acc with p::tl when finish p=x.offset->{p with length=Int64.add p.length x.length}::tl|_->x::acc)[]xs|>List.rev
let free (a:allocation)=let op="Ogpu.Memory.free"in match Handle.validate~operation:op a.handle with Error _ as e->e|Ok()when a.alias||List.exists(fun m->m.active&&m.allocation==a)a.heap.maps->err op Error.Invalid_state"allocation busy"|Ok()->Handle.destroy a.handle;a.heap.live<-List.filter((!=)a)a.heap.live;a.heap.free<-coalesce(a.interval::a.heap.free);Ok()
let allocation_interval (a:allocation)=a.interval
let validate_allocation d (a:allocation)=Handle.validate_for~operation:"Ogpu.Memory.validate_allocation"d a.handle
let begin_alias (a:allocation)=match Handle.validate~operation:"Ogpu.Memory.begin_alias"a.handle with Error _ as e->e|Ok()when a.alias->err"Ogpu.Memory.begin_alias"Error.Invalid_state"already aliasing"|Ok()->a.alias<-true;Ok()
let end_alias (a:allocation)=match Handle.validate~operation:"Ogpu.Memory.end_alias"a.handle with Error _ as e->e|Ok()when not a.alias->err"Ogpu.Memory.end_alias"Error.Invalid_state"not aliasing"|Ok()->a.alias<-false;Ok()
let allowed s a=match s,a with Private,_->false|Upload,(Read|Read_write)->false|Readback,(Write|Read_write)->false|_->true
let overlap a b=a.offset<finish b&&b.offset<finish a
let map_range (a:allocation) ~access ~offset ~length=let op="Ogpu.Memory.map_range"in match Handle.validate~operation:op a.handle with Error _ as e->e|Ok()when a.alias->err op Error.Invalid_state"aliasing"|Ok()when not(allowed a.heap.descriptor.storage access)->err op Error.Unsupported"mapping policy"|Ok()when offset<0L||length<=0L||offset>a.interval.length||length>Int64.sub a.interval.length offset->err op Error.Invalid_argument"range"|Ok()->let i={offset=Int64.add a.interval.offset offset;length}in if List.exists(fun m->m.active&&m.allocation==a&&overlap m.interval i)a.heap.maps then err op Error.Invalid_state"overlap"else let m={allocation=a;interval=i;active=true}in a.heap.maps<-m::a.heap.maps;Ok m
let unmap (m:mapped)=if not m.active then err"Ogpu.Memory.unmap"Error.Invalid_state"already unmapped"else(m.active<-false;m.allocation.heap.maps<-List.filter((!=)m)m.allocation.heap.maps;Ok())
let mapped_active (m:mapped)=m.active
let mapped_interval m=if m.active then Ok m.interval else err"Ogpu.Memory.mapped_interval"Error.Stale_handle"inactive"
let with_mapped_range a ~access ~offset ~length f=match map_range a~access~offset~length with Error _ as e->e|Ok m->Fun.protect~finally:(fun()->if m.active then ignore(unmap m))(fun()->Ok(f m))
let free_intervals h=h.free
let live_intervals h=List.map(fun a->a.interval)h.live|>List.sort(fun a b->Int64.compare a.offset b.offset)
let metadata_count h=List.length h.free+List.length h.live+List.length h.maps
