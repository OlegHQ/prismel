type mode =
  | Points
  | Lines
  | Line_strip
  | Line_loop
  | Triangles
  | Triangle_strip
  | Triangle_fan

type box_side =
  | Positive_x
  | Negative_x
  | Positive_y
  | Negative_y
  | Positive_z
  | Negative_z

module Vec3_buffer = struct
  type t = {
    x : float array;
    y : float array;
    z : float array;
  }

  let empty = { x = [||]; y = [||]; z = [||] }
  let length values = Array.length values.x
  let get values index = Vec3.create values.x.(index) values.y.(index) values.z.(index)

  let of_array values =
    let count = Array.length values in
    let x = Array.make count 0. and y = Array.make count 0.
    and z = Array.make count 0. in
    Array.iteri (fun index value ->
      x.(index) <- value.Vec3.x;
      y.(index) <- value.y;
      z.(index) <- value.z) values;
    { x; y; z }

  let to_array values = Array.init (length values) (get values)
  let to_list values = Array.to_list (to_array values)

  let init ?(parallel = false) count make =
    let x = Array.make count 0. and y = Array.make count 0.
    and z = Array.make count 0. in
    let fill index =
      let value = make index in
      x.(index) <- value.Vec3.x;
      y.(index) <- value.y;
      z.(index) <- value.z
    in
    if count > 0 then
      if parallel then Parallel.for_ ~chunk_size:4096 ~start:0 ~finish:(count - 1) fill
      else for index = 0 to count - 1 do fill index done;
    { x; y; z }

  let copy values = {
    x = Array.copy values.x;
    y = Array.copy values.y;
    z = Array.copy values.z;
  }

  let replace index value values =
    let copy = copy values in
    copy.x.(index) <- value.Vec3.x;
    copy.y.(index) <- value.y;
    copy.z.(index) <- value.z;
    copy

  let remove index values =
    init (length values - 1) (fun target ->
      get values (if target < index then target else target + 1))

  let blit source source_offset target target_offset count =
    Array.blit source.x source_offset target.x target_offset count;
    Array.blit source.y source_offset target.y target_offset count;
    Array.blit source.z source_offset target.z target_offset count

  let append left right =
    let left_count = length left and right_count = length right in
    let output = {
      x = Array.make (left_count + right_count) 0.;
      y = Array.make (left_count + right_count) 0.;
      z = Array.make (left_count + right_count) 0.;
    } in
    blit left 0 output 0 left_count;
    blit right 0 output left_count right_count;
    output

  let transform_points matrix values =
    let count = length values in
    let output = {
      x = Array.make count 0.;
      y = Array.make count 0.;
      z = Array.make count 0.;
    } in
    let (m00, m01, m02, m03), (m10, m11, m12, m13),
        (m20, m21, m22, m23), (m30, m31, m32, m33) =
      Mat4.to_rows matrix in
    if count > 0 then
      Parallel.for_ ~chunk_size:4096 ~start:0 ~finish:(count - 1)
      (fun index ->
        let vx = values.x.(index) and vy = values.y.(index)
        and vz = values.z.(index) in
        let x = m00 *. vx +. m01 *. vy +. m02 *. vz +. m03
        and y = m10 *. vx +. m11 *. vy +. m12 *. vz +. m13
        and z = m20 *. vx +. m21 *. vy +. m22 *. vz +. m23
        and w = m30 *. vx +. m31 *. vy +. m32 *. vz +. m33 in
        if abs_float w <= 1e-12 then begin
          output.x.(index) <- x;
          output.y.(index) <- y;
          output.z.(index) <- z
        end else begin
          output.x.(index) <- x /. w;
          output.y.(index) <- y /. w;
          output.z.(index) <- z /. w
        end);
    output

  let transform_normalized_directions matrix values =
    let count = length values in
    let output = {
      x = Array.make count 0.;
      y = Array.make count 0.;
      z = Array.make count 0.;
    } in
    let (m00, m01, m02, _), (m10, m11, m12, _),
        (m20, m21, m22, _), _ = Mat4.to_rows matrix in
    if count > 0 then
      Parallel.for_ ~chunk_size:4096 ~start:0 ~finish:(count - 1)
      (fun index ->
        let vx = values.x.(index) and vy = values.y.(index)
        and vz = values.z.(index) in
        let x = m00 *. vx +. m01 *. vy +. m02 *. vz
        and y = m10 *. vx +. m11 *. vy +. m12 *. vz
        and z = m20 *. vx +. m21 *. vy +. m22 *. vz in
        let length = sqrt (x *. x +. y *. y +. z *. z) in
        if length <> 0. then begin
          output.x.(index) <- x /. length;
          output.y.(index) <- y /. length;
          output.z.(index) <- z /. length
        end);
    output
end

type t = {
  mode : mode;
  vertices : Vec3_buffer.t;
  indices : int array;
  normals : Vec3_buffer.t option;
  colors : Color.t array option;
  tex_coords : Vec2.t array option;
}

type face = {
  vertex_indices : int * int * int;
  points : Vec3.t * Vec3.t * Vec3.t;
  vertex_normals : (Vec3.t * Vec3.t * Vec3.t) option;
  vertex_colors : (Color.t * Color.t * Color.t) option;
  vertex_tex_coords : (Vec2.t * Vec2.t * Vec2.t) option;
  face_normal : Vec3.t;
}

let validate_attribute name vertex_count = function
  | None -> Ok None
  | Some values ->
      let values = Array.of_list values in
      if Array.length values <> vertex_count then
        Error
          (Printf.sprintf
             "Mesh.create: %s count (%d) must match vertex count (%d)"
             name (Array.length values) vertex_count)
      else Ok (Some values)

let validate_attribute_array name vertex_count = function
  | None -> Ok None
  | Some values when Array.length values = vertex_count -> Ok (Some values)
  | Some values ->
      Error (Printf.sprintf
        "Mesh.create: %s count (%d) must match vertex count (%d)"
        name (Array.length values) vertex_count)

