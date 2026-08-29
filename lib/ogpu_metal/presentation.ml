type t =
  { device : Metal.Device.t
  ; library : Metal.Library.t
  ; pipeline : Metal.Render_pipeline.t
  ; mutable dead : bool
  }
type render_result = Completed | Committed_with_error of Ogpu.Error.t

let operation = "Ogpu_metal.Presentation"
let error kind message = Error (Ogpu.Error.make operation kind message)
let metal value = Error (Adapter.error ~operation value)

let fail_encode encoder value =
  Option.iter
    (fun encoder ->
       if not (Metal.Render_encoder.destroyed encoder) then
         ignore (Metal.Render_encoder.end_encoding encoder))
    encoder;
  metal value

let fail_render commands encoder value =
  Option.iter
    (fun encoder ->
       if not (Metal.Render_encoder.destroyed encoder) then
         ignore (Metal.Render_encoder.end_encoding encoder))
    encoder;
  ignore (Metal.Command_buffer.destroy commands);
  metal value

let fail_copy commands encoder value =
  Option.iter
    (fun encoder ->
       if not (Metal.Blit_encoder.destroyed encoder) then
         ignore (Metal.Blit_encoder.end_encoding encoder))
    encoder;
  ignore (Metal.Command_buffer.destroy commands);
  metal value

let source = {|
#include <metal_stdlib>
using namespace metal;

struct PrismelPresentVertex {
  float4 position [[position]];
};

vertex PrismelPresentVertex prismel_present_vertex(uint vertex_id [[vertex_id]]) {
  const float2 positions[3] = {
    float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)
  };
  PrismelPresentVertex output;
  output.position = float4(positions[vertex_id], 0.0, 1.0);
  return output;
}

fragment float4 prismel_present_fragment(
    PrismelPresentVertex input [[stage_in]],
    texture2d<float, access::read> source_texture [[texture(0)]]) {
  return source_texture.read(uint2(input.position.xy));
}
|}

let create device =
  let native = Device.Private.metal device in
  if Device.destroyed device then
    error Ogpu.Error.Stale_handle "device is destroyed"
  else
    match Metal.Library.compile_source ~label:"Prismel presentation" ~device:native source with
    | Error value -> metal value
    | Ok library ->
        (match Metal.Compiler.create native with
         | Error value ->
             ignore (Metal.Library.destroy library);
             metal value
         | Ok compiler ->
             let compiled =
               Metal.Compiler.create_render_pipeline
                 ~label:"Prismel presentation"
                 ~fragment:"prismel_present_fragment"
                 ~color_formats:[Metal.Texture.Bgra8_unorm]
                 ~primitive_topology:Metal.Render_pipeline.Triangle
                 compiler ~library ~vertex:"prismel_present_vertex"
             in
             ignore (Metal.Compiler.destroy compiler);
             match compiled with
             | Error value ->
                 ignore (Metal.Library.destroy library);
                 metal value
             | Ok pipeline -> Ok {device=native; library; pipeline; dead=false})

let validate_resources value ~device ~source ~target =
  if value.dead then error Ogpu.Error.Stale_handle "presentation helper is destroyed"
  else if not (Metal.Device.same value.device device) then
    error Ogpu.Error.Cross_device "presentation command belongs to another device"
  else if Metal.Texture.destroyed source || Metal.Texture.destroyed target then
    error Ogpu.Error.Stale_handle "presentation texture is destroyed"
  else if not (Metal.Device.same value.device (Metal.Texture.device source)) ||
          not (Metal.Device.same value.device (Metal.Texture.device target)) then
    error Ogpu.Error.Cross_device "presentation texture belongs to another device"
  else
    let source_descriptor = Metal.Texture.descriptor source
    and target_descriptor = Metal.Texture.descriptor target in
    if source_descriptor.kind <> Metal.Texture.Texture_2d ||
       source_descriptor.format <> Metal.Texture.Rgba8_unorm ||
       source_descriptor.depth <> 1 || source_descriptor.mip_levels <> 1 ||
       source_descriptor.sample_count <> 1 || source_descriptor.array_length <> 1 then
      error Ogpu.Error.Invalid_argument
        "presentation source must be a single-sample 2D RGBA8 texture"
    else if not (List.mem Metal.Texture.Shader_read source_descriptor.usage) then
      error Ogpu.Error.Invalid_argument
        "presentation source must be shader-readable"
    else if target_descriptor.kind <> Metal.Texture.Texture_2d ||
            target_descriptor.format <> Metal.Texture.Bgra8_unorm ||
            target_descriptor.depth <> 1 || target_descriptor.mip_levels <> 1 ||
            target_descriptor.sample_count <> 1 || target_descriptor.array_length <> 1 then
      error Ogpu.Error.Invalid_argument
        "presentation target must be a single-sample 2D BGRA8 texture"
    else if not (List.mem Metal.Texture.Render_target target_descriptor.usage) then
      error Ogpu.Error.Invalid_argument
        "presentation target must be renderable"
    else if source_descriptor.width <> target_descriptor.width ||
            source_descriptor.height <> target_descriptor.height then
      error Ogpu.Error.Invalid_argument
        "presentation source and target extents differ"
    else Ok ()

