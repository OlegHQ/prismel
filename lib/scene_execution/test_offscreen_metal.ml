open Ogpu_metal

let get = function
  | Ok value -> value
  | Error error -> failwith (Ogpu.Error.to_string error)

let metal = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)

let shader_source = {|
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
vertex V scene_vertex(uint i [[vertex_id]]) {
  constexpr float2 p[3]={{-1.,-1.},{3.,-1.},{-1.,3.}};
  V v; v.position=float4(p[i],0.,1.); return v;
}
fragment float4 scene_fragment(){return float4(0.25,0.5,0.75,1.);}
|}

let () =
  match Device.system_default () with
  | Error _ -> print_endline "offscreen Metal execution: skipped (no device)"
  | Ok native_device ->
      let before = metal (Metal.Release_queue.stats ()) in
      let driver, control = Backend.create ~device:native_device () in
      let cache = get (Pipeline.create_cache ~capacity:1) in
      let configuration : Ogpu.Surface.configuration =
        { logical_width=4; logical_height=4; physical_width=4;
          physical_height=4; format=Bgra8_unorm; present_mode=Fifo;
          max_acquired=1 }
      in
      let make backend_device =
        let vertex = get (Ogpu.Shader.create
          {backend="metal";label=Some"offscreen-vertex";
           bytes=Bytes.of_string shader_source;
           entry_points=[{name="scene_vertex";stage=Vertex}];bindings=[]})
        and fragment = get (Ogpu.Shader.create
          {backend="metal";label=Some"offscreen-fragment";
           bytes=Bytes.of_string shader_source;
           entry_points=[{name="scene_fragment";stage=Fragment}];bindings=[]}) in
        let layout = get (Ogpu.Binding.create_pipeline_layout
          ~device:(Ogpu.Backend.device_handle backend_device)
          ~capabilities:(Ogpu.Backend.capabilities backend_device) []) in
        let descriptor : Ogpu.Pipeline.render_descriptor =
          {backend="metal";label=Some"offscreen";layout;vertex;
           vertex_entry="scene_vertex";fragment=Some fragment;
           fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;
           depth_format=No_depth;sample_count=1}
        in
        match Pipeline.create_render_runtime_msl cache native_device descriptor with
        | Error _ as error -> error
        | Ok pipeline ->
            Backend.register_pipeline control pipeline;
            Ok (Pipeline.Private.portable pipeline)
      in
      let renderer = get (Scene_execution.create_offscreen_with_pipeline driver
        configuration ~before_device_destroy:(fun () ->
          Pipeline.clear_cache cache; Ok ()) make) in
      let indices=Bytes.make 12 '\000' in
      Bytes.set_int32_le indices 4 1l; Bytes.set_int32_le indices 8 2l;
      let mesh : Scene_execution.mesh =
        {key="offscreen-fullscreen";vertices=Bytes.make 48 '\000';
         vertex_count=3;indices;index_count=3}
      and state : Scene_execution.state =
        {viewport=(0,0,4,4);scissor=(0,0,4,4);
         cull=Ogpu.Render_pass.Cull_none;depth_compare=Always;
         depth_write=false;depth_load=Load;depth_clear=1.;
         transform_uniforms=None;stencil_state=None;stencil_load=Load;
         stencil_clear=0}
      in
      let expected = Bytes.of_string "\x40\x80\xbf\xff" in
      for frame=1 to 600 do
        if not (get (Scene_execution.render renderer [{mesh;state}])) then
          failwith "layerless offscreen submission was skipped";
        if List.mem frame [1;2;60;600] then begin
          let pixels=get(Scene_execution.read_pixels renderer~bytes_per_row:16) in
          if Bytes.sub pixels 0 4 <> expected then
            failwith (Printf.sprintf "offscreen pixel drift at frame %d" frame)
        end
      done;
      let uploaded=Scene_execution.upload_bytes renderer in
      if uploaded<=0L || Scene_execution.cache_entries renderer>2 then
        failwith "offscreen cache accounting is unbounded or empty";
      get (Scene_execution.destroy renderer);
      if Backend.sampler_cache_entries control<>0 ||
         Backend.retained_plan_entries control<>0 ||
         Backend.classic_submission_entries control<>0 then
        failwith "offscreen native caches survived destruction";
      ignore (metal (Metal.Release_queue.drain ()));
      let after=metal(Metal.Release_queue.stats ()) in
      if after.live_handles<>before.live_handles-1 then
        failwith "offscreen native live-handle delta";
      print_endline
        "offscreen Metal execution: layerless exact frame1/2/60/600, bounded, zero delta"
