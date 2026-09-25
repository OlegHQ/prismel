type scalar = Bool | Int | Nsuint | Nsint | Float | Double

type enum_case = string * string * int64 * (int * int * int)

type sdk_type = Protocol of string | Class of string

let feature_name : Ogpu_core.Caps.feature -> string =
  let open Ogpu_core.Caps in
  function
  | Buffer -> "buffer" | Texture -> "texture" | Sampler -> "sampler"
  | Compute_pipeline -> "compute_pipeline" | Render_pipeline -> "render_pipeline"
  | Queue -> "queue" | Surface -> "surface" | Memory -> "memory"
  | Event_synchronization -> "event_synchronization"
  | Timeline_fence -> "timeline_fence" | Timestamp_queries -> "timestamp_queries"
  | Ray_tracing -> "ray_tracing" | Ray_tracing_curves -> "ray_tracing_curves"
  | Function_tables -> "function_tables" | Metal_fx -> "metal_fx"
  | Sparse_memory -> "sparse_memory" | Heaps -> "heaps"
  | Residency_sets -> "residency_sets" | Fences -> "fences"
  | Mesh_shaders -> "mesh_shaders" | Tile_shaders -> "tile_shaders"
  | Dynamic_libraries -> "dynamic_libraries" | Binary_archives -> "binary_archives"
  | Unknown name -> name

let feature_map : (Ogpu_core.Caps.feature * sdk_type list) list =
  let open Ogpu_core.Caps in
  [ Buffer, [ Protocol "MTLBuffer" ]
  ; Texture, [ Protocol "MTLTexture" ]
  ; Sampler, [ Protocol "MTLSamplerState" ]
  ; Compute_pipeline, [ Protocol "MTLComputePipelineState" ]
  ; Render_pipeline, [ Protocol "MTLRenderPipelineState" ]
  ; Queue, [ Protocol "MTLCommandQueue" ]
  ; Surface, [ Class "CAMetalLayer" ]
  ; Memory, [ Protocol "MTLBuffer" ]
  ; Event_synchronization, [ Protocol "MTLSharedEvent" ]
  ; Timeline_fence, []
  ; Timestamp_queries, [ Protocol "MTLCounterSampleBuffer" ]
  ; Ray_tracing, [ Protocol "MTLAccelerationStructure" ]
  ; Ray_tracing_curves, [ Class "MTLAccelerationStructureCurveGeometryDescriptor" ]
  ; Function_tables, [ Protocol "MTLIntersectionFunctionTable" ]
  ; Metal_fx, [ Protocol "MTLFXSpatialScaler" ]
  ; Sparse_memory, [ Protocol "MTLHeap"; Protocol "MTLTexture" ]
  ; Heaps, [ Protocol "MTLHeap" ]
  ; Residency_sets, [ Protocol "MTLResidencySet" ]
  ; Fences, [ Protocol "MTLFence" ]
  ; Mesh_shaders, [ Class "MTLMeshRenderPipelineDescriptor" ]
  ; Tile_shaders, [ Class "MTLTileRenderPipelineDescriptor" ]
  ; Dynamic_libraries, [ Protocol "MTLDynamicLibrary" ]
  ; Binary_archives, [ Protocol "MTLBinaryArchive" ]
  ]

type entry =
  | Enum of
      { sdk : string
      ; ocaml : string
      ; cases : enum_case list
      ; feature : Ogpu_core.Caps.feature
      }
  | Record of
      { sdk : string
      ; ocaml : string
      ; fields : (string * scalar) list
      ; feature : Ogpu_core.Caps.feature
      }
  | Selector of
      { recv : string
      ; sel : string
      ; args : scalar list
      ; ret : scalar option
      ; ocaml : string
      ; since : (int * int) option
      ; feature : Ogpu_core.Caps.feature
      }

