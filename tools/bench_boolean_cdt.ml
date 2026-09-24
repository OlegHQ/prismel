open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Arrangement = Boolean_kernel.Arrangement
module Triangulation = Boolean_kernel.Triangulation

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let segment_count = integer_env "PRISMEL_BOOLEAN_SEGMENTS" 500
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let exact_scan = match Sys.getenv_opt "PRISMEL_BOOLEAN_POINT_SCAN" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let edge_scan = match Sys.getenv_opt "PRISMEL_BOOLEAN_EDGE_SCAN" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let get_string = function Ok value -> value | Error message -> failwith message
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)

let geometry points triangles =
  let point_count = Array.length points in
  let x = Array.init point_count (fun point -> let x,_,_ = points.(point) in x)
  and y = Array.init point_count (fun point -> let _,y,_ = points.(point) in y)
  and z = Array.init point_count (fun point -> let _,_,z = points.(point) in z) in
  let topology = Topology.polygons_owned ~point_count ~vertex_points:triangles
      ~primitive_offsets:(Array.init ((Array.length triangles / 3) + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let inputs () =
  let scale = float_of_int segment_count in
  let left = geometry
      [|-.scale,-.scale,0.; 2.*.scale,-.scale,0.;
        scale/.2.,2.*.scale,0.|] [|0;1;2|] in
  let points = Array.make (segment_count * 3) (0.,0.,0.)
  and triangles = Array.init (segment_count * 3) Fun.id in
  for segment = 0 to segment_count - 1 do
    let point = segment * 3 and x = float_of_int segment +. 0.25 in
    points.(point) <- x,-1.,-1.;
    points.(point + 1) <- x,1.,-1.;
    points.(point + 2) <- x,0.,1.
  done;
  left, geometry points triangles

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let mix hash value = ((hash * 65_599) lxor value) land max_int

let triangulation_hash triangulation =
  let hash = ref 17 in
  for triangle = 0 to Triangulation.triangle_count triangulation - 1 do
    hash := mix !hash (Triangulation.triangle_point triangulation triangle 0);
    hash := mix !hash (Triangulation.triangle_point triangulation triangle 1);
    hash := mix !hash (Triangulation.triangle_point triangulation triangle 2)
  done;
  for constraint_index = 0 to Triangulation.constraint_count triangulation - 1 do
    hash := mix !hash (Triangulation.constraint_first triangulation constraint_index);
    hash := mix !hash (Triangulation.constraint_second triangulation constraint_index)
  done;
  !hash

let () =
  let left,right = inputs () in
  let constraints,arrangement = Parallel.run ~domains (fun () ->
      let constraints = Constraints.build ~grain:1024 ~left ~right () |> get in
      let arrangement = Arrangement.build constraints
          ~side:Arrangement.Left ~triangle:0 |> get in
      constraints,arrangement) in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and points = ref 0 and triangles = ref 0 and constraints_out = ref 0
  and hash = ref 0 in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes ()
    and started = Unix.gettimeofday () in
    let triangulation = Triangulation.build
        ~point_location:(if exact_scan then Triangulation.Exact_scan
          else Triangulation.Walk)
        ~constraint_recovery:(if edge_scan then Triangulation.Edge_scan
          else Triangulation.Trace)
        constraints arrangement
        ~side:Arrangement.Left ~triangle:0 |> get in
    times.(repeat) <- Unix.gettimeofday () -. started;
    allocations.(repeat) <- Gc.allocated_bytes () -. allocated_before;
    let after = Gc.quick_stat () in
    promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
    major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
    points := Triangulation.point_count triangulation;
    triangles := Triangulation.triangle_count triangulation;
    constraints_out := Triangulation.constraint_count triangulation;
    hash := triangulation_hash triangulation
  done;
  Printf.printf
    "point_location,constraint_recovery,input_segments,domains,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,triangles,constraints,hash\n";
  Printf.printf "%s,%s,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d,%d\n%!"
    (if exact_scan then "exact_scan" else "walk")
    (if edge_scan then "edge_scan" else "trace")
    segment_count domains repeats (median times) (median allocations)
    (median promoted) (median major) !points !triangles !constraints_out !hash
