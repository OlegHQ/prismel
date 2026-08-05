open Prismel

type plan = {
  edges : Edge_group.t;
  removed_primitives : int;
}

type scratch = {
  q00 : float array; q01 : float array; q02 : float array; q03 : float array;
  q11 : float array; q12 : float array; q13 : float array;
  q22 : float array; q23 : float array; q33 : float array;
  face_a : float array; face_b : float array; face_c : float array;
  face_d : float array; face_valid : bytes;
  costs : float array; incidence : int array;
  locked : bytes; reserved : bytes; neighbor_stamp : int array;
  primitive_stamp : int array;
}

let create_scratch ~points ~primitives ~edges =
  if points < 0 || primitives < 0 || edges < 0 then invalid_arg
      "Pdk.Poly_reduce.create_scratch: capacities must be non-negative";
  let float_points () = Array.make points 0. in
  { q00 = float_points (); q01 = float_points (); q02 = float_points ();
    q03 = float_points (); q11 = float_points (); q12 = float_points ();
    q13 = float_points (); q22 = float_points (); q23 = float_points ();
    q33 = float_points ();
    face_a = Array.make primitives 0.; face_b = Array.make primitives 0.;
    face_c = Array.make primitives 0.; face_d = Array.make primitives 0.;
    face_valid = Bytes.make primitives '\000';
    costs = Array.make edges infinity; incidence = Array.make edges 0;
    locked = Bytes.make points '\000';
    reserved = Bytes.make points '\000'; neighbor_stamp = Array.make points 0;
    primitive_stamp = Array.make primitives 0; }

exception Invalid of string

let finite = Float.is_finite

let validate_group ~owner ~length label = function
  | None -> ()
  | Some group when Group.owner group <> owner || Group.length group <> length ->
      raise (Invalid (Printf.sprintf "%s must be a matching %s group" label
        (match owner with Group.Point -> "point" | Group.Vertex -> "vertex"
         | Group.Primitive -> "primitive")))
  | Some _ -> ()

let validate_edge_group ~topology ~edge_count label = function
  | None -> ()
  | Some group when Edge_group.topology_data_id group <> Topology.data_id topology
      || Edge_group.length group <> edge_count ->
      raise (Invalid (label ^ " must belong to the input topology"))
  | Some _ -> ()

let[@inline] quadric_error q00 q01 q02 q03 q11 q12 q13 q22 q23 q33
    x y z =
  (q00 *. x *. x) +. (2. *. q01 *. x *. y)
  +. (2. *. q02 *. x *. z) +. (2. *. q03 *. x)
  +. (q11 *. y *. y) +. (2. *. q12 *. y *. z)
  +. (2. *. q13 *. y) +. (q22 *. z *. z)
  +. (2. *. q23 *. z) +. q33

