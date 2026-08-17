open Prismel

type method_ =
  | First
  | Last
  | Average
  | Minimum
  | Maximum
  | Mode
  | Median
  | Sum
  | Sum_squares
  | Root_mean_square
  | Array_all
  | Unique_values

type relation =
  | Identity of int
  | Constant_zero of int
  | Direct of int array
  | All of { source_count : int }
  | Csr_identity of { offsets : int array }
  | Csr_map of { offsets : int array; indices : int array }

module String_key = Hashtbl.Make (struct
  type t = string
  let equal = String.equal
  let hash = Hashtbl.hash
end)

let owner_count geometry = function
  | Attribute.Point -> Geometry.point_count geometry
  | Attribute.Vertex -> Geometry.vertex_count geometry
  | Attribute.Primitive -> Geometry.primitive_count geometry
  | Attribute.Detail -> 1

let relation_count = function
  | Identity count | Constant_zero count -> count
  | Direct values -> Array.length values
  | All _ -> 1
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> Array.length offsets - 1

let relation_first relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> 0
  | All _ -> 0
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination)

let relation_last relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> 1
  | All { source_count } -> source_count
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination + 1)

let relation_source relation destination slot = match relation with
  | Identity _ -> destination
  | Constant_zero _ -> 0
  | Direct values -> values.(destination)
  | All _ | Csr_identity _ -> slot
  | Csr_map { indices; _ } -> indices.(slot)

let relation_incidence_count = function
  | Identity count | Constant_zero count -> count
  | Direct values -> Array.length values
  | All { source_count } -> source_count
  | Csr_identity { offsets } | Csr_map { offsets; _ } ->
      offsets.(Array.length offsets - 1)

let relation_flat_first relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> destination
  | All _ -> 0
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination)

let relation_flat_last relation destination = match relation with
  | Identity _ | Constant_zero _ | Direct _ -> destination + 1
  | All { source_count } -> source_count
  | Csr_identity { offsets } | Csr_map { offsets; _ } -> offsets.(destination + 1)

let relation_source_flat relation destination slot = match relation with
  | Identity _ -> destination
  | Constant_zero _ -> 0
  | Direct values -> values.(destination)
  | All _ | Csr_identity _ -> slot
  | Csr_map { indices; _ } -> indices.(slot)

let sort_int_range ?cancel values first last =
  let swap left right =
    let value = values.(left) in
    values.(left) <- values.(right);
    values.(right) <- value
  in
  let sift root finish =
    let root = ref root and active = ref true in
    while !active do
      let child = ((!root - first) * 2) + 1 + first in
      if child >= finish then active := false
      else begin
        let child = if child + 1 < finish
            && values.(child) < values.(child + 1) then child + 1 else child in
        if values.(!root) < values.(child) then begin
          swap !root child;
          root := child
        end else active := false
      end
    done
  in
  let length = last - first in
  if length < 16 then
    for at = first + 1 to last - 1 do
      if at land 4095 = 0 then Cancel.check_opt cancel;
      let value = values.(at) and slot = ref at in
      while !slot > first && values.(!slot - 1) > value do
        values.(!slot) <- values.(!slot - 1);
        decr slot
      done;
      values.(!slot) <- value
    done
  else begin
    for root = first + (length / 2) - 1 downto first do
      if root land 4095 = 0 then Cancel.check_opt cancel;
      sift root last
    done;
    for finish = last - 1 downto first + 1 do
      if finish land 4095 = 0 then Cancel.check_opt cancel;
      swap first finish;
      sift first finish
    done
  end

let sort_float_range ?cancel values first last =
  let swap left right =
    let value = values.(left) in
    values.(left) <- values.(right);
    values.(right) <- value
  in
  let sift root finish =
    let root = ref root and active = ref true in
    while !active do
      let child = ((!root - first) * 2) + 1 + first in
      if child >= finish then active := false
      else begin
        let child = if child + 1 < finish
            && Float.compare values.(child) values.(child + 1) < 0
          then child + 1 else child in
        if Float.compare values.(!root) values.(child) < 0 then begin
          swap !root child;
          root := child
        end else active := false
      end
    done
  in
  let length = last - first in
  if length < 16 then
    for at = first + 1 to last - 1 do
      if at land 4095 = 0 then Cancel.check_opt cancel;
      let value = values.(at) and slot = ref at in
      while !slot > first && Float.compare values.(!slot - 1) value > 0 do
        values.(!slot) <- values.(!slot - 1);
        decr slot
      done;
      values.(!slot) <- value
    done
  else begin
    for root = first + (length / 2) - 1 downto first do
      if root land 4095 = 0 then Cancel.check_opt cancel;
      sift root last
    done;
    for finish = last - 1 downto first + 1 do
      if finish land 4095 = 0 then Cancel.check_opt cancel;
      swap first finish;
      sift first finish
    done
  end

let sort_text_range ?cancel values first last =
  let swap left right =
    let value = values.(left) in
    values.(left) <- values.(right);
    values.(right) <- value
  in
  let sift root finish =
    let root = ref root and active = ref true in
    while !active do
      let child = ((!root - first) * 2) + 1 + first in
      if child >= finish then active := false
      else begin
        let child = if child + 1 < finish
            && String.compare values.(child) values.(child + 1) < 0
          then child + 1 else child in
        if String.compare values.(!root) values.(child) < 0 then begin
          swap !root child;
          root := child
        end else active := false
      end
    done
  in
  let length = last - first in
  if length < 16 then
    for at = first + 1 to last - 1 do
      if at land 4095 = 0 then Cancel.check_opt cancel;
      let value = values.(at) and slot = ref at in
      while !slot > first && String.compare values.(!slot - 1) value > 0 do
        values.(!slot) <- values.(!slot - 1);
        decr slot
      done;
      values.(!slot) <- value
    done
  else begin
    for root = first + (length / 2) - 1 downto first do
      if root land 4095 = 0 then Cancel.check_opt cancel;
      sift root last
    done;
    for finish = last - 1 downto first + 1 do
      if finish land 4095 = 0 then Cancel.check_opt cancel;
      swap first finish;
      sift first finish
    done
  end

let select_range ?cancel ~compare ~sort values first last nth =
  let swap left right =
    let value = values.(left) in
    values.(left) <- values.(right);
    values.(right) <- value
  in
  let median_of_three left middle right =
    let a = values.(left) and b = values.(middle) and c = values.(right) in
    if compare a b <= 0 then
      if compare b c <= 0 then b else if compare a c <= 0 then c else a
    else if compare a c <= 0 then a else if compare b c <= 0 then c else b
  in
  let rec logarithm value result =
    if value <= 1 then result else logarithm (value lsr 1) (result + 1)
  in
  let left = ref first and right = ref last
  and budget = ref (2 * logarithm (last - first) 0)
  and selected = ref false in
  while not !selected && !right - !left > 16 && !budget > 0 do
    Cancel.check_opt cancel;
    decr budget;
    let pivot = median_of_three !left (!left + ((!right - !left) / 2))
        (!right - 1) in
    let lower = ref !left and scan = ref !left and upper = ref !right in
    while !scan < !upper do
      if !scan land 16_383 = 0 then Cancel.check_opt cancel;
      let order = compare values.(!scan) pivot in
      if order < 0 then begin
        swap !lower !scan;
        incr lower;
        incr scan
      end else if order > 0 then begin
        decr upper;
        swap !scan !upper
      end else incr scan
    done;
    if nth < !lower then right := !lower
    else if nth >= !upper then left := !upper
    else selected := true
  done;
  if not !selected then sort values !left !right;
  values.(nth)

let mode_sorted ?cancel compare values first last =
  let best = ref first and best_count = ref 1 and run = ref first in
  for slot = first + 1 to last do
    if slot land 16_383 = 0 then Cancel.check_opt cancel;
    if slot = last || compare values.(slot) values.(!run) <> 0 then begin
      let count = slot - !run in
      if count > !best_count then begin
        best := !run;
        best_count := count
      end;
      run := slot
    end
  done;
  values.(!best)

let mode_int_range ?cancel values first last =
  let length = last - first in
  if length < 4_096 then begin
    sort_int_range ?cancel values first last;
    mode_sorted ?cancel Int.compare values first last
  end else begin
    let minimum = ref values.(first) and maximum = ref values.(first) in
    for slot = first + 1 to last - 1 do
      if slot land 16_383 = 0 then Cancel.check_opt cancel;
      minimum := Int.min !minimum values.(slot);
      maximum := Int.max !maximum values.(slot)
    done;
    let span = Int64.(add (sub (of_int !maximum) (of_int !minimum)) 1L) in
    let dense_limit = if length > Sys.max_array_length / 2
        then Sys.max_array_length else length * 2 in
    if span > 0L && span <= Int64.of_int dense_limit
    then begin
      let counts = Array.make (Int64.to_int span) 0 in
      for slot = first to last - 1 do
        let bucket = values.(slot) - !minimum in
        counts.(bucket) <- counts.(bucket) + 1
      done;
      let best = ref 0 in
      for bucket = 1 to Array.length counts - 1 do
        if counts.(bucket) > counts.(!best) then best := bucket
      done;
      !minimum + !best
    end else begin
      sort_int_range ?cancel values first last;
      mode_sorted ?cancel Int.compare values first last
    end
  end

let reduction_chunk_size ~grain relation =
  let destinations = relation_count relation in
  if destinations = 0 then grain
  else
    let incidences = relation_incidence_count relation in
    let average = max 1 ((incidences + destinations - 1) / destinations) in
    max 1 (grain / average)

let fill_incidence_plane ?cancel ~grain ~default relation source =
  let count = relation_count relation in
  let values = Array.make (relation_incidence_count relation) default in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        for slot = first to last - 1 do
          if slot land 16_383 = 0 then Cancel.check_opt cancel;
          values.(slot) <- source.(relation_source_flat relation destination slot)
        done);
  values

let radix_sort_nonnegative ?cancel values =
  let length = Array.length values in
  if length < 2 then ()
  else if length < 4_096 then Array.sort Int.compare values
  else begin
    let maximum = Array.fold_left Int.max 0 values in
    let rec pass_count value count =
      if value = 0 then max 1 count else pass_count (value lsr 16) (count + 1)
    in
    let passes = pass_count maximum 0 in
    let scratch = Array.make length 0 and counts = Array.make 65_536 0 in
    let source = ref values and target = ref scratch in
    for pass = 0 to passes - 1 do
      Cancel.check_opt cancel;
      Array.fill counts 0 (Array.length counts) 0;
      let shift = pass * 16 in
      for at = 0 to length - 1 do
        if at land 16_383 = 0 then Cancel.check_opt cancel;
        let bucket = ((!source).(at) lsr shift) land 0xffff in
        counts.(bucket) <- counts.(bucket) + 1
      done;
      let offset = ref 0 in
      for bucket = 0 to Array.length counts - 1 do
        let size = counts.(bucket) in
        counts.(bucket) <- !offset;
        offset := !offset + size
      done;
      for at = 0 to length - 1 do
        let value = (!source).(at) in
        let bucket = (value lsr shift) land 0xffff in
        (!target).(counts.(bucket)) <- value;
        counts.(bucket) <- counts.(bucket) + 1
      done;
      let previous = !source in
      source := !target;
      target := previous
    done;
    if !source != values then Array.blit !source 0 values 0 length
  end

let primitive_to_point ?cancel geometry index =
  let index_view = Topology_index.Private.view index in
  let point_count = Geometry.point_count geometry in
  let offsets = Array.make (point_count + 1) 0 in
  for point = 0 to point_count - 1 do
    if point land 4095 = 0 then Cancel.check_opt cancel;
    let first = index_view.point_offsets.(point)
    and last = index_view.point_offsets.(point + 1)
    and previous = ref (-1) in
    for slot = first to last - 1 do
      let primitive = index_view.primitive_of_vertex.(index_view.point_vertices.(slot)) in
      if primitive <> !previous then begin
        offsets.(point + 1) <- offsets.(point + 1) + 1;
        previous := primitive
      end
    done
  done;
  for point = 0 to point_count - 1 do
    offsets.(point + 1) <- offsets.(point + 1) + offsets.(point)
  done;
  let indices = Array.make offsets.(point_count) 0 in
  for point = 0 to point_count - 1 do
    let output = ref offsets.(point) and previous = ref (-1) in
    for slot = index_view.point_offsets.(point)
        to index_view.point_offsets.(point + 1) - 1 do
      let primitive = index_view.primitive_of_vertex.(index_view.point_vertices.(slot)) in
      if primitive <> !previous then begin
        indices.(!output) <- primitive;
        incr output;
        previous := primitive
      end
    done
  done;
  Csr_map { offsets; indices }

let make_relation ?cancel ~source ~destination geometry =
  let topology = Geometry.topology geometry
  and topology_view = Topology.Private.view (Geometry.topology geometry) in
  if source = destination then Identity (owner_count geometry destination)
  else match source, destination with
  | Attribute.Detail, destination -> Constant_zero (owner_count geometry destination)
  | source, Attribute.Detail -> All { source_count = owner_count geometry source }
  | Attribute.Point, Attribute.Vertex -> Direct topology_view.vertex_points
  | Attribute.Primitive, Attribute.Vertex ->
      let index = Topology_index.create ?cancel topology in
      Direct (Topology_index.Private.view index).primitive_of_vertex
  | Attribute.Vertex, Attribute.Point ->
      let index = Topology_index.create ?cancel topology in
      let view = Topology_index.Private.view index in
      Csr_map { offsets = view.point_offsets; indices = view.point_vertices }
  | Attribute.Vertex, Attribute.Primitive ->
      Csr_identity { offsets = topology_view.primitive_offsets }
  | Attribute.Point, Attribute.Primitive ->
      Csr_map { offsets = topology_view.primitive_offsets;
                indices = topology_view.vertex_points }
  | Attribute.Primitive, Attribute.Point ->
      let index = Topology_index.create ?cancel topology in
      primitive_to_point ?cancel geometry index
  | (Attribute.Point, Attribute.Point)
  | (Attribute.Vertex, Attribute.Vertex)
  | (Attribute.Primitive, Attribute.Primitive) ->
      Identity (owner_count geometry destination)

let table_capacity count =
  if count > Sys.max_array_length / 2 then
    invalid_arg "Pdk.Attribute_ops.promote: piece table is too large";
  let target = max 16 (count * 2) in
  let rec grow value =
    if value >= target then value
    else if value > Sys.max_array_length / 2 then
      invalid_arg "Pdk.Attribute_ops.promote: piece table is too large"
    else grow (value * 2)
  in
  grow 16

let int_piece_ids values =
  let count = Array.length values in
  if count = 0 then [||], 0
  else begin
    let minimum = ref values.(0) and maximum = ref values.(0) in
    for at = 1 to count - 1 do
      minimum := Int.min !minimum values.(at);
      maximum := Int.max !maximum values.(at)
    done;
    let span = Int64.(add (sub (of_int !maximum) (of_int !minimum)) 1L) in
    let dense_limit = min Sys.max_array_length
        (if count > Sys.max_array_length / 2 then Sys.max_array_length
         else max 16 (count * 2)) in
    let output = Array.make count 0 and next = ref 0 in
    if span > 0L && span <= Int64.of_int dense_limit then begin
      let ids = Array.make (Int64.to_int span) (-1) in
      for at = 0 to count - 1 do
        let slot = values.(at) - !minimum in
        if ids.(slot) < 0 then begin
          ids.(slot) <- !next;
          incr next
        end;
        output.(at) <- ids.(slot)
      done
    end else begin
      let capacity = table_capacity count in
      let keys = Array.make capacity 0 and ids = Array.make capacity (-1) in
      let mask = capacity - 1 in
      for at = 0 to count - 1 do
        let key = values.(at) in
        let hash = ((key lxor (key lsr 16)) * 0x45d9f3b) land max_int in
        let slot = ref (hash land mask) in
        while ids.(!slot) >= 0 && keys.(!slot) <> key do
          slot := (!slot + 1) land mask
        done;
        if ids.(!slot) < 0 then begin
          keys.(!slot) <- key;
          ids.(!slot) <- !next;
          incr next
        end;
        output.(at) <- ids.(!slot)
      done
    end;
    output, !next
  end

let text_piece_ids values =
  let count = Array.length values in
  let table = String_key.create (max 16 (min count 4_096)) and next = ref 0 in
  let output = Array.make count 0 in
  for at = 0 to count - 1 do
    let key = values.(at) in
    let id = match String_key.find_opt table key with
      | Some id -> id
      | None ->
          let id = !next in
          incr next;
          String_key.add table key id;
          id
    in
    output.(at) <- id
  done;
  output, !next

