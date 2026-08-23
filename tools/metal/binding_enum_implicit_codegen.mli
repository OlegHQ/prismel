type declaration =
  { id : string
  ; kind : string
  ; name : string
  ; owner : string option
  ; header : string
  ; line : int option
  ; signature : string
  ; classification : string
  ; constant_value : string option
  }

type selection

exception Error of string

val select : declaration list -> selection
val identifiers : selection -> string list
val family_count : selection -> int
val case_count : selection -> int
val declaration_count : selection -> int
val render_raw_ml : ?outer_module:string -> selection -> string
val render_raw_mli : ?outer_module:string -> selection -> string
val render_static_asserts : selection -> string
val manifest_json : selection -> Yojson.Safe.t
