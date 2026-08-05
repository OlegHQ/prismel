open Prismel

type piece_owner = Centroid_piece_points | Centroid_piece_primitives

type run_over =
  | Centroid_detail
  | Centroid_primitives
  | Centroid_pieces of { owner : piece_owner; attribute : string }

type method_ = Centroid_point_mass | Centroid_bounding_box | Centroid_convex_hull

type piece_values = Int_values of int array | Text_values of string array
type piece_identifiers = Output_int of int array | Output_text of string array

exception Extract_error of string
let fail message = raise (Extract_error message)
let finite = Float.is_finite

let check_name label = function
  | None -> ()
  | Some name when String.trim name = "" || String.equal name "P" ->
      fail (label ^ " must be non-empty and cannot be P")
  | Some _ -> ()

let point_mass positions points first last =
  if first = last then fail "centroid piece contains no points";
  let scale = ref 0. in
  for at = first to last - 1 do
    let point = Array.unsafe_get points at in
    scale := Float.max !scale
        (Float.max (abs_float (Array.unsafe_get positions.Packed.Float3.Private.x point))
          (Float.max (abs_float (Array.unsafe_get positions.y point))
            (abs_float (Array.unsafe_get positions.z point))))
  done;
  if not (finite !scale) then fail "centroid input contains a non-finite point";
  if !scale = 0. then 0., 0., 0.
  else begin
    let sx = ref 0. and sy = ref 0. and sz = ref 0. in
    for at = first to last - 1 do
      let point = Array.unsafe_get points at in
      sx := !sx +. (Array.unsafe_get positions.x point /. !scale);
      sy := !sy +. (Array.unsafe_get positions.y point /. !scale);
      sz := !sz +. (Array.unsafe_get positions.z point /. !scale)
    done;
    let factor = !scale /. Float.of_int (last - first) in
    let x = !sx *. factor and y = !sy *. factor and z = !sz *. factor in
    if not (finite x && finite y && finite z) then
      fail "point-mass centroid is not representable";
    x, y, z
  end

let bounds positions points first last =
  if first = last then fail "centroid piece contains no points";
  let first_point = Array.unsafe_get points first in
  let min_x = ref (Array.unsafe_get positions.Packed.Float3.Private.x first_point)
  and min_y = ref (Array.unsafe_get positions.y first_point)
  and min_z = ref (Array.unsafe_get positions.z first_point)
  and max_x = ref (Array.unsafe_get positions.x first_point)
  and max_y = ref (Array.unsafe_get positions.y first_point)
  and max_z = ref (Array.unsafe_get positions.z first_point) in
  if not (finite !min_x && finite !min_y && finite !min_z) then
    fail "centroid input contains a non-finite point";
  for at = first + 1 to last - 1 do
    let point = Array.unsafe_get points at in
    let x = Array.unsafe_get positions.x point
    and y = Array.unsafe_get positions.y point
    and z = Array.unsafe_get positions.z point in
    if not (finite x && finite y && finite z) then
      fail "centroid input contains a non-finite point";
    if x < !min_x then min_x := x; if x > !max_x then max_x := x;
    if y < !min_y then min_y := y; if y > !max_y then max_y := y;
    if z < !min_z then min_z := z; if z > !max_z then max_z := z
  done;
  let x = (!min_x *. 0.5) +. (!max_x *. 0.5)
  and y = (!min_y *. 0.5) +. (!max_y *. 0.5)
  and z = (!min_z *. 0.5) +. (!max_z *. 0.5) in
  if not (finite x && finite y && finite z) then
    fail "bounding-box centroid is not representable";
  x, y, z

