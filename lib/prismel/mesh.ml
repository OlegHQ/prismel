type mode =
  | Points
  | Lines
  | Line_strip
  | Line_loop
  | Triangles
  | Triangle_strip
  | Triangle_fan

type grid_plane = XY | XZ | YZ
type box_side =
  | Positive_x
  | Negative_x
  | Positive_y
  | Negative_y
  | Positive_z
  | Negative_z

type ply_format =
  | Ply_ascii
  | Ply_binary_little_endian
  | Ply_binary_big_endian

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

  let map ?parallel operation values =
    init ?parallel (length values) (fun index -> operation (get values index))

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

  let select values sources =
    init (Array.length sources) (fun index -> get values sources.(index))

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

let with_color_for_indices ~first ~count color mesh =
  if first < 0 || count < 0 || first + count > Array.length mesh.indices then
    Error
      "Mesh.with_color_for_indices: range is outside the index buffer"
  else
    let colors =
      match mesh.colors with
      | Some colors -> Array.copy colors
      | None -> Array.make (Vec3_buffer.length mesh.vertices) Color.white
    in
    for position = first to first + count - 1 do
      colors.(mesh.indices.(position)) <- color
    done;
    Ok { mesh with colors = Some colors }

let remove_at name index values =
  let count = Array.length values in
  if index < 0 || index >= count then
    Error (Printf.sprintf "Mesh.remove_%s: index %d is out of range" name index)
  else
    Ok
      (Array.init (count - 1) (fun target ->
         values.(if target < index then target else target + 1)))

let remove_index index mesh =
  remove_at "index" index mesh.indices
  |> Result.map (fun indices -> { mesh with indices })

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

let map_vertices transform mesh =
  { mesh with vertices = Vec3_buffer.map ~parallel:true transform mesh.vertices }

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

let submesh ~first ~count mesh =
  if first < 0 || count < 0 || first + count > Array.length mesh.indices then
    Error "Mesh.submesh: index range is outside the mesh index buffer"
  else
    let selected = Array.sub mesh.indices first count in
    let remap = Hashtbl.create (Array.length selected) in
    let source_indices = ref [] in
    let compact_index source =
      match Hashtbl.find_opt remap source with
      | Some index -> index
      | None ->
          let index = Hashtbl.length remap in
          Hashtbl.add remap source index;
          source_indices := source :: !source_indices;
          index
    in
    let indices = Array.map compact_index selected in
    let source_indices = Array.of_list (List.rev !source_indices) in
    let select values = Array.map (Array.get values) source_indices in
    Ok {
      mode = mesh.mode;
      vertices = Vec3_buffer.select mesh.vertices source_indices;
      indices;
      normals = Option.map (Fun.flip Vec3_buffer.select source_indices) mesh.normals;
      colors = Option.map select mesh.colors;
      tex_coords = Option.map select mesh.tex_coords;
    }

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

