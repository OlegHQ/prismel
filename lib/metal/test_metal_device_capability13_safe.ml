open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf"%a"pp_error e)
let ()=match Device.system_default()with Error _->print_endline"device capability13: skipped"|Ok device->
  let before=get(Device.capability_snapshot device)in
  get(Device.set_maximize_concurrent_compilation device(not before.maximize_concurrent_compilation));
  let changed=get(Device.capability_snapshot device)in
  if changed.maximize_concurrent_compilation=before.maximize_concurrent_compilation then failwith"maximize mutation ignored";
  get(Device.set_maximize_concurrent_compilation device before.maximize_concurrent_compilation);
  ignore(get(Device.supports_counter_sampling device Device.Stage_boundary));
  ignore(get(Device.supports_feature_set device Feature_set.mtl_feature_set_mac_os_gpu_family1_v1));
  ignore(get(Device.supports_rasterization_rate_layers device 1L));
  get(Device.destroy device);print_endline"device capability13: query/mutation restore ok"
