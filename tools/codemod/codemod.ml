(* Compiler-driven dead-code codemods.

   dead-exports [--users-exclude SUBSTR]... DIR...
     Reads every .cmt under _build/default, resolves each identifier
     occurrence to its defining uid through compiler shapes, and prints
     "file.mli<TAB>Path.name" for every value exported by a unit under DIR
     that no other source file references.
   drop-vals FILE.mli NAME...     Remove [val]/[external] items (with docs).
   drop-unused < build-log        Remove the let bindings named by warning 32
                                  (unused value) in a dune build log.

   The compiler is the oracle: prune with drop-vals, rebuild, feed the log to
   drop-unused, repeat until the build is clean. *)

let read_file path = In_channel.with_open_bin path In_channel.input_all
let write_file path s = Out_channel.with_open_bin path (fun oc -> output_string oc s)

let rec walk dir f =
  Array.iter (fun name ->
    let path = Filename.concat dir name in
    if Sys.is_directory path then (if name.[0] <> '.' || Filename.check_suffix name "objs" || name = "byte" then walk path f) else f path)
    (Sys.readdir dir)

(* ---------- dead-exports ---------- *)

let dead_exports ~excludes dirs =
  let build = "_build/default" in
  let cmts = ref [] in
  walk build (fun p -> if Filename.check_suffix p ".cmt" then cmts := p :: !cmts);
  let infos = List.filter_map (fun p ->
    match Cmt_format.read_cmt p with
    | info -> Some (p, info)
    | exception _ -> None) !cmts in
  let shapes = Hashtbl.create 4096 in
  List.iter (fun (_, (i : Cmt_format.cmt_infos)) ->
    Option.iter (Hashtbl.replace shapes i.cmt_modname) i.cmt_impl_shape) infos;
  let source (i : Cmt_format.cmt_infos) = Option.value i.cmt_sourcefile ~default:"" in
  let excluded file = List.exists (fun s ->
    let n = String.length s and m = String.length file in
    let rec go k = k + n <= m && (String.sub file k n = s || go (k + 1)) in go 0) excludes in
  (* uid -> source files that reference it *)
  let users : (Shape.Uid.t, string list) Hashtbl.t = Hashtbl.create 65536 in
  let unresolved_names = Hashtbl.create 4096 in
  List.iter (fun (_, (i : Cmt_format.cmt_infos)) ->
    let file = source i in
    if not (excluded file) then begin
      let module R = Shape_reduce.Make (struct
        let fuel = 10
        let read_unit_shape ~unit_name = Hashtbl.find_opt shapes unit_name
      end) in
      let rec uids depth (r : Shape_reduce.result) = match r with
        | Resolved u | Approximated (Some u) -> [u]
        | Resolved_alias (u, r) -> u :: uids depth r
        | Unresolved s when depth = 0 -> uids 1 (R.reduce_for_uid Env.empty s)
        | _ -> [] in
      List.iter (fun ((lid : Longident.t Location.loc), r) ->
        match uids 0 r with
        | [] -> Hashtbl.replace unresolved_names (Longident.last lid.txt) ()
        | us -> List.iter (fun u ->
            let prev = Option.value (Hashtbl.find_opt users u) ~default:[] in
            if not (List.mem file prev) then Hashtbl.replace users u (file :: prev)) us)
        i.cmt_ident_occurrences
    end) infos;
  let under file = List.exists (fun d ->
    let d = if Filename.check_suffix d "/" then d else d ^ "/" in
    String.length file > String.length d && String.sub file 0 (String.length d) = d) dirs in
  let rec head s = match (s : Shape.t).desc with Alias s -> head s | _ -> s in
  let find shape name kind = match (head shape).desc with
    | Struct map -> Shape.Item.Map.find_opt (Shape.Item.make name kind) map
    | _ -> None in
  let results = ref [] in
  List.iter (fun (p, (i : Cmt_format.cmt_infos)) ->
    let ml = source i in
    let cmti = Filename.chop_suffix p ".cmt" ^ ".cmti" in
    if under ml && Filename.check_suffix ml ".ml" && Sys.file_exists cmti then
      match i.cmt_impl_shape, (Cmt_format.read_cmt cmti).cmt_annots with
      | Some shape, Interface sg ->
          let mli = Filename.chop_suffix ml ".ml" ^ ".mli" in
          let rec scan prefix shape items = List.iter (function
            | Types.Sig_value (id, _, _) ->
                let name = Ident.name id in
                (match find shape name Shape.Sig_component_kind.Value with
                 | Some { uid = Some uid; _ } ->
                     let used = match Hashtbl.find_opt users uid with
                       | Some files -> List.exists (fun f -> f <> ml) files
                       | None -> false in
                     if not used && not (Hashtbl.mem unresolved_names name) then
                       results := (mli, prefix ^ name) :: !results
                 | _ -> ())
            | Sig_module (id, _, { md_type = Mty_signature items; _ }, _, _) ->
                (match find shape (Ident.name id) Shape.Sig_component_kind.Module with
                 | Some sub -> scan (prefix ^ Ident.name id ^ ".") sub items
                 | None -> ())
            | _ -> ()) items in
          scan "" shape sg.sig_type
      | _ -> ()) infos;
  List.sort compare !results

