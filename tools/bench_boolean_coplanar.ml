open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Coplanar = Boolean_kernel.Coplanar

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 64
let get_string = function Ok value -> value | Error message -> failwith message
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)

let geometry ~right =
  let count = pair_count * 3 in
  let x = Array.make count 0. and y = Array.make count 0. and z = Array.make count 0. in
  for pair = 0 to pair_count - 1 do
    let point = pair * 3 and offset = float_of_int pair *. 8. in
    if right then begin
      x.(point) <- offset; y.(point) <- 3.;
      x.(point + 1) <- offset +. 4.; y.(point + 1) <- 3.;
      x.(point + 2) <- offset +. 2.; y.(point + 2) <- -1.
    end else begin
      x.(point) <- offset; y.(point) <- 0.;
      x.(point + 1) <- offset +. 4.; y.(point + 1) <- 0.;
      x.(point + 2) <- offset +. 2.; y.(point + 2) <- 4.
    end
  done;
  let topology = Topology.polygons_owned ~point_count:count
      ~vertex_points:(Array.init count Fun.id)
      ~primitive_offsets:(Array.init (pair_count + 1) (fun pair -> pair * 3))
      |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let median values =
  let values = Array.copy values in Array.sort Float.compare values;
  values.(Array.length values / 2)

let mix hash value = ((hash * 65_599) lxor value) land max_int

let overlap_hash value =
  let hash = ref 17 in
  for pair = 0 to Coplanar.pair_count value - 1 do
    hash := mix !hash (Coplanar.point_count value pair);
    hash := mix !hash (Coplanar.boundary_count value pair);
    for point = 0 to Coplanar.point_count value pair - 1 do
      let x, y, z = Coplanar.approximate_point value pair point in
      hash := mix !hash (Int64.to_int (Int64.bits_of_float x));
      hash := mix !hash (Int64.to_int (Int64.bits_of_float y));
      hash := mix !hash (Int64.to_int (Int64.bits_of_float z))
    done
  done;
  !hash

let () =
  let left = geometry ~right:false and right = geometry ~right:true in
  let constraints = Parallel.run ~domains (fun () ->
      Constraints.build ~grain:1024 ~left ~right () |> get) in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and hash = ref 0 and points = ref 0 and boundaries = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let value = Coplanar.build ~grain constraints |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated_before;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      hash := overlap_hash value;
      points := 0; boundaries := 0;
      for pair = 0 to Coplanar.pair_count value - 1 do
        points := !points + Coplanar.point_count value pair;
        boundaries := !boundaries + Coplanar.boundary_count value pair
      done
    done);
  Printf.printf
    "pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,boundaries,hash\n";
  Printf.printf "%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    pair_count domains grain repeats (median times) (median allocations)
    (median promoted) (median major) !points !boundaries !hash
