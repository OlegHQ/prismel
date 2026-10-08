module Operators = Operators
module Packed = Packed
module E = Flow.Eval
module W = Flow.Workspace
module V = Flow.Value
module Ty = Flow.Ty

type id = W.path * int list
module Count = struct
  type t = Static of int | Data of id | Unknown
end
type rate = Static | Frame | Event
type precision = Exact | Approx
type tier = Interp | Closure | Cpu_kernel | Gpu | Gpu_compile | Gpu_readback | Cooked
module Cost = struct
  type tier_cost = {fixed : float; per_element : float}
  (* P4 measured CPU table, performance-log "P4 residual pruning and costs".
     CPU packed-map endpoints are 1,024 and 1M elements at one domain; the
     closure row is one compiled scalar expression. Only legal tiers compete.
     ponytail: one affine model per tier, not an instruction-aware scheduler;
     fit per-operation models only if placement mistakes are measured. *)
  let table = function
    | Interp -> {fixed=0.;per_element=0.710282087 /. 1_000_000.}
    | Closure -> {fixed=0.000000170;per_element=0.}
    | Cpu_kernel ->
        let per_element = (0.016522884 -. 0.000040054) /. (1_000_000. -. 1024.) in
        {fixed=0.000040054 -. per_element *. 1024.;per_element}
    (* P5 native rows, performance-log "P5 native calibration" (Apple M1,
       `bench_kernel --gpu` and `bench_gpu`): pack, upload and synchronized
       dispatch at 1,024 and 1M elements, explicit readback, cold compile. *)
    | Gpu ->
        let per_element = (0.020215034 -. 0.000437975) /. (1_000_000. -. 1024.) in
        {fixed=0.000437975 -. per_element *. 1024.;per_element}
    | Gpu_readback ->
        let per_element = (0.007947922 -. 0.000010014) /. (1_000_000. -. 1024.) in
        {fixed=0.000010014 -. per_element *. 1024.;per_element}
    | Gpu_compile -> {fixed=0.008223057;per_element=0.}
    | Cooked -> {fixed=infinity;per_element=0.}
  let estimate tier ~count =
    if count < 0 then invalid_arg "Flow_ir.Cost.estimate: negative count";
    let cost = table tier in cost.fixed +. cost.per_element *. float count
  (* Per element beyond the producer, from the same log's editor rows at
     10,000 and 1M circles: CPU instance building and upload against the
     resident GPU circle conversion. A display sink competes route by route. *)
  let display_sink tier ~count =
    if count < 0 then invalid_arg "Flow_ir.Cost.display_sink: negative count";
    float count *. (match tier with
      | Gpu -> (0.028567791 -. 0.001480103) /. 990_000. -. (table Gpu).per_element
      | _ -> (0.903350830 -. 0.010123968) /. 990_000. -. (table Cpu_kernel).per_element)
  let cheapest ~legal ~count = match legal with
    | [] -> invalid_arg "Flow_ir.Cost.cheapest: no legal tier"
    | first :: rest -> List.fold_left (fun best tier ->
        if estimate tier ~count < estimate best ~count then tier else best) first rest
  let packed ~count = cheapest ~legal:[Interp;Cpu_kernel] ~count
end
module Gpu = struct
  type value={identity:int;count:int;width:int;stamp:int64;gpu_seconds:float option}
  type kernel={run:Packed.Private.inputs -> (value,Flow.Diagnostic.t)result;
    readback:value -> (E.value,Flow.Diagnostic.t)result}
  type backend={cost:Packed.t -> count:int -> float option;
    prepare:Packed.t -> (kernel,Flow.Diagnostic.t)result}
  type policy=Measured | Qualification
  let current : backend option Domain.DLS.key=Domain.DLS.new_key(fun()->None)
  let current_policy : policy Domain.DLS.key=Domain.DLS.new_key(fun()->Measured)
  let with_backend ?(policy=Measured) backend run = let previous=Domain.DLS.get current
    and previous_policy=Domain.DLS.get current_policy in
    Domain.DLS.set current(Some backend);
    Domain.DLS.set current_policy policy;
    Fun.protect ~finally:(fun()->Domain.DLS.set current previous;
      Domain.DLS.set current_policy previous_policy)run
end
type source = Constant of E.value | Frame_field of string | Input of string | State_previous of E.residual
type body = Operation of string | Vector | Field of string | List_value
  | Record_value of string list | Struct_value of string * Ty.t * string list
  | Reference of E.residual | Packed_map of Packed.t | Readback
