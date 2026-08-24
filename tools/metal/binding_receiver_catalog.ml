type owner_binding =
  | One_to_one
  | Distinct_role of string

type bridge_access =
  | Object_of_handle
  | Object_of_helper of string
  | Wrapped_property of
      { wrapper_type : string
      ; property : string
      }

type receiver =
  { sdk_owner : string
  ; objc_receiver_type : string
  ; handle_kind : string
  ; local_name : string
  ; raw_name : string
  ; owner_binding : owner_binding
  ; bridge_access : bridge_access
  }

type polymorphic_receiver =
  { sdk_owner : string
  ; objc_receiver_type : string
  ; accepted_handle_kinds : string list
  ; helper : string
  ; local_name : string
  ; raw_name : string
  }

type exclusion =
  { handle_kind : string
  ; reason : string
  }

let direct ?(owner_binding = One_to_one) sdk_owner objc_receiver_type
    handle_kind local_name : receiver =
  { sdk_owner
  ; objc_receiver_type
  ; handle_kind
  ; local_name
  ; raw_name = "raw_" ^ local_name
  ; owner_binding
  ; bridge_access = Object_of_handle
  }

let helper ?(owner_binding = One_to_one) sdk_owner objc_receiver_type
    handle_kind local_name helper_name : receiver =
  { sdk_owner
  ; objc_receiver_type
  ; handle_kind
  ; local_name
  ; raw_name = "raw_" ^ local_name
  ; owner_binding
  ; bridge_access = Object_of_helper helper_name
  }

let wrapped sdk_owner objc_receiver_type handle_kind local_name wrapper_type
    property : receiver =
  { sdk_owner
  ; objc_receiver_type
  ; handle_kind
  ; local_name
  ; raw_name = "raw_" ^ local_name
  ; owner_binding = One_to_one
  ; bridge_access = Wrapped_property { wrapper_type; property }
  }

