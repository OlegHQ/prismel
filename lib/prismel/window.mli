type config = {
  width : int;
  height : int;
  title : string;
  resizable : bool;
  fullscreen : bool;
  x : int option;
  y : int option;
  vsync : bool;
  highdpi : bool;
  multisampling : int option;
}
type t = {
  window : Tsdl.Sdl.window;
  renderer : Tsdl.Sdl.renderer;
  renderer_context : Tsdl.Sdl.gl_context option;
  config : config;
  mutable current_width : int;
  mutable current_height : int;
}
val default_config : config
val current_window : t option ref
val get_window_flags : config -> Tsdl.Sdl.Window.flags list
val get_renderer_flags : config -> Tsdl.Sdl.Renderer.flags list
val create : ?config:config -> unit -> t
val get_current : unit -> t
val width : unit -> int
val height : unit -> int
(* Logical window dimensions, in the same coordinate space as scenes and
   pointer events. *)
val size : unit -> int * int
(* Native framebuffer dimensions. These are commonly twice [size] on a Retina
   display. *)
val drawable_size : unit -> int * int
(* Native pixels per logical point on each axis. *)
val pixel_scale : unit -> float * float
val title : unit -> string
val is_resizable : unit -> bool
val is_fullscreen : unit -> bool
val set_title : string -> unit
val set_size : int -> int -> unit
(* Resize the native logical viewport. *)
val set_position : int -> int -> unit
val center : unit -> unit
val set_fullscreen : bool -> unit
val show : unit -> unit
val hide : unit -> unit
val minimize : unit -> unit
val maximize : unit -> unit
val restore : unit -> unit
val update_dimensions : int -> int -> unit
val get_window : unit -> Tsdl.Sdl.window
val get_renderer : unit -> Tsdl.Sdl.renderer
(* Run with SDL's native OpenGL renderer context current. The caller must flush
   pending SDL render commands before issuing direct OpenGL work. *)
val with_gpu_context : (unit -> 'a) -> ('a, string) result
val destroy : unit -> unit
val exists : unit -> bool
