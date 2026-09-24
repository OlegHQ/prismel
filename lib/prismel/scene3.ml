type render_mode = Faces | Wireframe | Vertices
type cull = Cull_none | Cull_back | Cull_front
type shading = Smooth | Flat
type comparison =
  | Never
  | Less
  | Equal
  | Less_equal
  | Greater
  | Not_equal
  | Greater_equal
  | Always
type depth_state = {
  comparison : comparison;
  write : bool;
}
type stencil_operation =
  | Keep
  | Zero
  | Replace
  | Increment
  | Decrement
  | Increment_wrap
  | Decrement_wrap
  | Invert
type stencil_state = {
  comparison : comparison;
  reference : int;
  read_mask : int;
  write_mask : int;
  on_stencil_fail : stencil_operation;
  on_depth_fail : stencil_operation;
  on_pass : stencil_operation;
}
type raster_state = {
  line_width : float;
  point_size : float;
}
type blend = Replace | Alpha | Add | Multiply | Screen | Subtract

type texture = {
  value : Texture.t;
  filter : Texture.filter;
  wrap_u : Texture.wrap;
  wrap_v : Texture.wrap;
}

type node =
  | Mesh of
      Mesh.t * Material.t * texture option * Shader3.t option
      * render_mode * cull * shading
  | Instances of
      Mesh.t * Material.t * texture option * Shader3.t option
      * render_mode * cull * shading * Mat4.t array
  | Group of node list
  | Transform of Mat4.t * node list
  | Depth_state of depth_state * node list
  | Stencil_state of stencil_state * node list
  | Raster_state of raster_state * node list
  | Blend_state of blend * node list

type t = {
  nodes : node list;
  lights : Light.t list;
  shadows : Shadow3.t list;
  ambient : Color.t;
  separate_specular : bool;
  fog : Fog3.t option;
  depth_clear : float;
  stencil_clear : int;
  samples : int;
}

let depth_state ?(comparison = Less) ?(write = true) () =
  { comparison; write }

let default_depth = depth_state ()

let validate_stencil_byte name value =
  if value < 0 || value > 0xff then
    invalid_arg ("Scene3.stencil_state: " ^ name ^ " must be in 0..255")

let stencil_state ?(comparison = Always) ?(reference = 0)
    ?(read_mask = 0xff) ?(write_mask = 0xff)
    ?(on_stencil_fail = Keep) ?(on_depth_fail = Keep) ?(on_pass = Keep) () =
  validate_stencil_byte "reference" reference;
  validate_stencil_byte "read_mask" read_mask;
  validate_stencil_byte "write_mask" write_mask;
  {
    comparison;
    reference;
    read_mask;
    write_mask;
    on_stencil_fail;
    on_depth_fail;
    on_pass;
  }

let default_stencil = stencil_state ()

let raster_state ?(line_width = 1.) ?(point_size = 1.) () =
  if not (Float.is_finite line_width) || line_width <= 0. then
    invalid_arg "Scene3.raster_state: line_width must be finite and positive";
  if not (Float.is_finite point_size) || point_size <= 0. then
    invalid_arg "Scene3.raster_state: point_size must be finite and positive";
  { line_width; point_size }

let default_raster = raster_state ()

let empty = {
  nodes = [];
  lights = [];
  shadows = [];
  ambient = Color.black;
  separate_specular = false;
  fog = None;
  depth_clear = 1.;
  stencil_clear = 0;
  samples = 1;
}

let create ?(lights = []) ?(shadows = []) ?(ambient = Color.rgb 32 32 32)
    ?(separate_specular = false) ?fog ?(depth_clear = 1.)
    ?(stencil_clear = 0) ?(samples = 1) nodes =
  if not (Float.is_finite depth_clear)
     || depth_clear < 0. || depth_clear > 1.
  then invalid_arg "Scene3.create: depth_clear must be finite and in 0..1";
  validate_stencil_byte "stencil_clear" stencil_clear;
  if not (List.mem samples [1; 4; 9; 16]) then
    invalid_arg "Scene3.create: samples must be 1, 4, 9, or 16";
  {
    nodes;
    lights;
    shadows;
    ambient;
    separate_specular;
    fog;
    depth_clear;
    stencil_clear;
    samples;
  }

let textured ?(filter = Texture.Bilinear) ?(wrap_u = Texture.Clamp)
    ?(wrap_v = Texture.Clamp) value =
  { value; filter; wrap_u; wrap_v }

let mesh ?(material = Material.default) ?texture ?shader ?(mode = Faces)
    ?(cull = Cull_back) ?(shading = Smooth) value =
  Mesh (value, material, texture, shader, mode, cull, shading)

