open Prismel
open Procedural

let fail message = raise (Failure message)
let check condition message = if not condition then fail message
let pointer (x, y) = float x, float y
let mouse_press (button, point) = Event.MousePressed (button, pointer point)
let mouse_release (button, point) = Event.MouseReleased (button, pointer point)
let mouse_move point = Event.MouseMoved (pointer point)

let frame ?(mouse = 0, 0) ?(keys = []) ?(events = []) () : Frame.t = {
  width = 1000; height = 700; size = 1000, 700;
  drawable_width = 1000; drawable_height = 700;
  drawable_size = 1000, 700; pixel_scale = 1., 1.;
  time = 0.; dt = 1. /. 60.; fps = 60.; count = 0;
  mouse = (float (fst mouse), float (snd mouse));
  mouse_delta = 0., 0.; keys; mouse_buttons = []; events;
}

let center (x, y, width, height) = x + (width / 2), y + (height / 2)

(* The canvas is built inside a UI frame; hit rectangles come from the
   previous frame, so each step first settles the layout without events. *)
let ui = Pxui.Ui.create ()
let update view (frame : Frame.t) =
  let settle = { frame with events = [] } in
  let view, _ = Pxui.Ui.frame ui settle (fun ui -> Pxui_graph.update view ui settle) in
  Pxui.Ui.frame ui frame (fun ui -> Pxui_graph.update view ui frame)
let graph_scene view =
  ignore (update view (frame ()));
  Pxui.Ui.scene ui

let node id view = List.find (fun node -> node.Pxui_graph.id = id)
    (Pxui_graph.node_views view)

let output_port node =
  let x, y, width, _ = node.Pxui_graph.bounds in
  x + width, y + 12

let unary_input_port node =
  let x, y, _, _ = node.Pxui_graph.bounds in
  x, y + 12

let midpoint (ax, ay) (bx, by) = (ax + bx) / 2, (ay + by) / 2

let run_smoke () =
  let started = Unix.gettimeofday () and allocated = Gc.allocated_bytes () in
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
  (* Painting is bounded by visible tiles and on-screen wire spans. *)
  let instances = match Scene.Private.stage_native ~width:1000 ~height:700
      (graph_scene dense_view) with
    | Ok staged -> List.fold_left (fun total -> function
        | Scene.Private.Ui_layer (batch, _) ->
            total + Scene_command.Ui_batch.count batch
        | _ -> total) 0 staged.layers
    | Error message -> fail message in
  check (instances > 0
      && instances < (64 * stats.visible_nodes) + (16 * stats.visible_wires) + 64)
    "large graph painting was not bounded by visible tiles and wire spans";
  Printf.printf "pxui graph 2,001-node smoke: %.6f s, %.0f allocated bytes\n%!"
    (Unix.gettimeofday () -. started) (Gc.allocated_bytes () -. allocated)

let run_grammar () =
  let step = update in
  let a = Sop.points ~label:"a" [|0., 0., 0.|]
  and b = Sop.points ~label:"b" [|1., 0., 0.|] in
  let aa = Sop.null ~label:"aa" a and bb = Sop.null ~label:"bb" b in
  let output = Sop.merge ~label:"out" [aa; bb] in
  let catalog = [Pxui_graph.{ key="null"; label="Null"; category=["Utility"]; arity=1; ports=[] }] in
  let id = Node.id in
  let canvas = Pxui_graph.create ~catalog ~width:800 ~height:500 output
    |> Pxui_graph.place_nodes [id a, 0., 0.; id b, 0., 180.; id aa, 252., 0.;
       id bb, 252., 180.; id output, 516., 0.] in
  let open Pxui_graph in
  List.iter (fun (source, targets) -> List.iter (fun (direction, target) ->
    let next, _ = run_command (select (id source) canvas) (Walk direction) in
    check (selected next = Some (id target)) "walk chose the wrong connected or directional node") targets)
    [a, [Left,a; Right,aa; Down,b; Up,a];
     b, [Left,b; Right,bb; Down,b; Up,a];
     aa, [Left,a; Right,output; Down,bb; Up,aa];
     bb, [Left,b; Right,output; Down,bb; Up,aa];
     output, [Left,aa; Right,output; Down,bb; Up,output]];
  let next, _ = run_command (clear_selection canvas) (Walk Right) in
  check (selected next = Some (id a)) "walk with no selection did not choose the leftmost node";
  let request canvas =
    let canvas, _ = step canvas (frame ()) in
    let _, changes = step canvas (frame ~events:[Event.TextInput "Null";
      Event.KeyPressed Input.Enter] ()) in
    List.find_map (function Insert_requested r -> Some r | _ -> None) changes |> Option.get in
  let adding, _ = run_command ~at:(400,300) (select (id a) canvas) Add in
  let insertion = request adding in
  check (insertion.connection = Edit_graph.{source=id a; consumer=id aa; input_index=0}
      && insertion.at = (256., 0.)
      && List.sort compare insertion.ripple = List.sort compare
         [id aa, 508., 0.; id output, 772., 0.]
      && node_positions canvas = node_positions adding)
    "Tab ripple included an upstream/sibling node, missed a consumer, or moved before reduction";
  let repeated, changes = run_command (select (id aa) (with_last_added "null" canvas)) Repeat in
  check (not (editing repeated) && List.exists (function
    | Insert_requested r -> r.factory_key = "null" && r.connection.source = id aa
        && r.at = (508., 0.) && r.ripple = [id output, 772., 0.]
    | _ -> false) changes) "repeat did not use the append rule or opened a menu";
  let world = create_document ~namespace:"world" ~catalog (Flow_sop.Network.of_geometry (Edit_graph.of_graph output))
    |> carry_last_added ~from:(with_last_added "null" canvas) in
  let _, changes = run_command world Repeat in
  check (List.for_all (function Notice _ -> true | _ -> false) changes && changes <> [])
    "repeat confused equal keys from different contexts";
  let returned = carry_last_added ~from:world canvas |> select (id aa) in
  let _, changes = run_command returned Repeat in
  check (List.exists (function Insert_requested _ -> true | _ -> false) changes)
    "returning to a level lost the last added kind";
  let framed, _ = run_command (select_nodes [id a; id bb] canvas) Frame_selection in
  List.iter (fun node -> let x,y,w,h = (List.find (fun n -> n.id = id node)
      (node_views framed)).bounds in
    check (x >= 24 && y >= 24 && x+w <= 800-24 && y+h <= 500-24)
      "f did not frame the complete selection") [a;bb];
  let targets = List.init 30 (fun i -> Sop.null ~label:(Printf.sprintf "target-%02d" i) a) in
  let document = List.fold_left (fun doc target -> Edit_graph.add_node ~inputs:[|None|]
    target doc |> Result.get_ok) (Edit_graph.add_node a Edit_graph.empty |> Result.get_ok) targets in
  let hints = create_document (Flow_sop.Network.of_geometry document) |> place_nodes
      (List.mapi (fun i node -> id node, 300., float (i*100)) targets)
      |> select (id a) |> fun value -> fst (run_command value Connect_hint) in
  let labels = Private.hint_labels hints in
  check (List.length labels = 30 && List.for_all (fun (label, _, _) -> String.length label = 2) labels
      && List.filteri (fun i _ -> i < 3) labels =
         ["aa", id (List.nth targets 0), Some 0;
          "as", id (List.nth targets 1), Some 0;
          "ad", id (List.nth targets 2), Some 0])
    "30-target hints did not get stable distance-ordered two-letter labels";
  let narrowed, _ = run_command hints (Hint_letter 'a') in
  check (hinting narrowed) "a prefix selected a two-letter hint early";
  let back, _ = run_command narrowed Hint_back in
  let narrowed, _ = run_command back (Hint_letter 'a') in
  let picked, changes = run_command narrowed (Hint_letter 's') in
  check (not (hinting picked) && changes = [Connect_requested Edit_graph.{
    source=id a; consumer=id (List.nth targets 1); input_index=0}])
    "hint backspace or exact selection connected the wrong port";
  let cyclic, _ = run_command (select (id aa) canvas) Connect_hint in
  check (List.for_all (fun (_, candidate, _) -> candidate <> id a && candidate <> id aa)
      (Private.hint_labels cyclic)) "hints offered a cycle or self connection";
  let collapsed = fst (run_command (select (id output) canvas) Point_detail)
    |> select (id a) |> fun v -> fst (run_command v Connect_hint) in
  let label = List.find_map (fun (label,candidate,slot) ->
    if candidate = id output && slot = None then Some label else None)
    (Private.hint_labels collapsed) |> Option.get in
  let expanded = String.fold_left (fun v c -> fst (run_command v (Hint_letter c))) collapsed label in
  check (Private.level expanded (id output) = Some Editor_core.Network_layout.Full
    && Private.hint_labels expanded = ["a", id output, Some 0; "s", id output, Some 1])
    "a collapsed multi-port hint did not open Full and relabel its ports";
  let finding, _ = run_command canvas Find in
  let finding, _ = step finding (frame ()) in
  let found, changes = step finding (frame ~events:[Event.TextInput "sop/merge";
    Event.KeyPressed Input.Enter] ()) in
  check (selected found = Some (id output) && not (editing found)
    && List.mem (Selected (Some (id output))) changes)
    "find did not select by qualified kind and close its shared picker"

