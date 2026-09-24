open Prismel

let validate_positive name value =
  if not (Float.is_finite value) || value <= 0. then
    invalid_arg ("Mesh3." ^ name ^ ": value must be finite and positive")

let mesh_with_normals_owned ?(angle = Float.pi /. 3.) ?tex_coords
    vertices indices =
  Mesh.Private.create_owned ~mode:Mesh.Triangles ~indices ?tex_coords vertices
  |> Result.map (Mesh.smooth_normals ~angle)

let point_index_table points =
  let table = Hashtbl.create (Array.length points) in
  Array.iteri
    (fun index point -> Hashtbl.replace table (point.Vec2.x, point.y) index)
    points;
  fun point ->
    match Hashtbl.find_opt table (point.Vec2.x, point.y) with
    | Some index -> index
    | None -> failwith "Mesh3: tessellator returned an unknown vertex"

let extrude ?(centered = true) ?(capped = true) ~depth polygon =
  validate_positive "extrude depth" depth;
  let polygon =
    if Polygon2.clockwise polygon then Polygon2.reverse polygon else polygon
  in
  let points = Array.of_list (Polygon2.vertices polygon) in
  let count = Array.length points in
  let back_z, front_z =
    if centered then -.depth /. 2., depth /. 2.
    else 0., depth
  in
  let vertices =
    Array.init (count * 2) (fun index ->
      let point = points.(index mod count) in
      Vec3.create point.x point.y
        (if index < count then back_z else front_z))
  in
  let side_indices = Array.make (count * 6) 0 in
  for index = 0 to count - 1 do
    let next = (index + 1) mod count in
    let offset = (count - index - 1) * 6 in
    side_indices.(offset) <- index;
    side_indices.(offset + 1) <- next;
    side_indices.(offset + 2) <- next + count;
    side_indices.(offset + 3) <- index;
    side_indices.(offset + 4) <- next + count;
    side_indices.(offset + 5) <- index + count
  done;
  let cap_indices =
    if not capped then Ok [||]
    else
      Polygon2.triangulate polygon
      |> Result.map (fun triangles ->
        let triangles = Array.of_list triangles in
        let index_of = point_index_table points in
        let result = Array.make (Array.length triangles * 6) 0 in
        Array.iteri
          (fun triangle (a, b, c) ->
            let a = index_of a and b = index_of b and c = index_of c in
            let offset = (Array.length triangles - triangle - 1) * 6 in
            (* Back faces -Z; front faces +Z. *)
            result.(offset) <- c;
            result.(offset + 1) <- b;
            result.(offset + 2) <- a;
            result.(offset + 3) <- a + count;
            result.(offset + 4) <- b + count;
            result.(offset + 5) <- c + count)
          triangles;
        result)
  in
  Result.bind cap_indices (fun caps ->
    let indices = Array.make (Array.length side_indices + Array.length caps) 0 in
    Array.blit side_indices 0 indices 0 (Array.length side_indices);
    Array.blit caps 0 indices (Array.length side_indices) (Array.length caps);
    Mesh.Private.create_owned ~mode:Mesh.Triangles ~indices vertices
    |> Result.map Mesh.flat_shaded)

