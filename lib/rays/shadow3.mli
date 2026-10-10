(** Deterministic depth-map shadows for [Scene3]. *)

type filter = Hard | Pcf_3x3 | Pcf_5x5
type t

module Private : sig
  type snapshot = {
    view_projection : Mat4.t;
    width : int;
    height : int;
    depths : float array;
    bias : float;
    normal_bias : float;
    filter : filter;
    strength : float;
  }
  val snapshot : t -> snapshot

  (** Process-local identity of this immutable shadow map. *)
  val identity : t -> int
end
