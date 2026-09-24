open Prismel

type tangent =
  | Average_edges
  | Central_difference
  | Previous_edge
  | Next_edge
  | Z_axis

type connectivity =
  | Points
  | Rows
  | Columns
  | Rows_and_columns
  | Quads
  | Triangles
  | Alternating_triangles
  | Reverse_triangles

type curve = {
  primitive : int;
  first : int;
  count : int;
  closed : bool;
}

type pair = {
  backbone : curve;
  profile : curve;
  point_first : int;
}

let finite = Float.is_finite

let checked_add label left right =
  if right < 0 || left > max_int - right then
    Error (label ^ ": output cardinality exceeds OCaml array limits")
  else Ok (left + right)

let checked_product label left right =
  if left < 0 || right < 0 || (left <> 0 && right > max_int / left) then
    Error (label ^ ": output cardinality exceeds OCaml array limits")
  else Ok (left * right)

let parallel_ranges ?cancel ~grain length body =
  if length > 0 then begin
    let chunks = 1 + ((length - 1) / grain) in
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(chunks - 1) (fun chunk ->
      Cancel.check_opt cancel;
      let first = chunk * grain in
      body ~first ~last:(first + min grain (length - first)))
  end

let robust_length x y z =
  let ax = abs_float x and ay = abs_float y and az = abs_float z in
  let scale = max ax (max ay az) in
  if scale = 0. then 0.
  else if not (finite scale) then Float.nan
  else
    let x = x /. scale and y = y /. scale and z = z /. scale in
    scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z))

let collect_curves label geometry selection =
  let topology = Geometry.topology geometry in
  let primitive_count = Geometry.primitive_count geometry in
  let selected primitive = match selection with
    | None -> true
    | Some group -> Group.mem primitive group in
  match selection with
  | Some group when Group.owner group <> Group.Primitive ->
      Error (label ^ " selection must be primitive-owned")
  | Some group when Group.length group <> primitive_count ->
      Error (label ^ " selection length does not match its geometry")
  | None | Some _ ->
      let count = ref 0 and failure = ref None in
      for primitive = 0 to primitive_count - 1 do
        if selected primitive then begin
          let size = Topology.primitive_size topology primitive in
          let kind = Topology.primitive_kind topology primitive in
          (match kind with
           | Topology.Polygon -> failure := Some (Printf.sprintf
               "%s primitive %d is a polygon; Sweep inputs must be polygon curves"
               label primitive)
           | Topology.Open_polyline when size < 2 -> failure := Some
               (Printf.sprintf "%s primitive %d has fewer than two vertices"
                  label primitive)
           | Topology.Closed_polyline when size < 3 -> failure := Some
               (Printf.sprintf "%s primitive %d has fewer than three vertices"
                  label primitive)
           | Topology.Open_polyline | Topology.Closed_polyline -> incr count)
        end
      done;
      (match !failure with
       | Some message -> Error message
       | None ->
           let output = Array.make !count
               { primitive = 0; first = 0; count = 2; closed = false } in
           let at = ref 0 in
           for primitive = 0 to primitive_count - 1 do
             if selected primitive then begin
               let first, last = Topology.primitive_vertex_range topology primitive in
               output.(!at) <- { primitive; first; count = last - first;
                 closed = Topology.primitive_kind topology primitive
                     = Topology.Closed_polyline };
               incr at
             end
           done;
           Ok output)

let validate_selected_positions label geometry curves =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Geometry.topology geometry in
  let failure = ref None in
  let curve = ref 0 in
  while !failure = None && !curve < Array.length curves do
    let value = curves.(!curve) in
    let local = ref 0 in
    while !failure = None && !local < value.count do
      let vertex = value.first + !local in
      let point = Topology.point_of_vertex topology vertex in
      if not (finite positions.x.(point) && finite positions.y.(point)
          && finite positions.z.(point)) then
        failure := Some (Printf.sprintf "%s point %d is not finite" label point);
      let has_edge = !local + 1 < value.count || value.closed in
      if has_edge then begin
        let next = value.first + ((!local + 1) mod value.count) in
        let next_point = Topology.point_of_vertex topology next in
        let length = robust_length
            (positions.x.(next_point) -. positions.x.(point))
            (positions.y.(next_point) -. positions.y.(point))
            (positions.z.(next_point) -. positions.z.(point)) in
        if length <= 1e-20 || not (finite length) then
          failure := Some (Printf.sprintf
              "%s primitive %d has a zero-length or non-finite edge at vertex %d"
              label value.primitive vertex)
      end;
      incr local
    done;
    incr curve
  done;
  match !failure with None -> Ok () | Some message -> Error message

let point_float geometry name =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> Ok (Some values)
       | _ -> Error (Printf.sprintf "point attribute %S must have float storage" name))

let point_float3 geometry name =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values -> Ok (Some (Packed.Float3.Private.view values))
       | _ -> Error (Printf.sprintf "point attribute %S must have float3 storage" name))

let point_float4 geometry name =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok None
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values -> Ok (Some (Packed.Float4.Private.view values))
       | _ -> Error (Printf.sprintf "point attribute %S must have float4 storage" name))

let validate_selected_float ?cancel topology curves values name =
  let failure = ref None and curve_index = ref 0 in
  while !failure = None && !curve_index < Array.length curves do
    let curve = curves.(!curve_index) and local = ref 0 in
    while !failure = None && !local < curve.count do
      if !local land 4095 = 0 then Cancel.check_opt cancel;
      let point = Topology.point_of_vertex topology (curve.first + !local) in
      if not (finite values.(point)) then failure := Some (Printf.sprintf
          "point attribute %S is not finite at selected point %d" name point);
      incr local
    done;
    incr curve_index
  done;
  match !failure with None -> Ok () | Some message -> Error message

let validate_selected_float3 ?cancel topology curves
    (values : Packed.Float3.Private.view) name =
  let failure = ref None and curve_index = ref 0 in
  while !failure = None && !curve_index < Array.length curves do
    let curve = curves.(!curve_index) and local = ref 0 in
    while !failure = None && !local < curve.count do
      if !local land 4095 = 0 then Cancel.check_opt cancel;
      let point = Topology.point_of_vertex topology (curve.first + !local) in
      if not (finite values.x.(point) && finite values.y.(point)
          && finite values.z.(point)) then failure := Some (Printf.sprintf
          "point attribute %S is not finite at selected point %d" name point);
      incr local
    done;
    incr curve_index
  done;
  match !failure with None -> Ok () | Some message -> Error message

let validate_selected_float4 ?cancel topology curves
    (values : Packed.Float4.Private.view) name =
  let failure = ref None and curve_index = ref 0 in
  while !failure = None && !curve_index < Array.length curves do
    let curve = curves.(!curve_index) and local = ref 0 in
    while !failure = None && !local < curve.count do
      if !local land 4095 = 0 then Cancel.check_opt cancel;
      let point = Topology.point_of_vertex topology (curve.first + !local) in
      if not (finite values.x.(point) && finite values.y.(point)
          && finite values.z.(point) && finite values.w.(point)) then
        failure := Some (Printf.sprintf
            "point attribute %S is not finite at selected point %d" name point);
      incr local
    done;
    incr curve_index
  done;
  match !failure with None -> Ok () | Some message -> Error message

