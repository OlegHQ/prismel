val pi : float
val two_pi : float
val half_pi : float
val e : float
val deg_to_rad : float -> float
val rad_to_deg : float -> float
val clamp_float : 'a -> min:'a -> max:'a -> 'a
val clamp_int : 'a -> min:'a -> max:'a -> 'a
val clamp : 'a -> min:'a -> max:'a -> 'a
val to_int : float -> int
val lerp : float -> float -> float -> float
val inv_lerp : float -> float -> float -> float
val map :
  float ->
  in_min:float -> in_max:float -> out_min:float -> out_max:float -> float
val map_clamped :
  float ->
  in_min:float -> in_max:float -> out_min:float -> out_max:float -> float
val random_float : float -> float
val random_range : float -> float -> float
val random_int : int -> int
val random_bool : unit -> bool
val choose : 'a list -> 'a
val sin : float -> float
val cos : float -> float
val sin_deg : float -> float
val cos_deg : float -> float
val hypot : float -> float -> float
val sign : float -> float
val smoothstep : float -> float
val normalize_angle : float -> float
val angle_of_vec : float * float -> float
val distance : float * float -> float * float -> float
val point_in_rect : float * float -> float * float * float * float -> bool
val rect_overlap :
  float * float * float * float -> float * float * float * float -> bool
val point_in_circle : float * float -> float * float * float -> bool
