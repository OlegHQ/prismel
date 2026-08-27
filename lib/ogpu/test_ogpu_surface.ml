let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected surface error"
let config={Ogpu.Surface.logical_width=64;logical_height=48;physical_width=128;physical_height=96;format=Bgra8_unorm;present_mode=Fifo;max_acquired=2}
let frame=function Ogpu.Surface.Acquired frame->frame|_->fail"expected acquired frame"
let ()=
  let device=Ogpu.Handle.create_device()in expect Ogpu.Error.Invalid_argument(Ogpu.Surface.create device{config with max_acquired=0});let surface=ok(Ogpu.Surface.create device config)in
  Ogpu.Surface.set_availability surface Force_timeout;(match ok(Ogpu.Surface.acquire surface)with Timeout->()|_->fail"timeout lost");Ogpu.Surface.set_availability surface Force_occluded;(match ok(Ogpu.Surface.acquire surface)with Occluded->()|_->fail"occlusion lost");
  Ogpu.Surface.set_availability surface Available;let first=frame(ok(Ogpu.Surface.acquire surface))and second=frame(ok(Ogpu.Surface.acquire surface))in expect Ogpu.Error.Capacity(Ogpu.Surface.acquire surface);ok(Ogpu.Surface.present surface first);expect Ogpu.Error.Invalid_state(Ogpu.Surface.present surface first);ok(Ogpu.Surface.discard surface second);expect Ogpu.Error.Invalid_state(Ogpu.Surface.discard surface second);
  let stale=frame(ok(Ogpu.Surface.acquire surface))in let before=Ogpu.Surface.generation surface in ok(Ogpu.Surface.resize surface ~logical_width:32 ~logical_height:24 ~physical_width:64 ~physical_height:48);if Ogpu.Surface.generation surface<>Int64.succ before||Ogpu.Surface.outstanding surface<>0 then fail"resize did not invalidate frames";expect Ogpu.Error.Stale_handle(Ogpu.Surface.present surface stale);
  let other=ok(Ogpu.Surface.create device config)in let foreign=frame(ok(Ogpu.Surface.acquire other))in expect Ogpu.Error.Cross_device(Ogpu.Surface.present surface foreign);Ogpu.Surface.set_availability surface Force_device_lost;(match ok(Ogpu.Surface.acquire surface)with Device_lost->()|_->fail"device loss lost");
  Ogpu.Surface.destroy surface;Ogpu.Surface.destroy surface;if not(Ogpu.Surface.destroyed surface)then fail"destroy failed";expect Ogpu.Error.Invalid_state(Ogpu.Surface.acquire surface);print_endline"OGPU surface lifecycle contract passed"
