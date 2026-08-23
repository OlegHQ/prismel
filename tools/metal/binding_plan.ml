type receiver =
  | Render_encoder4

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

type generation =
  | Direct_void of direct_void

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
  ; disposition : disposition
  ; safe_api : safe_api option
  }

let expected_sdk_version = "26.5"

let metal4_availability =
  { macos_major = 26
  ; macos_minor = 0
  ; unavailable_error = "Metal 4 commands require macOS 26"
  }

let enum_setter ~sdk_id ~name ~signature ~ocaml_name ~c_symbol ~argument_name
    ~enum_type ~cases ~error ~safe_value =
  { sdk_id
  ; expect =
      { kind = "method"
      ; owner = "MTL4RenderCommandEncoder"
      ; name
      ; header = "Metal/MTL4RenderCommandEncoder.h"
      ; signature
      ; attributes = []
      ; availability = metal4_availability
      }
  ; disposition =
      Generate
        (Direct_void
           { ocaml_name
           ; c_symbol
           ; receiver = Render_encoder4
           ; arguments =
               [ { name = argument_name
                 ; kind =
                     Enum_int
                       { enum_type
                       ; cases
                       }
                 ; error
                 }
               ]
           })
  ; safe_api =
      Some
        { operation = "Metal.Command4.Render_encoder." ^ safe_value
        ; module_path = [ "Command4"; "Render_encoder" ]
        ; value_name = safe_value
        ; test_value = "test_metal4_raster_state_commands"
        ; test_call = [ "Command4"; "Render_encoder"; safe_value ]
        }
  }

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
  ]

let generated_entries =
  List.filter
    (fun entry ->
      match entry.disposition with Generate _ -> true | _ -> false)
    entries

let bound_identifiers =
  generated_entries
  |> List.filter (fun entry -> Option.is_some entry.safe_api)
  |> List.map (fun entry -> entry.sdk_id)
