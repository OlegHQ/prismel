open Prismel

type t = { a : Vec3.t; b : Vec3.t; c : Vec3.t; d : Vec3.t }

let raw a b c d = { a; b; c; d }
let normal quad = Triangle3.normal (Triangle3.make quad.a quad.b quad.c)

let make ?(epsilon = 1e-8) a b c d =
  let quad = raw a b c d in
  let cross = Vec3.cross (Vec3.sub b a) (Vec3.sub c a) in
  if Vec3.length_sq cross <= epsilon *. epsilon then
    Error "Quad3.make: first three points are collinear"
  else
    let plane = Plane3.through ~normal:cross ~point:a in
    if abs_float (Plane3.signed_distance plane d) > epsilon then
      Error "Quad3.make: points are not coplanar"
    else Ok quad

let square ?(center = Vec3.zero) ~size () =
  if not (Float.is_finite size) || size <= 0. then
    invalid_arg "Quad3.square: size must be finite and positive";
  let half = size /. 2. in
  raw
    (Vec3.add center (Vec3.create (-.half) (-.half) 0.))
    (Vec3.add center (Vec3.create half (-.half) 0.))
    (Vec3.add center (Vec3.create half half 0.))
    (Vec3.add center (Vec3.create (-.half) half 0.))

let vertices quad = [quad.a; quad.b; quad.c; quad.d]
let edges quad = [Segment3.make quad.a quad.b; Segment3.make quad.b quad.c;
  Segment3.make quad.c quad.d; Segment3.make quad.d quad.a]
let area quad = Triangle3.area (Triangle3.make quad.a quad.b quad.c) +.
  Triangle3.area (Triangle3.make quad.a quad.c quad.d)
let perimeter quad = List.fold_left (fun total edge -> total +. Segment3.length edge) 0. (edges quad)
let centroid quad = List.fold_left Vec3.add Vec3.zero (vertices quad) |> fun sum -> Vec3.scale sum 0.25
let bounds quad = Bounds3.of_points (vertices quad) |> Option.get

let basis quad =
  let u = Vec3.normalize (Vec3.sub quad.b quad.a) in
  let n = normal quad in
  let v = Vec3.cross n u in
  let project point = let delta = Vec3.sub point quad.a in
    Vec2.create (Vec3.dot delta u) (Vec3.dot delta v) in
  let lift point = Vec3.add quad.a
      (Vec3.add (Vec3.scale u point.Vec2.x) (Vec3.scale v point.y)) in
  project, lift

let contains ?(epsilon = 1e-8) quad point =
  let plane = Plane3.through ~normal:(normal quad) ~point:quad.a in
  if abs_float (Plane3.signed_distance plane point) > epsilon then false
  else
    let project, _ = basis quad in
    let polygon = Polygon2.create_exn (List.map project (vertices quad)) in
    Polygon2.contains ~epsilon polygon (project point)

let inset ~distance quad =
  let project, lift = basis quad in
  let polygon = Polygon2.create_exn (List.map project (vertices quad)) in
  Result.bind (Polygon2.inset ~distance polygon) (fun polygon ->
    match List.map lift (Polygon2.vertices polygon) with
    | [a;b;c;d] -> make a b c d
    | _ -> Error "Quad3.inset: inset did not produce four vertices")

let transform matrix quad = raw
    (Mat4.transform_point matrix quad.a) (Mat4.transform_point matrix quad.b)
    (Mat4.transform_point matrix quad.c) (Mat4.transform_point matrix quad.d)

let to_mesh ?(flat = false) quad =
  let mesh = Mesh.create_exn ~mode:Mesh.Triangles ~indices:[0;1;2; 0;2;3]
      (vertices quad) in
  if flat then Mesh.flat_shaded mesh else Mesh.recalculate_normals mesh