let instances ?(material = Material.default) ?texture ?shader ?(mode = Faces)
    ?(cull = Cull_back) ?(shading = Smooth) value transforms =
  Instances (value, material, texture, shader, mode, cull, shading,
    Array.of_list transforms)

let instances_array ?(material = Material.default) ?texture ?shader ?(mode = Faces)
    ?(cull = Cull_back) ?(shading = Smooth) value transforms =
  Instances (value, material, texture, shader, mode, cull, shading,
    Array.copy transforms)

let group nodes = Group nodes
let transform matrix nodes = Transform (matrix, nodes)
let translate value nodes = transform (Mat4.translation value) nodes
let rotate ~axis angle nodes = transform (Mat4.rotation ~axis angle) nodes
let scale value nodes = transform (Mat4.scaling value) nodes
let at_node value nodes = transform (Node3.global_transform value) nodes
let with_depth state nodes = Depth_state (state, nodes)
let with_stencil state nodes = Stencil_state (state, nodes)
let with_raster state nodes = Raster_state (state, nodes)
let with_blend blend nodes = Blend_state (blend, nodes)

let box ?material ?texture ?shader ?mode ?cull ?shading
    ~width ~height ~depth () =
  mesh ?material ?texture ?shader ?mode ?cull ?shading
    (Mesh.box ~width ~height ~depth ())

let plane ?material ?texture ?shader ?mode ?cull ?shading ~width ~height () =
  mesh ?material ?texture ?shader ?mode ?cull ?shading
    (Mesh.plane ~width ~height ())

let sphere ?material ?texture ?shader ?mode ?cull ?shading ~radius () =
  mesh ?material ?texture ?shader ?mode ?cull ?shading
    (Mesh.sphere ~radius ())

let icosphere ?material ?texture ?shader ?mode ?cull ?shading ~radius () =
  mesh ?material ?texture ?shader ?mode ?cull ?shading
    (Mesh.icosphere ~radius ())

let cylinder ?material ?texture ?shader ?mode ?cull ?shading
    ~radius ~height () =
  mesh ?material ?texture ?shader ?mode ?cull ?shading
    (Mesh.cylinder ~radius ~height ())

let cone ?material ?texture ?shader ?mode ?cull ?shading
    ~radius ~height () =
  mesh ?material ?texture ?shader ?mode ?cull ?shading
    (Mesh.cone ~radius ~height ())

