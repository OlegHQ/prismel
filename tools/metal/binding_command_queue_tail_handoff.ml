type lane=Mechanical|Ownership|Metadata
type package=Descriptor_limit|Descriptor_log|Command_buffer|Queue_identity|Capture_boundary|Type_metadata
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
let mechanical_ids=["method:-[MTLCommandQueueDescriptor maxCommandBufferCount]";"method:-[MTLCommandQueueDescriptor setMaxCommandBufferCount:]";"property:MTLCommandQueueDescriptor:maxCommandBufferCount"]
let callable_ids =
  [ "method:-[MTLCommandQueue commandBufferWithDescriptor:]"
  ; "method:-[MTLCommandQueue commandBufferWithUnretainedReferences]"
  ; "method:-[MTLCommandQueue device]"
  ; "method:-[MTLCommandQueue insertDebugCaptureBoundary]"
  ; "method:-[MTLCommandQueue label]"
  ; "method:-[MTLCommandQueue setLabel:]"
  ; "method:-[MTLCommandQueueDescriptor logState]"
  ; "method:-[MTLCommandQueueDescriptor maxCommandBufferCount]"
  ; "method:-[MTLCommandQueueDescriptor setLogState:]"
  ; "method:-[MTLCommandQueueDescriptor setMaxCommandBufferCount:]"
  ; "property:MTLCommandQueue:device"
  ; "property:MTLCommandQueue:label"
  ; "property:MTLCommandQueueDescriptor:logState"
  ; "property:MTLCommandQueueDescriptor:maxCommandBufferCount"
  ]
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let classify~kind id=let lane=if List.mem id mechanical_ids then Mechanical else if kind="method"||kind="property"then Ownership else Metadata in let package,operation,tests=if lane=Metadata then Type_metadata,"Metal.Command_queue.Descriptor opaque type",["public provenance"]else if lane=Mechanical then Descriptor_limit,"Metal.Command_queue.Descriptor.max_count",["positive/range validation";"default round trip"]else if contains id "logState"||contains id "LogState"then Descriptor_log,"Metal.Command_queue.Descriptor.log_state",["same-device nullable log state";"mutation retention"]else if contains id "commandBuffer"then Command_buffer,"Metal.Command_queue.create_command_buffer",["nullable failure unwind";"queue parent retention";"unretained SDK path is safely retained by OCaml"]else if contains id "CaptureBoundary"then Capture_boundary,"Metal.Command_queue.capture_boundary",["queue live/state behavior"]else Queue_identity,"Metal.Command_queue device/label",["device identity";"nullable UTF-8 label"]in{id;lane;package;operation;tests}
let validate items=let count f=List.length(List.filter f items)in if List.length items<>15||count(fun x->x.lane=Mechanical)<>3||count(fun x->x.lane=Ownership)<>11||count(fun x->x.lane=Metadata)<>1||List.map(fun p->count(fun x->x.package=p))[Descriptor_limit;Descriptor_log;Command_buffer;Queue_identity;Capture_boundary;Type_metadata]<>[3;3;2;5;1;1]then failwith"CommandQueue15 tail drift"
