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

type ports = {
  geometry : Prismel.Color.t; float : Prismel.Color.t; int : Prismel.Color.t;
  vec3 : Prismel.Color.t; bool : Prismel.Color.t; compound : Prismel.Color.t;
  output : Prismel.Color.t; hint : Prismel.Color.t;
}
let ports theme =
  let dark = theme.panel.Prismel.Color.r + theme.panel.g + theme.panel.b < 384 in
  let color light night = Prismel.Color.hex_exn (if dark then night else light) in
  let vec3 = color "#6b50ae" "#a98cf5" in
  { geometry = theme.accent; float = color "#b0680f" "#e5a54c";
    int = color "#3b7d4e" "#74c28e"; vec3;
    bool = color "#b0435f" "#f08aa3"; compound = vec3;
    output = theme.foreground; hint = Prismel.Color.hex_exn "#f5cf4f" }
