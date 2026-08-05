open Prismel

type pairing = Bridge_by_order | Bridge_by_centroid

exception Invalid of string

let fail message = raise (Invalid message)
let get_ok = function Ok value -> value | Error message -> fail message

type path = {
  vertices : int array;
  closed : bool;
  primitive : int;
  key : int;
}

let checked_add label left right =
  if right < 0 || left > max_int - right then fail (label ^ " exceeds array limits");
  left + right

let checked_mul label left right =
  if left < 0 || right < 0 || (left <> 0 && right > max_int / left) then
    fail (label ^ " exceeds array limits");
  left * right

let reverse_values values =
  Array.init (Array.length values) (fun index ->
    values.(Array.length values - index - 1))

let validate_group label topology index group =
  if Edge_group.topology_data_id group <> Topology.data_id topology then
    fail (label ^ " edge group belongs to different topology");
  if Edge_group.length group <> Topology_index.edge_count index then
    fail (label ^ " edge group length does not match topology")

let extract_paths ?cancel label topology index group =
  validate_group label topology index group;
  let topology_view = Topology.Private.view topology
  and index_view = Topology_index.Private.view index
  and point_count = Topology.point_count topology
  and edge_count = Topology_index.edge_count index in
  let degree = Array.make point_count 0 in
  Edge_group.iter (fun edge ->
    let a = index_view.edge_a.(edge) and b = index_view.edge_b.(edge) in
    degree.(a) <- degree.(a) + 1;
    degree.(b) <- degree.(b) + 1) group;
  for point = 0 to point_count - 1 do
    if point land 4095 = 0 then Cancel.check_opt cancel;
    if degree.(point) > 2 then fail (Printf.sprintf
      "%s edge group branches at point %d" label point)
  done;
  let corner_for_point edge point =
    let first = index_view.edge_offsets.(edge)
    and last = index_view.edge_offsets.(edge + 1) in
    let best = ref max_int in
    for at = first to last - 1 do
      let vertex = index_view.edge_vertices.(at) in
      if topology_view.vertex_points.(vertex) = point then
        best := min !best vertex
      else
        let next = index_view.next_vertex.(vertex) in
        if next >= 0 && topology_view.vertex_points.(next) = point then
          best := min !best next
    done;
    if !best = max_int then fail (Printf.sprintf
      "%s edge %d has no corner at point %d" label edge point);
    !best in
  let next_unvisited_edge visited point previous =
    let first = index_view.point_edge_offsets.(point)
    and last = index_view.point_edge_offsets.(point + 1) in
    let found = ref (-1) in
    for at = first to last - 1 do
      let edge = index_view.point_edges.(at) in
      if edge <> previous && Edge_group.mem edge group && not visited.(edge)
          && (!found < 0 || edge < !found) then found := edge
    done;
    !found in
  let visited = Array.make edge_count false
  and paths = ref [] in
  let trace start first_edge =
    let vertices = ref (Array.make 16 0) in
    let count = ref 0 and current = ref start and edge = ref first_edge
    and closed = ref false and minimum_point = ref start in
    let push vertex =
      if !count = Array.length !vertices then begin
        let grown = Array.make (Array.length !vertices * 2) 0 in
        Array.blit !vertices 0 grown 0 !count;
        vertices := grown
      end;
      (!vertices).(!count) <- vertex;
      incr count in
    let running = ref true in
    while !running do
      if !count land 4095 = 0 then Cancel.check_opt cancel;
      if visited.(!edge) then fail (label ^ " edge traversal repeated an edge");
      push (corner_for_point !edge !current);
      visited.(!edge) <- true;
      let a = index_view.edge_a.(!edge) and b = index_view.edge_b.(!edge) in
      let next = if a = !current then b else if b = !current then a
        else fail (label ^ " edge traversal lost incidence") in
      minimum_point := min !minimum_point next;
      if next = start then begin
        closed := true; running := false
      end else begin
        let next_edge = next_unvisited_edge visited next !edge in
        if next_edge < 0 then begin
          push (corner_for_point !edge next);
          running := false
        end else begin
          current := next; edge := next_edge
        end
      end
    done;
    let vertices = Array.sub !vertices 0 !count in
    if (!closed && !count < 3) || (not !closed && !count < 2) then
      fail (label ^ " contains a degenerate path");
    let primitive = Topology_index.primitive_of_vertex index vertices.(0) in
    paths := { vertices; closed = !closed; primitive; key = !minimum_point }
      :: !paths in
  for point = 0 to point_count - 1 do
    if point land 4095 = 0 then Cancel.check_opt cancel;
    if degree.(point) = 1 then begin
      let edge = next_unvisited_edge visited point (-1) in
      if edge >= 0 then trace point edge
    end
  done;
  for edge = 0 to edge_count - 1 do
    if edge land 4095 = 0 then Cancel.check_opt cancel;
    if Edge_group.mem edge group && not visited.(edge) then
      trace (min index_view.edge_a.(edge) index_view.edge_b.(edge)) edge
  done;
  let paths = Array.of_list !paths in
  Array.sort (fun left right ->
    let order = Int.compare left.key right.key in
    if order <> 0 then order else Int.compare left.primitive right.primitive) paths;
  paths

