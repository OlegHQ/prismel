open Prismel

type kind = Triangle | Segment

type t = {
  positions : Packed.Float3.Private.view;
  topology : Topology.Private.view;
  kinds : bytes;
  primitives : int array;
  locals : int array;
  vertex_a : int array;
  vertex_b : int array;
  vertex_c : int array;
  u0 : float array;
  u1 : float array;
  piece_min_x : float array;
  piece_min_y : float array;
  piece_min_z : float array;
  piece_max_x : float array;
  piece_max_y : float array;
  piece_max_z : float array;
  order : int array;
  min_x : float array;
  min_y : float array;
  min_z : float array;
  max_x : float array;
  max_y : float array;
  max_z : float array;
  left : int array;
  right : int array;
  first : int array;
  count : int array;
}

exception Piece_error of string
exception Group_error of string

let finite = Float.is_finite
let leaf_size = 8
let ceiling_div value divisor =
  (value / divisor) + if value mod divisor = 0 then 0 else 1

let[@inline always] compare_centroid axis x y z left right =
  let compared = if axis = 0 then Float.compare x.(left) x.(right)
    else if axis = 1 then Float.compare y.(left) y.(right)
    else Float.compare z.(left) z.(right) in
  if compared <> 0 then compared else Int.compare left right

let swap values left right =
  if left <> right then begin
    let value = values.(left) in
    values.(left) <- values.(right);
    values.(right) <- value
  end

let[@inline always] median_pivot axis x y z order first middle last =
  let a = order.(first) and b = order.(middle) and c = order.(last) in
  if compare_centroid axis x y z a b < 0 then
    if compare_centroid axis x y z b c < 0 then b
    else if compare_centroid axis x y z a c < 0 then c else a
  else if compare_centroid axis x y z a c < 0 then a
  else if compare_centroid axis x y z b c < 0 then c else b

let select axis x y z order first last selected =
  let lower = ref first and upper = ref last in
  while !lower < !upper do
    let middle = !lower + ((!upper - !lower) / 2) in
    let pivot = median_pivot axis x y z order !lower middle !upper in
    let left = ref !lower and right = ref !upper in
    while !left <= !right do
      while compare_centroid axis x y z order.(!left) pivot < 0 do incr left done;
      while compare_centroid axis x y z order.(!right) pivot > 0 do decr right done;
      if !left <= !right then begin swap order !left !right; incr left; decr right end
    done;
    if selected <= !right then upper := !right
    else if selected >= !left then lower := !left
    else begin lower := selected; upper := selected end
  done

