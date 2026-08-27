let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

module Web = Runtime_next_web

let mesh extent =
  let vertices = Bytes.make 48 '\000' in
  let set index x y =
    let offset = index * 16 in
    Bytes.set_int64_le vertices offset (Int64.bits_of_float x);
    Bytes.set_int64_le vertices (offset + 8) (Int64.bits_of_float y)
  in
  set 0 0. 0.;
  set 1 (float extent) 0.;
  set 2 0. (float extent);
  let indices = Bytes.make 12 '\000' in
  Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  {
    Scene_execution.key = Printf.sprintf "web-%d" extent;
    vertices;
    vertex_count = 3;
    indices;
    index_count = 3;
  }

let draw extent =
  {
    Scene_execution.mesh = mesh extent;
    state =
      { viewport = (0, 0, extent, extent); scissor = (0, 0, extent, extent);
        cull = Ogpu.Render_pass.Cull_none;
        depth_compare = Ogpu.Render_pass.Always; depth_write = false;
        depth_load = Ogpu.Render_pass.Clear; depth_clear = 1.;
        transform_uniforms = None; stencil_state = None;
        stencil_load = Ogpu.Render_pass.Clear; stencil_clear = 0 };
  }

let () =
  let wap_config =
    {
      Wap.default_config with
      interface = "127.0.0.1";
      port = 0;
      max_frame_pool_bytes = 4096;
      compress_frames = false;
    }
  in
  let runtime =
    get
      (Web.create ~wap_config ~logical_width:4 ~logical_height:4
         ~drawable_width:4 ~drawable_height:4 ())
  in
  if get(Web.client_count runtime)<>0
     ||not(String.starts_with~prefix:"http://127.0.0.1:"(get(Web.url runtime)))then
    failwith"web URL/client facts drift";
  (match Web.download_frame runtime~filename:"capture.png"with
   |Error{kind=Ogpu.Error.Invalid_state;_}->()
   |Ok()|Error _->failwith"download without a browser was accepted");
  let text_regions : Wap.text_input_region list =
    [ { x = 1; y = 2; width = 3; height = 4; focused = false };
      { x = 8; y = 9; width = 10; height = 11; focused = true } ]
  in
  for frame = 1 to 600 do
    get (Web.set_text_input_regions runtime text_regions);
    ignore (get (Web.render runtime [ draw 4 ]));
    if List.mem frame [ 1; 2; 60; 600 ] then begin
      let stats = get(Web.target_stats runtime) in
      if stats.frames_submitted <> frame then failwith "frame codec order drift";
      if stats.source_bytes_submitted <> Int64.of_int (frame * 64) then
        failwith "frame codec byte count drift";
      if Web.text_input_regions runtime <> text_regions then
        failwith "typed text input region order/focus drift"
    end
  done;
  get
    (Web.resize runtime ~logical_width:4 ~logical_height:4 ~drawable_width:8
       ~drawable_height:8);
  ignore (get (Web.render runtime [ draw 8 ]));
  let after_resize = get(Web.target_stats runtime) in
  if after_resize.frames_submitted <> 601
     || after_resize.source_bytes_submitted <> 38_656L
  then failwith "post-resize codec bytes drift";
  for _cycle = 1 to 100_000 do
    ignore (get (Web.render runtime [ draw 8 ]))
  done;
  let stats = get(Web.target_stats runtime) in
  if stats.frames_submitted <> 100_601 || stats.frames_suppressed < 100_598 then
    failwith "slow-client stale-frame storage is not bounded";
  if Web.backend_live_counts runtime <> (2, 6, 84, 1, 1) then
    failwith "web long-run object counts grew";
  let trace_length, dropped_traces = Web.backend_trace_stats runtime in
  if trace_length > 256 || dropped_traces = 0 then
    failwith "web long-run trace storage is not bounded";
  if Web.port runtime <= 0 then failwith "web server did not bind";
  get (Web.destroy runtime);
  if Web.backend_live_counts runtime <> (0, 0, 0, 0, 0) then
    failwith "web destroy leaked backend objects";
  begin
    match Web.render runtime [] with
    | Error _ -> ()
    | Ok _ -> failwith "destroyed web runtime accepted a frame"
  end;
  begin
    match Web.set_text_input_regions runtime text_regions with
    | Error _ -> ()
    | Ok () -> failwith "destroyed web runtime accepted text input regions"
  end;
  print_endline
    "runtime_next web: packed frames1/2/60/600+resize, 100k bounded"
