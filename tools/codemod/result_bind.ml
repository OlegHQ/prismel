(* Source-preserving result syntax migration. The compiler parser identifies
   propagation; cleanup/error recovery branches are deliberately left alone. *)
open Parsetree

let parse path source =
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf path;
  Lexer.init ();
  Parse.implementation lexbuf

let bounds loc = loc.Location.loc_start.pos_cnum, loc.loc_end.pos_cnum
let ident name e = e.pexp_attributes = [] && match e.pexp_desc with
  | Pexp_ident { txt = Longident.Lident value; _ } -> value = name
  | _ -> false

let constructor name p = match p.ppat_desc with
  | Ppat_construct ({ txt = Longident.Lident value; _ }, Some ([], payload))
    when value = name && p.ppat_attributes = [] -> Some payload
  | _ -> None

let unit_pattern p = match p.ppat_desc with
  | Ppat_construct ({ txt = Longident.Lident "()"; _ }, None) -> true
  | _ -> false

let bind_pattern p = match p.ppat_desc with Ppat_var name -> name.txt = "let*" | _ -> false

let result_bind expression =
  let is_bind expression = match expression.pexp_desc with
    | Pexp_ident { txt = Longident.Ldot (Longident.Lident "Result", "bind"); _ } -> true
    | _ -> false in
  if is_bind expression then true else match expression.pexp_desc with
  | Pexp_function ([{ pparam_desc = Pparam_val (Nolabel, None, { ppat_desc = Ppat_var a; _ }); _ };
                     { pparam_desc = Pparam_val (Nolabel, None, { ppat_desc = Ppat_var b; _ }); _ }],
                    None, Pfunction_body { pexp_desc = Pexp_apply (fn, [Nolabel, x; Nolabel, y]); _ }) ->
      is_bind fn && ident a.txt x && ident b.txt y
  | _ -> false

let propagation case =
  if case.pc_guard <> None || case.pc_rhs.pexp_attributes <> [] then None else
  match case.pc_lhs.ppat_desc, case.pc_rhs.pexp_desc with
  | Ppat_alias (p, name), _ when ident name.txt case.pc_rhs ->
      (match constructor "Error" p with
       | Some { ppat_desc = Ppat_any; _ } -> Some None
       | _ -> None)
  | _, Pexp_apply (fn, [Nolabel, operation; Nolabel, message])
    when ident "native_error" fn ->
      (match constructor "Error" case.pc_lhs with
       | Some { ppat_desc = Ppat_var name; _ } when ident name.txt message ->
           (* Evaluating the operation eagerly is safe only for inert values. *)
           (match operation.pexp_desc with
            | Pexp_ident _ | Pexp_constant _ -> Some (Some operation)
            | _ -> None)
       | _ -> None)
  | _ -> None

