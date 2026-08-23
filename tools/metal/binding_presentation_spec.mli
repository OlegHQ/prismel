type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; signature : string; classification : string }

val owners : string list
val selected : declaration -> bool
val expected_count : int
val expected_digest : string
