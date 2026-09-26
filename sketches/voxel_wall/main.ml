(* Voxel wall: a Houdini-style SOP network (Grid -> Wall Depth -> Copy Cubes
   with a cube prototype) in the Sketch UI workspace, rendered either by the
   Metal path tracer, filled raster, or wireframe (choose in the inspector's
   "Renderer" control while no node is selected). "copy-cubes" packs and
   instances by default: its cook is the prototype plus one loose point per
   copy, so topology is never multiplied; the rasterizer draws it with
   Scene3 instancing and a Metal instance acceleration structure for tracing.
   Select a node to edit it; Command-Z / Shift-Command-Z undo and
   redo every edit. Orbit in the view pane with the mouse; Space opens the
   leader keys (Space w flies, Space s / Space b save and browse presets in
   ~/.prismel/voxel_wall). The ACTIVE camera node drives the path tracer.
   PRISMEL_VOXEL_RENDERER=wireframe|raster selects a startup mode;
   PRISMEL_VOXEL_SWITCH=wireframe|raster switches to it halfway through a
   finite smoke, exercising the live renderer change.
   PRISMEL_PATHTRACER_FRAMES=N runs a finite smoke; PRISMEL_PATHTRACER_PNG=path
   saves the final window. *)
open Prismel
open Procedural
module P = Prismel_pathtracer
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

let scale_key = Pdk.Attribute.key ~name:"scale" ~owner:Pdk.Attribute.Point Pdk.Attribute.float3

let wall_depth grid =
  Custom.map ~label:"wall-depth" ~operation:"wall_depth" ~schema:depth_schema
    ~values:(Parameter.default depth_schema) grid
    (fun ~parameters ~context:_ geometry ->
      let noise = Noise.create parameters.seed in
      let points = Pdk.Geometry.positions geometry in
      let count = Pdk.Packed.Float3.length points in
      let scale = Pdk.Packed.Float3.Builder.create count in
      for index = 0 to count - 1 do
        let x, y, _ = Pdk.Packed.Float3.get points index in
        let h = Noise.fbm2 ~octaves:parameters.octaves noise
            ~x:(x *. parameters.frequency) ~y:(y *. parameters.frequency) in
        let h = Float.max 0. (Float.min 1. h) in
        Pdk.Packed.Float3.Builder.set scale index 1. 1.
          (parameters.base +. (parameters.amplitude *. h *. h))
      done;
      Result.bind
        (Pdk.Attribute.create_key_owned scale_key (Pdk.Packed.Float3.Builder.freeze scale))
        (fun attribute -> Pdk.Geometry.with_attribute attribute geometry))

(* Copy Cubes: Houdini's Copy to Points with "Pack and Instance". Packed
   output is the prototype's polygons followed by one loose point per target
   carrying its [scale]; renderers read that as prototype + instance
   transforms. Materialized output expands every copy through PDK. *)
type copy = { pack : bool }

let copy_schema =
  Parameter.schema ~name:"copy_cubes" ~default:{ pack = true }
    [ Parameter.field ~name:"pack" ~label:"Pack and instance"
        ~kind:(Parameter.choice ~equal:( = ) [ "Instances", true; "Materialize", false ])
        ~default:true ~get:(fun r -> r.pack) ~set:(fun pack _ -> { pack }) () ]

let pdk_error result = Result.map_error Pdk.Error.to_string result

