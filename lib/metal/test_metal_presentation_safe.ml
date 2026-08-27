open Metal

let fail format = Printf.ksprintf failwith format
let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> fail "unexpected error: %s" (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "expected rejection"

let () =
  let device = get (Device.system_default ()) in
  let rate_layer=get(Rasterization_rate_layer.create~horizontal:[|1.|]~vertical:[|1.|])in
  get(Rasterization_rate_layer.set_sample rate_layer~vertical:false~index:0L 0.75);
  if get(Rasterization_rate_layer.sample rate_layer~vertical:false~index:0L)<>0.75 then fail "rasterization sample drift";
  let rate_descriptor=get(Rasterization_rate_descriptor.create~width:16L~height:8L~label:"rate"[|rate_layer|])in
  (match Rasterization_rate_map.create device rate_descriptor with
   | Error {kind=Unsupported;_}->()
   | Error error->fail "%s"(Format.asprintf"%a"pp_error error)
   | Ok map->
       if Rasterization_rate_map.layer_count map<>1 then fail "rasterization layer count drift";
       ignore(get(Rasterization_rate_map.physical_size map~layer:0));
       let size,alignment=Rasterization_rate_map.parameter_size_and_alignment map in
       let storage=get(Buffer.create~device~length:(Int64.add size alignment)~storage:Buffer.Shared())in
       get(Rasterization_rate_map.copy_parameters map storage~offset:0L);
       get(Buffer.destroy storage);get(Rasterization_rate_map.destroy map));
  expect Parent_has_dependents(Rasterization_rate_layer.destroy rate_layer);
  get(Rasterization_rate_descriptor.destroy rate_descriptor);
  get(Rasterization_rate_layer.destroy rate_layer);
  let queue = get (Command_queue.create device) in
  let layer = get (Metal_layer.create device (Metal_layer.default ~width:8 ~height:8)) in
  expect Unsupported
    (Metal_layer.configure layer
       { (Metal_layer.default ~width:8 ~height:8) with
         format = Texture.Rgba8_unorm
       });
  get
    (Metal_layer.configure layer
       (Metal_layer.default ~width:16 ~height:8));
  ignore(get(Metal_layer.checked_config layer));
  get(Metal_layer.set_wants_extended_range layer true);
  if not(Metal_layer.wants_extended_range layer)then fail"extended-range snapshot drift";
  get(Metal_layer.set_wants_extended_range layer false);
  expect Invalid_argument(Metal_layer.set_colorspace layer(Some "bad\000name"));
  (match Metal_layer.set_colorspace layer(Some "kCGColorSpaceSRGB")with
   |Ok()->ignore(get(Metal_layer.colorspace layer))|Error _->());
  get(Metal_layer.set_edr_metadata layer Metal_layer.Standard);
  expect Invalid_argument(Metal_layer.set_edr_metadata layer
    (Metal_layer.Hdr10{minimum_luminance=1.;maximum_luminance=0.;optical_output_scale=1.}));
  if Metal_layer.size layer <> (16, 8) then fail "layer resize snapshot drift";
  (match get (Metal_layer.preferred_device layer) with
   | Some preferred when preferred == device -> ()
   | Some _ -> fail "preferred device identity drift"
   | None -> ());
  get (Metal_layer.set_developer_hud_properties layer []);
  if get (Metal_layer.developer_hud_properties layer) <> [] then
    fail "developer HUD default/reset drift";
  ignore (get (Metal_layer.has_residency_set layer));
  let drawable =
    match get (Drawable.acquire layer) with
    | Ok drawable -> drawable
    | Error Drawable.Timeout_or_unavailable -> fail "unexpected drawable loss"
  in
  let drawable_id=get(Drawable.drawable_id drawable)in
  if drawable_id<0L then fail"drawable identifier is negative";
  ignore(get(Drawable.presented_time drawable));
  let presented=Atomic.make 0 in
  let presented_handler=get(Drawable.add_presented_handler drawable(fun~drawable_id:observed~presented_time->
    if observed<>drawable_id||not(Float.is_finite presented_time)||presented_time<0. then
      fail"invalid drawable callback snapshot";
    Atomic.incr presented))in
  let texture = get (Drawable.texture drawable) in
  if get(Drawable.checked_layer drawable)!=layer then fail"drawable parent identity drift";
  let texture_descriptor = Texture.descriptor texture in
  if texture_descriptor.width <> 16 || texture_descriptor.height <> 8 then
    fail "drawable texture metadata did not reflect the acquired texture";
  expect Parent_has_dependents (Drawable.destroy drawable);
  let commands = get (Command_buffer.create queue ()) in
  let encoded_pass =
    get (Render_pass_descriptor.create ~width:16 ~height:8 ())
  in
  let depth_stencil =
    get
      (Texture.create ~device
         (Texture.descriptor_2d ~storage:Buffer.Private
            ~usage:[ Texture.Render_target ]
            ~format:Texture.Depth32_float_stencil8 ~width:16 ~height:8 ()))
  in
  let visibility =
    get (Buffer.create ~device ~length:8L ~storage:Buffer.Shared ())
  in
  let short_visibility =
    get (Buffer.create ~device ~length:4L ~storage:Buffer.Shared ())
  in
  expect Invalid_argument
    (Render_pass_descriptor.set_attachments encoded_pass ~color:depth_stencil ());
  expect Invalid_argument
    (Render_pass_descriptor.set_attachments encoded_pass ~color:texture
       ~visibility_result:short_visibility ());
  get
    (Render_pass_descriptor.set_attachments encoded_pass ~color:texture
       ~depth:depth_stencil ~stencil:depth_stencil
       ~visibility_result:visibility ~clear:(0., 0., 0., 1.) ());
  (* Replacing an attachment retains the new graph before releasing the old
     graph, including when both identities are the same. *)
  get
    (Render_pass_descriptor.set_attachments encoded_pass ~color:texture
       ~depth:depth_stencil ~stencil:depth_stencil
       ~visibility_result:visibility ~clear:(0.1, 0.2, 0.3, 1.) ());
  (match Render_pass_descriptor.color_attachment encoded_pass with
   | Some retained when retained == texture -> ()
   | _ -> fail "render-pass color attachment snapshot drift");
  expect Parent_has_dependents (Texture.destroy texture);
  expect Parent_has_dependents (Texture.destroy depth_stencil);
  expect Parent_has_dependents (Buffer.destroy visibility);
  let before_rejection = get (Release_queue.stats ()) in
  expect Invalid_argument
    (Render_pass_descriptor.set_attachments encoded_pass ~color:texture
       ~clear:(nan, 0., 0., 1.) ());
  let after_rejection = get (Release_queue.stats ()) in
  if before_rejection.live_handles <> after_rejection.live_handles
     || before_rejection.total_created <> after_rejection.total_created then
    fail "rejected render-pass mutation changed native handle counts";
  if get(Render_pass_descriptor.checked_sizes encoded_pass)<>(16,8,1,1)then
    fail "native render-pass sizes disagree";
  let advanced : Render_pass_descriptor.advanced =
    {imageblock_sample_length=0L;threadgroup_memory_length=0L
    ;tile_width=0L;tile_height=0L
    ;visibility_result_type=Render_pass_descriptor.Disabled
    ;support_color_attachment_mapping=false
    ;sample_positions=[|(0.25,0.25);(0.75,0.75)|]} in
  get(Render_pass_descriptor.set_advanced encoded_pass advanced);
  if get(Render_pass_descriptor.advanced encoded_pass)<>advanced then
    fail "advanced render-pass round trip drift";
  let sample_attachments=get(Render_pass_descriptor.sample_attachments encoded_pass) in
  if Array.length sample_attachments<>4
     || Array.exists
          (function None->false|Some (attachment:Render_pass_descriptor.sample_attachment)->attachment.has_sample_buffer)
          sample_attachments
  then fail "default sample-buffer attachment graph drift";
  let render_counter_graph=
    match get(Counters.sets device)with
    | []->None
    | set::_->
        let descriptor=get(Counters.Descriptor.create device~set_name:set.name
          ~label:"render-pass24"~sample_count:4L~storage:Buffer.Shared())in
        let samples=get(Counters.Descriptor.create_buffer descriptor)in
        get(Counters.set_render_pass_attachment encoded_pass~index:0 samples
          ~start_vertex:0L~end_vertex:1L~start_fragment:2L~end_fragment:3L);
        let configured=get(Render_pass_descriptor.sample_attachments encoded_pass)in
        (match configured.(0)with
         | Some attachment when attachment.has_sample_buffer
             &&attachment.start_vertex=0L&&attachment.end_vertex=1L
             &&attachment.start_fragment=2L&&attachment.end_fragment=3L->()
         | _->fail "configured render sample attachment drift");
        Some(descriptor,samples)
  in
  let rate_map=get(Rasterization_rate_map.create_uniform device ~width:16L ~height:8L) in
  get(Render_pass_descriptor.set_rasterization_rate_map encoded_pass(Some rate_map));
  (match Render_pass_descriptor.rasterization_rate_map encoded_pass with
   | Some retained when retained==rate_map->()
   | _->fail "rasterization-rate map ownership graph drift");
  expect Parent_has_dependents(Rasterization_rate_map.destroy rate_map);
  get(Render_pass_descriptor.set_rasterization_rate_map encoded_pass None);
  get(Rasterization_rate_map.destroy rate_map);
  expect Invalid_argument(Render_pass_descriptor.set_advanced encoded_pass
    {advanced with sample_positions=[|(nan,0.)|]});
  get(Render_pass_descriptor.reset_depth_stencil encoded_pass);
  if Render_pass_descriptor.depth_attachment encoded_pass<>None
     ||Render_pass_descriptor.stencil_attachment encoded_pass<>None then
    fail "depth/stencil reset graph drift";
  let encoder = get (Render_encoder.create_from_pass commands encoded_pass) in
  get (Render_encoder.end_encoding encoder);
  let parallel=get(Command_buffer.create_parallel_render_encoder_with_descriptor commands encoded_pass) in
  get(Parallel_render_encoder.end_encoding parallel);
  get (Render_pass_descriptor.destroy encoded_pass);
  Option.iter(fun(_,samples)->expect Parent_has_dependents(Resource100.Sample_buffer.destroy samples))render_counter_graph;
  expect Invalid_argument
    (Command_buffer.present commands drawable ~at:(Command_buffer.At_time nan) ());
  expect Invalid_argument
    (Command_buffer.present commands drawable
       ~at:(Command_buffer.After_minimum_duration (-1.)) ());
  get (Command_buffer.present commands drawable ());
  let scheduled = Atomic.make 0 and completed = Atomic.make 0 in
  get (Command_buffer.add_scheduled_handler commands (fun () -> Atomic.incr scheduled));
  get (Command_buffer.add_completed_handler commands (fun () -> Atomic.incr completed));
  get (Command_buffer.add_completed_handler commands (fun () -> raise Exit));
  let before = get (Release_queue.stats ()) in
  expect Invalid_state (Command_buffer.present commands drawable ());
  let after = get (Release_queue.stats ()) in
  if before.total_created <> after.total_created || before.live_handles <> after.live_handles
  then fail "duplicate presentation allocated a native handle";
  expect Parent_has_dependents (Drawable.destroy drawable);
  get (Command_buffer.commit commands);
  expect Parent_has_dependents (Command_buffer.destroy commands);
  get (Command_buffer.wait_until_completed commands);
  Option.iter(fun(descriptor,samples)->get(Resource100.Sample_buffer.destroy samples);get(Counters.Descriptor.destroy descriptor))render_counter_graph;
  if Atomic.get scheduled <> 1 || Atomic.get completed <> 1 then
    fail "command callback cardinality drift";
  let deadline=Sys.time()+.5.0 in
  while Atomic.get presented=0&&Sys.time()<deadline do Unix.sleepf 0.001 done;
  if Atomic.get presented<>1 then fail"drawable presented callback cardinality drift";
  ignore(get(Drawable.presented_time drawable));
  get(Drawable.Handler.cancel presented_handler);
  get (Texture.destroy texture);
  get (Texture.destroy depth_stencil);
  get (Buffer.destroy visibility);
  get (Buffer.destroy short_visibility);
  get (Drawable.destroy drawable);
  get (Command_buffer.destroy commands);
  (* Abandoning many uncommitted Metal command buffers makes AGX report context
     leaks even when our callback tokens and roots are reclaimed.  Exercise the
     real integration once here; the native token prototype covers 10,000
     concurrent fire/cancel races without creating driver-invalid work. *)
  let before_cancel = get (Release_queue.stats ()) in
  let callback_commands = get (Command_buffer.create queue ()) in
  get (Command_buffer.add_completed_handler callback_commands (fun () -> ()));
  get (Command_buffer.destroy callback_commands);
  ignore (get (Release_queue.drain ()));
  let after_cancel = get (Release_queue.stats ()) in
  if after_cancel.live_handles <> before_cancel.live_handles then
    fail "callback cancellation leaked native handles";
  let diagnostic_commands=get(Command_buffer.create queue())in
  ignore(get(Command_buffer.diagnostics diagnostic_commands));
  expect Invalid_state(Command_buffer.pop_debug_group diagnostic_commands);
  get(Command_buffer.push_debug_group diagnostic_commands "presentation");
  get(Command_buffer.pop_debug_group diagnostic_commands);
  let event=get(Device.new_event device)in
  get(Command_buffer.encode_signal_event diagnostic_commands event~value:1L);
  get(Command_buffer.encode_wait_for_event diagnostic_commands event~value:1L);
  expect Parent_has_dependents(Event.destroy event);
  let compute=get(Command_buffer.create_compute_encoder diagnostic_commands Command_buffer.Serial)in
  get(Compute_encoder.end_encoding compute);
  ignore(get(Command_buffer.logs diagnostic_commands));
  get(Command_buffer.enqueue diagnostic_commands);
  expect Invalid_state(Command_buffer.enqueue diagnostic_commands);
  get(Command_buffer.commit diagnostic_commands);
  get(Command_buffer.wait_until_scheduled diagnostic_commands);
  get(Command_buffer.wait_until_completed diagnostic_commands);
  get(Event.destroy event);get(Command_buffer.destroy diagnostic_commands);
  let descriptor_commands=get(Command_buffer.create queue())in
  let descriptor_compute=get(Command_buffer.create_compute_encoder_with_descriptor descriptor_commands)in
  get(Compute_encoder.end_encoding descriptor_compute);
  let descriptor_blit=get(Command_buffer.create_blit_encoder_with_descriptor descriptor_commands)in
  get(Blit_encoder.end_encoding descriptor_blit);
  let descriptor_state=get(Command_buffer.create_resource_state_encoder_with_descriptor descriptor_commands)in
  get(Resource_state_encoder.end_encoding descriptor_state);
  let descriptor_acceleration=get(Command_buffer.create_acceleration_encoder_with_descriptor descriptor_commands)in
  get(Acceleration_encoder.end_encoding descriptor_acceleration);
  get(Command_buffer.commit descriptor_commands);get(Command_buffer.wait_until_completed descriptor_commands);get(Command_buffer.destroy descriptor_commands);
  let pass = get (Render_pass_descriptor.create ~width:8 ~height:8 ()) in
  if Render_pass_descriptor.size pass <> (8,8)
     || Render_pass_descriptor.array_length pass <> 1
     || Render_pass_descriptor.sample_count pass <> 1
  then fail "render-pass snapshot drift";
  get (Render_pass_descriptor.destroy pass);
  get (Metal_layer.destroy layer);
  get (Command_queue.destroy queue);
  get (Device.destroy device)
