open Prismel
open Procedural

let color hex = Color.hex_exn hex
let v = Vec3.create

(* The inputs the catalog has no node for: point clouds, curves and meshes built in OCaml
   from Pdk. Each is a source SOP of its own (gallery.plisp spells them sop/gallery_NAME),
   which is how a sketch adds nodes beside the catalog. *)
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


let star () =
  polygon (Array.init 18 (fun i ->
      let a = Float.pi *. float i /. 9. in
      let r = if i mod 2 = 0 then 1. else 0.45 in
      r *. cos a, 0., r *. sin a))

let profile () =
  let profile = [Vec2.create 0.05 (-1.2); Vec2.create 0.8 (-1.);
      Vec2.create 0.5 0.; Vec2.create 0.9 0.8;
      Vec2.create 0.1 1.2] in
  Pdk.Curve_sampling.catmull_rom2 ~resolution:7 profile
  |> Result.get_ok |> List.map (fun (p : Vec2.t) -> p.x,p.y,0.)
  |> Array.of_list |> Sop.polyline

let helix () =
  Sop.polyline (Array.init 72 (fun i ->
      let u = float i /. 71. in
      let a = u *. 4. *. Float.pi in
      1.2 *. cos a, (u -. 0.5) *. 2.8, 1.2 *. sin a))

let fibonacci () =
  Sop.points (Array.init 1_000 (fun i ->
      let a = float i *. 2.399963 and h = 1. -. (2. *. float i /. 999.) in
      let r = sqrt (max 0. (1. -. (h *. h))) in
      r *. cos a, h, r *. sin a))

let disc () =
  Sop.points (Array.init 80 (fun i ->
      let a = float i *. 2.399963 and r = 1.8 *. sqrt (float i /. 79.) in
      r *. cos a, r *. sin a, 0.))

let zigzag () =
  Sop.polyline [|(-1.5,0.,0.);(-0.5,0.8,0.);(0.5,-0.8,0.);(1.5,0.,0.)|]

let rose () =
  Sop.polyline ~closed:true (Array.init 720 (fun i ->
      let a = Float.pi *. 2. *. float i /. 720. in
      let r = 1.45 *. cos (7. *. a) in
      r *. cos a, r *. sin a, 0.))

let superformula () =
  Sop.polyline ~closed:true (Array.init 360 (fun i ->
      let a = Float.pi *. 2. *. float i /. 360. in
      let ca = abs_float (cos (5. *. a /. 4.))
      and sa = abs_float (sin (5. *. a /. 4.)) in
      let r = 1. /. ((ca ** 0.8 +. sa ** 0.8) ** (1. /. 0.35)) in
      1.4 *. r *. cos a, 1.4 *. r *. sin a, 0.))

let spline () =
  let controls = [Vec2.create (-1.) 0.; Vec2.create (-0.5) 1.;
      Vec2.create 0.5 (-1.); Vec2.create 1. 0.] in
  Pdk.Curve_sampling.catmull_rom2 ~resolution:24 controls
  |> Result.get_ok |> List.map (fun (p : Vec2.t) -> p.x,p.y,0.)
  |> Array.of_list |> Sop.polyline

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
  |> Result.get_ok |> Sop.snapshot

let isosurface () =
  let minimum = v (-1.4) (-1.4) (-1.4)
  and maximum = v 1.4 1.4 1.4 in
  Pdk.Iso_surface.extract_dense ~resolution:(20,20,20)
    ~min:minimum ~max:maximum ~iso:0.
    ~field:(Pdk.Iso_surface.Field.gyroid ~scale:2.6 ()) ()
  |> Result.get_ok |> Sop.snapshot


let sources = [
  "gallery_star", "Star polygon", star;
  "gallery_profile", "Lathe profile", profile;
  "gallery_helix", "Helix", helix;
  "gallery_fibonacci", "Fibonacci sphere points", fibonacci;
  "gallery_disc", "Disc points", disc;
  "gallery_zigzag", "Zigzag curve", zigzag;
  "gallery_rose", "Rose curve", rose;
  "gallery_superformula", "Superformula curve", superformula;
  "gallery_spline", "Catmull-Rom spline", spline;
  "gallery_voronoi", "Voronoi cells", voronoi;
  "gallery_isosurface", "Gyroid isosurface", isosurface;
]