let rewrite path source =
  let tree = parse path source in
  let comments = Lexer.comments () in
  let edits = ref [] and count = ref 0 in
  let piece loc =
    let start, finish = bounds loc in
    let output = Buffer.create (finish - start) in
    let position = List.fold_left (fun position (s, e, text) ->
        if s >= start && e <= finish then begin
          Buffer.add_substring output source position (s - position);
          Buffer.add_string output text;
          e
        end else position) start (List.sort compare !edits) in
    Buffer.add_substring output source position (finish - position);
    Buffer.contents output
  in
  let replace loc text =
    let s, e = bounds loc in
    edits := (s, e, text) :: List.filter (fun (a, b, _) -> a < s || b > e) !edits
  in
  let iterator = { Ast_iterator.default_iterator with
    structure_item = (fun self item ->
      match item.pstr_desc with
      | Pstr_value (_, bindings) when List.exists (fun b -> bind_pattern b.pvb_pat) bindings -> ()
      | _ -> Ast_iterator.default_iterator.structure_item self item);
    expr = (fun self expression ->
      Ast_iterator.default_iterator.expr self expression;
      match expression.pexp_desc with
      | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Ldot (Longident.Lident "Result", "bind"); _ }; _ },
                    [Nolabel, value; Nolabel,
                     { pexp_desc = Pexp_function ([{ pparam_desc = Pparam_val (Nolabel, None, pattern); _ }],
                                                  None, Pfunction_body body); pexp_attributes = []; _ }])
        when expression.pexp_attributes = [] ->
          let s, e = bounds expression.pexp_loc in
          let comments = List.filter_map (fun (_, loc) ->
              let a, b = bounds loc in
              if a >= s && b <= e && not (List.exists (fun loc ->
                  let x, y = bounds loc in a >= x && b <= y) [value.pexp_loc; pattern.ppat_loc; body.pexp_loc])
              then Some (String.sub source a (b - a)) else None) comments in
          replace expression.pexp_loc ("(" ^ String.concat "\n" comments ^ "\nlet* "
              ^ piece pattern.ppat_loc ^ " = (" ^ piece value.pexp_loc ^ ") in\n" ^ piece body.pexp_loc ^ ")");
          incr count
      | Pexp_let (Nonrecursive, [binding], body)
        when bind_pattern binding.pvb_pat && result_bind binding.pvb_expr
             && binding.pvb_attributes = [] && expression.pexp_attributes = [] ->
          let s, _ = bounds expression.pexp_loc and finish, _ = bounds body.pexp_loc in
          let comments = List.filter_map (fun (_, loc) -> let a, b = bounds loc in
              if a >= s && b <= finish then Some (String.sub source a (b - a)) else None) comments in
          replace expression.pexp_loc ("(" ^ String.concat "\n" comments ^ "\n" ^ piece body.pexp_loc ^ ")");
          incr count
      | Pexp_match (value, cases) when expression.pexp_attributes = [] ->
          let failures, successes = List.partition (fun c -> propagation c <> None) cases in
          (match failures, successes with
           | [failure], _ :: _ when failure.pc_lhs.ppat_attributes = [] ->
               let payloads = List.map (fun c -> constructor "Ok" c.pc_lhs) successes in
               let simple = match successes, payloads with
                 | [c], [Some p] when c.pc_guard = None -> Some p
                 | _ -> None in
               let guarded_unit = List.for_all (function Some p -> unit_pattern p | _ -> false) payloads
                 && (List.hd (List.rev successes)).pc_guard = None in
               if simple <> None || guarded_unit then begin
                 let operation = Option.get (propagation failure) in
                 let input = match operation with
                   | None -> piece value.pexp_loc
                   | Some operation -> "native_result (" ^ piece operation.pexp_loc ^ ") (" ^ piece value.pexp_loc ^ ")" in
                 let pattern, body = match simple with
                   | Some pattern -> piece pattern.ppat_loc, piece (List.hd successes).pc_rhs.pexp_loc
                   | None ->
                       let rec branches = function
                         | [{ pc_guard = None; pc_rhs; _ }] -> piece pc_rhs.pexp_loc
                         | { pc_guard = Some guard; pc_rhs; _ } :: rest ->
                             "if (" ^ piece guard.pexp_loc ^ ") then (" ^ piece pc_rhs.pexp_loc
                             ^ ") else (" ^ branches rest ^ ")"
                         | _ -> assert false in
                       "()", branches successes in
                 (* Preserve comments in removed match/branch syntax. Comments
                    inside retained expressions already travel with [piece]. *)
                 let kept = value.pexp_loc :: List.concat_map (fun c ->
                     c.pc_rhs.pexp_loc :: Option.to_list (Option.map (fun e -> e.pexp_loc) c.pc_guard)
                     @ Option.to_list (Option.map (fun p -> p.ppat_loc) (constructor "Ok" c.pc_lhs))) successes
                   @ Option.to_list (Option.map (fun e -> e.pexp_loc) operation) in
                 let s, e = bounds expression.pexp_loc in
                 let comments = List.filter_map (fun (_, loc) ->
                     let a, b = bounds loc in
                     if a >= s && b <= e && not (List.exists (fun loc ->
                         let x, y = bounds loc in a >= x && b <= y) kept)
                     then Some (String.sub source a (b - a)) else None) comments in
                 replace expression.pexp_loc ("(" ^ String.concat "\n" comments
                     ^ "\nlet* " ^ pattern ^ " = (" ^ input ^ ") in\n" ^ body ^ ")");
                 incr count
               end
           | _ -> ())
      | _ -> ()) } in
  iterator.structure iterator tree;
  if !count = 0 then source, 0 else begin
    let output = piece { Location.none with loc_start = { Lexing.dummy_pos with pos_cnum = 0 };
      loc_end = { Lexing.dummy_pos with pos_cnum = String.length source } } in
    (* Keep the operator private to the implementation; no dependency or API. *)
    let items = parse path output in
    let has name = List.exists (fun item -> match item.pstr_desc with
        | Pstr_value (_, bindings) -> List.exists (fun b -> match b.pvb_pat.ppat_desc with
            | Ppat_var value -> value.txt = name | _ -> false) bindings
        | _ -> false) items in
    let insertion = match List.find_opt (fun item -> match item.pstr_desc with
        | Pstr_value (_, bindings) -> List.exists (fun binding ->
            match binding.pvb_pat.ppat_desc with Ppat_var name -> name.txt = "native" | _ -> false) bindings
        | _ -> false) items with
      | Some item -> item.pstr_loc.loc_end.pos_cnum
      | None -> failwith "result-bind requires the existing native error adapter" in
    let output = if has "native_result" && has "let*" then output
      else if has "native_result" || has "let*" then failwith "result-bind helper name collision"
      else String.sub output 0 insertion ^ {|

let native_result = native

(* The Metal build lowers these binds to matches without continuations. *)
let ( let* ) = Result.bind
|}
      ^ String.sub output insertion (String.length output - insertion) in
    ignore (parse path output);
    output, !count
  end

