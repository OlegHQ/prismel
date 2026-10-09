module E = Flow.Eval
module I = Flow_ir
let ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let checked ?(ops = []) body =
  let text = "(workspace w (graph g :context value (let* [tested " ^ body ^ "] 0.0)))" in
  let forms = ok (Flow.Syntax.parse text) in
  match Flow.Workspace.check ~ops {Flow.Check.version = 1; kinds = []} forms with
    | Some w, [] -> w
    | _, ds -> failwith (text ^ "\n" ^ String.concat "; " (List.map Flow.Diagnostic.to_string ds))
let recorded ?ops body =
  let evaluation = ok (E.static ~record:true (checked ?ops body)) in
  List.assoc ["g"; "tested"] evaluation.records |> List.hd |> snd
let same a b = match a, b with
  | Ok a, Ok b -> Marshal.to_string a [Marshal.No_sharing] = Marshal.to_string b [Marshal.No_sharing]
  | Error a, Error b -> Flow.Diagnostic.to_string a = Flow.Diagnostic.to_string b
  | _ -> false
let has_cpu p = Array.exists (fun (n : I.node) -> n.tier = Cpu_kernel) (I.Executor.graph p).nodes
let stages p = Array.fold_left (fun count (n : I.node) -> match n.kind with
  | Kernel {body = Packed_map p; _} -> max count (I.Packed.stage_count p) | _ -> count)
  0 (I.Executor.graph p).nodes
let compile ?fusion residual term =
  let legacy = I.Packed.compile ?fusion residual term in
  (match legacy, I.Packed.compile_result ?fusion residual term with
   | None, Error [_] -> ()
   | Some a, Ok b ->
       assert (Marshal.to_string (I.Packed.Private.view a) [Marshal.No_sharing]
         = Marshal.to_string (I.Packed.Private.view b) [Marshal.No_sharing]);
       assert (I.Packed.stage_count a = I.Packed.stage_count b
         && I.Packed.provenance a = I.Packed.provenance b
         && I.Packed.static_count a = I.Packed.static_count b)
   | _ -> assert false);
  legacy
let () =
  List.iter (fun (x,y,z) ->
    let expression = Printf.sprintf "(length [%.17g %.17g %.17g])" x y z in
    let expected = E.Float (sqrt ((x *. x +. y *. y) +. z *. z)) in
    assert (Marshal.to_string (recorded expression) [Marshal.No_sharing]
      = Marshal.to_string expected [Marshal.No_sharing]))
    [(-3.,4.,-12.); (0.,0.,0.); (-0.,0.,-0.); (1e-200,-1e-200,1e-200)];
  let value = recorded "(map (fn [p] (if (> t 0) (min (length p) 1.0) 0.0))
    (array/vec3 16385 [1e200 0 0]))" in
  let packed = match value with E.Residual residual ->
    compile residual (E.Private.residual_view residual).term |> Option.get
    | _ -> failwith "length kernel did not defer" in
  List.iter (fun time ->
    let live = Frame_input.at_time time in
    let reference = E.Private.force_reference value ~live in
    (match time, reference with
     | 0., Ok (E.Float_array values) -> assert (Array.for_all ((=) 0.) values)
     | 1., Error d -> assert (d.code = "E_NONFINITE")
     | _ -> assert false);
    List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
      assert (same (I.Packed.force packed ~live) reference))) [1;8]) [0.;1.]