let receivers =
  [ direct "MTLDevice" "id<MTLDevice>" "Device" "device"
  ; direct "MTLHeap" "id<MTLHeap>" "Heap" "heap"
  ; direct "MTLBuffer" "id<MTLBuffer>" "Buffer" "buffer"
  ; direct "MTLTexture" "id<MTLTexture>" "Texture" "texture"
  ; direct "MTLSamplerState" "id<MTLSamplerState>" "Sampler" "sampler"
  ; direct "MTLLibrary" "id<MTLLibrary>" "Library" "library"
  ; direct "MTLFunction" "id<MTLFunction>" "Function" "function"
  ; direct "MTLDynamicLibrary" "id<MTLDynamicLibrary>" "Dynamic_library"
      "dynamic_library"
  ; direct "MTLBinaryArchive" "id<MTLBinaryArchive>" "Binary_archive"
      "binary_archive"
  ; direct "MTLComputePipelineState" "id<MTLComputePipelineState>"
      "Compute_pipeline" "compute_pipeline"
  ; direct "MTLCommandQueue" "id<MTLCommandQueue>" "Command_queue"
      "command_queue"
  ; direct "MTLCommandBuffer" "id<MTLCommandBuffer>" "Command_buffer"
      "command_buffer"
  ; direct "MTLComputeCommandEncoder" "id<MTLComputeCommandEncoder>"
      "Compute_encoder" "compute_encoder"
  ; direct "MTLResourceStateCommandEncoder"
      "id<MTLResourceStateCommandEncoder>" "Resource_state_encoder"
      "resource_state_encoder"
  ; direct "MTLBlitCommandEncoder" "id<MTLBlitCommandEncoder>" "Blit_encoder"
      "blit_encoder"
  ; direct "MTLResidencySet" "id<MTLResidencySet>" "Residency_set"
      "residency_set"
  ; helper "MTLSharedTextureHandle" "MTLSharedTextureHandle *"
      "Shared_texture_handle" "shared_texture_handle"
      "shared_texture_handle_of_handle"
  ; helper ~owner_binding:(Distinct_role "placement_mapping")
      "MTL4CommandQueue" "id<MTL4CommandQueue>" "Placement_mapping_queue"
      "placement_mapping_queue" "placement_mapping_queue_of_handle"
  ; direct "MTL4PipelineDataSetSerializer"
      "id<MTL4PipelineDataSetSerializer>" "Pipeline_dataset"
      "pipeline_dataset"
  ; direct "MTL4Archive" "id<MTL4Archive>" "Pipeline_archive"
      "pipeline_archive"
  ; direct "MTL4Compiler" "id<MTL4Compiler>" "Compiler" "compiler"
  ; direct "MTL4BinaryFunction" "id<MTL4BinaryFunction>" "Binary_function"
      "binary_function"
  ; wrapped "MTL4CompilerTask" "id<MTL4CompilerTask>" "Compiler_task"
      "compiler_task" "PrismelMetalCompilerTaskState *" "task"
  ; direct "MTLRenderPipelineState" "id<MTLRenderPipelineState>"
      "Render_pipeline" "render_pipeline"
  ; direct "MTL4CommandAllocator" "id<MTL4CommandAllocator>"
      "Command_allocator4" "command_allocator4"
  ; direct ~owner_binding:(Distinct_role "general") "MTL4CommandQueue"
      "id<MTL4CommandQueue>" "Command_queue4" "command_queue4"
  ; wrapped "MTL4CommandBuffer" "id<MTL4CommandBuffer>" "Command_buffer4"
      "command_buffer4" "PrismelMetal4CommandBufferState *" "commandBuffer"
  ; direct "MTL4RenderCommandEncoder" "id<MTL4RenderCommandEncoder>"
      "Render_encoder4" "render_encoder4"
  ; wrapped "MTL4ArgumentTable" "id<MTL4ArgumentTable>" "Argument_table4"
      "argument_table4" "PrismelMetal4ArgumentTableState *" "argumentTable"
  ; direct "MTL4ComputeCommandEncoder" "id<MTL4ComputeCommandEncoder>"
      "Compute_encoder4" "compute_encoder4"
  ; direct "MTLDepthStencilState" "id<MTLDepthStencilState>" "Depth_stencil"
      "depth_stencil"
  ; direct "MTLRenderCommandEncoder" "id<MTLRenderCommandEncoder>"
      "Render_encoder" "render_encoder"
  ; direct "MTLIndirectCommandBuffer" "id<MTLIndirectCommandBuffer>"
      "Indirect_command_buffer" "indirect_command_buffer"
  ; direct "MTLIndirectRenderCommand" "id<MTLIndirectRenderCommand>"
      "Indirect_render_command" "indirect_render_command"
  ; direct "MTLIndirectComputeCommand" "id<MTLIndirectComputeCommand>"
      "Indirect_compute_command" "indirect_compute_command"
  ; direct "MTLAccelerationStructure" "id<MTLAccelerationStructure>"
      "Acceleration_structure" "acceleration_structure"
  ; direct "MTLAccelerationStructureCommandEncoder"
      "id<MTLAccelerationStructureCommandEncoder>" "Acceleration_encoder"
      "acceleration_encoder"
  ; direct "MTLFunctionHandle" "id<MTLFunctionHandle>" "Function_handle"
      "function_handle"
  ; direct "MTLVisibleFunctionTable" "id<MTLVisibleFunctionTable>"
      "Visible_function_table" "visible_function_table"
  ; direct "MTLIntersectionFunctionTable" "id<MTLIntersectionFunctionTable>"
      "Intersection_function_table" "intersection_function_table"
  ; direct "MTLFence" "id<MTLFence>" "Fence" "fence"
  ; direct "CAMetalLayer" "CAMetalLayer *" "Metal_layer" "metal_layer"
  ; direct "CAMetalDrawable" "id<CAMetalDrawable>" "Metal_drawable"
      "metal_drawable"
  ; direct "MTLRenderPassDescriptor" "MTLRenderPassDescriptor *"
      "Render_pass_descriptor" "render_pass_descriptor"
  ; direct "MTLAccelerationStructureBoundingBoxGeometryDescriptor" "MTLAccelerationStructureBoundingBoxGeometryDescriptor *" "Acceleration_bbox_descriptor" "acceleration_bbox_descriptor"
  ; direct "MTLAccelerationStructureCurveGeometryDescriptor" "MTLAccelerationStructureCurveGeometryDescriptor *" "Acceleration_curve_descriptor" "acceleration_curve_descriptor"
  ; direct "MTLIndirectInstanceAccelerationStructureDescriptor" "MTLIndirectInstanceAccelerationStructureDescriptor *" "Acceleration_indirect_instance_descriptor" "acceleration_indirect_instance_descriptor"
  ; direct "MTLInstanceAccelerationStructureDescriptor" "MTLInstanceAccelerationStructureDescriptor *" "Acceleration_instance_descriptor" "acceleration_instance_descriptor"
  ; direct "MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor" "MTLAccelerationStructureMotionBoundingBoxGeometryDescriptor *" "Acceleration_motion_bbox_descriptor" "acceleration_motion_bbox_descriptor"
  ; direct "MTLAccelerationStructureMotionCurveGeometryDescriptor" "MTLAccelerationStructureMotionCurveGeometryDescriptor *" "Acceleration_motion_curve_descriptor" "acceleration_motion_curve_descriptor"
  ; direct "MTLMotionKeyframeData" "MTLMotionKeyframeData *" "Acceleration_motion_keyframe" "acceleration_motion_keyframe"
  ; direct "MTLAccelerationStructureMotionTriangleGeometryDescriptor" "MTLAccelerationStructureMotionTriangleGeometryDescriptor *" "Acceleration_motion_triangle_descriptor" "acceleration_motion_triangle_descriptor"
  ; direct "MTLPrimitiveAccelerationStructureDescriptor" "MTLPrimitiveAccelerationStructureDescriptor *" "Acceleration_primitive_descriptor" "acceleration_primitive_descriptor"
  ; direct "MTLAccelerationStructureTriangleGeometryDescriptor" "MTLAccelerationStructureTriangleGeometryDescriptor *" "Acceleration_triangle_owned_descriptor" "acceleration_triangle_owned_descriptor"
  ; direct "MTLAccelerationStructurePassDescriptor" "MTLAccelerationStructurePassDescriptor *" "Acceleration_pass_descriptor" "acceleration_pass_descriptor"
  ; direct "MTLAccelerationStructurePassSampleBufferAttachmentDescriptor" "MTLAccelerationStructurePassSampleBufferAttachmentDescriptor *" "Acceleration_sample_attachment" "acceleration_sample_attachment"
  ; direct "MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray" "MTLAccelerationStructurePassSampleBufferAttachmentDescriptorArray *" "Acceleration_sample_attachment_array" "acceleration_sample_attachment_array"
  ; direct "MTL4RenderPipelineBinaryFunctionsDescriptor" "MTL4RenderPipelineBinaryFunctionsDescriptor *" "Binary_functions_descriptor4" "binary_functions_descriptor4"
  ; direct "MTLBlitPassDescriptor" "MTLBlitPassDescriptor *" "Blit_pass_descriptor" "blit_pass_descriptor"
  ; direct "MTLBlitPassSampleBufferAttachmentDescriptor" "MTLBlitPassSampleBufferAttachmentDescriptor *" "Blit_sample_attachment" "blit_sample_attachment"
  ; direct "MTLBlitPassSampleBufferAttachmentDescriptorArray" "MTLBlitPassSampleBufferAttachmentDescriptorArray *" "Blit_sample_attachment_array" "blit_sample_attachment_array"
  ; direct "MTLCaptureScope" "id<MTLCaptureScope>" "Capture_scope" "capture_scope"
  ; direct "MTL4RenderPipelineColorAttachmentDescriptorArray" "MTL4RenderPipelineColorAttachmentDescriptorArray *" "Color_attachment_array4" "color_attachment_array4"
  ; direct "MTL4RenderPipelineColorAttachmentDescriptor" "MTL4RenderPipelineColorAttachmentDescriptor *" "Color_attachment_descriptor4" "color_attachment_descriptor4"
  ; direct "MTL4CommandBufferOptions" "MTL4CommandBufferOptions *" "Command_buffer_options4" "command_buffer_options4"
  ; direct "MTL4CommandQueueDescriptor" "MTL4CommandQueueDescriptor *" "Command_queue_descriptor" "command_queue_descriptor"
  ; direct "MTLCompileOptions" "MTLCompileOptions *" "Compile_options" "compile_options"
  ; direct "MTLComputePassDescriptor" "MTLComputePassDescriptor *" "Compute_pass_descriptor" "compute_pass_descriptor"
  ; direct "MTLComputePassSampleBufferAttachmentDescriptor" "MTLComputePassSampleBufferAttachmentDescriptor *" "Compute_sample_attachment" "compute_sample_attachment"
  ; direct "MTLComputePassSampleBufferAttachmentDescriptorArray" "MTLComputePassSampleBufferAttachmentDescriptorArray *" "Compute_sample_attachment_array" "compute_sample_attachment_array"
  ; direct "MTLCounter" "id<MTLCounter>" "Counter" "counter"
  ; direct "MTLFunctionConstantValues" "MTLFunctionConstantValues *" "Function_constant_values" "function_constant_values"
  ; direct "MTL4FunctionDescriptor" "MTL4FunctionDescriptor *" "Function_descriptor4" "function_descriptor4"
  ; direct "MTLFunctionDescriptor" "MTLFunctionDescriptor *" "Function_descriptor" "function_descriptor"
  ; direct "MTLFunctionReflection" "MTLFunctionReflection *" "Function_reflection" "function_reflection"
  ; direct "MTLLogState" "id<MTLLogState>" "Log_state" "log_state"
  ; direct "MTLLogStateDescriptor" "MTLLogStateDescriptor *" "Log_state_descriptor" "log_state_descriptor"
  ; direct "MTL4MachineLearningPipelineDescriptor" "MTL4MachineLearningPipelineDescriptor *" "Machine_learning_descriptor4" "machine_learning_descriptor4"
  ; direct "MTL4MachineLearningCommandEncoder" "id<MTL4MachineLearningCommandEncoder>" "Machine_learning_encoder4" "machine_learning_encoder4"
  ; direct "MTL4MachineLearningPipelineState" "id<MTL4MachineLearningPipelineState>" "Machine_learning_pipeline4" "machine_learning_pipeline4"
  ; direct "MTLParallelRenderCommandEncoder" "id<MTLParallelRenderCommandEncoder>" "Parallel_render_encoder" "parallel_render_encoder"
  ; direct "MTLRasterizationRateMapDescriptor" "MTLRasterizationRateMapDescriptor *" "Raster_rate_descriptor" "raster_rate_descriptor"
  ; direct "MTLRasterizationRateLayerDescriptor" "MTLRasterizationRateLayerDescriptor *" "Raster_rate_layer" "raster_rate_layer"
  ; direct "MTLRasterizationRateLayerArray" "MTLRasterizationRateLayerArray *" "Raster_rate_layer_array" "raster_rate_layer_array"
  ; direct "MTLRasterizationRateMap" "id<MTLRasterizationRateMap>" "Raster_rate_map" "raster_rate_map"
  ; direct "MTLRasterizationRateSampleArray" "MTLRasterizationRateSampleArray *" "Raster_rate_sample_array" "raster_rate_sample_array"
  ; direct "MTL4RenderPassDescriptor" "MTL4RenderPassDescriptor *" "Render_pass_descriptor4" "render_pass_descriptor4"
  ; direct "MTLSharedEventHandle" "MTLSharedEventHandle *" "Shared_event_handle" "shared_event_handle"
  ; direct "MTLSharedEventListener" "MTLSharedEventListener *" "Shared_event_listener" "shared_event_listener"
  ; direct "MTL4SpecializedFunctionDescriptor" "MTL4SpecializedFunctionDescriptor *" "Specialized_function_descriptor4" "specialized_function_descriptor4"
  ; direct "MTL4StitchedFunctionDescriptor" "MTL4StitchedFunctionDescriptor *" "Stitched_function_descriptor4" "stitched_function_descriptor4"
  ; direct "MTLStitchedLibraryDescriptor" "MTLStitchedLibraryDescriptor *" "Stitched_library_descriptor" "stitched_library_descriptor"
  ; direct "MTLFunctionStitchingAttribute" "id<MTLFunctionStitchingAttribute>" "Stitching_attribute" "stitching_attribute"
  ; direct "MTLFunctionStitchingFunctionNode" "MTLFunctionStitchingFunctionNode *" "Stitching_function_node" "stitching_function_node"
  ; direct "MTLFunctionStitchingGraph" "MTLFunctionStitchingGraph *" "Stitching_graph" "stitching_graph"
  ; direct "MTLTensorExtents" "MTLTensorExtents *" "Tensor_extents" "tensor_extents"
  ; direct "MTL4AccelerationStructureBoundingBoxGeometryDescriptor" "MTL4AccelerationStructureBoundingBoxGeometryDescriptor *" "Acceleration4_bbox_descriptor" "acceleration4_bbox_descriptor"
  ; direct "MTL4AccelerationStructureCurveGeometryDescriptor" "MTL4AccelerationStructureCurveGeometryDescriptor *" "Acceleration4_curve_descriptor" "acceleration4_curve_descriptor"
  ; direct "MTL4IndirectInstanceAccelerationStructureDescriptor" "MTL4IndirectInstanceAccelerationStructureDescriptor *" "Acceleration4_indirect_instance_descriptor" "acceleration4_indirect_instance_descriptor"
  ; direct "MTL4InstanceAccelerationStructureDescriptor" "MTL4InstanceAccelerationStructureDescriptor *" "Acceleration4_instance_descriptor" "acceleration4_instance_descriptor"
  ; direct "MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor" "MTL4AccelerationStructureMotionBoundingBoxGeometryDescriptor *" "Acceleration4_motion_bbox_descriptor" "acceleration4_motion_bbox_descriptor"
  ; direct "MTL4AccelerationStructureMotionCurveGeometryDescriptor" "MTL4AccelerationStructureMotionCurveGeometryDescriptor *" "Acceleration4_motion_curve_descriptor" "acceleration4_motion_curve_descriptor"
  ; direct "MTL4AccelerationStructureMotionTriangleGeometryDescriptor" "MTL4AccelerationStructureMotionTriangleGeometryDescriptor *" "Acceleration4_motion_triangle_descriptor" "acceleration4_motion_triangle_descriptor"
  ; direct "MTL4PrimitiveAccelerationStructureDescriptor" "MTL4PrimitiveAccelerationStructureDescriptor *" "Acceleration4_primitive_descriptor" "acceleration4_primitive_descriptor"
  ; direct "MTL4AccelerationStructureTriangleGeometryDescriptor" "MTL4AccelerationStructureTriangleGeometryDescriptor *" "Acceleration4_triangle_descriptor" "acceleration4_triangle_descriptor"
  ; direct "MTL4AccelerationStructureDescriptor" "MTL4AccelerationStructureDescriptor *" "Acceleration_descriptor4" "acceleration_descriptor4"
  ; direct "MTLIOScratchBufferAllocator" "id<MTLIOScratchBufferAllocator>" "Io_scratch_allocator" "io_scratch_allocator"
  ; direct "MTLIOScratchBuffer" "id<MTLIOScratchBuffer>" "Io_scratch_buffer" "io_scratch_buffer"
  ]

