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

let external_rss_tolerance () =
  match Sys.getenv_opt "PRISMEL_METAL_EXTERNAL_STRESS_RSS_TOLERANCE" with
  | None -> rss_tolerance ()
  | Some raw ->
      (match Int64.of_string_opt raw with
       | Some value when value >= 0L -> value
       | Some _ | None ->
           fail
             "PRISMEL_METAL_EXTERNAL_STRESS_RSS_TOLERANCE must be nonnegative")

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

let run_residency_cycles device count =
  let descriptor = Residency_set.make_descriptor ~initial_capacity:1 () in
  for _ = 1 to count do
    let buffer =
      get (Buffer.create ~device ~length:16L ~storage:Buffer.Shared ())
    in
    let residency_set = get (Residency_set.create ~device descriptor) in
    let allocation = Residency_set.Buffer buffer in
    get (Residency_set.add_allocation residency_set allocation);
    get (Residency_set.commit residency_set);
    get (Residency_set.remove_allocation residency_set allocation);
    get (Residency_set.commit residency_set);
    get (Buffer.destroy buffer);
    get (Residency_set.destroy residency_set)
  done

let run_external_buffer_cycles device ~page_size count =
  let length = Int64.of_int page_size in
  for _ = 1 to count do
    let memory = get (Buffer.External.create ~length) in
    let buffer =
      get
        (Buffer.create_no_copy ~device ~memory ~storage:Buffer.Shared ())
    in
    get (Buffer.destroy buffer);
    get (Buffer.External.destroy memory)
  done

let run_buffer_texture_cycles device count =
  let alignment =
    get
      (Texture.minimum_buffer_alignment ~device ~kind:Texture.Texture_2d
         ~format:Texture.Rgba8_unorm)
  in
  if alignment > Int64.of_int max_int then
    fail "linear texture alignment exceeds an OCaml integer";
  let minimum_row = 16L in
  let remainder = Int64.rem minimum_row alignment in
  let row_pitch =
    (if remainder = 0L then minimum_row
     else Int64.add minimum_row (Int64.sub alignment remainder))
    |> Int64.to_int
  in
  let descriptor =
    Texture.descriptor_2d ~storage:Buffer.Shared
      ~format:Texture.Rgba8_unorm ~width:4 ~height:1 ()
  in
  for _ = 1 to count do
    let buffer =
      get
        (Buffer.create ~device ~length:(Int64.of_int row_pitch)
           ~storage:Buffer.Shared ())
    in
    let texture =
      get
        (Texture.create_from_buffer ~buffer ~offset:0L
           ~bytes_per_row:row_pitch descriptor)
    in
    get (Texture.destroy texture);
    get (Buffer.destroy buffer)
  done

let check_cycles ?rss_limit ~name ~expected (baseline : Release_queue.stats)
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
  if
    finished.external_deallocation_mismatches
    <> baseline.external_deallocation_mismatches
  then
    fail "%s: Metal reported a no-copy deallocator layout mismatch" name;
  let rss_tolerance = Option.value rss_limit ~default:(rss_tolerance ()) in
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
    let residency_rss_growth =
      if get (Device.supports_residency_sets device) then begin
        run_residency_cycles device 500;
        let baseline = settle () in
        run_residency_cycles device 10_000;
        let finished = settle () in
        Some
          (check_cycles ~name:"residency sets/resources" ~expected:20_000L
             baseline finished)
      end
      else None
    in
    run_buffer_texture_cycles device 500;
    let buffer_texture_baseline = settle () in
    run_buffer_texture_cycles device 10_000;
    let buffer_texture_finished = settle () in
    let buffer_texture_rss_growth =
      check_cycles ~name:"buffer-backed textures" ~expected:20_000L
        buffer_texture_baseline buffer_texture_finished
    in
    let page_size = get (Buffer.External.page_size ()) in
    run_external_buffer_cycles device ~page_size 500;
    let external_baseline = settle () in
    run_external_buffer_cycles device ~page_size 10_000;
    let external_finished = settle () in
    let external_rss_growth =
      check_cycles ~rss_limit:(external_rss_tolerance ())
        ~name:"external/no-copy buffers" ~expected:20_000L
        external_baseline external_finished
    in
    let external_deallocations =
      Int64.sub external_finished.external_deallocations
        external_baseline.external_deallocations
    in
    get (Device.destroy device);
    let final = settle () in
    if final.live_handles <> 0 then
      fail "%d Metal handles remain after stress teardown" final.live_handles;
    (match residency_rss_growth with
     | Some residency_rss_growth ->
         Printf.printf
           "Metal ownership stress passed: 100000 buffer, 100000 texture/sampler, 30000 heap/resource, 20000 residency/resource, 20000 buffer/linear-texture, and 20000 external/no-copy handles, %Ld/%Ld/%Ld/%Ld/%Ld/%Ld-byte settled RSS deltas, %Ld deferred no-copy callbacks\n%!"
           buffer_rss_growth resource_rss_growth heap_rss_growth
           residency_rss_growth buffer_texture_rss_growth external_rss_growth
           external_deallocations
     | None ->
         Printf.printf
           "Metal ownership stress passed: 100000 buffer, 100000 texture/sampler, 30000 heap/resource, 20000 buffer/linear-texture, and 20000 external/no-copy handles; residency unsupported, %Ld/%Ld/%Ld/%Ld/%Ld-byte settled RSS deltas, %Ld deferred no-copy callbacks\n%!"
           buffer_rss_growth resource_rss_growth heap_rss_growth
           buffer_texture_rss_growth external_rss_growth external_deallocations)
  end
