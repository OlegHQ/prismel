open Prismel
open Pdk

module Constraints = Boolean_kernel.Constraints
module Coplanar = Boolean_kernel.Coplanar
module Arrangement = Boolean_kernel.Arrangement
module Triangulation = Boolean_kernel.Triangulation
module Refinement = Boolean_kernel.Refinement
module Complex = Boolean_kernel.Complex
module Radial = Boolean_kernel.Radial
module Weiler = Boolean_kernel.Weiler
module Cells = Boolean_kernel.Cells
module Extract = Boolean_kernel.Extract
module Solid = Boolean_kernel.Solid
module Payload = Boolean_kernel.Payload
module Materialization = Boolean_kernel.Materialization

let integer_env name default = match Sys.getenv_opt name with
  | None -> default | Some value -> max 1 (int_of_string value)

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
  and symbolic_seeds = ref 0 and candidate_pairs = ref 0 in
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
          Cells.build ~axis_fast_path:(not force_symbolic_cells)
            ~component_index ~track_left:(not left_surface)
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
      facets := Geometry.primitive_count result;
      symbolic_seeds := Cells.symbolic_seed_count cells
    done);
  Printf.printf
    "self_resolution,cell_seed_mode,component_query,pairs,domains,grain,repeats,median_seconds,current_domain_allocated_bytes,promoted_bytes,major_bytes,constraints_seconds,coplanar_seconds,refinement_seconds,complex_seconds,radial_seconds,weiler_seconds,cells_seconds,extract_seconds,constraints_allocated,complex_allocated,cells_allocated,symbolic_seeds,points,facets,hash,candidate_pairs\n";
  Printf.printf "%s,%s,%s,%d,%d,%d,%d,%.6f,%.0f,%.0f,%.0f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.0f,%.0f,%.0f,%d,%d,%d,%d,%d\n%!"
    (match resolve_left, resolve_right with
     | false, false -> "off" | true, true -> "both"
     | true, false -> "left" | false, true -> "right")
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
    !candidate_pairs
