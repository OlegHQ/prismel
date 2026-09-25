(** Pure editor state shared by the sketch host and presentation adapters. *)

module Store = Store

(** Bounded immutable undo history with explicit edit merge rules. *)
module History : sig
  type 'a t
  type merge =
    | Step
    | Gesture of int
    | Burst of { key : string; at : float; window : float }
    | Repair
  val create : ?capacity:int -> 'a -> 'a t
  val present : 'a t -> 'a
  (* [Step] adds an undo entry; matching [Gesture] ids merge until [seal];
      matching [Burst] keys merge while edits stay within [window] seconds;
      [Repair] changes the current entry without adding a step. *)
  val record : ?merge:merge -> 'a -> 'a t -> 'a t
  val seal : 'a t -> 'a t
  val undo : 'a t -> 'a t option
  val redo : 'a t -> 'a t option
  val can_undo : 'a t -> bool
  val can_redo : 'a t -> bool
  val depth : 'a t -> int
end

module Keymap : sig
  type trigger = Leader of char | Chord of Prismel.Input.key * Prismel.Input.key list

  type ('scope, 'action) binding = {
    trigger : trigger;
    label : string;
    scope : 'scope option;
    action : 'action;
  }

  val visible : ('scope, 'action) binding list -> 'scope ->
    ('scope, 'action) binding list
  val chord : ('scope, 'action) binding list -> 'scope ->
    Prismel.Input.key list -> Prismel.Input.key -> 'action option
end

module Router : sig
  type state = Idle | Pending

  (** In fly mode, keep pointer/window events and pass Space to the leader
      router after ending the mode. Escape ends fly without opening a shortcut. *)
  val fly : Prismel.Frame.t -> bool * Prismel.Frame.t

  val step : ('scope, 'action) Keymap.binding list -> focus:'scope ->
    text_focus:bool -> frame:Prismel.Frame.t -> state ->
    state * 'action list * Prismel.Frame.t
end
