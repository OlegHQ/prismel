open Flow_ir
module E = Flow.Eval

let node ?(ty = Flow.Ty.Float) ?(count = Count.Static 1) ?(rate = Static)
    ?(precision = Exact) ?(args = []) ?(scope = []) ?(invariant = false) name kind =
  let id = [name], scope in
  {id; ty; count; rate; precision; kind; args; scope; invariant; provenance = [id]; tier = Interp}
let edge name node = {name; node}
let constant name v = node name (Source (Constant (E.Float v)))
let op ?count ?rate ?precision ?scope ?invariant name args =
  node ?count ?rate ?precision ?scope ?invariant ~args name
    (Kernel {body = Operation "+"; elementwise = true; requires_exact = false})
let ir nodes roots = {nodes = Array.of_list nodes; roots = Array.of_list roots; groups = [||]}
let ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d)
let approx_error ir = match place ir with
  | Error d -> assert (d.Flow.Diagnostic.code = "E_APPROX_SINK")
  | Ok _ -> failwith "accepted an approximate exact-only sink"

let () =
  let shared = share (ir [constant "a" 1.; constant "b" 1.;
    op "sum" [edge "a" 0; edge "b" 1]] [2]) in
  assert (Array.length shared.nodes = 2);
  assert (shared.nodes.(0).provenance = [(["a"], []); (["b"], [])]);
  assert (shared.nodes.(1).args = [edge "a" 0; edge "b" 0]);
  let bits = share (ir [constant "zero" 0.; constant "negative_zero" (-0.)] [0; 1]) in
  assert (Array.length bits.nodes = 2);
  let phases = share (ir [constant "a" 1.;
    op ~precision:Exact "exact" [edge "a" 0];
    op ~precision:Approx "approx" [edge "a" 0];
    op ~rate:Frame "frame" [edge "a" 0]] [1; 2; 3]) in
  assert (Array.length phases.nodes = 4);
  let opaque = node "catalog" (Opaque ("sop/box", None)) in
  assert (Array.length (share (ir [opaque; {opaque with id = ["other"], []}] [0; 1])).nodes = 2);
  let hoisted = hoist (ir [constant "a" 1.;
    op ~scope:[4] ~invariant:true "uniform" [edge "a" 0];
    op ~scope:[4] "varying" [edge "a" 0];
    op ~scope:[4] ~rate:Frame ~invariant:true "live" [edge "a" 0]] [1; 2; 3]) in
  assert (hoisted.nodes.(1).scope = []);
  assert (hoisted.nodes.(1).id = (["uniform"], [4]));
  assert (hoisted.nodes.(2).scope = [4] && hoisted.nodes.(3).scope = [4]);
  let empty = prune (ir [] []) in
  assert (empty.nodes = [||] && empty.roots = [||]);
  let pruned = prune (ir [constant "unused" 5.; constant "a" 2.;
    op "sum" [edge "a" 1; edge "b" 1]] [2]) in
  assert (Array.length pruned.nodes = 2 && pruned.roots = [|1|]);
  assert (pruned.nodes.(1).args = [edge "a" 0; edge "b" 0]);
  let chain count_a count_b = ir [constant "a" 2.;
    op ~count:count_a "first" [edge "a" 0];
    op ~count:count_b "second" [edge "a" 1]] [2] in
  let group_sizes ir = Array.map Array.length (fuse ir).groups in
  assert (group_sizes (chain (Count.Static 2048) (Count.Static 2048)) = [|1; 2|]);
  assert (group_sizes (chain Count.Unknown Count.Unknown) = [|1; 1; 1|]);
  let origin = ["g"; "P"], [] in
  assert (group_sizes (chain (Count.Data origin) (Count.Data origin)) = [|1; 2|]);
  assert (group_sizes (chain (Count.Data origin) (Count.Data (["g"; "N"], []))) = [|1; 1; 1|]);
  let barrier = fuse (ir [constant "a" 1.; op "a" [edge "x" 0];
    node ~args:[edge "x" 1] "display" (Sink (Display "draw/point"));
    op "b" [edge "x" 1]] [3]) in
  assert (Array.for_all (fun g -> Array.length g = 1) barrier.groups);
  let branching = fuse (ir [constant "a" 1.; op "a" [edge "x" 0];
    op "b" [edge "x" 1]; op "c" [edge "x" 1]] [2; 3]) in
  assert (Array.for_all (fun g -> Array.length g = 1) branching.groups);
  let source = {(constant "gpu" 1.) with precision = Approx} in
  let forwarded = op "forwarded" [edge "x" 0] in
  let display = node ~args:[edge "x" 1] "display" (Sink (Display "draw/point")) in
  let placed = ok (place (ir [source; forwarded; display] [2])) in
  assert (placed.nodes.(1).precision = Approx && placed.nodes.(2).precision = Approx);
  List.iter (fun sink -> approx_error (ir [source; forwarded;
    node ~args:[edge "x" 1] "sink" (Sink sink)] [2])) [Export; Sop_input; State_seed; Cache_key];
  approx_error (ir [source; node ~args:[edge "x" 0] "catalog" (Opaque ("sop/transform", None))] [1]);
  let readback = node ~args:[edge "value" 0] "exact"
    (Kernel {body = Readback; elementwise = true; requires_exact = false}) in
  let exact = ok (place (ir [source; readback;
    node ~args:[edge "x" 1] "export" (Sink Export)] [2])) in
  assert (exact.nodes.(1).precision = Exact && exact.nodes.(2).precision = Exact);
  (try ignore (share (ir [op "cycle" [edge "x" 0]] [0])); failwith "accepted a cycle"
   with Invalid_argument _ -> ())