let copy_cubes ~source ~targets =
  Custom.create ~label:"copy-cubes" ~operation:"copy_cubes" ~schema:copy_schema
    ~values:(Parameter.default copy_schema) [ source; targets ]
    (fun ~parameters ~context:_ inputs ->
      let source = inputs.(0) and targets = inputs.(1) in
      if not parameters.pack then pdk_error (Pdk.Instance_copy.copy_to_points ~source ~targets ())
      else
        let proto_points = Pdk.Geometry.positions source and target_points = Pdk.Geometry.positions targets in
        let np = Pdk.Packed.Float3.length proto_points and nt = Pdk.Packed.Float3.length target_points in
        let topology = Pdk.Geometry.topology source in
        let builder = Pdk.Topology.Builder.create ~point_count:(np + nt) () in
        for primitive = 0 to Pdk.Topology.primitive_count topology - 1 do
          let polygon = Array.make (Pdk.Topology.primitive_size topology primitive) 0 in
          Pdk.Topology.iter_primitive_vertices topology primitive (fun vertex point ->
            let first, _ = Pdk.Topology.primitive_vertex_range topology primitive in
            polygon.(vertex - first) <- point);
          Pdk.Topology.Builder.add_polygon builder polygon
        done;
        let positions = Pdk.Packed.Float3.Builder.create (np + nt)
        and scale = Pdk.Packed.Float3.Builder.create (np + nt) in
        let target_scale = Option.bind
            (Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "scale" targets)
            (Pdk.Attribute.get scale_key) in
        for index = 0 to np - 1 do
          let x, y, z = Pdk.Packed.Float3.get proto_points index in
          Pdk.Packed.Float3.Builder.set positions index x y z;
          Pdk.Packed.Float3.Builder.set scale index 1. 1. 1.
        done;
        for index = 0 to nt - 1 do
          let x, y, z = Pdk.Packed.Float3.get target_points index in
          Pdk.Packed.Float3.Builder.set positions (np + index) x y z;
          let sx, sy, sz = match target_scale with
            | Some field -> Pdk.Packed.Float3.get field index | None -> 1., 1., 1. in
          Pdk.Packed.Float3.Builder.set scale (np + index) sx sy sz
        done;
        Result.bind
          (Pdk.Attribute.create_key_owned scale_key (Pdk.Packed.Float3.Builder.freeze scale))
          (fun attribute ->
            Pdk.Geometry.create ~positions:(Pdk.Packed.Float3.Builder.freeze positions)
              ~topology:(Pdk.Topology.Builder.freeze builder) ~attributes:[ attribute ] ()))

let graph () =
  let grid = Sop_catalog.Grid.create ~label:"wall-grid" ~orientation:Pdk.Plane_generators.Grid_xy
      ~columns:35 ~rows:59 ~width:35. ~height:59. ~size:35. () in
  let cube = Sop_catalog.Box.create ~label:"cube" ~size:(v 0.86 0.86 1.) ~center:(v 0. 0. 0.5) () in
  copy_cubes ~source:cube ~targets:(wall_depth grid)

(* ---- preparation (cook worker, pure) ---- *)

let concrete = P.material ~roughness:0.6 ~round:0.07 (rgb 0.42 0.42 0.44)
let raster_material = Material.create ~diffuse:(Color.rgb 150 150 156)
    ~ambient:(Color.rgb 10 10 12) ~specular:(Color.rgb 40 40 40) ~shininess:24. ()
let wire_material = Material.unlit (Color.rgb 190 215 225)

type renderer = Path_traced | Raster | Wireframe
let initial_renderer = match Sys.getenv_opt "PRISMEL_VOXEL_RENDERER" with
  | Some "raster" -> Raster | Some "wireframe" -> Wireframe
  | _ -> Path_traced
let switch_to = match Sys.getenv_opt "PRISMEL_VOXEL_SWITCH" with
  | Some "raster" -> Some Raster | Some "wireframe" -> Some Wireframe
  | Some "path" -> Some Path_traced | _ -> None

type prepared = { mode : renderer; traced : P.mesh option; raster : Scene3.node option;
  wire : Scene3.node option; triangles : int; instances : int }

