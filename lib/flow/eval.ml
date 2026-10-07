module W = Workspace
module S = Syntax
module Smap = Map.Make (String)

let max_steps = 600_000
let max_iterations = W.max_iterations
let max_concat = 4_096
let max_depth = 64

exception Needs_t

open Value
let hash = Value.hash
let element_key zone = "$elem:" ^ String.concat "/" zone

type ('f, 'r) payload = ('f, 'r) Value.t =
  | Int of int
  | Float of float
  | Bool of bool
  | Text of string
  | Vec3 of float * float * float
  | List of ('f, 'r) payload array
  | Record of (string * ('f, 'r) payload) list
  | Geo of int
  | No_geo
  | Struct of string * Ty.t * (string * ('f, 'r) payload) list
  | Fn of 'f
  | Residual of 'r

type value = (fn, residual) payload

and fn =
  | Closure of { params : (W.pattern * Ty.t option) list; body : W.term; env : value Smap.t;
                 zone : W.path; calls : int ref; at : ctx }
  | Named of { name : string; ncalls : int ref }

(* ponytail: [renv] is the whole scope of the term, not only its free variables; the
   compiled form ({!fast_of}) only reads the names the term uses. *)
and residual = { rid : int; rterm : W.term; renv : value Smap.t; rc : ctx; mutable fast : fast }

and fast = Untried | Failed | Ready of (float -> value)

and ctx = { st : st; inst : int; prefix : W.path; base : W.path; route : string list;
            iter : int list; depth : int; rec_ : bool }

and st = {
  time : float option;  (* [None] while evaluating statically *)
  mutable steps : int;
  mutable nodes : node list;
  mutable nnodes : int;
  mutable cells : cell list;
  cache : (string, cell) Hashtbl.t;
  memo : (int, value) Hashtbl.t;
  mutable rids : int;
  record : bool;
  elems : value Smap.t;  (* live evaluation: the element bound in each geometry zone *)
  recs : (W.path, int * (int list * value) list) Hashtbl.t;
  graphs : (string, W.graph) Hashtbl.t;
  defs : (string, W.graph) Hashtbl.t;
  kind_fns : (string * (string * Context.t * Check.slot list)) list;
}

and node = { id : int; inst : int; site : W.path; iter : int list; kind : string;
             args : (string * value) list }

and cell = { cgraph : string; cdefault : bool; mutable cinputs : (string * value) list; mutable cresult : value }

type live = { t : float }
type instance = { graph : string; default : bool; inputs : (string * value) list; result : value }
type plan = { instances : instance array; nodes : node array }
type t = { plan : plan; results : (string * value) list;
           records : (W.path * (int list * value) list) list }

let key_of v = Value.key_of ~residual:(fun r -> r.rid) v
(* [coerce v to the type of w]: fold accumulators, reduce, assoc *)
let rec coerce_like w v =
  match w, v with
  | _, Residual _ | Residual _, _ -> v
  | Int _, (Float _ | Bool _) -> coerce_to Ty.Int v
  | Float _, (Int _ | Bool _) -> coerce_to Ty.Float v
  | Bool _, (Int _ | Float _) -> coerce_to Ty.Bool v
  | Vec3 _, (Int _ | Float _) -> coerce_to Ty.Vec3 v
  | List a, List b when Array.length a > 0 -> List (Array.map (coerce_like a.(0)) b)
  | Record wf, Record fs ->
      Record (List.map (fun (n, x) -> match List.assoc_opt n wf with
        | Some w -> (n, coerce_like w x) | None -> (n, x)) fs)
  | _ -> v

(* an accumulator: as [coerce_like], but an int seed such as [0] does not round a float step *)
let widen_like w v = match w, v with Int _, Float _ -> v | _ -> coerce_like w v

let join_values xs = let t = elem_ty xs in Array.map (coerce_to t) xs

let rec pat_key = function
  | W.Name n -> n
  | W.Seq ps -> "[" ^ String.concat " " (List.map pat_key ps) ^ "]"
  | W.Keys ks -> "{:keys [" ^ String.concat " " ks ^ "]}"

let path_text p = String.concat "/" p

(* ---- str formatting (register C2) ---- *)

(* ---- context helpers ---- *)

let site c = c.prefix @ c.base @ List.rev c.route
let sub c seg = { c with route = seg :: c.route }
let span_of (x : W.term) =
  let s = x.form.span in if s.start = 0 && s.finish = 0 then None else Some s

let note c path v =
  let st = c.st in
  if st.record && c.rec_ then begin
    let n, l = match Hashtbl.find_opt st.recs path with Some p -> p | None -> (0, []) in
    if n < max_iterations then Hashtbl.replace st.recs path (n + 1, (c.iter, v) :: l)
  end

let mk_node c kind args =
  let st = c.st in
  if st.time <> None then
    failf "E_LIVE_GEOMETRY" "%s makes geometry; geometry cannot be created while evaluating a live value." kind;
  let n = { id = st.nnodes; inst = c.inst; site = site c; iter = c.iter; kind; args } in
  st.nodes <- n :: st.nodes;
  st.nnodes <- st.nnodes + 1;
  Geo n.id

