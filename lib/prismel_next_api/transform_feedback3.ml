type t = {
  primitives : Shader3.primitive list;
}

let validate_output shader (output : Shader3.vertex_output) =
  if List.length output.varyings <> Shader3.varying_count shader then
    invalid_arg
      "Transform_feedback3: stage output varying count differs from shader"

let pairs mode indices =
  let count = Array.length indices in
  match mode with
  | Mesh.Lines ->
      List.init (count / 2) (fun pair ->
        indices.(pair * 2), indices.((pair * 2) + 1))
  | Line_strip ->
      List.init (max 0 (count - 1)) (fun index ->
        indices.(index), indices.(index + 1))
  | Line_loop when count > 1 ->
      List.init count (fun index ->
        indices.(index), indices.((index + 1) mod count))
  | Points | Triangles | Triangle_strip | Triangle_fan | Line_loop -> []

let capture ?(model = Mat4.identity) ~viewport ~camera ~shader source =
  let source =
    if Mesh.has_normals source then source
    else Mesh.recalculate_normals source
  in
  let mesh = Mesh.Private.packed_view source in
  let view = Camera.view_matrix camera
  and projection = Camera.projection_matrix ~viewport camera in
  let model_view_projection = Mat4.mul projection (Mat4.mul view model) in
  let normal_matrix =
    Mat4.inverse model
    |> Option.fold ~none:Mat4.identity ~some:Mat4.transpose
  in
  let colors = Option.value ~default:[||] mesh.colors
  and tex_coords = Option.value ~default:[||] mesh.tex_coords
  and uniforms = Shader3.uniforms shader in
  let outputs =
    Array.init (Array.length mesh.vertices.x)
      (fun vertex_index ->
        let position =
          Vec3.create mesh.vertices.x.(vertex_index)
            mesh.vertices.y.(vertex_index) mesh.vertices.z.(vertex_index)
        in
        let input : Shader3.vertex_input = {
          vertex_index;
          position;
          normal =
            (match mesh.normals with
             | Some normals when vertex_index < Array.length normals.x ->
                 Vec3.create normals.x.(vertex_index) normals.y.(vertex_index)
                   normals.z.(vertex_index)
             | _ -> Vec3.unit_z);
          color =
            if vertex_index < Array.length colors
            then colors.(vertex_index)
            else Color.white;
          tex_coord =
            if vertex_index < Array.length tex_coords
            then tex_coords.(vertex_index)
            else Vec2.zero;
          model;
          view;
          projection;
          model_view_projection;
          normal_matrix;
          uniforms;
        } in
        let output = Shader3.Private.vertex shader input in
        validate_output shader output;
        output)
  in
  let inputs =
    match mesh.mode with
    | Mesh.Points ->
        Array.to_list mesh.indices
        |> List.map (fun index -> Shader3.Point outputs.(index))
    | Lines | Line_strip | Line_loop ->
        pairs mesh.mode mesh.indices
        |> List.map (fun (left, right) ->
          Shader3.Line (outputs.(left), outputs.(right)))
    | Triangles | Triangle_strip | Triangle_fan ->
        Mesh.triangles source
        |> List.map (fun (a, b, c) ->
          Shader3.Triangle (outputs.(a), outputs.(b), outputs.(c)))
  in
  let primitives =
    match Shader3.Private.geometry shader with
    | None -> inputs
    | Some geometry ->
        List.mapi
          (fun primitive_index primitive ->
            geometry { Shader3.primitive_index; primitive; uniforms })
          inputs
        |> List.concat
  in
  List.iter
    (function
      | Shader3.Point output -> validate_output shader output
      | Line (left, right) ->
          validate_output shader left;
          validate_output shader right
      | Triangle (a, b, c) ->
          validate_output shader a;
          validate_output shader b;
          validate_output shader c)
    primitives;
  { primitives }

let primitives feedback = feedback.primitives

let primitive_vertices = function
  | Shader3.Point vertex -> [vertex]
  | Line (left, right) -> [left; right]
  | Triangle (a, b, c) -> [a; b; c]

let vertices feedback = List.concat_map primitive_vertices feedback.primitives
let varyings feedback =
  List.map
    (fun (vertex : Shader3.vertex_output) -> vertex.varyings)
    (vertices feedback)
let primitive_count feedback = List.length feedback.primitives
let vertex_count feedback = List.length (vertices feedback)

let mesh_of_primitive primitive =
  let mode, vertices =
    match primitive with
    | Shader3.Point vertex -> Mesh.Points, [vertex]
    | Line (left, right) -> Mesh.Lines, [left; right]
    | Triangle (a, b, c) -> Mesh.Triangles, [a; b; c]
  in
  Mesh.create_exn ~mode
    ~normals:
      (List.map
         (fun (vertex : Shader3.vertex_output) -> vertex.world_normal)
         vertices)
    ~colors:
      (List.map
         (fun (vertex : Shader3.vertex_output) -> vertex.color)
         vertices)
    ~tex_coords:
      (List.map
         (fun (vertex : Shader3.vertex_output) -> vertex.tex_coord)
         vertices)
    (List.map
       (fun (vertex : Shader3.vertex_output) -> vertex.world_position)
       vertices)

let meshes feedback = List.map mesh_of_primitive feedback.primitives
