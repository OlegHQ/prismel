open Metal
let fail fmt=Printf.ksprintf failwith fmt
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a"pp_error e)
let run () =
  match Device.system_default()with Error _->print_endline"compute encoder35: skipped (no device)"|Ok device->
  let indirect_args=get(Buffer.create~device~length:12L~storage:Buffer.Shared())in
  let indirect_bytes=Bytes.make 12 '\000' in Bytes.set_int32_le indirect_bytes 0 4l;Bytes.set_int32_le indirect_bytes 4 1l;Bytes.set_int32_le indirect_bytes 8 1l;get(Buffer.write_bytes indirect_args~dst_offset:0L indirect_bytes);
  let stage_args=get(Buffer.create~device~length:24L~storage:Buffer.Shared())in
  let stage_bytes=Bytes.make 24 '\000' in Bytes.set_int32_le stage_bytes 12 1l;Bytes.set_int32_le stage_bytes 16 1l;Bytes.set_int32_le stage_bytes 20 1l;get(Buffer.write_bytes stage_args~dst_offset:0L stage_bytes);
  let range_buffer=get(Buffer.create~device~length:8L~storage:Buffer.Shared())in
  let range_bytes=Bytes.make 8 '\000' in Bytes.set_int32_le range_bytes 4 1l;get(Buffer.write_bytes range_buffer~dst_offset:0L range_bytes)
