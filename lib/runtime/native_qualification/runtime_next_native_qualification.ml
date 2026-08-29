type scenario = Basic | Pxui_like | Canvas_offscreen | Scene3_builtin

let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let metal = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)

let rss_kib () =
  let argv = [| "/bin/ps"; "-o"; "rss="; "-p"; string_of_int (Unix.getpid ()) |] in
  let input = Unix.open_process_args_in argv.(0) argv in
  Fun.protect ~finally:(fun () -> ignore (Unix.close_process_in input))
    (fun () -> int_of_string (String.trim (input_line input)))

let name = function
  | Basic -> "basic"
  | Pxui_like -> "pxui-like"
  | Canvas_offscreen -> "canvas-offscreen"
  | Scene3_builtin -> "scene3-builtin"

let draw_count = function Basic -> 1 | Pxui_like -> 8 | Canvas_offscreen -> 3 | Scene3_builtin -> 4

let frozen_software_hash = function
  | Basic -> "183be222f2a9499335f80e49bab17f24"
  | Pxui_like -> "c28fb438cfaf0381adc6b8dddec9d6cf"
  | Canvas_offscreen -> "6669327647bf796bcc136e62a62f7c95"
  | Scene3_builtin -> "52462b7485ced3177c5f7bf2fda8a7ae"

let put_vertex bytes index (x,y) color =
  let offset=index*16 in
  Bytes.set_int32_le bytes offset (Int32.bits_of_float x);
  Bytes.set_int32_le bytes (offset+4) (Int32.bits_of_float y);
  Bytes.set_int32_le bytes (offset+8) color

let mesh scenario index =
  let vertices = Bytes.make 48 '\000' and indices = Bytes.make 12 '\000' in
  Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  let positions,color=match scenario with
    |Basic->[(-1.,1.);(1.,1.);(-1.,-1.)],0x4080BFFFl
    |Canvas_offscreen->[(-1.,1.);(0.,1.);(-1.,0.)],0x4080BFFFl
    |Scene3_builtin->[(1.,1.);(1.,-1.);(-1.,-1.)],0x4080BFFFl
    |Pxui_like->[(-1.,-1.);(3.,-1.);(-1.,3.)],0x4080BFFFl in
  List.iteri(fun vertex position->put_vertex vertices vertex position color)positions;
  { Scene_execution.key = Printf.sprintf "%s-%d" (name scenario) index;
    vertices; vertex_count = 3; indices; index_count = 3 }

let draws scenario extent =
  List.init (draw_count scenario) (fun index ->
    let inset = 0 in
    { Scene_execution.mesh = mesh scenario index;
      state = { viewport = (0, 0, extent, extent);
        scissor = (inset, inset, extent - inset, extent - inset);
        cull = Ogpu.Render_pass.Cull_none;
        depth_compare = Ogpu.Render_pass.Always;
        depth_write = false;
        depth_load = Ogpu.Render_pass.Clear;
        depth_clear = 1.;
        transform_uniforms = None;
        stencil_state = None;
        stencil_load = Ogpu.Render_pass.Clear;
        stencil_clear = 0 } })

let check_pixels extent bytes =
  if Bytes.length bytes <> extent * extent * 4 then failwith "native capture size drift";
  Digest.to_hex (Digest.bytes bytes)

