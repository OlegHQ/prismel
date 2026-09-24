type scratch = {
  mutable u : float array;
  mutable v : float array;
  mutable remaining : int array;
  accumulators : float array;
}

let create_scratch () = {
  u = [||]; v = [||]; remaining = [||]; accumulators = Array.make 5 0.;
}

let ensure scratch size =
  if Array.length scratch.u < size then begin
    let rec capacity value = if value >= size then value else capacity (value * 2) in
    let capacity = capacity (max 4 (Array.length scratch.u)) in
    scratch.u <- Array.make capacity 0.;
    scratch.v <- Array.make capacity 0.;
    scratch.remaining <- Array.make capacity 0
  end

let[@inline] cross u v orientation a b c =
  (((u.(b) -. u.(a)) *. (v.(c) -. v.(a)))
   -. ((v.(b) -. v.(a)) *. (u.(c) -. u.(a)))) *. orientation

let[@inline] contains u v orientation a b c point =
  cross u v orientation a b point >= -.1e-12
  && cross u v orientation b c point >= -.1e-12
  && cross u v orientation c a point >= -.1e-12

let primitive ?cancel ~(positions : Packed.Float3.Private.view)
    ~(topology : Topology.Private.view) ?scratch primitive ~emit =
  let first = topology.Topology.Private.primitive_offsets.(primitive)
  and last = topology.primitive_offsets.(primitive + 1) in
  let size = last - first in
  if Bytes.get topology.primitive_kinds primitive <> '\000' then
    Error (Printf.sprintf "primitive %d is a curve, not a polygon" primitive)
  else if size < 3 then
    Error (Printf.sprintf "primitive %d has fewer than three corners" primitive)
  else if size = 3 then begin
    emit 0 first (first + 1) (first + 2);
    Ok ()
  end else begin
    let scratch = match scratch with Some value -> value | None -> create_scratch () in
    ensure scratch size;
    let sums = scratch.accumulators in
    Array.fill sums 0 (Array.length sums) 0.;
    sums.(4) <- 1.;
    for local = 0 to size - 1 do
      if local land 4095 = 0 then Cancel.check_opt cancel;
      let next = (local + 1) mod size in
      let pi = topology.vertex_points.(first + local)
      and pj = topology.vertex_points.(first + next) in
      let xi = positions.x.(pi) and yi = positions.y.(pi) and zi = positions.z.(pi)
      and xj = positions.x.(pj) and yj = positions.y.(pj) and zj = positions.z.(pj) in
      if not (Float.is_finite xi && Float.is_finite yi && Float.is_finite zi
          && Float.is_finite xj && Float.is_finite yj && Float.is_finite zj) then
        sums.(4) <- 0.
      else begin
        sums.(0) <- sums.(0) +. ((yi -. yj) *. (zi +. zj));
        sums.(1) <- sums.(1) +. ((zi -. zj) *. (xi +. xj));
        sums.(2) <- sums.(2) +. ((xi -. xj) *. (yi +. yj))
      end
    done;
    if sums.(4) = 0. then Error (Printf.sprintf
        "primitive %d has a non-finite position" primitive)
    else
        let ax = abs_float sums.(0) and ay = abs_float sums.(1)
        and az = abs_float sums.(2) in
        let dominant = if ax >= ay && ax >= az then 0 else if ay >= az then 1 else 2 in
        let u = scratch.u and v = scratch.v in
        for local = 0 to size - 1 do
          let point = topology.vertex_points.(first + local) in
          if dominant = 0 then begin
            u.(local) <- positions.y.(point); v.(local) <- positions.z.(point)
          end else if dominant = 1 then begin
            u.(local) <- positions.x.(point); v.(local) <- positions.z.(point)
          end else begin
            u.(local) <- positions.x.(point); v.(local) <- positions.y.(point)
          end
        done;
        sums.(3) <- 0.;
        for local = 0 to size - 1 do
          let next = (local + 1) mod size in
          sums.(3) <- sums.(3)
            +. ((u.(local) *. v.(next)) -. (u.(next) *. v.(local)))
        done;
        if not (Float.is_finite sums.(3)) || abs_float sums.(3) <= 1e-14 then
          Error (Printf.sprintf "primitive %d has degenerate projected area" primitive)
        else begin
          let orientation = if sums.(3) > 0. then 1. else -1. in
          let remaining = scratch.remaining in
          for local = 0 to size - 1 do remaining.(local) <- local done;
          let rec clip active emitted =
            if active = 3 then begin
              emit emitted (first + remaining.(0)) (first + remaining.(1))
                (first + remaining.(2));
              Ok ()
            end else begin
            Cancel.check_opt cancel;
            let rec find_ear slot =
              if slot = active then -1
              else
              let a = remaining.((slot + active - 1) mod active)
              and b = remaining.(slot)
              and c = remaining.((slot + 1) mod active) in
              if cross u v orientation a b c <= 1e-12 then find_ear (slot + 1)
              else
                let rec blocked other_slot =
                  if other_slot = active then false
                  else
                    let point = remaining.(other_slot) in
                    if point <> a && point <> b && point <> c
                       && contains u v orientation a b c point then true
                    else blocked (other_slot + 1) in
                if blocked 0 then find_ear (slot + 1) else slot in
            let ear = find_ear 0 in
            if ear < 0 then Error (Printf.sprintf
                "primitive %d is non-simple or degenerate" primitive)
            else
              let a = remaining.((ear + active - 1) mod active)
              and b = remaining.(ear)
              and c = remaining.((ear + 1) mod active) in
              emit emitted (first + a) (first + b) (first + c);
              Array.blit remaining (ear + 1) remaining ear (active - ear - 1);
              clip (active - 1) (emitted + 1)
            end
          in
          clip size 0
        end
  end
