open Prismel

type selection = Relax_points of Group.t | Relax_primitives of Group.t
type target_mode = Individual_lengths | Scale_independent_distribution

exception Relax_error of string
let fail message = raise (Relax_error message)

let[@inline always] finite positions point =
  Float.is_finite positions.Packed.Float3.Private.x.(point)
  && Float.is_finite positions.y.(point)
  && Float.is_finite positions.z.(point)

let[@inline always] maximum_abs left right =
  let left = abs_float left and right = abs_float right in
  if left > right then left else right

let[@inline always] length_between positions a b =
  let scale = maximum_abs positions.Packed.Float3.Private.x.(a)
      positions.x.(b) in
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

let same_topology left right =
  let left = Topology.Private.view left and right = Topology.Private.view right in
  left.point_count = right.point_count
  && left.vertex_points = right.vertex_points
  && left.primitive_offsets = right.primitive_offsets
  && Bytes.equal left.primitive_kinds right.primitive_kinds

let relax ?cancel ?(grain = 16_384) ?selection ?pin_points
    ?(iterations = 20) ?(step_size = 0.5)
    ?(target_mode = Individual_lengths) ?(only_shorten = false)
    ?(tolerance = 1e-6) ~reference geometry =
  try
    if grain <= 0 then fail "Edge Relax grain must be positive";
    if iterations <= 0 then fail "Edge Relax iterations must be positive";
    if not (Float.is_finite step_size) || step_size <= 0. || step_size > 1. then
      fail "Edge Relax step size must be finite and within (0, 1]";
    if not (Float.is_finite tolerance) || tolerance <= 0. then
      fail "Edge Relax tolerance must be finite and positive";
    Cancel.check_opt cancel;
    let topology = Geometry.topology geometry
    and reference_topology = Geometry.topology reference in
    if not (same_topology topology reference_topology) then
      fail "Edge Relax reference topology must exactly match the source topology";
    let point_count = Geometry.point_count geometry in
    let point_selection = match selection with
      | None -> None
      | Some (Relax_points group) ->
          if Group.owner group <> Group.Point then
            fail "Edge Relax point selection must own points";
          if Group.length group <> point_count then
            fail "Edge Relax point selection length does not match point count";
          Some group
      | Some (Relax_primitives group) ->
          if Group.owner group <> Group.Primitive then
            fail "Edge Relax primitive selection must own primitives";
          if Group.length group <> Geometry.primitive_count geometry then
            fail "Edge Relax primitive selection length does not match primitive count";
          (match Element_selection.promote ?cancel ~grain ~destination:Group.Point
              (Element_selection.Selected_primitives group) topology with
           | Ok group -> Some group | Error message -> fail message) in
    (match pin_points with
     | Some group when Group.owner group <> Group.Point ->
         fail "Edge Relax pin group must own points"
     | Some group when Group.length group <> point_count ->
         fail "Edge Relax pin group length does not match point count"
     | None | Some _ -> ());
    let movable point =
      (match point_selection with None -> true | Some group -> Group.mem point group)
      && (match pin_points with None -> true | Some group -> not (Group.mem point group)) in
    let index = Topology_index.create ?cancel topology in
    let view = Topology_index.Private.view index in
    let edge_count = Array.length view.edge_a in
    if edge_count = 0 then Ok geometry
    else begin
      let all_movable = Option.is_none selection && Option.is_none pin_points in
      let selected_flags = if all_movable then None
        else Some (Bytes.make edge_count '\000')
      and degrees = if all_movable then None
        else Some (Array.make point_count 0)
      and source_lengths = Array.make edge_count 0.
      and reference_lengths = Array.make edge_count 0. in
      let selected_count = ref (if all_movable then edge_count else 0)
      and first_invalid = Atomic.make max_int in
      let source_positions = Packed.Float3.Private.view (Geometry.positions geometry)
      and reference_positions = Packed.Float3.Private.view
          (Geometry.positions reference) in
      (match selected_flags, degrees with
       | Some selected_flags, Some degrees ->
           for edge = 0 to edge_count - 1 do
             if edge land 4095 = 0 then Cancel.check_opt cancel;
             let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
             if movable a || movable b then begin
               Bytes.unsafe_set selected_flags edge '\001';
               incr selected_count;
               degrees.(a) <- degrees.(a) + 1;
               if b <> a then degrees.(b) <- degrees.(b) + 1
             end
           done
       | None, None -> ()
       | _ -> assert false);
      if !selected_count = 0 then Ok geometry
      else begin
        Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(edge_count - 1)
          (fun edge ->
            if edge land 4095 = 0 then Cancel.check_opt cancel;
            if all_movable || (match selected_flags with
                | Some flags -> Bytes.unsafe_get flags edge <> '\000'
                | None -> false) then begin
              let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
              let source_length = length_between source_positions a b
              and reference_length = length_between reference_positions a b in
              source_lengths.(edge) <- source_length;
              reference_lengths.(edge) <- reference_length;
              if not (finite source_positions a && finite source_positions b
                  && finite reference_positions a && finite reference_positions b
                  && Float.is_finite source_length
                  && Float.is_finite reference_length) then begin
                let rec record () =
                  let known = Atomic.get first_invalid in
                  if edge < known
                      && not (Atomic.compare_and_set first_invalid known edge)
                  then record () in
                record ()
              end
            end);
        if Atomic.get first_invalid <> max_int then fail (Printf.sprintf
            "Edge Relax selected edge %d has a non-finite or unrepresentable source/reference length"
            (Atomic.get first_invalid));
        let maximum_source = ref 0. and maximum_reference = ref 0. in
        for edge = 0 to edge_count - 1 do
          if all_movable || (match selected_flags with
              | Some flags -> Bytes.unsafe_get flags edge <> '\000'
              | None -> false) then begin
            if source_lengths.(edge) > !maximum_source then
              maximum_source := source_lengths.(edge);
            if reference_lengths.(edge) > !maximum_reference then
              maximum_reference := reference_lengths.(edge)
          end
        done;
        let normalized_mean lengths maximum =
          if maximum = 0. then 0.
          else begin
            let sum = ref 0. in
            for edge = 0 to edge_count - 1 do
              if all_movable || (match selected_flags with
                  | Some flags -> Bytes.unsafe_get flags edge <> '\000'
                  | None -> false) then
                sum := !sum +. lengths.(edge) /. maximum
            done;
            maximum *. (!sum /. float_of_int !selected_count)
          end in
        let scale_factor = match target_mode with
          | Individual_lengths -> 1.
          | Scale_independent_distribution ->
              let source_mean = normalized_mean source_lengths !maximum_source
              and reference_mean = normalized_mean reference_lengths
                  !maximum_reference in
              if reference_mean = 0. then begin
                if source_mean = 0. then 1.
                else fail "Edge Relax cannot normalize a zero-mean reference"
              end else source_mean /. reference_mean in
        if not (Float.is_finite scale_factor) then
          fail "Edge Relax target scale is not representable";
        let targets = reference_lengths and maximum_target = ref 0.
        and maximum_error = ref 0. and maximum_degree = ref 0
        and moves_x = ref false and moves_y = ref false
        and moves_z = ref false in
        for edge = 0 to edge_count - 1 do
          if all_movable || (match selected_flags with
              | Some flags -> Bytes.unsafe_get flags edge <> '\000'
              | None -> false) then begin
            let target = reference_lengths.(edge) *. scale_factor in
            if not (Float.is_finite target) then
              fail "Edge Relax target edge length is not representable";
            targets.(edge) <- target;
            if target > !maximum_target then maximum_target := target;
            let error = source_lengths.(edge) -. target in
            let error = if only_shorten then
                (if error > 0. then error else 0.)
              else abs_float error in
            if error > !maximum_error then maximum_error := error;
            if error > 0. then begin
              let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
              if source_positions.x.(a) <> source_positions.x.(b) then
                moves_x := true;
              if source_positions.y.(a) <> source_positions.y.(b) then
                moves_y := true;
              if source_positions.z.(a) <> source_positions.z.(b) then
                moves_z := true
            end;
            if target > 0. && source_lengths.(edge) = 0.
                && not only_shorten then fail (Printf.sprintf
                  "Edge Relax cannot expand zero-length selected edge %d without a direction"
                  edge)
          end
        done;
        for point = 0 to point_count - 1 do
          let degree = match degrees with
            | Some degrees -> degrees.(point)
            | None -> view.point_edge_offsets.(point + 1)
                - view.point_edge_offsets.(point) in
          if degree > !maximum_degree then maximum_degree := degree
        done;
        let threshold = tolerance *. (if !maximum_source > !maximum_target
          then !maximum_source else !maximum_target) in
        if !maximum_error <= threshold then Ok geometry
        else begin
          let selected edge = all_movable || match selected_flags with
            | Some flags -> Bytes.unsafe_get flags edge <> '\000'
            | None -> false in
          let packed = if !maximum_degree = 1 && step_size <= 0.5 then begin
              let x = if !moves_x then Array.copy source_positions.x
                else source_positions.x
              and y = if !moves_y then Array.copy source_positions.y
                else source_positions.y
              and z = if !moves_z then Array.copy source_positions.z
                else source_positions.z in
              let both_decay = (1. -. (2. *. step_size))
                  ** float_of_int iterations
              and one_decay = (1. -. step_size) ** float_of_int iterations in
              let first_bad = Atomic.make max_int in
              Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(edge_count - 1)
                (fun edge ->
                  if edge land 4095 = 0 then Cancel.check_opt cancel;
                  if selected edge then begin
                    let length = source_lengths.(edge)
                    and target = targets.(edge) in
                    let signed_error = length -. target in
                    if (not only_shorten || signed_error > 0.)
                        && signed_error <> 0. then begin
                      let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
                      let move_a = movable a and move_b = movable b in
                      let final_length = target +. signed_error
                          *. (if move_a && move_b then both_decay else one_decay) in
                      let factor = if length = 0. then 0.
                        else (length -. final_length) /. length
                          /. (if move_a && move_b then 2. else 1.) in
                      let dx = source_positions.x.(b) -. source_positions.x.(a)
                      and dy = source_positions.y.(b) -. source_positions.y.(a)
                      and dz = source_positions.z.(b) -. source_positions.z.(a) in
                      let ax = source_positions.x.(a) +. factor *. dx
                      and ay = source_positions.y.(a) +. factor *. dy
                      and az = source_positions.z.(a) +. factor *. dz
                      and bx = source_positions.x.(b) -. factor *. dx
                      and by = source_positions.y.(b) -. factor *. dy
                      and bz = source_positions.z.(b) -. factor *. dz in
                      if Float.is_finite ax && Float.is_finite ay
                          && Float.is_finite az && Float.is_finite bx
                          && Float.is_finite by && Float.is_finite bz then begin
                        if move_a then begin
                          if !moves_x then x.(a) <- ax;
                          if !moves_y then y.(a) <- ay;
                          if !moves_z then z.(a) <- az
                        end;
                        if move_b then begin
                          if !moves_x then x.(b) <- bx;
                          if !moves_y then y.(b) <- by;
                          if !moves_z then z.(b) <- bz
                        end
                      end else begin
                        let rec record () =
                          let known = Atomic.get first_bad in
                          if edge < known
                              && not (Atomic.compare_and_set first_bad known edge)
                          then record () in
                        record ()
                      end
                    end
                  end);
              if Atomic.get first_bad <> max_int then fail (Printf.sprintf
                  "Edge Relax produced a non-finite point at selected edge %d"
                  (Atomic.get first_bad));
              Packed.Float3.Private.of_shared_exn ~x ~y ~z
            end else begin
              let projected = Edge_constraints.project ?cancel ~grain
                  ~operation:"Edge Relax" ~view ~source:source_positions
                  ~point_count ~selected
                  ~targets:(Edge_constraints.Per_edge targets) ~movable
                  ~maximum_degree:!maximum_degree ~iterations ~step_size
                  ~threshold ~only_shorten () |> function
                | Ok value -> value | Error message -> fail message in
              projected.positions
            end in
          let output = Geometry.with_positions packed geometry
              |> function Ok output -> output | Error message -> fail message in
          Ok (output
            |> Geometry.without_attribute ~owner:Attribute.Point "N"
            |> Geometry.without_attribute ~owner:Attribute.Vertex "N")
        end
      end
    end
  with Relax_error message -> Error message
