let get = function Ok x -> x | Error e -> failwith (Ogpu.Error.to_string e)
let run frames =
  let driver, control = Ogpu_raster2.create () in
  let config : Ogpu.Surface.configuration = { logical_width=4; logical_height=4; physical_width=4; physical_height=4; format=Rgba8_unorm; present_mode=Immediate; max_acquired=2 } in
  let renderer = get (Scene_execution.create driver config) in
  let indices=Bytes.make 12 '\000' in Bytes.set_int32_le indices 4 1l; Bytes.set_int32_le indices 8 2l;
  let vertices=Bytes.make 48 '\000'in let put offset value=Bytes.set_int64_le vertices offset(Int64.bits_of_float value)in put 0 0.;put 8 0.;put 16 4.;put 24 0.;put 32 0.;put 40 4.;
  let mesh : Scene_execution.mesh = {key="software";vertices;vertex_count=3;indices;index_count=3} in
  let state : Scene_execution.state = {viewport=(0,0,4,4);scissor=(0,0,4,4)} in
  let draw={Scene_execution.mesh;state} in
  let vertices2=Bytes.copy vertices in let put2 offset value=Bytes.set_int64_le vertices2 offset(Int64.bits_of_float value)in put2 0 4.;put2 8 4.;put2 16 0.;put2 24 4.;put2 32 4.;put2 40 0.;let mesh2:Scene_execution.mesh={mesh with key="software-overlap";vertices=vertices2}in let draw2={Scene_execution.mesh=mesh2;state}in
  for frame=1 to frames do
    ignore(get(Scene_execution.render renderer(if frame=2 then [draw;draw2] else [draw])));
    if List.mem frame [1;2;60;600] then let bytes=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in if Bytes.get_int32_be bytes 0<>0x4080BFFFl then failwith"software exact pixel"else if frame=2&&Bytes.get_int32_be bytes 60<>0x4080BFFFl then failwith"software second indexed draw"else if frame<>2&&Bytes.get_int32_be bytes 60<>0l then failwith"software off-triangle pixel"
  done;
  get(Scene_execution.resize renderer {config with physical_width=8;physical_height=8});
  ignore(get(Scene_execution.render renderer [{draw with state={viewport=(0,0,8,8);scissor=(0,0,8,8)}}]));
  Ogpu_raster2.inject_device_loss control;
  (match Scene_execution.render renderer [draw] with Error e when e.Ogpu.Error.kind=Device_lost->()|_->failwith"software device loss");
  let trace=Ogpu_raster2.trace control in get(Scene_execution.destroy renderer);
  if Ogpu_raster2.live_counts control<>(0,0,0,0,0)then failwith"software live delta";
  trace
let ()=
  let expected=run 600 in
  let workers=Array.init 4(fun _->Domain.spawn(fun()->run 600))in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"software domain drift")workers;
  let driver,control=Ogpu_raster2.create()in let device=get(Ogpu.Backend.create_device driver)in
  let descriptor:Ogpu.Types.buffer_descriptor={label=None;size=4L;usage=[Copy_dst]}in
  for _=1 to 100_000 do let buffer=get(Ogpu.Backend.create_buffer device descriptor)in get(Ogpu.Backend.destroy_buffer buffer)done;
  get(Ogpu.Backend.destroy_device device);
  if Ogpu_raster2.live_counts control<>(0,0,0,0,0)then failwith"software 100k growth";
  print_endline"ogpu_raster2: frames1/2/60/600+resize, 4-domain, 100k zero delta"
