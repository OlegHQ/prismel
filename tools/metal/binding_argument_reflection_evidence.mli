type symbol =
  { id : string
  ; kind : string
  ; owner : string option
  ; name : string
  ; header : string
  ; signature : string
  ; macos_introduced : string option
  ; classification : string
  }

val validate_inventory : symbol list -> unit
val is_bound_identifier : string -> bool
