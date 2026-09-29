open Flow
open Expr

let get = function Ok value -> value | Error diagnostic -> failwith (Diagnostic.to_string diagnostic)
let parse_get source = get (parse source)
let evaluate source = get (eval ~time:2. (parse_get source))
let () =
  List.iter (fun (source, expected) -> assert (evaluate source = expected))
    ["2 + 3 * 4", 14.; "2 ^ 3 ^ 2", 512.; "(2 ^ 3) ^ 2", 64.;
     "-t ^ 2", 4.; "-(t ^ 2)", -4.; "pow(-2, 3)", 8.;
     "sqrt(-9) + abs(-2)", 5.; "9 / 0", 0.; "floor(-1.5)", -2.;
     "sin(0) + cos(0)", 1.; "min(1, max(2, 3))", 1.;
     "(+ t (* 2 3))", 8.; "(/ 1 0)", 0.; "(sin t)", sin 2.;
     "1e-3 + 2E+2", 200.001; "0xbe-2", 188.; "0x1.fp2", 7.75;
     "1_000.5 - .5", 1000.; "pi", Float.pi];
  assert (Int64.bits_of_float (evaluate "-0") = Int64.min_int);
  assert (Result.is_error (num nan));
  assert (Result.is_error (op Sin []));
  assert (Result.is_error (apply Add [1.]));
  List.iter (fun value ->
    let printed = sexp_number value in
    assert (Int64.bits_of_float (float_of_string printed) =
      Int64.bits_of_float value);
    match Sexp.parse printed with
    | Ok [{node = Sexp.Atom (Sexp.Number _); _}] -> ()
    | _ -> failwith ("Flow reader rejected printed number " ^ printed))
    [-0.; 1e-100; 1e20; Float.min_float; Float.max_float;
      Int64.float_of_bits 1L];
  assert (sexp_number ~precision:6 0.040000000000000001 = "0.04");
  assert (sexp_number ~precision:6 1.3999999999999999 = "1.4");
  assert (sexp ~precision:6 (get (num 0.56000000000000005)) = "0.56");
  let number value = get (num value) in
  let atoms = [number (-0.); number (-2.); number 1e-100; time] in
  let forms = ref atoms in
  List.iter (fun (_, operator) -> List.iter (fun a ->
    if arity operator = 1 then forms := get (op operator [a]) :: !forms
    else List.iter (fun b -> forms := get (op operator [a;b]) :: !forms) atoms) atoms) operators;
  let base = !forms in
  List.iter (fun (_, operator) -> List.iter (fun a ->
    if arity operator = 1 then forms := get (op operator [a]) :: !forms
    else List.iter (fun b -> forms := get (op operator [a;b]) :: !forms) atoms) base) operators;
  List.iter (fun expression ->
    let printed = infix expression and canonical = sexp expression in
    if get (parse_infix printed) <> expression then
      failwith (Printf.sprintf "infix round trip: %s; expected %s, got %s"
        printed canonical (sexp (get (parse_infix printed))));
    assert (get (parse_sexp canonical) = expression);
    if parse_get printed <> expression || parse_get canonical <> expression then
      failwith ("automatic syntax round trip: " ^ printed ^ " / " ^ canonical)) !forms;
  let nested = parse_get "1e16 + (-1e16 + 1)" in
  assert (get (eval ~time:0. nested) = 0.);
  assert (infix nested = "10000000000000000 + (-10000000000000000 + 1)");
  List.iter (fun (source, code, offset) -> match parse source with
    | Ok _ -> failwith ("accepted invalid expression: " ^ source)
    | Error diagnostic ->
        assert (diagnostic.code = code);
        assert (Option.map (fun span -> span.Diagnostic.start) diagnostic.span = Some offset))
    ["", "E_UNEXPECTED", 0; "t +", "E_UNEXPECTED", 3;
     "(", "E_UNCLOSED", 0; "(t +", "E_UNCLOSED", 0;
     "(sin t", "E_UNCLOSED", 0; "sin(1, 2)", "E_ARITY", 0;
     "sin()", "E_ARITY", 0; "sin(1,)", "E_UNEXPECTED", 6;
     "(pow 2)", "E_ARITY", 1; "t xyz", "E_UNEXPECTED", 2;
     "unknown", "E_UNBOUND", 0; "1e999", "E_TYPE", 0;
     "1..2", "E_TYPE", 0; "[1]", "E_UNEXPECTED", 0; "t)", "E_UNEXPECTED", 1];
  let deep = List.init 10000 Fun.id |> List.fold_left (fun expression _ ->
    get (op Add [expression;number 1.])) time in
  assert (get (eval ~time:2. deep) = 10002. && depends_on_time deep);
  assert (not (depends_on_time (parse_get "sin(pi)")));
  Printf.printf "Flow expressions: %d exact infix/sexp round trips, located errors and deep evaluation pass\n"
    (List.length !forms)
