type t = { texture : Tsdl.Sdl.texture; width : int; height : int; }
val current_renderer : Tsdl.Sdl.renderer option ref
val set_renderer : Tsdl.Sdl.renderer -> unit
val get_renderer : unit -> (Tsdl.Sdl.renderer, string) result
val init_image_library : unit -> (unit, string) result
val quit_image_library : unit -> unit
val load : string -> (t, string) result
val load_exn : string -> t
val create : width:int -> height:int -> ?color:Color.t -> unit -> t
val destroy : t -> unit
val get_width : t -> int
val get_height : t -> int
val get_size : t -> int * int
val get_texture : t -> Tsdl.Sdl.texture
val from_texture : Tsdl.Sdl.texture -> int -> int -> t
val save : 'a -> 'b -> ('c, string) result
val is_valid : 'a -> bool
