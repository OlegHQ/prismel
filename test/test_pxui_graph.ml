open Prismel

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

(* ------------------------------------------------------- the node menu *)

module Node_menu = Pxui_graph.Node_menu

(* The menu is built inside a UI frame; hit rectangles come from the previous frame, so each
   step first settles the layout without events. *)
let menu_ui = Pxui.Ui.create ()
let bounds = 20, 30, 800, 520
let menu_step menu (frame : Frame.t) =
  let settle = { frame with events = [] } in
  match Pxui.Ui.frame menu_ui settle (fun ui -> Node_menu.update menu ui ~bounds) with
  | None, _ -> None, None
  | Some menu, _ -> Pxui.Ui.frame menu_ui frame (fun ui -> Node_menu.update menu ui ~bounds)

let menu_of entries = Node_menu.create ~x:400 ~y:250 entries
let entry ?(arity = 0) ?(category = [ "Utility" ]) key label = { Node_menu.key; label; category; arity }
let picks menu events = snd (menu_step menu (frame ~mouse:(400, 250) ~events ()))
let opened entries = match menu_step (menu_of entries) (frame ~mouse:(400, 250) ()) with
  | Some menu, _ -> menu | None, _ -> fail "the menu closed without input"

let run_menu () =
  (* a SOP with an input picks like any other: typing its name and Enter *)
  let null = [ entry ~arity:1 "null" "Null" ] in
  check (picks (opened null) [ Event.TextInput "null"; Event.KeyPressed Input.Enter ] = Some "null")
    "the menu search did not pick a node";
  check (menu_step (opened null) (frame ~mouse:(400, 250) ~events:[ Event.KeyPressed Input.Escape ] ())
         = (None, None))
    "Escape did not close the menu";
  (* A lone top-level category (Create) opens by itself; hovering a category opens its column
     to the right, clicking an entry picks it.  Rows sit one search row below the menu's top. *)
  let nested = [ entry ~category:[ "Create"; "Primitive" ] "box" "Box" ] in
  let row_y = 250 + 3 + 24 + 12 in
  let menu = match menu_step (opened nested) (frame ~mouse:(420, row_y)
      ~events:[ Event.MouseMoved (420., float row_y) ] ()) with
    | Some menu, _ -> menu | None, _ -> fail "hovering closed the menu" in
  let point = float (420 + 286), float row_y in
  let _, picked = menu_step menu (frame ~mouse:(420 + 286, row_y)
    ~events:[ Event.MousePressed (Input.LeftButton, point); Event.MouseReleased (Input.LeftButton, point) ] ()) in
  check (picked = Some "box") "the menu did not open category submenus on hover down to a node";
  (* the visual row window never makes later nodes inaccessible *)
  let many = List.init 15 (fun index -> entry (Printf.sprintf "node_%02d" index) (Printf.sprintf "Node %02d" index)) in
  let menu = match menu_step (opened many) (frame ~mouse:(400, 250) ~events:[ Event.TextInput "node" ] ()) with
    | Some menu, _ -> menu | None, _ -> fail "typing closed the menu" in
  let arrows = List.init 12 (fun _ -> Event.KeyPressed Input.ArrowDown) in
  check (picks menu (arrows @ [ Event.KeyPressed Input.Enter ]) = Some "node_12")
    "the menu's row window made later nodes inaccessible";
  (* global search matches a category breadcrumb and uses the shared fuzzy rule *)
  check (picks (opened nested) [ Event.TextInput "primitive"; Event.KeyPressed Input.Enter ] = Some "box")
    "global search did not match a category breadcrumb";
  check (picks (opened nested) [ Event.TextInput "prmtv"; Event.KeyPressed Input.Enter ] = Some "box")
    "node search did not use the shared fuzzy matching rule";
  (* every generated SOP can be reached by typing its key *)
  let entries = Node_menu.entries_of_factories Sop_catalog.Editor.factories in
  check (List.length entries = List.length Sop_catalog.Editor.factories)
    "the menu conversion dropped a generated SOP descriptor";
  List.iter (fun (e : Node_menu.entry) ->
    let menu = opened entries in
    let index = Node_menu.Private.keys menu ~query:e.key
      |> List.mapi (fun i key -> i, key)
      |> List.find_map (fun (i, key) -> if key = e.key then Some i else None) |> Option.get in
    check (picks menu (Event.TextInput e.key :: List.init index (fun _ -> Event.KeyPressed Input.ArrowDown)
                       @ [ Event.KeyPressed Input.Enter ]) = Some e.key)
      ("the menu cannot reach generated SOP " ^ e.key)) entries;
  print_endline "pxui graph node menu tests passed"

(* ------------------------------------------------- the workspace pane (W4) *)

module Scope = Pxui_graph.Scope
module P = Flow_sop.Projection

let cases = "../specification/workspace/cases"
let scope_catalog = Editor_document.Contexts.catalog ~version:1 Sop_catalog.Editor.factories |> Result.get_ok
let load_workspace name =
  let text = In_channel.with_open_bin (Filename.concat cases (name ^ ".lisp")) In_channel.input_all in
  match Flow.Syntax.parse text with
  | Error d -> fail (Flow.Diagnostic.to_string d)
  | Ok forms -> (match Flow.Workspace.check scope_catalog forms with
      | Some w, _ -> w
      | None, _ -> fail (name ^ " did not check"))
let scope_ui = Pxui.Ui.create ()
let scope_step view (frame : Frame.t) =
  let settle = { frame with events = [] } in
  let view, _ = Pxui.Ui.frame scope_ui settle (fun ui -> Scope.update view ui settle) in
  Pxui.Ui.frame scope_ui frame (fun ui -> Scope.update view ui frame)
let recorded ?inputs workspace =
  Flow_sop.Probe.make (Result.get_ok (Flow.Eval.static ~record:true ?inputs workspace))
let scope_view ?inputs ?probe ?at ?collapsed workspace graph =
  let scope = P.of_graph scope_catalog workspace graph in
  Scope.create ~width:1000 ~height:700 ()
  |> Scope.with_scope ?probe ?at ?collapsed ~key:graph scope
  |> Scope.with_records (recorded ?inputs workspace), scope
let scope_paint view =
  ignore (scope_step view (frame ()));
  match Scene.Private.stage_native ~width:1000 ~height:700 (Pxui.Ui.scene scope_ui) with
  | Error message -> fail message
  | Ok staged -> List.fold_left (fun total -> function
      | Scene.Private.Ui_layer (batch, _) -> total + Scene_command.Ui_batch.count batch
      | _ -> total) 0 staged.layers
let click point = [mouse_press (Input.LeftButton, point); mouse_release (Input.LeftButton, point)]
let scope_click view point =
  scope_step view (frame ~mouse:point ~events:(mouse_move point :: click point) ())
let rect_center (x, y, w, h) = int_of_float (x +. w /. 2.), int_of_float (y +. h /. 2.)

let scope_connection_hover () =
  let ws = Editor_document.Workspace_doc.of_text scope_catalog
    "(workspace hover (graph g :context sop (let* [a (sop/box) b (sop/transform a) c (sop/transform a)] (sop/merge b c))))"
    |> Result.get_ok in
  let view, _ = scope_view ~at:(function
    | ["g"; "a"] -> Some (0., 0.) | ["g"; "b"] -> Some (400., 0.)
    | ["g"; "c"] -> Some (400., 240.)
    | ["g"; "@result"] -> Some (800., 600.) | _ -> None) ws.checked "g" in
  let view, _ = scope_step view (frame ()) in
  let highlight point =
    let point = int_of_float (fst point), int_of_float (snd point) in
    let hovered, changes = scope_step view (frame ~mouse:point ~events:[mouse_move point] ()) in
    check (changes = []) "hover edited the graph";
    Scope.Private.highlighted_connections hovered in
  let source = Option.get (Scope.Private.output_socket view ["g"; "a"]) in
  let fanout = highlight source in
  check (List.length fanout = 2) "an output hover did not highlight its two connections";
  let ax, ay = source in
  let bx, _, _, _ = Option.get (Scope.Private.box_of view ["g"; "c"]) in
  let _, by = Option.get (Scope.Private.row_center view ["g"; "c"] 0) in
  let wire_hover = highlight ((ax +. bx) /. 2., (ay +. by) /. 2.) in
  check (List.length wire_hover = 1)
    (Printf.sprintf "hover on a wire did not isolate its connection: %d at %.1f %.1f; %s"
      (List.length wire_hover) ((ax +. bx) /. 2.) ((ay +. by) /. 2.)
      (String.concat "; " (List.map (fun ((a,b),(c,d)) -> Printf.sprintf "%.1f,%.1f -> %.1f,%.1f" a b c d) fanout)));
  check (List.length (highlight (bx, by)) = 1) "an input hover did not isolate its connection";
  check (highlight (999., 699.) = []) "connections stayed highlighted after leaving them";
  let ws = Editor_document.Workspace_doc.of_text scope_catalog
    "(workspace capture (graph g :context sop (let* [a (sop/box) copies (for [i (range 2)] (sop/transform a :translate [i 0 0]))] (sop/merge copies))))"
    |> Result.get_ok in
  let view, scope = scope_view ws.checked "g" in
  let view, _ = scope_step view (frame ()) in
  let zone = Option.get (P.find scope ["g"; "copies"]) in
  let rail = (Option.get zone.zone).rail in
  let index = Option.get (List.find_index (fun (r : P.rail_row) -> r.role = P.Capture && r.name = "a") rail) in
  let x, y, _, _ = Option.get (Scope.Private.box_of view zone.path) in
  let point = int_of_float x, int_of_float (y +. (P.rail_top zone +. (float index +. 0.5) *. P.row_height) *. Scope.zoom view) in
  let hovered, changes = scope_step view (frame ~mouse:point ~events:[mouse_move point] ()) in
  check (changes = [] && List.length (Scope.Private.highlighted_connections hovered) = 1)
    "hover on a captured value's socket missed its outer connection"

(* A trackpad pinch zooms the graph where the wheel does: at the pointer, the
   frame's pinch factors multiplied, clamped like the wheel. *)
let scope_pinch () =
  let w = load_workspace "bloom" in
  let view, _ = scope_view w "flower" in
  let view = fst (scope_step view (frame ())) in
  let before = Scope.zoom view in
  let point = 500, 350 in
  let zoomed events =
    Scope.zoom (fst (scope_step view (frame ~mouse:point ~events:(mouse_move point :: events) ()))) in
  let near a b = Float.abs (a -. b) < 1e-9 in
  check (before > 0.3 && before < 2.0) "the bloom framing leaves no room to zoom both ways";
  check (near (zoomed [ Event.MousePinched 1.25 ]) (before *. 1.25))
    "a pinch did not zoom the graph by its factor";
  check (near (zoomed [ Event.MousePinched 0.8 ]) (before *. 0.8))
    "a pinch below one did not zoom the graph out";
  check (near (zoomed [ Event.MousePinched 1.1; Event.MousePinched 1.1 ]) (before *. 1.21))
    "two pinches in a frame did not multiply";
  check (zoomed [ Event.MousePinched 100. ] = 2.5) "a huge pinch escaped the zoom clamp";
  check (zoomed [ Event.MousePinched 0.001 ] = 0.25) "a tiny pinch escaped the zoom clamp";
  check (near (zoomed [ Event.MouseScrolled (0., 1.) ]) (before *. 1.1))
    "the wheel no longer zooms by a tenth a step";
  (* the point under the pointer stays put, as with the wheel *)
  let anchored =
    let view = fst (scope_step view (frame ~mouse:point ~events:[ mouse_move point; Event.MousePinched 1.5 ] ())) in
    Scope.zoom view in
  check (anchored > before) "pinch-out did not enlarge";
  (* a pinch outside the pane is not the pane's *)
  let outside = 3000, 3000 in
  let unmoved = fst (scope_step view (frame ~mouse:outside ~events:[ mouse_move outside; Event.MousePinched 1.5 ] ())) in
  check (Scope.zoom unmoved = before) "a pinch away from the pane zoomed it"

(* W12b: every W3 gesture the pane can make reaches the host as its request. *)
(* A carried payload: the pane reports the node under the pointer (the path), or its empty canvas
   (the graph's own one-segment path), hovering and then released; it never edits. *)
let scope_carry () =
  let frame ?mouse ?keys ?events () =
    { (frame ?mouse ?keys ?events ()) with width = 3000; height = 2000; size = (3000, 2000);
      drawable_width = 3000; drawable_height = 2000; drawable_size = (3000, 2000) } in
  let w = load_workspace "bloom" in
  let scope = P.of_graph scope_catalog w "flower" in
  let view = Scope.create ~width:3000 ~height:2000 () |> Scope.with_scope ~key:"flower" scope
    |> Scope.with_records (recorded w) in
  let heart = [ "flower"; "heart" ] in
  let view = fst (scope_step view (frame ())) in
  let x, y, bw, bh = Option.get (Scope.Private.box_of view heart) in
  let over = int_of_float (x +. bw /. 2.), int_of_float (y +. bh -. 4.) in
  let nothing = 2900, 1900 in
  let drops changes = List.filter_map (function
    | Scope.Drop_over { path; kind; value } -> Some (`Over, path, kind, value)
    | Dropped { path; kind; value } -> Some (`Dropped, path, kind, value)
    | _ -> None) changes in
  (* idle frames report nothing *)
  let view, changes = scope_step view (frame ~mouse:over ~events:[ mouse_move over ] ()) in
  check (drops changes = []) "a pane with nothing carried reported a drop";
  Pxui.Ui.carry scope_ui ~kind:"material" ~value:"(ref cobalt)" ();
  let view, changes = scope_step view (frame ~mouse:over ~events:[ mouse_move over ] ()) in
  check (drops changes = [ `Over, heart, "material", "(ref cobalt)" ]) "a carry over a node did not report the node's path";
  let view, changes = scope_step view (frame ~mouse:nothing ~events:[ mouse_move nothing ] ()) in
  check (drops changes = [ `Over, [ "flower" ], "material", "(ref cobalt)" ])
    "a carry over the empty canvas did not report the graph";
  let view, changes = scope_step view (frame ~mouse:over ~events:[ mouse_move over ] ()) in
  check (List.length (drops changes) = 1) "one place under the pointer";
  let view, changes = scope_step view (frame ~mouse:over ~events:[ mouse_press (Input.LeftButton, over) ] ()) in
  check (drops changes = [ `Dropped, heart, "material", "(ref cobalt)" ]) "a put over a node did not emit Dropped with its path";
  check (not (List.exists (function Scope.Syntax_edit _ | Selected _ | Moved _ -> true | _ -> false) changes))
    "the pane edited, selected or moved on a put";
  check (Pxui.Ui.carrying scope_ui = None) "the payload outlived its put";
  let _, changes = scope_step view (frame ~mouse:over ~events:[ mouse_release (Input.LeftButton, over) ] ()) in
  check (drops changes = []) "the release after a put reported a drop";
  (* the marks of a carry paint without changing what the pane reports *)
  let marked = Scope.with_carry ~lit:[ heart, "a" ] ~hot:(Some (heart, true)) view in
  ignore (scope_step marked (frame ()))

let scope_gestures () =
  let module E = Flow_sop.Flow_edit in
  let module S = Flow.Syntax in
  let syntax op = Scope.Syntax_edit op in
  (* a large window keeps the zoom at 1, where every field is built *)
  let frame ?mouse ?keys ?events () =
    { (frame ?mouse ?keys ?events ()) with width = 3000; height = 2000; size = (3000, 2000);
      drawable_width = 3000; drawable_height = 2000; drawable_size = (3000, 2000) } in
  let scope_click view point =
    scope_step view (frame ~mouse:point ~events:(mouse_move point :: click point) ()) in
  let center_of view path = let x, y, w, h = Option.get (Scope.Private.box_of view path) in x, y, w, h in
  let settled view = fst (scope_step view (frame ())) in
  let scope_view ?inputs ?probe ?at ?collapsed workspace graph =
    ignore (inputs, probe, at, collapsed);
    let scope = P.of_graph scope_catalog workspace graph in
    Scope.create ~width:3000 ~height:2000 () |> Scope.with_scope ~key:graph scope
    |> Scope.with_records (recorded workspace), scope in
  let double_click view point = scope_click (fst (scope_click view point)) point in
  let type_text view text =
    scope_step view (frame ~events:[ Event.TextInput text; Event.KeyPressed Input.Enter ] ()) in
  (* rename: a double-click on the title opens a field, Enter commits Rename; F2 does the same *)
  let w = load_workspace "bloom" in
  let heart = [ "flower"; "heart" ] in
  let view = settled (fst (scope_view w "flower")) in
  let x, y, _, _ = center_of view heart in
  let view, _ = double_click view (int_of_float x + 100, int_of_float y + 8) in
  check (Scope.editing view) "a double-click on a title did not open the name field";
  let view = settled view in
  let view, changes = type_text view "core" in
  check (List.mem (syntax (E.Rename { node = heart; to_ = "core" })) changes) "typing a name did not become Rename";
  check (not (Scope.editing view)) "the name field stayed open after Enter";
  let view, changes = Scope.run_command (Scope.select [ heart ] view) Scope.Edit_name in
  check (changes = [] && Scope.editing view) "F2 did not open the name field";
  let view = settled view in
  let view, changes = scope_step view (frame ~events:[ Event.TextInput "two words"; Event.KeyPressed Input.Enter ] ()) in
  check (changes = [] || not (List.exists (function Scope.Syntax_edit (E.Rename _) -> true | _ -> false) changes))
    "a name with a space was accepted";
  let view = fst (scope_step view (frame ~events:[ Event.KeyPressed Input.Escape ] ())) in
  check (not (Scope.editing view)) "Escape left the name field open";
  let _, changes = Scope.run_command (Scope.select [] view) Scope.Edit_name in
  check (match changes with [ Scope.Notice _ ] -> true | _ -> false) "F2 with nothing selected";
  (* a graph input's default: double-click its tile, type a form *)
  let petals = [ "flower"; ":petals" ] in
  let view = settled (Scope.clear_selection view) in
  let x, y, _, _ = center_of view petals in
  let view, _ = double_click view (int_of_float x + 60, int_of_float y + 30) in
  check (Scope.editing view) "a double-click on a graph input did not open its default";
  let view = settled view in
  let _, changes = type_text view "9" in
  check (List.exists (function
    | Scope.Syntax_edit (E.Set_input_default { form = "flower"; input = "petals"; value = { S.node = S.Num "9"; _ } }) -> true
    | _ -> false) changes) "typing an input default did not become Set_input_default";
  (* scrub: a drag on a number field is Set_arg *)
  let view = settled (fst (scope_view w "flower")) in
  let node = Option.get (P.find (P.of_graph scope_catalog w "flower") heart) in
  let i = Option.get (List.find_index (fun (r : P.row) -> r.label = "radius") node.rows) in
  let fx, fy = Option.get (Scope.Private.row_center view heart i) in
  let from = int_of_float fx, int_of_float fy in
  let view, _ = scope_step view (frame ~mouse:from ~events:[ mouse_move from; mouse_press (Input.LeftButton, from) ] ()) in
  let towards = fst from + 40, snd from in
  let view, moved = scope_step view (frame ~mouse:towards ~events:[ mouse_move towards ] ()) in
  let _, released = scope_step view (frame ~mouse:towards ~events:[ mouse_release (Input.LeftButton, towards) ] ()) in
  check (List.exists (function Scope.Syntax_edit (E.Set_arg { node; sub = [ _ ]; _ }) -> node = heart | _ -> false)
           (moved @ released)) "scrubbing a vector field did not become Set_arg";
  (* the selection commands and their requests *)
  let view = settled (Scope.select [ heart ] (fst (scope_view w "flower"))) in
  let only command = snd (Scope.run_command view command) in
  check (only Scope.Fold_into = [ syntax (E.Fold_into { node = heart }) ]) "f: Fold_into";
  check (only Scope.Hoist = [ syntax (E.Hoist { node = heart }) ]) "h: Hoist";
  check (only Scope.Wrap_repeat = [ syntax (E.Wrap { nodes = [ heart ]; loop = E.For }) ]) "r: Wrap For";
  check (only Scope.Wrap_iterate = [ syntax (E.Wrap { nodes = [ heart ]; loop = E.Fold }) ]) "Shift-r: Wrap Fold";
  check (only Scope.Make_fn = [ syntax (E.Make_local_fn { nodes = [ heart ] }) ]) "l: Make_local_fn";
  check (only Scope.Duplicate = [ syntax (E.Duplicate { nodes = [ heart ] }) ]) "Command-D: Duplicate";
  check (only Scope.Copy = [ Scope.Copy_requested [ heart ] ]) "Command-C: Copy_requested";
  check (only Scope.Cut = [ Scope.Copy_requested [ heart ]; syntax (E.Delete_nodes { nodes = [ heart ] }) ])
    "Command-X: copy, then delete";
  check (only Scope.Paste = [ Scope.Paste_requested ]) "Command-V: Paste_requested";
  (* a screen point as a grid-snapped position in a scope: further right on screen is further
     right in the scope *)
  (let x, y, _, _ = center_of view heart in
   match Scope.scope_point view ~scope:[ "flower" ] (x, y), Scope.scope_point view ~scope:[ "flower" ] (x +. 60., y) with
   | Some (ax, ay), Some (bx, _) ->
       check (Float.rem ax 12. = 0. && Float.rem ay 12. = 0. && bx > ax) "scope_point snaps to 12 and follows the pointer"
   | _ -> fail "scope_point found no scope");
  check (Scope.scope_point view ~scope:[ "nosuch" ] (0., 0.) = None) "an unknown scope has no point";
  (* fold and unfold: the keys, and the right-click menu's rows *)
  let result = [ "flower"; "result" ] in
  (match snd (Scope.run_command (Scope.select [ result ] view) Scope.Unfold) with
   | [ Scope.Syntax_edit (E.Unfold { node; sub = []; _ }) ] when node = result -> ()
   | _ -> failwith "Shift-U on a call with an inline call did not become Unfold");
  let hx, hy, _, _ = center_of view heart in
  let at = int_of_float hx + 20, int_of_float hy + 8 in
  let menu, _ = scope_step view (frame ~mouse:at ~events:[ mouse_move at; mouse_press (Input.RightButton, at);
    mouse_release (Input.RightButton, at) ] ()) in
  let menu, _ = scope_step menu (frame ~mouse:at ()) in
  let item i = fst at + 30, snd at + 3 + (24 * i) + 12 in
  let _, picked = scope_step menu (frame ~mouse:(item 0) ~events:[ mouse_move (item 0); mouse_press (Input.LeftButton, item 0);
    mouse_release (Input.LeftButton, item 0) ] ()) in
  check (List.mem (syntax (E.Fold_into { node = heart })) picked) "the right-click menu's first row did not become Fold_into";
  (* a right-click on empty canvas asks the host for its add menu at that point *)
  let empty = 2900, 1900 in
  let _, requested = scope_step view (frame ~mouse:empty ~events:[ mouse_move empty;
    mouse_press (Input.RightButton, empty); mouse_release (Input.RightButton, empty) ] ()) in
  check (List.mem (Scope.Menu_requested (2900., 1900.)) requested) "a right-click on empty canvas did not ask for the add menu";
  check (only Scope.Display = [ Scope.Display_set heart ]) "v: a geometry node is shown in the viewport";
  (match snd (Scope.run_command (Scope.select [ [ "flower"; "petals" ] ] view) Scope.Display) with
   | [ Scope.Notice _ ] -> () | _ -> failwith "v on a number did not say only geometry can be viewed");
  check (match snd (Scope.run_command (Scope.select [] view) Scope.Duplicate) with [ Scope.Notice _ ] -> true | _ -> false)
    "Command-D with nothing selected did not say so";
  (* the viewed node carries the VIEW mark; the key bindings are the Command table's *)
  let viewed = Scope.with_scope ~key:"flower" ~display:heart (P.of_graph scope_catalog w "flower") view in
  ignore viewed;
  List.iter (fun (id, modifiers) ->
    check (List.exists (fun (c : _ Editor_core.Command.t) -> c.id = id && c.trigger = Some (Editor_core.Keymap.Chord (
      Input.KeyChar (if id = "scope.display" then 'v' else 'd'), modifiers))) Scope.bindings) (id ^ " is not bound"))
    [ "scope.duplicate", [ Input.Meta ]; "scope.duplicate", [ Input.Ctrl ]; "scope.display", [] ];
  (* list rows: the + item row, the up arrow and Alt-Up move an item, a record's + field row *)
  let kw = load_workspace "kit" in
  let kit_scope = P.of_graph scope_catalog kw "kit" in
  let view, _ = scope_view kw "kit" in
  let view = settled view in
  let widths = [ "kit"; "widths" ] in
  let node = Option.get (P.find kit_scope widths) in
  let add = Option.get (List.find_index (fun (r : P.row) -> r.kind = P.Add) node.rows) in
  let ax, ay = Option.get (Scope.Private.row_center view widths add) in
  let _, changes = scope_click view (int_of_float ax, int_of_float ay) in
  check (List.mem (syntax (E.Add_item { node = widths })) changes) "the + item row did not become Add_item";
  let bx, by, bw, _ = center_of view widths in
  let second = Option.get (List.find_index (fun (r : P.row) -> r.key = E.Pos 1) node.rows) in
  let ux = bx +. bw -. 14. *. Scope.zoom view and uy = snd (Option.get (Scope.Private.row_center view widths second)) in
  ignore by;
  let _, changes = scope_click view (int_of_float ux, int_of_float uy) in
  check (List.mem (syntax (E.Move_item { node = widths; pos = 1 })) changes) "the row arrow did not become Move_item";
  let hover = int_of_float (fst (Option.get (Scope.Private.row_center view widths second))), int_of_float uy in
  let hovered, _ = scope_step view (frame ~mouse:hover ~events:[ mouse_move hover ] ()) in
  check (snd (Scope.run_command hovered Scope.Item_up) = [ syntax (E.Move_item { node = widths; pos = 1 }) ]) "Alt-Up: Move_item";
  check (snd (Scope.run_command hovered Scope.Item_down) = [ syntax (E.Move_item { node = widths; pos = 2 }) ]) "Alt-Down: Move_item";
  check (match snd (Scope.run_command view Scope.Item_up) with [ Scope.Notice _ ] -> true | _ -> false)
    "Alt-Up with no hovered item";
  let rec records (nodes : P.node list) = List.concat_map (fun (n : P.node) ->
    (if n.head = "record" && n.zone = None then [ n ] else [])
    @ (match n.zone with Some z -> records z.scope.nodes | None -> [])) nodes in
  (match records kit_scope.nodes with
   | record :: _ ->
       let add = Option.get (List.find_index (fun (r : P.row) -> r.kind = P.Add) record.rows) in
       (match Scope.Private.row_center view record.path add with
        | Some (rx, ry) ->
            let _, changes = scope_click view (int_of_float rx, int_of_float ry) in
            check (List.exists (function Scope.Syntax_edit (E.Add_field { node; _ }) -> node = record.path | _ -> false) changes)
              "the + field row did not become Add_field"
        | None -> ())
   | [] -> fail "kit has no record node");
  (* frames: Shift-G makes one around the selection, the corner resizes it, the cross deletes it *)
  let view = settled (Scope.select [ heart; [ "flower"; "bloom" ] ] (fst (scope_view w "flower"))) in
  let view, changes = Scope.run_command view Scope.Make_frame in
  let made = match changes with
    | [ Scope.Frames_set { scope = [ "flower" ]; frames = [ (title, at, size) ] } ] -> title, at, size
    | _ -> fail "Shift-G did not make one frame" in
  let title, at, (fw, fh) = made in
  let framed = Scope.with_scope ~frames:(fun p -> if p = [ "flower" ] then [ made ] else []) ~key:"flower"
      (P.of_graph scope_catalog w "flower") view in
  let framed = settled framed in
  let fx0, fy0 = at in
  let ox, oy = let x, y, _, _ = center_of framed [ "flower"; "heart" ] in ignore (x, y); 0., 0. in
  ignore (ox, oy);
  (* the frame's screen position: its scope's origin is the pane's, so use the pan through a tile *)
  let tile_x, tile_y, _, _ = center_of framed heart in
  let heart_rel = P.layout ~at:(fun _ -> None) (P.of_graph scope_catalog w "flower") in
  let hp = List.find (fun (p : P.placed) -> p.path = heart) heart_rel.placed in
  let z = Scope.zoom framed in
  let sx0 = tile_x -. hp.x *. z and sy0 = tile_y -. hp.y *. z in
  let corner = int_of_float (sx0 +. (fx0 +. fw) *. z -. 6.), int_of_float (sy0 +. (fy0 +. fh) *. z -. 6.) in
  let drag_to = fst corner + 30, snd corner + 20 in
  let sized, _ = scope_step framed (frame ~mouse:corner ~events:[ mouse_move corner; mouse_press (Input.LeftButton, corner) ] ()) in
  let sized, _ = scope_step sized (frame ~mouse:drag_to ~events:[ mouse_move drag_to ] ()) in
  let _, changes = scope_step sized (frame ~mouse:drag_to ~events:[ mouse_release (Input.LeftButton, drag_to) ] ()) in
  (match List.find_map (function Scope.Frames_set { frames = [ (_, _, (w', h')) ]; _ } -> Some (w', h') | _ -> None) changes with
   | Some (w', h') -> check (w' > fw && h' > fh) "dragging the corner did not grow the frame"
   | None -> fail "dragging the corner did not emit Frames_set");
  let cross = int_of_float (sx0 +. (fx0 +. fw) *. z -. 10.), int_of_float (sy0 +. fy0 *. z +. 10.) in
  let _, changes = scope_click framed cross in
  check (List.exists (function Scope.Frames_set { frames = []; _ } -> true | _ -> false) changes) "the cross did not delete the frame";
  let title_at = int_of_float (sx0 +. fx0 *. z +. 20.), int_of_float (sy0 +. fy0 *. z +. 8.) in
  let retitled, _ = double_click framed title_at in
  check (Scope.editing retitled) "a double-click on a frame title did not open its field";
  let retitled = settled retitled in
  let _, changes = type_text retitled "legs" in
  check (List.exists (function Scope.Frames_set { frames = [ (t, _, _) ]; _ } -> t = "legs" && t <> title | _ -> false) changes)
    "typing a frame title did not emit Frames_set";
  (* a drag on the title carries the frame with the nodes inside it, as one Moved and one Frames_set *)
  let towards = fst title_at + 40, snd title_at + 30 in
  let carried, _ = scope_step framed (frame ~mouse:title_at ~events:[ mouse_move title_at; mouse_press (Input.LeftButton, title_at) ] ()) in
  let carried, _ = scope_step carried (frame ~mouse:towards ~events:[ mouse_move towards ] ()) in
  let carried, _ = scope_step carried (frame ~mouse:towards ~events:[] ()) in
  let moved_box = Scope.Private.box_of carried heart and still_box = Scope.Private.box_of framed heart in
  check (match moved_box, still_box with Some (x, _, _, _), Some (x0, _, _, _) -> x > x0 +. 10. | _ -> false)
    "the nodes did not travel with the frame while it was dragged";
  let _, changes = scope_step carried (frame ~mouse:towards ~events:[ mouse_release (Input.LeftButton, towards) ] ()) in
  (match List.filter_map (function Scope.Moved placed -> Some placed | _ -> None) changes,
         List.filter_map (function Scope.Frames_set { frames = [ (_, (x, y), _) ]; _ } -> Some (x, y) | _ -> None) changes with
   | [ placed ], [ (x, y) ] ->
       check (List.exists (fun (p, _, _) -> p = heart) placed && List.exists (fun (p, _, _) -> p = [ "flower"; "bloom" ]) placed)
         "the frame did not move the nodes inside it";
       check (Float.abs (x -. (fx0 +. 40. /. z)) < 2. && Float.abs (y -. (fy0 +. 30. /. z)) < 2.) "the frame did not move with the pointer"
   | _ -> fail "dragging the frame title did not emit one Moved and one Frames_set");
  (* f frames the selection, with nothing selected all of it *)
  let far = Scope.with_bounds ~x:0 ~y:0 ~width:400 ~height:300 framed in
  let zoomed = Scope.select [ heart ] far |> fun v -> fst (Scope.run_command v Scope.Frame_selection) in
  (match Scope.Private.box_of zoomed heart with
   | Some (x, y, w, h) -> check (x >= 0. && y >= 0. && x +. w <= 400. && y +. h <= 300. && w *. h > 0.)
       "framing the selection left the node out of view"
   | None -> fail "the framed node has no box");
  check (Scope.zoom (fst (Scope.run_command (Scope.select [] far) Scope.Frame_selection)) = Scope.zoom (fst (Scope.run_command far Scope.Frame_all)))
    "framing an empty selection is framing all";
  (* marquee: a drag on empty canvas selects the nodes of one scope it covers; Shift adds *)
  let view = settled (fst (scope_view w "flower")) in
  let sc = P.of_graph scope_catalog w "flower" in
  let boxes = List.map (fun (n : P.node) -> Option.get (Scope.Private.box_of view n.path)) sc.nodes in
  let x0 = List.fold_left (fun a (x, _, _, _) -> Float.min a x) infinity boxes -. 8.
  and y0 = List.fold_left (fun a (_, y, _, _) -> Float.min a y) infinity boxes -. 8.
  and x1 = List.fold_left (fun a (x, _, w, _) -> Float.max a (x +. w)) neg_infinity boxes +. 8.
  and y1 = List.fold_left (fun a (_, y, _, h) -> Float.max a (y +. h)) neg_infinity boxes +. 8. in
  let a = int_of_float x0, int_of_float y0 and b = int_of_float x1, int_of_float y1 in
  let drag view ?(shift = false) a b =
    let view, _ = scope_step view (frame ~mouse:a ~events:((if shift then [ Event.KeyPressed Input.Shift ] else [])
      @ [ mouse_move a; mouse_press (Input.LeftButton, a) ]) ()) in
    let view, moved = scope_step view (frame ~mouse:b ~events:[ mouse_move b ] ()) in
    let view, released = scope_step view (frame ~mouse:b ~events:[ mouse_release (Input.LeftButton, b) ] ()) in
    view, moved @ released in
  let view, changes = drag view a b in
  let covered = List.filter (fun p -> List.mem p (Scope.selected view)) (List.map (fun (n : P.node) -> n.path) sc.nodes) in
  check (List.length covered >= 4 && List.mem heart covered) "a marquee over the graph did not select its nodes";
  check (List.exists (function Scope.Selected l -> List.mem heart l | _ -> false) changes) "a marquee did not emit Selected";
  let view = settled (Scope.select [ heart ] (fst (scope_view w "flower"))) in
  let rx, ry, rw, rh = Option.get (Scope.Private.box_of view [ "flower"; "result" ]) in
  let view, _ = drag view ~shift:true (int_of_float (rx -. 4.), int_of_float (ry -. 4.)) (int_of_float (rx +. rw +. 4.), int_of_float (ry +. rh +. 4.)) in
  check (List.mem heart (Scope.selected view) && List.mem [ "flower"; "result" ] (Scope.selected view))
    "Shift marquee did not add to the selection";
  let view, _ = drag (settled (Scope.select [ heart ] (fst (scope_view w "flower")))) (int_of_float (rx -. 4.), int_of_float (ry -. 4.)) (int_of_float (rx +. rw +. 4.), int_of_float (ry +. rh +. 4.)) in
  check (not (List.mem heart (Scope.selected view))) "a plain marquee kept the old selection"

let run_scope () =
  (* every fixture's graphs draw: the pane's counts are the projection's *)
  List.iter (fun (name, graph, nodes, zones, rows) ->
    let w = load_workspace name in
    let view, _ = scope_view w graph in
    let view, _ = scope_step view (frame ()) in
    let s = Scope.stats view in
    check (s.nodes = nodes && s.zones = zones && s.rows = rows)
      (Printf.sprintf "%s/%s: pane counts %d/%d/%d" name graph s.nodes s.zones s.rows);
    check (s.drawn_items > 0 && s.drawn_zones <= s.zones) (name ^ ": nothing drawn"))
    [ "bloom", "flower", 9, 1, 35; "sunflower", "sunflower", 8, 1, 24; "orrery", "orrery", 15, 1, 62;
      "facade", "facade", 12, 2, 59; "kit", "kit", 15, 2, 49; "tree", "tree", 8, 1, 67;
      "garland", "garland", 14, 3, 59; "wave", "wave", 6, 2, 39; "tiles", "tiles", 8, 1, 34 ];
  (* the iteration selector: buttons and track are hit-tested boxes *)
  let w = load_workspace "sunflower" in
  let zone = [ "sunflower"; "seeds_each" ] in
  let view, _ = scope_view ~probe:(fun _ -> 5) w "sunflower" in
  let view, _ = scope_step view (frame ()) in
  let prev, track, next = Option.get (Scope.Private.selector view zone) in
  let _, changes = scope_click view (rect_center next) in
  check (List.mem (Scope.Probe_set { zone; index = 6 }) changes) "the next button did not step the probe";
  let _, changes = scope_click view (rect_center prev) in
  check (List.mem (Scope.Probe_set { zone; index = 4 }) changes) "the previous button did not step the probe";
  let x, y, tw, th = track in
  let _, changes = scope_click view (int_of_float (x +. tw *. 0.75), int_of_float (y +. th /. 2.)) in
  check (List.exists (function Scope.Probe_set { zone = z; index } -> z = zone && index >= 178 && index <= 181
                              | _ -> false) changes) "the track did not map the pointer to an iteration";
  let _, changes = scope_click view (10, 690) in
  check (changes = [] || List.for_all (function Scope.Selected _ -> true | _ -> false) changes)
    "a blank click made an edit";
  (* the toggle collapses the zone; a collapsed zone has no selector *)
  let tx, ty, _, _ = Option.get (Scope.Private.box_of view zone) in
  let _, changes = scope_click view (int_of_float tx + 10, int_of_float ty + 10) in
  check (List.mem (Scope.Zone_collapsed { zone; collapsed = true }) changes) "the toggle did not collapse the zone";
  (* only visible zones draw: 1,000 iterations draw what 3 do *)
  let draw_with n =
    let view, _ = scope_view ~inputs:[ "sunflower", [ "seeds", Flow.Eval.Int n ] ] w "sunflower" in
    let view, _ = scope_step view (frame ()) in
    (Scope.stats view).drawn_items, scope_paint view in
  let items3, paint3 = draw_with 3 and items1000, paint1000 = draw_with 1000 in
  check (items3 = items1000) "iterations changed how many tiles are built";
  (* what grows is the sparklines: at most 16 segments each, whatever the count *)
  check (paint1000 < paint3 + 30 * items3) "a 1,000-iteration zone painted much more than a 3-iteration one";
  let collapsed_view, _ = scope_view ~collapsed:(fun p -> p = zone) w "sunflower" in
  let collapsed_view, _ = scope_step collapsed_view (frame ()) in
  check ((Scope.stats collapsed_view).drawn_zones = 0) "a collapsed zone drew its body";
  (* gestures become requests: scrub, wire, delete *)
  let ws = load_workspace "bloom" in
  let view, scope = scope_view ws "flower" in
  let view, _ = scope_step view (frame ()) in
  let heart = [ "flower"; "heart" ] in
  let node = Option.get (P.find scope heart) in
  let i = Option.get (List.find_index (fun (r : P.row) -> r.label = "radius") node.rows) in
  let fx, fy = Option.get (Scope.Private.row_center view heart i) in
  ignore (fx, fy);
  (* wire: a node's output socket dropped on another node's geometry row *)
  let source = [ "flower"; "bloom" ] and target = [ "flower"; "result" ] in
  let sx, sy = Option.get (Scope.Private.output_socket view source) in
  let start = int_of_float sx, int_of_float sy in
  let tnode = Option.get (P.find scope target) in
  let row = Option.get (List.find_index (fun (r : P.row) -> r.socket && r.kind = P.Rest) tnode.rows) in
  let rx, ry = Option.get (Scope.Private.row_center view target row) in
  let stop = int_of_float rx, int_of_float ry in
  let view, _ = scope_step view (frame ~mouse:start ~events:[mouse_move start; mouse_press (Input.LeftButton, start)] ()) in
  let view, _ = scope_step view (frame ~mouse:stop ~events:[mouse_move stop] ()) in
  let _, changes = scope_step view (frame ~mouse:stop ~events:[mouse_release (Input.LeftButton, stop)] ()) in
  check (List.exists (function
      | Scope.Syntax_edit (Flow_sop.Flow_edit.Connect { node; src = "bloom"; iter = false; _ }) -> node = target
      | _ -> false) changes) "a wire dropped on a row did not become Connect";
  (* delete: the selected node *)
  let view, _ = scope_click view start in
  let view = Scope.select [ heart ] view in
  let _, changes = Scope.run_command view Scope.Delete in
  check (changes = [ Scope.Syntax_edit (Flow_sop.Flow_edit.Delete_nodes { nodes = [ heart ] }) ])
    "Delete did not become Delete_nodes";
  (* wire selection and deletion *)
  check (Scope.Private.wire_count view > 0) "there are wires in the graph";
  let wire_idx = Option.get (List.find_index (fun i -> Scope.Private.wire_target view i <> None)
    (List.init (Scope.Private.wire_count view) (fun i -> i))) in
  let wpt = Option.get (Scope.Private.wire_midpoint view wire_idx) in
  let view = Scope.select [ heart ] view in
  check (Scope.selected view = [ heart ]) "heart is selected";
  let view, _ = scope_click view (int_of_float (fst wpt), int_of_float (snd wpt)) in
  check (Scope.selected_wire view <> None) "clicking wire selected it";
  check (Scope.selected view = []) "clicking wire cleared node selection";
  let _, changes = Scope.run_command view Scope.Delete in
  check (match changes with [ Scope.Syntax_edit (Flow_sop.Flow_edit.Disconnect _) ] -> true | _ -> false)
    "Delete on selected wire emitted Disconnect";
  let straight_view = Scope.with_wires `Straight view in
  check (Scope.wires straight_view = `Straight) "wires style is straight";
  (* keys and menu: every key command maps to a request *)
  let some name = check (List.exists (fun (c : (_, Scope.command) Editor_core.Command.t) -> c.id = "scope." ^ name)
    Scope.bindings) ("no key for " ^ name) in
  List.iter some [ "delete"; "fold"; "unfold"; "hoist"; "bypass"; "repeat"; "iterate"; "function"; "collapse";
                   "probe-prev"; "probe-next"; "frame-all"; "walk.left" ];
  let _, changes = Scope.run_command (Scope.select [ heart ] view) Scope.Bypass in
  check (changes = [ Scope.Syntax_edit (Flow_sop.Flow_edit.Toggle_bypass { node = heart }) ]) "Bypass";
  (* W9: the macro lens, the bypass flag, the make-macro key *)
  let w = load_workspace "rosette" in
  let view, scope = scope_view w "rosette" in
  let view, _ = scope_step view (frame ()) in
  let outer = [ "rosette"; "outer" ] and soft = [ "rosette"; "soft" ] in
  let node = Option.get (P.find scope outer) in
  let lens = Option.get node.lens in
  check (Array.length lens.steps >= 2 && lens.error = None
         && String.starts_with ~prefix:"(radial" lens.steps.(0)
         && String.starts_with ~prefix:"(sop/merge" lens.steps.(1)) "the lens steps are the call, then its expansions";
  check (Scope.macro_step view outer = None) "the lens starts closed";
  let toggle = Scope.Private.lens_toggle view outer |> Option.get in
  let view, _ = scope_click view (int_of_float (fst toggle), int_of_float (snd toggle)) in
  check (Scope.macro_step view outer = Some (Array.length lens.steps - 1)) "the toggle opens the last step";
  let view, _ = scope_step view (frame ()) in
  let button i = let x, y = Option.get (Scope.Private.lens_step_button view outer i) in int_of_float x, int_of_float y in
  let view, changes = scope_click view (button 0) in
  check (Scope.macro_step view outer = Some 0 && changes = []) "the call button shows the call, no edit";
  let view, _ = scope_step view (frame ()) in
  let view, _ = scope_click view (button 1) in
  check (Scope.macro_step view outer = Some 1) "a step button chooses the step";
  let view, _ = scope_step view (frame ()) in
  (* the Template button shows the macro's definition, one step past the expansions *)
  check (List.exists (String.starts_with ~prefix:"(defmacro radial") (String.split_on_char '\n' lens.template))
    "the lens carries the macro's template";
  let view, changes = scope_click view (button (Array.length lens.steps)) in
  check (Scope.macro_step view outer = Some (Array.length lens.steps) && changes = []) "the Template button shows the definition, no edit";
  let view, _ = scope_step view (frame ()) in
  let view, _ = scope_click view (button 1) in
  let view, _ = scope_step view (frame ()) in
  let bx, by, bw, bh = Option.get (Scope.Private.box_of view outer) in
  check (bh > (let _, _, _, h0 = Option.get (Scope.Private.box_of (fst (scope_view w "rosette")) outer) in h0)
         && bw >= Flow_sop.Projection.lens_width *. Scope.zoom view -. 1.) "an open panel grows its card";
  ignore (bx, by);
  let rx, ry = Option.get (Scope.Private.lens_replace view outer) in
  let _, changes = scope_click view (int_of_float rx, int_of_float ry) in
  check (List.mem (Scope.Syntax_edit (Flow_sop.Flow_edit.Inline_macro { node = outer })) changes)
    "the replace button did not become Inline_macro";
  let tx, ty = Option.get (Scope.Private.lens_toggle view outer) in
  let view, _ = scope_click view (int_of_float tx, int_of_float ty) in
  check (Scope.macro_step view outer = None) "the toggle closes the panel";
  (* the bypass flag: a title flag on a call whose input fits, the same request as the key *)
  check (Scope.Private.bypass_flag view outer = None) "a macro call has no bypass flag";
  let fx, fy = Option.get (Scope.Private.bypass_flag view soft) in
  let _, changes = scope_click view (int_of_float fx, int_of_float fy) in
  check (List.mem (Scope.Syntax_edit (Flow_sop.Flow_edit.Toggle_bypass { node = soft })) changes)
    "the bypass flag did not become Toggle_bypass";
  check ((Option.get (P.find scope soft)).bypass) "soft is authored bypassed";
  (* m asks the host for the make-macro dialog over the selection *)
  let _, changes = Scope.run_command (Scope.select [ soft ] view) Scope.Make_macro in
  check (changes = [ Scope.Macro_requested [ soft ] ]) "m did not request the dialog";
  let _, changes = Scope.run_command (Scope.select [] view) Scope.Make_macro in
  check (match changes with [ Scope.Notice _ ] -> true | _ -> false) "m with nothing selected";
  scope_gestures ();
  scope_carry ();
  scope_connection_hover ();
  scope_pinch ();
  print_endline "pxui graph scope pane tests passed"

(* Frame cost of the graph pane on Sunflower (240 iterations), expanded and
   collapsed.  Command: dune exec test/test_main.exe -- bench_scope_pane *)
let bench_scope_pane () =
  let w = load_workspace "sunflower" in
  let ui = Pxui.Ui.create () in
  let frames = 300 in
  let time label build step =
    let view = ref build in
    for _ = 1 to 20 do view := fst (Pxui.Ui.frame ui (frame ()) (fun ui -> step !view ui (frame ()))) done;
    let started = Unix.gettimeofday () and allocated = Gc.allocated_bytes () in
    for _ = 1 to frames do view := fst (Pxui.Ui.frame ui (frame ()) (fun ui -> step !view ui (frame ()))) done;
    Printf.printf "%-28s %.3f ms/frame, %.0f bytes/frame\n%!" label
      ((Unix.gettimeofday () -. started) *. 1000. /. float frames)
      ((Gc.allocated_bytes () -. allocated) /. float frames) in
  let zone = [ "sunflower"; "seeds_each" ] in
  let scoped ?(records = true) collapsed =
    let view = Scope.create ~width:1000 ~height:700 ()
      |> Scope.with_scope ~collapsed:(fun p -> collapsed && p = zone) ~key:"sunflower"
           (P.of_graph scope_catalog w "sunflower") in
    if records then Scope.with_records (recorded w) view else view in
  time "scope pane, no records" (scoped ~records:false false) (fun view ui f -> Scope.update view ui f);
  time "scope pane, zone expanded" (scoped false) (fun view ui f -> Scope.update view ui f);
  time "scope pane, zone collapsed" (scoped true) (fun view ui f -> Scope.update view ui f);
  (* the costs around the frame: one recording evaluation (a document change),
     and Orrery's live records rebuilt every frame (Probe.make and the footers) *)
  let timed label n f =
    let started = Unix.gettimeofday () in
    for _ = 1 to n do ignore (Sys.opaque_identity (f ())) done;
    Printf.printf "%-28s %.3f ms\n%!" label ((Unix.gettimeofday () -. started) *. 1000. /. float n) in
  timed "record eval, Sunflower" 20 (fun () -> Flow.Eval.static ~record:true w);
  let orrery = load_workspace "orrery" in
  timed "record eval, Orrery" 20 (fun () -> Flow.Eval.static ~record:true orrery);
  let evaluated = Result.get_ok (Flow.Eval.static ~record:true orrery) in
  let scope = P.of_graph scope_catalog orrery "orrery" in
  let live_view records =
    Scope.create ~width:1000 ~height:700 ()
    |> Scope.with_scope ~key:"orrery" scope
    |> fun view -> match records with
      | None -> view | Some t -> Scope.with_records (Flow_sop.Probe.make ~time:t evaluated) view in
  time "orrery pane, no records" (live_view None) (fun view ui f -> Scope.update view ui f);
  let t = ref 0. in
  time "orrery pane, live records" (live_view (Some 0.)) (fun view ui f ->
    t := !t +. 0.016;
    Scope.update (Scope.with_records (Flow_sop.Probe.make ~time:!t evaluated) view) ui f)