let smooth_normals ?(angle = Float.pi) mesh =
  if not (Float.is_finite angle) || angle < 0. || angle > Float.pi then
    invalid_arg "Mesh.smooth_normals: angle must be finite and in [0, pi]";
  let index_count = Array.length mesh.indices in
  let face_count =
    match mesh.mode with
    | Triangles -> index_count / 3
    | Triangle_strip | Triangle_fan -> max 0 (index_count - 2)
    | Points | Lines | Line_strip | Line_loop -> 0
  in
  if face_count = 0 then recalculate_normals mesh
  else
    let threshold = cos angle -. 1e-12 in
    let vertex_group_head = Array.make (Vec3_buffer.length mesh.vertices) (-1) in
    let maximum_groups = face_count * 3 in
    let initial_groups =
      min maximum_groups (max 16 (Vec3_buffer.length mesh.vertices))
    in
    let group_head = ref (Array.make initial_groups (-1))
    and group_next = ref (Array.make initial_groups (-1))
    and group_sources = ref (Array.make initial_groups 0)
    and group_sum_x = ref (Array.make initial_groups 0.)
    and group_sum_y = ref (Array.make initial_groups 0.)
    and group_sum_z = ref (Array.make initial_groups 0.)
    and member_face = Array.make maximum_groups 0
    and member_next = Array.make maximum_groups (-1)
    and face_x = Array.make face_count 0.
    and face_y = Array.make face_count 0.
    and face_z = Array.make face_count 0.
    and indices = Array.make maximum_groups 0 in
    let group_count = ref 0 in
    let ensure_group_capacity () =
      if !group_count = Array.length !group_head then begin
        let old_length = Array.length !group_head in
        let length = min maximum_groups (max 1 (old_length * 2)) in
        let grow_int fill source =
          let output = Array.make length fill in
          Array.blit source 0 output 0 old_length;
          output
        and grow_float source =
          let output = Array.make length 0. in
          Array.blit source 0 output 0 old_length;
          output
        in
        group_head := grow_int (-1) !group_head;
        group_next := grow_int (-1) !group_next;
        group_sources := grow_int 0 !group_sources;
        group_sum_x := grow_float !group_sum_x;
        group_sum_y := grow_float !group_sum_y;
        group_sum_z := grow_float !group_sum_z
      end
    in
    let compatible face group =
      let normal_x = face_x.(face) and normal_y = face_y.(face)
      and normal_z = face_z.(face) in
      let member = ref (!group_head).(group) and result = ref true in
      while !result && !member >= 0 do
        let face = member_face.(!member) in
        result :=
          (face_x.(face) *. normal_x)
          +. (face_y.(face) *. normal_y)
          +. (face_z.(face) *. normal_z) >= threshold;
        member := member_next.(!member)
      done;
      !result
    in
    let find_group source face =
      let group = ref vertex_group_head.(source) and result = ref (-1) in
      while !result < 0 && !group >= 0 do
        if compatible face !group then result := !group
        else group := (!group_next).(!group)
      done;
      !result
    in
    let output_for source face member =
      let normal_x = face_x.(face) and normal_y = face_y.(face)
      and normal_z = face_z.(face) in
      let group = find_group source face in
      let group =
        if group >= 0 then begin
          (!group_sum_x).(group) <- (!group_sum_x).(group) +. normal_x;
          (!group_sum_y).(group) <- (!group_sum_y).(group) +. normal_y;
          (!group_sum_z).(group) <- (!group_sum_z).(group) +. normal_z;
          group
        end else begin
          ensure_group_capacity ();
          let group = !group_count in
          incr group_count;
          (!group_sources).(group) <- source;
          (!group_sum_x).(group) <- normal_x;
          (!group_sum_y).(group) <- normal_y;
          (!group_sum_z).(group) <- normal_z;
          (!group_next).(group) <- vertex_group_head.(source);
          vertex_group_head.(source) <- group;
          group
        end
      in
      member_face.(member) <- face;
      member_next.(member) <- (!group_head).(group);
      (!group_head).(group) <- member;
      group
    in
    let emit face a b c =
        let abx = mesh.vertices.x.(b) -. mesh.vertices.x.(a)
        and aby = mesh.vertices.y.(b) -. mesh.vertices.y.(a)
        and abz = mesh.vertices.z.(b) -. mesh.vertices.z.(a)
        and acx = mesh.vertices.x.(c) -. mesh.vertices.x.(a)
        and acy = mesh.vertices.y.(c) -. mesh.vertices.y.(a)
        and acz = mesh.vertices.z.(c) -. mesh.vertices.z.(a) in
        let nx = aby *. acz -. abz *. acy
        and ny = abz *. acx -. abx *. acz
        and nz = abx *. acy -. aby *. acx in
        let length = sqrt ((nx *. nx) +. (ny *. ny) +. (nz *. nz)) in
        let nx, ny, nz =
          if length <= 1e-18 then 0., 0., 0.
          else nx /. length, ny /. length, nz /. length in
        face_x.(face) <- nx;
        face_y.(face) <- ny;
        face_z.(face) <- nz;
        let offset = face * 3 in
        indices.(offset) <- output_for a face offset;
        indices.(offset + 1) <- output_for b face (offset + 1);
        indices.(offset + 2) <- output_for c face (offset + 2)
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
    let select values =
      Array.init !group_count (fun group -> values.((!group_sources).(group)))
    in
    let sources = Array.init !group_count (fun group -> (!group_sources).(group)) in
    let normals = Vec3_buffer.init !group_count (fun group ->
      let x = (!group_sum_x).(group) and y = (!group_sum_y).(group)
      and z = (!group_sum_z).(group) in
      let length = sqrt ((x *. x) +. (y *. y) +. (z *. z)) in
      if length <= 1e-18 then Vec3.zero
      else Vec3.create (x /. length) (y /. length) (z /. length)) in
    {
      mode = Triangles;
      vertices = Vec3_buffer.select mesh.vertices sources;
      indices;
      normals = Some normals;
      colors = Option.map select mesh.colors;
      tex_coords = Option.map select mesh.tex_coords;
    }

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

