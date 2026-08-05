open Prismel

type end_mode = Open | Close | Close_straight | Unroll | Unroll_new
type cut_mode = Inside | Outside | Inside_and_outside
type parameter_attribute_mode = Replace | Scale

type curve_join_end = Join_curve_start | Join_curve_end

type curve_join_pick = {
  primitive : int;
  end_ : curve_join_end;
}

exception Curve_error of string
let fail message = raise (Curve_error message)
let finite = Float.is_finite

let run_ranges ?(grain = 16_384) count operation =
  if grain <= 0 then fail "grain must be positive";
  let ranges = (count + grain - 1) / grain in
  if ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(ranges - 1)
    (fun range ->
      let first = range * grain and last = min count ((range + 1) * grain) in
      operation first last)

let validate_selection operation selection primitive_count =
  match selection with
  | None -> ()
  | Some group ->
      if Group.owner group <> Group.Primitive then
        fail (operation ^ " selection must own primitives");
      if Group.length group <> primitive_count then
        fail (operation ^ " selection length does not match primitive count")

let selected selection primitive = match selection with
  | None -> true
  | Some group -> Group.mem primitive group

let map_array ?cancel ?grain mapping source =
  let count = Array.length mapping in
  if count = 0 then [||]
  else begin
    let output = Array.make count source.(mapping.(0)) in
    run_ranges ?grain count (fun first last ->
      Cancel.check_opt cancel;
      for index = first to last - 1 do
        output.(index) <- source.(mapping.(index))
      done);
    output
  end

let remap_attribute ?cancel ?grain mapping attribute =
  let storage = match Attribute.Private.storage attribute with
    | Attribute.Float values -> Attribute.Float (map_array ?cancel ?grain mapping values)
    | Attribute.Int values -> Attribute.Int (map_array ?cancel ?grain mapping values)
    | Attribute.Int_array values ->
        Attribute.Int_array (Ragged_ops.remap_int ?cancel ?grain mapping values)
    | Attribute.Float_array values ->
        Attribute.Float_array (Ragged_ops.remap_float ?cancel ?grain mapping values)
    | Attribute.Text values -> Attribute.Text (map_array ?cancel ?grain mapping values)
    | Attribute.Float2 values ->
        let values = Packed.Float2.Private.view values in
        Attribute.Float2 (Packed.Float2.of_owned
          ~x:(map_array ?cancel ?grain mapping values.x)
          ~y:(map_array ?cancel ?grain mapping values.y) |> Result.get_ok)
    | Attribute.Float3 values ->
        let values = Packed.Float3.Private.view values in
        Attribute.Float3 (Packed.Float3.Private.of_owned_exn
          ~x:(map_array ?cancel ?grain mapping values.x)
          ~y:(map_array ?cancel ?grain mapping values.y)
          ~z:(map_array ?cancel ?grain mapping values.z))
    | Attribute.Float4 values ->
        let values = Packed.Float4.Private.view values in
        Attribute.Float4 (Packed.Float4.of_owned
          ~x:(map_array ?cancel ?grain mapping values.x)
          ~y:(map_array ?cancel ?grain mapping values.y)
          ~z:(map_array ?cancel ?grain mapping values.z)
          ~w:(map_array ?cancel ?grain mapping values.w) |> Result.get_ok) in
  Attribute.create_owned ~name:(Attribute.name attribute)
    ~owner:(Attribute.owner attribute) storage |> Result.get_ok

let radix_sort_edges ?cancel index_view point_count edges =
  let length = Array.length edges in
  if length < 2 then ()
  else if length < 4_096 then
    Array.sort (fun left right ->
      let by_a = Int.compare index_view.Topology_index.Private.edge_a.(left)
          index_view.edge_a.(right) in
      if by_a <> 0 then by_a
      else Int.compare index_view.edge_b.(left) index_view.edge_b.(right)) edges
  else begin
    let maximum = max 0 (point_count - 1) in
    let rec pass_count value count =
      if value = 0 then max 1 count
      else pass_count (value lsr 16) (count + 1) in
    let passes = pass_count maximum 0 in
    let scratch = Array.make length 0 and counts = Array.make 65_536 0 in
    let sort_key key =
      let source = ref edges and target = ref scratch in
      for pass = 0 to passes - 1 do
        Cancel.check_opt cancel;
        Array.fill counts 0 (Array.length counts) 0;
        let shift = pass * 16 in
        for at = 0 to length - 1 do
          if at land 16_383 = 0 then Cancel.check_opt cancel;
          let bucket = (key (!source).(at) lsr shift) land 0xffff in
          counts.(bucket) <- counts.(bucket) + 1
        done;
        let offset = ref 0 in
        for bucket = 0 to Array.length counts - 1 do
          let size = counts.(bucket) in
          counts.(bucket) <- !offset;
          offset := !offset + size
        done;
        for at = 0 to length - 1 do
          if at land 16_383 = 0 then Cancel.check_opt cancel;
          let edge = (!source).(at) in
          let bucket = (key edge lsr shift) land 0xffff in
          (!target).(counts.(bucket)) <- edge;
          counts.(bucket) <- counts.(bucket) + 1
        done;
        let previous = !source in
        source := !target;
        target := previous
      done;
      if !source != edges then Array.blit !source 0 edges 0 length
    in
    (* Stable least-significant-digit sorting makes the second key primary. *)
    sort_key (fun edge -> index_view.edge_b.(edge));
    sort_key (fun edge -> index_view.edge_a.(edge))
  end

let segment_length (positions : Packed.Float3.Private.view) a b =
  if not (finite positions.x.(a)
      && finite positions.y.(a) && finite positions.z.(a)
      && finite positions.x.(b) && finite positions.y.(b)
      && finite positions.z.(b)) then
    fail "curve length requires finite representable positions";
  let dx = positions.x.(b) -. positions.x.(a)
  and dy = positions.y.(b) -. positions.y.(a)
  and dz = positions.z.(b) -. positions.z.(a) in
  let scale = max (abs_float dx) (max (abs_float dy) (abs_float dz)) in
  if not (finite scale) then
    fail "curve length requires finite representable positions";
  if scale = 0. then 0.
  else begin
    let x = dx /. scale and y = dy /. scale and z = dz /. scale in
    let length = scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
    if not (finite length) then
      fail "curve length requires finite representable positions";
    length
  end

let with_length_attribute ?cancel ?grain ~name geometry =
  try
    (match grain with Some value when value <= 0 -> fail "grain must be positive"
     | _ -> ());
    if String.trim name = "" then fail "curve length attribute name must not be empty";
    Cancel.check_opt cancel;
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value
    and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let primitive_count = Geometry.primitive_count geometry in
    let lengths = Array.make primitive_count 0. in
    run_ranges ?grain primitive_count (fun first last ->
      Cancel.check_opt cancel;
      for primitive = first to last - 1 do
        let first_vertex = topology.primitive_offsets.(primitive)
        and last_vertex = topology.primitive_offsets.(primitive + 1) in
        let sum = ref 0. and correction = ref 0. in
        let add edge_length =
          let adjusted = edge_length -. !correction in
          let next = !sum +. adjusted in
          correction := (next -. !sum) -. adjusted;
          sum := next in
        for vertex = first_vertex to last_vertex - 2 do
          add (segment_length positions topology.vertex_points.(vertex)
            topology.vertex_points.(vertex + 1))
        done;
        if Topology.primitive_kind topology_value primitive <> Topology.Open_polyline
            && last_vertex - first_vertex > 1 then
          add (segment_length positions topology.vertex_points.(last_vertex - 1)
            topology.vertex_points.(first_vertex));
        if not (finite !sum) then
          fail "curve length requires finite representable positions";
        lengths.(primitive) <- !sum
      done);
    let attribute = Attribute.create_owned ~name ~owner:Attribute.Primitive
        (Attribute.Float lengths) |> Result.get_ok in
    Geometry.create ~positions:(Geometry.positions geometry)
      ~topology:(Geometry.topology geometry)
      ~attributes:(attribute :: Geometry.attributes geometry)
      ~groups:(Geometry.groups geometry) ~edge_groups:(Geometry.edge_groups geometry)
      ()
  with Curve_error message -> Error message

let interpolate_array ?cancel ?grain left right weight source =
  let output = Array.make (Array.length weight) 0. in
  run_ranges ?grain (Array.length output) (fun first last ->
    Cancel.check_opt cancel;
    for index = first to last - 1 do
      let left_value = source.(left.(index))
      and right_value = source.(right.(index)) in
      let delta = right_value -. left_value in
      output.(index) <- if finite delta
        then left_value +. (delta *. weight.(index))
        else (left_value *. (1. -. weight.(index)))
          +. (right_value *. weight.(index))
    done);
  output

let nearest_array ?cancel ?grain left right weight source =
  let count = Array.length weight in
  if count = 0 then [||]
  else begin
    let output = Array.make count source.(left.(0)) in
    run_ranges ?grain count (fun first last ->
      Cancel.check_opt cancel;
      for index = first to last - 1 do
        output.(index) <- source.
          ((if weight.(index) < 0.5 then left else right).(index))
      done);
    output
  end

let interpolate_attribute ?cancel ?grain point_left point_right point_weight
    vertex_left vertex_right vertex_weight attribute =
  let mapping = match Attribute.owner attribute with
    | Attribute.Point -> Some (point_left, point_right, point_weight)
    | Attribute.Vertex -> Some (vertex_left, vertex_right, vertex_weight)
    | Attribute.Primitive | Attribute.Detail -> None in
  match mapping with
  | None -> attribute
  | Some (left, right, weight) ->
      let storage = match Attribute.Private.storage attribute with
        | Attribute.Float values ->
            Attribute.Float (interpolate_array ?cancel ?grain left right weight values)
        | Attribute.Int values ->
            Attribute.Int (nearest_array ?cancel ?grain left right weight values)
        | Attribute.Int_array values ->
            let mapping = Array.init (Array.length weight) (fun index ->
              (if weight.(index) < 0.5 then left else right).(index)) in
            Attribute.Int_array
              (Ragged_ops.remap_int ?cancel ?grain mapping values)
        | Attribute.Float_array values ->
            let mapping = Array.init (Array.length weight) (fun index ->
              (if weight.(index) < 0.5 then left else right).(index)) in
            Attribute.Float_array
              (Ragged_ops.remap_float ?cancel ?grain mapping values)
        | Attribute.Text values ->
            Attribute.Text (nearest_array ?cancel ?grain left right weight values)
        | Attribute.Float2 values ->
            let values = Packed.Float2.Private.view values in
            Attribute.Float2 (Packed.Float2.of_owned
              ~x:(interpolate_array ?cancel ?grain left right weight values.x)
              ~y:(interpolate_array ?cancel ?grain left right weight values.y)
              |> Result.get_ok)
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            let x = interpolate_array ?cancel ?grain left right weight values.x
            and y = interpolate_array ?cancel ?grain left right weight values.y
            and z = interpolate_array ?cancel ?grain left right weight values.z in
            if String.equal (Attribute.name attribute) "N" then
              run_ranges ?grain (Array.length x) (fun first last ->
                for index = first to last - 1 do
                  let length = sqrt (x.(index) *. x.(index)
                      +. y.(index) *. y.(index) +. z.(index) *. z.(index)) in
                  if length > 1e-20 then begin
                    x.(index) <- x.(index) /. length;
                    y.(index) <- y.(index) /. length;
                    z.(index) <- z.(index) /. length
                  end
                done);
            Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)
        | Attribute.Float4 values ->
            let values = Packed.Float4.Private.view values in
            Attribute.Float4 (Packed.Float4.of_owned
              ~x:(interpolate_array ?cancel ?grain left right weight values.x)
              ~y:(interpolate_array ?cancel ?grain left right weight values.y)
              ~z:(interpolate_array ?cancel ?grain left right weight values.z)
              ~w:(interpolate_array ?cancel ?grain left right weight values.w)
              |> Result.get_ok) in
      Attribute.create_owned ~name:(Attribute.name attribute)
        ~owner:(Attribute.owner attribute) storage |> Result.get_ok

type carve_parameters = Constant of float * float
  | Varying of {
      first : float;
      last : float;
      first_values : float array option;
      last_values : float array option;
      attribute_mode : parameter_attribute_mode;
    }

let resolve_carve_parameters ?cancel ~allow_equal ~first ~last ?first_attribute
    ?last_attribute ~attribute_mode ~selected geometry =
  let primitive_count = Geometry.primitive_count geometry in
  let values label name = match Geometry.find_attribute
      ~owner:Attribute.Primitive name geometry with
    | None -> fail (Printf.sprintf "Curve Carve %s attribute %S was not found" label name)
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Float values -> values
         | _ -> fail (Printf.sprintf
             "Curve Carve %s attribute %S must be primitive float" label name)) in
  let first_values = Option.map (values "first") first_attribute
  and last_values = Option.map (values "second") last_attribute in
  match first_values, last_values with
  | None, None -> Constant (first, last)
  | _ ->
      let apply base values primitive = match values with
        | None -> base
        | Some values -> match attribute_mode with
            | Replace -> values.(primitive)
            | Scale -> base *. values.(primitive) in
      for primitive = 0 to primitive_count - 1 do
        if primitive land 16_383 = 0 then Cancel.check_opt cancel;
        let a = apply first first_values primitive
        and b = apply last last_values primitive in
        if selected primitive && (not (finite a && finite b) || a < 0. || b > 1.
            || (if allow_equal then a > b else a >= b)) then
          fail (Printf.sprintf
            "Curve Carve primitive %d parameters require finite 0 <= first %s last <= 1"
            primitive (if allow_equal then "<=" else "<"))
      done;
      Varying { first; last; first_values; last_values; attribute_mode }

let carve_parameter parameters primitive = match parameters with
  | Constant (first, last) -> first, last
  | Varying { first; last; first_values; last_values; attribute_mode } ->
      let apply base values = match values with
        | None -> base
        | Some values -> match attribute_mode with
            | Replace -> values.(primitive)
            | Scale -> base *. values.(primitive) in
      apply first first_values, apply last last_values

