type t
val load : string -> (t,string) result
val load_exn : string -> t
val create : width:int -> height:int -> ?color:Color.t -> unit -> t
val destroy : t -> unit
val get_width : t -> int
val get_height : t -> int
val get_size : t -> int * int
module Private : sig
  type renderer
  type texture
  val current_renderer : renderer option ref
  val set_renderer : renderer -> unit
  val get_renderer : unit -> (renderer,string) result
  val get_texture : t -> texture
  val from_texture : texture -> int -> int -> t
  val load_memory : string -> (t,string) result
  val replace : t -> t -> unit
  val identity : t -> int
  val generation : t -> int
  val reload : t -> string -> (unit,string) result
  val pixels : t -> (bytes,string) result
  val of_resource : Prismel_next_resources.Image.t -> t
  val resource : t -> Prismel_next_resources.Image.t
end