let plan_round ?cancel ~scratch ~grain ~primitive_selection ~hard_points ~hard_edges
    ~preserve_boundary ~only_original_positions ~equalize_lengths
    ~max_normal_deviation ~primitive_budget geometry =
  try
    if grain <= 0 then invalid_arg "Pdk.Poly_reduce: grain must be positive";
    if primitive_budget <= 0 then invalid_arg
        "Pdk.Poly_reduce: primitive budget must be positive";
    if not (finite equalize_lengths) || equalize_lengths < 0. then invalid_arg
        "Pdk.Poly_reduce: equalize lengths must be finite and non-negative";
    (match max_normal_deviation with
     | Some angle when not (finite angle) || angle < 0. || angle > Float.pi ->
         invalid_arg
           "Pdk.Poly_reduce: normal deviation must be finite and in [0, pi]"
     | None | Some _ -> ());
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    if not (Topology.all_triangles topology) then raise (Invalid
        "Pdk.Poly_reduce: the round planner requires triangle polygons");
    let topology_view = Topology.Private.view topology in
    let index_value = Topology_index.create ?cancel topology in
    let index = Topology_index.Private.view index_value in
    let point_count = Geometry.point_count geometry
    and primitive_count = Geometry.primitive_count geometry
    and edge_count = Array.length index.edge_a in
    if point_count > Array.length scratch.q00
        || primitive_count > Array.length scratch.face_a
        || edge_count > Array.length scratch.costs then raise (Invalid
        "Pdk.Poly_reduce: scratch capacity is smaller than the working topology");
    validate_group ~owner:Group.Primitive ~length:primitive_count
      "Pdk.Poly_reduce: primitive selection" primitive_selection;
    validate_group ~owner:Group.Point ~length:point_count
      "Pdk.Poly_reduce: hard points" hard_points;
    validate_edge_group ~topology ~edge_count
      "Pdk.Poly_reduce: hard edges" hard_edges;
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let first_non_finite = Atomic.make max_int in
    let record_min target value =
      let rec loop current =
        if value >= current then ()
        else if not (Atomic.compare_and_set target current value) then
          loop (Atomic.get target) in
      loop (Atomic.get target) in
    Parallel.for_ ~chunk_size:(max 1 (grain / 3)) ~start:0
      ~finish:(point_count - 1) (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if not (finite positions.x.(point) && finite positions.y.(point)
            && finite positions.z.(point)) then record_min first_non_finite point);
    if Atomic.get first_non_finite <> max_int then raise (Invalid
        (Printf.sprintf "Pdk.Poly_reduce: point %d has a non-finite position"
          (Atomic.get first_non_finite)));
    let coordinate_scale = ref 0. in
    for point = 0 to point_count - 1 do
      coordinate_scale := Float.max !coordinate_scale
          (Float.max (abs_float positions.x.(point))
            (Float.max (abs_float positions.y.(point))
              (abs_float positions.z.(point))))
    done;
    let coordinate_scale = if !coordinate_scale = 0. then 1.
      else !coordinate_scale in
    let face_a = scratch.face_a and face_b = scratch.face_b
    and face_c = scratch.face_c and face_d = scratch.face_d
    and face_valid = scratch.face_valid in
    Bytes.fill face_valid 0 primitive_count '\000';
    Parallel.for_ ~chunk_size:(max 1 (grain / 3)) ~start:0
      ~finish:(primitive_count - 1) (fun primitive ->
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        let first = topology_view.primitive_offsets.(primitive) in
        let p0 = topology_view.vertex_points.(first)
        and p1 = topology_view.vertex_points.(first + 1)
        and p2 = topology_view.vertex_points.(first + 2) in
        let ax = positions.x.(p0) /. coordinate_scale
        and ay = positions.y.(p0) /. coordinate_scale
        and az = positions.z.(p0) /. coordinate_scale in
        let ux = (positions.x.(p1) /. coordinate_scale) -. ax
        and uy = (positions.y.(p1) /. coordinate_scale) -. ay
        and uz = (positions.z.(p1) /. coordinate_scale) -. az
        and vx = (positions.x.(p2) /. coordinate_scale) -. ax
        and vy = (positions.y.(p2) /. coordinate_scale) -. ay
        and vz = (positions.z.(p2) /. coordinate_scale) -. az in
        let nx = (uy *. vz) -. (uz *. vy)
        and ny = (uz *. vx) -. (ux *. vz)
        and nz = (ux *. vy) -. (uy *. vx) in
        let scale = Float.max (abs_float nx)
            (Float.max (abs_float ny) (abs_float nz)) in
        if scale <> 0. && finite scale then begin
          let nx = nx /. scale and ny = ny /. scale and nz = nz /. scale in
          let length = sqrt ((nx *. nx) +. (ny *. ny) +. (nz *. nz)) in
          if length <> 0. && finite length then begin
            let a = nx /. length and b = ny /. length and c = nz /. length in
            face_a.(primitive) <- a; face_b.(primitive) <- b;
            face_c.(primitive) <- c;
            face_d.(primitive) <-
              -. ((a *. ax) +. (b *. ay) +. (c *. az));
            Bytes.unsafe_set face_valid primitive '\001'
          end
        end);
    let q00 = scratch.q00 and q01 = scratch.q01 and q02 = scratch.q02
    and q03 = scratch.q03 and q11 = scratch.q11 and q12 = scratch.q12
    and q13 = scratch.q13 and q22 = scratch.q22 and q23 = scratch.q23
    and q33 = scratch.q33 in
    List.iter (fun values -> Array.fill values 0 point_count 0.)
      [q00;q01;q02;q03;q11;q12;q13;q22;q23;q33];
    Parallel.for_ ~chunk_size:(max 1 (grain / 6)) ~start:0
      ~finish:(point_count - 1) (fun point ->
        if point land 2047 = 0 then Cancel.check_opt cancel;
        for slot = index.point_offsets.(point)
            to index.point_offsets.(point + 1) - 1 do
          let vertex = index.point_vertices.(slot) in
          let primitive = index.primitive_of_vertex.(vertex) in
          if Bytes.unsafe_get face_valid primitive <> '\000' then begin
              let a = face_a.(primitive) and b = face_b.(primitive)
              and c = face_c.(primitive) and d = face_d.(primitive) in
              q00.(point) <- q00.(point) +. (a *. a);
              q01.(point) <- q01.(point) +. (a *. b);
              q02.(point) <- q02.(point) +. (a *. c);
              q03.(point) <- q03.(point) +. (a *. d);
              q11.(point) <- q11.(point) +. (b *. b);
              q12.(point) <- q12.(point) +. (b *. c);
              q13.(point) <- q13.(point) +. (b *. d);
              q22.(point) <- q22.(point) +. (c *. c);
              q23.(point) <- q23.(point) +. (c *. d);
              q33.(point) <- q33.(point) +. (d *. d)
          end
        done);
    let locked = scratch.locked in
    Bytes.fill locked 0 point_count '\000';
    let lock point = Bytes.unsafe_set locked point '\001' in
    (match hard_points with None -> () | Some group -> Group.iter lock group);
    (match hard_edges with
     | None -> ()
     | Some group -> Edge_group.iter (fun edge ->
         lock index.edge_a.(edge); lock index.edge_b.(edge)) group);
    for edge = 0 to edge_count - 1 do
      let edge_incidence = index.edge_offsets.(edge + 1)
          - index.edge_offsets.(edge) in
      if edge_incidence > 2
          || (preserve_boundary && edge_incidence = 1) then begin
          lock index.edge_a.(edge); lock index.edge_b.(edge)
      end
    done;
    (match primitive_selection with
     | None -> ()
     | Some group ->
         for point = 0 to point_count - 1 do
           let slot = ref index.point_offsets.(point) in
           while Bytes.unsafe_get locked point = '\000'
               && !slot < index.point_offsets.(point + 1) do
             let primitive = index.primitive_of_vertex.(index.point_vertices.(!slot)) in
             if not (Group.mem primitive group) then lock point;
             incr slot
           done
         done);
    let costs = scratch.costs and incidence = scratch.incidence in
    Array.fill costs 0 edge_count infinity;
    let eligible_primitives edge =
      let first = index.edge_offsets.(edge) and last = index.edge_offsets.(edge + 1) in
      let count = last - first in
      count >= 1 && count <= 2 &&
      match primitive_selection with
      | None -> true
      | Some group ->
          let ok = ref true in
          for slot = first to last - 1 do
            let primitive = index.primitive_of_vertex.(index.edge_vertices.(slot)) in
            if not (Group.mem primitive group) then ok := false
          done;
          !ok in
    Parallel.for_ ~chunk_size:(max 1 grain) ~start:0 ~finish:(edge_count - 1)
      (fun edge ->
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
        let count = index.edge_offsets.(edge + 1) - index.edge_offsets.(edge) in
        incidence.(edge) <- count;
        if a <> b && Bytes.unsafe_get locked a = '\000'
            && Bytes.unsafe_get locked b = '\000' && eligible_primitives edge then begin
          let ax = positions.x.(a) /. coordinate_scale
          and ay = positions.y.(a) /. coordinate_scale
          and az = positions.z.(a) /. coordinate_scale
          and bx = positions.x.(b) /. coordinate_scale
          and by = positions.y.(b) /. coordinate_scale
          and bz = positions.z.(b) /. coordinate_scale in
          let x = if only_original_positions then ax else (ax +. bx) *. 0.5
          and y = if only_original_positions then ay else (ay +. by) *. 0.5
          and z = if only_original_positions then az else (az +. bz) *. 0.5 in
          let q00 = q00.(a) +. q00.(b) and q01 = q01.(a) +. q01.(b)
          and q02 = q02.(a) +. q02.(b) and q03 = q03.(a) +. q03.(b)
          and q11 = q11.(a) +. q11.(b) and q12 = q12.(a) +. q12.(b)
          and q13 = q13.(a) +. q13.(b) and q22 = q22.(a) +. q22.(b)
          and q23 = q23.(a) +. q23.(b) and q33 = q33.(a) +. q33.(b) in
          let dx = bx -. ax and dy = by -. ay and dz = bz -. az in
          let error = quadric_error q00 q01 q02 q03 q11 q12 q13 q22 q23 q33
              x y z +. (equalize_lengths *. ((dx *. dx) +. (dy *. dy) +. (dz *. dz))) in
          if finite error then costs.(edge) <- Float.max 0. error
        end);
    let order = Array.init edge_count Fun.id in
    Array.sort (fun left right ->
      let compared = Float.compare costs.(left) costs.(right) in
      if compared <> 0 then compared else Int.compare left right) order;
    let neighbor_stamp = scratch.neighbor_stamp
    and primitive_stamp = scratch.primitive_stamp and stamp = ref 0 in
    Array.fill neighbor_stamp 0 point_count 0;
    Array.fill primitive_stamp 0 primitive_count 0;
    let link_valid edge =
      incr stamp;
      let current = !stamp in
      let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
      for slot = index.point_edge_offsets.(a)
          to index.point_edge_offsets.(a + 1) - 1 do
        let adjacent = index.point_edges.(slot) in
        let neighbor = if index.edge_a.(adjacent) = a then index.edge_b.(adjacent)
          else index.edge_a.(adjacent) in
        if neighbor <> b then neighbor_stamp.(neighbor) <- current
      done;
      let common = ref 0 in
      for slot = index.point_edge_offsets.(b)
          to index.point_edge_offsets.(b + 1) - 1 do
        let adjacent = index.point_edges.(slot) in
        let neighbor = if index.edge_a.(adjacent) = b then index.edge_b.(adjacent)
          else index.edge_a.(adjacent) in
        if neighbor <> a && neighbor_stamp.(neighbor) = current then incr common
      done;
      !common = incidence.(edge) in
    let normal_valid edge =
      let a = index.edge_a.(edge) and b = index.edge_b.(edge) in
      let ax = positions.x.(a) /. coordinate_scale
      and ay = positions.y.(a) /. coordinate_scale
      and az = positions.z.(a) /. coordinate_scale
      and bx = positions.x.(b) /. coordinate_scale
      and by = positions.y.(b) /. coordinate_scale
      and bz = positions.z.(b) /. coordinate_scale in
      let x = if only_original_positions then ax else (ax +. bx) *. 0.5
      and y = if only_original_positions then ay else (ay +. by) *. 0.5
      and z = if only_original_positions then az else (az +. bz) *. 0.5 in
      let cosine = match max_normal_deviation with None -> 0.
        | Some angle -> cos angle in
      let valid = ref true and seen_stamp = !stamp + 1 in
      stamp := seen_stamp;
      let inspect_point point =
        for slot = index.point_offsets.(point)
            to index.point_offsets.(point + 1) - 1 do
          let primitive = index.primitive_of_vertex.(index.point_vertices.(slot)) in
          if primitive_stamp.(primitive) <> seen_stamp then begin
            primitive_stamp.(primitive) <- seen_stamp;
            let first = topology_view.primitive_offsets.(primitive) in
            let p0 = topology_view.vertex_points.(first)
            and p1 = topology_view.vertex_points.(first + 1)
            and p2 = topology_view.vertex_points.(first + 2) in
            if not ((p0 = a || p1 = a || p2 = a)
                && (p0 = b || p1 = b || p2 = b)) then begin
              let coord point axis = if point = a || point = b then
                  if axis = 0 then x else if axis = 1 then y else z
                else if axis = 0 then positions.x.(point) /. coordinate_scale
                else if axis = 1 then positions.y.(point) /. coordinate_scale
                else positions.z.(point) /. coordinate_scale in
              let ax = coord p0 0 and ay = coord p0 1 and az = coord p0 2
              and bx = coord p1 0 and by = coord p1 1 and bz = coord p1 2
              and cx = coord p2 0 and cy = coord p2 1 and cz = coord p2 2 in
              let ux = bx -. ax and uy = by -. ay and uz = bz -. az
              and vx = cx -. ax and vy = cy -. ay and vz = cz -. az in
              let scale = Float.max (abs_float ux)
                  (Float.max (abs_float uy) (Float.max (abs_float uz)
                    (Float.max (abs_float vx)
                      (Float.max (abs_float vy) (abs_float vz))))) in
              if Bytes.unsafe_get face_valid primitive = '\000' then
                valid := false
              else
                  let onx = face_a.(primitive) and ony = face_b.(primitive)
                  and onz = face_c.(primitive) in
                  if scale = 0. || not (finite scale) then valid := false
                  else
                    let ux = ux /. scale and uy = uy /. scale and uz = uz /. scale
                    and vx = vx /. scale and vy = vy /. scale and vz = vz /. scale in
                    let nx = (uy *. vz) -. (uz *. vy)
                    and ny = (uz *. vx) -. (ux *. vz)
                    and nz = (ux *. vy) -. (uy *. vx) in
                    let length = sqrt
                        ((nx *. nx) +. (ny *. ny) +. (nz *. nz)) in
                    if length = 0. || not (finite length)
                       || ((onx *. nx) +. (ony *. ny) +. (onz *. nz))
                          /. length < cosine then valid := false
            end
          end
        done in
      inspect_point a; inspect_point b; !valid in
    let selected = Bytes.make ((edge_count + 7) / 8) '\000'
    and reserved = scratch.reserved
    and removed = ref 0 in
    Bytes.fill reserved 0 point_count '\000';
    let reserve point =
      Bytes.unsafe_set reserved point '\001';
      for slot = index.point_edge_offsets.(point)
          to index.point_edge_offsets.(point + 1) - 1 do
        let edge = index.point_edges.(slot) in
        Bytes.unsafe_set reserved index.edge_a.(edge) '\001';
        Bytes.unsafe_set reserved index.edge_b.(edge) '\001'
      done in
    let ordinal = ref 0 in
    while !ordinal < edge_count && !removed < primitive_budget do
      if !ordinal land 4095 = 0 then Cancel.check_opt cancel;
      let edge = order.(!ordinal) in
      let a = index.edge_a.(edge) and b = index.edge_b.(edge)
      and reduction = incidence.(edge) in
      if finite costs.(edge) && Bytes.unsafe_get reserved a = '\000'
          && Bytes.unsafe_get reserved b = '\000'
          && (reduction <= primitive_budget - !removed || !removed = 0)
          && link_valid edge && normal_valid edge then begin
        let byte = edge lsr 3 and bit = 1 lsl (edge land 7) in
        Bytes.unsafe_set selected byte
          (Char.chr (Char.code (Bytes.unsafe_get selected byte) lor bit));
        removed := !removed + reduction;
        reserve a; reserve b
      end;
      incr ordinal
    done;
    let edges = Edge_group.Private.of_owned_bits ~topology ~edge_count
        ~name:"__pdk_poly_reduce_round" selected in
    Ok { edges; removed_primitives = !removed }
  with
  | Invalid message | Invalid_argument message -> Error message
