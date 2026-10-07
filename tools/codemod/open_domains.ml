(* Constructor migrations use compiler types, never spelling alone: Port_type.Geometry
   and Document.Scene remain constructors. Preserve source layout and comments. *)
let nominal = ["Geometry"; "Drawing"; "Scene"; "World"; "Settings"; "Panel"; "Editor"; "Material"]
let contexts = ["Sop"; "Value"; "Draw"; "Scene"; "World"; "Settings"; "Editor"; "Material"]

let owner (c : Types.constructor_description) =
  let file = c.cstr_loc.loc_start.pos_fname in
  if Filename.check_suffix file "lib/flow/ty.mli" then Some `Ty
  else if Filename.check_suffix file "lib/flow/context.mli"
    || Filename.check_suffix file "lib/flow/workspace.mli" then Some `Context
  else None

let replacement ~pattern ~internal c =
  let prefix = if internal then "" else "Flow." in
  match owner c with
  | Some `Ty when List.mem c.Types.cstr_name nominal ->
      let name = String.lowercase_ascii c.cstr_name in
      Some (if pattern then "(" ^ prefix ^ "Ty.Named " ^ Printf.sprintf "%S" name ^ ")" else prefix ^ "Ty." ^ name)
  | Some `Context when not pattern && List.mem c.Types.cstr_name contexts ->
      Some (prefix ^ "Context." ^ String.lowercase_ascii c.cstr_name)
  | _ -> None

let constructor_spans file source =
  let spans = Hashtbl.create 64 in
  let add pattern (name : Longident.t Location.loc) =
    Hashtbl.replace spans (pattern, name.loc.loc_start.pos_cnum, name.loc.loc_end.pos_cnum,
      String.concat "." (Longident.flatten name.txt)) () in
  let it = {Ast_iterator.default_iterator with
    expr = (fun self e ->
      (match e.Parsetree.pexp_desc with Pexp_construct (name, None) -> add false name | _ -> ());
      Ast_iterator.default_iterator.expr self e);
    pat = (fun self p ->
      (match p.Parsetree.ppat_desc with Ppat_construct (name, None) -> add true name | _ -> ());
      Ast_iterator.default_iterator.pat self p)} in
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf file;
  it.structure it (Parse.implementation lexbuf);
  spans

let migrate ~apply =
  let edits = Hashtbl.create 64 in
  let inspect file (info : Cmt_format.cmt_infos) =
    if file <> "lib/flow/ty.ml" && file <> "lib/flow/context.ml" && Sys.file_exists file then
    match info.cmt_annots with
    | Implementation tree ->
        let source = In_channel.with_open_bin file In_channel.input_all in
        let spans = constructor_spans file source in
        let add pattern expected loc text =
          let start = loc.Location.loc_start.pos_cnum and finish = loc.loc_end.pos_cnum in
          if not loc.loc_ghost && Hashtbl.mem spans
              (pattern, start, finish, String.concat "." (Longident.flatten expected)) then
            Hashtbl.replace edits file
              ((start, finish, text) :: Option.value ~default:[] (Hashtbl.find_opt edits file)) in
        let internal = String.starts_with ~prefix:"lib/flow/" file in
        let it = {Tast_iterator.default_iterator with
          expr = (fun self e ->
            (match e.Typedtree.exp_desc with
             | Texp_construct (name, c, []) -> Option.iter (add false name.txt name.loc) (replacement ~pattern:false ~internal c)
             | _ -> ());
            Tast_iterator.default_iterator.expr self e);
          pat = (fun (type k) self (p : k Typedtree.general_pattern) ->
            (match p.pat_desc with
             | Tpat_construct (name, c, [], _) -> Option.iter (add true name.txt name.loc) (replacement ~pattern:true ~internal c)
             | _ -> ());
            Tast_iterator.default_iterator.pat self p)} in
        it.structure it tree
    | _ -> () in
  let rec walk dir = Array.iter (fun name ->
    let path = Filename.concat dir name in
    if Sys.is_directory path then walk path
    else if Filename.check_suffix path ".cmt" then
      match Cmt_format.read_cmt path with
      | info ->
          let file = Option.value ~default:"" info.cmt_sourcefile in
          let file = if Filename.check_suffix file ".pp.ml" then Filename.chop_suffix file ".pp.ml" ^ ".ml" else file in
          inspect file info
      | exception _ -> ()) (Sys.readdir dir) in
  walk "_build/default";
  Hashtbl.to_seq edits |> List.of_seq |> List.sort compare |> List.iter (fun (file, edits) ->
    let source = In_channel.with_open_bin file In_channel.input_all in
    let output = Buffer.create (String.length source) in
    let position = List.fold_left (fun position (start, finish, text) ->
      if start < position || finish > String.length source then failwith ("overlapping/stale constructor locations in " ^ file);
      Buffer.add_substring output source position (start - position);
      Buffer.add_string output text;
      finish) 0 (List.sort_uniq compare edits) in
    Buffer.add_substring output source position (String.length source - position);
    Printf.printf "%s: %d constructor uses\n" file (List.length (List.sort_uniq compare edits));
    if apply then Out_channel.with_open_bin file (fun oc -> output_string oc (Buffer.contents output)))

let self_test () =
  (* The declaration location disambiguates constructors with identical names. *)
  let loc file = {Location.none with loc_start = {Lexing.dummy_pos with pos_fname = file}} in
  let fake : Types.constructor_description =
    {cstr_name = "Geometry"; cstr_res = Btype.newgenty (Tvar None); cstr_existentials = [];
     cstr_args = []; cstr_arity = 0; cstr_tag = Cstr_constant 0; cstr_consts = 0;
     cstr_nonconsts = 0; cstr_generalized = false;
     cstr_private = Asttypes.Public; cstr_loc = loc "lib/flow/ty.mli";
     cstr_attributes = []; cstr_inlined = None; cstr_uid = Shape.Uid.internal_not_actually_unique} in
  assert (replacement ~pattern:false ~internal:false fake = Some "Flow.Ty.geometry");
  assert (replacement ~pattern:true ~internal:true fake = Some "(Ty.Named \"geometry\")");
  assert (replacement ~pattern:false ~internal:true {fake with cstr_loc = loc "lib/flow/port_type.mli"} = None);
  let source = "let x = Flow.Ty.Geometry\nlet text = \"Flow.Ty.Geometry\"\n(* Flow.Ty.Geometry *)\n" in
  let spans = constructor_spans "test.ml" source in
  assert (Hashtbl.length spans = 1);
  assert (Hashtbl.mem spans (false, 8, 24, "Flow.Ty.Geometry"))