let create_owned ?(mode = Triangles) ?indices ?normals ?colors ?tex_coords
    vertices =
  let vertex_count = Array.length vertices in
  let indices = Option.value indices ~default:(Array.init vertex_count Fun.id) in
  match Array.find_opt (fun index -> index < 0 || index >= vertex_count) indices with
  | Some index -> Error
      (Printf.sprintf "Mesh.create: index %d is outside the vertex array" index)
  | None ->
      match validate_attribute_array "normal" vertex_count normals,
            validate_attribute_array "color" vertex_count colors,
            validate_attribute_array "texture coordinate" vertex_count tex_coords with
      | Ok normals, Ok colors, Ok tex_coords ->
          Ok {
            mode;
            vertices = Vec3_buffer.of_array vertices;
            indices;
            normals = Option.map Vec3_buffer.of_array normals;
            colors;
            tex_coords;
          }
      | Error message, _, _ | _, Error message, _ | _, _, Error message ->
          Error message

let create_packed_owned ?(mode = Triangles) ?indices ?normals ?colors
    ?tex_coords (vertices : Vec3_buffer.t) =
  let vertex_count = Vec3_buffer.length vertices in
  let valid_vec3_attribute name = function
    | None -> Ok None
    | Some values when Vec3_buffer.length values = vertex_count -> Ok (Some values)
    | Some values ->
        Error (Printf.sprintf
          "Mesh.create: %s count (%d) must match vertex count (%d)"
          name (Vec3_buffer.length values) vertex_count)
  in
  let indices = Option.value indices ~default:(Array.init vertex_count Fun.id) in
  match Array.find_opt (fun index -> index < 0 || index >= vertex_count) indices with
  | Some index -> Error
      (Printf.sprintf "Mesh.create: index %d is outside the vertex array" index)
  | None ->
      match valid_vec3_attribute "normal" normals,
            validate_attribute_array "color" vertex_count colors,
            validate_attribute_array "texture coordinate" vertex_count tex_coords with
      | Ok normals, Ok colors, Ok tex_coords ->
          Ok { mode; vertices; indices; normals; colors; tex_coords }
      | Error message, _, _ | _, Error message, _ | _, _, Error message ->
          Error message

let create ?(mode = Triangles) ?indices ?normals ?colors ?tex_coords vertices =
  let vertices = Array.of_list vertices in
  let vertex_count = Array.length vertices in
  let indices =
    match indices with
    | None -> Array.init vertex_count Fun.id
    | Some values -> Array.of_list values
  in
  match
    Array.find_opt (fun index -> index < 0 || index >= vertex_count) indices
  with
  | Some index ->
      Error (Printf.sprintf "Mesh.create: index %d is outside the vertex array" index)
  | None ->
      (match
         validate_attribute "normal" vertex_count normals,
         validate_attribute "color" vertex_count colors,
         validate_attribute "texture coordinate" vertex_count tex_coords
       with
       | Ok normals, Ok colors, Ok tex_coords ->
           Ok {
             mode;
             vertices = Vec3_buffer.of_array vertices;
             indices;
             normals = Option.map Vec3_buffer.of_array normals;
             colors;
             tex_coords;
           }
       | Error message, _, _ | _, Error message, _ | _, _, Error message ->
           Error message)

let create_exn ?mode ?indices ?normals ?colors ?tex_coords vertices =
  match create ?mode ?indices ?normals ?colors ?tex_coords vertices with
  | Ok mesh -> mesh
  | Error message -> invalid_arg message

let mode (mesh : t) = mesh.mode
let vertices (mesh : t) = Vec3_buffer.to_list mesh.vertices
let indices (mesh : t) = Array.to_list mesh.indices
let normals (mesh : t) = Option.fold ~none:[] ~some:Vec3_buffer.to_list mesh.normals
let colors (mesh : t) = Option.fold ~none:[] ~some:Array.to_list mesh.colors
let tex_coords (mesh : t) =
  Option.fold ~none:[] ~some:Array.to_list mesh.tex_coords
let vertex_count (mesh : t) = Vec3_buffer.length mesh.vertices
let index_count (mesh : t) = Array.length mesh.indices
let centroid (mesh : t) =
  let count = Vec3_buffer.length mesh.vertices in
  if count = 0 then None
  else
    let x = ref 0. and y = ref 0. and z = ref 0. in
    for index = 0 to count - 1 do
      x := !x +. mesh.vertices.x.(index);
      y := !y +. mesh.vertices.y.(index);
      z := !z +. mesh.vertices.z.(index)
    done;
    let inverse = 1. /. float_of_int count in
    Some (Vec3.create (!x *. inverse) (!y *. inverse) (!z *. inverse))
let has_normals (mesh : t) = Option.is_some mesh.normals
let has_colors (mesh : t) = Option.is_some mesh.colors
let has_tex_coords (mesh : t) = Option.is_some mesh.tex_coords

let array_get values index =
  if index < 0 || index >= Array.length values then None
  else Some values.(index)

let vertex index (mesh : t) =
  if index < 0 || index >= Vec3_buffer.length mesh.vertices then None
  else Some (Vec3_buffer.get mesh.vertices index)
let index index (mesh : t) = array_get mesh.indices index
let normal index (mesh : t) =
  Option.bind mesh.normals (fun values ->
    if index < 0 || index >= Vec3_buffer.length values then None
    else Some (Vec3_buffer.get values index))
let color index (mesh : t) =
  Option.bind mesh.colors (fun values -> array_get values index)
let tex_coord index (mesh : t) =
  Option.bind mesh.tex_coords (fun values -> array_get values index)

let with_mode mode mesh = { mesh with mode }

let replace name index value values =
  if index < 0 || index >= Array.length values then
    Error
      (Printf.sprintf "Mesh.with_%s: index %d is out of range" name index)
  else
    let copy = Array.copy values in
    copy.(index) <- value;
    Ok copy