let polymorphic_receivers =
  [ { sdk_owner = "MTLResource"
    ; objc_receiver_type = "id<MTLResource>"
    ; accepted_handle_kinds =
        [ "Buffer"; "Texture"; "Visible_function_table"
        ; "Intersection_function_table" ]
    ; helper = "resource_of_handle"
    ; local_name = "resource"
    ; raw_name = "raw_resource"
    }
  ; { sdk_owner = "MTLAllocation"
    ; objc_receiver_type = "id<MTLAllocation>"
    ; accepted_handle_kinds = [ "Heap"; "Buffer"; "Texture" ]
    ; helper = "allocation_of_handle"
    ; local_name = "allocation"
    ; raw_name = "raw_allocation"
    }
  ; { sdk_owner = "MTLCommandEncoder"
    ; objc_receiver_type = "id<MTLCommandEncoder>"
    ; accepted_handle_kinds =
        [ "Compute_encoder"; "Resource_state_encoder"; "Blit_encoder"
        ; "Acceleration_encoder" ]
    ; helper = "command_encoder_of_handle"
    ; local_name = "command_encoder"
    ; raw_name = "raw_command_encoder"
    }
  ]

let handwritten_only_handle_kinds =
  [ "Buffer_layout_descriptor"; "Buffer_layout_descriptor_array"
  ; "Resource_state_pass_descriptor"; "Resource_state_sample_attachment_descriptor"
  ; "Resource_state_sample_attachment_array"; "Resource_view_pool_descriptor"
  ; "Texture_view_pool"; "Tensor_descriptor"; "Tensor"; "Acceleration_descriptor"
  ; "Counter_sample_buffer"; "Texture_view_descriptor"; "Texture_descriptor"
  ; "Render_sample_attachment_descriptor"; "Render_sample_attachment_array"
  ; "Logical_to_physical_color_attachment_map"; "Shader_attribute"
  ; "Shader_vertex_attribute"; "Shader_attribute_descriptor"
  ; "Shader_attribute_descriptor_array"; "Shader_stage_descriptor"
  ; "Shader_argument_encoder"; "Shader_stitching_input_node"
  ; "Mesh_pipeline_descriptor"; "Tile_pipeline_descriptor"; "Linked_functions"
  ; "Counter_set"; "Counter_descriptor"; "Event"; "Capture_descriptor"
  ; "Capture_manager"; "Function_log"; "Function_log_location"; "Shared_event"
  ; "Pipeline_buffer_descriptor"; "Color_attachment_descriptor"
  ; "Io_command_buffer"; "Io_command_queue"; "Io_file_handle" ]
  @ [ "Compute_pipeline_descriptor"; "Render_pipeline_descriptor" ]
  @ [ "Counter_heap4" ]

