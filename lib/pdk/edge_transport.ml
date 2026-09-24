open Prismel

type roots = Transport_first_point | Transport_last_point
  | Transport_root_group of Group.t
type operation = Transport | Transport_from_root | Transport_total
  | Transport_maximum | Transport_minimum
type root_value = Transport_root_zero | Transport_root_hold
type split = Transport_copy | Transport_split
type normalization = Transport_no_normalization
  | Transport_normalize_components | Transport_normalize_global
type direction = Transport_forward | Transport_backward
type merge = Transport_merge_add | Transport_merge_maximum
  | Transport_merge_minimum

type source = Constant_one | Values of float array
type edge_scales = Unit_scales | Point_scales of float array
  | Indexed_scales of { tree_edge : int array; lengths : float array }

exception Transport_error of string
let fail message = raise (Transport_error message)

let[@inline always] maximum_abs left right =
  let left = abs_float left and right = abs_float right in
  if left > right then left else right

let[@inline always] finite_point positions point =
  Float.is_finite positions.Packed.Float3.Private.x.(point)
  && Float.is_finite positions.y.(point) && Float.is_finite positions.z.(point)

let[@inline always] edge_length positions a b =
  let scale = maximum_abs positions.Packed.Float3.Private.x.(a) positions.x.(b) in
  let scale = maximum_abs scale positions.y.(a) in
  let scale = maximum_abs scale positions.y.(b) in
  let scale = maximum_abs scale positions.z.(a) in
  let scale = maximum_abs scale positions.z.(b) in
  if scale = 0. then 0.
  else
    let dx = positions.x.(b) /. scale -. positions.x.(a) /. scale
    and dy = positions.y.(b) /. scale -. positions.y.(a) /. scale
    and dz = positions.z.(b) /. scale -. positions.z.(a) /. scale in
    scale *. sqrt (dx *. dx +. dy *. dy +. dz *. dz)

let[@inline always] source_value source point = match source with
  | Constant_one -> 1.
  | Values values -> values.(point)

let[@inline always] scale_value scales point = match scales with
  | Unit_scales -> 1.
  | Point_scales values -> values.(point)
  | Indexed_scales values -> values.lengths.(values.tree_edge.(point))

let[@inline always] backward_candidate operation source scales output child =
  match operation with
  | Transport | Transport_from_root
  | Transport_maximum | Transport_minimum -> output.(child)
  | Transport_total -> output.(child)
      +. source_value source child *. scale_value scales child

let record_atomic_min target value =
  let rec record () =
    let known = Atomic.get target in
    if value < known && not (Atomic.compare_and_set target known value) then
      record () in
  record ()

let evaluate_backward_tree ?cancel ~operation ~root_value ~merge ~source
    ~scales ~output ~order ~first ~last ~children ~child_offsets ~first_bad () =
  for at = last - 1 downto first do
    if at land 4095 = 0 then Cancel.check_opt cancel;
    let point = order.(at) in
    let first_child = child_offsets.(point)
    and last_child = child_offsets.(point + 1) in
    let value = if first_child = last_child then
        match operation with
        | Transport | Transport_from_root ->
            (match root_value with
             | Transport_root_zero -> 0.
             | Transport_root_hold -> source_value source point)
        | Transport_total -> 0.
        | Transport_maximum | Transport_minimum -> source_value source point
      else begin
        let aggregate = ref (backward_candidate operation source scales output
            children.(first_child)) in
        for child_at = first_child + 1 to last_child - 1 do
          let value = backward_candidate operation source scales output
              children.(child_at) in
          aggregate := match merge with
            | Transport_merge_add -> !aggregate +. value
            | Transport_merge_maximum ->
                if value > !aggregate then value else !aggregate
            | Transport_merge_minimum ->
                if value < !aggregate then value else !aggregate
        done;
        match operation with
        | Transport | Transport_from_root | Transport_total -> !aggregate
        | Transport_maximum ->
            let input = source_value source point in
            if input > !aggregate then input else !aggregate
        | Transport_minimum ->
            let input = source_value source point in
            if input < !aggregate then input else !aggregate
      end in
    output.(point) <- value;
    if not (Float.is_finite value) then record_atomic_min first_bad point
  done

