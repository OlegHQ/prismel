open Prismel

type minimize = Two_point_distance | Three_point_distance

type output = Triangles | Polygons

exception Invalid of string

let fail message = raise (Invalid message)
let get_ok = function Ok value -> value | Error message -> fail message

type section = {
  primitive : int;
  first : int;
  count : int;
  closed : bool;
  indices : int array option;
}

type alignment = {
  a_shift : int;
  a_reverse : bool;
  b_shift : int;
  b_reverse : bool;
}

type plan = {
  corners : int array;
  arity : int;
  count : int;
  corner_count : int;
  source_primitive : int;
}

let checked_add label left right =
  if right < 0 || left > max_int - right then fail (label ^ " exceeds array limits");
  left + right

let checked_mul label left right =
  if left < 0 || right < 0 || (left <> 0 && right > max_int / left) then
    fail (label ^ " exceeds array limits");
  left * right

let[@inline always] robust_length x y z =
  let scale = Float.max (abs_float x)
      (Float.max (abs_float y) (abs_float z)) in
  if scale = 0. then 0.
  else if not (Float.is_finite scale) then Float.nan
  else
    let x = x /. scale and y = y /. scale and z = z /. scale in
    scale *. sqrt ((x *. x) +. (y *. y) +. (z *. z))

let[@inline always] distance positions a b =
  robust_length
    (positions.Packed.Float3.Private.x.(a) -. positions.x.(b))
    (positions.y.(a) -. positions.y.(b))
    (positions.z.(a) -. positions.z.(b))

let[@inline always] distance_le positions a b c d =
  let ax = positions.Packed.Float3.Private.x.(a) -. positions.x.(b)
  and ay = positions.y.(a) -. positions.y.(b)
  and az = positions.z.(a) -. positions.z.(b)
  and bx = positions.x.(c) -. positions.x.(d)
  and by = positions.y.(c) -. positions.y.(d)
  and bz = positions.z.(c) -. positions.z.(d) in
  let ascale = Float.max (abs_float ax)
      (Float.max (abs_float ay) (abs_float az))
  and bscale = Float.max (abs_float bx)
      (Float.max (abs_float by) (abs_float bz)) in
  if ascale = 0. then true
  else if bscale = 0. then false
  else begin
    let anx = ax /. ascale and any = ay /. ascale and anz = az /. ascale
    and bnx = bx /. bscale and bny = by /. bscale and bnz = bz /. bscale in
    let alength = sqrt ((anx *. anx) +. (any *. any) +. (anz *. anz))
    and blength = sqrt ((bnx *. bnx) +. (bny *. bny) +. (bnz *. bnz)) in
    if ascale <= bscale then (ascale /. bscale) *. alength <= blength
    else alength <= (bscale /. ascale) *. blength
  end

let[@inline always] safe_sum left right =
  let value = left +. right in
  if Float.is_finite value then value else max_float

let[@inline always] source_vertex (section : section) alignment_shift reverse local =
  let local = if reverse then
      (alignment_shift - local + section.count) mod section.count
    else (alignment_shift + local) mod section.count in
  match section.indices with
  | None -> section.first + local
  | Some indices -> indices.(local)

let[@inline always] point topology vertex =
  topology.Topology.Private.vertex_points.(vertex)

let endpoint_alignment positions topology (a : section) (b : section) =
  let av first = point topology (a.first + if first then 0 else a.count - 1)
  and bv first = point topology (b.first + if first then 0 else b.count - 1) in
  let candidates = [|
    distance positions (av true) (bv true), false, false;
    distance positions (av true) (bv false), false, true;
    distance positions (av false) (bv true), true, false;
    distance positions (av false) (bv false), true, true;
  |] in
  let best = ref 0 in
  for index = 1 to 3 do
    if let cost, _, _ = candidates.(index)
       and best_cost, _, _ = candidates.(!best) in cost < best_cost then
      best := index
  done;
  let _, a_reverse, b_reverse = candidates.(!best) in
  { a_shift = (if a_reverse then a.count - 1 else 0); a_reverse;
    b_shift = (if b_reverse then b.count - 1 else 0); b_reverse }

