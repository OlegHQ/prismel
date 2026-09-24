open Prismel

type kernels = {
  triangulate : Geometry.t -> (Geometry.t, string) result;
  collapse : Edge_group.t -> Geometry.t -> (Geometry.t, string) result;
  flip : Edge_group.t -> Geometry.t -> (Geometry.t, string) result;
}

type projection_scratch = {
  count : int;
  primitives : int array;
  triangles : int array;
  barycentric_a : float array;
  barycentric_b : float array;
  barycentric_c : float array;
  distances_squared : float array;
}

let operation = "Pdk.Ops.remesh"
let fail message = Error (operation ^ ": " ^ message)
let finite = Float.is_finite

let validate_name label = function
  | None -> Ok ()
  | Some name when String.trim name = "" ->
      fail (label ^ " name must not be empty")
  | Some _ -> Ok ()

let validate_point_group geometry = function
  | None -> Ok ()
  | Some group when Group.owner group <> Group.Point ->
      fail "hard point selection must own points"
  | Some group when Group.length group <> Geometry.point_count geometry ->
      fail "hard point selection length does not match point count"
  | Some _ -> Ok ()

let validate_edge_group geometry = function
  | None -> Ok ()
  | Some group ->
      let topology = Geometry.topology geometry in
      let index = Topology_index.create topology in
      if Edge_group.topology_data_id group <> Topology.data_id topology then
        fail "hard edge selection belongs to a different topology"
      else if Edge_group.length group <> Topology_index.edge_count index then
        fail "hard edge selection length does not match topology edge count"
      else Ok ()

let validate_positions ?cancel geometry =
  let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let invalid = ref (-1) and point = ref 0 in
  while !point < Array.length positions.x && !invalid < 0 do
    if !point land 4095 = 0 then Cancel.check_opt cancel;
    if not (finite positions.x.(!point) && finite positions.y.(!point)
        && finite positions.z.(!point)) then invalid := !point;
    incr point
  done;
  if !invalid < 0 then Ok ()
  else fail (Printf.sprintf "point %d has a non-finite position" !invalid)

let target_values ?cancel name geometry = match name with
  | None -> Ok None
  | Some name ->
      if String.trim name = "" then fail "target-size attribute name must not be empty"
      else match Geometry.find_attribute ~owner:Attribute.Point name geometry with
        | None -> fail (Printf.sprintf
            "point target-size attribute %S does not exist" name)
        | Some attribute ->
            (match Attribute.Private.storage attribute with
             | Attribute.Float values ->
                 let invalid = ref (-1) and point = ref 0 in
                 while !point < Array.length values && !invalid < 0 do
                   if !point land 4095 = 0 then Cancel.check_opt cancel;
                   if not (finite values.(!point)) || values.(!point) <= 0. then
                     invalid := !point;
                   incr point
                 done;
                 if !invalid < 0 then Ok (Some values)
                 else fail (Printf.sprintf
                     "target-size attribute %S must be finite and positive at point %d"
                     name !invalid)
             | Attribute.Int _ | Attribute.Int_array _ | Attribute.Float_array _
             | Attribute.Float2 _ | Attribute.Float3 _ | Attribute.Float4 _
             | Attribute.Text _ -> fail (Printf.sprintf
                 "point target-size attribute %S must be scalar float" name))

let fresh_group_name geometry owner base reserved =
  let rec loop suffix =
    let name = if suffix = 0 then base else base ^ string_of_int suffix in
    if Some name = reserved || Geometry.find_group ~owner name geometry <> None
    then loop (suffix + 1) else name
  in
  loop 0

let fresh_edge_group_name geometry base reserved =
  let rec loop suffix =
    let name = if suffix = 0 then base else base ^ string_of_int suffix in
    if Some name = reserved || Geometry.find_edge_group name geometry <> None
    then loop (suffix + 1) else name
  in
  loop 0

let uv_reader name geometry =
  match Geometry.find_attribute ~owner:Attribute.Vertex name geometry with
  | None -> Ok None
  | Some attribute ->
      let equal = match Attribute.Private.storage attribute with
        | Attribute.Float values -> Some (fun a b -> values.(a) = values.(b))
        | Attribute.Float2 values ->
            let values = Packed.Float2.Private.view values in
            Some (fun a b -> values.x.(a) = values.x.(b)
              && values.y.(a) = values.y.(b))
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            Some (fun a b -> values.x.(a) = values.x.(b)
              && values.y.(a) = values.y.(b) && values.z.(a) = values.z.(b))
        | Attribute.Float4 values ->
            let values = Packed.Float4.Private.view values in
            Some (fun a b -> values.x.(a) = values.x.(b)
              && values.y.(a) = values.y.(b) && values.z.(a) = values.z.(b)
              && values.w.(a) = values.w.(b))
        | Attribute.Int _ | Attribute.Int_array _ | Attribute.Float_array _
        | Attribute.Text _ -> None in
      (match equal with
       | Some equal -> Ok (Some equal)
       | None -> fail (Printf.sprintf
           "vertex UV attribute %S must be float, float2, float3, or float4"
           name))

let endpoint_vertices topology index edge incidence =
  let vertex = index.Topology_index.Private.edge_vertices.(incidence) in
  let next = index.next_vertex.(vertex) in
  if next < 0 then None
  else
    let a = index.edge_a.(edge) and b = index.edge_b.(edge)
    and point = topology.Topology.Private.vertex_points.(vertex)
    and next_point = topology.vertex_points.(next) in
    if point = a && next_point = b then Some (vertex, next)
    else if point = b && next_point = a then Some (next, vertex)
    else None

