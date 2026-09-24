(** PXUI: Prismel's creative-coding UI kit.

    {!Ui} is the immediate-mode core: build the interface every frame inside
    [Ui.frame], read widget values straight back into the sketch model, and
    compose [Ui.scene] into the view. {!Theme} is the design kit's palette
    and typography, {!Settings} persists model values, the camera modules are
    reusable panels, and {!Undo} is the shared bounded history. *)

type theme = Theme.t = {
  panel : Prismel.Color.t;
  foreground : Prismel.Color.t;
  control : Prismel.Color.t;
  input : Prismel.Color.t;
  track : Prismel.Color.t;
  accent : Prismel.Color.t;
}

val default_theme : theme

module Theme = Theme
module Ui = Ui
module Settings = Settings
module Camera_control = Camera_controls.Camera_control
module Camera2_control = Camera_controls.Camera2_control

(** Bounded immutable undo history shared by every higher-level editor:
    [commit] records the current value as undoable and installs the new one,
    [amend] replaces the current value without a history entry so a
    continuous pointer edit collapses into one step, and [undo]/[redo] walk
    the stack. Committing clears the redo branch. *)
module Undo : sig
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
