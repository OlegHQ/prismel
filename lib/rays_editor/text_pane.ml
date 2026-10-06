(* The workspace text pane (plan W7): three tabs over the Lisp text.
   Selection prints the selected binding's top-level ancestor with its upstream
   closure and marks the selection; Graph prints the active graph; Document is
   the whole workspace, an editable draft with an atomic Check and apply.  The
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
  body : (S.t * (int * Flow.Diagnostic.span) list) option;  (* the graph's body and the spans of [text], for the caret *)
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
  picker : (int * int * bool) option;  (* the colour literal (byte range with its quotes) being edited, and whether it changed *)
  cache : ((S.t list * Editor_document.Workspace_doc.t option * string * path option * tab) * shown) option;
}

let initial = { tab = Selection; draft = None; binding_draft = None; graph_draft = None;
  doc_base = None; binding_base = None; graph_base = None;
  doc_errors = []; binding_errors = []; graph_errors = []; wrap = false; parinfer = true; menu = None; picker = None; cache = None }

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
      (* a nested node: the binding that holds it, then the inputs down to it *)
      let name, keys = Option.value (Flow_sop.Flow_edit.leaf_keys name) ~default:(name, []) in
      let found = match scope cur with
        | Some (_, res) when name = "@result" -> Some (None, res)
        | Some (ps, _) -> List.find_map (fun ((p : S.t), v) ->
            if Flow_sop.Flow_edit.pat_key p = name then Some (Some p, v) else None) ps
        | None when name = "@result" -> Some (None, cur)
        | None -> None in
      let found = if keys = [] then found else
        Option.bind found (fun (_, v) ->
          List.fold_left (fun e key -> Option.bind e (fun e -> Flow_sop.Flow_edit.arg_of e key)) (Some v) keys
          |> Option.map (fun e -> None, e)) in
      match found with
      | Some (p, v) when rest = [] -> Some (p, v)
      | Some (_, v) -> find_binding (enter v) rest
      | None -> None

let binding source = function
  | graph :: names ->
      Option.bind (root_form source graph) (fun root ->
        Option.bind (last root) (fun body -> find_binding body names))
  | [] -> None

(* Pasted text as bindings of [scope] in [graph]: "name expr" pairs, or bare expressions named by
   their head.  The names are paired with the bindings by position (two forms may share a head),
   each made free of the graph's names and of the ones before it; a pasted binding that reads an
   earlier pasted one reads its new name.  The renames are substituted at once, through
   placeholders, so a new name that is another pasted binding's old name is not renamed again. *)
let paste_ops source ~graph ~scope text =
  let module F = Flow_sop.Flow_edit in
  let rec named = function
    | { S.node = S.Sym n; _ } :: v :: rest -> Option.map (fun r -> (n, v) :: r) (named rest)
    | [] -> Some [] | _ -> None in
  let head (f : S.t) = match head_sym f with
    | Some h -> (match String.rindex_opt h '/' with
        | Some i -> String.sub h (i + 1) (String.length h - i - 1) | None -> h)
    | None -> "value" in
  match S.parse text with
  | Error _ | Ok [] -> Error "The clipboard holds no Lisp bindings"
  | Ok forms ->
      let bindings, reading = match named forms with
        | Some ps -> ps, true | None -> List.map (fun f -> head f, f) forms, false in
      let chosen = ref [] in
      let fresh n =
        let rec pick k =
          let name = F.fresh_name source ~root:graph (if k = 0 then n else Printf.sprintf "%s_%d" n k) in
          if List.mem name !chosen then pick (k + 1) else (chosen := name :: !chosen; name) in
        pick 0 in
      let _, ops = List.fold_left (fun (earlier, ops) (old, expr) ->
        let name = fresh old in
        (* what the earlier pasted bindings are called now, the latest of a name first *)
        let seen = ref [] in
        let renames = List.filter (fun (o, n) ->
          reading && o <> n && not (List.mem o !seen) && (seen := o :: !seen; true)) earlier in
        let held = List.mapi (fun i (o, n) -> o, Printf.sprintf "@paste%d" i, n) renames in
        let expr = List.fold_left (fun e (o, hold, _) -> F.rename_ref o hold e) expr held in
        let expr = List.fold_left (fun e (_, hold, n) -> F.rename_ref hold n e) expr held in
        (old, name) :: earlier, F.Add_node { scope; name; expr } :: ops) ([], []) bindings in
      Ok (List.rev ops)

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

(* the path of the innermost binding whose text holds [byte] (name through expression) *)
let binding_at (shown : shown) byte = match shown.body with
  | None -> None
  | Some (body, spans) ->
      let holds (f : S.t) = match span_of spans f with
        | Some s -> s.Flow.Diagnostic.start <= byte && byte <= s.finish | None -> false in
      (* the nested node the byte is in, innermost: a step of a ->, a call inside a call *)
      let rec nested prefix leaf (v : S.t) =
        match List.find_opt (fun (_, a) -> holds a) (Flow_sop.Flow_edit.nested_nodes v) with
        | Some (key, a) -> nested prefix (Flow_sop.Flow_edit.nested_leaf leaf key) a
        | None -> prefix @ [ leaf ] in
      let rec within prefix cur = match scope cur with
        | None -> None
        | Some (bindings, res) ->
            let inside leaf v = match within (prefix @ [ leaf ]) (enter v) with
              | Some _ as deeper -> deeper | None -> Some (nested prefix leaf v) in
            (match List.find_map (fun ((p : S.t), v) ->
              match span_of spans p, span_of spans v with
              | Some a, Some b when a.Flow.Diagnostic.start <= byte && byte <= b.Flow.Diagnostic.finish ->
                  inside (Flow_sop.Flow_edit.pat_key p) v
              | _ -> None) bindings with
             | Some _ as found -> found
             | None -> if holds res && Flow_sop.Flow_edit.node_call res then inside "@result" res else None) in
      let found = match within [] body with
        | Some _ as found -> found
        | None -> if scope body = None && holds body && Flow_sop.Flow_edit.node_call body
            then Some (nested [] "@result" body) else None in
      Option.map (fun names -> shown.graph :: names) found

(* the bindings of a scene graph that are cameras (the values of [scene/root :camera]) *)
let cameras source graph =
  match Option.bind (Option.bind (root_form source graph) last) scope with
  | None -> []
  | Some (bindings, _) ->
      List.filter_map (fun ((p : S.t), v) -> match head_sym v, p.node with
        | Some "scene/camera", S.Sym n -> Some n
        | _ -> None) bindings

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
                    (* a closure that changes nothing is the graph as it is, not a refusal: a
                       scrub applies on every frame of its drag, also the ones that did not move *)
                    let bindings = List.map (fun (p, old) ->
                      match List.find_opt (fun (q, _) -> q.S.node = p.S.node) patches with
                      | Some (_, v) when printed old <> printed v ->
                          p, (if v.notes = [] then { v with notes = old.notes } else v)
                      | _ -> p, old) bindings in
                    let body = { body with node = S.List [List.hd (S.children body);
                      { (List.nth (S.children body) 1) with node = S.Vec
                          (List.concat_map (fun (p, v) -> [p; v]) bindings) }; res] } in
                    Ok { root with node = S.List (List.rev (body :: List.tl (List.rev (S.children root)))) }
                | None -> error "Expected the shown Selection closure.")
           | None -> error "Selection graph no longer exists.")
  | _, _ -> error "Expected the shown (let* [...] name) closure, or the graph form."