let lathe ?(segments = 48) ?(capped = false) profile =
  if segments < 3 then
    invalid_arg "Mesh3.lathe: segments must be at least three";
  let profile_points = Array.of_list (Curve2.points profile) in
  if
    Array.exists
      (fun point ->
        not (Float.is_finite point.Vec2.x)
        || not (Float.is_finite point.y)
        || point.x < 0.)
      profile_points
  then Error "Mesh3.lathe: profile radii must be finite and non-negative"
  else
    let profile_count = Array.length profile_points in
    let profile_spans =
      if Curve2.closed profile then profile_count else profile_count - 1
    in
    let ring_vertex sector point_index =
      (sector mod segments * profile_count) + point_index
    in
    let base_vertex_count = segments * profile_count in
    let cap_vertex_count =
      if capped && not (Curve2.closed profile) then 2 else 0 in
    let vertices =
      Array.init (base_vertex_count + cap_vertex_count) (fun index ->
        if index >= base_vertex_count then
          let point =
            if index = base_vertex_count then profile_points.(0)
            else profile_points.(profile_count - 1) in
          Vec3.create 0. point.y 0.
        else
        let sector = index / profile_count
        and point = profile_points.(index mod profile_count) in
        let angle =
          float_of_int sector /. float_of_int segments
          *. 2. *. Float.pi
        in
        Vec3.create
          (point.x *. cos angle)
          point.y
          (point.x *. sin angle))
    in
    let tex_coords =
      Array.init (base_vertex_count + cap_vertex_count) (fun index ->
        if index >= base_vertex_count then
          Vec2.create 0.5 (if index = base_vertex_count then 0. else 1.)
        else
        let sector = index / profile_count
        and point_index = index mod profile_count in
        Vec2.create
          (float_of_int sector /. float_of_int segments)
          (if profile_count = 1 then 0.
           else
             float_of_int point_index
             /. float_of_int (profile_count - 1)))
    in
    let side_quad_count = segments * profile_spans in
    let cap_index_count = if cap_vertex_count = 0 then 0 else segments * 6 in
    let indices = Array.make ((side_quad_count * 6) + cap_index_count) 0 in
    for sector = 0 to segments - 1 do
      for point_index = 0 to profile_spans - 1 do
        let next_point = (point_index + 1) mod profile_count in
        let a = ring_vertex sector point_index
        and b = ring_vertex sector next_point
        and c = ring_vertex (sector + 1) next_point
        and d = ring_vertex (sector + 1) point_index in
        let quad = (sector * profile_spans) + point_index in
        let offset = (side_quad_count - quad - 1) * 6 in
        indices.(offset) <- a;
        indices.(offset + 1) <- b;
        indices.(offset + 2) <- c;
        indices.(offset + 3) <- a;
        indices.(offset + 4) <- c;
        indices.(offset + 5) <- d
      done
    done;
    if cap_vertex_count <> 0 then begin
        let bottom = base_vertex_count and top = base_vertex_count + 1 in
        for sector = 0 to segments - 1 do
          let next = (sector + 1) mod segments in
          let offset = (side_quad_count * 6) + ((segments - sector - 1) * 6) in
          (* Angular order faces -Y, so reverse the upper cap. *)
          indices.(offset) <- bottom;
          indices.(offset + 1) <- ring_vertex sector 0;
          indices.(offset + 2) <- ring_vertex next 0;
          indices.(offset + 3) <- top;
          indices.(offset + 4) <- ring_vertex next (profile_count - 1);
          indices.(offset + 5) <- ring_vertex sector (profile_count - 1)
        done
      end;
    mesh_with_normals_owned ~tex_coords vertices indices

let finite_vec3 point =
  Float.is_finite point.Vec3.x
  && Float.is_finite point.y
  && Float.is_finite point.z

let remove_consecutive_duplicate_vec3 points =
  List.fold_left
    (fun result point ->
      match result with
      | previous :: _ when Vec3.distance previous point <= 1e-12 -> result
      | _ -> point :: result)
    [] points
  |> List.rev

let rotate_around_axis vector axis cosine sine =
  let cross = Vec3.cross axis vector
  and projection = Vec3.dot axis vector in
  Vec3.add
    (Vec3.add
       (Vec3.scale vector cosine)
       (Vec3.scale cross sine))
    (Vec3.scale axis (projection *. (1. -. cosine)))

let spine_tangents spine =
  let count = Array.length spine in
  Array.init count (fun index ->
    if index = 0 then Vec3.sub spine.(1) spine.(0) |> Vec3.normalize
    else if index = count - 1 then
      Vec3.sub spine.(count - 1) spine.(count - 2) |> Vec3.normalize
    else
      Vec3.sub spine.(index + 1) spine.(index - 1) |> Vec3.normalize)

