type rgb = float * float * float

type material =
  { albedo : rgb; roughness : float; metallic : float; emission : rgb; round : float }

let material ?(roughness = 0.5) ?(metallic = 0.) ?(emission = (0., 0., 0.)) ?(round = 0.) albedo =
  { albedo; roughness; metallic; emission; round }

type panel =
  { direction : Prismel.Vec3.t
  ; width : float
  ; height : float
  ; softness : float
  ; color : rgb
  ; intensity : float }

let panel ?(softness = 0.05) ?(color = (1., 1., 1.)) ~intensity ~width ~height direction =
  { direction; width; height; softness; color; intensity }

type environment = { sky : rgb; ground : rgb; panels : panel list }
type camera = Prismel.Camera.t

type light =
  { at : Prismel.Vec3.t; target : Prismel.Vec3.t; size : float * float; color : rgb; intensity : float }

let rect_light ?(color = (1., 1., 1.)) ~intensity ~size ~target at =
  { at; target; size; color; intensity }

type scene =
  { objects : (Pdk.Geometry.t * material) list; environment : environment; lights : light list }

let source = Pathtrace_source.source

(* One in-flight frame: its command buffer, which output buffer it writes,
   and whether a camera change made its result obsolete. *)
type pending =
  { commands : Metal.Command_buffer.t; slot : int; mutable stale : bool; preview : bool
  ; camera : camera; history_epoch : int }

type film_texture={portable:Ogpu.Backend.texture option;native:Metal.Texture.t}

type instances = { matrices : float array array; shader_bytes : bytes }

type mesh =
  { mesh_positions : bytes; mesh_normals : bytes; mesh_ids : bytes; triangles : int
  ; mesh_materials : material list; instances : instances option }

type gpu_mesh =
  { positions : Metal.Buffer.t; normals : Metal.Buffer.t
  ; material_ids : Metal.Buffer.t; materials : Metal.Buffer.t
  ; structure : Metal.Acceleration_structure.t
  ; primitive : Metal.Acceleration_structure.t option
  ; instance_descriptor : Metal.Acceleration_structure.Instance.t option
  ; transforms : Metal.Buffer.t option
  ; prototype_key : (bytes * bytes * bytes * bytes) option
  ; mutable owns_prototype : bool }

type mesh_build =
  { gpu : gpu_mesh; scratch : Metal.Buffer.t; commands : Metal.Command_buffer.t }

type t =
  { device : Metal.device
  ; queue : Metal.Command_queue.t
  ; pipeline : Metal.Compute_pipeline.t
  ; library : Metal.Library.t
  ; function_ : Metal.Function.t
  ; instance_pipeline : Metal.Compute_pipeline.t
  ; instance_library : Metal.Library.t
  ; instance_function : Metal.Function.t
  ; resolve_pipeline : Metal.Compute_pipeline.t
  ; resolve_function : Metal.Function.t
  ; mutable gpu : gpu_mesh
  ; mutable building : mesh_build option
  ; mutable queued_mesh : mesh option
  ; panels : Metal.Buffer.t
  ; lights : Metal.Buffer.t
  ; light_count : int
  ; accum : Metal.Buffer.t
  ; outputs : film_texture array
  ; mutable next_output_slot : int
  ; history_color : Metal.Buffer.t array
  ; history_geometry : Metal.Buffer.t array
  ; mutable history_slot : int
  ; mutable history_camera : camera option
  ; mutable history_epoch : int
  ; mutable pending : pending option
  ; mutable completed : int
  ; resource : Prismel_next_resources.Image.t
  ; image : Prismel.Image.t
  ; width : int
  ; height : int
  ; spp : int
  ; bounces : int
  ; exposure : float
  ; round_samples : int
  ; profile : bool
  ; panel_count : int
  ; sky : rgb
  ; ground : rgb
  ; mutable frame : int
  ; mutable camera : camera option
  ; mutable moving : bool
  ; mutable pixels : bytes }

let ( let* ) = Result.bind
let metal result = Result.map_error (Format.asprintf "%a" Metal.pp_error) result
let pdk result = Result.map_error Pdk.Error.to_string result

let put_f32 bytes offset value = Bytes.set_int32_le bytes offset (Int32.bits_of_float value)
let put_u32 bytes offset value = Bytes.set_int32_le bytes offset (Int32.of_int value)

let add_f32 builder value =
  Stdlib.Buffer.add_int32_le builder (Int32.bits_of_float value)

let add_vec3 builder (x, y, z) = add_f32 builder x; add_f32 builder y; add_f32 builder z
let add_float4 builder (x, y, z) w = add_vec3 builder (x, y, z); add_f32 builder w

