open Prismel

type hit = { point : Vec3.t; distance : float; normal : Vec3.t; barycentric : (float * float * float) option }

let validate epsilon =
  if not (Float.is_finite epsilon) || epsilon < 0. then
    invalid_arg "Intersect3: epsilon must be finite and non-negative"

let oppose direction normal = if Vec3.dot direction normal > 0. then Vec3.neg normal else normal

let ray_plane ?(epsilon = 1e-9) (ray : Ray3.t) (plane : Plane3.t) =
  validate epsilon;
  let denominator = Vec3.dot plane.normal ray.direction in
  if abs_float denominator <= epsilon then None
  else
    let distance = (plane.offset -. Vec3.dot plane.normal ray.origin) /. denominator in
    if distance < -.epsilon then None
    else
      let distance = Float.max 0. distance in
      Some { point = Ray3.point_at ray distance; distance;
             normal = oppose ray.direction plane.normal; barycentric = None }

let ray_sphere ?(epsilon = 1e-9) (ray : Ray3.t) (sphere : Sphere3.t) =
  validate epsilon;
  let offset = Vec3.sub ray.origin sphere.center in
  let b = Vec3.dot offset ray.direction in
  let c = Vec3.length_sq offset -. (sphere.radius *. sphere.radius) in
  let discriminant = (b *. b) -. c in
  if discriminant < -.epsilon then []
  else
    let root = sqrt (Float.max 0. discriminant) in
    let distances = if root <= epsilon then [-.b] else [-.b -. root; -.b +. root] in
    distances |> List.filter (fun distance -> distance >= -.epsilon)
    |> List.map (fun distance ->
      let distance = Float.max 0. distance in
      let point = Ray3.point_at ray distance in
      { point; distance; normal = Vec3.sub point sphere.center |> Vec3.normalize |> oppose ray.direction; barycentric = None })

let ray_bounds ?(epsilon = 1e-9) (ray : Ray3.t) (bounds : Bounds3.t) =
  validate epsilon;
  let entries = ref [] and exits = ref [] and missed = ref false in
  let axis origin direction minimum maximum low_normal high_normal =
    if abs_float direction <= epsilon then begin
      if origin < minimum || origin > maximum then missed := true
    end else begin
      let low = (minimum -. origin) /. direction
      and high = (maximum -. origin) /. direction in
      if low <= high then begin entries := (low, low_normal) :: !entries; exits := (high, high_normal) :: !exits end
      else begin entries := (high, high_normal) :: !entries; exits := (low, low_normal) :: !exits end
    end
  in
  axis ray.origin.x ray.direction.x bounds.min.x bounds.max.x (Vec3.create (-1.) 0. 0.) (Vec3.create 1. 0. 0.);
  axis ray.origin.y ray.direction.y bounds.min.y bounds.max.y (Vec3.create 0. (-1.) 0.) (Vec3.create 0. 1. 0.);
  axis ray.origin.z ray.direction.z bounds.min.z bounds.max.z (Vec3.create 0. 0. (-1.)) (Vec3.create 0. 0. 1.);
  if !missed then None
  else
    let entry, entry_normal = List.fold_left (fun ((best, _) as current) candidate -> if fst candidate > best then candidate else current) (neg_infinity, Vec3.zero) !entries in
    let exit, exit_normal = List.fold_left (fun ((best, _) as current) candidate -> if fst candidate < best then candidate else current) (infinity, Vec3.zero) !exits in
    if entry > exit +. epsilon || exit < -.epsilon then None
    else
      let distance, normal = if entry >= 0. then entry, entry_normal else exit, exit_normal in
      Some { point = Ray3.point_at ray distance; distance; normal; barycentric = None }

let ray_triangle ?(epsilon = 1e-9) (ray : Ray3.t) (triangle : Triangle3.t) =
  validate epsilon;
  let edge1 = Vec3.sub triangle.b triangle.a
  and edge2 = Vec3.sub triangle.c triangle.a in
  let p = Vec3.cross ray.direction edge2 in
  let determinant = Vec3.dot edge1 p in
  if abs_float determinant <= epsilon then None
  else
    let inverse = 1. /. determinant in
    let offset = Vec3.sub ray.origin triangle.a in
    let v = Vec3.dot offset p *. inverse in
    if v < -.epsilon || v > 1. +. epsilon then None
    else
      let q = Vec3.cross offset edge1 in
      let w = Vec3.dot ray.direction q *. inverse in
      if w < -.epsilon || v +. w > 1. +. epsilon then None
      else
        let distance = Vec3.dot edge2 q *. inverse in
        if distance < -.epsilon then None
        else
          let distance = Float.max 0. distance in
          Some { point = Ray3.point_at ray distance; distance;
                 normal = Triangle3.normal triangle |> oppose ray.direction;
                 barycentric = Some (1. -. v -. w, v, w) }