let create_raw ?cancel ?(grain = 16_384) ?primitives geometry =
  if grain <= 0 then invalid_arg "Linear_piece_index: grain must be positive";
  Cancel.check_opt cancel;
  let positions = Packed.Float3.Private.view (Geometry.positions geometry)
  and topology = Topology.Private.view (Geometry.topology geometry) in
  let primitive_count = Bytes.length topology.primitive_kinds in
  let selected = match primitives with
    | None -> Array.init primitive_count Fun.id
    | Some group ->
        if Group.owner group <> Group.Primitive then
          raise (Group_error "selection must be a primitive group");
        if Group.length group <> primitive_count then
          raise (Group_error "primitive group length does not match geometry");
        let output = Array.make (Group.cardinality group) 0 and next = ref 0 in
        Group.iter (fun primitive -> output.(!next) <- primitive; incr next) group;
        output in
  let selected_count = Array.length selected in
  let piece_offsets = Array.make (selected_count + 1) 0 in
  for slot = 0 to selected_count - 1 do
    if slot land 4095 = 0 then Cancel.check_opt cancel;
    let primitive = selected.(slot) in
    let first = topology.primitive_offsets.(primitive)
    and last = topology.primitive_offsets.(primitive + 1) in
    let size = last - first in
    let pieces = match
        Char.code (Bytes.unsafe_get topology.primitive_kinds primitive) with
      | 0 ->
          if size <> 3 then raise (Piece_error (Printf.sprintf
            "primitive %d is a polygon with %d corners, not a triangle"
            primitive size));
          1
      | 1 -> size - 1
      | 2 -> size
      | _ -> raise (Piece_error (Printf.sprintf
          "primitive %d has an invalid kind" primitive)) in
    if pieces > Sys.max_array_length - piece_offsets.(slot) then
      raise (Piece_error "piece cardinality exceeds array limits");
    piece_offsets.(slot + 1) <- piece_offsets.(slot) + pieces
  done;
  let piece_count = piece_offsets.(selected_count) in
  let kinds = Bytes.make piece_count '\000'
  and primitive_of_piece = Array.make piece_count 0
  and locals = Array.make piece_count 0
  and vertex_a = Array.make piece_count 0
  and vertex_b = Array.make piece_count 0
  and vertex_c = Array.make piece_count (-1)
  and u0 = Array.make piece_count 0.
  and u1 = Array.make piece_count 0. in
  let average = if selected_count = 0 then 1
    else max 1 (ceiling_div piece_count selected_count) in
  let chunk = max 1 (grain / average) in
  let ranges = ceiling_div selected_count chunk in
  if ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(ranges - 1)
      (fun range ->
    let first_selected = range * chunk
    and last_selected = min selected_count ((range + 1) * chunk) in
    for slot = first_selected to last_selected - 1 do
      if slot land 4095 = 0 then Cancel.check_opt cancel;
      let primitive = selected.(slot) and output = piece_offsets.(slot) in
      let first = topology.primitive_offsets.(primitive)
      and last = topology.primitive_offsets.(primitive + 1) in
      let size = last - first
      and code = Char.code (Bytes.unsafe_get topology.primitive_kinds primitive) in
      if code = 0 then begin
        primitive_of_piece.(output) <- primitive;
        vertex_a.(output) <- first;
        vertex_b.(output) <- first + 1;
        vertex_c.(output) <- first + 2
      end else begin
        let segment_count = if code = 1 then size - 1 else size in
        for local = 0 to segment_count - 1 do
          let piece = output + local in
          Bytes.unsafe_set kinds piece '\001';
          primitive_of_piece.(piece) <- primitive;
          locals.(piece) <- local;
          vertex_a.(piece) <- first + local;
          vertex_b.(piece) <- if local + 1 < size then first + local + 1 else first;
          u0.(piece) <- float_of_int local /. float_of_int segment_count;
          u1.(piece) <- float_of_int (local + 1) /. float_of_int segment_count
        done
      end
    done);
  let centroid_x = Array.make piece_count 0.
  and centroid_y = Array.make piece_count 0.
  and centroid_z = Array.make piece_count 0.
  and piece_min_x = Array.make piece_count 0.
  and piece_min_y = Array.make piece_count 0.
  and piece_min_z = Array.make piece_count 0.
  and piece_max_x = Array.make piece_count 0.
  and piece_max_y = Array.make piece_count 0.
  and piece_max_z = Array.make piece_count 0. in
  let piece_ranges = ceiling_div piece_count grain in
  let errors = Array.make piece_ranges None in
  if piece_ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0
      ~finish:(piece_ranges - 1) (fun range ->
    let first_piece = range * grain
    and last_piece = min piece_count ((range + 1) * grain) in
    for piece = first_piece to last_piece - 1 do
      if piece land 4095 = 0 then Cancel.check_opt cancel;
      if errors.(range) = None then begin
        let primitive = primitive_of_piece.(piece) in
        let pa = topology.vertex_points.(vertex_a.(piece))
        and pb = topology.vertex_points.(vertex_b.(piece)) in
        let ax = positions.x.(pa) and ay = positions.y.(pa)
        and az = positions.z.(pa) and bx = positions.x.(pb)
        and by = positions.y.(pb) and bz = positions.z.(pb) in
        if not (finite ax && finite ay && finite az && finite bx && finite by
            && finite bz) then errors.(range) <- Some (Printf.sprintf
              "primitive %d has a non-finite position" primitive)
        else if Bytes.unsafe_get kinds piece = '\001' then begin
          if ax = bx && ay = by && az = bz then
            errors.(range) <- Some (Printf.sprintf
              "primitive %d segment %d is degenerate" primitive locals.(piece))
          else begin
            centroid_x.(piece) <- (ax *. 0.5) +. (bx *. 0.5);
            centroid_y.(piece) <- (ay *. 0.5) +. (by *. 0.5);
            centroid_z.(piece) <- (az *. 0.5) +. (bz *. 0.5);
            piece_min_x.(piece) <- Float.min ax bx;
            piece_min_y.(piece) <- Float.min ay by;
            piece_min_z.(piece) <- Float.min az bz;
            piece_max_x.(piece) <- Float.max ax bx;
            piece_max_y.(piece) <- Float.max ay by;
            piece_max_z.(piece) <- Float.max az bz
          end
        end else begin
          let pc = topology.vertex_points.(vertex_c.(piece)) in
          let cx = positions.x.(pc) and cy = positions.y.(pc)
          and cz = positions.z.(pc) in
          if not (finite cx && finite cy && finite cz) then
            errors.(range) <- Some (Printf.sprintf
              "primitive %d has a non-finite position" primitive)
          else begin
            let abx = bx -. ax and aby = by -. ay and abz = bz -. az
            and acx = cx -. ax and acy = cy -. ay and acz = cz -. az in
            let nx = (aby *. acz) -. (abz *. acy)
            and ny = (abz *. acx) -. (abx *. acz)
            and nz = (abx *. acy) -. (aby *. acx) in
            let area2 = (nx *. nx) +. (ny *. ny) +. (nz *. nz) in
            if not (finite area2) || area2 <= 1e-30 then
              errors.(range) <- Some (Printf.sprintf
                "primitive %d is degenerate" primitive)
            else begin
              centroid_x.(piece) <- (ax +. bx +. cx) /. 3.;
              centroid_y.(piece) <- (ay +. by +. cy) /. 3.;
              centroid_z.(piece) <- (az +. bz +. cz) /. 3.;
              piece_min_x.(piece) <- Float.min ax (Float.min bx cx);
              piece_min_y.(piece) <- Float.min ay (Float.min by cy);
              piece_min_z.(piece) <- Float.min az (Float.min bz cz);
              piece_max_x.(piece) <- Float.max ax (Float.max bx cx);
              piece_max_y.(piece) <- Float.max ay (Float.max by cy);
              piece_max_z.(piece) <- Float.max az (Float.max bz cz)
            end
          end
        end
      end
    done);
  let failure = ref None in
  Array.iter (fun value -> match !failure, value with
    | None, Some message -> failure := Some message
    | None, None | Some _, _ -> ()) errors;
  Option.iter (fun message -> raise (Piece_error message)) !failure;
  let subtree_nodes = Array.make (piece_count + 1) 0 in
  for count = 1 to piece_count do
    subtree_nodes.(count) <- if count <= leaf_size then 1 else
      let left_count = count / 2 in
      1 + subtree_nodes.(left_count) + subtree_nodes.(count - left_count)
  done;
  let capacity = subtree_nodes.(piece_count) in
  let min_x = Array.make capacity 0. and min_y = Array.make capacity 0.
  and min_z = Array.make capacity 0. and max_x = Array.make capacity 0.
  and max_y = Array.make capacity 0. and max_z = Array.make capacity 0.
  and left = Array.make capacity (-1) and right = Array.make capacity (-1)
  and first = Array.make capacity 0 and count = Array.make capacity 0
  and order = Array.init piece_count Fun.id in
  let rec build node range_first range_last =
    Cancel.check_opt cancel;
    min_x.(node) <- Float.infinity; min_y.(node) <- Float.infinity;
    min_z.(node) <- Float.infinity; max_x.(node) <- Float.neg_infinity;
    max_y.(node) <- Float.neg_infinity; max_z.(node) <- Float.neg_infinity;
    for at = range_first to range_last do
      let piece = order.(at) in
      if piece_min_x.(piece) < min_x.(node) then
        min_x.(node) <- piece_min_x.(piece);
      if piece_min_y.(piece) < min_y.(node) then
        min_y.(node) <- piece_min_y.(piece);
      if piece_min_z.(piece) < min_z.(node) then
        min_z.(node) <- piece_min_z.(piece);
      if piece_max_x.(piece) > max_x.(node) then
        max_x.(node) <- piece_max_x.(piece);
      if piece_max_y.(piece) > max_y.(node) then
        max_y.(node) <- piece_max_y.(piece);
      if piece_max_z.(piece) > max_z.(node) then
        max_z.(node) <- piece_max_z.(piece)
    done;
    let range_count = range_last - range_first + 1 in
    if range_count <= leaf_size then begin
      first.(node) <- range_first; count.(node) <- range_count
    end else begin
      let ex = max_x.(node) -. min_x.(node)
      and ey = max_y.(node) -. min_y.(node)
      and ez = max_z.(node) -. min_z.(node) in
      let axis = if ex >= ey && ex >= ez then 0 else if ey >= ez then 1 else 2 in
      let middle = range_first + (range_count / 2) in
      select axis centroid_x centroid_y centroid_z order range_first range_last middle;
      let left_count = middle - range_first in
      let left_node = node + 1
      and right_node = node + 1 + subtree_nodes.(left_count) in
      left.(node) <- left_node; right.(node) <- right_node;
      if range_count / 2 >= grain then ignore (Parallel.both
        (fun () -> build left_node range_first (middle - 1))
        (fun () -> build right_node middle range_last))
      else begin
        build left_node range_first (middle - 1);
        build right_node middle range_last
      end
    end in
  if piece_count > 0 then build 0 0 (piece_count - 1);
  { positions; topology; kinds; primitives = primitive_of_piece; locals;
    vertex_a; vertex_b; vertex_c; u0; u1; piece_min_x; piece_min_y; piece_min_z;
    piece_max_x; piece_max_y; piece_max_z; order; min_x; min_y; min_z; max_x;
    max_y; max_z; left; right; first; count }

