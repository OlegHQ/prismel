open Rays
open Editor_document
open Procedural
open Common
module Image = Rays.Image

let set_ui_cursor ui visible =
  let shape = match if visible then Pxui.Ui.cursor ui else None with
    | Some shape -> (shape :> [`Default|`Horizontal_resize|`Vertical_resize|`Text])
    | None -> `Default in
  Sketch.set_cursor shape

type ('rendered, 'camera) hidden_scene_cache = {
  width : int;
  height : int;
  rendered : 'rendered option;
  camera : 'camera;
  background : Color.t;
  view_visible : bool;
  scene : Scene.t;
}

type canvas_picture = {size : int * int; dynamic : bool; scene : Scene.t;
  prepared : Sketch_support.Drawing.prepared option}

(* A World bake for this frame: the preview size while a gesture or the
   day cycle is live, the final size when idle. *)
let bake_world ?view ~previous core ~live =
  Option.map (fun world ->
    let width, height = if live then 512, 256 else 2048, 1024 in
    match previous with
    (* The same World keeps the same bake value, so renderers see no change. *)
    | Some (last, baked) when last = world && (baked : World.baked).camera.width = width ->
        world, baked
    | Some _ | None -> world, World.bake_cached ~width ~height world)
    (Core.world ?view core ~time:(Sketch_support.Timeline.time (Core.timeline core)))

(* the viewports over another scene instance: those that draw objects of their own and those that
   show another World *)
let view_keys (core : _ Core.t) =
  let own = match core.Core.doc.Document.shell with Some shell -> List.map fst shell.views | None -> [] in
  own @ List.filter (fun key -> not (List.mem key own)) (List.map fst core.Core.doc.Document.view_worlds)

let save_status ~save ~filename pending rendered =
  match pending, rendered with
  | Some request, Some _ ->
      Some (match save request with
        | Ok () -> "Saved " ^ filename request
        | Error message -> "Render failed: " ^ message)
  | _ -> None

let world ~paint_view ~key ~camera ~rendered ~view_visible viewport =
  match rendered with
  | Some image when view_visible -> paint_view ~key viewport camera image
  | Some _ | None -> []

(* Each viewport shows its own scene instance's image, else the primary one. *)
let worlds ~paint_view ~camera ~rendered ~views ~view_visible bodies =
  List.concat_map (fun (key, bounds) ->
    world ~paint_view ~key ~camera:(camera key) ~view_visible
      ~rendered:(match List.assoc_opt key views with Some image -> Some image | None -> rendered)
      bounds) bodies

let hidden_only ~ui_visible core =
  not ui_visible && core.Core.leader = Leader.Idle

(* The fully hidden scene, reused while its inputs are physically unchanged
   so the renderer sees the same [Scene.t]. *)
let hidden_entry ~background ~rendered ~camera ~paint_view ~cache core
    (frame : Frame.t) =
  let view_visible = Core.view_visible core in
  match cache with
  | Some cached when cached.width = frame.width
      && cached.height = frame.height && cached.rendered == rendered
      && cached.camera == camera && cached.background = background
      && cached.view_visible = view_visible -> cached
  | _ ->
      let scene = Scene.clear background ::
        world ~paint_view ~key:"@hidden" ~camera ~rendered ~view_visible
          (0, 0, frame.width, frame.height) in
      { width = frame.width; height = frame.height;
        rendered; camera; background; view_visible; scene }

(* The World's camera map as an sRGB image: the path tracer's exposure,
   ACES fit, and gamma, so the map reads like the renders. *)
let map_rgba (baked : World.baked) =
  let map = baked.camera in
  let step = max 1 (map.width / 1024) in
  let width = map.width / step and height = map.height / step in
  let rgba = Bytes.create (width * height * 4) in
  let exposure = 2. ** baked.exposure in
  let channel value =
    let c = value *. exposure in
    let c = c *. (2.51 *. c +. 0.03) /. (c *. (2.43 *. c +. 0.59) +. 0.14) in
    Char.chr (int_of_float (Float.pow (Float.max 0. (Float.min 1. c)) (1. /. 2.2)
      *. 255. +. 0.5)) in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let source = 3 * ((y * step * map.width) + (x * step))
      and target = 4 * ((y * width) + x) in
      for c = 0 to 2 do
        Bytes.set rgba (target + c) (channel (Float.Array.get map.pixels (source + c)))
      done;
      Bytes.set rgba (target + 3) '\255'
    done
  done;
  width, height, rgba

(* The map fitted at 2:1 in the view pane, and the texel under a point. *)
let map_rect (x, y, width, height) =
  let w = min width (2 * height) in
  let h = w / 2 in
  x + ((width - w) / 2), y + ((height - h) / 2), w, h

let map_uv viewport (px, py) =
  let x, y, w, h = map_rect viewport in
  let u = (px -. float x) /. float (max 1 w) and v = (py -. float y) /. float (max 1 h) in
  if u < 0. || u > 1. || v < 0. || v > 1. then None else Some (u, v)

type world_operation = Rotate_world of int | Move_layer of int * int | Move_sun of int
type world_drag = { operation : world_operation; point : float * float;
                    area : Pxui_shell.Layout.bounds }

let wrap_degrees value = Float.rem (Float.rem (value +. 180.) 360. +. 360.) 360. -. 180.

let world_operation core area point ~shift =
  match Core.world_id core with
  | Some world when core.Core.map_view && map_uv area point <> None ->
      (match Core.selected_node core with
       | Some node when List.exists (fun (field : Parameter.field_view) ->
           field.name = "azimuth") (Node.parameter_fields node) ->
           Some (Move_layer (world, Node.id node))
       | Some node when Node.operation node = "sun" -> Some (Move_sun world)
       | _ -> None)
  | Some world when not core.Core.map_view && shift -> Some (Rotate_world world)
  | _ -> None

let move_world core drag point =
  if point = drag.point then core else
  match drag.operation with
  | Rotate_world world ->
      (match Option.bind (Edit_graph.find (Core.scene core) ~node_id:world)
          (fun node -> List.find_map (fun (field : Parameter.field_view) ->
            match field.name, field.current with
            | "rotation", Parameter.Float_value value -> Some value | _ -> None)
            (Node.parameter_fields node)) with
       | Some rotation ->
           let rotation = wrap_degrees (rotation +. 0.5 *. (fst point -. fst drag.point)) in
           Core.edit_node core Document.Scene world ~label:"Rotate World"
             ["rotation", Parameter.Float_value rotation]
       | None -> core)
  | Move_layer (world, _) | Move_sun world ->
      let x, y, w, h = map_rect drag.area in
      let u = Float.max 0. (Float.min 1. ((fst point -. float x) /. float (max 1 w)))
      and v = Float.max 0. (Float.min 1. ((snd point -. float y) /. float (max 1 h))) in
      let direction = World.direction_of_uv u v in
      let rotation = match Core.world core ~time:0. with
        | Some world -> world.World.rotation | None -> 0. in
      let degrees radians = radians *. 180. /. Float.pi in
      let azimuth = wrap_degrees (degrees (Float.atan2 direction.Vec3.x (-. direction.z)
        -. rotation))
      and elevation = degrees (Float.asin direction.y) in
      (match drag.operation with
       | Move_layer (_, id) ->
           Core.edit_node core (Document.Inside world) id ~label:"Move layer"
             ["azimuth", Parameter.Float_value azimuth;
              "elevation", Parameter.Float_value elevation]
       | Move_sun _ ->
           Core.edit_node core Document.Scene world ~label:"Move sun"
             ["sun_linked", Parameter.Bool_value false;
              "sun_azimuth", Parameter.Float_value azimuth;
              "sun_elevation", Parameter.Float_value (Float.max (-10.) elevation)]
       | Rotate_world _ -> assert false)

let compose_view ?map ~canvases ~ui_visible ~background ~rendered ~focused ~views ~camera ~camera_of ~paint_view ~film
    ~overlay ~guides ~cache core (frame : Frame.t) =
  let view_visible = Core.view_visible core in
  let paint_world = match map with
    | Some image when view_visible && core.Core.map_view -> (fun viewport ->
        let x, y, w, _ = map_rect viewport in
        [Scene.image image ~at:(x, y)
           ~scale:(float w /. float (max 1 (Image.get_width image))) ()])
    | _ -> world ~paint_view ~key:(match core.Core.focus with View key -> key | _ -> "main")
        ~camera ~rendered:focused ~view_visible in
  (* each viewport is drawn from its own orbit *)
  if not ui_visible && (match core.Core.focus with Canvas _ -> true | _ -> false) then
    let key = match core.Core.focus with Canvas key -> key | _ -> assert false in
    Scene.clear background :: Option.fold ~none:[] ~some:(fun picture -> picture.scene) (List.assoc_opt key canvases)
    @ Core.machinery core ~all_ui_visible:false
  else if hidden_only ~ui_visible core then
    (hidden_entry ~background ~rendered:focused ~camera ~paint_view ~cache core frame).scene
  else if not ui_visible then
    Scene.clear background :: (world ~paint_view ~key:"@hidden" ~camera ~rendered:focused ~view_visible
      (0, 0, frame.width, frame.height))
    @ Core.machinery core ~all_ui_visible:false
  else
    let viewport = (Core.panes core frame).view in
    let x, y, width, height = viewport in
    let guides = if view_visible then guides viewport else [] in
    (* The sketch overlay is drawn in the film rect: its frame is that size. *)
    let (fx, fy, _, _) as film = film viewport in
    let overlay = [Scene.clip ~at:(x, y) ~w:width ~h:height
        (Scene.translate fx fy (overlay (Core.graph core) (Core.prepared core)
          (viewport_frame film frame)) :: guides)] in
    (* every viewport shows its own scene instance's image; the map replaces the focused one *)
    let floating = List.filter_map (fun (leaf : Pxui_shell.Layout.leaf) ->
      match leaf.panel with
      | View key when leaf.floating ->
          Some (key, leaf.path, leaf.body)
      | _ -> None) (Core.geometry core core.Core.workspace frame).leaves in
    let painted, windows = List.fold_left (fun (painted, windows) (key, bounds) ->
      let image = if bounds = viewport && core.Core.map_view then paint_world viewport
        else worlds ~paint_view ~camera:camera_of ~rendered ~views ~view_visible [key, bounds] in
      match List.find_opt (fun (k, _, _) -> k = key) floating with
      | None -> image :: painted, windows
      | Some (_, path, (x, y, w, h)) ->
          let root = List.find_map (fun (root, (panel, p)) ->
            if panel = Pxui_shell.Layout.View key && p = Some path then Some root else None) core.Core.pane_keys in
          (* inside the window's line-2 frame, which Chrome paints on the body's edge *)
          let image = Scene.rect ~at:(x + 1, y + 1) ~w:(w - 2) ~h:(h - 2) ~fill:Color.white () :: image
            @ (if bounds = viewport then overlay else []) in
          painted, (root, image) :: windows) ([], []) (Core.view_bodies core frame) in
    let canvas_painted, canvas_windows = List.fold_left (fun (painted, windows) (leaf : Pxui_shell.Layout.leaf) -> match leaf.panel with
      | Canvas key ->
          let x, y, w, h = leaf.body in
          let scene = Option.fold ~none:[] ~some:(fun picture -> picture.scene) (List.assoc_opt key canvases) in
          let root = List.find_map (fun (root, (panel, p)) ->
            if panel = Pxui_shell.Layout.Canvas key && p = Some leaf.path then Some root else None) core.Core.pane_keys in
          let picture = [Scene.clip ~at:(x, y) ~w ~h [Scene.translate x y scene]] in
          if leaf.floating then painted, (root, picture) :: windows
          else picture :: painted, windows
      | _ -> painted, windows) ([], []) (Core.geometry core core.Core.workspace frame).leaves in
    let under key = Option.value ~default:[] (List.assoc_opt (Some key) (canvas_windows @ windows)) in
    Scene.clear background :: List.concat (List.rev (canvas_painted @ painted))
    @ (if List.exists (fun (_, _, bounds) -> bounds = viewport) floating then [] else overlay)
    @ Core.machinery ~under core ~all_ui_visible:true

(* The one environment: [Core] plus the 3D viewport. *)
module V = Viewport3
type layout = Pxui_shell.Layout.t

type 'prepared t = {
  core : 'prepared Core.t;
  camera : V.camera;  (* the orbit of the focused viewport *)
  cameras : (string * V.camera) list;  (* the orbits of the other viewports, by key *)
  viewing : string option;  (* the viewport [camera] belongs to *)
  control : V.control;
  draw : Graph.t -> 'prepared -> V.rendered;
  overlay : Graph.t -> 'prepared option -> Frame.t -> Scene.t;
  status : 'prepared option -> string option;  (* sketch text in the status bar *)
  rendered : V.rendered option;
  views : (string * V.rendered) list;  (* viewports over another scene instance *)
  drawn : (Graph.t * 'prepared * V.rendered) Document.Int_map.t;  (* per object *)
  composed : (Edit_graph.t * Document.level * (string * int list) list) option;
  resolved : (Document.t * Frame_input.t * Edit_graph.t) option;
  context_error : string option;
  (* The scene, open level (ghosts), and viewport membership used by the picture. *)
  baked : World.baked option;
  baked_from : (World.t * World.baked) option;
  baked_views : (string * (World.t * World.baked)) list;  (* the World of each viewport over another scene instance *)
  map : (World.baked * Image.t) option;  (* the lat-long view's upload *)
  render_status : string option;
  pending_render : V.request option;
  background : Color.t;
  extra : V.extra;
  hidden_scene_cache : (V.rendered, V.view) hidden_scene_cache option;
  commands : (Pxui_shell.Layout.panel, 'prepared t -> 'prepared t) Editor_core.Command.t list;
  world_drag : world_drag option;
  pick_press : (float * float) option;  (* a left press in the view that may become a click *)
  source : Source_file.t option;  (* the .rays the document came from: polled, saved over *)
  held : string option;  (* the file's changed text, waiting while the document has unsaved work *)
  refused : string option;  (* the file's text that did not check: the Document tab shows it *)
  opened : Document.t;  (* the document this session started from *)
  state_owned : bool;  (* this session wrote the recovery file *)
  state_checked : float;
  saved_doc : Document.t;
  saved_view : Flow.Syntax.t;
  state_error : string option;
  canvases : (string * canvas_picture) list;
  host : Workspace_host.t;
}

(* Scene objects a sketch starts with: its lights as light objects. *)
let seed_lights lights scene =
  List.fold_left (fun (scene, index) light ->
    let added = Result.bind (Edit_graph.instantiate_optional Objects.Light.factory [None])
        (fun node ->
          let node = Node.relabel (Printf.sprintf "light%d" index) node in
          Result.bind (Edit_graph.add_node ~factory:Objects.Light.factory
              ~inputs:[|None|] node scene) (fun scene ->
            Result.map fst (Edit_graph.apply_parameters scene ~node_id:(Node.id node)
              (Objects.light_values light)))) in
    (match added with Ok scene -> scene | Error _ -> scene), index + 1)
    (scene, 1) lights |> fst

let create ?inputs ?(layout = Pxui_shell.Layout.default) ?name ?presets ?timeline_frames ?factories
    ?settings ?(commands = []) ?(lights = []) ?world
    ?(camera = V.default_camera ()) ?lens ?(background = Color.hex_exn "#f4f5f0")
    ?seed ?grain ?domains ?max_entries ?max_payload_bytes ?await ?carry_budget ~workspace ?source ~prepare ~draw
    ?(overlay = fun _ _ _ -> Scene.empty) ?(status = fun _ -> None) () =
  let workspace = match inputs with None -> workspace
    | Some inputs -> {workspace with Workspace_doc.inputs} in
  let source = Option.map (fun source -> Source_file.with_imports source
      (Workspace_doc.import_texts workspace)) source in
  let name = Option.value name ~default:(Workspace_doc.name workspace) in
  let state_key = match source with
    | None -> "workspace:" ^ Workspace_doc.name workspace
    | Some source ->
        let file = Source_file.file source in
        let file = try Unix.realpath file with Unix.Unix_error _ ->
          if Filename.is_relative file then Filename.concat (Sys.getcwd ()) file else file in
        "file:" ^ file in
  let open Editor_core.Command in
  let normalize_key = function Input.KeyChar c -> Input.KeyChar (Char.lowercase_ascii c)
    | key -> key in
  let normalize = function
    | Editor_core.Keymap.Leader sequence ->
        Editor_core.Keymap.Leader (String.lowercase_ascii sequence)
    | Chord (key, modifiers) ->
        Chord (normalize_key key, List.sort_uniq compare modifiers) in
  let commands = List.map (fun command ->
      { command with trigger = Option.map normalize command.trigger }) commands in
  let overlaps a b = a.scope = None || b.scope = None || a.scope = b.scope in
  let conflicts a b = overlaps a b && match a.trigger, b.trigger with
    | Some a_trigger, Some b_trigger when a.id = b.id && a_trigger = b_trigger -> false
    | Some (Editor_core.Keymap.Leader a), Some (Leader b) ->
        String.starts_with ~prefix:a b || String.starts_with ~prefix:b a
    | Some (Chord (a, am)), Some (Chord (b, bm)) ->
        a = b && List.length am = List.length bm
        && List.mem Input.Meta am = List.mem Input.Meta bm
        && List.mem Input.Ctrl am = List.mem Input.Ctrl bm
    | Some a, Some b -> normalize a = normalize b
    | _ -> false in
  let rec validate seen = function
    | [] -> Ok ()
    | command :: rest ->
        let error = if String.trim command.id = "" || String.trim command.label = "" then
            Some "command id and label must be nonempty"
          else if List.exists (fun builtin -> builtin.id = command.id) V.keymap then
            Some ("command id is reserved: " ^ command.id)
          else if List.exists (fun previous -> previous.id = command.id
              && previous.action != command.action) seen then
            Some ("command aliases must share the same action: " ^ command.id)
          else match command.trigger with
            | Some (Editor_core.Keymap.Leader sequence)
                when sequence = "" || String.contains sequence ' ' ->
                Some ("invalid leader sequence: " ^ command.id)
            | Some (Chord (Input.Space, modifiers))
                when not (List.mem Input.Meta modifiers || List.mem Input.Ctrl modifiers) ->
                Some ("Space is reserved for leader routing: " ^ command.id)
            | Some (Chord (_, modifiers)) when List.exists (function
                | Input.Meta | Ctrl | Shift | Alt -> false | _ -> true) modifiers ->
                Some ("invalid chord modifier: " ^ command.id)
            | _ ->
                let previous = match List.find_opt (conflicts command) seen with
                  | Some previous -> Some previous.id
                  | None -> Option.map (fun previous -> previous.id)
                      (List.find_opt (conflicts command) V.keymap) in
                Option.map (fun id -> "command trigger conflicts: "
                  ^ command.id ^ " and " ^ id) previous in
        match error with Some message -> Error message
          | None -> validate (command :: seen) rest in
  Result.bind (validate [] commands) (fun () -> Result.map (fun core ->
    let core, extra = V.init core camera in
    let core = match source with
      | Some source -> { core with Core.file = Filename.basename (Source_file.file source) }
      | None -> core in
    { core; camera; control = V.create_control (); draw; overlay; status;
      rendered = None; views = []; drawn = Document.Int_map.empty; composed = None;
      resolved = None; context_error = None; canvases = []; host=Workspace_host.create(); baked = None; baked_from = None; baked_views = []; map = None;
      render_status = None; pending_render = None;
      background; extra; hidden_scene_cache = None; commands; world_drag = None; pick_press = None; source; held = None; refused = None; opened = core.doc; state_owned = false; cameras = []; viewing = None;
      state_checked = neg_infinity; saved_doc = core.doc; saved_view = V.section camera extra; state_error = None })
    (Core.create ?settings ?world
      ~keymap:(V.keymap @ List.map (fun (c : _ Editor_core.Command.t) ->
        { c with action = Leader.Sketch_command c.id }) commands)
      ~seed_scene:(fun factories scene ->
        V.seed_scene ?lens camera factories (seed_lights lights scene))
      ~layout ~name ~state_key ?presets ?timeline_frames ?factories ?seed ?grain ?domains
      ?max_entries ?max_payload_bytes ?await ?carry_budget ~workspace ~prepare ()))

let document value = Core.document value.core
let prepared value = Core.prepared value.core
let camera value = value.camera
let extra value = value.extra
let timeline value = Core.timeline value.core
let selected_node value = Core.selected_node value.core
let displayed_node value = Core.displayed_node value.core
let panes value frame = Core.panes value.core frame
let can_undo value = Editor_core.History.can_undo value.core.Core.history
let can_redo value = Editor_core.History.can_redo value.core.Core.history
let undo_label value = if can_undo value
  then Some (Editor_core.History.label value.core.Core.history) else None
let redo_label value = Editor_core.History.redo_label value.core.Core.history
let workspace value = fst value.core.Core.doc.workspace
let probe value zone = Layout_by_path.Path_map.find_opt zone value.core.Core.probes
let set_probe value zone index =
  { value with core = { value.core with Core.probes = Layout_by_path.Path_map.add zone index value.core.Core.probes } }
let node_box value path =
  Option.map (fun (x, y, w, h) -> int_of_float x, int_of_float y, int_of_float w, int_of_float h)
    (Pxui_graph.Scope.Private.box_of value.core.Core.scope_view path)
let edit value op = Result.map (fun core -> { value with core }) (Core.syntax_edit value.core op)

let edit_phases value = value.core.Core.edit_phases
let carrying value = Option.map (fun (c : _ Core.carry) -> c.payload.Carry.kind, c.payload.value) value.core.Core.carry
let carry_line value = Option.map Core.carry_line value.core.Core.carry
let level value = match value.core.Core.level with
  | Document.Scene -> None
  | Inside id -> Some (Option.fold ~none:"" ~some:Node.label
      (Edit_graph.find (Core.scene value.core) ~node_id:id))
let scene_document value = Core.scene value.core
let same_context (a : Document.t) (b : Document.t) =
  a.scene.graph.geometry == b.scene.graph.geometry && a.scene_drives == b.scene_drives
let resolved_scene value = match value.resolved with
  | Some (doc, _, scene) when same_context doc value.core.Core.doc -> scene
  | _ -> Core.scene value.core
let lights value = Objects.lights ~render:true (resolved_scene value)
let world value = value.baked
let objects value = List.map (fun (matrix, (piece : _ Cook.piece)) ->
    matrix, piece.prepared) (Core.placed_pieces ~render:true value.core)

let settings value = Core.settings value.core
let set_settings value settings =
  { value with core = Core.set_settings value.core settings }

(* the viewport the focus is in; the default layout's one before any focus *)
let focus_key value = Option.value value.viewing ~default:"main"

(* the viewport whose root a view is read from: the hidden scene shows the focused viewport *)
let look_key value key = if key = "@hidden" then focus_key value else key

(* the view of the viewport [key]: its own orbit, the focused one's being [camera], through
   the camera of its own root *)
let camera_of value key =
  let key = look_key value key in
  let orbit = if Some key = value.viewing then value.camera
    else Option.value (List.assoc_opt key value.cameras) ~default:value.camera in
  V.view_camera orbit value.extra ~key ~pending:(value.pending_render <> None)

let view_camera value = camera_of value (focus_key value)

(* Focus moves to another viewport: the orbit of the one left is kept, the new one starts from
   the orbit it last had, else from a copy of the one in use. *)
let follow_focus value frame =
  let core = value.core in
  let g = Core.geometry core core.Core.workspace frame in
  let keys = List.filter_map (fun (leaf : Pxui_shell.Layout.leaf) -> match leaf.panel with
    | View key -> Some key | _ -> None) g.leaves in
  let value = { value with cameras = List.filter (fun (key, _) -> List.mem key keys) value.cameras } in
  match Core.active_view core g with
  | Some { panel = View key; _ } when Some key <> value.viewing ->
      (match value.viewing with
       | None ->
           (* the first focus: every other viewport starts as a copy of the orbit in use *)
           let others = List.filter_map (fun (leaf : Pxui_shell.Layout.leaf) -> match leaf.panel with
             | View k when k <> key -> Some (k, value.camera) | _ -> None) g.leaves in
           { value with viewing = Some key; cameras = others }
       | Some previous ->
           let kept = if List.mem previous keys
             then (previous, value.camera) :: List.remove_assoc previous value.cameras
             else value.cameras in
           { value with viewing = Some key;
             camera = Option.value (List.assoc_opt key kept) ~default:value.camera;
             cameras = List.remove_assoc key kept })
  | _ -> value

let paint_view value ~key viewport view rendered =
  V.paint value.extra ~key (V.film value.extra ~key:(look_key value key) viewport) view rendered

let viewport_camera = camera_of

let focused_image value = match value.viewing with
  | Some key -> (match List.assoc_opt key value.views with Some image -> Some image | None -> value.rendered)
  | None -> value.rendered

let film value frame =
  let (x, y, _, _) as pane = (Core.panes value.core frame).view in
  let fx, fy, w, h = V.film value.extra ~key:(focus_key value) pane in
  fx - x, fy - y, w, h

let take_export value = match value.pending_render with
  | Some request -> { value with pending_render = None }, Some (V.filename request)
  | None -> value, None

let set_render_status value render_status = { value with render_status }

(* The hidden-scene cache is model state: refreshed here, read by [scene]. *)
let refresh_hidden value frame =
  let hidden_scene_cache =
    if hidden_only ~ui_visible:(V.ui_visible value.control) value.core then
      Some (hidden_entry ~background:value.background ~rendered:(focused_image value)
        ~camera:(view_camera value) ~paint_view:(paint_view value)
        ~cache:value.hidden_scene_cache value.core frame)
    else None in
  { value with hidden_scene_cache }

(* Recompose when a cook, the scene, or the World changed. Each object's
   drawing is reused while its graph and prepared value are physically the same, so
   moving an object only re-places it. *)
let composition_key core scene = scene, core.Core.level,
  (match core.Core.doc.Document.shell with Some shell -> shell.views | None -> [])

let compose value (update : (_, _) Core.update) ~baked ~baked_views ~scene =
  let scene, level, views = composition_key update.core scene in
  let same = match value.composed with
    | Some (s, l, v) -> s == scene && l = level && v = views
    | None -> false in
  if not (update.prepared_changed || update.scene_changed || update.effects.view
      || update.effects.export || not same || baked != value.baked || baked_views != value.baked_views
      || value.rendered = None)
  then value.rendered, value.views, value.drawn
  else
    let placed = Core.placed_pieces ~view:`All update.core in
    let drawn = List.fold_left (fun drawn (_, (piece : _ Cook.piece)) ->
        match Document.Int_map.find_opt piece.id value.drawn with
        | Some (graph, prepared, rendered) when graph == piece.graph && prepared == piece.prepared ->
            Document.Int_map.add piece.id (graph, prepared, rendered) drawn
        | Some _ | None ->
            Document.Int_map.add piece.id
              (piece.graph, piece.prepared, value.draw piece.graph piece.prepared) drawn)
        Document.Int_map.empty placed in
    let waiting = placed = [] && Core.geometry_objects update.core <> []
        && Core.pieces update.core = [] in
    let ghost id = match update.core.Core.level with
      | Document.Inside open_id -> Core.kind update.core open_id = Some "geometry"
          && id <> open_id
      | Scene -> false in
    let compose_pieces ?(world = baked) view pieces = V.compose ~scene:(Core.scene_for_view ~scene ~view update.core)
      ~world
      (List.map (fun (matrix, (piece : _ Cook.piece)) ->
         let _, _, rendered = Document.Int_map.find piece.id drawn in
         matrix, ghost piece.id, rendered) pieces) in
    (* a viewport over another scene instance: its own objects, its own World.  Viewports over
       the very same instance with the same World show one picture: it is composed once, so
       the renderer sees one scene and can give them one tracer *)
    let instance_of key = Option.bind update.core.Core.doc.Document.shell (fun shell ->
      Option.map (fun (source : Document.preview_source) -> source.instance)
        (List.assoc_opt key shell.preview_sources)) in
    let views = if waiting then [] else List.rev_map (fun (key, scene, _, _) -> key, scene)
      (List.fold_left (fun composed key ->
        let world = Option.map snd (List.assoc_opt key baked_views) in
        let instance = instance_of key in
        let same_instance = function Some a -> Option.fold ~none:false ~some:(( == ) a) instance | None -> false in
        let same_world other = match world, other with
          | None, None -> true | Some a, Some b -> a == b | Some _, None | None, Some _ -> false in
        let twin = List.find_map (fun (_, scene, other, other_world) ->
          if same_instance other && same_world other_world then Some scene else None) composed in
        let scene = match twin with
          | Some scene -> scene
          | None ->
              let own = match update.core.Core.doc.Document.shell with
                | Some shell -> List.mem_assoc key shell.views | None -> false in
              let view = if own then `Only key else `Primary in
              compose_pieces ~world:world view (Core.placed_pieces ~view update.core) in
        (key, scene, instance, world) :: composed) [] (view_keys update.core)) in
    (if waiting then None else Some (compose_pieces `Primary (Core.placed_pieces update.core))),
    views, drawn

(* The source file, at most every half second: a changed text reloads the document.  Unsaved work
   is never replaced: while the document differs from the file's last text or a text pane holds a
   draft, the file's new text waits ([held]) and the strip says how to choose.  It loads once the
   edits are undone, or at once by "Reload sketch from its file" (the palette).  Nothing is polled
   while a payload is carried: the document shown is a preview then. *)
let open_import value (update : (_, _) Core.update) = match update.core.Core.open_import, value.source with
  | Some path, Some source ->
      let core = {update.core with Core.open_import = None} in
      if Core.unsaved core then
        value, {update with core = {core with Core.notice = Some (Core.Refusal,
          "Save or undo your changes before opening " ^ path ^ ".")}}
      else
        let file = Filename.concat (Filename.dirname (Source_file.file source)) path in
        (match Source_file.read file with
         | Error message -> value, {update with core = {core with Core.notice = Some (Core.Refusal, message)}}
         | Ok original ->
             let text = original in
             (match Core.reload ~imports:[] core ~name:(Filename.basename file) text with
              | Error ds -> value, {update with core = Core.reload_failed core ~name:path text ds}
              | Ok core ->
                  let core = {core with Core.file = Filename.basename file} in
                  {value with source = Some (Source_file.at ~file ~digest:(Source_file.sha original));
                    held = None; refused = None}, {update with core; scene_changed = true}))
  | _ -> value, update

let reload_source value (update : (_, _) Core.update) ~now = match value.source with
  | Some previous when not (Core.carrying update.core) ->
      let file, read = Source_file.poll ~now previous in
      let name = Filename.basename (Source_file.file file) in
      let core = if file.error = previous.error then update.core else
        { update.core with Core.notice = Some (match file.error with
          | Some message -> Core.Refusal, "Source unreadable: " ^ message
          | None -> Core.Info, "Source readable again: " ^ name) } in
      let forced = List.mem Leader.Reload_source update.actions in
      let text = match read, value.held with
        | Some _, _ -> read
        | None, None when forced -> Result.to_option (Editor_core.Store.read_text ~filename:(Source_file.file file))
        | None, held -> held in
      let value = { value with source = Some file } in
      (match text with
       | None -> value, { update with core }
       | Some text when not forced && Core.unsaved ?except:value.refused core ->
           { value with held = Some text },
           { update with core = if read = None then core else
             { core with Core.notice = Some (Core.Info, name ^ " changed on disk · your unsaved edits are kept · \
               undo them or run \"Reload sketch from its file\" to take the file; Command-S saves yours as a preset") } }
       | Some text ->
           (match Result.bind (Source_file.read_imports ~file:(Source_file.file file) text)
              (fun imports -> Core.reload ~imports core ~name text) with
            | Ok core ->
                { value with source = Some (Source_file.with_imports (Source_file.accepted file text)
                    (Editor_document.Workspace_doc.import_texts (fst core.Core.doc.workspace))); held = None; refused = None },
                { update with core; scene_changed = true }
            | Error diagnostics ->
                { value with held = None; refused = Some text },
                { update with core = Core.reload_failed core ~name text diagnostics }))
  | _ -> value, update

(* Command-S: over the source file while it is what the document came from, else a preset. *)
let save_source core source view =
  let notice ?(kind = Core.Info) text = { core with Core.notice = Some (kind, text) } in
  let preset why = match Preset.save ~directory:core.Core.presets ~name:(Preset.default_name ())
      ~doc:core.doc ~view with
    | Ok path -> notice (why ^ "; saved as preset " ^ Filename.basename path)
    | Error message -> notice ~kind:Core.Refusal ("Not saved: " ^ message) in
  let text = Preset.text core.doc in
  match source with
  | None -> preset "no source file", source
  | Some file ->
      (match Source_file.save file text with
       | Ok file -> Core.filed (notice ("Saved " ^ Filename.basename (Source_file.file file))), Some file
       | Error `Changed -> preset "source changed since build", Some file
       | Error (`Failed message) -> notice ~kind:Core.Refusal ("Not saved: " ^ message), Some file)

(* One recovery file per sketch. Polling at 2 Hz coalesces live drags and
   keeps printing and filesystem work out of idle frames; close flushes. *)
let autosave ?(force = false) value ~now =
  if not force && now >= value.state_checked && now -. value.state_checked < 0.5 then value else
  let view = V.section value.camera value.extra in
  let value = { value with state_checked = now } in
  (* a preview document is never saved *)
  if (value.core.doc == value.saved_doc && view = value.saved_view) || Core.carrying value.core then value else
  (* the recovery file of an earlier session holds its unsaved work: orbiting in a document that
     is still the one opened never writes over it *)
  if not value.state_owned && Core.same_text value.core.doc value.opened
     && Sys.file_exists (Core.state_file value.core)
  then { value with saved_doc = value.core.doc; saved_view = view } else
  match Preset.save ~directory:(Core.state_directory value.core) ~name:value.core.state_name
      ~doc:value.core.doc ~view with
  | Ok _ -> { value with saved_doc = value.core.doc; saved_view = view; state_error = None; state_owned = true }
  | Error message -> { value with state_error = Some ("Autosave failed: " ^ message) }

let update_with value frame ~inspector =
  let value = follow_focus value frame in
  let ui = value.core.Core.ui in
  let raw_frame = frame in
  let extra, frame = V.begin_frame value.extra frame in
  let visible = V.ui_visible value.control in
  let camera_panel () = V.panel ui ~control:value.control ~camera:value.camera
      ~extra ~inspector in
  let view_handles ui ~selected ~space ~bounds =
    (* a handle is where the picture shows its point: in the view's film, not its pane *)
    V.handles ui ~selected ~scene:(Core.scene value.core) ~space (view_camera value)
      extra ~bounds:(V.film extra ~key:(focus_key value) bounds) in
  let update = Core.update value.core ~all_ui_visible:visible
      ~text_focus:(Pxui.Ui.text_input_focused ui) ~camera_panel ~view_handles
      ~render_status:(match value.status (Core.prepared value.core), value.render_status with
        | Some sketch, Some render -> Some (sketch ^ " · " ^ render)
        | sketch, None -> sketch | None, render -> render)
      ~error_status:(match value.state_error with
        | Some _ as error -> error
        | None -> match value.context_error, V.render_status value.extra with
          | Some live, Some renderer -> Some (live ^ "; " ^ renderer)
          | Some _ as error, None | None, (Some _ as error) -> error
          | None, None -> None)
      ~view_state:(function
        | Some (_, camera, _, extra, _) -> V.section camera extra
        | None -> V.section value.camera extra) frame in
  let value, update = open_import value update in
  let value, update = reload_source value update ~now:frame.Frame.time in
  let focused = follow_focus { value with core = update.core } frame in
  let core = update.core and panes = Core.panes update.core frame in
  let control, camera, requests, extra, inspected = match update.panel with
    | Some (control, camera, requests, extra, inspected) ->
        control, (if focused.viewing <> value.viewing then focused.camera else camera), requests, extra, Some inspected
    | None -> value.control, focused.camera, [], extra, None in
  let camera, extra = match update.loaded_view with
    | Some json -> V.restore camera extra json
    | None -> camera, extra in
  let previous_camera = if update.loaded_view = None then focused.camera else camera in
  let control, extra, render_status = List.fold_left
      (fun (control, extra, status) -> function
        | Leader.Hide_ui -> V.toggle_ui control, extra, status
        | Open_camera -> V.open_camera control, extra, status
        | action ->
            let extra, notice = V.apply_action camera extra action in
            control, extra, (if notice = None then status else notice))
      (control, extra, value.render_status) update.actions in
  let core = V.on_doc ~previous:value.core core camera in
  (* Command-S with a draft in a text pane applies it first; one that does not check keeps the
     save waiting, since the file would not have what the pane shows *)
  let core, source = if not (List.mem Leader.Save_source update.actions) then core, value.source else
    match Core.apply_drafts ?except:value.refused core with
    | Ok core -> save_source core value.source (V.section camera extra)
    | Error core ->
        { core with Core.notice = Some (Core.Refusal,
            "Not saved: the text pane's draft does not check · fix or discard it, then save") }, value.source in
  let value = if source != value.source then { value with held = None } else value in
  let area = if visible then panes.view
    else 0, 0, frame.Frame.width, frame.height in
  (* Latch the World operation and target at the owned press. Movement and
     the final release position are reduced before sealing its history. *)
  let seal core = { core with Core.history = Editor_core.History.seal core.Core.history } in
  let world_drag = if update.loaded_view <> None
      || core.Core.level <> value.core.Core.level
      || core.Core.map_view <> value.core.Core.map_view
      || List.exists (function Leader.Undo | Redo | Hide_ui -> true | _ -> false) update.actions
    then None else value.world_drag in
  let modifiers = ref (Event.Private.keys_before ~previous:value.core.Core.held_keys
    ~held:update.input.keys update.input.events) in
  let core, world_drag, events, consumed = List.fold_left
      (fun (core, drag, events, consumed) event ->
        modifiers := Event.Private.keys_after !modifiers event;
        match event, drag with
        | Event.MousePressed (Input.LeftButton, point), None ->
            (match world_operation core area point ~shift:(List.mem Input.Shift !modifiers) with
             | Some operation -> seal core, Some { operation; point; area },
                 Event.PointerCancelled Input.LeftButton :: events, true
             | None -> core, drag, event :: events, consumed)
        | Event.MouseMoved point, Some drag ->
            move_world core drag point, Some { drag with point }, events, true
        | Event.MouseReleased (Input.LeftButton, point), Some drag ->
            seal (move_world core drag point), None,
              Event.PointerCancelled Input.LeftButton :: events, true
        | (Event.PointerCancelled Input.LeftButton | Event.WindowFocusLost), _ ->
            seal core, None, event :: events, consumed || drag <> None
        | _ -> core, drag, event :: events, consumed)
      (core, world_drag, [], false) update.input.events in
  let input = { update.input with events = List.rev events;
    mouse_buttons = if world_drag = None then update.input.mouse_buttons
      else List.filter (( <> ) Input.LeftButton) update.input.mouse_buttons;
    mouse_delta = if consumed then 0., 0. else update.input.mouse_delta } in
  (* A press and release within 4 points is a click: the view picks. *)
  let pick_press, clicks = List.fold_left (fun (press, clicks) -> function
    | Event.MousePressed (Input.LeftButton, point) -> Some point, clicks
    | MouseReleased (Input.LeftButton, (qx, qy)) ->
        (match press with
         | Some (px, py) when Float.hypot (qx -. px) (qy -. py) < 4. ->
             None, (qx, qy) :: clicks
         | _ -> None, clicks)
    | PointerCancelled Input.LeftButton | WindowFocusLost -> None, clicks
    | _ -> press, clicks) (value.pick_press, []) input.events in
  let core = if core.Core.map_view then core else
    List.fold_left (fun core at ->
      let film = V.film extra ~key:(focus_key focused) area in
      let _, _, w, h = film in
      if w <= 0 || h <= 0 then core else
      let picking = { focused with core; camera; extra } in
      match V.pick_ray ~viewport:film (view_camera picking) at with
      | Some (origin, direction) -> Core.pick ?view:focused.viewing ~alt:(List.mem Input.Alt !modifiers) core ~origin ~direction
      | None -> core) core (List.rev clicks) in
  (* a payload carried over a viewport: the surface under the pointer is the place *)
  let core = match Core.carry_viewport core with
    | Some key when not core.Core.map_view ->
        (match List.assoc_opt key (Core.view_bodies core raw_frame) with
         | Some bounds ->
             let picking = { focused with core; camera; extra } in
             let film = V.film extra ~key:(look_key picking key) bounds in
             let _, _, w, h = film in
             if w <= 0 || h <= 0 then core else
             (match V.pick_ray ~viewport:film (camera_of picking key) raw_frame.Frame.mouse with
              | Some (origin, direction) -> Core.carry_over_surface ~view:key core ~origin ~direction
              | None -> core)
         | None -> core)
    | _ -> core in
  let camera, extra = if core.Core.map_view then camera, V.release extra
    else V.navigate ~area control camera extra core ~raw_frame ~input in
  let camera, render_status = match update.framed with
    | Some (Some (min, max)) ->
        let _, _, w, h = panes.view in
        if w > 0 && h > 0 then
          V.frame_bounds ~viewport:panes.view ~min ~max camera, render_status
        else camera, render_status
    | Some None -> camera, Some "Nothing to frame: no cooked points"
    | None -> camera, render_status in
  let core, camera, extra = V.on_view core ~previous:previous_camera ~key:(focus_key focused) camera extra
      ~stepped:(List.exists (function Leader.Undo | Redo -> true | _ -> false) update.actions) in
  let ends_pointer = function
      | Event.MouseReleased (Input.LeftButton, _) | PointerCancelled Input.LeftButton
      | WindowFocusLost -> true | _ -> false in
  let core = if not (Frame.mouse_down Input.LeftButton raw_frame)
      || Frame.has_event ends_pointer raw_frame || Frame.has_event ends_pointer update.input
    then { core with Core.history = Editor_core.History.seal ~gesture_only:true core.Core.history }
    else core in
  let live = world_drag <> None
    || Sketch_support.Timeline.mode (Core.timeline core) = Sketch_support.Timeline.Playing in
  let baked_from = bake_world ~previous:value.baked_from core ~live in
  let baked = Option.map snd baked_from in
  let baked_views = List.filter_map (fun key ->
    Option.map (fun bake -> key, bake)
      (bake_world ~view:(`Only key) ~previous:(List.assoc_opt key value.baked_views) core ~live))
    (view_keys core) in
  (* the same bakes as last frame: nothing to recompose for *)
  let baked_views = if List.length baked_views = List.length value.baked_views
      && List.for_all2 (fun (k, (_, b)) (k', (_, b')) -> k = k' && b == b') baked_views value.baked_views
    then value.baked_views else baked_views in
  let time = Sketch_support.Timeline.time (Core.timeline core) in
  let frame_input = {core.live_frame with Frame_input.t = time;
    frame = Int64.to_int (Sketch_support.Timeline.frame (Core.timeline core))} in
  let scene, context_error = match value.resolved with
    | Some (doc, at, scene) when same_context doc core.Core.doc && Frame_input.equal at frame_input -> scene, value.context_error
    | _ ->
        let previous = match value.resolved with
          | Some (doc, _, scene) when same_context doc core.doc -> Some scene
          | _ -> None in
        let scene, errors = Contexts.resolve_scene ?previous ~state:core.cook.state ~live:frame_input
          core.doc ~time in
        scene, (if errors = [] then None else Some (String.concat "; "
          (List.map Flow.Diagnostic.to_string errors))) in
  let canvases, context_error = List.fold_left (fun (pictures, error) (leaf : Pxui_shell.Layout.leaf) ->
    match leaf.panel with
    | Canvas key ->
        let _, _, w, h = if not (V.ui_visible control) && core.focus = Canvas key
          then (0, 0, raw_frame.width, raw_frame.height) else leaf.body in
        let drawing = Option.bind core.doc.Document.shell (fun shell -> List.assoc_opt key shell.canvases) in
        let _, lowered = core.doc.workspace in
        let same_plan = (snd value.core.doc.workspace).plan == lowered.plan in
        let previous = List.assoc_opt key value.canvases in
        let dynamic = match previous with
          | Some picture when same_plan -> picture.dynamic
          | _ -> lowered.states <> [] || Array.exists (fun (n : Flow.Eval.node) ->
              List.exists (fun (_, v) -> Flow.Eval.is_live v) n.args) lowered.plan.nodes in
        (match drawing with
         | None -> pictures, error
         | Some _ when same_plan && not dynamic && Option.fold ~none:false
             ~some:(fun picture -> picture.size = (w, h)) previous ->
             (key, Option.get previous) :: pictures, error
         | Some drawing ->
             let prepared = match previous with
               | Some {prepared = Some p; _} when same_plan -> Ok p
               | _ -> Sketch_support.Drawing.prepare ~profile:lowered.profile ~states:lowered.states lowered.plan drawing in
             (match Result.bind prepared (fun p -> Result.map (fun scene -> p, scene)
                 (Sketch_support.Drawing.render_prepared ~state:core.cook.state p ~live:frame_input ~size:(w, h))) with
              | Ok (prepared, scene) -> (key, {size = (w, h); dynamic; scene; prepared = Some prepared}) :: pictures, error
              | Error d -> (key, Option.value ~default:{size = (w, h); dynamic; scene = []; prepared = None} previous) :: pictures,
                  Some (Flow.Diagnostic.to_string d)))
    | _ -> pictures, error) ([], context_error) (Core.geometry core core.workspace raw_frame).leaves in
  let rendered, views, drawn = compose { value with core } { update with core } ~baked ~baked_views ~scene in
  let rendering = {focused with core; extra; camera; rendered; views} in
  let bodies = if V.ui_visible control then Core.view_bodies core raw_frame
    else ["@hidden", (0, 0, raw_frame.width, raw_frame.height)] in
  let extra = V.render extra ~pixel_scale:raw_frame.pixel_scale ~focus:(Some (focus_key rendering))
    (List.filter_map (fun (key, bounds) ->
      let scene = if key = "@hidden" then focused_image rendering else
        match List.assoc_opt key views with Some scene -> Some scene | None -> rendered in
      Option.map (fun scene ->
        key, V.film extra ~key:(look_key rendering key) bounds, camera_of rendering key, scene) scene) bodies) in
  let core = { core with Core.view_tools = V.header_tools extra } in
  (* what the panes draw over a view: the gate where it is not the whole pane, and the
     selected object's box in the focused view *)
  let core = { core with
    Core.gates = List.filter_map (fun (key, bounds) ->
      let film = V.film extra ~key:(look_key rendering key) bounds in
      if film = bounds || key = "@hidden" then None else Some (key, film)) bodies;
    selected_box = Option.bind (Core.selected_bounds core) (fun (world, box, name) ->
      let key = focus_key rendering in
      Option.bind (List.assoc_opt key bodies) (fun bounds ->
        Option.map (fun rect -> key, rect, name)
          (V.screen_box (camera_of rendering key) ~bounds:(V.film extra ~key:(look_key rendering key) bounds) ~world box))) } in
  (* the render clock: a restart of the samples starts it, reaching the cap stops it *)
  let core = { core with Core.traces = List.filter_map (fun (key, _) ->
    Option.map (fun (film, samples, cap, bounces) ->
      let now = frame.Frame.time in
      let seconds, since = match List.assoc_opt key value.core.Core.traces with
        | Some (t : Core.trace) when samples >= t.samples && t.film = film ->
            (if t.samples >= cap then t.seconds else now -. t.since), t.since
        | _ -> 0., now in
      key, { Core.film; samples; cap; bounces; seconds; since })
      (V.trace extra ~key:(look_key rendering key))) bodies } in
  let map = match baked, value.map with
    | Some baked, Some (source, image) when baked == source || not core.Core.map_view ->
        ignore baked; Some (source, image)
    | Some baked, previous when core.Core.map_view ->
        let width, height, rgba = map_rgba baked in
        (match Image.upload_rgba ?into:(Option.map snd previous) ~width ~height ~rgba () with
         | Ok image -> Some (baked, image)
         | Error _ -> previous)
    | _, previous -> previous in
  let pending_render = match List.rev requests with
    | request :: _ -> Some request | [] -> None in
  let render_status = if pending_render <> None && rendered = None then
      Some "Render unavailable until the first cook completes" else render_status in
  let value = refresh_hidden { value with core; camera; cameras = focused.cameras; viewing = focused.viewing;
    control; rendered; views; drawn;
    composed = Some (composition_key core scene); resolved = Some (core.doc, frame_input, scene);
    context_error; canvases; baked; baked_from; baked_views; map; world_drag; pick_press;
    pending_render; render_status; extra; source } raw_frame in
  (* Sketch commands run last, on the finished frame's model. *)
  let value = List.fold_left (fun value -> function
    | Leader.Sketch_command id -> (List.find (fun (c : _ Editor_core.Command.t) ->
        c.id = id) value.commands).action value
    | _ -> value) value update.actions in
  let workspace,lowered=value.core.doc.workspace in
  let value=match Workspace_host.update value.host ~state:value.core.cook.state
      ~live:frame_input workspace lowered.plan with
    |Ok()->value|Error diagnostic->{value with context_error=Some(Flow.Diagnostic.to_string diagnostic)}in
  autosave value ~now:frame.Frame.time, inspected

let update value frame = fst (update_with value frame ~inspector:ignore)

let after_present value frame =
  let value=match Workspace_host.save_pending value.host Canvas.save_screen_png with
    |Ok()->value|Error diagnostic->{value with context_error=Some(Flow.Diagnostic.to_string diagnostic)}in
  match save_status ~save:V.save ~filename:V.filename
      value.pending_render value.rendered with
  | Some status -> refresh_hidden
      { value with render_status = Some status; pending_render = None } frame
  | None -> value

let scene value frame =
  compose_view ?map:(Option.map snd value.map) ~ui_visible:(V.ui_visible value.control)
    ~canvases:value.canvases
    ~background:value.background ~rendered:value.rendered ~views:value.views
    ~focused:(focused_image value)
    ~camera:(view_camera value) ~camera_of:(camera_of value) ~paint_view:(paint_view value)
    ~film:(V.film value.extra ~key:(focus_key value)) ~overlay:value.overlay
    ~guides:(fun bounds -> if value.core.Core.map_view then [] else
      V.guides ~scene:(Core.scene value.core)
      ~selected:(Core.selected_node value.core) ~space:(Core.space value.core)
      (view_camera value) value.extra ~pane:bounds
      ~bounds:(V.film value.extra ~key:(focus_key value) bounds))
    ~cache:value.hidden_scene_cache value.core frame

(* A crash report's editor part: the document as a loadable preset and a
   summary of the view state and undo history. *)
let crash_dump value directory =
  let core = value.core in
  (* document.txt is the text of any document; document.rays is the
     loadable preset, written for workspace documents *)
  Out_channel.with_open_text (Filename.concat directory "document.txt") (fun channel ->
    output_string channel (Document.dump core.doc));
  ignore (Preset.save ~directory ~name:"document" ~doc:core.doc
    ~view:(V.section value.camera value.extra));
  let history = core.history in
  Out_channel.with_open_text (Filename.concat directory "editor.txt") (fun channel ->
    Printf.fprintf channel
      "level: %s\nprojection: %s\npane graph: %s\ngraph panels: %s\nwindows: %s\npanels: %s\nroute: %s\ntext: %s\nmap view: %b\ngraph pan: %b\nguide: %b\nkey hud: %s\nselected: %s\nscope selected: %s\nfocus: %s\nprompt: %s\n\
       undo: %s (%d entries)\nredo: %s\ncook: %s\nedit error: %s\nrenderer: %s\nlive scene: %s\nautosave: %s\n\
       load document.rays with Space b (workspace documents only) after copying it to %s\n"
      (Core.level_name core)
      (match Core.projection core with Core.List_view -> "list"
        | Graph_view -> "graph" | Text_view -> "text")
      (Option.value ~default:"-" (Core.graph_name core))
      (Core.graph_panels core) (Core.windows core) (Core.panels_line core)
      (Core.route core)
      (Text_pane.summary core.text)
      core.map_view (Pxui_graph.Scope.Private.grabbed core.scope_view) core.guide (Option.fold ~none:"-" ~some:fst core.hud)
      (Option.fold ~none:"none" ~some:(fun node ->
        Printf.sprintf "%s (#%d, %s)" (Node.label node) (Node.id node) (Node.operation node))
        (Core.selected_node core))
      (match Pxui_graph.Scope.selected core.scope_view with
       | [] -> "-"
       | paths -> String.concat ", " (List.map (String.concat "/") paths))
      (Leader.pane_name core.focus) (Core.prompt_name core)
      (Editor_core.History.label history) (Editor_core.History.depth history)
      (Option.value ~default:"-" (Editor_core.History.redo_label history))
      (Core.status_text core)
      (Option.value ~default:"-" core.edit_error)
      (Option.value ~default:"-" (V.render_status value.extra))
      (Option.value ~default:"-" value.context_error)
      (Option.value ~default:"-" value.state_error) core.presets;
    Printf.fprintf channel "last edit: %.3f ms\nphases: %s\n"
      (core.edit_phases.total *. 1000.) (Flow.Phase_timer.summary core.edit_phases))

let close value =
  let value = autosave ~force:true value ~now:value.state_checked in
  Option.iter prerr_endline value.state_error;
  Option.iter (fun (_, image) -> Image.destroy image) value.map;
  Workspace_host.close value.host;
  V.close value.extra;
  Core.close value.core

let run ?inputs ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights
    ?world ?camera ?lens ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes
    ~config ~workspace ?source ~prepare ~draw ?overlay ?status () =
  let name = Option.value name ~default:(Workspace_doc.name workspace) in
  let init _frame = create ?inputs ?layout ~name ?presets ?timeline_frames ?factories ?settings
      ?commands ?lights ?world
      ?camera ?lens ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes
      ~workspace ?source ~prepare ~draw ?overlay ?status () |> Result.get_ok in
  let update value frame =
    let value = update value frame in
    (* a cursor the platform refuses is said in the strip; the editor runs on *)
    match set_ui_cursor value.core.ui (V.ui_visible value.control) with
    | Ok () -> value
    | Error message -> { value with render_status = Some ("Cursor: " ^ message) } in
  ignore (Sketch.run_state ~config ~init ~update ~view:scene
    ~after_present ~crash_dump ~on_stop:close ())
