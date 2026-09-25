(** Pure editor state shared by the sketch host and presentation adapters. *)

(** Bounded immutable undo history. [amend] replaces the current value without
    adding an undo step; [commit] clears the redo branch. *)
module History : sig
  type 'a t
  val create : ?capacity:int -> 'a -> 'a t
  val present : 'a t -> 'a
  val commit : 'a -> 'a t -> 'a t
  val amend : 'a -> 'a t -> 'a t
  val undo : 'a t -> 'a t option
  val redo : 'a t -> 'a t option
  val can_undo : 'a t -> bool
  val can_redo : 'a t -> bool
  val depth : 'a t -> int
end
