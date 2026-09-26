open Prismel
open Procedural

let grid () = Sop.grid ~columns:8 ~rows:6 ~size:2. ()
let box () = Sop.box ~connectivity:Pdk.Box_generator.Box_quads
    ~consolidate_points:true ~size:(Vec3.create 1.8 1.8 1.8) ()
let torus () = Pdk.Parametric_generators.torus_checked ~connectivity:Pdk.Parametric_generators.Torus_alternating_triangles
    ~rows:16 ~columns:12 ~major_radius:1. ~minor_radius:0.3 ()
    |> Result.get_ok |> Sop.snapshot
let curve () = Sop.polyline
    [|(-1.5,-0.4,0.);(-0.7,0.5,0.);(0.,-0.3,0.);(0.6,0.6,0.);(1.5,-0.2,0.)|]
let wire node = Sop.polywire ~sides:6 ~radius:0.04 ~caps:true node
let marker = Sop.uv_sphere ~segments:8 ~rings:5 ~radius:0.08 ()

let signal_curve () =
  let count = 97 in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.init count (fun point ->
        -2.2 +. (4.4 *. float_of_int point /. float_of_int (count - 1))))
      ~y:(Array.init count (fun point -> 0.16 *. sin (float_of_int point *. 0.19)))
      ~z:(Array.make count 0.) in
  let topology = Pdk.Topology.create_owned ~point_count:count
      ~vertex_points:(Array.init count Fun.id) ~primitive_offsets:[|0;count|]
      ~primitive_kinds:[|Pdk.Topology.Open_polyline|] |> Result.get_ok in
  let signal = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"signal" (Pdk.Attribute.Float (Array.init count (fun point ->
        sin (float_of_int point *. 0.31))))
      |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology ~attributes:[signal] ()
  |> Result.get_ok |> Sop.snapshot

let rewire_source () =
  let geometry = Pdk.Plane_generators.grid_checked ~connectivity:Pdk.Plane_generators.Grid_quads
      ~columns:3 ~rows:3 ~size:2. () |> Result.get_ok in
  let targets = Array.init (Pdk.Geometry.point_count geometry)
      (fun point -> if point = 0 then 1 else -1) in
  let target = Pdk.Attribute.create_owned ~owner:Pdk.Attribute.Point
      ~name:"targetpt" (Pdk.Attribute.Int targets) |> Result.get_ok in
  Pdk.Geometry.with_attribute target geometry |> Result.get_ok |> Sop.snapshot

let nonempty geometry =
  if Pdk.Geometry.point_count geometry = 0
     || Pdk.Geometry.primitive_count geometry = 0 then
    failwith "cooked geometry is empty"

let point_attribute name geometry =
  nonempty geometry;
  if Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point name geometry = None
  then failwith ("missing point attribute " ^ name)

let primitive_attribute name geometry =
  nonempty geometry;
  if Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive name geometry = None
  then failwith ("missing primitive attribute " ^ name)

let primitive_group name geometry =
  nonempty geometry;
  if Pdk.Geometry.find_group ~owner:Pdk.Group.Primitive name geometry = None
  then failwith ("missing primitive group " ^ name)

