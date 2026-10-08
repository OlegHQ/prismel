(* The reference half of the Phase 4 kernel benchmark. Keep output hashes in
   the report so changes of execution tier can be compared exactly. *)
open Rdk
let ok = function Ok x -> x | Error e -> failwith (Error.to_string e)
let median a = let a = Array.copy a in Array.sort Float.compare a; a.(Array.length a / 2)
let allocated_bytes () =
  let stats = Gc.stat () in
  (stats.minor_words +. stats.major_words -. stats.promoted_words) *. float (Sys.word_size / 8)
let fingerprint geometry =
  let p = Packed.Float3.Private.view (Geometry.positions geometry) in
  Digest.to_hex (Digest.string (Marshal.to_string (p.x, p.y, p.z) [Marshal.No_sharing]))
let run ?(mode = Deform.Height_2d) ?(seed = 42) domains grid = Rays_math.Parallel.run ~domains (fun () ->
  let cook () = ok (Deform.noise_displace ~mode ~grain:16_384 ~amplitude:0.8
    ~frequency:0.16 ~seed grid) in
  let reference = fingerprint (cook ()) in
  let times = Array.make 7 0. and allocations = Array.make 7 0. in
  Array.iteri (fun i _ ->
    let bytes = allocated_bytes () in
    let started = Unix.gettimeofday () in
    let output = cook () in
    times.(i) <- Unix.gettimeofday () -. started;
    allocations.(i) <- allocated_bytes () -. bytes;
    assert (fingerprint output = reference)) times;
  Printf.printf "%s,%d,%d,%.9f,%.0f,%s\n%!"
    (match mode with Deform.Height_2d -> "rdk_noise_displace" | Normal_3d -> "rdk_noise_normal3")
    (Geometry.point_count grid) domains (median times) (median allocations) reference;
  reference)
let flow_noise grid =
  let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let packed view = Flow.Eval.Vec3_array (Array.init (Array.length view.Packed.Float3.Private.x * 3)
    (fun i -> match i mod 3 with 0 -> view.x.(i / 3) | 1 -> view.y.(i / 3) | _ -> view.z.(i / 3))) in
  let positions = packed (Packed.Float3.Private.view (Geometry.positions grid)) in
  let normals = Geometry.find_attribute ~owner:Attribute.Point "N" grid |> Option.get
    |> Attribute.get (Attribute.normal ~owner:Attribute.Point) |> Option.get
    |> Packed.Float3.Private.view |> packed in
  let text = "(workspace kernel (graph g :context value [(positions : (array vec3) (array/vec3 0)) (normals : (array vec3) (array/vec3 0))] (let* [mapped (map (fn [p n] (+ p (* n (* (+ 0.8 (* t 0)) (noise3 (* p 0.16)))))) positions normals)] 0.0)))" in
  let forms = flow_ok (Flow.Syntax.parse text) in
  let workspace = match Flow.Workspace.check ~ops:Flow_ir.Operators.all
      {Flow.Check.version = 1; kinds = []} forms with
    | Some ws, [] -> ws | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
  let evaluated = flow_ok (Flow.Eval.static ~record:true ~inputs:["g", ["positions", positions; "normals", normals]] workspace) in
  let value = List.assoc ["g"; "mapped"] evaluated.records |> List.hd |> snd in
  let program = flow_ok (Flow_ir.Executor.compile value) in
  assert (Array.exists (fun (n : Flow_ir.node) -> n.tier = Cpu_kernel) (Flow_ir.Executor.graph program).nodes);
  let expected = ok (Deform.noise_displace ~mode:Deform.Normal_3d ~amplitude:0.8
    ~frequency:0.16 ~seed:0 grid) |> Geometry.positions |> Packed.Float3.Private.view |> packed in
  let expected_bytes = Marshal.to_string expected [Marshal.No_sharing] in
  let fingerprint = function Flow.Eval.Vec3_array xs ->
    let n = Array.length xs / 3 in
    let planes = Array.init n (fun i -> xs.(i * 3)), Array.init n (fun i -> xs.(i * 3 + 1)),
      Array.init n (fun i -> xs.(i * 3 + 2)) in
    Digest.to_hex (Digest.string (Marshal.to_string planes [Marshal.No_sharing]))
    | _ -> failwith "noise map did not produce a packed vec3 array" in
  let live = Frame_input.at_time 1.25 in
  let measure label domains force = Rays_math.Parallel.run ~domains (fun () ->
    let warm = flow_ok (force ()) in
    assert (Marshal.to_string warm [Marshal.No_sharing] = expected_bytes);
    let reference = fingerprint warm in
    let times = Array.make 7 0. and allocations = Array.make 7 0. in
    Array.iteri (fun i _ ->
      let bytes = allocated_bytes () in
      let started = Unix.gettimeofday () in
      let output = flow_ok (force ()) in
      times.(i) <- Unix.gettimeofday () -. started;
      allocations.(i) <- allocated_bytes () -. bytes;
      assert (fingerprint output = reference)) times;
    Printf.printf "%s,%d,%d,%.9f,%.0f,%s\n%!" label (Geometry.point_count grid) domains
      (median times) (median allocations) reference;
    reference) in
  let one = measure "flow_noise_normal3_cpu" 1 (fun () -> Flow_ir.Executor.force program ~live) in
  let eight = measure "flow_noise_normal3_cpu" 8 (fun () -> Flow_ir.Executor.force program ~live) in
  assert (one = eight);
  List.iter (fun domains ->
    assert (one = measure "flow_noise_normal3_interp" domains
      (fun () -> Flow.Eval.Private.force_reference value ~live))) [1; 8];
  one
