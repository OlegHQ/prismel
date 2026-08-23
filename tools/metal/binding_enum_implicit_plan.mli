type case =
  { sdk_name : string
  ; unsigned_decimal : string
  ; expected_line : int
  }

type family =
  { sdk_name : string
  ; header : string
  ; enum_line : int
  ; typedef_signature : string
  ; cases : case list
  }

val families : family list
val expected_family_count : int
val expected_case_count : int
val expected_declaration_count : int
val source_paths : string list

