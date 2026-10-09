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
let packed_vec3 view = Flow.Eval.Vec3_array (Array.init (Array.length view.Packed.Float3.Private.x * 3)
  (fun i -> match i mod 3 with 0 -> view.x.(i / 3) | 1 -> view.y.(i / 3) | _ -> view.z.(i / 3)))
let flow_noise_program grid =
  let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let packed = packed_vec3 in
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
  workspace, value, program
let flow_noise grid =
  let flow_ok = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let packed = packed_vec3 in
  let _, value, program = flow_noise_program grid in
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
    let cook () = match Procedural.Node.Private.cook node context [|Procedural.Payload.Geometry grid|] with
      | Ok output -> (Result.get_ok (Procedural.Payload.geometry output.payload))
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
let gpu_drawing count = Printf.sprintf {|(workspace gpu-frame
  (graph picture :context draw
    (let* [xs (array/range %d)
           positions (map (fn [x]
             (let* [n (noise3 [(* x 0.003) (* t 0.25) 0.25])]
               [(+ (mod x 800) (* n 14)) (+ (mod (/ x 800) 600) (* n 14)) 0])) xs)]
      (draw/merge (draw/background "#080a10")
        (draw/circles positions :radius 1.0 :fill "#00ffffff"))))
  (graph editor :context editor (ui/workspace (ui/canvas (ref picture) :focus true))))|} count

let gpu_check () =
  let get = function Ok value -> value | Error error -> failwith (Flow.Diagnostic.to_string error) in
  let grid = ok (Plane_generators.grid ~counts:Plane_generators.Grid_point_counts
    ~connectivity:Plane_generators.Grid_points ~columns:32 ~rows:32 ~size:100. ()) in
  let _, value, _ = flow_noise_program grid in
  let packed = match value with Flow.Eval.Residual residual ->
    Option.get (Flow_ir.Packed.compile residual (Flow.Eval.Private.residual_view residual).term)
    | _ -> failwith "noise benchmark needs a packed residual" in
  ignore (get (Flow_gpu.Emit.kernel packed));
  assert ((get (Flow_ir.Packed.Private.prepare packed ~live:(Frame_input.at_time 1.25))).count = 1024);
  let expected = ok (Deform.noise_displace ~mode:Deform.Normal_3d ~amplitude:0.8
    ~frequency:0.16 ~seed:0 grid) |> Geometry.positions |> Packed.Float3.Private.view |> packed_vec3 in
  List.iter (fun domains -> Rays_math.Parallel.run ~domains (fun () ->
    assert (get (Flow_ir.Packed.force packed ~live:(Frame_input.at_time 1.25)) = expected))) [1;8];
  List.iter (fun count ->
    let doc = match Rays_editor.Workspace.load (gpu_drawing count) with Ok doc -> doc
      | Error ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds)) in
    let checked, evaluation = get (Flow_ir.qualify_workspace ~inputs:doc.inputs
      doc.Editor_document.Workspace_doc.checked) in
    assert (not (Flow.Workspace.Paths.is_empty checked.approx));
    let circles = Array.find_opt (fun (node : Flow.Eval.node) -> node.kind = "draw/circles")
      evaluation.plan.nodes |> Option.get in
    let value = List.assoc "positions" circles.args in
    let packed = match value with Flow.Eval.Residual residual ->
      Option.get (Flow_ir.Packed.compile residual (Flow.Eval.Private.residual_view residual).term)
      | _ -> failwith "drawing benchmark needs a packed residual" in
    ignore (get (Flow_gpu.Emit.kernel packed));
    let _, site, _ = Flow_ir.Packed.site packed in
    assert (Flow.Workspace.Paths.mem site checked.approx);
    assert (Flow_ir.Packed.static_count packed = Some count)) [10_000; 1_000_000];
  print_endline "GPU benchmark fixtures: emitted noise and live display maps, exact counts, approximate paths"