let create ?cancel ?grain ?primitives geometry =
  try Ok (create_raw ?cancel ?grain ?primitives geometry) with
  | Cancel.Cancelled -> Error (Error.make ~operation:"linear_piece_index"
      ~code:"cancelled" "linear-piece index construction was cancelled")
  | Piece_error message -> Error (Error.make ~operation:"linear_piece_index"
      ~code:"invalid_surface" message)
  | Group_error message -> Error (Error.make ~operation:"linear_piece_index"
      ~code:"invalid_group" message)
  | Invalid_argument message -> Error (Error.make ~operation:"linear_piece_index"
      ~code:"invalid_parameter" message)

let piece_count value = Array.length value.primitives
let payload_bytes value =
  let word = Sys.word_size / 8 in
  ((Array.length value.primitives + Array.length value.locals
    + Array.length value.vertex_a + Array.length value.vertex_b
    + Array.length value.vertex_c + Array.length value.order
    + Array.length value.left + Array.length value.right
    + Array.length value.first + Array.length value.count) * word)
  + Bytes.length value.kinds
  + ((Array.length value.u0 + Array.length value.u1
    + Array.length value.piece_min_x + Array.length value.piece_min_y
    + Array.length value.piece_min_z + Array.length value.piece_max_x
    + Array.length value.piece_max_y + Array.length value.piece_max_z
    + Array.length value.min_x + Array.length value.min_y
    + Array.length value.min_z + Array.length value.max_x
    + Array.length value.max_y + Array.length value.max_z) * 8)