let with_vertex index value mesh =
  if index < 0 || index >= Vec3_buffer.length mesh.vertices then
    Error (Printf.sprintf "Mesh.with_vertex: index %d is out of range" index)
  else Ok { mesh with vertices = Vec3_buffer.replace index value mesh.vertices }

let with_index index value mesh =
  if value < 0 || value >= Vec3_buffer.length mesh.vertices then
    Error
      (Printf.sprintf
         "Mesh.with_index: vertex index %d is out of range" value)
  else
    replace "index" index value mesh.indices
    |> Result.map (fun indices -> { mesh with indices })

let replace_optional name plural index value = function
  | None -> Error ("Mesh.with_" ^ name ^ ": mesh has no " ^ plural)
  | Some values ->
      replace name index value values |> Result.map Option.some

let with_normal index value mesh =
  match mesh.normals with
  | None -> Error "Mesh.with_normal: mesh has no normals"
  | Some normals when index < 0 || index >= Vec3_buffer.length normals ->
      Error (Printf.sprintf "Mesh.with_normal: index %d is out of range" index)
  | Some normals ->
      Ok { mesh with normals = Some (Vec3_buffer.replace index value normals) }

let with_color index value mesh =
  replace_optional "color" "colors" index value mesh.colors
  |> Result.map (fun colors -> { mesh with colors })

let with_tex_coord index value mesh =
  replace_optional "tex_coord" "texture coordinates"
    index value mesh.tex_coords
  |> Result.map (fun tex_coords -> { mesh with tex_coords })

let with_indices values mesh =
  let values = Array.of_list values in
  match
    Array.find_opt
      (fun index -> index < 0 || index >= Vec3_buffer.length mesh.vertices)
      values
  with
  | Some index ->
      Error
        (Printf.sprintf
           "Mesh.with_indices: vertex index %d is out of range" index)
  | None -> Ok { mesh with indices = values }

let replace_attribute name values mesh =
  let values = Array.of_list values in
  if Array.length values <> Vec3_buffer.length mesh.vertices then
    Error
      (Printf.sprintf
         "Mesh.with_%s: received %d values for %d vertices"
         name (Array.length values) (Vec3_buffer.length mesh.vertices))
  else Ok values

let with_normals values mesh =
  replace_attribute "normals" values mesh
  |> Result.map (fun normals ->
    { mesh with normals = Some (Vec3_buffer.of_array normals) })

let with_colors values mesh =
  replace_attribute "colors" values mesh
  |> Result.map (fun colors -> { mesh with colors = Some colors })

let with_tex_coords values mesh =
  replace_attribute "tex_coords" values mesh
  |> Result.map (fun tex_coords -> { mesh with tex_coords = Some tex_coords })

let remove_at name index values =
  let count = Array.length values in
  if index < 0 || index >= count then
    Error (Printf.sprintf "Mesh.remove_%s: index %d is out of range" name index)
  else
    Ok
      (Array.init (count - 1) (fun target ->
         values.(if target < index then target else target + 1)))

let remove_vertex index mesh =
  if index < 0 || index >= Vec3_buffer.length mesh.vertices then
    Error
      (Printf.sprintf "Mesh.remove_vertex: index %d is out of range" index)
  else if Array.exists (( = ) index) mesh.indices then
    Error
      (Printf.sprintf
         "Mesh.remove_vertex: vertex %d is still referenced by the index buffer"
         index)
  else
    let remove values =
      match remove_at "vertex" index values with
      | Ok values -> values
      | Error _ -> assert false
    in
    Ok {
      mesh with
      vertices = Vec3_buffer.remove index mesh.vertices;
      indices =
        Array.map (fun value -> if value > index then value - 1 else value)
          mesh.indices;
      normals = Option.map (Vec3_buffer.remove index) mesh.normals;
      colors = Option.map remove mesh.colors;
      tex_coords = Option.map remove mesh.tex_coords;
    }

let without_normals mesh = { mesh with normals = None }
let without_colors mesh = { mesh with colors = None }
let without_tex_coords mesh = { mesh with tex_coords = None }

let auto_indices mesh =
  { mesh with indices = Array.init (Vec3_buffer.length mesh.vertices) Fun.id }

let clear mesh =
  {
    mode = mesh.mode;
    vertices = Vec3_buffer.empty;
    indices = [||];
    normals = None;
    colors = None;
    tex_coords = None;
  }

let transformed matrix mesh =
  let normal_matrix =
    Mat4.inverse matrix |> Option.map Mat4.transpose
  in
  {
    mesh with
    vertices = Vec3_buffer.transform_points matrix mesh.vertices;
    normals =
      Option.map
        (fun normals ->
          match normal_matrix with
          | None -> Vec3_buffer.copy normals
          | Some normal_matrix ->
              Vec3_buffer.transform_normalized_directions normal_matrix normals)
        mesh.normals;
  }

let triangle_indices_array mesh =
  let values = mesh.indices and count = Array.length mesh.indices in
  match mesh.mode with
  | Triangles ->
      Array.init (count / 3) (fun face ->
        values.(face * 3), values.((face * 3) + 1), values.((face * 3) + 2))
  | Triangle_strip ->
      Array.init (max 0 (count - 2)) (fun face ->
        if face mod 2 = 0 then
          values.(face), values.(face + 1), values.(face + 2)
        else
          values.(face + 1), values.(face), values.(face + 2))
  | Triangle_fan when count >= 3 ->
      Array.init (count - 2) (fun face ->
        values.(0), values.(face + 1), values.(face + 2))
  | Points | Lines | Line_strip | Line_loop | Triangle_fan -> [||]

let triangles mesh = Array.to_list (triangle_indices_array mesh)

