type t = {
  panel : Rays.Color.t;
  foreground : Rays.Color.t;
  control : Rays.Color.t;
  input : Rays.Color.t;
  track : Rays.Color.t;
  accent : Rays.Color.t;
}

let default = {
  panel = Rays.Color.hex_exn "#f4f5f0";
  foreground = Rays.Color.hex_exn "#222b2b";
  control = Rays.Color.hex_exn "#dce3de";
  input = Rays.Color.hex_exn "#ffffff";
  track = Rays.Color.hex_exn "#e3e8e4";
  accent = Rays.Color.hex_exn "#f0481f";
}

let font_size = 11

let muted theme = Rays.Color.blend theme.foreground theme.panel ~pct:0.48
let border theme = Rays.Color.with_alpha theme.foreground 76 (* controls *)
let edge theme = Rays.Color.with_alpha theme.foreground 38 (* panels, cards, windows *)
let faint_border theme = Rays.Color.with_alpha theme.foreground 20
let sheen theme = Rays.Color.with_alpha theme.input 216 (* inner top line of a sheet *)
let hover_fill theme = Rays.Color.blend theme.input theme.accent ~pct:0.11
let pressed_fill theme = Rays.Color.blend theme.control theme.accent ~pct:0.18
let invalid = Rays.Color.hex_exn "#c2255c"

type ports = {
  geometry : Rays.Color.t; float : Rays.Color.t; int : Rays.Color.t;
  vec3 : Rays.Color.t; bool : Rays.Color.t; compound : Rays.Color.t;
  output : Rays.Color.t; hint : Rays.Color.t;
  text : Rays.Color.t; fn : Rays.Color.t; record : Rays.Color.t;
}
let ports theme =
  let dark = theme.panel.Rays.Color.r + theme.panel.g + theme.panel.b < 384 in
  let color light night = Rays.Color.hex_exn (if dark then night else light) in
  let vec3 = color "#6b50ae" "#a98cf5" in
  { geometry = theme.accent; float = color "#285f77" "#72b3cf";
    int = color "#3b7d4e" "#74c28e"; vec3;
    bool = color "#b0435f" "#f08aa3"; compound = vec3;
    output = theme.foreground; hint = Rays.Color.hex_exn "#f5cf4f";
    text = muted theme; fn = color "#a3407a" "#e88ac0";
    record = color "#4f6a5f" "#9cc2b2" }

(* Graph zones (plan W4): a tinted rectangle with a border; [dashed] draws the
   border as dashes, and a hollow zone has no fill worth the name.  The
   colours are the study's [--z-*] tokens. *)
type zone = { fill : Rays.Color.t; edge : Rays.Color.t; dashed : bool }

let dark theme = theme.panel.Rays.Color.r + theme.panel.g + theme.panel.b < 384
let zone theme ~light ~dark:night ~dashed =
  let r, g, b, fill, edge = if dark theme then night else light in
  { fill = Rays.Color.rgba r g b fill; edge = Rays.Color.rgba r g b edge; dashed }
let zone_for theme = zone theme ~dashed:false
  ~light:(240, 72, 31, 14, 90) ~dark:(255, 107, 69, 16, 100)
let zone_fold theme = zone theme ~dashed:false
  ~light:(107, 80, 174, 19, 128) ~dark:(169, 140, 245, 20, 128)
let zone_sum theme = zone theme ~dashed:false
  ~light:(40, 95, 119, 20, 128) ~dark:(114, 179, 207, 20, 128)
let zone_fn theme = zone theme ~dashed:true
  ~light:(163, 64, 122, 9, 140) ~dark:(232, 138, 192, 10, 128)
let zone_let theme = zone theme ~dashed:true
  ~light:(34, 43, 43, 0, 87) ~dark:(225, 231, 227, 0, 77)
