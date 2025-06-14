(* 3x3 Matrix Module for 2D Transformations *)

type t = {
  m11: float; m12: float; m13: float;
  m21: float; m22: float; m23: float;
  m31: float; m32: float; m33: float;
}

(* Construction *)
let create m11 m12 m13 m21 m22 m23 m31 m32 m33 =
  { m11; m12; m13; m21; m22; m23; m31; m32; m33 }

let identity = {
  m11 = 1.0; m12 = 0.0; m13 = 0.0;
  m21 = 0.0; m22 = 1.0; m23 = 0.0;
  m31 = 0.0; m32 = 0.0; m33 = 1.0;
}

(* Transform constructors *)
let translation tx ty = {
  m11 = 1.0; m12 = 0.0; m13 = tx;
  m21 = 0.0; m22 = 1.0; m23 = ty;
  m31 = 0.0; m32 = 0.0; m33 = 1.0;
}

let scale sx sy = {
  m11 = sx;  m12 = 0.0; m13 = 0.0;
  m21 = 0.0; m22 = sy;  m23 = 0.0;
  m31 = 0.0; m32 = 0.0; m33 = 1.0;
}

let rotation theta =
  let cos_theta = Float.cos theta in
  let sin_theta = Float.sin theta in
  {
    m11 = cos_theta; m12 = -.sin_theta; m13 = 0.0;
    m21 = sin_theta; m22 = cos_theta;   m23 = 0.0;
    m31 = 0.0;       m32 = 0.0;         m33 = 1.0;
  }

let shear sx sy = {
  m11 = 1.0; m12 = sx;  m13 = 0.0;
  m21 = sy;  m22 = 1.0; m23 = 0.0;
  m31 = 0.0; m32 = 0.0; m33 = 1.0;
}

(* Matrix multiplication *)
let mul a b = {
  m11 = a.m11 *. b.m11 +. a.m12 *. b.m21 +. a.m13 *. b.m31;
  m12 = a.m11 *. b.m12 +. a.m12 *. b.m22 +. a.m13 *. b.m32;
  m13 = a.m11 *. b.m13 +. a.m12 *. b.m23 +. a.m13 *. b.m33;
  
  m21 = a.m21 *. b.m11 +. a.m22 *. b.m21 +. a.m23 *. b.m31;
  m22 = a.m21 *. b.m12 +. a.m22 *. b.m22 +. a.m23 *. b.m32;
  m23 = a.m21 *. b.m13 +. a.m22 *. b.m23 +. a.m23 *. b.m33;
  
  m31 = a.m31 *. b.m11 +. a.m32 *. b.m21 +. a.m33 *. b.m31;
  m32 = a.m31 *. b.m12 +. a.m32 *. b.m22 +. a.m33 *. b.m32;
  m33 = a.m31 *. b.m13 +. a.m32 *. b.m23 +. a.m33 *. b.m33;
}

(* Transform a 2D point *)
let transform_point m (x, y) =
  let x' = m.m11 *. x +. m.m12 *. y +. m.m13 in
  let y' = m.m21 *. x +. m.m22 *. y +. m.m23 in
  (x', y')

(* Transform a Vec2 *)
let transform_vec2 m v =
  let (x', y') = transform_point m (v.Vec2.x, v.Vec2.y) in
  Vec2.create x' y'

(* Transform a vector (no translation) *)
let transform_vector m (x, y) =
  let x' = m.m11 *. x +. m.m12 *. y in
  let y' = m.m21 *. x +. m.m22 *. y in
  (x', y')

(* Combined transformation constructor *)
let combine ~translate:(tx, ty) ~rotate:theta ~scale:(sx, sy) =
  let t_mat = translation tx ty in
  let r_mat = rotation theta in
  let s_mat = scale sx sy in
  (* Apply in order: scale, then rotate, then translate *)
  mul t_mat (mul r_mat s_mat)

(* Matrix determinant *)
let det m =
  m.m11 *. (m.m22 *. m.m33 -. m.m23 *. m.m32) -.
  m.m12 *. (m.m21 *. m.m33 -. m.m23 *. m.m31) +.
  m.m13 *. (m.m21 *. m.m32 -. m.m22 *. m.m31)

(* Matrix inverse *)
let inv m =
  let d = det m in
  if abs_float d < Float.epsilon then
    failwith "Mat3.inv: matrix is singular (determinant is zero)"
  else
    let inv_det = 1.0 /. d in
    {
      m11 = inv_det *. (m.m22 *. m.m33 -. m.m23 *. m.m32);
      m12 = inv_det *. (m.m13 *. m.m32 -. m.m12 *. m.m33);
      m13 = inv_det *. (m.m12 *. m.m23 -. m.m13 *. m.m22);
      
      m21 = inv_det *. (m.m23 *. m.m31 -. m.m21 *. m.m33);
      m22 = inv_det *. (m.m11 *. m.m33 -. m.m13 *. m.m31);
      m23 = inv_det *. (m.m13 *. m.m21 -. m.m11 *. m.m23);
      
      m31 = inv_det *. (m.m21 *. m.m32 -. m.m22 *. m.m31);
      m32 = inv_det *. (m.m12 *. m.m31 -. m.m11 *. m.m32);
      m33 = inv_det *. (m.m11 *. m.m22 -. m.m12 *. m.m21);
    }

(* Create matrix from 2x2 rotation/scale part *)
let of_mat2 a b c d = {
  m11 = a; m12 = b; m13 = 0.0;
  m21 = c; m22 = d; m23 = 0.0;
  m31 = 0.0; m32 = 0.0; m33 = 1.0;
}

(* Equality with tolerance *)
let equal m1 m2 =
  let eps = Float.epsilon *. 10.0 in
  abs_float (m1.m11 -. m2.m11) < eps &&
  abs_float (m1.m12 -. m2.m12) < eps &&
  abs_float (m1.m13 -. m2.m13) < eps &&
  abs_float (m1.m21 -. m2.m21) < eps &&
  abs_float (m1.m22 -. m2.m22) < eps &&
  abs_float (m1.m23 -. m2.m23) < eps &&
  abs_float (m1.m31 -. m2.m31) < eps &&
  abs_float (m1.m32 -. m2.m32) < eps &&
  abs_float (m1.m33 -. m2.m33) < eps

(* String representation for debugging *)
let to_string m =
  Printf.sprintf 
    "Mat3(\n  [%g, %g, %g]\n  [%g, %g, %g]\n  [%g, %g, %g]\n)"
    m.m11 m.m12 m.m13
    m.m21 m.m22 m.m23
    m.m31 m.m32 m.m33