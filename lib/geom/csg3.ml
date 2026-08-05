open Prismel

type vertex = {
  position : Vec3.t;
  normal : Vec3.t;
  color : Color.t option;
  uv : Vec2.t option;
}

type plane = { normal : Vec3.t; offset : float }
type polygon = { vertices : vertex list; plane : plane }

type node = {
  mutable plane : plane option;
  mutable polygons : polygon list;
  mutable front : node option;
  mutable back : node option;
}

let empty_node () = { plane = None; polygons = []; front = None; back = None }

let interpolate_vertex left right amount =
  {
    position = Vec3.lerp left.position right.position amount;
    normal = Vec3.lerp left.normal right.normal amount |> Vec3.normalize;
    color = (match left.color, right.color with
      | Some left, Some right -> Some (Color.blend left right ~pct:amount)
      | _ -> None);
    uv = (match left.uv, right.uv with
      | Some left, Some right -> Some (Vec2.lerp left right amount)
      | _ -> None);
  }

let plane_of_vertices = function
  | first :: second :: third :: _ ->
      let abx = second.position.x -. first.position.x
      and aby = second.position.y -. first.position.y
      and abz = second.position.z -. first.position.z
      and acx = third.position.x -. first.position.x
      and acy = third.position.y -. first.position.y
      and acz = third.position.z -. first.position.z in
      let nx = (aby *. acz) -. (abz *. acy)
      and ny = (abz *. acx) -. (abx *. acz)
      and nz = (abx *. acy) -. (aby *. acx) in
      let length_sq = (nx *. nx) +. (ny *. ny) +. (nz *. nz) in
      if length_sq <= 1e-20 then None
      else
        let inverse_length = 1. /. sqrt length_sq in
        let normal =
          Vec3.create (nx *. inverse_length) (ny *. inverse_length)
            (nz *. inverse_length)
        in
        Some {
          normal;
          offset =
            (normal.x *. first.position.x)
            +. (normal.y *. first.position.y)
            +. (normal.z *. first.position.z);
        }
  | _ -> None

let make_polygon vertices =
  Option.map (fun plane -> { vertices; plane }) (plane_of_vertices vertices)

let flip_vertex (vertex : vertex) =
  { vertex with normal = Vec3.neg vertex.normal }
let flip_plane (plane : plane) =
  { normal = Vec3.neg plane.normal; offset = -.plane.offset }
let flip_polygon (polygon : polygon) =
  { vertices = List.rev_map flip_vertex polygon.vertices;
    plane = flip_plane polygon.plane }

type split_result =
  | Coplanar_front
  | Coplanar_back
  | In_front
  | Behind
  | Spanning of polygon option * polygon option

let classify epsilon (splitter : plane) vertex =
    let distance =
      (splitter.normal.x *. vertex.position.x)
      +. (splitter.normal.y *. vertex.position.y)
      +. (splitter.normal.z *. vertex.position.z)
      -. splitter.offset
    in
    if distance < -.epsilon then -1 else if distance > epsilon then 1 else 0

let rec classify_polygon epsilon splitter result = function
  | [] -> result
  | vertex :: rest ->
      let kind = classify epsilon splitter vertex in
      classify_polygon epsilon splitter
        (result lor if kind < 0 then 2 else kind)
        rest

let split_polygon epsilon (splitter : plane) (polygon : polygon) =
  let polygon_type = classify_polygon epsilon splitter 0 polygon.vertices in
  match polygon_type with
  | 0 ->
      if
        (splitter.normal.x *. polygon.plane.normal.x)
        +. (splitter.normal.y *. polygon.plane.normal.y)
        +. (splitter.normal.z *. polygon.plane.normal.z) > 0.
      then Coplanar_front
      else Coplanar_back
  | 1 -> In_front
  | 2 -> Behind
  | _ ->
      let front_vertices = ref [] and back_vertices = ref [] in
      let edge current_vertex next_vertex =
        let current_kind = classify epsilon splitter current_vertex
        and next_kind = classify epsilon splitter next_vertex in
        if current_kind >= 0 then front_vertices := current_vertex :: !front_vertices;
        if current_kind <= 0 then back_vertices := current_vertex :: !back_vertices;
        if (current_kind = 1 && next_kind = -1) || (current_kind = -1 && next_kind = 1) then begin
          let denominator =
            (splitter.normal.x
             *. (next_vertex.position.x -. current_vertex.position.x))
            +. (splitter.normal.y
                *. (next_vertex.position.y -. current_vertex.position.y))
            +. (splitter.normal.z
                *. (next_vertex.position.z -. current_vertex.position.z))
          in
          let projected =
            (splitter.normal.x *. current_vertex.position.x)
            +. (splitter.normal.y *. current_vertex.position.y)
            +. (splitter.normal.z *. current_vertex.position.z)
          in
          let amount = (splitter.offset -. projected) /. denominator in
          let vertex = interpolate_vertex current_vertex next_vertex amount in
          front_vertices := vertex :: !front_vertices;
          back_vertices := vertex :: !back_vertices
        end
      in
      (match polygon.vertices with
       | [] -> ()
       | first :: rest ->
           let rec visit current = function
             | next :: tail -> edge current next; visit next tail
             | [] -> edge current first
           in
           visit first rest);
      Spanning
        ( make_polygon (List.rev !front_vertices),
          make_polygon (List.rev !back_vertices) )