let extract_points_interpolated ?cancel ?grain ?primitives
    ?(relative_arc_length = true)
    ?(first = 0.) ?(last = 1.) ?first_attribute ?last_attribute
    ?(attribute_mode = Replace) ?(divisions = 1) ?(keep_original = false) geometry =
  try
    (match grain with Some value when value <= 0 -> fail "grain must be positive"
     | _ -> ());
    if divisions <= 0 then fail "Curve Carve extraction divisions must be positive";
    if not (finite first && finite last) || first < 0. || last > 1.
        || first > last then
      fail "Curve Carve extraction requires finite 0 <= first <= last <= 1";
    Cancel.check_opt cancel;
    let source_topology = Geometry.topology geometry in
    let source = Topology.Private.view source_topology in
    let primitive_count = Topology.primitive_count source_topology in
    validate_selection "Curve Carve" primitives primitive_count;
    let parameters = resolve_carve_parameters ?cancel ~allow_equal:true ~first ~last
        ?first_attribute ?last_attribute ~attribute_mode
        ~selected:(selected primitives) geometry in
    let selected_count = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        incr selected_count;
        if Topology.primitive_kind source_topology primitive = Topology.Polygon then
          fail (Printf.sprintf
            "Curve Carve primitive %d is a polygon, not a polygon curve" primitive)
      end
    done;
    if !selected_count = 0 then Ok geometry
    else if !selected_count > max_int / divisions then
      fail "Curve Carve extraction cardinality exceeds OCaml array limits"
    else begin
      let extract_count = !selected_count * divisions in
      let keep_primitive primitive = keep_original
          || not (selected primitives primitive) in
      let retained_primitive_count = primitive_count
          - if keep_original then 0 else !selected_count in
      let primitive_map = Array.make retained_primitive_count 0
      and primitive_offsets = Array.make (retained_primitive_count + 1) 0
      and primitive_kinds = Array.make retained_primitive_count
          Topology.Open_polyline in
      let retained_vertex_count = ref 0 and target_primitive = ref 0 in
      for primitive = 0 to primitive_count - 1 do
        if keep_primitive primitive then begin
          let size = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          if !retained_vertex_count > max_int - size then
            fail "Curve Carve extraction topology exceeds OCaml array limits";
          primitive_map.(!target_primitive) <- primitive;
          retained_vertex_count := !retained_vertex_count + size;
          primitive_offsets.(!target_primitive + 1) <- !retained_vertex_count;
          primitive_kinds.(!target_primitive) <-
            Topology.primitive_kind source_topology primitive;
          incr target_primitive
        end
      done;
      let vertex_map = Array.make !retained_vertex_count 0
      and vertex_points = Array.make !retained_vertex_count 0 in
      run_ranges ?grain retained_primitive_count (fun first_target last_target ->
        Cancel.check_opt cancel;
        for target = first_target to last_target - 1 do
          let primitive = primitive_map.(target) in
          let output = primitive_offsets.(target)
          and source_first = source.primitive_offsets.(primitive)
          and source_last = source.primitive_offsets.(primitive + 1) in
          for vertex = source_first to source_last - 1 do
            let target_vertex = output + vertex - source_first in
            vertex_map.(target_vertex) <- vertex;
            vertex_points.(target_vertex) <- source.vertex_points.(vertex)
          done
        done);
      let retain_source_points = retained_primitive_count > 0 || keep_original in
      let source_point_base = if retain_source_points then source.point_count else 0 in
      if source_point_base > max_int - extract_count then
        fail "Curve Carve extraction point count exceeds OCaml array limits";
      let output_point_count = source_point_base + extract_count in
      let px = Array.make output_point_count 0.
      and py = Array.make output_point_count 0.
      and pz = Array.make output_point_count 0.
      and point_left = Array.make output_point_count 0
      and point_right = Array.make output_point_count 0
      and point_weight = Array.make output_point_count 0. in
      let source_positions = Packed.Float3.Private.view
          (Geometry.positions geometry) in
      if retain_source_points then begin
        Array.blit source_positions.x 0 px 0 source.point_count;
        Array.blit source_positions.y 0 py 0 source.point_count;
        Array.blit source_positions.z 0 pz 0 source.point_count;
        for point = 0 to source.point_count - 1 do
          point_left.(point) <- point; point_right.(point) <- point
        done
      end;
      let cumulative_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        let edges = if selected primitives primitive then
            let size = source.primitive_offsets.(primitive + 1)
                - source.primitive_offsets.(primitive) in
            size - 1 + if Topology.primitive_kind source_topology primitive
                = Topology.Closed_polyline then 1 else 0
          else 0 in
        if cumulative_offsets.(primitive) > max_int - edges - 1 then
          fail "Curve Carve extraction cumulative storage exceeds array limits";
        cumulative_offsets.(primitive + 1) <- cumulative_offsets.(primitive)
          + if edges = 0 then 0 else edges + 1
      done;
      let cumulative = Array.make cumulative_offsets.(primitive_count) 0. in
      for primitive = 0 to primitive_count - 1 do
        if selected primitives primitive then begin
          if primitive land 255 = 0 then Cancel.check_opt cancel;
          let first_vertex = source.primitive_offsets.(primitive)
          and last_vertex = source.primitive_offsets.(primitive + 1)
          and base = cumulative_offsets.(primitive) in
          let count = last_vertex - first_vertex in
          let edges = count - 1 + if Topology.primitive_kind source_topology
              primitive = Topology.Closed_polyline then 1 else 0 in
          for edge = 0 to edges - 1 do
            let left = source.vertex_points.(first_vertex + (edge mod count))
            and right = source.vertex_points.
                (first_vertex + ((edge + 1) mod count)) in
            let dx = source_positions.x.(right) -. source_positions.x.(left)
            and dy = source_positions.y.(right) -. source_positions.y.(left)
            and dz = source_positions.z.(right) -. source_positions.z.(left) in
            let ax = abs_float dx and ay = abs_float dy and az = abs_float dz in
            let scale_xy = if ax >= ay then ax else ay in
            let scale = if scale_xy >= az then scale_xy else az in
            if not (finite scale) then fail (Printf.sprintf
              "Curve Carve primitive %d has an unrepresentable segment" primitive);
            let length = if scale = 0. then 0. else begin
              let x = dx /. scale and y = dy /. scale and z = dz /. scale in
              scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z))
            end in
            if not (finite length) || length <= 1e-20 then fail (Printf.sprintf
              "Curve Carve primitive %d has a zero or non-finite segment" primitive);
            cumulative.(base + edge + 1) <- cumulative.(base + edge) +. length
          done;
          if not (finite cumulative.(base + edges)) then fail (Printf.sprintf
            "Curve Carve primitive %d has unrepresentable total length" primitive)
        end
      done;
      let selected_primitives = Array.make !selected_count 0
      and selected_at = ref 0 in
      for primitive = 0 to primitive_count - 1 do
        if selected primitives primitive then begin
          selected_primitives.(!selected_at) <- primitive;
          incr selected_at
        end
      done;
      run_ranges ?grain extract_count (fun first_extract last_extract ->
        Cancel.check_opt cancel;
        for extract = first_extract to last_extract - 1 do
          let selected_index = extract / divisions
          and division = extract mod divisions in
          let primitive = selected_primitives.(selected_index) in
          let first_vertex = source.primitive_offsets.(primitive)
          and last_vertex = source.primitive_offsets.(primitive + 1)
          and base = cumulative_offsets.(primitive) in
          let count = last_vertex - first_vertex in
          let edges = count - 1 + if Topology.primitive_kind source_topology
              primitive = Topology.Closed_polyline then 1 else 0 in
          let total = cumulative.(base + edges) in
            let primitive_first, primitive_last =
              carve_parameter parameters primitive in
            let blend = if divisions = 1 then 0.
              else float_of_int division /. float_of_int (divisions - 1) in
            let parameter = primitive_first
                +. ((primitive_last -. primitive_first) *. blend) in
            let edge, t = if relative_arc_length then begin
                let distance = parameter *. total in
                let low = ref 1 and high = ref (edges + 1) in
                while !low < !high do
                  let middle = !low + ((!high - !low) / 2) in
                  if cumulative.(base + middle) <= distance
                  then low := middle + 1 else high := middle
                done;
                let edge = min (edges - 1) (!low - 1) in
                let start = cumulative.(base + edge)
                and length = cumulative.(base + edge + 1)
                    -. cumulative.(base + edge) in
                edge, (distance -. start) /. length
              end else
                let coordinate = parameter *. float_of_int edges in
                let edge = min (edges - 1) (int_of_float (floor coordinate)) in
                edge, coordinate -. float_of_int edge in
            let left_vertex = first_vertex + (edge mod count)
            and right_vertex = first_vertex + ((edge + 1) mod count) in
            let left_point = source.vertex_points.(left_vertex)
            and right_point = source.vertex_points.(right_vertex) in
            let output = source_point_base + extract in
            point_left.(output) <- left_point;
            point_right.(output) <- right_point;
            point_weight.(output) <- t;
            let interpolate left right =
              let delta = right -. left in
              if finite delta then left +. (delta *. t)
              else (left *. (1. -. t)) +. (right *. t) in
            px.(output) <- interpolate source_positions.x.(left_point)
                source_positions.x.(right_point);
            py.(output) <- interpolate source_positions.y.(left_point)
                source_positions.y.(right_point);
            pz.(output) <- interpolate source_positions.z.(left_point)
                source_positions.z.(right_point)
        done);
      let output_topology = Topology.create_owned ~point_count:output_point_count
          ~vertex_points ~primitive_offsets ~primitive_kinds |> Result.get_ok in
      let attributes = List.map (fun attribute -> match Attribute.owner attribute with
        | Attribute.Point -> interpolate_attribute ?cancel ?grain point_left
            point_right point_weight [||] [||] [||] attribute
        | Attribute.Vertex -> remap_attribute ?cancel ?grain vertex_map attribute
        | Attribute.Primitive -> remap_attribute ?cancel ?grain primitive_map attribute
        | Attribute.Detail -> attribute) (Geometry.attributes geometry) in
      let groups = List.map (fun group ->
        let mapping = match Group.owner group with
          | Group.Point -> Array.init output_point_count (fun point ->
              (if point_weight.(point) < 0.5 then point_left else point_right).(point))
          | Group.Vertex -> vertex_map
          | Group.Primitive -> primitive_map in
        let target = Group.init ?grain ~owner:(Group.owner group)
            ~name:(Group.name group) (Array.length mapping)
            (fun target -> Group.mem mapping.(target) group) in
        Group.Private.remap_order ~source:group ~source_of_target:mapping target)
          (Geometry.groups geometry) in
      let edge_groups = if retained_primitive_count = 0 then
          List.map (fun group -> Edge_group.Private.of_owned_bits
            ~topology:output_topology ~edge_count:0 ~name:(Edge_group.name group)
            Bytes.empty) (Geometry.edge_groups geometry)
        else
          let source_index = Topology_index.create ?cancel source_topology
          and target_index = Topology_index.create ?cancel output_topology
          and point_map = Array.init source.point_count Fun.id in
          List.map (fun group -> Edge_group.remap ?cancel ~source_index
            ~target_topology:output_topology ~target_index ~point_map group
            |> Result.get_ok) (Geometry.edge_groups geometry) in
      Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz)
        ~topology:output_topology ~attributes ~groups ~edge_groups ()
    end
  with Curve_error message -> Error message

let convert_line ?cancel ?grain ?edges ?length_attribute geometry =
  try
    (match grain with Some value when value <= 0 -> fail "grain must be positive"
     | _ -> ());
    Option.iter (fun name -> if String.trim name = "" then
      fail "Convert Line length attribute name must not be empty") length_attribute;
    Cancel.check_opt cancel;
    let source_topology = Geometry.topology geometry in
    let source_index = Topology_index.create ?cancel source_topology in
    let index = Topology_index.Private.view source_index in
    let source_edge_count = Topology_index.edge_count source_index in
    (match edges with
     | None -> ()
     | Some group ->
         if Edge_group.topology_data_id group <> Topology.data_id source_topology
            || Edge_group.length group <> source_edge_count then
           fail "Convert Line edge selection belongs to a different topology");
    let should_include edge =
      (match edges with None -> true | Some group -> Edge_group.mem edge group)
      && index.edge_a.(edge) <> index.edge_b.(edge) in
    let output_edge_count = ref 0 in
    for edge = 0 to source_edge_count - 1 do
      if edge land 16_383 = 0 then Cancel.check_opt cancel;
      if should_include edge then incr output_edge_count
    done;
    if !output_edge_count > max_int / 2 then
      fail "Convert Line output cardinality exceeds OCaml array limits";
    let source_edges = Array.make !output_edge_count 0 and at = ref 0 in
    for edge = 0 to source_edge_count - 1 do
      if edge land 16_383 = 0 then Cancel.check_opt cancel;
      if should_include edge then begin
        source_edges.(!at) <- edge;
        incr at
      end
    done;
    radix_sort_edges ?cancel index (Geometry.point_count geometry) source_edges;
    let output_vertex_count = !output_edge_count * 2 in
    let vertex_points = Array.make output_vertex_count 0
    and primitive_offsets = Array.init (!output_edge_count + 1)
        (fun primitive -> primitive * 2)
    and primitive_kinds = Array.make !output_edge_count Topology.Open_polyline in
    run_ranges ?grain !output_edge_count (fun first last ->
      Cancel.check_opt cancel;
      for primitive = first to last - 1 do
        let edge = source_edges.(primitive) in
        vertex_points.(primitive * 2) <- index.edge_a.(edge);
        vertex_points.((primitive * 2) + 1) <- index.edge_b.(edge)
      done);
    let output_topology = Topology.create_owned
        ~point_count:(Geometry.point_count geometry) ~vertex_points
        ~primitive_offsets ~primitive_kinds |> Result.get_ok in
    let attributes = List.filter (fun attribute ->
      match Attribute.owner attribute with
      | Attribute.Point | Attribute.Detail -> true
      | Attribute.Vertex | Attribute.Primitive -> false)
        (Geometry.attributes geometry) in
    let attributes = match length_attribute with
      | None -> attributes
      | Some name ->
          let positions = Packed.Float3.Private.view
              (Geometry.positions geometry) in
          let lengths = Array.make !output_edge_count 0. in
          run_ranges ?grain !output_edge_count (fun first last ->
            Cancel.check_opt cancel;
            for primitive = first to last - 1 do
              let edge = source_edges.(primitive) in
              let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
              lengths.(primitive) <- segment_length positions a b
            done);
          Attribute.create_owned ~name ~owner:Attribute.Primitive
            (Attribute.Float lengths) |> Result.get_ok |> fun value ->
          value :: attributes in
    let groups = List.filter (fun group -> Group.owner group = Group.Point)
        (Geometry.groups geometry) in
    let target_bytes = (!output_edge_count + 7) / 8 in
    let edge_groups = List.map (fun group ->
      let bits = Bytes.make target_bytes '\000' in
      run_ranges ?grain target_bytes (fun first last ->
        Cancel.check_opt cancel;
        for byte = first to last - 1 do
          let base = byte * 8 and value = ref 0 in
          for bit = 0 to min 7 (!output_edge_count - base - 1) do
            if Edge_group.mem source_edges.(base + bit) group then
              value := !value lor (1 lsl bit)
          done;
          Bytes.set bits byte (Char.chr !value)
        done);
      Edge_group.Private.of_owned_bits ~topology:output_topology
        ~edge_count:!output_edge_count ~name:(Edge_group.name group) bits)
        (Geometry.edge_groups geometry) in
    Geometry.create ~positions:(Geometry.positions geometry)
      ~topology:output_topology ~attributes ~groups ~edge_groups ()
  with Curve_error message -> Error message

