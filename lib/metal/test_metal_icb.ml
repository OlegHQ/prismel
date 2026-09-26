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

let run () =
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
  let data = get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ()) in
  let input = Bytes.create 4 in
  Bytes.set_int32_le input 0 5l;
  get (Buffer.write_bytes data ~dst_offset:0L input);
  let icb =
    get
      (Indirect_command_buffer.create ~device ~max_command_count:1 descriptor)
  in
  expect_error Invalid_argument
    (Indirect_command_buffer.reset icb ~location:1 ~length:1)