let flow_map count =
  let text = Printf.sprintf
    "(workspace kernel (graph g :context value (let* [xs (array/range %d) mapped (map (fn [x] (sin (+ (* x 0.25) t))) xs)] (array/sum mapped))))" count in
  let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let forms = flow_ok (Flow.Syntax.parse text) in
  let workspace = match Flow.Workspace.check {Flow.Check.version = 1; kinds = []} forms with
    | Some ws, [] -> ws | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
  let evaluated = flow_ok (Flow.Eval.static ~record:true workspace) in
  let value = List.assoc ["g"; "mapped"] evaluated.records |> List.hd |> snd in
  let program = flow_ok (Flow_ir.Executor.compile value) in
  assert (Array.exists (fun (n : Flow_ir.node) -> n.tier = Cpu_kernel) (Flow_ir.Executor.graph program).nodes);
  let fingerprint = function Flow.Eval.Float_array xs ->
    Digest.to_hex (Digest.string (Marshal.to_string xs [Marshal.No_sharing]))
    | _ -> failwith "map did not produce a packed float array" in
  let live = Frame_input.at_time 1.25 in
  let measure label domains force = Rays_math.Parallel.run ~domains (fun () ->
    let reference = fingerprint (flow_ok (force ())) in
    let times = Array.make 7 0. and allocations = Array.make 7 0. in
    Array.iteri (fun i _ ->
      let bytes = allocated_bytes () in
      let started = Unix.gettimeofday () in
      let output = flow_ok (force ()) in
      times.(i) <- Unix.gettimeofday () -. started;
      allocations.(i) <- allocated_bytes () -. bytes;
      assert (fingerprint output = reference)) times;
    Printf.printf "%s,%d,%d,%.9f,%.0f,%s\n%!" label count domains (median times) (median allocations) reference;
    reference) in
  let one = measure "flow_map_sin_cpu" 1 (fun () -> Flow_ir.Executor.force program ~live) in
  let eight = measure "flow_map_sin_cpu" 8 (fun () -> Flow_ir.Executor.force program ~live) in
  assert (one = eight);
  let reference = measure "flow_map_sin_interp" 1 (fun () -> Flow.Eval.Private.force_reference value ~live) in
  assert (one = reference)
