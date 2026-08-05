open Prismel

type facet = {
  index : int;
  world : Triangle3.t;
  projected : Polygon2.t;
  normal : Vec3.t;
  center : Vec3.t;
  depth : float;
}

type shader = facet -> Color.t

let lambert ?(ambient = 0.15) ~light_direction ~base =
  if not (Float.is_finite ambient) || ambient < 0. || ambient > 1. then
    invalid_arg "Svg3.lambert: ambient must be in zero to one";
  let light = Vec3.normalize light_direction in
  fun facet ->
    let diffuse = max 0. (Vec3.dot facet.normal light) in
    let amount = min 1. (ambient +. (1. -. ambient) *. diffuse) in
    Color.blend Color.black base ~pct:amount

let mesh ?(transform = Mat4.identity) ?(cull_backfaces = true) ?stroke
    ?stroke_width ?(shader = lambert ~ambient:0.15
      ~light_direction:(Vec3.create 0.3 0.6 1.)
      ~base:(Color.rgb 190 205 225)) ~viewport ~camera mesh =
  let mesh = Mesh.transformed transform mesh in
  let facets = Mesh.faces mesh |> List.mapi (fun index (face : Mesh.face) ->
    let a,b,c = face.points in
    let triangle = Triangle3.make a b c in
    let center = Triangle3.centroid triangle and normal = Triangle3.normal triangle in
    let visible = not cull_backfaces ||
      Vec3.dot normal (Vec3.sub (Camera.position camera) center) > 0. in
    if not visible then None
    else match Camera.world_to_screen ~viewport camera a,
               Camera.world_to_screen ~viewport camera b,
               Camera.world_to_screen ~viewport camera c with
      | Some pa, Some pb, Some pc ->
          let projected = Polygon2.create_exn
              [Vec3.to_vec2 pa; Vec3.to_vec2 pb; Vec3.to_vec2 pc] in
          Some { index; world = triangle; projected; normal; center;
            depth = (pa.z +. pb.z +. pc.z) /. 3. }
      | _ -> None)
    |> List.filter_map Fun.id
    |> List.sort (fun left right -> Float.compare right.depth left.depth) in
  Svg.group (List.map (fun facet ->
    let attrs = Svg.style ~fill:(shader facet) ?stroke ?stroke_width () in
    Svg.polygon ~attrs facet.projected) facets)
