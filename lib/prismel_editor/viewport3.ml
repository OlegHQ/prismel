open Prismel
open Editor_document
open Procedural

module CC = Pxui.Camera_control

type camera = Easy_camera.t
type control = CC.t
type rendered = Scene3.t
type request = CC.render_request
type view = Camera.t

(* The view's handle tool: W translate, E rotate, R scale, Escape none. *)
type tool = Move | Turn | Grow | No_tool

(* What the view draws over the render while the UI shows. *)
type show = { cameras : bool; axes : bool; handles : bool }

(* Look-through, the fly speed while the pointer is captured, the
   active camera node's view and the free viewport's view with its lens
   (both refreshed each update, the latter physically stable while
   unchanged so hidden-scene caching holds), and the guides. *)
type extra = { look_through : bool; fly : float option; render_camera : Camera.t;
               free_view : Camera.t; render : Objects.Camera.render;
               following : bool option;  (* the ACTIVE camera follows the viewport *)
               follow_request : bool option;  (* the Viewport panel's toggle, applied on the next update *)
               show : show; tool : tool }

let keymap = Leader.keymap3
let scene_level = true
let default_camera () = Easy_camera.create ~target:Vec3.zero ~distance:7. ()
let create_control () = CC.create ()
let ui_visible = CC.ui_visible
let toggle_ui = CC.toggle_ui
let open_camera = CC.open_camera
let set_relative enabled = ignore (Sketch.set_relative_mouse enabled)

(* ---- camera objects: scene nodes with operation "camera" (Objects.Camera). *)

let camera_ids scene = Objects.ids "camera" scene

let follows node = match Objects.Camera.of_node node with
  | Some (_, follow_viewport) -> follow_viewport | None -> false

let node_camera node = Option.map fst (Objects.Camera.of_node node)

let view_parameters easy =
  let camera = Easy_camera.camera easy in
  let eye = Camera.position camera and target = Camera.target camera in
  Objects.Camera.to_values ~eye ~target ~fov_y:(Easy_camera.fov_y easy)

let same_view a b =
  Vec3.nearly_equal (Camera.position a) (Camera.position b) ~eps:1e-6
  && Vec3.nearly_equal (Camera.target a) (Camera.target b) ~eps:1e-6
  && (match Camera.projection a, Camera.projection b with
    | Perspective a, Perspective b -> Float.abs (a.fov_y -. b.fov_y) < 1e-6
    | _ -> false)

let active_node (core : _ Core.t) = Option.bind core.doc.active_camera
    (fun node_id -> Edit_graph.find (Core.scene core) ~node_id)

(* A default camera, following the viewport, when the catalog offers one. *)
let add_default_camera ?(lens = Camera.pinhole) ~factories document easy =
  let ( let* ) = Result.bind in
  match List.find_opt (fun factory -> Edit_graph.factory_key factory = "camera")
      factories with
  | None -> None
  | Some factory ->
      Result.to_option (
        let* node = Edit_graph.instantiate factory [] in
        let node = Node.relabel "camera1" node in
        let* document = Edit_graph.add_node ~factory node document in
        let* document, _ = Edit_graph.apply_parameters document ~node_id:(Node.id node)
            (("follow_viewport", Parameter.Bool_value true)
             :: Objects.Camera.lens_values lens @ view_parameters easy) in
        Ok document)

let camera_factories = [Objects.Camera.factory]

let seed_scene ?lens easy _ scene =
  if camera_ids scene <> [] then scene
  else Option.value ~default:scene
      (add_default_camera ?lens ~factories:camera_factories scene easy)

(* One ACTIVE camera whenever any exists; a nonempty scene losing the last
   camera re-adds the default within the same undo entry. An intentionally
   empty scene stays empty. *)
let sync_cameras ~mode (core : _ Core.t) easy =
  let core = if camera_ids (Core.scene core) <> []
      || Edit_graph.inspect (Core.scene core) = [] then core
    else match add_default_camera ~factories:camera_factories (Core.scene core) easy with
      | Some scene -> Core.scene_edit core mode scene
      | None -> core in
  let ids = camera_ids (Core.scene core) in
  let active = match core.doc.active_camera with
    | Some id when List.mem id ids -> Some id
    | Some _ | None -> (match ids with id :: _ -> Some id | [] -> None) in
  if active = core.doc.active_camera then core
  else Core.scene_edit core `Amend ~active_camera:active (Core.scene core)

let render_camera_of core easy = match active_node core with
  | Some node -> Option.value (node_camera node) ~default:(Easy_camera.camera easy)
  | None -> Easy_camera.camera easy

(* The viewport camera carrying the ACTIVE camera's lens, focused on the
   orbit target unless that camera follows the viewport. *)
let free_view_of ~render_camera ~previous camera =
  let view = Easy_camera.camera camera in
  let lens = Camera.lens render_camera in
  let view = Camera.with_lens (if same_view render_camera view then lens
                               else { lens with focus_distance = None }) view in
  match previous with Some previous when previous = view -> previous | _ -> view

let render_of core = Option.value ~default:Objects.Camera.default_render
    (Option.bind (active_node core) Objects.Camera.render_of_node)

let init core camera =
  let core = sync_cameras ~mode:`Reset core camera in
  let render_camera = render_camera_of core camera in
  core, { look_through = false; fly = None; render_camera;
          free_view = free_view_of ~render_camera ~previous:None camera;
          render = render_of core; following = Option.map follows (active_node core);
          follow_request = None;
          show = { cameras = true; axes = true; handles = true }; tool = Move }

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
        (* The ACTIVE camera's own parameter, here so a look-through can be
           set up by orbiting: on, the viewport drives the camera. *)
        let follow_request = match extra.following with
          | Some following ->
              let wanted = toggle "Camera follows viewport" following in
              if wanted <> following then Some wanted else None
          | None -> None in
        let cameras = toggle "Cameras and lights" extra.show.cameras in
        let axes = toggle "Axis gizmo" extra.show.axes in
        let handles = toggle "Selected node handles" extra.show.handles in
        { extra with look_through; follow_request; show = { cameras; axes; handles } })) in
  let control, camera, requests = CC.widgets control ui ~camera in
  control, camera, requests, extra, inspector ui

