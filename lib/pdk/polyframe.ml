open Prismel

type style =
  | First_edge
  | Two_edges
  | Primitive_centroid
  | Texture_uv of string
  | Texture_uv_gradient of string
  | Attribute_gradient of string

type planes = {
  x : float array;
  y : float array;
  z : float array;
}

type scalar2 = {
  owner : Attribute.owner;
  u : float array;
  v : float array;
}

let[@inline always] finite value = Float.is_finite value

let owner_name = function
  | Attribute.Point -> "point"
  | Attribute.Vertex -> "vertex"
  | Attribute.Primitive -> "primitive"
  | Attribute.Detail -> "detail"

let[@inline] max_abs3 x y z =
  let x = abs_float x and y = abs_float y and z = abs_float z in
  if x >= y then if x >= z then x else z else if y >= z then y else z

let output_owner = function
  | First_edge | Two_edges | Primitive_centroid | Texture_uv _ -> Attribute.Point
  | Texture_uv_gradient _ | Attribute_gradient _ -> Attribute.Vertex

let texture_attribute_name name =
  if String.trim name = "" then "uv" else name

let validate_name label = function
  | None -> Ok ()
  | Some name when String.trim name = "" ->
      Error (label ^ " attribute name must not be empty")
  | Some "P" -> Error (label ^ " attribute cannot replace canonical P")
  | Some _ -> Ok ()

let validate_names ~normal_attribute ~tangent_attribute ~bitangent_attribute =
  let values = [Some normal_attribute; tangent_attribute; bitangent_attribute] in
  let rec loop = function
    | [] -> Ok ()
    | value :: rest ->
        Result.bind (validate_name "output" value) (fun () -> loop rest) in
  Result.bind (loop values) (fun () ->
    let names = List.filter_map Fun.id values |> List.sort String.compare in
    let rec duplicate = function
      | left :: (right :: _ as rest) ->
          if String.equal left right then Some left else duplicate rest
      | _ -> None in
    match duplicate names with
    | None -> Ok ()
    | Some name -> Error (Printf.sprintf
        "output attribute name %S is used more than once" name))

let existing_planes ~owner ~count name geometry =
  match Geometry.find_attribute ~owner name geometry with
  | None -> Ok { x = Array.make count 0.; y = Array.make count 0.;
      z = Array.make count 0. }
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values ->
           let values = Packed.Float3.Private.view values in
           Ok { x = Array.copy values.x; y = Array.copy values.y;
             z = Array.copy values.z }
       | _ -> Error (Printf.sprintf
           "existing %s attribute %S must have float3 storage"
           (owner_name owner) name))

let scalar2_attribute name geometry =
  let find owner =
    match Geometry.find_attribute ~owner name geometry with
    | None -> None
    | Some attribute ->
        match Attribute.Private.storage attribute with
        | Attribute.Float2 values ->
            let values = Packed.Float2.Private.view values in
            Some (Ok { owner; u = values.x; v = values.y })
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            Some (Ok { owner; u = values.x; v = values.y })
        | _ -> Some (Error (Printf.sprintf
            "%s attribute %S must have float2 or float3 storage"
            (owner_name owner) name)) in
  match find Attribute.Vertex with
  | Some result -> result
  | None ->
      (match find Attribute.Point with
       | Some result -> result
       | None -> Error (Printf.sprintf
           "point or vertex gradient attribute %S does not exist" name))

let validate_scalar2 values =
  let invalid = ref (-1) in
  let index = ref 0 in
  while !invalid < 0 && !index < Array.length values.u do
    if not (finite values.u.(!index) && finite values.v.(!index)) then
      invalid := !index;
    incr index
  done;
  if !invalid < 0 then Ok () else Error (Printf.sprintf
      "%s gradient attribute contains a non-finite value at element %d"
      (owner_name values.owner) !invalid)

let[@inline] selected_vertex selection (topology : Topology.Private.view)
    (view : Topology_index.Private.view) vertex = match selection with
  | None -> true
  | Some (Deform.Selected_points group) ->
      Group.mem topology.Topology.Private.vertex_points.(vertex) group
  | Some (Deform.Selected_vertices group) -> Group.mem vertex group
  | Some (Deform.Selected_primitives group) ->
      Group.mem view.primitive_of_vertex.(vertex) group
  | Some (Deform.Selected_edges group) ->
      let outgoing = view.edge_of_vertex.(vertex)
      and previous = view.previous_vertex.(vertex) in
      (outgoing >= 0 && Edge_group.mem outgoing group)
      || (previous >= 0 && view.edge_of_vertex.(previous) >= 0
          && Edge_group.mem view.edge_of_vertex.(previous) group)

