type declaration = { id:string; header:string; kind:string; owner:string option; name:string; signature:string }
type lane = Metadata | Mechanical | Handwritten_ownership
type entry = { declaration:declaration; lane:lane }
val expected_count : int
val expected_digest : string
val select : declaration list -> entry list
val validate : entry list -> unit
val count : lane -> entry list -> int
