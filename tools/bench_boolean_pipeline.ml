open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Coplanar = Boolean_kernel.Coplanar
module Refinement = Boolean_kernel.Refinement
module Complex = Boolean_kernel.Complex
module Radial = Boolean_kernel.Radial
module Weiler = Boolean_kernel.Weiler
module Cells = Boolean_kernel.Cells
module Extract = Boolean_kernel.Extract

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let resolve_self = match Sys.getenv_opt "PRISMEL_BOOLEAN_SELF" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let force_symbolic_cells = match Sys.getenv_opt "PRISMEL_BOOLEAN_SYMBOLIC_CELLS" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let component_index = match Sys.getenv_opt "PRISMEL_BOOLEAN_COMPONENT_INDEX" with
  | Some ("0" | "false" | "no") -> false
  | None | Some _ -> true
let get_string = function Ok value -> value | Error message -> failwith message
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)

let geometry ~right =
  let points = pair_count * 4 in
  let x = Array.make points 0. and y = Array.make points 0. and z = Array.make points 0.
  and vertices = Array.make (pair_count * 12) 0 in
  for pair = 0 to pair_count - 1 do
    let point = pair * 4
    and offset = (float_of_int pair *. 6.) +. if right then 3. else 0. in
    x.(point) <- offset;
    x.(point + 1) <- offset +. 1.;
    x.(point + 2) <- offset; y.(point + 2) <- 1.;
    x.(point + 3) <- offset; z.(point + 3) <- 1.;
    let vertex = pair * 12 in
    vertices.(vertex) <- point; vertices.(vertex + 1) <- point + 2;
    vertices.(vertex + 2) <- point + 1;
    vertices.(vertex + 3) <- point; vertices.(vertex + 4) <- point + 1;
    vertices.(vertex + 5) <- point + 3;
    vertices.(vertex + 6) <- point + 1; vertices.(vertex + 7) <- point + 2;
    vertices.(vertex + 8) <- point + 3;
    vertices.(vertex + 9) <- point + 2; vertices.(vertex + 10) <- point;
    vertices.(vertex + 11) <- point + 3
  done;
  let topology = Topology.polygons_owned ~point_count:points ~vertex_points:vertices
      ~primitive_offsets:(Array.init ((pair_count * 4) + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let median values =
  let values = Array.copy values in Array.sort Float.compare values;
  values.(Array.length values / 2)

let hash geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry)
  and hash = ref 17 in
  let mix value = hash := ((!hash * 65_599) lxor value) land max_int in
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) positions.x;
  Array.iter mix topology.vertex_points;
  !hash

let () =
  let left = geometry ~right:false and right = geometry ~right:true in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and phase_times = Array.init 8 (fun _ -> Array.make repeats 0.)
  and phase_allocations = Array.init 8 (fun _ -> Array.make repeats 0.)
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and result_hash = ref 0 and points = ref 0 and facets = ref 0
  and symbolic_seeds = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let measure phase operation =
        let allocated = Gc.allocated_bytes () and started = Unix.gettimeofday () in
        let result = operation () in
        phase_times.(phase).(repeat) <- Unix.gettimeofday () -. started;
        phase_allocations.(phase).(repeat) <- Gc.allocated_bytes () -. allocated;
        result in
      let constraints = measure 0 (fun () ->
          Constraints.build ~resolve_left_self_intersections:resolve_self
            ~resolve_right_self_intersections:resolve_self
            ~grain ~left ~right () |> get) in
      let coplanar = measure 1 (fun () -> Coplanar.build ~grain constraints |> get) in
      let refinement = measure 2 (fun () ->
          Refinement.build ~coplanar ~grain constraints |> get) in
      let complex = measure 3 (fun () -> Complex.build constraints refinement |> get) in
      let radial = measure 4 (fun () -> Radial.build complex |> get) in
      let weiler = measure 5 (fun () -> Weiler.build complex radial |> get) in
      let cells = measure 6 (fun () ->
          Cells.build ~axis_fast_path:(not force_symbolic_cells)
            ~component_index
            complex weiler |> get) in
      let result = measure 7 (fun () ->
          Extract.build ~expression:Extract.union complex weiler cells |> get) in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      result_hash := hash result;
      points := Geometry.point_count result;
      facets := Geometry.primitive_count result;
      symbolic_seeds := Cells.symbolic_seed_count cells
    done);
  Printf.printf
    "self_resolution,cell_seed_mode,component_query,pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,constraints_seconds,coplanar_seconds,refinement_seconds,complex_seconds,radial_seconds,weiler_seconds,cells_seconds,extract_seconds,constraints_allocated,complex_allocated,cells_allocated,symbolic_seeds,points,facets,hash\n";
  Printf.printf "%s,%s,%s,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.0f,%.0f,%.0f,%d,%d,%d,%d\n%!"
    (if resolve_self then "both" else "off")
    (if force_symbolic_cells then "symbolic" else "axis_then_symbolic")
    (if component_index then "indexed" else "exhaustive")
    pair_count domains grain repeats (median times) (median allocations)
    (median promoted) (median major)
    (median phase_times.(0)) (median phase_times.(1))
    (median phase_times.(2)) (median phase_times.(3))
    (median phase_times.(4)) (median phase_times.(5))
    (median phase_times.(6)) (median phase_times.(7))
    (median phase_allocations.(0)) (median phase_allocations.(3))
    (median phase_allocations.(6)) !symbolic_seeds !points !facets !result_hash
