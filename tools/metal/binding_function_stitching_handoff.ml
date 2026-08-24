type lane = Mechanical | Ownership | Metadata
type package = Options | Input_node | Function_node | Graph | Stitched_descriptor | Type_metadata
type item = { id:string; lane:lane; package:package; operation:string; tests:string list }
let contains s n=let l=String.length n in let rec f i=i+l<=String.length s&&(String.sub s i l=n||f(i+1))in f 0
let mechanical_ids=["method:-[MTLStitchedLibraryDescriptor options]";"method:-[MTLStitchedLibraryDescriptor setOptions:]";"property:MTLStitchedLibraryDescriptor:options"]
let callable_ids=["method:-[MTLFunctionStitchingFunctionNode arguments]";"method:-[MTLFunctionStitchingFunctionNode controlDependencies]";"method:-[MTLFunctionStitchingFunctionNode initWithName:arguments:controlDependencies:]";"method:-[MTLFunctionStitchingFunctionNode name]";"method:-[MTLFunctionStitchingFunctionNode setArguments:]";"method:-[MTLFunctionStitchingFunctionNode setControlDependencies:]";"method:-[MTLFunctionStitchingFunctionNode setName:]";"method:-[MTLFunctionStitchingGraph attributes]";"method:-[MTLFunctionStitchingGraph functionName]";"method:-[MTLFunctionStitchingGraph initWithFunctionName:nodes:outputNode:attributes:]";"method:-[MTLFunctionStitchingGraph nodes]";"method:-[MTLFunctionStitchingGraph outputNode]";"method:-[MTLFunctionStitchingGraph setAttributes:]";"method:-[MTLFunctionStitchingGraph setFunctionName:]";"method:-[MTLFunctionStitchingGraph setNodes:]";"method:-[MTLFunctionStitchingGraph setOutputNode:]";"method:-[MTLFunctionStitchingInputNode initWithArgumentIndex:]";"method:-[MTLStitchedLibraryDescriptor binaryArchives]";"method:-[MTLStitchedLibraryDescriptor functionGraphs]";"method:-[MTLStitchedLibraryDescriptor functions]";"method:-[MTLStitchedLibraryDescriptor options]";"method:-[MTLStitchedLibraryDescriptor setBinaryArchives:]";"method:-[MTLStitchedLibraryDescriptor setFunctionGraphs:]";"method:-[MTLStitchedLibraryDescriptor setFunctions:]";"method:-[MTLStitchedLibraryDescriptor setOptions:]";"property:MTLFunctionStitchingFunctionNode:arguments";"property:MTLFunctionStitchingFunctionNode:controlDependencies";"property:MTLFunctionStitchingFunctionNode:name";"property:MTLFunctionStitchingGraph:attributes";"property:MTLFunctionStitchingGraph:functionName";"property:MTLFunctionStitchingGraph:nodes";"property:MTLFunctionStitchingGraph:outputNode";"property:MTLStitchedLibraryDescriptor:binaryArchives";"property:MTLStitchedLibraryDescriptor:functionGraphs";"property:MTLStitchedLibraryDescriptor:functions";"property:MTLStitchedLibraryDescriptor:options"]
let classify ~kind id =
 let lane=if List.mem id mechanical_ids then Mechanical else if kind="method"||kind="property" then Ownership else Metadata in
 let package,operation,tests=
  if lane=Metadata then Type_metadata,"Metal.Function_stitching opaque graph types",["public type provenance"]
  else if contains id "MTLFunctionStitchingInputNode" then Input_node,"Metal.Function_stitching.Input",["index validation";"ownership"]
  else if contains id "MTLFunctionStitchingFunctionNode" then Function_node,"Metal.Function_stitching.Function_node",["argument/dependency graph";"cycle rejection";"mutation retention"]
  else if contains id "MTLFunctionStitchingGraph" then Graph,"Metal.Function_stitching.Graph",["node/output membership";"nullable output";"destroy order"]
  else if lane=Mechanical then Options,"Metal.Function_stitching.Descriptor.options",["typed flags round trip";"unknown-bit rejection"]
  else Stitched_descriptor,"Metal.Function_stitching.Descriptor",["function/graph/archive same-device checks";"failure unwind";"compile completion retention"] in
 {id;lane;package;operation;tests}
let validate items=
 let count lane=List.length(List.filter(fun x->x.lane=lane)items)in
 let count_package p=List.length(List.filter(fun x->x.package=p)items)in
 if List.length items<>43||count Mechanical<>3||count Ownership<>33||count Metadata<>7
    || List.map count_package [Options;Input_node;Function_node;Graph;Stitched_descriptor;Type_metadata]<>[3;1;10;13;9;7]
    || List.exists(fun x->x.operation=""||x.tests=[])items
 then failwith"FunctionStitching43 handoff drift"