let exclusions =
  [ { handle_kind = "External_memory"
    ; reason =
        "PrismelMetalExternalMemory is a Prismel ownership helper, not a Metal SDK receiver"
    }
  ; { handle_kind = "Io_surface"
    ; reason =
        "IOSurface is an XPC transport resource outside the pinned Metal SDK inventory"
    }
  ; { handle_kind = "Xpc_connection"
    ; reason = "PrismelMetalXpcConnection is a Prismel-only XPC helper"
    }
  ; { handle_kind = "Xpc_service"
    ; reason = "PrismelMetalXpcService is a Prismel-only XPC helper"
    }
  ; { handle_kind = "Xpc_request"
    ; reason = "PrismelMetalXpcRequest is a Prismel-only XPC helper"
    }
  ; { handle_kind = "Submission4"
    ; reason =
        "PrismelMetal4SubmissionState owns completion state and has no SDK receiver represented by the handle"
    }
  ; { handle_kind = "Dispatch_queue"
    ; reason = "dispatch_queue_t callback executor retained by Prismel; not an Objective-C Metal SDK receiver"
    }
  ; { handle_kind = "Function_constants4"
    ; reason = "Prismel immutable MTL4 function-constant snapshot helper; the SDK exposes no MTL4FunctionConstantValues receiver"
    }
  ] @ List.map (fun handle_kind ->
    { handle_kind
    ; reason = "Handwritten ownership receiver; not qualified for mechanical receiver generation"
    }) handwritten_only_handle_kinds

