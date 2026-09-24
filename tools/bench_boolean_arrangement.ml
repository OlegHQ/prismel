open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Arrangement = Boolean_kernel.Arrangement

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let segment_count = integer_env "PRISMEL_BOOLEAN_SEGMENTS" 2_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let oracle = match Sys.getenv_opt "PRISMEL_BOOLEAN_ORACLE" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let stable_bvh = match Sys.getenv_opt "PRISMEL_BOOLEAN_STABLE_BVH" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let fixture = match Sys.getenv_opt "PRISMEL_BOOLEAN_FIXTURE" with
  | None | Some "sparse" -> "sparse"
  | Some "multiway" -> "multiway"
  | Some value -> invalid_arg ("unknown Boolean arrangement fixture: " ^ value)
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

let sparse_inputs () =
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

let multiway_inputs () =
  let scale = max 10. (float_of_int segment_count) in
  let left = geometry
      [|-.scale,-.scale,0.; scale,-.scale,0.; 0.,scale,0.|] [|0;1;2|] in
  let points = Array.make (segment_count * 3) (0.,0.,0.)
  and triangles = Array.init (segment_count * 3) Fun.id in
  for line = 0 to segment_count - 1 do
    let angle = Float.pi *. float_of_int line /. float_of_int segment_count in
    let dx = 0.4 *. scale *. cos angle and dy = 0.4 *. scale *. sin angle
    and point = line * 3 in
    points.(point) <- -.dx,-.dy,-1.;
    points.(point + 1) <- dx,dy,-1.;
    points.(point + 2) <- 0.,0.,1.
  done;
  left, geometry points triangles

let inputs () = if fixture = "multiway" then multiway_inputs () else sparse_inputs ()

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let mix hash value = ((hash * 65_599) lxor value) land max_int

let arrangement_hash arrangement =
  let hash = ref 17 in
  for point = 0 to Arrangement.point_count arrangement - 1 do
    let x,y,z = Arrangement.approximate_point arrangement point in
    hash := mix !hash (Int64.to_int (Int64.bits_of_float x));
    hash := mix !hash (Int64.to_int (Int64.bits_of_float y));
    hash := mix !hash (Int64.to_int (Int64.bits_of_float z))
  done;
  for segment = 0 to Arrangement.segment_count arrangement - 1 do
    hash := mix !hash (Arrangement.segment_first arrangement segment);
    hash := mix !hash (Arrangement.segment_second arrangement segment)
  done;
  !hash

let () =
  let left, right = inputs () in
  let constraints = Parallel.run ~domains (fun () ->
      Constraints.build ~grain:1024 ~left ~right () |> get) in
  if Constraints.constraint_count constraints <> segment_count then
    failwith "arrangement benchmark did not produce the requested constraints";
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and points = ref 0 and segments = ref 0 and hash = ref 0 in
  for repeat = 0 to repeats - 1 do
    Gc.full_major ();
    let before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes ()
    and started = Unix.gettimeofday () in
    let arrangement = Arrangement.build
        ~broad_phase:(if oracle then Arrangement.Exact_oracle
          else if stable_bvh then Arrangement.Stable_bvh else Arrangement.Sweep)
        constraints
        ~side:Arrangement.Left ~triangle:0 |> get in
    times.(repeat) <- Unix.gettimeofday () -. started;
    allocations.(repeat) <- Gc.allocated_bytes () -. allocated_before;
    let after = Gc.quick_stat () in
    promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
    major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
    points := Arrangement.point_count arrangement;
    segments := Arrangement.segment_count arrangement;
    hash := arrangement_hash arrangement
  done;
  Printf.printf
    "fixture,broad_phase,input_segments,domains,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,segments,hash\n";
  Printf.printf "%s,%s,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    fixture (if oracle then "exact_oracle"
      else if stable_bvh then "stable_bvh" else "sweep")
    segment_count domains repeats (median times) (median allocations)
    (median promoted) (median major) !points !segments !hash