let merge_duplicate_vertices ?(epsilon = 0.) mesh =
  if not (Float.is_finite epsilon) || epsilon < 0. then
    invalid_arg
      "Mesh.merge_duplicate_vertices: epsilon must be finite and non-negative";
  let optional_equal equal values left right =
    match values with
    | None -> true
    | Some values -> equal values.(left) values.(right)
  in
  let vec3_equal left right =
    if epsilon = 0. then left = right
    else Vec3.nearly_equal left right ~eps:epsilon
  and vec2_equal left right =
    if epsilon = 0. then left = right
    else Vec2.nearly_equal left right ~eps:epsilon
  in
  let vec3_buffer_equal values left right =
    let left = Vec3_buffer.get values left
    and right = Vec3_buffer.get values right in
    vec3_equal left right in
  let equivalent left right =
    vec3_buffer_equal mesh.vertices left right
    && (match mesh.normals with
        | None -> true
        | Some values -> vec3_buffer_equal values left right)
    && optional_equal Color.equal mesh.colors left right
    && optional_equal
         vec2_equal mesh.tex_coords left right
  in
  let count = Vec3_buffer.length mesh.vertices in
  let representatives = Array.make count (-1) in
  let sources = ref [] in
  let accept source candidates =
    List.fold_left
      (fun found candidate ->
        if equivalent source candidate
           && (found < 0 || candidate < found)
        then candidate else found)
      (-1) candidates
  in
  if epsilon = 0. then begin
    let buckets = Hashtbl.create (max 16 (count / 2)) in
    for source = 0 to count - 1 do
      let point = Vec3_buffer.get mesh.vertices source in
      let key = point.Vec3.x, point.y, point.z in
      let candidates = Option.value ~default:[] (Hashtbl.find_opt buckets key) in
      let representative = accept source candidates in
      if representative >= 0 then representatives.(source) <- representative
      else begin
        representatives.(source) <- source;
        sources := source :: !sources;
        Hashtbl.replace buckets key (source :: candidates)
      end
    done
  end else begin
    let required_capacity = max 16 (count * 2) in
    let rec power_of_two capacity =
      if capacity >= required_capacity then capacity
      else power_of_two (capacity * 2)
    in
    let capacity = power_of_two 16 in
    let table_mask = capacity - 1 in
    let occupied = Bytes.make capacity '\000'
    and keys_x = Array.make capacity 0
    and keys_y = Array.make capacity 0
    and keys_z = Array.make capacity 0
    and heads = Array.make capacity (-1)
    and next = Array.make count (-1) in
    let hash_cell x y z =
      let hash =
        (x * 0x1e35a7bd)
        lxor (y * 0x0f27bb2d)
        lxor (z * 0x087fc72d)
      in
      (hash lxor (hash lsr 23)) land table_mask
    in
    let find_slot x y z =
      let slot = ref (hash_cell x y z) in
      while
        Bytes.unsafe_get occupied !slot <> '\000'
        && (Array.unsafe_get keys_x !slot <> x
            || Array.unsafe_get keys_y !slot <> y
            || Array.unsafe_get keys_z !slot <> z)
      do
        slot := (!slot + 1) land table_mask
      done;
      !slot
    in
    let accept_chain source head =
      let candidate = ref head and found = ref (-1) in
      while !candidate >= 0 do
        if equivalent source !candidate
           && (!found < 0 || !candidate < !found)
        then found := !candidate;
        candidate := Array.unsafe_get next !candidate
      done;
      !found
    in
    (* This secondary table is only used when a coordinate/epsilon ratio is
       too large to quantize safely into an OCaml integer. *)
    let extreme_buckets = Hashtbl.create 16 in
    (* Coordinates whose cell index is too large for a precise, overflow-safe
       [int64] cannot have a distinct representable neighbour within
       [epsilon]: at that magnitude epsilon is already far below one float
       ulp. Key that component by its exact bits while continuing to hash the
       other components normally. Canonicalize signed zero because the
       equivalence predicate does too. *)
    let cell coordinate =
      let scaled = coordinate /. epsilon in
      if Float.is_finite scaled && abs_float scaled < 0x1p60 then
        false, int_of_float (floor scaled), 0L
      else
        true, 0,
        (if coordinate = 0. then 0L else Int64.bits_of_float coordinate)
    in
    for source = 0 to count - 1 do
      let point = Vec3_buffer.get mesh.vertices source in
      if not (Float.is_finite point.x && Float.is_finite point.y
              && Float.is_finite point.z)
      then begin
        representatives.(source) <- source;
        sources := source :: !sources
      end else begin
        let exact_x, cx, bits_x = cell point.x
        and exact_y, cy, bits_y = cell point.y
        and exact_z, cz, bits_z = cell point.z in
        let mask =
          (if exact_x then 1 else 0)
          lor (if exact_y then 2 else 0)
          lor (if exact_z then 4 else 0)
        in
        let representative = ref (-1) in
        if mask = 0 then begin
          for dx = -1 to 1 do
            for dy = -1 to 1 do
              for dz = -1 to 1 do
                let slot = find_slot (cx + dx) (cy + dy) (cz + dz) in
                if Bytes.unsafe_get occupied slot <> '\000' then begin
                  let candidate = accept_chain source (Array.unsafe_get heads slot) in
                  if candidate >= 0
                     && (!representative < 0 || candidate < !representative)
                  then representative := candidate
                end
              done
            done
          done
        end else begin
          let component exact cell bits delta =
            if exact then bits else Int64.of_int (cell + delta)
          in
          for dx = (if exact_x then 0 else -1)
            to (if exact_x then 0 else 1) do
            for dy = (if exact_y then 0 else -1)
              to (if exact_y then 0 else 1) do
              for dz = (if exact_z then 0 else -1)
                to (if exact_z then 0 else 1) do
                let key =
                  mask,
                  component exact_x cx bits_x dx,
                  component exact_y cy bits_y dy,
                  component exact_z cz bits_z dz
                in
                match Hashtbl.find_opt extreme_buckets key with
                | None -> ()
                | Some candidates ->
                    let candidate = accept source candidates in
                    if candidate >= 0
                       && (!representative < 0 || candidate < !representative)
                    then representative := candidate
              done
            done
          done
        end;
        if !representative >= 0 then
          representatives.(source) <- !representative
        else begin
          representatives.(source) <- source;
          sources := source :: !sources;
          if mask = 0 then begin
            let slot = find_slot cx cy cz in
            if Bytes.unsafe_get occupied slot = '\000' then begin
              Bytes.unsafe_set occupied slot '\001';
              Array.unsafe_set keys_x slot cx;
              Array.unsafe_set keys_y slot cy;
              Array.unsafe_set keys_z slot cz
            end;
            Array.unsafe_set next source (Array.unsafe_get heads slot);
            Array.unsafe_set heads slot source
          end else begin
            let component exact cell bits =
              if exact then bits else Int64.of_int cell
            in
            let key =
              mask,
              component exact_x cx bits_x,
              component exact_y cy bits_y,
              component exact_z cz bits_z
            in
            let candidates =
              Option.value ~default:[] (Hashtbl.find_opt extreme_buckets key)
            in
            Hashtbl.replace extreme_buckets key (source :: candidates)
          end
        end
      end
    done
  end;
  let compact = Array.make count (-1) in
  List.rev !sources
  |> List.iteri (fun index source -> compact.(source) <- index);
  let remap source = compact.(representatives.(source)) in
  let sources = Array.of_list (List.rev !sources) in
  let select values = Array.map (Array.get values) sources in
  {
    mesh with
    vertices = Vec3_buffer.select mesh.vertices sources;
    indices = Array.map remap mesh.indices;
    normals = Option.map (Fun.flip Vec3_buffer.select sources) mesh.normals;
    colors = Option.map select mesh.colors;
    tex_coords = Option.map select mesh.tex_coords;
  }

