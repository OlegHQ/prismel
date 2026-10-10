(* Mechanical file split: a file that is a sequence of top-level [module X = struct ... end]
   becomes one file per module (with [--interfaces], and a matching [.mli] of
   [module X : sig ... end] splits too).
   Bodies move byte for byte; the comments between two modules go with the module after them; the
   leading [open]s are copied to every new [.ml] (remove the unused ones by hand: the build
   names them) and the original keeps only [module X = X] re-exports, so no caller changes.
   A module that names a sibling not defined before it is refused: it would capture it. *)
open Parsetree

let parse_with parse path source =
  let lexbuf = Lexing.from_string source in
  Location.init lexbuf path;
  Lexer.init ();
  parse lexbuf

let bounds (loc : Location.t) = loc.loc_start.pos_cnum, loc.loc_end.pos_cnum
let slice source (a, b) = String.sub source a (b - a)

(* A top-level item: a module (name, item bounds, bounds of its body between the keyword
   and [end]) or an [open]. *)
type item = Module of string * (int * int) * (int * int) | Open of int * int

let items ~keyword source parse project =
  let item_of name loc body_loc =
    let a, b = bounds body_loc in
    if not (String.starts_with ~prefix:keyword (slice source (a, b))) then failwith "unexpected module syntax";
    Module (name, bounds loc, (a + String.length keyword, b - 3)) in
  List.filter_map (project item_of) (parse_with parse "split" source)

(* Doc comments are attributes; anything else on a module would be lost in the move. *)
let plain = List.for_all (fun (a : attribute) -> a.attr_name.txt = "ocaml.doc" || a.attr_name.txt = "ocaml.text")

let ml_items source =
  items ~keyword:"struct" source Parse.implementation (fun item_of (it : structure_item) ->
    match it.pstr_desc with
    | Pstr_open _ -> let a, b = bounds it.pstr_loc in Some (Open (a, b))
    | Pstr_attribute attribute when plain [ attribute ] -> None
    | Pstr_module { pmb_name = { txt = Some name; _ };
                    pmb_expr = { pmod_desc = Pmod_structure _; pmod_loc; pmod_attributes = []; _ };
                    pmb_attributes; _ } when plain pmb_attributes -> Some (item_of name it.pstr_loc pmod_loc)
    | _ -> failwith "only top-level modules (and leading opens) can be split")

let mli_items source =
  items ~keyword:"sig" source Parse.interface (fun item_of (it : signature_item) ->
    match it.psig_desc with
    | Psig_open _ -> let a, b = bounds it.psig_loc in Some (Open (a, b))
    | Psig_attribute attribute when plain [ attribute ] -> None
    | Psig_module { pmd_name = { txt = Some name; _ };
                    pmd_type = { pmty_desc = Pmty_signature _; pmty_loc; pmty_attributes = []; _ };
                    pmd_attributes; _ } when plain pmd_attributes -> Some (item_of name it.psig_loc pmty_loc)
    | _ -> failwith "only top-level modules (and leading opens) can be split")

let names list = List.filter_map (function Module (name, _, _) -> Some name | Open _ -> None) list

(* The sibling modules a body names: a path head, [open M], [include M], [module N = M]. *)
let refs siblings text =
  let lexbuf = Lexing.from_string text in
  Lexer.init ();
  let rec read acc = match Lexer.token lexbuf with
    | Parser.EOF -> Array.of_list (List.rev acc)
    | token -> read (token :: acc)
    | exception _ -> Array.of_list (List.rev acc) in
  let tokens = read [] in
  let at i = if i < 0 || i >= Array.length tokens then Parser.EOF else tokens.(i) in
  let found = ref [] in
  Array.iteri (fun i token -> match token with
    | Parser.UIDENT name when List.mem name siblings && at (i - 1) <> Parser.DOT ->
        let named = at (i + 1) = Parser.DOT || at (i - 1) = Parser.OPEN || at (i - 1) = Parser.INCLUDE
          || (at (i - 1) = Parser.EQUAL && at (i - 3) = Parser.MODULE) in
        if named && not (List.mem name !found) then found := name :: !found
    | _ -> ()) tokens;
  !found

(* A body keeps its layout: only the line break after [struct]/[sig] and the blanks before
   [end] go. *)
let body text =
  let start = ref 0 and stop = ref (String.length text) in
  while !start < !stop && text.[!start] = '\n' do incr start done;
  while !stop > !start && (text.[!stop - 1] = ' ' || text.[!stop - 1] = '\n') do decr stop done;
  String.sub text !start (!stop - !start) ^ "\n"

let trim_blank text = let text = String.trim text in if text = "" then "" else text ^ "\n"
let join parts = String.concat "\n" (List.filter (( <> ) "") parts)

