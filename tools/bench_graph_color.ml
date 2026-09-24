open Prismel
open Pdk

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let elements = integer_env "PRISMEL_GRAPH_COLOR_ELEMENTS" 1_000_000
let repeats = integer_env "PRISMEL_GRAPH_COLOR_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS"
    (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_GRAPH_COLOR_GRAIN" 16_384

let get = function Ok value -> value | Error error ->
  failwith (Error.to_string error)

let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)

let disconnected_triangles point_count =
  let triangles = max 1 (max 3 point_count / 3) in
  let point_count = triangles * 3 in
  let x = Array.init point_count (fun point -> float_of_int (point / 3))
  and y = Array.init point_count (fun point ->
      match point mod 3 with 0 -> 0. | 1 -> 1. | _ -> 0.)
  and z = Array.make point_count 0. in
  let topology = Topology.create_owned ~point_count
      ~vertex_points:(Array.init point_count Fun.id)
      ~primitive_offsets:(Array.init (triangles + 1)
        (fun primitive -> primitive * 3))
      ~primitive_kinds:(Array.make triangles Topology.Polygon)
      |> Result.get_ok in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> Result.get_ok

let square_grid primitive_target =
  let side = max 1 (int_of_float (sqrt (float_of_int primitive_target))) in
  Ops.grid ~connectivity:Ops.Grid_quads ~columns:side ~rows:side
    ~size:(float_of_int side) () |> get

let color_values owner geometry =
  match Geometry.find_attribute ~owner "color" geometry with
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> values
       | _ -> failwith "Graph Color benchmark output has wrong storage")
  | None -> failwith "Graph Color benchmark output is missing"

let hash values =
  Array.fold_left (fun hash value ->
    ((hash * 65_599) lxor value) land max_int) 17 values

let measure name owner connectivity input =
  let times = Array.make repeats 0. and allocated = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and output_hash = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and bytes_before = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let output = Ops.graph_color ~grain ~connectivity input |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocated.(repeat) <- Gc.allocated_bytes () -. bytes_before;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      let current_hash = hash (color_values owner output) in
      if repeat > 0 && current_hash <> !output_hash then
        failwith (name ^ ": nondeterministic output");
      output_hash := current_hash
    done);
  Printf.printf "%s,%d,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d\n%!"
    name (Geometry.point_count input) (Geometry.primitive_count input)
    domains grain repeats (median times) (median allocated)
    (median promoted) (median major) !output_hash

let () =
  Printf.printf "case,points,primitives,domains,grain,repeats,seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,hash\n";
  measure "disconnected_triangle_points" Attribute.Point
    Ops.Graph_points_by_primitive (disconnected_triangles elements);
  let grid = square_grid elements in
  measure "quad_primitives_by_edge" Attribute.Primitive
    Ops.Graph_primitives_by_edge grid;
  measure "quad_primitives_by_point" Attribute.Primitive
    Ops.Graph_primitives_by_point grid
