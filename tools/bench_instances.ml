open Prismel

let instance_count =
  match Sys.getenv_opt "PRISMEL_INSTANCE_BENCH_COUNT" with
  | None -> 100_000
  | Some value -> max 1 (int_of_string value)

let retained_bytes baseline =
  let live = (Gc.stat ()).live_words - baseline in
  max 0 live * (Sys.word_size / 8)

let materialized scene =
  Gc.compact ();
  let baseline = (Gc.stat ()).live_words in
  let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
  let drawings = Scene3.Private.drawings scene in
  Gc.full_major ();
  let retained = retained_bytes baseline in
  let checksum = List.fold_left (fun sum drawing ->
      sum +. Mat4.get drawing.Scene3.Private.transform ~row:0 ~column:3)
      0. drawings in
  checksum, Unix.gettimeofday () -. started,
  Gc.allocated_bytes () -. allocated, retained

let streamed scene =
  Gc.compact ();
  let baseline = (Gc.stat ()).live_words in
  let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
  let checksum = ref 0. in
  Scene3.Private.iter_drawings (fun drawing ->
    checksum := !checksum
      +. Mat4.get drawing.Scene3.Private.transform ~row:0 ~column:3) scene;
  Gc.full_major ();
  !checksum, Unix.gettimeofday () -. started,
  Gc.allocated_bytes () -. allocated, retained_bytes baseline

let batched scene =
  Gc.compact ();
  let baseline = (Gc.stat ()).live_words in
  let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
  let checksum = ref 0. in
  Scene3.Private.iter_batches (fun drawing instances ->
    match instances with
    | None -> checksum := !checksum
        +. Mat4.get drawing.Scene3.Private.transform ~row:0 ~column:3
    | Some transforms ->
        Array.iter (fun transform ->
          let transform =
            Mat4.mul drawing.Scene3.Private.transform transform in
          checksum := !checksum +. Mat4.get transform ~row:0 ~column:3)
          transforms) scene;
  Gc.full_major ();
  !checksum, Unix.gettimeofday () -. started,
  Gc.allocated_bytes () -. allocated, retained_bytes baseline

let () =
  let side = max 1 (int_of_float (ceil (sqrt (float_of_int instance_count)))) in
  let transforms = Array.init instance_count (fun index ->
    let x = index mod side and y = index / side in
    Mat4.translation (Vec3.create (float_of_int x) (float_of_int y) 0.)) in
  let mesh = Mesh.box ~width:1. ~height:1. ~depth:1. () in
  let scene = Scene3.create [Scene3.instances_array mesh transforms] in
  let old_checksum, old_seconds, old_allocated, old_retained = materialized scene
  and stream_checksum, stream_seconds, stream_allocated, stream_retained =
    streamed scene
  and batch_checksum, batch_seconds, batch_allocated, batch_retained =
    batched scene in
  if old_checksum <> stream_checksum || old_checksum <> batch_checksum then
    failwith "instance traversal checksum drift";
  Printf.printf
    "mode,instances,seconds,allocated_bytes,retained_bytes,checksum\n";
  Printf.printf "materialized,%d,%.6f,%.0f,%d,%.0f\n"
    instance_count old_seconds old_allocated old_retained old_checksum;
  Printf.printf "streamed,%d,%.6f,%.0f,%d,%.0f\n"
    instance_count stream_seconds stream_allocated stream_retained stream_checksum;
  Printf.printf "batched,%d,%.6f,%.0f,%d,%.0f\n%!"
    instance_count batch_seconds batch_allocated batch_retained batch_checksum