let catalog_call c kind ctx args =
  if not (Context.supports_values ctx) || ctx = Context.Material
  then Struct (kind, Ty.of_context ctx, args) else mk_node c kind args

(* ---- the evaluator ---- *)

let lookup_field name v f =
  match v with
  | Vec3 (x, _, _) when f = "x" -> Float x
  | Vec3 (_, y, _) when f = "y" -> Float y
  | Vec3 (_, _, z) when f = "z" -> Float z
  | Record fs ->
      (match List.assoc_opt f fs with
       | Some v -> v
       | None -> failf "E_FIELD" "%s has no field %s." name f)
  | _ -> failf "E_FIELD" "%s has no output %s. A vec3 has .x .y .z; a record has its fields." name f

let case_literal (x : S.t) =
  match x.node with
  | S.Num s ->
      (match (if String.contains s '.' then None else int_of_string_opt s) with
       | Some n -> Int n
       | None -> Float (float_of_string s))
  | S.Str s -> Text s
  | S.Sym s -> Bool (s = "true")
  | _ -> fail "E_CASE" "case matches literal numbers, text or booleans."

let case_matches sv lv =
  let tb = function Bool b -> b | v -> num v <> 0. in
  match sv, lv with
  | Bool _, _ | _, Bool _ -> tb sv = tb lv
  | Text a, Text b -> a = b
  | (Int _ | Float _), (Int _ | Float _) -> num sv = num lv
  | _ -> false

(* ---- compiled residuals ----
   A residual is forced every frame while a live value plays, and most of its term does not
   depend on [t]: [fast_of] partially evaluates it once against its captured scope (constant
   subterms fold, a loop over a static list unrolls with its item known) into a closure of [t]
   that applies the same operators to the same values in the same order, so its result is
   bit-identical to the interpreter's.  A term outside the subset (calls, functions, records,
   geometry, a loop over anything but a static list) is left to the interpreter; so is any
   failure at run time, which re-runs the term there for its exact diagnostic.
   ponytail: no dynamic [let*] binding and at most [compile_budget] compiled nodes per root. *)
exception Unsupported

type cnode = Const of value | Dyn of (float -> value)
type cenv = { base : value Smap.t; over : cnode Smap.t; budget : int ref }

let compile_budget = 2048
let compile_residuals = ref true

let add_values a b = match a, b with
  | Vec3 (x, y, z), Vec3 (p, q, r) -> Vec3 (x +. p, y +. q, z +. r)
  | (Int _ as a), (Int _ as b) -> Int (int_of a + int_of b)
  | a, b -> Float (num a +. num b)

let run_node n t = match n with Const v -> v | Dyn f -> f t

let map_nodes f nodes = match List.for_all (function Const _ -> true | Dyn _ -> false) nodes with
  | true -> Const (f (List.map (function Const v -> v | Dyn _ -> assert false) nodes))
  | false -> Dyn (fun t -> f (List.map (fun n -> run_node n t) nodes))

let rec fast_of (r : residual) : (float -> value) option =
  if not !compile_residuals then None else
  match r.fast with
  | Ready f -> Some f
  | Failed -> None
  | Untried ->
      r.fast <- Failed;  (* a residual met again while it compiles is a cycle: interpreted *)
      (match compile { base = r.renv; over = Smap.empty; budget = ref compile_budget } r.rterm with
       | node ->
           (* a residual read twice in one frame (a chain of sums) is evaluated once: it depends
              on [t] alone, so its last value is kept for the same [t], compared bit for bit *)
           let raw = run_node node in
           let last_t = ref 0L and last = ref None in
           let f t =
             let bits = Int64.bits_of_float t in
             match !last with
             | Some v when Int64.equal bits !last_t -> v
             | _ -> let v = raw t in last_t := bits; last := Some v; v in
           r.fast <- Ready f; Some f
       | exception (Unsupported | Fail _ | Not_found | Invalid_argument _ | Failure _) -> None)

and cnode_of_value = function
  | Residual r -> (match fast_of r with Some f -> Dyn f | None -> raise Unsupported)
  | v -> Const v

