let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)
let get_string = function Ok value -> value | Error message -> failwith message
let get = function Ok value -> value | Error error -> failwith (Pdk.Error.to_string error)
let median values =
  let values = Array.copy values in
  Array.sort Float.compare values;
  values.(Array.length values / 2)
let mix hash value = ((hash * 65_599) lxor value) land max_int

let triangle_geometry points triangles =
  let open Pdk in
  let point_count = Array.length points in
  let x = Array.init point_count (fun point -> let x,_,_ = points.(point) in x)
  and y = Array.init point_count (fun point -> let _,y,_ = points.(point) in y)
  and z = Array.init point_count (fun point -> let _,_,z = points.(point) in z) in
  let topology = Topology.polygons_owned ~point_count ~vertex_points:triangles
      ~primitive_offsets:(Array.init ((Array.length triangles / 3) + 1)
        (fun primitive -> primitive * 3)) |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string

let transverse_geometry pair_count ~right =
  let open Pdk in
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

let cube_triangles =
  [|0;3;2; 0;2;1; 4;5;6; 4;6;7; 0;1;5; 0;5;4;
    3;7;6; 3;6;2; 0;4;7; 0;7;3; 1;2;6; 1;6;5|]

let cubes_geometry pair_count ~right =
  let open Pdk in
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

let hash_xyz geometry =
  let open Pdk in
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry)
  and value = ref 17 in
  let mix item = value := ((!value * 65_599) lxor item) land max_int in
  Array.iter (fun item -> mix (Int64.to_int (Int64.bits_of_float item))) positions.x;
  Array.iter (fun item -> mix (Int64.to_int (Int64.bits_of_float item))) positions.y;
  Array.iter (fun item -> mix (Int64.to_int (Int64.bits_of_float item))) positions.z;
  Array.iter mix topology.vertex_points;
  !value

let run_pipeline () =
  let module Bench = struct
open Prismel
open Pdk

module Constraints = Pdk_boolean.Boolean_constraints
module Coplanar = Pdk_boolean.Boolean_coplanar
module Arrangement = Pdk_boolean.Boolean_face_arrangement
module Triangulation = Pdk_boolean.Boolean_face_cdt
module Refinement = Pdk_boolean.Boolean_refinement
module Complex = Pdk_boolean.Boolean_complex
module Radial = Pdk_boolean.Boolean_radial
module Weiler = Pdk_boolean.Boolean_weiler
module Cells = Pdk_boolean.Boolean_cells
module Extract = Pdk_boolean.Boolean_extract
module Solid = Pdk_boolean.Boolean_solid
module Payload = Pdk_boolean.Boolean_payload
module Materialization = Pdk_boolean.Boolean_materialization


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let resolve_self = match Sys.getenv_opt "PRISMEL_BOOLEAN_SELF" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let boolean_env name default = match Sys.getenv_opt name with
  | Some ("1" | "true" | "yes") -> true
  | Some ("0" | "false" | "no") -> false
  | None | Some _ -> default
let resolve_left = boolean_env "PRISMEL_BOOLEAN_LEFT_SELF" resolve_self
let resolve_right = boolean_env "PRISMEL_BOOLEAN_RIGHT_SELF" resolve_self
let left_surface = boolean_env "PRISMEL_BOOLEAN_LEFT_SURFACE" false
let right_surface = boolean_env "PRISMEL_BOOLEAN_RIGHT_SURFACE" false
let refinement_detail = boolean_env "PRISMEL_BOOLEAN_REFINEMENT_DETAIL" false
let product_detail = boolean_env "PRISMEL_BOOLEAN_PRODUCT_DETAIL" false
let candidate_detail = boolean_env "PRISMEL_BOOLEAN_CANDIDATE_DETAIL" false

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

let words line =
  let length = String.length line and values = ref [] and start = ref (-1) in
  let finish stop = if !start >= 0 then begin
      values := String.sub line !start (stop - !start) :: !values;
      start := -1
    end in
  for index = 0 to length - 1 do
    match line.[index] with
    | ' ' | '\t' | '\r' -> finish index
    | _ -> if !start < 0 then start := index
  done;
  finish length;
  List.rev !values

