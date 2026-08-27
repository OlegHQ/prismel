type clock = Realtime | Fixed of float
type render_target = Native | Headless | Web
type config={width:int;height:int;title:string;fps:int option;domains:int option;clock:clock;resizable:bool;fullscreen:bool}
val default_config:config
val run : ?config:config -> (Frame.t -> Scene.t) -> unit
val run_state : ?config:config -> init:(Frame.t -> 'a) -> update:('a -> Frame.t -> 'a) -> view:('a -> Frame.t -> Scene.t) -> ?on_stop:('a -> unit) -> unit -> 'a
val run_assets : ?config:config -> ?root:string -> ?watch:bool -> init:(Assets.t -> Frame.t -> 'a) -> update:(Assets.t -> 'a -> Frame.t -> 'a) -> view:(Assets.t -> 'a -> Frame.t -> Scene.t) -> unit -> 'a
val export : ?config:config -> ?fps:int -> ?prefix:string -> directory:string -> frames:int -> (Frame.t -> Scene.t) -> unit
val export_state : ?config:config -> ?fps:int -> ?prefix:string -> directory:string -> frames:int -> init:(Frame.t -> 'a) -> update:('a -> Frame.t -> 'a) -> view:('a -> Frame.t -> Scene.t) -> ?on_stop:('a -> unit) -> unit -> 'a
val quit : unit -> unit
val is_headless : unit -> bool
val is_web : unit -> bool
val render_target : unit -> render_target
