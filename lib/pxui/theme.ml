type t = {
  panel : Prismel.Color.t;
  foreground : Prismel.Color.t;
  control : Prismel.Color.t;
  input : Prismel.Color.t;
  track : Prismel.Color.t;
  accent : Prismel.Color.t;
}

let default = {
  panel = Prismel.Color.hex_exn "#f4f5f0";
  foreground = Prismel.Color.hex_exn "#222b2b";
  control = Prismel.Color.hex_exn "#dce3de";
  input = Prismel.Color.hex_exn "#ffffff";
  track = Prismel.Color.hex_exn "#e3e8e4";
  accent = Prismel.Color.hex_exn "#285f77";
}

let font_size = 11

let muted theme = Prismel.Color.blend theme.foreground theme.panel ~pct:0.48
let border theme = Prismel.Color.with_alpha theme.foreground 180
let faint_border theme = Prismel.Color.with_alpha theme.foreground 60
let hover_fill theme = Prismel.Color.blend theme.input theme.accent ~pct:0.11
let pressed_fill theme = Prismel.Color.blend theme.control theme.accent ~pct:0.18
let invalid = Prismel.Color.hex_exn "#fb7185"
