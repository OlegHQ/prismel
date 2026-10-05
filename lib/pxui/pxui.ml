type theme = Theme.t = {
  panel : Rays.Color.t;
  foreground : Rays.Color.t;
  control : Rays.Color.t;
  input : Rays.Color.t;
  track : Rays.Color.t;
  accent : Rays.Color.t;
  ink_ground : Rays.Color.t option;
}

let default_theme = Theme.default

module Theme = Theme
module Ui = Ui
module Camera_control = Camera_controls.Camera_control
module Camera2_control = Camera_controls.Camera2_control
