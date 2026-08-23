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
      if Render_pipeline.kind render_pipeline <> Render_pipeline.Render then
        failwith "render pipeline kind changed";
      get (Pipeline_descriptor.Render.reset render);
      expect Invalid_state (Pipeline_descriptor.Render.compile render);
      get (Function.destroy vertex);
      get (Pipeline_descriptor.Render.destroy render);
      get (Compute_pipeline.destroy compute_pipeline);
      get (Render_pipeline.destroy render_pipeline);
      get (Library.destroy library);
      get (Device.destroy device);
      print_endline "metal pipeline113 safe: ok"
