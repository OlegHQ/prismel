type op = Add | Sub | Mul | Div | Pow | Min | Max | Sin | Cos | Abs | Floor | Sqrt
type t = Num of float | Time | Op of op * t list

let operators = ["add", Add; "sub", Sub; "mul", Mul; "div", Div; "pow", Pow;
  "min", Min; "max", Max; "sin", Sin; "cos", Cos; "abs", Abs; "floor", Floor; "sqrt", Sqrt]
let name = function Add -> "add" | Sub -> "sub" | Mul -> "mul" | Div -> "div"
  | Pow -> "pow" | Min -> "min" | Max -> "max" | Sin -> "sin" | Cos -> "cos"
  | Abs -> "abs" | Floor -> "floor" | Sqrt -> "sqrt"
let symbol = function Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/" | op -> name op
let arity = function Sin | Cos | Abs | Floor | Sqrt -> 1 | _ -> 2
let arity_error operator arguments = Diagnostic.error ~code:"E_ARITY"
  (Printf.sprintf "%s takes %d argument%s, got %d" (symbol operator) (arity operator)
    (if arity operator = 1 then "" else "s") (List.length arguments))
let num number = if Float.is_finite number then Ok (Num number) else
  Error (Diagnostic.error ~code:"E_TYPE" "An expression number must be finite")
let time = Time
let op operator arguments = if List.length arguments = arity operator then
  Ok (Op (operator, arguments)) else Error (arity_error operator arguments)
let apply operator arguments = match operator, arguments with
  | Add, [a;b] -> Ok (a +. b) | Sub, [a;b] -> Ok (a -. b)
  | Mul, [a;b] -> Ok (a *. b) | Div, [a;b] -> Ok (if b = 0. then 0. else a /. b)
  | Pow, [a;b] -> Ok (abs_float a ** b) | Min, [a;b] -> Ok (Float.min a b)
  | Max, [a;b] -> Ok (Float.max a b) | Sin, [a] -> Ok (sin a)
  | Cos, [a] -> Ok (cos a) | Abs, [a] -> Ok (abs_float a)
  | Floor, [a] -> Ok (floor a) | Sqrt, [a] -> Ok (sqrt (abs_float a))
  | _ -> Error (arity_error operator arguments)

type task = Visit of t | Apply of op
let eval ~time root =
  let rec run tasks values = match tasks with
    | [] -> (match values with [value] -> Ok value
        | _ -> Error (Diagnostic.error ~code:"E_ARITY" "Invalid expression stack"))
    | Visit (Num value) :: rest -> run rest (value :: values)
    | Visit Time :: rest -> run rest (time :: values)
    | Visit (Op (operator, arguments)) :: rest ->
        if List.length arguments <> arity operator then Error (arity_error operator arguments)
        else run (List.fold_right (fun argument rest -> Visit argument :: rest)
          arguments (Apply operator :: rest)) values
    | Apply operator :: rest ->
        let arguments, remaining = match arity operator, values with
          | 1, a :: remaining -> [a], remaining
          | 2, b :: a :: remaining -> [a;b], remaining
          | _ -> [], values in
        Result.bind (apply operator arguments) (fun value -> run rest (value :: remaining))
  in run [Visit root] []

let depends_on_time root =
  let rec visit = function
    | [] -> false | Time :: _ -> true | Num _ :: rest -> visit rest
    | Op (_, arguments) :: rest -> visit (List.rev_append arguments rest)
  in visit [root]

type token_kind = Number of float | Word of string | Mark of char | End
type token = { kind : token_kind; span : Diagnostic.span }
let tokenize source =
  let length = String.length source in
  let digit = function '0' .. '9' -> true | _ -> false in
  let letter = function 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false in
  let rec read offset tokens =
    if offset = length then Ok (Array.of_list (List.rev
      ({kind = End; span = {start = offset; finish = offset}} :: tokens)))
    else match source.[offset] with
    | ' ' | '\t' | '\r' | '\n' -> read (offset + 1) tokens
    | ('(' | ')' | ',' | '+' | '-' | '*' | '/' | '^') as mark ->
        read (offset + 1) ({kind = Mark mark; span = {start = offset; finish = offset+1}} :: tokens)
    | c when digit c || (c = '.' && offset + 1 < length && digit source.[offset+1]) ->
        let hex = offset + 1 < length && source.[offset] = '0'
          && (source.[offset+1] = 'x' || source.[offset+1] = 'X') in
        let finish = ref (offset + 1) in
        let numeric c = digit c || c = '_' || c = '.'
          || (if hex then (match c with 'a' .. 'f' | 'A' .. 'F' | 'x' | 'X' | 'p' | 'P' -> true | _ -> false)
              else c = 'e' || c = 'E') in
        let exponent c = if hex then c = 'p' || c = 'P' else c = 'e' || c = 'E' in
        while !finish < length && (numeric source.[!finish]
          || ((source.[!finish] = '+' || source.[!finish] = '-') && exponent source.[!finish-1])) do
          incr finish
        done;
        let text = String.sub source offset (!finish - offset) in
        let span = Diagnostic.{start = offset; finish = !finish} in
        (match float_of_string_opt text with
         | Some number when Float.is_finite number -> read !finish ({kind = Number number; span} :: tokens)
         | _ -> Error (Diagnostic.error ~span ~code:"E_TYPE" (Printf.sprintf "%S is not a finite number" text)))
    | c when letter c ->
        let finish = ref (offset + 1) in
        while !finish < length && (letter source.[!finish] || digit source.[!finish]) do incr finish done;
        let word = String.sub source offset (!finish - offset) in
        read !finish ({kind = Word word; span = {start = offset; finish = !finish}} :: tokens)
    | c -> Error (Diagnostic.error ~span:{start = offset; finish = offset + 1}
        ~code:"E_UNEXPECTED" (Printf.sprintf "Unexpected character %C" c))
  in read 0 []

