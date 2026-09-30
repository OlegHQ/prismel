(* W7: the workspace text pane.  Selection-scoped text (closure and marked
   span), then the pane driven through the editor: draft, Check & apply,
   Discard, an invalid draft (document unchanged, error at its line) and undo
   labels. *)
module T = Prismel_editor.Private.Text_pane

let fail message = failwith ("test_text_pane: " ^ message)
let check condition message = if not condition then fail message
let case name = In_channel.with_open_bin
  (Filename.concat "../specification/workspace/cases" (name ^ ".lisp")) In_channel.input_all
let source name = match Flow.Syntax.parse (case name) with
  | Ok forms -> forms | Error d -> fail (Flow.Diagnostic.to_string d)

let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0
let marked (shown : T.shown) = match shown.mark with
  | Some (a, b) -> String.sub shown.text a (b - a) | None -> fail "nothing marked"

let replace text ~from ~by =
  let n = String.length from in
  let rec at i = if i + n > String.length text then fail ("no " ^ from)
    else if String.sub text i n = from then i else at (i + 1) in
  let i = at 0 in
  String.sub text 0 i ^ by ^ String.sub text (i + n) (String.length text - i - n)

let selection_text () =
  let src = source "sunflower" in
  let sel path = T.make_shown src "sunflower" (Some path) T.Selection in
  (* a binding inside a loop: its top-level ancestor, no unrelated bindings *)
  let s = sel [ "sunflower"; "seeds_each"; "r" ] in
  check (contains s.text "(let* [seeds_each (for [i (range seeds)]") "sunflower closure lost the ancestor";
  check (not (contains s.text "head")) "sunflower closure kept a downstream binding";
  check (not (contains s.text "(graph")) "the closure is a let*, not the graph";
  check (contains s.text "inputs seeds, spread") "the closure names the inputs it reads";
  check (marked s = "r (* spread (sqrt i))") ("marked " ^ marked s);
  check (s.binding = Some ([ "sunflower"; "seeds_each"; "r" ], "(* spread (sqrt i))")) "binding text";
  (* a binding that reads another: the upstream closure comes with it *)
  let s = sel [ "sunflower"; "head" ] in
  check (contains s.text "with 1 upstream binding") "head has one upstream binding";
  check (contains s.text "seeds_each (for" && contains s.text "head (sop/merge seeds_each)") "head closure";
  check (marked s = "head (sop/merge seeds_each)") "head mark";
  (* the marked text is where the printer put it: printing again finds it *)
  let bloom = source "bloom" in
  let sel path = T.make_shown bloom "flower" (Some path) T.Selection in
  let s = sel [ "flower"; "ring"; "leaf" ] in
  check (marked s = "leaf (petal :length (+ 0.9 wobble) :width 0.22)") ("bloom leaf mark " ^ marked s);
  check (contains s.text "ring (for" && not (contains s.text "bloom (sop/merge")
    && not (contains s.text "heart")) "bloom closure of ring is the loop alone";
  let s = sel [ "flower"; "result" ] in
  check (contains s.text "bloom (sop/merge ring)" && contains s.text "heart (sop/uv_sphere"
    && contains s.text "ring (for" && contains s.text "with 3 upstream bindings") "bloom result closure";
  check (marked s |> fun m -> String.length m > 0 && String.sub m 0 6 = "result") "bloom result mark";
  (* no selection: the whole graph, nothing marked; Graph marks the selection *)
  let s = T.make_shown bloom "flower" None T.Selection in
  check (contains s.text "(graph flower" && s.mark = None && s.binding = None) "unselected shows the graph";
  let g = T.make_shown bloom "flower" (Some [ "flower"; "ring"; "leaf" ]) T.Graph in
  check (contains g.text "(graph flower" && contains g.text "heart" && g.mark <> None) "graph tab";
  check (not (contains g.text "(defn petal")) "the graph tab shows the active graph only";
  let d = T.make_shown bloom "flower" None T.Document in
  check (contains d.text "(defn petal" && contains d.text "(graph world") "document tab is the whole workspace";
  (* an error's line: a position, else the span *)
  let d = Flow.Diagnostic.error ~position:{ line = 4; col = 2 } ~code:"E_X" "x" in
  check (T.line_of "a\nb\nc\nd" d = Some 4) "line from position";
  let d = Flow.Diagnostic.error ~span:{ start = 4; finish = 5 } ~code:"E_X" "x" in
  check (T.line_of "a\nb\nc\nd" d = Some 3) "line from span"

let frame ?(mouse = (450., 320.)) ?(keys = []) count events : Prismel.Frame.t = {
  width = 900; height = 640; size = 900, 640;
  drawable_width = 900; drawable_height = 640; drawable_size = 900, 640;
  pixel_scale = 1., 1.; time = float count /. 60.; dt = 1. /. 60.;
  fps = 60.; count; mouse; mouse_delta = 0., 0.; keys; mouse_buttons = []; events }

module E = Prismel_editor.Editor3

let editor_text () =
  let open Prismel in
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  let workspace = Prismel_editor.Workspace_doc.of_text catalog (case "sunflower") |> Result.get_ok in
  let env = ref (E.create ~workspace
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok) in
  let count = ref 0 in
  let step ?keys ?(at = (450., 320.)) events =
    incr count; env := E.update !env (frame ~mouse:at ?keys !count events) in
  let click (x, y) = step ~at:(x, y) [ Event.MouseMoved (x, y) ];
    step ~at:(x, y) [ Event.MousePressed (Input.LeftButton, (x, y));
      Event.MouseReleased (Input.LeftButton, (x, y)) ] in
  let key k = Event.KeyPressed k and char c = Event.KeyPressed (Input.KeyChar c) in
  let dump () =
    let directory = Filename.temp_dir "prismel-text-pane" "" in
    Fun.protect ~finally:(fun () ->
      Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
      Unix.rmdir directory) (fun () ->
      E.crash_dump !env directory;
      In_channel.with_open_bin (Filename.concat directory "editor.txt") In_channel.input_all) in
  let settle () = for _ = 1 to 40 do step []; Unix.sleepf 0.002 done in
  settle ();
  let gx, gy, _, gh = (E.panes !env (frame 0 [])).graph in
  (* enter the sunflower object, then Space l twice: graph -> list -> text *)
  click (float (gx + 50), float (gy + 100));
  step [ key Input.Home ]; step [ char 'i' ]; settle ();
  step [ key Input.Space; char 'l' ]; step [ key Input.Space; char 'l' ]; step [];
  check (contains (dump ()) "projection: text") ("Space l did not reach the text pane\n" ^ dump ());
  let ws () = E.workspace !env in
  let original = ws () in
  let base = E.undo_label !env in
  let applied = Flow.Lisp.print original.source |> fst in
  let tab_document = float (gx + 8 + 81 + 53 + 20), float (gy + 12) in
  let area = float (gx + 200), float (gy + 24 + 60) in
  let apply = float (gx + 60), float (gy + gh - 36) and discard = float (gx + 170), float (gy + gh - 36) in
  click tab_document;
  check (contains (dump ()) "document tab, draft no") ("Document tab\n" ^ dump ());
  (* typing makes a draft; every other pane keeps the applied document *)
  let type_text text =
    click area;
    step ~keys:[ Input.Meta ] [ char 'a' ];
    step [ Event.TextInput text ] in
  type_text (replace applied ~from:"(seeds : int 240)" ~by:"(seeds : int 100)");
  check (contains (dump ()) "draft yes") ("a draft was not kept\n" ^ dump ());
  check (ws () == original && E.undo_label !env = base) "a draft changed the document";
  (* Discard reverts the draft *)
  click discard;
  check (contains (dump ()) "draft no") "Discard kept the draft";
  check (ws () == original) "Discard changed the document";
  (* an invalid draft stays; the document does not change; the error is at its line *)
  let bad = replace applied ~from:"(sqrt i)" ~by:"(sqrt nosuch)" in
  let line = 1 + List.length (String.split_on_char '\n'
    (String.sub bad 0 (let n = String.length "(sqrt nosuch)" in
       let rec at i = if String.sub bad i n = "(sqrt nosuch)" then i else at (i + 1) in at 0))) - 1 in
  type_text bad;
  click apply;
  let text = dump () in
  check (contains text "draft yes") ("an invalid draft left the pane\n" ^ text);
  check (contains text (Printf.sprintf "error at line %d:" line)) (Printf.sprintf "error not at line %d\n%s" line text);
  check (ws () == original && E.undo_label !env = base) "an invalid apply changed the document";
  (* typing clears the marks: they cannot drift away from the line they named *)
  click area; step [ Event.TextInput "\n" ];
  check (not (contains (dump ()) ", error")) ("an edit left its stale error mark\n" ^ dump ());
  click apply;
  check (contains (dump ()) "error at line") "the next apply marks its line again";
  (* a valid edit applies atomically, as one history entry *)
  type_text (replace applied ~from:"(seeds : int 240)" ~by:"(seeds : int 100)");
  click apply;
  check (contains (dump ()) "draft no") ("Check & apply kept the draft\n" ^ dump ());
  check (ws () != original && contains (Flow.Lisp.print (ws ()).source |> fst) "(seeds : int 100)")
    "Check & apply did not change the document";
  check (E.undo_label !env = Some "Edit text") "the history label is not Edit text";
  step ~keys:[ Input.Meta ] [ char 'z' ];
  check (Flow.Lisp.print (ws ()).source |> fst = applied) "undo did not restore the text";
  check (E.redo_label !env = Some "Edit text") "redo label";
  (* the Graph tab edits one graph through the same apply; Command-Enter is the button *)
  let original = ws () in
  let tab_graph = float (gx + 8 + 81 + 20), float (gy + 12) in
  click tab_graph;
  check (contains (dump ()) "graph tab, draft no") ("Graph tab\n" ^ dump ());
  let graph_text = (Prismel_editor.Private.Text_pane.make_shown original.source "sunflower" None Graph).text in
  check (contains graph_text "(graph sunflower") "the Graph tab does not show the graph";
  click area;
  step ~keys:[ Input.Meta ] [ char 'a' ];
  step [ Event.TextInput (replace graph_text ~from:"(seeds : int 240)" ~by:"(seeds : int 77)") ];
  check (contains (dump ()) "graph tab, draft yes") ("the Graph tab kept no draft\n" ^ dump ());
  check (ws () == original) "a Graph draft changed the document";
  step ~keys:[ Input.Meta ] [ key Input.Enter ];
  check (contains (dump ()) "graph tab, draft no") ("Command-Enter did not apply\n" ^ dump ());
  check (contains (Flow.Lisp.print (ws ()).source |> fst) "(seeds : int 77)"
         && E.undo_label !env = Some "Edit text") "the Graph tab's apply is not one Edit text entry";
  (* a graph that does not check stays in the pane, the document does not change *)
  let applied_graph = ws () in
  click area;
  step ~keys:[ Input.Meta ] [ char 'a' ];
  step [ Event.TextInput (replace graph_text ~from:"(sqrt i)" ~by:"(sqrt nosuch)") ];
  step ~keys:[ Input.Meta ] [ key Input.Enter ];
  check (contains (dump ()) "graph tab, draft yes, error") ("a refused graph left the pane\n" ^ dump ());
  check (ws () == applied_graph) "a refused Graph apply changed the document"

(* A checker error from a binding apply is marked on the binding text's line, and typing clears it. *)
let editor_binding () =
  let open Prismel in
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  let workspace = Prismel_editor.Workspace_doc.of_text catalog (case "sunflower") |> Result.get_ok in
  let env = ref (E.create ~workspace
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok) in
  let count = ref 0 in
  let step ?keys ?(at = (450., 320.)) events =
    incr count; env := E.update !env (frame ~mouse:at ?keys !count events) in
  let click (x, y) = step ~at:(x, y) [ Event.MouseMoved (x, y) ];
    step ~at:(x, y) [ Event.MousePressed (Input.LeftButton, (x, y));
      Event.MouseReleased (Input.LeftButton, (x, y)) ] in
  let key k = Event.KeyPressed k and char c = Event.KeyPressed (Input.KeyChar c) in
  let dump () =
    let directory = Filename.temp_dir "prismel-text-pane" "" in
    Fun.protect ~finally:(fun () ->
      Array.iter (fun f -> Sys.remove (Filename.concat directory f)) (Sys.readdir directory);
      Unix.rmdir directory) (fun () ->
      E.crash_dump !env directory;
      In_channel.with_open_bin (Filename.concat directory "editor.txt") In_channel.input_all) in
  let settle () = for _ = 1 to 40 do step []; Unix.sleepf 0.002 done in
  settle ();
  let gx, gy, _, gh = (E.panes !env (frame 0 [])).graph in
  click (float (gx + 50), float (gy + 100));
  step [ key Input.Home ]; step [ char 'i' ]; settle ();
  (* walk to a binding, then show the text pane: its Selection tab edits that binding *)
  for _ = 1 to 4 do step [ key Input.ArrowRight ] done;
  step [ key Input.Space; char 'l' ]; step [ key Input.Space; char 'l' ]; step [];
  check (contains (dump ()) "projection: text") "Space l did not reach the text pane";
  click (float (gx + 100), float (gy + gh - 60));
  step ~keys:[ Input.Meta ] [ char 'a' ];
  step [ Event.TextInput "(sqrt nosuch)" ];
  click (float (gx + 60), float (gy + gh - 36));
  check (contains (dump ()) "error at line 1:") ("a binding error has no line\n" ^ dump ());
  click (float (gx + 100), float (gy + gh - 60));
  step [ Event.TextInput " " ];
  check (not (contains (dump ()) ", error")) "typing in the binding left its error mark"

(* W9 through the editor: the 1400x800 window of sketches/flow_workspace, Rosette, the graph
   pane zoomed once (frame 12) so the cards sit where FLOW_W9 clicks them: the B flag of
   `soft`, its note in the inspector, and the make-macro dialog (m, Create macro).  The frame's
   mouse stays at the window centre (the pointer is the events'), as the export driver's does. *)
let editor_w9 () =
  let open Prismel in
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  let scenario script =
    Unix.putenv "PRISMEL_MAX_FRAMES" "40";
    let workspace = Prismel_editor.Workspace_doc.of_text catalog (case "rosette") |> Result.get_ok in
    let env = ref (E.create ~workspace
        ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
          |> Result.map_error Pdk.Error.to_string)
        ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok) in
    let mouse = ref (640., 360.) in
    for n = 1 to 40 do
      let click p =
        [ Event.MouseMoved p; Event.MousePressed (Input.LeftButton, p); Event.MouseReleased (Input.LeftButton, p) ] in
      let events = match List.assoc_opt n script with
        | Some events -> events click
        | None -> match n with
          | 4 -> click (900., 300.) | 6 -> [ Event.KeyPressed Input.ArrowDown ]
          | 8 -> [ Event.KeyPressed (Input.KeyChar 'i') ]
          | 12 -> [ Event.MouseMoved (780., 380.); Event.MouseScrolled (0., 9.) ]
          | 16 -> click (960., 466.)
          | _ -> [] in
      let f : Frame.t = { width = 1400; height = 800; size = 1400, 800; drawable_width = 1400;
        drawable_height = 800; drawable_size = 1400, 800; pixel_scale = 1., 1.;
        time = float n /. 60.; dt = 1. /. 60.; fps = 60.; count = n; mouse = !mouse;
        mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events } in
      env := E.update !env f;
      Unix.sleepf 0.002
    done;
    Unix.sleepf 0.05;
    let ws = E.workspace !env in
    Flow.Lisp.print ws.source |> fst, E.undo_label !env in
  let untouched, _ = scenario [] in
  check (contains untouched "^:bypass (sop/subdivide inner") "soft starts bypassed";
  (* the flag *)
  let text, label = scenario [ 22, (fun click -> click (1044., 236.)) ] in
  check (not (contains text "^:bypass") && label = Some "Bypass")
    (Printf.sprintf "the B flag: %s, bypass %b" (Option.value label ~default:"-") (contains text "^:bypass"));
  (* the inspector note: click the field, type, Enter *)
  let text, label = scenario [ 22, (fun click -> click (1075., 236.)); 26, (fun click -> click (1290., 158.));
    28, (fun _ -> [ Event.KeyPressed (Input.KeyChar 'a') ]); 30, (fun _ -> [ Event.TextInput "a fresh note" ]);
    32, (fun _ -> [ Event.KeyPressed Input.Enter ]) ] in
  check (contains text "; a fresh note" && label = Some "Note") ("the note edit: " ^ Option.value label ~default:"-");
  (* the dialog: m over the selection, then Create macro *)
  let text, label = scenario [ 22, (fun click -> click (1075., 236.));
    26, (fun _ -> [ Event.KeyPressed (Input.KeyChar 'm') ]); 30, (fun click -> click (700., 463.)) ] in
  check (contains text "(defmacro soft_tpl [p1 inner]" && label = Some "Make macro")
    ("the make-macro dialog: " ^ Option.value label ~default:"-")

let run () =
  selection_text ();
  editor_text ();
  editor_binding ();
  editor_w9 ();
  print_endline "text pane tests passed"