let run ?cancel ?(grain = 16_384) ?points ?(roots = Transport_first_point)
    ?(operation = Transport) ?(root_value = Transport_root_hold)
    ?(integrate_constant = false) ?(scale_by_edge_length = false)
    ?(split = Transport_copy) ?(direction = Transport_forward)
    ?(merge = Transport_merge_add)
    ?(normalization = Transport_no_normalization) ~attribute geometry =
  try
    if grain <= 0 then fail "Edge Transport grain must be positive";
    if String.trim attribute = "" || attribute = "P" then
      fail "Edge Transport attribute name must be non-empty and not P";
    if integrate_constant && operation <> Transport_total then
      fail "Edge Transport constant integration requires Total";
    if scale_by_edge_length && operation <> Transport_total then
      fail "Edge Transport edge-length scaling requires Total";
    let point_count = Geometry.point_count geometry in
    (match points with
     | Some group when Group.owner group <> Group.Point ->
         fail "Edge Transport selection must own points"
     | Some group when Group.length group <> point_count ->
         fail "Edge Transport selection length does not match point count"
     | None | Some _ -> ());
    (match roots with
     | Transport_root_group group when Group.owner group <> Group.Point ->
         fail "Edge Transport root group must own points"
     | Transport_root_group group when Group.length group <> point_count ->
         fail "Edge Transport root group length does not match point count"
     | Transport_first_point | Transport_last_point
     | Transport_root_group _ -> ());
    let input = if integrate_constant then Some Constant_one
      else match Geometry.find_attribute ~owner:Attribute.Point attribute geometry with
        | None -> None
        | Some source ->
            (match Attribute.Private.storage source with
             | Attribute.Float values when Array.length values = point_count ->
                 Some (Values values)
             | Attribute.Float _ ->
                 fail "Edge Transport point attribute length mismatch"
             | _ -> fail "Edge Transport requires a scalar float point attribute") in
    match input with
    | None -> Ok geometry
    | Some input ->
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry in
    let index = Topology_index.create ?cancel topology in
    let view = Topology_index.Private.view index in
    let edge_count = Array.length view.edge_a in
    let selected point = match points with
      | None -> true | Some group -> Group.mem point group in
    let selected_count = match points with
      | None -> point_count | Some group -> Group.cardinality group in
    if selected_count = 0 then Ok geometry
    else begin
      let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
      let lengths = Array.make edge_count 0.
      and valid_edges = Bytes.make edge_count '\000'
      and first_invalid = Atomic.make max_int in
      if edge_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(edge_count - 1) (fun edge ->
        if edge land 4095 = 0 then Cancel.check_opt cancel;
        let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
        if selected a && selected b then begin
          let length = edge_length positions a b in
          lengths.(edge) <- length;
          Bytes.unsafe_set valid_edges edge '\001';
          if not (finite_point positions a && finite_point positions b
              && Float.is_finite length) then begin
            let rec record () =
              let known = Atomic.get first_invalid in
              if edge < known
                  && not (Atomic.compare_and_set first_invalid known edge) then
                record () in
            record ()
          end
        end);
      if Atomic.get first_invalid <> max_int then fail (Printf.sprintf
          "Edge Transport selected edge %d has a non-finite or unrepresentable length"
          (Atomic.get first_invalid));
      let parent_set = Array.init point_count Fun.id
      and rank = Bytes.make point_count '\000' in
      let rec find point =
        let parent = parent_set.(point) in
        if parent = point then point
        else let root = find parent in parent_set.(point) <- root; root in
      let union a b =
        let a = find a and b = find b in
        if a <> b then begin
          let ar = Char.code (Bytes.unsafe_get rank a)
          and br = Char.code (Bytes.unsafe_get rank b) in
          if ar < br then parent_set.(a) <- b
          else if br < ar then parent_set.(b) <- a
          else begin
            let root, child = if a < b then a, b else b, a in
            parent_set.(child) <- root;
            Bytes.unsafe_set rank root (Char.unsafe_chr (ar + 1))
          end
        end in
      for edge = 0 to edge_count - 1 do
        if Bytes.unsafe_get valid_edges edge <> '\000' then
          union view.edge_a.(edge) view.edge_b.(edge)
      done;
      let component_root = Array.make point_count (-1) in
      (match roots with
       | Transport_first_point ->
           for point = 0 to point_count - 1 do
             if selected point then begin
               let component = find point in
               if component_root.(component) < 0 then
                 component_root.(component) <- point
             end
           done
       | Transport_last_point ->
           for point = 0 to point_count - 1 do
             if selected point then component_root.(find point) <- point
           done
       | Transport_root_group _ -> ());
      let distance = Array.make point_count infinity
      and tree_parent = Array.make point_count (-1)
      and tree_edge = Array.make point_count (-1)
      and tree_root = Array.make point_count (-1)
      and heap_points = Array.make point_count 0
      and heap_positions = Array.make point_count (-1)
      and order = Array.make selected_count 0 in
      let heap_size = ref 0 and order_count = ref 0 in
      let less left right =
        distance.(left) < distance.(right)
        || (distance.(left) = distance.(right)
            && (tree_root.(left) < tree_root.(right)
                || (tree_root.(left) = tree_root.(right) && left < right))) in
      let assign slot point =
        heap_points.(slot) <- point; heap_positions.(point) <- slot in
      let rec bubble slot point =
        if slot = 0 then assign 0 point
        else let parent_slot = (slot - 1) / 2 in
          let parent = heap_points.(parent_slot) in
          if less point parent then begin
            assign slot parent; bubble parent_slot point
          end else assign slot point in
      let enqueue point =
        let slot = heap_positions.(point) in
        if slot = -1 then begin
          let slot = !heap_size in incr heap_size; bubble slot point
        end else if slot >= 0 then bubble slot point in
      let rec sift_down slot point =
        let left = slot * 2 + 1 in
        if left >= !heap_size then assign slot point
        else begin
          let right = left + 1 in
          let child = if right < !heap_size
              && less heap_points.(right) heap_points.(left) then right else left in
          let child_point = heap_points.(child) in
          if less child_point point then begin
            assign slot child_point; sift_down child point
          end else assign slot point
        end in
      let pop () =
        let point = heap_points.(0) in
        heap_positions.(point) <- -2; decr heap_size;
        if !heap_size > 0 then sift_down 0 heap_points.(!heap_size);
        point in
      let add_root point =
        if selected point then begin
          component_root.(find point) <- point;
          if distance.(point) = infinity then begin
            distance.(point) <- 0.; tree_parent.(point) <- point;
            tree_root.(point) <- point; enqueue point
          end
        end in
      let visits = ref 0 in
      let drain_heap () =
        while !heap_size > 0 do
          if !visits land 4095 = 0 then Cancel.check_opt cancel;
          incr visits;
          let point = pop () in
          order.(!order_count) <- point; incr order_count;
          for at = view.point_edge_offsets.(point)
              to view.point_edge_offsets.(point + 1) - 1 do
            let edge = view.point_edges.(at) in
            if Bytes.unsafe_get valid_edges edge <> '\000' then begin
              let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
              let neighbor = if a = point then b else a in
              if heap_positions.(neighbor) <> -2 then begin
                let candidate = distance.(point) +. lengths.(edge) in
                let better = candidate < distance.(neighbor)
                  || (candidate = distance.(neighbor)
                      && (tree_root.(point) < tree_root.(neighbor)
                          || (tree_root.(point) = tree_root.(neighbor)
                              && point < tree_parent.(neighbor)))) in
                if better then begin
                  distance.(neighbor) <- candidate;
                  tree_parent.(neighbor) <- point;
                  tree_edge.(neighbor) <- edge;
                  tree_root.(neighbor) <- tree_root.(point);
                  enqueue neighbor
                end
              end
            end
          done
        done in
      (match roots with
       | Transport_first_point | Transport_last_point ->
           (* These policies choose exactly one root in each disconnected
              component.  Draining each independent heap immediately avoids
              interleaving every component in one unnecessarily large heap. *)
           for component = 0 to point_count - 1 do
             if component_root.(component) >= 0 then begin
               add_root component_root.(component);
               drain_heap ()
             end
           done
       | Transport_root_group group ->
           Group.iter add_root group;
           drain_heap ());
      let unrepresentable = ref (-1) in
      for point = 0 to point_count - 1 do
        if !unrepresentable < 0 && selected point
            && component_root.(find point) >= 0
            && distance.(point) = infinity then unrepresentable := point
      done;
      if !unrepresentable >= 0 then fail (Printf.sprintf
          "Edge Transport path distance to point %d is not representable"
          !unrepresentable);
      if !order_count = 0 then Ok geometry
      else if direction = Transport_backward then begin
      let child_count = Array.make point_count 0 and root_count = ref 0 in
      for at = 0 to !order_count - 1 do
        let point = order.(at) and parent = tree_parent.(order.(at)) in
        if parent = point then incr root_count
        else child_count.(parent) <- child_count.(parent) + 1
      done;
      let child_offsets = Array.make (point_count + 1) 0 in
      for point = 0 to point_count - 1 do
        child_offsets.(point + 1) <- child_offsets.(point) + child_count.(point)
      done;
      let children = Array.make child_offsets.(point_count) 0 in
      Array.fill child_count 0 point_count 0;
      for at = 0 to !order_count - 1 do
        let point = order.(at) and parent = tree_parent.(order.(at)) in
        if parent <> point then begin
          let target = child_offsets.(parent) + child_count.(parent) in
          children.(target) <- point;
          child_count.(parent) <- child_count.(parent) + 1
        end
      done;
      let grouped_order = Array.make !order_count 0
      and root_offsets = Array.make (!root_count + 1) 0 in
      let grouped_count = ref 0 and root_index = ref 0 in
      for at = 0 to !order_count - 1 do
        let root = order.(at) in
        if tree_parent.(root) = root then begin
          let first = !grouped_count in
          root_offsets.(!root_index) <- first;
          grouped_order.(!grouped_count) <- root; incr grouped_count;
          let read = ref first in
          while !read < !grouped_count do
            let point = grouped_order.(!read) in
            for child_at = child_offsets.(point)
                to child_offsets.(point + 1) - 1 do
              grouped_order.(!grouped_count) <- children.(child_at);
              incr grouped_count
            done;
            incr read
          done;
          incr root_index;
          root_offsets.(!root_index) <- !grouped_count
        end
      done;
      let output = match input with
        | Constant_one -> Array.make point_count 1.
        | Values values -> Array.copy values in
      let scales = if scale_by_edge_length then
          Indexed_scales { tree_edge; lengths } else Unit_scales in
      let first_bad = Atomic.make max_int in
      let average_tree_size = max 1
          ((!grouped_count + !root_count - 1) / !root_count) in
      let root_grain = max 1 (grain / average_tree_size) in
      Parallel.for_ ~chunk_size:root_grain ~start:0
        ~finish:(!root_count - 1) (fun root_index ->
          evaluate_backward_tree ?cancel ~operation ~root_value ~merge
            ~source:input ~scales ~output ~order:grouped_order
            ~first:root_offsets.(root_index)
            ~last:root_offsets.(root_index + 1) ~children ~child_offsets
            ~first_bad ());
      if Atomic.get first_bad <> max_int then fail (Printf.sprintf
          "Edge Transport produced a non-finite backward value at point %d"
          (Atomic.get first_bad));
      (match normalization with
       | Transport_no_normalization -> ()
       | Transport_normalize_global ->
           let minimum = ref infinity and maximum = ref neg_infinity in
           for at = 0 to !grouped_count - 1 do
             let value = output.(grouped_order.(at)) in
             if value < !minimum then minimum := value;
             if value > !maximum then maximum := value
           done;
           let span = !maximum -. !minimum in
           Parallel.for_ ~chunk_size:grain ~start:0
             ~finish:(!grouped_count - 1) (fun at ->
               let point = grouped_order.(at) in
               output.(point) <- if span = 0. then 0.
                 else (output.(point) -. !minimum) /. span)
       | Transport_normalize_components ->
           let minimum = Array.make point_count infinity
           and maximum = Array.make point_count neg_infinity in
           for at = 0 to !grouped_count - 1 do
             let point = grouped_order.(at) in
             let component = parent_set.(point) in
             if output.(point) < minimum.(component) then
               minimum.(component) <- output.(point);
             if output.(point) > maximum.(component) then
               maximum.(component) <- output.(point)
           done;
           Parallel.for_ ~chunk_size:grain ~start:0
             ~finish:(!grouped_count - 1) (fun at ->
               let point = grouped_order.(at) in
               let component = parent_set.(point) in
               let span = maximum.(component) -. minimum.(component) in
               output.(point) <- if span = 0. then 0.
                 else (output.(point) -. minimum.(component)) /. span));
      let attribute = Attribute.create_owned ~owner:Attribute.Point ~name:attribute
          (Attribute.Float output) |> function
        | Ok attribute -> attribute | Error message -> fail message in
      Geometry.with_attribute attribute geometry
      end
      else begin
      let child_count = if split = Transport_split then begin
          let counts = Array.make point_count 0 in
          for at = 0 to !order_count - 1 do
            let point = order.(at) and parent = tree_parent.(order.(at)) in
            if parent >= 0 && parent <> point then
              counts.(parent) <- counts.(parent) + 1
          done;
          Some counts
        end else None in
      let output = match input with
        | Constant_one -> Array.make point_count 1.
        | Values values -> Array.copy values in
      let[@inline always] input_at point = match input with
        | Constant_one -> 1.
        | Values values -> values.(point) in
      let first_bad = ref (-1) in
      for at = 0 to !order_count - 1 do
        if at land 4095 = 0 then Cancel.check_opt cancel;
        let point = order.(at) and parent = tree_parent.(order.(at)) in
        let value = if parent = point then match operation with
          | Transport | Transport_from_root -> (match root_value with
              | Transport_root_zero -> 0. | Transport_root_hold -> input_at point)
          | Transport_maximum | Transport_minimum -> input_at point
          | Transport_total -> 0.
        else match operation with
          | Transport ->
              let value = output.(parent) in
              (match child_count with
               | Some counts when counts.(parent) > 0 ->
                   value /. float_of_int counts.(parent)
               | None | Some _ -> value)
          | Transport_from_root -> output.(tree_root.(point))
          | Transport_total ->
              let contribution = input_at parent
                  *. (if scale_by_edge_length then
                    lengths.(tree_edge.(point)) else 1.) in
              let value = output.(parent) +. contribution in
              (match child_count with
               | Some counts when counts.(parent) > 0 ->
                   value /. float_of_int counts.(parent)
               | None | Some _ -> value)
          | Transport_maximum -> let input = input_at point in
              if input > output.(parent) then input else output.(parent)
          | Transport_minimum -> let input = input_at point in
              if input < output.(parent) then input else output.(parent) in
        output.(point) <- value;
        if !first_bad < 0 && not (Float.is_finite value) then first_bad := point
      done;
      if !first_bad >= 0 then fail (Printf.sprintf
          "Edge Transport produced a non-finite value at point %d" !first_bad);
      (match normalization with
       | Transport_no_normalization -> ()
       | Transport_normalize_global ->
           let minimum = ref infinity and maximum = ref neg_infinity in
           for at = 0 to !order_count - 1 do
             let value = output.(order.(at)) in
             if value < !minimum then minimum := value;
             if value > !maximum then maximum := value
           done;
           let span = !maximum -. !minimum in
           for at = 0 to !order_count - 1 do
             let point = order.(at) in
             output.(point) <- if span = 0. then 0.
               else (output.(point) -. !minimum) /. span
           done
       | Transport_normalize_components ->
           let minimum = Array.make point_count infinity
           and maximum = Array.make point_count neg_infinity in
           for at = 0 to !order_count - 1 do
             let point = order.(at) and component = find order.(at) in
             if output.(point) < minimum.(component) then
               minimum.(component) <- output.(point);
             if output.(point) > maximum.(component) then
               maximum.(component) <- output.(point)
           done;
           for at = 0 to !order_count - 1 do
             let point = order.(at) and component = find order.(at) in
             let span = maximum.(component) -. minimum.(component) in
             output.(point) <- if span = 0. then 0.
               else (output.(point) -. minimum.(component)) /. span
           done);
      let attribute = Attribute.create_owned ~owner:Attribute.Point ~name:attribute
          (Attribute.Float output) |> function
        | Ok attribute -> attribute | Error message -> fail message in
      Geometry.with_attribute attribute geometry
      end
    end
  with Transport_error message -> Error message