let () =
  List.iter (fun count ->
    let source = Printf.sprintf "(array/range %d)" count in
    let vectors = Printf.sprintf "(array/vec3 %d [0.25 -0.5 1])" count in
    let cases = [
      "(map (fn [x] (+ (+ x t) (floor 1.75))) " ^ source ^ ")";
      "(map (fn [x] [x t]) " ^ source ^ ")";
      "(map (fn [x] [x t (+ x t) -0.0]) " ^ source ^ ")";
      "(map (fn [(p : vec2)] (+ p t)) (map (fn [x] [x 1]) " ^ source ^ "))";
      "(map (fn [(p : vec4)] [p.w p.z p.y (+ p.x t)]) (map (fn [x] [x 1 2 3]) " ^ source ^ "))";
      "(let* [offset [t 1 2 3]] (map (fn [x] (+ [x x x x] offset)) " ^ source ^ "))";
      "(for [x " ^ source ^ "] [x t])";
      "(for [x " ^ source ^ "] :skip [0 1024 16384] [x t 2 3])";
      "(sum [x " ^ source ^ "] [x t])";
      "(array/sum (map (fn [x] [x t 2 3]) " ^ source ^ "))";
      "(scan [a [0.0 0.0]] [x " ^ source ^ "] (+ (* a 0.99) [x t]))";
      "(fold [a [0.0 0.0 0.0 0.0]] [x " ^ source ^ "] (+ (* a 0.99) [x t 2 3]))";
      "(for [x " ^ source ^ "] (sin (+ x t)))";
      "(for [x " ^ source ^ "] :skip [0 1024 16384] (sin (+ x t)))";
      "(for [x " ^ source ^ " y (array/range 3)] (+ (* x 0.25) (+ y t)))";
      "(sum [x " ^ source ^ "] (sin (+ x t)))";
      "(fold [a 0] [x " ^ source ^ "] (- (* a 0.99) (* (+ x t) 0.0001)))";
      "(scan [a 0.0] [x " ^ source ^ "] (- (* a 0.99) (* (+ x t) 0.0001)))";
      "(scan [a [0 0 0]] [x " ^ vectors ^ "] (+ (* a 0.99) (* x t)))";
      "(fold [a [1 2 3]] [x " ^ source ^ "] (+ x t))";
      "(reduce (fn [a x] (+ (* a 0.99) (* x t))) 0.0 " ^ source ^ ")";
      "(let* [f (fn [a x] (+ (* a 0.99) (* x t)))] (reduce f 0.0 " ^ source ^ "))";
      "(array/sum (map (fn [x] (sin (+ x t))) " ^ source ^ "))";
      "(sum [x (array/float " ^ string_of_int count ^ " -0.0)] (* x (+ t 1)))";
      "(array/sum (array/vec3 " ^ string_of_int count ^ " [t -0.0 1]))";
      "(sum [x " ^ source ^ "] (pow (+ x t) 1000000))";
      "(fold [a 0.0] [x " ^ source ^ "] (pow (+ a t) 1000000))"
    ] in
    List.iter (fun body ->
      let value = recorded body in
      let program = ok (I.Executor.compile value) in
      if count >= 1024 && not (has_cpu program) then
        failwith ("No CPU kernel (" ^ Flow.Ty.to_string (Flow.Value.ty_of value) ^ "): " ^ body);
      List.iter (fun time ->
        let live = Frame_input.at_time time in
        let reference = E.Private.force_reference value ~live in
        List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
          let output = I.Executor.force program ~live in
          if not (same output reference) then failwith (Printf.sprintf "Parity failed (%d domains, t=%g): %s" domains time body);
          (* Exercise the register executor even below the placement cutoff. *)
          match value with
          | E.Residual r -> (match compile r (E.Private.residual_view r).term with
              | Some p ->
                  if not (same (I.Packed.force p ~live) reference) then
                    failwith (Printf.sprintf "Direct kernel parity failed (%d domains, t=%g): %s" domains time body)
              | None -> ())
          | _ -> ())) [1; 8]) [0.; 0.125; 1.25; 7.]) cases)
    [0; 1; 1023; 1024; 1025; 2051; 16385];
  let correlated = recorded "(for [x (array/range 3) y (array/float (+ x 1))] (+ y t))" in
  let program = ok (I.Executor.compile correlated) in
  assert (not (has_cpu program));
  assert (same (I.Executor.force program ~live:(Frame_input.at_time 0.125))
    (E.Private.force_reference correlated ~live:(Frame_input.at_time 0.125)));
  List.iter (fun body ->
    let value = recorded body in
    let program = ok (I.Executor.compile value) in
    if stages program < 2 then failwith ("Map chain did not fuse: " ^ body);
    let unfused = match value with E.Residual r ->
      compile ~fusion:false r (E.Private.residual_view r).term |> Option.get
      | _ -> failwith "live map chain did not defer" in
    assert (I.Packed.stage_count unfused = 1);
    List.iter (fun time ->
      let live = Frame_input.at_time time in
      let reference = E.Private.force_reference value ~live in
      List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
        assert (same (I.Executor.force program ~live) reference);
        assert (same (I.Packed.force unfused ~live) reference))) [1;8]) [0.;0.125;1.25;7.])
    ["(map (fn [y] (* y y)) (map (fn [x] (sin (+ x t))) (array/range 16385)))";
     "(let* [a (map (fn [x] (sin (+ x t))) (array/range 16385))] (map (fn [y] (* y y)) a))";
     "(array/sum (map (fn [y] (* y y)) (map (fn [x] (sin (+ x t))) (array/range 16385))))";
     "(fold [a 0.0] [x (map (fn [x] (sin (+ x t))) (array/range 16385))] (+ a x))";
     "(map (fn [p n] (+ p n)) (map (fn [x] (* x t)) (array/vec3 16385 [1 2 3])) (array/vec3 16385 [0 1 0]))";
     "(map (fn [x] (* x t)) (map (fn [x] (+ x t)) (array/range (frame/index))))"];
  (* A shortened zip must still evaluate the producer's unused tail and report its failure. *)
  let value = recorded "(map (fn [x y] (+ x y)) (map (fn [x] (pow (+ x t) 1000000)) (array/range 2051)) (array/float 1))" in
  let program = ok (I.Executor.compile value) in
  assert (stages program = 1);
  assert (same (I.Executor.force program ~live:(Frame_input.at_time 0.))
    (E.Private.force_reference value ~live:(Frame_input.at_time 0.)));
  let ticks = ref 0. in
  let profile = I.Profile.create ~clock:(fun () -> ticks := !ticks +. 0.001; !ticks) in
  let value = recorded "(map (fn [y] (* y y)) (map (fn [x] (sin (+ x t))) (array/range 2051)))" in
  let program = ok (I.Executor.compile ~profile value) in
  ignore (ok (I.Executor.force program ~live:(Frame_input.at_time 1.25)));
  let reports = I.Profile.executions profile in
  assert (List.length reports = 1);
  let report = List.hd reports in
  assert (report.tier = Cpu_kernel && report.seconds > 0.);
  assert (fst report.owner = ["g";"tested"] && List.length report.sites >= 2);
  ignore (ok (I.Executor.force program ~live:(Frame_input.at_time 2.)));
  assert (List.length (I.Profile.executions profile) = 1);
  ignore (ok (I.Executor.force ~reference:true program ~live:(Frame_input.at_time 2.)));
  assert ((List.hd (I.Profile.executions profile)).tier = Interp);
  print_endline "Packed map/for/sum/fold/scan/reduce parity, group timings and one/eight domains"

let () =
  List.iter (fun body ->
    let value = recorded body in
    let packed = match value with E.Residual r ->
      compile r (E.Private.residual_view r).term | _ -> assert false in
    assert (packed = None);
    let program = ok (I.Executor.compile value) in
    List.iter (fun time ->
      let live = Frame_input.at_time time in
      assert (same (I.Executor.force program ~live)
        (E.Private.force_reference value ~live))) [0.;0.25;2.])
    ["(fold [a false] [x (array/range 1024)] (+ x t))";
     "(scan [a false] [x (array/range 1024)] (+ x t))"];
  let fn = match recorded "(fn [(uv : vec2)] [uv.x uv.y t 1])" with
    | E.Fn fn -> fn | _ -> assert false in
  let grid = Array.init (2 * 32769) (fun i -> float (i mod 17) /. 16.) in
  let original = Array.copy grid in
  let value = ok (E.Private.map_function
    ~signature:Flow.Ty.{params = [Vec2]; result = Vec4} fn [E.Vec2_array grid]) in
  let packed = match value with E.Residual r ->
    compile r (E.Private.residual_view r).term |> Option.get | _ -> assert false in
  assert (I.Packed.static_count packed = Some 32769);
  List.iter (fun time ->
    let live = Frame_input.at_time time in
    let expected = E.Private.force_reference value ~live in
    List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
      let output = I.Packed.force packed ~live in
      assert (same output expected);
      match ok output with E.Vec4_array xs ->
        assert (Array.length xs = 4 * 32769);
        assert (xs.(0) = grid.(0) && xs.(1) = grid.(1) && xs.(2) = time && xs.(3) = 1.)
      | _ -> assert false)) [1;8]) [0.;0.25;2.];
  assert (grid = original)