let scalar_cost () =
  let get = function Ok value -> value | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let forms = get (Flow.Syntax.parse "(workspace cost (graph g :context value (+ (* t 0.25) (sin t))))") in
  let workspace = match Flow.Workspace.check {Flow.Check.version=1;kinds=[]} forms with
    | Some workspace, [] -> workspace | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
  let value = List.assoc "g" (get (Flow.Eval.static workspace)).results in
  let residual = match value with Flow.Eval.Residual r -> r | _ -> assert false in
  assert (Flow.Eval.Private.closure_available residual);
  let live = Frame_input.at_time 1.25 and repeats = 10_000 in
  let expected = get (Flow.Eval.Private.force_reference value ~live) in
  List.iter (fun (label, force) ->
    assert (get (force ()) = expected);
    let times = Array.make 7 0. and allocations = Array.make 7 0. in
    for sample = 0 to 6 do
      let bytes = allocated_bytes () and started = Unix.gettimeofday () in
      for _ = 1 to repeats do ignore (get (force ())) done;
      times.(sample) <- (Unix.gettimeofday () -. started) /. float repeats;
      allocations.(sample) <- (allocated_bytes () -. bytes) /. float repeats
    done;
    Printf.printf "%s,1,1,%.9f,%.0f,%s\n%!" label (median times) (median allocations)
      (Digest.to_hex (Digest.string (Marshal.to_string expected [Marshal.No_sharing]))))
    ["flow_scalar_closure", (fun () -> Flow.Eval.residual_eval residual ~live);
     "flow_scalar_interp", (fun () -> Flow.Eval.Private.force_reference value ~live)]

let flow_loops ?(fusion_only = false) count =
  let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  List.iter (fun (label, body) ->
    let source = Printf.sprintf "(workspace kernel (graph g :context value (let* [tested %s] 0.0)))" body in
    let forms = flow_ok (Flow.Syntax.parse source) in
    let workspace = match Flow.Workspace.check {Flow.Check.version = 1; kinds = []} forms with
      | Some w, [] -> w | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
    let evaluation = flow_ok (Flow.Eval.static ~record:true workspace) in
    let value = List.assoc ["g"; "tested"] evaluation.records |> List.hd |> snd in
    let program = flow_ok (Flow_ir.Executor.compile value) in
    assert (Array.exists (fun (n : Flow_ir.node) -> n.tier = Cpu_kernel) (Flow_ir.Executor.graph program).nodes);
    let live = Frame_input.at_time 1.25 in
    let hash value = Digest.to_hex (Digest.string (Marshal.to_string value [Marshal.No_sharing])) in
    let reference = Flow.Eval.Private.force_reference value ~live |> flow_ok |> hash in
    let unfused = if label <> "map_chain" then [] else match value with
      | Flow.Eval.Residual r ->
          let program = Flow_ir.Packed.compile ~fusion:false r
            (Flow.Eval.Private.residual_view r).term |> Option.get in
          ["unfused_cpu", (fun () -> Flow_ir.Packed.force program ~live)]
      | _ -> assert false in
    List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
      List.iter (fun (tier, force) ->
        assert (hash (flow_ok (force ())) = reference);
        let times = Array.make 7 0. and allocations = Array.make 7 0. in
        Array.iteri (fun i _ ->
          let bytes = allocated_bytes () and started = Unix.gettimeofday () in
          let output = flow_ok (force ()) in
          times.(i) <- Unix.gettimeofday () -. started;
          allocations.(i) <- allocated_bytes () -. bytes;
          assert (hash output = reference)) times;
        Printf.printf "flow_%s_%s,%d,%d,%.9f,%.0f,%s\n%!" label tier count domains
          (median times) (median allocations) reference)
        (["cpu", (fun () -> Flow_ir.Executor.force program ~live)] @ unfused @
         ["interp", (fun () -> Flow.Eval.Private.force_reference value ~live)]))) [1;8])
    (let xs = Printf.sprintf "(array/range %d)" count in
     ["for_sin", "(for [x " ^ xs ^ "] (sin (+ x t)))";
      "sum_sin", "(sum [x " ^ xs ^ "] (sin (+ x t)))";
      "fold", "(fold [a 0.0] [x " ^ xs ^ "] (- (* a 0.99) (* (+ x t) 0.0001)))";
      "scan", "(scan [a 0.0] [x " ^ xs ^ "] (- (* a 0.99) (* (+ x t) 0.0001)))";
      "reduce", "(reduce (fn [a x] (- (* a 0.99) (* (+ x t) 0.0001))) 0.0 " ^ xs ^ ")";
      "map_chain", "(map (fn [y] (+ (* y y) (* t 0))) (map (fn [x] (sin (+ x t))) " ^ xs ^ "))"]
      |> List.filter (fun (name, _) -> not fusion_only || name = "map_chain"))
