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
let () =
  let grid = ok (Plane_generators.grid ~counts:Plane_generators.Grid_point_counts
    ~connectivity:Plane_generators.Grid_points ~columns:1000 ~rows:1000 ~size:100. ()) in
  assert (Geometry.point_count grid = 1_000_000);
  print_endline "name,points,domains,median_s,bytes_all_domains,hash";
  let one = run 1 grid in
  let eight = run 8 grid in
  assert (one = eight);
  flow_map 1024;
  flow_map 65_536;
  flow_map 1_000_000;
  let native = run ~mode:Deform.Normal_3d ~seed:0 1 grid in
  assert (native = run ~mode:Deform.Normal_3d ~seed:0 8 grid);
  assert (native = flow_noise grid)