let ends ?cancel ?grain ?primitives ?(allow_polygons = false) mode geometry =
  try
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let source = Topology.Private.view topology in
    let primitive_count = Topology.primitive_count topology in
    let operation = if allow_polygons then "Ends" else "Curve Ends" in
    validate_selection operation primitives primitive_count;
    let output_sizes = Array.make primitive_count 0
    and output_kinds = Array.make primitive_count Topology.Open_polyline
    and new_point_for_primitive = Array.make primitive_count (-1) in
    let changed = ref false and output_vertex_count = ref 0
    and output_point_count = ref source.point_count in
    let close primitive size kind =
      let first = source.primitive_offsets.(primitive) in
      let repeated_endpoint = size > 0
        && source.vertex_points.(first)
          = source.vertex_points.(first + size - 1) in
      let output_size = if repeated_endpoint then size - 1 else size in
      if output_size < 3 then fail (Printf.sprintf
        "%s cannot close primitive %d with fewer than three vertices"
        operation primitive);
      if output_size <> size || kind <> Topology.primitive_kind topology primitive
      then changed := true;
      output_size, kind in
    for primitive = 0 to primitive_count - 1 do
      let size = source.primitive_offsets.(primitive + 1)
          - source.primitive_offsets.(primitive) in
      let kind = Topology.primitive_kind topology primitive in
      let output_size, output_kind =
        if not (selected primitives primitive) then size, kind
        else match kind, mode with
          | Topology.Polygon, _ when not allow_polygons ->
              fail (Printf.sprintf
                "Curve Ends primitive %d is a polygon, not a polygon curve" primitive)
          | Topology.Open_polyline, Open
          | Topology.Open_polyline, Unroll
          | Topology.Open_polyline, Unroll_new
          | Topology.Closed_polyline, Close
          | Topology.Polygon, Close
          | Topology.Polygon, Close_straight -> size, kind
          | Topology.Open_polyline, Close ->
              close primitive size Topology.Closed_polyline
          | Topology.Open_polyline, Close_straight ->
              close primitive size Topology.Polygon
          | Topology.Closed_polyline, Close_straight ->
              changed := true; size, Topology.Polygon
          | (Topology.Closed_polyline | Topology.Polygon), Open ->
              changed := true; size, Topology.Open_polyline
          | (Topology.Closed_polyline | Topology.Polygon), Unroll ->
              changed := true; size + 1, Topology.Open_polyline
          | (Topology.Closed_polyline | Topology.Polygon), Unroll_new ->
              if !output_point_count = Sys.max_array_length then
                fail (operation ^ " output point count exceeds OCaml array limits");
              changed := true;
              new_point_for_primitive.(primitive) <- !output_point_count;
              incr output_point_count;
              size + 1, Topology.Open_polyline in
      if !output_vertex_count > max_int - output_size then
        fail (operation ^ " output cardinality exceeds OCaml array limits");
      output_sizes.(primitive) <- output_size;
      output_kinds.(primitive) <- output_kind;
      output_vertex_count := !output_vertex_count + output_size
    done;
    if not !changed then Ok geometry
    else begin
      let primitive_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        primitive_offsets.(primitive + 1) <- primitive_offsets.(primitive)
          + output_sizes.(primitive)
      done;
      let points_changed = !output_point_count <> source.point_count in
      let point_map = if not points_changed then [||] else
          Array.init !output_point_count (fun point ->
            if point < source.point_count then point else 0) in
      if points_changed then
        for primitive = 0 to primitive_count - 1 do
          let point = new_point_for_primitive.(primitive) in
          if point >= 0 then begin
            let first = source.primitive_offsets.(primitive) in
            point_map.(point) <- source.vertex_points.(first)
          end
        done;
      let vertex_map = Array.make !output_vertex_count 0
      and vertex_points = Array.make !output_vertex_count 0 in
      run_ranges ?grain primitive_count (fun first_primitive last_primitive ->
        Cancel.check_opt cancel;
        for primitive = first_primitive to last_primitive - 1 do
          let source_first = source.primitive_offsets.(primitive)
          and source_last = source.primitive_offsets.(primitive + 1)
          and output_first = primitive_offsets.(primitive) in
          let source_size = source_last - source_first in
          for local = 0 to output_sizes.(primitive) - 1 do
            let output = output_first + local in
            let source_vertex = source_first + (local mod source_size) in
            vertex_map.(output) <- source_vertex;
            vertex_points.(output) <-
              if local = source_size && new_point_for_primitive.(primitive) >= 0
              then new_point_for_primitive.(primitive)
              else source.vertex_points.(source_vertex)
          done
        done);
      let output_topology = Topology.create_owned ~point_count:!output_point_count
          ~vertex_points ~primitive_offsets ~primitive_kinds:output_kinds
          |> Result.get_ok in
      let vertices_changed = !output_vertex_count <> Array.length source.vertex_points in
      let positions = if not points_changed then Geometry.positions geometry else
        let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
        Packed.Float3.Private.of_owned_exn
          ~x:(map_array ?cancel ?grain point_map positions.x)
          ~y:(map_array ?cancel ?grain point_map positions.y)
          ~z:(map_array ?cancel ?grain point_map positions.z) in
      let attributes = List.map (fun attribute ->
        match Attribute.owner attribute with
        | Attribute.Point when points_changed ->
            remap_attribute ?cancel ?grain point_map attribute
        | Attribute.Vertex when vertices_changed ->
            remap_attribute ?cancel ?grain vertex_map attribute
        | Attribute.Point | Attribute.Vertex
        | Attribute.Primitive | Attribute.Detail -> attribute)
          (Geometry.attributes geometry) in
      let groups = List.map (fun group ->
        let mapping = match Group.owner group with
          | Group.Point when points_changed -> Some point_map
          | Group.Vertex when vertices_changed -> Some vertex_map
          | Group.Point | Group.Vertex | Group.Primitive -> None in
        match mapping with
        | None -> group
        | Some mapping ->
          let target = Group.init ?grain ~owner:(Group.owner group)
              ~name:(Group.name group) (Array.length mapping) (fun element ->
                if element land 4095 = 0 then Cancel.check_opt cancel;
                Group.mem mapping.(element) group) in
          Group.Private.remap_order ~source:group
            ~source_of_target:mapping target) (Geometry.groups geometry) in
      let edge_groups = match Geometry.edge_groups geometry with
        | [] -> []
        | source_groups ->
            let seen = Bytes.make source.point_count '\000'
            and unique_points = ref true in
            Array.iter (fun point ->
              if Bytes.get seen point <> '\000' then unique_points := false
              else Bytes.set seen point '\001') source.vertex_points;
            if !unique_points then begin
              let edge_count kind size = size - 1 + match kind with
                | Topology.Polygon | Topology.Closed_polyline -> 1
                | Topology.Open_polyline -> 0 in
              let source_edge_offsets = Array.make (primitive_count + 1) 0
              and target_edge_offsets = Array.make (primitive_count + 1) 0 in
              for primitive = 0 to primitive_count - 1 do
                let source_size = source.primitive_offsets.(primitive + 1)
                    - source.primitive_offsets.(primitive) in
                source_edge_offsets.(primitive + 1) <-
                  source_edge_offsets.(primitive)
                    + edge_count (Topology.primitive_kind topology primitive)
                        source_size;
                target_edge_offsets.(primitive + 1) <-
                  target_edge_offsets.(primitive)
                    + edge_count output_kinds.(primitive) output_sizes.(primitive)
              done;
              let target_edge_count = target_edge_offsets.(primitive_count) in
              List.map (fun group ->
                let bits = Bytes.make ((target_edge_count + 7) / 8) '\000' in
                let set edge =
                  let byte = edge lsr 3 and mask = 1 lsl (edge land 7) in
                  Bytes.set bits byte
                    (Char.chr (Char.code (Bytes.get bits byte) lor mask)) in
                for primitive = 0 to primitive_count - 1 do
                  if primitive land 4095 = 0 then Cancel.check_opt cancel;
                  let source_edges = source_edge_offsets.(primitive + 1)
                      - source_edge_offsets.(primitive)
                  and target_edges = target_edge_offsets.(primitive + 1)
                      - target_edge_offsets.(primitive) in
                  for local = 0 to target_edges - 1 do
                    if local < source_edges
                        && Edge_group.mem (source_edge_offsets.(primitive) + local)
                          group then set (target_edge_offsets.(primitive) + local)
                  done
                done;
                Edge_group.Private.of_owned_bits ~topology:output_topology
                  ~edge_count:target_edge_count ~name:(Edge_group.name group) bits)
                source_groups
            end else begin
              let source_index = Topology_index.create ?cancel topology
              and target_lookup = Topology_edge_lookup.create ?cancel
                  (Topology.Private.view output_topology) in
              let source_reverse = Topology_index.Private.view source_index
              and target = Topology.Private.view output_topology in
              let target_edge_count = Topology_edge_lookup.count target_lookup in
              let source_of_target = Array.make target_edge_count (-1) in
              for primitive = 0 to primitive_count - 1 do
                if primitive land 4095 = 0 then Cancel.check_opt cancel;
                let first = target.primitive_offsets.(primitive)
                and last = target.primitive_offsets.(primitive + 1) in
                for target_vertex = first to last - 1 do
                  let target_next = if target_vertex + 1 < last
                    then target_vertex + 1
                    else if Bytes.get target.primitive_kinds primitive = '\001'
                    then -1 else first in
                  if target_next >= 0 then begin
                    let source_vertex = vertex_map.(target_vertex)
                    and source_next = vertex_map.(target_next) in
                    let candidate = source_reverse.edge_of_vertex.(source_vertex) in
                    if candidate >= 0 then begin
                      let a = source.vertex_points.(source_vertex)
                      and b = source.vertex_points.(source_next)
                      and edge_a = source_reverse.edge_a.(candidate)
                      and edge_b = source_reverse.edge_b.(candidate) in
                      if (a = edge_a && b = edge_b)
                          || (a = edge_b && b = edge_a) then begin
                        let edge = Topology_edge_lookup.find target_lookup
                            ~a:target.vertex_points.(target_vertex)
                            ~b:target.vertex_points.(target_next) in
                        if edge < 0 then fail
                            (operation ^ " internal target edge lookup failed")
                        else if source_of_target.(edge) >= 0
                            && source_of_target.(edge) <> candidate then
                          fail (operation ^ " target edge has conflicting ancestry")
                        else source_of_target.(edge) <- candidate
                      end
                    end
                  end
                done
              done;
              List.map (fun group ->
                let byte_count = (target_edge_count + 7) / 8 in
                let bits = Bytes.make byte_count '\000' in
                run_ranges ?grain byte_count (fun first last ->
                  Cancel.check_opt cancel;
                  for byte = first to last - 1 do
                    let value = ref 0 in
                    for bit = 0 to 7 do
                      let edge = (byte lsl 3) + bit in
                      if edge < target_edge_count then begin
                        let source_edge = source_of_target.(edge) in
                        if source_edge >= 0 && Edge_group.mem source_edge group
                        then value := !value lor (1 lsl bit)
                      end
                    done;
                    Bytes.set bits byte (Char.chr !value)
                  done);
                Edge_group.Private.of_owned_bits ~topology:output_topology
                  ~edge_count:target_edge_count ~name:(Edge_group.name group) bits)
                source_groups
            end in
      Geometry.create ~positions
        ~topology:output_topology ~attributes ~groups ~edge_groups ()
    end
  with Curve_error message -> Error message

type endpoint_tree = {
  endpoint_ids : int array;
  endpoint_node : int array;
  endpoint_x : float array;
  endpoint_y : float array;
  endpoint_z : float array;
  left : int array;
  right : int array;
  parent : int array;
  axis : Bytes.t;
  active : Bytes.t;
  active_count : int array;
  mutable nearest_endpoint : int;
  mutable nearest_distance : float;
  root : int;
}

let[@inline always] robust_distance_xyz ax ay az bx by bz =
  let dx = ax -. bx and dy = ay -. by and dz = az -. bz in
  Float.hypot (Float.hypot dx dy) dz

let endpoint_tree ?cancel endpoint_x endpoint_y endpoint_z =
  let count = Array.length endpoint_x in
  if Array.length endpoint_y <> count || Array.length endpoint_z <> count then
    invalid_arg "Curve Join endpoint coordinate length mismatch";
  let endpoint_ids = Array.init count Fun.id
  and endpoint_node = Array.make count (-1)
  and left = Array.make count (-1)
  and right = Array.make count (-1)
  and parent = Array.make count (-1)
  and axis = Bytes.make count '\000'
  and active = Bytes.make count '\001'
  and active_count = Array.make count 0 in
  let compare axis left right =
    let order = if axis = 0 then Float.compare endpoint_x.(left) endpoint_x.(right)
      else if axis = 1 then Float.compare endpoint_y.(left) endpoint_y.(right)
      else Float.compare endpoint_z.(left) endpoint_z.(right) in
    if order <> 0 then order else Int.compare left right in
  let swap left right =
    let value = endpoint_ids.(left) in
    endpoint_ids.(left) <- endpoint_ids.(right);
    endpoint_ids.(right) <- value in
  let median_of_three axis first middle last =
    let a = endpoint_ids.(first) and b = endpoint_ids.(middle)
    and c = endpoint_ids.(last) in
    if compare axis a b <= 0 then
      if compare axis b c <= 0 then middle
      else if compare axis a c <= 0 then last else first
    else if compare axis a c <= 0 then first
    else if compare axis b c <= 0 then last else middle in
  let partition axis first last pivot_index =
    let pivot = endpoint_ids.(pivot_index) in
    swap pivot_index last;
    let store = ref first in
    for index = first to last - 1 do
      if index land 16_383 = 0 then Cancel.check_opt cancel;
      if compare axis endpoint_ids.(index) pivot < 0 then begin
        swap index !store;
        incr store
      end
    done;
    swap !store last;
    !store in
  let select axis first last target =
    let first = ref first and last = ref last in
    while !first < !last do
      Cancel.check_opt cancel;
      let middle = !first + ((!last - !first) lsr 1) in
      let pivot = median_of_three axis !first middle !last in
      let pivot = partition axis !first !last pivot in
      if target < pivot then last := pivot - 1
      else if target > pivot then first := pivot + 1
      else begin first := target; last := target end
    done in
  let min_x = Array.make Sys.int_size 0. and max_x = Array.make Sys.int_size 0.
  and min_y = Array.make Sys.int_size 0. and max_y = Array.make Sys.int_size 0.
  and min_z = Array.make Sys.int_size 0. and max_z = Array.make Sys.int_size 0. in
  let choose_axis first last depth =
    let endpoint = endpoint_ids.(first) in
    min_x.(depth) <- endpoint_x.(endpoint);
    max_x.(depth) <- endpoint_x.(endpoint);
    min_y.(depth) <- endpoint_y.(endpoint);
    max_y.(depth) <- endpoint_y.(endpoint);
    min_z.(depth) <- endpoint_z.(endpoint);
    max_z.(depth) <- endpoint_z.(endpoint);
    for index = first + 1 to last - 1 do
      if index land 16_383 = 0 then Cancel.check_opt cancel;
      let endpoint = endpoint_ids.(index) in
      let x = endpoint_x.(endpoint) and y = endpoint_y.(endpoint)
      and z = endpoint_z.(endpoint) in
      if x < min_x.(depth) then min_x.(depth) <- x;
      if x > max_x.(depth) then max_x.(depth) <- x;
      if y < min_y.(depth) then min_y.(depth) <- y;
      if y > max_y.(depth) then max_y.(depth) <- y;
      if z < min_z.(depth) then min_z.(depth) <- z;
      if z > max_z.(depth) then max_z.(depth) <- z
    done;
    let x_span = max_x.(depth) -. min_x.(depth)
    and y_span = max_y.(depth) -. min_y.(depth)
    and z_span = max_z.(depth) -. min_z.(depth) in
    if y_span > x_span then if z_span > y_span then 2 else 1
    else if z_span > x_span then 2 else 0 in
  let rec build first last depth parent_node =
    if first >= last then -1
    else begin
      let axis_value = choose_axis first last depth
      and middle = first + ((last - first) lsr 1) in
      select axis_value first (last - 1) middle;
      parent.(middle) <- parent_node;
      Bytes.set axis middle (Char.chr axis_value);
      endpoint_node.(endpoint_ids.(middle)) <- middle;
      let left_node = build first middle (depth + 1) middle
      and right_node = build (middle + 1) last (depth + 1) middle in
      left.(middle) <- left_node;
      right.(middle) <- right_node;
      active_count.(middle) <- 1
          + (if left_node < 0 then 0 else active_count.(left_node))
          + (if right_node < 0 then 0 else active_count.(right_node));
      middle
    end in
  let root = build 0 count 0 (-1) in
  { endpoint_ids; endpoint_node; endpoint_x; endpoint_y; endpoint_z;
    left; right; parent; axis; active; active_count;
    nearest_endpoint = -1; nearest_distance = infinity; root }

let endpoint_tree_remove tree endpoint =
  if Bytes.get tree.active endpoint <> '\000' then begin
    Bytes.set tree.active endpoint '\000';
    let node = ref tree.endpoint_node.(endpoint) in
    while !node >= 0 do
      tree.active_count.(!node) <- tree.active_count.(!node) - 1;
      node := tree.parent.(!node)
    done
  end

let endpoint_tree_nearest ?cancel tree query_endpoint =
  let qx = tree.endpoint_x.(query_endpoint)
  and qy = tree.endpoint_y.(query_endpoint)
  and qz = tree.endpoint_z.(query_endpoint) in
  tree.nearest_endpoint <- -1;
  tree.nearest_distance <- infinity;
  let visited = ref 0 in
  let rec visit node =
    if node >= 0 && tree.active_count.(node) > 0 then begin
      incr visited;
      if !visited land 16_383 = 0 then Cancel.check_opt cancel;
      let endpoint = tree.endpoint_ids.(node)
      and axis = Char.code (Bytes.get tree.axis node) in
      let delta = if axis = 0 then qx -. tree.endpoint_x.(endpoint)
        else if axis = 1 then qy -. tree.endpoint_y.(endpoint)
        else qz -. tree.endpoint_z.(endpoint) in
      let near, far = if delta <= 0. then tree.left.(node), tree.right.(node)
        else tree.right.(node), tree.left.(node) in
      visit near;
      if Bytes.get tree.active endpoint <> '\000' then begin
        let distance = robust_distance_xyz qx qy qz
            tree.endpoint_x.(endpoint) tree.endpoint_y.(endpoint)
            tree.endpoint_z.(endpoint) in
        if distance < tree.nearest_distance
            || distance = tree.nearest_distance
               && (tree.nearest_endpoint < 0
                   || endpoint < tree.nearest_endpoint) then begin
          tree.nearest_endpoint <- endpoint;
          tree.nearest_distance <- distance
        end
      end;
      if abs_float delta <= tree.nearest_distance then visit far
    end
  in
  visit tree.root