let install_feature_groups ?cancel ~grain ~hard_points ~hard_edges
    ~preserve_uv_seams ~uv_attribute ~point_name ~edge_name geometry =
  let topology_value = Geometry.topology geometry in
  let topology = Topology.Private.view topology_value in
  let index_value = Topology_index.create ?cancel topology_value in
  let index = Topology_index.Private.view index_value in
  let uv = if preserve_uv_seams then uv_reader uv_attribute geometry else Ok None in
  Result.bind uv (fun uv_equal ->
    let feature_edges = Edge_group.init ~grain ~topology:topology_value
        ~index:index_value ~name:edge_name (fun edge ->
      if edge land 4095 = 0 then Cancel.check_opt cancel;
      let explicit = match hard_edges with
        | None -> false | Some group -> Edge_group.mem edge group in
      if explicit then true
      else
        let first = index.edge_offsets.(edge)
        and last = index.edge_offsets.(edge + 1) in
        if last - first > 2 then true
        else match uv_equal with
          | None -> false
          | Some equal when last - first = 2 ->
              (match endpoint_vertices topology index edge first,
                  endpoint_vertices topology index edge (first + 1) with
               | Some (a0, b0), Some (a1, b1) ->
                   not (equal a0 a1 && equal b0 b1)
               | _ -> true)
          | Some _ -> false) in
    let points = Group.init ~grain ~owner:Group.Point ~name:point_name
        (Geometry.point_count geometry) (fun point -> match hard_points with
          | None -> false | Some group -> Group.mem point group) in
    Result.bind (Geometry.with_edge_group feature_edges geometry) (fun geometry ->
      Geometry.with_group points geometry))

let feature_group name geometry = match Geometry.find_edge_group name geometry with
  | Some group -> Ok group
  | None -> fail "internal feature-edge ancestry was lost"

let hard_point_group name geometry = match Geometry.find_group
    ~owner:Group.Point name geometry with
  | Some group -> Ok group
  | None -> fail "internal hard-point ancestry was lost"

let edge_length positions a b =
  Float.hypot (positions.Packed.Float3.Private.x.(a) -. positions.x.(b))
    (Float.hypot (positions.y.(a) -. positions.y.(b))
       (positions.z.(a) -. positions.z.(b)))

let edge_target target_length targets a b = match targets with
  | None -> target_length
  | Some values -> 0.5 *. (values.(a) +. values.(b))

let select_long_edges ?cancel ~grain ~target_length ~target_size_attribute geometry =
  Result.bind (target_values ?cancel target_size_attribute geometry) (fun targets ->
    let topology = Geometry.topology geometry in
    let index_value = Topology_index.create ?cancel topology in
    let index = Topology_index.Private.view index_value in
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    Ok (Edge_group.init ~grain ~topology ~index:index_value
      ~name:"__pdk_remesh_long" (fun edge ->
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
        edge_length positions a b > (4. /. 3.) *.
          edge_target target_length targets a b)))

let primitive_is_triangle topology primitive =
  Bytes.unsafe_get topology.Topology.Private.primitive_kinds primitive = '\000'
  && topology.primitive_offsets.(primitive + 1)
     - topology.primitive_offsets.(primitive) = 3

let checked_add label left right =
  if left < 0 || right < 0 || left > Sys.max_array_length - right then
    invalid_arg (operation ^ ": " ^ label ^ " exceeds array limits");
  left + right

