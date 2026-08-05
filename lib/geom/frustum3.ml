open Prismel

type t = { corners : Vec3.t array; planes : Plane3.t array }

let of_camera ~viewport:(x,y,width,height as viewport) camera =
  let screen x y depth =
    match Camera.screen_to_world ~viewport camera
        (Vec3.create (float_of_int x) (float_of_int y) depth) with
    | Some point -> point
    | None -> invalid_arg "Frustum3.of_camera: camera matrix is singular" in
  let corners = [|
    screen x y 0.; screen (x+width) y 0.;
    screen (x+width) (y+height) 0.; screen x (y+height) 0.;
    screen x y 1.; screen (x+width) y 1.;
    screen (x+width) (y+height) 1.; screen x (y+height) 1.;
  |] in
  let center = Array.fold_left Vec3.add Vec3.zero corners
      |> fun sum -> Vec3.scale sum (1./.8.) in
  let plane a b c =
    match Plane3.through_three_points corners.(a) corners.(b) corners.(c) with
    | None -> invalid_arg "Frustum3.of_camera: degenerate frustum"
    | Some plane ->
        if Plane3.signed_distance plane center < 0. then Plane3.flip plane
        else plane in
  { corners; planes = [|plane 0 3 7; plane 1 5 6; plane 0 4 5;
    plane 3 2 6; plane 0 1 2; plane 4 7 6|] }

let corners frustum = Array.to_list frustum.corners
let planes frustum = Array.to_list frustum.planes
let contains ?(epsilon = 1e-9) frustum point =
  Array.for_all (fun plane -> Plane3.signed_distance plane point >= -.epsilon)
    frustum.planes
let intersects_sphere ?(epsilon = 1e-9) frustum sphere =
  Array.for_all (fun plane ->
    Plane3.signed_distance plane sphere.Sphere3.center
      >= -.sphere.radius -. epsilon) frustum.planes
let intersects_bounds ?(epsilon = 1e-9) frustum bounds =
  let corners = Bounds3.corners bounds in
  Array.for_all (fun plane -> List.exists (fun point ->
    Plane3.signed_distance plane point >= -.epsilon) corners) frustum.planes

let to_mesh frustum =
  Mesh.create_exn ~mode:Mesh.Triangles
    ~indices:[0;2;1; 0;3;2; 4;5;6; 4;6;7;
      0;1;5; 0;5;4; 1;2;6; 1;6;5;
      2;3;7; 2;7;6; 3;0;4; 3;4;7]
    (corners frustum) |> Mesh.recalculate_normals