let make_piece_relation ?cancel ~source_count ~piece_attribute base_relation =
  let piece_of_destination, piece_count =
    match Attribute.Private.storage piece_attribute with
    | Attribute.Int values -> int_piece_ids values
    | Attribute.Text values -> text_piece_ids values
    | Attribute.Float _ | Attribute.Float2 _ | Attribute.Float3 _
    | Attribute.Float4 _ | Attribute.Int_array _ | Attribute.Float_array _ ->
        raise (Invalid_argument
          "Pdk.Attribute_ops.promote: piece attribute must use integer or text storage")
  in
  match base_relation with
  | Identity count ->
      let offsets = Array.make (piece_count + 1) 0 in
      for destination = 0 to count - 1 do
        if destination land 16_383 = 0 then Cancel.check_opt cancel;
        let piece = piece_of_destination.(destination) in
        offsets.(piece + 1) <- offsets.(piece + 1) + 1
      done;
      for piece = 0 to piece_count - 1 do
        offsets.(piece + 1) <- offsets.(piece + 1) + offsets.(piece)
      done;
      let cursors = Array.copy offsets and indices = Array.make count 0 in
      for destination = 0 to count - 1 do
        let piece = piece_of_destination.(destination) in
        indices.(cursors.(piece)) <- destination;
        cursors.(piece) <- cursors.(piece) + 1
      done;
      Csr_map { offsets; indices }, piece_of_destination
  | Constant_zero _ | Direct _ | All _ | Csr_identity _ | Csr_map _ ->
      if source_count > 0 && piece_count > max_int / source_count then
        invalid_arg "Pdk.Attribute_ops.promote: piece/source key space is too large";
      let pair_count = relation_incidence_count base_relation in
      let pairs = Array.make pair_count 0 in
      for destination = 0 to relation_count base_relation - 1 do
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let piece = piece_of_destination.(destination) in
        for slot = relation_flat_first base_relation destination
            to relation_flat_last base_relation destination - 1 do
          let source = relation_source_flat base_relation destination slot in
          pairs.(slot) <- (piece * source_count) + source
        done
      done;
      radix_sort_nonnegative ?cancel pairs;
      let unique_count = ref 0 and previous = ref (-1) in
      let offsets = Array.make (piece_count + 1) 0 in
      for at = 0 to pair_count - 1 do
        let key = pairs.(at) in
        if key <> !previous then begin
          incr unique_count;
          offsets.((key / source_count) + 1) <-
            offsets.((key / source_count) + 1) + 1;
          previous := key
        end
      done;
      for piece = 0 to piece_count - 1 do
        offsets.(piece + 1) <- offsets.(piece + 1) + offsets.(piece)
      done;
      let indices = Array.make !unique_count 0 in
      let output = ref 0 in
      previous := -1;
      for at = 0 to pair_count - 1 do
        let key = pairs.(at) in
        if key <> !previous then begin
          indices.(!output) <- key mod source_count;
          incr output;
          previous := key
        end
      done;
      Csr_map { offsets; indices }, piece_of_destination

let reduce_float ?cancel method_ relation source destination =
  let first = relation_first relation destination
  and last = relation_last relation destination in
  if first = last then 0.
  else match method_ with
  | First -> source.(relation_source relation destination first)
  | Last -> source.(relation_source relation destination (last - 1))
  | Minimum | Maximum ->
      let result = ref source.(relation_source relation destination first) in
      for slot = first + 1 to last - 1 do
        if slot land 16_383 = 0 then Cancel.check_opt cancel;
        let value = source.(relation_source relation destination slot) in
        result := (if method_ = Minimum then Float.min !result value
                   else Float.max !result value)
      done;
      !result
  | Mode | Median | Array_all | Unique_values -> assert false
  | Average | Sum | Sum_squares | Root_mean_square ->
      let result = ref 0. in
      for slot = first to last - 1 do
        if slot land 16_383 = 0 then Cancel.check_opt cancel;
        let value = source.(relation_source relation destination slot) in
        result := !result +. (if method_ = Sum_squares || method_ = Root_mean_square
                              then value *. value else value)
      done;
      (match method_ with
      | Average -> !result /. float_of_int (last - first)
      | Root_mean_square -> sqrt (!result /. float_of_int (last - first))
      | Sum | Sum_squares -> !result
      | First | Last | Minimum | Maximum | Mode | Median
      | Array_all | Unique_values -> assert false)

let reduce_int ?cancel method_ relation source destination =
  let first = relation_first relation destination
  and last = relation_last relation destination in
  if first = last then 0
  else match method_ with
  | First -> source.(relation_source relation destination first)
  | Last -> source.(relation_source relation destination (last - 1))
  | Minimum | Maximum ->
      let result = ref source.(relation_source relation destination first) in
      for slot = first + 1 to last - 1 do
        if slot land 16_383 = 0 then Cancel.check_opt cancel;
        let value = source.(relation_source relation destination slot) in
        result := (if method_ = Minimum then Int.min !result value
                   else Int.max !result value)
      done;
      !result
  | Average | Sum | Sum_squares | Root_mean_square | Mode | Median
  | Array_all | Unique_values -> assert false

let reduce_text method_ relation source destination =
  let first = relation_first relation destination
  and last = relation_last relation destination in
  if first = last then ""
  else match method_ with
  | First -> source.(relation_source relation destination first)
  | Last -> source.(relation_source relation destination (last - 1))
  | Average | Minimum | Maximum | Mode | Median | Sum | Sum_squares
  | Root_mean_square | Array_all | Unique_values -> assert false

let sorted_float_plane ?cancel ~grain method_ relation source =
  let count = relation_count relation and output = Array.make (relation_count relation) 0. in
  let values = fill_incidence_plane ?cancel ~grain ~default:0. relation source in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        if first < last then begin
          output.(destination) <- match method_ with
            | Median -> select_range ?cancel ~compare:Float.compare
                ~sort:(sort_float_range ?cancel) values first last
                (first + ((last - first) / 2))
            | Mode ->
                sort_float_range ?cancel values first last;
                mode_sorted ?cancel Float.compare values first last
            | First | Last | Average | Minimum | Maximum | Sum | Sum_squares
            | Root_mean_square | Array_all | Unique_values -> assert false
        end);
  output

let sorted_int_plane ?cancel ~grain method_ relation source =
  let count = relation_count relation and output = Array.make (relation_count relation) 0 in
  let values = fill_incidence_plane ?cancel ~grain ~default:0 relation source in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        if first < last then begin
          output.(destination) <- match method_ with
            | Median -> select_range ?cancel ~compare:Int.compare
                ~sort:(sort_int_range ?cancel) values first last
                (first + ((last - first) / 2))
            | Mode -> mode_int_range ?cancel values first last
            | First | Last | Average | Minimum | Maximum | Sum | Sum_squares
            | Root_mean_square | Array_all | Unique_values -> assert false
        end);
  output

let sorted_text_plane ?cancel ~grain method_ relation source =
  let count = relation_count relation and output = Array.make (relation_count relation) "" in
  let values = fill_incidence_plane ?cancel ~grain ~default:"" relation source in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        if first < last then begin
          output.(destination) <- match method_ with
            | Median -> select_range ?cancel ~compare:String.compare
                ~sort:(sort_text_range ?cancel) values first last
                (first + ((last - first) / 2))
            | Mode ->
                sort_text_range ?cancel values first last;
                mode_sorted ?cancel String.compare values first last
            | First | Last | Average | Minimum | Maximum | Sum | Sum_squares
            | Root_mean_square | Array_all | Unique_values -> assert false
        end);
  output

let float_plane ?cancel ~grain method_ relation source =
  match method_ with
  | Mode | Median -> sorted_float_plane ?cancel ~grain method_ relation source
  | First | Last | Average | Minimum | Maximum | Sum | Sum_squares
  | Root_mean_square ->
      let count = relation_count relation
      and output = Array.make (relation_count relation) 0. in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            output.(destination) <- reduce_float ?cancel method_ relation source
                destination);
      output
  | Array_all | Unique_values -> assert false

let int_plane ?cancel ~grain method_ relation source =
  match method_ with
  | Mode | Median -> sorted_int_plane ?cancel ~grain method_ relation source
  | First | Last | Minimum | Maximum ->
      let count = relation_count relation and output = Array.make (relation_count relation) 0 in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            output.(destination) <- reduce_int ?cancel method_ relation source
                destination);
      output
  | Average | Sum | Sum_squares | Root_mean_square
  | Array_all | Unique_values -> assert false

let text_plane ?cancel ~grain method_ relation source =
  match method_ with
  | Mode | Median | Average -> sorted_text_plane ?cancel ~grain
      (if method_ = Average then Median else method_) relation source
  | Sum ->
      let count = relation_count relation in
      let output = Array.make count "" in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1) (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            let first = relation_first relation destination
            and last = relation_last relation destination
            and length = ref 0 in
            for slot = first to last - 1 do
              if slot land 16_383 = 0 then Cancel.check_opt cancel;
              let source_index = relation_source relation destination slot in
              let source_length = String.length source.(source_index) in
              if source_length > Sys.max_string_length - !length then
                invalid_arg
                  "Pdk.Attribute_ops.promote: concatenated text exceeds string limits";
              length := !length + source_length
            done;
            if !length > 0 then begin
              let bytes = Bytes.create !length and at = ref 0 in
              for slot = first to last - 1 do
                let value = source.(relation_source relation destination slot) in
                let length = String.length value in
                Bytes.blit_string value 0 bytes !at length;
                at := !at + length
              done;
              output.(destination) <- Bytes.unsafe_to_string bytes
            end);
      output
  | First | Last | Minimum | Maximum | Sum_squares | Root_mean_square ->
      let count = relation_count relation
      and output = Array.make (relation_count relation) "" in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            output.(destination) <- reduce_text
                (if method_ = Last then Last else First) relation source destination);
      output
  | Array_all | Unique_values ->
      assert false

let indexed_method = function
  | First | Last | Minimum | Maximum | Mode -> true
  | Average | Median | Sum | Sum_squares | Root_mean_square
  | Array_all | Unique_values -> false

let indexed_float_plane ?cancel ~grain method_ relation source =
  match method_ with
  | Mode ->
      let output = sorted_float_plane ?cancel ~grain Mode relation source
      and indices = Array.make (relation_count relation) (-1) in
      let count = relation_count relation in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            let first = relation_first relation destination
            and last = relation_last relation destination
            and found = ref (-1) in
            let slot = ref first in
            while !slot < last && !found < 0 do
              if !slot land 16_383 = 0 then Cancel.check_opt cancel;
              let source_index = relation_source relation destination !slot in
              if Float.compare source.(source_index) output.(destination) = 0
              then found := source_index;
              incr slot
            done;
            indices.(destination) <- !found);
      output, indices
  | First | Last | Minimum | Maximum ->
      let count = relation_count relation
      and output = Array.make (relation_count relation) 0.
      and indices = Array.make (relation_count relation) (-1) in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            let first = relation_first relation destination
            and last = relation_last relation destination in
            if first < last then begin
              let slot = if method_ = Last then last - 1 else first in
              let source_index = ref (relation_source relation destination slot) in
              let value = ref source.(!source_index) in
              if method_ = Minimum || method_ = Maximum then
                for slot = first + 1 to last - 1 do
                  if slot land 16_383 = 0 then Cancel.check_opt cancel;
                  let candidate_index = relation_source relation destination slot in
                  let candidate = source.(candidate_index) in
                  let reduced = if method_ = Minimum
                      then Float.min !value candidate
                      else Float.max !value candidate in
                  if Int64.bits_of_float reduced
                      <> Int64.bits_of_float !value then
                    source_index := candidate_index;
                  value := reduced
                done;
              output.(destination) <- !value;
              indices.(destination) <- !source_index
            end);
      output, indices
  | Average | Median | Sum | Sum_squares | Root_mean_square
  | Array_all | Unique_values -> assert false

let indexed_int_plane ?cancel ~grain method_ relation source =
  match method_ with
  | Mode ->
      let output = sorted_int_plane ?cancel ~grain Mode relation source
      and indices = Array.make (relation_count relation) (-1) in
      let count = relation_count relation in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            let first = relation_first relation destination
            and last = relation_last relation destination
            and found = ref (-1) and slot = ref 0 in
            slot := first;
            while !slot < last && !found < 0 do
              if !slot land 16_383 = 0 then Cancel.check_opt cancel;
              let source_index = relation_source relation destination !slot in
              if source.(source_index) = output.(destination)
              then found := source_index;
              incr slot
            done;
            indices.(destination) <- !found);
      output, indices
  | First | Last | Minimum | Maximum ->
      let count = relation_count relation
      and output = Array.make (relation_count relation) 0
      and indices = Array.make (relation_count relation) (-1) in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            let first = relation_first relation destination
            and last = relation_last relation destination in
            if first < last then begin
              let slot = if method_ = Last then last - 1 else first in
              let source_index = ref (relation_source relation destination slot) in
              let value = ref source.(!source_index) in
              if method_ = Minimum || method_ = Maximum then
                for slot = first + 1 to last - 1 do
                  if slot land 16_383 = 0 then Cancel.check_opt cancel;
                  let candidate_index = relation_source relation destination slot in
                  let candidate = source.(candidate_index) in
                  if (method_ = Minimum && candidate < !value)
                      || (method_ = Maximum && candidate > !value) then begin
                    value := candidate;
                    source_index := candidate_index
                  end
                done;
              output.(destination) <- !value;
              indices.(destination) <- !source_index
            end);
      output, indices
  | Average | Median | Sum | Sum_squares | Root_mean_square
  | Array_all | Unique_values -> assert false

let indexed_text_plane ?cancel ~grain method_ relation source =
  match method_ with
  | Mode ->
      let output = sorted_text_plane ?cancel ~grain Mode relation source
      and indices = Array.make (relation_count relation) (-1) in
      let count = relation_count relation in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            let first = relation_first relation destination
            and last = relation_last relation destination
            and found = ref (-1) and slot = ref 0 in
            slot := first;
            while !slot < last && !found < 0 do
              if !slot land 16_383 = 0 then Cancel.check_opt cancel;
              let source_index = relation_source relation destination !slot in
              if String.equal source.(source_index) output.(destination)
              then found := source_index;
              incr slot
            done;
            indices.(destination) <- !found);
      output, indices
  | First | Last | Minimum | Maximum ->
      let count = relation_count relation
      and output = Array.make (relation_count relation) ""
      and indices = Array.make (relation_count relation) (-1) in
      if count > 0 then Parallel.for_
          ~chunk_size:(reduction_chunk_size ~grain relation)
          ~start:0 ~finish:(count - 1)
          (fun destination ->
            if destination land 4095 = 0 then Cancel.check_opt cancel;
            let first = relation_first relation destination
            and last = relation_last relation destination in
            if first < last then begin
              let slot = if method_ = Last then last - 1 else first in
              let source_index = relation_source relation destination slot in
              output.(destination) <- source.(source_index);
              indices.(destination) <- source_index
            end);
      output, indices
  | Average | Median | Sum | Sum_squares
  | Root_mean_square | Array_all | Unique_values -> assert false

let fixed_int_tuple_array ?cancel ~grain components =
  let width = Array.length components in
  if width = 0 then invalid_arg
      "Pdk.Attribute_ops.promote: integer tuple width must be positive";
  let count = Array.length components.(0) in
  Array.iter (fun component ->
    if Array.length component <> count then invalid_arg
        "Pdk.Attribute_ops.promote: integer tuple component lengths differ")
    components;
  if count > Sys.max_array_length / width then invalid_arg
      "Pdk.Attribute_ops.promote: integer tuple index output is too large";
  let offsets = Array.init (count + 1) (fun destination -> destination * width)
  and values = Array.make (count * width) (-1) in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = destination * width in
        for component = 0 to width - 1 do
          values.(first + component) <- components.(component).(destination)
        done);
  Packed.Int_array.Private.create_validated_owned ~offsets ~values

let map_plane ?cancel ~grain mapping values default =
  let count = Array.length mapping and output = Array.make (Array.length mapping) default in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        output.(destination) <- values.(mapping.(destination)));
  output

let relation_offsets relation =
  let count = relation_count relation in
  Array.init (count + 1) (fun destination ->
    if destination = count then relation_incidence_count relation
    else relation_flat_first relation destination)

let int_array_all ?cancel ~grain relation source =
  let offsets = relation_offsets relation
  and values = fill_incidence_plane ?cancel ~grain ~default:0 relation source in
  Packed.Int_array.Private.create_validated_owned ~offsets ~values

let float_array_all ?cancel ~grain relation source =
  let offsets = relation_offsets relation
  and values = fill_incidence_plane ?cancel ~grain ~default:0. relation source in
  Packed.Float_array.Private.create_validated_owned ~offsets ~values

let int_array_unique ?cancel ~grain relation source =
  let count = relation_count relation
  and sorted = fill_incidence_plane ?cancel ~grain ~default:0 relation source in
  let counts = Array.make count 0 in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1) (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        sort_int_range ?cancel sorted first last;
        if first < last then begin
          let unique = ref 1 in
          for slot = first + 1 to last - 1 do
            if slot land 16_383 = 0 then Cancel.check_opt cancel;
            if sorted.(slot) <> sorted.(slot - 1) then incr unique
          done;
          counts.(destination) <- !unique
        end);
  let offsets = Array.make (count + 1) 0 in
  for destination = 0 to count - 1 do
    offsets.(destination + 1) <- offsets.(destination) + counts.(destination)
  done;
  let values = Array.make offsets.(count) 0 in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1) (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        if first < last then begin
          let output = ref offsets.(destination) in
          values.(!output) <- sorted.(first);
          incr output;
          for slot = first + 1 to last - 1 do
            if slot land 16_383 = 0 then Cancel.check_opt cancel;
            if sorted.(slot) <> sorted.(slot - 1) then begin
              values.(!output) <- sorted.(slot);
              incr output
            end
          done
        end);
  Packed.Int_array.Private.create_validated_owned ~offsets ~values

let float_array_unique ?cancel ~grain relation source =
  let count = relation_count relation
  and sorted = fill_incidence_plane ?cancel ~grain ~default:0. relation source in
  let counts = Array.make count 0 in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1) (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        sort_float_range ?cancel sorted first last;
        if first < last then begin
          let unique = ref 1 in
          for slot = first + 1 to last - 1 do
            if slot land 16_383 = 0 then Cancel.check_opt cancel;
            if Float.compare sorted.(slot) sorted.(slot - 1) <> 0 then incr unique
          done;
          counts.(destination) <- !unique
        end);
  let offsets = Array.make (count + 1) 0 in
  for destination = 0 to count - 1 do
    offsets.(destination + 1) <- offsets.(destination) + counts.(destination)
  done;
  let values = Array.make offsets.(count) 0. in
  if count > 0 then Parallel.for_
      ~chunk_size:(reduction_chunk_size ~grain relation)
      ~start:0 ~finish:(count - 1) (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let first = relation_flat_first relation destination
        and last = relation_flat_last relation destination in
        if first < last then begin
          let output = ref offsets.(destination) in
          values.(!output) <- sorted.(first);
          incr output;
          for slot = first + 1 to last - 1 do
            if slot land 16_383 = 0 then Cancel.check_opt cancel;
            if Float.compare sorted.(slot) sorted.(slot - 1) <> 0 then begin
              values.(!output) <- sorted.(slot);
              incr output
            end
          done
        end);
  Packed.Float_array.Private.create_validated_owned ~offsets ~values

