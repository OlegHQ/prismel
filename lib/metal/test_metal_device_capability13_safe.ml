open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let run ()=match Device.system_default()with Error _->print_endline"device capability13: skipped"|Ok device->
  ignore(get(Device.supports_counter_sampling device Device.Stage_boundary));
  ignore(get(Device.supports_feature_set device Feature_set.mtl_feature_set_mac_os_gpu_family1_v1));
  get(Device.destroy device);print_endline"device capability13: queries ok"
