type sync={handle:unit Handle.t;mutable value:int64}
type fence=Fence of sync
type event=Event of sync
type query_kind=Timestamp|Counter
type query_set={handle:unit Handle.t;kind:query_kind;count:int}
type description=Signal_fence of int64|Wait_fence of int64|Signal_event of int64|Wait_event of int64|Resolve of{kind:query_kind;first:int;count:int;destination_offset:int64;completion_epoch:int64}
let invalid op text=Error(Error.make op Error.Invalid_argument text)
let create_sync op device initial=if initial<0L then invalid op"initial value must be nonnegative"else Ok{handle=Handle.create ~device;value=initial}
let create_fence device ~initial=Result.map(fun value->Fence value)(create_sync"Ogpu.Sync.create_fence"device initial)
let create_event device ~initial=Result.map(fun value->Event value)(create_sync"Ogpu.Sync.create_event"device initial)
let signal op make device (sync:sync) next=match Handle.validate_for ~operation:op device sync.handle with Error _ as e->e|Ok()when next<sync.value->invalid op"signal value moved backwards"|Ok()->sync.value<-next;Ok(make next)
let wait op make device (sync:sync) target=match Handle.validate_for ~operation:op device sync.handle with Error _ as e->e|Ok()when target<0L->invalid op"wait value must be nonnegative"|Ok()when target>sync.value->Error(Error.make op Error.Invalid_state"wait value has not been signaled")|Ok()->Ok(make target)
let signal_fence device(Fence value)next=signal"Ogpu.Sync.signal_fence"(fun x->Signal_fence x)device value next
let wait_fence device(Fence value)target=wait"Ogpu.Sync.wait_fence"(fun x->Wait_fence x)device value target
let signal_event device(Event value)next=signal"Ogpu.Sync.signal_event"(fun x->Signal_event x)device value next
let wait_event device(Event value)target=wait"Ogpu.Sync.wait_event"(fun x->Wait_event x)device value target
let create_query_set device ~supported ~kind ~count=if not supported then Error(Error.make"Ogpu.Sync.create_query_set"Error.Unsupported"query kind is unsupported")else if count<=0 then invalid"Ogpu.Sync.create_query_set""query count must be positive"else Ok{handle=Handle.create ~device;kind;count}
let resolve device queries ~destination ~destination_size ~first ~count ~destination_offset ~completion_epoch=let op="Ogpu.Sync.resolve"in match Handle.validate_for ~operation:op device queries.handle with Error _ as e->e|Ok()->match Handle.validate_for ~operation:op device destination with Error _ as e->e|Ok()when first<0||count<=0||first>queries.count-count->invalid op"query range is invalid"|Ok()when destination_size<0L||destination_offset<0L||Int64.rem destination_offset 8L<>0L->invalid op"resolve destination is invalid or unaligned"|Ok()when completion_epoch<0L->invalid op"completion epoch must be nonnegative"|Ok()->let count64=Int64.of_int count in if count64>Int64.div Int64.max_int 8L then invalid op"resolve byte count overflows"else let bytes=Int64.mul count64 8L in if destination_offset>Int64.sub destination_size bytes then invalid op"resolve destination is out of bounds"else Ok(Resolve{kind=queries.kind;first;count;destination_offset;completion_epoch})
let destroy_fence(Fence value)=Handle.destroy value.handle
let destroy_event(Event value)=Handle.destroy value.handle
let destroy_query_set value=Handle.destroy value.handle
let fence_value(Fence value)=value.value
let event_value(Event value)=value.value
