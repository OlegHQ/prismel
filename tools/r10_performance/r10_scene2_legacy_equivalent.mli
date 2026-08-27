type scenario = Basic | Pxui | Canvas

type t = {
  draws : Scene_execution.draw list;
  workload_signature : string;
  work_units : int;
}

val create : scenario -> width:int -> height:int -> t
