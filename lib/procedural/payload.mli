type t = Geometry of Rdk.Geometry.t | Image of Image.t
val data_id : t -> int
val payload_components : t -> (int * int) list
val element_count : t -> int
val geometry : t -> (Rdk.Geometry.t, Diagnostic.error) result
val image : t -> (Image.t, Diagnostic.error) result
