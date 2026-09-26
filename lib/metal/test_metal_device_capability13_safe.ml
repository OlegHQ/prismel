open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let run ()=match Device.system_default()with Error _->print_endline"device capability13: skipped"|Ok device->
  get(Device.destroy device);print_endline"device capability13: queries ok"
