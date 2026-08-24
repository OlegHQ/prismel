let fail format = Printf.ksprintf failwith format
let member name = function `Assoc values -> List.assoc_opt name values | _ -> None
let string name value = match member name value with Some (`String text) -> text | _ -> fail "missing %s" name
let contains haystack needle =
  let n = String.length needle in
  let rec loop i = i + n <= String.length haystack && (String.sub haystack i n = needle || loop (i + 1)) in loop 0

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let symbols = match member "symbols" (Yojson.Safe.from_file Sys.argv.(1)) with Some (`List xs) -> xs | _ -> fail "symbols" in
  let ids header = symbols |> List.filter (fun symbol -> let c=string "classification" symbol in (c="unreviewed"||c="bound") && string "header" symbol = header) |> List.map (string "id") in
  let count needle ids = List.length (List.filter (fun id -> contains (String.lowercase_ascii id) needle) ids) in
  let constants = ids "Metal/MTLFunctionConstantValues.h"|>List.filter(fun id->List.mem id ["method:-[MTLFunctionConstantValues reset]";"method:-[MTLFunctionConstantValues setConstantValue:type:atIndex:]";"method:-[MTLFunctionConstantValues setConstantValues:type:withRange:]"])
  and stitching = ids "Metal/MTL4StitchedFunctionDescriptor.h"|>List.filter(fun id->List.mem id ["class:MTL4StitchedFunctionDescriptor";"method:-[MTL4StitchedFunctionDescriptor setFunctionGraph:]";"property:MTL4StitchedFunctionDescriptor:functionGraph"])
  and render = ids "Metal/MTL4RenderPipeline.h"|>List.filter(fun id->List.mem id ["class:MTL4RenderPipelineBinaryFunctionsDescriptor";"method:-[MTL4RenderPipelineColorAttachmentDescriptor reset]";"method:-[MTL4RenderPipelineColorAttachmentDescriptorArray reset]"])
  and counters = ids "Metal/MTL4Counters.h"|>List.filter(fun id->List.mem id ["class:MTL4CounterHeapDescriptor";"protocol:MTL4CounterHeap";"typedef:MTL4TimestampHeapEntry"])
  and encoder = ids "Metal/MTL4CommandEncoder.h"|>List.filter(fun id->List.mem id ["enum-case:MTL4VisibilityOptions:MTL4VisibilityOptionDevice";"enum-case:MTL4VisibilityOptions:MTL4VisibilityOptionResourceAlias";"method:-[MTL4CommandEncoder waitForFence:beforeEncoderStages:]"]) in
  if List.length constants <> 3 || count "setconstant" constants <> 2 || count " reset]" constants <> 1
  then fail "FunctionConstantValues3 drift";
  if List.length stitching <> 3 || count "class:" stitching <> 1 || count "functiongraph" stitching <> 2
  then fail "MTL4StitchedDescriptor3 drift";
  if List.length render <> 3 || count "class:" render <> 1 || count " reset]" render <> 2
  then fail "MTL4RenderPipeline3 drift";
  if List.length counters <> 3 || count "class:" counters <> 1 || count "protocol:" counters <> 1 || count "typedef:" counters <> 1
  then fail "MTL4Counters3 drift";
  if List.length encoder <> 3 || count "enum-case:" encoder <> 2 || count "waitforfence:" encoder <> 1
  then fail "MTL4CommandEncoder3 drift";
  Printf.printf "Three-ID tails: constants writes/reset3; stitched graph ownership2/metadata1; render resets2/metadata1; counters value1/metadata2; visibility values2/fence wait1\n%!"
