open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message

let frame ?(mouse = 0, 0) ?(keys = []) ?(events = []) () : Frame.t = {
  width = 1000; height = 700; size = 1000, 700;
  drawable_width = 1000; drawable_height = 700;
  drawable_size = 1000, 700; pixel_scale = 1., 1.;
  time = 0.; dt = 1. /. 60.; fps = 60.; count = 0;
  mouse; mouse_delta = 0, 0; keys; mouse_buttons = []; events;
}

let center (x, y, width, height) = x + (width / 2), y + (height / 2)

let node id view = List.find (fun node -> node.Pxui_graph.id = id)
    (Pxui_graph.node_views view)

let output_port node =
  let x, y, width, height = node.Pxui_graph.bounds in
  x + (width / 2), y + height

let unary_input_port node =
  let x, y, width, _ = node.Pxui_graph.bounds in
  x + (width / 2), y

let midpoint (ax, ay) (bx, by) = (ax + bx) / 2, (ay + by) / 2

let () =
  let source_a = Sop.points ~label:"Source A" [|0., 0., 0.|]
  and source_b = Sop.points ~label:"Source B" [|1., 0., 0.|] in
  let moved_a = Sop.transform ~label:"Move A"
      (Mat4.translation (Vec3.create 0. 1. 0.)) source_a
  and moved_b = Sop.transform ~label:"Move B"
      (Mat4.translation (Vec3.create 0. (-1.) 0.)) source_b in
  let graph = Sop.merge ~label:"Output" [moved_a; moved_b] in
  let view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520 graph in
  let nodes = Pxui_graph.node_views view in
  check (List.length nodes = 5) "graph view lost nodes";
  let depth label =
    (List.find (fun node -> node.Pxui_graph.label = label) nodes).depth in
  check (depth "Source A" = 0 && depth "Move A" = 1 && depth "Output" = 2)
    "graph view is not laid out top-down";
  check (Pxui_graph.selected view = None)
    "graph view should leave the camera inspector active initially";

  let point = center (node (Node.id source_a) view).bounds in
  let view, changes = Pxui_graph.update view
      (frame ~mouse:point ~events:[Event.MousePressed (Input.LeftButton, point);
        MouseReleased (Input.LeftButton, point)] ()) in
  check (Pxui_graph.selected view = Some (Node.id source_a)
      && changes = [Pxui_graph.Selected (Some (Node.id source_a))])
    "graph node click did not update selection";

  let before = (node (Node.id source_a) view).bounds in
  let target = fst point + 45, snd point + 26 in
  let view, changes = Pxui_graph.update view (frame ~mouse:target ~events:[
      Event.MousePressed (Input.LeftButton, point);
      Event.MouseMoved target;
      Event.MouseReleased (Input.LeftButton, target)] ()) in
  let after = (node (Node.id source_a) view).bounds in
  let bx, by, _, _ = before and ax, ay, _, _ = after in
  check (ax - bx = 45 && ay - by = 26)
    "left-drag did not move the selected graph tile";
  check (List.mem (Pxui_graph.Node_moved (Node.id source_a)) changes)
    "node move was not reported";
  let topology = Pxui_graph.stats view in
  check (topology.nodes = 5 && topology.wires = 4)
    "moving a graph tile changed immutable SOP connectivity";

  let before = (node (Node.id source_b) view).bounds in
  let view, _ = Pxui_graph.update view (frame ~mouse:(140, 125) ~events:[
      Event.MousePressed (Input.RightButton, (100, 100));
      Event.MouseMoved (140, 125);
      Event.MouseReleased (Input.RightButton, (140, 125))] ()) in
  let after = (node (Node.id source_b) view).bounds in
  let bx, by, _, _ = before and ax, ay, _, _ = after in
  check (ax - bx = 40 && ay - by = 25)
    "graph right-drag pan did not follow logical pointer movement";

  let before = (node (Node.id source_b) view).bounds in
  let view, _ = Pxui_graph.update view (frame ~mouse:(180, 180)
      ~events:[Event.MousePressed (Input.RightButton, (180, 180))] ()) in
  let visible_view = Pxui_graph.with_visible true view in
  check (visible_view == view)
    "unchanged graph visibility discarded active pointer capture";
  let view, changes = Pxui_graph.update visible_view
      (frame ~mouse:(215, 202) ~events:[Event.MouseMoved (215, 202)] ()) in
  let view, _ = Pxui_graph.update view
      (frame ~mouse:(215, 202)
        ~events:[Event.MouseReleased (Input.RightButton, (215, 202))] ()) in
  let after = (node (Node.id source_b) view).bounds in
  let bx, by, _, _ = before and ax, ay, _, _ = after in
  check (ax - bx = 35 && ay - by = 22
      && List.mem Pxui_graph.View_changed changes)
    "graph right-drag capture did not survive across application frames";

  let source_view = node (Node.id source_b) view in
  let view_button = center source_view.view_bounds in
  let selected_before = Pxui_graph.selected view in
  let view, changes = Pxui_graph.update view
      (frame ~mouse:view_button ~events:[
        Event.MousePressed (Input.LeftButton, view_button);
        MouseReleased (Input.LeftButton, view_button)] ()) in
  check (Pxui_graph.viewed view = Node.id source_b
      && Pxui_graph.selected view = selected_before
      && changes = [Pxui_graph.Viewed (Node.id source_b)])
    "node VIEW button did not change display independently of inspection";

  let view, changes = Pxui_graph.update view
      (frame ~mouse:(400, 250) ~events:[Event.MouseScrolled (0, 2)] ()) in
  check (List.mem Pxui_graph.View_changed changes)
    "graph wheel zoom was not reported";
  let moved = (node (Node.id source_a) view).bounds in
  let view = Pxui_graph.with_graph graph view in
  check (Pxui_graph.with_graph graph view == view)
    "unchanged graph replacement still rebuilt presentation state";
  check ((node (Node.id source_a) view).bounds = moved)
    "graph replacement discarded a stable node's manual position";

  let blank = 30, 535 in
  let view, changes = Pxui_graph.update view
      (frame ~mouse:blank ~events:[Event.MousePressed (Input.LeftButton, blank);
        MouseReleased (Input.LeftButton, blank)] ()) in
  check (Pxui_graph.selected view = None
      && List.mem (Pxui_graph.Selected None) changes)
    "blank graph click did not restore camera-inspector selection";
  check (Pxui_graph.scene view <> []) "visible graph produced an empty scene";
  check (Pxui_graph.scene (Pxui_graph.with_visible false view) = [])
    "hidden graph still produced scene nodes";

  let catalog = [{ Pxui_graph.key = "null"; label = "Null";
      category = ["Utility"]; arity = 1 }] in
  let edit_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog graph in
  let click_shift view id =
    let point = center (node id view).bounds in
    fst (Pxui_graph.update view (frame ~mouse:point ~keys:[Input.Shift]
      ~events:[Event.MousePressed (Input.LeftButton, point);
        MouseReleased (Input.LeftButton, point)] ())) in
  let edit_view = click_shift edit_view (Node.id source_a)
    |> fun view -> click_shift view (Node.id source_b) in
  check (List.length (Pxui_graph.selected_nodes edit_view) = 2)
    "Shift-click did not form a multi-node selection";
  let source_point = center (node (Node.id source_a) edit_view).bounds in
  let target = fst source_point + 31, snd source_point + 19 in
  let before_a = (node (Node.id source_a) edit_view).bounds
  and before_b = (node (Node.id source_b) edit_view).bounds in
  let edit_view, changes = Pxui_graph.update edit_view
      (frame ~mouse:target ~events:[
        Event.MousePressed (Input.LeftButton, source_point);
        MouseMoved target; MouseReleased (Input.LeftButton, target)] ()) in
  let moved_by before after =
    let x0, y0, _, _ = before and x1, y1, _, _ = after in x1 - x0, y1 - y0 in
  check (moved_by before_a (node (Node.id source_a) edit_view).bounds = (31, 19)
      && moved_by before_b (node (Node.id source_b) edit_view).bounds = (31, 19)
      && List.exists (function Pxui_graph.Nodes_moved ids -> List.length ids = 2
        | _ -> false) changes)
    "dragging a multi-selection did not move and report the whole selection";
  let edit_view, changes = Pxui_graph.update edit_view
      (frame ~events:[Event.KeyPressed (Input.KeyChar 'o')] ()) in
  check (List.mem Pxui_graph.Layout_optimized changes)
    "O did not optimize the graph layout";

  let edit_view = Pxui_graph.select (Node.id source_a) edit_view in
  let menu_point = 400, 250 in
  let edit_view, _ = Pxui_graph.update edit_view
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space] ()) in
  let edit_view, changes = Pxui_graph.update edit_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function
      | Pxui_graph.Add_requested request ->
          request.factory_key = "null" && request.inputs = [Node.id source_a]
      | _ -> false) changes)
    "Space search did not emit a connected node-add request";
  let empty_view = Pxui_graph.clear_selection edit_view in
  let empty_view, _ = Pxui_graph.update empty_view
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space] ()) in
  let _, changes = Pxui_graph.update empty_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "null" && request.inputs = [] | _ -> false) changes)
    "Space menu disabled a SOP whose inputs should start disconnected";

  let nested_catalog = [{ Pxui_graph.key = "box"; label = "Box";
      category = ["Create"; "Primitive"]; arity = 0 }] in
  let nested_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog:nested_catalog graph in
  let nested_view, _ = Pxui_graph.update nested_view
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space] ()) in
  let _, changes = Pxui_graph.update nested_view
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Enter;
        Event.KeyPressed Input.Enter; Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "box" | _ -> false) changes)
    "Space menu did not navigate category submenus to a SOP";

  let scrolling_catalog = List.init 15 (fun index -> {
      Pxui_graph.key = Printf.sprintf "node_%02d" index;
      label = Printf.sprintf "Node %02d" index;
      category = ["Utility"]; arity = 0 }) in
  let scrolling_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog:scrolling_catalog graph in
  let scrolling_view, _ = Pxui_graph.update scrolling_view
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space] ()) in
  let scrolling_view, _ = Pxui_graph.update scrolling_view
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Enter] ()) in
  let arrows = List.init 12 (fun _ -> Event.KeyPressed Input.ArrowDown) in
  let _, changes = Pxui_graph.update scrolling_view
      (frame ~mouse:menu_point ~events:(arrows @ [Event.KeyPressed Input.Enter]) ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "node_12" | _ -> false) changes)
    "Space menu's visual row window made later SOPs inaccessible";

  let search_view, _ = Pxui_graph.update
      (Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
         ~catalog:nested_catalog graph)
      (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space] ()) in
  let _, changes = Pxui_graph.update search_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "primitive";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "box" | _ -> false) changes)
    "global Space search did not match a category breadcrumb";

  let clipboard_view = Pxui_graph.select (Node.id source_a) edit_view in
  let clipboard_view, changes = Pxui_graph.update clipboard_view
      (frame ~keys:[Input.Meta]
        ~events:[Event.KeyPressed (Input.KeyChar 'c')] ()) in
  check (changes = []) "Command-C unexpectedly changed graph topology";
  let _, changes = Pxui_graph.update clipboard_view
      (frame ~keys:[Input.Meta]
        ~events:[Event.KeyPressed (Input.KeyChar 'v')] ()) in
  check (List.exists (function Pxui_graph.Paste_requested request ->
      List.length request.positions = 1 | _ -> false) changes)
    "Command-V did not request a fresh subgraph paste";
  let _, changes = Pxui_graph.update clipboard_view
      (frame ~keys:[Input.Meta]
        ~events:[Event.KeyPressed (Input.KeyChar 'd')] ()) in
  check (List.exists (function Pxui_graph.Paste_requested _ -> true
      | _ -> false) changes)
    "Command-D did not request selection duplication";
  let _, changes = Pxui_graph.update clipboard_view
      (frame ~keys:[Input.Meta]
        ~events:[Event.KeyPressed (Input.KeyChar 'x')] ()) in
  check (List.mem (Pxui_graph.Delete_nodes_requested [Node.id source_a]) changes)
    "Command-X did not copy and request deletion of the selection";

  let chain_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog moved_a in
  let wire_point = midpoint
      (output_port (node (Node.id source_a) chain_view))
      (unary_input_port (node (Node.id moved_a) chain_view)) in
  let chain_view, changes = Pxui_graph.update chain_view
      (frame ~mouse:wire_point
        ~events:[Event.MousePressed (Input.LeftButton, wire_point)] ()) in
  check (Option.is_some (Pxui_graph.selected_connection chain_view)
      && List.exists (function Pxui_graph.Connection_selected (Some _) -> true
        | _ -> false) changes)
    "clicking a wire did not select its connection";
  let chain_view, _ = Pxui_graph.update chain_view
      (frame ~mouse:wire_point ~events:[Event.KeyPressed Input.Space] ()) in
  let chain_view, changes = Pxui_graph.update chain_view
      (frame ~mouse:wire_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Insert_requested request ->
      request.factory_key = "null" | _ -> false) changes)
    "Space on a wire did not request atomic unary insertion";
  let _, changes = Pxui_graph.update chain_view
      (frame ~events:[Event.KeyPressed Input.Delete] ()) in
  check (List.exists (function Pxui_graph.Disconnect_requested _ -> true
      | _ -> false) changes)
    "Delete on a selected wire did not request disconnection";

  let disconnected = Edit_graph.of_graph moved_b
      |> Edit_graph.disconnect ~consumer:(Node.id moved_b) ~input_index:0
      |> Result.get_ok in
  let connect_view = Pxui_graph.create_document ~x:20 ~y:30 ~width:800
      ~height:520 disconnected in
  let from_ = output_port (node (Node.id source_b) connect_view)
  and to_ = unary_input_port (node (Node.id moved_b) connect_view) in
  let _, changes = Pxui_graph.update connect_view
      (frame ~mouse:to_ ~events:[Event.MousePressed (Input.LeftButton, from_);
        MouseMoved to_; MouseReleased (Input.LeftButton, to_)] ()) in
  check (List.exists (function Pxui_graph.Connect_requested connection ->
      connection.source = Node.id source_b
      && connection.consumer = Node.id moved_b && connection.input_index = 0
      | _ -> false) changes)
    "port drag did not request a connection";

  let delete_view = Pxui_graph.select (Node.id source_a)
      (Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520 graph) in
  let _, changes = Pxui_graph.update delete_view
      (frame ~events:[Event.KeyPressed Input.Delete] ()) in
  check (List.mem (Pxui_graph.Delete_nodes_requested [Node.id source_a]) changes)
    "Delete did not request removal of selected nodes";

  let full_catalog = Pxui_graph.catalog_of_factories
      Sop_catalog.Editor.factories in
  check (List.length full_catalog = List.length Sop_catalog.Editor.factories)
    "Space-menu conversion dropped a generated SOP descriptor";
  List.iter (fun (entry : Pxui_graph.catalog_entry) ->
    let menu_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
        ~catalog:full_catalog graph in
    let menu_view, _ = Pxui_graph.update menu_view
        (frame ~mouse:menu_point ~events:[Event.KeyPressed Input.Space] ()) in
    let _, changes = Pxui_graph.update menu_view
        (frame ~mouse:menu_point ~events:[Event.TextInput entry.key;
          Event.KeyPressed Input.Enter] ()) in
    check (List.exists (function Pxui_graph.Add_requested request ->
        request.factory_key = entry.key | _ -> false) changes)
      ("Space search cannot reach generated SOP " ^ entry.key)) full_catalog;

  let dense_inputs = List.init 2000 (fun index ->
    Sop.points ~label:(Printf.sprintf "Input %d" index)
      [|float_of_int index, 0., 0.|]) in
  let dense = Sop.merge ~label:"Dense merge" dense_inputs in
  let dense_view = Pxui_graph.create ~width:700 ~height:400 dense in
  let stats = Pxui_graph.stats dense_view in
  check (stats.nodes = 2001 && stats.wires = 2000)
    "large graph indexing lost nodes or wires";
  check (stats.visible_nodes < stats.nodes)
    "large graph visibility culling did not reject off-screen nodes";
  ignore (Pxui_graph.scene dense_view);
  print_endline "pxui graph tests passed"
