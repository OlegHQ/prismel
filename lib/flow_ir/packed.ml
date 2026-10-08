module E = Flow.Eval
module W = Flow.Workspace
module V = Flow.Value
module Ty = Flow.Ty

type binary = Flow.Packed_ops.binary = Add | Sub | Mul | Div | Mod | Pow | Min | Max | Lt | Le | Gt | Ge | Eq | And | Or
type unary = Flow.Packed_ops.unary = Sin | Cos | Sqrt | Abs | Not
type instruction = Const of float | Input of int * int * int
  | Uniform of int * int | Frame of string | Accumulator of int
  | Binary of binary * int * int | Unary of unary * int | Noise3 of int * int * int * int * int
  | Select of int * int * int
type expression = { registers : int array; constant : E.value option }
type iteration = Zip | Product
type result = Collect | Sum of bool | Accumulate of W.term * bool
type origin = W.path * int list
type count_source = E.residual -> W.term -> origin option
type t = { residual : E.residual; term : W.term; sources : (E.residual * W.term) array;
  widths : int array; uniforms : E.value array; code : instruction array;
  dependent : bool array; output : int array; count : int option;
  iteration : iteration; result : result; skip : int array;
  stages : (E.residual * W.term) list; fusion : bool; dynamic : bool;
  body : W.term; binding_fn : string option; uniform_names : (string * string list) array;
  count_source : count_source; origin : origin option;
  sites : (int * W.path * int list) list }
exception Unsupported

let captured_value bindings name fields =
  let value = match List.assoc_opt name bindings with Some v -> v | None -> raise Unsupported in
  List.fold_left (fun value field -> match value, field with
    | E.Record fs, field | Struct (_, _, fs), field ->
        (match List.assoc_opt field fs with Some v -> v | None -> raise Unsupported)
    | E.Vec3 (x, _, _), "x" | Vec3 (_, x, _), "y" | Vec3 (_, _, x), "z" -> E.Float x
    | _ -> raise Unsupported) value fields

let count_of residual (s : W.term) = match s.node with
  | W.Ref_binding (name, fields) ->
      (try match captured_value (E.Private.residual_view residual).bindings name fields with
       | E.Float_array _ | Vec3_array _ as v -> Some (V.array_length v) | _ -> None
       with Unsupported -> None)
  | Op {op = ("array/float" | "array/vec3" | "array/range"); args; _} ->
      (match List.assoc_opt "count" args with
       | Some {node = W.Lit (Param.Int_value n); _} when n >= 0 -> Some n | _ -> None)
  | _ -> None

let count_of_sources iteration counts =
  let combine a b = match iteration with Zip -> min a b | Product ->
    if b <> 0 && a > max_int / b then raise Unsupported else a * b in
  if counts = [||] || (iteration = Product && Array.exists ((=) (Some 0)) counts) then Some 0
  else if Array.for_all Option.is_some counts then
    Some (Array.fold_left (fun n c -> combine n (Option.get c))
      (if iteration = Zip then max_int else 1) counts) else None

let rec pattern_names = function
  | W.Name name -> [name] | W.Keys names -> names | W.Seq ps -> List.concat_map pattern_names ps
let rec reads_names names (term : W.term) =
  let any = List.exists (reads_names names) and fields fs = List.map snd fs in
  match term.node with
  | W.Ref_binding (name, _) -> List.mem name names
  | Fn {params; body; _} ->
      let bound = List.concat_map (fun (p, _) -> pattern_names p) params in
      reads_names (List.filter (fun n -> not (List.mem n bound)) names) body
  | Let (bindings, body) ->
      let rec loop names = function
        | [] -> reads_names names body
        | (p, t) :: rest -> reads_names names t ||
            loop (List.filter (fun n -> not (List.mem n (pattern_names p))) names) rest in
      loop names bindings
  | Op {args; _} | Call {args; _} | Record args -> any (fields args)
  | Call_fn {args; _} -> any args
  | Graph_ref {inputs; _} -> any (fields inputs)
  | Vec ts | List_lit ts | Str ts | List_op (_, ts) | Hof (_, ts) -> any ts
  | Loop {accs; clauses; body; _} -> any (body :: fields (accs @ clauses))
  | State {init; step; _} -> any [init; step]
  | If (c, a, b) -> any [c; a; b]
  | Cond (arms, d) -> any (d :: List.concat_map (fun (a, b) -> [a; b]) arms)
  | Case (s, arms, d) -> any (s :: d :: fields arms)
  | Get (body, _) | Bypass body | Expanded {body; _} -> reads_names names body
  | Assoc (r, args) -> any (r :: fields args)
  | Lit _ | Text _ | Nil | Time | Fn_ref _ -> false

