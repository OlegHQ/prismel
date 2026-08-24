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
  let pass = ids "Metal/MTL4RenderPass.h"|>List.filter(fun id->contains(String.lowercase_ascii id)"samplepositions"||contains(String.lowercase_ascii id)"rasterizationratemap"||id="method:-[MTL4RenderPassDescriptor setDepthAttachment:]"||id="method:-[MTL4RenderPassDescriptor setStencilAttachment:]") and buffer = ids "Metal/MTL4CommandBuffer.h"|>List.filter(fun id->List.mem id ["class:MTL4CommandBufferOptions";"method:-[MTL4CommandBuffer beginCommandBufferWithAllocator:options:]";"method:-[MTL4CommandBuffer machineLearningCommandEncoder]";"method:-[MTL4CommandBuffer renderCommandEncoderWithDescriptor:options:]";"method:-[MTL4CommandBufferOptions logState]";"method:-[MTL4CommandBufferOptions setLogState:]";"property:MTL4CommandBufferOptions:logState"])
  and compressor = ids "Metal/MTLIOCompressor.h"|>List.filter(fun id->contains id "function:"||id="typedef:MTLIOCompressionContext") and archive = ids "Metal/MTLBinaryArchive.h"|>List.filter(fun id->List.mem id ["method:-[MTLBinaryArchive addFunctionWithDescriptor:library:error:]";"method:-[MTLBinaryArchive addLibraryWithDescriptor:error:]";"method:-[MTLBinaryArchive addMeshRenderPipelineFunctionsWithDescriptor:error:]";"method:-[MTLBinaryArchive addRenderPipelineFunctionsWithDescriptor:error:]";"method:-[MTLBinaryArchive addTileRenderPipelineFunctionsWithDescriptor:error:]"])
  and ml = ids "Metal/MTL4MachineLearningPipeline.h"|>List.filter(fun id->List.mem id ["method:-[MTL4MachineLearningPipelineState label]";"property:MTL4MachineLearningPipelineState:label";"class:MTL4MachineLearningPipelineDescriptor";"class:MTL4MachineLearningPipelineReflection";"protocol:MTL4MachineLearningPipelineState"]) and compute = ids "Metal/MTL4ComputeCommandEncoder.h"|>List.filter(fun id->List.mem id ["method:-[MTL4ComputeCommandEncoder buildAccelerationStructure:descriptor:scratchBuffer:]";"method:-[MTL4ComputeCommandEncoder copyFromTensor:sourceOrigin:sourceDimensions:toTensor:destinationOrigin:destinationDimensions:]";"method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:]";"method:-[MTL4ComputeCommandEncoder refitAccelerationStructure:descriptor:destination:scratchBuffer:options:]";"method:-[MTL4ComputeCommandEncoder writeCompactedAccelerationStructureSize:toBuffer:]"]) in
  if List.length pass <> 7 || count "samplepositions" pass <> 2 || count "rasterizationratemap" pass <> 3
     || count "attachment:" pass <> 2 then fail "MTL4RenderPass7 drift";
  if List.length buffer <> 7 || count "logstate" buffer <> 3 || count "commandencoder" buffer <> 2
     || count "begincommandbuffer" buffer <> 1 || count "class:" buffer <> 1 then fail "MTL4CommandBuffer7 drift";
  if List.length compressor <> 5 || count "function:" compressor <> 4 || count "typedef:" compressor <> 1
  then fail "IOCompressor5 drift";
  if List.length archive <> 5 || count "method:" archive <> 5 then fail "BinaryArchive5 drift";
  if List.length ml <> 5 || count "class:" ml <> 2 || count "label" ml <> 2 || count "protocol:" ml <> 1
  then fail "MTL4MachineLearningPipeline5 drift";
  if List.length compute <> 5 || count "accelerationstructure" compute <> 4 || count "copyfromtensor" compute <> 1
  then fail "MTL4ComputeEncoder5 drift";
  Printf.printf "Five-plus tails: MTL4Pass7 sample2/rate-map3/attachments2; MTL4Buffer7 options4/encoder2/begin1; IOCompressor5 context lifecycle; BinaryArchive5 owned descriptor additions; MTL4MLPipeline5 metadata3/label2; MTL4Compute5 AS4/tensor1\n%!"