let run_value_wires () =
  let box = Sop_catalog.Box.create () in
  let factory = List.find (fun factory -> Edit_graph.factory_key factory = "box")
      Sop_catalog.Editor.factories in
  let geometry = Edit_graph.add_node ~factory box Edit_graph.empty |> Result.get_ok in
  let network, time_id = Flow_sop.Network.add_value_node Flow.Value_kind.Time
      (Flow_sop.Network.of_geometry geometry) |> Result.get_ok in
  let box_id = Node.id box in
  let module Layout = Editor_core.Network_layout in
  let layout = {Layout.empty with rows = Layout.Int_map.singleton box_id
      (Layout.String_map.singleton "uniform_scale" true)} in
  let canvas = Pxui_graph.create_document ~x:20 ~y:30 ~width:800 ~height:520 network
    |> Pxui_graph.with_layout layout
    |> Pxui_graph.place_nodes [time_id, 0., 0.; box_id, 300., 0.] in
  let target = match Pxui_graph.Private.field_bounds canvas ~node:box_id
      ~path:"uniform_scale" with
    | Some (x, y, _, h) -> x - 112, y + h / 2
    | None -> fail "pinned value input did not appear on the card" in
  let source = output_port (node time_id canvas) in
  let _, changes = update canvas (frame ~mouse:target ~events:[
      mouse_press (Input.LeftButton, source); mouse_move target;
      mouse_release (Input.LeftButton, target)] ()) in
  let expected = Pxui_graph.Value_connect_requested {
    source = {Flow_sop.Port.node = time_id; path = "t"};
    target = {Flow_sop.Port.node = box_id; path = "uniform_scale"} } in
  check (List.mem expected changes) "value output drag did not target a parameter row";
  let size = Pxui_graph.Private.field_bounds canvas ~node:box_id ~path:"size"
    |> Option.get in
  let sx, sy, _, _ = size in
  let _, changes = update canvas (frame ~mouse:(sx - 80, sy + 8) ~events:[
      mouse_press (Input.LeftButton, (sx - 80, sy + 8));
      mouse_release (Input.LeftButton, (sx - 80, sy + 8))] ()) in
  check (List.mem (Pxui_graph.Split_requested {node = box_id; group = "size";
    split = true}) changes) "vec3 row did not request a split";
  let split = Pxui_graph.set_split ~node:box_id ~group:"size" ~split:true canvas in
  check (Pxui_graph.Private.field_bounds split ~node:box_id ~path:"size.x" <> None)
    "vec3 split did not expose component rows";
  let hovered, _ = update canvas (frame ~mouse:(sx - 80, sy + 8)
      ~events:[mouse_move (sx - 80, sy + 8)] ()) in
  let _, changes = Pxui_graph.run_command hovered Pxui_graph.Row_pin in
  check (List.mem (Pxui_graph.Row_pinned {node = box_id; path = "size";
    pinned = false}) changes) "s did not pin the hovered vector row";
  let connected = Flow_sop.Network.connect_value
      ~source:{Flow_sop.Port.node = time_id; path = "t"}
      ~target:{Flow_sop.Port.node = box_id; path = "uniform_scale"} network
    |> Result.get_ok in
  let wired = Pxui_graph.with_document connected canvas in
  check ((Pxui_graph.stats wired).wires = 1)
    "typed wire was not indexed with geometry wires";
  (match Sys.getenv_opt "PRISMEL_UI_PREVIEW" with
   | None -> ()
   | Some directory ->
       let resolved = Flow_sop.Value_lane.resolve
           (Flow_sop.Value_lane.create ()) ~time:1. connected |> Result.get_ok in
       let preview = Pxui_graph.with_applied resolved.applied wired in
       Sketch.export ~directory ~prefix:"flow-value" ~frames:1
         ~config:{Sketch.default_config with width=840; height=560}
         (fun _ -> Scene.clear (Color.rgb 228 139 161) :: graph_scene preview));
  let point = (Pxui_graph.Private.edge_query_points wired ~limit:1).(0) in
  let selected, _ = update wired (frame ~mouse:point ~events:[
      mouse_press (Input.LeftButton, point); mouse_release (Input.LeftButton, point)] ()) in
  let _, changes = Pxui_graph.delete_selection selected in
  check (List.mem (Pxui_graph.Value_disconnect_requested
      {Flow_sop.Port.node = box_id; path = "uniform_scale"}) changes)
    "selected typed wire did not request disconnection";
  let hidden = Pxui_graph.create_document ~x:20 ~y:30 ~width:800 ~height:520 network
    |> Pxui_graph.place_nodes [time_id, 0., 0.; box_id, 300., 0.] in
  let math = Flow.Value_kind.Math in
  let math_ports = Flow_sop.Port.parameters
      (Flow.Value_kind.fields (Flow.Value_kind.make math)) |> Result.get_ok
    |> List.filter_map (fun (parameter : Flow_sop.Port.parameter) ->
      Option.map (fun ty -> parameter.path, ty) parameter.ty) in
  let catalog = Pxui_graph.catalog_of_factories [factory] @ [Pxui_graph.{
      key = "value/math"; label = "Math"; category = ["Math"]; arity = 0;
      ports = math_ports }] in
  let menu_canvas = Pxui_graph.create_document ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog network |> Pxui_graph.place_nodes
        [time_id, 0., 0.; box_id, 300., 0.]
      |> Pxui_graph.select time_id in
  let menu_canvas, _ = Pxui_graph.run_command menu_canvas Pxui_graph.Add in
  check (Array.mem "value/math" (Pxui_graph.Private.menu_keys menu_canvas ~query:"math")
    && Array.mem "box" (Pxui_graph.Private.menu_keys menu_canvas ~query:"box"))
    "Tab from a value output did not include compatible value and SOP kinds";
  let _, changes = update menu_canvas (frame ~events:[
      Event.TextInput "value/math"; Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "value/math" && request.inputs = []
      && request.source = Some {Flow_sop.Port.node = time_id; path = "t"}
      | _ -> false) changes)
    "Tab from a value node did not preserve the typed append source";
  let drag_canvas = Pxui_graph.create_document ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog network |> Pxui_graph.place_nodes
        [time_id, 0., 0.; box_id, 300., 0.] in
  let blank = 400, 450 in
  let from = output_port (node time_id drag_canvas) in
  let dropped, _ = update drag_canvas (frame ~mouse:blank ~events:[
      mouse_press (Input.LeftButton, from); mouse_move blank;
      mouse_release (Input.LeftButton, blank)] ()) in
  check (Array.mem "value/math" (Pxui_graph.Private.menu_keys dropped ~query:"math")
    && Array.mem "box" (Pxui_graph.Private.menu_keys dropped ~query:"box"))
    "value wire release on empty canvas did not open compatible search";
  check (Pxui_graph.Private.field_bounds hidden ~node:box_id
    ~path:"uniform_scale" = None) "hidden-row test chose a visible parameter";
  let source = output_port (node time_id hidden) in
  let target_tile = node box_id hidden in
  let x, y, _, _ = target_tile.bounds in
  let hover = x + 40, y + 12 in
  let dragging, _ = update hidden (frame ~mouse:source
      ~events:[mouse_press (Input.LeftButton, source)] ()) in
  let bloomed, _ = update dragging (frame ~mouse:hover
      ~events:[mouse_move hover] ()) in
  let target = match Pxui_graph.Private.field_bounds bloomed ~node:box_id
      ~path:"uniform_scale" with
    | Some (x, y, _, h) -> x - 112, y + h / 2
    | None -> fail "drag hover did not expand hidden parameter rows" in
  let _, changes = update bloomed (frame ~mouse:target
      ~events:[mouse_move target; mouse_release (Input.LeftButton, target)] ()) in
  check (List.mem expected changes) "hidden-row drop did not request a value drive";
  let body = x + 90, y + 12 in
  let _, changes = update hidden (frame ~mouse:body ~events:[
      mouse_press (Input.LeftButton, source); mouse_move body;
      mouse_release (Input.LeftButton, body)] ()) in
  check (List.exists (function Pxui_graph.Value_connect_requested {source; target} ->
      source.node = time_id && target.node = box_id && target.path = "size"
      | _ -> false) changes)
    "value wire drop on a node body missed its first compatible parameter";
  let hinted, _ = Pxui_graph.run_command (Pxui_graph.select time_id hidden)
      Pxui_graph.Connect_hint in
  let labels = Pxui_graph.Private.hint_labels hinted in
  let first = match labels with [(label, id, None)] when id = box_id -> label
    | _ -> fail "value hint did not offer the target tile" in
  let expanded, changes = Pxui_graph.run_command hinted
      (Pxui_graph.Hint_letter first.[0]) in
  check (List.mem (Pxui_graph.Level_changed [box_id]) changes)
    "value hint did not expose hidden rows";
  let label, _, _ = List.hd (Pxui_graph.Private.hint_labels expanded) in
  let _, changes = String.fold_left (fun (value, changes) letter ->
      let value, emitted = Pxui_graph.run_command value
          (Pxui_graph.Hint_letter letter) in
      value, changes @ emitted) (expanded, []) label in
  check (List.exists (function Pxui_graph.Value_connect_requested {source; target} ->
      source.node = time_id && target.node = box_id | _ -> false) changes)
    "value hint did not request a typed connection"

