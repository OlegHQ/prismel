open Prismel_next_api

let put_f64 bytes offset value =
  Bytes.set_int64_le bytes offset (Int64.bits_of_float value)

let put_f32 bytes offset value =
  Bytes.set_int32_le bytes offset (Int32.bits_of_float value)

let state width height : Scene_execution.state =
  { viewport = (0, 0, width, height);
    scissor = (0, 0, width, height);
    cull = Ogpu.Render_pass.Cull_back;
    depth_compare = Ogpu.Render_pass.Less;
    depth_write = true;
    depth_load = Ogpu.Render_pass.Clear;
    depth_clear = 1.;
    transform_uniforms = None;
    stencil_state = None;
    stencil_load = Ogpu.Render_pass.Clear;
    stencil_clear = 0 }

let indices_bytes values =
  let bytes = Bytes.create (Array.length values * 4) in
  Array.iteri
    (fun index value ->
      Bytes.set_int32_le bytes (index * 4) (Int32.of_int value))
    values;
  bytes

let software_vertices ~width ~height matrix points =
  let bytes = Bytes.create (Array.length points * 16) in
  Array.iteri
    (fun index point ->
      let x, y, _, w =
        Mat4.transform matrix (point.Vec3.x, point.y, point.z, 1.)
      in
      let x = x /. w and y = y /. w in
      put_f64 bytes (index * 16) ((x +. 1.) *. 0.5 *. float width);
      put_f64 bytes ((index * 16) + 8)
        ((1. -. y) *. 0.5 *. float height))
    points;
  bytes

let native_vertices matrix points =
  let bytes = Bytes.create (Array.length points * 68) in
  Array.iteri
    (fun index point ->
      let x, y, z, w =
        Mat4.transform matrix (point.Vec3.x, point.y, point.z, 1.)
      in
      let offset = index * 68 in
      put_f32 bytes offset x;
      put_f32 bytes (offset + 4) y;
      put_f32 bytes (offset + 8) z;
      put_f32 bytes (offset + 12) w;
      put_f32 bytes (offset + 28) (56. /. 255.);
      put_f32 bytes (offset + 32) (189. /. 255.);
      put_f32 bytes (offset + 36) (248. /. 255.);
      put_f32 bytes (offset + 40) 1.;
      put_f64 bytes (offset + 52) 0.;
      put_f64 bytes (offset + 60) 0.)
    points;
  bytes

let mesh key vertices indices vertex_count index_count : Scene_execution.mesh =
  { key; vertices; vertex_count; indices; index_count }

let create ~width ~height =
  if width <= 0 || height <= 0 then invalid_arg "R10 Scene3 extent";
  let source = Mesh.sphere ~segments:96 ~rings:48 ~radius:1. () in
  let points = Array.of_list (Mesh.vertices source)
  and indices = Array.of_list (Mesh.indices source) in
  let packed_indices = indices_bytes indices in
  let camera =
    Camera.perspective ~at:(Vec3.create 0. 0. 5.4) ~target:Vec3.zero ()
  in
  let view_projection =
    Camera.view_projection_matrix ~viewport:(0, 0, width, height) camera
  in
  let software_draws, native_draws =
    List.split
      (List.init 12 (fun instance ->
         let angle = float instance /. 12. *. Math.two_pi in
         let model =
           Mat4.mul
             (Mat4.translation
                (Vec3.create (Float.cos angle *. 1.9)
                   (Float.sin angle *. 1.2) 0.))
             (Mat4.scaling (Vec3.create 0.38 0.38 0.38))
         in
         let matrix = Mat4.mul view_projection model in
         let key = "legacy-scene3-sphere-" ^ string_of_int instance in
         let make vertices =
           { Scene_execution.mesh =
               mesh key vertices packed_indices (Array.length points)
                 (Array.length indices);
             state = state width height }
         in
         (make (software_vertices ~width ~height matrix points),
          make (native_vertices matrix points))))
  in
  let digest draws =
    let context = Digest.string in
    draws
    |> List.map (fun (draw : Scene_execution.draw) ->
           Digest.to_hex (Digest.bytes draw.mesh.vertices)
           ^ Digest.to_hex (Digest.bytes draw.mesh.indices))
    |> String.concat ":" |> context |> Digest.to_hex
  in
  { software_draws;
    native_draws;
    instances = 12;
    vertices_per_instance = Array.length points;
    indices_per_instance = Array.length indices;
    triangles = 12 * Array.length indices / 3;
    samples = 4;
    diffuse_rgb = (56, 189, 248);
    ambient_rgb = (18, 22, 30);
    light_direction = (-0.6, -1., -1.4);
    signature = digest software_draws ^ ":" ^ digest native_draws }
