type resource = Fence | Depth_attachment | Stencil_attachment | Heap
              | Buffer_resource | Texture_resource | Indirect_command_buffer
              | Indirect_range_buffer

type check = Encoder_open | Same_device | Range | Capability | Attachment_present
           | Retain_resource | Pipeline_supports_icb

type entry =
  { id : string
  ; safe_name : string
  ; resources : resource list
  ; checks : check list
  ; deprecated_alias : bool
  }

let entries =
  [ { id="method:-[MTLRenderCommandEncoder memoryBarrierWithResources:count:afterStages:beforeStages:]"; safe_name="memory_barrier_resources"; resources=[Buffer_resource;Texture_resource]; checks=[Encoder_open;Same_device;Range;Capability;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder memoryBarrierWithScope:afterStages:beforeStages:]"; safe_name="memory_barrier"; resources=[]; checks=[Encoder_open;Range;Capability]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder textureBarrier]"; safe_name="memory_barrier"; resources=[]; checks=[Encoder_open;Capability]; deprecated_alias=true }
  ; { id="method:-[MTLRenderCommandEncoder updateFence:afterStages:]"; safe_name="update_fence"; resources=[Fence]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder waitForFence:beforeStages:]"; safe_name="wait_for_fence"; resources=[Fence]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder setDepthStoreAction:]"; safe_name="set_depth_store_action"; resources=[Depth_attachment]; checks=[Encoder_open;Attachment_present;Range]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder setDepthStoreActionOptions:]"; safe_name="set_depth_store_options"; resources=[Depth_attachment]; checks=[Encoder_open;Attachment_present;Range]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder setStencilStoreAction:]"; safe_name="set_stencil_store_action"; resources=[Stencil_attachment]; checks=[Encoder_open;Attachment_present;Range]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder setStencilStoreActionOptions:]"; safe_name="set_stencil_store_options"; resources=[Stencil_attachment]; checks=[Encoder_open;Attachment_present;Range]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder useHeap:]"; safe_name="use_heap"; resources=[Heap]; checks=[Encoder_open;Same_device;Retain_resource]; deprecated_alias=true }
  ; { id="method:-[MTLRenderCommandEncoder useHeap:stages:]"; safe_name="use_heap"; resources=[Heap]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder useHeaps:count:]"; safe_name="use_heaps"; resources=[Heap]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=true }
  ; { id="method:-[MTLRenderCommandEncoder useHeaps:count:stages:]"; safe_name="use_heaps"; resources=[Heap]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder useResource:usage:]"; safe_name="use_resource"; resources=[Buffer_resource;Texture_resource]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=true }
  ; { id="method:-[MTLRenderCommandEncoder useResource:usage:stages:]"; safe_name="use_resource"; resources=[Buffer_resource;Texture_resource]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder useResources:count:usage:]"; safe_name="use_resources"; resources=[Buffer_resource;Texture_resource]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=true }
  ; { id="method:-[MTLRenderCommandEncoder useResources:count:usage:stages:]"; safe_name="use_resources"; resources=[Buffer_resource;Texture_resource]; checks=[Encoder_open;Same_device;Range;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder executeCommandsInBuffer:withRange:]"; safe_name="execute_indirect_commands"; resources=[Indirect_command_buffer]; checks=[Encoder_open;Same_device;Range;Pipeline_supports_icb;Retain_resource]; deprecated_alias=false }
  ; { id="method:-[MTLRenderCommandEncoder executeCommandsInBuffer:indirectBuffer:indirectBufferOffset:]"; safe_name="execute_indirect_commands_indirect_range"; resources=[Indirect_command_buffer;Indirect_range_buffer]; checks=[Encoder_open;Same_device;Range;Pipeline_supports_icb;Retain_resource]; deprecated_alias=false }
  ]

let expected_count = 19
let () =
  if List.length entries <> expected_count then invalid_arg "render resource plan count drift";
  if List.length (List.sort_uniq String.compare (List.map (fun e -> e.id) entries)) <> expected_count
  then invalid_arg "render resource plan contains duplicate inventory IDs"