let centroid positions topology path =
  let scale = Array.make 3 0. in
  Array.iter (fun vertex ->
    let point = topology.Topology.Private.vertex_points.(vertex) in
    scale.(0) <- Float.max scale.(0)
        (abs_float positions.Packed.Float3.Private.x.(point));
    scale.(1) <- Float.max scale.(1) (abs_float positions.y.(point));
    scale.(2) <- Float.max scale.(2) (abs_float positions.z.(point))) path.vertices;
  let sum = Array.make 3 0. in
  Array.iter (fun vertex ->
    let point = topology.Topology.Private.vertex_points.(vertex) in
    if scale.(0) <> 0. then sum.(0) <- sum.(0)
        +. (positions.Packed.Float3.Private.x.(point) /. scale.(0));
    if scale.(1) <> 0. then sum.(1) <- sum.(1)
        +. (positions.y.(point) /. scale.(1));
    if scale.(2) <> 0. then sum.(2) <- sum.(2)
        +. (positions.z.(point) /. scale.(2))) path.vertices;
  let inverse = 1. /. float_of_int (Array.length path.vertices) in
  (sum.(0) *. inverse *. scale.(0), sum.(1) *. inverse *. scale.(1),
   sum.(2) *. inverse *. scale.(2))

let pair_paths ?cancel pairing positions topology sources destinations =
  match pairing with
  | Bridge_by_order -> Array.copy destinations
  | Bridge_by_centroid ->
      let count = Array.length sources in
      let output = Array.make count destinations.(0)
      and source_order = Array.init count Fun.id
      and destination_order = Array.init count Fun.id in
      let source_centroids = Array.map (centroid positions topology) sources
      and destination_centroids = Array.map (centroid positions topology)
          destinations in
      let compare_centroid centroids left right =
        let lx, ly, lz = centroids.(left)
        and rx, ry, rz = centroids.(right) in
        let order = Float.compare lx rx in
        if order <> 0 then order else
        let order = Float.compare ly ry in
        if order <> 0 then order else
        let order = Float.compare lz rz in
        if order <> 0 then order else Int.compare left right in
      Array.sort (compare_centroid source_centroids) source_order;
      Array.sort (compare_centroid destination_centroids) destination_order;
      for rank = 0 to count - 1 do
        if rank land 4095 = 0 then Cancel.check_opt cancel;
        output.(source_order.(rank)) <- destinations.(destination_order.(rank))
      done;
      output

type divided_pair = {
  source_vertices : int array;
  destination_vertices : int array;
  keep_faces : bytes;
  face_count : int;
  source_primitive : int;
  closed : bool;
}

let[@inline always] interpolate left right weight =
  let delta = right -. left in
  if Float.is_finite delta then left +. (delta *. weight)
  else (left *. (1. -. weight)) +. (right *. weight)

