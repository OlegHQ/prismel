open Metal
let fail format=Printf.ksprintf failwith format
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf "%a" pp_error e)
let source={|
#include <metal_stdlib>
using namespace metal;
struct V { float4 position [[position]]; };
using M = mesh<V, void, 3, 1, topology::triangle>;
[[mesh]] void mesh_tile105_mesh(M out, uint tid [[thread_index_in_threadgroup]]) {
  constexpr float2 p[3] = {float2(-1,-1),float2(3,-1),float2(-1,3)};
  if (tid < 3) { V v; v.position=float4(p[tid],0,1); out.set_vertex(tid,v); out.set_index(tid,tid); }
  if (tid == 0) out.set_primitive_count(1);
}
kernel void mesh_tile105_tile(ushort2 p [[thread_position_in_threadgroup]]) { (void)p; }
fragment float4 mesh_tile105_fragment() { return float4(0.0, 1.0, 0.0, 1.0); }
struct Pixel { half4 color [[color(0)]]; };
kernel void mesh_tile105_invert(imageblock<Pixel, imageblock_layout_implicit> block, ushort2 tid [[thread_position_in_threadgroup]]) {
  Pixel p = block.read(tid); half4 c = p.color; p.color = half4(1.0h - c.r, 1.0h - c.g, 1.0h - c.b, 1.0h); block.write(p, tid);
}
|}
let draw_through_classic_encoder device library =
  (* A mesh pipeline draws a full green triangle through the classic encoder,
     then a tile pipeline inverts the imageblock to magenta. *)
  let mesh=get(Function.find~library "mesh_tile105_mesh")in
  let fragment=get(Function.find~library "mesh_tile105_fragment")in
  let invert=get(Function.find~library "mesh_tile105_invert")in
  let open Render_pipeline.Mesh_tile in
  let three={width=3L;height=1L;depth=1L}and zero={width=0L;height=0L;depth=0L}in
  let descriptor=get(mesh_descriptor~mesh_function:mesh~fragment_function:fragment
    ~required_mesh_threads:three~required_object_threads:zero())in
  (match set_mesh_color_format descriptor~index:8 Texture.Bgra8_unorm with
   | Error {kind=Invalid_argument;_}->() | _->fail "color attachment index 8 was accepted");
  get(set_mesh_color_format descriptor~index:0 Texture.Bgra8_unorm);
  (* The tile threadgroup is the encoder's whole tile, as Apple's tile samples do. *)
  let queue=get(Command_queue.create device)in
  let probe_target=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
    ~usage:[Texture.Render_target]~format:Texture.Bgra8_unorm~width:4~height:4()))in
  let probe=get(Command_buffer.create queue())in
  let probe_encoder=get(Render_encoder.create probe~target:probe_target())in
  let tile_width=get(Render_encoder.tile_width probe_encoder)and tile_height=get(Render_encoder.tile_height probe_encoder)in
  get(Render_encoder.end_encoding probe_encoder);get(Command_buffer.destroy probe);get(Texture.destroy probe_target);
  if tile_width<4||tile_height<4 then fail "tile size smaller than the 4x4 target";
  let tile_descriptor=get(tile_descriptor~tile_function:invert~required_threads:{width=Int64.of_int tile_width;height=Int64.of_int tile_height;depth=1L}())in
  get(set_tile_color_format tile_descriptor~index:0 Texture.Bgra8_unorm);
  match compile_mesh~reflection:true descriptor with
  | Error {kind=Unsupported;_}->print_endline "metal mesh/tile classic draw: unsupported"
  | Error error->fail "%s"(Format.asprintf "%a" pp_error error)
  | Ok pipeline->
      let tile_pipeline=get(compile_tile~reflection:true tile_descriptor)in
      let target=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared
        ~usage:[Texture.Render_target]~format:Texture.Bgra8_unorm~width:4~height:4()))in
      let command=get(Command_buffer.create queue())in
      let encoder=get(Render_encoder.create command~target())in
      (match Render_encoder.draw_mesh_threadgroups encoder~threadgroups:(1,1,1)~mesh_threadgroup:(3,1,1)()with
       | Error {kind=Invalid_state;_}->() | _->fail "mesh draw without a pipeline was accepted");
      get(Render_encoder.set_pipeline encoder pipeline);
      (match Render_encoder.draw_mesh_threadgroups encoder~threadgroups:(1,1,1)~mesh_threadgroup:(2,1,1)()with
       | Error {kind=Invalid_argument;_}->() | _->fail "mesh threadgroup differing from the required size was accepted");
      (match Render_encoder.draw_mesh_threadgroups encoder~threadgroups:(1,1,1)~object_threadgroup:(1,1,1)~mesh_threadgroup:(3,1,1)()with
       | Error {kind=Invalid_argument;_}->() | _->fail "object threadgroup without an object stage was accepted");
      (match Render_encoder.dispatch_threads_per_tile encoder~threads:(1,1,1)with
       | Error {kind=Invalid_state;_}->() | _->fail "tile dispatch on a mesh pipeline was accepted");
      get(Render_encoder.draw_mesh_threadgroups encoder~threadgroups:(1,1,1)~mesh_threadgroup:(3,1,1)());
      get(Render_encoder.set_pipeline encoder tile_pipeline);
      (match Render_encoder.dispatch_threads_per_tile encoder~threads:(1,1,2)with
       | Error {kind=Invalid_argument;_}->() | _->fail "tile dispatch with depth two was accepted");
      (match Render_encoder.dispatch_threads_per_tile encoder~threads:(2,2,1)with
       | Error {kind=Invalid_argument;_}->() | _->fail "tile threads differing from the required size were accepted");
      get(Render_encoder.dispatch_threads_per_tile encoder~threads:(tile_width,tile_height,1));
      get(Render_encoder.end_encoding encoder);
      get(Command_buffer.commit command);
      get(Command_buffer.wait_until_completed command);
      let pixels=get(Texture.read_bytes target~region:{x=0;y=0;z=0;width=4;height=4;depth=1}~mip_level:0~slice:0~bytes_per_row:16~bytes_per_image:64)in
      let bgra x y=Bytes.sub_string pixels((y*4+x)*4)4 in
      let hex v=String.concat" "(List.init 4(fun i->Printf.sprintf"%02x"(Char.code v.[i])))in
      if bgra 0 0<>"\xff\x00\xff\xff"||bgra 3 3<>"\xff\x00\xff\xff"then fail "mesh draw then tile invert did not produce magenta (got %s and %s)"(hex(bgra 0 0))(hex(bgra 3 3));
      get(Command_buffer.destroy command);get(Texture.destroy target);get(Command_queue.destroy queue);
      get(Render_pipeline.destroy tile_pipeline);get(Render_pipeline.destroy pipeline);
      get(destroy_tile tile_descriptor);get(destroy_mesh descriptor);
      get(Function.destroy invert);get(Function.destroy fragment);get(Function.destroy mesh)
