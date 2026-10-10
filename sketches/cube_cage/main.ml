(* Cube cage: a lattice of hollow cube frames, path traced with round corners
   and thin-lens depth of field, in the Rays Editor workspace. The SOP
   network is catalog-only: a unit Box minus three merged bars (one Boolean
   difference resolving the cutter's self-intersections, polygon output) is
   the cage, Poly Bevel chamfers its edges, and a Merge adds a small
   octahedron inside. A point Grid duplicated along Y is the coarse
   lattice; per level, Group Random picks the cells that split, Blast +
   Attribute Randomize keep the rest with a pscale, and an unpacked Copy to
   Points of a 2x2x2 octant cloud onto the split cells is the next, half-pitch
   level (three levels: an octree). Merge joins the levels, Group Random +
   Blast punch holes, and Copy to Points (packed) instances the cell once per
   remaining point. Point-cloud nodes preview as unlit markers. Dark cells
   are chosen by a seeded hash of each cell's centre, because packed
   instances carry transforms only.
   The camera object carries depth of field (Aperture, Focus distance; with
   W, drag the yellow handle to slide the target along the view direction)
   and the render settings (resolution, max samples). The trace fills
   [Editor.film]: the whole pane while orbiting freely, the camera's aspect
   while looking through it; accumulation stops at max samples. "Render /
   save PNG" renders the camera at its resolution progressively, with the
   status bar counting samples, then saves the PNG.
   The empty-selection inspector holds the sketch settings: the renderer
   (path traced, raster, wireframe), the bounding frame, dark-cell fraction
   and seed. Space opens the leader keys.
   RAYS_CAGE_RENDERER=path|raster|wireframe picks the startup renderer;
   RAYS_PATHTRACER_FRAMES=N runs a finite smoke; RAYS_PATHTRACER_PNG=path
   saves the final window; RAYS_CAGE_EXPORT=path renders the camera
   halfway through a finite smoke. *)
open Rays
open Sop
module P = Rays_pathtracer
module Editor = Rays_editor.Editor
module Renderer = Rays_editor.Renderer
module Settings = Rays_editor.Settings
let rgb = P.Linear_color.rgb
let v = Vec3.create

(* The document (network, studio lights, camera, World) is sketch.rays. *)
let cells = 6
let pitch = 1.16
let extent = pitch *. float (cells - 1)

(* ---- settings (inspector, undo, presets) ---- *)

type settings = { renderer : Renderer.t; frame : bool; dark : float; seed : int }

let settings_schema =
  let open Parameter in
  let default = { renderer = Option.value ~default:Renderer.Path_traced (Renderer.of_env "RAYS_CAGE_RENDERER")
                ; frame = false; dark = 0.3; seed = 7 } in
  schema ~name:"cube_cage" ~default
    [ Renderer.field ~default:default.renderer ~get:(fun s -> s.renderer)
        ~set:(fun renderer s -> { s with renderer })
    ; field ~name:"frame" ~label:"Bounding frame" ~kind:Toggle
        ~default:default.frame ~get:(fun s -> s.frame) ~set:(fun frame s -> { s with frame }) ()
    ; field ~name:"dark" ~label:"Dark cells" ~kind:(floating ~min:0. ~max:1. ())
        ~default:default.dark ~get:(fun s -> s.dark) ~set:(fun dark s -> { s with dark }) ()
    ; field ~name:"seed" ~label:"Dark seed" ~kind:(integer ~min:0 ~max:9999 ())
        ~default:default.seed ~get:(fun s -> s.seed) ~set:(fun seed s -> { s with seed }) () ]

let settings env = Settings.get settings_schema (Editor.settings env)

(* ---- preparation (cook worker, pure) ---- *)

let white = P.material ~roughness:0.55 ~round:0.02 (rgb 0.82 0.82 0.8)
let black = P.material ~roughness:0.45 ~round:0.02 (rgb 0.012 0.012 0.013)
let raster_white = Material.create ~diffuse:(Color.rgb 210 210 205) ~ambient:(Color.rgb 12 12 12)
    ~specular:(Color.rgb 50 50 50) ~shininess:24. ()
let background = Color.rgb 6 6 7
let wire_material = Material.unlit (Renderer.wire_color background)
let point_material = Material.unlit (Color.rgb 251 191 116)

type prepared = { mode : Renderer.t; traced : P.mesh option; raster : Scene3.node option;
                  wire : Scene3.node option; triangles : int; instances : int }

(* ponytail: dark cells hash the cell centre (stable under hole edits)
   instead of a point attribute, which packed instances do not carry. The
   finest level sits on eighths of the pitch. *)
let dark_cell seed matrix =
  let c = Mat4.transform_point matrix Vec3.zero in
  let cell f = int_of_float (Float.round (f *. 8. /. pitch)) + 512 in
  let h = (cell c.x * 73856093) lxor (cell c.y * 19349663) lxor (cell c.z * 83492791) lxor (seed * 2654435761) in
  let h = ((h lxor (h lsr 16)) * 0x45d9f3b) land 0x3fffffff in
  float ((h lxor (h lsr 15)) land 0xffff) /. 65536.

let rdk_error result = Result.map_error Rdk.Error.to_string result

(* A point cloud (any node before Copy to Points) draws as unlit markers in
   both preview renderers; a surface draws lit, or as its unlit edges. *)
let points_node mesh transforms =
  Scene3.instances_array ~material:point_material ~cull:Scene3.Cull_none mesh transforms

let prepare settings (output : Session.output) =
  let s = Settings.get settings_schema settings in
  let geometry = (Result.get_ok (Sop.Payload.geometry output.payload)) in
  let transforms = Option.value ~default:[| Mat4.identity |] output.instances in
  let topology = Rdk.Geometry.topology geometry in
  let triangles = ref 0 in
  for primitive = 0 to Rdk.Topology.primitive_count topology - 1 do
    triangles := !triangles + max 0 (Rdk.Topology.primitive_size topology primitive - 2)
  done;
  let instances = Array.length transforms in
  let finish ?traced ?raster ?wire () =
    Ok { mode = s.renderer; traced; raster; wire; triangles = !triangles * instances; instances } in
  let smooth () = rdk_error (Rdk.Normal_ops.run ~owner:Rdk.Attribute.Vertex
      ~cusp_angle:(Float.pi /. 4.5) geometry) in
  let points_only = Rdk.Topology.primitive_count topology = 0 in
  match s.renderer with
  | Path_traced ->
      let materials = Array.map (fun m -> if dark_cell s.seed m < s.dark then black else white) transforms in
      Result.bind (smooth ()) (fun geometry ->
        Result.bind (P.mesh_instanced ~prototype:(geometry, white) ~materials transforms)
          (fun traced -> finish ~traced ()))
  | Raster when points_only ->
      Result.bind (rdk_error (Rdk_rays.Rays_mesh.to_mesh geometry)) (fun mesh ->
        finish ~raster:(points_node mesh transforms) ())
  | Raster ->
      Result.bind (smooth ()) (fun geometry ->
        Result.bind (rdk_error (Rdk_rays.Rays_mesh.to_mesh geometry)) (fun mesh ->
          finish ~raster:(Scene3.instances_array ~material:raster_white mesh transforms) ()))
  | Wireframe when points_only ->
      Result.bind (rdk_error (Rdk_rays.Rays_mesh.to_mesh geometry)) (fun mesh ->
        finish ~wire:(points_node mesh transforms) ())
  | Wireframe ->
      Result.bind (Renderer.wire_mesh geometry) (fun mesh ->
        finish ~wire:(Scene3.instances_array ~material:wire_material ~cull:Scene3.Cull_none mesh transforms) ())

(* ---- sketch ---- *)

let env name default of_string = Option.value ~default (Option.bind (Sys.getenv_opt name) of_string)
let frames = env "RAYS_PATHTRACER_FRAMES" 0 int_of_string_opt
let smoke_export = Sys.getenv_opt "RAYS_CAGE_EXPORT"
let started = Unix.gettimeofday ()

(* A progressive export: its own tracer at the camera's resolution, a few
   samples per frame until max samples, then the PNG. *)
type export = { film : P.t; camera : Camera.t; path : string; max_spp : int }

type model = { env : prepared Editor.t; tracer : P.t;
  shown : (Mat4.t * prepared) list; lit : Light.t list; world : World.baked option;
  traced_camera : Camera.t option;  (* physically the last view camera traced *)
  export : export option }

let status tracer = Option.map (fun p -> Printf.sprintf "%s · %d tris · %d cells"
  (match p.mode with
   | Path_traced -> Printf.sprintf "traced %d spp" (P.samples tracer)
   | Raster -> "raster" | Wireframe -> "wire") p.triangles p.instances)

let scene3 _graph prepared = match prepared.mode with
  | Path_traced -> Scene3.create []
  | Raster -> Scene3.create (Option.to_list prepared.raster)
  | Wireframe -> Scene3.create (Option.to_list prepared.wire)

(* Drawn in the film rect (the editor sizes the frame to it; the tracer is
   resized to match). *)
let overlay tracer _graph prepared (frame : Frame.t) = match prepared with
  | Some { mode = Path_traced; _ } ->
      Scene.[ rect ~at:(0, 0) ~w:frame.width ~h:frame.height ~fill:background ()
            ; image (P.image tracer) ~at:(0, 0) () ]
  | _ -> []

let empty_scene =
  let placeholder = Result.get_ok (Rdk.Box_generator.box ~size:(v 0.01 0.01 0.01) ()) in
  { P.objects = [ (placeholder, white) ]; spheres = []; strands = []
  ; environment = { sky = rgb 0.003 0.003 0.004; ground = rgb 0.003 0.003 0.004; panels = [] }
  ; lights = [] }

let init _frame =
  let tracer =
    match P.create ~bounces:4 ~exposure:1. ~width:64 ~height:64 empty_scene
    with Ok tracer -> tracer | Error message -> failwith message in
  let env =
    let workspace, source = Rays_editor.Workspace.open_text ~path:Sketch_source.path
        ~digest:Sketch_source.digest Sketch_source.text in
    match Editor.create ~name:"cube_cage"
      ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:30. ~azimuth:0.7
        ~elevation:0.5 ~fov_y:0.5 ~inertia:false ())
      ~background ~seed:7L ~grain:2 ~max_entries:24 ~max_payload_bytes:(256 * 1024 * 1024)
      ~settings:(Settings.make settings_schema (Parameter.default settings_schema))
      ~workspace ?source ~prepare ~scene3 ~status:(status tracer) ~overlay:(overlay tracer) ()
    with Ok env -> env | Error message -> failwith message in
  { env; tracer; shown = []; lit = []; world = None; traced_camera = None; export = None }

