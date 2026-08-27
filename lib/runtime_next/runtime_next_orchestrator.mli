type target = Native | Headless | Web
type t

type configuration = {
  target : target;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  wap_config : Wap.config option;
}

val target_of_string : string -> (target, string) result
val select_with : (string -> string option) -> (target, string) result
val selected : unit -> (target, string) result

val create : configuration -> (t, Ogpu.Error.t) result
val target : t -> target
val render : t -> Scene_execution.draw list -> (bool, Ogpu.Error.t) result
val resize : t -> logical_width:int -> logical_height:int ->
  drawable_width:int -> drawable_height:int -> (unit, Ogpu.Error.t) result
val capture : t -> bytes_per_row:int -> (bytes, Ogpu.Error.t) result
val destroy : t -> (unit, Ogpu.Error.t) result