let expected_receiver_count = 108
let expected_polymorphic_receiver_count = 3
let expected_catalog_count = 111
let expected_handle_kind_count = 158
let expected_exclusion_count = 50

let source_paths =
  [ "tools/metal/binding_receiver_catalog.ml"
  ; "tools/metal/binding_receiver_catalog.mli"
  ]

let audited_bridge_path = "lib/metal/metal_bridge.mm"

let nonempty what value =
  if String.equal value "" then invalid_arg ("Metal receiver " ^ what ^ " is empty")

let valid_local_name name =
  let valid_start = function 'a' .. 'z' -> true | _ -> false in
  let valid_rest = function
    | 'a' .. 'z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  String.length name > 0 && valid_start name.[0]
  && String.for_all valid_rest name

let reject_duplicates what values =
  let rec loop = function
    | left :: right :: _ when String.equal left right ->
        invalid_arg ("Duplicate Metal receiver " ^ what ^ ": " ^ left)
    | _ :: rest -> loop rest
    | [] -> ()
  in
  loop (List.sort String.compare values)

let validate_name_pair local_name raw_name =
  if not (valid_local_name local_name) then
    invalid_arg ("Invalid Metal receiver local name: " ^ local_name);
  if not (String.equal raw_name ("raw_" ^ local_name)) then
    invalid_arg ("Metal receiver raw/local name drift: " ^ raw_name)