(* Flattens every object into an unindexed triangle list with per-vertex
   normals and one material index per triangle. Pure: safe on a cook worker. *)
let mesh objects =
  let flatten objects =
  let positions = Stdlib.Buffer.create 4096 and normals = Stdlib.Buffer.create 4096
  and ids = Stdlib.Buffer.create 1024 and count = ref 0 in
  let* () =
    List.fold_left (fun acc (geometry, material_index) ->
      let* () = acc in
      let* triangles = pdk (Pdk.Ops.triangulate geometry) in
      let* triangles =
        pdk (Pdk.Ops.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:(Float.pi /. 4.5) triangles) in
      let topology = Pdk.Geometry.topology triangles in
      let points = Pdk.Geometry.positions triangles in
      let vertex_normals =
        Option.bind
          (Pdk.Geometry.find_attribute ~owner:Pdk.Attribute.Vertex "N" triangles)
          (Pdk.Attribute.get (Pdk.Attribute.normal ~owner:Pdk.Attribute.Vertex))
      in
      let id_bytes = Bytes.create 4 in
      put_u32 id_bytes 0 material_index;
      for primitive = 0 to Pdk.Topology.primitive_count topology - 1 do
        if Pdk.Topology.primitive_size topology primitive = 3 then begin
          Pdk.Topology.iter_primitive_vertices topology primitive (fun vertex point ->
            add_vec3 positions (Pdk.Packed.Float3.get points point);
            add_vec3 normals
              (match vertex_normals with
               | Some field -> Pdk.Packed.Float3.get field vertex
               | None -> (0., 0., 0.)));
          Stdlib.Buffer.add_bytes ids id_bytes;
          incr count
        end
      done;
      Ok ()) (Ok ()) objects
  in
  if !count = 0 then Error "path tracer scene has no triangles"
  else Ok (Stdlib.Buffer.to_bytes positions, Stdlib.Buffer.to_bytes normals, Stdlib.Buffer.to_bytes ids, !count)
  in
  let* (mesh_positions, mesh_normals, mesh_ids, triangles) =
    flatten (List.mapi (fun index (geometry, _) -> (geometry, index)) objects) in
  Ok { mesh_positions; mesh_normals; mesh_ids; triangles
     ; mesh_materials = List.map snd objects; instances = None }

let triangle_count mesh = mesh.triangles

let mesh_instanced ~prototype:(geometry, material) transforms =
  let* prototype = mesh [ (geometry, material) ] in
  let count = Array.length transforms in
  if count = 0 then Error "path tracer instancing needs at least one transform" else
  if prototype.triangles > max_int / count then
    Error "path tracer instanced triangle count overflows" else
  if count > max_int / 84 then Error "path tracer transform storage overflows" else
  let matrices = Array.make count [||] and shader_bytes = Bytes.create (count * 84) in
  let failure = ref None in
  Array.iteri (fun instance matrix ->
    let values = Array.init 16 (fun index ->
      Prismel.Mat4.get matrix ~row:(index / 4) ~column:(index mod 4)) in
    let a = values.(0) and b = values.(1) and c = values.(2)
    and d = values.(4) and e = values.(5) and f = values.(6)
    and g = values.(8) and h = values.(9) and i = values.(10) in
    let cofactors = [| e *. i -. f *. h; c *. h -. b *. i; b *. f -. c *. e
                     ; f *. g -. d *. i; a *. i -. c *. g; c *. d -. a *. f
                     ; d *. h -. e *. g; b *. g -. a *. h; a *. e -. b *. d |] in
    let determinant = a *. cofactors.(0) +. b *. cofactors.(3) +. c *. cofactors.(6) in
    if not (Array.for_all (fun value -> Float.is_finite value
      && Float.abs value <= 3.402823466e38) values)
       || Float.abs values.(12) > 1e-6 || Float.abs values.(13) > 1e-6
       || Float.abs values.(14) > 1e-6 || Float.abs (values.(15) -. 1.) > 1e-6
       || not (Float.is_finite determinant) || determinant = 0.
    then failure := Some "path tracer instance transform must be finite, affine, and nonsingular"
    else begin
        matrices.(instance) <- values;
        let base = instance * 84 in
        for column = 0 to 3 do
          for row = 0 to 2 do
            put_f32 shader_bytes (base + (column * 3 + row) * 4)
              values.(row * 4 + column)
          done
        done;
        for column = 0 to 2 do
          for row = 0 to 2 do
            let value = cofactors.(column * 3 + row) /. determinant in
            if not (Float.is_finite value) || Float.abs value > 3.402823466e38 then
              failure := Some "path tracer instance normal transform exceeds float32 range";
            put_f32 shader_bytes (base + 48 + (column * 3 + row) * 4)
              value
          done
        done
    end) transforms;
  match !failure with
  | Some message -> Error message
  | None -> Ok { prototype with triangles = prototype.triangles * count
            ; instances = Some { matrices; shader_bytes } }