let () =
  let prepare ?ops body = match recorded ?ops body with
    | E.Residual residual -> residual, (E.Private.residual_view residual).term
    | _ -> failwith ("diagnostic fixture did not defer: " ^ body) in
  let refused body code =
    let residual, term = prepare body in
    assert (compile residual term = None);
    match I.Packed.compile_result residual term with
    | Error [d] ->
        assert (d.code = code && d.message <> "");
        assert (Option.fold ~none:false ~some:(fun (span : Flow.Diagnostic.span) ->
          span.finish > span.start) d.span);
        d
    | _ -> failwith ("expected " ^ code ^ ": " ^ body) in
  List.iter (fun (body, code) -> ignore (refused body code))
    ["(let* [s (state [a 0.0] (+ a (frame/dt)))] (map (fn [x] (+ x s)) (array/range 3)))", "E_PACKED_STATE";
     "(for [x (array/range 3) y (array/float (+ x 1))] (+ y t))", "E_PACKED_FORM";
     "(let* [bad (list 1 2)] (map (fn [x] (+ (+ x t) (first bad))) (array/range 3)))", "E_PACKED_CAPTURE";
     "(map (fn [x] (+ t (first (list x 1)))) (array/range 3))", "E_PACKED_FORM";
     "(map sin (array/float 3 t))", "E_PACKED_FUNCTION";
     "(map (fn [x] (+ x (floor t))) (array/range 3))", "E_PACKED_OPERATOR";
     "(fold [a false] [x (array/range 3)] (+ x t))", "E_PACKED_TYPE"];
  let residual, term = prepare ~ops:I.Operators.all
      "(map (fn [p] (noise3 p :seed (frame/index))) (array/vec3 3 [0 1 2]))" in
  assert (compile residual term = None);
  (match I.Packed.compile_result residual term with
   | Error [d] -> assert (d.code = "E_PACKED_CONSTANT") | _ -> assert false);
  let sins n name = List.init n (fun _ -> "(sin ") |> String.concat ""
    |> fun prefix -> prefix ^ name ^ String.make n ')' in
  let kernel n = "(map (fn [x] (+ t " ^ sins n "x" ^ ")) (array/range 3))" in
  let residual, term = prepare (kernel 61) in
  let packed = Option.get (compile residual term) in
  assert (Array.length (I.Packed.Private.view packed).code = Flow.Packed_ops.register_limit);
  ignore (refused (kernel 62) "E_PACKED_LIMIT");
  let constant = "(map (fn [x] (+ (+ x t) (pow 1e200 2.0))) (array/range 3))" in
  (* Ordinary static evaluation also rejects this constant. Compile its
     checked term in the compatible empty scope before materialization. *)
  let bad = match (List.hd (checked constant).graphs).body.node with
    | Flow.Workspace.Let ([_, term], _) -> term | _ -> assert false in
  let residual, _ = prepare "(map (fn [x] (+ x t)) (array/range 3))" in
  assert (compile residual bad = None);
  let d = match I.Packed.compile_result residual bad with
    | Error [d] -> assert (d.code = "E_NONFINITE"); d | _ -> assert false in
  assert (Option.fold ~none:false ~some:(fun (span : Flow.Diagnostic.span) ->
    span.finish - span.start = String.length "(pow 1e200 2.0)") d.span);
  let parity value packed = List.iter (fun time ->
    let live = Frame_input.at_time time in
    let reference = E.Private.force_reference value ~live in
    List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
      assert (same (I.Packed.force packed ~live) reference))) [1;8]) [0.;0.125;1.25;7.] in
  List.iter (fun vector ->
    let value = recorded ("(let* [r {:vector " ^ vector ^ "}] (map (fn [x] (+ x r.vector.x)) (array/range 2051)))") in
    match value with
    | E.Residual residual ->
        let packed = Option.get (compile residual (E.Private.residual_view residual).term) in
        parity value packed
    | _ -> assert false) ["[t 1]"; "[t 1 2]"; "[t 1 2 3]"];
  let value = recorded ("(map (fn [y] (- " ^ sins 40 "y" ^ " t)) (map (fn [x] (+ t "
    ^ sins 40 "x" ^ ")) (array/range 2051)))") in
  (match value with
   | E.Residual residual ->
       let term = (E.Private.residual_view residual).term in
       let child = match term.node with Flow.Workspace.Hof (`Map, [_; child]) -> child | _ -> assert false in
       let child = Option.get (compile ~fusion:false residual child) in
       let packed = Option.get (compile residual term) in
       assert (Array.length (I.Packed.Private.view packed).code
         + Array.length (I.Packed.Private.view child).code > Flow.Packed_ops.register_limit);
       assert (I.Packed.stage_count packed = 1);
       parity value packed
   | _ -> assert false);
  print_endline "Packed diagnostics: refusal reasons/spans, 64-register boundary, captures and unfused fallback passed"
