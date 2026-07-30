(* 2D Vector Module *)

type t = { x: float; y: float }

(* Construction *)
let create x y = { x; y }
let zero = { x = 0.0; y = 0.0 }
let unit_x = { x = 1.0; y = 0.0 }
let unit_y = { x = 0.0; y = 1.0 }

(* Basic Operations *)
let add v1 v2 = { x = v1.x +. v2.x; y = v1.y +. v2.y }
let sub v1 v2 = { x = v1.x -. v2.x; y = v1.y -. v2.y }
let neg v = { x = -.v.x; y = -.v.y }
let scale v s = { x = v.x *. s; y = v.y *. s }

(* Dot product *)
let dot v1 v2 = v1.x *. v2.x +. v1.y *. v2.y

(* Length operations *)
let length_sq v = v.x *. v.x +. v.y *. v.y
let length v = Float.sqrt (length_sq v)

(* Normalization *)
let normalize v =
  let len = length v in
  if len = 0.0 then zero
  else { x = v.x /. len; y = v.y /. len }

(* Distance *)
let distance v1 v2 = length (sub v2 v1)

(* Angle of vector relative to positive X axis *)
let angle v = Float.atan2 v.y v.x

(* Rotation *)
let rotate v theta =
  let cos_theta = Float.cos theta in
  let sin_theta = Float.sin theta in
  { x = v.x *. cos_theta -. v.y *. sin_theta;
    y = v.x *. sin_theta +. v.y *. cos_theta }

(* Linear interpolation *)
let lerp v1 v2 t = 
  { x = v1.x +. (v2.x -. v1.x) *. t;
    y = v1.y +. (v2.y -. v1.y) *. t }

(* Equality with tolerance *)
let nearly_equal v1 v2 ~eps =
  abs_float (v1.x -. v2.x) < eps && abs_float (v1.y -. v2.y) < eps

(* Conversion utilities *)
let to_pair v = (int_of_float v.x, int_of_float v.y)
let to_pair_float v = (v.x, v.y)
let of_pair (x, y) = { x = float_of_int x; y = float_of_int y }
let of_pair_float (x, y) = { x; y }

(* String representation for debugging *)
let to_string v = Printf.sprintf "Vec2(%g, %g)" v.x v.y