let load_obj path =
  let channel = open_in_bin path in
  let points = ref [] and faces = ref [] and line_number = ref 0 in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      try while true do
        let line = input_line channel in
        incr line_number;
        match words line with
        | "v" :: sx :: sy :: sz :: _ ->
            points := (float_of_string sx, float_of_string sy,
              float_of_string sz) :: !points
        | "f" :: corners when List.length corners >= 3 ->
            let point_count = List.length !points in
            let point token =
              let slash = Option.value ~default:(String.length token)
                  (String.index_opt token '/') in
              let raw = int_of_string (String.sub token 0 slash) in
              let point = if raw > 0 then raw - 1 else point_count + raw in
              if point < 0 || point >= point_count then
                failwith (Printf.sprintf "%s:%d: OBJ index out of bounds"
                  path !line_number);
              point in
            faces := Array.of_list (List.map point corners) :: !faces
        | _ -> ()
      done with End_of_file -> ());
  let points = Array.of_list (List.rev !points)
  and faces = Array.of_list (List.rev !faces) in
  let point_count = Array.length points
  and vertex_count = Array.fold_left
      (fun count face -> count + Array.length face) 0 faces in
  let x = Array.init point_count (fun point -> let x, _, _ = points.(point) in x)
  and y = Array.init point_count (fun point -> let _, y, _ = points.(point) in y)
  and z = Array.init point_count (fun point -> let _, _, z = points.(point) in z)
  and vertices = Array.make vertex_count 0
  and offsets = Array.make (Array.length faces + 1) 0
  and cursor = ref 0 in
  Array.iteri (fun primitive face ->
      offsets.(primitive) <- !cursor;
      Array.iter (fun point -> vertices.(!cursor) <- point; incr cursor) face)
    faces;
  offsets.(Array.length faces) <- vertex_count;
  let topology = Topology.polygons_owned ~point_count ~vertex_points:vertices
      ~primitive_offsets:offsets |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string


let hash geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry)
  and hash = ref 17 in
  let mix value = hash := ((!hash * 65_599) lxor value) land max_int in
  Array.iter (fun value -> mix (Int64.to_int (Int64.bits_of_float value))) positions.x;
  Array.iter mix topology.vertex_points;
  !hash

