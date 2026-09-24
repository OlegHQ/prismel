open Prismel

type boundary = Curvature_boundary_zero | Curvature_boundary_one_sided

type outputs = {
  mean : string option;
  gaussian : string option;
  minimum : string option;
  maximum : string option;
  curvedness : string option;
  shape_index : string option;
}

let default_outputs = {
  mean = Some "curvature";
  gaussian = None;
  minimum = None;
  maximum = None;
  curvedness = None;
  shape_index = None;
}

exception Curvature_error of string
let fail message = raise (Curvature_error message)

let finite = Float.is_finite

let validate_outputs outputs =
  let named = [
    "mean", outputs.mean;
    "gaussian", outputs.gaussian;
    "minimum", outputs.minimum;
    "maximum", outputs.maximum;
    "curvedness", outputs.curvedness;
    "shape index", outputs.shape_index;
  ] in
  let names = List.filter_map (fun (label, name) -> match name with
    | None -> None
    | Some name ->
        if String.trim name = "" then
          fail (label ^ " curvature attribute name must not be empty");
        if String.equal name "P" then
          fail "curvature output cannot replace canonical point position P";
        Some name) named in
  if names = [] then fail "at least one curvature output must be enabled";
  let sorted = Array.of_list names in
  Array.sort String.compare sorted;
  for index = 1 to Array.length sorted - 1 do
    if String.equal sorted.(index - 1) sorted.(index) then
      fail (Printf.sprintf "curvature output name %S is used more than once"
          sorted.(index))
  done

let existing_float name point_count geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Array.make point_count 0.
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values when Array.length values = point_count ->
           Array.copy values
       | Attribute.Float _ ->
           fail (Printf.sprintf "point curvature attribute %S has wrong cardinality"
               name)
       | _ -> fail (Printf.sprintf
           "point curvature attribute %S exists with non-float storage" name))

