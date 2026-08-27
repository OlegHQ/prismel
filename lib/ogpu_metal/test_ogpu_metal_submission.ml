open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let get_metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"wrong rejection"
let buffer_descriptor : Ogpu.Types.buffer_descriptor={label=Some"submission-buffer";size=16L;usage=[Copy_src;Copy_dst;Storage]}
let texture_descriptor : Ogpu.Types.texture_descriptor={label=Some"submission-target";width=2;height=2;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}
let shader={|#include <metal_stdlib>
using namespace metal;
kernel void add_one(device uint *values [[buffer(0)]], uint i [[thread_position_in_grid]]) { values[i] += 1; }
|}
let ended f=let command=Command.create()in get(f command);get(Command.end_ command);command
let ()=match Device.system_default()with Error _->print_endline"ogpu_metal submission: skipped (no device)"|Ok device->
  let other=get(Device.system_default())in let before=get_metal(Metal.Release_queue.stats())in
  let queue=get(Queue.create~max_frames:3 device)in
  let source=get(Buffer.create device~memory:Buffer.Shared buffer_descriptor)and destination=get(Buffer.create device~memory:Buffer.Shared buffer_descriptor)in
  let bytes=Bytes.make 16 '\000'in for i=0 to 3 do Bytes.set_int32_le bytes(i*4)(Int32.of_int(i*10))done;get(Buffer.write_bytes device source~dst_offset:0L bytes);
  let target=get(Texture.create device~memory:Texture.Shared~format:Texture.Rgba8_unorm texture_descriptor)in
  let copy=ended(fun c->Command.copy_buffer c~source~source_offset:0L~destination~destination_offset:0L~length:16L)in
  let compute=ended(fun c->Command.compute c~source:shader~entry:"add_one"~buffer:destination~threads:4)in
  let clear=ended(fun c->Command.clear c target~color:(0.25,0.5,0.75,1.))in
  let r1=get(Queue.submit queue copy)and r2=get(Queue.submit queue compute)and r3=get(Queue.submit queue clear)in
  if(r1.epoch,r2.epoch,r3.epoch)<>(1L,2L,3L)||Queue.in_flight queue<>3 then failwith"three-frame epoch ordering drift";
  let capacity=ended(fun _->Ok())in expect Ogpu.Error.Capacity(Queue.submit queue capacity);
  get(Queue.wait_through queue r3.epoch);
  let actual=get(Buffer.read_bytes device destination~offset:0L~length:16)in for i=0 to 3 do if Bytes.get_int32_le actual(i*4)<>Int32.of_int(i*10+1)then failwith"copy/compute result mismatch"done;
  let pixels=get(Texture.read_bytes device target~mip_level:0~bytes_per_row:8)in if Bytes.length pixels<>16||Char.code(Bytes.get pixels 0)<>64||Char.code(Bytes.get pixels 1)<>128||Char.code(Bytes.get pixels 2)<>191||Char.code(Bytes.get pixels 3)<>255 then failwith"render clear result mismatch";
  let fourth=get(Queue.submit queue capacity)in expect Ogpu.Error.Invalid_state(Queue.submit queue capacity);get(Queue.wait_through queue fourth.epoch);
  let foreign=get(Buffer.create other~memory:Buffer.Shared buffer_descriptor)in let wrong=ended(fun c->Command.copy_buffer c~source:foreign~source_offset:0L~destination~destination_offset:0L~length:4L)in expect Ogpu.Error.Cross_device(Queue.submit queue wrong);
  let stale=get(Buffer.create device~memory:Buffer.Shared buffer_descriptor)in let stale_command=ended(fun c->Command.copy_buffer c~source:stale~source_offset:0L~destination~destination_offset:0L~length:4L)in get(Buffer.destroy stale);expect Ogpu.Error.Stale_handle(Queue.submit queue stale_command);
  let injected=ended(fun _->Ok())in Queue.inject_next_error queue;expect Ogpu.Error.Device_lost(Queue.submit queue injected);
  get(Buffer.destroy foreign);get(Texture.destroy target);get(Buffer.destroy destination);get(Buffer.destroy source);get(Queue.destroy queue);get(Device.destroy device);get(Device.destroy other);ignore(get_metal(Metal.Release_queue.drain()));
  let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-2 then failwith"submission live-handle delta";
  print_endline"ogpu_metal submission: copy/compute/clear, ordered max3, zero live-handle delta"
