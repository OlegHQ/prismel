open Prismel

type incidence = Any_edge | Boundary_edge | Manifold_edge | Non_manifold_edge
type angle_basis = Primitive_dihedral | Incident_edges
type equalize_method = Equalize_average | Equalize_longest | Equalize_shortest

exception Edge_error of string
let fail message = raise (Edge_error message)
let selected primitives primitive = match primitives with
  | None -> true
  | Some group -> Group.mem primitive group

let packed_flags ?cancel ~grain length predicate =
  let byte_count = (length + 7) / 8 in
  let output = Bytes.make byte_count '\000' in
  let bytes_per_range = max 1 (grain / 8) in
  let range_count = if byte_count = 0 then 0
    else ((byte_count - 1) / bytes_per_range) + 1 in
  if range_count > 0 then
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
      (fun range ->
        Cancel.check_opt cancel;
        let first_byte = range * bytes_per_range
        and last_byte = min byte_count ((range + 1) * bytes_per_range) in
        for byte = first_byte to last_byte - 1 do
          let base = byte * 8 and value = ref 0 in
          for bit = 0 to min 7 (length - base - 1) do
            if predicate (base + bit) then value := !value lor (1 lsl bit)
          done;
          Bytes.unsafe_set output byte (Char.unsafe_chr !value)
        done);
  output

let[@inline always] finite_position positions point =
  Float.is_finite positions.Packed.Float3.Private.x.(point)
  && Float.is_finite positions.y.(point)
  && Float.is_finite positions.z.(point)

let[@inline always] maximum_abs left right =
  let left = abs_float left and right = abs_float right in
  if left > right then left else right

let[@inline always] length_matches positions invalid_position
    has_minimum minimum has_maximum maximum a b =
  if not (finite_position positions a && finite_position positions b) then begin
    Atomic.set invalid_position true;
    false
  end else
    let scale = maximum_abs positions.x.(a) positions.x.(b) in
    let scale = maximum_abs scale positions.y.(a) in
    let scale = maximum_abs scale positions.y.(b) in
    let scale = maximum_abs scale positions.z.(a) in
    let scale = maximum_abs scale positions.z.(b) in
    if scale = 0. then
      (not has_minimum || minimum <= 0.)
      && (not has_maximum || maximum >= 0.)
    else
      let dx = positions.x.(b) /. scale -. positions.x.(a) /. scale
      and dy = positions.y.(b) /. scale -. positions.y.(a) /. scale
      and dz = positions.z.(b) /. scale -. positions.z.(a) /. scale in
      let normalized = sqrt (dx *. dx +. dy *. dy +. dz *. dz) in
      (not has_minimum || normalized >= minimum /. scale)
      && (not has_maximum || normalized <= maximum /. scale)

