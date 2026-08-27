let ids =
  [ "method:-[MTLDevice functionHandleWithBinaryFunction:]"
  ; "method:-[MTLDevice functionHandleWithFunction:]"
  ; "method:-[MTLDevice newArgumentEncoderWithArguments:]"
  ; "method:-[MTLDevice newIOHandleWithURL:compressionMethod:error:]"
  ; "method:-[MTLDevice newIOHandleWithURL:error:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:error:]" ]

let io_alias_ids = List.filter (fun id -> String.contains id 'I') ids

let validate () =
  if List.length ids <> 6 || List.length (List.sort_uniq String.compare ids) <> 6 then
    invalid_arg "Device remaining6 exact set drift";
  if List.length io_alias_ids <> 2 then invalid_arg "Device legacy IO2 partition drift"
