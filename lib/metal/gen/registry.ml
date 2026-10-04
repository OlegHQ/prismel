type scalar = Bool | Int | Nsuint | Nsuint_int | Nsint | Float | Double

(* A value crossing a generated call. [Obj kind] is a borrowed handle of the
   bridge's [Handle_kind::kind] (retained when returned); [Enum_of c] is a
   C enum or options type carried as int64; [Str] is NSString (invalid UTF-8
   is an [Error]); [Rec r] passes the [Record] entry [r] by value, and
   [Tuple r] uses the same native struct with an OCaml tuple ABI.
   [Nsuint_int] keeps bounded native indices as OCaml machine integers. *)
type ty =
  | Scalar of scalar
  | Enum_of of string
  | Str
  | Obj of string
  | Opt_obj of string
  | Rec of string
  | Tuple of string

type access = Get | Set | Get_set

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
  (* Custom marshalling/lifecycle code still implements these primitives.
     Keep its ABI here as well, so the audit covers every raw binding. *)
  | Native of
      { ocaml : string
      ; signature : string
      ; primitives : string list
      ; reason : string
      }
  | Class_method of
      { objc : string
      ; sel : string
      ; args : ty list
      ; ret : ty option
      ; ocaml : string
      ; since : (int * int) option
      ; feature : Ogpu_core.Caps.feature
      }
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
  (* [objc] receives [sel] (colons included) with [args]; [error] appends a
     trailing NSError** and turns failure into [Error]. [recv] is the
     receiver's Handle_kind, [objc] its Objective-C type. [pool = false]
     preserves pool-free encoding calls returning unit without NSString or
     NSError temporaries; exception conversion still owns a pool. *)
  | Method of
      { recv : string
      ; objc : string
      ; sel : string
      ; args : ty list
      ; ret : ty option
      ; error : bool
      ; pool : bool
      ; ocaml : string
      ; since : (int * int) option
      ; feature : Ogpu_core.Caps.feature
      }
  (* An Objective-C property: [Get] generates [ocaml], [Set] [set_ocaml]. *)
  | Property of
      { recv : string
      ; objc : string
      ; name : string
      ; ty : ty
      ; access : access
      ; ocaml : string
      ; since : (int * int) option
      ; feature : Ogpu_core.Caps.feature
      }

module C = Ogpu_core.Caps

