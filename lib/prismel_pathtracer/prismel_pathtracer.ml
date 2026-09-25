module Linear_color = struct
  type t = { r : float; g : float; b : float }

  let rgb r g b = { r; g; b }
end

type material = {
  albedo : Linear_color.t;
  roughness : float;
  metallic : float;
  emission : Linear_color.t;
  round : float;
}

let material ?(roughness = 0.5) ?(metallic = 0.)
    ?(emission = Linear_color.rgb 0. 0. 0.) ?(round = 0.) albedo =
  { albedo; roughness; metallic; emission; round }

type panel = {
  direction : Prismel.Vec3.t;
  width : float;
  height : float;
  softness : float;
  color : Linear_color.t;
  intensity : float;
}

let panel ?(softness = 0.05) ?(color = Linear_color.rgb 1. 1. 1.) ~intensity ~width ~height direction =
  { direction; width; height; softness; color; intensity }

type environment = { sky : Linear_color.t; ground : Linear_color.t; panels : panel list }
type camera = Prismel.Camera.t

type light = {
  at : Prismel.Vec3.t;
  target : Prismel.Vec3.t;
  size : float * float;
  color : Linear_color.t;
  intensity : float;
}

let rect_light ?(color = Linear_color.rgb 1. 1. 1.) ~intensity ~size ~target at =
  { at; target; size; color; intensity }

type sphere = { center : Prismel.Vec3.t; radius : float; sphere_material : material }

let sphere ~radius sphere_material center = { center; radius; sphere_material }

type strand = { points : Prismel.Vec3.t array; thickness : float; strand_material : material }

let strand ~thickness strand_material points = { points; thickness; strand_material }

type scene = {
  objects : (Pdk.Geometry.t * material) list;
  spheres : sphere list;
  strands : strand list;
  environment : environment;
  lights : light list;
}

let source = Pathtrace_source.source

module B = Ogpu.Backend

(* One in-flight frame: its receipt, which output texture it writes, and
   whether a camera change made its result obsolete. *)
type pending = {
  receipt : B.receipt;
  slot : int;
  mutable stale : bool;
  preview : bool;
  camera : camera;
  history_epoch : int;
}

(* Instances carry a user id selecting their material; with [motion] every
   instance has two transform keyframes (start and end of the shutter). *)
type instances = {
  records : B.instance_record array;
  shader_bytes : bytes;
  motion_transforms : float array array option;
}

(* Prepared analytic primitives: spheres as bounding boxes resolved by an
   intersection function, strands as linear round curves. *)
type extras = {
  sphere_bytes : bytes;
  box_bytes : bytes;
  sphere_count : int;
  strand_points : bytes;
  strand_radii : bytes;
  strand_indices : bytes;
  strand_ids : bytes;
  strand_point_count : int;
  strand_segments : int;
}

type mesh = {
  mesh_positions : bytes;
  mesh_normals : bytes;
  mesh_ids : bytes;
  triangles : int;
  mesh_materials : material list;
  instances : instances option;
  extras : extras;
}

(* The shape of the pipeline a mesh needs. *)
type shape = { instanced : bool; motion : bool; spheres : bool; curves : bool }

type gpu_mesh = {
  positions : B.buffer;
  normals : B.buffer;
  material_ids : B.buffer;
  materials : B.buffer;
  sphere_buffer : B.buffer option;
  box_buffer : B.buffer option;
  strands : (B.buffer * B.buffer * B.buffer * B.buffer) option;
  mutable structure : B.accel;
  mutable primitive : B.accel option;
  instance_buffer : B.buffer option;
  transforms : B.buffer option;
  motion_buffer : B.buffer option;
  prototype_key : (bytes * bytes * bytes * bytes * bytes) option;
  mutable owns_prototype : bool;
  shape : shape;
}

(* A replacement build runs in stages: the primitive structure builds and
   writes its compacted size; then it is compacted into a right-sized
   structure and the instance structure (if any) builds over the compacted
   one; then the uncompacted structure is released. *)
type stage =
  | Building of B.receipt
  | Compacting of B.receipt
  | Ready

type mesh_build = {
  gpu : gpu_mesh;
  scratch : B.buffer;
  mutable extra_scratch : B.buffer option;
  mutable size_buffer : B.buffer option;
  mutable uncompacted : B.accel option;
  mutable stage : stage;
  instance_count : int;
}

type t = {
  lease : Prismel_next_execution.gpu;
  device : B.device;
  queue : B.queue;
  library : B.library;
  pipelines : (shape, B.pipeline * B.function_table option) Hashtbl.t;
  resolve_pipeline : B.pipeline;
  mutable gpu : gpu_mesh;
  mutable building : mesh_build option;
  mutable queued_mesh : mesh option;
  panels : B.buffer;
  lights : B.buffer;
  light_count : int;
  accum : B.buffer;
  outputs : B.texture array;
  shared_film : bool;
  mutable next_output_slot : int;
  history_color : B.buffer array;
  history_geometry : B.buffer array;
  mutable history_slot : int;
  mutable history_camera : camera option;
  mutable history_epoch : int;
  mutable pending : pending option;
  mutable completed : int;
  resource : Prismel_next_resources.Image.t;
  image : Prismel.Image.t;
  width : int;
  height : int;
  spp : int;
  bounces : int;
  exposure : float;
  round_samples : int;
  profile : bool;
  panel_count : int;
  sky : Linear_color.t;
  ground : Linear_color.t;
  mutable frame : int;
  mutable camera : camera option;
  mutable moving : bool;
  mutable pixels : bytes;
}

let ( let* ) = Result.bind
let gpu result = Result.map_error Ogpu.Error.to_string result
let pdk result = Result.map_error Pdk.Error.to_string result
let put_f32 bytes offset value = Bytes.set_int32_le bytes offset (Int32.bits_of_float value)
let put_u32 bytes offset value = Bytes.set_int32_le bytes offset (Int32.of_int value)
let add_f32 builder value = Stdlib.Buffer.add_int32_le builder (Int32.bits_of_float value)

let add_vec3 builder (x, y, z) =
  add_f32 builder x;
  add_f32 builder y;
  add_f32 builder z

let add_float4 builder (x, y, z) w =
  add_vec3 builder (x, y, z);
  add_f32 builder w

let color_tuple (color : Linear_color.t) = color.r, color.g, color.b

let vec3_tuple (v : Prismel.Vec3.t) = (v.x, v.y, v.z)

