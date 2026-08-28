(** Ergonomic functional native Metal sketch lifecycle. *)

type clock =
  | Realtime
  | Fixed of float

type render_target = Native

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
(** The default configuration enables native resizing. *)

val default_config : config

val run :
  ?config:config ->
  (Frame.t -> Scene.t) ->
  unit
(** Runs a sketch with no user model. *)

val run_state :
  ?config:config ->
  ?max_frames:int ->
  init:(Frame.t -> 'model) ->
  update:('model -> Frame.t -> 'model) ->
  view:('model -> Frame.t -> Scene.t) ->
  ?on_stop:('model -> unit) ->
  unit ->
  'model
(** Runs a sketch with immutable user state threaded through every frame.
    [max_frames] keeps one runtime alive for exactly that many frames unless
    [quit] is requested first. *)

val run_assets :
  ?config:config ->
  ?root:string ->
  ?watch:bool ->
  init:(Assets.t -> Frame.t -> 'model) ->
  update:(Assets.t -> 'model -> Frame.t -> 'model) ->
  view:(Assets.t -> 'model -> Frame.t -> Scene.t) ->
  unit ->
  'model
(** Runs a stateful sketch with an automatically owned asset cache. *)

val export :
  ?config:config ->
  ?fps:int ->
  ?prefix:string ->
  directory:string ->
  frames:int ->
  (Frame.t -> Scene.t) ->
  unit
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
  unit ->
  'model
(** Renders a stateful deterministic PNG sequence. *)

val quit : unit -> unit
val resize : width:int -> height:int -> unit
(** Resizes the active native sketch. *)
val render_target : unit -> render_target
