open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->fail "%s"(Format.asprintf "%a" pp_error e)|Ok _->fail "expected rejection"
let ()=
  let manager=get(Capture.Manager.shared())in
  ignore(get(Capture.Manager.supports_destination manager Capture.Developer_tools));
  ignore(get(Capture.Manager.is_capturing manager));
  let capture=get(Capture.Descriptor.create ~destination:Capture.Developer_tools())in
  get(Capture.Descriptor.set_destination capture Capture.Gpu_trace_document);
  if Capture.Descriptor.destination capture<>Capture.Gpu_trace_document then fail "capture destination drift";
  get(Capture.Descriptor.destroy capture);get(Capture.Manager.destroy manager);
  let device=get(Device.system_default())in
  let compute_descriptor=Indirect_command_buffer.descriptor
    ~max_kernel_threadgroup_memory_bind_count:1
    ~command_types:[Indirect_command_buffer.Indirect_concurrent_dispatch]()in
  (match Indirect_command_buffer.create ~device ~max_command_count:1 compute_descriptor with
  | Error e when e.kind=Unsupported||e.kind=Native_error->()
  | Error e->fail "%s"(Format.asprintf "%a" pp_error e)
  | Ok buffer->
      let command=get(Indirect_command_buffer.Compute_command.at buffer 0)in
      expect Invalid_argument(Indirect_command_buffer.Compute_command.set_imageblock command ~width:(-1L)~height:1L);
      expect Invalid_argument(Indirect_command_buffer.Compute_command.set_threadgroup_memory_length command ~index:1 ~length:16L);
      expect Invalid_argument(Indirect_command_buffer.Compute_command.concurrent_dispatch_threadgroups command ~threadgroups:(0L,1L,1L)~threads_per_threadgroup:(1L,1L,1L));
      get(Indirect_command_buffer.Compute_command.destroy command);get(Indirect_command_buffer.destroy buffer));
  let render_descriptor=Indirect_command_buffer.descriptor
    ~inherit_cull_mode:false ~inherit_depth_bias:false
    ~max_object_threadgroup_memory_bind_count:1
    ~command_types:[Indirect_command_buffer.Indirect_draw]()in
  (match Indirect_command_buffer.create ~device ~max_command_count:1 render_descriptor with
  | Error e when e.kind=Unsupported||e.kind=Native_error->()
  | Error e->fail "%s"(Format.asprintf "%a" pp_error e)
  | Ok buffer->let command=get(Indirect_command_buffer.Render_command.at buffer 0)in
      expect Invalid_argument(Indirect_command_buffer.Render_command.set_depth_bias command ~bias:nan ~slope_scale:0. ~clamp:0.);
      expect Invalid_argument(Indirect_command_buffer.Render_command.set_object_threadgroup_memory_length command ~index:1 ~length:0L);
      expect Invalid_argument(Indirect_command_buffer.Render_command.draw_mesh_threads command ~threads:(0L,1L,1L)~object_threadgroup:(1L,1L,1L)~mesh_threadgroup:(1L,1L,1L));
      get(Indirect_command_buffer.Render_command.destroy command);get(Indirect_command_buffer.destroy buffer));
  get(Device.destroy device)
