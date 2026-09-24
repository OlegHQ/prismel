open Prismel

type frame = { point : Vec3.t; tangent : Vec3.t; normal : Vec3.t; binormal : Vec3.t }

let rotate vector axis angle =
  let cosine = cos angle and sine = sin angle in
  Vec3.add (Vec3.add (Vec3.scale vector cosine)
      (Vec3.scale (Vec3.cross axis vector) sine))
    (Vec3.scale axis (Vec3.dot axis vector *. (1. -. cosine)))

let remove_duplicates points = List.fold_left (fun result point -> match result with
  | previous :: _ when Vec3.distance previous point <= 1e-12 -> result
  | _ -> point :: result) [] points |> List.rev

let frames ?(closed = false) supplied =
  let points = remove_duplicates supplied |> Array.of_list in
  let count = Array.length points in
  if count < (if closed then 3 else 2) then
    Error "Transport3.frames: insufficient distinct path points"
  else
    let tangent index =
      if closed then Vec3.sub points.((index+1) mod count)
          points.((index+count-1) mod count) |> Vec3.normalize
      else if index = 0 then Vec3.sub points.(1) points.(0) |> Vec3.normalize
      else if index = count-1 then Vec3.sub points.(index) points.(index-1) |> Vec3.normalize
      else Vec3.sub points.(index+1) points.(index-1) |> Vec3.normalize in
    let tangents = Array.init count tangent in
    let normals = Array.make count Vec3.zero in
    let reference = if abs_float (Vec3.dot tangents.(0) Vec3.unit_y) < 0.9
      then Vec3.unit_y else Vec3.unit_x in
    normals.(0) <- Vec3.cross reference tangents.(0) |> Vec3.normalize;
    for index = 1 to count-1 do
      let previous = tangents.(index-1) and current = tangents.(index) in
      let axis = Vec3.cross previous current in
      let sine = Vec3.length axis
      and cosine = max (-1.) (min 1. (Vec3.dot previous current)) in
      let transported = if sine <= 1e-12 then normals.(index-1)
        else rotate normals.(index-1) (Vec3.scale axis (1./.sine)) (atan2 sine cosine) in
      normals.(index) <- Vec3.sub transported
          (Vec3.scale current (Vec3.dot transported current)) |> Vec3.normalize
    done;
    if closed then begin
      let previous = tangents.(count-1) and current = tangents.(0) in
      let axis = Vec3.cross previous current in
      let sine = Vec3.length axis and cosine = max (-1.) (min 1. (Vec3.dot previous current)) in
      let returned = if sine <= 1e-12 then normals.(count-1)
        else rotate normals.(count-1) (Vec3.scale axis (1./.sine)) (atan2 sine cosine) in
      let residual = atan2 (Vec3.dot (Vec3.cross returned normals.(0)) tangents.(0))
          (Vec3.dot returned normals.(0)) in
      for index = 1 to count-1 do
        normals.(index) <- rotate normals.(index) tangents.(index)
            (residual *. float_of_int index /. float_of_int count)
      done
    end;
    Ok (List.init count (fun index ->
      let normal = normals.(index) in
      { point = points.(index); tangent = tangents.(index); normal;
        binormal = Vec3.cross tangents.(index) normal |> Vec3.normalize }))

let sweep_point frame point =
  Vec3.add frame.point (Vec3.add (Vec3.scale frame.normal point.Vec2.x)
    (Vec3.scale frame.binormal point.y))
let sweep_profile frame profile = Polygon2.vertices profile |> List.map (sweep_point frame)
