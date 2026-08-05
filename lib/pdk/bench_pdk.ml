open Prismel
open Pdk

let integer_env name default =
  match Sys.getenv_opt name with None -> default | Some value -> max 1 (int_of_string value)
let count = integer_env "PRISMEL_PDK_BENCH_POINTS" 1_000_000
let repeats = integer_env "PRISMEL_PDK_BENCH_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_PDK_BENCH_GRAIN" 16_384
let sink = ref 0.

let median values =
  Array.sort Float.compare values; values.(Array.length values / 2)

let measure name operation =
  let times = Array.make repeats 0. and allocated = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0. in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.quick_stat () and bytes = Gc.allocated_bytes ()
    and start = Unix.gettimeofday () in
    let geometry = Parallel.run ~domains operation in
    times.(repeat) <- Unix.gettimeofday () -. start;
    allocated.(repeat) <- Gc.allocated_bytes () -. bytes;
    let after = Gc.quick_stat () in
    promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
    major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
    let x,_,_ = Packed.Float3.get (Geometry.positions geometry) (count - 1) in
    sink := !sink +. x
  done;
  Printf.printf "%s,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f\n%!" name count domains grain repeats
    (median times) (median allocated) (median promoted) (median major)

let () =
  Printf.printf "benchmark,points,domains,grain,repeats,median_seconds,allocated_bytes,promoted_bytes,major_bytes\n%!";
  measure "generate_linear" (fun () ->
    Kernel.generate_points ~grain count (fun output index ->
      let value = float_of_int index in
      Kernel.Writer.set output index value value value));
  measure "generate_linear_ranges" (fun () ->
    Kernel.generate_point_ranges ~grain count (fun ~first ~last ~x ~y ~z ->
      for index = first to last - 1 do
        let value = float_of_int index in
        x.(index) <- value; y.(index) <- value; z.(index) <- value
      done));
  measure "generate_trig" (fun () ->
    Kernel.generate_points ~grain count (fun output index ->
      let value = float_of_int index in
      Kernel.Writer.set output index value (sin value) (cos value)));
  measure "generate_trig_ranges" (fun () ->
    Kernel.generate_point_ranges ~grain count (fun ~first ~last ~x ~y ~z ->
      for index = first to last - 1 do
        let value = float_of_int index in
        x.(index) <- value; y.(index) <- sin value; z.(index) <- cos value
      done));
  let source = Kernel.generate_points ~grain count (fun output index ->
    let value = float_of_int index in Kernel.Writer.set output index value value value) in
  let matrix = Mat4.mul (Mat4.translation (Vec3.create 1. 2. 3.))
      (Mat4.rotation ~axis:(Vec3.create 1. 2. 3.) 0.75) in
  measure "transform" (fun () -> Kernel.transform ~grain matrix source);
  if !sink = neg_infinity then Printf.eprintf "unreachable\n"
