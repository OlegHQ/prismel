open Metal

let fail format = Printf.ksprintf failwith format

let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let expect_error kind = function
  | Error error when error.kind = kind -> error
  | Error error ->
      fail "expected another error kind: %s" (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "operation unexpectedly succeeded"

let shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void xpc_write(texture2d<uint, access::write> target [[texture(0)]],
                      device const uint *input [[buffer(0)]]) {
  target.write(uint4(input[0], 0u, 0u, 0u), uint2(0u, 0u));
}

kernel void xpc_exchange(texture2d<uint, access::read_write> target
                           [[texture(0)]],
                         device const uint *replacement [[buffer(0)]],
                         device uint *observed [[buffer(1)]]) {
  observed[0] = target.read(uint2(0u, 0u)).x;
  target.write(uint4(replacement[0], 0u, 0u, 0u), uint2(0u, 0u));
}

kernel void xpc_read(texture2d<uint, access::read> target [[texture(0)]],
                     device uint *observed [[buffer(0)]]) {
  observed[0] = target.read(uint2(0u, 0u)).x;
}
|}

type t =
  { device : Device.t
  ; library : Library.t
  ; write_function : Function.t
  ; exchange_function : Function.t
  ; read_function : Function.t
  ; write_pipeline : Compute_pipeline.t
  ; exchange_pipeline : Compute_pipeline.t
  ; read_pipeline : Compute_pipeline.t
  ; queue : Command_queue.t
  }

let create device =
  let library = get (Library.compile_source ~device shader_source) in
  let write_function = get (Function.find ~library "xpc_write") in
  let exchange_function = get (Function.find ~library "xpc_exchange") in
  let read_function = get (Function.find ~library "xpc_read") in
  let write_pipeline = get (Compute_pipeline.create write_function) in
  let exchange_pipeline = get (Compute_pipeline.create exchange_function) in
  let read_pipeline = get (Compute_pipeline.create read_function) in
  let queue = get (Command_queue.create device) in
  { device; library; write_function; exchange_function; read_function
  ; write_pipeline; exchange_pipeline; read_pipeline; queue
  }

let uint32_bytes value =
  let bytes = Bytes.create 4 in
  Bytes.set_int32_le bytes 0 value;
  bytes

let complete commands =
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  (match get (Command_buffer.status commands) with
   | Command_buffer.Completed -> ()
   | Command_buffer.Error message -> fail "Metal XPC compute failed: %s" message
   | _ -> fail "Metal XPC compute did not reach the completed state");
  get (Command_buffer.destroy commands)

let write value target replacement =
  let input =
    get
      (Buffer.create_copy ~device:value.device ~storage:Buffer.Shared
         (uint32_bytes replacement))
  in
  let commands = get (Command_buffer.create value.queue ()) in
  let encoder = get (Compute_encoder.create commands) in
  get (Compute_encoder.set_pipeline encoder value.write_pipeline);
  get (Compute_encoder.set_texture encoder ~index:0 target);
  get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L input);
  get
    (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
       ~threadgroup:(1, 1, 1));
  get (Compute_encoder.end_encoding encoder);
  complete commands;
  get (Buffer.destroy input)

let exchange value target replacement =
  let input =
    get
      (Buffer.create_copy ~device:value.device ~storage:Buffer.Shared
         (uint32_bytes replacement))
  in
  let output =
    get (Buffer.create ~device:value.device ~length:4L ~storage:Buffer.Shared ())
  in
  let commands = get (Command_buffer.create value.queue ()) in
  let encoder = get (Compute_encoder.create commands) in
  get (Compute_encoder.set_pipeline encoder value.exchange_pipeline);
  get (Compute_encoder.set_texture encoder ~index:0 target);
  get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L input);
  get (Compute_encoder.set_buffer encoder ~index:1 ~offset:0L output);
  get
    (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
       ~threadgroup:(1, 1, 1));
  get (Compute_encoder.end_encoding encoder);
  complete commands;
  let observed =
    Bytes.get_int32_le (get (Buffer.read_bytes output ~offset:0L ~length:4)) 0
  in
  get (Buffer.destroy output);
  get (Buffer.destroy input);
  observed

let read value target =
  let output =
    get (Buffer.create ~device:value.device ~length:4L ~storage:Buffer.Shared ())
  in
  let commands = get (Command_buffer.create value.queue ()) in
  let encoder = get (Compute_encoder.create commands) in
  get (Compute_encoder.set_pipeline encoder value.read_pipeline);
  get (Compute_encoder.set_texture encoder ~index:0 target);
  get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L output);
  get
    (Compute_encoder.dispatch_threads encoder ~threads:(1, 1, 1)
       ~threadgroup:(1, 1, 1));
  get (Compute_encoder.end_encoding encoder);
  complete commands;
  let observed =
    Bytes.get_int32_le (get (Buffer.read_bytes output ~offset:0L ~length:4)) 0
  in
  get (Buffer.destroy output);
  observed

let destroy value =
  get (Command_queue.destroy value.queue);
  get (Compute_pipeline.destroy value.read_pipeline);
  get (Compute_pipeline.destroy value.exchange_pipeline);
  get (Compute_pipeline.destroy value.write_pipeline);
  get (Function.destroy value.read_function);
  get (Function.destroy value.exchange_function);
  get (Function.destroy value.write_function);
  get (Library.destroy value.library)
