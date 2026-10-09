module W = Workspace
module S = Syntax
module Smap = Map.Make (String)
module Names = Set.Make (String)

let rec pattern_names names = function
  | Workspace.Name name -> Names.add name names
  | Seq patterns -> List.fold_left pattern_names names patterns
  | Keys names' -> List.fold_left (fun names name -> Names.add name names) names names'

module Free_cache = Ephemeron.K1.Make (struct
  type t = Workspace.term
  let equal a b = a == b
  let hash (term : t) = Hashtbl.hash term.form.id
end)

let free_caches = Domain.DLS.new_key (fun () -> Free_cache.create 256)
let free_walks = Atomic.make 0

let free_names term =
  let free_cache = Domain.DLS.get free_caches in
  match Free_cache.find_opt free_cache term with
  | Some names -> names
  | None ->
      ignore (Atomic.fetch_and_add free_walks 1);
      let rec walk bound names (term : Workspace.term) =
        let all bound names terms = List.fold_left (walk bound) names terms in
        let fields bound names fields = List.fold_left (fun names (_, term) -> walk bound names term) names fields in
        let reference name = if Names.mem name bound then names else Names.add name names in
        let bindings bound names bindings = List.fold_left (fun (bound, names) (pattern, term) ->
          pattern_names bound pattern, walk bound names term) (bound, names) bindings in
        match term.node with
        | Ref_binding (name, _) | Fn_ref name -> reference name
        | Call_fn {fn; args; _} -> all bound (reference fn) args
        | Call {args; _} | Op {args; _} | Record args -> fields bound names args
        | Graph_ref {inputs; _} -> fields bound names inputs
        | Vec terms | List_lit terms | Str terms | List_op (_, terms) | Hof (_, terms) -> all bound names terms
        | Let (steps, body) -> let bound, names = bindings bound names steps in walk bound names body
        | Loop {accs; clauses; body; _} ->
            let bound, names = bindings bound names accs in
            let bound, names = bindings bound names clauses in walk bound names body
        | State {binder; init; step; _} -> walk (pattern_names bound binder) (walk bound names init) step
        | Fn {capture = Some original; _} -> walk bound names original
        | Fn {params; body; _} -> walk (List.fold_left (fun bound (pattern, _) -> pattern_names bound pattern) bound params) names body
        | If (condition, yes, no) -> all bound names [condition; yes; no]
        | Cond (arms, default) -> List.fold_left (fun names (test, body) -> walk bound (walk bound names test) body) (walk bound names default) arms
        | Case (subject, arms, default) -> fields bound (all bound names [subject; default]) arms
        | Assoc (record, updates) -> fields bound (walk bound names record) updates
        | Get (body, _) | Bypass body | Expanded {body; _} -> walk bound names body
        | Lit _ | Text _ | Nil | Time -> names in
      let names = walk Names.empty Names.empty term in
      (* ponytail: bound weak memo; workloads above 16k distinct live terms recompute.
         An owner-scoped checked-workspace cache removes that ceiling if measured. *)
      if Free_cache.length free_cache >= 16_384 then Free_cache.clear free_cache;
      Free_cache.replace free_cache term names;
      names

let capture term env =
  Names.fold (fun name captured -> match Smap.find_opt name env with
    | None -> captured | Some value -> Smap.add name value captured)
    (free_names term) Smap.empty

let max_steps = 600_000
let max_iterations = W.max_iterations
let max_concat = 4_096
let max_depth = 64
let packed_block_size = 1024
let empty_live = Frame_input.at_time 0.

exception Needs_t

open Value
let hash = Value.hash
let element_key zone = "$elem:" ^ String.concat "/" zone

type ('f, 'r) payload = ('f, 'r) Value.t =
  | Int of int
  | Float of float
  | Bool of bool
  | Text of string
  | Vec2 of float * float
  | Vec3 of float * float * float
  | Vec4 of float * float * float * float
  | List of ('f, 'r) payload array
  | Float_array of float array
  | Vec2_array of float array
  | Vec3_array of float array
  | Vec4_array of float array
  | Record of (string * ('f, 'r) payload) list
  | Deferred of Ty.t * int
  | No_geo
  | Struct of string * Ty.t * (string * ('f, 'r) payload) list
  | Fn of 'f
  | Residual of 'r

type value = (fn, residual) payload

and fn =
  | Closure of { params : (W.pattern * Ty.t option) list; body : W.term; env : value Smap.t;
                 zone : W.path; calls : int ref; fid : int; at : ctx }
  | Named of { name : string; ncalls : int ref; fid : int }

