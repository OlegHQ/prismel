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
  let sampler_descriptor =
    if get (Device.supports_sampler_reduction device) then
      { (Sampler.default ()) with
        min_filter = Sampler.Linear
      ; mag_filter = Sampler.Linear
      ; mip_filter = Sampler.Mip_linear
      ; reduction_mode = Sampler.Minimum
      ; lod_bias = 0.5
      }
    else Sampler.default ()
  in
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

let sparse_page device =
  [ Sparse_page_size.Page_16_kib
  ; Sparse_page_size.Page_64_kib
  ; Sparse_page_size.Page_256_kib
  ]
  |> List.find_map (fun page_size ->
    match Heap.sparse_tile_size_in_bytes ~device page_size with
    | Ok bytes -> Some (page_size, bytes)
    | Error { kind = Unsupported; _ } -> None
    | Error error -> fail "%s" (Format.asprintf "%a" pp_error error))

let sparse_depth_descriptor device ~page_size ~page_bytes =
  let heap =
    get
      (Heap.create ~device
         (Heap.make_descriptor ~kind:Heap.Sparse ~sparse_page_size:page_size
            ~size:page_bytes ()))
  in
  Fun.protect
    ~finally:(fun () -> get (Heap.destroy heap))
    (fun () ->
      [ Texture.Depth16_unorm; Texture.Depth32_float; Texture.Stencil8
      ; Texture.Depth24_unorm_stencil8; Texture.Depth32_float_stencil8
      ]
      |> List.find_map (fun format ->
        let descriptor =
          Texture.descriptor_2d ~storage:Buffer.Private
            ~usage:[ Texture.Render_target ] ~format ~width:1 ~height:1 ()
        in
        match Heap.create_texture heap descriptor with
        | Ok texture ->
            get (Texture.destroy texture);
            Some descriptor
        | Error { kind = Unsupported; _ } -> None
        | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)))

let run_sparse_cycles device ~page_size ~page_bytes count =
  let heap_descriptor =
    Heap.make_descriptor ~kind:Heap.Sparse ~sparse_page_size:page_size
      ~size:page_bytes ()
  in
  let texture_descriptor =
    Texture.descriptor_2d ~storage:Buffer.Private
      ~usage:[ Texture.Shader_read ] ~format:Texture.R8_uint ~width:1
      ~height:1 ()
  in
  for _ = 1 to count do
    let heap = get (Heap.create ~device heap_descriptor) in
    let texture = get (Heap.create_texture heap texture_descriptor) in
    get (Texture.destroy texture);
    get (Heap.destroy heap)
  done

let run_sparse_depth_cycles device ~page_size ~page_bytes
    ~depth_descriptor count =
  let heap_descriptor =
    Heap.make_descriptor ~kind:Heap.Sparse ~sparse_page_size:page_size
      ~size:page_bytes ()
  in
  for _ = 1 to count do
    let heap = get (Heap.create ~device heap_descriptor) in
    let texture = get (Heap.create_texture heap depth_descriptor) in
    get (Texture.destroy texture);
    get (Heap.destroy heap)
  done

let placement_sparse_page device =
  let texture_descriptor =
    Texture.descriptor_2d ~storage:Buffer.Private
      ~usage:[ Texture.Shader_read ] ~format:Texture.R8_uint ~width:1
      ~height:1 ()
  in
  [ Sparse_page_size.Page_16_kib
  ; Sparse_page_size.Page_64_kib
  ; Sparse_page_size.Page_256_kib
  ]
  |> List.find_map (fun page_size ->
    let page_bytes = Sparse_page_size.bytes page_size in
    match
      Buffer.create_placement_sparse ~device ~page_size ~length:page_bytes
        ~storage:Buffer.Private ()
    with
    | Error { kind = Unsupported; _ } -> None
    | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
    | Ok buffer ->
        (match
           Texture.create_placement_sparse ~device ~page_size
             texture_descriptor
         with
         | Error { kind = Unsupported; _ } ->
             get (Buffer.destroy buffer);
             None
         | Error error ->
             get (Buffer.destroy buffer);
             fail "%s" (Format.asprintf "%a" pp_error error)
         | Ok texture ->
             get (Texture.destroy texture);
             get (Buffer.destroy buffer);
             Some (page_size, page_bytes, texture_descriptor)))

let run_placement_sparse_cycles device ~page_size ~page_bytes
    ~texture_descriptor count =
  let heap_descriptor =
    Heap.make_descriptor ~kind:Heap.Placement ~sparse_page_size:page_size
      ~size:page_bytes ()
  in
  for _ = 1 to count do
    let heap = get (Heap.create ~device heap_descriptor) in
    let buffer =
      get
        (Buffer.create_placement_sparse ~device ~page_size ~length:page_bytes
           ~storage:Buffer.Private ())
    in
    let texture =
      get
        (Texture.create_placement_sparse ~device ~page_size
           texture_descriptor)
    in
    get (Texture.destroy texture);
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

