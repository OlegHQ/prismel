(* Merges a catalog node and its hand-written typed SOP into one declaration.

     sop_merge [--dry-run] MODULE...

   For each catalog module [MODULE] (in lib/sop_catalog/{shapes,topology,
   attributes,groups}.ml) whose [build] forwards to [Sop.f]:
   - the module moves to lib/procedural/sop_<file>.ml, its record gaining
     [[@@sop.fn "f"] [@@sop.args ...]] from f's parameter list and, per field,
     [[@sop.nonblank]] / [[@sop.validate]] from f's [invalid_arg] checks and
     [[@sop.arg_default]] where f's default differs from the editor default
     (each such drift is printed);
   - its [build] inlines f's cook: one [let p = <argument> in] per typed
     parameter, then f's body without the checks and with an empty hand key;
   - [Sop.f] becomes an alias of the generated typed function, the module is
     registered in [Procedural.Nodes] and [Sop_catalog] points at it;
   - every [Shared] helper the module names is copied into
     lib/procedural/sop_support.ml once.
   A module whose arguments or checks do not fit these shapes is left alone
   and the reason printed. Run `dune build` afterwards and feed its warnings
   to `codemod drop-unused` for the key helpers that became dead. *)

open Parsetree

let read path = In_channel.with_open_bin path In_channel.input_all
let write path text = Out_channel.with_open_bin path (fun channel -> output_string channel text)
let fail format = Printf.ksprintf (fun message -> prerr_endline ("sop_merge: " ^ message); exit 2) format

let parse_with f path =
  let src = read path in
  let lexbuf = Lexing.from_string src in
  Location.init lexbuf path;
  Lexer.init ();
  src, f lexbuf

let text src (loc : Location.t) =
  String.sub src loc.loc_start.pos_cnum (loc.loc_end.pos_cnum - loc.loc_start.pos_cnum)

(* Byte range of an item widened to whole lines. *)
let line_range src (loc : Location.t) =
  let s = loc.loc_start.pos_cnum and e = loc.loc_end.pos_cnum in
  let rec back i = if i > 0 && src.[i - 1] <> '\n' then back (i - 1) else i in
  let rec fwd i = if i < String.length src && src.[i] <> '\n' then fwd (i + 1) else i in
  back s, min (String.length src) (fwd e + 1)

let apply_edits src edits =
  let edits = List.sort (fun (a, _, _) (b, _, _) -> compare a b) edits in
  let b = Buffer.create (String.length src) in
  let pos = List.fold_left (fun pos (s, e, t) ->
    if s < pos then fail "overlapping edits";
    Buffer.add_string b (String.sub src pos (s - pos)); Buffer.add_string b t; e) 0 edits in
  Buffer.add_string b (String.sub src pos (String.length src - pos));
  let out = Str.global_replace (Str.regexp "\n\n\n+") "\n\n" (Buffer.contents b) in
  Str.global_replace (Str.regexp "[ \t\n]+\\'") "\n" out

exception Skip of string
let skip format = Printf.ksprintf (fun message -> raise (Skip message)) format

let lident = function
  | { pexp_desc = Pexp_ident { txt; _ }; _ } -> Some (Longident.flatten txt)
  | _ -> None
let var = function { pexp_desc = Pexp_ident { txt = Longident.Lident v; _ }; _ } -> Some v | _ -> None
let string_literal = function
  | { pexp_desc = Pexp_constant { pconst_desc = Pconst_string (s, _, _); _ }; _ } -> Some s | _ -> None
let pat_var = function { ppat_desc = Ppat_var { txt; _ }; _ } -> Some txt | _ -> None

(* ---------- the typed function in sop.ml ---------- *)

type typed_param = {
  label : Asttypes.arg_label;
  name : string;
  default : expression option;   (* [?(x = d)] *)
}

let typed_params = function
  | { pexp_desc = Pexp_function (params, _, Pfunction_body body); _ } ->
      List.map (fun (p : function_param) -> match p.pparam_desc with
        | Pparam_val (label, default, pattern) ->
            (match pat_var pattern, pattern.ppat_desc with
             | Some name, _ -> { label; name; default }
             | None, Ppat_construct ({ txt = Lident "()"; _ }, None) -> { label; name = "()"; default }
             | None, _ -> skip "typed function has a non-variable parameter")
        | Pparam_newtype _ -> skip "typed function has a type parameter") params, body
  | { pexp_desc = Pexp_function (_, _, Pfunction_cases _); _ } -> skip "typed function uses [function]"
  | body -> [], body

(* f's body is [checks; let copies in Node.Private.make ...]: split it into
   the check statements and the final expression. *)
let rec statements = function
  | { pexp_desc = Pexp_sequence (first, rest); _ } -> let checks, last = statements rest in first :: checks, last
  | last -> [], last

let rec make_application = function
  | { pexp_desc = Pexp_let (_, _, body); _ } -> make_application body
  | { pexp_desc = Pexp_apply (f, args); _ } as e
    when lident f = Some ["Node"; "Private"; "make"] -> e, args
  | _ -> skip "typed function does not end in Node.Private.make"

(* ---------- checks -> attributes ---------- *)

type check = Nonblank of string * string | Validate of string * string * expression option * expression option
(* Nonblank (parameter, message); Validate (parameter, message, lower, upper) *)
type vec3_check = Vec3_finite of string * string