let benchmark_gpu () =
  let module G = Flow_gpu in
  let get = function Ok value -> value | Error error -> failwith (Flow.Diagnostic.to_string error) in
  let array = function Flow.Eval.Vec3_array values | Float_array values -> values
    | _ -> failwith "GPU benchmark expected packed numeric output" in
  let gpu = match Rays_execution.acquire_gpu () with Ok gpu -> gpu | Error error ->
    Format.eprintf "GPU startup rejected: %a@." Rays_execution.pp_error error;
    (* Preserve the backend's typed rejection: the coordinator's public error
       intentionally collapses backend kinds. Probe only after startup fails. *)
    let driver, _ = Ogpu.Impl.create_driver () in
    (match Ogpu.Backend.create_device driver with
     | Error error ->
         let kind = match error.Ogpu.Error.kind with
           | Invalid_argument -> "Invalid_argument" | Invalid_state -> "Invalid_state"
           | Unsupported -> "Unsupported" | No_adapter -> "No_adapter" | Capacity -> "Capacity"
           | Device_lost -> "Device_lost" | Stale_handle -> "Stale_handle" | Cross_device -> "Cross_device" in
         Printf.eprintf "%s: %s\n%!" kind (Ogpu.Error.to_string error)
     | Ok device -> ignore (Ogpu.Backend.destroy_device device));
    exit 2 in
  Fun.protect ~finally:(fun () -> Rays_execution.release_gpu gpu) (fun () ->
    if not (Ogpu.Caps.has (Ogpu.Backend.capabilities (Rays_execution.gpu_device gpu)) Compute_pipeline) then
      print_endline "SKIP: backend lacks Compute_pipeline"
    else begin
      let grid columns = ok (Plane_generators.grid ~counts:Plane_generators.Grid_point_counts
        ~connectivity:Plane_generators.Grid_points ~columns ~rows:columns ~size:100. ()) in
      let million = grid 1000 in
      print_endline "name,points,domains,median_s,bytes_all_domains,hash";
      let hash = run ~mode:Deform.Normal_3d ~seed:0 1 million in
      assert (hash = run ~mode:Deform.Normal_3d ~seed:0 8 million);
      assert (hash = flow_noise million);
      flow_attributes million;
      print_endline "name,count,compile_s,prepare_s,upload_dispatch_sync_s,gpu_s,readback_s,total_s,p95_s,bytes_per_frame,buffer_creations,max_abs_error";
      List.iter (fun columns ->
        let geometry = if columns=1000 then million else grid columns in
        let _, value, _ = flow_noise_program geometry in
        let packed = match value with Flow.Eval.Residual residual ->
          Option.get (Flow_ir.Packed.compile residual (Flow.Eval.Private.residual_view residual).term)
          | _ -> failwith "noise benchmark needs a packed residual" in
        let msl = get (G.Emit.kernel packed) in
        let compile_s = Array.init 10 (fun _ ->
          let cache = G.Pipelines.create ~clock:Unix.gettimeofday (Rays_execution.gpu_device gpu) in
          Fun.protect ~finally:(fun () -> G.Pipelines.close cache)
            (fun () -> (get (G.Pipelines.get cache msl)).seconds)) |> median in
        let cache = G.Pipelines.create ~clock:Unix.gettimeofday (Rays_execution.gpu_device gpu) in
        Fun.protect ~finally:(fun () -> G.Pipelines.close cache) (fun () ->
          ignore (get (G.Pipelines.get cache msl));
          let runner = G.Run.create gpu cache msl in
          Fun.protect ~finally:(fun () -> G.Run.close runner) (fun () ->
            let live = Frame_input.at_time 1.25 in
            let expected = array (get (Flow_ir.Packed.force packed ~live)) in
            let prepare () = get (Flow_ir.Packed.Private.prepare packed ~live) in
            ignore (get (G.Run.dispatch runner (prepare ())));
            let creations = G.Run.Private.buffer_creations runner in
            List.iter (fun readback ->
              let prepares=Array.make 7 0. and dispatches=Array.make 7 0.
              and gpu_seconds=Array.make 7 nan and reads=Array.make 7 0.
              and totals=Array.make 7 0. and allocations=Array.make 7 0. in
              let maximum=ref 0. in
              for sample=0 to 6 do
                let bytes=allocated_bytes () and started=Unix.gettimeofday () in
                let inputs=prepare () in
                let prepared=Unix.gettimeofday () in
                prepares.(sample)<-prepared-.started;
                let output=get (G.Run.dispatch runner inputs) in
                let dispatched=Unix.gettimeofday () in
                dispatches.(sample)<-dispatched-.prepared;
                gpu_seconds.(sample)<-Option.value (G.Run.gpu_seconds output) ~default:nan;
                let actual=if readback then Some (array (get (G.Run.readback output))) else None in
                let finished=Unix.gettimeofday () in
                reads.(sample)<-finished-.dispatched;
                totals.(sample)<-finished-.started;
                allocations.(sample)<-allocated_bytes ()-.bytes;
                assert (G.Run.Private.buffer_creations runner=creations);
                Option.iter (fun actual ->
                  assert (Array.length actual=Array.length expected);
                  Array.iteri (fun i value -> maximum:=max !maximum (abs_float(value-.expected.(i)))) actual) actual
              done;
              let sorted=Array.copy totals in Array.sort Float.compare sorted;
              Printf.printf "%s,%d,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%.0f,%d,%.9g\n%!"
                (if readback then "flow_noise_gpu_readback" else "flow_noise_gpu_no_array_readback")
                (Geometry.point_count geometry) compile_s (median prepares) (median dispatches)
                (median gpu_seconds) (if readback then median reads else 0.) (median totals)
                sorted.(6) (median allocations) creations (if readback then !maximum else nan)) [true;false])))
        [32;256;1000];
      print_endline "name,count,domains,median_s,p95_s,bytes_per_frame,device_gpu_s,draws_per_frame,uploaded_bytes_per_frame";
      List.iter (fun count ->
        let workspace = match Rays_editor.Workspace.load (gpu_drawing count) with Ok doc -> doc
          | Error ds -> failwith (String.concat "\n" (List.map Flow.Diagnostic.to_string ds)) in
        List.iter (fun gpu_selected ->
          let module Editor=Rays_editor.Editor3 in
          let editor=ref (Result.get_ok (Editor.create ~workspace ~await:true ~domains:1
            ~prepare:(fun _ _ -> Ok ()) ~scene3:(fun _ () -> Rays.Scene3.empty) ())) in
          Fun.protect ~finally:(fun () -> Editor.close !editor) (fun () ->
            if gpu_selected then Editor.Private.gpu_qualification !editor;
            let canvas=Rays.Canvas.create_exn ~width:800 ~height:600 in
            Fun.protect ~finally:(fun () -> Rays.Canvas.destroy canvas) (fun () ->
              let frame count : Rays.Frame.t = {width=800;height=600;size=800,600;
                drawable_width=800;drawable_height=600;drawable_size=800,600;pixel_scale=1.,1.;
                time=float count/.60.;dt=1./.60.;fps=60.;count;mouse=(-100.),(-100.);
                mouse_delta=0.,0.;mouse_buttons=[];keys=[];events=[]} in
              let step index =
                let frame=frame index in editor:=Editor.update !editor frame;
                let scene=Editor.scene !editor frame in
                let instances=Array.fold_left (fun total -> function
                  | Scene_command.Render_ir.Shapes batch when (Scene_command.Shape_batch.gpu batch<>None)=gpu_selected ->
                      total+Scene_command.Shape_batch.count batch
                  | _ -> total) 0 (Rays.Scene.Private.commands scene) in
                assert (instances=count);
                Rays.Canvas.render canvas scene in
              for index=1 to 10 do step index done;
              let before=Rays.Canvas.Private.native_stats canvas in
              let times=Array.make 200 0. in
              Gc.full_major ();
              let bytes=allocated_bytes () in
              Array.iteri (fun index _ -> let started=Unix.gettimeofday () in
                step (index+11);times.(index)<-Unix.gettimeofday ()-.started) times;
              let allocations=(allocated_bytes ()-.bytes)/.200. in
              let after=Rays.Canvas.Private.native_stats canvas in
              let gpu_seconds=if after.gpu_timing_supported then
                  (after.gpu_duration_seconds-.before.gpu_duration_seconds)/.200. else nan in
              let sorted=Array.copy times in Array.sort Float.compare sorted;
              Printf.printf "%s,%d,1,%.9f,%.9f,%.0f,%.9f,%.3f,%.0f\n%!"
                (if gpu_selected then "editor_noise_circles_gpu" else "editor_noise_circles_cpu")
                count (median times) sorted.(190) allocations gpu_seconds
                (Int64.to_float (Int64.sub after.logical_draws before.logical_draws)/.200.)
                (Int64.to_float (Int64.sub after.uploaded_bytes before.uploaded_bytes)/.200.)))) [false;true])
        [10_000;1_000_000]
    end)

