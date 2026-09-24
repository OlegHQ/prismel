let promotable_ids =
  [ "method:-[MTLBinaryArchive addLibraryWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addMeshRenderPipelineFunctionsWithDescriptor:error:]"
  ; "method:-[MTLBinaryArchive addTileRenderPipelineFunctionsWithDescriptor:error:]" ]

let validate () =
  if List.length promotable_ids <> 3
     || List.length (List.sort_uniq String.compare promotable_ids) <> 3
  then failwith "BinaryArchive residual exact3 drift"

let () = validate ()