(* Format the changed value definitions only, keeping unrelated declarations
   and whitespace byte-for-byte. One formatter invocation covers the file. *)
let format_changed path before after =
  let values source =
    let items = ref [] in
    let iterator = { Ast_iterator.default_iterator with
      structure_item = (fun self item ->
        (match item.pstr_desc with Pstr_value _ -> items := item :: !items | _ -> ());
        Ast_iterator.default_iterator.structure_item self item) } in
    iterator.structure iterator (parse path source);
    List.rev !items in
  let key item = match item.pstr_desc with
    | Pstr_value (_, bindings) -> String.concat "," (List.map (fun binding ->
        Format.asprintf "%a" Pprintast.pattern binding.pvb_pat) bindings)
    | _ -> assert false in
  let originals = Hashtbl.create 256 in
  List.iter (fun item ->
      let name = key item in
      Hashtbl.replace originals name (Option.value (Hashtbl.find_opt originals name) ~default:[] @ [item]))
    (values before);
  let temporary = Filename.temp_file "prismel-result-bind-format-" ".ml" in
  Fun.protect ~finally:(fun () -> Sys.remove temporary) (fun () ->
    Out_channel.with_open_bin temporary (fun channel -> output_string channel after);
    if Sys.command ("ocamlformat --enable-outside-detected-project --inplace --margin 100 "
        ^ Filename.quote temporary) <> 0 then failwith "result-bind formatter failed";
    let formatted = In_channel.with_open_bin temporary In_channel.input_all in
    let edits = List.filter_map (fun (item, formatted_item) ->
        let previous = match Hashtbl.find_opt originals (key item) with
          | Some (first :: rest) -> Hashtbl.replace originals (key item) rest; Some first
          | _ -> None in
        if (match previous with Some previous -> Format.asprintf "%a" Pprintast.structure [previous]
            = Format.asprintf "%a" Pprintast.structure [item] | None -> false) then None else
        let s, e = bounds item.pstr_loc and a, b = bounds formatted_item.pstr_loc in
        let indentation = item.pstr_loc.loc_start.pos_cnum - item.pstr_loc.loc_start.pos_bol
        and formatted_indentation = formatted_item.pstr_loc.loc_start.pos_cnum - formatted_item.pstr_loc.loc_start.pos_bol in
        let text = String.sub formatted a (b - a) |> String.split_on_char '\n'
          |> List.mapi (fun index line -> if index = 0 || line = "" then line else
              String.make indentation ' ' ^ String.sub line (min formatted_indentation (String.length line))
                (max 0 (String.length line - formatted_indentation))) |> String.concat "\n" in
        Some (s, e, text)) (List.combine (values after) (values formatted)) in
    let buffer = Buffer.create (String.length after) in
    let position = List.fold_left (fun position (s, e, text) ->
        if s < position then position else begin
          Buffer.add_substring buffer after position (s - position);
          Buffer.add_string buffer text;
          e
        end) 0 edits in
    Buffer.add_substring buffer after position (String.length after - position);
    let output = Buffer.contents buffer in
    if Format.asprintf "%a" Pprintast.structure (parse path output)
       <> Format.asprintf "%a" Pprintast.structure (parse path after)
    then failwith "result-bind formatting changed the AST";
    output)

