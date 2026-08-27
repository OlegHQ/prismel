type phase=Surface_frames|Submissions|Descriptor_arenas|Transfer_rings|Caches|Resources
type policy=Drain|Abandon
type reason=Device_lost|Shutdown
type failure={phase:phase;label:string;error:Error.t}
type report={reason:reason;policy:policy;callbacks:int;failures:failure list}
type callback={sequence:int;phase:phase;label:string;run:policy->(unit,Error.t)result}
type state=Active|Transitioning|Terminal of report
type t={handle:kind Handle.t;capacity:int;mutable next:int;mutable callbacks:callback list;mutable state:state}
and kind
let error operation kind message=Error(Error.make operation kind message)
let create ~device ~capacity=
  let operation="Ogpu.Device_lifecycle.create"in
  if Handle.device_destroyed device then error operation Error.Stale_handle"device is destroyed"
  else if capacity<=0 then error operation Error.Invalid_argument"callback capacity must be positive"
  else Ok{handle=Handle.create~device;capacity;next=0;callbacks=[];state=Active}
let valid_label label=label<>""&&not(String.contains label '\000')
let register device value ~phase ~label run=
  let operation="Ogpu.Device_lifecycle.register"in
  match Handle.validate_for~operation device value.handle with Error _ as failure->failure|Ok()->
  match value.state with Terminal _|Transitioning->error operation Error.Invalid_state"lifecycle transition has started"|Active->
  if not(valid_label label)then error operation Error.Invalid_argument"callback label is invalid"
  else if List.length value.callbacks>=value.capacity then error operation Error.Capacity"callback capacity reached"
  else let callback={sequence=value.next;phase;label;run}in value.next<-value.next+1;value.callbacks<-value.callbacks@[callback];Ok()
let phase_rank=function Surface_frames->0|Submissions->1|Descriptor_arenas->2|Transfer_rings->3|Caches->4|Resources->5
let compare_callback left right=match Int.compare(phase_rank left.phase)(phase_rank right.phase)with 0->Int.compare left.sequence right.sequence|order->order
let transition value ~reason ~policy=
  let operation="Ogpu.Device_lifecycle.transition"in
  match Handle.validate~operation value.handle with Error _ as failure->failure|Ok()->
  match value.state with Terminal report->Ok report|Transitioning->error operation Error.Invalid_state"recursive lifecycle transition"|Active->
  value.state<-Transitioning;
  let callbacks=List.sort compare_callback value.callbacks in
  let failures=List.filter_map(fun callback->
    try match callback.run policy with Ok()->None|Error failure->Some{phase=callback.phase;label=callback.label;error=failure}
    with exn->Some{phase=callback.phase;label=callback.label;
      error=Error.make operation Error.Invalid_state(Printexc.to_string exn)})callbacks in
  value.callbacks<-[];
  let report={reason;policy;callbacks=List.length callbacks;failures}in value.state<-Terminal report;Ok report
let terminal_report value=match value.state with Terminal report->Some report|Active|Transitioning->None
let registered_count value=List.length value.callbacks
let metadata_count value=value.capacity
let destroy value=
  let operation="Ogpu.Device_lifecycle.destroy"in
  match Handle.validate~operation value.handle with Error _->Ok()|Ok()->
  match value.state with Active when value.callbacks<>[]->error operation Error.Invalid_state"active lifecycle still owns callbacks"|Active|Terminal _->Handle.destroy value.handle;Ok()|Transitioning->error operation Error.Invalid_state"lifecycle transition is running"