let rotate_about_axis_into tx ty tz angle x y z ox oy oz index =
  let cosine = cos angle and sine = sin angle in
  let cross_x = (ty *. z) -. (tz *. y)
  and cross_y = (tz *. x) -. (tx *. z)
  and cross_z = (tx *. y) -. (ty *. x)
  and dot = (tx *. x) +. (ty *. y) +. (tz *. z) in
  ox.(index) <- (x *. cosine) +. (cross_x *. sine)
      +. (tx *. dot *. (1. -. cosine));
  oy.(index) <- (y *. cosine) +. (cross_y *. sine)
      +. (ty *. dot *. (1. -. cosine));
  oz.(index) <- (z *. cosine) +. (cross_z *. sine)
      +. (tz *. dot *. (1. -. cosine))

let quaternion_basis_into (orient : Packed.Float4.Private.view) point vertex
    out_x out_y out_z up_x up_y up_z tangent_x tangent_y tangent_z =
  let x = orient.x.(point) and y = orient.y.(point)
  and z = orient.z.(point) and w = orient.w.(point) in
  let norm = sqrt ((x *. x) +. (y *. y) +. (z *. z) +. (w *. w)) in
  if norm <= 1e-20 || not (finite norm) then false
  else
    let x = x /. norm and y = y /. norm and z = z /. norm and w = w /. norm in
    let xx = x *. x and yy = y *. y and zz = z *. z
    and xy = x *. y and xz = x *. z and yz = y *. z
    and wx = w *. x and wy = w *. y and wz = w *. z in
    out_x.(vertex) <- 1. -. (2. *. (yy +. zz));
    out_y.(vertex) <- 2. *. (xy +. wz);
    out_z.(vertex) <- 2. *. (xz -. wy);
    up_x.(vertex) <- 2. *. (xy -. wz);
    up_y.(vertex) <- 1. -. (2. *. (xx +. zz));
    up_z.(vertex) <- 2. *. (yz +. wx);
    tangent_x.(vertex) <- 2. *. (xz +. wy);
    tangent_y.(vertex) <- 2. *. (yz -. wx);
    tangent_z.(vertex) <- 1. -. (2. *. (xx +. yy));
    true

type frame_data = {
  tangent_x : float array;
  tangent_y : float array;
  tangent_z : float array;
  out_x : float array;
  out_y : float array;
  out_z : float array;
  up_x : float array;
  up_y : float array;
  up_z : float array;
  cumulative : float array;
  totals : float array;
}

let normalize_into x y z ox oy oz index =
  let ax = abs_float x and ay = abs_float y and az = abs_float z in
  let scale = max ax (max ay az) in
  if scale = 0. || not (finite scale) then false
  else
    let x = x /. scale and y = y /. scale and z = z /. scale in
    let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
    if length = 0. || not (finite length) then false
    else begin
      ox.(index) <- x /. length;
      oy.(index) <- y /. length;
      oz.(index) <- z /. length;
      true
    end

let fill_parameters ?cancel ~grain geometry curves =
  let topology = Geometry.topology geometry
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let vertex_count = Geometry.vertex_count geometry in
  let edge_x = Array.make vertex_count 0. and edge_y = Array.make vertex_count 0.
  and edge_z = Array.make vertex_count 0. and cumulative = Array.make vertex_count 0.
  and totals = Array.make (Geometry.primitive_count geometry) 0.
  and failures = Bytes.make (Array.length curves) '\000' in
  if Array.length curves > 0 then
    Parallel.for_ ~chunk_size:(max 1 (grain / 64)) ~start:0
      ~finish:(Array.length curves - 1) (fun curve_index ->
        Cancel.check_opt cancel;
        let curve = curves.(curve_index) in
        let edge_count = if curve.closed then curve.count else curve.count - 1 in
        for local = 0 to edge_count - 1 do
          if local land 4095 = 0 then Cancel.check_opt cancel;
          let vertex = curve.first + local
          and next_vertex = curve.first + ((local + 1) mod curve.count) in
          let point = Topology.point_of_vertex topology vertex
          and next_point = Topology.point_of_vertex topology next_vertex in
          let dx = positions.x.(next_point) -. positions.x.(point)
          and dy = positions.y.(next_point) -. positions.y.(point)
          and dz = positions.z.(next_point) -. positions.z.(point) in
          if not (normalize_into dx dy dz edge_x edge_y edge_z vertex) then
            Bytes.set failures curve_index '\001';
          let length = robust_length dx dy dz in
          if local + 1 < curve.count then
            cumulative.(vertex + 1) <- cumulative.(vertex) +. length
          else totals.(curve.primitive) <- cumulative.(vertex) +. length
        done;
        if not curve.closed then begin
          let last = curve.first + curve.count - 1 in
          edge_x.(last) <- edge_x.(last - 1);
          edge_y.(last) <- edge_y.(last - 1);
          edge_z.(last) <- edge_z.(last - 1);
          totals.(curve.primitive) <- cumulative.(last)
        end);
  let failed = ref 0 in
  while !failed < Array.length curves && Bytes.get failures !failed = '\000' do
    incr failed
  done;
  if !failed < Array.length curves then Error (Printf.sprintf
      "primitive %d has an undefined edge direction" curves.(!failed).primitive)
  else Ok (edge_x, edge_y, edge_z, cumulative, totals)

