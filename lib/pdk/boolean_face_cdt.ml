type t = {
  points : Implicit_point.t array;
  global_point_tokens : int array;
  source_winding : int;
  triangle_a : int array;
  triangle_b : int array;
  triangle_c : int array;
  constraint_first : int array;
  constraint_second : int array;
}

type point_location = Walk | Exact_scan
type constraint_recovery = Trace | Edge_scan
type workspace = Planar_cdt.Private.workspace

let create_workspace () =
  Planar_cdt.Private.create_workspace ~point_capacity:16
    ~triangle_capacity:16 ()

let operation = "boolean_face_cdt"
let error code message = Error (Error.make ~operation ~code message)

let point_count value = Array.length value.points
let approximate_point value point = Implicit_point.approximate value.points.(point)
let triangle_count value = Array.length value.triangle_a
let triangle_point value triangle local = match local with
  | 0 -> value.triangle_a.(triangle)
  | 1 -> value.triangle_b.(triangle)
  | 2 -> value.triangle_c.(triangle)
  | _ -> invalid_arg "Boolean face CDT local corner must be 0, 1, or 2"
let constraint_count value = Array.length value.constraint_first
let constraint_first value constraint_index = value.constraint_first.(constraint_index)
let constraint_second value constraint_index = value.constraint_second.(constraint_index)

module Private = struct
  let point value point = value.points.(point)
  let global_point_token value point = value.global_point_tokens.(point)
  let source_winding value = value.source_winding
end

let face_triangle_point constraints side triangle local = match side with
  | Boolean_face_arrangement.Left ->
      Boolean_constraints.Private.left_triangle_point constraints triangle local
  | Boolean_face_arrangement.Right ->
      Boolean_constraints.Private.right_triangle_point constraints triangle local

let face_triangle_implicit constraints side triangle local =
  Boolean_constraints.Private.source_point constraints
    (face_triangle_point constraints side triangle local)

let projection points =
  match Implicit_point.orient2d_xy points.(0) points.(1) points.(2) with
  | Predicates.Positive | Predicates.Negative -> 0
  | Predicates.Zero ->
      (match Implicit_point.orient2d_yz points.(0) points.(1) points.(2) with
       | Predicates.Positive | Predicates.Negative -> 1
       | Predicates.Zero -> 2)

let orient projection = match projection with
  | 0 -> Implicit_point.orient2d_xy
  | 1 -> Implicit_point.orient2d_yz
  | _ -> Implicit_point.orient2d_zx

let incircle projection = match projection with
  | 0 -> Implicit_point.incircle_xy
  | 1 -> Implicit_point.incircle_yz
  | _ -> Implicit_point.incircle_zx

module Orientation_cache = struct
  type table = {
    stride : int;
    mutable keys : int array;
    mutable signs : bytes;
    mutable count : int;
  }
  type t = Disabled | Table of table

  let create point_count =
    if point_count <= 0 || point_count > max_int / point_count
        || point_count * point_count > max_int / point_count then Disabled
    else begin
      let needed = if point_count > Sys.max_array_length / 8 then
          Sys.max_array_length else max 16 (point_count * 8) in
      let capacity = ref 16 in
      while !capacity < needed do
        if !capacity > Sys.max_array_length / 2 then capacity := needed
        else capacity := !capacity * 2
      done;
      Table { stride = point_count; keys = Array.make !capacity (-1);
        signs = Bytes.make !capacity '\000'; count = 0 }
    end

  let[@inline] key stride a b c = (((a * stride) + b) * stride) + c
  let[@inline] hash key = ((key lxor (key lsr 16)) * 0x45d9f3b) land max_int

  let find_slot keys key =
    let mask = Array.length keys - 1 in
    let slot = ref (hash key land mask) in
    while keys.(!slot) >= 0 && keys.(!slot) <> key do
      slot := (!slot + 1) land mask
    done;
    !slot

  let grow cache =
    let previous_keys = cache.keys and previous_signs = cache.signs in
    if Array.length previous_keys > Sys.max_array_length / 2 then
      invalid_arg "Boolean face CDT orientation cache exceeds array limits";
    cache.keys <- Array.make (Array.length previous_keys * 2) (-1);
    cache.signs <- Bytes.make (Array.length cache.keys) '\000';
    for slot = 0 to Array.length previous_keys - 1 do
      let key = previous_keys.(slot) in
      if key >= 0 then begin
        let target = find_slot cache.keys key in
        cache.keys.(target) <- key;
        Bytes.unsafe_set cache.signs target (Bytes.unsafe_get previous_signs slot)
      end
    done

  let encode = function
    | Predicates.Negative -> '\000'
    | Predicates.Zero -> '\001'
    | Predicates.Positive -> '\002'

  let decode value = match value with
    | '\000' -> Predicates.Negative
    | '\001' -> Predicates.Zero
    | _ -> Predicates.Positive

  let reverse = function
    | Predicates.Negative -> Predicates.Positive
    | Predicates.Positive -> Predicates.Negative
    | Predicates.Zero -> Predicates.Zero

  let get cache exact a b c = match cache with
    | Disabled -> exact a b c
    | Table cache ->
    if a = b || b = c || c = a then Predicates.Zero
    else begin
      let inversions = (if a > b then 1 else 0) + (if a > c then 1 else 0)
          + (if b > c then 1 else 0) in
      let a, b, c =
        if a <= b then
          if b <= c then a, b, c
          else if a <= c then a, c, b else c, a, b
        else if a <= c then b, a, c
        else if b <= c then b, c, a else c, b, a in
      if cache.count * 3 >= Array.length cache.keys * 2 then grow cache;
      let key = key cache.stride a b c in
      let slot = find_slot cache.keys key in
      let sign = if cache.keys.(slot) = key then
          decode (Bytes.unsafe_get cache.signs slot)
        else begin
          let sign = exact a b c in
          cache.keys.(slot) <- key;
          Bytes.unsafe_set cache.signs slot (encode sign);
          cache.count <- cache.count + 1;
          sign
        end in
      if inversions land 1 = 0 then sign else reverse sign
    end