let material_bytes materials =
  let builder = Stdlib.Buffer.create 256 in
  List.iter (fun m ->
    add_float4 builder m.albedo m.roughness;
    add_float4 builder m.emission m.metallic;
    add_float4 builder (m.round, 0., 0.) 0.) materials;
  Stdlib.Buffer.to_bytes builder

let panel_bytes panels =
  let builder = Stdlib.Buffer.create 256 in
  let normalize (v : Prismel.Vec3.t) =
    let l = sqrt ((v.x *. v.x) +. (v.y *. v.y) +. (v.z *. v.z)) in
    let l = if l = 0. then 1. else l in
    (v.x /. l, v.y /. l, v.z /. l)
  in
  List.iter (fun (p : panel) ->
    let (r, g, b) = p.color in
    add_float4 builder (normalize p.direction) 0.;
    add_float4 builder (r *. p.intensity, g *. p.intensity, b *. p.intensity) 0.;
    add_float4 builder (p.width, p.height, p.softness) 0.) panels;
  if panels = [] then Stdlib.Buffer.add_bytes builder (Bytes.make 48 '\000');
  Stdlib.Buffer.to_bytes builder

let light_bytes lights =
  let builder = Stdlib.Buffer.create 256 in
  let open Prismel.Vec3 in
  let sub a b = create (a.x -. b.x) (a.y -. b.y) (a.z -. b.z) in
  let cross a b = create ((a.y *. b.z) -. (a.z *. b.y)) ((a.z *. b.x) -. (a.x *. b.z)) ((a.x *. b.y) -. (a.y *. b.x)) in
  let normalize v =
    let l = sqrt ((v.x *. v.x) +. (v.y *. v.y) +. (v.z *. v.z)) in
    if l = 0. then create 0. 0. 1. else create (v.x /. l) (v.y /. l) (v.z /. l)
  in
  List.iter (fun (light : light) ->
    let w, h = light.size in
    let forward = normalize (sub light.target light.at) in
    let world_up = if Float.abs forward.y > 0.999 then create 0. 0. 1. else create 0. 1. 0. in
    let right = normalize (cross forward world_up) in
    let up = cross right forward in
    let u = create (right.x *. w) (right.y *. w) (right.z *. w)
    and v = create (up.x *. h) (up.y *. h) (up.z *. h) in
    let origin = create (light.at.x -. ((u.x +. v.x) /. 2.)) (light.at.y -. ((u.y +. v.y) /. 2.))
        (light.at.z -. ((u.z +. v.z) /. 2.)) in
    let (r, g, b) = light.color in
    add_float4 builder (origin.x, origin.y, origin.z) 0.;
    add_float4 builder (u.x, u.y, u.z) 0.;
    add_float4 builder (v.x, v.y, v.z) 0.;
    add_float4 builder (r *. light.intensity, g *. light.intensity, b *. light.intensity) (w *. h))
    lights;
  if lights = [] then Stdlib.Buffer.add_bytes builder (Bytes.make 64 '\000');
  Stdlib.Buffer.to_bytes builder

let shared device bytes = metal (Metal.Buffer.create_copy ~device ~storage:Metal.Buffer.Shared bytes)

let destroy_gpu gpu =
  Option.iter (fun descriptor -> ignore (Metal.Acceleration_structure.Instance.destroy descriptor))
    gpu.instance_descriptor;
  Option.iter (fun transforms -> ignore (Metal.Buffer.destroy transforms)) gpu.transforms;
  ignore (Metal.Acceleration_structure.destroy gpu.structure);
  if gpu.owns_prototype then begin
    List.iter (fun buffer -> ignore (Metal.Buffer.destroy buffer))
      [gpu.positions; gpu.normals; gpu.material_ids; gpu.materials];
    Option.iter (fun primitive -> ignore (Metal.Acceleration_structure.destroy primitive)) gpu.primitive
  end

(* Submit the replacement build without waiting. The old scene remains live
   until both the build and every render that used it have completed. *)