let rec compile_impl ?(fusion = true) ?(dynamic = false)
    ?(count_source = fun _ _ -> None) residual (term : W.term) =
  let view = E.Private.residual_view residual in
  if view.previous || E.state_dependent (E.Residual residual) then None else
  try
    let function_body (f : W.term) = match f.node with
      | W.Fn {params; body; _} -> params, body, view.bindings
      | W.Ref_binding (name, []) ->
          (match List.assoc_opt name view.bindings with
           | Some (E.Fn f) -> (match E.Private.function_body f with
               | Some (params, body) -> params, body, E.Private.function_bindings f
               | None -> raise Unsupported)
           | _ -> raise Unsupported)
      | _ -> raise Unsupported in
    let params, accumulator, body, sources, bindings, iteration, result, skip = match term.node with
      | W.Hof (`Map, f :: sources) ->
          let params, body, bindings = function_body f in
          params, None, body, sources, bindings, Zip, Collect, []
      | W.Hof (`Reduce, [f; seed; source]) ->
          let params, body, bindings = function_body f in
          (match params with
           | acc :: params -> params, Some acc, body, [source], bindings, Zip, Accumulate (seed, false), []
           | _ -> raise Unsupported)
      | W.Loop {kind; accs; clauses; body; skip; _} ->
          let accumulator, result = match kind, accs with
            | `For, [] -> None, Collect | `Sum, [] -> None, Sum false
            | (`Fold | `Scan), [p, seed] -> Some (p, None), Accumulate (seed, kind = `Scan)
            | _ -> raise Unsupported in
          List.map (fun (p, _) -> p, None) clauses, accumulator, body,
            List.map snd clauses, view.bindings, Product, result, skip
      | W.Op {op = "array/sum"; args = [_, source]; _} ->
          let ty = match source.ty with Ty.Array ty -> ty | _ -> raise Unsupported in
          let body = {source with ty; node = W.Ref_binding ("@item", [])} in
          [W.Name "@item", None], None, body, [source], view.bindings, Zip, Sum true, []
      | _ -> raise Unsupported in
    let sources = Array.of_list sources in
    let binding_fn = match term.node with
      | W.Hof (_, {node = W.Ref_binding (name, []); _} :: _) -> Some name | _ -> None in
    let names = List.filter_map (function W.Name name, _ -> Some name | _ -> None)
      (params @ Option.to_list accumulator) in
    (* ponytail: correlated clauses stay interpreted; lower their changing source counts before tiling them. *)
    if iteration = Product && Array.exists (reads_names names) sources then raise Unsupported;
    let widths = Array.map (fun (s : W.term) -> match s.ty with
      | Ty.Array Ty.Float -> 1 | Ty.Array Ty.Vec3 -> 3 | _ -> raise Unsupported) sources in
    if Array.length sources <> List.length params then raise Unsupported;
    let code = ref [] and size = ref 0 and uniforms = ref [] and nuniforms = ref 0 and uniform_names = ref [] in
    let dependent = Array.make 64 false in
    let emit instruction =
      (* ponytail: cap scratch at 512 KiB per block; measure larger bodies before raising it. *)
      if !size >= 64 then raise Unsupported;
      let id = !size in incr size; code := instruction :: !code;
      dependent.(id) <- (match instruction with
        | Accumulator _ -> true | Binary (_, a, b) -> dependent.(a) || dependent.(b)
        | Unary (_, a) -> dependent.(a) | Noise3 (a, b, c, _, _) | Select (a, b, c) -> dependent.(a) || dependent.(b) || dependent.(c)
        | _ -> false); id in
    let literal v =
      let data = match v with
        | E.Int n -> [|float n|] | Float f -> [|f|] | Bool b -> [|if b then 1. else 0.|] | Vec3 (x, y, z) -> [|x; y; z|]
        | _ -> raise Unsupported in
      {registers = Array.map (fun f -> emit (Const f)) data; constant = Some v} in
    let input i width = {registers = Array.init width (fun j -> emit (Input (i, width, j))); constant = None} in
    let uniform name v = match v with
      | E.Residual _ | E.Int _ | Float _ | Bool _ | Vec3 _ when dynamic || E.is_live v ->
          let ty = match v with E.Residual r -> (E.Private.residual_view r).term.ty | v -> V.ty_of v in
          let width = if ty = Ty.Vec3 then 3 else if List.mem ty [Ty.Float; Ty.Int; Ty.Bool] then 1 else raise Unsupported in
          let i = !nuniforms in incr nuniforms; uniforms := v :: !uniforms;
          uniform_names := name :: !uniform_names;
          {registers = Array.init width (fun j -> emit (Uniform (i, j))); constant = None}
      | _ -> literal v in
    let env = List.mapi (fun i (pattern, annotation) ->
      match pattern with
      | W.Name name when annotation = None || annotation = Some (if widths.(i) = 3 then Ty.Vec3 else Ty.Float) ->
          name, input i widths.(i)
      | _ -> raise Unsupported) params in
    let env = match accumulator, result with
      | Some (W.Name name, annotation), Accumulate (seed, _) ->
          let width = match seed.ty with Ty.Vec3 -> 3 | Ty.Float | Ty.Int -> 1 | _ -> raise Unsupported in
          if annotation <> None && annotation <> Some seed.ty
              && not (seed.ty = Ty.Int && annotation = Some Ty.Float) then raise Unsupported;
          (name, {registers = Array.init width (fun i -> emit (Accumulator i)); constant = None}) :: env
      | None, _ -> env | _ -> raise Unsupported in
    let captures = Hashtbl.create 16 in
    let captured name fields = match Hashtbl.find_opt captures (name, fields) with
      | Some e -> e
      | None ->
          let e = uniform (name, fields) (captured_value bindings name fields) in
          Hashtbl.add captures (name, fields) e; e in
    let field e = function
      | "x" when Array.length e.registers = 3 -> {registers = [|e.registers.(0)|]; constant = None}
      | "y" when Array.length e.registers = 3 -> {registers = [|e.registers.(1)|]; constant = None}
      | "z" when Array.length e.registers = 3 -> {registers = [|e.registers.(2)|]; constant = None}
      | _ -> raise Unsupported in
    let binary name = match Flow.Packed_ops.binary name with Some op -> op | None -> raise Unsupported in
    let unary name = match Flow.Packed_ops.unary name with Some op -> op | None -> raise Unsupported in
    let component e i = e.registers.(if Array.length e.registers = 1 then 0 else i) in
    let rec expression env (t : W.term) =
      match t.node with
      | W.Lit (Param.Int_value n) -> literal (E.Int n)
      | Lit (Param.Float_value f) -> literal (E.Float f)
      | Lit (Param.Bool_value b) -> literal (E.Bool b)
      | Ref_binding (name, fields) ->
          (match List.assoc_opt name env with
           | Some e -> List.fold_left field e fields | None -> captured name fields)
      | Time -> {registers = [|emit (Frame "t")|]; constant = None}
      | Vec ts when List.length ts = 3 ->
          let components = List.map (expression env) ts in
          if not (List.for_all (fun e -> Array.length e.registers = 1) components) then raise Unsupported;
          {registers = Array.of_list (List.map (fun e -> e.registers.(0)) components); constant = None}
      | Get (t, f) -> field (expression env t) f
      | If (condition, yes, no) ->
          (* ponytail: eager pure branches; nonfinite untaken arms rerun the reference.
             Add masked execution if such bodies appear in profiles. *)
          let condition = expression env condition in
          (match condition.constant with
           | Some v -> expression env (if V.truthy v then yes else no)
           | None ->
               let yes = expression env yes and no = expression env no in
               if Array.length condition.registers <> 1 then raise Unsupported;
               let width = max (Array.length yes.registers) (Array.length no.registers) in
               {registers = Array.init width (fun i ->
                 emit (Select (condition.registers.(0), component yes i, component no i))); constant = None})
      | Op {op; args; _} ->
          let declaration = match Flow.Op.find ~extra:(E.Private.residual_ops residual) op Flow.Context.value with
            | Some o when o.ctx = Flow.Context.value && o.shape = Flow.Op.Scalar
                && (o == Operators.noise3 || Option.fold ~none:false ~some:((==) o)
                  (Flow.Op.find o.name Flow.Context.value)) -> o
            | _ -> raise Unsupported in
          let expressions = List.map (fun (_, t) -> expression env t) args in
          if List.for_all (fun e -> Option.is_some e.constant) expressions && not declaration.live then
            literal (declaration.body ~live:(Frame_input.at_time 0.)
              ~node:(fun _ _ -> raise Unsupported)
              (List.map2 (fun (name, _) e -> name, Option.get e.constant) args expressions))
          else if declaration.live && args = [] && List.mem t.ty [Ty.Float; Ty.Int; Ty.Bool] then
            {registers = [|emit (Frame declaration.name)|]; constant = None}
          else begin
            let width = List.fold_left (fun n e -> max n (Array.length e.registers)) 1 expressions in
            if t.ty = Ty.Int then raise Unsupported;
            let registers = match expressions with
              | a::rest when declaration == Operators.noise3 && Array.length a.registers=3 ->
                  let configuration=List.map2(fun (name,_) expression ->
                    name,match expression.constant with Some value->value|None->raise Unsupported)
                    (List.tl args) rest in
                  let integer name default=Option.fold ~none:default ~some:V.int_of
                    (List.assoc_opt name configuration)in
                  let seed=integer "seed" 0 and octaves=integer "octaves" 1 in
                  if octaves<1||octaves>32 then raise Unsupported;
                  [|emit (Noise3 (a.registers.(0), a.registers.(1), a.registers.(2), seed, octaves))|]
              | [a] when declaration.name = "exact" -> a.registers
              | [a; b] -> let op = binary declaration.name in
                  Array.init width (fun i -> emit (Binary (op, component a i, component b i)))
              | [a] when width = 1 -> let op = unary declaration.name in
                  [|emit (Unary (op, a.registers.(0)))|]
              | _ -> raise Unsupported in
            {registers; constant = None}
          end
      | Let (bindings, result) ->
          let env = List.fold_left (fun env (p, t) -> match p with
            | W.Name n -> (n, expression env t) :: env | _ -> raise Unsupported) env bindings in
          expression env result
      | Expanded {body; _} | Bypass body -> expression env body
      | _ -> raise Unsupported in
    let output = (expression env body).registers in
    let width = match term.ty with Ty.Array Ty.Float | Ty.Float -> 1
      | Ty.Array Ty.Vec3 | Ty.Vec3 -> 3 | _ -> raise Unsupported in
    (match result with
     | Sum _ | Accumulate _ when body.ty <> Ty.Float && body.ty <> Ty.Vec3 -> raise Unsupported
     | _ -> ());
    (* array_init also broadcasts a scalar to vec3. *)
    let output = if Array.length output = 1 && width = 3 then Array.make 3 output.(0) else output in
    if Array.length output <> width then raise Unsupported;
    let counts = Array.map (count_of residual) sources in
    let count = count_of_sources iteration counts in
    let rec paths sites (t : W.term) =
      let sites = match t.path with Some p -> (view.instance, p, view.iter) :: sites | None -> sites in
      let children = match t.node with
        | W.Vec ts -> ts | Get (t, _) | Bypass t | Expanded {body = t; _} -> [t]
        | If (a, b, c) -> [a;b;c] | Op {args; _} -> List.map snd args
        | Let (bindings, result) -> result :: List.map snd bindings | _ -> [] in
      List.fold_left paths sites children in
    let sites = paths [view.instance, Option.value ~default:view.site term.path, view.iter] body in
    let sites = match term.node with
      | W.Hof (_, {node = Fn {zone; _}; _} :: _) -> (view.instance, zone, view.iter) :: sites
      | Hof (_, {node = Ref_binding (name, []); _} :: _) ->
          (match List.assoc_opt name view.bindings with Some (E.Fn f) ->
            (match E.Private.function_body f with Some (_, {path = Some p; _}) ->
              (view.instance, List.filteri (fun i _ -> i < List.length p - 1) p, view.iter) :: sites
            | _ -> sites) | _ -> sites)
      | _ -> sites in
    let skip = List.filter_map (fun tuple ->
      match List.rev tuple with
      | k :: prefix when List.rev prefix = view.iter -> Some k | _ -> None) skip
      |> List.sort_uniq Int.compare |> Array.of_list in
    let program = {residual; term; sources = Array.map (fun t -> residual, t) sources;
      widths; uniforms = Array.of_list (List.rev !uniforms);
      code = Array.of_list (List.rev !code); dependent = Array.sub dependent 0 !size;
      output; count; iteration; result; skip; stages = [residual, term]; fusion; dynamic; body; binding_fn;
      uniform_names = Array.of_list (List.rev !uniform_names); count_source;
      origin = None; sites} in
    Some (if fusion then fuse_maps program else program)
  with Unsupported | V.Fail _ | Invalid_argument _ -> None
and source_program ~dynamic ~count_source (residual, (term : W.term)) = match term.node with
  | W.Ref_binding (name, []) ->
      (match List.assoc_opt name (E.Private.residual_view residual).bindings with
       | Some (E.Residual r) -> source_program ~dynamic ~count_source (r, (E.Private.residual_view r).term)
       | _ -> None)
  | _ -> compile_impl ~dynamic ~count_source residual term
and fuse_maps t =
  if t.skip <> [||] || (t.iteration = Product && Array.length t.sources <> 1) then t else
  let children = Array.map (source_program ~dynamic:t.dynamic ~count_source:t.count_source) t.sources in
  let origins = Array.mapi (fun i -> function
    | Some p -> p.origin | None -> let r, s = t.sources.(i) in t.count_source r s) children in
  let origin = if origins <> [||] && Option.is_some origins.(0)
      && Array.for_all ((=) origins.(0)) origins then origins.(0) else None in
  let counts = Array.mapi (fun i -> function
    | Some p -> p.count | None -> let r, s = t.sources.(i) in count_of r s) children in
  let count = if Array.for_all Option.is_some counts && counts <> [||] then
    Some (Array.fold_left (fun n c -> min n (Option.get c)) max_int counts) else t.count in
  let t = {t with count; origin = (match t.result with Collect -> origin | _ -> None)} in
  let can_fuse = function
    | Some p when p.result = Collect && p.iteration = Zip && p.skip = [||] ->
        Array.length t.sources = 1 || (Option.is_some p.count && p.count = count)
          || (Option.is_some origin && p.origin = origin)
    | _ -> false in
  if not (Array.exists can_fuse children) then t else
  try
    let sources = ref [] and widths = ref [] and nsources = ref 0 in
    let uniforms = ref [] and nuniforms = ref 0 and code = ref [] and ncode = ref 0 in
    let dependent = Array.make 64 false and stages = ref t.stages and sites = ref t.sites in
    let shared = Hashtbl.create 64 in
    let emit instruction =
      let key = Marshal.to_string instruction [Marshal.No_sharing] in
      match Hashtbl.find_opt shared key with
      | Some id -> id
      | None ->
          if !ncode >= 64 then raise Unsupported;
          let id = !ncode in incr ncode; code := instruction :: !code;
          dependent.(id) <- (match instruction with
            | Accumulator _ -> true | Binary (_, a, b) -> dependent.(a) || dependent.(b)
            | Unary (_, a) -> dependent.(a) | Noise3 (a, b, c, _, _) | Select (a, b, c) -> dependent.(a) || dependent.(b) || dependent.(c)
            | _ -> false);
          Hashtbl.add shared key id; id in
    let append_source source width =
      let i = !nsources in incr nsources; sources := source :: !sources; widths := width :: !widths; i in
    let append_uniforms values =
      let offset = !nuniforms in
      Array.iter (fun v -> incr nuniforms; uniforms := v :: !uniforms) values; offset in
    let append_code p input uniform =
      let registers = Array.make (Array.length p.code) 0 in
      Array.iteri (fun i instruction ->
        let at n = registers.(n) in
        registers.(i) <- match instruction with
          | Input (source, width, component) -> input source width component
          | Uniform (n, component) -> emit (Uniform (uniform + n, component))
          | Binary (op, a, b) -> emit (Binary (op, at a, at b))
          | Unary (op, a) -> emit (Unary (op, at a))
          | Noise3 (a, b, c, seed, octaves) -> emit (Noise3 (at a, at b, at c, seed, octaves))
          | Select (a, b, c) -> emit (Select (at a, at b, at c))
          | instruction -> emit instruction) p.code;
      Array.map (Array.get registers) p.output in
    let inputs = Array.mapi (fun i child ->
      if can_fuse child then begin
        let p = Option.get child in
        let inputs = Array.mapi (fun i source -> append_source source p.widths.(i)) p.sources in
        let uniform = append_uniforms p.uniforms in
        stages := !stages @ p.stages;
        sites := p.sites @ !sites;
        append_code p (fun i width component -> emit (Input (inputs.(i), width, component))) uniform
      end else begin
        let source = append_source t.sources.(i) t.widths.(i) in
        Array.init t.widths.(i) (fun component -> emit (Input (source, t.widths.(i), component)))
      end) children in
    let uniform = append_uniforms t.uniforms in
    let output = append_code t (fun i _ component -> inputs.(i).(component)) uniform in
    {t with sources = Array.of_list (List.rev !sources); widths = Array.of_list (List.rev !widths);
      uniforms = Array.of_list (List.rev !uniforms); code = Array.of_list (List.rev !code);
      dependent = Array.sub dependent 0 !ncode; output; iteration = Zip; stages = !stages; sites = !sites}
  with Unsupported -> t

let static_count t = t.count
let count_origin t = t.origin
let compile ?fusion ?count_source r term = compile_impl ?fusion ?count_source r term
let compile_template ?count_source r term = compile_impl ~dynamic:true ?count_source r term
let rebind t residual =
  let view = E.Private.residual_view residual in
  if not t.dynamic || List.length t.stages <> 1 || t.term != view.term || view.previous
      || E.state_dependent (E.Residual residual) then None else
  try
    let bindings = match t.binding_fn with
      | None -> view.bindings
      | Some name -> (match List.assoc_opt name view.bindings with
          | Some (E.Fn f) when Option.fold ~none:false ~some:(fun (_, body) -> body == t.body)
              (E.Private.function_body f) -> E.Private.function_bindings f
          | _ -> raise Unsupported) in
    let uniforms = Array.map (fun (name, fields) -> captured_value bindings name fields) t.uniform_names in
    let sources = Array.map (fun (r, term) ->
      if r != t.residual then raise Unsupported; residual, term) t.sources in
    let count = count_of_sources t.iteration (Array.map (fun (r, s) -> count_of r s) sources) in
    Some {t with residual; uniforms; sources; count; stages = [residual, t.term]}
  with Unsupported -> None
let elementwise t = match t.result with Collect -> true | Sum _ | Accumulate _ -> false
let provenance t = List.sort_uniq compare t.sites
let stage_count t = List.length t.stages
let site t = let view = E.Private.residual_view t.residual in
  view.instance, Option.value ~default:view.site t.term.path, view.iter
let reference ?state ?elems ?resolve t ~live = E.Private.eval_term ?state ?elems ?resolve t.residual t.term ~live
exception Failed of Flow.Diagnostic.t
exception Nonfinite
let get = function Ok x -> x | Error d -> raise (Failed d)

let rec force ?state ?elems ?resolve ?measure t ~live =
  let state = Option.value ~default:(E.create_state ()) state in
  let work () =
    let rec evaluate residual (term : W.term) =
      let nested = match term.node with
        | W.Ref_binding (name, []) ->
            (match List.assoc_opt name (E.Private.residual_view residual).bindings with
             | Some (E.Residual r) -> let view = E.Private.residual_view r in Some (r, view.term)
             | _ -> None)
        | _ -> None in
      match nested with
      | Some (residual, term) -> evaluate residual term
      | None -> (match compile_impl ~fusion:t.fusion ~dynamic:t.dynamic ~count_source:t.count_source residual term with
          | Some program -> force ~state ?elems ?resolve ?measure program ~live
          | None -> E.Private.eval_term ~state ?elems ?resolve residual term ~live) in
    let seed = match t.result with
      | Accumulate (seed, _) -> Some (get (E.Private.eval_term ~state ?elems ?resolve t.residual seed ~live))
      | _ -> None in
    let inputs = Array.mapi (fun i (residual, term) ->
      let value = get (evaluate residual term) in
      match value, t.widths.(i) with
      | E.Float_array xs, 1 | Vec3_array xs, 3 -> xs
      | _ -> V.fail "E_ARRAY_TYPE" "Kernel input changed its packed element type.") t.sources in
    let lengths = Array.mapi (fun i a -> Array.length a / t.widths.(i)) inputs in
    let count = if t.iteration = Product && Array.exists ((=) 0) lengths then 0 else
      Array.fold_left (fun a b -> match t.iteration with
      | Zip -> min a b | Product ->
          if b <> 0 && a > max_int / b then V.fail "E_ARRAY_RANGE" "Kernel iteration count exceeds native bounds.";
          a * b) (if t.iteration = Zip then max_int else 1) lengths in
    let count = if inputs = [||] then 0 else count in
    let strides = Array.make (Array.length inputs) 1 in
    if t.iteration = Product && count > 0 then
      for i = Array.length inputs - 2 downto 0 do strides.(i) <- strides.(i + 1) * lengths.(i + 1) done;
    let uniforms = Array.map (fun v ->
      let v = get (E.Private.force_reference ~state ?elems ?resolve v ~live) in
      match v with E.Vec3 (x, y, z) -> [|x; y; z|] | _ -> [|V.num v|]) t.uniforms in
    let frame = Array.map (function
      | Frame "t" -> live.Frame_input.t
      | Frame name ->
          (match Flow.Op.find name Flow.Context.value with
           | Some op -> V.num (op.body ~live ~node:(fun _ _ -> raise Unsupported) [])
           | None -> raise Unsupported)
      | _ -> 0.) t.code in
    let started = Option.map (fun (clock, _) -> clock ()) measure in
    let width = Array.length t.output in
    List.iter (fun (_, (term : W.term)) -> match term.ty with
      | Ty.Array ty ->
          let width = if ty = Ty.Vec3 then 3 else 1 in
          if count > Sys.max_floatarray_length / width then
            V.fail "E_ARRAY_RANGE" "Kernel intermediate exceeds native storage bounds."
      | _ -> ()) t.stages;
    let skip = Array.to_list t.skip |> List.filter (fun i -> i >= 0 && i < count) |> Array.of_list in
    let skipped_before n =
      let lo = ref 0 and hi = ref (Array.length skip) in
      while !lo < !hi do
        let mid = (!lo + !hi) / 2 in
        if skip.(mid) < n then lo := mid + 1 else hi := mid
      done; !lo in
    let kept = count - Array.length skip in
    let collecting = match t.result with Collect | Accumulate (_, true) -> true | _ -> false in
    if collecting && kept > Sys.max_floatarray_length / width then V.fail "E_ARRAY_RANGE" "Kernel output exceeds native storage bounds.";
    let output = Array.make (if collecting then kept * width else 0) 0. in
    let accumulator = match seed with
      | Some (E.Vec3 (x, y, z)) -> [|x; y; z|]
      | Some v -> Array.make width (V.num v) | None -> Array.make width 0. in
    let initialized = ref (match t.result with Sum zero -> zero | _ -> true) in
    let block_size = 1024 in
    let blocks = if count = 0 then 0 else (count - 1) / block_size + 1 in
    let blocks_per_chunk = 16 in
    let chunks = if blocks = 0 then 0 else (blocks - 1) / blocks_per_chunk + 1 in
    let chunk chunk =
      let scratch = Array.make (Array.length t.code * block_size) 0. in
      let noise_scratch=Rays_math.Noise.Private.create_fbm3_scratch () in
      let tables=Array.map(function Noise3(_,_,_,seed,_)->Some(Operators.noise_table seed)
        |_->None)t.code in
      let indices = Array.make block_size 0 in
      for block = chunk * blocks_per_chunk to min blocks ((chunk + 1) * blocks_per_chunk) - 1 do
      let start = block * block_size and limit = min count ((block + 1) * block_size) in
      let skipped = ref (skipped_before start) and length = ref 0 in
      for i = start to limit - 1 do
        if !skipped < Array.length skip && skip.(!skipped) = i then incr skipped
        else begin indices.(!length) <- i; incr length end
      done;
      let length = !length and output_start = start - skipped_before start in
      let execute dependent first last =
      for slot = 0 to Array.length t.code - 1 do
        let instruction = t.code.(slot) in
        if t.dependent.(slot) = dependent then begin
        let at = slot * block_size in
        match instruction with
        | Const x -> Array.fill scratch (at + first) (last - first) x
        | Input (input, width, component) ->
            let source = inputs.(input) in
            for j = first to last - 1 do
              let i = if t.iteration = Zip then indices.(j)
                else indices.(j) / strides.(input) mod lengths.(input) in
              scratch.(at + j) <- source.(i * width + component)
            done
        | Uniform (uniform, component) -> Array.fill scratch (at + first) (last - first) uniforms.(uniform).(component)
        | Frame _ -> Array.fill scratch (at + first) (last - first) frame.(slot)
        | Accumulator component -> Array.fill scratch (at + first) (last - first) accumulator.(component)
        | Select (condition, yes, no) ->
            let condition = condition * block_size and yes = yes * block_size and no = no * block_size in
            for j = first to last - 1 do
              scratch.(at+j) <- scratch.((if scratch.(condition+j) <> 0. then yes else no) + j)
            done
        | Noise3 (x, y, z, _, octaves) ->
            let noise=Option.get tables.(slot)in
            if octaves=1 then Rays_math.Noise.Private.sample3_into noise ~first ~last
              ~x:scratch ~x_offset:(x * block_size) ~y:scratch ~y_offset:(y * block_size)
              ~z:scratch ~z_offset:(z * block_size) ~output:scratch ~output_offset:at ()
            else for j=first to last-1 do
              scratch.(at+j)<-Rays_math.Noise.Private.fbm3_with_scratch noise_scratch noise
                ~octaves ~lacunarity:2. ~gain:0.5
                ~x:scratch.(x*block_size+j) ~y:scratch.(y*block_size+j) ~z:scratch.(z*block_size+j)
            done
        | Binary (operation, a, b) ->
            let a = a * block_size and b = b * block_size in
            (match operation with
             | Add -> for j = first to last - 1 do let x = scratch.(a+j) +. scratch.(b+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Sub -> for j = first to last - 1 do let x = scratch.(a+j) -. scratch.(b+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Mul -> for j = first to last - 1 do let x = scratch.(a+j) *. scratch.(b+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Div -> for j = first to last - 1 do let y = scratch.(b+j) in
                 let x = if y = 0. then 0. else scratch.(a+j) /. y in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Mod -> for j = first to last - 1 do let y = scratch.(b+j) in
                 let x = if y = 0. then 0. else Float.rem (Float.rem scratch.(a+j) y +. y) y in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Pow -> for j = first to last - 1 do let x = Float.pow (Float.abs scratch.(a+j)) scratch.(b+j) in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Min -> for j = first to last - 1 do let x = Float.min scratch.(a+j) scratch.(b+j) in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Max -> for j = first to last - 1 do let x = Float.max scratch.(a+j) scratch.(b+j) in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | (Lt | Le | Gt | Ge | Eq | And | Or) ->
                 for j = first to last - 1 do
                   let x = scratch.(a+j) and y = scratch.(b+j) in
                   let result = match operation with
                     | Lt -> x < y | Le -> x <= y | Gt -> x > y | Ge -> x >= y | Eq -> x = y
                     | And -> x <> 0. && y <> 0. | Or -> x <> 0. || y <> 0.
                     | _ -> assert false in
                   scratch.(at+j) <- if result then 1. else 0.
                 done)
        | Unary (operation, a) ->
            let a = a * block_size in
            (match operation with
             | Sin -> for j = first to last - 1 do let x = sin scratch.(a+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Cos -> for j = first to last - 1 do let x = cos scratch.(a+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Sqrt -> for j = first to last - 1 do scratch.(at+j) <- sqrt (Float.abs scratch.(a+j)) done
             | Abs -> for j = first to last - 1 do scratch.(at+j) <- Float.abs scratch.(a+j) done
             | Not -> for j = first to last - 1 do scratch.(at+j) <- if scratch.(a+j) = 0. then 1. else 0. done)
        end
      done in
      execute false 0 length;
      for j = 0 to length - 1 do
        (match t.result with Accumulate _ -> execute true j (j + 1) | _ -> ());
        for component = 0 to width - 1 do
          let x = scratch.(t.output.(component) * block_size + j) in if not (Float.is_finite x) then raise Nonfinite;
          (match t.result with
           | Collect -> () | Accumulate _ -> accumulator.(component) <- x
           | Sum _ ->
               let total = if !initialized then accumulator.(component) +. x else x in
               if not (Float.is_finite total) then raise Nonfinite;
               accumulator.(component) <- total);
          if collecting then output.((output_start+j) * width + component) <- x
        done;
        (match t.result with Sum _ -> initialized := true | _ -> ())
      done
      done in
    (match t.result with
     | Collect -> Rays_math.Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(chunks - 1) chunk
     | Sum _ | Accumulate _ ->
         (* The fixed tree composes ordered chunk spans, retaining reference additions
            instead of reassociating partial sums (which changes cancellation and signed zero). *)
         let rec ordered first last =
           if last - first = 1 then chunk first else if first < last then begin
             let middle = first + (last - first) / 2 in
             ordered first middle; ordered middle last
           end in
         ordered 0 chunks);
    let value = if collecting then (if width = 3 then E.Vec3_array output else E.Float_array output)
    else match t.result, seed with
      | Accumulate _, Some seed when kept = 0 -> seed
      | Sum false, _ when kept = 0 -> E.Int 0
      | _ -> if width = 3 then E.Vec3 (accumulator.(0), accumulator.(1), accumulator.(2))
          else E.Float accumulator.(0) in
    Option.iter (fun (clock, report) -> report t ~seconds:(max 0. (clock () -. Option.get started)) ~reference:false) measure;
    value in
  let result = E.transaction state (fun () ->
    try Ok (work ()) with
    | Failed d -> Error d
    | Nonfinite | Unsupported -> Error (Flow.Diagnostic.error ~code:"E_KERNEL" "Kernel needs reference evaluation.")
    | V.Fail (code, message, span) -> Error (Flow.Diagnostic.error ?span ~code message)
    | Out_of_memory -> Error (Flow.Diagnostic.error ~code:"E_ARRAY_MEMORY" "Frame data exceeds available memory.")) in
  match result with Ok _ -> result | Error _ ->
    let started = Option.map (fun (clock, _) -> clock ()) measure in
    let result = reference ~state ?elems ?resolve t ~live in
    Option.iter (fun (clock, report) -> report t ~seconds:(max 0. (clock () -. Option.get started)) ~reference:true) measure;
    result

module Private = struct
  type view = {code : instruction array; widths : int array; output : int array;
    uniform_widths : int array; collecting : bool; zipped : bool; skip : int array}
  let view (t : t) =
    let uniform_widths = Array.make (Array.length t.uniforms) 1 in
    Array.iter (function Uniform (index, component) ->
      uniform_widths.(index) <- max uniform_widths.(index) (component+1) | _ -> ()) t.code;
    {code=t.code; widths=t.widths; output=t.output; uniform_widths;
      collecting=(match t.result with Collect -> true | _ -> false);
      zipped=t.iteration=Zip || Array.length t.sources=1; skip=t.skip}
  type inputs = {arrays : float array array; uniforms : float array array;
    frame : float array; count : int}
  let prepare ?state ?elems ?resolve (t : t) ~live =
    let state = Option.value ~default:(E.create_state ()) state in
    E.transaction state (fun () -> try
      let rec evaluate residual term =
        match term.W.node with
        | W.Ref_binding (name, []) ->
            (match List.assoc_opt name (E.Private.residual_view residual).bindings with
             | Some (E.Residual residual) -> evaluate residual (E.Private.residual_view residual).term
             | _ -> materialize residual term)
        | _ -> materialize residual term
      and materialize residual term =
        match compile_impl ~fusion:t.fusion ~dynamic:t.dynamic ~count_source:t.count_source residual term with
        | Some program -> get (force ~state ?elems ?resolve program ~live)
        | None -> get (E.Private.eval_term ~state ?elems ?resolve residual term ~live) in
      let arrays = Array.mapi (fun index (residual, term) ->
        match evaluate residual term, t.widths.(index) with
        | E.Float_array values, 1 | Vec3_array values, 3 -> values
        | _ -> V.fail "E_ARRAY_TYPE" "Kernel input changed its packed element type.") t.sources in
      let count = if arrays=[||] then 0 else Array.fold_left min max_int
        (Array.mapi (fun index values -> Array.length values / t.widths.(index)) arrays) in
      let uniforms = Array.map (fun value ->
        match get (E.Private.force_reference ~state ?elems ?resolve value ~live) with
        | E.Vec3 (x,y,z) -> [|x;y;z|] | value -> [|V.num value|]) t.uniforms in
      let frame = Array.map (function
        | Frame "t" -> live.Frame_input.t
        | Frame name -> (match Flow.Op.find name Flow.Context.value with
            | Some op -> V.num (op.body ~live ~node:(fun _ _ -> raise Unsupported) [])
            | None -> raise Unsupported)
        | _ -> 0.) t.code in
      Ok {arrays; uniforms; frame; count}
    with Failed error -> Error error
      | Unsupported -> Error (Flow.Diagnostic.error ~code:"E_KERNEL" "Kernel inputs need reference evaluation.")
      | V.Fail (code,message,span) -> Error (Flow.Diagnostic.error ?span ~code message)
      | Out_of_memory -> Error (Flow.Diagnostic.error ~code:"E_ARRAY_MEMORY" "Frame data exceeds available memory."))
end