let remap_int_array ?cancel ~grain mapping values =
  let source = Packed.Int_array.Private.view values
  and count = Array.length mapping in
  let offsets = Array.make (count + 1) 0 in
  for destination = 0 to count - 1 do
    if destination land 4095 = 0 then Cancel.check_opt cancel;
    let source_row = mapping.(destination) in
    let length = source.offsets.(source_row + 1) - source.offsets.(source_row) in
    if length > Sys.max_array_length - offsets.(destination) then
      invalid_arg "Pdk.Attribute_ops.promote: remapped integer array exceeds array limits";
    offsets.(destination + 1) <- offsets.(destination) + length
  done;
  let output = Array.make offsets.(count) 0 in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let source_row = mapping.(destination) in
        let first = source.offsets.(source_row)
        and length = source.offsets.(source_row + 1) - source.offsets.(source_row) in
        Array.blit source.values first output offsets.(destination) length);
  Packed.Int_array.Private.create_validated_owned ~offsets ~values:output

let remap_float_array ?cancel ~grain mapping values =
  let source = Packed.Float_array.Private.view values
  and count = Array.length mapping in
  let offsets = Array.make (count + 1) 0 in
  for destination = 0 to count - 1 do
    if destination land 4095 = 0 then Cancel.check_opt cancel;
    let source_row = mapping.(destination) in
    let length = source.offsets.(source_row + 1) - source.offsets.(source_row) in
    if length > Sys.max_array_length - offsets.(destination) then
      invalid_arg "Pdk.Attribute_ops.promote: remapped float array exceeds array limits";
    offsets.(destination + 1) <- offsets.(destination) + length
  done;
  let output = Array.make offsets.(count) 0. in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(count - 1)
      (fun destination ->
        if destination land 4095 = 0 then Cancel.check_opt cancel;
        let source_row = mapping.(destination) in
        let first = source.offsets.(source_row)
        and length = source.offsets.(source_row + 1) - source.offsets.(source_row) in
        Array.blit source.values first output offsets.(destination) length);
  Packed.Float_array.Private.create_validated_owned ~offsets ~values:output

type promotion_plan = {
  relation : relation;
  mapping : int array option;
  destination_count : int;
}

let make_promotion_plan ?cancel ?piece_attribute ~source ~destination geometry =
  let relation = make_relation ?cancel ~source ~destination geometry
  and destination_count = owner_count geometry destination in
  match piece_attribute with
  | None -> Ok { relation; mapping = None; destination_count }
  | Some piece_name ->
      (match Geometry.find_attribute ~owner:destination piece_name geometry with
       | None -> Error (Printf.sprintf
           "Pdk.Attribute_ops.promote: missing %s-owned piece attribute %s"
           (match destination with Attribute.Point -> "point"
             | Attribute.Vertex -> "vertex"
             | Attribute.Primitive -> "primitive"
             | Attribute.Detail -> "detail") piece_name)
       | Some piece ->
           (match Attribute.Private.storage piece with
            | Attribute.Int _ | Attribute.Text _ ->
                let relation, mapping = make_piece_relation ?cancel
                    ~source_count:(owner_count geometry source)
                    ~piece_attribute:piece relation in
                Ok { relation; mapping = Some mapping; destination_count }
            | Attribute.Float _ | Attribute.Float2 _ | Attribute.Float3 _
            | Attribute.Float4 _ | Attribute.Int_array _
            | Attribute.Float_array _ -> Error
                "Pdk.Attribute_ops.promote: piece attribute must use integer or text storage"))

let validate_index_request ~method_ ~destination ~into ~piece_attribute
    ~index_attribute attribute = match index_attribute with
  | None -> Ok ()
  | Some name when String.trim name = "" -> Error
      "Pdk.Attribute_ops.promote: index attribute name must not be empty"
  | Some name when destination = Attribute.Point && String.equal name "P" -> Error
      "Pdk.Attribute_ops.promote: canonical P cannot store a source index"
  | Some name when String.equal name into -> Error
      "Pdk.Attribute_ops.promote: value and index attributes must have different names"
  | Some name when (match piece_attribute with
      | Some piece -> String.equal name piece | None -> false) -> Error
      "Pdk.Attribute_ops.promote: index attribute must not replace the piece attribute"
  | Some _ when not (indexed_method method_) -> Error
      "Pdk.Attribute_ops.promote: source index requires first, last, minimum, maximum, or mode"
  | Some _ ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float _ | Attribute.Int _ | Attribute.Text _
       | Attribute.Float2 _ | Attribute.Float3 _ | Attribute.Float4 _ -> Ok ()
       | Attribute.Int_array _ | Attribute.Float_array _ -> Error
           "Pdk.Attribute_ops.promote: array source indices are not defined")

let promote_bound ?cancel ~grain ~method_ ~delete_source ~source ~destination
    ~name ~into ?index_attribute ~attribute plan geometry =
  let relation = plan.relation and mapping = plan.mapping in
  assert (match mapping with None -> relation_count relation = plan.destination_count
    | Some values -> Array.length values = plan.destination_count);
  let unsupported message = Error (Printf.sprintf
      "Pdk.Attribute_ops.promote: %s storage does not support %s"
      message (match method_ with First -> "first" | Last -> "last"
        | Average -> "average" | Minimum -> "minimum" | Maximum -> "maximum"
        | Mode -> "mode" | Median -> "median" | Sum -> "sum"
        | Sum_squares -> "sum_squares"
        | Root_mean_square -> "root_mean_square"
        | Array_all -> "array_all" | Unique_values -> "unique_values")) in
  let map_float values = match mapping with None -> values
    | Some mapping -> map_plane ?cancel ~grain mapping values 0.
  and map_int values = match mapping with None -> values
    | Some mapping -> map_plane ?cancel ~grain mapping values 0
  and map_text values = match mapping with None -> values
    | Some mapping -> map_plane ?cancel ~grain mapping values ""
  and map_int_array values = match mapping with None -> values
    | Some mapping -> remap_int_array ?cancel ~grain mapping values
  and map_float_array values = match mapping with None -> values
    | Some mapping -> remap_float_array ?cancel ~grain mapping values in
  let storage_result = match Attribute.Private.storage attribute with
    | Attribute.Float values ->
        (match method_, index_attribute with
         | Array_all, None -> Ok (Attribute.Float_array
             (float_array_all ?cancel ~grain relation values |> map_float_array), None)
         | Unique_values, None -> Ok (Attribute.Float_array
             (float_array_unique ?cancel ~grain relation values
              |> map_float_array), None)
         | (First | Last | Average | Minimum | Maximum | Mode | Median | Sum
           | Sum_squares | Root_mean_square), None -> Ok (Attribute.Float
             (float_plane ?cancel ~grain method_ relation values |> map_float), None)
         | (Array_all | Unique_values), Some _ -> assert false
         | _, Some _ ->
             let values, indices = indexed_float_plane ?cancel ~grain method_
                 relation values in
             Ok (Attribute.Float (map_float values),
               Some (Attribute.Int (map_int indices))))
    | Attribute.Int values ->
        (match method_ with
         | Array_all -> Ok (Attribute.Int_array
             (int_array_all ?cancel ~grain relation values |> map_int_array), None)
         | Unique_values -> Ok (Attribute.Int_array
             (int_array_unique ?cancel ~grain relation values |> map_int_array), None)
         | First | Last | Minimum | Maximum | Mode | Median ->
             (match index_attribute with
              | None -> Ok (Attribute.Int
                  (int_plane ?cancel ~grain method_ relation values |> map_int), None)
              | Some _ ->
                  let values, indices = indexed_int_plane ?cancel ~grain method_
                      relation values in
                  Ok (Attribute.Int (map_int values),
                    Some (Attribute.Int (map_int indices))))
         | Average | Sum | Sum_squares | Root_mean_square -> unsupported "integer")
    | Attribute.Text values ->
        (match method_ with
         | First | Last | Average | Minimum | Maximum | Mode | Median | Sum
         | Sum_squares | Root_mean_square ->
             (match index_attribute with
              | None -> Ok (Attribute.Text
                  (text_plane ?cancel ~grain method_ relation values |> map_text), None)
              | Some _ ->
                  let values, indices = indexed_text_plane ?cancel ~grain method_
                      relation values in
                  Ok (Attribute.Text (map_text values),
                    Some (Attribute.Int (map_int indices))))
         | Array_all | Unique_values -> unsupported "text")
    | Attribute.Float2 values ->
        (match method_ with
         | Array_all | Unique_values -> unsupported "float2"
         | First | Last | Average | Minimum | Maximum | Mode | Median | Sum
         | Sum_squares | Root_mean_square ->
             let view = Packed.Float2.Private.view values in
             (match index_attribute with
              | None ->
                  let x = float_plane ?cancel ~grain method_ relation view.x
                      |> map_float
                  and y = float_plane ?cancel ~grain method_ relation view.y
                      |> map_float in
                  Ok (Attribute.Float2 (Packed.Float2.of_owned ~x ~y
                    |> Result.get_ok), None)
              | Some _ ->
                  let x, ix = indexed_float_plane ?cancel ~grain method_
                      relation view.x
                  and y, iy = indexed_float_plane ?cancel ~grain method_
                      relation view.y in
                  Ok (Attribute.Float2 (Packed.Float2.of_owned
                      ~x:(map_float x) ~y:(map_float y) |> Result.get_ok),
                    Some (Attribute.Int_array (fixed_int_tuple_array ?cancel
                      ~grain [|map_int ix; map_int iy|])))))
    | Attribute.Float3 values ->
        (match method_ with
         | Array_all | Unique_values -> unsupported "float3"
         | First | Last | Average | Minimum | Maximum | Mode | Median | Sum
         | Sum_squares | Root_mean_square ->
             let view = Packed.Float3.Private.view values in
             (match index_attribute with
              | None ->
                  let x = float_plane ?cancel ~grain method_ relation view.x
                      |> map_float
                  and y = float_plane ?cancel ~grain method_ relation view.y
                      |> map_float
                  and z = float_plane ?cancel ~grain method_ relation view.z
                      |> map_float in
                  Ok (Attribute.Float3
                    (Packed.Float3.Private.of_owned_exn ~x ~y ~z), None)
              | Some _ ->
                  let x, ix = indexed_float_plane ?cancel ~grain method_
                      relation view.x
                  and y, iy = indexed_float_plane ?cancel ~grain method_
                      relation view.y
                  and z, iz = indexed_float_plane ?cancel ~grain method_
                      relation view.z in
                  Ok (Attribute.Float3 (Packed.Float3.Private.of_owned_exn
                      ~x:(map_float x) ~y:(map_float y) ~z:(map_float z)),
                    Some (Attribute.Int_array (fixed_int_tuple_array ?cancel
                      ~grain [|map_int ix; map_int iy; map_int iz|])))))
    | Attribute.Float4 values ->
        (match method_ with
         | Array_all | Unique_values -> unsupported "float4"
         | First | Last | Average | Minimum | Maximum | Mode | Median | Sum
         | Sum_squares | Root_mean_square ->
             let view = Packed.Float4.Private.view values in
             (match index_attribute with
              | None ->
                  let x = float_plane ?cancel ~grain method_ relation view.x
                      |> map_float
                  and y = float_plane ?cancel ~grain method_ relation view.y
                      |> map_float
                  and z = float_plane ?cancel ~grain method_ relation view.z
                      |> map_float
                  and w = float_plane ?cancel ~grain method_ relation view.w
                      |> map_float in
                  Ok (Attribute.Float4 (Packed.Float4.of_owned ~x ~y ~z ~w
                    |> Result.get_ok), None)
              | Some _ ->
                  let x, ix = indexed_float_plane ?cancel ~grain method_
                      relation view.x
                  and y, iy = indexed_float_plane ?cancel ~grain method_
                      relation view.y
                  and z, iz = indexed_float_plane ?cancel ~grain method_
                      relation view.z
                  and w, iw = indexed_float_plane ?cancel ~grain method_
                      relation view.w in
                  Ok (Attribute.Float4 (Packed.Float4.of_owned
                      ~x:(map_float x) ~y:(map_float y) ~z:(map_float z)
                      ~w:(map_float w) |> Result.get_ok),
                    Some (Attribute.Int_array (fixed_int_tuple_array ?cancel
                      ~grain [|map_int ix; map_int iy; map_int iz; map_int iw|])))))
    | Attribute.Int_array _ -> unsupported "integer array"
    | Attribute.Float_array _ -> unsupported "float array" in
  Result.bind storage_result (fun (storage, indices) ->
    Result.bind (Attribute.create_owned ~name:into ~owner:destination storage)
      (fun promoted ->
        let geometry = if delete_source then
            Geometry.without_attribute ~owner:source name geometry
          else geometry in
        Result.bind (Geometry.with_attribute promoted geometry) (fun geometry ->
          match index_attribute, indices with
          | None, None -> Ok geometry
          | Some name, Some storage ->
              Result.bind (Attribute.create_owned ~name ~owner:destination
                  storage) (fun indices ->
                Geometry.with_attribute indices geometry)
          | None, Some _ | Some _, None -> assert false)))

let validate_promotion_names ~piece_attribute ~source ~name ~into =
  if String.trim name = "" || String.trim into = "" then
    Error "Pdk.Attribute_ops.promote: attribute names must not be empty"
  else if (match piece_attribute with
      | Some value -> String.trim value = ""
      | None -> false) then
    Error "Pdk.Attribute_ops.promote: piece attribute name must not be empty"
  else if source = Attribute.Point && String.equal name "P" then
    Error "Pdk.Attribute_ops.promote: canonical P is not an ordinary attribute"
  else Ok ()

let promote_raw ?cancel ?(grain = 16_384) ?into ?(method_ = Average)
    ?(delete_source = true) ?piece_attribute ?index_attribute ~source
    ~destination ~name geometry =
  if grain <= 0 then invalid_arg "Pdk.Attribute_ops.promote: grain must be positive";
  let into = Option.value ~default:name into in
  Result.bind (validate_promotion_names ~piece_attribute ~source ~name ~into)
    (fun () -> match Geometry.find_attribute ~owner:source name geometry with
      | None -> Error ("Pdk.Attribute_ops.promote: missing source attribute " ^ name)
      | Some attribute ->
          Result.bind (validate_index_request ~method_ ~destination ~into
              ~piece_attribute ~index_attribute attribute) (fun () ->
            if source = destination && String.equal name into
                && Option.is_none piece_attribute then Ok geometry
            else Result.bind (make_promotion_plan ?cancel ?piece_attribute
                  ~source ~destination geometry) (fun plan ->
                promote_bound ?cancel ~grain ~method_ ~delete_source ~source
                  ~destination ~name ~into ?index_attribute ~attribute plan geometry)))

let promote_pattern_raw ?cancel ?(grain = 16_384) ?(method_ = Average)
    ?(delete_source = true) ?piece_attribute ?into_pattern ?index_pattern
    ~source ~destination ~pattern geometry =
  if grain <= 0 then invalid_arg
      "Pdk.Attribute_ops.promote_pattern: grain must be positive";
  if (match piece_attribute with Some value -> String.trim value = "" | None -> false)
  then Error "Pdk.Attribute_ops.promote_pattern: piece attribute name must not be empty"
  else if Option.is_some index_pattern && not (indexed_method method_) then Error
      "Pdk.Attribute_ops.promote_pattern: source index requires first, last, minimum, maximum, or mode"
  else Result.bind (Attribute_pattern.compile pattern) (fun compiled ->
    Result.bind (match into_pattern with
      | None -> Ok None
      | Some replacement -> Result.map Option.some
          (Attribute_pattern.compile_rewrite_set ~pattern ~replacement))
      (fun rewrite -> Result.bind (match index_pattern with
        | None -> Ok None
        | Some replacement -> Result.map Option.some
            (Attribute_pattern.compile_rewrite_set ~pattern ~replacement))
      (fun index_rewrite ->
    let rec select result = function
      | [] -> Result.map (fun values -> Array.of_list (List.rev values)) result
      | attribute :: rest when Attribute.owner attribute <> source ->
          select result rest
      | attribute :: rest ->
          let name = Attribute.name attribute in
          if not (Attribute_pattern.matches compiled name) then select result rest
          else Result.bind result (fun values ->
            let apply label rule fallback = match rule with
              | None -> Ok fallback
              | Some rule ->
                  (match Attribute_pattern.rewrite_set rule name with
                   | Some value -> Ok value
                   | None -> Error (Printf.sprintf
                       "Pdk.Attribute_ops.promote_pattern: %s rewrite did not match %s"
                       label name)) in
            Result.bind (apply "destination" rewrite name) (fun into ->
              Result.bind (match index_rewrite with
                | None -> Ok None
                | Some _ -> Result.map Option.some
                    (apply "index" index_rewrite name)) (fun index_attribute ->
                select (Ok ((attribute, into, index_attribute) :: values)) rest))) in
    Result.bind (select (Ok []) (Geometry.attributes geometry)) (fun selected ->
    let validation =
      let destinations = Hashtbl.create (Array.length selected * 2) in
      let reserve name =
        if Hashtbl.mem destinations name then Error (Printf.sprintf
            "Pdk.Attribute_ops.promote_pattern: multiple outputs use name %s" name)
        else begin Hashtbl.add destinations name (); Ok () end in
      Array.fold_left (fun result (attribute, into, index_attribute) ->
        Result.bind result (fun () ->
          if String.trim into = "" then Error
              "Pdk.Attribute_ops.promote_pattern: rewritten name must not be empty"
          else if destination = Attribute.Point && String.equal into "P" then Error
              "Pdk.Attribute_ops.promote_pattern: canonical P is not an ordinary attribute"
          else Result.bind (reserve into) (fun () ->
            Result.bind (validate_index_request ~method_ ~destination ~into
                ~piece_attribute ~index_attribute attribute) (fun () ->
              match index_attribute with None -> Ok () | Some name -> reserve name))))
        (Ok ()) selected in
    Result.bind validation (fun () ->
    if Array.length selected = 0
       || (source = destination && Option.is_none piece_attribute) then Ok geometry
    else Result.bind (make_promotion_plan ?cancel ?piece_attribute
        ~source ~destination geometry) (fun plan ->
      let geometry = if delete_source then
          Array.fold_left (fun geometry (attribute, _, _) ->
            Geometry.without_attribute ~owner:source (Attribute.name attribute)
              geometry) geometry selected
        else geometry in
      let rec promote geometry index =
        if index = Array.length selected then Ok geometry
        else
          let attribute, into, index_attribute = selected.(index) in
          let name = Attribute.name attribute in
          Result.bind (promote_bound ?cancel ~grain ~method_
              ~delete_source:false ~source ~destination ~name ~into ~attribute
              ?index_attribute plan geometry)
            (fun geometry -> promote geometry (index + 1)) in
      promote geometry 0))))))

