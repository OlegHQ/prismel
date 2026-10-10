(* Tuple shorthand for the record-based [Scene_execution.render_sampled_resources]. *)
let sampled ?texture ?auxiliary ?(samples=1) family blend draw : Scene_execution.sampled_draw =
  {family;blend;texture;auxiliary;vertex_attributes=None;samples;draw}
let render_blended ?clear r draws=Scene_execution.render_sampled_resources ?clear r
  (List.map(fun(blend,draw)->sampled Scene_execution.Scene2 blend draw)draws)
let get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let require condition message=if not condition then failwith message

let configuration:Ogpu.Surface.configuration={logical_width=64;logical_height=64;
  physical_width=64;physical_height=64;format=Rgba8_unorm;
  present_mode=Immediate;max_acquired=2;layer=None}

let state:Scene_execution.state={viewport=(0,0,64,64);scissor=(0,0,64,64);
  cull=Ogpu.Render_pass.Cull_none;depth_compare=Always;depth_write=false;
  depth_load=Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;
  stencil_load=Load;stencil_clear=0}

let mesh index:Scene_execution.mesh=
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  {key=Printf.sprintf"scratch-%03d"index;vertices;vertex_count=3;
   indices;index_count=3; primitive=Ogpu.Render_pass.Triangle_list}

let draws count=List.init count(fun index->
  ((if index land 1=0 then Ogpu.Pipeline.Replace else Alpha),
   {Scene_execution.mesh=mesh index;state}))

let with_renderer driver name body=
  match Scene_execution_fixtures.create_offscreen driver configuration with
  |Error{Ogpu.Error.kind=No_adapter;_}->Printf.printf"automatic scratch (%s): skipped (no device)\n"name
  |Error error->failwith(Ogpu.Error.to_string error)
  |Ok renderer->body renderer

let run () =
  let driver,live_handles=Ogpu.Impl.create_driver()in
  let before=live_handles()in
  with_renderer driver"retained"(fun replay_renderer->
  let stable=draws 10 in
  let retained=stable|>List.map(fun(blend,draw)->
    {Scene_execution.family=Scene2;blend;texture=None;auxiliary=None;vertex_attributes=None;
     samples=1;draw})in
  ignore(get(Scene_execution.render_prepared_sampled_resources
    ~identity:"scratch-retained"~version:7L replay_renderer retained));
  (match get(Scene_execution.replay_prepared_sampled_resources
      ~identity:"scratch-retained"~version:7L replay_renderer)with
   |Some(true,10)->()
   |_->failwith"retained replay did not return its exact draw count");
  (match get(Scene_execution.replay_prepared_sampled_resources
      ~identity:"scratch-retained"~version:8L replay_renderer)with
   |None->()
   |Some _->failwith"retained replay accepted a stale version");
  get(Scene_execution.destroy replay_renderer));
  with_renderer driver"capacity"(fun renderer->
  let over=draws 65_537 in
  (match render_blended renderer over with
   |Error error when error.Ogpu.Error.kind=Capacity->()
   |_->failwith"prepared scratch accepted more than 65,536 draws");
  get(Scene_execution.destroy renderer));
  with_renderer driver"segments"(fun renderer->
  let first={Scene_execution.mesh=mesh 70_000;state}
  and second={Scene_execution.mesh=mesh 70_001;
    state={state with depth_write=true}}in
  let stable=[{Scene_execution.family=Scene2;blend=Ogpu.Pipeline.Replace;
    texture=None;auxiliary=None;vertex_attributes=None;samples=1;draw=first};
    {Scene_execution.family=Scene3;blend=Ogpu.Pipeline.Replace;
    texture=None;auxiliary=None;vertex_attributes=None;samples=1;draw=second}]in
  ignore(get(Scene_execution.render_sampled_resources renderer stable));
  ignore(get(Scene_execution.render_sampled_resources renderer stable));
  let changed=[List.hd stable;
    {(List.nth stable 1) with draw=
      {second with state={second.state with scissor=(1,1,62,62)}}}]in
  ignore(get(Scene_execution.render_sampled_resources renderer changed));
  ignore(get(Scene_execution.render_sampled_resources renderer changed));
  get(Scene_execution.destroy renderer));
  with_renderer driver"release"(fun renderer->
  let releases=ref 0 in
  let release()=incr releases in
  let texture:Scene_execution.sampled_texture={key="lease-release";
    levels=[|{width=1;height=1;bytes=Bytes.of_string"\xff\xff\xff\xff"}|];
    sampler={label=None;min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;
      address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;
      max_anisotropy=1};gpu=None}in
  ignore(get(Scene_execution.render_sampled_resources
    ~after_prepare:release renderer
    [{Scene_execution.family=Scene2;blend=Ogpu.Pipeline.Replace;
      texture=Some texture;auxiliary=None;vertex_attributes=None;samples=1;
      draw={mesh=mesh 0;state}}]));
  require(!releases=1)"post-upload release hook did not run exactly once";
  let malformed={texture with levels=[||]}in
  (match Scene_execution.render_sampled_resources ~after_prepare:release renderer
      [{Scene_execution.family=Scene2;blend=Ogpu.Pipeline.Replace;
        texture=Some malformed;auxiliary=None;vertex_attributes=None;samples=1;
        draw={mesh=mesh 1;state}}]with
   |Error _->()|Ok _->failwith"malformed sampled texture unexpectedly rendered");
  require(!releases=2)"failed upload did not run release hook exactly once";
  get(Scene_execution.destroy renderer));
  with_renderer driver"viewport"(fun renderer->
  let oversized={state with viewport=(0,0,128,128);scissor=(16,-8,128,128)}in
  ignore(get(render_blended renderer
    [Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh 0;state=oversized}]));
  let offset={state with viewport=(100,100,8,8);scissor=(100,100,8,8)}in
  ignore(get(render_blended renderer
    [Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh 1;state=offset}]));
  get(Scene_execution.destroy renderer));
  with_renderer driver"uniforms"(fun renderer->
  let affine offset=let bytes=Bytes.make 24 '\000'in
    Bytes.set_int32_le bytes 0(Int32.bits_of_float 1.);
    Bytes.set_int32_le bytes 16(Int32.bits_of_float 1.);
    Bytes.set_int32_le bytes 8(Int32.bits_of_float offset);bytes in
  let transforms=[|affine 0.;affine 1.|]in
  let uniform_draws()=Array.to_list(Array.mapi(fun index bytes->
    Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh index;
      state={state with transform_uniforms=Some bytes}})transforms)in
  ignore(get(render_blended renderer(uniform_draws())));
  let uploaded=Scene_execution.upload_bytes renderer in
  ignore(get(render_blended renderer(uniform_draws())));
  require(Scene_execution.upload_bytes renderer=uploaded)
    "unchanged uniforms were uploaded again";
  Bytes.set_int32_le transforms.(1) 8(Int32.bits_of_float 2.);
  ignore(get(render_blended renderer(uniform_draws())));
  require(Scene_execution.upload_bytes renderer=Int64.add uploaded 48L)
    "mutated input bytes were mistaken for the completed uniform page";
  for frame=3 to 7 do
    Bytes.set_int32_le transforms.(1) 8(Int32.bits_of_float(float frame));
    ignore(get(render_blended renderer(uniform_draws())))
  done;
  get(Scene_execution.destroy renderer));
  let after=live_handles()in
  require(after=before)(Printf.sprintf"automatic scratch leaked handles %d -> %d"before after)
