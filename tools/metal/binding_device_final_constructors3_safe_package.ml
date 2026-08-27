let ids=
  [ "method:-[MTLDevice newArgumentEncoderWithBufferBinding:]"
  ; "method:-[MTLDevice newComputePipelineStateWithFunction:options:reflection:error:]"
  ; "method:-[MTLDevice newSharedEventWithHandle:]" ]
let validate()=if List.length(List.sort_uniq String.compare ids)<>3 then invalid_arg"Device constructors3 drift"