let closed_alignment ?cancel positions topology (a : section) (b : section) =
  let product = checked_mul "closest-end search" a.count b.count in
  let best_a = ref 0 and best_b = ref 0 and best_distance = ref infinity in
  if product <= 16_384 then begin
    for ai = 0 to a.count - 1 do
      if ai land 255 = 0 then Cancel.check_opt cancel;
      let ap = point topology (a.first + ai) in
      for bi = 0 to b.count - 1 do
        let bp = point topology (b.first + bi) in
        let candidate = distance positions ap bp in
        if candidate < !best_distance then begin
          best_distance := candidate; best_a := ai; best_b := bi
        end
      done
    done
  end else begin
    let x = Array.make b.count 0. and y = Array.make b.count 0.
    and z = Array.make b.count 0. in
    for bi = 0 to b.count - 1 do
      let bp = point topology (b.first + bi) in
      x.(bi) <- positions.Packed.Float3.Private.x.(bp);
      y.(bi) <- positions.y.(bp); z.(bi) <- positions.z.(bp)
    done;
    let packed = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
    let index = match Spatial_index.create ?cancel packed with
      | Ok value -> value
      | Error error -> fail (Error.to_string error) in
    let indices = Array.make 1 0 and distances = Array.make 1 0. in
    for ai = 0 to a.count - 1 do
      if ai land 255 = 0 then Cancel.check_opt cancel;
      let ap = point topology (a.first + ai) in
      let found = Spatial_index.Private.nearest_k_into index
          ~x:positions.x.(ap) ~y:positions.y.(ap) ~z:positions.z.(ap)
          ~max_distance_squared:infinity ~indices ~distances_squared:distances
          ~offset:0 ~count:1 in
      if found = 1 then begin
        let candidate = sqrt distances.(0) and bi = indices.(0) in
        if candidate < !best_distance
            || (candidate = !best_distance
                && (ai < !best_a || (ai = !best_a && bi < !best_b))) then begin
          best_distance := candidate; best_a := ai; best_b := bi
        end
      end
    done
  end;
  let a_next = point topology (a.first + ((!best_a + 1) mod a.count))
  and b_next = point topology (b.first + ((!best_b + 1) mod b.count))
  and b_previous = point topology
      (b.first + ((!best_b + b.count - 1) mod b.count)) in
  let reverse = distance positions a_next b_previous
      < distance positions a_next b_next in
  { a_shift = !best_a; a_reverse = false;
    b_shift = !best_b; b_reverse = reverse }

let alignment ?cancel ~connect_closest positions topology a b closed =
  if not connect_closest then
    { a_shift = 0; a_reverse = false; b_shift = 0; b_reverse = false }
  else if closed then closed_alignment ?cancel positions topology a b
  else endpoint_alignment positions topology a b

let[@inline always] non_collinear ~tolerance positions topology av bv cv =
  let a = point topology av and b = point topology bv and c = point topology cv in
  if a = b || b = c || c = a then false
  else begin
    let ux = positions.Packed.Float3.Private.x.(b) -. positions.x.(a)
    and uy = positions.y.(b) -. positions.y.(a)
    and uz = positions.z.(b) -. positions.z.(a)
    and vx = positions.x.(c) -. positions.x.(a)
    and vy = positions.y.(c) -. positions.y.(a)
    and vz = positions.z.(c) -. positions.z.(a) in
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