let join ?cancel ?grain ?primitives ?picked_ends ?(orient_closest = true)
    ?(connect_closest_ends = false) ?(only_connected = false)
    ?group_size ?(keep_originals = false) ?(tolerance = 0.)
    ?(wrap = false) geometry =
  try
    if not (finite tolerance) || tolerance < 0. then
      fail "Curve Join tolerance must be finite and non-negative";
    (match group_size with Some size when size <= 0 ->
       fail "Curve Join group size must be positive"
     | None | Some _ -> ());
    (match primitives, picked_ends with
     | Some _, Some _ ->
         fail "Curve Join primitive selection and picked ends are mutually exclusive"
     | None, _ | _, None -> ());
    (match picked_ends with
     | Some _ when connect_closest_ends ->
         fail "Curve Join picked ends and Connect Closest Ends are mutually exclusive"
     | None | Some _ -> ());
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let source = Topology.Private.view topology in
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let primitive_count = Topology.primitive_count topology in
    validate_selection "Curve Join" primitives primitive_count;
    let selected_count = match picked_ends with
      | Some picks -> Array.length picks
      | None -> match primitives with
          | Some group -> Group.cardinality group
          | None -> primitive_count in
    if selected_count = 0 then Ok geometry
    else begin
      let selected_primitives = Array.make selected_count 0
      and selected_index = Array.make primitive_count (-1) in
      (match picked_ends with
       | Some picks ->
           Array.iteri (fun index pick ->
             let primitive = pick.primitive in
             if primitive < 0 || primitive >= primitive_count then
               fail (Printf.sprintf
                 "Curve Join picked primitive %d is out of bounds" primitive);
             if selected_index.(primitive) >= 0 then
               fail (Printf.sprintf
                 "Curve Join picked primitive %d more than once" primitive);
             selected_index.(primitive) <- index;
             selected_primitives.(index) <- primitive) picks
       | None ->
           (match primitives with
            | Some group ->
                (match Group.Private.order_view group with
                 | Some order -> Array.blit order 0 selected_primitives 0 selected_count
                 | None ->
                     let at = ref 0 in
                     Group.iter (fun primitive ->
                       selected_primitives.(!at) <- primitive;
                       incr at) group)
            | None -> Array.iteri (fun index _ ->
                selected_primitives.(index) <- index) selected_primitives));
      Array.iter (fun primitive ->
        if Topology.primitive_kind topology primitive <> Topology.Open_polyline then
          fail (Printf.sprintf
            "Curve Join primitive %d is not an open polygon curve" primitive))
        selected_primitives;
      let reversed = Bytes.make selected_count '\000'
      and welded = Bytes.make selected_count '\000'
      and selected_chain = Array.make selected_count 0 in
      let chain_count = ref 1 in
      let starts_subgroup index = match group_size with
        | Some size -> index > 0 && index mod size = 0
        | None -> false in
      let endpoint primitive reverse last =
        let first = source.primitive_offsets.(primitive)
        and stop = source.primitive_offsets.(primitive + 1) in
        let vertex = if last <> reverse then stop - 1 else first in
        source.vertex_points.(vertex) in
      let distance left right =
        if not (finite positions.x.(left) && finite positions.y.(left)
            && finite positions.z.(left) && finite positions.x.(right)
            && finite positions.y.(right) && finite positions.z.(right)) then
          fail "Curve Join requires finite selected endpoint positions";
        robust_distance_xyz positions.x.(left) positions.y.(left)
          positions.z.(left) positions.x.(right) positions.y.(right)
          positions.z.(right) in
      if Option.is_some picked_ends then begin
        let picks = Option.get picked_ends in
        let picked_reverse index =
          let subgroup = starts_subgroup index in
          match picks.(index).end_ with
            | Join_curve_start -> index = 0 || subgroup
            | Join_curve_end -> index > 0 && not subgroup in
        if only_connected then
          for index = 0 to selected_count - 1 do
            if index land 4095 = 0 then Cancel.check_opt cancel;
            let subgroup = starts_subgroup index
            and reverse = picked_reverse index in
            if reverse then Bytes.set reversed index '\001';
            if index > 0 then begin
              let previous = selected_primitives.(index - 1)
              and primitive = selected_primitives.(index) in
              let previous_reversed = picked_reverse (index - 1) in
              let current_end = endpoint previous previous_reversed true
              and next_start = endpoint primitive reverse false in
              let join_distance = distance current_end next_start in
              if subgroup || join_distance > tolerance then begin
                selected_chain.(index) <- !chain_count;
                incr chain_count
              end else begin
                selected_chain.(index) <- !chain_count - 1;
                Bytes.set welded index '\001'
              end
            end
          done
        else begin
          let fixed_chain_count = match group_size with
            | None -> 1
            | Some size -> 1 + ((selected_count - 1) / size) in
          chain_count := fixed_chain_count;
          run_ranges ?grain selected_count (fun first last ->
            Cancel.check_opt cancel;
            for index = first to last - 1 do
              let subgroup = starts_subgroup index
              and reverse = picked_reverse index in
              if reverse then Bytes.set reversed index '\001';
              selected_chain.(index) <- (match group_size with
                | None -> 0
                | Some size -> index / size);
              if index > 0 && not subgroup then begin
                let previous = selected_primitives.(index - 1)
                and primitive = selected_primitives.(index) in
                let current_end = endpoint previous (picked_reverse (index - 1)) true
                and next_start = endpoint primitive reverse false in
                if distance current_end next_start <= tolerance then
                  Bytes.set welded index '\001'
              end
            done)
        end
      end else if connect_closest_ends then begin
        if selected_count > max_int / 2 then
          fail "Curve Join endpoint count exceeds OCaml array limits";
        let input_primitives = Array.copy selected_primitives in
        let endpoint_count = selected_count * 2 in
        let endpoint_x = Array.make endpoint_count 0.
        and endpoint_y = Array.make endpoint_count 0.
        and endpoint_z = Array.make endpoint_count 0. in
        run_ranges ?grain endpoint_count (fun first last ->
          for endpoint_slot = first to last - 1 do
            if endpoint_slot land 16_383 = 0 then Cancel.check_opt cancel;
            let primitive = input_primitives.(endpoint_slot lsr 1) in
            let point = endpoint primitive false (endpoint_slot land 1 = 1) in
            let x = positions.x.(point) and y = positions.y.(point)
            and z = positions.z.(point) in
            if not (finite x && finite y && finite z) then
              fail "Curve Join requires finite selected endpoint positions";
            endpoint_x.(endpoint_slot) <- x;
            endpoint_y.(endpoint_slot) <- y;
            endpoint_z.(endpoint_slot) <- z
          done);
        let tree = endpoint_tree ?cancel endpoint_x endpoint_y endpoint_z
        and used = Bytes.make selected_count '\000' in
        let remove primitive_slot =
          Bytes.set used primitive_slot '\001';
          endpoint_tree_remove tree (primitive_slot * 2);
          endpoint_tree_remove tree ((primitive_slot * 2) + 1) in
        let orient_root primitive_slot =
          if tree.active_count.(tree.root) = 0 then false
          else begin
            endpoint_tree_nearest ?cancel tree (primitive_slot * 2);
            let from_start = tree.nearest_distance in
            endpoint_tree_nearest ?cancel tree ((primitive_slot * 2) + 1);
            from_start < tree.nearest_distance
          end in
        remove 0;
        let current_endpoint = ref 1 and next_root = ref 1 in
        for index = 1 to selected_count - 1 do
          if index land 4095 = 0 then Cancel.check_opt cancel;
          endpoint_tree_nearest ?cancel tree !current_endpoint;
          let nearest = tree.nearest_endpoint
          and nearest_distance = tree.nearest_distance in
          if nearest < 0 then fail "Curve Join endpoint search exhausted early";
          let subgroup = starts_subgroup index in
          let disconnected = only_connected && nearest_distance > tolerance in
          let new_chain = subgroup || disconnected in
          let removed = ref false in
          let primitive_slot, reverse, join_distance = if new_chain then begin
              let primitive_slot = if subgroup then nearest lsr 1
              else begin
              while !next_root < selected_count
                  && Bytes.get used !next_root <> '\000' do incr next_root done;
              if !next_root >= selected_count then
                fail "Curve Join connected-component planning exhausted early";
              !next_root
              end in
              remove primitive_slot;
              removed := true;
              primitive_slot, orient_root primitive_slot, infinity
            end else nearest lsr 1, nearest land 1 = 1, nearest_distance in
          selected_primitives.(index) <- input_primitives.(primitive_slot);
          if new_chain then begin
            selected_chain.(index) <- !chain_count;
            incr chain_count
          end else begin
            selected_chain.(index) <- !chain_count - 1;
            if reverse then Bytes.set reversed index '\001';
            if join_distance <= tolerance then Bytes.set welded index '\001'
          end;
          if not !removed then remove primitive_slot;
          current_endpoint := (primitive_slot * 2) + if reverse then 0 else 1
        done
      end else
        for index = 1 to selected_count - 1 do
          let previous = selected_primitives.(index - 1)
          and primitive = selected_primitives.(index) in
          let previous_reversed = Bytes.get reversed (index - 1) <> '\000' in
          let current_end = endpoint previous previous_reversed true
          and next_start = endpoint primitive false false
          and next_end = endpoint primitive false true in
          let start_distance = distance current_end next_start
          and end_distance = distance current_end next_end in
          let subgroup = starts_subgroup index in
          let reverse, distance = if subgroup then begin
              let reverse = if orient_closest && index + 1 < selected_count
                    && not (starts_subgroup (index + 1)) then
                  let following = selected_primitives.(index + 1) in
                  let following_start = endpoint following false false
                  and following_end = endpoint following false true
                  and root_start = endpoint primitive false false
                  and root_end = endpoint primitive false true in
                  let from_start = min (distance root_start following_start)
                      (distance root_start following_end)
                  and from_end = min (distance root_end following_start)
                      (distance root_end following_end) in
                  from_start < from_end
                else false in
              reverse, infinity
            end else begin
              let reverse = orient_closest && end_distance < start_distance in
              reverse, if reverse then end_distance else start_distance
            end in
          if subgroup || only_connected && distance > tolerance then begin
            selected_chain.(index) <- !chain_count;
            if reverse then Bytes.set reversed index '\001';
            incr chain_count
          end else begin
            selected_chain.(index) <- !chain_count - 1;
            if reverse then Bytes.set reversed index '\001';
            if distance <= tolerance then Bytes.set welded index '\001'
          end
        done;
      Array.fill selected_index 0 primitive_count (-1);
      Array.iteri (fun index primitive -> selected_index.(primitive) <- index)
        selected_primitives;
      let chain_count = !chain_count in
      let chain_first = Array.make chain_count (-1)
      and chain_last = Array.make chain_count (-1)
      and chain_size = Array.make chain_count 0 in
      for index = 0 to selected_count - 1 do
        let chain = selected_chain.(index) in
        if chain_first.(chain) < 0 then chain_first.(chain) <- index;
        chain_last.(chain) <- index;
        let primitive = selected_primitives.(index) in
        let size = source.primitive_offsets.(primitive + 1)
            - source.primitive_offsets.(primitive) in
        chain_size.(chain) <- chain_size.(chain) + size
          - if index > chain_first.(chain) && Bytes.get welded index <> '\000'
            then 1 else 0
      done;
      if wrap then Array.iteri (fun chain size -> if size < 3 then
        fail (Printf.sprintf
          "Curve Join cannot wrap chain %d with fewer than three vertices" chain))
        chain_size;
      let retained_primitive_count = if keep_originals then primitive_count
        else primitive_count - selected_count in
      if retained_primitive_count > max_int - chain_count then
        fail "Curve Join primitive cardinality exceeds OCaml array limits";
      let output_primitive_count = retained_primitive_count + chain_count in
      let descriptor_primitive = Array.make output_primitive_count (-1)
      and descriptor_chain = Array.make output_primitive_count (-1)
      and primitive_map = Array.make output_primitive_count 0
      and output_sizes = Array.make output_primitive_count 0
      and output_kinds = Array.make output_primitive_count Topology.Open_polyline in
      let output_primitive = ref 0 in
      let emit_primitive primitive =
        let output = !output_primitive in incr output_primitive;
        descriptor_primitive.(output) <- primitive;
        primitive_map.(output) <- primitive;
        output_sizes.(output) <- source.primitive_offsets.(primitive + 1)
          - source.primitive_offsets.(primitive);
        output_kinds.(output) <- Topology.primitive_kind topology primitive in
      let emit_chain chain =
        let first_index = chain_first.(chain) in
        let output = !output_primitive in incr output_primitive;
        descriptor_chain.(output) <- chain;
        primitive_map.(output) <- selected_primitives.(first_index);
        output_sizes.(output) <- chain_size.(chain);
        output_kinds.(output) <- if wrap then Topology.Closed_polyline
          else Topology.Open_polyline in
      if keep_originals then begin
        for primitive = 0 to primitive_count - 1 do emit_primitive primitive done;
        for chain = 0 to chain_count - 1 do emit_chain chain done
      end else
        for primitive = 0 to primitive_count - 1 do
          let index = selected_index.(primitive) in
          if index < 0 then emit_primitive primitive
          else begin
            let chain = selected_chain.(index) in
            if chain_first.(chain) = index then emit_chain chain
          end
        done;
      let primitive_offsets = Array.make (output_primitive_count + 1) 0 in
      for primitive = 0 to output_primitive_count - 1 do
        if primitive_offsets.(primitive) > max_int - output_sizes.(primitive) then
          fail "Curve Join output cardinality exceeds OCaml array limits";
        primitive_offsets.(primitive + 1) <- primitive_offsets.(primitive)
          + output_sizes.(primitive)
      done;
      let output_vertex_count = primitive_offsets.(output_primitive_count) in
      let vertex_map = Array.make output_vertex_count 0
      and vertex_points = Array.make output_vertex_count 0
      and edge_source_corner = Array.make output_vertex_count (-1) in
      let fill_source output_at previous source_first source_size reverse skip_first =
        let first_step = if skip_first then 1 else 0 in
        for step = first_step to source_size - 1 do
          let local = if reverse then source_size - 1 - step else step in
          let source_vertex = source_first + local and output = !output_at in
          vertex_map.(output) <- source_vertex;
          vertex_points.(output) <- source.vertex_points.(source_vertex);
          if !previous >= 0 then begin
            let source_edge_corner =
              if step = first_step && first_step = 0 then -1
              else if reverse then source_first + local
              else source_first + local - 1 in
            edge_source_corner.(!previous) <- source_edge_corner
          end;
          previous := output;
          incr output_at
        done in
      run_ranges ?grain output_primitive_count (fun first_output last_output ->
        Cancel.check_opt cancel;
        for output_primitive = first_output to last_output - 1 do
          let output_at = ref primitive_offsets.(output_primitive)
          and previous = ref (-1) in
          let single = descriptor_primitive.(output_primitive) in
          if single >= 0 then begin
            let source_first = source.primitive_offsets.(single)
            and source_size = source.primitive_offsets.(single + 1)
                - source.primitive_offsets.(single) in
            fill_source output_at previous source_first source_size false false;
            if Topology.primitive_kind topology single <> Topology.Open_polyline then
              edge_source_corner.(!previous) <- source_first + source_size - 1
          end else begin
            let chain = descriptor_chain.(output_primitive) in
            for index = chain_first.(chain) to chain_last.(chain) do
              let primitive = selected_primitives.(index) in
              let source_first = source.primitive_offsets.(primitive)
              and source_size = source.primitive_offsets.(primitive + 1)
                  - source.primitive_offsets.(primitive) in
              fill_source output_at previous source_first source_size
                (Bytes.get reversed index <> '\000')
                (index > chain_first.(chain) && Bytes.get welded index <> '\000')
            done;
            edge_source_corner.(!previous) <- -1
          end
        done);
      let output_topology = Topology.create_owned ~point_count:source.point_count
          ~vertex_points ~primitive_offsets ~primitive_kinds:output_kinds
          |> Result.get_ok in
      let attributes = List.map (fun attribute -> match Attribute.owner attribute with
        | Attribute.Point | Attribute.Detail -> attribute
        | Attribute.Vertex -> remap_attribute ?cancel ?grain vertex_map attribute
        | Attribute.Primitive -> remap_attribute ?cancel ?grain primitive_map attribute)
          (Geometry.attributes geometry) in
      let groups = List.map (fun group -> match Group.owner group with
        | Group.Point -> group
        | Group.Vertex ->
            let target = Group.init ?grain ~owner:Group.Vertex
                ~name:(Group.name group) output_vertex_count (fun vertex ->
                  Group.mem vertex_map.(vertex) group) in
            Group.Private.remap_order ~source:group
              ~source_of_target:vertex_map target
        | Group.Primitive ->
            let target = Group.init ?grain ~owner:Group.Primitive
                ~name:(Group.name group) output_primitive_count (fun output ->
                  let single = descriptor_primitive.(output) in
                  if single >= 0 then Group.mem single group
                  else begin
                    let chain = descriptor_chain.(output) and member = ref false in
                    for index = chain_first.(chain) to chain_last.(chain) do
                      if Group.mem selected_primitives.(index) group then member := true
                    done;
                    !member
                  end) in
            Group.Private.remap_order ~source:group
              ~source_of_target:primitive_map target) (Geometry.groups geometry) in
      let edge_groups = match Geometry.edge_groups geometry with
        | [] -> []
        | source_groups ->
            let seen = Bytes.make source.point_count '\000'
            and unique_points = ref true in
            Array.iter (fun point ->
              if Bytes.get seen point <> '\000' then unique_points := false
              else Bytes.set seen point '\001') source.vertex_points;
            if !unique_points && not keep_originals then begin
              let edge_count kind size = size - 1 + match kind with
                | Topology.Polygon | Topology.Closed_polyline -> 1
                | Topology.Open_polyline -> 0 in
              let source_corner_edge = Array.make
                  (Array.length source.vertex_points) (-1) in
              let source_edge_at = ref 0 in
              for primitive = 0 to primitive_count - 1 do
                let first = source.primitive_offsets.(primitive)
                and size = source.primitive_offsets.(primitive + 1)
                    - source.primitive_offsets.(primitive) in
                let edges = edge_count (Topology.primitive_kind topology primitive)
                    size in
                for local = 0 to edges - 1 do
                  source_corner_edge.(first + local) <- !source_edge_at;
                  incr source_edge_at
                done
              done;
              let target_edge_offsets = Array.make
                  (output_primitive_count + 1) 0 in
              for primitive = 0 to output_primitive_count - 1 do
                target_edge_offsets.(primitive + 1) <-
                  target_edge_offsets.(primitive)
                    + edge_count output_kinds.(primitive) output_sizes.(primitive)
              done;
              let target_edge_count = target_edge_offsets.(output_primitive_count) in
              List.map (fun source_group ->
                let bits = Bytes.make ((target_edge_count + 7) / 8) '\000' in
                let set edge =
                  let byte = edge lsr 3 and mask = 1 lsl (edge land 7) in
                  Bytes.set bits byte
                    (Char.chr (Char.code (Bytes.get bits byte) lor mask)) in
                for primitive = 0 to output_primitive_count - 1 do
                  if primitive land 4095 = 0 then Cancel.check_opt cancel;
                  let edges = target_edge_offsets.(primitive + 1)
                      - target_edge_offsets.(primitive)
                  and first = primitive_offsets.(primitive) in
                  for local = 0 to edges - 1 do
                    let source_corner = edge_source_corner.(first + local) in
                    if source_corner >= 0 then begin
                      let source_edge = source_corner_edge.(source_corner) in
                      if source_edge >= 0 && Edge_group.mem source_edge source_group
                      then set (target_edge_offsets.(primitive) + local)
                    end
                  done
                done;
                Edge_group.Private.of_owned_bits ~topology:output_topology
                  ~edge_count:target_edge_count ~name:(Edge_group.name source_group)
                  bits) source_groups
            end else begin
              let source_index = Topology_index.create ?cancel topology
              and target_index = Topology_index.create ?cancel output_topology in
              let target_view = Topology_index.Private.view target_index in
              List.map (fun source_group ->
                let builder = Edge_group.Builder.create ~topology:output_topology
                    ~index:target_index ~name:(Edge_group.name source_group) in
                for vertex = 0 to output_vertex_count - 1 do
                  if vertex land 16_383 = 0 then Cancel.check_opt cancel;
                  let source_corner = edge_source_corner.(vertex) in
                  if source_corner >= 0 then begin
                    let source_edge = Topology_index.edge_of_vertex source_index
                        source_corner in
                    let target_edge = target_view.edge_of_vertex.(vertex) in
                    if source_edge >= 0 && target_edge >= 0
                        && Edge_group.mem source_edge source_group then
                      Edge_group.Builder.set builder target_edge true
                  end
                done;
                Edge_group.Builder.freeze builder) source_groups
            end in
      Geometry.create ~positions:(Geometry.positions geometry)
        ~topology:output_topology ~attributes ~groups ~edge_groups ()
    end
  with Curve_error message -> Error message

