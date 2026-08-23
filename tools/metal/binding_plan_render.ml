open Binding_spec

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
      ~sdk_id:
        "method:-[MTL4RenderCommandEncoder setFrontFacingWinding:]"
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
  ]
