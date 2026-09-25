open Prismel
open Procedural

let color hex = Color.hex_exn hex
let v = Vec3.create
let move x y z node = Sop.transform (Mat4.translation (v x y z)) node
let box () = Sop.box ~connectivity:Pdk.Box_generator.Box_quads
    ~consolidate_points:true ~size:(v 2. 2. 2.) ()
let sphere () = Sop.uv_sphere ~segments:24 ~rings:16 ~radius:1. ()
let torus () = Sop.torus ~rows:28 ~columns:36 ~major_radius:1.4
    ~minor_radius:0.45 ()
let polygon points =
  let count = Array.length points in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.map (fun (x,_,_) -> x) points)
      ~y:(Array.map (fun (_,y,_) -> y) points)
      ~z:(Array.map (fun (_,_,z) -> z) points) in
  let topology = Pdk.Topology.polygons_owned ~point_count:count
      ~vertex_points:(Array.init count Fun.id)
      ~primitive_offsets:[|0;count|] |> Result.get_ok in
  Pdk.Geometry.create ~positions ~topology () |> Result.get_ok
  |> Sop.snapshot

let boolean () =
  let left = box () in
  let right = box () |> Sop.transform (Mat4.mul
      (Mat4.translation (v 0.65 0. 0.)) (Mat4.rotation_y 0.4)) in
  Sop.boolean ~operation:Pdk.Boolean.Difference ~right left
  |> Sop.normals ~owner:Pdk.Attribute.Vertex

let collision_pair () =
  let source = Sop.grid ~counts:Pdk.Plane_generators.Grid_point_counts
      ~connectivity:Pdk.Plane_generators.Grid_alternating_triangles
      ~columns:28 ~rows:24 ~size:3.8 () in
  let collision = source |> Sop.transform (Mat4.mul
      (Mat4.rotation_z 0.18) (Mat4.rotation_x 1.08)) in
  source, collision

let circle_from_edges () =
  Sop.circle ~segments:80 ~radius:1. ()
  |> Sop.circle_from_edges ~scale:(v 1. 0.72 1.)
  |> Sop.polywire ~sides:6 ~radius:0.025

let convex_hull () =
  let points = Array.init 1_000 (fun i ->
      let a = float i *. 2.399963 and h = 1. -. (2. *. float i /. 999.) in
      let r = sqrt (max 0. (1. -. (h *. h))) in
      r *. cos a, h, r *. sin a) in
  Sop.points points |> Sop.convex_hull
  |> Sop.normals ~owner:Pdk.Attribute.Vertex

let extract_centroid () =
  let targets = box () |> Sop.extract_centroid
      ~run_over:Pdk.Ops.Centroid_primitives
      ~method_:Pdk.Ops.Centroid_bounding_box in
  Sop.copy_to_points ~source:(Sop.uv_sphere ~segments:12 ~rings:8
      ~radius:0.13 ()) ~targets ()

let extract_point_curve () =
  let source = Sop.polyline [|(-1.5,0.,0.);(-0.5,0.8,0.);
      (0.5,-0.8,0.);(1.5,0.,0.)|]
    |> Sop.attribute_randomize ~seed:2026 ~owner:Pdk.Attribute.Point
         ~name:"signal" (Pdk.Attribute_ops.Random_uniform {
           min=Pdk.Attribute_ops.Scalar 0.;
           max=Pdk.Attribute_ops.Scalar 1.}) in
  let targets = source |> Sop.extract_point_from_curve
      ~cut:(Sop.Extract_point_constant 0.5) ~distance_attribute:"signal" in
  Sop.copy_to_points ~source:(Sop.uv_sphere ~segments:12 ~rings:8
      ~radius:0.14 ()) ~targets ()

let graph_color () =
  Sop.grid ~connectivity:Pdk.Plane_generators.Grid_quads
    ~columns:18 ~rows:12 ~size:2. ()
  |> Sop.graph_color ~connectivity:Pdk.Ops.Graph_primitives_by_edge