let run_parent ?cancel ?(grain = 16_384) ?points
    ?(parent_attribute = "parent") ?(direction = Transport_forward)
    ?(operation = Transport) ?(root_value = Transport_root_hold)
    ?(integrate_constant = false) ?(scale_by_edge_length = false)
    ?(split = Transport_copy) ?(merge = Transport_merge_add)
    ?(normalization = Transport_no_normalization) ~attribute geometry =
  try
    if grain <= 0 then fail "Edge Transport Parent grain must be positive";
    if String.trim parent_attribute = "" then
      fail "Edge Transport Parent attribute name must be non-empty";
    if String.trim attribute = "" || attribute = "P" then
      fail "Edge Transport Parent transported attribute must be non-empty and not P";
    if integrate_constant && operation <> Transport_total then
      fail "Edge Transport Parent constant integration requires Total";
    if scale_by_edge_length && operation <> Transport_total then
      fail "Edge Transport Parent edge-length scaling requires Total";
    let point_count = Geometry.point_count geometry in
    (match points with
     | Some group when Group.owner group <> Group.Point ->
         fail "Edge Transport Parent selection must own points"
     | Some group when Group.length group <> point_count ->
         fail "Edge Transport Parent selection length does not match point count"
     | None | Some _ -> ());
    let parents = match Geometry.find_attribute ~owner:Attribute.Point
        parent_attribute geometry with
      | None -> fail (Printf.sprintf
          "Edge Transport Parent could not find integer point attribute %S"
          parent_attribute)
      | Some parent ->
          (match Attribute.Private.storage parent with
           | Attribute.Int values when Array.length values = point_count -> values
           | Attribute.Int _ ->
               fail "Edge Transport Parent attribute length mismatch"
           | _ -> fail
               "Edge Transport Parent requires an integer point parent attribute") in
    let input = if integrate_constant then Some Constant_one
      else match Geometry.find_attribute ~owner:Attribute.Point attribute geometry with
        | None -> None
        | Some source ->
            (match Attribute.Private.storage source with
             | Attribute.Float values when Array.length values = point_count ->
                 Some (Values values)
             | Attribute.Float _ ->
                 fail "Edge Transport Parent point attribute length mismatch"
             | _ -> fail
                 "Edge Transport Parent requires a scalar float point attribute") in
    match input with
    | None -> Ok geometry
    | Some input ->
        Cancel.check_opt cancel;
        let selected point = match points with
          | None -> true | Some group -> Group.mem point group in
        let selected_count = match points with
          | None -> point_count | Some group -> Group.cardinality group in
        if selected_count = 0 then Ok geometry
        else
          let ordered_prefix =
            let limit = min point_count 256 in
            let point = ref 0 and ordered = ref true in
            while !ordered && !point < limit do
              let parent = parents.(!point) in
              if parent >= 0 && parent < point_count && parent <> !point
                  && parent >= !point then ordered := false;
              incr point
            done;
            !ordered in
          let ordered_fast_path = if Option.is_none points && ordered_prefix
              && direction = Transport_forward && split = Transport_copy
              && normalization <> Transport_normalize_components then begin
              let positions = Packed.Float3.Private.view
                  (Geometry.positions geometry) in
              let output = match input with
                | Constant_one -> Array.make point_count 1.
                | Values values -> Array.copy values in
              let[@inline always] input_at point = match input with
                | Constant_one -> 1.
                | Values values -> values.(point) in
              let point = ref 0 and ordered = ref true in
              while !ordered && !point < point_count do
                if !point land 4095 = 0 then Cancel.check_opt cancel;
                let parent = parents.(!point) in
                let root = parent < 0 || parent >= point_count
                  || parent = !point in
                if not root && parent >= !point then ordered := false
                else begin
                  let value = if root then match operation with
                    | Transport | Transport_from_root ->
                        (match root_value with
                         | Transport_root_zero -> 0.
                         | Transport_root_hold -> input_at !point)
                    | Transport_total -> 0.
                    | Transport_maximum | Transport_minimum -> input_at !point
                  else match operation with
                    | Transport | Transport_from_root -> output.(parent)
                    | Transport_total ->
                        let scale = if scale_by_edge_length then begin
                            let length = edge_length positions parent !point in
                            if not (finite_point positions parent
                                && finite_point positions !point
                                && Float.is_finite length) then fail (Printf.sprintf
                                "Edge Transport Parent edge into point %d has a non-finite or unrepresentable length"
                                !point);
                            length
                          end else 1. in
                        output.(parent) +. input_at parent *. scale
                    | Transport_maximum ->
                        let input = input_at !point in
                        if input > output.(parent) then input else output.(parent)
                    | Transport_minimum ->
                        let input = input_at !point in
                        if input < output.(parent) then input else output.(parent) in
                  if not (Float.is_finite value) then fail (Printf.sprintf
                      "Edge Transport Parent produced a non-finite value at point %d"
                      !point);
                  output.(!point) <- value;
                  incr point
                end
              done;
              if not !ordered then None
              else begin
                if normalization = Transport_normalize_global then begin
                  let minimum = ref infinity and maximum = ref neg_infinity in
                  for point = 0 to point_count - 1 do
                    let value = output.(point) in
                    if value < !minimum then minimum := value;
                    if value > !maximum then maximum := value
                  done;
                  let span = !maximum -. !minimum in
                  Parallel.for_ ~chunk_size:grain ~start:0
                    ~finish:(point_count - 1) (fun point ->
                      output.(point) <- if span = 0. then 0.
                        else (output.(point) -. !minimum) /. span)
                end;
                let attribute = Attribute.create_owned ~owner:Attribute.Point
                    ~name:attribute (Attribute.Float output) |> function
                  | Ok attribute -> attribute | Error message -> fail message in
                Some (Geometry.with_attribute attribute geometry)
              end
            end else None in
          match ordered_fast_path with
          | Some result -> result
          | None -> begin
          let tree_parent = match points with
            | None ->
                let needs_normalization = Atomic.make false in
                Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(point_count - 1)
                  (fun point ->
                    if point land 4095 = 0 then Cancel.check_opt cancel;
                    let parent = parents.(point) in
                    if parent < 0 || parent >= point_count then
                      Atomic.set needs_normalization true);
                if not (Atomic.get needs_normalization) then parents
                else begin
                  let normalized = Array.make point_count 0 in
                  Parallel.for_ ~chunk_size:grain ~start:0
                    ~finish:(point_count - 1) (fun point ->
                      let parent = parents.(point) in
                      normalized.(point) <- if parent < 0 || parent >= point_count
                        then point else parent);
                  normalized
                end
            | Some _ ->
                let normalized = Array.make point_count (-1) in
                Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(point_count - 1) (fun point ->
                    if point land 4095 = 0 then Cancel.check_opt cancel;
                    if selected point then begin
                      let parent = parents.(point) in
                      normalized.(point) <- if parent < 0 || parent >= point_count
                          || parent = point || not (selected parent)
                        then point else parent
                    end);
                normalized in
          let child_count = Array.make point_count 0 and root_count = ref 0 in
          for point = 0 to point_count - 1 do
            let parent = tree_parent.(point) in
            if parent = point then incr root_count
            else if parent >= 0 then child_count.(parent) <- child_count.(parent) + 1
          done;
          if !root_count = 0 then Ok geometry
          else begin
            let child_offsets = Array.make (point_count + 1) 0 in
            for point = 0 to point_count - 1 do
              child_offsets.(point + 1) <- child_offsets.(point) + child_count.(point)
            done;
            let children = Array.make child_offsets.(point_count) 0 in
            Array.fill child_count 0 point_count 0;
            for point = 0 to point_count - 1 do
              let parent = tree_parent.(point) in
              if parent >= 0 && parent <> point then begin
                let target = child_offsets.(parent) + child_count.(parent) in
                children.(target) <- point;
                child_count.(parent) <- child_count.(parent) + 1
              end
            done;
            let order = Array.make selected_count 0
            and root_offsets = Array.make (!root_count + 1) 0 in
            let order_count = ref 0 and root_index = ref 0 in
            for root = 0 to point_count - 1 do
              if tree_parent.(root) = root then begin
                let first = !order_count in
                root_offsets.(!root_index) <- first;
                order.(!order_count) <- root; incr order_count;
                let read = ref first in
                while !read < !order_count do
                  let point = order.(!read) in
                  for at = child_offsets.(point)
                      to child_offsets.(point + 1) - 1 do
                    order.(!order_count) <- children.(at); incr order_count
                  done;
                  incr read
                done;
                incr root_index;
                root_offsets.(!root_index) <- !order_count
              end
            done;
            let positions = Packed.Float3.Private.view
                (Geometry.positions geometry) in
            let edge_lengths = if scale_by_edge_length then begin
                let lengths = Array.make point_count 0.
                and first_invalid = Atomic.make max_int in
                Parallel.for_ ~chunk_size:grain ~start:0
                  ~finish:(!order_count - 1) (fun at ->
                    if at land 4095 = 0 then Cancel.check_opt cancel;
                    let point = order.(at) and parent = tree_parent.(order.(at)) in
                    if parent <> point then begin
                      let length = edge_length positions parent point in
                      lengths.(point) <- length;
                      if not (finite_point positions parent
                          && finite_point positions point
                          && Float.is_finite length) then begin
                        let rec record () =
                          let known = Atomic.get first_invalid in
                          if point < known && not (Atomic.compare_and_set
                              first_invalid known point) then record () in
                        record ()
                      end
                    end);
                if Atomic.get first_invalid <> max_int then fail (Printf.sprintf
                    "Edge Transport Parent edge into point %d has a non-finite or unrepresentable length"
                    (Atomic.get first_invalid));
                Some lengths
              end else None in
            let output = match input with
              | Constant_one -> Array.make point_count 1.
              | Values values -> Array.copy values in
            let[@inline always] input_at point = match input with
              | Constant_one -> 1.
              | Values values -> values.(point) in
            let[@inline always] edge_scale point = match edge_lengths with
              | None -> 1. | Some lengths -> lengths.(point) in
            let scales = match edge_lengths with
              | None -> Unit_scales | Some lengths -> Point_scales lengths in
            let first_bad = Atomic.make max_int in
            let record_bad point =
              let rec record () =
                let known = Atomic.get first_bad in
                if point < known
                    && not (Atomic.compare_and_set first_bad known point) then
                  record () in
              record () in
            let average_tree_size = max 1
                ((!order_count + !root_count - 1) / !root_count) in
            let root_grain = max 1 (grain / average_tree_size) in
            Parallel.for_ ~chunk_size:root_grain ~start:0
              ~finish:(!root_count - 1) (fun root_index ->
                let first = root_offsets.(root_index)
                and last = root_offsets.(root_index + 1) in
                (match direction with
                 | Transport_forward ->
                     for at = first to last - 1 do
                       if at land 4095 = 0 then Cancel.check_opt cancel;
                       let point = order.(at) and parent = tree_parent.(order.(at)) in
                       let value = if parent = point then match operation with
                         | Transport | Transport_from_root ->
                             (match root_value with
                              | Transport_root_zero -> 0.
                              | Transport_root_hold -> input_at point)
                         | Transport_total -> 0.
                         | Transport_maximum | Transport_minimum -> input_at point
                       else match operation with
                         | Transport ->
                             let value = output.(parent) in
                             if split = Transport_split
                               && child_count.(parent) > 0 then
                               value /. float_of_int child_count.(parent) else value
                         | Transport_from_root -> output.(order.(first))
                         | Transport_total ->
                             let value = output.(parent)
                               +. input_at parent *. edge_scale point in
                             if split = Transport_split
                               && child_count.(parent) > 0 then
                               value /. float_of_int child_count.(parent) else value
                         | Transport_maximum ->
                             let input = input_at point in
                             if input > output.(parent) then input else output.(parent)
                         | Transport_minimum ->
                             let input = input_at point in
                             if input < output.(parent) then input else output.(parent) in
                       output.(point) <- value;
                       if not (Float.is_finite value) then record_bad point
                     done
                 | Transport_backward ->
                     evaluate_backward_tree ?cancel ~operation ~root_value
                       ~merge ~source:input ~scales ~output ~order ~first ~last
                       ~children ~child_offsets ~first_bad ());
                if normalization = Transport_normalize_components then begin
                  let minimum = ref infinity and maximum = ref neg_infinity in
                  for at = first to last - 1 do
                    let value = output.(order.(at)) in
                    if value < !minimum then minimum := value;
                    if value > !maximum then maximum := value
                  done;
                  let span = !maximum -. !minimum in
                  for at = first to last - 1 do
                    let point = order.(at) in
                    output.(point) <- if span = 0. then 0.
                      else (output.(point) -. !minimum) /. span
                  done
                end);
            if Atomic.get first_bad <> max_int then fail (Printf.sprintf
                "Edge Transport Parent produced a non-finite value at point %d"
                (Atomic.get first_bad));
            if normalization = Transport_normalize_global then begin
              let minimum = ref infinity and maximum = ref neg_infinity in
              for at = 0 to !order_count - 1 do
                let value = output.(order.(at)) in
                if value < !minimum then minimum := value;
                if value > !maximum then maximum := value
              done;
              let span = !maximum -. !minimum in
              Parallel.for_ ~chunk_size:grain ~start:0
                ~finish:(!order_count - 1) (fun at ->
                  let point = order.(at) in
                  output.(point) <- if span = 0. then 0.
                    else (output.(point) -. !minimum) /. span)
            end;
            let attribute = Attribute.create_owned ~owner:Attribute.Point
                ~name:attribute (Attribute.Float output) |> function
              | Ok attribute -> attribute | Error message -> fail message in
            Geometry.with_attribute attribute geometry
          end
        end
  with Transport_error message -> Error message