let build_plan ?cancel ~connect_closest ~minimize ~tolerance
    ?(pairing_shift = 0) positions topology a b ~closed =
  let alignment = alignment ?cancel ~connect_closest positions topology a b closed in
  let pairing_shift = pairing_shift mod b.count in
  let pairing_shift = if pairing_shift < 0 then pairing_shift + b.count
      else pairing_shift in
  let alignment = { alignment with
    b_shift = (alignment.b_shift + pairing_shift) mod b.count } in
  let a_steps = if closed then a.count else a.count - 1
  and b_steps = if closed then b.count else b.count - 1 in
  let maximum = checked_add "triangle count" a_steps b_steps in
  let triangles = Array.make (checked_mul "triangle corner count" maximum 3) 0 in
  let ai = ref 0 and bi = ref 0 and count = ref 0 in
  let vertex section shift reverse local =
    source_vertex section shift reverse local in
  let emit x y z =
    let distinct = point topology x <> point topology y
        && point topology y <> point topology z
        && point topology z <> point topology x in
    if distinct && (tolerance = 0.
        || non_collinear ~tolerance positions topology x y z) then begin
      let at = !count * 3 in
      triangles.(at) <- x; triangles.(at + 1) <- y; triangles.(at + 2) <- z;
      incr count
    end in
  while !ai < a_steps || !bi < b_steps do
    if (!ai + !bi) land 4095 = 0 then Cancel.check_opt cancel;
    let av = vertex a alignment.a_shift alignment.a_reverse !ai
    and bv = vertex b alignment.b_shift alignment.b_reverse !bi in
    let can_a = !ai < a_steps and can_b = !bi < b_steps in
    let advance_a = if not can_b then true else if not can_a then false else begin
      let an = vertex a alignment.a_shift alignment.a_reverse (!ai + 1)
      and bn = vertex b alignment.b_shift alignment.b_reverse (!bi + 1) in
      match minimize with
      | Two_point_distance -> distance_le positions
          (point topology an) (point topology bv)
          (point topology av) (point topology bn)
      | Three_point_distance ->
          let two_a = distance positions (point topology an) (point topology bv)
          and two_b = distance positions (point topology av) (point topology bn) in
          let edge_a = distance positions (point topology av) (point topology an)
          and edge_b = distance positions (point topology bv) (point topology bn) in
          safe_sum two_a edge_a <= safe_sum two_b edge_b
    end in
    if advance_a then begin
      let an = vertex a alignment.a_shift alignment.a_reverse (!ai + 1) in
      emit av an bv; incr ai
    end else begin
      let bn = vertex b alignment.b_shift alignment.b_reverse (!bi + 1) in
      emit av bn bv; incr bi
    end
  done;
  { corners = triangles; arity = 3; count = !count;
    corner_count = checked_mul "triangle corner count" !count 3;
    source_primitive = a.primitive }

let build_polygon_plan ?cancel ~connect_closest ~minimize ~tolerance positions
    ?(pairing_shift = 0) topology (a : section) (b : section) ~closed =
  if a.count <> b.count then
    build_plan ?cancel ~connect_closest ~minimize ~tolerance ~pairing_shift
      positions topology a b ~closed
  else begin
    let alignment = alignment ?cancel ~connect_closest positions topology a b closed in
    let pairing_shift = pairing_shift mod b.count in
    let pairing_shift = if pairing_shift < 0 then pairing_shift + b.count
        else pairing_shift in
    let alignment = { alignment with
      b_shift = (alignment.b_shift + pairing_shift) mod b.count } in
    let count = if closed then a.count else a.count - 1 in
    let corners = Array.make (checked_mul "skin corner count" count 4) 0 in
    let output = ref 0 in
    for local = 0 to count - 1 do
      if local land 4095 = 0 then Cancel.check_opt cancel;
      let av = source_vertex a alignment.a_shift alignment.a_reverse local
      and an = source_vertex a alignment.a_shift alignment.a_reverse (local + 1)
      and bv = source_vertex b alignment.b_shift alignment.b_reverse local
      and bn = source_vertex b alignment.b_shift alignment.b_reverse (local + 1) in
      let ap = point topology av and anp = point topology an
      and bp = point topology bv and bnp = point topology bn in
      let distinct =
        let unique = ref 1 in
        if anp <> ap then incr unique;
        if bp <> ap && bp <> anp then incr unique;
        if bnp <> ap && bnp <> anp && bnp <> bp then incr unique;
        !unique >= 3 in
      let non_collinear = tolerance = 0.
          || non_collinear ~tolerance positions topology av an bn
          || non_collinear ~tolerance positions topology av bn bv in
      if distinct && non_collinear then begin
        let target = !output * 4 in
        corners.(target) <- av; corners.(target + 1) <- an;
        corners.(target + 2) <- bn; corners.(target + 3) <- bv;
        incr output
      end
    done;
    { corners; arity = 4; count = !output;
      corner_count = checked_mul "skin corner count" !output 4;
      source_primitive = a.primitive }
  end

