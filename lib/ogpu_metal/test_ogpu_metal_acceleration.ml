open Ogpu_metal
let get = function Ok value->value|Error value->failwith(Ogpu.Error.to_string value)
let get_metal = function Ok value->value|Error value->failwith(Format.asprintf"%a"Metal.pp_error value)
let expect kind=function Error value when value.Ogpu.Error.kind=kind->()|Error value->failwith(Ogpu.Error.to_string value)|Ok _->failwith"unexpected acceleration success"
let ()=
  let device=get(Device.system_default())and other=get(Device.system_default())in
  let before=get_metal(Metal.Release_queue.stats())in
  let planned=get(Acceleration.plan_triangle~ray_tracing:true~buffer_size:36L~offset:0L~length:36L~vertex_stride:12~vertex_count:3)in
  if planned.vertex_count<>3||planned.vertex_stride<>12 then failwith"acceleration plan drift";
  expect Ogpu.Error.Invalid_argument(Acceleration.plan_triangle~ray_tracing:false~buffer_size:36L~offset:0L~length:35L~vertex_stride:12~vertex_count:3);
  expect Ogpu.Error.Unsupported(Acceleration.plan_triangle~ray_tracing:false~buffer_size:36L~offset:0L~length:36L~vertex_stride:12~vertex_count:3);
  get(Acceleration.validate_scratch_plan~buffer_size:1024L~offset:256L~required:512L);
  expect Ogpu.Error.Invalid_argument(Acceleration.validate_scratch_plan~buffer_size:1024L~offset:4L~required:512L);
  expect Ogpu.Error.Invalid_argument(Acceleration.validate_scratch_plan~buffer_size:1024L~offset:768L~required:512L);
  let vertices=get(Buffer.create device~memory:Buffer.Shared{Ogpu.Types.size=36L;usage=[Storage;Vertex];label=Some"triangle"})in
  if(Device.capabilities device).Ogpu.Capabilities.ray_tracing then begin
    let structure=get(Acceleration.create_triangle device~vertices~offset:0L~length:36L~vertex_stride:12~vertex_count:3~allow_refit:true)in
    let scratch=get(Buffer.create device~memory:Buffer.Device_local{Ogpu.Types.size=1048576L;usage=[Storage];label=Some"scratch"})in
    expect Ogpu.Error.Cross_device(Acceleration.build other structure~scratch~scratch_offset:0L);
    ignore(get(Acceleration.build device structure~scratch~scratch_offset:0L));
    ignore(get(Acceleration.refit device structure~scratch~scratch_offset:0L));
    let copied,_=get(Acceleration.copy device structure)in ignore(get(Acceleration.compact device structure));
    get(Acceleration.destroy copied);get(Acceleration.destroy structure);get(Buffer.destroy scratch)
  end else begin
    expect Ogpu.Error.Unsupported(Acceleration.create_triangle device~vertices~offset:0L~length:36L~vertex_stride:12~vertex_count:3~allow_refit:true);
    expect Ogpu.Error.Invalid_argument(Acceleration.create_triangle device~vertices~offset:0L~length:35L~vertex_stride:12~vertex_count:3~allow_refit:true)
  end;
  get(Buffer.destroy vertices);get(Device.destroy device);get(Device.destroy other);ignore(get_metal(Metal.Release_queue.drain()));
  let after=get_metal(Metal.Release_queue.stats())in if after.live_handles<>before.live_handles-2 then failwith"acceleration live-handle delta";
  print_endline"ogpu_metal acceleration: typed native path compiled, M1 unsupported atomic, zero delta ok"
