(** Owned renderer image resources. Prefer loading through [Assets]. *)

type t

val load : string -> (t, string) result
val load_exn : string -> t
val create : width:int -> height:int -> ?color:Color.t -> unit -> t
val destroy : t -> unit
val get_width : t -> int
val get_height : t -> int
val get_size : t -> int * int

module Private : sig
  val current_renderer : Tsdl.Sdl.renderer option ref
  val set_renderer : Tsdl.Sdl.renderer -> unit
  val get_renderer : unit -> (Tsdl.Sdl.renderer, string) result
  val get_texture : t -> Tsdl.Sdl.texture
  val from_texture : Tsdl.Sdl.texture -> int -> int -> t
  val load_memory : string -> (t, string) result
  val replace : t -> t -> unit
end
(** Backend hooks used by Prismel's renderer and asset cache. *)
