open Pdk
open Prismel

module Solid = Boolean_kernel.Solid
module Extract = Boolean_kernel.Extract
module Payload = Boolean_kernel.Payload

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let include_edge_groups = match Sys.getenv_opt "PRISMEL_BOOLEAN_EDGE_GROUPS" with
  | Some ("0" | "false" | "no") -> false
  | None | Some _ -> true
let get_string = function Ok value -> value | Error message -> failwith message
let get = function Ok value -> value | Error error -> failwith (Error.to_string error)

let geometry ~right =
  let point_count = pair_count * 4 and primitive_count = pair_count * 4 in
  let x = Array.make point_count 0. and y = Array.make point_count 0.
  and z = Array.make point_count 0. and vertices = Array.make (pair_count * 12) 0 in
  for pair = 0 to pair_count - 1 do
    let point = pair * 4
    and offset = (float_of_int pair *. 6.) +. if right then 3. else 0. in
    x.(point) <- offset; x.(point + 1) <- offset +. 1.;
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
  let topology = Topology.polygons_owned ~point_count ~vertex_points:vertices
      ~primitive_offsets:(Array.init (primitive_count + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  let side = if right then 1_000_000 else 0 in
  let scalar = Array.init primitive_count (fun primitive ->
      float_of_int (side + primitive))
  and vx = Array.init primitive_count (fun primitive ->
      float_of_int (side + primitive) *. 0.5)
  and vy = Array.init primitive_count (fun primitive ->
      float_of_int (side + primitive) *. 0.25)
  and vz = Array.init primitive_count (fun primitive ->
      float_of_int (side + primitive) *. 0.125)
  and offsets = Array.init (primitive_count + 1) (fun primitive -> primitive * 2)
  and values = Array.init (primitive_count * 2) (fun slot -> side + slot) in
  let attribute name storage = Attribute.create_owned ~name
      ~owner:Attribute.Primitive storage |> get_string in
  let attributes = [
    attribute "weight" (Attribute.Float scalar);
    attribute "vector" (Attribute.Float3
      (Packed.Float3.Private.of_owned_exn ~x:vx ~y:vy ~z:vz));
    attribute "rows" (Attribute.Int_array
      (Packed.Int_array.Private.create_validated_owned ~offsets ~values));
  ] in
  let point_offsets = Array.init (point_count + 1) (fun point -> point * 2)
  and point_values = Array.init (point_count * 2)
      (fun slot -> float_of_int side +. float_of_int slot *. 0.01)
  and vertex_offsets = Array.init (Array.length vertices + 1) (fun vertex -> vertex * 2)
  and vertex_values = Array.init (Array.length vertices * 2) (fun slot -> side + slot)
  and nx = Array.init (Array.length vertices) (fun vertex -> 1. +. float_of_int (vertex mod 3))
  and ny = Array.init (Array.length vertices) (fun vertex -> 2. +. float_of_int (vertex mod 5))
  and nz = Array.init (Array.length vertices) (fun vertex -> 3. +. float_of_int (vertex mod 7)) in
  let corner_attributes = [
    Attribute.create_owned ~name:"point_weight" ~owner:Attribute.Point
      (Attribute.Float (Array.init point_count
        (fun point -> float_of_int (side + point)))) |> get_string;
    Attribute.create_owned ~name:"point_rows" ~owner:Attribute.Point
      (Attribute.Float_array (Packed.Float_array.Private.create_validated_owned
        ~offsets:point_offsets ~values:point_values)) |> get_string;
    Attribute.create_owned ~name:"N" ~owner:Attribute.Vertex
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x:nx ~y:ny ~z:nz))
      |> get_string;
    Attribute.create_owned ~name:"vertex_rows" ~owner:Attribute.Vertex
      (Attribute.Int_array (Packed.Int_array.Private.create_validated_owned
        ~offsets:vertex_offsets ~values:vertex_values)) |> get_string;
  ] in
  let groups = [
    Group.init ~owner:Group.Primitive ~name:"alternating" primitive_count
      (fun primitive -> (primitive land 1 = 0) <> right);
    Group.init ~owner:Group.Point ~name:"point_alternating" point_count
      (fun point -> point land 1 = 0);
    Group.init ~owner:Group.Vertex ~name:"vertex_alternating" (Array.length vertices)
      (fun vertex -> vertex land 1 = 1);
  ] in
  let topology_index = Topology_index.create topology in
  let edge_group = Edge_group.init ~grain ~topology ~index:topology_index
      ~name:"edge_alternating" (fun edge -> (edge land 1 = 0) <> right) in
  let edge_groups = if include_edge_groups then [edge_group] else [] in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology ~attributes:(attributes @ corner_attributes) ~groups
    ~edge_groups () |> get_string

let median values =
  let values = Array.copy values in Array.sort Float.compare values;
  values.(Array.length values / 2)