type kernel = { body : body; elementwise : bool; requires_exact : bool }
type sink = Display of string | Export | Sop_input | State_seed | Cache_key
type kind = Source of source | Kernel of kernel
  | Opaque of string * Flow.Check.kernel_facts option | Sink of sink
type edge = { name : string; node : int }
type node = { id : id; ty : Ty.t; count : Count.t; rate : rate; precision : precision;
  kind : kind; args : edge list; scope : int list; invariant : bool;
  provenance : id list; tier : tier }
type t = { nodes : node array; roots : int array; groups : int array array }
type execution = { owner : id; sites : (int * W.path * int list) list;
  tier : tier; seconds : float }
module Profile = struct
  type t = {clock : unit -> float; executions : execution list Atomic.t}
  let create ~clock = {clock; executions = Atomic.make []}
  let executions profile = Atomic.get profile.executions
  let rec record profile execution =
    let previous = executions profile in
    let rec keep n = function
      | [] -> [] | _ when n = 0 -> []
      | old :: rest when old.sites = execution.sites && old.tier=execution.tier -> keep n rest
      | old :: rest -> old :: keep (n - 1) rest in
    (* ponytail: 512 recent groups, a linear scan once per group; index if
       profiling many small groups measurably costs a frame. *)
    let next = execution :: keep 511 previous in
    if not (Atomic.compare_and_set profile.executions previous next) then record profile execution
end

let rate_join a b = match a, b with
  | Event, _ | _, Event -> Event | Frame, _ | _, Frame -> Frame | _ -> Static
let singleton_groups nodes = Array.init (Array.length nodes) (fun i -> [|i|])
let graph nodes roots = {nodes; roots; groups = singleton_groups nodes}

(* Indices are topological; refuse corrupt direct IR before any pass follows edges. *)
let validate ir =
  let n = Array.length ir.nodes in
  Array.iteri (fun i node ->
    List.iter (fun e -> if e.node < 0 || e.node >= i then
      invalid_arg "Flow_ir: arguments must reference earlier nodes") node.args;
    match node.count with Count.Static n when n < 0 ->
      invalid_arg "Flow_ir: negative count" | _ -> ()) ir.nodes;
  Array.iter (fun i -> if i < 0 || i >= n then invalid_arg "Flow_ir: invalid root") ir.roots

let rec plain = function
  | E.Fn _ | Residual _ | Deferred _ -> false
  | List xs -> Array.for_all plain xs
  | Record fs | Struct (_, _, fs) -> List.for_all (fun (_, v) -> plain v) fs
  | _ -> true

let share_key node =
  let kind = match node.kind with
    | Source (Constant v) when plain v -> Some ("constant", Marshal.to_string v [Marshal.No_sharing])
    | Source (Frame_field name) -> Some ("frame", name)
    | Kernel {body = Operation name; _} -> Some ("op", name)
    | Kernel {body = Vector; _} -> Some ("vector", "")
    | Kernel {body = Field field; _} -> Some ("field", field)
    | Kernel {body = Readback; _} -> Some ("exact", "")
    | Kernel {body = List_value; _} -> Some ("list", "")
    | Kernel {body = Record_value fields; _} -> Some ("record", Marshal.to_string fields [])
    | Kernel {body = Struct_value (name, ty, fields); _} ->
        Some ("struct", Marshal.to_string (name, ty, fields) [])
    | _ -> None in
  Option.map (fun kind ->
    let requirements = match node.kind with Kernel k -> k.elementwise, k.requires_exact | _ -> false, false in
    Marshal.to_string (kind, requirements, node.ty, node.count, node.rate,
      node.precision, node.scope, node.args) [Marshal.No_sharing]) kind

let share ir =
  validate ir;
  let n = Array.length ir.nodes in
  let remap = Array.make n 0 and kept = Array.copy ir.nodes and count = ref 0 in
  let seen = Hashtbl.create n in
  Array.iteri (fun i node ->
    let node = {node with args = List.map (fun e -> {e with node = remap.(e.node)}) node.args} in
    let key = share_key node in
    match Option.bind key (Hashtbl.find_opt seen) with
    | Some existing ->
        remap.(i) <- existing;
        let old = kept.(existing) in
        kept.(existing) <- {old with provenance = List.sort_uniq compare (old.provenance @ node.provenance)}
    | None ->
        let index = !count in incr count; remap.(i) <- index; kept.(index) <- node;
        Option.iter (fun key -> Hashtbl.add seen key index) key) ir.nodes;
  graph (Array.sub kept 0 !count) (Array.map (Array.get remap) ir.roots)