let rec insert_polygon epsilon (node : node) (polygon : polygon) =
  match node.plane with
  | None ->
      node.plane <- Some polygon.plane;
      node.polygons <- [polygon]
  | Some splitter ->
      match split_polygon epsilon splitter polygon with
      | Coplanar_front | Coplanar_back ->
          node.polygons <- polygon :: node.polygons
      | In_front -> insert_child epsilon node true polygon
      | Behind -> insert_child epsilon node false polygon
      | Spanning (front, back) ->
          (match front with
           | Some polygon -> insert_child epsilon node true polygon
           | None -> ());
          (match back with
           | Some polygon -> insert_child epsilon node false polygon
           | None -> ())

and insert_child epsilon node in_front polygon =
  let child = if in_front then node.front else node.back in
  match child with
  | Some child -> insert_polygon epsilon child polygon
  | None ->
      let child = empty_node () in
      if in_front then node.front <- Some child else node.back <- Some child;
      insert_polygon epsilon child polygon

let build epsilon node polygons =
  List.iter (insert_polygon epsilon node) polygons

let all_polygons node =
  let output = ref [] in
  let pending = Stack.create () in
  Stack.push node pending;
  while not (Stack.is_empty pending) do
    let node = Stack.pop pending in
    List.iter (fun polygon -> output := polygon :: !output) node.polygons;
    (match node.back with Some child -> Stack.push child pending | None -> ());
    (match node.front with Some child -> Stack.push child pending | None -> ())
  done;
  List.rev !output

let invert node =
  let pending = Stack.create () in
  Stack.push node pending;
  while not (Stack.is_empty pending) do
    let node = Stack.pop pending in
    node.polygons <- List.map flip_polygon node.polygons;
    node.plane <- Option.map flip_plane node.plane;
    (match node.front with Some child -> Stack.push child pending | None -> ());
    (match node.back with Some child -> Stack.push child pending | None -> ());
    let front = node.front in
    node.front <- node.back;
    node.back <- front
  done

let rec clip_polygon epsilon (node : node) polygon output =
  match node.plane with
  | None -> polygon :: output
  | Some splitter ->
      match split_polygon epsilon splitter polygon with
      | Coplanar_front | In_front ->
          (match node.front with
           | None -> polygon :: output
           | Some child -> clip_polygon epsilon child polygon output)
      | Coplanar_back | Behind ->
          (match node.back with
           | None -> output
           | Some child -> clip_polygon epsilon child polygon output)
      | Spanning (front, back) ->
          let output =
            match back, node.back with
            | Some polygon, Some child ->
                clip_polygon epsilon child polygon output
            | _ -> output
          in
          (match front, node.front with
           | Some polygon, Some child ->
               clip_polygon epsilon child polygon output
           | Some polygon, None -> polygon :: output
           | None, _ -> output)

let clip_polygons epsilon node polygons =
  List.fold_left
    (fun output polygon -> clip_polygon epsilon node polygon output)
    [] polygons

let clip_to epsilon node other =
  let pending = Stack.create () in
  Stack.push node pending;
  while not (Stack.is_empty pending) do
    let node = Stack.pop pending in
    node.polygons <- clip_polygons epsilon other node.polygons;
    (match node.front with Some child -> Stack.push child pending | None -> ());
    (match node.back with Some child -> Stack.push child pending | None -> ())
  done

