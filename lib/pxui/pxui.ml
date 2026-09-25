type theme = Theme.t = {
  panel : Prismel.Color.t;
  foreground : Prismel.Color.t;
  control : Prismel.Color.t;
  input : Prismel.Color.t;
  track : Prismel.Color.t;
  accent : Prismel.Color.t;
}

let default_theme = Theme.default

module Theme = Theme
module Ui = Ui
module Settings = Settings
module Camera_control = Camera_controls.Camera_control
module Camera2_control = Camera_controls.Camera2_control

module Undo = Editor.History
