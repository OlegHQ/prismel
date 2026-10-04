(* The one renderer choice every sketch shows in its settings block, so the
   editor shell reads the same across sketches. *)
open Prismel

type t = Path_traced | Raster | Wireframe

let kind = Editor_core.Param.choice ~equal:( = )
    [ "Path traced", Path_traced; "Raster", Raster; "Wireframe", Wireframe ]

let field ~default ~get ~set =
  Editor_core.Param.field ~name:"renderer" ~label:"Renderer" ~kind ~default ~get ~set ()

let of_env name = match Sys.getenv_opt name with
  | Some "path" -> Some Path_traced
  | Some "raster" -> Some Raster
  | Some "wireframe" -> Some Wireframe
  | Some _ | None -> None

let wire_color background =
  let lightness = 299 * background.Color.r + 587 * background.g
    + 114 * background.b in
  if lightness >= 128000 then Color.hex_exn "#285f77"
  else Color.hex_exn "#bed7e1"

(* Every polygon edge once, as a line mesh. *)
let wire_mesh geometry =
  let topology = Pdk.Geometry.topology geometry in
  let edges = Pdk.Topology_index.create topology in
  let points = Pdk.Geometry.positions geometry in
  let vertices = Array.init (Pdk.Packed.Float3.length points) (fun index ->
    let x, y, z = Pdk.Packed.Float3.get points index in Vec3.create x y z) in
  let indices = Array.make (Pdk.Topology_index.edge_count edges * 2) 0 in
  for edge = 0 to Pdk.Topology_index.edge_count edges - 1 do
    let a, b = Pdk.Topology_index.edge_points edges edge in
    indices.(edge * 2) <- a; indices.(edge * 2 + 1) <- b
  done;
  Mesh.Private.create_owned ~mode:Mesh.Lines ~indices vertices

let label = function Path_traced -> "Path traced" | Raster -> "Raster" | Wireframe -> "Wireframe"
let of_label = function "Path traced" -> Some Path_traced | "Raster" -> Some Raster
  | "Wireframe" -> Some Wireframe | _ -> None
let schema = Editor_core.Param.schema ~name:"renderer" ~default:Raster
  [field ~default:Raster ~get:Fun.id ~set:(fun value _ -> value)]

module P = Prismel_pathtracer
type cached_mesh = { source : Mesh.t; material : Material.t; geometry : Pdk.Geometry.t;
                     traced : P.mesh }
