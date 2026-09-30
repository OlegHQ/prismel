module S = Syntax
module Smap = Map.Make (String)
module Paths = Set.Make (struct type t = string list let compare = compare end)

type path = string list
type context = Sop | Value | Scene | World | Settings | Editor
let context_name = function
  | Sop -> "sop" | Value -> "value" | Scene -> "scene" | World -> "world"
  | Settings -> "settings" | Editor -> "editor"
let context_of_name = function
  | "sop" -> Some Sop | "value" -> Some Value | "scene" -> Some Scene
  | "world" -> Some World | "settings" -> Some Settings | "editor" -> Some Editor
  | _ -> None
let context_ty = function
  | Sop -> Ty.Geometry | Value -> Ty.Float | Scene -> Ty.Scene | World -> Ty.World
  | Settings -> Ty.Settings | Editor -> Ty.Editor
(* Catalog kinds know every context but the editor, which only sees value kinds. *)
let catalog_context = function
  | Sop -> Context.Sop | Scene -> Context.Scene | World -> Context.World
  | Settings -> Context.Settings | Value | Editor -> Context.Value

type pattern = Name of string | Seq of pattern list | Keys of string list
type term = { path : path option; ty : Ty.t; node : node; form : S.t }
and node =
  | Lit of Param.value
  | Text of string
  | Nil
  | Time
  | Vec of term list
  | Ref_binding of string * string list
  | Call of { kind : string; args : (string * term) list }
  | Op of { op : string; args : (string * term) list }
  | Call_fn of { fn : string; args : term list }
  | Fn_ref of string
  | Graph_ref of { graph : string; inputs : (string * term) list }
  | Let of (pattern * term) list * term
  | Loop of { kind : [ `For | `Fold | `Scan | `Sum ]; accs : (pattern * term) list;
              clauses : (pattern * term) list; body : term; zone : path }
  | If of term * term * term
  | Cond of (term * term) list * term
  | Case of term * (S.t * term) list * term
  | Fn of { params : (pattern * Ty.t option) list; body : term; zone : path }
  | Hof of [ `Map | `Filter | `Reduce | `Sort_by ] * term list
  | List_lit of term list
  | Record of (string * term) list
  | Get of term * string
  | Assoc of term * (string * term) list
  | Str of term list
  | List_op of string * term list
  | Bypass of term
  | Expanded of { macro : string; body : term }

type graph = { name : string; context : context;
  inputs : (string * Ty.t * term option) list; body : term; form : S.t }
type t = { name : string; graphs : graph list; defs : graph list; macros : S.t list;
  source : S.t list; live : Paths.t; invariant : Paths.t }

let max_iterations = 4096
(* ponytail: a guard against exponential call-site typing, not a language limit. *)
let max_steps = 400_000
let max_call_depth = 64

(* ---- names ---- *)

let special = [ "workspace"; "graph"; "defn"; "defmacro"; "let*"; "ref"; "for"; "fold";
  "scan"; "sum"; "if"; "values"; "fn"; "cond"; "case"; "list"; "concat"; "str"; "get";
  "assoc"; "map"; "filter"; "reduce"; "sort-by"; "quote"; "quasiquote"; "unquote";
  "unquote-splicing" ]
let reserved s = List.mem s special || List.mem s [ "t"; "pi"; "true"; "false"; "nil" ]
let type_names = [ "float"; "int"; "bool"; "text"; "vec3"; "geometry"; "scene"; "world";
  "settings"; "panel"; "editor" ]