let transport_frames tangents =
  let count = Array.length tangents in
  let normals = Array.make count Vec3.zero
  and binormals = Array.make count Vec3.zero in
  let reference =
    if abs_float (Vec3.dot tangents.(0) Vec3.unit_y) < 0.9
    then Vec3.unit_y else Vec3.unit_x
  in
  normals.(0) <- Vec3.cross reference tangents.(0) |> Vec3.normalize;
  binormals.(0) <- Vec3.cross tangents.(0) normals.(0) |> Vec3.normalize;
  for index = 1 to count - 1 do
    let previous = tangents.(index - 1)
    and current = tangents.(index) in
    let axis = Vec3.cross previous current in
    let sine = Vec3.length axis
    and cosine =
      Vec3.dot previous current |> Float.max (-1.) |> Float.min 1.
    in
    let transported =
      if sine <= 1e-12 then normals.(index - 1)
      else
        rotate_around_axis normals.(index - 1)
          (Vec3.scale axis (1. /. sine)) cosine sine
    in
    let normal =
      Vec3.sub transported
        (Vec3.scale current (Vec3.dot transported current))
      |> Vec3.normalize
    in
    normals.(index) <- normal;
    binormals.(index) <- Vec3.cross current normal |> Vec3.normalize
  done;
  normals, binormals

let sweep ?(capped = true) ?(smooth_angle = Float.pi /. 3.)
    ~profile ~spine () =
  if
    not (Float.is_finite smooth_angle)
    || smooth_angle < 0. || smooth_angle > Float.pi
  then
    invalid_arg
      "Mesh3.sweep: smooth_angle must be finite and between zero and pi";
  if List.exists (fun point -> not (finite_vec3 point)) spine then
    Error "Mesh3.sweep: spine points must be finite"
  else
    let spine =
      remove_consecutive_duplicate_vec3 spine |> Array.of_list
    in
    if Array.length spine < 2 then
      Error "Mesh3.sweep: spine requires at least two distinct points"
    else
      let profile =
        if Polygon2.clockwise profile then Polygon2.reverse profile
        else profile
      in
      let profile_points = Array.of_list (Polygon2.vertices profile) in
      let profile_count = Array.length profile_points
      and spine_count = Array.length spine in
      let tangents = spine_tangents spine in
      let normals, binormals = transport_frames tangents in
      let vertices =
        Array.init (spine_count * profile_count) (fun index ->
          let ring = index / profile_count
          and point = profile_points.(index mod profile_count) in
          Vec3.add spine.(ring)
            (Vec3.add
               (Vec3.scale normals.(ring) point.x)
               (Vec3.scale binormals.(ring) point.y)))
      in
      let tex_coords =
        Array.init (spine_count * profile_count) (fun index ->
          let ring = index / profile_count
          and point = index mod profile_count in
          Vec2.create
            (float_of_int point /. float_of_int profile_count)
            (float_of_int ring /. float_of_int (spine_count - 1)))
      in
      let vertex ring point = (ring * profile_count) + point in
      let side_quad_count = (spine_count - 1) * profile_count in
      let side_indices = Array.make (side_quad_count * 6) 0 in
      for ring = 0 to spine_count - 2 do
        for point = 0 to profile_count - 1 do
          let next = (point + 1) mod profile_count in
          let a = vertex ring point
          and b = vertex ring next
          and c = vertex (ring + 1) next
          and d = vertex (ring + 1) point in
          let quad = (ring * profile_count) + point in
          let offset = (side_quad_count - quad - 1) * 6 in
          side_indices.(offset) <- a;
          side_indices.(offset + 1) <- b;
          side_indices.(offset + 2) <- c;
          side_indices.(offset + 3) <- a;
          side_indices.(offset + 4) <- c;
          side_indices.(offset + 5) <- d
        done
      done;
      let cap_indices =
        if not capped then Ok [||]
        else
          Polygon2.triangulate profile
          |> Result.map (fun triangles ->
            let triangles = Array.of_list triangles in
            let index_of = point_index_table profile_points in
            let result = Array.make (Array.length triangles * 6) 0 in
            Array.iteri
              (fun triangle (a, b, c) ->
                let a = index_of a and b = index_of b and c = index_of c in
                let offset = (Array.length triangles - triangle - 1) * 6 in
                result.(offset) <- vertex 0 c;
                result.(offset + 1) <- vertex 0 b;
                result.(offset + 2) <- vertex 0 a;
                result.(offset + 3) <- vertex (spine_count - 1) a;
                result.(offset + 4) <- vertex (spine_count - 1) b;
                result.(offset + 5) <- vertex (spine_count - 1) c)
              triangles;
            result)
      in
      Result.bind cap_indices (fun caps ->
        let indices = Array.make (Array.length side_indices + Array.length caps) 0 in
        Array.blit side_indices 0 indices 0 (Array.length side_indices);
        Array.blit caps 0 indices (Array.length side_indices) (Array.length caps);
        mesh_with_normals_owned ~angle:smooth_angle ~tex_coords vertices indices)

