open Metal
let fail error=failwith(Format.asprintf"%a"pp_error error)
let get=function Ok x->x|Error e->fail e
let cycles=match Sys.getenv_opt"PRISMEL_METAL_PRESENTATION_CYCLES"with
|None->10_000|Some value->let n=int_of_string value in if n<=0 then invalid_arg"presentation cycles"else n
let ()=match Device.system_default()with
|Error _->print_endline"metal presentation lifecycle: skipped (no device)"
|Ok device->
  let queue=get(Command_queue.create device)in
  let layer=get(Metal_layer.create device(Metal_layer.default~width:2~height:2))in
  let baseline=get(Release_queue.stats())in
  for _=1 to cycles do
    let drawable=match get(Drawable.acquire layer)with
      |Ok value->value|Error Drawable.Timeout_or_unavailable->failwith"drawable unavailable during lifecycle gate"in
    let texture=get(Drawable.texture drawable)in
    let commands=get(Command_buffer.create queue())in
    get(Command_buffer.present commands drawable());get(Command_buffer.commit commands);
    get(Command_buffer.wait_until_completed commands);
    get(Texture.destroy texture);get(Drawable.destroy drawable);get(Command_buffer.destroy commands)
  done;
  ignore(get(Release_queue.drain()));Gc.full_major();ignore(get(Release_queue.drain()));
  let settled=get(Release_queue.stats())in
  if settled.live_handles<>baseline.live_handles then
    failwith(Printf.sprintf"presentation lifecycle leaked %d handles"(settled.live_handles-baseline.live_handles));
  get(Metal_layer.destroy layer);get(Command_queue.destroy queue);get(Device.destroy device);
  Printf.printf"metal presentation lifecycle: %d frames, no live-handle delta\n"cycles