let section camera extra =
  Editor_core.Store.Viewport.encode3 camera ~look_through:extra.look_through
let restore camera extra json =
  let camera, look_through = Editor_core.Store.Viewport.decode3 camera json in
  camera, { extra with look_through }

let apply_action camera extra = function
  | Leader.Tool 0 -> { extra with tool = No_tool }, Some "Orbit (handles hidden)"
  | Tool 1 -> { extra with tool = Move }, Some "Translate (W)"
  | Tool 2 -> { extra with tool = Turn }, Some "Rotate (E)"
  | Tool 3 -> { extra with tool = Grow }, Some "Scale (R)"
  | Leader.Look_through -> { extra with look_through = not extra.look_through }, None
  | Fly when extra.fly = None ->
      set_relative true;
      { extra with fly = Some (Float.max 0.5 (Easy_camera.distance camera *. 0.5)) },
      Some "Flying: WASD/QE move, Shift x4, wheel speed, Esc exits"
  | _ -> extra, None

let on_doc ~previous core camera =
  if Core.scene core == Core.scene previous
      && core.Core.doc.active_camera = previous.Core.doc.active_camera
  then core else sync_cameras ~mode:`Amend core camera

let navigate ~area control camera extra core ~(raw_frame : Frame.t) ~(input : Frame.t) =
  let active = active_node core in
  let following = Option.fold ~none:false ~some:follows active in
  (* A fixed render camera owns the view while look-through is enabled. *)
  if extra.look_through && active <> None && not following then camera, extra
  else match extra.fly with
    | Some speed ->
        let camera, speed = Easy_camera.fly ~speed camera
          { raw_frame with events = input.events; keys = input.keys;
            mouse_buttons = input.mouse_buttons; mouse_delta = input.mouse_delta } in
        camera, { extra with fly = Some speed }
    | None -> CC.navigate ~control_area:area control camera input, extra

let frame_bounds ~viewport:_ ~min ~max camera = Easy_camera.frame_bounds ~min ~max camera

(* Follow-viewport motion changes the camera node in the same undo burst;
   node edits and undo pull the viewport back to the document. *)
let on_view core ~previous camera extra ~time =
  let core = match extra.follow_request, active_node core with
    | Some value, Some node ->
        Core.edit_node core Document.Scene (Node.id node)
          ["follow_viewport", Parameter.Bool_value value] ~label:"Follow viewport"
    | _ -> core in
  let core, camera = match active_node core with
    | Some node when follows node ->
        let moved = not (same_view (Easy_camera.camera previous)
            (Easy_camera.camera camera)) in
        (match node_camera node with
         | Some node_view when moved || not (same_view node_view (Easy_camera.camera camera)) ->
             if moved then
               match Edit_graph.apply_parameters (Core.scene core) ~node_id:(Node.id node)
                   (view_parameters camera) with
               | Ok (scene, _) ->
                   Core.scene_edit core (`View time) scene, camera
               | Error _ -> core, camera
             else core,
               (match Camera.projection node_view with
                | Perspective { fov_y; _ } -> Easy_camera.with_fov_y fov_y camera
                | _ -> camera)
               |> Easy_camera.of_view ~eye:(Camera.position node_view)
                    ~target:(Camera.target node_view)
         | Some _ | None -> core, camera)
    | Some _ | None -> core, camera in
  let render_camera = render_camera_of core camera in
  core, camera, { extra with render_camera;
    free_view = free_view_of ~render_camera ~previous:(Some extra.free_view) camera;
    render = render_of core; following = Option.map follows (active_node core);
    follow_request = None }

