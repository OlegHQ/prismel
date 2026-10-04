(** PXUI: Rays's creative-coding UI kit.

    {!Ui} is the immediate-mode core: build the interface every frame inside
    [Ui.frame], read widget values straight back into the sketch model, and
    compose [Ui.scene] into the view. {!Theme} is the design kit's palette
    and typography; the camera modules are
    reusable panels. *)

type theme = Theme.t = {
  panel : Rays.Color.t;
  foreground : Rays.Color.t;
  control : Rays.Color.t;
  input : Rays.Color.t;
  track : Rays.Color.t;
  accent : Rays.Color.t;
}

val default_theme : theme

module Theme = Theme
module Ui = Ui
module Camera_control = Camera_controls.Camera_control
module Camera2_control = Camera_controls.Camera2_control