let face_from_indices mesh ((a, b, c) as indices) =
  let optional_triangle values a b c =
    Option.map (fun values -> values.(a), values.(b), values.(c)) values
  in
  let va = Vec3_buffer.get mesh.vertices a
  and vb = Vec3_buffer.get mesh.vertices b
  and vc = Vec3_buffer.get mesh.vertices c in
  {
    vertex_indices = indices;
    points = va, vb, vc;
    vertex_normals =
      Option.map (fun values ->
        Vec3_buffer.get values a, Vec3_buffer.get values b,
        Vec3_buffer.get values c) mesh.normals;
    vertex_colors = optional_triangle mesh.colors a b c;
    vertex_tex_coords = optional_triangle mesh.tex_coords a b c;
    face_normal =
      Vec3.cross (Vec3.sub vb va) (Vec3.sub vc va)
      |> Vec3.normalize;
  }

let faces mesh =
  triangle_indices_array mesh
  |> Array.map (face_from_indices mesh)
  |> Array.to_list

let face index mesh =
  if index < 0 then None
  else
    let values = mesh.indices and count = Array.length mesh.indices in
    let indices =
      match mesh.mode with
      | Triangles when index < count / 3 ->
          let offset = index * 3 in
          Some (values.(offset), values.(offset + 1), values.(offset + 2))
      | Triangle_strip when index < count - 2 ->
          if index land 1 = 0 then
            Some (values.(index), values.(index + 1), values.(index + 2))
          else Some (values.(index + 1), values.(index), values.(index + 2))
      | Triangle_fan when index < count - 2 ->
          Some (values.(0), values.(index + 1), values.(index + 2))
      | Points | Lines | Line_strip | Line_loop
      | Triangles | Triangle_strip | Triangle_fan -> None
    in
    Option.map (face_from_indices mesh) indices

let face_normals mesh = List.map (fun face -> face.face_normal) (faces mesh)

let recalculate_normals mesh =
  let vertex_count = Vec3_buffer.length mesh.vertices in
  let nx = Array.make vertex_count 0.
  and ny = Array.make vertex_count 0.
  and nz = Array.make vertex_count 0. in
  let add_triangle a b c =
      let abx = mesh.vertices.x.(b) -. mesh.vertices.x.(a)
      and aby = mesh.vertices.y.(b) -. mesh.vertices.y.(a)
      and abz = mesh.vertices.z.(b) -. mesh.vertices.z.(a)
      and acx = mesh.vertices.x.(c) -. mesh.vertices.x.(a)
      and acy = mesh.vertices.y.(c) -. mesh.vertices.y.(a)
      and acz = mesh.vertices.z.(c) -. mesh.vertices.z.(a) in
      let x = aby *. acz -. abz *. acy
      and y = abz *. acx -. abx *. acz
      and z = abx *. acy -. aby *. acx in
      nx.(a) <- nx.(a) +. x; ny.(a) <- ny.(a) +. y; nz.(a) <- nz.(a) +. z;
      nx.(b) <- nx.(b) +. x; ny.(b) <- ny.(b) +. y; nz.(b) <- nz.(b) +. z;
      nx.(c) <- nx.(c) +. x; ny.(c) <- ny.(c) +. y; nz.(c) <- nz.(c) +. z
  in
  let values = mesh.indices and count = Array.length mesh.indices in
  (match mesh.mode with
   | Triangles ->
       for face = 0 to count / 3 - 1 do
         let offset = face * 3 in
         add_triangle values.(offset) values.(offset+1) values.(offset+2)
       done
   | Triangle_strip ->
       for face = 0 to count - 3 do
         if face land 1 = 0 then
           add_triangle values.(face) values.(face+1) values.(face+2)
         else add_triangle values.(face+1) values.(face) values.(face+2)
       done
   | Triangle_fan ->
       for face = 0 to count - 3 do
         add_triangle values.(0) values.(face+1) values.(face+2)
       done
   | Points | Lines | Line_strip | Line_loop -> ());
  let normals = Vec3_buffer.init ~parallel:true vertex_count (fun index ->
    let x = nx.(index) and y = ny.(index) and z = nz.(index) in
    let length = sqrt (x*.x +. y*.y +. z*.z) in
    if length <= 1e-18 then Vec3.zero
    else Vec3.create (x/.length) (y/.length) (z/.length)) in
  { mesh with normals = Some normals }