(* Analytic primitives share the material index space with the objects. *)
let prepare_extras ~first_material spheres strands =
  let sphere_bytes = Stdlib.Buffer.create 256
  and box_bytes = Stdlib.Buffer.create 256
  and strand_points = Stdlib.Buffer.create 256
  and strand_radii = Stdlib.Buffer.create 64
  and strand_indices = Stdlib.Buffer.create 64
  and strand_ids = Stdlib.Buffer.create 64 in
  let finite value = Float.is_finite value && Float.abs value <= 3.402823466e38 in
  let* () =
    List.fold_left
      (fun acc (index, (sphere : sphere)) ->
        let* () = acc in
        let x, y, z = vec3_tuple sphere.center in
        if not (finite x && finite y && finite z && finite sphere.radius && sphere.radius > 0.) then
          Error "path tracer sphere needs a finite center and a positive radius"
        else begin
          add_float4 sphere_bytes (x, y, z) sphere.radius;
          Stdlib.Buffer.add_int32_le sphere_bytes (Int32.of_int (first_material + index));
          Stdlib.Buffer.add_bytes sphere_bytes (Bytes.make 12 '\000');
          add_vec3 box_bytes (x -. sphere.radius, y -. sphere.radius, z -. sphere.radius);
          add_vec3 box_bytes (x +. sphere.radius, y +. sphere.radius, z +. sphere.radius);
          Ok ()
        end)
      (Ok ())
      (List.mapi (fun index sphere -> (index, sphere)) spheres)
  in
  let point_count = ref 0 and segments = ref 0 in
  let* () =
    List.fold_left
      (fun acc (index, (strand : strand)) ->
        let* () = acc in
        if Array.length strand.points < 2 then Error "path tracer strand needs at least two points"
        else if not (finite strand.thickness && strand.thickness > 0.) then
          Error "path tracer strand needs a positive finite thickness"
        else if Array.exists (fun p -> let x, y, z = vec3_tuple p in not (finite x && finite y && finite z)) strand.points
        then Error "path tracer strand points must be finite"
        else begin
          let first = !point_count in
          Array.iter (fun p -> add_vec3 strand_points (vec3_tuple p); add_f32 strand_radii (strand.thickness *. 0.5)) strand.points;
          point_count := !point_count + Array.length strand.points;
          for segment = 0 to Array.length strand.points - 2 do
            Stdlib.Buffer.add_int32_le strand_indices (Int32.of_int (first + segment));
            Stdlib.Buffer.add_int32_le strand_ids (Int32.of_int (first_material + List.length spheres + index));
            incr segments
          done;
          Ok ()
        end)
      (Ok ())
      (List.mapi (fun index strand -> (index, strand)) strands)
  in
  Ok
    {
      sphere_bytes = Stdlib.Buffer.to_bytes sphere_bytes;
      box_bytes = Stdlib.Buffer.to_bytes box_bytes;
      sphere_count = List.length spheres;
      strand_points = Stdlib.Buffer.to_bytes strand_points;
      strand_radii = Stdlib.Buffer.to_bytes strand_radii;
      strand_indices = Stdlib.Buffer.to_bytes strand_indices;
      strand_ids = Stdlib.Buffer.to_bytes strand_ids;
      strand_point_count = !point_count;
      strand_segments = !segments;
    }

(* Flattens every object into an unindexed triangle list with per-vertex
   normals and one material index per triangle. Pure: safe on a cook worker. *)
let mesh ?(spheres = []) ?(strands = []) objects =
  let flatten objects =
    let positions = Stdlib.Buffer.create 4096
    and normals = Stdlib.Buffer.create 4096
    and ids = Stdlib.Buffer.create 1024
    and count = ref 0 in
    let* () =
      List.fold_left
        (fun acc (geometry, material_index) ->
          let* () = acc in
          let* triangles = pdk (Pdk.Ops.triangulate geometry) in
          let* triangles =
            pdk
              (Pdk.Ops.normals ~owner:Pdk.Attribute.Vertex ~cusp_angle:(Float.pi /. 4.5) triangles)
          in
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
          Ok ())
        (Ok ()) objects
    in
    if !count = 0 && spheres = [] && strands = [] then Error "path tracer scene has no triangles"
    else
      Ok
        ( Stdlib.Buffer.to_bytes positions,
          Stdlib.Buffer.to_bytes normals,
          Stdlib.Buffer.to_bytes ids,
          !count )
  in
  let* mesh_positions, mesh_normals, mesh_ids, triangles =
    flatten (List.mapi (fun index (geometry, _) -> (geometry, index)) objects)
  in
  let* extras = prepare_extras ~first_material:(List.length objects) spheres strands in
  Ok
    {
      mesh_positions;
      mesh_normals;
      mesh_ids;
      triangles;
      mesh_materials =
        List.map snd objects
        @ List.map (fun (s : sphere) -> s.sphere_material) spheres
        @ List.map (fun (s : strand) -> s.strand_material) strands;
      instances = None;
      extras;
    }

let triangle_count mesh = mesh.triangles

(* Column-major 3x4 transform plus its 3x3 normal matrix (cofactors / det):
   seven packed float3 columns, 84 bytes. *)
let transform_columns (matrix : Prismel.Mat4.t) =
  let values = Array.init 16 (fun index -> Prismel.Mat4.get matrix ~row:(index / 4) ~column:(index mod 4)) in
  let a = values.(0) and b = values.(1) and c = values.(2)
  and d = values.(4) and e = values.(5) and f = values.(6)
  and g = values.(8) and h = values.(9) and i = values.(10) in
  let cofactors =
    [| (e *. i) -. (f *. h); (c *. h) -. (b *. i); (b *. f) -. (c *. e)
     ; (f *. g) -. (d *. i); (a *. i) -. (c *. g); (c *. d) -. (a *. f)
     ; (d *. h) -. (e *. g); (b *. g) -. (a *. h); (a *. e) -. (b *. d) |]
  in
  let determinant = (a *. cofactors.(0)) +. (b *. cofactors.(3)) +. (c *. cofactors.(6)) in
  let finite value = Float.is_finite value && Float.abs value <= 3.402823466e38 in
  if
    (not (Array.for_all finite values))
    || Float.abs values.(12) > 1e-6 || Float.abs values.(13) > 1e-6 || Float.abs values.(14) > 1e-6
    || Float.abs (values.(15) -. 1.) > 1e-6
    || (not (Float.is_finite determinant)) || determinant = 0.
  then Error "path tracer instance transform must be finite, affine, and nonsingular"
  else
    let normal = Array.map (fun value -> value /. determinant) cofactors in
    if not (Array.for_all finite normal) then
      Error "path tracer instance normal transform exceeds float32 range"
    else Ok (Array.sub values 0 12, normal)

let put_transform_record bytes base (transform, normal) =
  for column = 0 to 3 do
    for row = 0 to 2 do
      put_f32 bytes (base + (((column * 3) + row) * 4)) transform.((row * 4) + column)
    done
  done;
  for column = 0 to 2 do
    for row = 0 to 2 do
      put_f32 bytes (base + 48 + (((column * 3) + row) * 4)) normal.((column * 3) + row)
    done
  done