let wire_mesh geometry =
  let topology = Pdk.Geometry.topology geometry in
  let edges = Pdk.Topology_index.create topology in
  let points = Pdk.Geometry.positions geometry in
  let vertices = Array.init (Pdk.Packed.Float3.length points) (fun index ->
    let x, y, z = Pdk.Packed.Float3.get points index in v x y z) in
  let indices = Array.make (Pdk.Topology_index.edge_count edges * 2) 0 in
  for edge = 0 to Pdk.Topology_index.edge_count edges - 1 do
    let a, b = Pdk.Topology_index.edge_points edges edge in
    indices.(edge * 2) <- a; indices.(edge * 2 + 1) <- b
  done;
  Mesh.Private.create_owned ~mode:Mesh.Lines ~indices vertices

(* Splits packed output back into prototype and instance transforms. Points
   referenced by a primitive form the prototype; the rest are copies. *)
let split_packed geometry =
  let topology = Pdk.Geometry.topology geometry and points = Pdk.Geometry.positions geometry in
  let count = Pdk.Packed.Float3.length points in
  let referenced = ref 0 in
  for primitive = 0 to Pdk.Topology.primitive_count topology - 1 do
    Pdk.Topology.iter_primitive_vertices topology primitive (fun _ point ->
      referenced := max !referenced (point + 1))
  done;
  let np = !referenced in
  if np = 0 || np = count then None
  else
    let scale = Option.bind (Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Point "scale" geometry)
        (Pdk.Attribute.get scale_key) in
    let transforms = Array.init (count - np) (fun index ->
      let x, y, z = Pdk.Packed.Float3.get points (np + index) in
      let sx, sy, sz = match scale with Some field -> Pdk.Packed.Float3.get field (np + index) | None -> 1., 1., 1. in
      Mat4.mul (Mat4.translation (v x y z)) (Mat4.scaling (v sx sy sz))) in
    let builder = Pdk.Topology.Builder.create ~point_count:np () in
    for primitive = 0 to Pdk.Topology.primitive_count topology - 1 do
      let first, _ = Pdk.Topology.primitive_vertex_range topology primitive in
      let polygon = Array.make (Pdk.Topology.primitive_size topology primitive) 0 in
      Pdk.Topology.iter_primitive_vertices topology primitive (fun vertex point ->
        polygon.(vertex - first) <- point);
      Pdk.Topology.Builder.add_polygon builder polygon
    done;
    let xs = Array.make np 0. and ys = Array.make np 0. and zs = Array.make np 0. in
    for index = 0 to np - 1 do
      let x, y, z = Pdk.Packed.Float3.get points index in
      xs.(index) <- x; ys.(index) <- y; zs.(index) <- z
    done;
    match Pdk.Packed.Float3.of_owned ~x:xs ~y:ys ~z:zs with
    | Error _ -> None
    | Ok positions ->
        (match Pdk.Geometry.create ~positions ~topology:(Pdk.Topology.Builder.freeze builder) () with
         | Ok prototype -> Some (prototype, transforms)
         | Error _ -> None)

