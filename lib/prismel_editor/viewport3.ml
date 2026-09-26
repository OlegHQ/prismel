open Prismel
open Procedural

module CC = Pxui.Camera_control

type camera = Easy_camera.t
type control = CC.t
type rendered = Scene3.t
type request = CC.render_request
type view = Camera.t

(* What the view draws over the render while the UI shows. *)
type show = { cameras : bool; axes : bool; handles : bool }

(* Look-through, the fly speed while the pointer is captured, the
   active camera node's view, refreshed each update, and the guides. *)
type extra = { look_through : bool; fly : float option; render_camera : Camera.t;
               show : show }

let keymap = Leader.keymap3
let default_camera () = Easy_camera.create ~target:Vec3.zero ~distance:7. ()
let create_control () = CC.create ()
let ui_visible = CC.ui_visible
let toggle_ui = CC.toggle_ui
let open_camera = CC.open_camera
let set_relative enabled = ignore (Sketch.set_relative_mouse enabled)

(* ---- camera nodes: SOPs with operation "camera" (Sop_catalog.Camera). *)

let camera_ids document = Edit_graph.inspect document
  |> List.filter_map (fun (info : Edit_graph.node_info) ->
    if info.operation = "camera" then Some info.id else None)

let follows node = match Sop_catalog.Camera.of_node node with
  | Some (_, follow_viewport) -> follow_viewport | None -> false

let node_camera node = Option.map fst (Sop_catalog.Camera.of_node node)

let view_parameters easy =
  let camera = Easy_camera.camera easy in
  let eye = Camera.position camera and target = Camera.target camera in
  Sop_catalog.Camera.to_values ~eye ~target ~fov_y:(Easy_camera.fov_y easy)

let same_view a b =
  Vec3.nearly_equal (Camera.position a) (Camera.position b) ~eps:1e-6
  && Vec3.nearly_equal (Camera.target a) (Camera.target b) ~eps:1e-6
  && (match Camera.projection a, Camera.projection b with
    | Perspective a, Perspective b -> Float.abs (a.fov_y -. b.fov_y) < 1e-6
    | _ -> false)

let active_node (core : _ Core.t) = Option.bind (Pxui_graph.flagged core.graph_view)
    (fun node_id -> Edit_graph.find core.document ~node_id)

(* A default camera, following the viewport, when the catalog offers one. *)
let add_default_camera ~factories document easy =
  let ( let* ) = Result.bind in
  match List.find_opt (fun factory -> Edit_graph.factory_key factory = "camera")
      factories with
  | None -> None
  | Some factory ->
      Result.to_option (
        let* node = Edit_graph.instantiate factory [] in
        let* document = Edit_graph.add_node ~factory node document in
        let* document, _ = Edit_graph.apply_parameters document ~node_id:(Node.id node)
            (("follow_viewport", Parameter.Bool_value true) :: view_parameters easy) in
        Ok document)

let seed_document easy factories document =
  if camera_ids document <> [] then document
  else Option.value ~default:document
      (add_default_camera ~factories document easy)

(* One ACTIVE camera whenever any exists; losing the last one re-adds the
   default within the same undo entry. *)
let sync_cameras ~mode (core : _ Core.t) easy =
  let core = if camera_ids core.document <> [] then core
    else match add_default_camera ~factories:core.factories core.document easy with
      | Some document -> Core.environment_edit core mode document
      | None -> core in
  let ids = camera_ids core.document in
  let active = match Pxui_graph.flagged core.graph_view with
    | Some id when List.mem id ids -> Some id
    | Some _ | None -> (match ids with id :: _ -> Some id | [] -> None) in
  if active = Pxui_graph.flagged core.graph_view then core
  else { core with graph_view = Pxui_graph.with_flagged active core.graph_view }

let render_camera_of core easy = match active_node core with
  | Some node -> Option.value (node_camera node) ~default:(Easy_camera.camera easy)
  | None -> Easy_camera.camera easy

let init core camera =
  let core = sync_cameras ~mode:`Reset core camera in
  core, { look_through = false; fly = None;
          render_camera = render_camera_of core camera;
          show = { cameras = true; axes = true; handles = true } }

let begin_frame extra frame = match extra.fly with
  | None -> extra, frame
  | Some _ ->
      let ended, frame = Editor_core.Router.fly frame in
      if not ended then extra, frame
      else (set_relative false; { extra with fly = None }, frame)

let panel ui ~control ~camera ~extra ~inspector =
  let extra = Option.value ~default:extra
      (Pxui.Ui.accordion ui ~expanded:true "Viewport" (fun () ->
        let toggle = Pxui.Ui.toggle ui in
        let look_through = toggle "Look through render camera" extra.look_through in
        let cameras = toggle "Cameras" extra.show.cameras in
        let axes = toggle "Axis gizmo" extra.show.axes in
        let handles = toggle "Selected node handles" extra.show.handles in
        { extra with look_through; show = { cameras; axes; handles } })) in
  let control, camera, requests = CC.widgets control ui ~camera in
  control, camera, requests, extra, inspector ui

let section camera extra =
  Editor_core.Store.Viewport.encode3 camera ~look_through:extra.look_through
let restore camera extra json =
  let camera, look_through = Editor_core.Store.Viewport.decode3 camera json in
  camera, { extra with look_through }

let apply_action camera extra = function
  | Leader.Look_through -> { extra with look_through = not extra.look_through }, None
  | Fly when extra.fly = None ->
      set_relative true;
      { extra with fly = Some (Float.max 0.5 (Easy_camera.distance camera *. 0.5)) },
      Some "Flying: WASD/QE move, Shift x4, wheel speed, Esc exits"
  | _ -> extra, None

let on_doc ~previous core camera =
  if core.Core.document == previous.Core.document
      && Pxui_graph.flagged core.graph_view = Pxui_graph.flagged previous.graph_view
  then core else sync_cameras ~mode:`Amend core camera

let navigate ~area control camera extra core ~raw_frame ~input =
  let active = active_node core in
  let following = Option.fold ~none:false ~some:follows active in
  (* A fixed render camera owns the view while look-through is enabled. *)
  if extra.look_through && active <> None && not following then camera, extra
  else match extra.fly with
    | Some speed ->
        let camera, speed = Easy_camera.fly ~speed camera raw_frame in
        camera, { extra with fly = Some speed }
    | None -> CC.navigate ~control_area:area control camera input, extra

let frame_bounds ~viewport:_ ~min ~max camera = Easy_camera.frame_bounds ~min ~max camera

(* Follow-viewport motion changes the camera node in the same undo burst;
   node edits and undo pull the viewport back to the document. *)
let on_view core ~previous camera extra ~time =
  let core, camera = match active_node core with
    | Some node when follows node ->
        let moved = not (same_view (Easy_camera.camera previous)
            (Easy_camera.camera camera)) in
        (match node_camera node with
         | Some node_view when moved || not (same_view node_view (Easy_camera.camera camera)) ->
             if moved then
               match Edit_graph.apply_parameters core.Core.document ~node_id:(Node.id node)
                   (view_parameters camera) with
               | Ok (document, _) ->
                   Core.environment_edit core (`View time) document, camera
               | Error _ -> core, camera
             else core,
               (match Camera.projection node_view with
                | Perspective { fov_y; _ } -> Easy_camera.with_fov_y fov_y camera
                | _ -> camera)
               |> Easy_camera.of_view ~eye:(Camera.position node_view)
                    ~target:(Camera.target node_view)
         | Some _ | None -> core, camera)
    | Some _ | None -> core, camera in
  core, camera, { extra with render_camera = render_camera_of core camera }

(* The view shows the render camera while looking through it and on the
   frame whose framebuffer a PNG request captures. *)
let view_camera camera extra ~pending =
  if extra.look_through || pending then extra.render_camera
  else Easy_camera.camera camera

let paint viewport camera rendered = [Scene.view3d ~viewport ~camera rendered]

(* ---- guides and handles, in screen points over the view. *)

let axes = [| Vec3.create 1. 0. 0.; Vec3.create 0. 1. 0.; Vec3.create 0. 0. 1. |]
let axis_names = [| "x"; "y"; "z" |]
let axis_colors = Array.map Color.hex_exn [| "#e5484d"; "#46a758"; "#3e63dd" |]
let guide_color = Color.hex_exn "#a1a1aa"
let active_color = Color.hex_exn "#f5d90a"

let project bounds camera point = Option.map (fun (screen : Vec3.t) ->
  screen.x, screen.y) (Camera.world_to_screen ~viewport:bounds camera point)

let line ?(width = 1) color (x0, y0) (x1, y1) =
  Scene.line ~from_:(Float.to_int x0, Float.to_int y0)
    ~to_:(Float.to_int x1, Float.to_int y1) ~color ~width ()

let segment bounds view color a b =
  match project bounds view a, project bounds view b with
  | Some a, Some b -> [line color a b]
  | _ -> []

(* A pyramid half a unit deep with the view's aspect, and its aim. *)
let frustum bounds view color camera =
  let eye = Camera.position camera and target = Camera.target camera in
  let forward = Vec3.normalize (Vec3.sub target eye) in
  let side = Vec3.cross forward (Camera.up camera) in
  if Vec3.length side < 1e-6 then [] else
  let right = Vec3.normalize side in
  let up = Vec3.cross right forward in
  let fov_y = match Camera.projection camera with
    | Perspective { fov_y; _ } -> fov_y | _ -> 1. in
  let _, _, width, height = bounds in
  let half_h = 0.5 *. Float.tan (fov_y /. 2.) in
  let half_w = half_h *. float_of_int width /. float_of_int (max 1 height) in
  let centre = Vec3.add eye (Vec3.scale forward 0.5) in
  let corner sx sy = Vec3.add centre (Vec3.add (Vec3.scale right (sx *. half_w))
      (Vec3.scale up (sy *. half_h))) in
  let corners = [| corner (-1.) (-1.); corner 1. (-1.); corner 1. 1.; corner (-1.) 1. |] in
  let edge = segment bounds view color in
  List.concat (List.init 4 (fun index ->
    edge eye corners.(index) @ edge corners.(index) corners.((index + 1) mod 4))
    @ [edge (corner 0. 1.) (corner 0. 1.6); edge eye target])

(* ponytail: translate arrows on position-like xyz triples, found by name;
   add rotate/scale handles or a parameter role when a SOP needs them. *)
let handle_prefixes = ["translate"; "center"; "origin"; "eye"; "target"]
let arrow_length = 60.

type arrow = { name : string; value : float; axis : int;
               base : float * float; tip : float * float; unit : float * float }

(* The selected node's arrows; [unit] is one world unit along the axis on
   screen, so a drag maps back to a parameter delta. *)
let arrows node view bounds =
  let values = Node.parameter_fields node in
  let find name = List.find_map (fun (field : Parameter.field_view) ->
    match field.current with
    | Float_value value when field.name = name -> Some value
    | _ -> None) values in
  List.concat_map (fun prefix ->
    match find (prefix ^ "_x"), find (prefix ^ "_y"), find (prefix ^ "_z") with
    | Some x, Some y, Some z ->
        let point = Vec3.create x y z in
        (match project bounds view point with
         | None -> []
         | Some ((bx, by) as base) -> List.filter_map (fun axis ->
             Option.bind (project bounds view (Vec3.add point axes.(axis)))
               (fun (ux, uy) ->
                 let dx = ux -. bx and dy = uy -. by in
                 let length = Float.hypot dx dy in
                 if length < 1e-3 then None
                 else Some { name = prefix ^ "_" ^ axis_names.(axis);
                   value = [| x; y; z |].(axis); axis; base; unit = dx, dy;
                   tip = bx +. dx /. length *. arrow_length,
                         by +. dy /. length *. arrow_length }))
             [0; 1; 2])
    | _ -> []) handle_prefixes

let handles ui ~selected view extra ~bounds = match selected with
  | Some node when extra.show.handles ->
      List.fold_left (fun (edits, grab) arrow ->
        let tx, ty = arrow.tip in
        let box = Pxui.Ui.box ui ~flags:Pxui.Ui.clickable ~w:(Pxui.Ui.Px 14.)
            ~h:(Pxui.Ui.Px 14.) ~at:(tx -. 7., ty -. 7.) ("handle-" ^ arrow.name) in
        let signal = Pxui.Ui.signal ui box in
        let mx, my = signal.drag and ux, uy = arrow.unit in
        let delta = (mx *. ux +. my *. uy) /. (ux *. ux +. uy *. uy) in
        (if signal.held && delta <> 0. then
           (arrow.name, Parameter.Float_value (arrow.value +. delta)) :: edits
         else edits),
        grab || signal.held || signal.released)
        ([], false) (arrows node view bounds)
  | Some _ | None -> [], false

let gizmo (x, y, _, height) view =
  let cx = float_of_int x +. 40. and cy = float_of_int (y + height) -. 40. in
  let origin = Camera.world_to_camera view Vec3.zero in
  List.concat (List.init 3 (fun axis ->
    let d = Vec3.sub (Camera.world_to_camera view axes.(axis)) origin in
    let tip = cx +. d.x *. 28., cy -. d.y *. 28. in
    [line ~width:2 axis_colors.(axis) (cx, cy) tip;
     Scene.text ~at:(Float.to_int (fst tip) + 2, Float.to_int (snd tip) - 6)
       ~color:axis_colors.(axis) ~size:11 axis_names.(axis)]))

let guides ~document ~selected view extra ~bounds =
  let cameras = if not extra.show.cameras then [] else
    List.concat_map (fun node_id ->
      match Option.bind (Edit_graph.find document ~node_id) node_camera with
      | Some camera when not (same_view camera view) ->
          let active = Camera.position camera = Camera.position extra.render_camera
            && Camera.target camera = Camera.target extra.render_camera in
          frustum bounds view (if active then active_color else guide_color) camera
      | Some _ | None -> []) (camera_ids document) in
  let handles = match selected with
    | Some node when extra.show.handles ->
        List.concat_map (fun arrow ->
          let color = axis_colors.(arrow.axis) in
          [line ~width:2 color arrow.base arrow.tip;
           Scene.circle ~at:(Float.to_int (fst arrow.tip), Float.to_int (snd arrow.tip))
             ~radius:5 ~fill:color ()]) (arrows node view bounds)
    | Some _ | None -> [] in
  cameras @ (if extra.show.axes then gizmo bounds view else []) @ handles

let save = CC.save
let filename request = request.CC.filename
let close extra = if extra.fly <> None then set_relative false