let mesh_instanced ~prototype:(geometry, material) ?(materials = [||]) ?motion transforms =
  let* prototype = mesh [ (geometry, material) ] in
  let count = Array.length transforms in
  if count = 0 then Error "path tracer instancing needs at least one transform"
  else if prototype.triangles > max_int / count then
    Error "path tracer instanced triangle count overflows"
  else if count > max_int / 168 then Error "path tracer transform storage overflows"
  else if Array.length materials <> 0 && Array.length materials <> count then
    Error "path tracer instance materials must match the transform count"
  else if match motion with Some ends -> Array.length ends <> count | None -> false then
    Error "path tracer motion transforms must match the transform count"
  else
    let stride = if motion = None then 84 else 168 in
    let records = Array.make count { B.instance = { transform = [||]; mask = 0; structure_index = 0 }; user_id = 0; table_offset = 0 }
    and shader_bytes = Bytes.create (count * stride)
    and motion_transforms = Array.make (2 * count) [||] in
    let rec pack instance =
      if instance = count then Ok ()
      else
        let* start = transform_columns transforms.(instance) in
        let* finish = match motion with None -> Ok start | Some ends -> transform_columns ends.(instance) in
        records.(instance) <-
          { B.instance = { transform = fst start; mask = 0xFFFF_FFFF; structure_index = 0 }
          ; user_id = (if Array.length materials = 0 then 0 else 1 + instance); table_offset = 0 };
        put_transform_record shader_bytes (instance * stride) start;
        if motion <> None then put_transform_record shader_bytes ((instance * stride) + 84) finish;
        motion_transforms.(2 * instance) <- fst start;
        motion_transforms.((2 * instance) + 1) <- fst finish;
        pack (instance + 1)
    in
    let* () = pack 0 in
    Ok
      {
        prototype with
        triangles = prototype.triangles * count;
        mesh_materials = prototype.mesh_materials @ Array.to_list materials;
        instances =
          Some
            { records; shader_bytes
            ; motion_transforms = (if motion = None then None else Some motion_transforms) };
      }

let material_bytes materials =
  let builder = Stdlib.Buffer.create 256 in
  List.iter
    (fun m ->
      add_float4 builder (color_tuple m.albedo) m.roughness;
      add_float4 builder (color_tuple m.emission) m.metallic;
      add_float4 builder (m.round, 0., 0.) 0.)
    materials;
  Stdlib.Buffer.to_bytes builder

let panel_bytes panels =
  let builder = Stdlib.Buffer.create 256 in
  let normalize (v : Prismel.Vec3.t) =
    let l = sqrt ((v.x *. v.x) +. (v.y *. v.y) +. (v.z *. v.z)) in
    let l = if l = 0. then 1. else l in
    (v.x /. l, v.y /. l, v.z /. l)
  in
  List.iter
    (fun (p : panel) ->
      let r, g, b = color_tuple p.color in
      add_float4 builder (normalize p.direction) 0.;
      add_float4 builder (r *. p.intensity, g *. p.intensity, b *. p.intensity) 0.;
      add_float4 builder (p.width, p.height, p.softness) 0.)
    panels;
  if panels = [] then Stdlib.Buffer.add_bytes builder (Bytes.make 48 '\000');
  Stdlib.Buffer.to_bytes builder

let light_bytes lights =
  let builder = Stdlib.Buffer.create 256 in
  let open Prismel.Vec3 in
  let sub a b = create (a.x -. b.x) (a.y -. b.y) (a.z -. b.z) in
  let cross a b =
    create
      ((a.y *. b.z) -. (a.z *. b.y))
      ((a.z *. b.x) -. (a.x *. b.z))
      ((a.x *. b.y) -. (a.y *. b.x))
  in
  let normalize v =
    let l = sqrt ((v.x *. v.x) +. (v.y *. v.y) +. (v.z *. v.z)) in
    if l = 0. then create 0. 0. 1. else create (v.x /. l) (v.y /. l) (v.z /. l)
  in
  List.iter
    (fun (light : light) ->
      let w, h = light.size in
      let forward = normalize (sub light.target light.at) in
      let world_up = if Float.abs forward.y > 0.999 then create 0. 0. 1. else create 0. 1. 0. in
      let right = normalize (cross forward world_up) in
      let up = cross right forward in
      let u = create (right.x *. w) (right.y *. w) (right.z *. w)
      and v = create (up.x *. h) (up.y *. h) (up.z *. h) in
      let origin =
        create
          (light.at.x -. ((u.x +. v.x) /. 2.))
          (light.at.y -. ((u.y +. v.y) /. 2.))
          (light.at.z -. ((u.z +. v.z) /. 2.))
      in
      let r, g, b = color_tuple light.color in
      add_float4 builder (origin.x, origin.y, origin.z) 0.;
      add_float4 builder (u.x, u.y, u.z) 0.;
      add_float4 builder (v.x, v.y, v.z) 0.;
      add_float4 builder (r *. light.intensity, g *. light.intensity, b *. light.intensity) (w *. h))
    lights;
  if lights = [] then Stdlib.Buffer.add_bytes builder (Bytes.make 64 '\000');
  Stdlib.Buffer.to_bytes builder

(* Resource helpers on the leased OGPU device. Scene geometry lives in shared
   memory (Apple silicon is unified); accumulation, history, and build scratch
   are device-local. *)
let buffer ?(memory = Ogpu.Types.Shared) ?(usage = [ Ogpu.Types.Storage ]) device ~label size =
  gpu
    (B.create_buffer ~memory device
       { label = Some label; size = Int64.of_int (max 4 size); usage })

let shared device ~label bytes =
  let* value = buffer device ~label (Bytes.length bytes) in
  match gpu (B.write_buffer value ~offset:0L bytes) with
  | Ok () -> Ok value
  | Error _ as failure ->
      ignore (B.destroy_buffer value);
      failure

let destroy_gpu gpu =
  ignore (B.destroy_accel gpu.structure);
  Option.iter (fun transforms -> ignore (B.destroy_buffer transforms)) gpu.transforms;
  Option.iter (fun motion -> ignore (B.destroy_buffer motion)) gpu.motion_buffer;
  Option.iter (fun instances -> ignore (B.destroy_buffer instances)) gpu.instance_buffer;
  if gpu.owns_prototype then begin
    Option.iter (fun primitive -> ignore (B.destroy_accel primitive)) gpu.primitive;
    List.iter
      (fun value -> ignore (B.destroy_buffer value))
      [ gpu.positions; gpu.normals; gpu.material_ids; gpu.materials ];
    Option.iter (fun value -> ignore (B.destroy_buffer value)) gpu.sphere_buffer;
    Option.iter (fun value -> ignore (B.destroy_buffer value)) gpu.box_buffer;
    Option.iter
      (fun (points, radii, indices, ids) ->
        List.iter (fun value -> ignore (B.destroy_buffer value)) [ points; radii; indices; ids ])
      gpu.strands
  end