let flat_shaded mesh =
  match mesh.mode with
  | Points | Lines | Line_strip | Line_loop -> mesh
  | Triangles | Triangle_strip | Triangle_fan ->
      let source_index_count = Array.length mesh.indices in
      let face_count =
        match mesh.mode with
        | Triangles -> source_index_count / 3
        | Triangle_strip | Triangle_fan -> max 0 (source_index_count - 2)
        | Points | Lines | Line_strip | Line_loop -> assert false
      in
      let count = face_count * 3 in
      let vertices = {
        Vec3_buffer.x = Array.make count 0.;
        y = Array.make count 0.;
        z = Array.make count 0.;
      }
      and normals = {
        Vec3_buffer.x = Array.make count 0.;
        y = Array.make count 0.;
        z = Array.make count 0.;
      } in
      let colors =
        Option.map (fun _ -> Array.make count Color.white) mesh.colors
      and tex_coords =
        Option.map (fun _ -> Array.make count Vec2.zero) mesh.tex_coords
      in
      let emit face a b c =
          let offset = face * 3 in
          let ax = mesh.vertices.x.(a) and ay = mesh.vertices.y.(a)
          and az = mesh.vertices.z.(a)
          and bx = mesh.vertices.x.(b) and by = mesh.vertices.y.(b)
          and bz = mesh.vertices.z.(b)
          and cx = mesh.vertices.x.(c) and cy = mesh.vertices.y.(c)
          and cz = mesh.vertices.z.(c) in
          let abx = bx -. ax and aby = by -. ay and abz = bz -. az
          and acx = cx -. ax and acy = cy -. ay and acz = cz -. az in
          let nx = aby *. acz -. abz *. acy
          and ny = abz *. acx -. abx *. acz
          and nz = abx *. acy -. aby *. acx in
          let length = sqrt ((nx *. nx) +. (ny *. ny) +. (nz *. nz)) in
          let nx, ny, nz =
            if length <= 1e-18 then 0., 0., 0.
            else nx /. length, ny /. length, nz /. length in
          vertices.x.(offset) <- ax; vertices.y.(offset) <- ay; vertices.z.(offset) <- az;
          vertices.x.(offset + 1) <- bx; vertices.y.(offset + 1) <- by; vertices.z.(offset + 1) <- bz;
          vertices.x.(offset + 2) <- cx; vertices.y.(offset + 2) <- cy; vertices.z.(offset + 2) <- cz;
          for index = offset to offset + 2 do
            normals.x.(index) <- nx;
            normals.y.(index) <- ny;
            normals.z.(index) <- nz
          done;
          (match mesh.colors, colors with
           | Some source, Some target ->
               target.(offset) <- source.(a);
               target.(offset + 1) <- source.(b);
               target.(offset + 2) <- source.(c)
           | _ -> ());
          (match mesh.tex_coords, tex_coords with
           | Some source, Some target ->
               target.(offset) <- source.(a);
               target.(offset + 1) <- source.(b);
               target.(offset + 2) <- source.(c)
           | _ -> ())
      in
      let values = mesh.indices in
      (match mesh.mode with
       | Triangles ->
           for face = 0 to face_count - 1 do
             let offset = face * 3 in
             emit face values.(offset) values.(offset + 1) values.(offset + 2)
           done
       | Triangle_strip ->
           for face = 0 to face_count - 1 do
             if face land 1 = 0 then
               emit face values.(face) values.(face + 1) values.(face + 2)
             else emit face values.(face + 1) values.(face) values.(face + 2)
           done
       | Triangle_fan ->
           for face = 0 to face_count - 1 do
             emit face values.(0) values.(face + 1) values.(face + 2)
           done
       | Points | Lines | Line_strip | Line_loop -> assert false);
      {
        mode = Triangles;
        vertices;
        indices = Array.init count Fun.id;
        normals = Some normals;
        colors;
        tex_coords;
      }

let append left right =
  if left.mode <> right.mode then
    Error "Mesh.append: primitive modes must match"
  else
    let combine_optional name left_values right_values =
      match left_values, right_values with
      | None, None -> Ok None
      | Some left_values, Some right_values ->
          let left_count = Array.length left_values
          and right_count = Array.length right_values in
          let output =
            if left_count = 0 then Array.copy right_values
            else if right_count = 0 then Array.copy left_values
            else begin
              let output = Array.make (left_count + right_count) left_values.(0) in
              Array.blit left_values 0 output 0 left_count;
              Array.blit right_values 0 output left_count right_count;
              output
            end in
          Ok (Some output)
      | _ -> Error ("Mesh.append: both meshes must have " ^ name)
    in
    let combine_vec3_optional name left_values right_values =
      match left_values, right_values with
      | None, None -> Ok None
      | Some left_values, Some right_values ->
          Ok (Some (Vec3_buffer.append left_values right_values))
      | _ -> Error ("Mesh.append: both meshes must have " ^ name)
    in
    match
      combine_vec3_optional "normals" left.normals right.normals,
      combine_optional "colors" left.colors right.colors,
      combine_optional "texture coordinates" left.tex_coords right.tex_coords
    with
    | Ok normals, Ok colors, Ok tex_coords ->
        let offset = Vec3_buffer.length left.vertices in
        let vertices = Vec3_buffer.append left.vertices right.vertices in
        let left_indices = Array.length left.indices in
        let indices = Array.make (left_indices + Array.length right.indices) 0 in
        Array.blit left.indices 0 indices 0 left_indices;
        Array.iteri (fun index value ->
          indices.(left_indices + index) <- value + offset) right.indices;
        Ok {
          mode = left.mode;
          vertices;
          indices;
          normals;
          colors;
          tex_coords;
        }
    | Error message, _, _ | _, Error message, _ | _, _, Error message ->
        Error message

let positive name value =
  if not (Float.is_finite value) || value <= 0. then
    invalid_arg ("Mesh." ^ name ^ ": dimensions must be finite and positive")

let require_segments name minimum value =
  if value < minimum then
    invalid_arg
      (Printf.sprintf "Mesh.%s: resolution must be at least %d" name minimum)

let plane ?(columns = 1) ?(rows = 1) ~width ~height () =
  positive "plane" width;
  positive "plane" height;
  require_segments "plane" 1 columns;
  require_segments "plane" 1 rows;
  let row_width = columns + 1 in
  let vertex_count = row_width * (rows + 1) in
  let vertices = Array.make vertex_count Vec3.zero
  and normals = Array.make vertex_count Vec3.unit_z
  and tex_coords = Array.make vertex_count Vec2.zero in
  Parallel.for_ ~chunk_size:4096 ~start:0 ~finish:(vertex_count - 1)
    (fun index ->
      let row = index / row_width and column = index mod row_width in
      let u = float_of_int column /. float_of_int columns
      and v = float_of_int row /. float_of_int rows in
      vertices.(index) <- Vec3.create ((u -. 0.5) *. width) ((v -. 0.5) *. height) 0.;
      tex_coords.(index) <- Vec2.create u (1. -. v));
  let cell_count = columns * rows in
  let indices = Array.make (cell_count * 6) 0 in
  Parallel.for_ ~chunk_size:4096 ~start:0 ~finish:(cell_count - 1)
    (fun cell ->
      let row = cell / columns and column = cell mod columns in
      let a = row * row_width + column in
      let b = a + 1 and d = a + row_width in
      let c = d + 1 and output = cell * 6 in
      indices.(output) <- a; indices.(output+1) <- b; indices.(output+2) <- c;
      indices.(output+3) <- a; indices.(output+4) <- c; indices.(output+5) <- d);
  match create_owned ~indices ~normals ~tex_coords vertices with
  | Ok mesh -> mesh | Error message -> invalid_arg message

let append_exn left right =
  match append left right with
  | Ok mesh -> mesh
  | Error message -> invalid_arg message