end

let opposite_sign left right = match left, right with
  | Predicates.Negative, Predicates.Positive
  | Predicates.Positive, Predicates.Negative -> true
  | _ -> false

let edge_key point_count first second =
  let first, second = if first < second then first, second else second, first in
  if first > (max_int - second) / point_count then
    invalid_arg "Boolean face CDT edge key exceeds integer range";
  (first * point_count) + second

let squared_limit count =
  if count <= 0 then 0
  else if count > max_int / count then max_int else count * count

module Edge_table = struct
  let empty = -1
  let tombstone = -2

  type t = {
    mutable keys : int array;
    mutable first_triangles : int array;
    mutable first_opposites : int array;
    mutable second_triangles : int array;
    mutable second_opposites : int array;
    mutable edge_count : int;
    mutable tombstone_count : int;
  }

  let capacity_for expected =
    if expected < 0 || expected > Sys.max_array_length / 2 then
      invalid_arg "Boolean face CDT edge cardinality exceeds array limits";
    let needed = max 16 (expected * 2) in
    let capacity = ref 16 in
    while !capacity < needed do
      if !capacity > Sys.max_array_length / 2 then
        invalid_arg "Boolean face CDT edge table exceeds array limits";
      capacity := !capacity * 2
    done;
    !capacity

  let create expected =
    let capacity = capacity_for expected in
    { keys = Array.make capacity empty;
      first_triangles = Array.make capacity (-1);
      first_opposites = Array.make capacity (-1);
      second_triangles = Array.make capacity (-1);
      second_opposites = Array.make capacity (-1);
      edge_count = 0; tombstone_count = 0 }

  let[@inline] hash key =
    let value = key lxor (key lsr 16) in
    (value * 0x45d9f3b) land max_int

  let find_slot table key =
    let mask = Array.length table.keys - 1 in
    let slot = ref (hash key land mask) and first_tombstone = ref (-1)
    and found = ref (-1) and searching = ref true in
    while !searching do
      let present = table.keys.(!slot) in
      if present = key then begin found := !slot; searching := false end
      else if present = empty then begin
        found := if !first_tombstone >= 0 then !first_tombstone else !slot;
        searching := false
      end else begin
        if present = tombstone && !first_tombstone < 0 then
          first_tombstone := !slot;
        slot := (!slot + 1) land mask
      end
    done;
    !found

  let find table key =
    let slot = find_slot table key in
    if table.keys.(slot) = key then slot else -1

  let add_raw table key triangle opposite =
    let slot = find_slot table key in
    if table.keys.(slot) <> key then begin
      if table.keys.(slot) = tombstone then
        table.tombstone_count <- table.tombstone_count - 1;
      table.keys.(slot) <- key;
      table.first_triangles.(slot) <- triangle;
      table.first_opposites.(slot) <- opposite;
      table.second_triangles.(slot) <- -1;
      table.second_opposites.(slot) <- -1;
      table.edge_count <- table.edge_count + 1
    end else begin
      let first = table.first_triangles.(slot)
      and second = table.second_triangles.(slot) in
      if triangle = first || triangle = second then
        invalid_arg "Boolean face CDT duplicated one triangle edge incidence"
      else if second >= 0 then
        invalid_arg "Boolean face CDT produced a non-manifold planar edge"
      else if triangle < first then begin
        table.second_triangles.(slot) <- first;
        table.second_opposites.(slot) <- table.first_opposites.(slot);
        table.first_triangles.(slot) <- triangle;
        table.first_opposites.(slot) <- opposite
      end else begin
        table.second_triangles.(slot) <- triangle;
        table.second_opposites.(slot) <- opposite
      end
    end

  let rehash table capacity =
    let previous_keys = table.keys
    and previous_first_triangles = table.first_triangles
    and previous_first_opposites = table.first_opposites
    and previous_second_triangles = table.second_triangles
    and previous_second_opposites = table.second_opposites in
    table.keys <- Array.make capacity empty;
    table.first_triangles <- Array.make capacity (-1);
    table.first_opposites <- Array.make capacity (-1);
    table.second_triangles <- Array.make capacity (-1);
    table.second_opposites <- Array.make capacity (-1);
    table.edge_count <- 0;
    table.tombstone_count <- 0;
    for slot = 0 to Array.length previous_keys - 1 do
      if previous_keys.(slot) >= 0 then begin
        add_raw table previous_keys.(slot) previous_first_triangles.(slot)
          previous_first_opposites.(slot);
        if previous_second_triangles.(slot) >= 0 then
          add_raw table previous_keys.(slot) previous_second_triangles.(slot)
            previous_second_opposites.(slot)
      end
    done

  let prepare_insert table =
    let capacity = Array.length table.keys in
    let used = table.edge_count + table.tombstone_count + 1 in
    if used >= capacity - (capacity / 3) then begin
      if capacity > Sys.max_array_length / 2 then
        invalid_arg "Boolean face CDT edge table exceeds array limits";
      rehash table (capacity * 2)
    end
    else if table.tombstone_count > table.edge_count
        && table.tombstone_count > 64 then
      rehash table capacity

  let add table key triangle opposite =
    prepare_insert table;
    add_raw table key triangle opposite

  let remove table key triangle =
    let slot = find table key in
    if slot < 0 then invalid_arg "Boolean face CDT lost an indexed edge"
    else if table.first_triangles.(slot) = triangle then begin
      if table.second_triangles.(slot) >= 0 then begin
        table.first_triangles.(slot) <- table.second_triangles.(slot);
        table.first_opposites.(slot) <- table.second_opposites.(slot);
        table.second_triangles.(slot) <- -1;
        table.second_opposites.(slot) <- -1
      end else begin
        table.keys.(slot) <- tombstone;
        table.first_triangles.(slot) <- -1;
        table.first_opposites.(slot) <- -1;
        table.edge_count <- table.edge_count - 1;
        table.tombstone_count <- table.tombstone_count + 1
      end
    end else if table.second_triangles.(slot) = triangle then begin
      table.second_triangles.(slot) <- -1;
      table.second_opposites.(slot) <- -1
    end else invalid_arg "Boolean face CDT lost one edge incidence"
