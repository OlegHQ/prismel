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
  Printf.printf
    "automatic scratch: 1000 exact frames, 10 draws %.0f alloc/%.1f promoted B, 84 draws %.0f alloc/%.1f promoted B, capacity 65536\n%!"
    allocated10 promoted10 allocated84 promoted84
