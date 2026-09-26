open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let pointer (x, y) = float x, float y
let mouse_press (button, point) = Event.MousePressed (button, pointer point)
let mouse_release (button, point) = Event.MouseReleased (button, pointer point)
let mouse_move point = Event.MouseMoved (pointer point)

let frame ?(width = 900) ?(height = 640) ?mouse ?(events = []) count : Frame.t = {
  width; height; size = width, height;
  drawable_width = width; drawable_height = height;
  drawable_size = width, height; pixel_scale = 1., 1.;
  time = float_of_int count /. 60.; dt = 1. /. 60.; fps = 60.; count;
  mouse = (let x, y = Option.value ~default:(width / 2, height / 2) mouse in
    float x, float y);
  mouse_delta = 0., 0.;
  keys = []; mouse_buttons = []; events;
}

let width (_, _, width, _) = width
let center (x, y, width, height) = x + (width / 2), y + (height / 2)

(* False in the window-free [runtest] pass: the editor logic runs, and only
   checks that stage through Metal or open a window are skipped. *)
let native = ref true

(* The packed PXUI instances of a composed scene, for exact comparisons. *)
let ui_bytes scene =
  if not !native then "" else
  match Scene.Private.stage_native_render ~width:900 ~height:640 scene with
  | Error message -> fail message
  | Ok staged -> String.concat "" (List.filter_map (function
      | Scene.Private.Ui_layer (batch, _) ->
          Some (Bytes.to_string (Scene_command.Ui_batch.instances batch))
      | _ -> None) staged.layers)