let run ?cancel ?(grain = 16_384) ?points
    ?(boundary = Curvature_boundary_zero) ?(smoothing_iterations = 0)
    ?(smoothing_strength = 0.5) ?(outputs = default_outputs) geometry =
  try
    if grain <= 0 then fail "grain must be positive";
    if smoothing_iterations < 0 then
      fail "smoothing iteration count must be non-negative";
    if not (finite smoothing_strength && smoothing_strength >= 0.
        && smoothing_strength <= 1.) then
      fail "smoothing strength must be finite and between zero and one";
    validate_outputs outputs;
    let principal_requested = Option.is_some outputs.minimum
        || Option.is_some outputs.maximum || Option.is_some outputs.curvedness
        || Option.is_some outputs.shape_index in
    let need_mean = Option.is_some outputs.mean || principal_requested
    and need_gaussian = Option.is_some outputs.gaussian || principal_requested in
    Cancel.check_opt cancel;
    let point_count = Geometry.point_count geometry in
    (match points with
     | Some group when Group.owner group <> Group.Point ->
         fail "selection must own points"
     | Some group when Group.length group <> point_count ->
         fail "point selection length does not match geometry"
     | None | Some _ -> ());
    let metric = match Surface_metric.create ?cancel ~grain geometry with
      | Ok metric -> metric
      | Error message -> fail message in
    let scale = metric.scale and scaled_x = metric.scaled_x
    and scaled_y = metric.scaled_y and scaled_z = metric.scaled_z
    and triangle_a = metric.triangle_a and triangle_b = metric.triangle_b
    and triangle_c = metric.triangle_c and double_area = metric.double_area
    and cotangent_a = metric.cotangent_a
    and cotangent_b = metric.cotangent_b
    and cotangent_c = metric.cotangent_c
    and point_offsets = metric.point_offsets and incidence = metric.incidence
    and boundary_points = metric.boundary_points
    and index = metric.topology_index in
    let mean = if need_mean then Array.make point_count 0. else [||]
    and gaussian = if need_gaussian then Array.make point_count 0. else [||]
    and area_sum = Array.make point_count 0.
    and angle_sum = if need_gaussian then Array.make point_count 0. else [||]
    and normal_x = if need_mean then Array.make point_count 0. else [||]
    and normal_y = if need_mean then Array.make point_count 0. else [||]
    and normal_z = if need_mean then Array.make point_count 0. else [||]
    and laplace_x = if need_mean then Array.make point_count 0. else [||]
    and laplace_y = if need_mean then Array.make point_count 0. else [||]
    and laplace_z = if need_mean then Array.make point_count 0. else [||] in
    let invalid_point = Atomic.make false in
    let compute point =
      if point land 4095 = 0 then Cancel.check_opt cancel;
      let first = point_offsets.(point) and last = point_offsets.(point + 1) in
      if first < last && not (boundary = Curvature_boundary_zero
          && Bytes.unsafe_get boundary_points point <> '\000') then begin
        for at = first to last - 1 do
          let encoded = incidence.(at) in
          let triangle = encoded / 3 and local = encoded mod 3 in
          let a = triangle_a.(triangle) and b = triangle_b.(triangle)
          and c = triangle_c.(triangle) in
          let neighbor_a = if local = 0 then b else if local = 1 then c else a
          and neighbor_b = if local = 0 then c else if local = 1 then a else b
          and cotangent = if local = 0 then cotangent_a.(triangle)
            else if local = 1 then cotangent_b.(triangle)
            else cotangent_c.(triangle)
          and cotangent_neighbor_a = if local = 0 then cotangent_b.(triangle)
            else if local = 1 then cotangent_c.(triangle)
            else cotangent_a.(triangle)
          and cotangent_neighbor_b = if local = 0 then cotangent_c.(triangle)
            else if local = 1 then cotangent_a.(triangle)
            else cotangent_b.(triangle) in
          let dax = scaled_x.(neighbor_a) -. scaled_x.(point)
          and day = scaled_y.(neighbor_a) -. scaled_y.(point)
          and daz = scaled_z.(neighbor_a) -. scaled_z.(point)
          and dbx = scaled_x.(neighbor_b) -. scaled_x.(point)
          and dby = scaled_y.(neighbor_b) -. scaled_y.(point)
          and dbz = scaled_z.(neighbor_b) -. scaled_z.(point) in
          let length_a_squared = (dax *. dax) +. (day *. day) +. (daz *. daz)
          and length_b_squared = (dbx *. dbx) +. (dby *. dby) +. (dbz *. dbz) in
          let mixed_area = Surface_metric.mixed_area_contribution
              ~double_area:double_area.(triangle)
              ~cotangent_a:cotangent_a.(triangle)
              ~cotangent_b:cotangent_b.(triangle)
              ~cotangent_c:cotangent_c.(triangle)
              ~corner_cotangent:cotangent ~edge_a_squared:length_a_squared
              ~edge_b_squared:length_b_squared ~cotangent_neighbor_a
              ~cotangent_neighbor_b in
          area_sum.(point) <- area_sum.(point) +. mixed_area;
          if need_gaussian then
            angle_sum.(point) <- angle_sum.(point) +. atan2 1. cotangent;
          if need_mean then begin
            laplace_x.(point) <- laplace_x.(point)
                -. (cotangent_neighbor_b *. dax)
                -. (cotangent_neighbor_a *. dbx);
            laplace_y.(point) <- laplace_y.(point)
                -. (cotangent_neighbor_b *. day)
                -. (cotangent_neighbor_a *. dby);
            laplace_z.(point) <- laplace_z.(point)
                -. (cotangent_neighbor_b *. daz)
                -. (cotangent_neighbor_a *. dbz);
            let ux = scaled_x.(b) -. scaled_x.(a)
            and uy = scaled_y.(b) -. scaled_y.(a)
            and uz = scaled_z.(b) -. scaled_z.(a)
            and vx = scaled_x.(c) -. scaled_x.(a)
            and vy = scaled_y.(c) -. scaled_y.(a)
            and vz = scaled_z.(c) -. scaled_z.(a) in
            normal_x.(point) <- normal_x.(point) +. ((uy *. vz) -. (uz *. vy));
            normal_y.(point) <- normal_y.(point) +. ((uz *. vx) -. (ux *. vz));
            normal_z.(point) <- normal_z.(point) +. ((ux *. vy) -. (uy *. vx))
          end
        done;
        if not (finite area_sum.(point) && area_sum.(point) > 0.) then
          Atomic.set invalid_point true
        else begin
          if need_mean then begin
            let normal_length = Float.hypot normal_x.(point)
                (Float.hypot normal_y.(point) normal_z.(point)) in
            if not (finite normal_length && normal_length > 0.) then
              Atomic.set invalid_point true
            else begin
              let dot =
                (laplace_x.(point) *. (normal_x.(point) /. normal_length))
                +. (laplace_y.(point) *. (normal_y.(point) /. normal_length))
                +. (laplace_z.(point) *. (normal_z.(point) /. normal_length)) in
              let value = (dot /. (4. *. area_sum.(point))) /. scale in
              if finite value then mean.(point) <- value
              else Atomic.set invalid_point true
            end
          end;
          if need_gaussian then begin
            let defect = (if Bytes.unsafe_get boundary_points point = '\000'
                then 2. *. Float.pi else Float.pi) -. angle_sum.(point) in
            let value = ((defect /. area_sum.(point)) /. scale) /. scale in
            if finite value then gaussian.(point) <- value
            else Atomic.set invalid_point true
          end
        end
      end in
    if point_count > 0 then
      Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1) compute;
    if Atomic.get invalid_point then
      fail "surface curvature is numerically unrepresentable at one or more points";
    let mean,gaussian =
      if smoothing_iterations = 0 || smoothing_strength = 0. then mean,gaussian
      else begin
        let current_mean = ref mean and current_gaussian = ref gaussian
        and next_mean = ref (if need_mean then Array.make point_count 0. else [||])
        and next_gaussian = ref
            (if need_gaussian then Array.make point_count 0. else [||]) in
        for iteration = 0 to smoothing_iterations - 1 do
          if iteration land 15 = 0 then Cancel.check_opt cancel;
          if point_count > 0 then
            Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
              (fun point ->
                if point land 4095 = 0 then Cancel.check_opt cancel;
                let locked = boundary = Curvature_boundary_zero
                    && Bytes.unsafe_get boundary_points point <> '\000' in
                let first = index.point_edge_offsets.(point)
                and last = index.point_edge_offsets.(point + 1) in
                if locked || first = last then begin
                  if need_mean then
                    (!next_mean).(point) <- (!current_mean).(point);
                  if need_gaussian then
                    (!next_gaussian).(point) <- (!current_gaussian).(point)
                end else begin
                  if need_mean then (!next_mean).(point) <- 0.;
                  if need_gaussian then (!next_gaussian).(point) <- 0.;
                  for at = first to last - 1 do
                    let edge = index.point_edges.(at) in
                    let neighbor = if index.edge_a.(edge) = point
                      then index.edge_b.(edge) else index.edge_a.(edge) in
                    if need_mean then
                      (!next_mean).(point) <- (!next_mean).(point)
                          +. (!current_mean).(neighbor);
                    if need_gaussian then
                      (!next_gaussian).(point) <- (!next_gaussian).(point)
                          +. (!current_gaussian).(neighbor)
                  done;
                  let inverse = 1. /. float_of_int (last - first) in
                  if need_mean then
                    (!next_mean).(point) <-
                      ((1. -. smoothing_strength) *. (!current_mean).(point))
                      +. (smoothing_strength *. (!next_mean).(point) *. inverse);
                  if need_gaussian then
                    (!next_gaussian).(point) <-
                      ((1. -. smoothing_strength) *. (!current_gaussian).(point))
                      +. (smoothing_strength *. (!next_gaussian).(point) *. inverse)
                end);
          let swap left right = let value = !left in left := !right; right := value in
          if need_mean then swap current_mean next_mean;
          if need_gaussian then swap current_gaussian next_gaussian
        done;
        !current_mean,!current_gaussian
      end in
    let selected point = match points with
      | None -> true | Some group -> Group.mem point group in
    let derived kind point = match kind with
      | `Mean -> mean.(point)
      | `Gaussian -> gaussian.(point)
      | (`Minimum | `Maximum | `Curvedness | `Shape_index) as kind ->
          let h = mean.(point) and k = gaussian.(point) in
          let discriminant = max 0. ((h *. h) -. k) in
          let delta = sqrt discriminant in
          let minimum = h -. delta and maximum = h +. delta in
          match kind with
          | `Minimum -> minimum
          | `Maximum -> maximum
          | `Curvedness ->
              sqrt (((minimum *. minimum) +. (maximum *. maximum)) *. 0.5)
          | `Shape_index ->
              if minimum = 0. && maximum = 0. then 0.
              else (2. /. Float.pi) *. atan2 (maximum +. minimum)
                  (maximum -. minimum)
          | `Mean | `Gaussian -> assert false in
    let attributes = ref [] in
    let add name kind = match name with
      | None -> ()
      | Some name ->
          let values = existing_float name point_count geometry in
          if point_count > 0 then
            Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
              (fun point ->
                if point land 16_383 = 0 then Cancel.check_opt cancel;
                if selected point then values.(point) <- derived kind point);
          let attribute = Attribute.create_owned ~owner:Attribute.Point ~name
              (Attribute.Float values) in
          (match attribute with Ok value -> attributes := value :: !attributes
           | Error message -> fail message) in
    add outputs.mean `Mean;
    add outputs.gaussian `Gaussian;
    add outputs.minimum `Minimum;
    add outputs.maximum `Maximum;
    add outputs.curvedness `Curvedness;
    add outputs.shape_index `Shape_index;
    (match Geometry.Private.with_merged_attributes_owned
        (Array.of_list (List.rev !attributes)) geometry with
     | Ok output -> Ok output
     | Error message -> fail message)
  with Curvature_error message -> Error message
