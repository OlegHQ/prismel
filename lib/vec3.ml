(* 3D Vector Module *)

type t = { x: float; y: float; z: float }

(* Construction *)
let create x y z = { x; y; z }
let zero = { x = 0.0; y = 0.0; z = 0.0 }
let unit_x = { x = 1.0; y = 0.0; z = 0.0 }
let unit_y = { x = 0.0; y = 1.0; z = 0.0 }
let unit_z = { x = 0.0; y = 0.0; z = 1.0 }

(* Basic Operations *)
let add v1 v2 = { x = v1.x +. v2.x; y = v1.y +. v2.y; z = v1.z +. v2.z }
let sub v1 v2 = { x = v1.x -. v2.x; y = v1.y -. v2.y; z = v1.z -. v2.z }
let neg v = { x = -.v.x; y = -.v.y; z = -.v.z }
let scale v s = { x = v.x *. s; y = v.y *. s; z = v.z *. s }

(* Dot product *)
let dot v1 v2 = v1.x *. v2.x +. v1.y *. v2.y +. v1.z *. v2.z

(* Cross product *)
let cross v1 v2 = {
  x = v1.y *. v2.z -. v1.z *. v2.y;
  y = v1.z *. v2.x -. v1.x *. v2.z;
  z = v1.x *. v2.y -. v1.y *. v2.x;
}

(* Length operations *)
let length_sq v = v.x *. v.x +. v.y *. v.y +. v.z *. v.z
let length v = Float.sqrt (length_sq v)

(* Normalization *)
let normalize v =
  let len = length v in
  if len = 0.0 then zero
  else { x = v.x /. len; y = v.y /. len; z = v.z /. len }

(* Distance *)
let distance v1 v2 = length (sub v2 v1)

(* Linear interpolation *)
let lerp v1 v2 t = 
  { x = v1.x +. (v2.x -. v1.x) *. t;
    y = v1.y +. (v2.y -. v1.y) *. t;
    z = v1.z +. (v2.z -. v1.z) *. t }

(* Equality with tolerance *)
let nearly_equal v1 v2 ~eps =
  abs_float (v1.x -. v2.x) < eps && 
  abs_float (v1.y -. v2.y) < eps && 
  abs_float (v1.z -. v2.z) < eps

(* Conversion utilities *)
let to_vec2 v = Vec2.create v.x v.y
let of_vec2 v2 z = { x = v2.Vec2.x; y = v2.Vec2.y; z }
let to_triple v = (v.x, v.y, v.z)
let of_triple (x, y, z) = { x; y; z }

(* String representation for debugging *)
let to_string v = Printf.sprintf "Vec3(%g, %g, %g)" v.x v.y v.z