let normalize_selected ~orthogonal ~left_handed ~normal ~tangent ~bitangent ~selected
    ~count ~grain ?cancel () =
  let ranges = if count = 0 then 0 else (count + grain - 1) / grain in
  let failures = Bytes.make ranges '\000' in
  if ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(ranges - 1)
      (fun range ->
    let first = range * grain and last = min count ((range + 1) * grain) in
    for element = first to last - 1 do
      if element land 4095 = 0 then Cancel.check_opt cancel;
      if selected element then begin
        let nx = normal.x.(element) and ny = normal.y.(element)
        and nz = normal.z.(element) in
        let nscale = max_abs3 nx ny nz in
        let nsx = if nscale = 0. then 0. else nx /. nscale
        and nsy = if nscale = 0. then 0. else ny /. nscale
        and nsz = if nscale = 0. then 0. else nz /. nscale in
        let nlength = sqrt ((nsx *. nsx) +. (nsy *. nsy) +. (nsz *. nsz)) in
        let nx = if nscale = 0. then 0. else nsx /. nlength
        and ny = if nscale = 0. then 0. else nsy /. nlength
        and nz = if nscale = 0. then 0. else nsz /. nlength in
        normal.x.(element) <- nx; normal.y.(element) <- ny;
        normal.z.(element) <- nz;
        (match tangent with
         | None -> ()
         | Some tangent ->
             let tx = tangent.x.(element) and ty = tangent.y.(element)
             and tz = tangent.z.(element) in
             let projection = if orthogonal && nscale > 0.
               then (tx *. nx) +. (ty *. ny) +. (tz *. nz) else 0. in
             let tx = tx -. (projection *. nx)
             and ty = ty -. (projection *. ny)
             and tz = tz -. (projection *. nz) in
             let tscale = max_abs3 tx ty tz in
             let tsx = if tscale = 0. then 0. else tx /. tscale
             and tsy = if tscale = 0. then 0. else ty /. tscale
             and tsz = if tscale = 0. then 0. else tz /. tscale in
             let tlength = sqrt ((tsx *. tsx) +. (tsy *. tsy) +. (tsz *. tsz)) in
             let tx = if tscale = 0. then 0. else tsx /. tlength
             and ty = if tscale = 0. then 0. else tsy /. tlength
             and tz = if tscale = 0. then 0. else tsz /. tlength in
             tangent.x.(element) <- tx; tangent.y.(element) <- ty;
             tangent.z.(element) <- tz;
             (match bitangent with
              | None -> ()
              | Some bitangent when orthogonal && nscale > 0. && tscale > 0. ->
                  let bx = (ny *. tz) -. (nz *. ty)
                  and by = (nz *. tx) -. (nx *. tz)
                  and bz = (nx *. ty) -. (ny *. tx) in
                  let handedness = if left_handed then -1. else 1. in
                  bitangent.x.(element) <- handedness *. bx;
                  bitangent.y.(element) <- handedness *. by;
                  bitangent.z.(element) <- handedness *. bz
              | Some bitangent ->
                  let bx = bitangent.x.(element)
                  and by = bitangent.y.(element)
                  and bz = bitangent.z.(element) in
                  let bscale = max_abs3 bx by bz in
                  let bsx = if bscale = 0. then 0. else bx /. bscale
                  and bsy = if bscale = 0. then 0. else by /. bscale
                  and bsz = if bscale = 0. then 0. else bz /. bscale in
                  let blength = sqrt
                      ((bsx *. bsx) +. (bsy *. bsy) +. (bsz *. bsz)) in
                  bitangent.x.(element) <- if bscale = 0. then 0.
                    else bsx /. blength;
                  bitangent.y.(element) <- if bscale = 0. then 0.
                    else bsy /. blength;
                  bitangent.z.(element) <- if bscale = 0. then 0.
                    else bsz /. blength));
        if Bytes.get failures range = '\000'
            && not (finite normal.x.(element) && finite normal.y.(element)
              && finite normal.z.(element)
              && (match tangent with None -> true | Some value ->
                    finite value.x.(element) && finite value.y.(element)
                    && finite value.z.(element))
              && (match bitangent with None -> true | Some value ->
                    finite value.x.(element) && finite value.y.(element)
                    && finite value.z.(element))) then
          Bytes.set failures range '\001'
      end
    done);
  if Bytes.exists ((<>) '\000') failures then
    Error "frame normalization produced a non-finite vector" else Ok ()