let promote ?cancel ?grain ?into ?method_ ?delete_source ?piece_attribute
    ?index_attribute ~source ~destination ~name geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_promote" ~code:"invalid_attribute")
      (promote_raw ?cancel ?grain ?into ?method_ ?delete_source ?piece_attribute
         ?index_attribute ~source ~destination ~name geometry)
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_promote"
      ~code:"cancelled" "attribute promotion was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_promote"
      ~code:"invalid_parameter" message)

let promote_pattern ?cancel ?grain ?method_ ?delete_source ?piece_attribute
    ?into_pattern ?index_pattern ~source ~destination ~pattern geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_promote" ~code:"invalid_attribute")
      (promote_pattern_raw ?cancel ?grain ?method_ ?delete_source ?piece_attribute
         ?into_pattern ?index_pattern ~source ~destination ~pattern geometry)
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_promote"
      ~code:"cancelled" "attribute promotion was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_promote"
      ~code:"invalid_parameter" message)

type rename_conflict = Attribute_lifecycle.rename_conflict =
  | Attribute_rename_skip
  | Attribute_rename_error
  | Attribute_rename_overwrite

type rename_rule = Attribute_lifecycle.rename_rule = {
  rename_attribute_owner : Attribute.owner option;
  rename_attribute_pattern : string;
  rename_attribute_replacement : string;
  rename_attribute_conflict : rename_conflict;
}

let delete ?cancel ?reference ?delete_non_selected ?point_pattern
    ?vertex_pattern ?primitive_pattern ?detail_pattern geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_delete" ~code:"invalid_attribute")
      (Attribute_lifecycle.delete ?cancel ?reference ?delete_non_selected
         ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
         geometry)
  with Cancel.Cancelled -> Error (Error.make ~operation:"attribute_delete"
      ~code:"cancelled" "attribute deletion was cancelled")

let rename ?cancel ~rules geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_rename" ~code:"invalid_attribute")
      (Attribute_lifecycle.rename ?cancel ~rules geometry)
  with Cancel.Cancelled -> Error (Error.make ~operation:"attribute_rename"
      ~code:"cancelled" "attribute renaming was cancelled")

type swap_method = Attribute_lifecycle.swap_method =
  | Attribute_swap
  | Attribute_move
  | Attribute_copy

type swap_rule = Attribute_lifecycle.swap_rule = {
  swap_attribute_owner : Attribute.owner;
  swap_attribute_source : string;
  swap_attribute_destination : string;
  swap_attribute_method : swap_method;
}

let swap ?cancel ~rules geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_swap" ~code:"invalid_attribute")
      (Attribute_lifecycle.swap ?cancel ~rules geometry)
  with Cancel.Cancelled -> Error (Error.make ~operation:"attribute_swap"
      ~code:"cancelled" "attribute swap was cancelled")

type transfer_mode =
  | Nearest
  | Inverse_distance of { neighbors : int; power : float }
  | Kernel of {
      neighbors : int;
      radius : float;
      kernel : transfer_kernel;
    }

and transfer_kernel = Links | RenderMan | Hart

type unmatched = Keep_target | Default_value
type transfer_falloff = Linear | Smoothstep | Uniform of float
type surface_falloff = transfer_falloff
type surface_vertex_selection = Surface_index.vertex_selection =
  | All_triangle_vertices
  | Any_triangle_vertex
type copy_match = Attribute_copy.match_mode =
  | Cyclic
  | By_values of { source_attribute : string; target_attribute : string }
  | To_element of { target_attribute : string }
type copy_rule = Attribute_copy.rule = {
  copy_owner : Attribute.owner;
  copy_pattern : string;
  copy_into : string option;
}
type interpolate_attribute = {
  interpolate_owner : Attribute.owner;
  interpolate_source : string;
  interpolate_target : string;
}
type interpolate_driver =
  | Primitive_uvw of {
      primitive_attribute : string;
      uvw_attribute : string;
    }
  | Point_weights of {
      numbers_attribute : string;
      weights_attribute : string;
    }
  | Vertex_weights of {
      numbers_attribute : string;
      weights_attribute : string;
    }
  | Primitive_weights of {
      numbers_attribute : string;
      weights_attribute : string;
    }
type interpolate_computed = {
  computed_owner : Attribute.owner;
  computed_numbers_attribute : string;
  computed_weights_attribute : string;
}
type combine_operation = Attribute_combine.operation =
  | Combine_copy
  | Combine_add
  | Combine_subtract
  | Combine_multiply
  | Combine_divide
  | Combine_maximum
  | Combine_minimum
type combine_process = Attribute_combine.process =
  | Combine_process_none
  | Combine_reciprocal
  | Combine_clamp_01
  | Combine_complement_clamp_01
  | Combine_threshold_half
type combine_layer = Attribute_combine.layer = {
  source : string option;
  source_input : int;
  operation : combine_operation;
  scale : float;
  add : float;
  process : combine_process;
  blend : float;
  blend_attribute : string option;
  blend_input : int;
}
type enumeration_storage = Integer | Text of { prefix : string }
type enumeration_mode = Enumerate_piece_elements | Enumerate_pieces
type blur_method = Uniform | Edge_length
type blur_mode = Laplacian of float | Custom_steps of { odd : float; even : float }
type numeric_value = Attribute_generate.numeric_value =
  | Scalar of float
  | Vec2 of Vec2.t
  | Vec3 of Vec3.t
  | Vec4 of float * float * float * float
type random_operation = Attribute_generate.random_operation =
  | Random_set
  | Random_add
  | Random_minimum
  | Random_maximum
  | Random_multiply
type noise_kind = Attribute_generate.noise_kind =
  | Noise_float | Noise_vector | Noise_quaternion
type noise_location = Attribute_generate.noise_location =
  | Noise_position
  | Noise_element_number
  | Noise_attribute of string
type noise_range = Attribute_generate.noise_range =
  | Noise_positive
  | Noise_zero_centered
  | Noise_min_max of numeric_value * numeric_value
type noise_operation = Attribute_generate.noise_operation =
  | Noise_set_initial
  | Noise_set
  | Noise_add
  | Noise_subtract
  | Noise_multiply
  | Noise_minimum
  | Noise_maximum
type random_selection = Attribute_generate.random_selection =
  | Random_points of Group.t
  | Random_vertices of Group.t
  | Random_primitives of Group.t
  | Random_edges of Edge_group.t
type random_distribution = Attribute_generate.random_distribution =
  | Random_constant of numeric_value
  | Random_two_values of {
      a : numeric_value;
      b : numeric_value;
      probability_b : float;
    }
  | Random_uniform of { min : numeric_value; max : numeric_value }
  | Random_uniform_discrete of {
      min : numeric_value;
      max : numeric_value;
      step : numeric_value;
    }
  | Random_normal of { middle : numeric_value; scale : numeric_value }
  | Random_exponential of { median : numeric_value }
  | Random_log_normal of { median : numeric_value; stddev : numeric_value }
  | Random_cauchy of { median : numeric_value; scale : numeric_value }
  | Random_direction of {
      direction : numeric_value;
      cone_angle : float;
    }
  | Random_inside_sphere of { dimensions : int }
  | Random_inside_sphere_cone of {
      direction : numeric_value;
      cone_angle : float;
    }
  | Random_custom_ramp of {
      ramp : (float * float) list;
      fit_min : numeric_value;
      fit_max : numeric_value;
    }
  | Random_custom_discrete of (numeric_value * float) list
  | Random_custom_discrete_text of (string * float) list
type remap_input = Attribute_generate.remap_input =
  | Remap_explicit of { min : numeric_value; max : numeric_value }
  | Remap_auto
type remap_policy = Attribute_generate.remap_policy =
  | Remap_clamp
  | Remap_cycle
  | Remap_extrapolate

type int_piece_table = {
  mutable int_piece_keys : int array;
  mutable int_piece_values : int array;
  mutable int_piece_used : bytes;
  mutable int_piece_count : int;
}

let int_piece_table_create () = {
  int_piece_keys = Array.make 16 0;
  int_piece_values = Array.make 16 0;
  int_piece_used = Bytes.make 16 '\000';
  int_piece_count = 0;
}

let[@inline] int_piece_hash key =
  let value = key lxor (key lsr 27) in
  (value * 0x1e35a7bd) land max_int

let int_piece_insert_raw table key value =
  let mask = Array.length table.int_piece_keys - 1 in
  let slot = ref (int_piece_hash key land mask) in
  while Bytes.get table.int_piece_used !slot <> '\000' do
    slot := (!slot + 1) land mask
  done;
  Bytes.set table.int_piece_used !slot '\001';
  table.int_piece_keys.(!slot) <- key;
  table.int_piece_values.(!slot) <- value

let int_piece_grow table =
  let old_keys = table.int_piece_keys and old_values = table.int_piece_values
  and old_used = table.int_piece_used in
  let capacity = Array.length old_keys * 2 in
  table.int_piece_keys <- Array.make capacity 0;
  table.int_piece_values <- Array.make capacity 0;
  table.int_piece_used <- Bytes.make capacity '\000';
  for slot = 0 to Array.length old_keys - 1 do
    if Bytes.get old_used slot <> '\000' then
      int_piece_insert_raw table old_keys.(slot) old_values.(slot)
  done

let int_piece_find_or_add table key =
  if table.int_piece_count * 10 >= Array.length table.int_piece_keys * 7 then
    int_piece_grow table;
  let mask = Array.length table.int_piece_keys - 1 in
  let slot = ref (int_piece_hash key land mask) in
  while Bytes.get table.int_piece_used !slot <> '\000'
      && table.int_piece_keys.(!slot) <> key do
    slot := (!slot + 1) land mask
  done;
  if Bytes.get table.int_piece_used !slot <> '\000' then
    table.int_piece_values.(!slot)
  else begin
    let value = table.int_piece_count in
    Bytes.set table.int_piece_used !slot '\001';
    table.int_piece_keys.(!slot) <- key;
    table.int_piece_values.(!slot) <- value;
    table.int_piece_count <- value + 1;
    value
  end

let sequence_fits ~start ~step maximum_rank =
  if maximum_rank <= 0 || step = 0 then true
  else
    let rank = Int64.of_int maximum_rank
    and start64 = Int64.of_int start and step64 = Int64.of_int step
    and maximum = Int64.of_int max_int and minimum = Int64.of_int min_int in
    if step > 0 then
      Int64.compare rank (Int64.div (Int64.sub maximum start64) step64) <= 0
    else
      Int64.compare rank
        (Int64.div (Int64.sub start64 minimum) (Int64.neg step64)) <= 0

let piece_ranks ?cancel ~selection ~mode ~owner ~name count geometry =
  let source = match Geometry.find_attribute ~owner name geometry with
    | None -> Error (Printf.sprintf "piece attribute %s does not exist" name)
    | Some attribute ->
        (match Attribute.Private.storage attribute with
         | Attribute.Int values -> Ok (`Int values)
         | Attribute.Text values -> Ok (`Text values)
         | Attribute.Float _ | Attribute.Int_array _ | Attribute.Float_array _
         | Attribute.Float2 _ | Attribute.Float3 _ | Attribute.Float4 _ ->
             Error (Printf.sprintf
               "piece attribute %s has %s storage, expected int or text"
               name (Attribute.kind_name attribute))) in
  Result.map (fun source ->
    let ranks = Array.make count (-1) and piece_sizes = Dynarray.create ()
    and max_rank = ref (-1) in
    let integer_table = match source with
      | `Int _ -> Some (int_piece_table_create ())
      | `Text _ -> None in
    let text_table = match source with
      | `Text _ -> Some (Hashtbl.create 128)
      | `Int _ -> None in
    let piece_id element = match source with
      | `Int values -> int_piece_find_or_add (Option.get integer_table)
          values.(element)
      | `Text values ->
          let table = Option.get text_table and key = values.(element) in
          (match Hashtbl.find_opt table key with
           | Some piece -> piece
           | None ->
               let piece = Hashtbl.length table in
               Hashtbl.add table key piece;
               piece) in
    for element = 0 to count - 1 do
      if element land 4095 = 0 then Cancel.check_opt cancel;
      if (match selection with None -> true
          | Some group -> Group.mem element group) then begin
        let piece = piece_id element in
        while Dynarray.length piece_sizes <= piece do
          Dynarray.add_last piece_sizes 0
        done;
        let rank = match mode with
          | Enumerate_pieces -> piece
          | Enumerate_piece_elements ->
              let rank = Dynarray.get piece_sizes piece in
              Dynarray.set piece_sizes piece (rank + 1);
              rank in
        ranks.(element) <- rank;
        if rank > !max_rank then max_rank := rank
      end
    done;
    ranks, !max_rank) source

let enumerate_raw ?cancel ?(grain = 16_384) ?selection ?(start = 0) ?(step = 1)
    ?(storage = Integer) ?piece_attribute
    ?(mode = Enumerate_piece_elements) ~owner ~name geometry =
  if grain <= 0 then invalid_arg "Pdk.Attribute_ops.enumerate: grain must be positive";
  if String.trim name = "" then Error "attribute name must not be empty"
  else if (match piece_attribute with
      | Some value -> String.trim value = "" | None -> false) then
    Error "piece attribute name must not be empty"
  else if owner = Attribute.Detail then Error "detail ownership cannot be enumerated"
  else
    let count = owner_count geometry owner in
    let expected_group_owner = match owner with
      | Attribute.Point -> Group.Point
      | Attribute.Vertex -> Group.Vertex
      | Attribute.Primitive -> Group.Primitive
      | Attribute.Detail -> assert false in
    match selection with
    | Some group when Group.owner group <> expected_group_owner
        || Group.length group <> count ->
        Error "selection owner/length does not match the enumerated elements"
    | None | Some _ ->
        let ranges = (count + grain - 1) / grain in
        let range_offsets, selected_count = match piece_attribute with
          | Some _ -> [||], 0
          | None ->
              let range_counts = Array.make ranges 0 in
              if ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0
                  ~finish:(ranges - 1) (fun range ->
                    let first = range * grain
                    and last = min count ((range + 1) * grain) in
                    let selected = ref 0 in
                    for element = first to last - 1 do
                      if element land 4095 = 0 then Cancel.check_opt cancel;
                      if (match selection with None -> true
                          | Some group -> Group.mem element group) then
                        incr selected
                    done;
                    range_counts.(range) <- !selected);
              let range_offsets = Array.make ranges 0
              and selected_count = ref 0 in
              for range = 0 to ranges - 1 do
                range_offsets.(range) <- !selected_count;
                selected_count := !selected_count + range_counts.(range)
              done;
              range_offsets, !selected_count in
        let existing = Geometry.find_attribute ~owner name geometry in
        let expected_kind = match storage with Integer -> "int" | Text _ -> "text" in
        (match existing with
         | Some attribute when Attribute.kind_name attribute <> expected_kind ->
             Error (Printf.sprintf "target attribute %s has %s storage, expected %s"
               name (Attribute.kind_name attribute) expected_kind)
         | None | Some _ ->
             let global_fill set =
               if ranges > 0 then Parallel.for_ ~chunk_size:1 ~start:0
                   ~finish:(ranges - 1) (fun range ->
                     let first = range * grain
                     and last = min count ((range + 1) * grain) in
                     let rank = ref range_offsets.(range) in
                     let value = ref (Int64.to_int (Int64.add (Int64.of_int start)
                       (Int64.mul (Int64.of_int range_offsets.(range))
                          (Int64.of_int step)))) in
                     for element = first to last - 1 do
                       if element land 4095 = 0 then Cancel.check_opt cancel;
                       if (match selection with None -> true
                           | Some group -> Group.mem element group) then begin
                         set element !value;
                         incr rank;
                       if !rank < selected_count then value := !value + step
                       end
                     done) in
             let ranks = match piece_attribute with
               | None -> Ok None
               | Some piece_attribute -> Result.map Option.some
                   (piece_ranks ?cancel ~selection ~mode ~owner
                      ~name:piece_attribute count geometry) in
             Result.bind ranks (fun ranks ->
               let maximum_rank = match ranks with
                 | None -> selected_count - 1
                 | Some (_, maximum_rank) -> maximum_rank in
               if not (sequence_fits ~start ~step maximum_rank) then
                 invalid_arg "Pdk.Attribute_ops.enumerate: integer sequence overflows";
               let value_of_rank rank = Int64.to_int (Int64.add
                   (Int64.of_int start)
                   (Int64.mul (Int64.of_int rank) (Int64.of_int step))) in
               let piece_fill ranks set =
                 if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                     ~finish:(count - 1) (fun element ->
                       if element land 16_383 = 0 then Cancel.check_opt cancel;
                       let rank = ranks.(element) in
                       if rank >= 0 then set element (value_of_rank rank)) in
               let fill set = match ranks with
                 | None -> global_fill set
                 | Some (ranks, _) -> piece_fill ranks set in
               let attribute = match storage with
                 | Integer ->
                     let values = match existing with
                       | Some attribute ->
                           (match Attribute.Private.storage attribute with
                            | Attribute.Int values -> Array.copy values
                            | _ -> assert false)
                       | None -> Array.make count 0 in
                     fill (fun element value -> values.(element) <- value);
                     Attribute.create_owned ~name ~owner (Attribute.Int values)
                 | Text { prefix } ->
                     let values = match existing with
                       | Some attribute ->
                           (match Attribute.Private.storage attribute with
                            | Attribute.Text values -> Array.copy values
                            | _ -> assert false)
                       | None -> Array.make count "" in
                     fill (fun element value ->
                       values.(element) <- prefix ^ string_of_int value);
                     Attribute.create_owned ~name ~owner (Attribute.Text values) in
               Result.bind attribute (fun attribute ->
                 Geometry.with_attribute attribute geometry)))

