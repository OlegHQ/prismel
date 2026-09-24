open Prismel
open Pdk

let integer_env name default = match Sys.getenv_opt name with
  | None -> default
  | Some value -> max 1 (int_of_string value)

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 20
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS"
    (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
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
  let values = Array.copy values in Array.sort Float.compare values;
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

let () =
  let left = cubes ~right:false and right = cubes ~right:true in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and output_points = ref 0 and output_primitives = ref 0 and output_hash = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let output = Boolean.run ~grain ~operation:Boolean.Difference ~right left |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      output_points := Geometry.point_count output;
      output_primitives := Geometry.primitive_count output;
      output_hash := hash output
    done);
  Printf.printf
    "pairs,domains,grain,repeats,seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,primitives,hash\n";
  Printf.printf "%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    pair_count domains grain repeats (median times) (median allocations)
    (median promoted) (median major) !output_points !output_primitives !output_hash