let concat_exn meshes =
  match meshes with
  | [] -> invalid_arg "Mesh.concat: at least one mesh is required"
  | first :: _ ->
      let require_attribute name accessor =
        let present = Option.is_some (accessor first) in
        if List.exists (fun mesh -> Option.is_some (accessor mesh) <> present)
            meshes
        then invalid_arg ("Mesh.concat: every mesh must agree on " ^ name);
        present in
      if List.exists (fun mesh -> mesh.mode <> first.mode) meshes then
        invalid_arg "Mesh.concat: primitive modes must match";
      let has_normals = require_attribute "normals" (fun mesh -> mesh.normals)
      and has_colors = require_attribute "colors" (fun mesh -> mesh.colors)
      and has_tex_coords =
        require_attribute "texture coordinates" (fun mesh -> mesh.tex_coords) in
      let vertex_count = List.fold_left (fun total mesh ->
          total + Vec3_buffer.length mesh.vertices) 0 meshes
      and index_count = List.fold_left (fun total mesh ->
          total + Array.length mesh.indices) 0 meshes in
      if vertex_count = 0 then first
      else
        let make_vec3_buffer () = {
          Vec3_buffer.x = Array.make vertex_count 0.;
          y = Array.make vertex_count 0.;
          z = Array.make vertex_count 0.;
        } in
        let vertices = make_vec3_buffer ()
        and indices = Array.make index_count 0
        and normals = if has_normals then Some (make_vec3_buffer ())
          else None
        and colors = if has_colors then Some (Array.make vertex_count Color.white)
          else None
        and tex_coords = if has_tex_coords then
            Some (Array.make vertex_count Vec2.zero) else None in
        let vertex_offset = ref 0 and index_offset = ref 0 in
        List.iter (fun mesh ->
          let vertices_length = Vec3_buffer.length mesh.vertices
          and indices_length = Array.length mesh.indices in
          Vec3_buffer.blit mesh.vertices 0 vertices !vertex_offset vertices_length;
          Array.iteri (fun index value ->
            indices.(!index_offset + index) <- value + !vertex_offset)
            mesh.indices;
          (match normals, mesh.normals with
           | Some output, Some input ->
               Vec3_buffer.blit input 0 output !vertex_offset vertices_length
           | _ -> ());
          (match colors, mesh.colors with
           | Some output, Some input ->
               Array.blit input 0 output !vertex_offset vertices_length
           | _ -> ());
          (match tex_coords, mesh.tex_coords with
           | Some output, Some input ->
               Array.blit input 0 output !vertex_offset vertices_length
           | _ -> ());
          vertex_offset := !vertex_offset + vertices_length;
          index_offset := !index_offset + indices_length) meshes;
        { mode = first.mode; vertices; indices; normals; colors; tex_coords }

let transformed_plane ~normal ~center ~width ~height ~columns ~rows =
  let base = plane ~columns ~rows ~width ~height () in
  let rotation =
    if Vec3.nearly_equal normal Vec3.unit_z ~eps:1e-9 then Mat4.identity
    else if Vec3.nearly_equal normal (Vec3.neg Vec3.unit_z) ~eps:1e-9 then
      Mat4.rotation_x Float.pi
    else
      let axis = Vec3.normalize (Vec3.cross Vec3.unit_z normal) in
      let angle =
        acos (Float.max (-1.) (Float.min 1. (Vec3.dot Vec3.unit_z normal)))
      in
      Mat4.rotation ~axis angle
  in
  transformed (Mat4.mul (Mat4.translation center) rotation) base

let box_side ?(x_segments = 1) ?(y_segments = 1) ?(z_segments = 1)
    ~side ~width ~height ~depth () =
  positive "box_side" width;
  positive "box_side" height;
  positive "box_side" depth;
  require_segments "box_side" 1 x_segments;
  require_segments "box_side" 1 y_segments;
  require_segments "box_side" 1 z_segments;
  match side with
  | Positive_x ->
      transformed_plane ~normal:Vec3.unit_x
        ~center:(Vec3.create (width /. 2.) 0. 0.)
        ~width:depth ~height ~columns:z_segments ~rows:y_segments
  | Negative_x ->
      transformed_plane ~normal:(Vec3.neg Vec3.unit_x)
        ~center:(Vec3.create (-.width /. 2.) 0. 0.)
        ~width:depth ~height ~columns:z_segments ~rows:y_segments
  | Positive_y ->
      transformed_plane ~normal:Vec3.unit_y
        ~center:(Vec3.create 0. (height /. 2.) 0.)
        ~width ~height:depth ~columns:x_segments ~rows:z_segments
  | Negative_y ->
      transformed_plane ~normal:(Vec3.neg Vec3.unit_y)
        ~center:(Vec3.create 0. (-.height /. 2.) 0.)
        ~width ~height:depth ~columns:x_segments ~rows:z_segments
  | Positive_z ->
      transformed_plane ~normal:Vec3.unit_z
        ~center:(Vec3.create 0. 0. (depth /. 2.))
        ~width ~height ~columns:x_segments ~rows:y_segments
  | Negative_z ->
      transformed_plane ~normal:(Vec3.neg Vec3.unit_z)
        ~center:(Vec3.create 0. 0. (-.depth /. 2.))
        ~width ~height ~columns:x_segments ~rows:y_segments

let box ?(x_segments = 1) ?(y_segments = 1) ?(z_segments = 1)
    ~width ~height ~depth () =
  let make side =
    box_side ~x_segments ~y_segments ~z_segments
      ~side ~width ~height ~depth ()
  in
  concat_exn (List.map make
    [Positive_x; Negative_x; Positive_y; Negative_y; Positive_z; Negative_z])

