(** Pure editor state shared by the sketch host and presentation adapters. *)

module Store = Store

(** Typed parameter schemas (the same values as [Procedural.Parameter]). *)
module Param = Param

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
  val record : ?merge:merge -> ?label:string -> 'a -> 'a t -> 'a t
  (** [label] (default ["Edit"]) names the entry, e.g. ["Connect"]. *)

  val label : 'a t -> string
  (** The label of the edit that produced [present]: what [undo] reverts. *)

  val redo_label : 'a t -> string option
  val seal : 'a t -> 'a t
  val undo : 'a t -> 'a t option
  val redo : 'a t -> 'a t option
  val can_undo : 'a t -> bool
  val can_redo : 'a t -> bool
  val depth : 'a t -> int
end

module Keymap : sig
  type trigger = Leader of char | Chord of Prismel.Input.key * Prismel.Input.key list
end

(** Named editor commands: the one table behind key routing, which-key, and
    the command palette. Pure data; the host decides what [action] does. *)
module Command : sig
  type ('scope, 'action) t = {
    id : string;  (** stable, e.g. ["edit.undo"]; entries sharing an id are one command *)
    label : string;  (** shown in which-key and the palette *)
    trigger : Keymap.trigger option;  (** [None]: palette only *)
    scope : 'scope option;  (** [None]: global; else only while that pane has focus *)
    action : 'action;
  }

  val make : ?trigger:Keymap.trigger -> ?scope:'scope -> id:string -> label:string ->
    'action -> ('scope, 'action) t
end

module Router : sig
  type state = Idle | Pending

  (** In fly mode, keep pointer/window events and pass Space to the leader
      router after ending the mode. Escape ends fly without opening a shortcut. *)
  val fly : Prismel.Frame.t -> bool * Prismel.Frame.t

  val step : ('scope, 'action) Command.t list -> focus:'scope ->
    text_focus:bool -> frame:Prismel.Frame.t -> state ->
    state * 'action list * Prismel.Frame.t
  (** Commands without a trigger never match a key. *)
end