type stream = { tokens : token array; mutable index : int }
let peek stream = stream.tokens.(stream.index)
let take stream = let token = peek stream in
  (match token.kind with End -> () | _ -> stream.index <- stream.index + 1); token
let error token code message = Error (Diagnostic.error ~span:token.span ~code message)
let located token result = Result.map_error (fun (diagnostic : Diagnostic.t) ->
  if diagnostic.span = None then {diagnostic with span = Some token.span} else diagnostic) result
let binary = function '+' -> Some (Add,1) | '-' -> Some (Sub,1) | '*' -> Some (Mul,2)
  | '/' -> Some (Div,2) | '^' -> Some (Pow,3) | _ -> None
let functions = ["pow", Pow; "min", Min; "max", Max; "sin", Sin; "cos", Cos;
  "abs", Abs; "floor", Floor; "sqrt", Sqrt]
let close stream opening = match (peek stream).kind with
  | Mark ')' -> ignore (take stream); Ok ()
  | End -> error opening "E_UNCLOSED" "This \"(\" is never closed"
  | _ -> error (peek stream) "E_UNEXPECTED" "Expected \")\""
let finish stream result = Result.bind result (fun expression ->
  match (peek stream).kind with End -> Ok expression
  | _ -> error (peek stream) "E_UNEXPECTED" "Unexpected token after expression")

let infix_tokens tokens =
  let stream = {tokens; index = 0} in
  let rec expression minimum = Result.bind (primary ()) (rest minimum)
  and rest minimum left = match (peek stream).kind with
    | Mark mark -> (match binary mark with
        | Some (operator, precedence) when precedence >= minimum ->
            let token = take stream in
            Result.bind (expression (if operator = Pow then precedence else precedence + 1))
              (fun right -> Result.bind (located token (op operator [left;right])) (rest minimum))
        | _ -> Ok left)
    | _ -> Ok left
  and primary () =
    let token = take stream in
    match token.kind with
    | Number number -> Ok (Num number)
    | Mark '-' -> Result.bind (primary ()) (fun value -> match value with
        | Num number -> Ok (Num (-. number))
        | _ -> located token (op Sub [Num 0.;value]))
    | Mark '(' ->
        let nested = expression 0 in
        (match nested with
         | Error diagnostic when diagnostic.Diagnostic.code <> "E_UNCLOSED"
             && (peek stream).kind = End -> error token "E_UNCLOSED" "This \"(\" is never closed"
         | _ -> Result.bind nested (fun value ->
             Result.map (fun () -> value) (close stream token)))
    | Word name ->
        if (peek stream).kind = Mark '(' then
          (match List.assoc_opt name functions with
           | None -> error token "E_UNBOUND" (Printf.sprintf "Unknown function %s" name)
           | Some operator ->
               let opening = take stream in
               Result.bind (arguments opening []) (fun values -> located token (op operator values)))
        else if name = "t" then Ok Time
        else if name = "pi" then Ok (Num Float.pi)
        else error token "E_UNBOUND" (Printf.sprintf "Unknown name %s; use t for time" name)
    | End -> error token "E_UNEXPECTED" "Expression ends too early"
    | _ -> error token "E_UNEXPECTED" "Expected a number, t, function or parenthesis"
  and arguments opening reversed =
    if (peek stream).kind = Mark ')' && reversed = [] then
      (ignore (take stream); Ok [])
    else if (peek stream).kind = End then error opening "E_UNCLOSED" "This \"(\" is never closed"
    else Result.bind (expression 0) (fun argument ->
      let reversed = argument :: reversed in
      match (peek stream).kind with
      | Mark ',' -> ignore (take stream); arguments opening reversed
      | _ -> Result.map (fun () -> List.rev reversed) (close stream opening))
  in finish stream (expression 0)