let hull_center ?cancel ~grain positions points first last =
  let count = last - first in
  let x = Array.make count 0. and y = Array.make count 0.
  and z = Array.make count 0. in
  for local = 0 to count - 1 do
    let point = Array.unsafe_get points (first + local) in
    x.(local) <- Array.unsafe_get positions.Packed.Float3.Private.x point;
    y.(local) <- Array.unsafe_get positions.y point;
    z.(local) <- Array.unsafe_get positions.z point
  done;
  let source = Geometry.create
      ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology:(Topology.empty ~point_count:count) () |> Result.get_ok in
  let hull = match Convex_hull.run ?cancel ~grain ~preserve_point_payload:false source with
    | Ok hull -> hull | Error message -> fail message in
  let hp = Packed.Float3.Private.view (Geometry.positions hull)
  and ht = Topology.Private.view (Geometry.topology hull) in
  let hc = Geometry.point_count hull in
  if hc = 1 then hp.x.(0), hp.y.(0), hp.z.(0)
  else if Geometry.primitive_count hull = 1
      && Topology.primitive_kind (Geometry.topology hull) 0 = Topology.Open_polyline
  then
    (hp.x.(0) *. 0.5) +. (hp.x.(1) *. 0.5),
    (hp.y.(0) *. 0.5) +. (hp.y.(1) *. 0.5),
    (hp.z.(0) *. 0.5) +. (hp.z.(1) *. 0.5)
  else if Geometry.primitive_count hull = 1 then begin
    let first_vertex = ht.primitive_offsets.(0)
    and last_vertex = ht.primitive_offsets.(1) in
    let anchor = ht.vertex_points.(first_vertex) in
    let scale = ref 0. in
    for point = 0 to hc - 1 do
      scale := Float.max !scale (Float.max (abs_float hp.x.(point))
          (Float.max (abs_float hp.y.(point)) (abs_float hp.z.(point))))
    done;
    if !scale = 0. then 0., 0., 0. else begin
      let total = ref 0. and sx = ref 0. and sy = ref 0. and sz = ref 0. in
      let ax = hp.x.(anchor) /. !scale and ay = hp.y.(anchor) /. !scale
      and az = hp.z.(anchor) /. !scale in
      for vertex = first_vertex + 1 to last_vertex - 2 do
        let b = ht.vertex_points.(vertex) and c = ht.vertex_points.(vertex + 1) in
        let bx = hp.x.(b) /. !scale and by = hp.y.(b) /. !scale
        and bz = hp.z.(b) /. !scale and cx = hp.x.(c) /. !scale
        and cy = hp.y.(c) /. !scale and cz = hp.z.(c) /. !scale in
        let ux = bx -. ax and uy = by -. ay and uz = bz -. az
        and vx = cx -. ax and vy = cy -. ay and vz = cz -. az in
        let nx = (uy *. vz) -. (uz *. vy)
        and ny = (uz *. vx) -. (ux *. vz)
        and nz = (ux *. vy) -. (uy *. vx) in
        let area = sqrt ((nx *. nx) +. (ny *. ny) +. (nz *. nz)) in
        total := !total +. area;
        sx := !sx +. (area *. ((ax +. bx +. cx) /. 3.));
        sy := !sy +. (area *. ((ay +. by +. cy) /. 3.));
        sz := !sz +. (area *. ((az +. bz +. cz) /. 3.))
      done;
      if !total = 0. then point_mass hp ht.vertex_points first_vertex last_vertex
      else !scale *. !sx /. !total, !scale *. !sy /. !total,
           !scale *. !sz /. !total
    end
  end else begin
    (* The exact hull is outward. Translate tetrahedra to a hull vertex before
       accumulating so large world coordinates do not dominate the determinant. *)
    let ox = hp.x.(0) and oy = hp.y.(0) and oz = hp.z.(0) in
    let scale = ref 0. in
    for point = 0 to hc - 1 do
      scale := Float.max !scale (Float.max (abs_float (hp.x.(point) -. ox))
          (Float.max (abs_float (hp.y.(point) -. oy))
            (abs_float (hp.z.(point) -. oz))))
    done;
    if !scale = 0. then ox, oy, oz else begin
      let volume = ref 0. and sx = ref 0. and sy = ref 0. and sz = ref 0. in
      for primitive = 0 to Geometry.primitive_count hull - 1 do
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        let at = ht.primitive_offsets.(primitive) in
        let a = ht.vertex_points.(at) and b = ht.vertex_points.(at + 1)
        and c = ht.vertex_points.(at + 2) in
        let ax = (hp.x.(a) -. ox) /. !scale
        and ay = (hp.y.(a) -. oy) /. !scale
        and az = (hp.z.(a) -. oz) /. !scale
        and bx = (hp.x.(b) -. ox) /. !scale
        and by = (hp.y.(b) -. oy) /. !scale
        and bz = (hp.z.(b) -. oz) /. !scale
        and cx = (hp.x.(c) -. ox) /. !scale
        and cy = (hp.y.(c) -. oy) /. !scale
        and cz = (hp.z.(c) -. oz) /. !scale in
        let six = ax *. ((by *. cz) -. (bz *. cy))
            +. ay *. ((bz *. cx) -. (bx *. cz))
            +. az *. ((bx *. cy) -. (by *. cx)) in
        volume := !volume +. six;
        sx := !sx +. (six *. (ax +. bx +. cx));
        sy := !sy +. (six *. (ay +. by +. cy));
        sz := !sz +. (six *. (az +. bz +. cz))
      done;
      if !volume = 0. then point_mass hp (Array.init hc Fun.id) 0 hc
      else
        ox +. (!scale *. !sx /. (4. *. !volume)),
        oy +. (!scale *. !sy /. (4. *. !volume)),
        oz +. (!scale *. !sz /. (4. *. !volume))
    end
  end

