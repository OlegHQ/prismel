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
exception Compile_refused of Flow.Diagnostic.t

let zipped t = t.iteration = Zip || Array.length t.sources = 1

let output_reachable t =
  let used = Array.make (Array.length t.code) false in
  let rec use slot = if not used.(slot) then begin
    used.(slot) <- true;
    match t.code.(slot) with
    | Binary (_, a, b) -> use a; use b
    | Unary (_, a) -> use a
    | Select (a, b, c) | Noise3 (a, b, c, _, _) -> use a; use b; use c
    | _ -> ()
  end in
  Array.iter use t.output;
  used

let gpu_refusals t =
  let reasons = ref [] in
  let refuse message = reasons := Flow.Diagnostic.error ~code:"E_GPU_FORM" message :: !reasons in
  if t.result <> Collect || not (zipped t) || t.skip <> [||] then
    refuse "GPU kernels require Collect with Zip iteration and no skipped elements.";
  if Array.exists (function Accumulator _ -> true | _ -> false) t.code then
    refuse "Ordered accumulators stay on the CPU.";
  let used = output_reachable t in
  let bad_noise = ref false and bad_constant = ref false in
  Array.iteri (fun i instruction -> if used.(i) then match instruction with
    | Noise3 (_, _, _, _, octaves) ->
        if not (Flow.Packed_ops.supported_noise_octaves octaves) then bad_noise := true
    | Const value -> if not (Flow.Packed_ops.finite_float32 value) then bad_constant := true
    | _ -> ()) t.code;
  if !bad_noise then refuse "GPU noise supports 1 to 32 octaves.";
  if !bad_constant then
    refuse "Nonfinite float32 shader constants require reference evaluation.";
  List.rev !reasons

let width_of ty = match Flow.Packed_ops.scalar_width ty with
  | Some width -> width | None -> raise Unsupported
let components = function
  | E.Vec2 (x,y) -> [|x;y|] | Vec3 (x,y,z) -> [|x;y;z|]
  | Vec4 (x,y,z,w) -> [|x;y;z;w|] | value -> [|V.num value|]

let captured_value bindings name fields =
  let value = match List.assoc_opt name bindings with Some v -> v | None -> raise Unsupported in
  List.fold_left (fun value field -> match value, field with
    | E.Record fs, field | Struct (_, _, fs), field ->
        (match List.assoc_opt field fs with Some v -> v | None -> raise Unsupported)
    | E.Vec3 (x, _, _), "x" | Vec3 (_, x, _), "y" | Vec3 (_, _, x), "z" -> E.Float x
    | E.Vec2 (x,_), "x" | Vec2 (_,x), "y" -> E.Float x
    | E.Vec4 (x,_,_,_), "x" | Vec4 (_,x,_,_), "y"
    | Vec4 (_,_,x,_), "z" | Vec4 (_,_,_,x), "w" -> E.Float x
    | _ -> raise Unsupported) value fields