let check ?(ops = []) ?(catalog = {Flow.Check.version = 1; kinds = []}) text =
  let forms = ok (Flow.Syntax.parse text) in
  match Flow.Workspace.check ~ops catalog forms with
  | Some w, ds when not (List.exists (fun (d : Flow.Diagnostic.t) -> d.severity = Error) ds) -> w
  | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds))
let value ?ops body =
  let ws = check ?ops ("(workspace w (graph g :context value " ^ body ^ "))") in
  let evaluated = ok (E.static ~record:true ws) in
  List.assoc "g" evaluated.results
let rec same_bits a b = match a, b with
  | E.Float a, E.Float b -> Int64.bits_of_float a = Int64.bits_of_float b
  | Vec3 (a, b, c), Vec3 (x, y, z) ->
      List.for_all2 (fun a b -> Int64.bits_of_float a = Int64.bits_of_float b) [a; b; c] [x; y; z]
  | Float_array a, Float_array b | Vec3_array a, Vec3_array b ->
      Marshal.to_string a [] = Marshal.to_string b []
  | List a, List b -> Array.length a = Array.length b && Array.for_all2 same_bits a b
  | Record a, Record b | Struct (_, _, a), Struct (_, _, b) ->
      List.length a = List.length b && List.for_all2 (fun (n, a) (m, b) -> n = m && same_bits a b) a b
  | Fn _, Fn _ -> true
  | a, b -> a = b
let same_result a b = match a, b with
  | Ok a, Ok b -> same_bits a b
  | Error a, Error b -> Flow.Diagnostic.to_string a = Flow.Diagnostic.to_string b
  | _ -> false

let () =
  List.iter (fun body ->
    let v = value body in
    let p = ok (Executor.compile v) in
    List.iter (fun time ->
      let live = Frame_input.at_time time in
      let reference = E.Private.force_reference v ~live in
      List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
        assert (same_result (Executor.force p ~live) reference);
        assert (same_result (Executor.force ~reference:true p ~live) reference))) [1; 8])
      [0.; 0.125; 1.25; 7.])
    ["(+ (* t 2.0) (sin t))";
     "(exact (+ (* t 2.0) (sin t)))";
     "(let* [a t b (* a 3)] (+ b a))";
     "(let* [p [(sin t) (* t 2) (+ t 1)]] (+ p.x p.z))";
     "(let* [r {:x t :nested (list [(sin t) 0 0] [t 0 0])}] r.x)";
     "(if (> t 1) (sqrt t) (sin t))";
     "(sum [x (range 3)] (* t x))";
     "(array/sum (map (fn [x] (+ x t)) (array/range 128)))";
     "(let* [f (fn [x] (* x t))] (sum [x (map f (list 1 2 3))] x))";
     "(sqrt (pow t 1000000))"];
  let scalar = ok (Executor.compile (value "(+ (* t 2) (sin t))")) |> Executor.graph in
  assert (Array.exists (fun n -> n.tier = Closure) scalar.nodes);
  let conditional = ok (Executor.compile (value "(if (> t 0) (/ t 0) (sin t))")) |> Executor.graph in
  assert (Array.exists (function {kind = Kernel {body = Reference _; _}; _} -> true | _ -> false) conditional.nodes);
  let bad_live = {(Frame_input.at_time 0.) with dt = nan} in
  let v = value "(+ t 1)" in
  assert (same_result (Executor.force (ok (Executor.compile v)) ~live:bad_live)
    (E.Private.force_reference v ~live:bad_live));
  let v = value "(let* [a (state [p 0.0] (+ p (frame/dt))) b (* a 2)] (+ a b))" in
  let p = ok (Executor.compile v) in
  let optimized = E.create_state () and reference = E.create_state () in
  List.iter (fun frame ->
    let live = {(Frame_input.at_time (float frame)) with frame; dt = 0.125} in
    assert (same_result (Executor.force ~state:optimized p ~live)
      (E.Private.force_reference ~state:reference v ~live))) [0; 1; 2; 2; 3; 1];
  assert (E.state_stamp optimized = E.state_stamp reference)

