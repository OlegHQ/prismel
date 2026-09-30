(** Saved, undoable canvas metadata, independent of graph presentation. *)
module Int_map : Map.S with type key = int
module String_map : Map.S with type key = string
module String_set : Set.S with type elt = string
module Port_map : Map.S with type key = int * string
module Port_set : Set.S with type elt = int * string

type level = Point | Chip | Card | Full
type t = {
  at : (float * float) Int_map.t;
  level : level Int_map.t;
  pinned : bool Int_map.t;
  rows : bool String_map.t Int_map.t;
  split : String_set.t Int_map.t;
  bends : (float * float) list Port_map.t;
  wireless : Port_set.t;
}

val empty : t
val snap : float -> float
val slot : int -> int -> int * string
val remove_nodes : int list -> t -> t
val edit : nodes:int list -> ports:(int * string) list -> source:t -> t -> t
(** Copy only the named nodes and destination ports from [source]. *)
