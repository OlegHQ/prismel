open Prismel

exception Invalid of string

let fail message = raise (Invalid message)
let finite = Float.is_finite

let checked_add label left right =
  if right < 0 || left > Sys.max_array_length - right then
    fail (label ^ " exceeds OCaml array limits");
  left + right

let gcd left right =
  let a = ref left and b = ref right in
  while !b <> 0 do let next = !a mod !b in a := !b; b := next done;
  !a

let[@inline always] normalized_offset value count =
  let value = value mod count in
  if value < 0 then value + count else value

let[@inline always] interpolate left right weight =
  let delta = right -. left in
  if finite delta then left +. (delta *. weight)
  else (left *. (1. -. weight)) +. (right *. weight)

let robust_length dx dy dz =
  let scale = Float.max (abs_float dx) (Float.max (abs_float dy) (abs_float dz)) in
  if scale = 0. then 0.
  else if not (finite scale) then infinity
  else
    let x = dx /. scale and y = dy /. scale and z = dz /. scale in
    scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z))

let normalize x y z =
  let scale = Float.max (abs_float x) (Float.max (abs_float y) (abs_float z)) in
  if scale = 0. || not (finite scale) then None
  else
    let x = x /. scale and y = y /. scale and z = z /. scale in
    let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
    if length = 0. || not (finite length) then None
    else Some (x /. length, y /. length, z /. length)

let find_point_attribute geometry label name storage = match name with
  | None -> None
  | Some name when String.trim name = "" ->
      fail (label ^ " attribute name must not be empty")
  | Some name ->
      match Geometry.find_attribute ~owner:Attribute.Point name geometry with
      | None -> fail (Printf.sprintf "point %s attribute %S does not exist" label name)
      | Some attribute ->
          match storage (Attribute.Private.storage attribute) with
          | Some values -> Some values
          | None -> fail (Printf.sprintf
              "point %s attribute %S has incompatible storage" label name)

let find_vertex_attribute geometry label name storage = match name with
  | None -> None
  | Some name when String.trim name = "" ->
      fail (label ^ " attribute name must not be empty")
  | Some name ->
      match Geometry.find_attribute ~owner:Attribute.Vertex name geometry with
      | None -> fail (Printf.sprintf
          "vertex %s attribute %S does not exist" label name)
      | Some attribute ->
          match storage (Attribute.Private.storage attribute) with
          | Some values -> Some values
          | None -> fail (Printf.sprintf
              "vertex %s attribute %S has incompatible storage" label name)

let validate_selection primitives primitive_count = match primitives with
  | None -> ()
  | Some group ->
      if Group.owner group <> Group.Primitive then
        fail "primitive selection must own primitives";
      if Group.length group <> primitive_count then
        fail "primitive selection length does not match primitive count"

let selected primitives primitive = match primitives with
  | None -> true
  | Some group -> Group.mem primitive group

type curve = {
  primitive : int;
  closed : bool;
  cap_ends : bool;
  ring_first : int;
  ring_count : int;
  transition_first : int;
  transition_count : int;
}