let () =
  List.iter (fun body ->
    let v = value body in
    let program = ok (Executor.compile v) in
    assert (Array.exists (fun n -> n.tier = Cpu_kernel) (Executor.graph program).nodes);
    List.iter (fun time ->
      let live = Frame_input.at_time time in
      let reference = E.Private.force_reference v ~live in
      let sequential = Rays_math.Parallel.run ~domains:1 (fun () -> Executor.force program ~live) in
      let parallel = Rays_math.Parallel.run ~domains:8 (fun () -> Executor.force program ~live) in
      assert (same_result sequential reference && same_result parallel reference)) [0.; 0.125; 1.25; 7.])
    ["(array/sum (map (fn [x] (sin (+ (* x 0.25) t))) (array/range 2051)))";
     "(array/sum (map (fn [x] (/ (+ x t) (- x 1))) (array/range 2051)))";
     "(array/sum (map (fn [x] (mod (- t x) 0.7)) (array/range 2051)))";
     "(let* [p (array/nth (map (fn [p n] (+ p (* n (* t 0.8)))) (array/vec3 2051 [1 2 3]) (array/vec3 2053 [0 1 0])) 2050)] p.y)";
     "(array/sum (map (fn [x] (let* [a (* x t) b (sqrt a)] (+ (cos b) b))) (array/range 2051)))";
     "(array/sum (map (fn [x] (min (+ x t) (max x 100.0))) (array/range 2051)))";
     "(array/sum (map (fn [x] (+ (pow t 1000000) (* x 0))) (array/range 2051)))"];
  let v = value "(let* [unused (pow t 1000000) mapped (map (fn [x] (+ x t)) (array/range 2051))] (array/sum mapped))" in
  let program = ok (Executor.compile v) in
  List.iter (fun time ->
    let live = Frame_input.at_time time in
    assert (same_result (Executor.force program ~live) (E.Private.force_reference v ~live))) [0.; 0.125; 7.];
  let v = value "(array/sum (map (fn [x] (+ x t)) (array/float 0)))" in
  assert (Executor.force (ok (Executor.compile v)) ~live:(Frame_input.at_time 1.) = Ok (E.Float 0.));
  let v = value "(array/sum (map (fn [x] (+ x t)) (array/range (frame/index))))" in
  let program = ok (Executor.compile v) in
  List.iter (fun count ->
    let live = {(Frame_input.at_time 1.25) with frame = count} in
    assert (same_result (Executor.force program ~live) (E.Private.force_reference v ~live))) [0; 1023; 1024; 2051]

