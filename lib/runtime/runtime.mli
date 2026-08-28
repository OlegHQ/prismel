type target = Target.t = Native | Headless

type t

val start :
  width:int ->
  height:int ->
  title:string ->
  resizable:bool ->
  (t, string) result
(** Configure and initialize SDL_image/SDL_ttf plus the selected presentation
    target. The web target binds its HTTP/WebSocket server to [0.0.0.0].
    [PRISMEL_WEB_MAX_FPS] defaults to 60, [PRISMEL_WEB_MAX_MBIT] defaults to
    a 2 Mbit/s encoded-frame target, and [PRISMEL_WEB_MAX_PIXELS] defaults to
    921600 backing pixels; [PRISMAL_] aliases are accepted. Web viewports are
    authoritative regardless of native resize opt-in. *)

val stop : t -> unit
val target : t -> target
val selected_target : unit -> target
val target_of_string : string -> (target, string) result
val is_headless : unit -> bool
val is_displayless : unit -> bool

val present :
  t ->
  Tsdl.Sdl.renderer ->
  logical_width:int ->
  logical_height:int ->
  (unit, string) result
(** Present one frame through the selected local SDL target. *)

module Private : sig
  val select_target : (string -> string option) -> (target, string) result
end