let run_curves ?cancel ?(grain = 16_384) ?primitives
    ?(owner = Attribute.Point) ?(direction = Transport_forward)
    ?(operation = Transport) ?(root_value = Transport_root_hold)
    ?(integrate_constant = false) ?(scale_by_edge_length = false)
    ?(normalization = Transport_no_normalization) ~attribute geometry =
  try
    if grain <= 0 then fail "Edge Transport Each Curve grain must be positive";
    if String.trim attribute = "" || attribute = "P" then
      fail "Edge Transport Each Curve attribute name must be non-empty and not P";
    if owner <> Attribute.Point && owner <> Attribute.Vertex then
      fail "Edge Transport Each Curve supports point or vertex attributes";
    if integrate_constant && operation <> Transport_total then
      fail "Edge Transport Each Curve constant integration requires Total";
    if scale_by_edge_length && operation <> Transport_total then
      fail "Edge Transport Each Curve edge-length scaling requires Total";
    let topology_value = Geometry.topology geometry in
    let topology = Topology.Private.view topology_value in
    let point_count = Geometry.point_count geometry
    and vertex_count = Array.length topology.vertex_points
    and primitive_count = Bytes.length topology.primitive_kinds in
    (match primitives with
     | Some group when Group.owner group <> Group.Primitive ->
         fail "Edge Transport Each Curve selection must own primitives"
     | Some group when Group.length group <> primitive_count ->
         fail "Edge Transport Each Curve selection length does not match primitive count"
     | None | Some _ -> ());
    let selected primitive = match primitives with
      | None -> true | Some group -> Group.mem primitive group in
    let selected_count = match primitives with
      | None -> primitive_count | Some group -> Group.cardinality group in
    if selected_count = 0 then Ok geometry
    else begin
      let domain_count = if owner = Attribute.Point then point_count else vertex_count in
      let input = if integrate_constant then Some Constant_one
        else match Geometry.find_attribute ~owner attribute geometry with
          | None -> None
          | Some source ->
              (match Attribute.Private.storage source with
               | Attribute.Float values when Array.length values = domain_count ->
                   Some (Values values)
               | Attribute.Float _ ->
                   fail "Edge Transport Each Curve attribute length mismatch"
               | _ -> fail
                   "Edge Transport Each Curve requires a scalar float attribute") in
      match input with
      | None -> Ok geometry
      | Some input ->
          Cancel.check_opt cancel;
          let selected_vertices = ref 0 in
          for primitive = 0 to primitive_count - 1 do
            if selected primitive then selected_vertices := !selected_vertices
                + topology.primitive_offsets.(primitive + 1)
                - topology.primitive_offsets.(primitive)
          done;
          let average_curve_size = max 1
              ((!selected_vertices + selected_count - 1) / selected_count) in
          let primitive_grain = max 1 (grain / average_curve_size) in
          (* Point writes from different curves would race and are undefined in
             Houdini as well. Reject them deterministically; vertex attributes
             are disjoint by construction. *)
          if owner = Attribute.Point && selected_count > 1 then begin
            let first_curve = Array.make point_count (-1) in
            for primitive = 0 to primitive_count - 1 do
              if selected primitive then
                for vertex = topology.primitive_offsets.(primitive)
                    to topology.primitive_offsets.(primitive + 1) - 1 do
                  let point = topology.vertex_points.(vertex) in
                  if first_curve.(point) >= 0
                      && first_curve.(point) <> primitive then fail (Printf.sprintf
                      "Edge Transport Each Curve point %d is shared by primitives %d and %d"
                      point first_curve.(point) primitive)
                  else first_curve.(point) <- primitive
                done
            done
          end;
          let positions = Packed.Float3.Private.view (Geometry.positions geometry) in
          let output = match input with
            | Constant_one -> Array.make domain_count 1.
            | Values values -> Array.copy values in
          let[@inline always] input_at element = match input with
            | Constant_one -> 1.
            | Values values -> values.(element) in
          let first_bad = Atomic.make max_int in
          let record_bad element =
            let rec record () =
              let known = Atomic.get first_bad in
              if element < known
                  && not (Atomic.compare_and_set first_bad known element) then
                record () in
            record () in
          let curve_layout primitive =
            let first = topology.primitive_offsets.(primitive) in
            let size = topology.primitive_offsets.(primitive + 1) - first in
            if size = 0 then first, size, 0, 1
            else
              let closed = Bytes.unsafe_get topology.primitive_kinds primitive
                  <> '\001' in
              let forward_root, forward_step = if not closed then
                  let first_point = topology.vertex_points.(first)
                  and last_point = topology.vertex_points.(first + size - 1) in
                  if first_point <= last_point then 0, 1 else size - 1, -1
                else begin
                  let root = ref 0 in
                  for local = 1 to size - 1 do
                    if topology.vertex_points.(first + local)
                        < topology.vertex_points.(first + !root) then root := local
                  done;
                  if size <= 2 then !root, 1
                  else
                    let next = topology.vertex_points.(first + ((!root + 1) mod size))
                    and previous = topology.vertex_points.
                        (first + ((!root + size - 1) mod size)) in
                    !root, if next <= previous then 1 else -1
                end in
              let root, step = match direction with
                | Transport_forward -> forward_root, forward_step
                | Transport_backward when closed -> forward_root, -forward_step
                | Transport_backward -> size - 1 - forward_root, -forward_step in
              first, size, root, step in
          let vertex_at first size root step ordinal =
            let local = (root + (ordinal * step mod size) + size) mod size in
            first + local in
          let element_at vertex = if owner = Attribute.Point
            then topology.vertex_points.(vertex) else vertex in
          Parallel.for_ ~chunk_size:primitive_grain ~start:0
            ~finish:(primitive_count - 1)
            (fun primitive ->
              if primitive land 4095 = 0 then Cancel.check_opt cancel;
              if selected primitive then begin
                let first, size, root, step = curve_layout primitive in
                if size > 0 then begin
                  let root_vertex = vertex_at first size root step 0 in
                  let root_element = element_at root_vertex in
                  output.(root_element) <- (match operation with
                    | Transport | Transport_from_root ->
                        (match root_value with
                         | Transport_root_zero -> 0.
                         | Transport_root_hold -> input_at root_element)
                    | Transport_total -> 0.
                    | Transport_maximum | Transport_minimum ->
                        input_at root_element);
                  for ordinal = 1 to size - 1 do
                    let previous_vertex = vertex_at first size root step (ordinal - 1)
                    and vertex = vertex_at first size root step ordinal in
                    let previous = element_at previous_vertex
                    and element = element_at vertex in
                    let value = match operation with
                      | Transport -> output.(previous)
                      | Transport_from_root -> output.(root_element)
                      | Transport_total ->
                          let scale = if scale_by_edge_length then
                              let a = topology.vertex_points.(previous_vertex)
                              and b = topology.vertex_points.(vertex) in
                              if finite_point positions a && finite_point positions b
                              then edge_length positions a b else nan
                            else 1. in
                          output.(previous) +. input_at previous *. scale
                      | Transport_maximum ->
                          let value = input_at element in
                          if value > output.(previous) then value else output.(previous)
                      | Transport_minimum ->
                          let value = input_at element in
                          if value < output.(previous) then value else output.(previous) in
                    output.(element) <- value;
                    if not (Float.is_finite value) then record_bad element
                  done;
                  if not (Float.is_finite output.(root_element)) then
                    record_bad root_element;
                  if normalization = Transport_normalize_components then begin
                    let minimum = ref infinity and maximum = ref neg_infinity in
                    for ordinal = 0 to size - 1 do
                      let element = element_at (vertex_at first size root step ordinal) in
                      let value = output.(element) in
                      if value < !minimum then minimum := value;
                      if value > !maximum then maximum := value
                    done;
                    let span = !maximum -. !minimum in
                    for ordinal = 0 to size - 1 do
                      let element = element_at (vertex_at first size root step ordinal) in
                      output.(element) <- if span = 0. then 0.
                        else (output.(element) -. !minimum) /. span
                    done
                  end
                end
              end);
          if Atomic.get first_bad <> max_int then fail (Printf.sprintf
              "Edge Transport Each Curve produced a non-finite value at element %d"
              (Atomic.get first_bad));
          if normalization = Transport_normalize_global then begin
            let minimum = ref infinity and maximum = ref neg_infinity in
            for primitive = 0 to primitive_count - 1 do
              if selected primitive then
                for vertex = topology.primitive_offsets.(primitive)
                    to topology.primitive_offsets.(primitive + 1) - 1 do
                  let value = output.(element_at vertex) in
                  if value < !minimum then minimum := value;
                  if value > !maximum then maximum := value
                done
            done;
            let span = !maximum -. !minimum in
            Parallel.for_ ~chunk_size:primitive_grain ~start:0
              ~finish:(primitive_count - 1)
              (fun primitive ->
                if primitive land 4095 = 0 then Cancel.check_opt cancel;
                if selected primitive then
                  for vertex = topology.primitive_offsets.(primitive)
                      to topology.primitive_offsets.(primitive + 1) - 1 do
                    let element = element_at vertex in
                    output.(element) <- if span = 0. then 0.
                      else (output.(element) -. !minimum) /. span
                  done)
          end;
          let attribute = Attribute.create_owned ~owner ~name:attribute
              (Attribute.Float output) |> function
            | Ok attribute -> attribute | Error message -> fail message in
          Geometry.with_attribute attribute geometry
    end
  with Transport_error message -> Error message
