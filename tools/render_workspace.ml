(* A finite native beauty render of a workspace's authored scene and camera. *)
open Rays
open Sop
open Editor_document
module P = Rays_pathtracer

let get = function Ok value -> value | Error message -> failwith message
let () = if Array.length Sys.argv < 3 || Array.length Sys.argv > 5 then
  failwith "usage: render_workspace FILE.rays OUTPUT.png [SPP [SIZE]]"
let path = Sys.argv.(1)
let output = Sys.argv.(2)
let text = In_channel.with_open_bin path In_channel.input_all
let imports = match Rays_editor.Source.read_imports ~file:path text with
  | Ok imports -> imports | Error ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds))
let workspace = match Rays_editor.Workspace.load ~imports text with
  | Ok w -> w | Error ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds))
let document = Contexts.of_workspace ~factories:Sop_catalog.Editor.factories workspace
  |> Result.map_error Flow.Diagnostic.to_string |> get
let scene = document.scene.graph.geometry
let camera_node = match Objects.ids "camera" scene with
  | [] -> prerr_endline (path ^ ": the scene has no camera to render through (add a scene/camera)"); exit 1
  | id :: _ -> Edit_graph.find scene ~node_id:id |> Option.get
let camera = Objects.Camera.of_node camera_node |> Option.get |> fst
let settings = Objects.Root.render document.root
let spp = if Array.length Sys.argv > 3 then int_of_string Sys.argv.(3) else settings.max_spp
let width, height = if Array.length Sys.argv > 4 then
    let size = int_of_string Sys.argv.(4) in size, size else settings.width, settings.height
let () = if spp < 1 || width < 1 || height < 1 then failwith "positive SPP and dimensions required"
let linear (c : Color.t) = P.Linear_color.rgb (float c.r /. 255.) (float c.g /. 255.) (float c.b /. 255.)
let material (m : Material.t) = P.material
  ~roughness:(sqrt (2. /. (m.shininess +. 2.))) ~emission:(linear m.emissive) (linear m.diffuse)

type model = { tracer : P.t; canvas : Canvas.t }

let init _ =
  let session = Session.create ~max_entries:64 ~max_payload_bytes:(256 * 1024 * 1024) |> get in
  let placed = ref [] and first = ref None in
  Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
    List.iter (fun id ->
      let object_node = Edit_graph.find scene ~node_id:id |> Option.get in
      if Objects.visible object_node && Objects.flag "render" object_node then begin
        let network = Document.Int_map.find id document.networks in
        let resolved = Flow_sop.Value_lane.resolve (Flow_sop.Value_lane.create ())
            ~time:0. network.graph |> Result.map_error Flow.Diagnostic.to_string |> get in
        let node = Edit_graph.compile_node resolved.geometry
            ~node_id:(Option.get network.displayed) |> get in
        let cooked = Session.cook session ~context:(Context.create ~domains:1 ~grain:2 () |> get) node
            |> Result.map_error Diagnostic.error_to_string |> get in
        Printf.printf "%s: %d primitives, %d points\n%!" (Node.label object_node)
          (Rdk.Geometry.primitive_count (Result.get_ok (Sop.Payload.geometry cooked.payload))) (Rdk.Geometry.point_count (Result.get_ok (Sop.Payload.geometry cooked.payload)));
        let surface = Rays_editor.Surface.of_output cooked |> get in
        let drawing = Rays_editor.Surface.scene3 node surface in
        Scene3.Private.iter_batches (fun (d : Scene3.Private.drawing) transforms ->
          let geometry = Rdk_rays.Rays_mesh.of_mesh d.mesh
              |> Result.map_error Rdk.Error.to_string |> get in
          let material = material d.material in
          if !first = None then first := Some (geometry, material);
          let mesh = match transforms with
            | None -> P.mesh [geometry, material] |> get
            | Some transforms -> P.mesh_instanced ~prototype:(geometry, material) transforms |> get in
          placed := (Mat4.mul (Objects.world scene id) d.transform, mesh) :: !placed) drawing
      end) (Objects.ids "geometry" scene));
  let mesh = P.scene_mesh (List.rev !placed) |> get in
  let tracer = P.create ~spp:4 ~bounces:6 ~width ~height
      {P.objects = [Option.get !first]; spheres = []; strands = [];
       environment = {sky = P.Linear_color.rgb 0.22 0.24 0.25;
         ground = P.Linear_color.rgb 0.12 0.13 0.14; panels = []};
       lights = List.map P.light_of (Objects.lights ~render:true scene)} |> get in
  P.replace_mesh tracer mesh |> get;
  List.iter (fun id ->
    let node = Edit_graph.find scene ~node_id:id |> Option.get in
    match Document.Int_map.find_opt id document.networks with
    | None -> ()
    | Some network -> Option.iter (fun world ->
        P.set_world tracer (Some (World.bake ~domains:1 ~width:512 ~height:256 world)) |> get)
        (Layers.to_world node network)) (Objects.ids "world" scene);
  P.reset tracer;
  {tracer; canvas = Canvas.create_exn ~width ~height}

let () =
  let model = init () in
  Fun.protect ~finally:(fun () -> Canvas.destroy model.canvas; P.destroy model.tracer) (fun () ->
    while P.samples model.tracer < spp do
      P.render model.tracer camera |> get;
      P.flush model.tracer |> get
    done;
    Canvas.render model.canvas [Scene.image (P.image model.tracer) ~at:(0,0) ()];
    Canvas.save_png model.canvas output |> get;
    Printf.printf "Saved %s (%dx%d, %d spp)\n%!" output width height (P.samples model.tracer))