and compile ce (x : W.term) : cnode =
  decr ce.budget;
  if !(ce.budget) < 0 then raise Unsupported;
  match x.node with
  | W.Lit (Param.Int_value n) -> Const (Int n)
  | W.Lit (Param.Float_value f) -> Const (Float f)
  | W.Lit (Param.Bool_value b) -> Const (Bool b)
  | W.Text s -> Const (Text s)
  | W.Nil -> Const No_geo
  | W.Time -> Dyn (fun t -> Float t)
  | W.Vec [ a; b; d ] ->
      let a = compile ce a in let b = compile ce b in let d = compile ce d in
      (match a, b, d with
       | Const a, Const b, Const d -> Const (Vec3 (num a, num b, num d))
       | _ ->
           let comp = function Const v -> let f = num v in (fun _ -> f) | Dyn g -> (fun t -> num (g t)) in
           let ga = comp a and gb = comp b and gd = comp d in
           Dyn (fun t -> let x = ga t in let y = gb t in let z = gd t in Vec3 (x, y, z)))
  | W.Ref_binding (b, _) when String.starts_with ~prefix:"$elem:" b -> raise Unsupported
  | W.Ref_binding (b, fs) ->
      let start = match Smap.find_opt b ce.over with
        | Some n -> n
        | None -> (match Smap.find_opt b ce.base with Some v -> cnode_of_value v | None -> raise Unsupported) in
      List.fold_left (fun n f -> match n with
        | Const v -> Const (lookup_field b v f)
        | Dyn g -> Dyn (fun t -> lookup_field b (g t) f)) start fs
  | W.Op { op; args; _ } ->
      let o = match Op.find op Context.Value with
        | Some o when o.ctx = Context.Value && o.shape = Op.Scalar -> o
        | _ -> raise Unsupported in
      let nodes = List.map (fun (_, a) -> compile ce a) args in
      (match Op.arith op, nodes with
       | Some f, [ Const a; Const b ] -> Const (f.apply a b)
       | Some binary, [ a; b ] ->
           let f = binary.apply in
           (match a, b with
            | Dyn g, Dyn h -> Dyn (fun t -> let x = g t in f x (h t))
            | Dyn g, Const y -> Dyn (fun t -> f (g t) y)
            | Const x, Dyn h -> Dyn (fun t -> f x (h t))
            | Const _, Const _ -> assert false)
       | _ -> map_nodes (fun vals -> o.body ~node:(fun _ _ -> raise Unsupported)
           (List.map2 (fun (n, _) v -> n, v) args vals)) nodes)
  | W.Let (binds, res) ->
      let over = List.fold_left (fun over ((pat : W.pattern), t) -> match pat, compile { ce with over } t with
        | W.Name n, (Const _ as node) -> Smap.add n node over
        | _ -> raise Unsupported) ce.over binds in
      compile { ce with over } res
  | W.If (c, a, b) ->
      (match compile ce c with
       | Const v -> if truthy v then compile ce a else compile ce b
       | Dyn g ->
           let a = compile ce a and b = compile ce b in
           Dyn (fun t -> if truthy (g t) then run_node a t else run_node b t))
  | W.Loop { kind = (`Sum | `For) as kind; accs = []; clauses = [ (W.Name p, e) ]; skip = []; body; _ } ->
      let items = match compile ce e with
        | Const (List xs) when Array.length xs <= max_iterations -> xs
        | _ -> raise Unsupported in
      let bodies = Array.map (fun item ->
        compile { ce with over = Smap.add p (Const item) ce.over } body) items in
      let collect vs = match kind with
        | `Sum -> if vs = [||] then Int 0 else Array.fold_left add_values vs.(0) (Array.sub vs 1 (Array.length vs - 1))
        | `For -> List (join_values vs) in
      if Array.for_all (function Const _ -> true | Dyn _ -> false) bodies
      then Const (collect (Array.map (fun n -> run_node n 0.) bodies))
      else Dyn (fun t -> collect (Array.map (fun n -> run_node n t) bodies))
  | _ -> raise Unsupported

let rec concrete c v =
  match v with
  | Residual r -> (match c.st.time with None -> raise Needs_t | Some _ -> force_res c r)
  | v -> v

and force_res c r =
  match Hashtbl.find_opt c.st.memo r.rid with
  | Some v -> v
  | None ->
      let slow () = ev { r.rc with st = c.st } r.renv r.rterm in
      let v = match c.st.time, fast_of r with
        | Some t, Some f ->
            (try f t with Fail _ | Needs_t | Not_found | Invalid_argument _ | Failure _ -> slow ())
        | _ -> slow () in
      Hashtbl.replace c.st.memo r.rid v;
      v

and ev c env (x : W.term) : value =
  let st = c.st in
  st.steps <- st.steps + 1;
  if st.steps > max_steps then
    failf "E_EVAL_BUDGET" "Evaluation budget exceeded (%d steps). Reduce iteration counts." max_steps;
  let c = match x.path with Some p -> { c with base = p; route = [] } | None -> c in
  match st.time with
  | None ->
      let saved = st.nodes and saved_n = st.nnodes in
      (match ev_raw c env x with
       | v -> (match x.path with Some p -> note c p v | None -> ()); v
       | exception Needs_t ->
           (* ponytail: nodes made by the abandoned attempt are dropped, its records are kept *)
           st.nodes <- saved; st.nnodes <- saved_n;
           st.rids <- st.rids + 1;
           let r = Residual { rid = st.rids; rterm = x; renv = env; rc = c; fast = Untried } in
           (* the record is the residual: a probe forces it at the time it shows *)
           (match x.path with Some p -> note c p r | None -> ()); r
       | exception Fail (code, msg, None) -> raise (Fail (code, msg, span_of x)))
  | Some _ ->
      (match concrete c (ev_raw c env x) with
       | exception Fail (code, msg, None) -> raise (Fail (code, msg, span_of x))
       | v -> v)

and evs c env prefix ts = List.mapi (fun i t -> ev (sub c (prefix ^ string_of_int i)) env t) ts