end

module Ordered_keys = struct
  type t = { mutable values : int array; mutable count : int }

  let of_edge_table table =
    let values = Array.make table.Edge_table.edge_count 0
    and count = ref 0 in
    for slot = 0 to Array.length table.Edge_table.keys - 1 do
      if table.Edge_table.keys.(slot) >= 0 then begin
        values.(!count) <- table.Edge_table.keys.(slot);
        incr count
      end
    done;
    Array.sort Int.compare values;
    { values; count = !count }

  let lower_bound value key =
    let first = ref 0 and last = ref value.count in
    while !first < !last do
      let middle = !first + ((!last - !first) / 2) in
      if value.values.(middle) < key then first := middle + 1 else last := middle
    done;
    !first

  let add value key =
    let insertion = lower_bound value key in
    if insertion = value.count || value.values.(insertion) <> key then begin
      if value.count = Array.length value.values then begin
        let capacity = min Sys.max_array_length
            (max (value.count + 1) (value.count * 2)) in
        if capacity <= value.count then
          invalid_arg "Boolean face CDT ordered edge keys exceed array limits";
        let values = Array.make capacity 0 in
        Array.blit value.values 0 values 0 insertion;
        Array.blit value.values insertion values (insertion + 1)
          (value.count - insertion);
        value.values <- values
      end else
        Array.blit value.values insertion value.values (insertion + 1)
          (value.count - insertion);
      value.values.(insertion) <- key;
      value.count <- value.count + 1
    end

  let compact value table =
    if value.count > (table.Edge_table.edge_count * 2) + 64 then begin
      let output = Array.make table.Edge_table.edge_count 0
      and count = ref 0 in
      for index = 0 to value.count - 1 do
        let key = value.values.(index) in
        if Edge_table.find table key >= 0 then begin
          output.(!count) <- key;
          incr count
        end
      done;
      value.values <- output;
      value.count <- !count
    end
end

module Key_heap = struct
  type t = { mutable values : int array; mutable count : int }

  let create capacity = { values = Array.make (max 16 capacity) 0; count = 0 }

  let push heap key =
    if heap.count = Array.length heap.values then begin
      let capacity = min Sys.max_array_length (heap.count * 2) in
      if capacity <= heap.count then
        invalid_arg "Boolean face CDT edge queue exceeds array limits";
      let values = Array.make capacity 0 in
      Array.blit heap.values 0 values 0 heap.count;
      heap.values <- values
    end;
    let slot = ref heap.count in
    heap.count <- heap.count + 1;
    let moving = ref true in
    while !moving && !slot > 0 do
      let parent = (!slot - 1) / 2 in
      if heap.values.(parent) <= key then moving := false
      else begin heap.values.(!slot) <- heap.values.(parent); slot := parent end
    done;
    heap.values.(!slot) <- key

  let pop heap =
    if heap.count = 0 then None else begin
      let result = heap.values.(0) in
      heap.count <- heap.count - 1;
      if heap.count > 0 then begin
        let last = heap.values.(heap.count) and slot = ref 0
        and moving = ref true in
        while !moving do
          let left = (!slot * 2) + 1 in
          if left >= heap.count then moving := false else begin
            let right = left + 1 in
            let child = if right < heap.count
                && heap.values.(right) < heap.values.(left) then right else left in
            if heap.values.(child) >= last then moving := false
            else begin heap.values.(!slot) <- heap.values.(child); slot := child end
          end
        done;
        heap.values.(!slot) <- last
      end;
      Some result
    end
end

let global_point_tokens constraints arrangement arrangement_to_point
    ~side ~triangle ~point_count =
  let tokens = Array.make point_count (-1) in
  for local = 0 to 2 do
    tokens.(local) <- face_triangle_point constraints side triangle local
  done;
  let source_count = Boolean_constraints.Private.source_point_count constraints in
  for arrangement_point = 0 to Array.length arrangement_to_point - 1 do
    let handle = Boolean_face_arrangement.Private.point_handle
        arrangement arrangement_point in
    if handle >= 0 then begin
      let point = arrangement_to_point.(arrangement_point) in
      if tokens.(point) < 0 then tokens.(point) <- source_count + handle
    end
  done;
  tokens