(* Captures contain the term's lexically free names, including nested bodies. *)
and residual = { rid : int; rterm : W.term; renv : value Smap.t; rc : ctx;
  previous : bool; mutable fast : fast }

and state = { mutable source : string; mutable frame : int option;
  mutable before : value Smap.t; mutable next : value Smap.t; mutable host : state option }

and fast = Untried | Failed | Ready of (Frame_input.t -> value)

and ctx = { st : st; inst : int; prefix : W.path; base : W.path; route : string list;
            iter : int list; depth : int; rec_ : bool; data : bool; geometry : bool; host : bool }

and st = {
  time : Frame_input.t option;  (* [None] while evaluating statically *)
  resolve : (value -> (value, Diagnostic.t) result) option;
  execute : (residual -> Frame_input.t -> (value, Diagnostic.t) result option) option;
  compiled_residuals : bool;
  mutable observe_kernel : (residual -> unit) option;
  source : string Lazy.t;
  state : state option;
  mutable states : value list;
  mutable nfns : int;
  fn_calls : (int, int) Hashtbl.t;
  mutable steps : int;
  mutable nodes : node list;
  mutable authored : int list;
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
  ops : Op.t list;
}

and node = { id : int; inst : int; site : W.path; iter : int list; kind : string; ty : Ty.t;
             args : (string * value) list }

and cell = { cgraph : string; cdefault : bool; mutable cinputs : (string * value) list; mutable cresult : value }

type live = Frame_input.t
type instance = { graph : string; default : bool; inputs : (string * value) list; result : value }
type plan = { instances : instance array; nodes : node array }
type t = { plan : plan; authored : int array; results : (string * value) list; states : value list;
           records : (W.path * (int list * value) list) list }

let bulk_ids = Atomic.make (-1)

let create_state () = {source = ""; frame = None; before = Smap.empty; next = Smap.empty;host=None}
let reset_frame s = s.source <- ""; s.frame <- None; s.before <- Smap.empty; s.next <- Smap.empty
let reset_state ?(host_state=true) s = reset_frame s;if host_state then s.host<-None
let rec fork_state s = {source = s.source; frame = s.frame; before = s.before; next = s.next;
  host=Option.map fork_state s.host}
let restore_state s saved=s.source<-saved.source;s.frame<-saved.frame;
  s.before<-saved.before;s.next<-saved.next;s.host<-saved.host
let state_stamp s = Digest.to_hex (Digest.string (Marshal.to_string s []))
let transaction s f =
  let saved = fork_state s in
  let result = f () in
  (match result with Ok _ -> () | Error _ ->
    restore_state s saved);
  result
let begin_frame s source frame =
  if source <> s.source || Option.fold ~none:false ~some:(fun old -> frame < old) s.frame then reset_frame s;
  s.source <- source;
  if s.frame <> Some frame then begin
    s.before <- Smap.union (fun _ _ newer -> Some newer) s.before s.next;
    s.next <- Smap.empty; s.frame <- Some frame
  end
let state_key c zone = Marshal.to_string (c.inst, c.prefix @ zone, c.iter) []
let state_plane c =
  let state=Option.get c.st.state and live=Option.get c.st.time in
  if not c.host then state,live.frame else
    let plane=match state.host with Some plane->plane|None->let plane=create_state()in
      state.host<-Some plane;plane in
    plane,live.tick
let fn_id st = let id = st.nfns in st.nfns <- id + 1; id
let fn_call c fid count = match c.st.time with
  | None -> let k = !count in incr count; k
  | Some _ -> let k = Option.value ~default:0 (Hashtbl.find_opt c.st.fn_calls fid) in
      Hashtbl.replace c.st.fn_calls fid (k + 1); k

let key_of v = Value.key_of ~residual:(fun r -> r.rid) v
(* [coerce v to the type of w]: fold accumulators, reduce, assoc *)
let rec coerce_like w v =
  match w, v with
  | _, Residual _ | Residual _, _ -> v
  | Int _, (Float _ | Bool _) -> coerce_to Ty.Int v
  | Float _, (Int _ | Bool _) -> coerce_to Ty.Float v
  | Bool _, (Int _ | Float _) -> coerce_to Ty.Bool v
  | Vec3 _, (Int _ | Float _) -> coerce_to Ty.Vec3 v
  | Vec2 _, (Int _ | Float _) -> coerce_to Ty.Vec2 v
  | Vec4 _, (Int _ | Float _) -> coerce_to Ty.Vec4 v
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

let mk_node c ?(authored = 0) ?(ty = Ty.geometry) kind args =
  let st = c.st in
  if c.data then fail "E_ARRAY_TYPE" "Packed-array functions produce data, not graph nodes.";
  if st.time <> None then
    failf "E_LIVE_GEOMETRY" "%s makes geometry; geometry cannot be created while evaluating a live value." kind;
  let n = { id = st.nnodes; inst = c.inst; site = site c; iter = c.iter; kind; ty; args } in
  st.nodes <- n :: st.nodes;
  st.authored <- authored :: st.authored;
  st.nnodes <- st.nnodes + 1;
  Deferred (ty, n.id)

let catalog_call c ?(authored = 0) kind ctx args =
  if not (Context.supports_values ctx) || ctx = Context.material
  then Struct (kind, Context.result ctx, args) else mk_node c ~authored ~ty:(Context.result ctx) kind args

(* ---- the evaluator ---- *)

let lookup_field name v f =
  match v with
  | Vec2 (x, _) when f = "x" -> Float x
  | Vec2 (_, y) when f = "y" -> Float y
  | Vec3 (x, _, _) when f = "x" -> Float x
  | Vec3 (_, y, _) when f = "y" -> Float y
  | Vec3 (_, _, z) when f = "z" -> Float z
  | Vec4 (x, _, _, _) when f = "x" -> Float x
  | Vec4 (_, y, _, _) when f = "y" -> Float y
  | Vec4 (_, _, z, _) when f = "z" -> Float z
  | Vec4 (_, _, _, w) when f = "w" -> Float w
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

type cnode = Const of value | Dyn of (Frame_input.t -> value)
type cenv = { base : value Smap.t; over : cnode Smap.t; budget : int ref }

let compile_budget = 2048
let compile_residuals = ref true

let add_values a b = Value.arith "sum" ( +. ) a b

let run_node n t = match n with Const v -> v | Dyn f -> f t

let map_nodes f nodes = match List.for_all (function Const _ -> true | Dyn _ -> false) nodes with
  | true -> Const (f (List.map (function Const v -> v | Dyn _ -> assert false) nodes))
  | false -> Dyn (fun t -> f (List.map (fun n -> run_node n t) nodes))

let rec fast_of (r : residual) : (Frame_input.t -> value) option =
  if r.previous || not !compile_residuals then None else
  match r.fast with
  | Ready f -> Some f
  | Failed -> None
  | Untried ->
      r.fast <- Failed;  (* a residual met again while it compiles is a cycle: interpreted *)
      (match compile { base = r.renv; over = Smap.empty; budget = ref compile_budget } r.rterm with
       | node ->
           (* a residual read twice in one frame (a chain of sums) is evaluated once: it depends
              on the full frame snapshot, compared bit for bit *)
           let raw = run_node node in
           let last_t = ref (empty_live) and last = ref None in
           let f t =
             let bits = t in
             match !last with
             | Some v when Frame_input.equal bits !last_t -> v
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
  | W.Time -> Dyn (fun t -> Float t.t)
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
      let o = match Op.find op Context.value with
        | Some o when o.ctx = Context.value && o.shape = Op.Scalar -> o
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
       | _ ->
           let apply live vals = o.body ~live ~node:(fun _ _ -> raise Unsupported)
             (List.map2 (fun (n, _) v -> n, v) args vals) in
           if o.live then Dyn (fun live -> apply live (List.map (fun n -> run_node n live) nodes))
           else map_nodes (apply (empty_live)) nodes)
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
      then Const (collect (Array.map (fun n -> run_node n (empty_live)) bodies))
      else Dyn (fun t -> collect (Array.map (fun n -> run_node n t) bodies))
  | _ -> raise Unsupported

let rec concrete c v =
  match v with
  | Residual r -> (match c.st.time with None -> raise Needs_t | Some _ -> force_res c r)
  | Struct (_, Ty.Array _, _) ->
      (match c.st.time, c.st.resolve with
       | None, _ -> raise Needs_t
       | Some _, Some resolve -> (match resolve v with Ok v -> v
           | Error d -> raise (Fail (d.code, d.message, d.span)))
       | Some _, None -> fail "E_DATA_SOURCE" "This packed source needs its host's cooked data.")
  | v -> v

and force_res c r =
  match Hashtbl.find_opt c.st.memo r.rid with
  | Some v -> v
  | None ->
      let slow () =
        let c = {r.rc with st = c.st} in
        if r.previous then match r.rterm.node with
          | W.State {init; zone; _} -> state_previous c r.renv zone init
          | _ -> assert false
        else ev c r.renv r.rterm in
      let compiled = if c.st.compiled_residuals then fast_of r else None in
      let v = match c.st.time, compiled with
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
      (match st.observe_kernel, x.node with
       | Some observe, (W.Hof ((`Map | `Reduce), _) | W.Loop _ | W.Op {op = "array/sum"; _}) ->
           observe {rid = Atomic.fetch_and_add bulk_ids (-1); rterm = x;
             renv = capture x env; rc = c; previous = false; fast = Untried}
       | _ -> ());
      let saved = st.nodes and saved_n = st.nnodes and saved_authored = st.authored in
      (match ev_raw c env x with
       | v -> (match x.path with Some p -> note c p v | None -> ()); v
       | exception Needs_t ->
           (* ponytail: nodes made by the abandoned attempt are dropped, its records are kept *)
           st.nodes <- saved; st.nnodes <- saved_n; st.authored <- saved_authored;
           st.rids <- st.rids + 1;
           let r = Residual { rid = st.rids; rterm = x; renv = capture x env; rc = c; previous = false; fast = Untried } in
           (match x.node with W.State _ -> st.states <- r :: st.states | _ -> ());
           (* the record is the residual: a probe forces it at the time it shows *)
           (match x.path with Some p -> note c p r | None -> ()); r
       | exception Fail (code, msg, None) -> raise (Fail (code, msg, span_of x)))
  | Some live ->
      let evaluate () = match st.execute, x.node with
        | Some execute, (W.Hof ((`Map | `Reduce), _) | W.Loop _ | W.Op {op = "array/sum"; _}) ->
            st.rids <- st.rids + 1;
            let r = {rid = st.rids; rterm = x; renv = capture x env; rc = c; previous = false; fast = Untried} in
            (match execute r live with
             | Some (Ok v) -> v
             | Some (Error d) -> raise (Fail (d.code, d.message, d.span))
             | None -> ev_raw c env x)
        | _ -> ev_raw c env x in
      (match concrete c (evaluate ()) with
       | exception Fail (code, msg, None) -> raise (Fail (code, msg, span_of x))
       | v -> if st.record && c.rec_ then Option.iter (fun p -> note c p v) x.path; v)

and evs c env prefix ts = List.mapi (fun i t -> ev (sub c (prefix ^ string_of_int i)) env t) ts

and eval_named c env args =
  (* ponytail: O(n²) uniqueness scan bounded to 16 slots; wider/repeated
     signatures retain the hash path. Use declaration metadata if this
     small scan becomes measurable. *)
  let rec distinct = function
    | [] -> true
    | (name, _) :: rest -> not (List.mem_assoc name rest) && distinct rest in
  if List.compare_length_with args 16 <= 0 && distinct args then List.map (fun (name, term) ->
    name, ev (sub c name) env term) args
  else
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
        | Vec2 (a, b) -> [| Float a; Float b |]
        | Vec3 (a, b, d) -> [| Float a; Float b; Float d |]
        | Vec4 (a, b, d, e) -> [| Float a; Float b; Float d; Float e |]
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
  | W.Time -> (match c.st.time with Some t -> Float t.t | None -> raise Needs_t)
  | W.Vec [a; b] ->
      let f i t = num (concrete c (ev (sub c (string_of_int i)) env t)) in
      let a = f 0 a in let b = f 1 b in Vec2 (a, b)
  | W.Vec [ a; b; d ] ->
      let f i t = num (concrete c (ev (sub c (string_of_int i)) env t)) in
      let a = f 0 a in let b = f 1 b in let d = f 2 d in Vec3 (a, b, d)
  | W.Vec [a; b; d; e] ->
      let f i t = num (concrete c (ev (sub c (string_of_int i)) env t)) in
      let a = f 0 a in let b = f 1 b in let d = f 2 d in let e = f 3 e in Vec4 (a, b, d, e)
  | W.Vec cs -> failf "E_VECTOR" "A vector has 2, 3 or 4 components; this one has %d." (List.length cs)
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
      catalog_call c ~authored:x.form.id kind ctx vals
  | W.Op { op = "scene/merge"; args; skip = _ :: _ as skip } ->
      (* register L16: the arguments at skipped tuples are not evaluated *)
      let args = List.filteri (fun p _ -> not (List.mem (c.iter @ [ p ]) skip)) args in
      apply_op c ~authored:x.form.id "scene/merge" (eval_named c env args)
  | W.Op { op; args; _ } -> apply_op c ~authored:x.form.id op (eval_named c env args)
  | W.Call_fn { fn; args; body } ->
      let vals = evs c env "a" args in
      (match Smap.find_opt fn env with
       | Some (Fn f) -> call_fn ?body c f vals
       | _ -> apply_def ?body c fn vals)
  (* ponytail: a catalog kind used as a function value keeps the name as written; lowering resolves it. *)
  | W.Fn_ref name -> Fn (Named { name; ncalls = ref 0; fid = fn_id c.st })
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
  | W.Loop l -> loop c env ~out:x.ty l.kind l.accs l.clauses l.skip l.body l.zone
  | W.State {binder; init; step; zone} ->
      if c.geometry then fail "E_STATE_ELEMENT"
        "Frame state belongs to the workspace value lane; bind it outside a loop over cooked geometry.";
      let st = c.st in
      let previous = match st.time with
        | None ->
            st.rids <- st.rids + 1;
            Residual {rid = st.rids; rterm = x; renv = capture x env; rc = c; previous = true; fast = Failed}
        | Some _ -> state_previous c env zone init in
      let env = bind_pat c ~mk:(Some (fun n -> zone @ [":" ^ n])) ~whole:true binder previous env in
      (match st.time with
       | None -> ignore (ev c env step); raise Needs_t
       | Some _ ->
           let state,_ = state_plane c in let key = state_key c zone in
           match Smap.find_opt key state.next with
           | Some v -> v
           | None -> let v = coerce_to x.ty (ev c env step) in
               state.next <- Smap.add key v state.next; v)
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
  | W.Fn { params; body; zone; capture = original } ->
      (match original with
       | None -> Fn (Closure { params; body; env = capture x env; zone; calls = ref 0; fid = fn_id c.st; at = c })
       | Some original -> (match ev c env original with
           | Fn (Closure cl) -> Fn (Closure { cl with params; body })
           | Fn (Named n) -> Fn (Closure {params; body; zone; env = Smap.empty;
               calls = n.ncalls; fid = n.fid; at = c})
           | _ -> fail "E_TYPE" "A function port requires a function."))
  | W.Hof (kind, f :: rest) -> hof c env x kind f rest
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

and state_previous c env zone init =
  let state,frame = state_plane c in
  begin_frame state (Lazy.force c.st.source) frame;
  match Smap.find_opt (state_key c zone) state.before with
  | Some v -> v | None -> ev c env init

and apply_op c ?(authored = 0) name (vals : (string * value) list) : value =
  let o = match Op.find ~extra:c.st.ops name Context.value with
    | Some o -> o | None -> failf "E_UNKNOWN" "Unknown operator %s." name in
  let vals = match o.shape with
    | Op.Struct {splice = true} ->
        List.concat_map (fun (n, v) -> match concrete c v with
          | List xs -> List.map (fun x -> (n, x)) (Array.to_list xs)
          | v -> [ (n, v) ]) vals
    | _ -> vals in
  let vals = match o.shape with
    | Op.Scalar when o.ctx = Context.value -> List.map (fun (n, v) -> n, concrete c v) vals
    | _ -> vals in
  o.check vals;
  let live = match c.st.time with
    | Some live -> live
    | None when o.live -> raise Needs_t
    | None -> empty_live in
  o.body ~live ~node:(mk_node c ~authored ~ty:(o.out (List.map (fun (_, v) -> Value.ty_of v) vals))) vals

and apply_def ?body c name (vals : value list) : value =
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
  ev c' env (Option.value body ~default:d.body)

and call_fn ?body c f (vals : value list) : value =
  match f with
  | Closure cl ->
      if List.length vals <> List.length cl.params then
        failf "E_ARITY" "%s takes %d argument%s; got %d." (path_text cl.zone) (List.length cl.params)
          (if List.length cl.params = 1 then "" else "s") (List.length vals);
      if c.depth > max_depth then fail "E_DEPTH" "Call depth exceeds 64.";
      let k = fn_call c cl.fid cl.calls in
      let c' = { c with inst = cl.at.inst; prefix = cl.at.prefix; base = cl.zone; route = [];
                        iter = c.iter @ [ k ]; depth = c.depth + 1 } in
      let mk = Some (fun n -> cl.zone @ [ ":" ^ n ]) in
      let env = List.fold_left2 (fun env (pat, ty) v ->
        let v = match ty with Some t -> coerce_to t v | None -> v in
        bind_pat c' ~mk ~whole:true pat v env) cl.env cl.params vals in
      ev c' env (Option.value body ~default:cl.body)
  | Named { name; ncalls; fid } ->
      let k = fn_call c fid ncalls in
      let c' = { c with iter = c.iter @ [ k ] } in
      if Hashtbl.mem c.st.defs name then apply_def ?body c' name vals
      else begin
        match Op.find ~extra:c.st.ops name Context.value with
        | Some o ->
            let names = Array.of_list (List.map fst (o.signature.pos @ o.signature.opt)) in
            let named = List.mapi (fun i v ->
              (if i < Array.length names then names.(i)
               else match o.signature.rest with Some (name, _) -> name
                 | None -> "$" ^ string_of_int i), v) vals in
            apply_op c' o.name named
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

and hof c env term kind f rest =
  let out = term.W.ty in
  let packed = List.exists (fun (t : W.term) -> match t.ty with Ty.Array _ -> true | _ -> false) rest in
  let c = if packed then {c with data = true} else c in
  let saved_steps = c.st.steps and calls = ref 0 in
  let call fv values =
    if packed && !calls mod packed_block_size = 0 then c.st.steps <- saved_steps;
    incr calls; call_fn c fv values in
  let work () =
  let fv = match concrete c (ev (sub c "f") env f) with
    | Fn f -> f | _ -> fail "E_TYPE" "Expected a function." in
  (match kind, fv with
   | `Map, Closure cl when c.st.record && c.rec_ && (match out with Ty.Array _ -> true | _ -> false) ->
       c.st.rids <- c.st.rids + 1;
       let call = Residual {rid = c.st.rids; rterm = term; renv = capture term env; rc = c;
         previous = false; fast = Untried} in
       note c (cl.zone @ ["~calls"]) (Record ["offset", Int !(cl.calls); "call", call])
   | _ -> ());
  let lists_of ts = List.mapi (fun i t ->
    let v = concrete c (ev (sub c ("l" ^ string_of_int i)) env t) in
    match v with List xs -> Array.length xs, (fun k -> xs.(k))
    | Float_array _ | Vec2_array _ | Vec3_array _ | Vec4_array _ -> array_length v, array_get v
    | _ -> fail "E_TYPE" "Expected a list or packed array.") ts in
  match kind, rest with
  | `Map, ls ->
      let ls = lists_of ls in
      let n = List.fold_left (fun n (length, _) -> min n length) max_int ls in
      let n = if ls = [] then 0 else n in
      let item k = call fv (List.map (fun (_, get) -> get k) ls) in
      (match out with Ty.Array e -> array_init e n (fun k -> concrete c (item k))
       | _ -> List (join_values (Array.init n item)))
  | `Filter, [ l ] ->
      let count, get = List.hd (lists_of [ l ]) in
      (match out with
       | Ty.Array e ->
           let indices = Array.make count 0 and kept = ref 0 in
           for i = 0 to count - 1 do
             if truthy (concrete c (call fv [get i])) then begin
               indices.(!kept) <- i; incr kept end
           done;
           array_init e !kept (fun i -> get indices.(i))
       | _ ->
           let xs = Array.init count get in
           List (Array.of_list (List.filter (fun x -> truthy (concrete c (call fv [x]))) (Array.to_list xs))))
  | `Sort_by, [ l ] ->
      let count, get = List.hd (lists_of [ l ]) in
      (match out with
       | Ty.Array e ->
           let keys = Array.init count (fun i -> num (concrete c (call fv [get i]))) in
           let indices = Array.init count Fun.id in
           Array.stable_sort (fun a b -> Float.compare keys.(a) keys.(b)) indices;
           array_init e count (fun i -> get indices.(i))
       | _ ->
           let xs = Array.init count get in
           let keyed = Array.mapi (fun i x -> (num (concrete c (call fv [x])), i, x)) xs in
           let sorted = List.stable_sort (fun (a, _, _) (b, _, _) -> compare a b) (Array.to_list keyed) in
           List (Array.of_list (List.map (fun (_, _, x) -> x) sorted)))
  | `Reduce, [ init; l ] ->
      let init = ev (sub c "init") env init in
      let count, get = List.hd (lists_of [ l ]) in
      let acc = ref init in
      for i = 0 to count - 1 do
        let value = call fv [!acc; get i] in
        acc := widen_like !acc (if packed then concrete c value else value)
      done;
      !acc
  | _ -> fail "E_ARITY" "A higher-order form got the wrong number of arguments." in
  if packed then Fun.protect ~finally:(fun () -> c.st.steps <- saved_steps) work else work ()

and loop c env ~out kind accs clauses skip body zone =
  let packed = List.exists (fun (_, (e : W.term)) -> match e.ty with Ty.Array _ -> true | _ -> false) clauses in
  let c = if packed then {c with data = true} else c in
  let saved_steps = c.st.steps in
  let cz = { c with base = zone; route = [] } in
  let init = match accs with
    | [ (_, e) ] -> Some (ev (sub cz "init") env e)
    | _ -> None in
  let acc_pat = match accs with [ (p, _) ] -> Some p | _ -> None in
  let acc = ref init in
  let k = ref 0 and outs = ref [] and total = ref None and over_geometry = ref None in
  let clauses = Array.of_list clauses in
  let n = Array.length clauses in
  let width = match out with Ty.Array Ty.Vec2 -> 2 | Ty.Array Ty.Vec3 -> 3
    | Ty.Array Ty.Vec4 -> 4 | Ty.Array _ -> 1 | _ -> 0 in
  let data = ref (if width = 0 then [||] else Array.make (32 * width) 0.) and used = ref 0 in
  let collect v =
    if width = 0 then outs := v :: !outs else begin
      let v = concrete c v in
      if !used = Array.length !data / width then begin
        let next = Array.make (min Sys.max_floatarray_length (2 * Array.length !data)) 0. in
        if Array.length next / width <= !used then fail "E_ARRAY_RANGE" "Array exceeds native storage bounds.";
        Array.blit !data 0 next 0 (Array.length !data); data := next
      end;
      let at = width * !used in
      (match width, v with
       | 1, v -> (!data).(at) <- fin "array loop" (num v)
       | 2, Vec2 (x,y) -> (!data).(at) <- fin "array loop" x;
           (!data).(at + 1) <- fin "array loop" y
       | 3, Vec3 (x,y,z) -> (!data).(at) <- fin "array loop" x;
           (!data).(at + 1) <- fin "array loop" y; (!data).(at + 2) <- fin "array loop" z
       | 4, Vec4 (x,y,z,w) -> (!data).(at) <- fin "array loop" x;
           (!data).(at + 1) <- fin "array loop" y; (!data).(at + 2) <- fin "array loop" z;
           (!data).(at + 3) <- fin "array loop" w
       | _, (Int _ | Float _ | Bool _) -> let x = fin "array loop" (num v) in
           for j = 0 to width - 1 do (!data).(at + j) <- x done
       | _ -> fail "E_ARRAY_TYPE" "Packed loop element has the wrong vector width.");
      incr used
    end in
  let mk = Some (fun v -> zone @ [ ":" ^ v ]) in
  let add a b =
    add_values (concrete c a) (concrete c b) in
  let rec go ci env items =
    if ci = n then begin
      if packed && !k mod packed_block_size = 0 then c.st.steps <- saved_steps;
      if not packed && !k >= max_iterations then
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
      let v = if packed then concrete c v else v in
      (match kind, !acc with
       | (`Fold | `Scan), Some a ->
           let a' = widen_like a v in
           acc := Some a';
           if kind = `Scan then collect a'
       | `Sum, _ -> total := Some (match !total with None -> v | Some t -> add t v)
       | _ -> collect v);
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
           let count, get = match v with List xs -> Array.length xs, (fun i -> xs.(i))
             | Float_array _ | Vec2_array _ | Vec3_array _ | Vec4_array _ -> array_length v, array_get v
             | _ -> fail "E_TYPE" "Expected a list or packed array." in
           for i = 0 to count - 1 do
             let item = get i in
             go (ci + 1) (bind_pat c ~mk:None ~whole:false p item env) (item :: items)
           done)
    end in
  let work () =
  go 0 env [];
  match !over_geometry with Some v -> v | None ->
  match kind with
  | `Fold -> Option.get !acc
  | `Sum -> (match !total with None -> Int 0 | Some t -> concrete c t)
  | `For | `Scan ->
      if width = 0 then List (join_values (Array.of_list (List.rev !outs)))
      else let data = Array.sub !data 0 (!used * width) in
        (match width with 2 -> Vec2_array data | 3 -> Vec3_array data
         | 4 -> Vec4_array data | _ -> Float_array data) in
  if packed then Fun.protect ~finally:(fun () -> c.st.steps <- saved_steps) work else work ()


(* W8: [(for [p (sop/point_list g)] body)].  The count is known only when [g] cooks, so
   the body is evaluated once, as a template, with the element unknown: a point is a residual
   read from [st.elems] when forced, a piece a plan node [zone/element].  The template's nodes
   (ids [lo] .. [hi - 1]) are not part of the graph; the plan node [zone/points] or
   [zone/pieces] (a [Deferred (Geometry, id)], the merge of the elements) tells lowering how to cook them. *)
and geometry_loop c cz env op fs p body zone =
  if c.st.time <> None then failf "E_LIVE_GEOMETRY" "%s iterates geometry while evaluating a live value." (path_text zone);
  let src = match List.assoc_opt "geometry" fs with
    | Some (Deferred ((Ty.Named "geometry"), id)) -> id | _ -> failf "E_TYPE" "%s: %s needs geometry." (path_text zone) op in
  let key = List.assoc_opt "key" fs in
  let points = op = "sop/point_list" in
  let ci = { cz with iter = c.iter @ [ 0 ]; geometry = true } in
  let ekey = element_key zone in
  let lo = c.st.nnodes in
  let elem, elem_arg =
    if points then begin
      c.st.rids <- c.st.rids + 1;
      let term = { W.path = None; ty = Ty.Vec3; node = W.Ref_binding (ekey, []); form = body.W.form } in
      Residual { rid = c.st.rids; rterm = term; renv = Smap.empty; rc = ci; previous = false; fast = Untried }, Text ekey
    end else
      (match mk_node (sub ci "element") "zone/element" [] with
       | Deferred ((Ty.Named "geometry"), id) as g -> g, Int id
       | _ -> assert false) in
  let mk = Some (fun v -> zone @ [ ":" ^ v ]) in
  let env = bind_pat ci ~mk ~whole:true p elem env in
  let v = ev ci env body in
  let root = match v with
    | Deferred ((Ty.Named "geometry"), id) -> id
    | Residual _ -> failf "E_ZONE" "%s: what a loop over geometry builds cannot depend on the element; only arguments can." (path_text zone)
    | _ -> failf "E_TYPE" "%s: the body of a loop over geometry returns geometry." (path_text zone) in
  let hi = c.st.nnodes in
  mk_node c (if points then "zone/points" else "zone/pieces")
    ((("geometry", Deferred (Ty.geometry, src)) :: (match key with Some k -> [ ("key", k) ] | None -> []))
     @ [ ("body", Int root); ("lo", Int lo); ("hi", Int hi); ("element", elem_arg) ])

and graph_value ?(rec_ = true) c name over =
  let st = c.st in
  let g = match Hashtbl.find_opt st.graphs name with
    | Some g -> g | None -> failf "E_UNKNOWN_GRAPH" "Unknown graph reference: %s." name in
  let over = List.map (fun (n, v) ->
    match List.find_opt (fun (m, _, _) -> m = n) g.inputs with
    | Some (_, ty, _) ->
        if not (Ty.fits (Value.ty_of v) ty) then
          failf "E_INPUT_TYPE" "Graph input %s of %s needs %s; got %s." n name
            (Ty.to_string ty) (Ty.to_string (Value.ty_of v));
        (n, coerce_to ty v)
    | None -> failf "E_INPUT_UNKNOWN" "Graph %s has no input %s." name n) over in
  if List.length over <> List.length (List.sort_uniq String.compare (List.map fst over)) then
    failf "E_INPUT_DUPLICATE" "Graph %s has duplicate input overrides." name;
  let key = name ^ "|" ^ String.concat "," (List.sort compare
    (List.map (fun (n, v) -> n ^ "=" ^ key_of v) over)) in
  let run inst =
    if c.depth > max_depth then fail "E_DEPTH" "Call depth exceeds 64.";
    let c0 = { st; inst; prefix = []; base = [ name ]; route = []; iter = []; depth = c.depth + 1; rec_ = rec_; data = c.data; geometry = c.geometry; host=g.context=Context.host } in
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
  { time = None; resolve = None; execute = None; compiled_residuals = true; observe_kernel = None;
    source = lazy (Digest.string (fst (Lisp.print ws.W.source))); state = None; states = [];
    nfns = 0; fn_calls = Hashtbl.create 1;
    steps = 0; nodes = []; authored = []; nnodes = 0; cells = []; cache = Hashtbl.create 8;
    memo = Hashtbl.create 1; rids = 0; record; elems = Smap.empty; recs = Hashtbl.create 64; graphs; defs;
    kind_fns = ws.W.kind_fns; ops = ws.ops }

let live_state (st : st) ~state ?(elems = Smap.empty) (l : live) =
  { st with time = Some l; state = Some state; observe_kernel = None;
    steps = 0; memo = Hashtbl.create 16;
    fn_calls = Hashtbl.create 16; record = false; elems }

let root st = { st; inst = -1; prefix = []; base = []; route = []; iter = []; depth = 0; rec_ = true; data = false; geometry = false; host=false }

let protect f =
  try Ok (f ()) with
  | Fail (code, msg, span) -> Error (diagnostic code msg span)
  | Needs_t -> Error (diagnostic "E_EVAL" "A live value was needed while evaluating statically." None)
  | Stack_overflow -> Error (diagnostic "E_DEPTH" "Evaluation is nested too deeply." None)
  | Out_of_memory -> Error (diagnostic "E_ARRAY_MEMORY" "Frame data exceeds available memory." None)

let static_impl ?(record = false) ?(inputs = []) ?observe ws =
  Phase_timer.measure Evaluate (fun () ->
  protect (fun () ->
    if List.length inputs <> List.length (List.sort_uniq String.compare (List.map fst inputs)) then
      fail "E_INPUT_DUPLICATE" "A graph receives more than one input override set.";
    List.iter (fun (name, _) ->
      if not (List.exists (fun (g : W.graph) -> g.name = name) ws.W.graphs) then
        failf "E_UNKNOWN_GRAPH" "Unknown graph input target: %s." name) inputs;
    List.iter (fun (_, ins) -> List.iter (fun (_, value) -> Value.validate value) ins) inputs;
    let st = new_state ~record ws in
    st.observe_kernel <- observe;
    Fun.protect ~finally:(fun () -> st.observe_kernel <- None) (fun () ->
    let c = root st in
    let results = List.map (fun (g : W.graph) ->
      let over = Option.value (List.assoc_opt g.name inputs) ~default:[] in
      (g.name, graph_value c g.name over)) ws.W.graphs in
    let instances = st.cells |> List.rev |> List.map (fun cell ->
      { graph = cell.cgraph; default = cell.cdefault; inputs = cell.cinputs; result = cell.cresult }) |> Array.of_list in
    let records = Hashtbl.fold (fun p (_, l) acc -> (p, List.rev l) :: acc) st.recs []
      |> List.sort (fun (a, _) (b, _) -> compare a b) in
    { plan = { instances; nodes = Array.of_list (List.rev st.nodes) }; results; records;
      authored = Array.of_list (List.rev st.authored);
      states = List.rev st.states })))

let static ?record ?inputs ws = static_impl ?record ?inputs ws

let rec is_live = function
  | Residual _ -> true
  | Struct (_, Ty.Array _, _) -> true
  | List xs -> Array.exists is_live xs
  | Record fs | Struct (_, _, fs) -> List.exists (fun (_, v) -> is_live v) fs
  | _ -> false

let rec dependent frame = function
  | Residual r -> term_dependent frame r.rc.st r.renv r.rterm
  | List xs -> Array.exists (dependent frame) xs
  | Record fs | Struct (_, _, fs) -> List.exists (fun (_, v) -> dependent frame v) fs
  | Fn (Closure cl) -> term_dependent frame cl.at.st cl.env cl.body
  | _ -> false

and term_dependent frame st env (term : W.term) =
  let term_dep = term_dependent frame st env in
  let any = List.exists term_dep in
  let fields fs = any (List.map snd fs) in
  let definition name = match Hashtbl.find_opt st.defs name with
    | Some g -> term_dep g.body
    | None -> Option.fold ~none:false ~some:(dependent frame) (Smap.find_opt name env) in
  match term.node with
  | W.Time -> frame
  | W.State _ -> true
  | W.Ref_binding (name, _) ->
      Option.fold ~none:false ~some:(dependent frame) (Smap.find_opt name env)
  | W.Op {op; args; _} ->
      (frame && (Option.get (Op.find ~extra:st.ops op Context.value)).live) || fields args
  | W.Call {args; _} | W.Record args -> fields args
  | W.Call_fn {fn; args; body} ->
      definition fn || Option.fold ~none:false ~some:term_dep body || any args
  | W.Fn_ref name -> definition name
  | W.Graph_ref {graph; inputs} -> fields inputs ||
      (match Hashtbl.find_opt st.graphs graph with
       | Some g -> term_dep g.body ||
           List.exists (fun (_, _, d) -> Option.fold ~none:false ~some:term_dep d) g.inputs
       | None -> false)
  | W.Vec ts | W.List_lit ts | W.Str ts | W.List_op (_, ts) | W.Hof (_, ts) -> any ts
  | W.Let (bindings, body) -> any (List.map snd bindings) || term_dep body
  | W.Loop {accs; clauses; body; _} -> any (List.map snd (accs @ clauses)) || term_dep body
  | W.If (c, a, b) -> any [c; a; b]
  | W.Cond (arms, d) -> any (d :: List.concat_map (fun (a, b) -> [a; b]) arms)
  | W.Case (s, arms, d) -> any (s :: d :: List.map snd arms)
  | W.Fn {capture = Some original; _} -> term_dep original
  | W.Fn {body; _} | W.Expanded {body; _} | W.Get (body, _) | W.Bypass body -> term_dep body
  | W.Assoc (r, args) -> term_dep r || fields args
  | W.Lit _ | W.Text _ | W.Nil -> false

let frame_dependent = dependent true
let state_dependent = dependent false

(* one live state per call, made from the first residual met *)
let with_live ?state ?elems ?resolve ?execute ?(compiled = true) (l : live) (f : (residual -> ctx) -> 'a) : ('a, Diagnostic.t) result =
  let state = Option.value ~default:(create_state ()) state in
  let saved = fork_state state in
  let elems = Option.map Smap.of_list elems in
  let live = ref None in
  let ctx_of r =
    let st = match !live with
      | Some s -> s
      | None -> let s = { (live_state r.rc.st ~state ?elems l) with compiled_residuals = compiled; resolve; execute } in
          live := Some s; s in
    { r.rc with st } in
  match Frame_input.validate l with
  | Error message -> Error (Diagnostic.error ~code:"E_FRAME" message)
  | Ok () ->
      let result = protect (fun () -> f ctx_of) in
      (match result with Ok _ -> () | Error _ ->
        restore_state state saved);
      result

let residual_eval ?state ?elems r ~live =
  with_live ?state ?elems live (fun ctx_of -> let c = ctx_of r in force_res c r)

let force_with ?state ?elems ?resolve ?execute ?compiled v ~live =
  if not (is_live v) then Ok v
  else
    with_live ?state ?elems ?resolve ?execute ?compiled live (fun ctx_of ->
      let rec go v = match v with
        | Residual r -> let c = ctx_of r in go (force_res c r)
        | Struct (_, Ty.Array _, _) -> (match resolve with
            | Some resolve -> (match resolve v with Ok v -> v
                | Error d -> raise (Fail (d.code, d.message, d.span)))
            | None -> fail "E_DATA_SOURCE" "This packed source needs its host's cooked data.")
        | List xs -> List (Array.map go xs)
        | Record fs -> Record (List.map (fun (n, x) -> (n, go x)) fs)
        | Struct (n, ty, fs) -> Struct (n, ty, List.map (fun (k, x) -> (k, go x)) fs)
        | v -> v in
      go v)

let force ?state ?elems ?resolve v ~live = force_with ?state ?elems ?resolve v ~live

let run ?record ?inputs ?state ?live ~time ws =
  let state = Option.value ~default:(create_state ()) state in
  match static ?record ?inputs ws with
  | Error _ as e -> e
  | Ok s ->
      let live = Option.value ~default:(Frame_input.at_time time) live in
      let exception Stop of Diagnostic.t in
      let f v = match force ~state v ~live with Ok v -> v | Error d -> raise (Stop d) in
      transaction state (fun () -> try
         let states = List.map f s.states in
         Ok { s with states;
              plan = { nodes = Array.map (fun n -> { n with args = List.map (fun (k, v) -> (k, f v)) n.args }) s.plan.nodes;
                       instances = Array.map (fun i -> { i with inputs = List.map (fun (k, v) -> (k, f v)) i.inputs;
                                                                result = f i.result }) s.plan.instances };
              results = List.map (fun (n, v) -> (n, f v)) s.results;
              records = List.map (fun (p, l) -> (p, List.map (fun (it, v) -> (it, f v)) l)) s.records }
       with Stop d -> Error d)

let show v = show_with Fun.id v

module Private = struct
  let static_with_kernels = static_impl
  let map_function ~(signature : Ty.fn_signature) fn arrays = protect (fun () ->
    match fn with
    | Named _ -> fail "E_KERNEL_FORM" "A bulk function needs an instantiated local body."
    | Closure cl ->
    if List.compare_lengths cl.params arrays <> 0 then
      fail "E_ARITY" "Bulk function inputs differ from its parameter count.";
    if List.compare_lengths signature.params arrays <> 0
        || not (List.for_all2 (fun ty value -> Value.ty_of value = Ty.Array ty) signature.params arrays) then
      fail "E_ARRAY_TYPE" "Bulk function columns must match its declared parameter types.";
    List.iter (function Float_array _ | Vec2_array _ | Vec3_array _ | Vec4_array _ -> ()
      | _ -> fail "E_ARRAY_TYPE" "Bulk function inputs must be packed arrays.") arrays;
    List.iter Value.validate arrays;
    let counts = List.map array_length arrays in
    if List.exists (( <> ) (Option.value ~default:0 (List.nth_opt counts 0))) counts then
      fail "E_ARRAY_RANGE" "Bulk function inputs must have equal counts.";
    if not (Ty.fits cl.body.ty signature.result) then
      fail "E_KERNEL_FORM" "Bulk function body differs from its declared result type.";
    let result = match signature.result with
      | Ty.Float | Vec2 | Vec3 | Vec4 as ty -> ty
      | _ -> fail "E_KERNEL_FORM" "Bulk functions must return float, vec2, vec3 or vec4 data." in
    let binding name ty = W.{path = None; ty; node = Ref_binding (name, []); form = cl.body.form} in
    let inputs = List.mapi (fun i value -> "$kernel-input:" ^ string_of_int i, value) arrays in
    let function_name = "$kernel-function" in
    let term = W.{path = None; ty = Ty.Array result; form = cl.body.form;
      node = Hof (`Map, binding function_name (Ty.Fn None) ::
        List.map (fun (name, value) -> binding name (Value.ty_of value)) inputs)} in
    Residual {rid = Atomic.fetch_and_add bulk_ids (-1); rterm = term;
      renv = List.fold_left (fun env (name, value) -> Smap.add name value env)
        (Smap.singleton function_name (Fn fn)) inputs;
      rc = {cl.at with data = true; rec_ = false}; previous = false; fast = Untried})
  let free_names term = Names.elements (free_names term)
  let free_name_walks () = Atomic.get free_walks
  let force_with_executor ?state ?elems ?resolve ~execute v ~live =
    force_with ?state ?elems ?resolve ~execute v ~live
  let function_bindings = function Closure cl -> Smap.bindings cl.env | Named _ -> []
  let function_id = function Closure cl -> cl.fid | Named n -> n.fid
  let state_values state = List.map snd (Smap.bindings state.before) @ List.map snd (Smap.bindings state.next)
  let function_body = function Closure cl -> Some (cl.params, cl.body) | Named _ -> None
  let function_scope = function
    | Closure cl -> Some (cl.at.prefix @ cl.zone, cl.at.iter) | Named _ -> None
  type residual_view = {
    term : W.term;
    bindings : (string * value) list;
    site : W.path;
    owner : W.path;
    iter : int list;
    instance : int;
    previous : bool;
  }
  let residual_view r = {term = r.rterm; bindings = Smap.bindings r.renv;
    site = site r.rc; owner = r.rc.base; iter = r.rc.iter; instance = r.rc.inst; previous = r.previous}
  let residual_id r = r.rid
  let residual_ops r = r.rc.st.ops
  let force_reference ?state ?elems ?resolve v ~live = force_with ?state ?elems ?resolve ~compiled:false v ~live
  let closure_available r = Option.is_some (fast_of r)
  let eval_term ?state ?elems ?resolve r term ~live =
    with_live ?state ?elems ?resolve ~compiled:false live (fun ctx_of ->
      let c = ctx_of r in concrete c (ev c r.renv term))
  let map_probe ?state ?resolve ?(offset = 0) r ~live =
    with_live ?state ?resolve ~compiled:false live (fun ctx_of ->
      let c = {(ctx_of r) with rec_ = false} in
      match r.rterm.node with
      | W.Hof (`Map, f :: sources) ->
          let fn = match concrete c (ev c r.renv f) with
            | Fn fn -> fn | _ -> fail "E_TYPE" "Expected a function." in
          let arrays = List.map (fun source -> concrete c (ev c r.renv source)) sources in
          let size = function List xs -> Array.length xs | v -> array_length v in
          let count = List.fold_left (fun n v -> min n (size v)) max_int arrays in
          let count = if arrays = [] then 0 else count in
          let get v k = match v with List xs -> xs.(k) | v -> array_get v k in
          let at k = protect (fun () ->
            if k < 0 || k >= count then fail "E_LIST_RANGE" "Probe index is outside this map.";
            let st = {c.st with record = true; recs = Hashtbl.create 16;
              fn_calls = Hashtbl.create 1; memo = Hashtbl.create 16; steps = 0} in
            let fid = match fn with Closure cl -> cl.fid | Named n -> n.fid in
            Hashtbl.add st.fn_calls fid (offset + k);
            ignore (concrete {c with st; rec_ = true}
              (call_fn {c with st; rec_ = true} fn (List.map (fun v -> get v k) arrays)));
            Hashtbl.fold (fun path (_, values) all -> (path, List.rev values) :: all) st.recs []) in
          count, at
      | _ -> fail "E_TYPE" "A map probe needs a checked map.")
  let compile_residuals = compile_residuals
  let rec compiled = function
    | Residual { fast = Ready _; _ } -> 1
    | List xs -> Array.fold_left (fun n x -> n + compiled x) 0 xs
    | Record fs | Struct (_, _, fs) -> List.fold_left (fun n (_, x) -> n + compiled x) 0 fs
    | _ -> 0
end