let factories = List.map (fun (key, label, build) ->
    Edit_graph.factory ~key ~label ~category:["Gallery"] ~arity:0 (fun _ -> build ()))
  sources @ Sop_catalog.Editor.factories

let material = Material.create ~diffuse:Color.white
    ~ambient:(color "#172554") ~specular:Color.white ~shininess:36. ()

(* A packed cook (Copy to Points, Pack and instance) keeps its transforms. *)
let prepare output = Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
  |> Result.map (fun mesh -> mesh, output.Session.instances)
  |> Result.map_error Pdk.Error.to_string

let scene3 _graph (mesh, instances) =
  let mode = Mesh.mode mesh in
  let material = match mode with
    | Mesh.Points | Lines | Line_strip | Line_loop ->
        Material.unlit (color "#67e8f9")
    | Triangles | Triangle_strip | Triangle_fan -> material in
  Scene3.create ~samples:4 [match instances with
    | Some transforms -> Scene3.instances_array ~cull:Scene3.Cull_none ~material mesh transforms
    | None -> Scene3.mesh ~cull:Scene3.Cull_none ~material mesh]


let load ?(entry = "boolean") () =
  (* the scene shows (ref boolean); another entry is another ref *)
  let text = Gallery_source.text and marker = "(ref boolean)" in
  let text = if entry = "boolean" then text else
    let rec find i = if String.sub text i (String.length marker) = marker then i else find (i + 1) in
    let i = find 0 in
    String.sub text 0 i ^ "(ref " ^ entry ^ ")"
    ^ String.sub text (i + String.length marker) (String.length text - i - String.length marker) in
  match Prismel_editor.Workspace.load ~factories text with
  | Ok doc -> doc
  | Error ds -> List.iter (fun d -> prerr_endline (Flow.Diagnostic.report ~file:Gallery_source.path
      ~source:text d)) ds; exit 1

let graphs () = match Prismel_editor.Workspace.sop_graphs ~factories (load ()) with
  | Ok graphs -> graphs
  | Error message -> failwith message

let check_all () =
  let context = Context.create ~seed:2026L ~domains:1 () |> Result.get_ok in
  List.iter (fun (name, graph) ->
      let session = Session.create ~max_entries:24
          ~max_payload_bytes:134_217_728 |> Result.get_ok in
      Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
        match Session.cook session ~context graph with
        | Error error -> failwith (name ^ ": " ^
            Diagnostic.error_to_string error)
        | Ok output ->
            if Pdk.Geometry.point_count output.geometry = 0 then
              failwith (name ^ ": empty geometry");
            (match prepare output with
             | Ok (mesh, _) when Mesh.vertex_count mesh > 0 -> ()
             | Ok _ -> failwith (name ^ ": empty render mesh")
             | Error error -> failwith (name ^ ": " ^ error));
            Printf.printf "%s: %d points, %d primitives\n%!" name
              (Pdk.Geometry.point_count output.geometry)
              (Pdk.Geometry.primitive_count output.geometry))) (graphs ())

let () =
  let entry = ref "boolean" and list = ref false and check = ref false in
  Arg.parse ["--entry", Arg.Set_string entry, "Gallery entry";
             "--list", Arg.Set list, "List entries";
             "--check-all", Arg.Set check, "Cook every entry without a window"]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "sop_gallery [--list | --check-all | --entry NAME]";
  if !list then List.iter (fun (name, _) -> print_endline name) (graphs ())
  else if !check then check_all ()
  else begin
    if not (List.mem_assoc !entry (graphs ())) then failwith ("unknown gallery entry: " ^ !entry);
    Prismel_editor.Editor3.run
      ~config:{Sketch.default_config with width=1100; height=720;
        title="Prismel SOP gallery · " ^ !entry}
      ~name:"sop_gallery" ~factories
      ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:6.
        ~azimuth:0.6 ~elevation:0.35 ())
      ~seed:2026L ~max_entries:24 ~max_payload_bytes:134_217_728
      ~workspace:(load ~entry:!entry ()) ~prepare:(fun _ -> prepare) ~scene3 ()
  end
