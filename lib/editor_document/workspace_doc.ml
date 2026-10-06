module S = Flow.Syntax
module Param = Editor_core.Param

type t = {
  source : S.t list;
  checked : Flow.Workspace.t;
  layout : Layout_by_path.t;
  settings : Settings.t;
  extra : S.t list;
}

let name t = t.checked.name

let editor_graph t =
  List.find_opt (fun (g : Flow.Workspace.graph) -> g.context = Flow.Workspace.Editor
    && Option.fold ~none:true ~some:(( = ) g.name) t.layout.editor) t.checked.graphs

let head (f : S.t) = match f.node with S.List ({ S.node = S.Sym h; _ } :: _) -> Some h | _ -> None

(* ---- settings: (settings :name value ...), only non-default fields ---- *)

let settings_form settings =
  let fields = List.filter (fun (f : Param.field_view) -> f.current <> f.default) (Settings.fields settings) in
  if fields = [] then None
  else
    let value : Param.value -> S.t = function
      | Bool_value b -> S.make (S.Sym (if b then "true" else "false"))
      | Int_value i -> S.make (S.Num (string_of_int i))
      | Float_value x -> S.make (S.Num (Flow.Lisp.float x))
      | Text_value s | Choice_value s -> S.make (S.Str s) in
    Some (S.make (S.List (S.make (S.Sym "settings") :: List.concat_map (fun (f : Param.field_view) ->
      [ S.make (S.Kw f.name); value f.current ]) fields)))

let read_settings base (form : S.t) =
  let ( let* ) = Result.bind in
  let known = Settings.fields base in
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | { S.node = S.Kw k; _ } :: (v : S.t) :: rest ->
        (match List.find_opt (fun (f : Param.field_view) -> f.name = k) known, v.node with
         | None, _ -> Error (Printf.sprintf "unknown setting %s" k)
         | Some { current = Bool_value _; _ }, S.Sym "true" -> go ((k, Param.Bool_value true) :: acc) rest
         | Some { current = Bool_value _; _ }, S.Sym "false" -> go ((k, Param.Bool_value false) :: acc) rest
         | Some { current = Int_value _; _ }, S.Num n when int_of_string_opt n <> None ->
             go ((k, Param.Int_value (int_of_string n)) :: acc) rest
         | Some { current = Float_value _; _ }, S.Num n when float_of_string_opt n <> None ->
             go ((k, Param.Float_value (float_of_string n)) :: acc) rest
         | Some { current = Text_value _; _ }, S.Str s -> go ((k, Param.Text_value s) :: acc) rest
         | Some { current = Choice_value _; _ }, S.Str s -> go ((k, Param.Choice_value s) :: acc) rest
         | Some _, _ -> Error (Printf.sprintf "setting %s has the wrong type" k))
    | _ -> Error "expected :name value pairs" in
  let* changes = go [] (List.tl (S.children form)) in
  Result.map fst (Settings.apply (Settings.defaults base) changes)

(* ---- text ---- *)

let diag ?span code message = Flow.Diagnostic.error ?span ~code message

let check_forms forms =
  let rec go seen = function
    | [] -> Ok ()
    | f :: rest ->
        (match head f with
         | Some name when List.mem name ["workspace"; "layout"; "settings"; "view"] ->
             if List.mem name seen then Error [ diag ~span:f.S.span "E_DOCUMENT_FORM" ("Duplicate " ^ name ^ " form.") ]
             else go (name :: seen) rest
         | _ -> Error [ diag ~span:f.S.span "E_DOCUMENT_FORM"
             "Expected workspace, layout, settings or view at the document root." ]) in
  go [] forms

(* Layout entries live as long as what they name: a key whose node, input or scope is not in
   the checked workspace is dropped, and so is a selected editor layout that is not a graph. *)
