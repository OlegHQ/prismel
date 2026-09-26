(** Small shared kernel helpers: packed bitsets, open-addressing key maps,
    and index quickselect. *)

module Bits : sig
  val byte_count : int -> int
  (** Bytes needed for a bitset of the given length. *)

  val mem : Bytes.t -> int -> bool
  (** Unchecked bit read; the index must be in range. *)

  val set : Bytes.t -> int -> unit
  (** Unchecked bit set; the index must be in range. *)
end

module Key_map : sig
  type keep = First | Last
  (** Which index a repeated key resolves to. *)

  val ints : ?cancel:Cancel.t -> keep -> int array -> (int -> int) option
  (** [ints keep keys] returns a lookup from a key to the first or last index
      holding it in [keys], or [-1]. [None] when the table would exceed array
      limits. O(n) expected build time and O(n) memory. *)

  val strings : ?cancel:Cancel.t -> keep -> string array -> (string -> int) option
  (** String-keyed {!ints}. *)
end

val select : ?cancel:Cancel.t -> float array -> int array -> int -> int -> int -> unit
(** [select keys order first last k] reorders [order.(first..last)] so that
    [order.(k)] is the element that ordering by [keys.(i)] (ties by [i]) would
    put there, with smaller elements before it and larger after. Expected
    O(last - first) time, in place. *)
