let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let expect kind=function Error e when e.Ogpu.Error.kind=kind->()|_->failwith"backend rejection mismatch"
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