let sphere ?(segments = 24) ?(rings = 16) ~radius () =
  positive "sphere" radius;
  require_segments "sphere" 3 segments;
  require_segments "sphere" 2 rings;
  let row_width = segments + 1 in
  let vertex_count = row_width * (rings + 1) in
  let vertices = Array.make vertex_count Vec3.zero
  and normals = Array.make vertex_count Vec3.zero
  and tex_coords = Array.make vertex_count Vec2.zero in
  Parallel.for_ ~chunk_size:4096 ~start:0 ~finish:(vertex_count - 1)
    (fun index ->
      let latitude = index / row_width and longitude = index mod row_width in
      let u = float_of_int longitude /. float_of_int segments
      and v = float_of_int latitude /. float_of_int rings in
      let theta = u *. 2. *. Float.pi and phi = v *. Float.pi in
      let normal = Vec3.create (sin phi *. cos theta) (cos phi)
          (sin phi *. sin theta) in
      normals.(index) <- normal;
      vertices.(index) <- Vec3.scale normal radius;
      tex_coords.(index) <- Vec2.create u v);
  let cell_count = segments * rings in
  let indices = Array.make (cell_count * 6) 0 in
  Parallel.for_ ~chunk_size:4096 ~start:0 ~finish:(cell_count - 1)
    (fun cell ->
      let latitude = cell / segments and longitude = cell mod segments in
      let a = latitude * row_width + longitude in
      let b = a + 1 and d = a + row_width in
      let c = d + 1 and output = cell * 6 in
      indices.(output) <- a; indices.(output+1) <- b; indices.(output+2) <- c;
      indices.(output+3) <- a; indices.(output+4) <- c; indices.(output+5) <- d);
  match create_owned ~indices ~normals ~tex_coords vertices with
  | Ok mesh -> mesh | Error message -> invalid_arg message

let icosphere ?(subdivisions = 2) ~radius () =
  positive "icosphere" radius;
  if subdivisions < 0 || subdivisions > 6 then
    invalid_arg "Mesh.icosphere: subdivisions must be in 0..6";
  let golden = (1. +. sqrt 5.) /. 2. in
  let base_vertices =
    [|
      Vec3.create (-1.) golden 0.; Vec3.create 1. golden 0.;
      Vec3.create (-1.) (-.golden) 0.; Vec3.create 1. (-.golden) 0.;
      Vec3.create 0. (-1.) golden; Vec3.create 0. 1. golden;
      Vec3.create 0. (-1.) (-.golden); Vec3.create 0. 1. (-.golden);
      Vec3.create golden 0. (-1.); Vec3.create golden 0. 1.;
      Vec3.create (-.golden) 0. (-1.); Vec3.create (-.golden) 0. 1.;
    |]
    |> Array.map Vec3.normalize
  in
  let power4 = 1 lsl (subdivisions * 2) in
  let final_vertex_count = (10 * power4) + 2 in
  let vertices = Array.make final_vertex_count Vec3.zero in
  Array.blit base_vertices 0 vertices 0 (Array.length base_vertices);
  let vertex_count = ref (Array.length base_vertices) in
  let indices = ref [|
    0;11;5; 0;5;1; 0;1;7; 0;7;10; 0;10;11;
    1;5;9; 5;11;4; 11;10;2; 10;7;6; 7;1;8;
    3;9;4; 3;4;2; 3;2;6; 3;6;8; 3;8;9;
    4;9;5; 2;4;11; 6;2;10; 8;6;7; 9;8;1;
  |] in
  let module Edge_key = struct
    type t = int * int
    let equal (a0, b0) (a1, b1) = a0 = a1 && b0 = b1
    let hash (a, b) = ((a * 65599) lxor b) land max_int
  end in
  let module Edge_table = Hashtbl.Make (Edge_key) in
  for _ = 1 to subdivisions do
    let edge_count = Array.length !indices / 2 in
    let midpoints = Edge_table.create edge_count in
    let midpoint left right =
      let key = if left < right then left, right else right, left in
      match Edge_table.find_opt midpoints key with
      | Some index -> index
      | None ->
          let a = vertices.(left) and b = vertices.(right) in
          let x = a.x +. b.x and y = a.y +. b.y and z = a.z +. b.z in
          let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
          let index = !vertex_count in
          vertices.(index) <- Vec3.create (x /. length) (y /. length) (z /. length);
          incr vertex_count;
          Edge_table.add midpoints key index;
          index in
    let face_count = Array.length !indices / 3 in
    let output = Array.make (face_count * 12) 0 in
    for face = 0 to face_count - 1 do
      let source = face * 3 in
      let a = (!indices).(source) and b = (!indices).(source + 1)
      and c = (!indices).(source + 2) in
      let ab = midpoint a b and bc = midpoint b c and ca = midpoint c a in
      let target = face * 12 in
      output.(target) <- a; output.(target + 1) <- ab;
      output.(target + 2) <- ca;
      output.(target + 3) <- b; output.(target + 4) <- bc;
      output.(target + 5) <- ab;
      output.(target + 6) <- c; output.(target + 7) <- ca;
      output.(target + 8) <- bc;
      output.(target + 9) <- ab; output.(target + 10) <- bc;
      output.(target + 11) <- ca
    done;
    indices := output
  done;
  assert (!vertex_count = final_vertex_count);
  let normals = Array.copy vertices in
  let positions = Parallel.map_array ~grain:4096
      (fun vertex -> Vec3.scale vertex radius) vertices in
  match create_owned ~indices:!indices ~normals positions with
  | Ok mesh -> mesh
  | Error message -> invalid_arg message

