let state viewport scissor : Scene_execution.state =
  {viewport;scissor;cull=Ogpu.Render_pass.Cull_none;
   depth_compare=Ogpu.Render_pass.Always;depth_write=false;
   depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;
   stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}

let () =
  let mesh:Scene_execution.mesh={key="scale";vertices=Bytes.empty;
    vertex_count=1;indices=Bytes.empty;index_count=1}in
  let draw={Scene_execution.mesh;state=state(1,2,3,4)(0,0,4,4)}in
  let one:Runtime_next.frame_facts={logical_width=4;logical_height=4;
    drawable_width=4;drawable_height=4;pixel_scale_x=1.;pixel_scale_y=1.}in
  let retina:Runtime_next.frame_facts={logical_width=4;logical_height=4;
    drawable_width=8;drawable_height=12;pixel_scale_x=2.;pixel_scale_y=3.}in
  let draws=[draw]in
  if Runtime_next.Private.scale_draws one draws!=draws then
    failwith"1x draw graph was copied";
  let sampled=[Scene_execution.Scene2,Ogpu.Pipeline.Replace,None,None,1,draw]in
  if Runtime_next.Private.scale_sampled_resources one sampled!=sampled then
    failwith"1x sampled graph was copied";
  let scaled=List.hd(Runtime_next.Private.scale_draws retina draws)in
  if scaled==draw||scaled.state.viewport<>(2,6,6,12)||
     scaled.state.scissor<>(0,0,8,12)then
    failwith"Retina draw edges were not scaled exactly";
  let unchanged={draw with state=state(0,0,0,0)(0,0,0,0)}in
  if List.hd(Runtime_next.Private.scale_draws retina[unchanged])!=unchanged then
    failwith"unchanged Retina draw was copied";
  let resized={retina with Runtime_next.drawable_width=12;drawable_height=8}in
  let changed=List.hd(Runtime_next.Private.scale_draws resized draws)in
  if changed.state.viewport<>(3,4,9,8)||changed.state.scissor<>(0,0,12,8)then
    failwith"resized nonuniform edges were not recomputed";
  print_endline"runtime_next scaling: 1x identity, Retina and resize exact"
