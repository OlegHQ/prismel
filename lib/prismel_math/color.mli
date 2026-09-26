type t = { r : int; g : int; b : int; a : int; }
val clamp_byte : int -> int
val rgb : int -> int -> int -> t
val rgba : int -> int -> int -> int -> t
val gray : int -> t
val from_hex : int -> t
(* Parse #rgb, #rgba, #rrggbb, or #rrggbbaa. *)
val hex : string -> (t, string) result
val hex_exn : string -> t
(* Hue is in degrees; saturation/value are in 0..1. Hue wraps. *)
val hsv : ?alpha:float -> float -> float -> float -> t
(* Hue is in degrees; saturation/lightness are in 0..1. *)
val hsl : ?alpha:float -> float -> float -> float -> t
val black : t
val white : t
val red : t
val green : t
val blue : t
val yellow : t
val cyan : t
val magenta : t
val transparent : t
val dark_gray : t
val light_gray : t
val with_alpha : t -> int -> t
val to_tuple : t -> int * int * int * int
val blend : t -> t -> pct:float -> t
(* Sample evenly spaced color stops. Position is clamped to 0..1. *)
val gradient : t list -> float -> t
val lighten : t -> float -> t
val darken : t -> float -> t
val saturate : t -> float -> t
val desaturate : t -> float -> t
val rotate_hue : t -> float -> t
val invert : t -> t
val equal : t -> t -> bool
val to_string : t -> string
val to_hex : t -> int
val of_floats : float -> float -> float -> float -> t
val to_floats : t -> float * float * float * float
val to_hsv : t -> float * float * float * float
val to_hsl : t -> float * float * float * float
