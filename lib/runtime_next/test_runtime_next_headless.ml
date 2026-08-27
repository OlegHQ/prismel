let get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
module Headless=Runtime_next_headless

let mesh extent =
  let vertices=Bytes.make 48 '\000'in
  let set index x y=let offset=index*16 in Bytes.set_int64_le vertices offset
      (Int64.bits_of_float x);Bytes.set_int64_le vertices(offset+8)(Int64.bits_of_float y)in
  set 0 0. 0.;set 1(float extent)0.;set 2 0.(float extent);
  let indices=Bytes.make 12 '\000'in Bytes.set_int32_le indices 4 1l;
  Bytes.set_int32_le indices 8 2l;
  {Scene_execution.key=Printf.sprintf"headless-%d"extent;vertices;vertex_count=3;
    indices;index_count=3}

let draw extent =
  {Scene_execution.mesh=mesh extent;
    state={viewport=(0,0,extent,extent);scissor=(0,0,extent,extent)}}

let expect_pixels runtime extent =
  let pitch=extent*4 in let rendered=get(Headless.read_pixels runtime~bytes_per_row:pitch)
  and presented=get(Headless.presented_pixels runtime)in
  if rendered<>presented then failwith"presented framebuffer differs from software render";
  if Bytes.get_int32_be rendered 0<>0x4080bfffl then failwith"genuine software pixel missing"

let () =
  let runtime=get(Headless.create~logical_width:4~logical_height:4
      ~drawable_width:4~drawable_height:4)in
  for frame=1 to 600 do ignore(get(Headless.render runtime[draw 4]));
    if List.mem frame[1;2;60;600]then expect_pixels runtime 4 done;
  get(Headless.resize runtime~logical_width:4~logical_height:4
    ~drawable_width:8~drawable_height:8);
  ignore(get(Headless.render runtime[draw 8]));expect_pixels runtime 8;
  for _cycle=1 to 100_000 do ignore(get(Headless.render runtime[draw 8]))done;
  if Headless.backend_live_counts runtime<>(2,1,6,1,1)then
    failwith"headless long-run object counts grew";
  let trace_length, dropped_traces = Headless.backend_trace_stats runtime in
  if trace_length > 256 || dropped_traces = 0 then
    failwith "headless long-run trace storage is not bounded";
  get(Headless.destroy runtime);
  if Headless.backend_live_counts runtime<>(0,0,0,0,0)then
    failwith"headless destroy leaked backend objects";
  begin match Headless.render runtime[]with Error _->()|Ok _->failwith"stale runtime accepted"end;
  print_endline"runtime_next headless: genuine pixels frames1/2/60/600+resize, 100k flat"
