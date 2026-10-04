type t = { x : float; y : float; z : float; }
val create : float -> float -> float -> t
val zero : t
val unit_x : t
val unit_y : t
val unit_z : t
val add : t -> t -> t
val sub : t -> t -> t
val neg : t -> t
val scale : t -> float -> t
val dot : t -> t -> float
val cross : t -> t -> t
val length_sq : t -> float
val length : t -> float
val normalize : t -> t
val distance : t -> t -> float
val lerp : t -> t -> float -> t
val nearly_equal : t -> t -> eps:float -> bool
val to_vec2 : t -> Vec2.t
val of_vec2 : Vec2.t -> float -> t
val to_triple : t -> float * float * float
val of_triple : float * float * float -> t
val to_string : t -> string
