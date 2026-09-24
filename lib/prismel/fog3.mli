(** Standard deterministic distance fog for [Scene3]. *)

type mode =
  | Linear of { start : float; end_ : float }
  | Exponential of { density : float }
  | Exponential_squared of { density : float }

type t = private {
  color : Color.t;
  mode : mode;
}

val linear : color:Color.t -> start:float -> end_:float -> t
val exponential : color:Color.t -> density:float -> t
val exponential_squared : color:Color.t -> density:float -> t

module Private : sig
  val visibility : t -> distance:float -> float
end