let hoist ir =
  validate ir;
  let nodes = Array.copy ir.nodes in
  Array.iteri (fun i node ->
    match node.kind with
    | Kernel {body = (Reference _ | Packed_map _); _} | Source _ | Opaque _ | Sink _ -> ()
    | Kernel _ when node.invariant && node.rate = Static
        && List.for_all (fun e -> nodes.(e.node).rate = Static && nodes.(e.node).scope = []) node.args ->
        nodes.(i) <- {node with scope = []}
    | _ -> ()) ir.nodes;
  {ir with nodes; groups = singleton_groups nodes}

let prune ir =
  validate ir;
  let keep = Array.make (Array.length ir.nodes) false in
  Array.iter (fun i -> keep.(i) <- true) ir.roots;
  for i = Array.length ir.nodes - 1 downto 0 do
    if keep.(i) then List.iter (fun e -> keep.(e.node) <- true) ir.nodes.(i).args
  done;
  let remap = Array.make (Array.length ir.nodes) (-1) and count = ref 0 in
  Array.iteri (fun i live -> if live then (remap.(i) <- !count; incr count)) keep;
  let nodes = Array.copy ir.nodes in
  Array.iteri (fun i node -> if keep.(i) then
    nodes.(remap.(i)) <- {node with args = List.map (fun e -> {e with node = remap.(e.node)}) node.args}) ir.nodes;
  graph (Array.sub nodes 0 !count) (Array.map (Array.get remap) ir.roots)

let fusible = function Kernel {elementwise = true; body = (Operation _ | Vector | Field _); _} -> true | _ -> false
let same_count a b = match a, b with
  | Count.Static a, Count.Static b -> a = b
  | Count.Data a, Count.Data b -> a = b
  | _ -> false
let fuse ir =
  validate ir;
  let n = Array.length ir.nodes in
  let uses = Array.make n 0 and owner = Array.init n Fun.id and barriers = Array.make n 0 in
  Array.iter (fun i -> uses.(i) <- uses.(i) + 1) ir.roots;
  let barrier = ref 0 in
  Array.iteri (fun i node ->
    (match node.kind with Sink _ | Opaque _ -> incr barrier | _ -> ());
    barriers.(i) <- !barrier;
    List.iter (fun e -> uses.(e.node) <- uses.(e.node) + 1) node.args) ir.nodes;
  Array.iteri (fun i node -> if fusible node.kind then
    List.iter (fun e ->
      let before = ir.nodes.(e.node) in
      if uses.(e.node) = 1 && fusible before.kind && same_count before.count node.count
          && before.rate = node.rate && before.precision = node.precision
          && before.scope = node.scope && barriers.(e.node) = barriers.(i)
      then owner.(e.node) <- i) node.args) ir.nodes;
  for i = n - 1 downto 0 do if owner.(i) <> i then owner.(i) <- owner.(owner.(i)) done;
  let groups = Array.make n [] in
  for i = n - 1 downto 0 do groups.(owner.(i)) <- i :: groups.(owner.(i)) done;
  {ir with groups = Array.of_list (Array.fold_right (fun g acc ->
    if g = [] then acc else Array.of_list g :: acc) groups [])}

