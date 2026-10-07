open Rays
open Procedural

let grid () = Sop.grid ~width_mode:Procedural.Sop.Kernel_auto ~height_mode:Procedural.Sop.Kernel_auto ~columns:8 ~rows:6 ~size:2. ()
let box () = Sop.box ~normals:None ~connectivity:Rdk.Box_generator.Box_quads
    ~consolidate_points:true ~size:(Vec3.create 1.8 1.8 1.8) ()
let torus () = Rdk.Parametric_generators.torus ~connectivity:Rdk.Parametric_generators.Torus_alternating_triangles
    ~rows:16 ~columns:12 ~major_radius:1. ~minor_radius:0.3 ()
    |> Result.get_ok |> Sop.snapshot
let curve () = Sop.polyline
    [|(-1.5,-0.4,0.);(-0.7,0.5,0.);(0.,-0.3,0.);(0.6,0.6,0.);(1.5,-0.2,0.)|]
let wire node = (Sop.polywire ~use_sides:true ~use_max_valence:false ~use_u_range:false ~use_v_range:false ~cap_group:"" ~sides:(6) ~radius:(0.04) ~caps:(true) (node))
let marker = Sop.uv_sphere ~radius_x_mode:Procedural.Sop.Kernel_auto ~radius_y_mode:Procedural.Sop.Kernel_auto ~radius_z_mode:Procedural.Sop.Kernel_auto ~normals_mode:Procedural.Sop.Kernel_auto ~uv_attribute:"" ~segments:8 ~rings:5 ~base_radius:0.08 ()

let signal_curve () =
  let count = 97 in
  let positions = Rdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.init count (fun point ->
        -2.2 +. (4.4 *. float_of_int point /. float_of_int (count - 1))))
      ~y:(Array.init count (fun point -> 0.16 *. sin (float_of_int point *. 0.19)))
      ~z:(Array.make count 0.) in
  let topology = Rdk.Topology.create_owned ~point_count:count
      ~vertex_points:(Array.init count Fun.id) ~primitive_offsets:[|0;count|]
      ~primitive_kinds:[|Rdk.Topology.Open_polyline|] |> Result.get_ok in
  let signal = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"signal" (Rdk.Attribute.Float (Array.init count (fun point ->
        sin (float_of_int point *. 0.31))))
      |> Result.get_ok in
  Rdk.Geometry.create ~positions ~topology ~attributes:[signal] ()
  |> Result.get_ok |> Sop.snapshot

let rewire_source () =
  let geometry = Rdk.Plane_generators.grid ~connectivity:Rdk.Plane_generators.Grid_quads
      ~columns:3 ~rows:3 ~size:2. () |> Result.get_ok in
  let targets = Array.init (Rdk.Geometry.point_count geometry)
      (fun point -> if point = 0 then 1 else -1) in
  let target = Rdk.Attribute.create_owned ~owner:Rdk.Attribute.Point
      ~name:"targetpt" (Rdk.Attribute.Int targets) |> Result.get_ok in
  Rdk.Geometry.with_attribute target geometry |> Result.get_ok |> Sop.snapshot

let nonempty geometry =
  if Rdk.Geometry.point_count geometry = 0
     || Rdk.Geometry.primitive_count geometry = 0 then
    failwith "cooked geometry is empty"

let point_attribute name geometry =
  nonempty geometry;
  if Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Point name geometry = None
  then failwith ("missing point attribute " ^ name)

let primitive_attribute name geometry =
  nonempty geometry;
  if Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive name geometry = None
  then failwith ("missing primitive attribute " ^ name)

let primitive_group name geometry =
  nonempty geometry;
  if Rdk.Geometry.find_group ~owner:Rdk.Group.Primitive name geometry = None
  then failwith ("missing primitive group " ^ name)