module Edge_key = struct
  type t = int * int
  let equal = ( = )
  let hash = Hashtbl.hash
end

module Edge_table = Hashtbl.Make (Edge_key)

type edge_info = {
  a : int;
  b : int;
  mutable opposites : int list;
  mutable faces : int list;
  mutable output : int;
}

let edge_key a b = if a < b then a, b else b, a

let build_topology vertex_count faces =
  let neighbors = Array.make vertex_count []
  and edges = Edge_table.create (Array.length faces * 3) in
  let add_neighbor a b =
    neighbors.(a) <- b :: neighbors.(a)
  in
  let add_edge face a b opposite =
    let key = edge_key a b in
    match Edge_table.find_opt edges key with
    | Some edge ->
        edge.opposites <- opposite :: edge.opposites;
        edge.faces <- face :: edge.faces
    | None ->
        add_neighbor a b;
        add_neighbor b a;
        Edge_table.add edges key
          { a = fst key; b = snd key; opposites = [opposite];
            faces = [face]; output = -1 }
  in
  Array.iteri
    (fun face (a, b, c) ->
      add_edge face a b c;
      add_edge face b c a;
      add_edge face c a b)
    faces;
  neighbors, edges

let weighted_vec3 values terms =
  let rec accumulate x y z = function
    | [] -> Vec3.create x y z
    | (index, weight) :: rest ->
        let value = values.(index) in
        accumulate
          (x +. (value.Vec3.x *. weight))
          (y +. (value.y *. weight))
          (z +. (value.z *. weight))
          rest
  in
  accumulate 0. 0. 0. terms

let weighted_vec2 values terms =
  let rec accumulate x y = function
    | [] -> Vec2.create x y
    | (index, weight) :: rest ->
        let value = values.(index) in
        accumulate
          (x +. (value.Vec2.x *. weight))
          (y +. (value.y *. weight))
          rest
  in
  accumulate 0. 0. terms

let weighted_color values terms =
  let rec accumulate r g b a = function
    | [] ->
        let channel value =
          Float.round value |> int_of_float |> Color.clamp_byte
        in
        Color.rgba (channel r) (channel g) (channel b) (channel a)
    | (index, weight) :: rest ->
        let color = values.(index) in
        accumulate
          (r +. (float_of_int color.Color.r *. weight))
          (g +. (float_of_int color.g *. weight))
          (b +. (float_of_int color.b *. weight))
          (a +. (float_of_int color.a *. weight))
          rest
  in
  accumulate 0. 0. 0. 0. terms