let enumerate ?cancel ?grain ?selection ?start ?step ?storage ?piece_attribute
    ?mode ~owner ~name geometry =
  try Result.map_error
      (Error.of_string ~operation:"enumerate" ~code:"invalid_enumeration")
      (enumerate_raw ?cancel ?grain ?selection ?start ?step ?storage
         ?piece_attribute ?mode ~owner ~name geometry)
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"enumerate" ~code:"cancelled"
      "enumeration was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"enumerate"
      ~code:"invalid_enumeration" message)

type blur_target =
  | Blur_position of int
  | Blur_float of Attribute.t * int
  | Blur_float2 of Attribute.t * int
  | Blur_float3 of Attribute.t * int
  | Blur_float4 of Attribute.t * int

let blur_edge_lengths ?cancel ~grain positions topology =
  let edge_count = Array.length topology.Topology_index.Private.edge_a in
  let lengths = Array.make edge_count 0. in
  let range_count = if edge_count = 0 then 0 else
      (edge_count + grain - 1) / grain in
  let errors = Array.make range_count (-1) in
  Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1) (fun range ->
    let first = range * grain and last = min edge_count ((range + 1) * grain) in
    for edge = first to last - 1 do
      if edge land 16_383 = 0 then Cancel.check_opt cancel;
      let a = topology.edge_a.(edge) and b = topology.edge_b.(edge) in
      let dx = positions.Packed.Float3.Private.x.(b) -. positions.x.(a)
      and dy = positions.y.(b) -. positions.y.(a)
      and dz = positions.z.(b) -. positions.z.(a) in
      let length = Float.hypot dx (Float.hypot dy dz) in
      if errors.(range) < 0 && not (Float.is_finite length) then
        errors.(range) <- edge;
      lengths.(edge) <- length
    done);
  let invalid = Array.find_opt (fun edge -> edge >= 0) errors in
  (match invalid with
   | Some edge -> invalid_arg (Printf.sprintf
       "Pdk.Attribute_ops.blur_points: edge %d has non-finite length" edge)
   | None -> ());
  lengths

let blur_points_raw ?cancel ?(grain = 16_384) ?selection ?(iterations = 1)
    ?(method_ = Uniform) ?(mode = Laplacian 0.5) ?weight_attribute
    ?alpha_attribute ?(pin_borders = false) ?(original_blend = 0.)
    ?(blurred_blend = 1.) ~pattern geometry =
  if grain <= 0 then invalid_arg
      "Pdk.Attribute_ops.blur_points: grain must be positive";
  if iterations < 0 then Error
      "Pdk.Attribute_ops.blur_points: iterations must be non-negative"
  else if not (Float.is_finite original_blend && Float.is_finite blurred_blend)
  then Error "Pdk.Attribute_ops.blur_points: blend amounts must be finite"
  else
    let steps_valid = match mode with
      | Laplacian step -> Float.is_finite step
      | Custom_steps { odd; even } ->
          Float.is_finite odd && Float.is_finite even in
    if not steps_valid then Error
        "Pdk.Attribute_ops.blur_points: step sizes must be finite"
    else
      let point_count = Geometry.point_count geometry in
      let selection_result = match selection with
        | Some group when Group.owner group <> Group.Point
            || Group.length group <> point_count -> Error
              "Pdk.Attribute_ops.blur_points: selection must be a matching point group"
        | None | Some _ -> Ok () in
      Result.bind selection_result (fun () ->
      if String.trim pattern = "" || iterations = 0
          || (match selection with Some group -> Group.cardinality group = 0
               | None -> point_count = 0)
      then Ok geometry
      else Result.bind (Attribute_pattern.compile pattern) (fun compiled ->
      let targets = ref [] and planes = ref [] and plane_count = ref 0 in
      let add_target make arrays =
        let first = !plane_count in
        plane_count := first + List.length arrays;
        List.iter (fun values -> planes := values :: !planes) arrays;
        targets := make first :: !targets in
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      if Attribute_pattern.matches compiled "P" then
        add_target (fun first -> Blur_position first)
          [positions.x; positions.y; positions.z];
      List.iter (fun attribute ->
        if Attribute.owner attribute = Attribute.Point
            && Attribute_pattern.matches compiled (Attribute.name attribute) then
          match Attribute.Private.storage attribute with
          | Attribute.Float values ->
              add_target (fun first -> Blur_float (attribute, first)) [values]
          | Attribute.Float2 values ->
              let values = Packed.Float2.Private.view values in
              add_target (fun first -> Blur_float2 (attribute, first))
                [values.x; values.y]
          | Attribute.Float3 values ->
              let values = Packed.Float3.Private.view values in
              add_target (fun first -> Blur_float3 (attribute, first))
                [values.x; values.y; values.z]
          | Attribute.Float4 values ->
              let values = Packed.Float4.Private.view values in
              add_target (fun first -> Blur_float4 (attribute, first))
                [values.x; values.y; values.z; values.w]
          | Attribute.Int _ | Attribute.Text _ | Attribute.Int_array _
          | Attribute.Float_array _ -> ())
        (Geometry.attributes geometry);
      let targets = Array.of_list (List.rev !targets)
      and original = Array.of_list (List.rev !planes) in
      if Array.length targets = 0 then Ok geometry
      else begin
        let failure = ref None in
        Array.iteri (fun plane values ->
          let point = ref 0 in
          while !point < point_count && !failure = None do
            if !point land 16_383 = 0 then Cancel.check_opt cancel;
            if not (Float.is_finite values.(!point)) then
              failure := Some (Printf.sprintf
                  "Pdk.Attribute_ops.blur_points: plane %d contains a non-finite value at point %d"
                  plane !point);
            incr point
          done) original;
        let control name = match name with
          | None -> Ok None
          | Some name when String.trim name = "" -> Error
              "Pdk.Attribute_ops.blur_points: control attribute name must not be empty"
          | Some name ->
              (match Geometry.find_attribute ~owner:Attribute.Point name geometry with
               | None -> Error (Printf.sprintf
                   "Pdk.Attribute_ops.blur_points: missing point float attribute %s" name)
               | Some attribute ->
                   (match Attribute.Private.storage attribute with
                    | Attribute.Float values -> Ok (Some values)
                    | Attribute.Int _ | Attribute.Float2 _ | Attribute.Float3 _
                    | Attribute.Float4 _ | Attribute.Text _
                    | Attribute.Int_array _ | Attribute.Float_array _ ->
                        Error (Printf.sprintf
                        "Pdk.Attribute_ops.blur_points: control attribute %s must be scalar float"
                        name))) in
        Result.bind (match !failure with None -> Ok () | Some message -> Error message)
          (fun () -> Result.bind (control weight_attribute) (fun weights ->
        Result.bind (control alpha_attribute) (fun alpha ->
        let validate_control label = function
          | None -> Ok ()
          | Some values ->
              let invalid = ref (-1) and point = ref 0 in
              while !point < point_count && !invalid < 0 do
                if !point land 16_383 = 0 then Cancel.check_opt cancel;
                if not (Float.is_finite values.(!point)) then invalid := !point;
                incr point
              done;
              if !invalid < 0 then Ok () else Error (Printf.sprintf
                  "Pdk.Attribute_ops.blur_points: %s attribute is non-finite at point %d"
                  label !invalid) in
        Result.bind (validate_control "weight" weights) (fun () ->
        Result.bind (validate_control "alpha" alpha) (fun () ->
        let topology_index = Topology_index.create ?cancel (Geometry.topology geometry)
        and current = ref (Array.map Array.copy original)
        and next = ref (Array.map Array.copy original) in
        let topology = Topology_index.Private.view topology_index in
        let edge_lengths = match method_ with
          | Uniform -> None
          | Edge_length -> Some (blur_edge_lengths ?cancel ~grain positions topology) in
        let pinned = if not pin_borders then None else begin
            let pinned = Parallel.init_array ~grain point_count (fun point ->
              let first = topology.point_edge_offsets.(point)
              and last = topology.point_edge_offsets.(point + 1) in
              let boundary = ref false and local = ref first in
              while !local < last && not !boundary do
                let edge = topology.point_edges.(!local) in
                boundary := topology.edge_offsets.(edge + 1)
                    - topology.edge_offsets.(edge) = 1;
                incr local
              done;
              !boundary) in
            Some pinned
          end in
        for iteration = 0 to iterations - 1 do
          Cancel.check_opt cancel;
          let step = match mode with
            | Laplacian step -> step
            | Custom_steps { odd; even } ->
                if iteration land 1 = 0 then odd else even in
          let range_count = (point_count + grain - 1) / grain in
          Parallel.for_ ~chunk_size:1 ~start:0 ~finish:(range_count - 1)
            (fun range ->
              let first_point = range * grain
              and last_point = min point_count ((range + 1) * grain) in
              let zero_sum = ref 0. and zero_weight = ref 0.
              and regular_sum = ref 0. and regular_weight = ref 0. in
              for point = first_point to last_point - 1 do
                if point land 4095 = 0 then Cancel.check_opt cancel;
                let update = (match selection with
                      | None -> true | Some group -> Group.mem point group)
                    && not (match pinned with
                      | Some values -> values.(point) | None -> false) in
                for plane = 0 to Array.length !current - 1 do
                  let source = (!current).(plane)
                  and destination = (!next).(plane) in
                  if not update then destination.(point) <- source.(point)
                  else begin
                  let first = topology.point_edge_offsets.(point)
                  and last = topology.point_edge_offsets.(point + 1) in
                  zero_sum := 0.; zero_weight := 0.;
                  regular_sum := 0.; regular_weight := 0.;
                  for local = first to last - 1 do
                    let edge = topology.point_edges.(local) in
                    let a = topology.edge_a.(edge) and b = topology.edge_b.(edge) in
                    let neighbor = if a = point then b else a in
                    if neighbor <> point then begin
                      let influence = match alpha with
                        | None -> 1.
                        | Some values ->
                            Float.max 0. (Float.min 1. values.(neighbor)) in
                      if influence > 0. then match edge_lengths with
                        | None ->
                            regular_sum := !regular_sum +. (influence *. source.(neighbor));
                            regular_weight := !regular_weight +. influence
                        | Some lengths when lengths.(edge) = 0. ->
                            zero_sum := !zero_sum +. (influence *. source.(neighbor));
                            zero_weight := !zero_weight +. influence
                        | Some lengths ->
                            let influence = influence /. lengths.(edge) in
                            regular_sum := !regular_sum +. (influence *. source.(neighbor));
                            regular_weight := !regular_weight +. influence
                    end
                  done;
                  let sum, total = if !zero_weight > 0.
                      then !zero_sum, !zero_weight
                      else !regular_sum, !regular_weight in
                  if total = 0. then destination.(point) <- source.(point)
                  else
                    let local_weight = match weights with
                      | None -> 1. | Some values -> values.(point) in
                    let average = sum /. total in
                    destination.(point) <- source.(point)
                      +. ((step *. local_weight) *. (average -. source.(point)))
                  end
                done
              done);
          let swap = !current in current := !next; next := swap
        done;
        let output = if original_blend = 0. && blurred_blend = 1. then !current
          else begin
            let values = Array.init (Array.length !current)
                (fun _ -> Array.make point_count 0.) in
            Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
              (fun point ->
                for plane = 0 to Array.length values - 1 do
                  values.(plane).(point) <-
                    (original_blend *. original.(plane).(point))
                    +. (blurred_blend *. (!current).(plane).(point))
                done);
            values
          end in
        let invalid = ref None in
        Array.iteri (fun plane values ->
          let point = ref 0 in
          while !point < point_count && !invalid = None do
            if not (Float.is_finite values.(!point)) then
              invalid := Some (plane, !point);
            incr point
          done) output;
        match !invalid with
        | Some (plane, point) -> Error (Printf.sprintf
            "Pdk.Attribute_ops.blur_points: output plane %d is non-finite at point %d"
            plane point)
        | None ->
            let positions_changed = ref false in
            Array.iter (function
              | Blur_position first ->
                  let point = ref 0 in
                  while !point < point_count && not !positions_changed do
                    if output.(first).(!point) <> positions.x.(!point)
                        || output.(first + 1).(!point) <> positions.y.(!point)
                        || output.(first + 2).(!point) <> positions.z.(!point)
                    then positions_changed := true;
                    incr point
                  done
              | Blur_float _ | Blur_float2 _ | Blur_float3 _ | Blur_float4 _ -> ())
              targets;
            let result = if !positions_changed then
                Geometry.with_positions (Packed.Float3.Private.of_owned_exn
                  ~x:output.(0) ~y:output.(1) ~z:output.(2)) geometry
              else Ok geometry in
            Result.bind result (fun geometry ->
              let geometry = if !positions_changed then geometry
                  |> Geometry.without_attribute ~owner:Attribute.Point "N"
                  |> Geometry.without_attribute ~owner:Attribute.Vertex "N"
                else geometry in
              let rec install geometry target =
                if target = Array.length targets then Ok geometry
                else match targets.(target) with
                  | Blur_position _ -> install geometry (target + 1)
                  | Blur_float (source, first) ->
                      Result.bind (Attribute.create_owned ~name:(Attribute.name source)
                          ~owner:Attribute.Point (Attribute.Float output.(first)))
                        (fun attribute -> Result.bind
                          (Geometry.with_attribute attribute geometry)
                          (fun geometry -> install geometry (target + 1)))
                  | Blur_float2 (source, first) ->
                      Result.bind (Packed.Float2.of_owned ~x:output.(first)
                          ~y:output.(first + 1)) (fun values ->
                      Result.bind (Attribute.create_owned ~name:(Attribute.name source)
                          ~owner:Attribute.Point (Attribute.Float2 values))
                        (fun attribute -> Result.bind
                          (Geometry.with_attribute attribute geometry)
                          (fun geometry -> install geometry (target + 1))))
                  | Blur_float3 (source, first) ->
                      let values = Packed.Float3.Private.of_owned_exn
                          ~x:output.(first) ~y:output.(first + 1)
                          ~z:output.(first + 2) in
                      Result.bind (Attribute.create_owned ~name:(Attribute.name source)
                          ~owner:Attribute.Point (Attribute.Float3 values))
                        (fun attribute -> Result.bind
                          (Geometry.with_attribute attribute geometry)
                          (fun geometry -> install geometry (target + 1)))
                  | Blur_float4 (source, first) ->
                      Result.bind (Packed.Float4.of_owned ~x:output.(first)
                          ~y:output.(first + 1) ~z:output.(first + 2)
                          ~w:output.(first + 3)) (fun values ->
                      Result.bind (Attribute.create_owned ~name:(Attribute.name source)
                          ~owner:Attribute.Point (Attribute.Float4 values))
                        (fun attribute -> Result.bind
                          (Geometry.with_attribute attribute geometry)
                          (fun geometry -> install geometry (target + 1)))) in
              install geometry 0)
        )))))
      end))

let blur_points ?cancel ?grain ?selection ?iterations ?method_ ?mode
    ?weight_attribute ?alpha_attribute ?pin_borders ?original_blend
    ?blurred_blend ~pattern geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_blur" ~code:"invalid_blur")
      (blur_points_raw ?cancel ?grain ?selection ?iterations ?method_ ?mode
         ?weight_attribute ?alpha_attribute ?pin_borders ?original_blend
         ?blurred_blend ~pattern geometry)
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_blur"
      ~code:"cancelled" "attribute blur was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_blur"
      ~code:"invalid_parameter" message)

let randomize ?cancel ?(grain = 16_384) ?selection ?element_selection
    ?seed_attribute ?fraction_attribute ?minimum ?maximum
    ?(direction_bias = 0.) ~seed ~owner ~name
    ?(operation = Random_set) ?(scale = 1.) distribution geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_randomize"
        ~code:"invalid_randomize")
      (Attribute_generate.randomize ?cancel ~grain ?selection
         ?element_selection ?seed_attribute ?fraction_attribute ?minimum
         ?maximum ~direction_bias
         ~seed ~owner ~name ~operation ~scale distribution geometry)
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_randomize"
      ~code:"cancelled" "attribute randomization was cancelled")
  | Invalid_argument message -> Error (Error.make
      ~operation:"attribute_randomize" ~code:"invalid_parameter" message)

let noise ?cancel ?(grain = 16_384) ?selection ~seed ~owner ~name ~kind
    ?(location = Noise_position) ?(range = Noise_positive)
    ?(operation = Noise_set) ?(blend = 1.)
    ?(frequency = Vec3.create 1. 1. 1.) ?(offset = Vec3.zero)
    ?(octaves = 1) ?(lacunarity = 2.) ?(roughness = 0.5) geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_noise" ~code:"invalid_noise")
      (Attribute_generate.noise ?cancel ~grain ?selection ~seed ~owner ~name
         ~kind ~location ~range ~operation ~blend ~frequency ~offset ~octaves
         ~lacunarity ~roughness geometry)
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_noise"
      ~code:"cancelled" "attribute noise was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_noise"
      ~code:"invalid_parameter" message)

let remap ?cancel ?(grain = 16_384) ?selection ~owner ~name ?into ~input
    ~output_min ~output_max ?(policy = Remap_clamp) ?(ramp = []) geometry =
  try Result.map_error
      (Error.of_string ~operation:"attribute_remap" ~code:"invalid_remap")
      (Attribute_generate.remap ?cancel ~grain ?selection ~owner ~name ?into
         ~input ~output_min ~output_max ~policy ~ramp geometry)
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_remap"
      ~code:"cancelled" "attribute remapping was cancelled")
  | Invalid_argument message -> Error (Error.make
      ~operation:"attribute_remap" ~code:"invalid_parameter" message)

