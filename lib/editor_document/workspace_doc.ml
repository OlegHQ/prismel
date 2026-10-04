module S = Flow.Syntax
module Param = Editor_core.Param

type t = {
  source : S.t list;
  checked : Flow.Workspace.t;
  layout : Layout_by_path.t;
  settings : Settings.t;
}

let name t = t.checked.name

let editor_graph t =
  List.find_opt (fun (g : Flow.Workspace.graph) -> g.context = Flow.Workspace.Editor
    && Option.fold ~none:true ~some:(( = ) g.name) t.layout.editor) t.checked.graphs

let head (f : S.t) = match f.node with S.List ({ S.node = S.Sym h; _ } :: _) -> Some h | _ -> None

(* ---- settings: (settings :name value ...), only non-default fields ---- *)

let number x =
  let s = List.find_map (fun p ->
    let s = Printf.sprintf "%.*g" p x in if float_of_string s = x then Some s else None) [ 15; 16; 17 ] in
  let s = Option.get s in
  if String.exists (function '.' | 'e' | 'n' | 'i' -> true | _ -> false) s then s else s ^ ".0"

let settings_form settings =
  let fields = List.filter (fun (f : Param.field_view) -> f.current <> f.default) (Settings.fields settings) in
  if fields = [] then None
  else
    let value : Param.value -> S.t = function
      | Bool_value b -> S.make (S.Sym (if b then "true" else "false"))
      | Int_value i -> S.make (S.Num (string_of_int i))
      | Float_value x -> S.make (S.Num (number x))
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

let diag code message = Flow.Diagnostic.error ~code message

let check_forms forms =
  let rec go seen = function
    | [] -> Ok ()
    | f :: rest ->
        (match head f with
         | Some name when List.mem name ["workspace"; "layout"; "settings"; "view"] ->
             if List.mem name seen then Error [Flow.Diagnostic.error ~span:f.S.span
               ~code:"E_DOCUMENT_FORM" ("Duplicate " ^ name ^ " form.")]
             else go (name :: seen) rest
         | _ -> Error [Flow.Diagnostic.error ~span:f.S.span ~code:"E_DOCUMENT_FORM"
             "Expected workspace, layout, settings or view at the document root."]) in
  go [] forms

let of_text ?(settings = Settings.none) ?(layout = Layout_by_path.empty) catalog text =
  match S.parse text with
  | Error d -> Error [ d ]
  | Ok forms ->
      (match List.find_opt (fun f -> head f = Some "workspace") forms with
       | None -> Error [ diag "E_WORKSPACE" "Expected a (workspace ...) form." ]
       | Some ws ->
           Result.bind (check_forms forms) (fun () ->
           (match Flow.Workspace.check catalog [ ws ] with
            | None, ds -> Error ds
            | Some checked, _ ->
                let layout = match List.find_opt (fun f -> head f = Some "layout") forms with
                  | None -> Ok layout
                  | Some f -> Layout_by_path.of_syntax f in
                (match layout with
                 | Error m -> Error [ diag "E_LAYOUT" m ]
                 | Ok layout when layout.editor <> None
                     && editor_graph { source = [ws]; checked; layout; settings } = None ->
                     Error [ diag "E_LAYOUT" ("Unknown editor layout " ^ Option.get layout.editor ^ ".") ]
                 | Ok layout ->
                     let settings = match List.find_opt (fun f -> head f = Some "settings") forms with
                       | None -> Ok settings
                       | Some f -> read_settings settings f in
                     (match settings with
                      | Error m -> Error [ diag "E_SETTINGS" m ]
                      | Ok settings -> Ok { source = [ ws ]; checked; layout; settings })))))

let to_text t =
  let extra = (if Layout_by_path.is_empty t.layout then [] else [ Layout_by_path.to_syntax t.layout ])
    @ Option.to_list (settings_form t.settings) in
  fst (Flow.Lisp.print (t.source @ extra))

let edit catalog t op =
  Result.map (fun (source, checked) ->
    let layout = Layout_by_path.remap (Flow_sop.Flow_edit.remap op) t.layout in
    let layout = match op with
      | Flow_sop.Flow_edit.Connect { node = [ graph; "@result" ]; key = Whole; _ } ->
          { layout with display = Layout_by_path.Path_map.remove [ graph ] layout.display }
      | Flow_sop.Flow_edit.Merge_layouts _ -> { layout with editor = None }  (* the other editor graphs are gone *)
      | _ -> layout in
    { t with source; checked; layout })
    (Flow_sop.Flow_edit.apply_checked catalog t.source op)
