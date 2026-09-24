type slot = { mutable generation:int64; mutable owner:allocation option }
and t =
  { device:Handle.device; handle:arena_kind Handle.t; capacity:int;
    storage:slot array; mutable allocations:allocation list;
    mutable completed:int64 }
and allocation =
  { arena:t; handle:allocation_kind Handle.t; first:int; count:int;
    generations:int64 array; mutable submitted:int64 option }
and arena_kind and allocation_kind

let error operation kind message=Error(Error.make operation kind message)

let create ~device ~capacity =
  let operation="Ogpu.Descriptor_arena.create"in
  if Handle.device_destroyed device then error operation Error.Stale_handle"device is destroyed"
  else if capacity<=0 then error operation Error.Invalid_argument"capacity must be positive"
  else Ok{device;handle=Handle.create~device;capacity;
    storage=Array.init capacity(fun _->{generation=1L;owner=None});allocations=[];completed=0L}

let validate_arena operation device value =
  Handle.validate_for~operation device value.handle

let find_run value count =
  let rec search start run index =
    if run=count then Some start
    else if index=value.capacity then None
    else if value.storage.(index).owner=None then
      search(if run=0 then index else start)(run+1)(index+1)
    else search 0 0 (index+1)
  in search 0 0 0

let allocate device value ~count =
  let operation="Ogpu.Descriptor_arena.allocate"in
  match validate_arena operation device value with Error _ as failure->failure|Ok()->
  if count<=0||count>value.capacity then error operation Error.Invalid_argument"allocation cardinality is invalid"
  else match find_run value count with None->error operation Error.Capacity"descriptor arena is full or fragmented"|Some first->
    let generations=Array.init count(fun offset->value.storage.(first+offset).generation)in
    let allocation={arena=value;handle=Handle.create~device:value.device;first;count;generations;submitted=None}in
    for offset=0 to count-1 do value.storage.(first+offset).owner<-Some allocation done;
    value.allocations<-value.allocations@[allocation];Ok allocation

let slots (value:allocation)=Array.init value.count(fun offset->value.first+offset)
let generations (value:allocation)=Array.copy value.generations

let validate device (value:allocation) =
  let operation="Ogpu.Descriptor_arena.validate"in
  match Handle.validate_for~operation device value.handle with Error _ as failure->failure|Ok()->
  let rec loop offset =
    if offset=value.count then Ok()
    else let slot=value.arena.storage.(value.first+offset)in
      if (match slot.owner with Some owner->owner!=value|None->true)
         ||slot.generation<>value.generations.(offset)then
        error operation Error.Stale_handle"descriptor allocation generation is stale"
      else loop(offset+1)
  in loop 0

let mark_submitted (value:allocation) (receipt:Submission.receipt)=
  let operation="Ogpu.Descriptor_arena.mark_submitted"in
  match Handle.validate~operation value.handle with Error _ as failure->failure|Ok()->
  if receipt.id<=value.arena.completed then error operation Error.Invalid_argument"submission epoch is already completed"
  else match value.submitted with Some _->error operation Error.Invalid_state"allocation was already submitted"|None->value.submitted<-Some receipt.id;Ok()

let retire (value:allocation) =
  Handle.destroy value.handle;
  for offset=0 to value.count-1 do
    let slot=value.arena.storage.(value.first+offset)in
    slot.owner<-None;slot.generation<-Int64.succ slot.generation
  done;
  value.arena.allocations<-List.filter((!=)value)value.arena.allocations

let release (value:allocation) =
  let operation="Ogpu.Descriptor_arena.release"in
  match Handle.validate~operation value.handle with Error _ as failure->failure|Ok()->
  match value.submitted with Some epoch when epoch>value.arena.completed->
    error operation Error.Invalid_state"submitted descriptors are still in flight"
  |Some _|None->retire value;Ok()

let reset (value:t) ~completed_epoch =
  let operation="Ogpu.Descriptor_arena.reset"in
  match Handle.validate~operation value.handle with Error _ as failure->failure|Ok()->
  if completed_epoch<value.completed then error operation Error.Invalid_argument"completion epoch moved backwards"
  else begin
    value.completed<-completed_epoch;
    let releasable=List.filter(fun allocation->match allocation.submitted with None->true|Some epoch->epoch<=completed_epoch)value.allocations in
    List.iter retire releasable;Ok()
  end

let live_count (value:t)=List.length value.allocations
let pending_count (value:t)=List.fold_left(fun count allocation->match allocation.submitted with Some epoch when epoch>value.completed->count+1|_->count)0 value.allocations
let metadata_count (value:t)=Array.length value.storage
let completed_epoch (value:t)=value.completed

let destroy (value:t) =
  let operation="Ogpu.Descriptor_arena.destroy"in
  match Handle.validate~operation value.handle with Error _->Ok()|Ok()->
  if value.allocations<>[]then error operation Error.Invalid_state"arena still owns live allocations"
  else (Handle.destroy value.handle;Ok())
