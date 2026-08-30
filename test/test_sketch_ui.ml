open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message

let frame ?(width = 900) ?(height = 640) ?mouse ?(events = []) count : Frame.t = {
  width; height; size = width, height;
  drawable_width = width; drawable_height = height;
  drawable_size = width, height; pixel_scale = 1., 1.;
  time = float_of_int count /. 60.; dt = 1. /. 60.; fps = 60.; count;
  mouse = Option.value ~default:(width / 2, height / 2) mouse;
  mouse_delta = 0, 0;
  keys = []; mouse_buttons = []; events;
}

let width (_, _, width, _) = width
let center (x, y, width, height) = x + (width / 2), y + (height / 2)

let () =
  let workspace = Sketch_ui.Workspace.create Sketch_ui.default_layout in
  let initial = Sketch_ui.Workspace.geometry workspace (frame ~width:1000 0) in
  check (abs (width initial.view - 444) <= 1
      && abs (width initial.graph - 345) <= 1
      && abs (width initial.inspector - 199) <= 1)
    "workspace defaults are not 45/35/20 after splitter space";
  let splitter_x = width initial.view + 2 in
  let resized = Sketch_ui.Workspace.update workspace
      (frame ~width:1000 ~events:[
        Event.MousePressed (Input.LeftButton, (splitter_x, 200));
        MouseMoved (splitter_x + 80, 200);
        MouseReleased (Input.LeftButton, (splitter_x + 80, 200))] 1) in
  let resized_panes = Sketch_ui.Workspace.geometry resized (frame ~width:1000 2) in
  check (width resized_panes.view > width initial.view
      && width resized_panes.graph < width initial.graph)
    "workspace splitter did not resize its adjacent columns";
  let wider = Sketch_ui.Workspace.geometry resized (frame ~width:1200 3) in
  check (width wider.view > width resized_panes.view)
    "workspace splitter ratio did not survive a window resize";
  let collapsed = Sketch_ui.Workspace.update resized
      (frame ~events:[Event.KeyPressed (Input.KeyChar 'i')] 4) in
  let collapsed_panes = Sketch_ui.Workspace.geometry collapsed (frame 5) in
  check (width collapsed_panes.inspector
      = Sketch_ui.default_layout.collapsed_width)
    "inspector shortcut did not collapse the third column";

  let source = Sop.box ~label:"Inspectable source"
      ~size:(Vec3.create 2. 2. 2.) () in
  let graph = Sop.transform ~label:"Inspectable output"
      (Mat4.translation (Vec3.create 5. 0. 0.)) source in
  let null_factory = Edit_graph.factory ~key:"null" ~label:"Null"
      ~category:["Utility"] ~arity:1 (function
        | [input] -> Sop.null ~label:"Editor null" input
        | _ -> invalid_arg "Null factory expects one input") in
  let environment = Sketch_ui.Environment3.create ~graph
      ~factories:[null_factory]
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun output -> Bridge.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _graph mesh -> Scene3.create [Scene3.mesh mesh]) ()
    |> Result.get_ok in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait count environment =
    let environment = Sketch_ui.Environment3.update environment (frame count) in
    match Sketch_ui.Environment3.prepared environment with
    | Some _ -> environment
    | None when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.001;
        wait (count + 1) environment
    | None -> fail "sketch environment did not publish its initial async cook"
  in
  let environment = wait 0 environment in
  let fps_segment_version environment frame=
    let scene=Sketch_ui.Environment3.scene environment frame in
    let staged=Scene.Private.stage_native_render ~width:frame.Frame.width
      ~height:frame.height scene|>Result.get_ok in
    let version=List.fold_left(fun found->function
      |Scene.Private.Scene2_segment(segment,_)->
          Some(Scene_command.Display_list.version segment)
      |Scene.Private.Scene2_layer _|Scene.Private.Scene3_layer _->found)
      None staged.layers|>Option.get in
    Scene.Private.release scene;
    version in
  let at count fps={ (frame count) with fps }in
  let environment=Sketch_ui.Environment3.update environment(at 1_000 60.)in
  let fps_initial=fps_segment_version environment(at 1_000 60.)in
  let environment=Sketch_ui.Environment3.update environment(at 1_030 120.)in
  let fps_before_deadline=fps_segment_version environment(at 1_030 120.)in
  let environment=Sketch_ui.Environment3.update environment(at 1_061 120.)in
  let fps_after_deadline=fps_segment_version environment(at 1_061 120.)in
  check(fps_before_deadline=fps_initial&&fps_after_deadline>fps_initial)
    "FPS status segment ignored its one-second invalidation deadline";
  check (Sketch_ui.Environment3.selected_node environment = None)
    "camera/render controls should own an unselected inspector";
  let current_frame = frame 10 in
  let panes = Sketch_ui.Environment3.panes environment current_frame in
  check (Easy_camera.control_area (Sketch_ui.Environment3.camera environment)
      = Some panes.view)
    "3D camera gestures are not confined to the view column";
  let inspector_x, inspector_y, _, _ = panes.inspector in
  let camera_header = inspector_x + 32, inspector_y + 36 in
  let collapsed_scene = Sketch_ui.Environment3.scene environment current_frame in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MousePressed (Input.LeftButton, camera_header)] 11) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MouseReleased (Input.LeftButton, camera_header)] 12) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MouseMoved (10, 100)] 13) in
  let expanded_scene = Sketch_ui.Environment3.scene environment (frame 13) in
  check (expanded_scene <> collapsed_scene)
    "workspace camera accordion lost its armed press before the release frame";
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MousePressed (Input.LeftButton, camera_header)] 14) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MouseReleased (Input.LeftButton, camera_header)] 15) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MouseMoved (10, 100)] 16) in
  let render_header = inspector_x + 32, inspector_y + 68 in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MousePressed (Input.LeftButton, render_header)] 17) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MouseReleased (Input.LeftButton, render_header)] 18) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.MouseMoved (10, 100)] 19) in
  check (Sketch_ui.Environment3.scene environment (frame 19) <> collapsed_scene)
    "workspace render accordion lost its armed press before the release frame";
  let graph_tile = List.hd (Sketch_ui.Environment3.graph_nodes environment) in
  let point = center graph_tile.Pxui_graph.bounds in
  let selection_frame = frame ~events:[
      Event.MousePressed (Input.LeftButton, point);
      MouseReleased (Input.LeftButton, point)] 20 in
  let environment = Sketch_ui.Environment3.update environment selection_frame in
  check (Option.map Node.id (Sketch_ui.Environment3.selected_node environment)
      = Some graph_tile.id)
    "graph selection did not replace camera controls with node inspection";
  let camera_frame = frame ~events:[Event.KeyPressed (Input.KeyChar 'c')] 21 in
  let environment = Sketch_ui.Environment3.update environment camera_frame in
  check (Sketch_ui.Environment3.selected_node environment = None)
    "C did not restore the camera/render inspector";
  let source_tile = List.find (fun tile -> tile.Pxui_graph.id = Node.id source)
      (Sketch_ui.Environment3.graph_nodes environment) in
  let view_point = center source_tile.view_bounds in
  let view_frame = frame ~events:[
      Event.MousePressed (Input.LeftButton, view_point);
      MouseReleased (Input.LeftButton, view_point)] 22 in
  let environment = Sketch_ui.Environment3.update environment view_frame in
  check (Node.id (Sketch_ui.Environment3.displayed_node environment)
      = Node.id source)
    "graph VIEW button did not switch the environment display node";
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait_source count environment =
    let environment = Sketch_ui.Environment3.update environment (frame count) in
    match Option.bind (Sketch_ui.Environment3.prepared environment)
        Mesh.centroid with
    | Some center when abs_float center.Vec3.x < 1. -> environment
    | _ when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.001;
        wait_source (count + 1) environment
    | _ -> fail "display-node cook did not publish the selected source preview"
  in
  let environment = wait_source 23 environment in
  check (Sketch_ui.Environment3.scene environment current_frame <> [])
    "sketch environment produced an empty composed scene";
  let _, _, graph_width, graph_height =
    (Sketch_ui.Environment3.panes environment (frame 29)).graph in
  let graph_x, graph_y, _, _ =
    (Sketch_ui.Environment3.panes environment (frame 29)).graph in
  let menu_point = graph_x + (graph_width / 2), graph_y + (graph_height / 2) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space] 29) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~mouse:menu_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] 30) in
  let loose_nodes = Edit_graph.inspect
      (Sketch_ui.Environment3.document environment) in
  let loose_null = List.find (fun info -> info.Edit_graph.operation = "null"
      && info.id <> Node.id graph) loose_nodes in
  check (List.length loose_nodes = 3 && loose_null.inputs = [|None|]
      && Node.id (Sketch_ui.Environment3.displayed_node environment)
         = Node.id source)
    "workspace could not add a disconnected SOP without stealing the display flag";
  let source_tile = List.find (fun tile -> tile.Pxui_graph.id = Node.id source)
      (Sketch_ui.Environment3.graph_nodes environment) in
  let source_point = center source_tile.bounds in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~mouse:source_point ~events:[
        Event.MousePressed (Input.LeftButton, source_point);
        MouseReleased (Input.LeftButton, source_point)] 31) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~mouse:source_point ~events:[Event.KeyPressed Input.Space] 32) in
  let environment = Sketch_ui.Environment3.update environment
      (frame ~mouse:source_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] 33) in
  check (List.length (Edit_graph.inspect
      (Sketch_ui.Environment3.document environment)) = 4
      && Node.operation (Sketch_ui.Environment3.displayed_node environment) = "null")
    "workspace did not apply and display a Space-menu graph edit";
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.KeyPressed (Input.KeyChar 'd')]
        ~mouse:source_point 34 |> fun frame ->
          { frame with Frame.keys = [Input.Meta] }) in
  check (List.length (Edit_graph.inspect
      (Sketch_ui.Environment3.document environment)) = 5)
    "workspace did not apply Command-D subgraph duplication";
  let environment = Sketch_ui.Environment3.update environment
      (frame ~events:[Event.KeyPressed Input.Backspace] 35) in
  check (List.length (Edit_graph.inspect
      (Sketch_ui.Environment3.document environment)) = 4)
    "Backspace did not delete the duplicated node";
  Sketch_ui.Environment3.close environment;

  let environment2 = Sketch_ui.Environment2.create ~graph
      ~max_entries:4 ~max_payload_bytes:(16 * 1024 * 1024)
      ~prepare:(fun output -> Bridge.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene2:(fun _graph _mesh -> Scene.[
        rect ~at:(-60, -40) ~w:120 ~h:80
          ~fill:(Color.hex_exn "#5eead4") ()
      ]) ()
    |> Result.get_ok in
  let deadline = Unix.gettimeofday () +. 2. in
  let rec wait2 count environment =
    let environment = Sketch_ui.Environment2.update environment (frame count) in
    match Sketch_ui.Environment2.prepared environment with
    | Some _ -> environment
    | None when Unix.gettimeofday () < deadline ->
        Unix.sleepf 0.001;
        wait2 (count + 1) environment
    | None -> fail "2D sketch environment did not publish its initial cook"
  in
  let environment2 = wait2 0 environment2 in
  check (Sketch_ui.Environment2.selected_node environment2 = None)
    "2D camera/render controls should own an unselected inspector";
  check (Sketch_ui.Environment2.scene environment2 (frame 10) <> [])
    "2D sketch environment produced an empty composed scene";
  check (Sketch_support.Timeline.time (Sketch_ui.Environment2.timeline environment2)
      > 0.) "shared 2D sketch lifecycle did not advance playback time";
  let hidden_frame = frame ~events:[Event.KeyPressed (Input.KeyChar 'h')] 11 in
  let environment2 = Sketch_ui.Environment2.update environment2 hidden_frame in
  check (Easy_camera2.control_area (Sketch_ui.Environment2.camera environment2)
      = Some (0, 0, hidden_frame.width, hidden_frame.height))
    "hidden 2D sketch UI still reserved invisible workspace bounds";
  let hidden_scene = Sketch_ui.Environment2.scene environment2 hidden_frame in
  check (Sketch_ui.Environment2.scene environment2 (frame 12) == hidden_scene)
    "unchanged hidden 2D scene composition was rebuilt";
  Sketch_ui.Environment2.close environment2;
  print_endline "sketch ui tests passed"
