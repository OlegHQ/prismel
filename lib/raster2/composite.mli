(** Deterministic straight-alpha RGBA compositing. *)
type blend = Source_over | Copy | Replace | Alpha | Add | Multiply | Screen | Subtract
type rect = { x:int; y:int; width:int; height:int }
type error = Invalid_extent of { width:int; height:int }
val color : blend:blend -> source:int32 -> destination:int32 -> int32
val pixel : Surface.t -> blend:blend -> x:int -> y:int -> int32 -> unit
val pixel_int : Surface.t -> blend:blend -> x:int -> y:int -> int -> unit
val rect : Surface.t -> blend:blend -> rect -> int32 -> (unit,error) result
val blit : src:Surface.t -> src_rect:rect -> dst:Surface.t -> dst_x:int -> dst_y:int -> blend:blend -> (unit,error) result
