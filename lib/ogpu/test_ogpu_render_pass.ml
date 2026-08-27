let fail message=raise(Failure message)
let ok=function Ok value->value|Error e->fail(Ogpu.Error.to_string e)
let expect kind=function Error(e:Ogpu.Error.t)when e.kind=kind->()|_->fail"unexpected render-pass result"
let ()=
  let device=Ogpu.Handle.create_device()in let make id format samples usage={Ogpu.Render_pass.id;handle=Ogpu.Handle.create ~device;format;samples;width=64;height=64;usage}in
  let color=make 1L Rgba8 4[Render_target]and resolve=make 2L Rgba8 1[Resolve_target]in let attachment={Ogpu.Render_pass.texture=color;resolve=Some resolve;load=Clear;store=Resolve;clear=(0.,0.5,1.,1.)}in let rect={Ogpu.Render_pass.x=0;y=0;width=64;height=64}in let descriptor={Ogpu.Render_pass.colors=[|Some attachment|];depth=None;stencil=None;viewport=rect;scissor=rect}in
  let pass=ok(Ogpu.Render_pass.create device descriptor)in let command=Ogpu.Command.begin_encoder()in ok(Ogpu.Render_pass.encode pass command);ok(Ogpu.Command.end_encoder command);let descriptions=Ogpu.Command.descriptions command in
  if Ogpu.Render_pass.raster_state pass<>Ogpu.Render_pass.default_raster_state then fail"default raster state changed";
  if Ogpu.Render_pass.stencil_state pass<>None then fail"default stencil state changed";
  let depth=make 5L Depth32 4[Render_target]in
  let depth_attachment:Ogpu.Render_pass.depth={texture=depth;load=Clear;store=Store;clear=0.25}in
  let raster_state:Ogpu.Render_pass.raster_state={cull=Cull_back;depth_compare=Greater_equal;depth_write=true}in
  let typed=ok(Ogpu.Render_pass.create~raster_state device{descriptor with depth=Some depth_attachment})in
  if Ogpu.Render_pass.raster_state typed<>raster_state then fail"typed raster state changed";
  expect Ogpu.Error.Invalid_argument(Ogpu.Render_pass.create~raster_state device descriptor);
  expect Ogpu.Error.Invalid_argument(Ogpu.Render_pass.create~stencil_state:Ogpu.Render_pass.default_stencil_state device descriptor);
  let stencil=make 6L Stencil8 4[Render_target]in
  let stencil_attachment:Ogpu.Render_pass.stencil={texture=stencil;load=Clear;store=Store;clear=23}in
  let face:Ogpu.Render_pass.stencil_face={compare=Not_equal;stencil_fail=Replace;depth_fail=Increment_clamp;pass=Invert;read_mask=0x0fl;write_mask=0xf0l}in
  let stencil_state:Ogpu.Render_pass.stencil_state={front=face;back={face with compare=Less;pass=Decrement_wrap};front_reference=7l;back_reference=11l}in
  let stencil_pass=ok(Ogpu.Render_pass.create~stencil_state device{descriptor with stencil=Some stencil_attachment})in
  if Ogpu.Render_pass.stencil_state stencil_pass<>Some stencil_state then fail"typed stencil state changed";
  (match Array.to_list descriptions with
  |[Ogpu.Command.Begin_encoder;Begin_pass Render;Declare_resource{resource_id=1L;_};Declare_resource{resource_id=2L;_};End_pass Render;End_encoder]->()
  |_->fail"render declaration sequence changed");
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"typed";min_filter=Nearest;mag_filter=Linear;mip_filter=Linear_mip;address_u=Repeat;address_v=Mirror_repeat;lod_min=0.;lod_max=4.;max_anisotropy=1}in
  let draw:Ogpu.Render_pass.draw={pipeline_key="p";buffers=[{stage=Ogpu.Command.Fragment;index=0;buffer_id=3L;offset=0L}];textures=[{stage=Ogpu.Command.Fragment;index=0;texture_id=4L}];samplers=[{stage=Ogpu.Command.Fragment;index=0;sampler}];primitive=Triangle_list;vertex_start=0;vertex_count=3;index=None}in
  ignore(ok(Ogpu.Render_pass.submit pass[draw]));
  expect Ogpu.Error.Invalid_argument(Ogpu.Render_pass.submit pass[{draw with samplers=draw.samplers@draw.samplers}]);
  expect Ogpu.Error.Invalid_argument(Ogpu.Render_pass.submit pass[{draw with samplers=[{stage=Ogpu.Command.Fragment;index=0;sampler={sampler with lod_min=nan}}]}]);
  expect Ogpu.Error.Invalid_argument(Ogpu.Render_pass.create device{descriptor with colors=Array.make 9 None});expect Ogpu.Error.Invalid_argument(Ogpu.Render_pass.create device{descriptor with colors=[|Some{attachment with resolve=Some color}|]});expect Ogpu.Error.Invalid_argument(Ogpu.Render_pass.create device{descriptor with viewport={rect with width=65}});Ogpu.Handle.destroy color.handle;expect Ogpu.Error.Stale_handle(Ogpu.Render_pass.create device descriptor);print_endline"OGPU render-pass descriptor validation passed"
