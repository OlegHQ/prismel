type receiver =
  | Render_encoder4
  | Compute_encoder4
  | Compute_pipeline
  | Device

type enum_type =
  | Winding
  | Cull_mode
  | Depth_clip_mode
  | Triangle_fill_mode

type enum_case =
  { sdk_id : string
  ; value : int
  }

type argument_kind =
  | Enum_int of
      { enum_type : enum_type
      ; cases : enum_case list
      }
  | Unsigned_int of
      { minimum : int
      ; multiple_of : int option
      }

type argument =
  { name : string
  ; kind : argument_kind
  ; error : string
  }

type availability =
  { macos_major : int
  ; macos_minor : int
  ; unavailable_error : string
  }

type expectation =
  { kind : string
  ; owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; attributes : string list
  ; availability : availability
  }

type direct_void =
  { ocaml_name : string
  ; c_symbol : string
  ; receiver : receiver
  ; arguments : argument list
  }

type result_kind =
  | Nsuint_to_checked_int64 of
      { overflow_error : string
      }

type direct_getter =
  { ocaml_name : string
  ; c_symbol : string
  ; receiver : receiver
  ; result : result_kind
  }

type generation =
  | Direct_void of direct_void
  | Direct_getter of direct_getter

type companion =
  { sdk_id : string
  ; kind : string
  ; owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; attributes : string list
  }

type safe_api =
  { operation : string
  ; module_path : string list
  ; value_name : string
  ; test_value : string
  ; test_call : string list
  }

type disposition =
  | Generate of generation
  | Manual
  | Exclude of string
  | Pending

type entry =
  { sdk_id : string
  ; expect : expectation
  ; companions : companion list
  ; disposition : disposition
  ; safe_api : safe_api option
  }

let expected_sdk_version = "26.5"

let metal4_availability =
  { macos_major = 26
  ; macos_minor = 0
  ; unavailable_error = "Metal 4 commands require macOS 26"
  }

let macos_10_13_availability =
  { macos_major = 10
  ; macos_minor = 13
  ; unavailable_error = "Metal device limit requires macOS 10.13"
  }

let compute_pipeline_macos_10_13_availability =
  { macos_major = 10
  ; macos_minor = 13
  ; unavailable_error =
      "Metal compute-pipeline static threadgroup-memory length requires macOS 10.13"
  }

let safe_api ~module_path ~value_name ~test_value =
  { operation = String.concat "." ("Metal" :: module_path @ [ value_name ])
  ; module_path
  ; value_name
  ; test_value
  ; test_call = module_path @ [ value_name ]
  }

let direct_void ~sdk_id ~owner ~header ~name ~signature ~ocaml_name ~c_symbol
    ~receiver ~arguments ~safe_api =
  { sdk_id
  ; expect =
      { kind = "method"
      ; owner
      ; name
      ; header
      ; signature
      ; attributes = []
      ; availability = metal4_availability
      }
  ; companions = []
  ; disposition =
      Generate
        (Direct_void
           { ocaml_name
           ; c_symbol
           ; receiver
           ; arguments
           })
  ; safe_api
  }

let enum_setter ~sdk_id ~name ~signature ~ocaml_name ~c_symbol ~argument_name
    ~enum_type ~cases ~error ~safe_value =
  direct_void ~sdk_id ~owner:"MTL4RenderCommandEncoder"
    ~header:"Metal/MTL4RenderCommandEncoder.h" ~name ~signature ~ocaml_name
    ~c_symbol ~receiver:Render_encoder4
    ~arguments:
      [ { name = argument_name
        ; kind = Enum_int { enum_type; cases }
        ; error
        }
      ]
    ~safe_api:
      (Some
         (safe_api ~module_path:[ "Command4"; "Render_encoder" ]
            ~value_name:safe_value
            ~test_value:"test_metal4_raster_state_commands"))

let unsigned_argument ?(minimum = 0) ?multiple_of name error =
  { name; kind = Unsigned_int { minimum; multiple_of }; error }