(* ---------- text removal ---------- *)

let parse_with f path =
  let src = read_file path in
  let lexbuf = Lexing.from_string src in
  Location.init lexbuf path;
  Lexer.init ();
  src, f lexbuf

(* Byte range of an item plus its attached doc comments, widened to whole
   lines when nothing else shares them. *)
let range src (loc : Location.t) (attrs : Parsetree.attributes) =
  let s = List.fold_left (fun a (at : Parsetree.attribute) ->
    min a at.attr_loc.loc_start.pos_cnum) loc.loc_start.pos_cnum attrs in
  let e = List.fold_left (fun a (at : Parsetree.attribute) ->
    max a at.attr_loc.loc_end.pos_cnum) loc.loc_end.pos_cnum attrs in
  let rec back i = if i > 0 && (src.[i-1] = ' ' || src.[i-1] = '\t') then back (i-1) else i in
  let rec fwd i = if i < String.length src && (src.[i] = ' ' || src.[i] = '\t') then fwd (i+1) else i in
  let s' = back s and e' = fwd e in
  if (s' = 0 || src.[s'-1] = '\n') && (e' >= String.length src || src.[e'] = '\n')
  then s', min (String.length src) (e' + 1) else s, e

let remove_ranges ?(subst = []) path src ranges =
  let edits = List.sort_uniq compare (List.map (fun (s, e) -> s, e, "") ranges @ subst) in
  let b = Buffer.create (String.length src) in
  let pos = List.fold_left (fun pos (s, e, text) ->
    if s < pos then pos
    else (Buffer.add_string b (String.sub src pos (s - pos)); Buffer.add_string b text; e)) 0 edits in
  Buffer.add_string b (String.sub src pos (String.length src - pos));
  (* collapse runs of blank lines left behind *)
  let out = Buffer.contents b in
  let re = Str.regexp "\n\n\n+" in
  write_file path (Str.global_replace re "\n\n" out)

let drop_vals path names =
  let src, sg = parse_with Parse.interface path in
  let ranges = ref [] and found = ref [] in
  let rec go prefix items = List.iter (fun (item : Parsetree.signature_item) ->
    match item.psig_desc with
    | Psig_value vd when List.mem (prefix ^ vd.pval_name.txt) names ->
        found := (prefix ^ vd.pval_name.txt) :: !found;
        ranges := range src item.psig_loc vd.pval_attributes :: !ranges
    | Psig_module { pmd_name = { txt = Some m; _ }; pmd_type = { pmty_desc = Pmty_signature s; _ }; _ } ->
        go (prefix ^ m ^ ".") s
    | _ -> ()) items in
  go "" sg;
  List.iter (fun n -> if not (List.mem n !found) then
    Printf.eprintf "drop-vals: %s: %s not found\n" path n) names;
  if !ranges <> [] then remove_ranges path src !ranges