(* Encodes the instance structure build over [build.gpu.primitive]. *)
let encode_instances device (build : mesh_build) command =
  match (build.gpu.instance_buffer, build.gpu.primitive) with
  | Some instances, Some primitive ->
      let kind = if build.gpu.motion_buffer = None then B.User_id_instances else B.Motion_instances in
      let* structure =
        gpu
          (B.create_accel device
             (B.Tlas_of
                { instances; offset = 0L; instance_count = build.instance_count; kind
                ; structures = [ primitive ]; allow_refit = false
                ; motion_transforms =
                    Option.map (fun buffer -> (buffer, 0L, 2 * build.instance_count)) build.gpu.motion_buffer }))
      in
      let needed = (B.accel_sizes structure).build_scratch_size in
      let* scratch =
        if needed <= B.buffer_size build.scratch then Ok build.scratch
        else
          let* extra = buffer ~memory:Ogpu.Types.Device_local device ~label:"pathtracer-instance-scratch" (Int64.to_int needed) in
          build.extra_scratch <- Some extra;
          Ok extra
      in
      let encoded =
        let* encoder = gpu (B.accel_encoder command) in
        let* () = gpu (B.build_accel encoder structure ~scratch ()) in
        gpu (B.end_accel encoder)
      in
      (match encoded with
       | Ok () -> build.gpu.structure <- structure; Ok ()
       | Error _ as failure -> ignore (B.destroy_accel structure); failure)
  | _ -> Ok ()

let submit_instances device queue (build : mesh_build) =
  let* command = gpu (B.begin_commands queue) in
  match (let* () = encode_instances device build command in gpu (B.commit command)) with
  | Ok receipt -> build.stage <- Compacting receipt; Ok ()
  | Error _ as failure -> ignore (B.abandon command); failure

let mesh_shape mesh =
  { instanced = mesh.instances <> None
  ; motion = (match mesh.instances with Some { motion_transforms = Some _; _ } -> true | _ -> false)
  ; spheres = mesh.extras.sphere_count > 0
  ; curves = mesh.extras.strand_segments > 0 }

(* Stage one of a replacement build: upload the geometry, build the primitive
   structure, and write its compacted size, all without waiting. A reused
   prototype skips straight to the instance build. *)
let upload_mesh_async ?reuse device queue mesh =
  let buffers = ref []
  and structures = ref []
  and scratch = ref None
  and commands = ref None in
  let owned bytes ~label =
    let* value = shared device ~label bytes in
    buffers := value :: !buffers;
    Ok value
  in
  let accel descriptor =
    let* value = gpu (B.create_accel device descriptor) in
    structures := value :: !structures;
    Ok value
  in
  let material_data = material_bytes mesh.mesh_materials in
  let shape = mesh_shape mesh in
  let extras = mesh.extras in
  let capabilities = B.capabilities device in
  let* () =
    if shape.spheres && not (Ogpu.Caps.has capabilities Function_tables) then
      Error "path tracer spheres need intersection function tables on this device"
    else if shape.curves && not (Ogpu.Caps.has capabilities Ray_tracing_curves) then
      Error "path tracer strands need curve primitives, which this device does not intersect"
    else Ok ()
  in
  let reused =
    match (reuse, mesh.instances) with
    | Some gpu, Some _ -> (
        match (gpu.prototype_key, gpu.primitive) with
        | Some (positions, normals, ids, materials, extra_key), Some primitive
          when Bytes.equal positions mesh.mesh_positions
               && Bytes.equal normals mesh.mesh_normals
               && Bytes.equal ids mesh.mesh_ids
               && Bytes.equal materials material_data
               && Bytes.equal extra_key (Bytes.cat extras.sphere_bytes extras.strand_points) ->
            Some (gpu, primitive)
        | _ -> None)
    | _ -> None
  in
  let result =
    let* positions, normals, material_ids, materials, spheres, boxes, strands, primitive, build_primitive =
      match reused with
      | Some (gpu, primitive) ->
          Ok (gpu.positions, gpu.normals, gpu.material_ids, gpu.materials, gpu.sphere_buffer, gpu.box_buffer, gpu.strands, primitive, false)
      | None ->
          let* positions = owned mesh.mesh_positions ~label:"pathtracer-positions" in
          let* normals = owned mesh.mesh_normals ~label:"pathtracer-normals" in
          let* material_ids = owned mesh.mesh_ids ~label:"pathtracer-material-ids" in
          let* materials = owned material_data ~label:"pathtracer-materials" in
          let* spheres, boxes =
            if not shape.spheres then Ok (None, None)
            else
              let* spheres = owned extras.sphere_bytes ~label:"pathtracer-spheres" in
              let* boxes = owned extras.box_bytes ~label:"pathtracer-sphere-boxes" in
              Ok (Some spheres, Some boxes)
          in
          let* strands =
            if not shape.curves then Ok None
            else
              let* points = owned extras.strand_points ~label:"pathtracer-strand-points" in
              let* radii = owned extras.strand_radii ~label:"pathtracer-strand-radii" in
              let* indices = owned extras.strand_indices ~label:"pathtracer-strand-indices" in
              let* ids = owned extras.strand_ids ~label:"pathtracer-strand-ids" in
              Ok (Some (points, radii, indices, ids))
          in
          let vertex_count = Bytes.length mesh.mesh_positions / 12 in
          let geometries =
            (if vertex_count = 0 then []
             else
               [ B.Triangles
                   { vertices = positions; offset = 0L; length = Int64.of_int (vertex_count * 12)
                   ; vertex_stride = 12; vertex_count } ])
            @ (match boxes with
               | None -> []
               | Some boxes ->
                   [ B.Bounding_boxes
                       { boxes = [ { buffer = boxes; offset = 0L } ]; stride = 24; count = extras.sphere_count
                       ; options = B.default_geometry_options } ])
            @ (match strands with
               | None -> []
               | Some (points, radii, indices, _) ->
                   [ B.Curves
                       { control_points = [ { buffer = points; offset = 0L } ]; control_stride = 12
                       ; control_point_count = extras.strand_point_count
                       ; radii = [ { buffer = radii; offset = 0L } ]; radius_stride = 4; indices; index_offset = 0L
                       ; segment_count = extras.strand_segments; control_points_per_segment = 2
                       ; curve_type = Round_curve; basis = Linear_basis; caps = Sphere_caps } ])
          in
          let* primitive = accel (B.Blas { geometries; allow_refit = false }) in
          Ok (positions, normals, material_ids, materials, spheres, boxes, strands, primitive, true)
    in
    let* instance_buffer, transforms, motion_buffer =
      match mesh.instances with
      | None -> Ok (None, None, None)
      | Some instances ->
          let* transforms = owned instances.shader_bytes ~label:"pathtracer-transforms" in
          let* motion_buffer =
            match instances.motion_transforms with
            | None -> Ok None
            | Some keyframes ->
                let* packed = gpu (B.pack_transforms keyframes) in
                let* buffer = owned packed ~label:"pathtracer-motion" in
                Ok (Some buffer)
          in
          let* packed =
            match instances.motion_transforms with
            | None -> gpu (B.pack_instance_records device instances.records)
            | Some _ ->
                gpu
                  (B.pack_motion_instances device
                     (Array.mapi
                        (fun index record ->
                          { B.record; transforms_start = 2 * index; transforms_count = 2; start_time = 0.
                          ; end_time = 1.; start_border = Clamp; end_border = Clamp })
                        instances.records))
          in
          let* instance_buffer = owned packed ~label:"pathtracer-instances" in
          Ok (Some instance_buffer, Some transforms, motion_buffer)
    in
    let* work =
      buffer ~memory:Ogpu.Types.Device_local device ~label:"pathtracer-scratch"
        (max 1024 (Int64.to_int (Int64.mul 2L (B.accel_sizes primitive).build_scratch_size)))
    in
    scratch := Some work;
    let gpu_mesh =
      { positions; normals; material_ids; materials; sphere_buffer = spheres; box_buffer = boxes; strands
      ; structure = primitive; primitive = None; instance_buffer; transforms; motion_buffer
      ; prototype_key =
          (match mesh.instances with
           | None -> None
           | Some _ ->
               Some (mesh.mesh_positions, mesh.mesh_normals, mesh.mesh_ids, material_data,
                     Bytes.cat extras.sphere_bytes extras.strand_points))
      ; owns_prototype = reused = None; shape }
    in
    let instance_count = match mesh.instances with None -> 0 | Some i -> Array.length i.records in
    if build_primitive then begin
      let* size_buffer = buffer device ~label:"pathtracer-compacted-size" ~usage:[ Ogpu.Types.Storage; Copy_src ] 8 in
      buffers := size_buffer :: !buffers;
      let* command = gpu (B.begin_commands queue) in
      commands := Some command;
      let* receipt =
        let* encoder = gpu (B.accel_encoder command) in
        let* () = gpu (B.build_accel encoder primitive ~scratch:work ()) in
        let* () = gpu (B.write_compacted_size encoder primitive ~dst:size_buffer ()) in
        let* () = gpu (B.end_accel encoder) in
        gpu (B.commit command)
      in
      Ok { gpu = gpu_mesh; scratch = work; extra_scratch = None; size_buffer = Some size_buffer
         ; uncompacted = None; stage = Building receipt; instance_count }
    end
    else
      (* A reused compacted prototype only needs its instance structure. *)
      let build = { gpu = { gpu_mesh with primitive = Some primitive }; scratch = work; extra_scratch = None
                  ; size_buffer = None; uncompacted = None; stage = Ready; instance_count } in
      let* () = submit_instances device queue build in
      Ok build
  in
  match result with
  | Ok _ as ready -> ready
  | Error _ as failure ->
      Option.iter (fun command -> ignore (B.abandon command)) !commands;
      Option.iter (fun work -> ignore (B.destroy_buffer work)) !scratch;
      List.iter (fun built -> ignore (B.destroy_accel built)) !structures;
      List.iter (fun value -> ignore (B.destroy_buffer value)) !buffers;
      failure