(* The [Set_graph] the text of the Graph or Selection tab means: the one graph (or function) form
   replaces the graph's; a Selection closure is patched into it ({!selection_form}).  The errors
   that are not the reader's carry no position. *)
let graph_op source ~graph ?selection text =
  let error message = Error (Flow.Diagnostic.error ~code:"E_EDIT" message) in
  let set form = Flow_sop.Flow_edit.Set_graph { name = graph; form } in
  match S.parse text, selection with
  | Error d, _ -> Error d
  | Ok [ ({ node = S.List ({ node = S.Sym ("graph" | "defn"); _ } :: _); _ } as form) ], _ -> Ok (set form)
  | Ok [ form ], Some path -> Result.map set (selection_form source path form)
  | Ok [ form ], None -> Ok (set form)
  | Ok _, Some _ -> error "Expected the shown (let* [...] name) closure, or the graph form."
  | Ok _, None -> error "Expected the one graph form"

let make_shown source graph selected tab =
  let applied = lazy (fst (Flow.Lisp.print source)) in
  let key = match selected with Some path -> path | None -> [ graph ] in
  match tab with
  | Document -> { graph; text = Lazy.force applied; mark = None; key; applied; body = None }
  | Selection | Graph ->
      (match root_form source graph with
       | None -> { graph; text = ""; mark = None; key; applied; body = None }
       | Some root ->
           let names = match selected with Some (_ :: names) -> names | _ -> [] in
           let found = Option.bind (last root) (fun body -> find_binding body names) in
           let form = match tab, names with
             | Selection, top :: _ -> Option.value ~default:root (closure root top)
             | _ -> root in
           let text, spans = Flow.Lisp.print [ form ] in
           { graph; text; mark = mark spans found; key; applied;
             body = (if tab = Graph then Option.map (fun body -> body, spans) (last root) else None) })

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

(* ---- a draft against a document that changed under it ---- *)

(* Three texts, merged form by form: [base] is what the draft began from, [mine] the draft,
   [theirs] the text now.  A form only one side changed takes that side's; a form both changed
   merges child by child; graphs of a workspace and bindings of a [let*] pair up by name, so one
   added or removed on either side is kept.  [None]: both changed the same value, or [mine] does
   not read.
   ponytail: a binding or keyword argument [theirs] added goes last in its form; keep [theirs]'
   place for it when the order of bindings bites (the merged text is still checked). *)
let merge3 ~base ~mine ~theirs =
  let text f = fst (Flow.Lisp.print [ f ]) in
  let same a b = text a = text b in
  let rec all = function
    | [] -> Some [] | None :: _ -> None
    | Some x :: rest -> Option.map (fun rest -> x :: rest) (all rest) in
  let key (f : S.t) = match f.node with
    | S.List ({ node = S.Sym h; _ } :: { node = S.Sym n; _ } :: _) -> h ^ " " ^ n
    | S.List ({ node = S.Sym h; _ } :: _) -> h
    | _ -> text f in
  let entries = List.map (fun f -> key f, [ f ]) in
  let rec pairs = function
    | p :: v :: rest -> Option.map (fun rest -> (text p, [ p; v ]) :: rest) (pairs rest)
    | [] -> Some [] | [ _ ] -> None in
  let rec merge (b : S.t) (m : S.t) (t : S.t) =
    if same m b then Some t else if same t b || same m t then Some m
    else
      let node make kids = Option.map (fun kids -> { m with node = make kids }) kids in
      match b.node, m.node, t.node with
      | S.List ({ node = S.Sym "let*"; _ } :: { node = S.Vec bv; _ } :: br),
        S.List (head :: ({ node = S.Vec mv; _ } as vec) :: mr),
        S.List (_ :: { node = S.Vec tv; _ } :: tr) ->
          (match pairs bv, pairs mv, pairs tv with
           | Some bv, Some mv, Some tv ->
               Option.bind (keyed bv mv tv) (fun bindings ->
                 node (fun rest -> S.List (head :: { vec with node = S.Vec bindings } :: rest)) (seq br mr tr))
           | _ -> None)
      | S.List ({ node = S.Sym "workspace"; _ } :: _ as bl), S.List ml, S.List tl ->
          node (fun kids -> S.List kids) (keyed (entries bl) (entries ml) (entries tl))
      | S.List bl, S.List ml, S.List tl ->
          node (fun kids -> S.List kids) (match seq bl ml tl with Some _ as kids -> kids | None -> call bl ml tl)
      | S.Vec bl, S.Vec ml, S.Vec tl -> node (fun kids -> S.Vec kids) (seq bl ml tl)
      | S.Map bl, S.Map ml, S.Map tl -> node (fun kids -> S.Map kids) (seq bl ml tl)
      | _ -> None
  (* a call whose argument count differs: what stands before the first keyword pairs by position,
     the keyword arguments by name *)
  and call bl ml tl =
    let rec split before = function
      | ({ S.node = S.Kw _; _ } :: _) as rest ->
          let rec keywords = function
            | { S.node = S.Kw _; _ } :: _ :: rest -> keywords rest | [] -> true | _ -> false in
          List.rev before, if keywords rest then pairs rest else None
      | f :: rest -> split (f :: before) rest
      | [] -> List.rev before, Some [] in
    match split [] bl, split [] ml, split [] tl with
    | (bp, Some bk), (mp, Some mk), (tp, Some tk) ->
        Option.bind (seq bp mp tp) (fun positional ->
          Option.map (fun keywords -> positional @ keywords) (keyed bk mk tk))
    | _ -> None
  and seq bl ml tl =
    if List.length bl = List.length ml && List.length ml = List.length tl
    then all (List.map2 (fun b (m, t) -> merge b m t) bl (List.combine ml tl)) else None
  and keyed bl ml tl =
    let unique l = let keys = List.map fst l in
      List.length (List.sort_uniq String.compare keys) = List.length keys in
    let sames a b = List.length a = List.length b && List.for_all2 same a b in
    if not (unique bl && unique ml && unique tl) then None else
    let mine = List.map (fun (k, m) -> match List.assoc_opt k bl, List.assoc_opt k tl with
      | Some b, Some t -> seq b m t
      | Some b, None -> if sames m b then Some [] else None  (* they removed what I left alone *)
      | None, Some t -> if sames m t then Some m else None   (* both added it *)
      | None, None -> Some m) ml in
    let theirs = List.map (fun (k, t) -> match List.mem_assoc k ml, List.assoc_opt k bl with
      | true, _ -> Some []
      | false, None -> Some t                                 (* they added it *)
      | false, Some b -> if sames t b then Some [] else None) tl in  (* I removed what they left alone *)
    Option.map List.concat (all (mine @ theirs)) in
  match S.parse base, S.parse mine, S.parse theirs with
  | Ok b, Ok m, Ok t -> Option.map (fun forms -> fst (Flow.Lisp.print forms)) (keyed (entries b) (entries m) (entries t))
  | _ -> None

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
  | Picker of (int * int * bool) option
  | Open_graph of string
  | Select_binding of path
  | Carry_over of int * bool

let dirty state (shown : shown) = match state.draft with
  | Some d -> d <> Lazy.force shown.applied | None -> false

(* The kit's colour control (swatch, hex, r g b) in a popup over the literal [text.[a..b)]:
   the new literal while it is edited. *)
let colour_popup ui ~at text (a, b) =
  let module Ui = Pxui.Ui in
  let module Color = Rays.Color in
  let theme = Ui.theme ui in
  let literal = String.sub text (a + 1) (b - a - 2) in
  let colour = Result.value (Color.hex literal) ~default:Color.white in
  let r, g, bl, _ = Color.to_floats colour in
  let clamp x = max 0 (min 255 (int_of_float (Float.round (x *. 255.)))) in
  let alpha = if String.length literal = 9 then String.sub literal 7 2 else "" in
  let hex r g b = Printf.sprintf "#%02x%02x%02x%s" (clamp r) (clamp g) (clamp b) alpha in
  let shown = hex r g bl in
  Ui.popup ui ~stroke:(Pxui.Theme.edge theme) ~at ~width:300. ~height:24. "text-colour" (fun () ->
    let box, cx, cy, cw = Ui.inspector_row ui ~width:300. ~key:"text-colour-row" ~label:"colour" () in
    Ui.within ui box (fun () ->
      let swatch = Ui.box ui ~at:(cx, cy) ~w:(Ui.Px 20.) ~h:(Ui.Px 20.) "text-colour-swatch" in
      Ui.draw ui swatch (fun paint (sx, sy, sw, sh) ->
        Ui.Paint.fill paint ~x:sx ~y:sy ~w:sw ~h:sh colour;
        Ui.Paint.stroke paint ~x:(sx +. 0.5) ~y:(sy +. 0.5) ~w:(sw -. 1.) ~h:(sh -. 1.) (Pxui.Theme.edge theme));
      let hex_x = cx +. 28. in
      let typed, _ = Ui.value_field ui ~at:(hex_x, cy) ~w:64. ~h:20. ~left:true
          ~valid:(fun t -> Result.is_ok (Color.hex t)) "text-colour-hex" shown in
      let from_hex = if typed = shown then None else
          Option.map (fun c -> let r, g, b, _ = Color.to_floats c in hex r g b) (Result.to_option (Color.hex typed)) in
      let sliders_x = hex_x +. 72. in
      let field_w = (Float.max 60. (cw -. 100.) -. 16.) /. 3. in
      let from_slider = List.find_map Fun.id (List.mapi (fun index (axis, cur) ->
        let ax_x = sliders_x +. float index *. (field_w +. 8.) in
        Ui.draw ui box (fun paint (x, y, _, _) ->
          Ui.Paint.text paint ~at:(x +. ax_x +. 2., Pxui_shell.Kit.cap_y ui (y +. cy) 20.)
            ~size:(Pxui_shell.Kit.cap_size ui) ~color:(Pxui.Theme.ink_3 theme) axis);
        let display = Printf.sprintf "%.2f" cur in
        let changed, _ = Ui.value_field ui ~at:(ax_x, cy) ~w:field_w ~h:20.
            ~display ~fraction:cur ~slide:(fun f -> Printf.sprintf "%.2f" f) ~edit:false ~left:false
            ~valid:(fun t -> float_of_string_opt t <> None) ("text-colour-" ^ axis) display in
        if changed = display then None else
          Option.map (fun v ->
            let v = Float.max 0. (Float.min 1. v) in
            hex (if index = 0 then v else r) (if index = 1 then v else g) (if index = 2 then v else bl))
            (float_of_string_opt changed)) [ "r", r; "g", g; "b", bl ]) in
      match from_slider with Some _ -> from_slider | None -> from_hex))
  |> Option.map (fun edit -> String.sub text 0 (a + 1) ^ Option.value ~default:literal edit
                             ^ String.sub text (b - 1) (String.length text - b + 1))

(* the tabs' names: the workspace sheet's narrow Lisp panel (under 400 points) says "Doc"; a
   document with a draft wears a star *)
let tab_labels ~width ~dirty =
  let doc = if width < 400 then "Doc" else "Document" in
  [ Selection, "Selection"; Graph, "Graph"; Document, if dirty then doc ^ " *" else doc ]

(* the room the tabs take in the panel's header, 12 apart *)
let tabs_width ui ~width state shown =
  List.fold_left (fun w (_, label) -> w +. 12. +. Pxui.Ui.text_width ui label) (-12.)
    (tab_labels ~width ~dirty:(dirty state shown))

let view ui ~bounds:(x, y, width, height) ~tabs_right ~vocab ~names state (shown : shown) =
  let module Ui = Pxui.Ui in
  let row = float (Ui.row_height ui) in
  let x = float x and y = float y and width = float width and height = float height in
  let theme = Ui.theme ui in
  let intents = ref [] in
  let emit i = intents := i :: !intents in
  let applied = Lazy.force shown.applied in
  let dirty = dirty state shown in
  (* the tabs sit in the panel's header, at its right: the body is all text *)
  (* the workspace sheet's narrow Lisp panel (under 400 points): "Doc", the two buttons alone in
     the bar and no status row *)
  let narrow = width < 400. in
  let tabs = tab_labels ~width:(int_of_float width) ~dirty in
  let active = Option.value ~default:0 (List.find_index (fun (tab, _) -> tab = state.tab) tabs) in
  (* [tabs_right] is where the header has room for them ([Pxui_shell.Chrome.header_slots]); none
     in a header too narrow *)
  Option.iter (fun right ->
    match fst (Pxui_shell.Kit.segments ui ~key:"text-tab" ~right
                 ~y:(y -. float Pxui_shell.Layout.header_height +. 2.) (List.map snd tabs) active) with
    | Some index -> emit (Tab (fst (List.nth tabs index)))
    | None -> ()) tabs_right;
  let bar = 32. in
  (* a hairline, the 32-point button bar, a hairline and the 24-point status row *)
  let footer = if narrow then bar +. 1. else bar +. row +. 2. in
  let body_y = y in
  let body_h = Float.max row height in
  let language = Lisp_text.language ~vocab ~names ~parinfer:state.parinfer theme in
  (* the toolbar and the message row under an editable area; a right-click menu offers the same
     buttons and the wrap toggle *)
  let editor key ~at:(ey, eh) ~text ~errors ~spans ?reveal ?(caret_select = fun _ -> None)
      ~apply ~discard ~can_apply ~message ~draft ~scrub () =
    let chips = Lisp_text.color_chips text in
    (* a dragged number applies live ([scrub], merged into one history entry); typing is a draft *)
    let phase = ref None and caret = ref None in
    let text', submitted = Ui.text_area_submit ui ~at:(x, ey) ~w:width ~h:(Float.max row (eh -. footer))
        ~wrap:state.wrap ~errors:(List.filter_map (line_of text) errors)
        ~messages:(List.filter_map (fun (d : Flow.Diagnostic.t) ->
          Option.map (fun line ->
            line, Option.map (fun (s : Flow.Diagnostic.span) -> s.start, s.finish) d.span,
            d.code ^ "  " ^ String.map (function '\n' -> ' ' | c -> c) d.message) (line_of text d)) errors)
        ~spans ?reveal ~language
        ~on_context:(fun at -> emit (Menu (Some at))) ~on_scrub:(fun p -> phase := Some p)
        ~chips
        ~on_drop:(fun byte drop -> emit (Carry_over (byte, (match drop with Ui.Dropped _ -> true | Hover _ -> false))))
        (* Command-click follows a (ref name); a click on a colour literal opens the colour control *)
        ~on_click:(fun byte command ->
          if command then
            (match Lisp_text.ref_at text byte with
             | Some name when List.mem name names.Lisp_text.graphs -> emit (Open_graph name)
             | _ -> ())
          else match List.find_opt (fun (a, b, _) -> a <= byte && byte < b) chips with
            | Some (a, b, _) -> emit (Picker (Some (a, b, false)))
            | None -> ())
        (* the caret in a binding selects its node *)
        ~on_caret:(fun byte -> caret := Some byte; match caret_select byte with
          | Some path when path <> shown.key -> emit (Select_binding path)
          | _ -> ())
        key text in
    (match !phase with
     | Some `Live -> emit (scrub text' false)
     | Some `Done -> emit (scrub text' true)
     | None -> if text' <> text then emit (draft text'));
    (* the colour control: each edit applies live as one merged history entry, sealed on close *)
    let text' = match state.picker with
      | Some (a, b, changed) when b <= String.length text' && List.exists (fun (a', b', _) -> a = a' && b = b') chips ->
          (match colour_popup ui ~at:(Float.max x (x +. width -. 310.), ey +. row) text' (a, b) with
           | Some edited when edited <> text' ->
               emit (Picker (Some (a, b, true))); emit (scrub edited false); edited
           | Some _ -> text'
           | None ->
               emit (Picker None); if changed then emit (scrub text' true); text')
      | Some _ -> emit (Picker None); text'
      | None -> text' in
    let can_apply = can_apply || text' <> text in
    let ty = ey +. Float.max row (eh -. footer) in
    let rule name at = Ui.draw ui (Ui.box ui ~w:(Ui.Px width) ~h:(Ui.Px 1.) ~at:(x, at) (key ^ name))
      (fun paint (x, y, w, h) -> Ui.Paint.fill paint ~x ~y ~w ~h (Pxui.Theme.edge theme)) in
    rule "-rule" ty;
    (* Command-Enter in the area is the button: the one outlined button of the panel *)
    let hint = "\xe2\x8c\x98\xe2\x86\xb5" in
    (* the caret's line and column, 1-based, in the status row's label *)
    let position = Option.map (fun byte ->
      let p = Flow.Diagnostic.position_of_offset text' (min byte (String.length text')) in
      Printf.sprintf "%d:%d" p.line p.col) !caret in
    let apply_w = Pxui_shell.Kit.button_width ui ~hint "Check and apply" in
    let by = ty +. 1. +. ((bar -. 20.) /. 2.) in
    if (Pxui_shell.Kit.button ui ~key:(key ^ "-apply") ~at:(x +. 12., by) ~w:apply_w ~primary:true
          ~enabled:can_apply ~hint "Check and apply")
       || (submitted && can_apply)
    then emit (apply text');
    let discard_hint = if narrow then None else Some "esc" in
    if Pxui_shell.Kit.button ui ~key:(key ^ "-discard") ~at:(x +. 12. +. apply_w +. 8., by)
         ~w:(Pxui_shell.Kit.button_width ui ?hint:discard_hint "Discard") ~enabled:can_apply ?hint:discard_hint "Discard"
    then emit discard;
    (* parinfer and its switch, at the bar's end *)
    let switch_x = x +. width -. 12. -. 28. in
    if not narrow then begin
      if Pxui_shell.Kit.switch ui ~key:(key ^ "-parinfer") ~at:(switch_x, ty +. 1. +. ((bar -. 14.) /. 2.)) state.parinfer
      then emit Toggle_parinfer;
      Ui.draw ui (Ui.box ui ~w:(Ui.Px 80.) ~h:(Ui.Px bar) ~at:(switch_x -. 8. -. 80., ty +. 1.) (key ^ "-parinfer-label"))
        (fun paint (x, y, w, h) ->
          let label = "parinfer" in
          Ui.Paint.text paint ~at:(x +. w -. Ui.Paint.text_width paint label, Pxui_shell.Kit.text_y ui y h)
            ~color:(Pxui.Theme.ink_2 theme) label);
      rule "-rule2" (ty +. 1. +. bar)
    end;
    let wrong = errors <> [] in
    let msg = Ui.box ui ~flags:Ui.clip ~w:(Ui.Px width) ~h:(Ui.Px (if narrow then 0. else row)) ~at:(x, ty +. bar +. 2.) (key ^ "-message") in
    if not narrow then Ui.draw ui msg (fun paint (x, y, w, h) ->
      (* the state: a dot in the error colour or the accent for a draft, then what it says; the
         first error is "n errors" in the error colour and its line and message in ink-2 *)
      let tx = if wrong || can_apply then begin
          Ui.Paint.circle paint ~at:(x +. 15., y +. (h /. 2.)) ~radius:3.
            ~fill:(if wrong then Pxui.Theme.invalid else theme.accent) (); x +. 26.
        end else x +. 12. in
      (* the label at the row's end: where the caret is, and whether the text is a draft *)
      let state_label = String.concat " \xc2\xb7 " (Option.to_list position @ (if can_apply then [ "modified" ] else [])) in
      let tail = if state_label <> "" then Pxui_shell.Kit.cap_width ui state_label +. 20. else 12. in
      let ty = Pxui_shell.Kit.text_y ui y h in
      (match errors with
       | (first : Flow.Diagnostic.t) :: _ ->
           let count = Printf.sprintf "%d error%s" (List.length errors) (if List.length errors = 1 then "" else "s") in
           Ui.Paint.text paint ~at:(tx, ty) ~color:(Pxui.Theme.invalid) count;
           let dx = tx +. Ui.Paint.text_width paint count +. 8. in
           let detail = (match line_of text first with Some l -> Printf.sprintf "line %d \xc2\xb7 " l | None -> "")
             ^ String.map (function '\n' -> ' ' | c -> c) (Flow.Diagnostic.to_string first) in
           Ui.Paint.text paint ~at:(dx, ty) ~color:(Pxui.Theme.ink_2 theme)
             (Ui.ellipsis ~width:(Ui.Paint.text_width paint) ~limit:(x +. w -. tail -. dx) detail)
       | [] ->
           Ui.Paint.text paint ~at:(tx, ty) ~color:(Pxui.Theme.ink_2 theme)
             (Ui.ellipsis ~width:(Ui.Paint.text_width paint) ~limit:(x +. w -. tail -. tx) message));
      if state_label <> "" then
        Ui.Paint.cap paint ~at:(x +. w -. 12. -. Pxui_shell.Kit.cap_width ui state_label, Pxui_shell.Kit.cap_y ui y h)
          state_label);
    (match state.menu with
     | None -> ()
     | Some at ->
         (match Ui.context_menu ui ~at (key ^ "-menu")
                  [ "Check and apply", can_apply; "Discard", can_apply; "", false;
                    (if state.wrap then "Unwrap long lines" else "Wrap long lines"), true;
                    (if state.parinfer then "Parinfer off (keep brackets as typed)"
                     else "Parinfer on (brackets follow indentation)"), true ] with
          | `Open -> ()
          | `Dismiss -> emit (Menu None)
          | `Pick 0 -> emit (Menu None); emit (apply text')
          | `Pick 1 -> emit (Menu None); emit discard
          | `Pick 3 -> emit (Menu None); emit Toggle_wrap
          | `Pick _ -> emit (Menu None); emit Toggle_parinfer)) in
  let message errors ~dirty ~clean = match real_errors errors with
    | d :: _ -> String.map (function '\n' -> ' ' | c -> c) (Flow.Diagnostic.to_string d)
    | [] -> if dirty then "Unapplied draft. Every other pane shows the last applied document."
        else clean in
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
       let spans = if dirty then [] else Option.to_list shown.mark in
       editor "text-graph" ~at:(body_y, body_h) ~text ~errors:(real_errors state.graph_errors)
         ~spans ?reveal:(if dirty then None else Option.map fst shown.mark)
         ~caret_select:(fun byte -> if dirty then None else binding_at shown byte) ~apply:(fun t -> Graph_apply (shown.graph, t)) ~discard:Graph_discard ~can_apply:dirty
         ~message:(message state.graph_errors ~dirty
           ~clean:(Printf.sprintf "Edit %s as text; Check and apply checks the whole workspace." shown.graph))
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
           ~clean:"The selection with what it reads; Check and apply writes the bindings shown.")
         ~draft:(fun t -> Binding_draft (shown.key, t))
         ~scrub:(fun t done_ -> Binding_scrub (shown.key, t, done_)) ());
  List.rev !intents
