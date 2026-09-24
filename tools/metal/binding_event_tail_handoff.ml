type package=Listener_constructor|Listener_queue|Shared_handle|Handle_label|Device_identity|Notification|Type_metadata
type item={id:string;package:package;operation:string;tests:string list}
let callable_ids =
  [ "method:+[MTLSharedEventListener sharedListener]"
  ; "method:-[MTLSharedEvent newSharedEventHandle]"
  ; "method:-[MTLSharedEvent notifyListener:atValue:block:]"
  ; "method:-[MTLSharedEventHandle label]"
  ; "method:-[MTLSharedEventListener dispatchQueue]"
  ; "method:-[MTLSharedEventListener initWithDispatchQueue:]"
  ; "method:-[MTLSharedEventListener init]"
  ; "property:MTLEvent:device"
  ; "property:MTLSharedEventHandle:label"
  ; "property:MTLSharedEventListener:dispatchQueue"
  ]
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let classify~kind id=let package,operation,tests=if kind="class"||kind="record"||kind="typedef"then Type_metadata,"Metal.Event handle/listener/callback types",["public provenance";"private record remains opaque"]else if contains id "notifyListener"then Notification,"Metal.Shared_event.notify",["callback exactly once at threshold";"callback root until fire/cancel";"exception isolation"]else if contains id "newSharedEventHandle"then Shared_handle,"Metal.Shared_event.export_handle",["owned exact handle kind";"parent lifetime"]else if contains id "SharedEventHandle"then Handle_label,"Metal.Shared_event_handle.label",["nullable UTF-8 snapshot"]else if contains id " device"||contains id ":device"then Device_identity,"Metal.Event.device",["nullable safe owner identity"]else if contains id "dispatchQueue"then Listener_queue,"Metal.Shared_event_listener.queue",["queue identity";"listener thread lifetime"]else Listener_constructor,"Metal.Shared_event_listener.create",["default/custom queue construction";"destroy idempotence";"failure unwind"]in{id;package;operation;tests}
let validate items=let count p=List.length(List.filter(fun x->x.package=p)items)in if List.length items<>14||List.map count[Listener_constructor;Listener_queue;Shared_handle;Handle_label;Device_identity;Notification;Type_metadata]<>[3;2;1;2;1;1;4]then failwith"Event14 tail drift"
