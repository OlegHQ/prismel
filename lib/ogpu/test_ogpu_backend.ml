let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"backend rejection mismatch"
let run ()=
  let driver,control=Ogpu.Backend_mock.create()in let device=get(Ogpu.Backend.create_device driver)in
  let descriptor : Ogpu.Types.buffer_descriptor={label=Some"portable";size=64L;usage=[Copy_src;Copy_dst]}in
  let source=get(Ogpu.Backend.create_buffer device descriptor)and destination=get(Ogpu.Backend.create_buffer device descriptor)in
  let portable_source=Ogpu.Backend.transfer_buffer source and portable_destination=Ogpu.Backend.transfer_buffer destination in
  let pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in get(Ogpu.Transfer_pass.copy_buffer pass~src:portable_source~src_offset:0L~dst:portable_destination~dst_offset:0L~length:16L);let command=get(Ogpu.Backend.transfer pass)in
  let queue=get(Ogpu.Backend.create_queue device)in expect Ogpu.Error.Invalid_argument(Ogpu.Backend.submit queue command~resources:[]~pipelines:[]);
  ignore portable_source;ignore portable_destination;
  let receipt=get(Ogpu.Backend.submit queue command~resources:[`Buffer source;`Buffer destination]~pipelines:[])in get(Ogpu.Backend.complete_through queue receipt.epoch);
  let config : Ogpu.Surface.configuration={logical_width=2;logical_height=2;physical_width=4;physical_height=4;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in let surface=get(Ogpu.Backend.create_surface device config)in let frame=match get(Ogpu.Backend.acquire surface)with`Acquired x->x|_->failwith"mock acquire"in get(Ogpu.Backend.present frame);expect Ogpu.Error.Invalid_state(Ogpu.Backend.present frame);
  Ogpu.Backend_mock.inject_device_loss control;expect Ogpu.Error.Device_lost(Ogpu.Backend.submit queue command~resources:[`Buffer source;`Buffer destination]~pipelines:[]);
  expect Ogpu.Error.Invalid_state(Ogpu.Backend.destroy_device device);get(Ogpu.Backend.destroy_surface surface);get(Ogpu.Backend.destroy_queue queue);get(Ogpu.Backend.destroy_buffer source);get(Ogpu.Backend.destroy_buffer destination);get(Ogpu.Backend.destroy_device device);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"backend mock live-count delta";Ogpu.Backend_mock.trace control
let ()=let a=run()and b=run()in if a<>b then failwith"backend mock trace is nondeterministic";print_endline"OGPU backend boundary: deterministic submit/loss/frame/lifetime conformance passed"