let prepare mode (output : Session.output) =
  let packed = split_packed output.geometry in
  let geometry, instances = match packed with
    | Some (prototype, transforms) -> prototype, Array.length transforms
    | None -> output.geometry, 0 in
  let topology = Pdk.Geometry.topology geometry in
  let triangles = ref 0 in
  for primitive = 0 to Pdk.Topology.primitive_count topology - 1 do
    triangles := !triangles + max 0 (Pdk.Topology.primitive_size topology primitive - 2)
  done;
  let triangles = !triangles * max 1 instances in
  let finish ?traced ?raster ?wire () =
    Ok { mode; traced; raster; wire; triangles; instances } in
  match mode with
  | Path_traced ->
      let geometry = match packed with
        | Some _ -> pdk_error (Pdk.Normal_ops.run ~owner:Pdk.Attribute.Vertex
            ~cusp_angle:(Float.pi /. 4.5) geometry)
        | None -> Ok geometry in
      Result.bind geometry (fun geometry ->
        let mesh = match packed with
          | Some (_, transforms) -> P.mesh_instanced ~prototype:(geometry, concrete) transforms
          | None -> P.mesh [ geometry, concrete ] in
        Result.bind mesh (fun traced -> finish ~traced ()))
  | Raster ->
      let geometry = match packed with
        | Some _ -> pdk_error (Pdk.Normal_ops.run ~owner:Pdk.Attribute.Vertex
            ~cusp_angle:(Float.pi /. 4.5) geometry)
        | None -> Ok geometry in
      Result.bind geometry (fun geometry ->
      Result.bind (pdk_error (Pdk_prismel.Prismel_mesh.to_mesh geometry)) (fun mesh ->
        let raster = match packed with
          | Some (_, transforms) -> Scene3.instances_array ~material:raster_material mesh transforms
          | None -> Scene3.mesh ~material:raster_material mesh in
        finish ~raster ()))
  | Wireframe ->
      Result.bind (wire_mesh geometry) (fun mesh ->
        let wire = match packed with
          | Some (_, transforms) -> Scene3.instances_array ~material:wire_material
              ~cull:Scene3.Cull_none mesh transforms
          | None -> Scene3.mesh ~material:wire_material ~cull:Scene3.Cull_none mesh in
        finish ~wire ())

(* ---- sketch ---- *)

let env name default of_string = Option.value ~default (Option.bind (Sys.getenv_opt name) of_string)
let frames = env "PRISMEL_PATHTRACER_FRAMES" 0 int_of_string_opt
let orbit = Sys.getenv_opt "PRISMEL_PATHTRACER_ORBIT" = Some "1"
let started = Unix.gettimeofday ()
let image_size = (560, 800)

(* The renderer is a sketch setting: shown in the inspector while no node is
   selected, undoable, saved in presets, and handed to [prepare]. *)
module Settings = Prismel_editor.Settings

let settings_schema =
  Parameter.schema ~name:"voxel_wall" ~default:initial_renderer
    [ Parameter.field ~name:"renderer" ~label:"Renderer"
        ~kind:(Parameter.choice ~equal:( = )
          [ "Path traced", Path_traced; "Raster", Raster; "Wireframe", Wireframe ])
        ~default:initial_renderer ~get:Fun.id ~set:(fun renderer _ -> renderer) () ]

let renderer env = Settings.get settings_schema (Prismel_editor.Editor3.settings env)

type model = { env : prepared Prismel_editor.Editor3.t; tracer : P.t; shown : prepared option }

let raster_lights =
  [ Light.directional ~direction:(v 0.6 (-0.7) (-0.55)) ~diffuse:(Color.rgb 255 250 240) ()
  ; Light.directional ~direction:(v (-0.7) 0.3 (-0.6)) ~diffuse:(Color.rgb 90 95 110) ~intensity:0.4 () ]

let scene3 _graph prepared =
  match prepared.mode with
  | Path_traced -> Scene3.create []
  | Raster -> Scene3.create ~lights:raster_lights (Option.to_list prepared.raster)
  | Wireframe -> Scene3.create (Option.to_list prepared.wire)

let overlay tracer _graph prepared (frame : Frame.t) =
  let status = match prepared with
    | None -> "cooking"
    | Some p -> Printf.sprintf "%s  %d triangles%s%s"
        (match p.mode with Path_traced -> "path traced" | Raster -> "raster"
          | Wireframe -> "wireframe") p.triangles
        (if p.instances > 0 then Printf.sprintf "  %d instances" p.instances else "")
        (if p.mode = Path_traced then Printf.sprintf "  %d spp" (P.samples tracer)
         else "") in
  let picture = match prepared with
    | Some { mode = Path_traced; _ } ->
        let iw, ih = P.size tracer in
        let fit = Float.min (float frame.width /. float iw) (float frame.height /. float ih) in
        let w = int_of_float (float iw *. fit) and h = int_of_float (float ih *. fit) in
        Scene.[ rect ~at:(0, 0) ~w:frame.width ~h:frame.height ~fill:(Color.rgb 8 8 10) ()
              ; image (P.image tracer) ~at:((frame.width - w) / 2, (frame.height - h) / 2) ~scale:fit () ]
    | _ -> [] in
  picture @ Scene.[ text ~at:(12, 12) ~color:(Color.rgb 140 140 145) status ]

