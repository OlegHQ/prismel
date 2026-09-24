open Prismel

type uv_generator = face:int -> vertex:int -> point:Vec3.t -> Vec2.t

let face_uvs values =
  let values = Array.of_list (List.map Array.of_list values) in
  fun ~face ~vertex ~point:_ ->
    if face < 0 || face >= Array.length values then
      invalid_arg "Mesh_attrib.face_uvs: missing face";
    let face_values = values.(face) in
    if vertex < 0 || vertex >= Array.length face_values then
      invalid_arg "Mesh_attrib.face_uvs: missing face vertex";
    face_values.(vertex)

let constant_uv value ~face:_ ~vertex:_ ~point:_ = value

let uv_rect ?(x = 0.) ?(y = 0.) ?(u_width = 1.) ?(v_height = 1.)
    ~width ~height () =
  if width <= 0. || height <= 0. then
    invalid_arg "Mesh_attrib.uv_rect: dimensions must be positive";
  let u = 0.5 *. u_width /. width and v = 0.5 *. v_height /. height in
  [Vec2.create (x+.u) (y+.v); Vec2.create (x+.u_width-.u) (y+.v);
   Vec2.create (x+.u_width-.u) (y+.v_height-.v);
   Vec2.create (x+.u) (y+.v_height-.v)]

let next_power_of_two value =
  let result = ref 1 in while !result < value do result := !result lsl 1 done; !result

let uv_cube_map_horizontal ?(power_of_two = false) ~face_size () =
  if face_size <= 0 then invalid_arg "Mesh_attrib.uv_cube_map_horizontal: face size must be positive";
  let width = face_size * 6 in
  let texture_width = if power_of_two then next_power_of_two width else width in
  let face_width = float_of_int width /. float_of_int texture_width /. 6. in
  List.init 6 (fun face -> uv_rect ~x:(float_of_int face *. face_width)
    ~u_width:face_width ~width:(float_of_int face_size) ~height:(float_of_int face_size) ())

let uv_cube_map_vertical ?(power_of_two = false) ~face_size () =
  if face_size <= 0 then invalid_arg "Mesh_attrib.uv_cube_map_vertical: face size must be positive";
  let height = face_size * 6 in
  let texture_height = if power_of_two then next_power_of_two height else height in
  let face_height = float_of_int height /. float_of_int texture_height /. 6. in
  List.init 6 (fun face -> uv_rect ~y:(float_of_int face *. face_height)
    ~v_height:face_height ~width:(float_of_int face_size) ~height:(float_of_int face_size) ())

let uv_tube ~u ~v ~du ~dv =
  [Vec2.create u v; Vec2.create (u+.du) v;
   Vec2.create (u+.du) (v+.dv); Vec2.create u (v+.dv)]

let uv_flat_disc ~theta ~delta ~radius =
  let point angle = Vec2.create (0.5 +. cos angle *. radius)
      (0.5 +. sin angle *. radius) in
  [Vec2.create 0.5 0.5; point theta; point (theta+.delta)]

let uv_polygon_disc ~vertices =
  if vertices < 3 then invalid_arg "Mesh_attrib.uv_polygon_disc: vertex count must be at least three";
  List.init vertices (fun index ->
    let angle = float_of_int index /. float_of_int vertices *. 2. *. Float.pi in
    Vec2.create (0.5 +. cos angle *. 0.5) (0.5 +. sin angle *. 0.5))

let with_generated_uvs generator mesh =
  let source = Mesh.Private.view mesh in
  let triangle_count = Mesh.Private.triangle_count mesh in
  let output_count = triangle_count * 3 in
  let vertices = Array.make output_count Vec3.zero
  and tex_coords = Array.make output_count Vec2.zero
  and colors = Option.map (fun _ -> Array.make output_count Color.white)
      source.colors in
  let face = ref 0 in
  Mesh.Private.iter_triangles (fun a b c ->
    for vertex = 0 to 2 do
      let target = (!face * 3) + vertex in
      let source_index = if vertex = 0 then a else if vertex = 1 then b else c in
      let point = source.vertices.(source_index) in
      vertices.(target) <- point;
      tex_coords.(target) <- generator ~face:!face ~vertex ~point;
      (match colors, source.colors with
       | Some output, Some input -> output.(target) <- input.(source_index)
       | _ -> ())
    done;
    incr face) mesh;
  Mesh.Private.create_owned ~mode:Mesh.Triangles ~tex_coords ?colors vertices
  |> Result.map Mesh.recalculate_normals
