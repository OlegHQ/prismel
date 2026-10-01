(* W10 part B: the editor graph lowers to the shell tree; viewports over other
   instances of the scene get objects of their own; layout gestures are edits of
   the editor graph with history entries; "Restore layout" survives a layout that
   hides everything. *)
open Prismel
open Procedural
module Doc = Editor_document.Workspace_doc
module Document = Editor_document.Document
module Contexts = Editor_document.Contexts
module Panels = Editor_core.Panels
module Layout = Pxui_shell.Layout
module E = Flow_sop.Flow_edit
module S = Flow.Syntax
module E3 = Prismel_editor.Editor3

let fail message = failwith ("test_workspace_shell: " ^ message)
let check condition message = if not condition then fail message
let factories = Sop_catalog.Editor.factories
let catalog = Contexts.catalog ~version:1 factories |> Result.get_ok
let show ds = String.concat "; " (List.map Flow.Diagnostic.to_string ds)
let case name = In_channel.with_open_bin
    (Filename.concat "../specification/workspace/cases" (name ^ ".lisp")) In_channel.input_all
let of_text text = match Doc.of_text catalog text with Ok d -> d | Error ds -> fail (show ds)
let build ?previous ws = Contexts.of_workspace ~factories ?previous ws
let build_ok ws = match build ws with Ok d -> d | Error d -> fail (Flow.Diagnostic.to_string d)
let has text sub =
  let n = String.length sub in
  let rec at i = i + n <= String.length text && (String.sub text i n = sub || at (i + 1)) in
  at 0
let replace text from by =
  let n = String.length from in
  let rec at i = if i + n > String.length text then fail ("no " ^ from)
    else if String.sub text i n = from then i else at (i + 1) in
  let i = at 0 in
  String.sub text 0 i ^ by ^ String.sub text (i + n) (String.length text - i - n)
let shell_of doc = match doc.Document.shell with Some s -> s | None -> fail "no editor graph"
let leaves tree = Panels.leaves tree

(* the variations workspace with its editor graph replaced *)
let with_editor body =
  let text = case "variations" in
  let start = let rec find i = if String.sub text i 22 = "(graph editor :context" then i else find (i + 1) in find 0 in
  String.sub text 0 start ^ "(graph editor :context editor\n" ^ body ^ "))\n"

let expect_error name text needle =
  match Doc.of_text catalog text with
  | Error ds -> check (has (show ds) needle) (name ^ ": " ^ show ds)
  | Ok ws -> (match build ws with
      | Error d -> check (has (Flow.Diagnostic.to_string d) needle) (name ^ ": " ^ Flow.Diagnostic.to_string d)
      | Ok _ -> fail (name ^ " was accepted"))

(* ---- lowering ---- *)

let run_lowering () =
  let doc = build_ok (of_text (case "variations")) in
  let shell = shell_of doc in
  check (Panels.to_string shell.tree = "(h outline (h (v graph lisp) (tile view view view view)))")
    ("the variations shell: " ^ Panels.to_string shell.tree);
  (match shell.tree with
   | Split { ratio; b = Split { ratio = inner; a = Split { ratio = left; _ }; _ }; _ } ->
       check (ratio = 0.13 && inner = 0.5 && left = 0.58) "ratios come from the editor graph"
   | _ -> fail "root split");
  (* four viewports: the default scene instance, and one scene instance for each override *)
  let keys = List.filter_map (fun (_, p) -> match p with Panels.View k -> Some k | _ -> None) (leaves shell.tree) in
  check (keys = [ "v1.1.0"; "v1.1.1"; "v1.1.2"; "v1.1.3" ]) ("viewport keys are tile indices: " ^ String.concat "," keys);
  check (List.map fst shell.views = [ "v1.1.1"; "v1.1.2"; "v1.1.3" ]
         && List.for_all (fun (_, ids) -> List.length ids = 1) shell.views)
    "the default instance is the primary scene; each override has an object of its own";
  let ids = List.concat_map snd shell.views in
  check (List.length (List.sort_uniq compare ids) = 3) "the objects of the overrides are distinct";
  (* origins: named panels can be edited, looped ones say where they come from (E1) *)
  let origin path = List.assoc_opt path shell.origins in
  check (origin [ 0 ] = Some (Document.Bound "outline") && origin [ 1; 0; 0 ] = Some (Document.Bound "network")
         && origin [ 1; 0 ] = Some (Document.Bound "left") && origin [] = Some (Document.Bound "panels"))
    "named panels keep their binding";
  check (origin [ 1; 1; 2 ] = Some (Document.Loop (Document.Bound_at [ "editor"; "sheet" ], Flow_sop.Flow_edit.Pos 0)) && origin [ 1; 1 ] = Some (Document.Bound "sheet"))
    "a panel made by a loop names the loop";
  (* a count change keeps the first panels' keys *)
  let more = build_ok (of_text (replace (case "variations") "(range 4)" "(range 6)")) in
  let keys6 = List.filter_map (fun (_, p) -> match p with Panels.View k -> Some k | _ -> None)
      (leaves (shell_of more).tree) in
  check (List.filteri (fun i _ -> i < 4) keys6 = keys && List.length keys6 = 6) "panel keys follow the iteration index";
  check (List.length (Editor_document.Document.scene_graph more |> Procedural.Edit_graph.inspect) > 4) "more objects for more viewports";
  (* the default shell of a workspace without an editor graph, and a named graph panel *)
  let plain = build_ok (of_text (case "tree")) in
  check (plain.shell = None) "no editor graph, no shell";
  let named = build_ok (of_text (with_editor "    (ui/workspace (ui/split \"vertical\" (ui/graph \"scene\") (ui/viewport (ref scene))))")) in
  check ((shell_of named).named = Some "scene") "ui/graph names its graph";
  check (Panels.to_string (shell_of named).tree = "(v graph view)") "ui/split is an even split";
  (match (shell_of named).tree with Split { ratio; _ } -> check (ratio = 0.5) "ui/split halves" | _ -> fail "split");
  let floated = build_ok (of_text (with_editor "    (ui/workspace (ui/split-at \"horizontal\" 0.5 (ui/graph) (ui/floating (ui/viewport (ref scene)))))")) in
  check (Panels.to_string (shell_of floated).tree = "(h graph (float view))") "a floating panel";
  let timeline = build_ok (of_text (with_editor "    (ui/workspace (ui/split-at \"vertical\" 0.7 (ui/graph) (ui/timeline)))")) in
  check (Panels.to_string (shell_of timeline).tree = "(v graph timeline)") "a timeline panel";
  (* negative: what the checker or the evaluator refuses leaves no layout *)
  expect_error "a split axis" (with_editor "    (ui/workspace (ui/split \"diagonal\" (ui/graph) (ui/lisp)))") "axis";
  expect_error "a computed ratio out of range"
    (with_editor "    (let* [r (* 3 0.5)] (ui/workspace (ui/split-at \"horizontal\" r (ui/graph) (ui/lisp))))") "0.1";
  expect_error "an empty tile" (with_editor "    (ui/workspace (ui/tile (for [i (range 0)] (ui/graph))))") "tile";
  expect_error "a workspace of a number" (with_editor "    (ui/workspace 3)") "";
  expect_error "a panel that is not one" (with_editor "    (ui/workspace (ui/split \"vertical\" (ui/graph) 3))") ""
  ; expect_error "an unknown named layout"
      (with_editor "    (ui/workspace (ui/graph))" ^ "\n(layout (editor \"missing\"))") "Unknown editor layout"

(* ---- through the editor ---- *)

let frame ?(buttons = []) mouse events count = Test_editor_input.frame ~buttons mouse events count
(* every editor here awaits the cook its frame submits: what a frame shows is settled, never racing
   the worker *)
let editor ?camera ?presets text =
  E3.create ?camera ?presets ~await:true ~workspace:(of_text text)
    ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
      |> Result.map_error Pdk.Error.to_string)
    ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) ()
  |> function Ok e -> e | Error m -> fail m

let source e = fst (Flow.Lisp.print (E3.workspace e).Doc.source)

let dump_line e key =
  let directory = Filename.temp_dir "prismel-shell-dump" "" in
  Fun.protect ~finally:(fun () ->
    Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
    Unix.rmdir directory) (fun () ->
    E3.crash_dump e directory;
    let text = In_channel.with_open_bin (Filename.concat directory "editor.txt") In_channel.input_all in
    let lines = String.split_on_char '\n' text in
    match List.find_opt (fun l -> String.starts_with ~prefix:(key ^ ": ") l) lines with
    | Some l -> String.sub l (String.length key + 2) (String.length l - String.length key - 2)
    | None -> fail ("no " ^ key ^ " in the dump"))