let validate_receiver (receiver : receiver) =
  nonempty "SDK owner" receiver.sdk_owner;
  nonempty "Objective-C type" receiver.objc_receiver_type;
  nonempty "Handle_kind spelling" receiver.handle_kind;
  validate_name_pair receiver.local_name receiver.raw_name;
  (match receiver.owner_binding with
  | One_to_one -> ()
  | Distinct_role role -> nonempty "distinct owner role" role);
  match receiver.bridge_access with
  | Object_of_handle -> ()
  | Object_of_helper helper_name -> nonempty "bridge helper" helper_name
  | Wrapped_property { wrapper_type; property } ->
      nonempty "bridge wrapper type" wrapper_type;
      nonempty "bridge wrapper property" property

let validate_owner_bindings () =
  let owners = Hashtbl.create expected_receiver_count in
  List.iter
    (fun (receiver : receiver) ->
      let existing =
        Option.value ~default:[] (Hashtbl.find_opt owners receiver.sdk_owner)
      in
      Hashtbl.replace owners receiver.sdk_owner (receiver :: existing))
    receivers;
  Hashtbl.iter
    (fun owner bindings ->
      match bindings with
      | [ { owner_binding = One_to_one; _ } ] -> ()
      | [ { owner_binding = Distinct_role _; _ } ] ->
          invalid_arg
            ("Single Metal receiver owner is unnecessarily role-qualified: "
           ^ owner)
      | _ ->
          let roles =
            List.map
              (fun receiver ->
                match receiver.owner_binding with
                | Distinct_role role -> role
                | One_to_one ->
                    invalid_arg
                      ("Ambiguous Metal receiver owner lacks a distinct role: "
                     ^ owner))
              bindings
          in
          reject_duplicates ("role for " ^ owner) roles)
    owners