let intersection_analysis () =
  let source, collision = collision_pair () in
  let targets = Sop.intersection_analysis ~collision source in
  Sop.copy_to_points ~source:(Sop.uv_sphere ~segments:9 ~rings:6
      ~radius:0.045 ()) ~targets ()

let remesh () =
  sphere () |> Sop.mountain ~seed:91 ~height:0.12
      ~frequency:(v 2.2 1.7 2.5) ~octaves:4
  |> Sop.remesh ~target_length:0.25 ~iterations:2 ~smoothing:0.35

let terrain () =
  Sop.grid ~columns:100 ~rows:100 ~size:10. ()
  |> Sop.noise_displace ~seed:42 ~amplitude:1.25 ~frequency:0.22
  |> Sop.color_by_height ~low:(color "#172554") ~high:(color "#fbbf24")

let triangulate_2d () =
  let points = Array.init 80 (fun i ->
      let a = float i *. 2.399963 and r = 1.8 *. sqrt (float i /. 79.) in
      r *. cos a, r *. sin a, 0.) in
  Sop.points points |> Sop.triangulate_2d

let curve_mesh () =
  let points = Array.init 72 (fun i ->
      let u = float i /. 71. in
      let a = u *. 4. *. Float.pi in
      1.2 *. cos a, (u -. 0.5) *. 2.8, 1.2 *. sin a) in
  Sop.polyline points |> Sop.resample ~maximum_segment_length:0.08
  |> Sop.sweep_circle ~sides:8 ~radius:0.12

let csg () =
  let left = sphere () and right = box () |> move 0.35 0. 0. in
  let result op x = Sop.boolean ~operation:op ~right left |> move x 0. 0. in
  Sop.merge [result Pdk.Boolean.Union (-3.);
    result Pdk.Boolean.Intersection 0.;
    result Pdk.Boolean.Difference 3.]

let meshes () =
  let star = Array.init 18 (fun i ->
      let a = Float.pi *. float i /. 9. in
      let r = if i mod 2 = 0 then 1. else 0.45 in
      r *. cos a, 0., r *. sin a) in
  let extrusion = polygon star
    |> Sop.poly_extrude ~distance:0.65 |> move (-3.3) 0. 0. in
  let profile = [Vec2.create 0.05 (-1.2); Vec2.create 0.8 (-1.);
      Vec2.create 0.5 0.; Vec2.create 0.9 0.8;
      Vec2.create 0.1 1.2] in
  let lathe = Pdk.Curve_sampling.catmull_rom2 ~resolution:7 profile
    |> Result.get_ok |> List.map (fun (p : Vec2.t) -> p.x,p.y,0.)
    |> Array.of_list |> Sop.polyline
    |> Sop.revolve ~divisions:36 ~origin:Vec3.zero ~axis:Vec3.unit_y
      ~caps:true |> move (-1.1) 0. 0. in
  let sweep = curve_mesh () |> move 1.1 0. 0. in
  let subdivided = sphere () |> Sop.triangulate
    |> Sop.subdivide ~scheme:Pdk.Ops.Loop ~iterations:1
    |> move 3.3 0. 0. in
  let plain node = Sop.delete_attributes ~point_pattern:"*"
      ~vertex_pattern:"*" ~primitive_pattern:"*" ~detail_pattern:"*" node in
  Sop.merge (List.map plain [extrusion; lathe; sweep; subdivided])