(* ---- built-in operators (the study's value, scene, world, settings and ui ops) ---- *)

type op = { oname : string; octx : context; pos : (string * Ty.t) list;
  opt : (string * Ty.t) list; rest : (string * Ty.t) option;
  kw : (string * Ty.t) list; out : Ty.t list -> Ty.t; any_num : bool }

let lst j ts = match List.nth_opt ts j with Some (Ty.List _ as t) -> t | _ -> Ty.List Ty.Any
let elm j ts = match lst j ts with Ty.List e -> e | _ -> Ty.Any
let mk ?(octx = Value) ?(opt = []) ?rest ?(kw = []) ?(any_num = false) name pos out =
  { oname = name; octx; pos; opt; rest; kw; out; any_num }
let fl = Ty.Float
let num2 name = mk ~any_num:true name [ "a", fl; "b", fl ] (fun ts ->
  if List.mem Ty.Vec3 ts then Ty.Vec3
  else if name <> "/" && List.for_all (( = ) Ty.Int) ts then Ty.Int else Ty.Float)
let unary name out = mk name [ "x", fl ] out
let compare_op name = mk name [ "a", fl; "b", fl ] (fun _ -> Ty.Bool)
let bool_op name pos = mk name pos (fun _ -> Ty.Bool)
let panel name pos = mk ~octx:Editor name pos (fun _ -> Ty.Panel)
let ops = [
  num2 "+"; num2 "-"; num2 "*"; num2 "/"; num2 "mod";
  mk ~any_num:true "pow" [ "a", fl; "b", fl ] (fun ts -> if List.mem Ty.Vec3 ts then Ty.Vec3 else Ty.Float);
  num2 "min"; num2 "max";
  unary "sin" (fun _ -> fl); unary "cos" (fun _ -> fl); unary "sqrt" (fun _ -> fl);
  unary "floor" (fun _ -> Ty.Int);
  unary "abs" (function Ty.Int :: _ -> Ty.Int | _ -> fl);
  compare_op "<"; compare_op ">"; compare_op "<="; compare_op ">="; compare_op "=";
  bool_op "and" [ "a", Ty.Bool; "b", Ty.Bool ]; bool_op "or" [ "a", Ty.Bool; "b", Ty.Bool ];
  bool_op "not" [ "a", Ty.Bool ];
  mk ~rest:("key", fl) "value/rand" [] (fun _ -> fl);
  mk "value/hsv" [ "h", fl; "s", fl; "v", fl ] (fun _ -> Ty.Vec3);
  mk ~any_num:true "value/lerp" [ "a", fl; "b", fl; "u", fl ] (fun ts ->
    match ts with a :: b :: _ when a = Ty.Vec3 || b = Ty.Vec3 -> Ty.Vec3 | _ -> fl);
  mk ~opt:[ "height", fl ] "value/polar" [ "radius", fl; "angle", fl ] (fun _ -> Ty.Vec3);
  mk ~opt:[ "end", Ty.Int ] "range" [ "count", Ty.Int ] (fun _ -> Ty.List Ty.Int);
  mk "linspace" [ "from", fl; "to", fl; "count", Ty.Int ] (fun _ -> Ty.List fl);
  mk "count" [ "list", Ty.List Ty.Any ] (fun _ -> Ty.Int);
  mk "first" [ "list", Ty.List Ty.Any ] (elm 0); mk "last" [ "list", Ty.List Ty.Any ] (elm 0);
  mk "rest" [ "list", Ty.List Ty.Any ] (lst 0);
  mk "nth" [ "list", Ty.List Ty.Any; "index", Ty.Int ] (elm 0);
  mk "reverse" [ "list", Ty.List Ty.Any ] (lst 0);
  mk "take" [ "n", Ty.Int; "list", Ty.List Ty.Any ] (lst 1);
  mk "drop" [ "n", Ty.Int; "list", Ty.List Ty.Any ] (lst 1);
  (* ponytail: the catalog has no "curve from a list of points" kind (its sop/poly_path takes
     geometry); the workspace names one and W2 lowering must supply the native node. *)
  mk ~octx:Sop ~kw:[ "closed", Ty.Bool ] "sop/curve" [ "points", Ty.List Ty.Vec3 ] (fun _ -> Ty.Geometry);
  (* W8: lists whose length is known only when the geometry cooks; only a [for] over one
     runs (Eval makes a zone node), see [Eval] *)
  mk ~octx:Sop ~kw:[ "key", Ty.Text ] "sop/point_list" [ "geometry", Ty.Geometry ] (fun _ -> Ty.List Ty.Vec3);
  mk ~octx:Sop ~kw:[ "key", Ty.Text ] "sop/piece_list" [ "geometry", Ty.Geometry ] (fun _ -> Ty.List Ty.Geometry);
  mk ~octx:Scene ~rest:("scene", Ty.Scene) "scene/merge" [] (fun _ -> Ty.Scene);
  (* a world graph is authoritative (plan W10): this is how its text says there is no World *)
  mk ~octx:World "world/none" [] (fun _ -> Ty.World);
  mk ~octx:Editor "ui/workspace" [ "root", Ty.Panel ] (fun _ -> Ty.Editor);
  panel "ui/viewport" [ "scene", Ty.Scene ];
  { (panel "ui/graph" []) with opt = [ "graph", Ty.Text ] }; panel "ui/inspector" [];
  panel "ui/outline" []; panel "ui/list" []; panel "ui/lisp" []; panel "ui/timeline" [];
  panel "ui/split" [ "axis", Ty.Text; "first", Ty.Panel; "second", Ty.Panel ];
  panel "ui/split-at" [ "axis", Ty.Text; "ratio", fl; "first", Ty.Panel; "second", Ty.Panel ];
  { (panel "ui/tile" []) with rest = Some ("panel", Ty.Panel) };
  panel "ui/floating" [ "panel", Ty.Panel ];
]
let op_table = let h = Hashtbl.create 64 in List.iter (fun o -> Hashtbl.replace h o.oname o) ops; h
let find_op name ctx =
  let try_ n = Hashtbl.find_opt op_table n in
  match try_ name with
  | Some _ as o -> o
  | None -> (match try_ ("value/" ^ name) with
      | Some _ as o -> o
      | None -> try_ (context_name ctx ^ "/" ^ name))

(* ---- helpers ---- *)

let replace_all ~sub ~by s =
  let n = String.length sub in
  let b = Buffer.create (String.length s) in
  let i = ref 0 in
  while !i < String.length s do
    if !i + n <= String.length s && String.sub s !i n = sub then (Buffer.add_string b by; i := !i + n)
    else (Buffer.add_char b s.[!i]; incr i)
  done;
  Buffer.contents b
let show t = replace_all ~sub:"list:" ~by:"list of " (Ty.to_string t)
let plural n = if n = 1 then "" else "s"
let rec shape_ty = function
  | Ty.Geometry | Scene | World | Panel | Editor -> true
  | List e -> shape_ty e
  | Record fs -> List.exists (fun (_, t) -> shape_ty t) fs
  | _ -> false
let last_segment id = match List.rev id with s :: _ -> s | [] -> ""
let path_text id = String.concat "/" id
let sym_of (x : S.t) = match x.node with S.Sym s -> Some s | _ -> None
let pattern_key (x : S.t) = Lisp.flat x
let map_seq f xs = List.rev (List.fold_left (fun acc x -> f x :: acc) [] xs)

(* ---- checker state ---- *)

type v = { ty : Ty.t; live : bool; live_len : bool; vary : int list; len : int option;
  fn : callee option; groups : string list }
and callee =
  | Closure of closure
  | Def_fn of string
  | Op_fn of string
  | Kind_fn of Check.kind
and closure = { params : (S.t * Ty.t option) list; body : S.t; ccx : cx; cname : string; cid : path }
and cx = { env : v Smap.t; ctx : context; scope : string; path : path; in_def : bool;
  stack : string list; depth : int; zone : int; zbody : bool }

type arg = { key : string option; aform : S.t; aterm : term; av : v }
type signature = { sname : string; sctx : context; sparams : (string * Ty.t * S.t option) list;
  sbody : S.t; sform : S.t }

exception Budget

let leaf ?(live = false) ?(vary = []) ?(groups = []) ?len ty =
  { ty; live; live_len = false; vary; len; fn = None; groups }
let union a b = List.sort_uniq compare (a @ b)
let derive ty vs = { ty; live = List.exists (fun v -> v.live) vs; live_len = false;
  vary = List.fold_left (fun a v -> union a v.vary) [] vs; len = None; fn = None;
  groups = List.fold_left (fun a v -> union a v.groups) [] vs }
let poison = leaf Ty.Any

let port_ty = function
  | Ty.Float -> Some Port_type.Float | Int -> Some Port_type.Int | Bool -> Some Port_type.Bool
  | Vec3 -> Some Port_type.Vec3 | Geometry -> Some Port_type.Geometry | _ -> None
let ty_of_port = function
  | Port_type.Float -> Ty.Float | Int -> Ty.Int | Bool -> Ty.Bool | Vec3 -> Ty.Vec3
  | Geometry -> Ty.Geometry
let is_color (p : Check.parameter) = p.ty = Some Port_type.Vec3 && (match p.fields with
  | [ (a, _, _); (b, _, _); (c, _, _) ] ->
      String.ends_with ~suffix:"_r" a && String.ends_with ~suffix:"_g" b
      && String.ends_with ~suffix:"_b" c
  | _ -> false)
let param_ty (p : Check.parameter) = match p.ty with
  | Some Port_type.Vec3 when is_color p -> Ty.Color
  | Some t -> ty_of_port t
  | None -> Ty.Text
let kind_out (k : Check.kind) = match k.context, k.outputs with
  | Context.Scene, _ -> Ty.Scene | World, _ -> Ty.World | Settings, _ -> Ty.Settings
  | _, [ (_, t) ] -> ty_of_port t
  | _, [] -> Ty.Any
  | _, outs -> Ty.Record (List.map (fun (n, t) -> (n, ty_of_port t)) outs)
(* ponytail: the catalog has no group markers yet; a `group` parameter reads a group and
   `name` on a `sop/group_*` kind writes one. *)
let group_reader (p : Check.parameter) = p.name = "group"
let group_writer (k : Check.kind) (p : Check.parameter) =
  p.name = "name" && String.starts_with ~prefix:"sop/group_" k.qualified

let rec to_check (t : term) : Check.term =
  let ty = port_ty t.ty in
  match t.node with
  | Lit v -> { node = Check.Literal v; ty }
  | Text s -> { node = Check.Literal (Param.Text_value s); ty = None }
  | Nil -> { node = Check.Nil; ty }
  | Vec cs -> { node = Check.Vector (List.map (fun (c : term) ->
      let c = to_check c in if c.ty = None then { c with ty = Some Port_type.Float } else c) cs); ty }
  | _ -> { node = Check.Reference ("_", "_"); ty }

let hex_colour s =
  let n = String.length s in
  n > 0 && s.[0] = '#' && (n = 4 || n = 7 || n = 9)
  && String.for_all (function '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true | _ -> false)
       (String.sub s 1 (n - 1))
let rec pairs = function a :: b :: rest -> (a, b) :: pairs rest | _ -> []
let is_kw (x : S.t) = match x.node with S.Kw _ -> true | _ -> false
let tm (x : S.t) ty node = { path = None; ty; node; form = x }
let rec pat_ir (p : S.t) = match p.node with
  | S.Sym n -> Name n
  | S.Vec ps -> Seq (List.map pat_ir ps)
  | S.Map [ _; { S.node = S.Vec ks; _ } ] -> Keys (List.filter_map sym_of ks)
  | _ -> Name "_"
let rec pat_names (p : S.t) = match p.node with
  | S.Sym n -> [ n ]
  | S.Vec ps -> List.concat_map pat_names ps
  | S.Map [ _; { S.node = S.Vec ks; _ } ] -> List.filter_map sym_of ks
  | _ -> []

let check catalog forms =
  let diags = ref [] in
  let live = ref Paths.empty and invariant = ref Paths.empty in
  let steps = ref 0 and zones = ref 0 in
  let add sev (x : S.t) code msg =
    let span = if x.span.start = 0 && x.span.finish = 0 then None else Some x.span in
    diags := (match sev with
      | Diagnostic.Error -> Diagnostic.error ?span ~code msg
      | Diagnostic.Warning -> Diagnostic.warning ?span ~code msg) :: !diags in
  let err x code msg = add Diagnostic.Error x code msg in
  let bad x code msg = err x code msg; (tm x Ty.Any Nil, poison) in
  let mark id (v : v) = if v.live then live := Paths.add id !live in
  let names : (string, unit) Hashtbl.t = Hashtbl.create 16 in
  let sigs : (string, signature) Hashtbl.t = Hashtbl.create 8 in
  let gsigs : (string, signature) Hashtbl.t = Hashtbl.create 8 in
  let macro_tbl : (string, S.t) Hashtbl.t = Hashtbl.create 8 in
  let macro_forms = ref [] in
  let kind_memo = Hashtbl.create 64 in
  let kind_of ctx head =
    let key = (context_name ctx, head) in
    match Hashtbl.find_opt kind_memo key with
    | Some r -> r
    | None ->
        let r = Check.resolve_kind catalog (catalog_context ctx) head in
        Hashtbl.add kind_memo key r; r in
  let resolve_head cx s = match Hashtbl.find_opt sigs s with
    | Some d -> `Def d
    | None -> (match Hashtbl.find_opt macro_tbl s with
        | Some m -> `Macro m
        | None -> (match find_op s cx.ctx with
            | Some o -> `Op o
            | None -> (match kind_of cx.ctx s with Ok k -> `Kind k | Error e -> `Missing e))) in
  let known s = reserved s || List.mem s type_names || s = "fn" || Hashtbl.mem names s
    || List.exists (fun c -> find_op s c <> None) [ Value; Sop; Scene; World; Settings; Editor ]
    || (match kind_of Sop s with
        | Ok _ | Error (("E_WRONG_CONTEXT" | "E_AMBIGUOUS"), _) -> true
        | Error _ -> false) in
  let value_op s = match find_op s Value with Some o -> o.octx = Value | None -> false in
  let no_fn x (t : Ty.t) what =
    if Ty.has_fn t then
      err x "E_FN_ESCAPES" (Printf.sprintf "%s is a function; a function value cannot be stored or returned (E_FN_ESCAPES). Call it where it is bound." what) in
  let need (a : arg) what want =
    if Ty.fits a.av.ty want then true
    else (err a.aform "E_TYPE" (Printf.sprintf "%s: expected %s, got %s." what (show want) (show a.av.ty)); false) in
  let field x (v : v) f name =
    let derived ty = { v with ty; live_len = false; len = None; fn = None } in
    match v.ty with
    | Ty.Any -> derived Ty.Any
    | Ty.Vec3 when f = "x" || f = "y" || f = "z" -> derived Ty.Float
    | Ty.Record fs ->
        (match List.assoc_opt f fs with
         | Some t -> derived t
         | None ->
             err x "E_FIELD" (Printf.sprintf "%s has no field %s. Fields: %s." name f
               (if fs = [] then "none" else String.concat ", " (List.map fst fs)));
             poison)
    | _ ->
        err x "E_FIELD" (Printf.sprintf "%s has no output %s. A vec3 has .x .y .z; a record has its fields." name f);
        poison in
  let check_pat cx (pat : S.t) seen what zone =
    let msg_shape p = if zone then Printf.sprintf "%s binds names; %s is not a name or pattern." what (pattern_key p)
      else Printf.sprintf "Invalid binding name %s. Bind a name, [a b] or {:keys [a b]}." (pattern_key p) in
    let ok = ref true in
    let name_ok (at : S.t) n =
      if not (Macro.valid_name n) || reserved n then begin
        ok := false;
        err at "E_BINDING" (if zone then Printf.sprintf "%s binds names; %s is not a valid one." what n
          else Printf.sprintf "Invalid binding name %s%s." n (if n = "t" then ": t is the context time" else ""))
      end else if Hashtbl.mem seen n then begin
        ok := false; err at "E_DUPLICATE" (Printf.sprintf "%s is bound twice in one %s." n what)
      end else if Smap.mem n cx.env then begin
        ok := false;
        err at "E_SHADOW" (if zone then Printf.sprintf "%s shadows an outer name. Pick another loop name." n
          else Printf.sprintf "%s shadows an outer name in %s. Rename it; the graph cannot show two nodes called %s on one wire." n cx.scope n)
      end else Hashtbl.add seen n () in
    let rec go (p : S.t) = match p.node with
      | S.Sym n -> name_ok p n
      | S.Vec (_ :: _ as ps) -> List.iter go ps
      | S.Map [ { S.node = S.Kw "keys"; _ }; { S.node = S.Vec (_ :: _ as ks); _ } ] ->
          List.iter (fun (k : S.t) -> match k.node with
            | S.Sym n -> name_ok k n
            | _ -> ok := false; err k "E_PATTERN" (msg_shape k)) ks
      | _ -> ok := false; err p "E_PATTERN" (msg_shape p) in
    go pat; !ok in
  (* bind [pat] to [v]; names get the path [pfx @ [marker ^ name]] *)
  let rec bind_parts (pat : S.t) (v : v) env pfx marker =
    match pat.node with
    | S.Sym n -> mark (pfx @ [ marker ^ n ]) v; Smap.add n v env
    | S.Vec ps ->
        let pk = pattern_key pat in
        let et =
          if v.ty = Ty.Vec3 then begin
            if List.length ps > 3 then
              err pat "E_PATTERN" (Printf.sprintf "%s needs %d elements; a vec3 has 3." pk (List.length ps));
            Ty.Float
          end else match Ty.elem v.ty with
            | Some e -> e
            | None ->
                if v.ty <> Ty.Any then
                  err pat "E_PATTERN" (Printf.sprintf "%s destructures a list or vec3; got %s." pk (show v.ty));
                Ty.Any in
        (match v.len with
         | Some n when v.ty <> Ty.Vec3 && n < List.length ps ->
             err pat "E_PATTERN" (Printf.sprintf "%s needs %d elements; the list has %d." pk (List.length ps) n)
         | _ -> ());
        let part = { v with ty = et; live_len = false; len = None; fn = None } in
        List.fold_left (fun env p -> bind_parts p part env pfx marker) env ps
    | S.Map [ _; { S.node = S.Vec ks; _ } ] ->
        let pk = pattern_key pat in
        (match v.ty with
         | Ty.Record _ | Ty.Any -> ()
         | t -> err pat "E_PATTERN" (Printf.sprintf "%s destructures a record; got %s." pk (show t)));
        List.fold_left (fun env (k : S.t) -> match k.node with
          | S.Sym n -> bind_parts k (field k v n pk) env pfx marker
          | _ -> env) env ks
    | _ -> env in
  let bind_pat (pat : S.t) v env pfx marker =
    (match pat.node with S.Sym _ -> () | _ -> mark (pfx @ [ marker ^ pattern_key pat ]) v);
    bind_parts pat v env pfx marker in
  let poison_names (pat : S.t) env =
    List.fold_left (fun env n -> Smap.add n poison env) env (pat_names pat) in
  let graph_terms : (string, graph) Hashtbl.t = Hashtbl.create 8 in
  let def_terms : (string, graph) Hashtbl.t = Hashtbl.create 8 in
  let ginfo : (string, v) Hashtbl.t = Hashtbl.create 8 in
  let gstack = ref [] in
  let def_defaults : (string * string, term * v) Hashtbl.t = Hashtbl.create 8 in
  let unbound cx x s =
    let bound = List.map fst (Smap.bindings cx.env) in
    let recent = List.filteri (fun i _ -> i >= List.length bound - 6) bound in
    bad x "E_UNBOUND" (Printf.sprintf "%s is not bound in %s.%s%s" s cx.scope
      (if bound = [] then "" else " Bound here: " ^ String.concat ", " recent ^ ".")
      (Check.suggestion s bound)) in
  let rec infer cx (x : S.t) : term * v =
    incr steps;
    if !steps > max_steps then raise Budget;
    if x.meta <> [] then bypass cx x else plain cx x

  and plain cx (x : S.t) : term * v =
    match x.node with
    | S.Num s ->
        (match float_of_string_opt s with
         | Some f when Float.is_finite f ->
             (match (if String.contains s '.' then None else int_of_string_opt s) with
              | Some n -> (tm x Ty.Int (Lit (Param.Int_value n)), leaf Ty.Int)
              | None -> (tm x Ty.Float (Lit (Param.Float_value f)), leaf Ty.Float))
         | _ -> bad x "E_TYPE" "Nonfinite number.")
    | S.Str s -> (tm x Ty.Text (Text s), leaf Ty.Text)
    | S.Kw k -> bad x "E_KEYWORD" (Printf.sprintf "Keyword :%s has no call to belong to." k)
    | S.Sym s -> symbol cx x s
    | S.Vec cs -> vector cx x cs
    | S.Map cs -> record cx x cs "A record"
    | S.Quote _ -> bad x "E_QUOTE" "Quotes belong in a defmacro template (`…)."
    | S.List [] -> bad x "E_EXPR" "Expected an expression."
    | S.List (h :: args) ->
        (match h.node with
         | S.Sym name -> call cx x name args
         | _ -> bad x "E_CALL" "A call head is a name.")

  and symbol cx x s =
    match s with
    | "t" -> (tm x Ty.Float Time, leaf ~live:true Ty.Float)
    | "pi" -> (tm x Ty.Float (Lit (Param.Float_value Float.pi)), leaf Ty.Float)
    | "true" | "false" -> (tm x Ty.Bool (Lit (Param.Bool_value (s = "true"))), leaf Ty.Bool)
    | "nil" -> (tm x Ty.Geometry Nil, leaf Ty.Geometry)
    | _ ->
        let b, fs = match String.split_on_char '.' s with b :: fs -> (b, fs) | [] -> (s, []) in
        (match Smap.find_opt b cx.env with
         | None -> unbound cx x b
         | Some v0 ->
             let v, _ = List.fold_left (fun (v, p) f -> (field x v f p, p ^ "." ^ f)) (v0, b) fs in
             (tm x v.ty (Ref_binding (b, fs)), if fs = [] then v else { v with fn = None }))

  and vector cx (x : S.t) (cs : S.t list) =
    if List.length cs <> 3 then
      bad x "E_VECTOR" (Printf.sprintf "A vector has 3 components [x y z]; this one has %d." (List.length cs))
    else begin
      let rs = map_seq (infer cx) cs in
      List.iter2 (fun c ((_, (v : v)) : term * v) -> match v.ty with
        | Ty.Int | Ty.Float | Ty.Any -> ()
        | t -> err c "E_TYPE" (Printf.sprintf "Vector components are numbers; got %s." (show t))) cs rs;
      (tm x Ty.Vec3 (Vec (List.map fst rs)), derive Ty.Vec3 (List.map snd rs))
    end

  and record cx (x : S.t) (items : S.t list) what =
    if List.length items mod 2 <> 0 then
      bad x "E_RECORD" (Printf.sprintf "%s is :key value pairs; a key has no value." what)
    else begin
      let fields = ref [] and vs = ref [] and terms = ref [] and ok = ref true in
      List.iter (fun ((k : S.t), value) ->
        match k.node with
        | S.Kw n when Macro.valid_name n ->
            if List.mem_assoc n !fields then
              (ok := false; err k "E_RECORD" (Printf.sprintf "%s gives :%s twice." what n))
            else begin
              let (t, v) = infer cx value in
              no_fn value v.ty (Printf.sprintf "Record field :%s" n);
              fields := (n, v.ty) :: !fields; vs := v :: !vs; terms := (n, t) :: !terms
            end
        | _ -> ok := false;
            err k "E_RECORD" (Printf.sprintf "%s keys are keywords like :size; got %s." what (pattern_key k)))
        (pairs items);
      if not !ok then (tm x Ty.Any Nil, poison)
      else let ty = Ty.Record (List.rev !fields) in
        (tm x ty (Record (List.rev !terms)), derive ty !vs)
    end

  and list_ cx (x : S.t) (args : S.t list) =
    let rs = map_seq (infer cx) args in
    let t = List.fold_left2 (fun t a ((_, (v : v)) : term * v) ->
      no_fn a v.ty "A list element";
      match Ty.join t v.ty with
      | Some j -> j
      | None -> err a "E_TYPE" (Printf.sprintf "List elements share one type; got %s and %s." (show t) (show v.ty)); t)
      Ty.Any args rs in
    let ty = Ty.List t in
    (tm x ty (List_lit (List.map fst rs)), { (derive ty (List.map snd rs)) with len = Some (List.length args) })

  and concat cx (x : S.t) (args : S.t list) =
    let rs = map_seq (infer cx) args in
    let t = List.fold_left2 (fun t a ((_, (v : v)) : term * v) ->
      let vt = match v.ty with Ty.Any -> Ty.List Ty.Any | t -> t in
      if Ty.elem vt = None then (err a "E_TYPE" (Printf.sprintf "concat joins lists; got %s." (show v.ty)); t)
      else match Ty.join t vt with
        | Some j -> j
        | None -> err a "E_TYPE" (Printf.sprintf "concat joins lists of one type; got %s and %s." (show t) (show v.ty)); t)
      (Ty.List Ty.Any) args rs in
    let vs = List.map snd rs in
    let len = List.fold_left (fun a (v : v) -> match a, v.len with Some a, Some n -> Some (a + n) | _ -> None) (Some 0) vs in
    (tm x t (List_op ("concat", List.map fst rs)),
     { (derive t vs) with live_len = List.exists (fun (v : v) -> v.live_len) vs; len })

  and get cx (x : S.t) (args : S.t list) =
    match args with
    | [ r; ({ S.node = S.Kw f; _ }) ] ->
        let (rt, rv) = infer cx r in
        (match rv.ty with
         | Ty.Record _ | Ty.Any -> ()
         | t -> err r "E_TYPE" (Printf.sprintf "get reads a record field; got %s." (show t)));
        let v = field x rv f (pattern_key r) in
        (tm x v.ty (Get (rt, f)), v)
    | _ -> bad x "E_ARGS" "get is (get record :field)."

  and assoc cx (x : S.t) (args : S.t list) =
    match args with
    | r :: (_ :: _ :: _ as rest) when List.length rest mod 2 = 0 ->
        let (rt, rv) = infer cx r in
        (match rv.ty with
         | Ty.Any -> (tm x Ty.Any (Assoc (rt, [])), { poison with live = rv.live })
         | Ty.Record fs0 ->
             let fs = ref fs0 and vs = ref [ rv ] and updates = ref [] in
             List.iter (fun ((k : S.t), value) -> match k.node with
               | S.Kw n ->
                   let (t, v) = infer cx value in
                   no_fn value v.ty (Printf.sprintf "Record field :%s" n);
                   (match List.assoc_opt n !fs with
                    | Some want ->
                        if not (Ty.fits v.ty want) then
                          err value "E_TYPE" (Printf.sprintf "assoc :%s is %s; got %s." n (show want) (show v.ty))
                    | None -> fs := !fs @ [ (n, v.ty) ]);
                   vs := v :: !vs; updates := (n, t) :: !updates
               | _ -> err k "E_ARGS" (Printf.sprintf "assoc keys are keywords; got %s." (pattern_key k)))
               (pairs rest);
             let ty = Ty.Record !fs in
             (tm x ty (Assoc (rt, List.rev !updates)), derive ty !vs)
         | t -> bad x "E_TYPE" (Printf.sprintf "assoc updates a record; got %s." (show t)))
    | _ -> bad x "E_ARGS" "assoc is (assoc record :field value …)."

  and str cx (x : S.t) (args : S.t list) =
    let rs = map_seq (infer cx) args in
    (tm x Ty.Text (Str (List.map fst rs)), derive Ty.Text (List.map snd rs))

  and time_branch cx x test_live ty =
    if test_live && shape_ty ty then
      err x "E_TIME_BRANCH" (Printf.sprintf
        "A branch in %s picks between shapes by t. The network keeps its shape while playing; pick a value instead, for example an if on a size or a colour."
        (path_text cx.path))

  and if_ cx (x : S.t) (args : S.t list) =
    match args with
    | [ c; a; b ] ->
        let (ct, cv) = infer cx c in
        if not (Ty.fits cv.ty Ty.Bool) then
          err c "E_TYPE" (Printf.sprintf "if needs a bool condition, got %s." (show cv.ty));
        let (at, av) = infer cx a and (bt, bv) = infer cx b in
        if not (Ty.fits av.ty bv.ty || Ty.fits bv.ty av.ty) then
          err x "E_TYPE" (Printf.sprintf "Both branches of if must have one type: %s and %s." (show av.ty) (show bv.ty));
        no_fn a av.ty "An if branch"; no_fn b bv.ty "An if branch";
        let ty = match Ty.unify av.ty bv.ty with Some t -> t | None -> av.ty in
        time_branch cx x cv.live ty;
        (tm x ty (If (ct, at, bt)), derive ty [ cv; av; bv ])
    | _ -> bad x "E_NO_ELSE" "if takes a condition, a then and an else."

  and cond cx (x : S.t) h (args : S.t list) =
    let usage = if h = "case" then "case is (case value literal result … :else result)."
      else "cond is (cond test value … :else value)." in
    let scrut, arms_forms = match h, args with
      | "case", s :: rest -> (Some s, rest)
      | "case", [] -> (None, [])
      | _ -> (None, args) in
    if (h = "case" && scrut = None) || arms_forms = [] || List.length arms_forms mod 2 <> 0 then
      bad x "E_COND" usage
    else begin
      let arms = pairs arms_forms in
      let last_test, _ = List.nth arms (List.length arms - 1) in
      if (match last_test.node with S.Kw "else" -> false | _ -> true) then
        bad x "E_NO_ELSE" (Printf.sprintf "%s needs a final :else arm, so it always has a value." h)
      else begin
        let sv = Option.map (infer cx) scrut in
        let vs = ref [] and ty = ref None in
        let test_live = ref (match sv with Some (_, v) -> v.live | None -> false) in
        let n = List.length arms in
        let terms = List.mapi (fun i ((c : S.t), e) ->
          let is_else = (match c.node with S.Kw "else" -> true | _ -> false) in
          if is_else && i < n - 1 then err c "E_COND" (Printf.sprintf ":else is the last arm of %s." h);
          let test =
            if is_else then None
            else match sv with
              | None ->
                  let (t, v) = infer cx c in
                  if not (Ty.fits v.ty Ty.Bool) then
                    err c "E_TYPE" (Printf.sprintf "cond tests are bool; got %s." (show v.ty));
                  if v.live then test_live := true;
                  vs := v :: !vs; Some t
              | Some (_, s) ->
                  (match c.node with
                   | S.Num _ | S.Str _ | S.Sym ("true" | "false") ->
                       let (t, lv) = infer cx c in
                       if not (Ty.fits lv.ty s.ty || Ty.fits s.ty lv.ty) then
                         err c "E_TYPE" (Printf.sprintf "case compares %s with the %s literal %s." (show s.ty) (show lv.ty) (pattern_key c));
                       Some t
                   | _ -> err c "E_CASE" (Printf.sprintf "case matches literal numbers, text or booleans; got %s." (pattern_key c)); None) in
          let (et, ev) = infer cx e in
          no_fn e ev.ty (Printf.sprintf "A %s arm" h);
          vs := ev :: !vs;
          (match !ty with
           | None -> ty := Some ev.ty
           | Some t -> (match Ty.unify t ev.ty with
               | Some j -> ty := Some j
               | None -> err e "E_TYPE" (Printf.sprintf "All arms of %s must have one type: %s and %s." h (show t) (show ev.ty))));
          (c, test, et)) arms in
        let ty = Option.value !ty ~default:Ty.Any in
        time_branch cx x !test_live ty;
        let v = derive ty (!vs @ (match sv with Some (_, s) -> [ s ] | None -> [])) in
        let default = match List.rev terms with (_, _, d) :: _ -> d | [] -> assert false in
        let node = match sv with
          | Some (st, _) -> Case (st, List.filter_map (fun ((c : S.t), t, e) ->
              Option.map (fun _ -> (c, e)) t) terms, default)
          | None -> Cond (List.filter_map (fun (_, t, e) -> Option.map (fun t -> (t, e)) t) terms, default) in
        (tm x ty node, v)
      end
    end

  and body cx (b : S.t) : term * v =
    match b.node, b.meta with
    | S.List ({ S.node = S.Sym "let*"; _ } :: _), [] -> scope cx b cx.path
    | _ -> result cx b cx.path

  and result cx x path =
    let id = path @ [ "@result" ] in
    let (t, v) = binding cx x id in
    no_fn x v.ty (Printf.sprintf "The result of %s" cx.scope);
    (t, v)

  and binding cx (x : S.t) id : term * v =
    let (t, v) =
      if x.meta <> [] then infer cx x
      else match x.node with
        | S.List ({ S.node = S.Sym ("for" | "fold" | "scan" | "sum"); _ } :: _) -> zone cx x id
        | S.List ({ S.node = S.Sym "let*"; _ } :: _) -> scope cx x id
        | _ -> infer cx x in
    mark id v;
    ({ t with path = Some id }, v)

  and scope cx (x : S.t) path : term * v =
    match x.node with
    | S.List [ _; { S.node = S.Vec bs; _ }; res ] when List.length bs mod 2 = 0 ->
        let seen = Hashtbl.create 8 in
        let env = ref cx.env and binds = ref [] in
        List.iter (fun ((pat : S.t), (expr : S.t)) ->
          let ok = check_pat cx pat seen "let*" false in
          let id = path @ [ pattern_key pat ] in
          let inner = { cx with env = !env; path = id; zbody = false } in
          let (t, v) = match pat.node, expr.node, expr.meta with
            | S.Sym n, S.List ({ S.node = S.Sym "fn"; _ } :: _), [] ->
                let (t, v) = mk_fn inner expr id n in
                mark id v; ({ t with path = Some id }, v)
            | _ -> binding inner expr id in
          if cx.zbody && not (List.mem cx.zone v.vary) then invariant := Paths.add id !invariant;
          binds := (pat_ir pat, t) :: !binds;
          env := if ok then bind_pat pat v !env path "" else poison_names pat !env)
          (pairs bs);
        let (rt, rv) = result { cx with env = !env; zbody = false } res path in
        (tm x rv.ty (Let (List.rev !binds, rt)), rv)
    | _ -> bad x "E_LET" "let* needs [name expression …] and one result."

  and zone cx (x : S.t) id : term * v =
    match x.node with
    | S.List ({ S.node = S.Sym h; _ } :: args) ->
        let kind = match h with "for" -> `For | "fold" -> `Fold | "scan" -> `Scan | _ -> `Sum in
        let is_acc = kind = `Fold || kind = `Scan in
        let shape = match args with
          | [ { S.node = S.Vec a; _ }; { S.node = S.Vec i; _ }; b ]
            when is_acc && List.length a mod 2 = 0 && List.length i mod 2 = 0 -> Some (pairs a, pairs i, b)
          | [ { S.node = S.Vec i; _ }; b ] when (not is_acc) && List.length i mod 2 = 0 -> Some ([], pairs i, b)
          | _ -> None in
        (match shape with
         | None -> bad x "E_ZONE" (if is_acc then Printf.sprintf "%s is (%s [acc init] [i collection] body)." h h
             else Printf.sprintf "%s is (%s [i collection …] body)." h h)
         | Some (accs, iters, b) ->
             let seen = Hashtbl.create 8 in
             let ok = List.fold_left (fun ok ((p : S.t), _) -> check_pat cx p seen h true && ok) true (accs @ iters) in
             let ok = ok && (if iters = [] then (err x "E_ZONE" (Printf.sprintf "%s needs at least one [name collection] clause." h); false) else true) in
             let ok = ok && (if is_acc && List.length accs <> 1 then
               (err x "E_ZONE" (Printf.sprintf "%s carries exactly one accumulator: [acc init]. Carry several values in a record: [{:keys [a b]} {:a 0 :b 1}]." h); false) else true) in
             if not ok then
               (tm x Ty.Any Nil, poison)
             else zone_typed cx x id h kind accs iters b)
    | _ -> bad x "E_ZONE" "Expected a loop form."

  and zone_typed cx x id h kind accs iters b =
    incr zones;
    let zid = !zones in
    let init = match accs with
      | [ (p, e) ] ->
          let (t, v) = infer cx e in
          no_fn e v.ty (Printf.sprintf "The %s accumulator" h);
          Some (p, t, v)
      | _ -> None in
    let name = last_segment id in
    let run acc_live =
      let env0 = match init with
        | Some (p, _, iv) ->
            bind_pat p { iv with live = acc_live; vary = union iv.vary [ zid ]; live_len = false }
              cx.env id ":"
        | None -> cx.env in
      let envs = ref env0 and clauses = ref [] and lens = ref [] and outer = ref [] in
      List.iter (fun ((p : S.t), (e : S.t)) ->
        let (ct, cv) = infer { cx with env = !envs } e in
        let et = match Ty.elem cv.ty with
          | Some t -> t
          | None ->
              if cv.ty <> Ty.Any then
                err e "E_TYPE" (Printf.sprintf "%s in %s iterates a list (range, linspace, point_list …); got %s."
                  (pattern_key p) h (show cv.ty));
              Ty.Any in
        if cv.live_len && kind <> `Sum then
          err e "E_TIME_COUNT" (Printf.sprintf
            "The number of iterations of %s depends on t. Loop counts are fixed while playing; animate parameters instead, for example scale a piece to 0." name);
        envs := bind_pat p { cv with ty = et; live_len = false; len = None; fn = None;
                                     vary = union cv.vary [ zid ] } !envs id ":";
        clauses := (pat_ir p, ct) :: !clauses; lens := cv.len :: !lens; outer := cv :: !outer)
        iters;
      let inner = { cx with env = !envs; path = id; scope = cx.scope ^ " › " ^ name;
                            zone = zid; zbody = true } in
      let (bt, bv) = body inner b in
      (List.rev !clauses, List.rev !lens, !outer, bt, bv) in
    let acc_live0 = match init with Some (_, _, iv) -> iv.live | None -> false in
    let (clauses, lens, outer, bt, bv) =
      let ((_, _, _, _, bv) as r) = run acc_live0 in
      if init <> None && bv.live && not acc_live0 then run true else r in
    (* ponytail: literal counts only; a driven count is bounded when Eval runs the zone. *)
    if List.for_all (fun l -> match l with Some n -> n <= max_iterations | None -> false) lens then begin
      let total = List.fold_left (fun a l -> a * Option.get l) 1 lens in
      if total > max_iterations then
        err x "E_ITER_BOUND" (Printf.sprintf "%s runs more than 4,096 iterations (%d)." name total)
    end;
    let acc_ty = match init with Some (_, _, iv) -> Some iv.ty | None -> None in
    (match acc_ty with
     | Some at when not (Ty.fits bt.ty at) ->
         err x "E_ACC_TYPE" (Printf.sprintf "%s body must return the accumulator type %s; it returns %s." h (show at) (show bt.ty))
     | _ -> ());
    if kind = `Sum && not (match bt.ty with Ty.Int | Ty.Float | Ty.Vec3 | Ty.Any -> true | _ -> false) then
      err x "E_TYPE" (Printf.sprintf "sum adds numbers or vec3; the body returns %s." (show bt.ty));
    let ty = match kind, acc_ty with
      | (`For | `Scan), _ -> Ty.List bt.ty
      | `Sum, _ -> (match bt.ty with Ty.Int -> Ty.Int | Ty.Vec3 -> Ty.Vec3 | _ -> Ty.Float)
      | `Fold, Some at -> at
      | `Fold, None -> Ty.Any in
    let init_vs = match init with Some (_, _, iv) -> [ iv ] | None -> [] in
    let ins = outer @ init_vs in
    let v = { (derive ty (bv :: ins)) with
              vary = union (List.filter (( <> ) zid) bv.vary)
                (List.fold_left (fun a (v : v) -> union a v.vary) [] ins) } in
    (tm x ty (Loop { kind; accs = (match init with Some (p, t, _) -> [ (pat_ir p, t) ] | None -> []);
                     clauses; body = bt; zone = id }), v)

  and mk_fn cx (x : S.t) id name : term * v =
    match x.node with
    | S.List [ _; { S.node = S.Vec ps; _ }; fbody ] ->
        let seen = Hashtbl.create 4 in
        let params = List.map (fun (p : S.t) ->
          let pat, ty = match p.node with
            | S.List [ pat; { S.node = S.Sym ":"; _ }; t ] ->
                (match Ty.of_syntax t with
                 | Some ty -> (pat, Some ty)
                 | None -> err p "E_PARAM" (Printf.sprintf "Invalid fn parameter %s. Annotate it as (name : type)." (pattern_key p)); (pat, None))
            | _ -> (p, None) in
          ignore (check_pat cx pat seen "fn" false);
          (pat, ty)) ps in
        let c = { params; body = fbody; ccx = { cx with path = id }; cname = name; cid = id } in
        (* type the body with the declared types, or Any; call sites refine it *)
        let args = List.map (fun ((pat : S.t), ty) ->
          { key = None; aform = pat; aterm = tm pat (Option.value ty ~default:Ty.Any) (Ref_binding ("_", []));
            av = leaf (Option.value ty ~default:Ty.Any) }) params in
        let (bt, bv) = call_closure cx x c args in
        let ir_params = List.map (fun (p, ty) -> (pat_ir p, ty)) params in
        (tm x Ty.Fn (Fn { params = ir_params; body = bt; zone = id }),
         { (leaf ~live:bv.live Ty.Fn) with fn = Some (Closure c) })
    | _ -> bad x "E_FN" "fn is (fn [params] body)."

  and call_closure cx x (c : closure) (args : arg list) : term * v =
    if List.length args <> List.length c.params then
      bad x "E_ARITY" (Printf.sprintf "%s takes %d argument%s; got %d." c.cname
        (List.length c.params) (plural (List.length c.params)) (List.length args))
    else if cx.depth > max_call_depth then bad x "E_DEPTH" "Call depth exceeds 64."
    else begin
      let env = ref c.ccx.env in
      List.iter2 (fun ((pat : S.t), ty) (a : arg) ->
        let v = match ty with
          | Some t ->
              ignore (need a (Printf.sprintf "%s %s" c.cname (pattern_key pat)) t);
              { a.av with ty = Ty.coerce a.av.ty t }
          | None -> a.av in
        env := bind_pat pat v !env c.cid ":") c.params args;
      let inner = { c.ccx with env = !env; path = c.cid; scope = c.ccx.scope ^ " › " ^ c.cname;
                               depth = cx.depth + 1; zbody = false;
                               stack = List.sort_uniq compare (cx.stack @ c.ccx.stack) } in
      let (bt, bv) = body inner c.body in
      (bt, { bv with fn = None })
    end

  and fn_arg cx (x : S.t) : term * v =
    let (t, v) = match x.node with
      | S.Sym s when x.meta = [] && (not (String.contains s '.')) && (not (Smap.mem s cx.env)) && not (reserved s) ->
          (match resolve_head cx s with
           | `Def _ -> (tm x Ty.Fn (Fn_ref s), { (leaf Ty.Fn) with fn = Some (Def_fn s) })
           | `Op o -> (tm x Ty.Fn (Fn_ref s), { (leaf Ty.Fn) with fn = Some (Op_fn o.oname) })
           | `Kind k -> (tm x Ty.Fn (Fn_ref s), { (leaf Ty.Fn) with fn = Some (Kind_fn k) })
           | `Macro _ -> bad x "E_MACRO_AS_VALUE" (Printf.sprintf "%s is a macro; a macro is not a function value. Wrap it: (fn [a] (%s a))." s s)
           | `Missing _ -> infer cx x)
      | _ -> infer cx x in
    (t, v)

  and fn_value cx x what =
    let (t, v) = fn_arg cx x in
    if v.ty <> Ty.Fn && v.ty <> Ty.Any then
      (err x "E_TYPE" (Printf.sprintf "%s expects a function (fn, a defn or an operator name); got %s." what (show v.ty)));
    (t, v)

  and call_value cx x (f : v) (args : arg list) : term * v =
    match f.fn with
    | None -> (tm x Ty.Any Nil, { (derive Ty.Any (f :: List.map (fun a -> a.av) args)) with fn = None })
    | Some (Closure c) -> call_closure cx x c args
    | Some (Def_fn n) -> apply_def cx x (Hashtbl.find sigs n) args
    | Some (Op_fn n) -> apply_op cx x (Hashtbl.find op_table n) args
    | Some (Kind_fn k) -> apply_kind cx x k args

  and dummy x ty = tm x ty (Ref_binding ("_", []))
  and value_arg x (v : v) = { key = None; aform = x; aterm = dummy x v.ty; av = v }

  and hof cx (x : S.t) h (args : S.t list) =
    let lo, hi = match h with "map" -> (2, 4) | "filter" | "sort-by" -> (2, 2) | _ -> (3, 3) in
    let n = List.length args in
    if n < lo || n > hi then
      bad x "E_ARITY" (match h with
        | "map" -> "map is (map f list …) with 1–3 lists."
        | "filter" -> "filter is (filter pred list)."
        | "reduce" -> "reduce is (reduce f init list)."
        | _ -> "sort-by is (sort-by key list).")
    else begin
      let f_form = List.hd args in
      let (ft, fv) = fn_value cx f_form h in
      let init = if h = "reduce" then Some (infer cx (List.nth args 1)) else None in
      (match init with Some (_, iv) -> no_fn x iv.ty "The reduce accumulator" | None -> ());
      let list_forms = List.filteri (fun i _ -> i >= (if h = "reduce" then 2 else 1)) args in
      let lists = List.map (fun (a : S.t) ->
        let (t, v) = infer cx a in
        if Ty.elem v.ty = None && v.ty <> Ty.Any then
          err a "E_TYPE" (Printf.sprintf "%s iterates a list; got %s." h (show v.ty));
        (a, t, v)) list_forms in
      let elem (_, _, (v : v)) = { v with ty = Option.value (Ty.elem v.ty) ~default:Ty.Any;
                                          live_len = false; len = None; fn = None } in
      let call_args = match init, lists with
        | Some (_, iv), l :: _ -> [ value_arg x iv; value_arg x (elem l) ]
        | _ -> List.map (fun l -> value_arg x (elem l)) lists in
      let (_, rv) = call_value cx x fv call_args in
      let l0 = match lists with (_, _, v) :: _ -> v | [] -> poison in
      let list_vs = List.map (fun (_, _, v) -> v) lists in
      let any_len = List.exists (fun (v : v) -> v.live_len) list_vs in
      let terms = ft :: (match init with Some (t, _) -> [ t ] | None -> []) @ List.map (fun (_, t, _) -> t) lists in
      let kind, ty, live_len =
        match h with
        | "map" -> no_fn x rv.ty "The map result"; (`Map, Ty.List rv.ty, any_len)
        | "filter" ->
            if not (Ty.fits rv.ty Ty.Bool) then
              err x "E_TYPE" (Printf.sprintf "filter's predicate returns bool; it returns %s." (show rv.ty));
            (`Filter, l0.ty, any_len || rv.live)
        | "sort-by" ->
            if not (match rv.ty with Ty.Int | Ty.Float | Ty.Bool | Ty.Any -> true | _ -> false) then
              err x "E_TYPE" (Printf.sprintf "sort-by's key returns a number; it returns %s." (show rv.ty));
            (`Sort_by, l0.ty, any_len)
        | _ ->
            let it = match init with Some (_, iv) -> iv.ty | None -> Ty.Any in
            no_fn x rv.ty "The reduce result";
            if not (Ty.fits rv.ty it) then
              err x "E_TYPE" (Printf.sprintf "reduce's function must return the accumulator type %s; it returns %s." (show it) (show rv.ty));
            (`Reduce, it, false) in
      let v = derive ty (fv :: rv :: list_vs @ (match init with Some (_, iv) -> [ iv ] | None -> [])) in
      (tm x ty (Hof (kind, terms)), { v with live_len; live = v.live || live_len })
    end

  and ref_ cx (x : S.t) (args : S.t list) =
    match args with
    | ({ S.node = S.Sym g; _ } as gf) :: rest ->
        if not (Hashtbl.mem gsigs g) then bad gf "E_UNKNOWN_GRAPH" (Printf.sprintf "Unknown graph reference: %s." g)
        else if cx.in_def then
          bad x "E_REF_IN_DEF" "Reusable functions cannot capture project graphs; add an explicit parameter."
        else begin
          let sg = Hashtbl.find gsigs g in
          let gv = graph_info x g in
          let overrides = ref [] and vs = ref [ gv ] in
          let rec go = function
            | ({ S.node = S.Kw k; _ } as kf) :: value :: more ->
                (match List.find_opt (fun (n, _, _) -> n = k) sg.sparams with
                 | None ->
                     err kf "E_UNKNOWN_PARAM" (Printf.sprintf "Graph %s has no input :%s. Inputs: %s." g k
                       (if sg.sparams = [] then "none" else String.concat ", " (List.map (fun (n, _, _) -> n) sg.sparams)))
                 | Some (_, ty, _) ->
                     let (t, v) = infer cx value in
                     no_fn value v.ty (Printf.sprintf "Input :%s of %s" k g);
                     ignore (need (value_arg value v) (Printf.sprintf ":%s of %s" k g) ty);
                     overrides := (k, t) :: !overrides; vs := v :: !vs);
                go more
            | [] -> ()
            | y :: _ -> err y "E_ARGS" "ref takes a graph name, then :input value pairs." in
          go rest;
          let ty = context_ty sg.sctx in
          (tm x ty (Graph_ref { graph = g; inputs = List.rev !overrides }), { (derive ty !vs) with groups = [] })
        end
    | _ -> bad x "E_ARGS" "ref takes a graph name, then :input value pairs."

  and args_of cx fn_slot (forms : S.t list) : arg list =
    let rec go i acc = function
      | [] -> List.rev acc
      | ({ S.node = S.Kw k; _ } as kf) :: value :: rest ->
          let (t, v) = if fn_slot None (Some k) then fn_arg cx value else infer cx value in
          go i ({ key = Some k; aform = kf; aterm = t; av = v } :: acc) rest
      | ({ S.node = S.Kw k; _ } as kf) :: [] ->
          err kf "E_MISSING_VALUE" (Printf.sprintf ":%s has no value" k); List.rev acc
      | y :: rest ->
          let (t, v) = if fn_slot (Some i) None then fn_arg cx y else infer cx y in
          go (i + 1) ({ key = None; aform = y; aterm = t; av = v } :: acc) rest in
    go 0 [] forms

  and call cx (x : S.t) name args : term * v =
    match name with
    | "let*" -> scope cx x (cx.path @ [ "~let" ])
    | "for" | "fold" | "scan" | "sum" -> zone cx x (cx.path @ [ "~" ^ name ])
    | "fn" -> mk_fn cx x (cx.path @ [ "~fn" ]) "fn"
    | "if" -> if_ cx x args
    | "cond" | "case" -> cond cx x name args
    | "ref" -> ref_ cx x args
    | "values" -> record cx x args "values"
    | "list" -> list_ cx x args
    | "concat" -> concat cx x args
    | "str" -> str cx x args
    | "get" -> get cx x args
    | "assoc" -> assoc cx x args
    | "map" | "filter" | "reduce" | "sort-by" -> hof cx x name args
    | "quote" | "quasiquote" | "unquote" | "unquote-splicing" ->
        bad x "E_QUOTE" (Printf.sprintf "%s belongs in a defmacro template (`…)." name)
    | "workspace" | "graph" | "defn" | "defmacro" ->
        bad x "E_FORM" (Printf.sprintf "%s is a top-level form of a workspace." name)
    | _ ->
        let local = Smap.find_opt name cx.env in
        (match local with
         | Some lv when lv.ty = Ty.Fn || lv.ty = Ty.Any ->
             if List.exists is_kw args then
               bad x "E_ARGS" (Printf.sprintf "%s is a local function; it takes positional arguments only." name)
             else begin
               let a = args_of cx (fun _ _ -> false) args in
               let (_, rv) = call_value cx x lv a in
               (tm x rv.ty (Call_fn { fn = name; args = List.map (fun a -> a.aterm) a }), rv)
             end
         | _ ->
             (match resolve_head cx name with
              | `Missing (code, msg) ->
                  (match local with
                   | Some lv -> bad x "E_TYPE" (Printf.sprintf "%s is %s, not a function." name (show lv.ty))
                   | None ->
                       let prefix = "Unknown node " ^ name ^ "." in
                       if code = "E_UNKNOWN_KIND" && String.starts_with ~prefix msg then
                         bad x code (Printf.sprintf "Unknown operator “%s”.%s" name
                           (String.sub msg (String.length prefix) (String.length msg - String.length prefix)))
                       else bad x code msg)
              | `Macro _ ->
                  (match Macro.expand (List.rev !macro_forms) x with
                   | Error d -> diags := d :: !diags; (tm x Ty.Any Nil, poison)
                   | Ok y ->
                       let (t, v) = infer cx y in
                       (tm x t.ty (Expanded { macro = name; body = t }), v))
              | `Def d ->
                  let fn_slot pos key =
                    let p = match pos, key with
                      | Some i, _ -> List.nth_opt d.sparams i
                      | None, Some k -> List.find_opt (fun (n, _, _) -> n = k) d.sparams
                      | _ -> None in
                    (match p with Some (_, Ty.Fn, _) -> true | _ -> false) in
                  apply_def cx x d (args_of cx fn_slot args)
              | `Op o -> apply_op cx x o (args_of cx (fun _ _ -> false) args)
              | `Kind k -> apply_kind cx x k (args_of cx (fun _ _ -> false) args)))

  and apply_op cx x (o : op) (args : arg list) : term * v =
    if o.octx <> Value && o.octx <> cx.ctx then
      bad x "E_WRONG_CONTEXT" (Printf.sprintf "%s belongs to %s; it cannot run in %s. Pass data through a typed input or ref."
        o.oname (context_name o.octx) (context_name cx.ctx))
    else begin
      let pos = List.filter (fun a -> a.key = None) args in
      let kws = List.filter (fun a -> a.key <> None) args in
      let slots = o.pos @ o.opt in
      let np = List.length pos in
      if o.rest = None && (np < List.length o.pos || np > List.length slots) then
        bad x "E_ARITY" (Printf.sprintf "%s takes %d%s positional input%s%s; got %d." o.oname (List.length o.pos)
          (if o.opt <> [] then "–" ^ string_of_int (List.length slots) else "")
          (plural (List.length slots))
          (if o.pos <> [] then " (" ^ String.concat ", " (List.map fst o.pos) ^ ")" else "") np)
      else begin
        let nfix = if o.rest <> None then List.length o.pos else List.length slots in
        let named = ref [] and ts = ref [] in
        List.iteri (fun i a ->
          if i < nfix then begin
            let sname, sty = List.nth slots i in
            ts := a.av.ty :: !ts;
            if not (o.any_num && (a.av.ty = Ty.Vec3 || a.av.ty = Ty.Int || a.av.ty = Ty.Float)) then
              ignore (need a (Printf.sprintf "%s %s" o.oname sname) sty);
            named := (sname, a.aterm) :: !named
          end else begin
            let rname, rty = Option.get o.rest in
            (match Ty.elem a.av.ty with
             | Some e when Ty.fits e rty ->
                 if a.av.live_len && shape_ty rty then
                   err a.aform "E_TIME_COUNT" (Printf.sprintf
                     "The list passed to %s changes length with t. The network keeps its shape while playing; animate parameters instead, for example scale a piece to 0." o.oname)
             | _ -> ignore (need a (Printf.sprintf "%s %s" o.oname rname) rty));
            named := (rname, a.aterm) :: !named
          end) pos;
        let seen = Hashtbl.create 4 in
        List.iter (fun a ->
          let k = Option.get a.key in
          match List.assoc_opt k o.kw with
          | None ->
              err a.aform "E_UNKNOWN_PARAM" (Printf.sprintf "%s has no parameter :%s.%s" o.oname k
                (if o.kw = [] then "" else " Parameters: " ^ String.concat " " (List.map (fun (n, _) -> ":" ^ n) o.kw) ^ "."))
          | Some want ->
              if Hashtbl.mem seen k then err a.aform "E_DUPLICATE_PARAM" (Printf.sprintf ":%s is given twice" k)
              else begin
                Hashtbl.add seen k ();
                ignore (need a (Printf.sprintf "%s :%s" o.oname k) want);
                named := (k, a.aterm) :: !named
              end) kws;
        literal_checks x o args;
        let ty = o.out (List.rev !ts) in
        let avs = List.map (fun a -> a.av) args in
        let nth_live_len i = match List.nth_opt pos i with Some a -> a.av.live_len | None -> false in
        let live_len = match o.oname with
          | "range" | "linspace" -> List.exists (fun (v : v) -> v.live) avs
          | "take" | "drop" -> (match List.nth_opt pos 0 with Some a -> a.av.live | None -> false) || nth_live_len 1
          | "rest" | "reverse" -> nth_live_len 0
          | _ -> false in
        let int_of a = match a.aterm.node with Lit (Param.Int_value n) -> Some n | _ -> None in
        let len = match o.oname, List.map int_of pos with
          | "range", [ Some n ] -> Some (max 0 n)
          | "range", [ Some a; Some b ] -> Some (max 0 (b - a))
          | "linspace", [ _; _; Some n ] -> Some (max 0 n)
          | _ -> None in
        let v = { (derive ty avs) with live_len; len } in
        (tm x ty (Op { op = o.oname; args = List.rev !named }), v)
      end
    end

  and literal_checks x (o : op) (args : arg list) =
    let pos = List.filter (fun a -> a.key = None) args in
    let int_of a = match a.aterm.node with Lit (Param.Int_value n) -> Some n | _ -> None in
    let num_of a = match a.aterm.node with
      | Lit (Param.Int_value n) -> Some (float_of_int n) | Lit (Param.Float_value f) -> Some f | _ -> None in
    match o.oname with
    | "range" ->
        (match List.map int_of pos with
         | [ Some n ] when n > max_iterations -> err x "E_ITER_BOUND" (Printf.sprintf "range 0‥%d exceeds 4,096 iterations." n)
         | [ Some a; Some b ] when b - a > max_iterations ->
             err x "E_ITER_BOUND" (Printf.sprintf "range %d‥%d exceeds 4,096 iterations." a b)
         | _ -> ())
    | "linspace" ->
        (match List.map int_of pos with
         | [ _; _; Some n ] when n > max_iterations -> err x "E_ITER_BOUND" "linspace exceeds 4,096 values."
         | _ -> ())
    | "ui/split" | "ui/split-at" ->
        (match pos with
         | { aterm = { node = Text axis; _ }; _ } :: _ when axis <> "horizontal" && axis <> "vertical" ->
             err x "E_RANGE" "Split axis is horizontal or vertical."
         | _ -> ());
        (match o.oname, pos with
         | "ui/split-at", _ :: r :: _ ->
             (match num_of r with Some n when n < 0.1 || n > 0.9 -> err x "E_RANGE" "Split ratio is 0.1–0.9." | _ -> ())
         | _ -> ())
    | _ -> ()

  and validate (p : Check.parameter) (a : arg) =
    let want = param_ty p and have = a.av.ty in
    let report sev code msg = add sev a.aform code msg in
    if have <> Ty.Any then begin
      if not (Ty.fits have want) then
        err a.aform "E_TYPE" (Printf.sprintf ":%s takes %s, but this is %s" p.name (show want) (show have))
      else match want, a.aterm.node with
        | Ty.Color, Text s ->
            if not (hex_colour s) then
              err a.aform "E_TYPE" (Printf.sprintf ":%s is a colour: write \"#rrggbb\" or a vec3, not %S" p.name s)
        | Ty.Color, _ ->
            if have = Ty.Vec3 then
              Check.validate_parameter report { p with ty = Some Port_type.Vec3 } (to_check a.aterm)
        | Ty.Vec3, _ when have <> Ty.Vec3 -> ()
        | Ty.Text, Text _ -> Check.validate_parameter report p (to_check a.aterm)
        | Ty.Text, _ -> ()
        | _ -> Check.validate_parameter report p (to_check a.aterm)
    end

  and apply_kind _cx x (k : Check.kind) (args : arg list) : term * v =
    let rest_kind = List.exists (fun (s : Check.slot) -> s.rest) k.slots in
    let short = Check.short k.qualified in
    let nslots = List.length k.slots in
    let seen = Hashtbl.create 8 in
    let out = ref [] and npos = ref 0 and writes = ref [] in
    let groups_in = List.fold_left (fun g a -> union g a.av.groups) [] args in
    let slot_ty = if k.context = Context.World then Ty.World else Ty.Geometry in
    let slot_arg a sname =
      if Ty.fits a.av.ty slot_ty then ()
      else if rest_kind && (match a.av.ty with Ty.List e -> Ty.fits e Ty.Geometry | _ -> false) then begin
        if a.av.live_len then
          err a.aform "E_TIME_COUNT" (Printf.sprintf
            "The list passed to %s changes length with t. The network keeps its shape while playing; animate parameters instead, for example scale a piece to 0." k.qualified)
      end else err a.aform "E_TYPE" (Printf.sprintf "Input %s takes %s" sname (show slot_ty)) in
    List.iter (fun a ->
      match a.key with
      | None ->
          let idx = !npos in
          incr npos;
          if rest_kind then (slot_arg a "input"; out := ("input", a.aterm) :: !out)
          else if idx >= nslots then
            err a.aform "E_EXTRA_POSITIONAL" (Printf.sprintf "%s takes %d geometry input%s; this one is extra" short nslots (plural nslots))
          else begin
            let s = List.nth k.slots idx in
            Hashtbl.replace seen s.name ();
            slot_arg a s.name; out := (s.name, a.aterm) :: !out
          end
      | Some n ->
          if Hashtbl.mem seen n then err a.aform "E_DUPLICATE_PARAM" (Printf.sprintf ":%s is given twice" n)
          else begin
            Hashtbl.add seen n ();
            match List.find_opt (fun (s : Check.slot) -> s.name = n) k.slots,
                  List.find_opt (fun (p : Check.parameter) -> p.name = n) k.parameters with
            | Some _, _ -> slot_arg a n; out := (n, a.aterm) :: !out
            | None, Some p ->
                validate p a;
                (match a.aterm.node with
                 | Text s when group_reader p && s <> "" && not (List.mem s groups_in) ->
                     add Diagnostic.Warning a.aform "W_UNKNOWN_GROUP"
                       (Printf.sprintf "Group %S is not made by any node upstream of %s." s short)
                 | Text s when group_writer k p -> writes := s :: !writes
                 | _ -> ());
                out := (n, a.aterm) :: !out
            | None, None ->
                let names = List.map (fun (s : Check.slot) -> s.name) k.slots
                  @ List.map (fun (p : Check.parameter) -> p.name) k.parameters in
                err a.aform "E_UNKNOWN_PARAM" (Printf.sprintf "%s has no parameter :%s.%s" short n (Check.suggestion n names))
          end) args;
    if not rest_kind then
      List.iter (fun (s : Check.slot) ->
        if s.required && not (Hashtbl.mem seen s.name) then
          err x "E_MISSING_INPUT" (Printf.sprintf "%s needs its %s input" short s.name)) k.slots;
    let ty = kind_out k in
    let v = { (derive ty (List.map (fun a -> a.av) args)) with groups = union groups_in !writes } in
    (tm x ty (Call { kind = k.qualified; args = List.rev !out }), v)

  and def_default (d : signature) pname : (term * v) option =
    match Hashtbl.find_opt def_defaults (d.sname, pname) with
    | Some r -> Some r
    | None ->
        (match List.find_opt (fun (n, _, _) -> n = pname) d.sparams with
         | Some (_, ty, Some df) ->
             let cx = { env = Smap.empty; ctx = d.sctx; scope = "ƒ " ^ d.sname; path = [ "def:" ^ d.sname; ":" ^ pname ];
                        in_def = true; stack = [ d.sname ]; depth = 0; zone = 0; zbody = false } in
             let (t, v) = infer cx df in
             if not (Ty.fits v.ty ty) then
               err df "E_TYPE" (Printf.sprintf "The default of %s input %s is %s; it is declared %s." d.sname pname (show v.ty) (show ty));
             Hashtbl.replace def_defaults (d.sname, pname) (t, v);
             Some (t, v)
         | _ -> None)

  and apply_def cx x (d : signature) (args : arg list) : term * v =
    if d.sctx <> Value && d.sctx <> cx.ctx then
      bad x "E_WRONG_CONTEXT" (Printf.sprintf "%s belongs to %s; it cannot run in %s." d.sname (context_name d.sctx) (context_name cx.ctx))
    else if List.mem d.sname cx.stack then
      bad x "E_RECURSION" (Printf.sprintf "Recursive call: %s. Use fold for repetition."
        (String.concat " → " (List.rev (d.sname :: cx.stack))))
    else if cx.depth > max_call_depth then bad x "E_DEPTH" "Call depth exceeds 64."
    else begin
      let pos = List.filter (fun a -> a.key = None) args in
      let np = List.length pos and nparams = List.length d.sparams in
      let ok = ref true in
      if np > nparams then
        (ok := false; err x "E_ARITY" (Printf.sprintf "%s takes %d input%s; got %d positional." d.sname nparams (plural nparams) np));
      List.iter (fun a -> match a.key with
        | Some k when not (List.exists (fun (n, _, _) -> n = k) d.sparams) ->
            ok := false;
            err a.aform "E_UNKNOWN_PARAM" (Printf.sprintf "%s has no input :%s. Inputs: %s." d.sname k
              (String.concat ", " (List.map (fun (n, _, _) -> n) d.sparams)))
        | _ -> ()) args;
      if not !ok then (tm x Ty.Any Nil, poison)
      else begin
        let env = ref Smap.empty and terms = ref [] in
        List.iteri (fun i (pname, pty, _) ->
          let by_pos = List.nth_opt pos i and by_key = List.find_opt (fun a -> a.key = Some pname) args in
          (match by_pos, by_key with
           | Some _, Some k -> err k.aform "E_DUPLICATE_PARAM" (Printf.sprintf "%s input %s is given twice." d.sname pname)
           | _ -> ());
          let given = match by_pos with Some a -> Some a | None -> by_key in
          let t, v = match given with
            | Some a ->
                ignore (need a (Printf.sprintf "%s :%s" d.sname pname) pty);
                (a.aterm, { a.av with ty = Ty.coerce a.av.ty pty })
            | None ->
                (match def_default d pname with
                 | Some (t, v) -> (t, v)
                 | None ->
                     err x "E_ARGS" (Printf.sprintf "%s needs :%s (%s)." d.sname pname (show pty));
                     (tm x pty Nil, leaf pty)) in
          env := Smap.add pname v !env;
          terms := t :: !terms) d.sparams;
        let inner = { env = !env; ctx = d.sctx; stack = d.sname :: cx.stack; scope = "ƒ " ^ d.sname;
                      path = [ "def:" ^ d.sname ]; in_def = true; depth = cx.depth + 1; zone = 0; zbody = false } in
        let (_, bv) = body inner d.sbody in
        (tm x bv.ty (Call_fn { fn = d.sname; args = List.rev !terms }), { bv with fn = None })
      end
    end

  and bypass cx (x : S.t) : term * v =
    match List.filter (( <> ) "bypass") x.meta with
    | m :: _ -> bad x "E_META" (Printf.sprintf "Unknown metadata ^:%s. The only metadata is ^:bypass." m)
    | [] ->
        let bare = { x with meta = [] } in
        (match x.node with
         | S.List ({ S.node = S.Sym h; _ } :: args)
           when (not (List.mem h special)) && not (Hashtbl.mem macro_tbl h) ->
             let rec first i = function
               | [] -> None
               | ({ S.node = S.Kw _; _ }) :: _ :: rest -> first (i + 1) rest
               | _ :: _ -> Some i in
             (match first 0 args with
              | None -> bad x "E_BYPASS" (Printf.sprintf "can't bypass %s: it has no positional input to pass through." h)
              | Some i ->
                  let (t, v) = plain cx bare in
                  let entries = match t.node with
                    | Call { args; _ } | Op { args; _ } -> List.map snd args
                    | Call_fn { args; _ } -> args
                    | _ -> [] in
                  (match List.nth_opt entries i with
                   | Some a ->
                       if not (Ty.fits a.ty v.ty) || Ty.has_fn a.ty then
                         err x "E_BYPASS" (Printf.sprintf "can't bypass %s: its input is %s but it returns %s." h (show a.ty) (show v.ty));
                       (tm x v.ty (Bypass t), v)
                   | _ -> (tm x v.ty (Bypass t), v)))
         | _ ->
             bad x "E_BYPASS" (Printf.sprintf "can't bypass %s: only operator and function calls pass an input through."
               (match x.node with S.List ({ S.node = S.Sym h; _ } :: _) -> h | _ -> pattern_key { x with meta = [] })))

  and graph_info x name : v =
    match Hashtbl.find_opt ginfo name with
    | Some v -> v
    | None ->
        if List.mem name !gstack then begin
          err x "E_GRAPH_CYCLE" (Printf.sprintf "Graph cycle: %s." (String.concat " → " (List.rev (name :: !gstack))));
          leaf (context_ty (Hashtbl.find gsigs name).sctx)
        end else begin
          let sg = Hashtbl.find gsigs name in
          gstack := name :: !gstack;
          let cx0 = { env = Smap.empty; ctx = sg.sctx; scope = name; path = [ name ]; in_def = false;
                      stack = []; depth = 0; zone = 0; zbody = false } in
          let env = ref Smap.empty and inputs = ref [] in
          List.iter (fun (n, ty, df) ->
            let cx = { cx0 with env = !env } in
            let dt, dv = match df with
              | Some d ->
                  let (t, v) = infer cx d in
                  if not (Ty.fits v.ty ty) then
                    err d "E_TYPE" (Printf.sprintf "The default of %s input %s is %s; it is declared %s." name n (show v.ty) (show ty));
                  (Some t, v)
              | None -> (None, leaf ty) in
            let v = { (leaf ~live:dv.live ty) with vary = [] } in
            mark [ name; ":" ^ n ] v;
            env := Smap.add n v !env; inputs := (n, ty, dt) :: !inputs) sg.sparams;
          let (bt, bv) = body { cx0 with env = !env } sg.sbody in
          let want = context_ty sg.sctx in
          if not (Ty.fits bv.ty want) then
            err sg.sbody "E_TYPE" (Printf.sprintf "%s must return %s, but its result is %s." name (show want) (show bv.ty));
          gstack := List.tl !gstack;
          Hashtbl.replace graph_terms name { name; context = sg.sctx; inputs = List.rev !inputs; body = bt; form = sg.sform };
          let v = { (leaf ~live:bv.live want) with groups = [] } in
          Hashtbl.replace ginfo name v;
          v
        end in
  let items = ref [] in
  let parse_sig head n (f : S.t) : signature option =
    let shape_error () =
      err f "E_SHAPE" (Printf.sprintf "Invalid shape for %s: expected (%s %s :context ctx [params] body)." n head n); None in
    match f.node with
    | S.List (_ :: _ :: { S.node = S.Kw "context"; _ } :: { S.node = S.Sym cname; _ } :: rest) ->
        (match context_of_name cname with
         | None ->
             err f "E_CONTEXT_UNKNOWN" (Printf.sprintf "Unknown context %s. Known contexts: sop, value, scene, world, settings, editor." cname);
             None
         | Some ctx ->
             let shape = match rest with
               | [ b ] when head = "graph" -> Some ([], b)
               | [ { S.node = S.Vec ps; _ }; b ] -> Some (ps, b)
               | _ -> None in
             (match shape with
              | None ->
                  if head = "defn" && List.length rest = 1 then
                    (err f "E_SHAPE" (Printf.sprintf "defn %s needs a parameter vector." n); None)
                  else shape_error ()
              | Some (ps, b) ->
                  let used = Hashtbl.create 4 in
                  let sparams = List.filter_map (fun (p : S.t) ->
                    match p.node with
                    | S.List ({ S.node = S.Sym pn; _ } :: { S.node = S.Sym ":"; _ } :: tyf :: dflt)
                      when List.length dflt <= 1 && Macro.valid_name pn && not (reserved pn) && not (Hashtbl.mem used pn) ->
                        (match Ty.of_syntax tyf with
                         | None ->
                             err p "E_PARAM" (Printf.sprintf "Invalid parameter in %s. Each is (name : type default?)." n); None
                         | Some ty ->
                             Hashtbl.add used pn ();
                             let df = match dflt with [ d ] -> Some d | _ -> None in
                             if Ty.has_fn ty && (ty <> Ty.Fn || head = "graph") then begin
                               err p "E_FN_ESCAPES" (Printf.sprintf
                                 "%s input %s: a function value cannot be stored or returned (E_FN_ESCAPES); %s." n pn
                                 (if head = "graph" then "graph inputs are data" else "only a defn input may have type fn"));
                               None
                             end else if ty = Ty.Fn && df <> None then begin
                               err p "E_PARAM" (Printf.sprintf "%s input %s: a fn input has no default; callers pass a function." n pn); None
                             end else if head = "graph" && df = None then begin
                               err p "E_INPUT_DEFAULT" (Printf.sprintf "Graph input %s of %s needs a default, so the graph runs on its own." pn n); None
                             end else Some (pn, ty, df))
                    | _ ->
                        err p "E_PARAM" (Printf.sprintf "Invalid parameter in %s. Each is (name : type default?)." n); None) ps in
                  Some { sname = n; sctx = ctx; sparams; sbody = b; sform = f }))
    | _ -> shape_error () in
  let driver (ws : S.t) wname children =
    ignore wname;
    List.iter (fun (f : S.t) -> match f.node with
      | S.List ({ S.node = S.Sym (("graph" | "defn" | "defmacro") as head); _ } :: { S.node = S.Sym n; _ } :: _) ->
          if not (Macro.valid_name n) || reserved n || Hashtbl.mem names n || Hashtbl.mem op_table n then
            err f "E_NAME" (Printf.sprintf "Invalid, reserved or duplicate name: %s." n)
          else (Hashtbl.add names n (); items := (head, n, f) :: !items)
      | _ -> err f "E_FORM" "Workspace children are graph, defn and defmacro forms.") children;
    let items = List.rev !items in
    List.iter (fun (head, n, (f : S.t)) ->
      if head = "defmacro" then begin
        diags := List.rev_append (Macro.check ~known ~value_op f) !diags;
        match Macro.params f with
        | Ok _ -> Hashtbl.replace macro_tbl n f; macro_forms := f :: !macro_forms
        | Error _ -> ()
      end) items;
    let graph_order = ref [] and def_order = ref [] in
    List.iter (fun (head, n, f) -> if head <> "defmacro" then
      match parse_sig head n f with
      | Some sg ->
          if head = "graph" then (Hashtbl.replace gsigs n sg; graph_order := n :: !graph_order)
          else (Hashtbl.replace sigs n sg; def_order := n :: !def_order)
      | None -> ()) items;
    let graph_order = List.rev !graph_order and def_order = List.rev !def_order in
    List.iter (fun n ->
      let d = Hashtbl.find sigs n in
      let env = List.fold_left (fun env (pn, ty, _) -> Smap.add pn (leaf ty) env) Smap.empty d.sparams in
      let cx = { env; ctx = d.sctx; scope = "ƒ " ^ n; path = [ "def:" ^ n ]; in_def = true;
                 stack = [ n ]; depth = 0; zone = 0; zbody = false } in
      let inputs = List.map (fun (pn, ty, _) ->
        (pn, ty, Option.map fst (def_default d pn))) d.sparams in
      let (bt, _) = body cx d.sbody in
      Hashtbl.replace def_terms n { name = n; context = d.sctx; inputs; body = bt; form = d.sform }) def_order;
    List.iter (fun n -> ignore (graph_info (Hashtbl.find gsigs n).sform n)) graph_order;
    if graph_order = [] && not (List.exists (fun (h, _, _) -> h = "graph") items) then
      err ws "E_NO_GRAPH" "A workspace needs at least one graph.";
    (graph_order, def_order) in
  let outcome =
    match forms with
    | [ ({ S.node = S.List ({ S.node = S.Sym "workspace"; _ } :: { S.node = S.Sym wname; _ } :: children); _ } as ws) ]
      when Macro.valid_name wname ->
        (try
           let (go, dos) = driver ws wname children in
           Some (wname, ws, go, dos)
         with Budget ->
           err ws "E_BUDGET" "The workspace is too large to check: call-site typing exceeded its budget. Reduce nested function calls.";
           None)
    | [] -> diags := [ Diagnostic.error ~code:"E_NO_WORKSPACE" "Expected (workspace name …)." ]; None
    | [ f ] -> err f "E_WORKSPACE" "Expected (workspace name …)."; None
    | _ :: f :: _ -> err f "E_ONE_WORKSPACE" "A file holds one workspace form."; None in
  let seen = Hashtbl.create 16 in
  let diagnostics = List.filter (fun (d : Diagnostic.t) ->
    let key = (d.code, d.span, d.message) in
    if Hashtbl.mem seen key then false else (Hashtbl.add seen key (); true)) (List.rev !diags) in
  let has_error = List.exists (fun (d : Diagnostic.t) -> d.severity = Diagnostic.Error) diagnostics in
  match outcome with
  | Some (wname, _, go, dos) when not has_error ->
      let get tbl = List.filter_map (Hashtbl.find_opt tbl) in
      (Some { name = wname; graphs = get graph_terms go; defs = get def_terms dos;
              macros = List.rev !macro_forms; source = forms; live = !live; invariant = !invariant },
       diagnostics)
  | _ -> (None, diagnostics)

let name_taken s =
  reserved s || Symbol.reserved s || Hashtbl.mem op_table s || Hashtbl.mem op_table ("value/" ^ s)
  || List.mem s type_names

type op_signature = {
  pos : (string * Ty.t) list; opt : (string * Ty.t) list;
  rest : (string * Ty.t) option; kw : (string * Ty.t) list }

let value_ops = List.filter_map (fun (o : op) -> if o.octx = Value then Some o.oname else None) ops

let op_signature ctx name = Option.map (fun (o : op) ->
  ({ pos = o.pos; opt = o.opt; rest = o.rest; kw = o.kw } : op_signature)) (find_op name ctx)
