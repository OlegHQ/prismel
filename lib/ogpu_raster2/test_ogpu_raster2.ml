let get = function Ok x -> x | Error e -> failwith (Ogpu.Error.to_string e)
let run frames =
  let driver, control = Ogpu_raster2.create () in
  let config : Ogpu.Surface.configuration = { logical_width=4; logical_height=4; physical_width=4; physical_height=4; format=Rgba8_unorm; present_mode=Immediate; max_acquired=2 } in
  let renderer = get (Scene_execution.create driver config) in
  let indices=Bytes.make 12 '\000' in Bytes.set_int32_le indices 4 1l; Bytes.set_int32_le indices 8 2l;
  let vertices=Bytes.make 48 '\000'in let put offset value=Bytes.set_int64_le vertices offset(Int64.bits_of_float value)in put 0 0.;put 8 0.;put 16 4.;put 24 0.;put 32 0.;put 40 4.;
  let mesh : Scene_execution.mesh = {key="software";vertices;vertex_count=3;indices;index_count=3} in
  let state : Scene_execution.state = {viewport=(0,0,4,4);scissor=(0,0,4,4);
    cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;
    depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;
    transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;
    stencil_clear=0} in
  let draw={Scene_execution.mesh;state} in
  let vertices2=Bytes.copy vertices in let put2 offset value=Bytes.set_int64_le vertices2 offset(Int64.bits_of_float value)in put2 0 4.;put2 8 4.;put2 16 0.;put2 24 4.;put2 32 4.;put2 40 0.;let mesh2:Scene_execution.mesh={mesh with key="software-overlap";vertices=vertices2}in let draw2={Scene_execution.mesh=mesh2;state}in
  for frame=1 to frames do
    ignore(get(Scene_execution.render renderer(if frame=2 then [draw;draw2] else [draw])));
    if List.mem frame [1;2;60;600] then let bytes=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in if Bytes.get_int32_be bytes 0<>0x4080BFFFl then failwith"software exact pixel"else if frame=2&&Bytes.get_int32_be bytes 60<>0x4080BFFFl then failwith"software second indexed draw"else if frame<>2&&Bytes.get_int32_be bytes 60<>0l then failwith"software off-triangle pixel"
  done;
  let _,stable_decode_misses=Ogpu_raster2.decode_cache_stats control in
  if stable_decode_misses<>4 then
    failwith(Printf.sprintf"stable frame decoded %d vertex/index buffers"stable_decode_misses);
  (* A densely indexed mesh deliberately reuses three degenerate vertices.
     The software adapter must decode those vertices once, not construct three
     boxed records for every triangle. *)
  let triangle_count=4096 in
  let shared_indices=Bytes.create(triangle_count*3*4)in
  for triangle=0 to triangle_count-1 do
    Bytes.set_int32_le shared_indices((triangle*3+1)*4)1l;
    Bytes.set_int32_le shared_indices((triangle*3+2)*4)2l
  done;
  let shared_mesh:Scene_execution.mesh={mesh with key="shared-index-allocation";
    indices=shared_indices;index_count=triangle_count*3}in
  let shared_draw={Scene_execution.mesh=shared_mesh;state}in
  ignore(get(Scene_execution.render renderer[shared_draw]));
  let _,shared_misses=Ogpu_raster2.decode_cache_stats control in
  Gc.compact();
  let before=Gc.allocated_bytes()in
  ignore(get(Scene_execution.render renderer[shared_draw]));
  let allocated=Gc.allocated_bytes()-.before in
  if allocated>750_000. then
    failwith(Printf.sprintf"shared-index render allocated %.0f bytes"allocated);
  let entries,unchanged_misses=Ogpu_raster2.decode_cache_stats control in
  if unchanged_misses<>shared_misses||entries>64 then
    failwith"stable shared-index draw missed or decode cache exceeded capacity";
  let changed_vertices=Bytes.copy vertices in
  Bytes.set_int64_le changed_vertices 0(Int64.bits_of_float 1.);
  let changed_mesh:Scene_execution.mesh={shared_mesh with vertices=changed_vertices}in
  ignore(get(Scene_execution.render renderer[{shared_draw with mesh=changed_mesh}]));
  let _,changed_misses=Ogpu_raster2.decode_cache_stats control in
  if changed_misses<=unchanged_misses then
    failwith"changed vertex buffer did not invalidate decoded vertices";
  for version=0 to 79 do
    let changing=Bytes.copy vertices in
    Bytes.set_int64_le changing 0(Int64.bits_of_float(float version));
    let changing_mesh:Scene_execution.mesh={mesh with key="decode-lru-"^string_of_int version;
      vertices=changing}in
    ignore(get(Scene_execution.render renderer[{draw with mesh=changing_mesh}]))
  done;
  let cache_entries,_=Ogpu_raster2.decode_cache_stats control in
  if cache_entries>64 then failwith"decoded vertex cache did not remain bounded";
  get(Scene_execution.resize renderer {config with physical_width=8;physical_height=8});
  ignore(get(Scene_execution.render renderer [{draw with state={state with viewport=(0,0,8,8);scissor=(0,0,8,8)}}]));
  Ogpu_raster2.inject_device_loss control;
  if Ogpu_raster2.decode_cache_stats control|>fst<>0 then
    failwith"device loss retained decoded vertices";
  (match Scene_execution.render renderer [draw] with Error e when e.Ogpu.Error.kind=Device_lost->()|_->failwith"software device loss");
  let trace=Ogpu_raster2.trace control in get(Scene_execution.destroy renderer);
  if Ogpu_raster2.live_counts control<>(0,0,0,0,0)then failwith"software live delta";
  trace
