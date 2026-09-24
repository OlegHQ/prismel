type uniform =
  | Float of float
  | Int of int
  | Bool of bool
  | Vec2 of Vec2.t
  | Vec3 of Vec3.t
  | Vec4 of float * float * float * float
  | Color of Color.t
  | Mat4 of Mat4.t
  | Texture of Texture.t
  | Floats of float list
  | Ints of int list

type uniforms = (string * uniform) list

let empty_uniforms = []

let validate_name name =
  if String.trim name = "" then
    invalid_arg "Shader3: uniform names must not be empty"

let remove_uniform name uniforms =
  List.filter (fun (candidate, _) -> candidate <> name) uniforms

let set_uniform name value uniforms =
  validate_name name;
  (name, value) :: remove_uniform name uniforms

let find_uniform name uniforms = List.assoc_opt name uniforms

let float_uniform name uniforms =
  match find_uniform name uniforms with Some (Float value) -> Some value | _ -> None

let int_uniform name uniforms =
  match find_uniform name uniforms with Some (Int value) -> Some value | _ -> None

let bool_uniform name uniforms =
  match find_uniform name uniforms with Some (Bool value) -> Some value | _ -> None

let vec2_uniform name uniforms =
  match find_uniform name uniforms with Some (Vec2 value) -> Some value | _ -> None

let vec3_uniform name uniforms =
  match find_uniform name uniforms with Some (Vec3 value) -> Some value | _ -> None

let color_uniform name uniforms =
  match find_uniform name uniforms with Some (Color value) -> Some value | _ -> None

let mat4_uniform name uniforms =
  match find_uniform name uniforms with Some (Mat4 value) -> Some value | _ -> None

let texture_uniform name uniforms =
  match find_uniform name uniforms with Some (Texture value) -> Some value | _ -> None

type vertex_input = {
  vertex_index : int;
  position : Vec3.t;
  normal : Vec3.t;
  color : Color.t;
  tex_coord : Vec2.t;
  model : Mat4.t;
  view : Mat4.t;
  projection : Mat4.t;
  model_view_projection : Mat4.t;
  normal_matrix : Mat4.t;
  uniforms : uniforms;
}

type vertex_output = {
  clip_position : float * float * float * float;
  world_position : Vec3.t;
  world_normal : Vec3.t;
  color : Color.t;
  tex_coord : Vec2.t;
  varyings : float list;
}

type primitive =
  | Point of vertex_output
  | Line of vertex_output * vertex_output
  | Triangle of vertex_output * vertex_output * vertex_output

type geometry_input = {
  primitive_index : int;
  primitive : primitive;
  uniforms : uniforms;
}

type fragment_input = {
  screen_position : Vec2.t;
  depth : float;
  front_facing : bool;
  world_position : Vec3.t;
  world_normal : Vec3.t;
  color : Color.t;
  tex_coord : Vec2.t;
  varyings : float list;
  uniforms : uniforms;
}

type fragment_output = {
  color : Color.t;
  depth : float option;
}

type t = {
  varying_count : int;
  uniforms : uniforms;
  vertex : vertex_input -> vertex_output;
  geometry : (geometry_input -> primitive list) option;
  fragment : fragment_input -> fragment_output option;
}

let create ?(varying_count = 0) ?(uniforms = empty_uniforms)
    ?geometry ~vertex ~fragment () =
  if varying_count < 0 then
    invalid_arg "Shader3.create: varying_count must be non-negative";
  { varying_count; uniforms; vertex; geometry; fragment }

let with_uniform name value shader =
  { shader with uniforms = set_uniform name value shader.uniforms }

let with_uniforms uniforms shader = { shader with uniforms }
let uniforms shader = shader.uniforms
let varying_count shader = shader.varying_count
let has_geometry shader = Option.is_some shader.geometry

let default_vertex input =
  let world_position = Mat4.transform_point input.model input.position in
  let world_normal =
    Mat4.transform_direction input.normal_matrix input.normal
    |> Vec3.normalize
  in
  {
    clip_position =
      Mat4.transform input.model_view_projection
        (input.position.x, input.position.y, input.position.z, 1.);
    world_position;
    world_normal;
    color = input.color;
    tex_coord = input.tex_coord;
    varyings = [];
  }

let output ?depth color = Some { color; depth }
let default_fragment (input : fragment_input) = output input.color
let discard = None

module Private = struct
  let vertex shader = shader.vertex
  let geometry shader = shader.geometry
  let fragment shader = shader.fragment
end
