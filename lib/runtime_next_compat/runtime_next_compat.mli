(** Native-only compatibility facade retained for the public Prismel API. *)
type target = Native
type t
type facts = Runtime_next_orchestrator.facts
type pacing = Runtime_next_orchestrator.pacing
val start : width:int -> height:int -> title:string -> resizable:bool -> (t,string) result
val stop : t -> unit
val target : t -> target
val selected_target : unit -> (target,string) result
val target_of_string : string -> (target,string) result
val is_headless : unit -> bool
val is_web : unit -> bool
val is_displayless : unit -> bool
val facts : t -> (facts,string) result
val pacing : t -> (pacing,string) result
val render : t -> Scene_execution.draw list -> (bool,string) result
val capture : t -> bytes_per_row:int -> (bytes,string) result
val resize : t -> logical_width:int -> logical_height:int -> drawable_width:int -> drawable_height:int -> (unit,string) result
val set_title : t -> string -> (unit,string) result
val set_position : t -> x:int -> y:int -> (unit,string) result
val center : t -> (unit,string) result
val set_bordered : t -> bool -> (unit,string) result
val set_resizable : t -> bool -> (unit,string) result
val set_always_on_top : t -> bool -> (unit,string) result
val set_fullscreen : t -> bool -> (unit,string) result
val show : t -> (unit,string) result
val hide : t -> (unit,string) result
val minimize : t -> (unit,string) result
val maximize : t -> (unit,string) result
val restore : t -> (unit,string) result
val omitted_raw_api : string list
type coverage = Mapped | Adapted of string | Raw_omission of string
val api_coverage : (string * coverage) list
val api_type_coverage : (string * coverage) list
