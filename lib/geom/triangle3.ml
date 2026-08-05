open Prismel

type t = { a : Vec3.t; b : Vec3.t; c : Vec3.t }
type vertex = A | B | C

let make a b c = { a; b; c }
let equilateral_on ~normal a b =
  let edge = Vec3.sub b a in
  let perpendicular = Vec3.cross edge normal in
  if Vec3.length_sq edge <= 1e-18 || Vec3.length_sq perpendicular <= 1e-18 then
    Error "Triangle3.equilateral_on: edge and normal must define a plane"
  else
    let midpoint = Vec3.scale (Vec3.add a b) 0.5 in
    let height = Vec3.length edge *. sqrt 3. /. 2. in
    Ok (make a b
      (Vec3.add midpoint (Vec3.scale (Vec3.normalize perpendicular) height)))
let cross triangle = Vec3.cross (Vec3.sub triangle.b triangle.a) (Vec3.sub triangle.c triangle.a)
let area triangle = Vec3.length (cross triangle) /. 2.
let normal triangle = Vec3.normalize (cross triangle)
let centroid triangle = Vec3.scale (Vec3.add triangle.a (Vec3.add triangle.b triangle.c)) (1. /. 3.)
let bounds triangle = Bounds3.of_points [triangle.a; triangle.b; triangle.c] |> Option.get

let barycentric ?(epsilon = 1e-12) triangle point =
  let v0 = Vec3.sub triangle.b triangle.a
  and v1 = Vec3.sub triangle.c triangle.a
  and v2 = Vec3.sub point triangle.a in
  let d00 = Vec3.dot v0 v0 and d01 = Vec3.dot v0 v1
  and d11 = Vec3.dot v1 v1 and d20 = Vec3.dot v2 v0
  and d21 = Vec3.dot v2 v1 in
  let denominator = (d00 *. d11) -. (d01 *. d01) in
  if abs_float denominator <= epsilon then None
  else
    let v = ((d11 *. d20) -. (d01 *. d21)) /. denominator in
    let w = ((d00 *. d21) -. (d01 *. d20)) /. denominator in
    Some (1. -. v -. w, v, w)

let contains ?(epsilon = 1e-9) triangle point =
  let plane_distance = abs_float (Vec3.dot (normal triangle) (Vec3.sub point triangle.a)) in
  if plane_distance > epsilon then false
  else
    match barycentric ~epsilon triangle point with
    | None -> false
    | Some (u, v, w) -> u >= -.epsilon && v >= -.epsilon && w >= -.epsilon

let closest_point triangle point =
  (* Ericson's region tests, Real-Time Collision Detection. *)
  let a = triangle.a and b = triangle.b and c = triangle.c in
  let ab = Vec3.sub b a and ac = Vec3.sub c a and ap = Vec3.sub point a in
  let d1 = Vec3.dot ab ap and d2 = Vec3.dot ac ap in
  if d1 <= 0. && d2 <= 0. then a
  else
    let bp = Vec3.sub point b in
    let d3 = Vec3.dot ab bp and d4 = Vec3.dot ac bp in
    if d3 >= 0. && d4 <= d3 then b
    else
      let vc = (d1 *. d4) -. (d3 *. d2) in
      if vc <= 0. && d1 >= 0. && d3 <= 0. then
        Vec3.add a (Vec3.scale ab (d1 /. (d1 -. d3)))
      else
        let cp = Vec3.sub point c in
        let d5 = Vec3.dot ab cp and d6 = Vec3.dot ac cp in
        if d6 >= 0. && d5 <= d6 then c
        else
          let vb = (d5 *. d2) -. (d1 *. d6) in
          if vb <= 0. && d2 >= 0. && d6 <= 0. then
            Vec3.add a (Vec3.scale ac (d2 /. (d2 -. d6)))
          else
            let va = (d3 *. d6) -. (d5 *. d4) in
            if va <= 0. && d4 -. d3 >= 0. && d5 -. d6 >= 0. then
              Vec3.add b (Vec3.scale (Vec3.sub c b) ((d4 -. d3) /. ((d4 -. d3) +. (d5 -. d6))))
            else
              let denominator = 1. /. (va +. vb +. vc) in
              let v = vb *. denominator and w = vc *. denominator in
              Vec3.add a (Vec3.add (Vec3.scale ab v) (Vec3.scale ac w))

let altitude vertex triangle =
  let left, right, apex = match vertex with
    | A -> triangle.b, triangle.c, triangle.a
    | B -> triangle.a, triangle.c, triangle.b
    | C -> triangle.a, triangle.b, triangle.c
  in
  let edge = Vec3.sub right left in
  let amount =
    let length_sq = Vec3.length_sq edge in
    if length_sq <= 1e-18 then 0.
    else max 0. (min 1.
      (Vec3.dot (Vec3.sub apex left) edge /. length_sq))
  in
  let foot = Vec3.add left (Vec3.scale edge amount) in
  Ray3.make ~origin:foot ~direction:(Vec3.sub apex foot)

let transform matrix triangle = make (Mat4.transform_point matrix triangle.a) (Mat4.transform_point matrix triangle.b) (Mat4.transform_point matrix triangle.c)