let build_frames ?cancel ~grain ~tangent_mode ~continuous_closed ~roll ~twist
    ~(normal_values : Packed.Float3.Private.view option)
    ~(up_values : Packed.Float3.Private.view option)
    ~(orient_values : Packed.Float4.Private.view option) backbone curves =
  let topology = Geometry.topology backbone
  and positions = Packed.Float3.Private.view (Geometry.positions backbone) in
  Result.bind (fill_parameters ?cancel ~grain backbone curves)
    (fun (edge_x, edge_y, edge_z, cumulative, totals) ->
      let vertex_count = Geometry.vertex_count backbone in
      let tangent_x = Array.make vertex_count 0.
      and tangent_y = Array.make vertex_count 0.
      and tangent_z = Array.make vertex_count 0.
      and out_x = Array.make vertex_count 0.
      and out_y = Array.make vertex_count 0.
      and out_z = Array.make vertex_count 0.
      and up_x = Array.make vertex_count 0.
      and up_y = Array.make vertex_count 0.
      and up_z = Array.make vertex_count 0.
      and failures = Bytes.make (Array.length curves) '\000' in
      let initialize_up curve_index vertex tx ty tz requested_x requested_y requested_z =
        let projection = (requested_x *. tx) +. (requested_y *. ty)
            +. (requested_z *. tz) in
        let ux = requested_x -. (projection *. tx)
        and uy = requested_y -. (projection *. ty)
        and uz = requested_z -. (projection *. tz) in
        if not (normalize_into ux uy uz up_x up_y up_z vertex) then
          Bytes.set failures curve_index '\002'
        else begin
          let x = (up_y.(vertex) *. tz) -. (up_z.(vertex) *. ty)
          and y = (up_z.(vertex) *. tx) -. (up_x.(vertex) *. tz)
          and z = (up_x.(vertex) *. ty) -. (up_y.(vertex) *. tx) in
          if not (normalize_into x y z out_x out_y out_z vertex) then
            Bytes.set failures curve_index '\002'
        end in
      if Array.length curves > 0 then
        Parallel.for_ ~chunk_size:(max 1 (grain / 64)) ~start:0
          ~finish:(Array.length curves - 1) (fun curve_index ->
            Cancel.check_opt cancel;
            let curve = curves.(curve_index) in
            (* Tangent classification is independent per curve vertex. *)
            for local = 0 to curve.count - 1 do
              if local land 4095 = 0 then Cancel.check_opt cancel;
              let vertex = curve.first + local in
              let point = Topology.point_of_vertex topology vertex in
              match orient_values with
              | Some orient ->
                  if not (quaternion_basis_into orient point vertex
                      out_x out_y out_z up_x up_y up_z
                      tangent_x tangent_y tangent_z) then
                    Bytes.set failures curve_index '\003'
              | None ->
                  (match normal_values with
                   | Some normal ->
                       if not (normalize_into normal.x.(point) normal.y.(point)
                           normal.z.(point) tangent_x tangent_y tangent_z vertex)
                       then Bytes.set failures curve_index '\004'
                   | None ->
                       let previous_vertex = if local = 0 then
                           if curve.closed then curve.first + curve.count - 1
                           else curve.first
                         else vertex - 1 in
                       let next_vertex = if local + 1 = curve.count then
                           if curve.closed then curve.first else vertex
                         else vertex + 1 in
                       let ok = match tangent_mode with
                         | Z_axis ->
                             tangent_z.(vertex) <- 1.; true
                         | Previous_edge ->
                             let edge = if local = 0 && not curve.closed
                               then curve.first else previous_vertex in
                             tangent_x.(vertex) <- edge_x.(edge);
                             tangent_y.(vertex) <- edge_y.(edge);
                             tangent_z.(vertex) <- edge_z.(edge); true
                         | Next_edge ->
                             let edge = if local + 1 = curve.count && not curve.closed
                               then vertex - 1 else vertex in
                             tangent_x.(vertex) <- edge_x.(edge);
                             tangent_y.(vertex) <- edge_y.(edge);
                             tangent_z.(vertex) <- edge_z.(edge); true
                         | Average_edges ->
                             let previous_edge = if local = 0 && not curve.closed
                               then curve.first else previous_vertex in
                             let next_edge = if local + 1 = curve.count
                                 && not curve.closed then vertex - 1 else vertex in
                             normalize_into
                               (edge_x.(previous_edge) +. edge_x.(next_edge))
                               (edge_y.(previous_edge) +. edge_y.(next_edge))
                               (edge_z.(previous_edge) +. edge_z.(next_edge))
                               tangent_x tangent_y tangent_z vertex
                         | Central_difference ->
                             let previous_point = Topology.point_of_vertex topology
                                 previous_vertex
                             and next_point = Topology.point_of_vertex topology
                                 next_vertex in
                             normalize_into
                               (positions.x.(next_point) -. positions.x.(previous_point))
                               (positions.y.(next_point) -. positions.y.(previous_point))
                               (positions.z.(next_point) -. positions.z.(previous_point))
                               tangent_x tangent_y tangent_z vertex in
                       if not ok then Bytes.set failures curve_index '\005')
            done;
            if Bytes.get failures curve_index = '\000' && orient_values = None then begin
              (* Parallel transport is ordered within a curve, while curves cook in
                 independent pooled ranges. *)
              for local = 0 to curve.count - 1 do
                if local land 4095 = 0 then Cancel.check_opt cancel;
                let vertex = curve.first + local
                and point = Topology.point_of_vertex topology (curve.first + local) in
                let tx = tangent_x.(vertex) and ty = tangent_y.(vertex)
                and tz = tangent_z.(vertex) in
                match up_values with
                | Some up -> initialize_up curve_index vertex tx ty tz
                    up.x.(point) up.y.(point) up.z.(point)
                | None when local = 0 ->
                    let projection = ty in
                    let ux = -.projection *. tx
                    and uy = 1. -. (projection *. ty)
                    and uz = -.projection *. tz in
                    if robust_length ux uy uz > 1e-10 then
                      initialize_up curve_index vertex tx ty tz 0. 1. 0.
                    else initialize_up curve_index vertex tx ty tz 1. 0. 0.
                | None ->
                    let previous = vertex - 1 in
                    let ax = (tangent_y.(previous) *. tz)
                        -. (tangent_z.(previous) *. ty)
                    and ay = (tangent_z.(previous) *. tx)
                        -. (tangent_x.(previous) *. tz)
                    and az = (tangent_x.(previous) *. ty)
                        -. (tangent_y.(previous) *. tx) in
                    let sine = robust_length ax ay az
                    and cosine = (tangent_x.(previous) *. tx)
                        +. (tangent_y.(previous) *. ty)
                        +. (tangent_z.(previous) *. tz) in
                    if sine <= 1e-12 then begin
                      if cosine < 0. then Bytes.set failures curve_index '\006'
                      else begin
                        out_x.(vertex) <- out_x.(previous);
                        out_y.(vertex) <- out_y.(previous);
                        out_z.(vertex) <- out_z.(previous)
                      end
                    end else begin
                      let kx = ax /. sine and ky = ay /. sine and kz = az /. sine in
                      rotate_about_axis_into kx ky kz (atan2 sine cosine)
                        out_x.(previous) out_y.(previous) out_z.(previous)
                        out_x out_y out_z vertex
                    end;
                    let ux = (ty *. out_z.(vertex)) -. (tz *. out_y.(vertex))
                    and uy = (tz *. out_x.(vertex)) -. (tx *. out_z.(vertex))
                    and uz = (tx *. out_y.(vertex)) -. (ty *. out_x.(vertex)) in
                    ignore (normalize_into ux uy uz up_x up_y up_z vertex)
              done;
            end;
            if Bytes.get failures curve_index = '\000' then
              for local = 0 to curve.count - 1 do
                if local land 4095 = 0 then Cancel.check_opt cancel;
                let vertex = curve.first + local in
                let total = totals.(curve.primitive) in
                let amount = roll +. if total = 0. then 0.
                    else twist *. cumulative.(vertex) /. total in
                if amount <> 0. then begin
                  rotate_about_axis_into tangent_x.(vertex)
                      tangent_y.(vertex) tangent_z.(vertex) amount
                      out_x.(vertex) out_y.(vertex) out_z.(vertex)
                      out_x out_y out_z vertex;
                  rotate_about_axis_into tangent_x.(vertex)
                      tangent_y.(vertex) tangent_z.(vertex) amount
                      up_x.(vertex) up_y.(vertex) up_z.(vertex)
                      up_x up_y up_z vertex
                end
              done;
            (* Apply loop closure after roll/twist so non-integral requested
               twists are distributed instead of becoming one seam jump. *)
            if continuous_closed && curve.closed && up_values = None
                && orient_values = None
                && Bytes.get failures curve_index = '\000' then begin
              let first = curve.first and previous = curve.first + curve.count - 1 in
              let tx = tangent_x.(first) and ty = tangent_y.(first)
              and tz = tangent_z.(first) in
              let ax = (tangent_y.(previous) *. tz)
                  -. (tangent_z.(previous) *. ty)
              and ay = (tangent_z.(previous) *. tx)
                  -. (tangent_x.(previous) *. tz)
              and az = (tangent_x.(previous) *. ty)
                  -. (tangent_y.(previous) *. tx) in
              let sine = robust_length ax ay az
              and cosine = (tangent_x.(previous) *. tx)
                  +. (tangent_y.(previous) *. ty)
                  +. (tangent_z.(previous) *. tz) in
              let closing_x, closing_y, closing_z =
                if sine <= 1e-12 then
                  out_x.(previous), out_y.(previous), out_z.(previous)
                else
                  let tx = ax /. sine and ty = ay /. sine and tz = az /. sine
                  and angle = atan2 sine cosine
                  and x = out_x.(previous) and y = out_y.(previous)
                  and z = out_z.(previous) in
                  let cosine = cos angle and sine = sin angle in
                  let cross_x = (ty *. z) -. (tz *. y)
                  and cross_y = (tz *. x) -. (tx *. z)
                  and cross_z = (tx *. y) -. (ty *. x)
                  and dot = (tx *. x) +. (ty *. y) +. (tz *. z) in
                  (x *. cosine) +. (cross_x *. sine)
                    +. (tx *. dot *. (1. -. cosine)),
                  (y *. cosine) +. (cross_y *. sine)
                    +. (ty *. dot *. (1. -. cosine)),
                  (z *. cosine) +. (cross_z *. sine)
                    +. (tz *. dot *. (1. -. cosine)) in
              let cross_x = (closing_y *. out_z.(first))
                  -. (closing_z *. out_y.(first))
              and cross_y = (closing_z *. out_x.(first))
                  -. (closing_x *. out_z.(first))
              and cross_z = (closing_x *. out_y.(first))
                  -. (closing_y *. out_x.(first)) in
              let correction = atan2
                  ((tx *. cross_x) +. (ty *. cross_y) +. (tz *. cross_z))
                  ((closing_x *. out_x.(first)) +.
                   (closing_y *. out_y.(first)) +.
                   (closing_z *. out_z.(first))) in
              let span = cumulative.(curve.first + curve.count - 1) in
              if span > 0. && abs_float correction > 1e-15 then
                for local = 1 to curve.count - 1 do
                  if local land 4095 = 0 then Cancel.check_opt cancel;
                  let vertex = curve.first + local in
                  let amount = correction *. cumulative.(vertex) /. span in
                  rotate_about_axis_into tangent_x.(vertex)
                      tangent_y.(vertex) tangent_z.(vertex) amount
                      out_x.(vertex) out_y.(vertex) out_z.(vertex)
                      out_x out_y out_z vertex;
                  rotate_about_axis_into tangent_x.(vertex)
                      tangent_y.(vertex) tangent_z.(vertex) amount
                      up_x.(vertex) up_y.(vertex) up_z.(vertex)
                      up_x up_y up_z vertex
                done
            end);
      let failed = ref 0 in
      while !failed < Array.length curves && Bytes.get failures !failed = '\000' do
        incr failed
      done;
      if !failed < Array.length curves then
        let curve = curves.(!failed) in
        Error (Printf.sprintf "backbone primitive %d has %s" curve.primitive
          (match Bytes.get failures !failed with
           | '\002' -> "an up vector parallel to its tangent"
           | '\003' -> "a zero-length or non-finite orient quaternion"
           | '\004' -> "a zero-length N tangent attribute"
           | '\005' -> "an undefined tangent at a reversal"
           | '\006' -> "an antiparallel transport discontinuity"
           | _ -> "an invalid local frame"))
      else Ok { tangent_x; tangent_y; tangent_z; out_x; out_y; out_z;
        up_x; up_y; up_z; cumulative; totals })

