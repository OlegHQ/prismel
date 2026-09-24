open Prismel
open Pdk

module Solid = Boolean_kernel.Solid
module Extract = Boolean_kernel.Extract
module Materialization = Boolean_kernel.Materialization

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 100
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let collapse = match Sys.getenv_opt "PRISMEL_BOOLEAN_COLLAPSE" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)
let get_string = function Ok value -> value | Error message -> failwith message

let cube_triangles =
  [|0;3;2; 0;2;1; 4;5;6; 4;6;7; 0;1;5; 0;5;4;
    3;7;6; 3;6;2; 0;4;7; 0;7;3; 1;2;6; 1;6;5|]

let cubes ~right =
  let points = pair_count * 8 and triangles = pair_count * 12 in
  let x = Array.make points 0. and y = Array.make points 0.
  and z = Array.make points 0. and vertices = Array.make (triangles * 3) 0 in
  for cube = 0 to pair_count - 1 do
    let point = cube * 8 and translation = float_of_int cube *. 5. in
    let base_x = if right then
        Float.next_after (translation +. 0.6) Float.infinity else translation
    and base_y = if right then 0.60000000000000009 else 0.
    and base_z = if right then 0.60000000000000009 else 0. in
    for local = 0 to 7 do
      x.(point + local) <- base_x +. if local = 1 || local = 2
          || local = 5 || local = 6 then 2. else 0.;
      y.(point + local) <- base_y +. if local = 2 || local = 3
          || local = 6 || local = 7 then 2. else 0.;
      z.(point + local) <- base_z +. if local >= 4 then 2. else 0.
    done;
    for corner = 0 to Array.length cube_triangles - 1 do
      vertices.((cube * Array.length cube_triangles) + corner) <-
        point + cube_triangles.(corner)
    done
  done;
  let topology = Topology.polygons_owned ~point_count:points
      ~vertex_points:vertices
      ~primitive_offsets:(Array.init (triangles + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let hash geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry)
  and value = ref 17 in
  let mix item = value := ((!value * 65_599) lxor item) land max_int in
  Array.iter (fun item -> mix (Int64.to_int (Int64.bits_of_float item))) positions.x;
  Array.iter (fun item -> mix (Int64.to_int (Int64.bits_of_float item))) positions.y;
  Array.iter (fun item -> mix (Int64.to_int (Int64.bits_of_float item))) positions.z;
  Array.iter mix topology.vertex_points;
  !value

let minimum_candidate_length ancestry candidates =
  let geometry = Extract.geometry ancestry in
  let index = Topology_index.create (Geometry.topology geometry)
      |> Topology_index.Private.view
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let minimum = ref infinity in
  Edge_group.iter (fun edge ->
    let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
    minimum := Float.min !minimum
        (Float.hypot (positions.x.(a) -. positions.x.(b))
          (Float.hypot (positions.y.(a) -. positions.y.(b))
             (positions.z.(a) -. positions.z.(b))))) candidates;
  !minimum

let () =
  let left = cubes ~right:false and right = cubes ~right:true in
  let prepared = Parallel.run ~domains (fun () ->
      Solid.prepare ~grain ~left ~right () |> get) in
  let ancestry = Solid.extract_with_ancestry ~expression:Extract.union prepared |> get
  and seam = Solid.seams ~grain prepared |> get in
  let threshold = 100. in
  let initial_candidates = Materialization.tiny_seam_edges ~grain ~threshold
      ancestry seam |> get in
  let cleanup_threshold = if collapse
    then minimum_candidate_length ancestry initial_candidates else 0. in
  let candidate_times = Array.make repeats 0. and candidate_alloc = Array.make repeats 0.
  and plan_times = Array.make repeats 0. and plan_alloc = Array.make repeats 0.
  and batch_times = Array.make repeats 0. and batch_alloc = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and candidate_count = ref 0 and collapsed_count = ref 0
  and output_points = ref 0 and output_facets = ref 0 and output_hash = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () in
      let measure times allocations operation =
        let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
        let value = operation () in
        times.(repeat) <- Unix.gettimeofday () -. started;
        allocations.(repeat) <- Gc.allocated_bytes () -. allocated;
        value in
      let candidates = measure candidate_times candidate_alloc (fun () ->
          Materialization.tiny_seam_edges ~grain ~threshold ancestry seam |> get) in
      ignore (measure plan_times plan_alloc (fun () ->
        Materialization.safe_independent_edges ~grain candidates
          (Extract.geometry ancestry) |> get));
      let cleanup = measure batch_times batch_alloc (fun () ->
          Materialization.collapse_tiny_seam_batch ~grain
            ~threshold:cleanup_threshold
            ~require_closed:true ancestry seam (Extract.geometry ancestry) |> get) in
      let after = Gc.quick_stat ()
      and output = Materialization.cleanup_geometry cleanup in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      candidate_count := Edge_group.cardinality candidates;
      collapsed_count := Materialization.cleanup_collapsed_count cleanup;
      output_points := Geometry.point_count output;
      output_facets := Geometry.primitive_count output;
      output_hash := hash output
    done);
  Printf.printf
    "pairs,domains,grain,repeats,candidate_threshold,cleanup_threshold,candidate_seconds,candidate_allocated,plan_seconds,plan_allocated,verified_batch_seconds,verified_batch_allocated,promoted_bytes,major_bytes,candidates,collapsed,points,facets,hash\n";
  Printf.printf "%d,%d,%d,%d,%.17g,%.17g,%.6f,%.0f,%.6f,%.0f,%.6f,%.0f,%.0f,%.0f,%d,%d,%d,%d,%d\n%!"
    pair_count domains grain repeats threshold cleanup_threshold
    (median candidate_times) (median candidate_alloc)
    (median plan_times) (median plan_alloc)
    (median batch_times) (median batch_alloc)
    (median promoted) (median major) !candidate_count !collapsed_count
    !output_points !output_facets !output_hash
