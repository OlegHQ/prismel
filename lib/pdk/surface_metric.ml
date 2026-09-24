open Prismel

type t = {
  point_count : int;
  scale : float;
  scaled_x : float array;
  scaled_y : float array;
  scaled_z : float array;
  triangle_a : int array;
  triangle_b : int array;
  triangle_c : int array;
  double_area : float array;
  cotangent_a : float array;
  cotangent_b : float array;
  cotangent_c : float array;
  point_offsets : int array;
  incidence : int array;
  boundary_points : bytes;
  topology_index : Topology_index.Private.view;
}

exception Surface_metric_error of string
let fail message = raise (Surface_metric_error message)

let ceiling_div value divisor =
  (value / divisor) + if value mod divisor = 0 then 0 else 1

let triangulate ?cancel ~grain ~positions ~topology () =
  let primitive_count = Bytes.length topology.Topology.Private.primitive_kinds in
  let offsets = Array.make (primitive_count + 1) 0 in
  for primitive = 0 to primitive_count - 1 do
    if primitive land 4095 = 0 then Cancel.check_opt cancel;
    let size = topology.primitive_offsets.(primitive + 1)
        - topology.primitive_offsets.(primitive) in
    if size - 2 > Sys.max_array_length - offsets.(primitive) then
      fail "triangulated surface exceeds array limits";
    offsets.(primitive + 1) <- offsets.(primitive) + size - 2
  done;
  let triangle_count = offsets.(primitive_count) in
  if triangle_count > Sys.max_array_length / 3 then
    fail "surface triangle incidence exceeds array limits";
  let triangle_a = Array.make triangle_count 0
  and triangle_b = Array.make triangle_count 0
  and triangle_c = Array.make triangle_count 0 in
  let average = if primitive_count = 0 then 1
    else max 1 (ceiling_div triangle_count primitive_count) in
  let primitive_chunk = max 1 (grain / average) in
  let range_count = ceiling_div primitive_count primitive_chunk in
  let errors = Array.make range_count None in
  if range_count > 0 then
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1) (fun range ->
      let first = range * primitive_chunk
      and last = min primitive_count ((range + 1) * primitive_chunk) in
      let scratch = Polygon_triangulation.create_scratch () in
      for primitive = first to last - 1 do
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        if errors.(range) = None then begin
          let output = offsets.(primitive) in
          let emit local a b c =
            let triangle = output + local in
            triangle_a.(triangle) <- topology.vertex_points.(a);
            triangle_b.(triangle) <- topology.vertex_points.(b);
            triangle_c.(triangle) <- topology.vertex_points.(c) in
          match Polygon_triangulation.primitive ?cancel ~positions ~topology
              ~scratch primitive ~emit with
          | Ok () -> ()
          | Error message -> errors.(range) <- Some message
        end
      done);
  Array.iter (function None -> () | Some message -> fail message) errors;
  triangle_a,triangle_b,triangle_c

