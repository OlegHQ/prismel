type implementation = Generated_typed_selector | Handwritten_lifecycle
type item = { id : string; implementation : implementation; evidence : string }
val items : item list
val generated_count : int
val handwritten_count : int
