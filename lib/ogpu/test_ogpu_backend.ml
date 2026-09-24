let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"backend rejection mismatch"
let cache_and_destroy_large_resource device queue weak=
  let descriptor:Ogpu.Types.buffer_descriptor=
    {label=Some"portable-cache-large";size=4_194_304L;usage=[Copy_dst]}in
  let buffer=get(Ogpu.Backend.create_buffer device descriptor)in
  Weak.set weak 0(Some buffer);
  let pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in
  get(Ogpu.Transfer_pass.fill_buffer pass(Ogpu.Backend.transfer_buffer buffer)
    ~offset:0L~length:16L~value:7);
  let command=get(Ogpu.Backend.transfer pass)in
  let receipt=get(Ogpu.Backend.submit queue command~resources:[`Buffer buffer]
    ~pipelines:[])in
  get(Ogpu.Backend.complete_through queue receipt.epoch);
  if (Ogpu.Backend.Private.submission_cache_stats queue).entries<>1 then
    failwith"large resource submission was not cached";
  get(Ogpu.Backend.destroy_buffer buffer);
  let purged=Ogpu.Backend.Private.submission_cache_stats queue in
  if purged.entries<>0||purged.retained_bytes<>0L then
    failwith"destroyed resource did not purge portable cache"
let cache_and_destroy_pipeline device queue command resources weak=
  let shader=get(Ogpu.Shader.create
    {backend="mock";label=None;bytes=Bytes.of_string"pipeline";
     entry_points=[{name="main";stage=Ogpu.Shader.Compute}];bindings=[]})in
  let layout=get(Ogpu.Binding.create_pipeline_layout
    ~device:(Ogpu.Backend.device_handle device)
    ~capabilities:(Ogpu.Backend.capabilities device)[])in
  let portable=get(Ogpu.Pipeline.create_compute(Ogpu.Backend.capabilities device)
    {backend="mock";label=Some"portable-cache-pipeline";layout;shader;
     entry="main"})in
  let pipeline=get(Ogpu.Backend.adopt_pipeline device portable)in
  Weak.set weak 0(Some pipeline);
  let receipt=get(Ogpu.Backend.submit queue command~resources
    ~pipelines:[pipeline])in
  get(Ogpu.Backend.complete_through queue receipt.epoch);
  if (Ogpu.Backend.Private.submission_cache_stats queue).entries<>1 then
    failwith"pipeline submission was not cached";
  get(Ogpu.Backend.destroy_pipeline pipeline);
  let purged=Ogpu.Backend.Private.submission_cache_stats queue in
  if purged.entries<>0||purged.retained_bytes<>0L then
    failwith"destroyed pipeline did not purge portable cache"
let run ()=
  let driver,control=Ogpu.Backend_mock.create()in let device=get(Ogpu.Backend.create_device driver)in
  let descriptor : Ogpu.Types.buffer_descriptor={label=Some"portable";size=64L;usage=[Copy_src;Copy_dst]}in
  let source=get(Ogpu.Backend.create_buffer device descriptor)and destination=get(Ogpu.Backend.create_buffer device descriptor)in
  let attachment_descriptor:Ogpu.Types.texture_descriptor={label=Some"stencil";width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment]}in
  let stencil=get(Ogpu.Backend.create_stencil_texture device attachment_descriptor)in
  let readable=get(Ogpu.Backend.create_texture device
    {attachment_descriptor with label=Some"read-into";width=2;height=2;
      usage=[Texture_copy_src]})in
  let readback=Bytes.make 16 '\255'in
  get(Ogpu.Backend.read_texture_into readable~bytes_per_row:8~destination:readback);
  if readback<>Bytes.make 16 '\000'then failwith"read-into exact bytes";
  expect Ogpu.Error.Invalid_argument
    (Ogpu.Backend.read_texture_into readable~bytes_per_row:8
       ~destination:(Bytes.create 15));
  expect Ogpu.Error.Invalid_argument(Ogpu.Backend.create_stencil_texture device{attachment_descriptor with usage=[Texture_binding]});
  let portable_source=Ogpu.Backend.transfer_buffer source and portable_destination=Ogpu.Backend.transfer_buffer destination in
  let pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in get(Ogpu.Transfer_pass.copy_buffer pass~src:portable_source~src_offset:0L~dst:portable_destination~dst_offset:0L~length:16L);let command=get(Ogpu.Backend.transfer pass)in
  let source_descriptions=[|Ogpu.Transfer_pass.Copy_buffer
    (Ogpu.Backend.buffer_id source,0L,Ogpu.Backend.buffer_id destination,0L,16L)|]in
  let snapshotted=Ogpu.Backend.Private.snapshot_command
    (Transfer source_descriptions)in
  source_descriptions.(0)<-Ogpu.Transfer_pass.Fill_buffer(Int64.max_int,0L,16L,0);
  let compute_groups=[|0,[0,Ogpu.Binding.Buffer]|]
  and compute_commands=[|Ogpu.Command.Push_debug"snapshot"|]in
  let compute_description:Ogpu.Compute_pass.description=
    {pipeline_key="snapshot";groups=compute_groups;
     dispatch=Direct{x=1;y=1;z=1};commands=compute_commands}in
  let compute_snapshot=Ogpu.Backend.Private.snapshot_command
    (Compute compute_description)in
  compute_groups.(0)<-(0,List.init 1_024(fun index->index,Ogpu.Binding.Buffer));
  compute_commands.(0)<-Ogpu.Command.Push_debug(String.make 8_192 'x');
  (match Ogpu.Backend.Private.command_view compute_snapshot with
   |Compute frozen when frozen.groups=[|0,[0,Ogpu.Binding.Buffer]|]&&
       frozen.commands=[|Ogpu.Command.Push_debug"snapshot"|]->()
   |_->failwith"compute command did not snapshot mutable source arrays");
  let snapshot_target=get(Ogpu.Backend.create_texture device
    {attachment_descriptor with label=Some"snapshot-render"})in
  let snapshot_texture=Ogpu.Backend.render_texture snapshot_target~format:Rgba8
    ~usage:Render_target in
  let snapshot_colors=[|Some({texture=snapshot_texture;resolve=None;load=Clear;
    store=Store;clear=(0.,0.,0.,1.)}:Ogpu.Render_pass.color)|]in
  let snapshot_pass=get(Ogpu.Render_pass.create(Ogpu.Backend.device_handle device)
    {colors=snapshot_colors;depth=None;stencil=None;
     viewport={x=0;y=0;width=4;height=4};
     scissor={x=0;y=0;width=4;height=4}})in
  let source_submission=get(Ogpu.Render_pass.submit snapshot_pass[])in
  let render_snapshot=Ogpu.Backend.Private.snapshot_command
    (Render source_submission)in
  snapshot_colors.(0)<-None;
  (match Ogpu.Backend.Private.command_view render_snapshot with
   |Render frozen when Ogpu.Render_pass.submission_pass frozen!=
       Ogpu.Render_pass.submission_pass source_submission&&
       Option.is_some
         (Ogpu.Render_pass.descriptor(Ogpu.Render_pass.submission_pass frozen)).colors.(0)->()
   |_->failwith"render command did not snapshot mutable pass arrays");
  get(Ogpu.Backend.destroy_texture snapshot_target);
  let bounded_resources=[`Buffer source;`Buffer destination]in
  let snapshot_queue=get(Ogpu.Backend.create_queue device)in
  let snapshot_receipt=get(Ogpu.Backend.submit snapshot_queue snapshotted
    ~resources:bounded_resources~pipelines:[])in
  get(Ogpu.Backend.complete_through snapshot_queue snapshot_receipt.epoch);
  get(Ogpu.Backend.destroy_queue snapshot_queue);
  expect Ogpu.Error.Invalid_argument
    (Ogpu.Backend.create_queue~submission_cache_byte_capacity:0L device);
  let bounded_queue=get(Ogpu.Backend.create_queue
    ~submission_cache_byte_capacity:1_000L device)in
  let initial_stats=Ogpu.Backend.Private.submission_cache_stats bounded_queue in
  if initial_stats.entries<>0||initial_stats.retained_bytes<>0L||
     initial_stats.entry_capacity<>256||initial_stats.byte_capacity<>1_000L then
    failwith"submission cache initial byte statistics";
  let oversized_pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in
  for _=1 to 24 do
    get(Ogpu.Transfer_pass.copy_buffer oversized_pass~src:portable_source
      ~src_offset:0L~dst:portable_destination~dst_offset:0L~length:16L)
  done;
  let oversized_command=get(Ogpu.Backend.transfer oversized_pass)in
  let oversized_resources=bounded_resources@
    List.init 8(fun _->`Buffer source)in
  for _=1 to 2 do
    let receipt=get(Ogpu.Backend.submit bounded_queue oversized_command
      ~resources:oversized_resources~pipelines:[])in
    get(Ogpu.Backend.complete_through bounded_queue receipt.epoch)
  done;
  if Ogpu.Backend.Private.submission_cache_stats bounded_queue<>initial_stats then
    failwith"oversized portable submission became persistent";
  let receipt=get(Ogpu.Backend.submit bounded_queue command
    ~resources:bounded_resources~pipelines:[])in
  get(Ogpu.Backend.complete_through bounded_queue receipt.epoch);
  let small_stats=Ogpu.Backend.Private.submission_cache_stats bounded_queue in
  if small_stats.entries<>1||small_stats.retained_bytes<=0L||
     small_stats.retained_bytes>small_stats.byte_capacity then
    failwith"portable submission cache retained-byte bound";
  let oversized_receipt=get(Ogpu.Backend.submit bounded_queue oversized_command
    ~resources:oversized_resources~pipelines:[])in
  get(Ogpu.Backend.complete_through bounded_queue oversized_receipt.epoch);
  if Ogpu.Backend.Private.submission_cache_stats bounded_queue<>small_stats||
     not(Ogpu.Backend.Private.submission_cache_contains bounded_queue command
       ~resources:bounded_resources~pipelines:[])then
    failwith"oversized replacement disturbed cached submission";
  expect Ogpu.Error.Invalid_argument
    (Ogpu.Backend.submit bounded_queue command~resources:[]~pipelines:[]);
  if Ogpu.Backend.Private.submission_cache_stats bounded_queue<>small_stats then
    failwith"failed portable submission mutated cache accounting";
  let extra=get(Ogpu.Backend.create_buffer device
    {descriptor with label=Some"portable-cache-extra"})in
  let receipt=get(Ogpu.Backend.submit bounded_queue command
    ~resources:[`Buffer source;`Buffer destination;`Buffer extra]~pipelines:[])in
  get(Ogpu.Backend.complete_through bounded_queue receipt.epoch);
  let grown_stats=Ogpu.Backend.Private.submission_cache_stats bounded_queue in
  if grown_stats.entries<>1||grown_stats.retained_bytes<=small_stats.retained_bytes||
     grown_stats.retained_bytes>grown_stats.byte_capacity then
    failwith"portable submission cache replacement growth accounting";
  let receipt=get(Ogpu.Backend.submit bounded_queue command
    ~resources:bounded_resources~pipelines:[])in
  get(Ogpu.Backend.complete_through bounded_queue receipt.epoch);
  if Ogpu.Backend.Private.submission_cache_stats bounded_queue<>small_stats then
    failwith"portable submission cache replacement shrink accounting";
  let distinct_pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in
  get(Ogpu.Transfer_pass.copy_buffer distinct_pass~src:portable_source~src_offset:0L
    ~dst:portable_destination~dst_offset:0L~length:16L);
  let distinct_command=get(Ogpu.Backend.transfer distinct_pass)in
  Ogpu.Backend_mock.fail_next_submission control;
  expect Ogpu.Error.Invalid_state(Ogpu.Backend.submit bounded_queue distinct_command
    ~resources:bounded_resources~pipelines:[]);
  if Ogpu.Backend.Private.submission_cache_stats bounded_queue<>small_stats||
     not(Ogpu.Backend.Private.submission_cache_contains bounded_queue command
       ~resources:bounded_resources~pipelines:[])||
     Ogpu.Backend.Private.submission_cache_contains bounded_queue distinct_command
       ~resources:bounded_resources~pipelines:[]then
    failwith"failed saturated-cache admission mutated portable cache";
  let receipt=get(Ogpu.Backend.submit bounded_queue distinct_command
    ~resources:bounded_resources~pipelines:[])in
  get(Ogpu.Backend.complete_through bounded_queue receipt.epoch);
  let evicted_stats=Ogpu.Backend.Private.submission_cache_stats bounded_queue in
  if evicted_stats.entries<>1||evicted_stats.retained_bytes<>small_stats.retained_bytes||
     evicted_stats.retained_bytes>evicted_stats.byte_capacity then
    failwith"portable submission cache byte eviction accounting";
  get(Ogpu.Backend.destroy_queue bounded_queue);
  let destroyed_stats=Ogpu.Backend.Private.submission_cache_stats bounded_queue in
  if destroyed_stats.entries<>0||destroyed_stats.retained_bytes<>0L||
     destroyed_stats.entry_capacity<>256||destroyed_stats.byte_capacity<>1_000L then
    failwith"portable submission cache teardown accounting";
  get(Ogpu.Backend.destroy_buffer extra);
  let retention_queue=get(Ogpu.Backend.create_queue device)in
  let retained_weak=Weak.create 1 in
  cache_and_destroy_large_resource device retention_queue retained_weak;
  Gc.full_major();Gc.full_major();
  if Weak.check retained_weak 0 then
    failwith"portable cache retained a destroyed driver resource closure";
  let pipeline_weak=Weak.create 1 in
  cache_and_destroy_pipeline device retention_queue command bounded_resources
    pipeline_weak;
  Gc.full_major();Gc.full_major();
  if Weak.check pipeline_weak 0 then
    failwith"portable cache retained a destroyed driver pipeline closure";
  get(Ogpu.Backend.destroy_queue retention_queue);
  let queue=get(Ogpu.Backend.create_queue device)in expect Ogpu.Error.Invalid_argument(Ogpu.Backend.submit queue command~resources:[]~pipelines:[]);
  ignore portable_source;ignore portable_destination;
  let resources=[`Buffer source;`Buffer destination]in
  let receipt=get(Ogpu.Backend.submit queue command~resources~pipelines:[])in get(Ogpu.Backend.complete_through queue receipt.epoch);
  Ogpu.Backend_mock.clear_trace control;Gc.full_major();
  let allocated0=Gc.allocated_bytes()and gc0=Gc.quick_stat()in
  for _=1 to 1_000 do
    (* Fresh list cells must still reuse the same checked handle translation. *)
    let receipt=get(Ogpu.Backend.submit queue command
      ~resources:[`Buffer source;`Buffer destination]~pipelines:[])in
    get(Ogpu.Backend.complete_through queue receipt.epoch);
    Ogpu.Backend_mock.clear_trace control
  done;
  let gc1=Gc.quick_stat()in
  let allocated=(Gc.allocated_bytes()-.allocated0)/.1_000.
  and promoted=(gc1.promoted_words-.gc0.promoted_words)*.float(Sys.word_size/8)in
  if allocated>2_000. then
    failwith(Printf.sprintf"stable queue wrapper allocated %.0f bytes/frame"allocated);
  if promoted>100_000. then
    failwith(Printf.sprintf"stable queue wrapper promoted %.0f bytes"promoted);
  for _=0 to 300 do
    let pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in
    get(Ogpu.Transfer_pass.copy_buffer pass~src:portable_source~src_offset:0L
      ~dst:portable_destination~dst_offset:0L~length:16L);
    let distinct=get(Ogpu.Backend.transfer pass)in
    let receipt=get(Ogpu.Backend.submit queue distinct~resources~pipelines:[])in
    get(Ogpu.Backend.complete_through queue receipt.epoch)
  done;
  let cache_stats=Ogpu.Backend.Private.submission_cache_stats queue in
  if cache_stats.entries<>256||cache_stats.entry_capacity<>256||
     cache_stats.retained_bytes<=0L||
     cache_stats.retained_bytes>cache_stats.byte_capacity then
    failwith(Printf.sprintf"submission cache bound changed: %d/%d, %Ld/%Ld bytes"
      cache_stats.entries cache_stats.entry_capacity cache_stats.retained_bytes
      cache_stats.byte_capacity);
  Ogpu.Backend_mock.clear_trace control;
  let config : Ogpu.Surface.configuration={logical_width=2;logical_height=2;physical_width=4;physical_height=4;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let surface=get(Ogpu.Backend.create_surface device config)in
  let presentation_descriptor={attachment_descriptor with
    label=Some"presentation-source";usage=[Texture_binding;Render_attachment]}in
  let presentation_source=get(Ogpu.Backend.create_texture device presentation_descriptor)in
  let wrong_extent=get(Ogpu.Backend.create_texture device
    {presentation_descriptor with label=Some"wrong-extent";width=3})in
  let wrong_usage=get(Ogpu.Backend.create_texture device
    {presentation_descriptor with label=Some"wrong-usage";usage=[Render_attachment]})in
  let multisampled=get(Ogpu.Backend.create_texture device
    {presentation_descriptor with label=Some"multisampled";sample_count=4})in
  let stale_source=get(Ogpu.Backend.create_texture device
    {presentation_descriptor with label=Some"stale-source"})in
  let foreign_driver,foreign_control=Ogpu.Backend_mock.create()in
  let foreign_device=get(Ogpu.Backend.create_device foreign_driver)in
  let foreign_source=get(Ogpu.Backend.create_texture foreign_device
    {presentation_descriptor with label=Some"foreign-source"})in
  let foreign_queue=get(Ogpu.Backend.create_queue foreign_device)in
  let acquire_frame ()=match get(Ogpu.Backend.acquire surface)with
    |`Acquired frame->frame
    |_->failwith"mock acquire"in
  let reject ?(present_queue=queue) source kind=
    let frame=acquire_frame()in
    expect kind(Ogpu.Backend.present~queue:present_queue~source frame);
    get(Ogpu.Backend.discard frame)
  in
  let atomic_frame=acquire_frame()in
  expect Ogpu.Error.Invalid_argument
    (Ogpu.Backend.submit_present queue command~resources:[]~pipelines:[]
      ~source:presentation_source atomic_frame);
  let atomic_receipt=get(Ogpu.Backend.submit_present queue command
    ~resources~pipelines:[]~source:presentation_source atomic_frame)in
  get(Ogpu.Backend.complete_through queue atomic_receipt.epoch);
  let synchronous_frame=acquire_frame()in
  Ogpu.Backend_mock.inject_next_completion_error control;
  let admitted=get(Ogpu.Backend.submit_present_sync queue command
    ~resources~pipelines:[]~source:presentation_source synchronous_frame)in
  (match admitted.completion with
   |Error error when error.Ogpu.Error.kind=Device_lost->()
   |_->failwith"synchronous terminal completion failure mismatch");
  if admitted.receipt.epoch<>Int64.succ atomic_receipt.epoch then
    failwith"synchronous admitted epoch did not advance exactly once";
  expect Ogpu.Error.Invalid_state
    (Ogpu.Backend.discard synchronous_frame);
  expect Ogpu.Error.Invalid_state
    (Ogpu.Backend.submit_present queue command~resources~pipelines:[]
      ~source:presentation_source atomic_frame);
  get(Ogpu.Backend.destroy_texture stale_source);
  reject stale_source Ogpu.Error.Stale_handle;
  reject foreign_source Ogpu.Error.Cross_device;
  reject~present_queue:foreign_queue presentation_source Ogpu.Error.Cross_device;
  reject wrong_extent Ogpu.Error.Invalid_argument;
  reject wrong_usage Ogpu.Error.Invalid_argument;
  reject multisampled Ogpu.Error.Invalid_argument;
  let frame=acquire_frame()in
  get(Ogpu.Backend.present~queue~source:presentation_source frame);
  expect Ogpu.Error.Invalid_state
    (Ogpu.Backend.present~queue~source:presentation_source frame);
  Ogpu.Backend_mock.fail_next_configure control;
  expect Ogpu.Error.Invalid_state
    (Ogpu.Backend.configure surface{config with physical_width=9});
  let frame=acquire_frame()in
  get(Ogpu.Backend.present~queue~source:presentation_source frame);
  let producer_queue=get(Ogpu.Backend.create_queue device)in
  let copy_source=get(Ogpu.Backend.create_texture device
    {presentation_descriptor with label=Some"copy-source";
      usage=[Texture_copy_src]})in
  let produced_source=get(Ogpu.Backend.create_texture device
    {presentation_descriptor with label=Some"produced-source";
      usage=[Texture_binding;Render_attachment;Texture_copy_dst]})in
  let copy_pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in
  let origin:Ogpu.Transfer_pass.origin={x=0;y=0;z=0}
  and extent:Ogpu.Transfer_pass.extent={width=4;height=4;depth=1}in
  get(Ogpu.Transfer_pass.copy_texture copy_pass
    ~src:(Ogpu.Backend.transfer_texture copy_source)~src_mip:0~src_origin:origin
    ~dst:(Ogpu.Backend.transfer_texture produced_source)~dst_mip:0
    ~dst_origin:origin~extent);
  let copy_command=get(Ogpu.Backend.transfer copy_pass)in
  ignore(get(Ogpu.Backend.submit producer_queue copy_command
    ~resources:[`Texture copy_source;`Texture produced_source]~pipelines:[]));
  reject produced_source Ogpu.Error.Invalid_state;
  let frame=acquire_frame()in
  get(Ogpu.Backend.present~queue:producer_queue~source:produced_source frame);
  get(Ogpu.Backend.destroy_queue producer_queue);
  reject~present_queue:producer_queue produced_source Ogpu.Error.Stale_handle;
  let frame=acquire_frame()in
  get(Ogpu.Backend.present~queue~source:produced_source frame);
  let resized={config with physical_width=5;physical_height=6}in
  get(Ogpu.Backend.configure surface resized);
  reject presentation_source Ogpu.Error.Invalid_argument;
  let resized_source=get(Ogpu.Backend.create_texture device
    {presentation_descriptor with label=Some"resized-source";width=5;height=6})in
  let frame=acquire_frame()in
  get(Ogpu.Backend.present~queue~source:resized_source frame);
  Ogpu.Backend_mock.inject_device_loss control;expect Ogpu.Error.Device_lost(Ogpu.Backend.submit queue command~resources:[`Buffer source;`Buffer destination]~pipelines:[]);
  get(Ogpu.Backend.destroy_buffer source);
  expect Ogpu.Error.Stale_handle(Ogpu.Backend.submit queue command~resources~pipelines:[]);
  expect Ogpu.Error.Invalid_state(Ogpu.Backend.destroy_device device);
  get(Ogpu.Backend.destroy_surface surface);get(Ogpu.Backend.destroy_queue queue);
  get(Ogpu.Backend.destroy_buffer source);get(Ogpu.Backend.destroy_buffer destination);
  get(Ogpu.Backend.destroy_texture stencil);get(Ogpu.Backend.destroy_texture readable);
  get(Ogpu.Backend.destroy_texture presentation_source);
  get(Ogpu.Backend.destroy_texture wrong_extent);
  get(Ogpu.Backend.destroy_texture wrong_usage);
  get(Ogpu.Backend.destroy_texture multisampled);
  get(Ogpu.Backend.destroy_texture copy_source);
  get(Ogpu.Backend.destroy_texture produced_source);
  get(Ogpu.Backend.destroy_texture resized_source);
  get(Ogpu.Backend.destroy_device device);
  get(Ogpu.Backend.destroy_texture foreign_source);
  get(Ogpu.Backend.destroy_queue foreign_queue);
  get(Ogpu.Backend.destroy_device foreign_device);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then
    failwith"backend mock live-count delta";
  if Ogpu.Backend_mock.live_counts foreign_control<>(0,0,0,0,0)then
    failwith"foreign backend mock live-count delta";
  Ogpu.Backend_mock.trace control
let ()=let a=run()and b=run()in if a<>b then failwith"backend mock trace is nondeterministic";print_endline"OGPU backend boundary: deterministic submit/loss/frame/lifetime conformance passed"