let create ?cancel ?(grain = 16_384) geometry =
  try
    if grain <= 0 then fail "surface metric grain must be positive";
    Cancel.check_opt cancel;
    let point_count = Geometry.point_count geometry in
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value in
    let index_value = Topology_index.create ?cancel topology_value in
    let topology_index = Topology_index.Private.view index_value in
    let boundary_points = match
        Topology_index.Private.polygon_manifold_boundary_points ?cancel
          ~topology:topology_value index_value with
      | Ok boundary -> boundary
      | Error message -> fail message in
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    let coordinate_scale = [|0.|] in
    for point = 0 to point_count - 1 do
      if point land 16_383 = 0 then Cancel.check_opt cancel;
      let x = positions.x.(point) and y = positions.y.(point)
      and z = positions.z.(point) in
      if not (Float.is_finite x && Float.is_finite y && Float.is_finite z) then
        fail "surface positions must be finite";
      let x = abs_float x and y = abs_float y and z = abs_float z in
      if x > coordinate_scale.(0) then coordinate_scale.(0) <- x;
      if y > coordinate_scale.(0) then coordinate_scale.(0) <- y;
      if z > coordinate_scale.(0) then coordinate_scale.(0) <- z
    done;
    let triangle_a,triangle_b,triangle_c =
      triangulate ?cancel ~grain ~positions ~topology () in
    let triangle_count = Array.length triangle_a in
    if triangle_count > 0 && coordinate_scale.(0) = 0. then
      fail "surface triangles are metrically degenerate";
    let scale = if coordinate_scale.(0) = 0. then 1. else coordinate_scale.(0) in
    let scaled_x = Array.make point_count 0.
    and scaled_y = Array.make point_count 0.
    and scaled_z = Array.make point_count 0. in
    if point_count > 0 then
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
        (fun point ->
          if point land 16_383 = 0 then Cancel.check_opt cancel;
          scaled_x.(point) <- positions.x.(point) /. scale;
          scaled_y.(point) <- positions.y.(point) /. scale;
          scaled_z.(point) <- positions.z.(point) /. scale);
    let double_area = Array.make triangle_count 0.
    and cotangent_a = Array.make triangle_count 0.
    and cotangent_b = Array.make triangle_count 0.
    and cotangent_c = Array.make triangle_count 0. in
    let invalid_triangle = Atomic.make false in
    if triangle_count > 0 then
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(triangle_count - 1)
        (fun triangle ->
          if triangle land 16_383 = 0 then Cancel.check_opt cancel;
          let a = triangle_a.(triangle) and b = triangle_b.(triangle)
          and c = triangle_c.(triangle) in
          let ux = scaled_x.(b) -. scaled_x.(a)
          and uy = scaled_y.(b) -. scaled_y.(a)
          and uz = scaled_z.(b) -. scaled_z.(a)
          and vx = scaled_x.(c) -. scaled_x.(a)
          and vy = scaled_y.(c) -. scaled_y.(a)
          and vz = scaled_z.(c) -. scaled_z.(a) in
          let cx = (uy *. vz) -. (uz *. vy)
          and cy = (uz *. vx) -. (ux *. vz)
          and cz = (ux *. vy) -. (uy *. vx) in
          let area = Float.hypot cx (Float.hypot cy cz)
          and uv = (ux *. vx) +. (uy *. vy) +. (uz *. vz)
          and uu = (ux *. ux) +. (uy *. uy) +. (uz *. uz)
          and vv = (vx *. vx) +. (vy *. vy) +. (vz *. vz) in
          if not (Float.is_finite area && area > 0. && Float.is_finite uv
              && Float.is_finite uu && Float.is_finite vv) then
            Atomic.set invalid_triangle true
          else begin
            let ca = uv /. area
            and cb = (uu -. uv) /. area
            and cc = (vv -. uv) /. area in
            if not (Float.is_finite ca && Float.is_finite cb
                && Float.is_finite cc) then Atomic.set invalid_triangle true
            else begin
              double_area.(triangle) <- area;
              cotangent_a.(triangle) <- ca;
              cotangent_b.(triangle) <- cb;
              cotangent_c.(triangle) <- cc
            end
          end);
    if Atomic.get invalid_triangle then
      fail "surface contains a degenerate or numerically unrepresentable triangle";
    let incidence_count = triangle_count * 3 in
    let point_offsets = Array.make (point_count + 1) 0 in
    for triangle = 0 to triangle_count - 1 do
      point_offsets.(triangle_a.(triangle) + 1) <-
        point_offsets.(triangle_a.(triangle) + 1) + 1;
      point_offsets.(triangle_b.(triangle) + 1) <-
        point_offsets.(triangle_b.(triangle) + 1) + 1;
      point_offsets.(triangle_c.(triangle) + 1) <-
        point_offsets.(triangle_c.(triangle) + 1) + 1
    done;
    for point = 0 to point_count - 1 do
      point_offsets.(point + 1) <- point_offsets.(point + 1)
          + point_offsets.(point)
    done;
    let incidence = Array.make incidence_count 0
    and cursor = Array.copy point_offsets in
    let add point encoded =
      let output = cursor.(point) in
      incidence.(output) <- encoded;
      cursor.(point) <- output + 1 in
    for triangle = 0 to triangle_count - 1 do
      add triangle_a.(triangle) (triangle * 3);
      add triangle_b.(triangle) ((triangle * 3) + 1);
      add triangle_c.(triangle) ((triangle * 3) + 2)
    done;
    Ok {point_count;scale;scaled_x;scaled_y;scaled_z;triangle_a;triangle_b;
      triangle_c;double_area;cotangent_a;cotangent_b;cotangent_c;point_offsets;
      incidence;boundary_points;topology_index}
  with Surface_metric_error message -> Error message

let[@inline] mixed_area_contribution ~double_area ~cotangent_a ~cotangent_b
    ~cotangent_c ~corner_cotangent ~edge_a_squared ~edge_b_squared
    ~cotangent_neighbor_a ~cotangent_neighbor_b =
  if cotangent_a < 0. || cotangent_b < 0. || cotangent_c < 0. then
    double_area /. (if corner_cotangent < 0. then 4. else 8.)
  else ((edge_a_squared *. cotangent_neighbor_b)
      +. (edge_b_squared *. cotangent_neighbor_a)) /. 8.
