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

val expected_sdk_version : string
val entries : entry list
val generated_entries : entry list
val bound_identifiers : string list
