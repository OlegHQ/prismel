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

module Identity_cache : sig
  type ('k, 'v) t
  (** A domain-safe cache keyed by physical identity with a fixed capacity.
      Entries are ephemerons, so a value is retained only while its key is
      alive; at most [capacity] entries are held, replaced first-in
      first-out. Lookup is O(capacity) integer comparisons and never cleans
      or rehashes the table. *)

  val create : id:('k -> int) -> int -> ('k, 'v) t
  (** [create ~id capacity]; [id] is a cheap stable identifier for a key,
      compared before physical identity. *)

  val find_or_add : ('k, 'v) t -> 'k -> (unit -> 'v) -> 'v
  (** Return the cached value for a key, or build, insert, and return it. The
      builder runs outside the lock; a racing insert of the same key wins. *)
end

val select : ?cancel:Cancel.t -> float array -> int array -> int -> int -> int -> unit
(** [select keys order first last k] reorders [order.(first..last)] so that
    [order.(k)] is the element that ordering by [keys.(i)] (ties by [i]) would
    put there, with smaller elements before it and larger after. Expected
    O(last - first) time, in place. *)