let hash geometry =
  let scalar = match Geometry.find_attribute ~owner:Attribute.Primitive
      "weight" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> values | _ -> assert false)
    | None -> assert false
  and vector = match Geometry.find_attribute ~owner:Attribute.Primitive
      "vector" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float3 value -> Packed.Float3.Private.view value
         | _ -> assert false)
    | None -> assert false
  and rows = match Geometry.find_attribute ~owner:Attribute.Primitive "rows" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Int_array value -> Packed.Int_array.Private.view value
         | _ -> assert false)
    | None -> assert false
  and group = Option.get
      (Geometry.find_group ~owner:Group.Primitive "alternating" geometry) in
  let point_weight = match Geometry.find_attribute ~owner:Attribute.Point
      "point_weight" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> values | _ -> assert false)
    | None -> assert false
  and normal = match Geometry.find_attribute ~owner:Attribute.Vertex "N" geometry with
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float3 value -> Packed.Float3.Private.view value | _ -> assert false)
    | None -> assert false
  and point_group = Option.get
      (Geometry.find_group ~owner:Group.Point "point_alternating" geometry)
  and vertex_group = Option.get
      (Geometry.find_group ~owner:Group.Vertex "vertex_alternating" geometry)
  and edge_group = Geometry.find_edge_group "edge_alternating" geometry in
  let state = ref 17 in
  let mix value = state := ((!state * 65_599) lxor value) land max_int in
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) scalar;
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) vector.x;
  Array.iter mix rows.values;
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) point_weight;
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) normal.x;
  for primitive = 0 to Geometry.primitive_count geometry - 1 do
    mix (if Group.mem primitive group then 1 else 0)
  done;
  for point = 0 to Geometry.point_count geometry - 1 do
    mix (if Group.mem point point_group then 3 else 5)
  done;
  for vertex = 0 to Geometry.vertex_count geometry - 1 do
    mix (if Group.mem vertex vertex_group then 7 else 11)
  done;
  Option.iter (fun edge_group ->
    for edge = 0 to Edge_group.length edge_group - 1 do
      mix (if Edge_group.mem edge edge_group then 13 else 17)
    done) edge_group;
  !state

let () =
  let left = geometry ~right:false and right = geometry ~right:true in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and primitive_times = Array.make repeats 0. and corner_times = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and result_hash = ref 0 and output_primitives = ref 0
  and solid_seconds = ref 0. and ancestry_seconds = ref 0.
  and ancestry_allocated = ref 0. and ancestry_promoted = ref 0.
  and ancestry_major = ref 0. in
  Parallel.run ~domains (fun () ->
    let phase = Unix.gettimeofday () in
    let solid = Solid.prepare ~grain ~left ~right () |> get in
    solid_seconds := Unix.gettimeofday () -. phase;
    let phase = Unix.gettimeofday () in
    let ancestry_before = Gc.quick_stat ()
    and ancestry_allocated_before = Gc.allocated_bytes () in
    let ancestry = Solid.extract_with_ancestry ~expression:Extract.union solid |> get in
    ancestry_seconds := Unix.gettimeofday () -. phase;
    ancestry_allocated := Gc.allocated_bytes () -. ancestry_allocated_before;
    let ancestry_after = Gc.quick_stat () in
    ancestry_promoted :=
      (ancestry_after.promoted_words -. ancestry_before.promoted_words) *. 8.;
    ancestry_major :=
      (ancestry_after.major_words -. ancestry_before.major_words) *. 8.;
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let phase = Unix.gettimeofday () in
      let primitive = Payload.copy_primitives ~grain ancestry |> get in
      primitive_times.(repeat) <- Unix.gettimeofday () -. phase;
      let phase = Unix.gettimeofday () in
      let output = Payload.copy_points_and_vertices ~grain
          ~point_conflict:Payload.Reject ~point_tolerance:1e-12
          ancestry primitive |> get in
      corner_times.(repeat) <- Unix.gettimeofday () -. phase;
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      result_hash := hash output;
      output_primitives := Geometry.primitive_count output
    done);
  Printf.printf
    "pairs,output_primitives,domains,grain,repeats,solid_seconds,ancestry_seconds,ancestry_current_domain_allocated_bytes,ancestry_promoted_bytes,ancestry_major_bytes,median_seconds,primitive_seconds,corner_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,hash\n";
  Printf.printf "%d,%d,%d,%d,%d,%.6f,%.6f,%.0f,%.0f,%.0f,%.6f,%.6f,%.6f,%.0f,%.0f,%.0f,%d\n%!"
    pair_count !output_primitives domains grain repeats
    !solid_seconds !ancestry_seconds !ancestry_allocated !ancestry_promoted
    !ancestry_major (median times)
    (median primitive_times) (median corner_times)
    (median allocations) (median promoted) (median major) !result_hash