let place ?(approx=W.Paths.empty) ?(gpu_cost=fun _ ~count:_ -> None) ir =
  validate ir;
  let nodes = Array.copy ir.nodes in
  let exception Refused of Flow.Diagnostic.t in
  try
    Array.iteri (fun i node ->
      let gpu=match node.kind,node.count with
        |Kernel{body=Packed_map packed;_},Count.Static count when count>=1024
          && List.exists(fun(path,_)->W.Paths.mem path approx)node.provenance ->
            let view=Packed.Private.view packed in
            view.collecting && view.zipped && view.skip=[||] &&
              Option.fold ~none:false ~some:(fun seconds->Float.is_finite seconds && seconds>=0.
                && seconds<Cost.estimate (Cost.packed ~count) ~count)(gpu_cost packed ~count)
        |_->false in
      let approximate = List.exists (fun e -> nodes.(e.node).precision = Approx) node.args in
      let readback = match node.kind with Kernel {body = Readback; _} -> true | _ -> false in
      let forbidden = match node.kind with
        | Opaque _ | Sink (Export | Sop_input | State_seed | Cache_key) | Source (State_previous _) -> true
        | Kernel k -> k.requires_exact && not readback
        | _ -> false in
      if approximate && forbidden then
        raise (Refused (Flow.Diagnostic.error ~code:"E_APPROX_SINK"
          "Approximate values require (exact x) before catalog calls, exports, state or cache keys."));
      let precision = if readback then Exact else if approximate || gpu then Approx else node.precision in
      let tier = match node.kind with
        | Opaque _ -> Cooked
        | Kernel {body = Packed_map _; _} when gpu -> Gpu
        | Kernel {body = Readback; _} when approximate -> Gpu_readback
        | Kernel {body = Packed_map _; _} ->
            (match node.count with Count.Static count -> Cost.packed ~count | _ -> Cpu_kernel)
        | Kernel {body = Reference r; _} -> if E.Private.closure_available r then
            Cost.cheapest ~legal:[Interp;Closure] ~count:(match node.count with Count.Static n -> n | _ -> 1)
            else Interp
        | Kernel _ -> Closure
        | _ -> Interp in
      nodes.(i) <- {node with precision; tier}) ir.nodes;
    Ok {ir with nodes}
  with Refused d -> Error d

let optimize ir = Result.map fuse (place (prune (share (hoist ir))))

module Residuals = Hashtbl.Make (struct
  type t = E.residual
  let equal a b = a == b
  let hash = E.Private.residual_id
end)
type builder = {
  mutable rev : node list;
  mutable count : int;
  mutable checks : int list;
  slots : (int, node) Hashtbl.t;
  deferred : (int, int) Hashtbl.t;
  residuals : int Residuals.t;
  live : W.Paths.t;
  invariant : W.Paths.t;
  count_source : Packed.count_source;
}
let builder ?(count_source = fun _ _ -> None) live invariant = {rev = []; count = 0; checks = []; slots = Hashtbl.create 64;
  deferred = Hashtbl.create 64; residuals = Residuals.create 64; live; invariant; count_source}
let authored (path, iter) = match path with
  | namespace :: path when String.starts_with ~prefix:"@instance:" namespace -> path, iter
  | _ -> path, iter
let identity instance (path, iter) =
  if instance < 0 then path, iter else ("@instance:" ^ string_of_int instance) :: path, iter
let at_path (path, iter) replacement = match path with
  | namespace :: _ when String.starts_with ~prefix:"@instance:" namespace -> namespace :: replacement, iter
  | _ -> replacement, iter
let add ?(provenance = []) b id ty count kind args rate =
  let i = b.count in b.count <- i + 1;
  let rate = List.fold_left (fun r e -> rate_join r (Hashtbl.find b.slots e.node).rate) rate args in
  let origin = authored id in
  let rate = if W.Paths.mem (fst origin) b.live then rate_join Frame rate else rate in
  let scope = match kind, rate with Source (Constant _), Static -> [] | _ -> snd id in
  let provenance = List.sort_uniq compare (origin :: List.map authored provenance) in
  let n = {id; ty; count; kind; args; rate; precision = Exact; scope;
    invariant = W.Paths.mem (fst origin) b.invariant; provenance; tier = Interp} in
  b.rev <- n :: b.rev; Hashtbl.add b.slots i n; i
let kernel body = Kernel {body; elementwise = true; requires_exact = false}
let child (path, iter) name = path @ [name], iter
let value_count = function
  | E.Float_array xs -> Count.Static (Array.length xs)
  | Vec2_array xs -> Count.Static (Array.length xs / 2)
  | Vec3_array xs -> Count.Static (Array.length xs / 3)
  | Vec4_array xs -> Count.Static (Array.length xs / 4)
  | List xs -> Count.Static (Array.length xs)
  | _ -> Count.Static 1
let type_count id = function
  | Ty.Array _ | Ty.List _ -> Count.Data id | _ -> Count.Static 1
let term_count id (term : W.term) = type_count id term.ty
let rec value_ty = function
  | E.Residual r -> (E.Private.residual_view r).term.ty
  | List xs -> Ty.List (Array.fold_left (fun ty v ->
      Option.value ~default:Ty.Any (Ty.join ty (value_ty v))) Ty.Any xs)
  | Record fs -> Ty.Record (List.map (fun (name, v) -> name, value_ty v) fs)
  | v -> V.ty_of v