let entries : entry list =
  [ Enum
      { sdk = "MTLAttributeFormat"
      ; ocaml = "Mtl_attribute_format"
      ; cases =
        [ ("mtl_attribute_format_char", "MTLAttributeFormatChar", 0x000000000000002eL, (10, 13, 0))
        ; ("mtl_attribute_format_char2", "MTLAttributeFormatChar2", 0x0000000000000004L, (10, 12, 0))
        ; ("mtl_attribute_format_char2_normalized", "MTLAttributeFormatChar2Normalized", 0x000000000000000aL, (10, 12, 0))
        ; ("mtl_attribute_format_char3", "MTLAttributeFormatChar3", 0x0000000000000005L, (10, 12, 0))
        ; ("mtl_attribute_format_char3_normalized", "MTLAttributeFormatChar3Normalized", 0x000000000000000bL, (10, 12, 0))
        ; ("mtl_attribute_format_char4", "MTLAttributeFormatChar4", 0x0000000000000006L, (10, 12, 0))
        ; ("mtl_attribute_format_char4_normalized", "MTLAttributeFormatChar4Normalized", 0x000000000000000cL, (10, 12, 0))
        ; ("mtl_attribute_format_char_normalized", "MTLAttributeFormatCharNormalized", 0x0000000000000030L, (10, 13, 0))
        ; ("mtl_attribute_format_float", "MTLAttributeFormatFloat", 0x000000000000001cL, (10, 12, 0))
        ; ("mtl_attribute_format_float2", "MTLAttributeFormatFloat2", 0x000000000000001dL, (10, 12, 0))
        ; ("mtl_attribute_format_float3", "MTLAttributeFormatFloat3", 0x000000000000001eL, (10, 12, 0))
        ; ("mtl_attribute_format_float4", "MTLAttributeFormatFloat4", 0x000000000000001fL, (10, 12, 0))
        ; ("mtl_attribute_format_float_rg11_b10", "MTLAttributeFormatFloatRG11B10", 0x0000000000000036L, (14, 0, 0))
        ; ("mtl_attribute_format_float_rgb9_e5", "MTLAttributeFormatFloatRGB9E5", 0x0000000000000037L, (14, 0, 0))
        ; ("mtl_attribute_format_half", "MTLAttributeFormatHalf", 0x0000000000000035L, (10, 13, 0))
        ; ("mtl_attribute_format_half2", "MTLAttributeFormatHalf2", 0x0000000000000019L, (10, 12, 0))
        ; ("mtl_attribute_format_half3", "MTLAttributeFormatHalf3", 0x000000000000001aL, (10, 12, 0))
        ; ("mtl_attribute_format_half4", "MTLAttributeFormatHalf4", 0x000000000000001bL, (10, 12, 0))
        ; ("mtl_attribute_format_int", "MTLAttributeFormatInt", 0x0000000000000020L, (10, 12, 0))
        ; ("mtl_attribute_format_int1010102_normalized", "MTLAttributeFormatInt1010102Normalized", 0x0000000000000028L, (10, 12, 0))
        ; ("mtl_attribute_format_int2", "MTLAttributeFormatInt2", 0x0000000000000021L, (10, 12, 0))
        ; ("mtl_attribute_format_int3", "MTLAttributeFormatInt3", 0x0000000000000022L, (10, 12, 0))
        ; ("mtl_attribute_format_int4", "MTLAttributeFormatInt4", 0x0000000000000023L, (10, 12, 0))
        ; ("mtl_attribute_format_invalid", "MTLAttributeFormatInvalid", 0x0000000000000000L, (10, 12, 0))
        ; ("mtl_attribute_format_short", "MTLAttributeFormatShort", 0x0000000000000032L, (10, 13, 0))
        ; ("mtl_attribute_format_short2", "MTLAttributeFormatShort2", 0x0000000000000010L, (10, 12, 0))
        ; ("mtl_attribute_format_short2_normalized", "MTLAttributeFormatShort2Normalized", 0x0000000000000016L, (10, 12, 0))
        ; ("mtl_attribute_format_short3", "MTLAttributeFormatShort3", 0x0000000000000011L, (10, 12, 0))
        ; ("mtl_attribute_format_short3_normalized", "MTLAttributeFormatShort3Normalized", 0x0000000000000017L, (10, 12, 0))
        ; ("mtl_attribute_format_short4", "MTLAttributeFormatShort4", 0x0000000000000012L, (10, 12, 0))
        ; ("mtl_attribute_format_short4_normalized", "MTLAttributeFormatShort4Normalized", 0x0000000000000018L, (10, 12, 0))
        ; ("mtl_attribute_format_short_normalized", "MTLAttributeFormatShortNormalized", 0x0000000000000034L, (10, 13, 0))
        ; ("mtl_attribute_format_u_char", "MTLAttributeFormatUChar", 0x000000000000002dL, (10, 13, 0))
        ; ("mtl_attribute_format_u_char2", "MTLAttributeFormatUChar2", 0x0000000000000001L, (10, 12, 0))
        ; ("mtl_attribute_format_u_char2_normalized", "MTLAttributeFormatUChar2Normalized", 0x0000000000000007L, (10, 12, 0))
        ; ("mtl_attribute_format_u_char3", "MTLAttributeFormatUChar3", 0x0000000000000002L, (10, 12, 0))
        ; ("mtl_attribute_format_u_char3_normalized", "MTLAttributeFormatUChar3Normalized", 0x0000000000000008L, (10, 12, 0))
        ; ("mtl_attribute_format_u_char4", "MTLAttributeFormatUChar4", 0x0000000000000003L, (10, 12, 0))
        ; ("mtl_attribute_format_u_char4_normalized", "MTLAttributeFormatUChar4Normalized", 0x0000000000000009L, (10, 12, 0))
        ; ("mtl_attribute_format_u_char4_normalized_bgra", "MTLAttributeFormatUChar4Normalized_BGRA", 0x000000000000002aL, (10, 13, 0))
        ; ("mtl_attribute_format_u_char_normalized", "MTLAttributeFormatUCharNormalized", 0x000000000000002fL, (10, 13, 0))
        ; ("mtl_attribute_format_u_int", "MTLAttributeFormatUInt", 0x0000000000000024L, (10, 12, 0))
        ; ("mtl_attribute_format_u_int1010102_normalized", "MTLAttributeFormatUInt1010102Normalized", 0x0000000000000029L, (10, 12, 0))
        ; ("mtl_attribute_format_u_int2", "MTLAttributeFormatUInt2", 0x0000000000000025L, (10, 12, 0))
        ; ("mtl_attribute_format_u_int3", "MTLAttributeFormatUInt3", 0x0000000000000026L, (10, 12, 0))
        ; ("mtl_attribute_format_u_int4", "MTLAttributeFormatUInt4", 0x0000000000000027L, (10, 12, 0))
        ; ("mtl_attribute_format_u_short", "MTLAttributeFormatUShort", 0x0000000000000031L, (10, 13, 0))
        ; ("mtl_attribute_format_u_short2", "MTLAttributeFormatUShort2", 0x000000000000000dL, (10, 12, 0))
        ; ("mtl_attribute_format_u_short2_normalized", "MTLAttributeFormatUShort2Normalized", 0x0000000000000013L, (10, 12, 0))
        ; ("mtl_attribute_format_u_short3", "MTLAttributeFormatUShort3", 0x000000000000000eL, (10, 12, 0))
        ; ("mtl_attribute_format_u_short3_normalized", "MTLAttributeFormatUShort3Normalized", 0x0000000000000014L, (10, 12, 0))
        ; ("mtl_attribute_format_u_short4", "MTLAttributeFormatUShort4", 0x000000000000000fL, (10, 12, 0))
        ; ("mtl_attribute_format_u_short4_normalized", "MTLAttributeFormatUShort4Normalized", 0x0000000000000015L, (10, 12, 0))
        ; ("mtl_attribute_format_u_short_normalized", "MTLAttributeFormatUShortNormalized", 0x0000000000000033L, (10, 13, 0))
        ]
      ; feature = Ogpu_core.Caps.Render_pipeline
      }
  ; Enum
      { sdk = "MTLDataType"
      ; ocaml = "Mtl_data_type"
      ; cases =
        [ ("mtl_data_type_array", "MTLDataTypeArray", 0x0000000000000002L, (10, 11, 0))
        ; ("mtl_data_type_b_float", "MTLDataTypeBFloat", 0x0000000000000079L, (14, 0, 0))
        ; ("mtl_data_type_b_float2", "MTLDataTypeBFloat2", 0x000000000000007aL, (14, 0, 0))
        ; ("mtl_data_type_b_float3", "MTLDataTypeBFloat3", 0x000000000000007bL, (14, 0, 0))
        ; ("mtl_data_type_b_float4", "MTLDataTypeBFloat4", 0x000000000000007cL, (14, 0, 0))
        ; ("mtl_data_type_bool", "MTLDataTypeBool", 0x0000000000000035L, (10, 11, 0))
        ; ("mtl_data_type_bool2", "MTLDataTypeBool2", 0x0000000000000036L, (10, 11, 0))
        ; ("mtl_data_type_bool3", "MTLDataTypeBool3", 0x0000000000000037L, (10, 11, 0))
        ; ("mtl_data_type_bool4", "MTLDataTypeBool4", 0x0000000000000038L, (10, 11, 0))
        ; ("mtl_data_type_char", "MTLDataTypeChar", 0x000000000000002dL, (10, 11, 0))
        ; ("mtl_data_type_char2", "MTLDataTypeChar2", 0x000000000000002eL, (10, 11, 0))
        ; ("mtl_data_type_char3", "MTLDataTypeChar3", 0x000000000000002fL, (10, 11, 0))
        ; ("mtl_data_type_char4", "MTLDataTypeChar4", 0x0000000000000030L, (10, 11, 0))
        ; ("mtl_data_type_compute_pipeline", "MTLDataTypeComputePipeline", 0x000000000000004fL, (11, 0, 0))
        ; ("mtl_data_type_depth_stencil_state", "MTLDataTypeDepthStencilState", 0x000000000000008bL, (26, 0, 0))
        ; ("mtl_data_type_float", "MTLDataTypeFloat", 0x0000000000000003L, (10, 11, 0))
        ; ("mtl_data_type_float2", "MTLDataTypeFloat2", 0x0000000000000004L, (10, 11, 0))
        ; ("mtl_data_type_float2x2", "MTLDataTypeFloat2x2", 0x0000000000000007L, (10, 11, 0))
        ; ("mtl_data_type_float2x3", "MTLDataTypeFloat2x3", 0x0000000000000008L, (10, 11, 0))
        ; ("mtl_data_type_float2x4", "MTLDataTypeFloat2x4", 0x0000000000000009L, (10, 11, 0))
        ; ("mtl_data_type_float3", "MTLDataTypeFloat3", 0x0000000000000005L, (10, 11, 0))
        ; ("mtl_data_type_float3x2", "MTLDataTypeFloat3x2", 0x000000000000000aL, (10, 11, 0))
        ; ("mtl_data_type_float3x3", "MTLDataTypeFloat3x3", 0x000000000000000bL, (10, 11, 0))
        ; ("mtl_data_type_float3x4", "MTLDataTypeFloat3x4", 0x000000000000000cL, (10, 11, 0))
        ; ("mtl_data_type_float4", "MTLDataTypeFloat4", 0x0000000000000006L, (10, 11, 0))
        ; ("mtl_data_type_float4x2", "MTLDataTypeFloat4x2", 0x000000000000000dL, (10, 11, 0))
        ; ("mtl_data_type_float4x3", "MTLDataTypeFloat4x3", 0x000000000000000eL, (10, 11, 0))
        ; ("mtl_data_type_float4x4", "MTLDataTypeFloat4x4", 0x000000000000000fL, (10, 11, 0))
        ; ("mtl_data_type_half", "MTLDataTypeHalf", 0x0000000000000010L, (10, 11, 0))
        ; ("mtl_data_type_half2", "MTLDataTypeHalf2", 0x0000000000000011L, (10, 11, 0))
        ; ("mtl_data_type_half2x2", "MTLDataTypeHalf2x2", 0x0000000000000014L, (10, 11, 0))
        ; ("mtl_data_type_half2x3", "MTLDataTypeHalf2x3", 0x0000000000000015L, (10, 11, 0))
        ; ("mtl_data_type_half2x4", "MTLDataTypeHalf2x4", 0x0000000000000016L, (10, 11, 0))
        ; ("mtl_data_type_half3", "MTLDataTypeHalf3", 0x0000000000000012L, (10, 11, 0))
        ; ("mtl_data_type_half3x2", "MTLDataTypeHalf3x2", 0x0000000000000017L, (10, 11, 0))
        ; ("mtl_data_type_half3x3", "MTLDataTypeHalf3x3", 0x0000000000000018L, (10, 11, 0))
        ; ("mtl_data_type_half3x4", "MTLDataTypeHalf3x4", 0x0000000000000019L, (10, 11, 0))
        ; ("mtl_data_type_half4", "MTLDataTypeHalf4", 0x0000000000000013L, (10, 11, 0))
        ; ("mtl_data_type_half4x2", "MTLDataTypeHalf4x2", 0x000000000000001aL, (10, 11, 0))
        ; ("mtl_data_type_half4x3", "MTLDataTypeHalf4x3", 0x000000000000001bL, (10, 11, 0))
        ; ("mtl_data_type_half4x4", "MTLDataTypeHalf4x4", 0x000000000000001cL, (10, 11, 0))
        ; ("mtl_data_type_indirect_command_buffer", "MTLDataTypeIndirectCommandBuffer", 0x0000000000000050L, (10, 14, 0))
        ; ("mtl_data_type_instance_acceleration_structure", "MTLDataTypeInstanceAccelerationStructure", 0x0000000000000076L, (11, 0, 0))
        ; ("mtl_data_type_int", "MTLDataTypeInt", 0x000000000000001dL, (10, 11, 0))
        ; ("mtl_data_type_int2", "MTLDataTypeInt2", 0x000000000000001eL, (10, 11, 0))
        ; ("mtl_data_type_int3", "MTLDataTypeInt3", 0x000000000000001fL, (10, 11, 0))
        ; ("mtl_data_type_int4", "MTLDataTypeInt4", 0x0000000000000020L, (10, 11, 0))
        ; ("mtl_data_type_intersection_function_table", "MTLDataTypeIntersectionFunctionTable", 0x0000000000000074L, (11, 0, 0))
        ; ("mtl_data_type_long", "MTLDataTypeLong", 0x0000000000000051L, (12, 0, 0))
        ; ("mtl_data_type_long2", "MTLDataTypeLong2", 0x0000000000000052L, (12, 0, 0))
        ; ("mtl_data_type_long3", "MTLDataTypeLong3", 0x0000000000000053L, (12, 0, 0))
        ; ("mtl_data_type_long4", "MTLDataTypeLong4", 0x0000000000000054L, (12, 0, 0))
        ; ("mtl_data_type_none", "MTLDataTypeNone", 0x0000000000000000L, (10, 11, 0))
        ; ("mtl_data_type_pointer", "MTLDataTypePointer", 0x000000000000003cL, (10, 13, 0))
        ; ("mtl_data_type_primitive_acceleration_structure", "MTLDataTypePrimitiveAccelerationStructure", 0x0000000000000075L, (11, 0, 0))
        ; ("mtl_data_type_r16_snorm", "MTLDataTypeR16Snorm", 0x0000000000000041L, (11, 0, 0))
        ; ("mtl_data_type_r16_unorm", "MTLDataTypeR16Unorm", 0x0000000000000040L, (11, 0, 0))
        ; ("mtl_data_type_r8_snorm", "MTLDataTypeR8Snorm", 0x000000000000003fL, (11, 0, 0))
        ; ("mtl_data_type_r8_unorm", "MTLDataTypeR8Unorm", 0x000000000000003eL, (11, 0, 0))
        ; ("mtl_data_type_rg11_b10_float", "MTLDataTypeRG11B10Float", 0x000000000000004cL, (11, 0, 0))
        ; ("mtl_data_type_rg16_snorm", "MTLDataTypeRG16Snorm", 0x0000000000000045L, (11, 0, 0))
        ; ("mtl_data_type_rg16_unorm", "MTLDataTypeRG16Unorm", 0x0000000000000044L, (11, 0, 0))
        ; ("mtl_data_type_rg8_snorm", "MTLDataTypeRG8Snorm", 0x0000000000000043L, (11, 0, 0))
        ; ("mtl_data_type_rg8_unorm", "MTLDataTypeRG8Unorm", 0x0000000000000042L, (11, 0, 0))
        ; ("mtl_data_type_rgb10_a2_unorm", "MTLDataTypeRGB10A2Unorm", 0x000000000000004bL, (11, 0, 0))
        ; ("mtl_data_type_rgb9_e5_float", "MTLDataTypeRGB9E5Float", 0x000000000000004dL, (11, 0, 0))
        ; ("mtl_data_type_rgba16_snorm", "MTLDataTypeRGBA16Snorm", 0x000000000000004aL, (11, 0, 0))
        ; ("mtl_data_type_rgba16_unorm", "MTLDataTypeRGBA16Unorm", 0x0000000000000049L, (11, 0, 0))
        ; ("mtl_data_type_rgba8_snorm", "MTLDataTypeRGBA8Snorm", 0x0000000000000048L, (11, 0, 0))
        ; ("mtl_data_type_rgba8_unorm", "MTLDataTypeRGBA8Unorm", 0x0000000000000046L, (11, 0, 0))
        ; ("mtl_data_type_rgba8_unorm_s_rgb", "MTLDataTypeRGBA8Unorm_sRGB", 0x0000000000000047L, (11, 0, 0))
        ; ("mtl_data_type_render_pipeline", "MTLDataTypeRenderPipeline", 0x000000000000004eL, (10, 14, 0))
        ; ("mtl_data_type_sampler", "MTLDataTypeSampler", 0x000000000000003bL, (10, 13, 0))
        ; ("mtl_data_type_short", "MTLDataTypeShort", 0x0000000000000025L, (10, 11, 0))
        ; ("mtl_data_type_short2", "MTLDataTypeShort2", 0x0000000000000026L, (10, 11, 0))
        ; ("mtl_data_type_short3", "MTLDataTypeShort3", 0x0000000000000027L, (10, 11, 0))
        ; ("mtl_data_type_short4", "MTLDataTypeShort4", 0x0000000000000028L, (10, 11, 0))
        ; ("mtl_data_type_struct", "MTLDataTypeStruct", 0x0000000000000001L, (10, 11, 0))
        ; ("mtl_data_type_tensor", "MTLDataTypeTensor", 0x000000000000008cL, (26, 0, 0))
        ; ("mtl_data_type_texture", "MTLDataTypeTexture", 0x000000000000003aL, (10, 13, 0))
        ; ("mtl_data_type_u_char", "MTLDataTypeUChar", 0x0000000000000031L, (10, 11, 0))
        ; ("mtl_data_type_u_char2", "MTLDataTypeUChar2", 0x0000000000000032L, (10, 11, 0))
        ; ("mtl_data_type_u_char3", "MTLDataTypeUChar3", 0x0000000000000033L, (10, 11, 0))
        ; ("mtl_data_type_u_char4", "MTLDataTypeUChar4", 0x0000000000000034L, (10, 11, 0))
        ; ("mtl_data_type_u_int", "MTLDataTypeUInt", 0x0000000000000021L, (10, 11, 0))
        ; ("mtl_data_type_u_int2", "MTLDataTypeUInt2", 0x0000000000000022L, (10, 11, 0))
        ; ("mtl_data_type_u_int3", "MTLDataTypeUInt3", 0x0000000000000023L, (10, 11, 0))
        ; ("mtl_data_type_u_int4", "MTLDataTypeUInt4", 0x0000000000000024L, (10, 11, 0))
        ; ("mtl_data_type_u_long", "MTLDataTypeULong", 0x0000000000000055L, (12, 0, 0))
        ; ("mtl_data_type_u_long2", "MTLDataTypeULong2", 0x0000000000000056L, (12, 0, 0))
        ; ("mtl_data_type_u_long3", "MTLDataTypeULong3", 0x0000000000000057L, (12, 0, 0))
        ; ("mtl_data_type_u_long4", "MTLDataTypeULong4", 0x0000000000000058L, (12, 0, 0))
        ; ("mtl_data_type_u_short", "MTLDataTypeUShort", 0x0000000000000029L, (10, 11, 0))
        ; ("mtl_data_type_u_short2", "MTLDataTypeUShort2", 0x000000000000002aL, (10, 11, 0))
        ; ("mtl_data_type_u_short3", "MTLDataTypeUShort3", 0x000000000000002bL, (10, 11, 0))
        ; ("mtl_data_type_u_short4", "MTLDataTypeUShort4", 0x000000000000002cL, (10, 11, 0))
        ; ("mtl_data_type_visible_function_table", "MTLDataTypeVisibleFunctionTable", 0x0000000000000073L, (11, 0, 0))
        ]
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  ; Enum
      { sdk = "MTLFeatureSet"
      ; ocaml = "Mtl_feature_set"
      ; cases =
        [ ("mtl_feature_set_osx_gpu_family1_v1", "MTLFeatureSet_OSX_GPUFamily1_v1", 0x0000000000002710L, (10, 11, 0))
        ; ("mtl_feature_set_osx_gpu_family1_v2", "MTLFeatureSet_OSX_GPUFamily1_v2", 0x0000000000002711L, (10, 12, 0))
        ; ("mtl_feature_set_osx_read_write_texture_tier2", "MTLFeatureSet_OSX_ReadWriteTextureTier2", 0x0000000000002712L, (10, 12, 0))
        ; ("mtl_feature_set_mac_os_gpu_family1_v1", "MTLFeatureSet_macOS_GPUFamily1_v1", 0x0000000000002710L, (10, 11, 0))
        ; ("mtl_feature_set_mac_os_gpu_family1_v2", "MTLFeatureSet_macOS_GPUFamily1_v2", 0x0000000000002711L, (10, 12, 0))
        ; ("mtl_feature_set_mac_os_gpu_family1_v3", "MTLFeatureSet_macOS_GPUFamily1_v3", 0x0000000000002713L, (10, 13, 0))
        ; ("mtl_feature_set_mac_os_gpu_family1_v4", "MTLFeatureSet_macOS_GPUFamily1_v4", 0x0000000000002714L, (10, 14, 0))
        ; ("mtl_feature_set_mac_os_gpu_family2_v1", "MTLFeatureSet_macOS_GPUFamily2_v1", 0x0000000000002715L, (10, 14, 0))
        ; ("mtl_feature_set_mac_os_read_write_texture_tier2", "MTLFeatureSet_macOS_ReadWriteTextureTier2", 0x0000000000002712L, (10, 12, 0))
        ]
      ; feature = Ogpu_core.Caps.Buffer
      }
  ; Enum
      { sdk = "MTLIntersectionFunctionSignature"
      ; ocaml = "Mtl_intersection_function_signature"
      ; cases =
        [ ("mtl_intersection_function_signature_curve_data", "MTLIntersectionFunctionSignatureCurveData", 0x0000000000000080L, (14, 0, 0))
        ; ("mtl_intersection_function_signature_extended_limits", "MTLIntersectionFunctionSignatureExtendedLimits", 0x0000000000000020L, (12, 0, 0))
        ; ("mtl_intersection_function_signature_instance_motion", "MTLIntersectionFunctionSignatureInstanceMotion", 0x0000000000000008L, (12, 0, 0))
        ; ("mtl_intersection_function_signature_instancing", "MTLIntersectionFunctionSignatureInstancing", 0x0000000000000001L, (11, 0, 0))
        ; ("mtl_intersection_function_signature_intersection_function_buffer", "MTLIntersectionFunctionSignatureIntersectionFunctionBuffer", 0x0000000000000100L, (26, 0, 0))
        ; ("mtl_intersection_function_signature_max_levels", "MTLIntersectionFunctionSignatureMaxLevels", 0x0000000000000040L, (14, 0, 0))
        ; ("mtl_intersection_function_signature_none", "MTLIntersectionFunctionSignatureNone", 0x0000000000000000L, (11, 0, 0))
        ; ("mtl_intersection_function_signature_primitive_motion", "MTLIntersectionFunctionSignaturePrimitiveMotion", 0x0000000000000010L, (12, 0, 0))
        ; ("mtl_intersection_function_signature_triangle_data", "MTLIntersectionFunctionSignatureTriangleData", 0x0000000000000002L, (11, 0, 0))
        ; ("mtl_intersection_function_signature_user_data", "MTLIntersectionFunctionSignatureUserData", 0x0000000000000200L, (26, 0, 0))
        ; ("mtl_intersection_function_signature_world_space_data", "MTLIntersectionFunctionSignatureWorldSpaceData", 0x0000000000000004L, (11, 0, 0))
        ]
      ; feature = Ogpu_core.Caps.Function_tables
      }
  ; Record
      { sdk = "MTLSize"
      ; ocaml = "Mtl_size"
      ; fields = [ "width", Nsuint; "height", Nsuint; "depth", Nsuint ]
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  ; Selector
      { recv = "MTLDevice"
      ; sel = "maxThreadgroupMemoryLength"
      ; args = []
      ; ret = Some Nsuint
      ; ocaml = "device_max_threadgroup_memory_length"
      ; since = Some (10, 13)
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  ; Selector
      { recv = "MTLComputePipelineState"
      ; sel = "supportIndirectCommandBuffers"
      ; args = []
      ; ret = Some Bool
      ; ocaml = "compute_pipeline_state_support_indirect_command_buffers"
      ; since = Some (11, 0)
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  ; Selector
      { recv = "MTLComputePipelineState"
      ; sel = "staticThreadgroupMemoryLength"
      ; args = []
      ; ret = Some Nsuint
      ; ocaml = "compute_pipeline_static_threadgroup_memory_length"
      ; since = Some (10, 13)
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  ; Selector
      { recv = "MTLRenderPipelineState"
      ; sel = "supportIndirectCommandBuffers"
      ; args = []
      ; ret = Some Bool
      ; ocaml = "render_pipeline_state_support_indirect_command_buffers"
      ; since = Some (10, 14)
      ; feature = Ogpu_core.Caps.Render_pipeline
      }
  ]