let prepare_subdivision mesh =
  let geometry =
    mesh |> Mesh.without_normals |> Mesh.without_colors
    |> Mesh.without_tex_coords
    |> Mesh.merge_duplicate_vertices ~epsilon:1e-12
  in
  if Mesh.vertex_count geometry < Mesh.vertex_count mesh then geometry
  else mesh

let pdk_subdivide ~scheme ~iterations mesh =
  if iterations < 0 then invalid_arg "Mesh3 subdivision iterations must be non-negative"
  else if iterations = 0 then Ok mesh
  else
    Result.bind (Pdk.Prismel_mesh.of_mesh mesh) (fun geometry ->
      Result.bind (Pdk.Ops.subdivide ~scheme ~iterations geometry) (fun geometry ->
        Result.bind (Pdk.Ops.normals geometry) Pdk.Prismel_mesh.to_mesh))
    |> Result.map_error Pdk.Error.to_string

let loop_subdivide ?(iterations = 1) mesh =
  pdk_subdivide ~scheme:Pdk.Ops.Loop ~iterations mesh

let validate_subdivision name iterations mesh =
  if iterations < 0 then
    invalid_arg ("Mesh3." ^ name ^ ": iterations must be non-negative");
  let faces = Mesh.Private.triangle_indices mesh in
  if Array.length faces = 0 then Error ("Mesh3." ^ name ^ ": mesh contains no triangle geometry")
  else Ok faces

let sorted_edges edges =
  let values = Edge_table.to_seq_values edges |> Array.of_seq in
  Array.sort (fun left right -> compare (left.a, left.b) (right.a, right.b)) values;
  values

let non_manifold edges =
  Edge_table.to_seq_values edges
  |> Seq.exists (fun edge -> List.length edge.faces > 2)

let other_opposite edges a b excluded =
  match Edge_table.find_opt edges (edge_key a b) with
  | None -> None
  | Some edge -> List.find_opt (fun value -> value <> excluded) edge.opposites

let butterfly_edge_terms edges omega edge =
  match edge.opposites with
  | [d3; d4] ->
      (match
         other_opposite edges edge.a d3 edge.b,
         other_opposite edges edge.b d3 edge.a,
         other_opposite edges edge.a d4 edge.b,
         other_opposite edges edge.b d4 edge.a
       with
       | Some d6, Some d5, Some d8, Some d7 ->
           [
             edge.a, 0.5; edge.b, 0.5;
             d3, omega; d4, omega;
             d5, -.omega /. 2.; d6, -.omega /. 2.;
             d7, -.omega /. 2.; d8, -.omega /. 2.;
           ]
       | _ -> [edge.a, 0.5; edge.b, 0.5])
  | _ -> [edge.a, 0.5; edge.b, 0.5]