(* Polling a later epoch retires earlier ones, so a wait on an already
   completed receipt is a no-op rather than an invalid-epoch error. *)
let wait queue (receipt : B.receipt) =
  if Ogpu.Command_buffer.completed_epoch queue >= receipt.epoch then Ok ()
  else gpu (B.complete_through queue receipt.epoch)

(* Stage two: build the instance structure over the compacted primitive. *)
let advance_build device queue (build : mesh_build) =
  match build.stage with
  | Ready -> Ok ()
  | Building _ -> (
      let uncompacted = build.gpu.structure in
      let* size_bytes =
        match build.size_buffer with
        | Some size_buffer -> gpu (B.read_buffer size_buffer ~offset:0L ~length:8)
        | None -> Error "path tracer build lost its compacted size"
      in
      let size = Bytes.get_int64_le size_bytes 0 in
      let* compacted = gpu (B.create_accel device (B.Sized { size; template = uncompacted })) in
      build.uncompacted <- Some uncompacted;
      build.gpu.structure <- compacted;
      if build.instance_count > 0 then build.gpu.primitive <- Some compacted;
      let* command = gpu (B.begin_commands queue) in
      let encoded =
        let* encoder = gpu (B.accel_encoder command) in
        let* () = gpu (B.compact_accel encoder ~src:uncompacted ~dst:compacted) in
        let* () = gpu (B.end_accel encoder) in
        let* () = encode_instances device build command in
        gpu (B.commit command)
      in
      match encoded with
      | Ok receipt ->
          build.stage <- Compacting receipt;
          Ok ()
      | Error _ as failure ->
          ignore (B.abandon command);
          failure)
  | Compacting _ ->
      Option.iter (fun structure -> ignore (B.destroy_accel structure)) build.uncompacted;
      build.uncompacted <- None;
      Option.iter (fun size_buffer -> ignore (B.destroy_buffer size_buffer)) build.size_buffer;
      build.size_buffer <- None;
      build.stage <- Ready;
      Ok ()

let finish_build device queue (build : mesh_build) =
  let rec finish () =
    match build.stage with
    | Ready -> Ok ()
    | Building receipt | Compacting receipt ->
        let* () = wait queue receipt in
        let* () = advance_build device queue build in
        finish ()
  in
  let finished = finish () in
  ignore (B.destroy_buffer build.scratch);
  Option.iter (fun extra -> ignore (B.destroy_buffer extra)) build.extra_scratch;
  match finished with
  | Ok () -> Ok build.gpu
  | Error _ as failure ->
      Option.iter (fun structure -> ignore (B.destroy_accel structure)) build.uncompacted;
      Option.iter (fun size_buffer -> ignore (B.destroy_buffer size_buffer)) build.size_buffer;
      destroy_gpu build.gpu;
      failure

let discard_build queue (build : mesh_build) =
  (match build.stage with
   | Ready -> ()
   | Building receipt | Compacting receipt -> ignore (wait queue receipt));
  ignore (B.destroy_buffer build.scratch);
  Option.iter (fun extra -> ignore (B.destroy_buffer extra)) build.extra_scratch;
  Option.iter (fun structure -> ignore (B.destroy_accel structure)) build.uncompacted;
  Option.iter (fun size_buffer -> ignore (B.destroy_buffer size_buffer)) build.size_buffer;
  destroy_gpu build.gpu

