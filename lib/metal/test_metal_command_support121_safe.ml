open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let run () =
  let device=get(Device.system_default())in
  get(Device.destroy device)
