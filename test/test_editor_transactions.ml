open Prismel
open Procedural
module E = Prismel_editor.Editor2

let check condition message = if not condition then failwith message
let run () =
  let rec source ~label ~inputs:_ value =
    Node.parameterize ~schema:Test_editor_commands.schema ~values:value ~rebuild:source
      (Sop.points ~label [|float value, 0., 0.|]) in
  let first = source ~label:"first" ~inputs:[] 0
  and second = source ~label:"second" ~inputs:[] 1 in
  let draws = Atomic.make 0 in
  let current = ref (E.create ~graph:(Sop.merge [first; second])
    ~prepare:(fun _ _ -> Ok ()) ~scene2:(fun _ () -> Atomic.incr draws; []) () |> Result.get_ok)
  and count = ref 0 in
  Fun.protect ~finally:(fun () -> E.close !current) (fun () ->
    let step ?(mouse = (0., 0.)) ?(keys = []) ?(buttons = []) events =
      incr count;
      current := E.update !current (Test_editor_input.frame ~keys ~buttons mouse events !count) in
    let click point = [Event.MousePressed (Input.LeftButton, point);
      Event.MouseReleased (Input.LeftButton, point)] in
    let wait_draw after = Test_editor_cook.await (fun () -> step []; Atomic.get draws > after) in
    wait_draw 0;
    let value id = Edit_graph.find (E.document !current) ~node_id:id |> Option.get
      |> Node.parameter_fields |> List.find (fun (field : Parameter.field_view) -> field.name = "value")
      |> fun field -> field.current in
    let tile = List.find (fun tile -> tile.Pxui_graph.id = Node.id second) (E.graph_nodes !current) in
    let x, y, w, h = tile.bounds in
    let selected = float (x + w / 2), float (y + h / 2) in
    step ~mouse:selected (click selected); step [];
    let ix, iy, _, _ = (E.panes !current (Test_editor_input.frame (0., 0.) [] 0))
      .Pxui_shell.Layout.inspector in
    let control = float (ix + 165), float (iy + 70) in
    let before = Atomic.get draws in
    (* Re-select the stable id and edit its already visible inspector in one frame. *)
    step ~mouse:control (click selected @ click control);
    check (value (Node.id first) = Parameter.Int_value 0
      && value (Node.id second) <> Parameter.Int_value 1)
      "same-frame selection/inspection edited the wrong stable node";
    check (E.can_undo !current) "inspector edit did not enter document history";
    wait_draw before;
    let before = Atomic.get draws in
    step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'z')];
    check (value (Node.id first) = Parameter.Int_value 0
      && value (Node.id second) = Parameter.Int_value 1 && E.can_redo !current)
      "inspector undo did not restore the history present";
    wait_draw before;
    check (Atomic.get draws >= 3) "changed graph with the same prepared value retained a stale drawing";
    count := !count + 30;
    let label = float (ix + 40), float (iy + 70) in
    step ~mouse:label (click label); step ~mouse:label (click label);
    step [Event.TextInput "invalid"]; step [Event.KeyPressed Input.Enter];
    check (value (Node.id second) = Parameter.Int_value 1 && E.can_redo !current)
      "invalid numeric edit changed the document or history";
    step [Event.KeyPressed Input.Escape];
    check (value (Node.id second) = Parameter.Int_value 1 && E.can_redo !current)
      "cancelled numeric edit changed the document or history";
    let directory = Filename.temp_dir "prismel-flow-history" "" in
    Fun.protect ~finally:(fun () ->
      Array.iter (fun file -> Sys.remove (Filename.concat directory file)) (Sys.readdir directory);
      Unix.rmdir directory) (fun () ->
      let snapshot () = E.crash_dump !current directory;
        Yojson.Safe.from_file (Filename.concat directory "document.json") in
      let tile id = List.find (fun tile -> tile.Pxui_graph.id = id) (E.graph_nodes !current) in
      let header id = let x, y, _, _ = (tile id).bounds in float (x + 50), float (y + 12) in
      let undo () = step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'z')] in
      count := !count + 30;
      let at = header (Node.id second) in
      step ~mouse:at (click at); step [];
      let before = snapshot () in
      step [Event.KeyPressed (Input.KeyChar 'o')];
      step [Event.KeyPressed (Input.KeyChar 'p')];
      check (snapshot () <> before) "detail-level commands did not change saved layout";
      undo ();
      check (snapshot () = before) "detail levels did not merge into one Burst entry";
      step [];
      count := !count + 90;
      let x, y, _, _ = (tile (Node.id second)).bounds in
      let at = float (x + 145), float (y + 36) in
      let original = value (Node.id second) in
      step ~mouse:at ~buttons:[Input.LeftButton] [Event.MousePressed (Input.LeftButton, at)];
      List.iter (fun dx -> let target = fst at +. dx, snd at in
        step ~mouse:target ~buttons:[Input.LeftButton] [Event.MouseMoved target]) [3.; 6.; 9.];
      let target = fst at +. 12., snd at in
      step ~mouse:target [Event.MouseReleased (Input.LeftButton, target)];
      check (value (Node.id second) <> original) "canvas integer scrub did not edit the node";
      undo ();
      check (snapshot () = before) "canvas scrub did not undo in one gesture";
      step []; count := !count + 90;
      let at = header (Node.id second) in
      step ~mouse:at ~buttons:[Input.LeftButton] [Event.MousePressed (Input.LeftButton, at)];
      List.iter (fun dx -> let target = fst at +. dx, snd at in
        step ~mouse:target ~buttons:[Input.LeftButton] [Event.MouseMoved target]) [6.; 12.; 18.];
      let target = fst at +. 24., snd at in
      step ~mouse:target [Event.MouseReleased (Input.LeftButton, target)];
      check (snapshot () <> before) "canvas movement did not change saved positions";
      let first_move = snapshot () in
      count := !count + 90;
      let at = header (Node.id second) in
      step ~mouse:at ~buttons:[Input.LeftButton] [Event.MousePressed (Input.LeftButton, at)];
      let target = fst at +. 24., snd at in
      step ~mouse:target ~buttons:[Input.LeftButton] [Event.MouseMoved target];
      step ~mouse:target [Event.MouseReleased (Input.LeftButton, target)];
      undo ();
      check (snapshot () = first_move) "separate node drags merged after release";
      undo ();
      check (snapshot () = before) "canvas movement did not undo in one gesture";
      step []; count := !count + 90;
      step [Event.KeyPressed Input.Home]; step [];
      let source_x, source_y, source_w, _ = (tile (Node.id first)).bounds in
      let root = Edit_graph.root (E.document !current) |> Option.get in
      let dest_x, dest_y, _, _ = (tile root).bounds in
      let scale = float source_w /. 196. in
      let wire = float (source_x + source_w + dest_x) /. 2.,
        (float (source_y + dest_y) /. 2.) +. 12. *. scale in
      let before_bend = snapshot () in
      step ~mouse:wire ~keys:[Input.Alt] ~buttons:[Input.LeftButton]
        [Event.MousePressed (Input.LeftButton, wire)];
      List.iter (fun dy -> let target = fst wire, snd wire +. dy in
        step ~mouse:target ~keys:[Input.Alt] ~buttons:[Input.LeftButton]
          [Event.MouseMoved target]) [12.; 24.; 36.];
      let target = fst wire, snd wire +. 36. in
      step ~mouse:target ~keys:[Input.Alt] [Event.MouseReleased (Input.LeftButton, target)];
      check (snapshot () <> before_bend) "bend gesture did not change the saved layout";
      undo ();
      check (snapshot () = before_bend) "bend add and drag did not undo in one gesture";
      let at = header (Node.id second) in
      step ~mouse:at (click at); step [];
      let before_group = snapshot () in
      let before_draws = Atomic.get draws in
      step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'g')];
      check (snapshot () <> before_group
        && List.exists (fun tile -> tile.Pxui_graph.operation = "flow_compound")
          (E.graph_nodes !current))
        "group command did not replace the selected tile with a compound";
      wait_draw before_draws;
      let grouped = snapshot () in
      let instance = List.find (fun tile ->
        tile.Pxui_graph.operation = "flow_compound") (E.graph_nodes !current) in
      let instance_id = instance.id in
      check (Option.fold ~none:false ~some:(fun node ->
        Node.id node = instance_id) (E.selected_node !current))
        "group did not select the new compound instance";
      let at = header instance_id in
      step ~mouse:at [Event.MousePressed (Input.RightButton, at);
        Event.MouseReleased (Input.RightButton, at)];
      step [];
      let action = fst at +. 60., snd at +. 3. +. 5. *. 24. +. 12. in
      step ~mouse:action (click action);
      check (snapshot () <> grouped)
        "compound context menu did not make the instance unique";
      let unique = snapshot () in
      undo ();
      check (snapshot () = grouped) "make unique was not one undo step";
      step ~keys:[Input.Meta; Input.Shift]
        [Event.KeyPressed (Input.KeyChar 'z')];
      check (snapshot () = unique) "make unique redo changed its copied ids";
      undo ();
      check (snapshot () = grouped) "make unique undo did not restore sharing";
      step [Event.KeyPressed (Input.KeyChar 'i')];
      check (List.exists (fun tile -> tile.Pxui_graph.id = Node.id second)
        (E.graph_nodes !current)
        && List.exists (fun tile -> tile.Pxui_graph.operation = "flow_inputs")
          (E.graph_nodes !current))
        "enter did not open the compound definition";
      step [Event.KeyPressed Input.Home]; step [];
      let outputs_tile = List.find (fun tile ->
        tile.Pxui_graph.operation = "flow_outputs") (E.graph_nodes !current) in
      let ox, oy, ow, oh = outputs_tile.bounds in
      let at = float (ox + ow / 2), float (oy + oh / 2) in
      step ~mouse:at (click at); step [];
      check (Option.fold ~none:false ~some:(fun node ->
        Node.id node = outputs_tile.id) (E.selected_node !current))
        "compound Outputs marker was not selected";
      let before_rename = snapshot () in
      let ix, iy, _, _ = (E.panes !current
        (Test_editor_input.frame (0., 0.) [] 0)).Pxui_shell.Layout.inspector in
      let port_field = float (ix + 100), float (iy + 94) in
      step ~mouse:port_field (click port_field);
      step [];
      step ~keys:[Input.Meta] [Event.KeyPressed (Input.KeyChar 'a')];
      step [Event.TextInput "mesh"];
      step [Event.KeyPressed Input.Enter];
      check (snapshot () <> before_rename)
        "compound inspector did not rename its output interface";
      let blank_graph = 430., 500. in
      step ~mouse:blank_graph (click blank_graph); step [];
      undo ();
      check (snapshot () = before_rename)
        "interface rename was not one undo step";
      step [Event.KeyPressed (Input.KeyChar 'u')];
      check (List.exists (fun tile -> tile.Pxui_graph.id = instance_id)
        (E.graph_nodes !current)
        && Option.fold ~none:false ~some:(fun node -> Node.id node = instance_id)
          (E.selected_node !current)
        && snapshot () = grouped)
        "up did not restore the parent graph and select its instance";
      let before_ungroup_draws = Atomic.get draws in
      step ~keys:[Input.Meta; Input.Shift]
        [Event.KeyPressed (Input.KeyChar 'g')];
      check (List.for_all (fun tile ->
        tile.Pxui_graph.operation <> "flow_compound") (E.graph_nodes !current)
        && List.exists (fun tile -> tile.Pxui_graph.operation = "points"
          && tile.id <> Node.id first && tile.id <> Node.id second)
          (E.graph_nodes !current))
        "ungroup did not replace the instance with a fresh node";
      wait_draw before_ungroup_draws;
      let ungrouped = snapshot () in
      undo ();
      check (snapshot () = grouped) "ungroup was not one undo step";
      step ~keys:[Input.Meta; Input.Shift]
        [Event.KeyPressed (Input.KeyChar 'z')];
      check (snapshot () = ungrouped) "ungroup redo changed fresh IDs";
      undo ();
      check (snapshot () = grouped) "ungroup undo did not restore the instance";
      undo ();
      check (snapshot () = before_group) "group was not one undo step";
      step ~keys:[Input.Meta; Input.Shift]
        [Event.KeyPressed (Input.KeyChar 'z')];
      check (snapshot () = grouped) "redo changed the grouped definition or compiled ids");
    print_endline "editor transactions: stable selection/inspector target, undo agreement and graph-aware drawing reuse passed")