let upload_mesh_async ?reuse device queue mesh =
  let buffers = ref [] and structures = ref [] and instance_descriptor = ref None
  and scratch = ref None and commands = ref None in
  let buffer bytes =
    let* value = shared device bytes in
    buffers := value :: !buffers;
    Ok value in
  let material_data = material_bytes mesh.mesh_materials in
  let reused = match reuse, mesh.instances with
    | Some gpu, Some _ ->
        (match gpu.prototype_key, gpu.primitive with
         | Some (positions, normals, ids, materials), Some primitive
           when Bytes.equal positions mesh.mesh_positions
             && Bytes.equal normals mesh.mesh_normals
             && Bytes.equal ids mesh.mesh_ids
             && Bytes.equal materials material_data -> Some (gpu, primitive)
         | _ -> None)
    | _ -> None in
  let result =
    let* (positions, normals, material_ids, materials, primitive, triangle, primitive_scratch) =
      match reused with
      | Some (gpu, primitive) ->
          Ok (gpu.positions, gpu.normals, gpu.material_ids, gpu.materials,
              primitive, None, 0L)
      | None ->
          let* positions = buffer mesh.mesh_positions in
          let* normals = buffer mesh.mesh_normals in
          let* material_ids = buffer mesh.mesh_ids in
          let* materials = buffer material_data in
          let* triangle =
            metal (Metal.Acceleration_structure.Triangle.create ~vertex_buffer:positions
              ~vertex_stride:12L
              ~triangle_count:(Int64.of_int (Bytes.length mesh.mesh_positions / 36)) ()) in
          let* sizes = metal (Metal.Acceleration_structure.sizes ~device triangle) in
          let* primitive = metal (Metal.Acceleration_structure.create ~device
            ~size:sizes.acceleration_structure_size) in
          structures := primitive :: !structures;
          Ok (positions, normals, material_ids, materials, primitive,
              Some triangle, sizes.build_scratch_buffer_size) in
    let* (structure, descriptor, transforms, scratch_size) =
      match mesh.instances with
      | None -> Ok (primitive, None, None, primitive_scratch)
      | Some instances ->
          let* transforms = buffer instances.shader_bytes in
          let* descriptor = metal (Metal.Acceleration_structure.Instance.create
            ~device ~primitive ~transforms:instances.matrices) in
          instance_descriptor := Some descriptor;
          let* sizes = metal (Metal.Acceleration_structure.sizes_instances ~device descriptor) in
          let* top = metal (Metal.Acceleration_structure.create ~device
            ~size:sizes.acceleration_structure_size) in
          structures := top :: !structures;
          Ok (top, Some descriptor, Some transforms,
              Int64.max primitive_scratch sizes.build_scratch_buffer_size) in
    let* work =
      metal (Metal.Buffer.create ~device ~length:scratch_size
        ~storage:Metal.Buffer.Private ()) in
    scratch := Some work;
    let* command = metal (Metal.Command_buffer.create queue ()) in
    commands := Some command;
    let* () = match triangle with
      | None -> Ok ()
      | Some triangle ->
          let* encoder = metal (Metal.Acceleration_encoder.create command) in
          let* () = metal (Metal.Acceleration_encoder.build encoder ~destination:primitive
            ~descriptor:triangle ~scratch:work ~scratch_offset:0L) in
          metal (Metal.Acceleration_encoder.end_encoding encoder) in
    let* () = match descriptor with
      | None -> Ok ()
      | Some descriptor ->
          let* encoder = metal (Metal.Acceleration_encoder.create command) in
          let* () = metal (Metal.Acceleration_encoder.build_instances encoder
            ~destination:structure ~descriptor ~scratch:work ~scratch_offset:0L) in
          metal (Metal.Acceleration_encoder.end_encoding encoder) in
    let* () = metal (Metal.Command_buffer.commit command) in
    Ok { gpu = {positions; normals; material_ids; materials; structure
                ; primitive = (if descriptor = None then None else Some primitive)
                ; instance_descriptor = descriptor; transforms
                ; prototype_key = (match mesh.instances with None -> None | Some _ ->
                    Some (mesh.mesh_positions, mesh.mesh_normals, mesh.mesh_ids, material_data))
                ; owns_prototype = (reused = None)}
       ; scratch = work; commands = command } in
  match result with
  | Ok _ as ready -> ready
  | Error _ as failure ->
      Option.iter (fun command -> ignore (Metal.Command_buffer.destroy command)) !commands;
      Option.iter (fun work -> ignore (Metal.Buffer.destroy work)) !scratch;
      Option.iter (fun descriptor -> ignore (Metal.Acceleration_structure.Instance.destroy descriptor)) !instance_descriptor;
      List.iter (fun built -> ignore (Metal.Acceleration_structure.destroy built)) !structures;
      List.iter (fun value -> ignore (Metal.Buffer.destroy value)) !buffers;
      failure

let finish_build build =
  let waited = metal (Metal.Command_buffer.wait_until_completed build.commands) in
  ignore (Metal.Command_buffer.destroy build.commands);
  ignore (Metal.Buffer.destroy build.scratch);
  match waited with
  | Ok () -> Ok build.gpu
  | Error _ as failure -> destroy_gpu build.gpu; failure