(* ---------- drop-unused (warnings 32 value, 33 open, 34 type, 60 module) ---------- *)

let header = Str.regexp
  "File \"\\([^\"]+\\)\", line \\([0-9]+\\), characters \\([0-9]+\\)-[0-9]+:"
let warning = Str.regexp ".*(warning \\([0-9]+\\) "

let contains s sub =
  let n = String.length sub and m = String.length s in
  let rec go k = k + n <= m && (String.sub s k n = sub || go (k + 1)) in go 0

(* (file, line, col, warning) for every diagnostic in a dune log; warning 0
   marks a hard error. *)
let diagnostics log =
  let rec go acc = function
    | l :: rest when Str.string_match header l 0 ->
        let file = Str.matched_group 1 l and line = int_of_string (Str.matched_group 2 l)
        and col = int_of_string (Str.matched_group 3 l) in
        let rec kind = function
          | w :: r when Str.string_match warning w 0 ->
              let n = int_of_string (Str.matched_group 1 w) in
              (* 69 also reports "never mutated"; only unread fields go *)
              let unread = match r with m :: _ -> contains (w ^ m) "never read" | [] -> false in
              if n = 69 && not (unread || contains w "is never used") then 690 else n
          | w :: _ when String.length w >= 5 && String.sub w 0 5 = "Error" -> 0
          | w :: r when not (Str.string_match header w 0) -> kind r
          | _ -> 0 in
        go ((file, line, col, kind rest) :: acc) rest
    | _ :: rest -> go acc rest
    | [] -> List.rev acc in
  go [] (String.split_on_char '\n' log)

let handled = [26; 27; 32; 33; 34; 60; 69]