let upload_mesh device queue mesh =
  let* build = upload_mesh_async device queue mesh in
  finish_build device queue build

let storage_buffer binding = { Ogpu.Shader.group = 0; binding; kind = Storage_buffer; visibility = [ Compute ] }

let trace_interface shape =
  [ { Ogpu.Shader.group = 0; binding = 0; kind = Acceleration_structure; visibility = [ Compute ] }
  ; { Ogpu.Shader.group = 0; binding = 1; kind = Uniform_buffer; visibility = [ Compute ] } ]
  @ List.map storage_buffer
      ([ 2; 3 ] @ (if shape.instanced then [ 5; 6; 7; 9; 10 ] else [ 4; 5; 6; 7; 9 ]) @ [ 11; 12; 13; 14 ]
       @ (if shape.spheres then [ 15 ] else []) @ (if shape.curves then [ 17; 18; 19 ] else []))
  @ (if shape.spheres then [ { Ogpu.Shader.group = 0; binding = 16; kind = Intersection_table; visibility = [ Compute ] } ] else [])
  @ [ { Ogpu.Shader.group = 0; binding = 0; kind = Storage_texture; visibility = [ Compute ] } ]

let resolve_interface =
  [ { Ogpu.Shader.group = 0; binding = 0; kind = Ogpu.Shader.Uniform_buffer; visibility = [ Compute ] }
  ; storage_buffer 1; storage_buffer 2
  ; { Ogpu.Shader.group = 0; binding = 0; kind = Storage_texture; visibility = [ Compute ] } ]