let butterfly_once ~omega mesh =
  let mesh = prepare_subdivision mesh in
  Result.bind (validate_subdivision "butterfly_subdivide" 1 mesh) (fun faces ->
    let view = Mesh.Private.view mesh in
    let source = view.vertices in
    let _, edges = build_topology (Array.length source) faces in
    if non_manifold edges then Error "Mesh3.butterfly_subdivide: mesh is non-manifold"
    else
      let edge_list = sorted_edges edges in
      Array.iteri (fun index edge -> edge.output <- Array.length source + index) edge_list;
      let output_count = Array.length source + Array.length edge_list in
      let positions = Array.make output_count Vec3.zero in
      Array.blit source 0 positions 0 (Array.length source);
      Array.iter
        (fun edge ->
          positions.(edge.output) <-
            weighted_vec3 source (butterfly_edge_terms edges omega edge))
        edge_list;
      let output_terms = lazy (
        Array.append
          (Array.init (Array.length source) (fun index -> [index, 1.]))
          (Array.map (butterfly_edge_terms edges omega) edge_list))
      in
      let colors =
        Option.map
          (fun values -> Array.map (weighted_color values) (Lazy.force output_terms))
          view.colors
      and tex_coords =
        Option.map
          (fun values -> Array.map (weighted_vec2 values) (Lazy.force output_terms))
          view.tex_coords
      in
      let edge_output a b = match Edge_table.find_opt edges (edge_key a b) with Some edge -> edge.output | None -> assert false in
      let indices = Array.make (Array.length faces * 12) 0 in
      Array.iteri (fun face (a, b, c) ->
        let ab = edge_output a b and bc = edge_output b c
        and ca = edge_output c a in
        let output = (Array.length faces - face - 1) * 12 in
        indices.(output) <- a;
        indices.(output + 1) <- ab;
        indices.(output + 2) <- ca;
        indices.(output + 3) <- b;
        indices.(output + 4) <- bc;
        indices.(output + 5) <- ab;
        indices.(output + 6) <- c;
        indices.(output + 7) <- ca;
        indices.(output + 8) <- bc;
        indices.(output + 9) <- ab;
        indices.(output + 10) <- bc;
        indices.(output + 11) <- ca) faces;
      Mesh.Private.create_owned ~mode:Mesh.Triangles ~indices
        ?colors ?tex_coords positions
      |> Result.map Mesh.recalculate_normals)

let butterfly_subdivide ?(iterations = 1) ?(omega = 1. /. 8.) mesh =
  if not (Float.is_finite omega) then invalid_arg "Mesh3.butterfly_subdivide: omega must be finite";
  if iterations < 0 then invalid_arg "Mesh3.butterfly_subdivide: iterations must be non-negative";
  let rec apply count mesh = if count = 0 then Ok mesh else Result.bind (butterfly_once ~omega mesh) (apply (count - 1)) in
  apply iterations mesh

let face_vertices = function a, b, c -> [a; b; c]

let face_terms face =
  let vertices = face_vertices face in
  let weight = 1. /. float_of_int (List.length vertices) in
  List.map (fun vertex -> vertex, weight) vertices

let vertex_face_adjacency vertex_count faces =
  let adjacency = Array.make vertex_count [] in
  Array.iteri (fun face (a, b, c) ->
    adjacency.(a) <- face :: adjacency.(a);
    if b <> a then adjacency.(b) <- face :: adjacency.(b);
    if c <> a && c <> b then adjacency.(c) <- face :: adjacency.(c)) faces;
  adjacency

let triangle_centroid (values : Vec3.t array) (a, b, c) =
  let a = values.(a) and b = values.(b) and c = values.(c) in
  Vec3.create
    ((a.Vec3.x +. b.x +. c.x) /. 3.)
    ((a.y +. b.y +. c.y) /. 3.)
    ((a.z +. b.z +. c.z) /. 3.)

let catmull_clark ?(iterations = 1) mesh =
  pdk_subdivide ~scheme:Pdk.Ops.Catmull_clark ~iterations mesh

let doo_corner_terms face local =
  let vertices = Array.of_list (face_vertices face) in
  let count = Array.length vertices in
  let previous = vertices.((local + count - 1) mod count)
  and current = vertices.(local)
  and next = vertices.((local + 1) mod count) in
  let centroid = face_terms face |> List.map (fun (vertex, weight) -> vertex, weight *. 0.25) in
  centroid @ [previous, 0.125; current, 0.125; current, 0.125; next, 0.125; current, 0.25]

let doo_corner_position (values : Vec3.t array) (a, b, c) local =
  let previous, current, next =
    match local with
    | 0 -> c, a, b
    | 1 -> a, b, c
    | _ -> b, c, a
  in
  let previous = values.(previous) and current = values.(current)
  and next = values.(next) in
  let centroid = triangle_centroid values (a, b, c) in
  Vec3.create
    ((centroid.x *. 0.25) +. (previous.x *. 0.125)
     +. (current.x *. 0.5) +. (next.x *. 0.125))
    ((centroid.y *. 0.25) +. (previous.y *. 0.125)
     +. (current.y *. 0.5) +. (next.y *. 0.125))
    ((centroid.z *. 0.25) +. (previous.z *. 0.125)
     +. (current.z *. 0.5) +. (next.z *. 0.125))

