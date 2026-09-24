type result =
  | Bool
  | Unsigned
  | Enum of string
  | String
  | Retained_object of { objc_type : string; nullable : bool }
  | Retained_array of string

type argument = String_argument

type entry =
  { sdk_id : string
  ; property_id : string option
  ; owner : string
  ; selector : string
  ; arguments : argument list
  ; result : result
  ; macos_introduced : string
  }

val entries : entry list
val inventory_ids : string list
val expected_method_count : int
val expected_property_count : int
val expected_declaration_count : int
val source_paths : string list
