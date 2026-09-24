type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; header : string; signature : string; macos_introduced : string option
  ; classification : string }

type selection =
  { declarations : declaration list
  ; identifiers : string list
  ; owners : string list
  ; method_count : int }

val expected_identifier_count : int
val expected_owner_count : int
val select : declaration list -> selection
val source_paths : string list
