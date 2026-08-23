open Metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" pp_error error)

let () =
  if Sys.os_type <> "Unix"
     || not (Sys.file_exists "/System/Library/Frameworks/Metal.framework")
  then Printf.printf "Metal generated device capability test skipped\n%!"
  else begin
    let device = get (Device.system_default ()) in
    let before = get (Release_queue.stats ()) in
    let capabilities = get (Device.capabilities device) in
    let after = get (Release_queue.stats ()) in
    if after.live_handles <> before.live_handles
       || after.total_created <> before.total_created
       || after.total_released <> before.total_released
    then failwith "capability getters changed Metal handle accounting";
    if capabilities.location_number < 0L
       || capabilities.max_argument_buffer_sampler_count < 0L
       || capabilities.max_transfer_rate < 0L
       || capabilities.maximum_concurrent_compilation_task_count < 0L
       || capabilities.peer_count < 0L
       || capabilities.peer_index < 0L
    then failwith "unsigned Metal capability was negative";
    get (Device.destroy device);
    ignore (get (Release_queue.drain ()));
    Printf.printf "Metal generated Device capability conformance passed\n%!"
  end
