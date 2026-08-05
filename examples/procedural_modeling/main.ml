open Prismel
open Procedural

type model = {
  session : Session.t;
  meshes : Mesh.t list;
  camera : Easy_camera.t;
  frames_left : int option;
}

let cook session frame graph =
  let context = Context.of_frame ~seed:2026L frame |> Result.get_ok in
  match Bridge.cook_to_mesh session ~context graph with
  | Ok (mesh, _warnings) -> mesh
  | Error error -> failwith (Diagnostic.error_to_string error)

let graphs () =
  let tube =
    Sop.polyline [|(-3.,0.,0.); (-2.5,1.4,0.4); (-1.5,0.7,-0.5);
      (-0.8,2.2,0.)|]
    |> Sop.resample ~maximum_segment_length:0.08
         ~curve_u_attribute:"curveu" ~tangent_attribute:"curve_tangent"
    |> Sop.sweep_circle ~sides:12 ~radius:0.16
    |> Sop.polyframe ~orthogonal:true (Pdk.Ops.Attribute_gradient "uv")
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
  and swept_star =
    let backbone =
      Sop.polyline [|(-3.1, 0.15, 1.8); (-2.7, 0.9, 2.15);
        (-2.2, 1.45, 1.75); (-1.7, 2.05, 2.2)|]
      |> Sop.resample ~maximum_segment_length:0.07 in
    let cross_section =
      Array.init 10 (fun index ->
        let angle = (Float.pi /. 2.)
            +. (2. *. Float.pi *. float_of_int index /. 10.) in
        let radius = if index land 1 = 0 then 0.19 else 0.08 in
        radius *. cos angle, radius *. sin angle, 0.)
      |> Sop.polyline ~closed:true in
    Sop.sweep ~backbone ~cross_section ~tangent:Pdk.Ops.Sweep_central_difference
      ~twist:2.4 ~caps:true ~cap_group:"star_caps" ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f59e0b")
  and tiles =
    Sop.grid ~columns:4 ~rows:3 ~size:2.8 ()
    |> Sop.mountain ~seed:222 ~height:0.16
         ~frequency:(Vec3.create 1.2 0.8 1.2) ~octaves:4
    |> Sop.group_random ~seed:221 ~probability:0.1
         ~owner:Pdk.Ops.Group_points ~name:"growth_seeds"
    |> Sop.group_edge_depth ~depth:1 ~point_group:"growth_seeds"
         ~name:"growth_points"
    |> Sop.peak ~selection:(Sop.Point_group "growth_points") ~distance:0.015
         ~recompute_normals:true
    |> Sop.group_random ~seed:223 ~probability:0.42
         ~owner:Pdk.Ops.Group_primitives ~name:"raised_tiles"
    |> Sop.group_bounds ~base:"raised_tiles"
         ~containment:Pdk.Ops.Partially_contained
         (Pdk.Ops.Bounds_sphere { center = Vec3.zero; radius = 1.35 })
         ~owner:Pdk.Ops.Group_primitives ~name:"raised_tiles"
    |> Sop.group_normal ~use_existing_normal:false ~base:"raised_tiles"
         ~direction:Vec3.unit_y
         ~spread_angle:(Float.pi /. 3.) ~owner:Pdk.Ops.Group_primitives
         ~name:"raised_tiles"
    |> Sop.group_backface ~merge:Pdk.Ops.Group_subtract
         ~viewpoint:(Vec3.create 0. 4. 5.) ~name:"raised_tiles"
    |> Sop.peak ~selection:(Sop.Primitive_group "raised_tiles") ~distance:0.04
    |> Sop.poly_extrude ~group:"raised_tiles"
         ~divide:Pdk.Ops.Extrude_connected_components ~divisions:3
         ~front_group:"tile_fronts" ~side_group:"tile_sides"
         ~front_boundary_group:"tile_rims" ~distance:0.28
    |> Sop.facet ~unique_points:true ~post_compute_normals:true
    |> Sop.measure ~total_name:"tile_surface_area" Pdk.Analysis.Area
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
    |> Sop.transform (Mat4.translation (Vec3.create 1.5 0. 0.))
  and copies =
    let prototype = Sop.box ~connectivity:Pdk.Ops.Box_quads
        ~consolidate_points:true ~size:(Vec3.create 0.28 0.62 0.2) ()
        |> Sop.facet ~cusp_angle:0.6 ~post_compute_normals:true
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15") in
    let targets = Array.init 18 (fun index ->
      let angle = float_of_int index *. 0.72 in
      (2.4 *. cos angle, 0.35 +. (float_of_int index *. 0.12),
       2.4 *. sin angle)) in
    Sop.copy_to_points ~source:prototype
      ~targets:(Sop.points targets
        |> Sop.attribute_randomize ~seed:301 ~owner:Pdk.Attribute.Point
             ~name:"pscale" (Pdk.Attribute_ops.Random_custom_discrete [
               Pdk.Attribute_ops.Scalar 0.45, 1.;
               Pdk.Attribute_ops.Scalar 0.65, 3.;
               Pdk.Attribute_ops.Scalar 0.9, 1.;
             ])
        |> Sop.attribute_randomize ~seed:302 ~owner:Pdk.Attribute.Point
             ~direction_bias:0.8 ~name:"orient"
             (Pdk.Attribute_ops.Random_direction {
               direction = Pdk.Attribute_ops.Vec4 (0., 0., 0., 1.);
               cone_angle = Float.pi *. 0.8;
             })) ()
    |> Sop.connectivity ~name:"copy_piece"
         ~attribute:(Pdk.Analysis.Connectivity_text "copy_")
    |> Sop.groups_from_name ~owner:Pdk.Attribute.Primitive
         ~attribute:"copy_piece"
  and wire =
    Sop.grid ~columns:4 ~rows:3 ~size:2.4 ()
    |> Sop.enumerate ~owner:Pdk.Attribute.Primitive ~name:"face_id"
    |> Sop.group ~name:"wire_faces" Select.all_primitives
    |> Sop.group_promote_boundary ~source:Pdk.Ops.Group_primitives
         ~destination:Pdk.Ops.Group_edges ~group:"wire_faces"
         ~name:"wire_edges" ~include_unshared_edges:true ~attributes:[{
           Pdk.Ops.boundary_attribute_owner = Pdk.Attribute.Primitive;
           boundary_attribute_pattern = "face_id" }]
    |> Sop.convert_line ~group:"wire_edges" ~connect_path:true
         ~maximum_distance:0. ~make_isolated_loops_closed:true
    |> Sop.polywire ~sides:8 ~caps:true ~radius:0.035
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#34d399")
    |> Sop.transform (Mat4.translation (Vec3.create 0. 2.8 (-1.2)))
  and ends_wire =
    Sop.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~size:(Vec3.create 0.9 0.75 0.8) ()
    |> Sop.ends Pdk.Ops.Ends_unroll_shared
    |> Sop.polywire ~sides:6 ~caps:true ~radius:0.02
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15")
    |> Sop.transform (Mat4.translation (Vec3.create 1.45 2.8 (-1.2)))
  and line =
    Sop.line ~points:24 ~origin:(Vec3.create (-2.7) 0. (-2.2))
      ~direction:(Vec3.create 0.3 1. 0.15) ~length:2.4 ()
    |> Sop.set_float ~owner:Pdk.Attribute.Primitive ~name:"first_u" 0.04
    |> Sop.set_float ~owner:Pdk.Attribute.Primitive ~name:"second_u" 0.96
    |> Sop.group ~name:"carve_line" Select.all_primitives
    |> Sop.carve ~group:"carve_line" ~first_attribute:"first_u"
         ~last_attribute:"second_u" ~only_at_breakpoints:true
         ~keep:Pdk.Ops.Keep_inside_and_outside
    |> Sop.set_float ~owner:Pdk.Attribute.Point ~name:"width" 0.65
    |> Sop.polywire ~sides:10 ~scale_attribute:"width" ~caps:true ~radius:0.1
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6")
  and joined_path =
    Sop.merge [
      Sop.polyline [|(-1.1,0.,0.); (-0.55,0.45,0.15)|];
      Sop.polyline [|(0.5,0.3,-0.1); (1.1,0.05,0.)|];
      Sop.polyline [|(0.,0.9,0.2); (-0.55,0.45,0.15)|];
      Sop.polyline [|(0.5,0.3,-0.1); (0.,0.9,0.2)|]]
    |> Sop.join_curves ~connect_closest_ends:true ~group_size:2
    |> Sop.polywire ~sides:8 ~caps:true ~radius:0.035
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fbbf24")
    |> Sop.transform (Mat4.translation (Vec3.create 0. 1.1 (-2.4)))
  and skinned_shell =
    let ring y radius phase = Sop.polyline ~closed:true
        (Array.init 24 (fun point ->
          let angle = phase +. (2. *. Float.pi *. float_of_int point /. 24.) in
          radius *. cos angle, y, radius *. sin angle)) in
    Sop.merge [ring (-0.7) 0.28 0.; ring (-0.25) 0.62 0.08;
      ring 0.2 0.4 (-0.05); ring 0.72 0.55 0.12]
    |> Sop.skin ~output_group:"skin_faces"
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.9
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6")
    |> Sop.transform (Mat4.translation (Vec3.create 2.7 1.0 (-2.4)))
  and bridged_shell =
    let ring group other y radius phase =
      Sop.circle ~center:(Vec3.create 0. y 0.) ~segments:20 ~radius ()
      |> Sop.transform (Mat4.rotation_y phase)
      |> Sop.group ~name:group Select.all_primitives
      |> Sop.group ~name:other (Select.primitive_indices [||]) in
    Sop.merge [ring "bridge_source_faces" "bridge_destination_faces"
        (-0.62) 0.34 0.;
      ring "bridge_destination_faces" "bridge_source_faces"
        0.62 0.55 0.16]
    |> Sop.group_edges ~name:"bridge_source" ~group:"bridge_source_faces"
    |> Sop.group_edges ~name:"bridge_destination"
         ~group:"bridge_destination_faces"
    |> Sop.poly_bridge ~source_group:"bridge_source"
         ~destination_group:"bridge_destination" ~pairing_shift:1
         ~divisions:6 ~keep_input:false ~output_group:"bridge_faces"
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.9
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
    |> Sop.transform (Mat4.translation (Vec3.create 3.7 1.1 (-0.7)))
  and bent_panel =
    Sop.grid ~columns:36 ~rows:24 ~size:2.2 ()
    |> Sop.bend ~origin:(Vec3.create 0. 0. (-1.1))
         ~direction:Vec3.unit_z ~up:Vec3.unit_y ~length:2.2
         ~bend_angle:1.25 ~twist_angle:0.7 ~recompute_normals:true
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#60a5fa")
    |> Sop.transform (Mat4.translation (Vec3.create 0. 3.2 (-2.1)))
  and reduced_terrain =
    Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~columns:48 ~rows:36 ~size:1.8 ()
    |> Sop.mountain ~seed:744 ~height:0.34
         ~frequency:(Vec3.create 2.2 1.1 1.8) ~octaves:5
         ~recompute_normals:true
    |> Sop.poly_reduce ~target:(Pdk.Ops.Reduce_ratio 0.24)
         ~preserve_boundary:true ~equalize_lengths:1e-7
         ~max_normal_deviation:0.7 ~output_group:"reduced_faces"
    |> Sop.normals
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316")
    |> Sop.transform (Mat4.translation (Vec3.create (-3.6) 1.0 0.8))
  and scattered =
    let prototype = Sop.box ~size:(Vec3.create 0.055 0.055 0.055) ()
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#c084fc") in
    let targets = Sop.grid ~columns:30 ~rows:24 ~size:1.8 ()
        |> Sop.attribute_randomize ~seed:512 ~owner:Pdk.Attribute.Point
             ~name:"density" (Pdk.Attribute_ops.Random_uniform {
               min = Pdk.Attribute_ops.Scalar 0.;
               max = Pdk.Attribute_ops.Scalar 1.;
             })
        |> Sop.group_random ~seed:513 ~probability:0.78
             ~owner:Pdk.Ops.Group_primitives ~name:"scatter_surface"
        |> Sop.scatter ~seed:514 ~group:"scatter_surface" ~count:320
             ~density:(Pdk.Ops.scatter_density ~owner:Pdk.Attribute.Point
               "density")
             ~source_primitive_attribute:"source_primitive"
        |> Sop.transform (Mat4.translation (Vec3.create 0. 3.1 2.2)) in
    Sop.copy_to_points ~source:prototype ~targets ()
  and promoted_piece =
    Sop.grid ~columns:16 ~rows:12 ~size:1.8 ()
    |> Sop.noise_displace ~seed:51 ~amplitude:0.35 ~frequency:1.2
    |> Sop.smooth ~iterations:2 ~boundary:Pdk.Ops.Smooth_unshared
         ~attributes:"P" ~method_:Pdk.Attribute_ops.Edge_length
         ~mode:(Pdk.Attribute_ops.Laplacian 0.3)
    |> Sop.color_by_height ~low:(Color.hex_exn "#2563eb")
         ~high:(Color.hex_exn "#f97316")
    |> Sop.attribute_randomize ~seed:404 ~operation:Pdk.Attribute_ops.Random_add
         ~scale:0.06 ~owner:Pdk.Attribute.Point ~name:"Cd"
         (Pdk.Attribute_ops.Random_uniform {
           min = Pdk.Attribute_ops.Vec4 (-1., -1., -1., 0.);
           max = Pdk.Attribute_ops.Vec4 (1., 1., 1., 0.);
         })
    |> Sop.attribute_remap ~owner:Pdk.Attribute.Point ~name:"Cd"
         ~input:(Pdk.Attribute_ops.Remap_explicit {
           min = Pdk.Attribute_ops.Vec4 (-0.06, -0.06, -0.06, 0.);
           max = Pdk.Attribute_ops.Vec4 (1.06, 1.06, 1.06, 1.);
         }) ~output_min:(Pdk.Attribute_ops.Vec4 (0., 0., 0., 0.))
         ~output_max:(Pdk.Attribute_ops.Vec4 (1., 1., 1., 1.))
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
         ~pattern:"source_*" ~into_pattern:"*"
    |> Sop.promote_attribute ~method_:Pdk.Attribute_ops.Maximum
         ~piece_attribute:"piece" ~delete_source:false
         ~index_attribute:"weight_source" ~source:Pdk.Attribute.Point
         ~destination:Pdk.Attribute.Vertex ~name:"input_weight" ~into:"weight"
    |> Sop.delete_attributes ~point_pattern:"source_Cd input_weight"
    |> Sop.transform (Mat4.translation (Vec3.create 2.8 2.2 (-1.5)))
  and transferred_corners =
    let source = Sop.grid ~columns:18 ~rows:14 ~size:1.8 ()
        |> Sop.noise_displace ~seed:93 ~amplitude:0.3 ~frequency:1.3
        |> Sop.color_by_height ~low:(Color.hex_exn "#06b6d4")
             ~high:(Color.hex_exn "#f97316")
        |> Sop.promote_attribute ~delete_source:false
             ~source:Pdk.Attribute.Point ~destination:Pdk.Attribute.Vertex
             ~name:"Cd"
        |> Sop.group ~name:"transfer_surface" Select.all_primitives in
    let target = Sop.grid ~columns:20 ~rows:16 ~size:1.7 ()
        |> Sop.transform (Mat4.translation (Vec3.create 0. 0.18 0.))
        |> Sop.group ~name:"transfer_corners" Select.all_vertices in
    Sop.attribute_transfer ~owner:Pdk.Attribute.Vertex ~pattern:"C*"
      ~max_distance:0.6 ~source_group:"transfer_surface"
      ~target_group:"transfer_corners" ~source ~target ()
    |> Sop.transform (Mat4.translation (Vec3.create (-2.6) 2.2 1.5))
  and grown_patch =
    let source = Sop.grid ~columns:14 ~rows:10 ~size:1.7 ()
        |> Sop.group_range ~owner:Pdk.Ops.Group_points ~name:"bands"
             ~connectivity:(Pdk.Ops.Range_disconnected { region = None })
             ~filter:{ select = 2; of_ = 9; offset = 1 }
             (Pdk.Ops.Range_from_ends { start = 4; end_offset = 4 }) in
    let target = Sop.grid ~columns:14 ~rows:10 ~size:1.7 ()
        |> Sop.group ~name:"seed"
             (Select.points_in_bounds ~min:(Vec3.create (-0.12) (-1.) (-0.12))
                ~max:(Vec3.create 0.12 1. 0.12)) in
    let copied = Sop.group_copy ~source ~target ~rules:[
      { Pdk.Ops.copy_owner = Pdk.Ops.Group_points; copy_pattern = "bands";
        copy_prefix = "copied_"; match_attribute = None }] () in
    Sop.group_transfer ~distance:0.001
      ~rules:[{ Pdk.Ops.transfer_owner = Pdk.Ops.Group_points;
        transfer_pattern = "bands"; transfer_prefix = "near_" }]
      ~source ~target:copied ()
    |> Sop.group_combine ~owner:Pdk.Ops.Group_points ~name:"selection"
         ~base:{ Pdk.Ops.pattern = "seed"; inverted = false }
         ~steps:[{ Pdk.Ops.operation = Pdk.Ops.Group_union;
           operand = { pattern = "near_bands"; inverted = false } }]
    |> Sop.group_expand ~steps:2 ~owner:Pdk.Ops.Group_points ~group:"selection"
    |> Sop.group_combine ~owner:Pdk.Ops.Group_points ~name:"outside"
         ~base:{ Pdk.Ops.pattern = "selection"; inverted = false } ~steps:[]
    |> Sop.group_invert ~owner:Pdk.Ops.Group_points ~pattern:"outside"
    |> Sop.group_rename ~rules:[
         { Pdk.Ops.rename_owner = Some Pdk.Ops.Group_points;
           rename_pattern = "outside"; rename_replacement = "discard";
           rename_conflict = Pdk.Ops.Rename_error }]
    |> Sop.group_delete ~rules:[
         { Pdk.Ops.delete_owner = Some Pdk.Ops.Group_points;
           delete_pattern = "discard copied_* near_* seed" }]
    |> Sop.group_promote ~keep_original:true ~name:"grown_faces"
         ~mode:Pdk.Ops.Include_shared_edge ~source:Pdk.Ops.Group_points
         ~destination:Pdk.Ops.Group_primitives ~group:"selection"
    |> Sop.peak ~selection:(Sop.Primitive_group "grown_faces") ~distance:0.32
         ~recompute_normals:true
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
    |> Sop.transform (Mat4.translation (Vec3.create (-0.4) 3. 1.3))
  and path_ridge =
    Sop.grid ~columns:32 ~rows:20 ~size:2.2 ()
    |> Sop.ordered_group ~owner:Pdk.Group.Primitive ~name:"waypoints"
         [|0; (10 * 32 * 2) + (16 * 2); (20 * 32 * 2) - 1|]
    |> Sop.group_find_path ~owner:Pdk.Group.Primitive
         ~base_group:"waypoints" ~name:"route"
    |> Sop.peak ~selection:(Sop.Primitive_group "route") ~distance:0.22
         ~recompute_normals:true
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
    |> Sop.transform (Mat4.translation (Vec3.create 2.8 3.4 1.3))
  and warped_panel =
    Sop.grid ~columns:5 ~rows:4 ~size:1.5 ()
    |> Sop.subdivide ~scheme:Pdk.Ops.Bilinear
    |> Sop.mountain ~seed:731 ~height:0.08
         ~frequency:(Vec3.create 1.6 0.9 1.3) ~octaves:3
    |> Sop.group_non_planar ~tolerance:0.0005 ~name:"warped_faces"
    |> Sop.peak ~selection:(Sop.Primitive_group "warped_faces")
         ~distance:0.035 ~recompute_normals:true
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f59e0b")
    |> Sop.transform (Mat4.translation (Vec3.create (-2.7) 3.2 (-1.5)))
  and ray_drape =
    let collision =
      Sop.grid ~columns:36 ~rows:28 ~size:2.2 ()
      |> Sop.mountain ~seed:812 ~height:0.34
           ~frequency:(Vec3.create 1.4 0.8 1.2) ~octaves:4
      |> Sop.color_by_height ~low:(Color.hex_exn "#0ea5e9")
           ~high:(Color.hex_exn "#fde047") in
    Sop.grid ~columns:28 ~rows:20 ~size:2.05 ()
    |> Sop.transform (Mat4.translation (Vec3.create 0. 0.8 0.))
    |> Sop.ray ~collision
         ~direction:(Pdk.Ops.Ray_vector (Vec3.create 0. (-1.) 0.))
         ~point_pattern:"Cd" ~normal_attribute:"N" ~hit_group:"ray_hits"
    |> Sop.transform (Mat4.translation (Vec3.create 2.8 0.2 1.8))
  and grid_snapped =
    Sop.grid ~columns:28 ~rows:20 ~size:2.05 ()
    |> Sop.mountain ~seed:819 ~height:0.28
         ~frequency:(Vec3.create 1.7 0.8 1.5) ~octaves:4
    |> Sop.snap_to_grid ~spacing:(Vec3.create 0.09 0.09 0.09)
         ~offset:(Vec3.create 0.5 0. 0.5) ~snapped_group:"snapped"
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f472b6")
    |> Sop.transform (Mat4.translation (Vec3.create (-2.8) 0.2 1.8))
  and bound_ovoid =
    Sop.box ~size:(Vec3.create 1.1 1.7 0.8) ()
    |> Sop.transform (Mat4.rotation ~axis:(Vec3.create 1. 2. 0.5) 0.55)
    |> Sop.bound ~shape:(Pdk.Ops.Bound_sphere {
         segments = 28; rings = 14; minimum_radius = 0. })
         ~lower_padding:(Vec3.create 0.05 0.25 0.1)
         ~upper_padding:(Vec3.create 0.35 0.05 0.2)
         ~bounds_group:"bounds" ~center_attribute:"bound_center"
         ~radii_attribute:"bound_radii"
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a78bfa")
    |> Sop.transform (Mat4.translation (Vec3.create 0. 4.4 0.))
  and matched_arch =
    Sop.box ~size:(Vec3.create 0.7 1.5 0.55) ()
    |> Sop.group ~name:"match_source" Select.all_points
    |> Sop.match_size ~source_selection:(Sop.Point_group "match_source")
         ~fit:Pdk.Ops.Match_y ~justify:(Vec3.create 1. (-1.) 0.)
         ~target_justify:(Vec3.create (-1.) 1. 0.)
         ~offset:(Vec3.create 0.12 0.08 0.)
         ~target_center:(Vec3.create (-2.8) 4.4 0.)
         ~target_size:(Vec3.create 1.4 1.9 1.1)
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2dd4bf")
  and oriented_grid =
    Sop.grid ~counts:Pdk.Ops.Grid_point_counts
      ~connectivity:Pdk.Ops.Grid_alternating_triangles
      ~orientation:(Pdk.Ops.Grid_axes {
        horizontal = Vec3.create 1. 0.2 0.4;
        vertical = Vec3.create (-0.3) 1. 0.5 })
      ~center:(Vec3.create 2.8 4.4 0.) ~width:1.4 ~height:0.9
      ~rotation:0.31 ~uv_attribute:"uv" ~columns:12 ~rows:8 ~size:1. ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
  and open_ellipse =
    Sop.circle ~arc:(Pdk.Ops.Circle_open_arc {
        start_angle = -0.6; end_angle = 4.7 })
      ~orientation:Pdk.Ops.Circle_xy ~reverse:true
      ~center:(Vec3.create (-2.8) 3.5 (-0.4))
      ~radius_x:0.75 ~radius_y:0.35 ~rotation:0.3
      ~segments:64 ~radius:1. ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
  and sliced_ellipse =
    Sop.circle ~arc:(Pdk.Ops.Circle_sliced_arc {
        start_angle = 0.2; end_angle = 4.9 })
      ~orientation:(Pdk.Ops.Circle_axes {
        horizontal = Vec3.create 1. 0.1 0.25;
        vertical = Vec3.create (-0.2) 1. 0.4 })
      ~center:(Vec3.create 2.8 3.5 0.4)
      ~radius_x:0.7 ~radius_y:0.4 ~rotation:(-0.2)
      ~segments:64 ~radius:1. ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a3e635")
  and divided_box =
    Sop.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_vertex_normals
      ~center:(Vec3.create 0. 4.8 (-1.4))
      ~rotation:(Vec3.create 0.25 0.55 0.15)
      ~rotation_order:Pdk.Ops.Box_yzx
      ~x_divisions:5 ~y_divisions:4 ~z_divisions:3
      ~uv_attribute:"uv" ~face_groups:"box_face"
      ~size:(Vec3.create 1.2 0.8 0.7) ()
    |> Sop.facet ~unique_points:true ~consolidate_normals_distance:0.
    |> Sop.set_color ~owner:Pdk.Attribute.Point Color.white
  and advanced_sphere =
    Sop.uv_sphere ~connectivity:Pdk.Ops.Sphere_quads
      ~unique_points_per_pole:true ~triangular_poles:true
      ~normals:Pdk.Ops.Sphere_vertex_normals
      ~orientation:(Pdk.Ops.Sphere_axis (Vec3.create 1. 2. 0.5))
      ~center:(Vec3.create 1.7 4.8 (-1.3))
      ~rotation:(Vec3.create 0.2 0.45 0.1)
      ~rotation_order:Pdk.Ops.Sphere_zxy
      ~radius_x:0.65 ~radius_y:0.45 ~radius_z:0.3
      ~uv_attribute:"uv" ~segments:36 ~rings:20 ~radius:1. ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
  and capped_torus =
    Sop.torus ~connectivity:Pdk.Ops.Torus_alternating_triangles
      ~normals:Pdk.Ops.Torus_vertex_normals
      ~orientation:(Pdk.Ops.Torus_axis (Vec3.create 0.3 1. 0.2))
      ~center:(Vec3.create (-1.6) 4.8 (-1.3))
      ~rotation:(Vec3.create 0.15 0.3 0.1)
      ~rotation_order:Pdk.Ops.Torus_yzx
      ~u_start:0.25 ~u_end:5.4 ~v_start:(-2.4) ~v_end:2.4
      ~u_wrap:false ~v_wrap:false ~u_end_caps:true ~v_end_cap:true
      ~uv_attribute:"uv" ~rows:48 ~columns:20
      ~major_radius:0.55 ~minor_radius:0.17 ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#c084fc")
  and capped_tube =
    Sop.tube ~connectivity:Pdk.Ops.Tube_alternating_triangles
      ~end_caps:true ~consolidate_cap_points:false
      ~normals:Pdk.Ops.Tube_vertex_normals
      ~orientation:(Pdk.Ops.Tube_axis (Vec3.create 0.4 1. 0.25))
      ~center:(Vec3.create 3.1 4.7 (-1.2))
      ~rotation:(Vec3.create 0.2 0.35 0.1)
      ~rotation_order:Pdk.Ops.Tube_zxy ~radius_scale:1.1
      ~uv_attribute:"uv" ~cap_group:"tube_caps"
      ~rows:18 ~columns:28 ~top_radius:0. ~bottom_radius:0.48 ~height:1.3 ()
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316")
  and soccer_ball =
    Sop.platonic ~kind:Pdk.Ops.Platonic_soccer_ball
      ~normals:Pdk.Ops.Platonic_vertex_normals
      ~orientation:(Pdk.Ops.Platonic_axis (Vec3.create 0.2 1. 0.35))
      ~center:(Vec3.create (-3.1) 4.7 (-1.2))
      ~rotation:(Vec3.create 0.15 0.35 0.2)
      ~rotation_order:Pdk.Ops.Platonic_xzy ~face_groups:"soccer_face"
      ~radius:0.52 ()
  and spiral_wire =
    Sop.spiral ~extent:(Pdk.Ops.Spiral_turns { turns = 2.5; height = 1.25 })
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
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#4ade80")
  and filled_tube =
    Sop.tube ~connectivity:Pdk.Ops.Tube_quads ~end_caps:false
      ~normals:Pdk.Ops.Tube_point_normals ~rows:8 ~columns:28
      ~top_radius:0.34 ~bottom_radius:0.48 ~height:0.9 ()
    |> Sop.poly_fill ~mode:Pdk.Ops.Fill_triangle_fan
         ~update_point_normals:true ~patch_group:"filled_caps"
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#facc15")
    |> Sop.transform (Mat4.translation (Vec3.create 3.1 3.5 1.2))
  and beveled_box =
    Sop.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_no_normals ~size:(Vec3.create 1.1 0.8 0.7) ()
    |> Sop.group_edges ~name:"bevel_edges"
    |> Sop.poly_bevel ~group:"bevel_edges"
         ~shape:(Pdk.Ops.Bevel_round { convexity = 1. }) ~divisions:4
         ~distance:0.14 ~edge_group:"bevel_faces"
         ~corner_group:"bevel_corners" ~offset_group:"bevel_rims"
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:0.85
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
    |> Sop.transform (Mat4.translation (Vec3.create (-3.1) 3.5 1.2))
  and creased_box =
    Sop.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_no_normals ~face_groups:"crease_face"
      ~size:(Vec3.create 1.05 0.8 0.8) ()
    |> Sop.group_edges ~group:"crease_face__top" ~name:"feature_edges"
    |> Sop.crease ~group:"feature_edges" ~operation:Pdk.Ops.Crease_set
         ~weight:2.5 ~add_vertex_color:true
    |> Sop.subdivide ~iterations:2 ~scheme:Pdk.Ops.Catmull_clark
    |> Sop.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:Float.pi
    |> Sop.transform (Mat4.translation (Vec3.create 0. 3.5 1.2))
  and fading_panel =
    Sop.grid ~columns:24 ~rows:24 ~size:1.4 ()
    |> Sop.enumerate ~owner:Pdk.Attribute.Point ~name:"fade_start"
    |> Sop.attribute_fade ~start_attribute:"fade_start"
         ~start_retime:(0., -0.02) ~fade_in:4. ~fade_hold:2. ~fade_out:4.
         ~fade_in_ramp:[0.,0.;0.35,0.12;0.72,0.9;1.,1.]
         ~fade_out_ramp:[0.,1.;0.28,0.92;0.7,0.12;1.,0.]
         ~visualize:true
    |> Sop.peak ~mask_attribute:"fade" ~distance:0.36
         ~recompute_normals:true
    |> Sop.transform (Mat4.translation (Vec3.create 2.9 6.1 (-1.2)))
  and cut_signal_curve =
    Sop.line ~points:160 ~origin:(Vec3.create (-1.1) 0. 0.)
      ~direction:Vec3.unit_x ~length:2.2 ()
    |> Sop.point_jitter ~seed:916 ~axis_scales:(Vec3.create 0. 0.22 0.12)
    |> Sop.attribute_randomize ~seed:917 ~owner:Pdk.Attribute.Point
         ~name:"cut_signal" (Pdk.Attribute_ops.Random_uniform {
           min = Pdk.Attribute_ops.Scalar (-1.);
           max = Pdk.Attribute_ops.Scalar 1.;
         })
    |> Sop.poly_cut ~element:Pdk.Ops.Poly_cut_points
         ~strategy:Pdk.Ops.Poly_cut_remove
         ~detection:(Pdk.Ops.Poly_cut_crossing {
           attribute = "cut_signal"; value = 0. }) ~keep_closed:false
    |> Sop.polywire ~sides:8 ~caps:true ~radius:0.035
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#38bdf8")
    |> Sop.transform (Mat4.translation (Vec3.create (-2.8) 6.0 (-1.2)))
  and separated_pieces =
    let piece id color x =
      Sop.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
        ~normals:Pdk.Ops.Box_vertex_normals
        ~size:(Vec3.create 0.48 0.48 0.48) ()
      |> Sop.transform (Mat4.translation (Vec3.create x 0. 0.))
      |> Sop.set_int ~owner:Pdk.Attribute.Primitive ~name:"piece" id
      |> Sop.set_color ~owner:Pdk.Attribute.Point color in
    Sop.merge [
      piece 10 (Color.hex_exn "#38bdf8") (-0.06);
      piece 20 (Color.hex_exn "#f97316") 0.;
      piece 30 (Color.hex_exn "#a3e635") 0.06;
    ]
    |> Sop.separate_pieces ~piece_attribute:"piece" ~gap:0.12
    |> Sop.transform (Mat4.translation (Vec3.create 0. 6.0 (-1.2)))
  and equalized_wire =
    Sop.polyline [|(-1.05,-0.25,0.);(-0.8,0.45,0.);(0.05,-0.2,0.);
      (0.35,0.5,0.);(1.1,-0.1,0.)|]
    |> Sop.group_edges ~name:"uneven_edges"
    |> Sop.edge_equalize ~group:"uneven_edges"
         ~method_:Pdk.Ops.Equalize_average ~iterations:128
         ~tolerance:1e-7 ~output_group:"equalized_edges"
    |> Sop.polywire ~sides:8 ~caps:true ~radius:0.035
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fde047")
    |> Sop.transform (Mat4.translation (Vec3.create 2.8 3.5 1.2))
  and relaxed_wire =
    let source = Sop.polyline
        [|(-1.05,-0.35,0.);(-0.8,0.45,0.);(0.1,-0.25,0.);
          (0.4,0.5,0.);(1.1,-0.15,0.)|]
    and reference = Sop.polyline
        [|(-1.05,-0.35,0.);(-0.35,0.05,0.);(0.15,-0.05,0.);
          (0.65,0.2,0.);(1.1,-0.15,0.)|] in
    source
    |> Sop.edge_relax ~reference ~iterations:128 ~step_size:0.5
         ~target_mode:Pdk.Ops.Individual_lengths ~tolerance:1e-7
    |> Sop.polywire ~sides:8 ~caps:true ~radius:0.035
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a3e635")
    |> Sop.transform (Mat4.translation (Vec3.create (-2.8) 3.5 1.2))
  and transported_panel =
    Sop.grid ~columns:18 ~rows:12 ~size:1.4 ()
    |> Sop.edge_transport ~operation:Pdk.Ops.Transport_total
         ~integrate_constant:true ~scale_by_edge_length:true
         ~normalization:Pdk.Ops.Transport_normalize_global
         ~attribute:"distance"
    |> Sop.peak ~mask_attribute:"distance" ~distance:0.32
         ~recompute_normals:true
    |> Sop.normals ~owner:Pdk.Attribute.Vertex
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee")
    |> Sop.transform (Mat4.translation (Vec3.create 2.8 6.0 (-1.2)))
  and morphed_panel =
    let source = Sop.grid ~columns:18 ~rows:12 ~size:1.25 () in
    let target = Sop.grid ~columns:18 ~rows:12 ~size:1.25 ()
        |> Sop.bend ~length:1.25 ~bend_angle:1.1 in
    source
    |> Sop.blend_shapes ~attributes:"^*"
         ~shapes:[Sop.blend_shape ~weight:0.58 target]
    |> Sop.normals ~owner:Pdk.Attribute.Vertex
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#c084fc")
    |> Sop.transform (Mat4.translation (Vec3.create 0. 3.5 1.2))
  and composited_panel =
    let source = Sop.grid ~columns:18 ~rows:12 ~size:1.25 ()
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#f97316") in
    let target = Sop.grid ~columns:18 ~rows:12 ~size:1.25 ()
        |> Sop.bend ~length:1.25 ~bend_angle:1.1
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#22d3ee") in
    source
    |> Sop.attribute_composite ~operation:Pdk.Ops.Composite_mean ~weight:0.42
         ~point_attributes:"P Cd" ~allow_position:true
         ~vertex_attributes:"^*" ~primitive_attributes:"^*"
         ~detail_attributes:"^*"
         ~inputs:[Sop.attribute_composite_input ~weight:0.58 target]
    |> Sop.normals ~owner:Pdk.Attribute.Vertex
    |> Sop.transform (Mat4.translation (Vec3.create 1.4 6.0 (-1.2)))
  and mirrored_panel =
    let geometry = Pdk.Ops.grid ~connectivity:Pdk.Ops.Grid_quads
        ~columns:18 ~rows:12 ~size:1.25 () |> Result.get_ok in
    let positions = Pdk.Packed.Float3.Private.view
        (Pdk.Geometry.positions geometry) in
    let count = Pdk.Geometry.point_count geometry in
    let color = Pdk.Packed.Float4.of_owned
        ~x:(Array.init count (fun point ->
          if positions.x.(point) < 0. then 0.96 else 0.04))
        ~y:(Array.init count (fun point ->
          if positions.x.(point) < 0. then
            0.2 +. (0.5 *. (0.5 +. 0.5 *. sin (positions.z.(point) *. 14.)))
          else 0.05))
        ~z:(Array.init count (fun point ->
          if positions.x.(point) < 0. then 0.08 else 0.1))
        ~w:(Array.make count 1.) |> Result.get_ok in
    let color = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point ~name:"Cd"
        (Pdk.Attribute.Float4 color) |> Result.get_ok in
    Pdk.Geometry.with_attribute color geometry |> Result.get_ok
    |> Sop.snapshot
    |> Sop.attribute_mirror ~owner:Pdk.Ops.Mirror_point_attributes
         ~method_:(Sop.Attribute_mirror_plane {
           origin = Vec3.zero; normal = Vec3.unit_x;
           distance = 0.; tolerance = 1e-10 })
         ~attributes:"Cd" ~output_mapping:"mirror_pair"
         ~source_group:"mirror_source" ~destination_group:"mirror_destination"
    |> Sop.normals ~owner:Pdk.Attribute.Vertex
    |> Sop.transform (Mat4.translation (Vec3.create (-1.4) 6.0 (-1.2)))
  and rewired_panel =
    let columns = 18 and rows = 12 in
    let geometry = Pdk.Ops.grid
        ~connectivity:Pdk.Ops.Grid_alternating_triangles
        ~columns ~rows ~size:1.25 () |> Result.get_ok in
    let point_count = Pdk.Geometry.point_count geometry
    and width = columns + 1 in
    let selected point =
      let column = point mod width in
      column mod 5 = 1 && column + 2 <= columns in
    let target = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
        ~name:"targetpt" (Pdk.Attribute.Int (Array.init point_count (fun point ->
          if selected point then point + 2 else -1))) |> Result.get_ok
    and selected_group = Pdk.Group.init ~owner:Pdk.Group.Point
        ~name:"rewire_points" point_count selected in
    geometry |> Pdk.Geometry.with_attribute target |> Result.get_ok
    |> Pdk.Geometry.with_group selected_group |> Result.get_ok
    |> Sop.snapshot
    |> Sop.rewire_vertices ~selection:(Sop.Point_group "rewire_points")
         ~delete_target_attribute:true ~original_point_attribute:"origpt"
         ~owner:Pdk.Attribute.Point ~target_attribute:"targetpt"
    |> Sop.normals ~owner:Pdk.Attribute.Vertex
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#2dd4bf")
    |> Sop.transform (Mat4.translation (Vec3.create (-4.2) 6.0 (-1.2)))
  and split_box =
    Sop.box ~connectivity:Pdk.Ops.Box_quads ~consolidate_points:true
      ~normals:Pdk.Ops.Box_vertex_normals
      ~face_groups:"split_face"
      ~size:(Vec3.create 0.9 0.7 0.8) ()
    |> Sop.point_split ~attributes:"N split_face_*" ~promote_attributes:true
    |> Sop.peak ~distance:0.08
    |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#fb7185")
    |> Sop.transform (Mat4.translation (Vec3.create (-1.55) 3.5 1.2))
  and emitted_copies =
    let prototype = Sop.box ~connectivity:Pdk.Ops.Box_quads
        ~consolidate_points:true ~size:(Vec3.create 0.09 0.09 0.09) ()
        |> Sop.set_color ~owner:Pdk.Attribute.Point (Color.hex_exn "#a3e635") in
    let targets = Sop.points [|(-0.55, 0., 0.); (0., 0.2, 0.15);
        (0.55, 0., 0.); (0.2, 0.55, -0.2)|]
        |> Sop.set_float ~owner:Pdk.Attribute.Point ~name:"density" 8.
        |> Sop.enumerate ~owner:Pdk.Attribute.Point ~name:"id"
        |> Sop.set_orient Quat.identity
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"scale"
             (Vec3.create 0.8 1.1 1.3)
        |> Sop.set_vector ~owner:Pdk.Attribute.Point ~name:"N"
             (Vec3.create 0.35 1. 0.2)
        |> Sop.point_replicate ~label:"creative-replication" ~seed:814
             ~generated_group:"emitted"
             ~transform_attributes:"N"
             ~shape:Pdk.Ops.Replicate_sphere ~quasi_stratified:true
             ~size:(Vec3.create 0.64 0.45 0.64)
             ~points_per_point:1. ~scale_attribute:"density" in
    Sop.copy_to_points ~source:prototype ~targets ()
    |> Sop.transform (Mat4.translation (Vec3.create 1.45 3.55 1.2))
  in
  [tube; swept_star; tiles; copies; wire; ends_wire; line; joined_path; skinned_shell;
   bridged_shell;
   bent_panel; reduced_terrain; scattered;
   promoted_piece;
   transferred_corners;
   grown_patch; path_ridge; warped_panel; ray_drape; grid_snapped; bound_ovoid;
   matched_arch; oriented_grid; open_ellipse; sliced_ellipse; divided_box;
   advanced_sphere; capped_torus; capped_tube; soccer_ball; spiral_wire;
   filled_tube; beveled_box; creased_box; fading_panel; cut_signal_curve;
   separated_pieces; equalized_wire; relaxed_wire; transported_panel; morphed_panel;
   composited_panel; mirrored_panel; rewired_panel; split_box; emitted_copies]