let local_vertex face vertex =
  let a, b, c = face in
  if vertex = a then Some 0
  else if vertex = b then Some 1
  else if vertex = c then Some 2
  else None

let directed_edge face a b =
  match local_vertex face a, local_vertex face b with
  | Some ai, Some bi -> (ai + 1) mod 3 = bi
  | _ -> false

let triangle_normal (positions : Vec3.t array) (a, b, c) =
  let a = positions.(a) and b = positions.(b) and c = positions.(c) in
  let abx = b.x -. a.x and aby = b.y -. a.y and abz = b.z -. a.z
  and acx = c.x -. a.x and acy = c.y -. a.y and acz = c.z -. a.z in
  let x = (aby *. acz) -. (abz *. acy)
  and y = (abz *. acx) -. (abx *. acz)
  and z = (abx *. acy) -. (aby *. acx) in
  let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
  if length <= 1e-18 then Vec3.zero
  else Vec3.create (x /. length) (y /. length) (z /. length)

let doo_sabin_once mesh =
  let mesh = prepare_subdivision mesh in
  Result.bind (validate_subdivision "doo_sabin" 1 mesh) (fun faces ->
    let view = Mesh.Private.view mesh in
    let source = view.vertices in
    let neighbors, edges = build_topology (Array.length source) faces in
    if non_manifold edges then Error "Mesh3.doo_sabin: mesh is non-manifold"
    else
      let vertex_faces = vertex_face_adjacency (Array.length source) faces in
      let output_count = Array.length faces * 3 in
      let positions = Array.init output_count (fun output ->
        doo_corner_position source faces.(output / 3) (output mod 3)) in
      let output_terms = lazy (
        Array.init output_count (fun output ->
          doo_corner_terms faces.(output / 3) (output mod 3)))
      in
      let colors =
        Option.map
          (fun values -> Array.map (weighted_color values) (Lazy.force output_terms))
          view.colors
      and tex_coords =
        Option.map
          (fun values -> Array.map (weighted_vec2 values) (Lazy.force output_terms))
          view.tex_coords
      in
      let corner face vertex = match local_vertex faces.(face) vertex with Some local -> (face * 3) + local | None -> assert false in
      let face_normals = Array.map (triangle_normal source) faces in
      let vertex_closed vertex =
        neighbors.(vertex) <> []
        && List.for_all (fun neighbor ->
          match Edge_table.find_opt edges (edge_key vertex neighbor) with
          | Some edge -> List.length edge.faces = 2
          | None -> false) neighbors.(vertex)
      in
      let output_triangles = ref (Array.length faces) in
      Edge_table.iter
        (fun _ edge ->
          match edge.faces with
          | [_; _] -> output_triangles := !output_triangles + 2
          | _ -> ())
        edges;
      Array.iteri
        (fun vertex incident ->
          if vertex_closed vertex && List.length incident >= 3 then
            output_triangles := !output_triangles + List.length incident - 2)
        vertex_faces;
      let indices = Array.make (!output_triangles * 3) 0 in
      let cursor = ref (Array.length indices) in
      let prepend a b c =
        cursor := !cursor - 3;
        indices.(!cursor) <- a;
        indices.(!cursor + 1) <- b;
        indices.(!cursor + 2) <- c
      in
      let prepend_oriented (desired : Vec3.t) a b c =
        let pa = positions.(a) and pb = positions.(b) and pc = positions.(c) in
        let abx = pb.x -. pa.x and aby = pb.y -. pa.y
        and abz = pb.z -. pa.z
        and acx = pc.x -. pa.x and acy = pc.y -. pa.y
        and acz = pc.z -. pa.z in
        let nx = (aby *. acz) -. (abz *. acy)
        and ny = (abz *. acx) -. (abx *. acz)
        and nz = (abx *. acy) -. (aby *. acx) in
        if (nx *. desired.x) +. (ny *. desired.y) +. (nz *. desired.z) >= 0.
        then prepend a b c else prepend a c b
      in
      Array.iteri
        (fun face _ -> prepend (face * 3) (face * 3 + 1) (face * 3 + 2))
        faces;
      Edge_table.iter (fun _ edge -> match edge.faces with
        | [first; second] ->
            let a, b = if directed_edge faces.(first) edge.a edge.b then edge.a, edge.b else edge.b, edge.a in
            let q0 = corner first a and q1 = corner first b and q2 = corner second b and q3 = corner second a in
            let first_normal = face_normals.(first)
            and second_normal = face_normals.(second) in
            let desired = Vec3.create
              (first_normal.x +. second_normal.x)
              (first_normal.y +. second_normal.y)
              (first_normal.z +. second_normal.z) in
            prepend_oriented desired q0 q2 q3;
            prepend_oriented desired q0 q1 q2
        | _ -> ()) edges;
      Array.iteri (fun vertex incident ->
        let closed = vertex_closed vertex in
        if closed && List.length incident >= 3 then begin
          let rec sum_normal x y z = function
            | [] -> Vec3.create x y z |> Vec3.normalize
            | face :: rest ->
                let normal = face_normals.(face) in
                sum_normal (x +. normal.x) (y +. normal.y)
                  (z +. normal.z) rest
          in
          let desired = sum_normal 0. 0. 0. incident in
          let reference = if abs_float (Vec3.dot desired Vec3.unit_y) < 0.9 then Vec3.unit_y else Vec3.unit_x in
          let axis_x = Vec3.cross reference desired |> Vec3.normalize in
          let axis_y = Vec3.cross desired axis_x |> Vec3.normalize in
          let ordered = List.map (fun face ->
            let output = corner face vertex in
            let delta = Vec3.sub positions.(output) source.(vertex) in
            atan2 (Vec3.dot delta axis_y) (Vec3.dot delta axis_x), output) incident
            |> List.sort (fun (left, _) (right, _) -> Float.compare left right)
            |> List.map snd in
          match ordered with
          | first :: second :: rest ->
              let rec fan previous = function
                | [] -> ()
                | current :: tail ->
                    prepend_oriented desired first previous current;
                    fan current tail
              in fan second rest
          | _ -> ()
        end) vertex_faces;
      assert (!cursor = 0);
      Mesh.Private.create_owned ~mode:Mesh.Triangles ~indices
        ?colors ?tex_coords positions
      |> Result.map Mesh.recalculate_normals)

let doo_sabin ?(iterations = 1) mesh =
  if iterations < 0 then invalid_arg "Mesh3.doo_sabin: iterations must be non-negative";
  let rec apply count mesh = if count = 0 then Ok mesh else Result.bind (doo_sabin_once mesh) (apply (count - 1)) in
  apply iterations mesh

let saddle ~size =
  if not (Float.is_finite size) || size <= 0. then
    invalid_arg "Mesh3.saddle: size must be finite and positive";
  let voxels = Voxel3.create ~origin:Vec3.zero ~dimensions:(2,3,1)
      ~voxel_size:size in
  let filled = List.fold_left
      (fun result cell -> Result.bind result (Voxel3.set cell))
      (Ok voxels) [0,0,0; 0,1,0; 1,1,0; 0,2,0] in
  Result.map (fun mesh -> mesh |> Mesh.without_normals
    |> Mesh.merge_duplicate_vertices ~epsilon:1e-10
    |> Mesh.recalculate_normals) (Result.bind filled Voxel3.surface_mesh)
