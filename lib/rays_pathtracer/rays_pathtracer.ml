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
  direction : Rays.Vec3.t;
  width : float;
  height : float;
  softness : float;
  color : Linear_color.t;
  intensity : float;
}

let panel ?(softness = 0.05) ~intensity ~width ~height direction =
  { direction; width; height; softness; color = Linear_color.rgb 1. 1. 1.; intensity }

type environment = { sky : Linear_color.t; ground : Linear_color.t; panels : panel list }
type camera = Rays.Camera.t

type light = {
  at : Rays.Vec3.t;
  target : Rays.Vec3.t;
  size : float * float;
  color : Linear_color.t;
  intensity : float;
}

let rect_light ~intensity ~size ~target at =
  { at; target; size; color = Linear_color.rgb 1. 1. 1.; intensity }

(* Inverse of the raster World conversion (a rect of radiance L and area A is
   a Light.t of color L A / pi), so the irradiance pi I / d^2 matches. *)
let light_of (light : Rays.Light.t) =
  let c = light.diffuse in
  let color = Linear_color.rgb (float c.r /. 255.) (float c.g /. 255.) (float c.b /. 255.) in
  let rect ~at ~target ?(distance2 = 1.) (w, h) =
    { at; target; size = (w, h); color; intensity = Float.pi *. light.intensity *. distance2 /. (w *. h) } in
  let open Rays.Vec3 in
  match light.kind with
  | Area { position; direction; width; height; _ } -> rect ~at:position ~target:(add position direction) (width, height)
  | Point { position; _ } -> rect ~at:position ~target:(sub position unit_y) (0.1, 0.1)
  | Spot { position; direction; _ } -> rect ~at:position ~target:(add position direction) (0.1, 0.1)
  | Directional { direction } ->
      rect ~at:(scale (normalize direction) (-100.)) ~target:zero ~distance2:1e4 (20., 20.)

type sphere = { center : Rays.Vec3.t; radius : float; sphere_material : material }

type strand = { points : Rays.Vec3.t array; thickness : float; strand_material : material }

type scene = {
  objects : (Rdk.Geometry.t * material) list;
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
  last : bool;  (* the last band of its frame: publishes the film *)
}

(* Instances carry a user id selecting their material; with [motion] every
   instance has two transform keyframes (start and end of the shutter). *)
type instances = {
  records : B.instance_record array;
  shader_bytes : bytes;
  motion_transforms : float array array option;
  matrices : Rays.Mat4.t array;
}

(* A scene is a TLAS over several BLASes, one per part and one geometry kind
   each (Metal cannot mix kinds in one BLAS). A placement is one TLAS
   instance: its world matrix, its part, and its material (-1: the per-triangle
   ids). The shader table holds, per instance, the part's first triangle in
   the shared vertex buffer and that material. A [scene_mesh] layout also
   keeps, for [move], each object's placement range ([objects.(o)] to
   [objects.(o + 1)]; empty for [mesh]) and each placement's matrix relative
   to its object. *)
type part = Triangle_part of int * int (* first vertex, vertex count *) | Sphere_part | Strand_part

