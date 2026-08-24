module S = Set.Make (String)
let fail format = Printf.ksprintf failwith format
let member name = function `Assoc values -> List.assoc_opt name values | _ -> None
let string name value = match member name value with Some (`String text) -> text | _ -> fail "missing %s" name

let expected =
  [ "Metal/MTL4ArgumentTable.h\tmethod:-[MTL4ArgumentTable setResource:atBufferIndex:]"
  ; "Metal/MTL4BufferRange.h\tfunction:MTL4BufferRangeMake"
  ; "Metal/MTL4BufferRange.h\ttypedef:MTL4BufferRange"
  ; "Metal/MTL4Compiler.h\tmethod:-[MTL4Compiler newMachineLearningPipelineStateWithDescriptor:completionHandler:]"
  ; "Metal/MTL4Compiler.h\ttypedef:MTL4NewMachineLearningPipelineStateCompletionHandler"
  ; "Metal/MTL4ComputePipeline.h\tmethod:-[MTL4ComputePipelineDescriptor reset]"
  ; "Metal/MTL4LinkingDescriptor.h\tclass:MTL4BinaryFunction"
  ; "Metal/MTL4LinkingDescriptor.h\tclass:MTLDynamicLibrary"
  ; "Metal/MTL4PipelineState.h\tenum-case:MTL4BlendState:MTL4BlendStateUnspecialized"
  ; "Metal/MTL4PipelineState.h\tenum-case:MTL4ShaderReflection:MTL4ShaderReflectionNone"
  ; "Metal/MTL4SpecializedFunctionDescriptor.h\tclass:MTL4SpecializedFunctionDescriptor"
  ; "Metal/MTLDepthStencil.h\tmethod:-[MTLDepthStencilState gpuResourceID]"
  ; "Metal/MTLDepthStencil.h\tproperty:MTLDepthStencilState:gpuResourceID"
  ; "Metal/MTLResource.h\tenum-case:MTLStorageMode:MTLStorageModeMemoryless"
  ; "Metal/MTLResourceStateCommandEncoder.h\ttypedef:MTLMapIndirectArguments"
  ; "Metal/MTLResourceViewPool.h\tprotocol:MTLResourceViewPool"
  ; "Metal/MTLTexture.h\trecord:MTLSharedTextureHandlePrivate"
  ; "Metal/MTLTextureViewPool.h\tprotocol:MTLTextureViewPool"
  ; "Metal/MTLVertexDescriptor.h\tenum-case:MTLVertexFormat:MTLVertexFormatInvalid"
  ; "Metal/MTLVisibleFunctionTable.h\tmethod:-[MTLVisibleFunctionTable setFunctions:withRange:]"
  ]

let () =
  if Array.length Sys.argv <> 2 then fail "usage: %s INVENTORY" Sys.argv.(0);
  let symbols = match member "symbols" (Yojson.Safe.from_file Sys.argv.(1)) with Some (`List xs) -> xs | _ -> fail "symbols" in
  let counts = Hashtbl.create 32 in
  List.iter (fun symbol -> if string "classification" symbol = "unreviewed" then let h = string "header" symbol in Hashtbl.replace counts h (1 + Option.value ~default:0 (Hashtbl.find_opt counts h))) symbols;
  let actual = symbols |> List.filter (fun symbol -> string "classification" symbol = "unreviewed" && Option.value ~default:0 (Hashtbl.find_opt counts (string "header" symbol)) <= 2) |> List.map (fun symbol -> string "header" symbol ^ "\t" ^ string "id" symbol) |> S.of_list in
  let expected = S.of_list expected in
  if not (S.equal actual expected) then fail "one/two-ID tail closure drift";
  Printf.printf "One/two-ID tails: exact 20 IDs across 15 headers (values6, metadata6, ownership/effect8)\n%!"
