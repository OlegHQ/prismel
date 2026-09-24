open Prismel

type scalar =
  | Constant of float
  | Floats of float array
  | Ints of int array

type ramp = {
  positions : float array;
  values : float array;
}

let fail message = Error ("Pdk.Ops.attribute_fade: " ^ message)
let ( let* ) result continuation = Result.bind result continuation

let block_count length grain =
  if length = 0 then 0 else 1 + ((length - 1) / grain)

let block_bounds length grain block =
  let first = block * grain in
  let remaining = length - first in
  first, if grain >= remaining then length else first + grain

let[@inline always] scalar_get source point = match source with
  | Constant value -> value
  | Floats values -> Array.unsafe_get values point
  | Ints values -> Float.of_int (Array.unsafe_get values point)

let compile_ramp label knots =
  let knots = Array.of_list knots in
  let count = Array.length knots in
  if count < 2 then fail (label ^ " ramp requires at least two knots")
  else begin
    let failure = ref None in
    for index = 0 to count - 1 do
      if !failure = None then begin
        let position, value = Array.unsafe_get knots index in
        if not (Float.is_finite position && Float.is_finite value) then
          failure := Some (label ^ " ramp knots must be finite")
        else if position < 0. || position > 1. then
          failure := Some (label ^ " ramp positions must lie in [0, 1]")
        else if index > 0
            && position <= fst (Array.unsafe_get knots (index - 1)) then
          failure := Some (label ^ " ramp positions must be strictly increasing")
      end
    done;
    match !failure with
    | Some message -> fail message
    | None when fst (Array.unsafe_get knots 0) <> 0.
        || fst (Array.unsafe_get knots (count - 1)) <> 1. ->
        fail (label ^ " ramp must span 0 through 1")
    | None ->
        let positions = Array.make count 0.
        and values = Array.make count 0. in
        for index = 0 to count - 1 do
          let position, value = Array.unsafe_get knots index in
          Array.unsafe_set positions index position;
          Array.unsafe_set values index value
        done;
        Ok { positions; values }
  end

let[@inline always] sample ramp value =
  let count = Array.length ramp.positions in
  if value <= 0. then Array.unsafe_get ramp.values 0
  else if value >= 1. then Array.unsafe_get ramp.values (count - 1)
  else begin
    let low = ref 0 and high = ref (count - 1) in
    while !high - !low > 1 do
      let middle = (!low + !high) / 2 in
      if Array.unsafe_get ramp.positions middle <= value
      then low := middle else high := middle
    done;
    let x0 = Array.unsafe_get ramp.positions !low
    and x1 = Array.unsafe_get ramp.positions !high
    and y0 = Array.unsafe_get ramp.values !low
    and y1 = Array.unsafe_get ramp.values !high in
    y0 +. (((value -. x0) /. (x1 -. x0)) *. (y1 -. y0))
  end

let validate_points point_count = function
  | None -> Ok ()
  | Some points when Group.owner points <> Group.Point ->
      fail "selection must be point-owned"
  | Some points when Group.length points <> point_count ->
      fail (Printf.sprintf "selection length %d does not match point count %d"
        (Group.length points) point_count)
  | Some _ -> Ok ()

let validate_reference label point_count = function
  | None -> Ok ()
  | Some source when Geometry.point_count source <> point_count ->
      fail (Printf.sprintf "%s input point count %d does not match target point count %d"
        label (Geometry.point_count source) point_count)
  | Some _ -> Ok ()

let point_scalar ~label ~default name geometry = match name with
  | None -> Ok (Constant default)
  | Some name ->
      if String.trim name = "" then fail (label ^ " attribute name must not be empty")
      else match Geometry.find_attribute ~owner:Attribute.Point name geometry with
        | None -> Ok (Constant default)
        | Some attribute ->
            (match Attribute.Private.storage attribute with
             | Attribute.Float values -> Ok (Floats values)
             | Attribute.Int values -> Ok (Ints values)
             | _ -> fail (Printf.sprintf
                 "%s point attribute %S must have scalar float or integer storage, not %s"
                 label name (Attribute.kind_name attribute)))

let fade_source name geometry =
  match Geometry.find_attribute ~owner:Attribute.Point name geometry with
  | None -> Ok (Constant 1., false)
  | Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> Ok (Floats values, true)
       | _ -> fail (Printf.sprintf
           "fade point attribute %S must have scalar float storage, not %s"
           name (Attribute.kind_name attribute)))

let error_message kind point = match kind with
  | 1 -> Printf.sprintf "fade value is non-finite at point %d" point
  | 2 -> Printf.sprintf "fade start value is non-finite at point %d" point
  | 3 -> Printf.sprintf "hold scale is non-finite or negative at point %d" point
  | 4 -> Printf.sprintf "retimed fade start is non-finite at point %d" point
  | 5 -> Printf.sprintf "scaled fade hold is non-finite at point %d" point
  | 6 -> Printf.sprintf "relative fade frame is non-finite at point %d" point
  | _ -> Printf.sprintf "faded output is non-finite at point %d" point