let drop_unused log =
  let by_file = Hashtbl.create 64 in
  List.iter (fun (f, l, c, w) -> if List.mem w handled then
    Hashtbl.replace by_file f ((l, c, w) :: Option.value (Hashtbl.find_opt by_file f) ~default:[]))
    (diagnostics log);
  let total = ref 0 in
  Hashtbl.iter (fun file warned ->
    if Sys.file_exists file && Filename.check_suffix file ".ml" then begin
      let src, str = parse_with Parse.implementation file in
      let pos (loc : Location.t) = loc.loc_start.pos_lnum, loc.loc_start.pos_cnum - loc.loc_start.pos_bol in
      let hit kinds loc = List.exists (fun (l, c, w) -> (l, c) = pos loc && List.mem w kinds) warned in
      let at = hit [32; 33; 34; 60; 69] in
      let params_hit = hit [27] in
      let locals_hit (p : Parsetree.pattern) = match p.ppat_desc with
        | Ppat_var v -> hit [26] v.loc | _ -> false in
      let rec pat_hit (p : Parsetree.pattern) = match p.ppat_desc with
        | Ppat_var v -> at v.loc
        | Ppat_constraint (p, _) -> pat_hit p
        | _ -> false in
      let ranges = ref [] in
      let add loc attrs = ranges := range src loc attrs :: !ranges in
      let rec go items = List.iter (fun (item : Parsetree.structure_item) ->
        match item.pstr_desc with
        | Pstr_value (_, [vb]) when pat_hit vb.pvb_pat -> add item.pstr_loc vb.pvb_attributes
        | Pstr_value (_, vbs) when List.exists (fun vb -> pat_hit vb.Parsetree.pvb_pat) vbs ->
            Printf.eprintf "drop-unused: %s:%d: multi-binding let left alone\n" file
              item.pstr_loc.loc_start.pos_lnum
        | Pstr_primitive vd when at vd.pval_name.loc -> add item.pstr_loc vd.pval_attributes
        | Pstr_open _ when at item.pstr_loc -> add item.pstr_loc []
        | Pstr_type (_, [td]) when at td.ptype_name.loc -> add item.pstr_loc td.ptype_attributes
        | Pstr_module mb when at mb.pmb_name.loc || at item.pstr_loc ->
            add item.pstr_loc mb.pmb_attributes
        | Pstr_module { pmb_expr = me; _ } -> modexpr me
        | _ -> ()) items
      and modexpr (me : Parsetree.module_expr) = match me.pmod_desc with
        | Pmod_structure s -> go s
        | Pmod_constraint (me, _) -> modexpr me
        | _ -> () in
      go str;
      (* Unread record fields: drop the declaration and every [field = e] in
         record literals of this file, with one adjacent semicolon. *)
      let field_range s e =
        let n = String.length src in
        let rec fwd i = if i < n && (src.[i] = ' ' || src.[i] = '\n' || src.[i] = '\t') then fwd (i+1) else i in
        let rec back i = if i > 0 && (src.[i-1] = ' ' || src.[i-1] = '\n' || src.[i-1] = '\t') then back (i-1) else i in
        let f = fwd e in
        if e > 0 && src.[e-1] = ';' then s, e
        else if f < n && src.[f] = ';' then s, f + 1
        else let b = back s in if b > 0 && src.[b-1] = ';' then b - 1, e else s, e in
      let decls = ref [] and dead = ref [] in
      let it = { Ast_iterator.default_iterator with
        label_declaration = (fun self (ld : Parsetree.label_declaration) ->
          decls := ld.pld_name.txt :: !decls;
          if at ld.pld_loc || at ld.pld_name.loc then begin
            dead := ld.pld_name.txt :: !dead;
            ranges := field_range ld.pld_loc.loc_start.pos_cnum ld.pld_loc.loc_end.pos_cnum :: !ranges
          end;
          Ast_iterator.default_iterator.label_declaration self ld) } in
      it.structure it str;
      let unique name = List.length (List.filter (( = ) name) !decls) = 1 in
      List.iter (fun name -> if not (unique name) then
        Printf.eprintf "drop-unused: %s: field %s is declared twice; literals left alone\n" file name) !dead;
      let it = { Ast_iterator.default_iterator with
        expr = (fun self (e : Parsetree.expression) ->
          (match e.pexp_desc with
           | Pexp_record (fields, _) -> List.iter (fun ((lid : Longident.t Location.loc), (v : Parsetree.expression)) ->
               let name = Longident.last lid.txt in
               if List.mem name !dead && unique name then
                 ranges := field_range lid.loc.loc_start.pos_cnum
                   (max lid.loc.loc_end.pos_cnum v.pexp_loc.loc_end.pos_cnum) :: !ranges) fields
           | _ -> ());
          Ast_iterator.default_iterator.expr self e) } in
      if !dead <> [] then it.structure it str;
      (* 26: an unused [let x = e in body] local becomes [body] (ReviewED via
         the printed list; e must not be needed for effect). 27: an unused
         parameter is renamed [_x] / [~x:_]. *)
      let subst = ref [] in
      let it = { Ast_iterator.default_iterator with
        expr = (fun self (e : Parsetree.expression) ->
          (match e.pexp_desc with
           | Pexp_let (_, [vb], body) when locals_hit vb.pvb_pat ->
               Printf.printf "  26 %s:%d: dropped local\n" file e.pexp_loc.loc_start.pos_lnum;
               ranges := (e.pexp_loc.loc_start.pos_cnum, body.pexp_loc.loc_start.pos_cnum) :: !ranges
           | Pexp_function (params, _, _) -> List.iter (fun (p : Parsetree.function_param) ->
               match p.pparam_desc with
               | Pparam_val (label, None, ({ ppat_desc = Ppat_var v; _ } as pat)) when params_hit v.loc ->
                   ignore pat;
                   let s = v.loc.loc_start.pos_cnum and e = v.loc.loc_end.pos_cnum in
                   (* a punned [~x] / [?x] keeps its label: [~x:_] *)
                   let punned sigil = s > 0 && src.[s - 1] = sigil in
                   let s, text = match label with
                     | Labelled l when punned '~' -> s - 1, "~" ^ l ^ ":_"
                     | Optional l when punned '?' -> s - 1, "?" ^ l ^ ":_"
                     | _ -> s, "_" ^ v.txt in
                   Printf.printf "  27 %s:%d: %s\n" file v.loc.loc_start.pos_lnum text;
                   subst := (s, e, text) :: !subst
               | _ -> ()) params
           | _ -> ());
          Ast_iterator.default_iterator.expr self e);
        pat = (fun self (p : Parsetree.pattern) ->
          (match p.ppat_desc with
           | Ppat_var v when hit [26; 27] v.loc
                && not (List.exists (fun (s, _, _) -> s = v.loc.loc_start.pos_cnum
                                                      || s = v.loc.loc_start.pos_cnum - 1) !subst)
                && not (List.exists (fun (s, _) -> s <= v.loc.loc_start.pos_cnum
                                     && v.loc.loc_end.pos_cnum <= s + 0) !ranges) ->
               let s = v.loc.loc_start.pos_cnum in
               if not (s > 0 && (src.[s-1] = '~' || src.[s-1] = '?')) then begin
                 Printf.printf "  27 %s:%d: _%s\n" file v.loc.loc_start.pos_lnum v.txt;
                 subst := (s, v.loc.loc_end.pos_cnum, "_" ^ v.txt) :: !subst
               end
           | _ -> ());
          Ast_iterator.default_iterator.pat self p) } in
      if List.exists (fun (_, _, w) -> w = 26 || w = 27) warned then it.structure it str;
      total := !total + List.length !ranges + List.length !subst;
      if !ranges <> [] || !subst <> [] then remove_ranges ~subst:!subst file src !ranges
    end) by_file;
  !total

