(* First safe/public qualification slice from the exact 88-ID MTLDevice.h
   residual.  These are synchronous constructors or queries whose returned
   graph already has a concrete owned representation in Metal.  Callback-only
   constructors and process-global device observation intentionally remain in
   the residual until their cancellation/root ownership is integrated. *)

let ids =
  [ "method:-[MTLDevice accelerationStructureSizesWithDescriptor:]"
  ; "method:-[MTLDevice functionHandleWithBinaryFunction:]"
  ; "method:-[MTLDevice functionHandleWithFunction:]"
  ; "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithDescriptor:]"
  ; "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithSize:]"
  ; "method:-[MTLDevice newAccelerationStructureWithDescriptor:]"
  ; "method:-[MTLDevice newAccelerationStructureWithSize:]"
  ; "method:-[MTLDevice newArgumentEncoderWithArguments:]"
  ; "method:-[MTLDevice newCommandQueueWithDescriptor:]"
  ; "method:-[MTLDevice newCommandQueueWithMaxCommandBufferCount:]"
  ; "method:-[MTLDevice newCounterHeapWithDescriptor:error:]"
  ; "method:-[MTLDevice newCounterSampleBufferWithDescriptor:error:]"
  ; "method:-[MTLDevice newDefaultLibrary]"
  ; "method:-[MTLDevice newDefaultLibraryWithBundle:error:]"
  ; "method:-[MTLDevice newFence]"
  ; "method:-[MTLDevice newIOFileHandleWithURL:compressionMethod:error:]"
  ; "method:-[MTLDevice newIOHandleWithURL:compressionMethod:error:]"
  ; "method:-[MTLDevice newIOHandleWithURL:error:]"
  ; "method:-[MTLDevice newLibraryWithData:error:]"
  ; "method:-[MTLDevice newLibraryWithFile:error:]"
  ; "method:-[MTLDevice newLibraryWithStitchedDescriptor:error:]"
  ; "method:-[MTLDevice newLogStateWithDescriptor:error:]"
  ; "method:-[MTLDevice newMTL4CommandQueue]"
  ; "method:-[MTLDevice newRasterizationRateMapWithDescriptor:]"
  ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:error:]"
  ]

let already_safe_ids =
  [ "method:-[MTLDevice accelerationStructureSizesWithDescriptor:]"
  ; "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithDescriptor:]"
  ; "method:-[MTLDevice heapAccelerationStructureSizeAndAlignWithSize:]"
  ; "method:-[MTLDevice newAccelerationStructureWithDescriptor:]"
  ; "method:-[MTLDevice newAccelerationStructureWithSize:]"
  ; "method:-[MTLDevice newCounterHeapWithDescriptor:error:]"
  ; "method:-[MTLDevice newCounterSampleBufferWithDescriptor:error:]"
  ; "method:-[MTLDevice newFence]"
  ; "method:-[MTLDevice newIOFileHandleWithURL:compressionMethod:error:]"
  ; "method:-[MTLDevice newLogStateWithDescriptor:error:]"
  ; "method:-[MTLDevice newRasterizationRateMapWithDescriptor:]"
  ]

let missing_safe_ids =
  [ "method:-[MTLDevice newArgumentEncoderWithArguments:]"
  ; "method:-[MTLDevice functionHandleWithBinaryFunction:]"
  ; "method:-[MTLDevice functionHandleWithFunction:]"
  ; "method:-[MTLDevice newCommandQueueWithDescriptor:]"
  ; "method:-[MTLDevice newCommandQueueWithMaxCommandBufferCount:]"
  ; "method:-[MTLDevice newDefaultLibrary]"
  ; "method:-[MTLDevice newDefaultLibraryWithBundle:error:]"
  ; "method:-[MTLDevice newIOHandleWithURL:compressionMethod:error:]"
  ; "method:-[MTLDevice newIOHandleWithURL:error:]"
  ; "method:-[MTLDevice newLibraryWithData:error:]"
  ; "method:-[MTLDevice newLibraryWithFile:error:]"
  ; "method:-[MTLDevice newLibraryWithStitchedDescriptor:error:]" ]
  @ [ "method:-[MTLDevice newMTL4CommandQueue]"
    ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:error:]" ]

let lookalike_but_not_exact_ids =
  [ "method:-[MTLDevice functionHandleWithBinaryFunction:]",
      "public function-handle paths call MTLRenderPipelineState/MTLComputePipelineState selectors"
  ; "method:-[MTLDevice functionHandleWithFunction:]",
      "public function-handle paths call pipeline-state selectors"
  ; "method:-[MTLDevice newMTL4CommandQueue]",
      "public Metal 4 queue creation calls the descriptor/error selector"
  ; "method:-[MTLDevice newRenderPipelineStateWithDescriptor:error:]",
      "public render compilation calls the options/reflection/error selector" ]

type ownership =
  | Immutable_value
  | Owned_child
  | Nullable_owned_child

type obligation =
  { id : string
  ; ownership : ownership
  ; requires_same_device_graph : bool
  ; capability_gated : bool
  }

let obligations =
  List.map
    (fun id ->
      let value_query =
        String.contains id 'S'
        && (String.starts_with ~prefix:"method:-[MTLDevice accelerationStructureSizes" id
            || String.starts_with ~prefix:"method:-[MTLDevice heapAccelerationStructureSize" id)
      in
      { id
      ; ownership = if value_query then Immutable_value else Nullable_owned_child
      ; requires_same_device_graph =
          String.contains id ':'
          && not (String.ends_with ~suffix:"newDefaultLibrary]" id)
      ; capability_gated =
          String.contains id '4'
          || String.contains id 'I'
          || String.contains id 'R'
      })
    ids

let validate () =
  if List.length ids <> 25 then invalid_arg "Device residual safe slice cardinality drift";
  let sorted = List.sort_uniq String.compare ids in
  if List.length sorted <> List.length ids then
    invalid_arg "Device residual safe slice contains duplicate IDs";
  if List.exists (fun id -> String.ends_with ~suffix:"completionHandler:]" id) ids then
    invalid_arg "Device residual safe slice contains an unowned callback constructor";
  if List.map (fun item -> item.id) obligations <> ids then
    invalid_arg "Device residual obligation order drift";
  if List.length already_safe_ids <> 11 || List.length missing_safe_ids <> 14 then
    invalid_arg "Device residual safe/missing partition drift";
  if List.sort String.compare (already_safe_ids @ missing_safe_ids)
     <> List.sort String.compare ids
  then invalid_arg "Device residual safe/missing set equality drift";
  if
    List.map fst lookalike_but_not_exact_ids
    |> List.exists (fun id -> List.mem id already_safe_ids)
  then invalid_arg "Device lookalike selector was incorrectly treated as exact"