let flow_attributes grid =
  let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let string_ok = function Ok x -> x | Error e -> failwith e in
  let text = "(workspace kernel (graph g :context sop (let* [g (sop/grid) amp 0.8 freq 0.16 result (sop/with_attr g :P (map (fn [p n] (+ p (* n (* amp (noise3 (* p freq)))))) (sop/attr g :P) (sop/attr g :N)))] result)))" in
  let lowered = Flow_sop.Lower.workspace ~factories:Sop_catalog.Editor.factories
    (Flow.Syntax.parse text |> flow_ok) |> flow_ok in
  let graph = List.hd lowered.graphs in
  let cpu = Procedural.Edit_graph.compile_node graph.network.geometry
    ~node_id:(Option.get graph.root) |> string_ok in
  let call = Array.find_opt (fun (n : Flow.Eval.node) -> n.kind = "sop/with_attr") lowered.plan.nodes |> Option.get in
  let values = List.assoc "values" call.args in
  let source = match List.assoc "geometry" call.args with Flow.Eval.Deferred (_, id) -> id | _ -> assert false in
  let reference = Flow_sop.Attribute_kernel.node ~reference:true ~source:"benchmark"
    ~name:"P" ~values ~sources:[source] (Procedural.Node.inputs cpu) in
  let expected = ok (Deform.noise_displace ~mode:Deform.Normal_3d ~amplitude:0.8
    ~frequency:0.16 ~seed:0 grid) |> fingerprint in
  let measure label domains node = Rays_math.Parallel.run ~domains (fun () ->
    let context = Procedural.Context.create ~domains ~grain:16_384 ~time:1.25 () |> string_ok in
    let cook () = match Procedural.Node.Private.cook node context [|grid|] with
      | Ok output -> output.geometry
      | Error d -> failwith (Procedural.Diagnostic.error_to_string d) in
    assert (fingerprint (cook ()) = expected);
    let times = Array.make 7 0. and allocations = Array.make 7 0. in
    Array.iteri (fun i _ ->
      let bytes = allocated_bytes () and started = Unix.gettimeofday () in
      let output = cook () in
      times.(i) <- Unix.gettimeofday () -. started;
      allocations.(i) <- allocated_bytes () -. bytes;
      assert (fingerprint output = expected)) times;
    Printf.printf "%s,%d,%d,%.9f,%.0f,%s\n%!" label (Geometry.point_count grid) domains
      (median times) (median allocations) expected) in
  List.iter (fun domains -> measure "flow_attr_noise_cpu" domains cpu;
    measure "flow_attr_noise_interp" domains reference) [1;8]