let[@inline always] bounds_overlap tolerance left right_index node left_piece =
  left.piece_min_x.(left_piece) <= right_index.max_x.(node) +. tolerance
  && left.piece_max_x.(left_piece) >= right_index.min_x.(node) -. tolerance
  && left.piece_min_y.(left_piece) <= right_index.max_y.(node) +. tolerance
  && left.piece_max_y.(left_piece) >= right_index.min_y.(node) -. tolerance
  && left.piece_min_z.(left_piece) <= right_index.max_z.(node) +. tolerance
  && left.piece_max_z.(left_piece) >= right_index.min_z.(node) -. tolerance

let[@inline always] piece_bounds_overlap tolerance left left_piece right
    right_piece =
  left.piece_min_x.(left_piece) <= right.piece_max_x.(right_piece) +. tolerance
  && left.piece_max_x.(left_piece) >= right.piece_min_x.(right_piece) -. tolerance
  && left.piece_min_y.(left_piece) <= right.piece_max_y.(right_piece) +. tolerance
  && left.piece_max_y.(left_piece) >= right.piece_min_y.(right_piece) -. tolerance
  && left.piece_min_z.(left_piece) <= right.piece_max_z.(right_piece) +. tolerance
  && left.piece_max_z.(left_piece) >= right.piece_min_z.(right_piece) -. tolerance

