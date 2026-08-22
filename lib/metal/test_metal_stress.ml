open Metal

let fail format = Printf.ksprintf failwith format

let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let settle () =
  Gc.full_major ();
  Gc.compact ();
  ignore (get (Release_queue.drain ()));
  get (Release_queue.stats ())

let run_cycles device count =
  for _ = 1 to count do
    let buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
    in
    get (Buffer.destroy buffer)
  done

let () =
  if Sys.os_type <> "Unix"
     || not (Sys.file_exists "/System/Library/Frameworks/Metal.framework")
  then Printf.printf "Metal ownership stress skipped on this platform\n%!"
  else begin
    let device = get (Device.system_default ()) in
    run_cycles device 5_000;
    let baseline = settle () in
    run_cycles device 100_000;
    let finished = settle () in
    let created = Int64.sub finished.total_created baseline.total_created in
    let released = Int64.sub finished.total_released baseline.total_released in
    let rss_growth = Int64.sub finished.resident_bytes baseline.resident_bytes in
    if created <> 100_000L || released <> created then
      fail "expected 100000 balanced handles, got %Ld created and %Ld released"
        created released;
    if finished.live_handles <> baseline.live_handles then
      fail "live handles grew from %d to %d" baseline.live_handles
        finished.live_handles;
    if finished.pending <> 0 || finished.dropped <> 0 then
      fail "release queue did not settle (%d pending, %d dropped)" finished.pending
        finished.dropped;
    let rss_tolerance = 8_388_608L in
    if rss_growth > rss_tolerance then
      fail "resident memory grew by %Ld bytes after settling (limit %Ld)"
        rss_growth rss_tolerance;
    get (Device.destroy device);
    let final = settle () in
    if final.live_handles <> 0 then
      fail "%d Metal handles remain after stress teardown" final.live_handles;
    Printf.printf
      "Metal ownership stress passed: 100000 cycles, %Ld-byte settled RSS delta\n%!"
      rss_growth
  end
