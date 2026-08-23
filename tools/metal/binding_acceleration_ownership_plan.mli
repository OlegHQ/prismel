type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; header : string; signature : string; macos_introduced : string option
  ; classification : string }
type ownership = Borrowed_buffer | Copied_string | Copied_retained_array | Buffer_range | Resource_id
type property = { property : declaration; getter : declaration; setter : declaration option; ownership : ownership }
type selection = { properties : property list; identifiers : string list; owners : string list }
val select : declaration list -> selection
val expected_property_count : int
val expected_identifier_count : int
val expected_owner_count : int
val source_paths : string list
