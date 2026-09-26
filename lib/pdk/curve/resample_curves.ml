open Prismel_math

let get_ok = function Ok value -> value | Error message -> invalid_arg message

let interpolated_array ~grain left right weights source =
  Parallel.init_array ~grain (Array.length weights) (fun index ->
    let t = weights.(index) in
    source.(left.(index)) +. ((source.(right.(index)) -. source.(left.(index))) *. t))

let nearest_array ~grain left right weights source =
  Parallel.init_array ~grain (Array.length weights) (fun index ->
    source.((if weights.(index) < 0.5 then left else right).(index)))

let interpolate_attribute ~grain point_left point_right vertex_left vertex_right
    weights attribute =
  let mapping = match Attribute.owner attribute with
    | Attribute.Point -> Some (point_left, point_right)
    | Attribute.Vertex -> Some (vertex_left, vertex_right)
    | Attribute.Primitive | Attribute.Detail -> None in
  match mapping with
  | None -> Ok attribute
  | Some (left, right) ->
      let storage = match Attribute.Private.storage attribute with
        | Attribute.Float values ->
            Attribute.Float (interpolated_array ~grain left right weights values)
        | Attribute.Int values ->
            Attribute.Int (nearest_array ~grain left right weights values)
        | Attribute.Text values ->
            Attribute.Text (nearest_array ~grain left right weights values)
        | Attribute.Float2 values ->
            let view = Packed.Float2.Private.view values in
            Attribute.Float2 (Packed.Float2.of_owned
              ~x:(interpolated_array ~grain left right weights view.x)
              ~y:(interpolated_array ~grain left right weights view.y) |> get_ok)
        | Attribute.Float3 values ->
            let view = Packed.Float3.Private.view values in
            let x = interpolated_array ~grain left right weights view.x
            and y = interpolated_array ~grain left right weights view.y
            and z = interpolated_array ~grain left right weights view.z in
            if String.equal (Attribute.name attribute) "N" then
              Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(Array.length x - 1)
                  (fun index ->
                let length = sqrt ((x.(index) *. x.(index))
                    +. (y.(index) *. y.(index)) +. (z.(index) *. z.(index))) in
                if length > 1e-20 then begin
                  x.(index) <- x.(index) /. length;
                  y.(index) <- y.(index) /. length;
                  z.(index) <- z.(index) /. length
                end);
            Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)
        | Attribute.Float4 values ->
            let view = Packed.Float4.Private.view values in
            Attribute.Float4 (Packed.Float4.of_owned
              ~x:(interpolated_array ~grain left right weights view.x)
              ~y:(interpolated_array ~grain left right weights view.y)
              ~z:(interpolated_array ~grain left right weights view.z)
              ~w:(interpolated_array ~grain left right weights view.w) |> get_ok)
        | Attribute.Int_array values ->
            let mapping = Parallel.init_array ~grain (Array.length weights) (fun index ->
                if weights.(index) < 0.5 then left.(index) else right.(index)) in
            Attribute.Int_array (Ragged_ops.remap_int mapping values)
        | Attribute.Float_array values ->
            let mapping = Parallel.init_array ~grain (Array.length weights) (fun index ->
                if weights.(index) < 0.5 then left.(index) else right.(index)) in
            Attribute.Float_array (Ragged_ops.remap_float mapping values) in
      Attribute.create_owned ~name:(Attribute.name attribute)
        ~owner:(Attribute.owner attribute) storage

