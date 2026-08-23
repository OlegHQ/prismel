open Metal

let fail format = Printf.ksprintf failwith format
let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
let expect_error kind = function
  | Error error when error.kind = kind -> ()
  | Error error ->
      fail "unexpected error: %s" (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "operation unexpectedly succeeded"

let source = {|
#include <metal_stdlib>
using namespace metal;
kernel void icb_increment(device uint *value [[buffer(0)]]) { *value += 7u; }
|}

let () =
  let device = get (Device.system_default ()) in
  let baseline = get (Release_queue.stats ()) in
  let descriptor =
    Indirect_command_buffer.descriptor
      ~command_types:[ Indirect_concurrent_dispatch_threads ]
      ~max_kernel_buffer_bind_count:1 ()
  in
  expect_error Invalid_argument
    (Indirect_command_buffer.create ~device ~max_command_count:0 descriptor);
  let after_rejection = get (Release_queue.stats ()) in
  if after_rejection.live_handles <> baseline.live_handles then
    fail "rejected ICB creation leaked a native handle";
  let library = get (Library.compile_source ~device source) in
  let function_ = get (Function.find ~library "icb_increment") in
  let pipeline =
    get (Compute_pipeline.create ~support_indirect_command_buffers:true function_)
  in
  let data = get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ()) in
  let input = Bytes.create 4 in
  Bytes.set_int32_le input 0 5l;
  get (Buffer.write_bytes data ~dst_offset:0L input);
  let icb =
    get
      (Indirect_command_buffer.create ~device ~max_command_count:1 descriptor)
  in
  if Indirect_command_buffer.allocated_size icb <= 0L then
    fail "Metal returned an empty ICB allocation";
  expect_error Invalid_argument
    (Indirect_command_buffer.reset icb ~location:1 ~length:1);
  let indirect = get (Indirect_command_buffer.Compute_command.at icb 0) in
  get (Indirect_command_buffer.Compute_command.set_pipeline indirect pipeline);
  get
    (Indirect_command_buffer.Compute_command.set_kernel_buffer indirect ~index:0
       ~offset:0L data);
  get
    (Indirect_command_buffer.Compute_command.dispatch_threads indirect
       ~threads:(1, 1, 1) ~threadgroup:(1, 1, 1));
  expect_error Parent_has_dependents (Indirect_command_buffer.destroy icb);
  expect_error Parent_has_dependents (Buffer.destroy data);
  get (Indirect_command_buffer.Compute_command.destroy indirect);
  let queue = get (Command_queue.create device) in
  let command_buffer = get (Command_buffer.create queue ()) in
  let encoder = get (Compute_encoder.create command_buffer) in
  get (Compute_encoder.execute_indirect_commands encoder icb ~location:0 ~length:1);
  get (Compute_encoder.end_encoding encoder);
  expect_error Parent_has_dependents (Indirect_command_buffer.destroy icb);
  get (Command_buffer.commit command_buffer);
  get (Command_buffer.wait_until_completed command_buffer);
  let output = get (Buffer.read_bytes data ~offset:0L ~length:4) in
  if Bytes.get_int32_le output 0 <> 12l then
    fail "ICB compute result was %ld rather than 12" (Bytes.get_int32_le output 0);
  get (Command_buffer.destroy command_buffer);
  get (Command_queue.destroy queue);
  get (Indirect_command_buffer.reset icb ~location:0 ~length:1);
  get (Indirect_command_buffer.destroy icb);
  get (Buffer.destroy data);
  get (Compute_pipeline.destroy pipeline);
  get (Function.destroy function_);
  get (Library.destroy library);
  Gc.full_major ();
  ignore (get (Release_queue.drain ()));
  let settled = get (Release_queue.stats ()) in
  if settled.live_handles <> baseline.live_handles then
    fail "ICB conformance left %d child handle(s) live"
      (settled.live_handles - baseline.live_handles);
  get (Device.destroy device);
  Printf.printf "Metal indirect command buffer conformance passed\n%!"