let non_collinear ~tolerance x y z a b c =
  if a = b || b = c || c = a then false
  else begin
    let ux = x.(b) -. x.(a) and uy = y.(b) -. y.(a)
    and uz = z.(b) -. z.(a)
    and vx = x.(c) -. x.(a) and vy = y.(c) -. y.(a)
    and vz = z.(c) -. z.(a) in
    let us = Float.max (abs_float ux)
        (Float.max (abs_float uy) (abs_float uz))
    and vs = Float.max (abs_float vx)
        (Float.max (abs_float vy) (abs_float vz)) in
    if us = 0. || vs = 0. then false
    else begin
      let ux = ux /. us and uy = uy /. us and uz = uz /. us
      and vx = vx /. vs and vy = vy /. vs and vz = vz /. vs in
      let cx = (uy *. vz) -. (uz *. vy)
      and cy = (uz *. vx) -. (ux *. vz)
      and cz = (ux *. vy) -. (uy *. vx) in
      let cross = sqrt ((cx *. cx) +. (cy *. cy) +. (cz *. cz))
      and ul = sqrt ((ux *. ux) +. (uy *. uy) +. (uz *. uz))
      and vl = sqrt ((vx *. vx) +. (vy *. vy) +. (vz *. vz)) in
      cross > tolerance *. ul *. vl
    end
  end