and eval_named c env args =
  let counts = Hashtbl.create 4 in
  List.map (fun (name, t) ->
    let n = Option.value (Hashtbl.find_opt counts name) ~default:0 in
    Hashtbl.replace counts name (n + 1);
    let seg = if n = 0 then name else name ^ "#" ^ string_of_int n in
    (name, ev (sub c seg) env t)) args

and field c v f name = lookup_field name (concrete c v) f

and bind_parts c ~mk pat v env =
  match pat with
  | W.Name n ->
      (match mk with Some mk -> note c (mk n) v | None -> ());
      Smap.add n v env
  | W.Seq ps ->
      let xs = match concrete c v with
        | List xs -> xs
        | Vec3 (a, b, d) -> [| Float a; Float b; Float d |]
        | _ -> failf "E_PATTERN" "%s destructures a list or vec3." (pat_key pat) in
      if Array.length xs < List.length ps then
        failf "E_PATTERN" "%s needs %d elements; the list has %d." (pat_key pat) (List.length ps)
          (Array.length xs);
      snd (List.fold_left (fun (i, env) p -> (i + 1, bind_parts c ~mk p xs.(i) env)) (0, env) ps)
  | W.Keys ks ->
      let r = concrete c v in
      List.fold_left (fun env k ->
        bind_parts c ~mk (W.Name k) (lookup_field (pat_key pat) r k) env) env ks

(* [whole]: also record the value of a destructuring pattern under its printed name *)
and bind_pat c ~mk ~whole pat v env =
  (match pat, mk with
   | (W.Seq _ | W.Keys _), Some mk when whole -> note c (mk (pat_key pat)) v
   | _ -> ());
  match pat with
  | W.Name n when not whole -> Smap.add n v env
  | _ -> bind_parts c ~mk pat v env

and ev_raw c env (x : W.term) : value =
  match x.node with
  | W.Lit (Param.Int_value n) -> Int n
  | W.Lit (Param.Float_value f) -> Float f
  | W.Lit (Param.Bool_value b) -> Bool b
  | W.Lit _ -> fail "E_TYPE" "Unexpected literal."
  | W.Text s -> Text s
  | W.Nil -> No_geo
  | W.Time -> (match c.st.time with Some t -> Float t | None -> raise Needs_t)
  | W.Vec [ a; b; d ] ->
      let f i t = num (concrete c (ev (sub c (string_of_int i)) env t)) in
      let a = f 0 a in let b = f 1 b in let d = f 2 d in Vec3 (a, b, d)
  | W.Vec cs -> failf "E_VECTOR" "A vector has 3 components [x y z]; this one has %d." (List.length cs)
  | W.Ref_binding (b, []) when String.starts_with ~prefix:"$elem:" b ->
      (match Smap.find_opt b c.st.elems with Some v -> v | None -> raise Needs_t)
  | W.Ref_binding (b, fs) ->
      (match Smap.find_opt b env with
       | None -> failf "E_UNBOUND" "%s is not bound." b
       | Some v -> fst (List.fold_left (fun (v, p) f -> (field c v f p, p ^ "." ^ f)) (v, b) fs))
  | W.Call { kind; ctx; args } ->
      let vals = eval_named c env args in
      let vals =
        if kind = "sop/merge" then
          List.concat_map (fun (n, v) -> match concrete c v with
            | List xs -> List.map (fun g -> (n, g)) (Array.to_list xs)
            | v -> [ (n, v) ]) vals
          |> List.filter (fun (_, v) -> match v with No_geo -> false | _ -> true)
        else vals in
      catalog_call c kind ctx vals
  | W.Op { op = "scene/merge"; args; skip = _ :: _ as skip } ->
      (* register L16: the arguments at skipped tuples are not evaluated *)
      let args = List.filteri (fun p _ -> not (List.mem (c.iter @ [ p ]) skip)) args in
      apply_op c "scene/merge" (eval_named c env args)
  | W.Op { op; args; _ } -> apply_op c op (eval_named c env args)
  | W.Call_fn { fn; args } ->
      let vals = evs c env "a" args in
      (match Smap.find_opt fn env with
       | Some (Fn f) -> call_fn c f vals
       | _ -> apply_def c fn vals)
  (* ponytail: a catalog kind used as a function value keeps the name as written; lowering resolves it. *)
  | W.Fn_ref name -> Fn (Named { name; ncalls = ref 0 })
  | W.Graph_ref { graph; inputs } ->
      let over = eval_named c env inputs in
      graph_value ~rec_:(over = []) c graph over
  | W.Let (binds, res) ->
      let env = List.fold_left (fun env (pat, (t : W.term)) ->
        let v = ev c env t in
        let pfx = match t.path with
          | Some p -> List.filteri (fun i _ -> i < List.length p - 1) p | None -> [] in
        bind_pat c ~mk:(Some (fun n -> pfx @ [ n ])) ~whole:false pat v env) env binds in
      ev c env res
  | W.Loop l -> loop c env l.kind l.accs l.clauses l.skip l.body l.zone
  | W.If (cnd, a, b) ->
      if truthy (concrete c (ev (sub c "if") env cnd)) then ev (sub c "then") env a
      else ev (sub c "else") env b
  | W.Cond (arms, default) ->
      let rec go i = function
        | [] -> ev (sub c "else") env default
        | (t, e) :: rest ->
            if truthy (concrete c (ev (sub c ("test" ^ string_of_int i)) env t))
            then ev (sub c ("arm" ^ string_of_int i)) env e else go (i + 1) rest in
      go 0 arms
  | W.Case (scrut, arms, default) ->
      let sv = concrete c (ev (sub c "case") env scrut) in
      let rec go i = function
        | [] -> ev (sub c "else") env default
        | (lit, e) :: rest ->
            if case_matches sv (case_literal lit) then ev (sub c ("arm" ^ string_of_int i)) env e
            else go (i + 1) rest in
      go 0 arms
  | W.Fn { params; body; zone } ->
      Fn (Closure { params; body; env; zone; calls = ref 0; at = c })
  | W.Hof (kind, f :: rest) -> hof c env kind f rest
  | W.Hof (_, []) -> fail "E_ARITY" "A higher-order form takes a function."
  | W.List_lit ts -> List (join_values (Array.of_list (evs c env "" ts)))
  | W.Record fs -> Record (List.map (fun (n, t) -> (n, ev (sub c n) env t)) fs)
  | W.Get (r, f) -> field c (ev c env r) f (Lisp.flat r.form)
  | W.Assoc (r, ups) ->
      let fs = match concrete c (ev c env r) with
        | Record fs -> fs | _ -> fail "E_TYPE" "assoc updates a record." in
      let fs = List.fold_left (fun fs (n, t) ->
        let v = ev (sub c n) env t in
        match List.assoc_opt n fs with
        | Some old -> List.map (fun (k, x) -> if k = n then (k, coerce_like old v) else (k, x)) fs
        | None -> fs @ [ (n, v) ]) fs ups in
      Record fs
  | W.Str ts -> Text (String.concat "" (List.map (show_with (concrete c)) (evs c env "" ts)))
  | W.List_op (_, ts) ->
      let xs = List.concat_map (fun v -> Array.to_list (list_arg (concrete c v))) (evs c env "" ts) in
      let xs = join_values (Array.of_list xs) in
      if Array.length xs > max_concat then fail "E_ITER_BOUND" "concat exceeds 4,096 elements.";
      List xs
  | W.Bypass t ->
      let entries = match t.node with
        | W.Call { args; _ } | W.Op { args; _ } -> List.map snd args
        | W.Call_fn { args; _ } -> args
        | _ -> [] in
      (* as the checker counts it: the first positional argument, after the keyword pairs *)
      let index = match t.node, t.form.node with
        | _, S.List (_ :: args) ->
            let rec first i = function
              | { S.node = S.Kw _; _ } :: _ :: rest -> first (i + 1) rest
              | _ -> i in
            first 0 args
        | _ -> 0 in
      (match List.nth_opt entries index with
       | Some input -> coerce_to t.ty (ev (sub c "bypass") env input)
       | None -> fail "E_BYPASS" "Nothing to pass through.")
  | W.Expanded { body; _ } -> ev c env body