let read path = In_channel.with_open_text path In_channel.input_all
let () =
  let ops = Flow_ir.Operators.all in
  let mapped ~ops body =
    let ws = check ~ops ("(workspace noise (graph g :context value (let* [mapped " ^ body ^ "] (array/sum mapped))))") in
    let evaluated = ok (E.static ~record:true ws) in
    List.assoc ["g"; "mapped"] evaluated.records |> List.hd |> snd in
  let body = "(map (fn [p] (exact (noise3 (+ p [t 0 0])))) (array/vec3 2051 [0.3 0.7 -0.2]))" in
  let v = mapped ~ops body in
  let program = ok (Executor.compile v) in
  assert (Array.exists (fun n -> n.tier = Cpu_kernel) (Executor.graph program).nodes);
  List.iter (fun time ->
    let live = Frame_input.at_time time in
    let reference = ok (E.Private.force_reference v ~live) in
    List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
      let result = ok (Executor.force program ~live) in
      assert (same_bits result reference);
      match result with
      | E.Float_array xs ->
          let expected = Rays_math.Noise.sample3 (Rays_math.Noise.create 0)
            ~x:(0.3 +. time) ~y:0.7 ~z:(-0.2) in
          assert (Array.length xs = 2051);
          Array.iter (fun x -> assert (Int64.bits_of_float x = Int64.bits_of_float expected)) xs
      | _ -> assert false)) [1; 8]) [0.; 0.125; 1.25; 7.];
  let v = mapped ~ops "(map (fn [p] (noise3 (* p (pow t 1000000)))) (array/vec3 2051 [1 2 3]))" in
  let program = ok (Executor.compile v) in
  let live = Frame_input.at_time 7. in
  assert (same_result (Executor.force program ~live) (E.Private.force_reference v ~live));
  let custom = {Flow_ir.Operators.noise3 with body = (fun ~live:_ ~node:_ _ -> E.Float 0.125)} in
  let v = mapped ~ops:[custom] body in
  let program = ok (Executor.compile v) in
  assert (Array.for_all (fun n -> n.tier <> Cpu_kernel) (Executor.graph program).nodes);
  assert (same_result (Executor.force program ~live) (E.Private.force_reference v ~live));
  match ok (Executor.force program ~live) with
  | E.Float_array xs -> assert (Array.for_all (( = ) 0.125) xs)
  | _ -> assert false

let () =
  (* Compare all million elements with the independent tree walker. *)
  let ws = check "(workspace large (graph g :context value (let* [xs (array/range 1000000) mapped (map (fn [x] (sin (+ (* x 0.25) t))) xs)] (array/sum mapped))))" in
  let evaluated = ok (E.static ~record:true ws) in
  let v = List.assoc ["g"; "mapped"] evaluated.records |> List.hd |> snd in
  let program = ok (Executor.compile v) in
  let live = Frame_input.at_time 1.25 in
  let one = Rays_math.Parallel.run ~domains:1 (fun () -> ok (Executor.force program ~live)) in
  let eight = Rays_math.Parallel.run ~domains:8 (fun () -> ok (Executor.force program ~live)) in
  let reference = ok (E.Private.force_reference v ~live) in
  let reference_eight = Rays_math.Parallel.run ~domains:8 (fun () -> ok (E.Private.force_reference v ~live)) in
  assert (same_bits one reference);
  assert (same_bits eight reference_eight);
  assert (same_bits one eight);
  (match one with
   | E.Float_array xs -> assert (Array.length xs = 1_000_000);
       Array.iteri (fun i x -> assert (Int64.bits_of_float x = Int64.bits_of_float (sin (float i *. 0.25 +. 1.25)))) xs
   | _ -> failwith "CPU map did not return a packed array")
let () =
  let catalog, _ = ok (Flow.Check.catalog_of_manifest (read "../sop_catalog/flow_manifest.sexp")) in
  List.iter (fun name ->
    let ws = check ~catalog (read ("../../specification/workspace/cases/" ^ name ^ ".lisp")) in
    let evaluated = ok (E.static ~record:true ws) in
    let dataflow = of_evaluation ws catalog evaluated |> optimize |> ok in
    assert (Array.length dataflow.roots >= List.length evaluated.results);
    let opaque_ids = Array.to_list dataflow.nodes |> List.filter_map (fun n -> match n.kind with
      | Opaque _ -> Some n.id | _ -> None) in
    assert (List.length opaque_ids = List.length (List.sort_uniq compare opaque_ids));
    let values = List.map snd evaluated.results @ evaluated.states
      @ Array.fold_right (fun (n : E.node) acc -> List.map snd n.args @ acc) evaluated.plan.nodes []
      @ Array.fold_right (fun (i : E.instance) acc -> i.result :: List.map snd i.inputs @ acc) evaluated.plan.instances []
      @ List.concat_map (fun (_, records) -> List.map snd records) evaluated.records in
    let prepared = List.map (fun v -> v, ok (Executor.compile v)) values in
    List.iter (fun time ->
      let live = Frame_input.at_time time in
      List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
        let reference_state = E.create_state () and ir_state = E.create_state () in
        List.iter (fun (v, p) ->
          assert (same_result (Executor.force ~state:ir_state p ~live)
            (E.Private.force_reference ~state:reference_state v ~live))) prepared)) [1; 8])
      [0.; 0.125; 1.25; 7.])
    ["bloom"; "facade"; "garland"; "kit"; "orrery"; "rosette";
     "sunflower"; "tiles"; "tree"; "tunnel"; "variations"; "wave"];
  print_endline "Flow IR passes, precision, scalar/fallback execution and twelve-fixture parity passed"
