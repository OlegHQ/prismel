type t = { r : int; g : int; b : int; a : int; }
val clamp_byte : int -> int
val rgb : int -> int -> int -> t
val rgba : int -> int -> int -> int -> t
val gray : int -> t
val from_hex : int -> t
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
val lighten : t -> float -> t
val darken : t -> float -> t
val invert : t -> t
val equal : t -> t -> bool
val to_string : t -> string
val to_hex : t -> int
val of_floats : float -> float -> float -> float -> t
val to_floats : t -> float * float * float * float
