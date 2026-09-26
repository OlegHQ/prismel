open Prismel_math

let get_ok = function Ok value -> value | Error message -> invalid_arg message

let run_legacy ?cancel ?(grain = 16_384) ?(sides = 12) ?scale_attribute
    ?(seam_offset = 0) ?seam_attribute ?v_attribute ?up_attribute
    ?(caps = false) ?cap_group ~radius geometry =
  if grain <= 0 then invalid_arg "Pdk_mesh.Sweep_circle.sweep_circle: grain must be positive";
  if sides < 3 then Error "Pdk_mesh.Sweep_circle.sweep_circle: sides must be at least three"
  else if not (Float.is_finite radius) || radius <= 0. then
    Error "Pdk_mesh.Sweep_circle.sweep_circle: radius must be finite and positive"
  else
    let topology = Geometry.topology geometry
    and source_positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let source_vertices = Geometry.vertex_count geometry
    and source_primitives = Geometry.primitive_count geometry in
    let find_point_attribute label name storage = match name with
      | None -> None, None
      | Some name when String.trim name = "" ->
          None, Some (label ^ " attribute name must not be empty")
      | Some name ->
          (match Geometry.find_attribute ~owner:Attribute.Point name geometry with
           | None -> None, Some (Printf.sprintf
               "point %s attribute %S does not exist" label name)
           | Some attribute ->
               match storage (Attribute.Private.storage attribute) with
               | Some values -> Some values, None
               | None -> None, Some (Printf.sprintf
                   "point %s attribute %S has incompatible storage" label name)) in
    let scale_values, scale_error = find_point_attribute "scale" scale_attribute
        (function Attribute.Float values -> Some values | _ -> None)
    and seam_values, seam_error = find_point_attribute "seam" seam_attribute
        (function Attribute.Int values -> Some values | _ -> None)
    and v_values, v_error = find_point_attribute "V texture" v_attribute
        (function Attribute.Float values -> Some values | _ -> None)
    and up_values, up_error = find_point_attribute "joint up" up_attribute
        (function Attribute.Float3 values ->
          Some (Packed.Float3.Private.view values) | _ -> None) in
    let invalid = ref (List.find_opt Option.is_some
        [scale_error; seam_error; v_error; up_error] |> Option.join)
    and edge_count = ref 0
    and open_count = ref 0 in
    Option.iter (fun name -> if String.trim name = "" then
      invalid := Some "cap group name must not be empty") cap_group;
    if cap_group <> None && not caps then
      invalid := Some "cap_group requires caps=true";
    Option.iter (fun values ->
      let point = ref 0 in
      while !invalid = None && !point < Array.length values do
        let value = values.(!point) in
        if not (Float.is_finite value) || value < 0. then invalid := Some (Printf.sprintf
            "point scale attribute %S contains a non-finite or negative value at point %d"
            (Option.get scale_attribute) !point);
        incr point
      done) scale_values;
    Option.iter (fun values ->
      let point = ref 0 in
      while !invalid = None && !point < Array.length values do
        if not (Float.is_finite values.(!point)) then invalid := Some (Printf.sprintf
            "point V texture attribute %S contains a non-finite value at point %d"
            (Option.get v_attribute) !point);
        incr point
      done) v_values;
    Option.iter (fun (values : Packed.Float3.Private.view) ->
      let point = ref 0 in
      while !invalid = None && !point < Array.length values.x do
        if not (Float.is_finite values.x.(!point) && Float.is_finite values.y.(!point)
            && Float.is_finite values.z.(!point)) then invalid := Some (Printf.sprintf
            "point joint up attribute %S contains a non-finite value at point %d"
            (Option.get up_attribute) !point);
        incr point
      done) up_values;
    let source_primitive_offsets = Array.make (source_primitives + 1) 0
    and open_ranks = Array.make source_primitives (-1) in
    for primitive = 0 to source_primitives - 1 do
      let size = Topology.primitive_size topology primitive in
      match Topology.primitive_kind topology primitive with
      | Topology.Polygon -> if !invalid = None then invalid := Some
          (Printf.sprintf "primitive %d is a polygon" primitive)
      | Topology.Open_polyline ->
          open_ranks.(primitive) <- !open_count;
          incr open_count;
          edge_count := !edge_count + size - 1;
          source_primitive_offsets.(primitive + 1) <- !edge_count
      | Topology.Closed_polyline ->
          edge_count := !edge_count + size;
          source_primitive_offsets.(primitive + 1) <- !edge_count
    done;
    if source_vertices > max_int / sides || !edge_count > max_int / sides
        || (caps && !open_count > max_int / 2) then
      invalid := Some "output cardinality exceeds OCaml array limits";
    if !invalid = None then
      for primitive = 1 to source_primitives do
        source_primitive_offsets.(primitive) <-
          source_primitive_offsets.(primitive) * sides
      done;
    match !invalid with
    | Some message -> Error ("Pdk_mesh.Sweep_circle.sweep_circle: " ^ message)
    | None ->
        let output_points = source_vertices * sides
        and side_primitives = !edge_count * sides in
        let cap_primitives = if caps then !open_count * 2 else 0 in
        let output_primitives = side_primitives + cap_primitives in
        if output_primitives < side_primitives
            || side_primitives > max_int / 4
            || (cap_primitives > 0
                && cap_primitives > (max_int - (side_primitives * 4)) / sides) then
          Error "Pdk_mesh.Sweep_circle.sweep_circle: output vertex count exceeds OCaml array limits"
        else
          let side_vertices = side_primitives * 4 in
          let output_vertices = side_vertices + (cap_primitives * sides) in
          let px = Array.make output_points 0. and py = Array.make output_points 0.
          and pz = Array.make output_points 0. and nx = Array.make output_points 0.
          and ny = Array.make output_points 0. and nz = Array.make output_points 0.
          and uvx = Array.make output_vertices 0. and uvy = Array.make output_vertices 0.
          and point_map = Array.make output_points 0
          and frame_nx = Array.make source_vertices 0.
          and frame_ny = Array.make source_vertices 0.
          and frame_nz = Array.make source_vertices 0.
          and tangent_x = Array.make source_vertices 0.
          and tangent_y = Array.make source_vertices 0.
          and tangent_z = Array.make source_vertices 0.
          and cumulative = Array.make source_vertices 0.
          and curve_total = Array.make source_primitives 0.
          and vertex_points = Array.make output_vertices 0
          and vertex_map = Array.make output_vertices 0
          and primitive_offsets = Array.init (output_primitives + 1)
              (fun primitive ->
                if primitive <= side_primitives then primitive * 4
                else side_vertices + ((primitive - side_primitives) * sides))
          and primitive_map = Array.make output_primitives 0
          and primitive_kinds = Bytes.make output_primitives '\000'
          and vertex_nx = if caps then Array.make output_vertices 0. else [||]
          and vertex_ny = if caps then Array.make output_vertices 0. else [||]
          and vertex_nz = if caps then Array.make output_vertices 0. else [||] in
          let edge_primitive = Array.make !edge_count 0 in
          if source_primitives > 0 then Parallel.for_ ~chunk_size:1 ~start:0
              ~finish:(source_primitives - 1) (fun primitive ->
            let first_edge = source_primitive_offsets.(primitive) / sides
            and last_edge = source_primitive_offsets.(primitive + 1) / sides in
            for edge = first_edge to last_edge - 1 do
              edge_primitive.(edge) <- primitive
            done);
          let side_cos = Array.init sides (fun side ->
              cos (2. *. Float.pi *. float_of_int side /. float_of_int sides))
          and side_sin = Array.init sides (fun side ->
              sin (2. *. Float.pi *. float_of_int side /. float_of_int sides))
          and failures = Bytes.make source_primitives '\000'
          and invalid_frames = Bytes.make source_vertices '\000' in
          let base_seam = let value = seam_offset mod sides in
            if value < 0 then value + sides else value in
          let initialize_frame vertex tx ty tz =
            let ax, ay, az =
              let x = abs_float tx and y = abs_float ty and z = abs_float tz in
              if x <= y && x <= z then 1., 0., 0.
              else if y <= z then 0., 1., 0. else 0., 0., 1. in
            let x = (ay *. tz) -. (az *. ty)
            and y = (az *. tx) -. (ax *. tz)
            and z = (ax *. ty) -. (ay *. tx) in
            let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
            frame_nx.(vertex) <- x /. length;
            frame_ny.(vertex) <- y /. length;
            frame_nz.(vertex) <- z /. length in
          let average_vertices = max 1
              (source_vertices / max 1 source_primitives) in
          if source_primitives > 0 then Parallel.for_
              ~chunk_size:(max 1 (grain / average_vertices)) ~start:0
              ~finish:(source_primitives - 1) (fun primitive ->
            Cancel.check_opt cancel;
            let first, last = Topology.primitive_vertex_range topology primitive in
            let count = last - first
            and closed = Topology.primitive_kind topology primitive
                = Topology.Closed_polyline in
            for local = 0 to count - 1 do
              if local land 4095 = 0 then Cancel.check_opt cancel;
              let previous = if local = 0 then (if closed then count - 1 else 0)
                else local - 1
              and next = if local = count - 1 then (if closed then 0 else count - 1)
                else local + 1 in
              let previous_point = Topology.point_of_vertex topology (first + previous)
              and next_point = Topology.point_of_vertex topology (first + next) in
              let tx = source_positions.x.(next_point) -. source_positions.x.(previous_point)
              and ty = source_positions.y.(next_point) -. source_positions.y.(previous_point)
              and tz = source_positions.z.(next_point) -. source_positions.z.(previous_point) in
              let ax = abs_float tx and ay = abs_float ty and az = abs_float tz in
              let scale = if ax >= ay then if ax >= az then ax else az
                else if ay >= az then ay else az in
              let sx = if scale = 0. then 0. else tx /. scale
              and sy = if scale = 0. then 0. else ty /. scale
              and sz = if scale = 0. then 0. else tz /. scale in
              let length = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
              if scale = 0. || not (Float.is_finite scale && Float.is_finite length) then begin
                if Bytes.get failures primitive = '\000' then
                  Bytes.set failures primitive '\001'
              end
              else begin
                tangent_x.(first + local) <- sx /. length;
                tangent_y.(first + local) <- sy /. length;
                tangent_z.(first + local) <- sz /. length
              end;
              if local > 0 then begin
                let a = Topology.point_of_vertex topology (first + local - 1)
                and b = Topology.point_of_vertex topology (first + local) in
                let dx = source_positions.x.(b) -. source_positions.x.(a)
                and dy = source_positions.y.(b) -. source_positions.y.(a)
                and dz = source_positions.z.(b) -. source_positions.z.(a) in
                let ax = abs_float dx and ay = abs_float dy
                and az = abs_float dz in
                let scale = if ax >= ay then if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let sx = if scale = 0. then 0. else dx /. scale
                and sy = if scale = 0. then 0. else dy /. scale
                and sz = if scale = 0. then 0. else dz /. scale in
                let segment_length = scale
                    *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                if segment_length <= 1e-20 || not (Float.is_finite segment_length) then
                  Bytes.set failures primitive '\003'
                else cumulative.(first + local) <-
                    cumulative.(first + local - 1) +. segment_length
              end
            done;
            let total = if closed then begin
                let a = Topology.point_of_vertex topology (last - 1)
                and b = Topology.point_of_vertex topology first in
                let dx = source_positions.x.(b) -. source_positions.x.(a)
                and dy = source_positions.y.(b) -. source_positions.y.(a)
                and dz = source_positions.z.(b) -. source_positions.z.(a) in
                let ax = abs_float dx and ay = abs_float dy
                and az = abs_float dz in
                let scale = if ax >= ay then if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let sx = if scale = 0. then 0. else dx /. scale
                and sy = if scale = 0. then 0. else dy /. scale
                and sz = if scale = 0. then 0. else dz /. scale in
                let segment_length = scale
                    *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                if segment_length <= 1e-20 || not (Float.is_finite segment_length) then begin
                  Bytes.set failures primitive '\003'; 0.
                end else cumulative.(last - 1) +. segment_length
              end else cumulative.(last - 1) in
            curve_total.(primitive) <- total;
            if total <= 1e-20 || not (Float.is_finite total) then begin
              if Bytes.get failures primitive = '\000' then
                Bytes.set failures primitive '\002'
            end;
            if Bytes.get failures primitive = '\000' then begin
              (match up_values with
               | Some _ -> ()
               | None ->
                initialize_frame first tangent_x.(first) tangent_y.(first)
                  tangent_z.(first);
                for local = 1 to count - 1 do
                let previous = first + local - 1 and vertex = first + local in
                let ax = (tangent_y.(previous) *. tangent_z.(vertex))
                    -. (tangent_z.(previous) *. tangent_y.(vertex))
                and ay = (tangent_z.(previous) *. tangent_x.(vertex))
                    -. (tangent_x.(previous) *. tangent_z.(vertex))
                and az = (tangent_x.(previous) *. tangent_y.(vertex))
                    -. (tangent_y.(previous) *. tangent_x.(vertex)) in
                let sine = sqrt ((ax *. ax) +. (ay *. ay) +. (az *. az))
                and cosine = (tangent_x.(previous) *. tangent_x.(vertex))
                    +. (tangent_y.(previous) *. tangent_y.(vertex))
                    +. (tangent_z.(previous) *. tangent_z.(vertex)) in
                if sine <= 1e-12 then
                  if cosine >= 0. then begin
                    frame_nx.(vertex) <- frame_nx.(previous);
                    frame_ny.(vertex) <- frame_ny.(previous);
                    frame_nz.(vertex) <- frame_nz.(previous)
                  end else initialize_frame vertex tangent_x.(vertex)
                      tangent_y.(vertex) tangent_z.(vertex)
                else begin
                  let kx = ax /. sine and ky = ay /. sine and kz = az /. sine
                  and vx = frame_nx.(previous) and vy = frame_ny.(previous)
                  and vz = frame_nz.(previous) in
                  let cross_x = (ky *. vz) -. (kz *. vy)
                  and cross_y = (kz *. vx) -. (kx *. vz)
                  and cross_z = (kx *. vy) -. (ky *. vx)
                  and dot = (kx *. vx) +. (ky *. vy) +. (kz *. vz) in
                  frame_nx.(vertex) <- (vx *. cosine) +. (cross_x *. sine)
                    +. (kx *. dot *. (1. -. cosine));
                  frame_ny.(vertex) <- (vy *. cosine) +. (cross_y *. sine)
                    +. (ky *. dot *. (1. -. cosine));
                  frame_nz.(vertex) <- (vz *. cosine) +. (cross_z *. sine)
                    +. (kz *. dot *. (1. -. cosine))
                end
                done;
                if closed then begin
                  let previous = last - 1 and vertex = first in
                  let ax = (tangent_y.(previous) *. tangent_z.(vertex))
                      -. (tangent_z.(previous) *. tangent_y.(vertex))
                  and ay = (tangent_z.(previous) *. tangent_x.(vertex))
                      -. (tangent_x.(previous) *. tangent_z.(vertex))
                  and az = (tangent_x.(previous) *. tangent_y.(vertex))
                      -. (tangent_y.(previous) *. tangent_x.(vertex)) in
                  let sine = sqrt ((ax *. ax) +. (ay *. ay) +. (az *. az))
                  and cosine = (tangent_x.(previous) *. tangent_x.(vertex))
                      +. (tangent_y.(previous) *. tangent_y.(vertex))
                      +. (tangent_z.(previous) *. tangent_z.(vertex)) in
                  let cnx, cny, cnz = if sine <= 1e-12 then
                      frame_nx.(previous), frame_ny.(previous),
                      frame_nz.(previous)
                    else
                      let kx = ax /. sine and ky = ay /. sine and kz = az /. sine
                      and vx = frame_nx.(previous) and vy = frame_ny.(previous)
                      and vz = frame_nz.(previous) in
                      let cross_x = (ky *. vz) -. (kz *. vy)
                      and cross_y = (kz *. vx) -. (kx *. vz)
                      and cross_z = (kx *. vy) -. (ky *. vx)
                      and dot = (kx *. vx) +. (ky *. vy) +. (kz *. vz) in
                      (vx *. cosine) +. (cross_x *. sine)
                        +. (kx *. dot *. (1. -. cosine)),
                      (vy *. cosine) +. (cross_y *. sine)
                        +. (ky *. dot *. (1. -. cosine)),
                      (vz *. cosine) +. (cross_z *. sine)
                        +. (kz *. dot *. (1. -. cosine)) in
                  let target_x = frame_nx.(first)
                  and target_y = frame_ny.(first)
                  and target_z = frame_nz.(first) in
                  let cross_x = (cny *. target_z) -. (cnz *. target_y)
                  and cross_y = (cnz *. target_x) -. (cnx *. target_z)
                  and cross_z = (cnx *. target_y) -. (cny *. target_x) in
                  let correction = atan2
                      ((tangent_x.(first) *. cross_x)
                        +. (tangent_y.(first) *. cross_y)
                        +. (tangent_z.(first) *. cross_z))
                      ((cnx *. target_x) +. (cny *. target_y)
                        +. (cnz *. target_z)) in
                  let span = cumulative.(last - 1) in
                  if abs_float correction > 1e-15 && span > 0. then
                    for local = 1 to count - 1 do
                      let vertex = first + local in
                      let angle = correction *. cumulative.(vertex) /. span in
                      let cosine = cos angle and sine = sin angle
                      and tx = tangent_x.(vertex) and ty = tangent_y.(vertex)
                      and tz = tangent_z.(vertex)
                      and vx = frame_nx.(vertex) and vy = frame_ny.(vertex)
                      and vz = frame_nz.(vertex) in
                      let cross_x = (ty *. vz) -. (tz *. vy)
                      and cross_y = (tz *. vx) -. (tx *. vz)
                      and cross_z = (tx *. vy) -. (ty *. vx) in
                      frame_nx.(vertex) <- (vx *. cosine) +. (cross_x *. sine);
                      frame_ny.(vertex) <- (vy *. cosine) +. (cross_y *. sine);
                      frame_nz.(vertex) <- (vz *. cosine) +. (cross_z *. sine)
                    done
                end)
            end);
          Option.iter (fun (up : Packed.Float3.Private.view) ->
            if source_vertices > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                ~finish:(source_vertices - 1) (fun vertex ->
              if vertex land 4095 = 0 then Cancel.check_opt cancel;
                let source_point = Topology.point_of_vertex topology vertex in
                let tx = tangent_x.(vertex) and ty = tangent_y.(vertex)
                and tz = tangent_z.(vertex) in
                let ax = abs_float up.x.(source_point)
                and ay = abs_float up.y.(source_point)
                and az = abs_float up.z.(source_point) in
                let scale = if ax >= ay then if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let ux = if scale = 0. then 0. else up.x.(source_point) /. scale
                and uy = if scale = 0. then 0. else up.y.(source_point) /. scale
                and uz = if scale = 0. then 0. else up.z.(source_point) /. scale in
                let projection = (ux *. tx) +. (uy *. ty) +. (uz *. tz) in
                let x = ux -. (projection *. tx)
                and y = uy -. (projection *. ty)
                and z = uz -. (projection *. tz) in
                let ax = abs_float x and ay = abs_float y
                and az = abs_float z in
                let residual_scale = if ax >= ay then
                    if ax >= az then ax else az
                  else if ay >= az then ay else az in
                let sx = if residual_scale = 0. then 0.
                    else x /. residual_scale
                and sy = if residual_scale = 0. then 0.
                    else y /. residual_scale
                and sz = if residual_scale = 0. then 0.
                    else z /. residual_scale in
                let length = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                if scale = 0. || residual_scale <= 1e-12
                    || not (Float.is_finite length) then
                  Bytes.set invalid_frames vertex '\001'
                else begin
                  frame_nx.(vertex) <- sx /. length;
                  frame_ny.(vertex) <- sy /. length;
                  frame_nz.(vertex) <- sz /. length
                end)) up_values;
          let invalid_positions = Bytes.make source_vertices '\000' in
          if source_vertices > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(source_vertices - 1) (fun vertex ->
            if vertex land 4095 = 0 then Cancel.check_opt cancel;
            let source_point = Topology.point_of_vertex topology vertex in
            let ring_radius = radius *. match scale_values with
              | None -> 1. | Some values -> values.(source_point) in
            let attribute_seam = match seam_values with
              | None -> 0
              | Some values -> let value = values.(source_point) mod sides in
                  if value < 0 then value + sides else value in
            let ring_seam = let value = base_seam + attribute_seam in
              if value >= sides then value - sides else value in
            let bx = (tangent_y.(vertex) *. frame_nz.(vertex))
                -. (tangent_z.(vertex) *. frame_ny.(vertex))
            and by = (tangent_z.(vertex) *. frame_nx.(vertex))
                -. (tangent_x.(vertex) *. frame_nz.(vertex))
            and bz = (tangent_x.(vertex) *. frame_ny.(vertex))
                -. (tangent_y.(vertex) *. frame_nx.(vertex)) in
            let frame_b_length = sqrt ((bx *. bx) +. (by *. by) +. (bz *. bz)) in
            let invalid_frame_b = frame_b_length = 0.
                || not (Float.is_finite frame_b_length) in
            if invalid_frame_b then Bytes.set invalid_frames vertex '\002';
            let bx = if invalid_frame_b then 0. else bx /. frame_b_length
            and by = if invalid_frame_b then 0. else by /. frame_b_length
            and bz = if invalid_frame_b then 0. else bz /. frame_b_length in
            for side = 0 to sides - 1 do
              let profile_side = let value = side + ring_seam in
                if value >= sides then value - sides else value in
              let cosine = side_cos.(profile_side)
              and sine = side_sin.(profile_side)
              and output = (vertex * sides) + side in
              let rx = (frame_nx.(vertex) *. cosine)
                  +. (bx *. sine)
              and ry = (frame_ny.(vertex) *. cosine)
                  +. (by *. sine)
              and rz = (frame_nz.(vertex) *. cosine)
                  +. (bz *. sine) in
              let x = source_positions.x.(source_point) +. (ring_radius *. rx)
              and y = source_positions.y.(source_point) +. (ring_radius *. ry)
              and z = source_positions.z.(source_point) +. (ring_radius *. rz) in
              if Float.is_finite x && Float.is_finite y && Float.is_finite z then begin
                px.(output) <- x; py.(output) <- y; pz.(output) <- z
              end else Bytes.set invalid_positions vertex '\001';
              nx.(output) <- rx; ny.(output) <- ry; nz.(output) <- rz;
              point_map.(output) <- source_point
            done);
          if !edge_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(!edge_count - 1) (fun edge ->
            if edge land 4095 = 0 then Cancel.check_opt cancel;
            let primitive = edge_primitive.(edge) in
            let first, last = Topology.primitive_vertex_range topology primitive in
            let count = last - first
            and closed = Topology.primitive_kind topology primitive
                = Topology.Closed_polyline
            and edge_base = source_primitive_offsets.(primitive) / sides in
            let local = edge - edge_base in
            let current = first + local
            and next = first + ((local + 1) mod count)
            and total = curve_total.(primitive) in
            for side = 0 to sides - 1 do
              let next_side = (side + 1) mod sides
              and output_primitive = (edge * sides) + side in
              let at = output_primitive * 4 in
              vertex_points.(at) <- (current * sides) + side;
              vertex_points.(at + 1) <- (current * sides) + next_side;
              vertex_points.(at + 2) <- (next * sides) + next_side;
              vertex_points.(at + 3) <- (next * sides) + side;
              if caps then begin
                vertex_nx.(at) <- nx.((current * sides) + side);
                vertex_ny.(at) <- ny.((current * sides) + side);
                vertex_nz.(at) <- nz.((current * sides) + side);
                vertex_nx.(at + 1) <- nx.((current * sides) + next_side);
                vertex_ny.(at + 1) <- ny.((current * sides) + next_side);
                vertex_nz.(at + 1) <- nz.((current * sides) + next_side);
                vertex_nx.(at + 2) <- nx.((next * sides) + next_side);
                vertex_ny.(at + 2) <- ny.((next * sides) + next_side);
                vertex_nz.(at + 2) <- nz.((next * sides) + next_side);
                vertex_nx.(at + 3) <- nx.((next * sides) + side);
                vertex_ny.(at + 3) <- ny.((next * sides) + side);
                vertex_nz.(at + 3) <- nz.((next * sides) + side)
              end;
              vertex_map.(at) <- current; vertex_map.(at + 1) <- current;
              vertex_map.(at + 2) <- next; vertex_map.(at + 3) <- next;
              let u0 = float_of_int side /. float_of_int sides
              and u1 = float_of_int (side + 1) /. float_of_int sides
              and v0 = match v_values with
                | Some values -> values.(Topology.point_of_vertex topology current)
                | None -> cumulative.(current) /. total
              and v1 = match v_values with
                | Some values -> values.(Topology.point_of_vertex topology next)
                | None -> if closed && local = count - 1 then 1.
                    else cumulative.(next) /. total in
              uvx.(at) <- u0; uvy.(at) <- v0;
              uvx.(at + 1) <- u1; uvy.(at + 1) <- v0;
              uvx.(at + 2) <- u1; uvy.(at + 2) <- v1;
              uvx.(at + 3) <- u0; uvy.(at + 3) <- v1;
              primitive_map.(output_primitive) <- primitive
            done);
          if caps && source_primitives > 0 then Parallel.for_
              ~chunk_size:(max 1 (grain / average_vertices)) ~start:0
              ~finish:(source_primitives - 1) (fun primitive ->
            let rank = open_ranks.(primitive) in
            if rank >= 0 && Bytes.get failures primitive = '\000' then begin
              Cancel.check_opt cancel;
              let first, last = Topology.primitive_vertex_range topology primitive in
              let start_primitive = side_primitives + (rank * 2)
              and start_vertex = side_vertices + (rank * 2 * sides) in
              let seam_at vertex =
                let source_point = Topology.point_of_vertex topology vertex in
                let attribute_seam = match seam_values with
                  | None -> 0
                  | Some values -> let value = values.(source_point) mod sides in
                      if value < 0 then value + sides else value in
                let value = base_seam + attribute_seam in
                if value >= sides then value - sides else value in
              let start_seam = seam_at first and end_seam = seam_at (last - 1) in
              primitive_map.(start_primitive) <- primitive;
              primitive_map.(start_primitive + 1) <- primitive;
              for local = 0 to sides - 1 do
                let start_side = sides - 1 - local
                and end_side = local
                and start_at = start_vertex + local
                and end_at = start_vertex + sides + local in
                vertex_points.(start_at) <- (first * sides) + start_side;
                vertex_points.(end_at) <- ((last - 1) * sides) + end_side;
                vertex_map.(start_at) <- first;
                vertex_map.(end_at) <- last - 1;
                let start_profile = let value = start_side + start_seam in
                  if value >= sides then value - sides else value
                and end_profile = let value = end_side + end_seam in
                  if value >= sides then value - sides else value in
                uvx.(start_at) <- 0.5 +. (0.5 *. side_cos.(start_profile));
                uvy.(start_at) <- 0.5 +. (0.5 *. side_sin.(start_profile));
                uvx.(end_at) <- 0.5 +. (0.5 *. side_cos.(end_profile));
                uvy.(end_at) <- 0.5 +. (0.5 *. side_sin.(end_profile));
                vertex_nx.(start_at) <- -.tangent_x.(first);
                vertex_ny.(start_at) <- -.tangent_y.(first);
                vertex_nz.(start_at) <- -.tangent_z.(first);
                vertex_nx.(end_at) <- tangent_x.(last - 1);
                vertex_ny.(end_at) <- tangent_y.(last - 1);
                vertex_nz.(end_at) <- tangent_z.(last - 1)
              done
            end);
          let failed_primitive = ref 0 in
          while !failed_primitive < source_primitives
              && Bytes.get failures !failed_primitive = '\000' do
            incr failed_primitive
          done;
          let invalid_frame = ref 0 in
          while !invalid_frame < source_vertices
              && Bytes.get invalid_frames !invalid_frame = '\000' do
            incr invalid_frame
          done;
          let invalid_position = ref 0 in
          while !invalid_position < source_vertices
              && Bytes.get invalid_positions !invalid_position = '\000' do
            incr invalid_position
          done;
          if !failed_primitive < source_primitives then
            Error (Printf.sprintf "Pdk_mesh.Sweep_circle.sweep_circle: primitive %d has %s"
              !failed_primitive
              (match Bytes.get failures !failed_primitive with
               | '\001' -> "an undefined tangent"
               | '\003' -> "a zero-length or non-finite edge"
               | _ -> "zero length"))
          else if !invalid_frame < source_vertices then
            Error (Printf.sprintf
              "Pdk_mesh.Sweep_circle.sweep_circle: point %d has %s"
              (Topology.point_of_vertex topology !invalid_frame)
              (match Bytes.get invalid_frames !invalid_frame with
               | '\001' -> "a joint up vector parallel to its tangent"
               | _ -> "an undefined local frame"))
          else if !invalid_position < source_vertices then
            Error (Printf.sprintf
              "Pdk_mesh.Sweep_circle.sweep_circle: generated ring %d is not finite"
              !invalid_position)
          else
              let output_positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz
              and output_topology = Topology.Private.create_validated_owned
                  ~point_count:output_points ~vertex_points ~primitive_offsets
                  ~primitive_kinds in
              let rec attributes result = function
                | [] -> Ok (List.rev result)
                | attribute :: rest -> Result.bind
                    (Topology_remap.mapped_attribute ~grain:16_384 ~point_map ~vertex_map
                      ~primitive_map ~drop:Topology_remap.drop_point_vertex_normals
                      attribute)
                    (function None -> attributes result rest
                      | Some attribute -> attributes (attribute :: result) rest) in
              Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
                let normal = Attribute.create_key_owned
                    (Attribute.normal ~owner:Attribute.Point)
                    (Packed.Float3.Private.of_owned_exn ~x:nx ~y:ny ~z:nz) |> get_ok
                and uv = Attribute.create_key_owned
                    (Attribute.tex_coord ~owner:Attribute.Vertex)
                    (Packed.Float2.of_owned ~x:uvx ~y:uvy |> get_ok) |> get_ok in
                let vertex_normal = if caps then Some
                    (Attribute.create_key_owned
                      (Attribute.normal ~owner:Attribute.Vertex)
                      (Packed.Float3.Private.of_owned_exn ~x:vertex_nx
                        ~y:vertex_ny ~z:vertex_nz) |> get_ok)
                  else None in
                let groups = List.map
                    (Topology_remap.mapped_group ~grain:16_384 ~point_map ~vertex_map
                    ~primitive_map)
                    (Geometry.groups geometry) in
                let edge_groups = match Geometry.edge_groups geometry with
                  | [] -> []
                  | source_groups ->
                      let source_index = Topology_index.create ?cancel topology
                      and target_index = Topology_index.create ?cancel
                          output_topology in
                      List.map (fun source_group ->
                        let builder = Edge_group.Builder.create
                            ~topology:output_topology ~index:target_index
                            ~name:(Edge_group.name source_group) in
                        Edge_group.iter (fun edge ->
                          let incidence = Topology_index.edge_incidence_count
                              source_index edge in
                          for local = 0 to incidence - 1 do
                            let current = Topology_index.edge_vertex source_index
                                ~edge ~local in
                            let next = Topology_index.next_vertex source_index current in
                            if next >= 0 then
                              for side = 0 to sides - 1 do
                                match Topology_index.find_edge target_index
                                    ~a:(current * sides + side)
                                    ~b:(next * sides + side) with
                                | None -> ()
                                | Some target ->
                                    Edge_group.Builder.set builder target true
                              done
                          done) source_group;
                        Edge_group.Builder.freeze builder) source_groups in
                Result.bind (Geometry.create ~positions:output_positions
                    ~topology:output_topology ~attributes ~groups ~edge_groups ())
                  (fun geometry ->
                  Result.bind (Geometry.with_attribute normal geometry)
                    (fun geometry ->
                  Result.bind (Geometry.with_attribute uv geometry)
                    (fun geometry ->
                  Result.bind (match vertex_normal with
                    | None -> Ok geometry
                    | Some normal -> Geometry.with_attribute normal geometry)
                    (fun geometry -> match cap_group with
                      | None -> Ok geometry
                      | Some name -> Geometry.with_group
                          (Group.init ~grain ~owner:Group.Primitive ~name
                            output_primitives
                            (fun primitive -> primitive >= side_primitives))
                          geometry)))))

