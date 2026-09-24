type status = Promotable | Blocked of string
type item = { id:string; public_operation:string; required_test:string; status:status }

let attributes owner =
  [ "active"; "attributeIndex"; "attributeType"; "name"
  ; "patchControlPointData"; "patchData" ]
  |> List.concat_map (fun name ->
       [ "method:-[" ^ owner ^ " " ^ (if name = "active" then "isActive" else if name = "patchControlPointData" then "isPatchControlPointData" else if name = "patchData" then "isPatchData" else name) ^ "]"
       ; "property:" ^ owner ^ ":" ^ name ])

let promotable_ids =
  ([ "method:-[MTLFunction options]"; "property:MTLFunction:options"
   ; "method:-[MTLFunction patchControlPointCount]"; "property:MTLFunction:patchControlPointCount"
   ; "method:-[MTLFunction patchType]"; "property:MTLFunction:patchType"
   ; "method:-[MTLAttributeDescriptor bufferIndex]"; "property:MTLAttributeDescriptor:bufferIndex"; "method:-[MTLAttributeDescriptor setBufferIndex:]"
   ; "method:-[MTLAttributeDescriptor offset]"; "property:MTLAttributeDescriptor:offset"; "method:-[MTLAttributeDescriptor setOffset:]"
   ; "method:-[MTLAttributeDescriptor format]"; "property:MTLAttributeDescriptor:format"; "method:-[MTLAttributeDescriptor setFormat:]"
   ; "method:+[MTLStageInputOutputDescriptor stageInputOutputDescriptor]"
   ; "method:-[MTLStageInputOutputDescriptor indexBufferIndex]"; "property:MTLStageInputOutputDescriptor:indexBufferIndex"; "method:-[MTLStageInputOutputDescriptor setIndexBufferIndex:]"
   ; "method:-[MTLStageInputOutputDescriptor indexType]"; "property:MTLStageInputOutputDescriptor:indexType"; "method:-[MTLStageInputOutputDescriptor setIndexType:]"
   ; "method:-[MTLFunctionStitchingInputNode argumentIndex]"; "property:MTLFunctionStitchingInputNode:argumentIndex"; "method:-[MTLFunctionStitchingInputNode setArgumentIndex:]"
   ] @ attributes "MTLVertexAttribute")
  |> List.sort_uniq String.compare

let contains text needle =
  let n=String.length needle in
  let rec loop i=i+n<=String.length text && (String.sub text i n=needle || loop(i+1)) in loop 0

let public_operation id =
  if contains id "MTLFunction " || contains id "property:MTLFunction:" then "Metal.Function metadata query"
  else if contains id "MTLVertexAttribute" then "Metal.Shader_attribute query (vertex)"
  else if contains id "MTLAttributeDescriptor" then "Metal.Shader_attribute_descriptor get/set"
  else if contains id "MTLStageInputOutputDescriptor" then "Metal.Shader_stage_descriptor create/get/set"
  else if contains id "MTLFunctionStitchingInputNode" then "Metal.Shader_stitching_input get/set"
  else "missing public Shader157 operation"

let required_test id =
  if contains id "set" || contains id "stageInputOutputDescriptor" then
    "invalid input rejection, exact round trip, destroy/parent ownership"
  else "exact native getter, destroyed rejection, handle-kind conformance"

let items = List.map (fun id ->
  {id;public_operation=public_operation id;required_test=required_test id;
   status=if List.mem id promotable_ids then Promotable else Blocked "graph/callback/reflection ownership is not safely closed"})
  Binding_shader_graph_manifest.ids
let blocked=List.filter(fun x->match x.status with Blocked _->true|Promotable->false)items
let validate()=
  if List.length items<>157 || List.length promotable_ids<>37 || List.length blocked<>120 then failwith"Shader157 cardinality drift";
  let manifest=List.sort String.compare Binding_shader_graph_manifest.ids in
  if List.exists(fun id->not(List.mem id manifest))promotable_ids then failwith"Shader157 promotion escaped manifest"
let ()=validate()