let remap_tex_coords ~u1 ~v1 ~u2 ~v2 mesh =
  if
    not
      (List.for_all Float.is_finite [u1; v1; u2; v2])
  then Error "Mesh.remap_tex_coords: bounds must be finite"
  else
    match mesh.tex_coords with
    | None -> Error "Mesh.remap_tex_coords: mesh has no texture coordinates"
    | Some tex_coords ->
        let width = u2 -. u1 and height = v2 -. v1 in
        Ok {
          mesh with
          tex_coords =
            Some
              (Array.map
                 (fun uv ->
                   Vec2.create
                     (u1 +. (uv.Vec2.x *. width))
                     (v1 +. (uv.y *. height)))
                 tex_coords);
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

let icosahedron ~radius = icosphere ~subdivisions:0 ~radius ()

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

let axis ~size =
  positive "axis" size;
  create_exn ~mode:Lines
    ~colors:[
      Color.red; Color.red;
      Color.green; Color.green;
      Color.blue; Color.blue;
    ]
    [
      Vec3.zero; Vec3.create size 0. 0.;
      Vec3.zero; Vec3.create 0. size 0.;
      Vec3.zero; Vec3.create 0. 0. size;
    ]

let grid ?(divisions = 10) ~size () =
  positive "grid" size;
  require_segments "grid" 1 divisions;
  let half = size /. 2. in
  let vertices = ref [] in
  for division = 0 to divisions do
    let amount = float_of_int division /. float_of_int divisions in
    let coordinate = (-.half) +. (amount *. size) in
    vertices :=
      Vec3.create (-.half) 0. coordinate
      :: Vec3.create half 0. coordinate
      :: Vec3.create coordinate 0. (-.half)
      :: Vec3.create coordinate 0. half
      :: !vertices
  done;
  create_exn ~mode:Lines (List.rev !vertices)

let grid_plane ?divisions ~plane ~size () =
  let grid = grid ?divisions ~size () in
  match plane with
  | XZ -> grid
  | XY -> transformed (Mat4.rotation_x (Float.pi /. 2.)) grid
  | YZ -> transformed (Mat4.rotation_z (Float.pi /. 2.)) grid

let rotation_axes ?(segments = 64) ~radius () =
  positive "rotation_axes" radius;
  require_segments "rotation_axes" 3 segments;
  let vertices = ref [] and colors = ref [] in
  let ring color point =
    for segment = 0 to segments - 1 do
      let angle_a =
        float_of_int segment /. float_of_int segments *. 2. *. Float.pi
      and angle_b =
        float_of_int (segment + 1) /. float_of_int segments
        *. 2. *. Float.pi
      in
      vertices := point angle_b :: point angle_a :: !vertices;
      colors := color :: color :: !colors
    done
  in
  ring Color.red (fun angle ->
    Vec3.create 0. (radius *. cos angle) (radius *. sin angle));
  ring Color.green (fun angle ->
    Vec3.create (radius *. cos angle) 0. (radius *. sin angle));
  ring Color.blue (fun angle ->
    Vec3.create (radius *. cos angle) (radius *. sin angle) 0.);
  create_exn ~mode:Lines
    ~colors:(List.rev !colors) (List.rev !vertices)

let rotation_from_y direction =
  let direction = Vec3.normalize direction in
  let cosine =
    Float.max (-1.) (Float.min 1. (Vec3.dot Vec3.unit_y direction))
  in
  if cosine > 1. -. 1e-9 then Mat4.identity
  else if cosine < (-1. +. 1e-9) then Mat4.rotation_x Float.pi
  else
    Mat4.rotation
      ~axis:(Vec3.normalize (Vec3.cross Vec3.unit_y direction))
      (acos cosine)

let arrow ~from_ ~to_ ~head_size =
  if not (Float.is_finite head_size) || head_size <= 0. then
    invalid_arg "Mesh.arrow: head_size must be finite and positive";
  let delta = Vec3.sub to_ from_ in
  let length = Vec3.length delta in
  if length <= 1e-12 then
    invalid_arg "Mesh.arrow: endpoints must differ";
  let direction = Vec3.normalize delta in
  let head_length = min head_size (length *. 0.8) in
  let shaft_length = length -. head_length in
  let rotation = rotation_from_y direction in
  let place distance =
    Mat4.mul
      (Mat4.translation
         (Vec3.add from_ (Vec3.scale direction distance)))
      rotation
  in
  let head =
    cone ~segments:12 ~radius:(head_length *. 0.45)
      ~height:head_length ()
    |> transformed (place (shaft_length +. (head_length /. 2.)))
  in
  if shaft_length <= 1e-9 then head
  else
    let shaft =
      cylinder ~segments:12 ~radius:(head_length *. 0.12)
        ~height:shaft_length ()
      |> transformed (place (shaft_length /. 2.))
    in
    append_exn shaft head

let normal_lines ?(face_normals = false) ~length mesh =
  positive "normal_lines" length;
  if face_normals then
    let vertices =
      faces mesh
      |> List.concat_map (fun face ->
        let a, b, c = face.points in
        let center =
          Vec3.add a (Vec3.add b c) |> Fun.flip Vec3.scale (1. /. 3.)
        in
        [center; Vec3.add center (Vec3.scale face.face_normal length)])
    in
    create_exn ~mode:Lines
      ~colors:(List.map (Fun.const Color.cyan) vertices) vertices
  else
    let mesh =
      if has_normals mesh then mesh else recalculate_normals mesh
    in
    let normals = Option.get mesh.normals in
    let vertices =
      Array.to_list
        (Array.init (Vec3_buffer.length mesh.vertices * 2) (fun index ->
           let source = index / 2 in
           let vertex = Vec3_buffer.get mesh.vertices source in
           if index mod 2 = 0 then vertex
           else
             Vec3.add vertex
               (Vec3.scale (Vec3_buffer.get normals source) length)))
    in
    create_exn ~mode:Lines
      ~colors:(List.map (Fun.const Color.cyan) vertices) vertices

let obj_words line =
  let line =
    match String.index_opt line '#' with
    | None -> line
    | Some index -> String.sub line 0 index
  in
  String.map (fun character -> if character = '\t' then ' ' else character) line
  |> String.split_on_char ' '
  |> List.filter (fun value -> value <> "")

let obj_float line value =
  match float_of_string_opt value with
  | Some value when Float.is_finite value -> Ok value
  | _ ->
      Error
        (Printf.sprintf "Mesh.load_obj: line %d has invalid float %S"
           line value)

let obj_index line value =
  match int_of_string_opt value with
  | Some 0 | None ->
      Error
        (Printf.sprintf "Mesh.load_obj: line %d has invalid index %S"
           line value)
  | Some value -> Ok value

let obj_corner line value =
  match String.split_on_char '/' value with
  | [position] ->
      Result.map (fun position -> position, None, None)
        (obj_index line position)
  | [position; texture] ->
      (match obj_index line position, obj_index line texture with
       | Ok position, Ok texture -> Ok (position, Some texture, None)
       | Error message, _ | _, Error message -> Error message)
  | [position; ""; normal] ->
      (match obj_index line position, obj_index line normal with
       | Ok position, Ok normal -> Ok (position, None, Some normal)
       | Error message, _ | _, Error message -> Error message)
  | [position; texture; normal] ->
      (match
         obj_index line position,
         obj_index line texture,
         obj_index line normal
       with
       | Ok position, Ok texture, Ok normal ->
           Ok (position, Some texture, Some normal)
       | Error message, _, _
       | _, Error message, _
       | _, _, Error message -> Error message)
  | _ ->
      Error
        (Printf.sprintf "Mesh.load_obj: line %d has invalid face corner %S"
           line value)

let load_obj filename =
  try
    let channel = open_in filename in
    Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      let positions = ref [] and normals = ref [] and tex_coords = ref []
      and faces = ref [] and line_number = ref 0 and error = ref None in
      (try
         while true do
           incr line_number;
           let words = obj_words (input_line channel) in
           let fail message = if !error = None then error := Some message in
           match words with
           | [] | "#" :: _ -> ()
           | "v" :: x :: y :: z :: _ ->
               (match obj_float !line_number x, obj_float !line_number y,
                      obj_float !line_number z with
                | Ok x, Ok y, Ok z ->
                    positions := Vec3.create x y z :: !positions
                | Error message, _, _
                | _, Error message, _
                | _, _, Error message -> fail message)
           | "vn" :: x :: y :: z :: _ ->
               (match obj_float !line_number x, obj_float !line_number y,
                      obj_float !line_number z with
                | Ok x, Ok y, Ok z ->
                    normals := Vec3.create x y z :: !normals
                | Error message, _, _
                | _, Error message, _
                | _, _, Error message -> fail message)
           | "vt" :: u :: v :: _ ->
               (match obj_float !line_number u, obj_float !line_number v with
                | Ok u, Ok v -> tex_coords := Vec2.create u v :: !tex_coords
                | Error message, _ | _, Error message -> fail message)
           | "f" :: corners when List.length corners >= 3 ->
               let parsed =
                 List.fold_right
                   (fun value result ->
                     match obj_corner !line_number value, result with
                     | Ok corner, Ok corners -> Ok (corner :: corners)
                     | Error message, _ | _, Error message -> Error message)
                   corners (Ok [])
               in
               (match parsed with
                | Ok corners -> faces := corners :: !faces
                | Error message -> fail message)
           | ("v" | "vn" | "vt" | "f") :: _ ->
               fail
                 (Printf.sprintf
                    "Mesh.load_obj: line %d has an incomplete record"
                    !line_number)
           | _ -> ()
         done
       with End_of_file -> ());
      match !error with
      | Some message -> Error message
      | None ->
          let positions = Array.of_list (List.rev !positions)
          and source_normals = Array.of_list (List.rev !normals)
          and source_tex_coords = Array.of_list (List.rev !tex_coords) in
          let resolve line kind count raw =
            let index = if raw > 0 then raw - 1 else count + raw in
            if index < 0 || index >= count then
              Error
                (Printf.sprintf
                   "Mesh.load_obj: %s index %d is out of range near face %d"
                   kind raw line)
            else Ok index
          in
          let table = Hashtbl.create 128 in
          let vertices = ref [] and output_normals = ref []
          and output_tex_coords = ref [] and output_indices = ref []
          and has_normals = ref false and has_tex_coords = ref false in
          let intern face_number ((position, texture, normal) as corner) =
            match Hashtbl.find_opt table corner with
            | Some index -> Ok index
            | None ->
                (match
                   resolve face_number "position"
                     (Array.length positions) position
                 with
                 | Error _ as error -> error
                 | Ok position ->
                     let texture =
                       match texture with
                       | None -> Ok None
                       | Some value ->
                           Result.map Option.some
                             (resolve face_number "texture"
                                (Array.length source_tex_coords) value)
                     and normal =
                       match normal with
                       | None -> Ok None
                       | Some value ->
                           Result.map Option.some
                             (resolve face_number "normal"
                                (Array.length source_normals) value)
                     in
                     match texture, normal with
                     | Ok texture, Ok normal ->
                         let index = List.length !vertices in
                         Hashtbl.add table corner index;
                         vertices := positions.(position) :: !vertices;
                         output_tex_coords :=
                           Option.fold ~none:Vec2.zero
                             ~some:(Array.get source_tex_coords) texture
                           :: !output_tex_coords;
                         output_normals :=
                           Option.fold ~none:Vec3.zero
                             ~some:(Array.get source_normals) normal
                           :: !output_normals;
                         if Option.is_some texture then has_tex_coords := true;
                         if Option.is_some normal then has_normals := true;
                         Ok index
                     | Error message, _ | _, Error message -> Error message)
          in
          let failure = ref None in
          List.rev !faces
          |> List.iteri (fun face_number corners ->
            match corners with
            | first :: second :: rest ->
                let rec fan left = function
                  | right :: remaining ->
                      List.iter
                        (fun corner ->
                          match intern (face_number + 1) corner with
                          | Ok index -> output_indices := index :: !output_indices
                          | Error message -> failure := Some message)
                        [first; left; right];
                      fan right remaining
                  | [] -> ()
                in
                fan second rest
            | _ -> ());
          (match !failure with
           | Some message -> Error message
           | None ->
               let vertices = List.rev !vertices
               and indices = List.rev !output_indices in
               let normals =
                 if !has_normals then Some (List.rev !output_normals) else None
               and tex_coords =
                 if !has_tex_coords then Some (List.rev !output_tex_coords)
                 else None
               in
               match create ~indices ?normals ?tex_coords vertices with
               | Error _ as error -> error
               | Ok mesh ->
                   if Option.is_some mesh.normals then Ok mesh
                   else Ok (recalculate_normals mesh)))
  with Sys_error message -> Error ("Mesh.load_obj: " ^ message)

