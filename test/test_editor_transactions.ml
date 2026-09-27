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
    let step ?(mouse = (0., 0.)) ?(keys = []) events =
      incr count;
      current := E.update !current (Test_editor_input.frame ~keys mouse events !count) in
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
    let control = float (ix + 165), float (iy + 46) in
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
    let label = float (ix + 20), float (iy + 46) in
    step ~mouse:label (click label); step ~mouse:label (click label);
    step [Event.TextInput "invalid"]; step [Event.KeyPressed Input.Enter];
    check (value (Node.id second) = Parameter.Int_value 1 && E.can_redo !current)
      "invalid numeric edit changed the document or history";
    step [Event.KeyPressed Input.Escape];
    check (value (Node.id second) = Parameter.Int_value 1 && E.can_redo !current)
      "cancelled numeric edit changed the document or history";
    print_endline "editor transactions: stable selection/inspector target, undo agreement and graph-aware drawing reuse passed")
