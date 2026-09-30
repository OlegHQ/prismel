(* W10 part B: the editor graph lowers to the shell tree; viewports over other
   instances of the scene get objects of their own; layout gestures are edits of
   the editor graph with history entries; "Restore layout" survives a layout that
   hides everything. *)
open Prismel
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
  check (origin [ 1; 1; 2 ] = Some (Document.Loop "sheet") && origin [ 1; 1 ] = Some (Document.Bound "sheet"))
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

(* ---- through the editor ---- *)

let frame ?(buttons = []) mouse events count = Test_editor_input.frame ~buttons mouse events count
let editor text =
  E3.create ~workspace:(of_text text)
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
  let settle () =
    let deadline = Unix.gettimeofday () +. 20. in
    let busy line = String.starts_with ~prefix:"Cooking" line || String.starts_with ~prefix:"Waiting" line
      || has line "skipping frames" in
    while busy (dump_line !e "cook") do
      if Unix.gettimeofday () > deadline then fail "the editor did not cook";
      Unix.sleepf 0.005; step []
    done in
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
  click (float (hx + 30), float (hy + 22 + 12));
  step [];
  check (E3.undo_label !e = depth) "a looped panel did not change the graph";
  settle ();
  check (has (dump_line !e "cook") "comes from a loop in sheet") ("the status names the loop: " ^ dump_line !e "cook");
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
  step [ key Input.Space; ch 'o'; ch 'l' ]; step [];
  check (E3.undo_label !e = Some "Retype panel" && has (source !e) "(ui/list") "Space o l retyped it to a list"

let run_frame_key () =
  (* the graph pane's keys reach the document: Shift-G frames the walked-to node (layout data, one entry);
     the rosette is entered as in test_text_pane's W9 scenario *)
  Unix.putenv "PRISMEL_MAX_FRAMES" "40";
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
    e := E3.update !e f;
    Unix.sleepf 0.002
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

(* the frame draws one 3D layer per viewport, each over its own scene instance *)
let run_views () =
  let e = ref (editor (case "variations")) in
  let deadline = Unix.gettimeofday () +. 20. in
  let rec settle count =
    e := E3.update !e (frame (450., 300.) [] count);
    if List.length (E3.objects !e) >= 1 && Option.is_some (E3.prepared !e) && count > 10 then ()
    else if Unix.gettimeofday () > deadline then fail "the editor did not cook"
    else (Unix.sleepf 0.005; settle (count + 1)) in
  settle 1;
  for c = 200 to 230 do e := E3.update !e (frame (450., 300.) [] c); Unix.sleepf 0.005 done;
  let scene = E3.scene !e (frame (450., 300.) [] 231) in
  match Scene.Private.stage_native ~width:900 ~height:640 scene with
  | Error m -> fail m
  | Ok staged ->
      let viewports = List.length (List.filter (function Scene.Private.Scene3_layer _ -> true | _ -> false) staged.layers) in
      check (viewports = 4) (Printf.sprintf "four viewports draw four 3D layers, got %d" viewports)

let run () = run_lowering (); run_ops (); run_panel_keys (); run_frame_key (); run_editor (); run_restore (); run_views ()

(* Native: a real window draws Variations' four viewports, each its own scene instance (the
   frame's 3D layers were once cached per frame, so only the first drew). *)
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
  Unix.rmdir directory
