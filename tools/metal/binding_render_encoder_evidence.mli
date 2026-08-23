type symbol =
  { id : string
  ; kind : string
  ; owner : string option
  ; signature : string
  ; macos_introduced : string option
  ; attributes : string list
  ; classification : string
  }

val validate_inventory : symbol list -> string list