let run () =
  let left, right = match Sys.getenv_opt "PRISMEL_BOOLEAN_LEFT_OBJ",
      Sys.getenv_opt "PRISMEL_BOOLEAN_RIGHT_OBJ" with
    | None, None -> geometry ~right:false, geometry ~right:true
    | Some left, Some right -> load_obj left, load_obj right
    | _ -> failwith
        "PRISMEL_BOOLEAN_LEFT_OBJ and PRISMEL_BOOLEAN_RIGHT_OBJ must be paired" in
  if refinement_detail then begin
    Parallel.run ~domains (fun () ->
      let started = Unix.gettimeofday () in
      let constraints = Constraints.build
          ~resolve_left_self_intersections:resolve_left
          ~resolve_right_self_intersections:resolve_right
          ~grain ~left ~right () |> get in
      let constraints_seconds = Unix.gettimeofday () -. started in
      let build_side side count range =
        let output = Array.make count None in
        let range_size = max 8 grain in
        let ranges = (count + range_size - 1) / range_size in
        if ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0
            ~finish:(ranges - 1) (fun work_range ->
          let first_face = work_range * range_size
          and last_face = min count ((work_range + 1) * range_size) in
          for face = first_face to last_face - 1 do
            let first, last = range constraints face in
            if first < last then
              output.(face) <- Some (Arrangement.build constraints ~side
                ~triangle:face |> get)
          done);
        output in
      let started = Unix.gettimeofday () in
      let left_arrangements = build_side Arrangement.Left
          (Constraints.left_triangle_count constraints)
          Constraints.left_constraint_range
      and right_arrangements = build_side Arrangement.Right
          (Constraints.right_triangle_count constraints)
          Constraints.right_constraint_range in
      let arrangement_seconds = Unix.gettimeofday () -. started in
      let triangulations = Atomic.make 0 and output_triangles = Atomic.make 0 in
      let point_tokens = Atomic.make
          (Geometry.point_count left + Geometry.point_count right) in
      let build_side side values =
        let count = Array.length values and range_size = max 8 grain in
        let ranges = (count + range_size - 1) / range_size in
        if ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0
            ~finish:(ranges - 1) (fun work_range ->
          let workspace = Triangulation.create_workspace () in
          let first_face = work_range * range_size
          and last_face = min count ((work_range + 1) * range_size) in
          for face = first_face to last_face - 1 do
            match values.(face) with
            | None -> ()
            | Some arrangement ->
                let triangulation = Triangulation.build ~workspace constraints
                    arrangement ~side ~triangle:face |> get in
                ignore (Atomic.fetch_and_add output_triangles
                  (Triangulation.triangle_count triangulation));
                ignore (Atomic.fetch_and_add point_tokens
                  (max 0 (Triangulation.point_count triangulation - 3)));
                Atomic.incr triangulations
          done)
      in
      let started = Unix.gettimeofday () in
      build_side Arrangement.Left left_arrangements;
      build_side Arrangement.Right right_arrangements;
      let triangulation_seconds = Unix.gettimeofday () -. started in
      Printf.printf
        "constraints_seconds,arrangement_seconds,triangulation_seconds,refined_faces,output_triangles,point_tokens\n%.6f,%.6f,%.6f,%d,%d,%d\n%!"
        constraints_seconds arrangement_seconds triangulation_seconds
        (Atomic.get triangulations) (Atomic.get output_triangles)
        (Atomic.get point_tokens));
    exit 0
  end;
  if product_detail then begin
    Parallel.run ~domains (fun () ->
      let measure operation =
        let started = Unix.gettimeofday () in
        let output = operation () in
        output, Unix.gettimeofday () -. started in
      let treatment surface = if surface then Solid.Surface else Solid.Solid in
      let prepared, prepare_seconds = measure (fun () ->
          Solid.prepare
            ~resolve_left_self_intersections:resolve_left
            ~resolve_right_self_intersections:resolve_right
            ~left_treatment:(treatment left_surface)
            ~right_treatment:(treatment right_surface)
            ~grain ~left ~right () |> get) in
      let ancestry, extract_seconds = measure (fun () ->
          Solid.extract_product_with_ancestry
            ~require_closed:false ~defer_rounded_slivers:true
            ~corner_payload:false
            ~operation:Solid.Difference prepared |> get) in
      let primitive_payload, primitive_payload_seconds = measure (fun () ->
          Payload.copy_primitives ~grain ancestry |> get) in
      let payload, corner_payload_seconds = measure (fun () ->
          Payload.copy_points_and_vertices ~grain
            ~point_conflict:Payload.Promote_to_vertex
            ~point_tolerance:0. ancestry primitive_payload |> get) in
      let seams, seam_seconds = measure (fun () ->
          Solid.seams ~grain ~materialize:false prepared |> get) in
      let _, seam_map_seconds = measure (fun () ->
          Materialization.surface_seam_edges ~grain ancestry seams |> get) in
      Printf.eprintf
        "preverify prepare=%.6f extract=%.6f primitive_payload=%.6f corner_payload=%.6f seam=%.6f seam_map=%.6f points=%d facets=%d\n%!"
        prepare_seconds extract_seconds primitive_payload_seconds
        corner_payload_seconds seam_seconds seam_map_seconds
        (Geometry.point_count payload) (Geometry.primitive_count payload);
      if candidate_detail then begin
        let surface, index_seconds = measure (fun () ->
            Surface_index.create ~grain payload |> get) in
        let (first, _), candidates_seconds = measure (fun () ->
            Surface_index.Private.overlapping_self_triangle_pairs_disjoint_topology
              ~grain ~tolerance:0. surface) in
        let (raw_first, raw_second), raw_candidates_seconds = measure (fun () ->
            Surface_index.Private.overlapping_self_triangle_pairs
              ~grain ~tolerance:0. surface) in
        let disjoint_count, filter_seconds = measure (fun () ->
            let count = ref 0 in
            for pair = 0 to Array.length raw_first - 1 do
              let shared = ref false in
              for first_local = 0 to 2 do
                let point = Surface_index.Private.triangle_point surface
                    raw_first.(pair) first_local in
                for second_local = 0 to 2 do
                  if point = Surface_index.Private.triangle_point surface
                      raw_second.(pair) second_local then shared := true
                done
              done;
              if not !shared then incr count
            done;
            !count) in
        Printf.printf
          "index_seconds,candidates_seconds,raw_candidates_seconds,filter_seconds,triangles,candidates,raw_candidates,filtered_candidates\n%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%d\n%!"
          index_seconds candidates_seconds raw_candidates_seconds filter_seconds
          (Surface_index.triangle_count surface)
          (Array.length first) (Array.length raw_first) disjoint_count;
        exit 0
      end;
      let verified, verify_seconds = measure (fun () ->
          Materialization.verify_unchanged_extraction ~grain
            ~require_closed:false ~allow_opposite_duplicates:true
            ancestry payload |> get) in
      if not verified then failwith
          "unchanged extraction unexpectedly requested rounding repair";
      let full, full_seconds = measure (fun () ->
          Boolean.run ~grain ~operation:Boolean.Difference
            ~left_treatment:(if left_surface then Boolean.Surface else Boolean.Solid)
            ~right_treatment:(if right_surface then Boolean.Surface else Boolean.Solid)
            ~resolve_left_self_intersections:resolve_left
            ~resolve_right_self_intersections:resolve_right
            ~right left |> get) in
      Printf.printf
        "prepare_seconds,extract_seconds,primitive_payload_seconds,corner_payload_seconds,seam_seconds,seam_map_seconds,verify_seconds,full_seconds,points,facets,hash\n%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%d,%d\n%!"
        prepare_seconds extract_seconds primitive_payload_seconds
        corner_payload_seconds seam_seconds seam_map_seconds verify_seconds
        full_seconds (Geometry.point_count full) (Geometry.primitive_count full)
        (hash full));
    exit 0
  end;
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and phase_times = Array.init 8 (fun _ -> Array.make repeats 0.)
  and phase_allocations = Array.init 8 (fun _ -> Array.make repeats 0.)
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and result_hash = ref 0 and points = ref 0 and facets = ref 0
  and candidate_pairs = ref 0 in
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
          Constraints.build ~resolve_left_self_intersections:resolve_left
            ~resolve_right_self_intersections:resolve_right
            ~grain ~left ~right () |> get) in
      candidate_pairs := Constraints.candidate_pair_count constraints;
      let coplanar = measure 1 (fun () -> Coplanar.build ~grain constraints |> get) in
      let refinement = measure 2 (fun () ->
          Refinement.build ~coplanar ~grain constraints |> get) in
      let complex = measure 3 (fun () -> Complex.build constraints refinement |> get) in
      let radial = measure 4 (fun () -> Radial.build complex |> get) in
      let weiler = measure 5 (fun () -> Weiler.build complex radial |> get) in
      let cells = measure 6 (fun () ->
          Cells.build ~track_left:(not left_surface)
            ~track_right:(not right_surface)
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
      facets := Geometry.primitive_count result
    done);
  Printf.printf
    "self_resolution,pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,constraints_seconds,coplanar_seconds,refinement_seconds,complex_seconds,radial_seconds,weiler_seconds,cells_seconds,extract_seconds,constraints_allocated,complex_allocated,cells_allocated,points,facets,hash,candidate_pairs\n";
  Printf.printf "%s,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.0f,%.0f,%.0f,%d,%d,%d,%d\n%!"
    (match resolve_left, resolve_right with
     | false, false -> "off" | true, true -> "both"
     | true, false -> "left" | false, true -> "right")
    pair_count domains grain repeats (median times) (median allocations)
    (median promoted) (median major)
    (median phase_times.(0)) (median phase_times.(1))
    (median phase_times.(2)) (median phase_times.(3))
    (median phase_times.(4)) (median phase_times.(5))
    (median phase_times.(6)) (median phase_times.(7))
    (median phase_allocations.(0)) (median phase_allocations.(3))
    (median phase_allocations.(6)) !points !facets !result_hash
    !candidate_pairs
  end in Bench.run ()

