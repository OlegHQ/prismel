open Prismel

type t = { a : Vec3.t; b : Vec3.t; c : Vec3.t; d : Vec3.t }

let make a b c d = { a; b; c; d }

let regular ~center ~radius =
  if not (Float.is_finite radius) || radius <= 0. then
    invalid_arg "Tetrahedron3.regular: radius must be finite and positive";
  match Polyhedra3.vertices Polyhedra3.Tetrahedron ~radius with
  | [a;b;c;d] -> make (Vec3.add center a) (Vec3.add center b)
      (Vec3.add center c) (Vec3.add center d)
  | _ -> assert false

let signed_volume tetrahedron =
  Vec3.dot (Vec3.sub tetrahedron.b tetrahedron.a)
    (Vec3.cross (Vec3.sub tetrahedron.c tetrahedron.a)
       (Vec3.sub tetrahedron.d tetrahedron.a)) /. 6.

let volume tetrahedron = abs_float (signed_volume tetrahedron)
let centroid tetrahedron =
  Vec3.scale
    (Vec3.add tetrahedron.a
       (Vec3.add tetrahedron.b (Vec3.add tetrahedron.c tetrahedron.d))) 0.25

let bounds tetrahedron =
  Bounds3.of_points
    [tetrahedron.a; tetrahedron.b; tetrahedron.c; tetrahedron.d]
  |> Option.get

let determinant a b c = Vec3.dot a (Vec3.cross b c)

let barycentric ?(epsilon = 1e-12) tetrahedron point =
  let v0 = Vec3.sub tetrahedron.a tetrahedron.d
  and v1 = Vec3.sub tetrahedron.b tetrahedron.d
  and v2 = Vec3.sub tetrahedron.c tetrahedron.d
  and p = Vec3.sub point tetrahedron.d in
  let denominator = determinant v0 v1 v2 in
  if abs_float denominator <= epsilon then None
  else
    let a = determinant p v1 v2 /. denominator
    and b = determinant v0 p v2 /. denominator
    and c = determinant v0 v1 p /. denominator in
    Some (a, b, c, 1. -. a -. b -. c)

let contains ?(epsilon = 1e-9) tetrahedron point =
  match barycentric ~epsilon tetrahedron point with
  | None -> false
  | Some (a,b,c,d) ->
      a >= -.epsilon && b >= -.epsilon && c >= -.epsilon && d >= -.epsilon

let orient_outward tetrahedron =
  if signed_volume tetrahedron < 0. then
    { tetrahedron with b = tetrahedron.c; c = tetrahedron.b }
  else tetrahedron

let faces tetrahedron =
  let tetrahedron = orient_outward tetrahedron in
  [
    Triangle3.make tetrahedron.a tetrahedron.c tetrahedron.b;
    Triangle3.make tetrahedron.a tetrahedron.b tetrahedron.d;
    Triangle3.make tetrahedron.a tetrahedron.d tetrahedron.c;
    Triangle3.make tetrahedron.b tetrahedron.c tetrahedron.d;
  ]

let transform matrix tetrahedron =
  make
    (Mat4.transform_point matrix tetrahedron.a)
    (Mat4.transform_point matrix tetrahedron.b)
    (Mat4.transform_point matrix tetrahedron.c)
    (Mat4.transform_point matrix tetrahedron.d)