let[@warning "-32"] build_legacy ?cancel ?(point_location = Walk)
    ?(constraint_recovery = Trace)
    constraints arrangement ~side ~triangle =
  try
    Cancel.check_opt cancel;
    let arrangement_count = Boolean_face_arrangement.point_count arrangement in
    let point_capacity = 3 + arrangement_count in
    let fallback = face_triangle_implicit constraints side triangle 0 in
    let points = Array.make point_capacity fallback in
    for local = 0 to 2 do
      points.(local) <- face_triangle_implicit constraints side triangle local
    done;
    let arrangement_to_point = Array.make arrangement_count 0
    and actual_point_count = ref 3 in
    for arrangement_point = 0 to arrangement_count - 1 do
      let point = Boolean_face_arrangement.Private.point arrangement arrangement_point in
      let found = ref (-1) and candidate = ref 0 in
      (* Arrangement points are already globally exact-unique. Only the three
         source-triangle corners can alias them at this adapter boundary. *)
      while !found < 0 && !candidate < 3 do
        if Implicit_point.equal points.(!candidate) point then found := !candidate;
        incr candidate
      done;
      if !found >= 0 then arrangement_to_point.(arrangement_point) <- !found
      else begin
        points.(!actual_point_count) <- point;
        arrangement_to_point.(arrangement_point) <- !actual_point_count;
        incr actual_point_count
      end
    done;
    let points = Array.sub points 0 !actual_point_count in
    let projection_axis = projection points in
    let orient = orient projection_axis and incircle = incircle projection_axis in
    let point_u_min = Array.make (Array.length points) 0.
    and point_u_max = Array.make (Array.length points) 0.
    and point_v_min = Array.make (Array.length points) 0.
    and point_v_max = Array.make (Array.length points) 0. in
    for point = 0 to Array.length points - 1 do
      let (x_min,x_max),(y_min,y_max),(z_min,z_max) =
        Implicit_point.bounds points.(point) in
      let u_min,u_max,v_min,v_max = match projection_axis with
        | 0 -> x_min,x_max,y_min,y_max
        | 1 -> y_min,y_max,z_min,z_max
        | _ -> z_min,z_max,x_min,x_max in
      point_u_min.(point) <- u_min; point_u_max.(point) <- u_max;
      point_v_min.(point) <- v_min; point_v_max.(point) <- v_max
    done;
    let segment_bounds_overlap first second edge_a edge_b =
      let first_u_min = min point_u_min.(first) point_u_min.(second)
      and first_u_max = max point_u_max.(first) point_u_max.(second)
      and first_v_min = min point_v_min.(first) point_v_min.(second)
      and first_v_max = max point_v_max.(first) point_v_max.(second)
      and second_u_min = min point_u_min.(edge_a) point_u_min.(edge_b)
      and second_u_max = max point_u_max.(edge_a) point_u_max.(edge_b)
      and second_v_min = min point_v_min.(edge_a) point_v_min.(edge_b)
      and second_v_max = max point_v_max.(edge_a) point_v_max.(edge_b) in
      first_u_max >= second_u_min && second_u_max >= first_u_min
      && first_v_max >= second_v_min && second_v_max >= first_v_min in
    let source_winding = match orient points.(0) points.(1) points.(2) with
      | Predicates.Positive -> 1
      | Predicates.Negative -> -1
      | Predicates.Zero -> invalid_arg "degenerate source triangle during face CDT" in
    let capacity = max 4 ((2 * Array.length points) + 8) in
    let triangle_a = Array.make capacity 0 and triangle_b = Array.make capacity 0
    and triangle_c = Array.make capacity 0 and triangle_count = ref 0 in
    let set_triangle index a b c =
      match orient points.(a) points.(b) points.(c) with
      | Predicates.Positive ->
          triangle_a.(index) <- a; triangle_b.(index) <- b; triangle_c.(index) <- c
      | Predicates.Negative ->
          triangle_a.(index) <- a; triangle_b.(index) <- c; triangle_c.(index) <- b
      | Predicates.Zero -> invalid_arg "degenerate triangle during face CDT" in
    let append_triangle a b c =
      if !triangle_count >= capacity then
        invalid_arg "Boolean face CDT exceeded planar cardinality bound";
      let triangle = !triangle_count in
      set_triangle triangle a b c;
      incr triangle_count;
      triangle in
    ignore (append_triangle 0 1 2);
    let triangle_contains triangle point =
      let a = triangle_a.(triangle) and b = triangle_b.(triangle)
      and c = triangle_c.(triangle) in
      let ab = orient points.(a) points.(b) points.(point)
      and bc = orient points.(b) points.(c) points.(point)
      and ca = orient points.(c) points.(a) points.(point) in
      let inside sign = sign <> Predicates.Negative in
      if inside ab && inside bc && inside ca then
        Some (if ab = Predicates.Zero then (a,b,c)
              else if bc = Predicates.Zero then (b,c,a)
              else if ca = Predicates.Zero then (c,a,b)
              else (-1,-1,-1))
      else None in
    let point_count = Array.length points in
    let edge_table = Edge_table.create (capacity * 3) in
    let add_triangle_edges triangle =
      let a = triangle_a.(triangle) and b = triangle_b.(triangle)
      and c = triangle_c.(triangle) in
      Edge_table.add edge_table (edge_key point_count a b) triangle c;
      Edge_table.add edge_table (edge_key point_count b c) triangle a;
      Edge_table.add edge_table (edge_key point_count c a) triangle b in
    let remove_triangle_edges triangle =
      let a = triangle_a.(triangle) and b = triangle_b.(triangle)
      and c = triangle_c.(triangle) in
      Edge_table.remove edge_table (edge_key point_count a b) triangle;
      Edge_table.remove edge_table (edge_key point_count b c) triangle;
      Edge_table.remove edge_table (edge_key point_count c a) triangle in
    add_triangle_edges 0;
    let exact_scan point =
      let containing = ref (-1) and edge_u = ref (-1)
      and edge_v = ref (-1) and opposite = ref (-1)
      and candidate = ref 0 in
      while !containing < 0 && !candidate < !triangle_count do
        match triangle_contains !candidate point with
        | None -> incr candidate
        | Some (u,v,w) ->
            containing := !candidate; edge_u := u; edge_v := v; opposite := w
      done;
      !containing,!edge_u,!edge_v,!opposite in
    let walk_start = ref 0 in
    let walk point =
      let current = ref (min !walk_start (!triangle_count - 1))
      and steps = ref 0 and result = ref None in
      while Option.is_none !result && !steps <= !triangle_count do
        match triangle_contains !current point with
        | Some (u,v,w) ->
            let containing = if u < 0 then !current else begin
              let slot = Edge_table.find edge_table (edge_key point_count u v) in
              if slot < 0 then !current else
                let first = edge_table.Edge_table.first_triangles.(slot)
                and second = edge_table.Edge_table.second_triangles.(slot) in
                if second < 0 then !current else min first second
            end in
            if containing = !current then result := Some (containing,u,v,w)
            else result := Option.map (fun (u,v,w) -> containing,u,v,w)
                (triangle_contains containing point)
        | None ->
            let a = triangle_a.(!current) and b = triangle_b.(!current)
            and c = triangle_c.(!current) in
            let ab = orient points.(a) points.(b) points.(point)
            and bc = orient points.(b) points.(c) points.(point) in
            let u,v = if ab = Predicates.Negative then a,b
              else if bc = Predicates.Negative then b,c else c,a in
            let slot = Edge_table.find edge_table (edge_key point_count u v) in
            if slot < 0 then steps := !triangle_count + 1 else begin
              let first = edge_table.Edge_table.first_triangles.(slot)
              and second = edge_table.Edge_table.second_triangles.(slot) in
              let adjacent = if first = !current then second else first in
              if adjacent < 0 || adjacent = !current then
                steps := !triangle_count + 1
              else current := adjacent
            end;
            incr steps
      done;
      match !result with Some value -> value | None -> exact_scan point in
    for point = 3 to Array.length points - 1 do
      if point land 255 = 0 then Cancel.check_opt cancel;
      let containing,edge_u,edge_v,opposite = match point_location with
        | Exact_scan -> exact_scan point
        | Walk -> walk point in
      if containing < 0 then
        invalid_arg "constraint point lies outside its source triangle";
      walk_start := containing;
      if edge_u < 0 then begin
        let a = triangle_a.(containing) and b = triangle_b.(containing)
        and c = triangle_c.(containing) in
        remove_triangle_edges containing;
        set_triangle containing a b point;
        let second = append_triangle b c point
        and third = append_triangle c a point in
        add_triangle_edges containing;
        add_triangle_edges second;
        add_triangle_edges third
      end else begin
        let slot = Edge_table.find edge_table (edge_key point_count edge_u edge_v) in
        if slot < 0 then invalid_arg "Boolean face CDT lost a split edge";
        let first = edge_table.Edge_table.first_triangles.(slot)
        and second = edge_table.Edge_table.second_triangles.(slot) in
        let adjacent = if first = containing then second else first in
        let adjacent_opposite = if adjacent < 0 then -1
          else if first = adjacent then edge_table.Edge_table.first_opposites.(slot)
          else edge_table.Edge_table.second_opposites.(slot) in
        remove_triangle_edges containing;
        if adjacent >= 0 then remove_triangle_edges adjacent;
        set_triangle containing edge_u point opposite;
        let containing_second = append_triangle point edge_v opposite in
        add_triangle_edges containing;
        add_triangle_edges containing_second;
        if adjacent >= 0 then begin
          set_triangle adjacent edge_v point adjacent_opposite;
          let adjacent_second = append_triangle point edge_u adjacent_opposite in
          add_triangle_edges adjacent;
          add_triangle_edges adjacent_second
        end
      end
    done;
    let constraint_count = Boolean_face_arrangement.segment_count arrangement in
    let constraint_first = Array.make constraint_count 0
    and constraint_second = Array.make constraint_count 0 in
    for constraint_index = 0 to constraint_count - 1 do
      constraint_first.(constraint_index) <- arrangement_to_point.(
          Boolean_face_arrangement.segment_first arrangement constraint_index);
      constraint_second.(constraint_index) <- arrangement_to_point.(
          Boolean_face_arrangement.segment_second arrangement constraint_index)
    done;
    let constrained = Hashtbl.create (max 4 (constraint_count * 2)) in
    let ordered_keys = match constraint_recovery with
      | Edge_scan -> Some (Ordered_keys.of_edge_table edge_table)
      | Trace -> None in
    let point_triangle = Array.make point_count (-1) in
    let seed_triangle triangle =
      point_triangle.(triangle_a.(triangle)) <- triangle;
      point_triangle.(triangle_b.(triangle)) <- triangle;
      point_triangle.(triangle_c.(triangle)) <- triangle in
    for triangle = 0 to !triangle_count - 1 do seed_triangle triangle done;
    let flip_diagonal left_triangle right_triangle left_opposite right_opposite
        edge_a edge_b =
      Option.iter (fun keys -> Ordered_keys.add keys
          (edge_key point_count left_opposite right_opposite)) ordered_keys;
      remove_triangle_edges left_triangle;
      remove_triangle_edges right_triangle;
      set_triangle left_triangle left_opposite right_opposite edge_a;
      set_triangle right_triangle right_opposite left_opposite edge_b;
      add_triangle_edges left_triangle;
      add_triangle_edges right_triangle;
      seed_triangle left_triangle;
      seed_triangle right_triangle in
    let edge_exists key = Edge_table.find edge_table key >= 0 in
    let properly_crosses constraint_a constraint_b edge_a edge_b =
      edge_a <> constraint_a && edge_a <> constraint_b
      && edge_b <> constraint_a && edge_b <> constraint_b
      && segment_bounds_overlap constraint_a constraint_b edge_a edge_b
      && let o1 = orient points.(constraint_a) points.(constraint_b) points.(edge_a)
         and o2 = orient points.(constraint_a) points.(constraint_b) points.(edge_b)
         and o3 = orient points.(edge_a) points.(edge_b) points.(constraint_a)
         and o4 = orient points.(edge_a) points.(edge_b) points.(constraint_b) in
         opposite_sign o1 o2 && opposite_sign o3 o4 in
    let flip_crossing_scan constraint_a constraint_b =
      let best_key = ref max_int and best_left_triangle = ref (-1)
      and best_right_triangle = ref (-1) and best_left_opposite = ref (-1)
      and best_right_opposite = ref (-1) and best_edge_a = ref (-1)
      and best_edge_b = ref (-1) in
      let scan_keys = match ordered_keys with
        | Some keys -> Ordered_keys.compact keys edge_table; keys
        | None -> Ordered_keys.of_edge_table edge_table in
      let ordered_slot = ref 0 in
      while !best_left_triangle < 0 && !ordered_slot < scan_keys.Ordered_keys.count do
        let key = scan_keys.Ordered_keys.values.(!ordered_slot) in
        let slot = Edge_table.find edge_table key in
        if slot >= 0 && edge_table.Edge_table.second_triangles.(slot) >= 0
            && not (Hashtbl.mem constrained key) then begin
          let left_triangle = edge_table.Edge_table.first_triangles.(slot)
          and right_triangle = edge_table.Edge_table.second_triangles.(slot)
          and left_opposite = edge_table.Edge_table.first_opposites.(slot)
          and right_opposite = edge_table.Edge_table.second_opposites.(slot)
          and edge_a = key / point_count and edge_b = key mod point_count in
          if properly_crosses constraint_a constraint_b edge_a edge_b then begin
            let convex_a = orient points.(left_opposite) points.(right_opposite)
                points.(edge_a)
            and convex_b = orient points.(left_opposite) points.(right_opposite)
                points.(edge_b) in
            if opposite_sign convex_a convex_b then begin
              best_key := key;
              best_left_triangle := left_triangle;
              best_right_triangle := right_triangle;
              best_left_opposite := left_opposite;
              best_right_opposite := right_opposite;
              best_edge_a := edge_a;
              best_edge_b := edge_b
            end
          end
        end;
        incr ordered_slot
      done;
      if !best_left_triangle < 0 then false else begin
        flip_diagonal !best_left_triangle !best_right_triangle
          !best_left_opposite !best_right_opposite !best_edge_a !best_edge_b;
        true
      end in
    let triangle_has_point triangle point =
      triangle_a.(triangle) = point || triangle_b.(triangle) = point
      || triangle_c.(triangle) = point in
    let crossing_key constraint_a constraint_b triangle entry_key =
      let a = triangle_a.(triangle) and b = triangle_b.(triangle)
      and c = triangle_c.(triangle) and found = ref (-1) in
      let consider first second =
        let key = edge_key point_count first second in
        if key <> entry_key && properly_crosses constraint_a constraint_b first second
            && (!found < 0 || key < !found) then found := key in
      consider a b; consider b c; consider c a;
      !found in
    let adjacent_across triangle first second =
      let slot = Edge_table.find edge_table (edge_key point_count first second) in
      if slot < 0 then -1 else
        let left = edge_table.Edge_table.first_triangles.(slot)
        and right = edge_table.Edge_table.second_triangles.(slot) in
        if left = triangle then right else if right = triangle then left else -1 in
    let other_vertex triangle first second =
      let a = triangle_a.(triangle) and b = triangle_b.(triangle)
      and c = triangle_c.(triangle) in
      if a <> first && a <> second then a
      else if b <> first && b <> second then b else c in
    let find_incident_start constraint_a constraint_b =
      let seed = point_triangle.(constraint_a) in
      if seed < 0 || not (triangle_has_point seed constraint_a) then -1
      else if crossing_key constraint_a constraint_b seed (-1) >= 0 then seed
      else begin
        let a = triangle_a.(seed) and b = triangle_b.(seed)
        and c = triangle_c.(seed) in
        let first_other,second_other = if a = constraint_a then b,c
          else if b = constraint_a then c,a else a,b in
        let search entry_vertex =
          let current = ref (adjacent_across seed constraint_a entry_vertex)
          and entry = ref entry_vertex and steps = ref 0 and found = ref (-1) in
          while !found < 0 && !current >= 0 && !current <> seed
              && !steps <= !triangle_count do
            if crossing_key constraint_a constraint_b !current (-1) >= 0 then
              found := !current
            else begin
              let exit = other_vertex !current constraint_a !entry in
              let next = adjacent_across !current constraint_a exit in
              entry := exit;
              current := next
            end;
            incr steps
          done;
          !found in
        let found = search first_other in
        if found >= 0 then found else search second_other
      end in
    let flip_crossing_trace constraint_a constraint_b =
      let start = ref (find_incident_start constraint_a constraint_b) in
      if !start < 0 then begin
        (* Audited degeneracy fallback: arrangement subsegments should make the
           endpoint fan sufficient, but retain a complete exact search rather
           than dropping a valid recovery event if that invariant is violated. *)
        let triangle = ref 0 in
        while !start < 0 && !triangle < !triangle_count do
          if triangle_has_point !triangle constraint_a
              && crossing_key constraint_a constraint_b !triangle (-1) >= 0 then
            start := !triangle;
          incr triangle
        done
      end;
      if !start < 0 then flip_crossing_scan constraint_a constraint_b else begin
        let current = ref !start and entry_key = ref (-1) and steps = ref 0
        and complete = ref false and failed = ref false
        and best_key = ref max_int and best_left_triangle = ref (-1)
        and best_right_triangle = ref (-1) and best_left_opposite = ref (-1)
        and best_right_opposite = ref (-1) and best_edge_a = ref (-1)
        and best_edge_b = ref (-1) in
        while not !complete && not !failed && !steps <= !triangle_count do
          if triangle_has_point !current constraint_b then complete := true
          else begin
            let key = crossing_key constraint_a constraint_b !current !entry_key in
            let slot = if key < 0 then -1 else Edge_table.find edge_table key in
            if slot < 0 || edge_table.Edge_table.second_triangles.(slot) < 0 then
              failed := true
            else begin
              let left_triangle = edge_table.Edge_table.first_triangles.(slot)
              and right_triangle = edge_table.Edge_table.second_triangles.(slot)
              and left_opposite = edge_table.Edge_table.first_opposites.(slot)
              and right_opposite = edge_table.Edge_table.second_opposites.(slot)
              and edge_a = key / point_count and edge_b = key mod point_count in
              if key < !best_key && not (Hashtbl.mem constrained key) then begin
                let convex_a = orient points.(left_opposite) points.(right_opposite)
                    points.(edge_a)
                and convex_b = orient points.(left_opposite) points.(right_opposite)
                    points.(edge_b) in
                if opposite_sign convex_a convex_b then begin
                  best_key := key;
                  best_left_triangle := left_triangle;
                  best_right_triangle := right_triangle;
                  best_left_opposite := left_opposite;
                  best_right_opposite := right_opposite;
                  best_edge_a := edge_a;
                  best_edge_b := edge_b
                end
              end;
              let adjacent = if left_triangle = !current then right_triangle
                else if right_triangle = !current then left_triangle else -1 in
              if adjacent < 0 then failed := true else begin
                entry_key := key;
                current := adjacent
              end
            end
          end;
          incr steps
        done;
        if !failed || not !complete then flip_crossing_scan constraint_a constraint_b
        else if !best_left_triangle < 0 then false else begin
          flip_diagonal !best_left_triangle !best_right_triangle
            !best_left_opposite !best_right_opposite !best_edge_a !best_edge_b;
          true
        end
      end in
    for constraint_index = 0 to constraint_count - 1 do
      if constraint_index land 255 = 0 then Cancel.check_opt cancel;
      let first = constraint_first.(constraint_index)
      and second = constraint_second.(constraint_index) in
      let key = edge_key (Array.length points) first second
      and attempts = ref 0
      and attempt_limit = squared_limit !triangle_count in
      while not (edge_exists key) do
        if !attempts land 255 = 0 then Cancel.check_opt cancel;
        if !attempts > attempt_limit then
          invalid_arg (Printf.sprintf
            "constraint recovery did not converge (side=%s source_triangle=%d constraint=%d endpoints=%d,%d attempts=%d triangles=%d)"
            (match side with Boolean_face_arrangement.Left -> "left"
             | Boolean_face_arrangement.Right -> "right")
            triangle constraint_index first second !attempts !triangle_count);
        let flipped = match constraint_recovery with
          | Trace -> flip_crossing_trace first second
          | Edge_scan -> flip_crossing_scan first second in
        if not flipped then
          invalid_arg (Printf.sprintf
            "constraint recovery found no flippable crossing edge (side=%s source_triangle=%d constraint=%d endpoints=%d,%d triangles=%d)"
            (match side with Boolean_face_arrangement.Left -> "left"
             | Boolean_face_arrangement.Right -> "right")
            triangle constraint_index first second !triangle_count);
        incr attempts
      done;
      Hashtbl.replace constrained key true
    done;
    let queue = Key_heap.create edge_table.Edge_table.edge_count in
    let queue_limit = max (edge_table.Edge_table.edge_count + 16)
        (max 1_024 (min 1_000_000
          (if edge_table.Edge_table.edge_count > 125_000 then 1_000_000
           else edge_table.Edge_table.edge_count * 8))) in
    let refill_queue () =
      queue.Key_heap.count <- 0;
      for slot = 0 to Array.length edge_table.Edge_table.keys - 1 do
        let key = edge_table.Edge_table.keys.(slot) in
        if key >= 0 && edge_table.Edge_table.second_triangles.(slot) >= 0
            && not (Hashtbl.mem constrained key) then Key_heap.push queue key
      done in
    let enqueue key =
      if queue.Key_heap.count >= queue_limit then refill_queue ();
      Key_heap.push queue key in
    refill_queue ();
    let enqueue_triangle triangle =
      let a = triangle_a.(triangle) and b = triangle_b.(triangle)
      and c = triangle_c.(triangle) in
      enqueue (edge_key point_count a b);
      enqueue (edge_key point_count b c);
      enqueue (edge_key point_count c a) in
    let flips = ref 0 and queued = ref true in
    while !queued do
      match Key_heap.pop queue with
      | None -> queued := false
      | Some key ->
          if !flips land 255 = 0 then Cancel.check_opt cancel;
          let slot = Edge_table.find edge_table key in
          if slot >= 0 && edge_table.Edge_table.second_triangles.(slot) >= 0
              && not (Hashtbl.mem constrained key) then begin
            let left_triangle = edge_table.Edge_table.first_triangles.(slot)
            and right_triangle = edge_table.Edge_table.second_triangles.(slot)
            and left_opposite = edge_table.Edge_table.first_opposites.(slot)
            and right_opposite = edge_table.Edge_table.second_opposites.(slot)
            and edge_a = key / point_count and edge_b = key mod point_count in
            let circle = incircle points.(edge_a) points.(edge_b)
                points.(left_opposite) points.(right_opposite) in
            let orientation = orient points.(edge_a) points.(edge_b)
                points.(left_opposite) in
            let illegal = match orientation, circle with
              | Predicates.Positive, Predicates.Positive
              | Predicates.Negative, Predicates.Negative -> true
              | _, Predicates.Zero ->
                  edge_key point_count left_opposite right_opposite < key
              | _ -> false in
            if illegal then begin
              let convex_a = orient points.(left_opposite) points.(right_opposite)
                  points.(edge_a)
              and convex_b = orient points.(left_opposite) points.(right_opposite)
                  points.(edge_b) in
              if opposite_sign convex_a convex_b then begin
                incr flips;
                if !flips > squared_limit !triangle_count then
                  invalid_arg "Delaunay edge flipping did not converge";
                flip_diagonal left_triangle right_triangle left_opposite
                  right_opposite edge_a edge_b;
                enqueue_triangle left_triangle;
                enqueue_triangle right_triangle
              end
            end
          end
    done;
    Ok {
      points;
      global_point_tokens = global_point_tokens constraints arrangement
          arrangement_to_point ~side ~triangle ~point_count:(Array.length points);
      source_winding;
      triangle_a = Array.sub triangle_a 0 !triangle_count;
      triangle_b = Array.sub triangle_b 0 !triangle_count;
      triangle_c = Array.sub triangle_c 0 !triangle_count;
      constraint_first;
      constraint_second;
    }
  with
  | Cancel.Cancelled -> error "cancelled" "Boolean face CDT was cancelled"
  | Invalid_argument message -> error "invalid_constraints" message