let load_obj_exn filename =
  match load_obj filename with
  | Ok mesh -> mesh
  | Error message -> failwith message

let save_obj mesh filename =
  match mesh.mode with
  | Points | Lines | Line_strip | Line_loop ->
      Error "Mesh.save_obj: only triangle geometry is supported"
  | Triangles | Triangle_strip | Triangle_fan ->
      try
        let channel = open_out filename in
        Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
          for index = 0 to Vec3_buffer.length mesh.vertices - 1 do
            Printf.fprintf channel "v %.17g %.17g %.17g\n"
              mesh.vertices.x.(index) mesh.vertices.y.(index)
              mesh.vertices.z.(index)
          done;
          Option.iter
            (Array.iter (fun coord ->
               Printf.fprintf channel "vt %.17g %.17g\n"
                 coord.Vec2.x coord.y))
            mesh.tex_coords;
          Option.iter (fun normals ->
            for index = 0 to Vec3_buffer.length normals - 1 do
              Printf.fprintf channel "vn %.17g %.17g %.17g\n"
                normals.x.(index) normals.y.(index) normals.z.(index)
            done) mesh.normals;
          let corner index =
            let index = index + 1 in
            match mesh.tex_coords, mesh.normals with
            | None, None -> string_of_int index
            | Some _, None -> Printf.sprintf "%d/%d" index index
            | None, Some _ -> Printf.sprintf "%d//%d" index index
            | Some _, Some _ -> Printf.sprintf "%d/%d/%d" index index index
          in
          List.iter
            (fun (a, b, c) ->
              Printf.fprintf channel "f %s %s %s\n"
                (corner a) (corner b) (corner c))
            (triangles mesh);
          Ok ())
      with Sys_error message -> Error ("Mesh.save_obj: " ^ message)

