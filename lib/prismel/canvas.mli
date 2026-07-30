(** CPU-backed offscreen canvases.

    Canvases render through SDL's software renderer, so they work identically
    in visible and headless sketches and provide direct pixel readback. *)

type t

val create : width:int -> height:int -> (t, string) result
val create_exn : width:int -> height:int -> t
val width : t -> int
val height : t -> int
val size : t -> int * int

val render : t -> Scene.t -> unit
(** Replace the canvas contents by rendering a scene. *)

val capture : unit -> (t, string) result
(** Copy the active window renderer into a new native-pixel canvas. On a
    Retina display its dimensions commonly equal twice [Frame.size]. *)

val pixel : t -> x:int -> y:int -> Color.t option
val pixels : t -> Color.t array
(* Return a row-major copy of all pixels. *)
val set_pixel : t -> x:int -> y:int -> Color.t -> unit
val map_pixels : t -> (x:int -> y:int -> Color.t -> Color.t) -> unit

val apply_mask : source:t -> mask:t -> unit
(** Multiply [source] alpha by [mask] alpha. Both canvases must have the same
    dimensions. RGB values in the mask are ignored. *)

val to_image : t -> (Image.t, string) result
(** Upload a snapshot as a texture for the active window renderer. The caller
    owns the returned image and should call [Image.destroy]. *)

val save_png : t -> string -> (unit, string) result
(* Save the active native-pixel framebuffer. *)
val save_screen_png : string -> (unit, string) result
val destroy : t -> unit
