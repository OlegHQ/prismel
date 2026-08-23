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

val validate_inventory : inventory_symbol list -> unit
val promotion_ids : string list
val expected_promotion_count : int