(* Boolean arrangements and the general planar CDT share the same exact PSLG
   contract. Keep this adapter at the representation boundary so Boolean face
   refinement uses the terminating strip/cavity recovery owned by Planar_cdt
   rather than maintaining a second constraint-insertion kernel. *)
let build ?cancel ?workspace ?(point_location = Walk) ?(constraint_recovery = Trace)
    constraints arrangement ~side ~triangle =
  let _ = point_location,constraint_recovery in
  try
    Cancel.check_opt cancel;
    let arrangement_count = Boolean_face_arrangement.point_count arrangement in
    let point_capacity = 3 + arrangement_count in
    let fallback = face_triangle_implicit constraints side triangle 0 in
    let points = Array.make point_capacity fallback in
    for local = 0 to 2 do
      points.(local) <- face_triangle_implicit constraints side triangle local
    done;
    let arrangement_to_point = Array.make arrangement_count 0
    and actual_point_count = ref 3 in
    for arrangement_point = 0 to arrangement_count - 1 do
      let point = Boolean_face_arrangement.Private.point arrangement arrangement_point in
      let found = ref (-1) and candidate = ref 0 in
      while !found < 0 && !candidate < 3 do
        if Implicit_point.equal points.(!candidate) point then found := !candidate;
        incr candidate
      done;
      if !found >= 0 then arrangement_to_point.(arrangement_point) <- !found
      else begin
        points.(!actual_point_count) <- point;
        arrangement_to_point.(arrangement_point) <- !actual_point_count;
        incr actual_point_count
      end
    done;
    let points = Array.sub points 0 !actual_point_count in
    let projection_axis = projection points in
    let orient_points = orient projection_axis
    and incircle_points = incircle projection_axis in
    let orientation_cache = Orientation_cache.create (Array.length points) in
    let orient_indices a b c = Orientation_cache.get orientation_cache
        (fun a b c -> orient_points points.(a) points.(b) points.(c)) a b c in
    let source_winding = match orient_indices 0 1 2 with
      | Predicates.Positive -> 1
      | Predicates.Negative -> -1
      | Predicates.Zero -> invalid_arg "degenerate source triangle during face CDT" in
    let initial_triangle_points = if source_winding > 0
      then [|0;1;2|] else [|0;2;1|] in
    let insert_points = Array.init (Array.length points - 3) (fun index -> index + 3) in
    let source_constraint_count =
      Boolean_face_arrangement.segment_count arrangement in
    (* Face arrangement already canonicalizes every construction and performs
       its own indexed all-point/segment incidence pass before materializing
       unique atomic edges. Repeating that exact O(points * segments) scan here
       dominated dense fracture refinement and could not discover a new cut. *)
    let constraint_points = Array.init (source_constraint_count * 2) (fun slot ->
        let segment = slot / 2 in
        let arrangement_point = if slot land 1 = 0 then
            Boolean_face_arrangement.segment_first arrangement segment
          else Boolean_face_arrangement.segment_second arrangement segment in
        arrangement_to_point.(arrangement_point)) in
    let constraint_count = source_constraint_count in
    let point_u_min = Array.make (Array.length points) 0.
    and point_u_max = Array.make (Array.length points) 0.
    and point_v_min = Array.make (Array.length points) 0.
    and point_v_max = Array.make (Array.length points) 0. in
    for point = 0 to Array.length points - 1 do
      let (x_min,x_max),(y_min,y_max),(z_min,z_max) =
        Implicit_point.bounds points.(point) in
      let u_min,u_max,v_min,v_max = match projection_axis with
        | 0 -> x_min,x_max,y_min,y_max
        | 1 -> y_min,y_max,z_min,z_max
        | _ -> z_min,z_max,x_min,x_max in
      point_u_min.(point) <- u_min; point_u_max.(point) <- u_max;
      point_v_min.(point) <- v_min; point_v_max.(point) <- v_max
    done;
    let bounds_overlap first second edge_a edge_b =
      let first_u_min = min point_u_min.(first) point_u_min.(second)
      and first_u_max = max point_u_max.(first) point_u_max.(second)
      and first_v_min = min point_v_min.(first) point_v_min.(second)
      and first_v_max = max point_v_max.(first) point_v_max.(second)
      and second_u_min = min point_u_min.(edge_a) point_u_min.(edge_b)
      and second_u_max = max point_u_max.(edge_a) point_u_max.(edge_b)
      and second_v_min = min point_v_min.(edge_a) point_v_min.(edge_b)
      and second_v_max = max point_v_max.(edge_a) point_v_max.(edge_b) in
      first_u_max >= second_u_min && second_u_max >= first_u_min
      && first_v_max >= second_v_min && second_v_max >= first_v_min in
    match Planar_cdt.build ?cancel ?workspace ~point_count:(Array.length points)
        ~orient:orient_indices
        ~incircle:(fun a b c d ->
          incircle_points points.(a) points.(b) points.(c) points.(d))
        ~bounds_overlap ~triangle_points:initial_triangle_points ~insert_points
        ~constraint_points () with
    | Error message when String.starts_with ~prefix:
          "Planar CDT constraint strip boundary is not simple" message ->
        build_legacy ?cancel ~point_location ~constraint_recovery constraints
          arrangement ~side ~triangle
    | Error message -> error "invalid_constraints" (Printf.sprintf
          "%s (side=%s source_triangle=%d points=%d constraints=%d)" message
          (match side with Boolean_face_arrangement.Left -> "left"
           | Boolean_face_arrangement.Right -> "right")
          triangle (Array.length points) constraint_count)
    | Ok triangulation ->
        let view = Planar_cdt.Private.view triangulation in
        let triangle_count = Array.length view.triangle_points / 3 in
        Ok {
          points;
          global_point_tokens = global_point_tokens constraints arrangement
              arrangement_to_point ~side ~triangle
              ~point_count:(Array.length points);
          source_winding;
          triangle_a = Array.init triangle_count (fun triangle ->
            view.triangle_points.(triangle * 3));
          triangle_b = Array.init triangle_count (fun triangle ->
            view.triangle_points.((triangle * 3) + 1));
          triangle_c = Array.init triangle_count (fun triangle ->
            view.triangle_points.((triangle * 3) + 2));
          constraint_first = Array.init (Array.length view.constraint_points / 2)
              (fun index -> view.constraint_points.(index * 2));
          constraint_second = Array.init (Array.length view.constraint_points / 2)
              (fun index -> view.constraint_points.((index * 2) + 1));
        }
  with
  | Cancel.Cancelled -> error "cancelled" "Boolean face CDT was cancelled"
  | Invalid_argument message -> error "invalid_constraints" message