let run_shared_texture_cycles device count =
  let descriptor =
    Texture.descriptor_2d ~storage:Buffer.Private
      ~format:Texture.Rgba8_unorm ~width:1 ~height:1 ()
  in
  for _ = 1 to count do
    let source = get (Texture.create_shared ~device descriptor) in
    let handle = get (Texture.shared_handle source) in
    get (Texture.destroy source);
    let imported = get (Texture.import_shared ~device handle) in
    get (Texture.Shared_handle.destroy handle);
    get (Texture.destroy imported)
  done

let run_io_surface_cycles device count =
  let descriptor =
    Texture.descriptor_2d ~storage:Buffer.Shared
      ~format:Texture.Rgba8_unorm ~width:1 ~height:1 ()
  in
  for _ = 1 to count do
    let surface =
      get
        (Texture.Io_surface.create ~width:1 ~height:1 ~bytes_per_element:4 ())
    in
    let texture =
      get
        (Texture.create_from_io_surface ~device ~surface ~plane:0 descriptor)
    in
    get (Texture.destroy texture);
    get (Texture.Io_surface.destroy surface)
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

type lane =
  | Buffers
  | Textures_and_samplers
  | Heaps_and_resources
  | Sparse_heaps_and_textures
  | Sparse_depth_stencil
  | Placement_sparse_resources
  | Residency_sets_and_resources
  | Buffer_backed_textures
  | Shared_textures
  | Io_surfaces
  | External_buffers

let lane_name = function
  | Buffers -> "buffers"
  | Textures_and_samplers -> "textures-samplers"
  | Heaps_and_resources -> "heaps-resources"
  | Sparse_heaps_and_textures -> "sparse-heaps-textures"
  | Sparse_depth_stencil -> "sparse-depth-stencil"
  | Placement_sparse_resources -> "placement-sparse-resources"
  | Residency_sets_and_resources -> "residency-sets-resources"
  | Buffer_backed_textures -> "buffer-backed-textures"
  | Shared_textures -> "shared-textures"
  | Io_surfaces -> "io-surfaces"
  | External_buffers -> "external-buffers"

let lane_of_name = function
  | "buffers" -> Buffers
  | "textures-samplers" -> Textures_and_samplers
  | "heaps-resources" -> Heaps_and_resources
  | "sparse-heaps-textures" -> Sparse_heaps_and_textures
  | "sparse-depth-stencil" -> Sparse_depth_stencil
  | "placement-sparse-resources" -> Placement_sparse_resources
  | "residency-sets-resources" -> Residency_sets_and_resources
  | "buffer-backed-textures" -> Buffer_backed_textures
  | "shared-textures" -> Shared_textures
  | "io-surfaces" -> Io_surfaces
  | "external-buffers" -> External_buffers
  | name -> fail "unknown Metal ownership-stress lane %S" name

let lanes =
  [ Buffers
  ; Textures_and_samplers
  ; Heaps_and_resources
  ; Sparse_heaps_and_textures
  ; Sparse_depth_stencil
  ; Placement_sparse_resources
  ; Residency_sets_and_resources
  ; Buffer_backed_textures
  ; Shared_textures
  ; Io_surfaces
  ; External_buffers
  ]

let destroy_device device =
  get (Device.destroy device);
  let final = settle () in
  if final.live_handles <> 0 then
    fail "%d Metal handles remain after stress teardown" final.live_handles;
  final

let finish_device device = ignore (destroy_device device)

let measure device ~name ~warmup ~cycles ~expected run =
  run device warmup;
  let baseline = settle () in
  run device cycles;
  let finished = settle () in
  let growth = check_cycles ~name ~expected baseline finished in
  finish_device device;
  Printf.printf
    "Metal ownership lane %s passed: %Ld measured handles, %Ld-byte settled RSS delta\n%!"
    name expected growth

