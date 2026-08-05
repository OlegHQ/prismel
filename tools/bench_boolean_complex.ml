open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Refinement = Boolean_kernel.Refinement
module Complex = Boolean_kernel.Complex
module Radial = Boolean_kernel.Radial

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

let result_hash complex radial =
  let hash = ref 17 in
  for facet = 0 to Complex.facet_count complex - 1 do
    hash := mix !hash (Complex.facet_vertex complex facet 0);
    hash := mix !hash (Complex.facet_vertex complex facet 1);
    hash := mix !hash (Complex.facet_vertex complex facet 2)
  done;
  for edge = 0 to Radial.edge_count radial - 1 do
    let first, last = Radial.incident_range radial edge in
    for incident = first to last - 1 do
      hash := mix !hash (Radial.incident_facet radial incident);
      hash := mix !hash (Radial.incident_local radial incident)
    done
  done;
  !hash

let () =
  let left = geometry ~right:false and right = geometry ~right:true in
  let constraints, refinement = Parallel.run ~domains (fun () ->
      let constraints = Constraints.build ~grain:1024 ~left ~right () |> get in
      constraints, Refinement.build ~grain constraints |> get) in
  let complex_times = Array.make repeats 0. and radial_times = Array.make repeats 0.
  and complex_alloc = Array.make repeats 0. and radial_alloc = Array.make repeats 0.
  and hash = ref 0 and vertices = ref 0 and facets = ref 0 and edges = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
      let complex = Complex.build constraints refinement |> get in
      complex_times.(repeat) <- Unix.gettimeofday () -. started;
      complex_alloc.(repeat) <- Gc.allocated_bytes () -. allocated;
      let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
      let radial = Radial.build complex |> get in
      radial_times.(repeat) <- Unix.gettimeofday () -. started;
      radial_alloc.(repeat) <- Gc.allocated_bytes () -. allocated;
      hash := result_hash complex radial;
      vertices := Complex.vertex_count complex;
      facets := Complex.facet_count complex;
      edges := Complex.edge_count complex
    done);
  Printf.printf
    "pairs,domains,grain,repeats,complex_seconds,radial_seconds,complex_current_domain_allocated_bytes,radial_current_domain_allocated_bytes,vertices,facets,edges,hash\n";
  Printf.printf "%d,%d,%d,%d,%.6f,%.6f,%.0f,%.0f,%d,%d,%d,%d\n%!"
    pair_count domains grain repeats (median complex_times) (median radial_times)
    (median complex_alloc) (median radial_alloc) !vertices !facets !edges !hash
