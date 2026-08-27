open Ogpu_metal
let get = function Ok value -> value | Error value -> failwith (Ogpu.Error.to_string value)
let get_metal = function Ok value -> value | Error value -> failwith (Format.asprintf "%a" Metal.pp_error value)
let expect kind = function
  | Error value when value.Ogpu.Error.kind=kind -> ()
  | Error value -> failwith ("unexpected memory error: " ^ Ogpu.Error.to_string value)
  | Ok _ -> failwith "unexpected memory success"
let descriptor storage = {Ogpu.Memory.size=65536L;alignment=256L;storage;max_allocations=8}
let () =
  let device=get(Device.system_default()) and other=get(Device.system_default()) in
  let before=get_metal(Metal.Release_queue.stats()) in
  expect Ogpu.Error.Unsupported (Memory.create_sparse device (descriptor Ogpu.Memory.Private));
  let heap=get(Memory.create device (descriptor Ogpu.Memory.Shared)) in
  expect Ogpu.Error.Invalid_argument (Memory.allocate device heap ~size:64L ~alignment:3L);
  expect Ogpu.Error.Invalid_argument (Memory.allocate device heap ~size:Int64.max_int ~alignment:256L);
  let allocation=get(Memory.allocate device heap ~size:1024L ~alignment:256L) in
  let physical=Memory.interval allocation in
  if physical.offset<>0L||physical.length<1024L then failwith "Metal heap layout drift";
  expect Ogpu.Error.Cross_device (Memory.read_bytes other allocation ~offset:0L ~length:1);
  let payload=Bytes.init 1024 (fun i->Char.chr(i land 255)) in
  get(Memory.write_bytes device allocation ~offset:0L payload);
  if get(Memory.read_bytes device allocation ~offset:0L ~length:1024)<>payload then failwith "heap byte roundtrip drift";
  expect Ogpu.Error.Invalid_state (Memory.destroy heap);
  get(Memory.begin_alias device allocation);
  expect Ogpu.Error.Invalid_state (Memory.read_bytes device allocation ~offset:0L ~length:1);
  expect Ogpu.Error.Invalid_state (Memory.free allocation);
  get(Memory.end_alias device allocation); get(Memory.free allocation);
  let reused=get(Memory.allocate device heap ~size:1024L ~alignment:256L) in
  if (Memory.interval reused).offset<>physical.offset then failwith "heap interval was not reused";
  get(Memory.free reused);
  for _=1 to 1000 do let value=get(Memory.allocate device heap ~size:64L ~alignment:256L) in get(Memory.free value) done;
  if Memory.live_allocations heap<>0 then failwith "heap ownership is unbounded";
  get(Memory.destroy heap); expect Ogpu.Error.Stale_handle (Memory.allocate device heap ~size:64L ~alignment:256L);
  let check_policy storage write_kind read_kind =
    let heap=get(Memory.create device (descriptor storage)) in
    let value=get(Memory.allocate device heap ~size:256L ~alignment:256L) in
    (match write_kind with None->get(Memory.write_bytes device value ~offset:0L(Bytes.of_string"x"))|Some kind->expect kind(Memory.write_bytes device value ~offset:0L(Bytes.of_string"x")));
    (match read_kind with None->ignore(get(Memory.read_bytes device value ~offset:0L ~length:1))|Some kind->expect kind(Memory.read_bytes device value ~offset:0L ~length:1));
    get(Memory.free value);get(Memory.destroy heap)
  in
  check_policy Ogpu.Memory.Private (Some Ogpu.Error.Unsupported) (Some Ogpu.Error.Unsupported);
  check_policy Ogpu.Memory.Upload None (Some Ogpu.Error.Unsupported);
  check_policy Ogpu.Memory.Readback (Some Ogpu.Error.Unsupported) None;
  get(Device.destroy device);get(Device.destroy other);ignore(get_metal(Metal.Release_queue.drain()));
  let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-2 then failwith"memory live-handle delta";
  print_endline"ogpu_metal memory: placed heap, alias/reuse, 1000 lifecycle, zero delta ok"
