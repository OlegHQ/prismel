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

let rss_tolerance () =
  match Sys.getenv_opt "PRISMEL_METAL_STRESS_RSS_TOLERANCE" with
  | None -> 8_388_608L
  | Some raw ->
      (match Int64.of_string_opt raw with
       | Some value when value >= 0L -> value
       | Some _ | None ->
           fail "PRISMEL_METAL_STRESS_RSS_TOLERANCE must be nonnegative")

let run_buffer_cycles device count =
  for _ = 1 to count do
    let buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
    in
    get (Buffer.destroy buffer)
  done

let run_texture_sampler_cycles device count =
  let texture_descriptor =
    Texture.descriptor_2d ~format:Texture.Rgba8_unorm ~width:1 ~height:1 ()
  in
  let sampler_descriptor = Sampler.default () in
  for _ = 1 to count do
    let texture = get (Texture.create ~device texture_descriptor) in
    let sampler = get (Sampler.create ~device sampler_descriptor) in
    get (Sampler.destroy sampler);
    get (Texture.destroy texture)
  done

let run_heap_cycles device count =
  let layout =
    get
      (Heap.buffer_size_and_align ~device ~length:16L
         ~storage:Buffer.Private ())
  in
  let descriptor = Heap.make_descriptor ~size:layout.size () in
  for _ = 1 to count do
    let heap = get (Heap.create ~device descriptor) in
    ignore (get (Heap.set_purgeable_state heap Volatile));
    (match get (Heap.purgeable_state heap) with
     | Nonvolatile -> ()
     | Volatile | Empty ->
         ignore (get (Heap.set_purgeable_state heap Nonvolatile)));
    let buffer = get (Heap.create_buffer heap ~length:16L ()) in
    ignore (get (Buffer.set_purgeable_state buffer Volatile));
    (match get (Buffer.purgeable_state buffer) with
     | Nonvolatile -> ()
     | Volatile | Empty ->
         ignore (get (Buffer.set_purgeable_state buffer Nonvolatile)));
    get (Buffer.make_aliasable buffer);
    let replacement = get (Heap.create_buffer heap ~length:16L ()) in
    get (Buffer.destroy replacement);
    get (Buffer.destroy buffer);
    get (Heap.destroy heap)
  done

let check_cycles ~name ~expected (baseline : Release_queue.stats)
    (finished : Release_queue.stats) =
  let created = Int64.sub finished.total_created baseline.total_created in
  let released = Int64.sub finished.total_released baseline.total_released in
  let rss_growth = Int64.sub finished.resident_bytes baseline.resident_bytes in
  if created <> expected || released <> created then
    fail "%s: expected %Ld balanced handles, got %Ld created and %Ld released"
      name expected created released;
  if finished.live_handles <> baseline.live_handles then
    fail "%s: live handles grew from %d to %d" name baseline.live_handles
      finished.live_handles;
  if finished.pending <> 0 || finished.dropped <> 0 then
    fail "%s: release queue did not settle (%d pending, %d dropped)" name
      finished.pending finished.dropped;
  let rss_tolerance = rss_tolerance () in
  if rss_growth > rss_tolerance then
    fail "%s: resident memory grew by %Ld bytes after settling (limit %Ld)" name
      rss_growth rss_tolerance;
  rss_growth

let () =
  if Sys.os_type <> "Unix"
     || not (Sys.file_exists "/System/Library/Frameworks/Metal.framework")
  then Printf.printf "Metal ownership stress skipped on this platform\n%!"
  else begin
    let device = get (Device.system_default ()) in
    run_buffer_cycles device 5_000;
    let buffer_baseline = settle () in
    run_buffer_cycles device 100_000;
    let buffer_finished = settle () in
    let buffer_rss_growth =
      check_cycles ~name:"buffers" ~expected:100_000L buffer_baseline
        buffer_finished
    in
    run_texture_sampler_cycles device 2_500;
    let resource_baseline = settle () in
    run_texture_sampler_cycles device 50_000;
    let resource_finished = settle () in
    let resource_rss_growth =
      check_cycles ~name:"textures/samplers" ~expected:100_000L
        resource_baseline resource_finished
    in
    run_heap_cycles device 500;
    let heap_baseline = settle () in
    run_heap_cycles device 10_000;
    let heap_finished = settle () in
    let heap_rss_growth =
      check_cycles ~name:"heaps/resources" ~expected:30_000L heap_baseline
        heap_finished
    in
    get (Device.destroy device);
    let final = settle () in
    if final.live_handles <> 0 then
      fail "%d Metal handles remain after stress teardown" final.live_handles;
    Printf.printf
      "Metal ownership stress passed: 100000 buffer, 100000 texture/sampler, and 30000 heap/resource handles, %Ld/%Ld/%Ld-byte settled RSS deltas\n%!"
      buffer_rss_growth resource_rss_growth heap_rss_growth
  end