let rec value b id = function
  | E.Deferred (_, old) as v ->
      (match Hashtbl.find_opt b.deferred old with Some i -> i
       | None -> add b id (V.ty_of v) (Count.Static 1) (Source (Constant v)) [] Static)
  | Residual r -> residual b r
  | List xs ->
      let args = Array.mapi (fun i v -> {name = string_of_int i; node = value b (child id (string_of_int i)) v}) xs |> Array.to_list in
      add b id (value_ty (E.List xs)) (Count.Static (Array.length xs)) (kernel List_value) args Static
  | Record fs -> fields b id (value_ty (E.Record fs)) (Record_value (List.map fst fs)) fs
  | Struct (name, ty, fs) -> fields b id ty (Struct_value (name, ty, List.map fst fs)) fs
  | v -> add b id (V.ty_of v) (value_count v) (Source (Constant v)) [] Static
and fields b id ty body fs =
  let args = List.mapi (fun i (name, v) -> {name; node = value b (child id (name ^ "#" ^ string_of_int i)) v}) fs in
  add b id ty (type_count id ty) (kernel body) args Static
and residual b r =
  match Residuals.find_opt b.residuals r with
  | Some i -> i
  | None ->
      let view = E.Private.residual_view r in
      let id = identity view.instance (view.site, view.iter) in
      let make_reference () =
        let kind = if view.previous then Source (State_previous r)
          else Kernel {body = Reference r; elementwise = false; requires_exact = true} in
        let rate = if E.frame_dependent (E.Residual r) || E.state_dependent (E.Residual r) then Frame else Static in
        add b id view.term.ty (term_count id view.term) kind [] rate in
      let index = if view.previous || E.state_dependent (E.Residual r) then make_reference () else
        let exception Unsupported in
        let saved_checks = b.checks in
        let rec term env id (t : W.term) =
          let id = match t.path with Some p -> at_path id p | None -> id in
          let count = term_count id t in
          let args args = List.mapi (fun i (name, t) -> {name;
            node = term env (child id (name ^ "#" ^ string_of_int i)) t}) args in
          match t.node with
          | W.Lit (Param.Int_value n) -> value b id (E.Int n)
          | Lit (Param.Float_value n) -> value b id (E.Float n)
          | Lit (Param.Bool_value n) -> value b id (E.Bool n)
          | Text text -> value b id (E.Text text)
          | Nil -> value b id E.No_geo
          | Time -> add b id Ty.Float count (Source (Frame_field "t")) [] Frame
          | Ref_binding (name, fs) ->
              let input = match List.assoc_opt name env with
                | Some (`Index i) -> i
                | Some (`Value v) -> value b (child id ("@capture:" ^ name)) v
                | None -> raise Unsupported in
              List.fold_left (fun i field ->
                let ty = match (Hashtbl.find b.slots i).ty with
                  | Ty.Vec2 | Vec3 | Vec4 -> Ty.Float
                  | Ty.Record fields -> Option.value ~default:Ty.Any (List.assoc_opt field fields)
                  | _ -> Ty.Any in
                add b (child id field) ty (type_count (child id field) ty)
                  (kernel (Field field)) [{name = "value"; node = i}] Static) input fs
          | Vec ts when List.mem (List.length ts) [2;3;4] -> add b id t.ty count (kernel Vector)
              (args (List.mapi (fun i t -> string_of_int i, t) ts)) Static
          | (Hof ((`Map | `Reduce), _) | Loop _ | Op {op = "array/sum"; _}) ->
              (match Packed.compile ~count_source:b.count_source r t with
               | None -> raise Unsupported
               | Some program ->
                   let count = match Packed.static_count program with
                     | Some n -> Count.Static n | None -> Count.Data (Option.value ~default:id (Packed.count_origin program)) in
                   let rate = if E.frame_dependent (E.Residual r) then Frame else Static in
                   let kind = Kernel {body = Packed_map program;
                     elementwise = Packed.elementwise program; requires_exact = true} in
                   let provenance = List.map (fun (instance, site, iter) -> identity instance (site, iter))
                     (Packed.provenance program) in
                   add ~provenance b id t.ty count kind [] rate)
          | Op {op; args = ts; _} ->
              let op = match Flow.Op.find ~extra:(E.Private.residual_ops r) op Flow.Context.value with
                | Some op when op.ctx = Flow.Context.value && op.shape = Flow.Op.Scalar
                    && (op == Operators.noise3 || Option.fold ~none:false ~some:((==) op)
                      (Flow.Op.find op.name Flow.Context.value)) -> op
                | _ -> raise Unsupported in
              let kind, rate = if op.live then Source (Frame_field op.name),
                  (if op.name = "frame/events" || op.name = "frame/input" then Event else Frame)
                else if op.name = "exact" then kernel Readback, Static
                else kernel (Operation op.name), Static in
              add b id t.ty count kind (args ts) rate
          | Let (bindings, result) ->
              let env = List.fold_left (fun env (pattern, t) -> match pattern with
                | W.Name name ->
                    let index = term env (child id name) t in
                    (* Unused evaluation can still fail. Only literal constants are total. *)
                    (match (Hashtbl.find b.slots index).kind with
                     | Source (Constant _) -> () | _ -> b.checks <- index :: b.checks);
                    (name, `Index index) :: env
                | _ -> raise Unsupported) env bindings in
              term env (child id "@result") result
          | Get (record, field) -> add b id t.ty count (kernel (Field field))
              [{name = "value"; node = term env (child id "value") record}] Static
          | Expanded {body; _} | Bypass body -> term env id body
          | _ -> raise Unsupported in
        try term (List.map (fun (name, v) -> name, `Value v) view.bindings) id view.term
        with Unsupported -> b.checks <- saved_checks; make_reference () in
      Residuals.add b.residuals r index; index