let split_long_triangles ?cancel ~grain edges geometry =
  let topology_value = Geometry.topology geometry in
  let topology = Topology.Private.view topology_value in
  let index_value = Topology_index.create ?cancel topology_value in
  let index = Topology_index.Private.view index_value in
  let edge_count = Array.length index.edge_a
  and source_points = Geometry.point_count geometry
  and source_primitives = Geometry.primitive_count geometry in
  if Edge_group.topology_data_id edges <> Topology.data_id topology_value
      || Edge_group.length edges <> edge_count then
    fail "internal long-edge selection does not match its topology"
  else if Edge_group.cardinality edges = 0 then Ok geometry
  else begin
    let midpoint_of_edge = Array.make edge_count (-1) in
    let output_points = ref source_points
    and selected_incidences = ref 0 in
    for edge = 0 to edge_count - 1 do
      if edge land 4095 = 0 then Cancel.check_opt cancel;
      if Edge_group.mem edge edges then begin
        midpoint_of_edge.(edge) <- !output_points;
        output_points := checked_add "split point cardinality" !output_points 1;
        selected_incidences := checked_add "split primitive cardinality"
            !selected_incidences
            (index.edge_offsets.(edge + 1) - index.edge_offsets.(edge))
      end
    done;
    let output_primitives = checked_add "split primitive cardinality"
        source_primitives !selected_incidences in
    if output_primitives > Sys.max_array_length / 3 then
      fail "split vertex cardinality exceeds array limits"
    else begin
      let primitive_bases = Array.make (source_primitives + 1) 0 in
      for primitive = 0 to source_primitives - 1 do
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        if not (primitive_is_triangle topology primitive) then
          invalid_arg (Printf.sprintf "%s: primitive %d is not a triangle"
            operation primitive);
        let first = topology.primitive_offsets.(primitive) in
        let additions = ref 0 in
        for local = 0 to 2 do
          let edge = index.edge_of_vertex.(first + local) in
          if edge >= 0 && midpoint_of_edge.(edge) >= 0 then incr additions
        done;
        primitive_bases.(primitive + 1) <- checked_add
            "split primitive prefix" primitive_bases.(primitive)
            (1 + !additions)
      done;
      if primitive_bases.(source_primitives) <> output_primitives then
        invalid_arg (operation ^ ": split primitive plan does not match incidence count");
      let point_left = Array.init !output_points (fun point ->
          if point < source_points then point else 0)
      and point_right = Array.init !output_points (fun point ->
          if point < source_points then point else 0)
      and point_weight = Array.make !output_points 0. in
      if edge_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(edge_count - 1) (fun edge ->
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        let midpoint = midpoint_of_edge.(edge) in
        if midpoint >= 0 then begin
          point_left.(midpoint) <- index.edge_a.(edge);
          point_right.(midpoint) <- index.edge_b.(edge);
          point_weight.(midpoint) <- 0.5
        end);
      let source_positions = Packed.Float3.Private.view
          (Geometry.positions geometry) in
      let x = Array.make !output_points 0. and y = Array.make !output_points 0.
      and z = Array.make !output_points 0. in
      Array.blit source_positions.x 0 x 0 source_points;
      Array.blit source_positions.y 0 y 0 source_points;
      Array.blit source_positions.z 0 z 0 source_points;
      let inserted = !output_points - source_points in
      if inserted > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(inserted - 1) (fun local ->
        let point = source_points + local in
        let a = point_left.(point) and b = point_right.(point) in
        x.(point) <- 0.5 *. source_positions.x.(a)
          +. 0.5 *. source_positions.x.(b);
        y.(point) <- 0.5 *. source_positions.y.(a)
          +. 0.5 *. source_positions.y.(b);
        z.(point) <- 0.5 *. source_positions.z.(a)
          +. 0.5 *. source_positions.z.(b);
        if not (finite x.(point) && finite y.(point) && finite z.(point)) then
          invalid_arg (Printf.sprintf "%s: split point %d is non-finite"
            operation point));
      let output_vertices = output_primitives * 3 in
      let vertex_points = Array.make output_vertices 0
      and vertex_left = Array.make output_vertices 0
      and vertex_right = Array.make output_vertices 0
      and vertex_weight = Array.make output_vertices 0.
      and primitive_source = Array.make output_primitives 0 in
      let set_descriptor source_first target descriptor =
        if descriptor < 3 then begin
          let source = source_first + descriptor in
          vertex_points.(target) <- topology.vertex_points.(source);
          vertex_left.(target) <- source;
          vertex_right.(target) <- source
        end else begin
          let local = descriptor - 3 in
          let left = source_first + local
          and right = source_first + ((local + 1) mod 3) in
          let edge = index.edge_of_vertex.(left) in
          let midpoint = midpoint_of_edge.(edge) in
          if midpoint < 0 then invalid_arg
              (operation ^ ": split triangle references an absent midpoint");
          vertex_points.(target) <- midpoint;
          vertex_left.(target) <- left;
          vertex_right.(target) <- right;
          vertex_weight.(target) <- 0.5
        end in
      let emit source_primitive source_first output_local a b c =
        let primitive = primitive_bases.(source_primitive) + output_local in
        let vertex = primitive * 3 in
        primitive_source.(primitive) <- source_primitive;
        set_descriptor source_first vertex a;
        set_descriptor source_first (vertex + 1) b;
        set_descriptor source_first (vertex + 2) c in
      if source_primitives > 0 then Parallel.for_ ~chunk_size:(max 1 (grain / 3))
          ~start:0 ~finish:(source_primitives - 1) (fun primitive ->
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        let first = topology.primitive_offsets.(primitive) in
        let mask = ref 0 in
        for local = 0 to 2 do
          let edge = index.edge_of_vertex.(first + local) in
          if edge >= 0 && midpoint_of_edge.(edge) >= 0 then
            mask := !mask lor (1 lsl local)
        done;
        match !mask with
        | 0 -> emit primitive first 0 0 1 2
        | 1 -> emit primitive first 0 0 3 2; emit primitive first 1 3 1 2
        | 2 -> emit primitive first 0 1 4 0; emit primitive first 1 4 2 0
        | 4 -> emit primitive first 0 2 5 1; emit primitive first 1 5 0 1
        | 3 -> emit primitive first 0 0 3 2; emit primitive first 1 3 4 2;
            emit primitive first 2 3 1 4
        | 6 -> emit primitive first 0 1 4 0; emit primitive first 1 4 5 0;
            emit primitive first 2 4 2 5
        | 5 -> emit primitive first 0 2 5 1; emit primitive first 1 5 3 1;
            emit primitive first 2 5 0 3
        | 7 -> emit primitive first 0 0 3 5; emit primitive first 1 3 1 4;
            emit primitive first 2 5 4 2; emit primitive first 3 3 4 5
        | _ -> assert false);
      let output_topology = Topology.Private.create_validated_owned
          ~point_count:!output_points ~vertex_points
          ~primitive_offsets:(Array.init (output_primitives + 1)
            (fun primitive -> primitive * 3))
          ~primitive_kinds:(Bytes.make output_primitives '\000') in
      let attributes = Geometry.attributes geometry |> List.filter_map
          (fun attribute ->
            if String.equal (Attribute.name attribute) "N"
                && (Attribute.owner attribute = Attribute.Point
                    || Attribute.owner attribute = Attribute.Vertex)
            then None
            else Some (Subdivide.interpolate_owned_attribute ?cancel ~grain
              ~point_left ~point_right ~point_weight ~vertex_left ~vertex_right
              ~vertex_weight ~primitive_source attribute)) in
      let groups = Geometry.groups geometry |> List.map (fun group ->
        let left, right, weight = match Group.owner group with
          | Group.Point -> point_left, point_right, point_weight
          | Group.Vertex -> vertex_left, vertex_right, vertex_weight
          | Group.Primitive -> primitive_source, primitive_source,
              Array.make output_primitives 0. in
        let target = Group.init ~grain ~owner:(Group.owner group)
            ~name:(Group.name group) (Array.length left) (fun output ->
          Group.mem left.(output) group && Group.mem right.(output) group) in
        if not (Group.is_ordered group) then target
        else
          let ancestry = Array.mapi (fun output source ->
            if weight.(output) = 0. && source = right.(output)
            then source else -1) left in
          Group.Private.remap_order ~source:group ~source_of_target:ancestry target) in
      let output_index_value = Topology_index.create ?cancel output_topology in
      let output_index = Topology_index.Private.view output_index_value in
      let midpoint_source = Array.make !output_points (-1) in
      for edge = 0 to edge_count - 1 do
        let midpoint = midpoint_of_edge.(edge) in
        if midpoint >= 0 then midpoint_source.(midpoint) <- edge
      done;
      let source_edge_of_output = Array.init (Array.length output_index.edge_a)
          (fun edge ->
        let a = output_index.edge_a.(edge) and b = output_index.edge_b.(edge) in
        if a < source_points && b < source_points then
          Topology_index.find_edge_index index_value ~a ~b
        else if a >= source_points && b >= source_points then -1
        else
          let midpoint, endpoint = if a >= source_points then a, b else b, a in
          let source_edge = midpoint_source.(midpoint) in
          if source_edge < 0 then -1
          else if endpoint = index.edge_a.(source_edge)
              || endpoint = index.edge_b.(source_edge) then source_edge
          else -1) in
      let edge_groups = Geometry.edge_groups geometry |> List.map (fun group ->
        Edge_group.init ~grain ~topology:output_topology ~index:output_index_value
          ~name:(Edge_group.name group) (fun edge ->
            let source = source_edge_of_output.(edge) in
            source >= 0 && Edge_group.mem source group)) in
      Geometry.create
        ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
        ~topology:output_topology ~attributes ~groups ~edge_groups ()
    end
  end

