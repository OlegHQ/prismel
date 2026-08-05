open Prismel

let finite value = Float.is_finite value
let float_key value = Int64.to_string (Int64.bits_of_float value)
exception Native_cancelled

type element_group =
  | Point_group of string
  | Vertex_group of string
  | Primitive_group of string
  | Edge_group of string

let element_group_key = function
  | Point_group name -> "point:" ^ String.escaped name
  | Vertex_group name -> "vertex:" ^ String.escaped name
  | Primitive_group name -> "primitive:" ^ String.escaped name
  | Edge_group name -> "edge:" ^ String.escaped name

let resolve_element_group ~operation selection geometry = match selection with
  | None -> Ok None
  | Some (Point_group name) ->
      (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
       | Some group -> Ok (Some (Pdk.Ops.Selected_points group))
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find point group %S" operation name)))
  | Some (Vertex_group name) ->
      (match Pdk.Geometry.find_group ~owner:Pdk.Group.Vertex name geometry with
       | Some group -> Ok (Some (Pdk.Ops.Selected_vertices group))
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find vertex group %S" operation name)))
  | Some (Primitive_group name) ->
      (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
       | Some group -> Ok (Some (Pdk.Ops.Selected_primitives group))
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find primitive group %S" operation name)))
  | Some (Edge_group name) ->
      (match Pdk.Geometry.find_edge_group name geometry with
       | Some group -> Ok (Some (Pdk.Ops.Selected_edges group))
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find edge group %S" operation name)))

let vec3_copy value = Vec3.create value.Vec3.x value.y value.z
let vec3_key value = String.concat "," [ float_key value.Vec3.x;
  float_key value.y; float_key value.z ]
let vec2_copy value = Vec2.create value.Vec2.x value.y
let vec2_key value = String.concat "," [float_key value.Vec2.x; float_key value.y]
let option_string_key = function
  | None -> "none" | Some value -> String.escaped value
let option_float_key = function
  | None -> "none" | Some value -> "some:" ^ float_key value

let matrix_copy matrix =
  let a, b, c, d = Mat4.to_rows matrix in
  Mat4.of_rows a b c d

let matrix_key matrix =
  let a, b, c, d = Mat4.to_rows matrix in
  let row (x, y, z, w) =
    String.concat "," [float_key x; float_key y; float_key z; float_key w]
  in
  String.concat ";" [row a; row b; row c; row d]

let matrices_fingerprint matrices =
  let hash = ref 0xcbf29ce484222325L in
  let mix bits =
    hash := Int64.mul (Int64.logxor !hash bits) 0x100000001b3L in
  mix (Int64.of_int (Array.length matrices));
  Array.iter (fun matrix ->
    for row = 0 to 3 do for column = 0 to 3 do
      mix (Int64.bits_of_float (Mat4.get matrix ~row ~column))
    done done) matrices;
  Printf.sprintf "%Lx" !hash

let color_key color =
  let r, g, b, a = Color.to_tuple color in
  Printf.sprintf "%d,%d,%d,%d" r g b a

let cooked geometry = Ok Node.Private.{ geometry; diagnostics = [] }
let pdk_error ?(hints = []) operation message =
  Error (Diagnostic.error ~code:(operation ^ "_failed") ~cause:message ~hints
    (operation ^ " could not produce valid geometry"))

let structured_pdk_error error =
  Error (Diagnostic.error ~code:(Pdk.Error.code error)
    ~cause:(Pdk.Error.to_string error) ~hints:(Pdk.Error.hints error)
    (Pdk.Error.operation error ^ " could not produce valid geometry"))

let snapshot ?label geometry =
  let parameters = Printf.sprintf "data_id=%d;bytes=%d"
      (Pdk.Geometry.data_id geometry) (Pdk.Geometry.payload_bytes geometry) in
  Node.Private.make ?label ~operation:"snapshot" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _context _inputs -> cooked geometry)

let points ?label values =
  let values = Array.copy values in
  let parameters = Printf.sprintf "count=%d" (Array.length values) in
  Node.Private.make ?label ~operation:"points" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _context _inputs ->
      if Array.exists (fun (x, y, z) -> not (finite x && finite y && finite z)) values
      then Error (Diagnostic.error ~code:"non_finite_position"
        "points requires finite x, y, and z coordinates")
      else cooked (Pdk.Ops.points values))

let point_generate_mode_key = function
  | Pdk.Ops.Generate_total points -> Printf.sprintf "total:%d" points
  | Pdk.Ops.Generate_per_point { points_per_point; scale_attribute } ->
      Printf.sprintf "per_point:%s:%s" (float_key points_per_point)
        (option_string_key scale_attribute)
  | Pdk.Ops.Generate_probability { attribute } ->
      "probability:" ^ String.escaped attribute

let point_generate_origin ?label ?generated_group
    ?(source_point_attribute = "sourcepoint")
    ?(source_index_attribute = "sourceindex") ~points () =
  let mode = Pdk.Ops.Generate_total points in
  Node.Private.make ?label ~operation:"point_generate" ~version:1
    ~parameters:(String.concat ";" [
      "mode=" ^ point_generate_mode_key mode;
      "generated_group=" ^ option_string_key generated_group;
      "source_point=" ^ String.escaped source_point_attribute;
      "source_index=" ^ String.escaped source_index_attribute])
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.point_generate ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?generated_group
          ~source_point_attribute ~source_index_attribute ~mode
          (Pdk.Ops.points [||]) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let line_kind_key = function
  | Pdk.Ops.Line_curve -> "curve"
  | Pdk.Ops.Line_points -> "points"

let line ?label ?(kind = Pdk.Ops.Line_curve) ?(points = 2)
    ~origin ~direction ~length () =
  let origin = vec3_copy origin and direction = vec3_copy direction in
  Node.Private.make ?label ~operation:"line" ~version:1
    ~parameters:(Printf.sprintf
      "kind=%s;points=%d;origin=%s;direction=%s;length=%s"
      (line_kind_key kind) points (vec3_key origin) (vec3_key direction)
      (float_key length))
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.line ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~kind ~points ~origin ~direction
          ~length () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let polyline ?label ?(closed = false) values =
  let values = Array.copy values in
  let parameters = Printf.sprintf "count=%d;closed=%b" (Array.length values) closed in
  Node.Private.make ?label ~operation:"polyline" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _context _inputs ->
      match Pdk.Ops.polyline ~closed values with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let circle_arc_key = function
  | Pdk.Ops.Circle_closed -> "closed"
  | Pdk.Ops.Circle_open_arc { start_angle; end_angle } ->
      "open:" ^ float_key start_angle ^ ":" ^ float_key end_angle
  | Pdk.Ops.Circle_closed_arc { start_angle; end_angle } ->
      "closed_arc:" ^ float_key start_angle ^ ":" ^ float_key end_angle
  | Pdk.Ops.Circle_sliced_arc { start_angle; end_angle } ->
      "sliced:" ^ float_key start_angle ^ ":" ^ float_key end_angle

let circle_orientation_copy = function
  | Pdk.Ops.Circle_xy -> Pdk.Ops.Circle_xy
  | Pdk.Ops.Circle_xz -> Pdk.Ops.Circle_xz
  | Pdk.Ops.Circle_yz -> Pdk.Ops.Circle_yz
  | Pdk.Ops.Circle_axes { horizontal; vertical } ->
      Pdk.Ops.Circle_axes {
        horizontal = vec3_copy horizontal; vertical = vec3_copy vertical }

let circle_orientation_key = function
  | Pdk.Ops.Circle_xy -> "xy"
  | Pdk.Ops.Circle_xz -> "xz"
  | Pdk.Ops.Circle_yz -> "yz"
  | Pdk.Ops.Circle_axes { horizontal; vertical } ->
      "axes:" ^ vec3_key horizontal ^ ":" ^ vec3_key vertical

let circle ?label ?(arc = Pdk.Ops.Circle_closed)
    ?(orientation = Pdk.Ops.Circle_xz) ?(reverse = false)
    ?(center = Vec3.zero) ?radius_x ?radius_y ?(rotation = 0.)
    ?(uniform_scale = 1.) ?(segments = 64) ~radius () =
  let orientation = circle_orientation_copy orientation
  and center = vec3_copy center in
  let optional_float = function None -> "none" | Some value -> float_key value in
  let parameters = String.concat ";" [
      "segments=" ^ string_of_int segments;
      "radius=" ^ float_key radius;
      "arc=" ^ circle_arc_key arc;
      "orientation=" ^ circle_orientation_key orientation;
      "reverse=" ^ string_of_bool reverse;
      "center=" ^ vec3_key center;
      "radius_x=" ^ optional_float radius_x;
      "radius_y=" ^ optional_float radius_y;
      "rotation=" ^ float_key rotation;
      "uniform_scale=" ^ float_key uniform_scale ] in
  Node.Private.make ?label ~operation:"circle" ~version:2 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.circle ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~arc ~orientation ~reverse ~center
          ?radius_x ?radius_y ~rotation ~uniform_scale ~segments ~radius () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let grid_counts_key = function
  | Pdk.Ops.Grid_divisions -> "divisions"
  | Pdk.Ops.Grid_point_counts -> "point_counts"

let grid_connectivity_key = function
  | Pdk.Ops.Grid_points -> "points"
  | Pdk.Ops.Grid_rows -> "rows"
  | Pdk.Ops.Grid_columns -> "columns"
  | Pdk.Ops.Grid_rows_and_columns -> "rows_columns"
  | Pdk.Ops.Grid_quads -> "quads"
  | Pdk.Ops.Grid_triangles -> "triangles"
  | Pdk.Ops.Grid_alternating_triangles -> "alternating_triangles"
  | Pdk.Ops.Grid_reverse_triangles -> "reverse_triangles"

let grid_orientation_copy = function
  | Pdk.Ops.Grid_xy -> Pdk.Ops.Grid_xy
  | Pdk.Ops.Grid_xz -> Pdk.Ops.Grid_xz
  | Pdk.Ops.Grid_yz -> Pdk.Ops.Grid_yz
  | Pdk.Ops.Grid_axes { horizontal; vertical } -> Pdk.Ops.Grid_axes {
      horizontal = vec3_copy horizontal; vertical = vec3_copy vertical }

let grid_orientation_key = function
  | Pdk.Ops.Grid_xy -> "xy"
  | Pdk.Ops.Grid_xz -> "xz"
  | Pdk.Ops.Grid_yz -> "yz"
  | Pdk.Ops.Grid_axes { horizontal; vertical } ->
      "axes:" ^ vec3_key horizontal ^ ":" ^ vec3_key vertical

let grid ?label ?(counts = Pdk.Ops.Grid_divisions)
    ?(connectivity = Pdk.Ops.Grid_triangles)
    ?(orientation = Pdk.Ops.Grid_xz) ?(center = Vec3.zero) ?width ?height
    ?(rotation = 0.) ?uv_attribute ~columns ~rows ~size () =
  let orientation = grid_orientation_copy orientation
  and center = vec3_copy center in
  let optional_float = function None -> "none" | Some value -> float_key value in
  let parameters = String.concat ";" [
      "columns=" ^ string_of_int columns;
      "rows=" ^ string_of_int rows;
      "size=" ^ float_key size;
      "counts=" ^ grid_counts_key counts;
      "connectivity=" ^ grid_connectivity_key connectivity;
      "orientation=" ^ grid_orientation_key orientation;
      "center=" ^ vec3_key center;
      "width=" ^ optional_float width;
      "height=" ^ optional_float height;
      "rotation=" ^ float_key rotation;
      "uv=" ^ option_string_key uv_attribute ] in
  Node.Private.make ?label ~operation:"grid" ~version:2 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ _context _inputs ->
      match Pdk.Ops.grid ~cancel:(Context.cancel_token _context)
          ~grain:(Context.grain _context) ~counts ~connectivity ~orientation
          ~center ?width ?height ~rotation ?uv_attribute ~columns ~rows ~size () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let box_connectivity_key = function
  | Pdk.Ops.Box_triangles -> "triangles"
  | Pdk.Ops.Box_quads -> "quads"
  | Pdk.Ops.Box_surface_points -> "surface_points"
  | Pdk.Ops.Box_lattice_points -> "lattice_points"

let box_normals_key = function
  | Pdk.Ops.Box_no_normals -> "none"
  | Pdk.Ops.Box_point_normals -> "point"
  | Pdk.Ops.Box_vertex_normals -> "vertex"

let box_rotation_order_key = function
  | Pdk.Ops.Box_xyz -> "xyz" | Pdk.Ops.Box_xzy -> "xzy"
  | Pdk.Ops.Box_yxz -> "yxz" | Pdk.Ops.Box_yzx -> "yzx"
  | Pdk.Ops.Box_zxy -> "zxy" | Pdk.Ops.Box_zyx -> "zyx"

let box ?label ?(size = Vec3.create 1. 1. 1.)
    ?(connectivity = Pdk.Ops.Box_triangles) ?(consolidate_points = false)
    ?normals ?(center = Vec3.zero) ?(rotation = Vec3.zero)
    ?(rotation_order = Pdk.Ops.Box_xyz) ?(uniform_scale = 1.)
    ?(x_divisions = 1) ?(y_divisions = 1) ?(z_divisions = 1)
    ?uv_attribute ?face_groups () =
  let size = vec3_copy size and center = vec3_copy center
  and rotation = vec3_copy rotation in
  let parameters = String.concat ";" [
      "size=" ^ vec3_key size;
      "connectivity=" ^ box_connectivity_key connectivity;
      "consolidate=" ^ string_of_bool consolidate_points;
      "normals=" ^ Option.fold ~none:"default" ~some:box_normals_key normals;
      "center=" ^ vec3_key center;
      "rotation=" ^ vec3_key rotation;
      "rotation_order=" ^ box_rotation_order_key rotation_order;
      "uniform_scale=" ^ float_key uniform_scale;
      "x_divisions=" ^ string_of_int x_divisions;
      "y_divisions=" ^ string_of_int y_divisions;
      "z_divisions=" ^ string_of_int z_divisions;
      "uv=" ^ option_string_key uv_attribute;
      "face_groups=" ^ option_string_key face_groups ] in
  Node.Private.make ?label ~operation:"box" ~version:2 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.box ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~connectivity ~consolidate_points
          ?normals ~center ~rotation ~rotation_order ~uniform_scale
          ~x_divisions ~y_divisions ~z_divisions ?uv_attribute ?face_groups
          ~size () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let sphere_connectivity_key = function
  | Pdk.Ops.Sphere_triangles -> "triangles"
  | Pdk.Ops.Sphere_alternating_triangles -> "alternating_triangles"
  | Pdk.Ops.Sphere_quads -> "quads"
  | Pdk.Ops.Sphere_rows -> "rows"
  | Pdk.Ops.Sphere_columns -> "columns"
  | Pdk.Ops.Sphere_rows_and_columns -> "rows_and_columns"
  | Pdk.Ops.Sphere_points -> "points"

let sphere_normals_key = function
  | Pdk.Ops.Sphere_no_normals -> "none"
  | Pdk.Ops.Sphere_point_normals -> "point"
  | Pdk.Ops.Sphere_vertex_normals -> "vertex"

let sphere_orientation_key = function
  | Pdk.Ops.Sphere_x -> "x" | Pdk.Ops.Sphere_y -> "y"
  | Pdk.Ops.Sphere_z -> "z"
  | Pdk.Ops.Sphere_axis axis -> "axis:" ^ vec3_key axis

let sphere_rotation_order_key = function
  | Pdk.Ops.Sphere_xyz -> "xyz" | Pdk.Ops.Sphere_xzy -> "xzy"
  | Pdk.Ops.Sphere_yxz -> "yxz" | Pdk.Ops.Sphere_yzx -> "yzx"
  | Pdk.Ops.Sphere_zxy -> "zxy" | Pdk.Ops.Sphere_zyx -> "zyx"

let uv_sphere ?label ?(connectivity = Pdk.Ops.Sphere_triangles)
    ?(unique_points_per_pole = false) ?(triangular_poles = true) ?normals
    ?(orientation = Pdk.Ops.Sphere_y) ?(center = Vec3.zero)
    ?(rotation = Vec3.zero) ?(rotation_order = Pdk.Ops.Sphere_xyz)
    ?(uniform_scale = 1.) ?radius_x ?radius_y ?radius_z ?uv_attribute
    ?(segments = 48) ?(rings = 24) ~radius () =
  let orientation = match orientation with
    | Pdk.Ops.Sphere_axis axis -> Pdk.Ops.Sphere_axis (vec3_copy axis)
    | value -> value in
  let center = vec3_copy center and rotation = vec3_copy rotation in
  let parameters = String.concat ";" [
      "connectivity=" ^ sphere_connectivity_key connectivity;
      "unique_points_per_pole=" ^ string_of_bool unique_points_per_pole;
      "triangular_poles=" ^ string_of_bool triangular_poles;
      "normals=" ^ Option.fold ~none:"default" ~some:sphere_normals_key normals;
      "orientation=" ^ sphere_orientation_key orientation;
      "center=" ^ vec3_key center; "rotation=" ^ vec3_key rotation;
      "rotation_order=" ^ sphere_rotation_order_key rotation_order;
      "uniform_scale=" ^ float_key uniform_scale;
      "radius=" ^ float_key radius; "radius_x=" ^ option_float_key radius_x;
      "radius_y=" ^ option_float_key radius_y;
      "radius_z=" ^ option_float_key radius_z;
      "uv=" ^ option_string_key uv_attribute;
      "segments=" ^ string_of_int segments; "rings=" ^ string_of_int rings ] in
  Node.Private.make ?label ~operation:"uv_sphere" ~version:2 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.uv_sphere ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~connectivity ~unique_points_per_pole
          ~triangular_poles ?normals ~orientation ~center ~rotation
          ~rotation_order ~uniform_scale ?radius_x ?radius_y ?radius_z
          ?uv_attribute ~segments ~rings ~radius () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let torus_connectivity_key = function
  | Pdk.Ops.Torus_triangles -> "triangles"
  | Pdk.Ops.Torus_alternating_triangles -> "alternating_triangles"
  | Pdk.Ops.Torus_quads -> "quads"
  | Pdk.Ops.Torus_rows -> "rows"
  | Pdk.Ops.Torus_columns -> "columns"
  | Pdk.Ops.Torus_rows_and_columns -> "rows_and_columns"
  | Pdk.Ops.Torus_points -> "points"

let torus_normals_key = function
  | Pdk.Ops.Torus_no_normals -> "none"
  | Pdk.Ops.Torus_point_normals -> "point"
  | Pdk.Ops.Torus_vertex_normals -> "vertex"

let torus_orientation_key = function
  | Pdk.Ops.Torus_x -> "x" | Pdk.Ops.Torus_y -> "y"
  | Pdk.Ops.Torus_z -> "z"
  | Pdk.Ops.Torus_axis axis -> "axis:" ^ vec3_key axis

let torus_rotation_order_key = function
  | Pdk.Ops.Torus_xyz -> "xyz" | Pdk.Ops.Torus_xzy -> "xzy"
  | Pdk.Ops.Torus_yxz -> "yxz" | Pdk.Ops.Torus_yzx -> "yzx"
  | Pdk.Ops.Torus_zxy -> "zxy" | Pdk.Ops.Torus_zyx -> "zyx"

let torus ?label ?(connectivity = Pdk.Ops.Torus_triangles) ?normals
    ?(orientation = Pdk.Ops.Torus_y) ?(center = Vec3.zero)
    ?(rotation = Vec3.zero) ?(rotation_order = Pdk.Ops.Torus_xyz)
    ?(uniform_scale = 1.) ?(u_start = 0.) ?(u_end = 2. *. Float.pi)
    ?(v_start = 0.) ?(v_end = 2. *. Float.pi) ?(u_wrap = true)
    ?(v_wrap = true) ?(u_end_caps = false) ?(v_end_cap = false)
    ?uv_attribute ?(rows = 48) ?(columns = 24) ~major_radius ~minor_radius () =
  let orientation = match orientation with
    | Pdk.Ops.Torus_axis axis -> Pdk.Ops.Torus_axis (vec3_copy axis)
    | value -> value in
  let center = vec3_copy center and rotation = vec3_copy rotation in
  let parameters = String.concat ";" [
      "connectivity=" ^ torus_connectivity_key connectivity;
      "normals=" ^ Option.fold ~none:"default" ~some:torus_normals_key normals;
      "orientation=" ^ torus_orientation_key orientation;
      "center=" ^ vec3_key center; "rotation=" ^ vec3_key rotation;
      "rotation_order=" ^ torus_rotation_order_key rotation_order;
      "uniform_scale=" ^ float_key uniform_scale;
      "u_start=" ^ float_key u_start; "u_end=" ^ float_key u_end;
      "v_start=" ^ float_key v_start; "v_end=" ^ float_key v_end;
      "u_wrap=" ^ string_of_bool u_wrap; "v_wrap=" ^ string_of_bool v_wrap;
      "u_end_caps=" ^ string_of_bool u_end_caps;
      "v_end_cap=" ^ string_of_bool v_end_cap;
      "uv=" ^ option_string_key uv_attribute;
      "rows=" ^ string_of_int rows; "columns=" ^ string_of_int columns;
      "major_radius=" ^ float_key major_radius;
      "minor_radius=" ^ float_key minor_radius ] in
  Node.Private.make ?label ~operation:"torus" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.torus ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~connectivity ?normals ~orientation
          ~center ~rotation ~rotation_order ~uniform_scale ~u_start ~u_end
          ~v_start ~v_end ~u_wrap ~v_wrap ~u_end_caps ~v_end_cap ?uv_attribute
          ~rows ~columns ~major_radius ~minor_radius () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let tube_connectivity_key = function
  | Pdk.Ops.Tube_triangles -> "triangles"
  | Pdk.Ops.Tube_alternating_triangles -> "alternating_triangles"
  | Pdk.Ops.Tube_quads -> "quads"
  | Pdk.Ops.Tube_rows -> "rows"
  | Pdk.Ops.Tube_columns -> "columns"
  | Pdk.Ops.Tube_rows_and_columns -> "rows_and_columns"
  | Pdk.Ops.Tube_points -> "points"

let tube_normals_key = function
  | Pdk.Ops.Tube_no_normals -> "none"
  | Pdk.Ops.Tube_point_normals -> "point"
  | Pdk.Ops.Tube_vertex_normals -> "vertex"

let tube_orientation_key = function
  | Pdk.Ops.Tube_x -> "x" | Pdk.Ops.Tube_y -> "y"
  | Pdk.Ops.Tube_z -> "z"
  | Pdk.Ops.Tube_axis axis -> "axis:" ^ vec3_key axis

let tube_rotation_order_key = function
  | Pdk.Ops.Tube_xyz -> "xyz" | Pdk.Ops.Tube_xzy -> "xzy"
  | Pdk.Ops.Tube_yxz -> "yxz" | Pdk.Ops.Tube_yzx -> "yzx"
  | Pdk.Ops.Tube_zxy -> "zxy" | Pdk.Ops.Tube_zyx -> "zyx"

let tube ?label ?(connectivity = Pdk.Ops.Tube_quads) ?(end_caps = false)
    ?(consolidate_cap_points = true) ?normals
    ?(orientation = Pdk.Ops.Tube_y) ?(center = Vec3.zero)
    ?(rotation = Vec3.zero) ?(rotation_order = Pdk.Ops.Tube_xyz)
    ?(radius_scale = 1.) ?uv_attribute ?cap_group ?(rows = 2) ?(columns = 32)
    ~top_radius ~bottom_radius ~height () =
  let orientation = match orientation with
    | Pdk.Ops.Tube_axis axis -> Pdk.Ops.Tube_axis (vec3_copy axis)
    | value -> value in
  let center = vec3_copy center and rotation = vec3_copy rotation in
  let parameters = String.concat ";" [
      "connectivity=" ^ tube_connectivity_key connectivity;
      "end_caps=" ^ string_of_bool end_caps;
      "consolidate_cap_points=" ^ string_of_bool consolidate_cap_points;
      "normals=" ^ Option.fold ~none:"default" ~some:tube_normals_key normals;
      "orientation=" ^ tube_orientation_key orientation;
      "center=" ^ vec3_key center; "rotation=" ^ vec3_key rotation;
      "rotation_order=" ^ tube_rotation_order_key rotation_order;
      "radius_scale=" ^ float_key radius_scale;
      "uv=" ^ option_string_key uv_attribute;
      "cap_group=" ^ option_string_key cap_group;
      "rows=" ^ string_of_int rows; "columns=" ^ string_of_int columns;
      "top_radius=" ^ float_key top_radius;
      "bottom_radius=" ^ float_key bottom_radius;
      "height=" ^ float_key height ] in
  Node.Private.make ?label ~operation:"tube" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.tube ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~connectivity ~end_caps
          ~consolidate_cap_points ?normals ~orientation ~center ~rotation
          ~rotation_order ~radius_scale ?uv_attribute ?cap_group ~rows ~columns
          ~top_radius ~bottom_radius ~height () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let platonic_kind_key = function
  | Pdk.Ops.Platonic_tetrahedron -> "tetrahedron"
  | Pdk.Ops.Platonic_cube -> "cube"
  | Pdk.Ops.Platonic_octahedron -> "octahedron"
  | Pdk.Ops.Platonic_icosahedron -> "icosahedron"
  | Pdk.Ops.Platonic_dodecahedron -> "dodecahedron"
  | Pdk.Ops.Platonic_soccer_ball -> "soccer_ball"

let platonic_normals_key = function
  | Pdk.Ops.Platonic_no_normals -> "none"
  | Pdk.Ops.Platonic_point_normals -> "point"
  | Pdk.Ops.Platonic_vertex_normals -> "vertex"

let platonic_orientation_key = function
  | Pdk.Ops.Platonic_x -> "x" | Pdk.Ops.Platonic_y -> "y"
  | Pdk.Ops.Platonic_z -> "z"
  | Pdk.Ops.Platonic_axis axis -> "axis:" ^ vec3_key axis

let platonic_rotation_order_key = function
  | Pdk.Ops.Platonic_xyz -> "xyz" | Pdk.Ops.Platonic_xzy -> "xzy"
  | Pdk.Ops.Platonic_yxz -> "yxz" | Pdk.Ops.Platonic_yzx -> "yzx"
  | Pdk.Ops.Platonic_zxy -> "zxy" | Pdk.Ops.Platonic_zyx -> "zyx"

let platonic ?label ?(kind = Pdk.Ops.Platonic_tetrahedron)
    ?(normals = Pdk.Ops.Platonic_point_normals)
    ?(orientation = Pdk.Ops.Platonic_y) ?(center = Vec3.zero)
    ?(rotation = Vec3.zero) ?(rotation_order = Pdk.Ops.Platonic_xyz)
    ?face_groups ~radius () =
  let orientation = match orientation with
    | Pdk.Ops.Platonic_axis axis -> Pdk.Ops.Platonic_axis (vec3_copy axis)
    | value -> value in
  let center = vec3_copy center and rotation = vec3_copy rotation in
  let parameters = String.concat ";" [
      "kind=" ^ platonic_kind_key kind;
      "normals=" ^ platonic_normals_key normals;
      "orientation=" ^ platonic_orientation_key orientation;
      "center=" ^ vec3_key center; "rotation=" ^ vec3_key rotation;
      "rotation_order=" ^ platonic_rotation_order_key rotation_order;
      "face_groups=" ^ option_string_key face_groups;
      "radius=" ^ float_key radius ] in
  Node.Private.make ?label ~operation:"platonic" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.platonic ~cancel:(Context.cancel_token context) ~kind
          ~normals ~orientation ~center ~rotation ~rotation_order ?face_groups
          ~radius () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let spiral_extent_key = function
  | Pdk.Ops.Spiral_turns { turns; height } ->
      "turns:" ^ float_key turns ^ ":" ^ float_key height
  | Pdk.Ops.Spiral_height_pitch { height; pitch } ->
      "height_pitch:" ^ float_key height ^ ":" ^ float_key pitch

let spiral_radius_key = function
  | Pdk.Ops.Spiral_archimedean_change { start_radius; increase_per_turn } ->
      "archimedean_change:" ^ float_key start_radius ^ ":"
      ^ float_key increase_per_turn
  | Pdk.Ops.Spiral_archimedean_end { start_radius; end_radius } ->
      "archimedean_end:" ^ float_key start_radius ^ ":" ^ float_key end_radius
  | Pdk.Ops.Spiral_logarithmic_change { start_radius; scale_per_turn } ->
      "logarithmic_change:" ^ float_key start_radius ^ ":"
      ^ float_key scale_per_turn
  | Pdk.Ops.Spiral_logarithmic_end { start_radius; end_radius } ->
      "logarithmic_end:" ^ float_key start_radius ^ ":" ^ float_key end_radius

let spiral_direction_key = function
  | Pdk.Ops.Spiral_counterclockwise -> "counterclockwise"
  | Pdk.Ops.Spiral_clockwise -> "clockwise"

let spiral_divisions_key = function
  | Pdk.Ops.Spiral_divisions_per_curve count ->
      "per_curve:" ^ string_of_int count
  | Pdk.Ops.Spiral_divisions_per_turn count ->
      "per_turn:" ^ string_of_int count

let spiral_orientation_key = function
  | Pdk.Ops.Spiral_x -> "x" | Pdk.Ops.Spiral_y -> "y"
  | Pdk.Ops.Spiral_z -> "z"
  | Pdk.Ops.Spiral_axis axis -> "axis:" ^ vec3_key axis

let spiral_rotation_order_key = function
  | Pdk.Ops.Spiral_xyz -> "xyz" | Pdk.Ops.Spiral_xzy -> "xzy"
  | Pdk.Ops.Spiral_yxz -> "yxz" | Pdk.Ops.Spiral_yzx -> "yzx"
  | Pdk.Ops.Spiral_zxy -> "zxy" | Pdk.Ops.Spiral_zyx -> "zyx"

let spiral_ramp_key ramp = ramp |> List.map (fun (position, value) ->
    float_key position ^ ":" ^ float_key value) |> String.concat ","

let spiral ?label ?(extent = Pdk.Ops.Spiral_turns { turns = 3.; height = 2. })
    ?(radius = Pdk.Ops.Spiral_archimedean_change {
      start_radius = 1.; increase_per_turn = 0. })
    ?(height_ramp = []) ?(radius_scale = 1.) ?(radius_ramp = [])
    ?(direction = Pdk.Ops.Spiral_counterclockwise) ?(start_angle = 0.)
    ?(divisions = Pdk.Ops.Spiral_divisions_per_turn 32)
    ?(uniform_angle = true) ?(spiral_count = 1)
    ?(orientation = Pdk.Ops.Spiral_y) ?(center = Vec3.zero)
    ?(rotation = Vec3.zero) ?(rotation_order = Pdk.Ops.Spiral_xyz)
    ?(uniform_scale = 1.) ?angle_attribute ?x_axis_attribute ?y_axis_attribute
    ?tangent_attribute ?orient_attribute ?distance_attribute () =
  let orientation = match orientation with
    | Pdk.Ops.Spiral_axis axis -> Pdk.Ops.Spiral_axis (vec3_copy axis)
    | value -> value in
  let center = vec3_copy center and rotation = vec3_copy rotation
  and height_ramp = List.map (fun (position, value) -> position, value) height_ramp
  and radius_ramp = List.map (fun (position, value) -> position, value) radius_ramp in
  let parameters = String.concat ";" [
      "extent=" ^ spiral_extent_key extent;
      "radius=" ^ spiral_radius_key radius;
      "height_ramp=" ^ spiral_ramp_key height_ramp;
      "radius_scale=" ^ float_key radius_scale;
      "radius_ramp=" ^ spiral_ramp_key radius_ramp;
      "direction=" ^ spiral_direction_key direction;
      "start_angle=" ^ float_key start_angle;
      "divisions=" ^ spiral_divisions_key divisions;
      "uniform_angle=" ^ string_of_bool uniform_angle;
      "spiral_count=" ^ string_of_int spiral_count;
      "orientation=" ^ spiral_orientation_key orientation;
      "center=" ^ vec3_key center; "rotation=" ^ vec3_key rotation;
      "rotation_order=" ^ spiral_rotation_order_key rotation_order;
      "uniform_scale=" ^ float_key uniform_scale;
      "angle=" ^ option_string_key angle_attribute;
      "x_axis=" ^ option_string_key x_axis_attribute;
      "y_axis=" ^ option_string_key y_axis_attribute;
      "tangent=" ^ option_string_key tangent_attribute;
      "orient=" ^ option_string_key orient_attribute;
      "distance=" ^ option_string_key distance_attribute ] in
  Node.Private.make ?label ~operation:"spiral" ~version:1 ~parameters
    ~cook_mode:Node.Generator ~dependencies:Context.Dependencies.static
    ~inputs:[||] (fun ~node_id:_ context _inputs ->
      match Pdk.Ops.spiral ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~extent ~radius ~height_ramp
          ~radius_scale ~radius_ramp ~direction ~start_angle ~divisions
          ~uniform_angle ~spiral_count ~orientation ~center ~rotation
          ~rotation_order ~uniform_scale ?angle_attribute ?x_axis_attribute
          ?y_axis_attribute ?tangent_attribute ?orient_attribute
          ?distance_attribute () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let transform ?label ?selection ?(preserve_normal_length = false)
    ?(recompute_normals = false) matrix input =
  let matrix = matrix_copy matrix in
  Node.Private.make ?label ~operation:"transform" ~version:2
    ~parameters:(String.concat ";" ["matrix=" ^ matrix_key matrix;
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "preserve_normal_length=" ^ string_of_bool preserve_normal_length;
      "recompute_normals=" ^ string_of_bool recompute_normals])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"transform" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection -> match Pdk.Ops.transform_selected
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ?selection ~preserve_normal_length ~recompute_normals matrix inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_pdk_error error)

let transform_trs ?label ?order ?rotation_order ?translate ?rotate ?scale
    ?shear ?uniform_scale ?pivot ?pivot_rotation ?invert ?selection
    ?preserve_normal_length ?recompute_normals input =
  match Pdk.Ops.compose_transform ?order ?rotation_order ?translate ?rotate
      ?scale ?shear ?uniform_scale ?pivot ?pivot_rotation ?invert () with
  | Error error -> invalid_arg (Pdk.Error.to_string error)
  | Ok matrix -> transform ?label ?selection ?preserve_normal_length
      ?recompute_normals matrix input

let soft_transform_metric_key = function
  | Pdk.Ops.Soft_radius -> "radius"
  | Pdk.Ops.Soft_edge -> "edge"
  | Pdk.Ops.Soft_attribute { attribute; apply_rolloff } ->
      Printf.sprintf "attribute:%S:%b" attribute apply_rolloff

let soft_transform_falloff_key = function
  | Pdk.Ops.Soft_linear -> "linear"
  | Pdk.Ops.Soft_quadratic -> "quadratic"
  | Pdk.Ops.Soft_cubic -> "cubic"

let soft_transform ?label ?selection ?(metric = Pdk.Ops.Soft_radius)
    ?(falloff = Pdk.Ops.Soft_cubic) ?(radius = 1.) ?falloff_attribute
    ?(recompute_normals = true) matrix input =
  let matrix = matrix_copy matrix in
  Node.Private.make ?label ~operation:"soft_transform" ~version:1
    ~parameters:(String.concat ";" ["matrix=" ^ matrix_key matrix;
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "metric=" ^ soft_transform_metric_key metric;
      "falloff=" ^ soft_transform_falloff_key falloff;
      "radius=" ^ float_key radius;
      "falloff_attribute=" ^ option_string_key falloff_attribute;
      "recompute_normals=" ^ string_of_bool recompute_normals])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"soft_transform" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection -> match Pdk.Ops.soft_transform
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ?selection ~metric ~falloff ~radius ?falloff_attribute
          ~recompute_normals matrix inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_pdk_error error)

let soft_transform_trs ?label ?order ?rotation_order ?translate ?rotate ?scale
    ?shear ?uniform_scale ?pivot ?pivot_rotation ?invert ?selection ?metric
    ?falloff ?radius ?falloff_attribute ?recompute_normals input =
  match Pdk.Ops.compose_transform ?order ?rotation_order ?translate ?rotate
      ?scale ?shear ?uniform_scale ?pivot ?pivot_rotation ?invert () with
  | Error error -> invalid_arg (Pdk.Error.to_string error)
  | Ok matrix -> soft_transform ?label ?selection ?metric ?falloff ?radius
      ?falloff_attribute ?recompute_normals matrix input

let distance_along_radius_key = function
  | Pdk.Ops.Distance_fixed value -> "fixed:" ^ float_key value
  | Pdk.Ops.Distance_maximum -> "maximum"

let distance_along_geometry ?label ?affected
    ?(falloff = Pdk.Ops.Soft_linear) ?(radius = Pdk.Ops.Distance_maximum)
    ?(distance_attribute = Some "distance") ?mask_attribute ~start input =
  Node.Private.make ?label ~operation:"distance_along_geometry" ~version:1
    ~parameters:(String.concat ";" [
      "start=" ^ element_group_key start;
      "affected=" ^ (match affected with None -> "all"
        | Some selection -> element_group_key selection);
      "falloff=" ^ soft_transform_falloff_key falloff;
      "radius=" ^ distance_along_radius_key radius;
      "distance_attribute=" ^ option_string_key distance_attribute;
      "mask_attribute=" ^ option_string_key mask_attribute])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_element_group ~operation:"distance_along_geometry start"
          (Some start) geometry with
      | Error error -> Error error
      | Ok None -> assert false
      | Ok (Some start) ->
          (match resolve_element_group
              ~operation:"distance_along_geometry affected" affected geometry with
           | Error error -> Error error
           | Ok affected ->
               match Pdk.Ops.distance_along_geometry
                   ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ?affected ~falloff ~radius
                   ~distance_attribute ?mask_attribute ~start geometry with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let distance_from_geometry_reference_key = function
  | Pdk.Ops.Distance_reference_points -> "points"
  | Pdk.Ops.Distance_reference_primitives -> "primitives"

let distance_from_geometry ?label ?affected ?reference_selection
    ?(reference_kind = Pdk.Ops.Distance_reference_primitives)
    ?(falloff = Pdk.Ops.Soft_linear) ?(radius = Pdk.Ops.Distance_maximum)
    ?(distance_attribute = Some "distance") ?mask_attribute ~reference source =
  Node.Private.make ?label ~operation:"distance_from_geometry" ~version:1
    ~parameters:(String.concat ";" [
      "affected=" ^ (match affected with None -> "all"
        | Some selection -> element_group_key selection);
      "reference_selection=" ^ (match reference_selection with None -> "all"
        | Some selection -> element_group_key selection);
      "reference_kind=" ^ distance_from_geometry_reference_key reference_kind;
      "falloff=" ^ soft_transform_falloff_key falloff;
      "radius=" ^ distance_along_radius_key radius;
      "distance_attribute=" ^ option_string_key distance_attribute;
      "mask_attribute=" ^ option_string_key mask_attribute])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|source; reference|]
    (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"distance_from_geometry affected"
          affected inputs.(0) with
      | Error error -> Error error
      | Ok affected ->
          (match resolve_element_group
              ~operation:"distance_from_geometry reference"
              reference_selection inputs.(1) with
           | Error error -> Error error
           | Ok reference_selection ->
               match Pdk.Ops.distance_from_geometry
                   ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ?affected ?reference_selection
                   ~reference_kind ~falloff ~radius ~distance_attribute
                   ?mask_attribute ~reference:inputs.(1) inputs.(0) with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let distance_from_target_projection_key = function
  | Pdk.Ops.Distance_target_spherical -> "spherical"
  | Pdk.Ops.Distance_target_cylindrical -> "cylindrical"
  | Pdk.Ops.Distance_target_planar -> "planar"

let distance_from_target_metric_key = function
  | Pdk.Ops.Distance_target_absolute -> "absolute"
  | Pdk.Ops.Distance_target_signed -> "signed"

let distance_from_target ?label ?affected
    ?(projection = Pdk.Ops.Distance_target_spherical) ?(origin = Vec3.zero)
    ?(direction = Vec3.unit_y) ?(metric = Pdk.Ops.Distance_target_absolute)
    ?(falloff = Pdk.Ops.Soft_linear) ?(radius = Pdk.Ops.Distance_maximum)
    ?(distance_attribute = Some "distance") ?mask_attribute input =
  let origin = vec3_copy origin and direction = vec3_copy direction in
  Node.Private.make ?label ~operation:"distance_from_target" ~version:1
    ~parameters:(String.concat ";" [
      "affected=" ^ (match affected with None -> "all"
        | Some selection -> element_group_key selection);
      "projection=" ^ distance_from_target_projection_key projection;
      "origin=" ^ vec3_key origin;
      "direction=" ^ vec3_key direction;
      "metric=" ^ distance_from_target_metric_key metric;
      "falloff=" ^ soft_transform_falloff_key falloff;
      "radius=" ^ distance_along_radius_key radius;
      "distance_attribute=" ^ option_string_key distance_attribute;
      "mask_attribute=" ^ option_string_key mask_attribute])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"distance_from_target affected"
          affected inputs.(0) with
      | Error error -> Error error
      | Ok affected ->
          match Pdk.Ops.distance_from_target
              ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?affected ~projection ~origin
              ~direction ~metric ~falloff ~radius ~distance_attribute
              ?mask_attribute inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let merge ?label inputs =
  let inputs = Array.of_list inputs in
  Node.Private.make ?label ~operation:"merge" ~version:1
    ~parameters:(Printf.sprintf "inputs=%d" (Array.length inputs))
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      match Pdk.Ops.merge ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context)
          (Array.to_list inputs) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let resolve_optional_point_group operation name geometry = match name with
  | None -> Ok None
  | Some name ->
      (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
       | Some group -> Ok (Some group)
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find point group %S" operation name)))

let resolve_optional_primitive_group operation name geometry = match name with
  | None -> Ok None
  | Some name ->
      (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
       | Some group -> Ok (Some group)
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find primitive group %S" operation name)))

let resolve_optional_edge_group operation name geometry = match name with
  | None -> Ok None
  | Some name ->
      (match Pdk.Geometry.find_edge_group name geometry with
       | Some group -> Ok (Some group)
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find edge group %S" operation name)))

let fuse_position_key = function
  | Pdk.Ops.First_position -> "first"
  | Pdk.Ops.Least_point_position -> "least"
  | Pdk.Ops.Greatest_point_position -> "greatest"
  | Pdk.Ops.Average_position -> "average"
  | Pdk.Ops.Minimum_position -> "minimum"
  | Pdk.Ops.Maximum_position -> "maximum"
  | Pdk.Ops.Mode_position -> "mode"
  | Pdk.Ops.Median_position -> "median"
  | Pdk.Ops.Sum_position -> "sum"
  | Pdk.Ops.Sum_squares_position -> "sum_squares"
  | Pdk.Ops.Root_mean_square_position -> "root_mean_square"
  | Pdk.Ops.Weighted_average_position -> "weighted_average"
  | Pdk.Ops.Weighted_sum_position -> "weighted_sum"
  | Pdk.Ops.Minimum_weight_position -> "minimum_weight"
  | Pdk.Ops.Maximum_weight_position -> "maximum_weight"

let fuse_attribute_method_key = function
  | Pdk.Ops.Attribute_average -> "average"
  | Pdk.Ops.Attribute_least_point -> "least"
  | Pdk.Ops.Attribute_greatest_point -> "greatest"
  | Pdk.Ops.Attribute_maximum -> "maximum"
  | Pdk.Ops.Attribute_minimum -> "minimum"
  | Pdk.Ops.Attribute_mode -> "mode"
  | Pdk.Ops.Attribute_median -> "median"
  | Pdk.Ops.Attribute_sum -> "sum"
  | Pdk.Ops.Attribute_sum_squares -> "sum_squares"
  | Pdk.Ops.Attribute_root_mean_square -> "root_mean_square"
  | Pdk.Ops.Attribute_concatenate -> "concatenate"
  | Pdk.Ops.Attribute_weighted_average -> "weighted_average"
  | Pdk.Ops.Attribute_weighted_sum -> "weighted_sum"
  | Pdk.Ops.Attribute_minimum_weight -> "minimum_weight"
  | Pdk.Ops.Attribute_maximum_weight -> "maximum_weight"
  | Pdk.Ops.Attribute_concatenate_weight_order -> "concatenate_weight_order"

let fuse_attribute_rules_key rules = rules |> List.map
    (fun (rule : Pdk.Ops.fuse_attribute_rule) ->
    String.concat "," [String.escaped rule.Pdk.Ops.pattern;
      fuse_attribute_method_key rule.method_;
      option_string_key rule.weight_attribute]) |> String.concat "|"

let fuse_group_method_key = function
  | Pdk.Ops.Group_least_point -> "least"
  | Pdk.Ops.Group_greatest_point -> "greatest"
  | Pdk.Ops.Group_union -> "union"
  | Pdk.Ops.Group_intersection -> "intersection"
  | Pdk.Ops.Group_most_common -> "most_common"

let fuse_group_rules_key rules = rules |> List.map
    (fun (rule : Pdk.Ops.fuse_group_rule) ->
    String.escaped rule.Pdk.Ops.group_pattern ^ ","
      ^ fuse_group_method_key rule.group_method) |> String.concat "|"

let fuse ?label ?group ?target_group ?(targeting = Pdk.Ops.Near_points)
    ?(using = Pdk.Ops.Least_target_point) ?(tolerance = 1e-6)
    ?(position = Pdk.Ops.Average_position)
    ?weight_attribute ?(attributes = Pdk.Ops.Keep_first)
    ?(attribute_rules = []) ?(group_rules = []) ?(metric = Pdk.Ops.Euclidean)
    ?(inclusive = true) ?(match_attributes = false) ?radius_attribute
    ?match_attribute ?(match_condition = Pdk.Ops.Equal_attribute_values)
    ?(match_tolerance = 0.) ?(modify_target = false)
    ?(fuse_points = true) ?(keep_fused_points = false) ?snapped_group
    ?snapped_destination_attribute ?(remove_degenerate_primitives = false)
    ?(remove_unused_points_from_degenerate_primitives = false)
    ?(remove_all_unused_points = false) ?target input =
  List.iter (fun (kind, name) -> Option.iter (fun name ->
      if String.trim name = "" then
        invalid_arg ("Sop.fuse: empty " ^ kind)) name)
    ["point group name", group; "target point group name", target_group;
     "radius attribute name", radius_attribute;
     "match attribute name", match_attribute;
     "position weight attribute name", weight_attribute;
     "snapped group name", snapped_group;
     "snapped destination attribute name", snapped_destination_attribute];
  let position_key = fuse_position_key position in
  let attributes_key = match attributes with
    | Pdk.Ops.Keep_first -> "first"
    | Pdk.Ops.Average_numeric -> "average_numeric" in
  let metric_key = match metric with
    | Pdk.Ops.Euclidean -> "euclidean"
    | Pdk.Ops.Componentwise -> "componentwise" in
  let targeting_key = match targeting with
    | Pdk.Ops.Near_points -> "near"
    | Pdk.Ops.Specified_points name -> "specified:" ^ name in
  let using_key = match using with
    | Pdk.Ops.Least_target_point -> "least"
    | Pdk.Ops.Closest_target_point -> "closest" in
  let match_condition_key = match match_condition with
    | Pdk.Ops.Equal_attribute_values -> "equal"
    | Pdk.Ops.Unequal_attribute_values -> "unequal" in
  let inputs = match target with None -> [|input|] | Some node -> [|input;node|] in
  Node.Private.make ?label ~operation:"fuse" ~version:6
    ~parameters:(Printf.sprintf
      "group=%s;target_group=%s;targeting=%s;using=%s;tolerance=%s;position=%s;weight_attribute=%s;attributes=%s;attribute_rules=%s;group_rules=%s;metric=%s;inclusive=%b;match_attributes=%b;radius_attribute=%s;match_attribute=%s;match_condition=%s;match_tolerance=%s;modify_target=%b;fuse_points=%b;keep_fused_points=%b;snapped_group=%s;snapped_destination_attribute=%s;remove_degenerate_primitives=%b;remove_unused_points_from_degenerate_primitives=%b;remove_all_unused_points=%b;target=%b"
      (option_string_key group) (option_string_key target_group) targeting_key
      using_key (float_key tolerance) position_key
      (option_string_key weight_attribute) attributes_key
      (fuse_attribute_rules_key attribute_rules)
      (fuse_group_rules_key group_rules) metric_key
      inclusive match_attributes (option_string_key radius_attribute)
      (option_string_key match_attribute) match_condition_key
      (float_key match_tolerance) modify_target fuse_points keep_fused_points
      (option_string_key snapped_group)
      (option_string_key snapped_destination_attribute)
      remove_degenerate_primitives
      remove_unused_points_from_degenerate_primitives remove_all_unused_points
      (Option.is_some target))
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      match resolve_optional_point_group "fuse" group inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          let target_geometry = if Array.length inputs = 2
              then inputs.(1) else inputs.(0) in
          (match resolve_optional_point_group "fuse target" target_group
              target_geometry with
           | Error error -> Error error
           | Ok target_selection ->
              let target = if Array.length inputs = 2
                  then Some target_geometry else None in
              (match Pdk.Ops.fuse ~cancel:(Context.cancel_token context)
                  ~grain:(Context.grain context) ?selection ?target_selection
                  ~targeting ~using ~tolerance ~position ?weight_attribute
                  ~attributes ~attribute_rules ~group_rules ~metric
                  ~inclusive ~match_attributes ?radius_attribute
                  ?match_attribute ~match_condition ~match_tolerance
                  ~modify_target ~fuse_points ~keep_fused_points
                  ?snapped_group ?snapped_destination_attribute
                  ~remove_degenerate_primitives
                  ~remove_unused_points_from_degenerate_primitives
                  ~remove_all_unused_points
                  ?target inputs.(0) with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error)))

let snap_to_grid ?label ?group ?(spacing = Vec3.create 1. 1. 1.)
    ?(offset = Vec3.zero) ?(rounding = Pdk.Ops.Grid_nearest) ?max_distance
    ?(fuse_points = false) ?(position = Pdk.Ops.Average_position)
    ?weight_attribute ?(attributes = Pdk.Ops.Keep_first)
    ?(attribute_rules = []) ?(group_rules = []) ?snapped_group input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.snap_to_grid: empty point group name") group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.snap_to_grid: empty snapped group name") snapped_group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.snap_to_grid: empty position weight attribute name")
    weight_attribute;
  let spacing = vec3_copy spacing and offset = vec3_copy offset in
  let rounding_key = match rounding with
    | Pdk.Ops.Grid_nearest -> "nearest"
    | Pdk.Ops.Grid_down -> "down"
    | Pdk.Ops.Grid_up -> "up" in
  let position_key = fuse_position_key position in
  let attributes_key = match attributes with
    | Pdk.Ops.Keep_first -> "first"
    | Pdk.Ops.Average_numeric -> "average_numeric" in
  let max_distance_key = match max_distance with
    | None -> "none"
    | Some value -> float_key value in
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "spacing=" ^ vec3_key spacing; "offset=" ^ vec3_key offset;
      "rounding=" ^ rounding_key; "max_distance=" ^ max_distance_key;
      "fuse_points=" ^ string_of_bool fuse_points;
      "position=" ^ position_key;
      "weight_attribute=" ^ option_string_key weight_attribute;
      "attributes=" ^ attributes_key;
      "attribute_rules=" ^ fuse_attribute_rules_key attribute_rules;
      "group_rules=" ^ fuse_group_rules_key group_rules;
      "snapped_group=" ^ option_string_key snapped_group ] in
  Node.Private.make ?label ~operation:"snap_to_grid" ~version:3 ~parameters
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match resolve_optional_point_group "snap_to_grid" group inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          (match Pdk.Ops.snap_to_grid ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~spacing ~offset ~rounding
              ?max_distance ~fuse_points ~position ?weight_attribute ~attributes
              ~attribute_rules ~group_rules ?snapped_group
              inputs.(0) with
           | Ok geometry -> cooked geometry
           | Error error -> structured_pdk_error error))

let mirror ?label ?(keep_original = true) ~origin ~normal input =
  let origin = vec3_copy origin and normal = vec3_copy normal in
  Node.Private.make ?label ~operation:"mirror" ~version:1
    ~parameters:(Printf.sprintf "origin=%s;normal=%s;keep_original=%b"
      (vec3_key origin) (vec3_key normal) keep_original)
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Ops.mirror ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~keep_original ~origin ~normal inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let clip_keep_key = function
  | Pdk.Ops.Above -> "above"
  | Pdk.Ops.Below -> "below"
  | Pdk.Ops.All -> "all"

let clip ?label ?(keep = Pdk.Ops.Above) ?(snapping_tolerance = 1e-9)
    ?(fill = false) ?(split_connectivity = false) ?(clip_attribute = "P")
    ?(distance = 0.) ?selection ?(replace_existing_groups = true)
    ?clipped_edge_group ?cap_group ?clipped_group ?above_group ?below_group
    ~origin ~normal input =
  let origin = vec3_copy origin and normal = vec3_copy normal in
  Node.Private.make ?label ~operation:"clip" ~version:5
    ~parameters:(String.concat ";" [
      "keep=" ^ clip_keep_key keep;
      "snapping_tolerance=" ^ float_key snapping_tolerance;
      "fill=" ^ string_of_bool fill;
      "split_connectivity=" ^ string_of_bool split_connectivity;
      "clip_attribute=" ^ String.escaped clip_attribute;
      "distance=" ^ float_key distance;
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "replace_existing_groups=" ^ string_of_bool replace_existing_groups;
      "origin=" ^ vec3_key origin; "normal=" ^ vec3_key normal;
      "clipped_edge_group=" ^ option_string_key clipped_edge_group;
      "cap_group=" ^ option_string_key cap_group;
      "clipped_group=" ^ option_string_key clipped_group;
      "above_group=" ^ option_string_key above_group;
      "below_group=" ^ option_string_key below_group;
    ]) ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"clip" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection -> match Pdk.Ops.clip ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~keep ~snapping_tolerance ~fill
          ~split_connectivity ~clip_attribute ~distance ?selection
          ~replace_existing_groups
          ?clipped_edge_group
          ?cap_group ?clipped_group ?above_group ?below_group ~origin ~normal
          inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let clip_transform ?label ?keep ?snapping_tolerance ?fill ?split_connectivity
    ?clip_attribute ?distance ?selection ?replace_existing_groups
    ?clipped_edge_group ?cap_group ?clipped_group ?above_group ?below_group
    ?(local_normal = Vec3.unit_y) ~transform input =
  let origin = Mat4.transform_point transform Vec3.zero
  and normal = Mat4.transform_direction transform local_normal in
  clip ?label ?keep ?snapping_tolerance ?fill ?split_connectivity
    ?clip_attribute ?distance ?selection ?replace_existing_groups
    ?clipped_edge_group ?cap_group ?clipped_group ?above_group ?below_group
    ~origin ~normal input

let crease_operation_key = function
  | Pdk.Ops.Crease_add -> "add"
  | Pdk.Ops.Crease_set -> "set"
  | Pdk.Ops.Crease_delete -> "delete"

let crease ?label ?group ?(operation = Pdk.Ops.Crease_add) ?(weight = 1.)
    ?(add_vertex_color = false) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.crease: empty edge group name") group;
  let weight_key = match operation with
    | Pdk.Ops.Crease_delete -> "ignored"
    | Pdk.Ops.Crease_add | Pdk.Ops.Crease_set -> float_key weight in
  Node.Private.make ?label ~operation:"crease" ~version:1
    ~parameters:(Printf.sprintf
      "group=%s;operation=%s;weight=%s;add_vertex_color=%b"
      (option_string_key group) (crease_operation_key operation) weight_key
      add_vertex_color)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "crease could not find native edge group %S" name))) in
      Result.bind edges (fun edges ->
        match Pdk.Ops.crease ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?edges ~operation ~weight
            ~add_vertex_color geometry with
        | Ok geometry -> cooked geometry
        | Error error -> structured_pdk_error error))

let attribute_fade_ramp_key ramp = ramp |> List.map (fun (position, value) ->
    float_key position ^ ":" ^ float_key value) |> String.concat ","

let attribute_fade ?label ?group ?start_source ?hold_source
    ?(fade_attribute = "fade") ?start_attribute
    ?(start_retime = (0., 1.)) ?hold_scale_attribute ?(frame_offset = 0.)
    ?(fade_in = 2.) ?(fade_hold = 0.) ?(fade_out = 2.)
    ?(fade_in_ramp = [0., 0.; 1., 1.])
    ?(fade_out_ramp = [0., 1.; 1., 0.]) ?(visualize = false) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.attribute_fade: empty point group name") group;
  List.iter (fun (label, name) -> Option.iter (fun name ->
    if String.trim name = "" then
      invalid_arg ("Sop.attribute_fade: empty " ^ label ^ " attribute name")) name)
    ["start", start_attribute; "hold-scale", hold_scale_attribute];
  let fade_in_ramp = List.map (fun (position, value) -> position, value) fade_in_ramp
  and fade_out_ramp = List.map (fun (position, value) -> position, value) fade_out_ramp in
  let inputs, start_index, hold_index = match start_source, hold_source with
    | None, None -> [|input|], None, None
    | Some start, None -> [|input; start|], Some 1, None
    | None, Some hold -> [|input; hold|], None, Some 1
    | Some start, Some hold -> [|input; start; hold|], Some 1, Some 2 in
  let start_offset, start_scale = start_retime in
  Node.Private.make ?label ~operation:"attribute_fade" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "start_source=" ^ string_of_bool (Option.is_some start_source);
      "hold_source=" ^ string_of_bool (Option.is_some hold_source);
      "fade_attribute=" ^ String.escaped fade_attribute;
      "start_attribute=" ^ option_string_key start_attribute;
      "start_retime=" ^ float_key start_offset ^ "," ^ float_key start_scale;
      "hold_scale_attribute=" ^ option_string_key hold_scale_attribute;
      "frame_offset=" ^ float_key frame_offset;
      "fade_in=" ^ float_key fade_in;
      "fade_hold=" ^ float_key fade_hold;
      "fade_out=" ^ float_key fade_out;
      "fade_in_ramp=" ^ attribute_fade_ramp_key fade_in_ramp;
      "fade_out_ramp=" ^ attribute_fade_ramp_key fade_out_ramp;
      "visualize=" ^ string_of_bool visualize])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:(Context.Dependencies.one Context.Dependencies.Frame)
    ~inputs (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_optional_point_group "attribute_fade" group geometry with
      | Error error -> Error error
      | Ok points ->
          let start_source = Option.map (Array.unsafe_get inputs) start_index
          and hold_source = Option.map (Array.unsafe_get inputs) hold_index in
          match Pdk.Ops.attribute_fade ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?points ?start_source ?hold_source
              ~fade_attribute ?start_attribute ~start_retime
              ?hold_scale_attribute ~frame:(Int64.to_float (Context.frame context))
              ~frame_offset ~fade_in ~fade_hold ~fade_out ~fade_in_ramp
              ~fade_out_ramp ~visualize geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let poly_cut_element_key = function
  | Pdk.Ops.Poly_cut_points -> "points"
  | Pdk.Ops.Poly_cut_edges -> "edges"

let poly_cut_strategy_key = function
  | Pdk.Ops.Poly_cut_remove -> "remove"
  | Pdk.Ops.Poly_cut_cut -> "cut"

let poly_cut_detection_key = function
  | Pdk.Ops.Poly_cut_all -> "all"
  | Pdk.Ops.Poly_cut_crossing {attribute; value} ->
      "crossing:" ^ String.escaped attribute ^ ":" ^ float_key value
  | Pdk.Ops.Poly_cut_change {attribute; threshold} ->
      "change:" ^ String.escaped attribute ^ ":" ^ float_key threshold

let poly_cut ?label ?group ?cut_group ?(element = Pdk.Ops.Poly_cut_points)
    ?(strategy = Pdk.Ops.Poly_cut_remove)
    ?(detection = Pdk.Ops.Poly_cut_all) ?(keep_closed = true) input =
  List.iter (fun (label, name) -> Option.iter (fun name ->
    if String.trim name = "" then
      invalid_arg ("Sop.poly_cut: empty " ^ label ^ " group name")) name)
    ["primitive", group; "cut", cut_group];
  Node.Private.make ?label ~operation:"poly_cut" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "cut_group=" ^ option_string_key cut_group;
      "element=" ^ poly_cut_element_key element;
      "strategy=" ^ poly_cut_strategy_key strategy;
      "detection=" ^ poly_cut_detection_key detection;
      "keep_closed=" ^ string_of_bool keep_closed])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_optional_primitive_group "poly_cut" group geometry with
      | Error error -> Error error
      | Ok primitives ->
          let cut_selection = match element with
            | Pdk.Ops.Poly_cut_points ->
                Result.map (fun value -> `Points value)
                  (resolve_optional_point_group "poly_cut" cut_group geometry)
            | Pdk.Ops.Poly_cut_edges ->
                Result.map (fun value -> `Edges value)
                  (resolve_optional_edge_group "poly_cut" cut_group geometry) in
          match cut_selection with
          | Error error -> Error error
          | Ok (`Points cut_points) ->
              (match Pdk.Ops.poly_cut ~cancel:(Context.cancel_token context)
                  ~grain:(Context.grain context) ?primitives ?cut_points
                  ~element ~strategy ~detection ~keep_closed geometry with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error)
          | Ok (`Edges cut_edges) ->
              (match Pdk.Ops.poly_cut ~cancel:(Context.cancel_token context)
                  ~grain:(Context.grain context) ?primitives ?cut_edges
                  ~element ~strategy ~detection ~keep_closed geometry with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let separate_pieces_mode_key = function
  | Pdk.Ops.Separate_pieces_separate -> "separate"
  | Pdk.Ops.Separate_pieces_move_back -> "move_back"

let separate_pieces_owner_key = function
  | Pdk.Attribute.Point -> "point"
  | Pdk.Attribute.Primitive -> "primitive"
  | Pdk.Attribute.Vertex -> "vertex"
  | Pdk.Attribute.Detail -> "detail"

let separate_pieces ?label ?(owner = Pdk.Attribute.Primitive)
    ?(translation_attribute = "piece_translation") ?(axis = Vec3.unit_x)
    ?(gap = 0.001) ?(mode = Pdk.Ops.Separate_pieces_separate)
    ~piece_attribute input =
  if String.trim piece_attribute = "" then
    invalid_arg "Sop.separate_pieces: empty piece attribute name";
  if String.trim translation_attribute = "" then
    invalid_arg "Sop.separate_pieces: empty translation attribute name";
  let axis = vec3_copy axis in
  Node.Private.make ?label ~operation:"separate_pieces" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ separate_pieces_owner_key owner;
      "piece_attribute=" ^ String.escaped piece_attribute;
      "translation_attribute=" ^ String.escaped translation_attribute;
      "axis=" ^ vec3_key axis;
      "gap=" ^ float_key gap;
      "mode=" ^ separate_pieces_mode_key mode])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Ops.separate_pieces ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~owner ~translation_attribute ~axis
          ~gap ~mode ~piece_attribute inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let subdivision_scheme_key = function
  | Pdk.Ops.Catmull_clark -> "catmull_clark"
  | Pdk.Ops.Loop -> "loop"
  | Pdk.Ops.Bilinear -> "bilinear"

let subdivision_boundary_key = function
  | Pdk.Ops.Subdivide_boundary_none -> "none"
  | Pdk.Ops.Subdivide_boundary_edge_only -> "edge_only"
  | Pdk.Ops.Subdivide_boundary_edge_and_corner -> "edge_and_corner"

let subdivision_fvar_key = function
  | Pdk.Ops.Subdivide_fvar_none -> "none"
  | Pdk.Ops.Subdivide_fvar_corners_only -> "corners_only"
  | Pdk.Ops.Subdivide_fvar_corners_plus1 -> "corners_plus1"
  | Pdk.Ops.Subdivide_fvar_corners_plus2 -> "corners_plus2"
  | Pdk.Ops.Subdivide_fvar_boundaries -> "boundaries"
  | Pdk.Ops.Subdivide_fvar_all -> "all"

let subdivision_triangle_key = function
  | Pdk.Ops.Subdivide_triangles_catmull_clark -> "catmull_clark"
  | Pdk.Ops.Subdivide_triangles_smooth -> "smooth"

let subdivision_creasing_key = function
  | Pdk.Ops.Subdivide_creasing_uniform -> "uniform"
  | Pdk.Ops.Subdivide_creasing_chaikin -> "chaikin"

let subdivision_cracks_key = function
  | Pdk.Ops.Subdivide_do_not_close -> "do_not_close"
  | Pdk.Ops.Subdivide_pull_no_edge_division -> "pull_no_edge_division"
  | Pdk.Ops.Subdivide_pull_divide_edges bias ->
      "pull_divide_edges:" ^ float_key bias
  | Pdk.Ops.Subdivide_pull_triangulate bias ->
      "pull_triangulate:" ^ float_key bias
  | Pdk.Ops.Subdivide_stitch_no_edge_division -> "stitch_no_edge_division"
  | Pdk.Ops.Subdivide_stitch_divide_edges -> "stitch_divide_edges"
  | Pdk.Ops.Subdivide_stitch_triangulate -> "stitch_triangulate"

let subdivide ?label ?group ?(scheme = Pdk.Ops.Catmull_clark)
    ?(iterations = 1) ?(cracks = Pdk.Ops.Subdivide_do_not_close)
    ?(consistent_topology = false) ?creases ?crease_group ?crease_weight
    ?(generate_resulting_creases = true) ?resulting_crease_group
    ?hole_group ?(remove_holes = true)
    ?(boundary_interpolation = Pdk.Ops.Subdivide_boundary_edge_only)
    ?(face_varying_interpolation = Pdk.Ops.Subdivide_fvar_all)
    ?(triangle_policy = Pdk.Ops.Subdivide_triangles_catmull_clark)
    ?(creasing_method = Pdk.Ops.Subdivide_creasing_uniform)
    ?(treat_curves_as_independent = false)
    ?(recompute_point_normals = false) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.subdivide: empty primitive group name") group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.subdivide: empty crease group name") crease_group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.subdivide: empty resulting crease group name")
    resulting_crease_group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.subdivide: empty hole group name") hole_group;
  if creases = None && crease_group <> None then
    invalid_arg "Sop.subdivide: crease_group requires creases";
  if not generate_resulting_creases && resulting_crease_group <> None then
    invalid_arg "Sop.subdivide: resulting_crease_group requires generated creases";
  let inputs = match creases with None -> [|input|] | Some creases -> [|input; creases|] in
  Node.Private.make ?label ~operation:"subdivide" ~version:13
    ~parameters:(Printf.sprintf
      "group=%s;scheme=%s;iterations=%d;cracks=%s;consistent_topology=%b;creases=%b;crease_group=%s;crease_weight=%s;generate_resulting_creases=%b;resulting_crease_group=%s;hole_group=%s;remove_holes=%b;boundary_interpolation=%s;face_varying_interpolation=%s;triangle_policy=%s;creasing_method=%s;treat_curves_as_independent=%b;recompute_point_normals=%b"
      (option_string_key group) (subdivision_scheme_key scheme) iterations
      (subdivision_cracks_key cracks) consistent_topology (Option.is_some creases)
      (option_string_key crease_group)
      (match crease_weight with None -> "attribute" | Some value -> float_key value)
      generate_resulting_creases (option_string_key resulting_crease_group)
      (option_string_key hole_group) remove_holes
      (subdivision_boundary_key boundary_interpolation)
      (subdivision_fvar_key face_varying_interpolation)
      (subdivision_triangle_key triangle_policy)
      (subdivision_creasing_key creasing_method)
      treat_curves_as_independent recompute_point_normals)
    ~cook_mode:(match creases with None -> Node.Duplicate_input 0 | Some _ -> Node.Generic)
    ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let selection = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "subdivide could not find primitive group %S" name))) in
      let crease_selection = match creases, crease_group with
        | None, _ | Some _, None -> Ok None
        | Some _, Some name ->
            let creases = inputs.(1) in
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name creases with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "subdivide could not find crease primitive group %S" name))) in
      let hole_selection = match hole_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "subdivide could not find hole primitive group %S"
                   name))) in
      match selection, crease_selection, hole_selection with
      | Error error, _, _ -> Error error
      | _, Error error, _ -> Error error
      | _, _, Error error -> Error error
      | Ok primitives, Ok crease_primitives, Ok hole_primitives ->
          match Pdk.Ops.subdivide ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~scheme ~iterations ?primitives
              ~cracks ~consistent_topology
              ?creases:(Option.map (fun _ -> inputs.(1)) creases)
              ?crease_primitives ?crease_weight ~generate_resulting_creases
              ?resulting_crease_group ?hole_primitives ~remove_holes
              ~boundary_interpolation ~face_varying_interpolation
              ~triangle_policy ~creasing_method ~treat_curves_as_independent
              ~recompute_point_normals
              geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_divide ?label ?group ?(divisions = 2) ?(share_points = true) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_divide: empty edge group name") group;
  if divisions <= 0 then
    invalid_arg "Sop.edge_divide: divisions must be positive";
  Node.Private.make ?label ~operation:"edge_divide" ~version:1
    ~parameters:(Printf.sprintf "group=%s;divisions=%d;share_points=%b"
      (option_string_key group) divisions share_points)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "edge_divide could not find native edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.edge_divide ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ~divisions ~share_points
              inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_collapse ?label ?group ?connectivity_attribute
    ?(position = Pdk.Ops.Average_position)
    ?(remove_degenerate_primitives = true)
    ?(recompute_point_normals = true) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_collapse: empty edge group name") group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_collapse: empty connectivity attribute name")
    connectivity_attribute;
  Node.Private.make ?label ~operation:"edge_collapse" ~version:1
    ~parameters:(Printf.sprintf
      "group=%s;connectivity_attribute=%s;position=%s;remove_degenerate_primitives=%b;recompute_point_normals=%b"
      (option_string_key group) (option_string_key connectivity_attribute)
      (fuse_position_key position)
      remove_degenerate_primitives recompute_point_normals)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some edges -> Ok (Some edges)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "edge_collapse could not find native edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.edge_collapse ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ?connectivity_attribute
              ~position
              ~remove_degenerate_primitives ~recompute_point_normals geometry with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let dissolve_operation_key = function
  | Pdk.Ops.Dissolve_selected -> "selected"
  | Pdk.Ops.Dissolve_non_selected -> "non_selected"

let dissolve_bridge_policy_key = function
  | Pdk.Ops.Create_bridged_polygons -> "bridged"
  | Pdk.Ops.Create_disjoint_polygons -> "disjoint"
  | Pdk.Ops.Delete_bridge_polygons -> "delete"

let dissolve ?label ?group ?(operation = Pdk.Ops.Dissolve_selected)
    ?(bridge_policy = Pdk.Ops.Create_bridged_polygons)
    ?(remove_inline_points = false) ?(collinearity_tolerance = 0.)
    ?(remove_unused_points = true) ?(create_boundary_curves = false)
    ?(recompute_normals = true) input =
  Node.Private.make ?label ~operation:"dissolve" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "operation=" ^ dissolve_operation_key operation;
      "bridge=" ^ dissolve_bridge_policy_key bridge_policy;
      "remove_inline=" ^ string_of_bool remove_inline_points;
      "collinearity=" ^ float_key collinearity_tolerance;
      "remove_unused=" ^ string_of_bool remove_unused_points;
      "boundary_curves=" ^ string_of_bool create_boundary_curves;
      "normals=" ^ string_of_bool recompute_normals])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name inputs.(0) with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_edge_group"
                 (Printf.sprintf "dissolve could not find edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.dissolve ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ~operation ~bridge_policy
              ~remove_inline_points ~collinearity_tolerance
              ~remove_unused_points ~create_boundary_curves ~recompute_normals
              inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let poly_bevel_shape_key = function
  | Pdk.Ops.Bevel_chamfer -> "chamfer"
  | Pdk.Ops.Bevel_round { convexity } -> "round:" ^ float_key convexity

let poly_bevel ?label ?group ?(shape = Pdk.Ops.Bevel_chamfer)
    ?(divisions = 1) ?point_scale_attribute ?ignore_flat_angle
    ?(clamp_overlap = true) ?edge_group ?corner_group ?offset_group
    ?(recompute_point_normals = true) ~distance input =
  List.iter (fun (kind, value) -> Option.iter (fun name ->
    if String.trim name = "" then invalid_arg
      (Printf.sprintf "Sop.poly_bevel: empty %s name" kind)) value)
    ["edge selection group", group;
     "point scale attribute", point_scale_attribute;
     "edge fillet group", edge_group;
     "corner fillet group", corner_group;
     "offset edge group", offset_group];
  if divisions <= 0 then
    invalid_arg "Sop.poly_bevel: divisions must be positive";
  Node.Private.make ?label ~operation:"poly_bevel" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "shape=" ^ poly_bevel_shape_key shape;
      "divisions=" ^ string_of_int divisions;
      "point_scale=" ^ option_string_key point_scale_attribute;
      "ignore_flat=" ^ option_float_key ignore_flat_angle;
      "clamp=" ^ string_of_bool clamp_overlap;
      "edge_group=" ^ option_string_key edge_group;
      "corner_group=" ^ option_string_key corner_group;
      "offset_group=" ^ option_string_key offset_group;
      "normals=" ^ string_of_bool recompute_point_normals;
      "distance=" ^ float_key distance])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_edge_group"
                 (Printf.sprintf "poly_bevel could not find edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.poly_bevel ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ~shape ~divisions
              ?point_scale_attribute ?ignore_flat_angle ~clamp_overlap
              ?edge_group ?corner_group ?offset_group ~recompute_point_normals
              ~distance geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let point_split ?label ?selection ?(attributes = "") ?(tolerance = 1e-5)
    ?(promote_attributes = false) input =
  (match selection with Some (Edge_group _) -> invalid_arg
      "Sop.point_split: selection must own points, vertices, or primitives"
   | None | Some (Point_group _ | Vertex_group _ | Primitive_group _) -> ());
  Node.Private.make ?label ~operation:"point_split" ~version:2
    ~parameters:(String.concat ";" [
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "attributes=" ^ String.escaped attributes;
      "tolerance=" ^ float_key tolerance;
      "promote=" ^ string_of_bool promote_attributes])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"point_split" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection -> match Pdk.Ops.point_split
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ?selection ~attributes ~tolerance ~promote_attributes inputs.(0) with
        | Ok geometry -> cooked geometry
        | Error error -> structured_pdk_error error)

let poly_loft_minimize_key = function
  | Pdk.Ops.Two_point_distance -> "two_point"
  | Pdk.Ops.Three_point_distance -> "three_point"

let poly_loft ?label ?group ?rest ?(connect_closest_ends = true)
    ?(minimize = Pdk.Ops.Two_point_distance) ?(u_wrap = false)
    ?(v_wrap = false) ?(keep_primitives = false) ?output_group
    ?(collinearity_tolerance = 0.) ?(recompute_normals = true) input =
  let inputs = match rest with None -> [|input|] | Some rest -> [|input; rest|] in
  Node.Private.make ?label ~operation:"poly_loft" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "rest=" ^ string_of_bool (Option.is_some rest);
      "closest=" ^ string_of_bool connect_closest_ends;
      "minimize=" ^ poly_loft_minimize_key minimize;
      "u_wrap=" ^ string_of_bool u_wrap;
      "v_wrap=" ^ string_of_bool v_wrap;
      "keep=" ^ string_of_bool keep_primitives;
      "output_group=" ^ option_string_key output_group;
      "collinearity=" ^ float_key collinearity_tolerance;
      "normals=" ^ string_of_bool recompute_normals])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "poly_loft could not find primitive group %S" name))) in
      match primitives with
      | Error error -> Error error
      | Ok primitives ->
          let rest = if Array.length inputs = 2 then Some inputs.(1) else None in
          match Pdk.Ops.poly_loft ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ?rest
              ~connect_closest_ends ~minimize ~u_wrap ~v_wrap ~keep_primitives
              ?output_group ~collinearity_tolerance ~recompute_normals geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let skin ?label ?group ?rest ?(connect_closest_ends = true)
    ?(minimize = Pdk.Ops.Two_point_distance) ?(u_wrap = false)
    ?(v_wrap = false) ?(keep_primitives = false) ?output_group
    ?(collinearity_tolerance = 0.) ?(recompute_normals = true) input =
  let inputs = match rest with None -> [|input|] | Some rest -> [|input; rest|] in
  Node.Private.make ?label ~operation:"skin" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "rest=" ^ string_of_bool (Option.is_some rest);
      "closest=" ^ string_of_bool connect_closest_ends;
      "minimize=" ^ poly_loft_minimize_key minimize;
      "u_wrap=" ^ string_of_bool u_wrap;
      "v_wrap=" ^ string_of_bool v_wrap;
      "keep=" ^ string_of_bool keep_primitives;
      "output_group=" ^ option_string_key output_group;
      "collinearity=" ^ float_key collinearity_tolerance;
      "normals=" ^ string_of_bool recompute_normals])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "skin could not find primitive group %S" name))) in
      match primitives with
      | Error error -> Error error
      | Ok primitives ->
          let rest = if Array.length inputs = 2 then Some inputs.(1) else None in
          match Pdk.Ops.skin ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ?rest
              ~connect_closest_ends ~minimize ~u_wrap ~v_wrap ~keep_primitives
              ?output_group ~collinearity_tolerance ~recompute_normals geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let poly_bridge_pairing_key = function
  | Pdk.Ops.Bridge_by_order -> "order"
  | Pdk.Ops.Bridge_by_centroid -> "centroid"

let poly_bridge ?label ~source_group ~destination_group
    ?(pairing = Pdk.Ops.Bridge_by_order) ?(connect_closest_ends = true)
    ?(minimize = Pdk.Ops.Two_point_distance) ?(reverse_source = false)
    ?(reverse_destination = false) ?(pairing_shift = 0)
    ?(divisions = 1) ?(keep_input = true) ?output_group
    ?(collinearity_tolerance = 0.)
    ?(recompute_normals = true) input =
  if String.trim source_group = "" then
    invalid_arg "Sop.poly_bridge: empty source edge group name";
  if String.trim destination_group = "" then
    invalid_arg "Sop.poly_bridge: empty destination edge group name";
  Node.Private.make ?label ~operation:"poly_bridge" ~version:1
    ~parameters:(String.concat ";" [
      "source=" ^ source_group;
      "destination=" ^ destination_group;
      "pairing=" ^ poly_bridge_pairing_key pairing;
      "closest=" ^ string_of_bool connect_closest_ends;
      "minimize=" ^ poly_loft_minimize_key minimize;
      "reverse_source=" ^ string_of_bool reverse_source;
      "reverse_destination=" ^ string_of_bool reverse_destination;
      "pairing_shift=" ^ string_of_int pairing_shift;
      "divisions=" ^ string_of_int divisions;
      "keep_input=" ^ string_of_bool keep_input;
      "output_group=" ^ option_string_key output_group;
      "collinearity=" ^ float_key collinearity_tolerance;
      "normals=" ^ string_of_bool recompute_normals])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match Pdk.Geometry.find_edge_group source_group geometry,
          Pdk.Geometry.find_edge_group destination_group geometry with
      | None, _ -> Error (Diagnostic.error ~code:"missing_edge_group"
          (Printf.sprintf "poly_bridge could not find source edge group %S"
             source_group))
      | _, None -> Error (Diagnostic.error ~code:"missing_edge_group"
          (Printf.sprintf "poly_bridge could not find destination edge group %S"
             destination_group))
      | Some source, Some destination ->
          match Pdk.Ops.poly_bridge ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~source ~destination ~pairing
              ~connect_closest_ends ~minimize ~reverse_source
              ~reverse_destination ~pairing_shift ~divisions ~keep_input ?output_group
              ~collinearity_tolerance ~recompute_normals geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_flip ?label ?group ?(cycles = 1)
    ?(cycle_vertex_attributes = true) ?(recompute_point_normals = false) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_flip: empty edge group name") group;
  if cycles < 0 then invalid_arg "Sop.edge_flip: cycles must be non-negative";
  Node.Private.make ?label ~operation:"edge_flip" ~version:1
    ~parameters:(Printf.sprintf
      "group=%s;cycles=%d;cycle_vertex_attributes=%b;recompute_point_normals=%b"
      (option_string_key group) cycles cycle_vertex_attributes
      recompute_point_normals)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some edges -> Ok (Some edges)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "edge_flip could not find native edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.edge_flip ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ~cycles
              ~cycle_vertex_attributes ~recompute_point_normals geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_cusp ?label ?group ?(update_point_normals = true) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_cusp: empty edge group name") group;
  Node.Private.make ?label ~operation:"edge_cusp" ~version:1
    ~parameters:(Printf.sprintf "group=%s;update_point_normals=%b"
      (option_string_key group) update_point_normals)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some edges -> Ok (Some edges)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "edge_cusp could not find native edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.edge_cusp ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ~update_point_normals
              geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_straighten ?label ?group ?output_group input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_straighten: empty edge group name") group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_straighten: empty output edge group name")
    output_group;
  Node.Private.make ?label ~operation:"edge_straighten" ~version:1
    ~parameters:(Printf.sprintf "group=%s;output_group=%s"
      (option_string_key group) (option_string_key output_group))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some edges -> Ok (Some edges)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "edge_straighten could not find native edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.edge_straighten ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ?output_group geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let circle_from_edges ?label ?group ?radius
    ?(scale = Vec3.create 1. 1. 1.) ?output_group input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.circle_from_edges: empty edge group name") group;
  Option.iter (fun value -> if not (Float.is_finite value) || value <= 0. then
    invalid_arg "Sop.circle_from_edges: radius must be finite and positive")
    radius;
  if not (Float.is_finite scale.Vec3.x && Float.is_finite scale.y
      && Float.is_finite scale.z) then
    invalid_arg "Sop.circle_from_edges: scale must be finite";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.circle_from_edges: empty output edge group name")
    output_group;
  let scale = vec3_copy scale in
  Node.Private.make ?label ~operation:"circle_from_edges" ~version:1
    ~parameters:(Printf.sprintf "group=%s;radius=%s;scale=%s;output_group=%s"
      (option_string_key group) (option_float_key radius) (vec3_key scale)
      (option_string_key output_group))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some edges -> Ok (Some edges)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "circle_from_edges could not find native edge group %S"
                    name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.circle_from_edges ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ?radius ~scale ?output_group
              geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let graph_color_connectivity_key = function
  | Pdk.Ops.Graph_primitives_by_point -> "primitives_by_point"
  | Pdk.Ops.Graph_points_by_primitive -> "points_by_primitive"
  | Pdk.Ops.Graph_primitives_by_edge -> "primitives_by_edge"

let graph_color_worksets_key (value : Pdk.Ops.graph_color_worksets) =
  String.escaped value.begin_attribute ^ "," ^ String.escaped value.length_attribute

let graph_color ?label ?selection
    ?(connectivity = Pdk.Ops.Graph_primitives_by_point)
    ?(color_attribute = "color") ?(sort_output = false) ?worksets input =
  let validate_name label name =
    if String.trim name = "" || String.equal name "P" then
      invalid_arg ("Sop.graph_color: " ^ label ^ " must be non-empty and not P") in
  validate_name "color attribute" color_attribute;
  Option.iter (fun selection ->
    let name = match selection with
      | Point_group name | Vertex_group name | Primitive_group name
      | Edge_group name -> name in
    if String.trim name = "" then
      invalid_arg "Sop.graph_color: empty selection group name") selection;
  Option.iter (fun (value : Pdk.Ops.graph_color_worksets) ->
    validate_name "workset begin attribute" value.begin_attribute;
    validate_name "workset length attribute" value.length_attribute;
    if String.equal value.begin_attribute value.length_attribute then
      invalid_arg "Sop.graph_color: workset attribute names must be distinct";
    if not sort_output then
      invalid_arg "Sop.graph_color: worksets require sorted output") worksets;
  Node.Private.make ?label ~operation:"graph_color" ~version:1
    ~parameters:(Printf.sprintf
      "selection=%s;connectivity=%s;color_attribute=%s;sort_output=%b;worksets=%s"
      (match selection with None -> "none" | Some value -> element_group_key value)
      (graph_color_connectivity_key connectivity) (String.escaped color_attribute)
      sort_output
      (match worksets with None -> "none" | Some value -> graph_color_worksets_key value))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"graph_color" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.graph_color ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~connectivity
              ~color_attribute ~sort_output ?worksets inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_equalize_method_key = function
  | Pdk.Ops.Equalize_average -> "average"
  | Pdk.Ops.Equalize_longest -> "longest"
  | Pdk.Ops.Equalize_shortest -> "shortest"

let edge_equalize ?label ?group ?(method_ = Pdk.Ops.Equalize_average)
    ?(iterations = 64) ?(tolerance = 1e-6) ?output_group input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_equalize: empty edge group name") group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_equalize: empty output edge group name") output_group;
  if iterations <= 0 then
    invalid_arg "Sop.edge_equalize: iterations must be positive";
  if not (Float.is_finite tolerance) || tolerance <= 0. then
    invalid_arg "Sop.edge_equalize: tolerance must be finite and positive";
  Node.Private.make ?label ~operation:"edge_equalize" ~version:1
    ~parameters:(Printf.sprintf
      "group=%s;method=%s;iterations=%d;tolerance=%h;output_group=%s"
      (option_string_key group) (edge_equalize_method_key method_) iterations
      tolerance (option_string_key output_group))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some edges -> Ok (Some edges)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "edge_equalize could not find native edge group %S" name))) in
      match edges with
      | Error error -> Error error
      | Ok edges ->
          match Pdk.Ops.edge_equalize ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ~method_ ~iterations
              ~tolerance ?output_group geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_relax_target_key = function
  | Pdk.Ops.Individual_lengths -> "individual"
  | Pdk.Ops.Scale_independent_distribution -> "scale_independent"

let edge_relax ?label ?group ?pin_group ?(iterations = 20)
    ?(step_size = 0.5) ?(target_mode = Pdk.Ops.Individual_lengths)
    ?(only_shorten = false) ?(tolerance = 1e-6) ~reference input =
  (match group with
   | Some (Vertex_group _ | Edge_group _) ->
       invalid_arg "Sop.edge_relax: group must own points or primitives"
   | None | Some (Point_group _ | Primitive_group _) -> ());
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_relax: empty pin point group name") pin_group;
  if iterations <= 0 then
    invalid_arg "Sop.edge_relax: iterations must be positive";
  if not (Float.is_finite step_size) || step_size <= 0. || step_size > 1. then
    invalid_arg "Sop.edge_relax: step size must be finite and within (0, 1]";
  if not (Float.is_finite tolerance) || tolerance <= 0. then
    invalid_arg "Sop.edge_relax: tolerance must be finite and positive";
  Node.Private.make ?label ~operation:"edge_relax" ~version:1
    ~parameters:(Printf.sprintf
      "group=%s;pin_group=%s;iterations=%d;step_size=%s;target_mode=%s;only_shorten=%b;tolerance=%s;roles=source,reference"
      (match group with None -> "none" | Some group -> element_group_key group)
      (option_string_key pin_group) iterations (float_key step_size)
      (edge_relax_target_key target_mode) only_shorten (float_key tolerance))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input;reference|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) and reference = inputs.(1) in
      let selection = match group with
        | None -> Ok None
        | Some (Point_group name) ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
             | Some group -> Ok (Some (Pdk.Ops.Relax_points group))
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "edge_relax could not find point group %S" name)))
        | Some (Primitive_group name) ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some (Pdk.Ops.Relax_primitives group))
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "edge_relax could not find primitive group %S" name)))
        | Some (Vertex_group _ | Edge_group _) -> assert false in
      let pins = match pin_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "edge_relax could not find pin point group %S"
                    name))) in
      match selection, pins with
      | Error error, _ | _, Error error -> Error error
      | Ok selection, Ok pin_points ->
          match Pdk.Ops.edge_relax ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ?pin_points ~iterations
              ~step_size ~target_mode ~only_shorten ~tolerance ~reference
              geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_transport_roots_key = function
  | Pdk.Ops.Transport_first_point -> "first"
  | Pdk.Ops.Transport_last_point -> "last"
  | Pdk.Ops.Transport_root_group _ -> "group"

let edge_transport_operation_key = function
  | Pdk.Ops.Transport -> "transport"
  | Pdk.Ops.Transport_from_root -> "from_root"
  | Pdk.Ops.Transport_total -> "total"
  | Pdk.Ops.Transport_maximum -> "maximum"
  | Pdk.Ops.Transport_minimum -> "minimum"

let edge_transport_split_key = function
  | Pdk.Ops.Transport_copy -> "copy"
  | Pdk.Ops.Transport_split -> "split"

let edge_transport_normalization_key = function
  | Pdk.Ops.Transport_no_normalization -> "none"
  | Pdk.Ops.Transport_normalize_components -> "components"
  | Pdk.Ops.Transport_normalize_global -> "global"

let edge_transport_direction_key = function
  | Pdk.Ops.Transport_forward -> "forward"
  | Pdk.Ops.Transport_backward -> "backward"

let edge_transport_merge_key = function
  | Pdk.Ops.Transport_merge_add -> "add"
  | Pdk.Ops.Transport_merge_maximum -> "maximum"
  | Pdk.Ops.Transport_merge_minimum -> "minimum"

type blend_shape = {
  blend_node : Node.t;
  blend_weight : float;
  blend_mask_attribute : string option;
  blend_mask_source : Pdk.Ops.blend_shape_mask_source;
}

let blend_shape ?mask_attribute
    ?(mask_source = Pdk.Ops.Blend_mask_shape) ~weight blend_node =
  if not (Float.is_finite weight) then
    invalid_arg "Sop.blend_shape: weight must be finite";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.blend_shape: empty mask attribute") mask_attribute;
  { blend_node; blend_weight = weight; blend_mask_attribute = mask_attribute;
    blend_mask_source = mask_source }

let blend_shapes_mode_key = function
  | Pdk.Ops.Blend_normalized -> "normalized"
  | Pdk.Ops.Blend_differencing -> "differencing"

let blend_shapes_masking_key = function
  | Pdk.Ops.Blend_no_mask -> "none"
  | Pdk.Ops.Blend_set_from_attribute -> "set"
  | Pdk.Ops.Blend_scale_from_attribute -> "scale"

let blend_mask_source_key = function
  | Pdk.Ops.Blend_mask_first_input -> "first"
  | Pdk.Ops.Blend_mask_shape -> "shape"

let blend_shapes ?label ?point_group ?(mode = Pdk.Ops.Blend_normalized)
    ?(masking = Pdk.Ops.Blend_no_mask) ?mask_attribute ?point_id_attribute
    ?(attributes = "*") ~shapes input =
  List.iter (fun (kind, name) -> Option.iter (fun name ->
      if String.trim name = "" then invalid_arg
        ("Sop.blend_shapes: empty " ^ kind ^ " name")) name)
    ["point group", point_group; "mask attribute", mask_attribute;
     "point ID attribute", point_id_attribute];
  if shapes = [] then input
  else
    let shape_array = Array.of_list shapes in
    let inputs = Array.make (Array.length shape_array + 1) input in
    Array.iteri (fun index shape -> inputs.(index + 1) <- shape.blend_node)
      shape_array;
    let shape_keys = Array.mapi (fun index shape -> Printf.sprintf
        "%d:{weight=%s;mask=%s;mask_source=%s}" index
        (float_key shape.blend_weight)
        (option_string_key shape.blend_mask_attribute)
        (blend_mask_source_key shape.blend_mask_source)) shape_array in
    Node.Private.make ?label ~operation:"blend_shapes" ~version:1
      ~parameters:(String.concat ";" [
        "point_group=" ^ option_string_key point_group;
        "mode=" ^ blend_shapes_mode_key mode;
        "masking=" ^ blend_shapes_masking_key masking;
        "mask_attribute=" ^ option_string_key mask_attribute;
        "point_id_attribute=" ^ option_string_key point_id_attribute;
        "attributes=" ^ Printf.sprintf "%S" attributes;
        "shapes=" ^ String.concat "," (Array.to_list shape_keys)])
      ~cook_mode:(Node.Duplicate_input 0)
      ~dependencies:Context.Dependencies.static ~inputs
      (fun ~node_id:_ context inputs ->
        let geometry = inputs.(0) in
        match resolve_optional_point_group "blend_shapes" point_group geometry with
        | Error error -> Error error
        | Ok points ->
            let shapes = Array.to_list (Array.mapi (fun index shape ->
              Pdk.Ops.blend_shape ?mask_attribute:shape.blend_mask_attribute
                ~mask_source:shape.blend_mask_source ~weight:shape.blend_weight
                inputs.(index + 1)) shape_array) in
            match Pdk.Ops.blend_shapes ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ?points ~mode ~masking
                ?mask_attribute ?point_id_attribute ~attributes ~shapes geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_pdk_error error)

type attribute_composite_input = {
  composite_node : Node.t;
  composite_weight : float;
}

let attribute_composite_input ~weight composite_node =
  if not (Float.is_finite weight) then
    invalid_arg "Sop.attribute_composite_input: weight must be finite";
  { composite_node; composite_weight = weight }

let attribute_composite_operation_key = function
  | Pdk.Ops.Composite_mean -> "mean"
  | Pdk.Ops.Composite_maximum -> "maximum"
  | Pdk.Ops.Composite_minimum -> "minimum"
  | Pdk.Ops.Composite_over -> "over"
  | Pdk.Ops.Composite_under -> "under"

let attribute_composite ?label ?(operation = Pdk.Ops.Composite_mean)
    ?(weight = 1.) ?(detail_attributes = "*")
    ?(primitive_attributes = "*") ?(point_attributes = "*")
    ?(vertex_attributes = "*") ?(allow_position = false) ?alpha_attribute
    ~inputs input =
  if not (Float.is_finite weight) then
    invalid_arg "Sop.attribute_composite: weight must be finite";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.attribute_composite: alpha attribute must be non-empty")
    alpha_attribute;
  let composite_inputs = Array.of_list inputs in
  let nodes = Array.make (Array.length composite_inputs + 1) input in
  Array.iteri (fun index input -> nodes.(index + 1) <- input.composite_node)
    composite_inputs;
  let input_keys = Array.mapi (fun index input -> Printf.sprintf "%d:%s"
      index (float_key input.composite_weight)) composite_inputs in
  Node.Private.make ?label ~operation:"attribute_composite" ~version:1
    ~parameters:(String.concat ";" [
      "operation=" ^ attribute_composite_operation_key operation;
      "weight=" ^ float_key weight;
      "detail_attributes=" ^ Printf.sprintf "%S" detail_attributes;
      "primitive_attributes=" ^ Printf.sprintf "%S" primitive_attributes;
      "point_attributes=" ^ Printf.sprintf "%S" point_attributes;
      "vertex_attributes=" ^ Printf.sprintf "%S" vertex_attributes;
      "allow_position=" ^ string_of_bool allow_position;
      "alpha_attribute=" ^ option_string_key alpha_attribute;
      "inputs=" ^ String.concat "," (Array.to_list input_keys)])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:nodes
    (fun ~node_id:_ context geometries ->
      let inputs = Array.to_list (Array.mapi (fun index input ->
        Pdk.Ops.attribute_composite_input ~weight:input.composite_weight
          geometries.(index + 1)) composite_inputs) in
      match Pdk.Ops.attribute_composite ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~operation ~weight ~detail_attributes
          ~primitive_attributes ~point_attributes ~vertex_attributes
          ~allow_position ?alpha_attribute ~inputs geometries.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

type attribute_mirror_method =
  | Attribute_mirror_plane of {
      origin : Vec3.t;
      normal : Vec3.t;
      distance : float;
      tolerance : float;
    }
  | Attribute_mirror_mapping of {
      mapping_attribute : string;
      destination_group : string;
    }

let attribute_mirror_owner_key = function
  | Pdk.Ops.Mirror_point_attributes -> "point"
  | Pdk.Ops.Mirror_vertex_attributes -> "vertex"
  | Pdk.Ops.Mirror_primitive_attributes -> "primitive"

let attribute_mirror_group_owner = function
  | Pdk.Ops.Mirror_point_attributes -> Pdk.Group.Point
  | Pdk.Ops.Mirror_vertex_attributes -> Pdk.Group.Vertex
  | Pdk.Ops.Mirror_primitive_attributes -> Pdk.Group.Primitive

let attribute_mirror_group_use_key = function
  | Pdk.Ops.Mirror_group_as_source -> "source"
  | Pdk.Ops.Mirror_group_as_destination -> "destination"

let attribute_mirror_transform_key = function
  | Pdk.Ops.Mirror_copy -> "copy"
  | Pdk.Ops.Mirror_uv { origin_u; origin_v; direction_u; direction_v } ->
      String.concat ":" ["uv"; float_key origin_u; float_key origin_v;
        float_key direction_u; float_key direction_v]
  | Pdk.Ops.Mirror_vector -> "vector"
  | Pdk.Ops.Mirror_point -> "point"

let attribute_mirror_method_copy = function
  | Attribute_mirror_plane { origin; normal; distance; tolerance } ->
      Attribute_mirror_plane { origin = vec3_copy origin;
        normal = vec3_copy normal; distance; tolerance }
  | Attribute_mirror_mapping { mapping_attribute; destination_group } ->
      Attribute_mirror_mapping { mapping_attribute; destination_group }

let attribute_mirror_method_key = function
  | Attribute_mirror_plane { origin; normal; distance; tolerance } ->
      String.concat ":" ["plane"; vec3_key origin; vec3_key normal;
        float_key distance; float_key tolerance]
  | Attribute_mirror_mapping { mapping_attribute; destination_group } ->
      "mapping:" ^ String.escaped mapping_attribute ^ ":"
      ^ String.escaped destination_group

let attribute_mirror ?label ?group
    ?(group_use = Pdk.Ops.Mirror_group_as_source) ?(attributes = "Cd")
    ?(transform = Pdk.Ops.Mirror_copy) ?string_replace ?output_mapping
    ?source_group ?destination_group ~owner ~method_ input =
  let method_ = attribute_mirror_method_copy method_ in
  List.iter (fun (kind, name) -> Option.iter (fun name ->
      if String.trim name = "" then invalid_arg
        ("Sop.attribute_mirror: empty " ^ kind ^ " name")) name)
    ["selection group", group; "output mapping", output_mapping;
     "source group", source_group; "destination group", destination_group];
  (match method_ with
   | Attribute_mirror_mapping { mapping_attribute; destination_group } ->
       if String.trim mapping_attribute = "" then invalid_arg
           "Sop.attribute_mirror: empty mapping attribute";
       if String.trim destination_group = "" then invalid_arg
           "Sop.attribute_mirror: empty mapping destination group"
   | Attribute_mirror_plane _ -> ());
  Option.iter (fun (search, _) -> if search = "" then invalid_arg
    "Sop.attribute_mirror: empty string search") string_replace;
  let replace_key = match string_replace with
    | None -> "none"
    | Some (search, replacement) ->
        "some:" ^ String.escaped search ^ ":" ^ String.escaped replacement in
  Node.Private.make ?label ~operation:"attribute_mirror" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ attribute_mirror_owner_key owner;
      "method=" ^ attribute_mirror_method_key method_;
      "group=" ^ option_string_key group;
      "group_use=" ^ attribute_mirror_group_use_key group_use;
      "attributes=" ^ Printf.sprintf "%S" attributes;
      "transform=" ^ attribute_mirror_transform_key transform;
      "string_replace=" ^ replace_key;
      "output_mapping=" ^ option_string_key output_mapping;
      "source_group=" ^ option_string_key source_group;
      "destination_group=" ^ option_string_key destination_group])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) and group_owner = attribute_mirror_group_owner owner in
      let resolve label name = match name with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:group_owner name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "attribute_mirror could not find %s %S"
                    label name))) in
      match resolve "selection group" group with
      | Error error -> Error error
      | Ok resolved_group ->
          let resolved_method = match method_ with
            | Attribute_mirror_plane { origin; normal; distance; tolerance } ->
                Ok (Pdk.Ops.Mirror_by_plane {
                  origin; normal; distance; tolerance })
            | Attribute_mirror_mapping { mapping_attribute;
                destination_group = name } ->
                (match Pdk.Geometry.find_group ~owner:group_owner name geometry with
                 | Some destination_group -> Ok (Pdk.Ops.Mirror_by_mapping {
                     mapping_attribute; destination_group })
                 | None -> Error (Diagnostic.error ~code:"missing_group"
                     (Printf.sprintf
                       "attribute_mirror could not find mapping destination group %S"
                       name))) in
          match resolved_method with
          | Error error -> Error error
          | Ok method_ ->
              match Pdk.Ops.attribute_mirror
                  ~cancel:(Context.cancel_token context)
                  ~grain:(Context.grain context) ?group:resolved_group ~group_use
                  ~attributes ~transform ?string_replace ?output_mapping
                  ?source_group ?destination_group ~owner ~method_ geometry with
              | Ok geometry -> cooked geometry
              | Error error -> structured_pdk_error error)

let rewire_owner_key = function
  | Pdk.Attribute.Point -> "point"
  | Pdk.Attribute.Vertex -> "vertex"
  | Pdk.Attribute.Primitive -> "primitive"
  | Pdk.Attribute.Detail -> "detail"

let rewire_vertices ?label ?selection ?(recursive = false)
    ?(delete_target_attribute = false) ?(keep_unused_points = false)
    ?original_point_attribute ~owner ~target_attribute input =
  if String.trim target_attribute = "" then
    invalid_arg "Sop.rewire_vertices: empty target attribute";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.rewire_vertices: empty original point attribute")
    original_point_attribute;
  Node.Private.make ?label ~operation:"rewire_vertices" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ rewire_owner_key owner;
      "target_attribute=" ^ String.escaped target_attribute;
      "selection=" ^ (match selection with
        | None -> "none" | Some selection -> element_group_key selection);
      "recursive=" ^ string_of_bool recursive;
      "delete_target_attribute=" ^ string_of_bool delete_target_attribute;
      "keep_unused_points=" ^ string_of_bool keep_unused_points;
      "original_point_attribute=" ^ option_string_key original_point_attribute])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"rewire_vertices" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.rewire_vertices ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~recursive
              ~delete_target_attribute ~keep_unused_points
              ?original_point_attribute ~owner ~target_attribute inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_transport ?label ?point_group ?root_group
    ?(roots = Pdk.Ops.Transport_first_point)
    ?(direction = Pdk.Ops.Transport_forward)
    ?(operation = Pdk.Ops.Transport)
    ?(root_value = Pdk.Ops.Transport_root_hold)
    ?(integrate_constant = false) ?(scale_by_edge_length = false)
    ?(split = Pdk.Ops.Transport_copy)
    ?(merge = Pdk.Ops.Transport_merge_add)
    ?(normalization = Pdk.Ops.Transport_no_normalization) ~attribute input =
  List.iter (fun (kind, name) -> Option.iter (fun name ->
      if String.trim name = "" then
        invalid_arg ("Sop.edge_transport: empty " ^ kind ^ " group name")) name)
    ["point", point_group; "root", root_group];
  if String.trim attribute = "" || attribute = "P" then
    invalid_arg "Sop.edge_transport: attribute must be non-empty and not P";
  (match roots, root_group with
   | Pdk.Ops.Transport_root_group _, _ ->
       invalid_arg "Sop.edge_transport: construct grouped roots with ~root_group"
   | (Pdk.Ops.Transport_first_point | Pdk.Ops.Transport_last_point), Some _ -> ()
   | _, None -> ());
  let roots_key = if Option.is_some root_group then "group"
    else edge_transport_roots_key roots in
  Node.Private.make ?label ~operation:"edge_transport" ~version:1
    ~parameters:(Printf.sprintf
      "point_group=%s;roots=%s;root_group=%s;direction=%s;operation=%s;root_value=%s;integrate_constant=%b;scale_by_edge_length=%b;split=%s;merge=%s;normalization=%s;attribute=%S"
      (option_string_key point_group) roots_key (option_string_key root_group)
      (edge_transport_direction_key direction)
      (edge_transport_operation_key operation)
      (match root_value with Pdk.Ops.Transport_root_zero -> "zero"
        | Pdk.Ops.Transport_root_hold -> "hold")
      integrate_constant scale_by_edge_length (edge_transport_split_key split)
      (edge_transport_merge_key merge)
      (edge_transport_normalization_key normalization) attribute)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let points = resolve_optional_point_group "edge_transport" point_group
          geometry in
      let roots = match root_group with
        | None -> Ok roots
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
             | Some group -> Ok (Pdk.Ops.Transport_root_group group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "edge_transport could not find root point group %S"
                    name))) in
      match points, roots with
      | Error error, _ | _, Error error -> Error error
      | Ok points, Ok roots ->
          match Pdk.Ops.edge_transport ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?points ~roots ~operation ~root_value
              ~integrate_constant ~scale_by_edge_length ~split ~direction ~merge
              ~normalization ~attribute geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_transport_curves ?label ?primitive_group
    ?(owner = Pdk.Attribute.Point)
    ?(direction = Pdk.Ops.Transport_forward)
    ?(operation = Pdk.Ops.Transport)
    ?(root_value = Pdk.Ops.Transport_root_hold)
    ?(integrate_constant = false) ?(scale_by_edge_length = false)
    ?(normalization = Pdk.Ops.Transport_no_normalization) ~attribute input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_transport_curves: empty primitive group name")
    primitive_group;
  if String.trim attribute = "" || attribute = "P" then
    invalid_arg
      "Sop.edge_transport_curves: attribute must be non-empty and not P";
  if owner <> Pdk.Attribute.Point && owner <> Pdk.Attribute.Vertex then
    invalid_arg "Sop.edge_transport_curves: owner must be point or vertex";
  let owner_key = match owner with
    | Pdk.Attribute.Point -> "point"
    | Pdk.Attribute.Vertex -> "vertex"
    | Pdk.Attribute.Primitive | Pdk.Attribute.Detail -> assert false in
  Node.Private.make ?label ~operation:"edge_transport_curves" ~version:1
    ~parameters:(Printf.sprintf
      "primitive_group=%s;owner=%s;direction=%s;operation=%s;root_value=%s;integrate_constant=%b;scale_by_edge_length=%b;normalization=%s;attribute=%S"
      (option_string_key primitive_group) owner_key
      (edge_transport_direction_key direction)
      (edge_transport_operation_key operation)
      (match root_value with Pdk.Ops.Transport_root_zero -> "zero"
        | Pdk.Ops.Transport_root_hold -> "hold")
      integrate_constant scale_by_edge_length
      (edge_transport_normalization_key normalization) attribute)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_optional_primitive_group "edge_transport_curves"
          primitive_group geometry with
      | Error error -> Error error
      | Ok primitives ->
          match Pdk.Ops.edge_transport_curves
              ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ~owner ~direction
              ~operation ~root_value ~integrate_constant ~scale_by_edge_length
              ~normalization ~attribute geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_transport_parent ?label ?point_group ?(parent_attribute = "parent")
    ?(direction = Pdk.Ops.Transport_forward)
    ?(operation = Pdk.Ops.Transport)
    ?(root_value = Pdk.Ops.Transport_root_hold)
    ?(integrate_constant = false) ?(scale_by_edge_length = false)
    ?(split = Pdk.Ops.Transport_copy)
    ?(merge = Pdk.Ops.Transport_merge_add)
    ?(normalization = Pdk.Ops.Transport_no_normalization) ~attribute input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.edge_transport_parent: empty point group name") point_group;
  if String.trim parent_attribute = "" then
    invalid_arg "Sop.edge_transport_parent: empty parent attribute name";
  if String.trim attribute = "" || attribute = "P" then
    invalid_arg
      "Sop.edge_transport_parent: attribute must be non-empty and not P";
  Node.Private.make ?label ~operation:"edge_transport_parent" ~version:1
    ~parameters:(Printf.sprintf
      "point_group=%s;parent_attribute=%S;direction=%s;operation=%s;root_value=%s;integrate_constant=%b;scale_by_edge_length=%b;split=%s;merge=%s;normalization=%s;attribute=%S"
      (option_string_key point_group) parent_attribute
      (edge_transport_direction_key direction)
      (edge_transport_operation_key operation)
      (match root_value with Pdk.Ops.Transport_root_zero -> "zero"
        | Pdk.Ops.Transport_root_hold -> "hold")
      integrate_constant scale_by_edge_length (edge_transport_split_key split)
      (edge_transport_merge_key merge)
      (edge_transport_normalization_key normalization) attribute)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_optional_point_group "edge_transport_parent" point_group
          geometry with
      | Error error -> Error error
      | Ok points ->
          match Pdk.Ops.edge_transport_parent
              ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?points ~parent_attribute ~direction
              ~operation ~root_value ~integrate_constant ~scale_by_edge_length
              ~split ~merge ~normalization ~attribute geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let copy_target_owner_key = function
  | Pdk.Ops.Copy_target_points -> "points"
  | Pdk.Ops.Copy_target_vertices -> "vertices"
  | Pdk.Ops.Copy_target_primitives -> "primitives"

let copy_target_operation_key = function
  | Pdk.Ops.Copy_target_nothing -> "nothing"
  | Pdk.Ops.Copy_target_copy -> "copy"
  | Pdk.Ops.Copy_target_add -> "add"
  | Pdk.Ops.Copy_target_subtract -> "subtract"
  | Pdk.Ops.Copy_target_multiply -> "multiply"

let copy_target_rule_key rule = Printf.sprintf "%S:%s:%s"
    rule.Pdk.Ops.copy_target_pattern
    (copy_target_owner_key rule.copy_target_owner)
    (copy_target_operation_key rule.copy_target_operation)

let copy_to_points ?label ?source_group ?target_group ?piece_attribute
    ?(target_attributes = []) ~source ~targets () =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.copy_to_points: empty source group name") source_group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.copy_to_points: empty target group name") target_group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.copy_to_points: empty piece attribute name") piece_attribute;
  Node.Private.make ?label ~operation:"copy_to_points" ~version:8
    ~parameters:(Printf.sprintf
      "source_group=%S;target_group=%S;piece_attribute=%S;target_attributes=%s"
      (Option.value ~default:"" source_group)
      (Option.value ~default:"" target_group)
      (Option.value ~default:"" piece_attribute)
      (String.concat "," (List.map copy_target_rule_key target_attributes)))
    ~cook_mode:Node.Generic
    ~dependencies:Context.Dependencies.static ~inputs:[|source; targets|]
    (fun ~node_id:_ context inputs ->
      let source_primitives = match source_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name
                inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "copy_to_points could not find source primitive group %S" name))) in
      let target_points = match target_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name inputs.(1) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "copy_to_points could not find target point group %S" name))) in
      match source_primitives, target_points with
      | Error error, _ | _, Error error -> Error error
      | Ok source_primitives, Ok target_points ->
          match Pdk.Ops.copy_to_points ~grain:(Context.grain context)
              ~cancel:(Context.cancel_token context) ?source_primitives
              ?target_points ?piece_attribute ~target_attributes ~source:inputs.(0)
              ~targets:inputs.(1) () with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let duplicate ?label ?(copies = 1) ?(cumulative = true)
    ?(transform = Mat4.identity) ?group ?copy_group_prefix
    ?(preserve_groups = false) input =
  let transform = matrix_copy transform in
  Node.Private.make ?label ~operation:"duplicate" ~version:2
    ~parameters:(Printf.sprintf
      "copies=%d;cumulative=%b;transform=%s;group=%s;copy_group_prefix=%s;preserve_groups=%b"
      copies cumulative (matrix_key transform) (option_string_key group)
      (option_string_key copy_group_prefix) preserve_groups)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "duplicate could not find primitive group %S" name))) in
      match primitives with
      | Error error -> Error error
      | Ok primitives ->
          match Pdk.Ops.duplicate ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~copies ~cumulative ~transform
              ?primitives ?copy_group_prefix ~preserve_groups inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let pack ?transforms input = Instances.create ?transforms input
let duplicate_packed ?copies ?cumulative ?transform instances =
  Instances.duplicate ?copies ?cumulative ?transform instances

let unpack ?label ?(apply_transform = true) instances =
  let transforms = Instances.transforms instances in
  let input = Instances.source instances in
  Node.Private.make ?label ~operation:"unpack" ~version:1
    ~parameters:(Printf.sprintf "instances=%d;apply_transform=%b;fingerprint=%s"
      (Array.length transforms) apply_transform
      (matrices_fingerprint transforms))
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Ops.materialize_instances
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ~apply_transform ~transforms inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let switch ?label ~index inputs =
  let inputs = Array.of_list inputs in
  if index < 0 || index >= Array.length inputs then
    invalid_arg "Sop.switch: index is outside the input list";
  Node.Private.make ?label ~operation:"switch" ~version:1
    ~parameters:(Printf.sprintf "index=%d;inputs=%d" index (Array.length inputs))
    ~cook_mode:(Node.Passthrough index)
    ~dependencies:Context.Dependencies.static ~input_policy:(Node.Private.Only index)
    ~inputs (fun ~node_id:_ _context selected -> cooked selected.(0))

let null ?label input =
  Node.Private.make ?label ~operation:"null" ~version:1 ~parameters:""
    ~cook_mode:(Node.Passthrough 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs -> cooked inputs.(0))

let unary_result ?label ~operation cook input =
  Node.Private.make ?label ~operation ~version:1 ~parameters:""
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match cook context inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let triangulate ?label ?group input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.triangulate: empty primitive group name") group;
  Node.Private.make ?label ~operation:"triangulate" ~version:2
    ~parameters:("group=" ^ option_string_key group)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "triangulate could not find primitive group %S" name))) in
      match primitives with
      | Error error -> Error error
      | Ok primitives ->
          match Pdk.Ops.triangulate ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let triangulate_2d_projection_key = function
  | Pdk.Ops.Triangulate_2d_best_fit -> "best_fit"
  | Pdk.Ops.Triangulate_2d_xy -> "xy"
  | Pdk.Ops.Triangulate_2d_yz -> "yz"
  | Pdk.Ops.Triangulate_2d_zx -> "zx"
  | Pdk.Ops.Triangulate_2d_plane { origin; normal } ->
      "plane:" ^ vec3_key origin ^ ":" ^ vec3_key normal
  | Pdk.Ops.Triangulate_2d_point_attribute name -> "attribute:" ^ name

let triangulate_2d ?label ?point_group ?constraint_edge_group
    ?constraint_primitive_group
    ?(projection = Pdk.Ops.Triangulate_2d_best_fit) ?(seed = 0L)
    ?(split_crossing_constraints = false) ?(flood_from_hull_boundary = false)
    ?(remove_outside_constraint_polygons = false)
    ?(silhouette_constraints = false) ?(remove_outside_silhouette = false)
    ?(ignore_non_constraint_points = false)
    ?(remove_duplicate_points = false)
    ?(refine = false) ?(allow_constraint_splitting = true)
    ?(minimum_angle = Float.pi /. 9.) ?maximum_area ?target_edge_length
    ?(minimum_edge_length = 0.) ?(maximum_new_points = 100_000)
    ?(regularization_steps = 0)
    ?(allow_movement_of_interior_input_points = false)
    ?(preserve_point_payload = true)
    ?(restore_original_point_positions = true) ?(keep_primitives = false)
    ?(remove_unused_points = false) ?(recompute_point_normals = false)
    ?split_point_group ?refinement_point_group ?triangle_group
    ?constraint_group input =
  List.iter (fun (kind,name) -> Option.iter (fun name ->
      if String.trim name = "" then invalid_arg
          (Printf.sprintf "Sop.triangulate_2d: empty %s name" kind)) name)
    ["point group",point_group; "constraint edge group",constraint_edge_group;
     "constraint primitive group",constraint_primitive_group;
     "split point group",split_point_group;
     "refinement point group",refinement_point_group;
     "triangle group",triangle_group; "constraint output group",constraint_group];
  (match projection with
   | Pdk.Ops.Triangulate_2d_point_attribute name when String.trim name = "" ->
       invalid_arg "Sop.triangulate_2d: empty point attribute name"
   | _ -> ());
  Node.Private.make ?label ~operation:"triangulate_2d" ~version:12
    ~parameters:(String.concat ";" [
      "point_group=" ^ option_string_key point_group;
      "constraint_edge_group=" ^ option_string_key constraint_edge_group;
      "constraint_primitive_group=" ^ option_string_key constraint_primitive_group;
      "projection=" ^ triangulate_2d_projection_key projection;
      "seed=" ^ Int64.to_string seed;
      "split_crossing_constraints=" ^ string_of_bool split_crossing_constraints;
      "flood_from_hull_boundary=" ^ string_of_bool flood_from_hull_boundary;
      "remove_outside_constraint_polygons=" ^
        string_of_bool remove_outside_constraint_polygons;
      "silhouette_constraints=" ^ string_of_bool silhouette_constraints;
      "remove_outside_silhouette=" ^ string_of_bool remove_outside_silhouette;
      "ignore_non_constraint_points=" ^ string_of_bool ignore_non_constraint_points;
      "remove_duplicate_points=" ^ string_of_bool remove_duplicate_points;
      "refine=" ^ string_of_bool refine;
      "allow_constraint_splitting=" ^ string_of_bool allow_constraint_splitting;
      "minimum_angle=" ^ float_key minimum_angle;
      "maximum_area=" ^ option_float_key maximum_area;
      "target_edge_length=" ^ option_float_key target_edge_length;
      "minimum_edge_length=" ^ float_key minimum_edge_length;
      "maximum_new_points=" ^ string_of_int maximum_new_points;
      "regularization_steps=" ^ string_of_int regularization_steps;
      "allow_movement_of_interior_input_points=" ^
        string_of_bool allow_movement_of_interior_input_points;
      "preserve_point_payload=" ^ string_of_bool preserve_point_payload;
      "restore_original_point_positions=" ^
        string_of_bool restore_original_point_positions;
      "keep_primitives=" ^ string_of_bool keep_primitives;
      "remove_unused_points=" ^ string_of_bool remove_unused_points;
      "recompute_point_normals=" ^ string_of_bool recompute_point_normals;
      "split_point_group=" ^ option_string_key split_point_group;
      "refinement_point_group=" ^ option_string_key refinement_point_group;
      "triangle_group=" ^ option_string_key triangle_group;
      "constraint_group=" ^ option_string_key constraint_group ])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let selection = match point_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
             | Some group -> Ok (Some (Pdk.Ops.Selected_points group))
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "triangulate_2d could not find point group %S" name))) in
      let constraint_edges = match constraint_edge_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "triangulate_2d could not find native edge group %S" name))) in
      let constraint_primitives = match constraint_primitive_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "triangulate_2d could not find primitive group %S" name))) in
      match selection,constraint_edges,constraint_primitives with
      | Error error,_,_ -> Error error
      | _,Error error,_ | _,_,Error error -> Error error
      | Ok selection,Ok constraint_edges,Ok constraint_primitives ->
          match Pdk.Ops.triangulate_2d
              ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
              ?selection ?constraint_edges ?constraint_primitives ~projection
              ~seed ~split_crossing_constraints ~flood_from_hull_boundary
              ~remove_outside_constraint_polygons
              ~silhouette_constraints ~remove_outside_silhouette
              ~ignore_non_constraint_points
              ~remove_duplicate_points
              ~refine ~allow_constraint_splitting ~minimum_angle ?maximum_area
              ?target_edge_length ~minimum_edge_length ~maximum_new_points
              ~regularization_steps ~allow_movement_of_interior_input_points
              ~preserve_point_payload ~restore_original_point_positions
              ~keep_primitives
              ~remove_unused_points ~recompute_point_normals
              ?split_point_group ?refinement_point_group ?triangle_group
              ?constraint_group geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let remesh ?label ?(iterations = 3) ?(smoothing = 0.5) ?(project = true)
    ?(use_input_points_only = false) ?hard_point_group ?hard_edge_group
    ?target_size_attribute ?(preserve_uv_seams = true) ?(uv_attribute = "uv")
    ?output_hard_edges ?output_mesh_size ?output_quality
    ?(recompute_point_normals = true) ~target_length input =
  List.iter (fun (kind, value) -> Option.iter (fun name ->
    if String.trim name = "" then invalid_arg
        (Printf.sprintf "Sop.remesh: empty %s name" kind)) value)
    ["hard point group", hard_point_group; "hard edge group", hard_edge_group;
     "target-size attribute", target_size_attribute;
     "output hard-edge group", output_hard_edges;
     "output mesh-size attribute", output_mesh_size;
     "output quality attribute", output_quality];
  if preserve_uv_seams && String.trim uv_attribute = "" then
    invalid_arg "Sop.remesh: empty UV attribute name";
  Node.Private.make ?label ~operation:"remesh" ~version:1
    ~parameters:(String.concat ";" [
      "target_length=" ^ float_key target_length;
      "iterations=" ^ string_of_int iterations;
      "smoothing=" ^ float_key smoothing;
      "project=" ^ string_of_bool project;
      "use_input_points_only=" ^ string_of_bool use_input_points_only;
      "hard_points=" ^ option_string_key hard_point_group;
      "hard_edges=" ^ option_string_key hard_edge_group;
      "target_size_attribute=" ^ option_string_key target_size_attribute;
      "preserve_uv_seams=" ^ string_of_bool preserve_uv_seams;
      "uv_attribute=" ^ String.escaped uv_attribute;
      "output_hard_edges=" ^ option_string_key output_hard_edges;
      "output_mesh_size=" ^ option_string_key output_mesh_size;
      "output_quality=" ^ option_string_key output_quality;
      "recompute_point_normals=" ^ string_of_bool recompute_point_normals])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_optional_point_group "remesh" hard_point_group geometry with
      | Error error -> Error error
      | Ok hard_points ->
          (match resolve_optional_edge_group "remesh" hard_edge_group geometry with
           | Error error -> Error error
           | Ok hard_edges ->
               match Pdk.Ops.remesh ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ~iterations ~smoothing ~project
                   ~use_input_points_only ?hard_points ?hard_edges
                   ?target_size_attribute ~preserve_uv_seams ~uv_attribute
                   ?output_hard_edges ?output_mesh_size ?output_quality
                   ~recompute_point_normals ~target_length geometry with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let boolean ?label ?(operation = Pdk.Boolean.Union)
    ?(left_treatment = Pdk.Boolean.Solid)
    ?(right_treatment = Pdk.Boolean.Solid)
    ?(resolve_left_self_intersections = false)
    ?(resolve_right_self_intersections = false)
    ?(point_conflict = Pdk.Boolean.Promote_to_vertex)
    ?(point_tolerance = 0.)
    ?(tiny_seam_threshold = 0.) ?(cleanup_max_batches = 8)
    ?(strict_cleanup = true)
    ?(seam_points = Pdk.Boolean.Shared_seam_points)
    ?(detriangulation = Pdk.Boolean.Triangles) ?(assume_flat = false)
    ?require_closed ?(left_piece_group = Some "boolean_left")
    ?(overlap_piece_group = Some "boolean_overlap")
    ?(right_piece_group = Some "boolean_right") ~right left =
  if not (Float.is_finite point_tolerance) || point_tolerance < 0. then
    invalid_arg "Sop.boolean: point_tolerance must be finite and non-negative";
  if not (Float.is_finite tiny_seam_threshold) || tiny_seam_threshold < 0. then
    invalid_arg
      "Sop.boolean: tiny_seam_threshold must be finite and non-negative";
  if cleanup_max_batches <= 0 then
    invalid_arg "Sop.boolean: cleanup_max_batches must be positive";
  let piece_names = List.filter_map Fun.id
      [left_piece_group; overlap_piece_group; right_piece_group] in
  if operation = Pdk.Boolean.Shatter
      && List.exists (fun name -> String.trim name = "") piece_names then
    invalid_arg "Sop.boolean: empty shatter piece group name";
  let piece_names = List.sort String.compare piece_names in
  let rec duplicate = function
    | first :: (second :: _ as rest) ->
        String.equal first second || duplicate rest
    | [] | [_] -> false in
  if operation = Pdk.Boolean.Shatter && duplicate piece_names then
    invalid_arg "Sop.boolean: shatter piece group names must be distinct";
  let operation_key = function
    | Pdk.Boolean.Union -> "union"
    | Pdk.Boolean.Intersection -> "intersection"
    | Pdk.Boolean.Difference -> "difference"
    | Pdk.Boolean.Reverse_difference -> "reverse_difference"
    | Pdk.Boolean.Xor -> "xor"
    | Pdk.Boolean.Shatter -> "shatter" in
  let treatment_key = function
    | Pdk.Boolean.Solid -> "solid"
    | Pdk.Boolean.Surface -> "surface" in
  let conflict_key = function
    | Pdk.Boolean.Reject -> "reject"
    | Pdk.Boolean.Promote_to_vertex -> "promote_to_vertex" in
  let seam_key = function
    | Pdk.Boolean.Shared_seam_points -> "shared"
    | Pdk.Boolean.Split_seam_points -> "split" in
  let detriangulation_key = function
    | Pdk.Boolean.Triangles -> "triangles"
    | Pdk.Boolean.Unchanged_polygons -> "unchanged_polygons"
    | Pdk.Boolean.All_polygons -> "all_polygons" in
  let optional_bool_key = function
    | None -> "default"
    | Some value -> string_of_bool value in
  let piece_key value = option_string_key
      (if operation = Pdk.Boolean.Shatter then value else None) in
  Node.Private.make ?label ~operation:"boolean" ~version:1
    ~parameters:(String.concat ";" [
      "operation=" ^ operation_key operation;
      "left_treatment=" ^ treatment_key left_treatment;
      "right_treatment=" ^ treatment_key right_treatment;
      "resolve_left_self_intersections=" ^
        string_of_bool resolve_left_self_intersections;
      "resolve_right_self_intersections=" ^
        string_of_bool resolve_right_self_intersections;
      "point_conflict=" ^ conflict_key point_conflict;
      "point_tolerance=" ^ float_key point_tolerance;
      "tiny_seam_threshold=" ^ float_key tiny_seam_threshold;
      "cleanup_max_batches=" ^ string_of_int cleanup_max_batches;
      "strict_cleanup=" ^ string_of_bool strict_cleanup;
      "seam_points=" ^ seam_key seam_points;
      "detriangulation=" ^ detriangulation_key detriangulation;
      "assume_flat=" ^ string_of_bool assume_flat;
      "require_closed=" ^ optional_bool_key require_closed;
      "left_piece_group=" ^ piece_key left_piece_group;
      "overlap_piece_group=" ^ piece_key overlap_piece_group;
      "right_piece_group=" ^ piece_key right_piece_group])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|left; right|] (fun ~node_id:_ context inputs ->
      match Pdk.Boolean.run ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~operation ~left_treatment
          ~right_treatment ~resolve_left_self_intersections
          ~resolve_right_self_intersections ~point_conflict ~point_tolerance
          ~tiny_seam_threshold ~cleanup_max_batches ~strict_cleanup
          ~seam_points ~detriangulation ~assume_flat ?require_closed
          ~left_piece_group ~overlap_piece_group ~right_piece_group
          ~right:inputs.(1) inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let boolean_seam ?label ?(output = Pdk.Boolean.Seam_curves)
    ?(left_treatment = Pdk.Boolean.Solid)
    ?(right_treatment = Pdk.Boolean.Solid)
    ?(resolve_left_self_intersections = false)
    ?(resolve_right_self_intersections = false)
    ?(left_self_group = Some "boolean_left_self_seam")
    ?(between_group = Some "boolean_seam")
    ?(right_self_group = Some "boolean_right_self_seam")
    ?(coincident_group = Some "boolean_coincident") ~right left =
  let names = match output with
    | Pdk.Boolean.Seam_curves ->
        [left_self_group; between_group; right_self_group]
    | Pdk.Boolean.Coincident_patches -> [coincident_group] in
  let names = List.filter_map Fun.id names in
  if List.exists (fun name -> String.trim name = "") names then
    invalid_arg "Sop.boolean_seam: empty output group name";
  let names = List.sort String.compare names in
  let rec duplicate = function
    | first :: (second :: _ as rest) ->
        String.equal first second || duplicate rest
    | [] | [_] -> false in
  if duplicate names then
    invalid_arg "Sop.boolean_seam: output group names must be distinct";
  let output_key = function
    | Pdk.Boolean.Seam_curves -> "curves"
    | Pdk.Boolean.Coincident_patches -> "coincident" in
  let treatment_key = function
    | Pdk.Boolean.Solid -> "solid"
    | Pdk.Boolean.Surface -> "surface" in
  let curve_key value = option_string_key
      (if output = Pdk.Boolean.Seam_curves then value else None)
  and coincident_key value = option_string_key
      (if output = Pdk.Boolean.Coincident_patches then value else None) in
  Node.Private.make ?label ~operation:"boolean_seam" ~version:1
    ~parameters:(String.concat ";" [
      "output=" ^ output_key output;
      "left_treatment=" ^ treatment_key left_treatment;
      "right_treatment=" ^ treatment_key right_treatment;
      "resolve_left_self_intersections=" ^
        string_of_bool resolve_left_self_intersections;
      "resolve_right_self_intersections=" ^
        string_of_bool resolve_right_self_intersections;
      "left_self_group=" ^ curve_key left_self_group;
      "between_group=" ^ curve_key between_group;
      "right_self_group=" ^ curve_key right_self_group;
      "coincident_group=" ^ coincident_key coincident_group])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|left;right|] (fun ~node_id:_ context inputs ->
      match Pdk.Boolean.seam ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~output ~left_treatment
          ~right_treatment ~resolve_left_self_intersections
          ~resolve_right_self_intersections ~left_self_group ~between_group
          ~right_self_group ~coincident_group ~right:inputs.(1) inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let boolean_detect ?label ?source_group ?collision_group ?(tolerance = 0.)
    ?(include_coplanar = true) ?intersecting_group
    ?intersections_attribute ?count_attribute ?self_intersecting_group
    ?self_intersections_attribute ?self_count_attribute ?collision input =
  if collision = None && collision_group <> None then
    invalid_arg "Sop.boolean_detect: collision_group requires a collision input";
  let intersecting_group = match intersecting_group, collision with
    | None, Some _ -> Some "boolean_intersections"
    | None, None -> None
    | Some value, _ -> value in
  let self_intersecting_group = match self_intersecting_group, collision with
    | None, None -> Some "boolean_self_intersections"
    | None, Some _ -> None
    | Some value, _ -> value in
  List.iter (fun (kind, value) -> Option.iter (fun name ->
    if String.trim name = "" then invalid_arg
        (Printf.sprintf "Sop.boolean_detect: empty %s name" kind)) value)
    ["source primitive group", source_group;
     "collision primitive group", collision_group;
     "intersecting group", intersecting_group;
     "intersections attribute", intersections_attribute;
     "count attribute", count_attribute;
     "self-intersecting group", self_intersecting_group;
     "self-intersections attribute", self_intersections_attribute;
     "self-count attribute", self_count_attribute];
  if intersecting_group = None && intersections_attribute = None
      && count_attribute = None && self_intersecting_group = None
      && self_intersections_attribute = None && self_count_attribute = None then
    invalid_arg "Sop.boolean_detect: at least one output must be requested";
  let attribute_names = List.filter_map Fun.id [intersections_attribute;
      count_attribute; self_intersections_attribute; self_count_attribute] in
  let group_names = List.filter_map Fun.id
      [intersecting_group; self_intersecting_group] in
  let duplicates names =
    let names = List.sort String.compare names in
    let rec loop = function
      | left :: (right :: _ as rest) -> String.equal left right || loop rest
      | [] | [_] -> false in
    loop names in
  if duplicates attribute_names then
       invalid_arg
         "Sop.boolean_detect: attribute outputs must have distinct names";
  if duplicates group_names then
    invalid_arg "Sop.boolean_detect: group outputs must have distinct names";
  if collision = None && (intersecting_group <> None
      || intersections_attribute <> None || count_attribute <> None) then
    invalid_arg "Sop.boolean_detect: AxB outputs require a collision input";
  let inputs = match collision with None -> [|input|]
    | Some collision -> [|input; collision|] in
  Node.Private.make ?label ~operation:"boolean_detect" ~version:1
    ~parameters:(String.concat ";" [
      "source_group=" ^ option_string_key source_group;
      "collision_group=" ^ option_string_key collision_group;
      "tolerance=" ^ float_key tolerance;
      "include_coplanar=" ^ string_of_bool include_coplanar;
      "intersecting_group=" ^ option_string_key intersecting_group;
      "intersections_attribute=" ^ option_string_key intersections_attribute;
      "count_attribute=" ^ option_string_key count_attribute;
      "self_intersecting_group=" ^ option_string_key self_intersecting_group;
      "self_intersections_attribute=" ^ option_string_key self_intersections_attribute;
      "self_count_attribute=" ^ option_string_key self_count_attribute;
      "collision_input=" ^ string_of_bool (collision <> None)])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs (fun ~node_id:_ context inputs ->
      match resolve_optional_primitive_group "boolean_detect" source_group
          inputs.(0) with
      | Error error -> Error error
      | Ok source_primitives ->
          let collision_geometry = if Array.length inputs = 1 then inputs.(0)
            else inputs.(1) in
          (match resolve_optional_primitive_group "boolean_detect collision"
              collision_group collision_geometry with
           | Error error -> Error error
           | Ok collision_primitives ->
               match Pdk.Ops.boolean_detect
                   ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ?source_primitives
                   ?collision_primitives ~tolerance ~include_coplanar
                   ~intersecting_group ?intersections_attribute
                   ?count_attribute ?self_intersecting_group
                   ?self_intersections_attribute ?self_count_attribute
                   ~collision:collision_geometry inputs.(0) with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let intersection_analysis ?label ?source_group ?collision_group
    ?(tolerance = 0.) ?(include_coplanar = true)
    ?(input_attribute = Some "sourceinput")
    ?(primitive_attribute = Some "sourceprim")
    ?(primitive_uvw_attribute = Some "sourceprimuv")
    ?(point_attribute = Some "sourcepoint") ?collision input =
  if collision = None && collision_group <> None then invalid_arg
      "Sop.intersection_analysis: collision_group requires a collision input";
  List.iter (fun (kind, value) -> Option.iter (fun name ->
    if String.trim name = "" then invalid_arg
        (Printf.sprintf "Sop.intersection_analysis: empty %s name" kind)) value)
    ["source primitive group", source_group;
     "collision primitive group", collision_group;
     "input attribute", input_attribute;
     "primitive attribute", primitive_attribute;
     "primitive UVW attribute", primitive_uvw_attribute;
     "point attribute", point_attribute];
  let names = List.sort String.compare (List.filter_map Fun.id
      [input_attribute; primitive_attribute; primitive_uvw_attribute;
       point_attribute]) in
  let rec duplicates = function
    | left :: (right :: _ as rest) -> String.equal left right || duplicates rest
    | [] | [_] -> false in
  if duplicates names then invalid_arg
      "Sop.intersection_analysis: output attribute names must be distinct";
  let inputs = match collision with None -> [|input|]
    | Some collision -> [|input; collision|] in
  Node.Private.make ?label ~operation:"intersection_analysis" ~version:1
    ~parameters:(String.concat ";" [
      "source_group=" ^ option_string_key source_group;
      "collision_group=" ^ option_string_key collision_group;
      "tolerance=" ^ float_key tolerance;
      "include_coplanar=" ^ string_of_bool include_coplanar;
      "input_attribute=" ^ option_string_key input_attribute;
      "primitive_attribute=" ^ option_string_key primitive_attribute;
      "primitive_uvw_attribute=" ^ option_string_key primitive_uvw_attribute;
      "point_attribute=" ^ option_string_key point_attribute;
      "collision_input=" ^ string_of_bool (collision <> None)])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      match resolve_optional_primitive_group "intersection_analysis"
          source_group inputs.(0) with
      | Error error -> Error error
      | Ok source_primitives ->
          let collision_geometry = if Array.length inputs = 1 then None
            else Some inputs.(1) in
          let group_geometry = match collision_geometry with
            | None -> inputs.(0) | Some geometry -> geometry in
          (match resolve_optional_primitive_group "intersection_analysis collision"
              collision_group group_geometry with
           | Error error -> Error error
           | Ok collision_primitives ->
               match Pdk.Ops.intersection_analysis
                   ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ?source_primitives
                   ?collision_primitives ~tolerance ~include_coplanar
                   ~input_attribute ~primitive_attribute
                   ~primitive_uvw_attribute ~point_attribute
                   ?collision:collision_geometry inputs.(0) with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let poly_reduce_target_key = function
  | Pdk.Ops.Reduce_ratio ratio -> "ratio:" ^ float_key ratio
  | Pdk.Ops.Reduce_primitive_count count -> "primitives:" ^ string_of_int count

let poly_reduce ?label ?group ?hard_point_group ?hard_edge_group
    ?(target = Pdk.Ops.Reduce_ratio 0.5) ?(preserve_boundary = true)
    ?(only_original_positions = false) ?(equalize_lengths = 1e-10)
    ?max_normal_deviation ?output_group ?(recompute_point_normals = true) input =
  List.iter (fun (label, value) -> Option.iter (fun name ->
    if String.trim name = "" then invalid_arg
        (Printf.sprintf "Sop.poly_reduce: empty %s name" label)) value)
    ["primitive group", group; "hard point group", hard_point_group;
     "hard edge group", hard_edge_group; "output group", output_group];
  Node.Private.make ?label ~operation:"poly_reduce" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "hard_points=" ^ option_string_key hard_point_group;
      "hard_edges=" ^ option_string_key hard_edge_group;
      "target=" ^ poly_reduce_target_key target;
      "preserve_boundary=" ^ string_of_bool preserve_boundary;
      "only_original_positions=" ^ string_of_bool only_original_positions;
      "equalize_lengths=" ^ float_key equalize_lengths;
      "max_normal_deviation=" ^ option_float_key max_normal_deviation;
      "output_group=" ^ option_string_key output_group;
      "recompute_point_normals=" ^ string_of_bool recompute_point_normals])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "poly_reduce could not find primitive group %S" name))) in
      let hard_points = match hard_point_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "poly_reduce could not find hard point group %S" name))) in
      let hard_edges = match hard_edge_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "poly_reduce could not find hard edge group %S" name))) in
      match primitives, hard_points, hard_edges with
      | Error error, _, _ | _, Error error, _ | _, _, Error error -> Error error
      | Ok primitives, Ok hard_points, Ok hard_edges ->
          match Pdk.Ops.poly_reduce ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~target ?primitives ?hard_points
              ?hard_edges ~preserve_boundary ~only_original_positions
              ~equalize_lengths ?max_normal_deviation ?output_group
              ~recompute_point_normals geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let reverse_operation_key = function
  | Pdk.Ops.Reverse_vertices -> "reverse"
  | Pdk.Ops.Shift_vertices offset -> "shift:" ^ string_of_int offset

let reverse ?label ?group ?(operation = Pdk.Ops.Reverse_vertices) input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.reverse: empty primitive group name") group;
  Node.Private.make ?label ~operation:"reverse" ~version:2
    ~parameters:(Printf.sprintf "group=%s;operation=%s"
      (option_string_key group) (reverse_operation_key operation))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "reverse could not find primitive group %S" name))) in
      match primitives with
      | Error error -> Error error
      | Ok primitives ->
          match Pdk.Ops.reverse ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ~operation geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let normal_owner_key = function
  | Pdk.Attribute.Point -> "point"
  | Vertex -> "vertex"
  | Primitive -> "primitive"
  | Detail -> "detail"

let normal_weighting_key = function
  | Pdk.Ops.Vertex_angle -> "vertex_angle"
  | Each_vertex -> "each_vertex"
  | Face_area -> "face_area"

let normals ?label ?selection ?(owner = Pdk.Attribute.Point)
    ?(weighting = Pdk.Ops.Face_area) ?(cusp_angle = Float.pi)
    ?(keep_original_zero = false) ?(reverse = false) ?(attribute = "N") input =
  if String.trim attribute = "" then
    invalid_arg "Sop.normals: empty attribute name";
  Node.Private.make ?label ~operation:"normals" ~version:2
    ~parameters:(Printf.sprintf
      "selection=%s;owner=%s;weighting=%s;cusp=%s;keep_zero=%b;reverse=%b;attribute=%S"
      (match selection with None -> "none" | Some value -> element_group_key value)
      (normal_owner_key owner) (normal_weighting_key weighting)
      (float_key cusp_angle) keep_original_zero reverse attribute)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"normals" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.normals ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~owner ~weighting
              ~cusp_angle ~keep_original_zero ~reverse ~attribute inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let polyframe_style_key = function
  | Pdk.Ops.First_edge -> "first_edge"
  | Pdk.Ops.Two_edges -> "two_edges"
  | Pdk.Ops.Primitive_centroid -> "primitive_centroid"
  | Pdk.Ops.Texture_uv name -> "texture_uv:" ^ String.escaped
      (if String.trim name = "" then "uv" else name)
  | Pdk.Ops.Texture_uv_gradient name ->
      "texture_uv_gradient:" ^ String.escaped
        (if String.trim name = "" then "uv" else name)
  | Pdk.Ops.Attribute_gradient name ->
      "attribute_gradient:" ^ String.escaped name

let polyframe ?label ?selection ?(orthogonal = false)
    ?(left_handed = false) ?(normal_attribute = "N")
    ?(tangent_attribute = Some "tangentu")
    ?(bitangent_attribute = Some "tangentv") style input =
  let parameters = String.concat ";" [
      "style=" ^ polyframe_style_key style;
      "selection=" ^ (match selection with
        | None -> "none" | Some value -> element_group_key value);
      "orthogonal=" ^ string_of_bool orthogonal;
      "left_handed=" ^ string_of_bool left_handed;
      "normal_attribute=" ^ String.escaped normal_attribute;
      "tangent_attribute=" ^ option_string_key tangent_attribute;
      "bitangent_attribute=" ^ option_string_key bitangent_attribute;
    ] in
  Node.Private.make ?label ~operation:"polyframe" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"polyframe" selection inputs.(0) with
      | Error _ as error -> error
      | Ok selection ->
          match Pdk.Ops.polyframe ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~orthogonal
              ~left_handed ~normal_attribute ~tangent_attribute
              ~bitangent_attribute style inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let smooth_boundary_key = function
  | Pdk.Ops.Smooth_free -> "free"
  | Pdk.Ops.Smooth_unshared -> "unshared"
  | Pdk.Ops.Smooth_group_boundary -> "group_boundary"

let smooth_method_key = function
  | Pdk.Attribute_ops.Uniform -> "uniform"
  | Pdk.Attribute_ops.Edge_length -> "edge_length"

let smooth_mode_key = function
  | Pdk.Attribute_ops.Laplacian step -> "laplacian:" ^ float_key step
  | Pdk.Attribute_ops.Custom_steps { odd; even } ->
      String.concat ":" ["custom"; float_key odd; float_key even]

let smooth ?label ?group ?constrained_points
    ?(boundary = Pdk.Ops.Smooth_free) ?(iterations = 1)
    ?(method_ = Pdk.Attribute_ops.Uniform)
    ?(mode = Pdk.Attribute_ops.Laplacian 0.5) ?weight_attribute
    ?alpha_attribute ?(recompute_normals = true) ?(original_blend = 0.)
    ?(smoothed_blend = 1.) ~attributes input =
  (match Pdk.Attribute_pattern.compile attributes with
   | Ok _ -> ()
   | Error message -> invalid_arg ("Sop.smooth: " ^ message));
  List.iter (fun (name, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.smooth: empty " ^ name)
    | None | Some _ -> ())
    ["primitive group", group; "constrained point group", constrained_points;
     "weight attribute", weight_attribute; "alpha attribute", alpha_attribute];
  Node.Private.make ?label ~operation:"smooth" ~version:1
    ~parameters:(String.concat ";" [
      "attributes=" ^ String.escaped attributes;
      "group=" ^ option_string_key group;
      "constrained_points=" ^ option_string_key constrained_points;
      "boundary=" ^ smooth_boundary_key boundary;
      "iterations=" ^ string_of_int iterations;
      "method=" ^ smooth_method_key method_;
      "mode=" ^ smooth_mode_key mode;
      "weight=" ^ option_string_key weight_attribute;
      "alpha=" ^ option_string_key alpha_attribute;
      "recompute_normals=" ^ string_of_bool recompute_normals;
      "original_blend=" ^ float_key original_blend;
      "smoothed_blend=" ^ float_key smoothed_blend])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let resolve owner code kind = function
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code
                 (Printf.sprintf "smooth could not find %s %S" kind name))) in
      match resolve Pdk.Group.Primitive "missing_group" "primitive group" group with
      | Error error -> Error error
      | Ok primitives ->
          (match resolve Pdk.Group.Point "missing_constrained_points"
              "constrained point group" constrained_points with
           | Error error -> Error error
           | Ok constrained_points ->
               match Pdk.Ops.smooth ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ?primitives
                   ?constrained_points ~boundary ~iterations ~method_ ~mode
                   ?weight_attribute ?alpha_attribute ~recompute_normals
                   ~original_blend ~smoothed_blend ~attributes geometry with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let clean_overlap_key = function
  | Pdk.Ops.Keep_first_overlap -> "keep_first"
  | Pdk.Ops.Delete_overlap_pairs -> "delete_pairs"

let clean ?label ?epsilon ?(remove_degenerate = true) ?consolidate_distance
    ?overlaps ?(reverse_winding = false) ?(remove_nan_points = false)
    ?(remove_unused_points = false) ?(delete_unused_groups = false)
    ?point_attributes ?vertex_attributes ?primitive_attributes ?detail_attributes
    ?point_groups ?vertex_groups ?primitive_groups ?edge_groups input =
  let epsilon_key = match epsilon with
    | None -> "default" | Some value -> float_key value in
  let distance_key = match consolidate_distance with
    | None -> "none" | Some value -> float_key value in
  let overlap_key = match overlaps with
    | None -> "none" | Some value -> clean_overlap_key value in
  Node.Private.make ?label ~operation:"clean" ~version:2
    ~parameters:(String.concat ";" [
      "epsilon=" ^ epsilon_key;
      "remove_degenerate=" ^ string_of_bool remove_degenerate;
      "consolidate_distance=" ^ distance_key;
      "overlaps=" ^ overlap_key;
      "reverse_winding=" ^ string_of_bool reverse_winding;
      "remove_nan_points=" ^ string_of_bool remove_nan_points;
      "remove_unused_points=" ^ string_of_bool remove_unused_points;
      "delete_unused_groups=" ^ string_of_bool delete_unused_groups;
      "point_attributes=" ^ option_string_key point_attributes;
      "vertex_attributes=" ^ option_string_key vertex_attributes;
      "primitive_attributes=" ^ option_string_key primitive_attributes;
      "detail_attributes=" ^ option_string_key detail_attributes;
      "point_groups=" ^ option_string_key point_groups;
      "vertex_groups=" ^ option_string_key vertex_groups;
      "primitive_groups=" ^ option_string_key primitive_groups;
      "edge_groups=" ^ option_string_key edge_groups])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Ops.clean ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?epsilon ~remove_degenerate
          ?consolidate_distance ?overlaps ~reverse_winding ~remove_nan_points
          ~remove_unused_points ~delete_unused_groups ?point_attributes
          ?vertex_attributes ?primitive_attributes ?detail_attributes
          ?point_groups ?vertex_groups ?primitive_groups ?edge_groups inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let facet ?label ?group ?selection ?(pre_compute_normals = false)
    ?(make_normals_unit_length = false) ?(unique_points = false)
    ?consolidate_distance ?consolidate_normals_distance
    ?(remove_inline_points = false)
    ?(inline_distance = 0.) ?(orient_polygons = false) ?cusp_angle
    ?(remove_degenerate = false) ?(make_planar = false)
    ?(post_compute_normals = false) ?(reverse_normals = false) input =
  let selection = match group, selection with
    | Some _, Some _ -> invalid_arg
        "Sop.facet: group and typed selection are mutually exclusive"
    | Some name, None -> Some (Primitive_group name)
    | None, selection -> selection in
  (match selection with
   | Some selection ->
       let name = match selection with Point_group name | Vertex_group name
         | Primitive_group name | Edge_group name -> name in
       if String.trim name = "" then
         invalid_arg "Sop.facet: empty selection group name"
   | None -> ());
  let distance = match consolidate_distance with
    | None -> "none" | Some value -> float_key value in
  let normal_distance = match consolidate_normals_distance with
    | None -> "none" | Some value -> float_key value in
  let cusp = match cusp_angle with
    | None -> "none" | Some value -> float_key value in
  Node.Private.make ?label ~operation:"facet" ~version:4
    ~parameters:(String.concat ";" [
      "selection=" ^ (match selection with
        | None -> "none" | Some value -> element_group_key value);
      "pre_compute_normals=" ^ string_of_bool pre_compute_normals;
      "make_normals_unit_length=" ^ string_of_bool make_normals_unit_length;
      "unique_points=" ^ string_of_bool unique_points;
      "consolidate_distance=" ^ distance;
      "consolidate_normals_distance=" ^ normal_distance;
      "remove_inline_points=" ^ string_of_bool remove_inline_points;
      "inline_distance=" ^ float_key inline_distance;
      "orient_polygons=" ^ string_of_bool orient_polygons;
      "cusp_angle=" ^ cusp;
      "remove_degenerate=" ^ string_of_bool remove_degenerate;
      "make_planar=" ^ string_of_bool make_planar;
      "post_compute_normals=" ^ string_of_bool post_compute_normals;
      "reverse_normals=" ^ string_of_bool reverse_normals])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_element_group ~operation:"facet" selection geometry with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.facet ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~pre_compute_normals
              ~make_normals_unit_length ~unique_points ?consolidate_distance
              ?consolidate_normals_distance ~remove_inline_points
              ~inline_distance ~orient_polygons ?cusp_angle ~remove_degenerate
              ~make_planar ~post_compute_normals ~reverse_normals geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let poly_extrude_divide_key = function
  | Pdk.Ops.Extrude_individual -> "individual"
  | Pdk.Ops.Extrude_connected_components -> "connected_components"

let poly_extrude ?label ?group ?split_edges
    ?(divide = Pdk.Ops.Extrude_individual) ?(divisions = 1)
    ?(output_front = true) ?(output_back = true) ?(output_side = true)
    ?front_group ?back_group ?side_group ?front_boundary_group
    ?back_boundary_group ~distance input =
  if divisions <= 0 then invalid_arg "Sop.poly_extrude: divisions must be positive";
  List.iter (fun (kind, value) -> match value with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.poly_extrude: empty " ^ kind ^ " group name")
    | None | Some _ -> ())
    ["selection", group; "split edge", split_edges; "front", front_group;
     "back", back_group; "side", side_group;
     "front boundary", front_boundary_group;
     "back boundary", back_boundary_group];
  Node.Private.make ?label ~operation:"poly_extrude" ~version:2
    ~parameters:(String.concat ";" [
      "distance=" ^ float_key distance;
      "group=" ^ option_string_key group;
      "split_edges=" ^ option_string_key split_edges;
      "divide=" ^ poly_extrude_divide_key divide;
      "divisions=" ^ string_of_int divisions;
      "output_front=" ^ string_of_bool output_front;
      "output_back=" ^ string_of_bool output_back;
      "output_side=" ^ string_of_bool output_side;
      "front_group=" ^ option_string_key front_group;
      "back_group=" ^ option_string_key back_group;
      "side_group=" ^ option_string_key side_group;
      "front_boundary_group=" ^ option_string_key front_boundary_group;
      "back_boundary_group=" ^ option_string_key back_boundary_group])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "poly_extrude could not find primitive group %S" name))) in
      let split = match split_edges with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "poly_extrude could not find edge split group %S" name))) in
      match primitives, split with
      | Error error, _ | _, Error error -> Error error
      | Ok primitives, Ok split_edges ->
          match Pdk.Ops.poly_extrude ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ?split_edges ~divide
              ~divisions ~output_front ~output_back ~output_side ?front_group
              ?back_group ?side_group ?front_boundary_group
              ?back_boundary_group ~distance geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let poly_fill_mode_key = function
  | Pdk.Ops.Fill_single_polygon -> "single_polygon"
  | Pdk.Ops.Fill_triangles -> "triangles"
  | Pdk.Ops.Fill_triangle_fan -> "triangle_fan"

let poly_fill ?label ?boundary_group ?(mode = Pdk.Ops.Fill_triangles)
    ?(reverse_patches = false) ?(unique_points = false)
    ?(update_point_normals = false) ?patch_group input =
  List.iter (fun (label, name) -> match name with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.poly_fill: empty " ^ label ^ " group name")
    | None | Some _ -> ())
    ["boundary", boundary_group; "patch", patch_group];
  Node.Private.make ?label ~operation:"poly_fill" ~version:1
    ~parameters:(String.concat ";" [
      "boundary_group=" ^ option_string_key boundary_group;
      "mode=" ^ poly_fill_mode_key mode;
      "reverse_patches=" ^ string_of_bool reverse_patches;
      "unique_points=" ^ string_of_bool unique_points;
      "update_point_normals=" ^ string_of_bool update_point_normals;
      "patch_group=" ^ option_string_key patch_group])
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let boundary = match boundary_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "poly_fill could not find boundary edge group %S" name))) in
      match boundary with
      | Error error -> Error error
      | Ok boundary ->
          match Pdk.Ops.poly_fill ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?boundary ~mode ~reverse_patches
              ~unique_points ~update_point_normals ?patch_group geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let resample ?label ?group ?segments ?maximum_segment_length
    ?segment_length_attribute ?segments_attribute ?(even_last_segment = true)
    ?curve_u_attribute ?curve_number_attribute ?distance_attribute
    ?tangent_attribute input =
  let option_int = function None -> "none" | Some value -> string_of_int value in
  let generated_names = [curve_u_attribute; curve_number_attribute;
    distance_attribute; tangent_attribute] |> List.filter_map Fun.id in
  List.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.resample: generated attribute names must not be empty")
    generated_names;
  List.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.resample: group/override names must not be empty")
    ([group; segment_length_attribute; segments_attribute]
      |> List.filter_map Fun.id);
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "segments=" ^ option_int segments;
      "maximum_segment_length=" ^ option_float_key maximum_segment_length;
      "segment_length_attribute=" ^ option_string_key segment_length_attribute;
      "segments_attribute=" ^ option_string_key segments_attribute;
      "even_last_segment=" ^ string_of_bool even_last_segment;
      "curve_u_attribute=" ^ option_string_key curve_u_attribute;
      "curve_number_attribute=" ^ option_string_key curve_number_attribute;
      "distance_attribute=" ^ option_string_key distance_attribute;
      "tangent_attribute=" ^ option_string_key tangent_attribute;
    ] in
  Node.Private.make ?label ~operation:"resample" ~version:2 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name
                inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "resample could not find primitive group %S"
                   name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.resample_curves ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ?segments
              ?maximum_segment_length ?segment_length_attribute
              ?segments_attribute ~even_last_segment ?curve_u_attribute
              ?curve_number_attribute ?distance_attribute ?tangent_attribute
              inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

type extract_point_cut =
  | Extract_point_constant of float
  | Extract_point_primitive_attribute of string
  | Extract_point_current_time

let extract_point_cut_key = function
  | Extract_point_constant value -> "constant:" ^ float_key value
  | Extract_point_primitive_attribute name ->
      "primitive_attribute:" ^ String.escaped name
  | Extract_point_current_time -> "current_time"

let extract_point_from_curve ?label ?group
    ?(cut = Extract_point_constant 0.) ?(point_attributes = "P")
    ?(copy_primitive_attributes = false) ?(primitive_attributes = "*")
    ?curve_u_attribute ?number_cuts_attribute ?curve_number_attribute
    ~distance_attribute input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.extract_point_from_curve: empty primitive group name") group;
  if String.trim distance_attribute = "" || distance_attribute = "P" then
    invalid_arg
      "Sop.extract_point_from_curve: distance attribute must be non-empty and not P";
  (match cut with
   | Extract_point_constant value when not (Float.is_finite value) ->
       invalid_arg "Sop.extract_point_from_curve: cut value must be finite"
   | Extract_point_primitive_attribute name
       when String.trim name = "" || name = "P" ->
       invalid_arg
         "Sop.extract_point_from_curve: cut attribute must be non-empty and not P"
   | Extract_point_constant _ | Extract_point_primitive_attribute _
   | Extract_point_current_time -> ());
  List.iter (fun (role, name) -> match name with
    | Some name when String.trim name = "" || name = "P" ->
        invalid_arg ("Sop.extract_point_from_curve: " ^ role
          ^ " must be non-empty and not P")
    | None | Some _ -> ()) [
      "curve U attribute", curve_u_attribute;
      "number of cuts attribute", number_cuts_attribute;
      "curve number attribute", curve_number_attribute];
  let dependencies = match cut with
    | Extract_point_current_time ->
        Context.Dependencies.one Context.Dependencies.Time
    | Extract_point_constant _ | Extract_point_primitive_attribute _ ->
        Context.Dependencies.static in
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "cut=" ^ extract_point_cut_key cut;
      "distance_attribute=" ^ String.escaped distance_attribute;
      "point_attributes=" ^ String.escaped point_attributes;
      "copy_primitive_attributes=" ^ string_of_bool copy_primitive_attributes;
      "primitive_attributes=" ^ String.escaped primitive_attributes;
      "curve_u_attribute=" ^ option_string_key curve_u_attribute;
      "number_cuts_attribute=" ^ option_string_key number_cuts_attribute;
      "curve_number_attribute=" ^ option_string_key curve_number_attribute] in
  Node.Private.make ?label ~operation:"extract_point_from_curve" ~version:1
    ~parameters ~cook_mode:Node.Generic ~dependencies ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match resolve_optional_primitive_group "extract_point_from_curve" group
          geometry with
      | Error error -> Error error
      | Ok primitives ->
          let cut = match cut with
            | Extract_point_constant value ->
                Pdk.Ops.Extract_cut_constant value
            | Extract_point_primitive_attribute name ->
                Pdk.Ops.Extract_cut_primitive_attribute name
            | Extract_point_current_time ->
                Pdk.Ops.Extract_cut_constant (Context.time context) in
          match Pdk.Ops.extract_point_from_curve
              ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ~cut ~point_attributes
              ~copy_primitive_attributes ~primitive_attributes
              ?curve_u_attribute ?number_cuts_attribute ?curve_number_attribute
              ~distance_attribute geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let convert_line ?label ?group ?(connect_path = false)
    ?(maximum_distance = 0.001)
    ?(connect_only_to_other_end_points = false)
    ?(make_isolated_loops_closed = false) ?(remove_unused_points = false)
    ?length_attribute input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.convert_line: empty edge group name") group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.convert_line: empty length attribute name") length_attribute;
  Node.Private.make ?label ~operation:"convert_line" ~version:2
    ~parameters:(Printf.sprintf
      "group=%S;connect_path=%b;maximum_distance=%s;connect_only_to_other_end_points=%b;make_isolated_loops_closed=%b;remove_unused_points=%b;length_attribute=%S"
      (Option.value ~default:"" group) connect_path
      (float_key maximum_distance) connect_only_to_other_end_points
      make_isolated_loops_closed remove_unused_points
      (Option.value ~default:"" length_attribute))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let edges = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the native edge group before Convert Line"]
                 (Printf.sprintf "convert_line could not find edge group %S"
                   name))) in
      match edges with
      | Error _ as error -> error
      | Ok edges ->
          match Pdk.Ops.convert_line ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?edges ~connect_path
              ~maximum_distance ~connect_only_to_other_end_points
              ~make_isolated_loops_closed ~remove_unused_points
              ?length_attribute inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let carve_keep_key = function
  | Pdk.Ops.Keep_inside -> "inside"
  | Pdk.Ops.Keep_outside -> "outside"
  | Pdk.Ops.Keep_inside_and_outside -> "inside_and_outside"

let carve_attribute_mode_key = function
  | Pdk.Ops.Attribute_replace -> "replace"
  | Pdk.Ops.Attribute_scale -> "scale"

let carve ?label ?group ?(relative_arc_length = true) ?(first = 0.) ?(last = 1.)
    ?first_attribute ?last_attribute
    ?(attribute_mode = Pdk.Ops.Attribute_replace)
    ?(only_at_breakpoints = false) ?(cut_at_all_internal_breakpoints = false)
    ?(keep = Pdk.Ops.Keep_inside) ?(extract_points = false)
    ?(divisions = 1) ?(keep_original = false) input =
  if divisions <= 0 then invalid_arg "Sop.carve: divisions must be positive";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.carve: empty primitive group name") group;
  List.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.carve: empty primitive parameter attribute name")
    (List.filter_map Fun.id [first_attribute; last_attribute]);
  Node.Private.make ?label ~operation:"carve" ~version:7
    ~parameters:(Printf.sprintf "group=%S;relative_arc_length=%b;first=%s;last=%s;first_attribute=%S;last_attribute=%S;attribute_mode=%s;only_at_breakpoints=%b;cut_at_all_internal_breakpoints=%b;keep=%s;extract_points=%b;divisions=%d;keep_original=%b"
      (Option.value ~default:"" group) relative_arc_length
      (float_key first) (float_key last)
      (Option.value ~default:"" first_attribute)
      (Option.value ~default:"" last_attribute)
      (carve_attribute_mode_key attribute_mode) only_at_breakpoints
      cut_at_all_internal_breakpoints (carve_keep_key keep)
      extract_points divisions keep_original)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name
                inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "carve could not find primitive group %S" name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.carve_curves ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ~relative_arc_length
              ~first ~last ?first_attribute ?last_attribute ~attribute_mode
              ~only_at_breakpoints ~cut_at_all_internal_breakpoints
              ~keep ~extract_points ~divisions ~keep_original
              inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let curve_end_mode_key = function
  | Pdk.Ops.Open_curve -> "open"
  | Pdk.Ops.Close_curve -> "close"
  | Pdk.Ops.Unroll_curve -> "unroll"

let curve_ends ?label ?group mode input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.curve_ends: empty primitive group name") group;
  Node.Private.make ?label ~operation:"curve_ends" ~version:1
    ~parameters:(Printf.sprintf "group=%S;mode=%s"
      (Option.value ~default:"" group) (curve_end_mode_key mode))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
                name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the primitive group before Curve Ends"]
                 (Printf.sprintf "curve_ends could not find primitive group %S"
                   name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.curve_ends ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives mode inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let ends_mode_key = function
  | Pdk.Ops.Ends_open -> "open"
  | Pdk.Ops.Ends_close_straight -> "close_straight"
  | Pdk.Ops.Ends_unroll_shared -> "unroll_shared"
  | Pdk.Ops.Ends_unroll_new -> "unroll_new"

let ends ?label ?group mode input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.ends: empty primitive group name") group;
  Node.Private.make ?label ~operation:"ends" ~version:1
    ~parameters:(Printf.sprintf "group=%S;mode=%s"
      (Option.value ~default:"" group) (ends_mode_key mode))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
                name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the primitive group before Ends"]
                 (Printf.sprintf "ends could not find primitive group %S" name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.ends ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives mode inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let curve_join_end_key = function
  | Pdk.Ops.Join_curve_start -> "start"
  | Pdk.Ops.Join_curve_end -> "end"

let curve_join_picks_key picks =
  String.concat "," (Array.to_list (Array.map (fun pick ->
    Printf.sprintf "%d:%s" pick.Pdk.Ops.primitive
      (curve_join_end_key pick.end_)) picks))

let join_curves ?label ?group ?picked_ends ?(orient_closest = true)
    ?(connect_closest_ends = false) ?(only_connected = false)
    ?group_size ?(keep_originals = false) ?(tolerance = 0.)
    ?(wrap = false) input =
  let picked_ends = Option.map Array.copy picked_ends in
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.join_curves: empty primitive group name") group;
  Option.iter (fun size -> if size <= 0 then
    invalid_arg "Sop.join_curves: group_size must be positive") group_size;
  (match group, picked_ends with
   | Some _, Some _ -> invalid_arg
       "Sop.join_curves: group and picked_ends are mutually exclusive"
   | None, _ | _, None -> ());
  (match picked_ends with
   | Some _ when connect_closest_ends -> invalid_arg
       "Sop.join_curves: picked_ends and connect_closest_ends are mutually exclusive"
   | None | Some _ -> ());
  Node.Private.make ?label ~operation:"join_curves" ~version:4
    ~parameters:(Printf.sprintf
      "group=%S;picked_ends=%s;orient_closest=%b;connect_closest_ends=%b;only_connected=%b;group_size=%s;keep_originals=%b;tolerance=%s;wrap=%b"
      (Option.value ~default:"" group)
      (match picked_ends with None -> "none" | Some picks -> curve_join_picks_key picks)
      orient_closest connect_closest_ends
      only_connected (match group_size with None -> "all" | Some size -> string_of_int size)
      keep_originals (float_key tolerance) wrap)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
                name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the primitive group before Curve Join"]
                 (Printf.sprintf "join_curves could not find primitive group %S"
                   name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.join_curves ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ?picked_ends ~orient_closest
              ~connect_closest_ends ~only_connected ?group_size ~keep_originals
              ~tolerance ~wrap inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let poly_path ?label ?(connect_end_points = false)
    ?(maximum_distance = 0.001)
    ?(connect_only_to_other_end_points = false)
    ?(make_isolated_loops_closed = false) input =
  Node.Private.make ?label ~operation:"poly_path" ~version:1
    ~parameters:(Printf.sprintf
      "connect_end_points=%b;maximum_distance=%s;connect_only_to_other_end_points=%b;make_isolated_loops_closed=%b"
      connect_end_points (float_key maximum_distance)
      connect_only_to_other_end_points make_isolated_loops_closed)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.poly_path ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~connect_end_points ~maximum_distance
          ~connect_only_to_other_end_points ~make_isolated_loops_closed
          inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let revolve_type_key = function
  | Pdk.Ops.Revolve_closed -> "closed"
  | Pdk.Ops.Revolve_open_arc -> "open_arc"

let revolve ?label ?group ?(revolve_type = Pdk.Ops.Revolve_closed)
    ?(connectivity = Pdk.Ops.Grid_quads) ?(start_angle = 0.)
    ?(end_angle = 2. *. Float.pi) ?(reverse_cross_sections = false)
    ?(caps = false) ?cap_group ?(uv_attribute = Some "uv") ~divisions
    ~origin ~axis input =
  List.iter (fun (description, name) -> match name with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.revolve: empty " ^ description)
    | None | Some _ -> ())
    ["primitive group name", group; "cap group name", cap_group;
     "UV attribute name", uv_attribute];
  let origin = vec3_copy origin and axis = vec3_copy axis in
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "type=" ^ revolve_type_key revolve_type;
      "connectivity=" ^ grid_connectivity_key connectivity;
      "start=" ^ float_key start_angle;
      "end=" ^ float_key end_angle;
      "reverse=" ^ string_of_bool reverse_cross_sections;
      "caps=" ^ string_of_bool caps;
      "cap_group=" ^ option_string_key cap_group;
      "uv=" ^ option_string_key uv_attribute;
      "divisions=" ^ string_of_int divisions;
      "origin=" ^ vec3_key origin;
      "axis=" ^ vec3_key axis ] in
  Node.Private.make ?label ~operation:"revolve" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "revolve could not find primitive group %S" name))) in
      match primitives with
      | Error error -> Error error
      | Ok primitives ->
          match Pdk.Ops.revolve ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ~revolve_type
              ~connectivity ~start_angle ~end_angle ~reverse_cross_sections
              ~caps ?cap_group ~uv_attribute ~divisions ~origin ~axis geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let sweep_tangent_key = function
  | Pdk.Ops.Sweep_average_edges -> "average_edges"
  | Pdk.Ops.Sweep_central_difference -> "central_difference"
  | Pdk.Ops.Sweep_previous_edge -> "previous_edge"
  | Pdk.Ops.Sweep_next_edge -> "next_edge"
  | Pdk.Ops.Sweep_z_axis -> "z_axis"

let sweep ?label ?backbone_group ?cross_section_group
    ?(connectivity = Pdk.Ops.Grid_quads)
    ?(tangent = Pdk.Ops.Sweep_average_edges) ?(continuous_closed = true)
    ?(transform_attributes = true) ?(reverse_cross_sections = false)
    ?(scale = 1.) ?(roll = 0.) ?(twist = 0.) ?(caps = false) ?cap_group
    ?(uv_attribute = Some "uv") ?(cross_section_prefix = "cross_section_")
    ~backbone ~cross_section () =
  List.iter (fun (description, name) -> match name with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.sweep: empty " ^ description)
    | None | Some _ -> ())
    ["backbone group", backbone_group;
     "cross-section group", cross_section_group;
     "cap group", cap_group;
     "UV attribute", uv_attribute];
  let parameters = String.concat ";" [
      "backbone_group=" ^ option_string_key backbone_group;
      "cross_section_group=" ^ option_string_key cross_section_group;
      "connectivity=" ^ grid_connectivity_key connectivity;
      "tangent=" ^ sweep_tangent_key tangent;
      "continuous_closed=" ^ string_of_bool continuous_closed;
      "transform_attributes=" ^ string_of_bool transform_attributes;
      "reverse_cross_sections=" ^ string_of_bool reverse_cross_sections;
      "scale=" ^ float_key scale;
      "roll=" ^ float_key roll;
      "twist=" ^ float_key twist;
      "caps=" ^ string_of_bool caps;
      "cap_group=" ^ option_string_key cap_group;
      "uv=" ^ option_string_key uv_attribute;
      "cross_section_prefix=" ^ Printf.sprintf "%S" cross_section_prefix ] in
  Node.Private.make ?label ~operation:"sweep" ~version:1 ~parameters
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|backbone; cross_section|] (fun ~node_id:_ context inputs ->
      let resolve input_index description name = match name with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name
                inputs.(input_index) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "sweep could not find %s primitive group %S"
                    description name))) in
      match resolve 0 "backbone" backbone_group with
      | Error error -> Error error
      | Ok backbones ->
          (match resolve 1 "cross-section" cross_section_group with
           | Error error -> Error error
           | Ok cross_sections ->
               match Pdk.Ops.sweep ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ?backbones ?cross_sections
                   ~connectivity ~tangent ~continuous_closed
                   ~transform_attributes ~reverse_cross_sections ~scale ~roll
                   ~twist ~caps ?cap_group ~uv_attribute ~cross_section_prefix
                   ~backbone:inputs.(0) ~cross_section:inputs.(1) () with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let circular_wire ?label ~operation ?group ?sides ?divisions_attribute
    ?(segments = 1) ?segments_attribute ?segment_scales
    ?segment_scales_attribute ?(prevent_joint_buckling = false)
    ?(maximum_joint_scale = 10.) ?maximum_joint_scale_attribute
    ?(smooth_point = true) ?smooth_attribute ?max_valence
    ?scale_attribute ?(seam_offset = 0)
    ?seam_attribute ?segment_seam_attribute ?v_attribute ?up_attribute
    ?(generate_uv = true) ?u_range
    ?v_range ?uv_range_attribute ?(caps = false) ?cap_group ~radius input =
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg ("Sop." ^ operation ^ ": empty primitive group name")) group;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg ("Sop." ^ operation ^ ": empty scale attribute name"))
    scale_attribute;
  List.iter (Option.iter (fun name -> if String.trim name = "" then
    invalid_arg ("Sop." ^ operation ^ ": empty attribute name")))
    [divisions_attribute; segments_attribute; segment_scales_attribute;
     maximum_joint_scale_attribute; smooth_attribute; seam_attribute;
     segment_seam_attribute; v_attribute; up_attribute; uv_range_attribute];
  if segments < 1 then invalid_arg ("Sop." ^ operation ^ ": segments must be positive");
  Option.iter (fun (first, last) ->
    if not (Float.is_finite first && Float.is_finite last)
        || first < 0. || last > 1. || first > last then
      invalid_arg ("Sop." ^ operation
        ^ ": segment scales require 0 <= first <= last <= 1")) segment_scales;
  if not (Float.is_finite maximum_joint_scale) || maximum_joint_scale < 1. then
    invalid_arg ("Sop." ^ operation
      ^ ": maximum joint scale must be finite and at least one");
  if Option.is_some maximum_joint_scale_attribute
      && not prevent_joint_buckling then
    invalid_arg ("Sop." ^ operation
      ^ ": maximum joint scale attribute requires joint buckling prevention");
  Option.iter (fun value -> if value < 1 then invalid_arg
    ("Sop." ^ operation ^ ": max valence must be positive")) max_valence;
  List.iter (Option.iter (fun (first, last) ->
    if not (Float.is_finite first && Float.is_finite last) then
      invalid_arg ("Sop." ^ operation ^ ": UV ranges must be finite")))
    [u_range; v_range];
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg ("Sop." ^ operation ^ ": empty cap group name")) cap_group;
  let range_key = function None -> "default" | Some (first, last) ->
    float_key first ^ "," ^ float_key last in
  Node.Private.make ?label ~operation ~version:7
    ~parameters:(Printf.sprintf
      "group=%S;sides=%s;divisions_attribute=%S;segments=%d;segments_attribute=%S;segment_scales=%s;segment_scales_attribute=%S;prevent_joint_buckling=%b;maximum_joint_scale=%s;maximum_joint_scale_attribute=%S;smooth_point=%b;smooth_attribute=%S;max_valence=%s;radius=%s;scale_attribute=%S;seam_offset=%d;seam_attribute=%S;segment_seam_attribute=%S;v_attribute=%S;up_attribute=%S;generate_uv=%b;u_range=%s;v_range=%s;uv_range_attribute=%S;caps=%b;cap_group=%S"
      (Option.value ~default:"" group)
      (match sides with None -> "default" | Some value -> string_of_int value)
      (Option.value ~default:"" divisions_attribute) segments
      (Option.value ~default:"" segments_attribute)
      (range_key segment_scales)
      (Option.value ~default:"" segment_scales_attribute)
      prevent_joint_buckling (float_key maximum_joint_scale)
      (Option.value ~default:"" maximum_joint_scale_attribute)
      smooth_point (Option.value ~default:"" smooth_attribute)
      (match max_valence with None -> "disabled" | Some value -> string_of_int value)
      (float_key radius) (Option.value ~default:"" scale_attribute) seam_offset
      (Option.value ~default:"" seam_attribute)
      (Option.value ~default:"" segment_seam_attribute)
      (Option.value ~default:"" v_attribute)
      (Option.value ~default:"" up_attribute) generate_uv (range_key u_range)
      (range_key v_range) (Option.value ~default:"" uv_range_attribute) caps
      (Option.value ~default:"" cap_group))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the primitive group before PolyWire"]
                 (Printf.sprintf "%s could not find primitive group %S"
                   operation name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.sweep_circle ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ?sides
              ?divisions_attribute ~segments ?segments_attribute ?segment_scales
              ?segment_scales_attribute ~prevent_joint_buckling
              ~maximum_joint_scale ?maximum_joint_scale_attribute
              ~smooth_point ?smooth_attribute ?max_valence ?scale_attribute
              ~seam_offset
              ?seam_attribute ?segment_seam_attribute ?v_attribute ?up_attribute
              ~generate_uv ?u_range
              ?v_range ?uv_range_attribute ~caps ?cap_group ~radius geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let sweep_circle ?label ?group ?sides ?divisions_attribute ?segments
    ?segments_attribute ?segment_scales ?segment_scales_attribute
    ?prevent_joint_buckling ?maximum_joint_scale ?maximum_joint_scale_attribute
    ?smooth_point ?smooth_attribute ?max_valence
    ?scale_attribute ?seam_offset ?seam_attribute ?segment_seam_attribute
    ?v_attribute ?up_attribute
    ?generate_uv ?u_range ?v_range ?uv_range_attribute ?caps ?cap_group
    ~radius input =
  circular_wire ?label ~operation:"sweep_circle" ?group ?sides
    ?divisions_attribute ?segments ?segments_attribute ?segment_scales
    ?segment_scales_attribute ?prevent_joint_buckling ?maximum_joint_scale
    ?maximum_joint_scale_attribute ?smooth_point ?smooth_attribute ?max_valence
    ?scale_attribute ?seam_offset ?seam_attribute ?segment_seam_attribute
    ?v_attribute ?up_attribute ?generate_uv ?u_range ?v_range
    ?uv_range_attribute ?caps ?cap_group ~radius input

let polywire ?label ?group ?sides ?divisions_attribute ?segments
    ?segments_attribute ?segment_scales ?segment_scales_attribute
    ?prevent_joint_buckling ?maximum_joint_scale ?maximum_joint_scale_attribute
    ?smooth_point ?smooth_attribute ?max_valence
    ?scale_attribute ?seam_offset ?seam_attribute ?segment_seam_attribute
    ?v_attribute ?up_attribute
    ?generate_uv ?u_range ?v_range ?uv_range_attribute ?caps ?cap_group
    ~radius input =
  circular_wire ?label ~operation:"polywire" ?group ?sides ?divisions_attribute
    ?segments ?segments_attribute ?segment_scales ?segment_scales_attribute
    ?prevent_joint_buckling ?maximum_joint_scale
    ?maximum_joint_scale_attribute ?smooth_point ?smooth_attribute ?max_valence
    ?scale_attribute ?seam_offset
    ?seam_attribute ?segment_seam_attribute ?v_attribute ?up_attribute
    ?generate_uv ?u_range ?v_range ?uv_range_attribute ?caps ?cap_group
    ~radius input

let measure_key = function
  | Pdk.Analysis.Perimeter -> "perimeter"
  | Pdk.Analysis.Area -> "area"
  | Pdk.Analysis.Signed_volume -> "signed_volume"

let accumulation_key = function
  | Pdk.Analysis.Per_element -> "per_element"
  | Pdk.Analysis.Throughout -> "throughout"

let measure ?label ?group ?(accumulation = Pdk.Analysis.Per_element)
    ?name ?total_name kind input =
  List.iter (fun (label, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.measure: empty " ^ label)
    | None | Some _ -> ())
    ["primitive group", group; "attribute name", name;
     "total attribute name", total_name];
  Node.Private.make ?label ~operation:"measure" ~version:1
    ~parameters:(String.concat ";" [
      "kind=" ^ measure_key kind;
      "group=" ^ Option.value ~default:"" group;
      "accumulation=" ^ accumulation_key accumulation;
      "name=" ^ Option.value ~default:"" name;
      "total_name=" ^ Option.value ~default:"" total_name])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "measure could not find primitive group %S" name))) in
      match primitives with
      | Error error -> Error error
      | Ok primitives ->
          (match Pdk.Analysis.with_measure ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ~accumulation ?name
              ?total_name kind geometry with
           | Ok geometry -> cooked geometry
           | Error error -> structured_pdk_error error))

let measure_area ?label ?name input =
  measure ?label ?name Pdk.Analysis.Area input

let connectivity_owner_key = function
  | Pdk.Analysis.Connectivity_points -> "points"
  | Pdk.Analysis.Connectivity_primitives -> "primitives"

let connectivity_attribute_key = function
  | Pdk.Analysis.Connectivity_integer -> "integer"
  | Pdk.Analysis.Connectivity_text prefix -> "text:" ^ String.escaped prefix

let connectivity ?label ?primitive_group ?point_group ?seam_group ?uv_attribute
    ?(owner = Pdk.Analysis.Connectivity_primitives) ?name
    ?(attribute = Pdk.Analysis.Connectivity_integer) input =
  List.iter (fun (field, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.connectivity: empty " ^ field)
    | None | Some _ -> ())
    ["primitive group", primitive_group; "point group", point_group;
     "seam group", seam_group; "UV attribute", uv_attribute;
     "attribute name", name];
  Node.Private.make ?label ~operation:"connectivity" ~version:2
    ~parameters:(String.concat ";" [
      "owner=" ^ connectivity_owner_key owner;
      "primitive_group=" ^ Option.value ~default:"" primitive_group;
      "point_group=" ^ Option.value ~default:"" point_group;
      "seam_group=" ^ Option.value ~default:"" seam_group;
      "uv_attribute=" ^ Option.value ~default:"" uv_attribute;
      "name=" ^ Option.value ~default:"" name;
      "attribute=" ^ connectivity_attribute_key attribute])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let ordinary owner label = function
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "connectivity could not find %s %S" label name)))
      in
      let seam = match seam_group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_edge_group name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "connectivity could not find edge group %S" name)))
      in
      match ordinary Pdk.Group.Primitive "primitive group" primitive_group,
          ordinary Pdk.Group.Point "point group" point_group, seam with
      | Error error, _, _ | _, Error error, _ | _, _, Error error -> Error error
      | Ok primitives, Ok points, Ok seams ->
          (match Pdk.Analysis.with_connectivity
              ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?primitives ?points ?seams
              ?uv_attribute ~owner ?name ~attribute geometry with
           | Ok geometry -> cooked geometry
           | Error error -> structured_pdk_error error))

let attribute_owner_key = function
  | Pdk.Attribute.Point -> "point"
  | Pdk.Attribute.Vertex -> "vertex"
  | Pdk.Attribute.Primitive -> "primitive"
  | Pdk.Attribute.Detail -> "detail"

let uv_projection_copy = function
  | Pdk.Ops.Planar { origin; u_axis; v_axis } ->
      Pdk.Ops.Planar {
        origin = vec3_copy origin;
        u_axis = vec3_copy u_axis;
        v_axis = vec3_copy v_axis;
      }
  | Pdk.Ops.Cylindrical { origin; axis; seam; height } ->
      Pdk.Ops.Cylindrical {
        origin = vec3_copy origin;
        axis = vec3_copy axis;
        seam = vec3_copy seam;
        height;
      }
  | Pdk.Ops.Spherical { origin; axis; seam } ->
      Pdk.Ops.Spherical {
        origin = vec3_copy origin;
        axis = vec3_copy axis;
        seam = vec3_copy seam;
      }

let uv_projection_key = function
  | Pdk.Ops.Planar { origin; u_axis; v_axis } ->
      Printf.sprintf "planar(origin=%s,u_axis=%s,v_axis=%s)"
        (vec3_key origin) (vec3_key u_axis) (vec3_key v_axis)
  | Pdk.Ops.Cylindrical { origin; axis; seam; height } ->
      Printf.sprintf "cylindrical(origin=%s,axis=%s,seam=%s,height=%s)"
        (vec3_key origin) (vec3_key axis) (vec3_key seam) (float_key height)
  | Pdk.Ops.Spherical { origin; axis; seam } ->
      Printf.sprintf "spherical(origin=%s,axis=%s,seam=%s)"
        (vec3_key origin) (vec3_key axis) (vec3_key seam)

let uv_project ?label ?(name = "uv") ?group ?(u_range = (0., 1.))
    ?(v_range = (0., 1.)) ?(fix_seams = true) ?(fix_poles = true)
    projection input =
  if String.trim name = "" then invalid_arg "Sop.uv_project: empty attribute name";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.uv_project: empty primitive group name") group;
  let projection = uv_projection_copy projection in
  let first_u, last_u = u_range and first_v, last_v = v_range in
  Node.Private.make ?label ~operation:"uv_project" ~version:1
    ~parameters:(Printf.sprintf
      "name=%S;group=%S;u=%s,%s;v=%s,%s;fix_seams=%b;fix_poles=%b;projection=%s"
      name (Option.value ~default:"" group) (float_key first_u)
      (float_key last_u) (float_key first_v) (float_key last_v) fix_seams
      fix_poles (uv_projection_key projection))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
                name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the primitive group before UV Project"]
                 (Printf.sprintf "uv_project could not find primitive group %S"
                   name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.uv_project ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~name ?primitives ~u_range ~v_range
              ~fix_seams ~fix_poles projection inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let uv_transform ?label ?(name = "uv") ?(owner = Pdk.Attribute.Vertex)
    ?group ?(translate = Vec2.zero) ?(scale = Vec2.create 1. 1.)
    ?(angle = 0.) ?(pivot = Vec2.create 0.5 0.5) input =
  if String.trim name = "" then invalid_arg "Sop.uv_transform: empty attribute name";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.uv_transform: empty group name") group;
  let group_owner = match owner with
    | Pdk.Attribute.Point -> Pdk.Group.Point
    | Pdk.Attribute.Vertex -> Pdk.Group.Vertex
    | Pdk.Attribute.Primitive | Pdk.Attribute.Detail ->
        invalid_arg "Sop.uv_transform: owner must be Point or Vertex" in
  let translate = vec2_copy translate and scale = vec2_copy scale
  and pivot = vec2_copy pivot in
  Node.Private.make ?label ~operation:"uv_transform" ~version:1
    ~parameters:(Printf.sprintf
      "name=%S;owner=%s;group=%S;translate=%s;scale=%s;angle=%s;pivot=%s"
      name (attribute_owner_key owner) (Option.value ~default:"" group)
      (vec2_key translate) (vec2_key scale) (float_key angle) (vec2_key pivot))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let selection = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:group_owner name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create a group with the same owner as the UV attribute"]
                 (Printf.sprintf "uv_transform could not find %s group %S"
                   (attribute_owner_key owner) name))) in
      match selection with
      | Error _ as error -> error
      | Ok selection ->
          match Pdk.Ops.uv_transform ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~name ?selection ~owner
              ~translate ~scale ~angle ~pivot inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let uv_auto_seam ?label ?(name = "uv_seams") ?group
    ?(angle = Float.pi /. 3.) ?(include_boundaries = true)
    ?(include_non_manifold = true) ?partition_attribute ?existing_uv
    ?(uv_tolerance = 1e-9) ?island_attribute input =
  let nonempty field = Option.iter (fun value ->
    if String.trim value = "" then invalid_arg ("Sop.uv_auto_seam: empty " ^ field)) in
  if String.trim name = "" then invalid_arg "Sop.uv_auto_seam: empty group name";
  nonempty "primitive group name" group;
  nonempty "partition attribute name" partition_attribute;
  nonempty "UV attribute name" existing_uv;
  nonempty "island attribute name" island_attribute;
  Node.Private.make ?label ~operation:"uv_auto_seam" ~version:1
    ~parameters:(Printf.sprintf
      "name=%S;group=%S;angle=%s;boundaries=%b;non_manifold=%b;partition=%S;existing_uv=%S;uv_tolerance=%s;island=%S"
      name (Option.value ~default:"" group) (float_key angle)
      include_boundaries include_non_manifold
      (Option.value ~default:"" partition_attribute)
      (Option.value ~default:"" existing_uv) (float_key uv_tolerance)
      (Option.value ~default:"" island_attribute))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some group_name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
                group_name inputs.(0) with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the primitive group before UV Auto Seam"]
                 (Printf.sprintf "uv_auto_seam could not find primitive group %S"
                   group_name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.uv_auto_seam ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~name ?primitives ~angle
              ~include_boundaries ~include_non_manifold ?partition_attribute
              ?existing_uv ~uv_tolerance ?island_attribute inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let edge_incidence_key = function
  | Pdk.Ops.Any_edge -> "any"
  | Pdk.Ops.Boundary_edge -> "boundary"
  | Pdk.Ops.Manifold_edge -> "manifold"
  | Pdk.Ops.Non_manifold_edge -> "non_manifold"

let edge_angle_basis_key = function
  | Pdk.Ops.Primitive_dihedral -> "primitive_dihedral"
  | Pdk.Ops.Incident_edges -> "incident_edges"

let group_edges ?label ?(name = "edges") ?group
    ?(incidence = Pdk.Ops.Any_edge) ?min_length ?max_length
    ?(angle_basis = Pdk.Ops.Primitive_dihedral) ?min_angle ?max_angle input =
  if String.trim name = "" then invalid_arg "Sop.group_edges: empty group name";
  Option.iter (fun value -> if String.trim value = "" then
    invalid_arg "Sop.group_edges: empty primitive group name") group;
  let optional_float = function None -> "" | Some value -> float_key value in
  Node.Private.make ?label ~operation:"group_edges" ~version:2
    ~parameters:(Printf.sprintf
      "name=%S;group=%S;incidence=%s;min_length=%s;max_length=%s;angle_basis=%s;min_angle=%s;max_angle=%s"
      name (Option.value ~default:"" group) (edge_incidence_key incidence)
      (optional_float min_length) (optional_float max_length)
      (edge_angle_basis_key angle_basis)
      (optional_float min_angle) (optional_float max_angle))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let primitives = match group with
        | None -> Ok None
        | Some group_name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive
                group_name inputs.(0) with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the primitive group before Edge Group"]
                 (Printf.sprintf "group_edges could not find primitive group %S"
                   group_name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.group_edges ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~name ?primitives ~incidence
              ?min_length ?max_length ~angle_basis ?min_angle ?max_angle
              inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let boundary_group_owner_key = function
  | Pdk.Ops.Group_points -> "points"
  | Pdk.Ops.Group_vertices -> "vertices"
  | Pdk.Ops.Group_primitives -> "primitives"
  | Pdk.Ops.Group_edges -> "edges"

let group_boundary_attribute_key (rule : Pdk.Ops.group_boundary_attribute) =
  attribute_owner_key rule.boundary_attribute_owner ^ ":"
  ^ Printf.sprintf "%S" rule.boundary_attribute_pattern

let group_from_attribute_boundary ?label ?(attributes = [])
    ?(tolerance = 1e-6) ?(include_unshared_edges = false)
    ?(include_all_unshared_curve_edges = false)
    ?(include_all_primitives_sharing_boundary_points = false)
    ~owner ~name input =
  if String.trim name = "" then
    invalid_arg "Sop.group_from_attribute_boundary: empty group name";
  let attributes = List.map (fun (rule : Pdk.Ops.group_boundary_attribute) ->
    { Pdk.Ops.boundary_attribute_owner = rule.boundary_attribute_owner;
      boundary_attribute_pattern = rule.boundary_attribute_pattern }) attributes in
  Node.Private.make ?label ~operation:"group_from_attribute_boundary" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ boundary_group_owner_key owner;
      "name=" ^ Printf.sprintf "%S" name;
      "attributes=" ^ String.concat ","
        (List.map group_boundary_attribute_key attributes);
      "tolerance=" ^ float_key tolerance;
      "include_unshared_edges=" ^ string_of_bool include_unshared_edges;
      "include_all_unshared_curve_edges="
        ^ string_of_bool include_all_unshared_curve_edges;
      "include_all_primitives_sharing_boundary_points="
        ^ string_of_bool include_all_primitives_sharing_boundary_points])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_from_attribute_boundary
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ~attributes ~tolerance ~include_unshared_edges
          ~include_all_unshared_curve_edges
          ~include_all_primitives_sharing_boundary_points ~owner ~name inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_name_conflict_key = function
  | Pdk.Ops.Name_replace -> "replace"
  | Pdk.Ops.Name_union -> "union"

let invalid_group_name_policy_key = function
  | Pdk.Ops.Ignore_invalid -> "ignore"
  | Pdk.Ops.Force_valid -> "force_valid"

let groups_from_name ?label ?(prefix = "")
    ?(conflict = Pdk.Ops.Name_replace)
    ?(invalid_names = Pdk.Ops.Ignore_invalid) ?(max_groups = 4_096)
    ?(max_payload_bytes = 268_435_456) ~owner ~attribute input =
  if String.trim attribute = "" then
    invalid_arg "Sop.groups_from_name: empty attribute name";
  Node.Private.make ?label ~operation:"groups_from_name" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ attribute_owner_key owner;
      "attribute=" ^ Printf.sprintf "%S" attribute;
      "prefix=" ^ Printf.sprintf "%S" prefix;
      "conflict=" ^ group_name_conflict_key conflict;
      "invalid_names=" ^ invalid_group_name_policy_key invalid_names;
      "max_groups=" ^ string_of_int max_groups;
      "max_payload_bytes=" ^ string_of_int max_payload_bytes])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.groups_from_name ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~prefix ~conflict ~invalid_names
          ~max_groups ~max_payload_bytes ~owner ~attribute inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_name_overlap_key = function
  | Pdk.Ops.First_group -> "first"
  | Pdk.Ops.Last_group -> "last"
  | Pdk.Ops.Error_on_overlap -> "error"

let name_from_groups ?label ?(attribute = "name") ?(pattern = "*")
    ?(default = "") ?(overlap = Pdk.Ops.Last_group)
    ?(delete_groups = false) ~owner input =
  if String.trim attribute = "" then
    invalid_arg "Sop.name_from_groups: empty attribute name";
  Node.Private.make ?label ~operation:"name_from_groups" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ attribute_owner_key owner;
      "attribute=" ^ Printf.sprintf "%S" attribute;
      "pattern=" ^ Printf.sprintf "%S" pattern;
      "default=" ^ Printf.sprintf "%S" default;
      "overlap=" ^ group_name_overlap_key overlap;
      "delete_groups=" ^ string_of_bool delete_groups])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.name_from_groups ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~attribute ~pattern ~default ~overlap
          ~delete_groups ~owner inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let uv_unitize_mode_key = function
  | Pdk.Ops.Per_face -> "per_face"
  | Pdk.Ops.Islands -> "islands"

let uv_unitize ?label ?(name = "uv") ?group ?seams ?(tolerance = 1e-9)
    ?(uniform = true) mode input =
  if String.trim name = "" then invalid_arg "Sop.uv_unitize: empty attribute name";
  Option.iter (fun value -> if String.trim value = "" then
    invalid_arg "Sop.uv_unitize: empty primitive group name") group;
  Option.iter (fun value -> if String.trim value = "" then
    invalid_arg "Sop.uv_unitize: empty seam group name") seams;
  Node.Private.make ?label ~operation:"uv_unitize" ~version:1
    ~parameters:(Printf.sprintf
      "name=%S;group=%S;seams=%S;tolerance=%s;uniform=%b;mode=%s"
      name (Option.value ~default:"" group) (Option.value ~default:"" seams)
      (float_key tolerance) uniform (uv_unitize_mode_key mode))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let find_group owner kind = function
        | None -> Ok None
        | Some group_name ->
            (match Pdk.Geometry.find_group ~owner group_name inputs.(0) with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 ~hints:["Create the named group before UV Unitize"]
                 (Printf.sprintf "uv_unitize could not find %s group %S"
                   kind group_name))) in
      let find_seams = function
        | None -> Ok (None, None)
        | Some group_name ->
            (match Pdk.Geometry.find_edge_group group_name inputs.(0) with
             | Some value -> Ok (Some value, None)
             | None ->
                 match Pdk.Geometry.find_group ~owner:Pdk.Group.Vertex
                     group_name inputs.(0) with
                 | Some value -> Ok (None, Some value)
                 | None -> Error (Diagnostic.error ~code:"missing_group"
                     ~hints:["Create a native edge group or compatibility vertex-edge group before UV Unitize"]
                     (Printf.sprintf
                       "uv_unitize could not find edge or vertex seam group %S"
                       group_name))) in
      match find_group Pdk.Group.Primitive "primitive" group, find_seams seams with
      | Error _ as error, _ | _, (Error _ as error) -> error
      | Ok primitives, Ok (edge_seams, seams) ->
          match Pdk.Ops.uv_unitize ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~name ?primitives ?seams
              ?edge_seams
              ~tolerance ~uniform mode inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let uv_parameterize_seams operation input = function
  | None -> Ok (None, None)
  | Some group_name ->
      (match Pdk.Geometry.find_edge_group group_name input with
       | Some value -> Ok (Some value, None)
       | None ->
           match Pdk.Geometry.find_group ~owner:Pdk.Group.Vertex group_name input with
           | Some value -> Ok (None, Some value)
           | None -> Error (Diagnostic.error ~code:"missing_group"
               ~hints:["Create a native edge group or compatibility vertex-edge group before " ^ operation]
               (Printf.sprintf "%s could not find edge or vertex seam group %S"
                 operation group_name)))

let uv_flatten ?label ?(name = "uv") ?seams ?(iterations = 500)
    ?(tolerance = 1e-7) input =
  if String.trim name = "" then invalid_arg "Sop.uv_flatten: empty attribute name";
  Option.iter (fun value -> if String.trim value = "" then
    invalid_arg "Sop.uv_flatten: empty seam group name") seams;
  Node.Private.make ?label ~operation:"uv_flatten" ~version:1
    ~parameters:(Printf.sprintf "name=%S;seams=%S;iterations=%d;tolerance=%s"
      name (Option.value ~default:"" seams) iterations (float_key tolerance))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match uv_parameterize_seams "uv_flatten" inputs.(0) seams with
      | Error _ as error -> error
      | Ok (edge_seams, seams) ->
          match Pdk.Ops.uv_flatten ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~name ?seams ?edge_seams
              ~iterations ~tolerance inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let uv_relax ?label ?(name = "uv") ?seams ?(uv_tolerance = 1e-9)
    ?(iterations = 500) ?(tolerance = 1e-7) input =
  if String.trim name = "" then invalid_arg "Sop.uv_relax: empty attribute name";
  Option.iter (fun value -> if String.trim value = "" then
    invalid_arg "Sop.uv_relax: empty seam group name") seams;
  Node.Private.make ?label ~operation:"uv_relax" ~version:1
    ~parameters:(Printf.sprintf
      "name=%S;seams=%S;uv_tolerance=%s;iterations=%d;tolerance=%s"
      name (Option.value ~default:"" seams) (float_key uv_tolerance)
      iterations (float_key tolerance))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match uv_parameterize_seams "uv_relax" inputs.(0) seams with
      | Error _ as error -> error
      | Ok (edge_seams, seams) ->
          match Pdk.Ops.uv_relax ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~name ?seams ?edge_seams
              ~uv_tolerance ~iterations ~tolerance inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let promote_method_key = function
  | Pdk.Attribute_ops.First -> "first"
  | Pdk.Attribute_ops.Last -> "last"
  | Pdk.Attribute_ops.Average -> "average"
  | Pdk.Attribute_ops.Minimum -> "minimum"
  | Pdk.Attribute_ops.Maximum -> "maximum"
  | Pdk.Attribute_ops.Mode -> "mode"
  | Pdk.Attribute_ops.Median -> "median"
  | Pdk.Attribute_ops.Sum -> "sum"
  | Pdk.Attribute_ops.Sum_squares -> "sum_squares"
  | Pdk.Attribute_ops.Root_mean_square -> "root_mean_square"
  | Pdk.Attribute_ops.Array_all -> "array_all"
  | Pdk.Attribute_ops.Unique_values -> "unique_values"

let promote_method_has_source_index = function
  | Pdk.Attribute_ops.First | Last | Minimum | Maximum | Mode -> true
  | Average | Median | Sum | Sum_squares | Root_mean_square
  | Array_all | Unique_values -> false

let promote_attribute ?label ?into ?(method_ = Pdk.Attribute_ops.Average)
    ?(delete_source = true) ?piece_attribute ?index_attribute ~source
    ~destination ~name input =
  if Option.is_some index_attribute && not (promote_method_has_source_index method_)
  then invalid_arg
      "Sop.promote_attribute: source index requires first, last, minimum, maximum, or mode";
  let into_key = Option.value ~default:name into in
  Node.Private.make ?label ~operation:"attribute_promote" ~version:4
    ~parameters:(String.concat ";" [
      "source=" ^ attribute_owner_key source;
      "destination=" ^ attribute_owner_key destination;
      "name=" ^ name; "into=" ^ into_key;
      "method=" ^ promote_method_key method_;
      "delete_source=" ^ string_of_bool delete_source;
      "piece_attribute=" ^ Option.value ~default:"" piece_attribute;
      "index_attribute=" ^ Option.value ~default:"" index_attribute;
    ]) ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Attribute_ops.promote ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?into ~method_ ~delete_source ~source
          ~destination ~name ?piece_attribute ?index_attribute inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let promote_attributes ?label ?(method_ = Pdk.Attribute_ops.Average)
    ?(delete_source = true) ?piece_attribute ?into_pattern ?index_pattern
    ~source ~destination ~pattern input =
  if Option.is_some index_pattern && not (promote_method_has_source_index method_)
  then invalid_arg
      "Sop.promote_attributes: source index requires first, last, minimum, maximum, or mode";
  (match Pdk.Attribute_pattern.compile pattern with
   | Ok _ -> ()
   | Error message -> invalid_arg ("Sop.promote_attributes: " ^ message));
  (match into_pattern with
   | None -> ()
   | Some replacement ->
       (match Pdk.Attribute_pattern.compile_rewrite_set ~pattern ~replacement with
        | Ok _ -> ()
        | Error message -> invalid_arg ("Sop.promote_attributes: " ^ message)));
  (match index_pattern with
   | None -> ()
   | Some replacement ->
       (match Pdk.Attribute_pattern.compile_rewrite_set ~pattern ~replacement with
        | Ok _ -> ()
        | Error message -> invalid_arg ("Sop.promote_attributes: " ^ message)));
  Node.Private.make ?label ~operation:"attribute_promote_pattern" ~version:5
    ~parameters:(String.concat ";" [
      "source=" ^ attribute_owner_key source;
      "destination=" ^ attribute_owner_key destination;
      "pattern=" ^ String.escaped pattern;
      "method=" ^ promote_method_key method_;
      "delete_source=" ^ string_of_bool delete_source;
      "piece_attribute=" ^ Option.value ~default:"" piece_attribute;
      "into_pattern=" ^ String.escaped (Option.value ~default:"" into_pattern);
      "index_pattern=" ^ String.escaped (Option.value ~default:"" index_pattern);
    ]) ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Attribute_ops.promote_pattern
          ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~method_ ~delete_source ~source
          ~destination ~pattern ?piece_attribute ?into_pattern ?index_pattern
          inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let transfer_mode_key = function
  | Pdk.Attribute_ops.Nearest -> "nearest"
  | Pdk.Attribute_ops.Inverse_distance { neighbors; power } ->
      Printf.sprintf "inverse_distance:%d:%s" neighbors (float_key power)
  | Pdk.Attribute_ops.Kernel { neighbors; radius; kernel } ->
      let kernel = match kernel with
        | Pdk.Attribute_ops.Links -> "links"
        | Pdk.Attribute_ops.RenderMan -> "renderman"
        | Pdk.Attribute_ops.Hart -> "hart" in
      String.concat ":" ["kernel"; string_of_int neighbors;
        float_key radius; kernel]

let unmatched_key = function
  | Pdk.Attribute_ops.Keep_target -> "keep_target"
  | Pdk.Attribute_ops.Default_value -> "default_value"

let transfer_falloff_key = function
  | Pdk.Attribute_ops.Linear -> "linear"
  | Pdk.Attribute_ops.Smoothstep -> "smoothstep"
  | Pdk.Attribute_ops.Uniform bias -> "uniform:" ^ float_key bias

let surface_vertex_selection_key = function
  | Pdk.Attribute_ops.All_triangle_vertices -> "all_triangle_vertices"
  | Pdk.Attribute_ops.Any_triangle_vertex -> "any_triangle_vertex"

let enumerate_mode_key = function
  | Pdk.Attribute_ops.Enumerate_piece_elements -> "piece_elements"
  | Pdk.Attribute_ops.Enumerate_pieces -> "pieces"

let enumerate ?label ?group ?(start = 0) ?(step = 1)
    ?(storage = Pdk.Attribute_ops.Integer) ?piece_attribute
    ?(mode = Pdk.Attribute_ops.Enumerate_piece_elements) ~owner ~name input =
  if owner = Pdk.Attribute.Detail then
    invalid_arg "Sop.enumerate: detail ownership is not enumerable";
  if String.trim name = "" then invalid_arg "Sop.enumerate: empty attribute name";
  (match group with Some value when String.trim value = "" ->
     invalid_arg "Sop.enumerate: empty group name" | None | Some _ -> ());
  (match piece_attribute with Some value when String.trim value = "" ->
     invalid_arg "Sop.enumerate: empty piece attribute name"
   | None | Some _ -> ());
  let storage_key = match storage with
    | Pdk.Attribute_ops.Integer -> "integer"
    | Pdk.Attribute_ops.Text { prefix } -> "text:" ^ String.escaped prefix in
  Node.Private.make ?label ~operation:"enumerate" ~version:2
    ~parameters:(String.concat ";" ["owner=" ^ attribute_owner_key owner;
      "name=" ^ String.escaped name; "group=" ^ option_string_key group;
      "start=" ^ string_of_int start; "step=" ^ string_of_int step;
      "storage=" ^ storage_key;
      "piece_attribute=" ^ option_string_key piece_attribute;
      "mode=" ^ enumerate_mode_key mode])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let group_owner = match owner with
        | Pdk.Attribute.Point -> Pdk.Group.Point
        | Pdk.Attribute.Vertex -> Pdk.Group.Vertex
        | Pdk.Attribute.Primitive -> Pdk.Group.Primitive
        | Pdk.Attribute.Detail -> assert false in
      let selection = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:group_owner name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "enumerate could not find %s group %S"
                    (attribute_owner_key owner) name))) in
      match selection with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Attribute_ops.enumerate
              ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
              ?selection ~start ~step ~storage ?piece_attribute ~mode
              ~owner ~name inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let blur_method_key = function
  | Pdk.Attribute_ops.Uniform -> "uniform"
  | Pdk.Attribute_ops.Edge_length -> "edge_length"

let blur_mode_key = function
  | Pdk.Attribute_ops.Laplacian step -> "laplacian:" ^ float_key step
  | Pdk.Attribute_ops.Custom_steps { odd; even } ->
      String.concat ":" ["custom"; float_key odd; float_key even]

let attribute_blur ?label ?group ?(iterations = 1)
    ?(method_ = Pdk.Attribute_ops.Uniform)
    ?(mode = Pdk.Attribute_ops.Laplacian 0.5) ?weight_attribute
    ?alpha_attribute ?(pin_borders = false) ?(original_blend = 0.)
    ?(blurred_blend = 1.) ~attributes input =
  (match Pdk.Attribute_pattern.compile attributes with
   | Ok _ -> ()
   | Error message -> invalid_arg ("Sop.attribute_blur: " ^ message));
  List.iter (fun (label, value) -> match value with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.attribute_blur: empty " ^ label)
    | None | Some _ -> ())
    ["point group", group; "weight attribute", weight_attribute;
     "alpha attribute", alpha_attribute];
  Node.Private.make ?label ~operation:"attribute_blur" ~version:1
    ~parameters:(String.concat ";" [
      "attributes=" ^ String.escaped attributes;
      "group=" ^ option_string_key group;
      "iterations=" ^ string_of_int iterations;
      "method=" ^ blur_method_key method_;
      "mode=" ^ blur_mode_key mode;
      "weight=" ^ option_string_key weight_attribute;
      "alpha=" ^ option_string_key alpha_attribute;
      "pin_borders=" ^ string_of_bool pin_borders;
      "original_blend=" ^ float_key original_blend;
      "blurred_blend=" ^ float_key blurred_blend])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let selection = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "attribute_blur could not find point group %S" name))) in
      match selection with
      | Error error -> Error error
      | Ok selection ->
          (match Pdk.Attribute_ops.blur_points
              ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
              ?selection ~iterations ~method_ ~mode ?weight_attribute
              ?alpha_attribute ~pin_borders ~original_blend ~blurred_blend
              ~pattern:attributes inputs.(0) with
           | Ok geometry -> cooked geometry
           | Error error -> structured_pdk_error error))

let group_length owner geometry = match owner with
  | Pdk.Group.Point -> Pdk.Geometry.point_count geometry
  | Pdk.Group.Vertex -> Pdk.Geometry.vertex_count geometry
  | Pdk.Group.Primitive -> Pdk.Geometry.primitive_count geometry

let compile_transfer_group_pattern operation label = function
  | None -> None
  | Some pattern ->
      match Pdk.Attribute_pattern.compile pattern with
      | Ok compiled -> Some compiled
      | Error message -> invalid_arg
          (Printf.sprintf "Sop.%s: invalid %s group pattern: %s"
             operation label message)

let resolve_transfer_group ~operation ~owner ~owner_name ~exact ~pattern
    ~cancel ~grain geometry =
  match exact, pattern with
  | Some _, Some _ -> invalid_arg
      (Printf.sprintf "Sop.%s: exact and patterned %s groups are mutually exclusive"
         operation owner_name)
  | Some name, None ->
      (match Pdk.Geometry.find_group ~owner name geometry with
       | Some group -> Ok (Some group)
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find %s group %S"
              operation owner_name name)))
  | None, None -> Ok None
  | None, Some pattern ->
      Pdk.Cancel.check cancel;
      let matches = Pdk.Geometry.groups geometry
          |> List.filter (fun group -> Pdk.Group.owner group = owner
            && Pdk.Attribute_pattern.matches pattern (Pdk.Group.name group)) in
      let selection = match matches with
        | [] -> Ok (Pdk.Group.init ~grain ~owner
            ~name:"__attribute_transfer_empty" (group_length owner geometry)
            (fun _ -> false))
        | [group] -> Ok group
        | groups -> Pdk.Group.union_many ~cancel ~grain
            ~name:"__attribute_transfer_union" groups in
      Result.map_error (fun message -> Diagnostic.error ~code:"invalid_group"
        (operation ^ ": " ^ message)) selection
      |> Result.map Option.some

let attribute_copy ?label ?(match_ = Pdk.Attribute_ops.Cyclic)
    ?(allow_position = false) ?source_group ?source_group_pattern
    ?target_group ?target_group_pattern ~group_owner ~rules ~source ~target () =
  if rules = [] then
    invalid_arg "Sop.attribute_copy: at least one copy rule is required";
  if source_group <> None && source_group_pattern <> None then invalid_arg
      "Sop.attribute_copy: source_group and source_group_pattern are mutually exclusive";
  if target_group <> None && target_group_pattern <> None then invalid_arg
      "Sop.attribute_copy: target_group and target_group_pattern are mutually exclusive";
  List.iter (fun (rule : Pdk.Attribute_ops.copy_rule) ->
    match rule.copy_into with
    | None ->
        (match Pdk.Attribute_pattern.compile rule.copy_pattern with
         | Ok _ -> ()
         | Error message -> invalid_arg ("Sop.attribute_copy: " ^ message))
    | Some into ->
        (match Pdk.Attribute_pattern.compile_rewrite
            ~pattern:rule.copy_pattern ~replacement:into with
         | Ok _ -> ()
         | Error message -> invalid_arg ("Sop.attribute_copy: " ^ message))) rules;
  let source_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_copy" "source" source_group_pattern
  and target_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_copy" "target" target_group_pattern in
  let group_owner_name = match group_owner with
    | Pdk.Group.Point -> "point"
    | Pdk.Group.Vertex -> "vertex"
    | Pdk.Group.Primitive -> "primitive" in
  let rule_key (rule : Pdk.Attribute_ops.copy_rule) = String.concat ":" [
    attribute_owner_key rule.copy_owner;
    String.escaped rule.copy_pattern;
    option_string_key rule.copy_into] in
  let match_key = match match_ with
    | Pdk.Attribute_ops.Cyclic -> "cyclic"
    | Pdk.Attribute_ops.By_values { source_attribute; target_attribute } ->
        "by_values:" ^ String.escaped source_attribute ^ ":"
        ^ String.escaped target_attribute
    | Pdk.Attribute_ops.To_element { target_attribute } ->
        "to_element:" ^ String.escaped target_attribute in
  Node.Private.make ?label ~operation:"attribute_copy" ~version:1
    ~parameters:(String.concat ";" [
      "group_owner=" ^ group_owner_name;
      "rules=" ^ String.concat "," (List.map rule_key rules);
      "match=" ^ match_key;
      "allow_position=" ^ string_of_bool allow_position;
      "source_group=" ^ option_string_key source_group;
      "source_group_pattern=" ^ option_string_key source_group_pattern;
      "target_group=" ^ option_string_key target_group;
      "target_group_pattern=" ^ option_string_key target_group_pattern])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|source; target|]
    (fun ~node_id:_ context inputs ->
      let cancel = Context.cancel_token context and grain = Context.grain context in
      match resolve_transfer_group ~operation:"attribute_copy"
          ~owner:group_owner ~owner_name:group_owner_name ~exact:source_group
          ~pattern:source_group_pattern_compiled ~cancel ~grain inputs.(0) with
      | Error error -> Error error
      | Ok source_group ->
          (match resolve_transfer_group ~operation:"attribute_copy"
              ~owner:group_owner ~owner_name:group_owner_name ~exact:target_group
              ~pattern:target_group_pattern_compiled ~cancel ~grain inputs.(1) with
           | Error error -> Error error
           | Ok target_group ->
               match Pdk.Attribute_ops.copy ~cancel ~grain ?source_group
                   ?target_group ~match_ ~allow_position ~group_owner ~rules
                   ~source:inputs.(0) ~target:inputs.(1) () with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let attribute_combine ?label ?group ?group_pattern ?match_attribute
    ?(create_missing = true) ?(create_missing_as_scalar = false)
    ?(delete_sources = false) ?(error_on_missing = true)
    ?(overall_scale = 1.) ?threshold ?minimum ?maximum ~owner ~destination
    ~layers ?(sources = []) ~target () =
  if group <> None && group_pattern <> None then invalid_arg
      "Sop.attribute_combine: group and group_pattern are mutually exclusive";
  if owner = Pdk.Attribute.Detail
      && (group <> None || group_pattern <> None) then invalid_arg
      "Sop.attribute_combine: detail attributes do not accept a group";
  let input_count = 1 + List.length sources in
  List.iter (fun (layer : Pdk.Attribute_ops.combine_layer) ->
    if layer.source_input < 0 || layer.source_input >= input_count then
      invalid_arg "Sop.attribute_combine: source input index is out of range";
    if layer.blend_input < 0 || layer.blend_input >= input_count then
      invalid_arg "Sop.attribute_combine: blend input index is out of range") layers;
  let group_owner, group_owner_name = match owner with
    | Pdk.Attribute.Point -> Pdk.Group.Point, "point"
    | Pdk.Attribute.Vertex -> Pdk.Group.Vertex, "vertex"
    | Pdk.Attribute.Primitive -> Pdk.Group.Primitive, "primitive"
    | Pdk.Attribute.Detail -> Pdk.Group.Point, "detail" in
  let group_pattern_compiled = compile_transfer_group_pattern
      "attribute_combine" "target" group_pattern in
  let operation_key = function
    | Pdk.Attribute_ops.Combine_copy -> "copy"
    | Pdk.Attribute_ops.Combine_add -> "add"
    | Pdk.Attribute_ops.Combine_subtract -> "subtract"
    | Pdk.Attribute_ops.Combine_multiply -> "multiply"
    | Pdk.Attribute_ops.Combine_divide -> "divide"
    | Pdk.Attribute_ops.Combine_maximum -> "maximum"
    | Pdk.Attribute_ops.Combine_minimum -> "minimum" in
  let process_key = function
    | Pdk.Attribute_ops.Combine_process_none -> "none"
    | Pdk.Attribute_ops.Combine_reciprocal -> "reciprocal"
    | Pdk.Attribute_ops.Combine_clamp_01 -> "clamp01"
    | Pdk.Attribute_ops.Combine_complement_clamp_01 -> "complement_clamp01"
    | Pdk.Attribute_ops.Combine_threshold_half -> "threshold_half" in
  let layer_key (layer : Pdk.Attribute_ops.combine_layer) = String.concat ":" [
    option_string_key layer.source;
    string_of_int layer.source_input;
    operation_key layer.operation;
    Printf.sprintf "%.17g" layer.scale;
    Printf.sprintf "%.17g" layer.add;
    process_key layer.process;
    Printf.sprintf "%.17g" layer.blend;
    option_string_key layer.blend_attribute;
    string_of_int layer.blend_input] in
  let option_float_key = function
    | None -> "none"
    | Some value -> Printf.sprintf "%.17g" value in
  let inputs = Array.of_list (target :: sources) in
  Node.Private.make ?label ~operation:"attribute_combine" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ attribute_owner_key owner;
      "destination=" ^ String.escaped destination;
      "layers=" ^ String.concat "," (List.map layer_key layers);
      "group=" ^ option_string_key group;
      "group_pattern=" ^ option_string_key group_pattern;
      "match=" ^ option_string_key match_attribute;
      "create_missing=" ^ string_of_bool create_missing;
      "create_scalar=" ^ string_of_bool create_missing_as_scalar;
      "delete_sources=" ^ string_of_bool delete_sources;
      "error_missing=" ^ string_of_bool error_on_missing;
      "overall_scale=" ^ Printf.sprintf "%.17g" overall_scale;
      "threshold=" ^ option_float_key threshold;
      "minimum=" ^ option_float_key minimum;
      "maximum=" ^ option_float_key maximum])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let cancel = Context.cancel_token context and grain = Context.grain context in
      let selection = if owner = Pdk.Attribute.Detail then Ok None
        else resolve_transfer_group ~operation:"attribute_combine"
          ~owner:group_owner ~owner_name:group_owner_name ~exact:group
          ~pattern:group_pattern_compiled ~cancel ~grain inputs.(0) in
      match selection with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Attribute_ops.combine ~cancel ~grain ?selection
              ?match_attribute ~create_missing ~create_missing_as_scalar
              ~delete_sources ~error_on_missing ~overall_scale ?threshold
              ?minimum ?maximum ~owner ~destination ~layers
              ~geometries:inputs () with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let attribute_interpolate ?label ?group ?group_pattern ?driver ?compute_weights
    ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
    ?(match_groups = false)
    ?primitive_attribute ?uvw_attribute ?(pre_scale = 1.)
    ?(normalize_weights = false) ?(threshold = 1e-6) ?(blend = 1.)
    ?(unmatched = Pdk.Attribute_ops.Keep_target) ~target_owner ~attributes
    ~source ~target () =
  if Option.is_some driver
      && (Option.is_some primitive_attribute || Option.is_some uvw_attribute) then
    invalid_arg
      "Sop.attribute_interpolate: driver is mutually exclusive with primitive_attribute and uvw_attribute";
  if group <> None && group_pattern <> None then invalid_arg
      "Sop.attribute_interpolate: group and group_pattern are mutually exclusive";
  if target_owner = Pdk.Attribute.Detail
      && (group <> None || group_pattern <> None) then invalid_arg
      "Sop.attribute_interpolate: detail attributes do not accept a group";
  let group_owner, group_owner_name = match target_owner with
    | Pdk.Attribute.Point -> Pdk.Group.Point, "point"
    | Pdk.Attribute.Vertex -> Pdk.Group.Vertex, "vertex"
    | Pdk.Attribute.Primitive -> Pdk.Group.Primitive, "primitive"
    | Pdk.Attribute.Detail -> Pdk.Group.Point, "detail" in
  let group_pattern_compiled = compile_transfer_group_pattern
      "attribute_interpolate" "target" group_pattern in
  let attribute_key (attribute : Pdk.Attribute_ops.interpolate_attribute) =
    String.concat ":" [
      attribute_owner_key attribute.interpolate_owner;
      String.escaped attribute.interpolate_source;
      String.escaped attribute.interpolate_target] in
  let unmatched_key = match unmatched with
    | Pdk.Attribute_ops.Keep_target -> "keep"
    | Pdk.Attribute_ops.Default_value -> "default" in
  let driver_key = match driver with
    | None -> String.concat ":" ["primitive_uvw";
        String.escaped (Option.value ~default:"source_primitive"
          primitive_attribute);
        String.escaped (Option.value ~default:"source_uvw" uvw_attribute)]
    | Some (Pdk.Attribute_ops.Primitive_uvw {
        primitive_attribute; uvw_attribute }) ->
        String.concat ":" ["primitive_uvw"; String.escaped primitive_attribute;
          String.escaped uvw_attribute]
    | Some (Pdk.Attribute_ops.Point_weights {
        numbers_attribute; weights_attribute }) ->
        String.concat ":" ["point_weights"; String.escaped numbers_attribute;
          String.escaped weights_attribute]
    | Some (Pdk.Attribute_ops.Vertex_weights {
        numbers_attribute; weights_attribute }) ->
        String.concat ":" ["vertex_weights"; String.escaped numbers_attribute;
          String.escaped weights_attribute]
    | Some (Pdk.Attribute_ops.Primitive_weights {
        numbers_attribute; weights_attribute }) ->
        String.concat ":" ["primitive_weights"; String.escaped numbers_attribute;
          String.escaped weights_attribute] in
  let compute_key = match compute_weights with
    | None -> "none"
    | Some (computed : Pdk.Attribute_ops.interpolate_computed) ->
        String.concat ":" [attribute_owner_key computed.computed_owner;
          String.escaped computed.computed_numbers_attribute;
          String.escaped computed.computed_weights_attribute] in
  Node.Private.make ?label ~operation:"attribute_interpolate" ~version:3
    ~parameters:(String.concat ";" [
      "owner=" ^ attribute_owner_key target_owner;
      "attributes=" ^ String.concat "," (List.map attribute_key attributes);
      "driver=" ^ driver_key;
      "compute_weights=" ^ compute_key;
      "point_pattern=" ^ option_string_key point_pattern;
      "vertex_pattern=" ^ option_string_key vertex_pattern;
      "primitive_pattern=" ^ option_string_key primitive_pattern;
      "detail_pattern=" ^ option_string_key detail_pattern;
      "match_groups=" ^ string_of_bool match_groups;
      "pre_scale=" ^ Printf.sprintf "%.17g" pre_scale;
      "normalize_weights=" ^ string_of_bool normalize_weights;
      "threshold=" ^ Printf.sprintf "%.17g" threshold;
      "blend=" ^ Printf.sprintf "%.17g" blend;
      "unmatched=" ^ unmatched_key;
      "group=" ^ option_string_key group;
      "group_pattern=" ^ option_string_key group_pattern])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|source; target|]
    (fun ~node_id:_ context inputs ->
      let cancel = Context.cancel_token context and grain = Context.grain context in
      let selection = if target_owner = Pdk.Attribute.Detail then Ok None
        else resolve_transfer_group ~operation:"attribute_interpolate"
          ~owner:group_owner ~owner_name:group_owner_name ~exact:group
          ~pattern:group_pattern_compiled ~cancel ~grain inputs.(1) in
      match selection with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Attribute_ops.interpolate ~cancel ~grain ?selection
              ?driver ?compute_weights ?primitive_attribute ?uvw_attribute ~pre_scale
              ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
              ~match_groups ~normalize_weights ~threshold ~blend ~unmatched
              ~target_owner ~attributes ~source:inputs.(0) ~target:inputs.(1) () with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let attribute_transfer ?label ?(owner = Pdk.Attribute.Point) ?names ?pattern
    ?(mode = Pdk.Attribute_ops.Nearest) ?max_distance ?(blend_width = 0.)
    ?(falloff = Pdk.Attribute_ops.Smoothstep)
    ?(unmatched = Pdk.Attribute_ops.Keep_target)
    ?source_group ?source_group_pattern ?source_vertex_group
    ?source_vertex_group_pattern
    ?(source_vertex_selection = Pdk.Attribute_ops.All_triangle_vertices)
    ?target_group ?target_group_pattern
    ~source ~target () =
  if owner <> Pdk.Attribute.Vertex
      && (source_vertex_group <> None || source_vertex_group_pattern <> None) then
    invalid_arg
      "Sop.attribute_transfer: source vertex groups require vertex ownership";
  if owner = Pdk.Attribute.Detail
     && (source_group <> None || source_group_pattern <> None
         || target_group <> None || target_group_pattern <> None
         || max_distance <> None || blend_width <> 0.) then
    invalid_arg
      "Sop.attribute_transfer: detail transfer does not accept spatial options";
  if owner = Pdk.Attribute.Detail && mode <> Pdk.Attribute_ops.Nearest then
    invalid_arg
      "Sop.attribute_transfer: detail transfer does not accept a spatial mode";
  if owner = Pdk.Attribute.Vertex && mode <> Pdk.Attribute_ops.Nearest then
    invalid_arg
      "Sop.attribute_transfer: vertex transfer supports closest-surface mode only";
  (match names, pattern with
   | Some _, Some _ -> invalid_arg
       "Sop.attribute_transfer: names and pattern are mutually exclusive"
   | None, Some value ->
       (match Pdk.Attribute_pattern.compile value with
        | Ok _ -> ()
        | Error message -> invalid_arg ("Sop.attribute_transfer: " ^ message))
   | None, None | Some _, None -> ());
  List.iter (fun (label, value) -> match value with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.attribute_transfer: empty " ^ label ^ " group")
    | None | Some _ -> ())
    ["source", source_group; "source pattern", source_group_pattern;
     "source vertex", source_vertex_group;
     "source vertex pattern", source_vertex_group_pattern;
     "target", target_group; "target pattern", target_group_pattern];
  if source_group <> None && source_group_pattern <> None then invalid_arg
      "Sop.attribute_transfer: source_group and source_group_pattern are mutually exclusive";
  if target_group <> None && target_group_pattern <> None then invalid_arg
      "Sop.attribute_transfer: target_group and target_group_pattern are mutually exclusive";
  if source_vertex_group <> None && source_vertex_group_pattern <> None then
    invalid_arg
      "Sop.attribute_transfer: source_vertex_group and source_vertex_group_pattern are mutually exclusive";
  let source_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_transfer" "source" source_group_pattern
  and target_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_transfer" "target" target_group_pattern
  and source_vertex_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_transfer" "source vertex" source_vertex_group_pattern in
  let names_key = match names with
    | None -> "all"
    | Some values -> String.concat "," (List.map String.escaped values) in
  let pattern_key = Option.value ~default:"none" pattern |> String.escaped in
  let maximum_key = match max_distance with
    | None -> "unbounded" | Some value -> float_key value in
  Node.Private.make ?label ~operation:"attribute_transfer" ~version:6
    ~parameters:(String.concat ";" ["owner=" ^ attribute_owner_key owner;
      "names=" ^ names_key;
      "pattern=" ^ pattern_key;
      "mode=" ^ transfer_mode_key mode; "max_distance=" ^ maximum_key;
      "blend_width=" ^ float_key blend_width;
      "falloff=" ^ transfer_falloff_key falloff;
      "unmatched=" ^ unmatched_key unmatched;
      "source_group=" ^ option_string_key source_group;
      "source_group_pattern=" ^ option_string_key source_group_pattern;
      "source_vertex_group=" ^ option_string_key source_vertex_group;
      "source_vertex_group_pattern=" ^ option_string_key source_vertex_group_pattern;
      "source_vertex_selection=" ^
        surface_vertex_selection_key source_vertex_selection;
      "target_group=" ^ option_string_key target_group;
      "target_group_pattern=" ^ option_string_key target_group_pattern])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|source; target|]
    (fun ~node_id:_ context inputs ->
      let source_group_owner, target_group_owner, source_owner_name,
          target_owner_name = match owner with
        | Pdk.Attribute.Point ->
            Pdk.Group.Point, Pdk.Group.Point, "point", "point"
        | Pdk.Attribute.Vertex ->
            Pdk.Group.Primitive, Pdk.Group.Vertex, "primitive", "vertex"
        | Pdk.Attribute.Primitive ->
            Pdk.Group.Primitive, Pdk.Group.Primitive, "primitive", "primitive"
        | Pdk.Attribute.Detail ->
            Pdk.Group.Point, Pdk.Group.Point, "detail", "detail" in
      let cancel = Context.cancel_token context and grain = Context.grain context in
      match resolve_transfer_group ~operation:"attribute_transfer"
          ~owner:source_group_owner ~owner_name:source_owner_name
          ~exact:source_group ~pattern:source_group_pattern_compiled
          ~cancel ~grain inputs.(0) with
      | Error error -> Error error
      | Ok source_elements ->
          (match resolve_transfer_group ~operation:"attribute_transfer"
              ~owner:Pdk.Group.Vertex ~owner_name:"vertex"
              ~exact:source_vertex_group
              ~pattern:source_vertex_group_pattern_compiled
              ~cancel ~grain inputs.(0) with
           | Error error -> Error error
           | Ok source_vertices ->
          (match resolve_transfer_group ~operation:"attribute_transfer"
              ~owner:target_group_owner ~owner_name:target_owner_name
              ~exact:target_group ~pattern:target_group_pattern_compiled
              ~cancel ~grain inputs.(1) with
           | Error error -> Error error
           | Ok target_elements ->
               let result = match owner with
                 | Pdk.Attribute.Point ->
                     Pdk.Attribute_ops.transfer_points
                       ~cancel ~grain ?names ?pattern ~mode ?max_distance
                       ~blend_width ~falloff
                       ~unmatched ?source_points:source_elements
                       ?target_points:target_elements ~source:inputs.(0)
                       ~target:inputs.(1) ()
                 | Pdk.Attribute.Vertex ->
                     Pdk.Attribute_ops.transfer_vertices
                       ~cancel ~grain ?names ?pattern ?max_distance
                       ~blend_width ~falloff
                       ~unmatched ?source_primitives:source_elements
                       ?source_vertices ~source_vertex_selection
                       ?target_vertices:target_elements ~source:inputs.(0)
                       ~target:inputs.(1) ()
                 | Pdk.Attribute.Primitive ->
                     Pdk.Attribute_ops.transfer_primitives
                       ~cancel ~grain ?names ?pattern ~mode ?max_distance
                       ~blend_width ~falloff
                       ~unmatched ?source_primitives:source_elements
                       ?target_primitives:target_elements ~source:inputs.(0)
                       ~target:inputs.(1) ()
                 | Pdk.Attribute.Detail ->
                     Pdk.Attribute_ops.transfer_detail ?names ?pattern
                       ~source:inputs.(0) ~target:inputs.(1) () in
               match result with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error)))

let attribute_transfer_surface ?label ?max_distance ?(blend_width = 0.)
    ?(falloff = Pdk.Attribute_ops.Smoothstep)
    ?(unmatched = Pdk.Attribute_ops.Keep_target)
    ?(target_owner = Pdk.Attribute.Point) ?distance_attribute ?source_group
    ?source_group_pattern ?source_vertex_group ?source_vertex_group_pattern
    ?(source_vertex_selection = Pdk.Attribute_ops.All_triangle_vertices)
    ?target_group ?target_group_pattern
    ~attributes ~source ~target () =
  if target_owner = Pdk.Attribute.Detail then
    invalid_arg "Sop.attribute_transfer_surface: detail target is not spatial";
  List.iter (fun (label, value) -> match value with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.attribute_transfer_surface: empty " ^ label ^ " group")
    | None | Some _ -> ())
    ["source", source_group; "source pattern", source_group_pattern;
     "source vertex", source_vertex_group;
     "source vertex pattern", source_vertex_group_pattern;
     "target", target_group; "target pattern", target_group_pattern];
  if source_group <> None && source_group_pattern <> None then invalid_arg
      "Sop.attribute_transfer_surface: source_group and source_group_pattern are mutually exclusive";
  if target_group <> None && target_group_pattern <> None then invalid_arg
      "Sop.attribute_transfer_surface: target_group and target_group_pattern are mutually exclusive";
  if source_vertex_group <> None && source_vertex_group_pattern <> None then
    invalid_arg
      "Sop.attribute_transfer_surface: source_vertex_group and source_vertex_group_pattern are mutually exclusive";
  let source_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_transfer_surface" "source" source_group_pattern
  and target_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_transfer_surface" "target" target_group_pattern
  and source_vertex_group_pattern_compiled = compile_transfer_group_pattern
      "attribute_transfer_surface" "source vertex" source_vertex_group_pattern in
  let attribute_key (value : Pdk.Attribute_ops.surface_attribute) =
    String.concat ":" [attribute_owner_key value.source_owner;
      String.escaped value.source_name; String.escaped value.target_name] in
  let maximum_key = match max_distance with
    | None -> "unbounded" | Some value -> float_key value in
  Node.Private.make ?label ~operation:"attribute_transfer_surface" ~version:5
    ~parameters:(String.concat ";" [
      "attributes=" ^ String.concat "," (List.map attribute_key attributes);
      "max_distance=" ^ maximum_key; "unmatched=" ^ unmatched_key unmatched;
      "distance_attribute=" ^ option_string_key distance_attribute;
      "blend_width=" ^ float_key blend_width;
      "falloff=" ^ transfer_falloff_key falloff;
      "target_owner=" ^ attribute_owner_key target_owner;
      "source_group=" ^ option_string_key source_group;
      "source_group_pattern=" ^ option_string_key source_group_pattern;
      "source_vertex_group=" ^ option_string_key source_vertex_group;
      "source_vertex_group_pattern=" ^ option_string_key source_vertex_group_pattern;
      "source_vertex_selection=" ^
        surface_vertex_selection_key source_vertex_selection;
      "target_group=" ^ option_string_key target_group;
      "target_group_pattern=" ^ option_string_key target_group_pattern;
    ]) ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|source; target|]
    (fun ~node_id:_ context inputs ->
      let target_group_owner = match target_owner with
        | Pdk.Attribute.Point -> Pdk.Group.Point
        | Pdk.Attribute.Vertex -> Pdk.Group.Vertex
        | Pdk.Attribute.Primitive -> Pdk.Group.Primitive
        | Pdk.Attribute.Detail -> assert false in
      let cancel = Context.cancel_token context and grain = Context.grain context in
      match resolve_transfer_group ~operation:"attribute_transfer_surface"
          ~owner:Pdk.Group.Primitive ~owner_name:"primitive"
          ~exact:source_group ~pattern:source_group_pattern_compiled
          ~cancel ~grain inputs.(0) with
      | Error error -> Error error
      | Ok source_primitives ->
          (match resolve_transfer_group ~operation:"attribute_transfer_surface"
              ~owner:Pdk.Group.Vertex ~owner_name:"vertex"
              ~exact:source_vertex_group
              ~pattern:source_vertex_group_pattern_compiled
              ~cancel ~grain inputs.(0) with
           | Error error -> Error error
           | Ok source_vertices ->
          (match resolve_transfer_group ~operation:"attribute_transfer_surface"
              ~owner:target_group_owner
              ~owner_name:(if target_group_owner = Pdk.Group.Primitive then "primitive"
                else if target_group_owner = Pdk.Group.Vertex then "vertex" else "point")
              ~exact:target_group ~pattern:target_group_pattern_compiled
              ~cancel ~grain inputs.(1) with
           | Error error -> Error error
           | Ok target_points ->
               match Pdk.Attribute_ops.transfer_surface
                   ~cancel ~grain ?max_distance ~blend_width
                   ~falloff ~unmatched ~target_owner ?distance_attribute
                   ?source_primitives ?source_vertices ~source_vertex_selection
                   ?target_elements:target_points
                   ~attributes ~source:inputs.(0)
                   ~target:inputs.(1) () with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error)))

let attribute_transfer_all ?label ?point_pattern ?vertex_pattern
    ?primitive_pattern ?detail_pattern ?(mode = Pdk.Attribute_ops.Nearest)
    ?max_distance ?(blend_width = 0.)
    ?(falloff = Pdk.Attribute_ops.Smoothstep)
    ?(unmatched = Pdk.Attribute_ops.Keep_target) ~source ~target () =
  if point_pattern = None && vertex_pattern = None
      && primitive_pattern = None && detail_pattern = None then
    invalid_arg "Sop.attribute_transfer_all: at least one owner pattern is required";
  List.iter (fun (owner, pattern) -> match pattern with
    | None -> ()
    | Some pattern ->
        (match Pdk.Attribute_pattern.compile pattern with
         | Ok _ -> ()
         | Error message -> invalid_arg (Printf.sprintf
             "Sop.attribute_transfer_all: invalid %s pattern: %s" owner message)))
    ["point", point_pattern; "vertex", vertex_pattern;
     "primitive", primitive_pattern; "detail", detail_pattern];
  let maximum_key = match max_distance with
    | None -> "unbounded" | Some value -> float_key value in
  Node.Private.make ?label ~operation:"attribute_transfer_all" ~version:1
    ~parameters:(String.concat ";" [
      "point_pattern=" ^ option_string_key point_pattern;
      "vertex_pattern=" ^ option_string_key vertex_pattern;
      "primitive_pattern=" ^ option_string_key primitive_pattern;
      "detail_pattern=" ^ option_string_key detail_pattern;
      "mode=" ^ transfer_mode_key mode;
      "max_distance=" ^ maximum_key;
      "blend_width=" ^ float_key blend_width;
      "falloff=" ^ transfer_falloff_key falloff;
      "unmatched=" ^ unmatched_key unmatched])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|source; target|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Attribute_ops.transfer_all
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
          ~mode ?max_distance ~blend_width ~falloff ~unmatched
          ~source:inputs.(0) ~target:inputs.(1) () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_owner_key = function
  | Pdk.Group.Point -> "point"
  | Pdk.Group.Vertex -> "vertex"
  | Pdk.Group.Primitive -> "primitive"

let attribute_count geometry = function
  | Pdk.Attribute.Point -> Pdk.Geometry.point_count geometry
  | Pdk.Attribute.Vertex -> Pdk.Geometry.vertex_count geometry
  | Pdk.Attribute.Primitive -> Pdk.Geometry.primitive_count geometry
  | Pdk.Attribute.Detail -> 1

let set_attribute_node ?label ~operation ~parameters ~owner ~name make input =
  if String.trim name = "" then invalid_arg ("Sop." ^ operation ^ ": empty name");
  Node.Private.make ?label ~operation ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      let geometry = inputs.(0) in
      match make (attribute_count geometry owner) with
      | Error message -> pdk_error operation message
      | Ok storage ->
          match Pdk.Attribute.create_owned ~name ~owner storage with
          | Error message -> pdk_error operation message
          | Ok attribute ->
              match Pdk.Geometry.with_attribute attribute geometry with
              | Ok geometry -> cooked geometry
              | Error message -> pdk_error operation message)

let set_float ?label ~owner ~name value input =
  set_attribute_node ?label ~operation:"set_float"
    ~parameters:(Printf.sprintf "owner=%s;name=%S;value=%s"
      (attribute_owner_key owner) name (float_key value)) ~owner ~name
    (fun count ->
      if finite value then Ok (Pdk.Attribute.Float (Array.make count value))
      else Error "set_float requires a finite value") input

let set_int ?label ~owner ~name value input =
  set_attribute_node ?label ~operation:"set_int"
    ~parameters:(Printf.sprintf "owner=%s;name=%S;value=%d"
      (attribute_owner_key owner) name value) ~owner ~name
    (fun count -> Ok (Pdk.Attribute.Int (Array.make count value))) input

let set_vector ?label ~owner ~name value input =
  let value = vec3_copy value in
  set_attribute_node ?label ~operation:"set_vector"
    ~parameters:(Printf.sprintf "owner=%s;name=%S;value=%s"
      (attribute_owner_key owner) name (vec3_key value)) ~owner ~name
    (fun count ->
      if finite value.Vec3.x && finite value.y && finite value.z then
        Ok (Pdk.Attribute.Float3 (Pdk.Packed.Float3.Private.of_owned_exn
          ~x:(Array.make count value.x) ~y:(Array.make count value.y)
          ~z:(Array.make count value.z)))
      else Error "set_vector requires finite components") input

let set_orient ?label value input =
  let value = Quat.normalize value in
  set_attribute_node ?label ~operation:"set_orient"
    ~parameters:(Printf.sprintf "x=%s;y=%s;z=%s;w=%s"
      (float_key value.Quat.x) (float_key value.y) (float_key value.z)
      (float_key value.w)) ~owner:Pdk.Attribute.Point ~name:"orient"
    (fun count ->
      if finite value.Quat.x && finite value.y && finite value.z && finite value.w then
        Result.map (fun values -> Pdk.Attribute.Float4 values)
          (Pdk.Packed.Float4.of_owned ~x:(Array.make count value.x)
             ~y:(Array.make count value.y) ~z:(Array.make count value.z)
             ~w:(Array.make count value.w))
      else Error "set_orient requires finite components") input

let set_transform ?label value input =
  let value = matrix_copy value in
  set_attribute_node ?label ~operation:"set_transform"
    ~parameters:("value=" ^ matrix_key value) ~owner:Pdk.Attribute.Point
    ~name:"transform"
    (fun count ->
      let finite_matrix = ref true in
      for row = 0 to 3 do
        for column = 0 to 3 do
          if not (finite (Mat4.get value ~row ~column)) then finite_matrix := false
        done
      done;
      if not !finite_matrix then Error "set_transform requires finite components"
      else if abs_float (Mat4.get value ~row:3 ~column:0) > 1e-12
          || abs_float (Mat4.get value ~row:3 ~column:1) > 1e-12
          || abs_float (Mat4.get value ~row:3 ~column:2) > 1e-12
          || abs_float (Mat4.get value ~row:3 ~column:3 -. 1.) > 1e-12 then
        Error "set_transform requires an affine matrix"
      else if count > Sys.max_array_length / 16 then
        Error "set_transform output exceeds OCaml array limits"
      else begin
        let row = Array.init 16 (fun index ->
          Mat4.get value ~row:(index / 4) ~column:(index mod 4)) in
        let values = Array.make (count * 16) 0. in
        for index = 0 to count - 1 do Array.blit row 0 values (index * 16) 16 done;
        let offsets = Array.init (count + 1) (fun index -> index * 16) in
        Result.map (fun values -> Pdk.Attribute.Float_array values)
          (Pdk.Packed.Float_array.create_owned ~offsets ~values)
      end) input

let set_color ?label ~owner value input =
  let r, g, b, a = Color.to_floats value in
  set_attribute_node ?label ~operation:"set_color"
    ~parameters:(Printf.sprintf "owner=%s;value=%s"
      (attribute_owner_key owner) (color_key value)) ~owner ~name:"Cd"
    (fun count -> Result.map (fun values -> Pdk.Attribute.Float4 values)
      (Pdk.Packed.Float4.of_owned ~x:(Array.make count r) ~y:(Array.make count g)
        ~z:(Array.make count b) ~w:(Array.make count a))) input

let delete_attribute ?label ~owner ~name input =
  Node.Private.make ?label ~operation:"delete_attribute" ~version:1
    ~parameters:(Printf.sprintf "owner=%s;name=%S" (attribute_owner_key owner) name)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      cooked (Pdk.Geometry.without_attribute ~owner name inputs.(0)))

let rename_attribute ?label ~owner ~from ~into input =
  Node.Private.make ?label ~operation:"rename_attribute" ~version:1
    ~parameters:(Printf.sprintf "owner=%s;from=%S;into=%S"
      (attribute_owner_key owner) from into)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Pdk.Geometry.rename_attribute ~owner ~from ~into inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error message -> pdk_error "rename_attribute" message)

let validate_attribute_pattern operation = function
  | None -> ()
  | Some value when String.trim value = "" -> ()
  | Some value ->
      (match Pdk.Attribute_pattern.compile value with
       | Ok _ -> ()
       | Error message -> invalid_arg (operation ^ ": " ^ message))

let delete_attributes ?label ?reference ?(delete_non_selected = false)
    ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern input =
  List.iter (validate_attribute_pattern "Sop.delete_attributes")
    [point_pattern; vertex_pattern; primitive_pattern; detail_pattern];
  let inputs, cook_mode = match reference with
    | None -> [|input|], Node.Duplicate_input 0
    | Some reference -> [|input; reference|], Node.Generic in
  Node.Private.make ?label ~operation:"attribute_delete_pattern" ~version:1
    ~parameters:(String.concat ";" [
      "delete_non_selected=" ^ string_of_bool delete_non_selected;
      "point=" ^ option_string_key point_pattern;
      "vertex=" ^ option_string_key vertex_pattern;
      "primitive=" ^ option_string_key primitive_pattern;
      "detail=" ^ option_string_key detail_pattern;
      "reference=" ^ string_of_bool (Option.is_some reference)])
    ~cook_mode ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let reference = if Array.length inputs = 2 then Some inputs.(1) else None in
      match Pdk.Attribute_ops.delete ~cancel:(Context.cancel_token context)
          ?reference ~delete_non_selected ?point_pattern ?vertex_pattern
          ?primitive_pattern ?detail_pattern inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let attribute_rename_conflict_key = function
  | Pdk.Attribute_ops.Attribute_rename_skip -> "skip"
  | Pdk.Attribute_ops.Attribute_rename_error -> "error"
  | Pdk.Attribute_ops.Attribute_rename_overwrite -> "overwrite"

let attribute_rename_rule_key (rule : Pdk.Attribute_ops.rename_rule) =
  String.concat ":" [
    (match rule.rename_attribute_owner with
     | None -> "any"
     | Some owner -> attribute_owner_key owner);
    String.escaped rule.rename_attribute_pattern;
    String.escaped rule.rename_attribute_replacement;
    attribute_rename_conflict_key rule.rename_attribute_conflict]

let rename_attributes ?label ~rules input =
  let rules = List.map (fun (rule : Pdk.Attribute_ops.rename_rule) ->
      match Pdk.Attribute_pattern.compile_rewrite
          ~pattern:rule.rename_attribute_pattern
          ~replacement:rule.rename_attribute_replacement with
      | Ok _ -> rule
      | Error message -> invalid_arg ("Sop.rename_attributes: " ^ message))
      rules in
  Node.Private.make ?label ~operation:"attribute_rename_pattern" ~version:1
    ~parameters:("rules=" ^ String.concat ","
      (List.map attribute_rename_rule_key rules))
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Attribute_ops.rename ~cancel:(Context.cancel_token context)
          ~rules inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let attribute_swap_method_key = function
  | Pdk.Attribute_ops.Attribute_swap -> "swap"
  | Pdk.Attribute_ops.Attribute_move -> "move"
  | Pdk.Attribute_ops.Attribute_copy -> "copy"

let attribute_swap_rule_key (rule : Pdk.Attribute_ops.swap_rule) =
  String.concat ":" [
    attribute_owner_key rule.swap_attribute_owner;
    String.escaped rule.swap_attribute_source;
    String.escaped rule.swap_attribute_destination;
    attribute_swap_method_key rule.swap_attribute_method]

let swap_attributes ?label ~rules input =
  let rules = List.map (fun (rule : Pdk.Attribute_ops.swap_rule) ->
      let validate pattern replacement =
        match Pdk.Attribute_pattern.compile_rewrite ~pattern ~replacement with
        | Ok _ -> ()
        | Error message -> invalid_arg ("Sop.swap_attributes: " ^ message) in
      validate rule.swap_attribute_source rule.swap_attribute_destination;
      validate rule.swap_attribute_destination rule.swap_attribute_source;
      rule) rules in
  Node.Private.make ?label ~operation:"attribute_swap" ~version:1
    ~parameters:("rules=" ^ String.concat ","
      (List.map attribute_swap_rule_key rules))
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Attribute_ops.swap ~cancel:(Context.cancel_token context)
          ~rules inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let rest_mode_key = function
  | Pdk.Motion.Store_rest -> "store"
  | Pdk.Motion.Extract_rest -> "extract"
  | Pdk.Motion.Swap_rest -> "swap"

let rest_normals_key = function
  | Pdk.Motion.No_rest_normals -> "none"
  | Pdk.Motion.Rest_normals_if_present -> "if_present"
  | Pdk.Motion.Rest_normals_always -> "always"

let rest_position ?label ?reference ?(rest_attribute = "rest")
    ?(normals = Pdk.Motion.No_rest_normals) ?(normal_attribute = "N")
    ?(rest_normal_attribute = "restN") mode input =
  let inputs, cook_mode = match reference with
    | None -> [|input|], Node.Duplicate_input 0
    | Some reference -> [|input; reference|], Node.Generic in
  Node.Private.make ?label ~operation:"rest_position" ~version:1
    ~parameters:(String.concat ";" [
      "mode=" ^ rest_mode_key mode;
      "rest=" ^ String.escaped rest_attribute;
      "normals=" ^ rest_normals_key normals;
      "normal=" ^ String.escaped normal_attribute;
      "rest_normal=" ^ String.escaped rest_normal_attribute;
      "reference=" ^ string_of_bool (Option.is_some reference)])
    ~cook_mode ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let reference = if Array.length inputs = 2 then Some inputs.(1) else None in
      match Pdk.Motion.rest_position ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?reference ~rest_attribute ~normals
          ~normal_attribute ~rest_normal_attribute mode inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let velocity_approximation_key = function
  | Pdk.Motion.Backward_difference -> "backward"
  | Pdk.Motion.Central_difference -> "central"
  | Pdk.Motion.Forward_difference -> "forward"

let velocity_initialization_key = function
  | Pdk.Motion.Compute_from_deformation -> "deformation"
  | Pdk.Motion.Keep_incoming -> "keep"
  | Pdk.Motion.Set_value value -> "set:" ^ vec3_key value
  | Pdk.Motion.From_attribute { name; scale } ->
      "attribute:" ^ String.escaped name ^ ":" ^ float_key scale

let velocity_unmatched_key = function
  | Pdk.Motion.Velocity_unmatched_error -> "error"
  | Pdk.Motion.Velocity_unmatched_zero -> "zero"

let point_velocity ?label ?group ?previous ?next
    ?(approximation = Pdk.Motion.Backward_difference) ?(dt = 1. /. 60.)
    ?(initialization = Pdk.Motion.Compute_from_deformation) ?match_attribute
    ?(unmatched = Pdk.Motion.Velocity_unmatched_error)
    ?(velocity_attribute = "v") ?(add_velocity = Vec3.zero)
    ?(compute_acceleration = false) ?(acceleration_attribute = "accel") input =
  let add_velocity = vec3_copy add_velocity in
  let inputs = Array.of_list (input ::
      (match previous with None -> [] | Some node -> [node]) @
      (match next with None -> [] | Some node -> [node])) in
  let cook_mode = if Array.length inputs = 1 then Node.Duplicate_input 0
      else Node.Generic in
  Node.Private.make ?label ~operation:"point_velocity" ~version:1
    ~parameters:(String.concat ";" [
      "group=" ^ option_string_key group;
      "previous=" ^ string_of_bool (Option.is_some previous);
      "next=" ^ string_of_bool (Option.is_some next);
      "approximation=" ^ velocity_approximation_key approximation;
      "dt=" ^ float_key dt;
      "initialization=" ^ velocity_initialization_key initialization;
      "match=" ^ option_string_key match_attribute;
      "unmatched=" ^ velocity_unmatched_key unmatched;
      "velocity=" ^ String.escaped velocity_attribute;
      "add=" ^ vec3_key add_velocity;
      "acceleration=" ^ string_of_bool compute_acceleration;
      "acceleration_attribute=" ^ String.escaped acceleration_attribute])
    ~cook_mode ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let index = ref 1 in
      let previous = match previous with
        | None -> None
        | Some _ -> let value = Some inputs.(!index) in incr index; value in
      let next = match next with None -> None | Some _ -> Some inputs.(!index) in
      let points = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "point_velocity could not find point group %S" name))) in
      match points with
      | Error error -> Error error
      | Ok points ->
          match Pdk.Motion.point_velocity
              ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
              ?points ?previous ?next ~approximation ~dt ~initialization
              ?match_attribute ~unmatched ~velocity_attribute ~add_velocity
              ~compute_acceleration ~acceleration_attribute inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let rename_group ?label ~owner ~from ~into input =
  Node.Private.make ?label ~operation:"rename_group" ~version:1
    ~parameters:(Printf.sprintf "owner=%s;from=%S;into=%S"
      (group_owner_key owner) from into)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Pdk.Geometry.rename_group ~owner ~from ~into inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error message -> pdk_error "rename_group" message)

let delete_edge_group ?label ~name input =
  if String.trim name = "" then invalid_arg "Sop.delete_edge_group: empty name";
  Node.Private.make ?label ~operation:"delete_edge_group" ~version:1
    ~parameters:(Printf.sprintf "name=%S" name)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      cooked (Pdk.Geometry.without_edge_group name inputs.(0)))

let rename_edge_group ?label ~from ~into input =
  if String.trim from = "" || String.trim into = "" then
    invalid_arg "Sop.rename_edge_group: empty name";
  Node.Private.make ?label ~operation:"rename_edge_group" ~version:1
    ~parameters:(Printf.sprintf "from=%S;into=%S" from into)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Pdk.Geometry.rename_edge_group ~from ~into inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error message -> pdk_error "rename_edge_group" message)

let group ?label ~name selection input =
  if String.trim name = "" then invalid_arg "Sop.group: empty name";
  Node.Private.make ?label ~operation:"group" ~version:1
    ~parameters:(Printf.sprintf "name=%S;selection=%s" name
      (Select.fingerprint selection))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Select.evaluate ~name selection inputs.(0) with
      | Error message -> pdk_error "group" message
      | Ok group ->
          match Pdk.Geometry.with_group group inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error message -> pdk_error "group" message)

let ordered_group ?label ~owner ~name supplied input =
  if String.trim name = "" then invalid_arg "Sop.ordered_group: empty name";
  let elements = Array.copy supplied in
  if Array.exists (fun element -> element < 0) elements then
    invalid_arg "Sop.ordered_group: negative element index";
  let owner_key = match owner with
    | Pdk.Group.Point -> "point"
    | Pdk.Group.Vertex -> "vertex"
    | Pdk.Group.Primitive -> "primitive" in
  Node.Private.make ?label ~operation:"ordered_group" ~version:1
    ~parameters:(Printf.sprintf "owner=%s;name=%S;elements=%s" owner_key name
      (String.concat "," (Array.to_list (Array.map string_of_int elements))))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      let geometry = inputs.(0) in
      let length = match owner with
        | Pdk.Group.Point -> Pdk.Geometry.point_count geometry
        | Pdk.Group.Vertex -> Pdk.Geometry.vertex_count geometry
        | Pdk.Group.Primitive -> Pdk.Geometry.primitive_count geometry in
      match Pdk.Group.ordered ~owner ~name ~length elements with
      | Error message -> pdk_error "ordered_group" message
      | Ok group ->
          match Pdk.Geometry.with_group group geometry with
          | Ok geometry -> cooked geometry
          | Error message -> pdk_error "ordered_group" message)

let topology_group_owner_key = function
  | Pdk.Ops.Group_points -> "point"
  | Pdk.Ops.Group_vertices -> "vertex"
  | Pdk.Ops.Group_primitives -> "primitive"
  | Pdk.Ops.Group_edges -> "edge"

let group_promote_mode_key = function
  | Pdk.Ops.Include_any -> "include_any"
  | Pdk.Ops.Include_all -> "include_all"
  | Pdk.Ops.Include_shared_edge -> "include_shared_edge"

let group_promote ?label ?name ?(keep_original = false) ?output_attribute
    ?(mode = Pdk.Ops.Include_any) ~source ~destination ~group input =
  if String.trim group = "" then invalid_arg "Sop.group_promote: empty group name";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.group_promote: empty output name") name;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.group_promote: empty output attribute name") output_attribute;
  Node.Private.make ?label ~operation:"group_promote" ~version:1
    ~parameters:(String.concat ";" [
      "source=" ^ topology_group_owner_key source;
      "destination=" ^ topology_group_owner_key destination;
      "group=" ^ Printf.sprintf "%S" group;
      "name=" ^ option_string_key name;
      "keep_original=" ^ string_of_bool keep_original;
      "output_attribute=" ^ option_string_key output_attribute;
      "mode=" ^ group_promote_mode_key mode])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_promote ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?name ~keep_original ?output_attribute
          ~mode ~source ~destination ~group inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_promote_operation_key destination = function
  | Pdk.Ops.Promote_elements mode ->
      "elements:" ^ group_promote_mode_key mode
  | Pdk.Ops.Promote_boundary options ->
      let attributes = List.map group_boundary_attribute_key
          options.promote_boundary_attributes in
      String.concat ":" [
        "boundary";
        String.concat "," attributes;
        (if attributes = [] then "0"
         else float_key options.promote_boundary_tolerance);
        string_of_bool options.promote_include_unshared_edges;
        string_of_bool (options.promote_include_unshared_edges
          && options.promote_include_all_unshared_curve_edges);
        string_of_bool (destination = Pdk.Ops.Group_primitives
          && options.promote_include_all_primitives_sharing_boundary_points)]

let group_promotion_rule_key index (rule : Pdk.Ops.group_promotion_rule) =
  let new_name = Option.bind rule.promotion_new_name (fun name ->
    let name = String.trim name in if String.equal name "" then None else Some name) in
  Printf.sprintf "%d:{source=%s;destination=%s;pattern=%S;new_name=%s;keep_original=%b;output_as_attribute=%b;operation=%s}"
    index (topology_group_owner_key rule.promotion_source)
    (topology_group_owner_key rule.promotion_destination)
    (String.trim rule.promotion_pattern) (option_string_key new_name)
    rule.promotion_keep_original rule.promotion_output_as_attribute
    (group_promote_operation_key rule.promotion_destination
      rule.promotion_operation)

let group_promotions ?label ?(max_outputs = 4_096)
    ?(max_payload_bytes = 268_435_456) rules input =
  if max_outputs < 0 then invalid_arg "Sop.group_promotions: negative max_outputs";
  if max_payload_bytes < 0 then
    invalid_arg "Sop.group_promotions: negative max_payload_bytes";
  let rules = List.filter (fun (rule : Pdk.Ops.group_promotion_rule) ->
      String.trim rule.promotion_pattern <> "") rules in
  match rules with
  | [] -> input
  | _ ->
      Node.Private.make ?label ~operation:"group_promotions" ~version:1
        ~parameters:(String.concat ";" [
          "max_outputs=" ^ string_of_int max_outputs;
          "max_payload_bytes=" ^ string_of_int max_payload_bytes;
          "count=" ^ string_of_int (List.length rules);
          "rules=" ^ String.concat ","
            (List.mapi group_promotion_rule_key rules)])
        ~cook_mode:(Node.Duplicate_input 0)
        ~dependencies:Context.Dependencies.static ~inputs:[|input|]
        (fun ~node_id:_ context inputs ->
          match Pdk.Ops.group_promotions ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~max_outputs ~max_payload_bytes
              ~rules inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let group_promote_boundary ?label ?name ?(keep_original = false)
    ?output_attribute ?(attributes = []) ?(tolerance = 1e-6)
    ?(include_unshared_edges = false)
    ?(include_all_unshared_curve_edges = false)
    ?(include_all_primitives_sharing_boundary_points = false)
    ~source ~destination ~group input =
  if String.trim group = "" then
    invalid_arg "Sop.group_promote_boundary: empty group name";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.group_promote_boundary: empty output name") name;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.group_promote_boundary: empty output attribute name")
    output_attribute;
  let attributes = List.map (fun (rule : Pdk.Ops.group_boundary_attribute) ->
    { Pdk.Ops.boundary_attribute_owner = rule.boundary_attribute_owner;
      boundary_attribute_pattern = rule.boundary_attribute_pattern }) attributes in
  Node.Private.make ?label ~operation:"group_promote_boundary" ~version:1
    ~parameters:(String.concat ";" [
      "source=" ^ topology_group_owner_key source;
      "destination=" ^ topology_group_owner_key destination;
      "group=" ^ Printf.sprintf "%S" group;
      "name=" ^ option_string_key name;
      "keep_original=" ^ string_of_bool keep_original;
      "output_attribute=" ^ option_string_key output_attribute;
      "attributes=" ^ String.concat ","
        (List.map group_boundary_attribute_key attributes);
      "tolerance=" ^ float_key tolerance;
      "include_unshared_edges=" ^ string_of_bool include_unshared_edges;
      "include_all_unshared_curve_edges=" ^
        string_of_bool include_all_unshared_curve_edges;
      "include_all_primitives_sharing_boundary_points=" ^
        string_of_bool include_all_primitives_sharing_boundary_points])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_promote_boundary
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ?name ~keep_original ?output_attribute ~attributes ~tolerance
          ~include_unshared_edges ~include_all_unshared_curve_edges
          ~include_all_primitives_sharing_boundary_points
          ~source ~destination ~group inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let primitive_group_connectivity_key = function
  | Pdk.Ops.Primitive_share_points -> "share_points"
  | Pdk.Ops.Primitive_share_edges -> "share_edges"

let group_expand_normal_key = function
  | None -> "none"
  | Some value -> Printf.sprintf "%s:%S"
      (attribute_owner_key value.Pdk.Ops.expand_normal_owner)
      value.expand_normal_name

let group_expand_collision_key = function
  | None -> "none"
  | Some value -> String.concat ":" [
      topology_group_owner_key value.Pdk.Ops.expand_collision_owner;
      Printf.sprintf "%S" value.expand_collision_group;
      string_of_bool value.expand_collision_contain;
      string_of_bool value.expand_collision_allow_boundary]

let group_expand ?label ?name ?(steps = 1) ?(flood = false) ?step_attribute
    ?(primitive_connectivity = Pdk.Ops.Primitive_share_points)
    ?normal_spread ?normal_attribute ?(connectivity_attributes = [])
    ?(connectivity_tolerance = 1e-6) ?collision
    ~owner ~group input =
  let connectivity_attributes = List.map
      (fun (value : Pdk.Ops.group_boundary_attribute) -> {
        Pdk.Ops.boundary_attribute_owner = value.boundary_attribute_owner;
        boundary_attribute_pattern = value.boundary_attribute_pattern })
      connectivity_attributes in
  if String.trim group = "" then invalid_arg "Sop.group_expand: empty group name";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.group_expand: empty output name") name;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.group_expand: empty step attribute name") step_attribute;
  Option.iter (fun value -> if String.trim value.Pdk.Ops.expand_normal_name = "" then
    invalid_arg "Sop.group_expand: empty normal attribute name") normal_attribute;
  Option.iter (fun value ->
    if value.Pdk.Ops.expand_normal_owner = Pdk.Attribute.Detail then
      invalid_arg "Sop.group_expand: detail normal attributes are unsupported")
    normal_attribute;
  Option.iter (fun value -> if String.trim value.Pdk.Ops.expand_collision_group = ""
    then invalid_arg "Sop.group_expand: empty collision group name") collision;
  Option.iter (fun value ->
    if value.Pdk.Ops.expand_collision_contain
        && value.expand_collision_owner = Pdk.Ops.Group_edges then
      invalid_arg "Sop.group_expand: edge collision groups cannot contain growth")
    collision;
  if normal_attribute <> None && normal_spread = None then
    invalid_arg "Sop.group_expand: normal_attribute requires normal_spread";
  if (normal_spread <> None || connectivity_attributes <> [] || collision <> None)
      && owner <> Pdk.Ops.Group_points && owner <> Pdk.Ops.Group_primitives then
    invalid_arg "Sop.group_expand: constraints require point or primitive groups";
  if (connectivity_attributes <> [] || collision <> None)
      && owner = Pdk.Ops.Group_primitives
      && primitive_connectivity <> Pdk.Ops.Primitive_share_edges then
    invalid_arg "Sop.group_expand: constrained primitives must share edges";
  Node.Private.make ?label ~operation:"group_expand" ~version:2
    ~parameters:(String.concat ";" [
      "owner=" ^ topology_group_owner_key owner;
      "group=" ^ Printf.sprintf "%S" group;
      "name=" ^ option_string_key name;
      "steps=" ^ string_of_int steps;
      "flood=" ^ string_of_bool flood;
      "step_attribute=" ^ option_string_key step_attribute;
      "primitive_connectivity=" ^
        primitive_group_connectivity_key primitive_connectivity;
      "normal_spread=" ^ option_float_key normal_spread;
      "normal_attribute=" ^ group_expand_normal_key normal_attribute;
      "connectivity_attributes=" ^ String.concat ","
        (List.map group_boundary_attribute_key connectivity_attributes);
      "connectivity_tolerance=" ^ float_key connectivity_tolerance;
      "collision=" ^ group_expand_collision_key collision])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_expand ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?name ~steps ~flood ?step_attribute
          ~primitive_connectivity ?normal_spread ?normal_attribute
          ~connectivity_attributes ~connectivity_tolerance ?collision
          ~owner ~group inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_boolean_operation_key = function
  | Pdk.Ops.Group_replace -> "replace"
  | Pdk.Ops.Group_union -> "union"
  | Pdk.Ops.Group_intersection -> "intersection"
  | Pdk.Ops.Group_subtract -> "subtract"
  | Pdk.Ops.Group_xor -> "xor"

let group_operand_key (operand : Pdk.Ops.group_operand) =
  Printf.sprintf "%S:%b" operand.pattern operand.inverted

let group_combine_step_key (step : Pdk.Ops.group_combine_step) =
  group_boolean_operation_key step.operation ^ ":" ^ group_operand_key step.operand

let group_combine ?label ~owner ~name ~base ~steps input =
  if String.trim name = "" then invalid_arg "Sop.group_combine: empty output name";
  if String.trim base.Pdk.Ops.pattern = "" then
    invalid_arg "Sop.group_combine: empty base pattern";
  let steps = List.map (fun (step : Pdk.Ops.group_combine_step) ->
    { Pdk.Ops.operation = step.operation;
      operand = { Pdk.Ops.pattern = step.operand.pattern;
        inverted = step.operand.inverted } }) steps in
  let base = { Pdk.Ops.pattern = base.pattern; inverted = base.inverted } in
  Node.Private.make ?label ~operation:"group_combine" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ topology_group_owner_key owner;
      "name=" ^ Printf.sprintf "%S" name;
      "base=" ^ group_operand_key base;
      "steps=" ^ String.concat "," (List.map group_combine_step_key steps)])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_combine ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~owner ~name ~base ~steps inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_range_key = function
  | Pdk.Ops.Range_start_end { start; end_ } ->
      Printf.sprintf "start_end:%d:%d" start end_
  | Pdk.Ops.Range_from_ends { start; end_offset } ->
      Printf.sprintf "from_ends:%d:%d" start end_offset
  | Pdk.Ops.Range_start_length { start; length } ->
      Printf.sprintf "start_length:%d:%d" start length
  | Pdk.Ops.Range_partition { partition; partitions } ->
      Printf.sprintf "partition:%d:%d" partition partitions

let group_range_filter_key = function
  | None -> "none"
  | Some (filter : Pdk.Ops.group_range_filter) ->
      Printf.sprintf "%d:%d:%d" filter.select filter.of_ filter.offset

let group_range_connectivity_key = function
  | None -> "global"
  | Some (Pdk.Ops.Range_disconnected { region }) ->
      "disconnected:" ^ (match region with
        | None -> "all"
        | Some region -> string_of_int region)
  | Some (Pdk.Ops.Range_connected { connectivity_attributes;
      connectivity_tolerance; collision; region; remove_other_regions }) ->
      let attributes = match connectivity_attributes with
        | None -> "none"
        | Some pattern ->
            let pattern = String.trim pattern in
            if String.equal pattern "" then "none" else Printf.sprintf "%S" pattern in
      let tolerance = if String.equal attributes "none" then 0.
        else connectivity_tolerance in
      let collision = match collision with
        | None -> "none"
        | Some collision -> Printf.sprintf "%s:%S:%b"
            (topology_group_owner_key collision.collision_owner)
            (String.trim collision.collision_pattern) collision.keep_boundary in
      Printf.sprintf "connected:%s:%.17g:%s:%s:%b" attributes
        tolerance collision
        (match region with None -> "all" | Some region -> string_of_int region)
        (if region = None then true else remove_other_regions)

let group_range ?label ?base ?(invert = false) ?filter ?connectivity
    ?(merge = Pdk.Ops.Group_replace) ~owner ~name range input =
  if String.trim name = "" then invalid_arg "Sop.group_range: empty output name";
  Option.iter (fun pattern -> if String.trim pattern = "" then
    invalid_arg "Sop.group_range: empty base pattern") base;
  Node.Private.make ?label ~operation:"group_range" ~version:3
    ~parameters:(String.concat ";" [
      "owner=" ^ topology_group_owner_key owner;
      "name=" ^ Printf.sprintf "%S" name;
      "base=" ^ option_string_key base;
      "invert=" ^ string_of_bool invert;
      "filter=" ^ group_range_filter_key filter;
      "connectivity=" ^ group_range_connectivity_key connectivity;
      "merge=" ^ group_boolean_operation_key merge;
      "range=" ^ group_range_key range])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_range ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?base ~invert ?filter ?connectivity
          ~merge ~owner ~name range inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_range_rule_key index (rule : Pdk.Ops.group_range_rule) =
  Printf.sprintf "%d:{owner=%s;name=%S;base=%s;invert=%b;filter=%s;connectivity=%s;merge=%s;range=%s}"
    index (topology_group_owner_key rule.range_owner) rule.range_name
    (option_string_key rule.range_base) rule.range_invert
    (group_range_filter_key rule.range_filter)
    (group_range_connectivity_key rule.range_connectivity)
    (group_boolean_operation_key rule.range_merge)
    (group_range_key rule.range_specification)

let group_ranges ?label rules input =
  let rules = List.filter (fun (rule : Pdk.Ops.group_range_rule) ->
      String.trim rule.range_name <> "") rules in
  List.iter (fun (rule : Pdk.Ops.group_range_rule) ->
    Option.iter (fun pattern -> if String.trim pattern = "" then
      invalid_arg "Sop.group_ranges: empty base pattern") rule.range_base) rules;
  match rules with
  | [] -> input
  | _ ->
      Node.Private.make ?label ~operation:"group_ranges" ~version:1
        ~parameters:(Printf.sprintf "count=%d;rules=%s" (List.length rules)
          (String.concat "," (List.mapi group_range_rule_key rules)))
        ~cook_mode:(Node.Duplicate_input 0)
        ~dependencies:Context.Dependencies.static ~inputs:[|input|]
        (fun ~node_id:_ context inputs ->
          match Pdk.Ops.group_ranges ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~rules inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let group_rename_conflict_key = function
  | Pdk.Ops.Rename_skip -> "skip"
  | Pdk.Ops.Rename_error -> "error"
  | Pdk.Ops.Rename_overwrite -> "overwrite"
  | Pdk.Ops.Rename_union -> "union"

let optional_topology_group_owner_key = function
  | None -> "any" | Some owner -> topology_group_owner_key owner

let group_invert ?label ?(conflict = Pdk.Ops.Rename_overwrite) ?owner
    ~pattern ?new_name input =
  if String.trim pattern = "" then invalid_arg "Sop.group_invert: empty pattern";
  Option.iter (fun pattern -> if String.trim pattern = "" then
    invalid_arg "Sop.group_invert: empty new-name pattern") new_name;
  Node.Private.make ?label ~operation:"group_invert" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ optional_topology_group_owner_key owner;
      "pattern=" ^ Printf.sprintf "%S" pattern;
      "new_name=" ^ option_string_key new_name;
      "conflict=" ^ group_rename_conflict_key conflict])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Pdk.Ops.group_invert ~conflict ?owner ~pattern ?new_name inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_delete_rule_key (rule : Pdk.Ops.group_delete_rule) =
  optional_topology_group_owner_key rule.delete_owner ^ ":"
  ^ Printf.sprintf "%S" rule.delete_pattern

let group_delete ?label ?(delete_unused = false) ~rules input =
  let rules = List.map (fun (rule : Pdk.Ops.group_delete_rule) ->
    { Pdk.Ops.delete_owner = rule.delete_owner;
      delete_pattern = rule.delete_pattern }) rules in
  Node.Private.make ?label ~operation:"group_delete" ~version:1
    ~parameters:(Printf.sprintf "delete_unused=%b;rules=%s" delete_unused
      (String.concat "," (List.map group_delete_rule_key rules)))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Pdk.Ops.group_delete ~rules ~delete_unused inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_rename_rule_key (rule : Pdk.Ops.group_rename_rule) =
  String.concat ":" [
    optional_topology_group_owner_key rule.rename_owner;
    Printf.sprintf "%S" rule.rename_pattern;
    Printf.sprintf "%S" rule.rename_replacement;
    group_rename_conflict_key rule.rename_conflict]

let group_rename ?label ~rules input =
  let rules = List.map (fun (rule : Pdk.Ops.group_rename_rule) ->
    { Pdk.Ops.rename_owner = rule.rename_owner;
      rename_pattern = rule.rename_pattern;
      rename_replacement = rule.rename_replacement;
      rename_conflict = rule.rename_conflict }) rules in
  Node.Private.make ?label ~operation:"group_rename" ~version:1
    ~parameters:("rules=" ^ String.concat ","
      (List.map group_rename_rule_key rules))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Pdk.Ops.group_rename ~rules inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_copy_conflict_key = function
  | Pdk.Ops.Copy_skip -> "skip"
  | Pdk.Ops.Copy_overwrite -> "overwrite"
  | Pdk.Ops.Copy_add_suffix -> "add_suffix"

let group_copy_rule_key (rule : Pdk.Ops.group_copy_rule) =
  String.concat ":" [topology_group_owner_key rule.copy_owner;
    Printf.sprintf "%S" rule.copy_pattern;
    Printf.sprintf "%S" rule.copy_prefix;
    option_string_key rule.match_attribute]

let group_copy ?label ?rules ?(conflict = Pdk.Ops.Copy_skip)
    ?(copy_empty = false) ~source ~target () =
  let rules = Option.map (List.map (fun (rule : Pdk.Ops.group_copy_rule) ->
    { Pdk.Ops.copy_owner = rule.copy_owner;
      copy_pattern = rule.copy_pattern;
      copy_prefix = rule.copy_prefix;
      match_attribute = rule.match_attribute })) rules in
  Node.Private.make ?label ~operation:"group_copy" ~version:1
    ~parameters:(String.concat ";" [
      "rules=" ^ (match rules with None -> "default" | Some rules ->
        String.concat "," (List.map group_copy_rule_key rules));
      "conflict=" ^ group_copy_conflict_key conflict;
      "copy_empty=" ^ string_of_bool copy_empty])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|source; target|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_copy ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?rules ~conflict ~copy_empty
          ~source:inputs.(0) ~target:inputs.(1) () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_transfer_rule_key (rule : Pdk.Ops.group_transfer_rule) =
  String.concat ":" [topology_group_owner_key rule.transfer_owner;
    Printf.sprintf "%S" rule.transfer_pattern;
    Printf.sprintf "%S" rule.transfer_prefix]

let group_transfer ?label ?rules ?(conflict = Pdk.Ops.Copy_skip)
    ?(create_empty = false) ?(distance = 0.001) ~source ~target () =
  let rules = Option.map (List.map (fun (rule : Pdk.Ops.group_transfer_rule) ->
    { Pdk.Ops.transfer_owner = rule.transfer_owner;
      transfer_pattern = rule.transfer_pattern;
      transfer_prefix = rule.transfer_prefix })) rules in
  Node.Private.make ?label ~operation:"group_transfer" ~version:1
    ~parameters:(String.concat ";" [
      "rules=" ^ (match rules with None -> "default" | Some rules ->
        String.concat "," (List.map group_transfer_rule_key rules));
      "conflict=" ^ group_copy_conflict_key conflict;
      "create_empty=" ^ string_of_bool create_empty;
      "distance=" ^ float_key distance])
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|source; target|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_transfer ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?rules ~conflict ~create_empty ~distance
          ~source:inputs.(0) ~target:inputs.(1) () with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_path_mode_key = function
  | Pdk.Ops.Through_each -> "through_each"
  | Pdk.Ops.Start_end_pairs -> "start_end_pairs"

let group_path_ending_key = function
  | Pdk.Ops.Stop_at_end -> "stop_at_end"
  | Pdk.Ops.Close_path -> "close_path"

let group_find_path ?label ?(mode = Pdk.Ops.Through_each)
    ?(ending = Pdk.Ops.Stop_at_end) ?(avoid_self_intersection = true)
    ?(owner = Pdk.Group.Point) ?collision_group ?(contain = false)
    ~base_group ~name input =
  Node.Private.make ?label ~operation:"group_find_path" ~version:2
    ~parameters:(String.concat ";" [
      "mode=" ^ group_path_mode_key mode;
      "ending=" ^ group_path_ending_key ending;
      "avoid_self_intersection=" ^ string_of_bool avoid_self_intersection;
      "owner=" ^ group_owner_key owner;
      "collision_group=" ^ option_string_key collision_group;
      "contain=" ^ string_of_bool contain;
      "base_group=" ^ Printf.sprintf "%S" base_group;
      "name=" ^ Printf.sprintf "%S" name])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      match Pdk.Geometry.find_group ~owner base_group geometry with
      | None -> Error (Diagnostic.error ~code:"missing_group"
          (Printf.sprintf "group_find_path could not find %s group %S"
            (group_owner_key owner) base_group))
      | Some base ->
          let collision = match collision_group with
            | None -> Ok None
            | Some group ->
                (match Pdk.Geometry.find_group ~owner group geometry with
                 | Some group -> Ok (Some group)
                 | None -> Error (Diagnostic.error ~code:"missing_group"
                     (Printf.sprintf
                       "group_find_path could not find collision %s group %S"
                       (group_owner_key owner) group))) in
          Result.bind collision (fun collision ->
            match Pdk.Ops.group_find_path
                ~cancel:(Context.cancel_token context)
                ~grain:(Context.grain context) ~mode ~ending
                ~avoid_self_intersection ?collision ~contain ~base ~name geometry with
            | Ok geometry -> cooked geometry
            | Error error -> structured_pdk_error error))

let delete_policy_key = function
  | Pdk.Ops.Destroy_touched_primitives -> "destroy_touched_primitives"
  | Pdk.Ops.Heal_primitives -> "heal_primitives"

let blast_attribute_owner_key = function
  | Pdk.Ops.Blast_points -> "points"
  | Pdk.Ops.Blast_primitives -> "primitives"

let blast_attribute_mode_key = function
  | Pdk.Ops.Blast_below threshold -> "below:" ^ float_key threshold
  | Pdk.Ops.Blast_range { minimum; maximum } ->
      String.concat ":" ["range"; float_key minimum; float_key maximum]
  | Pdk.Ops.Blast_width { center; width } ->
      String.concat ":" ["width"; float_key center; float_key width]

let blast_attribute_output_key = function
  | Pdk.Ops.Blast_delete -> "delete"
  | Pdk.Ops.Blast_group name -> "group:" ^ String.escaped name

let blast_by_attribute ?label ?group ?(invert = false)
    ?(remove_unused_points = false) ~owner ~attribute ~mode ~output input =
  if String.trim attribute = "" then
    invalid_arg "Sop.blast_by_attribute: empty attribute name";
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.blast_by_attribute: empty base group name") group;
  (match output with Pdk.Ops.Blast_group name when String.trim name = "" ->
     invalid_arg "Sop.blast_by_attribute: empty output group name"
   | Pdk.Ops.Blast_delete | Pdk.Ops.Blast_group _ -> ());
  Node.Private.make ?label ~operation:"blast_by_attribute" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ blast_attribute_owner_key owner;
      "attribute=" ^ String.escaped attribute;
      "mode=" ^ blast_attribute_mode_key mode;
      "output=" ^ blast_attribute_output_key output;
      "group=" ^ option_string_key group;
      "invert=" ^ string_of_bool invert;
      "remove_unused_points=" ^ string_of_bool remove_unused_points])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let geometry = inputs.(0) in
      let group_owner = match owner with
        | Pdk.Ops.Blast_points -> Pdk.Group.Point
        | Pdk.Ops.Blast_primitives -> Pdk.Group.Primitive in
      let base = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:group_owner name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                   "blast_by_attribute could not find %s group %S"
                   (blast_attribute_owner_key owner) name))) in
      Result.bind base (fun base ->
        match Pdk.Ops.blast_by_attribute
            ~cancel:(Context.cancel_token context)
            ~grain:(Context.grain context) ?base ~invert ~remove_unused_points
            ~owner ~attribute ~mode ~output geometry with
        | Ok geometry -> cooked geometry
        | Error error -> structured_pdk_error error))

let delete ?label ?(selected = true) ?(compact_points = false)
    ?(policy = Pdk.Ops.Destroy_touched_primitives) selection input =
  Node.Private.make ?label ~operation:"delete" ~version:1
    ~parameters:(Printf.sprintf
      "selected=%b;compact_points=%b;policy=%s;selection=%s"
      selected compact_points (delete_policy_key policy)
      (Select.fingerprint selection))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ _context inputs ->
      match Select.evaluate ~name:"__delete" selection inputs.(0) with
      | Error message -> pdk_error "delete" message
      | Ok selection ->
          match Pdk.Ops.delete ~cancel:(Context.cancel_token _context)
              ~grain:(Context.grain _context) ~selected ~compact_points ~policy
              selection inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let group_owner_key = function
  | Pdk.Group.Point -> "point"
  | Pdk.Group.Vertex -> "vertex"
  | Pdk.Group.Primitive -> "primitive"

let blast ?label ?(selected = true) ?(compact_points = false)
    ?(policy = Pdk.Ops.Destroy_touched_primitives) ~owner ~group input =
  if String.trim group = "" then invalid_arg "Sop.blast: empty group name";
  Node.Private.make ?label ~operation:"blast" ~version:1
    ~parameters:(Printf.sprintf
      "owner=%s;group=%S;selected=%b;compact_points=%b;policy=%s"
      (group_owner_key owner) group selected compact_points
      (delete_policy_key policy))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Geometry.find_group ~owner group inputs.(0) with
      | None -> Error (Diagnostic.error ~code:"missing_group"
          ~hints:["Create the typed group before Blast or correct its owner/name"]
          (Printf.sprintf "blast could not find %s group %S"
            (group_owner_key owner) group))
      | Some selection ->
          match Pdk.Ops.delete ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ~selected ~compact_points ~policy
              selection inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let split ?label ?(compact_points = false)
    ?(policy = Pdk.Ops.Destroy_touched_primitives) selection input =
  let selected_label = Option.map (fun value -> value ^ " selected") label
  and remainder_label = Option.map (fun value -> value ^ " remainder") label in
  delete ?label:selected_label ~selected:false ~compact_points ~policy selection input,
  delete ?label:remainder_label ~selected:true ~compact_points ~policy selection input

let compact_points ?label input =
  unary_result ?label ~operation:"compact_points"
    (fun context geometry -> Pdk.Ops.compact_points
      ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
      geometry) input

let bounding_box ?label ?(padding = Vec3.zero) input =
  let padding = vec3_copy padding in
  Node.Private.make ?label ~operation:"bounding_box" ~version:1
    ~parameters:("padding=" ^ vec3_key padding)
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Ops.bounding_box ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~padding inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let match_size_fit_key = function
  | Pdk.Ops.Translate_only -> "translate_only"
  | Pdk.Ops.Stretch -> "stretch"
  | Pdk.Ops.Contain -> "contain"
  | Pdk.Ops.Cover -> "cover"
  | Pdk.Ops.Match_x -> "match_x"
  | Pdk.Ops.Match_y -> "match_y"
  | Pdk.Ops.Match_z -> "match_z"
  | Pdk.Ops.Match_perimeter -> "match_perimeter"
  | Pdk.Ops.Match_area -> "match_area"
  | Pdk.Ops.Match_volume -> "match_volume"

let match_axis ?label ~from ~into input =
  let from = vec3_copy from and into = vec3_copy into in
  Node.Private.make ?label ~operation:"match_axis" ~version:1
    ~parameters:(Printf.sprintf "from=%s;into=%s" (vec3_key from) (vec3_key into))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.match_axis ~grain:(Context.grain context) ~from ~into inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let sort ?label ?group ?(descending = false) ?output_indices
    ?(combine_indices = false) ~owner ~key input =
  let owner_key = match owner with Pdk.Ops.Points -> "points"
    | Pdk.Ops.Primitives -> "primitives" in
  let key_key = match key with
    | Pdk.Ops.X -> "x" | Pdk.Ops.Y -> "y" | Pdk.Ops.Z -> "z"
    | Pdk.Ops.Distance_to point -> "distance:" ^ vec3_key point
    | Pdk.Ops.Along_vector vector -> "vector:" ^ vec3_key vector
    | Pdk.Ops.Attribute_component { name; component } ->
        Printf.sprintf "attribute:%s:%d" (String.escaped name) component
    | Pdk.Ops.By_vertex_order -> "vertex_order"
    | Pdk.Ops.By_primitive_index -> "primitive_index"
    | Pdk.Ops.Spatial_locality -> "spatial_locality"
    | Pdk.Ops.Random seed -> "random:" ^ Int64.to_string seed
    | Pdk.Ops.Index_attribute name ->
        "index_attribute:" ^ String.escaped name
    | Pdk.Ops.Reverse -> "reverse"
    | Pdk.Ops.Shift offset -> "shift:" ^ string_of_int offset in
  Node.Private.make ?label ~operation:"sort" ~version:2
    ~parameters:(String.concat ";" ["owner=" ^ owner_key; "key=" ^ key_key;
      "group=" ^ option_string_key group; "descending=" ^ string_of_bool descending;
      "output_indices=" ^ option_string_key output_indices;
      "combine_indices=" ^ string_of_bool combine_indices])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      let group_owner = match owner with Pdk.Ops.Points -> Pdk.Group.Point
        | Pdk.Ops.Primitives -> Pdk.Group.Primitive in
      let selection = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:group_owner name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "sort could not find %s group %S" owner_key name))) in
      match selection with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.sort ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~descending
              ?output_indices ~combine_indices ~owner ~key inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let match_size ?label ?selection ?source_selection ?target_selection
    ?(fit = Pdk.Ops.Contain) ?(translate_axes = true, true, true)
    ?(scale_axes = true, true, true) ?(justify = Vec3.zero) ?target_justify
    ?(offset = Vec3.zero) ?(scale = 1.) ?target_center ?target_size ?target
    input =
  let validate_selection label = function
    | None -> ()
    | Some selection ->
        let name = match selection with Point_group name | Vertex_group name
          | Primitive_group name | Edge_group name -> name in
        if String.trim name = "" then
          invalid_arg ("Sop.match_size: empty " ^ label ^ " group") in
  validate_selection "move" selection;
  validate_selection "source" source_selection;
  validate_selection "target" target_selection;
  let justify = vec3_copy justify
  and target_justify = Option.map vec3_copy target_justify
  and offset = vec3_copy offset
  and target_center = Option.map vec3_copy target_center
  and target_size = Option.map vec3_copy target_size in
  let axes_key (x, y, z) = Printf.sprintf "%b,%b,%b" x y z
  and selection_key = function
    | None -> "none"
    | Some (Point_group name) -> "point:" ^ String.escaped name
    | Some (Vertex_group name) -> "vertex:" ^ String.escaped name
    | Some (Primitive_group name) -> "primitive:" ^ String.escaped name
    | Some (Edge_group name) -> "edge:" ^ String.escaped name
  and optional_vec3_key = function
    | None -> "none" | Some value -> vec3_key value in
  let parameters = String.concat ";" [
      "fit=" ^ match_size_fit_key fit;
      "move=" ^ selection_key selection;
      "source=" ^ selection_key source_selection;
      "target=" ^ selection_key target_selection;
      "translate_axes=" ^ axes_key translate_axes;
      "scale_axes=" ^ axes_key scale_axes;
      "justify=" ^ vec3_key justify;
      "target_justify=" ^ optional_vec3_key target_justify;
      "offset=" ^ vec3_key offset;
      "scale=" ^ float_key scale;
      "target_center=" ^ optional_vec3_key target_center;
      "target_size=" ^ optional_vec3_key target_size;
      "target_input=" ^ string_of_bool (Option.is_some target) ] in
  let inputs = match target with None -> [|input|] | Some target -> [|input; target|] in
  Node.Private.make ?label ~operation:"match_size" ~version:2 ~parameters
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static ~inputs
    (fun ~node_id:_ context inputs ->
      let source = inputs.(0)
      and target = if Array.length inputs = 2 then Some inputs.(1) else None in
      match resolve_element_group ~operation:"match_size" selection source with
      | Error error -> Error error
      | Ok selection ->
          (match resolve_element_group ~operation:"match_size source"
              source_selection source with
           | Error error -> Error error
           | Ok source_selection ->
               let target_selection_result = match target with
                 | None ->
                     (match target_selection with
                      | None -> Ok None
                      | Some _ -> Error (Diagnostic.error ~code:"missing_target"
                          "match_size target selection requires a target node"))
                 | Some target -> resolve_element_group
                     ~operation:"match_size target" target_selection target in
               (match target_selection_result with
                | Error error -> Error error
                | Ok target_selection ->
                    match Pdk.Ops.match_size
                        ~cancel:(Context.cancel_token context)
                        ~grain:(Context.grain context) ?selection
                        ?source_selection ?target_selection ~fit ~translate_axes
                        ~scale_axes ~justify ?target_justify ~offset ~scale
                        ?target_center ?target_size ?target source with
                    | Ok geometry -> cooked geometry
                    | Error error -> structured_pdk_error error)))

let custom ?label ?(version = 1) ?(parameters = "")
    ?(cook_mode = Node.Generic) ?(dependencies = Context.Dependencies.static)
    ~operation inputs cook =
  let inputs = Array.of_list inputs in
  Node.Private.make ?label ~operation ~version ~parameters ~cook_mode
    ~dependencies ~inputs (fun ~node_id:_ context geometries ->
      if Context.cancelled context then
        Error (Diagnostic.error ~code:"cancelled"
          "custom procedural node was cancelled before cooking")
      else match cook ~context (Array.copy geometries) with
        | Ok geometry -> cooked geometry
        | Error message -> pdk_error operation message)

type point_range_kernel =
  context:Context.t -> first:int -> last:int -> x:float array -> y:float array ->
  z:float array -> unit

let native_point_ranges ?label ?grain ~key ~version ~dependencies kernel input =
  if String.trim key = "" then invalid_arg "Sop.native_point_ranges: empty key";
  (match grain with Some value when value <= 0 ->
     invalid_arg "Sop.native_point_ranges: grain must be positive"
   | _ -> ());
  let parameters = Printf.sprintf "key=%S;version=%d;grain=%s" key version
      (match grain with None -> "context" | Some grain -> string_of_int grain) in
  Node.Private.make ?label ~operation:"native_point_ranges" ~version ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      let grain = Option.value ~default:(Context.grain context) grain in
      try
        let geometry = Pdk.Kernel.edit_point_ranges ~grain
            (fun ~first ~last ~x ~y ~z ->
              if Context.cancelled context then raise Native_cancelled;
              kernel ~context ~first ~last ~x ~y ~z) inputs.(0) in
        cooked geometry
      with Native_cancelled ->
        Error (Diagnostic.error ~code:"cancelled"
          "native point-range kernel was cancelled"))

let stable_string_hash value =
  let hash = ref 0xcbf29ce484222325L in
  String.iter (fun character ->
    hash := Int64.mul (Int64.logxor !hash (Int64.of_int (Char.code character)))
        0x100000001b3L) value;
  !hash

let mixed_seed context identity =
  let mixed = Int64.logxor (Context.seed context)
      (Int64.mul identity 0x9e3779b97f4a7c15L) in
  Int64.to_int (Int64.logxor mixed (Int64.shift_right_logical mixed 32))

let group_random ?label ?seed ?seed_attribute ?base
    ?(merge = Pdk.Ops.Group_replace) ~probability ~owner ~name input =
  if String.trim name = "" then invalid_arg "Sop.group_random: empty group name";
  if not (Float.is_finite probability) || probability < 0. || probability > 1.
  then invalid_arg "Sop.group_random: probability must be in [0,1]";
  List.iter (fun (field, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.group_random: empty " ^ field)
    | None | Some _ -> ())
    ["seed attribute name", seed_attribute; "base group name", base];
  let dependencies = match seed with
    | Some _ -> Context.Dependencies.static
    | None -> Context.Dependencies.one Context.Dependencies.Seed in
  let stable_identity = Option.map (fun label ->
    stable_string_hash ("group_random:" ^ label)) label in
  Node.Private.make ?label ~operation:"group_random" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ boundary_group_owner_key owner;
      "name=" ^ Printf.sprintf "%S" name;
      "probability=" ^ float_key probability;
      "seed=" ^ (match seed with None -> "context"
        | Some seed -> string_of_int seed);
      "seed_attribute=" ^ option_string_key seed_attribute;
      "base=" ^ option_string_key base;
      "merge=" ^ group_boolean_operation_key merge])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
    (fun ~node_id context inputs ->
      let identity = Option.value ~default:(Int64.of_int node_id)
          stable_identity in
      let seed = Rand.seed (Option.value ~default:(mixed_seed context identity)
          seed) in
      match Pdk.Ops.group_random ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~seed ?seed_attribute ?base ~merge
          ~probability ~owner ~name inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_bounds_key = function
  | Pdk.Ops.Bounds_box { minimum; maximum } ->
      "box:" ^ vec3_key minimum ^ ":" ^ vec3_key maximum
  | Pdk.Ops.Bounds_sphere { center; radius } ->
      "sphere:" ^ vec3_key center ^ ":" ^ float_key radius

let copy_group_bounds = function
  | Pdk.Ops.Bounds_box { minimum; maximum } ->
      Pdk.Ops.Bounds_box {
        minimum = vec3_copy minimum;
        maximum = vec3_copy maximum;
      }
  | Pdk.Ops.Bounds_sphere { center; radius } ->
      Pdk.Ops.Bounds_sphere { center = vec3_copy center; radius }

let group_containment_key = function
  | Pdk.Ops.Fully_contained -> "full"
  | Pdk.Ops.Partially_contained -> "partial"

let group_bounds ?label ?base ?(containment = Pdk.Ops.Fully_contained)
    ?(merge = Pdk.Ops.Group_replace) bounds ~owner ~name input =
  if String.trim name = "" then invalid_arg "Sop.group_bounds: empty group name";
  (match base with Some value when String.trim value = "" ->
     invalid_arg "Sop.group_bounds: empty base group name"
   | None | Some _ -> ());
  let bounds = copy_group_bounds bounds in
  Node.Private.make ?label ~operation:"group_bounds" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ boundary_group_owner_key owner;
      "name=" ^ Printf.sprintf "%S" name;
      "base=" ^ option_string_key base;
      "containment=" ^ group_containment_key containment;
      "merge=" ^ group_boolean_operation_key merge;
      "bounds=" ^ group_bounds_key bounds])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_bounds ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?base ~containment ~merge bounds
          ~owner ~name inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_normal ?label ?normal_attribute ?(use_existing_normal = true) ?base
    ?(include_opposite = false) ?(merge = Pdk.Ops.Group_replace)
    ~direction ~spread_angle ~owner ~name input =
  if String.trim name = "" then invalid_arg "Sop.group_normal: empty group name";
  if not (Float.is_finite direction.Vec3.x && Float.is_finite direction.y
      && Float.is_finite direction.z) then
    invalid_arg "Sop.group_normal: direction must be finite";
  if direction.x = 0. && direction.y = 0. && direction.z = 0. then
    invalid_arg "Sop.group_normal: direction must be non-zero";
  if owner = Pdk.Ops.Group_vertices then
    invalid_arg "Sop.group_normal: vertex groups are not supported";
  if not (Float.is_finite spread_angle) || spread_angle < 0.
      || spread_angle > Float.pi then
    invalid_arg "Sop.group_normal: spread angle must be within [0, pi]";
  List.iter (fun (field, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.group_normal: empty " ^ field)
    | None | Some _ -> ())
    ["normal attribute name", normal_attribute; "base group name", base];
  let direction = vec3_copy direction in
  Node.Private.make ?label ~operation:"group_normal" ~version:1
    ~parameters:(String.concat ";" [
      "owner=" ^ boundary_group_owner_key owner;
      "name=" ^ Printf.sprintf "%S" name;
      "normal_attribute=" ^ option_string_key normal_attribute;
      "use_existing_normal=" ^ string_of_bool use_existing_normal;
      "base=" ^ option_string_key base;
      "include_opposite=" ^ string_of_bool include_opposite;
      "merge=" ^ group_boolean_operation_key merge;
      "direction=" ^ vec3_key direction;
      "spread_angle=" ^ float_key spread_angle])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_normal ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?normal_attribute ~use_existing_normal ?base
          ~include_opposite ~merge ~direction ~spread_angle ~owner ~name
          inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_non_planar ?label ?base ?(merge = Pdk.Ops.Group_replace)
    ~tolerance ~name input =
  if String.trim name = "" then
    invalid_arg "Sop.group_non_planar: empty group name";
  if not (Float.is_finite tolerance) || tolerance < 0. then
    invalid_arg "Sop.group_non_planar: tolerance must be finite and non-negative";
  (match base with Some value when String.trim value = "" ->
     invalid_arg "Sop.group_non_planar: empty base group name"
   | None | Some _ -> ());
  Node.Private.make ?label ~operation:"group_non_planar" ~version:1
    ~parameters:(String.concat ";" [
      "name=" ^ Printf.sprintf "%S" name;
      "base=" ^ option_string_key base;
      "merge=" ^ group_boolean_operation_key merge;
      "tolerance=" ^ float_key tolerance])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_non_planar ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?base ~merge ~tolerance ~name inputs.(0)
      with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_backface ?label ?base ?(merge = Pdk.Ops.Group_replace)
    ~viewpoint ~name input =
  if String.trim name = "" then
    invalid_arg "Sop.group_backface: empty group name";
  if not (Float.is_finite viewpoint.Vec3.x && Float.is_finite viewpoint.y
      && Float.is_finite viewpoint.z) then
    invalid_arg "Sop.group_backface: viewpoint must be finite";
  (match base with Some value when String.trim value = "" ->
     invalid_arg "Sop.group_backface: empty base group name"
   | None | Some _ -> ());
  let viewpoint = vec3_copy viewpoint in
  Node.Private.make ?label ~operation:"group_backface" ~version:1
    ~parameters:(String.concat ";" [
      "name=" ^ Printf.sprintf "%S" name;
      "base=" ^ option_string_key base;
      "merge=" ^ group_boolean_operation_key merge;
      "viewpoint=" ^ vec3_key viewpoint])
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_backface ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ?base ~merge ~viewpoint ~name inputs.(0)
      with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_edge_depth ?label ?(merge = Pdk.Ops.Group_replace) ~depth
    ~point_group ~name input =
  if String.trim point_group = "" then
    invalid_arg "Sop.group_edge_depth: empty seed point group name";
  if String.trim name = "" then
    invalid_arg "Sop.group_edge_depth: empty output group name";
  Node.Private.make ?label ~operation:"group_edge_depth" ~version:1
    ~parameters:(Printf.sprintf "depth=%d;point_group=%S;name=%S;merge=%s"
      depth point_group name (group_boolean_operation_key merge))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_edge_depth ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~merge ~depth ~point_group ~name
          inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_unshared ?label ?(merge = Pdk.Ops.Group_replace) ~owner ~name input =
  if String.trim name = "" then
    invalid_arg "Sop.group_unshared: empty output group name";
  Node.Private.make ?label ~operation:"group_unshared" ~version:1
    ~parameters:(Printf.sprintf "owner=%s;name=%S;merge=%s"
      (boundary_group_owner_key owner) name (group_boolean_operation_key merge))
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_unshared ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~merge ~owner ~name inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let group_boundary_components ?label ?(prefix = "boundary")
    ?(conflict = Pdk.Ops.Name_replace) ?(max_groups = 4_096)
    ?(max_payload_bytes = 268_435_456) input =
  if String.trim prefix = "" then
    invalid_arg "Sop.group_boundary_components: empty output prefix";
  Node.Private.make ?label ~operation:"group_boundary_components" ~version:1
    ~parameters:(Printf.sprintf
      "prefix=%S;conflict=%s;max_groups=%d;max_payload_bytes=%d"
      prefix (group_name_conflict_key conflict) max_groups max_payload_bytes)
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.group_boundary_components
          ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
          ~prefix ~conflict ~max_groups ~max_payload_bytes inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let numeric_value_key = function
  | Pdk.Attribute_ops.Scalar value -> "scalar:" ^ float_key value
  | Pdk.Attribute_ops.Vec2 value -> "vec2:" ^ vec2_key value
  | Pdk.Attribute_ops.Vec3 value -> "vec3:" ^ vec3_key value
  | Pdk.Attribute_ops.Vec4 (x, y, z, w) ->
      String.concat ":" ["vec4"; float_key x; float_key y; float_key z;
        float_key w]

let random_operation_key = function
  | Pdk.Attribute_ops.Random_set -> "set"
  | Pdk.Attribute_ops.Random_add -> "add"
  | Pdk.Attribute_ops.Random_minimum -> "minimum"
  | Pdk.Attribute_ops.Random_maximum -> "maximum"
  | Pdk.Attribute_ops.Random_multiply -> "multiply"

let random_distribution_key = function
  | Pdk.Attribute_ops.Random_constant value ->
      "constant:" ^ numeric_value_key value
  | Pdk.Attribute_ops.Random_two_values { a; b; probability_b } ->
      String.concat ":" ["two_values"; numeric_value_key a;
        numeric_value_key b; float_key probability_b]
  | Pdk.Attribute_ops.Random_uniform { min; max } ->
      String.concat ":" ["uniform"; numeric_value_key min;
        numeric_value_key max]
  | Pdk.Attribute_ops.Random_uniform_discrete { min; max; step } ->
      String.concat ":" ["uniform_discrete"; numeric_value_key min;
        numeric_value_key max; numeric_value_key step]
  | Pdk.Attribute_ops.Random_normal { middle; scale } ->
      String.concat ":" ["normal"; numeric_value_key middle;
        numeric_value_key scale]
  | Pdk.Attribute_ops.Random_exponential { median } ->
      "exponential:" ^ numeric_value_key median
  | Pdk.Attribute_ops.Random_log_normal { median; stddev } ->
      String.concat ":" ["log_normal"; numeric_value_key median;
        numeric_value_key stddev]
  | Pdk.Attribute_ops.Random_cauchy { median; scale } ->
      String.concat ":" ["cauchy"; numeric_value_key median;
        numeric_value_key scale]
  | Pdk.Attribute_ops.Random_direction { direction; cone_angle } ->
      String.concat ":" ["direction"; numeric_value_key direction;
        float_key cone_angle]
  | Pdk.Attribute_ops.Random_inside_sphere { dimensions } ->
      "inside_sphere:" ^ string_of_int dimensions
  | Pdk.Attribute_ops.Random_inside_sphere_cone { direction; cone_angle } ->
      String.concat ":" ["inside_sphere_cone"; numeric_value_key direction;
        float_key cone_angle]
  | Pdk.Attribute_ops.Random_custom_ramp { ramp; fit_min; fit_max } ->
      let ramp = ramp |> List.map (fun (position, value) ->
        float_key position ^ "," ^ float_key value) |> String.concat ";" in
      String.concat ":" ["custom_ramp"; ramp; numeric_value_key fit_min;
        numeric_value_key fit_max]
  | Pdk.Attribute_ops.Random_custom_discrete entries ->
      "custom_discrete:" ^ (entries |> List.map (fun (value, weight) ->
        numeric_value_key value ^ "," ^ float_key weight) |> String.concat ";")
  | Pdk.Attribute_ops.Random_custom_discrete_text entries ->
      "custom_discrete_text:" ^ (entries |> List.map (fun (value, weight) ->
        string_of_int (String.length value) ^ ":" ^ value ^ ","
        ^ float_key weight) |> String.concat ";")

let remap_input_key = function
  | Pdk.Attribute_ops.Remap_auto -> "auto"
  | Pdk.Attribute_ops.Remap_explicit { min; max } ->
      String.concat ":" ["explicit"; numeric_value_key min;
        numeric_value_key max]

let remap_policy_key = function
  | Pdk.Attribute_ops.Remap_clamp -> "clamp"
  | Pdk.Attribute_ops.Remap_cycle -> "cycle"
  | Pdk.Attribute_ops.Remap_extrapolate -> "extrapolate"

let attribute_group_owner = function
  | Pdk.Attribute.Point -> Some Pdk.Group.Point
  | Pdk.Attribute.Vertex -> Some Pdk.Group.Vertex
  | Pdk.Attribute.Primitive -> Some Pdk.Group.Primitive
  | Pdk.Attribute.Detail -> None

let resolve_attribute_group ~operation ~owner name geometry = match name with
  | None -> Ok None
  | Some _ when owner = Pdk.Attribute.Detail ->
      Error (Diagnostic.error ~code:"invalid_group"
        (operation ^ " does not accept a group for detail attributes"))
  | Some name ->
      let group_owner = Option.get (attribute_group_owner owner) in
      (match Pdk.Geometry.find_group ~owner:group_owner name geometry with
       | Some group -> Ok (Some group)
       | None -> Error (Diagnostic.error ~code:"missing_group"
           (Printf.sprintf "%s could not find %s group %S" operation
              (attribute_owner_key owner) name)))

let bound_shape_key = function
  | Pdk.Ops.Bound_box { divisions = x, y, z } ->
      Printf.sprintf "box:%d,%d,%d" x y z
  | Pdk.Ops.Bound_sphere { segments; rings; minimum_radius } ->
      String.concat ":" ["sphere"; string_of_int segments; string_of_int rings;
        float_key minimum_radius]

let convex_hull ?label ?selection ?(preserve_point_payload = true)
    ?source_point_attribute ?hull_group input =
  Option.iter (fun selection ->
    let name = match selection with Point_group name | Vertex_group name
      | Primitive_group name | Edge_group name -> name in
    if String.trim name = "" then
      invalid_arg "Sop.convex_hull: empty selection group") selection;
  Option.iter (fun name ->
    if String.trim name = "" || name = "P" then
      invalid_arg
        "Sop.convex_hull: source point attribute must be non-empty and not P")
    source_point_attribute;
  Option.iter (fun name -> if String.trim name = "" then
    invalid_arg "Sop.convex_hull: hull group must be non-empty") hull_group;
  let parameters = String.concat ";" [
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "preserve_point_payload=" ^ string_of_bool preserve_point_payload;
      "source_point_attribute=" ^ option_string_key source_point_attribute;
      "hull_group=" ^ option_string_key hull_group ] in
  Node.Private.make ?label ~operation:"convex_hull" ~version:1 ~parameters
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"convex_hull" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.convex_hull ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~preserve_point_payload
              ?source_point_attribute ?hull_group inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let centroid_piece_owner_key = function
  | Pdk.Ops.Centroid_piece_points -> "points"
  | Pdk.Ops.Centroid_piece_primitives -> "primitives"

let centroid_run_over_key = function
  | Pdk.Ops.Centroid_detail -> "detail"
  | Pdk.Ops.Centroid_primitives -> "primitives"
  | Pdk.Ops.Centroid_pieces {owner; attribute} ->
      String.concat ":" ["pieces"; centroid_piece_owner_key owner;
        String.escaped attribute]

let centroid_method_key = function
  | Pdk.Ops.Centroid_point_mass -> "point_mass"
  | Pdk.Ops.Centroid_bounding_box -> "bounding_box"
  | Pdk.Ops.Centroid_convex_hull -> "convex_hull"

let extract_centroid ?label ?(run_over = Pdk.Ops.Centroid_detail)
    ?(method_ = Pdk.Ops.Centroid_point_mass) ?source_primitive_attribute
    ?piece_output_attribute input =
  (match run_over with
   | Pdk.Ops.Centroid_pieces {attribute; _}
       when String.trim attribute = "" || attribute = "P" ->
       invalid_arg "Sop.extract_centroid: piece attribute must be non-empty and not P"
   | _ -> ());
  List.iter (fun (label, name) -> match name with
    | Some name when String.trim name = "" || name = "P" ->
        invalid_arg ("Sop.extract_centroid: " ^ label
          ^ " must be non-empty and not P")
    | None | Some _ -> ()) [
      "source primitive attribute", source_primitive_attribute;
      "piece output attribute", piece_output_attribute];
  let parameters = String.concat ";" [
      "run_over=" ^ centroid_run_over_key run_over;
      "method=" ^ centroid_method_key method_;
      "source_primitive_attribute="
        ^ option_string_key source_primitive_attribute;
      "piece_output_attribute=" ^ option_string_key piece_output_attribute ] in
  Node.Private.make ?label ~operation:"extract_centroid" ~version:1 ~parameters
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match Pdk.Ops.extract_centroid ~cancel:(Context.cancel_token context)
          ~grain:(Context.grain context) ~run_over ~method_
          ?source_primitive_attribute ?piece_output_attribute inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let bound ?label ?selection
    ?(shape = Pdk.Ops.Bound_box { divisions = 1, 1, 1 })
    ?(lower_padding = Vec3.zero) ?(upper_padding = Vec3.zero) ?bounds_group
    ?center_attribute ?radii_attribute input =
  Option.iter (fun selection ->
    let name = match selection with Point_group name | Vertex_group name
      | Primitive_group name | Edge_group name -> name in
    if String.trim name = "" then invalid_arg "Sop.bound: empty selection group")
    selection;
  List.iter (fun (label, value) -> match value with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.bound: empty " ^ label)
    | None | Some _ -> ()) ["bounds group", bounds_group;
      "center attribute", center_attribute; "radii attribute", radii_attribute];
  let lower_padding = vec3_copy lower_padding
  and upper_padding = vec3_copy upper_padding in
  let parameters = String.concat ";" [
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "shape=" ^ bound_shape_key shape;
      "lower_padding=" ^ vec3_key lower_padding;
      "upper_padding=" ^ vec3_key upper_padding;
      "bounds_group=" ^ option_string_key bounds_group;
      "center_attribute=" ^ option_string_key center_attribute;
      "radii_attribute=" ^ option_string_key radii_attribute ] in
  Node.Private.make ?label ~operation:"bound" ~version:1 ~parameters
    ~cook_mode:Node.Generic ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"bound" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          (match Pdk.Ops.bound ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~shape ~lower_padding
              ~upper_padding ?bounds_group ?center_attribute ?radii_attribute
              inputs.(0) with
           | Ok geometry -> cooked geometry
           | Error error -> structured_pdk_error error))

let ray_method_key = function
  | Pdk.Ops.Ray_minimum_distance -> "minimum_distance"
  | Pdk.Ops.Ray_project -> "project"

let ray_direction_key = function
  | Pdk.Ops.Ray_vector value -> "vector:" ^ vec3_key value
  | Pdk.Ops.Ray_normal -> "normal"
  | Pdk.Ops.Ray_attribute name -> "attribute:" ^ String.escaped name

let ray_direction_mode_key = function
  | Pdk.Ops.Ray_forward -> "forward"
  | Pdk.Ops.Ray_reverse -> "reverse"
  | Pdk.Ops.Ray_bidirectional_closest -> "bidirectional_closest"
  | Pdk.Ops.Ray_bidirectional_farthest -> "bidirectional_farthest"

let ray_surface_hit_key = function
  | Pdk.Ops.Ray_first_surface -> "first"
  | Pdk.Ops.Ray_last_surface -> "last"

let ray_combine_key = function
  | Pdk.Ops.Ray_average -> "average"
  | Pdk.Ops.Ray_median -> "median"
  | Pdk.Ops.Ray_shortest -> "shortest"
  | Pdk.Ops.Ray_longest -> "longest"

let ray ?label ?selection ?collision_group ?(method_ = Pdk.Ops.Ray_project)
    ?(direction = Pdk.Ops.Ray_normal) ?(direction_mode = Pdk.Ops.Ray_forward)
    ?(surface_hit = Pdk.Ops.Ray_first_surface) ?(samples = 1)
    ?(jitter_scale = 1.) ?(seed = 0) ?(combine = Pdk.Ops.Ray_average)
    ?(min_distance = 0.)
    ?max_distance ?(tolerance = 0.) ?(scale = 1.) ?(lift = 0.)
    ?distance_attribute ?primitive_attribute ?source_vertex_numbers_attribute
    ?source_vertex_weights_attribute ?hit_group ?normal_attribute
    ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
    ?(match_groups = false) ~collision source =
  let direction = match direction with
    | Pdk.Ops.Ray_vector value -> Pdk.Ops.Ray_vector (vec3_copy value)
    | Pdk.Ops.Ray_normal -> Pdk.Ops.Ray_normal
    | Pdk.Ops.Ray_attribute name -> Pdk.Ops.Ray_attribute name in
  Option.iter (fun selection ->
    let name = match selection with Point_group name | Vertex_group name
      | Primitive_group name | Edge_group name -> name in
    if String.trim name = "" then invalid_arg "Sop.ray: empty selection group")
    selection;
  List.iter (fun (label, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.ray: empty " ^ label)
    | None | Some _ -> ()) [
      "collision group", collision_group;
      "distance attribute", distance_attribute;
      "primitive attribute", primitive_attribute;
      "source vertex numbers attribute", source_vertex_numbers_attribute;
      "source vertex weights attribute", source_vertex_weights_attribute;
      "hit group", hit_group; "normal attribute", normal_attribute ];
  (match direction with
   | Pdk.Ops.Ray_attribute name when String.trim name = "" ->
       invalid_arg "Sop.ray: empty direction attribute"
   | Pdk.Ops.Ray_vector _ | Pdk.Ops.Ray_normal | Pdk.Ops.Ray_attribute _ -> ());
  List.iter (fun (label, pattern) -> Option.iter (fun pattern ->
    match Pdk.Attribute_pattern.compile pattern with
    | Ok _ -> ()
    | Error message -> invalid_arg ("Sop.ray: invalid " ^ label ^ ": " ^ message))
    pattern) ["point pattern", point_pattern; "vertex pattern", vertex_pattern;
      "primitive pattern", primitive_pattern; "detail pattern", detail_pattern];
  let option_float = function None -> "none" | Some value -> float_key value in
  let parameters = String.concat ";" [
    "selection=" ^ (match selection with None -> "all"
      | Some selection -> element_group_key selection);
    "collision_group=" ^ option_string_key collision_group;
    "method=" ^ ray_method_key method_;
    "direction=" ^ ray_direction_key direction;
    "direction_mode=" ^ ray_direction_mode_key direction_mode;
    "surface_hit=" ^ ray_surface_hit_key surface_hit;
    "samples=" ^ string_of_int samples;
    "jitter_scale=" ^ float_key jitter_scale;
    "seed=" ^ string_of_int seed;
    "combine=" ^ ray_combine_key combine;
    "min_distance=" ^ float_key min_distance;
    "max_distance=" ^ option_float max_distance;
    "tolerance=" ^ float_key tolerance; "scale=" ^ float_key scale;
    "lift=" ^ float_key lift;
    "distance_attribute=" ^ option_string_key distance_attribute;
    "primitive_attribute=" ^ option_string_key primitive_attribute;
    "source_vertex_numbers=" ^ option_string_key source_vertex_numbers_attribute;
    "source_vertex_weights=" ^ option_string_key source_vertex_weights_attribute;
    "hit_group=" ^ option_string_key hit_group;
    "normal_attribute=" ^ option_string_key normal_attribute;
    "point_pattern=" ^ option_string_key point_pattern;
    "vertex_pattern=" ^ option_string_key vertex_pattern;
    "primitive_pattern=" ^ option_string_key primitive_pattern;
    "detail_pattern=" ^ option_string_key detail_pattern;
    "match_groups=" ^ string_of_bool match_groups] in
  Node.Private.make ?label ~operation:"ray" ~version:2 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|source; collision|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"ray" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          let collision_primitives = match collision_group with
            | None -> Ok None
            | Some name ->
                (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name
                    inputs.(1) with
                 | Some group -> Ok (Some group)
                 | None -> Error (Diagnostic.error ~code:"missing_collision_group"
                     (Printf.sprintf "ray could not find collision primitive group %S"
                       name))) in
          (match collision_primitives with
           | Error error -> Error error
           | Ok collision_primitives ->
               match Pdk.Ops.ray ~cancel:(Context.cancel_token context)
                   ~grain:(Context.grain context) ?selection ?collision_primitives
                   ~method_ ~direction ~direction_mode ~surface_hit ~samples
                   ~jitter_scale ~seed ~combine ~min_distance
                   ?max_distance ~tolerance ~scale ~lift ?distance_attribute
                   ?primitive_attribute ?source_vertex_numbers_attribute
                   ?source_vertex_weights_attribute ?hit_group ?normal_attribute
                   ?point_pattern ?vertex_pattern ?primitive_pattern
                   ?detail_pattern ~match_groups ~source:inputs.(0)
                   ~collision:inputs.(1) () with
               | Ok geometry -> cooked geometry
               | Error error -> structured_pdk_error error))

let peak ?label ?selection ?direction_attribute ?(normalize_direction = true)
    ?mask_attribute ~distance ?(recompute_normals = false) input =
  Option.iter (fun selection ->
    let name = match selection with Point_group name | Vertex_group name
      | Primitive_group name | Edge_group name -> name in
    if String.trim name = "" then invalid_arg "Sop.peak: empty group name") selection;
  List.iter (fun (parameter, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.peak: empty " ^ parameter)
    | None | Some _ -> ())
    ["direction attribute name", direction_attribute;
     "mask attribute name", mask_attribute];
  let parameters = String.concat ";" [
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "direction=" ^ option_string_key direction_attribute;
      "normalize=" ^ string_of_bool normalize_direction;
      "mask=" ^ option_string_key mask_attribute;
      "distance=" ^ float_key distance;
      "recompute_normals=" ^ string_of_bool recompute_normals] in
  Node.Private.make ?label ~operation:"peak" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"peak" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.peak ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ?direction_attribute
              ~normalize_direction ?mask_attribute ~distance ~recompute_normals
              inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let bend ?label ?selection ?mask_attribute ?(origin = Vec3.zero)
    ?(direction = Vec3.unit_z) ?(up = Vec3.unit_y) ~length
    ?(bend_angle = 0.) ?(twist_angle = 0.) ?(limit = true)
    ?(both_directions = false) ?(continuous_twist = true) ?capture_attribute
    ?(recompute_normals = false) input =
  Option.iter (fun selection ->
    let name = match selection with Point_group name | Vertex_group name
      | Primitive_group name | Edge_group name -> name in
    if String.trim name = "" then invalid_arg "Sop.bend: empty group name") selection;
  List.iter (fun (parameter, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.bend: empty " ^ parameter)
    | None | Some _ -> ())
    ["mask attribute name", mask_attribute;
     "capture attribute name", capture_attribute];
  let origin = vec3_copy origin and direction = vec3_copy direction
  and up = vec3_copy up in
  let parameters = String.concat ";" [
      "selection=" ^ (match selection with None -> "all"
        | Some selection -> element_group_key selection);
      "mask=" ^ option_string_key mask_attribute;
      "origin=" ^ vec3_key origin;
      "direction=" ^ vec3_key direction;
      "up=" ^ vec3_key up;
      "length=" ^ float_key length;
      "bend_angle=" ^ float_key bend_angle;
      "twist_angle=" ^ float_key twist_angle;
      "limit=" ^ string_of_bool limit;
      "both_directions=" ^ string_of_bool both_directions;
      "continuous_twist=" ^ string_of_bool continuous_twist;
      "capture_attribute=" ^ option_string_key capture_attribute;
      "recompute_normals=" ^ string_of_bool recompute_normals] in
  Node.Private.make ?label ~operation:"bend" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input|] (fun ~node_id:_ context inputs ->
      match resolve_element_group ~operation:"bend" selection inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Ops.bend ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ?mask_attribute ~origin
              ~direction ~up ~length ~bend_angle ~twist_angle ~limit
              ~both_directions ~continuous_twist ?capture_attribute
              ~recompute_normals inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let mountain ?label ?group ?seed ?direction_attribute
    ?(normalize_direction = true) ?mask_attribute ~height
    ?(frequency = Vec3.create 1. 1. 1.) ?(offset = Vec3.zero) ?(octaves = 4)
    ?(lacunarity = 2.) ?(roughness = 0.5) ?height_attribute
    ?(recompute_normals = false) input =
  List.iter (fun (parameter, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.mountain: empty " ^ parameter)
    | None | Some _ -> ())
    ["point group name", group; "direction attribute name", direction_attribute;
     "mask attribute name", mask_attribute;
     "height attribute name", height_attribute];
  let frequency = vec3_copy frequency and offset = vec3_copy offset in
  let dependencies = match seed with
    | Some _ -> Context.Dependencies.static
    | None -> Context.Dependencies.one Context.Dependencies.Seed in
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "seed=" ^ (match seed with None -> "context" | Some seed -> string_of_int seed);
      "direction=" ^ option_string_key direction_attribute;
      "normalize=" ^ string_of_bool normalize_direction;
      "mask=" ^ option_string_key mask_attribute;
      "height=" ^ float_key height;
      "frequency=" ^ vec3_key frequency;
      "offset=" ^ vec3_key offset;
      "octaves=" ^ string_of_int octaves;
      "lacunarity=" ^ float_key lacunarity;
      "roughness=" ^ float_key roughness;
      "height_attribute=" ^ option_string_key height_attribute;
      "recompute_normals=" ^ string_of_bool recompute_normals] in
  let stable_identity = Option.map (fun label ->
    stable_string_hash ("mountain:" ^ label)) label in
  Node.Private.make ?label ~operation:"mountain" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
    (fun ~node_id context inputs ->
      let selection = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name inputs.(0) with
             | Some group -> Ok (Some (Pdk.Ops.Selected_points group))
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "mountain could not find point group %S" name))) in
      match selection with
      | Error error -> Error error
      | Ok selection ->
          let identity = Option.value ~default:(Int64.of_int node_id)
              stable_identity in
          let seed = Option.value ~default:(mixed_seed context identity) seed in
          match Pdk.Ops.mountain ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ?direction_attribute
              ~normalize_direction ?mask_attribute ~seed ~height ~frequency
              ~offset ~octaves ~lacunarity ~roughness ?height_attribute
              ~recompute_normals inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let point_generate ?label ?group ?(keep_input = false) ?seed ?generated_group
    ?(source_point_attribute = "sourcepoint")
    ?(source_index_attribute = "sourceindex")
    ?(copy_point_attributes = "*") ?(copy_detail_attributes = "") ~mode input =
  let dependencies = match seed with
    | Some _ -> Context.Dependencies.static
    | None -> Context.Dependencies.one Context.Dependencies.Seed in
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "keep_input=" ^ string_of_bool keep_input;
      "seed=" ^ (match seed with None -> "context"
        | Some seed -> string_of_int seed);
      "generated_group=" ^ option_string_key generated_group;
      "source_point=" ^ String.escaped source_point_attribute;
      "source_index=" ^ String.escaped source_index_attribute;
      "copy_point=" ^ String.escaped copy_point_attributes;
      "copy_detail=" ^ String.escaped copy_detail_attributes;
      "mode=" ^ point_generate_mode_key mode] in
  let stable_identity = Option.map (fun label ->
    stable_string_hash ("point_generate:" ^ label)) label in
  Node.Private.make ?label ~operation:"point_generate" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
    (fun ~node_id context inputs ->
      let geometry = inputs.(0) in
      let points = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name geometry with
             | Some value -> Ok (Some value)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "point_generate could not find point group %S" name))) in
      match points with
      | Error error -> Error error
      | Ok points ->
          let identity = Option.value ~default:(Int64.of_int node_id)
              stable_identity in
          let seed = Option.value ~default:(mixed_seed context identity) seed in
          match Pdk.Ops.point_generate ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?points ~keep_input ~seed:(Rand.seed seed)
              ?generated_group ~source_point_attribute ~source_index_attribute
              ~copy_point_attributes ~copy_detail_attributes ~mode geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let point_replicate_shape_key = function
  | Pdk.Ops.Replicate_point -> "point"
  | Pdk.Ops.Replicate_box -> "box"
  | Pdk.Ops.Replicate_sphere -> "sphere"
  | Pdk.Ops.Replicate_disk -> "disk"
  | Pdk.Ops.Replicate_line -> "line"
  | Pdk.Ops.Replicate_custom -> "custom"

let point_replicate_velocity_key = function
  | Pdk.Ops.Replicate_no_velocity_stretch -> "none"
  | Pdk.Ops.Replicate_scaled_velocity -> "scaled"
  | Pdk.Ops.Replicate_velocity_only -> "velocity_only"

let point_replicate ?label ?group ?(keep_input = false) ?seed
    ?(id_attribute = "id") ?generated_group ?(copy_point_attributes = "*")
    ?(keep_source_attributes = false) ?(transform_attributes = "P")
    ?(source_point_attribute = "sourcepoint")
    ?(source_index_attribute = "sourceindex")
    ?(shape = Pdk.Ops.Replicate_sphere) ?custom_shape ?(center = Vec3.zero)
    ?(size = Vec3.create 1. 1. 1.) ?(orientation = Vec3.zero)
    ?(uniform_scale = 1.) ?(quasi_stratified = false)
    ?(velocity_stretch = Pdk.Ops.Replicate_no_velocity_stretch)
    ?(velocity_scale = 1.) ?(inherit_velocity = 1.) ?(radial_velocity = 0.)
    ?noise_amplitude ?(noise_frequency = Vec3.create 1. 1. 1.)
    ?(noise_offset = Vec3.zero) ?(noise_roughness = 0.5)
    ?(noise_attenuation = 1.) ?(noise_turbulence = 3) ?noise_seed
    ~points_per_point ?scale_attribute input =
  let center = vec3_copy center and size = vec3_copy size
  and orientation = vec3_copy orientation in
  let noise_amplitude = Option.map vec3_copy noise_amplitude
  and noise_frequency = vec3_copy noise_frequency
  and noise_offset = vec3_copy noise_offset in
  let dependencies = if Option.is_none seed
      || (Option.is_some noise_amplitude && Option.is_none noise_seed)
    then Context.Dependencies.one Context.Dependencies.Seed
    else Context.Dependencies.static in
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "keep_input=" ^ string_of_bool keep_input;
      "seed=" ^ (match seed with None -> "context" | Some value -> string_of_int value);
      "id=" ^ String.escaped id_attribute;
      "generated_group=" ^ option_string_key generated_group;
      "copy_point=" ^ String.escaped copy_point_attributes;
      "transform_attributes=" ^ String.escaped transform_attributes;
      "keep_source=" ^ string_of_bool keep_source_attributes;
      "source_point=" ^ String.escaped source_point_attribute;
      "source_index=" ^ String.escaped source_index_attribute;
      "shape=" ^ point_replicate_shape_key shape;
      "custom_shape=" ^ string_of_bool (Option.is_some custom_shape);
      "center=" ^ vec3_key center;
      "size=" ^ vec3_key size;
      "orientation=" ^ vec3_key orientation;
      "uniform_scale=" ^ float_key uniform_scale;
      "quasi=" ^ string_of_bool quasi_stratified;
      "velocity_stretch=" ^ point_replicate_velocity_key velocity_stretch;
      "velocity_scale=" ^ float_key velocity_scale;
      "inherit_velocity=" ^ float_key inherit_velocity;
      "radial_velocity=" ^ float_key radial_velocity;
      "noise_amplitude=" ^ (match noise_amplitude with None -> "none"
        | Some value -> vec3_key value);
      "noise_frequency=" ^ vec3_key noise_frequency;
      "noise_offset=" ^ vec3_key noise_offset;
      "noise_roughness=" ^ float_key noise_roughness;
      "noise_attenuation=" ^ float_key noise_attenuation;
      "noise_turbulence=" ^ string_of_int noise_turbulence;
      "noise_seed=" ^ (match noise_amplitude, noise_seed with
        | None, _ -> "disabled"
        | Some _, None -> "context"
        | Some _, Some value -> string_of_int value);
      "points_per_point=" ^ float_key points_per_point;
      "scale_attribute=" ^ option_string_key scale_attribute] in
  let stable_identity = Option.map (fun label ->
      stable_string_hash ("point_replicate:" ^ label)) label in
  let inputs = match custom_shape with None -> [|input|]
    | Some custom_shape -> [|input;custom_shape|] in
  Node.Private.make ?label ~operation:"point_replicate" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs
    (fun ~node_id context inputs ->
      let geometry = inputs.(0) in
      let selection = match group with
        | None -> Ok None
        | Some name -> (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point
            name geometry with
          | Some value -> Ok (Some value)
          | None -> Error (Diagnostic.error ~code:"missing_group"
              (Printf.sprintf "point_replicate could not find point group %S" name))) in
      match selection with
      | Error error -> Error error
      | Ok selection ->
          let identity = Option.value ~default:(Int64.of_int node_id)
              stable_identity in
          let seed = Option.value ~default:(mixed_seed context identity) seed in
          let noise_seed = Option.value ~default:(mixed_seed context
              (Int64.logxor identity 0x6a09e667f3bcc909L)) noise_seed in
          let custom_shape = if Array.length inputs = 2 then Some inputs.(1) else None in
          match Pdk.Ops.point_replicate ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?points:selection ~keep_input
              ~seed:(Rand.seed seed) ~id_attribute ?generated_group
              ~copy_point_attributes ~keep_source_attributes
              ~transform_attributes
              ~source_point_attribute ~source_index_attribute ~shape ?custom_shape
              ~center ~size ~orientation ~uniform_scale ~quasi_stratified
              ~velocity_stretch ~velocity_scale ~inherit_velocity ~radial_velocity
              ?noise_amplitude ~noise_frequency ~noise_offset ~noise_roughness
              ~noise_attenuation ~noise_turbulence ~noise_seed
              ~points_per_point ?scale_attribute geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let point_jitter ?label ?group ?mask_attribute ?id_attribute ?seed
    ?(scale = 1.) ?(axis_scales = Vec3.create 1. 1. 1.)
    ?(use_point_scale = false) input =
  List.iter (fun (parameter, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.point_jitter: empty " ^ parameter)
    | None | Some _ -> ())
    ["point group name", group; "mask attribute name", mask_attribute;
     "id attribute name", id_attribute];
  let axis_scales = vec3_copy axis_scales in
  let dependencies = match seed with
    | Some _ -> Context.Dependencies.static
    | None -> Context.Dependencies.one Context.Dependencies.Seed in
  let parameters = String.concat ";" [
      "group=" ^ option_string_key group;
      "mask=" ^ option_string_key mask_attribute;
      "id=" ^ option_string_key id_attribute;
      "seed=" ^ (match seed with None -> "context"
        | Some seed -> string_of_int seed);
      "scale=" ^ float_key scale;
      "axis_scales=" ^ vec3_key axis_scales;
      "use_point_scale=" ^ string_of_bool use_point_scale] in
  let stable_identity = Option.map (fun label ->
    stable_string_hash ("point_jitter:" ^ label)) label in
  Node.Private.make ?label ~operation:"point_jitter" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
    (fun ~node_id context inputs ->
      let points = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Point name inputs.(0) with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf
                    "point_jitter could not find point group %S" name))) in
      match points with
      | Error error -> Error error
      | Ok points ->
          let identity = Option.value ~default:(Int64.of_int node_id)
              stable_identity in
          let seed = Option.value ~default:(mixed_seed context identity) seed in
          match Pdk.Ops.point_jitter ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?points ?mask_attribute
              ?id_attribute ~use_point_scale ~seed:(Rand.seed seed) ~scale
              ~axis_scales inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let attribute_randomize ?label ?group ?selection ?seed ?seed_attribute
    ?fraction_attribute ?minimum ?maximum ?(direction_bias = 0.)
    ?(operation = Pdk.Attribute_ops.Random_set) ?(scale = 1.) ~owner ~name
    distribution input =
  if String.trim name = "" then
    invalid_arg "Sop.attribute_randomize: empty attribute name";
  List.iter (fun (parameter, value) -> match value with
    | Some value when String.trim value = "" ->
        invalid_arg ("Sop.attribute_randomize: empty " ^ parameter)
    | None | Some _ -> ())
    ["group name", group; "seed attribute name", seed_attribute;
     "fraction attribute name", fraction_attribute];
  Option.iter (fun selection ->
    let name = match selection with Point_group name | Vertex_group name
      | Primitive_group name | Edge_group name -> name in
    if String.trim name = "" then
      invalid_arg "Sop.attribute_randomize: empty typed selection name")
    selection;
  if group <> None && selection <> None then
    invalid_arg
      "Sop.attribute_randomize: group and typed selection are mutually exclusive";
  if owner = Pdk.Attribute.Detail && group <> None then
    invalid_arg "Sop.attribute_randomize: detail attributes do not accept a group";
  if owner = Pdk.Attribute.Detail && selection <> None then
    invalid_arg
      "Sop.attribute_randomize: detail attributes do not accept a typed selection";
  if fraction_attribute <> None && (seed <> None || seed_attribute <> None) then
    invalid_arg
      "Sop.attribute_randomize: fraction sampling does not accept seed controls";
  let dependencies = match fraction_attribute, seed with
    | Some _, _ | None, Some _ -> Context.Dependencies.static
    | None, None -> Context.Dependencies.one Context.Dependencies.Seed in
  let parameters = String.concat ";" [
      "owner=" ^ attribute_owner_key owner;
      "name=" ^ String.escaped name;
      "group=" ^ option_string_key group;
      "selection=" ^ (match selection with None -> "none"
        | Some selection -> element_group_key selection);
      "seed=" ^ (match seed with None -> "context" | Some seed -> string_of_int seed);
      "seed_attribute=" ^ option_string_key seed_attribute;
      "fraction_attribute=" ^ option_string_key fraction_attribute;
      "minimum=" ^ (match minimum with None -> "none"
        | Some value -> numeric_value_key value);
      "maximum=" ^ (match maximum with None -> "none"
        | Some value -> numeric_value_key value);
      "direction_bias=" ^ float_key direction_bias;
      "operation=" ^ random_operation_key operation;
      "scale=" ^ float_key scale;
      "distribution=" ^ random_distribution_key distribution] in
  let stable_identity = Option.map (fun label ->
    stable_string_hash ("attribute_randomize:" ^ label)) label in
  Node.Private.make ?label ~operation:"attribute_randomize" ~version:2
    ~parameters ~cook_mode:(Node.Duplicate_input 0) ~dependencies
    ~inputs:[|input|] (fun ~node_id context inputs ->
      let selected = match selection with
        | Some selection ->
            Result.map (fun selected -> None, selected)
              (resolve_element_group ~operation:"attribute_randomize"
                 (Some selection) inputs.(0))
        | None ->
            Result.map (fun selected -> selected, None)
              (resolve_attribute_group ~operation:"attribute_randomize" ~owner
                 group inputs.(0)) in
      match selected with
      | Error error -> Error error
      | Ok (selection, element_selection) ->
          let element_selection = Option.map (function
            | Pdk.Ops.Selected_points group ->
                Pdk.Attribute_ops.Random_points group
            | Pdk.Ops.Selected_vertices group ->
                Pdk.Attribute_ops.Random_vertices group
            | Pdk.Ops.Selected_primitives group ->
                Pdk.Attribute_ops.Random_primitives group
            | Pdk.Ops.Selected_edges group ->
                Pdk.Attribute_ops.Random_edges group) element_selection in
          let identity = Option.value ~default:(Int64.of_int node_id)
              stable_identity in
          let seed = Rand.seed (match fraction_attribute with
            | Some _ -> 0
            | None -> Option.value ~default:(mixed_seed context identity) seed) in
          match Pdk.Attribute_ops.randomize
              ~cancel:(Context.cancel_token context) ~grain:(Context.grain context)
              ?selection ?element_selection ?seed_attribute ?fraction_attribute
              ?minimum ?maximum ~seed ~owner ~name ~direction_bias ~operation ~scale
              distribution inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let attribute_remap ?label ?group ?into
    ?(policy = Pdk.Attribute_ops.Remap_clamp) ?(ramp = []) ~owner ~name ~input
    ~output_min ~output_max input_node =
  if String.trim name = "" then
    invalid_arg "Sop.attribute_remap: empty source attribute name";
  (match into with Some name when String.trim name = "" ->
     invalid_arg "Sop.attribute_remap: empty destination attribute name"
   | None | Some _ -> ());
  (match group with Some name when String.trim name = "" ->
     invalid_arg "Sop.attribute_remap: empty group name"
   | None | Some _ -> ());
  if owner = Pdk.Attribute.Detail && group <> None then
    invalid_arg "Sop.attribute_remap: detail attributes do not accept a group";
  let ramp_key = ramp |> List.map (fun (position, value) ->
      float_key position ^ ":" ^ float_key value) |> String.concat "," in
  let parameters = String.concat ";" [
      "owner=" ^ attribute_owner_key owner;
      "name=" ^ String.escaped name;
      "into=" ^ option_string_key into;
      "group=" ^ option_string_key group;
      "input=" ^ remap_input_key input;
      "output_min=" ^ numeric_value_key output_min;
      "output_max=" ^ numeric_value_key output_max;
      "policy=" ^ remap_policy_key policy;
      "ramp=" ^ ramp_key] in
  Node.Private.make ?label ~operation:"attribute_remap" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies:Context.Dependencies.static
    ~inputs:[|input_node|] (fun ~node_id:_ context inputs ->
      match resolve_attribute_group ~operation:"attribute_remap" ~owner group
          inputs.(0) with
      | Error error -> Error error
      | Ok selection ->
          match Pdk.Attribute_ops.remap ~cancel:(Context.cancel_token context)
              ~grain:(Context.grain context) ?selection ~owner ~name ?into ~input
              ~output_min ~output_max ~policy ~ramp inputs.(0) with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)

let noise_displace ?label ?seed ~amplitude ~frequency input =
  let dependencies = match seed with
    | Some _ -> Context.Dependencies.static
    | None -> Context.Dependencies.one Context.Dependencies.Seed
  in
  let parameters = Printf.sprintf "amplitude=%s;frequency=%s;seed=%s"
      (float_key amplitude) (float_key frequency)
      (match seed with None -> "context" | Some seed -> string_of_int seed) in
  let stable_identity = Option.map (fun label ->
    stable_string_hash ("noise_displace:" ^ label)) label in
  Node.Private.make ?label ~operation:"noise_displace" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
    (fun ~node_id context inputs ->
      let identity = Option.value ~default:(Int64.of_int node_id) stable_identity in
      let seed = Option.value ~default:(mixed_seed context identity) seed in
      match Pdk.Ops.noise_displace ~grain:(Context.grain context)
          ~cancel:(Context.cancel_token context)
          ~amplitude ~frequency ~seed inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let color_by_height ?label ~low ~high input =
  let parameters = Printf.sprintf "low=%s;high=%s"
      (color_key low) (color_key high) in
  Node.Private.make ?label ~operation:"color_by_height" ~version:1 ~parameters
    ~cook_mode:(Node.Duplicate_input 0)
    ~dependencies:Context.Dependencies.static ~inputs:[|input|]
    (fun ~node_id:_ context inputs ->
      match Pdk.Ops.color_by_height ~grain:(Context.grain context)
          ~cancel:(Context.cancel_token context)
          ~low ~high inputs.(0) with
      | Ok geometry -> cooked geometry
      | Error error -> structured_pdk_error error)

let scatter ?label ?seed ?group ?density ?point_pattern ?vertex_pattern
    ?primitive_pattern ?detail_pattern ?(match_groups = false)
    ?source_primitive_attribute ?source_vertex_numbers_attribute
    ?source_vertex_weights_attribute ~count input =
  List.iter (fun (kind, value) -> match value with
    | Some name when String.trim name = "" ->
        invalid_arg ("Sop.scatter: empty " ^ kind)
    | None | Some _ -> ())
    ["primitive group", group; "point pattern", point_pattern;
     "vertex pattern", vertex_pattern; "primitive pattern", primitive_pattern;
     "detail pattern", detail_pattern;
     "source primitive attribute", source_primitive_attribute;
     "source vertex numbers attribute", source_vertex_numbers_attribute;
     "source vertex weights attribute", source_vertex_weights_attribute];
  let dependencies = match seed with
    | Some _ -> Context.Dependencies.static
    | None -> Context.Dependencies.one Context.Dependencies.Seed in
  let density = Option.map (fun (value : Pdk.Ops.scatter_density) ->
    { Pdk.Ops.density_owner = value.density_owner;
      density_attribute = String.sub value.density_attribute 0
          (String.length value.density_attribute) }) density in
  let density_key = match density with
    | None -> "none"
    | Some density -> attribute_owner_key density.density_owner ^ ":"
        ^ String.escaped density.density_attribute in
  let parameters = String.concat ";" [
      "count=" ^ string_of_int count;
      "seed=" ^ (match seed with None -> "context"
        | Some seed -> string_of_int seed);
      "group=" ^ option_string_key group;
      "density=" ^ density_key;
      "point_pattern=" ^ option_string_key point_pattern;
      "vertex_pattern=" ^ option_string_key vertex_pattern;
      "primitive_pattern=" ^ option_string_key primitive_pattern;
      "detail_pattern=" ^ option_string_key detail_pattern;
      "match_groups=" ^ string_of_bool match_groups;
      "source_primitive_attribute="
        ^ option_string_key source_primitive_attribute;
      "source_vertex_numbers_attribute="
        ^ option_string_key source_vertex_numbers_attribute;
      "source_vertex_weights_attribute="
        ^ option_string_key source_vertex_weights_attribute] in
  let stable_identity = Option.map (fun label ->
    stable_string_hash ("scatter:" ^ label)) label in
  Node.Private.make ?label ~operation:"scatter" ~version:2 ~parameters
    ~cook_mode:(Node.Duplicate_input 0) ~dependencies ~inputs:[|input|]
    (fun ~node_id context inputs ->
      let identity = Option.value ~default:(Int64.of_int node_id) stable_identity in
      let seed = Option.value ~default:(mixed_seed context identity) seed in
      let geometry = inputs.(0) in
      let primitives = match group with
        | None -> Ok None
        | Some name ->
            (match Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry with
             | Some group -> Ok (Some group)
             | None -> Error (Diagnostic.error ~code:"missing_group"
                 (Printf.sprintf "scatter could not find primitive group %S" name))) in
      match primitives with
      | Error _ as error -> error
      | Ok primitives ->
          match Pdk.Ops.scatter_surface ~grain:(Context.grain context) ~count ~seed
              ~cancel:(Context.cancel_token context) ?primitives ?density
              ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
              ~match_groups ?source_primitive_attribute
              ?source_vertex_numbers_attribute ?source_vertex_weights_attribute
              geometry with
          | Ok geometry -> cooked geometry
          | Error error -> structured_pdk_error error)