let sexp_tokens tokens =
  let stream = {tokens; index = 0} in
  let rec expression () =
    let token = take stream in
    match token.kind with
    | Number number -> Ok (Num number) | Word "t" -> Ok Time | Word "pi" -> Ok (Num Float.pi)
    | Mark '-' -> (match (take stream).kind with
        | Number number -> Ok (Num (-.number))
        | _ -> error token "E_UNEXPECTED" "Expected a number after minus")
    | Mark '(' ->
        let head = take stream in
        let operator = match head.kind with
          | Mark '+' -> Some Add | Mark '-' -> Some Sub | Mark '*' -> Some Mul
          | Mark '/' -> Some Div | Word name -> List.assoc_opt name functions | _ -> None in
        (match operator with
         | None when head.kind = End -> error token "E_UNCLOSED" "This \"(\" is never closed"
         | None -> error head "E_UNBOUND" "Unknown expression operator"
         | Some operator -> Result.bind (arguments token []) (fun values -> located head (op operator values)))
    | Word name -> error token "E_UNBOUND" (Printf.sprintf "Unknown name %s; use t for time" name)
    | _ -> error token "E_UNEXPECTED" "Expected an expression"
  and arguments opening reversed = match (peek stream).kind with
    | Mark ')' -> ignore (take stream); Ok (List.rev reversed)
    | End -> error opening "E_UNCLOSED" "This \"(\" is never closed"
    | _ -> Result.bind (expression ()) (fun value -> arguments opening (value :: reversed))
  in finish stream (expression ())

let parse_with parser source =
  (* ponytail: recursive syntax parsing is bounded by the OCaml stack;
     use an explicit parser stack if very deep field expressions are needed. *)
  try Result.bind (tokenize source) parser with Stack_overflow ->
    Error (Diagnostic.error ~code:"E_DEPTH" "Expression exceeds the parser stack capacity")
let parse_infix = parse_with infix_tokens
let parse_sexp = parse_with sexp_tokens
let parse source = parse_with (fun tokens ->
  let parenthesized = tokens.(0).kind = Mark '(' in
  let probable = parenthesized && (match tokens.(1).kind with
    | Mark ('+' | '-' | '*' | '/') -> true
    | Word name -> List.mem_assoc name functions
    | _ -> false) in
  let spaced_head = probable && Array.length tokens > 2
    && tokens.(1).span.finish < tokens.(2).span.start in
  let first, second = if spaced_head then sexp_tokens, infix_tokens else infix_tokens, sexp_tokens in
  match first tokens with
  | Ok _ as result -> result
  | Error original when not parenthesized -> Error original
  | Error original -> match second tokens with
      | Ok _ as result -> result
      | Error other -> Error (if probable && not spaced_head then other else original)) source

let precedence = function Add | Sub -> 1 | Mul | Div -> 2 | Pow -> 3 | _ -> 4
let infix root =
  let buffer = Buffer.create 64 in
  let rec write minimum = function
    | Num number -> Printf.bprintf buffer "%.17g" number
    | Time -> Buffer.add_char buffer 't'
    | Op ((Add | Sub | Mul | Div | Pow as operator), [left;right]) ->
        let priority = precedence operator in
        let parentheses = priority < minimum in
        if parentheses then Buffer.add_char buffer '(';
        write (if operator = Pow then priority+1 else priority) left;
        Printf.bprintf buffer " %s " (if operator = Pow then "^" else symbol operator);
        write (if operator = Pow then priority else priority+1) right;
        if parentheses then Buffer.add_char buffer ')'
    | Op (operator, arguments) ->
        Buffer.add_string buffer (name operator); Buffer.add_char buffer '(';
        List.iteri (fun index argument -> if index > 0 then Buffer.add_string buffer ", "; write 0 argument) arguments;
        Buffer.add_char buffer ')'
  in write 0 root; Buffer.contents buffer

let sexp root =
  let buffer = Buffer.create 64 in
  let rec write = function
    | Num number -> Printf.bprintf buffer "%.17g" number
    | Time -> Buffer.add_char buffer 't'
    | Op (operator, arguments) ->
        Buffer.add_char buffer '('; Buffer.add_string buffer (symbol operator);
        List.iter (fun argument -> Buffer.add_char buffer ' '; write argument) arguments;
        Buffer.add_char buffer ')'
  in write root; Buffer.contents buffer