let materialize_divided ?cancel ~grain ~divisions ~collinearity_tolerance
    ~keep_input ?output_group ~recompute_normals geometry topology_value topology
    source_positions sources destinations ~connect_closest_ends ~pairing_shift =
  let pair_count = Array.length sources
  and source_points = Geometry.point_count geometry
  and source_vertices_count = Geometry.vertex_count geometry
  and source_primitives = Geometry.primitive_count geometry in
  let aligned = Array.make pair_count ([||], [||]) in
  Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(pair_count - 1) (fun pair ->
    Cancel.check_opt cancel;
    let source = sources.(pair) and destination = destinations.(pair) in
    aligned.(pair) <- Poly_loft.Private.align_indexed ?cancel
        ~connect_closest:connect_closest_ends source_positions topology
        ~a_vertices:source.vertices ~a_primitive:source.primitive
        ~a_closed:source.closed ~b_vertices:destination.vertices
        ~b_primitive:destination.primitive ~b_closed:destination.closed
        ~pairing_shift);
  let point_offsets = Array.make (pair_count + 1) 0 in
  for pair = 0 to pair_count - 1 do
    let source, destination = aligned.(pair) in
    if Array.length source <> Array.length destination then fail (Printf.sprintf
      "bridge %d divisions require equal boundary cardinality" pair);
    point_offsets.(pair + 1) <- checked_add "intermediate point count"
        point_offsets.(pair)
        (checked_mul "intermediate point count" (divisions - 1)
           (Array.length source))
  done;
  let output_points = checked_add "output point count" source_points
      point_offsets.(pair_count) in
  let x = Array.make output_points 0. and y = Array.make output_points 0.
  and z = Array.make output_points 0. in
  Array.blit source_positions.Packed.Float3.Private.x 0 x 0 source_points;
  Array.blit source_positions.y 0 y 0 source_points;
  Array.blit source_positions.z 0 z 0 source_points;
  let attributes = Geometry.attributes geometry
  and groups = Geometry.groups geometry in
  let needs_point_maps = List.exists (fun attribute ->
      Attribute.owner attribute = Attribute.Point
      && Attribute.name attribute <> "N") attributes
      || List.exists (fun group -> Group.owner group = Group.Point) groups in
  let point_left = if needs_point_maps then Array.init output_points Fun.id else [||]
  and point_right = if needs_point_maps then Array.init output_points Fun.id else [||]
  and point_weight = if needs_point_maps then Array.make output_points 0. else [||] in
  let fill_points pair =
    let source, destination = aligned.(pair) in
    let count = Array.length source
    and base = source_points + point_offsets.(pair) in
    let fill item =
      let row = (item / count) + 1 and local = item mod count in
      let left = topology.Topology.Private.vertex_points.(source.(local))
      and right = topology.vertex_points.(destination.(local)) in
      let weight = float_of_int row /. float_of_int divisions
      and output = base + item in
      x.(output) <- interpolate source_positions.x.(left)
          source_positions.x.(right) weight;
      y.(output) <- interpolate source_positions.y.(left)
          source_positions.y.(right) weight;
      z.(output) <- interpolate source_positions.z.(left)
          source_positions.z.(right) weight;
      if needs_point_maps then begin
        point_left.(output) <- left; point_right.(output) <- right;
        point_weight.(output) <- weight
      end in
    let items = checked_mul "intermediate point count" (divisions - 1) count in
    if pair_count = 1 && items > 0 then
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(items - 1) fill
    else for item = 0 to items - 1 do fill item done in
  if pair_count = 1 then fill_points 0
  else Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(pair_count - 1) fill_points;
  let point_of pair row local =
    let source, destination = aligned.(pair) in
    if row = 0 then topology.vertex_points.(source.(local))
    else if row = divisions then topology.vertex_points.(destination.(local))
    else source_points + point_offsets.(pair)
        + ((row - 1) * Array.length source) + local in
  let make_pair pair =
    let source, _ = aligned.(pair) in
    let count = Array.length source
    and segments = if sources.(pair).closed then Array.length source
      else Array.length source - 1 in
    let maximum = checked_mul "divided bridge face count" divisions segments in
    let keep_faces = Bytes.make maximum '\000' in
    let check_face face =
      if face land 4095 = 0 then Cancel.check_opt cancel;
      let row = face / segments and local = face mod segments
      and next = (face mod segments + 1) mod count in
      let a = point_of pair row local and b = point_of pair row next
      and c = point_of pair (row + 1) next
      and d = point_of pair (row + 1) local in
      let distinct = a <> b && b <> c && c <> d && d <> a
          && a <> c && b <> d in
      if distinct && (collinearity_tolerance = 0.
          || non_collinear ~tolerance:collinearity_tolerance x y z a b c
          || non_collinear ~tolerance:collinearity_tolerance x y z a c d) then begin
        Bytes.set keep_faces face '\001'
      end in
    if pair_count = 1 && maximum > 0 then
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(maximum - 1) check_face
    else for face = 0 to maximum - 1 do check_face face done;
    let face_count = ref 0 in
    Bytes.iter (fun keep -> if keep <> '\000' then incr face_count) keep_faces;
    { source_vertices = fst aligned.(pair);
      destination_vertices = snd aligned.(pair);
      keep_faces; face_count = !face_count;
      source_primitive = sources.(pair).primitive;
      closed = sources.(pair).closed } in
  let pairs = if pair_count = 1 then [|make_pair 0|]
    else Parallel.init_array ~grain:1 pair_count make_pair in
  let pair_face_offsets = Array.make (pair_count + 1) 0 in
  for pair = 0 to pair_count - 1 do
    pair_face_offsets.(pair + 1) <- checked_add "generated primitive count"
        pair_face_offsets.(pair) pairs.(pair).face_count
  done;
  let prefix_primitives = if keep_input then source_primitives else 0
  and prefix_vertices = if keep_input then source_vertices_count else 0
  and generated_primitives = pair_face_offsets.(pair_count) in
  let output_primitives = checked_add "output primitive count"
      prefix_primitives generated_primitives
  and output_vertices = checked_add "output vertex count" prefix_vertices
      (checked_mul "generated vertex count" generated_primitives 4) in
  let primitive_offsets = Array.make (output_primitives + 1) 0
  and primitive_kinds = Array.make output_primitives Topology.Polygon
  and vertex_points = Array.make output_vertices 0
  and primitive_map = Array.make output_primitives 0 in
  let needs_vertex_maps = List.exists (fun attribute ->
      Attribute.owner attribute = Attribute.Vertex
      && Attribute.name attribute <> "N") attributes
      || List.exists (fun group -> Group.owner group = Group.Vertex) groups in
  let vertex_left = if needs_vertex_maps then Array.make output_vertices 0 else [||]
  and vertex_right = if needs_vertex_maps then Array.make output_vertices 0 else [||]
  and vertex_weight = if needs_vertex_maps then Array.make output_vertices 0. else [||] in
  if keep_input then begin
    Array.blit topology.primitive_offsets 0 primitive_offsets 0
      (source_primitives + 1);
    for primitive = 0 to source_primitives - 1 do
      primitive_kinds.(primitive) <- Topology.primitive_kind topology_value primitive;
      primitive_map.(primitive) <- primitive
    done;
    if source_vertices_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
        ~finish:(source_vertices_count - 1) (fun vertex ->
      vertex_points.(vertex) <- topology.vertex_points.(vertex);
      if needs_vertex_maps then begin
        vertex_left.(vertex) <- vertex; vertex_right.(vertex) <- vertex
      end)
  end;
  for primitive = prefix_primitives to output_primitives do
    primitive_offsets.(primitive) <- prefix_vertices
        + ((primitive - prefix_primitives) * 4)
  done;
  let fill_pair pair =
    let plan = pairs.(pair) in
    let count = Array.length plan.source_vertices in
    let segments = if plan.closed then count else count - 1
    and primitive = ref (prefix_primitives + pair_face_offsets.(pair)) in
    for face = 0 to Bytes.length plan.keep_faces - 1 do
      if Bytes.get plan.keep_faces face <> '\000' then begin
        let row = face / segments and local = face mod segments
        and next = (face mod segments + 1) mod count in
        let output = !primitive and target = primitive_offsets.(!primitive) in
        let set corner row local =
          vertex_points.(target + corner) <- point_of pair row local;
          if needs_vertex_maps then begin
            vertex_left.(target + corner) <- plan.source_vertices.(local);
            vertex_right.(target + corner) <- plan.destination_vertices.(local);
            vertex_weight.(target + corner) <-
              float_of_int row /. float_of_int divisions
          end in
        set 0 row local; set 1 row next;
        set 2 (row + 1) next; set 3 (row + 1) local;
        primitive_map.(output) <- plan.source_primitive;
        incr primitive
      end
    done in
  if pair_count = 1 then fill_pair 0
  else Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(pair_count - 1) fill_pair;
  let output_topology = Topology.create_owned ~point_count:output_points
      ~vertex_points ~primitive_offsets ~primitive_kinds |> get_ok in
  let output_positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let output_attributes = List.filter_map (fun attribute ->
    match Attribute.owner attribute with
    | Attribute.Point when Attribute.name attribute = "N" -> None
    | Attribute.Vertex when Attribute.name attribute = "N" -> None
    | Attribute.Point -> Some (Curve_ops.interpolate_attribute ?cancel ~grain
        point_left point_right point_weight [||] [||] [||] attribute)
    | Attribute.Vertex -> Some (Curve_ops.interpolate_attribute ?cancel ~grain
        [||] [||] [||] vertex_left vertex_right vertex_weight attribute)
    | Attribute.Primitive -> Some (Topology_remap.attribute ?cancel ~grain
        primitive_map attribute)
    | Attribute.Detail -> Some attribute) attributes in
  let point_nearest = lazy (Array.init output_points (fun point ->
      if point_weight.(point) < 0.5 then point_left.(point)
      else point_right.(point)))
  and vertex_nearest = lazy (Array.init output_vertices (fun vertex ->
      if vertex_weight.(vertex) < 0.5 then vertex_left.(vertex)
      else vertex_right.(vertex))) in
  let output_groups = List.map (fun group -> match Group.owner group with
    | Group.Point -> Topology_remap.group ?cancel ~grain (Lazy.force point_nearest) group
    | Group.Vertex -> Topology_remap.group ?cancel ~grain
        (Lazy.force vertex_nearest) group
    | Group.Primitive -> Topology_remap.group ?cancel ~grain primitive_map group)
      groups in
  let edge_groups = match Geometry.edge_groups geometry with
    | [] -> []
    | edge_groups ->
        let source_index = Topology_index.create ?cancel topology_value
        and target_index = Topology_index.create ?cancel output_topology
        and point_map = Array.init source_points Fun.id in
        List.map (fun group -> Edge_group.remap ?cancel ~source_index
          ~target_topology:output_topology ~target_index ~point_map group |> get_ok)
          edge_groups in
  let output = Geometry.create ~positions:output_positions ~topology:output_topology
      ~attributes:output_attributes ~groups:output_groups ~edge_groups () |> get_ok in
  let output = match output_group with
    | None -> output
    | Some name -> Geometry.with_group
        (Group.init ~grain ~owner:Group.Primitive ~name output_primitives
          (fun primitive -> primitive >= prefix_primitives)) output |> get_ok in
  let had_point_normals = Geometry.find_attribute ~owner:Attribute.Point "N"
      geometry <> None
  and had_vertex_normals = Geometry.find_attribute ~owner:Attribute.Vertex "N"
      geometry <> None in
  if not recompute_normals || not (had_point_normals || had_vertex_normals)
  then Ok output
  else Normal_ops.run ?cancel ~grain
      ~owner:(if had_point_normals then Attribute.Point else Attribute.Vertex) output