let run ?cancel ?(grain = 16_384) ?primitives ?rest
    ?(connect_closest_ends = true) ?(minimize = Two_point_distance)
    ?(u_wrap = false) ?(v_wrap = false) ?(keep_primitives = false)
    ?output_group ?(collinearity_tolerance = 0.)
    ?(recompute_normals = true) ?(output = Triangles)
    ?(operation = "poly_loft") geometry =
  try
    if grain <= 0 then fail "grain must be positive";
    if not (Float.is_finite collinearity_tolerance)
        || collinearity_tolerance < 0. || collinearity_tolerance > 1. then
      fail "collinearity tolerance must be finite and between zero and one";
    (match output_group with
     | Some name when String.trim name = "" -> fail "output group name is empty"
     | _ -> ());
    Cancel.check_opt cancel;
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value
    and primitive_count = Geometry.primitive_count geometry in
    (match primitives with
     | Some group when Group.owner group <> Group.Primitive ->
         fail "selection must be primitive-owned"
     | Some group when Group.length group <> primitive_count ->
         fail "selection length does not match geometry"
     | _ -> ());
    let selected primitive = match primitives with
      | None -> true | Some group -> Group.mem primitive group in
    let section_count = ref 0 in
    for primitive = 0 to primitive_count - 1 do
      if primitive land 4095 = 0 then Cancel.check_opt cancel;
      if selected primitive then begin
        let count = topology.primitive_offsets.(primitive + 1)
            - topology.primitive_offsets.(primitive) in
        (match Topology.primitive_kind topology_value primitive with
         | Topology.Open_polyline when count >= 2 -> incr section_count
         | Topology.Closed_polyline | Topology.Polygon when count >= 3 ->
             incr section_count
         | Topology.Open_polyline -> fail (Printf.sprintf
             "selected open curve %d has fewer than two vertices" primitive)
         | Topology.Closed_polyline | Topology.Polygon -> fail (Printf.sprintf
             "selected closed section %d has fewer than three vertices" primitive))
      end
    done;
    if !section_count < 2 then Ok geometry else begin
      let sections = Array.make !section_count
          { primitive = 0; first = 0; count = 2; closed = false;
            indices = None } in
      let at = ref 0 in
      for primitive = 0 to primitive_count - 1 do
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        if selected primitive then begin
          let first = topology.primitive_offsets.(primitive)
          and last = topology.primitive_offsets.(primitive + 1) in
          sections.(!at) <- { primitive; first; count = last - first;
            closed = u_wrap || Topology.primitive_kind topology_value primitive
                <> Topology.Open_polyline; indices = None };
          incr at
        end
      done;
      let guide = match rest with
        | None -> geometry
        | Some value when Geometry.point_count value <> Geometry.point_count geometry ->
            fail "rest geometry point count does not match input"
        | Some value -> value in
      let positions = Packed.Float3.Private.view (Geometry.positions guide) in
      Array.iter (fun (section : section) ->
        for local = 0 to section.count - 1 do
          if local land 4095 = 0 then Cancel.check_opt cancel;
          let source = point topology (section.first + local) in
          if not (Float.is_finite positions.x.(source)
              && Float.is_finite positions.y.(source)
              && Float.is_finite positions.z.(source)) then fail (Printf.sprintf
            "guide point %d is not finite" source)
        done) sections;
      let pair_count = !section_count - 1
          + if v_wrap && !section_count > 2 then 1 else 0 in
      let dummy = { corners = [||]; arity = 3; count = 0; corner_count = 0;
        source_primitive = 0 } in
      let plans = Array.make pair_count dummy in
      Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(pair_count - 1) (fun pair ->
        Cancel.check_opt cancel;
        let next = if pair + 1 < !section_count then pair + 1 else 0 in
        let a = sections.(pair) and b = sections.(next) in
        let closed = a.closed && b.closed in
        plans.(pair) <- match output with
          | Triangles -> build_plan ?cancel
              ~connect_closest:connect_closest_ends ~minimize
              ~tolerance:collinearity_tolerance positions topology a b ~closed
          | Polygons -> build_polygon_plan ?cancel
              ~connect_closest:connect_closest_ends ~minimize
              ~tolerance:collinearity_tolerance positions topology a b ~closed);
      let generated_count = Array.fold_left (fun total plan ->
          checked_add "generated primitive count" total plan.count) 0 plans in
      if generated_count = 0 && keep_primitives && output_group = None then
        Ok geometry
      else begin
        let keep primitive = keep_primitives || not (selected primitive) in
        let source_to_output = Array.make primitive_count (-1)
        and kept_vertex_offsets = Array.make (primitive_count + 1) 0 in
        let kept_count = ref 0 in
        for primitive = 0 to primitive_count - 1 do
          if primitive land 4095 = 0 then Cancel.check_opt cancel;
          kept_vertex_offsets.(primitive + 1) <- kept_vertex_offsets.(primitive);
          if keep primitive then begin
            source_to_output.(primitive) <- !kept_count; incr kept_count;
            kept_vertex_offsets.(primitive + 1) <- checked_add "kept vertex count"
                kept_vertex_offsets.(primitive)
                (topology.primitive_offsets.(primitive + 1)
                 - topology.primitive_offsets.(primitive))
          end
        done;
        let kept_vertices = kept_vertex_offsets.(primitive_count)
        and generated_vertices = Array.fold_left (fun total plan ->
            checked_add "generated vertex count" total plan.corner_count) 0 plans in
        let output_primitives = checked_add "output primitive count"
            !kept_count generated_count
        and output_vertices = checked_add "output vertex count"
            kept_vertices generated_vertices in
        let primitive_offsets = Array.make (output_primitives + 1) 0
        and primitive_kinds = Array.make output_primitives Topology.Polygon
        and vertex_points = Array.make output_vertices 0
        and vertex_map = Array.make output_vertices 0
        and primitive_map = Array.make output_primitives 0 in
        for primitive = 0 to primitive_count - 1 do
          let output = source_to_output.(primitive) in
          if output >= 0 then begin
            primitive_offsets.(output) <- kept_vertex_offsets.(primitive);
            primitive_kinds.(output) <- Topology.primitive_kind topology_value primitive;
            primitive_map.(output) <- primitive
          end
        done;
        let plan_offsets = Array.make (pair_count + 1) 0 in
        for pair = 0 to pair_count - 1 do
          if pair land 4095 = 0 then Cancel.check_opt cancel;
          plan_offsets.(pair + 1) <- checked_add "plan primitive offset"
              plan_offsets.(pair) plans.(pair).count
        done;
        let generated_at = ref kept_vertices in
        for pair = 0 to pair_count - 1 do
          let plan = plans.(pair) in
          for local = 0 to plan.count - 1 do
            let primitive = !kept_count + plan_offsets.(pair) + local in
            primitive_offsets.(primitive) <- !generated_at;
            generated_at := checked_add "generated vertex offset" !generated_at
                plan.arity
          done
        done;
        primitive_offsets.(output_primitives) <- output_vertices;
        let source_vertices = topology.vertex_points in
        if primitive_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(primitive_count - 1) (fun primitive ->
          if primitive land 1023 = 0 then Cancel.check_opt cancel;
          let output = source_to_output.(primitive) in
          if output >= 0 then begin
            let source_first = topology.primitive_offsets.(primitive)
            and source_last = topology.primitive_offsets.(primitive + 1)
            and target_first = kept_vertex_offsets.(primitive) in
            for local = 0 to source_last - source_first - 1 do
              let source = source_first + local and target = target_first + local in
              vertex_points.(target) <- source_vertices.(source);
              vertex_map.(target) <- source
            done
          end);
        Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(pair_count - 1) (fun pair ->
          Cancel.check_opt cancel;
          let plan = plans.(pair)
          and primitive_first = !kept_count + plan_offsets.(pair) in
          let source_at = ref 0 in
          for local = 0 to plan.count - 1 do
            let primitive = primitive_first + local in
            let target_at = primitive_offsets.(primitive) in
            primitive_map.(primitive) <- plan.source_primitive;
            let size = primitive_offsets.(primitive + 1) - target_at in
            for corner = 0 to size - 1 do
              let source_vertex = plan.corners.(!source_at + corner) in
              vertex_map.(target_at + corner) <- source_vertex;
              vertex_points.(target_at + corner) <- source_vertices.(source_vertex)
            done;
            source_at := !source_at + size
          done);
        let output_topology = Topology.create_owned ~point_count:topology.point_count
            ~vertex_points ~primitive_offsets ~primitive_kinds |> get_ok in
        let output = Topology_remap.preserving_points ?cancel ~grain
            ~topology:output_topology ~vertex_map ~primitive_map geometry |> get_ok in
        let output = match output_group with
          | None -> output
          | Some name -> Geometry.with_group
              (Group.init ~grain ~owner:Group.Primitive ~name output_primitives
                (fun primitive -> primitive >= !kept_count)) output |> get_ok in
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
  with Invalid message -> Error ("Pdk.Ops." ^ operation ^ ": " ^ message)

