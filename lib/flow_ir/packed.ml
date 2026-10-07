module E = Flow.Eval
module W = Flow.Workspace
module V = Flow.Value
module Ty = Flow.Ty

type binary = Add | Sub | Mul | Div | Mod | Pow | Min | Max
type unary = Sin | Cos | Sqrt | Abs
type instruction = Const of float | Input of int * int * int
  | Uniform of int * int | Frame of string
  | Binary of binary * int * int | Unary of unary * int | Noise3 of int * int * int
type expression = { registers : int array; constant : E.value option }
type t = { residual : E.residual; term : W.term; sources : W.term array;
  widths : int array; uniforms : E.value array; code : instruction array;
  output : int array; count : int option }
exception Unsupported

let compile residual (term : W.term) =
  let view = E.Private.residual_view residual in
  if view.previous || E.state_dependent (E.Residual residual) then None else
  try
    let params, body, sources = match term.node with
      | W.Hof (`Map, {node = W.Fn {params; body; _}; _} :: sources) -> params, body, sources
      | _ -> raise Unsupported in
    let sources = Array.of_list sources in
    let widths = Array.map (fun (s : W.term) -> match s.ty with
      | Ty.Array Ty.Float -> 1 | Ty.Array Ty.Vec3 -> 3 | _ -> raise Unsupported) sources in
    if Array.length sources <> List.length params then raise Unsupported;
    let code = ref [] and size = ref 0 and uniforms = ref [] and nuniforms = ref 0 in
    let emit instruction =
      (* ponytail: cap scratch at 512 KiB per block; measure larger bodies before raising it. *)
      if !size >= 64 then raise Unsupported;
      let id = !size in incr size; code := instruction :: !code; id in
    let literal v =
      let data = match v with
        | E.Int n -> [|float n|] | Float f -> [|f|] | Vec3 (x, y, z) -> [|x; y; z|]
        | _ -> raise Unsupported in
      {registers = Array.map (fun f -> emit (Const f)) data; constant = Some v} in
    let input i width = {registers = Array.init width (fun j -> emit (Input (i, width, j))); constant = None} in
    let uniform v = match v with
      | E.Residual r ->
          let ty = (E.Private.residual_view r).term.ty in
          let width = if ty = Ty.Vec3 then 3 else if ty = Ty.Float then 1 else raise Unsupported in
          let i = !nuniforms in incr nuniforms; uniforms := v :: !uniforms;
          {registers = Array.init width (fun j -> emit (Uniform (i, j))); constant = None}
      | _ -> literal v in
    let env = List.mapi (fun i (pattern, annotation) ->
      match pattern with
      | W.Name name when annotation = None || annotation = Some (if widths.(i) = 3 then Ty.Vec3 else Ty.Float) ->
          name, input i widths.(i)
      | _ -> raise Unsupported) params in
    let captures = Hashtbl.create 16 in
    let captured name = match Hashtbl.find_opt captures name with
      | Some e -> e
      | None ->
          let e = match List.assoc_opt name view.bindings with Some v -> uniform v | None -> raise Unsupported in
          Hashtbl.add captures name e; e in
    let field e = function
      | "x" when Array.length e.registers = 3 -> {registers = [|e.registers.(0)|]; constant = None}
      | "y" when Array.length e.registers = 3 -> {registers = [|e.registers.(1)|]; constant = None}
      | "z" when Array.length e.registers = 3 -> {registers = [|e.registers.(2)|]; constant = None}
      | _ -> raise Unsupported in
    let binary = function "+" -> Add | "-" -> Sub | "*" -> Mul | "/" -> Div
      | "mod" -> Mod | "pow" -> Pow | "min" -> Min | "max" -> Max | _ -> raise Unsupported in
    let unary = function "sin" -> Sin | "cos" -> Cos | "sqrt" -> Sqrt | "abs" -> Abs | _ -> raise Unsupported in
    let rec expression env (t : W.term) =
      match t.node with
      | W.Lit (Param.Int_value n) -> literal (E.Int n)
      | Lit (Param.Float_value f) -> literal (E.Float f)
      | Ref_binding (name, fields) ->
          let e = match List.assoc_opt name env with Some e -> e | None -> captured name in
          List.fold_left field e fields
      | Time -> {registers = [|emit (Frame "t")|]; constant = None}
      | Vec ts when List.length ts = 3 ->
          let components = List.map (expression env) ts in
          if not (List.for_all (fun e -> Array.length e.registers = 1) components) then raise Unsupported;
          {registers = Array.of_list (List.map (fun e -> e.registers.(0)) components); constant = None}
      | Get (t, f) -> field (expression env t) f
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
          else if declaration.live && args = [] && t.ty = Ty.Float then
            {registers = [|emit (Frame declaration.name)|]; constant = None}
          else begin
            let width = List.fold_left (fun n e -> max n (Array.length e.registers)) 1 expressions in
            if t.ty = Ty.Int || t.ty = Ty.Bool then raise Unsupported;
            let component e i = e.registers.(if Array.length e.registers = 1 then 0 else i) in
            let registers = match expressions with
              | [a] when declaration == Operators.noise3 && width = 3 ->
                  [|emit (Noise3 (a.registers.(0), a.registers.(1), a.registers.(2)))|]
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
    let width = match term.ty with Ty.Array Ty.Float -> 1 | Ty.Array Ty.Vec3 -> 3 | _ -> raise Unsupported in
    (* array_init also broadcasts a scalar to vec3. *)
    let output = if Array.length output = 1 && width = 3 then Array.make 3 output.(0) else output in
    if Array.length output <> width then raise Unsupported;
    let count_of (s : W.term) = match s.node with
      | W.Ref_binding (name, []) -> (match List.assoc_opt name view.bindings with
          | Some (E.Float_array _ | Vec3_array _ as v) -> Some (V.array_length v) | _ -> None)
      | Op {op = ("array/float" | "array/vec3" | "array/range"); args; _} ->
          (match List.assoc_opt "count" args with
           | Some {node = W.Lit (Param.Int_value n); _} when n >= 0 -> Some n | _ -> None)
      | _ -> None in
    let counts = Array.map count_of sources in
    let count = if counts = [||] then Some 0 else if Array.for_all Option.is_some counts then
      Some (Array.fold_left (fun n c -> min n (Option.get c)) max_int counts) else None in
    Some {residual; term; sources; widths; uniforms = Array.of_list (List.rev !uniforms);
      code = Array.of_list (List.rev !code); output; count}
  with Unsupported | V.Fail _ | Invalid_argument _ -> None

let static_count t = t.count
let noise = Rays_math.Noise.create 0
let reference ?state ?elems t ~live = E.Private.eval_term ?state ?elems t.residual t.term ~live
exception Failed of Flow.Diagnostic.t
exception Nonfinite
let get = function Ok x -> x | Error d -> raise (Failed d)

let force ?state ?elems t ~live =
  let state = Option.value ~default:(E.create_state ()) state in
  let work () =
    let inputs = Array.mapi (fun i term ->
      let value = get (E.Private.eval_term ~state ?elems t.residual term ~live) in
      match value, t.widths.(i) with
      | E.Float_array xs, 1 | Vec3_array xs, 3 -> xs
      | _ -> V.fail "E_ARRAY_TYPE" "Kernel input changed its packed element type.") t.sources in
    let count = Array.fold_left min max_int (Array.mapi (fun i a -> Array.length a / t.widths.(i)) inputs) in
    let count = if inputs = [||] then 0 else count in
    let uniforms = Array.map (fun v ->
      let v = get (E.Private.force_reference ~state ?elems v ~live) in
      match v with E.Vec3 (x, y, z) -> [|x; y; z|] | _ -> [|V.num v|]) t.uniforms in
    let frame = Array.map (function
      | Frame "t" -> live.Frame_input.t
      | Frame name ->
          (match Flow.Op.find name Flow.Context.value with
           | Some op -> V.num (op.body ~live ~node:(fun _ _ -> raise Unsupported) [])
           | None -> raise Unsupported)
      | _ -> 0.) t.code in
    let width = Array.length t.output in
    if count > Sys.max_floatarray_length / width then V.fail "E_ARRAY_RANGE" "Kernel output exceeds native storage bounds.";
    let output = Array.make (count * width) 0. in
    let block_size = 1024 in
    let blocks = if count = 0 then 0 else (count - 1) / block_size + 1 in
    let blocks_per_chunk = 16 in
    let chunks = if blocks = 0 then 0 else (blocks - 1) / blocks_per_chunk + 1 in
    Rays_math.Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(chunks - 1) (fun chunk ->
      let scratch = Array.make (Array.length t.code * block_size) 0. in
      for block = chunk * blocks_per_chunk to min blocks ((chunk + 1) * blocks_per_chunk) - 1 do
      let start = block * block_size and length = min block_size (count - block * block_size) in
      Array.iteri (fun slot instruction ->
        let at = slot * block_size in
        match instruction with
        | Const x -> Array.fill scratch at length x
        | Input (input, width, component) ->
            let source = inputs.(input) in
            for j = 0 to length - 1 do scratch.(at + j) <- source.((start + j) * width + component) done
        | Uniform (uniform, component) -> Array.fill scratch at length uniforms.(uniform).(component)
        | Frame _ -> Array.fill scratch at length frame.(slot)
        | Noise3 (x, y, z) ->
            Rays_math.Noise.Private.sample3_into noise ~first:0 ~last:length
              ~x:scratch ~x_offset:(x * block_size) ~y:scratch ~y_offset:(y * block_size)
              ~z:scratch ~z_offset:(z * block_size) ~output:scratch ~output_offset:at ()
        | Binary (operation, a, b) ->
            let a = a * block_size and b = b * block_size in
            (match operation with
             | Add -> for j = 0 to length - 1 do let x = scratch.(a+j) +. scratch.(b+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Sub -> for j = 0 to length - 1 do let x = scratch.(a+j) -. scratch.(b+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Mul -> for j = 0 to length - 1 do let x = scratch.(a+j) *. scratch.(b+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Div -> for j = 0 to length - 1 do let y = scratch.(b+j) in
                 let x = if y = 0. then 0. else scratch.(a+j) /. y in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Mod -> for j = 0 to length - 1 do let y = scratch.(b+j) in
                 let x = if y = 0. then 0. else Float.rem (Float.rem scratch.(a+j) y +. y) y in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Pow -> for j = 0 to length - 1 do let x = Float.pow (Float.abs scratch.(a+j)) scratch.(b+j) in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Min -> for j = 0 to length - 1 do let x = Float.min scratch.(a+j) scratch.(b+j) in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Max -> for j = 0 to length - 1 do let x = Float.max scratch.(a+j) scratch.(b+j) in
                 if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done)
        | Unary (operation, a) ->
            let a = a * block_size in
            (match operation with
             | Sin -> for j = 0 to length - 1 do let x = sin scratch.(a+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Cos -> for j = 0 to length - 1 do let x = cos scratch.(a+j) in if not (Float.is_finite x) then raise Nonfinite; scratch.(at+j) <- x done
             | Sqrt -> for j = 0 to length - 1 do scratch.(at+j) <- sqrt (Float.abs scratch.(a+j)) done
             | Abs -> for j = 0 to length - 1 do scratch.(at+j) <- Float.abs scratch.(a+j) done)) t.code;
      for j = 0 to length - 1 do
        for component = 0 to width - 1 do
          let x = scratch.(t.output.(component) * block_size + j) in if not (Float.is_finite x) then raise Nonfinite;
          output.((start+j) * width + component) <- x
        done
      done
      done);
    if width = 3 then E.Vec3_array output else E.Float_array output in
  let result = E.transaction state (fun () ->
    try Ok (work ()) with
    | Failed d -> Error d
    | Nonfinite | Unsupported -> Error (Flow.Diagnostic.error ~code:"E_KERNEL" "Kernel needs reference evaluation.")
    | V.Fail (code, message, span) -> Error (Flow.Diagnostic.error ?span ~code message)
    | Out_of_memory -> Error (Flow.Diagnostic.error ~code:"E_ARRAY_MEMORY" "Frame data exceeds available memory.")) in
  match result with Ok _ -> result | Error _ -> reference ~state ?elems t ~live