let rows = [
  "attribute_composite", (fun () ->
    let target = grid () |> Sop.bend ~up:(Vec3.unit_y) ~direction:(Vec3.unit_z) ~continuous_twist:(true) ~length:2. ~bend_angle:0.5
        |> Sop.set_color ~owner:Rdk.Attribute.Point ~color:Vec3.unit_x in
    grid () |> Sop.set_color ~owner:Rdk.Attribute.Point ~color:Vec3.unit_z
    |> fun input -> Sop.attribute_composite ~point_attributes:"P Cd" ~allow_position:true
         ~weight1:0.5 input (Some target) None None None []),
    point_attribute "Cd";
  "attribute_fade", (fun () ->
    (Sop.attribute_fade ~fade_in:2. ~fade_hold:2. ~fade_out:2. ~visualize:true
  (grid ()) None None)), point_attribute "fade";
  "attribute_laplacian", (fun () ->
    torus () |> Sop.attribute_laplacian ~output:("") ~source:"P"),
    point_attribute "laplacian";
  "attribute_mirror", (fun () ->
    grid () |> Sop.set_color ~owner:Rdk.Attribute.Point ~color:Vec3.unit_x
    |> Sop.attribute_mirror ~owner:Rdk.Attribute_mirror.Mirror_point_attributes
         ~attributes:"Cd"
         ~method_:Sop.Mirror_plane ~origin:Vec3.zero ~normal:Vec3.unit_x ~distance:0. ~tolerance:1e-10),
    point_attribute "Cd";
  "blend_shapes", (fun () ->
    Sop.blend_shapes ~weight1:0.5 ~mask_attribute:""
      ~mask_source:Rdk.Blend_shapes.Blend_mask_shape (grid ())
      (Some (grid () |> Sop.bend ~up:(Vec3.unit_y) ~direction:(Vec3.unit_z) ~continuous_twist:(true) ~length:2. ~bend_angle:0.5))
      None None None []), nonempty;
  "boolean_detect", (fun () ->
    let source = grid () in
    let collision = grid () |> (let migration_matrix = Mat4.rotation_x 0.8 in
fun migration_input ->
  Sop.transform ~mode:Sop.Transform_matrix
    ~m11:(Mat4.get migration_matrix ~row:1 ~column:1)
    ~m12:(Mat4.get migration_matrix ~row:1 ~column:2)
    ~m21:(Mat4.get migration_matrix ~row:2 ~column:1)
    ~m22:(Mat4.get migration_matrix ~row:2 ~column:2) migration_input) in
    source |> (fun detect_source -> Sop.boolean_detect ~intersecting_group:("crossing") ~self_intersecting_group:"" detect_source (Some (collision)))), primitive_group "crossing";
  "boolean", (fun () ->
    box () |> (fun boolean_left -> Sop.boolean ~operation:(Rdk.Boolean.Difference) boolean_left (Sop.box ~normals:None ~connectivity:Rdk.Box_generator.Box_triangles
  ~size:(Vec3.create 1.2 1.2 1.2) ~center:(Vec3.create 0.5 0. 0.) ()))), nonempty;
  "circle_from_edges", (fun () ->
    Sop.polyline ~closed:true
      [|(-1.,-1.,0.);(1.,-1.,0.);(1.,1.,0.);(-1.,1.,0.)|]
    |> Sop.circle_from_edges ~use_radius:true ~radius:1. |> wire), nonempty;
  "convex_hull", (fun () ->
    Sop.points [|(-1.,-1.,-1.);(1.,-1.,-1.);(1.,1.,-1.);(-1.,1.,-1.);
      (-1.,-1.,1.);(1.,-1.,1.);(1.,1.,1.);(-1.,1.,1.)|]
    |> Sop.convex_hull), nonempty;
  "edge_equalize", (fun () ->
    curve () |> Sop.edge_equalize ~iterations:12
      ~output_group:"equalized" |> wire), nonempty;
  "edge_relax", (fun () ->
    curve () |> (fun input -> Sop.edge_relax ~iterations:12 input (Sop.polyline
      [|(-1.5,-0.4,0.);(-0.7,0.,0.);(0.,0.1,0.);
        (0.6,0.2,0.);(1.5,-0.2,0.)|])) |> wire), nonempty;
  "edge_transport", (fun () ->
    grid () |> Sop.set_float ~owner:Rdk.Attribute.Point ~name:"distance" ~value:0.
    |> Sop.edge_transport ~attribute:"distance"
      ~operation:Rdk.Edge_transport.Transport_total
    |> Sop.peak ~direction_attribute:("") ~mask_attribute:"distance" ~distance:0.25),
    point_attribute "distance";
  "extract_centroid", (fun () ->
    box () |> Sop.extract_centroid ~run_over:Sop.Primitives
      ~method_:Rdk.Curve_topology.Centroid_bounding_box
    |> fun targets -> (Sop.copy_to_points marker targets)), nonempty;
  "extract_point_curve", (fun () ->
    signal_curve () |> Sop.extract_point_from_curve ~distance_attribute:"signal"
    |> fun targets -> (Sop.copy_to_points marker targets)), nonempty;
  "graph_color", (fun () ->
    grid () |> Sop.graph_color
      ~connectivity:Rdk.Graph_color.Graph_primitives_by_point),
    primitive_attribute "color";
  "intersection_analysis", (fun () ->
    let source = grid () in
    let collision = grid () |> (let migration_matrix = Mat4.rotation_x 0.8 in
fun migration_input ->
  Sop.transform ~mode:Sop.Transform_matrix
    ~m11:(Mat4.get migration_matrix ~row:1 ~column:1)
    ~m12:(Mat4.get migration_matrix ~row:1 ~column:2)
    ~m21:(Mat4.get migration_matrix ~row:2 ~column:1)
    ~m22:(Mat4.get migration_matrix ~row:2 ~column:2) migration_input) in
    source |> (fun intersection_source -> Sop.intersection_analysis intersection_source (Some (collision)))
    |> fun targets -> (Sop.copy_to_points marker targets)), nonempty;
  "measure_curvature", (fun () ->
    torus () |> Sop.measure_curvature), point_attribute "curvature";
  "poly_cut", (fun () ->
    signal_curve () |> Sop.poly_cut ~element:Rdk.Poly_cut.Poly_cut_points
      ~strategy:Rdk.Poly_cut.Poly_cut_remove
      ~detection:Sop.Cut_crossing ~attribute:"signal" ~value:0.
    |> wire), nonempty;
  "procedural", (fun () ->
    box () |> Sop.bend ~up:(Vec3.unit_y) ~direction:(Vec3.unit_z) ~continuous_twist:(true) ~length:2. ~bend_angle:0.5
    |> Sop.set_color ~owner:Rdk.Attribute.Point ~color:Vec3.unit_z), nonempty;
  "remesh", (fun () ->
    Sop.box ~normals:None ~connectivity:Rdk.Box_generator.Box_triangles
      ~consolidate_points:true ()
    |> Sop.remesh ~target_length:0.5 ~iterations:1 ~project:true
      ~output_quality:"quality"), primitive_attribute "quality";
  "rewire_vertices", (fun () ->
    rewire_source () |> Sop.rewire_vertices
      ~owner:Rdk.Attribute.Point ~target_attribute:"targetpt"
      ~original_point_attribute:"origpt"), (fun geometry ->
        nonempty geometry;
        if Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex
            "origpt" geometry = None then failwith "missing vertex attribute origpt");
  "separate_pieces", (fun () ->
    let piece id x = box () |> Sop.set_int ~owner:Rdk.Attribute.Primitive
        ~name:"piece" ~value:id
        |> (let migration_translation = Vec3.create x 0. 0. in
fun migration_input ->
  Sop.transform ~mode:Sop.Transform_matrix ~m03:migration_translation.Vec3.x
    ~m13:migration_translation.Vec3.y ~m23:migration_translation.Vec3.z
    migration_input) in
    Sop.merge [piece 1 (-0.4); piece 2 0.4]
    |> Sop.separate_pieces ~owner:Rdk.Attribute.Primitive
      ~piece_attribute:"piece" ~translation_attribute:"separation"
      ~gap:0.2), primitive_attribute "separation";
  "triangulate2d", (fun () ->
    Sop.points [|(-1.,-1.,0.);(1.,-1.,0.);(1.,1.,0.);(-1.,1.,0.);
      (0.,0.,0.);(0.4,0.2,0.);(-0.5,0.3,0.)|]
    |> Sop.triangulate_2d ~projection:Sop.Triangulate_xy
      ~triangle_group:"triangles"), primitive_group "triangles";
]

