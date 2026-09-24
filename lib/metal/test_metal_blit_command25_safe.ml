open Metal
let get = function Ok value -> value | Error error -> failwith error.message
let reject = function Error _ -> () | Ok _ -> failwith "expected rejection"
let () =
  let device = get (Device.system_default ()) in
  let queue = get (Command_queue.create device) in
  let commands = get (Command_buffer.create queue ()) in
  let blit = get (Blit_encoder.create commands) in
  let source = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
  let destination = get (Buffer.create ~device ~length:64L ~storage:Buffer.Shared ()) in
  get (Blit_encoder.fill_buffer blit source ~offset:0L ~length:64L ~byte:0x5a);
  get (Blit_encoder.copy_buffer blit ~source ~source_offset:0L ~destination
         ~destination_offset:0L ~length:64L);
  reject (Blit_encoder.copy_buffer blit ~source ~source_offset:60L ~destination
            ~destination_offset:0L ~length:8L);
  let fence = get (Fence.create device) in
  get (Blit_encoder.update_fence blit fence);
  get (Blit_encoder.wait_for_fence blit fence);
  let descriptor = Texture.descriptor_2d ~format:Texture.Rgba8_unorm
    ~width:4 ~height:4 ~mipmapped:true
    ~usage:[Texture.Shader_read;Texture.Shader_write] () in
  let texture = get (Texture.create ~device descriptor) in
  let texture2 = get (Texture.create ~device descriptor) in
  get (Blit_encoder.generate_mipmaps blit texture);
  get (Blit_encoder.copy_texture blit ~source:texture ~destination:texture2);
  reject (Blit_encoder.optimize_slice_for_cpu blit texture ~slice:(-1) ~level:0);
  let access_region = Texture.{x=0;y=0;z=0;width=1;height=1;depth=1} in
  let capability = function Ok () | Error {kind=(Unsupported|Native_error);_}->()
    | Error error->failwith error.message in
  capability (Blit_encoder.reset_access_counters blit texture ~region:access_region ~level:0 ~slice:0);
  capability (Blit_encoder.get_access_counters blit texture ~region:access_region ~level:0 ~slice:0 ~buffer:destination ~offset:0L);
  get (Blit_encoder.end_encoding blit);
  get (Command_buffer.commit commands);
  get (Command_buffer.wait_until_completed commands);
  get (Command_buffer.destroy commands);
  get (Fence.destroy fence); get (Texture.destroy texture2); get (Texture.destroy texture);
  get (Buffer.destroy destination); get (Buffer.destroy source);
  get (Command_queue.destroy queue); get (Device.destroy device);
  print_endline "BlitCommand safe conformance: ok"
