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

let dead_exports ?(modules = false) ~excludes dirs =
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
  (* "Module.name" -> files naming it, however it resolved: recursive modules
     resolve to their signature uid, so their values fall back to names *)
  let qualified : (string, string list) Hashtbl.t = Hashtbl.create 65536 in
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
        (match List.rev (Longident.flatten lid.txt) with
         | name :: m :: _ -> let k = m ^ "." ^ name in
             let prev = Option.value (Hashtbl.find_opt qualified k) ~default:[] in
             if not (List.mem file prev) then Hashtbl.replace qualified k (file :: prev)
         | _ -> ());
        match uids 0 r with
        | [] ->
            (* keyed "Module.name" when qualified, else the bare name *)
            let key = match List.rev (Longident.flatten lid.txt) with
              | name :: m :: _ -> m ^ "." ^ name | name :: [] -> name | [] -> "" in
            Hashtbl.replace unresolved_names key ()
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
    let unit_name = String.capitalize_ascii (Filename.remove_extension (Filename.basename ml)) in
    let cmti = Filename.chop_suffix p ".cmt" ^ ".cmti" in
    if under ml && Filename.check_suffix ml ".ml" && Sys.file_exists cmti then
      match i.cmt_impl_shape, (Cmt_format.read_cmt cmti).cmt_annots with
      | Some shape, Interface sg ->
          let mli = Filename.chop_suffix ml ".ml" ^ ".mli" in
          if Sys.file_exists mli then
          (* returns (values, dead values) under this signature; with
             [modules], a submodule whose values are all dead is reported
             whole as "module:Path" instead of value by value *)
          let rec scan ?(in_rec = false) prefix shape items = List.fold_left (fun (total, dead) -> function
            | Types.Sig_value (id, _, _) ->
                let name = Ident.name id in
                (match find shape name Shape.Sig_component_kind.Value with
                 | Some { uid = Some uid; _ } ->
                     let used = match Hashtbl.find_opt users uid with
                       | Some files -> List.exists (fun f -> f <> ml) files
                       | None -> false in
                     let owner = match List.rev (String.split_on_char '.' prefix) with
                       | "" :: m :: _ -> m | _ -> unit_name in
                     let used = used || (in_rec && match Hashtbl.find_opt qualified (owner ^ "." ^ name) with
                       | Some files -> List.exists (fun f -> f <> ml) files | None -> false) in
                     if not used && not (Hashtbl.mem unresolved_names name)
                        && not (Hashtbl.mem unresolved_names (owner ^ "." ^ name)) then begin
                       results := (mli, prefix ^ name) :: !results;
                       total + 1, dead + 1
                     end else total + 1, dead
                 | _ -> total + 1, dead)
            | Sig_module (id, _, { md_type = Mty_signature items; _ }, rec_status, _) ->
                (match find shape (Ident.name id) Shape.Sig_component_kind.Module with
                 | Some sub ->
                     let path = prefix ^ Ident.name id in
                     let before = !results in
                     let in_rec = in_rec || rec_status <> Types.Trec_not in
                     let t, d = scan ~in_rec (path ^ ".") sub items in
                     if modules && t > 0 && t = d then
                       results := (mli, "module:" ^ path) :: before;
                     total + t, dead + d
                 | None -> total, dead)
            | _ -> total, dead) (0, 0) items in
          ignore (scan "" shape sg.sig_type)
      | _ -> ()
    else if under ml && Filename.check_suffix ml ".ml" && Sys.file_exists ml && not (excluded ml) then
      (* no .mli: every top-level value is an export, reported against the .ml *)
      match i.cmt_impl_shape with
      | Some shape -> (match (head shape).desc with
          | Struct map -> Shape.Item.Map.iter (fun item (s : Shape.t) ->
              if Shape.Item.kind item = Shape.Sig_component_kind.Value then
                match s.uid with
                | Some uid ->
                    let name = Shape.Item.name item in
                    (* without an interface, a use in the same file counts *)
                    let used = Hashtbl.mem users uid in
                    if not used && not (Hashtbl.mem unresolved_names name)
                       && not (Hashtbl.mem unresolved_names (unit_name ^ "." ^ name)) then
                      results := (ml, name) :: !results
                | None -> ()) map
          | _ -> ())
      | None -> ()) infos;
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
    if s < pos then max pos e
    else (Buffer.add_string b (String.sub src pos (s - pos)); Buffer.add_string b text; e)) 0 edits in
  Buffer.add_string b (String.sub src pos (String.length src - pos));
  (* collapse runs of blank lines left behind *)
  let out = Buffer.contents b in
  let out = Str.global_replace (Str.regexp "[ \t]+$") "" out in
  let re = Str.regexp "\n\n\n+" in
  let out = Str.global_replace (Str.regexp "\n\n+\\'") "\n" out in
  write_file path (Str.global_replace re "\n\n" out)

