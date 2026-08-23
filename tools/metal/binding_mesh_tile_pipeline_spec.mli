type declaration =
  { id : string
  ; kind : string
  ; owner : string option
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string option
  ; attributes : string list
  ; classification : string
  }

type property_kind =
  | Enum of string
  | Value_record of string
  | Copied_string
  | Borrowed_function of [ `Required | `Optional ]
  | Borrowed_binary_archives
  | Borrowed_dynamic_libraries
  | Linked_functions
  | Buffer_descriptors
  | Color_attachments

val owners : string list
val selected : declaration -> bool
val property_kind : declaration -> property_kind
val mechanically_generated : property_kind -> bool
val inventory_id_digest : declaration list -> string
