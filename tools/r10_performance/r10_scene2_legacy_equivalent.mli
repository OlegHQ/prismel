type scenario = Basic | Pxui | Canvas
type descriptor = { scenario : scenario; semantic_signature : string;
  work_units : int; required_features : string list;
  canonical_parameters : string }
val describe : scenario -> width:int -> height:int -> descriptor
val phase : frame:int -> int
