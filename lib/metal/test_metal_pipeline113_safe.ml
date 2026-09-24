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

let () =
  match Device.system_default () with
  | Error _ -> print_endline "metal pipeline113 safe: skipped (no device)"
  | Ok device ->
      let library = get (Library.compile_source ~device source) in
      let vertex = get (Function.find ~library "pipeline113_vertex") in
      let kernel = get (Function.find ~library "pipeline113_compute") in
      expect Invalid_argument (Pipeline_descriptor.Compute.create vertex);
      expect Invalid_argument (Pipeline_descriptor.Render.create kernel);

      let compute = get (Pipeline_descriptor.Compute.create kernel) in
      let required : Pipeline_descriptor.Compute.size3 =
        { width = 2L; height = 1L; depth = 1L }
      in
      get (Pipeline_descriptor.Compute.set_required_threads compute required);
      let roundtrip = get (Pipeline_descriptor.Compute.required_threads compute) in
      if roundtrip <> required then failwith "compute size roundtrip changed";
      expect Parent_has_dependents (Function.destroy kernel);
      let compute_pipeline =
        get (Pipeline_descriptor.Compute.compile ~reflection:true compute)
      in
      ignore (get (Compute_pipeline.resource_id compute_pipeline));
      ignore (get (Compute_pipeline.required_threads_per_threadgroup compute_pipeline));
      ignore (get (Compute_pipeline.shader_validation compute_pipeline));
      ignore (get (Compute_pipeline.supports_indirect_command_buffers compute_pipeline));
      expect Invalid_argument
        (Compute_pipeline.imageblock_memory_length compute_pipeline
           { Compute_pipeline.width = 0L; height = 1L; depth = 1L });
      (match Compute_pipeline.bindings compute_pipeline with
       | Some (_ :: _) -> ()
       | Some [] | None -> failwith "compute reflection was not returned");
      get (Pipeline_descriptor.Compute.reset compute);
      expect Invalid_state (Pipeline_descriptor.Compute.compile compute);
      get (Function.destroy kernel);
      get (Pipeline_descriptor.Compute.destroy compute);

      let render = get (Pipeline_descriptor.Render.create vertex) in
      get (Pipeline_descriptor.Render.set_depth_format render Texture.Depth32_float);
      get (Pipeline_descriptor.Render.set_stencil_format render Texture.Stencil8);
      get (Pipeline_descriptor.Render.set_input_topology render
             Pipeline_descriptor.Render.Triangle);
      get (Pipeline_descriptor.Render.set_sample_count render 1);
      get (Pipeline_descriptor.Render.set_tessellation_winding render
             Pipeline_descriptor.Render.Clockwise);
      if get (Pipeline_descriptor.Render.depth_format render)
         <> Some Texture.Depth32_float then failwith "depth format changed";
      if get (Pipeline_descriptor.Render.stencil_format render)
         <> Some Texture.Stencil8 then failwith "stencil format changed";
      if get (Pipeline_descriptor.Render.input_topology render)
         <> Pipeline_descriptor.Render.Triangle then failwith "topology changed";
      if get (Pipeline_descriptor.Render.sample_count render) <> 1 then
        failwith "sample count changed";
      if get (Pipeline_descriptor.Render.tessellation_winding render)
         <> Pipeline_descriptor.Render.Clockwise then failwith "winding changed";
      expect Parent_has_dependents (Function.destroy vertex);
      let render_pipeline =
        get (Pipeline_descriptor.Render.compile ~reflection:true render)
      in
      let compiler=get(Compiler.create device)in
      let specialization_source=get(Compiler.create_render_pipeline compiler
        ~library~vertex:"pipeline113_vertex"~fragment:"pipeline113_fragment"
        ~color_formats:[Texture.Bgra8_unorm])in
      let specialized=get(Compiler.specialize_render_pipeline compiler
        ~source:specialization_source~library~vertex:"pipeline113_vertex"
        ~fragment:"pipeline113_fragment"
        ~color_format:Texture.Bgra8_unorm())in
      let specialized_task=get(Compiler.specialize_render_pipeline_async compiler
        ~source:specialization_source~library~vertex:"pipeline113_vertex"
        ~fragment:"pipeline113_fragment"
        ~color_format:Texture.Bgra8_unorm())in
      get(Compiler_task.wait specialized_task);
      let specialized_async=match get(Compiler_task.poll specialized_task)with
        |Compiler_task.Complete(Ok pipeline)->pipeline
        |Compiler_task.Complete(Error error)->fail_error error
        |Compiler_task.Pending->failwith"specialization task remained pending"in
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
      if Render_pipeline.kind render_pipeline <> Render_pipeline.Render then
        failwith "render pipeline kind changed";
      get (Pipeline_descriptor.Render.reset render);
      expect Invalid_state (Pipeline_descriptor.Render.compile render);
      get (Function.destroy vertex);
      get (Pipeline_descriptor.Render.destroy render);
      get (Compute_pipeline.destroy compute_pipeline);
      get(Render_pipeline.destroy specialized);get(Render_pipeline.destroy specialized_async);
      get(Render_pipeline.destroy specialization_source);
      get(Compute_pipeline.destroy archived_compute);get(Render_pipeline.destroy archived_render);
      get(Compute_pipeline.destroy archived_compute_source);get(Render_pipeline.destroy archived_render_source);
      get(Pipeline_archive.destroy archive);get(Compiler.destroy archive_compiler);
      get(Pipeline_dataset.destroy dataset);Sys.remove archive_path;
      get(Compiler_task.destroy specialized_task);get(Compiler.destroy compiler);
      get (Render_pipeline.destroy render_pipeline);
      get (Library.destroy library);
      get (Device.destroy device);
      print_endline "metal pipeline113 safe: ok"
