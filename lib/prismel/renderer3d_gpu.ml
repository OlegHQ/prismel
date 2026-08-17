open Tsdl
open Ctypes

(* Native fixed-pipeline OpenGL backend. The public Scene3 representation stays
   backend-neutral; unsupported programmable/offscreen features remain on the
   deterministic software reference until their GPU implementation lands. *)

let gl_depth_buffer_bit = 0x00000100
let gl_stencil_buffer_bit = 0x00000400
let gl_color_buffer_bit = 0x00004000
let gl_points = 0x0000
let gl_lines = 0x0001
let gl_line_loop = 0x0002
let gl_line_strip = 0x0003
let gl_triangles = 0x0004
let gl_triangle_strip = 0x0005
let gl_triangle_fan = 0x0006
let gl_never = 0x0200
let gl_less = 0x0201
let gl_equal = 0x0202
let gl_less_equal = 0x0203
let gl_greater = 0x0204
let gl_not_equal = 0x0205
let gl_greater_equal = 0x0206
let gl_always = 0x0207
let gl_zero = 0
let gl_keep = 0x1E00
let gl_replace = 0x1E01
let gl_increment = 0x1E02
let gl_decrement = 0x1E03
let gl_increment_wrap = 0x8507
let gl_decrement_wrap = 0x8508
let gl_invert = 0x150A
let gl_src_alpha = 0x0302
let gl_one_minus_src_alpha = 0x0303
let gl_one = 1
let gl_dst_color = 0x0306
let gl_one_minus_src_color = 0x0301
let gl_func_add = 0x8006
let gl_func_reverse_subtract = 0x800B
let gl_front = 0x0404
let gl_back = 0x0405
let gl_front_and_back = 0x0408
let gl_cull_face = 0x0B44
let gl_depth_test = 0x0B71
let gl_stencil_test = 0x0B90
let gl_blend = 0x0BE2
let gl_alpha_test = 0x0BC0
let gl_scissor_test = 0x0C11
let gl_texture_2d = 0x0DE1
let gl_lighting = 0x0B50
let gl_light0 = 0x4000
let gl_ambient = 0x1200
let gl_diffuse = 0x1201
let gl_specular = 0x1202
let gl_position = 0x1203
let gl_spot_direction = 0x1204
let gl_spot_exponent = 0x1205
let gl_spot_cutoff = 0x1206
let gl_constant_attenuation = 0x1207
let gl_linear_attenuation = 0x1208
let gl_quadratic_attenuation = 0x1209
let gl_emission = 0x1600
let gl_shininess = 0x1601
let gl_ambient_and_diffuse = 0x1602
let gl_color_material = 0x0B57
let gl_light_model_ambient = 0x0B53
let gl_normalize = 0x0BA1
let gl_flat = 0x1D00
let gl_smooth = 0x1D01
let gl_fill = 0x1B02
let gl_line = 0x1B01
let gl_projection = 0x1701
let gl_modelview = 0x1700
let gl_vertex_array = 0x8074
let gl_normal_array = 0x8075
let gl_color_array = 0x8076
let gl_double = 0x140A
let gl_float = 0x1406
let gl_unsigned_int = 0x1405
let gl_unsigned_byte = 0x1401
let gl_rgba = 0x1908
let gl_rgba8 = 0x8058
let gl_framebuffer = 0x8D40
let gl_renderbuffer = 0x8D41
let gl_color_attachment0 = 0x8CE0
let gl_depth_stencil_attachment = 0x821A
let gl_depth24_stencil8 = 0x88F0
let gl_framebuffer_complete = 0x8CD5
let gl_framebuffer_binding = 0x8CA6
let gl_renderbuffer_binding = 0x8CA7
let gl_all_attrib_bits = 0x000fffff
let gl_ccw = 0x0901
let gl_texture0 = 0x84C0
let gl_current_program = 0x8B8D
let gl_array_buffer = 0x8892
let gl_element_array_buffer = 0x8893
let gl_array_buffer_binding = 0x8894
let gl_element_array_buffer_binding = 0x8895

