open Support

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

let validate_relative_path path =
  if
    path = "" || not (Filename.is_relative path)
    || String.contains path '\000'
    || List.exists
         (fun component -> component = "" || component = "." || component = "..")
         (String.split_on_char '/' path)
  then fail "invalid binding-plan provenance path: %S" path

let aggregate_source_sha256 sources =
  let sources =
    List.sort (fun (left, _) (right, _) -> String.compare left right) sources
  in
  let rec reject_duplicates = function
    | (left, _) :: ((right, _) :: _ as rest) ->
        if left = right then
          fail "duplicate binding-plan provenance path: %s" left;
        reject_duplicates rest
    | [] | [ _ ] -> ()
  in
  List.iter (fun (path, _) -> validate_relative_path path) sources;
  reject_duplicates sources;
  let framed = Buffer.create 4096 in
  Printf.bprintf framed "%d:" (List.length sources);
  List.iter
    (fun (path, contents) ->
      Printf.bprintf framed "%d:" (String.length path);
      Buffer.add_string framed path;
      Printf.bprintf framed "%d:" (String.length contents);
      Buffer.add_string framed contents)
    sources;
  sha256 (Buffer.contents framed)