let run_lane lane =
  let device = get (Device.system_default ()) in
  match lane with
  | Buffers ->
      measure device ~name:"buffers" ~warmup:5_000 ~cycles:100_000
        ~expected:100_000L run_buffer_cycles
  | Textures_and_samplers ->
      measure device ~name:"textures/samplers" ~warmup:2_500 ~cycles:50_000
        ~expected:100_000L run_texture_sampler_cycles
  | Heaps_and_resources ->
      measure device ~name:"heaps/resources" ~warmup:500 ~cycles:10_000
        ~expected:30_000L run_heap_cycles
  | Sparse_heaps_and_textures ->
      if not (get (Device.supports_sparse_textures device)) then begin
        finish_device device;
        Printf.printf "Metal ownership lane sparse heaps/textures skipped: unsupported\n%!"
      end
      else
        (match sparse_page device with
         | None -> fail "sparse device exposes no usable sparse page size"
         | Some (page_size, page_bytes) ->
             let run device count =
               run_sparse_cycles device ~page_size ~page_bytes count
             in
             measure device ~name:"sparse heaps/textures" ~warmup:500
               ~cycles:10_000 ~expected:20_000L run)
  | Sparse_depth_stencil ->
      if not (get (Device.supports_sparse_textures device)) then begin
        finish_device device;
        Printf.printf
          "Metal ownership lane sparse depth/stencil skipped: unsupported\n%!"
      end
      else
        (match sparse_page device with
         | None -> fail "sparse device exposes no usable sparse page size"
         | Some (page_size, page_bytes) ->
             (match
                sparse_depth_descriptor device ~page_size ~page_bytes
              with
              | None ->
                  finish_device device;
                  Printf.printf
                    "Metal ownership lane sparse depth/stencil skipped: no supported format\n%!"
              | Some depth_descriptor ->
                  let run device count =
                    run_sparse_depth_cycles device ~page_size ~page_bytes
                      ~depth_descriptor count
                  in
                  measure device ~name:"sparse depth/stencil" ~warmup:500
                    ~cycles:10_000 ~expected:20_000L run))
  | Placement_sparse_resources ->
      if not (get (Device.supports_placement_sparse device)) then begin
        finish_device device;
        Printf.printf
          "Metal ownership lane placement sparse resources skipped: unsupported\n%!"
      end
      else
        (match placement_sparse_page device with
         | None ->
             fail
               "placement sparse device exposes no usable reviewed page size"
         | Some (page_size, page_bytes, texture_descriptor) ->
             let run device count =
               run_placement_sparse_cycles device ~page_size ~page_bytes
                 ~texture_descriptor count
             in
             measure device ~name:"placement sparse resources" ~warmup:500
               ~cycles:10_000 ~expected:30_000L run)
  | Residency_sets_and_resources ->
      if not (get (Device.supports_residency_sets device)) then begin
        finish_device device;
        Printf.printf "Metal ownership lane residency sets/resources skipped: unsupported\n%!"
      end
      else
        measure device ~name:"residency sets/resources" ~warmup:500
          ~cycles:10_000 ~expected:20_000L run_residency_cycles
  | Buffer_backed_textures ->
      measure device ~name:"buffer-backed textures" ~warmup:500
        ~cycles:10_000 ~expected:20_000L run_buffer_texture_cycles
  | Shared_textures ->
      measure device ~name:"shared textures/handles/imports" ~warmup:500
        ~cycles:10_000 ~expected:30_000L run_shared_texture_cycles
  | Io_surfaces ->
      measure device ~name:"IOSurface/texture ownership" ~warmup:500
        ~cycles:10_000 ~expected:20_000L run_io_surface_cycles
  | External_buffers ->
      let page_size = get (Buffer.External.page_size ()) in
      let run device count =
        run_external_buffer_cycles device ~page_size count
      in
      run device 500;
      let baseline = settle () in
      run device 10_000;
      let finished = settle () in
      let growth =
        check_cycles ~rss_limit:(external_rss_tolerance ())
          ~name:"external/no-copy buffers" ~expected:20_000L baseline finished
      in
      let final = destroy_device device in
      let deallocations =
        Int64.sub final.external_deallocations
          baseline.external_deallocations
      in
      Printf.printf
        "Metal ownership lane external/no-copy buffers passed: 20000 measured handles, %Ld-byte settled RSS delta, %Ld deferred callbacks\n%!"
        growth deallocations

let status_text = function
  | Unix.WEXITED code -> Printf.sprintf "exit %d" code
  | Unix.WSIGNALED signal -> Printf.sprintf "signal %d" signal
  | Unix.WSTOPPED signal -> Printf.sprintf "stopped %d" signal

let run_worker lane =
  let executable = Unix.realpath Sys.executable_name in
  let name = lane_name lane in
  let pid =
    Unix.create_process executable [| executable; "--lane"; name |]
      Unix.stdin Unix.stdout Unix.stderr
  in
  match snd (Unix.waitpid [] pid) with
  | Unix.WEXITED 0 -> ()
  | status -> fail "Metal ownership lane %s failed with %s" name (status_text status)

let metal_available () =
  Sys.os_type = "Unix"
  && Sys.file_exists "/System/Library/Frameworks/Metal.framework"

let () =
  if not (metal_available ()) then
    Printf.printf "Metal ownership stress skipped on this platform\n%!"
  else
    match Array.to_list Sys.argv with
    | [ _ ] ->
        List.iter run_worker lanes;
        Printf.printf "%d isolated Metal ownership lanes passed\n%!"
          (List.length lanes)
    | [ _; "--lane"; name ] -> run_lane (lane_of_name name)
    | _ -> fail "usage: test_metal_stress.exe [--lane LANE]"