let validate value ~queue ~source ~target =
  if Metal.Command_queue.destroyed queue then
    error Ogpu.Error.Stale_handle "presentation queue is destroyed"
  else
    validate_resources value ~device:(Metal.Command_queue.device queue) ~source ~target

let encode_classic value commands ?present ~source ~target () =
  if Metal.Command_buffer.destroyed commands then
    error Ogpu.Error.Stale_handle "presentation command buffer is destroyed"
  else
    match validate_resources value ~device:(Metal.Command_buffer.device commands)
            ~source ~target with
    | Error _ as failure -> failure
    | Ok () ->
        (match Metal.Render_encoder.create commands ~target () with
         | Error value -> metal value
         | Ok encoder ->
             (match Metal.Render_encoder.set_pipeline encoder value.pipeline with
              | Error value -> fail_encode (Some encoder) value
              | Ok () ->
                  (match Metal.Render_encoder.set_fragment_texture encoder ~index:0 source with
                   | Error value -> fail_encode (Some encoder) value
                   | Ok () ->
                       (match Metal.Render_encoder.draw_triangles encoder ~first:0 ~count:3 () with
                        | Error value -> fail_encode (Some encoder) value
                        | Ok () ->
                            (match Metal.Render_encoder.end_encoding encoder with
                             | Error value -> fail_encode None value
                             | Ok () ->
                                 match present with
                                 | None -> Ok ()
                                 | Some drawable ->
                                     (match Metal.Command_buffer.present commands drawable () with
                                      | Ok () -> Ok ()
                                      | Error value -> metal value))))))

let render value ~queue ?present ?on_commit ~source ~target () =
  match validate value ~queue ~source ~target with
  | Error _ as failure -> failure
  | Ok () ->
      (match Metal.Command_buffer.create queue ~label:"Prismel presentation" () with
       | Error value -> metal value
       | Ok commands ->
           match encode_classic value commands ?present ~source ~target () with
           | Error value ->
               ignore (Metal.Command_buffer.destroy commands);
               Error value
           | Ok () ->
               (match Metal.Command_buffer.commit commands with
                | Error value -> fail_render commands None value
                | Ok () ->
                    Option.iter (fun notify -> notify ()) on_commit;
                    (match Metal.Command_buffer.wait_until_completed commands with
                     | Error value ->
                         ignore (Metal.Command_buffer.destroy commands);
                         Ok (Committed_with_error
                               (Adapter.error ~operation value))
                     | Ok () ->
                         (match Metal.Command_buffer.destroy commands with
                          | Error value ->
                              Ok (Committed_with_error
                                    (Adapter.error ~operation value))
                          | Ok () -> Ok Completed))))

let copy value ~queue ~source ~target =
  if value.dead then error Ogpu.Error.Stale_handle "presentation helper is destroyed"
  else if Metal.Command_queue.destroyed queue then
    error Ogpu.Error.Stale_handle "presentation queue is destroyed"
  else if not (Metal.Device.same value.device (Metal.Command_queue.device queue)) then
    error Ogpu.Error.Cross_device "presentation queue belongs to another device"
  else if Metal.Texture.destroyed source || Metal.Texture.destroyed target then
    error Ogpu.Error.Stale_handle "presentation copy texture is destroyed"
  else if not (Metal.Device.same value.device (Metal.Texture.device source)) ||
          not (Metal.Device.same value.device (Metal.Texture.device target)) then
    error Ogpu.Error.Cross_device "presentation copy texture belongs to another device"
  else
    let source_descriptor = Metal.Texture.descriptor source
    and target_descriptor = Metal.Texture.descriptor target in
    if source_descriptor.kind <> Metal.Texture.Texture_2d ||
       target_descriptor.kind <> Metal.Texture.Texture_2d ||
       source_descriptor.format <> Metal.Texture.Bgra8_unorm ||
       target_descriptor.format <> Metal.Texture.Bgra8_unorm ||
       source_descriptor.width <> target_descriptor.width ||
       source_descriptor.height <> target_descriptor.height ||
       source_descriptor.sample_count <> 1 || target_descriptor.sample_count <> 1 then
      error Ogpu.Error.Invalid_argument "presentation copy textures are incompatible"
    else
      match Metal.Command_buffer.create queue ~label:"Prismel presentation readback" () with
      | Error value -> metal value
      | Ok commands ->
          (match Metal.Blit_encoder.create commands with
           | Error value -> fail_copy commands None value
           | Ok encoder ->
               (match Metal.Blit_encoder.copy_texture encoder ~source ~destination:target with
                | Error value -> fail_copy commands (Some encoder) value
                | Ok () ->
                    (match Metal.Blit_encoder.end_encoding encoder with
                     | Error value -> fail_copy commands None value
                     | Ok () ->
                         (match Metal.Command_buffer.commit commands with
                          | Error value -> fail_copy commands None value
                          | Ok () ->
                              (match Metal.Command_buffer.wait_until_completed commands with
                               | Error value -> fail_copy commands None value
                               | Ok () ->
                                   (match Metal.Command_buffer.destroy commands with
                                    | Error value -> metal value
                                    | Ok () -> Ok ()))))))

let destroy value =
  if not value.dead then begin
    value.dead <- true;
    ignore (Metal.Render_pipeline.destroy value.pipeline);
    ignore (Metal.Library.destroy value.library)
  end