let point_constraints ?cancel ~grain ~point_name ~edge_name geometry =
  let topology = Geometry.topology geometry in
  let index_value = Topology_index.create ?cancel topology in
  let index = Topology_index.Private.view index_value in
  Result.bind (hard_point_group point_name geometry) (fun hard_points ->
  Result.bind (feature_group edge_name geometry) (fun features ->
    Ok (Group.init ~grain ~owner:Group.Point ~name:"__pdk_remesh_constraints"
      (Geometry.point_count geometry) (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if Group.mem point hard_points then true
        else
          let first = index.point_edge_offsets.(point)
          and last = index.point_edge_offsets.(point + 1) in
          let constrained = ref false and local = ref first in
          while !local < last && not !constrained do
            let edge = index.point_edges.(!local) in
            constrained := Edge_group.mem edge features
              || index.edge_offsets.(edge + 1) - index.edge_offsets.(edge) <> 2;
            incr local
          done;
          !constrained))))

let scaled_cross positions a b c =
  let abx = positions.Packed.Float3.Private.x.(b) -. positions.x.(a)
  and aby = positions.y.(b) -. positions.y.(a)
  and abz = positions.z.(b) -. positions.z.(a)
  and acx = positions.x.(c) -. positions.x.(a)
  and acy = positions.y.(c) -. positions.y.(a)
  and acz = positions.z.(c) -. positions.z.(a) in
  let scale = Float.max (Float.max (Float.abs abx) (Float.abs aby))
      (Float.max (Float.abs abz) (Float.max (Float.abs acx)
        (Float.max (Float.abs acy) (Float.abs acz)))) in
  if scale = 0. then 0., 0., 0.
  else
    let abx = abx /. scale and aby = aby /. scale and abz = abz /. scale
    and acx = acx /. scale and acy = acy /. scale and acz = acz /. scale in
    (aby *. acz -. abz *. acy,
     abz *. acx -. abx *. acz,
     abx *. acy -. aby *. acx)

let collapse_preserves_triangle positions topology primitive a b mx my mz =
  let first = topology.Topology.Private.primitive_offsets.(primitive) in
  let p0 = topology.vertex_points.(first)
  and p1 = topology.vertex_points.(first + 1)
  and p2 = topology.vertex_points.(first + 2) in
  let ox, oy, oz = scaled_cross positions p0 p1 p2 in
  let coordinate point =
    if point = a || point = b then mx, my, mz
    else positions.Packed.Float3.Private.x.(point), positions.y.(point),
      positions.z.(point) in
  let x0, y0, z0 = coordinate p0 and x1, y1, z1 = coordinate p1
  and x2, y2, z2 = coordinate p2 in
  let abx = x1 -. x0 and aby = y1 -. y0 and abz = z1 -. z0
  and acx = x2 -. x0 and acy = y2 -. y0 and acz = z2 -. z0 in
  let scale = Float.max (Float.max (Float.abs abx) (Float.abs aby))
      (Float.max (Float.abs abz) (Float.max (Float.abs acx)
        (Float.max (Float.abs acy) (Float.abs acz)))) in
  if scale = 0. then false
  else
    let abx = abx /. scale and aby = aby /. scale and abz = abz /. scale
    and acx = acx /. scale and acy = acy /. scale and acz = acz /. scale in
    let nx = aby *. acz -. abz *. acy
    and ny = abz *. acx -. abx *. acz
    and nz = abx *. acy -. aby *. acx in
    let new_norm2 = nx *. nx +. ny *. ny +. nz *. nz
    and old_norm2 = ox *. ox +. oy *. oy +. oz *. oz in
    new_norm2 > 1e-28 && old_norm2 > 1e-28
    && ox *. nx +. oy *. ny +. oz *. nz > 1e-14 *. sqrt (old_norm2 *. new_norm2)

let link_condition index topology stamps stamp edge a b =
  let first = index.Topology_index.Private.edge_offsets.(edge) in
  let v0 = index.edge_vertices.(first) and v1 = index.edge_vertices.(first + 1) in
  let opposite vertex =
    let next = index.next_vertex.(vertex) in
    topology.Topology.Private.vertex_points.(index.next_vertex.(next)) in
  let c = opposite v0 and d = opposite v1 in
  let first_a = index.point_edge_offsets.(a)
  and last_a = index.point_edge_offsets.(a + 1) in
  for local = first_a to last_a - 1 do
    let candidate = index.point_edges.(local) in
    let x = index.edge_a.(candidate) and y = index.edge_b.(candidate) in
    let neighbor = if x = a then y else x in
    if neighbor <> a then stamps.(neighbor) <- stamp
  done;
  let common = ref 0 and valid = ref true in
  let first_b = index.point_edge_offsets.(b)
  and last_b = index.point_edge_offsets.(b + 1) in
  for local = first_b to last_b - 1 do
    let candidate = index.point_edges.(local) in
    let x = index.edge_a.(candidate) and y = index.edge_b.(candidate) in
    let neighbor = if x = b then y else x in
    if neighbor <> b && stamps.(neighbor) = stamp then begin
      incr common;
      if neighbor <> c && neighbor <> d then valid := false
    end
  done;
  !valid && !common = (if c = d then 1 else 2)