let select_array ?cancel ~grain mapping source =
  let count = Array.length mapping in
  if count = 0 then [||]
  else begin
    let output = Array.make count source.(mapping.(0)) in
    parallel_ranges ?cancel ~grain count (fun ~first ~last ->
      for index = first to last - 1 do
        output.(index) <- source.(mapping.(index))
      done);
    output
  end

let remap_attribute ?cancel ~grain ~prefix point_map vertex_map primitive_map
    attribute =
  let owner = Attribute.owner attribute in
  let mapping = match owner with
    | Attribute.Point -> Some point_map
    | Attribute.Vertex -> Some vertex_map
    | Attribute.Primitive -> Some primitive_map
    | Attribute.Detail -> None in
  let name = prefix ^ Attribute.name attribute in
  match mapping with
  | None -> Attribute.with_name name attribute
  | Some mapping ->
      let storage = match Attribute.Private.storage attribute with
        | Attribute.Float values ->
            Attribute.Float (select_array ?cancel ~grain mapping values)
        | Attribute.Int values ->
            Attribute.Int (select_array ?cancel ~grain mapping values)
        | Attribute.Text values ->
            Attribute.Text (select_array ?cancel ~grain mapping values)
        | Attribute.Float2 values ->
            let values = Packed.Float2.Private.view values in
            Attribute.Float2 (Packed.Float2.of_owned
              ~x:(select_array ?cancel ~grain mapping values.x)
              ~y:(select_array ?cancel ~grain mapping values.y)
              |> Result.get_ok)
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            Attribute.Float3 (Packed.Float3.Private.of_owned_exn
              ~x:(select_array ?cancel ~grain mapping values.x)
              ~y:(select_array ?cancel ~grain mapping values.y)
              ~z:(select_array ?cancel ~grain mapping values.z))
        | Attribute.Float4 values ->
            let values = Packed.Float4.Private.view values in
            Attribute.Float4 (Packed.Float4.of_owned
              ~x:(select_array ?cancel ~grain mapping values.x)
              ~y:(select_array ?cancel ~grain mapping values.y)
              ~z:(select_array ?cancel ~grain mapping values.z)
              ~w:(select_array ?cancel ~grain mapping values.w)
              |> Result.get_ok)
        | Attribute.Int_array values ->
            Attribute.Int_array (Ragged_ops.remap_int ?cancel ~grain mapping values)
        | Attribute.Float_array values ->
            Attribute.Float_array (Ragged_ops.remap_float ?cancel ~grain mapping values) in
      Attribute.create_owned ~name ~owner storage

let remap_attributes ?cancel ~grain ~prefix ~skip point_map vertex_map
    primitive_map attributes =
  let rec loop output = function
    | [] -> Ok (List.rev output)
    | attribute :: rest ->
        if skip attribute then loop output rest
        else Result.bind
            (remap_attribute ?cancel ~grain ~prefix point_map vertex_map
               primitive_map attribute)
            (fun attribute -> loop (attribute :: output) rest) in
  loop [] attributes

let remap_group ?cancel ~grain ~prefix point_map vertex_map primitive_map group =
  let mapping = match Group.owner group with
    | Group.Point -> point_map
    | Group.Vertex -> vertex_map
    | Group.Primitive -> primitive_map in
  let target = Group.init ~grain ~owner:(Group.owner group)
      ~name:(prefix ^ Group.name group) (Array.length mapping) (fun index ->
        if index land 4095 = 0 then Cancel.check_opt cancel;
        Group.mem mapping.(index) group) in
  Group.Private.remap_order ~source:group ~source_of_target:mapping target

let surface_connectivity = function
  | Quads | Triangles | Alternating_triangles | Reverse_triangles -> true
  | Points | Rows | Columns | Rows_and_columns -> false

let profile_source_local reverse count local =
  if reverse then count - 1 - local else local

let profile_parameter reverse cumulative totals curve local =
  let total_vertex = curve.first + curve.count - 1 in
  let total = max totals.(curve.primitive) 1e-300 in
  if not reverse then cumulative.(curve.first + local) /. total
  else if local = 0 then 0.
  else (cumulative.(total_vertex)
        -. cumulative.(curve.first + curve.count - 1 - local)) /. total

let find_pair pairs point =
  let low = ref 0 and high = ref (Array.length pairs) in
  while !low + 1 < !high do
    let middle = (!low + !high) lsr 1 in
    if pairs.(middle).point_first <= point then low := middle else high := middle
  done;
  !low

let find_prefix offsets index =
  let low = ref 0 and high = ref (Array.length offsets - 1) in
  while !low + 1 < !high do
    let middle = (!low + !high) lsr 1 in
    if offsets.(middle) <= index then low := middle else high := middle
  done;
  !low