let run_constraints () =
  let module Bench = struct
open Prismel
open Pdk

module Constraints = Pdk_boolean.Boolean_constraints
let approximate_point plan point =
  Pdk_exact.Implicit_point.approximate (Constraints.Private.point plan point)


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 20_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 1_024
let self_mode = match Sys.getenv_opt "PRISMEL_BOOLEAN_SELF" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false


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


let plan_hash plan =
  let hash = ref 17 in
  for point = 0 to Constraints.point_count plan - 1 do
    let x, y, z = approximate_point plan point in
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


let run () =
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

  end in Bench.run ()

let run_coplanar () =
  let module Bench = struct
open Prismel
open Pdk

module Constraints = Pdk_boolean.Boolean_constraints
module Coplanar = Pdk_boolean.Boolean_coplanar
let approximate_point value pair point =
  Pdk_exact.Implicit_point.approximate (Coplanar.Private.point value pair point)


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 64

let geometry ~right =
  let count = pair_count * 3 in
  let x = Array.make count 0. and y = Array.make count 0. and z = Array.make count 0. in
  for pair = 0 to pair_count - 1 do
    let point = pair * 3 and offset = float_of_int pair *. 8. in
    if right then begin
      x.(point) <- offset; y.(point) <- 3.;
      x.(point + 1) <- offset +. 4.; y.(point + 1) <- 3.;
      x.(point + 2) <- offset +. 2.; y.(point + 2) <- -1.
    end else begin
      x.(point) <- offset; y.(point) <- 0.;
      x.(point + 1) <- offset +. 4.; y.(point + 1) <- 0.;
      x.(point + 2) <- offset +. 2.; y.(point + 2) <- 4.
    end
  done;
  let topology = Topology.polygons_owned ~point_count:count
      ~vertex_points:(Array.init count Fun.id)
      ~primitive_offsets:(Array.init (pair_count + 1) (fun pair -> pair * 3))
      |> get_string in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology () |> get_string