let prune (checked : Flow.Workspace.t) catalog (layout : Layout_by_path.t) =
  if Layout_by_path.is_empty layout then layout
  else
    let module P = Flow_sop.Projection in
    let known = Hashtbl.create 256 in
    let rec scope (s : P.scope) =
      Hashtbl.replace known s.path ();
      List.iter (fun (i : P.input) -> Hashtbl.replace known i.path ()) s.inputs;
      List.iter (fun (n : P.node) ->
        Hashtbl.replace known n.path ();
        Option.iter (fun (z : P.zone) -> scope z.scope) n.zone) s.nodes in
    match
      List.iter (fun (g : Flow.Workspace.graph) -> scope (P.of_graph catalog checked g.name)) checked.graphs;
      List.iter (fun (g : Flow.Workspace.graph) -> scope (P.of_graph catalog checked ("def:" ^ g.name))) checked.defs
    with
    | exception Invalid_argument _ -> layout
    | () ->
        (* a scope's own pseudo items ([@result], [@panel n]) are keyed under its path *)
        let rec keep before = function
          | [] -> Hashtbl.mem known (List.rev before)
          | segment :: _ when String.length segment > 0 && segment.[0] = '@' -> Hashtbl.mem known (List.rev before)
          | segment :: rest -> keep (segment :: before) rest in
        let keep = keep [] in
        Layout_by_path.remap (fun path -> if keep path then Some path else None) { layout with editor = None }

let editor_known (checked : Flow.Workspace.t) name =
  List.exists (fun (g : Flow.Workspace.graph) -> g.context = Flow.Workspace.Editor && g.name = name) checked.graphs

let pruned checked catalog (layout : Layout_by_path.t) =
  let editor = Option.bind layout.editor (fun name -> if editor_known checked name then Some name else None) in
  { (prune checked catalog layout) with editor }

let check_text ?(settings = Settings.none) ?(layout = Layout_by_path.empty) catalog text =
  match S.parse text with
  | Error d -> Error [ d ]
  | Ok forms ->
      (match List.find_opt (fun f -> head f = Some "workspace") forms with
       | None -> Error [ diag "E_WORKSPACE" "Expected a (workspace ...) form." ]
       | Some ws ->
           Result.bind (check_forms forms) (fun () ->
           (match Flow.Workspace.check catalog [ ws ] with
            | None, ds -> Error ds
            | Some checked, warnings ->
                let layout = match List.find_opt (fun f -> head f = Some "layout") forms with
                  | None -> Ok layout
                  | Some f -> Result.map_error (fun m -> [ diag ~span:f.S.span "E_LAYOUT" m ]) (Layout_by_path.of_syntax f) in
                Result.bind layout (fun layout ->
                  let settings = match List.find_opt (fun f -> head f = Some "settings") forms with
                    | None -> Ok settings
                    | Some f -> Result.map_error (fun m -> [ diag ~span:f.S.span "E_SETTINGS" m ]) (read_settings settings f) in
                  Result.map (fun settings ->
                    { source = [ ws ]; checked; layout = pruned checked catalog layout; settings;
                      extra = List.filter (fun f -> f != ws) forms }, warnings) settings))))

let of_text ?settings ?layout catalog text = Result.map fst (check_text ?settings ?layout catalog text)

(* The workspace, then the other root forms in the order they were written ([view] verbatim,
   [layout] and [settings] rewritten from the document), each under the comments written above
   the form it replaces.  Comments of a form that is no longer written move to the next one, or
   to the end of the text. *)
let to_text t =
  let fresh = [ "layout", (if Layout_by_path.is_empty t.layout then None else Some (Layout_by_path.to_syntax t.layout));
                "settings", settings_form t.settings ] in
  let written = List.filter_map head t.extra in
  let names = written @ List.filter (fun n -> not (List.mem n written)) [ "layout"; "settings" ] in
  let carried = ref [] in
  let forms = List.filter_map (fun name ->
    let old = List.find_opt (fun f -> head f = Some name) t.extra in
    let notes = !carried @ Option.fold ~none:[] ~some:(fun (f : S.t) -> f.notes) old in
    let tail = Option.fold ~none:[] ~some:(fun (f : S.t) -> f.tail) old in
    match (if name = "view" then old else Option.map (fun (f : S.t) -> { f with tail }) (List.assoc name fresh)) with
    | Some f -> carried := []; Some { f with S.notes }
    | None -> carried := notes @ tail; None) names in
  let forms = t.source @ forms in
  let forms = match List.rev forms with
    | last :: rest when !carried <> [] -> List.rev ({ last with tail = last.tail @ !carried } :: rest)
    | _ -> forms in
  fst (Flow.Lisp.print forms)

let edit catalog t op =
  Result.map (fun (source, checked) ->
    let layout = Layout_by_path.remap (Flow_sop.Flow_edit.remap op) t.layout in
    let layout = match op with
      | Flow_sop.Flow_edit.Connect { node = [ graph; "@result" ]; key = Whole; _ } ->
          { layout with display = Layout_by_path.Path_map.remove [ graph ] layout.display }
      | Flow_sop.Flow_edit.Merge_layouts _ -> { layout with editor = None }  (* the other editor graphs are gone *)
      | _ -> layout in
    { t with source; checked; layout = pruned checked catalog layout })
    (Flow_sop.Flow_edit.apply_checked catalog t.source op)
