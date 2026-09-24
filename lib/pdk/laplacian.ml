open Prismel

type weighting =
  | Laplacian_cotan
  | Laplacian_positive_cotan
  | Laplacian_uniform

exception Laplacian_error of string
let fail message = raise (Laplacian_error message)
let finite = Float.is_finite

type source = { width : int; planes : float array array }

let source ?cancel name point_count geometry =
  if String.equal name "P" then begin
    let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
    {width=3;planes=[|positions.x;positions.y;positions.z|]}
  end else match Geometry.find_attribute ~owner:Attribute.Point name geometry with
    | None -> fail (Printf.sprintf "point source attribute %S is missing" name)
    | Some attribute ->
        if Attribute.length attribute <> point_count then
          fail (Printf.sprintf "point source attribute %S has wrong cardinality" name);
        match Attribute.Private.storage attribute with
        | Attribute.Float values -> {width=1;planes=[|values|]}
        | Attribute.Int values ->
            let converted = Array.make point_count 0. in
            if point_count > 0 then
              Parallel.for_ ~chunk_size:16_384 ~start:0 ~finish:(point_count - 1)
                (fun point ->
                  if point land 16_383 = 0 then Cancel.check_opt cancel;
                  converted.(point) <- float_of_int values.(point));
            {width=1;planes=[|converted|]}
        | Attribute.Float2 values ->
            let values = Packed.Float2.Private.view values in
            {width=2;planes=[|values.x;values.y|]}
        | Attribute.Float3 values ->
            let values = Packed.Float3.Private.view values in
            {width=3;planes=[|values.x;values.y;values.z|]}
        | Attribute.Float4 values ->
            let values = Packed.Float4.Private.view values in
            {width=4;planes=[|values.x;values.y;values.z;values.w|]}
        | Attribute.Text _ | Attribute.Int_array _ | Attribute.Float_array _ ->
            fail (Printf.sprintf
              "point source attribute %S must use scalar or fixed-width numeric storage"
              name)

let output_planes name width point_count geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Array.init width (fun _ -> Array.make point_count 0.)
  | Some attribute ->
      if Attribute.length attribute <> point_count then
        fail (Printf.sprintf "point output attribute %S has wrong cardinality" name);
      let copy planes = Array.map Array.copy planes in
      match width, Attribute.Private.storage attribute with
      | 1, Attribute.Float values -> [|Array.copy values|]
      | 2, Attribute.Float2 values ->
          let values = Packed.Float2.Private.view values in
          copy [|values.x;values.y|]
      | 3, Attribute.Float3 values ->
          let values = Packed.Float3.Private.view values in
          copy [|values.x;values.y;values.z|]
      | 4, Attribute.Float4 values ->
          let values = Packed.Float4.Private.view values in
          copy [|values.x;values.y;values.z;values.w|]
      | _ -> fail (Printf.sprintf
          "point output attribute %S has incompatible storage" name)

let create_attribute name planes =
  let storage = match Array.length planes with
    | 1 -> Attribute.Float planes.(0)
    | 2 ->
        (match Packed.Float2.of_owned ~x:planes.(0) ~y:planes.(1) with
         | Ok values -> Attribute.Float2 values | Error message -> fail message)
    | 3 ->
        (match Packed.Float3.of_owned ~x:planes.(0) ~y:planes.(1) ~z:planes.(2) with
         | Ok values -> Attribute.Float3 values | Error message -> fail message)
    | 4 ->
        (match Packed.Float4.of_owned ~x:planes.(0) ~y:planes.(1)
            ~z:planes.(2) ~w:planes.(3) with
         | Ok values -> Attribute.Float4 values | Error message -> fail message)
    | _ -> assert false in
  match Attribute.create_owned ~owner:Attribute.Point ~name storage with
  | Ok attribute -> attribute | Error message -> fail message

let validate_point_group point_count = function
  | Some group when Group.owner group <> Group.Point ->
      fail "laplacian selection must own points"
  | Some group when Group.length group <> point_count ->
      fail "laplacian point selection length does not match geometry"
  | None | Some _ -> ()