let discard_build build =
  ignore (Metal.Command_buffer.destroy build.commands);
  ignore (Metal.Buffer.destroy build.scratch);
  destroy_gpu build.gpu

let upload_mesh device queue mesh =
  let* build = upload_mesh_async device queue mesh in
  finish_build build

let create ?(spp = 1) ?(bounces = 6) ?(exposure = 1.) ?(round_samples = 4) ~width ~height scene =
  if width <= 0 || height <= 0 then Error "path tracer size must be positive"
  else if spp <= 0 || bounces <= 0 then Error "path tracer spp and bounces must be positive"
  else
  let* device = metal (Metal.Device.system_default ()) in
  let* info = metal (Metal.Device.info device) in
  if not info.raytracing then Error "Metal device does not support ray tracing"
  else
  let* mesh = mesh scene.objects in
  let* queue = metal (Metal.Command_queue.create device) in
  let* gpu = upload_mesh device queue mesh in
  let* panels = shared device (panel_bytes scene.environment.panels) in
  let* lights = shared device (light_bytes scene.lights) in
  let* library = metal (Metal.Library.compile_source ~label:"prismel_pathtracer" ~device source) in
  let* function_ = metal (Metal.Function.find ~library "pathtrace") in
  let* pipeline = metal (Metal.Compute_pipeline.create function_) in
  let* resolve_function = metal (Metal.Function.find ~library "resolve_preview") in
  let* resolve_pipeline = metal (Metal.Compute_pipeline.create resolve_function) in
  let* instance_library = metal (Metal.Library.compile_source
    ~label:"prismel_pathtracer_instanced" ~device ("#define INSTANCED 1\n" ^ source)) in
  let* instance_function = metal (Metal.Function.find ~library:instance_library "pathtrace_instanced") in
  let* instance_pipeline = metal (Metal.Compute_pipeline.create instance_function) in
  let pixel_count = width * height in
  let* accum =
    metal (Metal.Buffer.create ~device ~length:(Int64.of_int (pixel_count * 16))
      ~storage:Metal.Buffer.Private ()) in
  let history () = metal (Metal.Buffer.create ~device
    ~length:(Int64.of_int (pixel_count * 16)) ~storage:Metal.Buffer.Private ()) in
  let* color0 = history () in
  let* color1 = history () in
  let* geometry0 = history () in
  let* geometry1 = history () in
  let pixels = Bytes.make (pixel_count * 4) '\000' in
  let* resource =
    Result.map_error (Format.asprintf "%a" Prismel_next_resources.pp_error)
      (Prismel_next_resources.Image.create ~width ~height ~rgba:(Bytes.copy pixels)) in
  let* outputs = match Prismel_next_execution.Private.active_window_runtime() with
    |None->
        let create()=Result.map(fun native->{portable=None;native})
          (metal(Metal.Texture.create ~device
            (Metal.Texture.descriptor_2d ~storage:Metal.Buffer.Shared
              ~usage:[Metal.Texture.Shader_write] ~format:Metal.Texture.Rgba8_unorm
              ~width ~height ())))in
        let* output0=create()in
        (match create()with
        |Ok output1->Ok[|output0;output1|]
        |Error _ as failure->ignore(Metal.Texture.destroy output0.native);failure)
    |Some runtime->
        let create()=Result.map_error Ogpu.Error.to_string
          (Runtime_next_orchestrator.gpu_film_texture runtime ~width ~height) in
        let* portable0,native0=create() in
        (match create() with
        |Ok(portable1,native1)->Ok[|{portable=Some portable0;native=native0};
            {portable=Some portable1;native=native1}|]
        |Error _ as failure->ignore(Ogpu.Backend.destroy_texture portable0);failure) in
  Ok { device; queue; pipeline; library; function_; instance_pipeline; instance_library
     ; instance_function; resolve_pipeline; resolve_function
     ; gpu; building = None; queued_mesh = None
     ; panels; lights; light_count = List.length scene.lights; accum
     ; outputs;next_output_slot=0
     ; history_color = [|color0; color1|]
     ; history_geometry = [|geometry0; geometry1|]
     ; history_slot = 0; history_camera = None; history_epoch = 0
     ; pending = None; completed = 0; resource
     ; image = Prismel.Image.Private.of_resource resource; width; height; spp; bounces
     ; exposure; round_samples;profile=(Sys.getenv_opt"PRISMEL_PATHTRACER_PROFILE"=Some"1")
     ; panel_count = List.length scene.environment.panels
     ; sky = scene.environment.sky; ground = scene.environment.ground; frame = 0
     ; camera = None; moving = false; pixels }

