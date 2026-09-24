type package=Lifecycle|Queue_identity|Device_identity|Label|Type_metadata
type item={id:string;package:package;operation:string;tests:string list}
let callable_ids =
  [ "method:-[MTLCaptureScope beginScope]"; "method:-[MTLCaptureScope commandQueue]"
  ; "method:-[MTLCaptureScope device]"; "method:-[MTLCaptureScope endScope]"
  ; "method:-[MTLCaptureScope label]"; "method:-[MTLCaptureScope mtl4CommandQueue]"
  ; "method:-[MTLCaptureScope setLabel:]"; "property:MTLCaptureScope:commandQueue"
  ; "property:MTLCaptureScope:device"; "property:MTLCaptureScope:label"
  ; "property:MTLCaptureScope:mtl4CommandQueue" ]
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let classify~kind id=let package,operation,tests=if kind="protocol"then Type_metadata,"Metal.Capture_scope capability",["public provenance"]else if contains id "beginScope"||contains id "endScope"then Lifecycle,"Metal.Capture_scope begin/end",["balanced state";"nested/duplicate rejection";"destroyed behavior"]else if contains id "commandQueue"||contains id "CommandQueue"then Queue_identity,"Metal.Capture_scope queue",["nullable exact queue kind";"MTL4 availability";"parent identity"]else if contains id " device]"||contains id ":device"then Device_identity,"Metal.Capture_scope.device",["safe owner identity"]else Label,"Metal.Capture_scope.label",["nullable UTF-8 round trip";"lifetime"]in{id;package;operation;tests}
let validate items=let count p=List.length(List.filter(fun x->x.package=p)items)in if List.length items<>12||List.map count[Lifecycle;Queue_identity;Device_identity;Label;Type_metadata]<>[2;4;2;3;1]||List.exists(fun x->x.operation=""||x.tests=[])items then failwith"CaptureScope12 tail drift"