let copy_rule ?into ~owner pattern = {
  Attribute_copy.copy_owner = owner;
  copy_pattern = pattern;
  copy_into = into;
}

let interpolate_attribute ?into ~owner name =
  if String.trim name = "" then invalid_arg
      "Pdk.Attribute_ops.interpolate_attribute: empty source name";
  if String.equal name "P" && owner <> Attribute.Point then invalid_arg
      "Pdk.Attribute_ops.interpolate_attribute: canonical P must be point owned";
  let target = Option.value ~default:name into in
  if String.trim target = "" then invalid_arg
      "Pdk.Attribute_ops.interpolate_attribute: empty target name";
  { interpolate_owner = owner; interpolate_source = name;
    interpolate_target = target }

let expand_interpolate_patterns ~match_groups ?point_pattern ?vertex_pattern
    ?primitive_pattern ?detail_pattern source =
  let compile owner = function
    | None -> Ok (owner, None)
    | Some source -> Result.map (fun pattern -> owner, Some pattern)
        (Attribute_pattern.compile source) in
  let patterns_result = [
    compile Attribute.Point point_pattern;
    compile Attribute.Vertex vertex_pattern;
    compile Attribute.Primitive primitive_pattern;
    compile Attribute.Detail detail_pattern] in
  Result.bind (List.fold_left (fun result item ->
    Result.bind result (fun values -> Result.map (fun value -> value :: values)
      item)) (Ok []) patterns_result) (fun reversed ->
  let patterns = Array.of_list (List.rev reversed) in
  let pattern owner = Array.find_map (fun (candidate, pattern) ->
      if candidate = owner then pattern else None) patterns in
  let output = ref [] and groups = ref [] in
  (match pattern Attribute.Point with
   | Some pattern when Attribute_pattern.matches pattern "P" ->
       output := interpolate_attribute ~owner:Attribute.Point "P" :: !output
   | None | Some _ -> ());
  List.iter (fun attribute ->
    match pattern (Attribute.owner attribute) with
    | Some pattern when Attribute_pattern.matches pattern
        (Attribute.name attribute) ->
        output := interpolate_attribute ~owner:(Attribute.owner attribute)
            (Attribute.name attribute) :: !output
    | None | Some _ -> ()) (Geometry.attributes source);
  if match_groups then List.iter (fun group ->
    let owner = match Group.owner group with
      | Group.Point -> Attribute.Point
      | Group.Vertex -> Attribute.Vertex
      | Group.Primitive -> Attribute.Primitive in
    match pattern owner with
    | Some pattern when Attribute_pattern.matches pattern (Group.name group) ->
        groups := {
          Attribute_interpolate.group_source_owner = owner;
          group_source = group } :: !groups
    | None | Some _ -> ()) (Geometry.groups source);
  Ok (List.rev !output, List.rev !groups))

let combine_layer ?source ?(source_input = 0) ?(scale = 1.) ?(add = 0.)
    ?(process = Combine_process_none) ?(blend = 1.) ?blend_attribute
    ?(blend_input = 0) operation = {
  Attribute_combine.source;
  source_input;
  operation;
  scale;
  add;
  process;
  blend;
  blend_attribute;
  blend_input;
}

let combine ?cancel ?grain ?selection ?match_attribute ?create_missing
    ?create_missing_as_scalar ?delete_sources ?error_on_missing ?overall_scale
    ?threshold ?minimum ?maximum ~owner ~destination ~layers ~geometries () =
  try Result.map_error
      (Error.of_string ~operation:"attribute_combine" ~code:"invalid_combine")
      (Attribute_combine.combine ?cancel ?grain ?selection ?match_attribute
         ?create_missing ?create_missing_as_scalar ?delete_sources
         ?error_on_missing ?overall_scale ?threshold ?minimum ?maximum
         ~owner ~destination ~layers ~geometries ())
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_combine"
      ~code:"cancelled" "attribute combine was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_combine"
      ~code:"invalid_parameter" message)

let interpolate ?cancel ?grain ?selection ?driver ?compute_weights
    ?point_pattern ?vertex_pattern ?primitive_pattern ?detail_pattern
    ?(match_groups = false)
    ?primitive_attribute ?uvw_attribute ?pre_scale ?normalize_weights ?threshold ?blend
    ?(unmatched = Keep_target) ~target_owner ~attributes ~source ~target () =
  let unmatched = match unmatched with
    | Keep_target -> Attribute_interpolate.Keep_target
    | Default_value -> Attribute_interpolate.Default_value in
  let compute_result = match compute_weights with
    | None -> Ok None
    | Some value ->
        let computed_owner = match value.computed_owner with
          | Attribute.Point -> Ok Attribute_interpolate.Points
          | Attribute.Vertex -> Ok Attribute_interpolate.Vertices
          | Attribute.Primitive | Attribute.Detail -> Error
              "Attribute Interpolate: computed weights require point or vertex ownership" in
        Result.map (fun computed_owner -> Some {
          Attribute_interpolate.computed_owner;
          computed_numbers_attribute = value.computed_numbers_attribute;
          computed_weights_attribute = value.computed_weights_attribute })
          computed_owner in
  let driver_result = match driver, primitive_attribute, uvw_attribute with
    | Some _, Some _, _ | Some _, _, Some _ ->
        Error "Attribute Interpolate: driver is mutually exclusive with primitive_attribute and uvw_attribute"
    | Some driver, None, None -> Ok driver
    | None, primitive_attribute, uvw_attribute -> Ok (Primitive_uvw {
        primitive_attribute = Option.value ~default:"source_primitive"
          primitive_attribute;
        uvw_attribute = Option.value ~default:"source_uvw" uvw_attribute }) in
  try Result.bind (Result.map_error
      (Error.of_string ~operation:"attribute_interpolate"
        ~code:"invalid_interpolate")
      (expand_interpolate_patterns ~match_groups ?point_pattern ?vertex_pattern
        ?primitive_pattern ?detail_pattern source)) (fun (expanded, groups) ->
    let attributes = List.map (fun attribute -> {
      Attribute_interpolate.source_owner = attribute.interpolate_owner;
      source_name = attribute.interpolate_source;
      target_name = attribute.interpolate_target }) (attributes @ expanded) in
    Result.bind (Result.map_error
      (Error.of_string ~operation:"attribute_interpolate"
        ~code:"invalid_interpolate") driver_result) (fun driver ->
    Result.bind (Result.map_error
      (Error.of_string ~operation:"attribute_interpolate"
        ~code:"invalid_interpolate") compute_result) (fun compute ->
    Result.map_error
      (Error.of_string ~operation:"attribute_interpolate"
        ~code:"invalid_interpolate")
      (match driver with
       | Primitive_uvw { primitive_attribute; uvw_attribute } ->
           Attribute_interpolate.interpolate_primitive ?cancel ?grain ?selection
             ?compute ~primitive_attribute ~uvw_attribute ?pre_scale ?blend ~unmatched
             ~target_owner ~attributes ~groups ~source ~target ()
       | Point_weights { numbers_attribute; weights_attribute } ->
           if Option.is_some compute then Error
               "Attribute Interpolate: computed weights require primitive/UVW mode"
           else
           Attribute_interpolate.interpolate_weighted ?cancel ?grain ?selection
             ~numbers_attribute ~weights_attribute ?pre_scale ?normalize_weights
             ?threshold ?blend ~unmatched
             ~weighted_owner:Attribute_interpolate.Points ~target_owner
             ~attributes ~groups ~source ~target ()
       | Vertex_weights { numbers_attribute; weights_attribute } ->
           if Option.is_some compute then Error
               "Attribute Interpolate: computed weights require primitive/UVW mode"
           else
           Attribute_interpolate.interpolate_weighted ?cancel ?grain ?selection
             ~numbers_attribute ~weights_attribute ?pre_scale ?normalize_weights
             ?threshold ?blend ~unmatched
             ~weighted_owner:Attribute_interpolate.Vertices ~target_owner
             ~attributes ~groups ~source ~target ()
       | Primitive_weights { numbers_attribute; weights_attribute } ->
           if Option.is_some compute then Error
               "Attribute Interpolate: computed weights require primitive/UVW mode"
           else
           Attribute_interpolate.interpolate_weighted ?cancel ?grain ?selection
             ~numbers_attribute ~weights_attribute ?pre_scale ?normalize_weights
             ?threshold ?blend ~unmatched
             ~weighted_owner:Attribute_interpolate.Primitives ~target_owner
             ~attributes ~groups ~source ~target ()))))
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_interpolate"
      ~code:"cancelled" "attribute interpolation was cancelled")
  | Invalid_argument message -> Error (Error.make
      ~operation:"attribute_interpolate" ~code:"invalid_parameter" message)

let copy ?cancel ?grain ?source_group ?target_group ?match_ ?allow_position
    ~group_owner ~rules ~source ~target () =
  try Result.map_error
      (Error.of_string ~operation:"attribute_copy" ~code:"invalid_copy")
      (Attribute_copy.copy ?cancel ?grain ?source_group ?target_group ?match_
         ?allow_position ~group_owner ~rules ~source ~target ())
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_copy"
      ~code:"cancelled" "attribute copy was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_copy"
      ~code:"invalid_parameter" message)

let same_kind left right =
  String.equal (Attribute.kind_name left) (Attribute.kind_name right)

let owner_label = function
  | Attribute.Point -> "point"
  | Attribute.Vertex -> "vertex"
  | Attribute.Primitive -> "primitive"
  | Attribute.Detail -> "detail"

let selected_attributes ~operation ~owner ~names ~pattern source =
  let available = Geometry.attributes source
      |> List.filter (fun attribute -> Attribute.owner attribute = owner) in
  match names, pattern with
  | Some _, Some _ -> Error
      (operation ^ ": names and pattern are mutually exclusive")
  | None, None -> Ok (Array.of_list available)
  | None, Some source ->
      Result.map (fun pattern -> available
        |> List.filter (fun attribute ->
          Attribute_pattern.matches pattern (Attribute.name attribute))
        |> Array.of_list)
        (Attribute_pattern.compile source)
  | Some names, None ->
      let seen = Hashtbl.create (List.length names) in
      let rec collect result = function
        | [] -> Ok (Array.of_list (List.rev result))
        | name :: _ when String.trim name = "" ->
            Error (operation ^ ": attribute names must not be empty")
        | "P" :: _ when owner = Attribute.Point ->
            Error (operation ^ ": canonical P cannot be transferred as an ordinary attribute")
        | name :: _ when Hashtbl.mem seen name ->
            Error (operation ^ ": duplicate attribute name " ^ name)
        | name :: rest ->
            Hashtbl.add seen name ();
            (match Geometry.find_attribute ~owner name source with
             | None -> Error
                 (Printf.sprintf "%s: missing source %s attribute %s"
                    operation (owner_label owner) name)
             | Some attribute -> collect (attribute :: result) rest)
      in
      collect [] names

let validate_target_kinds ~operation ~owner attributes target =
  Array.fold_left (fun result source_attribute ->
    Result.bind result (fun () ->
      match Geometry.find_attribute ~owner
          (Attribute.name source_attribute) target with
      | None -> Ok ()
      | Some target_attribute when same_kind source_attribute target_attribute -> Ok ()
      | Some target_attribute -> Error (Printf.sprintf
          "%s: target attribute %s has %s storage, source has %s"
          operation
          (Attribute.name source_attribute) (Attribute.kind_name target_attribute)
          (Attribute.kind_name source_attribute)))) (Ok ()) attributes

let validate_sampled_storage ~operation attributes =
  Array.fold_left (fun result attribute ->
    Result.bind result (fun () ->
      match Attribute.Private.storage attribute with
      | Attribute.Int_array _ | Attribute.Float_array _ -> Error (Printf.sprintf
          "%s: sampled transfer of array attribute %s requires an explicit array policy"
          operation (Attribute.name attribute))
      | Attribute.Float _ | Attribute.Int _ | Attribute.Float2 _
      | Attribute.Float3 _ | Attribute.Float4 _ | Attribute.Text _ -> Ok ()))
    (Ok ()) attributes

let make_attribute_array count make =
  if count = 0 then Ok [||]
  else Result.bind (make 0) (fun first ->
    let attributes = Array.make count first in
    let rec fill index =
      if index = count then Ok attributes
      else Result.bind (make index) (fun attribute ->
        attributes.(index) <- attribute;
        fill (index + 1)) in
    fill 1)

let install_attributes_batch geometry attributes =
  Geometry.Private.with_merged_attributes_owned attributes geometry

let reset_selected selection reset = match selection with
  | None -> ()
  | Some group -> Group.iter reset group

let initial_float ?selection unmatched target_attribute count =
  match unmatched, target_attribute with
  | Keep_target, Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values -> Array.copy values | _ -> assert false)
  | Default_value, Some attribute when selection <> None ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float values ->
           let output = Array.copy values in
           reset_selected selection (fun element -> output.(element) <- 0.);
           output
       | _ -> assert false)
  | Keep_target, None | Default_value, _ -> Array.make count 0.

let initial_int ?selection unmatched target_attribute count =
  match unmatched, target_attribute with
  | Keep_target, Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values -> Array.copy values | _ -> assert false)
  | Default_value, Some attribute when selection <> None ->
      (match Attribute.Private.storage attribute with
       | Attribute.Int values ->
           let output = Array.copy values in
           reset_selected selection (fun element -> output.(element) <- 0);
           output
       | _ -> assert false)
  | Keep_target, None | Default_value, _ -> Array.make count 0

let initial_text ?selection unmatched target_attribute count =
  match unmatched, target_attribute with
  | Keep_target, Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text values -> Array.copy values | _ -> assert false)
  | Default_value, Some attribute when selection <> None ->
      (match Attribute.Private.storage attribute with
       | Attribute.Text values ->
           let output = Array.copy values in
           reset_selected selection (fun element -> output.(element) <- "");
           output
       | _ -> assert false)
  | Keep_target, None | Default_value, _ -> Array.make count ""

let initial_float2 ?selection unmatched target_attribute count =
  match unmatched, target_attribute with
  | Keep_target, Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values ->
           let values = Packed.Float2.Private.view values in
           Array.copy values.x, Array.copy values.y
       | _ -> assert false)
  | Default_value, Some attribute when selection <> None ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float2 values ->
           let values = Packed.Float2.Private.view values in
           let x = Array.copy values.x and y = Array.copy values.y in
           reset_selected selection (fun element ->
             x.(element) <- 0.; y.(element) <- 0.);
           x, y
       | _ -> assert false)
  | Keep_target, None | Default_value, _ -> Array.make count 0., Array.make count 0.

let initial_float3 ?selection unmatched target_attribute count =
  match unmatched, target_attribute with
  | Keep_target, Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values ->
           let values = Packed.Float3.Private.view values in
           Array.copy values.x, Array.copy values.y, Array.copy values.z
       | _ -> assert false)
  | Default_value, Some attribute when selection <> None ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float3 values ->
           let values = Packed.Float3.Private.view values in
           let x = Array.copy values.x and y = Array.copy values.y
           and z = Array.copy values.z in
           reset_selected selection (fun element ->
             x.(element) <- 0.; y.(element) <- 0.; z.(element) <- 0.);
           x, y, z
       | _ -> assert false)
  | Keep_target, None | Default_value, _ ->
      Array.make count 0., Array.make count 0., Array.make count 0.

let initial_float4 ?selection unmatched target_attribute count =
  match unmatched, target_attribute with
  | Keep_target, Some attribute ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values ->
           let values = Packed.Float4.Private.view values in
           Array.copy values.x, Array.copy values.y, Array.copy values.z,
           Array.copy values.w
       | _ -> assert false)
  | Default_value, Some attribute when selection <> None ->
      (match Attribute.Private.storage attribute with
       | Attribute.Float4 values ->
           let values = Packed.Float4.Private.view values in
           let x = Array.copy values.x and y = Array.copy values.y
           and z = Array.copy values.z and w = Array.copy values.w in
           reset_selected selection (fun element ->
             x.(element) <- 0.; y.(element) <- 0.; z.(element) <- 0.;
             w.(element) <- 0.);
           x, y, z, w
       | _ -> assert false)
  | Keep_target, None | Default_value, _ ->
      Array.make count 0., Array.make count 0., Array.make count 0.,
      Array.make count 0.

let group_owner_of_attribute = function
  | Attribute.Point -> Group.Point
  | Attribute.Vertex -> Group.Vertex
  | Attribute.Primitive -> Group.Primitive
  | Attribute.Detail -> invalid_arg "detail attributes do not have element groups"

let validate_transfer_falloff operation = function
  | Linear | Smoothstep -> Ok ()
  | Uniform bias when Float.is_finite bias && bias >= 0. && bias <= 1. -> Ok ()
  | Uniform _ -> Error (operation ^ ": uniform bias must be finite and in [0, 1]")

let transfer_distance_window ~operation ~blend_width ~falloff max_distance =
  if not (Float.is_finite blend_width) || blend_width < 0. then Error
      (operation ^ ": blend width must be finite and non-negative")
  else Result.bind (validate_transfer_falloff operation falloff) (fun () ->
    match max_distance with
    | None when blend_width > 0. -> Error
        (operation ^ ": blend width requires a maximum distance")
    | None -> Ok (Float.infinity, Float.infinity)
    | Some value when Float.is_finite value && value >= 0.
        && value <= sqrt max_float ->
        let outer = value +. blend_width in
        if not (Float.is_finite outer) || outer > sqrt max_float then Error
            (operation ^ ": distance plus blend width must be safely squarable")
        else Ok (value *. value, outer *. outer)
    | Some _ -> Error
        (operation ^
         ": maximum distance must be finite, non-negative, and safely squarable"))

