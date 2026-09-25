open Prismel_math

module Color = struct
  type t = { r : int; g : int; b : int; a : int }
  let clamp_byte value = max 0 (min 255 value)
  let rgba r g b a = { r; g; b; a }
end

type raw = {
  vertices : Vec3.t array;
  faces : (int * int * int) array;
  colors : Color.t array option;
  tex_coords : Vec2.t array option;
}

let validate_subdivision name mesh =
  if Array.length mesh.faces = 0 then
    Error ("Pdk.Subdivision_extra." ^ name ^ ": mesh contains no triangle geometry")
  else Ok mesh.faces

let create_raw_owned ~indices ?colors ?tex_coords vertices =
  let faces = Array.init (Array.length indices / 3) (fun face ->
    let offset = face * 3 in
    indices.(offset), indices.(offset + 1), indices.(offset + 2)) in
  Ok { vertices; faces; colors; tex_coords }

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
  Result.bind (validate_subdivision "butterfly" mesh) (fun faces ->
    let view = mesh in
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
      create_raw_owned ~indices ?colors ?tex_coords positions)

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
  Result.bind (validate_subdivision "doo_sabin" mesh) (fun faces ->
    let view = mesh in
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
      create_raw_owned ~indices ?colors ?tex_coords positions)

let source ?cancel geometry =
  Cancel.check_opt cancel;
  let topology = Geometry.topology geometry in
  if not (Topology.all_triangles topology) then
    Error "input must contain only triangles"
  else if List.exists (fun attribute ->
      Attribute.owner attribute <> Attribute.Point
      || not (List.mem (Attribute.name attribute) ["N"; "Cd"; "uv"]))
      (Geometry.attributes geometry)
      || Geometry.groups geometry <> []
      || Geometry.edge_groups geometry <> [] then
    Error "subdivision supports only point N, Cd and uv without groups"
  else
    let vertices = Array.init (Geometry.point_count geometry) (fun point ->
      if point land 4095 = 0 then Cancel.check_opt cancel;
      let x, y, z = Packed.Float3.get (Geometry.positions geometry) point in
      Vec3.create x y z) in
    let faces = Array.init (Geometry.primitive_count geometry) (fun face ->
      let first, _ = Topology.primitive_vertex_range topology face in
      Topology.point_of_vertex topology first,
      Topology.point_of_vertex topology (first + 1),
      Topology.point_of_vertex topology (first + 2)) in
    let colors = match Geometry.find_attribute ~owner:Attribute.Point "Cd" geometry with
      | None -> Ok None
      | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Float4 values ->
            let channel value = Color.clamp_byte (int_of_float (Float.round (value *. 255.))) in
            Ok (Some (Array.init (Array.length vertices) (fun point ->
              let r, g, b, a = Packed.Float4.get values point in
              Color.rgba (channel r) (channel g) (channel b) (channel a))))
        | _ -> Error "point Cd must be Float4") in
    let tex_coords = match Geometry.find_attribute ~owner:Attribute.Point "uv" geometry with
      | None -> Ok None
      | Some attribute -> (match Attribute.Private.storage attribute with
        | Attribute.Float2 values ->
            Ok (Some (Array.init (Array.length vertices) (fun point ->
              let x, y = Packed.Float2.get values point in Vec2.create x y)))
        | _ -> Error "point uv must be Float2") in
    Result.bind colors (fun colors ->
      Result.map (fun tex_coords -> { vertices; faces; colors; tex_coords }) tex_coords)

let output ?cancel raw =
  Cancel.check_opt cancel;
  let count = Array.length raw.vertices in
  let x = Array.make count 0. and y = Array.make count 0.
  and z = Array.make count 0. in
  Array.iteri (fun point value ->
    if point land 4095 = 0 then Cancel.check_opt cancel;
    x.(point) <- value.Vec3.x; y.(point) <- value.y; z.(point) <- value.z)
    raw.vertices;
  let positions = Packed.Float3.Private.of_owned_exn ~x ~y ~z in
  let vertex_points = Array.make (Array.length raw.faces * 3) 0 in
  Array.iteri (fun face (a, b, c) ->
    let at = face * 3 in
    vertex_points.(at) <- a; vertex_points.(at + 1) <- b;
    vertex_points.(at + 2) <- c) raw.faces;
  let primitive_offsets = Array.init (Array.length raw.faces + 1)
      (fun face -> face * 3) in
  let attributes = ref [] in
  Option.iter (fun colors ->
    let count = Array.length colors in
    let x = Array.make count 0. and y = Array.make count 0.
    and z = Array.make count 0. and w = Array.make count 0. in
    Array.iteri (fun point color ->
      x.(point) <- float_of_int color.Color.r /. 255.;
      y.(point) <- float_of_int color.g /. 255.;
      z.(point) <- float_of_int color.b /. 255.;
      w.(point) <- float_of_int color.a /. 255.) colors;
    let values = Packed.Float4.of_owned ~x ~y ~z ~w |> Result.get_ok in
    attributes := (Attribute.create_key_owned
      (Attribute.color ~owner:Attribute.Point) values |> Result.get_ok)
      :: !attributes) raw.colors;
  Option.iter (fun tex_coords ->
    let count = Array.length tex_coords in
    let x = Array.make count 0. and y = Array.make count 0. in
    Array.iteri (fun point value ->
      x.(point) <- value.Vec2.x; y.(point) <- value.y) tex_coords;
    let values = Packed.Float2.of_owned ~x ~y |> Result.get_ok in
    attributes := (Attribute.create_key_owned
      (Attribute.tex_coord ~owner:Attribute.Point) values |> Result.get_ok)
      :: !attributes) raw.tex_coords;
  Result.bind (Topology.polygons_owned ~point_count:count
    ~vertex_points ~primitive_offsets) (fun topology ->
      Geometry.create ~positions ~topology ~attributes:!attributes ())

let run ?cancel ~operation ~iterations once geometry =
  if iterations < 0 then
    Error (Error.make ~operation ~code:"invalid_iterations"
      "iterations must be non-negative")
  else if iterations = 0 then Ok geometry
  else Error.guard ~operation ~code:"invalid_geometry" (fun () ->
    Result.bind (source ?cancel geometry) (fun input ->
      let rec apply remaining raw =
        Cancel.check_opt cancel;
        if remaining = 0 then Ok raw
        else Result.bind (once raw) (apply (remaining - 1)) in
      Result.bind (apply iterations input) (fun raw ->
        Result.bind (output ?cancel raw) (fun output ->
          Normal_ops.run ?cancel output))))

let butterfly ?cancel ?(iterations = 1) ?(omega = 1. /. 8.) geometry =
  if not (Float.is_finite omega) then
    Error (Error.make ~operation:"butterfly" ~code:"invalid_omega"
      "omega must be finite")
  else run ?cancel ~operation:"butterfly" ~iterations
    (butterfly_once ~omega) geometry

let doo_sabin ?cancel ?(iterations = 1) geometry =
  run ?cancel ~operation:"doo_sabin" ~iterations doo_sabin_once geometry