(* The view shows the render camera while looking through it and on the
   frame whose framebuffer a PNG request captures; otherwise the viewport
   camera carries the ACTIVE camera's lens, focused on the orbit target
   unless the node follows the viewport. *)
let view_camera _camera extra ~pending =
  if extra.look_through || pending then extra.render_camera else extra.free_view

(* Looking through the camera, the render fills the largest rect of the
   camera's aspect (its render resolution) centred in the pane; otherwise
   the whole pane. *)
let film extra (x, y, width, height) =
  if not extra.look_through then x, y, width, height else
  let aspect = float extra.render.width /. float (max 1 extra.render.height) in
  let w = min width (int_of_float (Float.round (float height *. aspect))) in
  let h = min height (int_of_float (Float.round (float width /. aspect))) in
  let w = max 1 w and h = max 1 h in
  x + ((width - w) / 2), y + ((height - h) / 2), w, h

let paint viewport camera rendered = [Scene.view3d ~viewport ~camera rendered]

(* Objects under their world transforms. Light objects light the scene when
   there are any; otherwise the first object's own lights do. *)
let compose ~scene ~world pieces =
  let lights = Objects.lights scene in
  let base = match pieces with (_, _, first) :: _ -> first | [] -> Scene3.empty in
  let module P = Scene3.Private in
  (match world with Some baked -> Scene3.with_world baked | None -> Fun.id) @@
  Scene3.create ~lights:(if lights <> [] || Objects.ids "light" scene <> [] then lights
      else P.lights base)
    ?shadow:(P.shadow base) ~ambient:(P.ambient base)
    ~separate_specular:(P.separate_specular base) ~samples:(P.samples base)
    (List.map (fun (matrix, ghost, scene3) ->
      let placed = Scene3.transform matrix (Scene3.nodes scene3) in
      (* ponytail: ghosts screen-blend without writing depth; a real
         override material would need a Scene3 material-override node. *)
      if ghost then Scene3.with_depth (Scene3.depth_state ~write:false ())
          [Scene3.with_blend Scene3.Screen [placed]]
      else placed) pieces)

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

(* Handles on the selected node's xyz parameter triples, found by name:
   W translates position-like triples, E rotates [rotate_*], R scales
   [scale_*]; Escape hides them so a drag only orbits. A camera's target
   also slides along the view direction: its focus distance. *)
let handle_prefixes = ["translate"; "center"; "origin"; "eye"; "target"]
let arrow_length = 60.

(* A handle: its box key, colour, tool, screen base and tip, [unit] (one
   world unit along its axis on screen, so a drag maps back to a delta),
   and the parameter edits a delta makes. A rotation turns its whole soft
   range per 360 points. *)
type arrow = { name : string; color : Color.t; tool : tool;
               base : float * float; tip : float * float; unit : float * float;
               edits : float -> (string * Parameter.value) list }

let arrows node view bounds space tool =
  let project point = project bounds view (Mat4.transform_point space point) in
  let values = Node.parameter_fields node in
  let find name = List.find_map (fun (field : Parameter.field_view) ->
    match field.current with
    | Float_value value when field.name = name -> Some value
    | _ -> None) values in
  let range name = List.find_map (fun (field : Parameter.field_view) ->
    match field.kind with
    | Floating_view range when field.name = name -> Some (range.soft_max -. range.soft_min)
    | _ -> None) values in
  let triple prefix = match find (prefix ^ "_x"), find (prefix ^ "_y"), find (prefix ^ "_z") with
    | Some x, Some y, Some z -> Some (x, y, z) | _ -> None in
  let pivot = List.find_map triple handle_prefixes in
  let arrow ~name ~color at direction ~per_pixel edits =
    match project at, project (Vec3.add at direction) with
    | Some ((bx, by) as base), Some (ux, uy) ->
        let dx = ux -. bx and dy = uy -. by in
        let length = Float.hypot dx dy in
        if length < 1e-3 then None
        else Some { name; color; tool; base; unit = dx, dy;
                    edits = (fun delta -> edits (delta *. per_pixel));
                    tip = bx +. dx /. length *. arrow_length,
                          by +. dy /. length *. arrow_length }
    | _ -> None in
  let handles prefix (x, y, z) at =
    List.filter_map (fun axis ->
      let name = prefix ^ "_" ^ axis_names.(axis) and value = [| x; y; z |].(axis) in
      arrow ~name ~color:axis_colors.(axis) at axes.(axis)
        ~per_pixel:(if tool = Turn then Option.value ~default:360. (range name) /. 360. else 1.)
        (fun delta -> [name, Parameter.Float_value (value +. delta)])) [0; 1; 2] in
  let at = match pivot with Some (x, y, z) -> Vec3.create x y z | None -> Vec3.zero in
  match tool with
  | No_tool -> []
  | Move ->
      let distance = match triple "eye", triple "target" with
        | Some (ex, ey, ez), Some (tx, ty, tz) ->
            let target = Vec3.create tx ty tz in
            let direction = Vec3.sub target (Vec3.create ex ey ez) in
            if Vec3.length direction < 1e-6 then [] else
            let direction = Vec3.normalize direction in
            Option.to_list (arrow ~name:"target_distance" ~color:active_color target
              direction ~per_pixel:1. (fun delta ->
                let p = Vec3.add target (Vec3.scale direction delta) in
                ["target_x", Parameter.Float_value p.x; "target_y", Parameter.Float_value p.y;
                 "target_z", Parameter.Float_value p.z]))
        | _ -> [] in
      List.concat_map (fun prefix -> match triple prefix with
        | Some ((x, y, z) as values) -> handles prefix values (Vec3.create x y z)
        | None -> []) handle_prefixes @ distance
  | Turn -> Option.fold ~none:[] ~some:(fun values -> handles "rotate" values at) (triple "rotate")
  | Grow -> Option.fold ~none:[] ~some:(fun values -> handles "scale" values at) (triple "scale")

let pick_size = 16.

(* Handle drags edit the selected node; a click on a camera guide's eye
   selects that camera object. *)
let handles ui ~selected ~scene ~space view extra ~bounds =
  let edits, grab = match selected with
    | Some node when extra.show.handles ->
        List.fold_left (fun (edits, grab) arrow ->
          let tx, ty = arrow.tip in
          let box = Pxui.Ui.box ui ~flags:Pxui.Ui.clickable ~w:(Pxui.Ui.Px 14.)
              ~h:(Pxui.Ui.Px 14.) ~at:(tx -. 7., ty -. 7.) ("handle-" ^ arrow.name) in
          let signal = Pxui.Ui.signal ui box in
          let mx, my = signal.drag and ux, uy = arrow.unit in
          let delta = match arrow.tool with
            | Turn -> (mx *. ux +. my *. uy) /. Float.hypot ux uy
            | Move | Grow | No_tool -> (mx *. ux +. my *. uy) /. (ux *. ux +. uy *. uy) in
          (if signal.held && delta <> 0. then arrow.edits delta @ edits else edits),
          grab || signal.held || signal.released)
          ([], false) (arrows node view bounds space extra.tool)
    | Some _ | None -> [], false in
  let grab, picked = if not extra.show.cameras then grab, None else
    List.fold_left (fun (grab, picked) node_id ->
      match Option.bind (Edit_graph.find scene ~node_id) node_camera with
      | Some camera when not (same_view camera view) ->
          (match project bounds view (Camera.position camera) with
           | Some (x, y) ->
               let box = Pxui.Ui.box ui ~flags:Pxui.Ui.clickable ~w:(Pxui.Ui.Px pick_size)
                   ~h:(Pxui.Ui.Px pick_size) ~at:(x -. pick_size /. 2., y -. pick_size /. 2.)
                   ("pick-camera-" ^ string_of_int node_id) in
               let signal = Pxui.Ui.signal ui box in
               grab || signal.held, (if signal.clicked then Some node_id else picked)
           | None -> grab, picked)
      | Some _ | None -> grab, picked) (grab, None) (camera_ids scene) in
  edits, grab, picked

let gizmo (x, y, _, height) view =
  let cx = float_of_int x +. 40. and cy = float_of_int (y + height) -. 40. in
  let origin = Camera.world_to_camera view Vec3.zero in
  List.concat (List.init 3 (fun axis ->
    let d = Vec3.sub (Camera.world_to_camera view axes.(axis)) origin in
    let tip = cx +. d.x *. 28., cy -. d.y *. 28. in
    [line ~width:2 axis_colors.(axis) (cx, cy) tip;
     Scene.text ~at:(Float.to_int (fst tip) + 2, Float.to_int (snd tip) - 6)
       ~color:axis_colors.(axis) ~size:11 axis_names.(axis)]))

(* A light object: a marker at its position, a line to its target. *)
let light_guide bounds view color (light : Light.t) =
  let marker (x, y) = [Scene.circle ~at:(Float.to_int x, Float.to_int y) ~radius:5
      ~fill:color ()] in
  let aim at direction = match project bounds view at with
    | Some point -> marker point @ segment bounds view color at
        (Vec3.add at (Vec3.scale direction 1.5))
    | None -> [] in
  match light.kind with
  | Directional { direction } -> aim (Vec3.scale direction (-4.)) direction
  | Point { position; _ } ->
      (match project bounds view position with Some point -> marker point | None -> [])
  | Spot { position; direction; _ } -> aim position direction
  | Area { position; direction; width; height; _ } ->
      let side = Vec3.cross direction (Vec3.create 0. 1. 0.) in
      let side = if Vec3.length side < 1e-6 then Vec3.create 1. 0. 0. else Vec3.normalize side in
      let up = Vec3.normalize (Vec3.cross side direction) in
      let corner sx sy = Vec3.add position (Vec3.add (Vec3.scale side (sx *. width /. 2.))
          (Vec3.scale up (sy *. height /. 2.))) in
      let corners = [| corner (-1.) (-1.); corner 1. (-1.); corner 1. 1.; corner (-1.) 1. |] in
      aim position direction @ List.concat (List.init 4 (fun index ->
        segment bounds view color corners.(index) corners.((index + 1) mod 4)))

let guides ~scene ~selected ~space view extra ~bounds =
  let cameras = if not extra.show.cameras then [] else
    List.concat_map (fun node_id ->
      match Option.bind (Edit_graph.find scene ~node_id) node_camera with
      | Some camera when not (same_view camera view) ->
          let active = Camera.position camera = Camera.position extra.render_camera
            && Camera.target camera = Camera.target extra.render_camera in
          let color = if active then active_color else guide_color in
          let eye = match project bounds view (Camera.position camera) with
            | Some (x, y) -> [Scene.circle ~at:(Float.to_int x, Float.to_int y) ~radius:4 ~fill:color ()]
            | None -> [] in
          eye @ frustum bounds view color camera
      | Some _ | None -> []) (camera_ids scene) in
  let lights = if not extra.show.cameras then [] else
    List.concat_map (light_guide bounds view active_color) (Objects.lights scene) in
  let handles = match selected with
    | Some node when extra.show.handles ->
        List.concat_map (fun arrow ->
          let color = arrow.color in
          let at = Float.to_int (fst arrow.tip), Float.to_int (snd arrow.tip) in
          line ~width:2 color arrow.base arrow.tip :: (match arrow.tool with
            | Turn -> [Scene.circle ~at ~radius:7 ~stroke:color (); Scene.circle ~at ~radius:6 ~stroke:color ()]
            | Grow -> [Scene.rect ~at:(fst at - 5, snd at - 5) ~w:10 ~h:10 ~fill:color ()]
            | Move | No_tool -> [Scene.circle ~at ~radius:5 ~fill:color ()]))
          (arrows node view bounds space extra.tool)
    | Some _ | None -> [] in
  cameras @ lights @ (if extra.show.axes then gizmo bounds view else []) @ handles

let save = CC.save
let filename request = request.CC.filename
let close extra = if extra.fly <> None then set_relative false