let rows = [
  "attribute_composite", (fun () ->
    let target = grid () |> Sop.bend ~length:2. ~bend_angle:0.5
        |> Sop.set_color ~owner:Pdk.Attribute.Point Color.red in
    grid () |> Sop.set_color ~owner:Pdk.Attribute.Point Color.blue
    |> Sop.attribute_composite ~point_attributes:"P Cd" ~allow_position:true
         ~inputs:[Sop.attribute_composite_input ~weight:0.5 target]),
    point_attribute "Cd";
  "attribute_fade", (fun () ->
    grid () |> Sop.attribute_fade ~fade_in:2. ~fade_hold:2. ~fade_out:2.
      ~visualize:true), point_attribute "fade";
  "attribute_laplacian", (fun () ->
    torus () |> Sop.attribute_laplacian ~source:"P"),
    point_attribute "laplacian";
  "attribute_mirror", (fun () ->
    grid () |> Sop.set_color ~owner:Pdk.Attribute.Point Color.red
    |> Sop.attribute_mirror ~owner:Pdk.Attribute_mirror.Mirror_point_attributes
         ~attributes:"Cd"
         ~method_:(Sop.Attribute_mirror_plane {
           origin=Vec3.zero; normal=Vec3.unit_x; distance=0.; tolerance=1e-10 })),
    point_attribute "Cd";
  "blend_shapes", (fun () ->
    grid () |> Sop.blend_shapes
      ~shapes:[Sop.blend_shape ~weight:0.5
        (grid () |> Sop.bend ~length:2. ~bend_angle:0.5)]), nonempty;
  "boolean_detect", (fun () ->
    let source = grid () in
    let collision = grid () |> Sop.transform (Mat4.rotation_x 0.8) in
    source |> Sop.boolean_detect ~collision
      ~intersecting_group:(Some "crossing")), primitive_group "crossing";
  "boolean", (fun () ->
    box () |> Sop.boolean ~operation:Pdk.Boolean.Difference
      ~right:(Sop.box ~size:(Vec3.create 1.2 1.2 1.2)
        ~center:(Vec3.create 0.5 0. 0.) ())), nonempty;
  "circle_from_edges", (fun () ->
    Sop.polyline ~closed:true
      [|(-1.,-1.,0.);(1.,-1.,0.);(1.,1.,0.);(-1.,1.,0.)|]
    |> Sop.circle_from_edges ~radius:1. |> wire), nonempty;
  "convex_hull", (fun () ->
    Sop.points [|(-1.,-1.,-1.);(1.,-1.,-1.);(1.,1.,-1.);(-1.,1.,-1.);
      (-1.,-1.,1.);(1.,-1.,1.);(1.,1.,1.);(-1.,1.,1.)|]
    |> Sop.convex_hull), nonempty;
  "edge_equalize", (fun () ->
    curve () |> Sop.edge_equalize ~iterations:12
      ~output_group:"equalized" |> wire), nonempty;
  "edge_relax", (fun () ->
    curve () |> Sop.edge_relax ~reference:(Sop.polyline
      [|(-1.5,-0.4,0.);(-0.7,0.,0.);(0.,0.1,0.);
        (0.6,0.2,0.);(1.5,-0.2,0.)|]) ~iterations:12 |> wire), nonempty;
  "edge_transport", (fun () ->
    grid () |> Sop.set_float ~owner:Pdk.Attribute.Point ~name:"distance" 0.
    |> Sop.edge_transport ~attribute:"distance"
      ~operation:Pdk.Ops.Transport_total
    |> Sop.peak ~mask_attribute:"distance" ~distance:0.25),
    point_attribute "distance";
  "extract_centroid", (fun () ->
    box () |> Sop.extract_centroid ~run_over:Pdk.Ops.Centroid_primitives
      ~method_:Pdk.Ops.Centroid_bounding_box
    |> fun targets -> Sop.copy_to_points ~source:marker ~targets ()), nonempty;
  "extract_point_curve", (fun () ->
    signal_curve () |> Sop.extract_point_from_curve ~distance_attribute:"signal"
    |> fun targets -> Sop.copy_to_points ~source:marker ~targets ()), nonempty;
  "graph_color", (fun () ->
    grid () |> Sop.graph_color
      ~connectivity:Pdk.Ops.Graph_primitives_by_point),
    primitive_attribute "color";
  "intersection_analysis", (fun () ->
    let source = grid () in
    let collision = grid () |> Sop.transform (Mat4.rotation_x 0.8) in
    source |> Sop.intersection_analysis ~collision
    |> fun targets -> Sop.copy_to_points ~source:marker ~targets ()), nonempty;
  "measure_curvature", (fun () ->
    torus () |> Sop.measure_curvature), point_attribute "curvature";
  "poly_cut", (fun () ->
    signal_curve () |> Sop.poly_cut ~element:Pdk.Ops.Poly_cut_points
      ~strategy:Pdk.Ops.Poly_cut_remove
      ~detection:(Pdk.Ops.Poly_cut_crossing {attribute="signal"; value=0.})
    |> wire), nonempty;
  "procedural", (fun () ->
    box () |> Sop.bend ~length:2. ~bend_angle:0.5
    |> Sop.set_color ~owner:Pdk.Attribute.Point Color.blue), nonempty;
  "remesh", (fun () ->
    Sop.box ~connectivity:Pdk.Box_generator.Box_triangles
      ~consolidate_points:true ()
    |> Sop.remesh ~target_length:0.5 ~iterations:1 ~project:true
      ~output_quality:"quality"), primitive_attribute "quality";
  "rewire_vertices", (fun () ->
    rewire_source () |> Sop.rewire_vertices
      ~owner:Pdk.Attribute.Point ~target_attribute:"targetpt"
      ~original_point_attribute:"origpt"), (fun geometry ->
        nonempty geometry;
        if Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Vertex
            "origpt" geometry = None then failwith "missing vertex attribute origpt");
  "separate_pieces", (fun () ->
    let piece id x = box () |> Sop.set_int ~owner:Pdk.Attribute.Primitive
        ~name:"piece" id
        |> Sop.transform (Mat4.translation (Vec3.create x 0. 0.)) in
    Sop.merge [piece 1 (-0.4); piece 2 0.4]
    |> Sop.separate_pieces ~owner:Pdk.Attribute.Primitive
      ~piece_attribute:"piece" ~translation_attribute:"separation"
      ~gap:0.2), primitive_attribute "separation";
  "triangulate2d", (fun () ->
    Sop.points [|(-1.,-1.,0.);(1.,-1.,0.);(1.,1.,0.);(-1.,1.,0.);
      (0.,0.,0.);(0.4,0.2,0.);(-0.5,0.3,0.)|]
    |> Sop.triangulate_2d ~projection:Pdk.Triangulation_modeling.Triangulate_2d_xy
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
  let mesh = Bridge.to_mesh geometry |> Result.get_ok in
  let camera = Camera.perspective ~at:(Vec3.create 3.5 3. 5.)
      ~target:Vec3.zero () in
  Scene.[clear (Color.hex_exn "#020617");
    view3d ~camera (Scene3.create ~samples:1 [
      Scene3.mesh ~cull:Scene3.Cull_none
        ~material:(Material.unlit Color.white) mesh])]

let export directory prefix domains geometry =
  let config = {Sketch.default_config with width=256; height=192;
    domains=Some domains} in
  Sketch.export ~config ~directory ~prefix ~frames:1
    (fun _ -> scene geometry)

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    really_input_string channel (in_channel_length channel))

let run () =
  let root = Filename.temp_file "prismel-sop-parity-" "" in
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
      List.iter (fun (name, graph, check) ->
        let cook domains =
          try cook domains (graph ()) with
          | Failure message -> failwith (name ^ ": " ^ message) in
        let one_geometry = cook 1 and four_geometry = cook 4 in
        (try check one_geometry; check four_geometry with
         | Failure message -> failwith (name ^ ": " ^ message));
        if Pdk.Geometry.point_count one_geometry
           <> Pdk.Geometry.point_count four_geometry
           || Pdk.Geometry.primitive_count one_geometry
              <> Pdk.Geometry.primitive_count four_geometry then
          failwith (name ^ ": cook cardinality differs by domain count");
        export one name 1 one_geometry;
        export four name 4 four_geometry;
        let filename = name ^ "-000000.png" in
        let one_png = read (Filename.concat one filename)
        and four_png = read (Filename.concat four filename) in
        if not (String.equal one_png four_png) then
          failwith (name ^ ": one/four-domain PNG bytes differ");
        if String.length one_png < 100 then
          failwith (name ^ ": PNG is empty")
      ) rows);
  Printf.printf "SOP render parity: %d graphs, one/four-domain PNGs equal\n%!"
    (List.length rows)
