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

module Keymap : sig
  type ('scope, 'action) binding = {
    key : char;
    label : string;
    scope : 'scope option;
    action : 'action;
  }

  val visible : ('scope, 'action) binding list -> 'scope ->
    ('scope, 'action) binding list
end

module Router : sig
  type state = Idle | Pending

  val step : ('scope, 'action) Keymap.binding list -> focus:'scope ->
    text_focus:bool -> frame:Prismel.Frame.t -> state ->
    state * 'action list * Prismel.Frame.t
end