let validate_source ?cancel source point_count =
  let invalid = Atomic.make false in
  if point_count > 0 then
    Parallel.for_ ~chunk_size:16_384 ~start:0 ~finish:(point_count - 1)
      (fun point ->
        if point land 16_383 = 0 then Cancel.check_opt cancel;
        for component = 0 to source.width - 1 do
          if not (finite source.planes.(component).(point)) then
            Atomic.set invalid true
        done);
  if Atomic.get invalid then fail "laplacian source values must be finite"

let selected points point = match points with
  | None -> true | Some group -> Group.mem point group

let uniform ?cancel ~grain ~normalize ~points source output index =
  let point_count = Array.length index.Topology_index.Private.point_edge_offsets - 1 in
  let invalid = Atomic.make false in
  if point_count > 0 then
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
      (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if selected points point then begin
          let first = index.point_edge_offsets.(point)
          and last = index.point_edge_offsets.(point + 1) in
          for component = 0 to source.width - 1 do
            output.(component).(point) <- 0.
          done;
          for at = first to last - 1 do
            let edge = index.point_edges.(at) in
            let neighbor = if index.edge_a.(edge) = point
              then index.edge_b.(edge) else index.edge_a.(edge) in
            for component = 0 to source.width - 1 do
              output.(component).(point) <- output.(component).(point)
                  +. source.planes.(component).(neighbor)
                  -. source.planes.(component).(point)
            done
          done;
          let factor = if normalize && last > first
            then 1. /. float_of_int (last - first) else 1. in
          for component = 0 to source.width - 1 do
            let value = output.(component).(point) *. factor in
            if finite value then output.(component).(point) <- value
            else Atomic.set invalid true
          done
        end);
  if Atomic.get invalid then fail "uniform laplacian output is not finite"

let cotan ?cancel ~grain ~positive ~normalize ~points source output metric =
  let invalid = Atomic.make false in
  let areas = if normalize then Array.make metric.Surface_metric.point_count 0.
    else [||] in
  if normalize && metric.point_count > 0 then
    Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(metric.point_count - 1)
      (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if selected points point then begin
          areas.(point) <- 0.;
          for at = metric.point_offsets.(point)
              to metric.point_offsets.(point + 1) - 1 do
            let encoded = metric.incidence.(at) in
            let triangle = encoded / 3 and local = encoded mod 3 in
            let a = metric.triangle_a.(triangle)
            and b = metric.triangle_b.(triangle)
            and c = metric.triangle_c.(triangle) in
            let neighbor_a = if local = 0 then b else if local = 1 then c else a
            and neighbor_b = if local = 0 then c else if local = 1 then a else b
            and cotangent = if local = 0 then metric.cotangent_a.(triangle)
              else if local = 1 then metric.cotangent_b.(triangle)
              else metric.cotangent_c.(triangle)
            and cotangent_neighbor_a = if local = 0
              then metric.cotangent_b.(triangle)
              else if local = 1 then metric.cotangent_c.(triangle)
              else metric.cotangent_a.(triangle)
            and cotangent_neighbor_b = if local = 0
              then metric.cotangent_c.(triangle)
              else if local = 1 then metric.cotangent_a.(triangle)
              else metric.cotangent_b.(triangle) in
            let dax = metric.scaled_x.(neighbor_a) -. metric.scaled_x.(point)
            and day = metric.scaled_y.(neighbor_a) -. metric.scaled_y.(point)
            and daz = metric.scaled_z.(neighbor_a) -. metric.scaled_z.(point)
            and dbx = metric.scaled_x.(neighbor_b) -. metric.scaled_x.(point)
            and dby = metric.scaled_y.(neighbor_b) -. metric.scaled_y.(point)
            and dbz = metric.scaled_z.(neighbor_b) -. metric.scaled_z.(point) in
            let length_a_squared = (dax *. dax) +. (day *. day) +. (daz *. daz)
            and length_b_squared = (dbx *. dbx) +. (dby *. dby) +. (dbz *. dbz)
            in
            let area = Surface_metric.mixed_area_contribution
                ~double_area:metric.double_area.(triangle)
                ~cotangent_a:metric.cotangent_a.(triangle)
                ~cotangent_b:metric.cotangent_b.(triangle)
                ~cotangent_c:metric.cotangent_c.(triangle)
                ~corner_cotangent:cotangent
                ~edge_a_squared:length_a_squared
                ~edge_b_squared:length_b_squared ~cotangent_neighbor_a
                ~cotangent_neighbor_b in
            areas.(point) <- areas.(point) +. area
          done
        end);
  if metric.Surface_metric.point_count > 0 then
    Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(metric.point_count - 1) (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if selected points point then begin
          let first = metric.point_offsets.(point)
          and last = metric.point_offsets.(point + 1) in
          let area = if normalize then areas.(point) else 1. in
          if normalize && first < last && not (finite area && area > 0.) then
            Atomic.set invalid true
          else begin
            for component = 0 to source.width - 1 do
              output.(component).(point) <- 0.
            done;
            for at = first to last - 1 do
              let encoded = metric.incidence.(at) in
              let triangle = encoded / 3 and local = encoded mod 3 in
              let a = metric.triangle_a.(triangle)
              and b = metric.triangle_b.(triangle)
              and c = metric.triangle_c.(triangle) in
              let neighbor_a = if local = 0 then b else if local = 1 then c else a
              and neighbor_b = if local = 0 then c else if local = 1 then a else b
              and weight_a = if local = 0 then metric.cotangent_c.(triangle)
                else if local = 1 then metric.cotangent_a.(triangle)
                else metric.cotangent_b.(triangle)
              and weight_b = if local = 0 then metric.cotangent_b.(triangle)
                else if local = 1 then metric.cotangent_c.(triangle)
                else metric.cotangent_a.(triangle) in
              let weight_a = if positive && weight_a < 0. then 0. else weight_a
              and weight_b = if positive && weight_b < 0. then 0. else weight_b in
              for component = 0 to source.width - 1 do
                let center = source.planes.(component).(point) in
                output.(component).(point) <- output.(component).(point)
                    +. (weight_a *.
                      (source.planes.(component).(neighbor_a) -. center))
                    +. (weight_b *.
                      (source.planes.(component).(neighbor_b) -. center))
              done
            done;
            let factor = if normalize && first < last then
                ((0.5 /. area) /. metric.scale) /. metric.scale
              else 0.5 in
            for component = 0 to source.width - 1 do
              let value = output.(component).(point) *. factor in
              if finite value then output.(component).(point) <- value
              else Atomic.set invalid true
            done
          end
        end);
  if Atomic.get invalid then fail "cotangent laplacian output is not finite"

