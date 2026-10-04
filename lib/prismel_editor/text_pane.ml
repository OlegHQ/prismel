(* The workspace text pane (plan W7): three tabs over the Lisp text.
   Selection prints the selected binding's top-level ancestor with its upstream
   closure and marks the selection; Graph prints the active graph; Document is
   the whole workspace, an editable draft with an atomic Check & apply.  The
   study's Lisp panel (prototype/src/e4.js) is the behavioural reference.

   Pure state and text here; [view] draws it and returns intents, [Core]
   applies them (the model is never touched inside [Ui.frame]). *)
module S = Flow.Syntax

type tab = Selection | Graph | Document
type path = Flow.Workspace.path

type shown = {
  graph : string;  (* the graph the Selection and Graph tabs read *)
  text : string;
  mark : (int * int) option;  (* byte span of the selected binding in [text] *)
  key : path;  (* what the Selection tab shows: the selected binding's path, else [graph] *)
  applied : string Lazy.t;  (* the whole document's text, for the draft's dirty mark *)
}

type state = {
  tab : tab;
  draft : string option;  (* the Document tab's unapplied text *)
  binding_draft : (path * string) option;  (* the Selection tab's unapplied text, and its key *)
  graph_draft : (string * string) option;  (* the Graph tab's unapplied text, and its graph *)
  doc_base : Editor_document.Workspace_doc.t option;
  binding_base : Editor_document.Workspace_doc.t option;
  graph_base : Editor_document.Workspace_doc.t option;
  doc_errors : Flow.Diagnostic.t list;  (* of the last refused apply *)
  binding_errors : Flow.Diagnostic.t list;
  graph_errors : Flow.Diagnostic.t list;
  wrap : bool;  (* long lines continue on the next row *)
  parinfer : bool;  (* closing brackets follow indentation (Lisp_text.parinfer_text) *)
  menu : (float * float) option;  (* the right-click menu, while open *)
  cache : ((S.t list * Editor_document.Workspace_doc.t option * string * path option * tab) * shown) option;
}

let initial = { tab = Selection; draft = None; binding_draft = None; graph_draft = None;
  doc_base = None; binding_base = None; graph_base = None;
  doc_errors = []; binding_errors = []; graph_errors = []; wrap = false; parinfer = true; menu = None; cache = None }

(* ---- reading the source ---- *)

let head_sym (f : S.t) = match f.node with S.List ({ S.node = S.Sym h; _ } :: _) -> Some h | _ -> None

let root_form (source : S.t list) name =
  match source with
  | { S.node = S.List (_ :: _ :: items); _ } :: _ ->
      List.find_opt (fun (item : S.t) -> match item.node with
        | S.List ({ S.node = S.Sym ("graph" | "defn" as h); _ } :: { S.node = S.Sym n; _ } :: _) ->
            (if h = "defn" then "def:" ^ n else n) = name
        | _ -> false) items
  | _ -> None

let last (f : S.t) = List.nth_opt (List.rev (S.children f)) 0

let rec pairs = function a :: b :: rest -> (a, b) :: pairs rest | _ -> []

let scope (e : S.t) = match e.node with
  | S.List [ { S.node = S.Sym "let*"; _ }; { S.node = S.Vec bs; _ }; res ]
    when List.length bs mod 2 = 0 -> Some (pairs bs, res)
  | _ -> None

(* the scope inside a binding's value: itself, or a loop's body *)
let enter (v : S.t) = match scope v, head_sym v with
  | Some _, _ -> v
  | None, Some ("for" | "fold" | "scan" | "sum") -> Option.value ~default:v (last v)
  | None, _ -> v

(* the binding a path names (pattern and expression) below a graph's body *)
let rec find_binding (cur : S.t) = function
  | [] -> None
  | name :: rest ->
      let found = match scope cur with
        | Some (_, res) when name = "@result" -> Some (None, res)
        | Some (ps, _) -> List.find_map (fun ((p : S.t), v) ->
            if Flow_sop.Flow_edit.pat_key p = name then Some (Some p, v) else None) ps
        | None -> None in
      match found with
      | Some (p, v) when rest = [] -> Some (p, v)
      | Some (_, v) -> find_binding (enter v) rest
      | None -> None

let binding source = function
  | graph :: names ->
      Option.bind (root_form source graph) (fun root ->
        Option.bind (last root) (fun body -> find_binding body names))
  | [] -> None

let rec max_id (f : S.t) = List.fold_left (fun m c -> max m (max_id c)) f.id (S.children f)

let span_of spans (f : S.t) = List.assoc_opt f.id spans

(* the marked byte range of a binding: its name through its expression *)
let mark spans (found : (S.t option * S.t) option) = match found with
  | None -> None
  | Some (p, v) ->
      (match Option.bind p (span_of spans), span_of spans v with
       | Some a, Some b -> Some (a.Flow.Diagnostic.start, b.finish)
       | None, Some b -> Some (b.start, b.finish)
       | _ -> None)

let plural n what = Printf.sprintf "%d %s%s" n what (if n = 1 then "" else "s")

(* the top-level ancestor with what it reads, as a [let*] over the
   root bindings it needs; None when the graph body is not a scope *)
let closure (root : S.t) top =
  match Option.bind (last root) scope with
  | None -> None
  | Some (bindings, _) ->
      let declares = List.concat_map (fun ((p, _) as binding) ->
        List.map (fun n -> n, binding) (Flow_sop.Flow_edit.pat_names p)) bindings in
      let rec need acc name = match List.assoc_opt name declares with
        | Some ((_, v) as binding) when not (List.memq binding acc) ->
            List.fold_left need (binding :: acc) (Flow_sop.Flow_edit.free_names v)
        | _ -> acc in
      let needed = need [] top in
      let sub = List.filter (fun b -> List.memq b needed) bindings in
      if sub = [] then None else begin
        let inputs = match List.find_map (fun (c : S.t) -> match c.node with
            | S.Vec inputs -> Some inputs | _ -> None) (S.children root) with
          | None -> []
          | Some inputs -> List.filter_map (fun (i : S.t) -> match i.node with
              | S.List ({ S.node = S.Sym n; _ } :: _)
                when List.exists (fun (_, v) -> List.mem n (Flow_sop.Flow_edit.free_names v)) sub -> Some n
              | _ -> None) inputs in
        let base = max_id root + 1 in
        let form id node = { (S.make node) with id } in
        let note = Printf.sprintf "%s · %s%s" top
          (if List.length sub > 1 then "with " ^ plural (List.length sub - 1) "upstream binding"
           else "no upstream bindings")
          (if inputs = [] then "" else " and inputs " ^ String.concat ", " inputs) in
        Some { (form base (S.List [ form (base + 1) (S.Sym "let*");
          form (base + 2) (S.Vec (List.concat_map (fun (p, v) -> [ p; v ]) sub));
          form (base + 3) (S.Sym top) ])) with notes = [ note;
            "Selection patches named bindings; omitted bindings stay. Change the result in Graph or Document." ] }
      end

(* Build the complete candidate graph before checking: dependent bindings may
   change type together, so checking individual replacements is incorrect. *)
let selection_form source path form =
  let error message = Error (Flow.Diagnostic.error ~code:"E_EDIT" message) in
  match path, scope form with
  | graph :: top :: _, Some (patches, result) ->
      let printed f = fst (Flow.Lisp.print [f]) in
      let names = List.filter_map (fun ((p : S.t), _) -> match p.node with
        | S.Sym n -> Some n | _ -> None) patches in
      let invalid = List.find_opt (fun ((p : S.t), _) -> match p.node with
        | S.Sym n -> binding source [graph; n] = None | _ -> true) patches in
      (match invalid with
       | Some (p, _) -> error (Printf.sprintf "%s is not a binding of %s; add or remove bindings in the Graph tab."
           (String.trim (printed p)) graph)
       | None when List.length names <> List.length (List.sort_uniq String.compare names) ->
           error "Duplicate binding names in Selection."
       | None when printed result <> printed (S.make (S.Sym top)) ->
           error "Selection's result must stay unchanged; edit the result in Graph or Document."
       | None ->
           match Option.bind (root_form source graph) (fun root ->
             Option.map (fun body -> root, body) (last root)) with
           | Some (root, body) ->
               (match scope body with
                | Some (bindings, res) ->
                    let changed = ref false in
                    let bindings = List.map (fun (p, old) ->
                      match List.find_opt (fun (q, _) -> q.S.node = p.S.node) patches with
                      | Some (_, v) when printed old <> printed v ->
                          changed := true;
                          p, (if v.notes = [] then { v with notes = old.notes } else v)
                      | _ -> p, old) bindings in
                    if not !changed then error "Nothing changed." else
                    let body = { body with node = S.List [List.hd (S.children body);
                      { (List.nth (S.children body) 1) with node = S.Vec
                          (List.concat_map (fun (p, v) -> [p; v]) bindings) }; res] } in
                    Ok { root with node = S.List (List.rev (body :: List.tl (List.rev (S.children root)))) }
                | None -> error "Expected the shown Selection closure.")
           | None -> error "Selection graph no longer exists.")
  | _, _ -> error "Expected the shown (let* [...] name) closure, or the graph form."

let make_shown source graph selected tab =
  let applied = lazy (fst (Flow.Lisp.print source)) in
  let key = match selected with Some path -> path | None -> [ graph ] in
  match tab with
  | Document -> { graph; text = Lazy.force applied; mark = None; key; applied }
  | Selection | Graph ->
      (match root_form source graph with
       | None -> { graph; text = ""; mark = None; key; applied }
       | Some root ->
           let names = match selected with Some (_ :: names) -> names | _ -> [] in
           let found = Option.bind (last root) (fun body -> find_binding body names) in
           let form = match tab, names with
             | Selection, top :: _ -> Option.value ~default:root (closure root top)
             | _ -> root in
           let text, spans = Flow.Lisp.print [ form ] in
           { graph; text; mark = mark spans found; key; applied })

(* [shown] recomputed only when the source, the graph, the selection or the
   tab changed *)
let shown ?workspace state ~(source : S.t list) ~graph ~selected =
  let key = (source, workspace, graph, selected, state.tab) in
  let same a b = match a, b with None, None -> true | Some a, Some b -> a == b | _ -> false in
  match state.cache with
  | Some ((s, w, g, p, t), shown) when s == source && same w workspace
      && g = graph && p = selected && t = state.tab ->
      state, shown
  | _ ->
      let shown = make_shown source graph selected state.tab in
      let shown = match workspace with
        | None -> shown
        | Some workspace ->
            let applied = lazy (Editor_document.Workspace_doc.to_text workspace) in
            { shown with applied;
              text = if state.tab = Document then Lazy.force applied else shown.text } in
      { state with cache = Some (key, shown) }, shown

(* ---- errors ---- *)

let line_of text (d : Flow.Diagnostic.t) = match d.position, d.span with
  | Some p, _ -> Some p.line
  | None, Some s ->
      let lines = ref 1 in
      String.iteri (fun i c -> if i < s.start && c = '\n' then incr lines) text;
      Some !lines
  | None, None -> None

let real_errors = List.filter (fun (d : Flow.Diagnostic.t) -> d.severity = Flow.Diagnostic.Error)

let first_error state =
  match real_errors state.doc_errors, real_errors state.binding_errors, real_errors state.graph_errors with
  | d :: _, _, _ | [], d :: _, _ | [], [], d :: _ -> Some d
  | [], [], [] -> None

(* one line for the crash report and tests: the tab, the draft, the first error *)
let summary state =
  Printf.sprintf "%s tab, draft %s%s"
    (match state.tab with Selection -> "selection" | Graph -> "graph" | Document -> "document")
    (if (match state.tab with
         | Document -> state.draft <> None
         | Graph -> state.graph_draft <> None
         | Selection -> state.binding_draft <> None) then "yes" else "no")
    (match real_errors state.doc_errors, state.draft, real_errors state.binding_errors with
     | d :: _, Some draft, _ ->
         Printf.sprintf ", error%s: %s"
           (match line_of draft d with Some l -> Printf.sprintf " at line %d" l | None -> "")
           (Flow.Diagnostic.to_string d)
     | _, _, d :: _ ->
         Printf.sprintf ", error%s: %s"
           (match Option.bind state.binding_draft (fun (_, t) -> line_of t d) with
            | Some l -> Printf.sprintf " at line %d" l | None -> "")
           (Flow.Diagnostic.to_string d)
     | d :: _, None, _ -> ", error: " ^ Flow.Diagnostic.to_string d
     | [], _, [] ->
         (match real_errors state.graph_errors with
          | d :: _ -> ", error: " ^ Flow.Diagnostic.to_string d
          | [] -> ""))

(* ---- the pane ---- *)

type intent =
  | Tab of tab
  | Doc_draft of string
  | Doc_apply of string
  | Doc_discard
  | Binding_draft of path * string
  | Binding_apply of path * string
  | Binding_discard
  | Graph_draft of string * string
  | Graph_apply of string * string
  | Graph_discard
  | Menu of (float * float) option
  | Toggle_wrap
  | Doc_scrub of string * bool
  | Graph_scrub of string * string * bool
  | Binding_scrub of path * string * bool
  | Toggle_parinfer

let dirty state (shown : shown) = match state.draft with
  | Some d -> d <> Lazy.force shown.applied | None -> false

let view ui ~bounds:(x, y, width, height) ~vocab state (shown : shown) =
  let module Ui = Pxui.Ui in
  let row = float (Ui.row_height ui) in
  let x = float x and y = float y and width = float width and height = float height in
  let theme = Ui.theme ui in
  let intents = ref [] in
  let emit i = intents := i :: !intents in
  (* a labelled, clickable rectangle at [at] *)
  let chip key ~at:(cx, cy) ~w ~active ?(enabled = true) text =
    let box = Ui.box ui ~flags:Ui.(clickable + blocking) ~w:(Ui.Px w) ~h:(Ui.Px row)
        ~at:(cx, cy) key in
    let signal = Ui.signal ui box in
    Ui.draw ui box (fun paint _ ->
      Ui.Paint.rect paint ~x:cx ~y:cy ~w ~h:row
        ~fill:(if active then theme.foreground
               else if signal.hovered && enabled then Pxui.Theme.hover_fill theme else theme.panel)
        ~stroke:(if active || not enabled then Pxui.Theme.faint_border theme
                 else Pxui.Theme.border theme) ();
      Ui.Paint.text paint ~at:(cx +. 8., cy +. 5.)
        ~color:(if active then theme.input else if enabled then theme.foreground
                else Pxui.Theme.muted theme) text);
    signal.clicked && enabled in
  let applied = Lazy.force shown.applied in
  let dirty = dirty state shown in
  let tabs = [ Selection, "Selection"; Graph, "Graph";
    Document, if dirty then "Document *" else "Document" ] in
  ignore (List.fold_left (fun cx (tab, title) ->
    let w = 16. +. 7. *. float (String.length title) in
    if chip ("text-tab-" ^ title) ~at:(cx, y) ~w ~active:(state.tab = tab) title
    then emit (Tab tab);
    cx +. w +. 2.) x tabs);
  let footer = 2. *. row in
  let body_y = y +. row in
  let body_h = Float.max row (height -. row) in
  let language = Lisp_text.language ~vocab ~parinfer:state.parinfer theme in
  (* the toolbar and the message row under an editable area; a right-click menu offers the same
     buttons and the wrap toggle *)
  let editor key ~at:(ey, eh) ~text ~errors ~spans ?reveal ~apply ~discard ~can_apply ~message ~draft ~scrub () =
    (* a dragged number applies live ([scrub], merged into one history entry); typing is a draft *)
    let phase = ref None in
    let text', submitted = Ui.text_area_submit ui ~at:(x, ey) ~w:width ~h:(Float.max row (eh -. footer))
        ~wrap:state.wrap ~errors:(List.filter_map (line_of text) errors) ~spans ?reveal ~language
        ~on_context:(fun at -> emit (Menu (Some at))) ~on_scrub:(fun p -> phase := Some p) key text in
    (match !phase with
     | Some `Live -> emit (scrub text' false)
     | Some `Done -> emit (scrub text' true)
     | None -> if text' <> text then emit (draft text'));
    let can_apply = can_apply || text' <> text in
    let ty = ey +. Float.max row (eh -. footer) in
    (* Command-Enter in the area is the button *)
    if (chip (key ^ "-apply") ~at:(x, ty) ~w:118. ~active:false ~enabled:can_apply "Check & apply")
       || (submitted && can_apply)
    then emit (apply text');
    if chip (key ^ "-discard") ~at:(x +. 120., ty) ~w:74. ~active:false ~enabled:can_apply "Discard"
    then emit discard;
    let msg = Ui.box ui ~w:(Ui.Px width) ~h:(Ui.Px row) ~at:(x, ty +. row) (key ^ "-message") in
    Ui.draw ui msg (fun paint _ ->
      Ui.Paint.text paint ~at:(x +. 8., ty +. row +. 5.)
        ~color:(match errors with _ :: _ -> Pxui.Theme.invalid | [] -> Pxui.Theme.muted theme) message);
    (match state.menu with
     | None -> ()
     | Some at ->
         (match Ui.context_menu ui ~at (key ^ "-menu")
                  [ "Check & apply", can_apply; "Discard", can_apply; "", false;
                    (if state.wrap then "Unwrap long lines" else "Wrap long lines"), true;
                    (if state.parinfer then "Parinfer off (keep brackets as typed)"
                     else "Parinfer on (brackets follow indentation)"), true ] with
          | `Open -> ()
          | `Dismiss -> emit (Menu None)
          | `Pick 0 -> emit (Menu None); emit (apply text')
          | `Pick 1 -> emit (Menu None); emit discard
          | `Pick 3 -> emit (Menu None); emit Toggle_wrap
          | `Pick _ -> emit (Menu None); emit Toggle_parinfer)) in
  let fit text =
    let limit = max 8 (int_of_float ((width -. 16.) /. 7.)) in
    if String.length text <= limit then text else String.sub text 0 (limit - 3) ^ "..." in
  let message errors ~dirty ~clean = fit (match real_errors errors with
    | d :: _ -> String.map (function '\n' -> ' ' | c -> c) (Flow.Diagnostic.to_string d)
    | [] -> if dirty then "Unapplied draft. Every other pane shows the last applied document."
        else clean) in
  (match state.tab with
   | Document ->
       let text = Option.value ~default:applied state.draft in
       editor "text-document" ~at:(body_y, body_h) ~text ~errors:(real_errors state.doc_errors)
         ~spans:[] ~apply:(fun t -> Doc_apply t) ~discard:Doc_discard ~can_apply:dirty
         ~message:(message state.doc_errors ~dirty ~clean:"Source matches the applied document.")
         ~draft:(fun t -> Doc_draft t) ~scrub:(fun t done_ -> Doc_scrub (t, done_)) ()
   | Graph ->
       let text = match state.graph_draft with
         | Some (g, t) when g = shown.graph -> t | _ -> shown.text in
       let dirty = text <> shown.text in
       editor "text-graph" ~at:(body_y, body_h) ~text ~errors:(real_errors state.graph_errors)
         ~spans:[] ~apply:(fun t -> Graph_apply (shown.graph, t)) ~discard:Graph_discard ~can_apply:dirty
         ~message:(message state.graph_errors ~dirty
           ~clean:(Printf.sprintf "Edit %s as text; Check & apply checks the whole workspace." shown.graph))
         ~draft:(fun t -> Graph_draft (shown.graph, t))
         ~scrub:(fun t done_ -> Graph_scrub (shown.graph, t, done_)) ()
   | Selection ->
       (* the closure of the selection, editable: its bindings are the graph's root bindings *)
       let text = match state.binding_draft with
         | Some (k, t) when k = shown.key -> t | _ -> shown.text in
       let dirty = text <> shown.text in
       let spans = if dirty then [] else Option.to_list shown.mark in
       editor "text-selection" ~at:(body_y, body_h) ~text ~errors:(real_errors state.binding_errors)
         ~spans ?reveal:(Option.map fst shown.mark)
         ~apply:(fun t -> Binding_apply (shown.key, t)) ~discard:Binding_discard ~can_apply:dirty
         ~message:(message state.binding_errors ~dirty
           ~clean:"The selection with what it reads; Check & apply writes the bindings shown.")
         ~draft:(fun t -> Binding_draft (shown.key, t))
         ~scrub:(fun t done_ -> Binding_scrub (shown.key, t, done_)) ());
  List.rev !intents