let carve_inside ?cancel ?grain ?primitives ?(relative_arc_length = true) ?(first = 0.)
    ?(last = 1.) ?first_attribute ?last_attribute
    ?(attribute_mode = Replace) geometry =
  try
    (match grain with Some value when value <= 0 -> fail "grain must be positive"
     | _ -> ());
    if not (finite first && finite last) || first < 0. || last > 1.
        || first >= last then
      fail "Curve Carve requires finite 0 <= first < last <= 1";
    let topology = Geometry.topology geometry in
    let primitive_count = Topology.primitive_count topology in
    validate_selection "Curve Carve" primitives primitive_count;
    let parameters = resolve_carve_parameters ?cancel ~allow_equal:false ~first ~last
        ?first_attribute ?last_attribute ~attribute_mode
        ~selected:(selected primitives) geometry in
    let selected_count = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then incr selected_count
    done;
    if !selected_count = 0 || Option.is_none first_attribute
        && Option.is_none last_attribute && first = 0. && last = 1. then Ok geometry
    else begin
      Cancel.check_opt cancel;
      let source = Topology.Private.view topology in
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let sample_counts = Array.make primitive_count 0
      and cumulative_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        if not (selected primitives primitive) then begin
          sample_counts.(primitive) <- source.primitive_offsets.(primitive + 1)
            - source.primitive_offsets.(primitive);
          cumulative_offsets.(primitive + 1) <- cumulative_offsets.(primitive)
        end else match Topology.primitive_kind topology primitive with
          | Topology.Polygon -> fail (Printf.sprintf
              "Curve Carve primitive %d is a polygon, not a polygon curve" primitive)
          | Topology.Open_polyline | Topology.Closed_polyline ->
            let first_vertex = source.primitive_offsets.(primitive)
            and last_vertex = source.primitive_offsets.(primitive + 1) in
            let count = last_vertex - first_vertex in
            let edges = count - 1 + if Topology.primitive_kind topology primitive
                = Topology.Closed_polyline then 1 else 0 in
            if cumulative_offsets.(primitive) > max_int - edges - 1 then
              fail "Curve Carve cumulative cardinality exceeds OCaml array limits";
            cumulative_offsets.(primitive + 1) <-
              cumulative_offsets.(primitive) + edges + 1
      done;
      let cumulative = Array.make cumulative_offsets.(primitive_count) 0. in
      for primitive = 0 to primitive_count - 1 do
        if primitive land 255 = 0 then Cancel.check_opt cancel;
        if selected primitives primitive then begin
        let first_vertex = source.primitive_offsets.(primitive)
        and last_vertex = source.primitive_offsets.(primitive + 1)
        and base = cumulative_offsets.(primitive) in
        let count = last_vertex - first_vertex in
        let edges = count - 1 + if Topology.primitive_kind topology primitive
            = Topology.Closed_polyline then 1 else 0 in
        for edge = 0 to edges - 1 do
          let left_vertex = first_vertex + (edge mod count)
          and right_vertex = first_vertex + ((edge + 1) mod count) in
          let left = source.vertex_points.(left_vertex)
          and right = source.vertex_points.(right_vertex) in
          let dx = positions.x.(right) -. positions.x.(left)
          and dy = positions.y.(right) -. positions.y.(left)
          and dz = positions.z.(right) -. positions.z.(left) in
          let ax = abs_float dx and ay = abs_float dy and az = abs_float dz in
          let scale_xy = if ax >= ay then ax else ay in
          let scale = if scale_xy >= az then scale_xy else az in
          if not (finite scale) then fail (Printf.sprintf
            "Curve Carve primitive %d has an unrepresentable segment" primitive);
          let length = if scale = 0. then 0. else begin
            let x = dx /. scale and y = dy /. scale and z = dz /. scale in
            let value = scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
            if not (finite value) then fail (Printf.sprintf
              "Curve Carve primitive %d has an unrepresentable segment" primitive);
            value
          end in
          if length <= 1e-20 then fail (Printf.sprintf
            "Curve Carve primitive %d has a zero or non-finite segment" primitive);
          cumulative.(base + edge + 1) <- cumulative.(base + edge) +. length
        done;
        let total = cumulative.(base + edges) in
        if not (finite total) || total <= 1e-20 then fail (Printf.sprintf
          "Curve Carve primitive %d has zero or non-finite length" primitive);
        let count_samples = ref 2 in
        let primitive_first, primitive_last = carve_parameter parameters primitive in
        for local = 1 to edges - 1 do
          let parameter = if relative_arc_length then cumulative.(base + local) /. total
            else float_of_int local /. float_of_int edges in
          if parameter > primitive_first && parameter < primitive_last then
            incr count_samples
        done;
        sample_counts.(primitive) <- !count_samples
        end
      done;
      let primitive_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        if primitive_offsets.(primitive) > max_int - sample_counts.(primitive) then
          fail "Curve Carve output cardinality exceeds OCaml array limits";
        primitive_offsets.(primitive + 1) <- primitive_offsets.(primitive)
          + sample_counts.(primitive)
      done;
      let output_vertex_count = primitive_offsets.(primitive_count) in
      let selected_point_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        selected_point_offsets.(primitive + 1) <-
          selected_point_offsets.(primitive)
          + if selected primitives primitive then sample_counts.(primitive) else 0
      done;
      let retain_source_points = !selected_count < primitive_count in
      let source_point_base = if retain_source_points then source.point_count else 0 in
      let selected_point_count = selected_point_offsets.(primitive_count) in
      if source_point_base > max_int - selected_point_count then
        fail "Curve Carve point cardinality exceeds OCaml array limits";
      let output_point_count = source_point_base + selected_point_count in
      let px = Array.make output_point_count 0.
      and py = Array.make output_point_count 0.
      and pz = Array.make output_point_count 0.
      and point_left = Array.make output_point_count 0
      and point_right = Array.make output_point_count 0
      and point_weight = Array.make output_point_count 0. in
      let vertex_left = if retain_source_points
          then Array.make output_vertex_count 0 else point_left
      and vertex_right = if retain_source_points
          then Array.make output_vertex_count 0 else point_right
      and vertex_weight = if retain_source_points
          then Array.make output_vertex_count 0. else point_weight
      and vertex_points = Array.make output_vertex_count 0
      and source_edge = Array.make output_vertex_count 0
      and source_edge_t = Array.make output_vertex_count 0. in
      if retain_source_points then begin
        Array.blit positions.x 0 px 0 source.point_count;
        Array.blit positions.y 0 py 0 source.point_count;
        Array.blit positions.z 0 pz 0 source.point_count;
        for point = 0 to source.point_count - 1 do
          point_left.(point) <- point;
          point_right.(point) <- point
        done
      end;
      let locate primitive parameter vertex_output point_output =
        let first_vertex = source.primitive_offsets.(primitive)
        and last_vertex = source.primitive_offsets.(primitive + 1)
        and base = cumulative_offsets.(primitive) in
        let count = last_vertex - first_vertex in
        let edges = count - 1 + if Topology.primitive_kind topology primitive
            = Topology.Closed_polyline then 1 else 0 in
        let total = cumulative.(base + edges) in
        let edge = ref 0 and t = ref 0. in
        if relative_arc_length then begin
          let distance = parameter *. total in
          let low = ref 1 and high = ref (edges + 1) in
          while !low < !high do
            let middle = !low + ((!high - !low) / 2) in
            if cumulative.(base + middle) <= distance then low := middle + 1
            else high := middle
          done;
          edge := min (edges - 1) (!low - 1);
          let start = cumulative.(base + !edge)
          and length = cumulative.(base + !edge + 1) -. cumulative.(base + !edge) in
          t := (distance -. start) /. length
        end else begin
          let coordinate = parameter *. float_of_int edges in
          edge := min (edges - 1) (int_of_float (floor coordinate));
          t := coordinate -. float_of_int !edge
        end;
        if !t >= 1. -. 1e-12 && !edge + 1 < edges then begin
          incr edge; t := 0.
        end;
        let left_vertex = first_vertex + (!edge mod count)
        and right_vertex = first_vertex + ((!edge + 1) mod count) in
        let left_point = source.vertex_points.(left_vertex)
        and right_point = source.vertex_points.(right_vertex) in
        point_left.(point_output) <- left_point;
        point_right.(point_output) <- right_point;
        point_weight.(point_output) <- !t;
        vertex_left.(vertex_output) <- left_vertex;
        vertex_right.(vertex_output) <- right_vertex;
        vertex_weight.(vertex_output) <- !t;
        vertex_points.(vertex_output) <- point_output;
        source_edge.(vertex_output) <- !edge;
        source_edge_t.(vertex_output) <- !t;
        let interpolate left right =
          let delta = right -. left in
          if finite delta then left +. (delta *. !t)
          else (left *. (1. -. !t)) +. (right *. !t) in
        px.(point_output) <- interpolate positions.x.(left_point)
            positions.x.(right_point);
        py.(point_output) <- interpolate positions.y.(left_point)
            positions.y.(right_point);
        pz.(point_output) <- interpolate positions.z.(left_point)
            positions.z.(right_point) in
      let install_exact primitive local vertex_output point_output =
        let first_vertex = source.primitive_offsets.(primitive)
        and last_vertex = source.primitive_offsets.(primitive + 1) in
        let count = last_vertex - first_vertex in
        let left_vertex = first_vertex + local
        and right_vertex = first_vertex + ((local + 1) mod count) in
        let left_point = source.vertex_points.(left_vertex)
        and right_point = source.vertex_points.(right_vertex) in
        point_left.(point_output) <- left_point;
        point_right.(point_output) <- right_point;
        vertex_left.(vertex_output) <- left_vertex;
        vertex_right.(vertex_output) <- right_vertex;
        vertex_points.(vertex_output) <- point_output;
        source_edge.(vertex_output) <- local;
        source_edge_t.(vertex_output) <- 0.;
        px.(point_output) <- positions.x.(left_point);
        py.(point_output) <- positions.y.(left_point);
        pz.(point_output) <- positions.z.(left_point) in
      run_ranges ?grain primitive_count (fun first_primitive last_primitive ->
        Cancel.check_opt cancel;
        for primitive = first_primitive to last_primitive - 1 do
          let output_first = primitive_offsets.(primitive) in
          let first_vertex = source.primitive_offsets.(primitive)
          and last_vertex = source.primitive_offsets.(primitive + 1) in
          if not (selected primitives primitive) then
            for vertex = first_vertex to last_vertex - 1 do
              let output = output_first + vertex - first_vertex
              and point = source.vertex_points.(vertex) in
              vertex_points.(output) <- point;
              vertex_left.(output) <- vertex;
              vertex_right.(output) <- vertex;
              source_edge.(output) <- vertex - first_vertex
            done
          else begin
            let base = cumulative_offsets.(primitive)
            and point_first = source_point_base
                + selected_point_offsets.(primitive) in
            let count = last_vertex - first_vertex in
            let edges = count - 1 + if Topology.primitive_kind topology primitive
                = Topology.Closed_polyline then 1 else 0 in
            let total = cumulative.(base + edges) in
            let primitive_first, primitive_last = carve_parameter parameters primitive in
            locate primitive primitive_first output_first point_first;
            let output = ref (output_first + 1)
            and point_output = ref (point_first + 1) in
            for local = 1 to edges - 1 do
              let parameter = if relative_arc_length
                then cumulative.(base + local) /. total
                else float_of_int local /. float_of_int edges in
              if parameter > primitive_first && parameter < primitive_last then begin
                install_exact primitive local !output !point_output;
                incr output; incr point_output
              end
            done;
            locate primitive primitive_last !output !point_output
          end
        done);
      let primitive_kinds = Array.init primitive_count (fun primitive ->
        if selected primitives primitive then Topology.Open_polyline
        else Topology.primitive_kind topology primitive) in
      let topology = Topology.create_owned ~point_count:output_point_count
          ~vertex_points ~primitive_offsets ~primitive_kinds
          |> Result.get_ok in
      let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
      let attributes = List.map (interpolate_attribute ?cancel ?grain point_left
        point_right point_weight vertex_left vertex_right vertex_weight)
          (Geometry.attributes geometry) in
      let groups = List.map (fun group -> match Group.owner group with
        | Group.Primitive -> group
        | Group.Point ->
            let source output =
              (if point_weight.(output) < 0.5 then point_left else point_right).(output) in
            let target = Group.init ?grain ~owner:Group.Point
                ~name:(Group.name group) output_point_count
                (fun output -> Group.mem (source output) group) in
            if not (Group.is_ordered group) then target
            else
              let mapping = Array.init output_point_count source in
              Group.Private.remap_order ~source:group
                ~source_of_target:mapping target
        | Group.Vertex ->
            let source output =
              (if vertex_weight.(output) < 0.5 then vertex_left else vertex_right).(output) in
            let target = Group.init ?grain ~owner:Group.Vertex
                ~name:(Group.name group) output_vertex_count
                (fun output -> Group.mem (source output) group) in
            if not (Group.is_ordered group) then target
            else
              let mapping = Array.init output_vertex_count source in
              Group.Private.remap_order ~source:group
                ~source_of_target:mapping target)
          (Geometry.groups geometry) in
      let edge_groups = match Geometry.edge_groups geometry with
        | [] -> []
        | source_groups ->
            let source_index = Topology_index.create ?cancel
                (Geometry.topology geometry) in
            if not retain_source_points then begin
              let output_edge_count = output_vertex_count - primitive_count in
              List.map (fun source_group ->
                let bits = Bytes.make ((output_edge_count + 7) / 8) '\000' in
                let set edge =
                  let byte = edge lsr 3 and mask = 1 lsl (edge land 7) in
                  Bytes.set bits byte
                    (Char.chr (Char.code (Bytes.get bits byte) lor mask)) in
                for primitive = 0 to primitive_count - 1 do
                  let source_first = source.primitive_offsets.(primitive)
                  and output_first = primitive_offsets.(primitive)
                  and output_last = primitive_offsets.(primitive + 1) in
                  for output = output_first to output_last - 2 do
                    let first_edge = source_edge.(output) in
                    let last_edge = if source_edge_t.(output + 1) <= 1e-12
                      then source_edge.(output + 1) - 1
                      else source_edge.(output + 1) in
                    let all = ref true in
                    for local = first_edge to last_edge do
                      let edge = Topology_index.edge_of_vertex source_index
                          (source_first + local) in
                      if edge < 0 || not (Edge_group.mem edge source_group) then
                        all := false
                    done;
                    if !all then set (output - primitive)
                  done
                done;
                Edge_group.Private.of_owned_bits ~topology
                  ~edge_count:output_edge_count ~name:(Edge_group.name source_group)
                  bits) source_groups
            end else begin
            let output_index = Topology_index.create ?cancel topology in
            let output_edge_count = Topology_index.edge_count output_index in
            List.map (fun source_group ->
              let bits = Bytes.make ((output_edge_count + 7) / 8) '\000' in
              let set edge =
                let byte = edge lsr 3 and mask = 1 lsl (edge land 7) in
                Bytes.set bits byte
                  (Char.chr (Char.code (Bytes.get bits byte) lor mask)) in
              for primitive = 0 to primitive_count - 1 do
                let source_first = source.primitive_offsets.(primitive)
                and output_first = primitive_offsets.(primitive)
                and output_last = primitive_offsets.(primitive + 1) in
                if not (selected primitives primitive) then begin
                  let size = output_last - output_first in
                  let edge_count = size - 1 +
                    if primitive_kinds.(primitive) = Topology.Open_polyline
                    then 0 else 1 in
                  for local = 0 to edge_count - 1 do
                    let source_edge = Topology_index.edge_of_vertex source_index
                        (source_first + local)
                    and target_edge = Topology_index.edge_of_vertex output_index
                        (output_first + local) in
                    if source_edge >= 0 && target_edge >= 0
                        && Edge_group.mem source_edge source_group then set target_edge
                  done
                end else
                  for output = output_first to output_last - 2 do
                    let first_edge = source_edge.(output) in
                    let last_edge = if source_edge_t.(output + 1) <= 1e-12
                      then source_edge.(output + 1) - 1
                      else source_edge.(output + 1) in
                    let all = ref true in
                    for local = first_edge to last_edge do
                      let edge = Topology_index.edge_of_vertex source_index
                          (source_first + local) in
                      if edge < 0 || not (Edge_group.mem edge source_group) then
                        all := false
                    done;
                    let target_edge = Topology_index.edge_of_vertex output_index
                        output in
                    if !all && target_edge >= 0 then set target_edge
                  done
              done;
              Edge_group.Private.of_owned_bits ~topology
                ~edge_count:output_edge_count ~name:(Edge_group.name source_group)
                bits) source_groups
            end in
      Geometry.create ~positions ~topology ~attributes ~groups ~edge_groups ()
    end
  with Curve_error message -> Error message

