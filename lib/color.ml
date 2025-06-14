(* Color Module - RGBA Color System *)

(* Color type with 8-bit per channel (0-255) *)
type t = { r: int; g: int; b: int; a: int }

(* Helper function to clamp values to 0-255 range *)
let clamp_byte x = max 0 (min 255 x)

(* Constructors *)
let rgb r g b = { 
  r = clamp_byte r; 
  g = clamp_byte g; 
  b = clamp_byte b; 
  a = 255 
}

let rgba r g b a = { 
  r = clamp_byte r; 
  g = clamp_byte g; 
  b = clamp_byte b; 
  a = clamp_byte a 
}

let gray x = 
  let clamped = clamp_byte x in
  { r = clamped; g = clamped; b = clamped; a = 255 }

let from_hex hex =
  let r = (hex land 0xFF0000) lsr 16 in
  let g = (hex land 0x00FF00) lsr 8 in
  let b = hex land 0x0000FF in
  { r; g; b; a = 255 }

(* Predefined Colors *)
let black = { r = 0; g = 0; b = 0; a = 255 }
let white = { r = 255; g = 255; b = 255; a = 255 }
let red = { r = 255; g = 0; b = 0; a = 255 }
let green = { r = 0; g = 255; b = 0; a = 255 }
let blue = { r = 0; g = 0; b = 255; a = 255 }
let yellow = { r = 255; g = 255; b = 0; a = 255 }
let cyan = { r = 0; g = 255; b = 255; a = 255 }
let magenta = { r = 255; g = 0; b = 255; a = 255 }

(* Additional useful colors *)
let transparent = { r = 0; g = 0; b = 0; a = 0 }
let dark_gray = { r = 64; g = 64; b = 64; a = 255 }
let light_gray = { r = 192; g = 192; b = 192; a = 255 }

(* Color Operations *)
let with_alpha c a = { c with a = clamp_byte a }

let to_tuple c = (c.r, c.g, c.b, c.a)

let blend c1 c2 ~pct =
  let pct = max 0.0 (min 1.0 pct) in (* clamp pct to [0,1] *)
  let inv_pct = 1.0 -. pct in
  {
    r = int_of_float (float_of_int c1.r *. inv_pct +. float_of_int c2.r *. pct +. 0.5);
    g = int_of_float (float_of_int c1.g *. inv_pct +. float_of_int c2.g *. pct +. 0.5);
    b = int_of_float (float_of_int c1.b *. inv_pct +. float_of_int c2.b *. pct +. 0.5);
    a = int_of_float (float_of_int c1.a *. inv_pct +. float_of_int c2.a *. pct +. 0.5);
  }

let lighten c f =
  let f = max 0.0 (min 1.0 f) in (* clamp f to [0,1] *)
  blend c white ~pct:f

let darken c f =
  let f = max 0.0 (min 1.0 f) in (* clamp f to [0,1] *)
  blend c black ~pct:f

let invert c = {
  r = 255 - c.r;
  g = 255 - c.g;
  b = 255 - c.b;
  a = c.a; (* keep alpha unchanged *)
}

(* Utility functions *)
let equal c1 c2 =
  c1.r = c2.r && c1.g = c2.g && c1.b = c2.b && c1.a = c2.a

let to_string c =
  Printf.sprintf "Color(r=%d, g=%d, b=%d, a=%d)" c.r c.g c.b c.a

let to_hex c =
  (c.r lsl 16) lor (c.g lsl 8) lor c.b

(* Additional constructors for convenience *)
let of_floats r g b a =
  rgba 
    (int_of_float (r *. 255.0 +. 0.5))
    (int_of_float (g *. 255.0 +. 0.5))
    (int_of_float (b *. 255.0 +. 0.5))
    (int_of_float (a *. 255.0 +. 0.5))

let to_floats c =
  (float_of_int c.r /. 255.0,
   float_of_int c.g /. 255.0,
   float_of_int c.b /. 255.0,
   float_of_int c.a /. 255.0)