let values ~owner ~name geometry =
  if String.trim name = "" || String.equal name "P" then
    fail "piece attribute must be non-empty and cannot be P";
  let attribute_owner = match owner with
    | Centroid_piece_points -> Attribute.Point
    | Centroid_piece_primitives -> Attribute.Primitive in
  match Geometry.find_attribute ~owner:attribute_owner name geometry with
  | None -> fail (Printf.sprintf "%s piece attribute %S was not found"
      (match owner with Centroid_piece_points -> "point"
        | Centroid_piece_primitives -> "primitive") name)
  | Some attribute -> match Attribute.Private.storage attribute with
      | Attribute.Int values -> Int_values values
      | Attribute.Text values -> Text_values values
      | _ -> fail (Printf.sprintf "piece attribute %S must use integer or text storage" name)

let classify values count =
  let ids = Array.make count 0 in
  match values with
  | Int_values values ->
      let table = Hashtbl.create (min 65_536 (max 1 count))
      and representatives = ref (Array.make (min 16 (max 1 count)) 0)
      and length = ref 0 in
      let append value =
        if !length = Array.length !representatives then begin
          let old = !representatives in
          let capacity = min count (max 1 (Array.length old * 2)) in
          let next = Array.make capacity 0 in
          Array.blit old 0 next 0 !length; representatives := next
        end;
        (!representatives).(!length) <- value;
        incr length in
      for element = 0 to count - 1 do
        let value = values.(element) in
        match Hashtbl.find_opt table value with
        | Some piece -> ids.(element) <- piece
        | None ->
            let piece = !length in
            ids.(element) <- piece; Hashtbl.add table value piece; append value
      done;
      ids, Output_int (Array.sub !representatives 0 !length)
  | Text_values values ->
      let table = Hashtbl.create (min 65_536 (max 1 count))
      and representatives = ref (Array.make (min 16 (max 1 count)) "")
      and length = ref 0 in
      let append value =
        if !length = Array.length !representatives then begin
          let old = !representatives in
          let capacity = min count (max 1 (Array.length old * 2)) in
          let next = Array.make capacity "" in
          Array.blit old 0 next 0 !length; representatives := next
        end;
        (!representatives).(!length) <- value;
        incr length in
      for element = 0 to count - 1 do
        let value = values.(element) in
        match Hashtbl.find_opt table value with
        | Some piece -> ids.(element) <- piece
        | None ->
            let piece = !length in
            ids.(element) <- piece; Hashtbl.add table value piece; append value
      done;
      ids, Output_text (Array.sub !representatives 0 !length)