let face_normals ?cancel ~grain geometry =
  Result.map (fun values ->
    { x = values.Deform.x; y = values.y; z = values.z })
    (Deform.face_vectors ?cancel ~grain geometry)

let point_normals ?cancel ~grain geometry =
  Result.map (fun values ->
    { x = values.Deform.x; y = values.y; z = values.z })
    (Deform.geometric_point_vectors ?cancel ~grain geometry)

let centroids ?cancel ~grain geometry =
  let topology = Topology.Private.view (Geometry.topology geometry)
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let count = Array.length topology.primitive_offsets - 1 in
  let values = { x = Array.make count 0.; y = Array.make count 0.;
    z = Array.make count 0. } in
  let failures = Bytes.make count '\000' in
  if count > 0 then Parallel.for_ ~chunk_size:(max 1 (grain / 8)) ~start:0
      ~finish:(count - 1) (fun primitive ->
    if primitive land 1023 = 0 then Cancel.check_opt cancel;
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1) in
    let corners = last - first in
    if corners <= 0 then Bytes.set failures primitive '\001'
    else begin
      let anchor = topology.vertex_points.(first) in
      let ax = positions.x.(anchor) and ay = positions.y.(anchor)
      and az = positions.z.(anchor) in
      for vertex = first + 1 to last - 1 do
        let point = topology.vertex_points.(vertex) in
        values.x.(primitive) <- values.x.(primitive)
          +. (positions.x.(point) -. ax);
        values.y.(primitive) <- values.y.(primitive)
          +. (positions.y.(point) -. ay);
        values.z.(primitive) <- values.z.(primitive)
          +. (positions.z.(point) -. az)
      done;
      let inverse = 1. /. float_of_int corners in
      values.x.(primitive) <- ax +. (values.x.(primitive) *. inverse);
      values.y.(primitive) <- ay +. (values.y.(primitive) *. inverse);
      values.z.(primitive) <- az +. (values.z.(primitive) *. inverse);
      if not (finite values.x.(primitive) && finite values.y.(primitive)
          && finite values.z.(primitive)) then
        Bytes.set failures primitive '\001'
    end);
  if Bytes.exists ((<>) '\000') failures then
    Error "primitive centroid is not finite" else Ok values