let group ?cancel ?(grain = 16_384) ?(name = "edges") ?primitives
    ?(incidence = Any_edge) ?min_length ?max_length
    ?(angle_basis = Primitive_dihedral) ?min_angle ?max_angle geometry =
  try
    if grain <= 0 then fail "Edge Group grain must be positive";
    if String.trim name = "" then fail "Edge Group name must not be empty";
    let validate_non_negative label = function
      | Some value when not (Float.is_finite value) || value < 0. ->
          fail (label ^ " must be finite and non-negative")
      | _ -> () in
    let validate_angle label = function
      | Some value when not (Float.is_finite value) || value < 0.
          || value > Float.pi ->
          fail (label ^ " must be finite and within [0, pi]")
      | _ -> () in
    validate_non_negative "Edge Group minimum length" min_length;
    validate_non_negative "Edge Group maximum length" max_length;
    validate_angle "Edge Group minimum angle" min_angle;
    validate_angle "Edge Group maximum angle" max_angle;
    (match min_length, max_length with
     | Some minimum, Some maximum when minimum > maximum ->
         fail "Edge Group minimum length exceeds maximum length"
     | _ -> ());
    (match min_angle, max_angle with
     | Some minimum, Some maximum when minimum > maximum ->
         fail "Edge Group minimum angle exceeds maximum angle"
     | _ -> ());
    let topology = Geometry.topology geometry in
    let primitive_count = Topology.primitive_count topology in
    (match primitives with
     | Some group when Group.owner group <> Group.Primitive ->
         fail "Edge Group selection must own primitives"
     | Some group when Group.length group <> primitive_count ->
         fail "Edge Group selection length does not match primitive count"
     | _ -> ());
    Cancel.check_opt cancel;
    let index = Topology_index.create ?cancel topology in
    let view = Topology_index.Private.view index in
    let angle_filter = min_angle <> None || max_angle <> None in
    let normals = if angle_filter && angle_basis = Primitive_dihedral then
        match Face_normals.compute ?cancel ~grain ?primitives
            ~operation:"Edge Group" geometry with
        | Ok values -> Some values
        | Error message -> fail message
      else None in
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let has_minimum_angle = Option.is_some min_angle
    and has_maximum_angle = Option.is_some max_angle
    and has_minimum_length = Option.is_some min_length
    and has_maximum_length = Option.is_some max_length in
    let minimum_angle_dot = match min_angle with None -> 1. | Some value -> cos value
    and maximum_angle_dot = match max_angle with None -> -1. | Some value -> cos value
    and minimum_length = Option.value ~default:0. min_length
    and maximum_length = Option.value ~default:max_float max_length in
    let angle_epsilon = 64. *. Float.epsilon in
    let edge_count = Topology_index.edge_count index in
    let invalid_position = Atomic.make false in
    let edge_touches_selected edge = match primitives with
      | None -> true
      | Some _ ->
          let first = view.edge_offsets.(edge)
          and last = view.edge_offsets.(edge + 1) in
          let rec touches_selected local =
            local < last
            && (let primitive = view.primitive_of_vertex.(view.edge_vertices.(local)) in
                selected primitives primitive || touches_selected (local + 1)) in
          touches_selected first in
    let candidate_bits = match angle_basis, angle_filter, primitives with
      | Incident_edges, true, Some _ ->
          Some (packed_flags ?cancel ~grain edge_count edge_touches_selected)
      | _ -> None in
    let candidate edge = match candidate_bits with
      | None -> edge_touches_selected edge
      | Some bits -> Char.code (Bytes.unsafe_get bits (edge lsr 3))
          land (1 lsl (edge land 7)) <> 0 in
    let incident_directions =
      if angle_filter && angle_basis = Incident_edges then begin
        let x = Array.make edge_count 0.
        and y = Array.make edge_count 0.
        and z = Array.make edge_count 0. in
        let range_count = if edge_count = 0 then 0
          else ((edge_count - 1) / grain) + 1 in
        if range_count > 0 then
          Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
            (fun range ->
              Cancel.check_opt cancel;
              let first = range * grain
              and last = min edge_count ((range + 1) * grain) in
              for edge = first to last - 1 do
                let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
                if not (finite_position positions a
                    && finite_position positions b) then
                  Atomic.set invalid_position true
                else
                  let scale = maximum_abs positions.x.(a) positions.x.(b) in
                  let scale = maximum_abs scale positions.y.(a) in
                  let scale = maximum_abs scale positions.y.(b) in
                  let scale = maximum_abs scale positions.z.(a) in
                  let scale = maximum_abs scale positions.z.(b) in
                  if scale <> 0. then begin
                    let dx = positions.x.(b) /. scale -. positions.x.(a) /. scale
                    and dy = positions.y.(b) /. scale -. positions.y.(a) /. scale
                    and dz = positions.z.(b) /. scale -. positions.z.(a) /. scale in
                    let length = sqrt (dx *. dx +. dy *. dy +. dz *. dz) in
                    if length <> 0. then begin
                      x.(edge) <- dx /. length;
                      y.(edge) <- dy /. length;
                      z.(edge) <- dz /. length
                    end
                  end
              done);
        Some (x, y, z)
      end else None in
    if Atomic.get invalid_position then
      fail "Edge Group requires finite point positions";
    let angle_matches edge incidence_count first = match angle_basis, normals with
      | Primitive_dihedral, None -> true
      | Primitive_dihedral, Some (nx, ny, nz) when incidence_count = 2 ->
          let left = view.primitive_of_vertex.(view.edge_vertices.(first))
          and right = view.primitive_of_vertex.(view.edge_vertices.(first + 1)) in
          if not (selected primitives left && selected primitives right) then false
          else
            let dot = nx.(left) *. nx.(right) +. ny.(left) *. ny.(right)
                +. nz.(left) *. nz.(right) in
            let dot = if dot < -1. then -1.
              else if dot > 1. then 1. else dot in
            (not has_minimum_angle || dot <= minimum_angle_dot +. angle_epsilon)
            && (not has_maximum_angle
                || dot >= maximum_angle_dot -. angle_epsilon)
      | Primitive_dihedral, Some _ -> false
      | Incident_edges, _ when not angle_filter -> true
      | Incident_edges, _ ->
          let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
          let directions = Option.get incident_directions in
          let direction_x, direction_y, direction_z = directions in
          let edge_valid = direction_x.(edge) <> 0.
              || direction_y.(edge) <> 0. || direction_z.(edge) <> 0. in
          let found = ref false in
          if edge_valid then begin
            let cursor = ref view.point_edge_offsets.(a)
            and last = view.point_edge_offsets.(a + 1) in
            while not !found && !cursor < last do
              let neighbor = view.point_edges.(!cursor) in
              if neighbor <> edge && candidate neighbor
                  && (direction_x.(neighbor) <> 0.
                      || direction_y.(neighbor) <> 0.
                      || direction_z.(neighbor) <> 0.) then begin
                let dot = direction_x.(edge) *. direction_x.(neighbor)
                    +. direction_y.(edge) *. direction_y.(neighbor)
                    +. direction_z.(edge) *. direction_z.(neighbor) in
                let dot = if view.edge_a.(neighbor) = a then dot else -.dot in
                let dot = if dot < -1. then -1.
                  else if dot > 1. then 1. else dot in
                found := (not has_minimum_angle
                    || dot <= minimum_angle_dot +. angle_epsilon)
                  && (not has_maximum_angle
                      || dot >= maximum_angle_dot -. angle_epsilon)
              end;
              incr cursor
            done;
            if not !found && b <> a then begin
              let cursor = ref view.point_edge_offsets.(b)
              and last = view.point_edge_offsets.(b + 1) in
              while not !found && !cursor < last do
                let neighbor = view.point_edges.(!cursor) in
                if neighbor <> edge && candidate neighbor
                    && (direction_x.(neighbor) <> 0.
                        || direction_y.(neighbor) <> 0.
                        || direction_z.(neighbor) <> 0.) then begin
                  let dot = direction_x.(edge) *. direction_x.(neighbor)
                      +. direction_y.(edge) *. direction_y.(neighbor)
                      +. direction_z.(edge) *. direction_z.(neighbor) in
                  let dot = if view.edge_a.(neighbor) = b then -.dot else dot in
                  let dot = if dot < -1. then -1.
                    else if dot > 1. then 1. else dot in
                  found := (not has_minimum_angle
                      || dot <= minimum_angle_dot +. angle_epsilon)
                    && (not has_maximum_angle
                        || dot >= maximum_angle_dot -. angle_epsilon)
                end;
                incr cursor
              done
            end
          end;
          !found in
    let members = packed_flags ?cancel ~grain edge_count (fun edge ->
          let first = view.edge_offsets.(edge)
          and last = view.edge_offsets.(edge + 1) in
          let incidence_count = last - first in
          let incidence_matches = match incidence with
            | Any_edge -> true
            | Boundary_edge -> incidence_count = 1
            | Manifold_edge -> incidence_count = 2
            | Non_manifold_edge -> incidence_count > 2 in
          let length_matches = match min_length, max_length with
            | None, None -> true
            | _ ->
                let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
                length_matches positions invalid_position
                  has_minimum_length minimum_length has_maximum_length
                  maximum_length a b in
          candidate edge && incidence_matches && length_matches
          && angle_matches edge incidence_count first) in
    if Atomic.get invalid_position then
      fail "Edge Group requires finite edge lengths";
    let group = Edge_group.Private.of_owned_bits ~topology ~edge_count ~name members in
    Geometry.with_edge_group group geometry
  with Edge_error message -> Error message