let migrate path =
  let source = In_channel.with_open_bin path In_channel.input_all in
  let output, count = rewrite path source in
  if count > 0 then begin
    let output = format_changed path source output in
    Out_channel.with_open_bin path (fun channel -> output_string channel output)
  end;
  Printf.printf "%s: %d result rewrites\n%!" path count

(* Compare compiler trees after canonicalizing only the syntax being migrated.
   Cleanup branches and all other expressions must remain structurally equal. *)
let canonical tree =
  let open Ast_helper in
  let name value = Location.mknoloc (Longident.Lident value) in
  let variable value = Pat.var (Location.mknoloc value) in
  let identifier value = Exp.ident (name value) in
  let result input operation pattern body =
    let failure = match operation with
      | None -> Exp.case (Pat.alias (Pat.construct (name "Error") (Some ([], Pat.any ())))
          (Location.mknoloc "__failure")) (identifier "__failure")
      | Some operation -> Exp.case (Pat.construct (name "Error") (Some ([], variable "__message")))
          (Exp.apply (identifier "native_error") [Nolabel, operation; Nolabel, identifier "__message"]) in
    Exp.match_ input [failure; Exp.case (Pat.construct (name "Ok") (Some ([], pattern))) body] in
  let mapper = { Ast_mapper.default_mapper with
    structure = (fun self items ->
      let items = Ast_mapper.default_mapper.structure self items in
      let used = ref false in
      let iterator = { Ast_iterator.default_iterator with expr = (fun self expression ->
        (match expression.pexp_desc with Pexp_ident { txt = Longident.Lident "on_main"; _ } -> used := true | _ -> ());
        Ast_iterator.default_iterator.expr self expression) } in
      iterator.structure iterator items;
      if !used then items else List.filter (fun item -> match item.pstr_desc with
        | Pstr_value (Nonrecursive, [{ pvb_pat = { ppat_desc = Ppat_var name; _ };
                                      pvb_expr = { pexp_desc = Pexp_function _; _ }; _ }]) -> name.txt <> "on_main"
        | _ -> true) items);
    expr = (fun self expression ->
      let expression = Ast_mapper.default_mapper.expr self expression in
      match expression.pexp_desc with
      | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Lident "on_main"; _ }; _ },
                    [Nolabel, operation; Nolabel,
                     { pexp_desc = Pexp_function ([{ pparam_desc = Pparam_val (Nolabel, None, pattern); _ }],
                                                  None, Pfunction_body body); pexp_attributes = []; _ }])
        when unit_pattern pattern && (match operation.pexp_desc with Pexp_ident _ | Pexp_constant _ -> true | _ -> false) ->
          result (Exp.apply (identifier "before_main") [Nolabel, operation]) None pattern body
      | Pexp_letop { let_ = binding; ands = []; body } when binding.pbop_op.txt = "let*" ->
          result binding.pbop_exp None binding.pbop_pat body
      | Pexp_let (Nonrecursive, [binding], body) when bind_pattern binding.pvb_pat && result_bind binding.pvb_expr -> body
      | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Longident.Ldot (Longident.Lident "Result", "bind"); _ }; _ },
                    [Nolabel, input; Nolabel,
                     { pexp_desc = Pexp_function ([{ pparam_desc = Pparam_val (Nolabel, None, pattern); _ }],
                                                  None, Pfunction_body body); _ }]) -> result input None pattern body
      | Pexp_match (input, cases) ->
          let failures, successes = List.partition (fun c -> propagation c <> None) cases in
          (match failures, successes with
           | [failure], [success] ->
               (match constructor "Ok" success.pc_lhs, success.pc_guard with
                | Some pattern, None -> result input (Option.get (propagation failure)) pattern success.pc_rhs
                | _ -> expression)
           | [failure], _ :: _ when List.for_all (fun c ->
               match constructor "Ok" c.pc_lhs with Some p -> unit_pattern p | _ -> false) successes ->
               let rec branches = function
                 | [{ pc_guard = None; pc_rhs; _ }] -> Some pc_rhs
                 | { pc_guard = Some guard; pc_rhs; _ } :: rest ->
                     Option.map (fun rest -> Exp.ifthenelse guard pc_rhs (Some rest)) (branches rest)
                 | _ -> None in
               (match branches successes with
                | Some body -> result input (Option.get (propagation failure)) (Pat.construct (name "()") None) body
                | None -> expression)
           | _ -> expression)
      | _ -> expression) } in
  Format.asprintf "%a" Pprintast.structure (mapper.structure mapper tree)