let benchmark_gpu_uploads () =
  let get = function Ok x -> x | Error d -> failwith (Flow.Diagnostic.to_string d) in
  let source = "(workspace uploads (graph g :context value [(uv : (array vec2) (map (fn [x] [x x]) (array/range 0)))] (let* [mapped (map (fn [p] [p.x p.y t 1]) uv)] 0.0)))" in
  let forms = get (Flow.Syntax.parse source) in
  let workspace = match Flow.Workspace.check ~ops:Flow_ir.Operators.all {Flow.Check.version=1;kinds=[]} forms with
    | Some w, [] -> w | _, ds -> failwith (String.concat "; " (List.map Flow.Diagnostic.to_string ds)) in
  let gpu = match Rays_execution.acquire_gpu () with Ok gpu -> gpu
    | Error e -> failwith (Format.asprintf "%a" Rays_execution.pp_error e) in
  Fun.protect ~finally:(fun () -> Rays_execution.release_gpu gpu) (fun () ->
    print_endline "size,count,domains,trial,frames,dispatch_s_per_frame,bytes_per_frame,buffer_creations,input_uploads,input_uploaded_bytes";
    List.iter (fun size ->
      let uv = Array.init (size*size*2) (fun i ->
        (float (if i mod 2=0 then i/2 mod size else i/2/size) +. 0.5) /. float size) in
      let evaluated = get (Flow.Eval.static ~record:true ~inputs:["g",["uv",Flow.Eval.Vec2_array uv]] workspace) in
      let residual = match List.assoc ["g";"mapped"] evaluated.records |> List.hd |> snd with
        | Flow.Eval.Residual r -> r | _ -> failwith "expected packed map" in
      let packed = get (Flow_ir.Packed.compile_result residual (Flow.Eval.Private.residual_view residual).term
        |> Result.map_error (function d::_ -> d | [] -> assert false)) in
      let msl = get (Flow_gpu.Emit.kernel packed) in
      let cache = Flow_gpu.Pipelines.create ~clock:Unix.gettimeofday (Rays_execution.gpu_device gpu) in
      Fun.protect ~finally:(fun () -> Flow_gpu.Pipelines.close cache) (fun () ->
        let runner = Flow_gpu.Run.create gpu cache msl in
        Fun.protect ~finally:(fun () -> Flow_gpu.Run.close runner) (fun () ->
          let inputs = get (Flow_ir.Packed.Private.prepare packed ~live:(Frame_input.at_time 0.)) in
          let code = (Flow_ir.Packed.Private.view packed).code in
          assert (inputs.count=size*size && inputs.arrays.(0)==uv);
          let step index =
            Array.iteri (fun i instruction -> match instruction with
              | Flow_ir.Packed.Frame "t" -> inputs.frame.(i)<-float index/.60.
              | _ -> ()) code;
            ignore (get (Flow_gpu.Run.dispatch runner inputs)) in
          for index=1 to 10 do step index done;
          let creations = Flow_gpu.Run.Private.buffer_creations runner in
          for trial=1 to 7 do
            Gc.full_major ();
            let uploads = Flow_gpu.Run.Private.input_uploads runner
            and uploaded_bytes = Flow_gpu.Run.Private.input_uploaded_bytes runner in
            let bytes = allocated_bytes () and started = Unix.gettimeofday () in
            for frame=1 to 200 do step (10+(trial-1)*200+frame) done;
            let elapsed = Unix.gettimeofday ()-.started in
            let allocated = allocated_bytes ()-.bytes in
            assert (Flow_gpu.Run.Private.buffer_creations runner=creations);
            Printf.printf "%d,%d,1,%d,200,%.9f,%.0f,%d,%d,%d\n%!" size inputs.count trial
              (elapsed/.200.) (allocated/.200.) creations
              (Flow_gpu.Run.Private.input_uploads runner-uploads)
              (Flow_gpu.Run.Private.input_uploaded_bytes runner-uploaded_bytes)
          done))) [512;1024;2048])

