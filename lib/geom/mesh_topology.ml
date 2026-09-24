open Prismel

type edge = { a : int; b : int }

type t = {
  mesh : Mesh.t;
  faces : (int * int * int) array;
  index : Pdk.Topology_index.t;
}

let packed_geometry mesh faces =
  let mesh_view = Mesh.Private.packed_view mesh in
  let point_count = Mesh.vertex_count mesh
  and face_count = Array.length faces in
  let vertex_points = Array.make (face_count * 3) 0 in
  Array.iteri (fun face (a, b, c) ->
    let output = face * 3 in
    vertex_points.(output) <- a;
    vertex_points.(output + 1) <- b;
    vertex_points.(output + 2) <- c) faces;
  let primitive_offsets = Array.init (face_count + 1) (fun face -> face * 3) in
  let topology = Pdk.Topology.polygons_owned ~point_count ~vertex_points
      ~primitive_offsets |> Result.get_ok in
  let positions = Pdk.Packed.Float3.Private.of_shared_exn
      ~x:mesh_view.vertices.x ~y:mesh_view.vertices.y ~z:mesh_view.vertices.z in
  Pdk.Geometry.create ~positions ~topology () |> Result.get_ok

let of_mesh mesh =
  let faces = Mesh.Private.triangle_indices mesh in
  let geometry = packed_geometry mesh faces in
  { mesh; faces; index = Pdk.Topology_index.create (Pdk.Geometry.topology geometry) }

let mesh topology = topology.mesh

let edges topology =
  List.init (Pdk.Topology_index.edge_count topology.index) (fun edge ->
    let a, b = Pdk.Topology_index.edge_points topology.index edge in
    { a; b })

let edge_faces edge topology =
  match Pdk.Topology_index.find_edge topology.index ~a:edge.a ~b:edge.b with
  | None -> []
  | Some edge ->
      let count = Pdk.Topology_index.edge_incidence_count topology.index edge in
      let result = ref [] in
      for local = count - 1 downto 0 do
        let vertex = Pdk.Topology_index.edge_vertex topology.index ~edge ~local in
        result := Pdk.Topology_index.primitive_of_vertex topology.index vertex
            :: !result
      done;
      !result

let valid_vertex index topology =
  index >= 0 && index < Pdk.Topology_index.point_count topology.index

let vertex_neighbors vertex topology =
  if not (valid_vertex vertex topology) then []
  else
    let count = Pdk.Topology_index.point_edge_count topology.index vertex in
    let result = ref [] in
    for local = count - 1 downto 0 do
      let edge = Pdk.Topology_index.point_edge topology.index ~point:vertex ~local in
      let a, b = Pdk.Topology_index.edge_points topology.index edge in
      result := (if a = vertex then b else a) :: !result
    done;
    !result

let vertex_faces vertex topology =
  if not (valid_vertex vertex topology) then []
  else
    let count = Pdk.Topology_index.point_incidence_count topology.index vertex in
    let result = ref [] and previous = ref (-1) in
    for local = count - 1 downto 0 do
      let corner = Pdk.Topology_index.point_vertex topology.index
          ~point:vertex ~local in
      let face = Pdk.Topology_index.primitive_of_vertex topology.index corner in
      if face <> !previous then begin result := face :: !result; previous := face end
    done;
    !result

let vertex_valence vertex topology =
  if valid_vertex vertex topology
  then Pdk.Topology_index.point_edge_count topology.index vertex
  else 0

let face_neighbors face topology =
  if face < 0 || face >= Array.length topology.faces then []
  else
    let a, b, c = topology.faces.(face) in
    let result = ref [] in
    let include_edge left right =
      match Pdk.Topology_index.find_edge topology.index ~a:left ~b:right with
      | None -> ()
      | Some edge ->
          for local = 0 to Pdk.Topology_index.edge_incidence_count topology.index edge - 1 do
            let corner = Pdk.Topology_index.edge_vertex topology.index ~edge ~local in
            let neighbor = Pdk.Topology_index.primitive_of_vertex topology.index corner in
            if neighbor <> face then result := neighbor :: !result
          done in
    include_edge a b; include_edge b c; include_edge c a;
    List.sort_uniq Int.compare !result

let connected_components topology =
  let face_count = Array.length topology.faces in
  let parent = Array.init face_count Fun.id in
  let rec root face =
    let next = parent.(face) in
    if next = face then face
    else begin let result = root next in parent.(face) <- result; result end in
  let join left right =
    let left = root left and right = root right in
    if left <> right then parent.(max left right) <- min left right in
  for edge = 0 to Pdk.Topology_index.edge_count topology.index - 1 do
    let count = Pdk.Topology_index.edge_incidence_count topology.index edge in
    if count > 1 then begin
      let first_corner = Pdk.Topology_index.edge_vertex topology.index ~edge ~local:0 in
      let first = Pdk.Topology_index.primitive_of_vertex topology.index first_corner in
      for local = 1 to count - 1 do
        let corner = Pdk.Topology_index.edge_vertex topology.index ~edge ~local in
        join first (Pdk.Topology_index.primitive_of_vertex topology.index corner)
      done
    end
  done;
  let grouped = Array.make face_count [] in
  for face = face_count - 1 downto 0 do
    let representative = root face in
    grouped.(representative) <- face :: grouped.(representative)
  done;
  let components = ref [] in
  for representative = face_count - 1 downto 0 do
    match grouped.(representative) with
    | [] -> ()
    | component -> components := component :: !components
  done;
  !components

let replace_vertex index point topology =
  Result.map of_mesh (Mesh.with_vertex index point topology.mesh)

let remove_vertex index topology =
  Result.map of_mesh (Mesh.remove_vertex index topology.mesh)

let remove_faces predicate topology =
  let face_count = Array.length topology.faces in
  let keep = Array.make face_count false and kept_count = ref 0 in
  for index = 0 to face_count - 1 do
    match Mesh.face index topology.mesh with
    | Some face when not (predicate index face) ->
        keep.(index) <- true;
        incr kept_count
    | Some _ -> ()
    | None -> assert false
  done;
  let indices = Array.make (!kept_count * 3) 0 and output = ref 0 in
  for face = 0 to face_count - 1 do
    if keep.(face) then begin
      let a, b, c = topology.faces.(face) in
      indices.(!output) <- a;
      indices.(!output + 1) <- b;
      indices.(!output + 2) <- c;
      output := !output + 3
    end
  done;
  let view = Mesh.Private.view topology.mesh in
  Mesh.Private.create_owned ~mode:Mesh.Triangles ~indices
    ?colors:(Option.map Array.copy view.colors)
    ?tex_coords:(Option.map Array.copy view.tex_coords)
    (Array.copy view.vertices)
  |> Result.map (fun mesh -> Mesh.recalculate_normals mesh |> of_mesh)