let run ?cancel ~grain ~primitives ~sides ~divisions_attribute ~segments
    ~segments_attribute ~segment_scales ~segment_scales_attribute
    ~prevent_joint_buckling ~maximum_joint_scale
    ~maximum_joint_scale_attribute ~smooth_point ~smooth_attribute ~max_valence
    ~scale_attribute ~seam_offset
    ~seam_attribute ~segment_seam_attribute ~v_attribute ~generate_uv
    ~u_range ~v_range ~uv_range_attribute ~up_attribute ~caps ~cap_group
    ~radius geometry =
  try
    if grain <= 0 then fail "grain must be positive";
    if sides < 3 then fail "sides must be at least three";
    if sides > 4_096 then fail "sides must not exceed 4096";
    if segments < 1 then fail "segments must be positive";
    if segments > 1_048_576 then fail "segments must not exceed 1048576";
    if not (finite radius) || radius <= 0. then
      fail "radius must be finite and positive";
    let validate_range label (first, last) =
      if not (finite first && finite last) then
        fail (label ^ " range must be finite") in
    Option.iter (fun ((first, last) as range) ->
      validate_range "segment scale" range;
      if first < 0. || last > 1. || first > last then
        fail "segment scales require 0 <= first <= last <= 1") segment_scales;
    if not (finite maximum_joint_scale) || maximum_joint_scale < 1. then
      fail "maximum joint scale must be finite and at least one";
    if Option.is_some maximum_joint_scale_attribute
        && not prevent_joint_buckling then
      fail "maximum joint scale attribute requires joint buckling prevention";
    Option.iter (fun value -> if value < 1 then
      fail "max valence must be positive") max_valence;
    if generate_uv then begin
      Option.iter (validate_range "U texture") u_range;
      Option.iter (validate_range "V texture") v_range
    end;
    Option.iter (fun name -> if String.trim name = "" then
      fail "cap group name must not be empty") cap_group;
    if Option.is_some cap_group && not caps then fail "cap_group requires caps=true";
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let source = Topology.Private.view topology
    and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let point_count = source.point_count
    and vertex_count = Array.length source.vertex_points
    and primitive_count = Bytes.length source.primitive_kinds in
    validate_selection primitives primitive_count;
    let selected_count = ref 0
    and selected_reference = Bytes.make point_count '\000' in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        incr selected_count;
        if Topology.primitive_kind topology primitive = Topology.Polygon then
          fail (Printf.sprintf "primitive %d is a polygon" primitive);
        for vertex = source.primitive_offsets.(primitive)
            to source.primitive_offsets.(primitive + 1) - 1 do
          Bytes.set selected_reference source.vertex_points.(vertex) '\001'
        done
      end
    done;
    if !selected_count = 0 then Ok geometry else begin
    let scale_values = find_point_attribute geometry "scale" scale_attribute
        (function Attribute.Float values -> Some values | _ -> None)
    and seam_values = find_point_attribute geometry "seam" seam_attribute
        (function Attribute.Int values -> Some values | _ -> None)
    and v_values = if generate_uv then
        find_point_attribute geometry "V texture" v_attribute
          (function Attribute.Float values -> Some values | _ -> None)
      else None
    and up_values = find_point_attribute geometry "joint up" up_attribute
        (function Attribute.Float3 values ->
          Some (Packed.Float3.Private.view values) | _ -> None)
    and division_values = find_point_attribute geometry "division"
        divisions_attribute
        (function Attribute.Int values -> Some values | _ -> None)
    and segment_values = find_point_attribute geometry "segment"
        segments_attribute
        (function Attribute.Int values -> Some values | _ -> None)
    and segment_scale_values = find_vertex_attribute geometry "segment scale"
        segment_scales_attribute
        (function Attribute.Float2 values ->
          Some (Packed.Float2.Private.view values) | _ -> None)
    and segment_seam_values = find_vertex_attribute geometry "segment seam"
        segment_seam_attribute
        (function Attribute.Int values -> Some values | _ -> None)
    and uv_range_values = if generate_uv then
        find_vertex_attribute geometry "UV range" uv_range_attribute
          (function Attribute.Float4 values ->
            Some (Packed.Float4.Private.view values) | _ -> None)
      else None
    and maximum_joint_scale_values = if prevent_joint_buckling then
        find_point_attribute geometry "maximum joint scale"
          maximum_joint_scale_attribute
          (function Attribute.Float values -> Some values | _ -> None)
      else None
    and smooth_values = find_point_attribute geometry "smooth" smooth_attribute
        (function Attribute.Float values -> Some values | _ -> None) in
    Option.iter (fun values -> Array.iteri (fun point value ->
      if Bytes.get selected_reference point <> '\000'
          && (not (finite value) || value < 0.) then fail (Printf.sprintf
        "point scale attribute contains a non-finite or negative value at point %d"
        point)) values) scale_values;
    Option.iter (fun values -> Array.iteri (fun point value ->
      if Bytes.get selected_reference point <> '\000' && not (finite value) then
        fail (Printf.sprintf
          "point V texture attribute contains a non-finite value at point %d" point))
      values) v_values;
    Option.iter (fun (values : Packed.Float3.Private.view) ->
      for point = 0 to Array.length values.x - 1 do
        if Bytes.get selected_reference point <> '\000'
            && not (finite values.x.(point) && finite values.y.(point)
            && finite values.z.(point)) then fail (Printf.sprintf
          "point joint up attribute contains a non-finite value at point %d" point)
      done) up_values;
    Option.iter (fun values -> Array.iteri (fun point value ->
      if Bytes.get selected_reference point <> '\000'
          && (value < 3 || value > 4_096) then fail (Printf.sprintf
        "point division attribute must be in [3, 4096] at point %d" point)) values)
      division_values;
    Option.iter (fun values -> Array.iteri (fun point value ->
      if Bytes.get selected_reference point <> '\000'
          && (value < 1 || value > 1_048_576) then fail (Printf.sprintf
        "point segment attribute must be in [1, 1048576] at point %d" point)) values)
      segment_values;
    Option.iter (fun values -> Array.iteri (fun point value ->
      if Bytes.get selected_reference point <> '\000'
          && (not (finite value) || value < 1.) then fail (Printf.sprintf
        "point maximum joint scale attribute must be finite and at least one at point %d"
        point)) values) maximum_joint_scale_values;
    Option.iter (fun values -> Array.iteri (fun point value ->
      if Bytes.get selected_reference point <> '\000' && not (finite value) then
        fail (Printf.sprintf
          "point smooth attribute contains a non-finite value at point %d" point))
      values) smooth_values;
    let point_smooth = Bytes.make point_count
        (if smooth_point then '\001' else '\000') in
    Option.iter (fun values ->
      for point = 0 to point_count - 1 do
        if Bytes.get selected_reference point <> '\000' && values.(point) < 0.5
        then Bytes.set point_smooth point '\000'
      done) smooth_values;
    (match max_valence with
     | None -> ()
     | Some maximum ->
         let index = Topology_index.create ?cancel topology in
         let selected_edges = Bytes.make (Topology_index.edge_count index) '\000' in
         let view = Topology_index.Private.view index in
         for primitive = 0 to primitive_count - 1 do
           if selected primitives primitive then
             for vertex = source.primitive_offsets.(primitive)
                 to source.primitive_offsets.(primitive + 1) - 1 do
               let edge = view.edge_of_vertex.(vertex) in
               if edge >= 0 then Bytes.set selected_edges edge '\001'
             done
         done;
         for point = 0 to point_count - 1 do
           if Bytes.get selected_reference point <> '\000' then begin
             let valence = ref 0 in
             for at = view.point_edge_offsets.(point)
                 to view.point_edge_offsets.(point + 1) - 1 do
               if Bytes.get selected_edges view.point_edges.(at) <> '\000' then
                 incr valence
             done;
             if !valence > maximum then Bytes.set point_smooth point '\000'
           end
         done);
    let has_segment_scales = Option.is_some segment_scale_values
        || Option.is_some segment_scales in
    let constant_scale_first, constant_scale_last =
      Option.value ~default:(0., 1.) segment_scales in
    let segment_scale_first vertex = match segment_scale_values with
      | Some values -> values.x.(vertex) | None -> constant_scale_first in
    let segment_scale_last vertex = match segment_scale_values with
      | Some values -> values.y.(vertex) | None -> constant_scale_last in
    let segment_parameter vertex subdivisions sample =
      if sample <= 0 then 0.
      else if sample >= subdivisions then 1.
      else if not has_segment_scales then
        float_of_int sample /. float_of_int subdivisions
      else
        let first = segment_scale_first vertex
        and last = segment_scale_last vertex in
        if subdivisions = 2 then (first +. last) *. 0.5
        else first +. ((last -. first) *. float_of_int (sample - 1)
          /. float_of_int (subdivisions - 2)) in
    let constant_u0, constant_u1 = Option.value ~default:(0., 1.) u_range
    and constant_v0, constant_v1 = Option.value ~default:(0., 1.) v_range in
    let uv_u0 vertex = match uv_range_values with
      | Some values -> values.x.(vertex) | None -> constant_u0 in
    let uv_u1 vertex = match uv_range_values with
      | Some values -> values.y.(vertex) | None -> constant_u1 in
    let uv_v0 vertex = match uv_range_values with
      | Some values -> values.z.(vertex) | None -> constant_v0 in
    let uv_v1 vertex = match uv_range_values with
      | Some values -> values.w.(vertex) | None -> constant_v1 in
    let need_transition_parameters = generate_uv && Option.is_none v_values
        && (Option.is_some v_range || Option.is_some uv_range_values) in
    let custom_u_ranges = Option.is_some u_range
        || Option.is_some uv_range_values in
    let referenced = Bytes.make point_count '\000'
    and retained_reference = Bytes.make point_count '\000' in
    for primitive = 0 to primitive_count - 1 do
      let first = source.primitive_offsets.(primitive)
      and last = source.primitive_offsets.(primitive + 1) in
      for vertex = first to last - 1 do
        let point = source.vertex_points.(vertex) in
        Bytes.set referenced point '\001';
        if not (selected primitives primitive) then
          Bytes.set retained_reference point '\001'
      done
    done;
    let source_point_target = Array.make point_count (-1)
    and kept_source_points = ref 0 in
    for point = 0 to point_count - 1 do
      if Bytes.get referenced point = '\000'
          || Bytes.get retained_reference point <> '\000' then begin
        source_point_target.(point) <- !kept_source_points;
        incr kept_source_points
      end
    done;
    let edge_segments = Array.make vertex_count 0
    and curve_of_primitive = Array.make primitive_count (-1)
    and primitive_breaks = Array.make primitive_count 0
    and curve_ring_offsets = Array.make (!selected_count + 1) 0
    and curve_transition_offsets = Array.make (!selected_count + 1) 0 in
    let curve_index = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        if primitive land 255 = 0 then Cancel.check_opt cancel;
        let first = source.primitive_offsets.(primitive)
        and last = source.primitive_offsets.(primitive + 1) in
        let count = last - first
        and closed = Topology.primitive_kind topology primitive
            = Topology.Closed_polyline in
        let edges = count - 1 + if closed then 1 else 0 in
        if edges < 1 then fail (Printf.sprintf
          "primitive %d has fewer than two curve vertices" primitive);
        let breaks = ref 0 in
        if closed then begin
          for local = 0 to count - 1 do
            let point = source.vertex_points.(first + local) in
            if Bytes.get point_smooth point = '\000' then incr breaks
          done;
        end else
          for local = 1 to count - 2 do
            let point = source.vertex_points.(first + local) in
            if Bytes.get point_smooth point = '\000' then incr breaks
          done;
        primitive_breaks.(primitive) <- !breaks;
        let ring_count = ref ((if closed then 0 else 1) + !breaks) in
        for local = 0 to edges - 1 do
          let left_vertex = first + (local mod count)
          and right_vertex = first + ((local + 1) mod count) in
          let left_point = source.vertex_points.(left_vertex)
          and right_point = source.vertex_points.(right_vertex) in
          if has_segment_scales then begin
            let source_length = robust_length
                (positions.x.(right_point) -. positions.x.(left_point))
                (positions.y.(right_point) -. positions.y.(left_point))
                (positions.z.(right_point) -. positions.z.(left_point)) in
            if not (finite source_length) || source_length <= 1e-20 then
              fail (Printf.sprintf
                "primitive %d has a zero-length or non-finite source edge"
                primitive)
          end;
          let count = match segment_values with
            | None -> segments
            | Some values ->
                let left = values.(left_point) and right = values.(right_point) in
                (* Round the exact endpoint mean to nearest, with half values up. *)
                (left / 2) + (right / 2) + ((left land 1) + (right land 1) + 1) / 2 in
          if has_segment_scales then begin
            let first = segment_scale_first left_vertex
            and last = segment_scale_last left_vertex in
            if not (finite first && finite last) || first < 0. || last > 1.
                || first > last then fail (Printf.sprintf
              "vertex segment scale attribute requires 0 <= first <= last <= 1 at vertex %d"
              left_vertex)
          end;
          if generate_uv then begin
            let u0 = uv_u0 left_vertex and u1 = uv_u1 left_vertex
            and v0 = uv_v0 left_vertex and v1 = uv_v1 left_vertex in
            if not (finite u0 && finite u1 && finite v0 && finite v1) then
              fail (Printf.sprintf
                "vertex UV range attribute contains a non-finite value at vertex %d"
                left_vertex)
          end;
          edge_segments.(left_vertex) <- count;
          ring_count := checked_add "PolyWire ring count" !ring_count count
        done;
        curve_of_primitive.(primitive) <- !curve_index;
        curve_ring_offsets.(!curve_index + 1) <- checked_add
            "PolyWire ring count" curve_ring_offsets.(!curve_index) !ring_count;
        let transitions = if closed then
            if !breaks = 0 then !ring_count else !ring_count - !breaks
          else !ring_count - 1 - !breaks in
        curve_transition_offsets.(!curve_index + 1) <- checked_add
            "PolyWire transition count" curve_transition_offsets.(!curve_index)
            transitions;
        incr curve_index
      end
    done;
    let ring_count = curve_ring_offsets.(!selected_count)
    and transition_count = curve_transition_offsets.(!selected_count) in
    let has_breaks = Array.exists (fun count -> count > 0) primitive_breaks in
    let curves = Array.make !selected_count {
        primitive = 0; closed = false; cap_ends = false;
        ring_first = 0; ring_count = 0; transition_first = 0;
        transition_count = 0 }
    and ring_left_vertex = Array.make ring_count 0
    and ring_right_vertex = Array.make ring_count 0
    and ring_weight = Array.make ring_count 0.
    and transition_source_vertex = Array.make transition_count 0
    and transition_curve = Array.make transition_count 0
    and transition_current = Array.make transition_count 0
    and transition_next = Array.make transition_count 0
    and ring_break_before = Bytes.make ring_count '\000'
    and ring_joint_point = if prevent_joint_buckling
        then Array.make ring_count (-1) else [||]
    and transition_t0 = if need_transition_parameters
        then Array.make transition_count 0. else [||]
    and transition_t1 = if need_transition_parameters
        then Array.make transition_count 0. else [||] in
    let curve_index = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        let index = !curve_index
        and first = source.primitive_offsets.(primitive)
        and last = source.primitive_offsets.(primitive + 1) in
        let count = last - first
        and closed = Topology.primitive_kind topology primitive
            = Topology.Closed_polyline
        and ring_first = curve_ring_offsets.(index)
        and ring_last = curve_ring_offsets.(index + 1)
        and transition_first = curve_transition_offsets.(index)
        and transition_last = curve_transition_offsets.(index + 1) in
        let effective_closed = closed && primitive_breaks.(primitive) = 0 in
        curves.(index) <- { primitive; closed = effective_closed;
          cap_ends = not closed; ring_first;
          ring_count = ring_last - ring_first;
          transition_first; transition_count = transition_last - transition_first };
        let ring = ref ring_first in
        if not closed then begin
          ring_left_vertex.(!ring) <- first;
          ring_right_vertex.(!ring) <- first;
          incr ring
        end;
        let edges = count - 1 + if closed then 1 else 0 in
        let start_edge = if closed && primitive_breaks.(primitive) > 0 then begin
            let found = ref (-1) in
            for local = 0 to count - 1 do
              if !found < 0 && Bytes.get point_smooth
                  source.vertex_points.(first + local) = '\000' then
                found := local
            done;
            !found
          end else 0 in
        for order = 0 to edges - 1 do
          let local = if closed then (start_edge + order) mod count else order in
          let left_vertex = first + (local mod count)
          and right_vertex = first + ((local + 1) mod count) in
          let subdivisions = edge_segments.(left_vertex) in
          if closed && primitive_breaks.(primitive) > 0 && order = 0 then begin
            ring_left_vertex.(!ring) <- left_vertex;
            ring_right_vertex.(!ring) <- left_vertex;
            ring_weight.(!ring) <- 0.;
            incr ring
          end else if ((not closed && local > 0)
              || (closed && primitive_breaks.(primitive) > 0 && order > 0))
              && Bytes.get point_smooth source.vertex_points.(left_vertex) = '\000'
          then begin
            ring_left_vertex.(!ring) <- left_vertex;
            ring_right_vertex.(!ring) <- left_vertex;
            ring_weight.(!ring) <- 0.;
            Bytes.set ring_break_before !ring '\001';
            incr ring
          end;
          let split_closed = closed && primitive_breaks.(primitive) > 0 in
          let first_sample = if closed && not split_closed then 0 else 1
          and last_sample = if closed && not split_closed
            then subdivisions - 1 else subdivisions in
          for sample = first_sample to last_sample do
            ring_left_vertex.(!ring) <- left_vertex;
            ring_right_vertex.(!ring) <- right_vertex;
            ring_weight.(!ring) <- segment_parameter left_vertex subdivisions sample;
            if prevent_joint_buckling
                && ((closed && not split_closed && sample = 0)
                  || ((not closed || split_closed) && sample = subdivisions
                    && (closed || local + 1 < edges)))
                && Bytes.get point_smooth source.vertex_points.
                    ((if closed then left_vertex else right_vertex)) <> '\000'
            then
              ring_joint_point.(!ring) <- source.vertex_points.
                ((if closed then left_vertex else right_vertex));
            incr ring
          done
        done;
        if !ring <> ring_last then
          fail "internal ring cardinality mismatch";
        let transition = ref transition_first in
        for current = ring_first to ring_last - 2 do
          let next = current + 1 in
          if Bytes.get ring_break_before next = '\000' then begin
            let edge_vertex = ring_left_vertex.(next) in
            transition_current.(!transition) <- current;
            transition_next.(!transition) <- next;
            transition_source_vertex.(!transition) <- edge_vertex;
            transition_curve.(!transition) <- index;
            if need_transition_parameters then begin
              transition_t0.(!transition) <- if ring_left_vertex.(current)
                  = edge_vertex then ring_weight.(current) else 0.;
              transition_t1.(!transition) <- ring_weight.(next)
            end;
            incr transition
          end
        done;
        if effective_closed then begin
          let current = ring_last - 1 and next = ring_first in
          transition_current.(!transition) <- current;
          transition_next.(!transition) <- next;
          transition_source_vertex.(!transition) <- ring_left_vertex.(current);
          transition_curve.(!transition) <- index;
          if need_transition_parameters then begin
            transition_t0.(!transition) <- ring_weight.(current);
            transition_t1.(!transition) <- 1.
          end;
          incr transition
        end;
        if !transition <> transition_last then
          fail "internal transition cardinality mismatch";
        incr curve_index
      end
    done;
    let ring_divisions = Array.make ring_count sides
    and ring_point_offsets = Array.make (ring_count + 1) 0
    and center_x = Array.make ring_count 0.
    and center_y = Array.make ring_count 0.
    and center_z = Array.make ring_count 0. in
    for ring = 0 to ring_count - 1 do
      if ring land 4095 = 0 then Cancel.check_opt cancel;
      let left_vertex = ring_left_vertex.(ring)
      and right_vertex = ring_right_vertex.(ring)
      and weight = ring_weight.(ring) in
      let left_point = source.vertex_points.(left_vertex)
      and right_point = source.vertex_points.(right_vertex) in
      let divisions = match division_values with
        | None -> sides
        | Some values -> values.
            ((if weight < 0.5 then left_point else right_point)) in
      ring_divisions.(ring) <- divisions;
      ring_point_offsets.(ring + 1) <- checked_add "PolyWire point count"
          ring_point_offsets.(ring) divisions;
      center_x.(ring) <- interpolate positions.x.(left_point)
          positions.x.(right_point) weight;
      center_y.(ring) <- interpolate positions.y.(left_point)
          positions.y.(right_point) weight;
      center_z.(ring) <- interpolate positions.z.(left_point)
          positions.z.(right_point) weight;
      if not (finite center_x.(ring) && finite center_y.(ring)
          && finite center_z.(ring)) then
        fail (Printf.sprintf "generated ring center %d is not finite" ring)
    done;
    let wire_point_count = ring_point_offsets.(ring_count) in
    let output_point_count = checked_add "PolyWire point count"
        !kept_source_points wire_point_count in
    let transition_face_offsets = Array.make (transition_count + 1) 0
    and transition_vertex_offsets = Array.make (transition_count + 1) 0 in
    Array.iter (fun curve ->
      for local = 0 to curve.transition_count - 1 do
        let transition = curve.transition_first + local in
        let current = transition_current.(transition)
        and next = transition_next.(transition) in
        let a = ring_divisions.(current) and b = ring_divisions.(next) in
        let common = gcd a b in
        transition_face_offsets.(transition + 1) <- checked_add
            "PolyWire primitive count" transition_face_offsets.(transition)
            (a + b - common);
        transition_vertex_offsets.(transition + 1) <- checked_add
            "PolyWire vertex count" transition_vertex_offsets.(transition)
            ((3 * a) + (3 * b) - (2 * common))
      done) curves;
    let selected_side_primitives = transition_face_offsets.(transition_count)
    and selected_side_vertices = transition_vertex_offsets.(transition_count) in
    let cap_count = if caps then Array.fold_left (fun count curve ->
        if curve.cap_ends then checked_add "PolyWire cap count" count 2 else count)
        0 curves else 0 in
    let retained_primitives = primitive_count - !selected_count in
    let output_primitive_count = checked_add "PolyWire primitive count"
        (checked_add "PolyWire primitive count" retained_primitives
          selected_side_primitives) cap_count in
    let retained_vertices = ref 0 and cap_vertices = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if not (selected primitives primitive) then
        retained_vertices := checked_add "PolyWire vertex count" !retained_vertices
          (source.primitive_offsets.(primitive + 1)
            - source.primitive_offsets.(primitive))
    done;
    if caps then Array.iter (fun curve -> if curve.cap_ends then
      cap_vertices := checked_add "PolyWire cap vertex count" !cap_vertices
        (ring_divisions.(curve.ring_first)
          + ring_divisions.(curve.ring_first + curve.ring_count - 1))) curves;
    let output_vertex_count = checked_add "PolyWire vertex count"
        (checked_add "PolyWire vertex count" !retained_vertices
          selected_side_vertices) !cap_vertices in
    let primitive_first = Array.make (primitive_count + 1) 0
    and vertex_first = Array.make (primitive_count + 1) 0 in
    for primitive = 0 to primitive_count - 1 do
      if selected primitives primitive then begin
        let curve = curves.(curve_of_primitive.(primitive)) in
        let side_faces = transition_face_offsets.
            (curve.transition_first + curve.transition_count)
          - transition_face_offsets.(curve.transition_first) in
        let side_vertices = transition_vertex_offsets.
            (curve.transition_first + curve.transition_count)
          - transition_vertex_offsets.(curve.transition_first) in
        primitive_first.(primitive + 1) <- checked_add "PolyWire primitive count"
            primitive_first.(primitive)
            (side_faces + if caps && curve.cap_ends then 2 else 0);
        vertex_first.(primitive + 1) <- checked_add "PolyWire vertex count"
            vertex_first.(primitive)
            (side_vertices + if caps && curve.cap_ends then
              ring_divisions.(curve.ring_first)
              + ring_divisions.(curve.ring_first + curve.ring_count - 1)
             else 0)
      end else begin
        primitive_first.(primitive + 1) <- primitive_first.(primitive) + 1;
        vertex_first.(primitive + 1) <- vertex_first.(primitive)
          + source.primitive_offsets.(primitive + 1)
          - source.primitive_offsets.(primitive)
      end
    done;
    if primitive_first.(primitive_count) <> output_primitive_count
        || vertex_first.(primitive_count) <> output_vertex_count then
      fail "internal output cardinality mismatch";
    let tangent_x = Array.make ring_count 0.
    and tangent_y = Array.make ring_count 0.
    and tangent_z = Array.make ring_count 0.
    and frame_x = Array.make ring_count 0.
    and frame_y = Array.make ring_count 0.
    and frame_z = Array.make ring_count 0.
    and cumulative = Array.make ring_count 0.
    and curve_total = Array.make !selected_count 0.
    and tangent_previous = if has_segment_scales || prevent_joint_buckling
        || has_breaks
      then Array.make ring_count 0
      else [||]
    and tangent_next = if has_segment_scales || prevent_joint_buckling
        || has_breaks
      then Array.make ring_count 0
      else [||]
    and joint_direction_x = if prevent_joint_buckling
      then Array.make ring_count 0. else [||]
    and joint_direction_y = if prevent_joint_buckling
      then Array.make ring_count 0. else [||]
    and joint_direction_z = if prevent_joint_buckling
      then Array.make ring_count 0. else [||]
    and joint_limit = if prevent_joint_buckling
      then Array.make ring_count 1. else [||] in
    let initialize_frame ring tx ty tz =
      let ax, ay, az =
        let x = abs_float tx and y = abs_float ty and z = abs_float tz in
        if x <= y && x <= z then 1., 0., 0.
        else if y <= z then 0., 1., 0. else 0., 0., 1. in
      match normalize ((ay *. tz) -. (az *. ty))
          ((az *. tx) -. (ax *. tz)) ((ax *. ty) -. (ay *. tx)) with
      | None -> fail "undefined initial frame"
      | Some (x, y, z) -> frame_x.(ring) <- x; frame_y.(ring) <- y; frame_z.(ring) <- z in
    let transport previous ring =
      let ax = (tangent_y.(previous) *. tangent_z.(ring))
          -. (tangent_z.(previous) *. tangent_y.(ring))
      and ay = (tangent_z.(previous) *. tangent_x.(ring))
          -. (tangent_x.(previous) *. tangent_z.(ring))
      and az = (tangent_x.(previous) *. tangent_y.(ring))
          -. (tangent_y.(previous) *. tangent_x.(ring)) in
      let sine = sqrt ((ax *. ax) +. (ay *. ay) +. (az *. az))
      and cosine = (tangent_x.(previous) *. tangent_x.(ring))
          +. (tangent_y.(previous) *. tangent_y.(ring))
          +. (tangent_z.(previous) *. tangent_z.(ring)) in
      if sine <= 1e-12 then
        if cosine >= 0. then begin
          frame_x.(ring) <- frame_x.(previous);
          frame_y.(ring) <- frame_y.(previous);
          frame_z.(ring) <- frame_z.(previous)
        end else initialize_frame ring tangent_x.(ring) tangent_y.(ring)
            tangent_z.(ring)
      else begin
        let kx = ax /. sine and ky = ay /. sine and kz = az /. sine
        and vx = frame_x.(previous) and vy = frame_y.(previous)
        and vz = frame_z.(previous) in
        let cx = (ky *. vz) -. (kz *. vy)
        and cy = (kz *. vx) -. (kx *. vz)
        and cz = (kx *. vy) -. (ky *. vx)
        and dot = (kx *. vx) +. (ky *. vy) +. (kz *. vz) in
        frame_x.(ring) <- (vx *. cosine) +. (cx *. sine)
          +. (kx *. dot *. (1. -. cosine));
        frame_y.(ring) <- (vy *. cosine) +. (cy *. sine)
          +. (ky *. dot *. (1. -. cosine));
        frame_z.(ring) <- (vz *. cosine) +. (cz *. sine)
          +. (kz *. dot *. (1. -. cosine))
      end in
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(!selected_count - 1)
      (fun curve_index ->
        Cancel.check_opt cancel;
        let curve = curves.(curve_index) in
        let first = curve.ring_first
        and last = curve.ring_first + curve.ring_count - 1 in
        if primitive_breaks.(curve.primitive) > 0 then begin
          let same_center left right = robust_length
              (center_x.(right) -. center_x.(left))
              (center_y.(right) -. center_y.(left))
              (center_z.(right) -. center_z.(left)) <= 1e-20 in
          let run_first = ref first in
          while !run_first <= last do
            let run_last = ref (!run_first + 1) in
            while !run_last <= last
                && Bytes.get ring_break_before !run_last = '\000' do
              incr run_last
            done;
            let position = ref !run_first in
            while !position < !run_last do
              let duplicate_last = ref (!position + 1) in
              while !duplicate_last < !run_last
                  && same_center (!duplicate_last - 1) !duplicate_last do
                incr duplicate_last
              done;
              let previous = if !position = !run_first then !run_first
                else !position - 1
              and next = if !duplicate_last = !run_last then !run_last - 1
                else !duplicate_last in
              for ring = !position to !duplicate_last - 1 do
                tangent_previous.(ring) <- previous;
                tangent_next.(ring) <- next
              done;
              position := !duplicate_last
            done;
            run_first := !run_last
          done
        end else if (has_segment_scales || prevent_joint_buckling)
            && curve.closed then begin
          let same_center left right = robust_length
              (center_x.(right) -. center_x.(left))
              (center_y.(right) -. center_y.(left))
              (center_z.(right) -. center_z.(left)) <= 1e-20 in
          let break = ref (-1) in
          for local = 0 to curve.ring_count - 1 do
            let ring = first + local
            and next = first + ((local + 1) mod curve.ring_count) in
            if !break < 0 && not (same_center ring next) then break := local
          done;
          if !break < 0 then fail (Printf.sprintf
            "primitive %d has zero length" curve.primitive);
          let start_local = (!break + 1) mod curve.ring_count in
          let ring_at position = first
              + ((start_local + position) mod curve.ring_count) in
          let position = ref 0 in
          while !position < curve.ring_count do
            let run_first = !position and run_last = ref (!position + 1) in
            while !run_last < curve.ring_count
                && same_center (ring_at (!run_last - 1)) (ring_at !run_last) do
              incr run_last
            done;
            let previous = ring_at ((run_first + curve.ring_count - 1)
                mod curve.ring_count)
            and next = ring_at (!run_last mod curve.ring_count) in
            for at = run_first to !run_last - 1 do
              let ring = ring_at at in
              tangent_previous.(ring) <- previous;
              tangent_next.(ring) <- next
            done;
            position := !run_last
          done
        end else if has_segment_scales || prevent_joint_buckling
            || has_breaks then begin
          let same_center left right = robust_length
              (center_x.(right) -. center_x.(left))
              (center_y.(right) -. center_y.(left))
              (center_z.(right) -. center_z.(left)) <= 1e-20 in
          let run_first = ref first in
          while !run_first <= last do
            let run_last = ref (!run_first + 1) in
            while !run_last <= last
                && same_center (!run_last - 1) !run_last do incr run_last done;
            let previous = if !run_first = first then first else !run_first - 1
            and next = if !run_last > last then last else !run_last in
            for ring = !run_first to !run_last - 1 do
              tangent_previous.(ring) <- previous;
              tangent_next.(ring) <- next
            done;
            run_first := !run_last
          done
        end;
        for local = 0 to curve.ring_count - 1 do
          let ring = curve.ring_first + local in
          let previous = if has_segment_scales || prevent_joint_buckling
              || has_breaks
            then tangent_previous.(ring)
            else if local = 0 then
              if curve.closed then last else ring
            else ring - 1
          and next = if has_segment_scales || prevent_joint_buckling
              || has_breaks
            then tangent_next.(ring)
            else if local + 1 = curve.ring_count then
              if curve.closed then first else ring
            else ring + 1 in
          let tangent = if prevent_joint_buckling
              && ring_joint_point.(ring) >= 0 then
              let idx = center_x.(ring) -. center_x.(previous)
              and idy = center_y.(ring) -. center_y.(previous)
              and idz = center_z.(ring) -. center_z.(previous)
              and odx = center_x.(next) -. center_x.(ring)
              and ody = center_y.(next) -. center_y.(ring)
              and odz = center_z.(next) -. center_z.(ring) in
              let incoming_length = robust_length idx idy idz
              and outgoing_length = robust_length odx ody odz in
              if incoming_length <= 1e-20 || outgoing_length <= 1e-20
                  || not (finite incoming_length && finite outgoing_length)
              then None
              else
                  let ix = idx /. incoming_length
                  and iy = idy /. incoming_length
                  and iz = idz /. incoming_length
                  and ox = odx /. outgoing_length
                  and oy = ody /. outgoing_length
                  and oz = odz /. outgoing_length in
                  joint_direction_x.(ring) <- ix;
                  joint_direction_y.(ring) <- iy;
                  joint_direction_z.(ring) <- iz;
                  let point = ring_joint_point.(ring) in
                  joint_limit.(ring) <- (match maximum_joint_scale_values with
                    | None -> maximum_joint_scale
                    | Some values -> values.(point));
                  normalize (ix +. ox) (iy +. oy) (iz +. oz)
            else normalize (center_x.(next) -. center_x.(previous))
                (center_y.(next) -. center_y.(previous))
                (center_z.(next) -. center_z.(previous)) in
          match tangent with
          | None -> fail (Printf.sprintf "primitive %d has an undefined tangent"
              curve.primitive)
          | Some (x, y, z) ->
              tangent_x.(ring) <- x; tangent_y.(ring) <- y; tangent_z.(ring) <- z;
          if local > 0 then begin
            let length = robust_length (center_x.(ring) -. center_x.(ring - 1))
                (center_y.(ring) -. center_y.(ring - 1))
                (center_z.(ring) -. center_z.(ring - 1)) in
            if not (finite length)
                || (not has_segment_scales
                  && Bytes.get ring_break_before ring = '\000'
                  && length <= 1e-20)
            then fail (Printf.sprintf
              "primitive %d has a zero-length or non-finite generated segment"
              curve.primitive);
            cumulative.(ring) <- cumulative.(ring - 1) +. length
          end
        done;
        let total = if curve.closed then begin
            let length = robust_length (center_x.(first) -. center_x.(last))
                (center_y.(first) -. center_y.(last))
                (center_z.(first) -. center_z.(last)) in
            if not (finite length) || (not has_segment_scales && length <= 1e-20)
            then fail (Printf.sprintf
              "primitive %d has a zero-length or non-finite generated closing segment"
              curve.primitive);
            cumulative.(last) +. length
          end else cumulative.(last) in
        if not (finite total) || total <= 1e-20 then fail (Printf.sprintf
          "primitive %d has zero or non-finite length" curve.primitive);
        curve_total.(curve_index) <- total;
        (match up_values with
         | None ->
             initialize_frame first tangent_x.(first) tangent_y.(first)
               tangent_z.(first);
             for ring = first + 1 to last do
               if Bytes.get ring_break_before ring <> '\000' then
                 initialize_frame ring tangent_x.(ring) tangent_y.(ring)
                   tangent_z.(ring)
               else transport (ring - 1) ring
             done;
             if curve.closed then begin
               (* Transport the last frame across the closing tangent change,
                  then distribute the residual roll by stable arc length. *)
               let saved_x = frame_x.(first) and saved_y = frame_y.(first)
               and saved_z = frame_z.(first) in
               transport last first;
               let closed_x = frame_x.(first) and closed_y = frame_y.(first)
               and closed_z = frame_z.(first) in
               frame_x.(first) <- saved_x; frame_y.(first) <- saved_y;
               frame_z.(first) <- saved_z;
               let cx = (closed_y *. saved_z) -. (closed_z *. saved_y)
               and cy = (closed_z *. saved_x) -. (closed_x *. saved_z)
               and cz = (closed_x *. saved_y) -. (closed_y *. saved_x) in
               let correction = atan2
                   ((tangent_x.(first) *. cx) +. (tangent_y.(first) *. cy)
                     +. (tangent_z.(first) *. cz))
                   ((closed_x *. saved_x) +. (closed_y *. saved_y)
                     +. (closed_z *. saved_z)) in
               for ring = first + 1 to last do
                 let angle = correction *. cumulative.(ring) /. total in
                 let cosine = cos angle and sine = sin angle
                 and tx = tangent_x.(ring) and ty = tangent_y.(ring)
                 and tz = tangent_z.(ring)
                 and vx = frame_x.(ring) and vy = frame_y.(ring)
                 and vz = frame_z.(ring) in
                 let cx = (ty *. vz) -. (tz *. vy)
                 and cy = (tz *. vx) -. (tx *. vz)
                 and cz = (tx *. vy) -. (ty *. vx) in
                 frame_x.(ring) <- (vx *. cosine) +. (cx *. sine);
                 frame_y.(ring) <- (vy *. cosine) +. (cy *. sine);
                 frame_z.(ring) <- (vz *. cosine) +. (cz *. sine)
               done
             end
         | Some up ->
             for ring = first to last do
               let left_point = source.vertex_points.(ring_left_vertex.(ring))
               and right_point = source.vertex_points.(ring_right_vertex.(ring))
               and weight = ring_weight.(ring) in
               let ux = interpolate up.x.(left_point) up.x.(right_point) weight
               and uy = interpolate up.y.(left_point) up.y.(right_point) weight
               and uz = interpolate up.z.(left_point) up.z.(right_point) weight
               and tx = tangent_x.(ring) and ty = tangent_y.(ring)
               and tz = tangent_z.(ring) in
               let projection = (ux *. tx) +. (uy *. ty) +. (uz *. tz) in
               match normalize (ux -. (projection *. tx))
                   (uy -. (projection *. ty)) (uz -. (projection *. tz)) with
               | None -> fail (Printf.sprintf
                   "point %d has a joint up vector parallel to its tangent"
                   left_point)
               | Some (x, y, z) ->
                   frame_x.(ring) <- x; frame_y.(ring) <- y; frame_z.(ring) <- z
             done));
    let profile_cos = Array.make 4_097 [||]
    and profile_sin = Array.make 4_097 [||] in
    for ring = 0 to ring_count - 1 do
      let count = ring_divisions.(ring) in
      if Array.length profile_cos.(count) = 0 then begin
        profile_cos.(count) <- Array.init count (fun side ->
          cos (2. *. Float.pi *. float_of_int side /. float_of_int count));
        profile_sin.(count) <- Array.init count (fun side ->
          sin (2. *. Float.pi *. float_of_int side /. float_of_int count))
      end
    done;
    let px = Array.make output_point_count 0.
    and py = Array.make output_point_count 0.
    and pz = Array.make output_point_count 0.
    and point_nx = Array.make output_point_count 0.
    and point_ny = Array.make output_point_count 0.
    and point_nz = Array.make output_point_count 0.
    and point_left = Array.make output_point_count 0
    and point_right = Array.make output_point_count 0
    and point_weight = Array.make output_point_count 0. in
    let source_point_n = match Geometry.find_attribute ~owner:Attribute.Point "N"
        geometry with
      | Some attribute -> (match Attribute.Private.storage attribute with
          | Attribute.Float3 values -> Some (Packed.Float3.Private.view values)
          | _ -> None)
      | None -> None in
    for source_point = 0 to point_count - 1 do
      let target = source_point_target.(source_point) in
      if target >= 0 then begin
        px.(target) <- positions.x.(source_point);
        py.(target) <- positions.y.(source_point);
        pz.(target) <- positions.z.(source_point);
        point_left.(target) <- source_point;
        point_right.(target) <- source_point;
        match source_point_n with
        | None -> ()
        | Some normal ->
            point_nx.(target) <- normal.x.(source_point);
            point_ny.(target) <- normal.y.(source_point);
            point_nz.(target) <- normal.z.(source_point)
      end
    done;
    let wire_point ring side = !kept_source_points
        + ring_point_offsets.(ring) + side in
    Parallel.for_ ~chunk_size:(max 1 (grain / 64)) ~start:0
      ~finish:(ring_count - 1) (fun ring ->
        if ring land 4095 = 0 then Cancel.check_opt cancel;
        let left_point = source.vertex_points.(ring_left_vertex.(ring))
        and right_point = source.vertex_points.(ring_right_vertex.(ring))
        and weight = ring_weight.(ring)
        and count = ring_divisions.(ring) in
        let ring_radius = radius *. match scale_values with
          | None -> 1.
          | Some values -> interpolate values.(left_point) values.(right_point) weight in
        if not (finite ring_radius) then fail (Printf.sprintf
          "generated ring %d has a non-finite radius" ring);
        let seam_attribute = match seam_values with
          | None -> 0
          | Some values -> values.((if weight < 0.5 then left_point else right_point)) in
        let seam =
          let a = seam_offset mod count and b = seam_attribute mod count in
          let value = a + b in
          let value = if value < 0 then value + count else value in
          if value >= count then value - count else value in
        let bx = (tangent_y.(ring) *. frame_z.(ring))
            -. (tangent_z.(ring) *. frame_y.(ring))
        and by = (tangent_z.(ring) *. frame_x.(ring))
            -. (tangent_x.(ring) *. frame_z.(ring))
        and bz = (tangent_x.(ring) *. frame_y.(ring))
            -. (tangent_y.(ring) *. frame_x.(ring)) in
        match normalize bx by bz with
        | None -> fail (Printf.sprintf "ring %d has an undefined local frame" ring)
        | Some (bx, by, bz) ->
          for side = 0 to count - 1 do
            let profile = let value = side + seam in
              if value >= count then value - count else value in
            let cosine = profile_cos.(count).(profile)
            and sine = profile_sin.(count).(profile)
            and output = wire_point ring side in
            let nx = (frame_x.(ring) *. cosine) +. (bx *. sine)
            and ny = (frame_y.(ring) *. cosine) +. (by *. sine)
            and nz = (frame_z.(ring) *. cosine) +. (bz *. sine) in
            let joint_scale = if prevent_joint_buckling
                && ring_joint_point.(ring) >= 0 then
                let dot = (nx *. joint_direction_x.(ring))
                    +. (ny *. joint_direction_y.(ring))
                    +. (nz *. joint_direction_z.(ring)) in
                let denominator_squared = Float.max 0. (1. -. (dot *. dot)) in
                let ideal = if denominator_squared <= 1e-24 then
                    joint_limit.(ring)
                  else 1. /. sqrt denominator_squared in
                Float.min joint_limit.(ring) (Float.max 1. ideal)
              else 1. in
            let scaled_radius = ring_radius *. joint_scale in
            let x = center_x.(ring) +. (scaled_radius *. nx)
            and y = center_y.(ring) +. (scaled_radius *. ny)
            and z = center_z.(ring) +. (scaled_radius *. nz) in
            if not (finite x && finite y && finite z) then fail (Printf.sprintf
              "generated ring %d is not finite" ring);
            px.(output) <- x; py.(output) <- y; pz.(output) <- z;
            point_nx.(output) <- nx; point_ny.(output) <- ny;
            point_nz.(output) <- nz;
            point_left.(output) <- left_point;
            point_right.(output) <- right_point;
            point_weight.(output) <- weight
          done);
    let primitive_offsets = Array.make (output_primitive_count + 1) 0
    and primitive_map = Array.make output_primitive_count 0
    and primitive_kinds = Bytes.make output_primitive_count '\000'
    and is_cap = Bytes.make output_primitive_count '\000' in
    for primitive = 0 to primitive_count - 1 do
      let output_primitive = ref primitive_first.(primitive)
      and output_vertex = ref vertex_first.(primitive) in
      if not (selected primitives primitive) then begin
        let size = source.primitive_offsets.(primitive + 1)
          - source.primitive_offsets.(primitive) in
        primitive_offsets.(!output_primitive) <- !output_vertex;
        output_vertex := !output_vertex + size;
        primitive_offsets.(!output_primitive + 1) <- !output_vertex;
        primitive_map.(!output_primitive) <- primitive;
        Bytes.set primitive_kinds !output_primitive
          (Bytes.get source.primitive_kinds primitive);
        incr output_primitive
      end else begin
        let curve = curves.(curve_of_primitive.(primitive)) in
        for local = 0 to curve.transition_count - 1 do
          let transition = curve.transition_first + local in
          let current = transition_current.(transition)
          and next = transition_next.(transition) in
          let a = ring_divisions.(current) and b = ring_divisions.(next) in
          let i = ref 0 and j = ref 0 in
          while !i < a || !j < b do
            let advance_a = !i < a and advance_b = !j < b in
            let comparison = if not advance_a then 1 else if not advance_b then -1
              else Int.compare ((!i + 1) * b) ((!j + 1) * a) in
            let size = if comparison = 0 then 4 else 3 in
            primitive_offsets.(!output_primitive) <- !output_vertex;
            output_vertex := !output_vertex + size;
            primitive_offsets.(!output_primitive + 1) <- !output_vertex;
            primitive_map.(!output_primitive) <- primitive;
            incr output_primitive;
            if comparison <= 0 then incr i;
            if comparison >= 0 then incr j
          done
        done;
        if caps && curve.cap_ends then begin
          let start_size = ring_divisions.(curve.ring_first)
          and end_size = ring_divisions.(curve.ring_first + curve.ring_count - 1) in
          List.iter (fun size ->
            primitive_offsets.(!output_primitive) <- !output_vertex;
            output_vertex := !output_vertex + size;
            primitive_offsets.(!output_primitive + 1) <- !output_vertex;
            primitive_map.(!output_primitive) <- primitive;
            Bytes.set is_cap !output_primitive '\001';
            incr output_primitive) [start_size; end_size]
        end
      end;
      if !output_primitive <> primitive_first.(primitive + 1)
          || !output_vertex <> vertex_first.(primitive + 1) then
        fail "internal primitive layout mismatch"
    done;
    let vertex_points = Array.make output_vertex_count 0
    and vertex_left = Array.make output_vertex_count 0
    and vertex_right = Array.make output_vertex_count 0
    and vertex_weight = Array.make output_vertex_count 0.
    and uv_x = if generate_uv then Array.make output_vertex_count 0. else [||]
    and uv_y = if generate_uv then Array.make output_vertex_count 0. else [||]
    and vertex_nx = Array.make output_vertex_count 0.
    and vertex_ny = Array.make output_vertex_count 0.
    and vertex_nz = Array.make output_vertex_count 0. in
    let source_vertex_n = match Geometry.find_attribute ~owner:Attribute.Vertex "N"
        geometry with
      | Some attribute -> (match Attribute.Private.storage attribute with
          | Attribute.Float3 values -> Some (Packed.Float3.Private.view values)
          | _ -> None)
      | None -> None
    and source_uv = match Geometry.find_attribute ~owner:Attribute.Vertex "uv"
        geometry with
      | Some attribute -> (match Attribute.Private.storage attribute with
          | Attribute.Float2 values -> Some (Packed.Float2.Private.view values)
          | _ -> None)
      | None -> None in
    let set_wire_corner output ring side shift u v =
      let count = ring_divisions.(ring) in
      let side = side mod count in
      let side = side + shift in
      let point = wire_point ring (if side >= count then side - count else side) in
      vertex_points.(output) <- point;
      vertex_left.(output) <- ring_left_vertex.(ring);
      vertex_right.(output) <- ring_right_vertex.(ring);
      vertex_weight.(output) <- ring_weight.(ring);
      if generate_uv then begin uv_x.(output) <- u; uv_y.(output) <- v end;
      vertex_nx.(output) <- point_nx.(point);
      vertex_ny.(output) <- point_ny.(point);
      vertex_nz.(output) <- point_nz.(point) in
    Parallel.for_ ~chunk_size:(max 1 (grain / 16)) ~start:0
      ~finish:(primitive_count - 1) (fun primitive ->
        if primitive land 255 = 0 then Cancel.check_opt cancel;
        if not (selected primitives primitive) then begin
          let source_first = source.primitive_offsets.(primitive)
          and source_last = source.primitive_offsets.(primitive + 1)
          and output_first = vertex_first.(primitive) in
          for source_vertex = source_first to source_last - 1 do
            let output = output_first + source_vertex - source_first
            and source_point = source.vertex_points.(source_vertex) in
            vertex_points.(output) <- source_point_target.(source_point);
            vertex_left.(output) <- source_vertex;
            vertex_right.(output) <- source_vertex;
            (match source_vertex_n with
             | None -> ()
             | Some normal ->
                 vertex_nx.(output) <- normal.x.(source_vertex);
                 vertex_ny.(output) <- normal.y.(source_vertex);
                 vertex_nz.(output) <- normal.z.(source_vertex));
            (match source_uv with
             | None -> ()
             | Some uv when generate_uv ->
                 uv_x.(output) <- uv.x.(source_vertex);
                 uv_y.(output) <- uv.y.(source_vertex)
             | Some _ -> ())
          done
        end);
    if transition_count > 0 then Parallel.for_
      ~chunk_size:(max 1 (grain / 16)) ~start:0 ~finish:(transition_count - 1)
      (fun transition ->
        if transition land 4095 = 0 then Cancel.check_opt cancel;
        let curve_index = transition_curve.(transition)
        and curve = curves.(transition_curve.(transition)) in
        let current = transition_current.(transition)
        and next = transition_next.(transition) in
        let a = ring_divisions.(current) and b = ring_divisions.(next) in
        let edge_vertex = transition_source_vertex.(transition) in
        let segment_shift = match segment_seam_values with
          | None -> 0 | Some values -> values.(edge_vertex) in
        let current_shift = normalized_offset segment_shift a
        and next_shift = normalized_offset segment_shift b in
        let edge_u0 = if custom_u_ranges then uv_u0 edge_vertex else 0.
        and edge_u1 = if custom_u_ranges then uv_u1 edge_vertex else 1.
        and edge_v0 = if need_transition_parameters then uv_v0 edge_vertex else 0.
        and edge_v1 = if need_transition_parameters then uv_v1 edge_vertex else 1. in
        let v0 = match v_values with
          | Some values ->
              let lp = source.vertex_points.(ring_left_vertex.(current))
              and rp = source.vertex_points.(ring_right_vertex.(current)) in
              interpolate values.(lp) values.(rp) ring_weight.(current)
          | None when need_transition_parameters ->
              edge_v0 +. ((edge_v1 -. edge_v0) *. transition_t0.(transition))
          | None -> cumulative.(current) /. curve_total.(curve_index) in
        let v1 = match v_values with
          | Some values ->
              let lp = source.vertex_points.(ring_left_vertex.(next))
              and rp = source.vertex_points.(ring_right_vertex.(next)) in
              interpolate values.(lp) values.(rp) ring_weight.(next)
          | None when need_transition_parameters ->
              edge_v0 +. ((edge_v1 -. edge_v0) *. transition_t1.(transition))
          | None when curve.closed && next = curve.ring_first -> 1.
          | None -> cumulative.(next) /. curve_total.(curve_index) in
        let output_primitive = ref (primitive_first.(curve.primitive)
            + transition_face_offsets.(transition)
            - transition_face_offsets.(curve.transition_first))
        and i = ref 0 and j = ref 0 in
        if custom_u_ranges then
          while !i < a || !j < b do
            let comparison = if !i >= a then 1 else if !j >= b then -1
              else Int.compare ((!i + 1) * b) ((!j + 1) * a) in
            let at = primitive_offsets.(!output_primitive) in
            if comparison = 0 then begin
              set_wire_corner at current !i current_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int !i /. float_of_int a)) v0;
              set_wire_corner (at + 1) current (!i + 1) current_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int (!i + 1) /. float_of_int a)) v0;
              set_wire_corner (at + 2) next (!j + 1) next_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int (!j + 1) /. float_of_int b)) v1;
              set_wire_corner (at + 3) next !j next_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int !j /. float_of_int b)) v1
            end else if comparison < 0 then begin
              set_wire_corner at current !i current_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int !i /. float_of_int a)) v0;
              set_wire_corner (at + 1) current (!i + 1) current_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int (!i + 1) /. float_of_int a)) v0;
              set_wire_corner (at + 2) next !j next_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int !j /. float_of_int b)) v1
            end else begin
              set_wire_corner at current !i current_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int !i /. float_of_int a)) v0;
              set_wire_corner (at + 1) next (!j + 1) next_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int (!j + 1) /. float_of_int b)) v1;
              set_wire_corner (at + 2) next !j next_shift
                (interpolate edge_u0 edge_u1
                  (float_of_int !j /. float_of_int b)) v1
            end;
            incr output_primitive;
            if comparison <= 0 then incr i;
            if comparison >= 0 then incr j
          done
        else
          while !i < a || !j < b do
            let comparison = if !i >= a then 1 else if !j >= b then -1
              else Int.compare ((!i + 1) * b) ((!j + 1) * a) in
            let at = primitive_offsets.(!output_primitive) in
            if comparison = 0 then begin
              set_wire_corner at current !i current_shift
                (float_of_int !i /. float_of_int a) v0;
              set_wire_corner (at + 1) current (!i + 1) current_shift
                (float_of_int (!i + 1) /. float_of_int a) v0;
              set_wire_corner (at + 2) next (!j + 1) next_shift
                (float_of_int (!j + 1) /. float_of_int b) v1;
              set_wire_corner (at + 3) next !j next_shift
                (float_of_int !j /. float_of_int b) v1
            end else if comparison < 0 then begin
              set_wire_corner at current !i current_shift
                (float_of_int !i /. float_of_int a) v0;
              set_wire_corner (at + 1) current (!i + 1) current_shift
                (float_of_int (!i + 1) /. float_of_int a) v0;
              set_wire_corner (at + 2) next !j next_shift
                (float_of_int !j /. float_of_int b) v1
            end else begin
              set_wire_corner at current !i current_shift
                (float_of_int !i /. float_of_int a) v0;
              set_wire_corner (at + 1) next (!j + 1) next_shift
                (float_of_int (!j + 1) /. float_of_int b) v1;
              set_wire_corner (at + 2) next !j next_shift
                (float_of_int !j /. float_of_int b) v1
            end;
            incr output_primitive;
            if comparison <= 0 then incr i;
            if comparison >= 0 then incr j
          done);
    if caps then Parallel.for_ ~chunk_size:1 ~start:0
      ~finish:(!selected_count - 1) (fun curve_index ->
        let curve = curves.(curve_index) in
        if curve.cap_ends then begin
          let first_cap = primitive_first.(curve.primitive)
              + transition_face_offsets.
                  (curve.transition_first + curve.transition_count)
              - transition_face_offsets.(curve.transition_first) in
          let emit_cap ~start ~output_primitive ring =
            let count = ring_divisions.(ring)
            and at = primitive_offsets.(output_primitive) in
            let left_point = source.vertex_points.(ring_left_vertex.(ring))
            and right_point = source.vertex_points.(ring_right_vertex.(ring))
            and weight = ring_weight.(ring) in
            let seam_attribute = match seam_values with
              | None -> 0
              | Some values -> values.
                  ((if weight < 0.5 then left_point else right_point)) in
            let a = seam_offset mod count and b = seam_attribute mod count in
            let seam = let value = a + b in
              let value = if value < 0 then value + count else value in
              if value >= count then value - count else value in
            let edge_vertex = ring_left_vertex.(ring) in
            let segment_shift = match segment_seam_values with
              | None -> 0
              | Some values -> normalized_offset values.(edge_vertex) count in
            let edge_u0 = uv_u0 edge_vertex and edge_u1 = uv_u1 edge_vertex
            and edge_v0 = uv_v0 edge_vertex and edge_v1 = uv_v1 edge_vertex in
            for local = 0 to count - 1 do
              let side = if start then count - 1 - local else local
              and output = at + local in
              let profile = let value = side + seam in
                if value >= count then value - count else value in
              let planar_u = 0.5 +. (0.5 *. profile_cos.(count).(profile))
              and planar_v = 0.5 +. (0.5 *. profile_sin.(count).(profile)) in
              set_wire_corner output ring side segment_shift
                (edge_u0 +. ((edge_u1 -. edge_u0) *. planar_u))
                (edge_v0 +. ((edge_v1 -. edge_v0) *. planar_v));
              let sign = if start then -1. else 1. in
              vertex_nx.(output) <- sign *. tangent_x.(ring);
              vertex_ny.(output) <- sign *. tangent_y.(ring);
              vertex_nz.(output) <- sign *. tangent_z.(ring)
            done in
          emit_cap ~start:true ~output_primitive:first_cap curve.ring_first;
          emit_cap ~start:false ~output_primitive:(first_cap + 1)
            (curve.ring_first + curve.ring_count - 1)
        end);
    let output_topology = Topology.Private.create_validated_owned
        ~point_count:output_point_count ~vertex_points ~primitive_offsets
        ~primitive_kinds in
    let remapped_attributes = List.filter_map (fun attribute ->
      let owner = Attribute.owner attribute and name = Attribute.name attribute in
      if String.equal name "N"
          && (owner = Attribute.Point || owner = Attribute.Vertex)
          || generate_uv && String.equal name "uv" && owner = Attribute.Vertex then None
      else Some (match owner with
        | Attribute.Point | Attribute.Vertex ->
            Curve_ops.interpolate_attribute ?cancel ~grain point_left point_right
              point_weight vertex_left vertex_right vertex_weight attribute
        | Attribute.Primitive ->
            Topology_remap.attribute ?cancel ~grain primitive_map attribute
        | Attribute.Detail -> attribute)) (Geometry.attributes geometry) in
    let point_normal = Attribute.create_key_owned
        (Attribute.normal ~owner:Attribute.Point)
        (Packed.Float3.Private.of_owned_exn ~x:point_nx ~y:point_ny ~z:point_nz)
      |> Result.get_ok
    in
    let attributes = remapped_attributes @ [point_normal] in
    let attributes = if generate_uv then
        let vertex_uv = Attribute.create_key_owned
            (Attribute.tex_coord ~owner:Attribute.Vertex)
            (Packed.Float2.of_owned ~x:uv_x ~y:uv_y |> Result.get_ok)
          |> Result.get_ok in
        attributes @ [vertex_uv]
      else attributes in
    let attributes = if caps || Option.is_some source_vertex_n then
        Attribute.create_key_owned (Attribute.normal ~owner:Attribute.Vertex)
          (Packed.Float3.Private.of_owned_exn ~x:vertex_nx ~y:vertex_ny ~z:vertex_nz)
        |> Result.get_ok |> fun normal -> attributes @ [normal]
      else attributes in
    let groups = List.map (fun group ->
      let left, right, weight = match Group.owner group with
        | Group.Point -> point_left, point_right, point_weight
        | Group.Vertex -> vertex_left, vertex_right, vertex_weight
        | Group.Primitive -> primitive_map, primitive_map, [||] in
      let mapping = if Group.owner group = Group.Primitive then primitive_map
        else Array.init (Array.length left) (fun output ->
          (if weight.(output) < 0.5 then left else right).(output)) in
      let target = Group.init ~grain ~owner:(Group.owner group)
          ~name:(Group.name group) (Array.length mapping)
          (fun output -> Group.mem mapping.(output) group) in
      Group.Private.remap_order ~source:group ~source_of_target:mapping target)
        (Geometry.groups geometry) in
    let edge_groups = match Geometry.edge_groups geometry with
      | [] -> []
      | source_groups ->
          let source_index = Topology_index.create ?cancel topology
          and target_index = Topology_index.create ?cancel output_topology in
          let target_view = Topology_index.Private.view target_index
          and source_of_kept = Array.make !kept_source_points 0 in
          for source_point = 0 to point_count - 1 do
            let target = source_point_target.(source_point) in
            if target >= 0 then source_of_kept.(target) <- source_point
          done;
          let target_edge_count = Topology_index.edge_count target_index in
          let source_edge_of_target = Array.make target_edge_count (-1) in
          let install target_edge source_edge =
            if target_edge >= 0 then
              if source_edge_of_target.(target_edge) < 0 then
                source_edge_of_target.(target_edge) <- source_edge
              else if source_edge_of_target.(target_edge) <> source_edge then
                source_edge_of_target.(target_edge) <- -2 in
          for target_edge = 0 to target_edge_count - 1 do
            if target_edge land 4095 = 0 then Cancel.check_opt cancel;
            let a = target_view.edge_a.(target_edge)
            and b = target_view.edge_b.(target_edge) in
            if a < !kept_source_points && b < !kept_source_points then begin
              let source_edge = Topology_index.find_edge_index source_index
                  ~a:source_of_kept.(a) ~b:source_of_kept.(b) in
              if source_edge >= 0 then install target_edge source_edge
            end
          done;
          Array.iter (fun curve ->
            for local = 0 to curve.transition_count - 1 do
              let transition = curve.transition_first + local in
              let current = transition_current.(transition)
              and next = transition_next.(transition) in
              let a = ring_divisions.(current) and b = ring_divisions.(next) in
              let common = gcd a b
              and source_edge = Topology_index.edge_of_vertex source_index
                  transition_source_vertex.(transition) in
              let segment_shift = match segment_seam_values with
                | None -> 0
                | Some values -> values.(transition_source_vertex.(transition)) in
              let current_shift = normalized_offset segment_shift a
              and next_shift = normalized_offset segment_shift b in
              if source_edge >= 0 then
                for rank = 0 to common - 1 do
                  let current_side = rank * (a / common)
                  and next_side = rank * (b / common) in
                  let target_edge = Topology_index.find_edge_index target_index
                      ~a:(wire_point current
                        ((current_side + current_shift) mod a))
                      ~b:(wire_point next ((next_side + next_shift) mod b)) in
                  install target_edge source_edge
                done
            done) curves;
          List.map (fun source_group ->
            let byte_count = (target_edge_count + 7) / 8 in
            let bits = Bytes.make byte_count '\000' in
            if byte_count > 0 then Parallel.for_ ~chunk_size:(max 1 (grain / 8))
                ~start:0 ~finish:(byte_count - 1) (fun byte ->
              if byte land 511 = 0 then Cancel.check_opt cancel;
              let value = ref 0 in
              for bit = 0 to 7 do
                let target_edge = (byte lsl 3) + bit in
                if target_edge < target_edge_count then begin
                  let source_edge = source_edge_of_target.(target_edge) in
                  if source_edge >= 0 && Edge_group.mem source_edge source_group then
                    value := !value lor (1 lsl bit)
                end
              done;
              Bytes.set bits byte (Char.chr !value));
            Edge_group.Private.of_owned_bits ~topology:output_topology
              ~edge_count:target_edge_count ~name:(Edge_group.name source_group) bits)
            source_groups in
    let output = Geometry.create
        ~positions:(Packed.Float3.Private.of_owned_exn ~x:px ~y:py ~z:pz)
        ~topology:output_topology ~attributes ~groups ~edge_groups ()
      |> Result.get_ok in
    match cap_group with
    | None -> Ok output
    | Some name ->
        let group = Group.init ~grain ~owner:Group.Primitive ~name
            output_primitive_count (fun primitive ->
              Bytes.get is_cap primitive <> '\000') in
        Geometry.with_group group output
    end
  with
  | Invalid message -> Error ("Pdk.Ops.sweep_circle: " ^ message)