(* The sphere intersection function whose tags match the pipeline's intersector. *)
let sphere_function shape =
  "sphere_hit_" ^ (if shape.instanced then "i" else "f") ^ (if shape.motion then "m" else "")
  ^ if shape.curves then "c" else ""

(* Pipelines are specialized per mesh shape and compiled on first use. *)
let pipeline_for library pipelines shape =
  match Hashtbl.find_opt pipelines shape with
  | Some entry -> Ok entry
  | None ->
      let constants =
        [ ("INSTANCED", Ogpu.Shader.Bool shape.instanced); ("MOTION", Ogpu.Shader.Bool shape.motion)
        ; ("SPHERES", Ogpu.Shader.Bool shape.spheres); ("CURVES", Ogpu.Shader.Bool shape.curves) ]
      in
      let* pipeline =
        gpu
          (B.create_compute_pipeline_from library ~entry:"pathtrace" ~constants
             ~interface:(trace_interface shape)
             ~linked:(if shape.spheres then [ sphere_function shape ] else []) ())
      in
      let* table =
        if not shape.spheres then Ok None
        else
          let created =
            let* table = gpu (B.create_intersection_table pipeline ~capacity:1) in
            match gpu (B.table_set_function table ~index:0 (sphere_function shape)) with
            | Ok () -> Ok (Some table)
            | Error _ as failure -> ignore (B.destroy_table table); failure
          in
          match created with
          | Ok _ as ok -> ok
          | Error _ as failure -> ignore (B.destroy_pipeline pipeline); failure
      in
      Hashtbl.add pipelines shape (pipeline, table);
      Ok (pipeline, table)

let create ?(spp = 1) ?(bounces = 6) ?(exposure = 1.) ?(round_samples = 4) ~width ~height (scene : scene) =
  if width <= 0 || height <= 0 then Error "path tracer size must be positive"
  else if spp <= 0 || bounces <= 0 then Error "path tracer spp and bounces must be positive"
  else
    let* lease =
      Result.map_error
        (Format.asprintf "%a" Prismel_next_execution.pp_error)
        (Prismel_next_execution.acquire_gpu ())
    in
    let device = Prismel_next_execution.gpu_device lease
    and queue = Prismel_next_execution.gpu_queue lease in
    let release () = Prismel_next_execution.release_gpu lease in
    let created =
      let* () =
        gpu (Ogpu.Caps.require ~operation:"Prismel_pathtracer.create" (B.capabilities device) Ray_tracing)
      in
      let* mesh = mesh ~spheres:scene.spheres ~strands:scene.strands scene.objects in
      let* gpu_mesh = upload_mesh device queue mesh in
      let* panels = shared device ~label:"pathtracer-panels" (panel_bytes scene.environment.panels) in
      let* lights = shared device ~label:"pathtracer-lights" (light_bytes scene.lights) in
      let* shader =
        gpu
          (Ogpu.Shader.of_source
             {
               backend = "metal";
               label = Some "prismel_pathtracer";
               bytes = Bytes.of_string source;
               entry_points = [ { name = "pathtrace"; stage = Compute }; { name = "resolve_preview"; stage = Compute } ];
               bindings = [];
             })
      in
      let* library = gpu (B.create_library device shader) in
      let pipelines = Hashtbl.create 4 in
      let* _ = pipeline_for library pipelines gpu_mesh.shape in
      let* resolve_pipeline =
        gpu
          (B.create_compute_pipeline_from library ~entry:"resolve_preview"
             ~interface:resolve_interface ())
      in
      let pixel_count = width * height in
      let history label =
        buffer ~memory:Ogpu.Types.Device_local device ~label (pixel_count * 16)
      in
      let* accum = history "pathtracer-accum" in
      let* color0 = history "pathtracer-history-color-0" in
      let* color1 = history "pathtracer-history-color-1" in
      let* geometry0 = history "pathtracer-history-geometry-0" in
      let* geometry1 = history "pathtracer-history-geometry-1" in
      let pixels = Bytes.make (pixel_count * 4) '\000' in
      let* resource =
        Result.map_error
          (Format.asprintf "%a" Prismel_next_resources.pp_error)
          (Prismel_next_resources.Image.create ~width ~height ~rgba:(Bytes.copy pixels))
      in
      let film index =
        gpu
          (B.create_texture device
             {
               label = Some (Printf.sprintf "pathtracer-film-%d" index);
               width;
               height;
               depth = 1;
               mip_levels = 1;
               sample_count = 1;
               usage = [ Texture_binding; Storage_binding; Texture_copy_src ];
             })
      in
      let* output0 = film 0 in
      let* output1 =
        match film 1 with
        | Ok output1 -> Ok output1
        | Error _ as failure ->
            ignore (B.destroy_texture output0);
            failure
      in
      Ok
        {
          lease;
          device;
          queue;
          library;
          pipelines;
          resolve_pipeline;
          gpu = gpu_mesh;
          building = None;
          queued_mesh = None;
          panels;
          lights;
          light_count = List.length scene.lights;
          accum;
          outputs = [| output0; output1 |];
          shared_film = Prismel_next_execution.gpu_shared lease;
          next_output_slot = 0;
          history_color = [| color0; color1 |];
          history_geometry = [| geometry0; geometry1 |];
          history_slot = 0;
          history_camera = None;
          history_epoch = 0;
          pending = None;
          completed = 0;
          resource;
          image = Prismel.Image.Private.of_resource resource;
          width;
          height;
          spp;
          bounces;
          exposure;
          round_samples;
          profile = Sys.getenv_opt "PRISMEL_PATHTRACER_PROFILE" = Some "1";
          panel_count = List.length scene.environment.panels;
          sky = scene.environment.sky;
          ground = scene.environment.ground;
          frame = 0;
          camera = None;
          moving = false;
          pixels;
        }
    in
    (match created with
    | Ok _ -> ()
    | Error _ ->
        (* ponytail: partial creation failures release the lease and let the
           device report leaked children; creation is all-or-nothing in tests. *)
        release ());
    created

let camera_fov camera =
  match Prismel.Camera.projection camera with
  | Perspective { fov_y; lens_offset; _ }
    when lens_offset = Prismel.Vec2.zero
         && (not (Prismel.Camera.v_flip camera))
         && Prismel.Camera.forced_aspect camera = None ->
      Ok fov_y
  | _ -> Error "path tracer requires an unshifted perspective camera"

let uniform_bytes t (camera : camera) fov =
  let open Prismel.Vec3 in
  let sub a b = create (a.x -. b.x) (a.y -. b.y) (a.z -. b.z) in
  let cross a b =
    create
      ((a.y *. b.z) -. (a.z *. b.y))
      ((a.z *. b.x) -. (a.x *. b.z))
      ((a.x *. b.y) -. (a.y *. b.x))
  in
  let normalize v =
    let l = sqrt ((v.x *. v.x) +. (v.y *. v.y) +. (v.z *. v.z)) in
    if l = 0. then create 0. 0. 1. else create (v.x /. l) (v.y /. l) (v.z /. l)
  in
  let axes (camera : camera) =
    let forward = normalize (sub (Prismel.Camera.target camera) (Prismel.Camera.position camera)) in
    let camera_up = Prismel.Camera.up camera in
    let world_up =
      if Float.abs (dot forward camera_up) > 0.999 then
        if Float.abs forward.y > 0.999 then create 0. 0. 1. else create 0. 1. 0.
      else camera_up
    in
    let right = normalize (cross forward world_up) in
    (forward, right, cross right forward)
  in
  let forward, right, up = axes camera in
  let bytes = Bytes.make 208 '\000' in
  let put_vec4 offset (v : Prismel.Vec3.t) w =
    put_f32 bytes offset v.x;
    put_f32 bytes (offset + 4) v.y;
    put_f32 bytes (offset + 8) v.z;
    put_f32 bytes (offset + 12) w
  in
  let put_rgb offset color =
    let r, g, b = color_tuple color in
    put_vec4 offset (create r g b) 0. in
  put_vec4 0 (Prismel.Camera.position camera) 0.;
  put_vec4 16 forward (tan (fov /. 2.));
  put_vec4 32 right (float_of_int t.width /. float_of_int t.height);
  put_vec4 48 up 0.;
  put_rgb 64 t.sky;
  put_rgb 80 t.ground;
  put_u32 bytes 96 t.width;
  put_u32 bytes 100 t.height;
  put_u32 bytes 104 t.frame;
  put_u32 bytes 108 t.spp;
  put_u32 bytes 112 t.panel_count;
  put_u32 bytes 116 t.bounces;
  put_f32 bytes 120 t.exposure;
  put_u32 bytes 124 t.round_samples;
  put_u32 bytes 128 t.light_count;
  put_u32 bytes 132 (if t.moving then 1 else 0);
  let* () =
    match t.history_camera with
    | None -> Ok ()
    | Some previous ->
        let* previous_fov = camera_fov previous in
        let forward, right, up = axes previous in
        put_u32 bytes 136 1;
        put_vec4 144 (Prismel.Camera.position previous) 0.;
        put_vec4 160 forward (tan (previous_fov /. 2.));
        put_vec4 176 right (float_of_int t.width /. float_of_int t.height);
        put_vec4 192 up 0.;
        Ok ()
  in
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
  (match (t.gpu.primitive, gpu.primitive) with
  | Some old, Some next when old == next ->
      t.gpu.owns_prototype <- false;
      gpu.owns_prototype <- true
  | _ -> ());
  destroy_gpu t.gpu;
  t.gpu <- gpu;
  reset t

(* The pipeline and intersection table for the installed mesh, with the table
   pointed at the mesh's sphere records. *)
let current_pipeline t =
  let* pipeline, table = pipeline_for t.library t.pipelines t.gpu.shape in
  let* () =
    match (table, t.gpu.sphere_buffer) with
    | Some table, Some spheres -> gpu (B.table_set_buffer table ~index:0 spheres)
    | _ -> Ok ()
  in
  Ok (pipeline, table)

let samples t = t.completed * t.spp
let size t = (t.width, t.height)
let image t = t.image

let pixels t =
  match Prismel_next_resources.Image.Private.gpu_snapshot t.resource with
  | None -> t.pixels
  | Some _ -> (
      match Prismel_next_resources.Image.pixels t.resource with
      | Ok pixels ->
          t.pixels <- pixels;
          pixels
      | Error error -> failwith (Format.asprintf "%a" Prismel_next_resources.pp_error error))

(* Publishes a completed frame's pixels unless a reset made them obsolete. *)
let publish t (pending : pending) =
  t.pending <- None;
  (if t.profile then
     match B.gpu_duration t.queue pending.receipt with
     | Some seconds -> Printf.eprintf "pathtracer gpu_ms %.4f\n%!" (seconds *. 1000.)
     | None -> ());
  if pending.history_epoch = t.history_epoch then t.history_camera <- Some pending.camera;
  if pending.stale then Ok ()
  else
    let film = t.outputs.(pending.slot) in
    let* () =
      if t.shared_film then
        Result.map_error
          (Format.asprintf "%a" Prismel_next_resources.pp_error)
          (Prismel_next_resources.Image.Private.replace_gpu t.resource film)
      else
        let* rgba = gpu (B.read_texture film ~bytes_per_row:(t.width * 4)) in
        t.pixels <- rgba;
        Result.map_error
          (Format.asprintf "%a" Prismel_next_resources.pp_error)
          (Prismel_next_resources.Image.replace t.resource ~width:t.width ~height:t.height ~rgba)
    in
    if not pending.preview then t.completed <- t.completed + 1;
    Ok ()

let status t receipt = gpu (Ogpu.Command_buffer.status t.queue receipt)

let poll_build t =
  match t.building with
  | None -> Ok ()
  | Some build -> (
      let step =
        match build.stage with
        | Ready -> Ok true
        | Building receipt | Compacting receipt -> (
            match status t receipt with
            | Ok Pending -> Ok false
            | Ok Completed -> Result.map (fun () -> build.stage = Ready) (advance_build t.device t.queue build)
            | Error _ as failure -> failure)
      in
      match step with
      | Ok false -> Ok ()
      | Error _ as failure ->
          t.building <- None;
          discard_build t.queue build;
          failure
      | Ok true -> (
          t.building <- None;
          let built = finish_build t.device t.queue build in
          match t.queued_mesh with
          | Some latest ->
              t.queued_mesh <- None;
              (match built with Ok gpu -> destroy_gpu gpu | Error _ -> ());
              let* next = upload_mesh_async ~reuse:t.gpu t.device t.queue latest in
              t.building <- Some next;
              Ok ()
          | None ->
              let* gpu = built in
              install_gpu t gpu;
              Ok ()))

let flush t =
  let* () =
    match t.pending with
    | None -> Ok ()
    | Some pending -> (
        match wait t.queue pending.receipt with
        | Ok () -> publish t pending
        | Error _ as failure ->
            t.pending <- None;
            failure)
  in
  let rec finish_updates () =
    match t.building with
    | None -> Ok ()
    | Some build -> (
        let waited =
          match build.stage with
          | Ready -> Ok ()
          | Building receipt | Compacting receipt -> wait t.queue receipt
        in
        match waited with
        | Ok () ->
            let* () = poll_build t in
            finish_updates ()
        | Error _ as failure ->
            t.building <- None;
            discard_build t.queue build;
            failure)
  in
  finish_updates ()

(* Publishes the in-flight frame only if the GPU has finished it; never
   blocks the caller. Returns whether the tracer is free to submit. *)
let poll t =
  match t.pending with
  | None -> Ok true
  | Some pending -> (
      match status t pending.receipt with
      | Ok Completed ->
          let* () = publish t pending in
          Ok true
      | Ok Pending -> Ok false
      | Error message ->
          t.pending <- None;
          Error ("path tracer frame failed: " ^ message))

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
  if not free then Ok ()
  else
    let* () = poll_build t in
    let* uniforms = uniform_bytes t camera fov in
    let slot = t.next_output_slot in
    let previous_history = t.history_slot in
    let next_history = previous_history lxor 1 in
    let threads = (t.width, t.height, 1) in
    let* commands = gpu (B.begin_commands t.queue) in
    let encoded =
      let* encoder = gpu (B.compute_encoder commands) in
      let set index value = gpu (B.set_buffer encoder ~index value) in
      let* pipeline, table = current_pipeline t in
      let* () = gpu (B.set_pipeline encoder pipeline) in
      let* () = gpu (B.set_accel encoder ~index:0 t.gpu.structure) in
      let* () = gpu (B.set_bytes encoder ~index:1 uniforms) in
      let* () = set 2 t.gpu.positions in
      let* () = set 3 t.gpu.normals in
      let* () = if t.gpu.shape.instanced then Ok () else set 4 t.gpu.material_ids in
      let* () = set 5 t.gpu.materials in
      let* () = set 6 t.panels in
      let* () = set 7 t.accum in
      let* () = gpu (B.set_texture encoder ~index:0 t.outputs.(slot)) in
      let* () = set 9 t.lights in
      let* () = match t.gpu.transforms with None -> Ok () | Some transforms -> set 10 transforms in
      let* () = match t.gpu.sphere_buffer with None -> Ok () | Some spheres -> set 15 spheres in
      let* () = match table with None -> Ok () | Some table -> gpu (B.set_table encoder ~index:16 table) in
      let* () =
        match t.gpu.strands with
        | None -> Ok ()
        | Some (points, _, indices, ids) ->
            let* () = set 17 points in
            let* () = set 18 indices in
            set 19 ids
      in
      let* () = set 11 t.history_color.(previous_history) in
      let* () = set 12 t.history_geometry.(previous_history) in
      let* () = set 13 t.history_color.(next_history) in
      let* () = set 14 t.history_geometry.(next_history) in
      let* () = gpu (B.dispatch_threads encoder ~threads ~threadgroup:(16, 16, 1)) in
      let* () = gpu (B.end_compute encoder) in
      let* () =
        if not t.moving then Ok ()
        else
          let* resolve = gpu (B.compute_encoder commands) in
          let set index value = gpu (B.set_buffer resolve ~index value) in
          let* () = gpu (B.set_pipeline resolve t.resolve_pipeline) in
          let* () = gpu (B.set_bytes resolve ~index:0 uniforms) in
          let* () = set 1 t.history_color.(next_history) in
          let* () = set 2 t.history_geometry.(next_history) in
          let* () = gpu (B.set_texture resolve ~index:0 t.outputs.(slot)) in
          let* () = gpu (B.dispatch_threads resolve ~threads ~threadgroup:(16, 16, 1)) in
          gpu (B.end_compute resolve)
      in
      gpu (B.commit commands)
    in
    match encoded with
    | Error _ as failure ->
        ignore (B.abandon commands);
        failure
    | Ok receipt ->
        t.next_output_slot <- slot lxor 1;
        t.history_slot <- next_history;
        t.pending <-
          Some
            {
              receipt;
              slot;
              stale = false;
              preview = t.moving;
              camera;
              history_epoch = t.history_epoch;
            };
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
  let* gpu = finish_build t.device t.queue build in
  install_gpu t gpu;
  Ok ()

let queue_mesh t mesh =
  match t.building with
  | Some _ ->
      t.queued_mesh <- Some mesh;
      Ok ()
  | None ->
      let* build = upload_mesh_async ~reuse:t.gpu t.device t.queue mesh in
      t.building <- Some build;
      Ok ()

let destroy t =
  let release f = ignore (f ()) in
  Option.iter (fun pending -> pending.stale <- true) t.pending;
  release (fun () -> flush t);
  Prismel.Image.destroy t.image;
  Hashtbl.iter
    (fun _ (pipeline, table) ->
      Option.iter (fun table -> release (fun () -> B.destroy_table table)) table;
      release (fun () -> B.destroy_pipeline pipeline))
    t.pipelines;
  release (fun () -> B.destroy_pipeline t.resolve_pipeline);
  release (fun () -> B.destroy_library t.library);
  destroy_gpu t.gpu;
  List.iter
    (fun value -> release (fun () -> B.destroy_buffer value))
    [
      t.panels;
      t.lights;
      t.accum;
      t.history_color.(0);
      t.history_color.(1);
      t.history_geometry.(0);
      t.history_geometry.(1);
    ];
  Array.iter (fun film -> release (fun () -> B.destroy_texture film)) t.outputs;
  Prismel_next_execution.release_gpu t.lease