let carve_cut ?cancel ?grain ?primitives ?(relative_arc_length = true)
    ?(first = 0.) ?(last = 1.) ?first_attribute ?last_attribute
    ?(attribute_mode = Replace) ?(divisions = 1) mode geometry =
  try
    (match grain with Some value when value <= 0 -> fail "grain must be positive"
     | _ -> ());
    if divisions <= 0 then fail "Curve Carve cut divisions must be positive";
    if not (finite first && finite last) || first < 0. || last > 1.
        || first >= last then
      fail "Curve Carve requires finite 0 <= first < last <= 1";
    Cancel.check_opt cancel;
    let source_topology = Geometry.topology geometry in
    let source = Topology.Private.view source_topology in
    let primitive_count = Topology.primitive_count source_topology in
    validate_selection "Curve Carve" primitives primitive_count;
    let parameters = resolve_carve_parameters ?cancel ~allow_equal:false ~first ~last
        ?first_attribute ?last_attribute ~attribute_mode
        ~selected:(selected primitives) geometry in
    let selected_count = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        incr selected_count;
        if Topology.primitive_kind source_topology primitive = Topology.Polygon then
          fail (Printf.sprintf
            "Curve Carve primitive %d is a polygon, not a polygon curve" primitive)
      end
    done;
    if !selected_count = 0
        || mode = Inside_and_outside && Option.is_none first_attribute
          && Option.is_none last_attribute && first = 0. && last = 1. then Ok geometry
    else begin
      let per_selected = match mode with
        | Inside -> divisions
        | Outside -> 2
        | Inside_and_outside ->
            if divisions > Sys.max_array_length - 2 then
              fail "Curve Carve cut descriptor count exceeds array limits";
            divisions + 2 in
      let unselected_count = primitive_count - !selected_count in
      if per_selected <> 0
          && !selected_count > (Sys.max_array_length - unselected_count)
               / per_selected then
        fail "Curve Carve cut descriptor count exceeds array limits";
      let descriptor_capacity = unselected_count + (!selected_count * per_selected) in
      let descriptor_source_full = Array.make descriptor_capacity 0
      and descriptor_kind_full = Bytes.make descriptor_capacity '\000'
      and descriptor_first_full = Array.make descriptor_capacity 0.
      and descriptor_last_full = Array.make descriptor_capacity 1. in
      let descriptor_count = ref 0 in
      let add primitive kind a b =
        let target = !descriptor_count in incr descriptor_count;
        descriptor_source_full.(target) <- primitive;
        Bytes.set descriptor_kind_full target (Char.chr kind);
        descriptor_first_full.(target) <- a;
        descriptor_last_full.(target) <- b in
      for primitive = 0 to primitive_count - 1 do
        if not (selected primitives primitive) then add primitive 0 0. 1.
        else begin
          let primitive_first, primitive_last = carve_parameter parameters primitive in
          let closed = Topology.primitive_kind source_topology primitive
              = Topology.Closed_polyline in
          let add_inside () =
            let span = primitive_last -. primitive_first in
            for division = 0 to divisions - 1 do
              let a = if division = 0 then primitive_first
                else primitive_first
                  +. (span *. float_of_int division /. float_of_int divisions) in
              let b = if division + 1 = divisions then primitive_last
                else primitive_first
                  +. (span *. float_of_int (division + 1)
                      /. float_of_int divisions) in
              add primitive 1 a b
            done in
          let add_outside () =
            if closed && primitive_first > 0. && primitive_last < 1. then
              add primitive 2 primitive_last primitive_first
            else begin
              if primitive_first > 0. then add primitive 1 0. primitive_first;
              if primitive_last < 1. then add primitive 1 primitive_last 1.
            end in
          match mode with
          | Inside -> add_inside ()
          | Outside -> add_outside ()
          | Inside_and_outside ->
              if closed then begin
                add_inside (); add_outside () end
              else begin
                if primitive_first > 0. then add primitive 1 0. primitive_first;
                add_inside ();
                if primitive_last < 1. then add primitive 1 primitive_last 1.
              end
        end
      done;
      let descriptor_count = !descriptor_count in
      let descriptor_source = Array.sub descriptor_source_full 0 descriptor_count
      and descriptor_kind = Bytes.sub descriptor_kind_full 0 descriptor_count
      and descriptor_first = Array.sub descriptor_first_full 0 descriptor_count
      and descriptor_last = Array.sub descriptor_last_full 0 descriptor_count in
      let cumulative_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        let size = source.primitive_offsets.(primitive + 1)
            - source.primitive_offsets.(primitive) in
        let edges = if selected primitives primitive then size - 1
            + if Topology.primitive_kind source_topology primitive
                = Topology.Closed_polyline then 1 else 0 else 0 in
        if cumulative_offsets.(primitive) > max_int - edges - 1 then
          fail "Curve Carve cumulative storage exceeds array limits";
        cumulative_offsets.(primitive + 1) <- cumulative_offsets.(primitive)
          + if edges = 0 then 0 else edges + 1
      done;
      let cumulative = Array.make cumulative_offsets.(primitive_count) 0.
      and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      for primitive = 0 to primitive_count - 1 do
        if selected primitives primitive then begin
          if primitive land 255 = 0 then Cancel.check_opt cancel;
          let first_vertex = source.primitive_offsets.(primitive)
          and last_vertex = source.primitive_offsets.(primitive + 1)
          and base = cumulative_offsets.(primitive) in
          let count = last_vertex - first_vertex in
          let edges = count - 1 + if Topology.primitive_kind source_topology
              primitive = Topology.Closed_polyline then 1 else 0 in
          for edge = 0 to edges - 1 do
            let left = source.vertex_points.(first_vertex + (edge mod count))
            and right = source.vertex_points.
                (first_vertex + ((edge + 1) mod count)) in
            let dx = positions.x.(right) -. positions.x.(left)
            and dy = positions.y.(right) -. positions.y.(left)
            and dz = positions.z.(right) -. positions.z.(left) in
            let ax = abs_float dx and ay = abs_float dy and az = abs_float dz in
            let scale_xy = if ax >= ay then ax else ay in
            let scale = if scale_xy >= az then scale_xy else az in
            if not (finite scale) then fail (Printf.sprintf
              "Curve Carve primitive %d has an unrepresentable segment" primitive);
            let length = if scale = 0. then 0. else begin
              let x = dx /. scale and y = dy /. scale and z = dz /. scale in
              scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z)) end in
            if not (finite length) || length <= 1e-20 then fail (Printf.sprintf
              "Curve Carve primitive %d has a zero or non-finite segment" primitive);
            cumulative.(base + edge + 1) <- cumulative.(base + edge) +. length
          done;
          if not (finite cumulative.(base + edges)) then fail (Printf.sprintf
            "Curve Carve primitive %d has unrepresentable total length" primitive)
        end
      done;
      let parameter_of_local primitive local =
        let first_vertex = source.primitive_offsets.(primitive)
        and last_vertex = source.primitive_offsets.(primitive + 1)
        and base = cumulative_offsets.(primitive) in
        let count = last_vertex - first_vertex in
        let edges = count - 1 + if Topology.primitive_kind source_topology
            primitive = Topology.Closed_polyline then 1 else 0 in
        if relative_arc_length then cumulative.(base + local)
            /. cumulative.(base + edges)
        else float_of_int local /. float_of_int edges in
      let first_local_after primitive edges parameter =
        let lower = ref 1 and upper = ref edges in
        while !lower < !upper do
          let middle = !lower + ((!upper - !lower) / 2) in
          if parameter_of_local primitive middle <= parameter
          then lower := middle + 1 else upper := middle
        done;
        !lower in
      let first_local_at_or_after primitive edges parameter =
        let lower = ref 1 and upper = ref edges in
        while !lower < !upper do
          let middle = !lower + ((!upper - !lower) / 2) in
          if parameter_of_local primitive middle < parameter
          then lower := middle + 1 else upper := middle
        done;
        !lower in
      let output_sizes = Array.make descriptor_count 0 in
      for descriptor = 0 to descriptor_count - 1 do
        let primitive = descriptor_source.(descriptor) in
        if Char.code (Bytes.get descriptor_kind descriptor) = 0 then
          output_sizes.(descriptor) <- source.primitive_offsets.(primitive + 1)
            - source.primitive_offsets.(primitive)
        else begin
          let count = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          let edges = count - 1 + if Topology.primitive_kind source_topology
              primitive = Topology.Closed_polyline then 1 else 0 in
          let size = ref (if Char.code (Bytes.get descriptor_kind descriptor) = 2
            then 3 else 2) in
          let first_after = first_local_after primitive edges
              descriptor_first.(descriptor)
          and first_at_last = first_local_at_or_after primitive edges
              descriptor_last.(descriptor) in
          if Char.code (Bytes.get descriptor_kind descriptor) = 2 then
            size := !size + (edges - first_after) + (first_at_last - 1)
          else size := !size + max 0 (first_at_last - first_after);
          output_sizes.(descriptor) <- !size
        end
      done;
      let primitive_offsets = Array.make (descriptor_count + 1) 0 in
      for descriptor = 0 to descriptor_count - 1 do
        if primitive_offsets.(descriptor) > max_int - output_sizes.(descriptor) then
          fail "Curve Carve cut output exceeds array limits";
        primitive_offsets.(descriptor + 1) <- primitive_offsets.(descriptor)
          + output_sizes.(descriptor)
      done;
      let output_vertex_count = primitive_offsets.(descriptor_count) in
      let unselected = !selected_count < primitive_count in
      let source_point_base = if unselected then source.point_count else 0 in
      let selected_points = ref 0 in
      for descriptor = 0 to descriptor_count - 1 do
        if Char.code (Bytes.get descriptor_kind descriptor) <> 0 then begin
          if !selected_points > max_int - output_sizes.(descriptor) then
            fail "Curve Carve selected point count exceeds array limits";
          selected_points := !selected_points + output_sizes.(descriptor)
        end
      done;
      if source_point_base > max_int - !selected_points then
        fail "Curve Carve cut point count exceeds array limits";
      let output_point_count = source_point_base + !selected_points in
      let px = Array.make output_point_count 0. and py = Array.make output_point_count 0.
      and pz = Array.make output_point_count 0.
      and point_left = Array.make output_point_count 0
      and point_right = Array.make output_point_count 0
      and point_weight = Array.make output_point_count 0. in
      let vertex_left = if unselected then Array.make output_vertex_count 0
        else point_left
      and vertex_right = if unselected then Array.make output_vertex_count 0
        else point_right
      and vertex_weight = if unselected then Array.make output_vertex_count 0.
        else point_weight
      and vertex_points = Array.make output_vertex_count 0
      and source_edge = Array.make output_vertex_count 0
      and source_edge_t = Array.make output_vertex_count 0. in
      if unselected then begin
        Array.blit positions.x 0 px 0 source.point_count;
        Array.blit positions.y 0 py 0 source.point_count;
        Array.blit positions.z 0 pz 0 source.point_count;
        for point = 0 to source.point_count - 1 do
          point_left.(point) <- point; point_right.(point) <- point
        done
      end;
      let selected_point_offsets = Array.make (descriptor_count + 1) 0 in
      for descriptor = 0 to descriptor_count - 1 do
        selected_point_offsets.(descriptor + 1) <- selected_point_offsets.(descriptor)
          + if Char.code (Bytes.get descriptor_kind descriptor) = 0 then 0
            else output_sizes.(descriptor)
      done;
      let locate primitive parameter vertex_output point_output =
        let first_vertex = source.primitive_offsets.(primitive)
        and last_vertex = source.primitive_offsets.(primitive + 1)
        and base = cumulative_offsets.(primitive) in
        let count = last_vertex - first_vertex in
        let edges = count - 1 + if Topology.primitive_kind source_topology
            primitive = Topology.Closed_polyline then 1 else 0 in
        let edge, t = if relative_arc_length then begin
            let distance = parameter *. cumulative.(base + edges) in
            let low = ref 1 and high = ref (edges + 1) in
            while !low < !high do
              let middle = !low + ((!high - !low) / 2) in
              if cumulative.(base + middle) <= distance then low := middle + 1
              else high := middle
            done;
            let edge = min (edges - 1) (!low - 1) in
            edge, (distance -. cumulative.(base + edge))
              /. (cumulative.(base + edge + 1) -. cumulative.(base + edge))
          end else
            let coordinate = parameter *. float_of_int edges in
            let edge = min (edges - 1) (int_of_float (floor coordinate)) in
            edge, coordinate -. float_of_int edge in
        let left_vertex = first_vertex + (edge mod count)
        and right_vertex = first_vertex + ((edge + 1) mod count) in
        let left_point = source.vertex_points.(left_vertex)
        and right_point = source.vertex_points.(right_vertex) in
        point_left.(point_output) <- left_point; point_right.(point_output) <- right_point;
        point_weight.(point_output) <- t; vertex_left.(vertex_output) <- left_vertex;
        vertex_right.(vertex_output) <- right_vertex; vertex_weight.(vertex_output) <- t;
        vertex_points.(vertex_output) <- point_output; source_edge.(vertex_output) <- edge;
        source_edge_t.(vertex_output) <- t;
        let lerp left right = let delta = right -. left in
          if finite delta then left +. delta *. t
          else left *. (1. -. t) +. right *. t in
        px.(point_output) <- lerp positions.x.(left_point) positions.x.(right_point);
        py.(point_output) <- lerp positions.y.(left_point) positions.y.(right_point);
        pz.(point_output) <- lerp positions.z.(left_point) positions.z.(right_point) in
      let exact primitive local vertex_output point_output =
        let first_vertex = source.primitive_offsets.(primitive)
        and count = source.primitive_offsets.(primitive + 1)
            - source.primitive_offsets.(primitive) in
        let vertex = first_vertex + local
        and right_vertex = first_vertex + ((local + 1) mod count) in
        let point = source.vertex_points.(vertex) in
        point_left.(point_output) <- point; point_right.(point_output) <- point;
        vertex_left.(vertex_output) <- vertex; vertex_right.(vertex_output) <- vertex;
        vertex_points.(vertex_output) <- point_output; source_edge.(vertex_output) <- local;
        px.(point_output) <- positions.x.(point); py.(point_output) <- positions.y.(point);
        pz.(point_output) <- positions.z.(point);
        ignore right_vertex in
      run_ranges ?grain descriptor_count (fun first_descriptor last_descriptor ->
        Cancel.check_opt cancel;
        for descriptor = first_descriptor to last_descriptor - 1 do
          let primitive = descriptor_source.(descriptor)
          and output_first = primitive_offsets.(descriptor) in
          let kind = Char.code (Bytes.get descriptor_kind descriptor) in
          if kind = 0 then begin
            let source_first = source.primitive_offsets.(primitive)
            and source_last = source.primitive_offsets.(primitive + 1) in
            for vertex = source_first to source_last - 1 do
              let output = output_first + vertex - source_first in
              vertex_left.(output) <- vertex; vertex_right.(output) <- vertex;
              vertex_points.(output) <- source.vertex_points.(vertex);
              source_edge.(output) <- vertex - source_first
            done
          end else begin
            let point_first = source_point_base + selected_point_offsets.(descriptor)
            and a = descriptor_first.(descriptor) and b = descriptor_last.(descriptor) in
            locate primitive a output_first point_first;
            let output = ref (output_first + 1) and point = ref (point_first + 1) in
            let count = source.primitive_offsets.(primitive + 1)
                - source.primitive_offsets.(primitive) in
            let edges = count - 1 + if Topology.primitive_kind source_topology
                primitive = Topology.Closed_polyline then 1 else 0 in
            let first_after = first_local_after primitive edges a
            and first_at_last = first_local_at_or_after primitive edges b in
            if kind = 2 then begin
              for local = first_after to edges - 1 do
                exact primitive local !output !point; incr output; incr point
              done;
              exact primitive 0 !output !point; incr output; incr point;
              for local = 1 to first_at_last - 1 do
                exact primitive local !output !point; incr output; incr point
              done
            end else for local = first_after to first_at_last - 1 do
              exact primitive local !output !point; incr output; incr point
            done;
            locate primitive b !output !point
          end
        done);
      let primitive_kinds = Array.init descriptor_count (fun descriptor ->
        if Char.code (Bytes.get descriptor_kind descriptor) = 0 then
          Topology.primitive_kind source_topology descriptor_source.(descriptor)
        else Topology.Open_polyline) in
      let output_topology = Topology.create_owned ~point_count:output_point_count
          ~vertex_points ~primitive_offsets ~primitive_kinds |> Result.get_ok in
      let attributes = List.map (fun attribute -> match Attribute.owner attribute with
        | Attribute.Point -> interpolate_attribute ?cancel ?grain point_left point_right
            point_weight [||] [||] [||] attribute
        | Attribute.Vertex -> interpolate_attribute ?cancel ?grain [||] [||] [||]
            vertex_left vertex_right vertex_weight attribute
        | Attribute.Primitive -> remap_attribute ?cancel ?grain descriptor_source attribute
        | Attribute.Detail -> attribute) (Geometry.attributes geometry) in
      let groups = List.map (fun group ->
        let mapping = match Group.owner group with
          | Group.Point -> Array.init output_point_count (fun point ->
              (if point_weight.(point) < 0.5 then point_left else point_right).(point))
          | Group.Vertex -> Array.init output_vertex_count (fun vertex ->
              (if vertex_weight.(vertex) < 0.5 then vertex_left else vertex_right).(vertex))
          | Group.Primitive -> descriptor_source in
        let target = Group.init ?grain ~owner:(Group.owner group) ~name:(Group.name group)
            (Array.length mapping) (fun target -> Group.mem mapping.(target) group) in
        Group.Private.remap_order ~source:group ~source_of_target:mapping target)
          (Geometry.groups geometry) in
      let edge_groups = match Geometry.edge_groups geometry with
      | [] -> []
      | source_groups ->
      let source_index = Topology_index.create ?cancel source_topology in
      let target_index = if unselected
        then Some (Topology_index.create ?cancel output_topology) else None in
      let target_edge_count = match target_index with
        | Some index -> Topology_index.edge_count index
        | None -> output_vertex_count - descriptor_count in
      let target_edge descriptor vertex = match target_index with
        | Some index -> Topology_index.edge_of_vertex index vertex
        | None -> vertex - descriptor in
      List.map (fun source_group ->
        let bits = Bytes.make ((target_edge_count + 7) / 8) '\000' in
        let set edge = let byte = edge lsr 3 and mask = 1 lsl (edge land 7) in
          Bytes.set bits byte (Char.chr (Char.code (Bytes.get bits byte) lor mask)) in
        for descriptor = 0 to descriptor_count - 1 do
          let primitive = descriptor_source.(descriptor)
          and output_first = primitive_offsets.(descriptor)
          and output_last = primitive_offsets.(descriptor + 1) in
          let source_first = source.primitive_offsets.(primitive) in
          if Char.code (Bytes.get descriptor_kind descriptor) = 0 then begin
            let edges = output_last - output_first - 1 +
              if primitive_kinds.(descriptor) = Topology.Open_polyline then 0 else 1 in
            for local = 0 to edges - 1 do
              let source_edge_id = Topology_index.edge_of_vertex source_index
                  (source_first + local)
              and target_edge = target_edge descriptor (output_first + local) in
              if source_edge_id >= 0 && target_edge >= 0
                  && Edge_group.mem source_edge_id source_group then set target_edge
            done
          end else begin
            let source_size = source.primitive_offsets.(primitive + 1) - source_first in
            let source_edges = source_size - 1 + if Topology.primitive_kind source_topology
                primitive = Topology.Closed_polyline then 1 else 0 in
            for output = output_first to output_last - 2 do
              let first_edge = source_edge.(output)
              and next_edge = source_edge.(output + 1) in
              let last_edge = if source_edge_t.(output + 1) > 1e-12 then next_edge
                else if next_edge = 0 && first_edge > 0 then source_edges - 1
                else next_edge - 1 in
              let all = ref true in
              let check from_ to_ = for local = from_ to to_ do
                let edge = Topology_index.edge_of_vertex source_index
                    (source_first + local) in
                if edge < 0 || not (Edge_group.mem edge source_group) then all := false
              done in
              if last_edge >= first_edge then check first_edge last_edge
              else begin check first_edge (source_edges - 1); check 0 last_edge end;
              let target_edge = target_edge descriptor output in
              if !all && target_edge >= 0 then set target_edge
            done
          end
        done;
        Edge_group.Private.of_owned_bits ~topology:output_topology
          ~edge_count:target_edge_count ~name:(Edge_group.name source_group) bits)
          source_groups in
      Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz)
        ~topology:output_topology ~attributes ~groups ~edge_groups ()
    end
  with Curve_error message -> Error message

