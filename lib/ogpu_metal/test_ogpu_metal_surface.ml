open Ogpu_metal
let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let get_metal=function Ok x->x|Error e->failwith(Format.asprintf"%a"Metal.pp_error e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"wrong rejection"
let config : Ogpu.Surface.configuration={logical_width=4;logical_height=4;physical_width=4;physical_height=4;format=Bgra8_unorm;present_mode=Fifo;max_acquired=3}
let ()=match Device.system_default()with Error _->print_endline"ogpu_metal surface: skipped (no device)"|Ok device->
  let metal_device=Device.Private.metal device in let layer=get_metal(Metal.Metal_layer.create metal_device(Metal.Metal_layer.default~width:4~height:4))in let before=get_metal(Metal.Release_queue.stats())in
  expect Ogpu.Error.Invalid_argument(Surface.create device~layer{config with format=Rgba8_unorm});
  let surface=get(Surface.create device~layer config)in
  Surface.set_availability surface Force_timeout;(match get(Surface.acquire surface)with Timeout->()|_->failwith"timeout mapping");Surface.set_availability surface Force_occluded;(match get(Surface.acquire surface)with Occluded->()|_->failwith"occlusion mapping");Surface.set_availability surface Force_device_lost;(match get(Surface.acquire surface)with Device_lost->()|_->failwith"device-loss mapping");Surface.set_availability surface Available;
  for index=0 to 99 do match get(Surface.acquire surface)with Acquired frame->ignore(get(Surface.frame_texture frame));if index land 1=0 then get(Surface.present surface frame)else get(Surface.discard surface frame);expect Ogpu.Error.Invalid_state(Surface.discard surface frame)|_->failwith"drawable unavailable"done;
  let stale=match get(Surface.acquire surface)with Acquired frame->frame|_->failwith"stale setup"in let old_generation=Surface.frame_generation stale in get(Surface.resize surface~logical_width:8~logical_height:8~physical_width:8~physical_height:8);if Surface.generation surface<=old_generation then failwith"resize generation did not advance";expect Ogpu.Error.Stale_handle(Surface.present surface stale);
  expect Ogpu.Error.Invalid_state(Device.destroy device);Surface.destroy surface;if Metal.Metal_layer.destroyed layer then failwith"borrowed layer was destroyed";ignore(get_metal(Metal.Release_queue.drain()));let settled=get_metal(Metal.Release_queue.stats())in if settled.live_handles<>before.live_handles then failwith"surface drawable handle delta";
  get_metal(Metal.Metal_layer.destroy layer);get(Device.destroy device);print_endline"ogpu_metal surface: 100 frames/outcomes/resize, zero drawable-handle delta"
