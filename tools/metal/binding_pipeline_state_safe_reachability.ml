type status = Promotable | Blocked of string

type item =
  { id : string
  ; public_operation : string
  ; required_test : string
  ; status : status
  }

let promotable_ids =
  [ "method:-[MTLComputePipelineState gpuResourceID]"
  ; "method:-[MTLComputePipelineState imageblockMemoryLengthForDimensions:]"
  ; "method:-[MTLComputePipelineState requiredThreadsPerThreadgroup]"
  ; "method:-[MTLComputePipelineState shaderValidation]"
  ; "method:-[MTLComputePipelineState supportIndirectCommandBuffers]"
  ; "method:-[MTLRenderPipelineState gpuResourceID]"
  ; "method:-[MTLRenderPipelineState imageblockMemoryLengthForDimensions:]"
  ; "method:-[MTLRenderPipelineState imageblockSampleLength]"
  ; "method:-[MTLRenderPipelineState maxTotalThreadsPerMeshThreadgroup]"
  ; "method:-[MTLRenderPipelineState maxTotalThreadsPerObjectThreadgroup]"
  ; "method:-[MTLRenderPipelineState requiredThreadsPerTileThreadgroup]"
  ; "method:-[MTLRenderPipelineState shaderValidation]"
  ; "method:-[MTLRenderPipelineState supportIndirectCommandBuffers]"
  ; "property:MTLComputePipelineState:gpuResourceID"
  ; "property:MTLComputePipelineState:requiredThreadsPerThreadgroup"
  ; "property:MTLComputePipelineState:shaderValidation"
  ; "property:MTLComputePipelineState:supportIndirectCommandBuffers"
  ; "property:MTLRenderPipelineState:gpuResourceID"
  ; "property:MTLRenderPipelineState:imageblockSampleLength"
  ; "property:MTLRenderPipelineState:maxTotalThreadsPerMeshThreadgroup"
  ; "property:MTLRenderPipelineState:maxTotalThreadsPerObjectThreadgroup"
  ; "property:MTLRenderPipelineState:requiredThreadsPerTileThreadgroup"
  ; "property:MTLRenderPipelineState:shaderValidation"
  ; "property:MTLRenderPipelineState:supportIndirectCommandBuffers"
  ] |> List.sort String.compare

let contains text needle =
  let length = String.length needle in
  let rec loop offset =
    offset + length <= String.length text
    && (String.sub text offset length = needle || loop (offset + 1))
  in
  loop 0

let public_operation id =
  let owner = if contains id "ComputePipelineState" then "Compute_pipeline" else "Render_pipeline" in
  let operation =
    if contains id "gpuResourceID" then "resource_id"
    else if contains id "requiredThreadsPerThreadgroup" then "required_threads_per_threadgroup"
    else if contains id "shaderValidation" then "shader_validation"
    else if contains id "supportIndirectCommandBuffers" then "supports_indirect_command_buffers"
    else if contains id "imageblockMemoryLengthForDimensions" then "imageblock_memory_length"
    else if contains id "imageblockSampleLength" then "imageblock_sample_length"
    else if contains id "MeshThreadgroup" then "mesh_threads_per_threadgroup"
    else if contains id "ObjectThreadgroup" then "object_threads_per_threadgroup"
    else if contains id "TileThreadgroup" then "tile_threads_per_threadgroup"
    else "missing public pipeline operation"
  in
  "Metal." ^ owner ^ "." ^ operation

let required_test id =
  if contains id "imageblockMemoryLength" then
    "positive-dimension validation, exact native result, destroyed rejection"
  else if contains id "shaderValidation" then
    "exhaustive enum mapping, unknown-code rejection, destroyed rejection"
  else
    "exact native getter/property result and destroyed rejection"

let item id =
  { id
  ; public_operation = public_operation id
  ; required_test = required_test id
  ; status =
      if List.mem id promotable_ids then Promotable
      else Blocked "descriptor/constructor/ownership graph lacks safe closure"
  }
