type t = {
  m11 : float;
  m12 : float;
  m13 : float;
  m21 : float;
  m22 : float;
  m23 : float;
  m31 : float;
  m32 : float;
  m33 : float;
}
val create :
  float ->
  float -> float -> float -> float -> float -> float -> float -> float -> t
val identity : t
val translation : float -> float -> t
val scale : float -> float -> t
val rotation : float -> t
val shear : float -> float -> t
val mul : t -> t -> t
val transform_point : t -> float * float -> float * float
val transform_vec2 : t -> Vec2.t -> Vec2.t
val transform_vector : t -> float * float -> float * float
val combine :
  translate:float * float -> rotate:float -> scale:float * float -> t
val det : t -> float
val inv : t -> t
val of_mat2 : float -> float -> float -> float -> t
val equal : t -> t -> bool
val to_string : t -> string
