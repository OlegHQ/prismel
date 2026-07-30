(** Tiny persistent renderer for [dune utop] scene iteration. *)

val start :
  ?width:int -> ?height:int -> ?title:string -> unit -> unit
(** Open a preview window. Calling [start] again keeps the existing session. *)

val show : Scene.t -> unit
(** Poll events and display a scene, starting a default session if necessary. *)

val step : Scene.t -> Event.t list
(** Display a scene and return the ordered events polled immediately before it. *)

val is_open : unit -> bool
val stop : unit -> unit
(** Close the session and all Prismel backend subsystems. *)