let[@inline] transfer_influence ~falloff ~threshold_squared ~blend_width
    distance_squared =
  if blend_width = 0. || distance_squared <= threshold_squared then 1.
  else
    let threshold = sqrt threshold_squared in
    let remaining = 1. -. ((sqrt distance_squared -. threshold) /. blend_width) in
    let remaining = Float.max 0. (Float.min 1. remaining) in
    match falloff with
    | Linear -> remaining
    | Smoothstep -> remaining *. remaining *. (3. -. (2. *. remaining))
    | Uniform bias -> bias

let[@inline always] transfer_kernel_weight kernel t =
  if t >= 1. then 0.
  else
    let t = Float.max 0. t in
    match kernel with
    | Links ->
        if t < (1. /. 3.) then 1. -. (3. *. t *. t)
        else 1.5 *. (1. -. t) *. (1. -. t)
    | RenderMan ->
        let one_minus_square = 1. -. (t *. t) in
        one_minus_square *. one_minus_square *. one_minus_square
    | Hart ->
        let t2 = t *. t and t3 = t *. t *. t in
        1. -. (10. *. t3) +. (15. *. t2 *. t2) -.
          (6. *. t2 *. t3)

let primitive_barycenters ?cancel ~grain geometry =
  let topology = Topology.Private.view (Geometry.topology geometry)
  and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
  let count = Geometry.primitive_count geometry in
  let x = Array.make count 0. and y = Array.make count 0.
  and z = Array.make count 0. in
  if count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
      ~finish:(count - 1) (fun primitive ->
        if primitive land 4095 = 0 then Cancel.check_opt cancel;
        let first = topology.primitive_offsets.(primitive)
        and last = topology.primitive_offsets.(primitive + 1) in
        let sx = ref 0. and sy = ref 0. and sz = ref 0. in
        for vertex = first to last - 1 do
          let point = topology.vertex_points.(vertex) in
          sx := !sx +. positions.x.(point);
          sy := !sy +. positions.y.(point);
          sz := !sz +. positions.z.(point)
        done;
        let scale = 1. /. float_of_int (last - first) in
        x.(primitive) <- !sx *. scale;
        y.(primitive) <- !sy *. scale;
        z.(primitive) <- !sz *. scale);
  Packed.Float3.Private.of_owned_exn ~x ~y ~z

let transfer_spatial_raw ?cancel ?(grain = 16_384) ?names ?pattern
    ?(mode = Nearest) ?max_distance ?(blend_width = 0.)
    ?(falloff = Smoothstep) ?(unmatched = Keep_target)
    ?source_elements ?target_elements
    ~operation ~owner ~source_positions ~target_positions ~source ~target () =
  if owner = Attribute.Detail || owner = Attribute.Vertex then invalid_arg
      (operation ^ ": spatial samples require point or primitive ownership");
  if grain <= 0 then invalid_arg (operation ^ ": grain must be positive");
  Cancel.check_opt cancel;
  let neighbor_capacity_result = match mode with
    | Nearest -> Ok 1
    | Inverse_distance { neighbors; power }
      when neighbors > 0 && Float.is_finite power && power > 0. -> Ok neighbors
    | Inverse_distance _ -> Error
        (operation ^ ": neighbors and power must be positive; power must be finite")
    | Kernel { neighbors; radius; _ }
      when neighbors > 0 && Float.is_finite radius && radius >= 0.
        && radius <= sqrt max_float -> Ok neighbors
    | Kernel _ -> Error
        (operation ^
         ": kernel neighbors must be positive and radius must be finite, non-negative, and safely squarable") in
  let maximum_result = transfer_distance_window ~operation ~blend_width ~falloff
      max_distance in
  let expected_group_owner = group_owner_of_attribute owner
  and source_count = owner_count source owner
  and target_count = owner_count target owner in
  let groups_result =
    if (match source_elements with None -> false | Some group ->
        Group.owner group <> expected_group_owner
        || Group.length group <> source_count) then
      Error (Printf.sprintf "%s: source selection must be a matching %s group"
        operation (owner_label owner))
    else if (match target_elements with None -> false | Some group ->
        Group.owner group <> expected_group_owner
        || Group.length group <> target_count) then
      Error (Printf.sprintf "%s: target selection must be a matching %s group"
        operation (owner_label owner))
    else Ok () in
  Result.bind neighbor_capacity_result (fun neighbor_capacity ->
  Result.bind maximum_result (fun (threshold_squared, maximum_squared) ->
  Result.bind groups_result (fun () ->
  Result.bind (selected_attributes ~operation ~owner ~names ~pattern source)
      (fun attributes ->
  Result.bind (validate_sampled_storage ~operation attributes) (fun () ->
  Result.bind (validate_target_kinds ~operation ~owner attributes target) (fun () ->
  if Array.length attributes = 0 then Ok target else
  if target_count > Sys.max_array_length / neighbor_capacity then Error
      (operation ^ ": neighbor table is too large")
  else
    let source_positions = source_positions ()
    and target_positions = target_positions () in
    if Packed.Float3.length source_positions <> source_count
       || Packed.Float3.length target_positions <> target_count then
      invalid_arg (operation ^ ": internal sample cardinality mismatch");
    let source_points = Option.map
        (Group.Private.with_owner Group.Point) source_elements
    and target_points = Option.map
        (Group.Private.with_owner Group.Point) target_elements in
    match Spatial_index.create ?cancel ~grain ?points:source_points source_positions with
    | Error error when String.equal (Error.code error) "cancelled" ->
        raise Cancel.Cancelled
    | Error error -> Error (Error.to_string error)
    | Ok index ->
        let target_view = Packed.Float3.Private.view target_positions in
        for element = 0 to target_count - 1 do
          if element land 16_383 = 0 then Cancel.check_opt cancel;
          if (match target_elements with None -> true
              | Some group -> Group.mem element group)
             && not (Float.is_finite target_view.x.(element)
              && Float.is_finite target_view.y.(element)
              && Float.is_finite target_view.z.(element)) then
            invalid_arg "target positions must be finite"
        done;
        let slots = target_count * neighbor_capacity in
        let neighbors = Array.make slots (-1)
        and distances = Array.make slots Float.infinity
        and neighbor_counts = Array.make target_count 0 in
        Spatial_index.Private.nearest_k_many_into ?cancel ?points:target_points
          ~grain index
          ~queries:target_positions
          ~max_distance_squared:maximum_squared ~capacity:neighbor_capacity
          ~indices:neighbors ~distances_squared:distances
          ~counts:neighbor_counts;
        let influence = if blend_width = 0. then None
          else
            let values = Array.make target_count 0. in
            if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                ~finish:(target_count - 1) (fun target_element ->
                  if target_element land 4095 = 0 then Cancel.check_opt cancel;
                  if neighbor_counts.(target_element) > 0 then
                    values.(target_element) <- transfer_influence ~falloff
                      ~threshold_squared ~blend_width
                      distances.(target_element * neighbor_capacity));
            Some values in
        let sample_weights = match mode with
          | Nearest -> None
          | Inverse_distance { power; _ } ->
              let weights = distances in
              if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(target_count - 1) (fun target_element ->
                    if target_element land 4095 = 0 then Cancel.check_opt cancel;
                    let count = neighbor_counts.(target_element) in
                    if count > 0 then begin
                      let offset = target_element * neighbor_capacity
                      and nearest_distance = distances.(target_element
                        * neighbor_capacity) in
                      if nearest_distance = 0.
                          || not (Float.is_finite nearest_distance) then begin
                        for slot = 0 to count - 1 do
                          weights.(offset + slot) <- 0.
                        done;
                        weights.(offset) <- 1.
                      end
                      else begin
                        let nearest = sqrt nearest_distance and total = ref 0. in
                        for slot = 0 to count - 1 do
                          let weight =
                            (nearest /. sqrt distances.(offset + slot)) ** power in
                          weights.(offset + slot) <- weight;
                          total := !total +. weight
                        done;
                        let inverse = 1. /. !total in
                        for slot = 0 to count - 1 do
                          weights.(offset + slot) <-
                            weights.(offset + slot) *. inverse
                        done
                      end
                    end);
              Some weights
          | Kernel { radius; kernel; _ } ->
              let weights = distances in
              if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(target_count - 1) (fun target_element ->
                    if target_element land 4095 = 0 then Cancel.check_opt cancel;
                    let count = neighbor_counts.(target_element) in
                    if count > 0 then begin
                      let offset = target_element * neighbor_capacity in
                      if radius = 0. then begin
                        for slot = 0 to count - 1 do
                          weights.(offset + slot) <- 0.
                        done;
                        weights.(offset) <- 1.
                      end
                      else begin
                        let total = ref 0. in
                        for slot = 0 to count - 1 do
                          let weight = transfer_kernel_weight kernel
                              (sqrt distances.(offset + slot) /. radius) in
                          weights.(offset + slot) <- weight;
                          total := !total +. weight
                        done;
                        if !total > 0. && Float.is_finite !total then begin
                          let inverse = 1. /. !total in
                          for slot = 0 to count - 1 do
                            weights.(offset + slot) <-
                              weights.(offset + slot) *. inverse
                          done
                        end else begin
                          for slot = 0 to count - 1 do
                            weights.(offset + slot) <- 0.
                          done;
                          weights.(offset) <- 1.
                        end
                      end
                    end);
              Some weights in
        let transfer_plane source_values output =
          if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(target_count - 1) (fun target_element ->
                if target_element land 4095 = 0 then Cancel.check_opt cancel;
                let count = neighbor_counts.(target_element) in
                if count > 0 then begin
                  let offset = target_element * neighbor_capacity in
                  let sampled = match mode with
                  | Nearest -> source_values.(neighbors.(offset))
                  | Inverse_distance _ | Kernel _ ->
                      let weights = Option.get sample_weights
                      and weighted = ref 0. in
                      for slot = 0 to count - 1 do
                        weighted := !weighted +. (weights.(offset + slot) *.
                          source_values.(neighbors.(offset + slot)))
                      done;
                      !weighted in
                  output.(target_element) <- match influence with
                  | None -> sampled
                  | Some values -> output.(target_element) +.
                      (values.(target_element) *.
                       (sampled -. output.(target_element)))
                end) in
        let transfer_discrete source_values output =
          if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(target_count - 1) (fun target_element ->
                if target_element land 4095 = 0 then Cancel.check_opt cancel;
                if neighbor_counts.(target_element) > 0
                    && (match influence with None -> true
                        | Some values -> values.(target_element) >= 0.5) then
                  output.(target_element) <- source_values.(neighbors.(
                    target_element * neighbor_capacity))) in
        let make_attribute source_attribute =
          let name = Attribute.name source_attribute in
          let existing = Geometry.find_attribute ~owner name target in
          let storage = match Attribute.Private.storage source_attribute with
            | Attribute.Float source_values ->
                let output = initial_float ?selection:target_elements
                    unmatched existing target_count in
                transfer_plane source_values output;
                Attribute.Float output
            | Attribute.Int source_values ->
                let output = initial_int ?selection:target_elements
                    unmatched existing target_count in
                transfer_discrete source_values output;
                Attribute.Int output
            | Attribute.Text source_values ->
                let output = initial_text ?selection:target_elements
                    unmatched existing target_count in
                transfer_discrete source_values output;
                Attribute.Text output
            | Attribute.Float2 source_values ->
                let source_values = Packed.Float2.Private.view source_values in
                let x, y = initial_float2 ?selection:target_elements
                    unmatched existing target_count in
                transfer_plane source_values.x x; transfer_plane source_values.y y;
                Attribute.Float2 (Packed.Float2.of_owned ~x ~y |> Result.get_ok)
            | Attribute.Float3 source_values ->
                let source_values = Packed.Float3.Private.view source_values in
                let x, y, z = initial_float3 ?selection:target_elements
                    unmatched existing target_count in
                transfer_plane source_values.x x; transfer_plane source_values.y y;
                transfer_plane source_values.z z;
                if String.equal name "N" && target_count > 0 then
                  Parallel.for_ ~chunk_size:grain ~start:0
                    ~finish:(target_count - 1) (fun target_element ->
                      if neighbor_counts.(target_element) > 0
                          && (match influence with None -> true
                              | Some values -> values.(target_element) > 0.) then begin
                        let length = sqrt ((x.(target_element) *. x.(target_element))
                          +. (y.(target_element) *. y.(target_element))
                          +. (z.(target_element) *. z.(target_element))) in
                        if length > 1e-20 then begin
                          x.(target_element) <- x.(target_element) /. length;
                          y.(target_element) <- y.(target_element) /. length;
                          z.(target_element) <- z.(target_element) /. length
                        end
                      end);
                Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)
            | Attribute.Float4 source_values ->
                let source_values = Packed.Float4.Private.view source_values in
                let x, y, z, w = initial_float4 ?selection:target_elements
                    unmatched existing target_count in
                transfer_plane source_values.x x; transfer_plane source_values.y y;
                transfer_plane source_values.z z; transfer_plane source_values.w w;
                Attribute.Float4 (Packed.Float4.of_owned ~x ~y ~z ~w
                  |> Result.get_ok)
            | Attribute.Int_array _ | Attribute.Float_array _ -> assert false in
          Attribute.create_owned ~name ~owner storage
        in
        Result.bind (make_attribute_array (Array.length attributes)
            (fun index -> make_attribute attributes.(index)))
          (install_attributes_batch target)))))))

let transfer_points_raw ?cancel ?grain ?names ?pattern ?mode ?max_distance
    ?blend_width ?falloff ?unmatched ?source_points ?target_points
    ~source ~target () =
  transfer_spatial_raw ?cancel ?grain ?names ?pattern ?mode ?max_distance
    ?blend_width ?falloff ?unmatched
    ?source_elements:source_points ?target_elements:target_points
    ~operation:"Pdk.Attribute_ops.transfer_points" ~owner:Attribute.Point
    ~source_positions:(fun () -> Geometry.positions source)
    ~target_positions:(fun () -> Geometry.positions target)
    ~source ~target ()

let transfer_points ?cancel ?grain ?names ?pattern ?mode ?max_distance ?blend_width
    ?falloff ?unmatched ?source_points ?target_points ~source ~target () =
  try Result.map_error
      (Error.of_string ~operation:"attribute_transfer" ~code:"invalid_transfer")
      (transfer_points_raw ?cancel ?grain ?names ?pattern ?mode ?max_distance
         ?blend_width ?falloff ?unmatched ?source_points ?target_points
         ~source ~target ())
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_transfer"
      ~code:"cancelled" "attribute transfer was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_transfer"
      ~code:"invalid_position" message)

let transfer_primitives_raw ?cancel ?grain ?names ?pattern ?mode ?max_distance
    ?blend_width ?falloff ?unmatched
    ?source_primitives ?target_primitives ~source ~target () =
  let grain = Option.value ~default:16_384 grain in
  transfer_spatial_raw ?cancel ~grain ?names ?pattern ?mode ?max_distance
    ?blend_width ?falloff ?unmatched
    ?source_elements:source_primitives ?target_elements:target_primitives
    ~operation:"Pdk.Attribute_ops.transfer_primitives"
    ~owner:Attribute.Primitive
    ~source_positions:(fun () -> primitive_barycenters ?cancel ~grain source)
    ~target_positions:(fun () -> primitive_barycenters ?cancel ~grain target)
    ~source ~target ()

let transfer_primitives ?cancel ?grain ?names ?pattern ?mode ?max_distance
    ?blend_width ?falloff ?unmatched
    ?source_primitives ?target_primitives ~source ~target () =
  try Result.map_error
      (Error.of_string ~operation:"attribute_transfer" ~code:"invalid_transfer")
      (transfer_primitives_raw ?cancel ?grain ?names ?pattern ?mode ?max_distance
         ?blend_width ?falloff ?unmatched
         ?source_primitives ?target_primitives ~source ~target ())
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_transfer"
      ~code:"cancelled" "attribute transfer was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_transfer"
      ~code:"invalid_position" message)

let transfer_detail_raw ?names ?pattern ~source ~target () =
  Result.bind (selected_attributes ~operation:"Pdk.Attribute_ops.transfer_detail"
      ~owner:Attribute.Detail ~names ~pattern source) (fun attributes ->
    Result.bind (validate_target_kinds
        ~operation:"Pdk.Attribute_ops.transfer_detail" ~owner:Attribute.Detail
        attributes target) (fun () ->
      install_attributes_batch target attributes))

let transfer_detail ?names ?pattern ~source ~target () =
  Result.map_error
    (Error.of_string ~operation:"attribute_transfer" ~code:"invalid_transfer")
    (transfer_detail_raw ?names ?pattern ~source ~target ())

type surface_attribute = {
  source_owner : Attribute.owner;
  source_name : string;
  target_name : string;
}

let surface_attribute ?into ~owner name =
  if owner = Attribute.Detail then
    invalid_arg "Pdk.Attribute_ops.surface_attribute: detail ownership is not spatial";
  if String.trim name = "" then
    invalid_arg "Pdk.Attribute_ops.surface_attribute: empty source name";
  let target_name = Option.value ~default:name into in
  if String.trim target_name = "" then
    invalid_arg "Pdk.Attribute_ops.surface_attribute: empty target name";
  if owner = Attribute.Point && String.equal name "P" then
    invalid_arg "Pdk.Attribute_ops.surface_attribute: canonical P is not an ordinary attribute";
  { source_owner = owner; source_name = name; target_name }