let drop_vals path names =
  let src, sg = parse_with Parse.interface path in
  let ranges = ref [] and found = ref [] in
  (* a module whose types a type declaration elsewhere still names stays *)
  let type_refs = Hashtbl.create 16 in
  let it = { Ast_iterator.default_iterator with
    type_declaration = (fun self td ->
      let inner = { Ast_iterator.default_iterator with
        typ = (fun self' (t : Parsetree.core_type) ->
          (match t.ptyp_desc with
           | Ptyp_constr ({ txt; _ }, _) ->
               (match Longident.flatten txt with
                | m :: _ :: _ -> Hashtbl.replace type_refs m () | _ -> ())
           | _ -> ());
          Ast_iterator.default_iterator.typ self' t) } in
      inner.type_declaration inner td;
      Ast_iterator.default_iterator.type_declaration self td) } in
  it.signature it sg;
  let kept = ref [] in
  let names = List.filter (fun n ->
    let keep = String.length n > 7 && String.sub n 0 7 = "module:"
      && Hashtbl.mem type_refs (List.hd (List.rev (String.split_on_char '.' (String.sub n 7 (String.length n - 7))))) in
    if keep then begin
      Printf.eprintf "drop-vals: %s: %s kept for its types; its values go\n" path n;
      kept := (String.sub n 7 (String.length n - 7) ^ ".") :: !kept
    end;
    not keep) names in
  let in_kept prefix = List.exists (fun k -> String.starts_with ~prefix:k prefix) !kept in
  (* a val whose type names a dropped module goes with it *)
  let dead_mods = List.filter_map (fun n ->
    if String.length n > 7 && String.sub n 0 7 = "module:" then
      Some (List.rev (String.split_on_char '.' (String.sub n 7 (String.length n - 7)))
            |> List.hd) else None) names in
  let mentions_dead (vd : Parsetree.value_description) =
    let hit = ref false in
    let it = { Ast_iterator.default_iterator with
      typ = (fun self (t : Parsetree.core_type) ->
        (match t.ptyp_desc with
         | Ptyp_constr ({ txt; _ }, _) ->
             (match Longident.flatten txt with
              | m :: _ :: _ when List.mem m dead_mods -> hit := true
              | _ -> ())
         | _ -> ());
        Ast_iterator.default_iterator.typ self t) } in
    it.value_description it vd; !hit in
  let dead_module prefix m = let n = "module:" ^ prefix ^ m in
    if List.mem n names then (found := n :: !found; true) else false in
  let and_before p = let rec go i = if i >= 3 && String.sub src (i - 3) 3 = "and" then i - 3 else go (i - 1) in go p in
  let rec go prefix items = List.iter (fun (item : Parsetree.signature_item) ->
    match item.psig_desc with
    | Psig_value vd when in_kept prefix ->
        found := (prefix ^ vd.pval_name.txt) :: !found;
        ranges := range src item.psig_loc vd.pval_attributes :: !ranges
    | Psig_value vd when dead_mods <> [] && mentions_dead vd ->
        ranges := range src item.psig_loc vd.pval_attributes :: !ranges
    | Psig_value vd when List.mem (prefix ^ vd.pval_name.txt) names ->
        found := (prefix ^ vd.pval_name.txt) :: !found;
        ranges := range src item.psig_loc vd.pval_attributes :: !ranges
    | Psig_module { pmd_name = { txt = Some m; _ }; pmd_attributes; _ } when dead_module prefix m ->
        ranges := range src item.psig_loc pmd_attributes :: !ranges
    | Psig_module { pmd_name = { txt = Some m; _ }; pmd_type = { pmty_desc = Pmty_signature s; _ }; _ } ->
        go (prefix ^ m ^ ".") s
    | Psig_recmodule mds ->
        let name (md : Parsetree.module_declaration) = Option.value md.pmd_name.txt ~default:"_" in
        let dead = List.map (fun md -> dead_module prefix (name md)) mds in
        if List.for_all Fun.id dead then ranges := range src item.psig_loc [] :: !ranges
        else begin
          let starts = List.map (fun (md : Parsetree.module_declaration) -> md.pmd_name.loc.loc_start.pos_cnum) mds in
          List.iteri (fun i (md : Parsetree.module_declaration) ->
            if List.nth dead i then
              (if i = 0 then ranges := (List.nth starts 0, List.nth starts 1) :: !ranges
               else ranges := (and_before (List.nth starts i), md.pmd_loc.loc_end.pos_cnum) :: !ranges)
            else match md.pmd_type.pmty_desc with
              | Pmty_signature s -> go (prefix ^ name md ^ ".") s
              | _ -> ()) mds
        end
    | _ -> ()) items in
  go "" sg;
  List.iter (fun n -> if not (List.mem n !found) then
    Printf.eprintf "drop-vals: %s: %s not found\n" path n) names;
  if !ranges <> [] then remove_ranges path src !ranges

(* Remove top-level [external]s and single [let]s named in [names] from an
   .ml without an interface. *)
let drop_lets path names =
  let src, str = parse_with Parse.implementation path in
  let ranges = ref [] in
  List.iter (fun (item : Parsetree.structure_item) -> match item.pstr_desc with
    | Pstr_primitive vd when List.mem vd.pval_name.txt names ->
        ranges := range src item.pstr_loc vd.pval_attributes :: !ranges
    | Pstr_value (_, [ { pvb_pat = { ppat_desc = Ppat_var v; _ }; pvb_attributes; _ } ])
      when List.mem v.txt names -> ranges := range src item.pstr_loc pvb_attributes :: !ranges
    | _ -> ()) str;
  if !ranges <> [] then remove_ranges path src !ranges

(* ---------- dead-stubs: C stubs no [external] names ---------- *)

(* Every [extern "C" ... caml_*(...) { ... }] definition and one-line
   PREFIX_MACRO(caml_*, ...) instance in [mm] whose name no OCaml external in
   [roots] (or generated _build .ml) mentions, and no other kept stub calls. *)
let dead_stubs ~roots mm =
  let src = read_file mm in
  let named = Hashtbl.create 1024 in
  let re = Str.regexp "\"\\(caml_[A-Za-z0-9_]+\\)\"" in
  let scan file = let s = read_file file in
    let rec go i = match Str.search_forward re s i with
      | j -> Hashtbl.replace named (Str.matched_group 1 s) (); go (j + 1)
      | exception Not_found -> () in go 0 in
  List.iter (fun root -> walk root (fun p ->
    if Filename.check_suffix p ".ml" || Filename.check_suffix p ".mli" then scan p)) roots;
  (* definitions: find "caml_name(" at a definition head, then its body braces *)
  let def = Str.regexp "^\\(extern \"C\" \\)?\\(CAMLprim \\)?value[ \n]*\\(caml_[A-Za-z0-9_]+\\)[ \n]*(" in
  let n = String.length src in
  let defs = ref [] in
  let rec find i = match Str.search_forward def src i with
    | start ->
        let name = Str.matched_group 3 src in
        (match String.index_from_opt src (Str.match_end ()) '{' with
         | Some open_ ->
             let rec close k depth = if k >= n then n
               else match src.[k] with
                 | '{' -> close (k + 1) (depth + 1)
                 | '}' -> if depth = 1 then k + 1 else close (k + 1) (depth - 1)
                 | _ -> close (k + 1) depth in
             let stop = close open_ 0 in
             defs := (name, start, stop) :: !defs; find stop
         | None -> ())
    | exception Not_found -> () in
  find 0;
  let macro = Str.regexp "^PRISMEL_[A-Z0-9_]+(\\(caml_[A-Za-z0-9_]+\\)" in
  let rec findm i = match Str.search_forward macro src i with
    | start ->
        let name = Str.matched_group 1 src in
        (* balanced parens: macro calls may span lines *)
        let rec close k depth = if k >= n then n else match src.[k] with
          | '(' -> close (k + 1) (depth + 1)
          | ')' -> if depth = 1 then k + 1 else close (k + 1) (depth - 1)
          | _ -> close (k + 1) depth in
        let stop = close (String.index_from src start '(') 0 in
        let stop = if stop < n && src.[stop] = '\n' then stop + 1 else stop in
        defs := (name, start, stop) :: !defs; findm stop
    | exception Not_found -> () in
  findm 0;
  (* a stub also counts as used when a kept stub body calls it *)
  let live = Hashtbl.copy named in
  let calls body name = let needle = name ^ "(" in
    let rec go i = i + String.length needle <= String.length body
      && (String.sub body i (String.length needle) = needle || go (i + 1)) in go 0 in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter (fun (name, s, e) -> if Hashtbl.mem live name then
      List.iter (fun (other, _, _) -> if not (Hashtbl.mem live other)
        && calls (String.sub src s (e - s)) other then (Hashtbl.replace live other (); changed := true)) !defs) !defs
  done;
  let dead = List.filter (fun (name, _, _) -> not (Hashtbl.mem live name)) !defs in
  List.iter (fun (name, _, _) -> Printf.printf "%s\n" name) dead;
  remove_ranges mm src (List.map (fun (_, s, e) -> s, e) dead)

(* ---------- drop-unused (warnings 32 value, 33 open, 34 type, 60 module) ---------- *)

let header = Str.regexp
  "File \"\\([^\"]+\\)\", lines? \\([0-9]+\\)[-0-9]*, characters \\([0-9]+\\)-[0-9]+:"
let warning = Str.regexp ".*[Ww]arning \\([0-9]+\\) "

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
              if n = 69 && not (unread || contains w "is never used" || contains w "unused record field") then 690 else n
          | w :: _ when String.length w >= 5 && String.sub w 0 5 = "Error" -> 0
          | w :: r when not (Str.string_match header w 0) -> kind r
          | _ -> 0 in
        go ((file, line, col, kind rest) :: acc) rest
    | _ :: rest -> go acc rest
    | [] -> List.rev acc in
  go [] (String.split_on_char '\n' log)

(* The typed tree of [file] from its .cmt under _build/default. *)
let cmt_for file =
  let found = ref None in
  let dir = Filename.concat "_build/default" (Filename.dirname file) in
  if Sys.file_exists dir then
    walk dir (fun p ->
      if !found = None && Filename.check_suffix p ".cmt" then
        match Cmt_format.read_cmt p with
        | { cmt_sourcefile = Some f; cmt_annots = Implementation s; _ } when f = file -> found := Some s
        | _ | exception _ -> ());
  !found

let handled = [26; 27; 32; 33; 34; 37; 60; 69; 690]

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
            if List.for_all (fun vb -> pat_hit vb.Parsetree.pvb_pat) vbs then add item.pstr_loc []
            else
              (* [let rec a = .. and b = ..]: cut a dead binding together with
                 the [and] that joins it to its neighbour *)
              let starts = List.map (fun (vb : Parsetree.value_binding) -> vb.pvb_pat.ppat_loc.loc_start.pos_cnum) vbs in
              let and_before p = let rec go i = if i >= 3 && String.sub src (i - 3) 3 = "and" then i - 3 else go (i - 1) in go p in
              List.iteri (fun i (vb : Parsetree.value_binding) ->
                if pat_hit vb.pvb_pat then
                  let e = vb.pvb_expr.pexp_loc.loc_end.pos_cnum in
                  if i = 0 then ranges := (List.nth starts 0, List.nth starts 1) :: !ranges
                  else ranges := (and_before (List.nth starts i), e) :: !ranges) vbs
        | Pstr_primitive vd when at vd.pval_name.loc -> add item.pstr_loc vd.pval_attributes
        | Pstr_open _ when at item.pstr_loc -> add item.pstr_loc []
        | Pstr_type (_, [td]) when at td.ptype_name.loc -> add item.pstr_loc td.ptype_attributes
        | Pstr_module mb when at mb.pmb_name.loc || at item.pstr_loc ->
            add item.pstr_loc mb.pmb_attributes
        | Pstr_module { pmb_expr = me; _ } -> modexpr me
        | Pstr_recmodule mbs -> List.iter (fun (mb : Parsetree.module_binding) -> modexpr mb.pmb_expr) mbs
        | Pstr_modtype { pmtd_type = Some mt; _ } -> modtype mt
        | _ -> ()) items
      and modexpr (me : Parsetree.module_expr) = match me.pmod_desc with
        | Pmod_structure s -> go s
        | Pmod_constraint (me, mt) -> modexpr me; modtype mt
        | _ -> ()
      (* [val]s of local signatures, e.g. [module M : sig val x : t end = ...] *)
      and modtype (mt : Parsetree.module_type) = match mt.pmty_desc with
        | Pmty_signature items -> List.iter (fun (item : Parsetree.signature_item) ->
            match item.psig_desc with
            | Psig_value vd when at item.psig_loc || at vd.pval_name.loc ->
                add item.psig_loc vd.pval_attributes
            | Psig_module { pmd_type; _ } -> modtype pmd_type
            | _ -> ()) items
        | _ -> () in
      go str;
      (* Unread record fields: drop the declaration, and use the typed tree
         (.cmt) to find exactly the literals [f = e] and assignments [r.f <- e]
         that target that declaration. 690: a mutable field that is never
         mutated loses its [mutable]. *)
      let field_range s e =
        let n = String.length src in
        let rec fwd i = if i < n && (src.[i] = ' ' || src.[i] = '\n' || src.[i] = '\t') then fwd (i+1) else i in
        let rec back i = if i > 0 && (src.[i-1] = ' ' || src.[i-1] = '\n' || src.[i-1] = '\t') then back (i-1) else i in
        let f = fwd e in
        if e > 0 && src.[e-1] = ';' then s, e
        else if f < n && src.[f] = ';' then s, f + 1
        else let b = back s in if b > 0 && src.[b-1] = ';' then b - 1, e else s, e in
      let subst = ref [] in
      let dead_decls = ref [] in
      (* a record whose every field is dead is a dead type: rather than empty
         it, silence 69 on it so the loop goes on, and leave it for a person
         (grep [@@warning "-69"]) *)
      let labels ?(td : Parsetree.type_declaration option) (lds : Parsetree.label_declaration list) =
        let dead = List.filter (fun (ld : Parsetree.label_declaration) ->
          hit [69] ld.pld_loc || hit [69] ld.pld_name.loc) lds in
        if dead <> [] && List.length dead = List.length lds then begin
          Printf.eprintf "drop-unused: %s:%d: every field dead; record marked\n" file
            (List.hd lds).pld_loc.loc_start.pos_lnum;
          Option.iter (fun (td : Parsetree.type_declaration) -> let e = td.ptype_loc.loc_end.pos_cnum in
            subst := (e, e, " [@@warning \"-69\"]") :: !subst) td
        end
        else List.iter (fun (ld : Parsetree.label_declaration) ->
          let s = ld.pld_loc.loc_start.pos_cnum in
          if List.memq ld dead then begin
            dead_decls := s :: !dead_decls;
            ranges := field_range s ld.pld_loc.loc_end.pos_cnum :: !ranges
          end else if hit [690] ld.pld_loc && String.length src > s + 8 && String.sub src s 8 = "mutable " then
            subst := (s, s + 8, "") :: !subst) lds in
      let it = { Ast_iterator.default_iterator with
        type_declaration = (fun self (td : Parsetree.type_declaration) ->
          (match td.ptype_kind with
           | Ptype_record lds -> labels ~td lds
           | Ptype_variant cds -> List.iter (fun (cd : Parsetree.constructor_declaration) ->
               match cd.pcd_args with Pcstr_record lds -> labels lds | _ -> ()) cds
           | _ -> ());
          Ast_iterator.default_iterator.type_declaration self td) } in
      it.structure it str;
      if !dead_decls <> [] then (match cmt_for file with
        | None -> Printf.eprintf "drop-unused: %s: no .cmt; field uses left alone\n" file
        | Some tree ->
            let dead (l : Types.label_description) = List.mem l.lbl_loc.loc_start.pos_cnum !dead_decls
              && l.lbl_loc.loc_start.pos_fname = file in
            let it = { Tast_iterator.default_iterator with
              expr = (fun self (e : Typedtree.expression) ->
                (match e.exp_desc with
                 | Texp_record { fields; _ } -> Array.iter (function
                     | (l, Typedtree.Overridden (lid, v)) when dead l ->
                         ranges := field_range lid.loc.loc_start.pos_cnum
                           (max lid.loc.loc_end.pos_cnum v.exp_loc.loc_end.pos_cnum) :: !ranges
                     | _ -> ()) fields
                 | Texp_setfield (_, _, l, _) when dead l ->
                     subst := (e.exp_loc.loc_start.pos_cnum, e.exp_loc.loc_end.pos_cnum, "()") :: !subst
                 | _ -> ());
                Tast_iterator.default_iterator.expr self e) } in
            it.structure it tree);
      (* 37: a constructor that is never built disappears with the match arms
         (or or-pattern alternatives) that only it reaches. *)
      let bar_range s e =
        let n = String.length src in
        let rec fwd i = if i < n && (src.[i] = ' ' || src.[i] = '\n' || src.[i] = '\t') then fwd (i+1) else i in
        let rec back i = if i > 0 && (src.[i-1] = ' ' || src.[i-1] = '\n' || src.[i-1] = '\t') then back (i-1) else i in
        let b = back s and f = fwd e in
        if src.[s] = '|' then s, e
        else if b > 0 && src.[b-1] = '|' then b - 1, e
        else if f < n && src.[f] = '|' then s, f + 1 else s, e in
      let all_ctors = ref [] and dead_ctors = ref [] in
      let it = { Ast_iterator.default_iterator with
        type_declaration = (fun self (td : Parsetree.type_declaration) ->
          (match td.ptype_kind with
           | Ptype_variant cds ->
               List.iter (fun (cd : Parsetree.constructor_declaration) -> all_ctors := cd.pcd_name.txt :: !all_ctors) cds;
               let dead = List.filter (fun (cd : Parsetree.constructor_declaration) ->
                 hit [37] cd.pcd_loc || hit [37] cd.pcd_name.loc) cds in
               (* a variant with every constructor dead is a dead type; left for a person *)
               if dead <> [] && List.length dead = List.length cds then begin
                 Printf.eprintf "drop-unused: %s:%d: every constructor dead; variant marked\n" file
                   td.ptype_loc.loc_start.pos_lnum;
                 let e = td.ptype_loc.loc_end.pos_cnum in
                 subst := (e, e, " [@@warning \"-37\"]") :: !subst
               end
               else dead_ctors := dead @ !dead_ctors
           | _ -> ());
          Ast_iterator.default_iterator.type_declaration self td) } in
      it.structure it str;
      let dead_names = List.filter_map (fun (cd : Parsetree.constructor_declaration) ->
        if List.length (List.filter (( = ) cd.pcd_name.txt) !all_ctors) = 1 then begin
          ranges := bar_range cd.pcd_loc.loc_start.pos_cnum cd.pcd_loc.loc_end.pos_cnum :: !ranges;
          Some cd.pcd_name.txt
        end else None) !dead_ctors in
      (* a pattern that needs a dead constructor anywhere can never match *)
      let rec only_dead (p : Parsetree.pattern) = match p.ppat_desc with
        | Ppat_construct (lid, arg) -> List.mem (Longident.last lid.txt) dead_names
            || (match arg with Some (_, a) -> only_dead a | None -> false)
        | Ppat_tuple ps -> List.exists only_dead ps
        | Ppat_record (fs, _) -> List.exists (fun (_, p) -> only_dead p) fs
        | Ppat_or (a, b) -> only_dead a && only_dead b
        | Ppat_alias (p, _) | Ppat_constraint (p, _) -> only_dead p
        | _ -> false in
      let rec or_alts (p : Parsetree.pattern) = match p.ppat_desc with
        | Ppat_or (a, b) -> or_alts a @ or_alts b
        | _ -> [p] in
      let cases (cs : Parsetree.case list) = List.iter (fun (c : Parsetree.case) ->
        if only_dead c.pc_lhs then
          ranges := bar_range c.pc_lhs.ppat_loc.loc_start.pos_cnum c.pc_rhs.pexp_loc.loc_end.pos_cnum :: !ranges
        else begin
          (* dead alternatives of or-patterns at any depth *)
          let pit = { Ast_iterator.default_iterator with
            pat = (fun self (p : Parsetree.pattern) ->
              (match p.ppat_desc with
               | Ppat_or _ -> List.iter (fun (a : Parsetree.pattern) -> if only_dead a then
                   ranges := bar_range a.ppat_loc.loc_start.pos_cnum a.ppat_loc.loc_end.pos_cnum :: !ranges)
                   (or_alts p)
               | _ -> ());
              Ast_iterator.default_iterator.pat self p) } in
          pit.pat pit c.pc_lhs
        end) cs in
      let it = { Ast_iterator.default_iterator with
        expr = (fun self (e : Parsetree.expression) ->
          (match e.pexp_desc with
           | Pexp_match (_, cs) | Pexp_try (_, cs) -> cases cs
           | Pexp_function (_, _, Pfunction_cases (cs, _, _)) -> cases cs
           | _ -> ());
          Ast_iterator.default_iterator.expr self e) } in
      if dead_names <> [] then it.structure it str;
      (* 26: an unused [let x = e in body] local becomes [body] (ReviewED via
         the printed list; e must not be needed for effect). 27: an unused
         parameter is renamed [_x] / [~x:_]. *)
      let it = { Ast_iterator.default_iterator with
        expr = (fun self (e : Parsetree.expression) ->
          (match e.pexp_desc with
           | Pexp_let (_, [vb], body) when locals_hit vb.pvb_pat ->
               Printf.printf "  26 %s:%d: dropped local\n" file e.pexp_loc.loc_start.pos_lnum;
               ranges := (e.pexp_loc.loc_start.pos_cnum, body.pexp_loc.loc_start.pos_cnum) :: !ranges
           | Pexp_function (params, _, _) -> List.iter (fun (p : Parsetree.function_param) ->
               match p.pparam_desc with
               | Pparam_val (label, _, ({ ppat_desc = (Ppat_var v | Ppat_constraint ({ ppat_desc = Ppat_var v; _ }, _)); _ })) when params_hit v.loc ->
                   let s = v.loc.loc_start.pos_cnum and e = v.loc.loc_end.pos_cnum in
                   (* a label named like its variable ([~x], [?x], [?(x = d)], [~(x : t)])
                      keeps the label: the whole parameter becomes [~x:_] / [?x:_] *)
                   let whole = p.pparam_loc.loc_start.pos_cnum, p.pparam_loc.loc_end.pos_cnum in
                   let (s, e), text = match label with
                     | Labelled l when l = v.txt -> whole, "~" ^ l ^ ":_"
                     | Optional l when l = v.txt -> whole, "?" ^ l ^ ":_"
                     | _ -> (s, e), "_" ^ v.txt in
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
               if not (s > 0 && (src.[s-1] = '~' || src.[s-1] = '?' || (s > 1 && src.[s-1] = '(' && (src.[s-2] = '~' || src.[s-2] = '?')))) then begin
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

(* ---------- cut-tests: a test that stops compiling goes ---------- *)

let is_test file =
  let base = Filename.basename file in
  (String.length base > 5 && String.sub base 0 5 = "test_")
  || (String.length file > 5 && String.sub file 0 5 = "test/")

(* Remove the top-level item holding each hard error in a test file; inside
   an entry point ([run], [main], [tests], [let () =]) cut only the innermost
   sequence statement, or empty the body to [()]. Returns edits made. *)
let cut_tests log =
  let errors = List.filter (fun (f, _, _, w) -> w = 0 && is_test f && Sys.file_exists f
    && Filename.check_suffix f ".ml") (diagnostics log) in
  let by_file = Hashtbl.create 16 in
  List.iter (fun (f, l, c, _) -> Hashtbl.replace by_file f
    ((l, c) :: Option.value (Hashtbl.find_opt by_file f) ~default:[])) errors;
  let total = ref 0 in
  Hashtbl.iter (fun file points ->
    let src, str = parse_with Parse.implementation file in
    let offset (l, c) =
      (* byte offset of line l, column c *)
      let rec go i line = if line = l then i + c
        else match String.index_from_opt src i '\n' with
          | Some j -> go (j + 1) (line + 1) | None -> i in go 0 1 in
    let ranges = ref [] and subst = ref [] in
    List.iter (fun point ->
      let p = offset point in
      let inside (loc : Location.t) = loc.loc_start.pos_cnum <= p && p < loc.loc_end.pos_cnum in
      match List.find_opt (fun (i : Parsetree.structure_item) -> inside i.pstr_loc) str with
      | None -> ()
      | Some item ->
          let entry = match item.pstr_desc with
            | Pstr_value (_, vbs) -> List.exists (fun (vb : Parsetree.value_binding) ->
                match vb.pvb_pat.ppat_desc with
                | Ppat_var { txt = "run" | "main" | "tests"; _ } -> true
                | Ppat_construct ({ txt = Lident "()"; _ }, None) -> true
                | _ -> false) vbs
            | Pstr_eval _ -> true
            | _ -> false in
          if not entry then ranges := range src item.pstr_loc [] :: !ranges
          else begin
            let best = ref None in
            let it = { Ast_iterator.default_iterator with
              expr = (fun self (e : Parsetree.expression) ->
                (match e.pexp_desc with
                 | Pexp_sequence (a, b) when inside a.pexp_loc ->
                     best := Some (a.pexp_loc.loc_start.pos_cnum, b.pexp_loc.loc_start.pos_cnum)
                 | Pexp_sequence (a, b) when inside b.pexp_loc
                                              && (match b.pexp_desc with Pexp_sequence _ -> false | _ -> true) ->
                     best := Some (a.pexp_loc.loc_end.pos_cnum, b.pexp_loc.loc_end.pos_cnum)
                 | _ -> ());
                Ast_iterator.default_iterator.expr self e) } in
            it.structure_item it item;
            match !best with
            | Some r -> ranges := r :: !ranges
            | None -> (match item.pstr_desc with
                | Pstr_value (_, vbs) -> List.iter (fun (vb : Parsetree.value_binding) ->
                    let rec body (e : Parsetree.expression) = match e.pexp_desc with
                      | Pexp_function (_, _, Pfunction_body b) -> body b
                      | _ -> e in
                    let b = body vb.pvb_expr in
                    if inside b.pexp_loc then
                      subst := (b.pexp_loc.loc_start.pos_cnum, b.pexp_loc.loc_end.pos_cnum, "()") :: !subst) vbs
                | _ -> ranges := range src item.pstr_loc [] :: !ranges)
          end) points;
    Printf.printf "  cut %s: %d\n" file (List.length !ranges + List.length !subst);
    total := !total + List.length !ranges + List.length !subst;
    remove_ranges ~subst:!subst file src !ranges) by_file;
  !total

(* The Metal generator refuses registry entries metal.ml no longer calls:
   "registry <kind> NAME is not used by metal.ml". Drop those entries. *)
let registry = "lib/metal/gen/registry.ml"
let drop_registry_entries log =
  let re = Str.regexp "registry [a-z]+ \\([A-Za-z_0-9]+\\) is not used" in
  let names = List.filter_map (fun l ->
    if Str.string_match re l 0 then Some (Str.matched_group 1 l) else None)
    (String.split_on_char '\n' log) in
  if names = [] || not (Sys.file_exists registry) then 0 else begin
    let src, str = parse_with Parse.implementation registry in
    let ranges = ref [] in
    let it = { Ast_iterator.default_iterator with
      expr = (fun self (e : Parsetree.expression) ->
        (match e.pexp_desc with
         | Pexp_construct ({ txt = Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [ elt; _ ]; _ }) ->
             (match elt.pexp_desc with
              | Pexp_construct (_, Some { pexp_desc = Pexp_record (fields, _); _ })
                when List.exists (fun ((lid : Longident.t Location.loc), (v : Parsetree.expression)) ->
                       Longident.last lid.txt = "ocaml"
                       && (match v.pexp_desc with
                           | Pexp_constant { pconst_desc = Pconst_string (s, _, _); _ } -> List.mem s names
                           | _ -> false)) fields ->
                  let s = elt.pexp_loc.loc_start.pos_cnum and e = elt.pexp_loc.loc_end.pos_cnum in
                  (* take the separating ';' before, or the one after for the head *)
                  let rec back i = if i > 0 && (src.[i-1] = ' ' || src.[i-1] = '\n') then back (i-1) else i in
                  let b = back s in
                  if b > 0 && src.[b-1] = ';' then ranges := (b - 1, e) :: !ranges
                  else begin
                    let rec fwd i = if i < String.length src && (src.[i] = ' ' || src.[i] = '\n') then fwd (i+1) else i in
                    let f = fwd e in
                    ranges := (s, if f < String.length src && src.[f] = ';' then f + 1 else e) :: !ranges
                  end
              | _ -> ())
         | _ -> ());
        Ast_iterator.default_iterator.expr self e) } in
    it.structure it str;
    Printf.printf "  registry: dropped %s\n" (String.concat ", " names);
    remove_ranges registry src !ranges;
    List.length !ranges
  end

(* ---------- prune: iterate to a fixpoint with the compiler as oracle ---------- *)

let build target =
  let log = Filename.temp_file "codemod" ".log" in
  let code = Sys.command (Printf.sprintf "dune build --profile codemod %s > %s 2>&1" target log) in
  let text = read_file log in
  Sys.remove log; code, text

let prune ?(cut = false) ~modules ~excludes ~target dirs =
  let last = ref [] in
  let rec loop round =
    let code, log = build target in
    let dropped = drop_unused log in
    let dropped = if dropped = 0 && code <> 0 then drop_registry_entries log else dropped in
    let dropped = if dropped = 0 && code <> 0 && cut then cut_tests log else dropped in
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
      let dead = dead_exports ~modules ~excludes dirs in
      if dead = [] then Printf.printf "round %d: fixpoint\n" round
      else if dead = !last then (Printf.printf "round %d: no progress on %d exports; stopping\n" round (List.length dead); exit 1)
      else begin
        let by_file = Hashtbl.create 16 in
        List.iter (fun (f, n) -> Hashtbl.replace by_file f
          (n :: Option.value (Hashtbl.find_opt by_file f) ~default:[])) dead;
        last := dead;
        List.iter (fun (f, n) -> Printf.printf "  drop %s %s\n" f n) dead;
        Hashtbl.iter (fun f names -> if Sys.file_exists f then
          (if Filename.check_suffix f ".ml" then drop_lets f names else drop_vals f names)) by_file;
        Printf.printf "round %d: %d dead exports dropped\n%!" round (List.length dead);
        loop (round + 1)
      end
    end in
  loop 0

let () =
  let modules = ref false and cut = ref false in
  let rec split ex target dirs = function
    | "--modules" :: r -> modules := true; split ex target dirs r
    | "--cut-tests" :: r -> cut := true; split ex target dirs r
    | "--users-exclude" :: s :: r -> split (s :: ex) target dirs r
    | "--target" :: t :: r -> split ex t dirs r
    | d :: r -> split ex target (d :: dirs) r
    | [] -> ex, target, List.rev dirs in
  match Array.to_list Sys.argv |> List.tl with
  | "dead-exports" :: args ->
      let excludes, _, dirs = split [] "" [] args in
      List.iter (fun (f, n) -> Printf.printf "%s\t%s\n" f n) (dead_exports ~modules:!modules ~excludes dirs)
  | "prune" :: args ->
      let excludes, target, dirs = split [] "@check" [] args in
      prune ~cut:!cut ~modules:!modules ~excludes ~target dirs
  | "drop-vals" :: path :: names -> drop_vals path names
  | "dead-stubs" :: mm :: roots -> dead_stubs ~roots mm
  | [ "drop-unused" ] ->
      Printf.printf "%d removed\n" (drop_unused (In_channel.input_all stdin))
  | _ ->
      prerr_endline "usage: codemod (dead-exports | prune [--users-exclude S] [--target ALIAS]) DIR...\n\
                    \       codemod drop-vals FILE.mli NAME... | drop-unused < log";
      exit 2