let run ?cancel ~grain ?backbones ?cross_sections ~connectivity ~tangent
    ~continuous_closed ~transform_attributes ~reverse_cross_sections ~scale
    ~roll ~twist ~caps ?cap_group ~uv_attribute ~cross_section_prefix
    ~backbone ~cross_section () =
  if grain <= 0 then invalid_arg "Pdk.Ops.sweep: grain must be positive";
  if not (finite scale) then Error "Pdk.Ops.sweep: scale must be finite"
  else if not (finite roll && finite twist) then
    Error "Pdk.Ops.sweep: roll and twist must be finite"
  else if caps && not (surface_connectivity connectivity) then
    Error "Pdk.Ops.sweep: caps require polygon surface connectivity"
  else if cap_group <> None && not caps then
    Error "Pdk.Ops.sweep: cap_group requires caps=true"
  else if String.contains cross_section_prefix '\000' then
    Error "Pdk.Ops.sweep: cross-section prefix contains NUL"
  else
    let named label = function
      | Some name when String.trim name = "" ->
          Error ("Pdk.Ops.sweep: " ^ label ^ " must not be empty")
      | None | Some _ -> Ok () in
    Result.bind (named "cap group name" cap_group) (fun () ->
    Result.bind (match uv_attribute with
      | Some name when String.trim name = "" ->
          Error "Pdk.Ops.sweep: UV attribute name must not be empty"
      | None | Some _ -> Ok ()) (fun () ->
    Result.bind (collect_curves "backbone" backbone backbones) (fun backbone_curves ->
    Result.bind (collect_curves "cross-section" cross_section cross_sections)
      (fun profile_curves ->
    Result.bind (validate_selected_positions "backbone" backbone backbone_curves)
      (fun () ->
    Result.bind (validate_selected_positions "cross-section" cross_section
      profile_curves) (fun () ->
      Cancel.check_opt cancel;
      let attribute_result = if transform_attributes then
          Result.bind (point_float backbone "pscale") (fun pscale ->
          Result.bind (point_float3 backbone "scale") (fun scale_values ->
          Result.bind (point_float3 backbone "N") (fun normal ->
          Result.bind (point_float3 backbone "up") (fun up ->
          Result.map (fun orient -> pscale, scale_values, normal, up, orient)
            (point_float4 backbone "orient")))))
        else Ok (None, None, None, None, None) in
      Result.bind attribute_result
        (fun (pscale_values, scale_values, normal_values, up_values, orient_values) ->
      let backbone_topology = Geometry.topology backbone in
      let validation = match pscale_values with
        | None -> Ok () | Some values -> validate_selected_float ?cancel
            backbone_topology backbone_curves values "pscale" in
      Result.bind validation (fun () ->
      let validation = match scale_values with
        | None -> Ok () | Some values -> validate_selected_float3 ?cancel
            backbone_topology backbone_curves values "scale" in
      Result.bind validation (fun () ->
      let validation = match normal_values with
        | None -> Ok () | Some values -> validate_selected_float3 ?cancel
            backbone_topology backbone_curves values "N" in
      Result.bind validation (fun () ->
      let validation = match up_values with
        | None -> Ok () | Some values -> validate_selected_float3 ?cancel
            backbone_topology backbone_curves values "up" in
      Result.bind validation (fun () ->
      let validation = match orient_values with
        | None -> Ok () | Some values -> validate_selected_float4 ?cancel
            backbone_topology backbone_curves values "orient" in
      Result.bind validation (fun () ->
      Result.bind (build_frames ?cancel ~grain ~tangent_mode:tangent
        ~continuous_closed ~roll ~twist ~normal_values ~up_values ~orient_values
        backbone backbone_curves) (fun frames ->
      Result.bind (fill_parameters ?cancel ~grain cross_section profile_curves)
        (fun (_, _, _, profile_cumulative, profile_totals) ->
      let pair_count_result = checked_product "Pdk.Ops.sweep"
          (Array.length backbone_curves) (Array.length profile_curves) in
      Result.bind pair_count_result (fun pair_count ->
        let placeholder_curve =
          { primitive = 0; first = 0; count = 2; closed = false } in
        let pairs = Array.make pair_count { backbone = placeholder_curve;
          profile = placeholder_curve; point_first = 0 } in
        let point_cursor = ref 0 and failure = ref None in
        for pair_index = 0 to pair_count - 1 do
          let backbone_curve = backbone_curves.(pair_index / Array.length profile_curves)
          and profile_curve = profile_curves.(pair_index mod Array.length profile_curves) in
          pairs.(pair_index) <- { backbone = backbone_curve;
            profile = profile_curve; point_first = !point_cursor };
          if !failure = None then
            match checked_product "Pdk.Ops.sweep" backbone_curve.count
                profile_curve.count with
            | Error message -> failure := Some message
            | Ok points ->
                (match checked_add "Pdk.Ops.sweep" !point_cursor points with
                 | Error message -> failure := Some message
                 | Ok next -> point_cursor := next)
        done;
        match !failure with
        | Some message -> Error message
        | None ->
          let output_points = !point_cursor in
          let count_for_pair pair =
            let b = pair.backbone and p = pair.profile in
            let be = if b.closed then b.count else b.count - 1
            and pe = if p.closed then p.count else p.count - 1 in
            let eligible_caps = caps && (not b.closed) && p.closed in
            let cap_primitives = if eligible_caps then 2 else 0 in
            Result.bind (if eligible_caps then
                checked_product "Pdk.Ops.sweep" 2 p.count else Ok 0)
              (fun cap_vertices -> match connectivity with
            | Points -> Ok (0, 0)
            | Rows -> Result.map (fun vertices -> b.count, vertices)
                (checked_product "Pdk.Ops.sweep" b.count p.count)
            | Columns -> Result.map (fun vertices -> p.count, vertices)
                (checked_product "Pdk.Ops.sweep" b.count p.count)
            | Rows_and_columns ->
                Result.bind (checked_add "Pdk.Ops.sweep" b.count p.count)
                  (fun primitives ->
                Result.bind (checked_product "Pdk.Ops.sweep" b.count p.count)
                  (fun one_family -> Result.map (fun vertices -> primitives, vertices)
                    (checked_product "Pdk.Ops.sweep" one_family 2)))
            | Quads ->
                Result.bind (checked_product "Pdk.Ops.sweep" be pe) (fun cells ->
                Result.bind (checked_add "Pdk.Ops.sweep" cells cap_primitives)
                  (fun primitives ->
                Result.bind (checked_product "Pdk.Ops.sweep" cells 4)
                  (fun side_vertices -> Result.map (fun vertices ->
                    primitives, vertices)
                    (checked_add "Pdk.Ops.sweep" side_vertices cap_vertices))))
            | Triangles | Alternating_triangles | Reverse_triangles ->
                Result.bind (checked_product "Pdk.Ops.sweep" be pe) (fun cells ->
                Result.bind (checked_product "Pdk.Ops.sweep" cells 2)
                  (fun side_primitives ->
                Result.bind (checked_add "Pdk.Ops.sweep" side_primitives
                  cap_primitives) (fun primitives ->
                Result.bind (checked_product "Pdk.Ops.sweep" cells 6)
                  (fun side_vertices -> Result.map (fun vertices ->
                    primitives, vertices)
                    (checked_add "Pdk.Ops.sweep" side_vertices cap_vertices)))))) in
          let primitive_count = ref 0 and vertex_count = ref 0 in
          Array.iter (fun pair ->
            if !failure = None then begin
              match count_for_pair pair with
              | Error message -> failure := Some message
              | Ok (primitives, vertices) ->
                  (match checked_add "Pdk.Ops.sweep" !primitive_count primitives with
                   | Error message -> failure := Some message
                   | Ok value -> primitive_count := value);
                  (match checked_add "Pdk.Ops.sweep" !vertex_count vertices with
                   | Error message -> failure := Some message
                   | Ok value -> vertex_count := value)
            end) pairs;
          (match !failure with
           | Some message -> Error message
           | None ->
             let output_primitives = !primitive_count
             and output_vertices = !vertex_count in
             let skip_backbone attribute =
               let owner = Attribute.owner attribute
               and name = Attribute.name attribute in
               ((owner = Attribute.Point || owner = Attribute.Vertex)
                  && String.equal name "N")
               || match uv_attribute with
                  | Some uv_name -> String.equal name uv_name
                      && (owner = Attribute.Point || owner = Attribute.Vertex)
                  | None -> false in
             let skip_profile attribute = match uv_attribute with
               | Some uv_name -> String.equal
                   (cross_section_prefix ^ Attribute.name attribute) uv_name
                   && (Attribute.owner attribute = Attribute.Point
                       || Attribute.owner attribute = Attribute.Vertex)
               | None -> false in
             let has_attribute geometry owner keep =
               List.exists (fun attribute -> Attribute.owner attribute = owner
                   && keep attribute) (Geometry.attributes geometry) in
             let has_group geometry owner =
               List.exists (fun group -> Group.owner group = owner)
                 (Geometry.groups geometry) in
             let has_backbone_edges = Geometry.edge_groups backbone <> []
             and has_profile_edges = Geometry.edge_groups cross_section <> [] in
             let need_edge_maps = has_backbone_edges || has_profile_edges in
             let need_backbone_point_map = need_edge_maps
                 || has_attribute backbone Attribute.Point
                      (fun attribute -> not (skip_backbone attribute))
                 || has_group backbone Group.Point
             and need_profile_point_map = need_edge_maps
                 || has_attribute cross_section Attribute.Point
                      (fun attribute -> not (skip_profile attribute))
                 || has_group cross_section Group.Point
             and need_backbone_vertex_map =
               has_attribute backbone Attribute.Vertex
                 (fun attribute -> not (skip_backbone attribute))
               || has_group backbone Group.Vertex
             and need_profile_vertex_map =
               has_attribute cross_section Attribute.Vertex
                 (fun attribute -> not (skip_profile attribute))
               || has_group cross_section Group.Vertex
             and need_backbone_primitive_map =
               has_attribute backbone Attribute.Primitive (fun _ -> true)
               || has_group backbone Group.Primitive
             and need_profile_primitive_map =
               has_attribute cross_section Attribute.Primitive (fun _ -> true)
               || has_group cross_section Group.Primitive in
             let px = Array.make output_points 0. and py = Array.make output_points 0.
             and pz = Array.make output_points 0.
             and backbone_point_map = if need_backbone_point_map
               then Array.make output_points 0 else [||]
             and profile_point_map = if need_profile_point_map
               then Array.make output_points 0 else [||]
             and invalid_points = Bytes.make output_points '\000' in
             let point_uvx, point_uvy = match uv_attribute, connectivity with
               | Some _, Points -> Array.make output_points 0., Array.make output_points 0.
               | None, _ | Some _, _ -> [||], [||] in
             let backbone_topology = Geometry.topology backbone
             and backbone_positions = Packed.Float3.Private.view
                 (Geometry.positions backbone)
             and profile_topology = Geometry.topology cross_section
             and profile_positions = Packed.Float3.Private.view
                 (Geometry.positions cross_section) in
             parallel_ranges ?cancel ~grain output_points (fun ~first ~last ->
               let pair_index = ref (find_pair pairs first) in
               for output = first to last - 1 do
                 while !pair_index + 1 < pair_count
                     && pairs.(!pair_index + 1).point_first <= output do
                   incr pair_index
                 done;
                 let pair = pairs.(!pair_index) in
                 let local = output - pair.point_first in
                 let backbone_local = local / pair.profile.count
                 and profile_local = local mod pair.profile.count in
                 let backbone_vertex = pair.backbone.first + backbone_local
                 and profile_source_local = profile_source_local
                     reverse_cross_sections pair.profile.count profile_local in
                 let profile_vertex = pair.profile.first + profile_source_local in
                 let backbone_point = Topology.point_of_vertex backbone_topology
                     backbone_vertex
                 and profile_point = Topology.point_of_vertex profile_topology
                     profile_vertex in
                 let uniform = scale *. match pscale_values with
                   | None -> 1. | Some values -> values.(backbone_point) in
                 let sx = uniform *. match scale_values with
                   | None -> 1. | Some values -> values.x.(backbone_point)
                 and sy = uniform *. match scale_values with
                   | None -> 1. | Some values -> values.y.(backbone_point)
                 and sz = uniform *. match scale_values with
                   | None -> 1. | Some values -> values.z.(backbone_point) in
                 let lx = profile_positions.x.(profile_point) *. sx
                 and ly = profile_positions.y.(profile_point) *. sy
                 and lz = profile_positions.z.(profile_point) *. sz in
                 let x = backbone_positions.x.(backbone_point)
                     +. (lx *. frames.out_x.(backbone_vertex))
                     +. (ly *. frames.up_x.(backbone_vertex))
                     +. (lz *. frames.tangent_x.(backbone_vertex))
                 and y = backbone_positions.y.(backbone_point)
                     +. (lx *. frames.out_y.(backbone_vertex))
                     +. (ly *. frames.up_y.(backbone_vertex))
                     +. (lz *. frames.tangent_y.(backbone_vertex))
                 and z = backbone_positions.z.(backbone_point)
                     +. (lx *. frames.out_z.(backbone_vertex))
                     +. (ly *. frames.up_z.(backbone_vertex))
                     +. (lz *. frames.tangent_z.(backbone_vertex)) in
                 if finite x && finite y && finite z then begin
                   px.(output) <- x; py.(output) <- y; pz.(output) <- z
                 end else Bytes.set invalid_points output '\001';
                 if need_backbone_point_map then
                   backbone_point_map.(output) <- backbone_point;
                 if need_profile_point_map then
                   profile_point_map.(output) <- profile_point;
                 if Array.length point_uvx > 0 then begin
                   point_uvx.(output) <- profile_parameter reverse_cross_sections
                       profile_cumulative profile_totals pair.profile profile_local;
                   point_uvy.(output) <- frames.cumulative.(backbone_vertex)
                       /. frames.totals.(pair.backbone.primitive)
                 end
               done);
             let invalid = ref 0 in
             while !invalid < output_points
                 && Bytes.get invalid_points !invalid = '\000' do incr invalid done;
             if !invalid < output_points then Error (Printf.sprintf
                 "Pdk.Ops.sweep: generated point %d is not finite" !invalid)
             else
               let primitive_offsets = Array.make (output_primitives + 1) 0
               and primitive_kinds = Bytes.make output_primitives '\000'
               and pair_primitive_first = Array.make (pair_count + 1) 0
               and backbone_primitive_map = if need_backbone_primitive_map
                 then Array.make output_primitives 0 else [||]
               and profile_primitive_map = if need_profile_primitive_map
                 then Array.make output_primitives 0 else [||] in
               let primitive_at = ref 0 and vertex_at = ref 0 in
               let emit pair_index size kind =
                 primitive_offsets.(!primitive_at) <- !vertex_at;
                 Bytes.set primitive_kinds !primitive_at kind;
                 if need_backbone_primitive_map then
                   backbone_primitive_map.(!primitive_at) <-
                     pairs.(pair_index).backbone.primitive;
                 if need_profile_primitive_map then
                   profile_primitive_map.(!primitive_at) <-
                     pairs.(pair_index).profile.primitive;
                 vertex_at := !vertex_at + size;
                 incr primitive_at in
               Array.iteri (fun pair_index pair ->
                 pair_primitive_first.(pair_index) <- !primitive_at;
                 let b = pair.backbone and p = pair.profile in
                 let be = if b.closed then b.count else b.count - 1
                 and pe = if p.closed then p.count else p.count - 1 in
                 (match connectivity with
                  | Points -> ()
                  | Rows ->
                      for _ = 0 to b.count - 1 do
                        emit pair_index p.count (if p.closed then '\002' else '\001')
                      done
                  | Columns ->
                      for _ = 0 to p.count - 1 do
                        emit pair_index b.count (if b.closed then '\002' else '\001')
                      done
                  | Rows_and_columns ->
                      for _ = 0 to b.count - 1 do
                        emit pair_index p.count (if p.closed then '\002' else '\001')
                      done;
                      for _ = 0 to p.count - 1 do
                        emit pair_index b.count (if b.closed then '\002' else '\001')
                      done
                  | Quads ->
                      for _ = 0 to (be * pe) - 1 do
                        emit pair_index 4 '\000'
                      done
                  | Triangles | Alternating_triangles | Reverse_triangles ->
                      for _ = 0 to (be * pe) - 1 do
                        emit pair_index 3 '\000';
                        emit pair_index 3 '\000'
                      done);
                 if caps && not b.closed && p.closed then begin
                   emit pair_index p.count '\000';
                   emit pair_index p.count '\000'
                 end;
                 pair_primitive_first.(pair_index + 1) <- !primitive_at) pairs;
               primitive_offsets.(output_primitives) <- output_vertices;
               let vertex_points = Array.make output_vertices 0
               and backbone_vertex_map = if need_backbone_vertex_map
                 then Array.make output_vertices 0 else [||]
               and profile_vertex_map = if need_profile_vertex_map
                 then Array.make output_vertices 0 else [||] in
               let uvx, uvy = match uv_attribute, connectivity with
                 | Some _, (Rows | Columns | Rows_and_columns | Quads | Triangles
                     | Alternating_triangles | Reverse_triangles) ->
                     Array.make output_vertices 0., Array.make output_vertices 0.
                 | None, _ | Some _, Points -> [||], [||] in
               let backbone_u pair local ~wrapped =
                 if wrapped then 1.
                 else frames.cumulative.(pair.backbone.first + local)
                     /. frames.totals.(pair.backbone.primitive) in
               let profile_u pair local ~wrapped =
                 if wrapped then 1.
                 else profile_parameter reverse_cross_sections profile_cumulative
                     profile_totals pair.profile local in
               let write_vertex at pair b_local p_local ~u ~v =
                 vertex_points.(at) <- pair.point_first
                     + (b_local * pair.profile.count) + p_local;
                 if need_backbone_vertex_map then
                   backbone_vertex_map.(at) <- pair.backbone.first + b_local;
                 if need_profile_vertex_map then
                   profile_vertex_map.(at) <- pair.profile.first
                       + profile_source_local reverse_cross_sections
                           pair.profile.count p_local;
                 if Array.length uvx > 0 then begin uvx.(at) <- u; uvy.(at) <- v end in
               let fill_primitive primitive pair code local =
                 let at = primitive_offsets.(primitive) in
                 let b = pair.backbone and p = pair.profile in
                 let pe = if p.closed then p.count else p.count - 1 in
                 match code with
                 | '\001' ->
                     for p_local = 0 to p.count - 1 do
                       write_vertex (at + p_local) pair local p_local
                         ~u:(profile_u pair p_local ~wrapped:false)
                         ~v:(backbone_u pair local ~wrapped:false)
                     done
                 | '\002' ->
                     for b_local = 0 to b.count - 1 do
                       write_vertex (at + b_local) pair b_local local
                         ~u:(profile_u pair local ~wrapped:false)
                         ~v:(backbone_u pair b_local ~wrapped:false)
                     done
                 | ('\003' | '\004' | '\005' | '\006' | '\007') as code ->
                     let b0 = local / pe and p0 = local mod pe in
                     let b1 = (b0 + 1) mod b.count
                     and p1 = (p0 + 1) mod p.count in
                     let u0 = profile_u pair p0 ~wrapped:false
                     and u1 = profile_u pair p1 ~wrapped:(p1 = 0)
                     and v0 = backbone_u pair b0 ~wrapped:false
                     and v1 = backbone_u pair b1 ~wrapped:(b1 = 0) in
                     (match code with
                      | '\003' ->
                          write_vertex at pair b0 p0 ~u:u0 ~v:v0;
                          write_vertex (at + 1) pair b0 p1 ~u:u1 ~v:v0;
                          write_vertex (at + 2) pair b1 p1 ~u:u1 ~v:v1;
                          write_vertex (at + 3) pair b1 p0 ~u:u0 ~v:v1
                      | '\004' ->
                          write_vertex at pair b0 p0 ~u:u0 ~v:v0;
                          write_vertex (at + 1) pair b0 p1 ~u:u1 ~v:v0;
                          write_vertex (at + 2) pair b1 p1 ~u:u1 ~v:v1
                      | '\006' ->
                          write_vertex at pair b0 p0 ~u:u0 ~v:v0;
                          write_vertex (at + 1) pair b1 p1 ~u:u1 ~v:v1;
                          write_vertex (at + 2) pair b1 p0 ~u:u0 ~v:v1
                      | '\005' ->
                          write_vertex at pair b0 p0 ~u:u0 ~v:v0;
                          write_vertex (at + 1) pair b0 p1 ~u:u1 ~v:v0;
                          write_vertex (at + 2) pair b1 p0 ~u:u0 ~v:v1
                      | '\007' ->
                          write_vertex at pair b0 p1 ~u:u1 ~v:v0;
                          write_vertex (at + 1) pair b1 p1 ~u:u1 ~v:v1;
                          write_vertex (at + 2) pair b1 p0 ~u:u0 ~v:v1
                      | _ -> assert false)
                 | '\008' | '\009' as code ->
                     let b_local = if code = '\008' then 0 else b.count - 1 in
                     for cap_local = 0 to p.count - 1 do
                       let p_local = if code = '\008' then p.count - 1 - cap_local
                         else cap_local in
                       write_vertex (at + cap_local) pair b_local p_local
                         ~u:(profile_u pair p_local ~wrapped:false)
                         ~v:(backbone_u pair b_local ~wrapped:false)
                     done
                 | _ -> assert false in
               let side_primitive_count pair =
                 let b = pair.backbone and p = pair.profile in
                 let be = if b.closed then b.count else b.count - 1
                 and pe = if p.closed then p.count else p.count - 1 in
                 match connectivity with
                 | Points -> 0
                 | Rows -> b.count
                 | Columns -> p.count
                 | Rows_and_columns -> b.count + p.count
                 | Quads -> be * pe
                 | Triangles | Alternating_triangles | Reverse_triangles ->
                     be * pe * 2 in
               let fill_surface_primitives () =
                 parallel_ranges ?cancel ~grain output_primitives
                   (fun ~first ~last ->
                   let pair_index = ref (find_prefix pair_primitive_first first) in
                   for primitive = first to last - 1 do
                     while !pair_index + 1 < pair_count
                         && pair_primitive_first.(!pair_index + 1) <= primitive do
                       incr pair_index
                     done;
                     let pair = pairs.(!pair_index) in
                     let within = primitive - pair_primitive_first.(!pair_index) in
                     let b = pair.backbone and p = pair.profile in
                     let pe = if p.closed then p.count else p.count - 1 in
                     (match connectivity with
                      | Points -> assert false
                      | Rows -> fill_primitive primitive pair '\001' within
                      | Columns -> fill_primitive primitive pair '\002' within
                      | Rows_and_columns ->
                          if within < b.count then
                            fill_primitive primitive pair '\001' within
                          else fill_primitive primitive pair '\002'
                              (within - b.count)
                      | Quads ->
                          let cells = (if b.closed then b.count else b.count - 1)
                              * pe in
                          if within < cells then
                            fill_primitive primitive pair '\003' within
                          else fill_primitive primitive pair
                              (if within = cells then '\008' else '\009') 0
                      | Triangles | Alternating_triangles | Reverse_triangles ->
                          let cells = (if b.closed then b.count else b.count - 1)
                              * pe in
                          let sides = cells * 2 in
                          if within < sides then begin
                            let cell = within lsr 1 and half = within land 1 in
                            let reverse = connectivity = Reverse_triangles
                                || (connectivity = Alternating_triangles
                                    && (((cell / pe) + (cell mod pe)) land 1 = 1)) in
                            let code = if reverse then
                                if half = 0 then '\005' else '\007'
                              else if half = 0 then '\004' else '\006' in
                            fill_primitive primitive pair code cell
                          end else fill_primitive primitive pair
                              (if within = sides then '\008' else '\009') 0)
                   done) in
               let fill_curve_vertices () =
                 (* A row or column can itself contain millions of vertices.
                    Split its packed vertex plane, rather than limiting
                    parallelism to the much smaller primitive count. *)
                 let pair_vertex_first = Array.init (pair_count + 1)
                     (fun pair_index ->
                       primitive_offsets.(pair_primitive_first.(pair_index))) in
                 parallel_ranges ?cancel ~grain output_vertices
                   (fun ~first ~last ->
                     let pair_index = ref (find_prefix pair_vertex_first first) in
                     for at = first to last - 1 do
                       while !pair_index + 1 < pair_count
                           && pair_vertex_first.(!pair_index + 1) <= at do
                         incr pair_index
                       done;
                       let pair = pairs.(!pair_index) in
                       let within = at - pair_vertex_first.(!pair_index) in
                       let plane = pair.backbone.count * pair.profile.count in
                       let within, columns = match connectivity with
                         | Rows -> within, false
                         | Columns -> within, true
                         | Rows_and_columns ->
                             if within < plane then within, false
                             else within - plane, true
                         | _ -> assert false in
                       let b_local, p_local = if columns then
                           within mod pair.backbone.count,
                           within / pair.backbone.count
                         else within / pair.profile.count,
                           within mod pair.profile.count in
                       write_vertex at pair b_local p_local
                         ~u:(profile_u pair p_local ~wrapped:false)
                         ~v:(backbone_u pair b_local ~wrapped:false)
                     done) in
               (match connectivity with
                | Rows | Columns | Rows_and_columns -> fill_curve_vertices ()
                | Points -> ()
                | Quads | Triangles | Alternating_triangles
                | Reverse_triangles -> fill_surface_primitives ());
               let output_topology = Topology.Private.create_validated_owned
                   ~point_count:output_points ~vertex_points ~primitive_offsets
                   ~primitive_kinds in
               Result.bind (remap_attributes ?cancel ~grain ~prefix:""
                 ~skip:skip_backbone backbone_point_map backbone_vertex_map
                 backbone_primitive_map (Geometry.attributes backbone))
                 (fun backbone_attributes ->
               Result.bind (remap_attributes ?cancel ~grain
                 ~prefix:cross_section_prefix ~skip:skip_profile profile_point_map
                 profile_vertex_map profile_primitive_map
                 (Geometry.attributes cross_section)) (fun profile_attributes ->
               let uv_attributes = match uv_attribute with
                 | None -> []
                 | Some name when connectivity = Points ->
                     [Attribute.create_owned ~name ~owner:Attribute.Point
                        (Attribute.Float2 (Packed.Float2.of_owned
                          ~x:point_uvx ~y:point_uvy |> Result.get_ok))
                      |> Result.get_ok]
                 | Some name ->
                     [Attribute.create_owned ~name ~owner:Attribute.Vertex
                        (Attribute.Float2 (Packed.Float2.of_owned ~x:uvx ~y:uvy
                          |> Result.get_ok)) |> Result.get_ok] in
               let backbone_groups = List.map
                   (remap_group ?cancel ~grain ~prefix:"" backbone_point_map
                      backbone_vertex_map backbone_primitive_map)
                   (Geometry.groups backbone)
               and profile_groups = List.map
                   (remap_group ?cancel ~grain ~prefix:cross_section_prefix
                      profile_point_map profile_vertex_map profile_primitive_map)
                   (Geometry.groups cross_section) in
               let cap_groups = match cap_group with
                 | None -> []
                 | Some name -> [Group.init ~grain ~owner:Group.Primitive ~name
                     output_primitives (fun primitive ->
                       let pair_index = find_prefix pair_primitive_first primitive in
                       let pair = pairs.(pair_index) in
                       caps && not pair.backbone.closed && pair.profile.closed
                       && primitive - pair_primitive_first.(pair_index)
                          >= side_primitive_count pair)] in
               let target_index = lazy (Topology_index.create ?cancel output_topology)
               and backbone_index = lazy (Topology_index.create ?cancel
                   backbone_topology)
               and profile_index = lazy (Topology_index.create ?cancel
                   profile_topology) in
               let remap_edge source_index source_group ~profile ~name =
                 let target_index = Lazy.force target_index in
                 let target_view = Topology_index.Private.view target_index in
                 Edge_group.init ~grain ~topology:output_topology
                   ~index:target_index ~name (fun edge ->
                     let a = target_view.edge_a.(edge)
                     and b = target_view.edge_b.(edge) in
                     if profile then begin
                       if backbone_point_map.(a) <> backbone_point_map.(b) then false
                       else
                         let source_edge = Topology_index.find_edge_index source_index
                             ~a:profile_point_map.(a) ~b:profile_point_map.(b) in
                         source_edge >= 0
                         && Edge_group.mem source_edge source_group
                     end else begin
                       if profile_point_map.(a) <> profile_point_map.(b) then false
                       else
                         let source_edge = Topology_index.find_edge_index source_index
                             ~a:backbone_point_map.(a) ~b:backbone_point_map.(b) in
                         source_edge >= 0
                         && Edge_group.mem source_edge source_group
                     end) in
               let backbone_edge_groups = match Geometry.edge_groups backbone with
                 | [] -> []
                 | groups -> let index = Lazy.force backbone_index in
                     List.map (fun group -> remap_edge index group ~profile:false
                       ~name:(Edge_group.name group)) groups
               and profile_edge_groups = match Geometry.edge_groups cross_section with
                 | [] -> []
                 | groups -> let index = Lazy.force profile_index in
                     List.map (fun group -> remap_edge index group ~profile:true
                       ~name:(cross_section_prefix ^ Edge_group.name group)) groups in
               Geometry.create
                 ~positions:(Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz)
                 ~topology:output_topology
                 ~attributes:(backbone_attributes @ profile_attributes @ uv_attributes)
                 ~groups:(backbone_groups @ profile_groups @ cap_groups)
                 ~edge_groups:(backbone_edge_groups @ profile_edge_groups) ()))))))))))))))))))