let point_style ?cancel ~grain ~selection ~orthogonal ~left_handed ~normal ~tangent
    ~bitangent style geometry =
  let topology_value = Geometry.topology geometry
  and topology = Topology.Private.view (Geometry.topology geometry)
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let index = Topology_index.create ?cancel topology_value in
  let view = Topology_index.Private.view index in
  Result.bind (point_normals ?cancel ~grain geometry) (fun geometric_normal ->
    let centroid_result = match style with
      | Primitive_centroid -> centroids ?cancel ~grain geometry
      | _ -> Ok { x = [||]; y = [||]; z = [||] } in
    Result.bind centroid_result (fun centroids ->
      let point_count = topology.point_count in
      let index_option = Some index in
      let selected point = Deform.point_selected selection index_option point in
      if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(point_count - 1) (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if selected point then begin
          normal.x.(point) <- geometric_normal.x.(point);
          normal.y.(point) <- geometric_normal.y.(point);
          normal.z.(point) <- geometric_normal.z.(point);
          let incidence = Topology_index.point_incidence_count index point in
          let corner = if incidence = 0 then -1
            else Topology_index.point_vertex index ~point ~local:0 in
          if corner >= 0 then begin
            let previous = view.previous_vertex.(corner)
            and next = view.next_vertex.(corner) in
            let px = positions.x.(point) and py = positions.y.(point)
            and pz = positions.z.(point) in
            let tx = match style with
              | First_edge ->
                  if next >= 0 then
                    let target = topology.vertex_points.(next) in
                    positions.x.(target) -. px
                  else if previous >= 0 then
                    let source = topology.vertex_points.(previous) in
                    px -. positions.x.(source)
                  else 0.
              | Two_edges ->
                  let before = if previous < 0 then point
                    else topology.vertex_points.(previous)
                  and after = if next < 0 then point
                    else topology.vertex_points.(next) in
                  (positions.x.(before) -. px) +. (positions.x.(after) -. px)
              | Primitive_centroid ->
                  let primitive = view.primitive_of_vertex.(corner) in
                  px -. centroids.x.(primitive)
              | Texture_uv _ | Texture_uv_gradient _ | Attribute_gradient _ ->
                  assert false in
            let ty = match style with
              | First_edge ->
                  if next >= 0 then
                    positions.y.(topology.vertex_points.(next)) -. py
                  else if previous >= 0 then
                    py -. positions.y.(topology.vertex_points.(previous))
                  else 0.
              | Two_edges ->
                  let before = if previous < 0 then point
                    else topology.vertex_points.(previous)
                  and after = if next < 0 then point
                    else topology.vertex_points.(next) in
                  (positions.y.(before) -. py) +. (positions.y.(after) -. py)
              | Primitive_centroid ->
                  py -. centroids.y.(view.primitive_of_vertex.(corner))
              | Texture_uv _ | Texture_uv_gradient _ | Attribute_gradient _ ->
                  assert false in
            let tz = match style with
              | First_edge ->
                  if next >= 0 then
                    positions.z.(topology.vertex_points.(next)) -. pz
                  else if previous >= 0 then
                    pz -. positions.z.(topology.vertex_points.(previous))
                  else 0.
              | Two_edges ->
                  let before = if previous < 0 then point
                    else topology.vertex_points.(previous)
                  and after = if next < 0 then point
                    else topology.vertex_points.(next) in
                  (positions.z.(before) -. pz) +. (positions.z.(after) -. pz)
              | Primitive_centroid ->
                  pz -. centroids.z.(view.primitive_of_vertex.(corner))
              | Texture_uv _ | Texture_uv_gradient _ | Attribute_gradient _ ->
                  assert false in
            (match tangent with
             | None -> ()
             | Some value ->
                 value.x.(point) <- tx; value.y.(point) <- ty;
                 value.z.(point) <- tz);
            (match bitangent with
             | None -> ()
             | Some value ->
              let nx = geometric_normal.x.(point)
              and ny = geometric_normal.y.(point)
              and nz = geometric_normal.z.(point) in
              value.x.(point) <- (ny *. tz) -. (nz *. ty);
              value.y.(point) <- (nz *. tx) -. (nx *. tz);
              value.z.(point) <- (nx *. ty) -. (ny *. tx))
          end
        end);
      normalize_selected ~orthogonal ~left_handed ~normal ~tangent ~bitangent
        ~selected
        ~count:point_count ~grain ?cancel ()))