let entries =
  [ enum_setter
      ~sdk_id:"method:-[MTL4RenderCommandEncoder setCullMode:]"
      ~name:"setCullMode:" ~signature:"instance (MTLCullMode) -> void"
      ~ocaml_name:"command4_render_encoder_set_cull_mode"
      ~c_symbol:"caml_prismel_metal_command4_render_encoder_set_cull_mode"
      ~argument_name:"mode" ~enum_type:Cull_mode
      ~cases:
        [ { sdk_id = "enum-case:MTLCullMode:MTLCullModeNone"; value = 0 }
        ; { sdk_id = "enum-case:MTLCullMode:MTLCullModeFront"; value = 1 }
        ; { sdk_id = "enum-case:MTLCullMode:MTLCullModeBack"; value = 2 }
        ]
      ~error:"Metal 4 cull mode is invalid"
      ~safe_value:"set_cull_mode"
  ; enum_setter
      ~sdk_id:"method:-[MTL4RenderCommandEncoder setDepthClipMode:]"
      ~name:"setDepthClipMode:"
      ~signature:"instance (MTLDepthClipMode) -> void"
      ~ocaml_name:"command4_render_encoder_set_depth_clip_mode"
      ~c_symbol:"caml_prismel_metal_command4_render_encoder_set_depth_clip_mode"
      ~argument_name:"mode" ~enum_type:Depth_clip_mode
      ~cases:
        [ { sdk_id = "enum-case:MTLDepthClipMode:MTLDepthClipModeClip"
          ; value = 0
          }
        ; { sdk_id = "enum-case:MTLDepthClipMode:MTLDepthClipModeClamp"
          ; value = 1
          }
        ]
      ~error:"Metal 4 depth-clip mode is invalid"
      ~safe_value:"set_depth_clip_mode"
  ; enum_setter
      ~sdk_id:"method:-[MTL4RenderCommandEncoder setFrontFacingWinding:]"
      ~name:"setFrontFacingWinding:"
      ~signature:"instance (MTLWinding) -> void"
      ~ocaml_name:"command4_render_encoder_set_front_facing_winding"
      ~c_symbol:
        "caml_prismel_metal_command4_render_encoder_set_front_facing_winding"
      ~argument_name:"winding" ~enum_type:Winding
      ~cases:
        [ { sdk_id = "enum-case:MTLWinding:MTLWindingClockwise"; value = 0 }
        ; { sdk_id = "enum-case:MTLWinding:MTLWindingCounterClockwise"
          ; value = 1
          }
        ]
      ~error:"Metal 4 front-facing winding is invalid"
      ~safe_value:"set_front_facing_winding"
  ; enum_setter
      ~sdk_id:"method:-[MTL4RenderCommandEncoder setTriangleFillMode:]"
      ~name:"setTriangleFillMode:"
      ~signature:"instance (MTLTriangleFillMode) -> void"
      ~ocaml_name:"command4_render_encoder_set_triangle_fill_mode"
      ~c_symbol:
        "caml_prismel_metal_command4_render_encoder_set_triangle_fill_mode"
      ~argument_name:"mode" ~enum_type:Triangle_fill_mode
      ~cases:
        [ { sdk_id = "enum-case:MTLTriangleFillMode:MTLTriangleFillModeFill"
          ; value = 0
          }
        ; { sdk_id = "enum-case:MTLTriangleFillMode:MTLTriangleFillModeLines"
          ; value = 1
          }
        ]
      ~error:"Metal 4 triangle-fill mode is invalid"
      ~safe_value:"set_triangle_fill_mode"
  ; direct_void
      ~sdk_id:
        "method:-[MTL4ComputeCommandEncoder setThreadgroupMemoryLength:atIndex:]"
      ~owner:"MTL4ComputeCommandEncoder"
      ~header:"Metal/MTL4ComputeCommandEncoder.h"
      ~name:"setThreadgroupMemoryLength:atIndex:"
      ~signature:"instance (NSUInteger, NSUInteger) -> void"
      ~ocaml_name:"command4_compute_encoder_set_threadgroup_memory_length"
      ~c_symbol:
        "caml_prismel_metal_command4_compute_encoder_set_threadgroup_memory_length"
      ~receiver:Compute_encoder4
      ~arguments:
        [ unsigned_argument ~multiple_of:16 "length"
            "Metal 4 compute threadgroup-memory length must be nonnegative and a multiple of 16"
        ; unsigned_argument "index"
            "Metal 4 compute threadgroup-memory index must be nonnegative"
        ]
      ~safe_api:
        (Some
           (safe_api ~module_path:[ "Command4"; "Compute_encoder" ]
              ~value_name:"set_threadgroup_memory_length"
              ~test_value:"test_metal4_compute_commands"))
  ; direct_void
      ~sdk_id:
        "method:-[MTL4ComputeCommandEncoder setImageblockWidth:height:]"
      ~owner:"MTL4ComputeCommandEncoder"
      ~header:"Metal/MTL4ComputeCommandEncoder.h"
      ~name:"setImageblockWidth:height:"
      ~signature:"instance (NSUInteger, NSUInteger) -> void"
      ~ocaml_name:"command4_compute_encoder_set_imageblock_size"
      ~c_symbol:
        "caml_prismel_metal_command4_compute_encoder_set_imageblock_size"
      ~receiver:Compute_encoder4
      ~arguments:
        [ unsigned_argument "width"
            "Metal 4 compute imageblock width must be nonnegative"
        ; unsigned_argument "height"
            "Metal 4 compute imageblock height must be nonnegative"
        ]
      ~safe_api:None
  ; direct_void
      ~sdk_id:
        "method:-[MTL4RenderCommandEncoder setObjectThreadgroupMemoryLength:atIndex:]"
      ~owner:"MTL4RenderCommandEncoder"
      ~header:"Metal/MTL4RenderCommandEncoder.h"
      ~name:"setObjectThreadgroupMemoryLength:atIndex:"
      ~signature:"instance (NSUInteger, NSUInteger) -> void"
      ~ocaml_name:
        "command4_render_encoder_set_object_threadgroup_memory_length"
      ~c_symbol:
        "caml_prismel_metal_command4_render_encoder_set_object_threadgroup_memory_length"
      ~receiver:Render_encoder4
      ~arguments:
        [ unsigned_argument "length"
            "Metal 4 object threadgroup-memory length must be nonnegative"
        ; unsigned_argument "index"
            "Metal 4 object threadgroup-memory index must be nonnegative"
        ]
      ~safe_api:None
  ; direct_void
      ~sdk_id:
        "method:-[MTL4RenderCommandEncoder setThreadgroupMemoryLength:offset:atIndex:]"
      ~owner:"MTL4RenderCommandEncoder"
      ~header:"Metal/MTL4RenderCommandEncoder.h"
      ~name:"setThreadgroupMemoryLength:offset:atIndex:"
      ~signature:"instance (NSUInteger, NSUInteger, NSUInteger) -> void"
      ~ocaml_name:"command4_render_encoder_set_threadgroup_memory_length"
      ~c_symbol:
        "caml_prismel_metal_command4_render_encoder_set_threadgroup_memory_length"
      ~receiver:Render_encoder4
      ~arguments:
        [ unsigned_argument "length"
            "Metal 4 render threadgroup-memory length must be nonnegative"
        ; unsigned_argument "offset"
            "Metal 4 render threadgroup-memory offset must be nonnegative"
        ; unsigned_argument "index"
            "Metal 4 render threadgroup-memory index must be nonnegative"
        ]
      ~safe_api:None
  ; { sdk_id = "method:-[MTLDevice maxThreadgroupMemoryLength]"
    ; expect =
        { kind = "method"
        ; owner = "MTLDevice"
        ; name = "maxThreadgroupMemoryLength"
        ; header = "Metal/MTLDevice.h"
        ; signature = "instance () -> NSUInteger"
        ; attributes = [ "AvailabilityAttr" ]
        ; availability = macos_10_13_availability
        }
    ; companions =
        [ { sdk_id = "property:MTLDevice:maxThreadgroupMemoryLength"
          ; kind = "property"
          ; owner = "MTLDevice"
          ; name = "maxThreadgroupMemoryLength"
          ; header = "Metal/MTLDevice.h"
          ; signature = "NSUInteger"
          ; attributes = [ "AvailabilityAttr" ]
          }
        ]
    ; disposition =
        Generate
          (Direct_getter
             { ocaml_name = "device_max_threadgroup_memory_length"
             ; c_symbol =
                 "caml_prismel_metal_device_max_threadgroup_memory_length"
             ; receiver = Device
             ; result =
                 Nsuint_to_checked_int64
                   { overflow_error =
                       "Metal returned a threadgroup-memory limit outside signed 64-bit range"
                   }
             })
    ; safe_api =
        Some
          (safe_api ~module_path:[ "Device" ] ~value_name:"info"
             ~test_value:"test_device_info")
    }
  ; { sdk_id =
        "method:-[MTLComputePipelineState staticThreadgroupMemoryLength]"
    ; expect =
        { kind = "method"
        ; owner = "MTLComputePipelineState"
        ; name = "staticThreadgroupMemoryLength"
        ; header = "Metal/MTLComputePipeline.h"
        ; signature = "instance () -> NSUInteger"
        ; attributes = [ "AvailabilityAttr" ]
        ; availability = compute_pipeline_macos_10_13_availability
        }
    ; companions =
        [ { sdk_id =
              "property:MTLComputePipelineState:staticThreadgroupMemoryLength"
          ; kind = "property"
          ; owner = "MTLComputePipelineState"
          ; name = "staticThreadgroupMemoryLength"
          ; header = "Metal/MTLComputePipeline.h"
          ; signature = "NSUInteger"
          ; attributes = [ "AvailabilityAttr" ]
          }
        ]
    ; disposition =
        Generate
          (Direct_getter
             { ocaml_name =
                 "compute_pipeline_static_threadgroup_memory_length"
             ; c_symbol =
                 "caml_prismel_metal_compute_pipeline_static_threadgroup_memory_length"
             ; receiver = Compute_pipeline
             ; result =
                 Nsuint_to_checked_int64
                   { overflow_error =
                       "Metal returned a static threadgroup-memory length outside signed 64-bit range"
                   }
             })
    ; safe_api =
        Some
          (safe_api ~module_path:[ "Compute_pipeline" ]
             ~value_name:"static_threadgroup_memory_length"
             ~test_value:"test_metal4_compute_commands")
    }
  ]

let generated_entries =
  List.filter
    (fun entry ->
      match entry.disposition with Generate _ -> true | _ -> false)
    entries

let bound_identifiers =
  generated_entries
  |> List.filter (fun entry -> Option.is_some entry.safe_api)
  |> List.concat_map (fun entry ->
    entry.sdk_id
    :: List.map (fun (companion : companion) -> companion.sdk_id)
         entry.companions)
