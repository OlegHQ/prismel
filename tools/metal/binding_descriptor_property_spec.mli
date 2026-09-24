type representation =
  | Bool
  | Nsuint
  | Enum of string
  | Flags of string
  | Resource_options
  | Sample_index

type default =
  | Default_bool of bool
  | Default_int64 of int64

type entry =
  { owner : string
  ; name : string
  ; getter_name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string
  ; attributes : string list
  ; representation : representation
  ; default : default
  }

val entry :
  ?attributes:string list ->
  ?default_int64:int64 ->
  ?getter:string ->
  owner:string ->
  name:string ->
  header:string ->
  signature:string ->
  introduced:string ->
  unit ->
  entry

val property_sdk_id : entry -> string
val getter_sdk_id : entry -> string
val setter_sdk_id : entry -> string
val inventory_ids : entry -> string list
val field_name : entry -> string
val ocaml_type : entry -> string
val default_expression : entry -> string
val validate : entry list -> unit