let gradient_frames ?cancel ~grain ~selection ~compute_bitangent values geometry =
  let topology_value = Geometry.topology geometry
  and topology = Topology.Private.view (Geometry.topology geometry)
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let index = Topology_index.create ?cancel topology_value in
  let view = Topology_index.Private.view index in
  let vertex_count = Array.length topology.vertex_points in
  let tangent = { x = Array.make vertex_count 0.; y = Array.make vertex_count 0.;
    z = Array.make vertex_count 0. }
  and bitangent = if compute_bitangent then Some {
      x = Array.make vertex_count 0.; y = Array.make vertex_count 0.;
      z = Array.make vertex_count 0. }
    else None
  and failures = Bytes.make vertex_count '\000' in
  let point_values = values.owner = Attribute.Point in
  if vertex_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(vertex_count - 1) (fun vertex ->
    if vertex land 4095 = 0 then Cancel.check_opt cancel;
    let primitive = view.primitive_of_vertex.(vertex) in
    if Topology.primitive_kind topology_value primitive = Topology.Polygon
        && selected_vertex selection topology view vertex then begin
      let previous = view.previous_vertex.(vertex)
      and next = view.next_vertex.(vertex) in
      let point = topology.vertex_points.(vertex)
      and previous_point = topology.vertex_points.(previous)
      and next_point = topology.vertex_points.(next) in
      let value_index = if point_values then point else vertex
      and previous_value_index = if point_values then previous_point else previous
      and next_value_index = if point_values then next_point else next in
      let e1x = positions.x.(next_point) -. positions.x.(point)
      and e1y = positions.y.(next_point) -. positions.y.(point)
      and e1z = positions.z.(next_point) -. positions.z.(point)
      and e2x = positions.x.(previous_point) -. positions.x.(point)
      and e2y = positions.y.(previous_point) -. positions.y.(point)
      and e2z = positions.z.(previous_point) -. positions.z.(point)
      and du1 = values.u.(next_value_index) -. values.u.(value_index)
      and dv1 = values.v.(next_value_index) -. values.v.(value_index)
      and du2 = values.u.(previous_value_index) -. values.u.(value_index)
      and dv2 = values.v.(previous_value_index) -. values.v.(value_index) in
      let uv_scale =
        let a = abs_float du1 and b = abs_float dv1
        and c = abs_float du2 and d = abs_float dv2 in
        let ab = if a >= b then a else b
        and cd = if c >= d then c else d in
        if ab >= cd then ab else cd in
      let du1 = if uv_scale = 0. then 0. else du1 /. uv_scale
      and dv1 = if uv_scale = 0. then 0. else dv1 /. uv_scale
      and du2 = if uv_scale = 0. then 0. else du2 /. uv_scale
      and dv2 = if uv_scale = 0. then 0. else dv2 /. uv_scale in
      let determinant = (du1 *. dv2) -. (du2 *. dv1) in
      if abs_float determinant > 1e-15 then begin
        tangent.x.(vertex) <- ((dv2 *. e1x) -. (dv1 *. e2x)) /. determinant;
        tangent.y.(vertex) <- ((dv2 *. e1y) -. (dv1 *. e2y)) /. determinant;
        tangent.z.(vertex) <- ((dv2 *. e1z) -. (dv1 *. e2z)) /. determinant;
        (match bitangent with
         | None -> ()
         | Some bitangent ->
             bitangent.x.(vertex) <-
               ((du1 *. e2x) -. (du2 *. e1x)) /. determinant;
             bitangent.y.(vertex) <-
               ((du1 *. e2y) -. (du2 *. e1y)) /. determinant;
             bitangent.z.(vertex) <-
               ((du1 *. e2z) -. (du2 *. e1z)) /. determinant);
        if not (finite tangent.x.(vertex) && finite tangent.y.(vertex)
            && finite tangent.z.(vertex)
            && (match bitangent with None -> true | Some bitangent ->
                  finite bitangent.x.(vertex) && finite bitangent.y.(vertex)
                  && finite bitangent.z.(vertex))) then
          Bytes.set failures vertex '\001'
      end
    end);
  if Bytes.exists ((<>) '\000') failures then
    Error "attribute-gradient frame is not finite"
  else Ok (index, view, tangent, bitangent)

let vertex_gradient ?cancel ~grain ~selection ~orthogonal ~left_handed ~normal
    ~tangent ~bitangent values geometry =
  Result.bind (face_normals ?cancel ~grain geometry) (fun faces ->
    let compute_bitangent = not orthogonal && Option.is_some bitangent in
    Result.bind (gradient_frames ?cancel ~grain ~selection ~compute_bitangent
        values geometry)
      (fun (_index, view, raw_tangent, raw_bitangent) ->
    let topology = Topology.Private.view (Geometry.topology geometry) in
    let count = Array.length topology.vertex_points in
    let selected vertex = selected_vertex selection topology view vertex in
    if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
        (fun vertex ->
      if selected vertex then begin
        let primitive = view.primitive_of_vertex.(vertex) in
        normal.x.(vertex) <- faces.x.(primitive);
        normal.y.(vertex) <- faces.y.(primitive);
        normal.z.(vertex) <- faces.z.(primitive);
        (match tangent with
         | None -> ()
         | Some value ->
             value.x.(vertex) <- raw_tangent.x.(vertex);
             value.y.(vertex) <- raw_tangent.y.(vertex);
             value.z.(vertex) <- raw_tangent.z.(vertex));
        (match bitangent, raw_bitangent with
         | Some value, Some raw ->
             value.x.(vertex) <- raw.x.(vertex);
             value.y.(vertex) <- raw.y.(vertex);
             value.z.(vertex) <- raw.z.(vertex)
         | Some value, None ->
             value.x.(vertex) <- 0.; value.y.(vertex) <- 0.;
             value.z.(vertex) <- 0.
         | _ -> ())
      end);
    normalize_selected ~orthogonal ~left_handed ~normal ~tangent ~bitangent
      ~selected ~count ~grain ?cancel ()))

