open Metal
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a" pp_error e)
let expect kind=function Error e when e.kind=kind->()|Error e->failwith(Format.asprintf "%a" pp_error e)|Ok _->failwith"expected rejection"
let ()=match Device.system_default()with
|Error _->print_endline"MTL4RenderPass7 safe: skipped"
|Ok device->
 match Command4.Render_pass_descriptor.create device~width:4~height:4()with
 |Error e when e.kind=Unsupported||e.kind=Native_error->ignore(Device.destroy device);print_endline"MTL4RenderPass7 safe: skipped (Metal4 unavailable)"
 |Error e->failwith(Format.asprintf "%a" pp_error e)
 |Ok pass->
  let samples=get(Command4.Render_pass_descriptor.create device~width:4~height:4~sample_count:2())in
  get(Command4.Render_pass_descriptor.set_sample_positions samples[|(0.25,0.25);(0.75,0.75)|]);
  if Command4.Render_pass_descriptor.sample_positions samples<>[|(0.25,0.25);(0.75,0.75)|]then failwith"sample snapshot";
  expect Invalid_argument(Command4.Render_pass_descriptor.set_sample_positions samples[|(0.,0.)|]);
  let map=get(Rasterization_rate_map.create_uniform device~width:4L~height:4L)in
  get(Command4.Render_pass_descriptor.set_rasterization_rate_map pass(Some map));
  (match Command4.Render_pass_descriptor.rasterization_rate_map pass with
   | Some retained when retained == map -> ()
   | _ -> failwith "rate-map identity");
  let texture format=Texture.create~device(Texture.descriptor_2d~storage:Buffer.Private~usage:[Texture.Render_target]~format~width:4~height:4())in
  let depth=get(texture Texture.Depth32_float)and stencil=get(texture Texture.Stencil8)in
  get(Command4.Render_pass_descriptor.set_depth_attachment pass(Some(Command4.Render_encoder.depth_attachment depth)));
  get(Command4.Render_pass_descriptor.set_stencil_attachment pass(Some(Command4.Render_encoder.stencil_attachment stencil)));
  expect Parent_has_dependents(Texture.destroy depth);expect Parent_has_dependents(Texture.destroy stencil);expect Parent_has_dependents(Rasterization_rate_map.destroy map);
  get(Command4.Render_pass_descriptor.set_depth_attachment pass None);get(Command4.Render_pass_descriptor.set_stencil_attachment pass None);get(Command4.Render_pass_descriptor.set_rasterization_rate_map pass None);
  get(Texture.destroy depth);get(Texture.destroy stencil);get(Rasterization_rate_map.destroy map);get(Command4.Render_pass_descriptor.destroy samples);get(Command4.Render_pass_descriptor.destroy pass);get(Device.destroy device);
  print_endline"MTL4RenderPass7 safe: exact7 ownership/device/count validation passed"
