(** Ergonomic functional sketch lifecycle. *)

type clock =
  | Realtime
  | Fixed of float

type config = {
  width : int;
  height : int;
  title : string;
  fps : int option;
  domains : int option;
  clock : clock;
  resizable : bool;
  fullscreen : bool;
}
(** [default_config] enables native resizing. *)

val default_config : config

val run : ?config:config -> (Frame.t -> Scene.t) -> unit
(** Run a sketch with no user model. *)

val run_state :
  ?config:config ->
  ?max_frames:int ->
  init:(Frame.t -> 'model) ->
  update:('model -> Frame.t -> 'model) ->
  view:('model -> Frame.t -> Scene.t) ->
  ?after_present:('model -> Frame.t -> 'model) ->
  ?on_stop:('model -> unit) ->
  unit -> 'model
(** Run a sketch with immutable user state threaded through every frame.
    [max_frames] keeps one runtime alive for exactly that many frames unless
    [quit] is requested first; it defaults to [PRISMEL_MAX_FRAMES] when that
    environment variable is set, for finite smoke runs. [after_present] runs after
    the native frame is rendered, can capture that frame, and returns the model
    for the next frame and [on_stop]. *)

val export :
  ?config:config -> ?fps:int -> ?prefix:string -> directory:string ->
  frames:int -> (Frame.t -> Scene.t) -> unit
(** Renders a deterministic PNG sequence named [prefix-NNNNNN.png]. Captured
    frames use the renderer's native backing dimensions. *)

val export_state :
  ?config:config ->
  ?fps:int ->
  ?prefix:string ->
  directory:string ->
  frames:int ->
  init:(Frame.t -> 'model) ->
  update:('model -> Frame.t -> 'model) ->
  view:('model -> Frame.t -> Scene.t) ->
  ?on_stop:('model -> unit) ->
  unit -> 'model
(** Stateful deterministic PNG-sequence export. *)

val quit : unit -> unit

val set_relative_mouse : bool -> (unit, string) result
(** Capture and hide the pointer: [Frame.mouse_delta] then reports device
    motion even at the window edge (fly cameras). Released when the sketch
    stops; an error when no sketch is running. *)

val set_cursor : [`Default|`Horizontal_resize|`Vertical_resize] ->
  (unit, string) result
(** Set the active native pointer cursor; an error when no sketch is running. *)