let point_texture ?cancel ~grain ~selection ~orthogonal ~left_handed ~normal
    ~tangent ~bitangent values geometry =
  Result.bind (point_normals ?cancel ~grain geometry) (fun geometric_normal ->
    let compute_bitangent = not orthogonal && Option.is_some bitangent in
    Result.bind (gradient_frames ?cancel ~grain ~selection:None
        ~compute_bitangent values geometry)
      (fun (index, _view, vertex_tangent, vertex_bitangent) ->
    let point_count = Geometry.point_count geometry in
    let index_option = Some index in
    let selected point = Deform.point_selected selection index_option point in
    if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
        ~finish:(point_count - 1) (fun point ->
      if selected point then begin
        normal.x.(point) <- geometric_normal.x.(point);
        normal.y.(point) <- geometric_normal.y.(point);
        normal.z.(point) <- geometric_normal.z.(point);
        let incidence = Topology_index.point_incidence_count index point in
        (match tangent, bitangent, vertex_bitangent with
         | Some tangent, Some bitangent, Some vertex_bitangent ->
             tangent.x.(point) <- 0.; tangent.y.(point) <- 0.;
             tangent.z.(point) <- 0.; bitangent.x.(point) <- 0.;
             bitangent.y.(point) <- 0.; bitangent.z.(point) <- 0.;
             for local = 0 to incidence - 1 do
               let vertex = Topology_index.point_vertex index ~point ~local in
               tangent.x.(point) <- tangent.x.(point)
                 +. vertex_tangent.x.(vertex);
               tangent.y.(point) <- tangent.y.(point)
                 +. vertex_tangent.y.(vertex);
               tangent.z.(point) <- tangent.z.(point)
                 +. vertex_tangent.z.(vertex);
               bitangent.x.(point) <- bitangent.x.(point)
                 +. vertex_bitangent.x.(vertex);
               bitangent.y.(point) <- bitangent.y.(point)
                 +. vertex_bitangent.y.(vertex);
               bitangent.z.(point) <- bitangent.z.(point)
                 +. vertex_bitangent.z.(vertex)
             done
         | Some tangent, Some bitangent, None ->
             tangent.x.(point) <- 0.; tangent.y.(point) <- 0.;
             tangent.z.(point) <- 0.; bitangent.x.(point) <- 0.;
             bitangent.y.(point) <- 0.; bitangent.z.(point) <- 0.;
             for local = 0 to incidence - 1 do
               let vertex = Topology_index.point_vertex index ~point ~local in
               tangent.x.(point) <- tangent.x.(point)
                 +. vertex_tangent.x.(vertex);
               tangent.y.(point) <- tangent.y.(point)
                 +. vertex_tangent.y.(vertex);
               tangent.z.(point) <- tangent.z.(point)
                 +. vertex_tangent.z.(vertex)
             done
         | Some tangent, None, _ ->
             tangent.x.(point) <- 0.; tangent.y.(point) <- 0.;
             tangent.z.(point) <- 0.;
             for local = 0 to incidence - 1 do
               let vertex = Topology_index.point_vertex index ~point ~local in
               tangent.x.(point) <- tangent.x.(point)
                 +. vertex_tangent.x.(vertex);
               tangent.y.(point) <- tangent.y.(point)
                 +. vertex_tangent.y.(vertex);
               tangent.z.(point) <- tangent.z.(point)
                 +. vertex_tangent.z.(vertex)
             done
         | None, Some bitangent, Some vertex_bitangent ->
             bitangent.x.(point) <- 0.; bitangent.y.(point) <- 0.;
             bitangent.z.(point) <- 0.;
             for local = 0 to incidence - 1 do
               let vertex = Topology_index.point_vertex index ~point ~local in
               bitangent.x.(point) <- bitangent.x.(point)
                 +. vertex_bitangent.x.(vertex);
               bitangent.y.(point) <- bitangent.y.(point)
                 +. vertex_bitangent.y.(vertex);
               bitangent.z.(point) <- bitangent.z.(point)
                 +. vertex_bitangent.z.(vertex)
             done
         | None, Some bitangent, None ->
             bitangent.x.(point) <- 0.; bitangent.y.(point) <- 0.;
             bitangent.z.(point) <- 0.
         | None, None, _ -> ())
      end);
    normalize_selected ~orthogonal ~left_handed ~normal ~tangent ~bitangent
      ~selected ~count:point_count ~grain ?cancel ()))

