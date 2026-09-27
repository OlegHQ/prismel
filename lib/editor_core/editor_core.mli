(** Pure editor state shared by the sketch host and presentation adapters. *)

module Store = Store
module Network_layout = Network_layout

(** Typed parameter schemas (the same values as [Procedural.Parameter]). *)
module Param = Param

(** Bounded immutable undo history with explicit edit merge rules. *)
module History : sig
  type 'a t
  type merge =
    | Step
    | Gesture of string
    | Burst of { key : string; at : float; window : float }
    | Repair
  val create : ?capacity:int -> 'a -> 'a t
  val present : 'a t -> 'a
  (* [Step] adds an undo entry; matching [Gesture] operation/target keys merge until [seal];
      matching [Burst] keys merge while edits stay within [window] seconds;
      [Repair] changes the current entry without adding a step. *)
  val record : ?merge:merge -> ?label:string -> 'a -> 'a t -> 'a t
  (** [label] (default ["Edit"]) names the entry, e.g. ["Connect"]. *)

  val label : 'a t -> string
  (** The label of the edit that produced [present]: what [undo] reverts. *)

  val redo_label : 'a t -> string option
  val seal : ?gesture_only:bool -> 'a t -> 'a t
  (** [gesture_only] preserves timed bursts when a pointer gesture ends. *)

  val undo : 'a t -> 'a t option
  val redo : 'a t -> 'a t option
  val can_undo : 'a t -> bool
  val can_redo : 'a t -> bool
  val depth : 'a t -> int
end

module Keymap : sig
  type trigger = Leader of string | Chord of Prismel.Input.key * Prismel.Input.key list
end

module Guide_context : sig
  type t = Canvas | Node | Value_node | Compound | Multi | Wire | Row | Hints
    | Leader | Search | List | Text | Inside_compound
end

(** Named editor commands: the one table behind key routing, which-key, and
    the command palette. Pure data; the host decides what [action] does. *)
module Command : sig
  type ('scope, 'action) t = {
    id : string;  (** stable, e.g. ["edit.undo"]; entries sharing an id are one command *)
    label : string;  (** shown in which-key and the palette *)
    trigger : Keymap.trigger option;  (** [None]: palette only *)
    scope : 'scope option;  (** [None]: global; else only while that pane has focus *)
    guide : Guide_context.t list;  (** contexts where the guide strip lists this command *)
    action : 'action;
  }

  val make : ?trigger:Keymap.trigger -> ?scope:'scope -> ?guide:Guide_context.t list ->
    id:string -> label:string ->
    'action -> ('scope, 'action) t
end

module Router : sig
  (** Tab without a host binding cancels leader routing and hands the remaining
      ordered events to UI traversal/activation, including a same-frame Space. *)
  type state = Idle | Pending of string  (** leader keys typed so far *)

  (** In fly mode, keep pointer/window events and pass Space to the leader
      router after ending the mode. Escape ends fly without opening a shortcut. *)
  val fly : Prismel.Frame.t -> bool * Prismel.Frame.t

  val step : ?previous_keys:Prismel.Input.key list ->
    ('scope, 'action) Command.t list -> focus:'scope ->
    text_focus:bool -> frame:Prismel.Frame.t -> state ->
    state * 'action list * Prismel.Frame.t
  (** Commands without a trigger never match a key. Modifiers follow event
      order. Supply the previous frame's keys for changed modifiers and focus
      cancellation; omitted previous state assumes no modifiers were held. *)
end