type breakpoint_table =
  | Uniform_breakpoints
  | Arc_breakpoints of { offsets : int array; cumulative : float array }

let build_breakpoint_table ?cancel ~relative_arc_length ~selected geometry =
  if not relative_arc_length then Uniform_breakpoints
  else begin
    let topology = Geometry.topology geometry in
    let source = Topology.Private.view topology in
    let primitive_count = Topology.primitive_count topology in
    let offsets = Array.make (primitive_count + 1) 0 in
    for primitive = 0 to primitive_count - 1 do
      let edges = if selected primitive then
          let count = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          count - 1 + if Topology.primitive_kind topology primitive
              = Topology.Closed_polyline then 1 else 0
        else 0 in
      if offsets.(primitive) > max_int - edges - 1 then
        fail "Curve Carve breakpoint storage exceeds OCaml array limits";
      offsets.(primitive + 1) <- offsets.(primitive)
          + if edges = 0 then 0 else edges + 1
    done;
    let cumulative = Array.make offsets.(primitive_count) 0.
    and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    for primitive = 0 to primitive_count - 1 do
      if primitive land 255 = 0 then Cancel.check_opt cancel;
      if selected primitive then begin
        let first_vertex = source.primitive_offsets.(primitive)
        and count = source.primitive_offsets.(primitive + 1)
            - source.primitive_offsets.(primitive)
        and base = offsets.(primitive) in
        let edges = count - 1 + if Topology.primitive_kind topology primitive
            = Topology.Closed_polyline then 1 else 0 in
        for edge = 0 to edges - 1 do
          let left = source.vertex_points.(first_vertex + (edge mod count))
          and right = source.vertex_points.
              (first_vertex + ((edge + 1) mod count)) in
          let dx = positions.x.(right) -. positions.x.(left)
          and dy = positions.y.(right) -. positions.y.(left)
          and dz = positions.z.(right) -. positions.z.(left) in
          let ax = abs_float dx and ay = abs_float dy and az = abs_float dz in
          let scale_xy = if ax >= ay then ax else ay in
          let scale = if scale_xy >= az then scale_xy else az in
          if not (finite scale) then fail (Printf.sprintf
            "Curve Carve primitive %d has an unrepresentable segment" primitive);
          let length = if scale = 0. then 0. else begin
            let x = dx /. scale and y = dy /. scale and z = dz /. scale in
            scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z)) end in
          if not (finite length) || length <= 1e-20 then fail (Printf.sprintf
            "Curve Carve primitive %d has a zero or non-finite segment" primitive);
          cumulative.(base + edge + 1) <- cumulative.(base + edge) +. length
        done;
        if not (finite cumulative.(base + edges)) then fail (Printf.sprintf
          "Curve Carve primitive %d has unrepresentable total length" primitive)
      end
    done;
    Arc_breakpoints { offsets; cumulative }
  end

let breakpoint_parameter table primitive edges local = match table with
  | Uniform_breakpoints -> float_of_int local /. float_of_int edges
  | Arc_breakpoints { offsets; cumulative } ->
      let base = offsets.(primitive) in
      cumulative.(base + local) /. cumulative.(base + edges)

let breakpoint_interval table primitive edges first last =
  let lower = ref 0 and upper = ref (edges + 1) in
  while !lower < !upper do
    let middle = !lower + ((!upper - !lower) / 2) in
    if breakpoint_parameter table primitive edges middle < first
    then lower := middle + 1 else upper := middle
  done;
  let first_local = !lower in
  lower := 0; upper := edges + 1;
  while !lower < !upper do
    let middle = !lower + ((!upper - !lower) / 2) in
    if breakpoint_parameter table primitive edges middle <= last
    then lower := middle + 1 else upper := middle
  done;
  first_local, !lower - 1

let remap_exact_groups ?cancel ?grain ~point_map ~vertex_map ~primitive_map geometry =
  Topology_remap.groups ?cancel ~grain:(Option.value ~default:16_384 grain)
    ~point_map ~vertex_map ~primitive_map geometry

let remap_exact_attributes ?cancel ?grain ~point_map ~vertex_map ~primitive_map
    geometry =
  Topology_remap.attributes ?cancel ~grain:(Option.value ~default:16_384 grain)
    ~point_map ~vertex_map ~primitive_map geometry

let extract_breakpoint_points ?cancel ?grain ?primitives
    ?(relative_arc_length = true) ?(first = 0.) ?(last = 1.) ?first_attribute
    ?last_attribute ?(attribute_mode = Replace) ?(divisions = 1)
    ?(keep_original = false) ?(all_internal = false) geometry =
  try
    (match grain with Some value when value <= 0 -> fail "grain must be positive"
     | _ -> ());
    if divisions <= 0 then fail "Curve Carve extraction divisions must be positive";
    if not (finite first && finite last) || first < 0. || last > 1.
        || first > last then
      fail "Curve Carve extraction requires finite 0 <= first <= last <= 1";
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let source = Topology.Private.view topology in
    let primitive_count = Topology.primitive_count topology in
    validate_selection "Curve Carve" primitives primitive_count;
    let parameters = resolve_carve_parameters ?cancel ~allow_equal:true ~first ~last
        ?first_attribute ?last_attribute ~attribute_mode
        ~selected:(selected primitives) geometry in
    let selected_count = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        incr selected_count;
        if Topology.primitive_kind topology primitive = Topology.Polygon then
          fail (Printf.sprintf
            "Curve Carve primitive %d is a polygon, not a polygon curve" primitive)
      end
    done;
    if !selected_count = 0 then Ok geometry else begin
      let table = build_breakpoint_table ?cancel ~relative_arc_length
          ~selected:(selected primitives) geometry in
      let sample_counts = Array.make primitive_count 0
      and first_locals = Array.make primitive_count 0
      and last_locals = Array.make primitive_count (-1) in
      for primitive = 0 to primitive_count - 1 do
        if selected primitives primitive then begin
          let count = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          let edges = count - 1 + if Topology.primitive_kind topology primitive
              = Topology.Closed_polyline then 1 else 0 in
          let a, b = carve_parameter parameters primitive in
          let first_local, last_local = breakpoint_interval table primitive edges a b in
          first_locals.(primitive) <- first_local;
          last_locals.(primitive) <- last_local;
          if first_local <= last_local then
            sample_counts.(primitive) <- if all_internal
              then last_local - first_local + 1
              else if first_local = last_local then 1 else 2
        end
      done;
      let sample_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        if sample_offsets.(primitive) > max_int - sample_counts.(primitive) then
          fail "Curve Carve breakpoint extraction exceeds OCaml array limits";
        sample_offsets.(primitive + 1) <- sample_offsets.(primitive)
            + sample_counts.(primitive)
      done;
      let keep_primitive primitive = keep_original
          || not (selected primitives primitive) in
      let retained_count = primitive_count
          - if keep_original then 0 else !selected_count in
      let primitive_map = Array.make retained_count 0
      and primitive_offsets = Array.make (retained_count + 1) 0
      and primitive_kinds = Array.make retained_count Topology.Open_polyline in
      let retained_vertices = ref 0 and target_primitive = ref 0 in
      for primitive = 0 to primitive_count - 1 do
        if keep_primitive primitive then begin
          let size = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          if !retained_vertices > max_int - size then
            fail "Curve Carve breakpoint topology exceeds OCaml array limits";
          primitive_map.(!target_primitive) <- primitive;
          retained_vertices := !retained_vertices + size;
          primitive_offsets.(!target_primitive + 1) <- !retained_vertices;
          primitive_kinds.(!target_primitive) <- Topology.primitive_kind topology primitive;
          incr target_primitive
        end
      done;
      let vertex_map = Array.make !retained_vertices 0
      and vertex_points = Array.make !retained_vertices 0 in
      run_ranges ?grain retained_count (fun first_target last_target ->
        Cancel.check_opt cancel;
        for target = first_target to last_target - 1 do
          let primitive = primitive_map.(target)
          and output = primitive_offsets.(target) in
          let source_first = source.primitive_offsets.(primitive)
          and source_last = source.primitive_offsets.(primitive + 1) in
          for vertex = source_first to source_last - 1 do
            let target_vertex = output + vertex - source_first in
            vertex_map.(target_vertex) <- vertex;
            vertex_points.(target_vertex) <- source.vertex_points.(vertex)
          done
        done);
      let source_point_base = if retained_count = 0 then 0 else source.point_count in
      let extracted_count = sample_offsets.(primitive_count) in
      if source_point_base > max_int - extracted_count then
        fail "Curve Carve breakpoint point count exceeds OCaml array limits";
      let point_map = Array.make (source_point_base + extracted_count) 0 in
      for point = 0 to source_point_base - 1 do point_map.(point) <- point done;
      run_ranges ?grain primitive_count (fun first_primitive last_primitive ->
        Cancel.check_opt cancel;
        for primitive = first_primitive to last_primitive - 1 do
          let samples = sample_counts.(primitive) in
          if samples > 0 then begin
            let source_first = source.primitive_offsets.(primitive)
            and count = source.primitive_offsets.(primitive + 1)
                - source.primitive_offsets.(primitive)
            and output = source_point_base + sample_offsets.(primitive) in
            if all_internal then
              for sample = 0 to samples - 1 do
                let local = first_locals.(primitive) + sample in
                point_map.(output + sample) <-
                  source.vertex_points.(source_first + (local mod count))
              done
            else begin
              point_map.(output) <- source.vertex_points.
                  (source_first + (first_locals.(primitive) mod count));
              if samples = 2 then point_map.(output + 1) <- source.vertex_points.
                  (source_first + (last_locals.(primitive) mod count))
            end
          end
        done);
      let source_positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let positions = Packed.Float3.Private.of_owned_exn
          ~x:(map_array ?cancel ?grain point_map source_positions.x)
          ~y:(map_array ?cancel ?grain point_map source_positions.y)
          ~z:(map_array ?cancel ?grain point_map source_positions.z) in
      let output_topology = Topology.create_owned ~point_count:(Array.length point_map)
          ~vertex_points ~primitive_offsets ~primitive_kinds |> Result.get_ok in
      let attributes = remap_exact_attributes ?cancel ?grain ~point_map ~vertex_map
          ~primitive_map geometry
      and groups = remap_exact_groups ?cancel ?grain ~point_map ~vertex_map ~primitive_map
          geometry in
      let edge_groups = if retained_count = 0 then
          List.map (fun group -> Edge_group.Private.of_owned_bits
            ~topology:output_topology ~edge_count:0 ~name:(Edge_group.name group)
            Bytes.empty) (Geometry.edge_groups geometry)
        else
          let source_index = Topology_index.create ?cancel topology
          and target_index = Topology_index.create ?cancel output_topology
          and identity = Array.init source.point_count Fun.id in
          List.map (fun group -> Edge_group.remap ?cancel ~source_index
            ~target_topology:output_topology ~target_index ~point_map:identity group
            |> Result.get_ok) (Geometry.edge_groups geometry) in
      Geometry.create ~positions ~topology:output_topology ~attributes ~groups
        ~edge_groups ()
    end
  with Curve_error message -> Error message

