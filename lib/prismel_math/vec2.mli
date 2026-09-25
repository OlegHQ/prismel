type t = { x : float; y : float; }
val create : float -> float -> t
val zero : t
val unit_x : t
val unit_y : t
val add : t -> t -> t
val sub : t -> t -> t
val neg : t -> t
val scale : t -> float -> t
val dot : t -> t -> float
val length_sq : t -> float
val length : t -> float
val normalize : t -> t
val distance : t -> t -> float
val angle : t -> float
val rotate : t -> float -> t
val lerp : t -> t -> float -> t
val nearly_equal : t -> t -> eps:float -> bool
val to_pair : t -> int * int
val to_pair_float : t -> float * float
val of_pair : int * int -> t
val of_pair_float : float * float -> t
val to_string : t -> string
