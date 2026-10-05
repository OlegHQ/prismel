(* W10 part B: the editor graph lowers to the shell tree; viewports over other
   instances of the scene get objects of their own; layout gestures are edits of
   the editor graph with history entries; "Restore layout" survives a layout that
   hides everything. *)
open Rays
open Procedural
module Doc = Editor_document.Workspace_doc
module Document = Editor_document.Document
module Contexts = Editor_document.Contexts
module Panels = Editor_core.Panels
module Layout = Pxui_shell.Layout
module E = Flow_sop.Flow_edit
module S = Flow.Syntax
module E3 = Rays_editor.Editor3

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
   | Split { size = `Ratio ratio; b = Split { size = `Ratio inner; a = Split { size = `Ratio left; _ }; _ }; _ } ->
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
  check ((shell_of named).named = [ [ 0 ], "scene" ]) "ui/graph names its graph";
  check (Panels.to_string (shell_of named).tree = "(v graph view)") "ui/split is an even split";
  (match (shell_of named).tree with Split { size = `Ratio ratio; _ } -> check (ratio = 0.5) "ui/split halves" | _ -> fail "split");
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
    ~prepare:(fun _ output -> Rdk_rays.Rays_mesh.to_mesh output.Procedural.Session.geometry
      |> Result.map_error Rdk.Error.to_string)
    ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) ()
  |> function Ok e -> e | Error m -> fail m

let source e = fst (Flow.Lisp.print (E3.workspace e).Doc.source)

let dump_line e key =
  let directory = Filename.temp_dir "rays-shell-dump" "" in
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
  check (has (source !e) "(ui/split-at \"horizontal\" 0.3333 outline right)") ("the drag rewrote the outline split: " ^ source !e);
  check (E3.undo_label !e = Some "Resize panel") "one history entry named Resize panel";
  (* the header menu of the graph panel: split side by side *)
  let hx = 400. in
  click ~button:Input.RightButton (hx, 10.);
  step [];
  click (340., 37.);
  step [];
  check (E3.undo_label !e = Some "Split panel") ("the menu split the graph panel: " ^ Option.value ~default:"-" (E3.undo_label !e));
  check (has (source !e) "network_a" && has (source !e) "network_b") "the split bound two new panels";
  (* a panel made by a loop cannot be split: the status says where it comes from *)
  let geometry = Layout.geometry ~hidden:[ Layout.Timeline ] (shell_of (build_ok (E3.workspace !e)))
      .tree (frame (0., 0.) [] 0) in
  let leaf = Option.get (Layout.find geometry (Layout.View "v1.1.2")) in
  let hx, hy, hw, _ = leaf.header in
  let depth = E3.undo_label !e in
  click ~button:Input.RightButton (float (hx + (hw / 2)), float (hy + 10));
  step [];
  click (float (hx + 30), float (hy + 24 + 6 + 12));
  step [];
  check (E3.undo_label !e = depth) "a looped panel did not change the graph";
  settle ();
  check (has (dump_line !e "cook") "made by a loop in sheet") ("the status names the loop: " ^ dump_line !e "cook" ^ " / " ^ dump_line !e "edit error");
  (* focus is a panel: a press in a panel focuses it *)
  let focus_after (x, y) =
    click (x, y); step []; dump_line !e "focus" in
  check (focus_after (30., 300.) = "Outline") "a press in the outline focuses it";
  check (focus_after (float (hx + 30), float (hy + 100)) = "View") "a press in a viewport focuses a viewport";
  E3.close !e

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
  E3.close e;
  let e = add "str" in
  check (has (source e) "(str \"text\")") ("a str binding: " ^ source e);
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
  check (E3.undo_label !e = Some "View node")
    ("v did not view the node: " ^ Option.value ~default:"-" (E3.undo_label !e));
  check (not (has (fst (Flow.Lisp.print [ Editor_document.Layout_by_path.to_syntax (E3.workspace !e).Doc.layout ])) "(display"))
    "the viewed node is not saved in the layout";
  step ~mouse:p [];
  check (Node.operation (E3.displayed_node !e) = "box" && centre () = Some 0.)
    ("v marked the node but did not show it in the viewport: " ^ node);
  step ~mouse:p ~keys:[ Input.Meta ] [ Event.KeyPressed (Input.KeyChar 'z') ];
  step ~mouse:p [];
  check (centre () = Some 20.) "undo did not restore the graph result";
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
      (let* [a (sop/box) b (sop/transform a :translate [5 0 0])
             result (sop/transform b :translate [15 0 0])]
        result))
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
    select "result"; key (Input.KeyChar 'v'); step [];
    check (Editor_document.Layout_by_path.Path_map.is_empty (E3.workspace !e).layout.display) "layout.display is cleared";
    centre 20.;
    edit (E.Set_arg {node = ["g"; "b"]; key = E.Kw "translate"; sub = []; value = parsed "[9 0 0]"});
    centre 24.;
    edit (E.Set_arg {node = ["g"; "result"]; key = E.Kw "translate"; sub = []; value = parsed "[30 0 0]"});
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
    centre 11.;
    click (float (gx + 40), float (gy + 40));
    key (Input.KeyChar 'i'); step [];
    select "result"; key (Input.KeyChar 'v'); step []; centre 41.)

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
    "the frame is in the layout";
  E3.close !e

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
  let r = ok "Resize panel" (E.Set_layout_size { node = [ "editor"; "left" ]; size = `Ratio 0.3 }) in
  check (has (source r) "(ui/split-at \"vertical\" 0.3 network code)") "Set_layout_ratio";
  check (match (tree (ok "Resize panel" (E.Set_layout_size { node = [ "editor"; "left" ]; size = `Ratio 5. }))) with
      | Split { b = Split { a = Split { size; _ }; _ }; _ } -> size = `Ratio 0.9 | _ -> false) "a ratio clamps to 0.9";
  (* a ui/split (no ratio) becomes ui/split-at *)
  let plain = editor (with_editor "    (let* [a (ui/graph) b (ui/lisp) s (ui/split \"horizontal\" a b)] (ui/workspace s))") in
  (match E3.edit plain (E.Set_layout_size { node = [ "editor"; "s" ]; size = `Ratio 0.25 }) with
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
  check (has (source docked) "(ui/split-at \"horizontal\" 0.5 outline network)")
    "docking was not reflected in the editor Lisp";
  (* undo restores the tree with the source *)
  check (Panels.to_string (tree e) = Panels.to_string sh) "undo target";
  (* refusals leave everything alone *)
  let refuse name op needle = match E3.edit e op with
    | Error m -> check (has m needle) (name ^ ": " ^ m)
    | Ok _ -> fail (name ^ " was accepted") in
  refuse "close outside a split" (E.Close_panel { node = [ "editor"; "shell" ] }) "inside a split";
  refuse "an unknown panel type" (E.Set_panel_kind { node = [ "editor"; "network" ]; kind = "dashboard" }) "Unknown panel type";
  refuse "resize a panel" (E.Set_layout_size { node = [ "editor"; "network" ]; size = `Ratio 0.4 }) "not a split";
  refuse "no such binding" (E.Split_panel { node = [ "editor"; "nothing" ]; axis = `H }) "no longer exists";
  E3.close plain; E3.close e

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
  check (panes_graph !e = 0) "the second Space z returns to the editor graph";
  E3.close !e

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
  let geometry () = Layout.geometry ~hidden:[ Layout.Timeline ] (shell_of (build_ok (E3.workspace !e))).tree
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
    let geometry = Layout.geometry ~hidden:[ Layout.Timeline ] (shell_of (build_ok (E3.workspace !e))).tree
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

(* two roots, two Worlds, two viewports: the editor composes and draws a view for each *)
let run_instances () =
  let text = {|(workspace days
  (graph g :context sop (sop/box))
  (graph noon :context world (world/sun (world/sky :name "noon") :name "sun"))
  (graph dusk :context world (world/sun (world/sky :name "dusk") :name "sun"))
  (graph set :context scene
    (scene/merge (scene/geometry (ref g) :name "body") (scene/camera :name "hero")))
  (graph day :context scene
    (scene/root (scene/merge (ref set) (scene/world (ref noon) :name "Noon")) :renderer "Raster"))
  (graph night :context scene
    (scene/root (scene/merge (ref set) (scene/world (ref dusk) :name "Dusk" :exposure -2))
                :renderer "Path traced" :max_spp 1024 :bounces 12))
  (graph editor :context editor
    (ui/workspace (ui/split-at "horizontal" 0.5 (ui/viewport (ref day)) (ui/viewport (ref night))))))|} in
  let e = ref (editor text) in
  for c = 1 to 12 do e := E3.update !e (frame (450., 300.) [] c) done;
  check (List.length (E3.objects !e) >= 1 && Option.is_some (E3.prepared !e))
    (Printf.sprintf "the editor did not cook (cook %s)" (dump_line !e "cook"));
  check (not (has (dump_line !e "edit error") "Failure")) ("an error composing the views: " ^ dump_line !e "edit error");
  E3.close !e

(* the frame draws one 3D layer per viewport, each over its own scene instance *)
let run_views () =
  let e = ref (editor (case "variations")) in
  for c = 1 to 12 do e := E3.update !e (frame (450., 300.) [] c) done;
  check (List.length (E3.objects !e) >= 1 && Option.is_some (E3.prepared !e))
    (Printf.sprintf "the editor did not cook (%d objects, prepared %b, cook %s)" (List.length (E3.objects !e))
       (Option.is_some (E3.prepared !e)) (dump_line !e "cook"));
  for c = 200 to 230 do e := E3.update !e (frame (450., 300.) [] c) done;
  let scene = E3.scene !e (frame (450., 300.) [] 231) in
  E3.close !e;
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

(* With RAYS_UI_PREVIEW=<dir> the editor is drawn into <dir>/<name>.png, without a window: the
   picture a pointer position in these tests is read off. *)
let preview e name = match Sys.getenv_opt "RAYS_UI_PREVIEW" with
  | None -> ()
  | Some directory ->
      let canvas = Rays.Canvas.create_exn ~width:900 ~height:640 in
      Rays.Canvas.render canvas (E3.scene !e (frame (0., 0.) [] 0));
      ignore (Rays.Canvas.save_png canvas (Filename.concat directory (name ^ ".png")));
      Rays.Canvas.destroy canvas