let sphere_sphere (left : Sphere3.t) (right : Sphere3.t) =
  Vec3.distance left.center right.center <= left.radius +. right.radius

let sphere_bounds (sphere : Sphere3.t) bounds = Bounds3.distance_sq bounds sphere.center <= sphere.radius *. sphere.radius
let sphere_triangle (sphere : Sphere3.t) triangle = Vec3.distance sphere.center (Triangle3.closest_point triangle sphere.center) <= sphere.radius
let plane_sphere ?(epsilon = 1e-9) plane (sphere : Sphere3.t) = abs_float (Plane3.signed_distance plane sphere.center) <= sphere.radius +. epsilon

let plane_bounds ?(epsilon = 1e-9) plane bounds =
  let distances = Bounds3.corners bounds |> List.map (Plane3.signed_distance plane) in
  List.fold_left Float.min infinity distances <= epsilon && List.fold_left Float.max neg_infinity distances >= -.epsilon

let plane_plane ?(epsilon = 1e-9) (left : Plane3.t) (right : Plane3.t) =
  let direction = Vec3.cross left.normal right.normal in
  let denominator = Vec3.length_sq direction in
  if denominator <= epsilon *. epsilon then None
  else
    let weighted = Vec3.sub (Vec3.scale right.normal left.offset) (Vec3.scale left.normal right.offset) in
    let origin = Vec3.cross weighted direction |> Fun.flip Vec3.scale (1. /. denominator) in
    Some (Ray3.make ~origin ~direction)

let triangle_bounds ?(epsilon = 1e-9) (triangle : Triangle3.t) bounds =
  if Bounds3.contains bounds triangle.a || Bounds3.contains bounds triangle.b || Bounds3.contains bounds triangle.c then true
  else
    let triangle_edges = [triangle.a, triangle.b; triangle.b, triangle.c; triangle.c, triangle.a] in
    let edge_hits_bounds (a, b) =
      let length = Vec3.distance a b in
      if length <= epsilon then false
      else match ray_bounds ~epsilon (Ray3.through ~origin:a b) bounds with Some hit -> hit.distance <= length +. epsilon | None -> false
    in
    if List.exists edge_hits_bounds triangle_edges then true
    else
      let corners = Array.of_list (Bounds3.corners bounds) in
      let box_edges = [0,1;1,2;2,3;3,0;4,5;5,6;6,7;7,4;0,4;1,5;2,6;3,7] in
      List.exists (fun (a, b) ->
        let origin = corners.(a) and target = corners.(b) in
        let length = Vec3.distance origin target in
        match ray_triangle ~epsilon (Ray3.through ~origin target) triangle with
        | Some hit -> hit.distance <= length +. epsilon
        | None -> false) box_edges

let tetrahedron_tetrahedron ?(epsilon = 1e-9)
    (left : Tetrahedron3.t) (right : Tetrahedron3.t) =
  validate epsilon;
  let vertices tetrahedron =
    [tetrahedron.Tetrahedron3.a; tetrahedron.b; tetrahedron.c; tetrahedron.d]
  in
  let edges tetrahedron =
    let values = Array.of_list (vertices tetrahedron) in
    [0,1;0,2;0,3;1,2;1,3;2,3]
    |> List.map (fun (a,b) -> Vec3.sub values.(b) values.(a))
  in
  let face_normals tetrahedron =
    Tetrahedron3.faces tetrahedron |> List.map Triangle3.normal
  in
  let axes = face_normals left @ face_normals right @
    List.concat_map (fun a ->
      List.map (fun b -> Vec3.cross a b) (edges right)) (edges left)
  in
  let separated axis =
    if Vec3.length_sq axis <= epsilon *. epsilon then false
    else
      let project points = List.fold_left (fun (low,high) point ->
        let value = Vec3.dot point axis in
        min low value, max high value) (infinity, neg_infinity) points in
      let amin,amax = project (vertices left)
      and bmin,bmax = project (vertices right) in
      amax < bmin -. epsilon || bmax < amin -. epsilon
  in
  not (List.exists separated axes)