let run ?cancel ?grain ?primitives ?sides ?divisions_attribute
    ?segments ?segments_attribute ?segment_scales ?segment_scales_attribute
    ?(prevent_joint_buckling = false) ?(maximum_joint_scale = 10.)
    ?maximum_joint_scale_attribute
    ?(smooth_point = true) ?smooth_attribute ?max_valence
    ?scale_attribute ?seam_offset ?seam_attribute ?segment_seam_attribute
    ?v_attribute
    ?(generate_uv = true) ?u_range ?v_range ?uv_range_attribute ?up_attribute
    ?caps ?cap_group ~radius geometry =
  Error.guard ~operation:"sweep_circle" ~code:"invalid_geometry" @@ fun () ->
    let grain = Option.value ~default:16_384 grain
    and sides = Option.value ~default:12 sides
    and segments = Option.value ~default:1 segments
    and seam_offset = Option.value ~default:0 seam_offset
    and caps = Option.value ~default:false caps in
    if Option.is_none primitives && Option.is_none divisions_attribute
        && segments = 1 && Option.is_none segments_attribute
        && Option.is_none segment_scales
        && Option.is_none segment_scales_attribute
        && not prevent_joint_buckling
        && Float.is_finite maximum_joint_scale && maximum_joint_scale >= 1.
        && Option.is_none maximum_joint_scale_attribute && generate_uv
        && smooth_point && Option.is_none smooth_attribute
        && Option.is_none max_valence
        && Option.is_none segment_seam_attribute
        && Option.is_none u_range && Option.is_none v_range
        && Option.is_none uv_range_attribute then
      run_legacy ?cancel ~grain ~sides ?scale_attribute ~seam_offset
        ?seam_attribute ?v_attribute ?up_attribute ~caps ?cap_group ~radius
        geometry
    else Polywire.run ?cancel ~grain ~primitives ~sides ~divisions_attribute
        ~segments ~segments_attribute ~segment_scales
        ~segment_scales_attribute ~prevent_joint_buckling
        ~maximum_joint_scale ~maximum_joint_scale_attribute ~scale_attribute
        ~smooth_point ~smooth_attribute ~max_valence ~seam_offset
        ~seam_attribute ~segment_seam_attribute ~v_attribute ~generate_uv
        ~u_range ~v_range ~uv_range_attribute ~up_attribute ~caps ~cap_group
        ~radius geometry
