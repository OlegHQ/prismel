(** An instance chain followed by an inner node id. *)
type t = int list

module Map : Map.S with type key = t
