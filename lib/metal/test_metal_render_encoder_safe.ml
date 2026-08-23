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
  get
    (Render_encoder.set_blend_color encoder ~red:0. ~green:0. ~blue:0. ~alpha:1.);
  get (Render_encoder.set_depth_bias encoder ~bias:0. ~slope_scale:0. ~clamp:0.);
  get (Render_encoder.set_stencil_reference_value encoder 0l);
  get
    (Render_encoder.set_visibility_result encoder
       ~mode:Render_encoder.Visibility_disabled ~offset:0L);
  get (Render_encoder.set_vertex_texture encoder ~index:0 sampled);
  get (Render_encoder.set_fragment_texture encoder ~index:0 sampled);
  expect Parent_has_dependents (Texture.destroy sampled);
  get (Render_encoder.end_encoding encoder);
  expect Destroyed (Render_encoder.tile_width encoder);
  expect Destroyed (Render_encoder.set_cull_mode encoder Render_encoder.Cull_back);
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  get (Texture.destroy sampled);
  get (Command_buffer.destroy commands);
  get (Texture.destroy target);
  get (Command_queue.destroy queue);
  get (Device.destroy device)