let straighten ?cancel ?(grain = 16_384) ?edges ?output_group geometry =
  try
    if grain <= 0 then fail "Edge Straighten grain must be positive";
    Option.iter (fun name -> if String.trim name = "" then
      fail "Edge Straighten output edge group name must not be empty")
      output_group;
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let index = Topology_index.create ?cancel topology in
    let view = Topology_index.Private.view index in
    let edge_count = Array.length view.edge_a
    and point_count = Geometry.point_count geometry in
    (match edges with
     | Some selection when Edge_group.topology_data_id selection
         <> Topology.data_id topology ->
         fail "Edge Straighten selection belongs to a different topology"
     | Some selection when Edge_group.length selection <> edge_count ->
         fail "Edge Straighten selection length does not match topology edge count"
     | None | Some _ -> ());
    let selected edge = match edges with
      | None -> true | Some selection -> Edge_group.mem edge selection in
    let install_output geometry = match output_group with
      | None -> Ok geometry
      | Some name ->
          let output = Edge_group.init ~grain ~topology ~index ~name selected in
          Geometry.with_edge_group output geometry in
    if edge_count = 0 || (match edges with
        | Some selection -> Edge_group.cardinality selection = 0
        | None -> false) then install_output geometry
    else begin
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let parent = Array.init point_count Fun.id
      and rank = Bytes.make point_count '\000'
      and touched = Bytes.make point_count '\000'
      and first_invalid = ref (-1) in
      let root point =
        let representative = ref point in
        while parent.(!representative) <> !representative do
          representative := parent.(!representative)
        done;
        let representative = !representative and current = ref point in
        while parent.(!current) <> representative do
          let next = parent.(!current) in
          parent.(!current) <- representative;
          current := next
        done;
        representative in
      let union left right =
        let left = root left and right = root right in
        if left <> right then begin
          let left_rank = Char.code (Bytes.get rank left)
          and right_rank = Char.code (Bytes.get rank right) in
          if left_rank < right_rank then parent.(left) <- right
          else if right_rank < left_rank then parent.(right) <- left
          else begin
            let representative, child =
              if left < right then left, right else right, left in
            parent.(child) <- representative;
            Bytes.set rank representative (Char.chr (left_rank + 1))
          end
        end in
      for edge = 0 to edge_count - 1 do
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        if selected edge then begin
          let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
          if !first_invalid < 0
              && (not (finite_position positions a)
                  || not (finite_position positions b)) then
            first_invalid := edge;
          Bytes.set touched a '\001';
          Bytes.set touched b '\001';
          union a b
        end
      done;
      if !first_invalid >= 0 then fail (Printf.sprintf
          "Edge Straighten selected edge %d has a non-finite endpoint"
          !first_invalid);
      let root_component = Array.make point_count (-1)
      and point_component = Array.make point_count (-1)
      and component_count = ref 0 in
      for point = 0 to point_count - 1 do
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if Bytes.get touched point <> '\000' then begin
          let representative = root point in
          let component = if root_component.(representative) >= 0 then
              root_component.(representative)
            else begin
              let component = !component_count in
              incr component_count;
              root_component.(representative) <- component;
              component
            end in
          point_component.(point) <- component
        end
      done;
      let component_count = !component_count in
      let counts = Array.make component_count 0 in
      for point = 0 to point_count - 1 do
        let component = point_component.(point) in
        if component >= 0 then counts.(component) <- counts.(component) + 1
      done;
      let offsets = Array.make (component_count + 1) 0 in
      for component = 0 to component_count - 1 do
        offsets.(component + 1) <- offsets.(component) + counts.(component)
      done;
      let members = Array.make offsets.(component_count) 0
      and next = Array.copy offsets in
      for point = 0 to point_count - 1 do
        let component = point_component.(point) in
        if component >= 0 then begin
          members.(next.(component)) <- point;
          next.(component) <- next.(component) + 1
        end
      done;
      let center_x = Array.make component_count 0.
      and center_y = Array.make component_count 0.
      and center_z = Array.make component_count 0.
      and axis_x = Array.make component_count 1.
      and axis_y = Array.make component_count 0.
      and axis_z = Array.make component_count 0.
      and coordinate_scale = Array.make component_count 1.
      and moves = Bytes.make component_count '\000' in
      if component_count > 0 then Parallel.for_
          ~chunk_size:(max 1 (grain / 16)) ~start:0
          ~finish:(component_count - 1) (fun component ->
        Cancel.check_opt cancel;
        let first = offsets.(component) and last = offsets.(component + 1) in
        if last - first > 2 then begin
          let scale = ref 0. in
          for at = first to last - 1 do
            let point = members.(at) in
            scale := maximum_abs !scale positions.x.(point);
            scale := maximum_abs !scale positions.y.(point);
            scale := maximum_abs !scale positions.z.(point)
          done;
          let scale = if !scale = 0. then 1. else !scale in
          coordinate_scale.(component) <- scale;
          let sx = ref 0. and sy = ref 0. and sz = ref 0. in
          for at = first to last - 1 do
            let point = members.(at) in
            sx := !sx +. (positions.x.(point) /. scale);
            sy := !sy +. (positions.y.(point) /. scale);
            sz := !sz +. (positions.z.(point) /. scale)
          done;
          let inverse = 1. /. float_of_int (last - first) in
          let cx = !sx *. inverse and cy = !sy *. inverse
          and cz = !sz *. inverse in
          center_x.(component) <- cx;
          center_y.(component) <- cy;
          center_z.(component) <- cz;
          let xx = ref 0. and xy = ref 0. and xz = ref 0.
          and yy = ref 0. and yz = ref 0. and zz = ref 0. in
          for at = first to last - 1 do
            let point = members.(at) in
            let x = (positions.x.(point) /. scale) -. cx
            and y = (positions.y.(point) /. scale) -. cy
            and z = (positions.z.(point) /. scale) -. cz in
            xx := !xx +. (x *. x); xy := !xy +. (x *. y);
            xz := !xz +. (x *. z); yy := !yy +. (y *. y);
            yz := !yz +. (y *. z); zz := !zz +. (z *. z)
          done;
          if !xx <> 0. || !yy <> 0. || !zz <> 0. then begin
            let best_x = ref 1. and best_y = ref 0. and best_z = ref 0.
            and best_value = ref (-1.) in
            for seed = 0 to 2 do
              let vx = ref (if seed = 0 then 1. else 0.)
              and vy = ref (if seed = 1 then 1. else 0.)
              and vz = ref (if seed = 2 then 1. else 0.)
              and iteration = ref 0 and converged = ref false in
              while !iteration < 64 && not !converged do
                let old_x = !vx and old_y = !vy and old_z = !vz in
                let x = (!xx *. old_x) +. (!xy *. old_y) +. (!xz *. old_z)
                and y = (!xy *. old_x) +. (!yy *. old_y) +. (!yz *. old_z)
                and z = (!xz *. old_x) +. (!yz *. old_y) +. (!zz *. old_z) in
                let magnitude = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
                if magnitude = 0. then converged := true
                else begin
                  vx := x /. magnitude; vy := y /. magnitude;
                  vz := z /. magnitude;
                  let alignment = abs_float ((old_x *. !vx) +. (old_y *. !vy)
                      +. (old_z *. !vz)) in
                  if 1. -. alignment <= 8. *. Float.epsilon then
                    converged := true
                end;
                incr iteration
              done;
              let wx = (!xx *. !vx) +. (!xy *. !vy) +. (!xz *. !vz)
              and wy = (!xy *. !vx) +. (!yy *. !vy) +. (!yz *. !vz)
              and wz = (!xz *. !vx) +. (!yz *. !vy) +. (!zz *. !vz) in
              let value = (!vx *. wx) +. (!vy *. wy) +. (!vz *. wz) in
              if value > !best_value then begin
                best_x := !vx; best_y := !vy; best_z := !vz;
                best_value := value
              end
            done;
            let vx = !best_x and vy = !best_y and vz = !best_z in
            axis_x.(component) <- vx;
            axis_y.(component) <- vy;
            axis_z.(component) <- vz;
            let maximum_residual = ref 0. and spread = ref 0. in
            for at = first to last - 1 do
              let point = members.(at) in
              let x = (positions.x.(point) /. scale) -. cx
              and y = (positions.y.(point) /. scale) -. cy
              and z = (positions.z.(point) /. scale) -. cz in
              let along = (x *. vx) +. (y *. vy) +. (z *. vz) in
              let rx = x -. (along *. vx)
              and ry = y -. (along *. vy)
              and rz = z -. (along *. vz) in
              let residual = sqrt ((rx *. rx) +. (ry *. ry) +. (rz *. rz))
              and radius = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
              if residual > !maximum_residual then maximum_residual := residual;
              if radius > !spread then spread := radius
            done;
            if !maximum_residual > 512. *. Float.epsilon *. max 1. !spread
            then Bytes.set moves component '\001'
          end
        end);
      if not (Bytes.exists (( = ) '\001') moves) then install_output geometry
      else begin
        let x = Array.copy positions.x and y = Array.copy positions.y
        and z = Array.copy positions.z in
        let first_bad = Atomic.make max_int in
        if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(point_count - 1) (fun point ->
          if point land 4095 = 0 then Cancel.check_opt cancel;
          let component = point_component.(point) in
          if component >= 0 && Bytes.get moves component <> '\000' then begin
            let scale = coordinate_scale.(component) in
            let dx = (positions.x.(point) /. scale) -. center_x.(component)
            and dy = (positions.y.(point) /. scale) -. center_y.(component)
            and dz = (positions.z.(point) /. scale) -. center_z.(component) in
            let along = dx *. axis_x.(component) +. dy *. axis_y.(component)
                +. dz *. axis_z.(component) in
            let px = scale *. (center_x.(component)
                +. (along *. axis_x.(component)))
            and py = scale *. (center_y.(component)
                +. (along *. axis_y.(component)))
            and pz = scale *. (center_z.(component)
                +. (along *. axis_z.(component))) in
            if Float.is_finite px && Float.is_finite py && Float.is_finite pz
            then begin x.(point) <- px; y.(point) <- py; z.(point) <- pz end
            else begin
              let rec record () =
                let known = Atomic.get first_bad in
                if point < known
                    && not (Atomic.compare_and_set first_bad known point) then
                  record () in
              record ()
            end
          end);
        if Atomic.get first_bad <> max_int then fail (Printf.sprintf
            "Edge Straighten projection produced a non-finite point at %d"
            (Atomic.get first_bad));
        let packed = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
        let output = Geometry.with_positions packed geometry |> function
          | Ok output -> output
          | Error message -> fail message in
        let output = output
            |> Geometry.without_attribute ~owner:Attribute.Point "N"
            |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
        install_output output
      end
    end
  with Edge_error message -> Error message

