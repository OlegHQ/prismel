open Prismel
open Procedural
open Common

let set_ui_cursor ui visible =
  let shape = match if visible then Pxui.Ui.cursor ui else None with
    | Some shape -> (shape :> [`Default|`Horizontal_resize|`Vertical_resize])
    | None -> `Default in
  match Sketch.set_cursor shape with Ok () -> () | Error error -> failwith error

(* What a dimensional adapter supplies to the one environment: camera widgets
   and navigation, still-image painting, view persistence, and any mode state
   of its own ([extra]). Every hook is pure over the environment's values. *)
module type VIEWPORT = sig
  type camera
  type control
  type rendered
  type request
  type extra
  type view  (** The camera the view paints with. *)

  val keymap : Leader.command list
  val scene_level : bool
  (** A scene of objects above the SOP network (3D); without it the editor
      shows one geometry object's network (2D). *)

  val default_camera : unit -> camera
  val seed_scene : ?lens:Camera.lens -> camera -> Edit_graph.factory list ->
    Edit_graph.t -> Edit_graph.t
  (** Scene objects every document starts with, e.g. a default camera with
      [lens]. *)

  val compose : scene:Edit_graph.t -> world:World.baked option ->
    (Mat4.t * bool * rendered) list -> rendered
  (** One picture of the visible objects, each drawn by the sketch and placed
      at its world transform ([true]: ghosted, outside the open object), lit
      by the scene's light objects and World. *)
  val init : 'p Core.t -> camera -> 'p Core.t * extra
  val create_control : unit -> control
  val ui_visible : control -> bool
  val toggle_ui : control -> control
  val open_camera : control -> control
  val begin_frame : extra -> Frame.t -> extra * Frame.t
  (** Strip mode-owned input (3D fly) before the shell sees the frame. *)

  val panel : Pxui.Ui.t -> control:control -> camera:camera -> extra:extra ->
    inspector:(Pxui.Ui.t -> 'a) -> control * camera * request list * extra * 'a
  val section : camera -> extra -> Yojson.Safe.t
  val restore : camera -> extra -> Yojson.Safe.t -> camera * extra
  val apply_action : camera -> extra -> Leader.action -> extra * string option
  (** Adapter-owned leader actions; [Some status] replaces the render status. *)

  val on_doc : previous:'p Core.t -> 'p Core.t -> camera -> 'p Core.t
  val navigate : area:Workspace.bounds -> control -> camera -> extra ->
    'p Core.t -> raw_frame:Frame.t -> input:Frame.t -> camera * extra
  val frame_bounds : viewport:Workspace.bounds -> min:Vec3.t -> max:Vec3.t ->
    camera -> camera
  val on_view : 'p Core.t -> previous:camera -> camera -> extra -> time:float ->
    'p Core.t * camera * extra
  val view_camera : camera -> extra -> pending:bool -> view
  val film : extra -> Workspace.bounds -> Workspace.bounds
  (** The rect of the view the render fills: the whole view, or the render
      camera's aspect fitted into it while looking through. *)
  val paint : Workspace.bounds -> view -> rendered -> Scene.t
  val guides : scene:Edit_graph.t -> selected:Node.t option -> space:Mat4.t ->
    view -> extra -> bounds:Workspace.bounds -> Scene.t
  (* Editor-only lines over the view (cameras, lights, axes, handles), screen
     space. [space] is the transform the selected node's parameters live in. *)

  val handles : Pxui.Ui.t -> selected:Node.t option -> scene:Edit_graph.t ->
    space:Mat4.t -> view -> extra -> bounds:Workspace.bounds ->
    (string * Parameter.value) list * bool * int option
  (* The selected node's handle boxes: parameter edits, whether a handle
      holds the pointer (the camera then ignores it), and a scene object a
      click picked. *)
  val save : request -> (unit, string) result
  val filename : request -> string
  val close : extra -> unit
end

type ('rendered, 'camera) hidden_scene_cache = {
  width : int;
  height : int;
  rendered : 'rendered option;
  camera : 'camera;
  background : Color.t;
  view_visible : bool;
  scene : Scene.t;
}

(* A World bake for this frame: the preview size while a gesture or the
   day cycle is live, the final size when idle. *)
let bake_world ~previous core ~live =
  Option.map (fun world ->
    let width, height = if live then 512, 256 else 2048, 1024 in
    match previous with
    (* The same World keeps the same bake value, so renderers see no change. *)
    | Some (last, baked) when last = world && (baked : World.baked).camera.width = width ->
        world, baked
    | Some _ | None -> world, World.bake_cached ~width ~height world)
    (Core.world core ~time:(Sketch_support.Timeline.time (Core.timeline core)))

let save_status ~save ~filename pending rendered =
  match pending, rendered with
  | Some request, Some _ ->
      Some (match save request with
        | Ok () -> "Saved " ^ filename request
        | Error message -> "Render failed: " ^ message)
  | _ -> None

let world ~paint_view ~camera ~rendered ~view_visible viewport =
  match rendered with
  | Some image when view_visible -> paint_view viewport camera image
  | Some _ | None -> []

let hidden_only ~ui_visible core =
  not ui_visible && core.Core.leader = Leader.Idle

(* The fully hidden scene, reused while its inputs are physically unchanged
   so the renderer sees the same [Scene.t]. *)
let hidden_entry ~background ~rendered ~camera ~paint_view ~cache core
    (frame : Frame.t) =
  let view_visible = Core.column_visible core Workspace.View in
  match cache with
  | Some cached when cached.width = frame.width
      && cached.height = frame.height && cached.rendered == rendered
      && cached.camera == camera && cached.background = background
      && cached.view_visible = view_visible -> cached
  | _ ->
      let scene = Scene.clear background ::
        world ~paint_view ~camera ~rendered ~view_visible
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

let compose_view ?map ~ui_visible ~background ~rendered ~camera ~paint_view ~film ~overlay
    ~guides ~cache core (frame : Frame.t) =
  let view_visible = Core.column_visible core Workspace.View in
  let world = match map with
    | Some image when view_visible && core.Core.map_view -> (fun viewport ->
        let x, y, w, _ = map_rect viewport in
        [Scene.image image ~at:(x, y)
           ~scale:(float w /. float (max 1 (Image.get_width image))) ()])
    | _ -> world ~paint_view ~camera ~rendered ~view_visible in
  if hidden_only ~ui_visible core then
    (hidden_entry ~background ~rendered ~camera ~paint_view ~cache core frame).scene
  else if not ui_visible then
    Scene.clear background :: world (0, 0, frame.width, frame.height)
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
    Scene.clear background :: world viewport @ overlay
    @ Core.machinery core ~all_ui_visible:true

(* The one environment: [Core] plus a dimensional viewport. *)
module Make (V : VIEWPORT) = struct
  type layout = Pxui_shell.Layout.config
  let default_layout = Pxui_shell.Layout.default

  type 'prepared t = {
    core : 'prepared Core.t;
    camera : V.camera;
    control : V.control;
    draw : Graph.t -> 'prepared -> V.rendered;
    overlay : Graph.t -> 'prepared option -> Frame.t -> Scene.t;
    status : 'prepared option -> string option;  (* sketch text in the status bar *)
    rendered : V.rendered option;
    drawn : ('prepared * V.rendered) Document.Layout.t;  (* per object *)
    baked : World.baked option;
    baked_from : (World.t * World.baked) option;
    map : (World.baked * Image.t) option;  (* the lat-long view's upload *)
    render_status : string option;
    pending_render : V.request option;
    background : Color.t;
    extra : V.extra;
    hidden_scene_cache : (V.rendered, V.view) hidden_scene_cache option;
    commands : (Workspace.column, 'prepared t -> 'prepared t) Editor_core.Command.t list;
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

  let create ?(layout = Pxui_shell.Layout.default) ?name ?presets ?timeline_frames ?factories
      ?settings ?(commands = []) ?(lights = []) ?world
      ?(camera = V.default_camera ()) ?lens ?(background = Color.hex_exn "#09090b")
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~graph ~prepare ~draw
      ?(overlay = fun _ _ _ -> Scene.empty) ?(status = fun _ -> None) () =
    Result.map (fun core ->
      let core, extra = V.init core camera in
      { core; camera; control = V.create_control (); draw; overlay; status;
        rendered = None; drawn = Document.Layout.empty; baked = None; baked_from = None; map = None;
        render_status = None; pending_render = None;
        background; extra; hidden_scene_cache = None; commands })
      (Core.create ?settings ?world ~scene_level:V.scene_level
        ~keymap:(V.keymap @ List.map (fun (c : _ Editor_core.Command.t) ->
          { c with action = Leader.Sketch_command c.id }) commands)
        ~seed_scene:(fun factories scene ->
          V.seed_scene ?lens camera factories (seed_lights lights scene))
        ~layout ?name ?presets ?timeline_frames ?factories ?seed ?grain ?domains
        ?max_entries ?max_payload_bytes ~graph ~prepare ())

  let graph value = Core.graph value.core
  let document value = Core.document value.core
  let prepared value = Core.prepared value.core
  let camera value = value.camera
  let extra value = value.extra
  let timeline value = Core.timeline value.core
  let selected_node value = Core.selected_node value.core
  let displayed_node value = Core.displayed_node value.core
  let panes value frame = Core.panes value.core frame
  let graph_nodes value = Pxui_graph.node_views value.core.graph_view
  let can_undo value = Editor_core.History.can_undo value.core.Core.history
  let can_redo value = Editor_core.History.can_redo value.core.Core.history
  let level value = match value.core.Core.level with
    | Document.Scene -> None
    | Inside id -> Some (Option.fold ~none:"" ~some:Node.label
        (Edit_graph.find (Core.scene value.core) ~node_id:id))
  let scene_document value = Core.scene value.core
  let lights value = Objects.lights ~render:true (Core.scene value.core)
  let world value = value.baked
  let objects value = List.map (fun (matrix, (piece : _ Cook.piece)) ->
      matrix, piece.prepared) (Core.placed_pieces ~render:true value.core)

  let settings value = Core.settings value.core
  let set_settings value settings =
    { value with core = Core.set_settings value.core settings }

  let view_camera value = V.view_camera value.camera value.extra
      ~pending:(value.pending_render <> None)

  let paint_view value viewport view rendered = V.paint (V.film value.extra viewport) view rendered

  let film value frame =
    let (x, y, _, _) as pane = (Core.panes value.core frame).view in
    let fx, fy, w, h = V.film value.extra pane in
    fx - x, fy - y, w, h

  let take_export value = match value.pending_render with
    | Some request -> { value with pending_render = None }, Some (V.filename request)
    | None -> value, None

  let set_render_status value render_status = { value with render_status }

  (* The hidden-scene cache is model state: refreshed here, read by [scene]. *)
  let refresh_hidden value frame =
    let hidden_scene_cache =
      if hidden_only ~ui_visible:(V.ui_visible value.control) value.core then
        Some (hidden_entry ~background:value.background ~rendered:value.rendered
          ~camera:(view_camera value) ~paint_view:(paint_view value)
          ~cache:value.hidden_scene_cache value.core frame)
      else None in
    { value with hidden_scene_cache }

  (* Recompose when a cook, the scene, or the World changed. Each object's
     drawing is reused while its prepared value is physically the same, so
     moving an object only re-places it. *)
  let compose value (update : (_, _) Core.update) ~baked =
    if not (update.prepared_changed || update.scene_changed || update.effects.view
        || update.effects.export || baked != value.baked || value.rendered = None)
    then value.rendered, value.drawn
    else
      let placed = Core.placed_pieces update.core in
      let drawn = List.fold_left (fun drawn (_, (piece : _ Cook.piece)) ->
          match Document.Layout.find_opt piece.id value.drawn with
          | Some (prepared, rendered) when prepared == piece.prepared ->
              Document.Layout.add piece.id (prepared, rendered) drawn
          | Some _ | None ->
              Document.Layout.add piece.id
                (piece.prepared, value.draw piece.graph piece.prepared) drawn)
          Document.Layout.empty placed in
      let waiting = placed = [] && Core.geometry_objects update.core <> []
          && Core.pieces update.core = [] in
      let ghost id = match update.core.Core.level with
        | Document.Inside open_id -> Core.kind update.core open_id = Some "geometry"
            && id <> open_id
        | Scene -> false in
      (if waiting then None
       else Some (V.compose ~scene:(Core.scene update.core) ~world:baked
         (List.map (fun (matrix, (piece : _ Cook.piece)) ->
           matrix, ghost piece.id, snd (Document.Layout.find piece.id drawn)) placed))),
      drawn

  let update_with value frame ~inspector =
    let ui = value.core.Core.ui in
    let raw_frame = frame in
    let extra, frame = V.begin_frame value.extra frame in
    let visible = V.ui_visible value.control in
    let camera_panel () = V.panel ui ~control:value.control ~camera:value.camera
        ~extra ~inspector in
    let view_handles ui ~selected ~space ~bounds =
      V.handles ui ~selected ~scene:(Core.scene value.core) ~space (view_camera value)
        extra ~bounds in
    let update = Core.update value.core ~all_ui_visible:visible
        ~text_focus:(Pxui.Ui.text_input_focused ui) ~camera_panel ~view_handles
        ~render_status:(match value.status (Core.prepared value.core), value.render_status with
          | Some sketch, Some render -> Some (sketch ^ " · " ^ render)
          | sketch, None -> sketch | None, render -> render)
        ~view_state:(function
          | Some (_, camera, _, extra, _) -> V.section camera extra
          | None -> V.section value.camera extra) frame in
    let core = update.core and panes = Core.panes update.core frame in
    let control, camera, requests, extra, inspected = match update.panel with
      | Some (control, camera, requests, extra, inspected) ->
          control, camera, requests, extra, Some inspected
      | None -> value.control, value.camera, [], extra, None in
    let camera, extra = match update.loaded_view with
      | Some json -> V.restore camera extra json
      | None -> camera, extra in
    let control, extra, render_status = List.fold_left
        (fun (control, extra, status) -> function
          | Leader.Hide_ui -> V.toggle_ui control, extra, status
          | Open_camera -> V.open_camera control, extra, status
          | action ->
              let extra, notice = V.apply_action camera extra action in
              control, extra, (if notice = None then status else notice))
        (control, extra, value.render_status) update.actions in
    let core = V.on_doc ~previous:value.core core camera in
    let area = if visible then panes.view
      else 0, 0, frame.Frame.width, frame.height in
    (* The view's own World gestures: dragging on the lat-long map moves the
       selected layer; Shift-drag in 3D turns the World. *)
    let held = Frame.mouse_down Input.LeftButton update.input
      && update.input.mouse_delta <> (0., 0.) in
    let in_view (px, py) = let x, y, w, h = area in
      px >= float x && py >= float y && px < float (x + w) && py < float (y + h) in
    let core, gesture = match Core.world_id core with
      | Some world when held && in_view update.input.mouse && core.Core.map_view ->
          (match Core.selected_node core, map_uv area update.input.mouse with
           | Some node, Some (u, v) when List.exists (fun (field : Parameter.field_view) ->
               field.name = "azimuth") (Node.parameter_fields node) ->
               let d = World.direction_of_uv u v in
               let rotation = match (Core.world core ~time:0.) with
                 | Some world -> world.World.rotation | None -> 0. in
               let degrees radians = radians *. 180. /. Float.pi in
               let azimuth = Float.atan2 d.Vec3.x (-. d.z) -. rotation in
               let azimuth = Float.rem (azimuth +. (3. *. Float.pi)) (2. *. Float.pi) -. Float.pi in
               Core.edit_node core (Document.Inside world) (Node.id node) ~label:"Move layer"
                 [ "azimuth", Parameter.Float_value (degrees azimuth);
                   "elevation", Parameter.Float_value (degrees (Float.asin d.y)) ], true
           (* The Sun layer: dragging places the sun, unlinked from the time. *)
           | Some node, Some (u, v) when Node.operation node = "sun" ->
               let d = World.direction_of_uv u v in
               let rotation = match Core.world core ~time:0. with
                 | Some world -> world.World.rotation | None -> 0. in
               let degrees radians = radians *. 180. /. Float.pi in
               let azimuth = Float.rem (Float.atan2 d.Vec3.x (-. d.z) -. rotation
                   +. (3. *. Float.pi)) (2. *. Float.pi) -. Float.pi in
               Core.edit_node core Document.Scene world ~label:"Move sun"
                 [ "sun_linked", Parameter.Bool_value false;
                   "sun_azimuth", Parameter.Float_value (degrees azimuth);
                   "sun_elevation", Parameter.Float_value
                     (Float.max (-10.) (degrees (Float.asin d.y))) ], true
           | _ -> core, true)
      | Some world when held && in_view update.input.mouse
          && List.mem Input.Shift update.input.keys ->
          let turned = Option.bind (Edit_graph.find (Core.scene core) ~node_id:world)
              (fun node -> List.find_map (fun (field : Parameter.field_view) ->
                match field.name, field.current with
                | "rotation", Parameter.Float_value degrees ->
                    Some (degrees +. 0.5 *. fst update.input.mouse_delta)
                | _ -> None) (Node.parameter_fields node)) in
          (match turned with
           | Some degrees ->
               let degrees = Float.rem (degrees +. 540.) 360. -. 180. in
               Core.edit_node core Document.Scene world ~label:"Rotate World"
                 ["rotation", Parameter.Float_value degrees], true
           | None -> core, false)
      | _ -> core, core.Core.map_view in
    let camera, extra = if gesture then camera, extra
      else V.navigate ~area control camera extra core ~raw_frame ~input:update.input in
    let camera, render_status = match update.framed with
      | Some (Some (min, max)) ->
          V.frame_bounds ~viewport:panes.view ~min ~max camera, render_status
      | Some None -> camera, Some "Nothing to frame: no cooked points"
      | None -> camera, render_status in
    let core, camera, extra = V.on_view core ~previous:value.camera camera extra
        ~time:frame.Frame.time in
    let live = (Frame.mouse_down Input.LeftButton frame
                && (Core.in_world core || List.mem Input.Shift frame.keys))
      || Sketch_support.Timeline.mode (Core.timeline core) = Sketch_support.Timeline.Playing in
    let baked_from = bake_world ~previous:value.baked_from core ~live in
    let baked = Option.map snd baked_from in
    let rendered, drawn = compose { value with core } { update with core } ~baked in
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
    let value = refresh_hidden { value with core; camera; control; rendered; drawn; baked; baked_from; map;
      pending_render; render_status; extra } raw_frame in
    (* Sketch commands run last, on the finished frame's model. *)
    List.fold_left (fun value -> function
      | Leader.Sketch_command id -> (List.find (fun (c : _ Editor_core.Command.t) ->
          c.id = id) value.commands).action value
      | _ -> value) value update.actions, inspected

  let update value frame = fst (update_with value frame ~inspector:ignore)

  let after_present value frame =
    match save_status ~save:V.save ~filename:V.filename
        value.pending_render value.rendered with
    | Some status -> refresh_hidden
        { value with render_status = Some status; pending_render = None } frame
    | None -> value

  let scene value frame =
    compose_view ?map:(Option.map snd value.map) ~ui_visible:(V.ui_visible value.control)
      ~background:value.background ~rendered:value.rendered
      ~camera:(view_camera value) ~paint_view:(paint_view value)
      ~film:(V.film value.extra) ~overlay:value.overlay
      ~guides:(fun bounds -> if value.core.Core.map_view then [] else
        V.guides ~scene:(Core.scene value.core)
        ~selected:(Core.selected_node value.core) ~space:(Core.space value.core)
        (view_camera value) value.extra ~bounds)
      ~cache:value.hidden_scene_cache value.core frame

  (* A crash report's editor part: the document as a loadable preset and a
     summary of the view state and undo history. *)
  let crash_dump value directory =
    let core = value.core in
    ignore (Preset.save ~directory ~name:"document" ~sketch:core.Core.name ~doc:core.doc
      ~view:(V.section value.camera value.extra));
    let history = core.history in
    Out_channel.with_open_text (Filename.concat directory "editor.txt") (fun channel ->
      Printf.fprintf channel
        "level: %s\nprojection: %s\nmap view: %b\nselected: %s\nfocus: %s\n\
         undo: %s (%d entries)\nredo: %s\ncook: %s\nedit error: %s\n\
         load document.json with Space b after copying it to %s\n"
        (Core.level_name core)
        (match Core.projection core with Core.List_view -> "list" | Graph_view -> "graph")
        core.map_view
        (Option.fold ~none:"none" ~some:(fun node ->
          Printf.sprintf "%s (#%d, %s)" (Node.label node) (Node.id node) (Node.operation node))
          (Core.selected_node core))
        (Leader.pane_name core.focus)
        (Editor_core.History.label history) (Editor_core.History.depth history)
        (Option.value ~default:"-" (Editor_core.History.redo_label history))
        (Core.status_text core)
        (Option.value ~default:"-" core.edit_error) core.presets)

  let close value =
    Option.iter (fun (_, image) -> Image.destroy image) value.map;
    V.close value.extra;
    Core.close value.core

  let run ?layout ?name ?presets ?timeline_frames ?factories ?settings ?commands ?lights
      ?world ?camera ?lens ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes
      ~config ~graph ~prepare ~draw ?overlay ?status () =
    let name = Option.value name ~default:(String.lowercase_ascii config.Sketch.title) in
    let init _frame = create ?layout ~name ?presets ?timeline_frames ?factories ?settings
        ?commands ?lights ?world
        ?camera ?lens ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes
        ~graph ~prepare ~draw ?overlay ?status () |> Result.get_ok in
    let update value frame =
      let value = update value frame in
      set_ui_cursor value.core.ui (V.ui_visible value.control);
      value in
    ignore (Sketch.run_state ~config ~init ~update ~view:scene
      ~after_present ~crash_dump ~on_stop:close ())
end
