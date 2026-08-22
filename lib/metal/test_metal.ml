open Metal

let fail format = Printf.ksprintf failwith format

let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let expect_error kind = function
  | Error error when error.kind = kind -> error
  | Error error ->
      fail "expected a different error kind: %s"
        (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "operation unexpectedly succeeded"

let shader_source =
  {|
#include <metal_stdlib>
using namespace metal;

kernel void increment(device uint *values [[buffer(0)]],
                      uint index [[thread_position_in_grid]]) {
  values[index] += 1;
}
|}

let input_values () =
  let bytes = Bytes.create 16 in
  [| 1l; 41l; 99l; -2l |]
  |> Array.iteri (fun index value -> Bytes.set_int32_le bytes (index * 4) value);
  bytes

let expected_values = [| 2l; 42l; 100l; Int32.minus_one |]

let check_values bytes =
  Array.iteri
    (fun index expected ->
      let actual = Bytes.get_int32_le bytes (index * 4) in
      if actual <> expected then
        fail "compute output %d: expected %ld, got %ld" index expected actual)
    expected_values

let settle_finalizers ~expected_live =
  let rec loop remaining =
    Gc.full_major ();
    ignore (get (Release_queue.drain ()));
    let stats = get (Release_queue.stats ()) in
    if stats.pending = 0 && stats.live_handles = expected_live then stats
    else if remaining = 0 then
      fail "Metal finalizers did not settle (%d pending, %d live; expected %d)"
        stats.pending stats.live_handles expected_live
    else loop (remaining - 1)
  in
  loop 8

let () =
  if Sys.os_type <> "Unix"
     || not (Sys.file_exists "/System/Library/Frameworks/Metal.framework")
  then Printf.printf "Metal conformance skipped on this platform\n%!"
  else begin
    if Provenance.sdk_version <> "26.5" then
      fail "unexpected generated SDK provenance %s" Provenance.sdk_version;
    let device = get (Device.system_default ()) in
    let all_devices = get (Device.all ()) in
    if all_devices = [] then fail "MTLCopyAllDevices returned no devices";
    let info = get (Device.info device) in
    if info.name = "" || info.registry_id = 0L then
      fail "default device identity is incomplete";
    if info.max_buffer_length < 16L then fail "device buffer limit is invalid";
    let before_finalizer = get (Release_queue.stats ()) in
    let allocate_unreleased_buffer () =
      ignore (get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ()))
    in
    allocate_unreleased_buffer ();
    let after_finalizer =
      settle_finalizers ~expected_live:before_finalizer.live_handles
    in
    if
      Int64.sub after_finalizer.total_created before_finalizer.total_created <> 1L
      || Int64.sub after_finalizer.total_released before_finalizer.total_released
         <> 1L
    then fail "custom-block finalization did not release exactly one Metal handle";
    ignore
      (expect_error Wrong_domain
         (Domain.spawn (fun () -> Device.info device) |> Domain.join));
    let buffer =
      get
        (Buffer.create ~device ~length:16L ~storage:Buffer.Shared
           ~label:"Metal conformance values" ())
    in
    if get (Buffer.label buffer) <> Some "Metal conformance values" then
      fail "buffer label did not round-trip";
    get (Buffer.write_bytes buffer ~dst_offset:0L (input_values ()));
    ignore (expect_error Parent_has_dependents (Device.destroy device));
    ignore
      (expect_error Invalid_argument
         (Buffer.read_bytes buffer ~offset:12L ~length:8));
    ignore
      (expect_error Invalid_argument
         (Buffer.read_bytes buffer ~offset:0L ~length:max_int));
    let private_buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Private ())
    in
    ignore
      (expect_error Unsupported
         (Buffer.read_bytes private_buffer ~offset:0L ~length:4));
    get (Buffer.destroy private_buffer);
    let invalid_shader =
      expect_error Native_error
        (Library.compile_source ~device "not a Metal program")
    in
    if invalid_shader.message = "" then
      fail "shader compilation lost its diagnostic";
    let library = get (Library.compile_source ~device shader_source) in
    let function_ = get (Function.find ~library "increment") in
    if get (Function.name function_) <> "increment" then
      fail "Metal function name did not round-trip";
    ignore (expect_error Parent_has_dependents (Library.destroy library));
    let pipeline = get (Compute_pipeline.create function_) in
    if Compute_pipeline.thread_execution_width pipeline <= 0
       || Compute_pipeline.max_total_threads_per_threadgroup pipeline <= 0
    then fail "compute pipeline limits are invalid";
    let queue = get (Command_queue.create device) in
    let commands =
      get (Command_buffer.create queue ~label:"Metal compute conformance" ())
    in
    let encoder = get (Compute_encoder.create commands) in
    get (Compute_encoder.set_pipeline encoder pipeline);
    get (Compute_encoder.set_buffer encoder ~index:0 ~offset:0L buffer);
    ignore
      (expect_error Invalid_argument
         (Compute_encoder.dispatch_threads encoder ~threads:(4, 1, 1)
            ~threadgroup:(max_int, 2, 1)));
    get
      (Compute_encoder.dispatch_threads encoder ~threads:(4, 1, 1)
         ~threadgroup:(4, 1, 1));
    ignore (expect_error Invalid_state (Command_buffer.commit commands));
    get (Compute_encoder.end_encoding encoder);
    get (Command_buffer.commit commands);
    get (Command_buffer.wait_until_completed commands);
    (match get (Command_buffer.status commands) with
     | Command_buffer.Completed -> ()
     | _ -> fail "command buffer did not complete");
    Buffer.read_bytes buffer ~offset:0L ~length:16 |> get |> check_values;
    get (Command_buffer.destroy commands);
    get (Command_queue.destroy queue);
    get (Compute_pipeline.destroy pipeline);
    get (Function.destroy function_);
    get (Library.destroy library);
    get (Buffer.destroy buffer);
    get (Buffer.destroy buffer);
    ignore
      (expect_error Destroyed
         (Buffer.read_bytes buffer ~offset:0L ~length:1));
    get (Device.destroy device);
    List.iter (fun value -> get (Device.destroy value)) all_devices;
    let stats = settle_finalizers ~expected_live:0 in
    if stats.pending <> 0 || stats.dropped <> 0 || stats.live_handles <> 0 then
      fail "Metal release accounting did not settle (%d pending, %d dropped, %d live)"
        stats.pending stats.dropped stats.live_handles;
    Printf.printf
      "Metal ARC/device/buffer/runtime-shader/compute conformance passed on %s\n%!"
      info.name
  end