let overlap_hash value =
  let hash = ref 17 in
  for pair = 0 to Coplanar.pair_count value - 1 do
    hash := mix !hash (Coplanar.point_count value pair);
    hash := mix !hash (Coplanar.boundary_count value pair);
    for point = 0 to Coplanar.point_count value pair - 1 do
      let x, y, z = approximate_point value pair point in
      hash := mix !hash (Int64.to_int (Int64.bits_of_float x));
      hash := mix !hash (Int64.to_int (Int64.bits_of_float y));
      hash := mix !hash (Int64.to_int (Int64.bits_of_float z))
    done
  done;
  !hash

let run () =
  let left = geometry ~right:false and right = geometry ~right:true in
  let constraints = Parallel.run ~domains (fun () ->
      Constraints.build ~grain:1024 ~left ~right () |> get) in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and hash = ref 0 and points = ref 0 and boundaries = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let value = Coplanar.build ~grain constraints |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated_before;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      hash := overlap_hash value;
      points := 0; boundaries := 0;
      for pair = 0 to Coplanar.pair_count value - 1 do
        points := !points + Coplanar.point_count value pair;
        boundaries := !boundaries + Coplanar.boundary_count value pair
      done
    done);
  Printf.printf
    "pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,boundaries,hash\n";
  Printf.printf "%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    pair_count domains grain repeats (median times) (median allocations)
    (median promoted) (median major) !points !boundaries !hash

  end in Bench.run ()

let run_arrangement () =
  let module Bench = struct
open Prismel

module Constraints = Pdk_boolean.Boolean_constraints
module Arrangement = Pdk_boolean.Boolean_face_arrangement
let approximate_point value point =
  Pdk_exact.Implicit_point.approximate (Arrangement.Private.point value point)


let segment_count = integer_env "PRISMEL_BOOLEAN_SEGMENTS" 2_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let fixture = match Sys.getenv_opt "PRISMEL_BOOLEAN_FIXTURE" with
  | None | Some "sparse" -> "sparse"
  | Some "multiway" -> "multiway"
  | Some value -> invalid_arg ("unknown Boolean arrangement fixture: " ^ value)

let geometry points triangles = triangle_geometry points triangles

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



let arrangement_hash arrangement =
  let hash = ref 17 in
  for point = 0 to Arrangement.point_count arrangement - 1 do
    let x,y,z = approximate_point arrangement point in
    hash := mix !hash (Int64.to_int (Int64.bits_of_float x));
    hash := mix !hash (Int64.to_int (Int64.bits_of_float y));
    hash := mix !hash (Int64.to_int (Int64.bits_of_float z))
  done;
  for segment = 0 to Arrangement.segment_count arrangement - 1 do
    hash := mix !hash (Arrangement.segment_first arrangement segment);
    hash := mix !hash (Arrangement.segment_second arrangement segment)
  done;
  !hash