let strip_prefix fname message =
  let prefix = "Sop." ^ fname ^ ": " in
  if String.starts_with ~prefix message then
    String.sub message (String.length prefix) (String.length message - String.length prefix)
  else skip "check message %S does not start with %S" message prefix

let is_blank_test v = function
  (* String.trim v = "" *)
  | { pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident "="; _ }; _ },
      [Nolabel, { pexp_desc = Pexp_apply (trim, [Nolabel, x]); _ }; Nolabel, empty]); _ }
    when lident trim = Some ["String"; "trim"] && var x = Some v && string_literal empty = Some "" -> true
  | _ -> false

let invalid_arg_message = function
  | { pexp_desc = Pexp_apply (f, [Nolabel, m]); _ } when lident f = Some ["invalid_arg"] -> string_literal m
  | _ -> None

let rec finite_conjuncts = function
  | { pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident "&&"; _ }; _ }, [Nolabel, a; Nolabel, b]); _ } ->
      finite_conjuncts a @ finite_conjuncts b
  | { pexp_desc = Pexp_apply (f, [Nolabel, x]); _ } when lident f = Some ["Float"; "is_finite"] -> [x]
  | _ -> skip "unrecognised finiteness test"

let rec disjuncts = function
  | { pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident "||"; _ }; _ }, [Nolabel, a; Nolabel, b]); _ } ->
      disjuncts a @ disjuncts b
  | e -> [e]

let field_access v = function
  (* v.Vec3.x / v.x *)
  | { pexp_desc = Pexp_field (x, { txt; _ }); _ } when var x = Some v -> Some (Longident.last txt)
  | _ -> None