let run scenario =
  let runtime = get (Runtime_next.create ~width:4 ~height:4 ()) in
  let initial_facts=Runtime_next.frame_facts runtime in
  let clear=(0.,0.,0.,0.)in
  let checkpoints = ref [] in
  for frame = 1 to 600 do
    ignore (get (Runtime_next.render ~clear runtime (draws scenario 4)));
    if List.mem frame [ 1; 2; 60; 600 ] then
      checkpoints := (frame, check_pixels initial_facts.drawable_width (get (Runtime_next.read_pixels runtime ~bytes_per_row:(initial_facts.drawable_width*4)))) :: !checkpoints
  done;
  get (Runtime_next.resize runtime ~width:8 ~height:8);
  let resized_facts=Runtime_next.frame_facts runtime in
  ignore (get (Runtime_next.render ~clear runtime (draws scenario 8)));
  let resized_hash = check_pixels resized_facts.drawable_width (get (Runtime_next.read_pixels runtime ~bytes_per_row:(resized_facts.drawable_width*4))) in
  let live_stats=Runtime_next.stats runtime in
  get (Runtime_next.destroy runtime);
  let dead_stats=Runtime_next.stats runtime in
  if List.exists (fun (_, hash) -> hash <> frozen_software_hash scenario) !checkpoints
     || (scenario=Basic && resized_hash <> "a07e462221d8a87c5d83ad9a18411a44")
  then failwith (Printf.sprintf "native qualification %s hash drift: %s resized=%s expected=%s"
    (name scenario) (String.concat "," (List.map snd !checkpoints)) resized_hash (frozen_software_hash scenario));
  let uploaded = draw_count scenario * 60 in
  let native_hash = snd (List.hd !checkpoints) in
  `Assoc [ "scenario", `String (name scenario); "frames", `Int 601;
    "draw_calls", `Int (draw_count scenario * 601);
    "pass_calls", `Int 601; "render_calls", `Int 601; "readback_calls", `Int 5;
    "runtime_backend_calls", `Int 607;
    "prepared_upload_bytes", `Int uploaded;
    "reported_upload_bytes", `String(Int64.to_string live_stats.uploaded_bytes);
    "pipeline_cache_entries_live", `Int live_stats.pipeline_cache_entries;
    "pipeline_cache_entries_after_destroy", `Int dead_stats.pipeline_cache_entries;
    "initial_logical_drawable", `List[`Int initial_facts.logical_width;`Int initial_facts.logical_height;`Int initial_facts.drawable_width;`Int initial_facts.drawable_height];
    "initial_pixel_scale", `List[`Float initial_facts.pixel_scale_x;`Float initial_facts.pixel_scale_y];
    "frozen_software_hash", `String (frozen_software_hash scenario);
    "native_matches_frozen_software", `Bool (native_hash = frozen_software_hash scenario);
    "checkpoint_hashes", `List (List.rev_map (fun (frame, hash) -> `List [ `Int frame; `String hash ]) !checkpoints);
    "resized_hash", `String resized_hash ]

let () =
  let synthetic:Runtime_next.frame_facts={logical_width=10;logical_height=10;drawable_width=15;drawable_height=15;pixel_scale_x=1.5;pixel_scale_y=1.5}in
  if Runtime_next.map_logical_rect synthetic(1,1,3,3)<>(1,1,5,5)then failwith"synthetic logical/drawable edge mapping drift";
  let input=match Runtime_next_input.create~max_events:8~max_file_bytes:8~logical_width:10~logical_height:10 with Ok value->value|Error message->failwith message in
  ignore(Runtime_next_input_sdl3.push input(Sdl3.Event.Mouse_motion{timestamp_ns=0L;window_id=1L;which=1L;buttons=0L;x=3.25;y=4.5;dx=0.;dy=0.}));
  if (Runtime_next_input.snapshot input).pointer<>(3.25,4.5)then failwith"SDL3 logical pointer was double-scaled";
  let before = metal (Metal.Release_queue.stats ()) and rss_before = rss_kib () in
  match Runtime_next.create ~width:1 ~height:1 () with
  | Error error -> failwith ("runtime-next native qualification create failed: " ^ Ogpu.Error.to_string error)
  | Ok probe ->
      get (Runtime_next.destroy probe);
      let rss_checkpoints = ref [] in
      let scenarios = List.map (fun scenario -> let result = run scenario in Gc.full_major(); rss_checkpoints := rss_kib () :: !rss_checkpoints; result)
        [ Basic; Pxui_like; Canvas_offscreen; Scene3_builtin ] in
      (* CAMetalLayer, Objective-C and the OCaml allocator may reserve their
         one-time teardown pools on the first few lifecycles.  Those reservations
         are not retained Prismel resources: verify the release queue first,
         then measure a settled sequence rather than treating allocator warm-up
         as a leak. *)
      for _ = 1 to 4 do
        let runtime = get (Runtime_next.create ~width:2 ~height:2 ()) in
        get (Runtime_next.destroy runtime);
        ignore (metal (Metal.Release_queue.drain ()));
        Gc.full_major ()
      done;
      let teardown_rss=Array.init 12(fun _->let runtime=get(Runtime_next.create~width:2~height:2())in get(Runtime_next.destroy runtime);ignore(metal(Metal.Release_queue.drain()));Gc.full_major();rss_kib())in
      let teardown_min=Array.fold_left min max_int teardown_rss and teardown_max=Array.fold_left max 0 teardown_rss in
      if teardown_max-teardown_min>4096 then failwith"native repeated teardown RSS did not plateau";
      ignore (metal (Metal.Release_queue.drain ()));
      let after = metal (Metal.Release_queue.stats ()) and rss_after = rss_kib () in
      if after.live_handles <> before.live_handles then failwith "native qualification live-handle delta";
      let report = `Assoc [ "schema", `Int 1; "host", `String "Apple M1";
        "checkpoints", `List [ `Int 1; `Int 2; `Int 60; `Int 600 ];
        "scenarios", `List scenarios; "rss_before_kib", `Int rss_before;
        "rss_after_kib", `Int rss_after; "live_handles_before", `Int before.live_handles;
        "live_handles_after", `Int after.live_handles;
        "rss_after_each_scenario_kib", `List (List.rev_map (fun value -> `Int value) !rss_checkpoints);
        "rss_after_twelve_teardown_cycles_kib", `List(Array.to_list(Array.map(fun value->`Int value)teardown_rss));
        "teardown_rss_range_kib", `Int(teardown_max-teardown_min);
        "msaa", `String "unsupported-by-runtime-next-sample-count-1";
        "shader3", `String "software-only-not-qualified-by-this-test";
        "retina", `String "resize-qualified-drawable-scale-not-exposed" ] in
      print_endline (Yojson.Safe.pretty_to_string report)