let polygons_of_mesh mesh =
  let view = Mesh.Private.view mesh in
  let polygons = ref [] in
  Mesh.Private.iter_triangles (fun ia ib ic ->
    let a = view.vertices.(ia) and b = view.vertices.(ib)
    and c = view.vertices.(ic) in
    let geometric_normal =
      match view.normals with
      | Some _ -> Vec3.zero
      | None -> Vec3.cross (Vec3.sub b a) (Vec3.sub c a) |> Vec3.normalize in
    let normal index = match view.normals with
      | Some values -> values.(index)
      | None -> geometric_normal in
    let color index = Option.map (fun values -> values.(index)) view.colors
    and uv index = Option.map (fun values -> values.(index)) view.tex_coords in
    Option.iter (fun polygon -> polygons := polygon :: !polygons)
      (make_polygon [
         { position = a; normal = normal ia; color = color ia; uv = uv ia };
         { position = b; normal = normal ib; color = color ib; uv = uv ib };
         { position = c; normal = normal ic; color = color ic; uv = uv ic };
       ])) mesh;
  List.rev !polygons

let node_of_polygons epsilon polygons =
  let node = empty_node () in
  build epsilon node polygons;
  node

let mesh_of_polygons polygons =
  let vertex_count = List.fold_left (fun total polygon ->
      total + (max 0 (List.length polygon.vertices - 2) * 3)) 0 polygons in
  if vertex_count = 0 then Error "CSG result is empty"
  else begin
    let has_colors = List.for_all (fun polygon ->
        List.for_all (fun vertex -> Option.is_some vertex.color)
          polygon.vertices) polygons
    and has_tex_coords = List.for_all (fun polygon ->
        List.for_all (fun vertex -> Option.is_some vertex.uv)
          polygon.vertices) polygons in
    let positions = Array.make vertex_count Vec3.zero
    and normals = Array.make vertex_count Vec3.zero
    and colors = if has_colors then Some (Array.make vertex_count Color.white)
      else None
    and tex_coords = if has_tex_coords then Some (Array.make vertex_count Vec2.zero)
      else None in
    let output = ref 0 in
    let emit vertex =
      positions.(!output) <- vertex.position;
      normals.(!output) <- vertex.normal;
      (match colors, vertex.color with
       | Some values, Some color -> values.(!output) <- color
       | _ -> ());
      (match tex_coords, vertex.uv with
       | Some values, Some uv -> values.(!output) <- uv
       | _ -> ());
      incr output in
    List.iter (fun polygon -> match polygon.vertices with
      | first :: second :: rest ->
          let previous = ref second in
          List.iter (fun current ->
            emit first; emit !previous; emit current;
            previous := current) rest
      | _ -> ()) polygons;
    assert (!output = vertex_count);
    Mesh.Private.create_owned ~mode:Mesh.Triangles ~normals
      ?colors ?tex_coords positions
  end

let validate epsilon left right =
  if not (Float.is_finite epsilon) || epsilon <= 0. then invalid_arg "Csg3: epsilon must be finite and positive";
  let left = polygons_of_mesh left and right = polygons_of_mesh right in
  if left = [] || right = [] then Error "Csg3: both inputs must contain non-degenerate triangles"
  else Ok (left, right)

let union ?(epsilon = 1e-5) left right =
  Result.bind (validate epsilon left right) (fun (left, right) ->
    let a = node_of_polygons epsilon left and b = node_of_polygons epsilon right in
    clip_to epsilon a b;
    clip_to epsilon b a;
    invert b;
    clip_to epsilon b a;
    invert b;
    build epsilon a (all_polygons b);
    mesh_of_polygons (all_polygons a))

let difference ?(epsilon = 1e-5) left right =
  Result.bind (validate epsilon left right) (fun (left, right) ->
    let a = node_of_polygons epsilon left and b = node_of_polygons epsilon right in
    invert a;
    clip_to epsilon a b;
    clip_to epsilon b a;
    invert b;
    clip_to epsilon b a;
    invert b;
    build epsilon a (all_polygons b);
    invert a;
    mesh_of_polygons (all_polygons a))

let intersection ?(epsilon = 1e-5) left right =
  Result.bind (validate epsilon left right) (fun (left, right) ->
    let a = node_of_polygons epsilon left and b = node_of_polygons epsilon right in
    invert a;
    clip_to epsilon b a;
    invert b;
    clip_to epsilon a b;
    clip_to epsilon b a;
    build epsilon a (all_polygons b);
    invert a;
    mesh_of_polygons (all_polygons a))