let select_short_edges ?cancel ~grain ~target_length ~target_size_attribute
    ~point_name ~edge_name geometry =
  Result.bind (target_values ?cancel target_size_attribute geometry) (fun targets ->
  Result.bind (point_constraints ?cancel ~grain ~point_name ~edge_name geometry)
    (fun constraints ->
  Result.bind (feature_group edge_name geometry) (fun features ->
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value in
    let index_value = Topology_index.create ?cancel topology_value in
    let index = Topology_index.Private.view index_value in
    let edge_count = Array.length index.edge_a
    and primitive_count = Geometry.primitive_count geometry
    and point_count = Geometry.point_count geometry in
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let lengths = Parallel.init_array ~grain edge_count (fun edge ->
      let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
      edge_length positions a b) in
    let candidate_count = ref 0 in
    for edge = 0 to edge_count - 1 do
      if edge land 4095 = 0 then Cancel.check_opt cancel;
      let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
      if index.edge_offsets.(edge + 1) - index.edge_offsets.(edge) = 2
          && primitive_is_triangle topology
            index.primitive_of_vertex.(index.edge_vertices.(index.edge_offsets.(edge)))
          && primitive_is_triangle topology
            index.primitive_of_vertex.(index.edge_vertices.(index.edge_offsets.(edge) + 1))
          && not (Edge_group.mem edge features)
          && not (Group.mem a constraints || Group.mem b constraints)
          && lengths.(edge) < (4. /. 5.) *.
            edge_target target_length targets a b
      then incr candidate_count
    done;
    let candidates = Array.make !candidate_count 0 and cursor = ref 0 in
    for edge = 0 to edge_count - 1 do
      let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
      if index.edge_offsets.(edge + 1) - index.edge_offsets.(edge) = 2
          && primitive_is_triangle topology
            index.primitive_of_vertex.(index.edge_vertices.(index.edge_offsets.(edge)))
          && primitive_is_triangle topology
            index.primitive_of_vertex.(index.edge_vertices.(index.edge_offsets.(edge) + 1))
          && not (Edge_group.mem edge features)
          && not (Group.mem a constraints || Group.mem b constraints)
          && lengths.(edge) < (4. /. 5.) *.
            edge_target target_length targets a b
      then begin candidates.(!cursor) <- edge; incr cursor end
    done;
    Array.sort (fun left right ->
      let by_length = Float.compare lengths.(left) lengths.(right) in
      if by_length <> 0 then by_length else Int.compare left right) candidates;
    let chosen = Bytes.make ((edge_count + 7) / 8) '\000'
    and used_points = Bytes.make ((point_count + 7) / 8) '\000'
    and used_primitives = Bytes.make ((primitive_count + 7) / 8) '\000'
    and neighbor_stamps = Array.make point_count (-1) in
    let bit_get bits index = Char.code (Bytes.unsafe_get bits (index lsr 3))
        land (1 lsl (index land 7)) <> 0 in
    let bit_set bits index =
      let slot = index lsr 3 and mask = 1 lsl (index land 7) in
      Bytes.unsafe_set bits slot
        (Char.chr (Char.code (Bytes.unsafe_get bits slot) lor mask)) in
    Array.iteri (fun stamp edge ->
      if stamp land 4095 = 0 then Cancel.check_opt cancel;
      let a = index.edge_a.(edge) and b = index.edge_b.(edge)
      and first = index.edge_offsets.(edge) in
      let primitive_a = index.primitive_of_vertex.(index.edge_vertices.(first))
      and primitive_b = index.primitive_of_vertex.(index.edge_vertices.(first + 1)) in
      if not (bit_get used_points a || bit_get used_points b
          || bit_get used_primitives primitive_a
          || bit_get used_primitives primitive_b)
          && link_condition index topology neighbor_stamps stamp edge a b then begin
        let mx = 0.5 *. (positions.x.(a) +. positions.x.(b))
        and my = 0.5 *. (positions.y.(a) +. positions.y.(b))
        and mz = 0.5 *. (positions.z.(a) +. positions.z.(b)) in
        let valid = ref true in
        let inspect point =
          let first = index.point_offsets.(point)
          and last = index.point_offsets.(point + 1) in
          let local = ref first in
          while !local < last && !valid do
            let primitive = index.primitive_of_vertex.(index.point_vertices.(!local)) in
            if primitive <> primitive_a && primitive <> primitive_b then
              if bit_get used_primitives primitive
                  || not (primitive_is_triangle topology primitive)
                  || not (collapse_preserves_triangle positions topology primitive
                    a b mx my mz) then valid := false;
            incr local
          done in
        inspect a; inspect b;
        if !valid then begin
          bit_set chosen edge; bit_set used_points a; bit_set used_points b;
          let reserve point =
            let first = index.point_offsets.(point)
            and last = index.point_offsets.(point + 1) in
            for local = first to last - 1 do
              bit_set used_primitives
                index.primitive_of_vertex.(index.point_vertices.(local))
            done in
          reserve a; reserve b
        end
      end) candidates;
    Ok (Edge_group.Private.of_owned_bits ~topology:topology_value ~edge_count
      ~name:"__pdk_remesh_short" chosen))))

let cross_points positions a b c =
  let abx = positions.Packed.Float3.Private.x.(b) -. positions.x.(a)
  and aby = positions.y.(b) -. positions.y.(a)
  and abz = positions.z.(b) -. positions.z.(a)
  and acx = positions.x.(c) -. positions.x.(a)
  and acy = positions.y.(c) -. positions.y.(a)
  and acz = positions.z.(c) -. positions.z.(a) in
  (aby *. acz -. abz *. acy,
   abz *. acx -. abx *. acz,
   abx *. acy -. aby *. acx)