module Private = struct
  type drawing = {
    mesh : Mesh.t;
    material : Material.t;
    texture : texture option;
    shader : Shader3.t option;
    mode : render_mode;
    cull : cull;
    shading : shading;
    depth : depth_state;
    stencil : stencil_state;
    raster : raster_state;
    blend : blend;
    transform : Mat4.t;
  }

  let cacheable scene =
    let rec nodes = function
      | [] -> true
      | Mesh (_, _, None, None, _, _, _) :: rest -> nodes rest
      | Instances (_, _, None, None, _, _, _, _) :: rest -> nodes rest
      | Group nested :: rest
      | Transform (_, nested) :: rest
      | Depth_state (_, nested) :: rest
      | Stencil_state (_, nested) :: rest
      | Raster_state (_, nested) :: rest
      | Blend_state (_, nested) :: rest -> nodes nested && nodes rest
      | Mesh (_, _, (Some _), _, _, _, _) :: _
      | Mesh (_, _, _, (Some _), _, _, _) :: _
      | Instances (_, _, (Some _), _, _, _, _, _) :: _
      | Instances (_, _, _, (Some _), _, _, _, _) :: _ -> false in
    scene.shadows = [] && nodes scene.nodes

  let drawings scene =
    let rec flatten parent depth stencil raster blend acc = function
      | [] -> acc
      | Mesh (mesh, material, texture, shader, mode, cull, shading) :: rest ->
          flatten parent depth stencil raster blend
            ({ mesh; material; texture; shader; mode; cull; shading;
               depth; stencil; raster; blend;
               transform = parent } :: acc)
            rest
      | Instances
          (mesh, material, texture, shader, mode, cull, shading, transforms)
        :: rest ->
          let acc =
            Array.fold_left
              (fun acc transform ->
                {
                  mesh;
                  material;
                  texture;
                  shader;
                  mode;
                  cull;
                  shading;
                  depth;
                  stencil;
                  raster;
                  blend;
                  transform = Mat4.mul parent transform;
                }
                :: acc)
              acc transforms
          in
          flatten parent depth stencil raster blend acc rest
      | Group nodes :: rest ->
          flatten parent depth stencil raster blend
            (flatten parent depth stencil raster blend acc nodes) rest
      | Transform (matrix, nodes) :: rest ->
          let transform = Mat4.mul parent matrix in
          flatten parent depth stencil raster blend
            (flatten transform depth stencil raster blend acc nodes) rest
      | Depth_state (state, nodes) :: rest ->
          flatten parent depth stencil raster blend
            (flatten parent state stencil raster blend acc nodes) rest
      | Stencil_state (state, nodes) :: rest ->
          flatten parent depth stencil raster blend
            (flatten parent depth state raster blend acc nodes) rest
      | Raster_state (state, nodes) :: rest ->
          flatten parent depth stencil raster blend
            (flatten parent depth stencil state blend acc nodes) rest
      | Blend_state (state, nodes) :: rest ->
          flatten parent depth stencil raster blend
            (flatten parent depth stencil raster state acc nodes) rest
    in
    List.rev
      (flatten Mat4.identity default_depth default_stencil default_raster
         Alpha [] scene.nodes)

  let iter_drawings operation scene =
    let rec visit parent depth stencil raster blend = function
      | [] -> ()
      | Mesh (mesh, material, texture, shader, mode, cull, shading) :: rest ->
          operation { mesh; material; texture; shader; mode; cull; shading;
            depth; stencil; raster; blend; transform = parent };
          visit parent depth stencil raster blend rest
      | Instances (mesh, material, texture, shader, mode, cull, shading,
          transforms) :: rest ->
          Array.iter (fun transform -> operation {
            mesh; material; texture; shader; mode; cull; shading;
            depth; stencil; raster; blend;
            transform = Mat4.mul parent transform }) transforms;
          visit parent depth stencil raster blend rest
      | Group nodes :: rest ->
          visit parent depth stencil raster blend nodes;
          visit parent depth stencil raster blend rest
      | Transform (matrix, nodes) :: rest ->
          visit (Mat4.mul parent matrix) depth stencil raster blend nodes;
          visit parent depth stencil raster blend rest
      | Depth_state (state, nodes) :: rest ->
          visit parent state stencil raster blend nodes;
          visit parent depth stencil raster blend rest
      | Stencil_state (state, nodes) :: rest ->
          visit parent depth state raster blend nodes;
          visit parent depth stencil raster blend rest
      | Raster_state (state, nodes) :: rest ->
          visit parent depth stencil state blend nodes;
          visit parent depth stencil raster blend rest
      | Blend_state (state, nodes) :: rest ->
          visit parent depth stencil raster state nodes;
          visit parent depth stencil raster blend rest in
    visit Mat4.identity default_depth default_stencil default_raster Alpha scene.nodes

  let iter_batches operation scene =
    let rec visit parent depth stencil raster blend = function
      | [] -> ()
      | Mesh (mesh, material, texture, shader, mode, cull, shading) :: rest ->
          operation { mesh; material; texture; shader; mode; cull; shading;
            depth; stencil; raster; blend; transform = parent } None;
          visit parent depth stencil raster blend rest
      | Instances (mesh, material, texture, shader, mode, cull, shading,
          transforms) :: rest ->
          operation { mesh; material; texture; shader; mode; cull; shading;
            depth; stencil; raster; blend; transform = parent }
            (Some transforms);
          visit parent depth stencil raster blend rest
      | Group nodes :: rest ->
          visit parent depth stencil raster blend nodes;
          visit parent depth stencil raster blend rest
      | Transform (matrix, nodes) :: rest ->
          visit (Mat4.mul parent matrix) depth stencil raster blend nodes;
          visit parent depth stencil raster blend rest
      | Depth_state (state, nodes) :: rest ->
          visit parent state stencil raster blend nodes;
          visit parent depth stencil raster blend rest
      | Stencil_state (state, nodes) :: rest ->
          visit parent depth state raster blend nodes;
          visit parent depth stencil raster blend rest
      | Raster_state (state, nodes) :: rest ->
          visit parent depth stencil state blend nodes;
          visit parent depth stencil raster blend rest
      | Blend_state (state, nodes) :: rest ->
          visit parent depth stencil raster state nodes;
          visit parent depth stencil raster blend rest in
    visit Mat4.identity default_depth default_stencil default_raster Alpha scene.nodes

  let lights scene = scene.lights
  let shadows scene = scene.shadows
  let ambient scene = scene.ambient
  let separate_specular scene = scene.separate_specular
  let fog scene = scene.fog
  let depth_clear scene = scene.depth_clear
  let stencil_clear scene = scene.stencil_clear
  let samples scene = scene.samples
end