let subdivision () =
  let source = Pdk.Ops.platonic ~kind:Pdk.Ops.Platonic_icosahedron
      ~radius:1.15 () |> Result.get_ok in
  let packed operation = operation source |> Result.get_ok |> Sop.snapshot in
  let plain node = Sop.delete_attributes ~point_pattern:"*"
      ~vertex_pattern:"*" ~primitive_pattern:"*" ~detail_pattern:"*" node in
  Sop.merge (List.map plain [
    Sop.snapshot source |> Sop.subdivide ~scheme:Pdk.Ops.Loop
      ~iterations:2 |> move (-3.75) 0. 0.;
    packed (Pdk.Subdivision_extra.butterfly ~iterations:2)
      |> move (-1.25) 0. 0.;
    Sop.snapshot source |> Sop.subdivide ~scheme:Pdk.Ops.Catmull_clark
      ~iterations:2 |> move 1.25 0. 0.;
    packed (Pdk.Subdivision_extra.doo_sabin ~iterations:1)
      |> move 3.75 0. 0.])

let curves () =
  let rose = Array.init 720 (fun i ->
      let a = Float.pi *. 2. *. float i /. 720. in
      let r = 1.45 *. cos (7. *. a) in
      r *. cos a, r *. sin a, 0.) in
  let superformula = Array.init 360 (fun i ->
      let a = Float.pi *. 2. *. float i /. 360. in
      let ca = abs_float (cos (5. *. a /. 4.))
      and sa = abs_float (sin (5. *. a /. 4.)) in
      let r = 1. /. ((ca ** 0.8 +. sa ** 0.8) ** (1. /. 0.35)) in
      1.4 *. r *. cos a, 1.4 *. r *. sin a, 0.) in
  let controls = [Vec2.create (-1.) 0.; Vec2.create (-0.5) 1.;
      Vec2.create 0.5 (-1.); Vec2.create 1. 0.] in
  let sampled = Pdk.Curve_sampling.catmull_rom2 ~resolution:24 controls
    |> Result.get_ok |> List.map (fun (p : Vec2.t) -> p.x,p.y,0.)
    |> Array.of_list in
  let wire ~x points = Sop.polyline ~closed:true points
      |> Sop.polywire ~sides:6 ~radius:0.018 |> move x 0. 0. in
  Sop.merge [wire ~x:(-3.) rose; wire ~x:0. superformula;
    Sop.polyline sampled |> Sop.polywire ~sides:6 ~radius:0.03
      |> move 3. 0. 0.]

let voronoi () =
  let sites = List.init 24 (fun i ->
      let a = 2.399963 *. float i in
      let r = 1.6 *. sqrt (float (i + 1) /. 24.) in
      Vec2.create (r *. cos a) (r *. sin a)) in
  let bounds = Bounds2.make ~min:(Vec2.create (-2.) (-2.))
      ~max:(Vec2.create 2. 2.) in
  let cells = Pdk.Voronoi2.cells ~bounds sites |> Result.get_ok in
  let vertices = cells |> List.concat_map (fun (cell : Pdk.Voronoi2.cell) ->
      cell.vertices) |> Array.of_list in
  let point_count = Array.length vertices in
  let positions = Pdk.Packed.Float3.Private.of_owned_exn
      ~x:(Array.map (fun (p : Vec2.t) -> p.x) vertices)
      ~y:(Array.map (fun (p : Vec2.t) -> p.y) vertices)
      ~z:(Array.make point_count 0.) in
  let topology = Pdk.Topology.Builder.create ~point_count () in
  let offset = ref 0 in
  List.iter (fun (cell : Pdk.Voronoi2.cell) ->
      let count = List.length cell.vertices in
      Pdk.Topology.Builder.add_closed_polyline topology
        (Array.init count (fun i -> !offset + i));
      offset := !offset + count) cells;
  Pdk.Geometry.create ~positions
    ~topology:(Pdk.Topology.Builder.freeze topology) ()
  |> Result.get_ok |> Sop.snapshot |> Sop.polywire ~sides:6 ~radius:0.014

let isosurface () =
  let minimum = v (-1.4) (-1.4) (-1.4)
  and maximum = v 1.4 1.4 1.4 in
  Pdk.Iso_surface.extract_dense ~resolution:(20,20,20)
    ~min:minimum ~max:maximum ~iso:0.
    ~field:(Pdk.Iso_surface.Field.gyroid ~scale:2.6 ()) ()
  |> Result.get_ok |> Sop.snapshot

