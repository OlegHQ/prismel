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

let depth_actions device =
  let pass = get (Render_pass_descriptor.create ~width:4 ~height:4 ()) in
  let color = get (Texture.create ~device (Texture.descriptor_2d ~storage:Buffer.Private
    ~usage:[Texture.Render_target] ~format:Texture.Bgra8_unorm ~width:4 ~height:4 ())) in
  let depth = get (Texture.create ~device (Texture.descriptor_2d ~storage:Buffer.Private
    ~usage:[Texture.Render_target] ~format:Texture.Depth32_float ~width:4 ~height:4 ())) in
  get (Render_pass_descriptor.set_attachments pass ~color ~depth ());
  get (Render_pass_descriptor.set_depth_stencil_actions pass
    ~depth:(Render_pass_descriptor.Load, Render_pass_descriptor.Store, 0.5)
    ~stencil:(Render_pass_descriptor.Clear, Render_pass_descriptor.Store_dont_care, 0));
  expect Invalid_argument (Render_pass_descriptor.set_depth_stencil_actions pass
    ~depth:(Render_pass_descriptor.Load, Render_pass_descriptor.Store, 1.5)
    ~stencil:(Render_pass_descriptor.Clear, Render_pass_descriptor.Store, 0));
  expect Invalid_argument (Render_pass_descriptor.set_depth_stencil_actions pass
    ~depth:(Render_pass_descriptor.Load, Render_pass_descriptor.Store, 0.)
    ~stencil:(Render_pass_descriptor.Clear, Render_pass_descriptor.Store, 256));
  get (Render_pass_descriptor.destroy pass);
  get (Texture.destroy depth);
  get (Texture.destroy color)

let run () =
  let device = get (Device.system_default ()) in
  depth_actions device;
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
  let tile_width = get (Render_encoder.tile_width encoder) in
  let tile_height = get (Render_encoder.tile_height encoder) in
  if tile_width <= 0 || tile_height <= 0 then fail "invalid tile dimensions";
  expect Invalid_argument
    (Render_encoder.set_viewport encoder
       { x = 0.; y = 0.; width = 9.; height = 8.; znear = 0.; zfar = 1. });
  expect Invalid_argument
    (Render_encoder.set_scissor encoder { x = 7; y = 0; width = 2; height = 8 });
  expect Invalid_argument
    (Render_encoder.set_vertex_texture encoder ~index:31 sampled);
  expect Invalid_argument (Render_encoder.set_vertex_bytes encoder ~index:0 Bytes.empty);
  expect Invalid_state
    (Render_encoder.draw_primitives encoder ~primitive:Render_encoder.Point ~first:0 ~count:1 ());
  expect Invalid_argument (Render_encoder.set_stage_bytes encoder ~stage:Render_encoder.Mesh ~index:0 Bytes.empty);
  expect Invalid_argument (Render_encoder.set_stage_buffer encoder ~stage:Render_encoder.Mesh ~index:0 ~offset:1L None);
  expect Invalid_argument
    (Render_encoder.set_fragment_sampler encoder ~index:0 ~lod_min:2. ~lod_max:1. sampler)
