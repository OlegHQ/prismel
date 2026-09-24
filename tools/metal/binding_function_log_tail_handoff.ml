type lane=Mechanical|Ownership|Metadata
type package=Log_type|Source_position|Log_graph|Source_identity|Type_metadata
type item={id:string;lane:lane;package:package;operation:string;tests:string list}
let mechanical_ids=["method:-[MTLFunctionLog type]";"property:MTLFunctionLog:type";"method:-[MTLFunctionLogDebugLocation column]";"property:MTLFunctionLogDebugLocation:column";"method:-[MTLFunctionLogDebugLocation line]";"property:MTLFunctionLogDebugLocation:line"]
let callable_ids =
  [ "method:-[MTLFunctionLog debugLocation]"; "method:-[MTLFunctionLog encoderLabel]"
  ; "method:-[MTLFunctionLog function]"; "method:-[MTLFunctionLog type]"
  ; "method:-[MTLFunctionLogDebugLocation URL]"; "method:-[MTLFunctionLogDebugLocation column]"
  ; "method:-[MTLFunctionLogDebugLocation functionName]"; "method:-[MTLFunctionLogDebugLocation line]"
  ; "property:MTLFunctionLog:debugLocation"; "property:MTLFunctionLog:encoderLabel"
  ; "property:MTLFunctionLog:function"; "property:MTLFunctionLog:type"
  ; "property:MTLFunctionLogDebugLocation:URL"; "property:MTLFunctionLogDebugLocation:column"
  ; "property:MTLFunctionLogDebugLocation:functionName"; "property:MTLFunctionLogDebugLocation:line" ]
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let classify~kind id=let lane=if List.mem id mechanical_ids then Mechanical else if kind="method"||kind="property"then Ownership else Metadata in let package,operation,tests=if lane=Metadata then Type_metadata,"Metal.Function_log opaque protocols",["public type provenance"]else if contains id " type]"||contains id ":type"then Log_type,"Metal.Function_log.type",["typed enum exactness";"unknown rejection"]else if contains id " column]"||contains id ":column"||contains id " line]"||contains id ":line"then Source_position,"Metal.Function_log.Location line/column",["NSUInteger range";"one-based source semantics"]else if contains id "DebugLocation"then Source_identity,"Metal.Function_log.Location URL/function_name",["nullable URL/string snapshot";"UTF-8 lifetime"]else Log_graph,"Metal.Function_log",["nullable function/location exact kinds";"encoder-label snapshot";"command completion retention"]in{id;lane;package;operation;tests}
let validate items=let count f=List.length(List.filter f items)in if List.length items<>18||count(fun x->x.lane=Mechanical)<>6||count(fun x->x.lane=Ownership)<>10||count(fun x->x.lane=Metadata)<>2||List.map(fun p->count(fun x->x.package=p))[Log_type;Source_position;Log_graph;Source_identity;Type_metadata]<>[2;4;6;4;2]then failwith"FunctionLog18 tail drift"