let benchmark_image_map_gpu () =
  let module G=Flow_gpu in
  let module B=Ogpu.Backend in
  let get=function Ok x->x|Error d->failwith(Flow.Diagnostic.to_string d)in
  let gpu=match Rays_execution.acquire_gpu()with Ok gpu->gpu
    |Error e->failwith(Format.asprintf "%a" Rays_execution.pp_error e)in
  Fun.protect ~finally:(fun()->Rays_execution.release_gpu gpu)(fun()->
    print_endline "fixture,width,height,domains,phase,trial,frames,seconds_per_frame,bytes_per_frame,gpu_seconds_per_frame,runner_buffer_creations,sink_buffer_creations,sink_texture_creations,input_uploads,input_uploaded_bytes,status_reads,output_readback_bytes";
    List.iter(fun(name,expression)->
      let forms=Flow.Syntax.parse("(workspace image (graph g :context image "^expression^"))") |> get in
      let workspace=match Flow.Workspace.check {Flow.Check.version=1;kinds=[]} forms with
        |Some w,[]->w|_,ds->failwith(String.concat "; "(List.map Flow.Diagnostic.to_string ds))in
      let evaluated=Flow.Eval.static workspace |> get in
      let fn=match List.assoc "function" evaluated.plan.nodes.(0).args with Flow.Eval.Fn f->f|_->assert false in
      List.iter(fun size->
        Gc.full_major();
        let cold_bytes=allocated_bytes() and cold_started=Unix.gettimeofday()in
        let kernel=Flow_sop.Image_kernel.prepare ~identity:0 ~width:size ~height:size ~fn ~sources:[] [] |> get in
        let ir=Flow_ir.Executor.graph(Flow_sop.Image_kernel.program kernel)in
        let packed=match ir.nodes.(ir.roots.(0)).kind with Flow_ir.Kernel{body=Packed_map p;_}->p|_->assert false in
        let cache=G.Pipelines.create ~clock:Unix.gettimeofday (Rays_execution.gpu_device gpu)in
        Fun.protect ~finally:(fun()->G.Pipelines.close cache)(fun()->
          let runner=G.Run.create gpu cache (G.Emit.kernel packed |> get)in
          let sink=G.Image_sink.create gpu |> get in
          Fun.protect ~finally:(fun()->G.Image_sink.close sink;G.Run.close runner)(fun()->
            let step index=
              let live=Frame_input.at_time(float(index mod 200)/.200.)in
              let inputs=Flow_ir.Packed.Private.prepare packed ~live |> get in
              let output=G.Run.dispatch runner inputs |> get in
              let converted=G.Image_sink.convert sink ~width:size ~height:size output |> get in
              assert(G.Image_sink.texture converted<>None)in
            let queue=Rays_execution.gpu_queue gpu in
            let timing_before=B.gpu_timing queue in
            step 0;
            let cold_seconds=Unix.gettimeofday()-.cold_started in
            let cold_allocated=allocated_bytes()-.cold_bytes in
            let report width height phase trial frames seconds allocated before uploads uploaded reads readback creates=
              let after=B.gpu_timing queue in
              let gpu_seconds=if after.timing_supported then
                (after.gpu_seconds-.before.B.gpu_seconds)/.float frames else nan in
              let runner_creations,sink_buffers,sink_textures=creates in
              Printf.printf "%s,%d,%d,1,%s,%d,%d,%.9f,%.0f,%.9f,%d,%d,%d,%d,%d,%d,%d\n%!"
                name width height phase trial frames (seconds/.float frames) (allocated/.float frames) gpu_seconds
                (G.Run.Private.buffer_creations runner-runner_creations)
                (G.Image_sink.Private.buffer_creations sink-sink_buffers)
                (G.Image_sink.Private.texture_creations sink-sink_textures)
                (G.Run.Private.input_uploads runner-uploads)
                (G.Run.Private.input_uploaded_bytes runner-uploaded)
                (G.Run.Private.status_reads runner-reads)
                (G.Run.Private.readback_bytes runner-readback)in
            report size size "cold" 0 1 cold_seconds cold_allocated timing_before 0 0 0 0 (0,0,0);
            for frame=1 to 10 do step frame done;
            let creates=G.Run.Private.buffer_creations runner,G.Image_sink.Private.buffer_creations sink,
              G.Image_sink.Private.texture_creations sink in
            for trial=1 to 7 do
              Gc.full_major();
              let before=B.gpu_timing queue
              and uploads=G.Run.Private.input_uploads runner
              and uploaded=G.Run.Private.input_uploaded_bytes runner
              and reads=G.Run.Private.status_reads runner
              and readback=G.Run.Private.readback_bytes runner in
              let bytes=allocated_bytes() and started=Unix.gettimeofday()in
              for frame=1 to 200 do step (10+(trial-1)*200+frame)done;
              let elapsed=Unix.gettimeofday()-.started in
              let allocated=allocated_bytes()-.bytes in
              assert(creates=(G.Run.Private.buffer_creations runner,G.Image_sink.Private.buffer_creations sink,
                G.Image_sink.Private.texture_creations sink));
              assert(G.Run.Private.status_reads runner-reads=200 && G.Run.Private.readback_bytes runner=readback);
              report size size "warm" trial 200 elapsed allocated before uploads uploaded reads readback creates
            done;
            Gc.full_major();
            let before=B.gpu_timing queue
            and uploads=G.Run.Private.input_uploads runner
            and uploaded=G.Run.Private.input_uploaded_bytes runner
            and reads=G.Run.Private.status_reads runner
            and readback=G.Run.Private.readback_bytes runner in
            let bytes=allocated_bytes() and started=Unix.gettimeofday()in
            let width=size+1 and height=size in
            let resized=Flow_sop.Image_kernel.prepare ~identity:0 ~width ~height ~fn ~sources:[] [] |> get in
            let ir=Flow_ir.Executor.graph(Flow_sop.Image_kernel.program resized)in
            let p=match ir.nodes.(ir.roots.(0)).kind with Flow_ir.Kernel{body=Packed_map p;_}->p|_->assert false in
            assert((G.Emit.kernel p |> get).source=(G.Emit.kernel packed |> get).source);
            let inputs=Flow_ir.Packed.Private.prepare p ~live:(Frame_input.at_time 0.25) |> get in
            let output=G.Run.dispatch runner inputs |> get in
            let converted=G.Image_sink.convert sink ~width ~height output |> get in
            assert(G.Image_sink.texture converted<>None);
            let elapsed=Unix.gettimeofday()-.started in
            let allocated=allocated_bytes()-.bytes in
            report width height "resize" 0 1 elapsed allocated before uploads uploaded reads readback creates))) [512;1024;2048])
      ["gradient","(image/map (fn [uv] [uv.x uv.y 0.5 1]))";
       "live_capture","(let* [bias (* t 0.25)] (image/map (fn [uv] [(+ uv.x bias) uv.y 0.5 1])))"])

let () =
  if Array.to_list Sys.argv = [Sys.argv.(0); "--image-map-gpu"] then (benchmark_image_map_gpu (); exit 0);
  if Array.to_list Sys.argv = [Sys.argv.(0); "--gpu-uploads"] then (benchmark_gpu_uploads (); exit 0);
  if Array.to_list Sys.argv = [Sys.argv.(0); "--gpu"] then (benchmark_gpu (); exit 0);
  if Array.to_list Sys.argv = [Sys.argv.(0); "--gpu-check"] then (gpu_check (); exit 0);
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
  else invalid_arg "bench_kernel [--cost|--attributes|--loops|--fusion|--attribute-fusion|--gpu|--gpu-check|--gpu-uploads|--image-map-gpu]"
