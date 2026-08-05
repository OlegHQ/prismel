open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints

let integer_env name default =
  match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 20_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 1_024
let self_mode = match Sys.getenv_opt "PRISMEL_BOOLEAN_SELF" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false

let get_string = function Ok value -> value | Error message -> failwith message
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)

let geometry ~right =
  let point_count = pair_count * 3 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. and vertex_points = Array.init point_count Fun.id
  and primitive_offsets = Array.init (pair_count + 1) (fun pair -> pair * 3) in
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
  let topology = Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let self_geometry ~right =
  let triangles_per_pair = if right then 1 else 2 in
  let point_count = pair_count * triangles_per_pair * 3 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. and vertex_points = Array.init point_count Fun.id
  and primitive_offsets = Array.init (pair_count * triangles_per_pair + 1)
      (fun primitive -> primitive * 3) in
  for pair = 0 to pair_count - 1 do
    let offset = float_of_int pair *. 4. in
    if right then begin
      let point = pair * 3 in
      x.(point) <- offset; y.(point) <- 10.; z.(point) <- 0.;
      x.(point + 1) <- offset +. 2.; y.(point + 1) <- 10.; z.(point + 1) <- 0.;
      x.(point + 2) <- offset; y.(point + 2) <- 12.; z.(point + 2) <- 0.
    end else begin
      let point = pair * 6 in
      x.(point) <- offset; y.(point) <- 0.; z.(point) <- 0.;
      x.(point + 1) <- offset +. 2.; y.(point + 1) <- 0.; z.(point + 1) <- 0.;
      x.(point + 2) <- offset; y.(point + 2) <- 2.; z.(point + 2) <- 0.;
      x.(point + 3) <- offset +. 0.5; y.(point + 3) <- -0.5; z.(point + 3) <- -1.;
      x.(point + 4) <- offset +. 0.5; y.(point + 4) <- 1.5; z.(point + 4) <- 1.;
      x.(point + 5) <- offset +. 0.5; y.(point + 5) <- 1.5; z.(point + 5) <- -1.
    end
  done;
  let topology = Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let mix hash value = ((hash * 65_599) lxor value) land max_int

let plan_hash plan =
  let hash = ref 17 in
  for point = 0 to Constraints.point_count plan - 1 do
    let x, y, z = Constraints.approximate_point plan point in
    hash := mix !hash (Int64.to_int (Int64.bits_of_float x));
    hash := mix !hash (Int64.to_int (Int64.bits_of_float y));
    hash := mix !hash (Int64.to_int (Int64.bits_of_float z))
  done;
  for constraint_index = 0 to Constraints.constraint_count plan - 1 do
    hash := mix !hash (Constraints.constraint_first plan constraint_index);
    hash := mix !hash (Constraints.constraint_second plan constraint_index);
    hash := mix !hash (match Constraints.constraint_first_side plan constraint_index with
      | Constraints.Left -> 0 | Constraints.Right -> 1);
    hash := mix !hash (Constraints.constraint_first_triangle plan constraint_index);
    hash := mix !hash (match Constraints.constraint_second_side plan constraint_index with
      | Constraints.Left -> 0 | Constraints.Right -> 1);
    hash := mix !hash (Constraints.constraint_second_triangle plan constraint_index)
  done;
  !hash

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let () =
  let left = if self_mode then self_geometry ~right:false else geometry ~right:false
  and right = if self_mode then self_geometry ~right:true else geometry ~right:true in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and points = ref 0 and constraints = ref 0 and hash = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let plan = Constraints.build
          ~resolve_left_self_intersections:self_mode ~grain ~left ~right () |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated_before;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      points := Constraints.point_count plan;
      constraints := Constraints.constraint_count plan;
      hash := plan_hash plan
    done);
  Printf.printf
    "mode,pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,constraints,hash\n";
  Printf.printf "%s,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    (if self_mode then "self" else "cross") pair_count domains grain repeats
    (median times) (median allocations)
    (median promoted) (median major) !points !constraints !hash