let flow_attribute_fusion grid =
  let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let string_ok = function Ok x -> x | Error e -> failwith e in
  let text = "(workspace kernel (graph g :context sop (let* [g (sop/grid) other (sop/transform g) a (map (fn [p] (+ p [t 0 0])) (sop/attr g :P)) b (map (fn [p] (* p (+ t 1))) (sop/attr other :P)) result (sop/with_attr g :P (map (fn [left right] (+ left right)) a b))] result)))" in
  let lowered = Flow_sop.Lower.workspace ~factories:Sop_catalog.Editor.factories
    (Flow.Syntax.parse text |> flow_ok) |> flow_ok in
  let graph = List.hd lowered.graphs in
  let node = Procedural.Edit_graph.compile_node graph.network.geometry
    ~node_id:(Option.get graph.root) |> string_ok in
  let call = Array.find_opt (fun (n : Flow.Eval.node) -> n.kind = "sop/with_attr") lowered.plan.nodes |> Option.get in
  let values = List.assoc "values" call.args in
  let main = match List.assoc "geometry" call.args with Flow.Eval.Deferred (_, id) -> id | _ -> assert false in
  let sources = main :: List.filter ((<>) main) (Flow_sop.Attribute_kernel.sources values) in
  let fused = Flow_sop.Attribute_kernel.prepare ~sources (Procedural.Node.inputs node) values |> flow_ok in
  let materialized = Flow_ir.Executor.compile values |> flow_ok in
  let resolve = Flow_sop.Attribute_kernel.resolve ~geometry:(fun id -> if List.mem id sources then Some grid else None) in
  let live = Frame_input.at_time 1.25 in
  let hash value = Digest.to_hex (Digest.string (Marshal.to_string value [Marshal.No_sharing])) in
  let expected = Flow.Eval.Private.force_reference ~resolve values ~live |> flow_ok |> hash in
  List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
    List.iter (fun (label, force) ->
      let times = Array.make 7 0. and allocations = Array.make 7 0. in
      assert (hash (flow_ok (force ())) = expected);
      Array.iteri (fun i _ ->
        let bytes = allocated_bytes () and started = Unix.gettimeofday () in
        let output = flow_ok (force ()) in
        times.(i) <- Unix.gettimeofday () -. started;
        allocations.(i) <- allocated_bytes () -. bytes;
        assert (hash output = expected)) times;
      Printf.printf "%s,%d,%d,%.9f,%.0f,%s\n%!" label (Geometry.point_count grid) domains
        (median times) (median allocations) expected)
      ["flow_attr_fused_cpu", (fun () -> Flow_ir.Executor.force ~resolve fused ~live);
       "flow_attr_materialized_cpu", (fun () -> Flow_ir.Executor.force ~resolve materialized ~live);
       "flow_attr_fused_interp", (fun () -> Flow.Eval.Private.force_reference ~resolve values ~live)])) [1;8]
let () =
  let grid = ok (Plane_generators.grid ~counts:Plane_generators.Grid_point_counts
    ~connectivity:Plane_generators.Grid_points ~columns:1000 ~rows:1000 ~size:100. ()) in
  assert (Geometry.point_count grid = 1_000_000);
  print_endline "name,points,domains,median_s,bytes_all_domains,hash";
  if Array.length Sys.argv = 1 then begin
  let one = run 1 grid in
  let eight = run 8 grid in
  assert (one = eight);
  flow_map 1024;
  flow_map 65_536;
  flow_map 1_000_000;
  let native = run ~mode:Deform.Normal_3d ~seed:0 1 grid in
  assert (native = run ~mode:Deform.Normal_3d ~seed:0 8 grid);
  assert (native = flow_noise grid);
  flow_attributes grid
  end else if Array.to_list Sys.argv = [Sys.argv.(0); "--attributes"] then begin
    let native = run ~mode:Deform.Normal_3d ~seed:0 1 grid in
    assert (native = run ~mode:Deform.Normal_3d ~seed:0 8 grid);
    flow_attributes grid
  end else if Array.to_list Sys.argv = [Sys.argv.(0); "--cost"] then begin
    scalar_cost (); flow_map 1024; flow_map 65_536; flow_map 1_000_000
  end else if Array.to_list Sys.argv = [Sys.argv.(0); "--loops"] then
    flow_loops 1_000_000
  else if Array.to_list Sys.argv = [Sys.argv.(0); "--fusion"] then
    flow_loops ~fusion_only:true 1_000_000
  else if Array.to_list Sys.argv = [Sys.argv.(0); "--attribute-fusion"] then
    flow_attribute_fusion grid
  else invalid_arg "bench_kernel [--cost|--attributes|--loops|--fusion|--attribute-fusion]"