let validate_polymorphic_receiver (receiver : polymorphic_receiver) =
  nonempty "polymorphic SDK owner" receiver.sdk_owner;
  nonempty "polymorphic Objective-C type" receiver.objc_receiver_type;
  nonempty "polymorphic bridge helper" receiver.helper;
  validate_name_pair receiver.local_name receiver.raw_name;
  if receiver.accepted_handle_kinds = [] then
    invalid_arg
      ("Metal polymorphic receiver has no accepted handle kinds: "
     ^ receiver.sdk_owner);
  reject_duplicates
    ("accepted Handle_kind for " ^ receiver.sdk_owner)
    receiver.accepted_handle_kinds

let validate_handle_partition () =
  let represented =
    List.map (fun (receiver : receiver) -> receiver.handle_kind) receivers
  in
  let excluded = List.map (fun exclusion -> exclusion.handle_kind) exclusions in
  reject_duplicates "Handle_kind" represented;
  reject_duplicates "excluded Handle_kind" excluded;
  reject_duplicates "represented/excluded Handle_kind" (represented @ excluded);
  if List.length represented + List.length excluded <> expected_handle_kind_count
  then invalid_arg "Metal Handle_kind audit count drift";
  List.iter
    (fun (receiver : polymorphic_receiver) ->
      List.iter
        (fun handle_kind ->
          if not (List.exists (String.equal handle_kind) represented) then
            invalid_arg
              ("Metal polymorphic receiver references an unknown Handle_kind: "
             ^ receiver.sdk_owner ^ " -> " ^ handle_kind))
        receiver.accepted_handle_kinds)
    polymorphic_receivers