let load_ply filename =
  try
    let channel = open_in filename in
    Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      let next () =
        try input_line channel
        with End_of_file -> failwith "unexpected end of file"
      in
      if String.trim (next ()) <> "ply" then failwith "missing PLY signature";
      let vertex_count = ref 0 and face_count = ref 0
      and current_element = ref "" and vertex_properties = ref []
      and ascii = ref false and header_done = ref false in
      while not !header_done do
        match obj_words (next ()) with
        | ["format"; "ascii"; _] -> ascii := true
        | ["format"; _; _] -> failwith "only ASCII PLY is supported"
        | ["element"; name; count] ->
            let count =
              match int_of_string_opt count with
              | Some value when value >= 0 -> value
              | _ -> failwith "invalid element count"
            in
            current_element := name;
            if name = "vertex" then vertex_count := count
            else if name = "face" then face_count := count
        | "property" :: _type :: name :: []
          when !current_element = "vertex" ->
            vertex_properties := name :: !vertex_properties
        | ["end_header"] -> header_done := true
        | [] | "comment" :: _ | "obj_info" :: _
        | "property" :: _ | _ -> ()
      done;
      if not !ascii then failwith "missing ASCII format declaration";
      let properties = Array.of_list (List.rev !vertex_properties) in
      let property values name =
        let found = ref None in
        Array.iteri
          (fun index property_name ->
            if property_name = name && index < Array.length values then
              found := Some values.(index))
          properties;
        !found
      in
      let required_float values name =
        match
          property values name
          |> fun value ->
          Option.fold ~none:None ~some:float_of_string_opt value
        with
        | Some value when Float.is_finite value -> value
        | _ -> failwith ("missing or invalid vertex property " ^ name)
      in
      let optional_float values names =
        List.find_map
          (fun name ->
            property values name
            |> fun value ->
            Option.fold ~none:None ~some:float_of_string_opt value)
          names
      in
      let optional_byte values name =
        property values name
        |> fun value ->
        Option.fold ~none:None ~some:int_of_string_opt value
      in
      let positions = ref [] and normals = ref [] and tex_coords = ref []
      and colors = ref [] and has_normals = ref false
      and has_tex_coords = ref false and has_colors = ref false in
      for _ = 1 to !vertex_count do
        let values = Array.of_list (obj_words (next ())) in
        positions :=
          Vec3.create
            (required_float values "x")
            (required_float values "y")
            (required_float values "z")
          :: !positions;
        let normal =
          match
            optional_float values ["nx"],
            optional_float values ["ny"],
            optional_float values ["nz"]
          with
          | Some x, Some y, Some z ->
              has_normals := true;
              Vec3.create x y z
          | _ -> Vec3.zero
        in
        normals := normal :: !normals;
        let tex_coord =
          match
            optional_float values ["u"; "s"; "texture_u"],
            optional_float values ["v"; "t"; "texture_v"]
          with
          | Some u, Some v ->
              has_tex_coords := true;
              Vec2.create u v
          | _ -> Vec2.zero
        in
        tex_coords := tex_coord :: !tex_coords;
        let color =
          match
            optional_byte values "red",
            optional_byte values "green",
            optional_byte values "blue"
          with
          | Some red, Some green, Some blue ->
              has_colors := true;
              Color.rgba red green blue
                (Option.value ~default:255 (optional_byte values "alpha"))
          | _ -> Color.white
        in
        colors := color :: !colors
      done;
      let indices = ref [] in
      for _ = 1 to !face_count do
        match obj_words (next ()) with
        | count :: values ->
            let count =
              match int_of_string_opt count with
              | Some value when value >= 3 -> value
              | _ -> failwith "face must contain at least three vertices"
            in
            if List.length values < count then
              failwith "face index list is shorter than its declared count";
            let values =
              values |> List.to_seq |> Seq.take count |> List.of_seq
              |> List.map (fun value ->
                match int_of_string_opt value with
                | Some index
                  when index >= 0 && index < !vertex_count -> index
                | _ -> failwith "face vertex index is out of range")
            in
            (match values with
             | first :: second :: rest ->
                 let rec fan left = function
                   | right :: remaining ->
                       indices := right :: left :: first :: !indices;
                       fan right remaining
                   | [] -> ()
                 in
                 fan second rest
             | _ -> ())
        | [] -> failwith "empty face record"
      done;
      let normals = if !has_normals then Some (List.rev !normals) else None
      and tex_coords =
        if !has_tex_coords then Some (List.rev !tex_coords) else None
      and colors = if !has_colors then Some (List.rev !colors) else None in
      match
        create ~indices:(List.rev !indices) ?normals ?tex_coords ?colors
          (List.rev !positions)
      with
      | Error message -> Error message
      | Ok mesh ->
          if Option.is_some mesh.normals then Ok mesh
          else Ok (recalculate_normals mesh))
  with
  | Sys_error message -> Error ("Mesh.load_ply: " ^ message)
  | Failure message -> Error ("Mesh.load_ply: " ^ message)

