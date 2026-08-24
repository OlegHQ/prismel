type lane = Enum_case | Fixed_alias | Scalar_alias | Constructor
type item = { id : string; lane : lane }

let enum_ids =
  [ "enum-case:MTL4BlendState:MTL4BlendStateUnspecialized"
  ; "enum-case:MTL4ShaderReflection:MTL4ShaderReflectionNone"
  ; "enum-case:MTL4VisibilityOptions:MTL4VisibilityOptionDevice"
  ; "enum-case:MTL4VisibilityOptions:MTL4VisibilityOptionNone"
  ; "enum-case:MTLBlendFactor:MTLBlendFactorUnspecialized"
  ; "enum-case:MTLBlendOperation:MTLBlendOperationUnspecialized"
  ; "enum-case:MTLColorWriteMask:MTLColorWriteMaskUnspecialized"
  ; "enum-case:MTLGPUFamily:MTLGPUFamilyMac1"
  ; "enum-case:MTLGPUFamily:MTLGPUFamilyMacCatalyst1"
  ; "enum-case:MTLGPUFamily:MTLGPUFamilyMacCatalyst2"
  ; "enum-case:MTLPrimitiveTopologyClass:MTLPrimitiveTopologyClassUnspecified"
  ; "enum-case:MTLStorageMode:MTLStorageModeMemoryless"
  ; "enum-case:MTLVertexFormat:MTLVertexFormatInvalid"
  ; "enum-case:MTLStoreAction:MTLStoreActionCustomSampleDepthStore"
  ; "enum-case:MTLStoreAction:MTLStoreActionMultisampleResolve"
  ; "enum-case:MTLStoreAction:MTLStoreActionStoreAndMultisampleResolve"
  ]

let fixed_alias_ids =
  [ "typedef:MTL4BufferRange"; "typedef:MTL4CopySparseBufferMappingOperation"
  ; "typedef:MTL4CopySparseTextureMappingOperation"; "typedef:MTL4TimestampHeapEntry"
  ; "typedef:MTLAccelerationStructureInstanceDescriptor"
  ; "typedef:MTLAccelerationStructureMotionInstanceDescriptor"
  ; "typedef:MTLAccelerationStructureSizes"
  ; "typedef:MTLAccelerationStructureUserIDInstanceDescriptor"
  ; "typedef:MTLDispatchThreadgroupsIndirectArguments"
  ; "typedef:MTLDispatchThreadsIndirectArguments"; "typedef:MTLDrawPatchIndirectArguments"
  ; "typedef:MTLIndirectAccelerationStructureInstanceDescriptor"
  ; "typedef:MTLIndirectAccelerationStructureMotionInstanceDescriptor"
  ; "typedef:MTLIndirectCommandBufferExecutionRange"
  ; "typedef:MTLIntersectionFunctionBufferArguments"; "typedef:MTLMapIndirectArguments"
  ; "typedef:MTLQuadTessellationFactorsHalf"; "typedef:MTLSamplePosition"
  ; "typedef:MTLStageInRegionIndirectArguments"; "typedef:MTLTriangleTessellationFactorsHalf"
  ]

let scalar_alias_ids =
  [ "typedef:MTLArgumentAccess"; "typedef:MTLIndexType"
  ; "typedef:MTLTimestamp"; "typedef:MTLCoordinate2D" ]

let constructor_ids =
  [ "function:MTL4BufferRangeMake"; "function:MTLCoordinate2DMake"
  ; "function:MTLIndirectCommandBufferExecutionRangeMake"
  ; "function:MTLRegionMake1D"; "function:MTLRegionMake2D"
  ; "function:MTLSamplePositionMake" ]

let items =
  List.map (fun id -> { id; lane = Enum_case }) enum_ids
  @ List.map (fun id -> { id; lane = Fixed_alias }) fixed_alias_ids
  @ List.map (fun id -> { id; lane = Scalar_alias }) scalar_alias_ids
  @ List.map (fun id -> { id; lane = Constructor }) constructor_ids

let excluded =
  [ "typedef:MTLDrawIndexedPrimitivesIndirectArguments"
  ; "typedef:MTLDrawPrimitivesIndirectArguments"
  ; "reason:records are not represented by the generated public Value module"
  ; "callbacks, Objective-C pointers, private records, and IO compressor context operations"
  ]

let validate () =
  let count lane = List.length (List.filter (fun item -> item.lane = lane) items) in
  if List.length items <> 46 || count Enum_case <> 16 || count Fixed_alias <> 20
     || count Scalar_alias <> 4 || count Constructor <> 6
     || List.length (List.sort_uniq String.compare (List.map (fun item -> item.id) items)) <> 46
  then invalid_arg "pure mechanical tail plan drift"
