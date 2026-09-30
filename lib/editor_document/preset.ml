let ( let* ) = Result.bind

type loaded = { doc : Document.t; view : Yojson.Safe.t }

let sanitize name = String.map (function
  | ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-') as character -> character
  | _ -> '_') (String.trim name)

let default_name () =
  let time = Unix.localtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d_%02d-%02d-%02d" (time.tm_year + 1900)
    (time.tm_mon + 1) time.tm_mday time.tm_hour time.tm_min time.tm_sec

let suffix = ".plisp"
let path ~directory ~name = Filename.concat directory (sanitize name ^ suffix)

(* ---- the environment view: a JSON-shaped value kept in memory, written as an s-expression ---- *)

module S = Flow.Syntax

let mk node = S.make node
let rec view_syntax : Yojson.Safe.t -> S.t = function
  | `Assoc fields -> mk (S.Map (List.concat_map (fun (k, v) -> [ mk (S.Kw k); view_syntax v ]) fields))
  | `List l -> mk (S.Vec (List.map view_syntax l))
  | `Int i -> mk (S.Num (string_of_int i))
  | `Intlit s -> mk (S.Num s)
  | `Float x ->
      let s = List.find_map (fun p -> let s = Printf.sprintf "%.*g" p x in
        if float_of_string s = x then Some s else None) [ 15; 16; 17 ] in
      let s = Option.get s in
      mk (S.Num (if String.exists (function '.' | 'e' -> true | _ -> false) s then s else s ^ ".0"))
  | `String s -> mk (S.Str s)
  | `Bool b -> mk (S.Sym (if b then "true" else "false"))
  | `Null -> mk (S.Sym "nil")

let rec view_json (f : S.t) : (Yojson.Safe.t, string) result = match f.node with
  | S.Map l ->
      let rec go acc = function
        | [] -> Ok (`Assoc (List.rev acc))
        | { S.node = S.Kw k; _ } :: v :: rest -> let* v = view_json v in go ((k, v) :: acc) rest
        | _ -> Error "view: expected :name value pairs" in
      go [] l
  | S.Vec l -> let* l = List.fold_right (fun x acc -> let* acc = acc in let* x = view_json x in Ok (x :: acc)) l (Ok []) in Ok (`List l)
  | S.Num n -> (match int_of_string_opt n with
      | Some i -> Ok (`Int i)
      | None -> (match float_of_string_opt n with Some x -> Ok (`Float x) | None -> Error "view: bad number"))
  | S.Str s -> Ok (`String s)
  | S.Sym "true" -> Ok (`Bool true)
  | S.Sym "false" -> Ok (`Bool false)
  | S.Sym "nil" -> Ok `Null
  | _ -> Error "view: unreadable value"

let rec finite = function
  | `Float x -> Float.is_finite x
  | `Assoc fields -> List.for_all (fun (_, v) -> finite v) fields
  | `List l -> List.for_all finite l
  | _ -> true

(* ---- files ---- *)

let flow_catalog factories = Contexts.catalog ~version:1 factories

(* the text of the document: a settings graph owns the settings; else the document's are the
   sketch's, saved beside the text *)
let text (doc : Document.t) =
  let workspace, _ = doc.workspace in
  Workspace_doc.to_text (if Contexts.has_settings workspace then workspace
    else { workspace with settings = doc.settings })

let save ~directory ~name ~(doc : Document.t) ~view =
  if sanitize name = "" then Error "preset name is empty" else
  let* () = if finite view then Ok () else Error "viewport contains nonfinite values" in
  let text = text doc in
  let view_text = fst (Flow.Lisp.print [ mk (S.List [ mk (S.Sym "view"); view_syntax view ]) ]) in
  let target = path ~directory ~name in
  Editor_core.Store.write_text ~filename:target (text ^ "\n" ^ view_text)
  |> Result.map (fun () -> target)

let list ~directory =
  match Sys.readdir directory with
  | exception Sys_error _ -> []
  | files ->
      Array.to_list files
      |> List.filter_map (fun file ->
        if not (Filename.check_suffix file suffix) then None
        else match Unix.stat (Filename.concat directory file) with
          | { Unix.st_mtime; _ } -> Some (Filename.chop_suffix file suffix, st_mtime)
          | exception Unix.Unix_error _ -> None)
      |> List.sort (fun (a, at) (b, bt) ->
        let order = Float.compare bt at in if order <> 0 then order else String.compare a b)

let delete ~directory ~name =
  try Sys.remove (path ~directory ~name); Ok () with Sys_error message -> Error message

let load ~path ~factories ~settings =
  let* text = Editor_core.Store.read_text ~filename:path in
  let diagnostics ds = String.concat "\n" (List.map Flow.Diagnostic.to_string ds) in
  let* catalog = Result.map_error Flow.Diagnostic.to_string (flow_catalog factories) in
  let* workspace = Result.map_error diagnostics (Workspace_doc.of_text ~settings catalog text) in
  let* view = match S.parse text with
    | Error d -> Error (Flow.Diagnostic.to_string d)
    | Ok forms ->
        (match List.find_opt (fun (f : S.t) -> match f.node with
           | S.List ({ S.node = S.Sym "view"; _ } :: _) -> true | _ -> false) forms with
         | Some { S.node = S.List [ _; v ]; _ } -> view_json v
         | Some _ -> Error "view: expected one value"
         | None -> Ok `Null) in
  let* doc = Result.map_error Flow.Diagnostic.to_string (Contexts.of_workspace ~factories workspace) in
  let* () = Document.validate doc in
  Ok { doc; view }
