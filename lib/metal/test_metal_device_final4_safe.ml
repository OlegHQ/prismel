open Metal

let fail error = failwith (Format.asprintf "%a" pp_error error)
let get = function Ok value -> value | Error error -> fail error

let source = {|
#include <metal_stdlib>
using namespace metal;
struct Device4_out { float4 position [[position]]; };
vertex Device4_out device4_vertex(uint id [[vertex_id]]) {
  float2 p[3] = { float2(-1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
  return { float4(p[id], 0.0, 1.0) };
}
|}

let () =
  match Device.system_default () with
  | Error _ -> print_endline "metal device final4 safe: skipped (no device)"
  | Ok device ->
      let library = get (Library.compile_source ~device source) in
      let vertex = get (Function.find ~library "device4_vertex") in
      (match Device_function_handle.of_function device vertex with
       | Ok handle ->
           if Device.registry_id (Device_function_handle.device handle)
              <> Device.registry_id device then failwith "function handle device drift";
           get (Device_function_handle.destroy handle)
       | Error error when error.kind = Unsupported -> ()
       | Error error -> fail error);
      let descriptor = get (Shader_argument_encoder.descriptor
        ~data_type:Data_type.uint ~index:0L ~array_length:1L
        ~access:Shader_argument_encoder.Read_only
        ~texture_kind:Texture.Type_2d ~constant_block_alignment:0L ()) in
      let encoder = get (Shader_argument_encoder.create device [descriptor]) in
      if Shader_argument_encoder.encoded_length encoder <= 0L then
        failwith "argument encoder has empty layout";
      get (Shader_argument_encoder.destroy encoder);
      let render = get (Pipeline_descriptor.Render.create vertex) in
      let pipeline = get (Pipeline_descriptor.Render.compile_simple render) in
      if Render_pipeline.kind pipeline <> Render_pipeline.Render then
        failwith "simple render pipeline kind drift";
      get (Render_pipeline.destroy pipeline);
      get (Pipeline_descriptor.Render.destroy render);
      get (Function.destroy vertex);
      get (Library.destroy library);
      get (Device.destroy device);
      print_endline "metal device final4 safe: ok"