let camera_fov camera =
  match Prismel.Camera.projection camera with
  | Perspective { fov_y; lens_offset; _ }
    when lens_offset = Prismel.Vec2.zero
      && not (Prismel.Camera.v_flip camera)
      && Prismel.Camera.forced_aspect camera = None -> Ok fov_y
  | _ -> Error "path tracer requires an unshifted perspective camera"

let uniform_bytes t (camera : camera) fov =
  let open Prismel.Vec3 in
  let sub a b = create (a.x -. b.x) (a.y -. b.y) (a.z -. b.z) in
  let cross a b = create ((a.y *. b.z) -. (a.z *. b.y)) ((a.z *. b.x) -. (a.x *. b.z)) ((a.x *. b.y) -. (a.y *. b.x)) in
  let normalize v =
    let l = sqrt ((v.x *. v.x) +. (v.y *. v.y) +. (v.z *. v.z)) in
    if l = 0. then create 0. 0. 1. else create (v.x /. l) (v.y /. l) (v.z /. l)
  in
  let axes (camera : camera) =
    let forward = normalize (sub (Prismel.Camera.target camera)
        (Prismel.Camera.position camera)) in
    let camera_up = Prismel.Camera.up camera in
    let world_up = if Float.abs (dot forward camera_up) > 0.999 then
        if Float.abs forward.y > 0.999 then create 0. 0. 1.
        else create 0. 1. 0.
      else camera_up in
    let right = normalize (cross forward world_up) in
    forward, right, cross right forward in
  let forward, right, up = axes camera in
  let bytes = Bytes.make 208 '\000' in
  let put_vec4 offset (v : Prismel.Vec3.t) w =
    put_f32 bytes offset v.x; put_f32 bytes (offset + 4) v.y; put_f32 bytes (offset + 8) v.z;
    put_f32 bytes (offset + 12) w
  in
  let put_rgb offset (r, g, b) = put_vec4 offset (create r g b) 0. in
  put_vec4 0 (Prismel.Camera.position camera) 0.;
  put_vec4 16 forward (tan (fov /. 2.));
  put_vec4 32 right (float_of_int t.width /. float_of_int t.height);
  put_vec4 48 up 0.;
  put_rgb 64 t.sky;
  put_rgb 80 t.ground;
  put_u32 bytes 96 t.width; put_u32 bytes 100 t.height; put_u32 bytes 104 t.frame;
  put_u32 bytes 108 t.spp; put_u32 bytes 112 t.panel_count; put_u32 bytes 116 t.bounces;
  put_f32 bytes 120 t.exposure; put_u32 bytes 124 t.round_samples;
  put_u32 bytes 128 t.light_count; put_u32 bytes 132 (if t.moving then 1 else 0);
  let* () = match t.history_camera with
   | None -> Ok ()
   | Some previous ->
       let* previous_fov = camera_fov previous in
       let forward, right, up = axes previous in
       put_u32 bytes 136 1;
       put_vec4 144 (Prismel.Camera.position previous) 0.;
       put_vec4 160 forward (tan (previous_fov /. 2.));
       put_vec4 176 right (float_of_int t.width /. float_of_int t.height);
       put_vec4 192 up 0.;
       Ok () in
  Ok bytes

let reset_samples t =
  t.frame <- 0;
  t.completed <- 0

let reset t =
  reset_samples t;
  Option.iter (fun pending -> pending.stale <- true) t.pending;
  t.history_camera <- None;
  t.history_epoch <- t.history_epoch + 1

let install_gpu t gpu =
  (match t.gpu.primitive, gpu.primitive with
   | Some old, Some next when old == next ->
       t.gpu.owns_prototype <- false;
       gpu.owns_prototype <- true
   | _ -> ());
  destroy_gpu t.gpu;
  t.gpu <- gpu;
  reset t
let samples t = t.completed * t.spp
let size t = (t.width, t.height)
let image t = t.image
let pixels t=match Prismel_next_resources.Image.Private.gpu_snapshot t.resource with
  |None->t.pixels
  |Some _->(match Prismel_next_resources.Image.pixels t.resource with
    |Ok pixels->t.pixels<-pixels;pixels
    |Error error->failwith(Format.asprintf"%a"Prismel_next_resources.pp_error error))

(* Waits for the in-flight frame, if any, and publishes its pixels unless a
   reset made them obsolete. *)