let cook domains graph =
  let session = Session.create ~max_entries:8
      ~max_payload_bytes:(64 * 1024 * 1024) |> Result.get_ok in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    let context = Context.create ~seed:2026L ~frame:5L ~domains ~grain:17 ()
        |> Result.get_ok in
    match Session.cook session ~context graph with
    | Ok output -> output.geometry
    | Error error -> failwith (Diagnostic.error_to_string error))

let scene geometry =
  let mesh = Rdk_rays.Rays_mesh.to_mesh geometry |> Result.get_ok in
  let camera = Camera.perspective ~at:(Vec3.create 3.5 3. 5.)
      ~target:Vec3.zero () in
  Scene.[clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:1 [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit Color.white) mesh])]

(* One window per domain count: every graph is one frame of the same export. *)
let export directory domains geometries =
  let config = {Sketch.default_config with width=256; height=192;
    domains=Some domains} in
  let scenes = Array.of_list (List.map scene geometries) in
  ignore (Sketch.export_state ~config ~directory ~prefix:"parity"
    ~frames:(Array.length scenes) ~init:(fun _ -> 0)
    ~update:(fun _ (frame : Frame.t) -> frame.count - 1)
    ~view:(fun index _ -> scenes.(max 0 (min index (Array.length scenes - 1)))) ())

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let run () =
  let root = Filename.temp_file "rays-sop-parity-" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  let one = Filename.concat root "one" and four = Filename.concat root "four" in
  Fun.protect ~finally:(fun () ->
    List.iter (fun directory ->
      if Sys.file_exists directory then begin
        Sys.readdir directory |> Array.iter (fun file ->
          Sys.remove (Filename.concat directory file));
        Unix.rmdir directory
      end) [one; four];
    Unix.rmdir root) (fun () ->
      let cooked = List.map (fun (name, graph, check) ->
        let cook domains =
          try cook domains (graph ()) with
          | Failure message -> failwith (name ^ ": " ^ message) in
        let one_geometry = cook 1 and four_geometry = cook 4 in
        (try check one_geometry; check four_geometry with
         | Failure message -> failwith (name ^ ": " ^ message));
        if Rdk.Geometry.point_count one_geometry
           <> Rdk.Geometry.point_count four_geometry
           || Rdk.Geometry.primitive_count one_geometry
              <> Rdk.Geometry.primitive_count four_geometry then
          failwith (name ^ ": cook cardinality differs by domain count");
        name, one_geometry, four_geometry) rows in
      export one 1 (List.map (fun (_, geometry, _) -> geometry) cooked);
      export four 4 (List.map (fun (_, _, geometry) -> geometry) cooked);
      (* Each frame shows its own graph, so the comparison is per graph. *)
      if read (Filename.concat one "parity-000000.png")
         = read (Filename.concat one "parity-000001.png") then
        failwith "parity export repeated one graph across frames";
      List.iteri (fun index (name, _, _) ->
        let filename = Printf.sprintf "parity-%06d.png" index in
        let one_png = read (Filename.concat one filename)
        and four_png = read (Filename.concat four filename) in
        if not (String.equal one_png four_png) then
          failwith (name ^ ": one/four-domain PNG bytes differ");
        if String.length one_png < 100 then
          failwith (name ^ ": PNG is empty")) cooked);
  Printf.printf "SOP render parity: %d graphs, one/four-domain PNGs equal\n%!"
    (List.length rows)
