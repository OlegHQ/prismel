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
  binding : (path * string) option;  (* the selected binding and its expression's text *)
  applied : string Lazy.t;  (* the whole document's text, for the draft's dirty mark *)
}

type state = {
  tab : tab;
  draft : string option;  (* the Document tab's unapplied text *)
  binding_draft : (path * string) option;
  graph_draft : (string * string) option;  (* the Graph tab's unapplied text, and its graph *)
  doc_errors : Flow.Diagnostic.t list;  (* of the last refused apply *)
  binding_errors : Flow.Diagnostic.t list;
  graph_errors : Flow.Diagnostic.t list;
  cache : ((S.t list * string * path option * tab) * shown) option;
}

let initial = { tab = Selection; draft = None; binding_draft = None; graph_draft = None;
  doc_errors = []; binding_errors = []; graph_errors = []; cache = None }

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
          form (base + 3) (S.Sym top) ])) with notes = [ note ] }
      end

let make_shown source graph selected tab =
  let applied = lazy (fst (Flow.Lisp.print source)) in
  match tab with
  | Document -> { graph; text = Lazy.force applied; mark = None; binding = None; applied }
  | Selection | Graph ->
      (match root_form source graph with
       | None -> { graph; text = ""; mark = None; binding = None; applied }
       | Some root ->
           let names = match selected with Some (_ :: names) -> names | _ -> [] in
           let found = Option.bind (last root) (fun body -> find_binding body names) in
           let form = match tab, names with
             | Selection, top :: _ -> Option.value ~default:root (closure root top)
             | _ -> root in
           let text, spans = Flow.Lisp.print [ form ] in
           { graph; text; mark = mark spans found;
             binding = (match found, selected with
               | Some (_, v), Some path ->
                   Some (path, String.trim (fst (Flow.Lisp.print [ v ])))
               | _ -> None); applied })

(* [shown] recomputed only when the source, the graph, the selection or the
   tab changed *)
let shown state ~(source : S.t list) ~graph ~selected =
  let key = (source, graph, selected, state.tab) in
  match state.cache with
  | Some ((s, g, p, t), shown) when s == source && g = graph && p = selected && t = state.tab ->
      state, shown
  | _ ->
      let shown = make_shown source graph selected state.tab in
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

let dirty state (shown : shown) = match state.draft with
  | Some d -> d <> Lazy.force shown.applied | None -> false

let view ui ~bounds:(x, y, width, height) state (shown : shown) =
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
  (* the toolbar and the message row under an editable area *)
  let editor key ~at:(ey, eh) ~text ~errors ~spans ~apply ~discard ~can_apply ~message ~draft =
    let text', submitted = Ui.text_area_submit ui ~at:(x, ey) ~w:width ~h:(Float.max row (eh -. footer))
        ~wrap:true ~errors:(List.filter_map (line_of text) errors |> fun lines -> lines) ~spans key text in
    if text' <> text then emit (draft text');
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
    () in
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
         ~draft:(fun t -> Doc_draft t)
   | Graph ->
       let text = match state.graph_draft with
         | Some (g, t) when g = shown.graph -> t | _ -> shown.text in
       let dirty = text <> shown.text in
       editor "text-graph" ~at:(body_y, body_h) ~text ~errors:(real_errors state.graph_errors)
         ~spans:[] ~apply:(fun t -> Graph_apply (shown.graph, t)) ~discard:Graph_discard ~can_apply:dirty
         ~message:(message state.graph_errors ~dirty
           ~clean:(Printf.sprintf "Edit %s as text; Check & apply checks the whole workspace." shown.graph))
         ~draft:(fun t -> Graph_draft (shown.graph, t))
   | Selection ->
       let spans = Option.to_list shown.mark in
       let reveal = Option.map fst shown.mark in
       (match state.tab, shown.binding with
        | Selection, Some (path, expr) ->
            let upper = Float.max (2. *. row) (Float.floor ((body_h -. row) /. row *. 0.5) *. row) in
            ignore (Ui.text_area_submit ui ~at:(x, body_y) ~w:width ~h:upper ~readonly:true ~wrap:true
              ~spans ?reveal "text-selection" shown.text);
            let name = List.nth path (List.length path - 1) in
            let text = match state.binding_draft with
              | Some (p, t) when p = path -> t | _ -> expr in
            let dirty = text <> expr in
            editor "text-binding" ~at:(body_y +. upper, body_h -. upper) ~text
              ~errors:(real_errors state.binding_errors) ~spans:[]
              ~apply:(fun t -> Binding_apply (path, t)) ~discard:Binding_discard ~can_apply:dirty
              ~message:(message state.binding_errors ~dirty
                ~clean:(Printf.sprintf "Edit %s as text; Check & apply checks the whole workspace." name))
              ~draft:(fun t -> Binding_draft (path, t))
        | _ ->
            ignore (Ui.text_area_submit ui ~at:(x, body_y) ~w:width ~h:body_h ~readonly:true ~wrap:true
              ~spans ?reveal "text-readonly" shown.text)));
  List.rev !intents
