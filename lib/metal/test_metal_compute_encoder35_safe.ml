open Metal
let fail fmt=Printf.ksprintf failwith fmt
let run () =
  match Device.system_default()with Error _->print_endline"compute encoder35: skipped (no device)"|Ok _device->
  let indirect_bytes=Bytes.make 12 '\000' in Bytes.set_int32_le indirect_bytes 0 4l;Bytes.set_int32_le indirect_bytes 4 1l;Bytes.set_int32_le indirect_bytes 8 1l;let stage_bytes=Bytes.make 24 '\000' in Bytes.set_int32_le stage_bytes 12 1l;Bytes.set_int32_le stage_bytes 16 1l;Bytes.set_int32_le stage_bytes 20 1l;let range_bytes=Bytes.make 8 '\000' in Bytes.set_int32_le range_bytes 4 1l
