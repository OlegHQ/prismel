type inventory_symbol =
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

val expected_bound_count : int
val promotion_ids : string list
val validate_inventory : inventory_symbol list -> unit
