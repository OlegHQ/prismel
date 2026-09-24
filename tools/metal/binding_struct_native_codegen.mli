type output =
  { raw_ml : string
  ; raw_mli : string
  ; native : string
  ; method_ids : string list
  ; property_ids : string list
  }

val expected_method_count : int
val expected_property_count : int
val generate : unit -> output