let finish b roots = graph (Array.of_list (List.rev b.rev))
  (Array.append roots (Array.of_list (List.rev b.checks)))
let of_evaluation ws catalog evaluation =
  let b = builder ws.W.live ws.W.invariant in
  let facts = Hashtbl.create (List.length catalog.Flow.Check.kinds) in
  List.iter (fun (kind : Flow.Check.kind) ->
    Hashtbl.replace facts kind.qualified kind.facts;
    List.iter (fun alias -> Hashtbl.replace facts alias kind.facts) kind.aliases) catalog.kinds;
  Array.iter (fun (n : E.node) ->
    let id = identity n.inst (n.site, n.iter) in
    let args = List.mapi (fun i (name, v) -> {name; node = value b (child id (name ^ "#" ^ string_of_int i)) v}) n.args in
    let kind = if Flow.Op.is_display_kind n.kind then Sink (Display n.kind)
      else Opaque (n.kind, Option.join (Hashtbl.find_opt facts n.kind)) in
    let index = add b id n.ty (Count.Data id) kind args Static in
    Hashtbl.replace b.deferred n.id index) evaluation.E.plan.nodes;
  let roots = List.mapi (fun i (name, v) -> value b ([name; "@result"; string_of_int i], []) v) evaluation.results in
  let states = List.mapi (fun i v -> value b (["@state"; string_of_int i], []) v) evaluation.states in
  finish b (Array.of_list (roots @ states))

