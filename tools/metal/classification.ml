type t =
  | Bound
  | Availability_gated
  | Scope_excluded
  | Unreviewed

module String_set = Set.Make (String)

let methods owners =
  List.concat_map
    (fun (owner, selectors) ->
      List.map (fun selector -> "method:-[" ^ owner ^ " " ^ selector ^ "]")
        selectors)
    owners

let properties owners =
  List.concat_map
    (fun (owner, names) ->
      List.map (fun property -> "property:" ^ owner ^ ":" ^ property) names)
    owners

let enum_cases owner names =
  List.map (fun name -> "enum-case:" ^ owner ^ ":" ^ name) names

let bound_identifiers =
  [ "class:MTLCompileOptions"
  ; "enum:MTLCommandBufferStatus"
  ; "enum:MTLGPUFamily"
  ; "enum:MTLResourceOptions"
  ; "enum:MTLStorageMode"
  ; "function:MTLCopyAllDevices"
  ; "function:MTLCreateSystemDefaultDevice"
  ; "function:MTLSizeMake"
  ; "record:MTLSize"
  ; "field:MTLSize:width"
  ; "field:MTLSize:height"
  ; "field:MTLSize:depth"
  ; "protocol:MTLBuffer"
  ; "protocol:MTLCommandBuffer"
  ; "protocol:MTLCommandEncoder"
  ; "protocol:MTLCommandQueue"
  ; "protocol:MTLComputeCommandEncoder"
  ; "protocol:MTLComputePipelineState"
  ; "protocol:MTLDevice"
  ; "protocol:MTLFunction"
  ; "protocol:MTLLibrary"
  ; "protocol:MTLResource"
  ; "typedef:MTLCommandBufferStatus"
  ; "typedef:MTLGPUFamily"
  ; "typedef:MTLResourceOptions"
  ; "typedef:MTLSize"
  ; "typedef:MTLStorageMode"
  ]
  @ methods
      [ ( "MTLBuffer"
        , [ "contents"; "didModifyRange:"; "length" ] )
      ; ( "MTLCommandBuffer"
        , [ "commit"; "computeCommandEncoder"; "error"; "label"; "setLabel:"
          ; "status"; "waitUntilCompleted"
          ] )
      ; "MTLCommandEncoder", [ "endEncoding" ]
      ; ( "MTLCompileOptions"
        , [ "fastMathEnabled"; "setFastMathEnabled:" ] )
      ; ( "MTLComputeCommandEncoder"
        , [ "dispatchThreads:threadsPerThreadgroup:"
          ; "setBuffer:offset:atIndex:"
          ; "setComputePipelineState:"
          ] )
      ; ( "MTLComputePipelineState"
        , [ "maxTotalThreadsPerThreadgroup"; "threadExecutionWidth" ] )
      ; ( "MTLDevice"
        , [ "currentAllocatedSize"; "hasUnifiedMemory"; "isHeadless"
          ; "isLowPower"; "isRemovable"; "maxBufferLength"; "name"
          ; "newBufferWithLength:options:"; "newCommandQueue"
          ; "newComputePipelineStateWithFunction:error:"
          ; "newLibraryWithSource:options:error:"
          ; "recommendedMaxWorkingSetSize"; "registryID"
          ; "supportsDynamicLibraries"; "supportsFamily:"
          ; "supportsFunctionPointers"; "supportsRaytracing"
          ; "supportsRaytracingFromRender"
          ] )
      ; "MTLFunction", [ "name" ]
      ; "MTLLibrary", [ "newFunctionWithName:" ]
      ; "MTLResource", [ "label"; "setLabel:"; "storageMode" ]
      ; "MTLCommandQueue", [ "commandBuffer" ]
      ]
  @ properties
      [ ( "MTLCommandBuffer", [ "error"; "label"; "status" ] )
      ; "MTLCompileOptions", [ "fastMathEnabled" ]
      ; ( "MTLComputePipelineState"
        , [ "maxTotalThreadsPerThreadgroup"; "threadExecutionWidth" ] )
      ; ( "MTLDevice"
        , [ "currentAllocatedSize"; "hasUnifiedMemory"; "headless"; "lowPower"
          ; "maxBufferLength"; "name"; "recommendedMaxWorkingSetSize"
          ; "registryID"; "removable"; "supportsDynamicLibraries"
          ; "supportsFunctionPointers"; "supportsRaytracing"
          ; "supportsRaytracingFromRender"
          ] )
      ; "MTLFunction", [ "name" ]
      ; "MTLResource", [ "label"; "storageMode" ]
      ; "MTLBuffer", [ "length" ]
      ]
  @ enum_cases "MTLGPUFamily"
      [ "MTLGPUFamilyApple1"; "MTLGPUFamilyApple2"; "MTLGPUFamilyApple3"
      ; "MTLGPUFamilyApple4"; "MTLGPUFamilyApple5"; "MTLGPUFamilyApple6"
      ; "MTLGPUFamilyApple7"; "MTLGPUFamilyApple8"; "MTLGPUFamilyApple9"
      ; "MTLGPUFamilyApple10"; "MTLGPUFamilyMac2"; "MTLGPUFamilyCommon1"
      ; "MTLGPUFamilyCommon2"; "MTLGPUFamilyCommon3"; "MTLGPUFamilyMetal3"
      ; "MTLGPUFamilyMetal4"
      ]
  @ enum_cases "MTLStorageMode"
      [ "MTLStorageModeShared"; "MTLStorageModeManaged"; "MTLStorageModePrivate" ]
  @ enum_cases "MTLResourceOptions"
      [ "MTLResourceStorageModeShared"; "MTLResourceStorageModeManaged"
      ; "MTLResourceStorageModePrivate"
      ]
  @ enum_cases "MTLCommandBufferStatus"
      [ "MTLCommandBufferStatusNotEnqueued"; "MTLCommandBufferStatusEnqueued"
      ; "MTLCommandBufferStatusCommitted"; "MTLCommandBufferStatusScheduled"
      ; "MTLCommandBufferStatusCompleted"; "MTLCommandBufferStatusError"
      ]

let bound_identifier_set = String_set.of_list bound_identifiers

let name = function
  | Bound -> "bound"
  | Availability_gated -> "availability-gated"
  | Scope_excluded -> "scope-excluded"
  | Unreviewed -> "unreviewed"

let classify ~unavailable ~identifier =
  if unavailable then
    Scope_excluded, "Clang marks this declaration unavailable for macOS."
  else if String_set.mem identifier bound_identifier_set then
    Bound, "Implemented by the ownership-aware prismel.metal safe layer."
  else Unreviewed, "Binding classification pending during Phase 2."
