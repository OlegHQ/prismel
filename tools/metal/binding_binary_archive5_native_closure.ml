let ids =
  [ "method:-[MTLBinaryArchive addFunctionWithDescriptor:library:error:]"
  ; "method:-[MTLBinaryArchive addLibraryWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addMeshRenderPipelineFunctionsWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addRenderPipelineFunctionsWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addTileRenderPipelineFunctionsWithDescriptor:error:]" ]

let () =
  if List.length ids <> 5 || List.length (List.sort_uniq String.compare ids) <> 5
  then invalid_arg "BinaryArchive5 native closure drift"