let identifier_count = function
  | Output_int values -> Array.length values
  | Output_text values -> Array.length values

let radix_sort_nonnegative ?cancel values =
  let length = Array.length values in
  if length > 1 then begin
    let scratch = Array.make length 0 in
    let source = ref values and target = ref scratch in
    for byte = 0 to ((Sys.int_size - 2) / 8) do
      Cancel.check_opt cancel;
      let shift = byte * 8 and counts = Array.make 256 0 in
      for at = 0 to length - 1 do
        let bucket = (Array.unsafe_get !source at lsr shift) land 255 in
        Array.unsafe_set counts bucket (Array.unsafe_get counts bucket + 1)
      done;
      let total = ref 0 in
      for bucket = 0 to 255 do
        let count = Array.unsafe_get counts bucket in
        Array.unsafe_set counts bucket !total; total := !total + count
      done;
      for at = 0 to length - 1 do
        let value = Array.unsafe_get !source at in
        let bucket = (value lsr shift) land 255 in
        let output = Array.unsafe_get counts bucket in
        Array.unsafe_set !target output value;
        Array.unsafe_set counts bucket (output + 1)
      done;
      let previous = !source in source := !target; target := previous
    done;
    if !source != values then Array.blit !source 0 values 0 length
  end

let piece_points_for_primitives ?cancel topology primitive_piece piece_count =
  let vertex_count = Array.length topology.Topology.Private.vertex_points in
  if piece_count > 0 && topology.point_count > max_int / piece_count then
    fail "piece/point incidence key exceeds integer limits";
  let keys = Array.make vertex_count 0 in
  for primitive = 0 to Array.length primitive_piece - 1 do
    let piece = primitive_piece.(primitive) in
    for vertex = topology.primitive_offsets.(primitive)
        to topology.primitive_offsets.(primitive + 1) - 1 do
      keys.(vertex) <- (topology.vertex_points.(vertex) * piece_count) + piece
    done
  done;
  radix_sort_nonnegative ?cancel keys;
  let unique = ref 0 in
  for at = 0 to vertex_count - 1 do
    if at = 0 || keys.(at) <> keys.(at - 1) then begin
      keys.(!unique) <- keys.(at); incr unique
    end
  done;
  let counts = Array.make piece_count 0 in
  for at = 0 to !unique - 1 do
    counts.(keys.(at) mod piece_count) <- counts.(keys.(at) mod piece_count) + 1
  done;
  let offsets = Array.make (piece_count + 1) 0 in
  for piece = 0 to piece_count - 1 do offsets.(piece + 1) <- offsets.(piece) + counts.(piece) done;
  let points = Array.make !unique 0 and next = Array.copy offsets in
  for at = 0 to !unique - 1 do
    let key = keys.(at) in
    let piece = key mod piece_count in
    points.(next.(piece)) <- key / piece_count; next.(piece) <- next.(piece) + 1
  done;
  offsets, points

let detail_attributes geometry =
  List.filter (fun attribute -> Attribute.owner attribute = Attribute.Detail)
    (Geometry.attributes geometry)

