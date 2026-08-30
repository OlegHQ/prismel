let get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)
let require condition message=if not condition then failwith message

let configuration:Ogpu.Surface.configuration={logical_width=64;logical_height=64;
  physical_width=64;physical_height=64;format=Rgba8_unorm;
  present_mode=Immediate;max_acquired=2}

let state:Scene_execution.state={viewport=(0,0,64,64);scissor=(0,0,64,64);
  cull=Ogpu.Render_pass.Cull_none;depth_compare=Always;depth_write=false;
  depth_load=Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;
  stencil_load=Load;stencil_clear=0}

let mesh index:Scene_execution.mesh=
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  {key=Printf.sprintf"scratch-%03d"index;vertices;vertex_count=3;
   indices;index_count=3}

let draws count=List.init count(fun index->
  ((if index land 1=0 then Ogpu.Pipeline.Replace else Alpha),
   {Scene_execution.mesh=mesh index;state}))

let only_render_trace control=
  Ogpu.Backend_mock.trace control|>List.filter(fun entry->
    String.starts_with~prefix:"render:"entry)

let run_case count=
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create driver configuration)in
  let stable=draws count in
  for _=1 to 4 do ignore(get(Scene_execution.render_blended renderer stable))done;
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_blended renderer stable));
  let expected=only_render_trace control in
  require(List.length expected=1)(Printf.sprintf"%d-draw pass cardinality"count);
  Ogpu.Backend_mock.clear_trace control;
  Gc.full_major();
  let allocated_before=Gc.allocated_bytes()and gc_before=Gc.quick_stat()in
  for frame=1 to 1_000 do
    ignore(get(Scene_execution.render_blended renderer stable));
    if List.mem frame[1;2;60;1_000]then
      require(only_render_trace control=expected)
        (Printf.sprintf"%d-draw exact trace drift at frame %d"count frame);
    Ogpu.Backend_mock.clear_trace control
  done;
  let gc_after=Gc.quick_stat()in
  let allocated=(Gc.allocated_bytes()-.allocated_before)/.1_000.
  and promoted=(gc_after.promoted_words-.gc_before.promoted_words)*.
    float(Sys.word_size/8)/.1_000. in
  let changed=List.mapi(fun index (blend,draw)->blend,
    if index=count/2 then
      {draw with Scene_execution.state={state with scissor=(1,1,62,62)}}else draw)stable in
  ignore(get(Scene_execution.render_blended renderer changed));
  require(only_render_trace control<>expected)
    (Printf.sprintf"%d-draw changed state reused stale command"count);
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_blended renderer stable));
  require(only_render_trace control=expected)
    (Printf.sprintf"%d-draw restored order did not recover exact command"count);
  let transient=Weak.create 1 in
  let ()=
    let draw={Scene_execution.mesh=mesh(count+1_000);
      state={state with scissor=(2,2,60,60)}}in
    Weak.set transient 0(Some draw);
    ignore(get(Scene_execution.render_blended renderer[Ogpu.Pipeline.Replace,draw]))
  in
  Gc.full_major();
  require(Weak.get transient 0=None)
    (Printf.sprintf"%d-draw one-hit submission retained its draw graph"count);
  (* A compact candidate may authorize admission, but only an exact retained
     signature may replay.  Two equal frames admit; the following frame reuses
     the admitted command without accepting the intervening transient. *)
  let stable_again=draws count in
  ignore(get(Scene_execution.render_blended renderer stable_again));
  ignore(get(Scene_execution.render_blended renderer stable_again));
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_blended renderer stable_again));
  require(only_render_trace control=expected)
    (Printf.sprintf"%d-draw two-hit admission did not preserve stable replay"count);
  get(Scene_execution.destroy renderer);
  require(Ogpu.Backend_mock.live_counts control=(0,0,0,0,0))
    (Printf.sprintf"%d-draw mock handle delta"count);
  allocated,promoted