let publish t (pending : pending) =
  t.pending <- None;
  (if t.profile then
    match Metal.Command_buffer.diagnostics pending.commands with
    |Ok diagnostics->Printf.eprintf"pathtracer gpu_ms %.4f\n%!"
        ((diagnostics.gpu_end_time-.diagnostics.gpu_start_time)*.1000.)
    |Error _->());
  let* () = metal (Metal.Command_buffer.destroy pending.commands) in
  if pending.history_epoch = t.history_epoch then
    t.history_camera <- Some pending.camera;
  if pending.stale then Ok ()
  else match t.outputs.(pending.slot).portable with
  |Some film->
      let* ()=Result.map_error (Format.asprintf "%a" Prismel_next_resources.pp_error)
        (Prismel_next_resources.Image.Private.replace_gpu t.resource
          film) in
      if not pending.preview then t.completed<-t.completed+1;
      Ok ()
  |None->
        let* rgba =
          metal (Metal.Texture.read_bytes t.outputs.(pending.slot).native
            ~region:{x=0;y=0;z=0;width=t.width;height=t.height;depth=1}
            ~mip_level:0 ~slice:0 ~bytes_per_row:(t.width*4)
            ~bytes_per_image:(t.width*t.height*4)) in
        t.pixels <- rgba;
        let* () = Result.map_error (Format.asprintf "%a" Prismel_next_resources.pp_error)
          (Prismel_next_resources.Image.replace t.resource ~width:t.width ~height:t.height
             ~rgba) in
        if not pending.preview then t.completed <- t.completed + 1;
        Ok ()

let poll_build t =
  match t.building with
  | None -> Ok ()
  | Some build ->
      let* status = metal (Metal.Command_buffer.status build.commands) in
      (match status with
       | Metal.Command_buffer.Completed | Error _ ->
           t.building <- None;
           let built = finish_build build in
           (match t.queued_mesh with
            | Some latest ->
                t.queued_mesh <- None;
                (match built with Ok gpu -> destroy_gpu gpu | Error _ -> ());
                let* next = upload_mesh_async ~reuse:t.gpu t.device t.queue latest in
                t.building <- Some next;
                Ok ()
            | None ->
                let* gpu = built in
                install_gpu t gpu;
                Ok ())
       | _ -> Ok ())

let flush t =
  let* () = match t.pending with
    | None -> Ok ()
    | Some pending ->
        (match metal (Metal.Command_buffer.wait_until_completed pending.commands) with
         | Ok () -> publish t pending
         | Error _ as failure ->
             t.pending <- None;
             ignore (Metal.Command_buffer.destroy pending.commands);
             failure) in
  let rec finish_updates () = match t.building with
    | None -> Ok ()
    | Some build ->
        (match metal (Metal.Command_buffer.wait_until_completed build.commands) with
         | Ok () ->
             let* () = poll_build t in
             finish_updates ()
         | Error _ as failure ->
             t.building <- None;
             discard_build build;
             failure) in
  finish_updates ()

(* Publishes the in-flight frame only if the GPU has finished it; never
   blocks the caller. Returns whether the tracer is free to submit. *)
let poll t =
  match t.pending with
  | None -> Ok true
  | Some pending ->
      let* status = metal (Metal.Command_buffer.status pending.commands) in
      (match status with
       | Metal.Command_buffer.Completed -> let* () = publish t pending in Ok true
       | Error message ->
           t.pending <- None;
           ignore (Metal.Command_buffer.destroy pending.commands);
           Error ("path tracer frame failed: " ^ message)
       | _ -> Ok false)

(* One frame of latency: the frame submitted here is read back by the next
   [render] (or [flush]), so the CPU never waits on the GPU while the display
   pipeline runs. Both strategies share the accumulation buffer in queue order. *)
