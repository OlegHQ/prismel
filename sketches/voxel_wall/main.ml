(* Voxel wall: a Houdini-style SOP network (Grid -> Wall Depth -> Copy to
   Points with a cube prototype) in the Sketch UI workspace, rendered either
   by the Metal path tracer, filled raster, or wireframe (choose in the
   inspector's "Renderer" control while no node is selected). "copy-cubes"
   packs and instances: its cook is the cube plus one transform per target
   point ([Session.output.instances]), so topology is never multiplied; the
   rasterizer draws it with Scene3 instancing and the tracer with a Metal
   instance acceleration structure.
   Select a node to edit it; Command-Z / Shift-Command-Z undo and
   redo every edit. Orbit in the view pane with the mouse; Space opens the
   leader keys (Space w flies, Space s / Space b save and browse presets in
   ~/.rays/voxel_wall). The path tracer follows the view pane (the
   camera object through look-through) with the camera object's lens.
   RAYS_VOXEL_RENDERER=wireframe|raster selects a startup mode;
   RAYS_VOXEL_SWITCH=wireframe|raster switches to it halfway through a
   finite smoke, exercising the live renderer change.
   RAYS_PATHTRACER_FRAMES=N runs a finite smoke; RAYS_PATHTRACER_PNG=path
   saves the final window. *)
open Rays
open Procedural
module P = Rays_pathtracer
let rgb = P.Linear_color.rgb

let v = Vec3.create

(* Custom SOP: per-point [scale] = (1, 1, depth) from seeded fBm, which Copy
   Cubes applies to every cube. The typed schema drives the inspector. *)
type depth = { frequency : float; amplitude : float; base : float; octaves : int; seed : int }

let depth_schema =
  let open Parameter in
  let default = { frequency = 0.055; amplitude = 5.; base = 0.15; octaves = 3; seed = 7 } in
  schema ~name:"wall_depth" ~default
    [ field ~name:"frequency" ~label:"Noise frequency" ~kind:(floating ~min:0.01 ~max:0.5 ())
        ~default:default.frequency ~get:(fun r -> r.frequency)
        ~set:(fun frequency r -> { r with frequency }) ()
    ; field ~name:"amplitude" ~label:"Depth amplitude" ~kind:(floating ~min:0. ~max:8. ())
        ~default:default.amplitude ~get:(fun r -> r.amplitude)
        ~set:(fun amplitude r -> { r with amplitude }) ()
    ; field ~name:"base" ~label:"Base depth" ~kind:(floating ~min:0.05 ~max:3. ())
        ~default:default.base ~get:(fun r -> r.base) ~set:(fun base r -> { r with base }) ()
    ; field ~name:"octaves" ~label:"Octaves" ~kind:(integer ~min:1 ~max:6 ())
        ~default:default.octaves ~get:(fun r -> r.octaves)
        ~set:(fun octaves r -> { r with octaves }) ()
    ; field ~name:"seed" ~label:"Seed" ~kind:(integer ~min:0 ~max:9999 ())
        ~default:default.seed ~get:(fun r -> r.seed) ~set:(fun seed r -> { r with seed }) () ]

let scale_key = Rdk.Attribute.key ~name:"scale" ~owner:Rdk.Attribute.Point Rdk.Attribute.float3

let wall_depth grid =
  Custom.map ~label:"wall-depth" ~operation:"wall_depth" ~schema:depth_schema
    ~values:(Parameter.default depth_schema) grid
    (fun ~parameters ~context:_ geometry ->
      let noise = Noise.create parameters.seed in
      let points = Rdk.Geometry.positions geometry in
      let count = Rdk.Packed.Float3.length points in
      let scale = Rdk.Packed.Float3.Builder.create count in
      for index = 0 to count - 1 do
        let x, y, _ = Rdk.Packed.Float3.get points index in
        let h = Noise.fbm2 ~octaves:parameters.octaves noise
            ~x:(x *. parameters.frequency) ~y:(y *. parameters.frequency) in
        let h = Float.max 0. (Float.min 1. h) in
        Rdk.Packed.Float3.Builder.set scale index 1. 1.
          (parameters.base +. (parameters.amplitude *. h *. h))
      done;
      Result.bind
        (Rdk.Attribute.create_key_owned scale_key (Rdk.Packed.Float3.Builder.freeze scale))
        (fun attribute -> Rdk.Geometry.with_attribute attribute geometry))

let rdk_error result = Result.map_error Rdk.Error.to_string result

(* The sketch's own SOPs in the node menu, beside the catalog. *)
let factories =
  Edit_graph.factory ~key:"wall_depth" ~label:"Wall Depth" ~category:[ "Voxel wall" ]
    ~arity:1 (function [ grid ] -> wall_depth grid
      | _ -> invalid_arg "Wall Depth expects one input")
  :: Sop_catalog.Editor.factories

(* The document (network, studio lights, camera, World) is sketch.rays. *)

(* ---- preparation (cook worker, pure) ---- *)

let concrete = P.material ~roughness:0.6 ~round:0.07 (rgb 0.42 0.42 0.44)
let raster_material = Material.create ~diffuse:(Color.rgb 150 150 156)
    ~ambient:(Color.rgb 10 10 12) ~specular:(Color.rgb 40 40 40) ~shininess:24. ()
let background = Color.rgb 8 8 10
let wire_material = Material.unlit (Rays_editor.Renderer.wire_color background)

module Renderer = Rays_editor.Renderer
let initial_renderer = Option.value ~default:Renderer.Path_traced
    (Renderer.of_env "RAYS_VOXEL_RENDERER")
let switch_to = Renderer.of_env "RAYS_VOXEL_SWITCH"

type prepared = { mode : Renderer.t; traced : P.mesh option; raster : Scene3.node option;
  wire : Scene3.node option; triangles : int; instances : int }

let prepare mode (output : Session.output) =
  let packed = Option.map (fun transforms -> (Result.get_ok (Procedural.Payload.geometry output.payload)), transforms) output.instances in
  let geometry, instances = match packed with
    | Some (prototype, transforms) -> prototype, Array.length transforms
    | None -> (Result.get_ok (Procedural.Payload.geometry output.payload)), 0 in
  let topology = Rdk.Geometry.topology geometry in
  let triangles = ref 0 in
  for primitive = 0 to Rdk.Topology.primitive_count topology - 1 do
    triangles := !triangles + max 0 (Rdk.Topology.primitive_size topology primitive - 2)
  done;
  let triangles = !triangles * max 1 instances in
  let finish ?traced ?raster ?wire () =
    Ok { mode; traced; raster; wire; triangles; instances } in
  match mode with
  | Path_traced ->
      let geometry = match packed with
        | Some _ -> rdk_error (Rdk.Normal_ops.run ~owner:Rdk.Attribute.Vertex
            ~cusp_angle:(Float.pi /. 4.5) geometry)
        | None -> Ok geometry in
      Result.bind geometry (fun geometry ->
        let mesh = match packed with
          | Some (_, transforms) -> P.mesh_instanced ~prototype:(geometry, concrete) transforms
          | None -> P.mesh [ geometry, concrete ] in
        Result.bind mesh (fun traced -> finish ~traced ()))
  | Raster ->
      let geometry = match packed with
        | Some _ -> rdk_error (Rdk.Normal_ops.run ~owner:Rdk.Attribute.Vertex
            ~cusp_angle:(Float.pi /. 4.5) geometry)
        | None -> Ok geometry in
      Result.bind geometry (fun geometry ->
      Result.bind (rdk_error (Rdk_rays.Rays_mesh.to_mesh geometry)) (fun mesh ->
        let raster = match packed with
          | Some (_, transforms) -> Scene3.instances_array ~material:raster_material mesh transforms
          | None -> Scene3.mesh ~material:raster_material mesh in
        finish ~raster ()))
  | Wireframe ->
      Result.bind (Renderer.wire_mesh geometry) (fun mesh ->
        let wire = match packed with
          | Some (_, transforms) -> Scene3.instances_array ~material:wire_material
              ~cull:Scene3.Cull_none mesh transforms
          | None -> Scene3.mesh ~material:wire_material ~cull:Scene3.Cull_none mesh in
        finish ~wire ())

(* ---- sketch ---- *)

let env name default of_string = Option.value ~default (Option.bind (Sys.getenv_opt name) of_string)
let frames = env "RAYS_PATHTRACER_FRAMES" 0 int_of_string_opt
let orbit = Sys.getenv_opt "RAYS_PATHTRACER_ORBIT" = Some "1"
let started = Unix.gettimeofday ()
let image_size = (560, 800)

(* The renderer is a sketch setting: shown in the inspector while no node is
   selected, undoable, saved in presets, and handed to [prepare]. *)
module Settings = Rays_editor.Settings

let settings_schema =
  Parameter.schema ~name:"voxel_wall" ~default:initial_renderer
    [ Renderer.field ~default:initial_renderer ~get:Fun.id ~set:(fun renderer _ -> renderer) ]

let renderer env = Settings.get settings_schema (Rays_editor.Editor3.settings env)

(* What the tracer currently holds, compared physically so an idle frame
   uploads nothing. *)
type model = { env : prepared Rays_editor.Editor3.t; tracer : P.t;
  shown : (Mat4.t * prepared) list; lit : Light.t list; world : World.baked option }

let scene3 _graph prepared =
  match prepared.mode with
  | Path_traced -> Scene3.create []
  | Raster -> Scene3.create (Option.to_list prepared.raster)
  | Wireframe -> Scene3.create (Option.to_list prepared.wire)

(* Renderer stats go to the editor's status bar, not over the picture. *)
let status tracer = Option.map (fun p -> Printf.sprintf "%s%s · %d tris%s"
  (match p.mode with Path_traced -> "traced" | Raster -> "raster"
    | Wireframe -> "wire")
  (if p.mode = Path_traced then Printf.sprintf " %d spp" (P.samples tracer) else "")
  p.triangles
  (if p.instances > 0 then Printf.sprintf " · %d inst" p.instances else ""))

(* The traced film matches the editor's film rect (see [update]), so it
   fills the overlay frame. *)
let overlay tracer _graph prepared (frame : Frame.t) =
  match prepared with
    | Some { mode = Path_traced; _ } ->
        let iw, ih = P.size tracer in
        let fit = Float.min (float frame.width /. float iw) (float frame.height /. float ih) in
        let w = int_of_float (float iw *. fit) and h = int_of_float (float ih *. fit) in
        Scene.[ rect ~at:(0, 0) ~w:frame.width ~h:frame.height ~fill:(Color.rgb 8 8 10) ()
              ; image (P.image tracer) ~at:((frame.width - w) / 2, (frame.height - h) / 2) ~scale:fit () ]
    | _ -> []

let init _frame =
  let placeholder = Result.get_ok (Rdk.Box_generator.box ~size:(v 0.01 0.01 0.01) ()) in
  let w, h = image_size in
  let tracer =
    match P.create ~bounces:4 ~exposure:1. ~width:w ~height:h
      { P.objects = [ (placeholder, concrete) ]
      ; spheres = []; strands = []; environment = { sky = rgb 0.006 0.007 0.009; ground = rgb 0.002 0.002 0.003; panels = [] }
      ; lights =
          [ P.rect_light ~intensity:9. ~size:(24., 24.) ~target:(v 0. 0. 0.) (v (-34.) 40. 30.)
          ; P.rect_light ~intensity:1.2 ~size:(30., 30.) ~target:(v 0. 0. 0.) (v 30. (-10.) 26.) ] }
    with Ok tracer -> tracer | Error message -> failwith message in
  let env =
    let workspace, source = Rays_editor.Workspace.open_text ~factories ~path:Sketch_source.path
        ~digest:Sketch_source.digest Sketch_source.text in
    match Rays_editor.Editor3.create ~name:"voxel_wall"
      ~camera:(Easy_camera.create ~target:(v 0. 0. 1.) ~distance:19. ~azimuth:(-0.22)
        ~elevation:0.08 ~fov_y:0.7 ~inertia:false ())
      ~background ~seed:7L ~grain:2 ~max_entries:24
      ~max_payload_bytes:(256 * 1024 * 1024) ~factories
      ~settings:(Settings.make settings_schema initial_renderer)
      ~workspace ?source
      ~prepare:(fun settings -> prepare (Settings.get settings_schema settings))
      ~scene3 ~overlay:(overlay tracer) ~status:(status tracer) ()
    with Ok env -> env | Error message -> failwith message in
  { env; tracer; shown = []; lit = []; world = None }

let update m (frame : Frame.t) =
  let env = Rays_editor.Editor3.update m.env frame in
  let env = match switch_to with
    | Some target when frames > 0 && frame.count = frames / 2 ->
        Rays_editor.Editor3.set_settings env (Settings.make settings_schema target)
    | _ -> env in
  let renderer = renderer env in
  (* Every renderable object at its world transform in one scene_mesh; when
     only transforms changed, [P.move] rebuilds just the instance structure. *)
  let objects = Rays_editor.Editor3.objects env in
  let same_prepared = List.equal (fun (_, p) (_, q) -> p == q) objects m.shown in
  let same = same_prepared && List.equal (fun (m, _) (n, _) -> Mat4.nearly_equal m n ~eps:0.) objects m.shown in
  if not same then begin
    let traced = List.filter_map (fun (matrix, p) ->
        Option.map (fun mesh -> matrix, mesh) p.traced) objects in
    let rebuild () = match Result.bind (P.scene_mesh traced) (P.queue_mesh m.tracer) with
      | Ok () -> () | Error e -> prerr_endline e in
    if traced <> [] then
      if same_prepared then (match P.move m.tracer (List.map fst traced) with
        | Ok () -> () | Error _ -> rebuild ())
      else rebuild ()
  end;
  let lit = Rays_editor.Editor3.lights env in
  if lit <> m.lit then (match P.set_lights m.tracer (List.map P.light_of lit) with
    | Ok () -> () | Error e -> prerr_endline e);
  let world = Rays_editor.Editor3.world env in
  if world != m.world then (match P.set_world m.tracer world with
    | Ok () -> () | Error e -> prerr_endline e);
  let m = { m with shown = objects; lit; world } in
  (* The trace follows the view pane (the camera object through
     look-through) with the camera object's lens. *)
  if renderer = Path_traced then begin
    let _, _, width, height = Rays_editor.Editor3.film env frame in
    (match P.resize m.tracer ~width:(max 1 width) ~height:(max 1 height) with
     | Ok () -> () | Error e -> prerr_endline e);
    let camera = Rays_editor.Editor3.view_camera env in
    let camera = if not orbit then camera else
      let target = Camera.target camera in
      let angle = 0.5 *. sin (float frame.count *. 0.05) in
      Camera.with_position (v (target.x +. 19. *. sin angle) (target.y +. 1.5)
        (target.z +. 19. *. cos angle)) camera in
    match P.render m.tracer camera with Ok () -> () | Error e -> prerr_endline e
  end;
  if frames > 0 && frame.count + 1 >= frames then begin
    Option.iter (fun path ->
      match Canvas.save_screen_png path with
      | Ok () -> Printf.printf "saved %s\n%!" path
      | Error e -> prerr_endline e) (Sys.getenv_opt "RAYS_PATHTRACER_PNG");
    Printf.printf "%d frames  %d spp  %.1f ms/frame\n%!" frames (P.samples m.tracer)
      ((Unix.gettimeofday () -. started) *. 1000. /. float frames);
    Sketch.quit ()
  end;
  { m with env }

let view m (frame : Frame.t) = Rays_editor.Editor3.scene m.env frame

let () =
  if Array.exists (( = ) "--approx") Sys.argv then begin
    let document = Rays_editor.Workspace.load ~factories Sketch_source.text |> Result.get_ok in
    Workspace_parity.report_approx ~name:"sketches/voxel_wall/sketch.rays" document;
    exit 0
  end else if Array.exists (( = ) "--check-workspace") Sys.argv then begin
    let document = match Rays_editor.Workspace.load ~factories Sketch_source.text with
      | Ok document -> document
      | Error diagnostics ->
          List.iter (fun diagnostic -> prerr_endline
            (Flow.Diagnostic.report ~file:Sketch_source.path
              ~source:Sketch_source.text diagnostic)) diagnostics;
          exit 1 in
    Workspace_parity.check ?directory:(Sys.getenv_opt "RAYS_WORKSPACE_PIXELS") ~factories
      ~name:"sketches/voxel_wall/sketch.rays" document;
    let graphs = match Rays_editor.Workspace.sop_graphs ~factories document with
      | Ok graphs -> graphs
      | Error message -> failwith message in
    if graphs = [] then failwith "voxel_wall: no SOP graphs";
    let context = Context.create ~seed:7L ~domains:1 () |> Result.get_ok in
    let session = Session.create ~max_entries:24
        ~max_payload_bytes:(256 * 1024 * 1024) |> Result.get_ok in
    Fun.protect ~finally:(fun () -> Session.close session) (fun () ->
      List.iter (fun (name, graph) ->
        match Session.cook session ~context graph with
        | Error error -> failwith (name ^ ": " ^ Diagnostic.error_to_string error)
        | Ok output ->
            if Rdk.Geometry.point_count (Result.get_ok (Procedural.Payload.geometry output.payload)) = 0 then
              failwith (name ^ ": empty geometry");
            Printf.printf "%s: %d points, %d instances\n%!" name
              (Rdk.Geometry.point_count (Result.get_ok (Procedural.Payload.geometry output.payload)))
              (Option.fold ~none:0 ~some:Array.length output.instances)) graphs);
    exit 0
  end;
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 1280; height = 820; title = "Rays voxel wall"
            ; domains = Some 1 }
    ~init ~update ~view
    ~after_present:(fun m frame ->
      { m with env = Rays_editor.Editor3.after_present m.env frame })
    ~crash_dump:(fun m -> Rays_editor.Editor3.crash_dump m.env)
    ~on_stop:(fun m -> Rays_editor.Editor3.close m.env; P.destroy m.tracer) ())