module Private = struct
  type nonrec plan = plan

  let build_polygon_plan_indexed ?cancel ~connect_closest ~minimize ~tolerance
      positions topology ~a_vertices ~a_primitive ~a_closed
      ~b_vertices ~b_primitive ~b_closed ~pairing_shift =
    let a = { primitive = a_primitive; first = 0;
      count = Array.length a_vertices; closed = a_closed;
      indices = Some a_vertices }
    and b = { primitive = b_primitive; first = 0;
      count = Array.length b_vertices; closed = b_closed;
      indices = Some b_vertices } in
    build_polygon_plan ?cancel ~connect_closest ~minimize ~tolerance
      ~pairing_shift positions topology a b ~closed:(a_closed && b_closed)

  let align_indexed ?cancel ~connect_closest positions topology
      ~a_vertices ~a_primitive ~a_closed ~b_vertices ~b_primitive ~b_closed
      ~pairing_shift =
    let a = { primitive = a_primitive; first = 0;
      count = Array.length a_vertices; closed = a_closed;
      indices = Some a_vertices }
    and b = { primitive = b_primitive; first = 0;
      count = Array.length b_vertices; closed = b_closed;
      indices = Some b_vertices } in
    let closed = a_closed && b_closed in
    let aligned = alignment ?cancel ~connect_closest positions topology a b closed in
    let pairing_shift = pairing_shift mod b.count in
    let pairing_shift = if pairing_shift < 0 then pairing_shift + b.count
        else pairing_shift in
    let aligned = { aligned with
      b_shift = (aligned.b_shift + pairing_shift) mod b.count } in
    Array.init a.count (source_vertex a aligned.a_shift aligned.a_reverse),
    Array.init b.count (source_vertex b aligned.b_shift aligned.b_reverse)

  let corners plan = plan.corners
  let arity plan = plan.arity
  let primitive_count plan = plan.count
  let corner_count plan = plan.corner_count
  let source_primitive plan = plan.source_primitive
end