let same_orientation positions (a0, b0, c0) (a1, b1, c1) =
  let ox, oy, oz = cross_points positions a0 b0 c0
  and nx, ny, nz = cross_points positions a1 b1 c1 in
  let old2 = ox *. ox +. oy *. oy +. oz *. oz
  and new2 = nx *. nx +. ny *. ny +. nz *. nz in
  old2 > 0. && new2 > 0.
  && ox *. nx +. oy *. ny +. oz *. nz > 1e-14 *. sqrt (old2 *. new2)

let select_flip_edges ?cancel ~grain ~point_name ~edge_name geometry =
  Result.bind (point_constraints ?cancel ~grain ~point_name ~edge_name geometry)
    (fun constraints ->
  Result.bind (feature_group edge_name geometry) (fun features ->
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value in
    let index_value = Topology_index.create ?cancel topology_value in
    let index = Topology_index.Private.view index_value in
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let edge_count = Array.length index.edge_a
    and primitive_count = Geometry.primitive_count geometry in
    let valence = Array.init (Geometry.point_count geometry) (fun point ->
      index.point_edge_offsets.(point + 1) - index.point_edge_offsets.(point)) in
    let boundary = Bytes.make ((Geometry.point_count geometry + 7) / 8) '\000' in
    for edge = 0 to edge_count - 1 do
      if index.edge_offsets.(edge + 1) - index.edge_offsets.(edge) <> 2 then begin
        let set point =
          let slot = point lsr 3 and bit = 1 lsl (point land 7) in
          Bytes.unsafe_set boundary slot
            (Char.chr (Char.code (Bytes.unsafe_get boundary slot) lor bit)) in
        set index.edge_a.(edge); set index.edge_b.(edge)
      end
    done;
    let is_boundary point =
      Char.code (Bytes.unsafe_get boundary (point lsr 3))
        land (1 lsl (point land 7)) <> 0 in
    let ideal point = if is_boundary point then 4 else 6 in
    let penalty point degree = abs (degree - ideal point) in
    let eligible = Bytes.make ((edge_count + 7) / 8) '\000' in
    let set_eligible edge =
      let slot = edge lsr 3 and bit = 1 lsl (edge land 7) in
      Bytes.unsafe_set eligible slot
        (Char.chr (Char.code (Bytes.unsafe_get eligible slot) lor bit)) in
    for edge = 0 to edge_count - 1 do
      if edge land 4095 = 0 then Cancel.check_opt cancel;
      let first = index.edge_offsets.(edge)
      and last = index.edge_offsets.(edge + 1) in
      if last - first = 2 && not (Edge_group.mem edge features) then begin
        let va = index.edge_vertices.(first) and vb = index.edge_vertices.(first + 1) in
        let pa = index.primitive_of_vertex.(va)
        and pb = index.primitive_of_vertex.(vb) in
        if pa <> pb && primitive_is_triangle topology pa
            && primitive_is_triangle topology pb then begin
          let a = index.edge_a.(edge) and b = index.edge_b.(edge)
          and c = topology.vertex_points.(index.next_vertex.(index.next_vertex.(va)))
          and d = topology.vertex_points.(index.next_vertex.(index.next_vertex.(vb))) in
          if a <> b && a <> c && a <> d && b <> c && b <> d && c <> d
              && not (Group.mem a constraints || Group.mem b constraints)
              && Topology_index.find_edge_index index_value ~a:c ~b:d < 0 then begin
            let before = penalty a valence.(a) + penalty b valence.(b)
                + penalty c valence.(c) + penalty d valence.(d)
            and after = penalty a (valence.(a) - 1) + penalty b (valence.(b) - 1)
                + penalty c (valence.(c) + 1) + penalty d (valence.(d) + 1) in
            if after < before
                && same_orientation positions (a, b, c) (d, c, b)
                && same_orientation positions (b, a, d) (c, d, a)
            then set_eligible edge
          end
        end
      end
    done;
    let chosen = Bytes.make ((edge_count + 7) / 8) '\000'
    and used_primitives = Bytes.make ((primitive_count + 7) / 8) '\000' in
    let bit_get bits index = Char.code (Bytes.unsafe_get bits (index lsr 3))
        land (1 lsl (index land 7)) <> 0 in
    let bit_set bits index =
      let slot = index lsr 3 and mask = 1 lsl (index land 7) in
      Bytes.unsafe_set bits slot
        (Char.chr (Char.code (Bytes.unsafe_get bits slot) lor mask)) in
    for edge = 0 to edge_count - 1 do
      if bit_get eligible edge then begin
        let first = index.edge_offsets.(edge) in
        let pa = index.primitive_of_vertex.(index.edge_vertices.(first))
        and pb = index.primitive_of_vertex.(index.edge_vertices.(first + 1)) in
        if not (bit_get used_primitives pa || bit_get used_primitives pb) then begin
          bit_set chosen edge; bit_set used_primitives pa; bit_set used_primitives pb
        end
      end
    done;
    Ok (Edge_group.Private.of_owned_bits ~topology:topology_value ~edge_count
      ~name:"__pdk_remesh_flip" chosen)))

let projection_scratch scratch count = match !scratch with
  | Some value when value.count = count -> value
  | None | Some _ ->
      let value = {
        count;
        primitives = Array.make count (-1);
        triangles = Array.make count (-1);
        barycentric_a = Array.make count 0.;
        barycentric_b = Array.make count 0.;
        barycentric_c = Array.make count 0.;
        distances_squared = Array.make count infinity;
      } in
      scratch := Some value;
      value