let init frame =
  let session = Session.create ~max_entries:64
      ~max_payload_bytes:(128 * 1024 * 1024) |> Result.get_ok in
  { session;
    meshes = List.map (cook session frame) (graphs ());
    camera = Easy_camera.create ~target:(Vec3.create 0. 0.5 0.)
        ~distance:9. ~azimuth:0.7 ~elevation:0.45 ();
    frames_left = if Sketch.is_headless () then Some 2 else None; }

let update model frame =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None in
  { model with camera = Easy_camera.update model.camera frame; frames_left }

let view model _frame =
  let lights = [Light.directional ~direction:(Vec3.create (-1.) (-2.) (-1.))
      ~ambient:(Color.hex_exn "#1e293b") ()] in
  let nodes = List.map (fun mesh -> Scene3.mesh ~cull:Scene3.Cull_none
      ~material:(Material.create ~diffuse:Color.white ()) mesh) model.meshes in
  Scene.[
    clear (Color.hex_exn "#020617");
    view3d ~camera:(Easy_camera.camera model.camera)
      (Scene3.create ~lights ~samples:4 nodes);
    text ~at:(16, 16)
      "Procedural modeling — production generators and modeling modifiers";
  ]

let on_stop model = Session.close model.session

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 960; height = 640;
      title = "Prismel Procedural Modeling" }
    ~init ~update ~view ~on_stop ())
