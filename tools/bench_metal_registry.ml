(* Binding migration benchmark: public validation, native encoding and OCaml
   allocation costs. One domain, one device and a fixed one-thread kernel. *)
open Metal

let get = function Ok value -> value | Error error -> failwith (Format.asprintf "%a" pp_error error)

let () =
  let device = get (Device.system_default ()) in
  let queue = get (Command_queue.create device) in
  let buffer = get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ()) in
  let library = get (Library.compile_source ~device
      "#include <metal_stdlib>\nusing namespace metal; kernel void registry_bench(device uint *out [[buffer(0)]]) { out[0] = 7; }") in
  let function_ = get (Function.find ~library "registry_bench") in
  let pipeline = get (Compute_pipeline.create function_) in
  let bench name count operation =
    let samples = List.init 7 (fun _ ->
        let command = get (Command_buffer.create queue ()) in
        let encoder = get (Compute_encoder.create command) in
        get (Compute_encoder.set_pipeline encoder pipeline);
        get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L buffer);
        Gc.full_major ();
        let allocated = Gc.allocated_bytes () and start = Unix.gettimeofday () in
        for _ = 1 to count do get (operation encoder) done;
        let seconds = Unix.gettimeofday () -. start in
        let bytes = Gc.allocated_bytes () -. allocated in
        get (Compute_encoder.end_encoding encoder);
        get (Command_buffer.commit command);
        get (Command_buffer.wait_until_completed command);
        get (Command_buffer.destroy command);
        seconds, bytes) in
    let median values = List.nth (List.sort Float.compare values) 3 in
    Printf.printf "%s count=%d domains=1 median_ms=%.3f bytes_per_call=%.2f\n%!"
      name count (1000. *. median (List.map fst samples))
      (median (List.map snd samples) /. float count)
  in
  bench "set_buffer" 20000 (fun encoder -> Compute_encoder.set_buffer encoder ~index:0 ~offset:0L buffer);
  bench "dispatch_threads" 5000 (fun encoder -> Compute_encoder.dispatch_threads encoder ~threads:(1,1,1) ~threadgroup:(1,1,1));
  assert (Bytes.get_int32_le (get (Buffer.read_bytes buffer ~offset:0L ~length:4)) 0 = 7l);
  get (Compute_pipeline.destroy pipeline);
  get (Function.destroy function_);
  get (Library.destroy library);
  get (Buffer.destroy buffer);
  get (Command_queue.destroy queue);
  get (Device.destroy device)