let entries : entry list =
  [ Enum
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
  ; Record
      { sdk = "MTLSize"
      ; ocaml = "Mtl_size"
      ; fields = [ "width", Nsuint; "height", Nsuint; "depth", Nsuint ]
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  ; Record
      { sdk = "MTLViewport"
      ; ocaml = "Mtl_viewport"
      ; fields =
          [ "originX", Double; "originY", Double; "width", Double; "height", Double
          ; "znear", Double; "zfar", Double ]
      ; feature = Ogpu_core.Caps.Render_pipeline
      }
  ; Record
      { sdk = "MTLScissorRect"
      ; ocaml = "Mtl_scissor_rect"
      ; fields = [ "x", Nsuint; "y", Nsuint; "width", Nsuint; "height", Nsuint ]
      ; feature = Ogpu_core.Caps.Render_pipeline
      }
  ; Method
      { recv = "Device"
      ; objc = "id<MTLDevice>"
      ; sel = "supportsFamily:"
      ; args = [ Enum_of "MTLGPUFamily" ]
      ; ret = Some (Scalar Bool)
      ; error = false
      ; ocaml = "device_supports_family"
      ; since = None
      ; feature = Ogpu_core.Caps.Buffer
      ; pool = true }
  ; Property
      { recv = "Device"
      ; objc = "id<MTLDevice>"
      ; name = "maxThreadgroupMemoryLength"
      ; ty = Scalar Nsuint
      ; access = Get
      ; ocaml = "device_max_threadgroup_memory_length"
      ; since = Some (10, 13)
      ; feature = Ogpu_core.Caps.Compute_pipeline
      }
  ; Property
      { recv = "Render_pipeline"
      ; objc = "id<MTLRenderPipelineState>"
      ; name = "supportIndirectCommandBuffers"
      ; ty = Scalar Bool
      ; access = Get
      ; ocaml = "render_pipeline_state_support_indirect_command_buffers"
      ; since = Some (10, 14)
      ; feature = Ogpu_core.Caps.Render_pipeline
      }
  (* MTLDevice *)
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "name"; ty = Str; access = Get
             ; ocaml = "device_name"; since = None; feature = C.Buffer }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "registryID"; ty = Scalar Nsuint; access = Get
             ; ocaml = "device_registry_id"; since = None; feature = C.Buffer }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "lowPower"; ty = Scalar Bool; access = Get
             ; ocaml = "device_is_low_power"; since = None; feature = C.Buffer }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "removable"; ty = Scalar Bool; access = Get
             ; ocaml = "device_is_removable"; since = None; feature = C.Buffer }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "headless"; ty = Scalar Bool; access = Get
             ; ocaml = "device_is_headless"; since = None; feature = C.Buffer }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "hasUnifiedMemory"; ty = Scalar Bool; access = Get
             ; ocaml = "device_has_unified_memory"; since = None; feature = C.Memory }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "recommendedMaxWorkingSetSize"; ty = Scalar Nsuint
             ; access = Get; ocaml = "device_recommended_max_working_set_size"; since = None; feature = C.Memory }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "currentAllocatedSize"; ty = Scalar Nsuint
             ; access = Get; ocaml = "device_current_allocated_size"; since = None; feature = C.Memory }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "maxBufferLength"; ty = Scalar Nsuint; access = Get
             ; ocaml = "device_max_buffer_length"; since = None; feature = C.Buffer }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "supportsRaytracing"; ty = Scalar Bool; access = Get
             ; ocaml = "device_supports_raytracing"; since = None; feature = C.Ray_tracing }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "supportsRaytracingFromRender"; ty = Scalar Bool
             ; access = Get; ocaml = "device_supports_raytracing_from_render"; since = None; feature = C.Ray_tracing }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "supportsDynamicLibraries"; ty = Scalar Bool
             ; access = Get; ocaml = "device_supports_dynamic_libraries"; since = None; feature = C.Dynamic_libraries }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "supportsFunctionPointers"; ty = Scalar Bool
             ; access = Get; ocaml = "device_supports_function_pointers"; since = None; feature = C.Function_tables }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "supportsFunctionPointersFromRender"; ty = Scalar Bool
             ; access = Get; ocaml = "device_supports_function_pointers_from_render"; since = None
             ; feature = C.Function_tables }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "supportsVertexAmplificationCount:"; args = [ Scalar Nsuint ]
           ; ret = Some (Scalar Bool); error = false; ocaml = "device_supports_vertex_amplification_count"; since = None
           ; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "supportsTextureSampleCount:"; args = [ Scalar Nsuint ]
           ; ret = Some (Scalar Bool); error = false; ocaml = "device_supports_texture_sample_count"; since = None
           ; feature = C.Texture ; pool = true }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "depth24Stencil8PixelFormatSupported"; ty = Scalar Bool
             ; access = Get; ocaml = "device_supports_depth24_stencil8"; since = None; feature = C.Texture }
  ; Property { recv = "Device"; objc = "id<MTLDevice>"; name = "supportsBCTextureCompression"; ty = Scalar Bool
             ; access = Get; ocaml = "device_supports_bc_texture_compression"; since = None; feature = C.Texture }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "newCommandQueue"; args = []
           ; ret = Some (Obj "Command_queue"); error = false; ocaml = "command_queue_create"; since = None
           ; feature = C.Queue ; pool = true }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "newFence"; args = []
           ; ret = Some (Obj "Fence"); error = false; ocaml = "device_create_fence"; since = None
           ; feature = C.Fences ; pool = true }
  (* MTLCommandQueue, MTLCommandBuffer and encoder lifetimes *)
  ; Method { recv = "Command_queue"; objc = "id<MTLCommandQueue>"; sel = "commandBuffer"; args = []
           ; ret = Some (Obj "Command_buffer"); error = false; ocaml = "command_buffer_create"; since = None
           ; feature = C.Queue ; pool = true }
  ; Method { recv = "Command_queue"; objc = "id<MTLCommandQueue>"; sel = "addResidencySet:"
           ; args = [ Obj "Residency_set" ]; ret = None; error = false
           ; ocaml = "command_queue_add_residency_set"; since = Some (15, 0); feature = C.Residency_sets ; pool = true }
  ; Method { recv = "Command_queue"; objc = "id<MTLCommandQueue>"; sel = "removeResidencySet:"
           ; args = [ Obj "Residency_set" ]; ret = None; error = false
           ; ocaml = "command_queue_remove_residency_set"; since = Some (15, 0); feature = C.Residency_sets ; pool = true }
  ; Property { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; name = "label"; ty = Str; access = Set
             ; ocaml = "command_buffer_label"; since = None; feature = C.Queue }
  ; Property { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; name = "status"
             ; ty = Enum_of "MTLCommandBufferStatus"; access = Get; ocaml = "command_buffer_status"; since = None
             ; feature = C.Queue }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "commit"; args = []; ret = None
           ; error = false; ocaml = "command_buffer_commit"; since = None; feature = C.Queue ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "useResidencySet:"
           ; args = [ Obj "Residency_set" ]; ret = None; error = false
           ; ocaml = "command_buffer_use_residency_set"; since = Some (15, 0); feature = C.Residency_sets ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "encodeSignalEvent:value:"
           ; args = [ Obj "Shared_event"; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "command_buffer_encode_signal_event"; since = None; feature = C.Event_synchronization ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "encodeWaitForEvent:value:"
           ; args = [ Obj "Shared_event"; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "command_buffer_encode_wait_for_event"; since = None; feature = C.Event_synchronization ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "computeCommandEncoder"; args = []
           ; ret = Some (Obj "Compute_encoder"); error = false; ocaml = "command_buffer_compute_encoder"
           ; since = None; feature = C.Compute_pipeline ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "computeCommandEncoderWithDescriptor:"
           ; args = [ Obj "Compute_pass_descriptor" ]; ret = Some (Obj "Compute_encoder"); error = false
           ; ocaml = "command_buffer_compute_encoder_with_pass"; since = None; feature = C.Compute_pipeline ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "blitCommandEncoder"; args = []
           ; ret = Some (Obj "Blit_encoder"); error = false; ocaml = "command_buffer_blit_encoder"; since = None
           ; feature = C.Buffer ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "blitCommandEncoderWithDescriptor:"
           ; args = [ Obj "Blit_pass_descriptor" ]; ret = Some (Obj "Blit_encoder"); error = false
           ; ocaml = "command_buffer_blit_encoder_with_pass"; since = None; feature = C.Buffer ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "resourceStateCommandEncoder"; args = []
           ; ret = Some (Obj "Resource_state_encoder"); error = false
           ; ocaml = "command_buffer_resource_state_encoder"; since = None; feature = C.Sparse_memory ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "accelerationStructureCommandEncoder"
           ; args = []; ret = Some (Obj "Acceleration_encoder"); error = false
           ; ocaml = "command_buffer_acceleration_encoder"; since = None; feature = C.Ray_tracing ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "renderCommandEncoderWithDescriptor:"
           ; args = [ Obj "Render_pass_descriptor" ]; ret = Some (Obj "Render_encoder"); error = false
           ; ocaml = "command_buffer_render_encoder_from_pass"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "endEncoding"; args = []
           ; ret = None; error = false; ocaml = "compute_encoder_end"; since = None; feature = C.Compute_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "endEncoding"; args = []
           ; ret = None; error = false; ocaml = "render_encoder_end"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Blit_encoder"; objc = "id<MTLBlitCommandEncoder>"; sel = "endEncoding"; args = []
           ; ret = None; error = false; ocaml = "blit_encoder_end"; since = None; feature = C.Buffer ; pool = true }
  ; Method { recv = "Resource_state_encoder"; objc = "id<MTLResourceStateCommandEncoder>"; sel = "endEncoding"
           ; args = []; ret = None; error = false; ocaml = "resource_state_encoder_end"; since = None
           ; feature = C.Sparse_memory ; pool = true }
  ; Method { recv = "Acceleration_encoder"; objc = "id<MTLAccelerationStructureCommandEncoder>"; sel = "endEncoding"
           ; args = []; ret = None; error = false; ocaml = "acceleration_encoder_end"; since = None
           ; feature = C.Ray_tracing ; pool = true }
  (* MTLRenderCommandEncoder state and draws *)
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setRenderPipelineState:"
           ; args = [ Obj "Render_pipeline" ]; ret = None; error = false; ocaml = "render_encoder_set_pipeline"
           ; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setVertexBuffer:offset:atIndex:"
           ; args = [ Obj "Buffer"; Scalar Nsuint; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_vertex_buffer"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setFragmentBuffer:offset:atIndex:"
           ; args = [ Obj "Buffer"; Scalar Nsuint; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_fragment_buffer"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setVertexTexture:atIndex:"
           ; args = [ Obj "Texture"; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_vertex_texture"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setFragmentTexture:atIndex:"
           ; args = [ Obj "Texture"; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_fragment_texture"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setVertexSamplerState:atIndex:"
           ; args = [ Obj "Sampler"; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_vertex_sampler"; since = None; feature = C.Sampler ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setFragmentSamplerState:atIndex:"
           ; args = [ Obj "Sampler"; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_fragment_sampler"; since = None; feature = C.Sampler ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"
           ; sel = "setVertexSamplerState:lodMinClamp:lodMaxClamp:atIndex:"
           ; args = [ Obj "Sampler"; Scalar Float; Scalar Float; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_vertex_sampler_lod"; since = None; feature = C.Sampler ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"
           ; sel = "setFragmentSamplerState:lodMinClamp:lodMaxClamp:atIndex:"
           ; args = [ Obj "Sampler"; Scalar Float; Scalar Float; Scalar Nsuint ]; ret = None; error = false
           ; ocaml = "render_encoder_set_fragment_sampler_lod"; since = None; feature = C.Sampler ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setDepthStencilState:"
           ; args = [ Opt_obj "Depth_stencil" ]; ret = None; error = false; ocaml = "render_depth_stencil"
           ; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setViewport:"
           ; args = [ Rec "Mtl_viewport" ]; ret = None; error = false; ocaml = "render_encoder_set_viewport"
           ; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setScissorRect:"
           ; args = [ Rec "Mtl_scissor_rect" ]; ret = None; error = false; ocaml = "render_encoder_set_scissor"
           ; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setCullMode:"
           ; args = [ Enum_of "MTLCullMode" ]; ret = None; error = false; ocaml = "render_encoder_set_cull_mode"
           ; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "setFrontFacingWinding:"
           ; args = [ Enum_of "MTLWinding" ]; ret = None; error = false; ocaml = "render_encoder_set_winding"
           ; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"
           ; sel = "setStencilFrontReferenceValue:backReferenceValue:"; args = [ Scalar Nsuint; Scalar Nsuint ]
           ; ret = None; error = false; ocaml = "render_encoder_set_stencil_reference"; since = None
           ; feature = C.Render_pipeline ; pool = true }
  ; Property { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; name = "tileWidth"
             ; ty = Scalar Nsuint; access = Get; ocaml = "render_encoder_tile_width"; since = None
             ; feature = C.Tile_shaders }
  ; Property { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; name = "tileHeight"
             ; ty = Scalar Nsuint; access = Get; ocaml = "render_encoder_tile_height"; since = None
             ; feature = C.Tile_shaders }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "updateFence:afterStages:"
           ; args = [ Obj "Fence"; Enum_of "MTLRenderStages" ]; ret = None; error = false
           ; ocaml = "render_encoder_update_fence"; since = None; feature = C.Fences ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "waitForFence:beforeStages:"
           ; args = [ Obj "Fence"; Enum_of "MTLRenderStages" ]; ret = None; error = false
           ; ocaml = "render_encoder_wait_fence"; since = None; feature = C.Fences ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"
           ; sel = "drawPrimitives:vertexStart:vertexCount:instanceCount:"
           ; args = [ Enum_of "MTLPrimitiveType"; Scalar Nsuint; Scalar Nsuint; Scalar Nsuint ]; ret = None
           ; error = false; ocaml = "render_encoder_draw_primitives"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"
           ; sel = "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:"
           ; args = [ Enum_of "MTLPrimitiveType"; Scalar Nsuint; Enum_of "MTLIndexType"; Obj "Buffer"; Scalar Nsuint ]
           ; ret = None; error = false; ocaml = "render_draw_indexed_basic"; since = None
           ; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"
           ; sel = "drawIndexedPrimitives:indexCount:indexType:indexBuffer:indexBufferOffset:instanceCount:"
           ; args = [ Enum_of "MTLPrimitiveType"; Scalar Nsuint; Enum_of "MTLIndexType"; Obj "Buffer"; Scalar Nsuint
                    ; Scalar Nsuint ]
           ; ret = None; error = false; ocaml = "render_draw_indexed_instances"; since = None
           ; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"
           ; sel = "drawMeshThreadgroups:threadsPerObjectThreadgroup:threadsPerMeshThreadgroup:"
           ; args = [ Rec "Mtl_size"; Rec "Mtl_size"; Rec "Mtl_size" ]; ret = None; error = false
           ; ocaml = "render_encoder_draw_mesh_threadgroups"; since = None; feature = C.Mesh_shaders ; pool = true }
  ; Method { recv = "Render_encoder"; objc = "id<MTLRenderCommandEncoder>"; sel = "dispatchThreadsPerTile:"
           ; args = [ Rec "Mtl_size" ]; ret = None; error = false
           ; ocaml = "render_encoder_dispatch_threads_per_tile"; since = None; feature = C.Tile_shaders ; pool = true }
  (* MTLResidencySet *)
  ; Property { recv = "Residency_set"; objc = "id<MTLResidencySet>"; name = "allocatedSize"; ty = Scalar Nsuint
             ; access = Get; ocaml = "residency_set_allocated_size"; since = Some (15, 0); feature = C.Residency_sets }
  ; Method { recv = "Residency_set"; objc = "id<MTLResidencySet>"; sel = "commit"; args = []; ret = None
           ; error = false; ocaml = "residency_set_commit"; since = Some (15, 0); feature = C.Residency_sets ; pool = true }

  ; Native { ocaml = "is_main_thread"; signature = "unit -> bool"; primitives = [ "caml_rays_metal_is_main_thread" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "generation"; signature = "handle -> int64"; primitives = [ "caml_rays_metal_generation" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "destroy"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_destroy" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "drain_releases"; signature = "unit -> int"; primitives = [ "caml_rays_metal_drain_releases" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "pending_releases"; signature = "unit -> int"; primitives = [ "caml_rays_metal_pending_releases" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "live_handles"; signature = "unit -> int"; primitives = [ "caml_rays_metal_live_handles" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "total_created"; signature = "unit -> int64"; primitives = [ "caml_rays_metal_total_created" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "total_released"; signature = "unit -> int64"; primitives = [ "caml_rays_metal_total_released" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "external_deallocations"; signature = "unit -> int64"; primitives = [ "caml_rays_metal_external_deallocations" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "external_deallocation_mismatches"; signature = "unit -> int64"; primitives = [ "caml_rays_metal_external_deallocation_mismatches" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "resident_bytes"; signature = "unit -> int64"; primitives = [ "caml_rays_metal_resident_bytes" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "default_device"; signature = "unit -> (handle, string) result"; primitives = [ "caml_rays_metal_default_device" ]; reason = "platform/handle lifecycle; not an Objective-C instance call" }
  ; Native { ocaml = "device_supports_residency_sets"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_device_supports_residency_sets" ]; reason = "SDK availability and hardware capability policy" }
  ; Native { ocaml = "device_supports_sparse_textures"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_device_supports_sparse_textures" ]; reason = "SDK availability and hardware capability policy" }
  ; Native { ocaml = "device_supports_placement_sparse"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_device_supports_placement_sparse" ]; reason = "SDK availability and hardware capability policy" }
  ; Native { ocaml = "device_supports_sampler_reduction"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_device_supports_sampler_reduction" ]; reason = "SDK availability and hardware capability policy" }
  ; Native { ocaml = "device_supports_lossy_texture_compression"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_device_supports_lossy_texture_compression" ]; reason = "SDK availability and hardware capability policy" }
  ; Native { ocaml = "device_sparse_tile_size_in_bytes"; signature = "handle -> int -> (int64, string) result"; primitives = [ "caml_rays_metal_device_sparse_tile_size_in_bytes" ]; reason = "sparse hardware/page-size validation and nonzero byte-size result" }
  ; Native { ocaml = "device_sparse_texture_tile_size"; signature = "handle -> int -> int -> int -> int -> ((int * int * int), string) result"; primitives = [ "caml_rays_metal_device_sparse_texture_tile_size" ]; reason = "sparse hardware/layout validation and native MTLSize result" }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "newBufferWithLength:options:"; args = [ Scalar Nsuint; Enum_of "MTLResourceOptions" ]; ret = Some (Obj "Buffer"); error = false; ocaml = "buffer_create"; since = None; feature = C.Buffer ; pool = true }
  ; Property { recv = "Buffer"; objc = "id<MTLBuffer>"; name = "length"; ty = Scalar Nsuint; access = Get; ocaml = "buffer_info_length"; since = None; feature = C.Buffer }
  ; Property { recv = "Buffer"; objc = "id<MTLBuffer>"; name = "storageMode"; ty = Enum_of "MTLStorageMode"; access = Get; ocaml = "buffer_info_storageMode"; since = None; feature = C.Buffer }
  ; Property { recv = "Buffer"; objc = "id<MTLBuffer>"; name = "cpuCacheMode"; ty = Enum_of "MTLCPUCacheMode"; access = Get; ocaml = "buffer_info_cpuCacheMode"; since = None; feature = C.Buffer }
  ; Property { recv = "Buffer"; objc = "id<MTLBuffer>"; name = "hazardTrackingMode"; ty = Enum_of "MTLHazardTrackingMode"; access = Get; ocaml = "buffer_info_hazardTrackingMode"; since = None; feature = C.Buffer }
  ; Property { recv = "Buffer"; objc = "id<MTLBuffer>"; name = "heapOffset"; ty = Scalar Nsuint; access = Get; ocaml = "buffer_info_heapOffset"; since = None; feature = C.Buffer }
  ; Property { recv = "Buffer"; objc = "id<MTLBuffer>"; name = "label"; ty = Str; access = Set; ocaml = "buffer_label"; since = None; feature = C.Buffer }
  ; Native { ocaml = "buffer_write"; signature = "handle -> int64 -> bytes -> int -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_buffer_write" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "buffer_read"; signature = "handle -> int64 -> int -> (bytes, string) result"; primitives = [ "caml_rays_metal_buffer_read" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "resource_make_aliasable"; signature = "handle -> (unit, string) result"; primitives = [ "caml_rays_metal_resource_make_aliasable" ]; reason = "heterogeneous resource handles and heap/texture-view aliasing validation" }
  ; Native { ocaml = "resource_is_aliasable"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_resource_is_aliasable" ]; reason = "heterogeneous Buffer/Texture resource handle decoding" }
  ; Native { ocaml = "heap_buffer_size_and_align"; signature = "handle -> int64 -> int -> (int64 * int64)"; primitives = [ "caml_rays_metal_heap_buffer_size_and_align" ]; reason = "resource-option validation and native MTLSizeAndAlign result" }
  ; Native { ocaml = "heap_texture_size_and_align"; signature = "handle -> texture_descriptor -> (int64 * int64)"; primitives = [ "caml_rays_metal_heap_texture_size_and_align" ]; reason = "texture descriptor construction and native MTLSizeAndAlign result" }
  ; Native { ocaml = "heap_create"; signature = "handle ->\n  (int64 * int * int * int * int * int) ->\n    string option -> (handle, string) result"; primitives = [ "caml_rays_metal_heap_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Property { recv = "Heap"; objc = "id<MTLHeap>"; name = "size"; ty = Scalar Nsuint; access = Get; ocaml = "heap_info_size"; since = None; feature = C.Heaps }
  ; Property { recv = "Heap"; objc = "id<MTLHeap>"; name = "usedSize"; ty = Scalar Nsuint; access = Get; ocaml = "heap_info_usedSize"; since = None; feature = C.Heaps }
  ; Property { recv = "Heap"; objc = "id<MTLHeap>"; name = "currentAllocatedSize"; ty = Scalar Nsuint; access = Get; ocaml = "heap_info_currentAllocatedSize"; since = None; feature = C.Heaps }
  ; Property { recv = "Heap"; objc = "id<MTLHeap>"; name = "storageMode"; ty = Enum_of "MTLStorageMode"; access = Get; ocaml = "heap_info_storageMode"; since = None; feature = C.Heaps }
  ; Property { recv = "Heap"; objc = "id<MTLHeap>"; name = "cpuCacheMode"; ty = Enum_of "MTLCPUCacheMode"; access = Get; ocaml = "heap_info_cpuCacheMode"; since = None; feature = C.Heaps }
  ; Property { recv = "Heap"; objc = "id<MTLHeap>"; name = "hazardTrackingMode"; ty = Enum_of "MTLHazardTrackingMode"; access = Get; ocaml = "heap_info_hazardTrackingMode"; since = None; feature = C.Heaps }
  ; Property { recv = "Heap"; objc = "id<MTLHeap>"; name = "type"; ty = Enum_of "MTLHeapType"; access = Get; ocaml = "heap_info_type"; since = None; feature = C.Heaps }
  ; Method { recv = "Heap"; objc = "id<MTLHeap>"; sel = "maxAvailableSizeWithAlignment:"; args = [ Scalar Nsuint ]; ret = Some (Scalar Nsuint); error = false; ocaml = "heap_max_available_size"; since = None; feature = C.Heaps ; pool = true }
  ; Native { ocaml = "heap_buffer_create"; signature = "handle -> int64 -> int -> int64 option -> (handle, string) result"; primitives = [ "caml_rays_metal_heap_buffer_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "heap_texture_create"; signature = "handle ->\n  texture_descriptor ->\n    int64 option -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_heap_texture_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "residency_set_create"; signature = "handle -> int -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_residency_set_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "residency_set_counts"; signature = "handle -> ((int64 * int64), string) result"; primitives = [ "caml_rays_metal_residency_set_counts" ]; reason = "allocationCount plus NSArray allAllocations snapshot/count" }
  ; Native { ocaml = "residency_set_add_allocation"; signature = "handle -> handle -> (unit, string) result"; primitives = [ "caml_rays_metal_residency_set_add_allocation" ]; reason = "heterogeneous MTLAllocation handle decoding" }
  ; Native { ocaml = "residency_set_add_allocations"; signature = "handle -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_residency_set_add_allocations" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "residency_set_remove_allocation"; signature = "handle -> handle -> (unit, string) result"; primitives = [ "caml_rays_metal_residency_set_remove_allocation" ]; reason = "heterogeneous MTLAllocation handle decoding" }
  ; Native { ocaml = "residency_set_remove_allocations"; signature = "handle -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_residency_set_remove_allocations" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "texture_create"; signature = "handle -> texture_descriptor -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_texture_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "texture_info"; signature = "handle -> int array"; primitives = [ "caml_rays_metal_texture_info" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "texture_is_sparse"; signature = "handle -> bool"; primitives = [ "caml_rays_metal_texture_is_sparse" ]; reason = "SDK availability and hardware capability policy" }
  ; Native { ocaml = "texture_sparse_info"; signature = "handle -> handle -> int -> (int64 array, string) result"; primitives = [ "caml_rays_metal_texture_sparse_info" ]; reason = "array/aggregate marshalling and native validation" }
  ; Property { recv = "Texture"; objc = "id<MTLTexture>"; name = "shareable"; ty = Scalar Bool; access = Get; ocaml = "texture_is_shareable"; since = None; feature = C.Texture }
  ; Native { ocaml = "texture_write"; signature = "handle ->\n  ((int * int * int * int * int * int) * int * int * int * int * int) ->\n    bytes -> (unit, string) result"; primitives = [ "caml_rays_metal_texture_write" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "texture_read"; signature = "handle ->\n  ((int * int * int * int * int * int) * int * int * int * int * int) ->\n    (bytes, string) result"; primitives = [ "caml_rays_metal_texture_read" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "texture_read_into"; signature = "handle ->\n  ((int * int * int * int * int * int) * int * int * int * int * int) ->\n    bytes -> (unit, string) result"; primitives = [ "caml_rays_metal_texture_read_into" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "texture_create_view"; signature = "handle -> texture_view_descriptor -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_texture_create_view" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "sampler_create"; signature = "handle ->\n  (int * int * int * int * int * int * int * int * int * bool * float * float\n    * bool * float * int * bool) -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_sampler_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "depth_stencil_create"; signature = "handle -> depth_stencil_descriptor -> (handle, string) result"; primitives = [ "caml_rays_metal_depth_stencil_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "indirect_command_buffer_create"; signature = "handle ->\n  indirect_command_buffer_descriptor ->\n    int64 -> int64 -> (handle, string) result"; primitives = [ "caml_rays_metal_indirect_command_buffer_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "indirect_command_buffer_reset"; signature = "handle -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_indirect_command_buffer_reset" ]; reason = "checked NSRange assembled from scalar bounds; future record adapter" }
  ; Method { recv = "Indirect_command_buffer"; objc = "id<MTLIndirectCommandBuffer>"; sel = "indirectRenderCommandAtIndex:"; args = [ Scalar Nsuint ]; ret = Some (Obj "Indirect_render_command"); error = false; ocaml = "indirect_render_command"; since = None; feature = C.Render_pipeline ; pool = true }
  ; Method { recv = "Indirect_render_command"; objc = "id<MTLIndirectRenderCommand>"; sel = "setRenderPipelineState:"; args = [ Obj "Render_pipeline" ]; ret = None; error = false; ocaml = "indirect_render_command_set_pipeline"; since = None; feature = C.Render_pipeline ; pool = false }
  ; Method { recv = "Indirect_render_command"; objc = "id<MTLIndirectRenderCommand>"; sel = "setVertexBuffer:offset:atIndex:"; args = [ Obj "Buffer"; Scalar Nsuint; Scalar Nsuint_int ]; ret = None; error = false; ocaml = "indirect_render_command_set_vertex_buffer"; since = None; feature = C.Render_pipeline ; pool = false }
  ; Method { recv = "Indirect_render_command"; objc = "id<MTLIndirectRenderCommand>"; sel = "setFragmentBuffer:offset:atIndex:"; args = [ Obj "Buffer"; Scalar Nsuint; Scalar Nsuint_int ]; ret = None; error = false; ocaml = "indirect_render_command_set_fragment_buffer"; since = None; feature = C.Render_pipeline ; pool = false }
  ; Method { recv = "Indirect_render_command"; objc = "id<MTLIndirectRenderCommand>"; sel = "drawPrimitives:vertexStart:vertexCount:instanceCount:baseInstance:"; args = [ Enum_of "MTLPrimitiveType"; Scalar Nsuint; Scalar Nsuint; Scalar Nsuint; Scalar Nsuint ]; ret = None; error = false; ocaml = "indirect_render_command_draw_primitives"; since = None; feature = C.Render_pipeline ; pool = false }
  ; Native { ocaml = "library_compile"; signature = "handle -> string -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_library_compile" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "library_compile_descriptor"; signature = "handle -> string -> library_compile_descriptor -> (handle, string) result"; primitives = [ "caml_rays_metal_library_compile_descriptor" ]; reason = "descriptor construction and checked object graphs" }
  ; Property { recv = "Library"; objc = "id<MTLLibrary>"; name = "type"; ty = Enum_of "MTLLibraryType"; access = Get; ocaml = "library_kind"; since = None; feature = C.Compute_pipeline }
  ; Native { ocaml = "library_function_names"; signature = "handle -> string array"; primitives = [ "caml_rays_metal_library_function_names" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "function_find"; signature = "handle -> string -> (handle, string) result"; primitives = [ "caml_rays_metal_function_find" ]; reason = "checked function name/device identity after SDK lookup" }
  ; Property { recv = "Function"; objc = "id<MTLFunction>"; name = "name"; ty = Str; access = Get; ocaml = "function_name"; since = None; feature = C.Compute_pipeline }
  ; Property { recv = "Function"; objc = "id<MTLFunction>"; name = "functionType"; ty = Enum_of "MTLFunctionType"; access = Get; ocaml = "function_kind"; since = None; feature = C.Compute_pipeline }
  ; Native { ocaml = "function_specialize"; signature = "handle ->\n  string ->\n    function_constant_value array -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_function_specialize" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "dynamic_library_create"; signature = "handle -> handle -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_dynamic_library_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "dynamic_library_load_file"; signature = "handle -> string -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_dynamic_library_load_file" ]; reason = "NSString-to-NSURL conversion and NSError handling" }
  ; Property { recv = "Dynamic_library"; objc = "id<MTLDynamicLibrary>"; name = "installName"; ty = Str; access = Get; ocaml = "dynamic_library_install_name"; since = None; feature = C.Dynamic_libraries }
  ; Native { ocaml = "dynamic_library_serialize"; signature = "handle -> string -> (unit, string) result"; primitives = [ "caml_rays_metal_dynamic_library_serialize" ]; reason = "NSString-to-NSURL conversion and NSError handling" }
  ; Native { ocaml = "binary_archive_create"; signature = "handle -> string option -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_binary_archive_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "binary_archive_add_compute"; signature = "handle -> handle -> handle array -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_binary_archive_add_compute" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "binary_archive_serialize"; signature = "handle -> string -> (unit, string) result"; primitives = [ "caml_rays_metal_binary_archive_serialize" ]; reason = "NSString-to-NSURL conversion and NSError handling" }
  ; Native { ocaml = "compiler_create"; signature = "handle -> handle option -> string option -> (handle, string) result"; primitives = [ "caml_rays_metal_compiler_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "compiler_create_render_pipeline"; signature = "handle ->\n  metal4_render_descriptor ->\n    ((handle * render_pipeline_reflection), string) result"; primitives = [ "caml_rays_metal_compiler_create_render_pipeline" ]; reason = "descriptor construction and checked object graphs" }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "newComputePipelineStateWithFunction:error:"; args = [ Obj "Function" ]; ret = Some (Obj "Compute_pipeline"); error = true; ocaml = "compute_pipeline_create"; since = None; feature = C.Compute_pipeline ; pool = true }
  ; Native { ocaml = "compute_pipeline_create_descriptor"; signature = "handle ->\n  handle ->\n    compute_pipeline_descriptor ->\n      ((handle * pipeline_binding_info array), string) result"; primitives = [ "caml_rays_metal_compute_pipeline_create_descriptor" ]; reason = "array/aggregate marshalling and native validation" }
  ; Property { recv = "Compute_pipeline"; objc = "id<MTLComputePipelineState>"; name = "maxTotalThreadsPerThreadgroup"; ty = Scalar Nsuint; access = Get; ocaml = "compute_pipeline_max_total_threads"; since = None; feature = C.Compute_pipeline }
  ; Native { ocaml = "command_queue_add_residency_sets"; signature = "handle -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_command_queue_add_residency_sets" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "command_queue_remove_residency_sets"; signature = "handle -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_command_queue_remove_residency_sets" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "accel_descriptor_primitive"; signature = "accel_primitive_raw -> (handle, string) result"; primitives = [ "caml_rays_metal_accel_descriptor_primitive" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "accel_descriptor_instances"; signature = "accel_instances_raw -> (handle, string) result"; primitives = [ "caml_rays_metal_accel_descriptor_instances" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "accel_descriptor_sizes"; signature = "handle -> handle -> ((int64 * int64 * int64), string) result"; primitives = [ "caml_rays_metal_accel_descriptor_sizes" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "accel_encoder_build_descriptor"; signature = "handle -> handle -> handle -> handle -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_accel_encoder_build_descriptor" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "accel_encoder_refit_descriptor"; signature = "handle ->\n  handle -> handle -> handle -> handle -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_accel_encoder_refit_descriptor_bytecode"; "caml_rays_metal_accel_encoder_refit_descriptor" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "accel_instance_layout"; signature = "int -> int array"; primitives = [ "caml_rays_metal_accel_instance_layout" ]; reason = "array/aggregate marshalling and native validation" }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "newAccelerationStructureWithSize:"; args = [ Scalar Nsuint ]; ret = Some (Obj "Acceleration_structure"); error = false; ocaml = "acceleration_structure_create"; since = None; feature = C.Ray_tracing ; pool = true }
  ; Method { recv = "Acceleration_encoder"; objc = "id<MTLAccelerationStructureCommandEncoder>"; sel = "copyAccelerationStructure:toAccelerationStructure:"; args = [ Obj "Acceleration_structure"; Obj "Acceleration_structure" ]; ret = None; error = false; ocaml = "acceleration_encoder_copy"; since = None; feature = C.Ray_tracing ; pool = true }
  ; Method { recv = "Acceleration_encoder"; objc = "id<MTLAccelerationStructureCommandEncoder>"; sel = "copyAndCompactAccelerationStructure:toAccelerationStructure:"; args = [ Obj "Acceleration_structure"; Obj "Acceleration_structure" ]; ret = None; error = false; ocaml = "acceleration_encoder_copy_and_compact"; since = None; feature = C.Ray_tracing ; pool = true }
  ; Method { recv = "Compute_pipeline"; objc = "id<MTLComputePipelineState>"; sel = "functionHandleWithFunction:"; args = [ Obj "Function" ]; ret = Some (Obj "Function_handle"); error = false; ocaml = "compute_pipeline_function_handle"; since = None; feature = C.Function_tables ; pool = true }
  ; Native { ocaml = "compute_pipeline_visible_function_table"; signature = "handle -> int64 -> (handle, string) result"; primitives = [ "caml_rays_metal_compute_pipeline_visible_function_table" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "compute_pipeline_intersection_function_table"; signature = "handle -> int64 -> (handle, string) result"; primitives = [ "caml_rays_metal_compute_pipeline_intersection_function_table" ]; reason = "descriptor construction and checked object graphs" }
  ; Method { recv = "Visible_function_table"; objc = "id<MTLVisibleFunctionTable>"; sel = "setFunction:atIndex:"; args = [ Opt_obj "Function_handle"; Scalar Nsuint_int ]; ret = None; error = false; ocaml = "visible_function_table_set_function"; since = None; feature = C.Function_tables ; pool = true }
  ; Method { recv = "Intersection_function_table"; objc = "id<MTLIntersectionFunctionTable>"; sel = "setFunction:atIndex:"; args = [ Opt_obj "Function_handle"; Scalar Nsuint_int ]; ret = None; error = false; ocaml = "intersection_function_table_set_function"; since = None; feature = C.Function_tables ; pool = true }
  ; Method { recv = "Intersection_function_table"; objc = "id<MTLIntersectionFunctionTable>"; sel = "setBuffer:offset:atIndex:"; args = [ Opt_obj "Buffer"; Scalar Nsuint; Scalar Nsuint_int ]; ret = None; error = false; ocaml = "intersection_function_table_set_buffer"; since = None; feature = C.Function_tables ; pool = true }
  ; Native { ocaml = "command_buffer_use_residency_sets"; signature = "handle -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_command_buffer_use_residency_sets" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "command_buffer_render_encoder_attachments"; signature = "handle ->\n  handle ->\n    handle option ->\n      handle option ->\n        (float * float * float * float) -> (handle, string) result"; primitives = [ "caml_rays_metal_command_buffer_render_encoder_attachments_bytecode"; "caml_rays_metal_command_buffer_render_encoder_attachments" ]; reason = "temporary render-pass descriptor graph and attachment ownership" }
  ; Native { ocaml = "layer_create"; signature = "handle -> (handle, string) result"; primitives = [ "caml_rays_metal_layer_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "layer_adopt_borrowed"; signature = "handle -> Native_layer_token.t -> int64 -> int64 -> (handle, string) result"; primitives = [ "caml_rays_metal_layer_adopt_borrowed" ]; reason = "borrowed native layer ownership/token validation" }
  ; Native { ocaml = "layer_configure"; signature = "handle ->\n  int ->\n    int -> int -> (bool * int * bool * bool * bool) -> (unit, string) result"; primitives = [ "caml_rays_metal_layer_configure" ]; reason = "checked presentation flags/format and native CGSize marshalling" }
  ; Method { recv = "Metal_layer"; objc = "CAMetalLayer *"; sel = "nextDrawable"; args = [  ]; ret = Some (Opt_obj "Metal_drawable"); error = false; ocaml = "layer_next_drawable"; since = None; feature = C.Surface ; pool = true }
  ; Native { ocaml = "drawable_texture"; signature = "handle -> ((handle * int * int * int), string) result"; primitives = [ "caml_rays_metal_drawable_texture" ]; reason = "owned texture plus native dimension/format snapshot" }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "presentDrawable:"; args = [ Obj "Metal_drawable" ]; ret = None; error = false; ocaml = "command_buffer_present"; since = None; feature = C.Surface ; pool = false }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "presentDrawable:atTime:"; args = [ Obj "Metal_drawable"; Scalar Double ]; ret = None; error = false; ocaml = "command_buffer_present_at_time"; since = None; feature = C.Surface ; pool = true }
  ; Method { recv = "Command_buffer"; objc = "id<MTLCommandBuffer>"; sel = "presentDrawable:afterMinimumDuration:"; args = [ Obj "Metal_drawable"; Scalar Double ]; ret = None; error = false; ocaml = "command_buffer_present_after_duration"; since = None; feature = C.Surface ; pool = true }
  ; Native { ocaml = "presentation_command_snapshot"; signature = "handle -> (presentation_command_snapshot, string) result"; primitives = [ "caml_rays_metal_presentation_command_snapshot" ]; reason = "completion state, diagnostic string and native timing snapshot" }
  ; Native { ocaml = "command_buffer_cancel_handler"; signature = "nativeint -> unit"; primitives = [ "caml_rays_metal_command_buffer_cancel_handler" ]; reason = "callback root ownership and cancellation" }
  ; Class_method { objc = "MTLRenderPassDescriptor"; sel = "renderPassDescriptor"; args = []; ret = Some (Obj "Render_pass_descriptor"); ocaml = "render_pass_descriptor_create"; since = None; feature = C.Render_pipeline }
  ; Native { ocaml = "render_pass_descriptor_set_sizes"; signature = "handle -> int -> int -> int -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_pass_descriptor_set_sizes" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "render_pass_sample_set"; signature = "handle ->\n  int64 ->\n    handle option ->\n      int64 -> int64 -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_render_pass_sample_set_bytecode"; "caml_rays_metal_render_pass_sample_set" ]; reason = "indexed sample-attachment graph and sample index validation" }
  ; Native { ocaml = "render_pass_resolve_texture"; signature = "handle -> handle option -> bool -> (handle option, string) result"; primitives = [ "caml_rays_metal_render_pass_resolve_texture" ]; reason = "nullable resolve-texture access through a descriptor child" }
  ; Native { ocaml = "render_pass_color_store_action"; signature = "handle -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_pass_color_store_action" ]; reason = "store action on descriptor colorAttachments[0]; future property-path lowering" }
  ; Native { ocaml = "render_pass_color_load_action"; signature = "handle -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_pass_color_load_action" ]; reason = "load action on descriptor colorAttachments[0]; future property-path lowering" }
  ; Native { ocaml = "render_pass_descriptor_set_attachments"; signature = "handle ->\n  handle ->\n    handle option ->\n      handle option ->\n        handle option ->\n          (float * float * float * float) -> (unit, string) result"; primitives = [ "caml_rays_metal_render_pass_descriptor_set_attachments_bytecode"; "caml_rays_metal_render_pass_descriptor_set_attachments" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "render_encoder_use_heaps"; signature = "handle -> handle array -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_encoder_use_heaps" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "render_encoder_use_resources"; signature = "handle -> handle array -> int -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_encoder_use_resources" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "render_encoder_execute_icb_range"; signature = "handle -> handle -> int -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_encoder_execute_icb_range" ]; reason = "NSRange assembled from scalar bounds; future record adapter" }
  ; Native { ocaml = "render_encoder_execute_indexed_draws"; signature = "handle ->\n  handle array ->\n    handle array array ->\n      int array array ->\n        int64 array array ->\n          int array array ->\n            int array ->\n              int64 array ->\n                int array ->\n                  handle array -> int64 array -> (unit, string) result"; primitives = [ "caml_rays_metal_render_encoder_execute_indexed_draws_bytecode"; "caml_rays_metal_render_encoder_execute_indexed_draws" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "render_encoder_set_vertex_bytes"; signature = "handle -> bytes -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_encoder_set_vertex_bytes" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "render_encoder_set_fragment_bytes"; signature = "handle -> bytes -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_encoder_set_fragment_bytes" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "render_stage_buffer"; signature = "handle ->\n  int -> handle option -> int64 -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_render_stage_buffer_bytecode"; "caml_rays_metal_render_stage_buffer" ]; reason = "stage/stride selector dispatch with nullable buffer binding" }
  ; Native { ocaml = "render_stage_bytes"; signature = "handle -> int -> bytes -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_render_stage_bytes_bytecode"; "caml_rays_metal_render_stage_bytes" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Native { ocaml = "render_stage_sampler"; signature = "handle ->\n  int ->\n    handle option ->\n      bool -> (float * float) -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_render_stage_sampler_bytecode"; "caml_rays_metal_render_stage_sampler" ]; reason = "stage/LOD selector dispatch and native sampler validation" }
  ; Native { ocaml = "render_stage_texture"; signature = "handle -> int -> handle option -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_render_stage_texture" ]; reason = "stage selector dispatch and nullable texture binding" }
  ; Native { ocaml = "render_pass_depth_stencil_actions"; signature = "handle -> int -> int -> float -> int -> int -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_render_pass_depth_stencil_actions_bytecode"; "caml_rays_metal_render_pass_depth_stencil_actions" ]; reason = "conditional depth/stencil child updates and native clear-value conversion" }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "setComputePipelineState:"; args = [ Obj "Compute_pipeline" ]; ret = None; error = false; ocaml = "compute_encoder_set_pipeline"; since = None; feature = C.Compute_pipeline ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "setBuffer:offset:atIndex:"; args = [ Obj "Buffer"; Scalar Nsuint; Scalar Nsuint_int ]; ret = None; error = false; ocaml = "compute_encoder_set_buffer"; since = None; feature = C.Compute_pipeline ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "setTexture:atIndex:"; args = [ Obj "Texture"; Scalar Nsuint_int ]; ret = None; error = false; ocaml = "compute_encoder_set_texture"; since = None; feature = C.Compute_pipeline ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "dispatchThreads:threadsPerThreadgroup:"; args = [ Tuple "Mtl_size_int"; Tuple "Mtl_size_int" ]; ret = None; error = false; ocaml = "compute_encoder_dispatch"; since = None; feature = C.Compute_pipeline ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "setAccelerationStructure:atBufferIndex:"; args = [ Opt_obj "Acceleration_structure"; Scalar Nsuint ]; ret = None; error = false; ocaml = "compute35_acceleration"; since = None; feature = C.Ray_tracing ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "setVisibleFunctionTable:atBufferIndex:"; args = [ Opt_obj "Visible_function_table"; Scalar Nsuint ]; ret = None; error = false; ocaml = "compute35_visible"; since = None; feature = C.Function_tables ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "setIntersectionFunctionTable:atBufferIndex:"; args = [ Opt_obj "Intersection_function_table"; Scalar Nsuint ]; ret = None; error = false; ocaml = "compute35_intersection"; since = None; feature = C.Function_tables ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "dispatchThreadgroups:threadsPerThreadgroup:"; args = [ Tuple "Mtl_size_int"; Tuple "Mtl_size_int" ]; ret = None; error = false; ocaml = "compute35_dispatch_groups"; since = None; feature = C.Compute_pipeline ; pool = false }
  ; Native { ocaml = "compute35_bytes_plain"; signature = "handle -> bytes -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_compute35_bytes_plain" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "updateFence:"; args = [ Obj "Fence" ]; ret = None; error = false; ocaml = "compute35_update_fence"; since = None; feature = C.Fences ; pool = false }
  ; Method { recv = "Compute_encoder"; objc = "id<MTLComputeCommandEncoder>"; sel = "waitForFence:"; args = [ Obj "Fence" ]; ret = None; error = false; ocaml = "compute35_wait_fence"; since = None; feature = C.Fences ; pool = false }
  ; Native { ocaml = "compute35_heaps"; signature = "handle -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_compute35_heaps" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "compute35_accelerations"; signature = "handle -> handle array -> (unit, string) result"; primitives = [ "caml_rays_metal_compute35_accelerations" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "resource_state_encoder_update_texture_mapping"; signature = "handle ->\n  handle ->\n    int ->\n      (int * int * int * int * int * int) ->\n        int -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_resource_state_encoder_update_texture_mapping_bytecode"; "caml_rays_metal_resource_state_encoder_update_texture_mapping" ]; reason = "sparse region/slice validation and native MTLRegion marshalling" }
  ; Native { ocaml = "blit_encoder_copy_buffer_to_texture"; signature = "handle ->\n  handle ->\n    handle ->\n      (int64 * int * int * (int * int * int) * int * int * (int * int * int))\n        -> (unit, string) result"; primitives = [ "caml_rays_metal_blit_encoder_copy_buffer_to_texture" ]; reason = "checked packed copy specification and native MTLSize/MTLOrigin marshalling" }
  ; Native { ocaml = "command_buffer_wait"; signature = "handle -> unit"; primitives = [ "caml_rays_metal_command_buffer_wait" ]; reason = "blocking wait releases the OCaml runtime lock" }
  ; Native { ocaml = "command_buffer_error"; signature = "handle -> string option"; primitives = [ "caml_rays_metal_command_buffer_error" ]; reason = "nullable NSError-to-diagnostic-string conversion" }

  ; Native { ocaml = "mesh_pipeline_descriptor_owned"; signature = "mesh_pipeline_descriptor_inputs -> (handle, string) result"; primitives = [ "caml_rays_mesh_pipeline_descriptor" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "tile_pipeline_descriptor_owned"; signature = "tile_pipeline_descriptor_inputs -> (handle, string) result"; primitives = [ "caml_rays_tile_pipeline_descriptor" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "counter_sets"; signature = "handle -> ((handle * string) array, string) result"; primitives = [ "caml_rays_metal_counter_sets" ]; reason = "array/aggregate marshalling and native validation" }
  ; Class_method { objc = "MTLCounterSampleBufferDescriptor"; sel = "new"; args = []; ret = Some (Obj "Counter_descriptor"); ocaml = "counter_descriptor_create"; since = None; feature = C.Timestamp_queries }
  ; Native { ocaml = "counter_set_counters"; signature = "handle -> ((handle * string) array, string) result"; primitives = [ "caml_rays_metal_counter_set_counters" ]; reason = "array/aggregate marshalling and native validation" }
  ; Native { ocaml = "counter_descriptor_set"; signature = "handle -> handle -> string option -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_counter_descriptor_set" ]; reason = "descriptor construction and checked object graphs" }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "newCounterSampleBufferWithDescriptor:error:"; args = [ Obj "Counter_descriptor" ]; ret = Some (Obj "Counter_sample_buffer"); error = true; ocaml = "counter_sample_buffer_create"; since = None; feature = C.Timestamp_queries ; pool = true }
  ; Native { ocaml = "counter_sample_resolve"; signature = "handle -> int64 -> int64 -> (bytes, string) result"; primitives = [ "caml_rays_metal_counter_sample_resolve" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "supportsCounterSampling:"; args = [ Enum_of "MTLCounterSamplingPoint" ]; ret = Some (Scalar Bool); error = false; ocaml = "counter_supports_sampling"; since = None; feature = C.Timestamp_queries ; pool = true }
  ; Class_method { objc = "MTLBlitPassDescriptor"; sel = "blitPassDescriptor"; args = []; ret = Some (Obj "Blit_pass_descriptor"); ocaml = "blit_pass_create"; since = None; feature = C.Timestamp_queries }
  ; Property { recv = "Blit_pass_descriptor"; objc = "MTLBlitPassDescriptor *"; name = "sampleBufferAttachments"; ty = Obj "Blit_sample_attachment_array"; access = Get; ocaml = "blit_pass_attachments"; since = None; feature = C.Timestamp_queries }
  ; Native { ocaml = "blit_attachment"; signature = "handle -> int64 -> handle option -> int64 -> int64 -> (handle, string) result"; primitives = [ "caml_rays_metal_blit_attachment" ]; reason = "checked native descriptor/object marshalling" }
  ; Native { ocaml = "device_library_data"; signature = "handle -> string -> (handle, string) result"; primitives = [ "caml_rays_metal_device_library_data" ]; reason = "byte buffers/native memory and checked ranges" }
  ; Method { recv = "Function"; objc = "id<MTLFunction>"; sel = "newArgumentEncoderWithBufferIndex:"; args = [ Scalar Nsuint ]; ret = Some (Obj "Shader_argument_encoder"); error = false; ocaml = "shader_function_argument_encoder"; since = None; feature = C.Compute_pipeline ; pool = true }
  ; Property { recv = "Shared_event"; objc = "id<MTLSharedEvent>"; name = "signaledValue"; ty = Scalar Nsuint; access = Get_set; ocaml = "command_shared_event_value"; since = None; feature = C.Event_synchronization }
  ; Native { ocaml = "mesh_descriptor_set_mechanical"; signature = "handle ->\n  string option ->\n    int64 ->\n      int64 ->\n        mesh_tile_threadgroup_size ->\n          mesh_tile_threadgroup_size -> (unit, string) result"; primitives = [ "caml_rays_metal_mesh_descriptor_set_mechanical_bytecode"; "caml_rays_metal_mesh_descriptor_set_mechanical" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "tile_descriptor_set_mechanical"; signature = "handle ->\n  string option -> mesh_tile_threadgroup_size -> (unit, string) result"; primitives = [ "caml_rays_metal_tile_descriptor_set_mechanical" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "command_shared_event_create"; signature = "handle -> ((handle * int64), string) result"; primitives = [ "caml_rays_metal_command_shared_event_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "mesh_pipeline_compile"; signature = "handle ->\n  handle -> int64 -> ((handle * render_pipeline_reflection), string) result"; primitives = [ "caml_rays_metal_mesh_pipeline_compile" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "tile_pipeline_compile"; signature = "handle ->\n  handle -> int64 -> ((handle * render_pipeline_reflection), string) result"; primitives = [ "caml_rays_metal_tile_pipeline_compile" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "argument_encoder_snapshot"; signature = "handle -> ((string option * int64 * int64 * int64), string) result"; primitives = [ "caml_rays_metal_argument_encoder_snapshot" ]; reason = "nullable label plus length/alignment/device identity snapshot" }
  ; Native { ocaml = "argument_encoder_set_buffer"; signature = "handle -> handle -> int64 -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_argument_encoder_set_buffer" ]; reason = "buffer-range/device checks and selector dispatch" }
  ; Native { ocaml = "argument_encoder_single"; signature = "handle -> int -> handle -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_argument_encoder_single" ]; reason = "heterogeneous handle-kind selector dispatch and device/index checks" }
  ; Native { ocaml = "acceleration_encoder_write_type"; signature = "handle -> handle -> handle -> int64 -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_acceleration_encoder_write_type" ]; reason = "compacted-size type selector dispatch and destination range validation" }
  ; Native { ocaml = "blit_copy"; signature = "handle -> int -> handle -> handle -> blit_copy_spec -> (unit, string) result"; primitives = [ "caml_rays_metal_blit_copy" ]; reason = "variant copy specification, resource ranges and native struct marshalling" }
  ; Native { ocaml = "blit_fill_mipmap"; signature = "handle -> handle -> bool -> (int64 * int64 * int64) -> (unit, string) result"; primitives = [ "caml_rays_metal_blit_fill_mipmap" ]; reason = "fill/mipmap selector dispatch and checked range/value conversion" }
  ; Method { recv = "Blit_encoder"; objc = "id<MTLBlitCommandEncoder>"; sel = "updateFence:"; args = [ Obj "Fence" ]; ret = None; error = false; ocaml = "blit_update_fence"; since = None; feature = C.Fences ; pool = true }
  ; Method { recv = "Blit_encoder"; objc = "id<MTLBlitCommandEncoder>"; sel = "waitForFence:"; args = [ Obj "Fence" ]; ret = None; error = false; ocaml = "blit_wait_fence"; since = None; feature = C.Fences ; pool = true }
  ; Native { ocaml = "blit_counter"; signature = "handle ->\n  handle ->\n    int64 -> int64 -> handle -> int64 -> bool -> (unit, string) result"; primitives = [ "caml_rays_metal_blit_counter_bytecode"; "caml_rays_metal_blit_counter" ]; reason = "sample/resolve selector dispatch with sample/destination range validation" }
  ; Native { ocaml = "compute_pass_create"; signature = "int -> (handle, string) result"; primitives = [ "caml_rays_metal_compute_pass_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Property { recv = "Compute_pass_descriptor"; objc = "MTLComputePassDescriptor *"; name = "dispatchType"; ty = Enum_of "MTLDispatchType"; access = Get; ocaml = "compute_pass_snapshot_dispatchType"; since = None; feature = C.Compute_pipeline }
  ; Property { recv = "Compute_pass_descriptor"; objc = "MTLComputePassDescriptor *"; name = "sampleBufferAttachments"; ty = Obj "Compute_sample_attachment_array"; access = Get; ocaml = "compute_pass_snapshot_sampleBufferAttachments"; since = None; feature = C.Compute_pipeline }
  ; Native { ocaml = "compute_pass_attachment"; signature = "handle -> int64 -> handle option -> int64 -> int64 -> (handle, string) result"; primitives = [ "caml_rays_metal_compute_pass_attachment" ]; reason = "indexed attachment graph and nullable sample-buffer range validation" }
  ; Property { recv = "Compute_sample_attachment"; objc = "MTLComputePassSampleBufferAttachmentDescriptor *"; name = "sampleBuffer"; ty = Opt_obj "Counter_sample_buffer"; access = Get; ocaml = "compute_pass_attachment_snapshot_sampleBuffer"; since = None; feature = C.Timestamp_queries }
  ; Property { recv = "Compute_sample_attachment"; objc = "MTLComputePassSampleBufferAttachmentDescriptor *"; name = "startOfEncoderSampleIndex"; ty = Scalar Nsint; access = Get; ocaml = "compute_pass_attachment_snapshot_startOfEncoderSampleIndex"; since = None; feature = C.Timestamp_queries }
  ; Property { recv = "Compute_sample_attachment"; objc = "MTLComputePassSampleBufferAttachmentDescriptor *"; name = "endOfEncoderSampleIndex"; ty = Scalar Nsint; access = Get; ocaml = "compute_pass_attachment_snapshot_endOfEncoderSampleIndex"; since = None; feature = C.Timestamp_queries }
  ; Native { ocaml = "indirect_render_draw_indexed"; signature = "handle ->\n  int ->\n    int64 ->\n      int ->\n        handle ->\n          int64 -> int64 -> int64 -> int64 -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_indirect_render_draw_indexed_bytecode"; "caml_rays_metal_indirect_render_draw_indexed" ]; reason = "index layout, device identity and byte-range/overflow validation" }
  ; Native { ocaml = "render93_array_snapshot"; signature = "handle -> int -> int -> (int64 array, string) result"; primitives = [ "caml_rays_metal_render93_array_snapshot" ]; reason = "array/aggregate marshalling and native validation" }
  ; Method { recv = "Blit_sample_attachment_array"; objc = "MTLBlitPassSampleBufferAttachmentDescriptorArray *"; sel = "objectAtIndexedSubscript:"; args = [ Scalar Nsuint ]; ret = Some (Opt_obj "Blit_sample_attachment"); error = false; ocaml = "blit_pass10_attachment_at"; since = None; feature = C.Timestamp_queries ; pool = true }
  ; Native { ocaml = "blit_pass10_set_sample_buffer"; signature = "handle -> handle option -> int64 -> (unit, string) result"; primitives = [ "caml_rays_metal_blit_pass10_set_sample_buffer" ]; reason = "nullable counter-buffer attachment and authoritative device identity validation" }
  ; Property { recv = "Metal_drawable"; objc = "id<MTLDrawable>"; name = "drawableID"; ty = Scalar Nsuint; access = Get; ocaml = "drawable10_snapshot_drawableID"; since = None; feature = C.Surface }
  ; Property { recv = "Metal_drawable"; objc = "id<MTLDrawable>"; name = "presentedTime"; ty = Scalar Double; access = Get; ocaml = "drawable10_snapshot_presentedTime"; since = None; feature = C.Surface }
  ; Native { ocaml = "binary_archive5_configured_descriptor"; signature = "int -> handle -> handle option -> int64 -> (handle, string) result"; primitives = [ "caml_rays_metal_binary_archive5_configured_descriptor" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "binary_archive5_add"; signature = "handle ->\n  int ->\n    handle ->\n      handle option ->\n        int64 -> int64 -> int64 option -> (unit, string) result"; primitives = [ "caml_rays_metal_binary_archive5_add_bytecode"; "caml_rays_metal_binary_archive5_add" ]; reason = "pipeline-kind selector dispatch and checked descriptor graph" }
  ; Native { ocaml = "device_sample_timestamps"; signature = "handle -> ((int64 * int64), string) result"; primitives = [ "caml_rays_metal_device_sample_timestamps" ]; reason = "native out parameters" }
  ; Method { recv = "Device"; objc = "id<MTLDevice>"; sel = "queryTimestampFrequency"; args = [  ]; ret = Some (Scalar Nsuint); error = false; ocaml = "device_timestamp_frequency"; since = Some (26, 0); feature = C.Timestamp_queries ; pool = true }
  ; Native { ocaml = "shared_event_wait"; signature = "handle -> int64 -> int64 -> (bool, string) result"; primitives = [ "caml_rays_metal_shared_event_wait" ]; reason = "blocking wait releases the OCaml runtime lock" }
  ; Native { ocaml = "mesh_tile_descriptor_set_color_format"; signature = "handle -> bool -> int -> int -> (unit, string) result"; primitives = [ "caml_rays_metal_mesh_tile_descriptor_set_color_format" ]; reason = "mesh/tile descriptor child selection and attachment index validation" }
  ; Class_method { objc = "MTLFXSpatialScalerDescriptor"; sel = "supportsDevice:"; args = [Obj "Device"]; ret = Some (Scalar Bool); ocaml = "fx_spatial_supported"; since = Some (13, 0); feature = C.Metal_fx }
  ; Native { ocaml = "fx_spatial_create"; signature = "handle -> (int * int * int * int * int * int) -> (handle, string) result"; primitives = [ "caml_rays_metal_fx_spatial_create" ]; reason = "descriptor construction and checked object graphs" }
  ; Native { ocaml = "fx_spatial_encode"; signature = "handle -> handle -> handle -> handle -> (unit, string) result"; primitives = [ "caml_rays_metal_fx_spatial_encode" ]; reason = "texture dimension/format/usage validation and temporary scaler-slot ownership" }

  ; Record { sdk = "MTLSize"; ocaml = "Mtl_size_int"; fields = ["width", Nsuint_int; "height", Nsuint_int; "depth", Nsuint_int]; feature = C.Compute_pipeline }
  ]
