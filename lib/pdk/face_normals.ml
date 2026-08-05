open Prismel

let selected selection primitive = match selection with
  | None -> true
  | Some group -> Group.mem primitive group

let compute ?cancel ?(grain = 16_384) ?primitives ~operation geometry =
  if grain <= 0 then Error (operation ^ ": grain must be positive")
  else
    let topology = Geometry.topology geometry in
    let primitive_count = Topology.primitive_count topology in
    match primitives with
    | Some group when Group.owner group <> Group.Primitive ->
        Error (operation ^ ": selection must own primitives")
    | Some group when Group.length group <> primitive_count ->
        Error (operation ^ ": selection length does not match primitive count")
    | _ ->
        let topology_view = Topology.Private.view topology
        and positions = Packed.Float3.Private.view (Geometry.positions geometry) in
        let nx = Array.make primitive_count 0.
        and ny = Array.make primitive_count 0.
        and nz = Array.make primitive_count 0. in
        let invalid = Atomic.make false in
        if primitive_count > 0 then
          Parallel.for_ ~chunk_size:grain ~start:0 ~finish:(primitive_count - 1)
            (fun primitive ->
              if primitive land 16_383 = 0 then Cancel.check_opt cancel;
              if selected primitives primitive then begin
                if Topology.primitive_kind topology primitive <> Topology.Polygon then
                  Atomic.set invalid true
                else begin
                  let first = topology_view.primitive_offsets.(primitive)
                  and last = topology_view.primitive_offsets.(primitive + 1) in
                  let first_point = topology_view.vertex_points.(first) in
                  let ax = positions.x.(first_point)
                  and ay = positions.y.(first_point)
                  and az = positions.z.(first_point) in
                  for vertex = first + 1 to last - 2 do
                    if vertex land 16_383 = 0 then Cancel.check_opt cancel;
                    let b = topology_view.vertex_points.(vertex)
                    and c = topology_view.vertex_points.(vertex + 1) in
                    let ux = positions.x.(b) -. ax
                    and uy = positions.y.(b) -. ay
                    and uz = positions.z.(b) -. az
                    and vx = positions.x.(c) -. ax
                    and vy = positions.y.(c) -. ay
                    and vz = positions.z.(c) -. az in
                    nx.(primitive) <- nx.(primitive) +. uy *. vz -. uz *. vy;
                    ny.(primitive) <- ny.(primitive) +. uz *. vx -. ux *. vz;
                    nz.(primitive) <- nz.(primitive) +. ux *. vy -. uy *. vx
                  done;
                  let x = nx.(primitive) and y = ny.(primitive)
                  and z = nz.(primitive) in
                  let scale = abs_float x in
                  let scale = if abs_float y > scale then abs_float y else scale in
                  let scale = if abs_float z > scale then abs_float z else scale in
                  if scale = 0. || not (Float.is_finite x && Float.is_finite y
                      && Float.is_finite z) then Atomic.set invalid true
                  else begin
                    let x = x /. scale and y = y /. scale and z = z /. scale in
                    let inverse = 1. /. sqrt (x *. x +. y *. y +. z *. z) in
                    nx.(primitive) <- x *. inverse;
                    ny.(primitive) <- y *. inverse;
                    nz.(primitive) <- z *. inverse
                  end
                end
              end);
        if Atomic.get invalid then Error (operation
            ^ ": selected primitives must be finite non-degenerate polygons")
        else Ok (nx, ny, nz)
