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

  val keymap : Leader.binding list
  val default_camera : unit -> camera
  val seed_document : camera -> Edit_graph.factory list -> Edit_graph.t -> Edit_graph.t
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
  val paint : Workspace.bounds -> view -> rendered -> Scene.t
  val guides : document:Edit_graph.t -> selected:Node.t option -> view ->
    extra -> bounds:Workspace.bounds -> Scene.t
  (* Editor-only lines over the view (cameras, axes, handles), screen space. *)

  val handles : Pxui.Ui.t -> selected:Node.t option -> view -> extra ->
    bounds:Workspace.bounds -> (string * Parameter.value) list * bool
  (* The selected node's handle boxes: parameter edits, and whether a handle
      holds the pointer (the camera then ignores it). *)
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

let finish (update : (_, _) Core.update) ~core ~draw ~rendered ~requests ~status =
  let rendered = if update.prepared_changed || update.effects.view
      || update.effects.export then
      Option.map (draw (Core.displayed_node core)) (Core.prepared core)
    else rendered in
  let pending_render = match List.rev requests with
    | request :: _ -> Some request | [] -> None in
  let status = if pending_render <> None && rendered = None then
    Some "Render unavailable until the first cook completes" else status in
  rendered, pending_render, status

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
  not ui_visible && core.Core.leader <> Leader.Pending

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

let compose ~ui_visible ~background ~rendered ~camera ~paint_view ~overlay
    ~guides ~cache core (frame : Frame.t) =
  let view_visible = Core.column_visible core Workspace.View in
  let world = world ~paint_view ~camera ~rendered ~view_visible in
  if hidden_only ~ui_visible core then
    (hidden_entry ~background ~rendered ~camera ~paint_view ~cache core frame).scene
  else if not ui_visible then
    Scene.clear background :: world (0, 0, frame.width, frame.height)
    @ Core.machinery core ~all_ui_visible:false
  else
    let viewport = (Core.panes core frame).view in
    let x, y, width, height = viewport in
    let guides = if view_visible then guides viewport else [] in
    let overlay = [Scene.clip ~at:(x, y) ~w:width ~h:height
        (Scene.translate x y (overlay (Core.graph core) (Core.prepared core)
          (viewport_frame viewport frame)) :: guides)] in
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
    rendered : V.rendered option;
    render_status : string option;
    pending_render : V.request option;
    background : Color.t;
    extra : V.extra;
    hidden_scene_cache : (V.rendered, V.view) hidden_scene_cache option;
  }

  let create ?(layout = Pxui_shell.Layout.default) ?name ?presets ?timeline_frames ?factories
      ?(camera = V.default_camera ()) ?(background = Color.hex_exn "#09090b")
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~graph ~prepare ~draw
      ?(overlay = fun _ _ _ -> Scene.empty) () =
    Result.map (fun core ->
      let core, extra = V.init core camera in
      { core; camera; control = V.create_control (); draw; overlay;
        rendered = None; render_status = None; pending_render = None;
        background; extra; hidden_scene_cache = None })
      (Core.create ~keymap:V.keymap ~seed_document:(V.seed_document camera)
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

  let rerender value =
    let core = { value.core with Core.cook = Cook.force value.core.Core.cook } in
    { value with core;
      rendered = Option.map (value.draw (Core.displayed_node core))
          (Core.prepared core) }

  let view_camera value = V.view_camera value.camera value.extra
      ~pending:(value.pending_render <> None)

  (* The hidden-scene cache is model state: refreshed here, read by [scene]. *)
  let refresh_hidden value frame =
    let hidden_scene_cache =
      if hidden_only ~ui_visible:(V.ui_visible value.control) value.core then
        Some (hidden_entry ~background:value.background ~rendered:value.rendered
          ~camera:(view_camera value) ~paint_view:V.paint
          ~cache:value.hidden_scene_cache value.core frame)
      else None in
    { value with hidden_scene_cache }

  let update_with value frame ~inspector =
    let ui = value.core.Core.ui in
    let raw_frame = frame in
    let extra, frame = V.begin_frame value.extra frame in
    let visible = V.ui_visible value.control in
    let camera_panel () = V.panel ui ~control:value.control ~camera:value.camera
        ~extra ~inspector in
    let view_handles ui ~selected ~bounds =
      V.handles ui ~selected (view_camera value) extra ~bounds in
    let update = Core.update value.core ~all_ui_visible:visible
        ~text_focus:(Pxui.Ui.text_input_focused ui) ~camera_panel ~view_handles
        ~render_status:value.render_status
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
    let camera, extra = V.navigate ~area control camera extra core ~raw_frame
        ~input:update.input in
    let camera, render_status = match update.framed with
      | Some (Some (min, max)) ->
          V.frame_bounds ~viewport:panes.view ~min ~max camera, render_status
      | Some None -> camera, Some "Nothing to frame: no cooked points"
      | None -> camera, render_status in
    let core, camera, extra = V.on_view core ~previous:value.camera camera extra
        ~time:frame.Frame.time in
    let rendered, pending_render, render_status = finish update
        ~core ~draw:value.draw ~rendered:value.rendered ~requests
        ~status:render_status in
    refresh_hidden { value with core; camera; control; rendered; pending_render;
      render_status; extra } raw_frame, inspected

  let update value frame = fst (update_with value frame ~inspector:ignore)

  let after_present value frame =
    match save_status ~save:V.save ~filename:V.filename
        value.pending_render value.rendered with
    | Some status -> refresh_hidden
        { value with render_status = Some status; pending_render = None } frame
    | None -> value

  let scene value frame =
    compose ~ui_visible:(V.ui_visible value.control)
      ~background:value.background ~rendered:value.rendered
      ~camera:(view_camera value) ~paint_view:V.paint ~overlay:value.overlay
      ~guides:(fun bounds -> V.guides ~document:(Core.document value.core)
        ~selected:(Core.selected_node value.core) (view_camera value)
        value.extra ~bounds)
      ~cache:value.hidden_scene_cache value.core frame

  let close value =
    V.close value.extra;
    Core.close value.core

  let run ?layout ?name ?presets ?timeline_frames ?factories ?camera ?background
      ?seed ?grain ?domains ?max_entries ?max_payload_bytes ~config ~graph
      ~prepare ~draw ?overlay () =
    let name = Option.value name ~default:(String.lowercase_ascii config.Sketch.title) in
    let init _frame = create ?layout ~name ?presets ?timeline_frames ?factories
        ?camera ?background ?seed ?grain ?domains ?max_entries ?max_payload_bytes
        ~graph ~prepare ~draw ?overlay () |> Result.get_ok in
    let update value frame =
      let value = update value frame in
      set_ui_cursor value.core.ui (V.ui_visible value.control);
      value in
    ignore (Sketch.run_state ~config ~init ~update ~view:scene
      ~after_present ~on_stop:close ())
end