(* ---------- prune: iterate to a fixpoint with the compiler as oracle ---------- *)

let build target =
  let log = Filename.temp_file "codemod" ".log" in
  let code = Sys.command (Printf.sprintf "dune build %s > %s 2>&1" target log) in
  let text = read_file log in
  Sys.remove log; code, text

let prune ~excludes ~target dirs =
  let rec loop round =
    let code, log = build target in
    let dropped = drop_unused log in
    if dropped > 0 then (Printf.printf "round %d: %d unused items removed\n%!" round dropped; loop (round + 1))
    else if code <> 0 then begin
      let hard = List.filter (fun (_, _, _, w) -> w = 0 || not (List.mem w handled))
        (diagnostics log) in
      Printf.printf "round %d: build fails with %d unhandled diagnostics; stopping\n" round
        (List.length hard);
      List.iter (fun (f, l, c, w) -> Printf.printf "  %s:%d:%d warning=%d\n" f l c w) hard;
      if hard = [] then print_string log;
      exit 1
    end else begin
      let dead = dead_exports ~excludes dirs in
      if dead = [] then Printf.printf "round %d: fixpoint\n" round
      else begin
        let by_file = Hashtbl.create 16 in
        List.iter (fun (f, n) -> Hashtbl.replace by_file f
          (n :: Option.value (Hashtbl.find_opt by_file f) ~default:[])) dead;
        Hashtbl.iter drop_vals by_file;
        Printf.printf "round %d: %d dead exports dropped\n%!" round (List.length dead);
        loop (round + 1)
      end
    end in
  loop 0

let () =
  let rec split ex target dirs = function
    | "--users-exclude" :: s :: r -> split (s :: ex) target dirs r
    | "--target" :: t :: r -> split ex t dirs r
    | d :: r -> split ex target (d :: dirs) r
    | [] -> ex, target, List.rev dirs in
  match Array.to_list Sys.argv |> List.tl with
  | "dead-exports" :: args ->
      let excludes, _, dirs = split [] "" [] args in
      List.iter (fun (f, n) -> Printf.printf "%s\t%s\n" f n) (dead_exports ~excludes dirs)
  | "prune" :: args ->
      let excludes, target, dirs = split [] "@check" [] args in
      prune ~excludes ~target dirs
  | "drop-vals" :: path :: names -> drop_vals path names
  | [ "drop-unused" ] ->
      Printf.printf "%d removed\n" (drop_unused (In_channel.input_all stdin))
  | _ ->
      prerr_endline "usage: codemod (dead-exports | prune [--users-exclude S] [--target ALIAS]) DIR...\n\
                    \       codemod drop-vals FILE.mli NAME... | drop-unused < log";
      exit 2