let ()=
  let allocated10,promoted10=run_case 10
  and allocated84,promoted84=run_case 84 in
  (* The mock backend deliberately formats a complete render trace each frame;
     these ceilings include that diagnostic work as well as Scene execution. *)
  require(allocated10<80_000.)
    (Printf.sprintf"10-draw stable allocation %.0f B/frame"allocated10);
  require(allocated84<600_000.)
    (Printf.sprintf"84-draw stable allocation %.0f B/frame"allocated84);
  require(promoted10<512.)
    (Printf.sprintf"10-draw stable promotion %.1f B/frame"promoted10);
  require(promoted84<2_048.)
    (Printf.sprintf"84-draw stable promotion %.1f B/frame"promoted84);
  let driver,replay_control=Ogpu.Backend_mock.create()in
  let replay_renderer=get(Scene_execution.create driver configuration)in
  let stable=draws 10 in
  let retained=stable|>List.map(fun(blend,draw)->
    Scene_execution.Scene2,blend,None,None,1,draw)in
  ignore(get(Scene_execution.render_prepared_sampled_resources
    ~identity:"scratch-retained"~version:7L replay_renderer retained));
  Ogpu.Backend_mock.clear_trace replay_control;
  (match get(Scene_execution.replay_prepared_sampled_resources
      ~identity:"scratch-retained"~version:7L replay_renderer)with
   |Some(true,10)->()
   |_->failwith"retained replay did not return its exact draw count");
  require(List.length(only_render_trace replay_control)=1)
    "retained replay did not submit the cached command";
  Ogpu.Backend_mock.inject_next_completion_error replay_control;
  Ogpu.Backend_mock.clear_trace replay_control;
  (match Scene_execution.render_blended replay_renderer stable with
   |Error error when error.Ogpu.Error.kind=Device_lost->()
   |_->failwith"terminal completion failure was not reported");
  let terminal_trace=Ogpu.Backend_mock.trace replay_control in
  require(List.exists(String.starts_with~prefix:"submit-present:")terminal_trace)
    "terminal failure was not admitted";
  require(List.exists(String.starts_with~prefix:"complete:")terminal_trace)
    "terminal failure did not commit its epoch";
  require(not(List.mem"discard"terminal_trace))
    "admitted terminal failure discarded an already-consumed frame";
  Ogpu.Backend_mock.clear_trace replay_control;
  ignore(get(Scene_execution.render_blended replay_renderer stable));
  require(List.exists(String.starts_with~prefix:"submit-present:")
      (Ogpu.Backend_mock.trace replay_control))
    "renderer did not acquire the exact next frame after terminal failure";
  (match get(Scene_execution.replay_prepared_sampled_resources
      ~identity:"scratch-retained"~version:8L replay_renderer)with
   |None->()
   |Some _->failwith"retained replay accepted a stale version");
  get(Scene_execution.destroy replay_renderer);
  require(Ogpu.Backend_mock.live_counts replay_control=(0,0,0,0,0))
    "retained replay leaked mock handles";
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create driver configuration)in
  let over=draws 65_537 in
  Ogpu.Backend_mock.clear_trace control;
  (match Scene_execution.render_blended renderer over with
   |Error error when error.Ogpu.Error.kind=Capacity->()
   |_->failwith"prepared scratch accepted more than 65,536 draws");
  require(Ogpu.Backend_mock.trace control=[])
    "prepared scratch capacity rejection reached the backend";
  get(Scene_execution.destroy renderer);
  require(Ogpu.Backend_mock.live_counts control=(0,0,0,0,0))
    "prepared scratch capacity rejection leaked handles";
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create_variants driver configuration)in
  let first={Scene_execution.mesh=mesh 70_000;state}
  and second={Scene_execution.mesh=mesh 70_001;
    state={state with depth_write=true}}in
  let stable=[Scene_execution.Scene2,Ogpu.Pipeline.Replace,None,None,1,first;
    Scene_execution.Scene3,Ogpu.Pipeline.Replace,None,None,1,second]in
  ignore(get(Scene_execution.render_sampled_resources renderer stable));
  ignore(get(Scene_execution.render_sampled_resources renderer stable));
  let builds0,reuses0=Scene_execution.Private.retained_batch_stats renderer in
  let changed=[List.hd stable;
    Scene_execution.Scene3,Ogpu.Pipeline.Replace,None,None,1,
      {second with state={second.state with scissor=(1,1,62,62)}}]in
  ignore(get(Scene_execution.render_sampled_resources renderer changed));
  let builds1,reuses1=Scene_execution.Private.retained_batch_stats renderer in
  require(reuses1>reuses0&&builds1>builds0)
    (Printf.sprintf
      "changed second segment did not reuse stable first batch: %Ld/%Ld -> %Ld/%Ld"
      builds0 reuses0 builds1 reuses1);
  get(Scene_execution.destroy renderer);
  require(Ogpu.Backend_mock.live_counts control=(0,0,0,0,0))
    "retained batch segment test leaked handles";
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create driver configuration)in
  let releases=ref 0 in
  let release()=incr releases in
  let texture:Scene_execution.sampled_texture={key="lease-release";
    levels=[|{width=1;height=1;bytes=Bytes.of_string"\xff\xff\xff\xff"}|];
    sampler={label=None;min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;
      address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;
      max_anisotropy=1}}in
  ignore(get(Scene_execution.render_sampled_resources
    ~after_prepare:release renderer
    [Scene_execution.Scene2,Ogpu.Pipeline.Replace,Some texture,None,1,
     {Scene_execution.mesh=mesh 0;state}]));
  require(!releases=1)"post-upload release hook did not run exactly once";
  let malformed={texture with levels=[||]}in
  (match Scene_execution.render_sampled_resources ~after_prepare:release renderer
      [Scene_execution.Scene2,Ogpu.Pipeline.Replace,Some malformed,None,1,
       {Scene_execution.mesh=mesh 1;state}]with
   |Error _->()|Ok _->failwith"malformed sampled texture unexpectedly rendered");
  require(!releases=2)"failed upload did not run release hook exactly once";
  get(Scene_execution.destroy renderer);
  require(Ogpu.Backend_mock.live_counts control=(0,0,0,0,0))
    "post-upload release hook test leaked mock handles";
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create driver configuration)in
  let oversized={state with viewport=(0,0,128,128);scissor=(16,-8,128,128)}in
  ignore(get(Scene_execution.render_blended renderer
    [Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh 0;state=oversized}]));
  let offset={state with viewport=(100,100,8,8);scissor=(100,100,8,8)}in
  ignore(get(Scene_execution.render_blended renderer
    [Ogpu.Pipeline.Replace,{Scene_execution.mesh=mesh 1;state=offset}]));
  get(Scene_execution.destroy renderer);
  require(Ogpu.Backend_mock.live_counts control=(0,0,0,0,0))
    "oversized viewport clamp leaked mock handles";
  Printf.printf
    "automatic scratch: 1000 exact frames, 10 draws %.0f alloc/%.1f promoted B, 84 draws %.0f alloc/%.1f promoted B, capacity 65536\n%!"
    allocated10 promoted10 allocated84 promoted84