let render t (camera : camera) =
  let* fov = camera_fov camera in
  (* Only a change from a previous camera is a preview frame; the first frame
     after creation, reset, or a mesh swap renders at full quality. *)
  let was_moving = t.moving in
  t.moving <- (match t.camera with Some previous -> previous <> camera | None -> false);
  if t.camera <> Some camera || was_moving then reset_samples t;
  t.camera <- Some camera;
  let* free = poll t in
  if not free then Ok () else
  let* () = poll_build t in
  let* uniforms = uniform_bytes t camera fov in
  let slot = t.next_output_slot in
  let previous_history = t.history_slot in
  let next_history = previous_history lxor 1 in
  let threads = (t.width, t.height, 1) in
  let* commands = metal (Metal.Command_buffer.create t.queue ()) in
  let* encoder = metal (Metal.Compute_encoder.create commands) in
  let set index buffer = metal (Metal.Compute_encoder.set_buffer encoder ~index ~offset:0L buffer) in
  let* () = metal (Metal.Compute_encoder.set_pipeline encoder
    (if t.gpu.transforms = None then t.pipeline else t.instance_pipeline)) in
  let* () = metal (Metal.Compute_encoder.set_acceleration_structure encoder ~index:0 (Some t.gpu.structure)) in
  let* () = metal (Metal.Compute_encoder.set_bytes encoder ~index:1 uniforms) in
  let* () = set 2 t.gpu.positions in
  let* () = set 3 t.gpu.normals in
  let* () = set 4 t.gpu.material_ids in
  let* () = set 5 t.gpu.materials in
  let* () = set 6 t.panels in
  let* () = set 7 t.accum in
  let* () = metal(Metal.Compute_encoder.set_texture encoder ~index:0
    t.outputs.(slot).native) in
  let* () = set 9 t.lights in
  let* () = match t.gpu.transforms with None -> Ok () | Some transforms -> set 10 transforms in
  let* () = set 11 t.history_color.(previous_history) in
  let* () = set 12 t.history_geometry.(previous_history) in
  let* () = set 13 t.history_color.(next_history) in
  let* () = set 14 t.history_geometry.(next_history) in
  let* () =
    metal (Metal.Compute_encoder.dispatch_threads encoder ~threads ~threadgroup:(16, 16, 1)) in
  let* () = metal (Metal.Compute_encoder.end_encoding encoder) in
  let* () = if not t.moving then Ok () else
    let* resolve = metal (Metal.Compute_encoder.create commands) in
    let set index buffer = metal (Metal.Compute_encoder.set_buffer resolve ~index ~offset:0L buffer) in
    let* () = metal (Metal.Compute_encoder.set_pipeline resolve t.resolve_pipeline) in
    let* () = metal (Metal.Compute_encoder.set_bytes resolve ~index:0 uniforms) in
    let* () = set 1 t.history_color.(next_history) in
    let* () = set 2 t.history_geometry.(next_history) in
    let* () = metal(Metal.Compute_encoder.set_texture resolve ~index:0
      t.outputs.(slot).native) in
    let* () = metal (Metal.Compute_encoder.dispatch_threads resolve ~threads ~threadgroup:(16, 16, 1)) in
    metal (Metal.Compute_encoder.end_encoding resolve) in
  let* () = metal (Metal.Command_buffer.commit commands) in
  t.next_output_slot<-slot lxor 1;
  t.history_slot <- next_history;
  t.pending <- Some { commands; slot; stale = false; preview = t.moving
                    ; camera; history_epoch = t.history_epoch };
  (* A preview frame is shown but never counted: accumulation restarts at
     frame zero once the camera rests. *)
  if not t.moving then t.frame <- t.frame + 1;
  Ok ()

(* Swaps the geometry (buffers and acceleration structure) under the same
   pipeline and lights, then restarts accumulation. *)
let replace_mesh t mesh =
  Option.iter (fun pending -> pending.stale <- true) t.pending;
  let* () = flush t in
  let* build = upload_mesh_async ~reuse:t.gpu t.device t.queue mesh in
  let* gpu = finish_build build in
  install_gpu t gpu;
  Ok ()

let queue_mesh t mesh =
  match t.building with
  | Some _ -> t.queued_mesh <- Some mesh; Ok ()
  | None ->
      let* build = upload_mesh_async ~reuse:t.gpu t.device t.queue mesh in
      t.building <- Some build;
      Ok ()

let destroy t =
  let release f = ignore (f ()) in
  Option.iter (fun pending -> pending.stale <- true) t.pending;
  release (fun () -> flush t);
  Prismel.Image.destroy t.image;
  release (fun () -> Metal.Compute_pipeline.destroy t.pipeline);
  release (fun () -> Metal.Function.destroy t.function_);
  release (fun () -> Metal.Compute_pipeline.destroy t.resolve_pipeline);
  release (fun () -> Metal.Function.destroy t.resolve_function);
  release (fun () -> Metal.Library.destroy t.library);
  release (fun () -> Metal.Compute_pipeline.destroy t.instance_pipeline);
  release (fun () -> Metal.Function.destroy t.instance_function);
  release (fun () -> Metal.Library.destroy t.instance_library);
  destroy_gpu t.gpu;
  List.iter (fun buffer -> release (fun () -> Metal.Buffer.destroy buffer))
    [ t.panels; t.lights; t.accum
    ; t.history_color.(0); t.history_color.(1)
    ; t.history_geometry.(0); t.history_geometry.(1) ];
  Array.iter(fun film->match film.portable with
    |Some portable->ignore(Ogpu.Backend.destroy_texture portable)
    |None->release(fun()->Metal.Texture.destroy film.native))t.outputs;
  release (fun () -> Metal.Command_queue.destroy t.queue);
  release (fun () -> Metal.Device.destroy t.device);
  release (fun () -> Metal.Release_queue.drain ())
