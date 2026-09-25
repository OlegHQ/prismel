(* Tuple shorthand for the record-based [Scene_execution.render_sampled_resources]. *)
let sampled ?texture ?auxiliary ?(samples=1) family blend draw : Scene_execution.sampled_draw =
  {family;blend;texture;auxiliary;samples;draw}
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

let run_case driver count=
  let allocated=ref 0. and promoted=ref 0. in
  with_renderer driver(string_of_int count)(fun renderer->
  let stable=draws count in
  for _=1 to 4 do ignore(get(render_blended renderer stable))done;
  let stats0=Scene_execution.retained_stats renderer in
  require(stats0.plan_entries>=1)(Printf.sprintf"%d-draw stable frames did not admit a retained plan"count);
  Gc.full_major();
  let allocated_before=Gc.allocated_bytes()and gc_before=Gc.quick_stat()in
  for _=1 to 1_000 do
    ignore(get(render_blended renderer stable))
  done;
  let gc_after=Gc.quick_stat()in
  allocated:=(Gc.allocated_bytes()-.allocated_before)/.1_000.;
  promoted:=(gc_after.promoted_words-.gc_before.promoted_words)*.
    float(Sys.word_size/8)/.1_000.;
  let stats1=Scene_execution.retained_stats renderer in
  require(Int64.sub stats1.plan_hits stats0.plan_hits=1_000L&&stats1.plan_builds=stats0.plan_builds)
    (Printf.sprintf"%d-draw stable frames rebuilt plans: hits %Ld->%Ld builds %Ld->%Ld"
      count stats0.plan_hits stats1.plan_hits stats0.plan_builds stats1.plan_builds);
  let changed=List.mapi(fun index (blend,draw)->blend,
    if index=count/2 then
      {draw with Scene_execution.state={state with scissor=(1,1,62,62)}}else draw)stable in
  ignore(get(render_blended renderer changed));
  let stats2=Scene_execution.retained_stats renderer in
  require(stats2.plan_misses>stats1.plan_misses)
    (Printf.sprintf"%d-draw changed state replayed a stale plan"count);
  ignore(get(render_blended renderer stable));
  ignore(get(render_blended renderer stable));
  let stats3=Scene_execution.retained_stats renderer in
  ignore(get(render_blended renderer stable));
  let stats4=Scene_execution.retained_stats renderer in
  require(stats4.plan_hits=Int64.succ stats3.plan_hits)
    (Printf.sprintf"%d-draw restored order did not recover a retained plan"count);
  let transient=Weak.create 1 in
  let ()=
    let draw={Scene_execution.mesh=mesh(count+1_000);
      state={state with scissor=(2,2,60,60)}}in
    Weak.set transient 0(Some draw);
    ignore(get(render_blended renderer[Ogpu.Pipeline.Replace,draw]))
  in
  Gc.full_major();
  require(Weak.get transient 0=None)
    (Printf.sprintf"%d-draw one-hit submission retained its draw graph"count);
  get(Scene_execution.destroy renderer));
  !allocated,!promoted

let run () =
  let driver,live_handles=Ogpu.Impl.create_driver()in
  let before=live_handles()in
  let allocated10,promoted10=run_case driver 10
  and allocated84,promoted84=run_case driver 84 in
  (* Replayed frames encode one indirect execution per batch; ceilings cover
     Scene execution plus the driver's per-frame closures. *)
  require(allocated10<200_000.)
    (Printf.sprintf"10-draw stable allocation %.0f B/frame"allocated10);
  require(allocated84<400_000.)
    (Printf.sprintf"84-draw stable allocation %.0f B/frame"allocated84);
  require(promoted10<4_096.)
    (Printf.sprintf"10-draw stable promotion %.1f B/frame"promoted10);
  require(promoted84<8_192.)
    (Printf.sprintf"84-draw stable promotion %.1f B/frame"promoted84);
  with_renderer driver"retained"(fun replay_renderer->
  let stable=draws 10 in
  let retained=stable|>List.map(fun(blend,draw)->
    {Scene_execution.family=Scene2;blend;texture=None;auxiliary=None;
     samples=1;draw})in
  ignore(get(Scene_execution.render_prepared_sampled_resources
    ~identity:"scratch-retained"~version:7L replay_renderer retained));
  let stats0=Scene_execution.retained_stats replay_renderer in
  (match get(Scene_execution.replay_prepared_sampled_resources
      ~identity:"scratch-retained"~version:7L replay_renderer)with
   |Some(true,10)->()
   |_->failwith"retained replay did not return its exact draw count");
  let stats1=Scene_execution.retained_stats replay_renderer in
  require(stats1.plan_executions>stats0.plan_executions)
    "retained replay did not execute the cached indirect commands";
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
    texture=None;auxiliary=None;samples=1;draw=first};
    {Scene_execution.family=Scene3;blend=Ogpu.Pipeline.Replace;
    texture=None;auxiliary=None;samples=1;draw=second}]in
  ignore(get(Scene_execution.render_sampled_resources renderer stable));
  ignore(get(Scene_execution.render_sampled_resources renderer stable));
  let stats=Scene_execution.retained_stats renderer in
  require(stats.plan_entries=2&&stats.plan_builds>=2L)
    (Printf.sprintf"two-segment frame did not retain both batches: entries %d builds %Ld"
      stats.plan_entries stats.plan_builds);
  let changed=[List.hd stable;
    {(List.nth stable 1) with draw=
      {second with state={second.state with scissor=(1,1,62,62)}}}]in
  ignore(get(Scene_execution.render_sampled_resources renderer changed));
  ignore(get(Scene_execution.render_sampled_resources renderer changed));
  let stats2=Scene_execution.retained_stats renderer in
  require(stats2.plan_evictions>stats.plan_evictions)
    "changed second segment did not drop the stale plan";
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
      texture=Some texture;auxiliary=None;samples=1;
      draw={mesh=mesh 0;state}}]));
  require(!releases=1)"post-upload release hook did not run exactly once";
  let malformed={texture with levels=[||]}in
  (match Scene_execution.render_sampled_resources ~after_prepare:release renderer
      [{Scene_execution.family=Scene2;blend=Ogpu.Pipeline.Replace;
        texture=Some malformed;auxiliary=None;samples=1;
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
  require(after=before)(Printf.sprintf"automatic scratch leaked handles %d -> %d"before after);
  Printf.printf
    "automatic scratch: 1000 replayed frames, 10 draws %.0f alloc/%.1f promoted B, 84 draws %.0f alloc/%.1f promoted B, capacity 65536, zero delta\n%!"
    allocated10 promoted10 allocated84 promoted84