let validate_exact_polymorphism () =
  let require owner expected =
    match
      List.find_opt
        (fun (receiver : polymorphic_receiver) ->
          String.equal receiver.sdk_owner owner)
        polymorphic_receivers
    with
    | None -> invalid_arg ("Missing Metal polymorphic receiver: " ^ owner)
    | Some receiver ->
        if receiver.accepted_handle_kinds <> expected then
          invalid_arg ("Metal " ^ owner ^ " Handle_kind set drift")
  in
  require "MTLResource"
    [ "Buffer"; "Texture"; "Visible_function_table"
    ; "Intersection_function_table" ];
  require "MTLAllocation" [ "Heap"; "Buffer"; "Texture" ];
  require "MTLCommandEncoder"
    [ "Compute_encoder"; "Resource_state_encoder"; "Blit_encoder"
    ; "Acceleration_encoder" ]

let validate () =
  List.iter validate_receiver receivers;
  List.iter validate_polymorphic_receiver polymorphic_receivers;
  List.iter
    (fun exclusion ->
      nonempty "excluded Handle_kind" exclusion.handle_kind;
      nonempty "exclusion reason" exclusion.reason)
    exclusions;
  if List.length receivers <> expected_receiver_count then
    invalid_arg "Metal one-handle receiver catalog count drift";
  if
    List.length polymorphic_receivers <> expected_polymorphic_receiver_count
  then invalid_arg "Metal polymorphic receiver catalog count drift";
  if
    List.length receivers + List.length polymorphic_receivers
    <> expected_catalog_count
  then invalid_arg "Metal aggregate receiver catalog count drift";
  if List.length exclusions <> expected_exclusion_count then
    invalid_arg "Metal receiver exclusion count drift";
  reject_duplicates "local name"
    (List.map (fun (receiver : receiver) -> receiver.local_name) receivers
    @ List.map
        (fun (receiver : polymorphic_receiver) -> receiver.local_name)
        polymorphic_receivers);
  reject_duplicates "raw name"
    (List.map (fun (receiver : receiver) -> receiver.raw_name) receivers
    @ List.map
        (fun (receiver : polymorphic_receiver) -> receiver.raw_name)
        polymorphic_receivers);
  reject_duplicates "polymorphic owner"
    (List.map
       (fun (receiver : polymorphic_receiver) -> receiver.sdk_owner)
       polymorphic_receivers);
  List.iter
    (fun (receiver : polymorphic_receiver) ->
      if
        List.exists
          (fun (direct : receiver) ->
            String.equal receiver.sdk_owner direct.sdk_owner)
          receivers
      then
        invalid_arg
          ("Metal owner appears in direct and polymorphic catalogs: "
         ^ receiver.sdk_owner))
    polymorphic_receivers;
  validate_owner_bindings ();
  validate_handle_partition ();
  validate_exact_polymorphism ()

let () = validate ()