let entries = [|
  "attribute_laplacian", (fun () -> torus ()
    |> Sop.attribute_laplacian ~source:"P");
  "boolean", boolean;
  "boolean_detect", (fun () -> let a,b = collision_pair () in
    Sop.boolean_detect ~collision:b a);
  "circle_from_edges", circle_from_edges;
  "convex_hull", convex_hull;
  "extract_centroid", extract_centroid;
  "extract_point_curve", extract_point_curve;
  "graph_color", graph_color;
  "intersection_analysis", intersection_analysis;
  "measure_curvature", (fun () -> torus () |> Sop.measure_curvature);
  "remesh", remesh;
  "triangulate_2d", triangulate_2d;
  "procedural_terrain", terrain;
  "geom_csg", csg;
  "geom_curves", curves;
  "geom_meshes", meshes;
  "geom_subdivision", subdivision;
  "geom_isosurface", isosurface;
  "geom_voronoi", voronoi;
|]

let material = Material.create ~diffuse:Color.white
    ~ambient:(color "#172554") ~specular:Color.white ~shininess:36. ()

let prepare output = Bridge.to_mesh output.Session.geometry
  |> Result.map_error Pdk.Error.to_string

let scene3 _graph mesh =
  let mode = Mesh.mode mesh in
  let material = match mode with
    | Mesh.Points | Lines | Line_strip | Line_loop ->
        Material.unlit (color "#67e8f9")
    | Triangles | Triangle_strip | Triangle_fan -> material in
  Scene3.create ~samples:4 ~lights:[
    Light.directional ~direction:(v (-1.) (-1.2) (-2.))
      ~diffuse:Color.white ~ambient:(color "#172554") ()]
    [Scene3.mesh ~cull:Scene3.Cull_none ~material mesh]

let check_all () =
  let context = Context.create ~seed:2026L ~domains:1 () |> Result.get_ok in
  Array.iter (fun (name, graph) ->
      let session = Session.create ~max_entries:24
          ~max_payload_bytes:134_217_728 |> Result.get_ok in
      Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
        match Session.cook session ~context (graph ()) with
        | Error error -> failwith (name ^ ": " ^
            Diagnostic.error_to_string error)
        | Ok output ->
            if Pdk.Geometry.point_count output.geometry = 0 then
              failwith (name ^ ": empty geometry");
            (match prepare output with
             | Ok mesh when Mesh.vertex_count mesh > 0 -> ()
             | Ok _ -> failwith (name ^ ": empty render mesh")
             | Error error -> failwith (name ^ ": " ^ error));
            Printf.printf "%s: %d points, %d primitives\n%!" name
              (Pdk.Geometry.point_count output.geometry)
              (Pdk.Geometry.primitive_count output.geometry))) entries

let () =
  let entry = ref "boolean" and list = ref false and check = ref false in
  Arg.parse ["--entry", Arg.Set_string entry, "Gallery entry";
             "--list", Arg.Set list, "List entries";
             "--check-all", Arg.Set check, "Cook every entry without a window"]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "sop_gallery [--list | --check-all | --entry NAME]";
  if !list then Array.iter (fun (name, _) -> print_endline name) entries
  else if !check then check_all ()
  else match Array.find_opt (fun (name, _) -> name = !entry) entries with
    | None -> failwith ("unknown gallery entry: " ^ !entry)
    | Some (name, graph) ->
        Sketch_ui.Environment3.run
          ~config:{Sketch.default_config with width=1100; height=720;
            title="Prismel SOP gallery · " ^ name}
          ~name:"sop_gallery" ~factories:Sop_catalog.Editor.factories
          ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:6.
            ~azimuth:0.6 ~elevation:0.35 ())
          ~seed:2026L ~max_entries:24 ~max_payload_bytes:134_217_728
          ~graph:(graph ()) ~prepare ~scene3 ()
