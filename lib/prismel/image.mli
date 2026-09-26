type t
val load : string -> (t,string) result
val load_exn : string -> t
val create : width:int -> height:int -> ?color:Color.t -> unit -> t
(* Create or update an RGBA image. Updating preserves the image identity. *)
val upload_rgba : ?into:t -> width:int -> height:int -> rgba:bytes -> unit -> (t,string) result
val destroy : t -> unit
val get_width : t -> int
val get_height : t -> int
val get_size : t -> int * int
module Private : sig
  val replace : t -> t -> unit
  val identity : t -> int
  val pixels : t -> (bytes,string) result
  val of_resource : Runtime_resources.Image.t -> t
  val resource : t -> Runtime_resources.Image.t
end