let carve_breakpoints ?cancel ?grain ?primitives ?(relative_arc_length = true)
    ?(first = 0.) ?(last = 1.) ?first_attribute ?last_attribute
    ?(attribute_mode = Replace) ?(all_internal = false) mode geometry =
  try
    (match grain with Some value when value <= 0 -> fail "grain must be positive"
     | _ -> ());
    if not (finite first && finite last) || first < 0. || last > 1.
        || first >= last then
      fail "Curve Carve requires finite 0 <= first < last <= 1";
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let source = Topology.Private.view topology in
    let primitive_count = Topology.primitive_count topology in
    validate_selection "Curve Carve" primitives primitive_count;
    let parameters = resolve_carve_parameters ?cancel ~allow_equal:false ~first ~last
        ?first_attribute ?last_attribute ~attribute_mode
        ~selected:(selected primitives) geometry in
    let selected_count = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        incr selected_count;
        if Topology.primitive_kind topology primitive = Topology.Polygon then
          fail (Printf.sprintf
            "Curve Carve primitive %d is a polygon, not a polygon curve" primitive)
      end
    done;
    if !selected_count = 0 || not all_internal
        && Option.is_none first_attribute && Option.is_none last_attribute
        && first = 0. && last = 1. && mode <> Outside then Ok geometry
    else begin
      let table = build_breakpoint_table ?cancel ~relative_arc_length
          ~selected:(selected primitives) geometry in
      let first_locals = Array.make primitive_count 0
      and last_locals = Array.make primitive_count (-1) in
      for primitive = 0 to primitive_count - 1 do
        if selected primitives primitive then begin
          let count = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          let edges = count - 1 + if Topology.primitive_kind topology primitive
              = Topology.Closed_polyline then 1 else 0 in
          let a, b = carve_parameter parameters primitive in
          let first_local, last_local = breakpoint_interval table primitive edges a b in
          first_locals.(primitive) <- first_local;
          last_locals.(primitive) <- last_local
        end
      done;
      let iter_pieces primitive emit =
        if not (selected primitives primitive) then emit 0 0 0 false
        else begin
          let count = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          let closed = Topology.primitive_kind topology primitive
              = Topology.Closed_polyline in
          let edges = count - 1 + if closed then 1 else 0
          and a = first_locals.(primitive) and b = last_locals.(primitive) in
          let emit_range start finish wrap =
            let path_edges = if wrap then (edges - start) + finish
              else finish - start in
            if path_edges > 0 then
              if all_internal then begin
                for edge = start to edges - 1 do
                  if wrap || edge < finish then emit 1 edge (edge + 1) false
                done;
                if wrap then for edge = 0 to finish - 1 do
                  emit 1 edge (edge + 1) false
                done
              end else emit 1 start finish wrap in
          let valid_inside = a < b in
          let inside () = if valid_inside then emit_range a b false in
          let outside () =
            if not valid_inside then emit 0 0 0 false
            else if closed then begin
              if a = 0 then emit_range b edges false
              else if b = edges then emit_range 0 a false
              else emit_range b a true
            end else begin
              emit_range 0 a false; emit_range b edges false
            end in
          match mode with
          | Inside -> inside ()
          | Outside -> outside ()
          | Inside_and_outside ->
              if valid_inside then begin inside (); outside () end
              else emit 0 0 0 false
        end in
      let piece_counts = Array.make primitive_count 0 in
      for primitive = 0 to primitive_count - 1 do
        iter_pieces primitive (fun _ _ _ _ ->
          if piece_counts.(primitive) = max_int then
            fail "Curve Carve breakpoint piece count exceeds OCaml array limits";
          piece_counts.(primitive) <- piece_counts.(primitive) + 1)
      done;
      let piece_offsets = Array.make (primitive_count + 1) 0 in
      for primitive = 0 to primitive_count - 1 do
        if piece_offsets.(primitive) > max_int - piece_counts.(primitive) then
          fail "Curve Carve breakpoint piece count exceeds OCaml array limits";
        piece_offsets.(primitive + 1) <- piece_offsets.(primitive)
            + piece_counts.(primitive)
      done;
      let piece_count = piece_offsets.(primitive_count) in
      let piece_source = Array.make piece_count 0
      and piece_kind = Bytes.make piece_count '\000'
      and piece_first = Array.make piece_count 0
      and piece_last = Array.make piece_count 0
      and piece_wrap = Bytes.make piece_count '\000' in
      for primitive = 0 to primitive_count - 1 do
        let at = ref piece_offsets.(primitive) in
        iter_pieces primitive (fun kind first last wrap ->
          piece_source.(!at) <- primitive;
          Bytes.set piece_kind !at (Char.chr kind);
          piece_first.(!at) <- first; piece_last.(!at) <- last;
          if wrap then Bytes.set piece_wrap !at '\001';
          incr at)
      done;
      let output_sizes = Array.make piece_count 0 in
      for piece = 0 to piece_count - 1 do
        let primitive = piece_source.(piece) in
        if Char.code (Bytes.get piece_kind piece) = 0 then
          output_sizes.(piece) <- source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive)
        else begin
          let count = source.primitive_offsets.(primitive + 1)
              - source.primitive_offsets.(primitive) in
          let edges = count - 1 + if Topology.primitive_kind topology primitive
              = Topology.Closed_polyline then 1 else 0 in
          output_sizes.(piece) <- if Bytes.get piece_wrap piece = '\001'
            then edges - piece_first.(piece) + 1 + piece_last.(piece)
            else piece_last.(piece) - piece_first.(piece) + 1
        end
      done;
      let primitive_offsets = Array.make (piece_count + 1) 0 in
      for piece = 0 to piece_count - 1 do
        if primitive_offsets.(piece) > max_int - output_sizes.(piece) then
          fail "Curve Carve breakpoint output exceeds OCaml array limits";
        primitive_offsets.(piece + 1) <- primitive_offsets.(piece)
            + output_sizes.(piece)
      done;
      let output_vertex_count = primitive_offsets.(piece_count) in
      let passthrough = ref false and selected_points = ref 0 in
      for piece = 0 to piece_count - 1 do
        if Char.code (Bytes.get piece_kind piece) = 0 then passthrough := true
        else begin
          if !selected_points > max_int - output_sizes.(piece) then
            fail "Curve Carve breakpoint points exceed OCaml array limits";
          selected_points := !selected_points + output_sizes.(piece)
        end
      done;
      let source_point_base = if !passthrough then source.point_count else 0 in
      if source_point_base > max_int - !selected_points then
        fail "Curve Carve breakpoint points exceed OCaml array limits";
      let point_map = Array.make (source_point_base + !selected_points) 0
      and vertex_map = Array.make output_vertex_count 0
      and vertex_points = Array.make output_vertex_count 0
      and vertex_edge_source = Array.make output_vertex_count (-1) in
      for point = 0 to source_point_base - 1 do point_map.(point) <- point done;
      let selected_point_offsets = Array.make (piece_count + 1) 0 in
      for piece = 0 to piece_count - 1 do
        selected_point_offsets.(piece + 1) <- selected_point_offsets.(piece)
            + if Char.code (Bytes.get piece_kind piece) = 0
              then 0 else output_sizes.(piece)
      done;
      run_ranges ?grain piece_count (fun first_piece last_piece ->
        Cancel.check_opt cancel;
        for piece = first_piece to last_piece - 1 do
          let primitive = piece_source.(piece)
          and output_first = primitive_offsets.(piece) in
          let source_first = source.primitive_offsets.(primitive) in
          let count = source.primitive_offsets.(primitive + 1) - source_first in
          if Char.code (Bytes.get piece_kind piece) = 0 then begin
            for local = 0 to count - 1 do
              let output = output_first + local in
              vertex_map.(output) <- source_first + local;
              vertex_points.(output) <- source.vertex_points.(source_first + local);
              if local < count - 1 || Topology.primitive_kind topology primitive
                  <> Topology.Open_polyline then
                vertex_edge_source.(output) <- source_first + local
            done
          end else begin
            let output_point = source_point_base + selected_point_offsets.(piece) in
            let install output local =
              let source_local = local mod count
              and target_vertex = output_first + output in
              let source_vertex = source_first + source_local in
              point_map.(output_point + output) <- source.vertex_points.(source_vertex);
              vertex_map.(target_vertex) <- source_vertex;
              vertex_points.(target_vertex) <- output_point + output;
              if output + 1 < output_sizes.(piece) then
                vertex_edge_source.(target_vertex) <- source_vertex in
            if Bytes.get piece_wrap piece = '\001' then begin
              let output = ref 0 in
              for local = piece_first.(piece) to
                  count - 1 + if Topology.primitive_kind topology primitive
                    = Topology.Closed_polyline then 1 else 0 do
                install !output local; incr output
              done;
              for local = 1 to piece_last.(piece) do
                install !output local; incr output
              done
            end else
              for output = 0 to output_sizes.(piece) - 1 do
                install output (piece_first.(piece) + output)
              done
          end
        done);
      let primitive_kinds = Array.init piece_count (fun piece ->
        if Char.code (Bytes.get piece_kind piece) = 0
        then Topology.primitive_kind topology piece_source.(piece)
        else Topology.Open_polyline) in
      let output_topology = Topology.create_owned ~point_count:(Array.length point_map)
          ~vertex_points ~primitive_offsets ~primitive_kinds |> Result.get_ok in
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let positions = Packed.Float3.Private.of_owned_exn
          ~x:(map_array ?cancel ?grain point_map positions.x)
          ~y:(map_array ?cancel ?grain point_map positions.y)
          ~z:(map_array ?cancel ?grain point_map positions.z) in
      let attributes = remap_exact_attributes ?cancel ?grain ~point_map ~vertex_map
          ~primitive_map:piece_source geometry
      and groups = remap_exact_groups ?cancel ?grain ~point_map ~vertex_map
          ~primitive_map:piece_source geometry in
      let edge_groups = match Geometry.edge_groups geometry with
        | [] -> []
        | source_groups ->
            let source_index = Topology_index.create ?cancel topology in
            if not !passthrough then begin
              let output_edge_count = output_vertex_count - piece_count in
              List.map (fun source_group ->
                let bits = Bytes.make ((output_edge_count + 7) / 8) '\000' in
                let set edge =
                  let byte = edge lsr 3 and mask = 1 lsl (edge land 7) in
                  Bytes.set bits byte (Char.chr
                    (Char.code (Bytes.get bits byte) lor mask)) in
                for piece = 0 to piece_count - 1 do
                  for output = primitive_offsets.(piece) to
                      primitive_offsets.(piece + 1) - 2 do
                    let source_edge = Topology_index.edge_of_vertex source_index
                        vertex_edge_source.(output) in
                    if source_edge >= 0 && Edge_group.mem source_edge source_group
                    then set (output - piece)
                  done
                done;
                Edge_group.Private.of_owned_bits ~topology:output_topology
                  ~edge_count:output_edge_count ~name:(Edge_group.name source_group)
                  bits) source_groups
            end else begin
              let output_index = Topology_index.create ?cancel output_topology in
              List.map (fun source_group ->
                let builder = Edge_group.Builder.create ~topology:output_topology
                    ~index:output_index ~name:(Edge_group.name source_group) in
                for vertex = 0 to output_vertex_count - 1 do
                  let source_vertex = vertex_edge_source.(vertex) in
                  if source_vertex >= 0 then begin
                    let source_edge = Topology_index.edge_of_vertex source_index
                        source_vertex
                    and target_edge = Topology_index.edge_of_vertex output_index vertex in
                    if source_edge >= 0 && target_edge >= 0
                        && Edge_group.mem source_edge source_group then
                      Edge_group.Builder.set builder target_edge true
                  end
                done;
                Edge_group.Builder.freeze builder) source_groups
            end in
      Geometry.create ~positions ~topology:output_topology ~attributes ~groups
        ~edge_groups ()
    end
  with Curve_error message -> Error message

let extract_points ?cancel ?grain ?primitives ?relative_arc_length ?first ?last
    ?first_attribute ?last_attribute ?attribute_mode
    ?(only_at_breakpoints = false) ?(cut_at_all_internal_breakpoints = false)
    ?divisions ?keep_original
    geometry =
  if only_at_breakpoints then
    extract_breakpoint_points ?cancel ?grain ?primitives ?relative_arc_length
      ?first ?last ?first_attribute ?last_attribute ?attribute_mode ?divisions
      ?keep_original ~all_internal:cut_at_all_internal_breakpoints geometry
  else extract_points_interpolated ?cancel ?grain ?primitives
      ?relative_arc_length ?first ?last ?first_attribute ?last_attribute
      ?attribute_mode ?divisions ?keep_original geometry

let carve ?cancel ?grain ?primitives ?relative_arc_length ?first ?last
    ?first_attribute ?last_attribute ?attribute_mode
    ?(only_at_breakpoints = false) ?(cut_at_all_internal_breakpoints = false)
    ?(divisions = 1) ?(mode = Inside) geometry =
  if divisions <= 0 then Error "Curve Carve cut divisions must be positive"
  else if only_at_breakpoints then
    carve_breakpoints ?cancel ?grain ?primitives ?relative_arc_length ?first ?last
      ?first_attribute ?last_attribute ?attribute_mode
      ~all_internal:cut_at_all_internal_breakpoints mode geometry
  else match mode with
    | Inside when divisions = 1 ->
        carve_inside ?cancel ?grain ?primitives ?relative_arc_length
        ?first ?last ?first_attribute ?last_attribute ?attribute_mode geometry
    | Inside | Outside | Inside_and_outside as mode ->
        carve_cut ?cancel ?grain ?primitives ?relative_arc_length ?first ?last
          ?first_attribute ?last_attribute ?attribute_mode ~divisions mode geometry