let run ?cancel ?(grain = 16_384) ?(run_over = Centroid_detail)
    ?(method_ = Centroid_point_mass) ?source_primitive_attribute
    ?piece_output_attribute geometry =
  try
    if grain <= 0 then fail "grain must be positive";
    check_name "source primitive attribute" source_primitive_attribute;
    check_name "piece output attribute" piece_output_attribute;
    Cancel.check_opt cancel;
    let positions = Packed.Float3.Private.view (Geometry.positions geometry)
    and topology = Topology.Private.view (Geometry.topology geometry) in
    let piece_count, offsets, points, identifiers = match run_over with
      | Centroid_detail ->
          let count = Geometry.point_count geometry in
          if count = 0 then fail "cannot extract a centroid from empty geometry";
          1, [|0; count|], Array.init count Fun.id, None
      | Centroid_primitives ->
          let count = Geometry.primitive_count geometry in
          if count = 0 then fail "cannot extract primitive centroids without primitives";
          count, Array.copy topology.primitive_offsets,
          Array.copy topology.vertex_points, None
      | Centroid_pieces { owner = Centroid_piece_points; attribute } ->
          let source = values ~owner:Centroid_piece_points ~name:attribute geometry in
          let ids, representatives = classify source (Geometry.point_count geometry) in
          let count = identifier_count representatives in
          if count = 0 then fail "cannot extract pieces from empty geometry";
          let counts = Array.make count 0 in
          Array.iter (fun piece -> counts.(piece) <- counts.(piece) + 1) ids;
          let offsets = Array.make (count + 1) 0 in
          for piece = 0 to count - 1 do
            offsets.(piece + 1) <- offsets.(piece) + counts.(piece)
          done;
          let points = Array.make (Array.length ids) 0 and next = Array.copy offsets in
          Array.iteri (fun point piece -> points.(next.(piece)) <- point;
            next.(piece) <- next.(piece) + 1) ids;
          count, offsets, points, Some representatives
      | Centroid_pieces { owner = Centroid_piece_primitives; attribute } ->
          let source = values ~owner:Centroid_piece_primitives ~name:attribute geometry in
          let ids, representatives = classify source (Geometry.primitive_count geometry) in
          let count = identifier_count representatives in
          if count = 0 then fail "cannot extract pieces without primitives";
          let offsets, points = piece_points_for_primitives ?cancel topology ids
              count in
          count, offsets, points, Some representatives in
    let x = Array.make piece_count 0. and y = Array.make piece_count 0.
    and z = Array.make piece_count 0. in
    let compute piece =
      if piece land 1023 = 0 then Cancel.check_opt cancel;
      let first = offsets.(piece) and last = offsets.(piece + 1) in
      let cx, cy, cz = match method_ with
        | Centroid_point_mass -> point_mass positions points first last
        | Centroid_bounding_box -> bounds positions points first last
        | Centroid_convex_hull -> hull_center ?cancel ~grain positions points first last in
      if not (finite cx && finite cy && finite cz) then
        fail (Printf.sprintf "centroid %d is not representable" piece);
      x.(piece) <- cx; y.(piece) <- cy; z.(piece) <- cz in
    if method_ = Centroid_convex_hull || piece_count < 512 then
      for piece = 0 to piece_count - 1 do compute piece done
    else Parallel.for_ ~chunk_size:(max 1 (grain / 16)) ~start:0
        ~finish:(piece_count - 1) compute;
    let generated_attributes = ref [] in
    (match run_over, source_primitive_attribute with
     | Centroid_primitives, Some name ->
         generated_attributes := (Attribute.create_owned ~owner:Attribute.Point ~name
             (Attribute.Int (Array.init piece_count Fun.id)) |> Result.get_ok)
             :: !generated_attributes
     | _ -> ());
    (match identifiers with
     | None -> ()
     | Some identifiers ->
         let default_name = match run_over with
           | Centroid_pieces {attribute; _} -> attribute | _ -> assert false in
         let name = Option.value piece_output_attribute ~default:default_name in
         let storage = match identifiers with
           | Output_int values -> Attribute.Int values
           | Output_text values -> Attribute.Text values in
         generated_attributes := (Attribute.create_owned ~owner:Attribute.Point
             ~name storage |> Result.get_ok) :: !generated_attributes);
    Geometry.create ~positions:(Packed.Float3.Private.of_owned_exn ~x ~y ~z)
      ~topology:(Topology.empty ~point_count:piece_count)
      ~attributes:(detail_attributes geometry @ List.rev !generated_attributes) ()
  with
  | Extract_error message | Invalid_argument message -> Error message