let verify before after ppx =
  let read path = In_channel.with_open_bin path In_channel.input_all in
  let temporary = Filename.temp_file "prismel-result-bind-verify-" ".ml" in
  Fun.protect ~finally:(fun () -> Sys.remove temporary) (fun () ->
    if Sys.command (Filename.quote ppx ^ " --text " ^ Filename.quote after ^ " > " ^ Filename.quote temporary) <> 0
    then failwith "result-bind preprocessing failed";
    let original = canonical (parse before (read before))
    and migrated = canonical (parse after (read temporary)) in
    if original <> migrated then begin
      Out_channel.with_open_bin "/tmp/prismel-result-bind-original.ast" (fun channel -> output_string channel original);
      Out_channel.with_open_bin "/tmp/prismel-result-bind-migrated.ast" (fun channel -> output_string channel migrated);
      failwith "result-bind changed the compiler tree beyond result syntax (see /tmp/prismel-result-bind-*.ast)"
    end;
    print_endline "result-bind: entire compiler tree matches after result-syntax normalization")

let self_test ppx =
  let fixture = {|
let native_error operation message = Error (operation ^ ":" ^ message)
let native operation = function Ok x -> Ok x | Error m -> native_error operation m
let trace = ref []
let main_allowed = ref true
let before_main _ = trace := 20 :: !trace; if !main_allowed then Ok () else Error "wrong domain"
let on_main operation callback =
  match before_main operation with Error _ as failure -> failure | Ok () -> callback ()
let wrapper () = on_main "main" (fun () -> trace := 21 :: !trace; Ok 42)
let dynamic_wrapper callback = on_main "main" callback
let effect_wrapper () = on_main (trace := 19 :: !trace; "main") (fun () -> trace := 21 :: !trace; Ok 42)
let guard_mode = ref 0
let step n result = trace := n :: !trace; result
let run result =
  let ( let* ) value callback = Result.bind value callback in
  match step 1 result with
  | Error _ as failure -> (* propagate *) failure
  | Ok () when (trace := 2 :: !trace; !guard_mode = 1) -> Ok 11
  | Ok () when (trace := 3 :: !trace; !guard_mode = 2) -> Ok 22
  | Ok () -> (
      match step 4 (Ok (7, 8)) with
      | Ok (a, b) ->
          (match step 5 (if a = 7 then Ok b else Error "bad") with
           | Error message -> native_error "test" message
           | Ok value -> Ok value)
      | Error _ as e -> e)
let cleanup result =
  match result with
  | Error m -> trace := 9 :: !trace; native_error "cleanup" m
  | Ok value -> Ok value
let shadowed_native native =
  match native () with
  | Error m -> native_error "shadow" m
  | Ok value -> Ok value
let direct_bind result = Result.bind result (fun (a, b) -> Ok (a + b))
let capture __metal_native_message result =
  match result with
  | Error m -> native_error __metal_native_message m
  | Ok value -> Ok value
let eager_operation result =
  match result with
  | Error m -> native_error (trace := 10 :: !trace; "late") m
  | Ok value -> Ok value
let () =
  List.iter (fun mode -> guard_mode := mode; List.iter (fun result ->
    trace := [];
    let outcome = run result in
    Printf.printf "%s:%s\n" (match outcome with Ok n -> string_of_int n | Error e -> e)
      (String.concat "," (List.map string_of_int (List.rev !trace)))) [Ok (); Error "first"]) [0; 1; 2];
  List.iter (fun result -> ignore (cleanup result); ignore (eager_operation result)) [Ok 1; Error "failure"];
  List.iter (fun result -> ignore (shadowed_native (fun () -> result))) [Ok 1; Error "failure"];
  assert (direct_bind (Ok (1, 2)) = Ok 3);
  assert (direct_bind (Error "failure") = Error "failure");
  assert (shadowed_native (fun () -> Error "failure") = Error "shadow:failure");
  assert (capture "outer" (Error "failure") = Error "outer:failure");
  trace := [];
  assert (wrapper () = Ok 42 && List.rev !trace = [20; 21]);
  trace := []; main_allowed := false;
  assert (wrapper () = Error "wrong domain" && List.rev !trace = [20]);
  trace := []; main_allowed := true;
  assert (dynamic_wrapper (fun () -> trace := 22 :: !trace; Ok 43) = Ok 43 && List.rev !trace = [20; 22]);
  trace := [];
  assert (effect_wrapper () = Ok 42 && List.rev !trace = [19; 20; 21]);
  trace := []; main_allowed := false;
  assert (effect_wrapper () = Error "wrong domain" && List.rev !trace = [19; 20]);
  Printf.printf "cleanup:%s\n" (String.concat "," (List.map string_of_int (List.rev !trace)))
|} in
  let output, count = rewrite "fixture.ml" fixture in
  assert (count = 8);
  assert (snd (rewrite "fixture.ml" output) = 0);
  let incremental, count = rewrite "fixture.ml" (output ^ "\nlet extra r = match r with Error _ as e -> e | Ok () -> Ok ()\n") in
  assert (count = 1 && snd (rewrite "fixture.ml" incremental) = 0);
  assert (try ignore (Str.search_forward (Str.regexp_string "(* propagate *)") output 0); true with Not_found -> false);
  let execute ~preprocess source =
    let path = Filename.temp_file "prismel-result-bind-" ".ml" in
    let binary = path ^ ".exe" and log = path ^ ".log" in
    Fun.protect ~finally:(fun () -> List.iter (fun file -> if Sys.file_exists file then Sys.remove file)
        [path; binary; log; Filename.chop_extension path ^ ".cmo"; Filename.chop_extension path ^ ".cmi"])
      (fun () ->
         Out_channel.with_open_bin path (fun channel -> output_string channel source);
         let preprocess = if preprocess then " -pp " ^ Filename.quote (Filename.quote ppx) else "" in
         assert (Sys.command ("ocamlc -w -a" ^ preprocess ^ " -o " ^ Filename.quote binary ^ " " ^ Filename.quote path) = 0);
         assert (Sys.command (Filename.quote binary ^ " > " ^ Filename.quote log) = 0);
         In_channel.with_open_bin log In_channel.input_all) in
  assert (execute ~preprocess:false fixture = execute ~preprocess:true output);
  assert (execute ~preprocess:true output = execute ~preprocess:true incremental);
  let before = Filename.temp_file "prismel-result-bind-before-" ".ml"
  and after = Filename.temp_file "prismel-result-bind-after-" ".ml" in
  Fun.protect ~finally:(fun () -> Sys.remove before; Sys.remove after) (fun () ->
    Out_channel.with_open_bin before (fun channel -> output_string channel fixture);
    Out_channel.with_open_bin after (fun channel -> output_string channel output);
    verify before after ppx);
  print_endline "result-bind: success, short-circuit, guards, cleanup, evaluation order, comments and idempotence passed"