(* One file per module and the rewritten original: [(file name, contents)], the original
   first.  [stem] is the original's base name, [mli] its interface when it has one.  Without
   [interfaces] the interface is left alone: it stays the one public signature, and the siblings
   keep seeing every value of the others (a module's own [.mli] would hide what they use). *)
let split ?(interfaces = false) ~stem ~ml ~mli () =
  let mli = if interfaces then mli else None in
  let ml_list = ml_items ml in
  let mli_list = Option.map mli_items mli in
  let order = names ml_list in
  Option.iter (fun list -> List.iter (fun name -> if not (List.mem name order) then
    failwith (Printf.sprintf "%s.mli declares module %s that %s.ml does not define" stem name stem))
    (names list)) mli_list;
  let check what source list =
    let rec go earlier = function
      | [] -> ()
      | Open _ :: rest -> go earlier rest
      | Module (name, _, inner) :: rest ->
          (match List.filter (fun m -> not (List.mem m earlier)) (refs (names list) (slice source inner)) with
           | [] -> ()
           | bad -> failwith (Printf.sprintf "%s: module %s names %s, which is not defined before it" what name
                       (String.concat ", " bad)));
          go (name :: earlier) rest in
    go [] list in
  check (stem ^ ".ml") ml ml_list;
  Option.iter (check (stem ^ ".mli") (Option.value mli ~default:"")) mli_list;
  let opens source list = trim_blank (String.concat "\n" (List.filter_map (function
    | Open (a, b) -> Some (slice source (a, b)) | Module _ -> None) list)) in
  (* the comments between the previous item and this module belong to this module, except
     before the first one, which stay with the original *)
  let gap source list name =
    let rec go previous first = function
      | [] -> ""
      | Open (_, b) :: rest -> go b first rest
      | Module (n, (a, b), _) :: rest ->
          if n = name then (if first then "" else slice source (previous, a)) else go b false rest in
    trim_blank (go 0 true list) in
  let file source list name =
    let inner = List.find_map (function Module (n, _, inner) when n = name -> Some inner | _ -> None) list in
    inner |> Option.map (fun inner -> join [ opens source list; gap source list name; body (slice source inner) ]) in
  (* the original: what stood before the first module, minus its opens, then the re-exports *)
  let original source list ~only_declared =
    let first = List.find_map (function Module (_, (a, _), _) -> Some a | Open _ -> None) list in
    let head = slice source (0, Option.value first ~default:0) in
    let head = List.fold_left (fun head -> function
      | Open (a, b) -> Str.global_substitute (Str.regexp_string (slice source (a, b))) (fun _ -> "") head
      | Module _ -> head) head list in
    let aliases = List.filter_map (fun name ->
      if only_declared && not (List.mem name (names list)) then None
      else Some (Printf.sprintf "module %s = %s" name name)) order in
    trim_blank head ^ String.concat "\n\n" aliases ^ "\n" in
  let created = List.concat_map (fun name ->
    let lower = String.uncapitalize_ascii name in
    (lower ^ ".ml", Option.get (file ml ml_list name))
    :: (match mli, mli_list with
        | Some source, Some list -> Option.to_list (Option.map (fun text -> lower ^ ".mli", text) (file source list name))
        | _ -> [])) order in
  ((stem ^ ".ml", original ml ml_list ~only_declared:false)
   :: (match mli, mli_list with
       | Some source, Some list -> [ stem ^ ".mli", original source list ~only_declared:true ]
       | _ -> []))
  @ created

let run ?interfaces ~dry file =
  let dir = Filename.dirname file and stem = Filename.remove_extension (Filename.basename file) in
  let read path = In_channel.with_open_bin path In_channel.input_all in
  let mli = Filename.concat dir (stem ^ ".mli") in
  let files = split ?interfaces ~stem ~ml:(read file) ~mli:(if Sys.file_exists mli then Some (read mli) else None) () in
  List.iter (fun (name, _) ->
    let path = Filename.concat dir name in
    if name <> stem ^ ".ml" && name <> stem ^ ".mli" && Sys.file_exists path then
      failwith (path ^ " exists; not overwriting")) files;
  List.iter (fun (name, text) ->
    let path = Filename.concat dir name in
    Printf.printf "%s %s: %d lines\n" (if dry then "would write" else "write") path
      (List.length (String.split_on_char '\n' text) - 1);
    if not dry then Out_channel.with_open_bin path (fun channel -> output_string channel text)) files

let self_test () =
  let ml = "open Stdlib\n\n(* A *)\nmodule A = struct\n  let x = 1\nend\n\n(* B uses A *)\nmodule B = struct\n  (* kept *)\n  let y = A.x + 1\nend\n" in
  let mli = "(** Header. *)\n\n(** The first. *)\nmodule A : sig\n  val x : int\nend\n\n(** The second. *)\nmodule B : sig\n  val y : int\nend\n" in
  let files = split ~interfaces:true ~stem:"m" ~ml ~mli:(Some mli) () in
  let get name = List.assoc name files in
  let check label ok = if not ok then (prerr_endline ("split-modules self-test failed: " ^ label); exit 1) in
  check "six files" (List.length files = 6);
  check "original ml" (get "m.ml" = "(* A *)\nmodule A = A\n\nmodule B = B\n");
  check "original mli" (get "m.mli" = "(** Header. *)\n\n(** The first. *)\nmodule A = A\n\nmodule B = B\n");
  check "a.ml" (get "a.ml" = "open Stdlib\n\n  let x = 1\n");
  check "b.ml keeps comments" (get "b.ml" = "open Stdlib\n\n(* B uses A *)\n\n  (* kept *)\n  let y = A.x + 1\n");
  check "b.mli" (get "b.mli" = "(** The second. *)\n\n  val y : int\n");
  let refused source =
    match split ~stem:"m" ~ml:source ~mli:None () with _ -> false | exception Failure _ -> true in
  check "forward reference refused"
    (refused "module A = struct let x = B.y end\nmodule B = struct let y = 1 end\n");
  check "other items refused" (refused "module A = struct end\nlet x = 1\n");
  print_endline "split-modules self-test passed"
