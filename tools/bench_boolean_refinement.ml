open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Triangulation = Boolean_kernel.Triangulation
module Refinement = Boolean_kernel.Refinement

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
    let point = pair * 3 and offset = float_of_int pair *. 4. in
    if right then begin
      x.(point) <- offset +. 0.5; y.(point) <- -0.5; z.(point) <- -1.;
      x.(point + 1) <- offset +. 0.5; y.(point + 1) <- 1.5; z.(point + 1) <- 1.;
      x.(point + 2) <- offset +. 0.5; y.(point + 2) <- 1.5; z.(point + 2) <- -1.
    end else begin
      x.(point) <- offset; y.(point) <- 0.; z.(point) <- 0.;
      x.(point + 1) <- offset +. 2.; y.(point + 1) <- 0.; z.(point + 1) <- 0.;
      x.(point + 2) <- offset; y.(point + 2) <- 2.; z.(point + 2) <- 0.
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

let hash_face hash = function
  | None -> mix hash 0
  | Some face ->
      let hash = ref (mix hash (Triangulation.triangle_count face)) in
      for triangle = 0 to Triangulation.triangle_count face - 1 do
        hash := mix !hash (Triangulation.triangle_point face triangle 0);
        hash := mix !hash (Triangulation.triangle_point face triangle 1);
        hash := mix !hash (Triangulation.triangle_point face triangle 2)
      done;
      !hash

let refinement_hash value =
  let hash = ref 17 in
  for face = 0 to Refinement.left_face_count value - 1 do
    hash := hash_face !hash (Refinement.left_face value face)
  done;
  for face = 0 to Refinement.right_face_count value - 1 do
    hash := hash_face !hash (Refinement.right_face value face)
  done;
  !hash

let () =
  let left = geometry ~right:false and right = geometry ~right:true in
  let constraints = Parallel.run ~domains (fun () ->
      Constraints.build ~grain:1024 ~left ~right () |> get) in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and hash = ref 0 and left_count = ref 0 and right_count = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let value = Refinement.build ~grain constraints |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated_before;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      hash := refinement_hash value;
      left_count := Refinement.refined_left_count value;
      right_count := Refinement.refined_right_count value
    done);
  Printf.printf
    "pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,left_faces,right_faces,hash\n";
  Printf.printf "%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    pair_count domains grain repeats (median times) (median allocations)
    (median promoted) (median major) !left_count !right_count !hash
