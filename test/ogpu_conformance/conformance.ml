let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let require condition message = if not condition then failwith message

let run ?metallib driver =
  let open Ogpu in
  let device = get (Backend.create_device driver) in
  let capabilities = Backend.capabilities device in
  let profile = get (Caps.create capabilities ~timestamp_queries:capabilities.timestamp_queries
    ~sparse_memory:capabilities.sparse_memory ~conservative_limits:[]) in
  require (Caps.has profile Caps.Ray_tracing = capabilities.ray_tracing)
    "ray-tracing capability mismatch";
  (match Caps.require profile (Caps.Unknown "future") with
   | Error { Error.kind = Unsupported; _ } -> ()
   | _ -> failwith "unknown feature was not typed Unsupported");
  if not (Caps.has profile Caps.Compute_pipeline) then
    (match Caps.require profile Caps.Compute_pipeline with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unavailable compute was not typed Unsupported");
  let descriptor : Types.buffer_descriptor =
    { label = Some "conformance"; size = 16L; usage = [Copy_src; Copy_dst] } in
  let source = get (Backend.create_buffer device descriptor) in
  let destination = get (Backend.create_buffer device descriptor) in
  let queue = get (Backend.create_queue device) in
  require (Command_buffer.completed_epoch queue = 0L)
    "new queue completed an epoch";
  (match Backend.poll_through queue 0L with
   | Error { Error.kind = Invalid_argument; _ } -> ()
   | _ -> failwith "zero completion epoch was accepted");
  let bytes = Bytes.init 16 (fun i -> Char.chr (i * 13 land 255)) in
  get (Backend.write_buffer source ~offset:0L bytes);
  require (get (Backend.read_buffer source ~offset:0L ~length:16) = bytes)
    "buffer round trip differs";
  (* Blit encoders: a buffer copy, texture upload/copy/readback with padded
     rows, the same at a mip level, and at an inset origin. *)
  let rec poll receipt attempts =
    match get (Command_buffer.status queue receipt) with
    | Command_buffer.Completed -> ()
    | Command_buffer.Pending when attempts = 0 ->
        failwith "submitted epoch did not complete"
    | Command_buffer.Pending -> Unix.sleepf 0.001; poll receipt (attempts - 1) in
  let blit encode =
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.blit_encoder commands) in
    encode encoder;
    get (Backend.end_blit encoder);
    let receipt=get (Backend.commit commands) in
    poll receipt 1000; receipt in
  let receipt = blit (fun encoder ->
    get (Backend.copy_buffer encoder ~src:source ~dst:destination ~length:16L ())) in
  require (Command_buffer.completed_epoch queue = receipt.epoch)
    "queue completed epoch differs from receipt";
  require (get (Backend.poll_through queue receipt.epoch))
    "completed epoch did not remain complete";
  require (get (Backend.read_buffer destination ~offset:0L ~length:16) = bytes)
    "encoded buffer copy differs";
  let transfer_buffer : Types.buffer_descriptor =
    {label=Some "texture-transfer";size=512L;usage=[Copy_src;Copy_dst]} in
  let upload=get (Backend.create_buffer device transfer_buffer) in
  let readback=get (Backend.create_buffer device transfer_buffer) in
  let texture_descriptor : Types.texture_descriptor =
    {label=Some "texture-round-trip";width=2;height=2;depth=1;
     mip_levels=1;sample_count=1;
     usage=[Texture_copy_src;Texture_copy_dst]} in
  let first=get (Backend.create_texture device texture_descriptor) in
  let second=get (Backend.create_texture device texture_descriptor) in
  let padded=Bytes.make 512 '\000' in
  for i=0 to 7 do
    Bytes.set padded i (Char.chr (i*17+3));
    Bytes.set padded (256+i) (Char.chr (i*19+5))
  done;
  get (Backend.write_buffer upload ~offset:0L padded);
  get (Backend.write_buffer readback ~offset:0L (Bytes.make 512 '\000'));
  let extent : Types.extent={width=2;height=2;depth=1} in
  let round_trip ?(mip=0) ?(origin={Types.x=0;y=0;z=0}) src dst =
    ignore (blit (fun encoder ->
      get (Backend.buffer_to_texture encoder ~src:upload ~bytes_per_row:256L
        ~bytes_per_image:512L ~dst:src ~mip ~origin ~extent ());
      get (Backend.copy_texture encoder ~src ~src_mip:mip ~src_origin:origin
        ~dst ~dst_mip:mip ~dst_origin:origin ~extent ());
      get (Backend.texture_to_buffer encoder ~src:dst ~mip ~origin ~extent
        ~dst:readback ~bytes_per_row:256L ~bytes_per_image:512L ()))) in
  round_trip first second;
  require (get (Backend.read_buffer readback ~offset:0L ~length:512)=padded)
    "texture round-trip changed row bytes or padding";
  let compact=Bytes.create 16 in
  Bytes.blit padded 0 compact 0 8;
  Bytes.blit padded 256 compact 8 8;
  require (get (Backend.read_texture second ~bytes_per_row:8)=compact)
    "texture copy differs from uploaded pixels";
  let mipped_descriptor={texture_descriptor with width=4;height=4;mip_levels=2} in
  let mip_first=get (Backend.create_texture device mipped_descriptor) in
  let mip_second=get (Backend.create_texture device mipped_descriptor) in
  get (Backend.write_buffer readback ~offset:0L (Bytes.make 512 '\000'));
  round_trip ~mip:1 mip_first mip_second;
  require (get (Backend.read_buffer readback ~offset:0L ~length:512)=padded)
    "mip-level texture round-trip differs";
  get (Backend.write_buffer readback ~offset:0L (Bytes.make 512 '\000'));
  round_trip ~origin:{Types.x=1;y=1;z=0} mip_first mip_second;
  require (get (Backend.read_buffer readback ~offset:0L ~length:512)=padded)
    "texture subregion round-trip differs";
  let expected_image=Bytes.make 64 '\000' in
  Bytes.blit padded 0 expected_image 20 8;
  Bytes.blit padded 256 expected_image 36 8;
  require (get (Backend.read_texture mip_second ~bytes_per_row:16)=
    expected_image) "texture subregion changed other pixels";
  (* Precompiled metallib with function constants, through the same library
     and encoder path as source shaders. *)
  let compute_interface : Shader.binding list=
    [{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Compute]}] in
  let compiled bytes constants =
    get (Shader.of_metallib
      {backend="metal";label=Some"exact-compute-compiled";bytes;
       entry_points=[{name="exact_compute_compiled";stage=Shader.Compute}];
       bindings=compute_interface} ~constants) in
  if Caps.has profile Caps.Compute_pipeline then begin
    let compute_buffer=get (Backend.create_buffer device
      {label=Some"compute-output";size=16L;
       usage=[Storage;Copy_src;Copy_dst]}) in
    let run_compute shader factor =
      let input=Bytes.create 16 in
      for i=0 to 3 do Bytes.set_int32_le input (i*4) (Int32.of_int i) done;
      get (Backend.write_buffer compute_buffer ~offset:0L input);
      let library=get (Backend.create_library device shader) in
      let pipeline=get (Backend.create_compute_pipeline_from library
        ~entry:"exact_compute_compiled" ~interface:compute_interface ()) in
      let commands=get (Backend.begin_commands queue) in
      let encoder=get (Backend.compute_encoder commands) in
      get (Backend.set_pipeline encoder pipeline);
      get (Backend.set_buffer encoder ~index:0 compute_buffer);
      get (Backend.dispatch_threads encoder ~threads:(4,1,1) ~threadgroup:(4,1,1));
      get (Backend.end_compute encoder);
      poll (get (Backend.commit commands)) 1000;
      let output=get (Backend.read_buffer compute_buffer ~offset:0L ~length:16) in
      for i=0 to 3 do
        require (Bytes.get_int32_le output (i*4)=Int32.of_int(i*factor+1))
          "compiled compute output differs"
      done;
      get (Backend.destroy_pipeline pipeline);
      get (Backend.destroy_library library) in
    Option.iter (fun bytes ->
      run_compute (compiled bytes ["TRIPLE",Shader.Bool true]) 3;
      run_compute (compiled bytes ["TRIPLE",Shader.Bool false]) 2) metallib;
    get (Backend.destroy_buffer compute_buffer)
  end else
    Option.iter (fun bytes ->
      match Backend.create_library device (compiled bytes ["TRIPLE",Shader.Bool true]) with
      | Ok library ->
          (match Backend.create_compute_pipeline_from library
             ~entry:"exact_compute_compiled" ~interface:compute_interface () with
           | Error { Error.kind = Unsupported; _ } -> ()
           | _ -> failwith "unsupported compiled pipeline was accepted");
          get (Backend.destroy_library library)
      | Error { Error.kind = Unsupported; _ } -> ()
      | Error error -> failwith (Error.to_string error)) metallib;
  (* Reusable libraries and immediate-mode encoders: one library, two
     pipelines by function constant, exact output, blit copy, and status
     polling on a non-blocking command buffer. *)
  let library_source=Bytes.of_string
    "#include <metal_stdlib>\nusing namespace metal;\nconstant bool TRIPLE [[function_constant(0)]];\nkernel void scale(device uint *values [[buffer(0)]], constant uint &bias [[buffer(1)]], uint i [[thread_position_in_grid]]) { values[i] = values[i] * (TRIPLE ? 3u : 2u) + bias; }\nkernel void fill(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) { values[i] = i; }\n" in
  let library_shader=get (Shader.create
    {backend="metal";label=Some"conformance-library";bytes=library_source;
     entry_points=[{name="scale";stage=Shader.Compute};{name="fill";stage=Shader.Compute}];
     bindings=[]}) in
  let library=get (Backend.create_library device library_shader) in
  let scale_interface : Shader.binding list=
    [{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Compute]};
     {group=0;binding=1;kind=Shader.Uniform_buffer;visibility=[Shader.Compute]}] in
  let rec poll_epoch receipt attempts =
    match get (Command_buffer.status queue receipt) with
    | Command_buffer.Completed -> ()
    | Command_buffer.Pending when attempts = 0 -> failwith "encoded commands did not complete"
    | Command_buffer.Pending -> Unix.sleepf 0.001; poll_epoch receipt (attempts - 1) in
  let words=get (Backend.create_buffer device
    {label=Some"encoded-words";size=16L;usage=[Storage;Copy_src;Copy_dst]}) in
  let copied=get (Backend.create_buffer device
    {label=Some"encoded-copy";size=16L;usage=[Storage;Copy_src;Copy_dst]}) in
  let local=get (Backend.create_buffer ~memory:Types.Device_local device
    {label=Some"device-local";size=16L;usage=[Storage;Copy_src;Copy_dst]}) in
  require (Backend.buffer_memory local=Types.Device_local) "device-local memory was not recorded";
  (match Backend.read_buffer local ~offset:0L ~length:16 with
   | Error { Error.kind = Unsupported; _ } -> ()
   | _ -> failwith "device-local buffer was host readable");
  (match Backend.write_buffer local ~offset:0L (Bytes.make 16 '\000') with
   | Error { Error.kind = Unsupported; _ } -> ()
   | _ -> failwith "device-local buffer was host writable");
  let bias=Bytes.create 4 in
  Bytes.set_int32_le bias 0 5l;
  if Caps.has profile Caps.Compute_pipeline then begin
    let triple=get (Backend.create_compute_pipeline_from library ~entry:"scale"
      ~constants:["TRIPLE",Shader.Bool true] ~interface:scale_interface ()) in
    let double=get (Backend.create_compute_pipeline_from library ~entry:"scale"
      ~constants:["TRIPLE",Shader.Bool false] ~interface:scale_interface ()) in
    (match Backend.create_compute_pipeline_from library ~entry:"scale"
       ~constants:["TRIPLE",Shader.Bool true]
       ~interface:[{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Compute]}] () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "mismatched library interface was accepted");
    (match Backend.create_compute_pipeline_from library ~entry:"missing" ~interface:[] () with
     | Error _ -> ()
     | Ok _ -> failwith "missing library entry was accepted");
    (match Backend.destroy_library library with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "library with live pipelines was destroyed");
    let run pipeline factor =
      let input=Bytes.create 16 in
      for i=0 to 3 do Bytes.set_int32_le input (i*4) (Int32.of_int i) done;
      get (Backend.write_buffer words ~offset:0L input);
      get (Backend.write_buffer copied ~offset:0L (Bytes.make 16 '\000'));
      let commands=get (Backend.begin_commands queue) in
      let compute=get (Backend.compute_encoder commands) in
      (match Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1) with
       | Error { Error.kind = Invalid_state; _ } -> ()
       | _ -> failwith "dispatch without a pipeline was accepted");
      get (Backend.set_pipeline compute pipeline);
      get (Backend.set_buffer compute ~index:0 words);
      get (Backend.set_bytes compute ~index:1 bias);
      (match Backend.blit_encoder commands with
       | Error { Error.kind = Invalid_state; _ } -> ()
       | _ -> failwith "second encoder opened while one was recording");
      get (Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1));
      get (Backend.end_compute compute);
      let blit=get (Backend.blit_encoder commands) in
      get (Backend.copy_buffer blit ~src:words ~dst:copied ~length:16L ());
      get (Backend.end_blit blit);
      let receipt=get (Backend.commit commands) in
      (match Backend.commit commands with
       | Error { Error.kind = Invalid_state; _ } -> ()
       | _ -> failwith "commands were committed twice");
      poll_epoch receipt 1000;
      let output=get (Backend.read_buffer copied ~offset:0L ~length:16) in
      for i=0 to 3 do
        require (Bytes.get_int32_le output (i*4)=Int32.of_int (i*factor+5))
          "encoded compute output differs"
      done in
    run triple 3; run double 2; run triple 3;
    get (Backend.destroy_pipeline triple);
    get (Backend.destroy_pipeline double)
  end else begin
    (match Backend.create_compute_pipeline_from library ~entry:"scale" ~interface:scale_interface () with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported library pipeline was accepted");
    let commands=get (Backend.begin_commands queue) in
    (match Backend.compute_encoder commands with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported compute encoder was opened");
    get (Backend.abandon commands)
  end;
  let seeded=Bytes.init 16 (fun i -> Char.chr (200 - i)) in
  get (Backend.write_buffer words ~offset:0L seeded);
  get (Backend.write_buffer copied ~offset:0L (Bytes.make 16 '\000'));
  let commands=get (Backend.begin_commands queue) in
  let blit=get (Backend.blit_encoder commands) in
  (match Backend.copy_buffer blit ~src:words ~src_offset:8L ~dst:copied ~length:16L () with
   | Error { Error.kind = Invalid_argument; _ } -> ()
   | _ -> failwith "out-of-range blit copy was accepted");
  get (Backend.copy_buffer blit ~src:words ~src_offset:4L ~dst:copied ~dst_offset:8L ~length:8L ());
  get (Backend.end_blit blit);
  let blit_receipt=get (Backend.commit commands) in
  poll_epoch blit_receipt 1000;
  let expected_copy=Bytes.make 16 '\000' in
  Bytes.blit seeded 4 expected_copy 8 8;
  require (get (Backend.read_buffer copied ~offset:0L ~length:16)=expected_copy)
    "encoded blit copy differs";
  let abandoned=get (Backend.begin_commands queue) in
  let blit=get (Backend.blit_encoder abandoned) in
  get (Backend.copy_buffer blit ~src:words ~dst:copied ~length:16L ());
  get (Backend.abandon abandoned);
  (match Backend.commit abandoned with
   | Error { Error.kind = Invalid_state; _ } -> ()
   | _ -> failwith "abandoned commands were committed");
  require (get (Backend.read_buffer copied ~offset:0L ~length:16)=expected_copy)
    "abandoned commands executed";
  get (Backend.destroy_library library);
  (* Ray tracing: BLAS build, ray-query primitive id and t, TLAS instance ids,
     and refit after moving vertices; typed Unsupported otherwise. *)
  let ray_source=Bytes.of_string
    "#include <metal_stdlib>\n#include <metal_raytracing>\nusing namespace metal;\nusing namespace raytracing;\nstruct Hit { uint hit; uint primitive; uint instance; float t; };\nkernel void trace(primitive_acceleration_structure scene [[buffer(0)]], device const float4 *rays [[buffer(1)]], device Hit *hits [[buffer(2)]], uint i [[thread_position_in_grid]]) { ray r(rays[i*2].xyz, rays[i*2+1].xyz, 0.001f, 100.0f); intersector<triangle_data> isect; isect.assume_geometry_type(geometry_type::triangle); auto h = isect.intersect(r, scene); hits[i].hit = h.type == intersection_type::triangle ? 1u : 0u; hits[i].primitive = h.primitive_id; hits[i].instance = 0u; hits[i].t = h.distance; }\nkernel void trace_instances(instance_acceleration_structure scene [[buffer(0)]], device const float4 *rays [[buffer(1)]], device Hit *hits [[buffer(2)]], uint i [[thread_position_in_grid]]) { ray r(rays[i*2].xyz, rays[i*2+1].xyz, 0.001f, 100.0f); intersector<triangle_data, instancing> isect; isect.assume_geometry_type(geometry_type::triangle); auto h = isect.intersect(r, scene); hits[i].hit = h.type == intersection_type::triangle ? 1u : 0u; hits[i].primitive = h.primitive_id; hits[i].instance = h.instance_id; hits[i].t = h.distance; }\n" in
  let ray_shader=get (Shader.create
    {backend="metal";label=Some"conformance-rays";bytes=ray_source;
     entry_points=[{name="trace";stage=Shader.Compute};{name="trace_instances";stage=Shader.Compute}];
     bindings=[]}) in
  let ray_interface : Shader.binding list=
    [{group=0;binding=0;kind=Shader.Acceleration_structure;visibility=[Shader.Compute]};
     {group=0;binding=1;kind=Shader.Storage_buffer;visibility=[Shader.Compute]};
     {group=0;binding=2;kind=Shader.Storage_buffer;visibility=[Shader.Compute]}] in
  let put_f32 bytes offset value=Bytes.set_int32_le bytes offset (Int32.bits_of_float value) in
  (* Two triangles in z=0 (primitive 0 around x=0, primitive 1 around x=4). *)
  let vertex_bytes z=
    let bytes=Bytes.create 72 in
    Array.iteri (fun i v -> put_f32 bytes (i*4) v)
      [|-1.;-1.;z; 1.;-1.;z; 0.;1.;z;  3.;-1.;z; 5.;-1.;z; 4.;1.;z|];
    bytes in
  let vertices=get (Backend.create_buffer device
    {label=Some"ray-vertices";size=72L;usage=[Storage;Copy_dst]}) in
  get (Backend.write_buffer vertices ~offset:0L (vertex_bytes 0.));
  let ray_bytes=Bytes.create 128 in
  (* Rays from z=2 toward -z at x=0, x=4, x=8 (miss), x=12 (miss). *)
  Array.iteri (fun i v -> put_f32 ray_bytes (i*4) v)
    [|0.;0.;2.;0.; 0.;0.;-1.;0.;  4.;0.;2.;0.; 0.;0.;-1.;0.;  8.;0.;2.;0.; 0.;0.;-1.;0.;  12.;0.;2.;0.; 0.;0.;-1.;0.|];
  let rays=get (Backend.create_buffer device {label=Some"rays";size=128L;usage=[Storage;Copy_dst]}) in
  get (Backend.write_buffer rays ~offset:0L ray_bytes);
  let hits=get (Backend.create_buffer device {label=Some"hits";size=64L;usage=[Storage;Copy_src]}) in
  let blas_descriptor=Backend.Blas
    {geometries=[Backend.Triangles {vertices;offset=0L;length=72L;vertex_stride=12;vertex_count=6}];
     allow_refit=true} in
  if Caps.has profile Caps.Ray_tracing then begin
    let ray_library=get (Backend.create_library device ray_shader) in
    let trace=get (Backend.create_compute_pipeline_from ray_library ~entry:"trace" ~interface:ray_interface ()) in
    let trace_instances=get (Backend.create_compute_pipeline_from ray_library ~entry:"trace_instances" ~interface:ray_interface ()) in
    let blas=get (Backend.create_accel device blas_descriptor) in
    let sizes=Backend.accel_sizes blas in
    require (sizes.structure_size>0L && sizes.build_scratch_size>=0L) "BLAS sizes are empty";
    let scratch=get (Backend.create_buffer ~memory:Types.Device_local device
      {label=Some"scratch";size=Int64.max 256L (Int64.mul 2L (Int64.max sizes.build_scratch_size sizes.refit_scratch_size));usage=[Storage]}) in
    let stride=Backend.instance_stride device in
    let instances=get (Backend.pack_instances device
      [|{transform=[|1.;0.;0.;0.; 0.;1.;0.;0.; 0.;0.;1.;0.|];mask=0xFFFF_FFFF;structure_index=0};
        {transform=[|1.;0.;0.;8.; 0.;1.;0.;0.; 0.;0.;1.;0.|];mask=0xFFFF_FFFF;structure_index=0}|]) in
    require (Bytes.length instances=2*stride) "instance packing stride differs";
    let instance_buffer=get (Backend.create_buffer device
      {label=Some"instances";size=Int64.of_int (2*stride);usage=[Storage;Copy_dst]}) in
    get (Backend.write_buffer instance_buffer ~offset:0L instances);
    let tlas=get (Backend.create_accel device
      (Backend.Tlas {instances=instance_buffer;offset=0L;instance_count=2;structures=[blas];allow_refit=false})) in
    (match Backend.create_accel device
       (Backend.Tlas {instances=instance_buffer;offset=0L;instance_count=3;structures=[blas];allow_refit=false}) with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "oversized TLAS instance count was accepted");
    let tlas_scratch=get (Backend.create_buffer ~memory:Types.Device_local device
      {label=Some"tlas-scratch";size=Int64.max 256L (Backend.accel_sizes tlas).build_scratch_size;usage=[Storage]}) in
    let commands=get (Backend.begin_commands queue) in
    let compute=get (Backend.compute_encoder commands) in
    get (Backend.set_pipeline compute trace);
    (match Backend.set_accel compute ~index:0 blas with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "unbuilt structure was bound");
    get (Backend.end_compute compute);
    let build=get (Backend.accel_encoder commands) in
    (match Backend.build_accel build tlas ~scratch:tlas_scratch () with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "TLAS built before its BLAS");
    (match Backend.refit_accel build blas ~scratch () with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "refit before build was accepted");
    get (Backend.build_accel build blas ~scratch ());
    (match Backend.build_accel build blas ~scratch () with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "double build was accepted");
    get (Backend.build_accel build tlas ~scratch:tlas_scratch ());
    get (Backend.end_accel build);
    let query commands pipeline structure =
      let compute=get (Backend.compute_encoder commands) in
      get (Backend.set_pipeline compute pipeline);
      get (Backend.set_accel compute ~index:0 structure);
      get (Backend.set_buffer compute ~index:1 rays);
      get (Backend.set_buffer compute ~index:2 hits);
      get (Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1));
      get (Backend.end_compute compute) in
    query commands trace blas;
    let receipt=get (Backend.commit commands) in
    poll_epoch receipt 1000;
    let read_hits () =
      let bytes=get (Backend.read_buffer hits ~offset:0L ~length:64) in
      Array.init 4 (fun i ->
        Int32.to_int (Bytes.get_int32_le bytes (i*16)),
        Int32.to_int (Bytes.get_int32_le bytes (i*16+4)),
        Int32.to_int (Bytes.get_int32_le bytes (i*16+8)),
        Int32.float_of_bits (Bytes.get_int32_le bytes (i*16+12))) in
    let close a b=Float.abs (a-.b)<1e-4 in
    let primitive_hits=read_hits () in
    let hit0,prim0,_,t0=primitive_hits.(0) and hit1,prim1,_,t1=primitive_hits.(1)
    and hit2,_,_,_=primitive_hits.(2) and hit3,_,_,_=primitive_hits.(3) in
    require (hit0=1 && prim0=0 && close t0 2.) "primitive 0 hit differs";
    require (hit1=1 && prim1=1 && close t1 2.) "primitive 1 hit differs";
    require (hit2=0 && hit3=0) "misses reported hits";
    let commands=get (Backend.begin_commands queue) in
    query commands trace_instances tlas;
    poll_epoch (get (Backend.commit commands)) 1000;
    let instance_hits=read_hits () in
    let hit0,prim0,inst0,t0=instance_hits.(0) and hit1,prim1,inst1,t1=instance_hits.(1)
    and hit2,prim2,inst2,t2=instance_hits.(2) and hit3,prim3,inst3,t3=instance_hits.(3) in
    require (hit0=1 && prim0=0 && inst0=0 && close t0 2.) "instance 0 primitive 0 hit differs";
    require (hit1=1 && prim1=1 && inst1=0 && close t1 2.) "instance 0 primitive 1 hit differs";
    require (hit2=1 && prim2=0 && inst2=1 && close t2 2.) "instance 1 primitive 0 hit differs";
    require (hit3=1 && prim3=1 && inst3=1 && close t3 2.) "instance 1 primitive 1 hit differs";
    (* Refit: move the triangles to z=1 and query the BLAS again; t becomes 1. *)
    get (Backend.write_buffer vertices ~offset:0L (vertex_bytes 1.));
    let commands=get (Backend.begin_commands queue) in
    let refit=get (Backend.accel_encoder commands) in
    get (Backend.refit_accel refit blas ~scratch ());
    get (Backend.end_accel refit);
    query commands trace blas;
    poll_epoch (get (Backend.commit commands)) 1000;
    let refit_hits=read_hits () in
    let hit0,prim0,_,t0=refit_hits.(0) and hit1,prim1,_,t1=refit_hits.(1) in
    require (hit0=1 && prim0=0 && close t0 1.) "refit primitive 0 hit differs";
    require (hit1=1 && prim1=1 && close t1 1.) "refit primitive 1 hit differs";
    (* G5: bounding boxes resolved by an intersection function table, curves,
       motion keyframes, user-id instances with masks, compaction and copy,
       and a visible function table. *)
    let extra_source=Bytes.of_string (String.concat "\n" [
      "#include <metal_stdlib>";"#include <metal_raytracing>";"using namespace metal;";"using namespace raytracing;";
      "struct Hit { uint hit; uint primitive; uint instance; float t; };";
      "struct Sphere { float4 center_radius; };";
      "struct BoxResult { bool accept [[accept_intersection]]; float distance [[distance]]; };";
      "[[intersection(bounding_box)]] BoxResult sphere_hit(float3 origin [[origin]], float3 direction [[direction]], float min_distance [[min_distance]], float max_distance [[max_distance]], uint primitive_id [[primitive_id]], const device Sphere *spheres [[buffer(0)]]) {";
      "  BoxResult result; result.accept = false; result.distance = 0.0f;";
      "  float3 c = spheres[primitive_id].center_radius.xyz; float r = spheres[primitive_id].center_radius.w;";
      "  float3 oc = origin - c; float b = dot(oc, direction); float cc = dot(oc, oc) - r * r; float disc = b * b - cc;";
      "  if (disc < 0.0f) return result; float t = -b - sqrt(disc);";
      "  if (t < min_distance || t > max_distance) return result;";
      "  result.accept = true; result.distance = t; return result; }";
      "inline ray make_ray(const device float4 *rays, uint tid) { ray r; r.origin = rays[tid * 2].xyz; r.direction = rays[tid * 2 + 1].xyz; r.min_distance = 0.0f; r.max_distance = 100.0f; return r; }";
      "kernel void trace_boxes(primitive_acceleration_structure scene [[buffer(0)]], const device float4 *rays [[buffer(1)]], device Hit *hits [[buffer(2)]], intersection_function_table<> table [[buffer(3)]], uint tid [[thread_position_in_grid]]) {";
      "  intersector<> query; auto hit = query.intersect(make_ray(rays, tid), scene, table);";
      "  hits[tid].hit = hit.type == intersection_type::bounding_box ? 1u : 0u; hits[tid].primitive = hit.primitive_id; hits[tid].instance = 0u; hits[tid].t = hit.distance; }";
      "kernel void trace_curves(primitive_acceleration_structure scene [[buffer(0)]], const device float4 *rays [[buffer(1)]], device Hit *hits [[buffer(2)]], uint tid [[thread_position_in_grid]]) {";
      "  intersector<curve_data> query; auto hit = query.intersect(make_ray(rays, tid), scene);";
      "  hits[tid].hit = hit.type == intersection_type::curve ? 1u : 0u; hits[tid].primitive = hit.primitive_id; hits[tid].instance = 0u; hits[tid].t = hit.distance; }";
      "kernel void trace_motion(acceleration_structure<primitive_motion> scene [[buffer(0)]], const device float4 *rays [[buffer(1)]], device Hit *hits [[buffer(2)]], constant float &time [[buffer(3)]], uint tid [[thread_position_in_grid]]) {";
      "  intersector<primitive_motion> query; auto hit = query.intersect(make_ray(rays, tid), scene, time);";
      "  hits[tid].hit = hit.type == intersection_type::triangle ? 1u : 0u; hits[tid].primitive = hit.primitive_id; hits[tid].instance = 0u; hits[tid].t = hit.distance; }";
      "kernel void trace_masked(instance_acceleration_structure scene [[buffer(0)]], const device float4 *rays [[buffer(1)]], device Hit *hits [[buffer(2)]], constant uint &mask [[buffer(3)]], uint tid [[thread_position_in_grid]]) {";
      "  intersector<instancing> query; auto hit = query.intersect(make_ray(rays, tid), scene, mask);";
      "  hits[tid].hit = hit.type == intersection_type::triangle ? 1u : 0u; hits[tid].primitive = hit.primitive_id; hits[tid].instance = hit.user_instance_id; hits[tid].t = hit.distance; }";
      "kernel void trace_motion_instances(acceleration_structure<instancing, instance_motion> scene [[buffer(0)]], const device float4 *rays [[buffer(1)]], device Hit *hits [[buffer(2)]], constant float &time [[buffer(3)]], uint tid [[thread_position_in_grid]]) {";
      "  intersector<instancing, instance_motion> query; auto hit = query.intersect(make_ray(rays, tid), scene, time);";
      "  hits[tid].hit = hit.type == intersection_type::triangle ? 1u : 0u; hits[tid].primitive = hit.primitive_id; hits[tid].instance = hit.user_instance_id; hits[tid].t = hit.distance; }";
      "[[visible]] float scale_visible(float x) { return x * 3.0f; }";
      "kernel void call_visible(device float *values [[buffer(0)]], visible_function_table<float(float)> table [[buffer(1)]], uint tid [[thread_position_in_grid]]) { values[tid] = table[0](values[tid]); }"]) in
    let extra_shader=get (Shader.create
      {backend="metal";label=Some"conformance-rt-extra";bytes=extra_source;
       entry_points=List.map (fun name -> {Shader.name;stage=Shader.Compute}) ["trace_boxes";"trace_curves";"trace_motion";"trace_masked";"trace_motion_instances";"call_visible"];
       bindings=[]}) in
    let extra=get (Backend.create_library device extra_shader) in
    let binding index kind : Shader.binding={group=0;binding=index;kind;visibility=[Shader.Compute]} in
    (match Backend.create_intersection_table trace ~capacity:1 with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "table on a pipeline without linked functions was accepted");
    (match Backend.create_compute_pipeline_from extra ~entry:"trace_boxes" ~interface:(ray_interface@[binding 3 Shader.Intersection_table]) ~linked:["absent_function"] () with
     | Error _ -> ()
     | Ok _ -> failwith "unknown linked function was accepted");
    let boxes_pipeline=get (Backend.create_compute_pipeline_from extra ~entry:"trace_boxes"
      ~interface:(ray_interface@[binding 3 Shader.Intersection_table]) ~linked:["sphere_hit"] ()) in
    let float_buffer label values=
      let bytes=Bytes.create (4*Array.length values) in
      Array.iteri (fun i v -> put_f32 bytes (i*4) v) values;
      let buffer=get (Backend.create_buffer device {label=Some label;size=Int64.of_int (Bytes.length bytes);usage=[Storage;Copy_dst]}) in
      get (Backend.write_buffer buffer ~offset:0L bytes); buffer in
    let spheres=float_buffer "spheres" [|0.;0.;0.;0.5; 4.;0.;0.;0.5|] in
    let boxes=float_buffer "boxes" [|-0.5;-0.5;-0.5;0.5;0.5;0.5; 3.5;-0.5;-0.5;4.5;0.5;0.5|] in
    let box_blas=get (Backend.create_accel device (Backend.Blas
      {geometries=[Backend.Bounding_boxes {boxes=[{buffer=boxes;offset=0L}];stride=24;count=2;options=Backend.default_geometry_options}];allow_refit=false})) in
    let big_scratch=get (Backend.create_buffer ~memory:Types.Device_local device
      {label=Some"scratch-extra";size=1_048_576L;usage=[Storage]}) in
    let build_one structure=
      let commands=get (Backend.begin_commands queue) in
      let encoder=get (Backend.accel_encoder commands) in
      get (Backend.build_accel encoder structure ~scratch:big_scratch ());
      get (Backend.end_accel encoder);
      poll_epoch (get (Backend.commit commands)) 1000 in
    build_one box_blas;
    let table=get (Backend.create_intersection_table boxes_pipeline ~capacity:1) in
    require (Backend.table_capacity table=1) "intersection table capacity differs";
    (match Backend.table_set_function table ~index:0 "trace_boxes" with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "unlinked function name was accepted by the table");
    (match Backend.table_set_function table ~index:1 "sphere_hit" with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "table index beyond capacity was accepted");
    get (Backend.table_set_function table ~index:0 "sphere_hit");
    get (Backend.table_set_buffer table ~index:0 spheres);
    let query_with ?extra_bytes ?table pipeline structure=
      let commands=get (Backend.begin_commands queue) in
      let compute=get (Backend.compute_encoder commands) in
      get (Backend.set_pipeline compute pipeline);
      get (Backend.set_accel compute ~index:0 structure);
      get (Backend.set_buffer compute ~index:1 rays);
      get (Backend.set_buffer compute ~index:2 hits);
      Option.iter (fun bytes -> get (Backend.set_bytes compute ~index:3 bytes)) extra_bytes;
      Option.iter (fun table -> get (Backend.set_table compute ~index:3 table)) table;
      get (Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1));
      get (Backend.end_compute compute);
      poll_epoch (get (Backend.commit commands)) 1000;
      read_hits () in
    let box_hits=query_with ~table boxes_pipeline box_blas in
    let hit0,prim0,_,t0=box_hits.(0) and hit1,prim1,_,t1=box_hits.(1) and hit2,_,_,_=box_hits.(2) and hit3,_,_,_=box_hits.(3) in
    require (hit0=1 && prim0=0 && close t0 1.5) "sphere 0 intersection differs";
    require (hit1=1 && prim1=1 && close t1 1.5) "sphere 1 intersection differs";
    require (hit2=0 && hit3=0) "bounding boxes reported false hits";
    (* Curves: one round linear segment along y at x=8 with radius 0.5, on
       devices that intersect curves; typed Unsupported elsewhere. *)
    let control=float_buffer "curve-points" [|8.;-1.;0.; 8.;1.;0.|] in
    let radii=float_buffer "curve-radii" [|0.5;0.5|] in
    let indices=get (Backend.create_buffer device {label=Some"curve-indices";size=4L;usage=[Storage;Copy_dst]}) in
    get (Backend.write_buffer indices ~offset:0L (Bytes.make 4 '\000'));
    let curve_descriptor=Backend.Blas
      {geometries=[Backend.Curves {control_points=[{buffer=control;offset=0L}];control_stride=12;control_point_count=2;
         radii=[{buffer=radii;offset=0L}];radius_stride=4;indices;index_offset=0L;segment_count=1;control_points_per_segment=2;
         curve_type=Round_curve;basis=Linear_basis;caps=Sphere_caps}];allow_refit=false} in
    let curve_pipeline=get (Backend.create_compute_pipeline_from extra ~entry:"trace_curves" ~interface:ray_interface ()) in
    let curve_blas=
      if Caps.has profile Caps.Ray_tracing_curves then begin
        let curve_blas=get (Backend.create_accel device curve_descriptor) in
        build_one curve_blas;
        let curve_hits=query_with curve_pipeline curve_blas in
        let hit0,_,_,_=curve_hits.(0) and hit2,prim2,_,t2=curve_hits.(2) and hit3,_,_,_=curve_hits.(3) in
        require (hit0=0 && hit3=0) "curve reported false hits";
        require (hit2=1 && prim2=0 && close t2 1.5)
          (Printf.sprintf "curve intersection differs: %s"
            (String.concat ";" (Array.to_list (Array.map (fun (h,p,i,t) -> Printf.sprintf "%d/%d/%d/%g" h p i t) curve_hits))));
        Some curve_blas
      end else begin
        (match Backend.create_accel device curve_descriptor with
         | Error { Error.kind = Unsupported; _ } -> ()
         | _ -> failwith "curve geometry without curve support was accepted");
        None
      end in
    (* Motion: keyframes at z=0 and z=1.5; time selects the interpolated depth. *)
    let vertices0=get (Backend.create_buffer device {label=Some"motion-0";size=72L;usage=[Storage;Copy_dst]}) in
    let vertices1=get (Backend.create_buffer device {label=Some"motion-1";size=72L;usage=[Storage;Copy_dst]}) in
    get (Backend.write_buffer vertices0 ~offset:0L (vertex_bytes 0.));
    get (Backend.write_buffer vertices1 ~offset:0L (vertex_bytes 1.5));
    let motion={Backend.keyframes=2;start_time=0.;end_time=1.;start_border=Clamp;end_border=Clamp} in
    (match Backend.create_accel device (Backend.Motion_blas
       {geometries=[Backend.Motion_triangles {keyframes=[{buffer=vertices0;offset=0L}];vertex_stride=12;vertex_count=6}];motion;allow_refit=false}) with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "keyframe count mismatch was accepted");
    let motion_blas=get (Backend.create_accel device (Backend.Motion_blas
      {geometries=[Backend.Motion_triangles {keyframes=[{buffer=vertices0;offset=0L};{buffer=vertices1;offset=0L}];vertex_stride=12;vertex_count=6}];motion;allow_refit=false})) in
    build_one motion_blas;
    let motion_pipeline=get (Backend.create_compute_pipeline_from extra ~entry:"trace_motion" ~interface:(ray_interface@[binding 3 Shader.Uniform_buffer]) ()) in
    let time_bytes t=let bytes=Bytes.create 4 in put_f32 bytes 0 t; bytes in
    List.iter (fun (time,expected) ->
      let motion_hits=query_with ~extra_bytes:(time_bytes time) motion_pipeline motion_blas in
      let hit0,prim0,_,t0=motion_hits.(0) and hit1,_,_,t1=motion_hits.(1) in
      require (hit0=1 && prim0=0 && close t0 expected && hit1=1 && close t1 expected)
        (Printf.sprintf "motion intersection at time %g differs" time)) [0.,2.;1.,0.5;0.5,1.25];
    (* User-id instances with masks over the (refitted, z=1) triangle BLAS. *)
    let identity=[|1.;0.;0.;0.; 0.;1.;0.;0.; 0.;0.;1.;0.|] in
    let shifted=[|1.;0.;0.;8.; 0.;1.;0.;0.; 0.;0.;1.;0.|] in
    let records=get (Backend.pack_instance_records device
      [|{instance={transform=identity;mask=1;structure_index=0};user_id=7;table_offset=0};
        {instance={transform=shifted;mask=2;structure_index=0};user_id=9;table_offset=0}|]) in
    require (Bytes.length records=2*Backend.instance_stride_of device User_id_instances) "user-id record stride differs";
    let record_buffer=get (Backend.create_buffer device {label=Some"user-id-instances";size=Int64.of_int (Bytes.length records);usage=[Storage;Copy_dst]}) in
    get (Backend.write_buffer record_buffer ~offset:0L records);
    let masked_tlas=get (Backend.create_accel device (Backend.Tlas_of
      {instances=record_buffer;offset=0L;instance_count=2;kind=User_id_instances;structures=[blas];allow_refit=false;motion_transforms=None})) in
    build_one masked_tlas;
    let masked_pipeline=get (Backend.create_compute_pipeline_from extra ~entry:"trace_masked" ~interface:(ray_interface@[binding 3 Shader.Uniform_buffer]) ()) in
    let mask_bytes mask=let bytes=Bytes.create 4 in Bytes.set_int32_le bytes 0 (Int32.of_int mask); bytes in
    let masked=query_with ~extra_bytes:(mask_bytes 1) masked_pipeline masked_tlas in
    let hit0,_,inst0,t0=masked.(0) and hit1,_,inst1,_=masked.(1) and hit2,_,_,_=masked.(2) and hit3,_,_,_=masked.(3) in
    require (hit0=1 && hit1=1 && inst0=7 && inst1=7 && close t0 1. && hit2=0 && hit3=0) "mask 1 selected the wrong instance";
    let masked=query_with ~extra_bytes:(mask_bytes 2) masked_pipeline masked_tlas in
    let hit0,_,_,_=masked.(0) and hit2,_,inst2,t2=masked.(2) and hit3,_,inst3,_=masked.(3) in
    require (hit0=0 && hit2=1 && hit3=1 && inst2=9 && inst3=9 && close t2 1.) "mask 2 selected the wrong instance";
    (* A refittable user-id TLAS follows its rewritten instance transforms. *)
    let moving_tlas=get (Backend.create_accel device (Backend.Tlas_of
      {instances=record_buffer;offset=0L;instance_count=2;kind=User_id_instances;structures=[blas];allow_refit=true;motion_transforms=None})) in
    build_one moving_tlas;
    let moved=get (Backend.pack_instance_records device
      [|{instance={transform=shifted;mask=1;structure_index=0};user_id=7;table_offset=0};
        {instance={transform=identity;mask=2;structure_index=0};user_id=9;table_offset=0}|]) in
    get (Backend.write_buffer record_buffer ~offset:0L moved);
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.accel_encoder commands) in
    get (Backend.refit_accel encoder moving_tlas ~scratch:big_scratch ());
    get (Backend.end_accel encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    let refitted=query_with ~extra_bytes:(mask_bytes 1) masked_pipeline moving_tlas in
    let hit0,_,_,_=refitted.(0) and hit2,_,inst2,t2=refitted.(2) in
    require (hit0=0 && hit2=1 && inst2=7 && close t2 1.) "TLAS refit did not move the user-id instance";
    get (Backend.write_buffer record_buffer ~offset:0L records);
    (* Motion instances: one instance whose transform keyframes slide it from
       the origin to x=8, so time decides which ray pair hits it. *)
    let keyframes=get (Backend.pack_transforms [|identity;shifted|]) in
    let keyframe_buffer=get (Backend.create_buffer device {label=Some"instance-keyframes";size=Int64.of_int (Bytes.length keyframes);usage=[Storage;Copy_dst]}) in
    get (Backend.write_buffer keyframe_buffer ~offset:0L keyframes);
    let motion_records=get (Backend.pack_motion_instances device
      [|{record={instance={transform=identity;mask=1;structure_index=0};user_id=5;table_offset=0};
         transforms_start=0;transforms_count=2;start_time=0.;end_time=1.;start_border=Clamp;end_border=Clamp}|]) in
    require (Bytes.length motion_records=Backend.instance_stride_of device Motion_instances) "motion instance record stride differs";
    let motion_record_buffer=get (Backend.create_buffer device {label=Some"motion-instances";size=Int64.of_int (Bytes.length motion_records);usage=[Storage;Copy_dst]}) in
    get (Backend.write_buffer motion_record_buffer ~offset:0L motion_records);
    (match Backend.create_accel device (Backend.Tlas_of
      {instances=motion_record_buffer;offset=0L;instance_count=1;kind=Motion_instances;structures=[blas];allow_refit=false;motion_transforms=None}) with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "motion instances without keyframe transforms were accepted");
    let motion_tlas=get (Backend.create_accel device (Backend.Tlas_of
      {instances=motion_record_buffer;offset=0L;instance_count=1;kind=Motion_instances;structures=[blas];allow_refit=false;
       motion_transforms=Some (keyframe_buffer,0L,2)})) in
    build_one motion_tlas;
    let motion_instances_pipeline=get (Backend.create_compute_pipeline_from extra ~entry:"trace_motion_instances" ~interface:(ray_interface@[binding 3 Shader.Uniform_buffer]) ()) in
    let at_start=query_with ~extra_bytes:(time_bytes 0.) motion_instances_pipeline motion_tlas in
    let hit0,_,inst0,t0=at_start.(0) and hit2,_,_,_=at_start.(2) in
    require (hit0=1 && inst0=5 && close t0 1. && hit2=0) "motion instance at time 0 is not at the origin";
    let at_end=query_with ~extra_bytes:(time_bytes 1.) motion_instances_pipeline motion_tlas in
    let hit0,_,_,_=at_end.(0) and hit2,_,inst2,t2=at_end.(2) in
    require (hit0=0 && hit2=1 && inst2=5 && close t2 1.) "motion instance at time 1 did not reach x=8";
    (* Compaction and copy of the triangle BLAS reproduce its hits. *)
    let size_buffer=get (Backend.create_buffer device {label=Some"compacted-size";size=8L;usage=[Storage;Copy_src]}) in
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.accel_encoder commands) in
    (match Backend.write_compacted_size encoder blas ~dst:size_buffer ~offset:4L () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "unaligned compacted size offset was accepted");
    get (Backend.write_compacted_size encoder blas ~dst:size_buffer ());
    get (Backend.end_accel encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    let compact_size=Bytes.get_int64_le (get (Backend.read_buffer size_buffer ~offset:0L ~length:8)) 0 in
    require (compact_size>0L && compact_size<=sizes.structure_size) "compacted size is out of range";
    let compacted=get (Backend.create_accel device (Backend.Sized {size=compact_size;template=blas})) in
    let copied=get (Backend.create_accel device (Backend.Sized {size=sizes.structure_size;template=blas})) in
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.accel_encoder commands) in
    (match Backend.build_accel encoder compacted ~scratch:big_scratch () with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "sized structure accepted a build");
    (match Backend.copy_accel encoder ~src:compacted ~dst:copied with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "copy from an unfilled source was accepted");
    get (Backend.compact_accel encoder ~src:blas ~dst:compacted);
    get (Backend.copy_accel encoder ~src:compacted ~dst:copied);
    (match Backend.compact_accel encoder ~src:compacted ~dst:copied with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "compacting a compacted structure was accepted");
    get (Backend.end_accel encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    List.iter (fun (name,structure) ->
      let structure_hits=query_with trace structure in
      let hit0,prim0,_,t0=structure_hits.(0) and hit1,prim1,_,t1=structure_hits.(1) and hit2,_,_,_=structure_hits.(2) in
      require (hit0=1 && prim0=0 && close t0 1. && hit1=1 && prim1=1 && close t1 1. && hit2=0)
        (name^" structure hits differ from the source")) ["compacted",compacted;"copied",copied];
    (* Visible function table: the kernel calls a linked visible function. *)
    let values=float_buffer "visible-values" [|1.;2.;3.;4.|] in
    let visible_pipeline=get (Backend.create_compute_pipeline_from extra ~entry:"call_visible"
      ~interface:[binding 0 Shader.Storage_buffer;binding 1 Shader.Visible_table] ~linked:["scale_visible"] ()) in
    let vtable=get (Backend.create_visible_table visible_pipeline ~capacity:1) in
    (match Backend.table_set_buffer vtable ~index:0 values with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "visible table accepted a buffer");
    get (Backend.table_set_function vtable ~index:0 "scale_visible");
    let commands=get (Backend.begin_commands queue) in
    let compute=get (Backend.compute_encoder commands) in
    get (Backend.set_pipeline compute visible_pipeline);
    get (Backend.set_buffer compute ~index:0 values);
    get (Backend.set_table compute ~index:1 vtable);
    get (Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1));
    get (Backend.end_compute compute);
    poll_epoch (get (Backend.commit commands)) 1000;
    let scaled=get (Backend.read_buffer values ~offset:0L ~length:16) in
    for i=0 to 3 do
      require (close (Int32.float_of_bits (Bytes.get_int32_le scaled (i*4))) (float (3*(i+1)))) "visible function output differs"
    done;
    List.iter (fun destroy -> get (destroy ())) [
      (fun () -> Backend.destroy_table vtable);(fun () -> Backend.destroy_table table);
      (fun () -> Backend.destroy_pipeline visible_pipeline);(fun () -> Backend.destroy_pipeline boxes_pipeline);
      (fun () -> Backend.destroy_pipeline curve_pipeline);(fun () -> Backend.destroy_pipeline motion_pipeline);
      (fun () -> Backend.destroy_pipeline masked_pipeline);(fun () -> Backend.destroy_pipeline motion_instances_pipeline);
      (fun () -> Backend.destroy_accel motion_tlas);(fun () -> Backend.destroy_buffer motion_record_buffer);
      (fun () -> Backend.destroy_buffer keyframe_buffer);
      (fun () -> Backend.destroy_accel copied);(fun () -> Backend.destroy_accel compacted);
      (fun () -> Backend.destroy_accel moving_tlas);(fun () -> Backend.destroy_accel masked_tlas);(fun () -> Backend.destroy_accel motion_blas);
      (fun () -> Option.fold ~none:(Ok ()) ~some:Backend.destroy_accel curve_blas);(fun () -> Backend.destroy_accel box_blas);
      (fun () -> Backend.destroy_buffer values);(fun () -> Backend.destroy_buffer size_buffer);
      (fun () -> Backend.destroy_buffer record_buffer);(fun () -> Backend.destroy_buffer vertices1);
      (fun () -> Backend.destroy_buffer vertices0);(fun () -> Backend.destroy_buffer indices);
      (fun () -> Backend.destroy_buffer radii);(fun () -> Backend.destroy_buffer control);
      (fun () -> Backend.destroy_buffer big_scratch);(fun () -> Backend.destroy_buffer boxes);
      (fun () -> Backend.destroy_buffer spheres);(fun () -> Backend.destroy_library extra)];
    (match Backend.destroy_accel blas with
     | Ok () -> ()
     | Error error -> failwith (Error.to_string error));
    get (Backend.destroy_accel tlas);
    get (Backend.destroy_buffer instance_buffer);
    get (Backend.destroy_buffer tlas_scratch);
    get (Backend.destroy_buffer scratch);
    get (Backend.destroy_pipeline trace);
    get (Backend.destroy_pipeline trace_instances);
    get (Backend.destroy_library ray_library)
  end else begin
    (match Backend.create_accel device blas_descriptor with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported acceleration structure was created");
    let commands=get (Backend.begin_commands queue) in
    (match Backend.accel_encoder commands with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported acceleration encoder was opened");
    get (Backend.abandon commands);
    let mock_library=get (Backend.create_library device ray_shader) in
    (match Backend.create_compute_pipeline_from mock_library ~entry:"trace" ~interface:ray_interface ~linked:["sphere_hit"] () with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported linked functions were accepted");
    get (Backend.destroy_library mock_library);
    require (Backend.instance_stride_of device User_id_instances=68) "user-id instance stride differs";
    require (Bytes.length (get (Backend.pack_instance_records device
      [|{instance={transform=[|1.;0.;0.;0.; 0.;1.;0.;0.; 0.;0.;1.;0.|];mask=1;structure_index=0};user_id=3;table_offset=0}|]))=68)
      "user-id instance packing differs";
    require (Backend.instance_stride_of device Motion_instances=44) "motion instance stride differs";
    require (Bytes.length (get (Backend.pack_motion_instances device
      [|{record={instance={transform=[|1.;0.;0.;0.; 0.;1.;0.;0.; 0.;0.;1.;0.|];mask=1;structure_index=0};user_id=3;table_offset=0};
         transforms_start=0;transforms_count=2;start_time=0.;end_time=1.;start_border=Clamp;end_border=Clamp}|]))=44)
      "motion instance packing differs"
  end;
  get (Backend.destroy_buffer vertices);
  get (Backend.destroy_buffer rays);
  get (Backend.destroy_buffer hits);
  get (Backend.destroy_buffer words);
  get (Backend.destroy_buffer copied);
  get (Backend.destroy_buffer local);
  (* Plan G6: heaps with aliasing, residency sets, intra-queue fences,
     timeline events, and stage-boundary timestamps. Each feature either
     behaves exactly or rejects with typed Unsupported. *)
  let expect_unsupported message=function
    | Error { Error.kind = Unsupported; _ } -> ()
    | _ -> failwith message in
  let sevens=Bytes.make 16 '\007' in
  let g6_words=get (Backend.create_buffer device {label=Some"g6-words";size=16L;usage=[Storage;Copy_src;Copy_dst]}) in
  let g6_copy=get (Backend.create_buffer device {label=Some"g6-copy";size=16L;usage=[Storage;Copy_src;Copy_dst]}) in
  let g6_library=get (Backend.create_library device (get (Shader.create
    {backend="metal";label=Some"conformance-g6";entry_points=[{name="fill";stage=Shader.Compute}];bindings=[];
     bytes=Bytes.of_string "#include <metal_stdlib>\nusing namespace metal;\nkernel void fill(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) { values[i] = i; }\n"}))) in
  let fill_interface : Shader.binding list=[{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Compute]}] in
  let alias_descriptor : Types.buffer_descriptor={label=Some"alias";size=16L;usage=[Storage;Copy_src;Copy_dst]} in
  if Caps.has profile Caps.Fences then begin
    (* A fence orders two blit encoders of one command buffer. *)
    let fence=get (Backend.create_fence device) in
    get (Backend.write_buffer g6_copy ~offset:0L (Bytes.make 16 '\000'));
    let commands=get (Backend.begin_commands queue) in
    let first=get (Backend.blit_encoder commands) in
    get (Backend.fill_buffer first g6_words ~length:16L ~value:9 ());
    get (Backend.update_fence (`Blit first) fence);
    get (Backend.end_blit first);
    (match Backend.wait_fence (`Blit first) fence with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "ended encoder accepted a fence wait");
    let second=get (Backend.blit_encoder commands) in
    get (Backend.wait_fence (`Blit second) fence);
    get (Backend.copy_buffer second ~src:g6_words ~dst:g6_copy ~length:16L ());
    get (Backend.end_blit second);
    (match Backend.destroy_fence fence with Ok () -> () | Error e -> failwith (Error.to_string e));
    poll_epoch (get (Backend.commit commands)) 1000;
    require (get (Backend.read_buffer g6_copy ~offset:0L ~length:16)=Bytes.make 16 '\009') "fenced blit order lost the fill";
    let later=get (Backend.begin_commands queue) in
    let blit=get (Backend.blit_encoder later) in
    (match Backend.update_fence (`Blit blit) fence with
     | Error { Error.kind = Stale_handle; _ } -> ()
     | _ -> failwith "destroyed fence was accepted");
    get (Backend.abandon later)
  end else expect_unsupported "unsupported fence was created" (Backend.create_fence device);
  if Caps.has profile Caps.Heaps then begin
    let placement=get (Backend.buffer_placement device 16L) in
    require (placement.placement_size>=16L && placement.placement_alignment>0L) "buffer placement is invalid";
    let heap_size=Int64.mul 4L (max placement.placement_size placement.placement_alignment) in
    (match Backend.create_heap device ~size:0L () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "empty heap was created");
    (* Untracked: the fence below is what orders the aliased buffers. *)
    let heap=get (Backend.create_heap device ~tracked:false ~label:"conformance-heap" ~size:heap_size ()) in
    require (Backend.heap_size heap=heap_size) "heap size drift";
    let a=get (Backend.create_heap_buffer heap ~offset:0L {alias_descriptor with label=Some"alias-a"}) in
    (match Backend.create_heap_buffer heap ~offset:0L {alias_descriptor with label=Some"alias-b"} with
     | Error { Error.kind = Invalid_state | Invalid_argument; _ } -> ()
     | _ -> failwith "overlapping a non-aliasable resource was accepted");
    get (Backend.make_aliasable heap (`Buffer a));
    let b=get (Backend.create_heap_buffer heap ~offset:0L {alias_descriptor with label=Some"alias-b"}) in
    (match Backend.create_heap_buffer heap ~offset:(Int64.sub heap_size 8L) alias_descriptor with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "heap buffer past the end was created");
    (match Backend.destroy_heap heap with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "heap with live resources was destroyed");
    let fence=get (Backend.create_fence device) in
    let commands=get (Backend.begin_commands queue) in
    let first=get (Backend.blit_encoder commands) in
    get (Backend.fill_buffer first b ~length:16L ~value:7 ());
    get (Backend.update_fence (`Blit first) fence);
    get (Backend.end_blit first);
    let second=get (Backend.blit_encoder commands) in
    get (Backend.wait_fence (`Blit second) fence);
    get (Backend.copy_buffer second ~src:b ~dst:g6_words ~length:16L ());
    get (Backend.end_blit second);
    poll_epoch (get (Backend.commit commands)) 1000;
    require (get (Backend.read_buffer g6_words ~offset:0L ~length:16)=sevens) "aliased heap buffer lost its fill";
    if Caps.has profile Caps.Compute_pipeline then begin
      (* The fill kernel writes through [a] after [compute_use_heap]; [b] reads it. *)
      let fill=get (Backend.create_compute_pipeline_from g6_library ~entry:"fill" ~interface:fill_interface ()) in
      let commands=get (Backend.begin_commands queue) in
      let compute=get (Backend.compute_encoder commands) in
      get (Backend.compute_use_heap compute heap);
      get (Backend.set_pipeline compute fill);
      get (Backend.set_buffer compute ~index:0 b);
      get (Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1));
      get (Backend.update_fence (`Compute compute) fence);
      get (Backend.end_compute compute);
      let blit=get (Backend.blit_encoder commands) in
      get (Backend.wait_fence (`Blit blit) fence);
      get (Backend.copy_buffer blit ~src:b ~dst:g6_words ~length:16L ());
      get (Backend.end_blit blit);
      poll_epoch (get (Backend.commit commands)) 1000;
      let filled=get (Backend.read_buffer g6_words ~offset:0L ~length:16) in
      for i=0 to 3 do require (Bytes.get_int32_le filled (i*4)=Int32.of_int i) "compute through an aliased heap buffer differs" done;
      get (Backend.destroy_pipeline fill)
    end;
    (* A heap texture round-trips through encoded blits. *)
    let texture_descriptor : Types.texture_descriptor=
      {label=Some"heap-texture";width=2;height=2;depth=1;mip_levels=1;sample_count=1;usage=[Texture_copy_src;Texture_copy_dst]} in
    let texture_placement=get (Backend.texture_placement device texture_descriptor) in
    require (texture_placement.placement_size>=16L) "texture placement is too small";
    let texture_heap=get (Backend.create_heap device ~size:(Int64.mul 2L (max texture_placement.placement_size texture_placement.placement_alignment)) ()) in
    let texture=get (Backend.create_heap_texture texture_heap ~offset:0L texture_descriptor) in
    (* Rows are 256-byte aligned in staging buffers; two texels per row. *)
    let staging_in=get (Backend.create_buffer device {label=Some"g6-stage-in";size=512L;usage=[Copy_src]}) in
    let staging_out=get (Backend.create_buffer device {label=Some"g6-stage-out";size=512L;usage=[Copy_dst]}) in
    let pattern=Bytes.init 512 (fun i -> Char.chr ((i * 7 + 3) land 0xff)) in
    get (Backend.write_buffer staging_in ~offset:0L pattern);
    let commands=get (Backend.begin_commands queue) in
    let blit=get (Backend.blit_encoder commands) in
    get (Backend.buffer_to_texture blit ~src:staging_in ~bytes_per_row:256L ~bytes_per_image:512L ~dst:texture ~extent:{width=2;height=2;depth=1} ());
    get (Backend.texture_to_buffer blit ~src:texture ~extent:{width=2;height=2;depth=1} ~dst:staging_out ~bytes_per_row:256L ~bytes_per_image:512L ());
    get (Backend.end_blit blit);
    poll_epoch (get (Backend.commit commands)) 1000;
    let downloaded=get (Backend.read_buffer staging_out ~offset:0L ~length:512) in
    List.iter (fun row -> require (Bytes.sub downloaded (row*256) 8=Bytes.sub pattern (row*256) 8) "heap texture blit round trip differs") [0;1];
    get (Backend.destroy_buffer staging_in);
    get (Backend.destroy_buffer staging_out);
    if Caps.has profile Caps.Residency_sets then begin
      let set=get (Backend.create_residency_set device ~capacity:4 ~label:"conformance-residency" ()) in
      get (Backend.residency_add set (`Heap heap));
      get (Backend.residency_add set (`Buffer g6_words));
      get (Backend.residency_add set (`Texture texture));
      get (Backend.residency_commit set);
      require (get (Backend.residency_size set)>=heap_size) "residency size omits the heap";
      get (Backend.queue_add_residency queue set);
      let commands=get (Backend.begin_commands queue) in
      get (Backend.use_residency commands set);
      let blit=get (Backend.blit_encoder commands) in
      get (Backend.copy_buffer blit ~src:b ~dst:g6_words ~length:16L ());
      get (Backend.end_blit blit);
      poll_epoch (get (Backend.commit commands)) 1000;
      get (Backend.queue_remove_residency queue set);
      get (Backend.residency_remove set (`Texture texture));
      get (Backend.residency_remove set (`Buffer g6_words));
      get (Backend.residency_remove set (`Heap heap));
      get (Backend.residency_commit set);
      get (Backend.destroy_residency_set set);
      (match Backend.residency_add set (`Heap heap) with
       | Error { Error.kind = Stale_handle; _ } -> ()
       | _ -> failwith "destroyed residency set accepted an allocation")
    end else expect_unsupported "unsupported residency set was created" (Backend.create_residency_set device ());
    get (Backend.destroy_texture texture);
    get (Backend.destroy_heap texture_heap);
    get (Backend.destroy_buffer a);
    get (Backend.destroy_buffer b);
    get (Backend.destroy_fence fence);
    get (Backend.destroy_heap heap);
    (match Backend.create_heap_buffer heap ~offset:0L alias_descriptor with
     | Error { Error.kind = Stale_handle; _ } -> ()
     | _ -> failwith "destroyed heap created a buffer")
  end else begin
    expect_unsupported "unsupported heap was created" (Backend.create_heap device ~size:4096L ());
    expect_unsupported "unsupported buffer placement was answered" (Backend.buffer_placement device 16L);
    expect_unsupported "unsupported residency set was created" (Backend.create_residency_set device ())
  end;
  if Caps.has profile Caps.Event_synchronization then begin
    let event=get (Backend.create_event device) in
    require (get (Backend.event_value event)=0L) "new event is not zero";
    get (Backend.signal_event event 2L);
    require (get (Backend.event_value event)=2L) "host signal was lost";
    (match Backend.signal_event event 1L with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "event value decreased");
    require (get (Backend.wait_event event ~value:2L ~timeout_ms:10)) "reached value did not satisfy the host wait";
    require (not (get (Backend.wait_event event ~value:3L ~timeout_ms:10))) "unreached value satisfied the host wait";
    (* The GPU holds the copy until the host signals 3, then signals 4. *)
    get (Backend.write_buffer g6_copy ~offset:0L (Bytes.make 16 '\000'));
    get (Backend.write_buffer g6_words ~offset:0L sevens);
    let commands=get (Backend.begin_commands queue) in
    get (Backend.commands_wait_event commands event 3L);
    let blit=get (Backend.blit_encoder commands) in
    (match Backend.commands_signal_event commands event 4L with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "event signal was accepted inside an open encoder");
    get (Backend.copy_buffer blit ~src:g6_words ~dst:g6_copy ~length:16L ());
    get (Backend.end_blit blit);
    get (Backend.commands_signal_event commands event 4L);
    let receipt=get (Backend.commit commands) in
    require (not (get (Backend.wait_event event ~value:4L ~timeout_ms:20))) "GPU signalled before the host released it";
    get (Backend.signal_event event 3L);
    require (get (Backend.wait_event event ~value:4L ~timeout_ms:2000)) "GPU signal never arrived";
    poll_epoch receipt 1000;
    require (get (Backend.read_buffer g6_copy ~offset:0L ~length:16)=sevens) "event-gated copy did not run";
    let negative=get (Backend.begin_commands queue) in
    (match Backend.commands_wait_event negative event (-1L) with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "negative event value was accepted");
    get (Backend.abandon negative);
    get (Backend.destroy_event event);
    (match Backend.event_value event with
     | Error { Error.kind = Stale_handle; _ } -> ()
     | _ -> failwith "destroyed event was readable")
  end else expect_unsupported "unsupported event was created" (Backend.create_event device);
  if Caps.has profile Caps.Timestamp_queries then begin
    let stamps=get (Backend.create_timestamps device ~count:4) in
    require (Backend.timestamps_count stamps=4) "timestamp count drift";
    let reference=get (Backend.timestamp_reference device) in
    require (reference.gpu_frequency>0L && reference.cpu_nanoseconds>0L) "timestamp reference is empty";
    let resolved=get (Backend.create_buffer device {label=Some"stamps";size=32L;usage=[Storage;Copy_dst]}) in
    let equal=get (Backend.begin_commands queue) in
    (match Backend.blit_encoder ~timestamps:(stamps,1,1) equal with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "equal timestamp indices were accepted");
    get (Backend.abandon equal);
    let commands=get (Backend.begin_commands queue) in
    let blit=get (Backend.blit_encoder ~timestamps:(stamps,0,1) commands) in
    get (Backend.fill_buffer blit g6_words ~length:16L ~value:1 ());
    get (Backend.end_blit blit);
    let resolve=get (Backend.blit_encoder commands) in
    (match Backend.resolve_timestamps resolve stamps ~count:5 ~dst:resolved () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "timestamp range past the end was accepted");
    (match Backend.resolve_timestamps resolve stamps ~count:2 ~dst:resolved ~offset:4L () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "unaligned timestamp destination was accepted");
    get (Backend.resolve_timestamps resolve stamps ~count:2 ~dst:resolved ());
    get (Backend.end_blit resolve);
    poll_epoch (get (Backend.commit commands)) 1000;
    let bytes=get (Backend.read_buffer resolved ~offset:0L ~length:16) in
    let t0=Bytes.get_int64_le bytes 0 and t1=Bytes.get_int64_le bytes 8 in
    require (t0>0L && t1>=t0) "blit stage timestamps are not ordered";
    let host=get (Backend.read_timestamps stamps ~count:2 ()) in
    require (host=[|t0;t1|]) "host-resolved timestamps differ from the GPU resolve";
    if Caps.has profile Caps.Compute_pipeline then begin
      let fill=get (Backend.create_compute_pipeline_from g6_library ~entry:"fill" ~interface:fill_interface ()) in
      let commands=get (Backend.begin_commands queue) in
      let compute=get (Backend.compute_encoder ~timestamps:(stamps,2,3) commands) in
      get (Backend.set_pipeline compute fill);
      get (Backend.set_buffer compute ~index:0 g6_words);
      get (Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1));
      get (Backend.end_compute compute);
      poll_epoch (get (Backend.commit commands)) 1000;
      let later=get (Backend.read_timestamps stamps ~first:2 ~count:2 ()) in
      require (later.(1)>=later.(0) && later.(0)>=t1) "compute stage timestamps are not ordered after the blit";
      get (Backend.destroy_pipeline fill)
    end;
    get (Backend.destroy_buffer resolved);
    get (Backend.destroy_timestamps stamps);
    (match Backend.read_timestamps stamps ~count:1 () with
     | Error { Error.kind = Stale_handle; _ } -> ()
     | _ -> failwith "destroyed timestamps were readable")
  end else begin
    expect_unsupported "unsupported timestamps were created" (Backend.create_timestamps device ~count:2);
    expect_unsupported "unsupported timestamp reference was answered" (Backend.timestamp_reference device)
  end;
  get (Backend.destroy_library g6_library);
  get (Backend.destroy_buffer g6_words);
  get (Backend.destroy_buffer g6_copy);
  (* Render path: samplers, portable render pipelines, the render encoder
     with exact pixels, batched draws, indirect command buffers, argument
     buffers, depth load/clear, and encoded texture blits. *)
  let sampler_descriptor : Types.sampler_descriptor=
    {label=Some"conformance-sampler";min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;
     address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1} in
  let sampler=get (Backend.create_sampler device sampler_descriptor) in
  require (Backend.sampler_descriptor sampler=sampler_descriptor) "sampler descriptor drift";
  let render_source=Bytes.of_string
    "#include <metal_stdlib>\nusing namespace metal;\nstruct V { float4 position [[position]]; float2 uv; };\nvertex V flat_vertex(uint i [[vertex_id]], const device float *offsets [[buffer(0)]]) { float2 p[3]={{-1.,-1.},{3.,-1.},{-1.,3.}}; V v; v.position=float4(p[i]+float2(offsets[0],offsets[1]),0.,1.); v.uv=(p[i]+1.)*.5; return v; }\nfragment float4 flat_fragment(V v [[stage_in]], constant float4 &color [[buffer(1)]]) { return color; }\nstruct Args { texture2d<float, access::sample> image [[id(0)]]; sampler sampling [[id(1)]]; };\nfragment float4 argument_fragment(V v [[stage_in]], constant Args &args [[buffer(1)]]) { return args.image.sample(args.sampling, v.uv); }\nfragment float4 textured_fragment(V v [[stage_in]], texture2d<float> image [[texture(1)]], sampler sampling [[sampler(2)]]) { return image.sample(sampling, v.uv); }\n" in
  let render_shader entries bindings=get (Shader.create
    {backend="metal";label=Some"conformance-render";bytes=render_source;entry_points=entries;bindings}) in
  let vertex=render_shader [{name="flat_vertex";stage=Shader.Vertex}]
    [{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Vertex]}] in
  let fragment_flat=render_shader [{name="flat_fragment";stage=Shader.Fragment}]
    [{group=0;binding=1;kind=Shader.Uniform_buffer;visibility=[Shader.Fragment]}] in
  let fragment_argument=render_shader [{name="argument_fragment";stage=Shader.Fragment}]
    [{group=0;binding=1;kind=Shader.Storage_buffer;visibility=[Shader.Fragment]}] in
  let fragment_textured=render_shader [{name="textured_fragment";stage=Shader.Fragment}]
    [{group=0;binding=1;kind=Shader.Sampled_texture;visibility=[Shader.Fragment]};
     {group=0;binding=2;kind=Shader.Sampler;visibility=[Shader.Fragment]}] in
  let render_layout entries=
    let group=get (Binding.create_layout entries) in
    get (Binding.create_pipeline_layout ~device:(Backend.device_handle device) ~capabilities [0,group]) in
  let vertex_entry : Binding.layout_entry={binding=0;kind=Binding.Buffer;visibility=[Binding.Vertex]} in
  let flat_layout=render_layout [vertex_entry;{binding=1;kind=Binding.Buffer;visibility=[Binding.Fragment]}] in
  let textured_layout=render_layout
    [vertex_entry;{binding=1;kind=Binding.Texture;visibility=[Binding.Fragment]};
     {binding=2;kind=Binding.Sampler;visibility=[Binding.Fragment]}] in
  let render_descriptor ?(layout=flat_layout) fragment entry : Pipeline.render_descriptor=
    {backend="metal";label=Some"conformance-render";layout;vertex;vertex_entry="flat_vertex";
     fragment=Some fragment;fragment_entry=Some entry;color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1} in
  let target_descriptor : Types.texture_descriptor=
    {label=Some"render-target";width=4;height=4;depth=1;mip_levels=1;sample_count=1;
     usage=[Texture_binding;Render_attachment;Texture_copy_src]} in
  let target=get (Backend.create_texture device target_descriptor) in
  let offsets=get (Backend.create_buffer device {label=Some"offsets";size=8L;usage=[Storage]}) in
  get (Backend.write_buffer offsets ~offset:0L (Bytes.make 8 '\000'));
  let color_bytes r g b a=let bytes=Bytes.create 16 in
    List.iteri (fun i v->Bytes.set_int32_le bytes (i*4) (Int32.bits_of_float v)) [r;g;b;a]; bytes in
  let pixel bytes x y=Bytes.sub_string bytes ((y*4+x)*4) 4 in
  let expect_pixels expected message=
    let pixels=get (Backend.read_texture target ~bytes_per_row:16) in
    require (pixel pixels 0 0=expected && pixel pixels 3 3=expected) message in
  let clear_target r g b a=
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Clear;store=Store;clear=(r,g,b,a)}];depth=None;stencil=None}) in
    get (Backend.end_render encoder);
    poll_epoch (get (Backend.commit commands)) 1000 in
  if Caps.has profile Caps.Render_pipeline then begin
    let flat=get (Backend.create_render_pipeline device (render_descriptor fragment_flat "flat_fragment")) in
    clear_target 0.125 0.25 0.5 1.;
    expect_pixels "\x20\x40\x80\xff" "clear-only render pass pixels differ";
    (* One full-screen triangle through the immediate encoder with inline
       fragment bytes. *)
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Load;store=Store;clear=(0.,0.,0.,0.)}];depth=None;stencil=None}) in
    (match Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 () with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "draw without a render pipeline was accepted");
    get (Backend.set_render_pipeline encoder flat);
    get (Backend.set_stage_buffer encoder Vertex ~index:0 offsets);
    get (Backend.set_stage_bytes encoder Fragment ~index:1 (color_bytes 1. 0. 0.5 1.));
    get (Backend.set_viewport encoder {x=0;y=0;width=4;height=4});
    get (Backend.set_scissor encoder {x=0;y=0;width=4;height=4});
    get (Backend.set_cull encoder Cull_none);
    get (Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 ());
    get (Backend.end_render encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    expect_pixels "\xff\x00\x80\xff" "immediate triangle pixels differ";
    (* The same triangle as one indexed batch draw. *)
    let indices=get (Backend.create_buffer device {label=Some"indices";size=12L;usage=[Index]}) in
    let index_bytes=Bytes.create 12 in
    List.iteri (fun i v->Bytes.set_int32_le index_bytes (i*4) v) [0l;1l;2l];
    get (Backend.write_buffer indices ~offset:0L index_bytes);
    let color=get (Backend.create_buffer device {label=Some"color";size=16L;usage=[Uniform]}) in
    get (Backend.write_buffer color ~offset:0L (color_bytes 0. 1. 0. 1.));
    clear_target 0. 0. 0. 1.;
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Load;store=Store;clear=(0.,0.,0.,0.)}];depth=None;stencil=None}) in
    get (Backend.set_viewport encoder {x=0;y=0;width=4;height=4});
    get (Backend.draw_batch encoder
      [|{pipeline=flat;buffers=[|Vertex,0,offsets,0L;Fragment,1,color,0L|];primitive=Triangle_list;
         index=Some (Uint32,indices,0L,3L);vertex_start=0;vertex_count=3;instances=1}|]);
    get (Backend.end_render encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    expect_pixels "\x00\xff\x00\xff" "batched indexed triangle pixels differ";
    (* Indirect command buffer: one recorded draw, executed twice. *)
    let indirect=get (Backend.create_render_pipeline ~indirect:true device (render_descriptor fragment_flat "flat_fragment")) in
    let icb=get (Backend.create_icb device ~max_commands:2) in
    (match Backend.icb_set_pipeline icb ~index:2 indirect with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "out-of-range indirect command index was accepted");
    get (Backend.write_buffer color ~offset:0L (color_bytes 0. 0. 1. 1.));
    get (Backend.icb_set_pipeline icb ~index:0 indirect);
    get (Backend.icb_set_buffer icb ~index:0 Vertex ~slot:0 offsets);
    get (Backend.icb_set_buffer icb ~index:0 Fragment ~slot:1 color);
    get (Backend.icb_draw_indexed icb ~index:0 ~primitive:Triangle_list ~index_type:Uint32 indices ~offset:0L ~count:3L ());
    clear_target 0. 0. 0. 1.;
    for _=1 to 2 do
      let commands=get (Backend.begin_commands queue) in
      let encoder=get (Backend.render_encoder commands
        {colors=[{texture=target;resolve=None;load=Load;store=Store;clear=(0.,0.,0.,0.)}];depth=None;stencil=None}) in
      get (Backend.set_viewport encoder {x=0;y=0;width=4;height=4});
      (match Backend.execute_icb encoder icb ~location:0 ~length:1 with
       | Error { Error.kind = Invalid_state; _ } -> ()
       | _ -> failwith "indirect execution without a pipeline was accepted");
      get (Backend.set_render_pipeline encoder indirect);
      get (Backend.use_resources encoder [`Buffer offsets;`Buffer color;`Buffer indices]);
      get (Backend.execute_icb encoder icb ~location:0 ~length:1);
      get (Backend.end_render encoder);
      poll_epoch (get (Backend.commit commands)) 1000
    done;
    expect_pixels "\x00\x00\xff\xff" "indirect command pixels differ";
    (* Argument buffer: a 1x1 texture and sampler bound through one buffer. *)
    let argument_pipeline=get (Backend.create_render_pipeline ~indirect:true device
      (render_descriptor fragment_argument "argument_fragment")) in
    let argument=get (Backend.create_argument argument_pipeline Fragment ~index:1) in
    require (Backend.argument_length argument>0) "argument length is empty";
    let argument_buffer=get (Backend.create_buffer device
      {label=Some"arguments";size=Int64.of_int (max 256 (Backend.argument_length argument));usage=[Storage]}) in
    let texel=get (Backend.create_texture device
      {label=Some"texel";width=1;height=1;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Texture_copy_dst]}) in
    let texel_upload=get (Backend.create_buffer device {label=Some"texel-upload";size=256L;usage=[Copy_src]}) in
    get (Backend.write_buffer texel_upload ~offset:0L (Bytes.init 256 (fun i->if i<4 then "\x40\x80\xc0\xff".[i] else '\000')));
    let commands=get (Backend.begin_commands queue) in
    let blit=get (Backend.blit_encoder commands) in
    get (Backend.buffer_to_texture blit ~src:texel_upload ~bytes_per_row:256L ~bytes_per_image:256L ~dst:texel
      ~extent:{width=1;height=1;depth=1} ());
    get (Backend.end_blit blit);
    poll_epoch (get (Backend.commit commands)) 1000;
    get (Backend.argument_texture argument argument_buffer ~offset:0L ~slot:0 texel);
    get (Backend.argument_sampler argument argument_buffer ~offset:0L ~slot:1 sampler);
    clear_target 0. 0. 0. 1.;
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Load;store=Store;clear=(0.,0.,0.,0.)}];depth=None;stencil=None}) in
    get (Backend.set_viewport encoder {x=0;y=0;width=4;height=4});
    get (Backend.set_render_pipeline encoder argument_pipeline);
    get (Backend.set_stage_buffer encoder Vertex ~index:0 offsets);
    get (Backend.set_stage_buffer encoder Fragment ~index:1 argument_buffer);
    get (Backend.use_resources encoder [`Texture texel]);
    get (Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 ());
    get (Backend.end_render encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    expect_pixels "\x40\x80\xc0\xff" "argument-buffer sampled pixels differ";
    (* Direct texture and sampler binding. *)
    let textured=get (Backend.create_render_pipeline device (render_descriptor ~layout:textured_layout fragment_textured "textured_fragment")) in
    clear_target 0. 0. 0. 1.;
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Load;store=Store;clear=(0.,0.,0.,0.)}];depth=None;stencil=None}) in
    get (Backend.set_viewport encoder {x=0;y=0;width=4;height=4});
    get (Backend.set_render_pipeline encoder textured);
    get (Backend.set_stage_buffer encoder Vertex ~index:0 offsets);
    get (Backend.set_stage_texture encoder Fragment ~index:1 texel);
    get (Backend.set_stage_sampler encoder Fragment ~index:2 sampler);
    get (Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 ());
    get (Backend.end_render encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    expect_pixels "\x40\x80\xc0\xff" "directly sampled pixels differ";
    (* Depth: a cleared depth attachment at 0.25 with Less rejects a triangle
       at z=0.5 when loaded, and admits it after a clear to 1. *)
    let depth_descriptor : Types.texture_descriptor=
      {label=Some"depth";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment]} in
    let depth=get (Backend.create_depth_texture device depth_descriptor) in
    let depth_shader=render_shader [{name="flat_vertex";stage=Shader.Vertex}]
      [{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Vertex]}] in
    let depth_pipeline=get (Backend.create_render_pipeline device
      {(render_descriptor fragment_flat "flat_fragment") with vertex=depth_shader;depth_format=Depth32_float}) in
    let render_depth ~load ~clear expected message=
      clear_target 0. 0. 0. 1.;
      let commands=get (Backend.begin_commands queue) in
      let encoder=get (Backend.render_encoder commands
        {colors=[{texture=target;resolve=None;load=Load;store=Store;clear=(0.,0.,0.,0.)}];
         depth=Some {depth_texture=depth;depth_load=load;depth_store=Store;depth_clear=clear};stencil=None}) in
      get (Backend.set_viewport encoder {x=0;y=0;width=4;height=4});
      get (Backend.set_render_pipeline encoder depth_pipeline);
      get (Backend.set_depth_state encoder (Some {depth_compare=Less;depth_write=true;stencil=None}));
      get (Backend.set_stage_buffer encoder Vertex ~index:0 offsets);
      get (Backend.set_stage_bytes encoder Fragment ~index:1 (color_bytes 1. 1. 0. 1.));
      get (Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 ());
      get (Backend.end_render encoder);
      poll_epoch (get (Backend.commit commands)) 1000;
      expect_pixels expected message in
    render_depth ~load:Clear ~clear:1. "\xff\xff\x00\xff" "depth clear-to-far rejected the triangle";
    render_depth ~load:Clear ~clear:0. "\x00\x00\x00\xff" "depth clear-to-near admitted the triangle";
    render_depth ~load:Load ~clear:1. "\x00\x00\x00\xff" "depth load ignored the retained near depth";
    (* Encoded texture copy into a second target. *)
    let copy_target=get (Backend.create_texture device
      {target_descriptor with label=Some"copy-target";usage=[Texture_binding;Texture_copy_src;Texture_copy_dst]}) in
    clear_target 0.5 0.25 0.125 1.;
    let commands=get (Backend.begin_commands queue) in
    let blit=get (Backend.blit_encoder commands) in
    get (Backend.copy_texture blit ~src:target ~dst:copy_target ~extent:{width=4;height=4;depth=1} ());
    get (Backend.end_blit blit);
    poll_epoch (get (Backend.commit commands)) 1000;
    require (get (Backend.read_texture copy_target ~bytes_per_row:16)=get (Backend.read_texture target ~bytes_per_row:16))
      "encoded texture copy differs";
    get (Backend.destroy_texture copy_target);
    (* Render passes sample timestamps at their stage boundaries and take
       part in fences and heap residency like the other encoders. *)
    if Caps.has profile Caps.Timestamp_queries && Caps.has profile Caps.Fences then begin
      let stamps=get (Backend.create_timestamps device ~count:2) in
      let fence=get (Backend.create_fence device) in
      let commands=get (Backend.begin_commands queue) in
      let encoder=get (Backend.render_encoder ~timestamps:(stamps,0,1) commands
        {colors=[{texture=target;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}];depth=None;stencil=None}) in
      get (Backend.wait_fence (`Render encoder) fence);
      get (Backend.set_render_pipeline encoder flat);
      get (Backend.set_stage_buffer encoder Vertex ~index:0 offsets);
      get (Backend.set_stage_bytes encoder Fragment ~index:1 (color_bytes 0. 1. 0. 1.));
      get (Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 ());
      get (Backend.update_fence (`Render encoder) fence);
      get (Backend.end_render encoder);
      poll_epoch (get (Backend.commit commands)) 1000;
      expect_pixels "\x00\xff\x00\xff" "timestamped render pass lost its pixels";
      let stamped=get (Backend.read_timestamps stamps ~count:2 ()) in
      require (stamped.(0)>0L && stamped.(1)>=stamped.(0)) "render stage timestamps are not ordered";
      get (Backend.destroy_fence fence);
      get (Backend.destroy_timestamps stamps)
    end;
    get (Backend.destroy_texture depth);
    get (Backend.destroy_pipeline depth_pipeline);
    get (Backend.destroy_pipeline textured);
    get (Backend.destroy_argument argument);
    get (Backend.destroy_buffer argument_buffer);
    get (Backend.destroy_buffer texel_upload);
    get (Backend.destroy_texture texel);
    get (Backend.destroy_pipeline argument_pipeline);
    get (Backend.destroy_icb icb);
    get (Backend.destroy_pipeline indirect);
    get (Backend.destroy_buffer color);
    get (Backend.destroy_buffer indices);
    get (Backend.destroy_pipeline flat)
  end else begin
    (match Backend.create_render_pipeline device (render_descriptor fragment_flat "flat_fragment") with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported render pipeline was created");
    (match Backend.create_icb device ~max_commands:1 with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported indirect command buffer was created");
    let commands=get (Backend.begin_commands queue) in
    (match Backend.render_encoder commands
       {colors=[{texture=target;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}];depth=None;stencil=None} with
     | Error { Error.kind = Unsupported; _ } -> ()
     | _ -> failwith "unsupported render encoder was opened");
    get (Backend.abandon commands)
  end;
  (* Plan G7: mesh and tile pipelines, dynamic libraries, binary archives,
     sparse textures with tile mapping, and MetalFX upscaling. Each feature
     either behaves exactly or rejects with typed Unsupported. *)
  let g7_target : Types.texture_descriptor=
    {label=Some"g7-target";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Render_attachment;Texture_copy_src]} in
  let g7_pixels target=get (Backend.read_texture target ~bytes_per_row:16) in
  let g7_pixel bytes x y=Bytes.sub_string bytes ((y*4+x)*4) 4 in
  if Caps.has profile Caps.Mesh_shaders then begin
    let source=Bytes.of_string (String.concat "\n" [
      "#include <metal_stdlib>";"using namespace metal;";
      "struct V { float4 position [[position]]; };";
      "using Tri = mesh<V, void, 3, 1, topology::triangle>;";
      "struct Payload { float shift; };";
      "[[object]] void shift_object(object_data Payload &payload [[payload]], mesh_grid_properties grid, uint tid [[thread_index_in_threadgroup]]) {";
      "  if (tid == 0) { payload.shift = 0.0f; grid.set_threadgroups_per_grid(uint3(1, 1, 1)); } }";
      "[[mesh]] void fullscreen_mesh(Tri out, const object_data Payload &payload [[payload]], uint tid [[thread_index_in_threadgroup]]) {";
      "  constexpr float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};";
      "  if (tid < 3) { V v; v.position = float4(p[tid] + float2(payload.shift, 0.0f), 0, 1); out.set_vertex(tid, v); out.set_index(tid, tid); }";
      "  if (tid == 0) out.set_primitive_count(1); }";
      "fragment float4 blue_fragment() { return float4(0.0, 0.0, 1.0, 1.0); }"]) in
    let shader=get (Shader.create {backend="metal";label=Some"conformance-mesh";bytes=source;entry_points=[];bindings=[]}) in
    let library=get (Backend.create_library device shader) in
    let descriptor : Backend.mesh_descriptor=
      {mesh_label=Some"conformance-mesh";mesh_library=library;object_entry=Some"shift_object";mesh_entry="fullscreen_mesh";
       mesh_fragment_entry="blue_fragment";mesh_color_format=Rgba8_unorm;mesh_threadgroup=(3,1,1);object_threadgroup=Some (1,1,1)} in
    (match Backend.create_mesh_pipeline device {descriptor with object_threadgroup=None} with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "object entry without an object threadgroup was accepted");
    (match Backend.create_mesh_pipeline device {descriptor with mesh_entry="missing"} with
     | Error _ -> ()
     | Ok _ -> failwith "missing mesh entry was accepted");
    let mesh=get (Backend.create_mesh_pipeline device descriptor) in
    let target=get (Backend.create_texture device g7_target) in
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}];depth=None;stencil=None}) in
    (match Backend.draw_mesh encoder ~threadgroups:(1,1,1) ~mesh_threadgroup:(3,1,1) () with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "mesh draw without a mesh pipeline was accepted");
    get (Backend.set_render_pipeline encoder mesh);
    (match Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 () with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "vertex draw on a mesh pipeline was accepted");
    (match Backend.draw_mesh encoder ~threadgroups:(1,1,1) ~mesh_threadgroup:(2,1,1) ~object_threadgroup:(1,1,1) () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "mesh threadgroup differing from the compiled size was accepted");
    get (Backend.draw_mesh encoder ~threadgroups:(1,1,1) ~object_threadgroup:(1,1,1) ~mesh_threadgroup:(3,1,1) ());
    get (Backend.end_render encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    let pixels=g7_pixels target in
    require (g7_pixel pixels 0 0="\x00\x00\xff\xff" && g7_pixel pixels 3 3="\x00\x00\xff\xff") "mesh pipeline did not draw the full-screen triangle";
    get (Backend.destroy_texture target);
    get (Backend.destroy_pipeline mesh);
    get (Backend.destroy_library library)
  end else begin
    let shader=get (Shader.create {backend="metal";label=Some"conformance-mesh";bytes=Bytes.of_string"kernel void k() {}";entry_points=[];bindings=[]}) in
    let library=get (Backend.create_library device shader) in
    expect_unsupported "unsupported mesh pipeline was created" (Backend.create_mesh_pipeline device
      {mesh_label=None;mesh_library=library;object_entry=None;mesh_entry="m";mesh_fragment_entry="f";mesh_color_format=Rgba8_unorm;mesh_threadgroup=(1,1,1);object_threadgroup=None});
    get (Backend.destroy_library library)
  end;
  if Caps.has profile Caps.Tile_shaders && Caps.has profile Caps.Render_pipeline then begin
    (* A flat draw paints green; the tile kernel then inverts the imageblock. *)
    let source=Bytes.of_string (String.concat "\n" [
      "#include <metal_stdlib>";"using namespace metal;";
      "struct Pixel { half4 color [[color(0)]]; };";
      "kernel void invert_tile(imageblock<Pixel, imageblock_layout_implicit> block, ushort2 tid [[thread_position_in_threadgroup]]) {";
      "  Pixel p = block.read(tid); half4 c = p.color; p.color = half4(1.0h - c.r, 1.0h - c.g, 1.0h - c.b, 1.0h); block.write(p, tid); }"]) in
    let shader=get (Shader.create {backend="metal";label=Some"conformance-tile";bytes=source;entry_points=[];bindings=[]}) in
    let library=get (Backend.create_library device shader) in
    let target=get (Backend.create_texture device g7_target) in
    let probe=get (Backend.begin_commands queue) in
    let probe_encoder=get (Backend.render_encoder probe
      {colors=[{texture=target;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}];depth=None;stencil=None}) in
    let tile_width,tile_height=get (Backend.tile_size probe_encoder) in
    require (tile_width>=4 && tile_height>=4) "tile size is smaller than the target";
    get (Backend.end_render probe_encoder);
    get (Backend.abandon probe);
    let descriptor : Backend.tile_descriptor=
      {tile_label=Some"conformance-tile";tile_library=library;tile_entry="invert_tile";tile_color_format=Rgba8_unorm;tile_threadgroup=(tile_width,tile_height,1)} in
    (match Backend.create_tile_pipeline device {descriptor with tile_threadgroup=(2,2,2)} with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "tile threadgroup with depth two was accepted");
    let tile=get (Backend.create_tile_pipeline device descriptor) in
    let flat=get (Backend.create_render_pipeline device (render_descriptor fragment_flat "flat_fragment")) in
    let commands=get (Backend.begin_commands queue) in
    let encoder=get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,1.)}];depth=None;stencil=None}) in
    get (Backend.set_render_pipeline encoder flat);
    get (Backend.set_stage_buffer encoder Vertex ~index:0 offsets);
    get (Backend.set_stage_bytes encoder Fragment ~index:1 (color_bytes 0. 1. 0. 1.));
    get (Backend.draw encoder ~primitive:Triangle_list ~first:0 ~count:3 ());
    (match Backend.dispatch_tile encoder ~threads:(tile_width,tile_height,1) with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "tile dispatch on a vertex pipeline was accepted");
    get (Backend.set_render_pipeline encoder tile);
    (match Backend.dispatch_tile encoder ~threads:(2,2,1) with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "tile threads differing from the compiled size were accepted");
    get (Backend.dispatch_tile encoder ~threads:(tile_width,tile_height,1));
    get (Backend.end_render encoder);
    poll_epoch (get (Backend.commit commands)) 1000;
    let pixels=g7_pixels target in
    require (g7_pixel pixels 0 0="\xff\x00\xff\xff" && g7_pixel pixels 3 3="\xff\x00\xff\xff") "tile kernel did not invert the imageblock";
    get (Backend.destroy_pipeline flat);
    get (Backend.destroy_pipeline tile);
    get (Backend.destroy_texture target);
    get (Backend.destroy_library library)
  end else if not (Caps.has profile Caps.Tile_shaders) then begin
    let shader=get (Shader.create {backend="metal";label=Some"conformance-tile";bytes=Bytes.of_string"kernel void k() {}";entry_points=[];bindings=[]}) in
    let library=get (Backend.create_library device shader) in
    expect_unsupported "unsupported tile pipeline was created" (Backend.create_tile_pipeline device
      {tile_label=None;tile_library=library;tile_entry="t";tile_color_format=Rgba8_unorm;tile_threadgroup=(1,1,1)});
    get (Backend.destroy_library library)
  end;
  let fill_kernel name body=Bytes.of_string (String.concat "\n" ["#include <metal_stdlib>";"using namespace metal;";body;
    "kernel void "^name^"(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) { values[i] = prismel_dynamic_scale(i); }"]) in
  let uint_interface : Shader.binding list=[{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Compute]}] in
  let g7_words=get (Backend.create_buffer device {label=Some"g7-words";size=16L;usage=[Storage;Copy_src;Copy_dst]}) in
  let run_uint pipeline=
    let commands=get (Backend.begin_commands queue) in
    let compute=get (Backend.compute_encoder commands) in
    get (Backend.set_pipeline compute pipeline);
    get (Backend.set_buffer compute ~index:0 g7_words);
    get (Backend.dispatch_threads compute ~threads:(4,1,1) ~threadgroup:(4,1,1));
    get (Backend.end_compute compute);
    poll_epoch (get (Backend.commit commands)) 1000;
    let bytes=get (Backend.read_buffer g7_words ~offset:0L ~length:16) in
    Array.init 4 (fun i -> Int32.to_int (Bytes.get_int32_le bytes (i*4))) in
  if Caps.has profile Caps.Dynamic_libraries && Caps.has profile Caps.Compute_pipeline then begin
    let dynamic_source=Bytes.of_string "#include <metal_stdlib>\nusing namespace metal;\nextern \"C\" uint prismel_dynamic_scale(uint value) { return value * 7u; }\n" in
    let dynamic_shader=get (Shader.create {backend="metal";label=Some"conformance-dynamic";bytes=dynamic_source;entry_points=[];bindings=[]}) in
    (match Backend.create_dynamic_library device ~install_name:"" dynamic_shader with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "empty install name was accepted");
    let install_name=Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "prismel-conformance-%d.dynamic" (Unix.getpid ())) in
    let dynamic=get (Backend.create_dynamic_library device ~install_name dynamic_shader) in
    let client=get (Shader.create {backend="metal";label=Some"conformance-dynamic-client";
      bytes=fill_kernel "scaled" "extern \"C\" uint prismel_dynamic_scale(uint value);";entry_points=[{name="scaled";stage=Shader.Compute}];bindings=[]}) in
    let library=get (Backend.create_library ~dynamic:[dynamic] device client) in
    (match Backend.destroy_dynamic_library dynamic with
     | Error { Error.kind = Invalid_state; _ } -> ()
     | _ -> failwith "dynamic library with a linked library was destroyed");
    let pipeline=get (Backend.create_compute_pipeline_from library ~entry:"scaled" ~interface:uint_interface ()) in
    require (run_uint pipeline=[|0;7;14;21|]) "dynamic library function returned wrong values";
    get (Backend.destroy_pipeline pipeline);
    get (Backend.destroy_library library);
    get (Backend.destroy_dynamic_library dynamic)
  end else if not (Caps.has profile Caps.Dynamic_libraries) then begin
    let dynamic_shader=get (Shader.create {backend="metal";label=Some"conformance-dynamic";bytes=Bytes.of_string"void f() {}";entry_points=[];bindings=[]}) in
    expect_unsupported "unsupported dynamic library was created" (Backend.create_dynamic_library device ~install_name:"x" dynamic_shader)
  end;
  if Caps.has profile Caps.Binary_archives && Caps.has profile Caps.Compute_pipeline then begin
    let shader=get (Shader.create {backend="metal";label=Some"conformance-archive";
      bytes=fill_kernel "archived" "static uint prismel_dynamic_scale(uint value) { return value * 5u; }";entry_points=[{name="archived";stage=Shader.Compute}];bindings=[]}) in
    let library=get (Backend.create_library device shader) in
    let path=Filename.concat (Filename.get_temp_dir_name ()) (Printf.sprintf "prismel-conformance-%d.metallib" (Unix.getpid ())) in
    (match Backend.create_archive ~path:"relative.metallib" device () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "relative archive path was accepted");
    let archive=get (Backend.create_archive device ()) in
    (match Backend.create_compute_pipeline_from ~archives:[archive] ~archive_only:true library ~entry:"archived" ~interface:uint_interface () with
     | Error _ -> ()
     | Ok _ -> failwith "an empty archive satisfied archive_only");
    let compiled=get (Backend.create_compute_pipeline_from ~archives:[archive] library ~entry:"archived" ~interface:uint_interface ()) in
    get (Backend.archive_add archive compiled);
    get (Backend.archive_serialize archive path);
    get (Backend.destroy_pipeline compiled);
    get (Backend.destroy_archive archive);
    let loaded=get (Backend.create_archive ~path device ()) in
    let from_archive=get (Backend.create_compute_pipeline_from ~archives:[loaded] ~archive_only:true library ~entry:"archived" ~interface:uint_interface ()) in
    require (run_uint from_archive=[|0;5;10;15|]) "archived pipeline computed wrong values";
    get (Backend.destroy_pipeline from_archive);
    get (Backend.destroy_archive loaded);
    (try Sys.remove path with Sys_error _ -> ());
    get (Backend.destroy_library library)
  end else if not (Caps.has profile Caps.Binary_archives) then
    expect_unsupported "unsupported archive was created" (Backend.create_archive device ());
  get (Backend.destroy_buffer g7_words);
  if Caps.has profile Caps.Sparse_memory && Caps.has profile Caps.Heaps then begin
    (* Two tiles wide: only the mapped tile keeps the upload. *)
    let heap=get (Backend.create_heap device ~sparse:true ~size:(Int64.mul 4L 65536L) ()) in
    (match Backend.create_heap_buffer heap ~offset:0L {label=None;size=16L;usage=[Storage]} with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "sparse heap created a buffer");
    let probe=get (Backend.create_sparse_texture heap {label=Some"sparse-probe";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Texture_copy_src;Texture_copy_dst]}) in
    let tile_width,tile_height=get (Backend.texture_tile probe) in
    require (tile_width>0 && tile_height>0) "sparse tile size is empty";
    get (Backend.destroy_texture probe);
    let width=2*tile_width and height=tile_height in
    let descriptor : Types.texture_descriptor={label=Some"sparse";width;height;depth=1;mip_levels=1;sample_count=1;usage=[Texture_copy_src;Texture_copy_dst]} in
    let sparse=get (Backend.create_sparse_texture heap descriptor) in
    let row=Int64.of_int (((width*4)+255)/256*256) in
    let image=Int64.mul row (Int64.of_int height) in
    let upload=get (Backend.create_buffer device {label=Some"sparse-upload";size=image;usage=[Copy_src]}) in
    let download=get (Backend.create_buffer device {label=Some"sparse-download";size=image;usage=[Copy_dst]}) in
    get (Backend.write_buffer upload ~offset:0L (Bytes.make (Int64.to_int image) '\x5a'));
    let commands=get (Backend.begin_commands queue) in
    (match Backend.map_tiles commands sparse ~region:(0,0,0,1) ~map:true () with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "empty tile region was accepted");
    get (Backend.map_tiles commands sparse ~region:(0,0,1,1) ~map:true ());
    let blit=get (Backend.blit_encoder commands) in
    get (Backend.buffer_to_texture blit ~src:upload ~bytes_per_row:row ~bytes_per_image:image ~dst:sparse ~extent:{width;height;depth=1} ());
    get (Backend.texture_to_buffer blit ~src:sparse ~extent:{width;height;depth=1} ~dst:download ~bytes_per_row:row ~bytes_per_image:image ());
    get (Backend.end_blit blit);
    poll_epoch (get (Backend.commit commands)) 1000;
    let bytes=get (Backend.read_buffer download ~offset:0L ~length:(Int64.to_int image)) in
    let byte x y=Bytes.get bytes ((y*Int64.to_int row)+(x*4)) in
    require (byte 0 0='\x5a' && byte (tile_width-1) (height-1)='\x5a') "mapped sparse tile lost its upload";
    require (byte tile_width 0='\x00' && byte (width-1) (height-1)='\x00') "unmapped sparse tile did not read as zero";
    let commands=get (Backend.begin_commands queue) in
    get (Backend.map_tiles commands sparse ~region:(1,0,1,1) ~map:true ());
    get (Backend.map_tiles commands sparse ~region:(0,0,1,1) ~map:false ());
    let blit=get (Backend.blit_encoder commands) in
    get (Backend.buffer_to_texture blit ~src:upload ~bytes_per_row:row ~bytes_per_image:image ~dst:sparse ~extent:{width;height;depth=1} ());
    get (Backend.texture_to_buffer blit ~src:sparse ~extent:{width;height;depth=1} ~dst:download ~bytes_per_row:row ~bytes_per_image:image ());
    get (Backend.end_blit blit);
    poll_epoch (get (Backend.commit commands)) 1000;
    let bytes=get (Backend.read_buffer download ~offset:0L ~length:(Int64.to_int image)) in
    let byte x y=Bytes.get bytes ((y*Int64.to_int row)+(x*4)) in
    require (byte tile_width 0='\x5a' && byte 0 0='\x00') "remapped sparse tiles did not follow the mapping";
    get (Backend.destroy_buffer upload);
    get (Backend.destroy_buffer download);
    get (Backend.destroy_texture sparse);
    get (Backend.destroy_heap heap)
  end else if not (Caps.has profile Caps.Sparse_memory) then
    expect_unsupported "unsupported sparse heap was created" (Backend.create_heap device ~sparse:true ~size:65536L ());
  if Caps.has profile Caps.Metal_fx then begin
    (* A constant 2x2 image upscaled to 4x4 stays constant. *)
    (match Backend.create_upscaler device ~input:(4,4) ~output:(2,2) with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "downscaling upscaler was created");
    let upscaler=get (Backend.create_upscaler device ~input:(2,2) ~output:(4,4)) in
    let small=get (Backend.create_texture device {label=Some"fx-in";width=2;height=2;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Texture_copy_dst]}) in
    let large=get (Backend.create_texture device {label=Some"fx-out";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Render_attachment;Texture_copy_src]}) in
    let wrong=get (Backend.create_texture device {label=Some"fx-wrong";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding]}) in
    let staging=get (Backend.create_buffer device {label=Some"fx-staging";size=512L;usage=[Copy_src]}) in
    get (Backend.write_buffer staging ~offset:0L (Bytes.init 512 (fun i -> match i mod 4 with 0 -> '\x40' | 1 -> '\x80' | 2 -> '\xc0' | _ -> '\xff')));
    let commands=get (Backend.begin_commands queue) in
    let blit=get (Backend.blit_encoder commands) in
    get (Backend.buffer_to_texture blit ~src:staging ~bytes_per_row:256L ~bytes_per_image:512L ~dst:small ~extent:{width=2;height=2;depth=1} ());
    get (Backend.end_blit blit);
    (match Backend.upscale commands upscaler ~src:small ~dst:wrong with
     | Error { Error.kind = Invalid_argument; _ } -> ()
     | _ -> failwith "upscale into a texture without render usage was accepted");
    get (Backend.upscale commands upscaler ~src:small ~dst:large);
    poll_epoch (get (Backend.commit commands)) 1000;
    let pixels=get (Backend.read_texture large ~bytes_per_row:16) in
    for i=0 to 15 do
      let r=Char.code (Bytes.get pixels (i*4)) and g=Char.code (Bytes.get pixels (i*4+1)) and b=Char.code (Bytes.get pixels (i*4+2)) in
      require (abs (r-0x40)<=2 && abs (g-0x80)<=2 && abs (b-0xc0)<=2) "upscaled constant image drifted"
    done;
    get (Backend.destroy_buffer staging);
    get (Backend.destroy_texture wrong);
    get (Backend.destroy_texture large);
    get (Backend.destroy_texture small);
    get (Backend.destroy_upscaler upscaler);
    let stale=get (Backend.begin_commands queue) in
    (match Backend.upscale stale upscaler ~src:small ~dst:large with
     | Error { Error.kind = Stale_handle; _ } -> ()
     | _ -> failwith "destroyed upscaler was accepted");
    get (Backend.abandon stale)
  end else expect_unsupported "unsupported upscaler was created" (Backend.create_upscaler device ~input:(2,2) ~output:(4,4));
  get (Backend.destroy_buffer offsets);
  get (Backend.destroy_texture target);
  get (Backend.destroy_sampler sampler);
  let other_queue = get (Backend.create_queue device) in
  require (Command_buffer.completed_epoch other_queue = 0L)
    "new queue inherited another queue's completion";
  let other_commands=get (Backend.begin_commands other_queue) in
  let other_blit=get (Backend.blit_encoder other_commands) in
  get (Backend.copy_buffer other_blit ~src:source ~dst:destination ~length:16L ());
  get (Backend.end_blit other_blit);
  let other = get (Backend.commit other_commands) in
  require (other.epoch = 1L) "queue epochs are not independent";
  let rec poll_other attempts =
    match get (Command_buffer.status other_queue other) with
    | Command_buffer.Completed -> ()
    | Command_buffer.Pending when attempts = 0 ->
        failwith "second queue did not complete"
    | Command_buffer.Pending -> Unix.sleepf 0.001; poll_other (attempts - 1) in
  poll_other 1000;
  get (Backend.destroy_buffer source);
  (match Backend.read_buffer source ~offset:0L ~length:1 with
   | Error { Error.kind = Stale_handle; _ } -> ()
   | _ -> failwith "destroyed buffer remained readable");
  get (Backend.destroy_buffer destination);
  get (Backend.destroy_buffer upload);
  get (Backend.destroy_buffer readback);
  get (Backend.destroy_texture first);
  get (Backend.destroy_texture second);
  get (Backend.destroy_texture mip_first);
  get (Backend.destroy_texture mip_second);
  get (Backend.destroy_queue other_queue);
  get (Backend.destroy_queue queue);
  get (Backend.destroy_device device)