let project_to_reference ?cancel ~grain ~surface ~scratch reference geometry =
    let count = Geometry.point_count geometry in
    let topology = Geometry.topology geometry in
    let index = Topology_index.create ?cancel topology in
    let used = Group.init ~grain ~owner:Group.Point ~name:"__pdk_remesh_used"
        count (fun point -> Topology_index.point_incidence_count index point > 0) in
    let scratch = projection_scratch scratch count in
    let primitives = scratch.primitives and triangles = scratch.triangles
    and a = scratch.barycentric_a and b = scratch.barycentric_b
    and c = scratch.barycentric_c and distances = scratch.distances_squared in
    Surface_index.Private.closest_many_into ?cancel ~selection:used ~grain surface
      ~queries:(Geometry.positions geometry) ~max_distance_squared:infinity
      ~primitives ~triangles ~barycentric_a:a ~barycentric_b:b
      ~barycentric_c:c ~distances_squared:distances;
    let missed = ref (-1) in
    Group.iter (fun point -> if triangles.(point) < 0 && !missed < 0 then
      missed := point) used;
    if !missed >= 0 then fail (Printf.sprintf
        "could not project point %d to the input surface" !missed)
    else
      let source_positions = Packed.Float3.Private.view (Geometry.positions reference)
      and source_topology = Topology.Private.view (Geometry.topology reference)
      and current = Packed.Float3.Private.view (Geometry.positions geometry) in
      let x = Array.copy current.x and y = Array.copy current.y
      and z = Array.copy current.z in
      if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
          (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if Group.mem point used then begin
          let triangle = triangles.(point) in
          let vertex0 = Surface_index.Private.triangle_vertex surface triangle 0
          and vertex1 = Surface_index.Private.triangle_vertex surface triangle 1
          and vertex2 = Surface_index.Private.triangle_vertex surface triangle 2 in
          let p0 = source_topology.vertex_points.(vertex0)
          and p1 = source_topology.vertex_points.(vertex1)
          and p2 = source_topology.vertex_points.(vertex2) in
          x.(point) <- a.(point) *. source_positions.x.(p0)
            +. b.(point) *. source_positions.x.(p1)
            +. c.(point) *. source_positions.x.(p2);
          y.(point) <- a.(point) *. source_positions.y.(p0)
            +. b.(point) *. source_positions.y.(p1)
            +. c.(point) *. source_positions.y.(p2);
          z.(point) <- a.(point) *. source_positions.z.(p0)
            +. b.(point) *. source_positions.z.(p1)
            +. c.(point) *. source_positions.z.(p2)
        end);
      Geometry.with_positions
        (Packed.Float3.Private.of_owned_exn ~x ~y ~z) geometry

let install_outputs ?cancel ~grain ~target_length ~target_size_attribute
    ~edge_name ~output_hard_edges ~output_mesh_size ~output_quality geometry =
  let topology_value = Geometry.topology geometry in
  let topology = Topology.Private.view topology_value in
  let index_value = Topology_index.create ?cancel topology_value in
  let index = Topology_index.Private.view index_value in
  Result.bind (feature_group edge_name geometry) (fun features ->
  let with_hard_edges = match output_hard_edges with
    | None -> Ok geometry
    | Some name ->
        let group = Edge_group.init ~grain ~topology:topology_value
            ~index:index_value ~name (fun edge ->
          Edge_group.mem edge features
          || index.edge_offsets.(edge + 1) - index.edge_offsets.(edge) <> 2) in
        Geometry.with_edge_group group geometry in
  Result.bind with_hard_edges (fun geometry ->
  let with_size = match output_mesh_size with
    | None -> Ok geometry
    | Some name ->
        (match target_size_attribute with
         | Some source ->
             (match Geometry.find_attribute ~owner:Attribute.Point source geometry with
              | Some attribute -> Result.bind (Attribute.with_name name attribute)
                  (fun attribute -> Geometry.with_attribute attribute geometry)
              | None -> fail "internal target-size attribute ancestry was lost")
         | None ->
             let values = Array.make (Geometry.point_count geometry) target_length in
             Result.bind (Attribute.create_owned ~owner:Attribute.Point ~name
                 (Attribute.Float values)) (fun attribute ->
               Geometry.with_attribute attribute geometry)) in
  Result.bind with_size (fun geometry -> match output_quality with
    | None -> Ok geometry
    | Some name ->
        let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
        let primitive_count = Geometry.primitive_count geometry in
        let quality = Parallel.init_array ~grain primitive_count (fun primitive ->
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          if not (primitive_is_triangle topology primitive) then 0.
          else
            let first = topology.primitive_offsets.(primitive) in
            let p0 = topology.vertex_points.(first)
            and p1 = topology.vertex_points.(first + 1)
            and p2 = topology.vertex_points.(first + 2) in
            let dx01 = positions.x.(p1) -. positions.x.(p0)
            and dy01 = positions.y.(p1) -. positions.y.(p0)
            and dz01 = positions.z.(p1) -. positions.z.(p0)
            and dx12 = positions.x.(p2) -. positions.x.(p1)
            and dy12 = positions.y.(p2) -. positions.y.(p1)
            and dz12 = positions.z.(p2) -. positions.z.(p1)
            and dx20 = positions.x.(p0) -. positions.x.(p2)
            and dy20 = positions.y.(p0) -. positions.y.(p2)
            and dz20 = positions.z.(p0) -. positions.z.(p2) in
            let scale = Float.max (Float.max (Float.abs dx01) (Float.abs dy01))
                (Float.max (Float.abs dz01) (Float.max (Float.abs dx12)
                  (Float.max (Float.abs dy12) (Float.max (Float.abs dz12)
                    (Float.max (Float.abs dx20)
                      (Float.max (Float.abs dy20) (Float.abs dz20))))))) in
            if scale = 0. then 0.
            else
              let ax = dx01 /. scale and ay = dy01 /. scale
              and az = dz01 /. scale and bx = -.dx20 /. scale
              and by = -.dy20 /. scale and bz = -.dz20 /. scale in
              let cx = ay *. bz -. az *. by
              and cy = az *. bx -. ax *. bz
              and cz = ax *. by -. ay *. bx in
              let area2 = sqrt (cx *. cx +. cy *. cy +. cz *. cz)
              and lengths2 =
                (dx01 /. scale) ** 2. +. (dy01 /. scale) ** 2.
                +. (dz01 /. scale) ** 2. +. (dx12 /. scale) ** 2.
                +. (dy12 /. scale) ** 2. +. (dz12 /. scale) ** 2.
                +. (dx20 /. scale) ** 2. +. (dy20 /. scale) ** 2.
                +. (dz20 /. scale) ** 2. in
              if lengths2 = 0. then 0.
              else Float.min 1. (2. *. sqrt 3. *. area2 /. lengths2)) in
        Result.bind (Attribute.create_owned ~owner:Attribute.Primitive ~name
            (Attribute.Float quality)) (fun attribute ->
          Geometry.with_attribute attribute geometry))))

