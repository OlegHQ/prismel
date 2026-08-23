type representation =
  | Bool
  | Nsuint
  | Enum of string

type entry =
  { owner : string
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string
  ; attributes : string list
  ; representation : representation
  }

val entry :
  ?attributes:string list ->
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
val validate : entry list -> unit
