type t = Prismel_next_resources.Image.t
val load : string -> (t,string) result
val load_exn : string -> t
val create : width:int -> height:int -> ?color:Color.t -> unit -> t
val destroy : t -> unit
val get_width : t -> int
val get_height : t -> int
val get_size : t -> int * int
val identity : t -> int
val generation : t -> int
val reload : t -> string -> (unit,string) result
val pixels : t -> (bytes,string) result
