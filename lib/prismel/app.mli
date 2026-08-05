type config = Window.config
type 'a framework_state = {
  window : Window.t;
  running : bool;
  user_state : 'a;
}
val framework_running : bool ref
val quit_requested : bool ref
val request_quit : unit -> unit
val is_running : unit -> bool
val init_sdl : ?config:Window.config -> unit -> unit
val cleanup_sdl : unit -> unit
val cleanup_graphics : unit -> unit
val process_frame :
  Window.t ->
  'a ->
  ('a -> float -> 'a) ->
  ('a -> unit) ->
  ('a -> unit) option ->
  ('a -> Event.t -> 'a) option ->
  'a framework_state
val main_loop :
  'a framework_state ->
  ('a -> float -> 'a) ->
  ('a -> unit) ->
  ('a -> unit) option ->
  ('a -> Event.t -> 'a) option ->
  'a
val run :
  ?config:Window.config ->
  init:(unit -> 'a) ->
  update:('a -> float -> 'a) ->
  draw:('a -> unit) ->
  ?after_draw:('a -> unit) ->
  ?on_event:('a -> Event.t -> 'a) ->
  ?on_stop:('a -> unit) ->
  unit -> 'a
val run_simple :
  ?width:int ->
  ?height:int ->
  ?title:string ->
  init:(unit -> 'a) ->
  update:('a -> float -> 'a) ->
  draw:('a -> unit) ->
  ?after_draw:('a -> unit) ->
  ?on_event:('a -> Event.t -> 'a) ->
  ?on_stop:('a -> unit) ->
  unit -> 'a
val get_window : unit -> Window.t
val get_renderer : unit -> Tsdl.Sdl.renderer
module Utils :
  sig
    val window_size : unit -> int * int
    val window_width : unit -> int
    val window_height : unit -> int
    val time : unit -> float
    val delta_time : unit -> float
    val frame_rate : unit -> float
    val set_frame_rate : int -> unit
    val set_vsync : bool -> unit
  end
