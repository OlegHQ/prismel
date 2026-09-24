open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Coplanar = Boolean_kernel.Coplanar
module Refinement = Boolean_kernel.Refinement
module Complex = Boolean_kernel.Complex
module Seam = Boolean_kernel.Seam

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 2_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let resolve_self = match Sys.getenv_opt "PRISMEL_BOOLEAN_SELF" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let get_string = function Ok value -> value | Error message -> failwith message
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)

let between_geometry ~right =
  let points = pair_count * 3 in
  let x = Array.make points 0. and y = Array.make points 0.
  and z = Array.make points 0. and vertices = Array.init points Fun.id in
  for pair = 0 to pair_count - 1 do
    let point = pair * 3 and offset = float_of_int pair *. 4. in
    if right then begin
      x.(point) <- offset +. 0.5; y.(point) <- -0.5; z.(point) <- -1.;
      x.(point + 1) <- offset +. 0.5; y.(point + 1) <- 1.5; z.(point + 1) <- 1.;
      x.(point + 2) <- offset +. 0.5; y.(point + 2) <- 1.5; z.(point + 2) <- -1.
    end else begin
      x.(point) <- offset;
      x.(point + 1) <- offset +. 2.;
      x.(point + 2) <- offset; y.(point + 2) <- 2.
    end
  done;
  let topology = Topology.polygons_owned ~point_count:points ~vertex_points:vertices
      ~primitive_offsets:(Array.init (pair_count + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let self_geometry () =
  let points = pair_count * 6 in
  let x = Array.make points 0. and y = Array.make points 0.
  and z = Array.make points 0. and vertices = Array.init points Fun.id in
  for pair = 0 to pair_count - 1 do
    let point = pair * 6 and offset = float_of_int pair *. 4. in
    x.(point) <- offset;
    x.(point + 1) <- offset +. 2.;
    x.(point + 2) <- offset; y.(point + 2) <- 2.;
    x.(point + 3) <- offset +. 0.5; y.(point + 3) <- -0.5; z.(point + 3) <- -1.;
    x.(point + 4) <- offset +. 0.5; y.(point + 4) <- 1.5; z.(point + 4) <- 1.;
    x.(point + 5) <- offset +. 0.5; y.(point + 5) <- 1.5; z.(point + 5) <- -1.
  done;
  let topology = Topology.polygons_owned ~point_count:points ~vertex_points:vertices
      ~primitive_offsets:(Array.init ((pair_count * 2) + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let empty_geometry () =
  Geometry.create
    ~positions:(Packed.Float3.Private.of_owned_exn ~x:[||] ~y:[||] ~z:[||])
    ~topology:(Topology.empty ~point_count:0) () |> get_string

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let hash value =
  let geometry = Seam.curves value in
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry)
  and hash = ref 17 in
  let mix value = hash := ((!hash * 65_599) lxor value) land max_int in
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) positions.x;
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) positions.y;
  Array.iter mix topology.vertex_points;
  for curve = 0 to Geometry.primitive_count geometry - 1 do
    mix (match Seam.curve_kind value curve with
      | Seam.Left_self -> 0 | Seam.Between -> 1 | Seam.Right_self -> 2);
    let first, last = Seam.curve_edge_range value curve in
    for slot = first to last - 1 do mix (Seam.curve_edge value slot) done
  done;
  !hash

let () =
  let left, right = if resolve_self then self_geometry (), empty_geometry ()
    else between_geometry ~right:false, between_geometry ~right:true in
  let complex = Parallel.run ~domains (fun () ->
      let constraints = Constraints.build
          ~resolve_left_self_intersections:resolve_self ~grain ~left ~right () |> get in
      let coplanar = Coplanar.build ~grain constraints |> get in
      let refinement = Refinement.build ~coplanar ~grain constraints |> get in
      Complex.build constraints refinement |> get) in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and live = Array.make repeats 0. and result_hash = ref 0
  and curves = ref 0 and points = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let result = Seam.build ~grain complex |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      live.(repeat) <- float_of_int (Gc.stat ()).live_words *. 8.;
      result_hash := hash result;
      curves := Geometry.primitive_count (Seam.curves result);
      points := Geometry.point_count (Seam.curves result)
    done);
  Printf.printf
    "mode,pairs,complex_edges,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,live_bytes,curves,points,hash\n";
  Printf.printf "%s,%d,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    (if resolve_self then "left_self" else "between")
    pair_count (Complex.edge_count complex) domains grain repeats
    (median times) (median allocations)
    (median promoted) (median major) (median live) !curves !points !result_hash