let run () =
  let module Leader = Prismel_editor.Private.Leader in
  List.iter (fun (trigger, _, command) ->
    check (List.exists (fun binding ->
      binding.Editor_core.Keymap.trigger = trigger
      && binding.action = Leader.Graph_command command) Leader.keymap)
      "graph command missing from the host keymap") Pxui_graph.bindings;
  let camera_binding key action = List.exists (fun binding ->
    binding.Editor_core.Keymap.trigger = Editor_core.Keymap.Leader key
    && binding.action = action) Leader.keymap in
  check (camera_binding 'h' Leader.Hide_ui
      && camera_binding 'c' Leader.Open_camera)
    "camera visibility commands missing from the host keymap";
  let workspace = Prismel_editor.Private.Workspace.create Prismel_editor.default_layout in
  let initial = Prismel_editor.Private.Workspace.geometry workspace (frame ~width:1000 0) in
  check (initial.view_header = (0, 0, width initial.view, 22))
    "workspace header is not a compact single line";
  check (abs (width initial.view - 444) <= 1
      && abs (width initial.graph - 345) <= 1
      && abs (width initial.inspector - 199) <= 1)
    "workspace defaults are not 45/35/20 after splitter space";
  let splitter_x = width initial.view + 2 in
  let ui = Pxui.Ui.create () in
  let workspace_step workspace frame =
    Pxui.Ui.frame ui frame (fun ui -> Prismel_editor.Private.Workspace.update workspace ui frame) in
  let workspace = workspace_step workspace (frame ~width:1000 0) in
  let resized = workspace_step workspace
      (frame ~width:1000 ~events:[
        mouse_press (Input.LeftButton, (splitter_x, 200));
        mouse_move (splitter_x + 80, 200);
        mouse_release (Input.LeftButton, (splitter_x + 80, 200))] 1) in
  let resized_panes = Prismel_editor.Private.Workspace.geometry resized (frame ~width:1000 2) in
  check (width resized_panes.view > width initial.view
      && width resized_panes.graph < width initial.graph)
    "workspace splitter did not resize its adjacent columns";
  let wider = Prismel_editor.Private.Workspace.geometry resized (frame ~width:1200 3) in
  check (width wider.view > width resized_panes.view)
    "workspace splitter ratio did not survive a window resize";
  let collapsed = workspace_step
      (Prismel_editor.Private.Workspace.toggle Prismel_editor.Private.Workspace.Inspector resized) (frame 4) in
  Pxui.Ui.destroy ui;
  let collapsed_panes = Prismel_editor.Private.Workspace.geometry collapsed (frame 5) in
  check (width collapsed_panes.inspector = 0)
    "inspector toggle did not collapse the third column";

  let source = Sop.box ~label:"Inspectable source"
      ~size:(Vec3.create 2. 2. 2.) () in
  let graph = Sop.transform ~label:"Inspectable output"
      (Mat4.translation (Vec3.create 5. 0. 0.)) source in
  let null_factory = Edit_graph.factory ~key:"null" ~label:"Null"
      ~category:["Utility"] ~arity:1 (function
        | [input] -> Sop.null ~label:"Editor null" input
        | _ -> invalid_arg "Null factory expects one input") in
  let environment = Prismel_editor.Editor3.create ~graph
      ~factories:[null_factory]
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _graph mesh -> Scene3.create [Scene3.mesh mesh]) ()
    |> Result.get_ok in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait count environment =
    let environment = Prismel_editor.Editor3.update environment (frame count) in
    match Prismel_editor.Editor3.prepared environment with
    | Some _ -> environment
    | None when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.001;
        wait (count + 1) environment
    | None -> fail "sketch environment did not publish its initial async cook"
  in
  let environment = wait 0 environment in
  (match Sys.getenv_opt "PRISMEL_UI_PREVIEW" with
   | Some directory ->
       Sketch.export ~directory ~prefix:"workspace" ~frames:1
         ~config:{ Sketch.default_config with width=900; height=640 }
         (Prismel_editor.Editor3.scene environment)
   | None -> ());
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 'h')] 1) in
  let hidden_scene = Prismel_editor.Editor3.scene environment (frame 1) in
  check (Prismel_editor.Editor3.scene environment (frame 2) == hidden_scene)
    "unchanged hidden 3D scene composition was rebuilt";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 'h')] 2) in
  let at count fps={ (frame count) with fps }in
  let status environment frame=ui_bytes(Prismel_editor.Editor3.scene environment frame)in
  let environment=Prismel_editor.Editor3.update environment(at 1_000 60.)in
  let fps_initial=status environment(at 1_000 60.)in
  let environment=Prismel_editor.Editor3.update environment(at 1_030 120.)in
  let fps_before_deadline=status environment(at 1_030 120.)in
  let environment=Prismel_editor.Editor3.update environment(at 1_061 120.)in
  let fps_after_deadline=status environment(at 1_061 120.)in
  if !native then check(fps_before_deadline=fps_initial&&fps_after_deadline<>fps_initial)
    "FPS status text ignored its one-second sampling deadline";
  check (Prismel_editor.Editor3.selected_node environment = None)
    "camera/render controls should own an unselected inspector";
  let current_frame = frame 10 in
  let panes = Prismel_editor.Editor3.panes environment current_frame in
  check (Easy_camera.control_area (Prismel_editor.Editor3.camera environment)
      = Some panes.view)
    "3D camera gestures are not confined to the view column";
  let inspector_x, inspector_y, _, _ = panes.inspector in
  let camera_header = inspector_x + 32, inspector_y + 15 in
  let collapsed_scene = ui_bytes (Prismel_editor.Editor3.scene environment current_frame) in
  let blank_inspector = inspector_x + 4, inspector_y + 200 in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_press (Input.LeftButton, blank_inspector);
        mouse_release (Input.LeftButton, blank_inspector);
        Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'w')] 10) in
  check (not (Prismel_editor.Editor3.flying environment))
    "same-frame inspector click routed a view-only shortcut";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_press (Input.LeftButton, camera_header)] 11) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_release (Input.LeftButton, camera_header)] 12) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_move (10, 100)] 13) in
  let expanded_scene = ui_bytes (Prismel_editor.Editor3.scene environment (frame 13)) in
  if !native then check (expanded_scene <> collapsed_scene)
    "workspace camera accordion lost its armed press before the release frame";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_press (Input.LeftButton, camera_header)] 14) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_release (Input.LeftButton, camera_header)] 15) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_move (10, 100)] 16) in
  let render_header = inspector_x + 32, inspector_y + 39 in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_press (Input.LeftButton, render_header)] 17) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_release (Input.LeftButton, render_header)] 18) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_move (10, 100)] 19) in
  if !native then
    check (ui_bytes (Prismel_editor.Editor3.scene environment (frame 19)) <> collapsed_scene)
    "workspace render accordion lost its armed press before the release frame";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 'w')] 19) in
  check (not (Prismel_editor.Editor3.flying environment))
    "inspector child press did not focus its pane";
  (match Sys.getenv_opt "PRISMEL_UI_PREVIEW" with
   | Some directory -> Sketch.export ~directory ~prefix:"workspace-render"
       ~frames:1 ~config:{ Sketch.default_config with width=900; height=640 }
       (Prismel_editor.Editor3.scene environment)
   | None -> ());
  let graph_tile = List.hd (Prismel_editor.Editor3.graph_nodes environment) in
  let point = center graph_tile.Pxui_graph.bounds in
  let selection_frame = frame ~events:[
      mouse_press (Input.LeftButton, point);
      mouse_release (Input.LeftButton, point)] 20 in
  let environment = Prismel_editor.Editor3.update environment selection_frame in
  check (Option.map Node.id (Prismel_editor.Editor3.selected_node environment)
      = Some graph_tile.id)
    "graph selection did not replace camera controls with node inspection";
  (match Sys.getenv_opt "PRISMEL_UI_PREVIEW" with
   | Some directory -> Sketch.export ~directory ~prefix:"workspace-inspector"
       ~frames:1 ~config:{ Sketch.default_config with width=900; height=640 }
       (Prismel_editor.Editor3.scene environment)
   | None -> ());
  let camera_frame = frame ~events:[Event.KeyPressed Input.Space;
      Event.KeyPressed (Input.KeyChar 'c')] 21 in
  let environment = Prismel_editor.Editor3.update environment camera_frame in
  check (Prismel_editor.Editor3.selected_node environment = None)
    "Space c did not restore the camera/render inspector";
  let source_tile = List.find (fun tile -> tile.Pxui_graph.id = Node.id source)
      (Prismel_editor.Editor3.graph_nodes environment) in
  let view_point = center source_tile.view_bounds in
  let view_frame = frame ~events:[
      mouse_press (Input.LeftButton, view_point);
      mouse_release (Input.LeftButton, view_point)] 22 in
  let environment = Prismel_editor.Editor3.update environment view_frame in
  check (Node.id (Prismel_editor.Editor3.displayed_node environment)
      = Node.id source)
    "graph VIEW button did not switch the environment display node";
  (* Shared undo stack: a duplicated node is one entry; Command-Z removes it,
     Shift-Command-Z brings it back. *)
  let tiles environment = List.length (Prismel_editor.Editor3.graph_nodes environment) in
  let before = tiles environment in
  let source_point = center source_tile.Pxui_graph.bounds in
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      mouse_press (Input.LeftButton, source_point);
      mouse_release (Input.LeftButton, source_point)] 23) in
  let chord ?(shift = false) key count =
    { (frame ~events:[Event.KeyPressed (Input.KeyChar key)] count) with
      keys = Input.Meta :: (if shift then [Input.Shift] else []) } in
  let environment = Prismel_editor.Editor3.update environment (chord 'd' 24) in
  check (tiles environment = before + 1) "Command-D did not duplicate the selected node";
  check (Prismel_editor.Editor3.can_undo environment) "duplicate did not enter the undo stack";
  let environment = Prismel_editor.Editor3.update environment (chord 'z' 25) in
  check (tiles environment = before) "Command-Z did not undo the duplicate";
  check (Prismel_editor.Editor3.can_redo environment) "undo did not leave a redo entry";
  let environment = Prismel_editor.Editor3.update environment (chord ~shift:true 'z' 26) in
  check (tiles environment = before + 1) "Shift-Command-Z did not redo the duplicate";
  let environment = Prismel_editor.Editor3.update environment (chord 'z' 27) in
  check (tiles environment = before) "second undo failed after redo";
  (* Tile positions are document state: one drag is one undo entry. *)
  let tile_x environment = List.find_map (fun (view : Pxui_graph.node_view) ->
      if view.id = Node.id source then (let x, _, _, _ = view.bounds in Some x)
      else None) (Prismel_editor.Editor3.graph_nodes environment) |> Option.get in
  let x0 = tile_x environment and sx, sy = source_point in
  let environment = List.fold_left (fun environment (count, mouse, events) ->
      Prismel_editor.Editor3.update environment { (frame ~mouse ~events count) with
        mouse_buttons = if count > 27 then [Input.LeftButton] else [] })
    environment [
      27, (sx, sy), [];  (* hover first: hit testing uses the last frame *)
      28, (sx, sy), [mouse_press (Input.LeftButton, (sx, sy))];
      29, (sx + 20, sy), [mouse_move (sx + 20, sy)];
      30, (sx + 40, sy), [mouse_move (sx + 40, sy)]] in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~mouse:(sx + 40, sy)
         ~events:[mouse_release (Input.LeftButton, (sx + 40, sy))] 31) in
  check (tile_x environment <> x0) "dragging a tile did not move it";
  let environment = Prismel_editor.Editor3.update environment (chord 'z' 32) in
  check (tile_x environment = x0) "undo did not restore the dragged tile position";
  (* Space c clears the selection the drag made, as before this check. *)
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'c')] 33) in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait_source count environment =
    let environment = Prismel_editor.Editor3.update environment (frame count) in
    match Option.bind (Prismel_editor.Editor3.prepared environment)
        Mesh.centroid with
    | Some center when abs_float center.Vec3.x < 1. -> environment
    | _ when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.001;
        wait_source (count + 1) environment
    | _ -> fail "display-node cook did not publish the selected source preview"
  in
  let environment = wait_source 23 environment in
  check (Prismel_editor.Editor3.scene environment current_frame <> [])
    "sketch environment produced an empty composed scene";
  (* The whole workspace paints in batch groups, not one draw per label. *)
  if !native then begin
    let batches = match Scene.Private.stage_native_render ~width:900 ~height:640
        (Prismel_editor.Editor3.scene environment current_frame) with
      | Ok staged -> List.fold_left (fun total -> function
          | Scene.Private.Ui_layer (batch, _) ->
              total + Array.length (Scene_command.Ui_batch.batches batch)
          | _ -> total) 0 staged.layers
      | Error message -> fail message in
    Printf.printf "workspace UI batches: %d\n" batches;
    check (batches > 0 && batches <= 16) "workspace UI draws were not batched"
  end;
  let _, _, graph_width, graph_height =
    (Prismel_editor.Editor3.panes environment (frame 29)).graph in
  let graph_x, graph_y, _, _ =
    (Prismel_editor.Editor3.panes environment (frame 29)).graph in
  let menu_point = graph_x + (graph_width / 2), graph_y + (graph_height / 2) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 'a')] 29) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~mouse:menu_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] 30) in
  let loose_nodes = Edit_graph.inspect
      (Prismel_editor.Editor3.document environment) in
  let loose_null = List.find (fun info -> info.Edit_graph.operation = "null"
      && info.id <> Node.id graph) loose_nodes in
  check (List.length loose_nodes = 3 && loose_null.inputs = [|None|]
      && Node.id (Prismel_editor.Editor3.displayed_node environment)
         = Node.id source)
    "workspace could not add a disconnected SOP without stealing the display flag";
  let source_tile = List.find (fun tile -> tile.Pxui_graph.id = Node.id source)
      (Prismel_editor.Editor3.graph_nodes environment) in
  let source_point = center source_tile.bounds in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~mouse:source_point ~events:[
        mouse_press (Input.LeftButton, source_point);
        mouse_release (Input.LeftButton, source_point)] 31) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~mouse:source_point ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 'a')] 32) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~mouse:source_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] 33) in
  check (List.length (Edit_graph.inspect
      (Prismel_editor.Editor3.document environment)) = 4
      && Node.operation (Prismel_editor.Editor3.displayed_node environment) = "null")
    "workspace did not apply and display a leader add-node graph edit";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed (Input.KeyChar 'd')]
        ~mouse:source_point 34 |> fun frame ->
          { frame with Frame.keys = [Input.Meta] }) in
  check (List.length (Edit_graph.inspect
      (Prismel_editor.Editor3.document environment)) = 5)
    "workspace did not apply Command-D subgraph duplication";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Backspace] 35) in
  check (List.length (Edit_graph.inspect
      (Prismel_editor.Editor3.document environment)) = 4)
    "Backspace did not delete the duplicated node";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 'g')] 35) in
  let environment = Prismel_editor.Editor3.update environment
      { (frame ~events:[Event.KeyPressed (Input.KeyChar 'd')] 35)
        with keys = [Input.Meta] } in
  check (List.length (Edit_graph.inspect
      (Prismel_editor.Editor3.document environment)) = 4)
    "hidden graph still accepted a duplicate shortcut";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 'g')] 35) in
  (* Space t shows the timeline bar; dragging its scrub slider seeks and
     pauses the shared clock. *)
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Space;
        Event.KeyPressed (Input.KeyChar 't')] 36) in
  let tx, ty, tw, th = (Prismel_editor.Editor3.panes environment (frame 37)).timeline in
  check (th > 0 && tw = 900) "Space t did not show the full-width timeline bar";
  let environment = Prismel_editor.Editor3.update environment (frame 37) in
  let scrub_y = ty + (th / 2) and scrub_x = tx + tw - 60 in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_press (Input.LeftButton, (scrub_x, scrub_y))] 38) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_move (tx + tw - 10, scrub_y);
        mouse_release (Input.LeftButton, (tx + tw - 10, scrub_y))] 39) in
  let clock = Prismel_editor.Editor3.timeline environment in
  check (Sketch_support.Timeline.mode clock = Sketch_support.Timeline.Paused
      && Sketch_support.Timeline.frame clock >= 200L)
    "dragging the timeline scrub did not seek and pause";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Space] 40) in
  (match Sys.getenv_opt "PRISMEL_UI_PREVIEW" with
   | Some directory -> Sketch.export ~directory ~prefix:"workspace-leader"
       ~frames:1 ~config:{ Sketch.default_config with width=900; height=640 }
       (Prismel_editor.Editor3.scene environment)
   | None -> ());
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Escape] 41) in
  Prismel_editor.Editor3.close environment;

  (* Camera nodes: a default camera following the viewport joins a document
     without one, exactly one is ACTIVE, deleting the last re-adds it inside
     the same undo entry, and a viewport drag is one coalesced undo entry. *)
  let cameras environment = List.filter (fun info -> info.Edit_graph.operation = "camera")
      (Edit_graph.inspect (Prismel_editor.Editor3.document environment)) in
  let active environment = List.filter (fun tile -> tile.Pxui_graph.active)
      (Prismel_editor.Editor3.graph_nodes environment) in
  let environment = Prismel_editor.Editor3.create ~graph
      ~camera:(Easy_camera.create ~distance:6. ~inertia:false ())
      ~factories:Sop_catalog.Editor.factories
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _graph mesh -> Scene3.create [Scene3.mesh mesh]) ()
    |> Result.get_ok in
  let near a b = Vec3.nearly_equal a b ~eps:1e-6 in
  let eye environment = Camera.position (Prismel_editor.Editor3.render_camera environment) in
  let viewport_eye environment =
    Camera.position (Easy_camera.camera (Prismel_editor.Editor3.camera environment)) in
  check (List.length (cameras environment) = 1 && List.length (active environment) = 1)
    "Editor3 did not add one ACTIVE default camera";
  let environment = List.fold_left (fun environment count ->
      Prismel_editor.Editor3.update environment (frame count)) environment [0; 1; 2] in
  check (not (Prismel_editor.Editor3.can_undo environment)
      && near (eye environment) (viewport_eye environment))
    "an idle following camera wrote undo entries or drifted from the viewport";
  let start_eye = eye environment in
  let vx, vy, vw, vh = (Prismel_editor.Editor3.panes environment (frame 3)).view in
  let px, py = vx + (vw / 2), vy + (vh / 2) in
  let environment = List.fold_left (fun environment (count, events) ->
      Prismel_editor.Editor3.update environment
        { (frame ~events count) with mouse_buttons = [Input.LeftButton] })
    environment [
      4, [mouse_press (Input.LeftButton, (px, py))];
      5, [mouse_move (px + 30, py)];
      6, [mouse_move (px + 60, py + 10)];
      7, [mouse_move (px + 90, py + 20)]] in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[mouse_release (Input.LeftButton, (px + 90, py + 20))] 8) in
  check (not (near (eye environment) start_eye)
      && near (eye environment) (viewport_eye environment))
    "the following camera did not track a viewport orbit";
  let command key count = { (frame ~events:[Event.KeyPressed (Input.KeyChar key)] count)
    with keys = [Input.Meta] } in
  let environment = Prismel_editor.Editor3.update environment (command 'z' 9) in
  let environment = Prismel_editor.Editor3.update environment (frame 10) in
  check (near (eye environment) start_eye && near (viewport_eye environment) start_eye
      && not (Prismel_editor.Editor3.can_undo environment))
    "one undo did not revert the whole drag and move the viewport back";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Home] 10) in
  let environment = Prismel_editor.Editor3.update environment (frame 10) in
  let camera_tile = List.hd (active environment) in
  (* The title bar: at this zoom the ACTIVE/VIEW buttons cover the center. *)
  let at = let x, y, w, _ = camera_tile.bounds in x + (w / 3), y + 5 in
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      mouse_press (Input.LeftButton, at); mouse_release (Input.LeftButton, at)] 11) in
  let environment = Prismel_editor.Editor3.update environment (command 'd' 12) in
  check (List.length (cameras environment) = 2 && List.length (active environment) = 1)
    "duplicating a camera broke the single ACTIVE flag";
  let environment = Prismel_editor.Editor3.update environment (command 'z' 13) in
  let environment = Prismel_editor.Editor3.update environment (frame 14) in
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      mouse_press (Input.LeftButton, at); mouse_release (Input.LeftButton, at)] 15) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.KeyPressed Input.Delete] 16) in
  check (List.length (cameras environment) = 1 && List.length (active environment) = 1
      && (List.hd (cameras environment)).id <> camera_tile.id)
    "deleting the last camera did not re-add an ACTIVE default";
  let environment = Prismel_editor.Editor3.update environment (command 'z' 17) in
  check (List.map (fun info -> info.Edit_graph.id) (cameras environment) = [camera_tile.id])
    "undo after deleting the camera did not restore the original in one step";
  (* Fly: Space w (view focused) flies, held W moves forward, Escape exits;
     Space exits and arms the leader in the same frame. *)
  let key k = Event.KeyPressed k in
  let fly_view environment = let vx, vy, _, _ = (Prismel_editor.Editor3.panes
      environment (frame 18)).view in vx + 20, vy + 20 in
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      mouse_press (Input.RightButton, fly_view environment);
      mouse_release (Input.RightButton, fly_view environment)] 18) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space; key (Input.KeyChar 'w')] 18) in
  check (Prismel_editor.Editor3.flying environment) "Space w did not enter fly mode";
  let before = viewport_eye environment in
  let environment = Prismel_editor.Editor3.update environment
      { (frame ~events:[key (Input.KeyChar 'w')] 18) with keys = [Input.KeyChar 'w'] } in
  check (not (near (viewport_eye environment) before)
      && Prismel_editor.Editor3.selected_node environment = None)
    "held W did not fly the viewport";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Escape] 18) in
  check (not (Prismel_editor.Editor3.flying environment)) "Escape did not exit fly mode";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space; key (Input.KeyChar 'w')] 18) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space] 18) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key (Input.KeyChar 'g')] 18) in
  check (not (Prismel_editor.Editor3.flying environment)
      && width (Prismel_editor.Editor3.panes environment (frame 18)).graph = 0)
    "Space did not exit fly mode into the leader";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space; key (Input.KeyChar 'g')] 18) in
  (* F frames the displayed tile in the graph, then the displayed geometry
     in the viewport even when another node is selected. *)
  let source_tile = List.find (fun tile -> tile.Pxui_graph.label = "Inspectable source")
      (Prismel_editor.Editor3.graph_nodes environment) in
  let at = let x, y, w, _ = source_tile.bounds in x + (w / 3), y + 5 in
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      mouse_press (Input.LeftButton, at); mouse_release (Input.LeftButton, at)] 18) in
  let target environment = Easy_camera.target (Prismel_editor.Editor3.camera environment) in
  let before_target = target environment in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key (Input.KeyChar 'f')] 19) in
  let displayed_tile = List.find (fun tile -> tile.Pxui_graph.label = "Inspectable output")
      (Prismel_editor.Editor3.graph_nodes environment) in
  let graph_center = center (Prismel_editor.Editor3.panes environment (frame 19)).graph in
  let tile_center = center displayed_tile.bounds in
  check (abs (fst graph_center - fst tile_center) <= 2
      && abs (snd graph_center - snd tile_center) <= 2
      && near (target environment) before_target)
    "graph-focused F did not frame the displayed tile without moving the camera";
  let view_at = fly_view environment in
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      mouse_press (Input.LeftButton, view_at); mouse_release (Input.LeftButton, view_at)] 20) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key (Input.KeyChar 'f')] 21) in
  check (near (target environment) (Vec3.create 5. 0. 0.))
    "viewport-focused F did not focus on the displayed node's cached bounds";
  Prismel_editor.Editor3.close environment;

  (* Sketch settings live in the document: [prepare] reads them, a change
     recooks, and undo restores the previous value (voxel_wall's renderer). *)
  let mode_schema = Editor_core.Param.(schema ~name:"mode" ~default:0
    [ field ~name:"mode" ~label:"Mode" ~kind:(integer ~min:0 ~max:3 ())
        ~default:0 ~get:Fun.id ~set:(fun mode _ -> mode) () ]) in
  let module Settings = Prismel_editor.Settings in
  let bump = Editor_core.Command.make ~id:"test.bump" ~label:"bump mode"
      ~trigger:(Editor_core.Keymap.Leader 'k') (fun environment ->
        Prismel_editor.Editor3.set_settings environment (Settings.make mode_schema 3)) in
  let environment = Prismel_editor.Editor3.create ~graph
      ~settings:(Settings.make mode_schema 0) ~commands:[bump]
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun settings _ -> Ok (Settings.get mode_schema settings))
      ~scene3:(fun _ _ -> Scene3.create []) () |> Result.get_ok in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait_mode expected count environment =
    let environment = Prismel_editor.Editor3.update environment (frame count) in
    if Prismel_editor.Editor3.prepared environment = Some expected then environment
    else if Unix.gettimeofday () < deadline then
      (Unix.sleepf 0.001; wait_mode expected (count + 1) environment)
    else fail "a settings change did not re-run prepare" in
  let environment = wait_mode 0 0 environment in
  let environment = wait_mode 1 100
      (Prismel_editor.Editor3.set_settings environment (Settings.make mode_schema 1)) in
  let undo count = { (frame ~events:[Event.KeyPressed (Input.KeyChar 'z')] count)
    with keys = [Input.Meta] } in
  let environment = wait_mode 0 200
      (Prismel_editor.Editor3.update environment (undo 199)) in
  check (Settings.get mode_schema (Prismel_editor.Editor3.settings environment) = 0)
    "undo did not restore the sketch settings";
  (* A sketch command runs from its leader key and from the palette. *)
  let mode environment = Settings.get mode_schema (Prismel_editor.Editor3.settings environment) in
  let environment = Prismel_editor.Editor3.update environment (frame ~events:[
      Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'k')] 300) in
  check (mode environment = 3) "Space k did not run the sketch command";
  let environment = Prismel_editor.Editor3.update environment (undo 301) in
  check (mode environment = 0) "undo did not revert the sketch command";
  let environment = List.fold_left (fun environment (count, events) ->
      Prismel_editor.Editor3.update environment (frame ~events count)) environment [
      302, [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar '/')];
      303, [Event.TextInput "bump"];
      304, [Event.KeyPressed Input.Enter];
      305, []] in
  check (mode environment = 3) "the command palette did not run the sketch command";
  Prismel_editor.Editor3.close environment;

  let cooks2 = Atomic.make 0 in
  let environment2 = Prismel_editor.Editor2.create ~graph
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun _ output -> Atomic.incr cooks2;
        Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene2:(fun _graph _mesh -> Scene.[
        rect ~at:(-60, -40) ~w:120 ~h:80
          ~fill:(Color.hex_exn "#5eead4") ()
      ]) ()
    |> Result.get_ok in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait2 count environment =
    let environment = Prismel_editor.Editor2.update environment (frame count) in
    match Prismel_editor.Editor2.prepared environment with
    | Some _ -> environment
    | None when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.001;
        wait2 (count + 1) environment
    | None -> fail "2D sketch environment did not publish its initial cook"
  in
  let environment2 = wait2 0 environment2 in
  let environment2 = Prismel_editor.Editor2.update environment2
      (frame ~events:[Event.KeyPressed (Input.KeyChar 'f')] 9) in
  check (Float.abs ((Easy_camera2.center (Prismel_editor.Editor2.camera environment2)).x -. 5.) < 1e-6)
    "2D viewport-focused F did not focus on the displayed node";
  check (not (Prismel_editor.Editor2.can_undo environment2)
      && not (Prismel_editor.Editor2.can_redo environment2))
    "new 2D environment has an unexpected undo history";
  let environment2, inspected = Prismel_editor.Editor2.update_with
      environment2 (frame 10) ~inspector:(fun _ui -> 7) in
  check (inspected = Some 7) "2D update_with omitted the unselected inspector";
  let prior_cooks = Atomic.get cooks2 in
  let environment2 = Prismel_editor.Editor2.set_settings environment2
      (Prismel_editor.Settings.make mode_schema 2) in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait_reprepare count environment =
    let environment = Prismel_editor.Editor2.update environment (frame count) in
    if Atomic.get cooks2 > prior_cooks then environment
    else if Unix.gettimeofday () < deadline then
      (Unix.sleepf 0.001; wait_reprepare (count + 1) environment)
    else fail "2D settings change did not force a new cook" in
  let environment2 = wait_reprepare 11 environment2 in
  check (Prismel_editor.Editor2.selected_node environment2 = None)
    "2D camera/render controls should own an unselected inspector";
  check (Prismel_editor.Editor2.scene environment2 (frame 10) <> [])
    "2D sketch environment produced an empty composed scene";
  check (Sketch_support.Timeline.time (Prismel_editor.Editor2.timeline environment2)
      > 0.) "shared 2D sketch lifecycle did not advance playback time";
  let hidden_frame = frame ~events:[Event.KeyPressed Input.Space;
      Event.KeyPressed (Input.KeyChar 'h')] 11 in
  let environment2 = Prismel_editor.Editor2.update environment2 hidden_frame in
  let hidden_frame = frame 11 in
  let environment2 = Prismel_editor.Editor2.update environment2 hidden_frame in
  check (Easy_camera2.control_area (Prismel_editor.Editor2.camera environment2)
      = Some (0, 0, hidden_frame.width, hidden_frame.height))
    "hidden 2D sketch UI still reserved invisible workspace bounds";
  let hidden_scene = Prismel_editor.Editor2.scene environment2 hidden_frame in
  check (Prismel_editor.Editor2.scene environment2 (frame 12) == hidden_scene)
    "unchanged hidden 2D scene composition was rebuilt";
  Prismel_editor.Editor2.close environment2;
  (* Presets: a custom node, an added catalog node, a moved tile, and an
     edited parameter survive save -> load; a sketch whose code graph lacks
     the custom node, or corrupt JSON, is rejected. *)
  let depth_schema = Parameter.schema ~name:"test_depth" ~default:2.
      [Parameter.field ~name:"amount" ~label:"Amount"
         ~kind:(Parameter.floating ~min:0. ~max:10. ()) ~default:2.
         ~get:Fun.id ~set:(fun amount _ -> amount) ()] in
  let code () =
    let grid = Sop_catalog.Grid.create ~label:"code-grid" ~columns:2 ~rows:2 ~size:1. () in
    Custom.map ~label:"code-depth" ~operation:"test_depth" ~schema:depth_schema
      ~values:2. grid (fun ~parameters:_ ~context:_ geometry -> Ok geometry) in
  let code_graph = code () in
  let box = List.find (fun factory -> Edit_graph.factory_key factory = "box")
      Sop_catalog.Editor.factories in
  let added = Result.get_ok (Edit_graph.instantiate box []) in
  let document = Edit_graph.of_graph code_graph
    |> Edit_graph.add_node ~factory:box added |> Result.get_ok in
  let document, _ = Edit_graph.apply_parameters document ~node_id:(Node.id code_graph)
      ["amount", Parameter.Float_value 7.25] |> Result.get_ok in
  let directory = Filename.temp_dir "sketch-ui-presets" "" in
  let positions = [Node.id added, 123.5, -40.; Node.id added, 999., 999.] in
  let saved = Prismel_editor.Preset.save ~directory ~name:"my wall/1" ~sketch:"test"
      ~document ~positions ~display:(Some (Node.id code_graph)) ~active_camera:None
      ~settings:["mode", Parameter.Int_value 2]
      ~view:(`Assoc ["fov", `Float 0.5]) |> Result.get_ok in
  check (Filename.basename saved = "my_wall_1.json"
      && List.map fst (Prismel_editor.Preset.list ~directory) = ["my_wall_1"])
    "preset save did not sanitize the name or list the file";
  (match Yojson.Safe.from_file saved with
   | `Assoc fields -> check (List.assoc_opt "prismel" fields = Some (`Int 1)
       && List.assoc_opt "kind" fields = Some (`String "preset")
       && (match List.assoc_opt "sections" fields with
           | Some (`Assoc sections) ->
               List.mem_assoc "graph" sections && List.mem_assoc "viewport" sections
           | _ -> false))
       "preset lacks the shared sectioned envelope"
   | _ -> check false "preset is not a JSON object");
  let loaded = Prismel_editor.Preset.load ~path:saved ~code:code_graph
      ~factories:Sop_catalog.Editor.factories |> Result.get_ok in
  let describe document = Edit_graph.inspect document |> List.map (fun info ->
    let label id = (Option.get (Edit_graph.find document ~node_id:id) |> Node.label) in
    info.Edit_graph.label, info.operation, info.parameters,
    Array.map (Option.map label) info.inputs) in
  check (describe loaded.document = describe document
      && loaded.view = `Assoc ["fov", `Float 0.5]
      && loaded.display = Some (Node.id code_graph)
      && List.exists (fun (_, x, y) -> x = 123.5 && y = -40.) loaded.positions
      && loaded.settings = ["mode", Parameter.Int_value 2])
    "preset round trip changed the document, view, display, positions, or settings";
  let legacy = Filename.concat directory "legacy.json" in
  let sectioned = Yojson.Safe.from_file saved in
  (match sectioned with
   | `Assoc fields ->
       let sections = match List.assoc "sections" fields with `Assoc s -> s | _ -> assert false in
       let graph = match List.assoc "graph" sections with `Assoc g -> g | _ -> assert false in
       Yojson.Safe.to_file legacy (`Assoc (
         ["prismel", `Int 1; "kind", `String "preset";
          "sketch", `String "test"; "view", List.assoc "viewport" sections] @ graph))
   | _ -> assert false);
  let loaded_legacy = Prismel_editor.Preset.load ~path:legacy ~code:code_graph
      ~factories:Sop_catalog.Editor.factories |> Result.get_ok in
  check (describe loaded_legacy.document = describe document
      && loaded_legacy.view = loaded.view)
    "old flat preset stopped loading";
  check (Prismel_editor.Preset.delete ~directory ~name:"legacy" = Ok ())
    "legacy preset could not be deleted";
  check (Result.is_error (Prismel_editor.Preset.load ~path:saved ~code:(code ())
      ~factories:Sop_catalog.Editor.factories))
    "a preset loaded into a sketch without its custom node";
  let corrupt = Filename.concat directory "corrupt.json" in
  Out_channel.with_open_text corrupt (fun channel -> output_string channel "{nope");
  check (Result.is_error (Prismel_editor.Preset.load ~path:corrupt ~code:code_graph
      ~factories:Sop_catalog.Editor.factories)) "corrupt preset JSON loaded";
  check (Prismel_editor.Preset.delete ~directory ~name:"corrupt" = Ok ()
      && List.map fst (Prismel_editor.Preset.list ~directory) = ["my_wall_1"])
    "preset delete did not remove the file";

  (* Workspace presets: Space s + Enter saves; Space b loads a preset whose
     camera does not follow the viewport, as one undo step, and looking
     through it renders exactly the render camera's framebuffer. *)
  let presets = Filename.temp_dir "sketch-ui-workspace-presets" "" in
  let mesh_scene mesh = Scene3.create [Scene3.mesh mesh] in
  let environment = Prismel_editor.Editor3.create ~graph ~presets
      ~camera:(Easy_camera.create ~distance:6. ~inertia:false ())
      ~factories:Sop_catalog.Editor.factories
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _graph mesh -> mesh_scene mesh) () |> Result.get_ok in
  let environment = wait 0 environment in
  let key k = Event.KeyPressed k in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space; key (Input.KeyChar 's')] 50) in
  let graph_width = width (Prismel_editor.Editor3.panes environment (frame 50)).graph in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space; key (Input.KeyChar 'g')] 50) in
  check (width (Prismel_editor.Editor3.panes environment (frame 50)).graph
      = graph_width) "open preset prompt let a workspace shortcut toggle the graph";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Enter] 51) in
  check (List.length (Prismel_editor.Preset.list ~directory:presets) = 1)
    "Space s + Enter did not save a preset";
  let document = Prismel_editor.Editor3.document environment in
  let camera_id = (List.hd (cameras environment)).id in
  let document, _ = Edit_graph.apply_parameters document ~node_id:camera_id
      [ "follow_viewport", Parameter.Bool_value false;
        "eye_x", Parameter.Float_value 6.; "eye_y", Parameter.Float_value 2.;
        "eye_z", Parameter.Float_value 6. ] |> Result.get_ok in
  ignore (Prismel_editor.Preset.save ~directory:presets ~name:"fixed" ~sketch:"test" ~document
      ~positions:[] ~display:None ~active_camera:(Some camera_id) ~settings:[]
      ~view:(`Assoc ["look_through", `Bool true]) |> Result.get_ok);
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space; key (Input.KeyChar 'b')] 52) in
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[Event.TextInput "fixed"; key Input.Enter] 53) in
  let environment = Prismel_editor.Editor3.update environment (frame 54) in
  check (near (eye environment) (Vec3.create 6. 2. 6.)
      && Prismel_editor.Editor3.look_through environment
      && not (near (viewport_eye environment) (Vec3.create 6. 2. 6.)))
    "loading a preset did not restore its fixed render camera and look-through";
  let environment = Prismel_editor.Editor3.update environment
      (frame ~events:[key Input.Space; key (Input.KeyChar 'h')] 55) in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait_cook count environment =
    let environment = Prismel_editor.Editor3.update environment (frame count) in
    if Prismel_editor.Editor3.prepared environment <> None
        && Prismel_editor.Editor3.displayed_node environment != graph
        || Unix.gettimeofday () > deadline then environment
    else (Unix.sleepf 0.001; wait_cook (count + 1) environment) in
  let environment = wait_cook 56 environment in
  let mesh = Option.get (Prismel_editor.Editor3.prepared environment) in
  let direct camera frame = [Scene.clear (Color.hex_exn "#09090b");
      Scene.view3d ~viewport:(0, 0, frame.Frame.width, frame.height) ~camera
        (mesh_scene mesh)] in
  (* One window, three frames: look-through, render camera, viewport camera. *)
  let views = [| Prismel_editor.Editor3.scene environment;
    direct (Prismel_editor.Editor3.render_camera environment);
    direct (Easy_camera.camera (Prismel_editor.Editor3.camera environment)) |] in
  if !native then begin
  let directory = Filename.temp_dir "sketch-ui-look" "" in
  Sketch.export_state ~directory ~prefix:"look" ~frames:3
    ~config:{ Sketch.default_config with width = 200; height = 150 }
    ~init:(fun _ -> 0) ~update:(fun _ (frame : Frame.t) -> frame.count)
    ~view:(fun count frame -> views.(min 2 (count - 1)) frame) () |> ignore;
  let png index = In_channel.with_open_bin
      (Filename.concat directory (Printf.sprintf "look-%06d.png" index))
      In_channel.input_all in
  check (png 0 = png 1 && png 0 <> png 2)
    "look-through framebuffer differs from the render camera's"
  end;
  let environment = Prismel_editor.Editor3.update environment (command 'z' 90) in
  let environment = Prismel_editor.Editor3.update environment (frame 91) in
  check (not (near (eye environment) (Vec3.create 6. 2. 6.)))
    "one undo did not revert the loaded preset";
  Prismel_editor.Editor3.close environment;

  (* Finite native smoke: the relative-pointer boundary toggles on a live
     window and is released when the sketch stops. *)
  if !native then begin
  let toggled = ref [] in
  let directory = Filename.temp_dir "sketch-ui-fly" "" in
  let nested_capture = Filename.concat directory "nested/capture.png" in
  (* One window: relative pointer, nested capture, and after_present. *)
  let final = Sketch.run_state ~max_frames:2
      ~config:{ Sketch.default_config with width = 120; height = 80 }
      ~init:(fun _ -> 0)
      ~update:(fun value (frame : Frame.t) ->
        toggled := Sketch.set_relative_mouse (frame.count = 1) :: !toggled;
        if frame.count = 2 then begin
          check (value = 11) "after_present model was not used on the next frame";
          check (Canvas.save_screen_png nested_capture = Ok ())
            "native capture did not create its output directory"
        end;
        value + 1)
      ~view:(fun _ _ -> [Scene.clear Color.black])
      ~after_present:(fun value _ -> value + 10) () in
  check (final = 22) "after_present model was not returned";
  check (!toggled = [Ok (); Ok ()]
      && Sketch.set_relative_mouse true <> Ok ())
    "native relative-pointer toggle failed or outlived the sketch";
  check (Sys.file_exists nested_capture)
    "native capture did not write its nested PNG"
  end;
  print_endline (if !native then "sketch ui tests passed"
    else "sketch ui logic tests passed (window-free)")

let run_logic () = native := false; run ()
