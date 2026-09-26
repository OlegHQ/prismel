(* The runtime's Scene2 direct and argument-buffer fragment shaders sample the
   same texel through the portable render path and must agree exactly. *)
open Ogpu

let get = function Ok x -> x | Error e -> failwith (Error.to_string e)

let run () =
  let driver, live_handles = Impl.create_driver () in
  let before = live_handles () in
  let device = get (Backend.create_device driver) in
  let capabilities = Backend.capabilities device in
  let queue = get (Backend.create_queue device) in
  let shader source entries bindings =
    get (Shader.create {backend="metal";label=Some"scene2-shader";bytes=Bytes.of_string source;
      entry_points=entries;bindings}) in
  let vertex_binding : Shader.binding list =
    [{group=0;binding=0;kind=Shader.Storage_buffer;visibility=[Shader.Vertex]};
     {group=0;binding=6;kind=Shader.Storage_buffer;visibility=[Shader.Vertex]}] in
  (* As in the runtime, each pipeline takes a vertex artifact and a fragment
     artifact compiled from the same source, each listing its stage's bindings. *)
  let vertex_of source = shader source [{name="scene_vertex";stage=Shader.Vertex}] vertex_binding in
  let direct = shader Runtime.Private.scene2_textured_direct
    [{name="scene_fragment";stage=Shader.Fragment}]
    [{group=0;binding=1;kind=Shader.Sampled_texture;visibility=[Shader.Fragment]};
     {group=0;binding=2;kind=Shader.Sampler;visibility=[Shader.Fragment]}] in
  let argument = shader Runtime.Private.scene2_textured_argument
    [{name="scene_fragment_argument";stage=Shader.Fragment}]
    [{group=0;binding=1;kind=Shader.Storage_buffer;visibility=[Shader.Fragment]}] in
  let layout entries =
    let group = get (Binding.create_layout entries) in
    get (Binding.create_pipeline_layout ~device:(Backend.device_handle device) ~capabilities [0,group]) in
  let vertex_entries : Binding.layout_entry list =
    [{binding=0;kind=Binding.Buffer;visibility=[Binding.Vertex]};
     {binding=6;kind=Binding.Buffer;visibility=[Binding.Vertex]}] in
  let descriptor layout source fragment fragment_entry : Pipeline.render_descriptor =
    {backend="metal";label=Some"scene2-shader";layout;vertex=vertex_of source;vertex_entry="scene_vertex";
     fragment=Some fragment;fragment_entry=Some fragment_entry;color_format=Rgba8_unorm;
     depth_format=No_depth;sample_count=1} in
  let direct_pipeline = get (Backend.create_render_pipeline device (descriptor
    (layout (vertex_entries @ [{binding=1;kind=Binding.Texture;visibility=[Binding.Fragment]};
      {binding=2;kind=Binding.Sampler;visibility=[Binding.Fragment]}])) Runtime.Private.scene2_textured_direct direct "scene_fragment")) in
  let argument_pipeline = get (Backend.create_render_pipeline ~indirect:true device (descriptor
    (layout (vertex_entries @ [{binding=1;kind=Binding.Buffer;visibility=[Binding.Fragment]}]))
    Runtime.Private.scene2_textured_argument argument "scene_fragment_argument")) in
  let encoder = get (Backend.create_argument argument_pipeline Fragment ~index:1) in
  if Backend.argument_length encoder <= 0 || Backend.argument_alignment encoder <= 0 then
    failwith "argument encoder reports no layout";
  (match Backend.create_argument argument_pipeline Fragment ~index:(-1) with
   | Error {Error.kind=Invalid_argument;_} -> ()
   | _ -> failwith "malformed argument binding accepted");
  let vertices = Bytes.make (3*68) '\000' in
  let put i x y u v = let base = i*68 in
    Bytes.set_int64_le vertices base (Int64.bits_of_float x);
    Bytes.set_int64_le vertices (base+8) (Int64.bits_of_float y);
    Bytes.set_int32_le vertices (base+48) Int32.minus_one;
    Bytes.set_int64_le vertices (base+52) (Int64.bits_of_float u);
    Bytes.set_int64_le vertices (base+60) (Int64.bits_of_float v) in
  put 0 (-1.) (-1.) 0. 1.; put 1 3. (-1.) 2. 1.; put 2 (-1.) 3. 0. (-1.);
  let buffer label bytes usage =
    let value = get (Backend.create_buffer device
      {label=Some label;size=Int64.of_int (Bytes.length bytes);usage}) in
    get (Backend.write_buffer value ~offset:0L bytes); value in
  let vertex_buffer = buffer "vertices" vertices [Storage] in
  let affine = Bytes.make 24 '\000' in
  Bytes.set_int32_le affine 0 (Int32.bits_of_float 1.);
  Bytes.set_int32_le affine 16 (Int32.bits_of_float 1.);
  let affine_buffer = buffer "affine" affine [Storage] in
  let texel = get (Backend.create_texture device
    {label=Some"texel";width=1;height=1;depth=1;mip_levels=1;sample_count=1;
     usage=[Texture_binding;Texture_copy_dst]}) in
  let upload = buffer "texel-upload" (Bytes.init 256 (fun i -> if i < 4 then "\x11\x22\x33\xff".[i] else '\000')) [Copy_src] in
  let wait receipt = get (Backend.complete_through queue receipt.Backend.epoch) in
  let commands = get (Backend.begin_commands queue) in
  let blit = get (Backend.blit_encoder commands) in
  get (Backend.buffer_to_texture blit ~src:upload ~bytes_per_row:256L ~bytes_per_image:256L ~dst:texel
    ~extent:{width=1;height=1;depth=1} ());
  get (Backend.end_blit blit);
  wait (get (Backend.commit commands));
  let sampler = get (Backend.create_sampler device
    {label=Some"scene2-sampler";min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;
     address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}) in
  let argument_buffer = get (Backend.create_buffer device
    {label=Some"arguments";size=Int64.of_int (max 256 (Backend.argument_length encoder));usage=[Storage]}) in
  get (Backend.argument_texture encoder argument_buffer ~offset:0L ~slot:0 texel);
  get (Backend.argument_sampler encoder argument_buffer ~offset:0L ~slot:1 sampler);
  let target () = get (Backend.create_texture device
    {label=Some"target";width=1;height=1;depth=1;mip_levels=1;sample_count=1;
     usage=[Texture_binding;Render_attachment;Texture_copy_src]}) in
  let direct_target = target () and argument_target = target () in
  let render pipeline target bind =
    let commands = get (Backend.begin_commands queue) in
    let pass = get (Backend.render_encoder commands
      {colors=[{texture=target;resolve=None;load=Clear;store=Store;clear=(0.,0.,0.,0.)}];
       depth=None;stencil=None}) in
    get (Backend.set_render_pipeline pass pipeline);
    get (Backend.set_stage_buffer pass Vertex ~index:0 vertex_buffer);
    get (Backend.set_stage_buffer pass Vertex ~index:6 affine_buffer);
    bind pass;
    get (Backend.draw pass ~primitive:Triangle_list ~first:0 ~count:3 ());
    get (Backend.end_render pass);
    wait (get (Backend.commit commands));
    get (Backend.read_texture target ~bytes_per_row:4) in
  let direct_pixels = render direct_pipeline direct_target (fun pass ->
    get (Backend.set_stage_texture pass Fragment ~index:1 texel);
    get (Backend.set_stage_sampler pass Fragment ~index:2 sampler)) in
  let argument_pixels = render argument_pipeline argument_target (fun pass ->
    get (Backend.set_stage_buffer pass Fragment ~index:1 argument_buffer);
    get (Backend.use_resources pass [`Texture texel])) in
  if direct_pixels <> argument_pixels || direct_pixels <> Bytes.of_string "\x11\x22\x33\xff" then
    failwith (Printf.sprintf "direct/argument-buffer pixel mismatch: direct=%S argument=%S"
      (Bytes.to_string direct_pixels) (Bytes.to_string argument_pixels));
  get (Backend.destroy_argument encoder);
  List.iter (fun t -> get (Backend.destroy_texture t)) [argument_target;direct_target;texel];
  List.iter (fun b -> get (Backend.destroy_buffer b)) [argument_buffer;upload;affine_buffer;vertex_buffer];
  get (Backend.destroy_sampler sampler);
  get (Backend.destroy_pipeline argument_pipeline);
  get (Backend.destroy_pipeline direct_pipeline);
  get (Backend.destroy_queue queue);
  get (Backend.destroy_device device);
  if live_handles () <> before then failwith "argument shader live-handle delta";
  print_endline "runtime-next scene2 direct/argument shader: exact pixel parity on OGPU, zero delta"
