open Prismel
open Pdk
open Procedural

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let columns = integer_env "PRISMEL_PDK_OPS_COLUMNS" 1_000
let rows = integer_env "PRISMEL_PDK_OPS_ROWS" 1_000
let repeats = integer_env "PRISMEL_PDK_OPS_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_PDK_BENCH_GRAIN" 16_384
let uv_iterations = integer_env "PRISMEL_PDK_UV_ITERATIONS" 500
let curve_points = max 3 (integer_env "PRISMEL_PDK_CURVE_POINTS" 200_001)
let attribute_count = integer_env "PRISMEL_PDK_ATTRIBUTES" 4_096
let scatter_count = integer_env "PRISMEL_PDK_SCATTER_COUNT" 1_000_000
let box_batch = integer_env "PRISMEL_PDK_BOX_BATCH" 10_000
let platonic_batch = integer_env "PRISMEL_PDK_PLATONIC_BATCH" 100_000
let poly_fill_boxes = integer_env "PRISMEL_PDK_POLY_FILL_BOXES" 100_000
let low_color = Color.rgb 45 36 114
let high_color = Color.rgb 244 124 42
let session_only = match Sys.getenv_opt "PRISMEL_PDK_OPS_SESSION_ONLY" with
  | Some value -> List.mem (String.lowercase_ascii value) ["1"; "true"; "yes"; "on"]
  | None -> false
let benchmark_filter = Sys.getenv_opt "PRISMEL_PDK_OPS_FILTER"
let benchmark_enabled name = match benchmark_filter with
  | None -> true
  | Some prefix -> String.starts_with ~prefix name

let get_ok = function Ok value -> value | Error _ -> failwith "benchmark setup failed"
let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let mix hash value = ((hash * 65_599) lxor value) land max_int
let float_bits value = Int64.to_int (Int64.bits_of_float value)

let hash_float_array hash values =
  let hash = ref hash in
  Array.iter (fun value -> hash := mix !hash (float_bits value)) values;
  !hash

let geometry_hash geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry) in
  let hash = ref 17 in
  hash := hash_float_array !hash positions.x;
  hash := hash_float_array !hash positions.y;
  hash := hash_float_array !hash positions.z;
  Array.iter (fun value -> hash := mix !hash value) topology.vertex_points;
  Array.iter (fun value -> hash := mix !hash value) topology.primitive_offsets;
  Bytes.iter (fun value -> hash := mix !hash (Char.code value + 1))
    topology.primitive_kinds;
  List.iter (fun attribute ->
    hash := mix !hash (Hashtbl.hash
      (Attribute.owner attribute, Attribute.name attribute,
       Attribute.kind_name attribute));
    match Attribute.Private.storage attribute with
    | Attribute.Float values -> hash := hash_float_array !hash values
    | Attribute.Int values ->
        Array.iter (fun value -> hash := mix !hash value) values
    | Attribute.Float2 values ->
        let values = Packed.Float2.Private.view values in
        hash := hash_float_array !hash values.x;
        hash := hash_float_array !hash values.y
    | Attribute.Float3 values ->
        let values = Packed.Float3.Private.view values in
        hash := hash_float_array !hash values.x;
        hash := hash_float_array !hash values.y;
        hash := hash_float_array !hash values.z
    | Attribute.Float4 values ->
        let values = Packed.Float4.Private.view values in
        hash := hash_float_array !hash values.x;
        hash := hash_float_array !hash values.y;
        hash := hash_float_array !hash values.z;
        hash := hash_float_array !hash values.w
    | Attribute.Text values ->
        Array.iter (fun value -> hash := mix !hash (Hashtbl.hash value)) values
    | Attribute.Int_array values ->
        let values = Packed.Int_array.Private.view values in
        Array.iter (fun value -> hash := mix !hash value) values.offsets;
        Array.iter (fun value -> hash := mix !hash value) values.values
    | Attribute.Float_array values ->
        let values = Packed.Float_array.Private.view values in
        Array.iter (fun value -> hash := mix !hash value) values.offsets;
        hash := hash_float_array !hash values.values)
    (Geometry.attributes geometry);
  List.iter (fun group ->
    hash := mix !hash (Hashtbl.hash
      (Group.owner group, Group.name group, Group.length group));
    hash := mix !hash (if Group.is_ordered group then 1 else 0);
    Group.iter_ordered (fun index -> hash := mix !hash index) group)
    (Geometry.groups geometry);
  List.iter (fun group ->
    hash := mix !hash (Hashtbl.hash
      (Edge_group.name group, Edge_group.length group));
    Edge_group.iter (fun edge -> hash := mix !hash edge) group)
    (Geometry.edge_groups geometry);
  !hash

let geometry_output geometry =
  let cardinality = Geometry.point_count geometry + Geometry.vertex_count geometry
      + Geometry.primitive_count geometry in
  cardinality, geometry_hash geometry

let float_array_output values = Array.length values, hash_float_array 17 values

let integer_pair_arrays_output (left, right) =
  let hash = ref 17 in
  Array.iter (fun value -> hash := mix !hash value) left;
  Array.iter (fun value -> hash := mix !hash value) right;
  Array.length left + Array.length right, !hash

let attribute_metadata_output geometry =
  let attributes = Geometry.attributes geometry in
  let hash = List.fold_left (fun hash attribute ->
      mix (mix (mix hash (Hashtbl.hash (Attribute.owner attribute)))
        (Hashtbl.hash (Attribute.name attribute)))
        (Attribute.storage_id attribute)) 17 attributes in
  List.length attributes, hash

let attribute_metadata_set_output geometry =
  let owner_rank = function
    | Attribute.Point -> 0 | Attribute.Vertex -> 1
    | Attribute.Primitive -> 2 | Attribute.Detail -> 3 in
  let attributes = Geometry.attributes geometry |> List.sort (fun left right ->
      let owner = Int.compare (owner_rank (Attribute.owner left))
          (owner_rank (Attribute.owner right)) in
      if owner <> 0 then owner
      else String.compare (Attribute.name left) (Attribute.name right)) in
  let hash = List.fold_left (fun hash attribute ->
      mix (mix (mix hash (owner_rank (Attribute.owner attribute)))
        (Hashtbl.hash (Attribute.name attribute)))
        (Attribute.storage_id attribute)) 17 attributes in
  List.length attributes, hash

let mesh_output mesh =
  Mesh.vertex_count mesh + Mesh.index_count mesh,
  let view = Mesh.Private.packed_view mesh in
  let hash = ref (hash_float_array 17 view.vertices.x) in
  hash := hash_float_array !hash view.vertices.y;
  hash := hash_float_array !hash view.vertices.z;
  Array.iter (fun value -> hash := mix !hash value) view.indices;
  !hash

let topology_index_output index =
  let hash = ref 17 in
  for edge = 0 to Topology_index.edge_count index - 1 do
    let a, b = Topology_index.edge_points index edge in
    hash := mix (mix !hash a) b;
    hash := mix !hash (Topology_index.edge_incidence_count index edge)
  done;
  Topology_index.vertex_count index + Topology_index.edge_count index, !hash

let spatial_index_output index =
  let hash = ref 17 in
  for sample = 0 to 63 do
    let x = (float_of_int sample /. 63. -. 0.5) *. 20. in
    match Spatial_index.nearest index ~x ~y:0. ~z:(x *. 0.37) with
    | Ok (Some (point, distance)) ->
        hash := mix (mix !hash point) (float_bits distance)
    | Ok None -> hash := mix !hash (-1)
    | Error error -> failwith (Error.to_string error)
  done;
  Spatial_index.length index, !hash

let surface_index_output index =
  let hash = ref 17 in
  for sample = 0 to 63 do
    let x = (float_of_int sample /. 63. -. 0.5) *. 20. in
    match Surface_index.closest index ~x ~y:1. ~z:(x *. 0.37) with
    | Ok (Some hit) ->
        let a, b, c = hit.barycentric in
        hash := mix (mix (mix (mix !hash hit.primitive)
          (float_bits hit.distance)) (float_bits a))
          (mix (float_bits b) (float_bits c))
    | Ok None -> hash := mix !hash (-1)
    | Error error -> failwith (Error.to_string error)
  done;
  Surface_index.triangle_count index + Surface_index.node_count index, !hash

let measure ?(input_points = (columns + 1) * (rows + 1)) name operation consume =
  if benchmark_enabled name then begin
  let seconds = Array.make repeats 0. and allocated = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0. in
  let expected = ref None in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.quick_stat () and bytes_before = Gc.allocated_bytes ()
    and started = Unix.gettimeofday () in
    let output = Parallel.run ~domains operation in
    seconds.(repeat) <- Unix.gettimeofday () -. started;
    allocated.(repeat) <- Gc.allocated_bytes () -. bytes_before;
    let after = Gc.quick_stat () in
    promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
    major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
    let cardinality, hash = consume output in
    (match !expected with
     | None -> expected := Some (cardinality, hash)
     | Some expected when expected = (cardinality, hash) -> ()
     | Some _ -> failwith (name ^ ": nondeterministic output"))
  done;
  let cardinality, hash = Option.get !expected in
  Printf.printf "%s,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d\n%!"
    name input_points domains grain repeats
    (median seconds) (median allocated) (median promoted) (median major)
    cardinality hash
  end

let make_grid () = Ops.grid ~columns ~rows ~size:100. () |> get_ok
let make_context () =
  Context.create ~domains ~grain ~seed:42L () |> get_ok
let make_session () =
  Session.create ~max_entries:16 ~max_payload_bytes:2_000_000_000 |> get_ok

let run_grid_generator_benchmarks () =
  let point_count = (columns + 1) * (rows + 1) in
  measure ~input_points:point_count "grid_generator_triangles" (fun () ->
    Ops.grid ~grain ~columns ~rows ~size:100. () |> get_ok) geometry_output;
  measure ~input_points:point_count "grid_generator_quads" (fun () ->
    Ops.grid ~grain ~connectivity:Ops.Grid_quads
      ~columns ~rows ~size:100. () |> get_ok) geometry_output;
  measure ~input_points:point_count "grid_generator_rows_columns" (fun () ->
    Ops.grid ~grain ~connectivity:Ops.Grid_rows_and_columns
      ~columns ~rows ~size:100. () |> get_ok) geometry_output;
  measure ~input_points:point_count "grid_generator_oriented_uv" (fun () ->
    Ops.grid ~grain ~connectivity:Ops.Grid_alternating_triangles
      ~orientation:(Ops.Grid_axes {
        horizontal = Vec3.create 1. 2. 0.5;
        vertical = Vec3.create (-0.25) 0.75 2. })
      ~center:(Vec3.create 3. (-2.) 5.) ~width:80. ~height:60.
      ~rotation:0.37 ~uv_attribute:"uv" ~columns ~rows ~size:100. ()
    |> get_ok) geometry_output

let run_circle_generator_benchmarks () =
  let segments = max 3 ((columns + 1) * (rows + 1)) in
  measure ~input_points:segments "circle_generator_closed" (fun () ->
    Ops.circle ~grain ~segments ~radius:50. () |> get_ok) geometry_output;
  measure ~input_points:(segments + 1) "circle_generator_open_arc" (fun () ->
    Ops.circle ~grain ~arc:(Ops.Circle_open_arc {
        start_angle = -0.7; end_angle = 5.2 })
      ~radius_x:50. ~radius_y:25. ~segments ~radius:1. () |> get_ok)
    geometry_output;
  measure ~input_points:(segments + 2)
    "circle_generator_oriented_sliced_ellipse" (fun () ->
      Ops.circle ~grain ~arc:(Ops.Circle_sliced_arc {
          start_angle = -0.7; end_angle = 5.2 })
        ~orientation:(Ops.Circle_axes {
          horizontal = Vec3.create 1. 2. 0.5;
          vertical = Vec3.create (-0.25) 0.75 2. })
        ~reverse:true ~center:(Vec3.create 3. (-2.) 5.)
        ~radius_x:40. ~radius_y:25. ~rotation:0.37 ~uniform_scale:1.2
        ~segments ~radius:1. () |> get_ok)
    geometry_output

let run_box_generator_benchmarks () =
  measure ~input_points:(box_batch * 24) "box_generator_legacy_batch" (fun () ->
    let output = ref (Ops.box ~size:(Vec3.create 1. 2. 3.) () |> get_ok) in
    for _ = 2 to box_batch do
      output := Ops.box ~size:(Vec3.create 1. 2. 3.) () |> get_ok
    done;
    !output) geometry_output;
  measure ~input_points:523_606 "box_generator_face_triangles" (fun () ->
    Ops.box ~grain ~connectivity:Ops.Box_triangles
      ~normals:Ops.Box_point_normals
      ~x_divisions:400 ~y_divisions:300 ~z_divisions:200
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Box_yzx
      ~size:(Vec3.create 40. 25. 18.) () |> get_ok) geometry_output;
  measure ~input_points:520_002 "box_generator_welded_surface_points" (fun () ->
    Ops.box ~grain ~connectivity:Ops.Box_surface_points
      ~consolidate_points:true ~normals:Ops.Box_point_normals
      ~x_divisions:400 ~y_divisions:300 ~z_divisions:200
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Box_xzy
      ~size:(Vec3.create 40. 25. 18.) () |> get_ok) geometry_output;
  measure ~input_points:520_002 "box_generator_welded_quads_uv" (fun () ->
    Ops.box ~grain ~connectivity:Ops.Box_quads ~consolidate_points:true
      ~normals:Ops.Box_vertex_normals ~uv_attribute:"uv" ~face_groups:"face"
      ~x_divisions:400 ~y_divisions:300 ~z_divisions:200
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7) ~rotation_order:Ops.Box_zxy
      ~size:(Vec3.create 40. 25. 18.) () |> get_ok) geometry_output;
  measure ~input_points:1_030_301 "box_generator_volume_lattice" (fun () ->
    Ops.box ~grain ~connectivity:Ops.Box_lattice_points
      ~x_divisions:100 ~y_divisions:100 ~z_divisions:100
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7)
      ~size:(Vec3.create 40. 25. 18.) () |> get_ok) geometry_output

let run_uv_sphere_generator_benchmarks () =
  measure ~input_points:1_000_002 "uv_sphere_generator_legacy_triangles"
    (fun () ->
      Ops.uv_sphere ~grain ~segments:2_000 ~rings:501 ~radius:25. ()
      |> get_ok)
    geometry_output;
  measure ~input_points:502_000 "uv_sphere_generator_alternating_ellipsoid"
    (fun () ->
      Ops.uv_sphere ~grain ~connectivity:Ops.Sphere_alternating_triangles
        ~unique_points_per_pole:true ~normals:Ops.Sphere_vertex_normals
        ~orientation:(Ops.Sphere_axis (Vec3.create 1. 2. 3.))
        ~center:(Vec3.create 3. (-2.) 5.)
        ~rotation:(Vec3.create 0.3 0.5 0.7)
        ~rotation_order:Ops.Sphere_yzx ~radius_x:40. ~radius_y:25.
        ~radius_z:18. ~uv_attribute:"uv" ~segments:1_000 ~rings:501
        ~radius:1. () |> get_ok)
    geometry_output;
  measure ~input_points:500_002 "uv_sphere_generator_logical_quads"
    (fun () ->
      Ops.uv_sphere ~grain ~connectivity:Ops.Sphere_quads
        ~triangular_poles:false ~uv_attribute:"uv" ~segments:1_000 ~rings:501
        ~radius:25. () |> get_ok)
    geometry_output;
  measure ~input_points:1_000_002 "uv_sphere_generator_rows_columns"
    (fun () ->
      Ops.uv_sphere ~grain ~connectivity:Ops.Sphere_rows_and_columns
        ~normals:Ops.Sphere_vertex_normals ~uv_attribute:"uv"
        ~segments:2_000 ~rings:501 ~radius:25. () |> get_ok)
    geometry_output;
  measure ~input_points:1_004_000 "uv_sphere_generator_unique_points"
    (fun () ->
      Ops.uv_sphere ~grain ~connectivity:Ops.Sphere_points
        ~unique_points_per_pole:true ~uv_attribute:"uv"
        ~segments:2_000 ~rings:501 ~radius:25. () |> get_ok)
    geometry_output

let reference_torus ~rows ~columns ~major_radius ~minor_radius =
  let point_count = rows * columns in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        let row = point / columns and column = point mod columns in
        let u = 2. *. Float.pi *. float_of_int row /. float_of_int rows
        and v = 2. *. Float.pi *. float_of_int column /. float_of_int columns in
        (major_radius +. (minor_radius *. cos v)) *. cos u))
      ~y:(Array.init point_count (fun point ->
        let column = point mod columns in
        let v = 2. *. Float.pi *. float_of_int column /. float_of_int columns in
        minor_radius *. sin v))
      ~z:(Array.init point_count (fun point ->
        let row = point / columns and column = point mod columns in
        let u = 2. *. Float.pi *. float_of_int row /. float_of_int rows
        and v = 2. *. Float.pi *. float_of_int column /. float_of_int columns in
        (major_radius +. (minor_radius *. cos v)) *. sin u)) in
  let normals = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        let row = point / columns and column = point mod columns in
        let u = 2. *. Float.pi *. float_of_int row /. float_of_int rows
        and v = 2. *. Float.pi *. float_of_int column /. float_of_int columns in
        cos v *. cos u))
      ~y:(Array.init point_count (fun point ->
        let column = point mod columns in
        let v = 2. *. Float.pi *. float_of_int column /. float_of_int columns in
        sin v))
      ~z:(Array.init point_count (fun point ->
        let row = point / columns and column = point mod columns in
        let u = 2. *. Float.pi *. float_of_int row /. float_of_int rows
        and v = 2. *. Float.pi *. float_of_int column /. float_of_int columns in
        cos v *. sin u)) in
  let primitive_count = 2 * rows * columns in
  let vertex_points = Array.init (primitive_count * 3) (fun vertex ->
    let triangle = vertex / 3 and corner = vertex mod 3 in
    let cell = triangle / 2 and half = triangle land 1 in
    let row = cell / columns and column = cell mod columns in
    let next_row = if row + 1 = rows then 0 else row + 1
    and next_column = if column + 1 = columns then 0 else column + 1 in
    let a = (row * columns) + column
    and b = (next_row * columns) + column
    and c = (next_row * columns) + next_column
    and d = (row * columns) + next_column in
    if half = 0 then (match corner with 0 -> a | 1 -> d | _ -> c)
    else match corner with 0 -> a | 1 -> c | _ -> b) in
  let topology = Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets:(Array.init (primitive_count + 1)
        (fun primitive -> primitive * 3)) |> get_ok in
  let normal = Attribute.create_key_owned
      (Attribute.normal ~owner:Attribute.Point) normals |> get_ok in
  Geometry.create ~positions ~topology ~attributes:[normal] () |> get_ok

let run_torus_reference_benchmark () =
  measure ~input_points:1_000_000 "torus_generator_reference_triangles"
    (fun () -> reference_torus ~rows:1_000 ~columns:1_000
      ~major_radius:25. ~minor_radius:8.) geometry_output

let run_torus_generator_benchmarks () =
  measure ~input_points:1_000_000 "torus_generator_triangles" (fun () ->
    Ops.torus ~grain ~rows:1_000 ~columns:1_000
      ~major_radius:25. ~minor_radius:8. () |> get_ok) geometry_output;
  measure ~input_points:500_000 "torus_generator_quads_uv" (fun () ->
    Ops.torus ~grain ~connectivity:Ops.Torus_quads
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~orientation:(Ops.Torus_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7)
      ~rotation_order:Ops.Torus_yzx ~rows:1_000 ~columns:500
      ~major_radius:25. ~minor_radius:8. () |> get_ok) geometry_output;
  measure ~input_points:500_000 "torus_generator_partial_caps" (fun () ->
    Ops.torus ~grain ~connectivity:Ops.Torus_alternating_triangles
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~u_start:(-0.7) ~u_end:4.8 ~v_start:(-1.2) ~v_end:2.1
      ~u_wrap:false ~v_wrap:false ~u_end_caps:true ~v_end_cap:true
      ~rows:1_000 ~columns:500 ~major_radius:25. ~minor_radius:8. ()
    |> get_ok) geometry_output;
  measure ~input_points:1_000_000 "torus_generator_rows_columns" (fun () ->
    Ops.torus ~grain ~connectivity:Ops.Torus_rows_and_columns
      ~normals:Ops.Torus_vertex_normals ~uv_attribute:"uv"
      ~rows:1_000 ~columns:1_000 ~major_radius:25. ~minor_radius:8. ()
    |> get_ok) geometry_output;
  measure ~input_points:1_000_000 "torus_generator_points" (fun () ->
    Ops.torus ~grain ~connectivity:Ops.Torus_points ~uv_attribute:"uv"
      ~rows:1_000 ~columns:1_000 ~major_radius:25. ~minor_radius:8. ()
    |> get_ok) geometry_output

let run_tube_reference_benchmark () =
  measure ~input_points:1_000_000 "tube_generator_reference_sweep" (fun () ->
    Ops.line ~grain ~kind:Ops.Line_curve ~points:1_000
      ~origin:(Vec3.create 0. (-25.) 0.) ~direction:Vec3.unit_y ~length:50. ()
    |> get_ok
    |> Ops.sweep_circle ~grain ~sides:1_000 ~radius:8.
    |> get_ok) geometry_output

let run_tube_generator_benchmarks () =
  measure ~input_points:1_000_000 "tube_generator_open_quads" (fun () ->
    Ops.tube ~grain ~connectivity:Ops.Tube_quads ~uv_attribute:"uv"
      ~rows:1_000 ~columns:1_000 ~top_radius:8. ~bottom_radius:8. ~height:50. ()
    |> get_ok) geometry_output;
  measure ~input_points:500_000 "tube_generator_capped_frustum" (fun () ->
    Ops.tube ~grain ~connectivity:Ops.Tube_quads ~end_caps:true
      ~consolidate_cap_points:true ~normals:Ops.Tube_vertex_normals
      ~orientation:(Ops.Tube_axis (Vec3.create 1. 2. 3.))
      ~center:(Vec3.create 3. (-2.) 5.)
      ~rotation:(Vec3.create 0.3 0.5 0.7)
      ~rotation_order:Ops.Tube_yzx ~uv_attribute:"uv" ~cap_group:"caps"
      ~rows:1_000 ~columns:500 ~top_radius:5. ~bottom_radius:8. ~height:50. ()
    |> get_ok) geometry_output;
  measure ~input_points:499_501 "tube_generator_capped_cone" (fun () ->
    Ops.tube ~grain ~connectivity:Ops.Tube_alternating_triangles ~end_caps:true
      ~consolidate_cap_points:false ~normals:Ops.Tube_vertex_normals
      ~uv_attribute:"uv" ~cap_group:"caps" ~rows:1_000 ~columns:500
      ~top_radius:0. ~bottom_radius:8. ~height:50. () |> get_ok) geometry_output;
  measure ~input_points:1_000_000 "tube_generator_rows_columns" (fun () ->
    Ops.tube ~grain ~connectivity:Ops.Tube_rows_and_columns
      ~normals:Ops.Tube_vertex_normals ~uv_attribute:"uv"
      ~rows:1_000 ~columns:1_000 ~top_radius:5. ~bottom_radius:8. ~height:50. ()
    |> get_ok) geometry_output;
  measure ~input_points:1_000_000 "tube_generator_points" (fun () ->
    Ops.tube ~grain ~connectivity:Ops.Tube_points ~uv_attribute:"uv"
      ~rows:1_000 ~columns:1_000 ~top_radius:5. ~bottom_radius:8. ~height:50. ()
    |> get_ok) geometry_output

let reference_platonic_icosahedron () =
  let phi = (1. +. sqrt 5.) /. 2. and radius = 3. in
  let source = [|
    -1., phi, 0.; 1., phi, 0.; -1., -.phi, 0.; 1., -.phi, 0.;
    0., -1., phi; 0., 1., phi; 0., -1., -.phi; 0., 1., -.phi;
    phi, 0., -1.; phi, 0., 1.; -.phi, 0., -1.; -.phi, 0., 1.;
  |] in
  let positions = Array.map (fun (x, y, z) ->
      let scale = radius /. sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
      x *. scale, y *. scale, z *. scale) source
    |> Ops.points |> Geometry.positions in
  let faces = [|
    [|0;11;5|]; [|0;5;1|]; [|0;1;7|]; [|0;7;10|]; [|0;10;11|];
    [|1;5;9|]; [|5;11;4|]; [|11;10;2|]; [|10;7;6|]; [|7;1;8|];
    [|3;9;4|]; [|3;4;2|]; [|3;2;6|]; [|3;6;8|]; [|3;8;9|];
    [|4;9;5|]; [|2;4;11|]; [|6;2;10|]; [|8;6;7|]; [|9;8;1|];
  |] in
  let topology = Topology.Builder.create ~point_count:12
      ~vertex_capacity:60 ~primitive_capacity:20 () in
  Array.iter (Topology.Builder.add_polygon topology) faces;
  Geometry.create ~positions ~topology:(Topology.Builder.freeze topology) ()
  |> get_ok

let run_platonic_reference_benchmark () =
  measure ~input_points:(platonic_batch * 12)
    "platonic_generator_reference_icosahedron_batch" (fun () ->
      let output = ref (reference_platonic_icosahedron ()) in
      for _ = 2 to platonic_batch do
        output := reference_platonic_icosahedron ()
      done;
      !output) geometry_output

let run_platonic_generator_benchmarks () =
  measure ~input_points:(platonic_batch * 12)
    "platonic_generator_icosahedron_batch" (fun () ->
      let make () = Ops.platonic ~kind:Ops.Platonic_icosahedron
          ~normals:Ops.Platonic_no_normals ~radius:3. () |> get_ok in
      let output = ref (make ()) in
      for _ = 2 to platonic_batch do output := make () done;
      !output) geometry_output;
  let soccer_batch = max 1 (platonic_batch / 5) in
  measure ~input_points:(soccer_batch * 60)
    "platonic_generator_soccer_vertex_normals_batch" (fun () ->
      let make () = Ops.platonic ~kind:Ops.Platonic_soccer_ball
          ~normals:Ops.Platonic_vertex_normals
          ~orientation:(Ops.Platonic_axis (Vec3.create 1. 2. 3.))
          ~rotation:(Vec3.create 0.3 0.5 0.7)
          ~rotation_order:Ops.Platonic_yzx ~face_groups:"face" ~radius:3. ()
        |> get_ok in
      let output = ref (make ()) in
      for _ = 2 to soccer_batch do output := make () done;
      !output) geometry_output

let reference_spiral ~divisions ~turns ~height ~start_radius ~end_radius =
  let points = Array.init (divisions + 1) (fun point ->
    let t = float_of_int point /. float_of_int divisions in
    let angle = turns *. 2. *. Float.pi *. t
    and radius = start_radius +. ((end_radius -. start_radius) *. t) in
    radius *. cos angle, height *. t, radius *. sin angle) in
  Ops.polyline points |> get_ok

let run_spiral_reference_benchmark () =
  measure ~input_points:1_000_001 "spiral_generator_reference_polyline"
    (fun () -> reference_spiral ~divisions:1_000_000 ~turns:250. ~height:50.
      ~start_radius:2. ~end_radius:30.) geometry_output

let run_spiral_generator_benchmarks () =
  measure ~input_points:1_000_001 "spiral_generator_uniform_angle" (fun () ->
    Ops.spiral ~grain ~extent:(Ops.Spiral_turns { turns = 250.; height = 50. })
      ~radius:(Ops.Spiral_archimedean_end {
        start_radius = 2.; end_radius = 30. })
      ~divisions:(Ops.Spiral_divisions_per_curve 1_000_000) ()
    |> get_ok) geometry_output;
  measure ~input_points:1_000_004 "spiral_generator_equal_arc" (fun () ->
    Ops.spiral ~grain
      ~extent:(Ops.Spiral_height_pitch { height = 50.; pitch = 0.2 })
      ~radius:(Ops.Spiral_logarithmic_end {
        start_radius = 0.2; end_radius = 30. })
      ~height_ramp:[0., 0.8; 0.4, 1.2; 0.7, 0.6; 1., 1.]
      ~radius_ramp:[0., 1.; 0.35, 0.7; 0.8, 1.25; 1., 1.]
      ~uniform_angle:false ~spiral_count:4
      ~divisions:(Ops.Spiral_divisions_per_curve 250_000) ()
    |> get_ok) geometry_output;
  measure ~input_points:1_000_004 "spiral_generator_equal_arc_frames" (fun () ->
    Ops.spiral ~grain
      ~extent:(Ops.Spiral_height_pitch { height = 50.; pitch = 0.2 })
      ~radius:(Ops.Spiral_logarithmic_end {
        start_radius = 0.2; end_radius = 30. })
      ~height_ramp:[0., 0.8; 0.4, 1.2; 0.7, 0.6; 1., 1.]
      ~radius_ramp:[0., 1.; 0.35, 0.7; 0.8, 1.25; 1., 1.]
      ~uniform_angle:false ~spiral_count:4
      ~divisions:(Ops.Spiral_divisions_per_curve 250_000)
      ~orientation:(Ops.Spiral_axis (Vec3.create 1. 2. 3.))
      ~rotation:(Vec3.create 0.3 0.5 0.7)
      ~angle_attribute:"angle" ~x_axis_attribute:"xaxis"
      ~y_axis_attribute:"yaxis" ~tangent_attribute:"tangent"
      ~orient_attribute:"orient" ~distance_attribute:"distance" ()
    |> get_ok) geometry_output

let run_polywire_benchmarks () =
  let source_points = 100_001 in
  let source = Array.init source_points (fun point ->
      let t = float_of_int point *. 0.0005 in
      t, sin (t *. 0.19) *. 2., cos (t *. 0.13) *. 1.5)
    |> Ops.polyline |> get_ok in
  measure ~input_points:source_points "polywire_long_spine" (fun () ->
    Ops.sweep_circle ~grain ~sides:12 ~radius:0.08 source |> get_ok)
    geometry_output;
  let add name storage geometry = Attribute.create_owned
      ~owner:Attribute.Point ~name storage |> get_ok
      |> fun attribute -> Geometry.with_attribute attribute geometry |> get_ok in
  let controlled = source
      |> add "wire_scale" (Attribute.Float (Array.init source_points
           (fun point -> 0.8 +. (0.2 *. sin (float_of_int point *. 0.0007)))))
      |> add "wire_seam" (Attribute.Int (Array.init source_points
           (fun point -> (point / 997) - 50)))
      |> add "wire_v" (Attribute.Float (Array.init source_points
           (fun point -> float_of_int point *. 0.0005)))
      |> add "wire_up" (Attribute.Float3
           (Packed.Float3.Private.of_owned_exn ~x:(Array.make source_points 0.)
             ~y:(Array.make source_points 1.) ~z:(Array.init source_points
               (fun point -> 0.15 *. cos (float_of_int point *. 0.0009))))) in
  measure ~input_points:source_points "polywire_long_spine_controls" (fun () ->
    Ops.sweep_circle ~grain ~sides:12 ~scale_attribute:"wire_scale"
      ~seam_offset:(-3) ~seam_attribute:"wire_seam" ~v_attribute:"wire_v"
      ~up_attribute:"wire_up" ~caps:true ~cap_group:"caps" ~radius:0.08
      controlled |> get_ok) geometry_output;
  let variable_points = 25_001 in
  let variable = Array.init variable_points (fun point ->
      let t = float_of_int point *. 0.0015 in
      t, sin (t *. 0.23) *. 1.6, cos (t *. 0.17) *. 1.2)
    |> Ops.polyline |> get_ok
    |> add "wire_divisions" (Attribute.Int (Array.init variable_points
         (fun point -> 6 + ((point / 127) mod 9))))
    |> add "wire_segments" (Attribute.Int (Array.init variable_points
         (fun point -> 1 + ((point / 251) mod 3))))
    |> add "wire_scale" (Attribute.Float (Array.init variable_points
         (fun point -> 0.75 +. (0.25 *. sin (float_of_int point *. 0.0021))))) in
  measure ~input_points:variable_points
    "polywire_variable_divisions_segments" (fun () ->
      Ops.sweep_circle ~grain ~sides:12 ~divisions_attribute:"wire_divisions"
        ~segments_attribute:"wire_segments" ~scale_attribute:"wire_scale"
        ~caps:true ~cap_group:"caps" ~radius:0.08 variable |> get_ok)
    geometry_output;
  measure ~input_points:variable_points
    "polywire_variable_segment_uv_controls" (fun () ->
      Ops.sweep_circle ~grain ~sides:12 ~divisions_attribute:"wire_divisions"
        ~segments_attribute:"wire_segments" ~segment_scales:(0.18,0.82)
        ~u_range:(-0.5,1.5) ~v_range:(2.,7.)
        ~scale_attribute:"wire_scale" ~caps:true ~cap_group:"caps"
        ~radius:0.08 variable |> get_ok) geometry_output
  ;
  let segment_seam = Attribute.create_owned ~owner:Attribute.Vertex
      ~name:"segment_seam" (Attribute.Int (Array.init variable_points
        (fun point -> (point / 193) - 70))) |> get_ok in
  let variable_segment_seam = Geometry.with_attribute segment_seam variable
      |> get_ok in
  measure ~input_points:variable_points
    "polywire_variable_segment_seam" (fun () ->
      Ops.sweep_circle ~grain ~sides:12 ~divisions_attribute:"wire_divisions"
        ~segments_attribute:"wire_segments" ~scale_attribute:"wire_scale"
        ~segment_seam_attribute:"segment_seam" ~caps:true ~cap_group:"caps"
        ~radius:0.08 variable_segment_seam |> get_ok) geometry_output;
  let sharp = Array.init variable_points (fun point ->
      let p = float_of_int point in
      p *. 0.04, (if point land 1 = 0 then 0. else 0.035),
      0.08 *. sin (p *. 0.007))
    |> Ops.polyline |> get_ok
    |> add "joint_limit" (Attribute.Float (Array.init variable_points
         (fun point -> 1.15 +. (0.35 *. float_of_int (point mod 17) /. 16.)))) in
  measure ~input_points:variable_points
    "polywire_sharp_joints_baseline" (fun () ->
      Ops.sweep_circle ~grain ~sides:12 ~segments:2 ~radius:0.025 sharp
      |> get_ok) geometry_output;
  measure ~input_points:variable_points
    "polywire_sharp_joints_buckling" (fun () ->
      Ops.sweep_circle ~grain ~sides:12 ~segments:2
        ~prevent_joint_buckling:true
        ~maximum_joint_scale_attribute:"joint_limit" ~radius:0.025 sharp
      |> get_ok) geometry_output;
  let smooth_runs = sharp
      |> add "wire_smooth" (Attribute.Float (Array.init variable_points
           (fun point -> if point > 0 && point + 1 < variable_points
               && point mod 257 = 0 then 0. else 1.))) in
  measure ~input_points:variable_points
    "polywire_smooth_runs" (fun () ->
      Ops.sweep_circle ~grain ~sides:12 ~segments:2
        ~smooth_attribute:"wire_smooth" ~radius:0.025 smooth_runs |> get_ok)
    geometry_output

let run_sweep_general_benchmarks () =
  let backbone_points = 20_001 and profile_points = 32 in
  let backbone_values = Array.init backbone_points (fun point ->
      let t = float_of_int point *. 0.001 in
      0.4 *. sin (t *. 0.71), 0.3 *. cos (t *. 0.43), t) in
  let profile_values = Array.init profile_points (fun point ->
      let angle = 2. *. Float.pi *. float_of_int point
          /. float_of_int profile_points in
      (0.08 +. (0.012 *. cos (5. *. angle))) *. cos angle,
      (0.08 +. (0.012 *. cos (5. *. angle))) *. sin angle, 0.) in
  let backbone = Ops.polyline backbone_values |> get_ok
  and profile = Ops.polyline ~closed:true profile_values |> get_ok in
  measure ~input_points:(backbone_points + profile_points)
    "sweep_general_profile_triangles" (fun () ->
      Ops.sweep ~grain ~connectivity:Ops.Grid_alternating_triangles
        ~twist:3.7 ~backbone ~cross_section:profile () |> get_ok)
    geometry_output;
  let add owner name storage geometry = Attribute.create_owned ~owner ~name storage
      |> get_ok |> fun attribute -> Geometry.with_attribute attribute geometry |> get_ok in
  let payload_backbone = backbone
      |> add Attribute.Point "weight" (Attribute.Float
           (Array.init backbone_points (fun point ->
             0.7 +. (0.3 *. sin (float_of_int point *. 0.013)))))
      |> add Attribute.Vertex "curve_u" (Attribute.Float
           (Array.init backbone_points (fun point ->
             float_of_int point /. float_of_int (backbone_points - 1))))
      |> fun geometry -> Geometry.with_group
           (Group.init ~owner:Group.Point ~name:"alternating" backbone_points
              (fun point -> point land 1 = 0)) geometry |> get_ok
      |> Ops.group_edges ~grain ~name:"spine_edges" |> get_ok in
  let payload_profile = profile
      |> add Attribute.Point "profile_id"
           (Attribute.Int (Array.init profile_points Fun.id))
      |> add Attribute.Vertex "profile_u" (Attribute.Float
           (Array.init profile_points (fun point ->
             float_of_int point /. float_of_int profile_points)))
      |> fun geometry -> Geometry.with_group
           (Group.init ~owner:Group.Point ~name:"upper" profile_points
              (fun point -> let _, y, _ = profile_values.(point) in y >= 0.))
           geometry |> get_ok
      |> Ops.group_edges ~grain ~name:"profile_edges" |> get_ok in
  measure ~input_points:(backbone_points + profile_points)
    "sweep_general_profile_payload" (fun () ->
      Ops.sweep ~grain ~caps:true ~cap_group:"caps" ~twist:3.7
        ~backbone:payload_backbone ~cross_section:payload_profile () |> get_ok)
    geometry_output

let run_revolve_benchmarks () =
  let profile_points = 10_001 in
  let values = Array.init profile_points (fun point ->
      let u = float_of_int point /. float_of_int (profile_points - 1) in
      let y = (u *. 20.) -. 10. in
      let radius = if point = 0 || point = profile_points - 1 then 0.
        else 2. +. (0.35 *. sin (u *. 14. *. Float.pi))
          +. (0.12 *. cos (u *. 37. *. Float.pi)) in
      radius, y, 0.) in
  let source = Ops.polyline values |> get_ok in
  measure ~input_points:profile_points "revolve_dense_profile_triangles" (fun () ->
    Ops.revolve ~grain ~connectivity:Ops.Grid_alternating_triangles
      ~divisions:64 ~origin:Vec3.zero ~axis:Vec3.unit_y source |> get_ok)
    geometry_output;
  let point_id = Attribute.create_owned ~owner:Attribute.Point ~name:"profile_id"
      (Attribute.Int (Array.init profile_points Fun.id)) |> get_ok
  and vertex_u = Attribute.create_owned ~owner:Attribute.Vertex ~name:"profile_u"
      (Attribute.Float (Array.init profile_points (fun point ->
        float_of_int point /. float_of_int (profile_points - 1)))) |> get_ok
  and alternating = Group.init ~owner:Group.Point ~name:"alternating"
      profile_points (fun point -> point land 1 = 0) in
  let payload_source = source |> Geometry.with_attribute point_id |> get_ok
      |> Geometry.with_attribute vertex_u |> get_ok
      |> Geometry.with_group alternating |> get_ok
      |> Ops.group_edges ~grain ~name:"profile_edges" |> get_ok in
  measure ~input_points:profile_points "revolve_dense_profile_payload" (fun () ->
    Ops.revolve ~grain ~connectivity:Ops.Grid_quads ~caps:true
      ~cap_group:"caps" ~divisions:64 ~origin:Vec3.zero ~axis:Vec3.unit_y
      payload_source |> get_ok) geometry_output

let run_resample_benchmarks () =
  let source_points = curve_points in
  let source = Array.init source_points (fun point ->
      let t = float_of_int point *. 0.0005 in
      t, (2. *. sin (t *. 0.19)) +. (0.1 *. sin (t *. 2.7)),
      (1.5 *. cos (t *. 0.13)) +. (0.08 *. sin (t *. 3.1)))
    |> Ops.polyline |> get_ok in
  measure ~input_points:source_points "resample_long_spine" (fun () ->
    Ops.resample_curves ~grain ~segments:1_000_000 source |> get_ok)
    geometry_output;
  measure ~input_points:source_points
    "resample_long_spine_length_diagnostics" (fun () ->
      Ops.resample_curves ~grain ~maximum_segment_length:0.0001
        ~even_last_segment:false ~curve_u_attribute:"curveu"
        ~curve_number_attribute:"curvenum" ~distance_attribute:"distance"
        ~tangent_attribute:"tangent" source |> get_ok)
    geometry_output

let run_polyframe_benchmarks () =
  let source = Ops.grid ~grain ~columns:600 ~rows:600 ~uv_attribute:"uv"
      ~size:100. () |> get_ok in
  let input_points = Geometry.point_count source in
  measure ~input_points "polyframe_two_edges" (fun () ->
    Ops.polyframe ~grain ~orthogonal:true Ops.Two_edges source |> get_ok)
    geometry_output;
  measure ~input_points "polyframe_texture_uv" (fun () ->
    Ops.polyframe ~grain ~orthogonal:true (Ops.Texture_uv "uv") source
    |> get_ok) geometry_output;
  measure ~input_points "polyframe_attribute_gradient" (fun () ->
    Ops.polyframe ~grain ~orthogonal:true (Ops.Attribute_gradient "uv") source
    |> get_ok) geometry_output

let run_facet_benchmarks () =
  let source = Ops.grid ~grain ~columns:500 ~rows:400 ~uv_attribute:"uv"
      ~size:100. () |> get_ok in
  let displaced = Ops.noise_displace ~grain ~amplitude:0.8 ~frequency:0.7
      ~seed:927 source |> get_ok in
  let source_topology = Topology.Private.view (Geometry.topology source) in
  let vertex_points = Array.copy source_topology.vertex_points in
  for primitive = 1 to Geometry.primitive_count source - 1 do
    if primitive land 1 = 1 then begin
      let first = source_topology.primitive_offsets.(primitive)
      and last = source_topology.primitive_offsets.(primitive + 1) in
      for local = 0 to (last - first) / 2 - 1 do
        let left = first + local and right = last - local - 1 in
        let swap = vertex_points.(left) in
        vertex_points.(left) <- vertex_points.(right);
        vertex_points.(right) <- swap
      done
    end
  done;
  let topology = Topology.Private.create_validated_owned
      ~point_count:source_topology.point_count ~vertex_points
      ~primitive_offsets:(Array.copy source_topology.primitive_offsets)
      ~primitive_kinds:(Bytes.copy source_topology.primitive_kinds) in
  let inconsistent = Geometry.create ~positions:(Geometry.positions source)
      ~topology ~attributes:(Geometry.attributes source)
      ~groups:(Geometry.groups source) () |> get_ok in
  let inline_primitives = 200_000 in
  let inline_points = inline_primitives * 6 in
  let x = Array.make inline_points 0. and y = Array.make inline_points 0.
  and z = Array.make inline_points 0. in
  for primitive = 0 to inline_primitives - 1 do
    let point = primitive * 6 and base = float_of_int primitive *. 4. in
    x.(point) <- base;
    x.(point + 1) <- base +. 1.;
    x.(point + 2) <- base +. 2.;
    x.(point + 3) <- base +. 3.;
    x.(point + 4) <- base +. 3.; z.(point + 4) <- 1.;
    x.(point + 5) <- base; z.(point + 5) <- 1.
  done;
  let inline_positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let inline_topology = Topology.polygons_owned ~point_count:inline_points
      ~vertex_points:(Array.init inline_points Fun.id)
      ~primitive_offsets:(Array.init (inline_primitives + 1)
        (fun primitive -> primitive * 6)) |> get_ok in
  let inline_id = Attribute.create_owned ~owner:Attribute.Point ~name:"id"
      (Attribute.Int (Array.init inline_points Fun.id)) |> get_ok in
  let inline_source = Geometry.create ~positions:inline_positions
      ~topology:inline_topology ~attributes:[inline_id] () |> get_ok in
  let planar_primitives = 200_000 and planar_points = 800_000 in
  let planar_x = Array.make planar_points 0.
  and planar_y = Array.make planar_points 0.
  and planar_z = Array.make planar_points 0. in
  for primitive = 0 to planar_primitives - 1 do
    let point = primitive * 4 and base = float_of_int primitive *. 2. in
    planar_x.(point) <- base;
    planar_x.(point + 1) <- base +. 1.;
    planar_x.(point + 2) <- base +. 1.;
    planar_y.(point + 2) <- 1.;
    planar_y.(point + 3) <- 1.;
    planar_z.(point + 2) <- if primitive land 1 = 0 then 0.25 else -0.25
  done;
  let planar_positions = Packed.Float3.Private.of_owned_exn
      ~x:planar_x ~y:planar_y ~z:planar_z in
  let planar_topology = Topology.polygons_owned ~point_count:planar_points
      ~vertex_points:(Array.init planar_points Fun.id)
      ~primitive_offsets:(Array.init (planar_primitives + 1)
        (fun primitive -> primitive * 4)) |> get_ok in
  let planar_source = Geometry.create ~positions:planar_positions
      ~topology:planar_topology () |> get_ok in
  let normal_pairs = 600_000 and normal_points = 1_200_000 in
  let normal_x = Array.make normal_points 0.
  and normal_y = Array.make normal_points 0.
  and normal_z = Array.make normal_points 0.
  and nx = Array.make normal_points 0.
  and ny = Array.make normal_points 0. in
  for pair = 0 to normal_pairs - 1 do
    let point = pair * 2 and base = float_of_int pair *. 2. in
    normal_x.(point) <- base;
    normal_x.(point + 1) <- base +. 0.0001;
    nx.(point) <- 1.;
    ny.(point + 1) <- 1.
  done;
  let normal_positions = Packed.Float3.Private.of_owned_exn
      ~x:normal_x ~y:normal_y ~z:normal_z in
  let normal_topology = Topology.Private.create_validated_owned
      ~point_count:normal_points ~vertex_points:[||]
      ~primitive_offsets:[|0|] ~primitive_kinds:Bytes.empty in
  let normal = Attribute.create_owned ~owner:Attribute.Point ~name:"N"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:nx ~y:ny ~z:(Array.make normal_points 0.))) |> get_ok in
  let normal_source = Geometry.create ~positions:normal_positions
      ~topology:normal_topology ~attributes:[normal] () |> get_ok in
  let input_points = Geometry.point_count source in
  let selected_primitives = Group.init ~owner:Group.Primitive
      ~name:"facet_even" (Geometry.primitive_count source)
      (fun primitive -> primitive land 1 = 0)
  and selected_points = Group.init ~owner:Group.Point
      ~name:"facet_left_points" (Geometry.point_count source)
      (fun point -> point < Geometry.point_count source / 2)
  and selected_vertices = Group.init ~owner:Group.Vertex
      ~name:"facet_first_vertices" (Geometry.vertex_count source)
      (fun vertex -> vertex < Geometry.vertex_count source / 2)
  and selected_inline = Group.init ~owner:Group.Primitive
      ~name:"facet_inline_even" inline_primitives
      (fun primitive -> primitive land 1 = 0)
  and selected_planar = Group.init ~owner:Group.Primitive
      ~name:"facet_planar_even" planar_primitives
      (fun primitive -> primitive land 1 = 0) in
  let source_topology_value = Geometry.topology source in
  let source_index = Topology_index.create source_topology_value in
  let selected_edges = Edge_group.init ~topology:source_topology_value
      ~index:source_index ~name:"facet_sparse_edges"
      (fun edge -> edge mod 7 = 0) in
  measure ~input_points "facet_unique_points" (fun () ->
    Ops.facet ~grain ~unique_points:true source |> get_ok) geometry_output;
  measure ~input_points "facet_pre_normals_unique_reverse" (fun () ->
    Ops.facet ~grain ~pre_compute_normals:true
      ~make_normals_unit_length:true ~unique_points:true ~reverse_normals:true
      source |> get_ok) geometry_output;
  measure ~input_points "facet_group_pre_normals_unique_reverse" (fun () ->
    Ops.facet ~grain ~primitives:selected_primitives ~pre_compute_normals:true
      ~make_normals_unit_length:true ~unique_points:true ~reverse_normals:true
      source |> get_ok) geometry_output;
  measure ~input_points "facet_group_unique_points" (fun () ->
    Ops.facet ~grain ~primitives:selected_primitives ~unique_points:true source
    |> get_ok) geometry_output;
  measure ~input_points "facet_point_selection_unique_points" (fun () ->
    Ops.facet ~grain ~selection:(Ops.Selected_points selected_points)
      ~unique_points:true source |> get_ok) geometry_output;
  measure ~input_points "facet_vertex_selection_unique_points" (fun () ->
    Ops.facet ~grain ~selection:(Ops.Selected_vertices selected_vertices)
      ~unique_points:true source |> get_ok) geometry_output;
  measure ~input_points "facet_edge_selection_unique_points" (fun () ->
    Ops.facet ~grain ~selection:(Ops.Selected_edges selected_edges)
      ~unique_points:true source |> get_ok) geometry_output;
  measure ~input_points "facet_group_pre_normals" (fun () ->
    Ops.facet ~grain ~primitives:selected_primitives ~pre_compute_normals:true
      source |> get_ok) geometry_output;
  measure ~input_points "facet_orient_polygons" (fun () ->
    Ops.facet ~grain ~orient_polygons:true inconsistent |> get_ok)
    geometry_output;
  measure ~input_points "facet_cusp_polygons" (fun () ->
    Ops.facet ~grain ~cusp_angle:0.08 displaced |> get_ok) geometry_output;
  measure ~input_points:inline_points "facet_remove_inline_points" (fun () ->
    Ops.facet ~grain ~remove_inline_points:true inline_source |> get_ok)
    geometry_output;
  measure ~input_points:inline_points "facet_group_remove_inline_points"
    (fun () -> Ops.facet ~grain ~primitives:selected_inline
      ~remove_inline_points:true inline_source |> get_ok) geometry_output;
  measure ~input_points:planar_points "facet_make_planar" (fun () ->
    Ops.facet ~grain ~make_planar:true planar_source |> get_ok) geometry_output;
  measure ~input_points:planar_points "facet_group_make_planar" (fun () ->
    Ops.facet ~grain ~primitives:selected_planar ~make_planar:true planar_source
    |> get_ok) geometry_output;
  measure ~input_points:normal_points "facet_consolidate_point_normals"
    (fun () -> Ops.facet ~grain ~consolidate_normals_distance:0.001
      normal_source |> get_ok) geometry_output

let run_poly_extrude_benchmarks () =
  let geometry = Ops.grid ~columns:200 ~rows:200 ~size:20. () |> get_ok in
  let input_points = Geometry.point_count geometry in
  measure ~input_points "poly_extrude" (fun () ->
    Ops.poly_extrude ~grain ~distance:0.2 geometry |> get_ok) geometry_output;
  measure ~input_points "poly_extrude_connected" (fun () ->
    Ops.poly_extrude ~grain ~divide:Ops.Extrude_connected_components
      ~distance:0.2 geometry |> get_ok) geometry_output;
  measure ~input_points "poly_extrude_connected_divisions4" (fun () ->
    Ops.poly_extrude ~grain ~divide:Ops.Extrude_connected_components
      ~divisions:4 ~distance:0.2 geometry |> get_ok) geometry_output;
  measure ~input_points "poly_extrude_connected_boundaries" (fun () ->
    Ops.poly_extrude ~grain ~divide:Ops.Extrude_connected_components
      ~divisions:4 ~front_boundary_group:"front_rim"
      ~back_boundary_group:"back_rim" ~distance:0.2 geometry |> get_ok)
    geometry_output

let run_poly_fill_benchmarks () =
  let count = poly_fill_boxes in
  let point_count = count * 8 and primitive_count = count * 5
  and vertex_count = count * 20 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. and vertex_points = Array.make vertex_count 0
  and primitive_offsets = Array.init (primitive_count + 1) (fun p -> p * 4) in
  let local_x = [|-1.;1.;1.;-1.;-1.;1.;1.;-1.|]
  and local_y = [|-1.;-1.;1.;1.;-1.;-1.;1.;1.|]
  and local_z = [|-1.;-1.;-1.;-1.;1.;1.;1.;1.|]
  and local_vertices = [|0;3;2;1; 0;1;5;4; 1;2;6;5; 2;3;7;6; 3;0;4;7|] in
  for box = 0 to count - 1 do
    let point_base = box * 8 and vertex_base = box * 20 in
    let gx = box mod 512 and gy = box / 512 in
    for local = 0 to 7 do
      x.(point_base + local) <- float_of_int gx *. 3. +. local_x.(local);
      y.(point_base + local) <- float_of_int gy *. 3. +. local_y.(local);
      z.(point_base + local) <- local_z.(local)
    done;
    for local = 0 to 19 do
      vertex_points.(vertex_base + local) <- point_base + local_vertices.(local)
    done
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets |> get_ok in
  let point_color = Attribute.create_owned ~owner:Attribute.Point ~name:"Cd"
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.init point_count (fun point -> float_of_int (point land 255) /. 255.))
        ~y:(Array.make point_count 0.4) ~z:(Array.make point_count 0.8)
        ~w:(Array.make point_count 1.) |> get_ok)) |> get_ok
  and vertex_uv = Attribute.create_owned ~owner:Attribute.Vertex ~name:"uv"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init vertex_count (fun vertex -> float_of_int (vertex land 3) /. 3.))
        ~y:(Array.init vertex_count (fun vertex -> float_of_int ((vertex lsr 2) land 1)))
        |> get_ok)) |> get_ok
  and primitive_piece = Attribute.create_owned ~owner:Attribute.Primitive
      ~name:"piece" (Attribute.Int
        (Array.init primitive_count (fun primitive -> primitive / 5))) |> get_ok in
  let top_points = Group.init ~owner:Group.Point ~name:"top" point_count
      (fun point -> point land 7 >= 4)
  and bottoms = Group.init ~owner:Group.Primitive ~name:"bottom" primitive_count
      (fun primitive -> primitive mod 5 = 0) in
  let index = Topology_index.create topology in
  let rims = Edge_group.init ~topology ~index ~name:"rims" (fun edge ->
      Topology_index.edge_incidence_count index edge = 1) in
  let source = Geometry.create ~positions ~topology
      ~attributes:[point_color; vertex_uv; primitive_piece]
      ~groups:[top_points; bottoms] ~edge_groups:[rims] () |> get_ok in
  measure ~input_points:point_count "poly_fill_single_polygon" (fun () ->
    Ops.poly_fill ~grain ~mode:Ops.Fill_single_polygon ~patch_group:"patch"
      source |> get_ok) geometry_output;
  measure ~input_points:point_count "poly_fill_triangles" (fun () ->
    Ops.poly_fill ~grain ~mode:Ops.Fill_triangles ~patch_group:"patch"
      source |> get_ok) geometry_output;
  measure ~input_points:point_count "poly_fill_triangle_fan_unique" (fun () ->
    Ops.poly_fill ~grain ~mode:Ops.Fill_triangle_fan ~unique_points:true
      ~patch_group:"patch" source |> get_ok) geometry_output

let run_clean_benchmarks () =
  let primitive_count = 200_000 in
  let used_points = primitive_count * 3 and unused_points = 10_000 in
  let point_count = used_points + unused_points in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for primitive = 0 to primitive_count - 1 do
    let point = primitive * 3 and base = float_of_int primitive *. 0.001 in
    x.(point) <- base;
    x.(point + 1) <- base +. 0.0005;
    x.(point + 2) <- base +. 0.00025;
    y.(point + 2) <- if primitive land 7 = 0 then 0. else 0.001
  done;
  for point = used_points to point_count - 1 do
    x.(point) <- float_of_int point *. 0.001;
    y.(point) <- 2.
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.polygons_owned ~point_count
      ~vertex_points:(Array.init used_points Fun.id)
      ~primitive_offsets:(Array.init (primitive_count + 1)
        (fun primitive -> primitive * 3)) |> get_ok in
  let weight = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float (Array.init point_count (fun point ->
        float_of_int (point land 255)))) |> get_ok
  and primitive_id = Attribute.create_owned ~name:"primitive_id"
      ~owner:Attribute.Primitive
      (Attribute.Int (Array.init primitive_count Fun.id)) |> get_ok
  and marked_points = Group.init ~owner:Group.Point ~name:"marked_points"
      point_count (fun point -> point mod 17 = 0)
  and marked_primitives = Group.init ~owner:Group.Primitive
      ~name:"marked_primitives" primitive_count
      (fun primitive -> primitive mod 19 = 0) in
  let geometry = Geometry.create ~positions ~topology
      ~attributes:[weight; primitive_id]
      ~groups:[marked_points; marked_primitives] () |> get_ok in
  measure ~input_points:point_count "clean_degenerate" (fun () ->
    Ops.clean ~grain ~epsilon:1e-12 geometry |> get_ok) geometry_output;
  measure ~input_points:point_count "clean_degenerate_compact" (fun () ->
    Ops.clean ~grain ~epsilon:1e-12 ~remove_unused_points:true geometry |> get_ok)
    geometry_output;
  let overlap_primitives = primitive_count * 2 in
  let overlap_vertices = used_points * 2 in
  let overlap_vertex_points = Array.make overlap_vertices 0 in
  for primitive = 0 to primitive_count - 1 do
    let source = primitive * 3 and output = primitive * 6 in
    let a = source and b = source + 1 and c = source + 2 in
    overlap_vertex_points.(output) <- a;
    overlap_vertex_points.(output + 1) <- b;
    overlap_vertex_points.(output + 2) <- c;
    overlap_vertex_points.(output + 3) <- b;
    overlap_vertex_points.(output + 4) <- c;
    overlap_vertex_points.(output + 5) <- a
  done;
  let overlap_topology = Topology.polygons_owned ~point_count
      ~vertex_points:overlap_vertex_points
      ~primitive_offsets:(Array.init (overlap_primitives + 1)
        (fun primitive -> primitive * 3)) |> get_ok in
  let overlap_id = Attribute.create_owned ~name:"primitive_id"
      ~owner:Attribute.Primitive
      (Attribute.Int (Array.init overlap_primitives (fun primitive -> primitive / 2)))
      |> get_ok in
  let overlap_geometry = Geometry.create ~positions
      ~topology:overlap_topology ~attributes:[weight; overlap_id]
      ~groups:[marked_points] () |> get_ok in
  measure ~input_points:point_count "clean_overlaps_keep_first" (fun () ->
    Ops.clean ~grain ~remove_degenerate:false
      ~overlaps:Ops.Keep_first_overlap overlap_geometry |> get_ok)
    geometry_output

let run_transfer_benchmarks filter =
  if String.starts_with ~prefix:"attribute_transfer_detail" filter then begin
    let attributes = Array.init attribute_count (fun index ->
      Attribute.create_owned ~name:(Printf.sprintf "detail_%05d" index)
        ~owner:Attribute.Detail (Attribute.Int [|index|]) |> get_ok) in
    let base = Ops.points [||] in
    let source = Geometry.create ~positions:(Geometry.positions base)
        ~topology:(Geometry.topology base) ~attributes:(Array.to_list attributes) ()
        |> get_ok in
    measure ~input_points:attribute_count
      "attribute_transfer_detail_rebuild_baseline" (fun () ->
        Array.fold_left (fun geometry attribute ->
          Geometry.with_attribute attribute geometry |> get_ok) base attributes)
      geometry_output;
    measure ~input_points:attribute_count "attribute_transfer_detail_batch"
      (fun () -> Attribute_ops.transfer_detail ~source ~target:base () |> get_ok)
      geometry_output
  end else
  let modeling_grid = Ops.grid ~columns:200 ~rows:200 ~size:20. () |> get_ok in
  let input_points = Geometry.point_count modeling_grid in
  let transfer_target = Ops.transform ~grain
      (Mat4.translation (Vec3.create 0.015 0. 0.012)) modeling_grid in
  let point_source_group = Group.init ~owner:Group.Point ~name:"point_source"
      input_points (fun _ -> true)
  and point_target_group = Group.init ~owner:Group.Point ~name:"point_target"
      (Geometry.point_count transfer_target) (fun _ -> true) in
  measure ~input_points "attribute_transfer_inverse4" (fun () ->
    Attribute_ops.transfer_points ~grain ~names:["N"]
      ~mode:(Attribute_ops.Inverse_distance { neighbors = 4; power = 2. })
      ~max_distance:0.2 ~source_points:point_source_group
      ~target_points:point_target_group ~source:modeling_grid
      ~target:transfer_target () |> get_ok)
    geometry_output;
  measure ~input_points "attribute_transfer_kernel4_hart" (fun () ->
    Attribute_ops.transfer_points ~grain ~names:["N"]
      ~mode:(Attribute_ops.Kernel {
        neighbors = 4; radius = 0.2; kernel = Attribute_ops.Hart })
      ~max_distance:0.2 ~source_points:point_source_group
      ~target_points:point_target_group ~source:modeling_grid
      ~target:transfer_target () |> get_ok)
    geometry_output;
  if String.equal filter "attribute_transfer_inverse4"
      || String.equal filter "attribute_transfer_kernel4_hart" then ()
  else if String.starts_with ~prefix:"surface_index" filter then begin
    measure ~input_points "surface_index" (fun () ->
      Surface_index.create ~grain modeling_grid |> get_ok) surface_index_output;
    let selected_vertices = Group.init ~owner:Group.Vertex
        ~name:"surface_vertex_half" (Geometry.vertex_count modeling_grid)
        (fun vertex -> vertex < Geometry.vertex_count modeling_grid / 2) in
    measure ~input_points "surface_index_vertex_restricted" (fun () ->
      Surface_index.create ~grain ~vertices:selected_vertices modeling_grid
      |> get_ok) surface_index_output;
    let quads = Ops.subdivide ~grain ~scheme:Ops.Bilinear modeling_grid |> get_ok in
    measure ~input_points "surface_index_quads" (fun () ->
      Surface_index.create ~grain quads |> get_ok) surface_index_output
  end else begin
    let vertex_count = Geometry.vertex_count modeling_grid
    and primitive_count = Geometry.primitive_count modeling_grid in
    let uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
        (Attribute.Float2 (Packed.Float2.of_owned
          ~x:(Array.init vertex_count (fun index ->
            float_of_int (index mod 3) *. 0.5))
          ~y:(Array.init vertex_count (fun index ->
            float_of_int ((index / 3) land 1))) |> get_ok)) |> get_ok
    and density = Attribute.create_owned ~name:"density"
        ~owner:Attribute.Primitive
        (Attribute.Float (Array.init primitive_count (fun index ->
          float_of_int (index mod 97) /. 96.))) |> get_ok in
    let source = modeling_grid
        |> Geometry.with_attribute uv |> get_ok
        |> Geometry.with_attribute density |> get_ok
        |> Ops.color_by_height ~grain ~low:low_color ~high:high_color |> get_ok in
    let revision = Attribute.create_owned ~name:"revision"
        ~owner:Attribute.Detail (Attribute.Int [|17|]) |> get_ok in
    let source = Geometry.with_attribute revision source |> get_ok in
    let surface_target = Ops.transform ~grain
        (Mat4.translation (Vec3.create 0.015 0.2 0.012)) modeling_grid in
    let source_primitives = Group.init ~owner:Group.Primitive
        ~name:"surface_source" primitive_count (fun _ -> true)
    and target_points = Group.init ~owner:Group.Point
        ~name:"surface_target" (Geometry.point_count surface_target) (fun _ -> true)
    and target_vertices = Group.init ~owner:Group.Vertex
        ~name:"surface_target_vertices" (Geometry.vertex_count surface_target)
        (fun _ -> true)
    and target_primitives = Group.init ~owner:Group.Primitive
        ~name:"surface_target_primitives" (Geometry.primitive_count surface_target)
        (fun _ -> true)
    and source_vertices = Group.init ~owner:Group.Vertex
        ~name:"surface_vertex_half" vertex_count
        (fun vertex -> vertex < vertex_count / 2) in
    let surface_specs = [
      Attribute_ops.surface_attribute ~owner:Attribute.Point "Cd";
      Attribute_ops.surface_attribute ~owner:Attribute.Vertex "uv";
      Attribute_ops.surface_attribute ~owner:Attribute.Primitive "density";
    ] in
    measure ~input_points "attribute_transfer_surface" (fun () ->
      Attribute_ops.transfer_surface ~grain ~max_distance:0.1 ~blend_width:0.4
        ~falloff:Attribute_ops.Smoothstep ~source_primitives ~target_points
        ~distance_attribute:"surface_distance" ~attributes:surface_specs
        ~source ~target:surface_target () |> get_ok) geometry_output;
    measure ~input_points "attribute_transfer_surface_vertex_restricted" (fun () ->
      Attribute_ops.transfer_surface ~grain ~max_distance:0.1 ~blend_width:0.4
        ~falloff:Attribute_ops.Smoothstep ~source_primitives ~source_vertices
        ~target_points ~distance_attribute:"surface_distance"
        ~attributes:surface_specs ~source ~target:surface_target () |> get_ok)
      geometry_output;
    measure ~input_points "attribute_transfer_primitives" (fun () ->
      Attribute_ops.transfer_primitives ~grain ~names:["density"]
        ~mode:(Attribute_ops.Inverse_distance { neighbors = 4; power = 2. })
        ~max_distance:0.5 ~source_primitives ~target_primitives
        ~source ~target:surface_target () |> get_ok) geometry_output;
    measure ~input_points "attribute_transfer_inverse4_blend" (fun () ->
      Attribute_ops.transfer_points ~grain ~pattern:"Cd N"
        ~mode:(Attribute_ops.Inverse_distance { neighbors = 4; power = 2. })
        ~max_distance:0.1 ~blend_width:0.4
        ~falloff:Attribute_ops.Smoothstep ~source ~target:surface_target ()
      |> get_ok) geometry_output;
    measure ~input_points "attribute_transfer_all_sequential_baseline" (fun () ->
      Attribute_ops.transfer_points ~grain ~pattern:"Cd N" ~max_distance:0.5
        ~source ~target:surface_target () |> get_ok
      |> fun target -> Attribute_ops.transfer_primitives ~grain
          ~pattern:"density" ~max_distance:0.5 ~source ~target () |> get_ok
      |> fun target -> Attribute_ops.transfer_vertices ~grain ~pattern:"uv"
          ~max_distance:0.5 ~source ~target () |> get_ok
      |> fun target -> Attribute_ops.transfer_detail ~pattern:"revision"
          ~source ~target () |> get_ok) geometry_output;
    measure ~input_points "attribute_transfer_all" (fun () ->
      Attribute_ops.transfer_all ~grain ~point_pattern:"Cd N"
        ~primitive_pattern:"density" ~vertex_pattern:"uv"
        ~detail_pattern:"revision" ~max_distance:0.5
        ~source ~target:surface_target () |> get_ok) geometry_output;
    measure ~input_points "attribute_transfer_vertices" (fun () ->
      Attribute_ops.transfer_vertices ~grain ~names:["uv"] ~max_distance:0.5
        ~source_primitives ~target_vertices ~source ~target:surface_target ()
        |> get_ok) geometry_output;
    measure ~input_points "attribute_transfer_surface_vertices" (fun () ->
      Attribute_ops.transfer_surface ~grain ~max_distance:0.1 ~blend_width:0.4
        ~target_owner:Attribute.Vertex ~target_elements:target_vertices
        ~distance_attribute:"surface_distance" ~attributes:surface_specs
        ~source ~target:surface_target () |> get_ok) geometry_output;
    measure ~input_points "attribute_transfer_surface_primitives" (fun () ->
      Attribute_ops.transfer_surface ~grain ~max_distance:0.1 ~blend_width:0.4
        ~target_owner:Attribute.Primitive ~target_elements:target_primitives
        ~distance_attribute:"surface_distance" ~attributes:surface_specs
        ~source ~target:surface_target () |> get_ok) geometry_output
  end

let run_attribute_copy_benchmarks () =
  let count = columns * rows in
  let point_geometry count =
    let positions = Packed.Float3.Private.of_owned_exn
        ~x:(Array.init count (fun point -> float_of_int point *. 0.0001))
        ~y:(Array.init count (fun point -> sin (float_of_int point *. 0.0003)))
        ~z:(Array.make count 0.) in
    Geometry.create ~positions ~topology:(Topology.empty ~point_count:count) ()
    |> get_ok in
  let add_attribute attribute geometry =
    Geometry.with_attribute attribute geometry |> get_ok in
  let source = point_geometry count in
  let weight = Attribute.create_owned ~name:"weight" ~owner:Attribute.Point
      (Attribute.Float (Array.init count (fun point ->
        float_of_int (point land 1023) /. 1023.))) |> get_ok
  and id = Attribute.create_owned ~name:"id" ~owner:Attribute.Point
      (Attribute.Int (Array.init count (fun point -> point lxor 0x5a5a))) |> get_ok
  and uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Point
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init count (fun point ->
          float_of_int (point mod 1000) /. 999.))
        ~y:(Array.init count (fun point ->
          float_of_int (point / 1000) /. 999.)) |> get_ok)) |> get_ok
  and velocity = Attribute.create_owned ~name:"velocity" ~owner:Attribute.Point
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.init count (fun point -> cos (float_of_int point *. 0.001)))
        ~y:(Array.init count (fun point -> sin (float_of_int point *. 0.001)))
        ~z:(Array.make count 0.25))) |> get_ok in
  let source = source |> add_attribute weight |> add_attribute id
      |> add_attribute uv |> add_attribute velocity in
  let target = point_geometry count in
  let clone attribute =
    let storage = match Attribute.Private.storage attribute with
      | Attribute.Float values -> Attribute.Float (Array.copy values)
      | Attribute.Int values -> Attribute.Int (Array.copy values)
      | Attribute.Text values -> Attribute.Text (Array.copy values)
      | Attribute.Float2 values ->
          let values = Packed.Float2.Private.view values in
          Attribute.Float2 (Packed.Float2.of_owned ~x:(Array.copy values.x)
            ~y:(Array.copy values.y) |> get_ok)
      | Attribute.Float3 values ->
          let values = Packed.Float3.Private.view values in
          Attribute.Float3 (Packed.Float3.Private.of_owned_exn
            ~x:(Array.copy values.x) ~y:(Array.copy values.y)
            ~z:(Array.copy values.z))
      | Attribute.Float4 values ->
          let values = Packed.Float4.Private.view values in
          Attribute.Float4 (Packed.Float4.of_owned ~x:(Array.copy values.x)
            ~y:(Array.copy values.y) ~z:(Array.copy values.z)
            ~w:(Array.copy values.w) |> get_ok)
      | Attribute.Int_array values ->
          let values = Packed.Int_array.Private.view values in
          Attribute.Int_array (Packed.Int_array.Private.create_validated_owned
            ~offsets:(Array.copy values.offsets) ~values:(Array.copy values.values))
      | Attribute.Float_array values ->
          let values = Packed.Float_array.Private.view values in
          Attribute.Float_array (Packed.Float_array.Private.create_validated_owned
            ~offsets:(Array.copy values.offsets) ~values:(Array.copy values.values)) in
    Attribute.create_owned ~name:(Attribute.name attribute)
      ~owner:(Attribute.owner attribute) storage |> get_ok in
  measure ~input_points:count "attribute_copy_materialized_baseline" (fun () ->
    Geometry.create ~positions:(Geometry.positions target)
      ~topology:(Geometry.topology target)
      ~attributes:(List.map clone (Geometry.attributes source)) () |> get_ok)
    geometry_output;
  let rules = [Attribute_ops.copy_rule ~owner:Attribute.Point
      "weight id uv velocity"] in
  measure ~input_points:count "attribute_copy_identity_shared" (fun () ->
    Attribute_ops.copy ~grain ~group_owner:Group.Point ~rules
      ~source ~target () |> get_ok) geometry_output;
  let source_count = max 1 (count / 4) in
  let cyclic_source = point_geometry source_count in
  let cyclic_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point (Attribute.Float (Array.init source_count
        (fun point -> float_of_int (point land 4095)))) |> get_ok in
  let cyclic_source = add_attribute cyclic_weight cyclic_source in
  measure ~input_points:count "attribute_copy_cyclic" (fun () ->
    Attribute_ops.copy ~grain ~group_owner:Group.Point
      ~rules:[Attribute_ops.copy_rule ~owner:Attribute.Point "weight"]
      ~source:cyclic_source ~target () |> get_ok) geometry_output

let run_attribute_combine_benchmarks () =
  let count = columns * rows in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init count (fun point -> float_of_int point *. 0.0001))
      ~y:(Array.init count (fun point -> sin (float_of_int point *. 0.0003)))
      ~z:(Array.make count 0.) in
  let geometry = Geometry.create ~positions
      ~topology:(Topology.empty ~point_count:count) () |> get_ok in
  let tuple name phase = Attribute.create_owned ~name ~owner:Attribute.Point
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.init count (fun point ->
          sin ((float_of_int point *. 0.001) +. phase)))
        ~y:(Array.init count (fun point ->
          cos ((float_of_int point *. 0.0007) +. phase)))
        ~z:(Array.init count (fun point ->
          float_of_int (point land 255) /. 255.))
        ~w:(Array.make count (0.5 +. (phase *. 0.1))) |> get_ok)) |> get_ok in
  let mask = Attribute.create_owned ~name:"mask" ~owner:Attribute.Point
      (Attribute.Float (Array.init count (fun point ->
        float_of_int (point land 1023) /. 1023.))) |> get_ok in
  let add attribute geometry = Geometry.with_attribute attribute geometry |> get_ok in
  let geometry = geometry |> add (tuple "result" 0.1)
      |> add (tuple "field_a" 0.3) |> add (tuple "field_b" 0.7)
      |> add (tuple "field_c" 1.1) |> add mask in
  let layers = [
    Attribute_ops.combine_layer ~source:"field_a" ~blend:0.7
      ~blend_attribute:"mask" Attribute_ops.Combine_copy;
    Attribute_ops.combine_layer ~source:"field_b" ~scale:0.25
      Attribute_ops.Combine_add;
    Attribute_ops.combine_layer ~add:0.9 Attribute_ops.Combine_multiply;
    Attribute_ops.combine_layer ~source:"field_c"
      Attribute_ops.Combine_maximum;
  ] in
  let one_layer geometry layer = Attribute_ops.combine ~grain
      ~owner:Attribute.Point ~destination:"result" ~layers:[layer]
      ~geometries:[|geometry|] () |> get_ok in
  measure ~input_points:count "attribute_combine_sequential_layers" (fun () ->
    List.fold_left one_layer geometry layers) geometry_output;
  measure ~input_points:count "attribute_combine_fused_layers" (fun () ->
    Attribute_ops.combine ~grain ~owner:Attribute.Point ~destination:"result"
      ~layers ~geometries:[|geometry|] () |> get_ok) geometry_output;
  let primary_key = Attribute.create_owned ~name:"key" ~owner:Attribute.Point
      (Attribute.Int (Array.init count (fun point -> point))) |> get_ok in
  let primary = add primary_key geometry in
  let source_key = Attribute.create_owned ~name:"key" ~owner:Attribute.Point
      (Attribute.Int (Array.init count (fun point -> count - point - 1))) |> get_ok
  and matched = Attribute.create_owned ~name:"matched" ~owner:Attribute.Point
      (Attribute.Float (Array.init count float_of_int)) |> get_ok in
  let source = Geometry.create ~positions ~topology:(Topology.empty ~point_count:count)
      ~attributes:[source_key; matched] () |> get_ok in
  measure ~input_points:count "attribute_combine_matched_input" (fun () ->
    Attribute_ops.combine ~grain ~match_attribute:"key" ~owner:Attribute.Point
      ~destination:"matched_result"
      ~layers:[Attribute_ops.combine_layer ~source:"matched" ~source_input:1
        Attribute_ops.Combine_copy]
      ~geometries:[|primary;source|] () |> get_ok) geometry_output

let run_attribute_interpolate_benchmarks () =
  let count = columns * rows in
  let source_positions = Packed.Float3.Private.of_owned_exn
      ~x:[|0.;0.;1.;1.|] ~y:[|0.;1.;1.;0.|] ~z:[|0.;0.2;0.4;0.1|] in
  let source_topology = Topology.create_owned ~point_count:4
      ~vertex_points:[|0;1;2;3|] ~primitive_offsets:[|0;4|]
      ~primitive_kinds:[|Topology.Polygon|] |> get_ok in
  let attribute name storage = Attribute.create_owned ~name
      ~owner:Attribute.Point storage |> get_ok in
  let hot = Group.init ~owner:Group.Point ~name:"hot" 4
      (fun point -> point = 1 || point = 2) in
  let source = Geometry.create ~positions:source_positions ~topology:source_topology
      ~groups:[hot]
      ~attributes:[
        attribute "weight" (Attribute.Float [|0.;1.;2.;3.|]);
        attribute "id" (Attribute.Int [|3;5;7;11|]);
        attribute "label" (Attribute.Text [|"a";"b";"c";"d"|]);
        attribute "uv" (Attribute.Float2 (Packed.Float2.of_owned
          ~x:[|0.;0.;1.;1.|] ~y:[|0.;1.;1.;0.|] |> get_ok));
        attribute "N" (Attribute.Float3
          (Packed.Float3.Private.of_owned_exn
            ~x:[|0.;0.;0.;0.|] ~y:[|1.;1.;1.;1.|]
            ~z:[|0.;0.;0.;0.|]));
        attribute "tuple4" (Attribute.Float4 (Packed.Float4.of_owned
          ~x:[|0.;1.;2.;3.|] ~y:[|4.;5.;6.;7.|]
          ~z:[|8.;9.;10.;11.|] ~w:[|12.;13.;14.;15.|] |> get_ok));
        attribute "neighbors" (Attribute.Int_array
          (Packed.Int_array.create_owned ~offsets:[|0;1;3;3;6|]
            ~values:[|0;1;2;3;4;5|] |> get_ok));
        attribute "samples" (Attribute.Float_array
          (Packed.Float_array.create_owned ~offsets:[|0;1;3;3;6|]
            ~values:[|0.25;1.;2.;3.;4.;5.|] |> get_ok));
      ] () |> get_ok in
  let target_positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.make count 0.) ~y:(Array.make count 0.) ~z:(Array.make count 0.) in
  let primitive_driver = attribute "source_primitive"
      (Attribute.Int (Array.make count 0))
  and uvw_driver = attribute "source_uvw" (Attribute.Float3
      (Packed.Float3.Private.of_owned_exn
        ~x:(Array.init count (fun point ->
          float_of_int (point land 1023) /. 1023.))
        ~y:(Array.init count (fun point ->
          float_of_int ((point * 37) land 1023) /. 1023.))
        ~z:(Array.make count 0.))) in
  let target = Geometry.create ~positions:target_positions
      ~topology:(Topology.empty ~point_count:count)
      ~attributes:[primitive_driver;uvw_driver] () |> get_ok in
  let attributes = [
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "P";
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "weight";
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "id";
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "label";
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "uv";
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "N";
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "tuple4";
  ] in
  let sequential () = List.fold_left (fun target attribute ->
      Attribute_ops.interpolate ~grain ~target_owner:Attribute.Point
        ~attributes:[attribute] ~source ~target () |> get_ok) target attributes in
  let fused () = Attribute_ops.interpolate ~grain ~target_owner:Attribute.Point
      ~attributes ~source ~target () |> get_ok in
  let compute_weights : Attribute_ops.interpolate_computed = {
    computed_owner=Attribute.Point;
    computed_numbers_attribute="computed_points";
    computed_weights_attribute="computed_weights" } in
  let fused_computed () = Attribute_ops.interpolate ~grain
      ~compute_weights ~target_owner:Attribute.Point
      ~attributes ~source ~target () |> get_ok in
  let computed_target = fused_computed () in
  let weighted () = Attribute_ops.interpolate ~grain
      ~driver:(Attribute_ops.Point_weights {
        numbers_attribute="computed_points";
        weights_attribute="computed_weights" })
      ~target_owner:Attribute.Point ~attributes ~source
      ~target:computed_target () |> get_ok in
  let weighted_groups () = Attribute_ops.interpolate ~grain
      ~driver:(Attribute_ops.Point_weights {
        numbers_attribute="computed_points";
        weights_attribute="computed_weights" })
      ~point_pattern:"hot" ~match_groups:true
      ~target_owner:Attribute.Point ~attributes ~source
      ~target:computed_target () |> get_ok in
  let array_attributes = [
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "neighbors";
    Attribute_ops.interpolate_attribute ~owner:Attribute.Point "samples";
  ] in
  let array_rows () = Attribute_ops.interpolate ~grain
      ~target_owner:Attribute.Point ~attributes:array_attributes
      ~source ~target () |> get_ok in
  let array_rows_weighted () = Attribute_ops.interpolate ~grain
      ~driver:(Attribute_ops.Point_weights {
        numbers_attribute="computed_points";
        weights_attribute="computed_weights" })
      ~target_owner:Attribute.Point ~attributes:array_attributes ~source
      ~target:computed_target () |> get_ok in
  let sequential_hash = geometry_hash (sequential ()) in
  let fused_hash = geometry_hash (fused ()) in
  if sequential_hash <> fused_hash then
    failwith "Attribute Interpolate fused output differs from sequential fields";
  if geometry_hash (weighted ()) <> geometry_hash computed_target then
    failwith "Attribute Interpolate computed/weighted output differs from primitive UVW";
  measure ~input_points:count "attribute_interpolate_sequential_attributes"
    sequential geometry_output;
  measure ~input_points:count "attribute_interpolate_fused" fused geometry_output;
  measure ~input_points:count "attribute_interpolate_fused_computed"
      fused_computed geometry_output;
  measure ~input_points:count "attribute_interpolate_weighted"
      weighted geometry_output;
  measure ~input_points:count "attribute_interpolate_weighted_groups"
      weighted_groups geometry_output;
  measure ~input_points:count "attribute_interpolate_array_rows"
      array_rows geometry_output;
  measure ~input_points:count "attribute_interpolate_array_rows_weighted"
      array_rows_weighted geometry_output

let run_attribute_pattern_benchmark () =
  let names = Array.init 1_024 (fun index ->
    if index mod 8 = 0 then Printf.sprintf "attr_tmp_%d" index
    else if index mod 17 = 0 then "attr_tmp_keep"
    else Printf.sprintf "attr_value_%d" index) in
  let pattern = Attribute_pattern.compile
      "attr_* ^attr_tmp_* attr_tmp_keep" |> get_ok in
  measure ~input_points:(Array.length names) "attribute_pattern_million" (fun () ->
    let cardinality = ref 0 and hash = ref 17 in
    for iteration = 0 to 999 do
      for index = 0 to Array.length names - 1 do
        if Attribute_pattern.matches pattern names.(index) then begin
          incr cardinality;
          hash := mix !hash (index + iteration)
        end
      done
    done;
    !cardinality, !hash) Fun.id

let run_enumerate_benchmarks () =
  let count = (columns + 1) * (rows + 1) in
  let source = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:(Array.init count (fun point -> float_of_int point *. 0.0001))
        ~y:(Array.make count 0.) ~z:(Array.make count 0.))
      ~topology:(Topology.empty ~point_count:count) () |> get_ok in
  measure ~input_points:count "enumerate_points" (fun () ->
    Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"sequence"
      source |> get_ok) geometry_output;
  let enumerate_half = Group.init ~owner:Group.Point ~name:"enumerate_half"
      count (fun point -> point land 1 = 0) in
  measure ~input_points:count "enumerate_points_group" (fun () ->
    Attribute_ops.enumerate ~grain ~selection:enumerate_half ~start:7 ~step:3
      ~owner:Attribute.Point ~name:"sequence" source |> get_ok) geometry_output;
  let integer_pieces = Attribute.create_owned ~owner:Attribute.Point
      ~name:"piece" (Attribute.Int (Array.init count (fun point ->
        (point * 31) mod 4093))) |> get_ok in
  let text_piece_names = Array.init 4093 (fun piece ->
      Printf.sprintf "piece_%04d" piece) in
  let text_pieces = Attribute.create_owned ~owner:Attribute.Point
      ~name:"text_piece" (Attribute.Text (Array.init count (fun point ->
        text_piece_names.((point * 31) mod 4093)))) |> get_ok in
  let source = source
      |> Geometry.with_attribute integer_pieces |> get_ok
      |> Geometry.with_attribute text_pieces |> get_ok in
  let reference () =
    let counts = Hashtbl.create 4093 and values = Array.make count 0 in
    for point = 0 to count - 1 do
      let piece = (point * 31) mod 4093 in
      let rank = match Hashtbl.find_opt counts piece with
        | Some rank -> rank | None -> 0 in
      values.(point) <- rank;
      Hashtbl.replace counts piece (rank + 1)
    done;
    let attribute = Attribute.create_owned ~owner:Attribute.Point ~name:"local"
        (Attribute.Int values) |> get_ok in
    Geometry.with_attribute attribute source |> get_ok in
  measure ~input_points:count "enumerate_piece_elements_reference" reference
    geometry_output;
  measure ~input_points:count "enumerate_piece_elements_int4093" (fun () ->
    Attribute_ops.enumerate ~grain ~piece_attribute:"piece"
      ~mode:Attribute_ops.Enumerate_piece_elements
      ~owner:Attribute.Point ~name:"local" source |> get_ok)
    geometry_output;
  measure ~input_points:count "enumerate_pieces_int4093" (fun () ->
    Attribute_ops.enumerate ~grain ~piece_attribute:"piece"
      ~mode:Attribute_ops.Enumerate_pieces
      ~owner:Attribute.Point ~name:"class" source |> get_ok)
    geometry_output;
  measure ~input_points:count "enumerate_piece_elements_text4093" (fun () ->
    Attribute_ops.enumerate ~grain ~piece_attribute:"text_piece"
      ~mode:Attribute_ops.Enumerate_piece_elements
      ~owner:Attribute.Point ~name:"local" source |> get_ok)
    geometry_output

let run_motion_benchmarks () =
  let count = (columns + 1) * (rows + 1) in
  let topology = Topology.empty ~point_count:count in
  let make_positions offset = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init count (fun point -> float_of_int point *. 0.0001 +. offset))
      ~y:(Array.init count (fun point ->
        sin (float_of_int point *. 0.0003) +. (offset *. 2.)))
      ~z:(Array.init count (fun point ->
        cos (float_of_int point *. 0.0002) -. offset)) in
  let previous = Geometry.create ~positions:(make_positions 0.) ~topology ()
      |> get_ok
  and current = Geometry.create ~positions:(make_positions 0.125) ~topology ()
      |> get_ok in
  let reference () =
    let before = Packed.Float3.Private.view (Geometry.positions previous)
    and now = Packed.Float3.Private.view (Geometry.positions current) in
    let inverse = 60. in
    let x = Array.init count (fun point ->
        (now.x.(point) -. before.x.(point)) *. inverse)
    and y = Array.init count (fun point ->
        (now.y.(point) -. before.y.(point)) *. inverse)
    and z = Array.init count (fun point ->
        (now.z.(point) -. before.z.(point)) *. inverse) in
    let values = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
    let attribute = Attribute.create_owned ~owner:Attribute.Point ~name:"v"
        (Attribute.Float3 values) |> get_ok in
    Geometry.with_attribute attribute current |> get_ok in
  measure ~input_points:count "motion_velocity_reference" reference geometry_output;
  measure ~input_points:count "motion_velocity_packed" (fun () ->
    Motion.point_velocity ~grain ~previous ~dt:(1. /. 60.) current |> get_ok)
    geometry_output;
  let ids = Attribute.create_owned ~owner:Attribute.Point ~name:"id"
      (Attribute.Int (Array.init count Fun.id)) |> get_ok in
  let previous_by_id = Geometry.with_attribute ids previous |> get_ok
  and current_by_id = Geometry.with_attribute ids current |> get_ok in
  measure ~input_points:count "motion_velocity_id_match" (fun () ->
    Motion.point_velocity ~grain ~previous:previous_by_id ~match_attribute:"id"
      ~dt:(1. /. 60.) current_by_id |> get_ok) geometry_output;
  measure ~input_points:count "motion_rest_store_shared" (fun () ->
    Motion.rest_position Motion.Store_rest current |> get_ok) geometry_output

let run_dissolve_benchmarks () =
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_quads
      ~columns ~rows ~size:100. () |> get_ok in
  let topology = Geometry.topology source
  and index = Topology_index.create (Geometry.topology source) in
  let interior = Edge_group.init ~grain ~topology ~index ~name:"interior"
      (fun edge -> Topology_index.edge_incidence_count index edge = 2) in
  let input_points = Geometry.point_count source in
  measure ~input_points "dissolve_grid_boundary" (fun () ->
    Ops.dissolve ~grain ~edges:interior ~remove_unused_points:false
      ~recompute_normals:false source |> get_ok) geometry_output;
  measure ~input_points "dissolve_grid_rectangle" (fun () ->
    Ops.dissolve ~grain ~edges:interior ~remove_inline_points:true
      ~collinearity_tolerance:1e-10 source |> get_ok) geometry_output

let run_poly_loft_benchmarks () =
  let sections = rows + 1 and per_section = max 3 columns in
  let point_count = sections * per_section in
  let ring_x = Array.init per_section (fun local ->
      cos (2. *. Float.pi *. float_of_int local /. float_of_int per_section))
  and ring_z = Array.init per_section (fun local ->
      sin (2. *. Float.pi *. float_of_int local /. float_of_int per_section)) in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for section = 0 to sections - 1 do
    let radius = 1. +. (0.08 *. sin (float_of_int section *. 0.017)) in
    for local = 0 to per_section - 1 do
      let point = (section * per_section) + local in
      x.(point) <- radius *. ring_x.(local);
      y.(point) <- float_of_int section *. 0.0025;
      z.(point) <- radius *. ring_z.(local)
    done
  done;
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (sections + 1)
        (fun section -> section * per_section))
      ~primitive_kinds:(Array.make sections Topology.Closed_polyline) |> get_ok in
  let source = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z) ~topology ()
      |> get_ok in
  measure ~input_points:point_count "poly_loft_authored_two_point" (fun () ->
    Ops.poly_loft ~grain ~connect_closest_ends:false
      ~output_group:"loft" source |> get_ok) geometry_output;
  measure ~input_points:point_count "poly_loft_authored_three_point" (fun () ->
    Ops.poly_loft ~grain ~connect_closest_ends:false
      ~minimize:Ops.Three_point_distance ~output_group:"loft" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "poly_loft_closest_three_point" (fun () ->
    Ops.poly_loft ~grain ~minimize:Ops.Three_point_distance
      ~output_group:"loft" source |> get_ok) geometry_output;
  measure ~input_points:point_count "skin_authored_quads" (fun () ->
    Ops.skin ~grain ~connect_closest_ends:false ~output_group:"skin" source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "skin_closest_quads" (fun () ->
    Ops.skin ~grain ~output_group:"skin" source |> get_ok) geometry_output

let bridge_fixture ~pairs ~per_loop =
  let points_per_pair = per_loop * 2
  and point_count = pairs * per_loop * 2
  and primitive_count = pairs * 2 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for pair = 0 to pairs - 1 do
    for side = 0 to 1 do
      for local = 0 to per_loop - 1 do
        let point = (pair * points_per_pair) + (side * per_loop) + local
        and angle = 2. *. Float.pi *. float_of_int local
            /. float_of_int per_loop in
        let radius = 1. +. (float_of_int side *. 0.05) in
        x.(point) <- (float_of_int pair *. 2.5) +. (radius *. cos angle);
        y.(point) <- float_of_int side *. 0.1;
        z.(point) <- radius *. sin angle
      done
    done
  done;
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (primitive_count + 1)
        (fun primitive -> primitive * per_loop))
      ~primitive_kinds:(Array.make primitive_count Topology.Polygon) |> get_ok in
  let geometry = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z) ~topology ()
      |> get_ok in
  let index = Topology_index.create topology in
  let source = Edge_group.init ~grain ~topology ~index ~name:"source"
      (fun edge ->
        let a, _ = Topology_index.edge_points index edge in
        (a mod points_per_pair) < per_loop)
  and destination = Edge_group.init ~grain ~topology ~index ~name:"destination"
      (fun edge ->
        let a, _ = Topology_index.edge_points index edge in
        (a mod points_per_pair) >= per_loop) in
  geometry, source, destination

let run_poly_bridge_benchmarks () =
  let total_target = max 12 (columns * rows) in
  let single_per_loop = max 3 (total_target / 2) in
  let single, single_source, single_destination =
    bridge_fixture ~pairs:1 ~per_loop:single_per_loop in
  let single_points = Geometry.point_count single in
  measure ~input_points:single_points "poly_bridge_single_authored" (fun () ->
    Ops.poly_bridge ~grain ~source:single_source ~destination:single_destination
      ~connect_closest_ends:false ~output_group:"bridge" single |> get_ok)
    geometry_output;
  measure ~input_points:single_points "poly_bridge_single_divided" (fun () ->
    Ops.poly_bridge ~grain ~source:single_source ~destination:single_destination
      ~connect_closest_ends:false ~divisions:2 ~output_group:"bridge" single
      |> get_ok) geometry_output;
  let pairs = max 1 rows and per_loop = max 3 (columns / 2) in
  let many, many_source, many_destination = bridge_fixture ~pairs ~per_loop in
  let many_points = Geometry.point_count many in
  measure ~input_points:many_points "poly_bridge_many_authored" (fun () ->
    Ops.poly_bridge ~grain ~source:many_source ~destination:many_destination
      ~connect_closest_ends:false ~output_group:"bridge" many |> get_ok)
    geometry_output;
  measure ~input_points:many_points "poly_bridge_many_divided" (fun () ->
    Ops.poly_bridge ~grain ~source:many_source ~destination:many_destination
      ~connect_closest_ends:false ~divisions:2 ~output_group:"bridge" many
      |> get_ok) geometry_output;
  let many_payload = many
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Point
          ~name:"weight" (Attribute.Float (Array.init many_points (fun point ->
            float_of_int (point mod (per_loop * 2)) /. float_of_int per_loop)))
          |> get_ok) |> get_ok
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Vertex
          ~name:"corner_weight" (Attribute.Float
            (Array.init (Geometry.vertex_count many) (fun vertex ->
              float_of_int (vertex mod per_loop) /. float_of_int per_loop)))
          |> get_ok) |> get_ok
      |> Geometry.with_group (Group.init ~grain ~owner:Group.Point
          ~name:"source_points" many_points (fun point ->
            point mod (per_loop * 2) < per_loop)) |> get_ok in
  measure ~input_points:many_points "poly_bridge_many_divided_payload" (fun () ->
    Ops.poly_bridge ~grain ~source:many_source ~destination:many_destination
      ~connect_closest_ends:false ~divisions:2 ~output_group:"bridge"
      many_payload |> get_ok) geometry_output;
  measure ~input_points:many_points "poly_bridge_many_centroid" (fun () ->
    Ops.poly_bridge ~grain ~source:many_source ~destination:many_destination
      ~pairing:Ops.Bridge_by_centroid ~connect_closest_ends:false
      ~output_group:"bridge" many |> get_ok) geometry_output

let run_attribute_lifecycle_benchmarks () =
  let attributes = Array.init attribute_count (fun index ->
      let prefix = if index land 1 = 0 then "temporary" else "keep" in
      let owner = match index land 3 with
        | 0 -> Attribute.Point
        | 1 -> Attribute.Vertex
        | 2 -> Attribute.Primitive
        | _ -> Attribute.Detail in
      Attribute.create_owned
        ~name:(Printf.sprintf "%s_%06d" prefix index)
        ~owner
        (Attribute.Float (match owner with
          | Attribute.Point | Attribute.Detail -> [|float_of_int index|]
          | Attribute.Vertex | Attribute.Primitive -> [||])) |> get_ok) in
  let source = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:[|0.|] ~y:[|0.|] ~z:[|0.|])
      ~topology:(Topology.empty ~point_count:1)
      ~attributes:(Array.to_list attributes) () |> get_ok in
  measure ~input_points:attribute_count "attribute_lifecycle_exact_rename"
    (fun () ->
      Array.fold_left (fun geometry attribute ->
        let name = Attribute.name attribute in
        if String.starts_with ~prefix:"temporary_" name then
          Geometry.rename_attribute ~owner:(Attribute.owner attribute) ~from:name
            ~into:("final_" ^ String.sub name 10 (String.length name - 10))
            geometry |> get_ok
        else geometry) source attributes)
    attribute_metadata_set_output;
  measure ~input_points:attribute_count "attribute_lifecycle_exact_delete"
    (fun () ->
      Array.fold_left (fun geometry attribute ->
        let name = Attribute.name attribute in
        if String.starts_with ~prefix:"temporary_" name then
          Geometry.without_attribute ~owner:(Attribute.owner attribute) name geometry
        else geometry) source attributes)
    attribute_metadata_output;
  measure ~input_points:attribute_count "attribute_lifecycle_exact_copy"
    (fun () ->
      Array.fold_left (fun geometry attribute ->
        let name = Attribute.name attribute in
        if String.starts_with ~prefix:"temporary_" name then
          let copy = Attribute.with_name
              ("copy_" ^ String.sub name 10 (String.length name - 10))
              attribute |> get_ok in
          Geometry.with_attribute copy geometry |> get_ok
        else geometry) source attributes)
    attribute_metadata_set_output;
  measure ~input_points:attribute_count "attribute_lifecycle_batch_rename"
    (fun () -> Attribute_ops.rename ~rules:[{
      rename_attribute_owner = None;
      rename_attribute_pattern = "temporary_*";
      rename_attribute_replacement = "final_*";
      rename_attribute_conflict = Attribute_ops.Attribute_rename_error;
    }] source |> get_ok)
    attribute_metadata_set_output;
  measure ~input_points:attribute_count "attribute_lifecycle_batch_delete"
    (fun () -> Attribute_ops.delete ~point_pattern:"temporary_*"
      ~vertex_pattern:"temporary_*" ~primitive_pattern:"temporary_*"
      ~detail_pattern:"temporary_*" source |> get_ok)
    attribute_metadata_output;
  let copy_rule owner = {
    Attribute_ops.swap_attribute_owner = owner;
    swap_attribute_source = "temporary_*";
    swap_attribute_destination = "copy_*";
    swap_attribute_method = Attribute_ops.Attribute_copy;
  } in
  measure ~input_points:attribute_count "attribute_lifecycle_batch_swap_copy"
    (fun () -> Attribute_ops.swap ~rules:[
      copy_rule Attribute.Point; copy_rule Attribute.Vertex;
      copy_rule Attribute.Primitive; copy_rule Attribute.Detail]
      source |> get_ok)
    attribute_metadata_set_output

let run_promote_pattern_benchmarks () =
  let source = Ops.grid ~columns:400 ~rows:400 ~size:20. () |> get_ok in
  let count = Geometry.point_count source in
  let names = [|"bench_a"; "bench_b"; "bench_c"; "bench_d"|] in
  let source = Array.fold_left (fun geometry name ->
      let attribute = Attribute.create_owned ~name ~owner:Attribute.Point
          (Attribute.Float (Array.init count (fun point ->
            float_of_int ((point * 31) mod 997) /. 996.))) |> get_ok in
      Geometry.with_attribute attribute geometry |> get_ok) source names in
  let tuple = Attribute.create_owned ~name:"tuple_value"
      ~owner:Attribute.Point (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.init count (fun point -> float_of_int ((point * 3) mod 997)))
        ~y:(Array.init count (fun point -> float_of_int ((point * 5) mod 991)))
        ~z:(Array.init count (fun point -> float_of_int ((point * 7) mod 983)))
        ~w:(Array.init count (fun point -> float_of_int ((point * 11) mod 977)))
        |> get_ok)) |> get_ok
  and label = Attribute.create_owned ~name:"text_value"
      ~owner:Attribute.Point (Attribute.Text (Array.init count (fun point ->
        String.make 1 (Char.chr (Char.code 'a' + (point mod 26)))))) |> get_ok in
  let source = source |> Geometry.with_attribute tuple |> get_ok
      |> Geometry.with_attribute label |> get_ok in
  let piece = Attribute.create_owned ~name:"bench_piece"
      ~owner:Attribute.Primitive
      (Attribute.Int (Array.init (Geometry.primitive_count source)
        (fun primitive -> primitive / 64))) |> get_ok in
  let source = Geometry.with_attribute piece source |> get_ok in
  measure ~input_points:count "attribute_promote_pattern4_shared" (fun () ->
    Attribute_ops.promote_pattern ~grain ~method_:Attribute_ops.Average
      ~delete_source:false ~source:Attribute.Point
      ~destination:Attribute.Primitive ~piece_attribute:"bench_piece"
      ~pattern:"bench_*" ~into_pattern:"promoted_*" source |> get_ok)
    geometry_output;
  measure ~input_points:count "attribute_promote_pattern4_max_shared" (fun () ->
    Attribute_ops.promote_pattern ~grain ~method_:Attribute_ops.Maximum
      ~delete_source:false ~source:Attribute.Point
      ~destination:Attribute.Primitive ~piece_attribute:"bench_piece"
      ~pattern:"bench_*" ~into_pattern:"promoted_*" source |> get_ok)
    geometry_output;
  measure ~input_points:count "attribute_promote_pattern4_indexed_shared"
    (fun () ->
      Attribute_ops.promote_pattern ~grain ~method_:Attribute_ops.Maximum
        ~delete_source:false ~source:Attribute.Point
        ~destination:Attribute.Primitive ~piece_attribute:"bench_piece"
        ~pattern:"bench_*" ~into_pattern:"promoted_*"
        ~index_pattern:"source_*" source |> get_ok)
    geometry_output;
  measure ~input_points:count "attribute_promote_pattern_tuple4_indexed_shared"
    (fun () ->
      Attribute_ops.promote ~grain ~method_:Attribute_ops.Maximum
        ~delete_source:false ~source:Attribute.Point
        ~destination:Attribute.Primitive ~piece_attribute:"bench_piece"
        ~name:"tuple_value" ~into:"promoted_tuple"
        ~index_attribute:"tuple_sources" source |> get_ok)
    geometry_output;
  measure ~input_points:count "attribute_promote_pattern_text_sum" (fun () ->
    Attribute_ops.promote ~grain ~method_:Attribute_ops.Sum
      ~delete_source:false ~source:Attribute.Point
      ~destination:Attribute.Primitive ~name:"text_value"
      ~into:"promoted_label" source |> get_ok)
    geometry_output;
  measure ~input_points:count "attribute_promote_pattern4_array_all" (fun () ->
    Attribute_ops.promote_pattern ~grain ~method_:Attribute_ops.Array_all
      ~delete_source:false ~source:Attribute.Point
      ~destination:Attribute.Primitive ~pattern:"bench_*"
      ~into_pattern:"promoted_*" source |> get_ok)
    geometry_output;
  measure ~input_points:count "attribute_promote_pattern4_unique_values" (fun () ->
    Attribute_ops.promote_pattern ~grain ~method_:Attribute_ops.Unique_values
      ~delete_source:false ~source:Attribute.Point
      ~destination:Attribute.Primitive ~pattern:"bench_*"
      ~into_pattern:"promoted_*" source |> get_ok)
    geometry_output;
  measure ~input_points:count "attribute_promote_pattern4_repeated_baseline"
    (fun () -> Array.fold_left (fun geometry name ->
      Attribute_ops.promote ~grain ~method_:Attribute_ops.Average
        ~delete_source:false ~source:Attribute.Point
        ~destination:Attribute.Primitive ~piece_attribute:"bench_piece"
        ~name ~into:("promoted_" ^ String.sub name 6 (String.length name - 6))
        geometry |> get_ok) source names)
    geometry_output;
  measure ~input_points:count
    "attribute_promote_pattern4_indexed_repeated_baseline"
    (fun () -> Array.fold_left (fun geometry name ->
      let suffix = String.sub name 6 (String.length name - 6) in
      Attribute_ops.promote ~grain ~method_:Attribute_ops.Maximum
        ~delete_source:false ~source:Attribute.Point
        ~destination:Attribute.Primitive ~piece_attribute:"bench_piece"
        ~name ~into:("promoted_" ^ suffix)
        ~index_attribute:("source_" ^ suffix) geometry |> get_ok) source names)
    geometry_output

let legacy_measure_area_baseline geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry) in
  let values = Array.make (Geometry.primitive_count geometry) 0. in
  for primitive = 0 to Geometry.primitive_count geometry - 1 do
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1) in
    if last - first >= 3 then begin
      let point_a = topology.vertex_points.(first) in
      let ax = positions.x.(point_a) and ay = positions.y.(point_a)
      and az = positions.z.(point_a) in
      let area = ref 0. in
      for vertex = first + 1 to last - 2 do
        let point_b = topology.vertex_points.(vertex)
        and point_c = topology.vertex_points.(vertex + 1) in
        let abx = positions.x.(point_b) -. ax
        and aby = positions.y.(point_b) -. ay
        and abz = positions.z.(point_b) -. az
        and acx = positions.x.(point_c) -. ax
        and acy = positions.y.(point_c) -. ay
        and acz = positions.z.(point_c) -. az in
        let nx = (aby *. acz) -. (abz *. acy)
        and ny = (abz *. acx) -. (abx *. acz)
        and nz = (abx *. acy) -. (aby *. acx) in
        area := !area +. (0.5 *. sqrt ((nx *. nx) +. (ny *. ny) +. (nz *. nz)))
      done;
      values.(primitive) <- !area
    end
  done;
  let attribute = Attribute.create_owned ~name:"area"
      ~owner:Attribute.Primitive (Attribute.Float values) |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let run_measure_benchmarks () =
  let source = Ops.grid ~columns:400 ~rows:400 ~size:20. () |> get_ok in
  let input_points = Geometry.point_count source in
  measure ~input_points "measure_area_legacy_fan_baseline" (fun () ->
    legacy_measure_area_baseline source) geometry_output;
  measure ~input_points "measure_area_packed" (fun () ->
    Analysis.with_measure ~grain Analysis.Area source
    |> get_ok) geometry_output;
  measure ~input_points "measure_area_packed_with_total" (fun () ->
    Analysis.with_measure ~grain ~total_name:"surface_area" Analysis.Area source
    |> get_ok) geometry_output;
  measure ~input_points "measure_perimeter_packed" (fun () ->
    Analysis.with_measure ~grain ~total_name:"perimeter" Analysis.Perimeter source
    |> get_ok) geometry_output;
  let boxes = Ops.box ~size:(Vec3.create 2. 3. 4.) () |> get_ok
      |> Ops.duplicate ~grain ~copies:20_000
           ~transform:(Mat4.translation (Vec3.create 3. 0. 0.)) |> get_ok in
  measure ~input_points:(Geometry.point_count boxes) "measure_volume_packed"
    (fun () -> Analysis.with_measure ~grain ~total_name:"signed_volume"
      Analysis.Signed_volume boxes |> get_ok) geometry_output

let legacy_connectivity_baseline geometry =
  let topology = Topology.Private.view (Geometry.topology geometry) in
  let primitive_count = Geometry.primitive_count geometry in
  let parent = Array.init primitive_count Fun.id in
  let rec root primitive =
    if parent.(primitive) = primitive then primitive
    else begin
      parent.(primitive) <- root parent.(primitive);
      parent.(primitive)
    end
  in
  let union left right =
    let left = root left and right = root right in
    if left <> right then parent.(right) <- left
  in
  let first_primitive = Array.make (Geometry.point_count geometry) (-1) in
  for primitive = 0 to primitive_count - 1 do
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1) in
    for vertex = first to last - 1 do
      let point = topology.vertex_points.(vertex) in
      let previous = first_primitive.(point) in
      if previous < 0 then first_primitive.(point) <- primitive
      else union primitive previous
    done
  done;
  let root_to_class = Hashtbl.create primitive_count in
  let next_class = ref 0 in
  let classes = Array.init primitive_count (fun primitive ->
    let representative = root primitive in
    match Hashtbl.find_opt root_to_class representative with
    | Some class_id -> class_id
    | None ->
        let class_id = !next_class in
        incr next_class;
        Hashtbl.add root_to_class representative class_id;
        class_id)
  in
  let attribute = Attribute.create_owned ~name:"class"
      ~owner:Attribute.Primitive (Attribute.Int classes) |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let run_connectivity_benchmarks () =
  let source = Ops.grid ~columns:500 ~rows:500 ~size:20. () |> get_ok in
  let input_points = Geometry.point_count source in
  measure ~input_points "connectivity_legacy_primitives" (fun () ->
    legacy_connectivity_baseline source) geometry_output;
  measure ~input_points "connectivity_primitives" (fun () ->
    Analysis.with_connectivity ~grain source |> get_ok) geometry_output;
  measure ~input_points "connectivity_points_text" (fun () ->
    Analysis.with_connectivity ~grain ~owner:Analysis.Connectivity_points
      ~attribute:(Analysis.Connectivity_text "piece_") source |> get_ok)
    geometry_output;
  let topology = Geometry.topology source in
  let index = Topology_index.create topology in
  let seams = Edge_group.init ~grain ~topology ~index ~name:"periodic_seams"
      (fun edge -> edge mod 97 = 0) in
  measure ~input_points "connectivity_primitives_seams" (fun () ->
    Analysis.with_connectivity ~grain ~seams source |> get_ok) geometry_output;
  let topology_view = Topology.Private.view topology in
  let positions = Packed.Float3.Private.view (Geometry.positions source) in
  let uv = Packed.Float2.of_owned
      ~x:(Array.init (Geometry.vertex_count source) (fun vertex ->
        positions.x.(topology_view.vertex_points.(vertex))))
      ~y:(Array.init (Geometry.vertex_count source) (fun vertex ->
        positions.z.(topology_view.vertex_points.(vertex)))) |> get_ok in
  let uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 uv) |> get_ok in
  let source_uv = Geometry.with_attribute uv source |> get_ok in
  measure ~input_points "connectivity_primitives_uv" (fun () ->
    Analysis.with_connectivity ~grain ~uv_attribute:"uv" source_uv |> get_ok)
    geometry_output

let run_attribute_blur_benchmarks () =
  let source = Ops.grid ~columns:400 ~rows:400 ~size:20. () |> get_ok
      |> Ops.noise_displace ~grain ~amplitude:0.8 ~frequency:0.35 ~seed:91
           |> get_ok
      |> Ops.color_by_height ~grain ~low:low_color ~high:high_color |> get_ok in
  let point_count = Geometry.point_count source in
  let weight = Attribute.create_owned ~name:"blur_weight"
      ~owner:Attribute.Point (Attribute.Float (Array.init point_count
        (fun point -> 0.5 +. (float_of_int (point mod 101) /. 200.)))) |> get_ok
  and alpha = Attribute.create_owned ~name:"blur_alpha"
      ~owner:Attribute.Point (Attribute.Float (Array.init point_count
        (fun point -> 0.75 +. (float_of_int (point mod 17) /. 68.)))) |> get_ok in
  let source = source |> Geometry.with_attribute weight |> get_ok
      |> Geometry.with_attribute alpha |> get_ok in
  measure ~input_points:point_count "attribute_blur_uniform_p_cd" (fun () ->
    Attribute_ops.blur_points ~grain ~iterations:8
      ~mode:(Attribute_ops.Laplacian 0.35) ~pin_borders:true
      ~pattern:"P Cd" source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_blur_edge_controls_p_cd"
    (fun () -> Attribute_ops.blur_points ~grain ~iterations:8
      ~method_:Attribute_ops.Edge_length
      ~mode:(Attribute_ops.Custom_steps { odd = 0.42; even = -0.44 })
      ~weight_attribute:"blur_weight" ~alpha_attribute:"blur_alpha"
      ~pin_borders:true ~pattern:"P Cd" source |> get_ok) geometry_output

let run_smooth_benchmarks () =
  let source = Ops.grid ~columns:400 ~rows:400 ~size:20. () |> get_ok
      |> Ops.noise_displace ~grain ~amplitude:0.8 ~frequency:0.35 ~seed:91
           |> get_ok
      |> Ops.color_by_height ~grain ~low:low_color ~high:high_color |> get_ok in
  let point_count = Geometry.point_count source
  and primitive_count = Geometry.primitive_count source in
  let primitives = Group.init ~grain ~owner:Group.Primitive ~name:"smooth_faces"
      primitive_count (fun primitive -> primitive mod 19 <> 0)
  and constrained = Group.init ~grain ~owner:Group.Point ~name:"smooth_locks"
      point_count (fun point -> point mod 1009 = 0) in
  measure ~input_points:point_count "smooth_group_boundary_p_cd" (fun () ->
    Ops.smooth ~grain ~primitives ~constrained_points:constrained
      ~boundary:Ops.Smooth_group_boundary ~iterations:8
      ~method_:Attribute_ops.Edge_length
      ~mode:(Attribute_ops.Custom_steps { odd = 0.42; even = -0.44 })
      ~attributes:"P Cd" source |> get_ok) geometry_output

let run_ray_benchmarks () =
  let columns = 500 and rows = 400 in
  let collision = Ops.grid ~columns ~rows ~size:40. () |> get_ok
      |> Ops.noise_displace ~grain ~amplitude:0.8 ~frequency:0.18 ~seed:903
           |> get_ok
      |> Ops.color_by_height ~grain ~low:low_color ~high:high_color |> get_ok in
  let source = Ops.grid ~columns ~rows ~size:39.5 () |> get_ok
      |> Ops.transform ~grain (Mat4.translation (Vec3.create 0. 2. 0.)) in
  let point_count = Geometry.point_count source in
  measure ~input_points:point_count "ray_project_vector" (fun () ->
    Ops.ray ~grain ~direction:(Ops.Ray_vector (Vec3.create 0. (-1.) 0.))
      ~distance_attribute:"ray_distance" ~source ~collision () |> get_ok)
    geometry_output;
  measure ~input_points:point_count "ray_project_provenance_cd" (fun () ->
    Ops.ray ~grain ~direction:(Ops.Ray_vector (Vec3.create 0. (-1.) 0.))
      ~distance_attribute:"ray_distance" ~primitive_attribute:"source_primitive"
      ~source_vertex_numbers_attribute:"source_vertices"
      ~source_vertex_weights_attribute:"source_weights"
      ~normal_attribute:"hit_N" ~hit_group:"ray_hits" ~point_pattern:"Cd"
      ~source ~collision () |> get_ok) geometry_output;
  measure ~input_points:point_count "ray_multisample_position_average_8" (fun () ->
    Ops.ray ~grain ~samples:8 ~jitter_scale:0.08 ~seed:2903
      ~combine:Ops.Ray_average
      ~direction:(Ops.Ray_vector (Vec3.create 0. (-1.) 0.))
      ~distance_attribute:"ray_distance" ~normal_attribute:"hit_N"
      ~source ~collision () |> get_ok) geometry_output;
  measure ~input_points:point_count "ray_multisample_position_median_8" (fun () ->
    Ops.ray ~grain ~samples:8 ~jitter_scale:0.08 ~seed:2903
      ~combine:Ops.Ray_median
      ~direction:(Ops.Ray_vector (Vec3.create 0. (-1.) 0.))
      ~distance_attribute:"ray_distance" ~normal_attribute:"hit_N"
      ~source ~collision () |> get_ok) geometry_output;
  measure ~input_points:point_count "ray_multisample_provenance_average_8_cd"
    (fun () ->
      Ops.ray ~grain ~samples:8 ~jitter_scale:0.08 ~seed:2903
        ~combine:Ops.Ray_average
        ~direction:(Ops.Ray_vector (Vec3.create 0. (-1.) 0.))
        ~distance_attribute:"ray_distance" ~primitive_attribute:"source_primitive"
        ~source_vertex_numbers_attribute:"source_vertices"
        ~source_vertex_weights_attribute:"source_weights"
        ~normal_attribute:"hit_N" ~hit_group:"ray_hits" ~point_pattern:"Cd"
        ~source ~collision () |> get_ok) geometry_output

let run_fuse_benchmarks () =
  let source = make_grid ()
      |> Ops.noise_displace ~grain ~amplitude:0.37 ~frequency:0.29 ~seed:907
           |> get_ok in
  let point_count = Geometry.point_count source in
  let selection = Group.init ~grain ~owner:Group.Point ~name:"snap_points"
      point_count (fun point -> point land 1 = 0) in
  measure ~input_points:point_count "snap_to_grid_all" (fun () ->
    Ops.snap_to_grid ~grain ~spacing:(Vec3.create 0.03125 0.03125 0.03125)
      ~offset:(Vec3.create 0.25 0.5 0.75) ~snapped_group:"snapped" source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "snap_to_grid_half_group" (fun () ->
    Ops.snap_to_grid ~grain ~selection
      ~spacing:(Vec3.create 0.03125 0.03125 0.03125)
      ~offset:(Vec3.create 0.25 0.5 0.75) ~snapped_group:"snapped" source
      |> get_ok) geometry_output;
  let duplicate = Ops.grid ~columns:400 ~rows:400 ~size:20. () |> get_ok in
  let duplicate = Ops.merge ~grain [duplicate; duplicate] |> get_ok in
  let duplicate_count = Geometry.point_count duplicate in
  measure ~input_points:duplicate_count "fuse_grid_duplicate_pair" (fun () ->
    Ops.snap_to_grid ~grain ~spacing:(Vec3.create 0.05 0.05 0.05)
      ~fuse_points:true ~snapped_group:"snapped" duplicate |> get_ok)
    geometry_output;
  measure ~input_points:duplicate_count "fuse_exact_duplicate_pair" (fun () ->
    Ops.fuse ~grain ~tolerance:0. duplicate |> get_ok) geometry_output;
  let target = Ops.grid ~columns:500 ~rows:400 ~size:30. () |> get_ok in
  let query = Ops.transform ~grain
      (Mat4.translation (Vec3.create 0.013 (-0.017) 0.009)) target in
  let target_count = Geometry.point_count target in
  measure ~input_points:(target_count * 2) "fuse_target_closest_snap" (fun () ->
    Ops.fuse ~grain ~target ~using:Ops.Closest_target_point ~tolerance:0.05
      ~fuse_points:false ~snapped_group:"snapped"
      ~snapped_destination_attribute:"destination" query |> get_ok)
    geometry_output;
  let add_point_attribute attribute geometry =
    Geometry.with_attribute attribute geometry |> get_ok in
  let target_rules = target
      |> add_point_attribute (Attribute.create_owned ~owner:Attribute.Point
          ~name:"signal" (Attribute.Float (Array.init target_count (fun point ->
            sin (float_of_int point *. 0.013)))) |> get_ok)
      |> add_point_attribute (Attribute.create_owned ~owner:Attribute.Point
          ~name:"catalog" (Attribute.Int (Array.init target_count Fun.id))
          |> get_ok)
      |> add_point_attribute (Attribute.create_owned ~owner:Attribute.Point
          ~name:"weight" (Attribute.Float (Array.make target_count 1.)) |> get_ok)
      |> fun geometry -> Geometry.with_group
          (Group.init ~grain ~owner:Group.Point ~name:"marked" target_count
            (fun point -> point land 1 = 0)) geometry |> get_ok in
  let query_rules = query
      |> add_point_attribute (Attribute.create_owned ~owner:Attribute.Point
          ~name:"signal" (Attribute.Float (Array.make target_count 0.)) |> get_ok)
      |> add_point_attribute (Attribute.create_owned ~owner:Attribute.Point
          ~name:"catalog" (Attribute.Int (Array.make target_count (-1))) |> get_ok) in
  measure ~input_points:(target_count * 2) "fuse_target_attribute_rules" (fun () ->
    Ops.fuse ~grain ~target:target_rules ~using:Ops.Closest_target_point
      ~tolerance:0.05 ~fuse_points:false ~attribute_rules:[
        Ops.fuse_attribute_rule ~pattern:"signal" ~weight_attribute:"weight"
          Ops.Attribute_weighted_average;
        Ops.fuse_attribute_rule ~pattern:"catalog" Ops.Attribute_concatenate]
      ~group_rules:[Ops.fuse_group_rule ~pattern:"marked" Ops.Group_union]
      query_rules |> get_ok) geometry_output;
  let shifted_target = Ops.transform ~grain
      (Mat4.translation (Vec3.create 0.013 (-0.017) 0.009)) target in
  let linked = Ops.merge ~grain [target; shifted_target] |> get_ok in
  let linked_count = Geometry.point_count linked in
  let weight = Attribute.create_owned ~owner:Attribute.Point ~name:"weight"
      (Attribute.Float (Array.init linked_count (fun point ->
        if point < target_count then 1. else 3.))) |> get_ok in
  let linked = Geometry.with_attribute weight linked |> get_ok in
  let queries = Group.init ~grain ~owner:Group.Point ~name:"queries"
      linked_count (fun point -> point < target_count)
  and targets = Group.init ~grain ~owner:Group.Point ~name:"targets"
      linked_count (fun point -> point >= target_count) in
  measure ~input_points:linked_count "fuse_modify_target_weighted_pair"
    (fun () -> Ops.fuse ~grain ~selection:queries ~target_selection:targets
      ~using:Ops.Closest_target_point ~tolerance:0.05 ~modify_target:true
      ~position:Ops.Weighted_average_position ~weight_attribute:"weight"
      linked |> get_ok) geometry_output;
  let ruled = linked
      |> fun geometry -> Geometry.with_attribute
          (Attribute.create_owned ~owner:Attribute.Point ~name:"signal"
            (Attribute.Float (Array.init linked_count (fun point ->
              sin (float_of_int (point mod target_count) *. 0.013)))) |> get_ok)
          geometry |> get_ok
      |> fun geometry -> Geometry.with_attribute
          (Attribute.create_owned ~owner:Attribute.Point ~name:"rank"
            (Attribute.Int (Array.init linked_count (fun point -> point mod 97)))
            |> get_ok) geometry |> get_ok
      |> fun geometry -> Geometry.with_attribute
          (Attribute.create_owned ~owner:Attribute.Point ~name:"label"
            (Attribute.Text (Array.init linked_count (fun point ->
              if point < target_count then "q" else "t"))) |> get_ok)
          geometry |> get_ok
      |> fun geometry -> Geometry.with_group
          (Group.init ~grain ~owner:Group.Point ~name:"marked" linked_count
            (fun point -> point land 1 = 0)) geometry |> get_ok in
  measure ~input_points:linked_count "fuse_modify_target_attribute_rules"
    (fun () -> Ops.fuse ~grain ~selection:queries ~target_selection:targets
      ~using:Ops.Closest_target_point ~tolerance:0.05 ~modify_target:true
      ~attribute_rules:[
        Ops.fuse_attribute_rule ~pattern:"signal" ~weight_attribute:"weight"
          Ops.Attribute_weighted_average;
        Ops.fuse_attribute_rule ~pattern:"rank" Ops.Attribute_mode;
        Ops.fuse_attribute_rule ~pattern:"label" ~weight_attribute:"weight"
          Ops.Attribute_concatenate_weight_order]
      ~group_rules:[Ops.fuse_group_rule ~pattern:"marked"
        Ops.Group_most_common] ruled |> get_ok) geometry_output;
  let cleanup_grid = Ops.grid ~columns:500 ~rows:400 ~size:30. () |> get_ok in
  measure ~input_points:(Geometry.point_count cleanup_grid)
    "fuse_cleanup_grid_pairs" (fun () ->
      Ops.fuse ~grain ~tolerance:0.061 ~remove_degenerate_primitives:true
        ~remove_all_unused_points:true cleanup_grid |> get_ok) geometry_output

let run_bound_benchmarks () =
  let source = make_grid ()
      |> Ops.noise_displace ~grain ~amplitude:2. ~frequency:0.23 ~seed:937
           |> get_ok in
  let point_count = Geometry.point_count source in
  let selection = Group.init ~grain ~owner:Group.Point ~name:"bound_points"
      point_count (fun point -> point land 1 = 0) in
  measure ~input_points:point_count "bound_box_divided" (fun () ->
    Ops.bound ~grain ~shape:(Ops.Bound_box { divisions = 512, 512, 512 })
      ~lower_padding:(Vec3.create 0.25 0.5 0.75)
      ~upper_padding:(Vec3.create 0.75 0.5 0.25)
      ~bounds_group:"bounds" ~center_attribute:"bound_center"
      ~radii_attribute:"bound_radii" source |> get_ok) geometry_output;
  measure ~input_points:point_count "bound_box_half_group" (fun () ->
    Ops.bound ~grain ~selection:(Ops.Selected_points selection)
      ~shape:(Ops.Bound_box { divisions = 256, 128, 64 })
      ~lower_padding:(Vec3.create 0.25 0.5 0.75)
      ~upper_padding:(Vec3.create 0.75 0.5 0.25)
      ~bounds_group:"bounds" source |> get_ok) geometry_output;
  measure ~input_points:point_count "bound_sphere_512x256" (fun () ->
    Ops.bound ~grain ~shape:(Ops.Bound_sphere {
        segments = 512; rings = 256; minimum_radius = 0. })
      ~lower_padding:(Vec3.create 0.25 0.5 0.75)
      ~upper_padding:(Vec3.create 0.75 0.5 0.25)
      ~bounds_group:"bounds" source |> get_ok) geometry_output

let run_match_size_benchmarks () =
  let source = make_grid ()
      |> Ops.noise_displace ~grain ~amplitude:2. ~frequency:0.23 ~seed:941
           |> get_ok
      |> Ops.normals ~grain |> get_ok in
  let point_count = Geometry.point_count source in
  let half = Group.init ~grain ~owner:Group.Point ~name:"match_points"
      point_count (fun point -> point land 1 = 0) in
  let target = Ops.box ~size:(Vec3.create 80. 45. 120.) () |> get_ok
      |> Ops.transform (Mat4.translation (Vec3.create 12. 7. (-5.))) in
  measure ~input_points:point_count "match_size_contain" (fun () ->
    Ops.match_size ~grain ~fit:Ops.Contain ~target source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "match_size_stretch_half" (fun () ->
    Ops.match_size ~grain ~selection:(Ops.Selected_points half)
      ~source_selection:(Ops.Selected_points half) ~fit:Ops.Stretch
      ~scale_axes:(true, false, true)
      ~justify:(Vec3.create (-1.) 0. 1.)
      ~target_justify:(Vec3.create 1. (-1.) 0.)
      ~offset:(Vec3.create 0.25 0.5 (-0.75)) ~target source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "match_size_area" (fun () ->
    Ops.match_size ~grain ~fit:Ops.Match_area ~target source |> get_ok)
    geometry_output

let run_attribute_generate_benchmarks () =
  let source = make_grid () in
  let point_count = Geometry.point_count source in
  let samples = Packed.Float4.of_owned
      ~x:(Array.init point_count (fun point ->
        (float_of_int (point mod 1009) /. 1008.) *. 8. -. 4.))
      ~y:(Array.init point_count (fun point ->
        (float_of_int (point mod 503) /. 502.) *. 4. -. 2.))
      ~z:(Array.init point_count (fun point ->
        float_of_int (point mod 257) /. 256.))
      ~w:(Array.init point_count (fun point ->
        0.25 +. (float_of_int (point mod 127) /. 84.))) |> get_ok in
  let sample_attribute = Attribute.create_owned ~name:"sample"
      ~owner:Attribute.Point (Attribute.Float4 samples) |> get_ok
  and seed_attribute = Attribute.create_owned ~name:"seed_id"
      ~owner:Attribute.Point (Attribute.Int (Array.init point_count (fun point ->
        (point * 65_537) lxor (point lsr 5)))) |> get_ok in
  let fractions = Packed.Float4.of_owned
      ~x:(Array.init point_count (fun point ->
        float_of_int (point mod 1009) /. 1009.))
      ~y:(Array.init point_count (fun point ->
        float_of_int (point mod 1013) /. 1013.))
      ~z:(Array.init point_count (fun point ->
        float_of_int (point mod 1019) /. 1019.))
      ~w:(Array.init point_count (fun point ->
        float_of_int (point mod 1021) /. 1021.)) |> get_ok in
  let fraction_attribute = Attribute.create_owned ~name:"fractions"
      ~owner:Attribute.Point (Attribute.Float4 fractions) |> get_ok in
  let populated = source |> Geometry.with_attribute sample_attribute |> get_ok
      |> Geometry.with_attribute seed_attribute |> get_ok in
  let quantile_source = populated |> Geometry.with_attribute fraction_attribute
      |> get_ok in
  let sparse_points = Group.init ~grain ~owner:Group.Point
      ~name:"randomize_sparse_points" point_count
      (fun point -> point mod 7 = 0) in
  measure ~input_points:point_count "attribute_randomize_uniform4" (fun () ->
    Attribute_ops.randomize ~grain ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~owner:Attribute.Point ~name:"generated"
      (Attribute_ops.Random_uniform {
        min = Attribute_ops.Vec4 (-2., -1., 0., 1.);
        max = Attribute_ops.Vec4 (2., 1., 4., 3.);
      }) source |> get_ok) geometry_output;
  measure ~input_points:point_count
    "attribute_randomize_normal4_seed_add" (fun () ->
      Attribute_ops.randomize ~grain ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
        ~seed_attribute:"seed_id" ~operation:Attribute_ops.Random_add ~scale:0.25
        ~owner:Attribute.Point ~name:"sample"
        (Attribute_ops.Random_normal {
          middle = Attribute_ops.Vec4 (0., 0., 0., 0.);
          scale = Attribute_ops.Vec4 (1., 1., 1., 1.);
        }) populated |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_direction4" (fun () ->
    Attribute_ops.randomize ~grain ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~owner:Attribute.Point ~name:"orient"
      (Attribute_ops.Random_direction {
        direction = Attribute_ops.Vec4 (0., 0., 0., 1.);
        cone_angle = 2. *. Float.pi;
      }) source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_direction3_cone"
    (fun () -> Attribute_ops.randomize ~grain
      ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~owner:Attribute.Point ~name:"direction"
      (Attribute_ops.Random_direction {
        direction = Attribute_ops.Vec3 Vec3.unit_y;
        cone_angle = Float.pi /. 3.;
      }) source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_sphere3" (fun () ->
    Attribute_ops.randomize ~grain ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~owner:Attribute.Point ~name:"offset"
      (Attribute_ops.Random_inside_sphere { dimensions = 3 }) source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "attribute_randomize_sphere3_cone_bias"
    (fun () -> Attribute_ops.randomize ~grain
      ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL) ~direction_bias:1.5
      ~owner:Attribute.Point ~name:"cone_offset"
      (Attribute_ops.Random_inside_sphere_cone {
        direction = Attribute_ops.Vec3 Vec3.unit_y;
        cone_angle = Float.pi /. 2.;
      }) source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_custom_discrete4"
    (fun () -> Attribute_ops.randomize ~grain
      ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~owner:Attribute.Point ~name:"choice"
      (Attribute_ops.Random_custom_discrete [
        Attribute_ops.Vec4 (1., 0., 0., 1.), 1.;
        Attribute_ops.Vec4 (0., 1., 0., 1.), 4.;
        Attribute_ops.Vec4 (0., 0., 1., 1.), 2.;
        Attribute_ops.Vec4 (1., 1., 1., 1.), 0.5;
      ]) source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_cauchy2_bounded"
    (fun () -> Attribute_ops.randomize ~grain
      ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~minimum:(Attribute_ops.Vec2 (Vec2.create (-25.) (-25.)))
      ~maximum:(Attribute_ops.Vec2 (Vec2.create 25. 25.))
      ~owner:Attribute.Point ~name:"cauchy"
      (Attribute_ops.Random_cauchy {
        median = Attribute_ops.Vec2 Vec2.zero;
        scale = Attribute_ops.Vec2 (Vec2.create 1. 1.);
      }) source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_text_discrete"
    (fun () -> Attribute_ops.randomize ~grain
      ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~owner:Attribute.Primitive ~name:"label"
      (Attribute_ops.Random_custom_discrete_text [
        "low", 1.; "medium", 3.; "high", 2.;
      ]) source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_point_to_vertex_group"
    (fun () -> Attribute_ops.randomize ~grain
      ~element_selection:(Attribute_ops.Random_points sparse_points)
      ~seed:(Rand.seed64 0x5eed_1234_9876_abcdL)
      ~owner:Attribute.Vertex ~name:"selected"
      (Attribute_ops.Random_constant (Attribute_ops.Scalar 1.)) source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_normal4_bounded_fraction"
    (fun () -> Attribute_ops.randomize ~grain ~fraction_attribute:"fractions"
      ~minimum:(Attribute_ops.Vec4 (-2., -2., -2., -2.))
      ~maximum:(Attribute_ops.Vec4 (2., 2., 2., 2.))
      ~seed:(Rand.seed 0) ~owner:Attribute.Point ~name:"bounded_normal"
      (Attribute_ops.Random_normal {
        middle = Attribute_ops.Vec4 (0., 0., 0., 0.);
        scale = Attribute_ops.Vec4 (1., 1., 1., 1.);
      }) quantile_source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_randomize_fraction_ramp4"
    (fun () -> Attribute_ops.randomize ~grain ~fraction_attribute:"fractions"
      ~seed:(Rand.seed 0) ~owner:Attribute.Point ~name:"quantiles"
      (Attribute_ops.Random_custom_ramp {
        ramp = [0., 0.; 0.2, 0.04; 0.65, 0.88; 1., 1.];
        fit_min = Attribute_ops.Vec4 (-1., 0., 2., 10.);
        fit_max = Attribute_ops.Vec4 (1., 1., 6., 20.);
      }) quantile_source |> get_ok) geometry_output;
  measure ~input_points:point_count "attribute_remap_explicit4" (fun () ->
    Attribute_ops.remap ~grain ~owner:Attribute.Point ~name:"sample"
      ~into:"mapped"
      ~input:(Attribute_ops.Remap_explicit {
        min = Attribute_ops.Vec4 (-4., -2., 0., 0.25);
        max = Attribute_ops.Vec4 (4., 2., 1., 1.75);
      }) ~output_min:(Attribute_ops.Vec4 (0., 0., 0., 0.))
      ~output_max:(Attribute_ops.Vec4 (1., 1., 1., 1.)) populated |> get_ok)
    geometry_output;
  measure ~input_points:point_count "attribute_remap_auto4_ramp" (fun () ->
    Attribute_ops.remap ~grain ~owner:Attribute.Point ~name:"sample"
      ~into:"mapped" ~input:Attribute_ops.Remap_auto
      ~output_min:(Attribute_ops.Vec4 (0., 0., 0., 0.))
      ~output_max:(Attribute_ops.Vec4 (1., 1., 1., 1.))
      ~ramp:[0., 0.; 0.3, 0.12; 0.7, 0.88; 1., 1.] populated |> get_ok)
    geometry_output

let run_deform_benchmarks () =
  let source = make_grid () in
  let geometric_source = source
      |> Geometry.without_attribute ~owner:Attribute.Point "N"
      |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
  let source_with_normals = source in
  let point_count = Geometry.point_count source in
  let mask = Attribute.create_owned ~name:"deform_mask"
      ~owner:Attribute.Point (Attribute.Float (Array.init point_count (fun point ->
        0.2 +. (float_of_int (point mod 257) /. 320.)))) |> get_ok in
  let source_with_normals = Geometry.with_attribute mask source_with_normals
      |> get_ok in
  let jitter_id = Attribute.create_owned ~name:"jitter_id"
      ~owner:Attribute.Point (Attribute.Int (Array.init point_count (fun point ->
        (point * 65_537) lxor (point lsr 5)))) |> get_ok
  and point_scale = Attribute.create_owned ~name:"pscale"
      ~owner:Attribute.Point (Attribute.Float (Array.init point_count (fun point ->
        0.25 +. (float_of_int (point mod 17) /. 16.)))) |> get_ok in
  let jitter_source = geometric_source
      |> Geometry.with_attribute mask |> get_ok
      |> Geometry.with_attribute jitter_id |> get_ok
      |> Geometry.with_attribute point_scale |> get_ok in
  let jitter_selection = Group.init ~grain ~owner:Group.Point
      ~name:"jitter_selection" point_count (fun point -> point mod 5 <> 0) in
  measure ~input_points:point_count "normals_area_weighted" (fun () ->
    Ops.normals ~grain geometric_source |> get_ok) geometry_output;
  measure ~input_points:point_count "normals_vertex_angle_points" (fun () ->
    Ops.normals ~grain ~weighting:Ops.Vertex_angle geometric_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "normals_vertex_angle_vertices_smooth"
    (fun () -> Ops.normals ~grain ~owner:Attribute.Vertex
      ~weighting:Ops.Vertex_angle ~cusp_angle:Float.pi geometric_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "normals_vertex_angle_vertices_cusp60"
    (fun () -> Ops.normals ~grain ~owner:Attribute.Vertex
      ~weighting:Ops.Vertex_angle ~cusp_angle:(Float.pi /. 3.) geometric_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "normals_primitives" (fun () ->
    Ops.normals ~grain ~owner:Attribute.Primitive geometric_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "normals_detail" (fun () ->
    Ops.normals ~grain ~owner:Attribute.Detail geometric_source |> get_ok)
    geometry_output;
  let selected_primitives = Group.init ~grain ~owner:Group.Primitive
      ~name:"normal_alternating" (Geometry.primitive_count geometric_source)
      (fun primitive -> primitive land 1 = 0) in
  measure ~input_points:point_count "normals_vertex_cusp60_local_missing" (fun () ->
    Ops.normals ~grain ~selection:(Ops.Selected_primitives selected_primitives)
      ~owner:Attribute.Vertex ~weighting:Ops.Vertex_angle
      ~cusp_angle:(Float.pi /. 3.) geometric_source |> get_ok) geometry_output;
  measure ~input_points:point_count "peak_point_n_mask" (fun () ->
    Ops.peak ~grain ~mask_attribute:"deform_mask" ~distance:0.35
      source_with_normals |> get_ok) geometry_output;
  measure ~input_points:point_count "peak_geometric_recompute" (fun () ->
    Ops.peak ~grain ~distance:0.35 ~recompute_normals:true geometric_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "bend_twist_capture" (fun () ->
    Ops.bend ~grain ~origin:(Vec3.create 0. 0. (-50.))
      ~direction:Vec3.unit_z ~up:Vec3.unit_y ~length:100.
      ~bend_angle:1.3 ~twist_angle:2.1 ~mask_attribute:"deform_mask"
      ~capture_attribute:"bend_capture" source_with_normals |> get_ok)
    geometry_output;
  measure ~input_points:point_count "point_jitter_attribute_randomize_baseline"
    (fun () -> Attribute_ops.randomize ~grain ~seed:(Rand.seed 73)
      ~operation:Attribute_ops.Random_add ~owner:Attribute.Point ~name:"P"
      (Attribute_ops.Random_uniform {
        min = Attribute_ops.Vec3 (Vec3.create (-0.5) (-0.5) (-0.5));
        max = Attribute_ops.Vec3 (Vec3.create 0.5 0.5 0.5);
      }) geometric_source |> get_ok) geometry_output;
  measure ~input_points:point_count "point_jitter_uniform" (fun () ->
    Ops.point_jitter ~grain ~seed:(Rand.seed 73) ~scale:1. geometric_source
    |> get_ok) geometry_output;
  measure ~input_points:point_count "point_jitter_controls" (fun () ->
    Ops.point_jitter ~grain ~points:jitter_selection
      ~mask_attribute:"deform_mask" ~id_attribute:"jitter_id"
      ~use_point_scale:true ~seed:(Rand.seed 73) ~scale:1.25
      ~axis_scales:(Vec3.create 0.5 1.5 (-0.75)) jitter_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "mountain_fbm6_n_height" (fun () ->
    Ops.mountain ~grain ~seed:73 ~height:1.25
      ~frequency:(Vec3.create 0.17 0.31 0.23)
      ~offset:(Vec3.create 1. 2. 3.) ~octaves:6 ~lacunarity:2.05
      ~roughness:0.47 ~mask_attribute:"deform_mask"
      ~height_attribute:"mountain_height" source_with_normals |> get_ok)
    geometry_output;
  measure ~input_points:point_count "mountain_fbm6_geometric_recompute"
    (fun () -> Ops.mountain ~grain ~seed:73 ~height:1.25
      ~frequency:(Vec3.create 0.17 0.31 0.23)
      ~offset:(Vec3.create 1. 2. 3.) ~octaves:6 ~lacunarity:2.05
      ~roughness:0.47 ~recompute_normals:true geometric_source |> get_ok)
    geometry_output

let run_edge_divide_benchmarks () =
  let columns = 300 and rows = 250 in
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_quads
      ~uv_attribute:"uv" ~columns ~rows ~size:100. () |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"point_id"
      |> get_ok in
  let vertex_count = Geometry.vertex_count source in
  let corner = Attribute.create_owned ~owner:Attribute.Vertex ~name:"corner"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init vertex_count (fun vertex ->
          float_of_int (vertex land 3) /. 3.))
        ~y:(Array.init vertex_count (fun vertex ->
          float_of_int ((vertex + 1) land 3) /. 3.)) |> get_ok)) |> get_ok in
  let point_count = Geometry.point_count source in
  let point_group = Group.init ~grain ~owner:Group.Point ~name:"checker"
      point_count (fun point -> point land 1 = 0) in
  let source = source |> Geometry.with_attribute corner |> get_ok
      |> Geometry.with_group point_group |> get_ok
      |> Ops.group_edges ~grain ~name:"all_edges" |> get_ok in
  let edges = Geometry.find_edge_group "all_edges" source |> Option.get in
  measure ~input_points:point_count "edge_divide_shared_divisions4" (fun () ->
    Ops.edge_divide ~grain ~edges ~divisions:4 source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "edge_divide_unique_divisions4" (fun () ->
    Ops.edge_divide ~grain ~edges ~divisions:4 ~share_points:false source
    |> get_ok) geometry_output

let run_edge_collapse_benchmarks () =
  let columns = 500 and rows = 400 in
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_quads
      ~uv_attribute:"uv" ~columns ~rows ~size:100. () |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"point_id"
      |> get_ok in
  let point_count = Geometry.point_count source
  and vertex_count = Geometry.vertex_count source in
  let corner = Attribute.create_owned ~owner:Attribute.Vertex ~name:"corner"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init vertex_count (fun vertex ->
          float_of_int (vertex land 3) /. 3.))
        ~y:(Array.init vertex_count (fun vertex ->
          float_of_int ((vertex + 1) land 3) /. 3.)) |> get_ok)) |> get_ok in
  let checker = Group.init ~grain ~owner:Group.Point ~name:"checker"
      point_count (fun point -> point land 1 = 0) in
  let source = source |> Geometry.with_attribute corner |> get_ok
      |> Geometry.with_group checker |> get_ok in
  let topology = Geometry.topology source in
  let index = Topology_index.create topology in
  let index_view = Topology_index.Private.view index in
  let collapse = Edge_group.init ~grain ~topology ~index ~name:"collapse_edges"
      (fun edge ->
        let a = index_view.edge_a.(edge) and b = index_view.edge_b.(edge) in
        b = a + 1 && a mod 4 = 0) in
  let source = Geometry.with_edge_group collapse source |> get_ok in
  let collapse = Geometry.find_edge_group "collapse_edges" source
      |> Option.get in
  measure ~input_points:point_count "edge_collapse_sparse_center_cleanup" (fun () ->
    Ops.edge_collapse ~grain ~edges:collapse source |> get_ok) geometry_output

let run_poly_reduce_benchmarks () =
  let columns = 420 and rows = 320 in
  let source = Ops.grid ~grain ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_alternating_triangles ~uv_attribute:"uv"
      ~columns ~rows ~size:100. () |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"point_id"
      |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Primitive
           ~name:"source_primitive" |> get_ok in
  let point_count = Geometry.point_count source in
  let checker = Group.init ~grain ~owner:Group.Point ~name:"checker"
      point_count (fun point -> point land 1 = 0) in
  let source = Geometry.with_group checker source |> get_ok
      |> Ops.group_edges ~grain ~name:"boundary"
           ~incidence:Ops.Boundary_edge |> get_ok in
  measure ~input_points:point_count "poly_reduce_qem_ratio40_payload" (fun () ->
    Ops.poly_reduce ~grain ~target:(Ops.Reduce_ratio 0.4)
      ~preserve_boundary:true ~equalize_lengths:1e-8
      ~max_normal_deviation:0.7 ~output_group:"reduced" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "poly_reduce_original_positions_ratio40"
    (fun () -> Ops.poly_reduce ~grain ~target:(Ops.Reduce_ratio 0.4)
      ~preserve_boundary:false ~only_original_positions:true source |> get_ok)
    geometry_output

let run_remesh_benchmarks () =
  let remesh_columns = max 8 (min columns 420)
  and remesh_rows = max 8 (min rows 320) in
  let source = Ops.grid ~grain ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_alternating_triangles ~uv_attribute:"uv"
      ~columns:remesh_columns ~rows:remesh_rows ~size:100. () |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"point_id"
      |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Primitive
           ~name:"source_primitive" |> get_ok in
  let positions = Packed.Float3.Private.view (Geometry.positions source) in
  let x = Array.copy positions.x and z = Array.copy positions.z
  and y = Array.init (Geometry.point_count source) (fun point ->
    0.35 *. sin (positions.x.(point) *. 0.17)
    *. cos (positions.z.(point) *. 0.13)) in
  let source = Geometry.with_positions
      (Packed.Float3.Private.of_owned_exn ~x ~y ~z) source |> get_ok in
  let point_count = Geometry.point_count source in
  let target = 100. /. float_of_int (max remesh_columns remesh_rows) *. 1.13 in
  measure ~input_points:point_count "remesh_topology_iteration_payload" (fun () ->
    Ops.remesh ~grain ~iterations:1 ~smoothing:0. ~project:false
      ~recompute_point_normals:false ~target_length:target source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "remesh_uniform_full_iteration" (fun () ->
    Ops.remesh ~grain ~iterations:1 ~smoothing:0.45 ~project:true
      ~target_length:target ~output_hard_edges:"hard"
      ~output_mesh_size:"mesh_size" ~output_quality:"quality" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "remesh_input_points_relax_project" (fun () ->
    Ops.remesh ~grain ~iterations:3 ~smoothing:0.45 ~project:true
      ~use_input_points_only:true ~target_length:target
      ~output_quality:"quality" source |> get_ok) geometry_output;
  measure ~input_points:point_count "remesh_triangulate_diagnostics" (fun () ->
    Ops.remesh ~grain ~iterations:0 ~target_length:target
      ~output_hard_edges:"hard" ~output_mesh_size:"mesh_size"
      ~output_quality:"quality" source |> get_ok) geometry_output

let run_boolean_detect_benchmarks () =
  let detect_columns = max 8 (min columns 420)
  and detect_rows = max 8 (min rows 320) in
  let source = Ops.grid ~grain ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_alternating_triangles
      ~columns:detect_columns ~rows:detect_rows ~size:100. () |> get_ok in
  let point_count = Geometry.point_count source in
  let crossing = Ops.transform ~grain
      (Mat4.rotation_x (Float.pi /. 2.)) source in
  measure ~input_points:(point_count * 2) "boolean_detect_crossing_grids"
    (fun () -> Ops.boolean_detect ~grain ~collision:crossing
      ~intersecting_group:(Some "intersections")
      ~intersections_attribute:"collision_primitives"
      ~count_attribute:"intersection_count" source |> get_ok)
    geometry_output;
  let combined = Ops.merge [source; crossing] |> get_ok in
  let combined_index = Surface_index.create ~grain combined |> get_ok in
  measure ~input_points:(point_count * 2) "boolean_detect_self_crossing_broadphase"
    (fun () -> Surface_index.Private.overlapping_self_triangle_pairs ~grain
      ~tolerance:0. combined_index) integer_pair_arrays_output;
  measure ~input_points:(point_count * 2) "boolean_detect_self_crossing_grids"
    (fun () -> Ops.boolean_detect ~grain ~collision:(Ops.points [||])
      ~intersecting_group:None
      ~self_intersecting_group:"self_intersections"
      ~self_intersections_attribute:"self_primitives"
      ~self_count_attribute:"self_count" combined |> get_ok)
    geometry_output;
  let cell_x = 100. /. float_of_int detect_columns
  and cell_z = 100. /. float_of_int detect_rows in
  let coplanar = Ops.transform ~grain
      (Mat4.translation (Vec3.create (0.37 *. cell_x) 0. (0.41 *. cell_z)))
      source in
  let source_index = Surface_index.create ~grain source |> get_ok
  and coplanar_index = Surface_index.create ~grain coplanar |> get_ok in
  measure ~input_points:(point_count * 2) "boolean_detect_coplanar_broadphase"
    (fun () -> Surface_index.Private.overlapping_triangle_pairs ~grain
      ~tolerance:0. source_index coplanar_index)
    integer_pair_arrays_output;
  measure ~input_points:(point_count * 2) "boolean_detect_coplanar_shifted_grids"
    (fun () -> Ops.boolean_detect ~grain ~collision:coplanar
      ~intersecting_group:(Some "intersections")
      ~intersections_attribute:"collision_primitives"
      ~count_attribute:"intersection_count" source |> get_ok)
    geometry_output

let run_intersection_analysis_benchmarks () =
  let detect_columns = max 8 (min columns 420)
  and detect_rows = max 8 (min rows 320) in
  let source = Ops.grid ~grain ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_alternating_triangles
      ~columns:detect_columns ~rows:detect_rows ~size:100. () |> get_ok in
  let point_count = Geometry.point_count source in
  let crossing = Ops.transform ~grain
      (Mat4.rotation_x (Float.pi /. 2.)) source in
  measure ~input_points:(point_count * 2)
    "intersection_analysis_crossing_grids" (fun () ->
      Ops.intersection_analysis ~grain ~include_coplanar:false
        ~collision:crossing source |> get_ok) geometry_output;
  let combined = Ops.merge [source; crossing] |> get_ok in
  measure ~input_points:(point_count * 2)
    "intersection_analysis_self_crossing_grids" (fun () ->
      Ops.intersection_analysis ~grain ~include_coplanar:false combined |> get_ok)
    geometry_output;
  let cell_x = 100. /. float_of_int detect_columns
  and cell_z = 100. /. float_of_int detect_rows in
  let coplanar = Ops.transform ~grain
      (Mat4.translation (Vec3.create (0.37 *. cell_x) 0. (0.41 *. cell_z)))
      source in
  measure ~input_points:(point_count * 2)
    "intersection_analysis_coplanar_shifted_grids" (fun () ->
      Ops.intersection_analysis ~grain ~collision:coplanar source |> get_ok)
    geometry_output;
  let curve_columns = max 8 (min columns 360)
  and curve_rows = max 8 (min rows 260) in
  let rows = Ops.grid ~grain ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_rows ~columns:curve_columns ~rows:curve_rows
      ~size:100. () |> get_ok
  and columns = Ops.grid ~grain ~counts:Ops.Grid_point_counts
      ~connectivity:Ops.Grid_columns ~columns:curve_columns ~rows:curve_rows
      ~size:100. () |> get_ok in
  measure ~input_points:(Geometry.point_count rows + Geometry.point_count columns)
    "intersection_analysis_curve_grid" (fun () ->
      Ops.intersection_analysis ~grain ~collision:columns rows |> get_ok)
    geometry_output

let run_poly_bevel_benchmarks () =
  let copies = box_batch in
  let source = Ops.box ~grain ~connectivity:Ops.Box_quads
      ~consolidate_points:true ~normals:Ops.Box_no_normals
      ~size:(Vec3.create 1. 1. 1.) () |> get_ok
      |> Ops.duplicate ~grain ~copies:(copies - 1)
           ~transform:(Mat4.translation (Vec3.create 1.5 0. 0.)) |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"point_id"
      |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Vertex ~name:"corner_id"
      |> get_ok
      |> Ops.group_edges ~grain ~name:"bevel_edges" |> get_ok in
  let point_count = Geometry.point_count source in
  let scale = Attribute.create_owned ~owner:Attribute.Point ~name:"pscale"
      (Attribute.Float (Array.init point_count (fun point ->
        0.75 +. float_of_int (point land 3) *. 0.125))) |> get_ok in
  let source = Geometry.with_attribute scale source |> get_ok in
  let edges = Geometry.find_edge_group "bevel_edges" source |> Option.get in
  measure ~input_points:point_count "poly_bevel_chamfer_all_boxes" (fun () ->
    Ops.poly_bevel ~grain ~edges ~distance:0.08
      ~edge_group:"edge_fillets" ~corner_group:"corner_fillets"
      ~offset_group:"offset_edges" source |> get_ok) geometry_output;
  measure ~input_points:point_count "poly_bevel_round4_payload_boxes" (fun () ->
    Ops.poly_bevel ~grain ~edges ~shape:(Ops.Bevel_round { convexity = 1. })
      ~divisions:4 ~point_scale_attribute:"pscale" ~distance:0.08
      ~edge_group:"edge_fillets" ~corner_group:"corner_fillets"
      ~offset_group:"offset_edges" source |> get_ok) geometry_output

let run_point_split_benchmarks () =
  let columns = 500 and rows = 400 in
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_quads
      ~columns ~rows ~size:100. () |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"point_id"
      |> get_ok
      |> Ops.group_edges ~grain ~name:"source_edges" |> get_ok in
  let point_count = Geometry.point_count source
  and vertex_count = Geometry.vertex_count source
  and primitive_count = Geometry.primitive_count source in
  let topology = Topology.Private.view (Geometry.topology source) in
  let seam_uv = Attribute.create_owned ~owner:Attribute.Vertex ~name:"seam_uv"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init vertex_count (fun vertex ->
          let primitive = vertex / 4 in
          float_of_int topology.vertex_points.(vertex) +.
          (float_of_int ((primitive / 11) mod 4) *. 0.125)))
        ~y:(Array.init vertex_count (fun vertex ->
          float_of_int ((vertex / 4) mod 17) *. 0.0625)) |> get_ok)) |> get_ok
  and seam_material = Attribute.create_owned ~owner:Attribute.Primitive
      ~name:"seam_material" (Attribute.Int (Array.init primitive_count
        (fun primitive -> (primitive / 11) mod 4))) |> get_ok
  and corner_id = Attribute.create_owned ~owner:Attribute.Vertex ~name:"corner_id"
      (Attribute.Int (Array.init vertex_count Fun.id)) |> get_ok
  and checker = Group.init ~grain ~owner:Group.Point ~name:"checker" point_count
      (fun point -> point land 1 = 0)
  and seam_region = Group.init ~grain ~owner:Group.Primitive
      ~name:"seam_region" primitive_count
      (fun primitive -> primitive land 7 < 4) in
  let source = source |> Geometry.with_attribute seam_uv |> get_ok
      |> Geometry.with_attribute seam_material |> get_ok
      |> Geometry.with_attribute corner_id |> get_ok
      |> Geometry.with_group checker |> get_ok
      |> Geometry.with_group seam_region |> get_ok in
  measure ~input_points:point_count "point_split_unique_quads" (fun () ->
    Ops.point_split ~grain source |> get_ok) geometry_output;
  measure ~input_points:point_count "point_split_group_seams_quads" (fun () ->
    Ops.point_split ~grain ~attributes:"seam_region" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "point_split_attribute_seams_promote_quads"
    (fun () ->
      Ops.point_split ~grain ~attributes:"seam_uv seam_material"
        ~tolerance:1e-6 ~promote_attributes:true source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "point_split_seams_promote_quads" (fun () ->
    Ops.point_split ~grain ~attributes:"seam_*" ~tolerance:1e-6
      ~promote_attributes:true source |> get_ok) geometry_output

let run_point_generate_benchmarks () =
  let source_count = 100_000 in
  let source = Ops.points (Array.init source_count (fun point ->
      float_of_int (point mod 1_000) *. 0.01,
      float_of_int (point / 1_000) *. 0.01,
      float_of_int (point mod 17) *. 0.001))
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"source_id"
      |> get_ok in
  let density = Attribute.create_owned ~owner:Attribute.Point ~name:"density"
      (Attribute.Float (Array.make source_count 6.)) |> get_ok
  and velocity = Attribute.create_owned ~owner:Attribute.Point ~name:"v"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.init source_count (fun point -> float_of_int (point land 7)))
        ~y:(Array.init source_count (fun point -> float_of_int (point land 3)))
        ~z:(Array.make source_count 0.5))) |> get_ok
  and weights = Attribute.create_owned ~owner:Attribute.Point ~name:"weights"
      (Attribute.Float_array (Packed.Float_array.Private.create_validated_owned
        ~offsets:(Array.init (source_count + 1) (fun point -> point * 2))
        ~values:(Array.init (source_count * 2) (fun value ->
          float_of_int (value land 31) *. 0.03125)))) |> get_ok
  and author = Attribute.create_owned ~owner:Attribute.Detail ~name:"author"
      (Attribute.Text [|"point-generate-benchmark"|]) |> get_ok in
  let source = source |> Geometry.with_attribute density |> get_ok
      |> Geometry.with_attribute velocity |> get_ok
      |> Geometry.with_attribute weights |> get_ok
      |> Geometry.with_attribute author |> get_ok in
  measure ~input_points:0 "point_generate_total_origin_1m" (fun () ->
    Ops.point_generate ~grain ~mode:(Ops.Generate_total scatter_count)
      source |> get_ok) geometry_output;
  let mode = Ops.Generate_per_point {
      points_per_point = 1.; scale_attribute = Some "density" } in
  measure ~input_points:source_count "point_generate_per_point_payload_600k"
    (fun () -> Ops.point_generate ~grain ~seed:(Rand.seed 727)
      ~generated_group:"emitted" ~copy_point_attributes:"*"
      ~copy_detail_attributes:"author" ~mode source |> get_ok) geometry_output;
  measure ~input_points:source_count "point_generate_keep_input_payload_700k"
    (fun () -> Ops.point_generate ~grain ~seed:(Rand.seed 727) ~keep_input:true
      ~generated_group:"emitted" ~copy_point_attributes:"*"
      ~copy_detail_attributes:"author" ~mode source |> get_ok) geometry_output

let run_point_replicate_benchmarks () =
  let source_count = 100_000 in
  let source = Ops.points (Array.init source_count (fun point ->
      float_of_int (point mod 1_000) *. 0.01,
      float_of_int (point / 1_000) *. 0.01, 0.)) in
  let density = Attribute.create_owned ~owner:Attribute.Point ~name:"density"
      (Attribute.Float (Array.make source_count 6.)) |> get_ok
  and id = Attribute.create_owned ~owner:Attribute.Point ~name:"id"
      (Attribute.Int (Array.init source_count (fun point -> point * 17))) |> get_ok
  and pscale = Attribute.create_owned ~owner:Attribute.Point ~name:"pscale"
      (Attribute.Float (Array.init source_count (fun point ->
        0.5 +. float_of_int (point land 7) *. 0.0625))) |> get_ok
  and normal = Attribute.create_owned ~owner:Attribute.Point ~name:"N"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make source_count 0.) ~y:(Array.make source_count 1.)
        ~z:(Array.make source_count 0.))) |> get_ok
  and velocity = Attribute.create_owned ~owner:Attribute.Point ~name:"v"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make source_count 0.25) ~y:(Array.make source_count 0.)
        ~z:(Array.make source_count 0.5))) |> get_ok
  and flow = Attribute.create_owned ~owner:Attribute.Point ~name:"flow"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:(Array.make source_count 1.) ~y:(Array.make source_count 2.)
        ~z:(Array.make source_count 3.))) |> get_ok in
  let source = source |> Geometry.with_attribute density |> get_ok
      |> Geometry.with_attribute id |> get_ok
      |> Geometry.with_attribute pscale |> get_ok
      |> Geometry.with_attribute normal |> get_ok
      |> Geometry.with_attribute velocity |> get_ok
      |> Geometry.with_attribute flow |> get_ok in
  let basis = Ops.points [|0.,0.,0.; 1.,0.,0.; 0.,1.,0.; 0.,0.,1.|] in
  measure ~input_points:source_count "point_replicate_basis_frames_100k"
    (fun () -> Ops.copy_to_points ~grain ~source:basis ~targets:source ()
      |> get_ok) geometry_output;
  measure ~input_points:source_count "point_replicate_emission_only_600k"
    (fun () -> Ops.point_generate ~grain ~seed:(Rand.seed 991)
      ~generated_group:"cloud" ~copy_point_attributes:"density id pscale N v"
      ~mode:(Ops.Generate_per_point {
        points_per_point = 1.; scale_attribute = Some "density" }) source
      |> get_ok) geometry_output;
  measure ~input_points:source_count "point_replicate_sphere_payload_600k"
    (fun () -> Ops.point_replicate ~grain ~seed:(Rand.seed 991)
      ~shape:Ops.Replicate_sphere ~generated_group:"cloud"
      ~copy_point_attributes:"density id pscale N v"
      ~points_per_point:1. ~scale_attribute:"density" source |> get_ok)
    geometry_output;
  measure ~input_points:source_count "point_replicate_line_payload_600k"
    (fun () -> Ops.point_replicate ~grain ~seed:(Rand.seed 991)
      ~shape:Ops.Replicate_line ~generated_group:"cloud"
      ~copy_point_attributes:"density id pscale N v"
      ~points_per_point:1. ~scale_attribute:"density" source |> get_ok)
    geometry_output;
  measure ~input_points:source_count "point_replicate_transformed_vectors_600k"
    (fun () -> Ops.point_replicate ~grain ~seed:(Rand.seed 991)
      ~shape:Ops.Replicate_sphere ~generated_group:"cloud"
      ~copy_point_attributes:"density id pscale N flow"
      ~transform_attributes:"N flow"
      ~points_per_point:1. ~scale_attribute:"density" source |> get_ok)
    geometry_output;
  measure ~input_points:source_count "point_replicate_sphere_quasi_velocity_600k"
    (fun () -> Ops.point_replicate ~grain ~seed:(Rand.seed 991)
      ~shape:Ops.Replicate_sphere ~quasi_stratified:true
      ~velocity_stretch:Ops.Replicate_scaled_velocity ~velocity_scale:0.7
      ~inherit_velocity:0.8 ~radial_velocity:0.25
      ~generated_group:"cloud" ~copy_point_attributes:"density id pscale N v"
      ~points_per_point:1. ~scale_attribute:"density" source |> get_ok)
    geometry_output;
  measure ~input_points:source_count "point_replicate_sphere_noise_600k"
    (fun () -> Ops.point_replicate ~grain ~seed:(Rand.seed 991)
      ~shape:Ops.Replicate_sphere ~noise_seed:992
      ~noise_amplitude:(Vec3.create 0.12 0.2 0.16)
      ~noise_frequency:(Vec3.create 1.2 0.8 1.7) ~noise_turbulence:4
      ~noise_roughness:0.55 ~noise_attenuation:1.2
      ~generated_group:"cloud" ~copy_point_attributes:"density id pscale N v"
      ~points_per_point:1. ~scale_attribute:"density" source |> get_ok)
    geometry_output

let run_edge_flip_benchmarks () =
  let pairs = 50_000 in
  let point_count = pairs * 4 and vertex_count = pairs * 6 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0.
  and vertex_points = Array.make vertex_count 0 in
  for pair = 0 to pairs - 1 do
    let point = pair * 4 and vertex = pair * 6 in
    let origin_x = float_of_int (pair mod 500) *. 2.
    and origin_y = float_of_int (pair / 500) *. 2. in
    x.(point) <- origin_x; y.(point) <- origin_y;
    x.(point + 1) <- origin_x +. 1.; y.(point + 1) <- origin_y;
    x.(point + 2) <- origin_x +. 1.; y.(point + 2) <- origin_y +. 1.;
    x.(point + 3) <- origin_x; y.(point + 3) <- origin_y +. 1.;
    vertex_points.(vertex) <- point;
    vertex_points.(vertex + 1) <- point + 1;
    vertex_points.(vertex + 2) <- point + 2;
    vertex_points.(vertex + 3) <- point;
    vertex_points.(vertex + 4) <- point + 2;
    vertex_points.(vertex + 5) <- point + 3
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets:(Array.init (pairs * 2 + 1) (fun face -> face * 3))
      |> get_ok in
  let corner = Attribute.create_owned ~owner:Attribute.Vertex ~name:"corner"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init vertex_count (fun vertex ->
          float_of_int (vertex mod 3) /. 2.))
        ~y:(Array.init vertex_count (fun vertex ->
          float_of_int ((vertex + 1) mod 3) /. 2.)) |> get_ok)) |> get_ok in
  let checker = Group.init ~grain ~owner:Group.Point ~name:"checker"
      point_count (fun point -> point land 1 = 0) in
  let index = Topology_index.create topology in
  let flip = Edge_group.init ~grain ~topology ~index ~name:"flip_edges"
      (fun edge ->
        let a, b = Topology_index.edge_points index edge in
        abs (a - b) = 2 && min a b mod 4 = 0) in
  let source = Geometry.create ~positions ~topology ~attributes:[corner]
      ~groups:[checker] ~edge_groups:[flip] () |> get_ok in
  let flip = Geometry.find_edge_group "flip_edges" source |> Option.get in
  measure ~input_points:point_count "edge_flip_disjoint_triangle_pairs" (fun () ->
    Ops.edge_flip ~grain ~edges:flip source |> get_ok) geometry_output

let run_edge_cusp_benchmarks () =
  let columns = 300 and rows = 250 in
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_triangles
      ~uv_attribute:"uv" ~columns ~rows ~size:100. () |> get_ok
      |> Attribute_ops.enumerate ~grain ~owner:Attribute.Point ~name:"point_id"
      |> get_ok in
  let point_count = Geometry.point_count source
  and vertex_count = Geometry.vertex_count source in
  let corner = Attribute.create_owned ~owner:Attribute.Vertex ~name:"corner"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init vertex_count (fun vertex ->
          float_of_int (vertex mod 3) /. 2.))
        ~y:(Array.init vertex_count (fun vertex ->
          float_of_int ((vertex + 1) mod 3) /. 2.)) |> get_ok)) |> get_ok in
  let checker = Group.init ~grain ~owner:Group.Point ~name:"checker"
      point_count (fun point -> point land 1 = 0) in
  let source = source |> Geometry.with_attribute corner |> get_ok
      |> Geometry.with_group checker |> get_ok
      |> Ops.group_edges ~grain ~name:"cusp_edges" |> get_ok in
  let cusp = Geometry.find_edge_group "cusp_edges" source |> Option.get in
  measure ~input_points:point_count "edge_cusp_all_triangle_edges" (fun () ->
    Ops.edge_cusp ~grain ~edges:cusp source |> get_ok) geometry_output

let run_edge_straighten_benchmarks () =
  let components = 100_000 in
  let point_count = components * 3 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for component = 0 to components - 1 do
    let point = component * 3
    and ox = float_of_int (component mod 1_000) *. 4.
    and oy = float_of_int (component / 1_000) *. 3. in
    x.(point) <- ox -. 1.; y.(point) <- oy;
    x.(point + 1) <- ox; y.(point + 1) <- oy +. 1.;
    x.(point + 2) <- ox +. 1.; y.(point + 2) <- oy
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (components + 1)
        (fun primitive -> primitive * 3))
      ~primitive_kinds:(Array.make components Topology.Open_polyline) |> get_ok in
  let point_id = Attribute.create_owned ~owner:Attribute.Point ~name:"point_id"
      (Attribute.Int (Array.init point_count Fun.id)) |> get_ok in
  let checker = Group.init ~grain ~owner:Group.Point ~name:"checker"
      point_count (fun point -> point land 1 = 0) in
  let source = Geometry.create ~positions ~topology ~attributes:[point_id]
      ~groups:[checker] () |> get_ok in
  measure ~input_points:point_count "edge_straighten_independent_bends" (fun () ->
    Ops.edge_straighten ~grain ~output_group:"straightened" source |> get_ok)
    geometry_output

let edge_equalize_benchmark_fixture () =
  let edges = max 1 (rows * max 1 columns) in
  let point_count = edges * 2 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for edge = 0 to edges - 1 do
    let point = edge * 2 in
    let base = float_of_int edge *. 3.
    and length = 0.5 +. (float_of_int (edge mod 17) *. 0.1) in
    x.(point) <- base;
    x.(point + 1) <- base +. length
  done;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (edges + 1) (fun edge -> edge * 2))
      ~primitive_kinds:(Array.make edges Topology.Open_polyline) |> get_ok in
  let point_id = Attribute.create_owned ~owner:Attribute.Point ~name:"point_id"
      (Attribute.Int (Array.init point_count Fun.id)) |> get_ok in
  Geometry.create ~positions ~topology ~attributes:[point_id] () |> get_ok,
  edges

let reference_edge_equalize_average geometry edge_count =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let total = ref 0. in
  for edge = 0 to edge_count - 1 do
    let point = edge * 2 in
    total := !total +. (positions.x.(point + 1) -. positions.x.(point))
  done;
  let target = !total /. float_of_int edge_count in
  let x = Array.copy positions.x in
  for edge = 0 to edge_count - 1 do
    let point = edge * 2 in
    let length = positions.x.(point + 1) -. positions.x.(point) in
    let factor = 0.5 *. (length -. target) /. length in
    let delta = positions.x.(point + 1) -. positions.x.(point) in
    x.(point) <- positions.x.(point) +. (factor *. delta);
    x.(point + 1) <- positions.x.(point + 1) -. (factor *. delta)
  done;
  Geometry.with_positions
    (Packed.Float3.Private.of_shared_exn ~x ~y:positions.y ~z:positions.z)
    geometry |> get_ok

let run_edge_equalize_reference_benchmarks () =
  let geometry, edge_count = edge_equalize_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_equalize_reference_disjoint_average" (fun () ->
      reference_edge_equalize_average geometry edge_count) geometry_output

let run_edge_equalize_benchmarks () =
  let geometry, _ = edge_equalize_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_equalize_disjoint_average" (fun () ->
      Ops.edge_equalize ~grain ~method_:Ops.Equalize_average geometry |> get_ok)
    geometry_output

let edge_relax_benchmark_fixture () =
  let geometry, edge_count = edge_equalize_benchmark_fixture () in
  let source = Packed.Float3.Private.view (Geometry.positions geometry) in
  let x = Array.copy source.x in
  for edge = 0 to edge_count - 1 do
    let point = edge * 2 in
    x.(point + 1) <- x.(point) +. 0.8 +. float_of_int (edge mod 11) *. 0.1
  done;
  let reference = Geometry.with_positions
      (Packed.Float3.Private.of_shared_exn ~x ~y:source.y ~z:source.z)
      geometry |> get_ok in
  geometry, reference, edge_count

let reference_edge_relax geometry reference edge_count =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and target = Packed.Float3.Private.view (Geometry.positions reference) in
  let x = Array.copy positions.x in
  for edge = 0 to edge_count - 1 do
    let point = edge * 2 in
    let length = positions.x.(point + 1) -. positions.x.(point)
    and target_length = target.x.(point + 1) -. target.x.(point) in
    let factor = 0.5 *. (length -. target_length) /. length in
    let delta = positions.x.(point + 1) -. positions.x.(point) in
    x.(point) <- positions.x.(point) +. factor *. delta;
    x.(point + 1) <- positions.x.(point + 1) -. factor *. delta
  done;
  Geometry.with_positions
    (Packed.Float3.Private.of_shared_exn ~x ~y:positions.y ~z:positions.z)
    geometry |> get_ok

let run_edge_relax_reference_benchmarks () =
  let geometry, reference, edge_count = edge_relax_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_relax_reference_disjoint_individual" (fun () ->
      reference_edge_relax geometry reference edge_count) geometry_output

let run_edge_relax_benchmarks () =
  let geometry, reference, _ = edge_relax_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_relax_disjoint_individual" (fun () ->
      Ops.edge_relax ~grain ~reference geometry |> get_ok) geometry_output;
  let chains = max 1 (rows * max 1 columns / 3) in
  let point_count = chains * 3 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. and reference_x = Array.make point_count 0. in
  for chain = 0 to chains - 1 do
    let point = chain * 3 and base = float_of_int chain *. 5. in
    x.(point) <- base; x.(point + 1) <- base +. 0.7;
    x.(point + 2) <- base +. 2.8;
    reference_x.(point) <- base;
    reference_x.(point + 1) <- base +. 1.2;
    reference_x.(point + 2) <- base +. 2.4
  done;
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (chains + 1) (fun chain -> chain * 3))
      ~primitive_kinds:(Array.make chains Topology.Open_polyline) |> get_ok in
  let geometry = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z) ~topology ()
      |> get_ok in
  let source = Packed.Float3.Private.view (Geometry.positions geometry) in
  let reference = Geometry.with_positions
      (Packed.Float3.Private.of_shared_exn ~x:reference_x ~y:source.y ~z:source.z)
      geometry |> get_ok in
  measure ~input_points:point_count "edge_relax_connected_individual" (fun () ->
    Ops.edge_relax ~grain ~reference geometry |> get_ok) geometry_output

let edge_transport_benchmark_fixture () =
  let point_count = max 2 (rows * max 1 columns * 2) in
  let x = Array.init point_count (fun point -> float_of_int point *. 0.001)
  and y = Array.init point_count (fun point ->
    sin (float_of_int point *. 0.003) *. 0.02)
  and z = Array.make point_count 0. in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:[|0;point_count|]
      ~primitive_kinds:[|Topology.Open_polyline|] |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_ok

let edge_transport_many_curves_fixture () =
  let point_count = max 2 (rows * max 1 columns * 2) in
  let curve_size = 10 in
  let curve_count = point_count / curve_size in
  let point_count = curve_count * curve_size in
  let x = Array.init point_count (fun point ->
      float_of_int (point mod curve_size) *. 0.001)
  and y = Array.init point_count (fun point ->
      float_of_int (point / curve_size) *. 0.001)
  and z = Array.init point_count (fun point ->
      sin (float_of_int point *. 0.003) *. 0.02) in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (curve_count + 1)
        (fun curve -> curve * curve_size))
      ~primitive_kinds:(Array.make curve_count Topology.Open_polyline) |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_ok

let edge_transport_parent_fixture () =
  let point_count = max 10 (rows * max 1 columns * 2) in
  let tree_size = 10 in
  let tree_count = point_count / tree_size in
  let point_count = tree_count * tree_size in
  let x = Array.init point_count (fun point ->
      float_of_int (point mod tree_size) *. 0.001)
  and y = Array.init point_count (fun point ->
      float_of_int (point / tree_size) *. 0.001)
  and z = Array.make point_count 0. in
  let parent = Array.init point_count (fun point ->
      if point mod tree_size = 0 then point else point - 1) in
  let parent = Attribute.create_owned ~owner:Attribute.Point ~name:"parent"
      (Attribute.Int parent) |> get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology:(Topology.empty ~point_count) ~attributes:[parent] () |> get_ok

let edge_transport_parent_unordered_fixture () =
  let geometry = edge_transport_parent_fixture () in
  let point_count = Geometry.point_count geometry and tree_size = 10 in
  let parent = Array.init point_count (fun point ->
      if point mod tree_size = tree_size - 1 then point else point + 1) in
  let parent = Attribute.create_owned ~owner:Attribute.Point ~name:"parent"
      (Attribute.Int parent) |> get_ok in
  Geometry.with_attribute parent
    (Geometry.without_attribute ~owner:Attribute.Point "parent" geometry) |> get_ok

let reference_edge_transport_distance geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let point_count = Geometry.point_count geometry in
  let distance = Array.make point_count 0. in
  for point = 1 to point_count - 1 do
    let dx = positions.x.(point) -. positions.x.(point - 1)
    and dy = positions.y.(point) -. positions.y.(point - 1)
    and dz = positions.z.(point) -. positions.z.(point - 1) in
    distance.(point) <- distance.(point - 1)
      +. sqrt (dx *. dx +. dy *. dy +. dz *. dz)
  done;
  let attribute = Attribute.create_owned ~owner:Attribute.Point
      ~name:"distance" (Attribute.Float distance) |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let run_edge_transport_reference_benchmarks () =
  let geometry = edge_transport_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_transport_reference_curve_distance" (fun () ->
      reference_edge_transport_distance geometry) geometry_output

let reference_edge_transport_parent_distance geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let parents = match Geometry.find_attribute ~owner:Attribute.Point "parent"
      geometry with
    | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Int values -> values | _ -> assert false)
    | None -> assert false in
  let point_count = Geometry.point_count geometry in
  let distance = Array.make point_count 0. in
  for point = 0 to point_count - 1 do
    let parent = parents.(point) in
    if parent <> point then begin
      let dx = positions.x.(point) -. positions.x.(parent)
      and dy = positions.y.(point) -. positions.y.(parent)
      and dz = positions.z.(point) -. positions.z.(parent) in
      distance.(point) <- distance.(parent)
        +. sqrt (dx *. dx +. dy *. dy +. dz *. dz)
    end
  done;
  let attribute = Attribute.create_owned ~owner:Attribute.Point
      ~name:"distance" (Attribute.Float distance) |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let run_edge_transport_parent_reference_benchmarks () =
  let geometry = edge_transport_parent_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_transport_parent_reference_distance" (fun () ->
      reference_edge_transport_parent_distance geometry) geometry_output

let run_edge_transport_benchmarks () =
  let geometry = edge_transport_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_transport_network_curve_distance" (fun () ->
      Ops.edge_transport ~grain ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true geometry |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count geometry)
    "edge_transport_each_curve_distance" (fun () ->
      Ops.edge_transport_curves ~grain ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true geometry |> get_ok) geometry_output;
  let many = edge_transport_many_curves_fixture () in
  measure ~input_points:(Geometry.point_count many)
    "edge_transport_many_curves_distance" (fun () ->
      Ops.edge_transport_curves ~grain ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true many |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count many)
    "edge_transport_network_many_curves_forward_total" (fun () ->
      Ops.edge_transport ~grain ~attribute:"depth"
        ~operation:Ops.Transport_total ~integrate_constant:true many
        |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count many)
    "edge_transport_network_many_curves_backward_total" (fun () ->
      Ops.edge_transport ~grain ~attribute:"depth"
        ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
        ~integrate_constant:true ~merge:Ops.Transport_merge_add many
        |> get_ok) geometry_output

let run_edge_transport_parent_benchmarks () =
  let geometry = edge_transport_parent_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "edge_transport_parent_distance" (fun () ->
      Ops.edge_transport_parent ~grain ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true geometry |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count geometry)
    "edge_transport_parent_backward_total" (fun () ->
      Ops.edge_transport_parent ~grain ~attribute:"total"
        ~direction:Ops.Transport_backward ~operation:Ops.Transport_total
        ~integrate_constant:true ~merge:Ops.Transport_merge_add geometry
        |> get_ok) geometry_output;
  let unordered = edge_transport_parent_unordered_fixture () in
  measure ~input_points:(Geometry.point_count unordered)
    "edge_transport_parent_unordered_distance" (fun () ->
      Ops.edge_transport_parent ~grain ~attribute:"distance"
        ~operation:Ops.Transport_total ~integrate_constant:true
        ~scale_by_edge_length:true unordered |> get_ok) geometry_output

let blend_shapes_fixture () =
  let point_count = max 1 (rows * columns) in
  let make offset scale =
    let x = Array.init point_count (fun point ->
        offset +. scale *. float_of_int point *. 0.001)
    and y = Array.init point_count (fun point ->
        sin (float_of_int point *. 0.003 +. offset))
    and z = Array.init point_count (fun point ->
        cos (float_of_int point *. 0.002 -. offset)) in
    let geometry = Geometry.create
        ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
        ~topology:(Topology.empty ~point_count) () |> get_ok in
    let density = Attribute.create_owned ~owner:Attribute.Point ~name:"density"
        (Attribute.Float (Array.init point_count (fun point ->
          offset +. float_of_int (point mod 101) *. 0.01))) |> get_ok in
    let color = Attribute.create_owned ~owner:Attribute.Point ~name:"Cd"
        (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
          ~x:(Array.init point_count (fun point ->
            float_of_int (point mod 251) /. 251.))
          ~y:(Array.init point_count (fun point ->
            float_of_int (point mod 127) /. 127.))
          ~z:(Array.init point_count (fun point ->
            float_of_int (point mod 67) /. 67.)))) |> get_ok in
    let mask = Attribute.create_owned ~owner:Attribute.Point ~name:"mask"
        (Attribute.Float (Array.init point_count (fun point ->
          float_of_int (point mod 257) /. 256.))) |> get_ok in
    geometry |> Geometry.with_attribute density |> get_ok
    |> Geometry.with_attribute color |> get_ok
    |> Geometry.with_attribute mask |> get_ok in
  make 0. 1., make 1. 1.25, make (-0.5) 0.75

let reference_blend_shapes weight source target =
  let source_position = Packed.Float3.Private.view (Geometry.positions source)
  and target_position = Packed.Float3.Private.view (Geometry.positions target) in
  let point_count = Geometry.point_count source in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for point = 0 to point_count - 1 do
    x.(point) <- source_position.x.(point)
      +. weight *. (target_position.x.(point) -. source_position.x.(point));
    y.(point) <- source_position.y.(point)
      +. weight *. (target_position.y.(point) -. source_position.y.(point));
    z.(point) <- source_position.z.(point)
      +. weight *. (target_position.z.(point) -. source_position.z.(point))
  done;
  Geometry.with_positions (Packed.Float3.Private.of_owned_exn ~x ~y ~z) source
  |> get_ok

let run_blend_shapes_reference_benchmarks () =
  let source, target, _ = blend_shapes_fixture () in
  measure ~input_points:(Geometry.point_count source)
    "blend_shapes_reference_one_target_positions" (fun () ->
      reference_blend_shapes 0.37 source target) geometry_output

let run_blend_shapes_benchmarks () =
  let source, first, second = blend_shapes_fixture () in
  let first_shape = Ops.blend_shape ~weight:0.37 first in
  measure ~input_points:(Geometry.point_count source)
    "blend_shapes_one_target_positions" (fun () ->
      Ops.blend_shapes ~grain ~attributes:"^*" ~shapes:[first_shape] source
      |> get_ok) geometry_output;
  let first_shape = Ops.blend_shape ~weight:0.65 first
  and second_shape = Ops.blend_shape ~weight:0.55 second in
  measure ~input_points:(Geometry.point_count source)
    "blend_shapes_two_targets_attributes" (fun () ->
      Ops.blend_shapes ~grain ~shapes:[first_shape;second_shape] source
      |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count source)
    "blend_shapes_two_targets_masked" (fun () ->
      Ops.blend_shapes ~grain ~masking:Ops.Blend_scale_from_attribute
        ~mask_attribute:"mask" ~shapes:[first_shape;second_shape] source
      |> get_ok) geometry_output

let attribute_composite_fixture () =
  let point_count = max 1 (rows * columns) in
  let make offset =
    let geometry = Geometry.create
        ~positions:(Packed.Float3.Private.of_owned_exn
          ~x:(Array.init point_count (fun point -> float_of_int point *. 0.001))
          ~y:(Array.make point_count 0.) ~z:(Array.make point_count 0.))
        ~topology:(Topology.empty ~point_count) () |> get_ok in
    let value = Attribute.create_owned ~owner:Attribute.Point ~name:"value"
        (Attribute.Float (Array.init point_count (fun point ->
          offset +. float_of_int (point mod 1021) *. 0.001))) |> get_ok
    and alpha = Attribute.create_owned ~owner:Attribute.Point ~name:"alpha"
        (Attribute.Float (Array.init point_count (fun point ->
          float_of_int (point mod 101) /. 100.))) |> get_ok
    and color = Attribute.create_owned ~owner:Attribute.Point ~name:"Cd"
        (Attribute.Float4 (Packed.Float4.of_owned
          ~x:(Array.init point_count (fun point ->
            offset +. float_of_int (point mod 251) *. 0.01))
          ~y:(Array.init point_count (fun point ->
            offset *. 2. +. float_of_int (point mod 127) *. 0.02))
          ~z:(Array.init point_count (fun point ->
            offset *. 3. +. float_of_int (point mod 67) *. 0.03))
          ~w:(Array.make point_count 1.) |> get_ok)) |> get_ok in
    geometry |> Geometry.with_attribute value |> get_ok
    |> Geometry.with_attribute alpha |> get_ok
    |> Geometry.with_attribute color |> get_ok in
  make 0., make 1., make (-0.5)

let reference_attribute_composite_mean first second third =
  let values geometry = Geometry.find_attribute ~owner:Attribute.Point "value"
      geometry |> Option.get |> Attribute.Private.storage |> function
    | Attribute.Float values -> values | _ -> assert false in
  let first_values = values first and second_values = values second
  and third_values = values third in
  let point_count = Geometry.point_count first in
  let output = Array.make point_count 0. in
  for point = 0 to point_count - 1 do
    output.(point) <- (0.2 *. first_values.(point))
      +. (0.3 *. second_values.(point)) +. (0.5 *. third_values.(point))
  done;
  let attribute = Attribute.create_owned ~owner:Attribute.Point ~name:"value"
      (Attribute.Float output) |> get_ok in
  Geometry.with_attribute attribute first |> get_ok

let run_attribute_composite_reference_benchmarks () =
  let first, second, third = attribute_composite_fixture () in
  measure ~input_points:(Geometry.point_count first)
    "attribute_composite_reference_mean_scalar" (fun () ->
      reference_attribute_composite_mean first second third) geometry_output

let run_attribute_composite_benchmarks () =
  let first, second, third = attribute_composite_fixture () in
  let second_input = Ops.attribute_composite_input ~weight:0.3 second
  and third_input = Ops.attribute_composite_input ~weight:0.5 third in
  measure ~input_points:(Geometry.point_count first)
    "attribute_composite_mean_scalar" (fun () ->
      Ops.attribute_composite ~grain ~weight:0.2
        ~detail_attributes:"^*" ~primitive_attributes:"^*"
        ~point_attributes:"value" ~vertex_attributes:"^*"
        ~inputs:[second_input; third_input] first |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count first)
    "attribute_composite_mean_alpha_fields" (fun () ->
      Ops.attribute_composite ~grain ~weight:0.2 ~alpha_attribute:"alpha"
        ~detail_attributes:"^*" ~primitive_attributes:"^*"
        ~point_attributes:"P value Cd" ~vertex_attributes:"^*"
        ~allow_position:true ~inputs:[second_input; third_input] first |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count first)
    "attribute_composite_over_scalar" (fun () ->
      Ops.attribute_composite ~grain ~operation:Ops.Composite_over ~weight:0.2
        ~alpha_attribute:"alpha" ~detail_attributes:"^*"
        ~primitive_attributes:"^*" ~point_attributes:"value"
        ~vertex_attributes:"^*" ~inputs:[second_input; third_input] first
      |> get_ok) geometry_output

let attribute_mirror_fixture () =
  let point_count = max 2 (rows * columns) in
  let point_count = if point_count land 1 = 0 then point_count
    else point_count - 1 in
  let half = point_count / 2 in
  let x = Array.init point_count (fun point ->
    if point < half then -. (float_of_int (half - point) *. 0.001)
    else float_of_int (point - half + 1) *. 0.001) in
  let geometry = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn ~x
        ~y:(Array.init point_count (fun point ->
          float_of_int (point mod 257) *. 0.001))
        ~z:(Array.init point_count (fun point ->
          float_of_int (point mod 131) *. 0.001)))
      ~topology:(Topology.empty ~point_count) () |> get_ok in
  let color = Attribute.create_owned ~owner:Attribute.Point ~name:"Cd"
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.init point_count (fun point -> float_of_int (point mod 251)))
        ~y:(Array.init point_count (fun point -> float_of_int (point mod 127)))
        ~z:(Array.init point_count (fun point -> float_of_int (point mod 67)))
        ~w:(Array.make point_count 1.) |> get_ok)) |> get_ok in
  let mapping = Attribute.create_owned ~owner:Attribute.Point ~name:"mirror_map"
      (Attribute.Int (Array.init point_count (fun point ->
        if point < half then -1 else point_count - point - 1))) |> get_ok in
  let destination = Group.init ~owner:Group.Point ~name:"mirror_dest"
      point_count (fun point -> point >= half) in
  geometry |> Geometry.with_attribute color |> get_ok
  |> Geometry.with_attribute mapping |> get_ok
  |> Geometry.with_group destination |> get_ok

let reference_attribute_mirror_mapping geometry =
  let point_count = Geometry.point_count geometry in
  let mapping = Geometry.find_attribute ~owner:Attribute.Point "mirror_map"
      geometry |> Option.get |> Attribute.Private.storage |> function
    | Attribute.Int values -> values | _ -> assert false in
  let destination = Geometry.find_group ~owner:Group.Point "mirror_dest" geometry
      |> Option.get in
  let color = Geometry.find_attribute ~owner:Attribute.Point "Cd" geometry
      |> Option.get |> Attribute.Private.storage |> function
    | Attribute.Float4 values -> Packed.Float4.Private.view values
    | _ -> assert false in
  let x = Array.copy color.x and y = Array.copy color.y
  and z = Array.copy color.z and w = Array.copy color.w in
  for point = 0 to point_count - 1 do
    if Group.mem point destination then begin
      let source = mapping.(point) in
      x.(point) <- color.x.(source); y.(point) <- color.y.(source);
      z.(point) <- color.z.(source); w.(point) <- color.w.(source)
    end
  done;
  let color = Attribute.create_owned ~owner:Attribute.Point ~name:"Cd"
      (Attribute.Float4 (Packed.Float4.of_owned ~x ~y ~z ~w |> get_ok))
    |> get_ok in
  Geometry.with_attribute color geometry |> get_ok

let run_attribute_mirror_reference_benchmarks () =
  let geometry = attribute_mirror_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "attribute_mirror_reference_mapping_float4" (fun () ->
      reference_attribute_mirror_mapping geometry) geometry_output

let attribute_mirror_plane_fixture () =
  let point_count = max 2 (rows * columns) in
  let point_count = if point_count land 1 = 0 then point_count
    else point_count - 1 in
  let half = point_count / 2 in
  let source_index point = if point < half then point else point_count - point - 1 in
  let geometry = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:(Array.init point_count (fun point ->
          if point < half then -. (float_of_int (half - point) *. 0.001)
          else float_of_int (point - half + 1) *. 0.001))
        ~y:(Array.init point_count (fun point ->
          float_of_int (source_index point mod 257) *. 0.001))
        ~z:(Array.init point_count (fun point ->
          float_of_int (source_index point mod 131) *. 0.001)))
      ~topology:(Topology.empty ~point_count) () |> get_ok in
  let color = Attribute.create_owned ~owner:Attribute.Point ~name:"Cd"
      (Attribute.Float4 (Packed.Float4.of_owned
        ~x:(Array.init point_count (fun point -> float_of_int (point mod 251)))
        ~y:(Array.init point_count (fun point -> float_of_int (point mod 127)))
        ~z:(Array.init point_count (fun point -> float_of_int (point mod 67)))
        ~w:(Array.make point_count 1.) |> get_ok)) |> get_ok in
  Geometry.with_attribute color geometry |> get_ok

let run_attribute_mirror_benchmarks () =
  let geometry = attribute_mirror_fixture () in
  let destination = Geometry.find_group ~owner:Group.Point "mirror_dest" geometry
      |> Option.get in
  measure ~input_points:(Geometry.point_count geometry)
    "attribute_mirror_mapping_float4" (fun () ->
      Ops.attribute_mirror ~grain ~owner:Ops.Mirror_point_attributes
        ~method_:(Ops.Mirror_by_mapping {
          mapping_attribute = "mirror_map"; destination_group = destination })
        geometry |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count geometry)
    "attribute_mirror_mapping_float4_outputs" (fun () ->
      Ops.attribute_mirror ~grain ~owner:Ops.Mirror_point_attributes
        ~method_:(Ops.Mirror_by_mapping {
          mapping_attribute = "mirror_map"; destination_group = destination })
        ~output_mapping:"mirror_pair" ~source_group:"mirror_source"
        ~destination_group:"mirror_destination" geometry |> get_ok)
    geometry_output;
  let plane_geometry = attribute_mirror_plane_fixture () in
  measure ~input_points:(Geometry.point_count plane_geometry)
    "attribute_mirror_plane_float4" (fun () ->
      Ops.attribute_mirror ~grain ~owner:Ops.Mirror_point_attributes
        ~method_:(Ops.Mirror_by_plane { origin = Vec3.zero;
          normal = Vec3.unit_x; distance = 0.; tolerance = 1e-12 })
        plane_geometry |> get_ok) geometry_output

let rewire_vertices_fixture () =
  let requested = max 3 (rows * columns) in
  let point_count = requested - (requested mod 3) in
  let primitive_count = point_count / 3 in
  let topology = Topology.polygons_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (primitive_count + 1) (fun primitive ->
        primitive * 3)) |> get_ok in
  let geometry = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn
        ~x:(Array.init point_count (fun point -> float_of_int point *. 0.001))
        ~y:(Array.init point_count (fun point ->
          float_of_int (point mod 3) *. 0.25))
        ~z:(Array.init point_count (fun point ->
          float_of_int (point mod 97) *. 0.001)))
      ~topology () |> get_ok in
  let target = Attribute.create_owned ~owner:Attribute.Point ~name:"targetpt"
      (Attribute.Int (Array.init point_count (fun point ->
        if point mod 3 = 0 then point + 1 else -1))) |> get_ok in
  Geometry.with_attribute target geometry |> get_ok

let reference_rewire_vertices geometry =
  let topology = Topology.Private.view (Geometry.topology geometry) in
  let target = Geometry.find_attribute ~owner:Attribute.Point "targetpt" geometry
      |> Option.get |> Attribute.Private.storage |> function
    | Attribute.Int values -> values | _ -> assert false in
  let vertex_points = Array.copy topology.vertex_points in
  for vertex = 0 to Array.length vertex_points - 1 do
    let point = vertex_points.(vertex) in
    let destination = target.(point) in
    if destination >= 0 && destination < topology.point_count then
      vertex_points.(vertex) <- destination
  done;
  let output_topology = Topology.Private.create_validated_owned
      ~point_count:topology.point_count ~vertex_points
      ~primitive_offsets:(Array.copy topology.primitive_offsets)
      ~primitive_kinds:(Bytes.copy topology.primitive_kinds) in
  Geometry.create ~positions:(Geometry.positions geometry)
    ~topology:output_topology ~attributes:(Geometry.attributes geometry)
    ~groups:(Geometry.groups geometry) () |> get_ok

let run_rewire_vertices_reference_benchmarks () =
  let geometry = rewire_vertices_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "rewire_vertices_reference_point_direct" (fun () ->
      reference_rewire_vertices geometry) geometry_output

let run_rewire_vertices_benchmarks () =
  let geometry = rewire_vertices_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "rewire_vertices_point_direct" (fun () ->
      Ops.rewire_vertices ~grain ~keep_unused_points:true
        ~owner:Attribute.Point ~target_attribute:"targetpt" geometry |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count geometry)
    "rewire_vertices_point_cleanup_provenance" (fun () ->
      Ops.rewire_vertices ~grain ~delete_target_attribute:true
        ~original_point_attribute:"origpt" ~owner:Attribute.Point
        ~target_attribute:"targetpt" geometry |> get_ok) geometry_output;
  let point_count = Geometry.point_count geometry in
  let recursive = Attribute.create_owned ~owner:Attribute.Point ~name:"chain"
      (Attribute.Int (Array.init point_count (fun point ->
        if point mod 4 = 3 then -1 else point + 1))) |> get_ok in
  let recursive_geometry = Geometry.with_attribute recursive geometry |> get_ok in
  measure ~input_points:point_count "rewire_vertices_point_recursive" (fun () ->
    Ops.rewire_vertices ~grain ~recursive:true ~keep_unused_points:true
      ~owner:Attribute.Point ~target_attribute:"chain" recursive_geometry
    |> get_ok) geometry_output

let run_scatter_benchmarks () =
  let source = make_grid () in
  let source_points = Geometry.point_count source in
  let density = Attribute.create_owned ~name:"scatter_density"
      ~owner:Attribute.Point (Attribute.Float
        (Array.init source_points (fun point ->
          0.05 +. float_of_int (point mod 257) /. 257.))) |> get_ok in
  let weighted = Geometry.with_attribute density source |> get_ok in
  measure ~input_points:source_points "scatter_uniform_exact_count" (fun () ->
    Ops.scatter_surface ~grain ~count:scatter_count ~seed:73 source |> get_ok)
    geometry_output;
  measure ~input_points:source_points "scatter_density_provenance" (fun () ->
    Ops.scatter_surface ~grain ~count:scatter_count ~seed:73
      ~density:(Ops.scatter_density ~owner:Attribute.Point "scatter_density")
      ~point_pattern:"N scatter_density"
      ~source_primitive_attribute:"source_primitive"
      ~source_vertex_numbers_attribute:"source_vertices"
      ~source_vertex_weights_attribute:"source_weights" weighted |> get_ok)
    geometry_output

let run_group_benchmarks () =
  let source = make_grid () in
  let point_count = Geometry.point_count source
  and primitive_count = Geometry.primitive_count source in
  let width = columns + 1 in
  let point_seed = Group.init ~grain ~owner:Group.Point ~name:"point_seed"
      point_count (fun point -> point mod width = width / 2) in
  let point_seed_b = Group.init ~grain ~owner:Group.Point ~name:"point_seed_b"
      point_count (fun point -> point mod width = width / 3) in
  let primitive_seed = Group.init ~grain ~owner:Group.Primitive
      ~name:"primitive_seed" primitive_count (fun primitive ->
        primitive / (columns * 2) = rows / 2) in
  let point_source = Geometry.with_group point_seed source |> get_ok
  and primitive_source = Geometry.with_group primitive_seed source |> get_ok in
  let constrained_point_seed = Group.init ~grain ~owner:Group.Point
      ~name:"constrained_point_seed" point_count (fun point ->
        point = (rows / 2 * width) + (columns / 4)) in
  let constrained_point_region = Attribute.create_owned ~owner:Attribute.Point
      ~name:"expand_region" (Attribute.Int (Array.init point_count (fun point ->
        let column = point mod width in
        column * 8 / max 1 width))) |> get_ok in
  let constrained_point_container = Group.init ~grain ~owner:Group.Point
      ~name:"expand_container" point_count (fun point ->
        point mod width <= columns * 3 / 4) in
  let constrained_point_source = source
      |> Geometry.with_group constrained_point_seed |> get_ok
      |> Geometry.with_group constrained_point_container |> get_ok
      |> Geometry.with_attribute constrained_point_region |> get_ok in
  let constrained_primitive_seed = Group.init ~grain ~owner:Group.Primitive
      ~name:"constrained_primitive_seed" primitive_count (fun primitive ->
        primitive = (((rows / 2 * columns) + (columns / 4)) * 2)) in
  let constrained_primitive_region = Attribute.create_owned
      ~owner:Attribute.Primitive ~name:"expand_region"
      (Attribute.Int (Array.init primitive_count (fun primitive ->
        let column = (primitive / 2) mod columns in
        column * 8 / max 1 columns))) |> get_ok in
  let constrained_primitive_container = Group.init ~grain
      ~owner:Group.Primitive ~name:"expand_container" primitive_count
      (fun primitive -> (primitive / 2) mod columns <= columns * 3 / 4) in
  let vertex_count = Geometry.vertex_count source in
  let constrained_flow = Attribute.create_owned ~owner:Attribute.Vertex
      ~name:"expand_flow" (Attribute.Float3
        (Packed.Float3.Private.of_owned_exn
          ~x:(Array.make vertex_count 0.) ~y:(Array.make vertex_count 0.)
          ~z:(Array.make vertex_count 1.))) |> get_ok in
  let constrained_primitive_source = source
      |> Geometry.with_group constrained_primitive_seed |> get_ok
      |> Geometry.with_group constrained_primitive_container |> get_ok
      |> Geometry.with_attribute constrained_primitive_region |> get_ok
      |> Geometry.with_attribute constrained_flow |> get_ok in
  let point_ids = Attribute.create_owned ~owner:Attribute.Point ~name:"copy_id"
      (Attribute.Int (Array.init point_count Fun.id)) |> get_ok in
  let catalog_source = point_source
      |> Geometry.with_group point_seed_b |> get_ok
      |> Geometry.with_attribute point_ids |> get_ok in
  let promotion_source = List.init 8 (fun stripe ->
      Group.init ~grain ~owner:Group.Point
        ~name:(Printf.sprintf "promote_%02d" stripe) point_count
        (fun point -> point mod width = (stripe + 1) * width / 9))
      |> List.fold_left (fun geometry group ->
           Geometry.with_group group geometry |> get_ok) source in
  let boundary_ids = Attribute.create_owned ~owner:Attribute.Primitive
      ~name:"material_id" (Attribute.Int (Array.init primitive_count
        (fun primitive -> ((primitive / 2) mod columns) / 8))) |> get_ok in
  let boundary_source = Geometry.with_attribute boundary_ids source |> get_ok in
  let all_primitives = Group.init ~grain ~owner:Group.Primitive
      ~name:"all_primitives" primitive_count (fun _ -> true) in
  let boundary_source = Geometry.with_group all_primitives boundary_source
      |> get_ok in
  let name_palette = Array.init 64 (Printf.sprintf "piece_%02d") in
  let name_values = Array.init point_count (fun point ->
    name_palette.(point mod 64)) in
  let name_attribute = Attribute.create_owned ~owner:Attribute.Point
      ~name:"piece_name" (Attribute.Text name_values) |> get_ok in
  let name_source = Geometry.with_attribute name_attribute source |> get_ok in
  let grouped_name_source = Ops.groups_from_name ~grain ~owner:Attribute.Point
      ~attribute:"piece_name" name_source |> get_ok in
  let reversed_ids = Attribute.create_owned ~owner:Attribute.Point ~name:"copy_id"
      (Attribute.Int (Array.init point_count (fun point ->
        point_count - point - 1))) |> get_ok in
  let copy_target = Geometry.with_attribute reversed_ids source |> get_ok in
  (* Exclude shared cold-index construction from the per-operator warm-path
     medians. [topology_index] remains the dedicated cold-index benchmark. *)
  ignore (Topology_index.create (Geometry.topology source));
  measure ~input_points:point_count "group_promote_points_to_primitives_edge"
    (fun () -> Ops.group_promote ~grain ~keep_original:true
      ~name:"promoted" ~mode:Ops.Include_shared_edge
      ~source:Ops.Group_points ~destination:Ops.Group_primitives
      ~group:"point_seed" point_source |> get_ok) geometry_output;
  measure ~input_points:point_count
    "group_promote_points_to_primitives_attribute" (fun () ->
      Ops.group_promote ~grain ~keep_original:true
        ~output_attribute:"promoted_mask" ~mode:Ops.Include_shared_edge
        ~source:Ops.Group_points ~destination:Ops.Group_primitives
        ~group:"point_seed" point_source |> get_ok) geometry_output;
  let promotion_rules = [Ops.group_promote_rule ~new_name:"faces_*"
      ~keep_original:true ~mode:Ops.Include_shared_edge
      ~source:Ops.Group_points ~destination:Ops.Group_primitives
      ~pattern:"promote_*" ()] in
  measure ~input_points:point_count
    "group_promotions_points_to_primitives_wildcard_8" (fun () ->
      Ops.group_promotions ~grain ~rules:promotion_rules promotion_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_promote_boundary_primitives_to_edges"
    (fun () -> Ops.group_promote_boundary ~grain ~keep_original:true
      ~include_unshared_edges:true ~name:"primitive_outline"
      ~source:Ops.Group_primitives ~destination:Ops.Group_edges
      ~group:"primitive_seed" primitive_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_promote_boundary_primitives_to_points"
    (fun () -> Ops.group_promote_boundary ~grain ~keep_original:true
      ~include_unshared_edges:true ~name:"primitive_outline_points"
      ~source:Ops.Group_primitives ~destination:Ops.Group_points
      ~group:"primitive_seed" primitive_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_promote_boundary_attribute_edges"
    (fun () -> Ops.group_promote_boundary ~grain ~keep_original:true
      ~attributes:[{ Ops.boundary_attribute_owner = Attribute.Primitive;
        boundary_attribute_pattern = "material_id" }]
      ~name:"material_boundaries" ~source:Ops.Group_primitives
      ~destination:Ops.Group_edges ~group:"all_primitives" boundary_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_promote_points_to_edges_all"
    (fun () -> Ops.group_promote ~grain ~keep_original:true
      ~name:"promoted_edges" ~mode:Ops.Include_all
      ~source:Ops.Group_points ~destination:Ops.Group_edges
      ~group:"point_seed" point_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_expand_points_steps16"
    (fun () -> Ops.group_expand ~grain ~steps:16 ~owner:Ops.Group_points
      ~group:"point_seed" point_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_edge_depth_points_16"
    (fun () -> Ops.group_edge_depth ~grain ~depth:16
      ~point_group:"point_seed" ~name:"point_seed" point_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_edge_depth_points_128"
    (fun () -> Ops.group_edge_depth ~grain ~depth:128
      ~point_group:"point_seed" ~name:"point_seed" point_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_unshared_edges"
    (fun () -> Ops.group_unshared ~grain ~owner:Ops.Group_edges
      ~name:"unshared_edges" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_unshared_points"
    (fun () -> Ops.group_unshared ~grain ~owner:Ops.Group_points
      ~name:"unshared_points" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_unshared_primitives"
    (fun () -> Ops.group_unshared ~grain ~owner:Ops.Group_primitives
      ~name:"unshared_primitives" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_boundary_components"
    (fun () -> Ops.group_boundary_components ~grain ~prefix:"boundary"
      source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_expand_points_steps16_attribute"
    (fun () -> Ops.group_expand ~grain ~steps:16 ~step_attribute:"step"
      ~owner:Ops.Group_points ~group:"point_seed" point_source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_expand_primitives_edges_steps8"
    (fun () -> Ops.group_expand ~grain ~steps:8
      ~primitive_connectivity:Ops.Primitive_share_edges
      ~owner:Ops.Group_primitives ~group:"primitive_seed" primitive_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_expand_points_flood"
    (fun () -> Ops.group_expand ~grain ~flood:true ~owner:Ops.Group_points
      ~group:"point_seed" point_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_expand_points_flood_attribute"
    (fun () -> Ops.group_expand ~grain ~flood:true ~step_attribute:"step"
      ~owner:Ops.Group_points ~group:"point_seed" point_source |> get_ok)
    geometry_output;
  let connectivity_attributes = [{
      Ops.boundary_attribute_owner = Attribute.Point;
      boundary_attribute_pattern = "expand_region" }] in
  let point_collision = {
    Ops.expand_collision_owner = Ops.Group_points;
    expand_collision_group = "expand_container";
    expand_collision_contain = true;
    expand_collision_allow_boundary = true } in
  measure ~input_points:point_count "group_expand_points_constraints_flood"
    (fun () -> Ops.group_expand ~grain ~flood:true ~step_attribute:"step"
      ~connectivity_attributes ~collision:point_collision
      ~owner:Ops.Group_points ~group:"constrained_point_seed"
      constrained_point_source |> get_ok) geometry_output;
  let connectivity_attributes = [{
      Ops.boundary_attribute_owner = Attribute.Primitive;
      boundary_attribute_pattern = "expand_region" }] in
  let primitive_collision = {
    Ops.expand_collision_owner = Ops.Group_primitives;
    expand_collision_group = "expand_container";
    expand_collision_contain = true;
    expand_collision_allow_boundary = true } in
  measure ~input_points:point_count
    "group_expand_primitives_constraints_flood" (fun () ->
      Ops.group_expand ~grain ~flood:true ~step_attribute:"step"
        ~primitive_connectivity:Ops.Primitive_share_edges
        ~normal_spread:0.2
        ~normal_attribute:{ Ops.expand_normal_owner = Attribute.Vertex;
          expand_normal_name = "expand_flow" }
        ~connectivity_attributes ~collision:primitive_collision
        ~owner:Ops.Group_primitives ~group:"constrained_primitive_seed"
        constrained_primitive_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_range_points_filter"
    (fun () -> Ops.group_range ~grain ~owner:Ops.Group_points ~name:"range"
      ~filter:{ select = 5; of_ = 13; offset = 3 }
      (Ops.Range_from_ends { start = 17; end_offset = 23 }) catalog_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_range_points_disconnected"
    (fun () -> Ops.group_range ~grain ~owner:Ops.Group_points
      ~name:"connected_range"
      ~connectivity:(Ops.Range_disconnected { region = None })
      ~filter:{ select = 5; of_ = 13; offset = 3 }
      (Ops.Range_from_ends { start = 17; end_offset = 23 }) catalog_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_range_primitives_disconnected"
    (fun () -> Ops.group_range ~grain ~owner:Ops.Group_primitives
      ~name:"connected_partition"
      ~connectivity:(Ops.Range_disconnected { region = None })
      (Ops.Range_partition { partition = 1; partitions = 3 }) source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_range_points_attribute_copy_id"
    (fun () -> Ops.group_range ~grain ~owner:Ops.Group_points
      ~name:"attribute_range"
      ~connectivity:(Ops.Range_connected {
        connectivity_attributes = Some "copy_id";
        connectivity_tolerance = 1e-6;
        collision = None;
        region = None;
        remove_other_regions = true })
      (Ops.Range_start_end { start = 0; end_ = 0 }) catalog_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_range_primitives_attribute_material"
    (fun () -> Ops.group_range ~grain ~owner:Ops.Group_primitives
      ~name:"material_range"
      ~connectivity:(Ops.Range_connected {
        connectivity_attributes = Some "material_id";
        connectivity_tolerance = 1e-6;
        collision = None;
        region = None;
        remove_other_regions = true })
      (Ops.Range_start_end { start = 0; end_ = 0 }) boundary_source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_range_points_collision_keep"
    (fun () -> Ops.group_range ~grain ~owner:Ops.Group_points
      ~name:"collision_range"
      ~connectivity:(Ops.Range_connected {
        connectivity_attributes = None;
        connectivity_tolerance = 1e-6;
        collision = Some {
          Ops.collision_owner = Ops.Group_points;
          collision_pattern = "point_seed";
          keep_boundary = true };
        region = None;
        remove_other_regions = true })
      (Ops.Range_start_end { start = 0; end_ = 0 }) point_source
      |> get_ok) geometry_output;
  let range_rules_16 = List.init 16 (fun rule ->
    Ops.group_range_rule
      ~filter:{ select = (rule mod 5) + 1; of_ = 7; offset = rule - 8 }
      ~owner:Ops.Group_points ~name:(Printf.sprintf "range_%02d" rule)
      (Ops.Range_partition { partition = rule mod 7; partitions = 7 })) in
  measure ~input_points:point_count "group_ranges_points_global_16"
    (fun () -> Ops.group_ranges ~grain ~rules:range_rules_16 catalog_source
      |> get_ok) geometry_output;
  let boundary_attributes = [{ Ops.boundary_attribute_owner = Attribute.Primitive;
    boundary_attribute_pattern = "material_id" }] in
  measure ~input_points:point_count "group_attribute_boundary_edges"
    (fun () -> Ops.group_from_attribute_boundary ~grain
      ~attributes:boundary_attributes ~owner:Ops.Group_edges ~name:"seams"
      boundary_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_attribute_boundary_primitives"
    (fun () -> Ops.group_from_attribute_boundary ~grain
      ~attributes:boundary_attributes ~owner:Ops.Group_primitives
      ~name:"seam_faces" boundary_source |> get_ok) geometry_output;
  measure ~input_points:point_count "groups_from_name_points_64"
    (fun () -> Ops.groups_from_name ~grain ~owner:Attribute.Point
      ~attribute:"piece_name" name_source |> get_ok) geometry_output;
  measure ~input_points:point_count "name_from_groups_points_64"
    (fun () -> Ops.name_from_groups ~grain ~attribute:"round_trip"
      ~pattern:"piece_*" ~delete_groups:true ~owner:Attribute.Point
      grouped_name_source |> get_ok) geometry_output;
  let random_seed = Rand.seed 0x514e in
  measure ~input_points:point_count "group_random_points"
    (fun () -> Ops.group_random ~grain ~seed:random_seed ~probability:0.37
      ~owner:Ops.Group_points ~name:"random_points" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_random_points_seed_attribute"
    (fun () -> Ops.group_random ~grain ~seed:random_seed
      ~seed_attribute:"copy_id" ~probability:0.37 ~owner:Ops.Group_points
      ~name:"random_points" catalog_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_random_vertices"
    (fun () -> Ops.group_random ~grain ~seed:random_seed ~probability:0.37
      ~owner:Ops.Group_vertices ~name:"random_vertices" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_random_primitives"
    (fun () -> Ops.group_random ~grain ~seed:random_seed ~probability:0.37
      ~owner:Ops.Group_primitives ~name:"random_primitives" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_random_edges"
    (fun () -> Ops.group_random ~grain ~seed:random_seed ~probability:0.37
      ~owner:Ops.Group_edges ~name:"random_edges" source |> get_ok)
    geometry_output;
  let bounds_box = Ops.Bounds_box {
    minimum = Vec3.create (-28.) (-1.) (-24.);
    maximum = Vec3.create 31. 1. 27.;
  } and bounds_sphere = Ops.Bounds_sphere {
    center = Vec3.create 3. 0. (-4.); radius = 34.;
  } in
  measure ~input_points:point_count "group_bounds_points_box"
    (fun () -> Ops.group_bounds ~grain bounds_box ~owner:Ops.Group_points
      ~name:"bounded_points" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_bounds_vertices_sphere"
    (fun () -> Ops.group_bounds ~grain bounds_sphere ~owner:Ops.Group_vertices
      ~name:"bounded_vertices" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_bounds_primitives_partial_sphere"
    (fun () -> Ops.group_bounds ~grain ~containment:Ops.Partially_contained
      bounds_sphere ~owner:Ops.Group_primitives ~name:"bounded_primitives"
      source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_bounds_edges_partial_box"
    (fun () -> Ops.group_bounds ~grain ~containment:Ops.Partially_contained
      bounds_box ~owner:Ops.Group_edges ~name:"bounded_edges" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_normal_primitives_geometric"
    (fun () -> Ops.group_normal ~grain ~use_existing_normal:false
      ~direction:Vec3.unit_y
      ~spread_angle:(Float.pi /. 4.) ~owner:Ops.Group_primitives
      ~name:"normal_primitives" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_normal_points_geometric"
    (fun () -> Ops.group_normal ~grain ~use_existing_normal:false
      ~direction:Vec3.unit_y
      ~spread_angle:(Float.pi /. 4.) ~owner:Ops.Group_points
      ~name:"normal_points" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_normal_edges_geometric"
    (fun () -> Ops.group_normal ~grain ~use_existing_normal:false
      ~direction:Vec3.unit_y
      ~spread_angle:(Float.pi /. 4.) ~owner:Ops.Group_edges
      ~name:"normal_edges" source |> get_ok) geometry_output;
  if benchmark_enabled "group_normal_points_attribute" then begin
    let source_with_normals = Ops.normals ~grain source |> get_ok in
    measure ~input_points:point_count "group_normal_points_attribute"
      (fun () -> Ops.group_normal ~grain ~normal_attribute:"N"
        ~direction:Vec3.unit_y ~spread_angle:(Float.pi /. 4.)
        ~owner:Ops.Group_points ~name:"normal_points" source_with_normals
        |> get_ok) geometry_output
  end;
  if benchmark_enabled "group_non_planar_primitives" then begin
    let quad_source = source
        |> Ops.subdivide ~grain ~scheme:Ops.Bilinear |> get_ok
        |> Ops.mountain ~grain ~seed:0x67a1 ~height:0.04
             ~frequency:(Vec3.create 0.31 0.47 0.29) ~octaves:3 |> get_ok in
    measure ~input_points:(Geometry.point_count quad_source)
      "group_non_planar_primitives"
      (fun () -> Ops.group_non_planar ~grain ~tolerance:0.0001
        ~name:"non_planar" quad_source |> get_ok) geometry_output
  end;
  measure ~input_points:point_count "group_backface_primitives"
    (fun () -> Ops.group_backface ~grain
      ~viewpoint:(Vec3.create 0. (-100.) 0.) ~name:"backfaces" source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "group_edges_incident_angle"
    (fun () -> Ops.group_edges ~grain ~angle_basis:Ops.Incident_edges
      ~min_angle:(Float.pi /. 3.) ~max_angle:(2. *. Float.pi /. 3.)
      ~name:"incident_angles" source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_edges_dihedral_angle"
    (fun () -> Ops.group_edges ~grain ~angle_basis:Ops.Primitive_dihedral
      ~min_angle:0.01 ~name:"dihedral_angles" source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "group_combine_points_xor"
    (fun () -> Ops.group_combine ~grain ~owner:Ops.Group_points ~name:"combined"
      ~base:{ pattern = "point_seed*"; inverted = false }
      ~steps:[{ operation = Ops.Group_xor;
        operand = { pattern = "point_seed_b"; inverted = true } }]
      catalog_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_invert_points"
    (fun () -> Ops.group_invert ~owner:Ops.Group_points ~pattern:"point_seed*"
      catalog_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_rename_metadata"
    (fun () -> Ops.group_rename ~rules:[
      { rename_owner = Some Ops.Group_points; rename_pattern = "point_*";
        rename_replacement = "selected_*"; rename_conflict = Ops.Rename_error }]
      catalog_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_delete_metadata"
    (fun () -> Ops.group_delete ~rules:[
      { delete_owner = Some Ops.Group_points; delete_pattern = "point_seed_b" }]
      catalog_source |> get_ok) geometry_output;
  measure ~input_points:point_count "group_copy_points_index"
    (fun () -> Ops.group_copy ~grain ~rules:[
      { copy_owner = Ops.Group_points; copy_pattern = "point_seed*";
        copy_prefix = "copied_"; match_attribute = None }]
      ~source:catalog_source ~target:copy_target () |> get_ok) geometry_output;
  measure ~input_points:point_count "group_copy_points_attribute"
    (fun () -> Ops.group_copy ~grain ~rules:[
      { copy_owner = Ops.Group_points; copy_pattern = "point_seed*";
        copy_prefix = "copied_"; match_attribute = Some "copy_id" }]
      ~source:catalog_source ~target:copy_target () |> get_ok) geometry_output

let run_group_transfer_benchmarks () =
  let transfer_source = Ops.grid ~columns:300 ~rows:300 ~size:20. () |> get_ok in
  let transfer_points = Group.init ~grain ~owner:Group.Point
      ~name:"transfer_points" (Geometry.point_count transfer_source)
      (fun point -> point mod 301 < 23)
  and transfer_points_ordered = Group.ordered ~owner:Group.Point
      ~name:"transfer_points_ordered"
      ~length:(Geometry.point_count transfer_source)
      (Array.init (301 * 23) (fun index ->
        let reverse = (301 * 23) - 1 - index in
        ((reverse / 23) * 301) + (reverse mod 23))) |> Result.get_ok
  and transfer_primitives = Group.init ~grain ~owner:Group.Primitive
      ~name:"transfer_primitives" (Geometry.primitive_count transfer_source)
      (fun primitive -> primitive mod 31 < 5) in
  let transfer_source = transfer_source
      |> Geometry.with_group transfer_points |> get_ok
      |> Geometry.with_group transfer_points_ordered |> get_ok
      |> Geometry.with_group transfer_primitives |> get_ok
      |> Ops.group_edges ~grain ~name:"transfer_edges" ~min_length:0.09
           |> get_ok in
  let transfer_target = Ops.transform ~grain
      (Mat4.translation (Vec3.create 0.001 0. 0.001)) transfer_source in
  let transfer_points_rule = [{ Ops.transfer_owner = Ops.Group_points;
    transfer_pattern = "transfer_points"; transfer_prefix = "mapped_" }]
  and transfer_points_ordered_rule = [{ Ops.transfer_owner = Ops.Group_points;
    transfer_pattern = "transfer_points_ordered"; transfer_prefix = "mapped_" }]
  and transfer_primitives_rule = [{ Ops.transfer_owner = Ops.Group_primitives;
    transfer_pattern = "transfer_primitives"; transfer_prefix = "mapped_" }]
  and transfer_edges_rule = [{ Ops.transfer_owner = Ops.Group_edges;
    transfer_pattern = "transfer_edges"; transfer_prefix = "mapped_" }] in
  let transfer_input_points = Geometry.point_count transfer_source in
  measure ~input_points:transfer_input_points "group_transfer_points" (fun () ->
    Ops.group_transfer ~grain ~distance:0.01 ~rules:transfer_points_rule
      ~source:transfer_source ~target:transfer_target () |> get_ok)
    geometry_output;
  measure ~input_points:transfer_input_points "group_transfer_points_ordered"
    (fun () ->
      Ops.group_transfer ~grain ~distance:0.01
        ~rules:transfer_points_ordered_rule ~source:transfer_source
        ~target:transfer_target () |> get_ok)
    geometry_output;
  measure ~input_points:transfer_input_points "group_transfer_primitives"
    (fun () -> Ops.group_transfer ~grain ~distance:0.01
      ~rules:transfer_primitives_rule ~source:transfer_source
      ~target:transfer_target () |> get_ok) geometry_output;
  measure ~input_points:transfer_input_points "group_transfer_edges" (fun () ->
    Ops.group_transfer ~grain ~distance:0.01 ~rules:transfer_edges_rule
      ~source:transfer_source ~target:transfer_target () |> get_ok)
    geometry_output

let run_group_find_path_benchmarks () =
  let columns = 300 and rows = 300 in
  let source = Ops.grid ~columns ~rows ~size:20. () |> get_ok in
  let stride = columns + 1 in
  let point row column = (row * stride) + column in
  let pair_count = 16 in
  let pair_elements = Array.init (pair_count * 2) (fun index ->
    let row = (index / 2) * 18 in
    if index land 1 = 0 then point row 0 else point row columns) in
  let through_elements = Array.init 16 (fun index ->
    let row = index * 18 in
    point row (if index land 1 = 0 then 0 else columns)) in
  let primitive_pair_elements = Array.init (pair_count * 2) (fun index ->
    let row = (index / 2) * 18 in
    if index land 1 = 0 then (row * columns) * 2
    else (((row * columns) + columns - 1) * 2) + 1) in
  let pair_group = Group.ordered ~owner:Group.Point ~name:"pair_bases"
      ~length:(Geometry.point_count source) pair_elements |> Result.get_ok
  and through_group = Group.ordered ~owner:Group.Point ~name:"through_bases"
      ~length:(Geometry.point_count source) through_elements |> Result.get_ok
  and primitive_pair_group = Group.ordered ~owner:Group.Primitive
      ~name:"primitive_pair_bases" ~length:(Geometry.primitive_count source)
      primitive_pair_elements |> Result.get_ok
  and primitive_setup_group = Group.ordered ~owner:Group.Primitive
      ~name:"primitive_setup_base" ~length:(Geometry.primitive_count source)
      [|0|] |> Result.get_ok in
  let source = source |> Geometry.with_group pair_group |> get_ok
      |> Geometry.with_group through_group |> get_ok
      |> Geometry.with_group primitive_pair_group |> get_ok
      |> Geometry.with_group primitive_setup_group |> get_ok in
  measure ~input_points:(Geometry.point_count source) "group_find_path_pairs"
    (fun () -> Ops.group_find_path ~grain ~mode:Ops.Start_end_pairs
      ~avoid_self_intersection:false ~base:pair_group ~name:"pair_paths" source
      |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count source) "group_find_path_avoiding"
    (fun () -> Ops.group_find_path ~grain ~base:through_group
      ~name:"through_path" source |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count source)
    "group_find_path_primitive_setup"
    (fun () -> Ops.group_find_path ~grain ~base:primitive_setup_group
      ~name:"primitive_setup_path" source |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count source)
    "group_find_path_primitive_pairs"
    (fun () -> Ops.group_find_path ~grain ~mode:Ops.Start_end_pairs
      ~avoid_self_intersection:false ~base:primitive_pair_group
      ~name:"primitive_pair_paths" source |> get_ok) geometry_output

let run_unpack_benchmarks () =
  let copies = 4_096 in
  let source = Ops.box ~size:(Vec3.create 0.25 0.5 0.75) () |> get_ok
      |> Ops.group_edges ~grain ~name:"prototype_edges" |> get_ok in
  let matrices = Array.init copies (fun index ->
    let angle = float_of_int index *. 0.013 in
    Mat4.mul
      (Mat4.translation (Vec3.create
        (float_of_int (index mod 64) *. 0.4)
        (float_of_int (index / 64) *. 0.4)
        (sin angle *. 0.2)))
      (Mat4.mul (Mat4.rotation_y angle)
        (Mat4.scaling (Vec3.create 1. (0.75 +. 0.25 *. cos angle) 1.)))) in
  let legacy_materialize () =
    Array.to_list matrices
    |> List.map (fun matrix -> Ops.transform ~grain matrix source)
    |> Ops.merge ~grain
    |> get_ok in
  measure ~input_points:(Geometry.point_count source)
    "unpack_transform_merge_baseline" legacy_materialize geometry_output;
  measure ~input_points:(Geometry.point_count source) "unpack_packed"
    (fun () -> Ops.materialize_instances ~grain ~transforms:matrices source
      |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count source) "unpack_packed_raw"
    (fun () -> Ops.materialize_instances ~grain ~apply_transform:false
      ~transforms:matrices source |> get_ok)
    geometry_output;
  let dense = Ops.grid ~columns:500 ~rows:500 ~size:20. () |> get_ok in
  let dense_matrix = Mat4.mul (Mat4.translation (Vec3.create 2. 3. 4.))
      (Mat4.rotation ~axis:(Vec3.create 1. 2. 3.) 0.7) in
  measure ~input_points:(Geometry.point_count dense)
    "unpack_single_dense_transform_baseline"
    (fun () -> Ops.transform ~grain dense_matrix dense) geometry_output;
  measure ~input_points:(Geometry.point_count dense) "unpack_single_dense"
    (fun () -> Ops.materialize_instances ~grain ~transforms:[|dense_matrix|]
      dense |> get_ok)
    geometry_output

let run_transform_benchmarks () =
  let source = make_grid () |> Ops.normals ~grain ~owner:Attribute.Point
      |> get_ok in
  let point_count = Geometry.point_count source
  and primitive_count = Geometry.primitive_count source in
  let point_selection = Group.init ~grain ~owner:Group.Point
      ~name:"transform_points" point_count (fun point -> point mod 3 = 0) in
  let primitive_selection = Group.init ~grain ~owner:Group.Primitive
      ~name:"transform_primitives" primitive_count
      (fun primitive -> primitive mod 5 < 2) in
  let source = source |> Geometry.with_group point_selection |> get_ok
      |> Geometry.with_group primitive_selection |> get_ok in
  let matrix = Ops.compose_transform ~order:Ops.Transform_rts
      ~rotation_order:Ops.Transform_zyx
      ~translate:(Vec3.create 2. 3. 4.)
      ~rotate:(Vec3.create 0.2 (-0.4) 0.7)
      ~scale:(Vec3.create 1.3 0.8 1.1)
      ~shear:(Vec3.create 0.15 (-0.08) 0.12)
      ~pivot:(Vec3.create 0.3 (-0.2) 0.5) () |> get_ok in
  measure ~input_points:point_count "transform_selected_all" (fun () ->
      Ops.transform_selected ~grain matrix source |> get_ok) geometry_output;
  measure ~input_points:point_count "transform_selected_points_third" (fun () ->
      Ops.transform_selected ~grain
        ~selection:(Ops.Selected_points point_selection) matrix source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "transform_selected_primitives_two_fifths"
    (fun () -> Ops.transform_selected ~grain
      ~selection:(Ops.Selected_primitives primitive_selection) matrix source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "transform_selected_recompute_normals"
    (fun () -> Ops.transform_selected ~grain ~recompute_normals:true
      ~selection:(Ops.Selected_points point_selection) matrix source |> get_ok)
    geometry_output

let run_soft_transform_benchmarks () =
  let source = make_grid () in
  let point_count = Geometry.point_count source and width = columns + 1 in
  let seed = Group.init ~grain ~owner:Group.Point ~name:"soft_seed" point_count
      (fun point -> point = (rows / 2 * width) + (columns / 2)) in
  let authored = Attribute.create_owned ~owner:Attribute.Point
      ~name:"soft_authored" (Attribute.Float (Array.init point_count (fun point ->
        let column = point mod width in
        float_of_int column /. float_of_int (max 1 columns)))) |> get_ok in
  let source = source |> Geometry.with_group seed |> get_ok
      |> Geometry.with_attribute authored |> get_ok in
  let matrix = Ops.compose_transform ~translate:(Vec3.create 0. 1.5 0.)
      ~rotate:(Vec3.create 0. 0.35 0.) ~scale:(Vec3.create 0.8 1.2 0.8)
      ~pivot:(Vec3.create 0.2 0. (-0.1)) () |> get_ok in
  measure ~input_points:point_count "soft_transform_radius_cubic" (fun () ->
      Ops.soft_transform ~grain ~selection:(Ops.Selected_points seed)
        ~metric:Ops.Soft_radius ~falloff:Ops.Soft_cubic ~radius:20.
        ~falloff_attribute:"soft_weight" matrix source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "soft_transform_edge_cubic" (fun () ->
      Ops.soft_transform ~grain ~selection:(Ops.Selected_points seed)
        ~metric:Ops.Soft_edge ~falloff:Ops.Soft_cubic ~radius:20.
        ~falloff_attribute:"soft_weight" matrix source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "soft_transform_attribute_direct" (fun () ->
      Ops.soft_transform ~grain ~metric:(Ops.Soft_attribute {
        attribute = "soft_authored"; apply_rolloff = false })
        ~falloff_attribute:"soft_weight" matrix source |> get_ok)
    geometry_output

let run_distance_along_geometry_benchmarks () =
  let source = make_grid () in
  let point_count = Geometry.point_count source and width = columns + 1 in
  let start = Group.init ~grain ~owner:Group.Point ~name:"distance_start"
      point_count (fun point -> point = (rows / 2 * width) + (columns / 2)) in
  let affected = Group.init ~grain ~owner:Group.Point ~name:"distance_affected"
      point_count (fun point -> point mod 5 <> 0) in
  let source = source |> Geometry.with_group start |> get_ok
      |> Geometry.with_group affected |> get_ok in
  measure ~input_points:point_count "distance_along_edge_full_fixed_mask"
    (fun () -> Ops.distance_along_geometry ~grain
      ~start:(Ops.Selected_points start)
      ~radius:(Ops.Distance_fixed 20.) ~falloff:Ops.Soft_cubic
      ~mask_attribute:"distance_mask" source |> get_ok) geometry_output;
  measure ~input_points:point_count "distance_along_edge_bounded_mask_only"
    (fun () -> Ops.distance_along_geometry ~grain
      ~start:(Ops.Selected_points start) ~distance_attribute:None
      ~radius:(Ops.Distance_fixed 20.) ~falloff:Ops.Soft_cubic
      ~mask_attribute:"distance_mask" source |> get_ok) geometry_output;
  measure ~input_points:point_count "distance_along_edge_affected_maximum"
    (fun () -> Ops.distance_along_geometry ~grain
      ~start:(Ops.Selected_points start)
      ~affected:(Ops.Selected_points affected)
      ~radius:Ops.Distance_maximum ~falloff:Ops.Soft_quadratic
      ~mask_attribute:"distance_mask" source |> get_ok) geometry_output

let run_distance_from_geometry_benchmarks () =
  let source = make_grid ()
      |> Ops.transform ~grain (Mat4.translation (Vec3.create 0. 1.5 0.)) in
  let point_count = Geometry.point_count source in
  let affected = Group.init ~grain ~owner:Group.Point ~name:"distance_affected"
      point_count (fun point -> point mod 5 <> 0) in
  let reference = Ops.uv_sphere ~grain ~rings:96 ~segments:144 ~radius:28. ()
      |> get_ok in
  measure ~input_points:point_count "distance_from_points_full_fixed_mask"
    (fun () -> Ops.distance_from_geometry ~grain
      ~affected:(Ops.Selected_points affected)
      ~reference_kind:Ops.Distance_reference_points
      ~radius:(Ops.Distance_fixed 20.) ~falloff:Ops.Soft_cubic
      ~mask_attribute:"distance_mask" ~reference source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "distance_from_surface_full_fixed_mask"
    (fun () -> Ops.distance_from_geometry ~grain
      ~affected:(Ops.Selected_points affected)
      ~reference_kind:Ops.Distance_reference_primitives
      ~radius:(Ops.Distance_fixed 20.) ~falloff:Ops.Soft_cubic
      ~mask_attribute:"distance_mask" ~reference source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "distance_from_surface_bounded_mask_only"
    (fun () -> Ops.distance_from_geometry ~grain
      ~affected:(Ops.Selected_points affected)
      ~reference_kind:Ops.Distance_reference_primitives
      ~distance_attribute:None ~radius:(Ops.Distance_fixed 6.)
      ~falloff:Ops.Soft_cubic ~mask_attribute:"distance_mask"
      ~reference source |> get_ok) geometry_output;
  let index = Surface_index.create ~grain reference |> get_ok
  and queries = Geometry.positions source in
  let legacy_query () =
    let primitives = Array.make point_count (-1)
    and triangles = Array.make point_count (-1)
    and a = Array.make point_count 0. and b = Array.make point_count 0.
    and c = Array.make point_count 0.
    and distances = Array.make point_count Float.infinity in
    Surface_index.Private.closest_many_into ~grain index ~queries
      ~max_distance_squared:Float.infinity ~primitives ~triangles
      ~barycentric_a:a ~barycentric_b:b ~barycentric_c:c
      ~distances_squared:distances;
    distances in
  let distance_only_query () =
    let distances = Array.make point_count Float.infinity in
    Surface_index.Private.closest_distances_many_into ~grain index ~queries
      ~max_distance_squared:Float.infinity ~distances_squared:distances;
    distances in
  measure ~input_points:point_count "distance_from_surface_query_provenance_baseline"
    legacy_query float_array_output;
  measure ~input_points:point_count "distance_from_surface_query_distance_only"
    distance_only_query float_array_output

let run_distance_from_target_benchmarks () =
  let source = make_grid ()
      |> Ops.transform ~grain
           (Mat4.translation (Vec3.create 1.25 (-0.75) 2.5)) in
  let point_count = Geometry.point_count source in
  let affected = Group.init ~grain ~owner:Group.Point ~name:"distance_affected"
      point_count (fun point -> point mod 5 <> 0) in
  measure ~input_points:point_count "distance_from_target_spherical_full_fixed"
    (fun () -> Ops.distance_from_target ~grain
      ~affected:(Ops.Selected_points affected)
      ~projection:Ops.Distance_target_spherical
      ~origin:(Vec3.create 0.5 (-1.25) 2.)
      ~radius:(Ops.Distance_fixed 20.) ~falloff:Ops.Soft_cubic
      ~mask_attribute:"distance_mask" source |> get_ok) geometry_output;
  measure ~input_points:point_count "distance_from_target_cylindrical_mask_only"
    (fun () -> Ops.distance_from_target ~grain
      ~affected:(Ops.Selected_points affected)
      ~projection:Ops.Distance_target_cylindrical
      ~origin:(Vec3.create 0.5 (-1.25) 2.)
      ~direction:(Vec3.create 1. 2. (-3.)) ~distance_attribute:None
      ~radius:(Ops.Distance_fixed 20.) ~falloff:Ops.Soft_cubic
      ~mask_attribute:"distance_mask" source |> get_ok) geometry_output;
  measure ~input_points:point_count "distance_from_target_planar_signed_maximum"
    (fun () -> Ops.distance_from_target ~grain
      ~affected:(Ops.Selected_points affected)
      ~projection:Ops.Distance_target_planar
      ~origin:(Vec3.create 0.5 (-1.25) 2.)
      ~direction:(Vec3.create 1. 2. (-3.))
      ~metric:Ops.Distance_target_signed ~radius:Ops.Distance_maximum
      ~falloff:Ops.Soft_quadratic ~mask_attribute:"distance_mask" source
      |> get_ok) geometry_output

let run_sort_extended_benchmarks () =
  let source = make_grid () in
  let point_count = Geometry.point_count source in
  measure ~input_points:point_count "sort_extended_random_points"
    (fun () -> Ops.sort ~grain ~owner:Ops.Points ~key:(Ops.Random 918273L)
      source |> get_ok) geometry_output;
  measure ~input_points:point_count "sort_extended_indices_x"
    (fun () -> Ops.sort ~grain ~owner:Ops.Points ~key:Ops.X
      ~output_indices:"sort_rank" source |> get_ok) geometry_output;
  let ranked = Ops.sort ~grain ~owner:Ops.Points ~key:Ops.X
      ~output_indices:"sort_rank" source |> get_ok in
  measure ~input_points:point_count "sort_extended_reorder_by_index"
    (fun () -> Ops.sort ~grain ~owner:Ops.Points
      ~key:(Ops.Index_attribute "sort_rank") ranked |> get_ok) geometry_output;
  let ranked_y = Ops.sort ~grain ~owner:Ops.Points ~key:Ops.Y
      ~output_indices:"sort_rank" source |> get_ok in
  measure ~input_points:point_count "sort_extended_indices_combined_x_after_y"
    (fun () -> Ops.sort ~grain ~owner:Ops.Points ~key:Ops.X
      ~output_indices:"sort_rank" ~combine_indices:true ranked_y |> get_ok)
    geometry_output;
  measure ~input_points:point_count "sort_extended_by_vertex_order"
    (fun () -> Ops.sort ~grain ~owner:Ops.Points ~key:Ops.By_vertex_order source
      |> get_ok) geometry_output;
  measure ~input_points:point_count "sort_extended_by_primitive_index"
    (fun () -> Ops.sort ~grain ~owner:Ops.Points
      ~key:Ops.By_primitive_index source |> get_ok) geometry_output;
  measure ~input_points:point_count "sort_extended_spatial_locality"
    (fun () -> Ops.sort ~grain ~owner:Ops.Points ~key:Ops.Spatial_locality source
      |> get_ok) geometry_output

let run_blast_by_attribute_benchmarks () =
  let source = make_grid () in
  let point_count = Geometry.point_count source
  and primitive_count = Geometry.primitive_count source in
  let point_values = Array.init point_count (fun point ->
      float_of_int (point mod 1_009) /. 1_008.)
  and primitive_values = Array.init primitive_count (fun primitive ->
      (primitive * 17) mod 1_009) in
  let point_attribute = Attribute.create_owned ~name:"density"
      ~owner:Attribute.Point (Attribute.Float point_values) |> get_ok
  and primitive_attribute = Attribute.create_owned ~name:"class"
      ~owner:Attribute.Primitive (Attribute.Int primitive_values) |> get_ok in
  let source = source |> Geometry.with_attribute point_attribute |> get_ok
      |> Geometry.with_attribute primitive_attribute |> get_ok in
  let point_selection () = Group.init ~grain ~owner:Group.Point
      ~name:"blast_selection" point_count (fun point ->
        let value = point_values.(point) in value >= 0.35 && value <= 0.65) in
  let primitive_selection () = Group.init ~grain ~owner:Group.Primitive
      ~name:"blast_selection" primitive_count (fun primitive ->
        primitive_values.(primitive) < 400) in
  let point_base = Group.init ~grain ~owner:Group.Point ~name:"blast_base"
      point_count (fun point -> point mod 5 <> 0) in
  measure ~input_points:point_count "blast_by_attribute_baseline_point_group"
    (fun () -> Geometry.with_group (point_selection ()) source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "blast_by_attribute_baseline_point_delete"
    (fun () -> Ops.delete ~grain (point_selection ()) source |> get_ok)
    geometry_output;
  measure ~input_points:point_count
    "blast_by_attribute_baseline_primitive_delete_compact"
    (fun () -> Ops.delete ~grain ~compact_points:true
      (primitive_selection ()) source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "blast_by_attribute_point_group"
    (fun () -> Ops.blast_by_attribute ~grain ~owner:Ops.Blast_points
      ~attribute:"density"
      ~mode:(Ops.Blast_range { minimum = 0.35; maximum = 0.65 })
      ~output:(Ops.Blast_group "blast_selection") source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "blast_by_attribute_point_group_base_invert"
    (fun () -> Ops.blast_by_attribute ~grain ~base:point_base ~invert:true
      ~owner:Ops.Blast_points ~attribute:"density"
      ~mode:(Ops.Blast_range { minimum = 0.35; maximum = 0.65 })
      ~output:(Ops.Blast_group "blast_selection") source |> get_ok)
    geometry_output;
  measure ~input_points:point_count "blast_by_attribute_point_delete"
    (fun () -> Ops.blast_by_attribute ~grain ~owner:Ops.Blast_points
      ~attribute:"density"
      ~mode:(Ops.Blast_range { minimum = 0.35; maximum = 0.65 })
      ~output:Ops.Blast_delete source |> get_ok)
    geometry_output;
  measure ~input_points:point_count
    "blast_by_attribute_primitive_delete_compact"
    (fun () -> Ops.blast_by_attribute ~grain ~remove_unused_points:true
      ~owner:Ops.Blast_primitives ~attribute:"class"
      ~mode:(Ops.Blast_below 400.) ~output:Ops.Blast_delete source |> get_ok)
    geometry_output

type reference_crease_operation = Reference_crease_add | Reference_crease_set
  | Reference_crease_delete

let reference_crease ~index ~edges ~operation ~weight geometry =
  let index = Topology_index.Private.view index in
  let count = Geometry.vertex_count geometry in
  let existing = match Geometry.find_attribute ~owner:Attribute.Vertex
      "creaseweight" geometry with
    | None -> None
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> Some values
         | _ -> failwith "reference creaseweight storage") in
  let values = Array.init count (fun vertex ->
      let old = match existing with None -> 0. | Some values -> values.(vertex) in
      let edge = index.edge_of_vertex.(vertex) in
      if edge < 0 || not (Edge_group.mem edge edges) then old
      else match operation with
        | Reference_crease_add -> old +. weight
        | Reference_crease_set -> weight
        | Reference_crease_delete -> 0.) in
  let attribute = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex (Attribute.Float values) |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let run_crease_reference_benchmarks () =
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_quads ~columns ~rows
      ~size:100. () |> get_ok in
  let topology = Geometry.topology source in
  let index = Topology_index.create topology in
  let selected = Edge_group.init ~grain ~topology ~index ~name:"bench_edges"
      (fun edge -> edge mod 7 = 0) in
  let existing = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex
      (Attribute.Float (Array.init (Geometry.vertex_count source) (fun vertex ->
        if vertex mod 13 = 0 then 1.25 else 0.5))) |> get_ok in
  let attributed = Geometry.with_attribute existing source |> get_ok in
  let measure_reference name operation geometry weight =
    measure ~input_points:(Geometry.point_count geometry) name (fun () ->
      reference_crease ~index ~edges:selected ~operation ~weight geometry)
      geometry_output in
  measure_reference "crease_reference_set_sparse" Reference_crease_set source 2.;
  measure_reference "crease_reference_add_sparse" Reference_crease_add attributed 2.;
  measure_reference "crease_reference_delete_sparse" Reference_crease_delete
    attributed 0.

let run_crease_benchmarks () =
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_quads ~columns ~rows
      ~size:100. () |> get_ok in
  let topology = Geometry.topology source in
  let index = Topology_index.create topology in
  let selected = Edge_group.init ~grain ~topology ~index ~name:"bench_edges"
      (fun edge -> edge mod 7 = 0) in
  let existing = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex
      (Attribute.Float (Array.init (Geometry.vertex_count source) (fun vertex ->
        if vertex mod 13 = 0 then 1.25 else 0.5))) |> get_ok in
  let attributed = Geometry.with_attribute existing source |> get_ok in
  let measure_crease name operation geometry weight =
    measure ~input_points:(Geometry.point_count geometry) name (fun () ->
      Ops.crease ~grain ~edges:selected ~operation ~weight geometry |> get_ok)
      geometry_output in
  measure_crease "crease_set_sparse" Ops.Crease_set source 2.;
  measure_crease "crease_add_sparse" Ops.Crease_add attributed 2.;
  measure_crease "crease_delete_sparse" Ops.Crease_delete attributed 0.;
  measure ~input_points:(Geometry.point_count source) "crease_set_all" (fun () ->
    Ops.crease ~grain ~operation:Ops.Crease_set ~weight:2. source |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count source)
    "crease_set_sparse_vertex_color" (fun () ->
      Ops.crease ~grain ~edges:selected ~operation:Ops.Crease_set ~weight:2.
        ~add_vertex_color:true source |> get_ok) geometry_output

let[@inline] reference_fade_ramp knots value =
  if value <= 0. then snd knots.(0)
  else if value >= 1. then snd knots.(Array.length knots - 1)
  else begin
    let low = ref 0 and high = ref (Array.length knots - 1) in
    while !high - !low > 1 do
      let middle = (!low + !high) / 2 in
      if fst knots.(middle) <= value then low := middle else high := middle
    done;
    let x0, y0 = knots.(!low) and x1, y1 = knots.(!high) in
    y0 +. (((value -. x0) /. (x1 -. x0)) *. (y1 -. y0))
  end

let reference_attribute_fade ~points ~frame ~fade_in ~fade_hold ~fade_out
    ~fade_in_ramp ~fade_out_ramp geometry =
  let point_count = Geometry.point_count geometry in
  let float_values name =
    match Geometry.find_attribute ~owner:Attribute.Point name geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> values
         | _ -> failwith (name ^ " benchmark storage"))
    | None -> failwith (name ^ " benchmark attribute") in
  let source = float_values "fade"
  and starts = float_values "start_fade"
  and hold_scales = float_values "duration" in
  let output = Array.init point_count (fun point ->
    let source_value = source.(point) in
    if not (Group.mem point points) then source_value
    else
      let elapsed = frame -. starts.(point) in
      let hold = fade_hold *. hold_scales.(point) in
      let factor =
        if elapsed < 0. then 0.
        else if elapsed < fade_in && fade_in > 0. then
          reference_fade_ramp fade_in_ramp (elapsed /. fade_in)
        else if elapsed < fade_in +. hold then 1.
        else if elapsed < fade_in +. hold +. fade_out && fade_out > 0. then
          reference_fade_ramp fade_out_ramp
            ((elapsed -. fade_in -. hold) /. fade_out)
        else 0. in
      source_value *. factor) in
  let attribute = Attribute.create_owned ~name:"fade" ~owner:Attribute.Point
      (Attribute.Float output) |> get_ok in
  Geometry.with_attribute attribute geometry |> get_ok

let attribute_fade_benchmark_fixture () =
  let source = Ops.grid ~grain ~connectivity:Ops.Grid_quads ~columns ~rows
      ~size:100. () |> get_ok in
  let point_count = Geometry.point_count source in
  let float_attribute name values =
    Attribute.create_owned ~name ~owner:Attribute.Point
      (Attribute.Float values) |> get_ok in
  let fade = float_attribute "fade" (Array.init point_count (fun point ->
      0.25 +. (float_of_int (point mod 29) /. 31.)))
  and start = float_attribute "start_fade" (Array.init point_count (fun point ->
      float_of_int (point mod 181) *. 0.75))
  and duration = float_attribute "duration" (Array.init point_count (fun point ->
      0.25 +. (float_of_int (point mod 17) /. 16.))) in
  let source = source |> Geometry.with_attribute fade |> get_ok
      |> Geometry.with_attribute start |> get_ok
      |> Geometry.with_attribute duration |> get_ok in
  let points = Group.init ~grain ~owner:Group.Point ~name:"fade_points"
      point_count (fun point -> point mod 7 <> 0) in
  source, points

let run_attribute_fade_reference_benchmarks () =
  let source, points = attribute_fade_benchmark_fixture () in
  let point_count = Geometry.point_count source in
  let fade_in_ramp = [|0., 0.; 0.3, 0.08; 0.72, 0.9; 1., 1.|]
  and fade_out_ramp = [|0., 1.; 0.25, 0.96; 0.65, 0.18; 1., 0.|] in
  measure ~input_points:point_count "attribute_fade_reference_selected_ramps"
    (fun () -> reference_attribute_fade ~points ~frame:137.25 ~fade_in:8.
      ~fade_hold:24. ~fade_out:16. ~fade_in_ramp ~fade_out_ramp source)
    geometry_output

let run_attribute_fade_benchmarks () =
  let source, points = attribute_fade_benchmark_fixture () in
  let point_count = Geometry.point_count source in
  let fade_in_ramp = [0., 0.; 0.3, 0.08; 0.72, 0.9; 1., 1.]
  and fade_out_ramp = [0., 1.; 0.25, 0.96; 0.65, 0.18; 1., 0.] in
  let run ?points ?(visualize = false) name fade_in_ramp fade_out_ramp =
    measure ~input_points:point_count name (fun () ->
      Ops.attribute_fade ~grain ?points ~frame:137.25
        ~start_attribute:"start_fade" ~hold_scale_attribute:"duration"
        ~fade_in:8. ~fade_hold:24. ~fade_out:16. ~fade_in_ramp ~fade_out_ramp
        ~visualize source |> get_ok) geometry_output in
  run ~points "attribute_fade_selected_ramps" fade_in_ramp fade_out_ramp;
  run "attribute_fade_all_default_ramps" [0.,0.;1.,1.] [0.,1.;1.,0.];
  run ~points ~visualize:true "attribute_fade_selected_ramps_visualize"
    fade_in_ramp fade_out_ramp

let poly_cut_benchmark_fixture () =
  let curve_count = max 1 rows and points_per_curve = max 3 (columns + 1) in
  let point_count = curve_count * points_per_curve in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        float_of_int (point mod points_per_curve) *. 0.01))
      ~y:(Array.init point_count (fun point ->
        float_of_int (point / points_per_curve) *. 0.01))
      ~z:(Array.make point_count 0.) in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (curve_count + 1) (fun primitive ->
        primitive * points_per_curve))
      ~primitive_kinds:(Array.make curve_count Topology.Open_polyline)
      |> get_ok in
  let cut_signal = Attribute.create_owned ~owner:Attribute.Point
      ~name:"cut_signal" (Attribute.Float (Array.init point_count (fun point ->
        float_of_int (point mod 29) -. 14.5))) |> get_ok in
  let geometry = Geometry.create ~positions ~topology ~attributes:[cut_signal] ()
      |> get_ok in
  geometry, curve_count, points_per_curve

let reference_poly_cut_edges_remove geometry curve_count points_per_curve =
  let signal = match Geometry.find_attribute ~owner:Attribute.Point
      "cut_signal" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> values
         | _ -> failwith "PolyCut benchmark signal storage")
    | None -> failwith "PolyCut benchmark signal missing" in
  let fragments = ref [] in
  for primitive = curve_count - 1 downto 0 do
    let base = primitive * points_per_curve in
    let primitive_fragments = ref [] and first = ref 0 in
    for local = 0 to points_per_curve - 2 do
      let a = signal.(base + local) and b = signal.(base + local + 1) in
      if (a < 0. && b > 0.) || (a > 0. && b < 0.) then begin
        if local - !first + 1 >= 2 then
          primitive_fragments :=
            Array.init (local - !first + 1) (fun offset ->
              base + !first + offset) :: !primitive_fragments;
        first := local + 1
      end
    done;
    if points_per_curve - !first >= 2 then
      primitive_fragments :=
        Array.init (points_per_curve - !first) (fun offset ->
          base + !first + offset) :: !primitive_fragments;
    fragments := List.rev_append !primitive_fragments !fragments
  done;
  let fragments = !fragments in
  let primitive_count = List.length fragments in
  let primitive_offsets = Array.make (primitive_count + 1) 0 in
  List.iteri (fun primitive fragment ->
    primitive_offsets.(primitive + 1) <- primitive_offsets.(primitive)
      + Array.length fragment) fragments;
  let vertex_points = Array.of_list (List.concat_map Array.to_list fragments) in
  let topology = Topology.create_owned
      ~point_count:(Geometry.point_count geometry) ~vertex_points
      ~primitive_offsets
      ~primitive_kinds:(Array.make primitive_count Topology.Open_polyline)
      |> get_ok in
  Geometry.create ~positions:(Geometry.positions geometry) ~topology
    ~attributes:(Geometry.attributes geometry) () |> get_ok

let run_poly_cut_reference_benchmarks () =
  let geometry, curve_count, points_per_curve = poly_cut_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "poly_cut_reference_edges_remove_crossing" (fun () ->
      reference_poly_cut_edges_remove geometry curve_count points_per_curve)
    geometry_output

let run_poly_cut_benchmarks () =
  let geometry, _, _ = poly_cut_benchmark_fixture () in
  let point_count = Geometry.point_count geometry in
  measure ~input_points:point_count "poly_cut_edges_remove_crossing" (fun () ->
    Ops.poly_cut ~grain ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_remove
      ~detection:(Ops.Poly_cut_crossing {attribute="cut_signal"; value=0.})
      geometry |> get_ok) geometry_output;
  measure ~input_points:point_count "poly_cut_edges_cut_crossing" (fun () ->
    Ops.poly_cut ~grain ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_crossing {attribute="cut_signal"; value=0.})
      geometry |> get_ok) geometry_output;
  measure ~input_points:point_count "poly_cut_edges_cut_change" (fun () ->
    Ops.poly_cut ~grain ~element:Ops.Poly_cut_edges
      ~strategy:Ops.Poly_cut_cut
      ~detection:(Ops.Poly_cut_change {attribute="cut_signal"; threshold=3.})
      geometry |> get_ok) geometry_output

let separate_pieces_benchmark_fixture () =
  let piece_count = max 1 rows and points_per_piece = max 3 (columns + 1) in
  let point_count = piece_count * points_per_piece in
  let positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init point_count (fun point ->
        float_of_int (point mod points_per_piece) *. 0.002))
      ~y:(Array.init point_count (fun point ->
        sin (float_of_int (point mod points_per_piece) *. 0.013)))
      ~z:(Array.make point_count 0.) in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (piece_count + 1) (fun primitive ->
        primitive * points_per_piece))
      ~primitive_kinds:(Array.make piece_count Topology.Open_polyline)
      |> get_ok in
  let piece = Attribute.create_owned ~owner:Attribute.Primitive ~name:"piece"
      (Attribute.Int (Array.init piece_count Fun.id)) |> get_ok in
  Geometry.create ~positions ~topology ~attributes:[piece] () |> get_ok,
  piece_count, points_per_piece

let reference_separate_pieces ~gap geometry piece_count points_per_piece =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let minimum = Array.make piece_count Float.infinity
  and maximum = Array.make piece_count Float.neg_infinity in
  for point = 0 to Geometry.point_count geometry - 1 do
    let piece = point / points_per_piece and value = positions.x.(point) in
    minimum.(piece) <- min minimum.(piece) value;
    maximum.(piece) <- max maximum.(piece) value
  done;
  let translation = Array.make piece_count 0. and cursor = ref minimum.(0) in
  for piece = 0 to piece_count - 1 do
    let offset = !cursor -. minimum.(piece) in
    translation.(piece) <- offset;
    cursor := maximum.(piece) +. offset +. gap
  done;
  let x = Array.init (Geometry.point_count geometry) (fun point ->
      positions.x.(point) +. translation.(point / points_per_piece)) in
  let positions = Packed.Float3.Private.of_shared_exn ~x
      ~y:positions.y ~z:positions.z in
  let translation = Attribute.create_owned ~owner:Attribute.Primitive
      ~name:"piece_translation"
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:translation ~y:(Array.make piece_count 0.)
        ~z:(Array.make piece_count 0.))) |> get_ok in
  geometry |> Geometry.with_positions positions |> get_ok
  |> Geometry.with_attribute translation |> get_ok

let run_separate_pieces_reference_benchmarks () =
  let geometry, piece_count, points_per_piece =
    separate_pieces_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "separate_pieces_reference_primitive_int" (fun () ->
      reference_separate_pieces ~gap:0.01 geometry piece_count points_per_piece)
    geometry_output

let run_separate_pieces_benchmarks () =
  let geometry, _, _ = separate_pieces_benchmark_fixture () in
  measure ~input_points:(Geometry.point_count geometry)
    "separate_pieces_primitive_int" (fun () ->
      Ops.separate_pieces ~grain ~gap:0.01
        ~mode:Ops.Separate_pieces_separate ~piece_attribute:"piece" geometry
      |> get_ok) geometry_output

let run_curve_join_benchmarks () =
  let ordered_curve_count = 1_000 and ordered_segments = 200 in
  let ordered_points = ordered_curve_count * (ordered_segments + 1) in
  let ordered_positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init ordered_points (fun point ->
        let curve = point / (ordered_segments + 1)
        and local = point mod (ordered_segments + 1) in
        float_of_int ((curve * ordered_segments) + local) *. 0.001))
      ~y:(Array.init ordered_points (fun point ->
        let curve = point / (ordered_segments + 1)
        and local = point mod (ordered_segments + 1) in
        sin (float_of_int ((curve * ordered_segments) + local) *. 0.0007)))
      ~z:(Array.make ordered_points 0.) in
  let ordered_topology = Topology.create_owned ~point_count:ordered_points
      ~vertex_points:(Array.init ordered_points Fun.id)
      ~primitive_offsets:(Array.init (ordered_curve_count + 1)
        (fun primitive -> primitive * (ordered_segments + 1)))
      ~primitive_kinds:(Array.make ordered_curve_count Topology.Open_polyline)
      |> get_ok in
  let ordered_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point
      (Attribute.Float (Array.init ordered_points (fun point ->
        float_of_int point *. 0.001))) |> get_ok in
  let ordered_source = Geometry.create ~positions:ordered_positions
      ~topology:ordered_topology ~attributes:[ordered_weight] () |> get_ok
      |> Ops.group_edges ~grain ~name:"all_join_edges" |> get_ok in
  measure ~input_points:ordered_points "curve_join_ordered" (fun () ->
    Ops.join_curves ~grain ordered_source |> get_ok) geometry_output;
  let picked_ends = Array.init ordered_curve_count (fun order -> {
      Ops.primitive = (order * 37) mod ordered_curve_count;
      end_ = if order land 1 = 0 then Ops.Join_curve_start
        else Ops.Join_curve_end;
    }) in
  measure ~input_points:ordered_points "curve_join_picked_ends" (fun () ->
    Ops.join_curves ~grain ~picked_ends ordered_source |> get_ok)
    geometry_output;
  let closest_curve_count = 65_537 in
  let closest_point_count = closest_curve_count * 2 in
  let physical_part slot =
    if slot = 0 then 0 else 1 + ((slot * 40_503) land 65_535) in
  let x = Array.make closest_point_count 0.
  and y = Array.make closest_point_count 0.
  and z = Array.make closest_point_count 0. in
  for slot = 0 to closest_curve_count - 1 do
    let part = physical_part slot and point = slot * 2 in
    x.(point) <- float_of_int part;
    x.(point + 1) <- float_of_int (part + 1);
    y.(point) <- sin (float_of_int part *. 0.0007);
    y.(point + 1) <- sin (float_of_int (part + 1) *. 0.0007)
  done;
  let closest_topology = Topology.create_owned ~point_count:closest_point_count
      ~vertex_points:(Array.init closest_point_count Fun.id)
      ~primitive_offsets:(Array.init (closest_curve_count + 1)
        (fun primitive -> primitive * 2))
      ~primitive_kinds:(Array.make closest_curve_count Topology.Open_polyline)
      |> get_ok in
  let point_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point
      (Attribute.Float (Array.init closest_point_count (fun point ->
        float_of_int point *. 0.001))) |> get_ok
  and corner_id = Attribute.create_owned ~name:"corner_id"
      ~owner:Attribute.Vertex (Attribute.Int (Array.init closest_point_count Fun.id))
      |> get_ok
  and piece_id = Attribute.create_owned ~name:"piece_id"
      ~owner:Attribute.Primitive
      (Attribute.Int (Array.init closest_curve_count Fun.id)) |> get_ok
  and selected = Group.init ~owner:Group.Primitive ~name:"source_curves"
      closest_curve_count (fun _ -> true) in
  let closest_source = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology:closest_topology
      ~attributes:[point_weight; corner_id; piece_id] ~groups:[selected] ()
      |> get_ok |> Ops.group_edges ~grain ~name:"source_edges" |> get_ok in
  measure ~input_points:closest_point_count "curve_join_closest_ends" (fun () ->
    Ops.join_curves ~grain ~connect_closest_ends:true closest_source |> get_ok)
    geometry_output;
  measure ~input_points:closest_point_count
    "curve_join_closest_ends_subgroups_keep" (fun () ->
      Ops.join_curves ~grain ~connect_closest_ends:true ~group_size:128
        ~keep_originals:true closest_source |> get_ok)
    geometry_output

let () =
  Printf.printf
    "benchmark,points,domains,grain,repeats,median_seconds,allocated_bytes,promoted_bytes,major_bytes,cardinality,hash\n%!";
  if session_only then begin
    let graph = Sop.grid ~columns ~rows ~size:100. ()
        |> Sop.noise_displace ~seed:42 ~amplitude:0.8 ~frequency:0.16
        |> Sop.color_by_height ~low:low_color ~high:high_color in
    measure "session_first_cook" (fun () ->
      let session = make_session () in
      let geometry = match Session.cook session ~context:(make_context ()) graph with
        | Ok output -> output.geometry
        | Error error -> failwith (Diagnostic.error_to_string error) in
      Session.close session;
      geometry) geometry_output;
    exit 0
  end;
  (match benchmark_filter with
   | Some filter when String.starts_with ~prefix:"torus_generator_reference" filter ->
       run_torus_reference_benchmark ();
       exit 0
   | Some filter when String.starts_with ~prefix:"torus_generator" filter ->
       run_torus_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"tube_generator_reference" filter ->
       run_tube_reference_benchmark ();
       exit 0
   | Some filter when String.starts_with ~prefix:"tube_generator" filter ->
       run_tube_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"platonic_generator_reference" filter ->
       run_platonic_reference_benchmark ();
       exit 0
   | Some filter when String.starts_with ~prefix:"platonic_generator" filter ->
       run_platonic_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"spiral_generator_reference" filter ->
       run_spiral_reference_benchmark ();
       exit 0
   | Some filter when String.starts_with ~prefix:"spiral_generator" filter ->
       run_spiral_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"polywire" filter ->
       run_polywire_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"sweep_general" filter ->
       run_sweep_general_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"revolve" filter ->
       run_revolve_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"resample" filter ->
       run_resample_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"polyframe" filter ->
       run_polyframe_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"facet" filter ->
       run_facet_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"uv_sphere_generator" filter ->
       run_uv_sphere_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"box_generator" filter ->
       run_box_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"circle_generator" filter ->
       run_circle_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"grid_generator" filter ->
       run_grid_generator_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_extrude" filter ->
       run_poly_extrude_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_fill" filter ->
       run_poly_fill_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"clean" filter ->
       run_clean_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_pattern" filter ->
       run_attribute_pattern_benchmark ();
       exit 0
   | Some filter when String.starts_with ~prefix:"motion" filter ->
       run_motion_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"dissolve" filter ->
       run_dissolve_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_loft" filter ->
       run_poly_loft_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"skin" filter ->
       run_poly_loft_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_bridge" filter ->
       run_poly_bridge_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"enumerate" filter ->
       run_enumerate_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_lifecycle" filter ->
       run_attribute_lifecycle_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_copy" filter ->
       run_attribute_copy_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_combine" filter ->
       run_attribute_combine_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_interpolate" filter ->
       run_attribute_interpolate_benchmarks ();
       exit 0
   | Some filter when String.starts_with
       ~prefix:"attribute_promote_pattern" filter ->
       run_promote_pattern_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"measure" filter ->
       run_measure_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"connectivity" filter ->
       run_connectivity_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_blur" filter ->
       run_attribute_blur_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"smooth" filter ->
       run_smooth_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"ray" filter ->
       run_ray_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"fuse" filter
       || String.starts_with ~prefix:"snap_to_grid" filter ->
       run_fuse_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"bound" filter ->
       run_bound_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"match_size" filter ->
       run_match_size_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_randomize" filter
       || String.starts_with ~prefix:"attribute_remap" filter ->
       run_attribute_generate_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"normals_" filter
       || String.starts_with ~prefix:"peak" filter
       || String.starts_with ~prefix:"bend" filter
       || String.starts_with ~prefix:"point_jitter" filter
       || String.starts_with ~prefix:"mountain" filter ->
       run_deform_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_divide" filter ->
       run_edge_divide_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_collapse" filter ->
       run_edge_collapse_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"remesh" filter ->
       run_remesh_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"boolean_detect" filter ->
       run_boolean_detect_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"intersection_analysis" filter ->
       run_intersection_analysis_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_reduce" filter ->
       run_poly_reduce_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_bevel" filter ->
       run_poly_bevel_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"point_split" filter ->
       run_point_split_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"point_generate" filter ->
       run_point_generate_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"point_replicate" filter ->
       run_point_replicate_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_flip" filter ->
       run_edge_flip_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_cusp" filter ->
       run_edge_cusp_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_straighten" filter ->
       run_edge_straighten_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_equalize_reference" filter ->
       run_edge_equalize_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_equalize" filter ->
       run_edge_equalize_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_relax_reference" filter ->
       run_edge_relax_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_relax" filter ->
       run_edge_relax_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"blend_shapes_reference" filter ->
       run_blend_shapes_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"blend_shapes" filter ->
       run_blend_shapes_benchmarks ();
       exit 0
   | Some filter when String.starts_with
       ~prefix:"attribute_composite_reference" filter ->
       run_attribute_composite_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_composite" filter ->
       run_attribute_composite_benchmarks ();
       exit 0
   | Some filter when String.starts_with
       ~prefix:"attribute_mirror_reference" filter ->
       run_attribute_mirror_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_mirror" filter ->
       run_attribute_mirror_benchmarks ();
       exit 0
   | Some filter when String.starts_with
       ~prefix:"rewire_vertices_reference" filter ->
       run_rewire_vertices_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"rewire_vertices" filter ->
       run_rewire_vertices_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_transport_reference" filter ->
       run_edge_transport_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_transport_parent_reference"
       filter ->
       run_edge_transport_parent_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_transport_parent" filter ->
       run_edge_transport_parent_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"edge_transport" filter ->
       run_edge_transport_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"scatter" filter ->
       run_scatter_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"group_transfer" filter ->
       run_group_transfer_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"group_find_path" filter ->
       run_group_find_path_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"unpack" filter ->
       run_unpack_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"curve_join" filter ->
       run_curve_join_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"transform_selected" filter ->
       run_transform_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"soft_transform" filter ->
       run_soft_transform_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"distance_along" filter ->
       run_distance_along_geometry_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"distance_from_target" filter ->
       run_distance_from_target_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"sort_extended" filter ->
       run_sort_extended_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"blast_by_attribute" filter ->
       run_blast_by_attribute_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"crease_reference" filter ->
       run_crease_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"crease" filter ->
       run_crease_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_fade_reference" filter ->
       run_attribute_fade_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_fade" filter ->
       run_attribute_fade_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_cut_reference" filter ->
       run_poly_cut_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"poly_cut" filter ->
       run_poly_cut_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"separate_pieces_reference" filter ->
       run_separate_pieces_reference_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"separate_pieces" filter ->
       run_separate_pieces_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"distance_from" filter ->
       run_distance_from_geometry_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"group_" filter
       || String.starts_with ~prefix:"groups_from_name" filter
       || String.starts_with ~prefix:"name_from_groups" filter ->
       run_group_benchmarks ();
       exit 0
   | Some filter when String.starts_with ~prefix:"attribute_transfer" filter
       || String.starts_with ~prefix:"surface_index" filter ->
       run_transfer_benchmarks filter;
       exit 0
   | None | Some _ -> ());
  measure "grid" make_grid geometry_output;
  let line_count = (columns + 1) * (rows + 1) in
  measure "line_generator" (fun () ->
    Ops.line ~grain ~points:line_count ~origin:Vec3.zero
      ~direction:(Vec3.create 1. 2. 3.) ~length:100. () |> get_ok)
    geometry_output;
  if benchmark_filter = Some "line_generator" then exit 0;
  let source = make_grid () in
  measure ~input_points:(Geometry.point_count source) "reverse_all" (fun () ->
    Ops.reverse ~grain source |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count source) "reverse_shift_all" (fun () ->
    Ops.reverse ~grain ~operation:(Ops.Shift_vertices 1) source |> get_ok)
    geometry_output;
  let reverse_half = Group.init ~owner:Group.Primitive ~name:"reverse_half"
      (Geometry.primitive_count source) (fun primitive -> primitive land 1 = 0) in
  measure ~input_points:(Geometry.point_count source) "reverse_local_half" (fun () ->
    Ops.reverse ~grain ~primitives:reverse_half source |> get_ok) geometry_output;
  (match benchmark_filter with
   | Some filter when String.starts_with ~prefix:"reverse_" filter -> exit 0
   | None | Some _ -> ());
  let convert_line_source = Ops.group_edges ~grain ~name:"all_grid_edges"
      source |> get_ok in
  measure "convert_line_grid_edges" (fun () ->
    Ops.convert_line ~grain ~length_attribute:"edge_length"
      convert_line_source |> get_ok) geometry_output;
  if benchmark_filter = Some "convert_line" then exit 0;
  measure "convert_line_connect_path_composed" (fun () ->
    Ops.convert_line ~grain convert_line_source |> get_ok
    |> Ops.poly_path ~grain |> get_ok) geometry_output;
  if benchmark_filter = Some "convert_line_connect_path_composed" then exit 0;
  measure "convert_line_path_fused" (fun () ->
    Ops.convert_line ~grain ~connect_path:true ~maximum_distance:0.
      convert_line_source |> get_ok) geometry_output;
  if benchmark_filter = Some "convert_line_path_fused" then exit 0;
  measure "poly_path_grid" (fun () ->
    Ops.poly_path ~grain source |> get_ok) geometry_output;
  measure "poly_path_connect_grid_exact" (fun () ->
    Ops.poly_path ~grain ~connect_end_points:true ~maximum_distance:0.
      source |> get_ok) geometry_output;
  if benchmark_filter = Some "poly_path" then exit 0;
  let matrix = Mat4.mul (Mat4.translation (Vec3.create 2. 3. 4.))
      (Mat4.rotation ~axis:(Vec3.create 1. 2. 3.) 0.7) in
  measure "transform" (fun () -> Ops.transform ~grain matrix source) geometry_output;
  measure "noise_displace" (fun () ->
    Ops.noise_displace ~grain ~amplitude:0.8 ~frequency:0.16 ~seed:42 source
    |> get_ok) geometry_output;
  let displaced = Ops.noise_displace ~grain ~amplitude:0.8 ~frequency:0.16
      ~seed:42 source |> get_ok in
  measure "color_by_height" (fun () ->
    Ops.color_by_height ~grain ~low:low_color ~high:high_color displaced
    |> get_ok) geometry_output;
  measure "sort_points_x" (fun () ->
    Ops.sort ~grain ~owner:Ops.Points ~key:Ops.X source |> get_ok) geometry_output;
  measure "triangulate_triangles" (fun () -> Ops.triangulate source |> get_ok)
    geometry_output;
  if benchmark_enabled "triangulate_quads"
     || benchmark_enabled "triangulate_quads_local_half" then begin
    let quad_source = Ops.grid ~grain ~connectivity:Ops.Grid_quads
        ~columns ~rows ~size:100. () |> get_ok in
    measure ~input_points:(Geometry.point_count quad_source)
      "triangulate_quads" (fun () -> Ops.triangulate quad_source |> get_ok)
      geometry_output;
    let alternating = Group.init ~grain ~owner:Group.Primitive
        ~name:"triangulate_alternating"
        (Geometry.primitive_count quad_source)
        (fun primitive -> primitive land 1 = 0) in
    measure ~input_points:(Geometry.point_count quad_source)
      "triangulate_quads_local_half" (fun () ->
        Ops.triangulate ~grain ~primitives:alternating quad_source |> get_ok)
      geometry_output
  end;
  (match benchmark_filter with
   | Some filter when String.starts_with ~prefix:"triangulate" filter -> exit 0
   | None | Some _ -> ());
  measure "mesh_bridge_plain" (fun () -> Prismel_mesh.to_mesh source |> get_ok)
    mesh_output;
  let colored = Ops.color_by_height ~grain ~low:low_color ~high:high_color
      displaced |> get_ok in
  measure "mesh_bridge_colored" (fun () -> Prismel_mesh.to_mesh colored |> get_ok)
    mesh_output;
  measure "merge_pair" (fun () -> Ops.merge ~grain [source; source] |> get_ok)
    geometry_output;
  let prototype = Ops.box ~size:(Vec3.create 0.08 0.16 0.08) () |> get_ok
  and targets = Ops.grid ~columns:320 ~rows:320 ~size:100. () |> get_ok in
  measure "copy_to_points" (fun () ->
    Ops.copy_to_points ~grain ~source:prototype ~targets () |> get_ok)
    geometry_output;
  let target_count = Geometry.point_count targets in
  let transform_offsets = Array.init (target_count + 1) (fun index -> index * 16)
  and transform_values = Array.make (target_count * 16) 0. in
  for target = 0 to target_count - 1 do
    let first = target * 16 in
    transform_values.(first + 1) <- -1.;
    transform_values.(first + 4) <- 2.;
    transform_values.(first + 6) <- 0.25;
    transform_values.(first + 10) <- 0.5;
    transform_values.(first + 15) <- 1.
  done;
  let target_transform = Attribute.create_owned ~owner:Attribute.Point
      ~name:"transform" (Attribute.Float_array
        (Packed.Float_array.create_owned ~offsets:transform_offsets
          ~values:transform_values |> get_ok)) |> get_ok in
  let transformed_targets = Geometry.with_attribute target_transform targets
      |> get_ok in
  measure "copy_to_points_transform" (fun () ->
    Ops.copy_to_points ~grain ~source:prototype ~targets:transformed_targets ()
      |> get_ok) geometry_output;
  let source_half = Group.init ~owner:Group.Primitive ~name:"source_half"
      (Geometry.primitive_count prototype) (fun primitive ->
        primitive < Geometry.primitive_count prototype / 2)
  and target_half = Group.init ~grain ~owner:Group.Point ~name:"target_half"
      (Geometry.point_count targets) (fun point -> point land 1 = 0) in
  measure "copy_to_points_restricted" (fun () ->
    Ops.copy_to_points ~grain ~source_primitives:source_half
      ~target_points:target_half ~source:prototype ~targets () |> get_ok)
    geometry_output;
  let transfer_source = prototype
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Point
           ~name:"weight" (Attribute.Float
             (Array.make (Geometry.point_count prototype) 2.)) |> get_ok)
      |> get_ok
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Vertex
           ~name:"corner_gain" (Attribute.Float2 (Packed.Float2.of_owned
             ~x:(Array.make (Geometry.vertex_count prototype) 1.)
             ~y:(Array.make (Geometry.vertex_count prototype) 2.) |> get_ok))
           |> get_ok) |> get_ok
      |> Geometry.with_attribute (Attribute.create_owned
           ~owner:Attribute.Primitive ~name:"density"
           (Attribute.Float (Array.make (Geometry.primitive_count prototype) 3.))
           |> get_ok) |> get_ok in
  let transfer_targets = targets
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Point
           ~name:"weight" (Attribute.Float (Array.init target_count (fun index ->
             0.5 +. float_of_int (index land 31) /. 64.))) |> get_ok) |> get_ok
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Point
           ~name:"corner_gain" (Attribute.Float2 (Packed.Float2.of_owned
             ~x:(Array.init target_count (fun index ->
               float_of_int (index land 15) /. 16.))
             ~y:(Array.init target_count (fun index ->
               float_of_int (index land 7) /. 8.)) |> get_ok)) |> get_ok) |> get_ok
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Point
           ~name:"density" (Attribute.Float (Array.init target_count (fun index ->
             float_of_int (index land 63) /. 64.))) |> get_ok) |> get_ok in
  let transfer_rules = Ops.[
    { copy_target_pattern = "weight"; copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_multiply };
    { copy_target_pattern = "corner_gain";
      copy_target_owner = Copy_target_vertices;
      copy_target_operation = Copy_target_add };
    { copy_target_pattern = "density";
      copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_subtract };
  ] in
  measure "copy_to_points_target_attributes" (fun () ->
    Ops.copy_to_points ~grain ~target_attributes:transfer_rules
      ~source:transfer_source ~targets:transfer_targets () |> get_ok)
    geometry_output;
  let group_source = transfer_source
      |> Geometry.with_group (Group.init ~grain ~owner:Group.Point
           ~name:"active" (Geometry.point_count transfer_source)
           (fun point -> point land 1 = 0)) |> get_ok
      |> Geometry.with_group (Group.init ~grain ~owner:Group.Vertex
           ~name:"visible" (Geometry.vertex_count transfer_source)
           (fun vertex -> vertex land 3 <> 0)) |> get_ok
      |> Geometry.with_group (Group.init ~grain ~owner:Group.Primitive
           ~name:"selected" (Geometry.primitive_count transfer_source)
           (fun primitive -> primitive land 1 = 0)) |> get_ok in
  let group_targets = transfer_targets
      |> Geometry.with_group (Group.init ~grain ~owner:Group.Point
           ~name:"active" target_count (fun point -> point land 3 <> 0))
      |> get_ok
      |> Geometry.with_group (Group.init ~grain ~owner:Group.Point
           ~name:"visible" target_count (fun point -> point land 7 < 3))
      |> get_ok
      |> Geometry.with_group (Group.init ~grain ~owner:Group.Point
           ~name:"selected" target_count (fun point -> point land 15 < 5))
      |> get_ok in
  let group_rules = transfer_rules @ Ops.[
    { copy_target_pattern = "active"; copy_target_owner = Copy_target_points;
      copy_target_operation = Copy_target_add };
    { copy_target_pattern = "visible"; copy_target_owner = Copy_target_vertices;
      copy_target_operation = Copy_target_multiply };
    { copy_target_pattern = "selected";
      copy_target_owner = Copy_target_primitives;
      copy_target_operation = Copy_target_subtract };
  ] in
  measure "copy_to_points_target_groups" (fun () ->
    Ops.copy_to_points ~grain ~target_attributes:group_rules
      ~source:group_source ~targets:group_targets () |> get_ok)
    geometry_output;
  let piece_four_source = prototype
      |> Geometry.with_attribute (Attribute.create_owned
           ~owner:Attribute.Primitive ~name:"piece"
           (Attribute.Int (Array.init (Geometry.primitive_count prototype)
             (fun primitive -> primitive land 3))) |> get_ok) |> get_ok
  and piece_four_targets = targets
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Point
           ~name:"piece" (Attribute.Int (Array.init target_count
             (fun target -> target land 3))) |> get_ok) |> get_ok in
  measure ~input_points:target_count "copy_to_points_piece_4" (fun () ->
    Ops.copy_to_points ~grain ~piece_attribute:"piece"
      ~source:piece_four_source ~targets:piece_four_targets () |> get_ok)
    geometry_output;
  let many_piece_source = Ops.grid ~columns:33 ~rows:33 ~size:1. () |> get_ok in
  let many_piece_count = Geometry.primitive_count many_piece_source in
  let many_piece_source = many_piece_source
      |> Geometry.with_attribute (Attribute.create_owned
           ~owner:Attribute.Primitive ~name:"piece"
           (Attribute.Int (Array.init many_piece_count Fun.id)) |> get_ok)
      |> get_ok in
  let many_target_count = 16_384 in
  let many_piece_targets = Ops.points (Array.init many_target_count (fun target ->
      float_of_int (target land 127) *. 0.01,
      float_of_int (target lsr 7) *. 0.01, 0.))
      |> Geometry.with_attribute (Attribute.create_owned ~owner:Attribute.Point
           ~name:"piece" (Attribute.Int (Array.init many_target_count
             (fun target -> target mod many_piece_count))) |> get_ok) |> get_ok in
  measure ~input_points:many_target_count "copy_to_points_piece_many" (fun () ->
    Ops.copy_to_points ~grain ~piece_attribute:"piece"
      ~source:many_piece_source ~targets:many_piece_targets () |> get_ok)
    geometry_output;
  let modeling_grid = Ops.grid ~columns:200 ~rows:200 ~size:20. () |> get_ok in
  let wire_scale = Attribute.create_owned ~name:"wire_scale"
      ~owner:Attribute.Point
      (Attribute.Float (Array.init (Geometry.point_count modeling_grid)
        (fun point -> 0.5 +. (float_of_int (point mod 101) /. 200.)))) |> get_ok in
  let many_curve_spines = Geometry.with_attribute wire_scale modeling_grid
      |> get_ok |> Ops.convert_line ~grain |> get_ok in
  measure "sweep_many_curves" (fun () ->
    Ops.sweep_circle ~grain ~sides:8 ~scale_attribute:"wire_scale"
      ~radius:0.025 many_curve_spines |> get_ok) geometry_output;
  measure "sweep_caps_many_curves" (fun () ->
    Ops.sweep_circle ~grain ~sides:8 ~scale_attribute:"wire_scale" ~caps:true
      ~cap_group:"caps" ~radius:0.025 many_curve_spines |> get_ok)
    geometry_output;
  if benchmark_filter = Some "sweep_many" then exit 0;
  if benchmark_filter = Some "sweep_caps" then exit 0;
  measure "edge_group_topology_index_cold" (fun () ->
    Topology_index.create_uncached (Geometry.topology modeling_grid))
    topology_index_output;
  ignore (Topology_index.create (Geometry.topology modeling_grid));
  measure "edge_group_boundary" (fun () ->
    Ops.group_edges ~grain ~name:"boundary" ~incidence:Ops.Boundary_edge
      modeling_grid |> get_ok) geometry_output;
  measure "edge_group_angle" (fun () ->
    Ops.group_edges ~grain ~name:"angled" ~incidence:Ops.Manifold_edge
      ~min_angle:0.01 modeling_grid |> get_ok) geometry_output;
  let fully_edged_grid = Ops.group_edges ~grain ~name:"all_edges" modeling_grid
      |> get_ok in
  measure "edge_group_duplicate_plain_4" (fun () ->
    Ops.duplicate ~grain ~copies:3
      ~transform:(Mat4.translation (Vec3.create 0. 0.2 0.))
      modeling_grid |> get_ok) geometry_output;
  measure "edge_group_duplicate_4" (fun () ->
    Ops.duplicate ~grain ~copies:3
      ~transform:(Mat4.translation (Vec3.create 0. 0.2 0.))
      fully_edged_grid |> get_ok) geometry_output;
  let planar_projection = Ops.Planar {
      origin = Vec3.zero;
      u_axis = Vec3.create 20. 0. 0.;
      v_axis = Vec3.create 0. 0. 20.;
    } in
  measure "uv_project_planar" (fun () ->
    Ops.uv_project ~grain planar_projection modeling_grid |> get_ok)
    geometry_output;
  let projected_grid = Ops.uv_project ~grain planar_projection modeling_grid
      |> get_ok in
  measure "uv_transform_vertex" (fun () ->
    Ops.uv_transform ~grain ~owner:Attribute.Vertex
      ~scale:(Vec2.create 4. 3.) ~angle:0.13 projected_grid |> get_ok)
    geometry_output;
  measure "uv_auto_seam_grid" (fun () ->
    Ops.uv_auto_seam ~grain ~angle:(Float.pi /. 4.) ~existing_uv:"uv"
      ~island_attribute:"uv_island" projected_grid |> get_ok)
    geometry_output;
  let seamed_grid = Ops.uv_auto_seam ~grain ~angle:(Float.pi /. 4.)
      ~existing_uv:"uv" ~island_attribute:"uv_island" projected_grid |> get_ok in
  let grid_seams = Geometry.find_edge_group "uv_seams" seamed_grid
      |> Option.get in
  measure "uv_unitize_islands" (fun () ->
    Ops.uv_unitize ~grain ~edge_seams:grid_seams Ops.Islands seamed_grid |> get_ok)
    geometry_output;
  measure "uv_flatten_grid" (fun () ->
    Ops.uv_flatten ~grain ~iterations:uv_iterations ~tolerance:1e-7 modeling_grid
    |> get_ok) geometry_output;
  let flattened_grid = Ops.uv_flatten ~grain ~iterations:uv_iterations ~tolerance:1e-7
      modeling_grid |> get_ok in
  measure "uv_relax_grid" (fun () ->
    Ops.uv_relax ~grain ~iterations:uv_iterations ~tolerance:1e-7 flattened_grid
    |> get_ok) geometry_output;
  if benchmark_filter = Some "uv_flatten" || benchmark_filter = Some "uv_relax"
  then exit 0;
  let uv_sphere = Ops.uv_sphere ~segments:512 ~rings:256 ~radius:2. ()
      |> get_ok in
  measure "uv_project_spherical_seams" (fun () ->
    Ops.uv_project ~grain
      (Ops.Spherical { origin = Vec3.zero; axis = Vec3.unit_y;
        seam = Vec3.unit_x }) uv_sphere |> get_ok)
    geometry_output;
  if benchmark_filter = Some "uv_" then exit 0;
  measure "duplicate_grid_8" (fun () ->
    Ops.duplicate ~grain ~copies:8
      ~transform:(Mat4.mul (Mat4.translation (Vec3.create 0. 0.2 0.))
        (Mat4.rotation_y 0.03)) modeling_grid |> get_ok) geometry_output;
  let duplicate_selection = Group.init ~owner:Group.Primitive
      ~name:"duplicate_selection" (Geometry.primitive_count modeling_grid)
      (fun primitive -> primitive land 1 = 0) in
  measure "duplicate_selected_grid_8" (fun () ->
    Ops.duplicate ~grain ~copies:8 ~primitives:duplicate_selection
      ~copy_group_prefix:"copy_"
      ~transform:(Mat4.mul (Mat4.translation (Vec3.create 0. 0.2 0.))
        (Mat4.rotation_y 0.03)) modeling_grid |> get_ok) geometry_output;
  measure "sort_primitives_x" (fun () ->
    Ops.sort ~grain ~descending:true ~owner:Ops.Primitives ~key:Ops.X
      modeling_grid |> get_ok) geometry_output;
  measure "topology_index" (fun () ->
    Topology_index.create (Geometry.topology modeling_grid)) topology_index_output;
  measure "spatial_index" (fun () ->
    Spatial_index.create ~grain (Geometry.positions modeling_grid) |> get_ok)
    spatial_index_output;
  measure "surface_index" (fun () ->
    Surface_index.create modeling_grid |> get_ok) surface_index_output;
  measure "attribute_promote_point_primitive" (fun () ->
    Attribute_ops.promote ~grain ~source:Attribute.Point
      ~destination:Attribute.Primitive ~name:"N" modeling_grid |> get_ok)
    geometry_output;
  let promote_count = Geometry.point_count source in
  let promote_value = Attribute.create_owned ~name:"promote_value"
      ~owner:Attribute.Point (Attribute.Int (Array.init promote_count
        (fun point -> (point * 17) mod 101))) |> get_ok
  and promote_piece = Attribute.create_owned ~name:"promote_piece"
      ~owner:Attribute.Point (Attribute.Int (Array.init promote_count
        (fun point -> point / 64))) |> get_ok in
  let promote_source = source
      |> Geometry.with_attribute promote_value |> get_ok
      |> Geometry.with_attribute promote_piece |> get_ok in
  measure "attribute_promote_mode_detail" (fun () ->
    Attribute_ops.promote ~grain ~method_:Attribute_ops.Mode
      ~source:Attribute.Point ~destination:Attribute.Detail
      ~name:"promote_value" promote_source |> get_ok) geometry_output;
  measure "attribute_promote_median_detail" (fun () ->
    Attribute_ops.promote ~grain ~method_:Attribute_ops.Median
      ~source:Attribute.Point ~destination:Attribute.Detail
      ~name:"promote_value" promote_source |> get_ok) geometry_output;
  measure "attribute_promote_piece_mode" (fun () ->
    Attribute_ops.promote ~grain ~method_:Attribute_ops.Mode
      ~piece_attribute:"promote_piece" ~into:"piece_mode" ~delete_source:false
      ~source:Attribute.Point ~destination:Attribute.Point
      ~name:"promote_value" promote_source |> get_ok) geometry_output;
  let transfer_target = Ops.transform ~grain
      (Mat4.translation (Vec3.create 0.015 0. 0.012)) modeling_grid in
  let point_source_group = Group.init ~owner:Group.Point ~name:"point_source"
      (Geometry.point_count modeling_grid) (fun _ -> true)
  and point_target_group = Group.init ~owner:Group.Point ~name:"point_target"
      (Geometry.point_count transfer_target) (fun _ -> true) in
  measure "attribute_transfer_inverse4" (fun () ->
    Attribute_ops.transfer_points ~grain ~names:["N"]
      ~mode:(Attribute_ops.Inverse_distance { neighbors = 4; power = 2. })
      ~max_distance:0.2 ~source_points:point_source_group
      ~target_points:point_target_group ~source:modeling_grid
      ~target:transfer_target () |> get_ok)
    geometry_output;
  let delete_half = Group.init ~owner:Group.Primitive ~name:"delete_half"
      (Geometry.primitive_count modeling_grid)
      (fun primitive -> primitive < Geometry.primitive_count modeling_grid / 2) in
  measure "delete_primitives_compact" (fun () ->
    Ops.delete_primitives ~grain ~compact_points:true delete_half modeling_grid
    |> get_ok) geometry_output;
  measure "delete_primitives_keep_points" (fun () ->
    Ops.delete ~grain delete_half modeling_grid |> get_ok) geometry_output;
  let modeling_positions = Packed.Float3.Private.view
      (Geometry.positions modeling_grid) in
  let delete_left_points = Group.init ~owner:Group.Point ~name:"left"
      (Geometry.point_count modeling_grid)
      (fun point -> modeling_positions.x.(point) < 0.) in
  measure "delete_points_destroy_compact" (fun () ->
    Ops.delete ~grain ~compact_points:true delete_left_points modeling_grid
    |> get_ok) geometry_output;
  measure "bounding_box" (fun () ->
    Ops.bounding_box ~grain ~padding:(Vec3.create 0.1 0.1 0.1) modeling_grid
    |> get_ok) geometry_output;
  let match_target = Ops.box ~size:(Vec3.create 8. 4. 12.) () |> get_ok in
  measure "match_size_contain" (fun () ->
    Ops.match_size ~grain ~fit:Ops.Contain ~target:match_target modeling_grid
    |> get_ok) geometry_output;
  let clip_grid = source in
  let clip_input_points = Geometry.point_count clip_grid in
  measure ~input_points:clip_input_points "clip_half_grid" (fun () ->
    Ops.clip ~grain ~keep:Ops.Above ~clipped_group:"cut"
      ~origin:(Vec3.create 0.123 0. 0.) ~normal:Vec3.unit_x clip_grid
    |> get_ok) geometry_output;
  let clip_vertex_count = Geometry.vertex_count clip_grid
  and clip_primitive_count = Geometry.primitive_count clip_grid in
  let clip_uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init clip_vertex_count (fun index ->
          float_of_int (index mod 3) *. 0.5))
        ~y:(Array.init clip_vertex_count (fun index ->
          float_of_int ((index / 3) land 1))) |> get_ok)) |> get_ok
  and clip_density = Attribute.create_owned ~name:"density"
      ~owner:Attribute.Primitive
      (Attribute.Float (Array.init clip_primitive_count (fun index ->
        float_of_int (index mod 97) /. 96.))) |> get_ok in
  let clip_attribute_grid = clip_grid
      |> Geometry.with_attribute clip_uv |> get_ok
      |> Geometry.with_attribute clip_density |> get_ok
      |> Ops.color_by_height ~grain ~low:low_color ~high:high_color |> get_ok in
  let deletion_quads = Ops.subdivide ~grain ~scheme:Ops.Bilinear
      clip_attribute_grid |> get_ok in
  measure "surface_index_quads" (fun () ->
    Surface_index.create deletion_quads |> get_ok) surface_index_output;
  let delete_quad_corners = Group.init ~owner:Group.Vertex
      ~name:"sparse_corners" (Geometry.vertex_count deletion_quads)
      (fun vertex -> vertex mod 16 = 0) in
  measure "delete_vertices_heal_quads_attributes" (fun () ->
    Ops.delete ~grain ~policy:Ops.Heal_primitives delete_quad_corners
      deletion_quads |> get_ok) geometry_output;
  let surface_target = Ops.transform ~grain
      (Mat4.translation (Vec3.create 0.015 0.2 0.012)) modeling_grid in
  let surface_specs = [
    Attribute_ops.surface_attribute ~owner:Attribute.Point "Cd";
    Attribute_ops.surface_attribute ~owner:Attribute.Vertex "uv";
    Attribute_ops.surface_attribute ~owner:Attribute.Primitive "density";
  ] in
  let surface_source_group = Group.init ~owner:Group.Primitive
      ~name:"surface_source" (Geometry.primitive_count clip_attribute_grid)
      (fun _ -> true)
  and surface_target_group = Group.init ~owner:Group.Point
      ~name:"surface_target" (Geometry.point_count surface_target)
      (fun _ -> true) in
  measure "attribute_transfer_surface" (fun () ->
    Attribute_ops.transfer_surface ~grain ~max_distance:0.1 ~blend_width:0.4
      ~falloff:Attribute_ops.Smoothstep ~source_primitives:surface_source_group
      ~target_points:surface_target_group
      ~distance_attribute:"surface_distance" ~attributes:surface_specs
      ~source:clip_attribute_grid ~target:surface_target () |> get_ok)
    geometry_output;
  let surface_target_vertices = Group.init ~owner:Group.Vertex
      ~name:"surface_target_vertices" (Geometry.vertex_count surface_target)
      (fun _ -> true)
  and surface_target_primitives = Group.init ~owner:Group.Primitive
      ~name:"surface_target_primitives" (Geometry.primitive_count surface_target)
      (fun _ -> true) in
  measure "attribute_transfer_primitives" (fun () ->
    Attribute_ops.transfer_primitives ~grain ~names:["density"]
      ~mode:(Attribute_ops.Inverse_distance { neighbors = 4; power = 2. })
      ~max_distance:0.5 ~source_primitives:surface_source_group
      ~target_primitives:surface_target_primitives
      ~source:clip_attribute_grid ~target:surface_target () |> get_ok)
    geometry_output;
  measure "attribute_transfer_vertices" (fun () ->
    Attribute_ops.transfer_vertices ~grain ~names:["uv"] ~max_distance:0.5
      ~source_primitives:surface_source_group
      ~target_vertices:surface_target_vertices
      ~source:clip_attribute_grid ~target:surface_target () |> get_ok)
    geometry_output;
  measure "attribute_transfer_surface_vertices" (fun () ->
    Attribute_ops.transfer_surface ~grain ~max_distance:0.1 ~blend_width:0.4
      ~target_owner:Attribute.Vertex ~target_elements:surface_target_vertices
      ~distance_attribute:"surface_distance" ~attributes:surface_specs
      ~source:clip_attribute_grid ~target:surface_target () |> get_ok)
    geometry_output;
  measure "attribute_transfer_surface_primitives" (fun () ->
    Attribute_ops.transfer_surface ~grain ~max_distance:0.1 ~blend_width:0.4
      ~target_owner:Attribute.Primitive
      ~target_elements:surface_target_primitives
      ~distance_attribute:"surface_distance" ~attributes:surface_specs
      ~source:clip_attribute_grid ~target:surface_target () |> get_ok)
    geometry_output;
  measure ~input_points:clip_input_points "clip_half_grid_attributes" (fun () ->
    Ops.clip ~grain ~keep:Ops.Above ~clipped_group:"cut"
      ~origin:(Vec3.create 0.123 0. 0.) ~normal:Vec3.unit_x
      clip_attribute_grid |> get_ok) geometry_output;
  let clip_selected_third = Group.init ~grain ~owner:Group.Primitive
      ~name:"clip_selected_third" (Geometry.primitive_count clip_attribute_grid)
      (fun primitive -> primitive < Geometry.primitive_count clip_attribute_grid / 3) in
  measure ~input_points:clip_input_points "clip_selected_third_attributes"
    (fun () ->
      Ops.clip ~grain ~keep:Ops.Above
        ~selection:(Ops.Selected_primitives clip_selected_third)
        ~clipped_group:"cut"
        ~origin:(Vec3.create 0.123 0. 0.) ~normal:Vec3.unit_x
        clip_attribute_grid |> get_ok) geometry_output;
  measure ~input_points:clip_input_points "clip_selected_third_attributes_edges"
    (fun () ->
      Ops.clip ~grain ~keep:Ops.Above
        ~selection:(Ops.Selected_primitives clip_selected_third)
        ~clipped_group:"cut" ~clipped_edge_group:"clip_edges"
        ~origin:(Vec3.create 0.123 0. 0.) ~normal:Vec3.unit_x
        clip_attribute_grid |> get_ok) geometry_output;
  if benchmark_enabled "clip_custom_attribute_distance_edges" then begin
    let clip_positions = Packed.Float3.Private.view
        (Geometry.positions clip_attribute_grid) in
    let clip_field = Attribute.create_owned ~name:"clip_field"
        ~owner:Attribute.Point
        (Attribute.Float4 (Packed.Float4.of_owned
          ~x:(Array.init clip_input_points (fun point ->
            clip_positions.x.(point) +. (0.2 *. clip_positions.z.(point))))
          ~y:(Array.copy clip_positions.y) ~z:(Array.copy clip_positions.z)
          ~w:(Array.init clip_input_points (fun point ->
            float_of_int (point land 255) /. 255.)) |> get_ok)) |> get_ok in
    let clip_custom_grid = Geometry.with_attribute clip_field clip_attribute_grid
        |> get_ok in
    measure ~input_points:clip_input_points
      "clip_custom_attribute_distance_edges" (fun () ->
        Ops.clip ~grain ~keep:Ops.Above ~clip_attribute:"clip_field"
          ~distance:0.137 ~clipped_edge_group:"clip_edges"
          ~origin:Vec3.zero ~normal:(Vec3.create 0.7 0.1 (-0.2))
          clip_custom_grid |> get_ok) geometry_output
  end;
  let clip_sphere = Ops.uv_sphere ~segments:96 ~rings:64 ~radius:2. () |> get_ok in
  measure ~input_points:(Geometry.point_count clip_sphere)
    "clip_sphere_filled_all" (fun () ->
    Ops.clip ~grain ~keep:Ops.All ~fill:true ~split_connectivity:true
      ~cap_group:"caps" ~above_group:"above" ~below_group:"below"
      ~origin:(Vec3.create 0. 0.13 0.) ~normal:(Vec3.create 0.2 1. 0.3)
      clip_sphere |> get_ok) geometry_output;
  if benchmark_enabled "clip_nested_caps_64_holes" then begin
    let box ~center ~y ~z = Ops.box ~connectivity:Ops.Box_quads
        ~consolidate_points:true ~normals:Ops.Box_no_normals ~center
        ~size:(Vec3.create 2. y z) () |> get_ok in
    let outer = box ~center:Vec3.zero ~y:20. ~z:20. in
    let holes = Array.init 64 (fun hole ->
        let row = hole / 8 and column = hole mod 8 in
        box ~center:(Vec3.create 0. ((float_of_int column -. 3.5) *. 2.)
          ((float_of_int row -. 3.5) *. 2.)) ~y:1. ~z:1.
        |> Ops.reverse |> get_ok) in
    let source = Ops.merge (outer :: Array.to_list holes) |> get_ok in
    measure ~input_points:(Geometry.point_count source)
      "clip_nested_caps_64_holes" (fun () ->
        Ops.clip ~grain ~fill:true ~cap_group:"caps" ~origin:Vec3.zero
          ~normal:Vec3.unit_x source |> get_ok) geometry_output
  end;
  if benchmark_enabled "clip_nested_caps_16_components" then begin
    let box ~center ~size = Ops.box ~connectivity:Ops.Box_quads
        ~consolidate_points:true ~normals:Ops.Box_no_normals
        ~y_divisions:64 ~z_divisions:64 ~center ~size () |> get_ok in
    let shells = ref [] in
    for component = 15 downto 0 do
      let row = component / 4 and column = component mod 4 in
      let center = Vec3.create 0. ((float_of_int column -. 1.5) *. 3.)
          ((float_of_int row -. 1.5) *. 3.) in
      let outer = box ~center ~size:(Vec3.create 2. 2. 2.)
      and inner = box ~center ~size:(Vec3.create 2. 1. 1.)
          |> Ops.reverse |> get_ok in
      shells := outer :: inner :: !shells
    done;
    let source = Ops.merge !shells |> get_ok in
    measure ~input_points:(Geometry.point_count source)
      "clip_nested_caps_16_components" (fun () ->
        Ops.clip ~grain ~fill:true ~cap_group:"caps" ~origin:Vec3.zero
          ~normal:Vec3.unit_x source |> get_ok) geometry_output
  end;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_loop_grid_attributes" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Loop clip_attribute_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_grid_attributes" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark clip_attribute_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_grid_boundary_edge_and_corner" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~boundary_interpolation:Ops.Subdivide_boundary_edge_and_corner
      clip_attribute_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_grid_boundary_none" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~boundary_interpolation:Ops.Subdivide_boundary_none
      clip_attribute_grid |> get_ok)
    geometry_output;
  let fvar_topology = Topology.Private.view
      (Geometry.topology clip_attribute_grid) in
  let fvar_positions = Packed.Float3.Private.view
      (Geometry.positions clip_attribute_grid) in
  let continuous_uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.map (fun point -> fvar_positions.x.(point))
          fvar_topology.vertex_points)
        ~y:(Array.map (fun point -> fvar_positions.z.(point))
          fvar_topology.vertex_points) |> get_ok)) |> get_ok in
  let continuous_fvar_grid = Geometry.with_attribute continuous_uv
      clip_attribute_grid |> get_ok in
  let no_point_normal_grid = Geometry.without_attribute
      ~owner:Attribute.Point "N" clip_attribute_grid in
  measure ~input_points:(Geometry.point_count no_point_normal_grid)
    "subdivide_catmull_normals_absent" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark no_point_normal_grid
      |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_normals_interpolated" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark clip_attribute_grid
      |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_normals_recomputed" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
        ~recompute_point_normals:true clip_attribute_grid |> get_ok)
    geometry_output;
  let measure_fvar name policy =
    measure ~input_points:(Geometry.point_count continuous_fvar_grid)
      ("subdivide_catmull_fvar_" ^ name) (fun () ->
        Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
          ~face_varying_interpolation:policy continuous_fvar_grid |> get_ok)
      geometry_output in
  measure_fvar "none" Ops.Subdivide_fvar_none;
  measure_fvar "corners_only" Ops.Subdivide_fvar_corners_only;
  measure_fvar "corners_plus1" Ops.Subdivide_fvar_corners_plus1;
  measure_fvar "corners_plus2" Ops.Subdivide_fvar_corners_plus2;
  measure_fvar "boundaries" Ops.Subdivide_fvar_boundaries;
  measure_fvar "all" Ops.Subdivide_fvar_all;
  let triangle_subdivision_grid = Ops.grid
      ~connectivity:Ops.Grid_triangles ~columns:200 ~rows:200 ~size:20. ()
      |> get_ok
      |> Ops.uv_project ~grain planar_projection |> get_ok
      |> Ops.color_by_height ~grain ~low:low_color ~high:high_color |> get_ok in
  let measure_triangles name policy =
    measure ~input_points:(Geometry.point_count triangle_subdivision_grid)
      ("subdivide_catmull_triangles_" ^ name) (fun () ->
        Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~triangle_policy:policy
          ~face_varying_interpolation:Ops.Subdivide_fvar_none
          triangle_subdivision_grid |> get_ok) geometry_output in
  measure_triangles "catmull_clark" Ops.Subdivide_triangles_catmull_clark;
  measure_triangles "smooth" Ops.Subdivide_triangles_smooth;
  let measure_seamed_fvar name policy =
    measure ~input_points:(Geometry.point_count clip_attribute_grid)
      ("subdivide_catmull_fvar_seamed_" ^ name) (fun () ->
        Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
          ~face_varying_interpolation:policy clip_attribute_grid |> get_ok)
      geometry_output in
  measure_seamed_fvar "none" Ops.Subdivide_fvar_none;
  measure_seamed_fvar "corners_plus2" Ops.Subdivide_fvar_corners_plus2;
  let fvar_index = Topology_index.create (Geometry.topology clip_attribute_grid)
      |> Topology_index.Private.view in
  let mixed_uv = Attribute.create_owned ~name:"uv" ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.map (fun point -> fvar_positions.x.(point))
          fvar_topology.vertex_points)
        ~y:(Array.init (Geometry.vertex_count clip_attribute_grid) (fun vertex ->
          let point = fvar_topology.vertex_points.(vertex) in
          let primitive = fvar_index.primitive_of_vertex.(vertex) in
          let region = ((primitive / 2) mod 200) / 50 in
          fvar_positions.z.(point) +. (float_of_int region *. 100.)))
        |> get_ok)) |> get_ok in
  let mixed_fvar_grid = Geometry.with_attribute mixed_uv clip_attribute_grid
      |> get_ok in
  let measure_mixed_fvar name policy =
    measure ~input_points:(Geometry.point_count mixed_fvar_grid)
      ("subdivide_catmull_fvar_mixed_" ^ name) (fun () ->
        Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
          ~face_varying_interpolation:policy mixed_fvar_grid |> get_ok)
      geometry_output in
  measure_mixed_fvar "none" Ops.Subdivide_fvar_none;
  measure_mixed_fvar "corners_plus2" Ops.Subdivide_fvar_corners_plus2;
  let dense_creases = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex
      (Attribute.Float (Array.init (Geometry.vertex_count clip_attribute_grid)
        (fun vertex -> if vertex mod 7 = 0 then 2. else 0.))) |> get_ok in
  let creased_grid = Geometry.with_attribute dense_creases clip_attribute_grid
      |> get_ok in
  measure ~input_points:(Geometry.point_count creased_grid)
    "subdivide_catmull_grid_creases" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark creased_grid |> get_ok)
    geometry_output;
  let varying_creases = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex
      (Attribute.Float (Array.init (Geometry.vertex_count clip_attribute_grid)
        (fun vertex -> if vertex mod 19 = 0 then 0.
          else 0.25 +. (float_of_int (vertex mod 17) *. 0.25)))) |> get_ok in
  let varying_creased_grid = Geometry.with_attribute varying_creases
      clip_attribute_grid |> get_ok in
  let measure_creasing name method_ =
    measure ~input_points:(Geometry.point_count varying_creased_grid)
      ("subdivide_catmull_creasing_" ^ name) (fun () ->
        Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
          ~creasing_method:method_ ~resulting_crease_group:"remaining_creases"
          varying_creased_grid |> get_ok) geometry_output in
  measure_creasing "uniform" Ops.Subdivide_creasing_uniform;
  measure_creasing "chaikin" Ops.Subdivide_creasing_chaikin;
  let all_edge_weights = Attribute.create_owned ~name:"creaseweight"
      ~owner:Attribute.Vertex
      (Attribute.Float (Array.make
        (Geometry.vertex_count clip_attribute_grid) 3.)) |> get_ok in
  let all_edge_attribute_grid = Geometry.with_attribute all_edge_weights
      clip_attribute_grid |> get_ok in
  measure ~input_points:(Geometry.point_count all_edge_attribute_grid)
    "subdivide_catmull_all_edges_attribute" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
        ~resulting_crease_group:"remaining_creases"
        all_edge_attribute_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_all_edges_override" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~crease_weight:3.
        ~resulting_crease_group:"remaining_creases"
        clip_attribute_grid |> get_ok) geometry_output;
  let add_detail name value geometry =
    let attribute = Attribute.create_owned ~owner:Attribute.Detail ~name
        (Attribute.Int [|value|]) |> get_ok in
    Geometry.with_attribute attribute geometry |> get_ok in
  let explicit_detail_payload = varying_creased_grid
      |> add_detail "bench_scheme" 0
      |> add_detail "bench_vtxboundaryinterpolation" 1
      |> add_detail "bench_fvarlinearinterpolation" 5
      |> add_detail "bench_creasingmethod" 1
      |> add_detail "bench_trianglesubdiv" 0
  and detail_overridden_grid = varying_creased_grid
      |> add_detail "osd_scheme" 0
      |> add_detail "osd_vtxboundaryinterpolation" 1
      |> add_detail "osd_fvarlinearinterpolation" 5
      |> add_detail "osd_creasingmethod" 1
      |> add_detail "osd_trianglesubdiv" 0 in
  measure ~input_points:(Geometry.point_count explicit_detail_payload)
    "subdivide_catmull_explicit_controls_detail_payload" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
        ~boundary_interpolation:Ops.Subdivide_boundary_edge_only
        ~face_varying_interpolation:Ops.Subdivide_fvar_all
        ~creasing_method:Ops.Subdivide_creasing_chaikin
        ~triangle_policy:Ops.Subdivide_triangles_catmull_clark
        ~resulting_crease_group:"remaining_creases"
        explicit_detail_payload |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count detail_overridden_grid)
    "subdivide_catmull_detail_overrides" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Bilinear
        ~boundary_interpolation:Ops.Subdivide_boundary_none
        ~face_varying_interpolation:Ops.Subdivide_fvar_none
        ~creasing_method:Ops.Subdivide_creasing_uniform
        ~triangle_policy:Ops.Subdivide_triangles_smooth
        ~resulting_crease_group:"remaining_creases"
        detail_overridden_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_second_input_dense_attributes" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~creases:creased_grid
      clip_attribute_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_second_input_dense_group" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~creases:creased_grid
      ~resulting_crease_group:"remaining_creases" clip_attribute_grid |> get_ok)
    geometry_output;
  let sparse_crease_topology = Topology.create_owned
      ~point_count:(Geometry.point_count modeling_grid)
      ~vertex_points:(Array.init 201 Fun.id) ~primitive_offsets:[|0;201|]
      ~primitive_kinds:[|Topology.Open_polyline|] |> get_ok in
  let sparse_crease_input = Geometry.create
      ~positions:(Geometry.positions modeling_grid)
      ~topology:sparse_crease_topology () |> get_ok in
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_second_input_sparse_override" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~creases:sparse_crease_input ~crease_weight:2.5 modeling_grid |> get_ok)
    geometry_output;
  let hole_primitive_count = Geometry.primitive_count clip_attribute_grid in
  let sparse_holes = Group.init ~grain ~owner:Group.Primitive
      ~name:"subdivision_hole" hole_primitive_count
      (fun primitive -> primitive mod 401 = 0)
  and dense_holes = Group.init ~grain ~owner:Group.Primitive
      ~name:"subdivision_hole" hole_primitive_count
      (fun primitive -> primitive land 1 = 0) in
  let sparse_hole_grid = Geometry.with_group sparse_holes clip_attribute_grid
      |> get_ok
  and dense_hole_grid = Geometry.with_group dense_holes clip_attribute_grid
      |> get_ok in
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_sparse_holes" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark sparse_hole_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_dense_holes" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark dense_hole_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count clip_attribute_grid)
    "subdivide_catmull_dense_holes_retained" (fun () ->
      Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~remove_holes:false
        dense_hole_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_bilinear_grid" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Bilinear modeling_grid |> get_ok)
    geometry_output;
  let subdivision_primitives = Geometry.primitive_count modeling_grid in
  let subdivision_half = Group.init ~grain ~owner:Group.Primitive
      ~name:"subdivision_half" subdivision_primitives
      (fun primitive -> primitive < subdivision_primitives / 2)
  and subdivision_alternating = Group.init ~grain ~owner:Group.Primitive
      ~name:"subdivision_alternating" subdivision_primitives
      (fun primitive -> primitive land 1 = 0) in
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_bilinear_local_half" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Bilinear ~primitives:subdivision_half
      modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_bilinear_local_alternating" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Bilinear
      ~primitives:subdivision_alternating modeling_grid |> get_ok)
    geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_half" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_pull_no_edge_division" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~cracks:Ops.Subdivide_pull_no_edge_division
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_stitch_no_edge_division" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~cracks:Ops.Subdivide_stitch_no_edge_division
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_pull_divide_edges" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~cracks:(Ops.Subdivide_pull_divide_edges 0.75)
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_stitch_divide_edges" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~cracks:Ops.Subdivide_stitch_divide_edges
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_pull_triangulate" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~cracks:(Ops.Subdivide_pull_triangulate 0.75)
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_stitch_triangulate" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~cracks:Ops.Subdivide_stitch_triangulate
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_stitch_divide_consistent" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~consistent_topology:true
      ~cracks:Ops.Subdivide_stitch_divide_edges
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_stitch_triangulate_consistent" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~consistent_topology:true
      ~cracks:Ops.Subdivide_stitch_triangulate
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure ~input_points:(Geometry.point_count modeling_grid)
    "subdivide_catmull_local_pull_triangulate_consistent" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark ~consistent_topology:true
      ~cracks:(Ops.Subdivide_pull_triangulate 0.75)
      ~primitives:subdivision_half modeling_grid |> get_ok) geometry_output;
  measure "mirror" (fun () ->
    Ops.mirror ~grain ~origin:Vec3.zero ~normal:(Vec3.create 1. 1. 0.)
      modeling_grid |> get_ok) geometry_output;
  let fuse_source = Ops.merge ~grain [modeling_grid; modeling_grid] |> get_ok in
  measure "fuse_exact_pair" (fun () ->
    Ops.fuse ~grain ~tolerance:0. ~match_attributes:true fuse_source |> get_ok)
    geometry_output;
  let modeling_points = Geometry.point_count modeling_grid in
  measure ~input_points:modeling_points "poly_extrude" (fun () ->
    Ops.poly_extrude ~grain ~distance:0.2 modeling_grid |> get_ok) geometry_output;
  measure ~input_points:modeling_points "poly_extrude_connected" (fun () ->
    Ops.poly_extrude ~grain ~divide:Ops.Extrude_connected_components
      ~distance:0.2 modeling_grid |> get_ok) geometry_output;
  measure ~input_points:modeling_points "poly_extrude_connected_divisions4" (fun () ->
    Ops.poly_extrude ~grain ~divide:Ops.Extrude_connected_components
      ~divisions:4 ~distance:0.2 modeling_grid |> get_ok) geometry_output;
  measure ~input_points:modeling_points "poly_extrude_connected_boundaries" (fun () ->
    Ops.poly_extrude ~grain ~divide:Ops.Extrude_connected_components
      ~divisions:4 ~front_boundary_group:"front_rim"
      ~back_boundary_group:"back_rim" ~distance:0.2 modeling_grid |> get_ok)
    geometry_output;
  let curve = Array.init 10_001 (fun index ->
    let t = float_of_int index *. 0.002 in
    (t, sin (t *. 2.3), cos (t *. 1.7) *. 0.5))
    |> Ops.polyline |> get_ok in
  measure "sweep_circle" (fun () ->
    Ops.sweep_circle ~sides:12 ~radius:0.08 curve |> get_ok) geometry_output;
  let dense_curve_values = Array.init curve_points (fun index ->
      let t = float_of_int index *. 0.001 in
      t, sin (t *. 0.19), cos (t *. 0.07) *. 0.5) in
  let dense_curve_plain = Ops.polyline dense_curve_values |> get_ok in
  let curve_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point
      (Attribute.Float (Array.init curve_points (fun index ->
        float_of_int index *. 0.001))) |> get_ok
  and curve_uv = Attribute.create_owned ~name:"curve_uv"
      ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init curve_points (fun index ->
          float_of_int index /. float_of_int (curve_points - 1)))
        ~y:(Array.make curve_points 0.) |> get_ok)) |> get_ok
  and curve_points_group = Group.init ~owner:Group.Point ~name:"alternating"
      curve_points (fun point -> point land 1 = 0) in
  let dense_curve = dense_curve_plain |> Geometry.with_attribute curve_weight |> get_ok
      |> Geometry.with_attribute curve_uv |> get_ok
      |> Geometry.with_group curve_points_group |> get_ok
      |> Ops.group_edges ~grain ~name:"all_curve_edges" |> get_ok in
  let segment_count = curve_points - 1 in
  let segmented_topology = Topology.create_owned ~point_count:curve_points
      ~vertex_points:(Array.init (segment_count * 2) (fun vertex ->
        let primitive = vertex / 2 in primitive + (vertex land 1)))
      ~primitive_offsets:(Array.init (segment_count + 1)
        (fun primitive -> primitive * 2))
      ~primitive_kinds:(Array.make segment_count Topology.Open_polyline)
      |> get_ok in
  let segmented_uv = Attribute.create_owned ~name:"curve_uv"
      ~owner:Attribute.Vertex
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init (segment_count * 2) (fun vertex ->
          float_of_int (vertex / 2 + (vertex land 1))
          /. float_of_int segment_count))
        ~y:(Array.make (segment_count * 2) 0.) |> get_ok)) |> get_ok in
  let segmented_curves = Geometry.create
      ~positions:(Geometry.positions dense_curve_plain)
      ~topology:segmented_topology
      ~attributes:[curve_weight; segmented_uv]
      ~groups:[curve_points_group] () |> get_ok
      |> Ops.group_edges ~grain ~name:"all_curve_edges" |> get_ok in
  measure ~input_points:curve_points "subdivide_catmull_curves_shared" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Catmull_clark segmented_curves |> get_ok)
    geometry_output;
  measure ~input_points:curve_points "subdivide_catmull_curves_independent"
    (fun () -> Ops.subdivide ~grain ~scheme:Ops.Catmull_clark
      ~treat_curves_as_independent:true segmented_curves |> get_ok)
    geometry_output;
  measure ~input_points:curve_points "subdivide_bilinear_curves_shared" (fun () ->
    Ops.subdivide ~grain ~scheme:Ops.Bilinear segmented_curves |> get_ok)
    geometry_output;
  measure "curve_carve_relative" (fun () ->
    Ops.carve_curves ~grain ~first:0.137 ~last:0.863 dense_curve |> get_ok)
    geometry_output;
  measure "curve_carve_divided" (fun () ->
    Ops.carve_curves ~grain ~first:0.137 ~last:0.863 ~divisions:1_024
      dense_curve |> get_ok) geometry_output;
  measure "curve_carve_extract_points" (fun () ->
    Ops.carve_curves ~grain ~first:0.137 ~last:0.863 ~extract_points:true
      ~divisions:100_001 dense_curve |> get_ok) geometry_output;
  measure "curve_carve_all_pieces" (fun () ->
    Ops.carve_curves ~grain ~first:0.137 ~last:0.863
      ~keep:Ops.Keep_inside_and_outside dense_curve |> get_ok) geometry_output;
  measure "curve_carve_breakpoint_interval" (fun () ->
    Ops.carve_curves ~grain ~first:0.137 ~last:0.863
      ~only_at_breakpoints:true dense_curve |> get_ok) geometry_output;
  measure "curve_carve_all_breakpoints" (fun () ->
    Ops.carve_curves ~grain ~first:0. ~last:1. ~only_at_breakpoints:true
      ~cut_at_all_internal_breakpoints:true dense_curve |> get_ok)
    geometry_output;
  let carve_grid = Ops.grid ~connectivity:Ops.Grid_quads ~columns:400 ~rows:400
      ~size:100. () |> get_ok
      |> Geometry.without_attribute ~owner:Attribute.Point "N" in
  let grouped_carve_source = Ops.merge ~grain [dense_curve_plain; carve_grid]
      |> get_ok in
  let grouped_carve_selection = Group.init ~owner:Group.Primitive
      ~name:"carve_curve" (Geometry.primitive_count grouped_carve_source)
      (fun primitive -> primitive = 0) in
  let grouped_carve_source = Geometry.with_group grouped_carve_selection
      grouped_carve_source |> get_ok |> Ops.group_edges ~grain ~name:"all_edges"
      |> get_ok in
  measure ~input_points:(Geometry.point_count grouped_carve_source)
    "curve_carve_grouped" (fun () ->
      Ops.carve_curves ~grain ~primitives:grouped_carve_selection ~first:0.137
        ~last:0.863 grouped_carve_source |> get_ok) geometry_output;
  let closed_dense_curve = Ops.polyline ~closed:true dense_curve_values |> get_ok
      |> Geometry.with_attribute curve_weight |> get_ok
      |> Geometry.with_attribute curve_uv |> get_ok
      |> Geometry.with_group curve_points_group |> get_ok
      |> Ops.group_edges ~grain ~name:"all_curve_edges" |> get_ok in
  measure "curve_ends_unroll" (fun () ->
    Ops.curve_ends ~grain Ops.Unroll_curve closed_dense_curve |> get_ok)
    geometry_output;
  let ends_quads = 100_000 and ends_points = 400_000 in
  let ends_positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init ends_points (fun point ->
        float_of_int ((point / 4) mod 1_000) +.
          (if point land 3 = 1 || point land 3 = 2 then 0.75 else 0.)))
      ~y:(Array.init ends_points (fun point ->
        float_of_int ((point / 4) / 1_000) +.
          (if point land 3 >= 2 then 0.75 else 0.)))
      ~z:(Array.make ends_points 0.) in
  let ends_topology = Topology.polygons_owned ~point_count:ends_points
      ~vertex_points:(Array.init ends_points Fun.id)
      ~primitive_offsets:(Array.init (ends_quads + 1)
        (fun primitive -> primitive * 4)) |> get_ok in
  let ends_id = Attribute.create_owned ~owner:Attribute.Point ~name:"id"
      (Attribute.Int (Array.init ends_points Fun.id)) |> get_ok
  and ends_uv = Attribute.create_owned ~owner:Attribute.Vertex ~name:"uv"
      (Attribute.Float2 (Packed.Float2.of_owned
        ~x:(Array.init ends_points (fun vertex ->
          if vertex land 3 = 1 || vertex land 3 = 2 then 1. else 0.))
        ~y:(Array.init ends_points (fun vertex ->
          if vertex land 3 >= 2 then 1. else 0.)) |> get_ok)) |> get_ok in
  let ends_source = Geometry.create ~positions:ends_positions
      ~topology:ends_topology ~attributes:[ends_id;ends_uv]
      ~groups:[Group.init ~owner:Group.Point ~name:"marked" ends_points
        (fun point -> point land 7 = 0)] () |> get_ok
      |> Ops.group_edges ~grain ~name:"all_edges" |> get_ok in
  measure ~input_points:ends_points "ends_unroll_new_100k_quads"
    (fun () -> Ops.ends ~grain Ops.Ends_unroll_new ends_source |> get_ok)
    geometry_output;
  let shared_ends_source = Ops.grid ~connectivity:Ops.Grid_quads
      ~columns:400 ~rows:400 ~size:100. () |> get_ok
      |> Ops.group_edges ~grain ~name:"all_edges" |> get_ok in
  measure ~input_points:(Geometry.point_count shared_ends_source)
    "ends_unroll_shared_159k_grid_faces"
    (fun () -> Ops.ends ~grain Ops.Ends_unroll_shared shared_ends_source
      |> get_ok) geometry_output;
  let join_curve_count = 1_000 and join_segments = 200 in
  let join_points = join_curve_count * (join_segments + 1) in
  let join_positions = Packed.Float3.Private.of_owned_exn
      ~x:(Array.init join_points (fun point ->
        let curve = point / (join_segments + 1)
        and local = point mod (join_segments + 1) in
        float_of_int ((curve * join_segments) + local) *. 0.001))
      ~y:(Array.init join_points (fun point ->
        let curve = point / (join_segments + 1)
        and local = point mod (join_segments + 1) in
        sin (float_of_int ((curve * join_segments) + local) *. 0.0007)))
      ~z:(Array.make join_points 0.) in
  let join_topology = Topology.create_owned ~point_count:join_points
      ~vertex_points:(Array.init join_points Fun.id)
      ~primitive_offsets:(Array.init (join_curve_count + 1)
        (fun primitive -> primitive * (join_segments + 1)))
      ~primitive_kinds:(Array.make join_curve_count Topology.Open_polyline)
      |> get_ok in
  let join_weight = Attribute.create_owned ~name:"weight"
      ~owner:Attribute.Point
      (Attribute.Float (Array.init join_points (fun point ->
        float_of_int point *. 0.001))) |> get_ok in
  let join_source = Geometry.create ~positions:join_positions
      ~topology:join_topology ~attributes:[join_weight] () |> get_ok
      |> Ops.group_edges ~grain ~name:"all_join_edges" |> get_ok in
  let first_u = Attribute.create_owned ~name:"first_u"
      ~owner:Attribute.Primitive
      (Attribute.Float (Array.init join_curve_count (fun primitive ->
        0.1 +. (float_of_int (primitive mod 17) *. 0.005)))) |> get_ok
  and second_u = Attribute.create_owned ~name:"second_u"
      ~owner:Attribute.Primitive
      (Attribute.Float (Array.init join_curve_count (fun primitive ->
        0.9 -. (float_of_int (primitive mod 13) *. 0.005)))) |> get_ok in
  let attributed_curves = join_source
      |> Geometry.with_attribute first_u |> get_ok
      |> Geometry.with_attribute second_u |> get_ok in
  measure ~input_points:join_points "curve_carve_primitive_parameters" (fun () ->
    Ops.carve_curves ~grain ~first_attribute:"first_u"
      ~last_attribute:"second_u" attributed_curves |> get_ok) geometry_output;
  measure "curve_join_ordered" (fun () ->
    Ops.join_curves ~grain join_source |> get_ok) geometry_output;
  let graph = Sop.grid ~columns ~rows ~size:100. ()
      |> Sop.noise_displace ~seed:42 ~amplitude:0.8 ~frequency:0.16
      |> Sop.color_by_height ~low:low_color ~high:high_color in
  measure "session_first_cook" (fun () ->
    let session = make_session () in
    let geometry = match Session.cook session ~context:(make_context ()) graph with
      | Ok output -> output.geometry
      | Error error -> failwith (Diagnostic.error_to_string error) in
    Session.close session;
    geometry) geometry_output;
  let session = make_session () in
  ignore (Session.cook session ~context:(make_context ()) graph);
  measure "session_cache_hit" (fun () ->
    match Session.cook session ~context:(make_context ()) graph with
    | Ok output -> output.geometry
    | Error error -> failwith (Diagnostic.error_to_string error)) geometry_output;
  Session.close session