let init _frame =
  let placeholder = Result.get_ok (Pdk.Box_generator.box ~size:(v 0.01 0.01 0.01) ()) in
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
    match Prismel_editor.Editor3.create ~name:"voxel_wall"
      ~camera:(Easy_camera.create ~target:(v 0. 0. 1.) ~distance:19. ~azimuth:(-0.22)
        ~elevation:0.08 ~fov_y:0.7 ~inertia:false ())
      ~background:(Color.rgb 8 8 10) ~seed:7L ~grain:2 ~max_entries:24
      ~max_payload_bytes:(256 * 1024 * 1024) ~factories:Sop_catalog.Editor.factories
      ~settings:(Settings.make settings_schema initial_renderer)
      ~graph:(graph ())
      ~prepare:(fun settings -> prepare (Settings.get settings_schema settings))
      ~scene3 ~overlay:(overlay tracer) ()
    with Ok env -> env | Error message -> failwith message in
  { env; tracer; shown = None }

let update m (frame : Frame.t) =
  let env = Prismel_editor.Editor3.update m.env frame in
  let env = match switch_to with
    | Some target when frames > 0 && frame.count = frames / 2 ->
        Prismel_editor.Editor3.set_settings env (Settings.make settings_schema target)
    | _ -> env in
  let renderer = renderer env in
  let shown = match Prismel_editor.Editor3.prepared env with
    | Some prepared when (match m.shown with Some previous -> previous != prepared | None -> true) ->
        Option.iter (fun traced -> match P.queue_mesh m.tracer traced with
          | Ok () -> () | Error e -> prerr_endline e) prepared.traced;
        Some prepared
    | _ -> m.shown in
  (* The ACTIVE camera node drives the trace; the default one follows the
     viewport, so orbiting still steers it. *)
  if renderer = Path_traced then begin
    let camera = Prismel_editor.Editor3.render_camera env in
    let target = Camera.target camera in
    let fov = match Camera.projection camera with
      | Camera.Perspective { fov_y; _ } -> fov_y | _ -> 0.7 in
    let eye = if orbit then
      let angle = 0.5 *. sin (float frame.count *. 0.05) in
      v (target.x +. 19. *. sin angle) (target.y +. 1.5) (target.z +. 19. *. cos angle)
      else Camera.position camera in
    match P.render m.tracer (Camera.perspective ~fov_y:fov ~at:eye ~target ())
    with Ok () -> () | Error e -> prerr_endline e
  end;
  if frames > 0 && frame.count + 1 >= frames then begin
    Option.iter (fun path ->
      match Canvas.save_screen_png path with
      | Ok () -> Printf.printf "saved %s\n%!" path
      | Error e -> prerr_endline e) (Sys.getenv_opt "PRISMEL_PATHTRACER_PNG");
    Printf.printf "%d frames  %d spp  %.1f ms/frame\n%!" frames (P.samples m.tracer)
      ((Unix.gettimeofday () -. started) *. 1000. /. float frames);
    Sketch.quit ()
  end;
  { m with env; shown }

let view m (frame : Frame.t) = Prismel_editor.Editor3.scene m.env frame

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with width = 1280; height = 820; title = "Prismel voxel wall"
            ; domains = Some 1 }
    ~init ~update ~view
    ~after_present:(fun m frame ->
      { m with env = Prismel_editor.Editor3.after_present m.env frame })
    ~on_stop:(fun m -> Prismel_editor.Editor3.close m.env; P.destroy m.tracer) ())