let run () =
  let open Render_pipeline.Mesh_tile in
  let buffer=get(buffer_descriptor ~mutability:Mutable())in
  if buffer_mutability buffer<>Mutable then fail "buffer mutability drift";
  (match set_buffer_mutability buffer Immutable with
   | Error {kind=Invalid_argument;_}->()
   | Error error->fail "%s"(Format.asprintf "%a" pp_error error)
   | Ok ()->fail "immutable pipeline buffer descriptor accepted mutation");
  if buffer_mutability buffer<>Mutable then fail "rejected mutation changed descriptor";
  let immutable_buffer=get(buffer_descriptor ~mutability:Immutable())in
  if buffer_mutability immutable_buffer<>Immutable then fail "replacement mutability drift";
  let color=get(create_color_attachment Texture.Bgra8_unorm)in
  if color_attachment_format color<>Texture.Bgra8_unorm then fail "color format drift";
  get(destroy_color color);get(destroy_buffer immutable_buffer);get(destroy_buffer buffer);
  match Device.system_default() with
  | Error _->print_endline "metal mesh/tile safe: skipped (no device)"
  | Ok device->
      let library=get(Library.compile_source~device source)in
      let mesh=get(Function.find~library "mesh_tile105_mesh")in
      let tile=get(Function.find~library "mesh_tile105_tile")in
      let one={width=1L;height=1L;depth=1L}in
      let zero={width=0L;height=0L;depth=0L}in
      let three={width=3L;height=1L;depth=1L}in
      let mesh_descriptor=get(mesh_descriptor~mesh_function:mesh
        ~depth_format:Texture.Depth32_float~stencil_format:Texture.Stencil8
        ~required_mesh_threads:three~required_object_threads:zero())in
      let tile_descriptor=get(tile_descriptor~tile_function:tile
        ~required_threads:one())in
      (match compile_mesh~reflection:true mesh_descriptor with
       | Error {kind=Unsupported;_}->()
       | Error error->fail "%s"(Format.asprintf "%a" pp_error error)
       | Ok pipeline->
           if Render_pipeline.kind pipeline<>Render_pipeline.Mesh then fail "mesh pipeline kind drift";
           let mesh_threads=get(Render_pipeline.mesh_threads_per_threadgroup pipeline)in
           if mesh_threads.width<>3L||mesh_threads.height<>1L||mesh_threads.depth<>1L then
             fail "mesh required threadgroup size drift";
           let object_threads=get(Render_pipeline.object_threads_per_threadgroup pipeline)in
           if object_threads.width<>0L||object_threads.height<>0L||object_threads.depth<>0L then
             fail "nil-object required threadgroup size drift";
           get(Render_pipeline.destroy pipeline));
      (match compile_tile~reflection:true tile_descriptor with
       | Error {kind=Unsupported;_}->()
       | Error error->fail "%s"(Format.asprintf "%a" pp_error error)
       | Ok pipeline->
           if Render_pipeline.kind pipeline<>Render_pipeline.Tile then fail "tile pipeline kind drift";
           get(Render_pipeline.destroy pipeline));
      get(destroy_mesh mesh_descriptor);get(destroy_tile tile_descriptor);
      get(Function.destroy mesh);get(Function.destroy tile);
      draw_through_classic_encoder device library;
      get(Library.destroy library);get(Device.destroy device);
      print_endline "metal mesh/tile safe: ok"
