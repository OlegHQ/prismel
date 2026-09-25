(** PXUI: Prismel's creative-coding UI kit.

    {!Ui} is the immediate-mode core: build the interface every frame inside
    [Ui.frame], read widget values straight back into the sketch model, and
    compose [Ui.scene] into the view. {!Theme} is the design kit's palette
    and typography, {!Settings} persists model values, the camera modules are
    reusable panels. *)

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
