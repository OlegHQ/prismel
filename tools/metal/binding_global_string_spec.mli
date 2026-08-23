type family =
  | Error_domain
  | Error_user_info_key
  | Common_counter
  | Common_counter_set
  | Device_notification

type entry =
  { sdk_id : string
  ; name : string
  ; header : string
  ; signature : string
  ; objc_typedef : string
  ; family : family
  ; macos_introduced : Binding_availability.version
  }

val entries : entry list
val expected_count : int
val ocaml_name : entry -> string
val c_symbol : entry -> string

