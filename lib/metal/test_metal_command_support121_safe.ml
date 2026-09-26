open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let run () =
  let device=get(Device.system_default())in
  let render_descriptor=Indirect_command_buffer.descriptor
    ~inherit_cull_mode:false ~inherit_depth_bias:false
    ~max_object_threadgroup_memory_bind_count:1
    ~command_types:[Indirect_command_buffer.Indirect_draw]()in
  (match Indirect_command_buffer.create ~device ~max_command_count:1 render_descriptor with
  | Error e when e.kind=Unsupported||e.kind=Native_error->()
  | Error e->fail "%s"(Format.asprintf "%a" pp_error e)
  | Ok buffer->let command=get(Indirect_command_buffer.Render_command.at buffer 0)in
      get(Indirect_command_buffer.Render_command.destroy command);get(Indirect_command_buffer.destroy buffer));
  get(Device.destroy device)