let report = function Ok () -> () | Error e -> prerr_endline e

let ( let* ) = Result.bind

(* Start an export: a tracer at the camera's resolution over the same scene. *)
let begin_export env ~traced ~lit ~world path =
  let { Editor.width; height; max_spp } = Editor.render_settings env in
  let* film = P.create ~spp:4 ~bounces:6 ~exposure:1. ~width ~height empty_scene in
  let* mesh = P.scene_mesh traced in
  let* () = P.replace_mesh film mesh in
  let* () = P.set_lights film (List.map P.light_of lit) in
  let* () = P.set_world film world in
  Ok { film; camera = Editor.render_camera env; path; max_spp }

(* One step: a few more samples, or the finished PNG. *)
let step_export export =
  let* () = P.render export.film export.camera in
  let* () = P.flush export.film in
  let samples = P.samples export.film in
  if samples < export.max_spp then
    Ok (Some export, Printf.sprintf "Rendering %s · %d/%d spp" export.path samples export.max_spp)
  else begin
    let width, height = P.size export.film in
    (try Sys.mkdir (Filename.dirname export.path) 0o755 with Sys_error _ -> ());
    let* canvas = Canvas.create ~width ~height in
    Canvas.render canvas [ Scene.image (P.image export.film) ~at:(0, 0) () ];
    let saved = Canvas.save_png canvas export.path in
    Canvas.destroy canvas;
    P.destroy export.film;
    let* () = saved in
    Ok (None, Printf.sprintf "Saved %s (%dx%d, %d spp)" export.path width height samples)
  end

let update m (frame : Frame.t) =
  let env = Editor.update m.env frame in
  let objects = Editor.objects env in
  let path_traced = (settings env).renderer = Path_traced in
  (* A "Render / save PNG" request is ours while path tracing. *)
  let env, requested = if path_traced then Editor.take_export env else env, None in
  let requested = match smoke_export with
    | Some path when frames > 0 && frame.count = frames / 2 && path_traced -> Some path
    | _ -> requested in
  let same_prepared = List.equal (fun (_, p) (_, q) -> p == q) objects m.shown in
  let same = same_prepared && List.equal (fun (a, _) (b, _) -> Mat4.nearly_equal a b ~eps:0.) objects m.shown in
  let traced = List.filter_map (fun (matrix, p) -> Option.map (fun mesh -> matrix, mesh) p.traced) objects in
  if not same && traced <> [] then begin
    let rebuild () = report (Result.bind (P.scene_mesh traced) (P.queue_mesh m.tracer)) in
    if same_prepared then (match P.move m.tracer (List.map fst traced) with Ok () -> () | Error _ -> rebuild ())
    else rebuild ()
  end;
  let lit = Editor.lights env in
  if lit <> m.lit then report (P.set_lights m.tracer (List.map P.light_of lit));
  let world = Editor.world env in
  if world != m.world then report (P.set_world m.tracer world);
  let traced_camera = if not path_traced then m.traced_camera else begin
    let _, _, width, height = Editor.film env frame in
    report (P.resize m.tracer ~width:(max 1 width) ~height:(max 1 height));
    (* What the view pane shows: the viewport orbit, or the camera object
       through look-through; either way with the camera object's lens. A
       resting camera stops at the camera's max samples. *)
    let camera = Editor.view_camera env in
    let resting = match m.traced_camera with Some previous -> previous == camera | None -> false in
    if not resting || P.samples m.tracer < (Editor.render_settings env).max_spp then
      report (P.render m.tracer camera);
    Some camera
  end in
  let export, env = match m.export, requested with
    | Some export, _ ->
        (match step_export export with
         | Ok (export, status) -> export, Editor.set_render_status env (Some status)
         | Error e -> P.destroy export.film; None, Editor.set_render_status env (Some ("Render failed: " ^ e)))
    | None, Some path when traced <> [] ->
        (match begin_export env ~traced ~lit ~world path with
         | Ok export -> Some export, Editor.set_render_status env (Some ("Rendering " ^ path))
         | Error e -> None, Editor.set_render_status env (Some ("Render failed: " ^ e)))
    | None, Some _ -> None, Editor.set_render_status env (Some "Render unavailable until the first cook completes")
    | None, None -> None, env in
  if frames > 0 && frame.count + 1 >= frames then begin
    Option.iter (fun path -> match Canvas.save_screen_png path with
      | Ok () -> Printf.printf "saved %s\n%!" path | Error e -> prerr_endline e)
      (Sys.getenv_opt "RAYS_PATHTRACER_PNG");
    Printf.printf "%d frames  %d spp  %.1f ms/frame\n%!" frames (P.samples m.tracer)
      ((Unix.gettimeofday () -. started) *. 1000. /. float frames);
    Sketch.quit ()
  end;
  { m with env; shown = objects; lit; world; traced_camera; export }

(* The thin bounding cube of the reference picture, drawn over the view:
   twelve edges projected through the view camera into the film rect. *)
let frame_lines env (frame : Frame.t) =
  let px, py, _, _ = (Editor.panes env frame).view in
  let fx, fy, w, h = Editor.film env frame in
  let x = px + fx and y = py + fy in
  if w <= 0 || h <= 0 || not (settings env).frame then [] else
  let camera = Editor.view_camera env in
  let half = (extent +. 1.) /. 2. +. 0.35 in
  let corner i = v (if i land 1 = 0 then -. half else half)
      (if i land 2 = 0 then -. half else half) (if i land 4 = 0 then -. half else half) in
  let project p = Option.map (fun (s : Vec3.t) -> x + int_of_float s.x, y + int_of_float s.y)
      (Camera.world_to_screen ~viewport:(0, 0, w, h) camera p) in
  let lines = List.concat_map (fun i -> List.filter_map (fun bit ->
      if i land bit <> 0 then None else
      match project (corner i), project (corner (i lor bit)) with
      | Some from_, Some to_ -> Some (Scene.line ~from_ ~to_ ~color:(Color.rgb 120 120 124) ())
      | _ -> None) [ 1; 2; 4 ]) [ 0; 1; 2; 3; 4; 5; 6; 7 ] in
  [ Scene.clip ~at:(x, y) ~w ~h lines ]

let view m (frame : Frame.t) = Editor.scene m.env frame @ frame_lines m.env frame

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 1280; height = 860; title = "Rays cube cage"
            ; domains = Some 1 }
    ~init ~update ~view
    ~after_present:(fun m frame -> { m with env = Editor.after_present m.env frame })
    ~crash_dump:(fun m -> Editor.crash_dump m.env)
    ~on_stop:(fun m ->
      Option.iter (fun export -> P.destroy export.film) m.export;
      Editor.close m.env; P.destroy m.tracer) ())
