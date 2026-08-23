type declaration =
  { id : string
  ; kind : string
  ; owner : string option
  ; signature : string
  ; classification : string
  }

type selection =
  { declarations : declaration list
  ; method_count : int
  ; property_count : int
  ; owner_count : int
  }

val expected_method_count : int
val expected_property_count : int
val expected_declaration_count : int
val expected_owner_count : int
val select : declaration list -> selection