let overlapping_pairs_raw ?cancel ~self ~grain ~tolerance left_index right_index =
  if grain <= 0 then invalid_arg
      "Linear_piece_index.overlapping_pairs: grain must be positive";
  if not (finite tolerance) || tolerance < 0. then invalid_arg
      "Linear_piece_index.overlapping_pairs: tolerance must be finite and non-negative";
  let left_count = piece_count left_index in
  if left_count = 0 || piece_count right_index = 0 then [||], [||]
  else begin
    let chunk = max 1 grain and ranges = ceiling_div left_count (max 1 grain) in
    let counts = Array.make left_count 0 in
    let scan stack left_piece output_left output_right output_at =
      let top = ref 1 and found = ref 0 in
      stack.(0) <- 0;
      while !top > 0 do
        decr top;
        let node = stack.(!top) in
        if bounds_overlap tolerance left_index right_index node left_piece then
          if right_index.count.(node) > 0 then begin
            let last = right_index.first.(node) + right_index.count.(node) in
            for slot = right_index.first.(node) to last - 1 do
              let right_piece = right_index.order.(slot) in
              if (not self || right_piece > left_piece)
                  && piece_bounds_overlap tolerance left_index left_piece
                       right_index right_piece then begin
                (match output_left, output_right with
                 | Some left, Some right ->
                     left.(output_at + !found) <- left_piece;
                     right.(output_at + !found) <- right_piece
                 | None, None -> ()
                 | _ -> assert false);
                incr found
              end
            done
          end else begin
            stack.(!top) <- right_index.right.(node);
            stack.(!top + 1) <- right_index.left.(node);
            top := !top + 2
          end
      done;
      !found in
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(ranges - 1) (fun range ->
      let stack = Array.make 65 0 in
      let first = range * chunk and last = min left_count ((range + 1) * chunk) in
      for piece = first to last - 1 do
        if piece land 4095 = 0 then Cancel.check_opt cancel;
        counts.(piece) <- scan stack piece None None 0
      done);
    let offsets = Array.make (left_count + 1) 0 in
    for piece = 0 to left_count - 1 do
      if counts.(piece) > Sys.max_array_length - offsets.(piece) then
        invalid_arg "Linear piece candidate cardinality exceeds array limits";
      offsets.(piece + 1) <- offsets.(piece) + counts.(piece)
    done;
    let total = offsets.(left_count) in
    let left_output = Array.make total 0 and right_output = Array.make total 0 in
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(ranges - 1) (fun range ->
      let stack = Array.make 65 0 in
      let first = range * chunk and last = min left_count ((range + 1) * chunk) in
      for piece = first to last - 1 do
        if piece land 4095 = 0 then Cancel.check_opt cancel;
        let written = scan stack piece (Some left_output) (Some right_output)
            offsets.(piece) in
        if written <> counts.(piece) then invalid_arg
            "Linear piece candidate count/fill drift"
      done);
    left_output, right_output
  end