let run () =
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
    "fixture,input_segments,domains,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,segments,hash\n";
  Printf.printf "%s,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    fixture
    segment_count domains repeats (median times) (median allocations)
    (median promoted) (median major) !points !segments !hash

  end in Bench.run ()

let run_cdt () =
  let module Bench = struct
open Prismel

module Constraints = Pdk_boolean.Boolean_constraints
module Arrangement = Pdk_boolean.Boolean_face_arrangement
module Triangulation = Pdk_boolean.Boolean_face_cdt


let segment_count = integer_env "PRISMEL_BOOLEAN_SEGMENTS" 500
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())

let geometry points triangles = triangle_geometry points triangles

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

let run () =
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
    "input_segments,domains,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,points,triangles,constraints,hash\n";
  Printf.printf "%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d,%d\n%!"
    segment_count domains repeats (median times) (median allocations)
    (median promoted) (median major) !points !triangles !constraints_out !hash

  end in Bench.run ()

let run_refinement () =
  let module Bench = struct
open Prismel

module Constraints = Pdk_boolean.Boolean_constraints
module Triangulation = Pdk_boolean.Boolean_face_cdt
module Refinement = Pdk_boolean.Boolean_refinement


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 64

let geometry ~right = transverse_geometry pair_count ~right



let hash_face hash = function
  | None -> mix hash 0
  | Some face ->
      let hash = ref (mix hash (Triangulation.triangle_count face)) in
      for triangle = 0 to Triangulation.triangle_count face - 1 do
        hash := mix !hash (Triangulation.triangle_point face triangle 0);
        hash := mix !hash (Triangulation.triangle_point face triangle 1);
        hash := mix !hash (Triangulation.triangle_point face triangle 2)
      done;
      !hash

let refinement_hash value =
  let hash = ref 17 in
  for face = 0 to Refinement.left_face_count value - 1 do
    hash := hash_face !hash (Refinement.left_face value face)
  done;
  for face = 0 to Refinement.right_face_count value - 1 do
    hash := hash_face !hash (Refinement.right_face value face)
  done;
  !hash

let run () =
  let left = geometry ~right:false and right = geometry ~right:true in
  let constraints = Parallel.run ~domains (fun () ->
      Constraints.build ~grain:1024 ~left ~right () |> get) in
  let times = Array.make repeats 0. and allocations = Array.make repeats 0.
  and promoted = Array.make repeats 0. and major = Array.make repeats 0.
  and hash = ref 0 and left_count = ref 0 and right_count = ref 0 in
  Parallel.run ~domains (fun () ->
    for repeat = 0 to repeats - 1 do
      Gc.full_major ();
      let before = Gc.quick_stat () and allocated_before = Gc.allocated_bytes ()
      and started = Unix.gettimeofday () in
      let value = Refinement.build ~grain constraints |> get in
      times.(repeat) <- Unix.gettimeofday () -. started;
      allocations.(repeat) <- Gc.allocated_bytes () -. allocated_before;
      let after = Gc.quick_stat () in
      promoted.(repeat) <- (after.promoted_words -. before.promoted_words) *. 8.;
      major.(repeat) <- (after.major_words -. before.major_words) *. 8.;
      hash := refinement_hash value;
      left_count := Refinement.refined_left_count value;
      right_count := Refinement.refined_right_count value
    done);
  Printf.printf
    "pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,left_faces,right_faces,hash\n";
  Printf.printf "%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%d,%d,%d\n%!"
    pair_count domains grain repeats (median times) (median allocations)
    (median promoted) (median major) !left_count !right_count !hash

  end in Bench.run ()

let run_complex () =
  let module Bench = struct
open Prismel

module Constraints = Pdk_boolean.Boolean_constraints
module Refinement = Pdk_boolean.Boolean_refinement
module Complex = Pdk_boolean.Boolean_complex
module Radial = Pdk_boolean.Boolean_radial


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 64

let geometry ~right = transverse_geometry pair_count ~right



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

let run () =
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

  end in Bench.run ()