(* how one viewport renders: the root of its scene instance, else the document's *)
type setting = { mode : t; bounces : int; round_samples : int }
type slot = { key : string; bounds : Pxui_shell.Layout.bounds; scene : Scene3.t;
              wire : Scene3.t option; tracer : P.t option; setting : setting }
(* [mode] and [tracing] are the default setting (the document's root); [raster_only]: every viewport
   draws as raster, so there are no slots *)
type state = { mode : t; custom : bool; slots : slot list; meshes : cached_mesh list;
               error : string option; tracing : int * int; raster_only : bool }
let empty = { mode = Raster; custom = false; slots = []; meshes = []; error = None; tracing = 4, 4;
              raster_only = true }
let close state = List.iter (fun slot -> Option.iter P.destroy slot.tracer) state.slots

let linear (color : Color.t) = P.Linear_color.rgb
  (float color.r /. 255.) (float color.g /. 255.) (float color.b /. 255.)
let traced_material (material : Material.t) =
  P.material ~roughness:(sqrt (2. /. (max 0. material.shininess +. 2.)))
    ~emission:(linear material.emissive) (linear material.diffuse)

let wire_scene scene =
  let nodes = ref [] in
  Scene3.Private.iter_batches (fun (drawing : Scene3.Private.drawing) transforms ->
    let material = Material.unlit (wire_color (Scene3.Private.ambient scene)) in
    let drawing_node = match transforms with
      | None -> Scene3.mesh ~material ~mode:Scene3.Wireframe ~cull:Scene3.Cull_none drawing.mesh
      | Some transforms -> Scene3.instances_array ~material ~mode:Scene3.Wireframe
          ~cull:Scene3.Cull_none drawing.mesh transforms in
    nodes := Scene3.transform drawing.transform [drawing_node] :: !nodes) scene;
  Scene3.create ~samples:1 (List.rev !nodes)

(* The cache keeps at most 64 converted source meshes. Placement remains in the
   tracer's instance structure, so an orbit does not convert or upload geometry. *)
let traced_scene meshes scene =
  let ( let* ) = Result.bind in
  let cache = ref meshes and result = ref (Ok []) in
  Scene3.Private.iter_batches (fun (drawing : Scene3.Private.drawing) transforms ->
    result := let* placed = !result in
      let* () = if drawing.texture = None then Ok ()
        else Error "Path tracing textured meshes is not supported." in
      let* cached = match List.find_opt (fun cached -> cached.source == drawing.mesh
          && cached.material = drawing.material) !cache with
        | Some cached -> Ok cached
        | None ->
            let* geometry = Result.map_error Pdk.Error.to_string
                (Pdk_prismel.Prismel_mesh.of_mesh drawing.mesh) in
            let* traced = P.mesh [geometry, traced_material drawing.material] in
            let cached = {source = drawing.mesh; material = drawing.material; geometry; traced} in
            cache := cached :: List.filteri (fun i _ -> i < 63) !cache;
            Ok cached in
      let* mesh = match transforms with
        | None -> Ok cached.traced
        | Some transforms -> P.mesh_instanced
            ~prototype:(cached.geometry, traced_material cached.material) transforms in
      Ok ((drawing.transform, mesh) :: placed)) scene;
  let* placed = !result in
  let* mesh = P.scene_mesh (List.rev placed) in
  Ok (!cache, mesh)

let update state ~mode ~custom ~bounces ~round_samples views =
  (* [views]: key, film, camera, scene and the setting of the viewport's own root, if it has one *)
  let default : setting = { mode; bounces; round_samples } in
  let views = List.map (fun (key, bounds, camera, scene, setting) ->
    key, bounds, camera, scene, Option.value ~default setting) views in
  if custom || List.for_all (fun (_, _, _, _, (setting : setting)) -> setting.mode = Raster) views then begin
    close state; { empty with mode; custom; tracing = bounces, round_samples }
  end else if List.length views > 16 then begin
    close state; { empty with mode; raster_only = false;
                   error = Some "At most 16 viewports can render together." }
  end else
    let meshes = ref state.meshes and errors = ref [] in
    let slots = List.map (fun (key, bounds, camera, scene, setting) ->
      let ({ mode; bounces; round_samples } : setting) = setting in
      let previous = List.find_opt (fun slot -> slot.key = key && slot.setting = setting) state.slots in
      let previous = Option.value ~default:{key; bounds; scene = Scene3.empty; wire = None; tracer = None; setting}
          previous in
      if mode = Raster then {key; bounds; scene; wire = None; tracer = None; setting}
      else if mode = Wireframe then
        {key; bounds; scene; tracer = None; setting; wire = Some (match previous.wire with
          | Some wire when previous.scene == scene -> wire | _ -> wire_scene scene)}
      else if (previous.scene != scene || previous.tracer = None)
          && (let found = ref false in
              Scene3.Private.iter_batches (fun _ _ -> found := true) scene; not !found)
      then {key; bounds; scene; wire = None; tracer = None; setting}
      else
        let ( let* ) = Result.bind in
        let _, _, width, height = bounds in
        let created = ref None in
        let render () =
          let* cache, mesh = if previous.scene == scene && previous.tracer <> None
            then Ok (!meshes, None) else
              Result.map (fun (cache, mesh) -> cache, Some mesh) (traced_scene !meshes scene) in
          meshes := cache;
          let* tracer = match previous.tracer with
            | Some tracer -> Ok tracer
            | None ->
                let first = List.hd cache in
                let* tracer = P.create ~bounces ~round_samples ~width:(max 1 width) ~height:(max 1 height)
                  {P.objects = [first.geometry, traced_material first.material]; spheres = []; strands = [];
                   environment = {sky = linear (Color.rgb 130 145 170);
                     ground = linear (Color.rgb 80 80 80); panels = []}; lights = []} in
                created := Some tracer; Ok tracer in
          let submitted = match mesh with None -> Ok () | Some mesh -> P.queue_mesh tracer mesh in
          let* () = submitted in
          let* () = P.resize tracer ~width:(max 1 width) ~height:(max 1 height) in
          let* () = if previous.tracer = None || Scene3.Private.lights previous.scene <> Scene3.Private.lights scene
            then P.set_lights tracer (List.map P.light_of (Scene3.Private.lights scene)) else Ok () in
          let* () = P.set_world tracer (Scene3.Private.world scene) in
          let* () = P.render tracer camera in
          Ok {key; bounds; scene; wire = None; tracer = Some tracer; setting} in
        match render () with
        | Ok slot -> slot
        | Error message -> Option.iter P.destroy !created;
            let stale = previous.tracer <> None in
            errors := Printf.sprintf "Renderer [%s]: %s (%s)" key message
              (if stale then "stale output retained" else "no output") :: !errors;
            if stale then {previous with bounds}
            else {key; bounds; scene; wire = None; tracer = None; setting}) views in
    List.iter (fun previous -> Option.iter (fun tracer ->
      if not (List.exists (fun slot -> Option.fold ~none:false ~some:(fun t -> t == tracer) slot.tracer) slots) then P.destroy tracer)
      previous.tracer) state.slots;
    {mode; custom; slots; meshes = !meshes; tracing = bounces, round_samples; raster_only = false;
     error = if !errors = [] then None else Some (String.concat "; " (List.rev !errors))}

let paint state ~key bounds camera scene =
  if state.custom || state.raster_only then [Scene.view3d ~viewport:bounds ~camera scene]
  else match List.find_opt (fun slot -> slot.key = key) state.slots with
    | Some {setting = {mode = Raster; _}; _} -> [Scene.view3d ~viewport:bounds ~camera scene]
    | Some {wire = Some wire; _} -> [Scene.view3d ~viewport:bounds ~camera wire]
    | Some {tracer = Some tracer; bounds = _, _, sw, _; _} -> let x, y, w, _ = bounds in
        (* a fixed render resolution is scaled to the film, so resizing a pane never re-renders *)
        [Scene.image (P.image tracer) ~at:(x, y) ~scale:(float w /. float (max 1 sw)) ()]
    | _ -> []
