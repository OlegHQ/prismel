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

val metal4_availability : availability
val macos_10_13_availability : availability
val compute_pipeline_macos_10_13_availability : availability

val safe_api :
  module_path:string list -> value_name:string -> test_value:string -> safe_api

val direct_void :
  sdk_id:string -> owner:string -> header:string -> name:string ->
  signature:string -> ocaml_name:string -> c_symbol:string ->
  receiver:receiver -> arguments:argument list -> safe_api:safe_api option ->
  entry

val enum_setter :
  sdk_id:string -> name:string -> signature:string -> ocaml_name:string ->
  c_symbol:string -> argument_name:string -> enum_type:enum_type ->
  cases:enum_case list -> error:string -> safe_value:string -> entry

val unsigned_argument :
  ?minimum:int -> ?multiple_of:int -> string -> string -> argument

(** Hashes a sorted, unambiguously framed sequence of relative source paths,
    byte lengths, and exact source bytes. *)
val aggregate_source_sha256 : (string * string) list -> string
