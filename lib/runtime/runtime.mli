type target = Target.t = Native

type t

val start :
  width:int ->
  height:int ->
  title:string ->
  resizable:bool ->
  (t, string) result
(** Configure and initialize SDL_image/SDL_ttf for native presentation. *)

val stop : t -> unit
val target : t -> target
val selected_target : unit -> target
val target_of_string : string -> (target, string) result
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
