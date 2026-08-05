open Prismel

type projection = {
  positions : Packed.Float3.t;
  converged : bool;
}

type targets = Constant of float | Per_edge of float array

exception Projection_error of string

let[@inline always] maximum_abs left right =
  let left = abs_float left and right = abs_float right in
  if left > right then left else right

let[@inline always] length dx dy dz =
  let scale = maximum_abs dx dy in
  let scale = maximum_abs scale dz in
  if scale = 0. then 0.
  else scale *. sqrt
      ((dx /. scale) ** 2. +. (dy /. scale) ** 2. +. (dz /. scale) ** 2.)

let project ?cancel ~grain ~operation ~view ~source ~point_count ~selected
    ~targets ~movable ~maximum_degree ~iterations ~step_size ~threshold
    ~only_shorten () =
  try
    let current_x = ref (Array.copy source.Packed.Float3.Private.x)
    and current_y = ref (Array.copy source.y)
    and current_z = ref (Array.copy source.z)
    and next_x = ref (Array.copy source.x)
    and next_y = ref (Array.copy source.y)
    and next_z = ref (Array.copy source.z) in
    let denominator = float_of_int maximum_degree
    and converged = ref false and iteration = ref 0 in
    while !iteration < iterations && not !converged do
      let first_bad = Atomic.make max_int in
      if point_count > 0 then Parallel.for_ ~chunk_size:grain ~start:0
          ~finish:(point_count - 1) (fun point ->
        if point land 4095 = 0 then Cancel.check_opt cancel;
        if not (movable point) then begin
          (!next_x).(point) <- (!current_x).(point);
          (!next_y).(point) <- (!current_y).(point);
          (!next_z).(point) <- (!current_z).(point)
        end else begin
          (!next_x).(point) <- (!current_x).(point);
          (!next_y).(point) <- (!current_y).(point);
          (!next_z).(point) <- (!current_z).(point);
          let first = view.Topology_index.Private.point_edge_offsets.(point)
          and last = view.point_edge_offsets.(point + 1) in
          for at = first to last - 1 do
            let edge = view.point_edges.(at) in
            if selected edge then begin
              let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
              let other = if a = point then b else a in
              let dx = (!current_x).(other) -. (!current_x).(point)
              and dy = (!current_y).(other) -. (!current_y).(point)
              and dz = (!current_z).(other) -. (!current_z).(point) in
              let edge_length = length dx dy dz in
              if edge_length > 0. then begin
                let target = match targets with
                  | Constant target -> target
                  | Per_edge targets -> Array.unsafe_get targets edge in
                let error = edge_length -. target in
                if not only_shorten || error > 0. then begin
                  let factor = step_size *. error /. edge_length /. denominator in
                  (!next_x).(point) <- (!next_x).(point) +. factor *. dx;
                  (!next_y).(point) <- (!next_y).(point) +. factor *. dy;
                  (!next_z).(point) <- (!next_z).(point) +. factor *. dz
                end
              end
            end
          done;
          let x = (!next_x).(point) and y = (!next_y).(point)
          and z = (!next_z).(point) in
          if Float.is_finite x && Float.is_finite y && Float.is_finite z then
            begin
              (!next_x).(point) <- x;
              (!next_y).(point) <- y;
              (!next_z).(point) <- z
            end
          else begin
            let rec record () =
              let known = Atomic.get first_bad in
              if point < known
                  && not (Atomic.compare_and_set first_bad known point) then
                record () in
            record ()
          end
        end);
      if Atomic.get first_bad <> max_int then raise (Projection_error
          (Printf.sprintf "%s produced non-finite point %d" operation
             (Atomic.get first_bad)));
      let swap left right = let old = !left in left := !right; right := old in
      swap current_x next_x; swap current_y next_y; swap current_z next_z;
      incr iteration;
      let maximum_error = ref 0. in
      for edge = 0 to Array.length view.edge_a - 1 do
        if selected edge then begin
          let a = view.edge_a.(edge) and b = view.edge_b.(edge) in
          let edge_length = length
              ((!current_x).(b) -. (!current_x).(a))
              ((!current_y).(b) -. (!current_y).(a))
              ((!current_z).(b) -. (!current_z).(a)) in
          let target = match targets with
            | Constant target -> target
            | Per_edge targets -> Array.unsafe_get targets edge in
          let error = edge_length -. target in
          let error = if only_shorten then
              (if error > 0. then error else 0.)
            else abs_float error in
          if error > !maximum_error then maximum_error := error
        end
      done;
      converged := !maximum_error <= threshold
    done;
    Ok { positions = Packed.Float3.Private.of_owned_exn
        ~x:!current_x ~y:!current_y ~z:!current_z;
      converged = !converged }
  with Projection_error message -> Error message