let add_attribute geometry owner name values =
  Result.bind (Attribute.create_owned ~owner ~name
      (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
        ~x:values.x ~y:values.y ~z:values.z))) (fun attribute ->
    Geometry.with_attribute attribute geometry)

let run ?cancel ?(grain = 16_384) ?selection ?(orthogonal = false)
    ?(left_handed = false)
    ?(normal_attribute = "N") ?(tangent_attribute = Some "tangentu")
    ?(bitangent_attribute = Some "tangentv") style geometry =
  if grain <= 0 then invalid_arg "Pdk.Ops.polyframe: grain must be positive";
  Result.bind (validate_names ~normal_attribute ~tangent_attribute
      ~bitangent_attribute) (fun () ->
  Result.bind (Deform.validate_selection (Geometry.topology geometry) selection)
    (fun () ->
  let owner = output_owner style in
  let count = match owner with
    | Attribute.Point -> Geometry.point_count geometry
    | Attribute.Vertex -> Geometry.vertex_count geometry
    | Attribute.Primitive -> Geometry.primitive_count geometry
    | Attribute.Detail -> 1 in
  Result.bind (existing_planes ~owner ~count normal_attribute geometry)
    (fun normal ->
  let tangent_result = match tangent_attribute with
    | None when bitangent_attribute = None -> Ok None
    | None -> Ok (Some { x = Array.make count 0.; y = Array.make count 0.;
        z = Array.make count 0. })
    | Some name -> Result.map Option.some
        (existing_planes ~owner ~count name geometry) in
  Result.bind tangent_result (fun tangent ->
  let bitangent_result = match bitangent_attribute with
    | None -> Ok None
    | Some name -> Result.map Option.some
        (existing_planes ~owner ~count name geometry) in
  Result.bind bitangent_result (fun bitangent ->
  let computation = match style with
    | First_edge | Two_edges | Primitive_centroid ->
        point_style ?cancel ~grain ~selection ~orthogonal ~left_handed ~normal
          ~tangent ~bitangent style geometry
    | Texture_uv name ->
        Result.bind (scalar2_attribute (texture_attribute_name name) geometry)
          (fun values ->
          Result.bind (validate_scalar2 values) (fun () ->
            point_texture ?cancel ~grain ~selection ~orthogonal ~left_handed
              ~normal ~tangent ~bitangent values geometry))
    | Texture_uv_gradient name ->
        Result.bind (scalar2_attribute (texture_attribute_name name) geometry)
          (fun values ->
          Result.bind (validate_scalar2 values) (fun () ->
            vertex_gradient ?cancel ~grain ~selection ~orthogonal ~left_handed
              ~normal ~tangent ~bitangent values geometry))
    | Attribute_gradient name ->
        Result.bind (scalar2_attribute name geometry) (fun values ->
          Result.bind (validate_scalar2 values) (fun () ->
            vertex_gradient ?cancel ~grain ~selection ~orthogonal ~left_handed
              ~normal ~tangent ~bitangent values geometry)) in
  Result.bind computation (fun () ->
  Result.bind (add_attribute geometry owner normal_attribute normal)
    (fun geometry ->
  let with_tangent = match tangent_attribute, tangent with
    | Some name, Some values -> add_attribute geometry owner name values
    | _ -> Ok geometry in
  Result.bind with_tangent (fun geometry ->
    match bitangent_attribute, bitangent with
    | Some name, Some values -> add_attribute geometry owner name values
    | _ -> Ok geometry))))))))