(* One check statement of f (the parameter names are f's). *)
let classify_check fname (e : expression) : [ `Checks of check list | `Vec3 of vec3_check ] =
  match e.pexp_desc with
  | Pexp_ifthenelse (test, branch, None) ->
      let message = match invalid_arg_message branch with
        | Some m -> strip_prefix fname m | None -> skip "if-check does not raise invalid_arg" in
      (* String.trim x = "" [|| String.trim y = ""] *)
      let blank_var = function
        | { pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident "="; _ }; _ },
            [Nolabel, { pexp_desc = Pexp_apply (trim, [Nolabel, x]); _ }; _]); _ } as t
          when lident trim = Some ["String"; "trim"] ->
            (match var x with Some v when is_blank_test v t -> Some v | _ -> None)
        | _ -> None in
      let blanks = List.map blank_var (disjuncts test) in
      (match blanks with
       | _ when List.for_all Option.is_some blanks ->
           `Checks (List.map (fun v -> Nonblank (Option.get v, message)) blanks)
       | _ ->
           (* not (Float.is_finite x) || x < lo || x > hi, or
              not (Float.is_finite v.x && Float.is_finite v.y && Float.is_finite v.z) *)
           let parts = disjuncts test in
           let finite, bounds = List.partition (function
             | { pexp_desc = Pexp_apply (f, [Nolabel, _]); _ } -> lident f = Some ["not"]
             | _ -> false) parts in
           let finite = List.concat_map (function
             | { pexp_desc = Pexp_apply (_, [Nolabel, inner]); _ } -> finite_conjuncts inner
             | _ -> assert false) finite in
           (match finite, bounds with
            | [a; b; c], [] ->
                let v = match var (match a.pexp_desc with Pexp_field (x, _) -> x | _ -> a) with
                  | Some v -> v | None -> skip "unrecognised vec3 finiteness test" in
                if List.map (field_access v) [a; b; c] <> [Some "x"; Some "y"; Some "z"] then
                  skip "unrecognised vec3 finiteness test";
                `Vec3 (Vec3_finite (v, message))
            | finite, bounds ->
                let v = ref None in
                let name x = match var x with
                  | Some n -> (match !v with None -> v := Some n | Some m when m = n -> () | Some _ ->
                      skip "range check mixes parameters"); n
                  | None -> skip "range check on a non-variable" in
                List.iter (fun x -> ignore (name x)) finite;
                let lower = ref None and upper = ref None in
                List.iter (function
                  | { pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident op; _ }; _ },
                      [Nolabel, x; Nolabel, bound]); _ } when op = "<" || op = ">" ->
                      ignore (name x);
                      if op = "<" then lower := Some bound else upper := Some bound
                  | _ -> skip "unrecognised range check") bounds;
                match !v with
                | None -> skip "empty range check"
                | Some v -> `Checks [Validate (v, message, !lower, !upper)]))
  | Pexp_apply (f, [Nolabel, { pexp_desc = Pexp_function ([{ pparam_desc = Pparam_val (Nolabel, None, p); _ }],
      None, Pfunction_body body); _ }; Nolabel, x])
    when lident f = Some ["Option"; "iter"] ->
      (* Option.iter (fun value -> if String.trim value = "" then invalid_arg m) x *)
      (match pat_var p, var x, body.pexp_desc with
       | Some inner, Some v, Pexp_ifthenelse (test, branch, None) when is_blank_test inner test ->
           (match invalid_arg_message branch with
            | Some m -> `Checks [Nonblank (v, strip_prefix fname m)]
            | None -> skip "Option.iter check does not raise invalid_arg")
       | _ -> skip "unrecognised Option.iter check")
  | Pexp_match (x, [ { pc_lhs = { ppat_desc = Ppat_construct ({ txt = Lident "Some"; _ },
      Some (_, p)); _ }; pc_guard = Some guard; pc_rhs }; _ ]) ->
      (* match x with Some value when String.trim value = "" -> invalid_arg m | None | Some _ -> () *)
      (match var x, pat_var p with
       | Some v, Some inner when is_blank_test inner guard ->
           (match invalid_arg_message pc_rhs with
            | Some m -> `Checks [Nonblank (v, strip_prefix fname m)]
            | None -> skip "match check does not raise invalid_arg")
       | _ -> skip "unrecognised match check")
  | Pexp_apply (f, [Nolabel, { pexp_desc = Pexp_function ([{ pparam_desc = Pparam_val (Nolabel, None, p); _ }],
      None, Pfunction_body body); _ }; Nolabel, ({ pexp_desc = Pexp_tuple _ | Pexp_construct _; _ } as pairs)])
    when lident f = Some ["List"; "iter"] ->
      (* List.iter (fun (field, value) -> match value with
           | Some value when String.trim value = "" -> invalid_arg ("Sop.f: empty " ^ field)
           | None | Some _ -> ()) ["seed attribute name", seed_attribute; ...] *)
      let inner = match p.ppat_desc with
        | Ppat_tuple [_; v] -> (match pat_var v with Some v -> v | None -> skip "unrecognised List.iter check")
        | _ -> skip "unrecognised List.iter check" in
      let prefix = match body.pexp_desc with
        | Pexp_match (x, [ { pc_lhs = { ppat_desc = Ppat_construct ({ txt = Lident "Some"; _ }, Some (_, p)); _ };
                             pc_guard = Some guard; pc_rhs = { pexp_desc = Pexp_apply (raise_, [Nolabel,
                               { pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident "^"; _ }; _ },
                                 [Nolabel, m; Nolabel, _]); _ }]); _ } }; _ ])
          when var x = Some inner && lident raise_ = Some ["invalid_arg"]
            && (match pat_var p with Some v -> is_blank_test v guard | None -> false) ->
            (match string_literal m with Some m -> strip_prefix fname m | None -> skip "List.iter message")
        | _ -> skip "unrecognised List.iter check" in
      let rec items = function
        | { pexp_desc = Pexp_construct ({ txt = Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [h; t]; _ }); _ } -> h :: items t
        | { pexp_desc = Pexp_construct ({ txt = Lident "[]"; _ }, None); _ } -> []
        | _ -> skip "List.iter check over a non-literal list" in
      `Checks (List.map (function
        | { pexp_desc = Pexp_tuple [field; x]; _ } ->
            (match string_literal field, var x with
             | Some field, Some v -> Nonblank (v, prefix ^ field)
             | _ -> skip "unrecognised List.iter pair")
        | _ -> skip "unrecognised List.iter pair") (items pairs))
  | _ -> skip "unrecognised check statement: %s" (Pprintast.string_of_expression e)

(* ---------- the catalog module ---------- *)

type argument_binding =
  | Field of string            (* ~x:parameters.f *)
  | Optional_text of string    (* ?x:(optional_text parameters.f) *)
  | Vec3 of string             (* ~x:(Vec3.create parameters.g_x parameters.g_y parameters.g_z) *)
  | Slot of int                (* a lambda input *)
  | Toggled of string * string * bool
    (* ?x:(if parameters.t then Some parameters.f else None): Toggled (f, t, true);
       ?x:(if parameters.t then None else Some parameters.f): Toggled (f, t, false) *)
  | Unit_argument

let record_field = function
  | { pexp_desc = Pexp_field (p, { txt = Lident f; _ }); _ } when var p = Some "parameters" -> Some f
  | _ -> None

let classify_argument slots (label, (e : expression)) = match label, e with
  | Asttypes.Nolabel, { pexp_desc = Pexp_construct ({ txt = Lident "()"; _ }, None); _ } -> Unit_argument
  | Nolabel, _ -> (match var e with
      | Some v -> (match List.assoc_opt v slots with Some i -> Slot i | None ->
          skip "positional argument %s is not an input" v)
      | None -> skip "positional argument is not an input: %s" (Pprintast.string_of_expression e))
  | (Labelled _ | Optional _), _ ->
      (match record_field e with
       | Some f -> Field f
       | None when (match var e with Some v -> List.mem_assoc v slots | None -> false) ->
           Slot (List.assoc (Option.get (var e)) slots)
       | None ->
           match e.pexp_desc with
           | Pexp_ifthenelse (t, a, Some b) ->
               let some = function
                 | { pexp_desc = Pexp_construct ({ txt = Lident "Some"; _ }, Some x); _ } -> record_field x
                 | _ -> None in
               let none = function
                 | { pexp_desc = Pexp_construct ({ txt = Lident "None"; _ }, None); _ } -> true | _ -> false in
               (match record_field t, some a, none b, none a, some b with
                | Some t, Some f, true, _, _ -> Toggled (f, t, true)
                | Some t, _, _, true, Some f -> Toggled (f, t, false)
                | _ -> skip "if-argument is not a toggled field")
           | Pexp_apply (f, [Nolabel, x]) when lident f = Some ["optional_text"] ->
               (match record_field x with Some f -> Optional_text f | None -> skip "optional_text of a non-field")
           | Pexp_apply (f, [Nolabel, x; Nolabel, y; Nolabel, z]) when lident f = Some ["Vec3"; "create"] ->
               (match record_field x, record_field y, record_field z with
                | Some x, Some y, Some z ->
                    let strip s suffix = if String.ends_with ~suffix s then
                        Some (String.sub s 0 (String.length s - String.length suffix)) else None in
                    (match strip x "_x", strip y "_y", strip z "_z" with
                     | Some g, Some g', Some g'' when g = g' && g = g'' -> Vec3 g
                     | _ -> skip "vec3 argument over fields that are no _x/_y/_z group")
                | _ -> skip "Vec3.create of non-fields")
           | _ -> skip "argument %s is not a field, optional_text or vec3 group: %s"
               (match label with Labelled l | Optional l -> l | Nolabel -> "")
               (Pprintast.string_of_expression e))

(* record field name -> declaration *)
let record_fields = function
  | { ptype_kind = Ptype_record fields; _ } -> List.map (fun f -> f.pld_name.txt, f) fields
  | _ -> skip "parameters is not a record"

let attribute_payload name (attrs : attributes) = List.find_map (fun a ->
    if a.attr_name.txt = name then match a.attr_payload with
      | PStr [{ pstr_desc = Pstr_eval (e, _); _ }] -> Some e | _ -> None
    else None) attrs

(* numeric literals compare by value, anything else by text *)
let same_expression (src_a, a) (src_b, b) =
  let number e = match e.pexp_desc with
    | Pexp_constant { pconst_desc = Pconst_float (f, _); _ } -> Some (float_of_string f)
    | Pexp_constant { pconst_desc = Pconst_integer (i, _); _ } -> Some (float_of_string i)
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident "~-"; _ }; _ }, [Nolabel,
        { pexp_desc = Pexp_constant { pconst_desc = Pconst_float (f, _) | Pconst_integer (f, _); _ }; _ }]) ->
        Some (-. float_of_string f)
    | _ -> None in
  match number a, number b with
  | Some x, Some y -> x = y
  | _ -> let norm s = String.concat "" (String.split_on_char ' ' s) in
      norm (text src_a a.pexp_loc) = norm (text src_b b.pexp_loc)

