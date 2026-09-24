open Prismel
open Procedural

let get_ok = function Ok value -> value | Error _ -> failwith "unexpected error"

let hollow_square_prism () =
  let x = Array.make 16 0. and y = Array.make 16 0.
  and z = Array.make 16 0. in
  let outer = [|(-0.8, -0.8); (0.8, -0.8); (0.8, 0.8); (-0.8, 0.8)|]
  and inner = [|(-0.35, -0.35); (0.35, -0.35);
      (0.35, 0.35); (-0.35, 0.35)|] in
  for side = 0 to 1 do
    let px = if side = 0 then -0.35 else 0.35 in
    for corner = 0 to 3 do
      let outer_point = (side * 4) + corner
      and inner_point = 8 + (side * 4) + corner in
      x.(outer_point) <- px; x.(inner_point) <- px;
      y.(outer_point) <- fst outer.(corner);
      z.(outer_point) <- snd outer.(corner);
      y.(inner_point) <- fst inner.(corner);
      z.(inner_point) <- snd inner.(corner)
    done
  done;
  let topology = Pdk.Topology.Builder.create ~point_count:16 () in
  for corner = 0 to 3 do
    let next = (corner + 1) mod 4 in
    Pdk.Topology.Builder.add_polygon topology
      [|corner; next; 4 + next; 4 + corner|];
    Pdk.Topology.Builder.add_polygon topology
      [|8 + corner; 12 + corner; 12 + next; 8 + next|];
    Pdk.Topology.Builder.add_polygon topology
      [|corner; 8 + corner; 8 + next; next|];
    Pdk.Topology.Builder.add_polygon topology
      [|4 + corner; 4 + next; 12 + next; 12 + corner|]
  done;
  Pdk.Geometry.create
    ~positions:(Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology:(Pdk.Topology.Builder.freeze topology) () |> Result.get_ok

let bridge_rings () =
  let per_ring = 18 and point_count = 36 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. in
  for ring = 0 to 1 do
    for local = 0 to per_ring - 1 do
      let point = (ring * per_ring) + local
      and angle = 2. *. Float.pi *. float_of_int local /. float_of_int per_ring in
      let radius = if ring = 0 then 0.34 else 0.52 in
      x.(point) <- radius *. cos angle;
      y.(point) <- if ring = 0 then -0.55 else 0.55;
      z.(point) <- radius *. sin angle
    done
  done;
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:[|0;per_ring;point_count|]
      ~primitive_kinds:[|Pdk.Topology.Polygon;Pdk.Topology.Polygon|]
      |> Result.get_ok in
  let index = Pdk.Topology_index.create topology in
  let source = Pdk.Edge_group.init ~grain:1 ~topology ~index ~name:"bridge_source"
      (fun edge -> let a, _ = Pdk.Topology_index.edge_points index edge in
        a < per_ring)
  and destination = Pdk.Edge_group.init ~grain:1 ~topology ~index
      ~name:"bridge_destination" (fun edge ->
        let a, _ = Pdk.Topology_index.edge_points index edge in a >= per_ring) in
  Pdk.Geometry.create
    ~positions:(Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z) ~topology
    ~edge_groups:[source;destination] () |> Result.get_ok

let constrained_growth_strip () =
  let x = [|0.;1.;2.;3.; 0.;1.;2.;3.|]
  and y = [|0.;0.;0.;0.; 1.;1.;1.;1.|]
  and z = [|0.;0.;0.;1.; 0.;0.;0.;1.|] in
  let topology = Pdk.Topology.create_owned ~point_count:8
      ~vertex_points:[|0;1;5;4; 1;2;6;5; 2;3;7;6|]
      ~primitive_offsets:[|0;4;8;12|]
      ~primitive_kinds:(Array.make 3 Pdk.Topology.Polygon) |> Result.get_ok in
  let region = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Primitive
      ~name:"region" (Pdk.Attribute.Int [|0;0;1|]) |> Result.get_ok
  and seed = Pdk.Group.init ~grain:1 ~owner:Pdk.Group.Primitive
      ~name:"growth_seed" 3 (fun primitive -> primitive = 0) in
  Pdk.Geometry.create
    ~positions:(Pdk.Packed.Float3.Private.of_owned_exn ~x ~y ~z) ~topology
    ~attributes:[region] ~groups:[seed] () |> Result.get_ok

let variable_wire_curve () =
  let values = [|(-0.7, -0.55, 0.); (-0.25, -0.2, 0.2); (0., 0.2, -0.1);
      (0.35, 0.5, 0.18); (0.7, 0.62, 0.)|] in
  let point_count = Array.length values in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.map (fun (x, _, _) -> x) values)
      ~y:(Array.map (fun (_, y, _) -> y) values)
      ~z:(Array.map (fun (_, _, z) -> z) values) in
  let topology = Pdk.Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:[|0;point_count|]
      ~primitive_kinds:[|Pdk.Topology.Open_polyline|] |> Result.get_ok in
  let divisions = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"wire_divisions" (Pdk.Attribute.Int [|4;7;5;9;6|]) |> Result.get_ok
  and segments = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"wire_segments" (Pdk.Attribute.Int [|1;3;2;4;2|]) |> Result.get_ok
  and scale = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"wire_scale" (Pdk.Attribute.Float [|0.7;1.;0.55;1.15;0.8|])
    |> Result.get_ok
  and joint_limit = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"wire_joint_limit" (Pdk.Attribute.Float [|1.;1.8;1.25;2.;1.|])
    |> Result.get_ok
  and smooth = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"wire_smooth" (Pdk.Attribute.Float [|1.;1.;0.;1.;1.|])
    |> Result.get_ok
  and segment_seam = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Vertex
      ~name:"wire_segment_seam" (Pdk.Attribute.Int [|0;2;-1;3;0|])
    |> Result.get_ok
  and segment_scales = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Vertex
      ~name:"wire_segment_scales" (Pdk.Attribute.Float2
        (Pdk.Packed.Float2.of_owned ~x:[|0.15;0.2;0.1;0.25;0.|]
          ~y:[|0.75;0.85;0.9;0.8;1.|] |> Result.get_ok)) |> Result.get_ok
  and uv_ranges = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Vertex
      ~name:"wire_uv_ranges" (Pdk.Attribute.Float4
        (Pdk.Packed.Float4.of_owned ~x:[|0.;0.1;0.2;0.3;0.|]
          ~y:[|1.;1.1;1.2;1.3;1.|] ~z:[|0.;1.;2.;3.;0.|]
          ~w:[|1.;2.;3.;4.;1.|] |> Result.get_ok)) |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology
    ~attributes:[divisions;segments;scale;joint_limit;smooth;segment_scales;
      segment_seam;uv_ranges] ()
    |> Result.get_ok

let crease_box_source () =
  let geometry = Pdk.Ops.box ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true ~normals:Pdk.Ops.Box_no_normals
      ~size:(Vec3.create 1.35 1.35 1.35) () |> Result.get_ok in
  let topology = Pdk.Geometry.topology geometry in
  let index = Pdk.Topology_index.create topology in
  let edges = Pdk.Edge_group.init ~grain:1 ~topology ~index
      ~name:"feature_edges" (fun edge -> edge mod 3 = 0) in
  Pdk.Geometry.with_edge_group edges geometry |> Result.get_ok

let read_file filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let cooked_mesh graph domains =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(32 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:97 ~seed:2026L () |> get_ok in
    match Bridge.cook_to_mesh session ~context graph with
    | Ok (mesh, _) -> mesh
    | Error error -> failwith (Diagnostic.error_to_string error))

let cooked_instances instances domains =
  let session = Session.create ~max_entries:16
      ~max_payload_bytes:(32 * 1024 * 1024) |> get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~domains ~grain:97 ~seed:2026L () |> get_ok in
    match Bridge.cook_to_scene3 ~cull:Scene3.Cull_none
        ~material:(Material.create ~diffuse:(Color.hex_exn "#f8fafc") ())
        session ~context instances with
    | Ok (node, _) -> node
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene meshes instance_node =
  let camera = Camera.perspective ~at:(Vec3.create 5. 4. 6.)
      ~target:Vec3.zero () in
  let lights = [Light.directional ~direction:(Vec3.create (-1.) (-2.) (-1.)) ()] in
  let checker = Texture.init ~width:16 ~height:16 (fun ~x ~y ->
      if ((x / 4) + (y / 4)) land 1 = 0 then Color.white
      else Color.hex_exn "#334155")
      |> Scene3.textured ~filter:Texture.Nearest
           ~wrap_u:Texture.Repeat ~wrap_v:Texture.Repeat in
  let nodes = List.map (fun mesh -> Scene3.mesh ~cull:Scene3.Cull_none
      ~texture:checker
      ~material:(Material.create ~diffuse:Color.white ()) mesh) meshes in
  let nodes = nodes @ [instance_node] in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~lights ~samples:4 nodes);
  ]

let render directory domains meshes instances =
  let config = { Sketch.default_config with
    width = 160; height = 120; domains = Some domains } in
  Sketch.export ~config ~directory ~prefix:"procedural" ~frames:1
    (fun _ -> scene meshes instances)

