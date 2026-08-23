type declaration =
  { id : string; kind : string; owner : string option; name : string
  ; header : string; signature : string; macos_introduced : string option
  ; classification : string }

type representation = Bool | Float | Unsigned | Enum of string
type property =
  { property : declaration; getter : declaration; setter : declaration option
  ; representation : representation }
type selection = { properties : property list; identifiers : string list; owners : string list }

val select : declaration list -> selection
val expected_property_count : int
val expected_getter_count : int
val expected_setter_count : int
val expected_identifier_count : int
val expected_owner_count : int
val source_paths : string list
