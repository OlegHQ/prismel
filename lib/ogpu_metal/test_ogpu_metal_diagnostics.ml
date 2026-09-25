open Ogpu_metal_native
let get=function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let get_metal=function Ok value->value|Error value->failwith(Format.asprintf"%a"Metal.pp_error value)
let run () =
  let device=get(Device.system_default())in let before=get_metal(Metal.Release_queue.stats())in
  let diagnostics=get(Diagnostics.create device~capacity:8)in
  let expected=Digest.to_hex(Digest.string"ogpu-metal-diagnostics")in
  let hash()=Digest.to_hex(Digest.string"ogpu-metal-diagnostics")in
  let workers=Array.init 4(fun _->Domain.spawn hash)in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"digest domain drift")workers;
  for i=1 to 100000 do
    get(Diagnostics.add_error diagnostics~label:"submit"(Ogpu.Error.make"Queue.submit"Ogpu.Error.Device_lost(string_of_int i)))done;
  if List.length(Diagnostics.messages diagnostics)<>8||Diagnostics.dropped diagnostics<>99992 then failwith"diagnostic bound drift";
  (match Metal.Buffer.create~device:(Device.Private.metal device)~length:0L~storage:Metal.Buffer.Shared()with
   | Error metal when (Diagnostics.classify_metal_error~operation:"capture"metal).Ogpu.Error.kind=Ogpu.Error.Invalid_argument->()
   | _->failwith"typed Metal error classification drift");
  Diagnostics.destroy diagnostics;get(Device.destroy device);ignore(get_metal(Metal.Release_queue.drain()));
  let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-1 then failwith"diagnostic live-handle delta";
  print_endline"ogpu_metal diagnostics: 100k bounded, typed Metal classification, zero delta ok"