(* ---------- shared.ml helpers ---------- *)


let identifiers (iter : 'a -> Ast_iterator.iterator -> unit) value =
  let names = Hashtbl.create 64 and bound = Hashtbl.create 64 in
  let it = { Ast_iterator.default_iterator with
    pat = (fun self p ->
      (match p.ppat_desc with Ppat_var { txt; _ } -> Hashtbl.replace bound txt () | _ -> ());
      Ast_iterator.default_iterator.pat self p);
    expr = (fun self e ->
      (match e.pexp_desc with
       | Pexp_ident { txt = Lident v; _ } -> Hashtbl.replace names v ()
       | _ -> ());
      Ast_iterator.default_iterator.expr self e);
    typ = (fun self t ->
      (match t.ptyp_desc with
       | Ptyp_constr ({ txt = Lident v; _ }, _) -> Hashtbl.replace names v ()
       | _ -> ());
      Ast_iterator.default_iterator.typ self t) } in
  iter value it;
  Hashtbl.iter (fun n () -> Hashtbl.remove names n) bound;
  names

(* The shared items the module names, transitively, that sop_support.ml lacks. *)
(* The items of [candidates] (names defined, text, item, location) that
   [module_items] or [extra] name, transitively, and sop_support.ml lacks, in
   their original order so each is defined before use. *)
let needed support_src candidates (module_items : structure) (extra : expression) =
  let have = Hashtbl.create 64 in
  let _, support = (let lexbuf = Lexing.from_string support_src in Lexer.init ();
                    support_src, Parse.implementation lexbuf) in
  List.iter (fun (item : structure_item) -> match item.pstr_desc with
    | Pstr_value (_, bindings) -> List.iter (fun b -> Option.iter (fun n -> Hashtbl.replace have n ()) (pat_var b.pvb_pat)) bindings
    | Pstr_type (_, decls) -> List.iter (fun d -> Hashtbl.replace have d.ptype_name.txt ()) decls
    | _ -> ()) support;
  let wanted = Hashtbl.create 64 in
  let rec visit (names : (string, unit) Hashtbl.t) =
    List.iter (fun (defined, _, item, _) ->
      if List.exists (Hashtbl.mem names) defined && not (List.exists (Hashtbl.mem have) defined) then begin
        List.iter (fun n -> Hashtbl.replace have n (); Hashtbl.replace wanted n ()) defined;
        visit (identifiers (fun i it -> it.structure_item it i) item)
      end) candidates in
  visit (identifiers (fun items it -> it.structure it items) module_items);
  visit (identifiers (fun e it -> it.expr it e) extra);
  List.filter (fun (defined, _, _, _) -> List.exists (Hashtbl.mem wanted) defined) candidates

let definitions src (items : structure) = List.filter_map (fun (item : structure_item) ->
    let names = match item.pstr_desc with
      | Pstr_value (_, bindings) -> List.filter_map (fun b -> pat_var b.pvb_pat) bindings
      | Pstr_type (_, decls) -> List.map (fun d -> d.ptype_name.txt) decls
      | _ -> [] in
    if names = [] then None else Some (names, text src item.pstr_loc, item, item.pstr_loc)) items

(* ---------- one node ---------- *)

let catalog_files = ["shapes"; "topology"; "attributes"; "groups"]

let find_module name =
  List.find_map (fun file ->
    let path = "lib/sop_catalog/" ^ file ^ ".ml" in
    let src, items = parse_with Parse.implementation path in
    List.find_map (fun (item : structure_item) -> match item.pstr_desc with
      | Pstr_module { pmb_name = { txt = Some m; _ }; pmb_expr = { pmod_desc = Pmod_structure body; _ }; _ }
        when m = name -> Some (file, path, src, item, body)
      | _ -> None) items) catalog_files

let merge ~dry name =
  let file, catalog_path, catalog_src, module_item, body = match find_module name with
    | Some found -> found | None -> fail "no catalog module %s" name in
  let record = List.find_map (fun (item : structure_item) -> match item.pstr_desc with
      | Pstr_type (_, [d]) when d.ptype_name.txt = "parameters" -> Some d | _ -> None) body in
  let record = match record with Some r -> r | None -> skip "no parameters record" in
  let fields = record_fields record in
  let build_item, lambda = match List.find_map (fun (item : structure_item) -> match item.pstr_desc with
      | Pstr_value (_, [{ pvb_pat; pvb_expr = { pexp_desc = Pexp_apply (f, [Nolabel, lambda]); _ }; _ }])
        when pat_var pvb_pat = Some "build" && lident f = Some ["parameters_build"] -> Some (item, lambda)
      | _ -> None) body with
    | Some found -> found | None -> skip "no [let build = parameters_build (fun ...)]" in
  let lambda_params, application = typed_params lambda in
  let slots = List.filter_map (fun p -> if p.name = "label" || p.name = "parameters" then None else Some p.name)
      lambda_params in
  let slots = List.mapi (fun i s -> s, i) slots in
  let slot_name i = match attribute_payload "sop.node_slots" record.ptype_attributes with
    | Some e -> (match string_literal e with
        | Some names -> List.nth (List.map String.trim (String.split_on_char ',' names)) i
        | None -> fail "sop.node_slots is not a string")
    | None -> "in" ^ string_of_int i in
  let fname, application_args = match application with
    | { pexp_desc = Pexp_apply (f, args); _ } ->
        (match lident f with Some ["Sop"; fname] -> fname, args
         | _ -> skip "build does not apply Sop.<f>")
    | _ -> skip "build body is not an application" in
  (* the typed function *)
  let sop_src, sop_items = parse_with Parse.implementation "lib/procedural/sop.ml" in
  let typed_item, typed_binding = match List.find_map (fun (item : structure_item) -> match item.pstr_desc with
      | Pstr_value (_, [b]) when pat_var b.pvb_pat = Some fname -> Some (item, b) | _ -> None) sop_items with
    | Some found -> found | None -> skip "no Sop.%s in sop.ml" fname in
  let params, typed_body = typed_params typed_binding.pvb_expr in
  let checks, final = statements typed_body in
  let make, make_args = make_application final in
  (* which catalog argument feeds each typed parameter *)
  let bound = List.map (fun (label, e) ->
    (match label with Asttypes.Labelled l | Optional l -> l | Nolabel -> ""), (label, e)) application_args in
  let positional = ref (List.filter_map (fun (l, (label, e)) -> if l = "" then Some (label, e) else None) bound) in
  let drift = ref [] and field_attrs = ref [] and args = ref [] in
  (* the cook keeps f's [?label] by rebinding the build's label *)
  let lets = ref ["label", "Some label"] in
  let add_field_attr f a = field_attrs := (f, a) :: !field_attrs in
  let field f = match List.assoc_opt f fields with Some d -> d | None -> skip "no field %s" f in
  let catalog_text e = text catalog_src e.pexp_loc in
  List.iter (fun p ->
    if p.name = "label" then () else
    let argument = match p.label with
      | Nolabel -> (match !positional with
          | a :: rest -> positional := rest; Some a | [] -> skip "typed positional %s has no catalog argument" p.name)
      | Labelled l | Optional l -> List.assoc_opt l bound in
    let argument = match argument with
      | Some a -> a | None -> skip "typed parameter %s is not passed by the catalog build" p.name in
    let binding = classify_argument slots argument in
    let token prefix name = args := (prefix ^ name) :: !args in
    let prefix = match p.label with Optional _ -> "?" | Labelled _ -> "~" | Nolabel -> "" in
    let let_ e = lets := (p.name, e) :: !lets in
    let catalog_label, (expr : expression) = argument in
    let arg_text = catalog_text expr in
    (match binding with
     | Unit_argument -> args := "()" :: !args
     | Toggled (f, toggle, present) ->
         (match p.label, p.default with
          | Optional _, None -> ()
          | _ -> skip "toggled argument %s is not a plain ?%s" p.name p.name);
         token prefix (p.name ^ (if f = p.name then "" else "=" ^ f));
         add_field_attr f (Printf.sprintf "[@sop.%s %S]" (if present then "present" else "absent") toggle);
         let_ arg_text
     | Slot i -> token prefix (slot_name i);
         if Option.get (var expr) <> p.name then let_ arg_text
     | Field f | Optional_text f ->
         let d = field f in
         let alias = if f = p.name then "" else "=" ^ f in
         token prefix (p.name ^ alias);
         (* the typed default versus the editor default *)
         (match p.default, attribute_payload "sop.default" d.pld_attributes with
          | Some td, Some ed when not (same_expression (sop_src, td) (catalog_src, ed)) ->
              let td_text = text sop_src td.pexp_loc in
              add_field_attr f (Printf.sprintf "[@sop.arg_default (%s)]" td_text);
              drift := Printf.sprintf "%s.%s: typed default %s, editor default %s" fname p.name td_text
                  (text catalog_src ed.pexp_loc) :: !drift
          | _ -> ());
         (match binding, p.label, p.default with
          | Optional_text _, Optional _, None ->
              (match attribute_payload "sop.default" d.pld_attributes with
               | Some { pexp_desc = Pexp_constant { pconst_desc = Pconst_string ("", _, _); _ }; _ } -> ()
               | _ -> skip "?%s is optional_text of a field whose editor default is not \"\"" p.name)
          | _ -> ());
         (* the cook's binding *)
         (match catalog_label, p.label, p.default with
          | Asttypes.Optional _, Optional _, None | Labelled _, (Labelled _ | Nolabel), _ -> let_ arg_text
          | Labelled _, Optional _, Some _ -> let_ arg_text
          | Labelled _, Optional _, None -> let_ ("Some (" ^ arg_text ^ ")")
          | Optional _, Optional _, Some td ->
              let_ (Printf.sprintf "Option.value ~default:(%s) (%s)" (text sop_src td.pexp_loc) arg_text)
          | _ -> skip "argument %s: unsupported label combination" p.name)
     | Vec3 g ->
         token prefix (p.name ^ (if g = p.name then "" else "=" ^ g));
         (match p.default with
          | Some td -> let components = [g ^ "_x"; g ^ "_y"; g ^ "_z"] in
              let eds = List.map (fun c -> attribute_payload "sop.default" (field c).pld_attributes) components in
              (match td.pexp_desc, eds with
               | Pexp_apply (f, [Nolabel, x; Nolabel, y; Nolabel, z]), [Some ex; Some ey; Some ez]
                 when lident f = Some ["Vec3"; "create"] ->
                   List.iter2 (fun (c, t) e -> if not (same_expression (sop_src, t) (catalog_src, e)) then begin
                       add_field_attr c (Printf.sprintf "[@sop.arg_default (%s)]" (text sop_src t.pexp_loc));
                       drift := Printf.sprintf "%s.%s: typed default %s, editor default %s" fname c
                           (text sop_src t.pexp_loc) (text catalog_src e.pexp_loc) :: !drift end)
                     (List.combine components [x; y; z]) [ex; ey; ez]
               | Pexp_ident { txt = Ldot (Lident "Vec3", "zero"); _ }, _ ->
                   List.iter2 (fun c e -> match e with
                     | Some { pexp_desc = Pexp_constant { pconst_desc = Pconst_float (f, _); _ }; _ } when float_of_string f = 0. -> ()
                     | _ -> add_field_attr c "[@sop.arg_default 0.]";
                         drift := Printf.sprintf "%s.%s: typed default 0., editor default differs" fname c :: !drift)
                     components eds
               | _ -> skip "vec3 default of %s is not Vec3.create or Vec3.zero" p.name)
          | None -> ());
         let_ arg_text)) params;
  (* checks *)
  List.iter (fun check ->
    let by_param name = match List.find_opt (fun p -> p.name = name) params with
      | Some p -> p | None -> skip "check on %s, which is no parameter" name in
    let field_of_param p = match p.label with
      | Nolabel | Labelled _ | Optional _ ->
          let l = p.name in
          (match List.assoc_opt l bound with
           | Some (_, e) -> (match classify_argument slots (Asttypes.Labelled l, e) with
               | Field f | Optional_text f | Toggled (f, _, _) -> `Field f | Vec3 g -> `Vec3 g
               | _ -> skip "check on an input")
           | None -> skip "check on %s, which the catalog does not pass" l) in
    match classify_check fname check with
    | `Checks list -> List.iter (function
        | Nonblank (v, m) -> (match field_of_param (by_param v) with
            | `Field f -> add_field_attr f (Printf.sprintf "[@sop.nonblank %S]" m)
            | `Vec3 _ -> skip "nonblank on a vec3")
        | Validate (v, m, lower, upper) ->
            (match field_of_param (by_param v) with
             | `Field f ->
                 let d = field f in
                 let same bound attr = match bound, attribute_payload attr d.pld_attributes with
                   | None, None -> true
                   | Some b, Some h -> same_expression (sop_src, b) (catalog_src, h)
                   | _ -> false in
                 if not (same lower "sop.hard_min" && same upper "sop.hard_max") then
                   skip "range check on %s differs from its hard range" v;
                 add_field_attr f (Printf.sprintf "[@sop.validate %S]" m)
             | `Vec3 _ -> skip "range check on a vec3")) list
    | `Vec3 (Vec3_finite (v, m)) ->
        (match field_of_param (by_param v) with
         | `Vec3 g -> List.iter (fun c ->
             let d = field c in
             if attribute_payload "sop.hard_min" d.pld_attributes <> None
                || attribute_payload "sop.hard_max" d.pld_attributes <> None then
               skip "vec3 finiteness check on %s, which has a hard range" c;
             add_field_attr c (Printf.sprintf "[@sop.validate %S]" m)) [g ^ "_x"; g ^ "_y"; g ^ "_z"]
         | `Field _ -> skip "vec3 finiteness check on a scalar")) checks;
  (* the new module text *)
  let module_src = text catalog_src module_item.pstr_loc in
  let base = module_item.pstr_loc.loc_start.pos_cnum in
  let edits = ref [] in
  let edit (loc : Location.t) t = edits := (loc.loc_start.pos_cnum - base, loc.loc_end.pos_cnum - base, t) :: !edits in
  let insert pos t = edits := (pos - base, pos - base, t) :: !edits in
  let deriving = List.find_opt (fun a -> a.attr_name.txt = "deriving") record.ptype_attributes in
  let deriving = match deriving with Some d -> d | None -> skip "no [@@deriving]" in
  let args_text = String.concat " " (List.rev !args) in
  insert deriving.attr_loc.loc_start.pos_cnum
    (Printf.sprintf "[@@sop.fn %S] [@@sop.args %S]\n    " fname args_text);
  List.iter (fun (f, _) ->
    let d = field f in
    let attrs = List.filter_map (fun (g, a) -> if g = f then Some a else None) (List.rev !field_attrs) in
    let last = List.fold_left (fun e (a : attribute) -> max e a.attr_loc.loc_end.pos_cnum)
        d.pld_type.ptyp_loc.loc_end.pos_cnum d.pld_attributes in
    if attrs <> [] then insert last (" " ^ String.concat " " attrs)) fields;
  (* f's body: checks out, [?label] -> [~label], hand key -> "" *)
  let body_text =
    let start = typed_body.pexp_loc.loc_start.pos_cnum in
    let body_edits = ref [] in
    List.iter (fun (c : expression) ->
      (* the statement and the [;] after it *)
      let s = c.pexp_loc.loc_start.pos_cnum and e = c.pexp_loc.loc_end.pos_cnum in
      let rec semi i = if sop_src.[i] = ';' then i + 1 else semi (i + 1) in
      let e = semi e in
      let rec eat i = if i < String.length sop_src && (sop_src.[i] = ' ' || sop_src.[i] = '\n') then eat (i + 1) else i in
      body_edits := (s - start, eat e - start, "") :: !body_edits) checks;
    List.iter (fun (label, (e : expression)) -> match label with
      | Asttypes.Labelled "parameters" ->
          (* the argument text spans "~parameters:(...)": find its label start *)
          let rec back i = if sop_src.[i] = '~' then i else back (i - 1) in
          let s = back (e.pexp_loc.loc_start.pos_cnum - 1) in
          body_edits := (s - start, e.pexp_loc.loc_end.pos_cnum - start, "~parameters:\"\"") :: !body_edits
      | _ -> ()) make_args;
    (* a [let x = e in] the hand key alone used goes with it *)
    let parameters_arg = List.find_map (fun (label, e) ->
        if label = Asttypes.Labelled "parameters" then Some e else None) make_args in
    let uses name =
      let count = ref 0 in
      let it = { Ast_iterator.default_iterator with
        expr = (fun self e ->
          (match e.pexp_desc with
           | Pexp_ident { txt = Lident v; _ } when v = name -> incr count
           | _ -> ());
          if not (match parameters_arg with Some p -> p == e | None -> false) then
            Ast_iterator.default_iterator.expr self e) } in
      it.expr it final;
      !count in
    let rec lets = function
      | { pexp_desc = Pexp_let (_, [binding], body); pexp_loc; _ } ->
          (match pat_var binding.pvb_pat with
           | Some name when uses name = 0 ->
               (* "let x = e in" through the whitespace after [in] *)
               let s = pexp_loc.loc_start.pos_cnum in
               let rec in_after i = if String.sub sop_src i 2 = "in" then i + 2 else in_after (i + 1) in
               let e = in_after binding.pvb_loc.loc_end.pos_cnum in
               let rec eat i = if sop_src.[i] = ' ' || sop_src.[i] = '\n' then eat (i + 1) else i in
               body_edits := (s - start, eat e - start, "") :: !body_edits
           | _ -> ());
          lets body
      | { pexp_desc = Pexp_let (_, _, body); _ } -> lets body
      | _ -> () in
    lets final;
    ignore make;
    apply_edits (text sop_src typed_body.pexp_loc) !body_edits in
  let lambda_header =
    let s = lambda.pexp_loc.loc_start.pos_cnum and e = application.pexp_loc.loc_start.pos_cnum in
    let header = String.trim (String.sub catalog_src s (e - s)) in
    if header.[0] = '(' then String.sub header 1 (String.length header - 1) else header in
  let indent = Str.global_replace (Str.regexp "\n") "\n  " in
  let unparen e = let e = String.trim e in
    if e.[0] = '(' && e.[String.length e - 1] = ')' then String.sub e 1 (String.length e - 2) else e in
  let new_build = Printf.sprintf "let build = parameters_build (%s%s%s)"
      lambda_header
      (String.concat "" (List.rev_map (fun (n, e) -> Printf.sprintf "\n    let %s = %s in" n (indent (unparen e))) !lets))
      ("\n    " ^ indent body_text) in
  edit build_item.pstr_loc new_build;
  (* the typed alias after the factory *)
  let last = List.nth body (List.length body - 1) in
  insert last.pstr_loc.loc_end.pos_cnum "\n  let fn = parameters_fn build";
  let new_module = apply_edits module_src !edits in
  let support_path = "lib/procedural/sop_support.ml" in
  let support_src = read support_path in
  (* Shared helpers are copied (the catalog still has nodes); sop.ml helpers the
     cook names, other than typed SOPs, move *)
  let shared_src, shared = parse_with Parse.implementation "lib/sop_catalog/shared.ml" in
  let cook = Parse.expression (Lexing.from_string body_text) in
  let helpers = needed support_src (definitions shared_src shared) body cook in
  let exported = let _, mli = parse_with Parse.interface "lib/procedural/sop.mli" in
    List.filter_map (fun (i : signature_item) -> match i.psig_desc with
      | Psig_value v -> Some v.pval_name.txt | _ -> None) mli in
  (* of a name defined twice, the definition in scope at the typed function *)
  let in_scope = List.filter (fun (defined, _, _, (loc : Location.t)) ->
      loc.loc_end.pos_cnum <= typed_item.pstr_loc.loc_start.pos_cnum
      && not (List.exists (fun n -> List.mem n exported) defined)) (definitions sop_src sop_items) in
  let movable = List.filter (fun (defined, _, _, (loc : Location.t)) ->
      not (List.exists (fun (names, _, _, (later : Location.t)) ->
        later.loc_start.pos_cnum > loc.loc_start.pos_cnum
        && List.exists (fun n -> List.mem n names) defined) in_scope)) in_scope in
  let moved = needed (support_src ^ String.concat "\n" (List.map (fun (_, t, _, _) -> t) helpers))
      movable body cook in
  let target = Printf.sprintf "lib/procedural/sop_%s.ml" file in
  Printf.printf "%s: %s -> %s (Sop.%s); args %S\n" name catalog_path target fname args_text;
  List.iter (fun d -> Printf.printf "  drift: %s\n" d) (List.rev !drift);
  List.iter (fun (f, a) -> Printf.printf "  %s %s\n" f a) (List.rev !field_attrs);
  List.iter (fun (_, h, _, _) -> Printf.printf "  shared helper: %s\n" (List.hd (String.split_on_char '\n' h))) helpers;
  List.iter (fun (_, h, _, _) -> Printf.printf "  moved from sop.ml: %s\n" (List.hd (String.split_on_char '\n' h))) moved;
  if not dry then begin
    write target (read target ^ "\n" ^ new_module ^ "\n");
    if helpers <> [] || moved <> [] then write support_path (support_src ^ "\n"
      ^ String.concat "\n\n" (List.map (fun (_, t, _, _) -> t) (helpers @ moved)) ^ "\n");
    let s, e = line_range catalog_src module_item.pstr_loc in
    write catalog_path (apply_edits catalog_src [s, e, ""]);
    let s, e = line_range sop_src typed_item.pstr_loc in
    write "lib/procedural/sop.ml" (apply_edits sop_src
      ((s, e, Printf.sprintf "let %s = Sop_%s.%s.fn\n" fname file name)
       :: List.map (fun (_, _, _, loc) -> let s, e = line_range sop_src loc in s, e, "") moved));
    write "lib/procedural/nodes.ml" (read "lib/procedural/nodes.ml"
      ^ Printf.sprintf "module %s = Sop_%s.%s\n" name file name);
    (* the signature Sop_catalog exports for the module ([create]) moves along *)
    let exported =
      let mli_src, items = parse_with Parse.interface "lib/sop_catalog/sop_catalog.mli" in
      List.concat_map (fun (item : signature_item) -> match item.psig_desc with
        | Psig_module { pmd_name = { txt = Some m; _ }; pmd_type = { pmty_desc = Pmty_signature inner; _ }; _ }
          when m = name ->
            List.map (fun (i : signature_item) ->
              Str.global_replace (Str.regexp_string "Procedural.") "" (text mli_src i.psig_loc)) inner
        | _ -> []) items in
    write "lib/procedural/nodes.mli" (read "lib/procedural/nodes.mli"
      ^ (if exported = [] then Printf.sprintf "module %s : sig val factory : Edit_graph.factory end\n" name
         else Printf.sprintf "module %s : sig\n  val factory : Edit_graph.factory\n  %s\nend\n" name
           (String.concat "\n  " exported)));
    let registry = read "lib/sop_catalog/sop_catalog.ml" in
    let old = Printf.sprintf "module %s = %s.%s [@@sop.register]" name (String.capitalize_ascii file) name in
    let fresh = Printf.sprintf "module %s = Procedural.Nodes.%s [@@sop.register]" name name in
    (match Str.search_forward (Str.regexp_string old) registry 0 with
     | exception Not_found -> fail "%s is not registered in sop_catalog.ml" name
     | i -> write "lib/sop_catalog/sop_catalog.ml"
         (String.sub registry 0 i ^ fresh ^ String.sub registry (i + String.length old)
            (String.length registry - i - String.length old)))
  end

let () =
  let dry = ref false and names = ref [] in
  Array.iteri (fun i a -> if i > 0 then if a = "--dry-run" then dry := true else names := a :: !names) Sys.argv;
  if !names = [] then fail "usage: sop_merge [--dry-run] MODULE...";
  List.iter (fun name ->
    match merge ~dry:!dry name with
    | () -> ()
    | exception Skip reason -> Printf.printf "%s: left hand-written: %s\n" name reason)
    (List.rev !names)
