type implementation = Generated_typed | Handwritten_safe
type item = { id : string; implementation : implementation; evidence : string }
val items : item list
val generated_count : int
val handwritten_count : int