let count_of residual (s : W.term) = match s.node with
  | W.Ref_binding (name, fields) ->
      (try match captured_value (E.Private.residual_view residual).bindings name fields with
       | E.Float_array _ | Vec2_array _ | Vec3_array _ | Vec4_array _ as v -> Some (V.array_length v) | _ -> None
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
  let refuse ?(at = term) code message =
    raise (Compile_refused (Flow.Diagnostic.error ~span:at.form.span ~code message)) in
  try
    if view.previous then refuse "E_PACKED_STATE" "Previous-state values require reference evaluation.";
    if E.state_dependent (E.Residual residual) then
      refuse "E_PACKED_STATE" "State-dependent kernels require reference evaluation.";
    let function_body ?reduction (f : W.term) = match f.node with
      | W.Fn {capture = Some _; _} ->
          (match E.Private.eval_term residual f ~live:(Frame_input.at_time 0.) with
           | Ok (E.Fn fn) -> (match E.Private.function_body fn with
               | Some (params, body) -> params, body, E.Private.function_bindings fn
               | None -> refuse ~at:f "E_PACKED_FUNCTION" "Captured function has no instantiated packed body.")
           | Error d -> raise (Compile_refused d)
           | Ok _ -> refuse ~at:f "E_PACKED_FUNCTION" "Captured callable did not resolve to a function.")
      | W.Fn {params; body; _} -> params, body, view.bindings
      | W.Ref_binding (name, []) ->
          (match List.assoc_opt name view.bindings with
           | Some (E.Fn fn) -> (match E.Private.function_body fn with
               | Some (params, body) -> params, body, E.Private.function_bindings fn
               | None -> refuse ~at:f "E_PACKED_FUNCTION" ("Function " ^ name ^ " has no instantiated packed body."))
           | _ -> refuse ~at:f "E_PACKED_FUNCTION" ("Function binding " ^ name ^ " is unavailable."))
      | W.Fn_ref "+" when Option.is_some reduction ->
          (match Flow.Op.find ~extra:(E.Private.residual_ops residual) "+" Flow.Context.value with
           | Some op when Flow.Op.packed_kind op = Some (Flow.Op.Binary Add) ->
               let seed, source = Option.get reduction in
               let item_ty = match source.W.ty with Ty.Array ty -> ty | _ ->
                 refuse ~at:source "E_PACKED_TYPE" "Packed reduce requires a numeric array." in
               let arg name ty = {f with path=None;ty;node=W.Ref_binding(name,[])} in
               let body = {f with ty=term.ty;node=W.Op {op=op.name;
                 args=["a",arg "@accumulator" seed.W.ty;"b",arg "@item" item_ty];skip=[]}} in
               [W.Name "@accumulator",None;W.Name "@item",None],body,view.bindings
           | _ -> refuse ~at:f "E_PACKED_FUNCTION" "Packed named reduce requires canonical addition.")
      | W.Fn_ref name -> refuse ~at:f "E_PACKED_FUNCTION" ("Function value " ^ name ^ " has no instantiated packed body.")
      | _ -> refuse ~at:f "E_PACKED_FUNCTION" "Packed kernels require a function with an instantiated body." in
    let params, accumulator, body, sources, bindings, iteration, result, skip = match term.node with
      | W.Hof (`Map, f :: sources) ->
          let params, body, bindings = function_body f in
          params, None, body, sources, bindings, Zip, Collect, []
      | W.Hof (`Reduce, [f; seed; source]) ->
          let params, body, bindings = function_body ~reduction:(seed,source) f in
          (match params with
           | acc :: params -> params, Some acc, body, [source], bindings, Zip, Accumulate (seed, false), []
           | _ -> refuse "E_PACKED_FORM" "Packed reduce requires an accumulator parameter.")
      | W.Loop {kind; accs; clauses; body; skip; _} ->
          let accumulator, result = match kind, accs with
            | `For, [] -> None, Collect | `Sum, [] -> None, Sum false
            | (`Fold | `Scan), [p, seed] -> Some (p, None), Accumulate (seed, kind = `Scan)
            | _ -> refuse "E_PACKED_FORM" "Packed fold/scan requires exactly one accumulator." in
          List.map (fun (p, _) -> p, None) clauses, accumulator, body,
            List.map snd clauses, view.bindings, Product, result, skip
      | W.Op {op = "array/sum"; args = [_, source]; _} ->
          let ty = match source.ty with Ty.Array ty -> ty | _ ->
            refuse ~at:source "E_PACKED_TYPE" ("array/sum source is " ^ Ty.to_string source.ty ^ ", not an array.") in
          let body = {source with ty; node = W.Ref_binding ("@item", [])} in
          [W.Name "@item", None], None, body, [source], view.bindings, Zip, Sum true, []
      | _ -> refuse "E_PACKED_FORM" "Packed kernels require map, reduce, a numeric loop or array/sum." in
    let sources = Array.of_list sources in
    let binding_fn = match term.node with
      | W.Hof (_, {node = W.Ref_binding (name, []); _} :: _) -> Some name | _ -> None in
    let names = List.filter_map (function W.Name name, _ -> Some name | _ -> None)
      (params @ Option.to_list accumulator) in
    (* ponytail: correlated clauses stay interpreted; lower their changing source counts before tiling them. *)
    if iteration = Product && Array.exists (reads_names names) sources then
      refuse "E_PACKED_FORM" "Correlated product sources require reference evaluation.";
    let widths = Array.map (fun (s : W.term) -> match Flow.Packed_ops.array_width s.ty with
      | Some width -> width
      | None -> refuse ~at:s "E_PACKED_TYPE" ("Packed source must be a float/vector array, got " ^ Ty.to_string s.ty ^ ".")) sources in
    if Array.length sources <> List.length params then
      refuse "E_PACKED_FORM" (Printf.sprintf "Packed kernel has %d sources but %d parameters."
        (Array.length sources) (List.length params));
    let code = ref [] and size = ref 0 and uniforms = ref [] and nuniforms = ref 0 and uniform_names = ref [] in
    let dependent = Array.make Flow.Packed_ops.register_limit false in
    let emit instruction =
      (* ponytail: cap scratch at 512 KiB per block; measure larger bodies before raising it. *)
      if !size >= Flow.Packed_ops.register_limit then
        refuse "E_PACKED_LIMIT" (Printf.sprintf "Packed kernel exceeds %d registers." Flow.Packed_ops.register_limit);
      let id = !size in incr size; code := instruction :: !code;
      dependent.(id) <- (match instruction with
        | Accumulator _ -> true | Binary (_, a, b) -> dependent.(a) || dependent.(b)
        | Unary (_, a) -> dependent.(a) | Noise3 (a, b, c, _, _) | Select (a, b, c) -> dependent.(a) || dependent.(b) || dependent.(c)
        | _ -> false); id in
    let literal ?(at = term) v =
      let data = match v with
        | E.Int _ | Float _ | Bool _ | Vec2 _ | Vec3 _ | Vec4 _ -> components v
        | _ -> refuse ~at "E_PACKED_TYPE" ("Packed constant has unsupported type " ^ Ty.to_string (V.ty_of v) ^ ".") in
      {registers = Array.map (fun f -> emit (Const f)) data; constant = Some v} in
    let input i width = {registers = Array.init width (fun j -> emit (Input (i, width, j))); constant = None} in
    let uniform at name v = match v with
      | E.Residual _ | E.Int _ | Float _ | Bool _ | Vec2 _ | Vec3 _ | Vec4 _ when dynamic || E.is_live v ->
          let ty = match v with E.Residual r -> (E.Private.residual_view r).term.ty | v -> V.ty_of v in
          let width = try width_of ty with Unsupported ->
            refuse ~at "E_PACKED_CAPTURE" ("Capture " ^ String.concat "." (fst name :: snd name)
              ^ " has unsupported type " ^ Ty.to_string ty ^ ".") in
          let i = !nuniforms in incr nuniforms; uniforms := v :: !uniforms;
          uniform_names := name :: !uniform_names;
          {registers = Array.init width (fun j -> emit (Uniform (i, j))); constant = None}
      | E.Int _ | Float _ | Bool _ | Vec2 _ | Vec3 _ | Vec4 _ -> literal ~at v
      | _ -> refuse ~at "E_PACKED_CAPTURE" ("Capture " ^ String.concat "." (fst name :: snd name)
          ^ " has unsupported type " ^ Ty.to_string (V.ty_of v) ^ ".") in
    let env = List.mapi (fun i (pattern, annotation) ->
      match pattern with
      | W.Name name when annotation = None || annotation = Some
          (match widths.(i) with 2 -> Ty.Vec2 | 3 -> Ty.Vec3 | 4 -> Ty.Vec4 | _ -> Ty.Float) ->
          name, input i widths.(i)
      | W.Name name -> refuse "E_PACKED_TYPE" (Printf.sprintf
          "Packed parameter %s annotation %s does not match its %d-component source."
          name (Option.fold ~none:"none" ~some:Ty.to_string annotation) widths.(i))
      | _ -> refuse "E_PACKED_FORM" "Packed parameters require name patterns.") params in
    let env = match accumulator, result with
      | Some (W.Name name, annotation), Accumulate (seed, _) ->
          if not (List.mem seed.ty [Ty.Float;Ty.Int;Ty.Vec2;Ty.Vec3;Ty.Vec4]) then
            refuse ~at:seed "E_PACKED_TYPE" ("Packed accumulator " ^ name ^ " has unsupported seed type " ^ Ty.to_string seed.ty ^ ".");
          let width = width_of seed.ty in
          if annotation <> None && annotation <> Some seed.ty
              && not (seed.ty = Ty.Int && annotation = Some Ty.Float) then
            refuse ~at:seed "E_PACKED_TYPE" (Printf.sprintf
              "Packed accumulator %s annotation %s does not match seed type %s."
              name (Option.fold ~none:"none" ~some:Ty.to_string annotation) (Ty.to_string seed.ty));
          (name, {registers = Array.init width (fun i -> emit (Accumulator i)); constant = None}) :: env
      | None, _ -> env | _ -> refuse "E_PACKED_FORM" "Packed accumulator requires a name pattern." in
    let captures = Hashtbl.create 16 in
    let captured at name fields = match Hashtbl.find_opt captures (name, fields) with
      | Some e -> e
      | None ->
          let value = try captured_value bindings name fields with Unsupported ->
            refuse ~at "E_PACKED_CAPTURE" ("Captured binding or field " ^ String.concat "." (name :: fields) ^ " is unavailable.") in
          let e = uniform at (name, fields) value in
          Hashtbl.add captures (name, fields) e; e in
    let field at e = function
      | "x" when Array.length e.registers >= 2 -> {registers = [|e.registers.(0)|]; constant = None}
      | "y" when Array.length e.registers >= 2 -> {registers = [|e.registers.(1)|]; constant = None}
      | "z" when Array.length e.registers >= 3 -> {registers = [|e.registers.(2)|]; constant = None}
      | "w" when Array.length e.registers = 4 -> {registers = [|e.registers.(3)|]; constant = None}
      | name -> refuse ~at "E_PACKED_TYPE" (Printf.sprintf "Component %s is unavailable on a %d-component packed value."
          name (Array.length e.registers)) in
    let component e i = e.registers.(if Array.length e.registers = 1 then 0 else i) in
    let rec expression env (t : W.term) =
      try match t.node with
      | W.Lit (Param.Int_value n) -> literal ~at:t (E.Int n)
      | Lit (Param.Float_value f) -> literal ~at:t (E.Float f)
      | Lit (Param.Bool_value b) -> literal ~at:t (E.Bool b)
      | Ref_binding (name, fields) ->
          (match List.assoc_opt name env with
           | Some e -> List.fold_left (field t) e fields
           | None ->
               (* A record may contain a deferred vector. Bind that vector as a
                  uniform before projecting its component. *)
               let direct = try ignore (captured_value bindings name fields); true
                 with Unsupported -> false in
               if direct then captured t name fields else
               match List.rev fields with
               | component :: prefix -> field t (captured t name (List.rev prefix)) component
               | [] -> refuse ~at:t "E_PACKED_CAPTURE" ("Captured binding " ^ name ^ " is unavailable."))
      | Time -> {registers = [|emit (Frame "t")|]; constant = None}
      | Vec ts when List.mem (List.length ts) [2;3;4] ->
          let components = List.map (expression env) ts in
          if not (List.for_all (fun e -> Array.length e.registers = 1) components) then
            refuse ~at:t "E_PACKED_TYPE" "Packed vector components must be scalar values.";
          {registers = Array.of_list (List.map (fun e -> e.registers.(0)) components); constant = None}
      | Get (value, f) -> field t (expression env value) f
      | Cond (arms, default) ->
          expression env (List.fold_right (fun (condition, yes) no ->
            {t with node = If (condition, yes, no)}) arms default)
      | Case (scrutinee, arms, default) ->
          let boolean (value : W.term) = {value with ty = Ty.Bool;
            node = Op {op = "not"; args = ["x", {value with ty = Ty.Bool;
              node = Op {op = "not"; args = ["x", value]; skip = []}}]; skip = []}} in
          expression env (List.fold_right (fun ((literal : Flow.Syntax.t), yes) no ->
            let value, ty = match literal.node with
              | Num s -> (Param.Float_value (float_of_string s), Ty.Float)
              | Sym ("true" | "false" as s) -> Param.Bool_value (s = "true"), Ty.Bool
              | _ -> refuse ~at:t "E_PACKED_FORM" "Packed case arms require numeric or boolean literals." in
            let right : W.term = {path = None; ty; node = Lit value; form = literal} in
            let left, right = if scrutinee.ty = Ty.Bool || ty = Ty.Bool then
              boolean scrutinee, boolean right else scrutinee, right in
            let condition = {t with ty = Ty.Bool;
              node = Op {op = "="; args = ["a", left; "b", right]; skip = []}} in
            {t with node = If (condition, yes, no)}) arms default)
      | If (condition, yes, no) ->
          (* ponytail: eager pure branches; nonfinite untaken arms rerun the reference.
             Add masked execution if such bodies appear in profiles. *)
          let condition = expression env condition in
          (match condition.constant with
           | Some v -> expression env (if V.truthy v then yes else no)
           | None ->
               let yes = expression env yes and no = expression env no in
               if Array.length condition.registers <> 1 then
                 refuse ~at:t "E_PACKED_TYPE" "Packed conditions require a scalar value.";
               let width = max (Array.length yes.registers) (Array.length no.registers) in
               {registers = Array.init width (fun i ->
                 emit (Select (condition.registers.(0), component yes i, component no i))); constant = None})
      | Op {op; args; _} ->
          let declaration, kind = match Flow.Op.find ~extra:(E.Private.residual_ops residual) op Flow.Context.value with
            | Some o -> (match Flow.Op.packed_kind o with
                | Some kind -> o, kind | None -> refuse ~at:t "E_PACKED_OPERATOR"
                    ("Operator " ^ op ^ " is not a canonical scalar declaration or validated packed intrinsic."))
            | _ -> refuse ~at:t "E_PACKED_OPERATOR" ("Operator " ^ op ^ " is unavailable.") in
          let expressions = List.map (fun (_, t) -> expression env t) args in
          if List.for_all (fun e -> Option.is_some e.constant) expressions && not declaration.live then
            literal ~at:t (declaration.body ~live:(Frame_input.at_time 0.)
              ~node:(fun name _ -> refuse ~at:t "E_PACKED_CONSTANT" ("Constant operator " ^ op ^ " attempted to create node " ^ name ^ "."))
              (List.map2 (fun (name, _) e -> name, Option.get e.constant) args expressions))
          else if declaration.live && args = [] && List.mem t.ty [Ty.Float; Ty.Int; Ty.Bool] then
            {registers = [|emit (Frame declaration.name)|]; constant = None}
          else begin
            let width = List.fold_left (fun n e -> max n (Array.length e.registers)) 1 expressions in
            if t.ty = Ty.Int then refuse ~at:t "E_PACKED_OPERATOR" ("Dynamic integer operation " ^ op ^ " requires reference evaluation.");
            let registers = match kind, expressions with
              | Flow.Op.Noise3, a::rest when Array.length a.registers=3 ->
                  let configuration=List.map2(fun (name,_) expression ->
                    name,match expression.constant with Some value->value|None->
                      refuse ~at:t "E_PACKED_CONSTANT" ("Noise configuration " ^ name ^ " must be constant."))
                    (List.tl args) rest in
                  let integer name default=Option.fold ~none:default ~some:V.int_of
                    (List.assoc_opt name configuration)in
                  let seed=integer "seed" 0 and octaves=integer "octaves" 1 in
                  if not (Flow.Packed_ops.supported_noise_octaves octaves) then
                    refuse ~at:t "E_PACKED_CONSTANT" (Printf.sprintf "Packed noise octaves must be 1 to 32, got %d." octaves);
                  [|emit (Noise3 (a.registers.(0), a.registers.(1), a.registers.(2), seed, octaves))|]
              | Flow.Op.Exact, [a] -> a.registers
              | Flow.Op.Length, [a] when Array.length a.registers = 3 ->
                  let square i = emit (Binary (Mul, a.registers.(i), a.registers.(i))) in
                  let xx = square 0 and yy = square 1 and zz = square 2 in
                  let xy = emit (Binary (Add, xx, yy)) in
                  let sum = emit (Binary (Add, xy, zz)) in
                  [|emit (Unary (Sqrt, sum))|]
              | Flow.Op.Binary op, [a; b] ->
                  Array.init width (fun i -> emit (Binary (op, component a i, component b i)))
              | Flow.Op.Unary op, [a] when width = 1 ->
                  [|emit (Unary (op, a.registers.(0)))|]
              | _ -> refuse ~at:t "E_PACKED_OPERATOR" (Printf.sprintf
                  "Dynamic operator %s has no packed instruction for %d arguments at width %d." op (List.length expressions) width) in
            {registers; constant = None}
          end
      | Let (bindings, result) ->
          let env = List.fold_left (fun env (p, t) -> match p with
            | W.Name n -> (n, expression env t) :: env
            | _ -> refuse ~at:t "E_PACKED_FORM" "Packed let bindings require name patterns.") env bindings in
          expression env result
      | Expanded {body; _} | Bypass body -> expression env body
      | _ -> refuse ~at:t "E_PACKED_FORM" ("Unsupported packed body form " ^
          Option.value ~default:(Ty.to_string t.ty) (Flow.Syntax.head t.form) ^ ".")
      with V.Fail (code, message, span) ->
        raise (Compile_refused (Flow.Diagnostic.error ~span:(Option.value ~default:t.form.span span) ~code message)) in
    let output = (expression env body).registers in
    let result_ty = match term.ty with Ty.Array ty -> ty | ty -> ty in
    if not (List.mem result_ty [Ty.Float;Ty.Vec2;Ty.Vec3;Ty.Vec4]) then
      refuse "E_PACKED_TYPE" ("Packed result must be float or vector, got " ^ Ty.to_string result_ty ^ ".");
    let width = width_of result_ty in
    (match result with
     | Sum _ | Accumulate _ when not (List.mem body.ty [Ty.Float;Ty.Vec2;Ty.Vec3;Ty.Vec4]) ->
         refuse ~at:body "E_PACKED_TYPE" ("Packed reduction body has unsupported type " ^ Ty.to_string body.ty ^ ".")
     | _ -> ());
    (* array_init also broadcasts a scalar to the requested vector width. *)
    let output = if Array.length output = 1 && width > 1 then Array.make width output.(0) else output in
    if Array.length output <> width then refuse "E_PACKED_TYPE" (Printf.sprintf
      "Packed result has %d components but its type requires %d." (Array.length output) width);
    let counts = Array.map (count_of residual) sources in
    let count = try count_of_sources iteration counts with Unsupported ->
      refuse "E_PACKED_LIMIT" "Packed product source count exceeds the integer limit." in
    let rec paths sites (t : W.term) =
      let sites = match t.path with Some p -> (view.instance, p, view.iter) :: sites | None -> sites in
      let children = match t.node with
        | W.Vec ts -> ts | Get (t, _) | Bypass t | Expanded {body = t; _} -> [t]
        | If (a, b, c) -> [a;b;c] | Op {args; _} -> List.map snd args
        | Cond (arms, d) -> d :: List.concat_map (fun (a,b) -> [a;b]) arms
        | Case (s, arms, d) -> s :: d :: List.map snd arms
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
    Ok (if fusion then fuse_maps program else program)
  with
  | Compile_refused d -> Error [d]
  | V.Fail (code, message, span) ->
      Error [Flow.Diagnostic.error ~span:(Option.value ~default:term.form.span span) ~code message]
  | Invalid_argument message -> Error [Flow.Diagnostic.error ~span:term.form.span ~code:"E_PACKED_LAYOUT"
      ("Packed layout is unsupported: " ^ message)]
  | Unsupported -> Error [Flow.Diagnostic.error ~span:term.form.span ~code:"E_PACKED_FORM"
      "Packed form requires reference evaluation."]
and source_program ~dynamic ~count_source (residual, (term : W.term)) = match term.node with
  | W.Ref_binding (name, []) ->
      (match List.assoc_opt name (E.Private.residual_view residual).bindings with
       | Some (E.Residual r) -> source_program ~dynamic ~count_source (r, (E.Private.residual_view r).term)
       | _ -> None)
  | _ -> compile_impl ~dynamic ~count_source residual term |> Result.to_option
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
    let dependent = Array.make Flow.Packed_ops.register_limit false and stages = ref t.stages and sites = ref t.sites in
    let shared = Hashtbl.create 64 in
    let emit instruction =
      let key = Marshal.to_string instruction [Marshal.No_sharing] in
      match Hashtbl.find_opt shared key with
      | Some id -> id
      | None ->
          if !ncode >= Flow.Packed_ops.register_limit then raise Unsupported;
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
let compile_result ?fusion ?count_source r term = compile_impl ?fusion ?count_source r term
let compile ?fusion ?count_source r term = compile_result ?fusion ?count_source r term |> Result.to_option
let compile_template ?count_source r term = compile_impl ~dynamic:true ?count_source r term |> Result.to_option
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

let ordered_add t =
  let width = Array.length t.output in
  match t.result with
  | Accumulate (_, false) when width >= 1 && width <= 4 && t.iteration = Zip
      && Array.length t.sources = 1 && t.widths = [|width|] && Array.length t.skip = 0
      && Array.length t.code = 3 * width && Array.length t.dependent = 3 * width ->
      let matched = ref true in
      for k = 0 to width - 1 do
        if t.code.(k) <> Input (0, width, k) || t.dependent.(k)
          || t.code.(width+k) <> Accumulator k || not t.dependent.(width+k)
          || t.code.(2*width+k) <> Binary (Add, width+k, k) || not t.dependent.(2*width+k)
          || t.output.(k) <> 2*width+k then matched := false
      done;
      !matched
  | _ -> false

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
          | Ok program -> force ~state ?elems ?resolve ?measure program ~live
          | Error _ -> E.Private.eval_term ~state ?elems ?resolve residual term ~live) in
    let seed = match t.result with
      | Accumulate (seed, _) -> Some (get (E.Private.eval_term ~state ?elems ?resolve t.residual seed ~live))
      | _ -> None in
    let inputs = Array.mapi (fun i (residual, term) ->
      let value = get (evaluate residual term) in
      match value, t.widths.(i) with
      | E.Float_array xs, 1 | Vec2_array xs, 2 | Vec3_array xs, 3 | Vec4_array xs, 4 -> xs
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
    let uniforms = force_uniforms ~state ?resolve ?measure t ~live in
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
          let width = width_of ty in
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
      | Some (E.Vec2 _ | Vec3 _ | Vec4 _ as value) -> components value
      | Some v -> Array.make width (V.num v) | None -> Array.make width 0. in
    let initialized = ref (match t.result with Sum zero -> zero | _ -> true) in
    let ordered_add = ordered_add t in
    let block_size = 1024 in
    let blocks = if count = 0 then 0 else (count - 1) / block_size + 1 in
    let blocks_per_chunk = 16 in
    let chunks = if blocks = 0 then 0 else (blocks - 1) / blocks_per_chunk + 1 in
    let chunk chunk =
      if ordered_add then begin
        let source = inputs.(0) in
        let first = chunk * blocks_per_chunk * block_size
        and last = min count ((chunk + 1) * blocks_per_chunk * block_size) - 1 in
        if width = 3 then begin
          let x = ref accumulator.(0) and y = ref accumulator.(1)
          and z = ref accumulator.(2) in
          for i = first to last do
            let offset = i * 3 in
            let next = !x +. source.(offset) in
            if not (Float.is_finite next) then raise Nonfinite;
            x := next;
            let next = !y +. source.(offset + 1) in
            if not (Float.is_finite next) then raise Nonfinite;
            y := next;
            let next = !z +. source.(offset + 2) in
            if not (Float.is_finite next) then raise Nonfinite;
            z := next
          done;
          accumulator.(0) <- !x;
          accumulator.(1) <- !y;
          accumulator.(2) <- !z
        end else
        for i = first to last do
          for component = 0 to width - 1 do
            let x = accumulator.(component) +. source.(i * width + component) in
            if not (Float.is_finite x) then raise Nonfinite;
            accumulator.(component) <- x
          done
        done
      end else begin
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
        | Accumulator component ->
            for j = first to last - 1 do scratch.(at + j) <- accumulator.(component) done
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
          let x = scratch.(t.output.(component) * block_size + j) in
          if not (Float.is_finite x) then raise Nonfinite;
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
      done end in
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
    let value = if collecting then (match width with 2 -> E.Vec2_array output
      | 3 -> E.Vec3_array output | 4 -> E.Vec4_array output | _ -> E.Float_array output)
    else match t.result, seed with
      | Accumulate _, Some seed when kept = 0 -> seed
      | Sum false, _ when kept = 0 -> E.Int 0
      | _ -> (match width with
          | 2 -> E.Vec2 (accumulator.(0), accumulator.(1))
          | 3 -> E.Vec3 (accumulator.(0), accumulator.(1), accumulator.(2))
          | 4 -> E.Vec4 (accumulator.(0), accumulator.(1), accumulator.(2), accumulator.(3))
          | _ -> E.Float accumulator.(0)) in
    Option.iter (fun (clock, report) -> report t ~seconds:(max 0. (clock () -. Option.get started)) ~reference:false) measure;
    value in
  let result = E.transaction state (fun () ->
    try Ok (work ()) with
    | Failed d -> Error d
    | Nonfinite | Unsupported -> Error (Flow.Diagnostic.error ~code:"E_KERNEL" "Kernel needs reference evaluation.")
    | V.Fail (code, message, span) -> Error (Flow.Diagnostic.error ?span ~code message)
    | Invalid_argument message -> Error (Flow.Diagnostic.error ~code:"E_KERNEL" ("Kernel needs reference evaluation: " ^ message))
    | Out_of_memory -> Error (Flow.Diagnostic.error ~code:"E_ARRAY_MEMORY" "Frame data exceeds available memory.")) in
  match result with Ok _ -> result | Error _ ->
    let started = Option.map (fun (clock, _) -> clock ()) measure in
    let result = reference ~state ?elems ?resolve t ~live in
    Option.iter (fun (clock, report) -> report t ~seconds:(max 0. (clock () -. Option.get started)) ~reference:true) measure;
    result

and force_uniforms ~state ?elems ?resolve ?measure t ~live =
  let execute residual live =
    match compile_impl ~fusion:t.fusion ~dynamic:t.dynamic ~count_source:t.count_source
      residual (E.Private.residual_view residual).term with
    | Ok packed -> Some (force ~state ?elems ?resolve ?measure packed ~live)
    | Error _ -> None in
  match get (E.Private.force_with_executor ~state ?elems ?resolve ~compiled:false ~execute
    (E.List t.uniforms) ~live) with
  | E.List values -> Array.map components values
  | _ -> assert false

module Private = struct
  let ordered_add = ordered_add
  let output_reachable = output_reachable
  type view = {code : instruction array; widths : int array; output : int array;
    uniform_widths : int array; collecting : bool; }
  let view (t : t) =
    let uniform_widths = Array.make (Array.length t.uniforms) 1 in
    Array.iter (function Uniform (index, component) ->
      uniform_widths.(index) <- max uniform_widths.(index) (component+1) | _ -> ()) t.code;
    {code=t.code; widths=t.widths; output=t.output; uniform_widths;
      collecting=(match t.result with Collect -> true | _ -> false);
      }
  type inputs = {arrays : float array array; uniforms : float array array;
    frame : float array; count : int}
  let prepare ?state ?resolve ?measure (t : t) ~live =
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
        | Ok program -> get (force ~state ?resolve program ~live)
        | Error _ -> get (E.Private.eval_term ~state ?resolve residual term ~live) in
      let arrays = Array.mapi (fun index (residual, term) ->
        match evaluate residual term, t.widths.(index) with
        | E.Float_array values, 1 | Vec2_array values, 2 | Vec3_array values, 3 | Vec4_array values, 4 -> values
        | _ -> V.fail "E_ARRAY_TYPE" "Kernel input changed its packed element type.") t.sources in
      let count = if arrays=[||] then 0 else Array.fold_left min max_int
        (Array.mapi (fun index values -> Array.length values / t.widths.(index)) arrays) in
      let uniforms = force_uniforms ~state ?resolve ?measure t ~live in
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
      | Invalid_argument message -> Error (Flow.Diagnostic.error ~code:"E_KERNEL" ("Kernel inputs need reference evaluation: " ^ message))
      | Out_of_memory -> Error (Flow.Diagnostic.error ~code:"E_ARRAY_MEMORY" "Frame data exceeds available memory."))
end
