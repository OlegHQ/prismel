module E = Flow.Eval
module I = Flow_ir
let ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let recorded body =
  let text = "(workspace w (graph g :context value (let* [tested " ^ body ^ "] 0.0)))" in
  let forms = ok (Flow.Syntax.parse text) in
  let workspace = match Flow.Workspace.check {Flow.Check.version = 1; kinds = []} forms with
    | Some w, [] -> w
    | _, ds -> failwith (text ^ "\n" ^ String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
  let evaluation = ok (E.static ~record:true workspace) in
  List.assoc ["g"; "tested"] evaluation.records |> List.hd |> snd
let same a b = match a, b with
  | Ok a, Ok b -> Marshal.to_string a [Marshal.No_sharing] = Marshal.to_string b [Marshal.No_sharing]
  | Error a, Error b -> Flow.Diagnostic.to_string a = Flow.Diagnostic.to_string b
  | _ -> false
let has_cpu p = Array.exists (fun (n : I.node) -> n.tier = Cpu_kernel) (I.Executor.graph p).nodes
let stages p = Array.fold_left (fun count (n : I.node) -> match n.kind with
  | Kernel {body = Packed_map p; _} -> max count (I.Packed.stage_count p) | _ -> count)
  0 (I.Executor.graph p).nodes
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
    I.Packed.compile residual (E.Private.residual_view residual).term |> Option.get
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
          | E.Residual r -> (match I.Packed.compile r (E.Private.residual_view r).term with
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
      I.Packed.compile ~fusion:false r (E.Private.residual_view r).term |> Option.get
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