let find_overlapping_self_pair_raw ?cancel ~grain ~tolerance index predicate =
  if grain <= 0 then invalid_arg
      "Linear_piece_index.find_overlapping_self_pair: grain must be positive";
  if not (finite tolerance) || tolerance < 0. then invalid_arg
      "Linear_piece_index.find_overlapping_self_pair: tolerance must be finite and non-negative";
  let pieces = piece_count index in
  if pieces = 0 then None
  else begin
    let ranges = ceiling_div pieces grain in
    let found_left = Array.make ranges (-1) and found_right = Array.make ranges (-1) in
    Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(ranges - 1) (fun range ->
      let stack = Array.make 65 0
      and last_piece = min pieces ((range + 1) * grain)
      and left_piece = ref (range * grain) in
      while found_left.(range) < 0 && !left_piece < last_piece do
        if !left_piece land 4095 = 0 then Cancel.check_opt cancel;
        let top = ref 1 and best_right = ref (-1) in
        stack.(0) <- 0;
        while !top > 0 do
          decr top;
          let node = stack.(!top) in
          if node land 4095 = 0 then Cancel.check_opt cancel;
          if bounds_overlap tolerance index index node !left_piece then
            if index.count.(node) > 0 then begin
              let last = index.first.(node) + index.count.(node) in
              for slot = index.first.(node) to last - 1 do
                let right_piece = index.order.(slot) in
                if right_piece > !left_piece
                    && (right_piece < !best_right || !best_right < 0)
                    && piece_bounds_overlap tolerance index !left_piece
                         index right_piece
                    && predicate !left_piece right_piece then
                  best_right := right_piece
              done
            end else begin
              stack.(!top) <- index.right.(node);
              stack.(!top + 1) <- index.left.(node);
              top := !top + 2
            end
        done;
        if !best_right >= 0 then begin
          found_left.(range) <- !left_piece;
          found_right.(range) <- !best_right
        end;
        incr left_piece
      done);
    let range = ref 0 in
    while !range < ranges && found_left.(!range) < 0 do incr range done;
    if !range = ranges then None
    else Some (found_left.(!range), found_right.(!range))
  end

module Private = struct
  let[@inline always] kind value piece =
    if Bytes.unsafe_get value.kinds piece = '\000' then Triangle else Segment
  let[@inline always] primitive value piece = value.primitives.(piece)
  let[@inline always] local value piece = value.locals.(piece)
  let[@inline always] vertex value piece corner = match corner with
    | 0 -> value.vertex_a.(piece)
    | 1 -> value.vertex_b.(piece)
    | 2 when Bytes.unsafe_get value.kinds piece = '\000' -> value.vertex_c.(piece)
    | _ -> invalid_arg "Linear_piece_index.vertex: invalid local corner"
  let[@inline always] point value piece corner =
    value.topology.vertex_points.(vertex value piece corner)
  let[@inline always] curve_u value piece endpoint = match endpoint with
    | 0 -> value.u0.(piece) | 1 -> value.u1.(piece)
    | _ -> invalid_arg "Linear_piece_index.curve_u: invalid endpoint"
  let positions value = value.positions
  let overlapping_pairs ?cancel ~grain ~tolerance left right =
    overlapping_pairs_raw ?cancel ~self:false ~grain ~tolerance left right
  let overlapping_self_pairs ?cancel ~grain ~tolerance value =
    overlapping_pairs_raw ?cancel ~self:true ~grain ~tolerance value value
  let find_overlapping_self_pair ?cancel ~grain ~tolerance value predicate =
    find_overlapping_self_pair_raw ?cancel ~grain ~tolerance value predicate
end
