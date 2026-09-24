type t
val create : width:int -> height:int -> (t,string) result
val create_exn : width:int -> height:int -> t
val width : t -> int
val height : t -> int
val size : t -> int * int
(* Replace the canvas contents through a reusable, layerless native Metal
   target owned by the canvas. *)
val render : t -> Scene.t -> unit
val capture : unit -> (t,string) result
val pixel : t -> x:int -> y:int -> Color.t option
val pixels : t -> Color.t array
val set_pixel : t -> x:int -> y:int -> Color.t -> unit
val map_pixels : t -> (x:int -> y:int -> Color.t -> Color.t) -> unit
val apply_mask : source:t -> mask:t -> unit
val to_image : t -> (Image.t,string) result
module Private : sig
  (** Copy current pixels into an existing image without replacing its identity
      or allocating a same-sized snapshot. *)
  val copy_to_image : t -> Image.t -> (unit,string) result
  type native_stats = { frames:int64; logical_draws:int64;
    logical_passes:int64; logical_submissions:int64; uploaded_bytes:int64;
    cache_entries:int }
  val native_stats : t -> native_stats
end
val save_png : t -> string -> (unit,string) result
val save_screen_png : string -> (unit,string) result
val destroy : t -> unit