let load_ply_exn filename =
  match load_ply filename with
  | Ok mesh -> mesh
  | Error message -> failwith message

let output_int32 ~little_endian channel value =
  let byte shift =
    Int32.shift_right_logical value shift
    |> Int32.logand 0xffl
    |> Int32.to_int
    |> output_byte channel
  in
  if little_endian then begin
    byte 0;
    byte 8;
    byte 16;
    byte 24
  end
  else begin
    byte 24;
    byte 16;
    byte 8;
    byte 0
  end

let output_float32 ~little_endian channel value =
  output_int32 ~little_endian channel (Int32.bits_of_float value)

let save_ply ?(format = Ply_ascii) mesh filename =
  match mesh.mode with
  | Points | Lines | Line_strip | Line_loop ->
      Error "Mesh.save_ply: only triangle geometry is supported"
  | Triangles | Triangle_strip | Triangle_fan ->
      try
        let channel = open_out_bin filename in
        Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
          let faces = triangles mesh in
          let format_name =
            match format with
            | Ply_ascii -> "ascii"
            | Ply_binary_little_endian -> "binary_little_endian"
            | Ply_binary_big_endian -> "binary_big_endian"
          in
          Printf.fprintf channel "ply\nformat %s 1.0\n" format_name;
          Printf.fprintf channel "element vertex %d\n"
            (Vec3_buffer.length mesh.vertices);
          output_string channel
            "property float x\nproperty float y\nproperty float z\n";
          if Option.is_some mesh.normals then
            output_string channel
              "property float nx\nproperty float ny\nproperty float nz\n";
          if Option.is_some mesh.tex_coords then
            output_string channel "property float u\nproperty float v\n";
          if Option.is_some mesh.colors then
            output_string channel
              "property uchar red\nproperty uchar green\nproperty uchar blue\nproperty uchar alpha\n";
          Printf.fprintf channel
            "element face %d\nproperty list uchar int vertex_indices\nend_header\n"
            (List.length faces);
          (match format with
           | Ply_ascii ->
               for index = 0 to Vec3_buffer.length mesh.vertices - 1 do
                   Printf.fprintf channel "%.17g %.17g %.17g"
                     mesh.vertices.x.(index) mesh.vertices.y.(index)
                     mesh.vertices.z.(index);
                   Option.iter
                     (fun (normals : Vec3_buffer.t) ->
                       Printf.fprintf channel " %.17g %.17g %.17g"
                         normals.x.(index) normals.y.(index) normals.z.(index))
                     mesh.normals;
                   Option.iter
                     (fun tex_coords ->
                       let coord = tex_coords.(index) in
                       Printf.fprintf channel " %.17g %.17g"
                         coord.Vec2.x coord.y)
                     mesh.tex_coords;
                   Option.iter
                     (fun colors ->
                       let color = colors.(index) in
                       Printf.fprintf channel " %d %d %d %d"
                         color.Color.r color.g color.b color.a)
                     mesh.colors;
                   output_char channel '\n'
               done;
               List.iter
                 (fun (a, b, c) ->
                   Printf.fprintf channel "3 %d %d %d\n" a b c)
                 faces
           | Ply_binary_little_endian | Ply_binary_big_endian ->
               let little_endian = format = Ply_binary_little_endian in
               for index = 0 to Vec3_buffer.length mesh.vertices - 1 do
                   List.iter
                     (output_float32 ~little_endian channel)
                     [mesh.vertices.x.(index); mesh.vertices.y.(index);
                      mesh.vertices.z.(index)];
                   Option.iter
                     (fun (normals : Vec3_buffer.t) ->
                       List.iter
                         (output_float32 ~little_endian channel)
                         [normals.x.(index); normals.y.(index); normals.z.(index)])
                     mesh.normals;
                   Option.iter
                     (fun tex_coords ->
                       let coord = tex_coords.(index) in
                       List.iter
                         (output_float32 ~little_endian channel)
                         [coord.Vec2.x; coord.y])
                     mesh.tex_coords;
                   Option.iter
                     (fun colors ->
                       let color = colors.(index) in
                       List.iter (output_byte channel)
                         [color.Color.r; color.g; color.b; color.a])
                     mesh.colors
               done;
               List.iter
                 (fun (a, b, c) ->
                   output_byte channel 3;
                   List.iter
                     (fun index ->
                       output_int32 ~little_endian channel
                         (Int32.of_int index))
                     [a; b; c])
                 faces);
          Ok ())
      with Sys_error message -> Error ("Mesh.save_ply: " ^ message)

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

  let iter_triangles operation (mesh : t) =
    let values = mesh.indices and count = Array.length mesh.indices in
    match mesh.mode with
    | Triangles ->
        for face = 0 to count / 3 - 1 do
          let offset = face * 3 in
          operation values.(offset) values.(offset+1) values.(offset+2)
        done
    | Triangle_strip ->
        for face = 0 to count - 3 do
          if face land 1 = 0 then
            operation values.(face) values.(face+1) values.(face+2)
          else operation values.(face+1) values.(face) values.(face+2)
        done
    | Triangle_fan ->
        for face = 0 to count - 3 do
          operation values.(0) values.(face+1) values.(face+2)
        done
    | Points | Lines | Line_strip | Line_loop -> ()

  let triangle_indices mesh =
    let output = Array.make (triangle_count mesh) (0, 0, 0) in
    let face = ref 0 in
    iter_triangles (fun a b c ->
      output.(!face) <- a, b, c;
      incr face) mesh;
    output
end