let radial ?(height_segments = 1) ?(cap_segments = 2)
    ~name ~segments:segment_count ~capped ~radius ~height ~top_radius () =
  positive name radius;
  positive name height;
  require_segments name 3 segment_count;
  require_segments name 1 height_segments;
  require_segments name 1 cap_segments;
  let vertices = ref [] and normals = ref [] and tex_coords = ref [] in
  let slope = (radius -. top_radius) /. height in
  for row = 0 to height_segments do
    let v = float_of_int row /. float_of_int height_segments in
    let y = (v -. 0.5) *. height in
    let row_radius = radius +. ((top_radius -. radius) *. v) in
    for segment = 0 to segment_count do
      let u = float_of_int segment /. float_of_int segment_count in
      let angle = u *. 2. *. Float.pi in
      let cosine = cos angle and sine = sin angle in
      vertices := Vec3.create (row_radius *. cosine) y (row_radius *. sine)
        :: !vertices;
      normals := Vec3.normalize (Vec3.create cosine slope sine) :: !normals;
      tex_coords := Vec2.create u (1. -. v) :: !tex_coords
    done
  done;
  let vertex_index segment row =
    (row * (segment_count + 1)) + segment
  in
  let indices = ref [] in
  for row = 0 to height_segments - 1 do
    for segment = 0 to segment_count - 1 do
      let a = vertex_index segment row
      and b = vertex_index (segment + 1) row
      and c = vertex_index (segment + 1) (row + 1)
      and d = vertex_index segment (row + 1) in
      indices := c :: d :: a :: b :: c :: a :: !indices
    done
  done;
  let side =
    create_exn ~indices:(List.rev !indices)
      ~normals:(List.rev !normals) ~tex_coords:(List.rev !tex_coords)
      (List.rev !vertices)
  in
  if not capped then side
  else
    let cap ~y ~cap_radius ~normal =
      if cap_radius <= 1e-12 then None
      else
        let vertices = ref [Vec3.create 0. y 0.]
        and normals = ref [normal]
        and tex_coords = ref [Vec2.create 0.5 0.5] in
        for ring = 1 to cap_segments do
          let ring_radius =
            cap_radius *. float_of_int ring /. float_of_int cap_segments
          in
          for segment = 0 to segment_count do
            let amount =
              float_of_int segment /. float_of_int segment_count
            in
            let angle = amount *. 2. *. Float.pi in
            vertices :=
              Vec3.create
                (ring_radius *. cos angle) y (ring_radius *. sin angle)
              :: !vertices;
            normals := normal :: !normals;
            let uv_radius =
              float_of_int ring /. float_of_int cap_segments /. 2.
            in
            tex_coords :=
              Vec2.create
                (0.5 +. (uv_radius *. cos angle))
                (0.5 +. (uv_radius *. sin angle))
              :: !tex_coords
          done
        done;
        let indices = ref [] in
        let ring_index ring segment =
          1 + ((ring - 1) * (segment_count + 1)) + segment
        in
        for segment = 0 to segment_count - 1 do
          if normal.Vec3.y > 0. then
            indices :=
              ring_index 1 segment
              :: ring_index 1 (segment + 1)
              :: 0 :: !indices
          else
            indices :=
              ring_index 1 (segment + 1)
              :: ring_index 1 segment
              :: 0 :: !indices
        done;
        for ring = 2 to cap_segments do
          for segment = 0 to segment_count - 1 do
            let inner_a = ring_index (ring - 1) segment
            and inner_b = ring_index (ring - 1) (segment + 1)
            and outer_a = ring_index ring segment
            and outer_b = ring_index ring (segment + 1) in
            if normal.Vec3.y > 0. then
              indices :=
                outer_a :: outer_b :: inner_a
                :: inner_b :: inner_a :: outer_b :: !indices
            else
              indices :=
                outer_b :: outer_a :: inner_a
                :: inner_a :: inner_b :: outer_b :: !indices
          done
        done;
        Some
          (create_exn ~indices:(List.rev !indices)
             ~normals:(List.rev !normals)
             ~tex_coords:(List.rev !tex_coords)
             (List.rev !vertices))
    in
    let caps =
      [
        cap ~y:(-.height /. 2.) ~cap_radius:radius
          ~normal:(Vec3.neg Vec3.unit_y);
        cap ~y:(height /. 2.) ~cap_radius:top_radius ~normal:Vec3.unit_y;
      ]
      |> List.filter_map Fun.id
    in
    List.fold_left append_exn side caps

let cylinder ?(segments = 24) ?(height_segments = 1) ?(cap_segments = 2)
    ?(capped = true) ~radius ~height () =
  radial ~name:"cylinder" ~segments ~height_segments ~cap_segments ~capped
    ~radius ~height ~top_radius:radius ()

let cone ?(segments = 24) ?(height_segments = 1) ?(cap_segments = 2)
    ?(capped = true) ~radius ~height () =
  radial ~name:"cone" ~segments ~height_segments ~cap_segments ~capped
    ~radius ~height ~top_radius:0. ()

module Private = struct
  type vec3_view = Vec3_buffer.t = {
    x : float array;
    y : float array;
    z : float array;
  }

  type view = {
    mode : mode;
    vertices : Vec3.t array;
    indices : int array;
    normals : Vec3.t array option;
    colors : Color.t array option;
    tex_coords : Vec2.t array option;
  }

  let view (mesh : t) = {
    mode = mesh.mode;
    vertices = Vec3_buffer.to_array mesh.vertices;
    indices = mesh.indices;
    normals = Option.map Vec3_buffer.to_array mesh.normals;
    colors = mesh.colors;
    tex_coords = mesh.tex_coords;
  }

  type packed_view = {
    mode : mode;
    vertices : vec3_view;
    indices : int array;
    normals : vec3_view option;
    colors : Color.t array option;
    tex_coords : Vec2.t array option;
  }

  let packed_view (mesh : t) = {
    mode = mesh.mode;
    vertices = mesh.vertices;
    indices = mesh.indices;
    normals = mesh.normals;
    colors = mesh.colors;
    tex_coords = mesh.tex_coords;
  }

  let create_owned = create_owned
  let create_packed_owned = create_packed_owned
  let create_packed_shared = create_packed_owned

  let triangle_count (mesh : t) =
    match mesh.mode with
    | Triangles -> Array.length mesh.indices / 3
    | Triangle_strip | Triangle_fan -> max 0 (Array.length mesh.indices - 2)
    | Points | Lines | Line_strip | Line_loop -> 0

end
