open Metal

let fail format = Printf.ksprintf failwith format
let get = function
  | Ok value -> value
  | Error error -> fail "%s" (Format.asprintf "%a" pp_error error)

let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error ->
      fail "expected another error kind: %s" (Format.asprintf "%a" pp_error error)
  | Ok _ -> fail "expected Metal operation to fail"

let () =
  let device = get (Device.system_default ()) in
  let queue = get (Command_queue.create device) in
  let target =
    get
      (Texture.create ~device
         (Texture.descriptor_2d ~storage:Buffer.Shared
            ~usage:[ Texture.Render_target ] ~format:Texture.Bgra8_unorm
            ~width:8 ~height:8 ()))
  in
  let commands = get (Command_buffer.create queue ()) in
  let encoder = get (Render_encoder.create commands ~target ()) in
  let sampled =
    get
      (Texture.create ~device
         (Texture.descriptor_2d ~storage:Buffer.Shared
            ~usage:[ Texture.Shader_read ] ~format:Texture.Rgba8_unorm
            ~width:1 ~height:1 ()))
  in
  let sampler = get (Sampler.create ~device (Sampler.default ())) in
  let fence = get (Fence.create device) in
  let before = get (Release_queue.stats ()) in
  let tile_width = get (Render_encoder.tile_width encoder) in
  let tile_height = get (Render_encoder.tile_height encoder) in
  if tile_width <= 0 || tile_height <= 0 then fail "invalid tile dimensions";
  expect Invalid_argument
    (Render_encoder.set_viewport encoder
       { x = 0.; y = 0.; width = 9.; height = 8.; znear = 0.; zfar = 1. });
  expect Invalid_argument
    (Render_encoder.set_scissor encoder { x = 7; y = 0; width = 2; height = 8 });
  expect Invalid_argument
    (Render_encoder.set_depth_bias encoder ~bias:nan ~slope_scale:0. ~clamp:0.);
  expect Invalid_argument
    (Render_encoder.set_visibility_result encoder
       ~mode:Render_encoder.Visibility_boolean ~offset:1L);
  expect Invalid_argument
    (Render_encoder.set_vertex_texture encoder ~index:31 sampled);
  expect Invalid_argument (Render_encoder.set_vertex_bytes encoder ~index:0 Bytes.empty);
  expect Invalid_argument (Render_encoder.set_stage_bytes encoder ~stage:Render_encoder.Mesh ~index:0 Bytes.empty);
  expect Invalid_argument (Render_encoder.set_depth_bounds encoder ~minimum:0.8 ~maximum:0.2);
  expect Invalid_argument (Render_encoder.set_viewports encoder []);
  expect Invalid_argument (Render_encoder.set_scissors encoder []);
  expect Invalid_argument (Render_encoder.set_tessellation_factor_scale encoder nan);
  expect Invalid_argument (Render_encoder.set_tessellation_factor_buffer encoder ~offset:1L ~instance_stride:0L);
  expect Invalid_argument (Render_encoder.set_stage_buffer encoder ~stage:Render_encoder.Mesh ~index:0 ~offset:1L None);
  expect Invalid_argument
    (Render_encoder.set_fragment_sampler encoder ~index:0 ~lod_min:2. ~lod_max:1. sampler);
  expect Invalid_argument
    (Render_encoder.set_color_store_action encoder Render_encoder.Multisample_resolve);
  expect Invalid_state
    (Render_encoder.set_depth_store_action encoder Render_encoder.Store);
  expect Invalid_argument
    (Render_encoder.memory_barrier_resources encoder
       [ Render_encoder.Texture_resource sampled
       ; Render_encoder.Texture_resource sampled ]
       ~after:[ Render_encoder.Vertex ] ~before:[ Render_encoder.Fragment ]);
  let after = get (Release_queue.stats ()) in
  if after.total_created <> before.total_created
     || after.live_handles <> before.live_handles then
    fail "safe fixed-state rejection allocated a native handle";
  get
    (Render_encoder.set_viewport encoder
       { x = 0.; y = 0.; width = 8.; height = 8.; znear = 0.; zfar = 1. });
  get (Render_encoder.set_scissor encoder { x = 0; y = 0; width = 8; height = 8 });
  get (Render_encoder.set_cull_mode encoder Render_encoder.No_cull);
  get
    (Render_encoder.set_front_facing_winding encoder
       Render_encoder.Counter_clockwise);
  get (Render_encoder.set_triangle_fill_mode encoder Render_encoder.Fill);
  get (Render_encoder.set_color_store_action encoder Render_encoder.Store);
  get (Render_encoder.set_color_store_options encoder ~custom_sample_positions:false ());
  get
    (Render_encoder.set_blend_color encoder ~red:0. ~green:0. ~blue:0. ~alpha:1.);
  get (Render_encoder.set_depth_bias encoder ~bias:0. ~slope_scale:0. ~clamp:0.);
  get (Render_encoder.set_stencil_reference_value encoder 0l);
  get
    (Render_encoder.set_visibility_result encoder
       ~mode:Render_encoder.Visibility_disabled ~offset:0L);
  get (Render_encoder.set_vertex_texture encoder ~index:0 sampled);
  get (Render_encoder.set_fragment_texture encoder ~index:0 sampled);
  get (Render_encoder.set_vertex_bytes encoder ~index:2 (Bytes.make 8 '\000'));
  get (Render_encoder.set_fragment_bytes encoder ~index:2 (Bytes.make 16 '\000'));
  get (Render_encoder.set_stage_bytes encoder ~stage:Render_encoder.Vertex ~index:3 (Bytes.make 8 '\000'));
  expect Unsupported (Render_encoder.set_stage_texture encoder ~stage:Render_encoder.Fragment ~index:1 (Some sampled));
  get (Render_encoder.set_stage_textures encoder ~stage:Render_encoder.Fragment ~start:1 [Some sampled]);
  get (Render_encoder.set_stage_sampler encoder ~stage:Render_encoder.Tile ~index:1 (Some sampler));
  get (Render_encoder.set_depth_clip_mode encoder ~clamp:false);
  get (Render_encoder.set_depth_bounds encoder ~minimum:0. ~maximum:1.);
  get (Render_encoder.set_viewports encoder [{x=0.;y=0.;width=8.;height=8.;znear=0.;zfar=1.}]);
  get (Render_encoder.set_scissors encoder [{x=0;y=0;width=8;height=8}]);
  get (Render_encoder.set_tessellation_factor_scale encoder 1.);
  get (Render_encoder.set_vertex_sampler encoder ~index:0 sampler);
  get
    (Render_encoder.set_fragment_sampler encoder ~index:0 ~lod_min:0. ~lod_max:1.
       sampler);
  get (Render_encoder.memory_barrier encoder ~scope:[ Render_encoder.Textures ]
         ~after:[ Render_encoder.Vertex ] ~before:[ Render_encoder.Fragment ]);
  get (Render_encoder.memory_barrier_resources encoder
         [ Render_encoder.Texture_resource sampled ]
         ~after:[ Render_encoder.Vertex ] ~before:[ Render_encoder.Fragment ]);
  get (Render_encoder.use_resource encoder (Render_encoder.Texture_resource sampled)
         ~usage:[ Render_encoder.Read; Render_encoder.Sample ]
         ~stages:[ Render_encoder.Fragment ]);
  get (Render_encoder.update_fence encoder fence ~after:[ Render_encoder.Fragment ]);
  expect Parent_has_dependents (Texture.destroy sampled);
  expect Parent_has_dependents (Sampler.destroy sampler);
  expect Parent_has_dependents (Fence.destroy fence);
  get (Render_encoder.end_encoding encoder);
  expect Destroyed (Render_encoder.tile_width encoder);
  expect Destroyed (Render_encoder.set_cull_mode encoder Render_encoder.Cull_back);
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  get (Texture.destroy sampled);
  get (Sampler.destroy sampler);
  get (Fence.destroy fence);
  get (Command_buffer.destroy commands);
  let depth = get (Texture.create ~device
    (Texture.descriptor_2d ~storage:Buffer.Private ~usage:[Texture.Render_target]
       ~format:Texture.Depth32_float ~width:8 ~height:8 ())) in
  let stencil = get (Texture.create ~device
    (Texture.descriptor_2d ~storage:Buffer.Private ~usage:[Texture.Render_target]
       ~format:Texture.Stencil8 ~width:8 ~height:8 ())) in
  let commands = get (Command_buffer.create queue ()) in
  let encoder = get (Render_encoder.create commands ~target ~depth ~stencil ()) in
  get (Render_encoder.set_depth_store_action encoder Render_encoder.Store);
  get (Render_encoder.set_depth_store_options encoder ~custom_sample_positions:false ());
  get (Render_encoder.set_stencil_store_action encoder Render_encoder.Store);
  get (Render_encoder.set_stencil_store_options encoder ~custom_sample_positions:false ());
  get (Render_encoder.end_encoding encoder);
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  get (Command_buffer.destroy commands);
  get (Texture.destroy depth);
  get (Texture.destroy stencil);
  get (Texture.destroy target);
  get (Command_queue.destroy queue);
  get (Device.destroy device)