let run ?cancel ?(grain = 16_384) ~source ~destination
    ?(pairing = Bridge_by_order) ?(connect_closest_ends = true)
    ?(minimize = Poly_loft.Two_point_distance) ?(reverse_source = false)
    ?(reverse_destination = false) ?(pairing_shift = 0)
    ?(divisions = 1) ?(keep_input = true) ?output_group
    ?(collinearity_tolerance = 0.)
    ?(recompute_normals = true) geometry =
  try
    if grain <= 0 then fail "grain must be positive";
    if divisions <= 0 then fail "divisions must be positive";
    if not (Float.is_finite collinearity_tolerance)
        || collinearity_tolerance < 0. || collinearity_tolerance > 1. then
      fail "collinearity tolerance must be finite and between zero and one";
    (match output_group with
     | Some name when String.trim name = "" -> fail "output group name is empty"
     | _ -> ());
    Cancel.check_opt cancel;
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value
    and index = Topology_index.create ?cancel topology_value in
    validate_group "source" topology_value index source;
    validate_group "destination" topology_value index destination;
    Edge_group.iter (fun edge -> if Edge_group.mem edge destination then
      fail (Printf.sprintf "source and destination overlap at edge %d" edge)) source;
    let sources = extract_paths ?cancel "source" topology_value index source
    and destinations = extract_paths ?cancel "destination" topology_value index
        destination in
    if Array.length sources <> Array.length destinations then fail (Printf.sprintf
      "source has %d components but destination has %d"
      (Array.length sources) (Array.length destinations));
    let pair_count = Array.length sources in
    if pair_count = 0 then Ok geometry else begin
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let validate_finite label path =
        Array.iter (fun vertex ->
          let point = topology.vertex_points.(vertex) in
          if not (Float.is_finite positions.x.(point)
              && Float.is_finite positions.y.(point)
              && Float.is_finite positions.z.(point)) then fail (Printf.sprintf
            "%s point %d is not finite" label point)) path.vertices in
      Array.iter (validate_finite "source") sources;
      Array.iter (validate_finite "destination") destinations;
      let destinations = pair_paths ?cancel pairing positions topology sources
          destinations in
      for pair = 0 to pair_count - 1 do
        if sources.(pair).closed <> destinations.(pair).closed then fail
          (Printf.sprintf "bridge %d mixes an open path with a closed loop" pair);
        if pairing_shift <> 0 && not sources.(pair).closed then fail
          "pairing shift requires closed loops"
      done;
      let prepare should_reverse path =
        if should_reverse then
          { path with vertices = reverse_values path.vertices }
        else path in
      let sources = Array.map (prepare reverse_source) sources
      and destinations = Array.map (prepare reverse_destination) destinations in
      if divisions > 1 then
        materialize_divided ?cancel ~grain ~divisions ~collinearity_tolerance
          ~keep_input ?output_group ~recompute_normals geometry topology_value
          topology positions sources destinations ~connect_closest_ends
          ~pairing_shift
      else begin
      let build pair =
        Cancel.check_opt cancel;
        let source = sources.(pair) and destination = destinations.(pair) in
        Poly_loft.Private.build_polygon_plan_indexed ?cancel
            ~connect_closest:connect_closest_ends ~minimize
            ~tolerance:collinearity_tolerance positions topology
            ~a_vertices:source.vertices ~a_primitive:source.primitive
            ~a_closed:source.closed ~b_vertices:destination.vertices
            ~b_primitive:destination.primitive ~b_closed:destination.closed
            ~pairing_shift in
      let first_plan = build 0 in
      let plans = Array.make pair_count first_plan in
      if pair_count > 1 then
        Parallel.for_ ~chunk_size:1 ~start:1 ~finish:(pair_count - 1)
          (fun pair -> plans.(pair) <- build pair);
      let plan_primitive_offsets = Array.make (pair_count + 1) 0
      and plan_corner_offsets = Array.make (pair_count + 1) 0 in
      for pair = 0 to pair_count - 1 do
        plan_primitive_offsets.(pair + 1) <- checked_add "bridge primitive count"
            plan_primitive_offsets.(pair)
            (Poly_loft.Private.primitive_count plans.(pair));
        plan_corner_offsets.(pair + 1) <- checked_add "bridge corner count"
            plan_corner_offsets.(pair) (Poly_loft.Private.corner_count plans.(pair))
      done;
      let source_primitives = Geometry.primitive_count geometry
      and source_vertices = Geometry.vertex_count geometry in
      let prefix_primitives = if keep_input then source_primitives else 0
      and prefix_vertices = if keep_input then source_vertices else 0 in
      let generated_primitives = plan_primitive_offsets.(pair_count)
      and generated_vertices = plan_corner_offsets.(pair_count) in
      let output_primitives = checked_add "output primitive count"
          prefix_primitives generated_primitives
      and output_vertices = checked_add "output vertex count"
          prefix_vertices generated_vertices in
      let primitive_offsets = Array.make (output_primitives + 1) 0
      and primitive_kinds = Array.make output_primitives Topology.Polygon
      and vertex_points = Array.make output_vertices 0
      and vertex_map = Array.make output_vertices 0
      and primitive_map = Array.make output_primitives 0 in
      if keep_input then begin
        Array.blit topology.primitive_offsets 0 primitive_offsets 0
          (source_primitives + 1);
        for primitive = 0 to source_primitives - 1 do
          primitive_kinds.(primitive) <- Topology.primitive_kind topology_value primitive;
          primitive_map.(primitive) <- primitive
        done;
        if source_vertices > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(source_vertices - 1) (fun vertex ->
          vertex_points.(vertex) <- topology.vertex_points.(vertex);
          vertex_map.(vertex) <- vertex)
      end;
      Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(pair_count - 1) (fun pair ->
        Cancel.check_opt cancel;
        let plan = plans.(pair)
        and primitive_first = prefix_primitives + plan_primitive_offsets.(pair)
        and vertex_first = prefix_vertices + plan_corner_offsets.(pair)
        and corners = Poly_loft.Private.corners plans.(pair)
        and arity = Poly_loft.Private.arity plans.(pair) in
        for local = 0 to Poly_loft.Private.primitive_count plan - 1 do
          let primitive = primitive_first + local
          and target = vertex_first + (local * arity)
          and source_at = local * arity in
          primitive_offsets.(primitive) <- target;
          primitive_map.(primitive) <- Poly_loft.Private.source_primitive plan;
          for corner = 0 to arity - 1 do
            let source_vertex = corners.(source_at + corner) in
            vertex_map.(target + corner) <- source_vertex;
            vertex_points.(target + corner) <- topology.vertex_points.(source_vertex)
          done
        done);
      primitive_offsets.(output_primitives) <- output_vertices;
      let output_topology = Topology.create_owned ~point_count:topology.point_count
          ~vertex_points ~primitive_offsets ~primitive_kinds |> get_ok in
      let output = Topology_remap.preserving_points ?cancel ~grain
          ~topology:output_topology ~vertex_map ~primitive_map geometry |> get_ok in
      let output = match output_group with
        | None -> output
        | Some name -> Geometry.with_group
            (Group.init ~grain ~owner:Group.Primitive ~name output_primitives
              (fun primitive -> primitive >= prefix_primitives)) output |> get_ok in
      let had_point_normals = Geometry.find_attribute ~owner:Attribute.Point "N"
          geometry <> None
      and had_vertex_normals = Geometry.find_attribute ~owner:Attribute.Vertex "N"
          geometry <> None in
      let output = output
          |> Geometry.without_attribute ~owner:Attribute.Point "N"
          |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
      if not recompute_normals || not (had_point_normals || had_vertex_normals)
      then Ok output
      else Normal_ops.run ?cancel ~grain
          ~owner:(if had_point_normals then Attribute.Point else Attribute.Vertex)
          output
      end
    end
  with Invalid message -> Error ("Pdk.Ops.poly_bridge: " ^ message)
