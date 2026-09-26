open Metal

let fail format = Printf.ksprintf failwith format

let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let expect_invalid name = function
  | Error { kind = Invalid_argument; _ } -> ()
  | Error error ->
      fail "%s returned %s, expected Invalid_argument" name
        (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "%s accepted a malformed range" name

let stats_equal name before after =
  if before.Release_queue.total_created <> after.Release_queue.total_created
     || before.total_released <> after.total_released
     || before.live_handles <> after.live_handles
  then
    fail
      "%s crossed the native boundary (created %Ld -> %Ld, released %Ld -> %Ld, live %d -> %d)"
      name before.total_created after.total_created before.total_released
      after.total_released before.live_handles after.live_handles

let reject_without_native_work name operation =
  ignore (get (Release_queue.drain ()));
  ignore (get (Release_queue.drain ()));
  let before = get (Release_queue.stats ()) in
  expect_invalid name (operation ());
  let after = get (Release_queue.stats ()) in
  stats_equal name before after

let run () =
  match Device.system_default () with
  | Error _ -> print_endline "Metal resource bounds: skipped (no device)"
  | Ok device ->
      let info = get (Device.info device) in
      reject_without_native_work "negative buffer length" (fun () ->
        Buffer.create ~device ~length:(-1L) ~storage:Buffer.Shared ());
      reject_without_native_work "oversized buffer length" (fun () ->
        Buffer.create ~device ~length:(Int64.succ info.max_buffer_length)
          ~storage:Buffer.Shared ())