let () =
  let keep_artifacts = match Sys.getenv_opt "PRISMEL_KEEP_TEST_ARTIFACTS" with
    | Some value -> List.mem (String.lowercase_ascii value)
        ["1"; "true"; "yes"; "on"]
    | None -> false in
  let interpolation_target = Pdk.Ops.grid ~columns:10 ~rows:8 ~size:1.5 ()
      |> Result.get_ok in
  let interpolation_points = Pdk.Geometry.point_count interpolation_target in
  let primitive_driver = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"source_primitive"
      (Pdk.Attribute.Int (Array.make interpolation_points 0)) |> Result.get_ok
  and uvw_driver = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"source_uvw" (Pdk.Attribute.Float3
        (Pdk.Packed.Float3.Private.of_owned_exn
          ~x:(Array.init interpolation_points (fun point ->
            float_of_int (point mod 11) /. 10.))
          ~y:(Array.init interpolation_points (fun point ->
            float_of_int (point / 11) /. 8.))
          ~z:(Array.make interpolation_points 0.))) |> Result.get_ok in
  let interpolation_target = interpolation_target
      |> Pdk.Geometry.with_attribute primitive_driver |> Result.get_ok
      |> Pdk.Geometry.with_attribute uvw_driver |> Result.get_ok in
  let interpolation_source = Sop.grid ~columns:3 ~rows:3 ~size:1.5 ()
      |> Sop.noise_displace ~seed:937 ~amplitude:0.45 ~frequency:1.8
      |> Sop.color_by_height ~low:(Color.hex_exn "#14b8a6")
           ~high:(Color.hex_exn "#f43f5e")
      |> Sop.group ~name:"hot" Select.all_points in
  let interpolation_computed = Sop.attribute_interpolate
      ~target_owner:Pdk.Attribute.Point
      ~compute_weights:{
        Pdk.Attribute_ops.computed_owner=Pdk.Attribute.Point;
        computed_numbers_attribute="computed_points";
        computed_weights_attribute="computed_weights" }
      ~attributes:[] ~source:interpolation_source
      ~target:(Sop.snapshot interpolation_target) () in
  let inline_positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|(-0.7);0.;0.7;0.7;(-0.7)|] ~y:[|0.;0.;0.;0.25;0.|]
      ~z:[|0.;0.;0.;1.;1.|] in
  let inline_topology = Pdk.Topology.polygons_owned ~point_count:5
      ~vertex_points:[|0;1;2;3;4|] ~primitive_offsets:[|0;5|]
      |> Result.get_ok in
  let inline_geometry = Pdk.Geometry.create ~positions:inline_positions
      ~topology:inline_topology () |> Result.get_ok in
  let inline_panel = Sop.snapshot inline_geometry
      |> Sop.group ~name:"facet_anchor" (Select.point_indices [|0|])
      |> Sop.facet ~selection:(Sop.Point_group "facet_anchor")
           ~remove_inline_points:true ~make_planar:true
           ~post_compute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2dd4bf")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 3.7 1.2))
  and terrain = Sop.grid ~columns:24 ~rows:20 ~size:6. ()
      |> Sop.noise_displace ~seed:19 ~amplitude:0.8 ~frequency:0.35
      |> Sop.smooth ~iterations:3 ~boundary:Pdk.Ops.Smooth_unshared
           ~attributes:"P" ~method_:Pdk.Attribute_ops.Edge_length
           ~mode:(Pdk.Attribute_ops.Laplacian 0.32)
      |> Sop.color_by_height ~low:(Color.hex_exn "#1e3a8a")
           ~high:(Color.hex_exn "#f59e0b")
      |> Sop.attribute_randomize ~seed:409 ~operation:Pdk.Attribute_ops.Random_add
           ~scale:0.08 ~owner:Pdk.Attribute.Point ~name:"Cd"
           (Pdk.Attribute_ops.Random_custom_ramp {
             ramp = [0., 0.; 0.3, 0.08; 0.72, 0.9; 1., 1.];
             fit_min = Pdk.Attribute_ops.Vec4 (-1., -1., -1., 0.);
             fit_max = Pdk.Attribute_ops.Vec4 (1., 1., 1., 0.);
           })
      |> Sop.attribute_remap ~owner:Pdk.Attribute.Point ~name:"Cd"
           ~input:(Pdk.Attribute_ops.Remap_explicit {
             min = Pdk.Attribute_ops.Vec4 (-0.08, -0.08, -0.08, 0.);
             max = Pdk.Attribute_ops.Vec4 (1.08, 1.08, 1.08, 1.);
           }) ~output_min:(Pdk.Attribute_ops.Vec4 (0., 0., 0., 0.))
           ~output_max:(Pdk.Attribute_ops.Vec4 (1., 1., 1., 1.))
      |> Sop.enumerate ~owner:Pdk.Attribute.Primitive ~name:"primitive_id"
      |> Sop.group_random ~seed:407 ~probability:0.018
           ~owner:Pdk.Ops.Group_points ~name:"growth_seeds"
      |> Sop.group_edge_depth ~depth:2 ~point_group:"growth_seeds"
           ~name:"growth_points"
      |> Sop.peak ~selection:(Sop.Point_group "growth_points")
           ~distance:0.008 ~recompute_normals:true
      |> Sop.group_boundary_components ~prefix:"terrain_border"
      |> Sop.peak ~selection:(Sop.Point_group "terrain_border__0")
           ~distance:(-0.004) ~recompute_normals:true
      |> Sop.group_random ~seed:411 ~probability:0.14
           ~owner:Pdk.Ops.Group_primitives ~name:"random_ridges"
      |> Sop.group_bounds ~base:"random_ridges"
           ~containment:Pdk.Ops.Partially_contained
           (Pdk.Ops.Bounds_sphere { center = Vec3.zero; radius = 2.4 })
           ~owner:Pdk.Ops.Group_primitives ~name:"random_ridges"
      |> Sop.group_normal ~use_existing_normal:false ~base:"random_ridges"
           ~direction:Vec3.unit_y
           ~spread_angle:(Float.pi /. 3.) ~owner:Pdk.Ops.Group_primitives
           ~name:"random_ridges"
      |> Sop.group_backface ~merge:Pdk.Ops.Group_subtract
           ~viewpoint:(Vec3.create 5. 4. 6.) ~name:"random_ridges"
      |> Sop.peak ~selection:(Sop.Primitive_group "random_ridges")
           ~distance:0.025 ~recompute_normals:true
      |> Sop.sort ~descending:true ~owner:Pdk.Ops.Primitives
           ~key:(Pdk.Ops.Attribute_component
             { name = "primitive_id"; component = 0 })
  and tube = Sop.polyline [|(-2.,0.5,0.); (-1.,1.8,0.5); (0.,1.2,0.);
      (1.,2.,-0.5)|]
      |> Sop.resample ~maximum_segment_length:0.18
           ~curve_u_attribute:"curveu" ~tangent_attribute:"curve_tangent"
      |> Sop.sweep_circle ~sides:10 ~radius:0.12
      |> Sop.polyframe ~orthogonal:true (Pdk.Ops.Attribute_gradient "uv")
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
      |> Sop.duplicate ~copies:2
           ~transform:(Mat4.translation (Vec3.create 0. 0. (-0.35)))
      |> Sop.connectivity ~name:"copy_piece"
           ~attribute:(Pdk.Analysis.Connectivity_text "copy_")
      |> Sop.groups_from_name ~owner:Pdk.Attribute.Primitive
           ~attribute:"copy_piece"
      |> Sop.name_from_groups ~attribute:"copy_piece_round_trip"
           ~delete_groups:true ~owner:Pdk.Attribute.Primitive
      |> Sop.groups_from_name ~owner:Pdk.Attribute.Primitive
           ~attribute:"copy_piece_round_trip"
      |> Sop.peak ~selection:(Sop.Primitive_group "copy_0") ~distance:0.025
           ~recompute_normals:true
  and selected_duplicate = Sop.box ~size:(Vec3.create 0.6 0.6 0.6) ()
      |> Sop.group ~name:"duplicate_faces"
           (Select.primitive_indices [|0;2;4|])
      |> Sop.duplicate ~copies:3 ~group:"duplicate_faces"
           ~copy_group_prefix:"duplicate_copy_"
           ~transform:(Mat4.translation (Vec3.create 0.72 0. 0.))
      |> Sop.peak ~selection:(Sop.Primitive_group "duplicate_copy_2")
           ~distance:0.035 ~recompute_normals:true
      |> Sop.transform (Mat4.translation (Vec3.create (-1.1) 2.6 (-1.8)))
  and extruded = Sop.grid ~columns:2 ~rows:2 ~size:1.4 ()
      |> Sop.group ~name:"extrude_faces" Select.all_primitives
      |> Sop.poly_extrude ~group:"extrude_faces"
           ~divide:Pdk.Ops.Extrude_connected_components ~divisions:3
           ~front_group:"extrude_front" ~side_group:"extrude_side"
           ~front_boundary_group:"extrude_rim" ~distance:0.35
      |> Sop.clean ~reverse_winding:true ~delete_unused_groups:true
      |> Sop.facet ~cusp_angle:0.6 ~post_compute_normals:true
      |> Sop.measure ~total_name:"surface_area" Pdk.Analysis.Area
      |> Sop.measure ~name:"perimeter" Pdk.Analysis.Perimeter
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
      |> Sop.transform (Mat4.translation (Vec3.create 2. 0.7 1.5))
  and mirrored = Sop.box ~size:(Vec3.create 0.7 1.2 0.7) ()
      |> Sop.mirror ~origin:(Vec3.create (-0.55) 0. 0.) ~normal:Vec3.unit_x
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
      |> Sop.transform (Mat4.translation (Vec3.create (-1.5) 1. 1.))
  and transferred = Sop.attribute_transfer ~pattern:"C*"
      ~mode:(Pdk.Attribute_ops.Inverse_distance { neighbors = 4; power = 2. })
      ~max_distance:0.2 ~blend_width:0.5
      ~falloff:(Pdk.Attribute_ops.Uniform 0.8)
      ~source_group_pattern:"transfer_source*"
      ~target_group_pattern:"transfer_target*"
      ~source:(Sop.grid ~columns:12 ~rows:10 ~size:1.8 ()
        |> Sop.noise_displace ~seed:73 ~amplitude:0.35 ~frequency:1.4
        |> Sop.color_by_height ~low:(Color.hex_exn "#0ea5e9")
             ~high:(Color.hex_exn "#facc15")
        |> Sop.group ~name:"transfer_source" Select.all_points)
      ~target:(Sop.grid ~columns:14 ~rows:12 ~size:1.8 ()
        |> Sop.group ~name:"transfer_target" Select.all_points) ()
      |> Sop.transform (Mat4.translation (Vec3.create (-2.) 0.7 (-1.5)))
  and directly_copied = Sop.attribute_copy ~group_owner:Pdk.Group.Primitive
      ~rules:[Pdk.Attribute_ops.copy_rule ~owner:Pdk.Attribute.Point "Cd"]
      ~source:(Sop.grid ~columns:7 ~rows:5 ~size:1.2 ()
        |> Sop.noise_displace ~seed:734 ~amplitude:0.18 ~frequency:1.5
        |> Sop.color_by_height ~low:(Color.hex_exn "#ec4899")
             ~high:(Color.hex_exn "#fde047"))
      ~target:(Sop.grid ~columns:9 ~rows:7 ~size:1.2 ()) ()
      |> Sop.transform (Mat4.translation (Vec3.create (-3.) 2.8 (-1.5)))
  and combined_attributes = Sop.attribute_combine
      ~owner:Pdk.Attribute.Point ~destination:"Cd"
      ~layers:[
        Pdk.Attribute_ops.combine_layer ~source:"Cd" ~source_input:1
          Pdk.Attribute_ops.Combine_add;
        Pdk.Attribute_ops.combine_layer ~add:0.7
          Pdk.Attribute_ops.Combine_multiply;
      ]
      ~sources:[Sop.grid ~columns:7 ~rows:5 ~size:1.2 ()
        |> Sop.noise_displace ~seed:831 ~amplitude:0.22 ~frequency:1.7
        |> Sop.color_by_height ~low:(Color.hex_exn "#22d3ee")
             ~high:(Color.hex_exn "#fb7185")]
      ~target:(Sop.grid ~columns:9 ~rows:7 ~size:1.2 ()) ()
      |> Sop.transform (Mat4.translation (Vec3.create (-1.5) 2.8 (-1.5)))
  and interpolated_attributes = Sop.attribute_interpolate
      ~target_owner:Pdk.Attribute.Point
      ~driver:(Pdk.Attribute_ops.Point_weights {
        numbers_attribute="computed_points";
        weights_attribute="computed_weights" })
      ~point_pattern:"Cd hot" ~match_groups:true ~attributes:[]
      ~source:interpolation_source ~target:interpolation_computed ()
      |> Sop.transform (Mat4.translation (Vec3.create 0. 3.0 (-1.5)))
  and multi_transferred = Sop.attribute_transfer_all
      ~point_pattern:"Cd" ~vertex_pattern:"corner_id"
      ~primitive_pattern:"face_id" ~detail_pattern:"revision"
      ~max_distance:0.15 ~blend_width:0.35
      ~source:(Sop.grid ~columns:10 ~rows:8 ~size:1.3 ()
        |> Sop.noise_displace ~seed:731 ~amplitude:0.2 ~frequency:1.1
        |> Sop.color_by_height ~low:(Color.hex_exn "#7c3aed")
             ~high:(Color.hex_exn "#2dd4bf")
        |> Sop.set_int ~owner:Pdk.Attribute.Vertex ~name:"corner_piece" 0
        |> Sop.enumerate ~piece_attribute:"corner_piece"
             ~mode:Pdk.Attribute_ops.Enumerate_piece_elements
             ~owner:Pdk.Attribute.Vertex ~name:"corner_id"
        |> Sop.set_int ~owner:Pdk.Attribute.Primitive ~name:"face_piece" 0
        |> Sop.enumerate ~piece_attribute:"face_piece"
             ~mode:Pdk.Attribute_ops.Enumerate_piece_elements
             ~owner:Pdk.Attribute.Primitive ~name:"face_id"
        |> Sop.set_int ~owner:Pdk.Attribute.Detail ~name:"revision" 3)
      ~target:(Sop.grid ~columns:12 ~rows:10 ~size:1.3 ()
        |> Sop.transform (Mat4.translation (Vec3.create 0. 0.18 0.))) ()
      |> Sop.transform (Mat4.translation (Vec3.create 2.6 0.7 (-1.8)))
  and surface_transferred = Sop.attribute_transfer_surface
      ~target_owner:Pdk.Attribute.Vertex
      ~attributes:[
        Pdk.Attribute_ops.surface_attribute ~owner:Pdk.Attribute.Point "Cd";
        Pdk.Attribute_ops.surface_attribute ~owner:Pdk.Attribute.Point "N";
      ] ~max_distance:0.1 ~blend_width:0.5
      ~falloff:Pdk.Attribute_ops.Smoothstep
      ~distance_attribute:"surface_distance" ~source_group:"surface_source"
      ~source_vertex_group_pattern:"surface_vertex_*"
      ~target_group:"surface_target"
      ~source:(Sop.grid ~columns:16 ~rows:12 ~size:1.7 ()
        |> Sop.noise_displace ~seed:91 ~amplitude:0.28 ~frequency:1.2
        |> Sop.normals
        |> Sop.color_by_height ~low:(Color.hex_exn "#06b6d4")
             ~high:(Color.hex_exn "#f97316")
        |> Sop.group ~name:"surface_source" Select.all_primitives
        |> Sop.group ~name:"surface_vertex_patch"
             (Select.vertex_indices (Array.init 160 Fun.id)))
      ~target:(Sop.grid ~columns:18 ~rows:14 ~size:1.6 ()
        |> Sop.transform (Mat4.translation (Vec3.create 0. 0.22 0.))
        |> Sop.group ~name:"surface_target" Select.all_vertices) ()
      |> Sop.transform (Mat4.translation (Vec3.create 2.2 0.5 1.8))
  and clipped = Sop.uv_sphere ~segments:32 ~rings:20 ~radius:0.8 ()
      |> Sop.mountain ~seed:511 ~height:0.12
           ~frequency:(Vec3.create 1.7 1.2 1.5) ~octaves:5
           ~roughness:0.46
      |> Sop.peak ~distance:0.03 ~recompute_normals:true
      |> Sop.color_by_height ~low:(Color.hex_exn "#34d399")
           ~high:(Color.hex_exn "#f472b6")
      |> Sop.group_edges ~name:"render_clip_source"
      |> Sop.clip ~keep:Pdk.Ops.Above
           ~selection:(Sop.Edge_group "render_clip_source")
           ~clip_attribute:"N" ~distance:0.05
           ~clipped_edge_group:"clip_edges"
           ~origin:(Vec3.create 0.1 0. 0.)
           ~normal:(Vec3.create 1. 0.25 0.1)
      |> Sop.transform (Mat4.translation (Vec3.create 1.8 1.2 (-1.2))) in
  let concave_positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|(-0.8); 0.8; 0.8; (-0.4); (-0.4); 0.8; 0.8; (-0.8)|]
      ~y:[|(-0.8); (-0.8); (-0.4); (-0.4); 0.4; 0.4; 0.8; 0.8|]
      ~z:(Array.make 8 0.) in
  let concave_topology = Pdk.Topology.Builder.create ~point_count:8 () in
  Pdk.Topology.Builder.add_polygon concave_topology [|0;1;2;3;4;5;6;7|];
  let concave_clip = Pdk.Geometry.create ~positions:concave_positions
      ~topology:(Pdk.Topology.Builder.freeze concave_topology) ()
      |> Result.get_ok |> Pdk.Ops.poly_extrude ~distance:0.35 |> Result.get_ok
      |> Sop.snapshot
      |> Sop.clip ~fill:true ~cap_group:"concave_caps"
           ~origin:Vec3.zero ~normal:Vec3.unit_x
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fbbf24")
      |> Sop.transform (Mat4.translation (Vec3.create 3.2 3.2 0.8)) in
  let nested_clip = hollow_square_prism () |> Sop.snapshot
      |> Sop.clip ~fill:true ~cap_group:"nested_caps"
           ~origin:Vec3.zero ~normal:Vec3.unit_x
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
      |> Sop.transform (Mat4.translation (Vec3.create 3.1 1.9 0.8)) in
  let curve_positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:[|(-0.65);0.;0.8|] ~y:[|0.;0.8;0.|] ~z:[|0.;0.;0.|] in
  let curve_topology = Pdk.Topology.create_owned ~point_count:3
      ~vertex_points:[|0;1; 1;2|] ~primitive_offsets:[|0;2;4|]
      ~primitive_kinds:[|Pdk.Topology.Open_polyline;
        Pdk.Topology.Open_polyline|] |> Result.get_ok in
  let curve_geometry = Pdk.Geometry.create ~positions:curve_positions
      ~topology:curve_topology () |> Result.get_ok in
  let shared_curve_subdivision = Sop.snapshot curve_geometry
      |> Sop.subdivide ~iterations:3
      |> Sop.polywire ~sides:8 ~caps:true ~radius:0.025
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
      |> Sop.transform (Mat4.translation (Vec3.create (-0.9) 3.6 1.5))
  and independent_curve_subdivision = Sop.snapshot curve_geometry
      |> Sop.subdivide ~iterations:3 ~treat_curves_as_independent:true
      |> Sop.polywire ~sides:8 ~caps:true ~radius:0.025
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316")
      |> Sop.transform (Mat4.translation (Vec3.create 0.9 3.6 1.5)) in
  let subdivided = Sop.box ~size:(Vec3.create 1.1 1.1 1.1) ()
      |> Sop.fuse ~tolerance:0. ~attributes:Pdk.Ops.Average_numeric
      |> Sop.normals
      |> Sop.group ~name:"local_subdivision"
           (Select.primitive_indices [|0;2;4;6;8;10|])
      |> Sop.reverse ~group:"local_subdivision"
           ~operation:(Pdk.Ops.Shift_vertices 1)
      |> Sop.subdivide ~group:"local_subdivision"
           ~consistent_topology:true
           ~cracks:Pdk.Ops.Subdivide_stitch_divide_edges
           ~scheme:Pdk.Ops.Catmull_clark ~iterations:3
           ~recompute_point_normals:true
      |> Sop.attribute_randomize ~seed:513 ~operation:Pdk.Attribute_ops.Random_add
           ~direction_bias:0.5 ~scale:0.008 ~owner:Pdk.Attribute.Point ~name:"P"
           (Pdk.Attribute_ops.Random_inside_sphere_cone {
             direction = Pdk.Attribute_ops.Vec3 Vec3.unit_y;
             cone_angle = Float.pi /. 2.;
           })
      |> Sop.group_non_planar ~tolerance:0.0001 ~name:"warped_faces"
      |> Sop.peak ~selection:(Sop.Primitive_group "warped_faces")
           ~distance:0.01 ~recompute_normals:true
      |> Sop.group_backface ~viewpoint:(Vec3.create 0. 0. 5.)
           ~name:"backfaces"
      |> Sop.peak ~selection:(Sop.Primitive_group "backfaces")
           ~distance:(-0.012) ~recompute_normals:true
      |> Sop.group ~name:"render_faces" Select.all_primitives
      |> Sop.triangulate ~group:"render_faces"
      |> Sop.attribute_randomize ~seed:514 ~direction_bias:0.6
           ~owner:Pdk.Attribute.Point ~name:"N"
           (Pdk.Attribute_ops.Random_direction {
             direction = Pdk.Attribute_ops.Vec3 Vec3.unit_y;
             cone_angle = Float.pi /. 2.;
           })
      |> Sop.peak ~distance:0.015 ~recompute_normals:true
      |> Sop.normals ~owner:Pdk.Attribute.Vertex
           ~weighting:Pdk.Ops.Vertex_angle ~cusp_angle:(Float.pi /. 3.)
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 1.5 1.8)) in
  let pulled_subdivision = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:3 ~rows:3 ~size:0.9 ()
      |> Sop.mountain ~seed:612 ~height:0.16
           ~frequency:(Vec3.create 1.4 1.1 1.6) ~octaves:3
      |> Sop.group ~name:"pulled_patch" (Select.primitive_indices [|4|])
      |> Sop.subdivide ~group:"pulled_patch"
           ~cracks:(Pdk.Ops.Subdivide_pull_triangulate 0.75)
           ~scheme:Pdk.Ops.Catmull_clark ~iterations:2
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
      |> Sop.transform (Mat4.translation (Vec3.create (-1.4) 1.5 1.8)) in
  let smooth_triangles = Sop.grid ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:12 ~rows:10 ~size:1.1 ()
      |> Sop.mountain ~seed:731 ~height:0.24
           ~frequency:(Vec3.create 1.9 1.4 1.7) ~octaves:4
      |> Sop.subdivide ~scheme:Pdk.Ops.Catmull_clark
           ~triangle_policy:Pdk.Ops.Subdivide_triangles_smooth
           ~crease_weight:2.5
           ~resulting_crease_group:"all_edge_creases"
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
      |> Sop.transform (Mat4.translation (Vec3.create (-2.8) 1.5 1.8)) in
  let crease_topology = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:12 ~rows:10 ~size:1.1 ()
      |> Sop.group ~name:"crease_points"
           (Select.point_indices [|0;1;2;3;13;14;15;16;26;27;28;29|])
      |> Sop.attribute_randomize ~seed:818
           ~selection:(Sop.Point_group "crease_points")
           ~minimum:(Pdk.Attribute_ops.Scalar 0.25)
           ~maximum:(Pdk.Attribute_ops.Scalar 3.5)
           ~owner:Pdk.Attribute.Vertex ~name:"creaseweight"
           (Pdk.Attribute_ops.Random_cauchy {
             median = Pdk.Attribute_ops.Scalar 1.5;
             scale = Pdk.Attribute_ops.Scalar 0.65;
           }) in
  let second_input_creased = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:12 ~rows:10 ~size:1.1 ()
      |> Sop.mountain ~seed:819 ~height:0.22
           ~frequency:(Vec3.create 1.8 1.3 1.6) ~octaves:4
      |> Sop.uv_project (Pdk.Ops.Planar {
           origin = Vec3.zero; u_axis = Vec3.unit_x; v_axis = Vec3.unit_z })
      |> Sop.group ~name:"subdivision_hole"
           (Select.primitive_indices [|53;54;65;66|])
      |> Sop.set_int ~owner:Pdk.Attribute.Detail ~name:"osd_scheme" 0
      |> Sop.set_int ~owner:Pdk.Attribute.Detail
           ~name:"osd_vtxboundaryinterpolation" 1
      |> Sop.set_int ~owner:Pdk.Attribute.Detail
           ~name:"osd_fvarlinearinterpolation" 0
      |> Sop.set_int ~owner:Pdk.Attribute.Detail ~name:"osd_creasingmethod" 1
      |> Sop.set_int ~owner:Pdk.Attribute.Detail ~name:"osd_trianglesubdiv" 1
      |> Sop.subdivide ~creases:crease_topology
           ~resulting_crease_group:"remaining_creases"
           ~boundary_interpolation:Pdk.Ops.Subdivide_boundary_none
           ~face_varying_interpolation:Pdk.Ops.Subdivide_fvar_all
           ~creasing_method:Pdk.Ops.Subdivide_creasing_uniform
           ~scheme:Pdk.Ops.Bilinear ~iterations:2
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
      |> Sop.transform (Mat4.translation (Vec3.create 1.4 1.5 1.8)) in
  let blasted = Sop.grid ~columns:18 ~rows:18 ~size:1.6 ()
      |> Sop.group ~name:"cutout"
           (Select.points_in_bounds ~min:(Vec3.create (-0.3) (-0.1) (-0.3))
             ~max:(Vec3.create 0.3 0.1 0.3))
      |> Sop.blast ~owner:Pdk.Group.Point ~group:"cutout" ~compact_points:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb923c")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 0.8 (-2.2))) in
  let uv_mapped = Sop.uv_sphere ~segments:48 ~rings:28 ~radius:0.65 ()
      |> Sop.uv_project
           (Pdk.Ops.Spherical { origin = Vec3.zero; axis = Vec3.unit_y;
             seam = Vec3.unit_x })
      |> Sop.uv_transform ~scale:(Vec2.create 5. 3.)
      |> Sop.uv_auto_seam ~angle:(Float.pi /. 3.) ~existing_uv:"uv"
      |> Sop.uv_unitize ~seams:"uv_seams" Pdk.Ops.Islands
      |> Sop.transform (Mat4.translation (Vec3.create (-0.2) 2.5 (-1.7))) in
  let converted_wire = Sop.grid ~columns:3 ~rows:2 ~size:1.2 ()
      |> Sop.enumerate ~owner:Pdk.Attribute.Primitive ~name:"face_id"
      |> Sop.group ~name:"wire_faces" Select.all_primitives
      |> Sop.group_promote_boundary ~source:Pdk.Ops.Group_primitives
           ~destination:Pdk.Ops.Group_edges ~group:"wire_faces"
           ~name:"wire_edges" ~include_unshared_edges:true ~attributes:[{
           Pdk.Ops.boundary_attribute_owner = Pdk.Attribute.Primitive;
           boundary_attribute_pattern = "face_id" }]
      |> Sop.convert_line ~group:"wire_edges" ~connect_path:true
           ~maximum_distance:0.
      |> Sop.polywire ~sides:6 ~caps:true ~radius:0.025
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2dd4bf")
      |> Sop.transform (Mat4.translation (Vec3.create 1.5 2.8 0.4)) in
  let ends_wire = Sop.box ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true ~size:(Vec3.create 0.9 0.75 0.8) ()
      |> Sop.ends Pdk.Ops.Ends_unroll_shared
      |> Sop.polywire ~sides:6 ~caps:true ~radius:0.018
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15")
      |> Sop.transform (Mat4.translation (Vec3.create (-1.5) 2.8 0.4)) in
  let generated_line = Sop.line ~points:18 ~origin:(Vec3.create (-2.) 0. 0.)
      ~direction:(Vec3.create 0.2 1. 0.1) ~length:1.5 ()
      |> Sop.set_float ~owner:Pdk.Attribute.Primitive ~name:"first_u" 0.08
      |> Sop.set_float ~owner:Pdk.Attribute.Primitive ~name:"second_u" 0.92
      |> Sop.carve ~first_attribute:"first_u" ~last_attribute:"second_u"
           ~divisions:5
           ~keep:Pdk.Ops.Keep_inside_and_outside
      |> Sop.polywire ~sides:8 ~caps:true ~radius:0.04
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 1.6 0.)) in
  let open_ellipse = Sop.circle
      ~arc:(Pdk.Ops.Circle_open_arc {
        start_angle = -0.6; end_angle = 4.7 })
      ~orientation:Pdk.Ops.Circle_xy ~reverse:true
      ~center:(Vec3.create (-2.7) 3.5 (-0.3))
      ~radius_x:0.7 ~radius_y:0.35 ~rotation:0.35
      ~segments:48 ~radius:1. ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8") in
  let sliced_ellipse = Sop.circle
      ~arc:(Pdk.Ops.Circle_sliced_arc {
        start_angle = 0.2; end_angle = 4.9 })
      ~orientation:(Pdk.Ops.Circle_axes {
        horizontal = Vec3.create 1. 0.1 0.25;
        vertical = Vec3.create (-0.2) 1. 0.4 })
      ~center:(Vec3.create 2.7 3.4 0.4) ~radius_x:0.65 ~radius_y:0.4
      ~rotation:(-0.2) ~segments:48 ~radius:1. ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a3e635") in
  let bent_panel = Sop.grid ~columns:32 ~rows:20 ~size:1.5 ()
      |> Sop.bend ~origin:(Vec3.create 0. 0. (-0.75))
           ~direction:Vec3.unit_z ~up:Vec3.unit_y ~length:1.5
           ~bend_angle:1.2 ~twist_angle:0.8 ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#60a5fa")
      |> Sop.transform (Mat4.translation (Vec3.create 1.2 2.5 (-2.1))) in
  let jittered_panel = Sop.grid ~columns:24 ~rows:18 ~size:1.3 ()
      |> Sop.group ~name:"jitter_patch"
           (Select.points_in_bounds ~min:(Vec3.create (-0.5) (-0.1) (-0.5))
              ~max:(Vec3.create 0.5 0.1 0.5))
      |> Sop.set_float ~owner:Pdk.Attribute.Point ~name:"jitter_mask" 0.75
      |> Sop.set_float ~owner:Pdk.Attribute.Point ~name:"pscale" 0.8
      |> Sop.enumerate ~owner:Pdk.Attribute.Point ~name:"jitter_id"
      |> Sop.point_jitter ~label:"render-jitter" ~group:"jitter_patch"
           ~mask_attribute:"jitter_mask" ~id_attribute:"jitter_id"
           ~use_point_scale:true ~seed:821 ~scale:0.32
           ~axis_scales:(Vec3.create 1. 0.45 1.)
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#34d399")
      |> Sop.transform (Mat4.translation (Vec3.create (-1.2) 2.5 (-2.1))) in
  let edge_divided_panel = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:5 ~rows:4 ~size:1.1 ()
      |> Sop.group_edges ~name:"divide_edges"
      |> Sop.edge_divide ~group:"divide_edges" ~divisions:4
      |> Sop.mountain ~seed:829 ~height:0.11
           ~frequency:(Vec3.create 3.1 2.3 2.7) ~octaves:3
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f59e0b")
      |> Sop.transform (Mat4.translation (Vec3.create (-2.8) (-0.6) 2.3)) in
  let edge_collapsed_panel = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:9 ~rows:7 ~size:1.1 ()
      |> Sop.group_random ~seed:839 ~probability:0.13
           ~owner:Pdk.Ops.Group_edges ~name:"collapse_edges"
      |> Sop.edge_collapse ~group:"collapse_edges"
      |> Sop.mountain ~seed:840 ~height:0.09
           ~frequency:(Vec3.create 3.4 2.7 2.1) ~octaves:3
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
      |> Sop.transform (Mat4.translation (Vec3.create 2.8 (-0.6) 2.3)) in
  let edge_flipped_panel = Sop.grid ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:1 ~rows:1 ~size:1.1 ()
      |> Sop.group_edges ~name:"flip_edge" ~incidence:Pdk.Ops.Manifold_edge
      |> Sop.edge_flip ~group:"flip_edge"
      |> Sop.mountain ~seed:841 ~height:0.14
           ~frequency:(Vec3.create 2.9 2.2 3.3) ~octaves:3
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f0abfc")
      |> Sop.transform (Mat4.translation (Vec3.create 0. (-0.6) 2.3)) in
  let edge_cusped_panel = Sop.grid ~connectivity:Pdk.Ops.Grid_triangles
      ~columns:8 ~rows:6 ~size:1.1 ()
      |> Sop.mountain ~seed:843 ~height:0.18
           ~frequency:(Vec3.create 3.7 2.6 3.1) ~octaves:3
      |> Sop.group_edges ~name:"cusp_edges"
      |> Sop.edge_cusp ~group:"cusp_edges"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#67e8f9")
      |> Sop.transform (Mat4.translation (Vec3.create 0. (-2.0) 2.3)) in
  let dissolved_panel = Sop.grid ~connectivity:Pdk.Ops.Grid_quads
      ~columns:6 ~rows:4 ~size:1.1 ()
      |> Sop.group_edges ~name:"dissolve_interior"
           ~incidence:Pdk.Ops.Manifold_edge
      |> Sop.dissolve ~group:"dissolve_interior" ~remove_inline_points:true
           ~collinearity_tolerance:1e-10
      |> Sop.poly_extrude ~distance:0.16
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a3e635")
      |> Sop.transform (Mat4.translation (Vec3.create 1.5 (-2.0) 2.3)) in
  let reduced_panel = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:30 ~rows:22 ~size:1.15 ()
      |> Sop.mountain ~seed:847 ~height:0.2
           ~frequency:(Vec3.create 4.2 2.8 3.6) ~octaves:4
           ~recompute_normals:true
      |> Sop.poly_reduce ~target:(Pdk.Ops.Reduce_ratio 0.28)
           ~preserve_boundary:true ~equalize_lengths:1e-7
           ~max_normal_deviation:0.65 ~output_group:"reduced_faces"
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316")
      |> Sop.transform (Mat4.translation (Vec3.create (-3.0) (-2.0) 0.2)) in
  let lofted_shell =
    let ring height radius phase = Sop.polyline ~closed:true
        (Array.init 18 (fun point ->
          let angle = phase +. (2. *. Float.pi *. float_of_int point /. 18.) in
          radius *. cos angle, height, radius *. sin angle)) in
    Sop.merge [ring (-0.55) 0.22 0.; ring (-0.18) 0.5 0.08;
      ring 0.2 0.34 (-0.05); ring 0.58 0.46 0.12]
    |> Sop.poly_loft ~output_group:"loft_faces"
         ~minimize:Pdk.Ops.Three_point_distance
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.9
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6")
    |> Sop.transform (Mat4.translation (Vec3.create (-1.5) (-2.0) 1.0)) in
  let skinned_shell =
    let ring height radius phase = Sop.polyline ~closed:true
        (Array.init 18 (fun point ->
          let angle = phase +. (2. *. Float.pi *. float_of_int point /. 18.) in
          radius *. cos angle, height, radius *. sin angle)) in
    Sop.merge [ring (-0.55) 0.32 0.; ring (-0.2) 0.54 0.07;
      ring 0.2 0.38 (-0.04); ring 0.55 0.48 0.1]
    |> Sop.skin ~output_group:"skin_faces"
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.9
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2dd4bf")
    |> Sop.transform (Mat4.translation (Vec3.create 1.5 (-2.0) 1.0)) in
  let bridged_tube = Sop.snapshot (bridge_rings ())
    |> Sop.poly_bridge ~source_group:"bridge_source"
         ~destination_group:"bridge_destination" ~reverse_destination:true
         ~pairing_shift:2 ~divisions:6 ~output_group:"bridge_faces"
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.9
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
    |> Sop.transform (Mat4.translation (Vec3.create 3.0 (-2.0) 0.2)) in
  let straightened_wire = Sop.polyline (Array.init 17 (fun point ->
      let t = float_of_int point /. 16. in
      (t *. 1.5) -. 0.75, 0.22 *. sin (t *. 4. *. Float.pi), 0.))
      |> Sop.group_edges ~name:"wire_edges"
      |> Sop.edge_straighten ~group:"wire_edges"
           ~output_group:"straightened_wire"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fde047")
      |> Sop.transform (Mat4.translation (Vec3.create 0. (-3.0) 2.3)) in
  let scattered =
    let prototype = Sop.box ~size:(Vec3.create 0.045 0.045 0.045) ()
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6") in
    let targets = Sop.grid ~columns:24 ~rows:18 ~size:1.5 ()
        |> Sop.attribute_randomize ~seed:519 ~owner:Pdk.Attribute.Point
             ~name:"density" (Pdk.Attribute_ops.Random_uniform {
               min = Pdk.Attribute_ops.Scalar 0.;
               max = Pdk.Attribute_ops.Scalar 1.;
             })
        |> Sop.scatter ~seed:520 ~count:220
             ~density:(Pdk.Ops.scatter_density ~owner:Pdk.Attribute.Point
               "density")
             ~source_primitive_attribute:"source_primitive"
        |> Sop.transform (Mat4.translation (Vec3.create (-1.1) 2.8 (-2.1))) in
    Sop.copy_to_points ~source:prototype ~targets () in
  let piece_matched_copies =
    let source = Sop.merge [
      Sop.box ~size:(Vec3.create 0.12 0.38 0.12) ()
      |> Sop.set_int ~owner:Pdk.Attribute.Primitive ~name:"variant" 0
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185");
      Sop.box ~size:(Vec3.create 0.34 0.12 0.22) ()
      |> Sop.set_int ~owner:Pdk.Attribute.Primitive ~name:"variant" 1
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")]
    and targets = Sop.merge [
      Sop.points [|(-0.6,0.,0.); (0.6,0.,0.)|]
      |> Sop.set_int ~owner:Pdk.Attribute.Point ~name:"variant" 1;
      Sop.points [|(0.,0.6,0.)|]
      |> Sop.set_int ~owner:Pdk.Attribute.Point ~name:"variant" 0;
      Sop.points [|(0.,-0.6,0.)|]
      |> Sop.set_int ~owner:Pdk.Attribute.Point ~name:"variant" 99] in
    Sop.copy_to_points ~piece_attribute:"variant" ~source ~targets ()
    |> Sop.transform (Mat4.translation (Vec3.create 1.5 2.9 0.7)) in
  let extracted_dots =
    let prototype = Sop.box ~size:(Vec3.create 0.05 0.05 0.05) ()
        |> Sop.group ~name:"dot_faces" Select.all_primitives in
    let targets = Sop.polyline [|(-1.,0.,0.); (-0.3,0.8,0.);
        (0.4,-0.2,0.); (1.,0.7,0.)|]
        |> Sop.carve ~first:0.05 ~last:0.95 ~extract_points:true
             ~divisions:17
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"v" Vec3.unit_y
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"up" Vec3.unit_z
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"pivot"
             (Vec3.create 0.05 0. 0.)
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"trans"
             (Vec3.create 0.02 0. 0.)
        |> Sop.set_transform (Mat4.mul (Mat4.rotation_z 0.35)
             (Mat4.scaling (Vec3.create 0.8 1.2 1.)))
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#c084fc")
        |> Sop.group ~name:"dot_targets"
             (Select.point_indices [|0;2;4;6;8;10;12;14;16|])
        |> Sop.group ~name:"visible_targets"
             (Select.point_indices [|0;4;8;12;16|]) in
    Sop.copy_to_points ~source_group:"dot_faces" ~target_group:"dot_targets"
      ~target_attributes:Pdk.Ops.[
        { copy_target_pattern = "Cd";
          copy_target_owner = Copy_target_points;
          copy_target_operation = Copy_target_copy };
        { copy_target_pattern = "visible_targets";
          copy_target_owner = Copy_target_primitives;
          copy_target_operation = Copy_target_copy };
      ] ~source:prototype ~targets ()
    |> Sop.blast ~selected:false ~compact_points:true
         ~owner:Pdk.Group.Primitive ~group:"visible_targets"
    |> Sop.transform (Mat4.translation (Vec3.create 2.7 3.0 (-0.8))) in
  let closest_join_wire = Sop.merge [
      Sop.polyline [|(-0.9,0.,0.); (-0.45,0.25,0.1)|];
      Sop.polyline [|(0.45,0.35,-0.1); (0.9,0.05,0.)|];
      Sop.polyline [|(0.,0.65,0.15); (-0.45,0.25,0.1)|];
      Sop.polyline [|(0.45,0.35,-0.1); (0.,0.65,0.15)|]]
      |> Sop.join_curves ~connect_closest_ends:true ~group_size:2
      |> Sop.polywire ~sides:8 ~caps:true ~radius:0.025
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fbbf24")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 3.1 (-2.4))) in
  let picked_join_wire = Sop.merge [
      Sop.polyline [|(-0.8,-0.4,0.); (-0.2,-0.2,0.1)|];
      Sop.polyline [|(0.3,0.3,-0.1); (0.8,0.1,0.)|];
      Sop.polyline [|(0.2,0.5,0.15); (-0.2,-0.2,0.1)|];
      Sop.polyline [|(0.3,0.3,-0.1); (0.2,0.5,0.15)|];
    ] |> Sop.join_curves ~picked_ends:[|
      { Pdk.Ops.primitive = 0; end_ = Pdk.Ops.Join_curve_end };
      { Pdk.Ops.primitive = 2; end_ = Pdk.Ops.Join_curve_end };
      { Pdk.Ops.primitive = 3; end_ = Pdk.Ops.Join_curve_end };
      { Pdk.Ops.primitive = 1; end_ = Pdk.Ops.Join_curve_start };
    |]
      |> Sop.polywire ~sides:8 ~caps:true ~radius:0.03
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
      |> Sop.transform (Mat4.translation (Vec3.create 1.4 4.7 (-2.3))) in
  let promoted_piece = Sop.grid ~columns:10 ~rows:8 ~size:1.4 ()
      |> Sop.noise_displace ~seed:117 ~amplitude:0.3 ~frequency:1.1
      |> Sop.color_by_height ~low:(Color.hex_exn "#2563eb")
           ~high:(Color.hex_exn "#f97316")
      |> Sop.rename_attributes ~rules:[{
           Pdk.Attribute_ops.rename_attribute_owner = Some Pdk.Attribute.Point;
           rename_attribute_pattern = "Cd";
           rename_attribute_replacement = "source_Cd";
           rename_attribute_conflict = Pdk.Attribute_ops.Attribute_rename_error }]
      |> Sop.set_float ~owner:Pdk.Attribute.Point ~name:"input_weight" 1.
      |> Sop.set_int ~owner:Pdk.Attribute.Vertex ~name:"piece" 0
      |> Sop.promote_attributes ~method_:Pdk.Attribute_ops.Median
           ~piece_attribute:"piece" ~delete_source:false
           ~source:Pdk.Attribute.Point ~destination:Pdk.Attribute.Vertex
           ~pattern:"source_* input_weight" ~into_pattern:"* median_weight"
      |> Sop.promote_attribute ~method_:Pdk.Attribute_ops.Array_all
           ~delete_source:false ~source:Pdk.Attribute.Point
           ~destination:Pdk.Attribute.Primitive ~name:"input_weight"
           ~into:"face_weights"
      |> Sop.promote_attribute ~method_:Pdk.Attribute_ops.Maximum
           ~piece_attribute:"piece" ~delete_source:false
           ~index_attribute:"weight_source" ~source:Pdk.Attribute.Point
           ~destination:Pdk.Attribute.Vertex ~name:"input_weight" ~into:"weight"
      |> Sop.delete_attributes ~point_pattern:"source_Cd input_weight"
      |> Sop.transform (Mat4.translation (Vec3.create (-2.1) 2.4 1.3)) in
  let swapped_rest_patch =
    let source = Pdk.Ops.grid ~columns:12 ~rows:10 ~size:1.4 ()
        |> Result.get_ok in
    let positions = Pdk.Packed.Float3.Private.view
        (Pdk.Geometry.positions source) in
    let rest = Pdk.Packed.Float3.of_owned
        ~x:(Array.copy positions.x)
        ~y:(Array.init (Array.length positions.y) (fun point ->
          0.28 *. sin ((positions.x.(point) *. 4.)
            +. (positions.z.(point) *. 3.))))
        ~z:(Array.copy positions.z) |> Result.get_ok in
    let reference = Pdk.Geometry.with_positions rest source |> Result.get_ok in
    let origin = Pdk.Ops.points (Array.make (Pdk.Geometry.point_count source)
          (0., 0., 0.)) in
    let restored = Sop.snapshot source
        |> Sop.rest_position ~reference:(Sop.snapshot reference)
             Pdk.Motion.Store_rest
        |> Sop.rest_position Pdk.Motion.Extract_rest in
    restored
    |> Sop.point_velocity ~previous:(Sop.snapshot origin) ~dt:1.
    |> Sop.swap_attributes ~rules:[{
         Pdk.Attribute_ops.swap_attribute_owner = Pdk.Attribute.Point;
         swap_attribute_source = "P";
         swap_attribute_destination = "v";
         swap_attribute_method = Pdk.Attribute_ops.Attribute_swap }]
    |> Sop.normals ~owner:Pdk.Attribute.Vertex
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#34d399")
    |> Sop.transform (Mat4.translation (Vec3.create 2.1 2.4 1.3))
  in
  let grown_source = Sop.grid ~columns:12 ~rows:10 ~size:1.4 ()
      |> Sop.group_ranges [Pdk.Ops.group_range_rule
           ~connectivity:(Pdk.Ops.Range_connected {
             connectivity_attributes = None;
             connectivity_tolerance = 1e-6;
             collision = None;
             region = None;
             remove_other_regions = false })
           ~filter:{ select = 2; of_ = 7; offset = 1 }
           ~owner:Pdk.Ops.Group_points ~name:"bands"
           (Pdk.Ops.Range_from_ends { start = 3; end_offset = 3 });
         Pdk.Ops.group_range_rule ~owner:Pdk.Ops.Group_points
           ~name:"unused_range"
           (Pdk.Ops.Range_start_end { start = 0; end_ = 0 })] in
  let grown_target = Sop.grid ~columns:12 ~rows:10 ~size:1.4 ()
      |> Sop.group ~name:"seed"
           (Select.points_in_bounds ~min:(Vec3.create (-0.1) (-1.) (-0.1))
              ~max:(Vec3.create 0.1 1. 0.1)) in
  let grown_patch = Sop.group_transfer ~distance:0.
      ~rules:[{ Pdk.Ops.transfer_owner = Pdk.Ops.Group_points;
        transfer_pattern = "bands"; transfer_prefix = "" }]
      ~source:grown_source ~target:grown_target ()
      |> Sop.group_combine ~owner:Pdk.Ops.Group_points ~name:"selection"
           ~base:{ Pdk.Ops.pattern = "seed"; inverted = false }
           ~steps:[{ Pdk.Ops.operation = Pdk.Ops.Group_union;
             operand = { pattern = "bands"; inverted = false } }]
      |> Sop.group_expand ~steps:2 ~owner:Pdk.Ops.Group_points ~group:"selection"
      |> Sop.group_combine ~owner:Pdk.Ops.Group_points ~name:"outside"
           ~base:{ Pdk.Ops.pattern = "selection"; inverted = false } ~steps:[]
      |> Sop.group_invert ~owner:Pdk.Ops.Group_points ~pattern:"outside"
      |> Sop.group_delete ~rules:[
           { Pdk.Ops.delete_owner = Some Pdk.Ops.Group_points;
             delete_pattern = "outside bands seed" }]
      |> Sop.group_promotions [
           Pdk.Ops.group_promote_rule ~new_name:"grown_faces"
             ~keep_original:true ~mode:Pdk.Ops.Include_shared_edge
             ~source:Pdk.Ops.Group_points
             ~destination:Pdk.Ops.Group_primitives ~pattern:"selection" ();
           Pdk.Ops.group_promote_rule ~new_name:"unused_promoted_edges"
             ~keep_original:true ~mode:Pdk.Ops.Include_all
             ~source:Pdk.Ops.Group_points ~destination:Pdk.Ops.Group_edges
             ~pattern:"selection" ()]
      |> Sop.peak ~selection:(Sop.Primitive_group "grown_faces") ~distance:0.28
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
      |> Sop.transform (Mat4.translation (Vec3.create (-2.7) 1.7 (-0.2))) in
  let constrained_growth = Sop.snapshot (constrained_growth_strip ())
      |> Sop.group_expand ~flood:true
           ~primitive_connectivity:Pdk.Ops.Primitive_share_edges
           ~normal_spread:0.2
           ~connectivity_attributes:[{
             Pdk.Ops.boundary_attribute_owner = Pdk.Attribute.Primitive;
             boundary_attribute_pattern = "region" }]
           ~owner:Pdk.Ops.Group_primitives ~group:"growth_seed"
      |> Sop.blast ~selected:false ~compact_points:true
           ~owner:Pdk.Group.Primitive ~group:"growth_seed"
      |> Sop.normals ~owner:Pdk.Attribute.Vertex
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
      |> Sop.transform (Mat4.translation (Vec3.create 0.2 5.1 (-1.8))) in
  let transformed_patch = Sop.box ~size:(Vec3.create 1.1 1.1 1.1)
      ~x_divisions:5 ~y_divisions:5 ~z_divisions:5
      ~normals:Pdk.Ops.Box_point_normals ()
      |> Sop.group ~name:"transform_top"
           (Select.points_in_bounds ~min:(Vec3.create (-1.) 0.05 (-1.))
              ~max:(Vec3.create 1. 1. 1.))
      |> Sop.transform_trs ~order:Pdk.Ops.Transform_srt
           ~rotation_order:Pdk.Ops.Transform_zyx
           ~translate:(Vec3.create 0.15 0.35 (-0.1))
           ~rotate:(Vec3.create 0.15 (-0.25) 0.45)
           ~scale:(Vec3.create 0.7 1.35 0.85)
           ~shear:(Vec3.create 0.2 (-0.12) 0.08)
           ~pivot:(Vec3.create 0. 0.05 0.)
           ~selection:(Sop.Point_group "transform_top")
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15")
      |> Sop.transform (Mat4.translation (Vec3.create 2.7 5.1 (-1.8))) in
  let soft_transformed_patch = Sop.grid ~columns:24 ~rows:24 ~size:1.5 ()
      |> Sop.group ~name:"soft_seed"
           (Select.points_in_bounds ~min:(Vec3.create (-0.04) (-0.1) (-0.04))
              ~max:(Vec3.create 0.04 0.1 0.04))
      |> Sop.soft_transform_trs ~metric:Pdk.Ops.Soft_edge
           ~falloff:Pdk.Ops.Soft_cubic ~radius:0.72
           ~translate:(Vec3.create 0. 0.75 0.)
           ~rotate:(Vec3.create 0. 0.35 0.)
           ~scale:(Vec3.create 0.72 1. 0.72)
           ~falloff_attribute:"soft_weight"
           ~selection:(Sop.Point_group "soft_seed")
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
      |> Sop.transform (Mat4.translation (Vec3.create (-2.7) 5.1 (-1.8))) in
  let distance_deformed_patch = Sop.grid ~columns:24 ~rows:24 ~size:1.5 ()
      |> Sop.group ~name:"distance_seed"
           (Select.points_in_bounds ~min:(Vec3.create (-0.04) (-0.1) (-0.04))
              ~max:(Vec3.create 0.04 0.1 0.04))
      |> Sop.distance_along_geometry
           ~start:(Sop.Point_group "distance_seed")
           ~radius:(Pdk.Ops.Distance_fixed 0.72)
           ~falloff:Pdk.Ops.Soft_cubic ~mask_attribute:"distance_mask"
      |> Sop.soft_transform_trs
           ~metric:(Pdk.Ops.Soft_attribute {
             attribute = "distance_mask"; apply_rolloff = false })
           ~translate:(Vec3.create 0. 0.75 0.)
           ~rotate:(Vec3.create 0. (-0.35) 0.)
           ~scale:(Vec3.create 0.72 1. 0.72)
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 6.8 (-1.8))) in
  let distance_reference = Sop.uv_sphere ~rings:18 ~segments:28 ~radius:0.48 ()
      |> Sop.transform (Mat4.translation (Vec3.create 0.28 0. 0.)) in
  let distance_from_patch = Sop.grid ~columns:24 ~rows:24 ~size:1.7 ()
      |> Sop.distance_from_geometry ~reference:distance_reference
           ~reference_kind:Pdk.Ops.Distance_reference_primitives
           ~distance_attribute:None ~radius:(Pdk.Ops.Distance_fixed 0.42)
           ~falloff:Pdk.Ops.Soft_cubic ~mask_attribute:"surface_mask"
      |> Sop.peak ~mask_attribute:"surface_mask" ~distance:0.52
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb923c")
      |> Sop.transform (Mat4.translation (Vec3.create 2.7 6.8 (-1.8))) in
  let distance_target_patch = Sop.grid ~columns:24 ~rows:24 ~size:1.7 ()
      |> Sop.distance_from_target
           ~projection:Pdk.Ops.Distance_target_cylindrical
           ~origin:(Vec3.create 0.22 0. (-0.18))
           ~direction:(Vec3.create 0.35 1. 0.2)
           ~distance_attribute:None ~radius:(Pdk.Ops.Distance_fixed 0.78)
           ~falloff:Pdk.Ops.Soft_cubic ~mask_attribute:"target_mask"
      |> Sop.peak ~mask_attribute:"target_mask" ~distance:0.48
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#34d399")
      |> Sop.transform (Mat4.translation (Vec3.create (-2.7) 6.8 (-1.8))) in
  let sorted_jitter_patch = Sop.grid ~columns:24 ~rows:24 ~size:1.55 ()
      |> Sop.sort ~owner:Pdk.Ops.Points ~key:(Pdk.Ops.Random 86243L)
           ~output_indices:"sort_rank"
      |> Sop.point_jitter ~seed:613 ~id_attribute:"sort_rank" ~scale:0.035
           ~axis_scales:(Vec3.create 1. 0.35 1.)
      |> Sop.normals ~owner:Pdk.Attribute.Vertex
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#818cf8")
      |> Sop.attribute_fade ~start_attribute:"sort_rank"
           ~start_retime:(0., -0.016) ~fade_in:4. ~fade_hold:2. ~fade_out:4.
           ~fade_in_ramp:[0.,0.;0.35,0.12;0.72,0.9;1.,1.]
           ~fade_out_ramp:[0.,1.;0.28,0.92;0.7,0.12;1.,0.]
           ~visualize:true
      |> Sop.transform (Mat4.translation (Vec3.create 0. 6.8 0.8)) in
  let attribute_blast_patch = Sop.grid ~columns:24 ~rows:24 ~size:1.55 ()
      |> Sop.enumerate ~owner:Pdk.Attribute.Primitive ~name:"blast_id"
      |> Sop.blast_by_attribute ~remove_unused_points:true
           ~owner:Pdk.Ops.Blast_primitives ~attribute:"blast_id"
           ~mode:(Pdk.Ops.Blast_width { center = 576.; width = 300. })
           ~output:Pdk.Ops.Blast_delete
      |> Sop.normals ~owner:Pdk.Attribute.Vertex
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316")
      |> Sop.transform (Mat4.translation (Vec3.create 2.7 6.8 0.8)) in
  let crease_patch = Sop.snapshot (crease_box_source ())
      |> Sop.crease ~group:"feature_edges" ~operation:Pdk.Ops.Crease_set
           ~weight:2.5 ~add_vertex_color:true
      |> Sop.subdivide ~iterations:2 ~scheme:Pdk.Ops.Catmull_clark
      |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:Float.pi
      |> Sop.transform (Mat4.translation (Vec3.create (-2.7) 6.8 0.8)) in
  let path_ridge = Sop.grid ~columns:20 ~rows:12 ~size:1.3 ()
      |> Sop.ordered_group ~owner:Pdk.Group.Primitive ~name:"waypoints"
           [|0; (6 * 20 * 2) + (10 * 2); (12 * 20 * 2) - 1|]
      |> Sop.group_find_path ~owner:Pdk.Group.Primitive
           ~base_group:"waypoints" ~name:"route"
      |> Sop.peak ~selection:(Sop.Primitive_group "route") ~distance:0.18
           ~recompute_normals:true
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
      |> Sop.transform (Mat4.translation (Vec3.create 2.7 2.2 (-0.1))) in
  let unpacked_editable =
    Sop.box ~size:(Vec3.create 0.24 0.24 0.24) ()
    |> Sop.pack
         ~transforms:[|Mat4.translation (Vec3.create (-2.4) (-2.3) (-0.4))|]
    |> Sop.duplicate_packed ~copies:8
         ~transform:(Mat4.mul (Mat4.translation (Vec3.create 0.58 0. 0.))
           (Mat4.rotation_y 0.19))
    |> Sop.unpack
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#4ade80") in
  let ray_collision = Sop.grid ~columns:22 ~rows:16 ~size:1.5 ()
      |> Sop.noise_displace ~seed:601 ~amplitude:0.36 ~frequency:1.4
      |> Sop.color_by_height ~low:(Color.hex_exn "#14b8a6")
           ~high:(Color.hex_exn "#fde047") in
  let ray_drape = Sop.grid ~columns:22 ~rows:16 ~size:1.5 ()
      |> Sop.transform (Mat4.translation (Vec3.create 0. 1.2 0.))
      |> Sop.ray ~collision:ray_collision
           ~direction:(Pdk.Ops.Ray_vector (Vec3.neg Vec3.unit_y))
           ~samples:5 ~jitter_scale:0.08 ~seed:619
           ~combine:Pdk.Ops.Ray_average ~tolerance:1e-9
           ~normal_attribute:"N" ~point_pattern:"Cd"
      |> Sop.transform (Mat4.translation (Vec3.create 2.6 3.1 1.5)) in
  let grid_snapped = Sop.grid ~columns:24 ~rows:18 ~size:1.6 ()
      |> Sop.noise_displace ~seed:607 ~amplitude:0.3 ~frequency:1.8
      |> Sop.snap_to_grid ~spacing:(Vec3.create 0.1 0.1 0.1)
           ~offset:(Vec3.create 0.5 0. 0.5) ~snapped_group:"snapped"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
      |> Sop.transform (Mat4.translation (Vec3.create (-2.6) 3.1 1.5)) in
  let fuse_target_surface = Sop.grid ~columns:18 ~rows:14 ~size:1.25 ()
      |> Sop.noise_displace ~seed:608 ~amplitude:0.22 ~frequency:1.7 in
  let targeted_fuse_surface = Sop.grid ~columns:18 ~rows:14 ~size:1.25 ()
      |> Sop.noise_displace ~seed:608 ~amplitude:0.22 ~frequency:1.7
      |> Sop.transform (Mat4.translation (Vec3.create 0.018 0.025 (-0.013)))
      |> Sop.fuse ~target:fuse_target_surface
           ~using:Pdk.Ops.Closest_target_point ~tolerance:0.05
           ~fuse_points:false ~snapped_group:"targeted"
           ~snapped_destination_attribute:"target_point"
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
      |> Sop.transform (Mat4.translation (Vec3.create 1.3 4.3 1.5)) in
  let cleaned_fuse_surface = Sop.grid ~columns:18 ~rows:14 ~size:1.25 ()
      |> Sop.fuse ~tolerance:0.071 ~remove_degenerate_primitives:true
           ~remove_all_unused_points:true
      |> Sop.normals
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15")
      |> Sop.transform (Mat4.translation (Vec3.create (-1.3) 4.3 1.5)) in
  let rule_fused_surface = Sop.merge [
      Sop.grid ~columns:16 ~rows:12 ~size:1.1 ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#0ea5e9");
      Sop.grid ~columns:16 ~rows:12 ~size:1.1 ()
      |> Sop.transform (Mat4.translation (Vec3.create 0.018 0.024 (-0.013)))
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f43f5e")]
      |> Sop.fuse ~tolerance:0.05 ~attribute_rules:[
           Pdk.Ops.fuse_attribute_rule ~pattern:"Cd"
             Pdk.Ops.Attribute_average]
      |> Sop.normals
      |> Sop.transform (Mat4.translation (Vec3.create 0. 5.4 1.5)) in
  let bound_ovoid = Sop.box ~size:(Vec3.create 1.1 1.7 0.8) ()
      |> Sop.transform (Mat4.rotation ~axis:(Vec3.create 1. 2. 0.5) 0.55)
      |> Sop.bound ~shape:(Pdk.Ops.Bound_sphere {
           segments = 28; rings = 14; minimum_radius = 0. })
           ~lower_padding:(Vec3.create 0.05 0.25 0.1)
           ~upper_padding:(Vec3.create 0.35 0.05 0.2)
           ~bounds_group:"bounds"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 4.2 0.)) in
  let matched_arch = Sop.box ~size:(Vec3.create 0.7 1.5 0.55) ()
      |> Sop.group ~name:"match_source" Select.all_points
      |> Sop.match_size ~source_selection:(Sop.Point_group "match_source")
           ~fit:Pdk.Ops.Match_y ~justify:(Vec3.create 1. (-1.) 0.)
           ~target_justify:(Vec3.create (-1.) 1. 0.)
           ~offset:(Vec3.create 0.12 0.08 0.)
           ~target_center:(Vec3.create (-2.7) 4.2 0.)
           ~target_size:(Vec3.create 1.4 1.9 1.1)
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2dd4bf") in
  let oriented_grid = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~orientation:(Pdk.Ops.Grid_axes {
        horizontal = Vec3.create 1. 0.2 0.4;
        vertical = Vec3.create (-0.3) 1. 0.5 })
      ~center:(Vec3.create 2.8 3.9 (-0.4)) ~width:1.4 ~height:0.9
      ~rotation:0.31 ~uv_attribute:"uv" ~columns:12 ~rows:8 ~size:1. ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185") in
  let line_lattice = Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_rows_and_columns
      ~orientation:Pdk.Ops.Grid_xy ~center:(Vec3.create (-2.8) 4.2 0.)
      ~width:1.2 ~height:0.8 ~rotation:(-0.18)
      ~columns:7 ~rows:5 ~size:1. ()
      |> Sop.polywire ~sides:6 ~caps:true ~radius:0.012
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15") in
  let divided_box = Sop.box ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true ~normals:Pdk.Ops.Box_vertex_normals
      ~center:(Vec3.create 0. 4.8 (-1.4))
      ~rotation:(Vec3.create 0.25 0.55 0.15)
      ~rotation_order:Pdk.Ops.Box_yzx
      ~x_divisions:5 ~y_divisions:4 ~z_divisions:3
      ~uv_attribute:"uv" ~face_groups:"box_face"
      ~size:(Vec3.create 1.2 0.8 0.7) ()
      |> Sop.group ~name:"facet_subset"
           (Select.primitive_indices [|0;1;2;3;4;5;6;7|])
      |> Sop.facet ~group:"facet_subset" ~unique_points:true
           ~consolidate_normals_distance:0.
      |> Sop.set_color ~owner:Pdk.Attribute.Point Color.white in
  let advanced_sphere = Sop.uv_sphere
      ~connectivity:Pdk.Ops.Sphere_alternating_triangles
      ~unique_points_per_pole:true ~normals:Pdk.Ops.Sphere_vertex_normals
      ~orientation:(Pdk.Ops.Sphere_axis (Vec3.create 1. 2. 0.5))
      ~center:(Vec3.create 1.7 4.8 (-1.3))
      ~rotation:(Vec3.create 0.2 0.45 0.1)
      ~rotation_order:Pdk.Ops.Sphere_zxy
      ~radius_x:0.65 ~radius_y:0.45 ~radius_z:0.3
      ~uv_attribute:"uv" ~segments:36 ~rings:20 ~radius:1. ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8") in
  let capped_torus = Sop.torus
      ~connectivity:Pdk.Ops.Torus_alternating_triangles
      ~normals:Pdk.Ops.Torus_vertex_normals
      ~orientation:(Pdk.Ops.Torus_axis (Vec3.create 0.3 1. 0.2))
      ~center:(Vec3.create (-1.5) 4.8 (-1.3))
      ~rotation:(Vec3.create 0.15 0.3 0.1)
      ~rotation_order:Pdk.Ops.Torus_yzx
      ~u_start:0.25 ~u_end:5.4 ~v_start:(-.2.4) ~v_end:2.4
      ~u_wrap:false ~v_wrap:false ~u_end_caps:true ~v_end_cap:true
      ~uv_attribute:"uv" ~rows:48 ~columns:20
      ~major_radius:0.55 ~minor_radius:0.17 ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#c084fc") in
  let capped_tube = Sop.tube
      ~connectivity:Pdk.Ops.Tube_alternating_triangles ~end_caps:true
      ~consolidate_cap_points:false ~normals:Pdk.Ops.Tube_vertex_normals
      ~orientation:(Pdk.Ops.Tube_axis (Vec3.create 0.4 1. 0.25))
      ~center:(Vec3.create 3.1 4.7 (-1.2))
      ~rotation:(Vec3.create 0.2 0.35 0.1)
      ~rotation_order:Pdk.Ops.Tube_zxy ~radius_scale:1.1
      ~uv_attribute:"uv" ~cap_group:"tube_caps"
      ~rows:18 ~columns:28 ~top_radius:0. ~bottom_radius:0.48 ~height:1.3 ()
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316") in
  let soccer_ball = Sop.platonic ~kind:Pdk.Ops.Platonic_soccer_ball
      ~normals:Pdk.Ops.Platonic_vertex_normals
      ~orientation:(Pdk.Ops.Platonic_axis (Vec3.create 0.2 1. 0.35))
      ~center:(Vec3.create (-3.1) 4.7 (-1.2))
      ~rotation:(Vec3.create 0.15 0.35 0.2)
      ~rotation_order:Pdk.Ops.Platonic_xzy ~face_groups:"soccer_face"
      ~radius:0.52 () in
  let spiral_wire = Sop.spiral
      ~extent:(Pdk.Ops.Spiral_turns { turns = 2.5; height = 1.25 })
      ~radius:(Pdk.Ops.Spiral_archimedean_end {
        start_radius = 0.12; end_radius = 0.52 })
      ~radius_ramp:[0., 1.; 0.65, 1.15; 1., 0.85]
      ~uniform_angle:false
      ~orientation:(Pdk.Ops.Spiral_axis (Vec3.create 0.2 1. 0.1))
      ~center:(Vec3.create 0. 3.5 (-1.4))
      ~rotation:(Vec3.create 0.1 0.25 0.)
      ~divisions:(Pdk.Ops.Spiral_divisions_per_curve 128)
      ~distance_attribute:"wire_v" ()
      |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"wire_up" Vec3.unit_y
      |> Sop.polywire ~sides:8 ~seam_offset:2 ~v_attribute:"wire_v"
           ~up_attribute:"wire_up" ~caps:true ~radius:0.025
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#4ade80") in
  let filled_tube = Sop.tube ~connectivity:Pdk.Ops.Tube_quads
      ~end_caps:false ~normals:Pdk.Ops.Tube_point_normals
      ~rows:8 ~columns:28 ~top_radius:0.34 ~bottom_radius:0.48 ~height:0.9 ()
      |> Sop.poly_fill ~mode:Pdk.Ops.Fill_triangle_fan
           ~update_point_normals:true ~patch_group:"filled_caps"
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15")
      |> Sop.transform (Mat4.translation (Vec3.create 3.1 3.5 1.2)) in
  let beveled_box = Sop.box ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true ~normals:Pdk.Ops.Box_no_normals
      ~size:(Vec3.create 1.15 0.9 0.75) ()
      |> Sop.group_edges ~name:"bevel_edges"
      |> Sop.poly_bevel ~group:"bevel_edges"
           ~shape:(Pdk.Ops.Bevel_round { convexity = 1. }) ~divisions:4
           ~distance:0.16 ~edge_group:"bevel_faces"
           ~corner_group:"bevel_corners" ~offset_group:"bevel_rims"
      |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.85
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
      |> Sop.transform (Mat4.translation (Vec3.create 0. 5.75 0.)) in
  let split_box = Sop.box ~connectivity:Pdk.Ops.Box_quads
      ~consolidate_points:true ~normals:Pdk.Ops.Box_vertex_normals
      ~face_groups:"split_face" ~size:(Vec3.create 0.9 0.9 0.9) ()
      |> Sop.point_split ~attributes:"N split_face_*"
           ~promote_attributes:true
      |> Sop.peak ~direction_attribute:"N" ~distance:0.055
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6")
      |> Sop.transform (Mat4.translation (Vec3.create 1.5 5.75 0.)) in
  let generated_cloud =
    let prototype = Sop.box ~connectivity:Pdk.Ops.Box_quads
        ~consolidate_points:true ~size:(Vec3.create 0.08 0.08 0.08) ()
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a3e635") in
    let targets = Sop.points [|(-0.45, 0., 0.); (0., 0.3, 0.1);
        (0.45, 0., 0.)|]
        |> Sop.set_float ~owner:Pdk.Attribute.Point ~name:"density" 7.
        |> Sop.enumerate ~owner:Pdk.Attribute.Point ~name:"id"
        |> Sop.set_orient Quat.identity
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"scale"
             (Vec3.create 0.75 1.15 1.35)
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"N"
             (Vec3.create 0.35 1. 0.2)
        |> Sop.point_replicate ~label:"render-point-replicate" ~seed:823
             ~generated_group:"generated"
             ~transform_attributes:"N"
             ~shape:Pdk.Ops.Replicate_sphere ~quasi_stratified:true
             ~size:(Vec3.create 0.56 0.56 0.56)
             ~points_per_point:1. ~scale_attribute:"density" in
    Sop.copy_to_points ~source:prototype ~targets ()
    |> Sop.transform (Mat4.translation (Vec3.create 3.0 5.75 0.)) in
  let poly_path_lattice = Sop.grid ~columns:8 ~rows:6 ~size:1.2 ()
      |> Sop.poly_path
      |> Sop.polywire ~sides:6 ~caps:true ~radius:0.018
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
      |> Sop.transform (Mat4.translation (Vec3.create (-3.1) 3.5 1.2)) in
  let variable_polywire = Sop.snapshot (variable_wire_curve ())
      |> Sop.polywire ~divisions_attribute:"wire_divisions"
           ~segments_attribute:"wire_segments" ~scale_attribute:"wire_scale"
           ~segment_scales_attribute:"wire_segment_scales"
           ~uv_range_attribute:"wire_uv_ranges"
           ~prevent_joint_buckling:true
           ~maximum_joint_scale_attribute:"wire_joint_limit"
           ~smooth_attribute:"wire_smooth" ~max_valence:4
           ~segment_seam_attribute:"wire_segment_seam"
           ~caps:true ~cap_group:"variable_caps" ~radius:0.09
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f0abfc")
      |> Sop.transform (Mat4.translation (Vec3.create (-1.5) 5.75 1.2)) in
  let revolved_vase = Sop.polyline
      [|(0., -0.65, 0.); (0.42, -0.5, 0.); (0.3, 0.15, 0.);
        (0.5, 0.42, 0.); (0., 0.65, 0.)|]
      |> Sop.revolve ~connectivity:Pdk.Ops.Grid_alternating_triangles
           ~caps:true ~cap_group:"revolve_caps" ~divisions:40
           ~origin:Vec3.zero ~axis:Vec3.unit_y
      |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.8
      |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
      |> Sop.transform (Mat4.translation (Vec3.create 3.1 3.5 (-1.2))) in
  let swept_star =
    let backbone = Sop.polyline (Array.init 25 (fun point ->
        let t = float_of_int point /. 24. in
        0.35 *. sin (t *. 2. *. Float.pi), (t *. 1.3) -. 0.65,
        0.25 *. cos (t *. 2. *. Float.pi)))
    and cross_section = Sop.polyline ~closed:true (Array.init 10 (fun point ->
        let angle = 2. *. Float.pi *. float_of_int point /. 10. in
        let radius = if point land 1 = 0 then 0.34 else 0.16 in
        radius *. cos angle, radius *. sin angle, 0.)) in
    Sop.sweep ~connectivity:Pdk.Ops.Grid_alternating_triangles ~twist:2.4
      ~caps:true ~cap_group:"sweep_caps" ~backbone ~cross_section ()
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.9
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#c084fc")
    |> Sop.transform (Mat4.translation (Vec3.create (-3.1) 3.5 (-1.2))) in
  let graphs = [inline_panel; terrain; tube; extruded; mirrored; transferred; directly_copied;
    combined_attributes; interpolated_attributes;
    multi_transferred;
    surface_transferred; clipped; concave_clip; nested_clip; subdivided; pulled_subdivision;
    smooth_triangles; second_input_creased; shared_curve_subdivision;
    independent_curve_subdivision; blasted; uv_mapped;
    converted_wire; ends_wire; selected_duplicate; generated_line; open_ellipse;
    sliced_ellipse; bent_panel;
    jittered_panel; edge_divided_panel; edge_collapsed_panel; edge_flipped_panel;
    edge_cusped_panel; dissolved_panel; reduced_panel; lofted_shell; skinned_shell;
    bridged_tube; straightened_wire;
    scattered; piece_matched_copies; extracted_dots; closest_join_wire;
    picked_join_wire;
    promoted_piece; swapped_rest_patch;
    grown_patch; constrained_growth; transformed_patch; soft_transformed_patch;
    distance_deformed_patch; distance_from_patch; distance_target_patch;
    sorted_jitter_patch; attribute_blast_patch; crease_patch;
    path_ridge; ray_drape; grid_snapped;
    targeted_fuse_surface;
    cleaned_fuse_surface; rule_fused_surface;
    bound_ovoid; matched_arch;
    oriented_grid; line_lattice; divided_box; advanced_sphere; capped_torus;
    capped_tube; soccer_ball; spiral_wire; filled_tube; beveled_box; split_box;
    generated_cloud;
    poly_path_lattice; variable_polywire;
    revolved_vase; swept_star;
    unpacked_editable] in
  let packed =
    Sop.box ~size:(Vec3.create 0.28 0.28 0.28) ()
    |> Sop.pack
         ~transforms:[|Mat4.translation (Vec3.create (-1.8) 2.8 (-0.6))|]
    |> Sop.duplicate_packed ~copies:6
         ~transform:(Mat4.translation (Vec3.create 0.6 0. 0.))
  in
  let one_meshes = List.map (fun graph -> cooked_mesh graph 1) graphs
  and many_meshes = List.map (fun graph -> cooked_mesh graph 4) graphs
  and one_instances = cooked_instances packed 1
  and many_instances = cooked_instances packed 4 in
  let root = Filename.temp_file "prismel-procedural-render-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and many = Filename.concat root "many" in
  let one_file = Filename.concat one "procedural-000000.png"
  and many_file = Filename.concat many "procedural-000000.png" in
  Fun.protect
    ~finally:(fun () ->
      if keep_artifacts then Printf.printf "procedural render artifacts: %s\n%!" root
      else begin
        List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
          [one_file; many_file];
        List.iter (fun directory ->
          if Sys.file_exists directory then Unix.rmdir directory) [one; many];
        if Sys.file_exists root then Unix.rmdir root
      end)
    (fun () ->
      render one 1 one_meshes one_instances;
      render many 4 many_meshes many_instances;
      let one_png = read_file one_file and many_png = read_file many_file in
      if not (String.equal one_png many_png) then
        failwith "one-domain and four-domain procedural renders differ";
      if String.length one_png < 100 then failwith "procedural PNG is unexpectedly empty");
  print_endline "procedural render smoke passed"
