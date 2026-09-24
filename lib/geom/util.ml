open Prismel

let centroid2 = function
  | [] -> None
  | points -> Some (List.fold_left Vec2.add Vec2.zero points
      |> fun sum -> Vec2.scale sum (1. /. float_of_int (List.length points)))
let centroid3 = function
  | [] -> None
  | points -> Some (List.fold_left Vec3.add Vec3.zero points
      |> fun sum -> Vec3.scale sum (1. /. float_of_int (List.length points)))

let bounding_circle points = match centroid2 points with
  | None -> None
  | Some center -> Some (Circle2.make ~center ~radius:(List.fold_left
      (fun radius point -> max radius (Vec2.distance center point)) 0. points))
let bounding_sphere points = match centroid3 points with
  | None -> None
  | Some center -> Some (Sphere3.make ~center ~radius:(List.fold_left
      (fun radius point -> max radius (Vec3.distance center point)) 0. points))

let map_bilinear ~a ~b ~c ~d ~u ~v =
  Vec3.lerp (Vec3.lerp a b u) (Vec3.lerp d c u) v

let map_trilinear ~p000 ~p100 ~p110 ~p010 ~p001 ~p101 ~p111 ~p011
    ~u ~v ~w =
  Vec3.lerp
    (map_bilinear ~a:p000 ~b:p100 ~c:p110 ~d:p010 ~u ~v)
    (map_bilinear ~a:p001 ~b:p101 ~c:p111 ~d:p011 ~u ~v) w

let fit2 ?(uniform = true) ~source ~target () =
  let source_size = Bounds2.size source and target_size = Bounds2.size target in
  if source_size.x <= 1e-15 || source_size.y <= 1e-15 then
    invalid_arg "Util.fit2: source bounds must have positive area";
  let scaling = Vec2.create (target_size.x /. source_size.x)
      (target_size.y /. source_size.y) in
  let scaling = if uniform then
      let amount = min (abs_float scaling.x) (abs_float scaling.y) in
      Vec2.create amount amount else scaling in
  let source_center = Bounds2.center source and target_center = Bounds2.center target in
  Affine2.compose (Affine2.translation target_center)
    (Affine2.compose (Affine2.scaling scaling)
      (Affine2.translation (Vec2.neg source_center)))

let fit3 ?(uniform = true) ~source ~target () =
  let source_size = Bounds3.size source and target_size = Bounds3.size target in
  if source_size.x <= 1e-15 || source_size.y <= 1e-15 || source_size.z <= 1e-15 then
    invalid_arg "Util.fit3: source bounds must have positive volume";
  let scaling = Vec3.create (target_size.x /. source_size.x)
      (target_size.y /. source_size.y) (target_size.z /. source_size.z) in
  let scaling = if uniform then
      let amount = min (abs_float scaling.x)
          (min (abs_float scaling.y) (abs_float scaling.z)) in
      Vec3.create amount amount amount else scaling in
  Mat4.mul (Mat4.translation (Bounds3.center target))
    (Mat4.mul (Mat4.scaling scaling)
      (Mat4.translation (Vec3.neg (Bounds3.center source))))

let fit_points2 ?uniform ~target points = match Bounds2.of_points points with
  | None -> []
  | Some source -> List.map (Affine2.apply (fit2 ?uniform ~source ~target ())) points
let fit_points3 ?uniform ~target points = match Bounds3.of_points points with
  | None -> []
  | Some source -> List.map (Mat4.transform_point (fit3 ?uniform ~source ~target ())) points

let mesh_area mesh = Mesh.faces mesh |> List.fold_left
    (fun total (face : Mesh.face) ->
      let a,b,c = face.points in total +. Triangle3.area (Triangle3.make a b c)) 0.
let mesh_volume mesh = Mesh.faces mesh |> List.fold_left
    (fun total (face : Mesh.face) ->
      let a,b,c = face.points in total +. Vec3.dot a (Vec3.cross b c) /. 6.) 0.
  |> abs_float