module Executor = struct
  type program = { ir : t; value : E.value; dataflow : bool; templates : Packed.t list Atomic.t;
    count_source : Packed.count_source; profile : Profile.t option; approx:W.Paths.t;
    sink:sink option;mutable gpu_kernel:(Gpu.backend*Packed.t*Gpu.kernel)option }
  let compile ?profile ?(approx=W.Paths.empty) ?sink ?(count_source = fun _ _ -> None) v =
    let b = builder ~count_source W.Paths.empty W.Paths.empty in
    let root = value b (["@value"], []) v in
    Result.map (fun ir ->
      let dataflow = Array.exists (function
        | {kind = Kernel {body = Packed_map _; _}; tier = Cpu_kernel; _} -> true
        | _ -> false) ir.nodes in
      {ir; value = v; dataflow; templates = Atomic.make []; count_source; profile;
        approx;sink;gpu_kernel=None}) (optimize (finish b [|root|]))
  let graph p = p.ir
  let force ?state ?elems ?resolve ?(reference = false) program ~live =
    let packed_ran = ref false in
    let measure = Option.map (fun profile -> profile.Profile.clock,
      (fun packed ~seconds ~reference ->
        packed_ran := true;
        let sites = Packed.provenance packed in
        let _, path, iter = Packed.site packed in
        let owner = path, iter in
        Profile.record profile {owner; sites; seconds; tier = if reference then Interp else Cpu_kernel})) program.profile in
    let state = Option.value ~default:(E.create_state ()) state in
    let fell_back = ref reference in
    let fallback () = fell_back := true; E.Private.force_reference ~state ?elems ?resolve program.value ~live in
    let force_with_packed value ~live =
      let execute r live =
        let cached = Atomic.get program.templates in
        let prepared = match List.find_map (fun p -> Packed.rebind p r) cached with
          | Some p -> Some p
          | None ->
              let prepared = Packed.compile_template ~count_source:program.count_source r (E.Private.residual_view r).term in
              Option.iter (fun p ->
                let rec take n = function [] -> [] | _ when n = 0 -> [] | p :: rest -> p :: take (n - 1) rest in
                ignore (Atomic.compare_and_set program.templates cached (p :: take 31 cached))) prepared;
              prepared in
        match prepared with
        | Some p when not (Option.fold ~none:false ~some:(fun count -> Cost.packed ~count <> Cpu_kernel) (Packed.static_count p)) ->
            Some (Packed.force ~state ?elems ?resolve ?measure p ~live)
        | _ -> None in
      E.Private.force_with_executor ~state ?elems ?resolve ~execute value ~live in
    let run () = if reference then fallback () else if not program.dataflow then force_with_packed program.value ~live else
    match Frame_input.validate live with
    | Error _ -> fallback ()
    | Ok () ->
        let exception Refused of Flow.Diagnostic.t in
        let get = function Ok v -> v | Error d -> raise (Refused d) in
        let run () =
          let values = Array.make (Array.length program.ir.nodes) E.No_geo in
          Array.iteri (fun i node ->
            let args = List.map (fun e -> e.name, values.(e.node)) node.args in
            let arg () = snd (List.hd args) in
            let apply op = match Flow.Op.find ~extra:Operators.all op Flow.Context.value with
              | Some op -> op.body ~live ~node:(fun _ _ -> V.fail "E_IR" "Scalar IR cannot create catalog nodes.") args
              | None -> V.fail "E_IR" "Unknown scalar operator." in
            values.(i) <- match node.kind with
              | Source (Constant v) -> v
              | Source (Frame_field "t") -> E.Float live.t
              | Source (Frame_field name) -> apply name
              | Source (State_previous r) -> get (E.Private.force_reference ~state ?elems ?resolve (E.Residual r) ~live)
              | Kernel {body = Reference r; _} ->
                  get (force_with_packed (E.Residual r) ~live)
              | Kernel {body = Operation name; _} -> apply name
              | Kernel {body = Packed_map program; _} ->
                  get (if node.tier = Cpu_kernel then Packed.force ~state ?elems ?resolve ?measure program ~live
                    else Packed.reference ~state ?elems ?resolve program ~live)
              | Kernel {body = Readback; _} -> arg ()
              | Kernel {body = Vector; _} ->
                  (match List.map (fun (_, v) -> V.num v) args with
                   | [x; y] -> E.Vec2 (x,y) | [x; y; z] -> E.Vec3 (x, y, z)
                   | [x; y; z; w] -> E.Vec4 (x,y,z,w) | _ -> V.fail "E_IR" "Invalid vector.")
              | Kernel {body = Field field; _} ->
                  (match arg (), field with
                   | E.Vec3 (x, _, _), "x" | Vec3 (_, x, _), "y" | Vec3 (_, _, x), "z" -> E.Float x
                   | E.Vec2 (x,_), "x" | Vec2 (_,x), "y" -> E.Float x
                   | E.Vec4 (x,_,_,_), "x" | Vec4 (_,x,_,_), "y"
                   | Vec4 (_,_,x,_), "z" | Vec4 (_,_,_,x), "w" -> E.Float x
                   | Record fields, name -> List.assoc name fields
                   | _ -> V.fail "E_FIELD" "Invalid field.")
              | Kernel {body = List_value; _} -> E.List (Array.of_list (List.map snd args))
              | Kernel {body = Record_value fields; _} -> E.Record (List.map2 (fun name (_, v) -> name, v) fields args)
              | Kernel {body = Struct_value (name, ty, fields); _} ->
                  E.Struct (name, ty, List.map2 (fun name (_, v) -> name, v) fields args)
              | Source (Input _) | Opaque _ | Sink _ -> V.fail "E_IR" "This cone needs its environment.") program.ir.nodes;
          values.(program.ir.roots.(0)) in
        let result = E.transaction state (fun () ->
          try Ok (run ()) with
          | V.Fail (code, message, span) -> Error (Flow.Diagnostic.error ?span ~code message)
          | Refused d -> Error d
          | Not_found | Invalid_argument _ -> Error (Flow.Diagnostic.error ~code:"E_IR" "Unsupported IR value.")) in
        match result with Ok _ -> result | Error _ -> fallback () in
    let started = Option.map (fun profile -> profile.Profile.clock ()) program.profile in
    let result = run () in
    Option.iter (fun profile -> if not !packed_ran then begin
      let root = program.ir.nodes.(program.ir.roots.(0)) in
      let tier = if !fell_back then Interp else root.tier in
      let instance = match fst root.id with
        | namespace :: _ when String.starts_with ~prefix:"@instance:" namespace ->
            int_of_string (String.sub namespace 10 (String.length namespace - 10))
        | _ -> -1 in
      let sites = match root.kind with
        | Kernel {body = Packed_map packed; _} -> Packed.provenance packed
        | _ -> List.map (fun (path, iter) -> instance, path, iter) root.provenance in
      Profile.record profile {owner = authored root.id; sites; tier;
        seconds = max 0. (profile.clock () -. Option.get started)}
    end) program.profile;
    result
  type displayed=Cpu of E.value | Gpu of Gpu.value
  let try_display ?state ?elems ?resolve ?(reference=false) ?policy program ~live =
    let policy=Option.value ~default:(Domain.DLS.get Gpu.current_policy) policy in
    let cpu()=Ok None in
    if reference then cpu()else match Domain.DLS.get Gpu.current with None->cpu()|Some backend->
    let root=program.ir.nodes.(program.ir.roots.(0))in
    let packed,readback=match root.kind with
      |Kernel{body=Packed_map packed;_}->Some packed,false
      |Kernel{body=Readback;_}->(match root.args with
        |[{node;_}]->(match program.ir.nodes.(node).kind with
          |Kernel{body=Packed_map packed;_}->Some packed,true|_->None,false)
        |_->None,false)
      |_->None,false in
    match packed with None->cpu()|Some packed->
      let _,site,_=Packed.site packed in
      let view=Packed.Private.view packed in
      if not(W.Paths.mem site program.approx) || not(view.collecting && view.zipped && view.skip=[||])
        then cpu()else
      let cheaper count= count>=1024 && (policy=Gpu.Qualification ||
        Option.fold ~none:false ~some:(fun seconds->Float.is_finite seconds && seconds>=0.
          && seconds+.(if readback then Cost.estimate Gpu_readback ~count else Cost.display_sink Gpu ~count)
            <Cost.estimate(Cost.packed ~count) ~count
             +.(if readback then 0. else Cost.display_sink Cpu_kernel ~count))(backend.cost packed ~count))in
      (* Static cardinality lets unmeasured placement decline before allocating
         producer inputs, especially the million-element exact SOP value lane. *)
      if Option.fold ~none:false ~some:(fun count->not(cheaper count))(Packed.static_count packed)
        then cpu()else
      let (let*)=Result.bind in
      let* inputs=Packed.Private.prepare ?state ?elems ?resolve packed ~live in
      if not(cheaper inputs.count) then cpu()else
      let* ()=match program.sink,readback with
        |Some(Display _),_ |_,true->Ok()
        |_->Error(Flow.Diagnostic.error ~code:"E_APPROX_SINK"
          "GPU arrays require a display sink or (exact x) before CPU, SOP, state, export or cache use.")in
      let profile ?(seconds=fun _->None) tier run=
        let start=Option.map(fun p->p.Profile.clock())program.profile in
        let result=run()in
        let elapsed=match result with Ok value->seconds value|Error _->None in
        Option.iter(fun p->let _,path,iter=Packed.site packed in
          Profile.record p {owner=(path,iter);sites=Packed.provenance packed;tier;
            seconds=(match elapsed with Some value when Float.is_finite value && value>=0.->value
              |_->max 0.(p.clock()-.Option.get start))})program.profile;result in
      let* kernel=match program.gpu_kernel with
        |Some(previous,p,kernel)when previous==backend && p==packed->Ok kernel
        |_->profile Gpu_compile(fun()->Result.map(fun kernel->program.gpu_kernel<-Some(backend,packed,kernel);kernel)
            (backend.prepare packed))in
      let* output=profile ~seconds:(fun output->output.Gpu.gpu_seconds) Gpu(fun()->kernel.run inputs)in
      if readback then profile Gpu_readback(fun()->Result.map(fun value->Some(Cpu value))(kernel.readback output))
      else Ok(Some(Gpu output))
  let force_display ?state ?elems ?resolve ?(reference=false) ?policy program ~live =
    Result.bind (try_display ?state ?elems ?resolve ~reference ?policy program ~live) (function
      |Some value->Ok value
      |None->Result.map(fun value->Cpu value)(force ?state ?elems ?resolve ~reference program ~live))
end