let run_seam () =
  let module Bench = struct
open Prismel
open Pdk

module Constraints = Pdk_boolean.Boolean_constraints
module Coplanar = Pdk_boolean.Boolean_coplanar
module Refinement = Pdk_boolean.Boolean_refinement
module Complex = Pdk_boolean.Boolean_complex
module Seam = Pdk_boolean.Boolean_seam


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 2_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let resolve_self = match Sys.getenv_opt "PRISMEL_BOOLEAN_SELF" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false

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

let run () =
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

  end in Bench.run ()

let run_materialization () =
  let module Bench = struct
open Prismel
open Pdk

module Solid = Pdk_boolean.Boolean_solid
module Extract = Pdk_boolean.Boolean_extract
module Materialization = Pdk_boolean.Boolean_materialization


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 100
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let collapse = match Sys.getenv_opt "PRISMEL_BOOLEAN_COLLAPSE" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false

let cubes ~right = cubes_geometry pair_count ~right


let hash = hash_xyz

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

let run () =
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

  end in Bench.run ()

let run_payload () =
  let module Bench = struct
open Pdk
open Prismel

module Solid = Pdk_boolean.Boolean_solid
module Extract = Pdk_boolean.Boolean_extract
module Payload = Pdk_boolean.Boolean_payload


let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 10_000
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 3
let domains = integer_env "PRISMEL_BENCH_DOMAINS" (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256
let include_edge_groups = match Sys.getenv_opt "PRISMEL_BOOLEAN_EDGE_GROUPS" with
  | Some ("0" | "false" | "no") -> false
  | None | Some _ -> true
let ordered_groups = Sys.getenv_opt "PRISMEL_BOOLEAN_ORDERED" = Some "1"

let geometry ~right =
  let group ~owner ~name length contains =
    if not ordered_groups then Group.init ~owner ~name length contains else
    let members=Array.of_list(List.rev(List.filter contains(List.init length Fun.id)))in
    Group.ordered ~owner ~name ~length members|>get_string in
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
    group ~owner:Group.Primitive ~name:"alternating" primitive_count
      (fun primitive -> (primitive land 1 = 0) <> right);
    group ~owner:Group.Point ~name:"point_alternating" point_count
      (fun point -> point land 1 = 0);
    group ~owner:Group.Vertex ~name:"vertex_alternating" (Array.length vertices)
      (fun vertex -> vertex land 1 = 1);
  ] in
  let topology_index = Topology_index.create topology in
  let edge_group = Edge_group.init ~grain ~topology ~index:topology_index
      ~name:"edge_alternating" (fun edge -> (edge land 1 = 0) <> right) in
  let edge_groups = if include_edge_groups then [edge_group] else [] in
  Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
    ~topology ~attributes:(attributes @ corner_attributes) ~groups
    ~edge_groups () |> get_string


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

let run () =
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

  end in Bench.run ()

let run_product () =
  let module Bench = struct
open Prismel
open Pdk

let pair_count = integer_env "PRISMEL_BOOLEAN_PAIR_COUNT" 20
let repeats = integer_env "PRISMEL_BOOLEAN_REPEATS" 5
let domains = integer_env "PRISMEL_BENCH_DOMAINS"
    (Parallel.recommended_domains ())
let grain = integer_env "PRISMEL_BOOLEAN_GRAIN" 256

let cubes ~right = cubes_geometry pair_count ~right


let hash = hash_xyz

let run () =
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

  end in Bench.run ()

let () =
  let stage = match Array.to_list Sys.argv with
    | [_] -> "pipeline"
    | [_; stage] -> stage
    | _ -> invalid_arg "usage: bench_boolean_pipeline [stage]" in
  match stage with
  | "pipeline" -> run_pipeline ()
  | "constraints" -> run_constraints ()
  | "coplanar" -> run_coplanar ()
  | "arrangement" -> run_arrangement ()
  | "cdt" -> run_cdt ()
  | "refinement" -> run_refinement ()
  | "complex" -> run_complex ()
  | "seam" -> run_seam ()
  | "materialization" -> run_materialization ()
  | "payload" -> run_payload ()
  | "product" -> run_product ()
  | _ -> invalid_arg ("unknown Boolean benchmark stage: " ^ stage)