let transfer_surface_raw ?cancel ?(grain = 16_384) ?max_distance
    ?(blend_width = 0.) ?(falloff = Smoothstep) ?(unmatched = Keep_target)
    ?(target_owner = Attribute.Point) ?distance_attribute ?source_primitives
    ?source_vertices ?(source_vertex_selection = All_triangle_vertices)
    ?target_points ?target_elements
    ~attributes ~source ~target () =
  if grain <= 0 then invalid_arg
      "Pdk.Attribute_ops.transfer_surface: grain must be positive";
  Cancel.check_opt cancel;
  let operation = "Pdk.Attribute_ops.transfer_surface" in
  Result.bind (transfer_distance_window ~operation ~blend_width ~falloff
      max_distance) (fun (threshold_squared, maximum_squared) ->
  let specifications = Array.of_list attributes in
  let source_attributes = Array.make (Array.length specifications) None in
  let seen = Hashtbl.create (Array.length specifications + 1) in
  let failure = ref None in
  let target_selection = match target_points, target_elements with
    | Some _, Some _ ->
        failure := Some "target_points and target_elements are mutually exclusive";
        None
    | Some group, None ->
        if target_owner <> Attribute.Point then
          failure := Some "target_points requires point destination ownership";
        Some group
    | None, Some group -> Some group
    | None, None -> None in
  if target_owner = Attribute.Detail then
    failure := Some "detail ownership is not a spatial surface destination";
  (match source_primitives with
   | Some group when Group.owner group <> Group.Primitive
       || Group.length group <> Geometry.primitive_count source ->
       failure := Some "source selection must be a matching primitive group"
   | None | Some _ -> ());
  (match source_vertices with
   | Some group when Group.owner group <> Group.Vertex
       || Group.length group <> Geometry.vertex_count source ->
       failure := Some "source vertex selection must be a matching vertex group"
   | None | Some _ -> ());
  (match target_selection with
   | Some group when
       let expected_owner, expected_length = match target_owner with
         | Attribute.Point -> Group.Point, Geometry.point_count target
         | Attribute.Vertex -> Group.Vertex, Geometry.vertex_count target
         | Attribute.Primitive -> Group.Primitive, Geometry.primitive_count target
         | Attribute.Detail -> Group.Point, 0 in
       Group.owner group <> expected_owner || Group.length group <> expected_length ->
       failure := Some "target selection owner/length does not match destination elements"
   | None | Some _ -> ());
  Array.iteri (fun index specification ->
    if !failure = None then begin
      if specification.source_owner = Attribute.Detail then
        failure := Some "detail attributes are not spatial surface attributes"
      else if String.trim specification.source_name = ""
           || String.trim specification.target_name = "" then
        failure := Some "attribute names must not be empty"
      else if specification.source_owner = Attribute.Point
          && String.equal specification.source_name "P" then
        failure := Some "canonical P cannot be transferred as an ordinary attribute"
      else if target_owner = Attribute.Point
          && String.equal specification.target_name "P" then
        failure := Some "canonical target P cannot be an ordinary attribute"
      else if Hashtbl.mem seen specification.target_name then
        failure := Some ("duplicate target attribute " ^ specification.target_name)
      else begin
        Hashtbl.add seen specification.target_name ();
        match Geometry.find_attribute ~owner:specification.source_owner
            specification.source_name source with
        | None -> failure := Some (Printf.sprintf "missing source %s attribute %s"
            (match specification.source_owner with Point -> "point" | Vertex -> "vertex"
             | Primitive -> "primitive" | Detail -> "detail")
            specification.source_name)
        | Some attribute ->
            (match Attribute.Private.storage attribute with
             | Attribute.Int_array _ | Attribute.Float_array _ ->
                 failure := Some (Printf.sprintf
                   "sampled transfer of array attribute %s requires an explicit array policy"
                   specification.source_name)
             | Attribute.Float _ | Attribute.Int _ | Attribute.Float2 _
             | Attribute.Float3 _ | Attribute.Float4 _ | Attribute.Text _ ->
                 (match Geometry.find_attribute ~owner:target_owner
                     specification.target_name target with
                  | Some target_attribute when not (same_kind attribute target_attribute) ->
                      failure := Some (Printf.sprintf
                        "target attribute %s has %s storage, source has %s"
                        specification.target_name (Attribute.kind_name target_attribute)
                        (Attribute.kind_name attribute))
                  | _ -> source_attributes.(index) <- Some attribute))
      end
    end) specifications;
  let distance_name = match distance_attribute with
    | None -> None
    | Some name when String.trim name = "" ->
        failure := Some "distance attribute name must not be empty"; None
    | Some name when Hashtbl.mem seen name ->
        failure := Some ("distance attribute conflicts with " ^ name); None
    | Some "P" when target_owner = Attribute.Point ->
        failure := Some "canonical target P cannot store transfer distance"; None
    | Some name ->
        (match Geometry.find_attribute ~owner:target_owner name target with
         | Some attribute when Attribute.kind_name attribute <> "float" ->
             failure := Some ("distance target attribute " ^ name ^ " is not float")
         | _ -> ());
        Some name in
  match !failure with Some message -> Error message | None ->
  if Array.length specifications = 0 && distance_name = None then Ok target
  else if (match source_primitives, source_vertices with
      | Some group, _ when Group.cardinality group = 0 -> true
      | _, Some group when Group.cardinality group = 0 -> true
      | None, None | None, Some _ | Some _, None | Some _, Some _ ->
          Geometry.primitive_count source = 0) then begin
    let target_count = owner_count target target_owner in
    let make_unmatched_attribute index =
      let specification = specifications.(index)
      and source_attribute = Option.get source_attributes.(index) in
      let existing = Geometry.find_attribute ~owner:target_owner
          specification.target_name target in
      let storage = match Attribute.Private.storage source_attribute with
        | Attribute.Float _ -> Attribute.Float
            (initial_float ?selection:target_selection unmatched existing target_count)
        | Attribute.Int _ -> Attribute.Int
            (initial_int ?selection:target_selection unmatched existing target_count)
        | Attribute.Text _ -> Attribute.Text
            (initial_text ?selection:target_selection unmatched existing target_count)
        | Attribute.Float2 _ ->
            let x, y = initial_float2 ?selection:target_selection unmatched existing
                target_count in
            Attribute.Float2 (Packed.Float2.of_owned ~x ~y |> Result.get_ok)
        | Attribute.Float3 _ ->
            let x, y, z = initial_float3 ?selection:target_selection unmatched existing
                target_count in
            Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)
        | Attribute.Float4 _ ->
            let x, y, z, w = initial_float4 ?selection:target_selection unmatched
                existing target_count in
            Attribute.Float4
              (Packed.Float4.of_owned ~x ~y ~z ~w |> Result.get_ok)
        | Attribute.Int_array _ | Attribute.Float_array _ -> assert false in
      Attribute.create_owned ~name:specification.target_name ~owner:target_owner storage in
    let attribute_count = Array.length specifications
        + if distance_name = None then 0 else 1 in
    Result.bind (make_attribute_array attribute_count (fun index ->
      if index < Array.length specifications then make_unmatched_attribute index
      else
        let name = Option.get distance_name in
        let existing = Geometry.find_attribute ~owner:target_owner name target in
        let values = initial_float ?selection:target_selection unmatched existing
            target_count in
        Attribute.create_owned ~name ~owner:target_owner (Attribute.Float values)))
      (install_attributes_batch target)
  end
  else match Surface_index.create ?cancel ~grain ?primitives:source_primitives
      ?vertices:source_vertices ~vertex_selection:source_vertex_selection source with
  | Error error when String.equal (Error.code error) "cancelled" -> raise Cancel.Cancelled
  | Error error -> Error (Error.to_string error)
  | Ok surface ->
      let target_count = owner_count target target_owner in
      let query_positions, position_indices = match target_owner with
        | Attribute.Point -> Geometry.positions target, None
        | Attribute.Vertex ->
            let topology = Topology.Private.view (Geometry.topology target) in
            Geometry.positions target, Some topology.vertex_points
        | Attribute.Primitive -> primitive_barycenters ?cancel ~grain target, None
        | Attribute.Detail -> assert false in
      let primitives = Array.make target_count (-1)
      and triangles = Array.make target_count (-1)
      and barycentric_a = Array.make target_count 0.
      and barycentric_b = Array.make target_count 0.
      and barycentric_c = Array.make target_count 0.
      and distances_squared = Array.make target_count Float.infinity in
      Surface_index.Private.closest_many_into ?cancel ?selection:target_selection
        ?position_indices ~grain surface ~queries:query_positions
        ~max_distance_squared:maximum_squared
        ~primitives ~triangles ~barycentric_a ~barycentric_b ~barycentric_c
        ~distances_squared;
      let influence = if blend_width = 0. then None
        else
          let values = Array.make target_count 0. in
          if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(target_count - 1) (fun point ->
                if primitives.(point) >= 0 then
                  values.(point) <- transfer_influence ~falloff
                    ~threshold_squared ~blend_width distances_squared.(point));
          Some values in
      let source_topology = Topology.Private.view (Geometry.topology source) in
      let source_element owner primitive triangle local = match owner with
        | Attribute.Point ->
            let vertex = Surface_index.Private.triangle_vertex surface triangle local in
            source_topology.vertex_points.(vertex)
        | Attribute.Vertex ->
            Surface_index.Private.triangle_vertex surface triangle local
        | Attribute.Primitive -> primitive
        | Attribute.Detail -> 0 in
      let transfer_numeric owner source_values output =
        if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(target_count - 1) (fun point ->
              if point land 4095 = 0 then Cancel.check_opt cancel;
              let primitive = primitives.(point) in
              if primitive >= 0 then
                let sampled = if owner = Attribute.Primitive then source_values.(primitive)
                  else
                    (barycentric_a.(point) *.
                       source_values.(source_element owner primitive triangles.(point) 0))
                    +. (barycentric_b.(point) *.
                       source_values.(source_element owner primitive triangles.(point) 1))
                    +. (barycentric_c.(point) *.
                       source_values.(source_element owner primitive triangles.(point) 2)) in
                output.(point) <- match influence with
                | None -> sampled
                | Some values -> output.(point)
                    +. (values.(point) *. (sampled -. output.(point)))) in
      let transfer_discrete owner source_values output =
        if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
            ~finish:(target_count - 1) (fun point ->
              if point land 4095 = 0 then Cancel.check_opt cancel;
              let primitive = primitives.(point) in
              if primitive >= 0
                  && (match influence with None -> true
                      | Some values -> values.(point) >= 0.5) then begin
                let local = if owner = Attribute.Primitive then 0
                  else if barycentric_a.(point) >= barycentric_b.(point)
                       && barycentric_a.(point) >= barycentric_c.(point) then 0
                  else if barycentric_b.(point) >= barycentric_c.(point) then 1
                  else 2 in
                output.(point) <- source_values.(source_element owner primitive
                  triangles.(point) local)
              end) in
      let make_attribute index =
        let specification = specifications.(index)
        and source_attribute = Option.get source_attributes.(index) in
        let existing = Geometry.find_attribute ~owner:target_owner
            specification.target_name target in
        let owner = specification.source_owner in
        let storage = match Attribute.Private.storage source_attribute with
          | Attribute.Float values ->
              let output = initial_float ?selection:target_selection
                  unmatched existing target_count in
              transfer_numeric owner values output; Attribute.Float output
          | Attribute.Int values ->
              let output = initial_int ?selection:target_selection
                  unmatched existing target_count in
              transfer_discrete owner values output; Attribute.Int output
          | Attribute.Text values ->
              let output = initial_text ?selection:target_selection
                  unmatched existing target_count in
              transfer_discrete owner values output; Attribute.Text output
          | Attribute.Float2 values ->
              let values = Packed.Float2.Private.view values in
              let x, y = initial_float2 ?selection:target_selection
                  unmatched existing target_count in
              transfer_numeric owner values.x x; transfer_numeric owner values.y y;
              Attribute.Float2 (Packed.Float2.of_owned ~x ~y |> Result.get_ok)
          | Attribute.Float3 values ->
              let values = Packed.Float3.Private.view values in
              let x, y, z = initial_float3 ?selection:target_selection
                  unmatched existing target_count in
              transfer_numeric owner values.x x; transfer_numeric owner values.y y;
              transfer_numeric owner values.z z;
              if String.equal specification.source_name "N" && target_count > 0 then
                Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(target_count - 1)
                  (fun point -> if primitives.(point) >= 0
                      && (match influence with None -> true
                          | Some values -> values.(point) > 0.) then begin
                    let length = sqrt ((x.(point) *. x.(point))
                      +. (y.(point) *. y.(point)) +. (z.(point) *. z.(point))) in
                    if length > 1e-20 then begin x.(point) <- x.(point) /. length;
                      y.(point) <- y.(point) /. length; z.(point) <- z.(point) /. length end
                  end);
              Attribute.Float3 (Packed.Float3.Private.of_owned_exn ~x ~y ~z)
          | Attribute.Float4 values ->
              let values = Packed.Float4.Private.view values in
              let x, y, z, w = initial_float4 ?selection:target_selection
                  unmatched existing target_count in
              transfer_numeric owner values.x x; transfer_numeric owner values.y y;
              transfer_numeric owner values.z z; transfer_numeric owner values.w w;
              Attribute.Float4 (Packed.Float4.of_owned ~x ~y ~z ~w
                |> Result.get_ok)
          | Attribute.Int_array _ | Attribute.Float_array _ -> assert false in
        Attribute.create_owned ~name:specification.target_name
          ~owner:target_owner storage in
      let attribute_count = Array.length specifications
          + if distance_name = None then 0 else 1 in
      Result.bind (make_attribute_array attribute_count (fun index ->
        if index < Array.length specifications then make_attribute index
        else
          let name = Option.get distance_name in
          let existing = Geometry.find_attribute ~owner:target_owner name target in
          let values = initial_float ?selection:target_selection
              unmatched existing target_count in
          if target_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
              ~finish:(target_count - 1) (fun point ->
                if primitives.(point) >= 0 then
                  values.(point) <- sqrt distances_squared.(point));
          Attribute.create_owned ~name ~owner:target_owner
            (Attribute.Float values)))
        (install_attributes_batch target))

let transfer_surface ?cancel ?grain ?max_distance ?blend_width ?falloff ?unmatched
    ?target_owner ?distance_attribute ?source_primitives ?source_vertices
    ?source_vertex_selection ?target_points
    ?target_elements
    ~attributes ~source ~target () =
  try Result.map_error
      (Error.of_string ~operation:"attribute_transfer_surface"
        ~code:"invalid_transfer")
      (transfer_surface_raw ?cancel ?grain ?max_distance ?blend_width ?falloff
         ?unmatched ?target_owner ?distance_attribute ?source_primitives
         ?source_vertices ?source_vertex_selection
         ?target_points ?target_elements ~attributes ~source ~target ())
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_transfer_surface"
      ~code:"cancelled" "surface attribute transfer was cancelled")
  | Invalid_argument message -> Error (Error.make
      ~operation:"attribute_transfer_surface" ~code:"invalid_position" message)

let transfer_vertices_raw ?cancel ?grain ?names ?pattern ?max_distance
    ?blend_width ?falloff ?unmatched ?source_primitives ?source_vertices
    ?source_vertex_selection ?target_vertices
    ~source ~target () =
  Result.bind (selected_attributes
      ~operation:"Pdk.Attribute_ops.transfer_vertices"
      ~owner:Attribute.Vertex ~names ~pattern source) (fun attributes ->
    let attributes = Array.to_list attributes |> List.map (fun attribute ->
      surface_attribute ~owner:Attribute.Vertex (Attribute.name attribute)) in
    transfer_surface_raw ?cancel ?grain ?max_distance ?blend_width ?falloff
      ?unmatched ~target_owner:Attribute.Vertex ?source_primitives
      ?source_vertices ?source_vertex_selection
      ?target_elements:target_vertices ~attributes ~source ~target ())

let transfer_vertices ?cancel ?grain ?names ?pattern ?max_distance ?blend_width
    ?falloff ?unmatched ?source_primitives ?source_vertices
    ?source_vertex_selection ?target_vertices ~source ~target () =
  try Result.map_error
      (Error.of_string ~operation:"attribute_transfer" ~code:"invalid_transfer")
      (transfer_vertices_raw ?cancel ?grain ?names ?pattern ?max_distance
         ?blend_width ?falloff ?unmatched ?source_primitives ?source_vertices
         ?source_vertex_selection ?target_vertices
         ~source ~target ())
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_transfer"
      ~code:"cancelled" "attribute transfer was cancelled")
  | Invalid_argument message -> Error (Error.make ~operation:"attribute_transfer"
      ~code:"invalid_position" message)

let transfer_all_raw ?cancel ?grain ?point_pattern ?vertex_pattern
    ?primitive_pattern ?detail_pattern ?mode ?max_distance ?blend_width ?falloff
    ?unmatched ~source ~target () =
  let apply pattern transfer geometry = match pattern with
    | None -> Ok geometry
    | Some pattern -> transfer ~pattern geometry in
  Result.bind
    (apply point_pattern (fun ~pattern target ->
       transfer_points_raw ?cancel ?grain ~pattern ?mode ?max_distance
         ?blend_width ?falloff ?unmatched ~source ~target ()) target)
    (fun target -> Result.bind
      (apply primitive_pattern (fun ~pattern target ->
         transfer_primitives_raw ?cancel ?grain ~pattern ?mode ?max_distance
           ?blend_width ?falloff ?unmatched ~source ~target ()) target)
      (fun target -> Result.bind
        (apply vertex_pattern (fun ~pattern target ->
           transfer_vertices_raw ?cancel ?grain ~pattern ?max_distance
             ?blend_width ?falloff ?unmatched ~source ~target ()) target)
        (fun target -> apply detail_pattern (fun ~pattern target ->
           transfer_detail_raw ~pattern ~source ~target ()) target)))

let transfer_all ?cancel ?grain ?point_pattern ?vertex_pattern
    ?primitive_pattern ?detail_pattern ?mode ?max_distance ?blend_width ?falloff
    ?unmatched ~source ~target () =
  try Result.map_error
      (Error.of_string ~operation:"attribute_transfer_all"
        ~code:"invalid_transfer")
      (transfer_all_raw ?cancel ?grain ?point_pattern ?vertex_pattern
         ?primitive_pattern ?detail_pattern ?mode ?max_distance ?blend_width
         ?falloff ?unmatched ~source ~target ())
  with
  | Cancel.Cancelled -> Error (Error.make ~operation:"attribute_transfer_all"
      ~code:"cancelled" "multi-owner attribute transfer was cancelled")
  | Invalid_argument message -> Error (Error.make
      ~operation:"attribute_transfer_all" ~code:"invalid_position" message)