let run ?cancel ?(grain = 16_384) ?points ?(weighting = Laplacian_cotan)
    ?(normalize = true) ~source:source_name ?output geometry =
  try
    if grain <= 0 then fail "laplacian grain must be positive";
    if String.trim source_name = "" then fail "laplacian source name is empty";
    let output_name = match output with
      | Some name -> name
      | None when String.equal source_name "P" -> "laplacian"
      | None -> source_name ^ "_laplacian" in
    if String.trim output_name = "" || String.equal output_name "P" then
      fail "laplacian output name must be non-empty and not P";
    Cancel.check_opt cancel;
    let point_count = Geometry.point_count geometry in
    validate_point_group point_count points;
    let source = source ?cancel source_name point_count geometry in
    validate_source ?cancel source point_count;
    let output = output_planes output_name source.width point_count geometry in
    (match weighting with
     | Laplacian_uniform ->
         let topology = Geometry.topology geometry in
         let index_value = Topology_index.create ?cancel topology in
         (match Topology_index.Private.polygon_manifold_boundary_points ?cancel
             ~topology index_value with
          | Error message -> fail message | Ok _ -> ());
         uniform ?cancel ~grain ~normalize ~points source output
           (Topology_index.Private.view index_value)
     | Laplacian_cotan | Laplacian_positive_cotan ->
         let metric = match Surface_metric.create ?cancel ~grain geometry with
           | Ok metric -> metric | Error message -> fail message in
         cotan ?cancel ~grain
           ~positive:(weighting = Laplacian_positive_cotan)
           ~normalize ~points source output metric);
    let attribute = create_attribute output_name output in
    (match Geometry.Private.with_merged_attributes_owned [|attribute|] geometry with
     | Ok geometry -> Ok geometry | Error message -> fail message)
  with Laplacian_error message -> Error message
