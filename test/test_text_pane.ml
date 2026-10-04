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
  check (s.key = [ "sunflower"; "seeds_each"; "r" ]) "the selection's key";
  check ((match T.binding src [ "sunflower"; "seeds_each"; "r" ] with
          | Some (_, v) -> String.trim (fst (Flow.Lisp.print [ v ])) | None -> "")
         = "(* spread (sqrt i))") "binding text";
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
  check (contains s.text "(graph flower" && s.mark = None && s.key = [ "flower" ]) "unselected shows the graph";
  let g = T.make_shown bloom "flower" (Some [ "flower"; "ring"; "leaf" ]) T.Graph in
  check (contains g.text "(graph flower" && contains g.text "heart" && g.mark <> None) "graph tab";
  check (not (contains g.text "(defn petal")) "the graph tab shows the active graph only";
  let d = T.make_shown bloom "flower" None T.Document in
  check (contains d.text "(defn petal" && contains d.text "(graph world") "document tab is the whole workspace";
  (* the caret in a binding is that binding's path; outside every binding it is none *)
  let offset part = let rec at i = if String.sub g.text i (String.length part) = part then i else at (i + 1) in at 0 in
  check (T.binding_at g (offset "leaf (" + 6) = Some [ "flower"; "ring"; "leaf" ]) "binding_at: a nested binding";
  check (T.binding_at g 0 = None) "binding_at: the header is no binding";
  check (T.binding_at d 5 = None) "binding_at: the Document tab has none";
  (* Command-click, colour chips and the document-aware completions *)
  let module L = Prismel_editor.Private.Lisp_text in
  let sample = "(sop/material geo :material (ref cobalt) :tint \"#ff8000\" :note \"#zzzzzz\")" in
  check (L.ref_at sample 30 = Some "cobalt" && L.ref_at sample 40 = Some "cobalt") "ref_at: inside the form";
  check (L.ref_at sample 5 = None) "ref_at: elsewhere";
  (match L.color_chips sample with
   | [ (a, b, c) ] -> check (String.sub sample a (b - a) = "\"#ff8000\"" && Prismel.Color.to_tuple c = (255, 128, 0, 255)) "color_chips: the literal"
   | _ -> fail "color_chips: only the valid literal");
  let names = { L.materials = [ "cobalt"; "brass" ]; cameras = [ "cam" ]; layouts = [ "View | Graph"; "Lisp" ];
    graphs = [ "cobalt"; "brass"; "shards" ] } in
  let labels text = List.map (fun (c : Pxui.Ui.completion) -> c.label, c.insert)
    (L.complete ~names (L.vocab []) text (String.length text)) in
  check (labels "(sop/material geo :material " = [ "brass", "(ref brass)"; "cobalt", "(ref cobalt)" ]
         || labels "(sop/material geo :material " = [ "cobalt", "(ref cobalt)"; "brass", "(ref brass)" ])
    "completion: :material lists the material graphs";
  check (labels "(scene/root m :camera " = [ "cam", "cam" ]) "completion: :camera lists the cameras";
  check (labels "(ui/switch a b :active " = [ "0 View | Graph", "0"; "1 Lisp", "1" ]) "completion: :active lists the layouts";
  check (List.mem ("shards", "shards") (labels "(sop/material geo :material (ref sh")) "completion: ref offers every graph";
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
  let presets = Filename.temp_dir "prismel-text-presets" "" in
  let env = ref (E.create ~presets ~await:true ~workspace
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
  let settle () = for _ = 1 to 4 do step [] done in
  settle ();
  let gx, gy, _, gh = (E.panes !env (frame 0 [])).graph in
  (* enter the sunflower object, then Space l t: the graph panel shows its text *)
  click (float (gx + 50), float (gy + 100));
  step [ key Input.Home ]; step [ char 'i' ]; settle ();
  step [ key Input.Space; char 'l'; char 't' ]; step [];
  check (contains (dump ()) "projection: text") ("Space l t did not reach the text pane\n" ^ dump ());
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
  check (ws () == applied_graph) "a refused Graph apply changed the document";
  click discard;
  let current_graph = (T.make_shown (ws ()).source "sunflower" None Graph).text in
  type_text (replace current_graph ~from:"(seeds : int 77)" ~by:"(seeds : int 88)");
  step [key Input.Escape]; step ~keys:[Input.Meta] [char 'z'];
  let undone = ws () and undo_label = E.undo_label !env in
  click apply;
  check (ws () == undone && E.undo_label !env = undo_label)
    "an old Graph draft overwrote undo";
  check (contains (dump ()) "draft yes" && contains (dump ()) "E_DRAFT_CONFLICT")
    ("an old Graph draft was not retained as a conflict: " ^ dump ());
  click discard;
  click tab_document;
  type_text (replace (Prismel_editor.Workspace_doc.to_text (ws ()))
    ~from:"(seeds : int 240)" ~by:"(seeds : int 99)");
  env := E.edit !env (Flow_sop.Flow_edit.Set_input_default {form = "sunflower";
    input = "seeds"; value = Flow.Syntax.make (Flow.Syntax.Num "125")}) |> Result.get_ok;
  let host_edited = ws () and host_label = E.undo_label !env in
  click apply;
  check (ws () == host_edited && E.undo_label !env = host_label)
    "an old Document draft overwrote a host edit";
  check (contains (dump ()) "draft yes" && contains (dump ()) "E_DRAFT_CONFLICT")
    ("an old Document draft was not kept as a conflict: " ^ dump ());
  E.close !env; Test_workspace_source.remove_tree presets

(* A checker error from a binding apply is marked on the binding text's line, and typing clears it. *)
let editor_binding () =
  let open Prismel in
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  let workspace = Prismel_editor.Workspace_doc.of_text catalog (case "sunflower") |> Result.get_ok in
  let presets = Filename.temp_dir "prismel-text-presets" "" in
  let env = ref (E.create ~presets ~await:true ~workspace
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
  let settle () = for _ = 1 to 4 do step [] done in
  settle ();
  let gx, gy, _, gh = (E.panes !env (frame 0 [])).graph in
  click (float (gx + 50), float (gy + 100));
  step [ key Input.Home ]; step [ char 'i' ]; settle ();
  (* walk to a binding, then show the text pane: its Selection tab edits the closure shown *)
  for _ = 1 to 4 do step [ key Input.ArrowRight ] done;
  step [ key Input.Space; char 'l'; char 't' ]; step [];
  check (contains (dump ()) "projection: text") "Space l t did not reach the text pane";
  let area = float (gx + 200), float (gy + 24 + 60) and apply = float (gx + 60), float (gy + gh - 36) in
  let type_closure text = click area; step ~keys:[ Input.Meta ] [ char 'a' ]; step [ Event.TextInput text ] in
  let ws () = E.workspace !env in
  let original = ws () in
  (* a binding that does not check: refused, marked on line 1 *)
  type_closure "(let* [head (sop/merge nosuch)] head)";
  click apply;
  check (contains (dump ()) "error at line 1:") ("a refused closure has no line\n" ^ dump ());
  check (ws () == original) "a refused closure changed the document";
  click area; step [ Event.TextInput " " ];
  check (not (contains (dump ()) ", error")) "typing in the closure left its error mark";
  (* a name that is not a root binding is refused with its name *)
  type_closure "(let* [nosuch 1] nosuch)";
  click apply;
  check (contains (dump ()) "nosuch is not a binding of sunflower") ("an unknown binding\n" ^ dump ());
  (* a changed binding is written: one history entry *)
  type_closure "(let* [head (sop/merge seeds_each seeds_each)] seeds_each)";
  click apply;
  check (E.undo_label !env = Some "Edit text" && contains (fst (Flow.Lisp.print (ws ()).source)) "(sop/merge seeds_each seeds_each)")
    ("the closure edit was not applied\n" ^ dump ());
  let before = ws () in
  let printed_binding source path = Option.map (fun (_, v) -> fst (Flow.Lisp.print [v])) (T.binding source path) in
  let omitted = printed_binding original.source ["sunflower"; "seeds_each"] in
  check (omitted <> None && printed_binding before.source ["sunflower"; "seeds_each"] = omitted)
    "Selection removed or changed an omitted binding";
  let refuse text message =
    type_closure text; click apply;
    check (ws () == before) "refused Selection edit changed the document";
    check (contains (dump ()) message) ("missing Selection refusal: " ^ dump ()) in
  refuse "(let* [head (sop/box)] head)" "result must stay unchanged";
  refuse "(let* [head (sop/box) head (sop/box)] seeds_each)" "Duplicate binding";
  (* seeds_each changes from a list to geometry, together with its consumer.
     Neither replacement checks against the old sibling binding. *)
  type_closure "(let* [seeds_each (sop/box) head (sop/transform seeds_each)] seeds_each)";
  click apply;
  let after = ws () in
  check (after != before && contains (dump ()) "draft no")
    ("coherent cross-binding type change was refused: " ^ dump ());
  check (T.binding after.source ["sunflower"; "seeds_each"] <> T.binding before.source ["sunflower"; "seeds_each"])
    "producer was not patched";
  let reloaded = Prismel_editor.Workspace_doc.of_text catalog
    (Prismel_editor.Workspace_doc.to_text after) |> Result.get_ok in
  check (printed_binding reloaded.source ["sunflower"; "head"] = printed_binding after.source ["sunflower"; "head"])
    "Selection patch did not survive serialized reload";
  click (float (gx + 30), float (gy + gh - 70));
  step [key Input.Escape]; step ~keys:[Input.Meta] [char 'z'];
  check (ws () == before) "Selection's related edits were not one undo entry";
  type_closure "(let* [head (sop/merge seeds_each)] seeds_each)";
  env := E.edit !env (Flow_sop.Flow_edit.Set_arg {node = ["sunflower"; "head"];
    key = Whole; sub = []; value = (match Flow.Syntax.parse "(sop/merge seeds_each seeds_each seeds_each)" with
      | Ok [form] -> form | _ -> fail "test expression")}) |> Result.get_ok;
  let host_edited = ws () and host_label = E.undo_label !env in
  click apply;
  check (ws () == host_edited && E.undo_label !env = host_label)
    "an old Selection draft overwrote a host edit";
  check (contains (dump ()) "draft yes" && contains (dump ()) "E_DRAFT_CONFLICT")
    ("an old Selection draft was not kept as a conflict: " ^ dump ());
  E.close !env; Test_workspace_source.remove_tree presets

(* The editor's Lisp as the text area's language: indentation and bracket pairs. *)
let lisp_text () =
  let module L = Prismel_editor.Private.Lisp_text in
  let indent text = String.length (L.indent text (String.length text)) in
  check (indent "(let* [a 1" = 7) "a vector's elements line up under the first";
  check (indent "(graph g :context sop" = 2) "a body form indents two in";
  check (indent "  (let* [a 1]" = 4) "let* is a body form";
  check (indent "(sop/box :size 1" = 9) "a call's arguments line up under the first";
  check (indent "(sop/merge" = 1) "a call broken after its head indents one in";
  check (indent "(let* [a 1] (+ 1 2)) " = 0) "a closed form indents nothing";
  check (indent "(+ 1 ; comment (\n" = 3) "an open bracket in a comment does not count";
  check (indent "(str \"(\" " = 5) "an open bracket in a string does not count";
  check (L.brackets "(a [b] c)" = [ (0, 8); (3, 5) ] || L.brackets "(a [b] c)" = [ (3, 5); (0, 8) ]) "matched pairs";
  check (L.brackets "(a ]" = []) "a mismatched closer pairs with nothing";
  let colors = (L.language Pxui.Theme.default).colorize "(sop/box :size 1.5 \"s\" ; c" in
  check (List.length colors = 6) (Printf.sprintf "head, keyword, number, string, comment and the paren: %d runs" (List.length colors));
  (* completions over the catalog: ranked, for the token at the caret *)
  let vocab = L.vocab (List.map Flow_sop.Catalog.descriptor Sop_catalog.Editor.factories
    @ Editor_document.Contexts.descriptors) in
  let labels text = List.map (fun (c : Pxui.Ui.completion) -> c.label) (L.complete vocab text (String.length text)) in
  let first text = match labels text with l :: _ -> l | [] -> "" in
  let doc = "(workspace w (graph g :context sop [(depth : int 5)] (let* [ring (sop/box :size_x 2) b (" in
  (* a head: the context's kinds first, prefix matches before fuzzy ones *)
  check (first (doc ^ "sop/tra") = "sop/transform") ("head completion: " ^ first (doc ^ "sop/tra"));
  check (List.for_all (fun l -> String.length l >= 7 && String.sub l 0 7 = "sop/tra"
      || Pxui.Ui.fuzzy_match ~query:"sop/tra" l) (labels (doc ^ "sop/tra"))) "every head completion matches";
  check (List.mem "let*" (labels (doc ^ "le")) && List.mem "sop/merge" (labels (doc ^ "me")))
    "forms and kinds complete at a head";
  (* the empty head lists the kinds the text uses first *)
  check (first doc = "sop/box") ("the used kind ranks first: " ^ first doc);
  (* a keyword: the kind's parameters, a vec3 group before its components, present ones left out *)
  check (first (doc ^ "sop/box :si") = ":size") ("keyword completion: " ^ first (doc ^ "sop/box :si"));
  check (List.mem ":size_x" (labels (doc ^ "sop/box :si"))) "the group's components follow";
  check (not (List.mem ":size" (labels (doc ^ "sop/box :size [1 1 1] :s")))) "a keyword already given is left out";
  check (first (doc ^ "sop/transform ring :rot") = ":rotate") ("rotate group: " ^ first (doc ^ "sop/transform ring :rot"));
  (* a choice after its keyword, with or without the opening quote *)
  check (List.mem "Quads" (labels (doc ^ "sop/box :connectivity \"Qu")) && List.mem "Quads" (labels (doc ^ "sop/box :connectivity Qu")))
    "choices complete after their keyword";
  (match L.complete vocab (doc ^ "sop/box :connectivity \"Qu") (String.length doc + 24) with
   | c :: _ -> check (c.insert = "\"Quads\"") ("a choice inserts its quotes: " ^ c.insert)
   | [] -> fail "no choice");
  (* an argument: the bindings and inputs in scope before constants; naming a new binding offers nothing *)
  check (first (doc ^ "sop/transform ri") = "ring") ("binding completion: " ^ first (doc ^ "sop/transform ri"));
  check (List.mem "depth" (labels (doc ^ "sop/transform ring :uniform_scale de"))) "graph inputs complete";
  check (List.mem "t" (labels (doc ^ "sop/transform ring :uniform_scale t"))) "t completes";
  check (labels "(workspace w (graph g :context sop [] (let* [ri" = []) "a new binding's name is not completed";
  check (labels (doc ^ "sop/box :size 1") = []) "a number completes nothing";
  (* the operator's keyword and the context keyword *)
  check (List.mem ":closed" (labels (doc ^ "sop/curve ring :cl"))) "an operator's keyword";
  check (first "(workspace w (graph g :context sc" = "scene") "contexts after :context";
  (* descriptions *)
  let describe text at = match L.describe vocab text at with Some (_, _, d) -> d | None -> "" in
  let index_of part = let n = String.length part in
    let rec at i = if String.sub doc i n = part then i else at (i + 1) in at 0 in
  check (contains (describe doc (index_of "sop/box" + 2)) "Box") ("a kind's description: " ^ describe doc (index_of "sop/box" + 2));
  let at = index_of ":size_x" + 3 in
  check (contains (describe doc at) "Size X") ("a parameter's description: " ^ describe doc at);
  check (contains (describe (doc ^ "sop/box :size [1 1 1])") (String.length doc + 10)) "Size")
    ("a group's description: " ^ describe (doc ^ "sop/box :size [1 1 1])") (String.length doc + 10));
  check (contains (describe doc 15) "network") ("graph form: " ^ describe doc 15);
  check (describe doc (String.length doc - 1) = "") "an open paren has no description";
  check (contains (describe (doc ^ "sop/transform ring)") (String.length doc + 15)) "let* binding")
    ("a binding's description: " ^ describe (doc ^ "sop/transform ring)") (String.length doc + 15));
  check (contains (describe doc (index_of "int 5" + 4)) "drag") ("a number's description: " ^ describe doc (index_of "int 5" + 4));
  (* numbers *)
  check (L.number_at "(sop/box :size_x 1.25 :x 3)" 19 = Some (17, 21)) "the number at a byte";
  check (L.number_at "(sop/box :size_x 1.25 :x 3)" 16 = None) "a space is no number";
  (* parinfer: closers follow indentation, the printed workspaces are already in that shape *)
  let p text = fst (L.parinfer_text text 0) in
  List.iter (fun name ->
    let printed = fst (Flow.Lisp.print (source name)) in
    check (p printed = printed) (name ^ ": parinfer changed the printed workspace")) [ "bloom"; "sunflower"; "rosette" ];
  check (p "(a\n  b" = "(a\n  b)") "an open form closes at its last line";
  check (p "(a\nb)" = "(a)\nb") "a dedented line closes the form before it";
  check (p "(a (b)\n  c)" = "(a (b)\n  c)") "a closer in the middle of a line stays";
  check (p "(a \"(\" ; )\n  b" = "(a \"(\" ; )\n  b)") "strings and comments are not brackets";
  check (p "(a]" = "(a)") "a closer matching nothing is replaced";
  check (p "(let* [a 1\n       b 2]\n  a)" = "(let* [a 1\n       b 2]\n  a)") "a vector over two lines";
  check (p "(a\n  )" = "(a)\n") "a line of closers alone becomes blank";
  check (L.parinfer_text "(a \n  )" 6 = ("(a) \n  ", 7)) "Enter before a closer keeps the caret's indentation";
  check (L.parinfer_text "(a" 2 = ("(a)", 2)) "the caret stays before an inferred closer";
  check (L.parinfer_text "(a\nb)" 4 = ("(a)\nb", 5)) "the caret follows a moved closer";
  check (L.parinfer_text "(a  )" 3 = ("(a )", 3)) "a blank typed before a closer survives on the caret's line";
  check ((L.language ~parinfer:true Pxui.Theme.default).rewrite <> None
         && (L.language Pxui.Theme.default).rewrite = None) "the language rewrites only with parinfer on"

(* W9 through the editor: the 1400x800 window of sketches/flow_workspace, Rosette, the graph
   pane zoomed once (frame 12) so the cards sit where FLOW_W9 clicks them: the B flag of
   `soft`, its note in the inspector, and the make-macro dialog (m, Create macro).  The frame's
   mouse stays at the window centre (the pointer is the events'), as the export driver's does. *)
let editor_w9 () =
  let open Prismel in
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  let scenario script =
    let workspace = Prismel_editor.Workspace_doc.of_text catalog (case "rosette") |> Result.get_ok in
    let presets = Filename.temp_dir "prismel-text-presets" "" in
  let env = ref (E.create ~presets ~await:true ~workspace
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
      env := E.update !env f
    done;
    let ws = E.workspace !env in
    Flow.Lisp.print ws.source |> fst, E.undo_label !env in
  let untouched, _ = scenario [] in
  check (contains untouched "^:bypass (sop/subdivide inner") "soft starts bypassed";
  (* the flag *)
  let text, label = scenario [ 22, (fun click -> click (1044., 236.)) ] in
  check (not (contains text "^:bypass") && label = Some "Bypass")
    (Printf.sprintf "the B flag: %s, bypass %b" (Option.value label ~default:"-") (contains text "^:bypass"));
  (* the inspector's Bypass toggle is the flag's request too *)
  let text, label = scenario [ 22, (fun click -> click (1075., 236.)); 26, (fun click -> click (1236., 213.)) ] in
  check (not (contains text "^:bypass") && label = Some "Bypass")
    (Printf.sprintf "the inspector's Bypass toggle: %s" (Option.value label ~default:"-"));
  (* and its name field is the pane's rename *)
  let text, label = scenario [ 22, (fun click -> click (1075., 236.)); 26, (fun click -> click (1290., 187.));
    28, (fun _ -> [ Event.KeyPressed (Input.KeyChar 'a') ]); 30, (fun _ -> [ Event.TextInput "gentle" ]);
    32, (fun _ -> [ Event.KeyPressed Input.Enter ]) ] in
  check (contains text "gentle ^:bypass (sop/subdivide" && not (contains text "soft ^:bypass") && label = Some "Rename")
    ("the inspector's name field: " ^ Option.value label ~default:"-");
  (* a graph input's default is edited in the inspector too *)
  let text, label = scenario [ 22, (fun click -> click (700., 240.)); 26, (fun click -> click (1290., 98.));
    28, (fun _ -> [ Event.KeyPressed (Input.KeyChar 'a') ]); 30, (fun _ -> [ Event.TextInput "7" ]);
    32, (fun _ -> [ Event.KeyPressed Input.Enter ]) ] in
  check (contains text "(petals : int 7)" && label = Some "Input default")
    ("the inspector's input default: " ^ Option.value label ~default:"-");
  (* the inspector note: click the field, type, Enter *)
  let text, label = scenario [ 22, (fun click -> click (1075., 236.)); 26, (fun click -> click (1290., 158.));
    28, (fun _ -> [ Event.KeyPressed (Input.KeyChar 'a') ]); 30, (fun _ -> [ Event.TextInput "a fresh note" ]);
    32, (fun _ -> [ Event.KeyPressed Input.Enter ]) ] in
  check (contains text "; a fresh note" && label = Some "Note") ("the note edit: " ^ Option.value label ~default:"-");
  (* the dialog: m over the selection, then Create macro *)
  let text, label = scenario [ 22, (fun click -> click (1075., 236.));
    26, (fun _ -> [ Event.KeyPressed (Input.KeyChar 'm') ]); 30, (fun click -> click (700., 463.)) ] in
  check (contains text "(defmacro soft_tpl [p1 inner]" && label = Some "Make macro")
    ("the make-macro dialog: " ^ Option.value label ~default:"-");
  (* Enter in the name field creates the macro too *)
  let text, label = scenario [ 22, (fun click -> click (1075., 236.));
    26, (fun _ -> [ Event.KeyPressed (Input.KeyChar 'm') ]); 30, (fun click -> click (700., 433.));
    34, (fun _ -> [ Event.KeyPressed Input.Enter ]) ] in
  check (contains text "(defmacro soft_tpl [p1 inner]" && label = Some "Make macro")
    ("Enter in the make-macro dialog: " ^ Option.value label ~default:"-")

(* Scrubbing :active in the Document text: dragging the number after [:active] sideways switches
   the layout on every frame of the drag and the whole drag is one "Edit text" entry. *)
let editor_active_scrub () =
  let open Prismel in
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  let text = {|(workspace sw
  (graph g :context sop (sop/box))
  (graph scene :context scene (scene/merge (scene/geometry (ref g))))
  (graph editor :context editor
    (let* [wide (ui/split-at "vertical" 0.12 (ui/graph) (ui/lisp))
           split (ui/split-at "horizontal" 0.5 (ui/graph) (ui/inspector))
           three (ui/split-at "horizontal" 0.3 (ui/inspector) (ui/graph))]
      (ui/workspace (ui/switch wide split three :active 0)))))|} in
  let workspace = Prismel_editor.Workspace_doc.of_text catalog text |> Result.get_ok in
  let presets = Filename.temp_dir "prismel-text-presets" "" in
  let env = ref (E.create ~presets ~await:true ~workspace
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok) in
  let count = ref 0 and mouse = ref (450., 320.) in
  let step ?(buttons = []) ?(keys = []) events =
    incr count;
    env := E.update !env { (frame ~mouse:!mouse ~keys !count events) with mouse_buttons = buttons } in
  let at ?buttons point events = mouse := point; step ?buttons events in
  let char c = Event.KeyPressed (Input.KeyChar c) in
  for _ = 1 to 4 do step [] done;
  let gx, gy, _, gh = (E.panes !env (frame 0 [])).graph in
  (* the Lisp panel sits under the graph: the status strip (28 points), a splitter of one point and
     the 22-point header *)
  let gy = gy + gh + 28 + 1 + 22 in
  (* the Document tab *)
  let tab = float (gx + 8 + 81 + 53 + 20), float (gy + 12) in
  at tab [ Event.MouseMoved tab ];
  at tab [ Event.MousePressed (Input.LeftButton, tab); Event.MouseReleased (Input.LeftButton, tab) ]; step [];
  let printed = Flow.Lisp.print (E.workspace !env).source |> fst in
  let lines = String.split_on_char '\n' printed in
  let line = Option.get (List.find_index (fun l -> contains l ":active 0") lines) in
  let col = let l = List.nth lines line in
    let rec find i = if String.sub l i 9 = ":active 0" then i + 8 else find (i + 1) in find 0 in
  (* the digit sits [col] glyphs into its line: the gutter (12 and three glyphs), 8 points of padding,
     the line's indentation; a press within half a glyph of its left edge is on it *)
  let char_w = 6.95 in
  let number = float gx +. 12. +. 3. *. char_w +. 8. +. float col *. char_w, float gy +. 24. +. float line *. 24. in
  let before = E.workspace !env and history = E.undo_label !env in
  let nx, ny = number in
  at number [ Event.MouseMoved number ];
  at number ~buttons:[ Input.LeftButton ] [ Event.MousePressed (Input.LeftButton, number) ];
  at (nx +. 10., ny) ~buttons:[ Input.LeftButton ] [ Event.MouseMoved (nx +. 10., ny) ];
  check (contains (Flow.Lisp.print (E.workspace !env).source |> fst) ":active 2")
    ("a drag of ten points did not set :active 2 live: " ^ (Flow.Lisp.print (E.workspace !env).source |> fst));
  at (nx +. 10., ny) [ Event.MouseReleased (Input.LeftButton, (nx +. 10., ny)) ]; step [];
  check (E.undo_label !env = Some "Edit text") ("the drag is one Edit text entry: " ^ Option.value ~default:"-" (E.undo_label !env));
  step ~keys:[ Input.Meta ] [ char 'z' ];
  check (E.workspace !env == before && E.undo_label !env = history) "one undo returns the whole drag";
  E.close !env

(* A graph held by [y] and put on the text pane: [(ref a)] is inserted at the byte under the pointer
   and the text must check (Graph tab: one Set_graph; Document tab: the whole text), else refused
   with the checker's words; an unapplied draft refuses it too. *)
let editor_text_drop () =
  let open Prismel in
  let catalog = Editor_document.Contexts.catalog ~version:Flow_sop.Manifest.version
      Sop_catalog.Editor.factories |> Result.get_ok in
  let text = {|(workspace drop
  (graph a :context sop (sop/box))
  (graph b :context sop (sop/merge (sop/box)))
  (graph scene :context scene (scene/merge (scene/geometry (ref b))))
  (graph editor :context editor
    (ui/workspace (ui/split-at "vertical" 0.12 (ui/graph) (ui/lisp)))))|} in
  let workspace = Prismel_editor.Workspace_doc.of_text catalog text |> Result.get_ok in
  let presets = Filename.temp_dir "prismel-text-presets" "" in
  let env = ref (E.create ~presets ~await:true ~workspace
      ~prepare:(fun _ output -> Pdk_prismel.Prismel_mesh.to_mesh output.Procedural.Session.geometry
        |> Result.map_error Pdk.Error.to_string)
      ~scene3:(fun _ mesh -> Scene3.create [ Scene3.mesh mesh ]) () |> Result.get_ok) in
  let count = ref 0 and mouse = ref (450., 320.) in
  let step ?(buttons = []) ?(keys = []) events =
    incr count;
    env := E.update !env { (frame ~mouse:!mouse ~keys !count events) with mouse_buttons = buttons } in
  let at ?buttons point events = mouse := point; step ?buttons events in
  let key k = Event.KeyPressed k and char c = Event.KeyPressed (Input.KeyChar c) in
  let jump name =
    step [ key Input.Space; char 'j' ]; step [ Event.TextInput name ]; step [ key Input.Enter ]; step [] in
  let line () = Option.value ~default:"-" (E.carry_line !env) in
  let source () = Flow.Lisp.print (E.workspace !env).source |> fst in
  for _ = 1 to 4 do step [] done;
  let gx, gy, _, gh = (E.panes !env (frame 0 [])).graph in
  let top = gy + gh + 28 + 1 + 22 in
  let click point = at point [ Event.MouseMoved point ];
    at point [ Event.MousePressed (Input.LeftButton, point); Event.MouseReleased (Input.LeftButton, point) ];
    step [] in
  (* the Graph tab, graph b open, graph a held *)
  jump "b";
  click (float (gx + 8 + 81 + 20), float (top + 12));
  jump "a";
  step [ char 'y' ]; step [];
  check (E.carrying !env = Some ("sop", "(ref a)")) "y holds graph a";
  jump "b";
  check (E.carrying !env <> None) "the carry survives the jump";
  let original = E.workspace !env and history = E.undo_label !env in
  let shown tab =
    (Prismel_editor.Private.Text_pane.make_shown (E.workspace !env).source "b" None tab).text in
  let where tab needle =
    let lines = String.split_on_char '\n' (shown tab) in
    let line = Option.get (List.find_index (fun l -> contains l needle) lines) in
    let l = List.nth lines line in
    let rec find i = if String.sub l i (String.length needle) = needle then i else find (i + 1) in
    line, find 0 in
  let char_w = 6.95 in
  let point tab needle ~after =
    let line, col = where tab needle in
    float gx +. 12. +. 3. *. char_w +. 8. +. float (col + after) *. char_w, float top +. 24. +. float line *. 24. in
  (* hover between the call and its first argument: the text is the edit, the strip says where *)
  let over = point Prismel_editor.Private.Text_pane.Graph "(sop/merge" ~after:10 in
  at over [ Event.MouseMoved over ]; at over [];
  check (contains (line ()) "(ref a) at line") ("the strip says where it goes: " ^ line ());
  check (contains (source ()) "(sop/merge (ref a) (sop/box)") ("the preview is the edit: " ^ source ());
  check (E.undo_label !env = history) "a preview writes nothing to the history";
  (* a release is the put: one entry named Put *)
  at over [ Event.MousePressed (Input.LeftButton, over); Event.MouseReleased (Input.LeftButton, over) ]; step []; step [];
  check (E.carrying !env = None && E.undo_label !env = Some "Put" && contains (source ()) "(sop/merge (ref a) (sop/box)")
    ("a release writes it as one Put entry: " ^ source ());
  step ~keys:[ Input.Meta ] [ char 'z' ];
  check (E.workspace !env == original) "one undo gives it back";
  (* inside a keyword the text does not check: refused, nothing written *)
  jump "a"; step [ char 'y' ]; step []; jump "b";
  let inside = point Prismel_editor.Private.Text_pane.Graph "(sop/merge" ~after:5 in
  at inside [ Event.MouseMoved inside ]; at inside [];
  check (contains (line ()) "Refused") ("a put that does not check is refused: " ^ line ());
  check (E.workspace !env == original) "and the picture is the original";
  step [ key Input.Escape ]; step [];
  check (E.carrying !env = None && E.workspace !env == original) "Escape drops it";
  (* an unapplied draft: its bytes are not the document's *)
  at (float (gx + 200), float (top + 24 + 60)) [];
  click (float (gx + 200), float (top + 24 + 60));
  step [ Event.TextInput "x" ]; step [ key Input.Escape ]; step [];
  jump "a"; step [ char 'y' ]; step []; jump "b";
  let over = point Prismel_editor.Private.Text_pane.Graph "(sop/merge" ~after:10 in
  at over [ Event.MouseMoved over ]; at over [];
  check (contains (line ()) "unapplied draft") ("a draft refuses: " ^ line ());
  step [ key Input.Escape ]; step [];
  (* the Document tab: the whole text is checked and installed *)
  click (float (gx + 8 + 81 + 53 + 20), float (top + 12));
  let original = E.workspace !env in
  jump "a"; step [ char 'y' ]; step [];
  let over = point Prismel_editor.Private.Text_pane.Document "(sop/merge" ~after:10 in
  at over [ Event.MouseMoved over ]; at over [];
  check (contains (line ()) "(ref a) at line") ("the Document text takes it too: " ^ line ());
  at over [ Event.MousePressed (Input.LeftButton, over); Event.MouseReleased (Input.LeftButton, over) ]; step []; step [];
  check (E.undo_label !env = Some "Put" && contains (source ()) "(sop/merge (ref a) (sop/box)")
    ("a put at a caret of the Document text is one Put entry: " ^ source ());
  step ~keys:[ Input.Meta ] [ char 'z' ];
  check (E.workspace !env == original) "and one undo gives it back";
  E.close !env

let run () =
  selection_text ();
  lisp_text ();
  editor_text ();
  editor_binding ();
  editor_w9 ();
  editor_active_scrub ();
  editor_text_drop ();
  print_endline "text pane tests passed"