type api = {
  clear : int -> unit;
  clear_color : float -> float -> float -> float -> unit;
  clear_depth : float -> unit;
  clear_stencil : int -> unit;
  viewport : int -> int -> int -> int -> unit;
  scissor : int -> int -> int -> int -> unit;
  enable : int -> unit;
  disable : int -> unit;
  depth_func : int -> unit;
  depth_mask : int -> unit;
  stencil_func : int -> int -> int -> unit;
  stencil_mask : int -> unit;
  stencil_op : int -> int -> int -> unit;
  blend_func : int -> int -> unit;
  blend_equation : int -> unit;
  cull_face : int -> unit;
  front_face : int -> unit;
  color_mask : int -> int -> int -> int -> unit;
  draw_buffer : int -> unit;
  active_texture : int -> unit;
  line_width : float -> unit;
  point_size : float -> unit;
  shade_model : int -> unit;
  polygon_mode : int -> int -> unit;
  matrix_mode : int -> unit;
  push_matrix : unit -> unit;
  pop_matrix : unit -> unit;
  push_attrib : int -> unit;
  pop_attrib : unit -> unit;
  push_client_attrib : int -> unit;
  pop_client_attrib : unit -> unit;
  get_integer : int -> int ptr -> unit;
  use_program : int -> unit;
  bind_buffer : int -> int -> unit;
  get_error : unit -> int;
  load_matrix : float ptr -> unit;
  enable_client_state : int -> unit;
  disable_client_state : int -> unit;
  vertex_pointer : int -> int -> int -> unit ptr -> unit;
  normal_pointer : int -> int -> unit ptr -> unit;
  color_pointer : int -> int -> int -> unit ptr -> unit;
  draw_elements : int -> int -> int -> unit ptr -> unit;
  read_buffer : int -> unit;
  read_pixels : int -> int -> int -> int -> int -> int -> unit ptr -> unit;
  gen_framebuffers : int -> int ptr -> unit;
  bind_framebuffer : int -> int -> unit;
  delete_framebuffers : int -> int ptr -> unit;
  check_framebuffer_status : int -> int;
  gen_renderbuffers : int -> int ptr -> unit;
  bind_renderbuffer : int -> int -> unit;
  renderbuffer_storage : int -> int -> int -> int -> unit;
  framebuffer_renderbuffer : int -> int -> int -> int -> unit;
  delete_renderbuffers : int -> int ptr -> unit;
  color4 : float -> float -> float -> float -> unit;
  color_material : int -> int -> unit;
  material4 : int -> int -> float ptr -> unit;
  material1 : int -> int -> float -> unit;
  light4 : int -> int -> float ptr -> unit;
  light1 : int -> int -> float -> unit;
  light_model4 : int -> float ptr -> unit;
}

let sdl_gl_get_proc_address = lazy (
  Foreign.foreign "SDL_GL_GetProcAddress" (string @-> returning (ptr void)))

let api = lazy (
  let bind name signature =
    let address = (Lazy.force sdl_gl_get_proc_address) name in
    if is_null address then failwith ("missing OpenGL entry point " ^ name);
    coerce (ptr void) (Foreign.funptr signature) address in
  let bind_any names signature =
    let rec find = function
      | [] -> failwith ("missing OpenGL entry point " ^ String.concat "/" names)
      | name :: rest ->
          let address = (Lazy.force sdl_gl_get_proc_address) name in
          if is_null address then find rest
          else coerce (ptr void) (Foreign.funptr signature) address in
    find names in
  {
    clear = bind "glClear" (int @-> returning void);
    clear_color = bind "glClearColor"
        (float @-> float @-> float @-> float @-> returning void);
    clear_depth = bind "glClearDepth" (double @-> returning void);
    clear_stencil = bind "glClearStencil" (int @-> returning void);
    viewport = bind "glViewport" (int @-> int @-> int @-> int @-> returning void);
    scissor = bind "glScissor" (int @-> int @-> int @-> int @-> returning void);
    enable = bind "glEnable" (int @-> returning void);
    disable = bind "glDisable" (int @-> returning void);
    depth_func = bind "glDepthFunc" (int @-> returning void);
    depth_mask = bind "glDepthMask" (int @-> returning void);
    stencil_func = bind "glStencilFunc" (int @-> int @-> int @-> returning void);
    stencil_mask = bind "glStencilMask" (int @-> returning void);
    stencil_op = bind "glStencilOp" (int @-> int @-> int @-> returning void);
    blend_func = bind "glBlendFunc" (int @-> int @-> returning void);
    blend_equation = bind "glBlendEquation" (int @-> returning void);
    cull_face = bind "glCullFace" (int @-> returning void);
    front_face = bind "glFrontFace" (int @-> returning void);
    color_mask = bind "glColorMask"
        (int @-> int @-> int @-> int @-> returning void);
    draw_buffer = bind "glDrawBuffer" (int @-> returning void);
    active_texture = bind "glActiveTexture" (int @-> returning void);
    line_width = bind "glLineWidth" (float @-> returning void);
    point_size = bind "glPointSize" (float @-> returning void);
    shade_model = bind "glShadeModel" (int @-> returning void);
    polygon_mode = bind "glPolygonMode" (int @-> int @-> returning void);
    matrix_mode = bind "glMatrixMode" (int @-> returning void);
    push_matrix = bind "glPushMatrix" (void @-> returning void);
    pop_matrix = bind "glPopMatrix" (void @-> returning void);
    push_attrib = bind "glPushAttrib" (int @-> returning void);
    pop_attrib = bind "glPopAttrib" (void @-> returning void);
    push_client_attrib = bind "glPushClientAttrib" (int @-> returning void);
    pop_client_attrib = bind "glPopClientAttrib" (void @-> returning void);
    get_integer = bind "glGetIntegerv" (int @-> ptr int @-> returning void);
    use_program = bind "glUseProgram" (int @-> returning void);
    bind_buffer = bind "glBindBuffer" (int @-> int @-> returning void);
    get_error = bind "glGetError" (void @-> returning int);
    load_matrix = bind "glLoadMatrixd" (ptr double @-> returning void);
    enable_client_state = bind "glEnableClientState" (int @-> returning void);
    disable_client_state = bind "glDisableClientState" (int @-> returning void);
    vertex_pointer = bind "glVertexPointer"
        (int @-> int @-> int @-> ptr void @-> returning void);
    normal_pointer = bind "glNormalPointer"
        (int @-> int @-> ptr void @-> returning void);
    color_pointer = bind "glColorPointer"
        (int @-> int @-> int @-> ptr void @-> returning void);
    draw_elements = bind "glDrawElements"
        (int @-> int @-> int @-> ptr void @-> returning void);
    read_buffer = bind "glReadBuffer" (int @-> returning void);
    read_pixels = bind "glReadPixels"
        (int @-> int @-> int @-> int @-> int @-> int @-> ptr void
         @-> returning void);
    gen_framebuffers = bind_any ["glGenFramebuffers"; "glGenFramebuffersEXT"]
        (int @-> ptr int @-> returning void);
    bind_framebuffer = bind_any ["glBindFramebuffer"; "glBindFramebufferEXT"]
        (int @-> int @-> returning void);
    delete_framebuffers = bind_any
        ["glDeleteFramebuffers"; "glDeleteFramebuffersEXT"]
        (int @-> ptr int @-> returning void);
    check_framebuffer_status = bind_any
        ["glCheckFramebufferStatus"; "glCheckFramebufferStatusEXT"]
        (int @-> returning int);
    gen_renderbuffers = bind_any ["glGenRenderbuffers"; "glGenRenderbuffersEXT"]
        (int @-> ptr int @-> returning void);
    bind_renderbuffer = bind_any ["glBindRenderbuffer"; "glBindRenderbufferEXT"]
        (int @-> int @-> returning void);
    renderbuffer_storage = bind_any
        ["glRenderbufferStorage"; "glRenderbufferStorageEXT"]
        (int @-> int @-> int @-> int @-> returning void);
    framebuffer_renderbuffer = bind_any
        ["glFramebufferRenderbuffer"; "glFramebufferRenderbufferEXT"]
        (int @-> int @-> int @-> int @-> returning void);
    delete_renderbuffers = bind_any
        ["glDeleteRenderbuffers"; "glDeleteRenderbuffersEXT"]
        (int @-> ptr int @-> returning void);
    color4 = bind "glColor4f"
        (float @-> float @-> float @-> float @-> returning void);
    color_material = bind "glColorMaterial" (int @-> int @-> returning void);
    material4 = bind "glMaterialfv" (int @-> int @-> ptr float @-> returning void);
    material1 = bind "glMaterialf" (int @-> int @-> float @-> returning void);
    light4 = bind "glLightfv" (int @-> int @-> ptr float @-> returning void);
    light1 = bind "glLightf" (int @-> int @-> float @-> returning void);
    light_model4 = bind "glLightModelfv" (int @-> ptr float @-> returning void);
  })