let run ?cancel ?(grain = 16_384) ?(iterations = 3) ?(smoothing = 0.5)
    ?(project = true) ?(use_input_points_only = false) ?hard_points ?hard_edges
    ?target_size_attribute ?(preserve_uv_seams = true) ?(uv_attribute = "uv")
    ?output_hard_edges ?output_mesh_size ?output_quality
    ?(recompute_point_normals = true) ~target_length ~kernels geometry =
  try
    if grain <= 0 then fail "grain must be positive"
    else if iterations < 0 then fail "iterations must be non-negative"
    else if not (finite target_length) || target_length <= 0. then
      fail "target length must be finite and positive"
    else if not (finite smoothing) || smoothing < 0. || smoothing > 1. then
      fail "smoothing must be finite and in [0, 1]"
    else Result.bind (validate_name "output hard-edge group" output_hard_edges)
      (fun () -> Result.bind (validate_name "output mesh-size attribute"
        output_mesh_size) (fun () -> Result.bind
      (validate_name "output quality attribute" output_quality) (fun () ->
    Result.bind (validate_point_group geometry hard_points) (fun () ->
    Result.bind (validate_edge_group geometry hard_edges) (fun () ->
    Result.bind (validate_positions ?cancel geometry) (fun () ->
    Result.bind (target_values ?cancel target_size_attribute geometry) (fun _ ->
      let point_name = fresh_group_name geometry Group.Point
          "__pdk_remesh_hard_points" None
      and edge_name = fresh_edge_group_name geometry "__pdk_remesh_features"
          output_hard_edges in
      Result.bind (install_feature_groups ?cancel ~grain ~hard_points ~hard_edges
          ~preserve_uv_seams ~uv_attribute ~point_name ~edge_name geometry)
        (fun prepared ->
      Result.bind (kernels.triangulate prepared) (fun initial ->
      let current = ref initial in
      let failure = ref None and iteration = ref 0 in
      let projection_scratch = ref None in
      let projection_surface = if project && iterations > 0 then
          match Surface_index.create ?cancel ~grain geometry with
          | Ok surface -> Some surface
          | Error error when Error.code error = "cancelled" ->
              raise Cancel.Cancelled
          | Error error ->
              failure := Some (Error.to_string error); None
        else None in
      while !iteration < iterations && !failure = None do
        Cancel.check_opt cancel;
        if not use_input_points_only then begin
          (match select_long_edges ?cancel ~grain ~target_length
              ~target_size_attribute !current with
           | Error message -> failure := Some message
           | Ok edges when Edge_group.cardinality edges = 0 -> ()
           | Ok edges ->
               (match split_long_triangles ?cancel ~grain edges !current with
                | Error message -> failure := Some message
                | Ok triangulated -> current := triangulated));
          if !failure = None then
            match select_short_edges ?cancel ~grain ~target_length
                ~target_size_attribute ~point_name ~edge_name !current with
            | Error message -> failure := Some message
            | Ok edges when Edge_group.cardinality edges = 0 -> ()
            | Ok edges ->
                (match kernels.collapse edges !current with
                 | Error message -> failure := Some message
                 | Ok collapsed -> current := collapsed)
        end;
        if !failure = None then begin
          match select_flip_edges ?cancel ~grain ~point_name ~edge_name !current with
          | Error message -> failure := Some message
          | Ok edges when Edge_group.cardinality edges = 0 -> ()
          | Ok edges ->
              (match kernels.flip edges !current with
               | Error message -> failure := Some message
               | Ok flipped -> current := flipped)
        end;
        if !failure = None && smoothing > 0. then begin
          match point_constraints ?cancel ~grain ~point_name ~edge_name !current with
          | Error message -> failure := Some message
          | Ok constrained ->
              (match Smooth.run ?cancel ~grain ~constrained_points:constrained
                  ~boundary:Smooth.Smooth_unshared ~iterations:1
                  ~mode:(Attribute_ops.Laplacian smoothing)
                  ~recompute_normals:false ~attributes:"P" !current with
               | Error error when Error.code error = "cancelled" ->
                   raise Cancel.Cancelled
               | Error error -> failure := Some (Error.to_string error)
               | Ok smoothed -> current := smoothed)
        end;
        if !failure = None && project then begin
          match project_to_reference ?cancel ~grain
              ~surface:(Option.get projection_surface)
              ~scratch:projection_scratch geometry !current with
          | Error message -> failure := Some message
          | Ok projected -> current := projected
        end;
        incr iteration
      done;
      match !failure with
      | Some message -> Error message
      | None ->
          let output = !current
              |> Geometry.without_attribute ~owner:Attribute.Point "N"
              |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
          let with_normals = if not recompute_point_normals then Ok output
            else Deform.normals ?cancel ~grain output in
          Result.bind with_normals (fun output ->
          Result.bind (install_outputs ?cancel ~grain ~target_length
              ~target_size_attribute ~edge_name ~output_hard_edges
              ~output_mesh_size ~output_quality output) (fun output ->
            Ok (output
              |> Geometry.without_group ~owner:Group.Point point_name
              |> Geometry.without_edge_group edge_name))))))))))))
  with
  | Invalid_argument message -> fail message