let run ?cancel ?(grain = 16_384) ?primitives ?segments
    ?maximum_segment_length ?segment_length_attribute ?segments_attribute
    ?(even_last_segment = true) ?curve_u_attribute ?curve_number_attribute
    ?distance_attribute ?tangent_attribute geometry =
  Error.guard ~operation:"resample_curves" ~code:"invalid_geometry" @@ fun () ->
  if grain <= 0 then invalid_arg "Pdk_curve.Resample_curves.resample_curves: grain must be positive";
  let invalid = ref None in
  (match segments with
   | Some value when value < 1 ->
       invalid := Some "segments must be positive"
   | _ -> ());
  (match maximum_segment_length with
   | Some value when not (Float.is_finite value) || value <= 0. ->
       invalid := Some "maximum segment length must be finite and positive"
   | _ -> ());
  if segments = None && maximum_segment_length = None
      && segment_length_attribute = None && segments_attribute = None then
    invalid := Some ("segments, maximum_segment_length, or a primitive "
      ^ "override attribute is required");
  let generated_names = [curve_u_attribute; curve_number_attribute;
    distance_attribute; tangent_attribute] |> List.filter_map Fun.id in
  List.iter (fun name ->
    if String.trim name = "" then
      invalid := Some "generated attribute names must not be empty"
    else if String.equal name "P" then
      invalid := Some "generated attributes cannot replace canonical P")
    generated_names;
  let sorted_names = List.sort String.compare generated_names in
  let rec duplicate = function
    | left :: (right :: _ as rest) ->
        if String.equal left right then Some left else duplicate rest
    | _ -> None in
  Option.iter (fun name -> invalid := Some (Printf.sprintf
      "generated attribute name %S is used more than once" name))
    (duplicate sorted_names);
  let topology = Geometry.topology geometry
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let primitive_count = Geometry.primitive_count geometry in
  (match primitives with
   | Some group when Group.owner group <> Group.Primitive ->
       invalid := Some "selection group must own primitives"
   | Some group when Group.length group <> primitive_count ->
       invalid := Some "selection group length does not match primitive count"
   | _ -> ());
  let find_primitive_attribute label name storage = match name with
    | None -> None, None
    | Some name when String.trim name = "" ->
        None, Some (label ^ " attribute name must not be empty")
    | Some name ->
        (match Geometry.find_attribute ~owner:Attribute.Primitive name geometry with
         | None -> None, Some (Printf.sprintf
             "primitive %s attribute %S does not exist" label name)
         | Some attribute ->
             match storage (Attribute.Private.storage attribute) with
             | Some values -> Some values, None
             | None -> None, Some (Printf.sprintf
                 "primitive %s attribute %S has incompatible storage" label name)) in
  let segment_length_values, segment_length_error = find_primitive_attribute
      "segment length" segment_length_attribute
      (function Attribute.Float values -> Some values | _ -> None)
  and segments_values, segments_error = find_primitive_attribute
      "segments" segments_attribute
      (function Attribute.Int values -> Some values | _ -> None) in
  if !invalid = None then invalid := (match segment_length_error with
    | Some _ as error -> error | None -> segments_error);
  Option.iter (fun values ->
    let primitive = ref 0 in
    while !invalid = None && !primitive < Array.length values do
      if not (Float.is_finite values.(!primitive)) then invalid := Some (Printf.sprintf
          "primitive segment length attribute contains a non-finite value at primitive %d"
          !primitive);
      incr primitive
    done) segment_length_values;
  let source_offsets = Array.make (primitive_count + 1) 0
  and primitive_kinds = Array.make primitive_count Topology.Open_polyline in
  for primitive = 0 to primitive_count - 1 do
    let first, last = Topology.primitive_vertex_range topology primitive in
    let source_count = last - first
    and kind = Topology.primitive_kind topology primitive in
    primitive_kinds.(primitive) <- kind;
    (match kind with
     | Topology.Polygon when !invalid = None ->
         invalid := Some (Printf.sprintf "primitive %d is a polygon" primitive)
     | _ -> ());
    let cumulative_count = source_count
        + if kind = Topology.Closed_polyline then 1 else 0 in
    if source_offsets.(primitive) > Sys.max_array_length - cumulative_count then
      invalid := Some "input curve cardinality exceeds OCaml array limits"
    else source_offsets.(primitive + 1) <-
        source_offsets.(primitive) + cumulative_count
  done;
  match !invalid with
  | Some message -> Error ("Pdk_curve.Resample_curves.resample_curves: " ^ message)
  | None ->
      let cumulative = Array.make source_offsets.(primitive_count) 0.
      and totals = Array.make primitive_count 0.
      and failures = Bytes.make primitive_count '\000' in
      let average_vertices = max 1
          (Geometry.vertex_count geometry / max 1 primitive_count) in
      if primitive_count > 0 then Parallel.for_
          ~chunk_size:(max 1 (grain / average_vertices)) ~start:0
          ~finish:(primitive_count - 1) (fun primitive ->
        if primitive land 255 = 0 then Cancel.check_opt cancel;
        let first, last = Topology.primitive_vertex_range topology primitive in
        let source_count = last - first
        and closed = primitive_kinds.(primitive) = Topology.Closed_polyline
        and base = source_offsets.(primitive) in
        let edge_count = source_count - 1 + if closed then 1 else 0 in
        for edge = 0 to edge_count - 1 do
          let left_vertex = first + (edge mod source_count)
          and right_vertex = first + ((edge + 1) mod source_count) in
          let left_point = Topology.point_of_vertex topology left_vertex
          and right_point = Topology.point_of_vertex topology right_vertex in
          let dx = positions.x.(right_point) -. positions.x.(left_point)
          and dy = positions.y.(right_point) -. positions.y.(left_point)
          and dz = positions.z.(right_point) -. positions.z.(left_point) in
          let direct_length = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
          let edge_length = if Float.is_finite direct_length then direct_length
            else
              let ax = abs_float dx and ay = abs_float dy and az = abs_float dz in
              let scale = if ax >= ay then if ax >= az then ax else az
                else if ay >= az then ay else az in
              let sx = if scale = 0. then 0. else dx /. scale
              and sy = if scale = 0. then 0. else dy /. scale
              and sz = if scale = 0. then 0. else dz /. scale in
              scale *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
          let next = cumulative.(base + edge) +. edge_length in
          if not (Float.is_finite edge_length && Float.is_finite next) then
            Bytes.set failures primitive '\001'
          else cumulative.(base + edge + 1) <- next
        done;
        let total = cumulative.(base + edge_count) in
        totals.(primitive) <- total;
        if total <= 1e-20 || not (Float.is_finite total) then
          Bytes.set failures primitive '\002');
      let failed = ref 0 in
      while !failed < primitive_count && Bytes.get failures !failed = '\000' do
        incr failed
      done;
      if !failed < primitive_count then
        Error (Printf.sprintf
          "Pdk_curve.Resample_curves.resample_curves: primitive %d has zero or non-finite length"
          !failed)
      else begin
        let output_edges = Array.make primitive_count 0
        and uniform_spacing = Bytes.make primitive_count '\000'
        and preserve_original = Bytes.make primitive_count '\000'
        and effective_maximum = Array.make primitive_count 0.
        and primitive_offsets = Array.make (primitive_count + 1) 0 in
        let cardinality_error = ref None in
        for primitive = 0 to primitive_count - 1 do
          let closed = primitive_kinds.(primitive) = Topology.Closed_polyline in
          let minimum = if closed then 3 else 1 in
          let selected = match primitives with
            | None -> true | Some group -> Group.mem primitive group in
          let primitive_segments = if not selected then None else
              match segments_values with
              | Some values -> if values.(primitive) <= 0 then None
                  else Some values.(primitive)
              | None -> segments in
          let primitive_maximum = if not selected then None else
              match segment_length_values with
              | Some values -> if values.(primitive) <= 0. then None
                  else Some values.(primitive)
              | None -> maximum_segment_length in
          let preserve = not selected
              || (primitive_segments = None && primitive_maximum = None) in
          if preserve then Bytes.set preserve_original primitive '\001';
          Option.iter (fun value -> effective_maximum.(primitive) <- value)
            primitive_maximum;
          (match primitive_segments with
           | Some count when closed && count < 3 ->
               cardinality_error := Some (Printf.sprintf
                 "closed primitive %d requires at least three segments" primitive)
           | _ -> ());
          let length_edges = match primitive_maximum with
            | None -> None
            | Some maximum ->
                let ratio = totals.(primitive) /. maximum in
                if not (Float.is_finite ratio)
                    || ratio >= float_of_int Sys.max_array_length then begin
                  cardinality_error := Some (Printf.sprintf
                    "primitive %d length-driven cardinality exceeds OCaml array limits"
                    primitive);
                  Some Sys.max_array_length
                end else Some (max minimum (int_of_float (ceil ratio))) in
          let source_first, source_last =
            Topology.primitive_vertex_range topology primitive in
          let source_edges = source_last - source_first - 1
              + if closed then 1 else 0 in
          let edges = if preserve then source_edges else
              match primitive_segments, length_edges with
            | Some count, Some by_length -> max minimum (min count by_length)
            | Some count, None -> max minimum count
            | None, Some count -> count
            | None, None -> assert false in
          output_edges.(primitive) <- edges;
          let capped_by_segments = match primitive_segments, length_edges with
            | Some count, Some by_length -> count < by_length
            | _ -> false in
          if preserve then Bytes.set uniform_spacing primitive '\002'
          else if primitive_maximum = None || even_last_segment
              || capped_by_segments || edges = minimum then
            Bytes.set uniform_spacing primitive '\001';
          let samples = edges + if closed then 0 else 1 in
          if samples < edges
              || primitive_offsets.(primitive) > Sys.max_array_length - samples then
            cardinality_error := Some "output cardinality exceeds OCaml array limits"
          else primitive_offsets.(primitive + 1) <-
              primitive_offsets.(primitive) + samples
        done;
        match !cardinality_error with
        | Some message -> Error ("Pdk_curve.Resample_curves.resample_curves: " ^ message)
        | None ->
          let output_count = primitive_offsets.(primitive_count) in
          let px = Array.make output_count 0. and py = Array.make output_count 0.
          and pz = Array.make output_count 0.
          and point_left = Array.make output_count 0
          and point_right = Array.make output_count 0
          and vertex_left = Array.make output_count 0
          and vertex_right = Array.make output_count 0
          and weights = Array.make output_count 0.
          and curve_u = Option.map (fun _ -> Array.make output_count 0.)
              curve_u_attribute
          and curve_number = Option.map (fun _ -> Array.make output_count 0)
              curve_number_attribute in
          let chunk_count = if output_count = 0 then 0
            else (output_count + grain - 1) / grain in
          let output_failures = Bytes.make chunk_count '\000' in
          let find_primitive index =
            let low = ref 0 and high = ref primitive_count in
            while !low + 1 < !high do
              let middle = (!low + !high) / 2 in
              if primitive_offsets.(middle) <= index then low := middle
              else high := middle
            done;
            !low in
          if chunk_count > 0 then Parallel.for_ ~chunk_size:1 ~start:0
              ~finish:(chunk_count - 1) (fun chunk ->
            Cancel.check_opt cancel;
            let index = ref (chunk * grain) in
            let finish = min output_count (!index + grain) in
            let primitive = ref (find_primitive !index) in
            while !index < finish do
              let output_first = primitive_offsets.(!primitive)
              and output_last = min finish primitive_offsets.(!primitive + 1) in
              let source_first, source_last =
                Topology.primitive_vertex_range topology !primitive in
              let source_count = source_last - source_first
              and source_base = source_offsets.(!primitive)
              and closed = primitive_kinds.(!primitive) = Topology.Closed_polyline
              and edges = output_edges.(!primitive)
              and total = totals.(!primitive) in
              let source_edge_count = source_count - 1 + if closed then 1 else 0
              and spacing = Bytes.get uniform_spacing !primitive
              and maximum = effective_maximum.(!primitive) in
              let preserve = spacing = '\002' and uniform = spacing <> '\000' in
              let local = !index - output_first in
              let first_distance =
                if preserve then cumulative.(source_base + local)
                else if not closed && local = edges then total
                else if uniform then
                  total *. float_of_int local /. float_of_int edges
                else float_of_int local *. maximum in
              let low = ref 1 and high = ref source_edge_count in
              while !low < !high do
                let middle = (!low + !high) / 2 in
                if cumulative.(source_base + middle) < first_distance then
                  low := middle + 1 else high := middle
              done;
              let edge = ref (!low - 1) in
              while !index < output_last do
                let local = !index - output_first in
                let distance =
                  if preserve then cumulative.(source_base + local)
                  else if not closed && local = edges then total
                  else if uniform then
                    total *. float_of_int local /. float_of_int edges
                  else float_of_int local *. maximum in
                while !edge < source_edge_count - 1
                    && cumulative.(source_base + !edge + 1) < distance do
                  incr edge
                done;
                let edge_start = cumulative.(source_base + !edge)
                and edge_finish = cumulative.(source_base + !edge + 1) in
                let edge_length = edge_finish -. edge_start in
                let sampled_t = if edge_length <= 1e-20 then 0.
                  else (distance -. edge_start) /. edge_length in
                let sampled_left = source_first + (!edge mod source_count)
                and sampled_right = source_first
                    + ((!edge + 1) mod source_count) in
                let left_vertex = if preserve then source_first + local
                  else sampled_left
                and right_vertex = if preserve then source_first + local
                  else sampled_right
                and t = if preserve then 0. else sampled_t in
                let left_point = Topology.point_of_vertex topology left_vertex
                and right_point = Topology.point_of_vertex topology right_vertex in
                point_left.(!index) <- left_point;
                point_right.(!index) <- right_point;
                vertex_left.(!index) <- left_vertex;
                vertex_right.(!index) <- right_vertex;
                weights.(!index) <- t;
                let x = positions.x.(left_point)
                    +. ((positions.x.(right_point) -. positions.x.(left_point)) *. t)
                and y = positions.y.(left_point)
                    +. ((positions.y.(right_point) -. positions.y.(left_point)) *. t)
                and z = positions.z.(left_point)
                    +. ((positions.z.(right_point) -. positions.z.(left_point)) *. t) in
                if Float.is_finite x && Float.is_finite y && Float.is_finite z then begin
                  px.(!index) <- x; py.(!index) <- y; pz.(!index) <- z
                end else Bytes.set output_failures chunk '\001';
                (match curve_u with
                 | None -> ()
                 | Some values -> values.(!index) <-
                     if preserve then float_of_int local
                         /. float_of_int source_edge_count
                     else (float_of_int !edge +. t)
                         /. float_of_int source_edge_count);
                (match curve_number with
                 | None -> ()
                 | Some values -> values.(!index) <- !primitive);
                incr index
              done;
              incr primitive
            done);
          let failed_chunk = ref 0 in
          while !failed_chunk < chunk_count
              && Bytes.get output_failures !failed_chunk = '\000' do
            incr failed_chunk
          done;
          if !failed_chunk < chunk_count then Error
              "Pdk_curve.Resample_curves.resample_curves: generated a non-finite sample"
          else begin
            let distance_values = Option.map (fun _ -> Array.make output_count 0.)
                distance_attribute
            and tangent_x = Option.map (fun _ -> Array.make output_count 0.)
                tangent_attribute
            and tangent_y = Option.map (fun _ -> Array.make output_count 0.)
                tangent_attribute
            and tangent_z = Option.map (fun _ -> Array.make output_count 0.)
                tangent_attribute
            and diagnostic_failures = Bytes.make chunk_count '\000' in
            if chunk_count > 0
                && (distance_attribute <> None || tangent_attribute <> None) then
              Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(chunk_count - 1)
                (fun chunk ->
              Cancel.check_opt cancel;
              let first_index = chunk * grain in
              let last_index = min output_count (first_index + grain) in
              let primitive = ref (find_primitive first_index) in
              for index = first_index to last_index - 1 do
                while index >= primitive_offsets.(!primitive + 1) do
                  incr primitive
                done;
                let first = primitive_offsets.(!primitive)
                and last = primitive_offsets.(!primitive + 1) in
                let local = index - first and count = last - first
                and closed = primitive_kinds.(!primitive)
                    = Topology.Closed_polyline in
                let previous = if local = 0 then
                    if closed then last - 1 else index
                  else index - 1
                and next = if local = count - 1 then
                    if closed then first else index
                  else index + 1 in
                (match distance_values with
                 | None -> ()
                 | Some values ->
                  let left = if previous = index then 0. else
                      let dx = px.(index) -. px.(previous)
                      and dy = py.(index) -. py.(previous)
                      and dz = pz.(index) -. pz.(previous) in
                      let direct = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
                      if Float.is_finite direct then direct else
                        let ax = abs_float dx and ay = abs_float dy
                        and az = abs_float dz in
                        let scale = if ax >= ay then if ax >= az then ax else az
                          else if ay >= az then ay else az in
                        let sx = if scale = 0. then 0. else dx /. scale
                        and sy = if scale = 0. then 0. else dy /. scale
                        and sz = if scale = 0. then 0. else dz /. scale in
                        scale *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz))
                  and right = if next = index then 0. else
                      let dx = px.(next) -. px.(index)
                      and dy = py.(next) -. py.(index)
                      and dz = pz.(next) -. pz.(index) in
                      let direct = sqrt ((dx *. dx) +. (dy *. dy) +. (dz *. dz)) in
                      if Float.is_finite direct then direct else
                        let ax = abs_float dx and ay = abs_float dy
                        and az = abs_float dz in
                        let scale = if ax >= ay then if ax >= az then ax else az
                          else if ay >= az then ay else az in
                        let sx = if scale = 0. then 0. else dx /. scale
                        and sy = if scale = 0. then 0. else dy /. scale
                        and sz = if scale = 0. then 0. else dz /. scale in
                        scale *. sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                  let value = 0.5 *. (left +. right) in
                  if Float.is_finite value then values.(index) <- value
                  else Bytes.set diagnostic_failures chunk '\001');
                match tangent_x, tangent_y, tangent_z with
                | Some tx, Some ty, Some tz ->
                    let dx = px.(next) -. px.(previous)
                    and dy = py.(next) -. py.(previous)
                    and dz = pz.(next) -. pz.(previous) in
                    let ax = abs_float dx and ay = abs_float dy
                    and az = abs_float dz in
                    let scale = if ax >= ay then if ax >= az then ax else az
                      else if ay >= az then ay else az in
                    let sx = if scale = 0. then 0. else dx /. scale
                    and sy = if scale = 0. then 0. else dy /. scale
                    and sz = if scale = 0. then 0. else dz /. scale in
                    let length = sqrt ((sx *. sx) +. (sy *. sy) +. (sz *. sz)) in
                    if scale = 0. || not (Float.is_finite length) then
                      Bytes.set diagnostic_failures chunk '\002'
                    else begin
                      tx.(index) <- sx /. length;
                      ty.(index) <- sy /. length;
                      tz.(index) <- sz /. length
                    end
                | _ -> ()
              done);
            let failed_diagnostic = ref 0 in
            while !failed_diagnostic < chunk_count
                && Bytes.get diagnostic_failures !failed_diagnostic = '\000' do
              incr failed_diagnostic
            done;
            if !failed_diagnostic < chunk_count then Error
                "Pdk_curve.Resample_curves.resample_curves: generated a non-finite or undefined diagnostic"
            else
            let vertex_points = Parallel.init_array ~grain output_count Fun.id in
            Result.bind (Topology.create_owned ~point_count:output_count
                ~vertex_points ~primitive_offsets ~primitive_kinds) (fun topology ->
              let positions = Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz in
              let rec attributes result = function
                | [] -> Ok (List.rev result)
                | attribute :: rest -> Result.bind
                    (interpolate_attribute ~grain point_left point_right vertex_left
                      vertex_right weights attribute)
                    (fun attribute -> attributes (attribute :: result) rest) in
              Result.bind (attributes [] (Geometry.attributes geometry)) (fun attributes ->
                let generated = ref [] in
                let add name storage = match name with
                  | None -> ()
                  | Some name -> generated := (Attribute.create_owned
                      ~owner:Attribute.Point ~name storage |> get_ok) :: !generated in
                Option.iter (fun values -> add curve_u_attribute
                    (Attribute.Float values)) curve_u;
                Option.iter (fun values -> add curve_number_attribute
                    (Attribute.Int values)) curve_number;
                Option.iter (fun values -> add distance_attribute
                    (Attribute.Float values)) distance_values;
                (match tangent_x, tangent_y, tangent_z with
                 | Some x, Some y, Some z -> add tangent_attribute
                     (Attribute.Float3
                       (Packed.Float3.Private.of_owned_exn ~x ~y ~z))
                 | _ -> ());
                let generated = List.rev !generated in
                let attributes = List.filter (fun attribute ->
                    Attribute.owner attribute <> Attribute.Point
                    || not (List.exists (fun generated_attribute ->
                        String.equal (Attribute.name attribute)
                          (Attribute.name generated_attribute)) generated))
                    attributes @ generated in
                let groups = List.map (fun group ->
                  match Group.owner group with
                  | Group.Primitive -> group
                  | Group.Point ->
                      let source index =
                        (if weights.(index) < 0.5 then point_left else point_right).(index) in
                      let target = Group.init ~grain ~owner:Group.Point
                          ~name:(Group.name group) output_count
                          (fun index -> Group.mem (source index) group) in
                      if not (Group.is_ordered group) then target
                      else
                        let source_of_target = Parallel.init_array ~grain
                            output_count source in
                        Group.Private.remap_order ~source:group ~source_of_target target
                  | Group.Vertex ->
                      let source index =
                        (if weights.(index) < 0.5 then vertex_left else vertex_right).(index) in
                      let target = Group.init ~grain ~owner:Group.Vertex
                          ~name:(Group.name group) output_count
                          (fun index -> Group.mem (source index) group) in
                      if not (Group.is_ordered group) then target
                      else
                        let source_of_target = Parallel.init_array ~grain
                            output_count source in
                        Group.Private.remap_order ~source:group ~source_of_target target)
                    (Geometry.groups geometry) in
                let edge_groups = match Geometry.edge_groups geometry with
                  | [] -> []
                  | source_groups ->
                      let source_index = Topology_index.create ?cancel
                          (Geometry.topology geometry)
                      and target_index = Topology_index.create ?cancel topology in
                      let target_view = Topology_index.Private.view target_index in
                      List.map (fun source_group ->
                        let builder = Edge_group.Builder.create ~topology
                            ~index:target_index ~name:(Edge_group.name source_group) in
                        for primitive = 0 to primitive_count - 1 do
                          let source_first, source_last =
                            Topology.primitive_vertex_range
                              (Geometry.topology geometry) primitive in
                          let source_count = source_last - source_first in
                          let closed = Topology.primitive_kind
                              (Geometry.topology geometry) primitive
                              = Topology.Closed_polyline in
                          let source_edges = source_count - 1
                              + if closed then 1 else 0 in
                          let output_first, output_last =
                            Topology.primitive_vertex_range topology primitive in
                          let output_edges = output_last - output_first - 1
                              + if closed then 1 else 0 in
                          let selected_local local =
                            let corner = source_first + (local mod source_count) in
                            let edge = Topology_index.edge_of_vertex source_index corner in
                            edge >= 0 && Edge_group.mem edge source_group in
                          for local = 0 to output_edges - 1 do
                            let output_corner = output_first + local
                            and next_corner = output_first
                                + ((local + 1) mod (output_last - output_first)) in
                            let start_point = Topology.point_of_vertex topology
                                output_corner
                            and end_point = Topology.point_of_vertex topology next_corner in
                            let start_local = vertex_left.(start_point) - source_first
                                + if weights.(start_point) >= 1. -. 1e-12 then 1 else 0
                            and end_local = vertex_left.(end_point) - source_first in
                            let all = ref true in
                            let check first last =
                              for edge = first to last do
                                if edge >= 0 && edge < source_edges
                                   && not (selected_local edge) then all := false
                              done in
                            if closed && local = output_edges - 1 then begin
                              check start_local (source_edges - 1);
                              if weights.(end_point) > 1e-12 then check 0 end_local
                            end else begin
                              let last = if weights.(end_point) <= 1e-12
                                then end_local - 1 else end_local in
                              check start_local last
                            end;
                            if !all then begin
                              let target_edge = target_view.edge_of_vertex.(output_corner) in
                              if target_edge >= 0 then
                                Edge_group.Builder.set builder target_edge true
                            end
                          done
                        done;
                        Edge_group.Builder.freeze builder) source_groups in
                Geometry.create ~positions ~topology ~attributes ~groups
                  ~edge_groups ()))
          end
      end