let sdl_render_flush = lazy (
  Foreign.foreign "SDL_RenderFlush" (ptr void @-> returning int))

let diagnostics = match Sys.getenv_opt "PRISMEL_GPU_DIAGNOSTICS" with
  | Some ("1" | "true" | "yes") -> true
  | None | Some _ -> false
let diagnostic_frame = ref 0
let presentation_diagnostic_frame = ref 0
let front_buffer_diagnostic_frame = ref 0
let frame_pending = ref false

type packed = {
  value : Mesh.t;
  positions : (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t;
  normals : (float, Bigarray.float64_elt, Bigarray.c_layout) Bigarray.Array1.t;
  colors : (float, Bigarray.float32_elt, Bigarray.c_layout) Bigarray.Array1.t option;
  indices : (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t;
  mode : Mesh.mode;
}

module Mesh_key = struct
  type t = Mesh.t
  let equal (left : t) right = left == right
  let hash = Hashtbl.hash
end

module Mesh_cache = Ephemeron.K1.Make (Mesh_key)

type cache = {
  table : packed Mesh_cache.t;
  order : Mesh.t Weak.t Queue.t;
}

let create_cache () = { table = Mesh_cache.create 16; order = Queue.create () }
let smooth_cache = create_cache ()
let flat_cache = create_cache ()
(* Dense interactive edits can replace a mesh every pointer event. Keep only
   the current and immediately previous packed upload rather than retaining a
   viewport-sized trail of expanded flat meshes. *)
let cache_capacity = 2

let cache_add cache key value =
  Mesh_cache.replace cache.table key value;
  let weak = Weak.create 1 in
  Weak.set weak 0 (Some key);
  Queue.add weak cache.order;
  while Queue.length cache.order > cache_capacity do
    match Weak.get (Queue.take cache.order) 0 with
    | None -> ()
    | Some expired -> Mesh_cache.remove cache.table expired
  done

let array3 view =
  let count = Array.length view.Mesh.Private.x in
  let output = Bigarray.Array1.create Bigarray.float64 Bigarray.c_layout
      (count * 3) in
  for index = 0 to count - 1 do
    Bigarray.Array1.unsafe_set output (index * 3) view.x.(index);
    Bigarray.Array1.unsafe_set output (index * 3 + 1) view.y.(index);
    Bigarray.Array1.unsafe_set output (index * 3 + 2) view.z.(index)
  done;
  output

let pack_mesh shading source =
  let cache, prepare = match shading with
    | Scene3.Smooth -> smooth_cache, (fun mesh ->
        if Mesh.has_normals mesh then mesh else Mesh.recalculate_normals mesh)
    | Flat -> flat_cache, Mesh.flat_shaded in
  match Mesh_cache.find_opt cache.table source with
  | Some packed -> packed
  | None ->
      let value = prepare source in
      let view = Mesh.Private.packed_view value in
      let normals = match view.normals with
        | Some normals -> array3 normals
        | None -> Bigarray.Array1.create Bigarray.float64 Bigarray.c_layout 0 in
      let colors = Option.map (fun colors ->
          let output = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout
              (Array.length colors * 4) in
          Array.iteri (fun index color ->
            let red, green, blue, alpha = Color.to_floats color in
            Bigarray.Array1.unsafe_set output (index * 4) red;
            Bigarray.Array1.unsafe_set output (index * 4 + 1) green;
            Bigarray.Array1.unsafe_set output (index * 4 + 2) blue;
            Bigarray.Array1.unsafe_set output (index * 4 + 3) alpha) colors;
          output) view.colors in
      let source_indices = if Array.length view.indices = 0
          then Array.init (Mesh.vertex_count value) Fun.id else view.indices in
      let indices = Bigarray.Array1.create Bigarray.int32 Bigarray.c_layout
          (Array.length source_indices) in
      Array.iteri (fun index value ->
          Bigarray.Array1.unsafe_set indices index (Int32.of_int value))
        source_indices;
      let packed = {
        value;
        positions = array3 view.vertices;
        normals;
        colors;
        indices;
        mode = view.mode;
      } in
      cache_add cache source packed;
      packed

let matrix value =
  let output = Bigarray.Array1.create Bigarray.float64 Bigarray.c_layout 16 in
  for column = 0 to 3 do
    for row = 0 to 3 do
      Bigarray.Array1.unsafe_set output ((column * 4) + row)
        (Mat4.get value ~row ~column)
    done
  done;
  output

let integer_state gl name =
  let value = allocate int 0 in
  gl.get_integer name value;
  !@value

let float4 (a, b, c, d) =
  let output = CArray.make float 4 in
  CArray.set output 0 a; CArray.set output 1 b;
  CArray.set output 2 c; CArray.set output 3 d;
  CArray.start output

let color4 color = Color.to_floats color |> float4

let comparison = function
  | Scene3.Never -> gl_never | Less -> gl_less | Equal -> gl_equal
  | Less_equal -> gl_less_equal | Greater -> gl_greater
  | Not_equal -> gl_not_equal | Greater_equal -> gl_greater_equal
  | Always -> gl_always

let stencil_operation = function
  | Scene3.Keep -> gl_keep | Zero -> gl_zero | Replace -> gl_replace
  | Increment -> gl_increment | Decrement -> gl_decrement
  | Increment_wrap -> gl_increment_wrap | Decrement_wrap -> gl_decrement_wrap
  | Invert -> gl_invert

let primitive = function
  | Mesh.Points -> gl_points | Lines -> gl_lines | Line_strip -> gl_line_strip
  | Line_loop -> gl_line_loop | Triangles -> gl_triangles
  | Triangle_strip -> gl_triangle_strip | Triangle_fan -> gl_triangle_fan

let set_blend gl = function
  | Scene3.Replace -> gl.disable gl_blend
  | Alpha ->
      gl.enable gl_blend;
      gl.blend_equation gl_func_add;
      gl.blend_func gl_src_alpha gl_one_minus_src_alpha
  | Add ->
      gl.enable gl_blend;
      gl.blend_equation gl_func_add;
      gl.blend_func gl_src_alpha gl_one
  | Multiply ->
      gl.enable gl_blend;
      gl.blend_equation gl_func_add;
      gl.blend_func gl_dst_color gl_zero
  | Screen ->
      gl.enable gl_blend;
      gl.blend_equation gl_func_add;
      gl.blend_func gl_one gl_one_minus_src_color
  | Subtract ->
      gl.enable gl_blend;
      gl.blend_equation gl_func_reverse_subtract;
      gl.blend_func gl_src_alpha gl_one

let set_depth gl (state : Scene3.depth_state) =
  if state.comparison = Scene3.Always && not state.write then
    gl.disable gl_depth_test
  else begin
    gl.enable gl_depth_test;
    gl.depth_func (comparison state.comparison)
  end;
  gl.depth_mask (if state.write then 1 else 0)

let set_stencil gl (state : Scene3.stencil_state) =
  let inert = state.comparison = Scene3.Always && state.write_mask = 0
      && state.on_stencil_fail = Scene3.Keep
      && state.on_depth_fail = Scene3.Keep && state.on_pass = Scene3.Keep in
  if inert then gl.disable gl_stencil_test
  else begin
    gl.enable gl_stencil_test;
    gl.stencil_func (comparison state.comparison) state.reference state.read_mask;
    gl.stencil_mask state.write_mask;
    gl.stencil_op (stencil_operation state.on_stencil_fail)
      (stencil_operation state.on_depth_fail) (stencil_operation state.on_pass)
  end

let scaled_color color intensity =
  let r, g, b, a = Color.to_floats color in
  Float.min 1. (r *. intensity), Float.min 1. (g *. intensity),
  Float.min 1. (b *. intensity), a

let configure_lights gl ~view scene =
  gl.matrix_mode gl_modelview;
  let view_matrix = matrix view in
  gl.load_matrix (bigarray_start array1 view_matrix);
  let ambient = ref (Color.to_floats (Scene3.Private.ambient scene)) in
  let lights = Scene3.Private.lights scene in
  List.iter (fun light -> match light.Light.kind with
      | Light.Ambient ->
          let ar, ag, ab, aa = !ambient in
          let lr, lg, lb, _ = scaled_color light.ambient light.intensity in
          ambient := Float.min 1. (ar +. lr), Float.min 1. (ag +. lg),
            Float.min 1. (ab +. lb), aa
      | _ -> ()) lights;
  gl.light_model4 gl_light_model_ambient (float4 !ambient);
  for index = 0 to 7 do gl.disable (gl_light0 + index) done;
  let next = ref 0 in
  List.iter (fun light ->
    if !next < 8 then match light.Light.kind with
      | Light.Ambient -> ()
      | kind ->
          let slot = gl_light0 + !next in
          incr next;
          gl.enable slot;
          gl.light4 slot gl_ambient (scaled_color light.ambient light.intensity |> float4);
          gl.light4 slot gl_diffuse (scaled_color light.diffuse light.intensity |> float4);
          gl.light4 slot gl_specular (scaled_color light.specular light.intensity |> float4);
          let position, attenuation, spot = match kind with
            | Light.Directional { direction } ->
                ((-.direction.x, -.direction.y, -.direction.z, 0.),
                 Light.no_attenuation, None)
            | Point { position; attenuation } ->
                ((position.x, position.y, position.z, 1.), attenuation, None)
            | Spot { position; direction; cutoff; concentration; attenuation } ->
                ((position.x, position.y, position.z, 1.), attenuation,
                 Some (direction, cutoff, concentration))
            | Area { position; direction; attenuation; _ } ->
                ((position.x, position.y, position.z, 1.), attenuation,
                 Some (direction, Float.pi /. 2., 1.))
            | Ambient -> assert false in
          gl.light4 slot gl_position (float4 position);
          gl.light1 slot gl_constant_attenuation attenuation.constant;
          gl.light1 slot gl_linear_attenuation attenuation.linear;
          gl.light1 slot gl_quadratic_attenuation attenuation.quadratic;
          (match spot with
           | None -> gl.light1 slot gl_spot_cutoff 180.
           | Some (direction, cutoff, concentration) ->
               gl.light4 slot gl_spot_direction
                 (float4 (direction.x, direction.y, direction.z, 0.));
               gl.light1 slot gl_spot_cutoff
                 (Float.min 90. (cutoff *. 180. /. Float.pi));
               gl.light1 slot gl_spot_exponent (Float.min 128. concentration))
    ) lights;
  if !next = 0 && List.for_all (fun light -> match light.Light.kind with
      | Light.Ambient -> true | _ -> false) lights then gl.disable gl_lighting
  else gl.enable gl_lighting

let supported scene =
  Scene3.Private.shadows scene = []
  && Scene3.Private.fog scene = None
  && not (Scene3.Private.separate_specular scene)
  && let result = ref true in
     Scene3.Private.iter_batches (fun drawing _ ->
       if drawing.Scene3.Private.texture <> None || drawing.shader <> None then
         result := false) scene;
     !result

let draw gl ~view drawing transform =
  let packed = pack_mesh drawing.Scene3.Private.shading drawing.mesh in
  let modelview = Mat4.mul view transform |> matrix in
  gl.matrix_mode gl_modelview;
  gl.load_matrix (bigarray_start array1 modelview);
  set_depth gl drawing.depth;
  set_stencil gl drawing.stencil;
  set_blend gl drawing.blend;
  (match drawing.cull with
   | Scene3.Cull_none -> gl.disable gl_cull_face
   | Cull_back -> gl.enable gl_cull_face; gl.cull_face gl_back
   | Cull_front -> gl.enable gl_cull_face; gl.cull_face gl_front);
  gl.line_width drawing.raster.line_width;
  gl.point_size drawing.raster.point_size;
  gl.shade_model (match drawing.shading with Flat -> gl_flat | Smooth -> gl_smooth);
  gl.polygon_mode gl_front_and_back (match drawing.mode with
      | Scene3.Wireframe -> gl_line | Faces | Vertices -> gl_fill);
  let material = drawing.material in
  gl.material4 gl_front_and_back gl_ambient (color4 material.ambient);
  gl.material4 gl_front_and_back gl_diffuse (color4 material.diffuse);
  gl.material4 gl_front_and_back gl_specular (color4 material.specular);
  gl.material4 gl_front_and_back gl_emission (color4 material.emissive);
  gl.material1 gl_front_and_back gl_shininess material.shininess;
  gl.enable_client_state gl_vertex_array;
  gl.vertex_pointer 3 gl_double 0
    (to_voidp (bigarray_start array1 packed.positions));
  if Bigarray.Array1.dim packed.normals > 0 then begin
    gl.enable gl_normalize;
    gl.enable_client_state gl_normal_array;
    gl.normal_pointer gl_double 0
      (to_voidp (bigarray_start array1 packed.normals))
  end else begin
    gl.disable gl_normalize;
    gl.disable_client_state gl_normal_array
  end;
  (match packed.colors with
   | None ->
       gl.disable gl_color_material;
       gl.disable_client_state gl_color_array;
       gl.color4 1. 1. 1. 1.
   | Some colors ->
       gl.enable gl_color_material;
       gl.color_material gl_front_and_back gl_diffuse;
       gl.enable_client_state gl_color_array;
       gl.color_pointer 4 gl_float 0 (to_voidp (bigarray_start array1 colors)));
  let mode = match drawing.mode with
    | Scene3.Vertices -> gl_points
    | Faces | Wireframe -> primitive packed.mode in
  gl.draw_elements mode (Bigarray.Array1.dim packed.indices) gl_unsigned_int
    (to_voidp (bigarray_start array1 packed.indices))

let render ?viewport ~camera scene =
  if not (supported scene) then
    Error "native GPU backend does not yet support Shader3, textures, shadows, fog, or separate specular"
  else try
    let renderer = Graphics.get_renderer () in
    let renderer_width, renderer_height = match Sdl.get_renderer_output_size renderer with
      | Ok size -> size
      | Error (`Msg message) -> failwith message in
    let logical_width, logical_height = Sdl.render_get_logical_size renderer in
    let logical_width, logical_height =
      if logical_width > 0 && logical_height > 0 then
        logical_width, logical_height
      else renderer_width, renderer_height in
    let logical_viewport = match viewport with
      | None -> 0, 0, logical_width, logical_height
      | Some (x, y, width, height) ->
          if width <= 0 || height <= 0 then
            invalid_arg "Scene.view3d: viewport dimensions must be positive";
          x, y, width, height in
    let scale_edge position logical drawable =
      int_of_float (Float.round
        (float_of_int position *. float_of_int drawable
         /. float_of_int logical)) in
    let logical_x, logical_y, logical_view_width, logical_view_height =
      logical_viewport in
    let x = scale_edge logical_x logical_width renderer_width
    and y = scale_edge logical_y logical_height renderer_height
    and right = scale_edge (logical_x + logical_view_width)
        logical_width renderer_width
    and lower = scale_edge (logical_y + logical_view_height)
        logical_height renderer_height in
    let width = max 1 (right - x) and height = max 1 (lower - y) in
    let flush = Lazy.force sdl_render_flush in
    if flush (Obj.magic renderer) <> 0 then
      Error (Sdl.get_error ())
    else let operation () =
      let gl = Lazy.force api in
      (* SDL's OpenGL renderer leaves its shader and streaming VBOs bound after
         drawing the 2D overlay. Fixed-pipeline client pointers require program
         and buffer zero; these bindings are not covered reliably by the 2.1
         attribute stacks, so preserve them explicitly across every frame. *)
      let previous_program = integer_state gl gl_current_program
      and previous_array_buffer = integer_state gl gl_array_buffer_binding
      and previous_element_buffer =
        integer_state gl gl_element_array_buffer_binding in
      gl.push_attrib gl_all_attrib_bits;
      gl.push_client_attrib (-1);
      gl.matrix_mode gl_projection;
      gl.push_matrix ();
      gl.matrix_mode gl_modelview;
      gl.push_matrix ();
      gl.use_program 0;
      gl.bind_buffer gl_array_buffer 0;
      gl.bind_buffer gl_element_array_buffer 0;
      gl.active_texture gl_texture0;
      gl.disable gl_texture_2d;
      gl.disable gl_alpha_test;
      gl.front_face gl_ccw;
      gl.color_mask 1 1 1 1;
      gl.draw_buffer gl_back;
      Fun.protect
        ~finally:(fun () ->
          gl.matrix_mode gl_modelview;
          gl.pop_matrix ();
          gl.matrix_mode gl_projection;
          gl.pop_matrix ();
          gl.pop_client_attrib ();
          gl.pop_attrib ();
          gl.bind_buffer gl_array_buffer previous_array_buffer;
          gl.bind_buffer gl_element_array_buffer previous_element_buffer;
          gl.use_program previous_program)
        (fun () ->
          let bottom = renderer_height - y - height in
          gl.viewport x bottom width height;
          gl.enable gl_scissor_test;
          gl.scissor x bottom width height;
          gl.clear_depth (Scene3.Private.depth_clear scene);
          gl.clear_stencil (Scene3.Private.stencil_clear scene);
          gl.depth_mask 1;
          gl.stencil_mask 0xff;
          gl.clear (gl_depth_buffer_bit lor gl_stencil_buffer_bit);
          let projection =
            Camera.projection_matrix ~viewport:(x, y, width, height) camera
          and view = Camera.view_matrix camera in
          gl.matrix_mode gl_projection;
          let projection = matrix projection in
          gl.load_matrix (bigarray_start array1 projection);
          configure_lights gl ~view scene;
          Scene3.Private.iter_batches (fun drawing instances ->
            match instances with
            | None -> draw gl ~view drawing drawing.transform
            | Some transforms -> Array.iter (fun instance ->
                draw gl ~view drawing (Mat4.mul drawing.transform instance))
                transforms)
            scene;
          if diagnostics && !diagnostic_frame < 5 then begin
            incr diagnostic_frame;
            let pixels = Bigarray.Array1.create Bigarray.int8_unsigned
                Bigarray.c_layout (width * height * 4) in
            gl.read_pixels x bottom width height gl_rgba gl_unsigned_byte
              (to_voidp (bigarray_start array1 pixels));
            let changed = ref 0 in
            for pixel = 0 to (width * height) - 1 do
              let offset = pixel * 4 in
              if Bigarray.Array1.unsafe_get pixels offset <> 9
                  || Bigarray.Array1.unsafe_get pixels (offset + 1) <> 9
                  || Bigarray.Array1.unsafe_get pixels (offset + 2) <> 11 then
                incr changed
            done;
            Printf.eprintf
              "Prismel native GPU diagnostic frame %d: %d/%d pixels differ from the sketch background (gl error 0x%x)\n%!"
              !diagnostic_frame !changed (width * height) (gl.get_error ())
          end)
    in
    (match Window.with_gpu_context operation with
     | Error message -> Error message
     | Ok () ->
         (* Close the raw-OpenGL side of the boundary before later Scene/PXUI
            calls. The saved GL server/client state above keeps SDL's cached
            assumptions consistent with the actual context state. *)
         if flush (Obj.magic renderer) <> 0 then Error (Sdl.get_error ())
         else begin
           frame_pending := true;
           Ok ()
         end)
  with
  | Dl.DL_error message -> Error message
  | Failure message -> Error message
  | Invalid_argument message -> Error message

let capture ~width ~height ~background ~camera scene =
  if width <= 0 || height <= 0 then
    Error "native GPU capture dimensions must be positive"
  else if not (supported scene) then
    Error "native GPU capture does not support this Scene3 feature set"
  else try
    let renderer = Graphics.get_renderer () in
    let flush = Lazy.force sdl_render_flush in
    if flush (Obj.magic renderer) <> 0 then Error (Sdl.get_error ())
    else
      let result = ref (Error "native GPU capture did not run") in
      match Window.with_gpu_context (fun () ->
        let gl = Lazy.force api in
        let previous_program = integer_state gl gl_current_program
        and previous_array_buffer = integer_state gl gl_array_buffer_binding
        and previous_element_buffer = integer_state gl gl_element_array_buffer_binding
        and previous_framebuffer = integer_state gl gl_framebuffer_binding
        and previous_renderbuffer = integer_state gl gl_renderbuffer_binding in
        let framebuffer = allocate int 0
        and color_buffer = allocate int 0
        and depth_buffer = allocate int 0 in
        gl.gen_framebuffers 1 framebuffer;
        gl.gen_renderbuffers 1 color_buffer;
        gl.gen_renderbuffers 1 depth_buffer;
        Fun.protect
          ~finally:(fun () ->
            gl.bind_framebuffer gl_framebuffer previous_framebuffer;
            gl.bind_renderbuffer gl_renderbuffer previous_renderbuffer;
            gl.delete_renderbuffers 1 depth_buffer;
            gl.delete_renderbuffers 1 color_buffer;
            gl.delete_framebuffers 1 framebuffer)
          (fun () ->
            gl.bind_framebuffer gl_framebuffer !@framebuffer;
            gl.bind_renderbuffer gl_renderbuffer !@color_buffer;
            gl.renderbuffer_storage gl_renderbuffer gl_rgba8 width height;
            gl.framebuffer_renderbuffer gl_framebuffer gl_color_attachment0
              gl_renderbuffer !@color_buffer;
            gl.bind_renderbuffer gl_renderbuffer !@depth_buffer;
            gl.renderbuffer_storage gl_renderbuffer gl_depth24_stencil8 width height;
            gl.framebuffer_renderbuffer gl_framebuffer gl_depth_stencil_attachment
              gl_renderbuffer !@depth_buffer;
            let status = gl.check_framebuffer_status gl_framebuffer in
            if status <> gl_framebuffer_complete then
              failwith (Printf.sprintf
                "OpenGL framebuffer is incomplete (0x%x)" status);
            gl.push_attrib gl_all_attrib_bits;
            gl.push_client_attrib (-1);
            gl.matrix_mode gl_projection;
            gl.push_matrix ();
            gl.matrix_mode gl_modelview;
            gl.push_matrix ();
            Fun.protect
              ~finally:(fun () ->
                gl.matrix_mode gl_modelview;
                gl.pop_matrix ();
                gl.matrix_mode gl_projection;
                gl.pop_matrix ();
                gl.pop_client_attrib ();
                gl.pop_attrib ();
                gl.bind_buffer gl_array_buffer previous_array_buffer;
                gl.bind_buffer gl_element_array_buffer previous_element_buffer;
                gl.use_program previous_program)
              (fun () ->
                gl.use_program 0;
                gl.bind_buffer gl_array_buffer 0;
                gl.bind_buffer gl_element_array_buffer 0;
                gl.active_texture gl_texture0;
                gl.disable gl_texture_2d;
                gl.disable gl_alpha_test;
                gl.front_face gl_ccw;
                gl.color_mask 1 1 1 1;
                gl.draw_buffer gl_color_attachment0;
                gl.read_buffer gl_color_attachment0;
                gl.viewport 0 0 width height;
                gl.enable gl_scissor_test;
                gl.scissor 0 0 width height;
                let red, green, blue, alpha = Color.to_floats background in
                gl.clear_color red green blue alpha;
                gl.clear_depth (Scene3.Private.depth_clear scene);
                gl.clear_stencil (Scene3.Private.stencil_clear scene);
                gl.depth_mask 1;
                gl.stencil_mask 0xff;
                gl.clear (gl_color_buffer_bit lor gl_depth_buffer_bit
                  lor gl_stencil_buffer_bit);
                let viewport = 0, 0, width, height in
                let projection = Camera.projection_matrix ~viewport camera
                and view = Camera.view_matrix camera in
                gl.matrix_mode gl_projection;
                let projection = matrix projection in
                gl.load_matrix (bigarray_start array1 projection);
                configure_lights gl ~view scene;
                Scene3.Private.iter_batches (fun drawing instances ->
                  match instances with
                  | None -> draw gl ~view drawing drawing.transform
                  | Some transforms -> Array.iter (fun instance ->
                      draw gl ~view drawing
                        (Mat4.mul drawing.transform instance)) transforms)
                  scene;
                let bytes = Bigarray.Array1.create Bigarray.int8_unsigned
                    Bigarray.c_layout (width * height * 4) in
                gl.read_pixels 0 0 width height gl_rgba gl_unsigned_byte
                  (to_voidp (bigarray_start array1 bytes));
                let colors = Array.init (width * height) (fun index ->
                  let x = index mod width and y = index / width in
                  let source = (((height - y - 1) * width) + x) * 4 in
                  Color.rgba
                    (Bigarray.Array1.unsafe_get bytes source)
                    (Bigarray.Array1.unsafe_get bytes (source + 1))
                    (Bigarray.Array1.unsafe_get bytes (source + 2))
                    (Bigarray.Array1.unsafe_get bytes (source + 3))) in
                let error = gl.get_error () in
                if error <> 0 then
                  failwith (Printf.sprintf "OpenGL capture error 0x%x" error);
                result := Ok colors))
        ) with
      | Error message -> Error message
      | Ok () -> !result
  with
  | Dl.DL_error message -> Error message
  | Failure message -> Error message
  | Invalid_argument message -> Error message

let release () =
  frame_pending := false;
  Mesh_cache.clear smooth_cache.table;
  Mesh_cache.clear flat_cache.table;
  Queue.clear smooth_cache.order;
  Queue.clear flat_cache.order

let present_if_pending () =
  if not !frame_pending then Ok false
  else begin
    frame_pending := false;
    let renderer = Graphics.get_renderer () in
    let flush = Lazy.force sdl_render_flush in
    if flush (Obj.magic renderer) <> 0 then Error (Sdl.get_error ())
    else Result.map (fun () -> true)
      (Window.with_gpu_context (fun () ->
         if diagnostics
             && !presentation_diagnostic_frame < !diagnostic_frame then begin
           presentation_diagnostic_frame := !diagnostic_frame;
           let width, height = match Sdl.get_renderer_output_size renderer with
             | Ok size -> size | Error _ -> 0, 0 in
           if width > 0 && height > 0 then begin
             let pixels = Bigarray.Array1.create Bigarray.int8_unsigned
                 Bigarray.c_layout (width * height * 4) in
             let gl = Lazy.force api in
             gl.read_pixels 0 0 width height gl_rgba gl_unsigned_byte
               (to_voidp (bigarray_start array1 pixels));
             let changed = ref 0 in
             for pixel = 0 to (width * height) - 1 do
               let offset = pixel * 4 in
               if Bigarray.Array1.unsafe_get pixels offset <> 9
                   || Bigarray.Array1.unsafe_get pixels (offset + 1) <> 9
                   || Bigarray.Array1.unsafe_get pixels (offset + 2) <> 11 then
                 incr changed
             done;
             Printf.eprintf
               "Prismel native GPU presentation diagnostic frame %d: %d/%d pixels differ from the sketch background\n%!"
               !presentation_diagnostic_frame !changed (width * height)
           end
         end;
         (* SDL owns the window renderer and must own its presentation step as
            well. Its OpenGL backend performs the swap after submitting the 2D
            overlay commands that followed the raw Scene3 pass. *)
         Sdl.render_present renderer;
         if diagnostics
             && !front_buffer_diagnostic_frame < !diagnostic_frame then begin
           front_buffer_diagnostic_frame := !diagnostic_frame;
           let width, height = match Sdl.get_renderer_output_size renderer with
             | Ok size -> size | Error _ -> 0, 0 in
           if width > 0 && height > 0 then begin
             let pixels = Bigarray.Array1.create Bigarray.int8_unsigned
                 Bigarray.c_layout (width * height * 4) in
             let gl = Lazy.force api in
             gl.read_buffer gl_front;
             gl.read_pixels 0 0 width height gl_rgba gl_unsigned_byte
               (to_voidp (bigarray_start array1 pixels));
             let changed = ref 0 in
             let visible = ref 0 in
             let max_channel = ref 0 in
             for pixel = 0 to (width * height) - 1 do
               let offset = pixel * 4 in
               let red = Bigarray.Array1.unsafe_get pixels offset
               and green = Bigarray.Array1.unsafe_get pixels (offset + 1)
               and blue = Bigarray.Array1.unsafe_get pixels (offset + 2) in
               max_channel := max !max_channel (max red (max green blue));
               if red + green + blue > 96 then incr visible;
               if red <> 9 || green <> 9 || blue <> 11 then
                 incr changed
             done;
             Printf.eprintf
               "Prismel native GPU front-buffer diagnostic frame %d: %d/%d changed, %d visibly lit, max channel %d\n%!"
               !front_buffer_diagnostic_frame !changed (width * height)
               !visible !max_channel;
             gl.read_buffer gl_back
           end
         end))
  end
