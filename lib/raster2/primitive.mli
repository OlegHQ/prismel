(** Integer pixel-center rasterization. Rectangles are half-open; line endpoints
    are inclusive; triangles normalize winding and cover nonnegative edge tests. *)
val rect : Surface.t -> blend:Composite.blend -> x:int -> y:int -> width:int -> height:int -> int32 -> unit
val line : Surface.t -> blend:Composite.blend -> x0:int -> y0:int -> x1:int -> y1:int -> int32 -> unit
val triangle : Surface.t -> blend:Composite.blend -> (int*int) -> (int*int) -> (int*int) -> int32 -> unit
val circle : Surface.t -> blend:Composite.blend -> cx:int -> cy:int -> radius:int -> int32 -> unit
