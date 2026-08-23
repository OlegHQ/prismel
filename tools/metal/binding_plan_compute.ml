open Binding_spec

let entries =
  [ direct_void
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
