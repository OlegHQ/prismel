type lane = Constant_or_class | Scalar_selector | Handwritten_ownership
type item = { id : string; lane : lane; reason : string }
val items : item list
val count : lane -> int