and apply_op c name (vals : (string * value) list) : value =
  let o = match Op.find name Context.Value with
    | Some o -> o | None -> failf "E_UNKNOWN" "Unknown operator %s." name in
  let vals = match o.shape with
    | Op.Struct {splice = true} ->
        List.concat_map (fun (n, v) -> match concrete c v with
          | List xs -> List.map (fun x -> (n, x)) (Array.to_list xs)
          | v -> [ (n, v) ]) vals
    | _ -> vals in
  let vals = match o.shape with
    | Op.Scalar when o.ctx = Context.Value -> List.map (fun (n, v) -> n, concrete c v) vals
    | _ -> vals in
  o.check vals;
  o.body ~node:(mk_node c) vals

and apply_def c name (vals : value list) : value =
  let d = match Hashtbl.find_opt c.st.defs name with
    | Some d -> d | None -> failf "E_UNKNOWN" "Unknown function %s." name in
  if c.depth > max_depth then fail "E_DEPTH" "Call depth exceeds 64.";
  let base = [ "def:" ^ name ] in
  let c' = { c with prefix = site c; base; route = []; depth = c.depth + 1 } in
  let env, _ = List.fold_left (fun (env, i) (pname, ty, default) ->
    let v = match List.nth_opt vals i, default with
      | Some v, _ -> coerce_to ty v
      | None, Some t -> coerce_to ty (ev (sub c' pname) env t)
      | None, None -> failf "E_ARGS" "%s needs :%s." name pname in
    note c' (base @ [ ":" ^ pname ]) v;
    (Smap.add pname v env, i + 1)) (Smap.empty, 0) d.inputs in
  ev c' env d.body

and call_fn c f (vals : value list) : value =
  match f with
  | Closure cl ->
      if List.length vals <> List.length cl.params then
        failf "E_ARITY" "%s takes %d argument%s; got %d." (path_text cl.zone) (List.length cl.params)
          (if List.length cl.params = 1 then "" else "s") (List.length vals);
      if c.depth > max_depth then fail "E_DEPTH" "Call depth exceeds 64.";
      let k = !(cl.calls) in
      incr cl.calls;
      let c' = { c with inst = cl.at.inst; prefix = cl.at.prefix; base = cl.zone; route = [];
                        iter = c.iter @ [ k ]; depth = c.depth + 1 } in
      let mk = Some (fun n -> cl.zone @ [ ":" ^ n ]) in
      let env = List.fold_left2 (fun env (pat, ty) v ->
        let v = match ty with Some t -> coerce_to t v | None -> v in
        bind_pat c' ~mk ~whole:true pat v env) cl.env cl.params vals in
      ev c' env cl.body
  | Named { name; ncalls } ->
      let k = !ncalls in
      incr ncalls;
      let c' = { c with iter = c.iter @ [ k ] } in
      if Hashtbl.mem c.st.defs name then apply_def c' name vals
      else begin
        let named = List.mapi (fun i v -> ("$" ^ string_of_int i, v)) vals in
        match Op.find name Context.Value with
        | Some o -> apply_op c' o.name named
        | None ->
              (* a catalog kind: the checker resolved its name and which input each argument is *)
              let kind, ctx, slots = match List.assoc_opt name c.st.kind_fns with
                | Some k -> k | None -> failf "E_UNKNOWN" "Unknown function %s." name in
              let slots = Array.of_list slots in
              let rest = if Array.length slots = 0 then None else
                let slot = slots.(Array.length slots - 1) in
                if slot.Check.rest then Some slot.name else None in
              if List.length vals > Array.length slots && Option.is_none rest then
                failf "E_ARITY" "%s takes at most %d inputs." kind (Array.length slots);
              let args = List.mapi (fun i v ->
                ((if i < Array.length slots then slots.(i).Check.name else Option.get rest), v)) vals in
              catalog_call c' kind ctx args
      end

and hof c env kind f rest =
  let fv = match concrete c (ev (sub c "f") env f) with
    | Fn f -> f | _ -> fail "E_TYPE" "Expected a function." in
  let lists_of ts = List.mapi (fun i t ->
    list_arg (concrete c (ev (sub c ("l" ^ string_of_int i)) env t))) ts in
  match kind, rest with
  | `Map, ls ->
      let ls = lists_of ls in
      let n = List.fold_left (fun n l -> min n (Array.length l)) max_int ls in
      let n = if ls = [] then 0 else n in
      List (join_values (Array.init n (fun k -> call_fn c fv (List.map (fun l -> l.(k)) ls))))
  | `Filter, [ l ] ->
      let xs = List.hd (lists_of [ l ]) in
      List (Array.of_list (List.filter (fun x -> truthy (concrete c (call_fn c fv [ x ])))
        (Array.to_list xs)))
  | `Sort_by, [ l ] ->
      let xs = List.hd (lists_of [ l ]) in
      let keyed = Array.mapi (fun i x -> (num (concrete c (call_fn c fv [ x ])), i, x)) xs in
      let sorted = List.stable_sort (fun (a, _, _) (b, _, _) -> compare a b) (Array.to_list keyed) in
      List (Array.of_list (List.map (fun (_, _, x) -> x) sorted))
  | `Reduce, [ init; l ] ->
      let init = ev (sub c "init") env init in
      let xs = List.hd (lists_of [ l ]) in
      Array.fold_left (fun acc x -> widen_like acc (call_fn c fv [ acc; x ])) init xs
  | _ -> fail "E_ARITY" "A higher-order form got the wrong number of arguments."

and loop c env kind accs clauses skip body zone =
  let cz = { c with base = zone; route = [] } in
  let init = match accs with
    | [ (_, e) ] -> Some (ev (sub cz "init") env e)
    | _ -> None in
  let acc_pat = match accs with [ (p, _) ] -> Some p | _ -> None in
  let acc = ref init in
  let k = ref 0 and outs = ref [] and total = ref None and over_geometry = ref None in
  let clauses = Array.of_list clauses in
  let n = Array.length clauses in
  let mk = Some (fun v -> zone @ [ ":" ^ v ]) in
  let add a b =
    match concrete c a, concrete c b with
    | Vec3 (x, y, z), Vec3 (p, q, r) -> Vec3 (x +. p, y +. q, z +. r)
    | (Int _ as a), (Int _ as b) -> Int (int_of a + int_of b)
    | a, b -> Float (num a +. num b) in
  let rec go ci env items =
    if ci = n then begin
      if !k >= max_iterations then
        failf "E_ITER_BOUND" "%s runs more than 4,096 iterations." (path_text zone);
      let ci' = { cz with iter = c.iter @ [ !k ] } in
      (* record the loop names at this iteration, in clause order *)
      let env = ref env in
      List.iteri (fun i item -> env := bind_pat ci' ~mk ~whole:true (fst clauses.(i)) item !env)
        (List.rev items);
      (match acc_pat, !acc with
       | Some p, Some a -> env := bind_pat ci' ~mk ~whole:true p a !env
       | _ -> ());
      if List.mem ci'.iter skip then incr k else begin
      let v = ev ci' !env body in
      (match kind, !acc with
       | (`Fold | `Scan), Some a ->
           let a' = widen_like a v in
           acc := Some a';
           if kind = `Scan then outs := a' :: !outs
       | `Sum, _ -> total := Some (match !total with None -> v | Some t -> add t v)
       | _ -> outs := v :: !outs);
      incr k
      end
    end else begin
      let p, e = clauses.(ci) in
      (match concrete c (ev (sub cz ("in" ^ string_of_int ci)) env e) with
       | Struct (op, Ty.List _, fs) ->
           if kind <> `For || n <> 1 || skip <> [] then
             failf "E_ZONE" "%s: only a for with one clause and no :skip can iterate the elements of geometry." (path_text zone);
           over_geometry := Some (geometry_loop c cz env op fs p body zone)
       | v ->
           Array.iter (fun item ->
             go (ci + 1) (bind_pat c ~mk:None ~whole:false p item env) (item :: items)) (list_arg v))
    end in
  go 0 env [];
  match !over_geometry with Some v -> v | None ->
  match kind with
  | `Fold -> Option.get !acc
  | `Sum -> (match !total with None -> Int 0 | Some t -> concrete c t)
  | `For | `Scan -> List (join_values (Array.of_list (List.rev !outs)))


(* W8: [(for [p (sop/point_list g)] body)].  The count is known only when [g] cooks, so
   the body is evaluated once, as a template, with the element unknown: a point is a residual
   read from [st.elems] when forced, a piece a plan node [zone/element].  The template's nodes
   (ids [lo] .. [hi - 1]) are not part of the graph; the plan node [zone/points] or
   [zone/pieces] (a [Geo], the merge of the elements) tells lowering how to cook them. *)
and geometry_loop c cz env op fs p body zone =
  if c.st.time <> None then failf "E_LIVE_GEOMETRY" "%s iterates geometry while evaluating a live value." (path_text zone);
  let src = match List.assoc_opt "geometry" fs with
    | Some (Geo id) -> id | _ -> failf "E_TYPE" "%s: %s needs geometry." (path_text zone) op in
  let key = List.assoc_opt "key" fs in
  let points = op = "sop/point_list" in
  let ci = { cz with iter = c.iter @ [ 0 ] } in
  let ekey = element_key zone in
  let lo = c.st.nnodes in
  let elem, elem_arg =
    if points then begin
      c.st.rids <- c.st.rids + 1;
      let term = { W.path = None; ty = Ty.Vec3; node = W.Ref_binding (ekey, []); form = body.W.form } in
      Residual { rid = c.st.rids; rterm = term; renv = Smap.empty; rc = ci; fast = Untried }, Text ekey
    end else
      (match mk_node (sub ci "element") "zone/element" [] with
       | Geo id as g -> g, Int id
       | _ -> assert false) in
  let mk = Some (fun v -> zone @ [ ":" ^ v ]) in
  let env = bind_pat ci ~mk ~whole:true p elem env in
  let v = ev ci env body in
  let root = match v with
    | Geo id -> id
    | Residual _ -> failf "E_ZONE" "%s: what a loop over geometry builds cannot depend on the element; only arguments can." (path_text zone)
    | _ -> failf "E_TYPE" "%s: the body of a loop over geometry returns geometry." (path_text zone) in
  let hi = c.st.nnodes in
  mk_node c (if points then "zone/points" else "zone/pieces")
    ((("geometry", Geo src) :: (match key with Some k -> [ ("key", k) ] | None -> []))
     @ [ ("body", Int root); ("lo", Int lo); ("hi", Int hi); ("element", elem_arg) ])

and graph_value ?(rec_ = true) c name over =
  let st = c.st in
  let g = match Hashtbl.find_opt st.graphs name with
    | Some g -> g | None -> failf "E_UNKNOWN_GRAPH" "Unknown graph reference: %s." name in
  let over = List.map (fun (n, v) ->
    match List.find_opt (fun (m, _, _) -> m = n) g.inputs with
    | Some (_, ty, _) -> (n, coerce_to ty v)
    | None -> (n, v)) over in
  let key = name ^ "|" ^ String.concat "," (List.sort compare
    (List.map (fun (n, v) -> n ^ "=" ^ key_of v) over)) in
  let run inst =
    if c.depth > max_depth then fail "E_DEPTH" "Call depth exceeds 64.";
    let c0 = { st; inst; prefix = []; base = [ name ]; route = []; iter = []; depth = c.depth + 1; rec_ = rec_ } in
    let env, ins = List.fold_left (fun (env, ins) (n, ty, default) ->
      let v = match List.assoc_opt n over with
        | Some v -> v
        | None ->
            (match default with
             | Some t -> coerce_to ty (ev (sub c0 n) env t)
             | None -> failf "E_INPUT_DEFAULT" "Graph input %s of %s needs a default." n name) in
      note c0 [ name; ":" ^ n ] v;
      (Smap.add n v env, (n, v) :: ins)) (Smap.empty, []) g.inputs in
    (ev c0 env g.body, List.rev ins) in
  match st.time with
  | Some _ -> fst (run c.inst)
  | None ->
      (match Hashtbl.find_opt st.cache key with
       | Some cell -> cell.cresult
       | None ->
           let cid = List.length st.cells in
           let cell = { cgraph = name; cdefault = (over = []); cinputs = []; cresult = No_geo } in
           st.cells <- cell :: st.cells;
           Hashtbl.replace st.cache key cell;
           let v, ins = run cid in
           cell.cinputs <- ins;
           cell.cresult <- v;
           v)

(* ---- entry points ---- *)

let diagnostic code msg span = Diagnostic.error ?span ~code msg

let new_state ~record ws =
  let graphs = Hashtbl.create 8 and defs = Hashtbl.create 8 in
  List.iter (fun (g : W.graph) -> Hashtbl.replace graphs g.name g) ws.W.graphs;
  List.iter (fun (g : W.graph) -> Hashtbl.replace defs g.name g) ws.W.defs;
  { time = None; steps = 0; nodes = []; nnodes = 0; cells = []; cache = Hashtbl.create 8;
    memo = Hashtbl.create 1; rids = 0; record; elems = Smap.empty; recs = Hashtbl.create 64; graphs; defs;
    kind_fns = ws.W.kind_fns }

let live_state (st : st) ?(elems = Smap.empty) (l : live) =
  { st with time = Some l.t; steps = 0; memo = Hashtbl.create 16; record = false; elems }

let root st = { st; inst = -1; prefix = []; base = []; route = []; iter = []; depth = 0; rec_ = true }

let protect f =
  try Ok (f ()) with
  | Fail (code, msg, span) -> Error (diagnostic code msg span)
  | Needs_t -> Error (diagnostic "E_EVAL" "A live value was needed while evaluating statically." None)
  | Stack_overflow -> Error (diagnostic "E_DEPTH" "Evaluation is nested too deeply." None)

let static ?(record = false) ?(inputs = []) ws =
  protect (fun () ->
    let st = new_state ~record ws in
    let c = root st in
    let results = List.map (fun (g : W.graph) ->
      let over = Option.value (List.assoc_opt g.name inputs) ~default:[] in
      (g.name, graph_value c g.name over)) ws.W.graphs in
    let instances = st.cells |> List.rev |> List.map (fun cell ->
      { graph = cell.cgraph; default = cell.cdefault; inputs = cell.cinputs; result = cell.cresult }) |> Array.of_list in
    let records = Hashtbl.fold (fun p (_, l) acc -> (p, List.rev l) :: acc) st.recs []
      |> List.sort (fun (a, _) (b, _) -> compare a b) in
    { plan = { instances; nodes = Array.of_list (List.rev st.nodes) }; results; records })

let rec is_live = function
  | Residual _ -> true
  | List xs -> Array.exists is_live xs
  | Record fs | Struct (_, _, fs) -> List.exists (fun (_, v) -> is_live v) fs
  | _ -> false

(* one live state per call, made from the first residual met *)
let with_live ?elems (l : live) (f : (residual -> ctx) -> 'a) : ('a, Diagnostic.t) result =
  let elems = Option.map Smap.of_list elems in
  let live = ref None in
  let ctx_of r =
    let st = match !live with
      | Some s -> s
      | None -> let s = live_state r.rc.st ?elems l in live := Some s; s in
    { r.rc with st } in
  protect (fun () -> f ctx_of)

let residual_eval ?elems r ~live =
  with_live ?elems live (fun ctx_of -> let c = ctx_of r in force_res c r)

let force ?elems v ~live =
  if not (is_live v) then Ok v
  else
    with_live ?elems live (fun ctx_of ->
      let rec go v = match v with
        | Residual r -> let c = ctx_of r in go (force_res c r)
        | List xs -> List (Array.map go xs)
        | Record fs -> Record (List.map (fun (n, x) -> (n, go x)) fs)
        | Struct (n, ty, fs) -> Struct (n, ty, List.map (fun (k, x) -> (k, go x)) fs)
        | v -> v in
      go v)

let run ?record ?inputs ~time ws =
  match static ?record ?inputs ws with
  | Error _ as e -> e
  | Ok s ->
      let live = { t = time } in
      let exception Stop of Diagnostic.t in
      let f v = match force v ~live with Ok v -> v | Error d -> raise (Stop d) in
      (try
         Ok {
              plan = { nodes = Array.map (fun n -> { n with args = List.map (fun (k, v) -> (k, f v)) n.args }) s.plan.nodes;
                       instances = Array.map (fun i -> { i with inputs = List.map (fun (k, v) -> (k, f v)) i.inputs;
                                                                result = f i.result }) s.plan.instances };
              results = List.map (fun (n, v) -> (n, f v)) s.results;
              records = List.map (fun (p, l) -> (p, List.map (fun (it, v) -> (it, f v)) l)) s.records }
       with Stop d -> Error d)

let show v = show_with Fun.id v

module Private = struct
  let compile_residuals = compile_residuals
  let rec compiled = function
    | Residual { fast = Ready _; _ } -> 1
    | List xs -> Array.fold_left (fun n x -> n + compiled x) 0 xs
    | Record fs | Struct (_, _, fs) -> List.fold_left (fun n (_, x) -> n + compiled x) 0 fs
    | _ -> 0
end