(* a drag across the inspector's slider at [row] points under the panel's top *)
let drag_slider e count row =
  let step ?(buttons = []) ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame ~buttons mouse events !count) in
  let ix, iy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).inspector in
  (* the first field of a vector row starts at the control column: 12 + 6 + 8 + 56 + 8 = 90 in a
     180-wide panel; a point 10 inside it *)
  let at x = float (ix + 100 + x), float (iy + row) in
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
  preview e "loop-copies";
  let x () = List.map (fun i -> field_of i "translate_x") (objects !e) in
  check (List.length (objects !e) = 3 && List.for_all (fun v -> v = Some (Parameter.Float_value 0.)) (x ()))
    "the loop did not make three objects at the origin";
  (* the head is 118 tall at the test's 11 points, then Inputs (4 + 24, 24) and Transform (16 + 24):
     the translate row is 118 + 28 + 24 + 40 = 210 down, its middle 12 more *)
  drag_slider e count 222;
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
  preview e "loop-light";
  drag_slider e count 249;
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
  (* Option-click on the translate X field of the lamp: its row is 12 + 6 + 8 + 56 + 8 = 90 from
     the panel's left; vertically the head (118), Inputs (28, 24), Type (24), Transform (40) and
     half the translate row (12) above it, as in the preview *)
  let label = float (ix + 100), float (iy + 118 + 28 + 24 + 24 + 40 + 12) in
  step ~mouse:label [ Event.MouseMoved label ];
  let alt ?(buttons = []) events = incr count;
    e := E3.update !e (Test_editor_input.frame ~buttons ~keys:[ Input.Alt ] label events !count) in
  alt [ Event.MousePressed (Input.LeftButton, label) ] ~buttons:[ Input.LeftButton ];
  alt [ Event.MouseReleased (Input.LeftButton, label) ];
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
  let directory = Filename.temp_dir "rays-panel-state" "" in
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
  let before_split = Doc.to_text (E3.workspace !e) in
  step grip [Event.MouseMoved grip];
  step ~buttons:[Input.LeftButton] grip [Event.MousePressed (Input.LeftButton, grip)];
  step ~buttons:[Input.LeftButton] moved [Event.MouseMoved moved];
  check (Doc.to_text (E3.workspace !e) = before_split && E3.undo_label !e = None)
    "a held splitter drag committed authored state before release";
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
  click (889., 11.);
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
  let before_move = Doc.to_text (E3.workspace !e) in
  let before_bounds = (E3.panes !e (frame (0., 0.) [] 0)).graph in
  step grip [Event.MouseMoved grip];
  step ~buttons:[Input.LeftButton] grip [Event.MousePressed (Input.LeftButton, grip)];
  step ~buttons:[Input.LeftButton] to_ [Event.MouseMoved to_];
  check (Doc.to_text (E3.workspace !e) = before_move)
    "a held floating-window drag committed authored state before release";
  step to_ [Event.PointerCancelled Input.LeftButton];
  check (Doc.to_text (E3.workspace !e) = before_move
    && (E3.panes !e (frame (0., 0.) [] 0)).graph = before_bounds)
    "cancelling a floating-window drag retained draft bounds or changed authored state";
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
  let before_resize = Doc.to_text (E3.workspace !e) in
  step corner [Event.MouseMoved corner];
  step ~buttons:[Input.LeftButton] corner [Event.MousePressed (Input.LeftButton, corner)];
  step ~buttons:[Input.LeftButton] to_ [Event.MouseMoved to_];
  check (Doc.to_text (E3.workspace !e) = before_resize)
    "a held floating-window resize committed authored state before release";
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
  check (has (source !e) "preview network)" && (state "network").window = None
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
  e := E3.set_renderer !e Rays_editor.Renderer.Wireframe;
  step target [];
  check (E3.renderer !e = Rays_editor.Renderer.Wireframe && Option.equal ( == ) (E3.prepared !e) prepared)
    "the shared wireframe choice recooked the geometry";
  e := E3.set_renderer !e Rays_editor.Renderer.Raster;
  step target [];
  check (E3.renderer !e = Rays_editor.Renderer.Raster && Option.equal ( == ) (E3.prepared !e) prepared)
    "the shared raster choice recooked the geometry";
  E3.close !e;
  Array.iter (fun name -> let path = Filename.concat directory name in
    if Sys.is_directory path then begin
      Array.iter (fun name -> Sys.remove (Filename.concat path name)) (Sys.readdir path); Unix.rmdir path
    end else Sys.remove path) (Sys.readdir directory);
  Unix.rmdir directory

let run_ref_picker () =
  let text = {|(workspace ref_pick
    (graph scene :context scene
      (let* [geom (scene/geometry (ref g1))]
        (scene/merge geom)))
    (graph g1 :context sop (sop/box))
    (graph g2 :context sop (sop/grid))
    (graph editor :context editor
      (ui/workspace (ui/split "horizontal" (ui/graph "scene") (ui/inspector)))))|} in
  let e = ref (editor text) and count = ref 0 in
  let step ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
  step []; step [];
  let ix, iy, _, _ = (E3.panes !e (frame (0., 0.) [] 0)).inspector in
  let click point =
    step ~mouse:point [ Event.MouseMoved point ];
    step ~mouse:point [ Event.MousePressed (Input.LeftButton, point); Event.MouseReleased (Input.LeftButton, point) ] in
  let bx, by, _, _ = Option.get (E3.node_box !e [ "scene"; "geom" ]) in
  let node_pt = float (bx + 60), float (by + 12) in
  click node_pt;
  step [];
  check (dump_line !e "scope selected" = "scene/geom") ("the scene geometry node was not selected, got: " ^ dump_line !e "scope selected");
  preview e "ref-picker";
  let btn = float (ix + 180), float (iy + 190) in
  click btn;
  step [];
  preview e "ref-picker-open";
  let opt = float (ix + 180), float (iy + 245) in
  click opt;
  step [];
  check (has (source !e) "(ref g2)") ("inspector ref picker did not change ref to g2: " ^ source !e);
  e := E3.update !e { (frame (450., 300.) [ Event.KeyPressed (Input.KeyChar 'z') ] (incr count; !count)) with keys = [ Input.Meta ] };
  step [];
  check (has (source !e) "(ref g1)") ("undo did not restore ref to g1: " ^ source !e);
  E3.close !e

(* Space a on a scene graph: World, Merge and Geometry are one gesture each, one undo entry *)
let run_compose () =
  let text = {|(workspace compose
    (graph g1 :context sop (sop/box))
    (graph scene :context scene
      (let* [a (scene/geometry (ref g1))
             b (scene/geometry (ref g1) :translate [3 0 0] :name "b")]
        (scene/root (scene/merge a b))))
    (graph editor :context editor (ui/workspace (ui/split "horizontal" (ui/graph "scene") (ui/inspector)))))|} in
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  let pick typed =
    let e = ref (editor text) and count = ref 0 in
    let step ?(keys = []) events = incr count; e := E3.update !e (Test_editor_input.frame ~keys (450., 300.) events !count) in
    step []; step [];
    let before = source !e in
    step [ key Input.Space; ch 'a' ]; step [ Event.TextInput typed ]; step [ key Input.Enter ]; step [];
    let after = source !e and label = E3.undo_label !e in
    step ~keys:[ Input.Meta ] [ ch 'z' ]; step [];
    let undone = source !e in
    E3.close !e;
    before, after, label, undone in
  let flat t = String.concat " " (List.filter (( <> ) "") (String.split_on_char ' '
    (String.map (function '\n' -> ' ' | c -> c) t))) in
  let before, after, label, undone = pick "World" in
  check (has (flat after) "(scene/world (ref sky))" && has (flat after) "(graph sky :context world" && label = Some "Add World"
         && undone = before) ("Space a World: " ^ after);
  let before, after, label, undone = pick "Geometry" in
  check (has (flat after) "(graph shape :context sop" && has (flat after) "(scene/geometry (ref shape))"
         && label = Some "Add geometry" && undone = before) ("Space a Geometry: " ^ after);
  let before, after, label, undone = pick "Merge" in
  check (has (flat after) "(scene/merge)" && undone = before && label <> None) ("Space a Merge: " ^ after);
  (* Space e selects the scene's World, a merge member, and enters it *)
  let e = ref (editor {|(workspace sky
    (graph g1 :context sop (sop/box))
    (graph sky :context world (world/sun (world/sky)))
    (graph scene :context scene
      (scene/root (scene/merge (scene/geometry (ref g1)) (scene/world (ref sky) :name "Dome")))))|}) and count = ref 0 in
  let step events = incr count; e := E3.update !e (frame (450., 300.) events !count) in
  step []; step [];
  step [ key Input.Space; ch 'e' ]; step [];
  check (E3.level !e = Some "Dome" && not (has (source !e) "graph world"))
    "Space e did not enter the World of a scene/world member";
  E3.close !e;
  (* Space e on a scene with a root and no World makes one: a member of the merge and a world graph *)
  let e = ref (editor {|(workspace plain
    (graph g1 :context sop (sop/box))
    (graph scene :context scene (scene/root (scene/merge (scene/geometry (ref g1))))))|}) and count = ref 0 in
  let step events = incr count; e := E3.update !e (frame (450., 300.) events !count) in
  step []; step [];
  step [ key Input.Space; ch 'e' ]; step [];
  check (has (flat (source !e)) "(scene/world (ref world)" && has (source !e) "graph world :context world"
         && has (source !e) "scene/root" && E3.undo_label !e = Some "Add World")
    ("Space e did not write the new World: " ^ source !e);
  E3.close !e;
  print_endline "workspace shell: Space a adds World, Geometry (with its SOP graph) and Merge, one undo entry each; Space e enters a World member"

(* A switch holds the layouts of one editor graph: lowering, the names read from the panels, the
   edits, one merged undo entry, and the keys. *)
let switch_text = {|
  (workspace sw
    (graph g :context sop (sop/box))
    (graph scene :context scene
      (scene/merge (scene/geometry (ref g)) (scene/camera :eye [0 0 6])))
    (graph editor :context editor
      (let* [preview (ui/viewport (ref scene))
             network (ui/graph)
             inspector (ui/inspector)
             code (ui/lisp)
             build (ui/split-at "horizontal" 0.4 preview (ui/split-at "horizontal" 0.62 network inspector))
             write (ui/split-at "horizontal" 0.46 preview (ui/split-at "vertical" 0.5 network code))
             look preview]
        (ui/workspace (ui/switch build write look :active 0)))))
|}

let run_layouts () =
  let labels text = match (shell_of (build_ok (of_text text))).switch with
    | Some sw -> Panels.labels sw.layouts, sw.active | None -> fail "no switch" in
  check (labels switch_text = ([ "View | Graph | Inspector"; "View | Graph / Lisp"; "View" ], 0))
    "the layouts are named from their panels";
  let shell = shell_of (build_ok (of_text switch_text)) in
  check (Panels.to_string shell.tree = "(h view (h graph inspector))" && shell.origins <> []
         && List.assoc_opt [] shell.origins = Some (Document.Bound "build"))
    "the active layout is the tree, its origin the binding the switch names";
  let shell = shell_of (build_ok (of_text (replace switch_text ":active 0" ":active 1"))) in
  check (Panels.to_string shell.tree = "(h view (v graph lisp))") "the switch is transparent: :active picks the tree";
  expect_error "an active layout out of range" (replace switch_text ":active 0" ":active 3") "active layout";
  (* a switch inside a split swaps one column *)
  let inner = build_ok (of_text (with_editor "    (ui/workspace (ui/split-at \"horizontal\" 0.5 (ui/graph) (ui/switch (ui/lisp) (ui/inspector) :active 1)))")) in
  check (Panels.to_string (shell_of inner).tree = "(h graph inspector)") "a switch inside a split";
  (* edits *)
  let ws = of_text switch_text in
  let edit ws op = match Doc.edit catalog ws op with Ok ws -> ws | Error d -> fail (Flow.Diagnostic.to_string d) in
  let text ws = fst (Flow.Lisp.print ws.Doc.source) in
  let switched = edit ws (E.Set_layout { graph = "editor"; index = 2 }) in
  check (has (text switched) ":active 2") "Set_layout writes :active";
  let added = edit switched (E.Layout_new { graph = "editor" }) in
  check (has (text added) "(ui/switch build write look layout :active 3)" && has (text added) "layout preview")
    ("a new layout copies the active one: " ^ text added);
  let labelled = labels (text added) in
  check (labelled = ([ "View | Graph | Inspector"; "View | Graph / Lisp"; "View"; "View \xc2\xb7 View 100% (1)"; ], 3)
         || fst labelled = [ "View | Graph | Inspector"; "View | Graph / Lisp"; "View \xc2\xb7 View 100%"; "View \xc2\xb7 View 100% (2)" ])
    ("the copy is named like its twin: " ^ String.concat " / " (fst labelled));
  let removed = edit added (E.Layout_remove { graph = "editor" }) in
  check (has (text removed) "(ui/switch build write look :active" && not (has (text removed) "layout preview"))
    ("removing the current layout drops its input and binding: " ^ text removed);
  let one = edit (edit (edit removed (E.Set_layout { graph = "editor"; index = 0 })) (E.Layout_remove { graph = "editor" }))
      (E.Layout_remove { graph = "editor" }) in
  (match Doc.edit catalog one (E.Layout_remove { graph = "editor" }) with
   | Error d -> check (has d.Flow.Diagnostic.message "last layout") "the last layout stays"
   | Ok _ -> fail "removed the last layout");
  (* a window joins the active layout only; it floats and docks *)
  let windowed = edit ws (E.Layout_window { graph = "editor"; kind = "inspector" }) in
  check (has (text windowed) "(ui/floating (ui/inspector))") "a new window";
  check (Panels.label (shell_of (build_ok windowed)).tree = "View | Graph | Inspector + Inspector"
         && labels (text windowed) |> fst |> List.tl = [ "View | Graph / Lisp"; "View" ])
    "the window shows in the active layout's name only";
  let floated = edit ws (E.Layout_float { graph = "editor"; at = [ 1; 0 ] }) in
  check (Panels.label (shell_of (build_ok floated)).tree = "View | Inspector + Graph") ("a panel floats: " ^ text floated);
  let docked = edit floated (E.Layout_float { graph = "editor"; at = [ 1; 0 ] }) in
  check (Panels.label (shell_of (build_ok docked)).tree = "View | Inspector | Graph") ("a window docks: " ^ text docked);
  (* a switch inside a split edits in place *)
  let nested = of_text (with_editor "    (ui/workspace (ui/split-at \"horizontal\" 0.5 (ui/graph) (ui/switch (ui/lisp) (ui/inspector) :active 1)))") in
  let n_set = edit nested (E.Set_layout { graph = "editor"; index = 0 }) in
  check (has (text n_set) "(ui/switch (ui/lisp) (ui/inspector) :active 0)" || has (text n_set) ":active 0")
    ("Set_layout reaches a switch inside a split: " ^ text n_set);
  check (Panels.to_string (shell_of (build_ok n_set)).tree = "(h graph lisp)") "and the column swaps";
  let n_new = edit nested (E.Layout_new { graph = "editor" }) in
  check (Panels.to_string (shell_of (build_ok n_new)).tree = "(h graph inspector)"
         && (match (shell_of (build_ok n_new)).switch with Some sw -> List.length sw.layouts = 3 | None -> false))
    ("a new layout joins the nested switch: " ^ text n_new);
  (* an older file: several editor graphs become the layouts of one switch *)
  let old_text =
    let t = with_editor "    (let* [a (ui/graph) b (ui/lisp) s (ui/split \"horizontal\" a b)] (ui/workspace s))" in
    String.sub t 0 (String.length t - 2)
    ^ "\n  (graph second :context editor\n    (let* [a (ui/lisp) b (ui/inspector) s (ui/split \"vertical\" a b)] (ui/workspace s))))\n" in
  let old = of_text old_text in
  let merged = edit old (E.Merge_layouts { graph = "editor" }) in
  check (not (has (text merged) "(graph second") && has (text merged) "second_a" && has (text merged) "(ui/switch")
    ("the other editor graph joins the switch: " ^ text merged);
  (match (shell_of (build_ok merged)).switch with
   | Some sw -> check (List.length sw.layouts = 2 && List.map Panels.label sw.layouts = [ "Graph | Lisp"; "Lisp / Inspector" ])
       ("the merged layouts: " ^ String.concat " / " (List.map Panels.label sw.layouts))
   | None -> fail "no switch after merging");
  (match Doc.edit catalog merged (E.Merge_layouts { graph = "editor" }) with
   | Error _ -> () | Ok _ -> fail "merged with nothing to merge");
  (* a workspace without a switch gets one on the first new layout *)
  let plain = of_text (replace (replace switch_text "(ui/switch build write look :active 0)" "build") "write (" "write (") in
  let wrapped = edit plain (E.Layout_new { graph = "editor" }) in
  check (has (text wrapped) "(ui/workspace switch)" && has (text wrapped) "(ui/switch build layout :active 1)")
    ("a switch is written around the tree: " ^ text wrapped);
  (* one merged undo entry, by keys *)
  let e = ref (editor switch_text) and count = ref 0 in
  let step ?(keys = []) events = incr count; e := E3.update !e (Test_editor_input.frame ~keys (300., 150.) events !count) in
  step []; step [];
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  step [ key Input.Space; ch '[' ]; step [];  (* which-key lists the layouts *)
  step [ ch '1' ]; step [];
  check (has (source !e) ":active 1" && E3.undo_label !e = Some "Layout") "Space [ 1 switches the layout";
  step [ key Input.Space; ch '['; ch '2' ]; step [];
  check (has (source !e) ":active 2") "Space [ 2 switches again";
  step ~keys:[ Input.Meta ] [ ch 'z' ]; step [];
  check (has (source !e) ":active 0") "one undo returns past both switches";
  step [ key Input.Space; ch '['; ch 'n' ]; step [];
  check (has (source !e) ":active 3" && E3.undo_label !e = Some "New layout") "Space [ n copies the layout";
  step [ key Input.Space; ch '['; ch 'x' ]; step [];
  check (E3.undo_label !e = Some "Remove layout" && not (has (source !e) "layout preview")) "Space [ x removes it";
  step [ key Input.Space; ch 'n'; ch 'i' ]; step [];
  check (has (source !e) "(ui/floating (ui/inspector))" && E3.undo_label !e = Some "New window") "Space n i opens an inspector window";
  (* the layout's one docked panel cannot float: refused, nothing written, the entry stays *)
  let before = source !e in
  step [ key Input.Space; ch 'o'; ch 'f' ]; step [];
  check (E3.undo_label !e = Some "New window" && source !e = before)
    ("Space o f on a layout's only docked panel is refused: " ^ Option.value ~default:"-" (E3.undo_label !e));
  (* in a layout of several panels the focused one floats, as one entry named Float panel *)
  step [ key Input.Space; ch '['; ch '0' ]; step [];
  let gx, gy, gw, gh = (E3.panes !e (Test_editor_input.frame (0., 0.) [] !count)).graph in
  let at = (float gx +. float gw /. 2., float gy +. float gh /. 2.) in
  let press events = incr count; e := E3.update !e (Test_editor_input.frame at events !count) in
  press [ Event.MouseMoved at ]; press [ Event.MousePressed (Input.LeftButton, at) ];
  press [ Event.MouseReleased (Input.LeftButton, at) ]; press [];
  press [ key Input.Space; ch 'o'; ch 'f' ]; press [];
  check (E3.undo_label !e = Some "Float panel" && has (source !e) "(ui/floating")
    ("Space o f floats the focused panel: " ^ Option.value ~default:"-" (E3.undo_label !e) ^ "\n" ^ source !e)

(* The inspector with nothing selected has a Scene root section over the root's settings: a press
   on one of its controls writes the root in the text as one "Render settings" entry. *)
let run_root_section () =
  let e = ref (editor {|(workspace studio
  (graph g :context sop (sop/box))
  (graph scene :context scene
    (let* [body (scene/geometry (ref g) :name "body")
           all (scene/merge body)]
      (scene/root all :renderer "Raster" :width 800 :height 600 :max_spp 64))))|}) and count = ref 0 in
  let step ?(mouse = (450., 300.)) events = incr count; e := E3.update !e (frame mouse events !count) in
  for _ = 1 to 6 do step [] done;
  let before = E3.workspace !e in
  check (E3.undo_label !e = None && has (source !e) ":width 800") "the root is in the text, nothing to undo";
  let ix, iy, iw, ih = (E3.panes !e (frame (0., 0.) [] !count)).inspector in
  check (iw > 0 && ih > 0) "the inspector panel is showing";
  (* the Renderer row of the Scene root section: the header (85 points at the test's 11-point
     text), the live-update switch, the Viewport section and its four switches, then the Camera,
     Render and Scene root section headers.  A press opens its menu under the field; the second
     row of the menu is Wireframe. *)
  let hit = ref None in
  let row = iy + 85 + 24 + 40 + 96 + 40 + 24 + 24 in
  let press at =
    step ~mouse:at [ Event.MouseMoved at ];
    step ~mouse:at [ Event.MousePressed (Input.LeftButton, at); Event.MouseReleased (Input.LeftButton, at) ];
    step ~mouse:at [] in
  let x = float (ix + (iw * 3 / 4)) in
  press (x, float (row + 12));
  press (x, float (row + 22 + 6 + 24 + 12));
  if E3.undo_label !e = Some "Render settings" then hit := Some row;
  check (!hit <> None) "no control of the inspector wrote the root";
  check (E3.workspace !e != before && has (source !e) "(scene/root all") "the root stayed in the text, edited";
  incr count;
  e := E3.update !e (Test_editor_input.frame ~keys:[ Input.Meta ] (450., 300.) [ Event.KeyPressed (Input.KeyChar 'z') ] !count);
  check (E3.workspace !e == before) "one undo returns the root";
  E3.close !e

(* b on a scene object takes it out of the render without removing it (:visible), Alt-Down moves a
   merge's input, and each gesture prints what it wrote in the status strip. *)
let run_hide_and_order () =
  let text = {|(workspace hide
    (graph g1 :context sop (sop/box))
    (graph scene :context scene
      (let* [a (scene/geometry (ref g1) :name "a")
             b (scene/geometry (ref g1) :translate [3 0 0] :name "b")
             all (scene/merge a b)]
        (scene/root all)))
    (graph editor :context editor (ui/workspace (ui/split "horizontal" (ui/graph "scene") (ui/inspector)))))|} in
  let e = ref (editor text) and count = ref 0 in
  let step ?(keys = []) ?(mouse = (450., 300.)) events =
    incr count; e := E3.update !e (Test_editor_input.frame ~keys mouse events !count) in
  let key k = Event.KeyPressed k and ch c = Event.KeyPressed (Input.KeyChar c) in
  step []; step [];
  let click path =
    let bx, by, bw, bh = Option.get (E3.node_box !e path) in
    let at = float bx +. float bw /. 2., float by +. float bh -. 6. in
    step ~mouse:at [ Event.MouseMoved at ];
    step ~mouse:at [ Event.MousePressed (Input.LeftButton, at) ];
    step ~mouse:at [ Event.MouseReleased (Input.LeftButton, at) ]; step ~mouse:at [] in
  click [ "scene"; "a" ];
  step [ ch 'b' ]; step [];
  check (has (source !e) "(scene/geometry (ref g1) :name \"a\" :visible false)" && E3.undo_label !e = Some "Edit value")
    ("b wrote :visible false on the object: " ^ source !e);
  check (has (dump_line !e "cook") "Wrote :visible false on scene/a")
    ("the strip says what was written: " ^ dump_line !e "cook");
  step [ ch 'b' ]; step [];
  check (has (source !e) ":visible true") ("b again shows it: " ^ source !e);
  step ~keys:[ Input.Meta ] [ ch 'z' ]; step ~keys:[ Input.Meta ] [ ch 'z' ]; step [];
  check (not (has (source !e) ":visible")) "two undos give the text back";
  (* Alt-Down on a hovered merge input swaps it with the next *)
  let bx, by, bw, bh = Option.get (E3.node_box !e [ "scene"; "all" ]) in
  click [ "scene"; "all" ];
  let moved = ref false in
  let y = ref (by + 4) in
  while not !moved && !y < by + bh do
    let at = float (bx + bw / 2), float !y in
    step ~mouse:at [ Event.MouseMoved at ];
    step ~keys:[ Input.Alt ] ~mouse:at [ key Input.ArrowDown ]; step ~mouse:at [];
    if has (source !e) "(scene/merge b a)" then moved := true;
    y := !y + 3
  done;
  check !moved ("Alt-Down moved a merge input: " ^ source !e);
  check (E3.undo_label !e = Some "Move item") "one entry named Move item";
  E3.close !e

(* The palette's "Copy workspace as Lisp" puts the text Command-S writes on the clipboard.  A
   window-free run has no SDL clipboard: then the row still runs and says why it could not. *)
let run_copy_lisp () =
  let e = ref (editor {|(workspace copied
  (graph g :context sop (sop/box))
  (graph scene :context scene (scene/merge (scene/geometry (ref g)))))|}) and count = ref 0 in
  let step events = incr count; e := E3.update !e (frame (450., 300.) events !count) in
  let key k = Event.KeyPressed k in
  step []; step [];
  step [ key Input.Space; Event.KeyPressed (Input.KeyChar '/') ]; step [];
  step [ Event.TextInput "copy workspace" ]; step [ key Input.Enter ]; step [];
  let note = dump_line !e "cook" in
  (match Rays.Clipboard.get_text () with
   | Ok clip when has note "Copied the workspace as Lisp" ->
       check (has clip "(workspace copied" && has clip "(scene/geometry (ref g))")
         ("the clipboard holds the workspace text: " ^ clip)
   | _ -> check (has note "Clipboard: ") ("the palette row ran and said why it could not copy: " ^ note));
  check (E3.undo_label !e = None) "copying changes nothing";
  E3.close !e

(* ---- the studio layout (flow.md 11.11): fixed sizes, strips, start state, several graph panels ---- *)

let sketch name = In_channel.with_open_bin
    (Filename.concat "../sketches" (Filename.concat name "sketch.rays")) In_channel.input_all

let run_studio () =
  let text = sketch "ws_layout" in
  let ws = of_text text in
  let doc = build_ok ws in
  let shell = shell_of doc in
  check (Panels.to_string shell.tree = "(h outline (h (v (v view timeline) graph) (v inspector lisp)))")
    ("the studio tree: " ^ Panels.to_string shell.tree);
  (* the target at three window sizes: every fixed side keeps its points *)
  List.iter (fun (w, h) ->
    let g = Layout.geometry ~hidden:[] shell.tree { (frame (0., 0.) [] 0) with width = w; height = h; size = w, h } in
    let whole pick = match List.find_opt (fun (l : Layout.leaf) -> pick l.panel) g.leaves with
      | Some { header = x, y, lw, hh; body = _, _, _, bh; _ } -> x, y, lw, hh + bh
      | None -> fail "the studio lost a panel" in
    let expect what got want = check (got = want) (Printf.sprintf "studio at %dx%d: %s" w h what) in
    let tree = h - 24 and middle = w - 216 - 320 - 2 in
    expect "outline" (whole (( = ) Layout.Outline)) (0, 0, 216, tree);
    expect "viewport" (whole (function Layout.View _ -> true | _ -> false)) (217, 0, middle, tree - 336 - 24 - 2);
    expect "timeline" (whole (( = ) Layout.Timeline)) (217, tree - 336 - 24 - 1, middle, 24);
    expect "graph" (whole (( = ) Layout.Graph)) (217, tree - 336, middle, 336);
    expect "inspector" (whole (( = ) Layout.Inspector)) (w - 320, 0, 320, tree - 300 - 1);
    expect "lisp" (whole (( = ) Layout.Lisp)) (w - 320, tree - 300, 320, 300);
    expect "status" g.status_at (0, tree, w, 24))
    [ 1440, 900; 1920, 1080; 1100, 700 ];
  (* what the panels' keywords open the editor with *)
  let preview = match List.map fst shell.preview_sources with [ key ] -> key | _ -> fail "one viewport" in
  check (shell.named = [ [ 1; 0; 1 ], "garden" ] && shell.start.focus = Some [ 1; 0; 1 ]
         && shell.start.looking = [ preview ] && shell.start.tabs = [ [ 1; 1; 1 ], "graph" ])
    "the start state of the studio's panels";
  (* print and re-read *)
  let again = shell_of (build_ok (of_text (Doc.to_text ws))) in
  check (again.tree = shell.tree && again.named = shell.named && again.start = shell.start
         && again.switch = shell.switch)
    "the studio did not round-trip through its printed text";
  let apply ws op = match Doc.edit catalog ws op with
    | Ok ws -> ws | Error d -> fail (E.label op ^ ": " ^ Flow.Diagnostic.to_string d) in
  let text_of ws = fst (Flow.Lisp.print ws.Doc.source) in
  let refused name ws op needle = match Doc.edit catalog ws op with
    | Error d -> check (has (Flow.Diagnostic.to_string d) needle) (name ^ ": " ^ Flow.Diagnostic.to_string d)
    | Ok _ -> fail (name ^ " was accepted") in
  (* a gutter drag writes what the split is sized by *)
  let sized = apply ws (E.Set_layout_size { node = [ "editor"; "studio" ]; size = `First 260 }) in
  check (has (text_of sized) "(ui/split \"horizontal\" outline work :first_size 260)") "a fixed side is written in points";
  let ratio = apply ws (E.Set_layout_size { node = [ "editor"; "stage" ]; size = `Ratio 0.61803 }) in
  check (has (text_of ratio) "(ui/split-at \"vertical\" 0.618 preview timeline)") "a ratio keeps four decimals";
  let back = apply ratio (E.Set_layout_size { node = [ "editor"; "stage" ]; size = `Second 0 }) in
  check (has (text_of back) "(ui/split \"vertical\" preview timeline :second_size 1)") "a ratio split takes a fixed side";
  refused "two fixed sides" ws (E.Set_arg { node = [ "editor"; "studio" ]; key = E.Kw "second_size"; sub = [];
                                            value = S.make (S.Num "100") }) "one side";
  (* the keyword rows of the cards are the graph's view of it *)
  let rows name = match Flow_sop.Projection.find (Flow_sop.Projection.of_graph catalog ws.checked "editor") [ "editor"; name ] with
    | Some (n : Flow_sop.Projection.node) -> List.map (fun (r : Flow_sop.Projection.row) -> r.label) n.rows
    | None -> fail ("no card " ^ name) in
  check (List.mem "first_size" (rows "studio") && List.mem "second_size" (rows "studio")
         && List.mem "look_through" (rows "preview") && List.mem "focus" (rows "network")
         && List.mem "view" (rows "network") && List.mem "tab" (rows "code"))
    "the layout keywords are not rows of their cards";
  (* the layout commands take a graph whose result is a binding of the workspace *)
  List.iter (fun name ->
    let ws = of_text (sketch name) in
    let ws = List.fold_left apply ws [
      E.Layout_new { graph = "editor" }; E.Layout_window { graph = "editor"; kind = "inspector" };
      E.Layout_float { graph = "editor"; at = [ 0; 0 ] }; E.Set_layout { graph = "editor"; index = 0 };
      E.Layout_remove { graph = "editor" } ] in
    check (has (text_of ws) "shell (ui/workspace") (name ^ ": the workspace binding was not kept");
    check (not (has (text_of ws) "(-> ")) (name ^ ": a layout was printed as a thread");
    ignore (build_ok (of_text (Doc.to_text ws)))) [ "ws_layout"; "ws_bloom" ];
  (* diagnostics *)
  let bad name body needle = expect_error name (with_editor ("    " ^ body)) needle in
  bad "an unknown graph" "(ui/workspace (ui/graph \"nope\"))" "E_UNKNOWN_GRAPH";
  bad "two fixed sides" "(ui/workspace (ui/split \"vertical\" (ui/graph) (ui/lisp) :first_size 9 :second_size 9))" "one side";
  bad "a fixed side of nothing" "(ui/workspace (ui/split \"vertical\" (ui/graph) (ui/lisp) :first_size 0))" "1 point";
  bad "a fixed side on split-at" "(ui/workspace (ui/split-at \"vertical\" 0.5 (ui/graph) (ui/lisp) :first_size 9))" "first_size";
  bad "an unknown view" "(ui/workspace (ui/graph :view \"tree\"))" "view";
  bad "an unknown tab" "(ui/workspace (ui/lisp :tab \"all\"))" "tab";
  (* through the editor: the start state, the points a drag writes, two graph panels *)
  let e = ref (editor text) and count = ref 0 in
  let step ?(buttons = []) mouse events = incr count; e := E3.update !e (frame ~buttons mouse events !count) in
  let click point = step point [ Event.MouseMoved point ];
    step ~buttons:[ Input.LeftButton ] point [ Event.MousePressed (Input.LeftButton, point) ];
    step point [ Event.MouseReleased (Input.LeftButton, point) ]; step point [] in
  step (450., 100.) []; step (450., 100.) [];
  check (dump_line !e "focus" = "Graph" && dump_line !e "pane graph" = "garden") "the focus did not start in the graph panel";
  check (String.starts_with ~prefix:"graph tab" (dump_line !e "text")) ("the lisp panel's tab: " ^ dump_line !e "text");
  check (E3.look_through !e) "the viewport did not start looking through the render camera";
  step (216.5, 100.) [ Event.MouseMoved (216.5, 100.) ];
  step ~buttons:[ Input.LeftButton ] (216.5, 100.) [ Event.MousePressed (Input.LeftButton, (216.5, 100.)) ];
  step ~buttons:[ Input.LeftButton ] (180.2, 100.) [ Event.MouseMoved (180.2, 100.) ];
  step (180.2, 100.) [ Event.MouseReleased (Input.LeftButton, (180.2, 100.)) ]; step (180.2, 100.) [];
  check (has (source !e) "(ui/split \"horizontal\" outline work :first_size 180)" && E3.undo_label !e = Some "Resize panel")
    ("the gutter of a fixed split did not write points: " ^ source !e);
  (* the second layout: a floating graph on the material beside the docked graph, each its own pane *)
  e := (match E3.edit !e (E.Set_layout { graph = "editor"; index = 1 }) with Ok e -> e | Error m -> fail m);
  step (450., 100.) []; step (450., 100.) [];
  check (dump_line !e "graph panels" = "garden, clay") ("the graph panels: " ^ dump_line !e "graph panels");
  check (dump_line !e "windows" = "graph 560 90 520 360, view 250 470 380 260, inspector 1090 60 320 420, lisp 640 500 420 300")
    ("the windows: " ^ dump_line !e "windows");
  click (500., 200.);
  check (dump_line !e "pane graph" = "clay") "a press in the floating graph did not make it the pane in use";
  click (230., 420.);
  check (dump_line !e "pane graph" = "garden" && dump_line !e "graph panels" = "garden, clay")
    "the docked graph did not keep its own graph";
  E3.close !e;
  (* every panel is an instance (flow.md 11.11): at 1440x900 the second layout has an inspector
     and a text pane floating beside the docked ones; each draws, scrolls and types on its own *)
  let e = ref (editor (replace text ":active 0" ":active 1")) and count = ref 0 and probes = ref [] in
  let big mouse events = incr count;
    { (frame mouse events !count) with width = 1440; height = 900; size = 1440, 900;
      drawable_width = 1440; drawable_height = 900; drawable_size = 1440, 900 } in
  (* the sketch's own rows end every inspector: a tall filler whose place says where that inspector
     has scrolled to *)
  let step ?(buttons = []) mouse events =
    probes := [];
    e := fst (E3.update_with !e { (big mouse events) with mouse_buttons = buttons } ~inspector:(fun ui ->
      let filler = Pxui.Ui.box ui ~h:(Pxui.Ui.Px 1500.) "filler" in
      let _, y, _, _ = Pxui.Ui.rect ui filler in probes := !probes @ [ y ])) in
  let click point = step point [ Event.MouseMoved point ];
    step ~buttons:[ Input.LeftButton ] point [ Event.MousePressed (Input.LeftButton, point) ];
    step point [ Event.MouseReleased (Input.LeftButton, point) ]; step point [] in
  let rest point = step point []; step point []; step point [] in
  let docked = 1300., 530. and floating = 1200., 300. in
  rest (700., 200.);
  let at_rest = match !probes with [ a; b ] -> a, b | l -> fail (Printf.sprintf "%d inspectors drew their rows, not 2" (List.length l)) in
  let scroll point = step point [ Event.MouseMoved point ];
    for _ = 1 to 6 do step point [ Event.MouseScrolled (0., -8.) ] done; rest point;
    match !probes with [ a; b ] -> a, b | _ -> fail "an inspector stopped drawing" in
  let d1, f1 = scroll floating in
  check (d1 = fst at_rest && f1 <> snd at_rest)
    (Printf.sprintf "the floating inspector did not scroll on its own: %g %g, then %g %g" (fst at_rest) (snd at_rest) d1 f1);
  let d2, f2 = scroll docked in
  check (d2 <> d1 && f2 = f1) "the docked inspector did not scroll on its own";
  (* a click in a floating panel focuses it *)
  click floating;
  check (has (dump_line !e "panels") "inspector details*") ("a click did not focus the floating inspector: " ^ dump_line !e "panels");
  (* typing in the floating text pane drafts there, not in the docked one *)
  let pane name = List.find (fun l -> String.starts_with ~prefix:("lisp " ^ name) l)
    (List.map String.trim (String.split_on_char ';' (dump_line !e "panels"))) in
  check (has (pane "code") "graph tab, draft no" && has (pane "notes") "document tab, draft no")
    ("each text pane opens on its own tab: " ^ dump_line !e "panels");
  click (800., 660.);
  step (800., 660.) [ Event.TextInput " " ]; rest (800., 660.);
  check (has (pane "notes") "lisp notes*: document tab, draft yes" && has (pane "code") "graph tab, draft no")
    ("typing in one text pane reached the other: " ^ dump_line !e "panels");
  click (1280., 720.);
  step (1280., 720.) [ Event.TextInput " " ]; rest (1280., 720.);
  check (has (pane "code") "lisp code*: graph tab, draft yes" && has (pane "notes") "document tab, draft yes")
    ("the docked text pane does not draft on its own: " ^ dump_line !e "panels");
  E3.close !e;
  (* the start keywords are followed again when their value in the text changes, and only then *)
  let e = ref (editor text) and count = ref 0 in
  let big mouse events = incr count;
    { (frame mouse events !count) with width = 1440; height = 900; size = 1440, 900;
      drawable_width = 1440; drawable_height = 900; drawable_size = 1440, 900 } in
  let step ?(buttons = []) mouse events = e := E3.update !e { (big mouse events) with mouse_buttons = buttons } in
  let click point = step point [ Event.MouseMoved point ];
    step ~buttons:[ Input.LeftButton ] point [ Event.MousePressed (Input.LeftButton, point) ];
    step point [ Event.MouseReleased (Input.LeftButton, point) ]; step point [] in
  let at = 600., 700. in
  let rest () = step at []; step at [] in
  let set name key value =
    e := (match E3.edit !e (E.Set_arg { node = [ "editor"; name ]; key = E.Kw key; sub = []; value = S.make value }) with
      | Ok e -> e | Error m -> fail m);
    rest () in
  rest ();
  check (dump_line !e "projection" = "graph" && E3.look_through !e) "the studio opens as its keywords say";
  set "network" "view" (S.Str "list");
  check (dump_line !e "projection" = "list") "a changed :view was not followed";
  step at [ Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'l') ];
  step at [ Event.KeyPressed (Input.KeyChar 'g') ]; rest ();
  check (dump_line !e "projection" = "graph") "Space l g did not show the graph";
  e := (match E3.edit !e (E.Set_layout_size { node = [ "editor"; "stage" ]; size = `Ratio 0.4 }) with Ok e -> e | Error m -> fail m);
  rest ();
  check (dump_line !e "projection" = "graph") "an edit that left :view alone reset the view the user chose";
  set "network" "view" (S.Str "graph"); set "preview" "look_through" (S.Sym "false");
  check (not (E3.look_through !e)) "a changed :look_through was not followed";
  set "code" "tab" (S.Str "document");
  check (has (dump_line !e "panels") "lisp code: document tab") ("a changed :tab was not followed: " ^ dump_line !e "panels");
  set "outline" "focus" (S.Sym "true");
  check (dump_line !e "focus" = "Outline") "a changed :focus was not followed";
  (* the Size row of a split's card converts it, keeping the sizes it shows: the editor graph in
     the pane, the studio card selected, the row's menu *)
  step at [ Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'j') ];
  step at [ Event.TextInput "editor" ]; step at [ Event.KeyPressed Input.Enter ]; rest ();
  click (600., 600.);
  check (dump_line !e "scope selected" = "editor/studio") ("the studio card is not where the test clicks: " ^ dump_line !e "scope selected");
  (* the 320-wide inspector starts at y 24; the split's head is 125 tall (chips, name, detail), then the
     note row (24) and the Size row, whose middle is 24 + 125 + 24 + 12 = 185 *)
  let pick dy = click (600., 600.); click (1390., 185.); click (1390., 185. +. dy) in
  pick 26.;
  check (has (source !e) "studio (ui/split-at \"horizontal\" 0.1505 outline work)" && E3.undo_label !e = Some "Resize panel")
    ("the Size row did not size the split by its ratio: " ^ source !e);
  pick 74.;
  check (has (source !e) "studio (ui/split \"horizontal\" outline work :second_size 1223)")
    ("the Size row did not fix the second side at its points: " ^ source !e);
  pick 50.;
  check (has (source !e) "studio (ui/split \"horizontal\" outline work :first_size 216)")
    ("the Size row did not return to the first side's points: " ^ source !e);
  E3.close !e;
  (* a graph panel in text view is live without the focus, and takes a gesture on the first press *)
  let e = ref (editor (with_editor "    (ui/workspace (ui/split \"horizontal\" (ui/graph \"garden\" :focus true) (ui/graph \"scene\" :view \"text\")))"))
  and count = ref 0 in
  let step ?(buttons = []) mouse events = incr count; e := E3.update !e (frame ~buttons mouse events !count) in
  step (100., 300.) []; step (100., 300.) [];
  check (dump_line !e "pane graph" = "garden" && dump_line !e "projection" = "graph"
         && has (dump_line !e "panels") "graph 0*; graph 1: selection tab, draft no")
    ("the second graph panel does not hold its own text pane: " ^ dump_line !e "panels");
  let point = 650., 300. in
  step point [ Event.MouseMoved point ];
  step ~buttons:[ Input.LeftButton ] point [ Event.MousePressed (Input.LeftButton, point) ];
  step point [ Event.MouseReleased (Input.LeftButton, point) ];
  step point [ Event.TextInput " " ]; step point []; step point [];
  check (dump_line !e "pane graph" = "scene" && has (dump_line !e "panels") "graph 1*: selection tab, draft yes")
    ("the first press in an unfocused text view did not start an edit there: " ^ dump_line !e "panels");
  E3.close !e;
  (* a float that is the bound name takes the window of its binding *)
  let floated = editor (with_editor "    (let* [win (ui/floating (ui/inspector))]\n      (ui/workspace (ui/split \"horizontal\" (ui/graph) win)))"
    ^ "(layout (panel [\"editor\" \"win\"] :collapsed false :window [100 80 300 200]))") in
  check (dump_line floated "windows" = "inspector 100 80 300 200") ("a bound float's window: " ^ dump_line floated "windows");
  E3.close floated;
  print_endline "workspace shell: the studio layout: fixed sizes, strips, start keywords, size conversion, bound workspace, panel instances ok"

(* ---- panels tied to a graph panel, bindings used twice, views as said, second lists and outlines ---- *)

let run_panels () =
  let lowered body = shell_of (build_ok (of_text (with_editor body))) in
  (* :of ties an inspector, a list or a text pane to the graph panel a binding names *)
  let tied = "    (let* [a (ui/graph \"garden\" :focus true)\n           b (ui/graph \"scene\")\n           ia (ui/inspector :of a)\n           ib (ui/inspector :of b)]\n      (ui/workspace (ui/split \"horizontal\" (ui/split \"vertical\" a b) (ui/split \"vertical\" ia ib))))" in
  check ((lowered tied).follows = [ [ 1; 1 ], [ 0; 1 ]; [ 1; 0 ], [ 0; 0 ] ]) "the inspectors are tied to their graph panels";
  expect_error "an :of that is not a graph panel"
    (with_editor "    (let* [c (ui/lisp)] (ui/workspace (ui/split \"vertical\" c (ui/inspector :of c))))") "E_PANEL_OF";
  expect_error "an :of that is not a binding"
    (with_editor "    (ui/workspace (ui/split \"vertical\" (ui/graph) (ui/list :of (ui/graph))))") "E_PANEL_OF";
  expect_error "an :of outside the layout shown"
    (with_editor "    (let* [g (ui/graph) h (ui/graph)] (ui/workspace (ui/split \"vertical\" h (ui/lisp :of g))))") "E_PANEL_OF";
  let rows = match Flow_sop.Projection.find (Flow_sop.Projection.of_graph catalog (of_text (with_editor tied)).checked "editor") [ "editor"; "ia" ] with
    | Some (n : Flow_sop.Projection.node) -> List.map (fun (r : Flow_sop.Projection.row) -> r.label) n.rows
    | None -> fail "no card ia" in
  check (List.mem "of" rows) "the :of keyword is not a row of the inspector's card";
  let retied = match Doc.edit catalog (of_text (with_editor tied))
      (E.Connect { node = [ "editor"; "ia" ]; key = E.Kw "of"; src = "b"; iter = false }) with
    | Ok ws -> shell_of (build_ok ws) | Error d -> fail (Flow.Diagnostic.to_string d) in
  check (List.assoc [ 1; 0 ] retied.follows = [ 0; 1 ]) "a wire to the of row did not tie the inspector to the other graph panel";
  let e = ref (editor (with_editor tied)) and count = ref 0 and drawn = ref 0 in
  let step ?(buttons = []) mouse events = incr count; drawn := 0;
    e := fst (E3.update_with !e (frame ~buttons mouse events !count) ~inspector:(fun _ -> incr drawn)) in
  let click point = step point [ Event.MouseMoved point ];
    step ~buttons:[ Input.LeftButton ] point [ Event.MousePressed (Input.LeftButton, point) ];
    step point [ Event.MouseReleased (Input.LeftButton, point) ]; step point [] in
  step (100., 100.) []; step (100., 100.) [];
  check (!drawn = 2) "with nothing selected both inspectors show the sketch's rows";
  (* a node selected in graph a: its inspector shows the node, b's still the sketch's rows *)
  click (30., 60.);
  check (dump_line !e "scope selected" = "garden/:seed" && !drawn = 1)
    ("the inspector tied to a did not follow a's selection: " ^ dump_line !e "scope selected");
  (* graph b takes the focus: a's inspector keeps showing a's node *)
  click (200., 600.);
  check (dump_line !e "pane graph" = "scene" && dump_line !e "scope selected" = "-" && !drawn = 1)
    "the inspector tied to a followed the focus to b";
  (* a press in the tied inspector makes its graph panel the one in use *)
  click (880., 300.);
  check (dump_line !e "pane graph" = "garden" && dump_line !e "scope selected" = "garden/:seed"
         && has (dump_line !e "panels") "inspector ia*")
    "a press in a tied inspector did not bring its graph panel into use";
  E3.close !e;
  (* one binding used twice is two instances, keyed by place; the binding's saved entry is what
     each starts from *)
  let twice = with_editor "    (let* [g (ui/graph \"garden\")] (ui/workspace (ui/split \"horizontal\" g g)))" in
  check ((lowered "    (let* [g (ui/graph \"garden\")] (ui/workspace (ui/split \"horizontal\" g g)))").repeated = [ "g" ])
    "a binding used twice is not marked";
  let e = ref (editor (twice ^ "(layout (panel [\"editor\" \"g\"] :collapsed false :window [10 30 300 200])\n        (panel [\"editor\" \"@panel\" \"1\"] :collapsed false :window [400 30 300 200]))")) and count = ref 0 in
  let step ?(buttons = []) mouse events = incr count; e := E3.update !e (frame ~buttons mouse events !count) in
  let click point = step point [ Event.MouseMoved point ];
    step ~buttons:[ Input.LeftButton ] point [ Event.MousePressed (Input.LeftButton, point) ];
    step point [ Event.MouseReleased (Input.LeftButton, point) ]; step point [] in
  step (700., 500.) []; step (700., 500.) [];
  check (dump_line !e "windows" = "graph 10 30 300 200, graph 400 30 300 200")
    ("the saved entries of a binding used twice: " ^ dump_line !e "windows");
  check (dump_line !e "panels" = "graph 0; graph 1") ("the leaves of one binding are not two instances: " ^ dump_line !e "panels");
  click (40., 110.);
  let first = dump_line !e "scope selected" in
  click (550., 200.);
  check (first <> "-" && dump_line !e "scope selected" = "-" && dump_line !e "panels" = "graph 0; graph 1*")
    ("the second leaf shares the first one's selection: " ^ first ^ " / " ^ dump_line !e "scope selected");
  E3.close !e;
  (* a graph panel shows the view it says, with a lisp panel beside it *)
  let e = editor (with_editor "    (ui/workspace (ui/split \"horizontal\" (ui/graph \"garden\" :view \"text\" :focus true) (ui/lisp)))") in
  let e = E3.update (E3.update e (frame (700., 500.) [] 1)) (frame (700., 500.) [] 2) in
  check (dump_line e "projection" = "text" && has (dump_line e "panels") "graph 0*: selection tab")
    ("a graph panel beside a lisp panel does not show its text view: " ^ dump_line e "panels");
  E3.close e;
  (* two lists and two outlines: each its own filter, focus row and search; a click focuses *)
  let e = ref (editor (with_editor "    (let* [oa (ui/outline) ob (ui/outline) la (ui/list) lb (ui/list)]\n      (ui/workspace (ui/split \"horizontal\" (ui/split \"vertical\" oa ob)\n        (ui/split \"horizontal\" (ui/split \"vertical\" la lb) (ui/viewport (ref scene))))))")) and count = ref 0 in
  let step ?(buttons = []) mouse events = incr count; e := E3.update !e (frame ~buttons mouse events !count) in
  let click point = step point [ Event.MouseMoved point ];
    step ~buttons:[ Input.LeftButton ] point [ Event.MousePressed (Input.LeftButton, point) ];
    step point [ Event.MouseReleased (Input.LeftButton, point) ]; step point [] in
  step (800., 500.) []; step (800., 500.) [];
  let typed point text = click point; step point [ Event.TextInput text ]; step point [ Event.KeyPressed Input.Enter ]; step point [] in
  let panels () = dump_line !e "panels" in
  typed (100., 38.) "zz";
  check (has (panels ()) "outline oa*: search \"zz\"; outline ob: search \"\"") ("the first outline's search: " ^ panels ());
  typed (100., 344.) "q";
  check (has (panels ()) "outline oa: search \"zz\"; outline ob*: search \"q\"")
    ("a search typed in one outline shows in the other: " ^ panels ());
  click (550., 60.);
  step (550., 60.) [ Event.KeyPressed (Input.KeyChar '/') ]; step (550., 60.) [ Event.TextInput "g" ]; step (550., 60.) [];
  check (has (panels ()) "list la*: focus 336, 0 folded, filter \"g\"; list lb: focus -, 0 folded, filter -")
    ("the first list's focus row and filter: " ^ panels ());
  step (550., 60.) [ Event.KeyPressed Input.Enter ]; step (550., 60.) [];
  click (550., 370.);
  check (has (panels ()) "list la: focus 336, 0 folded, filter \"g\"; list lb*: focus 336, 0 folded, filter -")
    ("the second list does not keep its own filter: " ^ panels ());
  E3.close !e;
  print_endline "workspace shell: tied panels, repeated bindings, views as said, second lists and outlines ok"

let run () = run_panels (); run_studio (); run_copy_lisp (); run_hide_and_order (); run_root_section (); run_layouts (); run_compose (); run_ref_picker (); run_result_view (); run_panel_states (); run_camera_zoom (); run_cameras (); run_lowering (); run_ops (); run_panel_keys (); run_unbound_panels (); run_values (); run_duplicate_and_view (); run_movers (); run_frame_key (); run_loop_copies (); run_loop_expression (); run_editor (); run_restore (); run_views (); run_instances ()

(* Native VIEW regression over the reported sketch, including its piece renderer and a following
   camera. Moving the camera rebuilds the lowering while preserving an unchanged object network. *)
let run_view_native () =
  let directory = Filename.temp_dir "rays-view" "" in
  let prefix = Option.value ~default:(Filename.concat directory "view")
      (Sys.getenv_opt "RAYS_VIEW_PNG") in
  let text = In_channel.with_open_bin "../sketches/shattered_cube/sketch.rays" In_channel.input_all in
  let rendered = ref "" and vertices = ref [] and original = ref [] and edited = ref []
  and returned = ref false in
  ignore (Sketch.run_state ~max_frames:37
    ~config:{Sketch.default_config with width = 1200; height = 760;
      title = "Shattered Cube · VIEW regression"; domains = Some 1}
    ~init:(fun _ -> E3.create ~await:true ~workspace:(of_text text)
      ~presets:(Filename.concat directory "presets") ~seed:7349L ~grain:2
      ~camera:(Easy_camera.create ~target:Vec3.zero ~distance:6.8 ~azimuth:0.72 ~elevation:0.42 ())
      ~prepare:(fun _ output ->
        match Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Primitive "piece" output.Session.geometry with
        | Some attribute when (match Rdk.Attribute.Private.storage attribute with
            | Rdk.Attribute.Int _ | Text _ -> true | _ -> false) ->
            Sketch_support.Packed_pieces.of_geometry ~piece_attribute:"piece" output.geometry
            |> Result.map (fun pieces -> `Pieces pieces)
        | _ -> Rdk_rays.Rays_mesh.to_mesh output.geometry
            |> Result.map (fun mesh -> `Mesh (mesh, output.instances))
            |> Result.map_error Rdk.Error.to_string)
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
          E3.edit e (E.Set_arg {node = ["shattered"; "exploded_view"]; key = E.Kw "amount";
            sub = []; value = S.make (S.Num "0.8")}) |> Result.get_ok
        else e in
      let gx, gy, _, _ = (E3.panes e frame).graph in
      let graph = float (gx + 40), float (gy + 40) and view = 150., 300. in
      let mouse = if frame.count = 24 then
          (* the first v (frame 14) made the box the result, binding the old
             anonymous result under the name its head gives it *)
          let x, y, w, _ = Option.get (E3.node_box e ["shattered"; "exploded_view"]) in
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
          check (Node.operation (E3.displayed_node e) = "exploded_view"
                 && Editor_document.Layout_by_path.Path_map.find_opt ["shattered"] (E3.workspace e).layout.display = None)
            "native v did not set the result node"
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
  if Sys.getenv_opt "RAYS_VIEW_PNG" = None then
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
  let directory = Filename.temp_dir "rays-renderer" "" in
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
      ~prepare:(fun _ output -> Rdk_rays.Rays_mesh.to_mesh output.Session.geometry
        |> Result.map_error Rdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [Scene3.mesh
        ~material:(Material.unlit (Color.rgb 200 20 200)) mesh]) () |> Result.get_ok)
    ~update:(fun e (frame : Frame.t) ->
      let mode = if frame.count < 10 || frame.count >= 40 then Rays_editor.Renderer.Raster
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
  let mesh_pixels path =
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
          let b = Char.code (Bytes.get pixels (offset + 2)) in
          (* the mesh's magenta, a colour the kit's guides, brackets and labels over the view never use *)
          if r > 110 && b > 110 && g < 100 && g + 40 < r then counts.(i) <- counts.(i) + 1
        done
      done) [|(0, 50, 440, 450); (450, 142, 320, 258)|];
    Image.destroy image; counts in
  List.iter (fun frame ->
    let counts = mesh_pixels (Filename.concat directory (Printf.sprintf "%d.png" frame)) in
    check (counts.(0) > 30 && counts.(1) > 30)
      (Printf.sprintf "renderer frame %d missed a docked or floating viewport (%d, %d)" frame counts.(0) counts.(1))) [5; 35; 45];
  let wire = mesh_pixels (Filename.concat directory "15.png") in
  check (wire.(0) < 30 && wire.(1) < 30)
    (Printf.sprintf "wireframe still painted filled faces (%d, %d)" wire.(0) wire.(1));
  List.iter Sys.remove !samples;
  let state = Filename.concat directory "presets/state" in
  if Sys.file_exists state then begin Array.iter (fun name -> Sys.remove (Filename.concat state name)) (Sys.readdir state);
    Unix.rmdir state; Unix.rmdir (Filename.dirname state) end;
  Unix.rmdir directory

let run_native () =
  let directory = Filename.temp_dir "rays-variations" "" in
  let path = match Sys.getenv_opt "RAYS_SHELL_PNG" with Some p -> p | None -> Filename.concat directory "variations.png" in
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
  if Sys.getenv_opt "RAYS_SHELL_PNG" = None then Sys.remove path;
  Unix.rmdir directory;
  run_renderers_native ();
  run_renderers_native ~authored:true ()

(* ---- two roots in one frame: each viewport renders as its own root says ---- *)

(* Two scene graphs with a root, a camera, a size and a World each, in one window. *)
let roots_text ?(renderer = "Path traced") () = Printf.sprintf {|(workspace roots
  (graph g :context sop (sop/box))
  (graph noon :context world (world/sun (world/sky :name "noon") :name "sun"))
  (graph dusk :context world (world/sun (world/sky :name "dusk") :name "sun"))
  (graph set :context scene (scene/merge (scene/geometry (ref g) :name "body")))
  (graph day :context scene
    (let* [cam (scene/camera :name "noon-cam" :eye [0 1 8])
           all (scene/merge (ref set) cam (scene/world (ref noon) :name "Noon"))
           root (scene/root all :camera cam :renderer "%s" :width 800 :height 450 :max_spp 4096)]
      root))
  (graph night :context scene
    (let* [cam (scene/camera :name "dusk-cam" :eye [5 2 6])
           all (scene/merge (ref set) cam (scene/world (ref dusk) :name "Dusk" :exposure -2))
           root (scene/root all :camera cam :renderer "%s" :width 640 :height 640 :max_spp 16 :bounces 12)]
      root))
  (graph editor :context editor
    (ui/workspace (ui/split-at "horizontal" 0.5 (ui/viewport (ref day)) (ui/viewport (ref night))))))|}
  renderer renderer

let eye_of = function
  | "day" -> Vec3.create 0. 1. 8. | _ -> Vec3.create 5. 2. 6.

(* Without a GPU: looking through the camera, each viewport sees through the camera its own root
   names, at its own gate; the renderer's film steps and turns are pure. *)
let run_roots () =
  let module B = Rays_editor.Private.Render_budget in
  check (B.film ~resolution:(1600, 900) ~gate:(1700, 1000) = ((1600, 900), 1)) "a gate over the resolution is step 1";
  check (B.film ~resolution:(1600, 900) ~gate:(1600, 900) = ((1600, 900), 1)) "a gate at the resolution is step 1";
  check (B.film ~resolution:(1600, 900) ~gate:(1599, 899) = ((800, 450), 2)) "one pixel under is a half";
  check (B.film ~resolution:(1600, 900) ~gate:(800, 450) = ((800, 450), 2)) "the half fits its gate exactly";
  check (B.film ~resolution:(1600, 900) ~gate:(799, 449) = ((400, 225), 4)) "then a quarter";
  check (B.film ~resolution:(1600, 900) ~gate:(300, 169) = ((200, 112), 8)) "then an eighth";
  check (B.film ~resolution:(1600, 900) ~gate:(10, 10) = ((200, 112), 8)) "never smaller than an eighth";
  (* a resize inside a step leaves the film alone *)
  let step gate = B.film ~resolution:(1600, 900) ~gate in
  check (List.for_all (fun w -> step (w, w * 9 / 16) = ((400, 225), 4)) (List.init 200 (fun i -> 400 + i)))
    "every gate from 400 to 599 points wide gets the same film";
  let order = [ "a"; "b"; "c"; "d" ] in
  check (B.next_turn ~order ~last:None [ "b"; "c"; "d" ] = Some "b") "the first wanting viewport takes the first turn";
  check (B.next_turn ~order ~last:(Some "b") [ "b"; "c"; "d" ] = Some "c") "the next takes the next";
  check (B.next_turn ~order ~last:(Some "d") [ "b"; "c" ] = Some "b") "the rotation wraps";
  check (B.next_turn ~order ~last:(Some "c") [ "b" ] = Some "b") "a lone one repeats";
  check (B.next_turn ~order ~last:(Some "a") [] = None) "no one wants, no turn";
  let e = ref (editor (roots_text ~renderer:"Raster" ())) in
  let keys = List.map fst (shell_of (build_ok (E3.workspace !e))).preview_sources in
  let day, night = match keys with [ d; n ] -> d, n | _ -> fail "two viewports, two roots" in
  let count = ref 0 in
  let step ?(events = []) () = incr count; e := E3.update !e (frame (100., 100.) events !count) in
  step (); step ();
  step ~events:[ Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'v') ] (); step (); step ();
  check (E3.look_through !e) "Space v did not look through the camera";
  let near a b = Vec3.nearly_equal a b ~eps:1e-4 in
  check (near (Camera.position (E3.viewport_camera !e day)) (eye_of "day"))
    "the first viewport does not look through its own root's camera";
  (* look-through is the focused viewport's own: the other keeps its orbit until its panel says so *)
  check (not (near (Camera.position (E3.viewport_camera !e night)) (eye_of "night")))
    "Space v looked through a viewport that does not have the focus";
  let through = editor (replace (roots_text ~renderer:"Raster" ()) "(ui/viewport (ref night))"
    "(ui/viewport (ref night) :look_through true)") in
  let through = E3.update (E3.update through (frame (100., 100.) [] 1)) (frame (100., 100.) [] 2) in
  check (near (Camera.position (E3.viewport_camera through night)) (eye_of "night")
         && not (E3.look_through through))
    "the second viewport does not look through its own root's camera as its :look_through says";
  E3.close through;
  check (E3.slot !e day = None && E3.slot !e night = None) "a raster viewport has no tracer slot";
  E3.close !e;
  print_endline "workspace shell: film steps and turns, each viewport looks through its own root's camera ok"

(* Native: both roots path trace in one window.  Each slot has its root's film and camera, the dusk
   is darker than noon, a cap raised continues the accumulation, a splitter drag inside a film step
   keeps the samples (and one that crosses a step restarts them), and an edit of the second root
   restarts only its slot. *)
let run_roots_native () =
  let directory = Filename.temp_dir "rays-roots" "" in
  let png = Filename.concat directory "roots.png" in
  (* look-through is each viewport's own: the first takes Space v, the second says so in the text *)
  let text = replace (roots_text ()) "(ui/viewport (ref night))" "(ui/viewport (ref night) :look_through true)" in
  let doc = build_ok (of_text text) in
  let shell = shell_of doc in
  let day, night = match List.map fst shell.preview_sources with [ d; n ] -> d, n | _ -> fail "two viewports" in
  let geometry = Layout.geometry ~hidden:[ Layout.Timeline ] shell.tree (frame (0., 0.) [] 0) in
  let pane key = List.find_map (fun (l : Layout.leaf) -> if l.panel = Layout.View key then Some l.body else None)
      geometry.leaves |> Option.get in
  let splitter = List.find (fun (s : Layout.splitter) -> s.node = Some []) geometry.splitters in
  let sx, sy, sw, sh = splitter.bounds in
  let grip = float (sx + sw / 2), float (sy + sh / 2) in
  let drag_at start ~from ~by c = (* the frames of one splitter drag, from [from] points right of the grip *)
    let grip = fst grip +. from, snd grip in
    let target = fst grip +. by, snd grip in
    match c - start with
    | 0 -> Some (grip, [], [ Event.MouseMoved grip ])
    | 1 -> Some (grip, [ Input.LeftButton ], [ Event.MousePressed (Input.LeftButton, grip) ])
    | 2 -> Some (target, [ Input.LeftButton ], [ Event.MouseMoved target ])
    | 3 -> Some (target, [], [ Event.MouseReleased (Input.LeftButton, target) ])
    | _ -> None in
  let slots = Hashtbl.create 8 and cameras = ref [] in
  let need e key = match E3.slot e key with Some slot -> slot | None -> fail ("no tracer slot for " ^ key) in
  let edit e arg value =
    match E3.edit e (E.Set_arg { node = [ "night"; "root" ]; key = E.Kw arg; sub = []; value = S.make (S.Num value) }) with
    | Ok e -> e | Error message -> fail message in
  ignore (Sketch.run_state ~max_frames:200
    ~config:{ Sketch.default_config with width = 900; height = 640; title = "two roots" }
    ~init:(fun _ -> E3.create ~await:true ~workspace:(of_text text)
      ~presets:(Filename.concat directory "presets")
      ~prepare:(fun _ output -> Rdk_rays.Rays_mesh.to_mesh output.Session.geometry
        |> Result.map_error Rdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok)
    ~update:(fun e (frame : Frame.t) ->
      let c = frame.count in
      let e = if c = 61 then edit e "max_spp" "4096"      (* the cap rises: the film goes on *)
        else if c = 131 then edit e "bounces" "6"          (* the setting changes: the slot restarts *)
        else e in
      let mouse, buttons, events =
        match drag_at 101 ~from:0. ~by:10. c, drag_at 161 ~from:10. ~by:200. c with
        | Some move, _ | None, Some move -> move
        | None, None -> (100., 100.), [], (if c = 2 then [ Event.KeyPressed Input.Space; Event.KeyPressed (Input.KeyChar 'v') ] else []) in
      E3.update e { frame with mouse; mouse_buttons = buttons; mouse_delta = 0., 0.; keys = []; events })
    ~view:E3.scene
    ~after_present:(fun e (frame : Frame.t) ->
      if List.mem frame.count [ 60; 100; 130; 160; 195 ] then
        Hashtbl.replace slots frame.count (need e day, need e night);
      if frame.count = 60 then begin
        cameras := [ day, Camera.position (E3.viewport_camera e day); night, Camera.position (E3.viewport_camera e night) ];
        check (Canvas.save_screen_png png = Ok ()) "the window did not save its screen"
      end;
      E3.after_present e frame)
    ~on_stop:E3.close ());
  let at c = Hashtbl.find slots c in
  let day60, night60 = at 60 and day100, night100 = at 100 and day130, night130 = at 130
  and day160, night160 = at 160 and day195, night195 = at 195 in
  let describe (s : E3.slot) = Printf.sprintf "%dx%d 1/%d %d/%d" (fst s.film) (snd s.film) s.step s.samples s.max_spp in
  (* each slot's film is its own root's resolution in a step; its camera is its root's *)
  let steps = [ 1; 2; 4; 8 ] in
  check (List.mem day60.step steps && day60.film = (800 / day60.step, 450 / day60.step))
    ("the first slot's film is not its root's 800x450 in a step: " ^ describe day60);
  check (List.mem night60.step steps && night60.film = (640 / night60.step, 640 / night60.step))
    ("the second slot's film is not its root's 640x640 in a step: " ^ describe night60);
  check (day60.max_spp = 4096 && night60.max_spp = 16) "each slot carries its own root's cap";
  List.iter (fun (key, eye) ->
    let want = eye_of (if key = day then "day" else "night") in
    check (Vec3.nearly_equal eye want ~eps:1e-4)
      (Printf.sprintf "a pane's camera is not its root's authored camera (%s: %g %g %g, authored %g %g %g)"
         key eye.Vec3.x eye.y eye.z want.Vec3.x want.y want.z)) !cameras;
  check (night60.samples >= 16 && day60.samples >= 16)
    (Printf.sprintf "the slots did not accumulate: %s, %s" (describe day60) (describe night60));
  (* the cap read each frame: raised, the second slot goes on from where it stopped *)
  check (night100.max_spp = 4096 && night100.samples > night60.samples && night100.film = night60.film)
    (Printf.sprintf "raising a cap did not continue the accumulation: %s then %s" (describe night60) (describe night100));
  check (day100.samples > day60.samples) "the first slot stopped accumulating";
  (* a splitter drag inside a step keeps the samples *)
  check (day130.film = day100.film && night130.film = night100.film)
    "a splitter drag inside a step changed a film";
  check (day130.samples > day100.samples && night130.samples > night100.samples)
    (Printf.sprintf "a splitter drag inside a step restarted the accumulation: %s, %s then %s, %s"
       (describe day100) (describe night100) (describe day130) (describe night130));
  (* editing the second root restarts its slot and leaves the first alone *)
  check (night160.samples < night130.samples)
    (Printf.sprintf "editing a root's setting did not restart its slot: %s then %s"
       (describe night130) (describe night160));
  check (day160.samples > day130.samples)
    (Printf.sprintf "editing the second root disturbed the first slot: %s then %s" (describe day130) (describe day160));
  (* a drag across a step restarts: the second viewport's film is smaller, the first one's is not *)
  check (night195.step > night160.step && night195.film <> night160.film && night195.samples <= 40)
    (Printf.sprintf "a drag across a step kept the second film: %s then %s" (describe night160) (describe night195));
  check (day195.film = day160.film && day195.samples > day160.samples)
    (Printf.sprintf "a drag across the second film's step disturbed the first: %s then %s"
       (describe day160) (describe day195));
  (* what the window shows: both panes drawn, the pictures differ, dusk is darker than noon *)
  let image = Image.load_exn png in
  let pixels = Result.get_ok (Image.Private.pixels image) in
  let scale = float (Image.get_width image) /. 900. in
  let region (x, y, w, h) (resolution_w, resolution_h) =
    (* the inner part of the gate, which is centred in the pane *)
    let aspect = float resolution_w /. float resolution_h in
    let gw = min (float w) (float h *. aspect) and gh = min (float h) (float w /. aspect) in
    let cx = float x +. float w /. 2. and cy = float y +. float h /. 2. in
    let x0 = int_of_float ((cx -. gw *. 0.3) *. scale) and x1 = int_of_float ((cx +. gw *. 0.3) *. scale)
    and y0 = int_of_float ((cy -. gh *. 0.3) *. scale) and y1 = int_of_float ((cy +. gh *. 0.3) *. scale) in
    let sum = ref 0. and count = ref 0 and differing = ref 0 and bits = Buffer.create 256 in
    for py = y0 to y1 - 1 do
      for px = x0 to x1 - 1 do
        let o = 4 * (py * Image.get_width image + px) in
        let r = Char.code (Bytes.get pixels o) and g = Char.code (Bytes.get pixels (o + 1))
        and b = Char.code (Bytes.get pixels (o + 2)) in
        sum := !sum +. (0.2126 *. float r +. 0.7152 *. float g +. 0.0722 *. float b);
        incr count;
        if abs (r - 244) + abs (g - 245) + abs (b - 240) > 30 then incr differing;
        Buffer.add_char bits (Char.chr (r lsr 3 lsl 3))
      done
    done;
    !sum /. float (max 1 !count), !differing * 100 / max 1 !count, Digest.string (Buffer.contents bits) in
  let day_mean, day_cover, day_digest = region (pane day) (800, 450)
  and night_mean, night_cover, night_digest = region (pane night) (640, 640) in
  check (day_cover > 20 && night_cover > 20)
    (Printf.sprintf "a pane is blank (%d%% and %d%% drawn)" day_cover night_cover);
  check (day_digest <> night_digest) "both panes show the same picture";
  check (night_mean < day_mean)
    (Printf.sprintf "dusk is not darker than noon (mean %.1f and %.1f)" night_mean day_mean);
  Sys.remove png;
  let state = Filename.concat directory "presets/state" in
  if Sys.file_exists state then begin
    Array.iter (fun name -> Sys.remove (Filename.concat state name)) (Sys.readdir state);
    Unix.rmdir state; Unix.rmdir (Filename.dirname state) end;
  Unix.rmdir directory;
  print_endline "workspace shell: two roots in one frame, each with its own film, camera and cap ok"

(* Native: four traced viewports over three roots (two of them over one).  The two share a slot;
   the focused one renders every frame and the others take turns, so over a run it gets about
   twice the samples of each of the two that alternate. *)
let run_budget_native () =
  let root name eye = Printf.sprintf {|  (graph %s :context scene
    (let* [cam (scene/camera :name "cam" :eye %s)
           all (scene/merge (ref set) cam)
           root (scene/root all :camera cam :renderer "Path traced" :width 800 :height 450 :max_spp 4096)]
      root))
|} name eye in
  let text = {|(workspace budget
  (graph g :context sop (sop/box))
  (graph set :context scene (scene/merge (scene/geometry (ref g) :name "body")))
|} ^ root "a" "[0 1 8]" ^ root "b" "[5 2 6]" ^ root "c" "[-5 2 6]" ^ {|  (graph editor :context editor
    (ui/workspace (ui/split-at "horizontal" 0.5
      (ui/split-at "vertical" 0.5 (ui/viewport (ref a)) (ui/viewport (ref b)))
      (ui/split-at "vertical" 0.5 (ui/viewport (ref c)) (ui/viewport (ref a)))))))|} in
  let directory = Filename.temp_dir "rays-budget" "" in
  let keys = List.map fst (shell_of (build_ok (of_text text))).preview_sources in
  let a, b, c, a_again = match keys with [ a; b; c; d ] -> a, b, c, d | _ -> fail "four viewports" in
  let final = ref None in
  ignore (Sketch.run_state ~max_frames:120
    ~config:{ Sketch.default_config with width = 900; height = 640; title = "budget" }
    ~init:(fun _ -> E3.create ~await:true ~workspace:(of_text text)
      ~presets:(Filename.concat directory "presets")
      ~prepare:(fun _ output -> Rdk_rays.Rays_mesh.to_mesh output.Session.geometry
        |> Result.map_error Rdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok)
    ~update:(fun e (frame : Frame.t) ->
      E3.update e { frame with mouse = (450., 20.); mouse_buttons = []; mouse_delta = 0., 0.; keys = []; events = [] })
    ~view:E3.scene
    ~after_present:(fun e (frame : Frame.t) ->
      if frame.count = 120 then final := Some (List.map (fun key -> key, E3.slot e key) [ a; b; c; a_again ]);
      E3.after_present e frame)
    ~on_stop:E3.close ());
  let slot key = match Option.bind !final (List.assoc_opt key) with
    | Some (Some slot) -> slot | Some None | None -> fail ("no slot for " ^ key) in
  let sa = slot a and sb = slot b and sc = slot c and sd = slot a_again in
  let describe (s : E3.slot) = Printf.sprintf "%d spp (%d viewports)" s.samples s.viewports in
  check (sa.viewports = 2 && sd.viewports = 2 && sa.samples = sd.samples)
    ("two viewports over one root did not share a slot: " ^ describe sa ^ ", " ^ describe sd);
  check (sb.viewports = 1 && sc.viewports = 1) "a viewport over another root shared a slot";
  check (sa.samples > 80) ("the focused slot did not render every frame: " ^ describe sa);
  check (float sa.samples >= 1.5 *. float sb.samples && float sa.samples >= 1.5 *. float sc.samples)
    (Printf.sprintf "the focused slot did not get more of the budget: %s, %s, %s" (describe sa) (describe sb) (describe sc));
  check (sb.samples > 20 && sc.samples > 20 && abs (sb.samples - sc.samples) * 4 <= max sb.samples sc.samples)
    (Printf.sprintf "the others did not take turns: %s and %s" (describe sb) (describe sc));
  let state = Filename.concat directory "presets/state" in
  if Sys.file_exists state then begin
    Array.iter (fun name -> Sys.remove (Filename.concat state name)) (Sys.readdir state);
    Unix.rmdir state; Unix.rmdir (Filename.dirname state) end;
  Unix.rmdir directory;
  print_endline "workspace shell: a shared slot, the focused slot every frame, the others in turns ok"