type layout = {
  parts : part array;
  placements : (Rays.Mat4.t * int * int) array;
  table : bytes;
  objects : int array;
  placed : Rays.Mat4.t array; (* each object's world matrix *)
  locals : Rays.Mat4.t array;
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
  scene : layout option;
}

(* The shape of the pipeline a mesh needs. *)
type shape = { instanced : bool; motion : bool; spheres : bool; curves : bool; scene : bool }

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
  scene_blas : B.accel list;
  scene_table : B.buffer option;
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

(* A queued full rebuild, or a transform-only [move] over the installed BLASes. *)
type queued = Full of mesh | Move of mesh

type t = {
  lease : Rays_execution.gpu;
  device : B.device;
  queue : B.queue;
  library : B.library;
  pipelines : (shape, B.pipeline * B.function_table option) Hashtbl.t;
  resolve_pipeline : B.pipeline;
  mutable gpu : gpu_mesh;
  mutable building : mesh_build option;
  mutable queued_mesh : queued option;
  mutable latest : mesh; (* the newest mesh given, for [move] *)
  panels : B.buffer;
  mutable lights : B.buffer;
  mutable light_count : int;
  mutable scene_lights : light list;
  mutable world : Rays.World.baked option;
  mutable world_buffer : B.buffer;
  bsdf_only : bool;
  mutable accum : B.buffer;
  mutable outputs : B.texture array;
  shared_film : bool;
  mutable next_output_slot : int;
  mutable history_color : B.buffer array;
  mutable history_geometry : B.buffer array;
  mutable history_slot : int;
  mutable history_camera : camera option;
  mutable history_epoch : int;
  mutable pending : pending list;  (* oldest first, at most two in flight *)
  mutable retired : (unit -> unit) list;  (* freed once no frame is in flight *)
  mutable history_scale : int;
  mutable bands : int;  (* row bands per accumulation frame *)
  mutable frame_gpu : float;  (* GPU seconds of the frame in progress *)
  mutable completed : int;
  resource : Runtime_resources.Image.t;
  image : Rays.Image.t;
  mutable width : int;
  mutable height : int;
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
  mutable scene_edited : bool;

}

let ( let* ) = Result.bind
let gpu result = Result.map_error Ogpu.Error.to_string result
let rdk result = Result.map_error Rdk.Error.to_string result
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

let vec3_tuple (v : Rays.Vec3.t) = (v.x, v.y, v.z)

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
let flat_mesh ?(spheres = []) ?(strands = []) objects =
  let flatten objects =
    let positions = Stdlib.Buffer.create 4096
    and normals = Stdlib.Buffer.create 4096
    and ids = Stdlib.Buffer.create 1024
    and count = ref 0 in
    let* () =
      List.fold_left
        (fun acc (geometry, material_index) ->
          let* () = acc in
          let* triangles = rdk (Rdk.Triangulate.run geometry) in
          let* triangles =
            rdk
              (Rdk.Normal_ops.run ~owner:Rdk.Attribute.Vertex ~cusp_angle:(Float.pi /. 4.5) triangles)
          in
          let topology = Rdk.Geometry.topology triangles in
          let points = Rdk.Geometry.positions triangles in
          let vertex_normals =
            Option.bind
              (Rdk.Geometry.find_attribute ~owner:Rdk.Attribute.Vertex "N" triangles)
              (Rdk.Attribute.get (Rdk.Attribute.normal ~owner:Rdk.Attribute.Vertex))
          in
          let id_bytes = Bytes.create 4 in
          put_u32 id_bytes 0 material_index;
          for primitive = 0 to Rdk.Topology.primitive_count topology - 1 do
            if Rdk.Topology.primitive_size topology primitive = 3 then begin
              Rdk.Topology.iter_primitive_vertices topology primitive (fun vertex point ->
                  add_vec3 positions (Rdk.Packed.Float3.get points point);
                  add_vec3 normals
                    (match vertex_normals with
                    | Some field -> Rdk.Packed.Float3.get field vertex
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
      scene = None;
    }

(* Column-major 3x4 transform plus its 3x3 normal matrix (cofactors / det):
   seven packed float3 columns, 84 bytes. *)
let transform_columns (matrix : Rays.Mat4.t) =
  let values = Array.init 16 (fun index -> Rays.Mat4.get matrix ~row:(index / 4) ~column:(index mod 4)) in
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

(* Packs placements into TLAS records (structure index = part), shader
   transform records, and the per-instance (first triangle, material) table. *)
let layout_mesh ?(objects = [||]) ?(placed = [||]) ?(locals = [||]) base parts placements =
  let count = Array.length placements in
  let records = Array.make count { B.instance = { transform = [||]; mask = 0; structure_index = 0 }; user_id = 0; table_offset = 0 }
  and shader_bytes = Bytes.create (count * 84)
  and table = Bytes.create (count * 8) in
  let rec pack index =
    if index = count then Ok ()
    else
      let matrix, part, material = placements.(index) in
      let* columns = transform_columns matrix in
      records.(index) <-
        { B.instance = { transform = fst columns; mask = 0xFFFF_FFFF; structure_index = part }; user_id = 0; table_offset = 0 };
      put_transform_record shader_bytes (index * 84) columns;
      put_u32 table (index * 8) (match parts.(part) with Triangle_part (first, _) -> first / 3 | _ -> 0);
      put_u32 table ((index * 8) + 4) material;
      pack (index + 1)
  in
  let* () = pack 0 in
  Ok
    { base with
      instances = Some { records; shader_bytes; motion_transforms = None; matrices = Array.map (fun (m, _, _) -> m) placements }
    ; scene = Some { parts; placements; table; objects; placed; locals } }

let mesh ?spheres ?strands objects =
  let* flat = flat_mesh ?spheres ?strands objects in
  let parts =
    List.concat
      [ (if flat.triangles > 0 then [ Triangle_part (0, 3 * flat.triangles) ] else [])
      ; (if flat.extras.sphere_count > 0 then [ Sphere_part ] else [])
      ; (if flat.extras.strand_segments > 0 then [ Strand_part ] else []) ]
  in
  (* Several geometry kinds need one BLAS each, so the mesh becomes a scene of
     identity instances; a single kind keeps the flat fast path. *)
  if List.length parts < 2 then Ok flat
  else layout_mesh flat (Array.of_list parts) (Array.of_list (List.mapi (fun i _ -> (Rays.Mat4.identity, i, -1)) parts))

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
            { records; shader_bytes; matrices = transforms
            ; motion_transforms = (if motion = None then None else Some motion_transforms) };
      }

let scene_mesh objects =
  (* Each input as its parts and placements in its own index spaces. *)
  let input (matrix, (m : mesh)) =
    let whole = [| Triangle_part (0, Bytes.length m.mesh_positions / 12) |] in
    match (m.scene, m.instances) with
    | _ when m.extras.sphere_count > 0 || m.extras.strand_segments > 0 ->
        (* ponytail: spheres and strands would need per-instance bases in the
           intersection function; scene objects are triangle meshes. *)
        Error "path tracer scene_mesh objects cannot carry spheres or strands"
    | _, Some { motion_transforms = Some _; _ } -> Error "path tracer scene_mesh objects cannot carry motion"
    | Some layout, _ -> Ok (matrix, m, layout.parts, layout.placements)
    | None, None -> Ok (matrix, m, whole, [| (Rays.Mat4.identity, 0, -1) |])
    | None, Some instances ->
        Ok (matrix, m, whole, Array.mapi (fun i record -> (instances.matrices.(i), 0, record.B.user_id)) instances.records)
  in
  let rec inputs acc = function
    | [] -> Ok (List.rev acc)
    | object_ :: rest -> let* value = input object_ in inputs (value :: acc) rest
  in
  let* inputs = inputs [] objects in
  if inputs = [] then Error "path tracer scene needs at least one object"
  else
    let positions = Stdlib.Buffer.create 4096 and normals = Stdlib.Buffer.create 4096
    and ids = Stdlib.Buffer.create 1024 in
    let parts = ref [] and placements = ref [] and materials = ref [] and locals = ref [] and objects = ref [ 0 ]
    and placed = List.map (fun (matrix, _, _, _) -> matrix) inputs in
    let vertex_base = ref 0 and part_base = ref 0 and material_base = ref 0 and triangles = ref 0 in
    List.iter
      (fun (matrix, (m : mesh), input_parts, input_placements) ->
        Stdlib.Buffer.add_bytes positions m.mesh_positions;
        Stdlib.Buffer.add_bytes normals m.mesh_normals;
        for i = 0 to (Bytes.length m.mesh_ids / 4) - 1 do
          Stdlib.Buffer.add_int32_le ids (Int32.add (Bytes.get_int32_le m.mesh_ids (4 * i)) (Int32.of_int !material_base))
        done;
        Array.iter
          (function
            | Triangle_part (first, count) -> parts := Triangle_part (first + !vertex_base, count) :: !parts
            | part -> parts := part :: !parts)
          input_parts;
        Array.iter
          (fun (instance, part, material) ->
            locals := instance :: !locals;
            placements :=
              (Rays.Mat4.mul matrix instance, part + !part_base, if material < 0 then -1 else material + !material_base)
              :: !placements)
          input_placements;
        objects := (List.hd !objects + Array.length input_placements) :: !objects;
        materials := List.rev_append m.mesh_materials !materials;
        vertex_base := !vertex_base + (Bytes.length m.mesh_positions / 12);
        part_base := !part_base + Array.length input_parts;
        material_base := !material_base + List.length m.mesh_materials;
        triangles := !triangles + m.triangles)
      inputs;
    let* extras = prepare_extras ~first_material:0 [] [] in
    layout_mesh ~objects:(Array.of_list (List.rev !objects)) ~placed:(Array.of_list placed) ~locals:(Array.of_list (List.rev !locals))
      { mesh_positions = Stdlib.Buffer.to_bytes positions; mesh_normals = Stdlib.Buffer.to_bytes normals
      ; mesh_ids = Stdlib.Buffer.to_bytes ids; triangles = !triangles; mesh_materials = List.rev !materials
      ; instances = None; extras; scene = None }
      (Array.of_list (List.rev !parts)) (Array.of_list (List.rev !placements))

(* The same scene with object [o]'s placements at [matrices.(o) * local]. *)
let moved_mesh (m : mesh) matrices =
  match (m.scene, m.instances) with
  | Some layout, Some instances when Array.length layout.objects > 1 ->
      let matrices = Array.of_list matrices and objects = layout.objects in
      if Array.length matrices <> Array.length objects - 1 then
        Error "path tracer move needs one matrix per scene_mesh object"
      else
        (* Only objects whose matrix changed repack their placements. *)
        let placements = Array.copy layout.placements and records = Array.copy instances.records
        and shader_bytes = Bytes.copy instances.shader_bytes and world = Array.copy instances.matrices in
        let rec place o i =
          if o = Array.length matrices then Ok ()
          else if i = objects.(o + 1) || Rays.Mat4.nearly_equal matrices.(o) layout.placed.(o) ~eps:0. then
            place (o + 1) objects.(o + 1)
          else
            let _, part, material = placements.(i) in
            let matrix = Rays.Mat4.mul matrices.(o) layout.locals.(i) in
            let* columns = transform_columns matrix in
            placements.(i) <- (matrix, part, material);
            world.(i) <- matrix;
            records.(i) <- { (records.(i)) with instance = { (records.(i).instance) with transform = fst columns } };
            put_transform_record shader_bytes (i * 84) columns;
            place o (i + 1)
        in
        let* () = place 0 0 in
        Ok { m with instances = Some { instances with records; shader_bytes; matrices = world }
           ; scene = Some { layout with placements; placed = matrices } }
  | _ -> Error "path tracer move needs a scene_mesh scene"

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
  let normalize (v : Rays.Vec3.t) =
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

let light_bytes ?(world_lights = []) lights =
  let builder = Stdlib.Buffer.create 256 in
  let open Rays.Vec3 in
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
  (* World lights are one-sided (origin.w = 1): the edges are ordered so
     cross(u, v) is the emitting normal. *)
  List.iter
    (fun (light : Rays.World.light) ->
      let u = scale light.u 2. and v = scale light.v 2. in
      let n = cross u v in
      let u, v = if dot n light.normal < 0. then (v, u) else (u, v) in
      let origin = sub (sub light.position light.u) light.v in
      add_float4 builder (origin.x, origin.y, origin.z) 1.;
      add_float4 builder (u.x, u.y, u.z) 0.;
      add_float4 builder (v.x, v.y, v.z) 0.;
      add_float4 builder (light.radiance.r, light.radiance.g, light.radiance.b) (length n))
    world_lights;
  if lights = [] && world_lights = [] then Stdlib.Buffer.add_bytes builder (Bytes.make 64 '\000');
  Stdlib.Buffer.to_bytes builder

(* The baked World as one float32 buffer: camera map, lighting map, CDF
   marginal, CDF conditional rows (see pathtrace.metal). *)
let world_bytes (baked : Rays.World.baked) =
  let { Rays.World.width; height; _ } = baked.camera in
  let cdf = baked.cdf in
  if width < 1 || height < 1
     || baked.lighting.width <> width || baked.lighting.height <> height
     || Float.Array.length baked.camera.pixels <> width * height * 3
     || Float.Array.length baked.lighting.pixels <> width * height * 3
     || Float.Array.length cdf.marginal <> height + 1
     || Float.Array.length cdf.conditional <> height * (width + 1)
  then Error "path tracer World maps and CDF do not match in size"
  else
    let parts = [ baked.camera.pixels; baked.lighting.pixels; cdf.marginal; cdf.conditional ] in
    let bytes = Bytes.create (4 * List.fold_left (fun n a -> n + Float.Array.length a) 0 parts) in
    ignore
      (List.fold_left
         (fun offset array ->
           Float.Array.iteri (fun i value -> put_f32 bytes (offset + (4 * i)) value) array;
           offset + (4 * Float.Array.length array))
         0 parts);
    Ok bytes

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
    List.iter (fun blas -> ignore (B.destroy_accel blas)) gpu.scene_blas;
    Option.iter (fun value -> ignore (B.destroy_buffer value)) gpu.scene_table;
    Option.iter
      (fun (points, radii, indices, ids) ->
        List.iter (fun value -> ignore (B.destroy_buffer value)) [ points; radii; indices; ids ])
      gpu.strands
  end

(* Encodes the instance structure build over [build.gpu.primitive]. *)
let encode_instances device (build : mesh_build) command =
  let structures = match build.gpu.primitive with Some primitive -> [ primitive ] | None -> build.gpu.scene_blas in
  match (build.gpu.instance_buffer, structures) with
  | Some instances, _ :: _ ->
      let kind = if build.gpu.motion_buffer = None then B.User_id_instances else B.Motion_instances in
      let* structure =
        gpu
          (B.create_accel device
             (B.Tlas_of
                { instances; offset = 0L; instance_count = build.instance_count; kind
                ; structures
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
  ; curves = mesh.extras.strand_segments > 0
  ; scene = mesh.scene <> None }

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
    | Some gpu, Some _ when mesh.scene = None -> (
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
    let* positions, normals, material_ids, materials, spheres, boxes, strands, primitive, scene_blas, build_primitive =
      match reused with
      | Some (gpu, primitive) ->
          Ok (gpu.positions, gpu.normals, gpu.material_ids, gpu.materials, gpu.sphere_buffer, gpu.box_buffer, gpu.strands, primitive, [], false)
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
          let triangles first vertex_count =
            B.Triangles
              { vertices = positions; offset = Int64.of_int (first * 12); length = Int64.of_int (vertex_count * 12)
              ; vertex_stride = 12; vertex_count }
          in
          let geometry = function
            | Triangle_part (first, count) -> Ok (triangles first count)
            | Sphere_part -> (
                match boxes with
                | None -> Error "path tracer scene lost its sphere boxes"
                | Some boxes ->
                    Ok (B.Bounding_boxes
                          { boxes = [ { buffer = boxes; offset = 0L } ]; stride = 24; count = extras.sphere_count
                          ; options = B.default_geometry_options }))
            | Strand_part -> (
                match strands with
                | None -> Error "path tracer scene lost its strands"
                | Some (points, radii, indices, _) ->
                    Ok (B.Curves
                          { control_points = [ { buffer = points; offset = 0L } ]; control_stride = 12
                          ; control_point_count = extras.strand_point_count
                          ; radii = [ { buffer = radii; offset = 0L } ]; radius_stride = 4; indices; index_offset = 0L
                          ; segment_count = extras.strand_segments; control_points_per_segment = 2
                          ; curve_type = Round_curve; basis = Linear_basis; caps = Sphere_caps }))
          in
          (* A flat mesh has one geometry kind ([mesh] turns mixes into a scene). *)
          let parts =
            match mesh.scene with
            | Some layout -> Array.to_list layout.parts
            | None ->
                let vertex_count = Bytes.length mesh.mesh_positions / 12 in
                if vertex_count > 0 then [ Triangle_part (0, vertex_count) ]
                else if shape.spheres then [ Sphere_part ] else [ Strand_part ]
          in
          let rec build_all acc = function
            | [] -> Ok (List.rev acc)
            | part :: rest ->
                let* geometry = geometry part in
                let* blas = accel (B.Blas { geometries = [ geometry ] }) in
                build_all (blas :: acc) rest
          in
          let* blas = build_all [] parts in
          let primitive = List.hd blas in
          Ok (positions, normals, material_ids, materials, spheres, boxes, strands, primitive,
              (if mesh.scene = None then [] else blas), true)
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
    let* scene_table =
      match mesh.scene with
      | None -> Ok None
      | Some layout -> let* table = owned layout.table ~label:"pathtracer-scene-table" in Ok (Some table)
    in
    (* Scene BLASes build side by side, each in its own 256-byte-aligned
       slice of one scratch buffer. *)
    let scratch_offsets =
      List.rev
        (snd
           (List.fold_left
              (fun (offset, acc) blas ->
                let size = Int64.to_int (B.accel_sizes blas).build_scratch_size in
                (offset + ((size + 255) / 256 * 256), offset :: acc))
              (0, []) scene_blas))
    in
    let* work =
      buffer ~memory:Ogpu.Types.Device_local device ~label:"pathtracer-scratch"
        (if scene_blas <> [] then
           List.fold_left (fun total blas -> total + ((Int64.to_int (B.accel_sizes blas).build_scratch_size + 255) / 256 * 256))
             1024 scene_blas
         else max 1024 (Int64.to_int (Int64.mul 2L (B.accel_sizes primitive).build_scratch_size)))
    in
    scratch := Some work;
    let gpu_mesh =
      { positions; normals; material_ids; materials; sphere_buffer = spheres; box_buffer = boxes; strands
      ; structure = primitive; primitive = None; instance_buffer; transforms; motion_buffer
      ; prototype_key =
          (match mesh.instances with
           | Some _ when mesh.scene = None ->
               Some (mesh.mesh_positions, mesh.mesh_normals, mesh.mesh_ids, material_data,
                     Bytes.cat extras.sphere_bytes extras.strand_points)
           | _ -> None)
      ; scene_blas; scene_table
      ; owns_prototype = reused = None; shape }
    in
    let instance_count = match mesh.instances with None -> 0 | Some i -> Array.length i.records in
    if scene_blas <> [] then begin
      (* ponytail: scene BLASes are not compacted (one stage instead of two);
         compaction would save roughly half their memory. *)
      let* command = gpu (B.begin_commands queue) in
      commands := Some command;
      let build = { gpu = gpu_mesh; scratch = work; extra_scratch = None; size_buffer = None
                  ; uncompacted = None; stage = Ready; instance_count } in
      let* encoder = gpu (B.accel_encoder command) in
      let* () =
        List.fold_left2
          (fun acc blas offset ->
            let* () = acc in
            gpu (B.build_accel encoder blas ~scratch:work ~scratch_offset:(Int64.of_int offset) ()))
          (Ok ()) scene_blas scratch_offsets
      in
      let* () = gpu (B.end_accel encoder) in
      let* () = encode_instances device build command in
      structures := build.gpu.structure :: !structures;
      Option.iter (fun extra -> buffers := extra :: !buffers) build.extra_scratch;
      let* receipt = gpu (B.commit command) in
      build.stage <- Compacting receipt;
      Ok build
    end
    else if build_primitive then begin
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
      ([ 2; 3 ] @ (if shape.scene then [ 4 ] else [])
       @ (if shape.instanced then [ 5; 6; 7; 8; 9; 10 ] else [ 4; 5; 6; 7; 8; 9 ]) @ [ 11; 12; 13; 14 ]
       @ (if shape.spheres then [ 15 ] else []) @ (if shape.curves then [ 17; 18; 19 ] else [])
       @ if shape.scene then [ 20 ] else [])
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
        ; ("SPHERES", Ogpu.Shader.Bool shape.spheres); ("CURVES", Ogpu.Shader.Bool shape.curves)
        ; ("SCENE", Ogpu.Shader.Bool shape.scene) ]
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

(* Size-dependent storage: accumulation, two history frames, three output films. *)
type film = {
  accum : B.buffer;
  history_color : B.buffer array;
  history_geometry : B.buffer array;
  outputs : B.texture array;
}

(* ponytail: a failure midway leaks the earlier allocations to the device's
   leak report, like [create]; allocation failures are out-of-memory only. *)
let allocate_film device ~width ~height =
  let history label =
    buffer ~memory:Ogpu.Types.Device_local device ~label (width * height * 16) in
  let texture index =
    gpu
      (B.create_texture device
         {
           label = Some (Printf.sprintf "pathtracer-film-%d" index);
           width;
           height;
           depth = 1;
           mip_levels = 1;
           sample_count = 1;
           format = Rgba8_unorm;
           usage = [ Texture_binding; Storage_binding; Texture_copy_src ];
         })
  in
  let* accum = history "pathtracer-accum" in
  let* color0 = history "pathtracer-history-color-0" in
  let* color1 = history "pathtracer-history-color-1" in
  let* geometry0 = history "pathtracer-history-geometry-0" in
  let* geometry1 = history "pathtracer-history-geometry-1" in
  let* output0 = texture 0 in
  let* output1 = texture 1 in
  let* output2 = texture 2 in
  Ok { accum; history_color = [| color0; color1 |];
       history_geometry = [| geometry0; geometry1 |]; outputs = [| output0; output1; output2 |] }

let create ?(spp = 1) ?(bounces = 6) ?(exposure = 1.) ?(round_samples = 4) ~width ~height (scene : scene) =
  if width <= 0 || height <= 0 then Error "path tracer size must be positive"
  else if spp <= 0 || bounces <= 0 then Error "path tracer spp and bounces must be positive"
  else
    let* lease =
      Result.map_error
        (Format.asprintf "%a" Rays_execution.pp_error)
        (Rays_execution.acquire_gpu ())
    in
    let device = Rays_execution.gpu_device lease
    and queue = Rays_execution.gpu_queue lease in
    let release () = Rays_execution.release_gpu lease in
    let created =
      let* () =
        gpu (Ogpu.Caps.require ~operation:"Rays_pathtracer.create" (B.capabilities device) Ray_tracing)
      in
      let* mesh = mesh ~spheres:scene.spheres ~strands:scene.strands scene.objects in
      let* gpu_mesh = upload_mesh device queue mesh in
      let* panels = shared device ~label:"pathtracer-panels" (panel_bytes scene.environment.panels) in
      let* lights = shared device ~label:"pathtracer-lights" (light_bytes scene.lights) in
      let* world_buffer = shared device ~label:"pathtracer-world" (Bytes.make 16 '\000') in
      let* shader =
        gpu
          (Ogpu.Shader.of_source
             {
               backend = "metal";
               label = Some "rays_pathtracer";
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
      let* film = allocate_film device ~width ~height in
      let pixels = Bytes.make (width * height * 4) '\000' in
      let* resource =
        Result.map_error
          (Format.asprintf "%a" Runtime_resources.pp_error)
          (Runtime_resources.Image.create ~width ~height ~rgba:(Bytes.copy pixels))
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
          latest = mesh;
          panels;
          lights;
          light_count = List.length scene.lights;
          scene_lights = scene.lights;
          world = None;
          world_buffer;
          bsdf_only = Sys.getenv_opt "RAYS_PATHTRACER_BSDF_ONLY" = Some "1";
          accum = film.accum;
          outputs = film.outputs;
          shared_film = Rays_execution.gpu_shared lease;
          next_output_slot = 0;
          history_color = film.history_color;
          history_geometry = film.history_geometry;
          history_slot = 0;
          history_camera = None;
          history_epoch = 0;
          pending = [];
          retired = [];
          history_scale = 1;
          bands = 3;
          frame_gpu = 0.;
          completed = 0;
          resource;
          image = Rays.Image.Private.of_resource resource;
          width;
          height;
          spp;
          bounces;
          exposure;
          round_samples;
          profile = Sys.getenv_opt "RAYS_PATHTRACER_PROFILE" = Some "1";
          panel_count = List.length scene.environment.panels;
          sky = scene.environment.sky;
          ground = scene.environment.ground;
          frame = 0;
          camera = None;
          moving = false;
          scene_edited = false;

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
  match Rays.Camera.projection camera with
  | Perspective { fov_y; _ } -> Ok fov_y
  | Orthographic _ -> Error "path tracer requires a perspective camera"

(* The frame size the next dispatch traces: the whole frame, every pixel. *)
let dispatch_size t = 1, t.width, t.height

let uniform_bytes t (camera : camera) fov ~row_offset =
  let open Rays.Vec3 in
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
    let forward = normalize (sub (Rays.Camera.target camera) (Rays.Camera.position camera)) in
    let camera_up = Rays.Camera.up camera in
    let world_up =
      if Float.abs (dot forward camera_up) > 0.999 then
        if Float.abs forward.y > 0.999 then create 0. 0. 1. else create 0. 1. 0.
      else camera_up
    in
    let right = normalize (cross forward world_up) in
    (forward, right, cross right forward)
  in
  let forward, right, up = axes camera in
  let bytes = Bytes.make 288 '\000' in
  let put_vec4 offset (v : Rays.Vec3.t) w =
    put_f32 bytes offset v.x;
    put_f32 bytes (offset + 4) v.y;
    put_f32 bytes (offset + 8) v.z;
    put_f32 bytes (offset + 12) w
  in
  let put_rgb offset color =
    let r, g, b = color_tuple color in
    put_vec4 offset (create r g b) 0. in
  put_vec4 0 (Rays.Camera.position camera) (Rays.Camera.lens camera).aperture;
  put_vec4 16 forward (tan (fov /. 2.));
  put_vec4 32 right (float_of_int t.width /. float_of_int t.height);
  put_vec4 48 up (Rays.Camera.focus_distance camera);
  put_rgb 64 t.sky;
  put_rgb 80 t.ground;
  let scale, dispatch_width, dispatch_height = dispatch_size t in
  put_u32 bytes 96 dispatch_width;
  put_u32 bytes 100 dispatch_height;
  put_u32 bytes 140 scale;
  put_u32 bytes 276 row_offset;
  put_u32 bytes 104 t.frame;
  put_u32 bytes 108 t.spp;
  put_u32 bytes 112 (if t.world = None then t.panel_count else 0);
  put_u32 bytes 116 t.bounces;
  put_f32 bytes 120 t.exposure;
  (match t.world with
   | None -> ()
   | Some (baked : Rays.World.baked) ->
       put_f32 bytes 120 (t.exposure *. (2. ** baked.exposure));
       put_u32 bytes 208 1;
       put_u32 bytes 212 (match baked.background with Environment -> 0 | Color _ -> 1 | Transparent -> 2);
       put_u32 bytes 216 baked.camera.width;
       put_u32 bytes 220 baked.camera.height;
       (match baked.background with
        | Color c -> put_vec4 224 (create c.r c.g c.b) 0.
        | Environment | Transparent -> ());
       (match baked.sun with
        | Some sun when sun.angular_radius > 0. ->
            (* 1 - cos r = 2 sin^2 (r / 2), exact for tiny discs. *)
            let s = sin (sun.angular_radius /. 2.) in
            let one_minus_cos = 2. *. s *. s in
            put_vec4 240 (normalize sun.direction) one_minus_cos;
            put_vec4 256 (create sun.radiance.r sun.radiance.g sun.radiance.b)
              (1. /. (2. *. Float.pi *. one_minus_cos))
        | _ -> ());
       put_u32 bytes 272 (if t.bsdf_only then 1 else 0));
  put_u32 bytes 124 t.round_samples;
  put_u32 bytes 128 t.light_count;
  put_u32 bytes 132 (if t.moving then 1 else 0);
  let* () =
    match t.history_camera with
    | None -> Ok ()
    | Some _ when t.history_scale <> scale -> Ok ()
    | Some previous ->
        let* previous_fov = camera_fov previous in
        let forward, right, up = axes previous in
        put_u32 bytes 136 1;
        put_vec4 144 (Rays.Camera.position previous) 0.;
        put_vec4 160 forward (tan (previous_fov /. 2.));
        put_vec4 176 right (float_of_int t.width /. float_of_int t.height);
        put_vec4 192 up 0.;
        Ok ()
  in
  Ok bytes

(* GPU resources a frame in flight may still read are freed once none is. *)
let drain t =
  if t.pending = [] then begin
    let retired = t.retired in
    t.retired <- [];
    List.iter (fun free -> free ()) (List.rev retired)
  end

let retire t free = if t.pending = [] then free () else t.retired <- free :: t.retired

let reset_samples t =
  t.frame <- 0;
  t.completed <- 0

let restart t =
  reset_samples t;
  List.iter (fun pending -> pending.stale <- true) t.pending;
  t.history_camera <- None;
  t.history_epoch <- t.history_epoch + 1

let reset t =
  restart t;
  t.scene_edited <- false

(* Geometry, lights, or World just became current: the next [render] is a
   preview frame, like a camera move, so continuous edits stay interactive. *)
let edited t =
  restart t;
  t.scene_edited <- true

(* A reused prototype or a [move] shares the installed geometry and BLASes;
   ownership passes to the new mesh. *)
let install_gpu t gpu =
  if t.gpu.positions == gpu.positions then begin
    t.gpu.owns_prototype <- false;
    gpu.owns_prototype <- true
  end;
  let old = t.gpu in
  retire t (fun () -> destroy_gpu old);
  t.gpu <- gpu;
  edited t

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

let band_ms = 6.

(* Publishes a completed frame's pixels unless a reset made them obsolete. *)
let publish t (pending : pending) =
  let seconds = B.gpu_duration t.queue pending.receipt in
  if t.profile then Option.iter (fun seconds ->
      Printf.eprintf "pathtracer gpu_ms %.4f\n%!" (seconds *. 1000.)) seconds;
  if not pending.preview then begin
    t.frame_gpu <- t.frame_gpu +. Option.value seconds ~default:0.;
    if pending.last then begin
      (match seconds with
       | Some _ -> t.bands <- max 1 (min 3 (int_of_float (Float.ceil (t.frame_gpu *. 1000. /. band_ms))))
       | None -> ());
      t.frame_gpu <- 0.
    end
  end;
  if pending.history_epoch = t.history_epoch then t.history_camera <- Some pending.camera;
  if pending.stale || not pending.last then Ok ()
  else
    let film = t.outputs.(pending.slot) in
    let* () =
      if t.shared_film then
        Result.map_error
          (Format.asprintf "%a" Runtime_resources.pp_error)
          (Runtime_resources.Image.Private.replace_gpu t.resource film)
      else
        let* rgba = gpu (B.read_texture film ~bytes_per_row:(t.width * 4)) in
        ();
        Result.map_error
          (Format.asprintf "%a" Runtime_resources.pp_error)
          (Runtime_resources.Image.replace t.resource ~width:t.width ~height:t.height ~rgba)
    in
    if not pending.preview then t.completed <- t.completed + 1;
    Ok ()

let status t receipt = gpu (Ogpu.Command_buffer.status t.queue receipt)

(* A transform-only build: fresh instance records and shader transforms, and a
   new TLAS over the installed scene's BLASes; geometry, materials, and the
   table are borrowed (owns_prototype = false) until [install_gpu]. *)
let move_async t (moved : mesh) =
  match (moved.instances, moved.scene, t.gpu.scene_table) with
  | Some instances, Some layout, Some table
    (* ponytail: installed-scene identity is checked only as far as memory
       safety needs (BLAS count, table size); [move] after a failed rebuild
       may place the old geometry. *)
    when List.length t.gpu.scene_blas = Array.length layout.parts
         && B.buffer_size table = Int64.of_int (8 * Array.length instances.records) ->
      let owned = ref [] in
      let keep result = Result.map (fun value -> owned := value :: !owned; value) result in
      let started =
        let* packed = gpu (B.pack_instance_records t.device instances.records) in
        let* instance_buffer = keep (shared t.device ~label:"pathtracer-instances" packed) in
        let* transforms = keep (shared t.device ~label:"pathtracer-transforms" instances.shader_bytes) in
        let* scratch = keep (buffer ~memory:Ogpu.Types.Device_local t.device ~label:"pathtracer-scratch" 1024) in
        let build =
          { gpu = { t.gpu with instance_buffer = Some instance_buffer; transforms = Some transforms; owns_prototype = false }
          ; scratch; extra_scratch = None; size_buffer = None; uncompacted = None; stage = Ready
          ; instance_count = Array.length instances.records } in
        match submit_instances t.device t.queue build with
        | Ok () -> Ok build
        | Error _ as failure ->
            Option.iter (fun extra -> ignore (B.destroy_buffer extra)) build.extra_scratch;
            if build.gpu.structure != t.gpu.structure then ignore (B.destroy_accel build.gpu.structure);
            failure
      in
      (match started with
       | Ok _ -> ()
       | Error _ -> List.iter (fun value -> ignore (B.destroy_buffer value)) !owned);
      started
  | _ -> Error "path tracer move does not match the installed scene"

(* A build or move can start only while no frame band holds a queue slot. *)
let start_queued t =
  match t.queued_mesh with
  | Some (Full mesh) ->
      t.queued_mesh <- None;
      let* next = upload_mesh_async ~reuse:t.gpu t.device t.queue mesh in
      t.building <- Some next;
      Ok ()
  | Some (Move moved) ->
      t.queued_mesh <- None;
      let* next = move_async t moved in
      t.building <- Some next;
      Ok ()
  | None -> Ok ()

let poll_build t =
  match t.building with
  | None -> if t.pending = [] then start_queued t else Ok ()
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
          | Some (Full latest) ->
              t.queued_mesh <- None;
              (match built with Ok gpu -> destroy_gpu gpu | Error _ -> ());
              let* next = upload_mesh_async ~reuse:t.gpu t.device t.queue latest in
              t.building <- Some next;
              Ok ()
          | Some (Move moved) ->
              (* The move places the BLASes just built, so they install first. *)
              t.queued_mesh <- None;
              let* gpu = built in
              install_gpu t gpu;
              let* next = move_async t moved in
              t.building <- Some next;
              Ok ()
          | None ->
              let* gpu = built in
              install_gpu t gpu;
              Ok ()))

let flush t =
  let rec settle () =
    match t.pending with
    | [] -> drain t; Ok ()
    | pending :: rest -> (
        t.pending <- rest;
        match wait t.queue pending.receipt with
        | Ok () -> let* () = publish t pending in settle ()
        | Error _ as failure -> failure)
  in
  let* () = settle () in
  let* () = poll_build t in
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
(* Waits for the in-flight frame, swaps in film of the new size, and restarts
   accumulation; scene geometry and pipelines are kept. *)
let resize t ~width ~height =
  if width <= 0 || height <= 0 then Error "path tracer size must be positive"
  else if width = t.width && height = t.height then Ok ()
  else begin
    restart t;
    let* () = flush t in
    let* (film : film) = allocate_film t.device ~width ~height in
    let pixels = Bytes.make (width * height * 4) '\000' in
    (* The image stops sampling the old film before that film is destroyed. *)
    let* () = Result.map_error (Format.asprintf "%a" Runtime_resources.pp_error)
        (Runtime_resources.Image.replace t.resource ~width ~height ~rgba:(Bytes.copy pixels)) in
    List.iter (fun value -> ignore (B.destroy_buffer value))
      (t.accum :: Array.to_list t.history_color @ Array.to_list t.history_geometry);
    Array.iter (fun texture -> ignore (B.destroy_texture texture)) t.outputs;
    t.accum <- film.accum;
    t.history_color <- film.history_color;
    t.history_geometry <- film.history_geometry;
    t.outputs <- film.outputs;
    t.width <- width;
    t.height <- height;
    t.next_output_slot <- 0;
    t.history_slot <- 0;
    ();
    Ok ()
  end

let rec poll t =
  match t.pending with
  | [] -> drain t; Ok true
  | pending :: rest -> (
      match status t pending.receipt with
      | Ok Completed ->
          t.pending <- rest;
          let* () = publish t pending in
          poll t
      | Ok Pending -> Ok false
      | Error message ->
          t.pending <- rest;
          Error ("path tracer frame failed: " ^ message))

(* One frame of latency: the frame submitted here is read back by the next
   [render] (or [flush]), so the CPU never waits on the GPU while the display
   pipeline runs. Both strategies share the accumulation buffer in queue order. *)
(* One sample per call. An accumulation frame is submitted as row bands of
   about [band_ms] of GPU time each, one command buffer per band, so the
   window's own raster pass interleaves between them and the UI stays smooth
   while the tracer takes the rest of the GPU. The band count follows the
   measured GPU time of the previous frame; the accumulated image does not
   depend on it. *)
let render t (camera : camera) =
  let* fov = camera_fov camera in
  (* A camera change, or the first frame over newly installed geometry,
     lights, or World, is a preview frame; the first frame after creation or
     [reset] renders at full quality. *)
  let was_moving = t.moving in
  t.moving <- (match t.camera with Some previous -> previous <> camera | None -> false);
  if t.camera <> Some camera || was_moving then reset_samples t;
  t.camera <- Some camera;
  let* free = poll t in
  if not free then Ok ()
  else
    let* () = poll_build t in
    if t.scene_edited then begin
      t.scene_edited <- false;
      t.moving <- true
    end;
    let scale, dispatch_width, dispatch_height = dispatch_size t in
    (* ponytail: the queue holds three command buffers, one of which a mesh
       build may hold; more bands would need lazy submission from [poll]. *)
    let free_slots = 3 - (if t.building = None then 0 else 1) in
    let bands = if t.moving then 1 else max 1 (min t.bands (min dispatch_height free_slots)) in
    let rows_per_band = (dispatch_height + bands - 1) / bands in
    let slot = t.next_output_slot in
    let previous_history = t.history_slot in
    let next_history = previous_history lxor 1 in
    let* pipeline, table = current_pipeline t in
    let band index =
      let row_offset = index * rows_per_band in
      let rows = max 1 (min rows_per_band (dispatch_height - row_offset)) in
      let last = index = bands - 1 in
      let* uniforms = uniform_bytes t camera fov ~row_offset in
      let* commands = gpu (B.begin_commands t.queue) in
      let encoded =
        let* encoder = gpu (B.compute_encoder commands) in
        let set index value = gpu (B.set_buffer encoder ~index value) in
        let* () = gpu (B.set_pipeline encoder pipeline) in
        let* () = gpu (B.set_accel encoder ~index:0 t.gpu.structure) in
        (* The instance structure only references its BLASes: declare them
           read, or the device evicts them over time and rays start missing. *)
        let* () = gpu (B.compute_use_accels encoder (Option.to_list t.gpu.primitive @ t.gpu.scene_blas)) in
        let* () = gpu (B.set_bytes encoder ~index:1 uniforms) in
        let* () = set 2 t.gpu.positions in
        let* () = set 3 t.gpu.normals in
        let* () = if t.gpu.shape.instanced && not t.gpu.shape.scene then Ok () else set 4 t.gpu.material_ids in
        let* () = match t.gpu.scene_table with None -> Ok () | Some table -> set 20 table in
        let* () = set 5 t.gpu.materials in
        let* () = set 6 t.panels in
        let* () = set 7 t.accum in
        let* () = gpu (B.set_texture encoder ~index:0 t.outputs.(slot)) in
        let* () = set 8 t.world_buffer in
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
        let* () = gpu (B.dispatch_threads encoder ~threads:(dispatch_width, rows, 1) ~threadgroup:(16, 16, 1)) in
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
            let* () = gpu (B.dispatch_threads resolve ~threads:(dispatch_width, dispatch_height, 1) ~threadgroup:(16, 16, 1)) in
            gpu (B.end_compute resolve)
        in
        gpu (B.commit commands)
      in
      match encoded with
      | Error _ as failure ->
          ignore (B.abandon commands);
          failure
      | Ok receipt ->
          t.pending <- t.pending @ [ { receipt; slot; stale = false; preview = t.moving; camera;
                                       history_epoch = t.history_epoch; last } ];
          Ok ()
    in
    let rec submit index = if index = bands then Ok () else let* () = band index in submit (index + 1) in
    let* () = submit 0 in
    t.next_output_slot <- (slot + 1) mod 3;
    t.history_slot <- next_history;
    t.history_scale <- scale;
    (* A preview frame is shown but never counted: accumulation restarts at
       frame zero once the camera rests. *)
    if not t.moving then t.frame <- t.frame + 1;
    Ok ()

(* Swaps the geometry (buffers and acceleration structure) under the same
   pipeline and lights, then restarts accumulation. *)
let replace_mesh t mesh =
  List.iter (fun pending -> pending.stale <- true) t.pending;
  let* () = flush t in
  let* build = upload_mesh_async ~reuse:t.gpu t.device t.queue mesh in
  let* gpu = finish_build t.device t.queue build in
  install_gpu t gpu;
  t.latest <- mesh;
  Ok ()

(* Waits for the in-flight frame (it may read the buffer being replaced),
   swaps [current] for a buffer of [bytes], and restarts accumulation. *)
let swap_buffer t ~label bytes current install =
  List.iter (fun pending -> pending.stale <- true) t.pending;
  let* next = shared t.device ~label bytes in
  retire t (fun () -> ignore (B.destroy_buffer current));
  install next;
  edited t;
  Ok ()

let rebuild_lights t =
  let world_lights = match t.world with Some baked -> baked.lights | None -> [] in
  swap_buffer t ~label:"pathtracer-lights" (light_bytes ~world_lights t.scene_lights) t.lights (fun lights ->
    t.lights <- lights;
    t.light_count <- List.length t.scene_lights + List.length world_lights)

let set_lights t lights =
  t.scene_lights <- lights;
  rebuild_lights t

let set_world t baked =
  match (t.world, baked) with
  | Some current, Some next when current == next -> Ok ()
  | None, None -> Ok ()
  | _ ->
      let* bytes = match baked with None -> Ok (Bytes.make 16 '\000') | Some baked -> world_bytes baked in
      let* () = swap_buffer t ~label:"pathtracer-world" bytes t.world_buffer (fun world -> t.world_buffer <- world) in
      t.world <- baked;
      rebuild_lights t

(* The queue holds three command buffers: a frame in flight may use all of
   them, so a build or move arriving then waits for the next [render]. *)
let queue_mesh t mesh =
  t.queued_mesh <- Some (Full mesh);
  t.latest <- mesh;
  if t.building = None && t.pending = [] then start_queued t else Ok ()

let move t matrices =
  let* moved = moved_mesh t.latest matrices in
  let* () =
    match (t.building <> None || t.pending <> [], t.queued_mesh) with
    | true, Some (Full _) -> t.queued_mesh <- Some (Full moved); Ok ()
    | true, _ -> t.queued_mesh <- Some (Move moved); Ok ()
    | false, _ ->
        let* build = move_async t moved in
        t.building <- Some build;
        Ok ()
  in
  t.latest <- moved;
  Ok ()

let destroy t =
  let release f = ignore (f ()) in
  List.iter (fun pending -> pending.stale <- true) t.pending;
  release (fun () -> flush t);
  Rays.Image.destroy t.image;
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
      t.world_buffer;
      t.accum;
      t.history_color.(0);
      t.history_color.(1);
      t.history_geometry.(0);
      t.history_geometry.(1);
    ];
  Array.iter (fun film -> release (fun () -> B.destroy_texture film)) t.outputs;
  Rays_execution.release_gpu t.lease