let ()=
  let expected=run 600 in
  let workers=Array.init 4(fun _->Domain.spawn(fun()->run 600))in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"software domain drift")workers;
  let driver,control=Ogpu_raster2.create()in let device=get(Ogpu.Backend.create_device driver)in let queue=get(Ogpu.Backend.create_queue device)in
  let bd usage size:Ogpu.Types.buffer_descriptor={label=None;size;usage}and td usage:Ogpu.Types.texture_descriptor={label=None;width=4;height=4;depth=1;mip_levels=1;sample_count=1;usage}in
  let upload=get(Ogpu.Backend.create_buffer device(bd[Copy_src;Copy_dst]512L))and download=get(Ogpu.Backend.create_buffer device(bd[Copy_src;Copy_dst]512L))and texture=get(Ogpu.Backend.create_texture device(td[Texture_copy_dst;Texture_copy_src]))and texture2=get(Ogpu.Backend.create_texture device(td[Texture_copy_dst;Texture_copy_src]))in
  let source=Bytes.make 512 '\000'in for i=0 to 7 do Bytes.set source i(Char.chr(i+1))done;for i=0 to 7 do Bytes.set source(256+i)(Char.chr(i+9))done;get(Ogpu.Backend.write_buffer upload~offset:0L source);
  let pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in let origin:Ogpu.Transfer_pass.origin={x=1;y=1;z=0}and extent:Ogpu.Transfer_pass.extent={width=2;height=2;depth=1}in get(Ogpu.Transfer_pass.buffer_to_texture pass~src:(Ogpu.Backend.transfer_buffer upload)~offset:0L~bytes_per_row:256L~bytes_per_image:512L~dst:(Ogpu.Backend.transfer_texture texture)~mip:0~origin~extent);get(Ogpu.Transfer_pass.copy_texture pass~src:(Ogpu.Backend.transfer_texture texture)~src_mip:0~src_origin:origin~dst:(Ogpu.Backend.transfer_texture texture2)~dst_mip:0~dst_origin:{x=0;y=0;z=0}~extent);get(Ogpu.Transfer_pass.texture_to_buffer pass~src:(Ogpu.Backend.transfer_texture texture2)~mip:0~origin:{x=0;y=0;z=0}~extent~dst:(Ogpu.Backend.transfer_buffer download)~offset:0L~bytes_per_row:256L~bytes_per_image:512L);let command=get(Ogpu.Backend.transfer pass)in let receipt=get(Ogpu.Backend.submit queue command~resources:[`Buffer upload;`Buffer download;`Texture texture;`Texture texture2]~pipelines:[])in get(Ogpu.Backend.complete_through queue receipt.epoch);let copied=get(Ogpu.Backend.read_buffer download~offset:0L~length:512)in if Bytes.sub copied 0 8<>Bytes.sub source 0 8||Bytes.sub copied 256 8<>Bytes.sub source 256 8 then failwith"software pitched transfer";
  let odd_descriptor:Ogpu.Types.texture_descriptor={label=Some"odd-mips";width=5;height=3;depth=1;mip_levels=3;sample_count=1;usage=[Texture_copy_dst;Texture_copy_src]}in let odd=get(Ogpu.Backend.create_texture device odd_descriptor)in let one:Ogpu.Transfer_pass.extent={width=1;height=1;depth=1}and zero:Ogpu.Transfer_pass.origin={x=0;y=0;z=0}in let mip_pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle device)in get(Ogpu.Transfer_pass.buffer_to_texture mip_pass~src:(Ogpu.Backend.transfer_buffer upload)~offset:0L~bytes_per_row:256L~bytes_per_image:256L~dst:(Ogpu.Backend.transfer_texture odd)~mip:2~origin:zero~extent:one);get(Ogpu.Transfer_pass.texture_to_buffer mip_pass~src:(Ogpu.Backend.transfer_texture odd)~mip:2~origin:zero~extent:one~dst:(Ogpu.Backend.transfer_buffer download)~offset:32L~bytes_per_row:256L~bytes_per_image:256L);let mip_command=get(Ogpu.Backend.transfer mip_pass)in let mip_receipt=get(Ogpu.Backend.submit queue mip_command~resources:[`Buffer upload;`Buffer download;`Texture odd]~pipelines:[])in get(Ogpu.Backend.complete_through queue mip_receipt.epoch);let mip_bytes=get(Ogpu.Backend.read_buffer download~offset:32L~length:4)in if mip_bytes<>Bytes.sub source 0 4 then failwith"software explicit odd mip transfer";
  List.iter(fun texture->get(Ogpu.Backend.destroy_texture texture))[texture;texture2;odd];List.iter(fun buffer->get(Ogpu.Backend.destroy_buffer buffer))[upload;download];get(Ogpu.Backend.destroy_queue queue);get(Ogpu.Backend.destroy_device device);if Ogpu_raster2.live_counts control<>(0,0,0,0,0)then failwith"software transfer live delta";
  let driver,control=Ogpu_raster2.create()in let device=get(Ogpu.Backend.create_device driver)in
  let descriptor:Ogpu.Types.buffer_descriptor={label=None;size=4L;usage=[Copy_dst]}in
  for _=1 to 100_000 do let buffer=get(Ogpu.Backend.create_buffer device descriptor)in get(Ogpu.Backend.destroy_buffer buffer)done;
  let retained,dropped=Ogpu_raster2.trace_stats control in
  if retained<>256||dropped<99_744 then failwith"software diagnostic ring did not plateau";
  get(Ogpu.Backend.destroy_device device);
  if Ogpu_raster2.live_counts control<>(0,0,0,0,0)then failwith"software 100k growth";
  let driver,control=Ogpu_raster2.create()in
  let config:Ogpu.Surface.configuration={logical_width=4;logical_height=4;physical_width=4;physical_height=4;format=Rgba8_unorm;present_mode=Immediate;max_acquired=2}in
  let renderer=get(Scene_execution.create_variants driver config)in
  let indices=Bytes.make 12 '\000'and vertices=Bytes.make(68*3)'\000'in
  Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  List.iteri(fun index(x,y)->let offset=index*68 in Bytes.set_int64_le vertices offset(Int64.bits_of_float x);Bytes.set_int64_le vertices(offset+8)(Int64.bits_of_float y);Bytes.set_int64_le vertices(offset+40)(Int64.bits_of_float 1.);Bytes.set_int32_le vertices(offset+48)0xffffffffl)[0.,0.;4.,0.;0.,4.];
  let uniforms=Bytes.make 208 '\000'in for matrix=0 to 2 do for diagonal=0 to 3 do Bytes.set_int32_le uniforms((matrix*16+diagonal*5)*4)(Int32.bits_of_float 1.)done done;
  let mesh:Scene_execution.mesh={key="sampled-namespaces";vertices;vertex_count=3;indices;index_count=3}and state:Scene_execution.state={viewport=(0,0,4,4);scissor=(0,0,4,4);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;transform_uniforms=Some uniforms;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"namespace";min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
  let texture key rgba:Scene_execution.sampled_texture={key;levels=[|{width=1;height=1;bytes=Bytes.of_string rgba}|];sampler}in
  let red=texture"texture-one""\255\000\000\255"and green=texture"texture-four""\000\255\000\255"in
  let auxiliary:Scene_execution.auxiliary_resource={key="shadow-four";buffer=Bytes.make 84 '\000';texture=green}in
  let draw={Scene_execution.mesh;state}and stable=ref None in
  List.iter(fun _->ignore(get(Scene_execution.render_sampled_resources renderer[Scene3_textured,Ogpu.Pipeline.Replace,Some red,None,1,draw]));let pixels=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in if Char.code(Bytes.get pixels 0)<>255 then failwith"texture1/sampler2 exact pixel";ignore(get(Scene_execution.render_sampled_resources renderer[Scene3_shadow,Ogpu.Pipeline.Replace,None,Some auxiliary,1,draw]));let pixels=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in if Char.code(Bytes.get pixels 1)<>255 then failwith"shadow texture4/sampler5 exact pixel";let uploaded=Scene_execution.upload_bytes renderer in match!stable with None->stable:=Some uploaded|Some old when old=uploaded->()|Some _->failwith"sampled resources reuploaded")[1;2;60;600];
  get(Scene_execution.destroy renderer);if Ogpu_raster2.live_counts control<>(0,0,0,0,0)then failwith"sampled resources live delta";
  print_endline"ogpu_raster2: frames1/2/60/600+resize, 4-domain, 100k zero delta"