let fade ?cancel ?(grain = 16_384) ?points ?start_source ?hold_source
    ?(fade_attribute = "fade") ?start_attribute
    ?(start_retime = (0., 1.)) ?hold_scale_attribute ~frame
    ?(frame_offset = 0.) ?(fade_in = 2.) ?(fade_hold = 0.)
    ?(fade_out = 2.) ?(fade_in_ramp = [0., 0.; 1., 1.])
    ?(fade_out_ramp = [0., 1.; 1., 0.]) ?(visualize = false) geometry =
  Cancel.check_opt cancel;
  let point_count = Geometry.point_count geometry in
  let start_offset, start_scale = start_retime in
  if grain <= 0 then fail "grain must be positive"
  else if String.trim fade_attribute = "" then fail "fade attribute name must not be empty"
  else if String.equal fade_attribute "P" then fail "canonical P cannot be faded"
  else if visualize && String.equal fade_attribute "Cd" then
    fail "fade attribute and visualization Cd must have distinct names"
  else if not (Float.is_finite frame) then fail "frame must be finite"
  else if not (Float.is_finite frame_offset) then fail "frame offset must be finite"
  else if not (Float.is_finite start_offset && Float.is_finite start_scale) then
    fail "start retime offset and scale must be finite"
  else if not (Float.is_finite fade_in) || fade_in < 0. then
    fail "fade-in duration must be finite and non-negative"
  else if not (Float.is_finite fade_hold) || fade_hold < 0. then
    fail "fade-hold duration must be finite and non-negative"
  else if not (Float.is_finite fade_out) || fade_out < 0. then
    fail "fade-out duration must be finite and non-negative"
  else
  let* () = validate_points point_count points in
  let* () = validate_reference "start" point_count start_source in
  let* () = validate_reference "hold-scale" point_count hold_source in
  let* in_ramp = compile_ramp "fade-in" fade_in_ramp in
  let* out_ramp = compile_ramp "fade-out" fade_out_ramp in
  let* source, source_exists = fade_source fade_attribute geometry in
  let start_geometry = Option.value ~default:geometry start_source
  and hold_geometry = Option.value ~default:geometry hold_source in
  let* starts = point_scalar ~label:"fade start" ~default:0.
      start_attribute start_geometry in
  let* hold_scales = point_scalar ~label:"hold scale" ~default:1.
      hold_scale_attribute hold_geometry in
  let output = match source with
    | Floats values -> Array.copy values
    | Constant value -> Array.make point_count value
    | Ints _ -> assert false in
  let color = if visualize then Some (Array.make point_count 0.,
      Array.make point_count 0., Array.make point_count 0.,
      Array.make point_count 1.) else None in
  let blocks = block_count point_count grain in
  let error_points = Array.make blocks (-1)
  and error_kinds = Bytes.make blocks '\000'
  and changed = Bytes.make blocks (if source_exists then '\000' else '\001') in
  if blocks > 0 then Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(blocks - 1)
    (fun block ->
      Cancel.check_opt cancel;
      let first, last = block_bounds point_count grain block in
      let first_error = ref (-1) and first_kind = ref 0
      and block_changed = ref (not source_exists) in
      for point = first to last - 1 do
        if point land 4095 = 0 then Cancel.check_opt cancel;
        let selected = match points with None -> true | Some group -> Group.mem point group in
        let source_value = scalar_get source point in
        let value = if not selected then source_value else begin
          let start_value = scalar_get starts point
          and hold_scale = scalar_get hold_scales point in
          if !first_error < 0 then begin
            if not (Float.is_finite source_value) then
              (first_error := point; first_kind := 1)
            else if not (Float.is_finite start_value) then
              (first_error := point; first_kind := 2)
            else if not (Float.is_finite hold_scale) || hold_scale < 0. then
              (first_error := point; first_kind := 3)
          end;
          let start = start_offset +. (start_value *. start_scale) +. frame_offset
          and hold = fade_hold *. hold_scale in
          if !first_error < 0 && not (Float.is_finite start) then
            (first_error := point; first_kind := 4);
          if !first_error < 0 && not (Float.is_finite hold) then
            (first_error := point; first_kind := 5);
          let elapsed = frame -. start in
          if !first_error < 0 && not (Float.is_finite elapsed) then
            (first_error := point; first_kind := 6);
          let factor =
            if elapsed < 0. then 0.
            else if fade_in > 0. && elapsed <= fade_in then
              sample in_ramp (elapsed /. fade_in)
            else begin
              let after_in = elapsed -. fade_in in
              if after_in < hold then 1.
              else if fade_out > 0.
                  && after_in -. hold <= fade_out then
                sample out_ramp ((after_in -. hold) /. fade_out)
              else 0.
            end in
          source_value *. factor
        end in
        if !first_error < 0 && (selected || visualize)
            && not (Float.is_finite value) then
          (first_error := point; first_kind := 7);
        if selected && value <> Array.unsafe_get output point then
          block_changed := true;
        Array.unsafe_set output point value;
        (match color with
         | None -> ()
         | Some (x, y, z, w) ->
             Array.unsafe_set x point value;
             Array.unsafe_set y point value;
             Array.unsafe_set z point value;
             Array.unsafe_set w point 1.)
      done;
      if !first_error >= 0 then begin
        Array.unsafe_set error_points block !first_error;
        Bytes.unsafe_set error_kinds block (Char.chr !first_kind)
      end;
      if !block_changed then Bytes.unsafe_set changed block '\001');
  let first_bad_block = Array.find_index (fun point -> point >= 0) error_points in
  match first_bad_block with
  | Some block -> fail (error_message
      (Char.code (Bytes.unsafe_get error_kinds block))
      (Array.unsafe_get error_points block))
  | None ->
      let fade_changed = Bytes.exists (fun byte -> byte <> '\000') changed in
      if not fade_changed && not visualize then Ok geometry
      else
        let* faded = Attribute.create_owned ~name:fade_attribute
            ~owner:Attribute.Point (Attribute.Float output) in
        let* replacements = match color with
          | None -> Ok [|faded|]
          | Some (x, y, z, w) ->
              let* colors = Packed.Float4.of_owned ~x ~y ~z ~w in
              let* color = Attribute.create_owned ~name:"Cd"
                  ~owner:Attribute.Point (Attribute.Float4 colors) in
              Ok [|faded; color|] in
        Geometry.Private.with_merged_attributes_owned replacements geometry