let run_editor () =
  let e = ref (editor (case "variations")) and count = ref 0 in
  let step ?(buttons = []) ?(mouse = (450., 300.)) events =
    incr count; e := E3.update !e (frame ~buttons mouse events !count) in
  step []; step [];
  (* the editor awaits each cook, so after a frame nothing is cooking: a check, not a wait *)
  let settle () =
    let line = dump_line !e "cook" in
    check (not (String.starts_with ~prefix:"Cooking" line || String.starts_with ~prefix:"Waiting" line
                || has line "skipping frames")) ("the editor is still cooking: " ^ line) in
  settle ();
  let click ?(button = Input.LeftButton) (x, y) =
    step ~mouse:(x, y) [ Event.MouseMoved (x, y) ];
    step ~buttons:[ button ] ~mouse:(x, y) [ Event.MousePressed (button, (x, y)) ];
    step ~mouse:(x, y) [ Event.MouseReleased (button, (x, y)) ] in
  let drag ~from ~to_ =
    step ~mouse:from [ Event.MouseMoved from ];
    step ~buttons:[ Input.LeftButton ] ~mouse:from [ Event.MousePressed (Input.LeftButton, from) ];
    step ~buttons:[ Input.LeftButton ] ~mouse:to_ [ Event.MouseMoved to_ ];
    step ~mouse:to_ [ Event.MouseReleased (Input.LeftButton, to_) ];
    step [] in
  (* drag the outline | rest gutter: one rewrite of the editor graph, one history entry.
     At 900 points the outline's 120-point minimum lifts its 13% to 169. *)
  drag ~from:(169.5, 300.) ~to_:(300., 300.);
  check (has (source !e) "(ui/split-at \"horizontal\" 0.33 outline right)") ("the drag rewrote the outline split: " ^ source !e);
  check (E3.undo_label !e = Some "Resize panel") "one history entry named Resize panel";
  (* the header menu of the graph panel: split side by side *)
  let hx = 400. in
  click ~button:Input.RightButton (hx, 10. +. 28.);  (* under the 28-point host bar *)
  step [];
  click (340., 37. +. 28.);
  step [];
  check (E3.undo_label !e = Some "Split panel") ("the menu split the graph panel: " ^ Option.value ~default:"-" (E3.undo_label !e));
  check (has (source !e) "network_a" && has (source !e) "network_b") "the split bound two new panels";
  (* a panel made by a loop cannot be split: the status says where it comes from *)
  let geometry = Layout.geometry ~hidden:[ Layout.Timeline ] ~top:28 (shell_of (build_ok (E3.workspace !e)))
      .tree (frame (0., 0.) [] 0) in
  let leaf = Option.get (Layout.find geometry (Layout.View "v1.1.2")) in
  let hx, hy, hw, _ = leaf.header in
  let depth = E3.undo_label !e in
  click ~button:Input.RightButton (float (hx + (hw / 2)), float (hy + 10));
  step [];
  click (float (hx + 30), float (hy + 22 + 12));
  step [];
  check (E3.undo_label !e = depth) "a looped panel did not change the graph";
  settle ();
  check (has (dump_line !e "cook") "made by a loop in sheet") ("the status names the loop: " ^ dump_line !e "cook" ^ " / " ^ dump_line !e "edit error");
  (* focus is a panel: a press in a panel focuses it *)
  let focus_after (x, y) =
    click (x, y); step []; dump_line !e "focus" in
  check (focus_after (30., 300.) = "Outline") "a press in the outline focuses it";
  check (focus_after (float (hx + 30), float (hy + 100)) = "View") "a press in a viewport focuses a viewport";
  ()

(* Space o ...: the focused panel is split, closed or retyped by keys, the header menu's edits *)
let run_panel_keys () =
  let started () =
    let e = ref (editor (case "variations")) and count = ref 0 in
    let step ?(mouse = (300., 150.)) events = incr count; e := E3.update !e (frame mouse events !count) in
    step []; step [];
    (* a press in the graph panel focuses it *)
    step [ Event.MouseMoved (300., 150.) ];
    step [ Event.MousePressed (Input.LeftButton, (300., 150.)) ];
    step [ Event.MouseReleased (Input.LeftButton, (300., 150.)) ];
    step [];
    check (dump_line !e "focus" = "Graph") ("focus is the graph panel: " ^ dump_line !e "focus");
    e, step in
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  let e, step = started () in
  step [ key Input.Space; ch 'o'; ch 'h' ]; step [];
  check (E3.undo_label !e = Some "Split panel" && has (source !e) "network_a") "Space o h split the focused panel";
  step [ key Input.Space; ch 'o'; ch 'x' ]; step [];
  check (E3.undo_label !e = Some "Close panel") "Space o x closed it again";
  let e, step = started () in
  step [ key Input.Space; ch 'o'; ch 'v' ]; step [];
  check (E3.undo_label !e = Some "Split panel" && has (source !e) "\"vertical\" 0.5 network_a network_b")
    "Space o v split it stacked";
  let e, step = started () in
  step [ key Input.Space; ch 'l'; ch 'i' ]; step [];
  check (E3.undo_label !e = Some "Retype panel" && has (source !e) "(ui/inspector") "Space l i retyped it to an inspector";
  (* on the graph panel, Space l l / t / g only switch its own view: no edit *)
  let e, step = started () in
  step [ key Input.Space; ch 'l'; ch 'l' ]; step [];
  check (E3.undo_label !e = None && dump_line !e "projection" = "list")
    ("Space l l on the graph panel shows the list: " ^ dump_line !e "projection");
  (* a document without an editor graph gets one written from its layout before the retype *)
  let e = ref (editor "(workspace w (graph g :context sop (sop/box)))") and count = ref 0 in
  let step ?(mouse = (600., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
  step []; step [];
  let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
  let p = float (gx + 40), float (gy + 40) in
  step ~mouse:p [ Event.MouseMoved p ];
  step ~mouse:p [ Event.MousePressed (Input.LeftButton, p) ];
  step ~mouse:p [ Event.MouseReleased (Input.LeftButton, p) ];
  step ~mouse:p [];
  check (not (has (source !e) "(graph editor")) "the plain workspace has no editor graph";
  step ~mouse:p [ key Input.Space; ch 'l'; ch 'i' ]; step ~mouse:p [];
  check (has (source !e) "(graph editor :context editor" && has (source !e) "network (ui/inspector)"
         && has (source !e) "preview (ui/viewport (ref scene))" && has (source !e) "(graph scene :context scene"
         && E3.undo_label !e = Some "Retype panel")
    ("retyping wrote the editor graph (and the scene it views) first: " ^ source !e);
  E3.close !e;
  (* two panels of one kind: the keys act on the one clicked, not the first *)
  let twice = with_editor "    (let* [a (ui/graph) b (ui/graph) both (ui/split-at \"horizontal\" 0.5 a b)] (ui/workspace both))" in
  let e = ref (editor twice) and count = ref 0 in
  let step ?(mouse = (700., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
  step []; step [];
  let right = (700., 300.) in
  step ~mouse:right [ Event.MouseMoved right ];
  step ~mouse:right [ Event.MousePressed (Input.LeftButton, right) ];
  step ~mouse:right [ Event.MouseReleased (Input.LeftButton, right) ];
  step ~mouse:right [];
  step ~mouse:right [ key Input.Space; ch 'o'; ch 'x' ]; step ~mouse:right [];
  check (E3.undo_label !e = Some "Close panel" && has (source !e) "a (ui/graph)" && not (has (source !e) "b (ui/graph)"))
    ("closing the second graph panel closed it, not the first: " ^ source !e);
  E3.close !e

(* panels written in place, and panels made by a loop, are edited through the keys too: an
   inline panel is bound to a name first (one history entry), a loop's panels are retyped
   through their template *)
let run_unbound_panels () =
  let started text focus_at =
    let e = ref (editor text) and count = ref 0 in
    let step ?(mouse = focus_at) events = incr count; e := E3.update !e (frame mouse events !count) in
    step []; step [];
    step [ Event.MouseMoved focus_at ];
    step [ Event.MousePressed (Input.LeftButton, focus_at) ];
    step [ Event.MouseReleased (Input.LeftButton, focus_at) ];
    step [];
    e, step in
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  let inline = with_editor "    (ui/workspace (ui/split-at \"vertical\" 0.5 (ui/graph) (ui/viewport (ref scene))))" in
  let e, step = started inline (300., 100.) in
  check (dump_line !e "focus" = "Graph") ("focus is the inline graph panel: " ^ dump_line !e "focus");
  step [ key Input.Space; ch 'l'; ch 'i' ]; step [];
  check (E3.undo_label !e = Some "Retype panel" && has (source !e) "(ui/inspector)" && has (source !e) "(ui/viewport (ref scene))")
    ("an inline panel was retyped: " ^ Option.value ~default:"-" (E3.undo_label !e) ^ "\n" ^ source !e);
  E3.close !e;
  let e, step = started inline (300., 100.) in
  step [ key Input.Space; ch 'o'; ch 'h' ]; step [];
  check (E3.undo_label !e = Some "Split panel" && has (source !e) "graph_a" || has (source !e) "ui/split-at \"horizontal\" 0.5")
    ("an inline panel was split: " ^ Option.value ~default:"-" (E3.undo_label !e) ^ "\n" ^ source !e);
  E3.close !e;
  (* a loop's panels: retyping edits the template, splitting them says why it cannot *)
  let e, step = started (case "variations") (800., 100.) in
  check (dump_line !e "focus" = "View") "focus is a looped viewport";
  step [ key Input.Space; ch 'o'; ch 'x' ]; step [];
  check (E3.undo_label !e = None && has (dump_line !e "cook") "copies made by a loop")
    ("closing a looped panel said why not: " ^ Option.value ~default:"-" (E3.undo_label !e) ^ " / " ^ dump_line !e "cook");
  step [ key Input.Space; ch 'l'; ch 'l' ]; step [];
  check (E3.undo_label !e = Some "Retype panel" && has (source !e) "(ui/list)")
    ("retyping a looped panel edits its template: " ^ Option.value ~default:"-" (E3.undo_label !e));
  E3.close !e

(* Value nodes are bindings: the add menu offers a number, the time, a vector and every operator, and
   each becomes one [Add_node] with the expression written *)
let run_values () =
  let started () =
    let e = ref (editor "(workspace w (graph g :context sop (sop/box)))") and count = ref 0 in
    let step ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
    step []; step [];
    let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
    let p = float (gx + 40), float (gy + 40) in
    step ~mouse:p [ Event.MouseMoved p ];
    step ~mouse:p [ Event.MousePressed (Input.LeftButton, p) ];
    step ~mouse:p [ Event.MouseReleased (Input.LeftButton, p) ];
    step ~mouse:p [ Event.KeyPressed Input.Home ];
    step ~mouse:p [ Event.KeyPressed (Input.KeyChar 'i') ];
    step ~mouse:p [];
    e, (fun events -> step ~mouse:p events) in
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  let add text =
    let e, step = started () in
    check (E3.level !e = Some "g") "the box graph is open";
    step [ key Input.Space; ch 'a' ]; step [ Event.TextInput text ]; step [ key Input.Enter ]; step [];
    !e in
  let e = add "number" in
  check (E3.undo_label e = Some "Add node" && has (source e) "value 1.0") ("a number binding: " ^ source e);
  E3.close e;
  let e = add "time" in
  check (has (source e) "time t") ("a time binding: " ^ source e);
  E3.close e;
  let e = add "sin" in
  check (has (source e) "(sin 0.5)") ("an operator binding with typed defaults: " ^ source e);
  E3.close e

(* Command-D duplicates the selected nodes (fresh names, one history entry) and selects the copies; v
   views a node in the viewport (a layout entry, one history entry) and again returns to the result *)
let run_duplicate_and_view () =
  List.iter (fun text ->
  let e = ref (editor text) and count = ref 0 in
  let step ?(mouse = (450., 300.)) ?(keys = []) events =
    incr count; e := E3.update !e (Test_editor_input.frame ~keys mouse events !count) in
  step []; step [];
  let centre () = Option.bind (E3.prepared !e) Mesh.centroid
    |> Option.map (fun p -> p.Vec3.x) in
  check (centre () = Some 20.) "the initial viewport did not show the graph result";
  step ~mouse:(150., 300.) [Event.MouseMoved (150., 300.)];
  step ~mouse:(150., 300.) [Event.MouseScrolled (0., -1.)];
  step [];
  let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
  let p = float (gx + 40), float (gy + 40) in
  step ~mouse:p [ Event.MouseMoved p ];
  step ~mouse:p [ Event.MousePressed (Input.LeftButton, p) ];
  step ~mouse:p [ Event.MouseReleased (Input.LeftButton, p) ];
  step ~mouse:p [ Event.KeyPressed Input.Home ];
  step ~mouse:p [ Event.KeyPressed (Input.KeyChar 'i') ];
  step ~mouse:p [];
  let selected () = dump_line !e "scope selected" in
  step ~mouse:p [ Event.KeyPressed Input.ArrowRight ];
  check (selected () <> "-") "a walk key selected a node";
  let node = selected () in
  step ~mouse:p [ Event.KeyPressed (Input.KeyChar 'v') ];
  check (E3.undo_label !e = Some "View node"
         && Editor_document.Layout_by_path.Path_map.mem [ "g" ] (E3.workspace !e).Doc.layout.display)
    ("v did not view the node: " ^ Option.value ~default:"-" (E3.undo_label !e));
  check (has (fst (Flow.Lisp.print [ Editor_document.Layout_by_path.to_syntax (E3.workspace !e).Doc.layout ])) "(display")
    "the viewed node is saved in the layout";
  step ~mouse:p [];
  check (Node.operation (E3.displayed_node !e) = "box" && centre () = Some 0.)
    ("v marked the node but did not show it in the viewport: " ^ node);
  step ~mouse:p [ Event.KeyPressed (Input.KeyChar 'v') ];
  check (Editor_document.Layout_by_path.Path_map.is_empty (E3.workspace !e).Doc.layout.display) "v again returns to the result";
  step ~mouse:p [];
  check (centre () = Some 20.) "clearing VIEW did not restore the graph result";
  step ~mouse:p ~keys:[ Input.Meta ] [ Event.KeyPressed (Input.KeyChar 'd') ];
  check (E3.undo_label !e = Some "Duplicate" && has (source !e) "_2") ("Command-D made no copy: " ^ source !e);
  check (selected () <> node && selected () <> "-") "the copy is the selection";
  E3.close !e) [
    "(workspace w (graph g :context sop (let* [a (sop/box) b (sop/transform a :translate [20 0 0])] b)))";
    "(workspace w (graph g :context sop (let* [a (sop/box) b (sop/transform a :translate [20 0 0])] b))
       (graph scene :context scene (scene/merge (scene/geometry (ref g))
         (scene/camera :eye [0 0 6] :follow_viewport true))))"
  ]

(* An inline result is a geometry node too: viewing and editing it must follow the current
   lowering, including when an edit inserts a new plan node before the viewed one. *)
let run_result_view () =
  let e = ref (editor {|(workspace result_view
    (graph g :context sop
      (let* [a (sop/box) b (sop/transform a :translate [5 0 0])]
        (sop/transform b :translate [15 0 0])))
    (graph scene :context scene
      (scene/merge (scene/geometry (ref g))
        (scene/camera :eye [0 0 6] :follow_viewport true))))|}) in
  Fun.protect ~finally:(fun () -> E3.close !e) (fun () ->
    let count = ref 0 in
    let step ?(mouse = (450., 300.)) events =
      incr count; e := E3.update !e (frame mouse events !count) in
    let centre expected =
      let actual = Option.map (fun p -> p.Vec3.x) (Option.bind (E3.prepared !e) Mesh.centroid) in
      check (actual = Some expected)
        (Printf.sprintf "VIEW kept stale geometry: expected %.1f, got %s" expected
           (Option.fold ~none:"none" ~some:string_of_float actual)) in
    let click point =
      step ~mouse:point [Event.MouseMoved point];
      step ~mouse:point [Event.MousePressed (Input.LeftButton, point); Event.MouseReleased (Input.LeftButton, point)] in
    let select name =
      let x, y, _, _ = Option.get (E3.node_box !e ["g"; name]) in
      click (float (x + 60), float (y + 12));
      check (dump_line !e "scope selected" = "g/" ^ name) "the result node could not be selected" in
    let key k = step [Event.KeyPressed k] in
    let edit op = e := (match E3.edit !e op with Ok e -> e | Error m -> fail m); step [] in
    let parsed text = match S.parse text with Ok [e] -> e | _ -> fail "bad result-view expression" in
    step []; step []; centre 20.;
    let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
    click (float (gx + 40), float (gy + 40));
    key Input.Home; key (Input.KeyChar 'i'); step [];
    select "b"; key (Input.KeyChar 'v'); step []; centre 5.;
    select "@result"; key (Input.KeyChar 'v'); step [];
    check (Editor_document.Layout_by_path.Path_map.find_opt ["g"] (E3.workspace !e).layout.display
           = Some ["g"; "@result"]) "v refused the inline result node";
    centre 20.;
    edit (E.Set_arg {node = ["g"; "b"]; key = E.Kw "translate"; sub = []; value = parsed "[9 0 0]"});
    centre 24.;
    edit (E.Set_arg {node = ["g"; "@result"]; key = E.Kw "translate"; sub = []; value = parsed "[30 0 0]"});
    centre 39.;
    select "b"; key (Input.KeyChar 'v'); step []; centre 9.;
    edit (E.Set_arg {node = ["g"; "b"]; key = E.Whole; sub = [];
      value = parsed "(sop/transform (sop/transform a :translate [2 0 0]) :translate [9 0 0])"});
    centre 11.;
    let vx, vy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).view in
    click (float (vx + 10), float (vy + 10)); key (Input.KeyChar 'f'); step [];
    check (Float.abs ((Easy_camera.target (E3.camera !e)).Vec3.x -. 11.) < 1e-6)
      "viewport F framed the graph result instead of the viewed node";
    let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
    click (float (gx + 10), float (gy + 10)); key (Input.KeyChar 'u'); step [];
    check (dump_line !e "level" = "scene") "u did not leave the geometry network";
    centre 41.;
    click (float (gx + 40), float (gy + 40));
    key (Input.KeyChar 'i'); step [];
    select "@result"; key (Input.KeyChar 'v'); step []; centre 41.)

(* the inspector moves a list item up (Move_item), as the row arrow does *)
let run_movers () =
  let text = "(workspace w (graph g :context sop (let* [widths (list 1 2 3) r (for [i (range 2)] (sop/box :size [(nth widths i) 1 1]))] (sop/merge r))))" in
  let attempt y =
    let e = ref (editor text) and count = ref 0 in
    let step ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
    step []; step [];
    let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
    let p = float (gx + 40), float (gy + 40) in
    step ~mouse:p [ Event.MouseMoved p ];
    step ~mouse:p [ Event.MousePressed (Input.LeftButton, p) ];
    step ~mouse:p [ Event.MouseReleased (Input.LeftButton, p) ];
    step ~mouse:p [ Event.KeyPressed Input.Home ];
    step ~mouse:p [ Event.KeyPressed (Input.KeyChar 'i') ];
    step ~mouse:p [];
    let bx, by, bw, bh = Option.get (E3.node_box !e [ "g"; "widths" ]) in
    let c = float (bx + bw / 2), float (by + 8) in
    step ~mouse:c [ Event.MouseMoved c ];
    step ~mouse:c [ Event.MousePressed (Input.LeftButton, c) ];
    step ~mouse:c [ Event.MouseReleased (Input.LeftButton, c) ];
    step ~mouse:c [];
    ignore bh;
    let ix, _, iw, _ = (E3.panes !e (frame (0., 0.) [] 0)).inspector in
    let q = float (ix + iw / 2), y in
    step ~mouse:q [ Event.MouseMoved q ];
    step ~mouse:q [ Event.MousePressed (Input.LeftButton, q) ];
    step ~mouse:q [ Event.MouseReleased (Input.LeftButton, q) ];
    step ~mouse:q [];
    let label = E3.undo_label !e and moved = has (source !e) "(list 1 3 2" || has (source !e) "(list 2 1 3" in
    E3.close !e; label, moved in
  let label, moved = attempt 210. in
  check (label = Some "Move item" && moved) "the inspector's Move item button did not move a list item up"

let run_frame_key () =
  (* the graph pane's keys reach the document: Shift-G frames the walked-to node (layout data, one entry);
     the rosette is entered as in test_text_pane's W9 scenario *)
  let e = ref (editor (case "rosette")) in
  let key k = Event.KeyPressed k in
  for n = 1 to 24 do
    let click p = [ Event.MouseMoved p; Event.MousePressed (Input.LeftButton, p); Event.MouseReleased (Input.LeftButton, p) ] in
    let events = match n with
      | 4 -> click (900., 300.) | 6 -> [ key Input.ArrowDown ] | 8 -> [ key (Input.KeyChar 'i') ]
      | 16 -> [ key Input.ArrowRight ] | 18 -> [ key Input.Shift; key (Input.KeyChar 'g') ] | _ -> [] in
    let f : Frame.t = { width = 1400; height = 800; size = 1400, 800; drawable_width = 1400;
      drawable_height = 800; drawable_size = 1400, 800; pixel_scale = 1., 1.;
      time = float n /. 60.; dt = 1. /. 60.; fps = 60.; count = n; mouse = (640., 360.);
      mouse_delta = 0., 0.; keys = (if n = 18 then [ Input.Shift ] else []); mouse_buttons = []; events } in
    e := E3.update !e f
  done;
  check (E3.undo_label !e = Some "Frame") ("g made a frame: " ^ Option.value ~default:"-" (E3.undo_label !e));
  check (not (Editor_document.Layout_by_path.Path_map.is_empty (E3.workspace !e).Doc.layout.frames))
    "the frame is in the layout"

let panes_graph e = let _, _, w, _ = (E3.panes e (frame (0., 0.) [] 0)).graph in w

let run_ops () =
  let e = editor (case "variations") in
  let ok label op =
    match E3.edit e op with
    | Ok e' -> check (E3.undo_label e' = Some label) ("label " ^ label ^ ": " ^ Option.value ~default:"-" (E3.undo_label e')); e'
    | Error m -> fail (label ^ ": " ^ m) in
  let tree e = (shell_of (build_ok (E3.workspace e))).tree in
  let sh = tree e in
  (* resize *)
  let r = ok "Resize panel" (E.Set_layout_ratio { node = [ "editor"; "left" ]; ratio = 0.3 }) in
  check (has (source r) "(ui/split-at \"vertical\" 0.3 network code)") "Set_layout_ratio";
  check (match (tree (ok "Resize panel" (E.Set_layout_ratio { node = [ "editor"; "left" ]; ratio = 5. }))) with
      | Split { b = Split { a = Split { ratio; _ }; _ }; _ } -> ratio = 0.9 | _ -> false) "a ratio clamps to 0.9";
  (* a ui/split (no ratio) becomes ui/split-at *)
  let plain = editor (with_editor "    (let* [a (ui/graph) b (ui/lisp) s (ui/split \"horizontal\" a b)] (ui/workspace s))") in
  (match E3.edit plain (E.Set_layout_ratio { node = [ "editor"; "s" ]; ratio = 0.25 }) with
   | Ok p -> check (has (source p) "(ui/split-at \"horizontal\" 0.25 a b)") "ui/split gets a ratio"
   | Error m -> fail m);
  (* split, close, retype *)
  let s = ok "Split panel" (E.Split_panel { node = [ "editor"; "network" ]; axis = `V }) in
  check (Panels.to_string (tree s) = "(h outline (h (v (v graph lisp) lisp) (tile view view view view)))") ("split: " ^ Panels.to_string (tree s));
  check (has (source s) "(ui/split-at \"vertical\" 0.5 network_a network_b)") "the new split";
  let c = ok "Close panel" (E.Close_panel { node = [ "editor"; "network" ] }) in
  check (Panels.to_string (tree c) = "(h outline (h lisp (tile view view view view)))") ("close: " ^ Panels.to_string (tree c));
  let t = ok "Retype panel" (E.Set_panel_kind { node = [ "editor"; "network" ]; kind = "list" }) in
  check (Panels.to_string (tree t) = "(h outline (h (v list lisp) (tile view view view view)))") ("retype: " ^ Panels.to_string (tree t));
  let v = ok "Retype panel" (E.Set_panel_kind { node = [ "editor"; "outline" ]; kind = "viewport" }) in
  check (has (source v) "outline (ui/viewport (ref scene))") "a viewport is over the first scene graph";
  let docked = ok "Dock panel" (E.Dock_panel {node = ["editor"; "network"]; target = ["editor"; "outline"]; side = `Right}) in
  check (Panels.to_string (tree docked) = "(h (h outline graph) (h lisp (tile view view view view)))")
    ("docking duplicated a panel or left a gap: " ^ Panels.to_string (tree docked));
  check (has (source docked) "(ui/split-at \"horizontal\" 0.5 outline_content network)")
    "docking was not reflected in the editor Lisp";
  (* undo restores the tree with the source *)
  check (Panels.to_string (tree e) = Panels.to_string sh) "undo target";
  (* refusals leave everything alone *)
  let refuse name op needle = match E3.edit e op with
    | Error m -> check (has m needle) (name ^ ": " ^ m)
    | Ok _ -> fail (name ^ " was accepted") in
  refuse "close outside a split" (E.Close_panel { node = [ "editor"; "shell" ] }) "inside a split";
  refuse "an unknown panel type" (E.Set_panel_kind { node = [ "editor"; "network" ]; kind = "dashboard" }) "Unknown panel type";
  refuse "resize a panel" (E.Set_layout_ratio { node = [ "editor"; "network" ]; ratio = 0.4 }) "not a split";
  refuse "no such binding" (E.Split_panel { node = [ "editor"; "nothing" ]; axis = `H }) "no longer exists"

(* an editor graph that hides everything is valid; Restore layout brings the default back *)
let run_restore () =
  let e = ref (editor (case "variations")) and count = ref 0 in
  let step ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
  step []; step [];
  check (panes_graph !e > 0) "the shell starts with a graph panel";
  (* an invalid editor graph is refused whole: the layout and the document stay *)
  let before = source !e in
  (match E3.edit !e (E.Set_arg { node = [ "editor"; "panels" ]; key = Pos 1; sub = []; value = S.make (S.Num "0.95") }) with
   | Error _ -> ()
   | Ok _ -> fail "a ratio of 0.95 was accepted");
  check (source !e = before && panes_graph !e > 0) "a refused edit keeps the layout";
  (* a valid one that leaves only an outline: nothing to edit the layout with *)
  let bricked = E3.edit !e (E.Set_arg { node = [ "editor"; "shell" ]; key = Pos 0; sub = []; value =
    S.make (S.List [ S.make (S.Sym "ui/outline") ]) }) |> Result.get_ok in
  e := bricked;
  step [];
  check (panes_graph !e = 0) "the bricked shell has no graph panel";
  let key k = Event.KeyPressed k in
  step [ key Input.Space; key (Input.KeyChar 'z') ]; step [];
  check (panes_graph !e > 0) "Space z restores the default layout";
  check (has (dump_line !e "cook") "Default layout") ("the status says so: " ^ dump_line !e "cook");
  check (source !e = source bricked) "the document is untouched by Restore";
  (* the editor graph is repaired from the restored shell: the layout edit ends the restore *)
  let repaired = E3.edit !e (E.Set_arg { node = [ "editor"; "shell" ]; key = Pos 0; sub = []; value = S.make (S.Sym "panels") })
    |> Result.get_ok in
  e := repaired; step [];
  check (panes_graph !e > 0 && not (has (dump_line !e "cook") "Default layout")) "editing the editor graph ends the restore";
  (* pressing it twice returns to the editor graph's layout *)
  e := bricked; step [];
  step [ key Input.Space; key (Input.KeyChar 'z') ]; step [];
  step [ key Input.Space; key (Input.KeyChar 'z') ]; step [];
  check (panes_graph !e = 0) "the second Space z returns to the editor graph"

(* one orbit camera per viewport: the drag of the focused viewport moves only it, and focusing
   another keeps what each one showed *)
let run_camera_zoom () =
  let e = ref (editor ~camera:(Easy_camera.create ~inertia:false ())
    "(workspace zoom (graph g :context sop (sop/box)) (graph scene :context scene (scene/merge (scene/geometry (ref g)) (scene/camera :eye [0 0 12345.123456789] :follow_viewport true :active true))))") in
  let step events count = e := E3.update !e (frame (200., 200.) events count) in
  step [] 0; step [] 1;
  step [Event.MouseMoved (200., 200.); Event.MousePressed (Input.LeftButton, (200., 200.));
    Event.MouseReleased (Input.LeftButton, (200., 200.))] 2;
  for count = 3 to 15 do
    step [Event.MouseScrolled (0., -1.)] (2 * count);
    let viewport = Easy_camera.camera (E3.camera !e) and saved = E3.render_camera !e in
    check (Vec3.nearly_equal (Camera.position viewport) (Camera.position saved) ~eps:1e-6)
      "zooming out made the following camera lag behind the viewport";
    let eye = Camera.position viewport in
    step [] ((2 * count) + 1);
    check (Vec3.nearly_equal eye (Camera.position (Easy_camera.camera (E3.camera !e))) ~eps:1e-6)
      "an idle frame snapped the viewport to rounded camera coordinates"
  done;
  E3.close !e

let run_cameras () =
  let e = ref (editor ~camera:(Easy_camera.with_inertia false (Easy_camera.create ~target:Vec3.zero ~distance:7. ())) (case "variations")) and count = ref 0 in
  let step ?(buttons = []) ?(delta = (0., 0.)) (x, y) events =
    incr count; e := E3.update !e (Test_editor_input.frame ~buttons ~delta (x, y) events !count) in
  for _ = 1 to 8 do step (450., 300.) [] done;
  let geometry () = Layout.geometry ~hidden:[ Layout.Timeline ] ~top:28 (shell_of (build_ok (E3.workspace !e))).tree
      (frame (0., 0.) [] 0) in
  let center key =
    let leaf = Option.get (Layout.find (geometry ()) (Layout.View key)) in
    let x, y, w, h = leaf.body in float (x + (w / 2)), float (y + (h / 2)) in
  let position key = Camera.position (E3.viewport_camera !e key) in
  let keys = [ "v1.1.0"; "v1.1.1"; "v1.1.2"; "v1.1.3" ] in
  let click key =
    let p = center key in
    step p [ Event.MouseMoved p ];
    step ~buttons:[ Input.LeftButton ] p [ Event.MousePressed (Input.LeftButton, p) ];
    step p [ Event.MouseReleased (Input.LeftButton, p) ]; step p [] in
  (* a press at the point of the click just before would be a double click *)
  let orbit key delta =
    let x, y = let x, y = center key in x, y +. 40. in
    step (x, y) [ Event.MouseMoved (x, y) ];
    step ~buttons:[ Input.LeftButton ] (x, y) [ Event.MousePressed (Input.LeftButton, (x, y)) ];
    for k = 1 to 6 do
      let p = x +. float k *. fst delta, y +. float k *. snd delta in
      step ~buttons:[ Input.LeftButton ] ~delta p [ Event.MouseMoved p ]
    done;
    let last = x +. 6. *. fst delta, y +. 6. *. snd delta in
    step last [ Event.MouseReleased (Input.LeftButton, last) ]; step last [] in
  let same a b = Vec3.nearly_equal a b ~eps:1e-9 in
  click "v1.1.1";
  let start = List.map (fun k -> k, position k) keys in
  check (List.for_all (fun (_, p) -> same p (snd (List.hd start))) start) "viewports start from one orbit";
  orbit "v1.1.1" (20., 0.);
  check (not (same (position "v1.1.1") (List.assoc "v1.1.1" start))) "a drag did not orbit the focused viewport";
  List.iter (fun k -> check (same (position k) (List.assoc k start)) (k ^ " moved with another viewport's drag"))
    [ "v1.1.0"; "v1.1.2"; "v1.1.3" ];
  let first = position "v1.1.1" in
  click "v1.1.2";
  check (same (position "v1.1.1") first) "focusing another viewport moved the one left";
  orbit "v1.1.2" (-20., 10.);
  check (not (same (position "v1.1.2") (List.assoc "v1.1.2" start)) && not (same (position "v1.1.2") first))
    "the second viewport did not orbit on its own";
  check (same (position "v1.1.1") first && same (position "v1.1.0") (List.assoc "v1.1.0" start))
    "the second drag disturbed the first viewport";
  click "v1.1.1";
  check (same (position "v1.1.1") first) "returning to a viewport lost its orbit";
  (* a click on the geometry of a viewport over another scene instance selects the node that made
     it: the pane shows that graph and the node is selected there *)
  let graph_pane =
    let geometry = Layout.geometry ~hidden:[ Layout.Timeline ] ~top:28 (shell_of (build_ok (E3.workspace !e))).tree
        (frame (0., 0.) [] 0) in
    let x, y, _, _ = (Option.get (Layout.find geometry Layout.Graph)).body in
    float (x + 20), float (y + 200) in
  step graph_pane [ Event.MouseMoved graph_pane ];
  step ~buttons:[ Input.LeftButton ] graph_pane [ Event.MousePressed (Input.LeftButton, graph_pane) ];
  step graph_pane [ Event.MouseReleased (Input.LeftButton, graph_pane) ];
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  step graph_pane [ key Input.Space; ch 'l'; ch 'g' ]; step graph_pane [];
  check (has (dump_line !e "projection") "graph") ("the pane is not showing a graph: " ^ dump_line !e "projection");
  let scope_selected () = dump_line !e "scope selected" in
  click "v1.1.2";
  check (dump_line !e "pane graph" = "garden" && scope_selected () <> "-")
    (Printf.sprintf "a click in another instance's viewport selected nothing (pane %s, selected %s)"
       (dump_line !e "pane graph") (scope_selected ()));
  E3.close !e

(* the frame draws one 3D layer per viewport, each over its own scene instance *)
let run_views () =
  let e = ref (editor (case "variations")) in
  for c = 1 to 12 do e := E3.update !e (frame (450., 300.) [] c) done;
  check (List.length (E3.objects !e) >= 1 && Option.is_some (E3.prepared !e)) "the editor did not cook";
  for c = 200 to 230 do e := E3.update !e (frame (450., 300.) [] c) done;
  let scene = E3.scene !e (frame (450., 300.) [] 231) in
  match Scene.Private.stage_native ~width:900 ~height:640 scene with
  | Error m -> fail m
  | Ok staged ->
      let viewports = List.length (List.filter (function Scene.Private.Scene3_layer _ -> true | _ -> false) staged.layers) in
      check (viewports = 4) (Printf.sprintf "four viewports draw four 3D layers, got %d" viewports)


(* ---- the copies of a loop are one template, through the editor (register V4) ---- *)

let count_of text piece =
  let n = String.length piece in
  let rec go i acc = if i + n > String.length text then acc
    else go (i + 1) (if String.sub text i n = piece then acc + 1 else acc) in
  go 0 0

(* the list's rows, walked with the arrows: the row under the focus is the selection *)
let select_row e count k =
  let step ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
  step []; step [];
  let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
  let p = float (gx + 40), float (gy + 400) in
  step ~mouse:p [ Event.MousePressed (Input.LeftButton, p); Event.MouseReleased (Input.LeftButton, p) ];
  step [ Event.KeyPressed Input.Home ];
  for _ = 1 to k do step [ Event.KeyPressed Input.ArrowDown ] done;
  step []

(* a drag across the inspector's slider at [row] points under the panel's top *)
let drag_slider e count row =
  let step ?(buttons = []) ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame ~buttons mouse events !count) in
  let ix, iy, iw, _ = (E3.panes !e (frame (0., 0.) [] 0)).inspector in
  let at x = float (ix + (iw * 70 / 100) + x), float (iy + row) in
  step ~mouse:(at 0) ~buttons:[ Input.LeftButton ] [ Event.MousePressed (Input.LeftButton, at 0) ];
  List.iter (fun x -> step ~mouse:(at x) ~buttons:[ Input.LeftButton ] []) [ 4; 8; 12; 16 ];
  step ~mouse:(at 20) [ Event.MouseReleased (Input.LeftButton, at 20) ];
  step []

let objects e = Edit_graph.inspect (E3.scene_document e)
let field_of (i : Edit_graph.node_info) name = List.find_map (fun (f : Parameter.field_view) ->
  if f.name = name then Some f.current else None) (Node.parameter_fields i.node)

let run_loop_copies () =
  (* copies that differ only by the graph they place: every field of the template is a literal *)
  let text = {|(workspace copies
    (graph g :context sop [(seed : int 1)] (sop/box :size [seed 1 1]))
    (graph scene :context scene
      (let* [row (for [i (range 3)] (scene/geometry (ref g :seed (+ i 1))))]
        (scene/merge row))))|} in
  let e = ref (editor text) and count = ref 0 in
  select_row e count 1;
  let x () = List.map (fun i -> field_of i "translate_x") (objects !e) in
  check (List.length (objects !e) = 3 && List.for_all (fun v -> v = Some (Parameter.Float_value 0.)) (x ()))
    "the loop did not make three objects at the origin";
  drag_slider e count 171;
  let moved = x () in
  check (List.for_all (fun v -> v = List.hd moved && v <> Some (Parameter.Float_value 0.)) moved)
    "dragging a literal field of one copy did not move all three";
  check (count_of (source !e) ":translate [" = 1) ("the template was not edited once: " ^ source !e);
  check (E3.undo_label !e = Some "Set translate_x") "the drag is not one history entry named for the field";
  check (has (dump_line !e "cook") "loop template" && has (dump_line !e "cook") "3 copies")
    ("the status does not say the template changed: " ^ dump_line !e "cook");
  let saved = source !e in
  E3.close !e;
  e := editor saved;
  check (x () = moved) "the saved text does not reopen with the same copies";
  (* one undo gives them all back *)
  e := E3.update !e { (frame (450., 300.) [ Event.KeyPressed (Input.KeyChar 'z') ] (incr count; !count)) with keys = [ Input.Meta ] };
  E3.close !e;
  (* a rename from the list is the template's :name: every copy takes it *)
  let e = ref (editor text) and count = ref 0 in
  select_row e count 2;
  let step events = incr count; e := E3.update !e (frame (450., 300.) events !count) in
  step [ Event.KeyPressed Input.F2 ]; step [ Event.TextInput "spot" ]; step [ Event.KeyPressed Input.Enter ]; step [];
  check (List.for_all (fun (i : Edit_graph.node_info) -> i.label = "gspot") (objects !e)
         && count_of (source !e) ":name \"gspot\"" = 1 && E3.undo_label !e = Some "Rename")
    ("a rename of one copy did not rename the template: " ^ source !e ^ String.concat "," (List.map (fun (i : Edit_graph.node_info) -> i.label) (objects !e)));
  E3.close !e;
  (* a copy computed from its index has no value of its own *)
  let text = {|(workspace lamps
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (let* [row (for [i (range 3)] (scene/light :name "lamp" :translate [i 2 0]))]
        (scene/merge (scene/geometry (ref g)) row))))|} in
  let e = ref (editor text) and count = ref 0 in
  select_row e count 2;
  let before = source !e in
  drag_slider e count 195;
  check (source !e = before && E3.undo_label !e = None) "a computed field of a copy was written";
  check (has (dump_line !e "edit error") "computed by the loop") ("no reason for the refused edit: " ^ dump_line !e "edit error");
  (* deleting one copy skips its iteration: the others stay where they are *)
  select_row e count 2;
  e := E3.update !e (frame (450., 300.) [ Event.KeyPressed Input.Delete ] (incr count; !count));
  let lamps () = List.filter (fun (i : Edit_graph.node_info) -> i.operation = "light") (objects !e) in
  check (List.length (lamps ()) = 2 && has (source !e) ":skip [1]" && E3.undo_label !e = Some "Delete")
    ("deleting a copy did not skip it in the loop: " ^ source !e);
  check (List.map (fun i -> field_of i "translate_x") (lamps ())
         = [ Some (Parameter.Float_value 0.); Some (Parameter.Float_value 2.) ])
    "the copies after a deleted one moved";
  E3.close !e;
  (* a loop with two clauses: the same, one entry, and one undo gives the copy back *)
  let text = {|(workspace grid
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (let* [row (for [i (range 2) j (range 3)] (scene/light :translate [i j 0]))]
        (scene/merge (scene/geometry (ref g)) row))))|} in
  let e = ref (editor text) and count = ref 0 in
  select_row e count 2;
  let before = source !e in
  e := E3.update !e (frame (450., 300.) [ Event.KeyPressed Input.Delete ] (incr count; !count));
  check (has (source !e) ":skip [1]" && List.length (objects !e) = 6 && E3.undo_label !e = Some "Delete"
         && dump_line !e "prompt" = "-")
    ("a copy of a two-clause loop was not deleted exactly: " ^ source !e);
  let saved = source !e in
  e := E3.update !e { (frame (450., 300.) [ Event.KeyPressed (Input.KeyChar 'z') ] (incr count; !count)) with keys = [ Input.Meta ] };
  check (source !e = before && List.length (objects !e) = 7) "one undo did not give the deleted copy back";
  E3.close !e;
  e := editor saved;
  check (List.length (objects !e) = 6 && source !e = saved) "the saved text does not reopen without the copy";
  E3.close !e;
  print_endline "workspace shell: a loop's copies are one template (edit, computed refusal, exact delete, undo) ok"

(* an expression typed in a row of a copy is the template's argument: every copy follows it *)
let run_loop_expression () =
  let text = {|(workspace lamps
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (let* [row (for [i (range 3)] (scene/light :name "lamp" :translate [i 2 0]))]
        (scene/merge (scene/geometry (ref g)) row))))|} in
  let e = ref (editor text) and count = ref 0 in
  select_row e count 2;
  let step ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
  let ix, iy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).inspector in
  let label = float (ix + 30), float (iy + 195) in
  step ~mouse:label [ Event.MouseMoved label ];
  List.iter (fun () ->
    step ~mouse:label [ Event.MousePressed (Input.LeftButton, label) ];
    step ~mouse:label [ Event.MouseReleased (Input.LeftButton, label) ]) [ (); () ];
  step ~mouse:label [ Event.KeyPressed (Input.KeyChar 'a') ];
  step ~mouse:label [ Event.TextInput "=(* i 3)" ];
  step ~mouse:label [ Event.KeyPressed Input.Enter ];
  step ~mouse:label [];
  let lamps () = List.filter (fun (i : Edit_graph.node_info) -> i.operation = "light") (objects !e) in
  check (has (source !e) ":translate [(* i 3) 2 0]") ("the expression did not reach the template: " ^ source !e);
  check (List.map (fun i -> field_of i "translate_x") (lamps ())
         = List.map (fun v -> Some (Parameter.Float_value v)) [ 0.; 3.; 6. ])
    "the copies did not follow the expression";
  check (E3.undo_label !e = Some "Edit expression" && dump_line !e "edit error" = "-"
         && has (dump_line !e "cook") "loop template") "the expression edit is not one entry with its status";
  let saved = source !e in
  E3.close !e;
  e := editor saved;
  check (List.map (fun i -> field_of i "translate_x") (lamps ())
         = List.map (fun v -> Some (Parameter.Float_value v)) [ 0.; 3.; 6. ]) "the saved text does not reopen with the same copies";
  E3.close !e;
  print_endline "workspace shell: an expression typed in a copy edits the template ok"


let run_panel_states () =
  let directory = Filename.temp_dir "prismel-panel-state" "" in
  let e = ref (editor ~presets:directory "(workspace panels (graph g :context sop (sop/box)))")
  and count = ref 0 in
  let step ?(buttons = []) ?(keys = []) mouse events = incr count;
    e := E3.update !e (Test_editor_input.frame ~buttons ~keys mouse events !count) in
  let click point = step point [Event.MouseMoved point];
    step point [Event.MousePressed (Input.LeftButton, point); Event.MouseReleased (Input.LeftButton, point)];
    step point [] in
  step (450., 300.) []; step (450., 300.) [];
  let geometry = Layout.geometry ~hidden:[Layout.Timeline] Layout.default (frame (0., 0.) [] 0) in
  let splitter = List.find (fun (s : Layout.splitter) -> s.node = Some []) geometry.splitters in
  let sx, sy, sw, sh = splitter.bounds in
  let grip = float (sx + sw / 2), float (sy + sh / 2) in
  let moved = fst grip +. 30., snd grip in
  step grip [Event.MouseMoved grip];
  step ~buttons:[Input.LeftButton] grip [Event.MousePressed (Input.LeftButton, grip)];
  step ~buttons:[Input.LeftButton] moved [Event.MouseMoved moved];
  step moved [Event.MouseReleased (Input.LeftButton, moved)]; step moved [];
  check ((E3.workspace !e).layout.editor = None && has (source !e) "ui/split-at"
         && E3.undo_label !e = Some "Resize panel")
    "resizing the default shell did not write its editor graph";
  let saved_shell = (build_ok (E3.workspace !e)).Document.shell in
  check ((build_ok (of_text (Doc.to_text (E3.workspace !e)))).Document.shell = saved_shell)
    "the first splitter edit did not round-trip through Lisp";
  step ~keys:[Input.Meta] moved [Event.KeyPressed (Input.KeyChar 'z')];
  check ((build_ok (E3.workspace !e)).Document.shell = None)
    "undoing the first splitter edit did not restore the default shell";
  click (889., 11.);
  let state key = Option.value ~default:Editor_core.Panels.default_state
    (Editor_document.Layout_by_path.Path_map.find_opt ["editor"; key] (E3.workspace !e).layout.panels) in
  check ((state "inspector").collapsed && E3.undo_label !e = Some "Collapse panel"
         && (let _, _, w, _ = (E3.panes !e (frame (0., 0.) [] 0)).inspector in w = 0))
    "collapsing a panel did not persist or remove its body";
  let saved = Doc.to_text (E3.workspace !e) in
  check ((of_text saved).layout.panels = (E3.workspace !e).layout.panels)
    "panel state did not round-trip through Lisp";
  click (889., 39.);
  check (not (state "inspector").collapsed) "the collapsed header could not expand the panel";
  let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
  let start = float (gx + 8), float (gy - 11) in
  let moved = fst start +. 30., snd start +. 70. in
  step start [Event.MouseMoved start];
  step ~buttons:[Input.LeftButton] start [Event.MousePressed (Input.LeftButton, start)];
  step ~buttons:[Input.LeftButton] moved [Event.MouseMoved moved];
  step ~buttons:[Input.LeftButton] (fst moved +. 10., snd moved) [Event.MouseMoved (fst moved +. 10., snd moved)];
  step moved [Event.MouseReleased (Input.LeftButton, moved)]; step moved [];
  check ((state "network").window <> None && E3.undo_label !e = Some "Arrange panel")
    "the panel drag handle did not undock the panel";
  let window = Option.get (state "network").window in
  let x, y, w, h = window in
  let grip = float (x + 8), float (y + 11) in
  let to_ = fst grip +. 35., snd grip +. 30. in
  step grip [Event.MouseMoved grip];
  step ~buttons:[Input.LeftButton] grip [Event.MousePressed (Input.LeftButton, grip)];
  step ~buttons:[Input.LeftButton] to_ [Event.MouseMoved to_];
  step to_ [Event.MouseReleased (Input.LeftButton, to_)]; step to_ [];
  check ((state "network").window = Some (x + 35, y + 30, w, h))
    "an underlying pane covered the floating drag handle";
  step ~keys:[Input.Meta] to_ [Event.KeyPressed (Input.KeyChar 'z')];
  check ((state "network").window = Some window) "a second window drag merged with the previous gesture";
  let visible_h = min h (640 - y) in
  let corner = float (x + w - 4), float (y + visible_h - 4) in
  let to_ = fst corner -. 35., snd corner -. 40. in
  step corner [Event.MouseMoved corner];
  step ~buttons:[Input.LeftButton] corner [Event.MousePressed (Input.LeftButton, corner)];
  step ~buttons:[Input.LeftButton] to_ [Event.MouseMoved to_];
  step to_ [Event.MouseReleased (Input.LeftButton, to_)]; step to_ [];
  check ((state "network").window = Some (x, y, w - 35, visible_h - 40))
    "the floating window resize handle did not persist its size";
  step ~keys:[Input.Meta] to_ [Event.KeyPressed (Input.KeyChar 'z')];
  step ~keys:[Input.Meta] moved [Event.KeyPressed (Input.KeyChar 'z')];
  check ((state "network").window = None && not (state "inspector").collapsed)
    "one undo did not revert the whole window drag";
  (* Drop onto the viewport's lower edge: a docked split, preserved panel types, one undo. *)
  let before = Doc.to_text (E3.workspace !e) in
  let gx, gy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).graph in
  let start = float (gx + 8), float (gy - 11) and target = (180., 580.) in
  step start [Event.MouseMoved start];
  step ~buttons:[Input.LeftButton] start [Event.MousePressed (Input.LeftButton, start)];
  step ~buttons:[Input.LeftButton] target [Event.MouseMoved target];
  step ~buttons:[Input.LeftButton] target [];
  step target [Event.MouseReleased (Input.LeftButton, target)]; step target [];
  check (has (source !e) "preview_content network)" && (state "network").window = None
         && dump_line !e "edit error" = "-")
    ("the edge drop did not dock the panel: " ^ dump_line !e "edit error" ^ "\n" ^ source !e);
  step ~keys:[Input.Meta] target [Event.KeyPressed (Input.KeyChar 'z')];
  check (Doc.to_text (E3.workspace !e) = before) "one undo did not revert the docking gesture";
  step target [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'g')]; step target [];
  check ((state "network").collapsed) "the leader graph toggle was not saved";
  step target [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'a')];
  check (not (state "network").collapsed) "Add did not expand the saved collapsed graph";
  step target [];
  step target [Event.KeyPressed Input.Escape]; step target [];
  step target [Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 't')]; step target [];
  check (Option.fold ~none:false ~some:(fun (state : Panels.state) -> not state.collapsed)
      (Editor_document.Layout_by_path.Path_map.find_opt ["editor"; "@panel"; "-1"]
        (E3.workspace !e).layout.panels))
    "the leader timeline toggle was not saved";
  let prepared = E3.prepared !e in
  e := E3.set_renderer !e Prismel_editor.Renderer.Wireframe;
  step target [];
  check (E3.renderer !e = Prismel_editor.Renderer.Wireframe && Option.equal ( == ) (E3.prepared !e) prepared)
    "the shared wireframe choice recooked the geometry";
  e := E3.set_renderer !e Prismel_editor.Renderer.Raster;
  step target [];
  check (E3.renderer !e = Prismel_editor.Renderer.Raster && Option.equal ( == ) (E3.prepared !e) prepared)
    "the shared raster choice recooked the geometry";
  E3.close !e;
  Array.iter (fun name -> let path = Filename.concat directory name in
    if Sys.is_directory path then begin
      Array.iter (fun name -> Sys.remove (Filename.concat path name)) (Sys.readdir path); Unix.rmdir path
    end else Sys.remove path) (Sys.readdir directory);
  Unix.rmdir directory

let run () = run_result_view (); run_panel_states (); run_camera_zoom (); run_cameras (); run_lowering (); run_ops (); run_panel_keys (); run_unbound_panels (); run_values (); run_duplicate_and_view (); run_movers (); run_frame_key (); run_loop_copies (); run_loop_expression (); run_editor (); run_restore (); run_views ()

(* Native VIEW regression over the reported sketch, including its piece renderer and a following
   camera. Moving the camera rebuilds the lowering while preserving an unchanged object network. *)
let run_view_native () =
  let directory = Filename.temp_dir "prismel-view" "" in
  let prefix = Option.value ~default:(Filename.concat directory "view")
      (Sys.getenv_opt "PRISMEL_VIEW_PNG") in
  let text = In_channel.with_open_bin "../sketches/shattered_cube/sketch.plisp" In_channel.input_all in
  let rendered = ref "" and vertices = ref [] and original = ref [] and edited = ref []
  and returned = ref false in
  ignore (Sketch.run_state ~max_frames:37
    ~config:{Sketch.default_config with width = 1200; height = 760;
      title = "Shattered Cube · VIEW regression"; domains = Some 1}
    ~init:(fun _ -> E3.create ~await:true ~workspace:(of_text text)
      ~presets:(Filename.concat directory "presets") ~seed:7349L ~grain:2
      ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:6.8 ~azimuth:0.72 ~elevation:0.42 ())
      ~prepare:(fun _ output ->
        match Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Primitive "piece" output.Session.geometry with
        | Some attribute when (match Pdk.Attribute.Private.storage attribute with
            | Pdk.Attribute.Int _ | Text _ -> true | _ -> false) ->
            Sketch_support.Packed_pieces.of_geometry ~piece_attribute:"piece" output.geometry
            |> Result.map (fun pieces -> `Pieces pieces)
        | _ -> Pdk_prismel.Prismel_mesh.to_mesh output.geometry
            |> Result.map (fun mesh -> `Mesh (mesh, output.instances))
            |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun node preview ->
        rendered := Node.operation node;
        let mesh, transforms = match preview with
          | `Pieces pieces -> Sketch_support.Packed_pieces.mesh_for_node node pieces, None
          | `Mesh (mesh, transforms) -> mesh, transforms in
        vertices := Mesh.vertices mesh;
        let shading = if Node.operation node = "box" then Scene3.Flat else Smooth in
        let material = Material.create ~diffuse:(Color.hex_exn "#f2b36d") () in
        let drawing = match transforms with
          | Some transforms -> Scene3.instances_array ~cull:Scene3.Cull_none ~shading ~material mesh transforms
          | None -> Scene3.mesh ~cull:Scene3.Cull_none ~shading ~material mesh in
        Scene3.create [drawing]) () |> Result.get_ok)
    ~update:(fun e (frame : Frame.t) ->
      let e = if frame.count = 28 then
          E3.edit e (E.Set_arg {node = ["shattered"; "@result"]; key = E.Kw "amount";
            sub = []; value = S.make (S.Num "0.8")}) |> Result.get_ok
        else e in
      let gx, gy, _, _ = (E3.panes e frame).graph in
      let graph = float (gx + 40), float (gy + 40) and view = 150., 300. in
      let mouse = if frame.count = 24 then
          let x, y, w, _ = Option.get (E3.node_box e ["shattered"; "@result"]) in
          float (x + w / 2), float (y + 2)
        else if List.mem frame.count [3; 4; 18; 19; 20; 21; 22] then view else graph in
      let key k = Event.KeyPressed k in
      let events = match frame.count with
        | 3 | 6 | 18 | 23 -> [Event.MouseMoved mouse]
        | 4 | 19 -> [Event.MouseScrolled (0., -1.)]
        | 7 -> [Event.MousePressed (Input.LeftButton, mouse)]
        | 8 -> [Event.MouseReleased (Input.LeftButton, mouse)]
        | 9 -> [key Input.Home] | 10 -> [key (Input.KeyChar 'i')]
        | 12 -> [key Input.ArrowRight] | 14 | 25 -> [key (Input.KeyChar 'v')]
        | 24 -> [Event.MouseMoved mouse; Event.MousePressed (Input.LeftButton, mouse);
            Event.MouseReleased (Input.LeftButton, mouse)]
        | 32 -> [key (Input.KeyChar 'u')]
        | _ -> [] in
      E3.update e {frame with mouse; events; keys = []; mouse_buttons = []})
    ~view:E3.scene
    ~after_present:(fun e (frame : Frame.t) ->
      if List.mem frame.count [5; 16; 22; 26; 30; 36] then begin
        let operation = if frame.count = 16 || frame.count = 22 then "box" else "exploded_view" in
        check (Node.operation (E3.displayed_node e) = operation && !rendered = operation)
          (Printf.sprintf "Shattered Cube frame %d rendered %s instead of %s" frame.count !rendered operation);
        check (Canvas.save_screen_png (Printf.sprintf "%s-%d.png" prefix frame.count) = Ok ())
          "VIEW screenshot failed";
        if frame.count = 26 then begin
          original := !vertices;
          check (Editor_document.Layout_by_path.Path_map.find_opt ["shattered"] (E3.workspace e).layout.display
                 = Some ["shattered"; "@result"]) "native v refused the result node"
        end;
        if frame.count = 30 then begin
          edited := !vertices;
          check (!edited <> !original) "editing the result left the rendered geometry cached"
        end;
        if frame.count = 36 then begin
          check (dump_line e "level" = "scene" && !vertices = !edited)
            "returning up showed the old rendered result";
          returned := true
        end
      end;
      E3.after_present e frame)
    ~on_stop:E3.close ());
  check !returned "native VIEW regression stopped before returning to the scene";
  if Sys.getenv_opt "PRISMEL_VIEW_PNG" = None then
    List.iter (fun n -> Sys.remove (Printf.sprintf "%s-%d.png" prefix n)) [5; 16; 22; 26; 30; 36];
  let state = Filename.concat directory "presets/state" in
  if Sys.file_exists state then begin
    Array.iter (fun name -> Sys.remove (Filename.concat state name)) (Sys.readdir state);
    Unix.rmdir state; Unix.rmdir (Filename.dirname state)
  end;
  Unix.rmdir directory;
  print_endline "Shattered Cube: native VIEW of the result, camera movement, parameter edit and returning up passed"

(* Native: a real window draws Variations' four viewports, each its own scene instance (the
   frame's 3D layers were once cached per frame, so only the first drew). *)
let run_renderers_native ?(authored = false) () =
  let directory = Filename.temp_dir "prismel-renderer" "" in
  let workspace = of_text (Printf.sprintf {|
    (workspace renderer
      (graph g :context sop (sop/box))
      (graph scene :context scene
        (scene/merge (scene/geometry (ref g)) (scene/camera :eye [0 0 6])))
      (graph layout :context editor
        (let* [main (ui/viewport (ref scene))
               floating (ui/viewport (ref scene))
               network (ui/graph)
               side (ui/split-at "vertical" 0.5 network %s)]
          (ui/workspace (ui/split-at "horizontal" 0.5 main side)))))
    %s
  |} (if authored then "(ui/floating floating)" else "floating")
    (if authored then "" else "(layout (panel [\"layout\" \"floating\"] :collapsed false :window [450 120 320 280]))")) in
  let samples = ref [] in
  ignore (Sketch.run_state ~max_frames:46
    ~config:{Sketch.default_config with width = 900; height = 640; title = "shared renderer"}
    ~init:(fun _ -> E3.create ~await:true ~workspace ~presets:(Filename.concat directory "presets")
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [Scene3.mesh
        ~material:(Material.unlit (Color.rgb 190 30 20)) mesh]) () |> Result.get_ok)
    ~update:(fun e (frame : Frame.t) ->
      let mode = if frame.count < 10 || frame.count >= 40 then Prismel_editor.Renderer.Raster
        else if frame.count < 25 then Wireframe else Path_traced in
      let e = if E3.renderer e = mode then e else E3.set_renderer e mode in
      let e = E3.update e frame in
      check (E3.renderer e = mode) "the shared renderer did not switch";
      e)
    ~view:E3.scene
    ~after_present:(fun e (frame : Frame.t) ->
      if List.mem frame.count [5; 15; 35; 45] then begin
        let path = Filename.concat directory (Printf.sprintf "%d.png" frame.count) in
        check (Canvas.save_screen_png path = Ok ()) "renderer screenshot failed";
        samples := path :: !samples
      end;
      E3.after_present e frame)
    ~on_stop:E3.close ());
  let red_pixels path =
    let image = Image.load_exn path in
    let pixels = Image.Private.pixels image |> Result.get_ok in
    let w = Image.get_width image and h = Image.get_height image in
    let scale = float w /. 900. in
    let counts = Array.make 2 0 in
    Array.iteri (fun i (x, y, width, height) ->
      for py = int_of_float (float y *. scale) to min (h - 1) (int_of_float (float (y + height) *. scale) - 1) do
        for px = int_of_float (float x *. scale) to min (w - 1) (int_of_float (float (x + width) *. scale) - 1) do
          let offset = 4 * (py * w + px) in
          let r = Char.code (Bytes.get pixels offset) and g = Char.code (Bytes.get pixels (offset + 1)) in
          if r > 110 && r > g + 40 then counts.(i) <- counts.(i) + 1
        done
      done) [|(0, 50, 440, 450); (450, 142, 320, 258)|];
    Image.destroy image; counts in
  List.iter (fun frame ->
    let counts = red_pixels (Filename.concat directory (Printf.sprintf "%d.png" frame)) in
    check (counts.(0) > 30 && counts.(1) > 30)
      (Printf.sprintf "renderer frame %d missed a docked or floating viewport (%d, %d)" frame counts.(0) counts.(1))) [5; 35; 45];
  let wire = red_pixels (Filename.concat directory "15.png") in
  check (wire.(0) < 30 && wire.(1) < 30)
    (Printf.sprintf "wireframe still painted filled faces (%d, %d)" wire.(0) wire.(1));
  List.iter Sys.remove !samples;
  let state = Filename.concat directory "presets/state" in
  if Sys.file_exists state then begin Array.iter (fun name -> Sys.remove (Filename.concat state name)) (Sys.readdir state);
    Unix.rmdir state; Unix.rmdir (Filename.dirname state) end;
  Unix.rmdir directory

let run_native () =
  let directory = Filename.temp_dir "prismel-variations" "" in
  let path = match Sys.getenv_opt "PRISMEL_SHELL_PNG" with Some p -> p | None -> Filename.concat directory "variations.png" in
  let frames = 80 in
  let rects = ref [] in
  ignore (Sketch.run_state ~max_frames:frames
    ~config:{ Sketch.default_config with width = 900; height = 640; title = "variations" }
    ~init:(fun _ -> editor (case "variations"))
    ~update:(fun e (frame : Frame.t) -> Unix.sleepf 0.004; E3.update e frame)
    ~view:E3.scene
    ~after_present:(fun e (frame : Frame.t) ->
      if frame.count = frames then begin
        let tree = (shell_of (build_ok (E3.workspace e))).tree in
        rects := List.filter_map (fun (l : Layout.leaf) -> match l.panel with
          | Layout.View _ -> let x, y, w, h = l.body in Some (x, y, w, h, frame.width)
          | _ -> None) (Layout.geometry ~hidden:[ Layout.Timeline ] tree frame).leaves;
        check (Canvas.save_screen_png path = Ok ()) "the window did not save its screen"
      end;
      E3.after_present e frame)
    ~on_stop:E3.close ());
  let image = Image.load_exn path in
  let pixels = Result.get_ok (Image.Private.pixels image) in
  let scale = float (Image.get_width image) /. float (match !rects with (_, _, _, _, w) :: _ -> w | [] -> fail "no viewports") in
  check (List.length !rects = 4) "four viewport panels";
  let drawn (x, y, w, h, _) =
    let count = ref 0 and bits = Buffer.create 64 in
    for py = int_of_float (float y *. scale) to int_of_float (float (y + h) *. scale) - 1 do
      for px = int_of_float (float x *. scale) to int_of_float (float (x + w) *. scale) - 1 do
        let o = 4 * ((py * Image.get_width image) + px) in
        let r = Char.code (Bytes.get pixels o) and g = Char.code (Bytes.get pixels (o + 1))
        and b = Char.code (Bytes.get pixels (o + 2)) in
        let hit = r < 110 && g < 110 && b < 110 in  (* the unlit garden against the pale panel *)
        if hit then incr count;
        Buffer.add_char bits (if hit then '1' else '0')
      done
    done;
    !count, Digest.string (Buffer.contents bits) in
  let regions = List.map drawn !rects in
  List.iteri (fun i (count, _) -> check (count > 30) (Printf.sprintf "viewport %d drew nothing (%d dark pixels)" i count)) regions;
  check (List.length (List.sort_uniq compare (List.map snd regions)) = 4) "each viewport shows its own seed's garden";
  if Sys.getenv_opt "PRISMEL_SHELL_PNG" = None then Sys.remove path;
  Unix.rmdir directory;
  run_renderers_native ();
  run_renderers_native ~authored:true ()
