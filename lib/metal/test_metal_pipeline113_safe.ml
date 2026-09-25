open Metal

let fail_error error = failwith (Format.asprintf "%a" pp_error error)
let get = function Ok value -> value | Error error -> fail_error error
let expect kind = function
  | Error error when error.kind = kind -> ()
  | Error error -> failwith (Format.asprintf "unexpected error: %a" pp_error error)
  | Ok _ -> failwith "expected rejection"

let source = {|
#include <metal_stdlib>
using namespace metal;
struct Vertex_out { float4 position [[position]]; };
vertex Vertex_out pipeline113_vertex(uint id [[vertex_id]]) {
  float2 p[3] = { float2(-1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
  return { float4(p[id], 0.0, 1.0) };
}
fragment float4 pipeline113_fragment() { return float4(0.25, 0.5, 0.75, 1.0); }
kernel void pipeline113_compute(device uint *out [[buffer(0)]]) { out[0] = 113; }
|}

let run () =
  match Device.system_default () with
  | Error _ -> print_endline "metal pipeline113 safe: skipped (no device)"
  | Ok device ->
      let library = get (Library.compile_source ~device source) in
      let compiler=get(Compiler.create device)in
      let specialization_source=get(Compiler.create_render_pipeline compiler
        ~library~vertex:"pipeline113_vertex"~fragment:"pipeline113_fragment"
        ~color_formats:[Texture.Bgra8_unorm])in
      let specialized=get(Compiler.specialize_render_pipeline compiler
        ~source:specialization_source~library~vertex:"pipeline113_vertex"
        ~fragment:"pipeline113_fragment"
        ~color_format:Texture.Bgra8_unorm())in
      let dataset=get(Pipeline_dataset.create~device[Pipeline_dataset.Binaries])in
      let archive_compiler=get(Compiler.create~dataset device)in
      let archived_compute_source=get(Compiler.create_compute_pipeline archive_compiler
        ~library "pipeline113_compute")in
      let archived_render_source=get(Compiler.create_render_pipeline archive_compiler
        ~library~vertex:"pipeline113_vertex"~fragment:"pipeline113_fragment"
        ~color_formats:[Texture.Bgra8_unorm])in
      let archive_path=Filename.temp_file"metal-pipeline113-"".metallib"in
      Sys.remove archive_path;
      get(Pipeline_dataset.serialize_archive dataset archive_path);
      let archive=get(Pipeline_archive.load_file~device archive_path)in
      let archived_compute=get(Pipeline_archive.compile_compute archive~library
        "pipeline113_compute")in
      let archived_render=get(Pipeline_archive.compile_render archive~library
        ~vertex:"pipeline113_vertex"~fragment:"pipeline113_fragment"
        ~color_format:Texture.Bgra8_unorm())in
      get(Render_pipeline.destroy specialized);
      get(Render_pipeline.destroy specialization_source);
      get(Compute_pipeline.destroy archived_compute);get(Render_pipeline.destroy archived_render);
      get(Compute_pipeline.destroy archived_compute_source);get(Render_pipeline.destroy archived_render_source);
      get(Pipeline_archive.destroy archive);get(Compiler.destroy archive_compiler);
      get(Pipeline_dataset.destroy dataset);Sys.remove archive_path;
      get(Compiler.destroy compiler);
      get (Library.destroy library);
      get (Device.destroy device);
      print_endline "metal pipeline113 safe: ok"
