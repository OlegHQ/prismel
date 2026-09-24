open Ogpu_metal
let get=function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let get_metal=function Ok value->value|Error value->failwith(Format.asprintf"%a"Metal.pp_error value)
let expect kind=function Error value when value.Ogpu.Error.kind=kind->()|Error value->failwith(Ogpu.Error.to_string value)|Ok _->failwith"unexpected diagnostic success"
let ()=
  let device=get(Device.system_default())in let before=get_metal(Metal.Release_queue.stats())in
  let source=get(Buffer.create device~memory:Buffer.Shared{Ogpu.Types.size=16L;usage=[Copy_src];label=Some"source"})in
  let destination=get(Buffer.create device~memory:Buffer.Readback{Ogpu.Types.size=16L;usage=[Copy_dst];label=Some"destination"})in
  get(Buffer.write_bytes device source~dst_offset:0L(Bytes.of_string"0123456789abcdef"));
  let command=Command.create()in get(Command.copy_buffer command~source~source_offset:0L~destination~destination_offset:0L~length:16L);get(Command.end_ command);
  let resources=[Diagnostics.Buffer destination;Diagnostics.Buffer source]in
  expect Ogpu.Error.Invalid_state(Diagnostics.capture_hash device~label:"unfinished"~resources~commands:[Command.create()]);
  let hash()=get(Diagnostics.capture_hash device~label:"frame-0001"~resources~commands:[command])in
  let expected=hash()in let workers=Array.init 4(fun _->Domain.spawn hash)in Array.iter(fun worker->if Domain.join worker<>expected then failwith"capture hash domain drift")workers;
  let manifest=get(Diagnostics.serialize_capture device~label:"frame-0001"~resources~commands:[command])in
  if String.contains manifest 'x' && String.length manifest=0 then failwith"impossible manifest";
  let diagnostics=get(Diagnostics.create device~capacity:8)in for i=1 to 100000 do
    get(Diagnostics.add_error diagnostics~label:"submit"(Ogpu.Error.make"Queue.submit"Ogpu.Error.Device_lost(string_of_int i)))done;
  if List.length(Diagnostics.messages diagnostics)<>8||Diagnostics.dropped diagnostics<>99992 then failwith"diagnostic bound drift";
  (match Metal.Buffer.create~device:(Device.Private.metal device)~length:0L~storage:Metal.Buffer.Shared()with
   | Error metal when (Diagnostics.classify_metal_error~operation:"capture"metal).Ogpu.Error.kind=Ogpu.Error.Invalid_argument->()
   | _->failwith"typed Metal error classification drift");
  let queue=get(Queue.create device)in Queue.inject_next_error queue;
  let failure=match Queue.submit queue command with Error value when value.Ogpu.Error.kind=Ogpu.Error.Device_lost->value|_ ->failwith"injected error classification drift"in
  get(Diagnostics.add_error diagnostics~label:"real-m1"failure);
  if get(Buffer.read_bytes device destination~offset:0L~length:16)<>Bytes.make 16 '\000' then failwith"failed submit partially mutated destination";
  if hash()<>expected then failwith"failed submit mutated capture";
  get(Queue.destroy queue);Diagnostics.destroy diagnostics;get(Buffer.destroy destination);get(Buffer.destroy source);get(Device.destroy device);ignore(get_metal(Metal.Release_queue.drain()));
  let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"diagnostic/capture live-handle delta";
  Printf.printf"ogpu_metal diagnostics: hash=%s, 100k bounded, 4-domain equal, zero delta ok\n"expected