let run () =
  run_grammar ();
  run_value_wires ();
  let source_a = Sop.points ~label:"Source A" [|0., 0., 0.|]
  and source_b = Sop.points ~label:"Source B" [|1., 0., 0.|] in
  let moved_a = Sop.transform ~label:"Move A"
      (Mat4.translation (Vec3.create 0. 1. 0.)) source_a
  and moved_b = Sop.transform ~label:"Move B"
      (Mat4.translation (Vec3.create 0. (-1.) 0.)) source_b in
  let graph = Sop.merge ~label:"Output" [moved_a; moved_b] in
  let view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520 graph in
  (match Sys.getenv_opt "PRISMEL_UI_PREVIEW" with
   | Some directory ->
       Sketch.export ~directory ~prefix:"graph" ~frames:1
         ~config:{ Sketch.default_config with width=840; height=560 }
         (fun _ -> Scene.clear (Color.rgb 228 139 161)
           :: graph_scene view)
   | None -> ());
  let nodes = Pxui_graph.node_views view in
  check (List.length nodes = 5) "graph view lost nodes";
  let depth label =
    (List.find (fun node -> node.Pxui_graph.label = label) nodes).depth in
  check (depth "Source A" = 0 && depth "Move A" = 1 && depth "Output" = 2)
    "graph view has incorrect longest-path columns";
  check (Pxui_graph.selected view = None)
    "graph view should leave the camera inspector active initially";

  let point = center (node (Node.id source_a) view).bounds in
  let view, changes = update view
      (frame ~mouse:point ~events:[mouse_press (Input.LeftButton, point);
        mouse_release (Input.LeftButton, point)] ()) in
  check (Pxui_graph.selected view = Some (Node.id source_a)
      && changes = [Pxui_graph.Selected (Some (Node.id source_a))])
    "graph node click did not update selection";

  let before = (node (Node.id source_a) view).bounds in
  let target = fst point + 45, snd point + 26 in
  let view, pressed = update view (frame ~mouse:point ~events:[
      mouse_press (Input.LeftButton, point)] ()) in
  let view, moved = update view (frame ~mouse:target ~events:[
      mouse_move target] ()) in
  ignore (graph_scene view);
  let during = (node (Node.id source_a) view).bounds in
  let dx, dy, _, _ = during and bx, by, _, _ = before in
  check (dx - bx = 45 && dy - by = 26)
    "active graph drag did not retain its presentation offset";
  let view, released = update view (frame ~mouse:target ~events:[
      mouse_release (Input.LeftButton, target)] ()) in
  let changes = pressed @ moved @ released in
  let after = (node (Node.id source_a) view).bounds in
  let bx, by, _, _ = before and ax, ay, _, _ = after in
  check (ax - bx = 48 && ay - by = 24)
    "left-drag did not move the selected graph tile";
  check (List.mem (Pxui_graph.Node_moved (Node.id source_a)) changes)
    "node move was not reported";
  let topology = Pxui_graph.stats view in
  check (topology.nodes = 5 && topology.wires = 4)
    "moving a graph tile changed immutable SOP connectivity";
  check (topology.spatial_cells > 0
      && topology.max_spatial_candidates < 128)
    "graph spatial hit index exceeded its candidate bound";
  let moved_center = center (node (Node.id source_a) view).bounds in
  let click view point = fst (update view (frame ~mouse:point ~events:[
      mouse_press (Input.LeftButton, point);
      mouse_release (Input.LeftButton, point)] ())) in
  let probe = click view (center (node (Node.id graph) view).bounds) in
  let probe = click probe moved_center in
  check (Pxui_graph.selected probe = Some (Node.id source_a))
    "released graph tile did not take clicks at its retained position";
  let source_wire_hit view = Pxui_graph.Private.edge_query_points view ~limit:4
    |> Array.exists (fun point ->
      match Pxui_graph.Private.hit_edge_id view point with
      | Some connection -> connection.Edit_graph.source = Node.id source_a
      | None -> false) in
  check (source_wire_hit view)
    "released graph wire was not queryable after rebuilding the edge index";
  let previous = view in
  let start = center (node (Node.id source_a) view).bounds in
  let finish = fst start + 120, snd start + 80 in
  let view, _ = update view (frame ~mouse:start ~events:[
      mouse_press (Input.LeftButton, start)] ()) in
  let view, _ = update view (frame ~mouse:finish ~events:[
      mouse_move finish] ()) in
  let view, _ = update view (frame ~mouse:finish ~events:[
      mouse_release (Input.LeftButton, finish)] ()) in
  check (source_wire_hit view && source_wire_hit previous)
    "repeated edge-index rebuild lost the moved wire or changed the old view";
  let old_visible = (Pxui_graph.stats previous).visible_nodes
  and new_visible = (Pxui_graph.stats view).visible_nodes in
  check ((Pxui_graph.stats previous).visible_nodes = old_visible
      && (Pxui_graph.stats view).visible_nodes = new_visible)
    "edge-index rebuild shared mutable query marks with the old view";

  let before = (node (Node.id source_b) view).bounds in
  let view, _ = update view (frame ~mouse:(140, 125) ~events:[
      mouse_press (Input.RightButton, (100, 100));
      mouse_move (140, 125);
      mouse_release (Input.RightButton, (140, 125))] ()) in
  let after = (node (Node.id source_b) view).bounds in
  let bx, by, _, _ = before and ax, ay, _, _ = after in
  check (ax - bx = 40 && ay - by = 25)
    "graph right-drag pan did not follow logical pointer movement";

  let before = (node (Node.id source_b) view).bounds in
  let view, _ = update view (frame ~mouse:(180, 180)
      ~events:[mouse_press (Input.RightButton, (180, 180))] ()) in
  let visible_view = Pxui_graph.with_visible true view in
  check (visible_view == view)
    "unchanged graph visibility discarded active pointer capture";
  let view, changes = update visible_view
      (frame ~mouse:(215, 202) ~events:[mouse_move (215, 202)] ()) in
  let view, _ = update view
      (frame ~mouse:(215, 202)
        ~events:[mouse_release (Input.RightButton, (215, 202))] ()) in
  let after = (node (Node.id source_b) view).bounds in
  let bx, by, _, _ = before and ax, ay, _, _ = after in
  check (ax - bx = 35 && ay - by = 22
      && List.mem Pxui_graph.View_changed changes)
    "graph right-drag capture did not survive across application frames";

  let source_view = node (Node.id source_b) view in
  let view_button = center source_view.view_bounds in
  let selected_before = Pxui_graph.selected view in
  let view, changes = update view
      (frame ~mouse:view_button ~events:[
        mouse_press (Input.LeftButton, view_button);
        mouse_release (Input.LeftButton, view_button)] ()) in
  check (Pxui_graph.viewed view = Node.id source_b
      && Pxui_graph.selected view = selected_before
      && changes = [Pxui_graph.Viewed (Node.id source_b)])
    "node VIEW button did not change display independently of inspection";

  let view, changes = update view
      (frame ~mouse:(400, 250) ~events:[Event.MouseScrolled (0., 2.)] ()) in
  check (List.mem Pxui_graph.View_changed changes)
    "graph wheel zoom was not reported";
  let moved = (node (Node.id source_a) view).bounds in
  let view = Pxui_graph.with_graph graph view in
  check (Pxui_graph.with_graph graph view == view)
    "unchanged graph replacement still rebuilt presentation state";
  check ((node (Node.id source_a) view).bounds = moved)
    "graph replacement discarded a stable node's manual position";

  let blank = 30, 535 in
  let view, changes = update view
      (frame ~mouse:blank ~events:[mouse_press (Input.LeftButton, blank);
        mouse_release (Input.LeftButton, blank)] ()) in
  check (Pxui_graph.selected view = None
      && List.mem (Pxui_graph.Selected None) changes)
    "blank graph click did not restore camera-inspector selection";
  check (graph_scene view <> []) "visible graph produced an empty scene";
  let _, hidden_changes = update (Pxui_graph.with_visible false view) (frame ()) in
  check (hidden_changes = [] && Pxui.Ui.scene ui = [])
    "hidden graph still produced scene nodes";

  let catalog = [{ Pxui_graph.key = "null"; label = "Null";
      category = ["Utility"]; arity = 1; ports = [] }] in
  let edit_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog graph in
  let click_shift view id =
    let point = center (node id view).bounds in
    fst (update view (frame ~mouse:point
      ~events:[Event.KeyPressed Input.Shift; mouse_press (Input.LeftButton, point);
        Event.KeyReleased Input.Shift; mouse_release (Input.LeftButton, point)] ())) in
  let edit_view = click_shift edit_view (Node.id source_a)
    |> fun view -> click_shift view (Node.id source_b) in
  check (List.length (Pxui_graph.selected_nodes edit_view) = 2)
    "Shift-click did not form a multi-node selection";
  let source_point = center (node (Node.id source_a) edit_view).bounds in
  let target = fst source_point + 31, snd source_point + 19 in
  let before_a = (node (Node.id source_a) edit_view).bounds
  and before_b = (node (Node.id source_b) edit_view).bounds in
  let edit_view, changes = update edit_view
      (frame ~mouse:target ~events:[
        mouse_press (Input.LeftButton, source_point);
        mouse_move target; mouse_release (Input.LeftButton, target)] ()) in
  let moved_by before after =
    let x0, y0, _, _ = before and x1, y1, _, _ = after in x1 - x0, y1 - y0 in
  check (moved_by before_a (node (Node.id source_a) edit_view).bounds = (36, 24)
      && moved_by before_b (node (Node.id source_b) edit_view).bounds = (36, 24)
      && List.exists (function Pxui_graph.Nodes_moved ids -> List.length ids = 2
        | _ -> false) changes)
    "dragging a multi-selection did not move and report the whole selection";
  let moved = (node (Node.id source_a) edit_view).bounds in
  let edit_view = Pxui_graph.optimize_layout edit_view in
  check ((node (Node.id source_a) edit_view).bounds <> moved)
    "optimize_layout did not re-run the automatic layout";

  let edit_view = Pxui_graph.select (Node.id source_a) edit_view in
  let menu_point = 400, 250 in
  let edit_view, _ = update (Pxui_graph.open_menu_at menu_point edit_view)
      (frame ~mouse:menu_point ()) in
  let edit_view, changes = update edit_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function
      | Pxui_graph.Add_requested request ->
          request.factory_key = "null" && request.inputs = [Node.id source_a]
      | _ -> false) changes)
    "Space search did not emit a connected node-add request";
  let empty_view = Pxui_graph.clear_selection edit_view in
  let empty_view, _ = update (Pxui_graph.open_menu_at menu_point empty_view)
      (frame ~mouse:menu_point ()) in
  let _, changes = update empty_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "null" && request.inputs = [] | _ -> false) changes)
    "Space menu disabled a SOP whose inputs should start disconnected";

  let nested_catalog = [{ Pxui_graph.key = "box"; label = "Box";
      category = ["Create"; "Primitive"]; arity = 0; ports = [] }] in
  let nested_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog:nested_catalog graph in
  let nested_view, _ = update (Pxui_graph.open_menu_at menu_point nested_view)
      (frame ~mouse:menu_point ()) in
  (* A lone top-level category (Create) opens by itself; hovering a
     category opens its column to the right, clicking an entry adds it.
     Rows sit one search row below the menu's top (400, 250). *)
  let row_y = 250 + 3 + 24 + 12 in
  let hover view x = fst (update view (frame ~mouse:(x, row_y)
      ~events:[Event.MouseMoved (float x, float row_y)] ())) in
  let nested_view = hover nested_view 420 in
  let point = float (420 + 286), float row_y in
  let _, changes = update nested_view (frame ~mouse:(420 + 286, row_y)
      ~events:[Event.MousePressed (Input.LeftButton, point);
        Event.MouseReleased (Input.LeftButton, point)] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "box" | _ -> false) changes)
    "node menu did not open category submenus on hover down to a SOP";

  let scrolling_catalog = List.init 15 (fun index -> {
      Pxui_graph.key = Printf.sprintf "node_%02d" index;
      label = Printf.sprintf "Node %02d" index;
      category = ["Utility"]; arity = 0; ports = [] }) in
  let scrolling_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog:scrolling_catalog graph in
  let scrolling_view, _ = update (Pxui_graph.open_menu_at menu_point scrolling_view)
      (frame ~mouse:menu_point ()) in
  let scrolling_view, _ = update scrolling_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "node"] ()) in
  let arrows = List.init 12 (fun _ -> Event.KeyPressed Input.ArrowDown) in
  let _, changes = update scrolling_view
      (frame ~mouse:menu_point ~events:(arrows @ [Event.KeyPressed Input.Enter]) ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "node_12" | _ -> false) changes)
    "Space menu's visual row window made later SOPs inaccessible";

  let search_view, _ = update
      (Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
         ~catalog:nested_catalog graph |> Pxui_graph.open_menu_at menu_point)
      (frame ~mouse:menu_point ()) in
  let _, changes = update search_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "primitive";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "box" | _ -> false) changes)
    "global Space search did not match a category breadcrumb";
  let search_view, _ = update
      (Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
         ~catalog:nested_catalog graph |> Pxui_graph.open_menu_at menu_point)
      (frame ~mouse:menu_point ()) in
  let _, changes = update search_view
      (frame ~mouse:menu_point ~events:[Event.TextInput "prmtv";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Add_requested request ->
      request.factory_key = "box" | _ -> false) changes)
    "node search did not use the shared fuzzy matching rule";

  let clipboard_view = Pxui_graph.select (Node.id source_a) edit_view in
  let clipboard_view = Pxui_graph.copy_selection clipboard_view in
  let _, changes = Pxui_graph.run_command clipboard_view Paste in
  check (List.exists (function Pxui_graph.Paste_requested request ->
      List.length request.positions = 1 | _ -> false) changes)
    "Command-V did not request a fresh subgraph paste";
  let _, changes = Pxui_graph.run_command clipboard_view Duplicate in
  check (List.exists (function Pxui_graph.Paste_requested _ -> true
      | _ -> false) changes)
    "Command-D did not request selection duplication";
  let _, changes = Pxui_graph.run_command clipboard_view Cut in
  check (List.mem (Pxui_graph.Delete_nodes_requested [Node.id source_a]) changes)
    "Command-X did not copy and request deletion of the selection";

  let chain_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
      ~catalog moved_a in
  let wire_point = midpoint
      (output_port (node (Node.id source_a) chain_view))
      (unary_input_port (node (Node.id moved_a) chain_view)) in
  let chain_view, changes = update chain_view
      (frame ~mouse:wire_point
        ~events:[mouse_press (Input.LeftButton, wire_point);
          mouse_release (Input.LeftButton, wire_point)] ()) in
  check (Option.is_some (Pxui_graph.selected_connection chain_view)
      && List.exists (function Pxui_graph.Connection_selected (Some _) -> true
        | _ -> false) changes)
    "clicking a wire did not select its connection";
  let chain_view, _ = update (Pxui_graph.open_menu_at wire_point chain_view)
      (frame ~mouse:wire_point ()) in
  let chain_view, changes = update chain_view
      (frame ~mouse:wire_point ~events:[Event.TextInput "null";
        Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Insert_requested request ->
      request.factory_key = "null" | _ -> false) changes)
    "Space on a wire did not request atomic unary insertion";
  let _, changes = Pxui_graph.delete_selection chain_view in
  check (List.exists (function Pxui_graph.Disconnect_requested _ -> true
      | _ -> false) changes)
    "Delete on a selected wire did not request disconnection";

  let disconnected = Edit_graph.of_graph moved_b
      |> Edit_graph.disconnect ~consumer:(Node.id moved_b) ~input_index:0
      |> Result.get_ok in
  let connect_view = Pxui_graph.create_document ~x:20 ~y:30 ~width:800
      ~height:520 (Flow_sop.Network.of_geometry disconnected) in
  let from_ = output_port (node (Node.id source_b) connect_view)
  and to_ = unary_input_port (node (Node.id moved_b) connect_view) in
  let _, changes = update connect_view
      (frame ~mouse:to_ ~events:[mouse_press (Input.LeftButton, from_);
        mouse_move to_; mouse_release (Input.LeftButton, to_)] ()) in
  check (List.exists (function Pxui_graph.Connect_requested connection ->
      connection.source = Node.id source_b
      && connection.consumer = Node.id moved_b && connection.input_index = 0
      | _ -> false) changes)
    "port drag did not request a connection";
  let cancelled, changes = update connect_view
      (frame ~mouse:to_ ~events:[mouse_press (Input.LeftButton, from_);
        mouse_move to_; Event.PointerCancelled Input.LeftButton;
        mouse_release (Input.LeftButton, to_)] ()) in
  check (changes = [] && Pxui_graph.stats cancelled = Pxui_graph.stats connect_view)
    "a cancelled port drag still requested a connection";

  let delete_view = Pxui_graph.select (Node.id source_a)
      (Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520 graph) in
  let _, changes = Pxui_graph.delete_selection delete_view in
  check (List.mem (Pxui_graph.Delete_nodes_requested [Node.id source_a]) changes)
    "Delete did not request removal of selected nodes";

  (* Context menus: a right click opens one, a right drag only pans, and rows
     emit the ordinary typed changes. *)
  let right_click (x, y) = frame ~mouse:(x, y) ~events:[
      mouse_press (Input.RightButton, (x, y));
      mouse_release (Input.RightButton, (x, y))] () in
  let left_click (x, y) = frame ~mouse:(x, y) ~events:[
      mouse_press (Input.LeftButton, (x, y));
      mouse_release (Input.LeftButton, (x, y))] () in
  let menu_row (x, y) index = x + 60, y + 3 + (index * 24) + 12 in
  let tile = node (Node.id source_a) view in
  let tile_point = center tile.bounds in
  let context_view, _ = update view (right_click tile_point) in
  let _, changes = update context_view (left_click (menu_row tile_point 3)) in
  check (List.mem (Pxui_graph.Delete_nodes_requested [Node.id source_a]) changes)
    "tile context menu Delete did not request node removal";
  let blank = 780, 520 in
  let context_view, _ = update view (right_click blank) in
  let _, changes = update context_view (left_click (menu_row blank 2)) in
  check (List.mem Pxui_graph.View_changed changes)
    "canvas context menu Frame all did not reframe the graph";
  let dragged_view, changes = update view (frame ~mouse:(780, 490) ~events:[
      mouse_press (Input.RightButton, blank); mouse_move (780, 490);
      mouse_release (Input.RightButton, (780, 490))] ()) in
  check (List.mem Pxui_graph.View_changed changes) "right drag did not pan";
  let _, changes = update dragged_view (left_click (menu_row (780, 490) 2)) in
  check (changes = []) "a right drag opened a context menu";

  let full_catalog = Pxui_graph.catalog_of_factories
      Sop_catalog.Editor.factories in
  check (List.length full_catalog = List.length Sop_catalog.Editor.factories)
    "Space-menu conversion dropped a generated SOP descriptor";
  List.iter (fun (entry : Pxui_graph.catalog_entry) ->
    let menu_view = Pxui_graph.create ~x:20 ~y:30 ~width:800 ~height:520
        ~catalog:full_catalog graph in
    let menu_view, _ = update (Pxui_graph.open_menu_at menu_point menu_view)
        (frame ~mouse:menu_point ()) in
    let index = Pxui_graph.Private.menu_keys menu_view ~query:entry.key |> Array.to_list
      |> List.mapi (fun i key -> i, key)
      |> List.find_map (fun (i,key) -> if key = entry.key then Some i else None) |> Option.get in
    let _, changes = update menu_view
        (frame ~mouse:menu_point ~events:(Event.TextInput entry.key
          :: List.init index (fun _ -> Event.KeyPressed Input.ArrowDown)
          @ [Event.KeyPressed Input.Enter]) ()) in
    check (List.exists (function Pxui_graph.Add_requested request ->
        request.factory_key = entry.key | _ -> false) changes)
      ("Space search cannot reach generated SOP " ^ entry.key)) full_catalog;

  (* Flow layout, level grammar, polylines and native UI row edits. *)
  let module L = Editor_core.Network_layout in
  let chain = Pxui_graph.create ~width:900 ~height:600 moved_a in
  let x_source, y_source = Option.get (Pxui_graph.node_position chain (Node.id source_a))
  and x_dest, y_dest = Option.get (Pxui_graph.node_position chain (Node.id moved_a)) in
  check (x_source = 0. && x_dest = 252. && y_source = 0. && y_dest = 0.)
    "Flow columns did not snap the 256-point pitch";
  check (Pxui_graph.node_positions chain = Pxui_graph.node_positions
    (Pxui_graph.optimize_layout chain)) "Flow auto layout is not deterministic";
  check (Pxui_graph.with_graph moved_a chain == chain) "unchanged Flow graph lost its identity path";
  let wire = (Pxui_graph.Private.edge_query_points chain ~limit:1).(0) in
  check (Pxui_graph.Private.hit_edge_id chain wire <> None
    && Pxui_graph.Private.hit_edge_id chain (fst wire, snd wire + 7) = None)
    "polyline hit tolerance is not six logical points";
  let chain, changes = update chain (frame ~mouse:wire ~keys:[Input.Alt] ~events:[
    mouse_press (Input.LeftButton, wire); mouse_release (Input.LeftButton, wire)] ()) in
  let port = L.slot (Node.id moved_a) 0 in
  let bends view = Option.value ~default:[] (L.Port_map.find_opt port (Pxui_graph.layout view).bends) in
  check (List.length (bends chain) = 1 && List.exists (function
    | Pxui_graph.Bend_changed _ -> true | _ -> false) changes) "Alt-click did not author a bend";
  let bx, by = List.hd (bends chain) in
  (* Resolve the bend's screen coordinate through the retained node origin. *)
  let nx, ny, _, _ = (node (Node.id source_a) chain).bounds in
  let at = nx + int_of_float bx, ny + int_of_float by in
  let target = fst at + 24, snd at + 36 in
  let chain, _ = update chain (frame ~mouse:at ~events:[mouse_press (Input.LeftButton, at)] ()) in
  let chain, _ = update chain (frame ~mouse:target ~events:[mouse_move target] ()) in
  let chain, _ = update chain (frame ~mouse:target ~events:[mouse_release (Input.LeftButton, target)] ()) in
  check (bends chain = [bx +. 24., by +. 36.]) "bend drag did not move and snap the bend";
  let chain, _ = update chain (frame ~mouse:target ~keys:[Input.Alt] ~events:[
    mouse_press (Input.LeftButton, target); mouse_release (Input.LeftButton, target)] ()) in
  check (bends chain = []) "Alt-click did not remove the bend handle";
  let start = fst wire, snd wire - 30 and finish = fst wire, snd wire + 30 in
  check (List.length (Pxui_graph.Private.crossed_wires chain start finish) = 1)
    "knife intersection missed the trunk";
  check (Pxui_graph.Private.crossed_wires chain (fst wire + 100, snd wire - 30)
    (fst wire + 100, snd wire + 30) = []) "knife cut a noncrossing wire";
  let _, changes = update chain (frame ~mouse:finish ~keys:[Input.Meta] ~events:[
    mouse_press (Input.LeftButton, start); mouse_move finish;
    mouse_release (Input.LeftButton, finish)] ()) in
  check (List.exists (function Pxui_graph.Cut_wires_requested [_] -> true | _ -> false) changes)
    "knife did not emit one atomic cut";
  let two_branches = Pxui_graph.create ~width:900 ~height:600 graph in
  let source_x, _, source_w, _ = (node (Node.id source_a) two_branches).bounds
  and dest_x, _, _, _ = (node (Node.id moved_a) two_branches).bounds in
  let cut_x = (source_x + source_w + dest_x) / 2 in
  let crossed = Pxui_graph.Private.crossed_wires two_branches (cut_x, 0) (cut_x, 500) in
  check (List.map (fun c -> c.Edit_graph.consumer) crossed |> List.sort Int.compare
    = List.sort Int.compare [Node.id moved_a; Node.id moved_b])
    "knife did not isolate the two crossed branches";
  let schema = Parameter.schema ~name:"flow_rows" ~default:(1., "note") [
    Parameter.field ~name:"amount" ~folder:["Shape"] ~default:1.
      ~kind:(Parameter.floating ~min:0. ~max:150. ())
      ~get:fst ~set:(fun v (_, note) -> v, note) ();
    Parameter.field ~name:"note" ~folder:["Advanced"] ~default:"note" ~kind:Parameter.Text
      ~get:snd ~set:(fun note (v, _) -> v, note) ()] in
  let row_node = Custom.map ~operation:"flow_rows" ~schema ~values:(1., "note") source_a
    (fun ~parameters:_ ~context:_ geometry -> Ok geometry) in
  let rid = Node.id row_node in
  let rows = Pxui_graph.create ~width:900 ~height:600 row_node |> Pxui_graph.select rid in
  let field_bounds view path = Pxui_graph.Private.field_bounds view ~node:rid ~path in
  check (field_bounds rows "amount" <> None && field_bounds rows "note" = None)
    "card exposure did not use first-folder defaults";
  let height view = let _, _, _, h = (node rid view).bounds in h in
  check (height rows = 78) "card did not render one parameter and one more row";
  let rows, _ = Pxui_graph.run_command rows Open_detail in
  check (height rows = 150) "full did not render both folder headers and both fields";
  check (Pxui_graph.Private.level rows rid = Some L.Full && field_bounds rows "note" <> None)
    "opening detail did not expose all folders";
  let rows, _ = Pxui_graph.run_command rows Point_detail in
  check (Pxui_graph.Private.level rows rid = Some L.Point) "p did not collapse the selection";
  check (height rows = 24) "point retained card rows";
  let rows, _ = Pxui_graph.run_command rows Point_detail in
  check (Pxui_graph.Private.level rows rid = Some L.Full) "p did not restore the prior level";
  let rows, _ = Pxui_graph.run_command (Pxui_graph.clear_selection rows) Open_all in
  check (Pxui_graph.Private.level rows rid = Some L.Card) "Shift-O did not open every card";
  let field = center (Option.get (field_bounds rows "amount")) in
  let row_label = let x,y,_,_ = (node rid rows).bounds in x+30,y+36 in
  let over, _ = update rows (frame ~mouse:row_label ~events:[mouse_move row_label] ()) in
  check (Pxui_graph.hovered_row over = Some (rid,"amount"))
    "row labels did not own shared PXUI hover";
  let over, _ = update over (frame ~mouse:field ~events:[mouse_move field] ()) in
  check (Pxui_graph.hovered_row over = Some (rid,"amount"))
    "field hover did not belong to its row";
  let target = fst row_label+24,snd row_label+12 in
  let moved, changes = update (Pxui_graph.clear_selection rows)
      (frame ~mouse:target ~events:[mouse_press (Input.LeftButton,row_label);
        mouse_move target; mouse_release (Input.LeftButton,target)] ()) in
  check (Pxui_graph.selected moved = Some rid
      && Pxui_graph.node_position moved rid <> Pxui_graph.node_position rows rid
      && List.mem (Pxui_graph.Node_moved rid) changes)
    "row label capture did not retain node selection and drag";
  let target = fst field + 10, snd field in
  let _, changes = update rows (frame ~mouse:target ~events:[mouse_press (Input.LeftButton, field);
    mouse_move target; mouse_release (Input.LeftButton, target)] ()) in
  check (List.exists (function Pxui_graph.Set_parameter_requested { path="amount";
    value=Parameter.Float_value v; _ } -> v = 11. | _ -> false) changes)
    "canvas scrub did not use soft range / 150";
  let _, changes = update rows (frame ~mouse:target ~keys:[Input.Shift] ~events:[
    mouse_press (Input.LeftButton, field); mouse_move target;
    mouse_release (Input.LeftButton, target)] ()) in
  check (List.exists (function Pxui_graph.Set_parameter_requested { path="amount";
    value=Parameter.Float_value v; _ } -> v = 2. | _ -> false) changes)
    "Shift-scrub did not use soft range / 1500";
  let rows, _ = update rows (frame ~mouse:field ~events:[mouse_press (Input.LeftButton, field);
    mouse_release (Input.LeftButton, field)] ()) in
  let _, changes = update rows (frame ~mouse:field ~events:[Event.TextInput "42.25";
    Event.KeyPressed Input.Enter] ()) in
  check (List.exists (function Pxui_graph.Set_parameter_requested { path="amount";
    value=Parameter.Float_value v; _ } -> v = 42.25 | _ -> false) changes)
    "click-to-type did not commit through the shared text editor";
  let zoomed, _ = update (Pxui_graph.select rid rows) (frame ~mouse:(600,300)
    ~events:(mouse_move (600,300) :: List.init 30 (fun _ -> Event.MouseScrolled (0., -1.))) ()) in
  check (Pxui_graph.Private.zoom zoomed = 0.25 && Pxui_graph.Private.level zoomed rid = Some L.Card)
    "explicitly opened cards did not ignore the zoom cap";
  let unpinned = Pxui_graph.with_layout { (Pxui_graph.layout rows) with pinned=L.Int_map.empty } rows in
  let zoomed, _ = update unpinned (frame ~mouse:(600,300)
    ~events:(mouse_move (600,300) :: List.init 30 (fun _ -> Event.MouseScrolled (0., -1.))) ()) in
  check (Pxui_graph.Private.level zoomed rid = Some L.Point)
    (Printf.sprintf "zoom cap did not collapse unpinned nodes (zoom %.2f)" (Pxui_graph.Private.zoom zoomed));
  let chipped, _ = update unpinned (frame ~mouse:(600,300)
    ~events:(mouse_move (600,300) :: List.init 7 (fun _ -> Event.MouseScrolled (0., -1.))) ()) in
  check (Pxui_graph.Private.zoom chipped >= 0.34 && Pxui_graph.Private.zoom chipped < 0.50
    && Pxui_graph.Private.level chipped rid = Some L.Chip) "middle zoom cap did not show chips";
  let point_all, _ = Pxui_graph.run_command rows Point_all in
  check (List.for_all (fun n -> Pxui_graph.Private.level point_all n.Pxui_graph.id = Some L.Point)
    (Pxui_graph.node_views point_all)) "Shift-P left expanded nodes";
  let restored, _ = Pxui_graph.run_command point_all Point_all in
  check (Pxui_graph.Private.level restored rid = Some L.Card) "Shift-P did not restore prior cards";
  let chip_layout = { (Pxui_graph.layout rows) with level=L.Int_map.add rid L.Chip L.Int_map.empty } in
  let bloom = Pxui_graph.with_layout chip_layout rows in
  let output = output_port (node (Node.id source_a) bloom) in
  let tx, ty, _, _ = (node rid bloom).bounds in
  let target = tx + 60, ty + 12 in
  let bloom, _ = update bloom (frame ~mouse:output
    ~events:[mouse_press (Input.LeftButton, output)] ()) in
  let bloom, _ = update bloom (frame ~mouse:target ~events:[mouse_move target] ()) in
  check (Pxui_graph.Private.level bloom rid = Some L.Full
    && L.Int_map.find rid (Pxui_graph.layout bloom).level = L.Chip)
    "wire hover did not temporarily bloom a chip";
  let bloom, _ = update bloom (frame ~mouse:(800,500) ~events:[mouse_move (800,500)] ()) in
  check (Pxui_graph.Private.level bloom rid = Some L.Chip) "bloom did not clear when the pointer left";
  ignore (update bloom (frame ~mouse:(800,500)
    ~events:[mouse_release (Input.LeftButton, (800,500))] ()));
  let detail = Pxui_graph.with_layout chip_layout rows in
  let click_detail view = fst (update view (frame ~mouse:target ~events:[
    mouse_press (Input.LeftButton, target); mouse_release (Input.LeftButton, target)] ())) in
  let detail = click_detail detail |> click_detail in
  check (Pxui_graph.Private.level detail rid = Some L.Card
    && L.Int_map.find rid (Pxui_graph.layout detail).pinned) "double-click did not open and pin a chip";
  let amount_hidden = L.String_map.singleton "amount" false in
  let pin_layout = { (Pxui_graph.layout rows) with rows=L.Int_map.singleton rid amount_hidden } in
  let hidden = Pxui_graph.with_layout pin_layout rows in
  check (field_bounds hidden "amount" = None) "row pin did not hide a primary row";
  let shown = Pxui_graph.with_layout { pin_layout with rows=L.Int_map.singleton rid
    (L.String_map.singleton "note" true) } rows in
  check (field_bounds shown "note" <> None) "row pin did not expose a hidden row";

  run_smoke ();
  print_endline "pxui graph tests passed"