let[@inline always] edge_length positions a b =
  let scale = maximum_abs positions.Packed.Float3.Private.x.(a)
      positions.x.(b) in
  let scale = maximum_abs scale positions.y.(a) in
  let scale = maximum_abs scale positions.y.(b) in
  let scale = maximum_abs scale positions.z.(a) in
  let scale = maximum_abs scale positions.z.(b) in
  if scale = 0. then 0.
  else
    let dx = positions.x.(b) /. scale -. positions.x.(a) /. scale
    and dy = positions.y.(b) /. scale -. positions.y.(a) /. scale
    and dz = positions.z.(b) /. scale -. positions.z.(a) /. scale in
    scale *. sqrt (dx *. dx +. dy *. dy +. dz *. dz)

let equalize ?cancel ?(grain = 16_384) ?edges
    ?(method_ = Equalize_average) ?(iterations = 64) ?(tolerance = 1e-6)
    ?output_group geometry =
  try
    if grain <= 0 then fail "Edge Equalize grain must be positive";
    if iterations <= 0 then fail "Edge Equalize iterations must be positive";
    if not (Float.is_finite tolerance) || tolerance <= 0. then
      fail "Edge Equalize tolerance must be finite and positive";
    Option.iter (fun name -> if String.trim name = "" then
      fail "Edge Equalize output edge group name must not be empty")
      output_group;
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let index = Topology_index.create ?cancel topology in
    let view = Topology_index.Private.view index in
    let edge_count = Array.length view.edge_a
    and point_count = Geometry.point_count geometry in
    (match edges with
     | Some selection when Edge_group.topology_data_id selection
         <> Topology.data_id topology ->
         fail "Edge Equalize selection belongs to a different topology"
     | Some selection when Edge_group.length selection <> edge_count ->
         fail "Edge Equalize selection length does not match topology edge count"
     | None | Some _ -> ());
    let selected edge = match edges with
      | None -> true | Some selection -> Edge_group.mem edge selection in
    let install_output geometry = match output_group with
      | None -> Ok geometry
      | Some name ->
          let output = Edge_group.init ~grain ~topology ~index ~name selected in
          Geometry.with_edge_group output geometry in
    if edge_count = 0 || (match edges with
        | Some selection -> Edge_group.cardinality selection = 0
        | None -> false) then install_output geometry
    else begin
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let degrees = match edges with
        | None -> None
        | Some _ -> Some (Array.make point_count 0) in
      let lengths = Array.make edge_count 0. in
      let selected_count = match edges with
        | None -> edge_count
        | Some selection -> Edge_group.cardinality selection in
      let maximum_length = ref 0.
      and minimum_length = ref max_float and first_invalid = Atomic.make max_int in
      let record_invalid edge =
        let rec record () =
          let known = Atomic.get first_invalid in
          if edge < known
              && not (Atomic.compare_and_set first_invalid known edge) then
            record () in
        record () in
      (match degrees with
       | None ->
           Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(edge_count - 1)
             (fun edge ->
               if edge land 4095 = 0 then Cancel.check_opt cancel;
               let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
               let length = edge_length positions a b in
               lengths.(edge) <- length;
               if not (finite_position positions a)
                   || not (finite_position positions b)
                   || not (Float.is_finite length) then record_invalid edge)
       | Some degrees ->
           for edge = 0 to edge_count - 1 do
             if edge land 4095 = 0 then Cancel.check_opt cancel;
             if selected edge then begin
               let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
               let length = edge_length positions a b in
               lengths.(edge) <- length;
               if not (finite_position positions a)
                   || not (finite_position positions b)
                   || not (Float.is_finite length) then record_invalid edge;
               degrees.(a) <- degrees.(a) + 1;
               if b <> a then degrees.(b) <- degrees.(b) + 1
             end
           done);
      if Atomic.get first_invalid <> max_int then fail (Printf.sprintf
          "Edge Equalize selected edge %d has a non-finite or unrepresentable length"
          (Atomic.get first_invalid));
      for edge = 0 to edge_count - 1 do
        if selected edge then begin
          let length = lengths.(edge) in
          if length > !maximum_length then maximum_length := length;
          if length < !minimum_length then minimum_length := length
        end
      done;
      if selected_count = 0 then install_output geometry
      else begin
        let target = match method_ with
          | Equalize_longest -> !maximum_length
          | Equalize_shortest -> !minimum_length
          | Equalize_average ->
              if !maximum_length = 0. then 0.
              else begin
                let normalized_sum = ref 0. in
                for edge = 0 to edge_count - 1 do
                  if selected edge then
                    normalized_sum := !normalized_sum
                      +. (lengths.(edge) /. !maximum_length)
                done;
                !maximum_length *. (!normalized_sum /.
                  float_of_int selected_count)
              end in
        if not (Float.is_finite target) then
          fail "Edge Equalize target length is not representable";
        if target > 0. then begin
          let zero = ref (-1) in
          for edge = 0 to edge_count - 1 do
            if !zero < 0 && selected edge then begin
              if lengths.(edge) = 0. then zero := edge
            end
          done;
          if !zero >= 0 then fail (Printf.sprintf
              "Edge Equalize cannot expand zero-length selected edge %d without a direction"
              !zero)
        end;
        let scale = max target !maximum_length in
        let threshold = tolerance *. scale in
        let initial_error = ref 0. and maximum_degree = ref 0
        and moves_x = ref false and moves_y = ref false
        and moves_z = ref false in
        for edge = 0 to edge_count - 1 do
          if selected edge then begin
            let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
            let error = abs_float (lengths.(edge) -. target) in
            if error > !initial_error then initial_error := error;
            if error > threshold then begin
              if positions.x.(a) <> positions.x.(b) then moves_x := true;
              if positions.y.(a) <> positions.y.(b) then moves_y := true;
              if positions.z.(a) <> positions.z.(b) then moves_z := true
            end
          end
        done;
        for point = 0 to point_count - 1 do
          let degree = match degrees with
            | Some degrees -> degrees.(point)
            | None -> view.point_edge_offsets.(point + 1)
                - view.point_edge_offsets.(point) in
          if degree > !maximum_degree then maximum_degree := degree
        done;
        if !initial_error <= threshold then install_output geometry
        else begin
          let independent = !maximum_degree = 1 in
          let packed = if independent then begin
            let x = if not !moves_x then positions.x else Array.copy positions.x
            and y = if not !moves_y then positions.y else Array.copy positions.y
            and z = if not !moves_z then positions.z else Array.copy positions.z in
            let first_bad = Atomic.make max_int in
            if edge_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                ~finish:(edge_count - 1) (fun edge ->
              if edge land 4095 = 0 then Cancel.check_opt cancel;
              if selected edge then begin
                let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
                let length = lengths.(edge) in
                let factor = if length = 0. then 0.5
                  else 0.5 *. (length -. target) /. length in
                let dx = positions.x.(b) -. positions.x.(a)
                and dy = positions.y.(b) -. positions.y.(a)
                and dz = positions.z.(b) -. positions.z.(a) in
                let ax = positions.x.(a) +. factor *. dx
                and ay = positions.y.(a) +. factor *. dy
                and az = positions.z.(a) +. factor *. dz
                and bx = positions.x.(b) -. factor *. dx
                and by = positions.y.(b) -. factor *. dy
                and bz = positions.z.(b) -. factor *. dz in
                if Float.is_finite ax && Float.is_finite ay && Float.is_finite az
                    && Float.is_finite bx && Float.is_finite by
                    && Float.is_finite bz then begin
                  if !moves_x then begin x.(a) <- ax; x.(b) <- bx end;
                  if !moves_y then begin y.(a) <- ay; y.(b) <- by end;
                  if !moves_z then begin z.(a) <- az; z.(b) <- bz end
                end else begin
                  let rec record () =
                    let known = Atomic.get first_bad in
                    if edge < known
                        && not (Atomic.compare_and_set first_bad known edge) then
                      record () in
                  record ()
                end
              end);
            if Atomic.get first_bad <> max_int then fail (Printf.sprintf
                "Edge Equalize produced a non-finite point at selected edge %d"
                (Atomic.get first_bad));
            Packed.Float3.Private.of_shared_exn ~x ~y ~z
          end else begin
            match Edge_constraints.project ?cancel ~grain
                ~operation:"Edge Equalize" ~view ~source:positions ~point_count
                ~selected ~targets:(Edge_constraints.Constant target)
                ~movable:(Fun.const true) ~maximum_degree:!maximum_degree
                ~iterations ~step_size:0.9 ~threshold ~only_shorten:false () with
            | Error message -> fail message
            | Ok projection ->
                if not projection.converged then fail (Printf.sprintf
                    "Edge Equalize did not converge within %d iterations"
                    iterations);
                projection.positions
          end in
          let output = Geometry.with_positions packed geometry |> function
            | Ok output -> output | Error message -> fail message in
          let output = output
              |> Geometry.without_attribute ~owner:Attribute.Point "N"
              |> Geometry.without_attribute ~owner:Attribute.Vertex "N" in
          install_output output
        end
      end
    end
  with Edge_error message -> Error message
