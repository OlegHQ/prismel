type t
val create : width:int -> height:int -> (t,string) result
val create_exn : width:int -> height:int -> t
val width : t -> int
val height : t -> int
val size : t -> int * int
val clear : t -> Color.t -> unit
val pixel : t -> x:int -> y:int -> Color.t option
val pixels : t -> Color.t array
val set_pixel : t -> x:int -> y:int -> Color.t -> unit
val map_pixels : t -> (x:int -> y:int -> Color.t -> Color.t) -> unit
val apply_mask : source:t -> mask:t -> unit
val to_image : t -> (Image.t,string) result
val save_png : t -> string -> (unit,string) result
val destroy : t -> unit
