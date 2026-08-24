open Metal
let fail f=Printf.ksprintf failwith f
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf"%a"pp_error e)
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 if Resource100.Options.cpu_cache_code Resource100.Options.Default<>0L||Resource100.Options.cpu_cache_code Resource100.Options.Write_combined<>1L||Resource100.Options.storage_code Resource100.Options.Memoryless<>48L then failwith"resource option aliases";
 reject(Resource100.View_pool_descriptor.create~count:0L());
 let d=get(Resource100.Buffer_layout.create~stride:16L~step_rate:1L())in
 if Resource100.Buffer_layout.stride d<>16L||Resource100.Buffer_layout.step_rate d<>1L then failwith"layout snapshot";
 get(Resource100.Buffer_layout.set_stride d 32L);if Resource100.Buffer_layout.stride d<>32L then failwith"layout mutation";
 let layouts=get(Resource100.Buffer_layout_array.create())in
 reject(Resource100.Buffer_layout_array.get layouts~index:31);
 get(Resource100.Buffer_layout_array.set layouts~index:0(Some d));
 (match get(Resource100.Buffer_layout_array.get layouts~index:0)with Some copy when Resource100.Buffer_layout.stride copy=32L->get(Resource100.Buffer_layout.destroy copy)|_->failwith"layout array roundtrip");
 get(Resource100.Buffer_layout_array.set layouts~index:0 None);
 get(Resource100.Buffer_layout_array.destroy layouts);
 get(Resource100.Buffer_layout.destroy d);reject(Resource100.Buffer_layout.set_stride d 8L);
 let a=get(Resource100.Sample_attachment.create())in
 get(Resource100.Sample_attachment.set_range a ~start:(Index 2L) ~finish:(Index 5L));
 if Resource100.Sample_attachment.range a<>(2L,5L)then failwith"sample range";
 get(Resource100.Sample_attachment.destroy a);
 for i=1 to 10000 do let x=get(Resource100.View_pool_descriptor.create~label:(string_of_int i)~count:4L())in if Resource100.View_pool_descriptor.count x<>4L then failwith"descriptor count";get(Resource100.View_pool_descriptor.destroy x)done;
 let device=get(Device.system_default())in let desc=get(Resource100.View_pool_descriptor.create~count:4L())in
 let buffer_descriptor=Texture.descriptor_buffer~format:Texture.Rgba8_unorm~width:4()in
 let cube_descriptor=Texture.descriptor_cube~format:Texture.Rgba8_unorm~size:4()in
 let cube=get(Texture.create~device cube_descriptor)in get(Texture.destroy cube);
 let heap=get(Heap.create~device(Heap.make_descriptor~size:1048576L()))in
 if get(Resource100.Heap_ops.checked_device heap)!=device then failwith"heap device";
 reject(Resource100.Heap_ops.create_acceleration_structure heap~size:0L);
 (match Resource100.Heap_ops.create_acceleration_structure heap~size:4096L with
  |Ok acceleration->get(Acceleration_structure.destroy acceleration)
  |Error _->());
 let texture=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Shader_read;Texture.Shader_write]~format:Texture.Rgba8_unorm~width:4~height:4()))in
 if get(Resource100.Resource_ops.device(Resource100.Resource_ops.Texture texture))!=device then failwith"resource device";
 (match get(Resource100.Resource_ops.heap(Resource100.Resource_ops.Texture texture))with None->()|Some _->failwith"device texture heap");
 (match get(Resource100.Texture_ops.buffer_backing texture)with None->()|Some _->failwith"standalone texture has a buffer parent");
 (match get(Resource100.Texture_ops.root_resource texture)with None->()|Some _->failwith"root texture unexpectedly has a parent");
 (match get(Resource100.Texture_ops.remote_view texture~device)with None->()|Some remote->get(Texture.destroy remote));
 (match get(Resource100.Texture_ops.remote_storage texture)with None->()|Some remote->get(Texture.destroy remote));
 let backing_buffer=get(Buffer.create~device~length:4096L~storage:Buffer.Shared())in
 if get(Resource100.Resource_ops.device(Resource100.Resource_ops.Buffer backing_buffer))!=device then failwith"buffer device";
 (match get(Resource100.Buffer_ops.remote_view backing_buffer~device)with
  |None->()|Some remote->if Buffer.length remote<>4096L then failwith"remote buffer length"else get(Buffer.destroy remote));
 (match get(Resource100.Buffer_ops.remote_storage backing_buffer)with
  |None->()|Some remote->if Buffer.length remote<>4096L then failwith"remote storage length"else get(Buffer.destroy remote));
 let backed=get(Texture.create_from_buffer~buffer:backing_buffer~offset:0L~bytes_per_row:256
   buffer_descriptor)in
 (match get(Resource100.Texture_ops.root_resource backed)with Some(Resource100.Resource_ops.Buffer root)when root==backing_buffer->()|_->failwith"buffer texture root");
 for _=1 to 10000 do
   match get(Resource100.Texture_ops.buffer_backing backed)with
   |Some b when b.buffer==backing_buffer&&b.offset=0L&&b.bytes_per_row=256->()
   |_->failwith"buffer-backed texture graph"
 done;
 let bytes=Bytes.make 64 '\000'in
 reject(Resource100.Texture_ops.get_bytes texture~bytes~bytes_per_row:16~mip_level:0~region:{x=0;y=0;z=0;width=4;height=4;depth=2});
 reject(Resource100.Texture_ops.get_bytes texture~bytes~bytes_per_row:max_int~mip_level:0~region:{x=0;y=0;z=0;width=4;height=4;depth=1});
 reject(Resource100.Texture_ops.get_bytes texture~bytes:(Bytes.create 8)~bytes_per_row:16~mip_level:0~region:{x=0;y=0;z=0;width=4;height=1;depth=1});
 let queue=get(Command_queue.create device)in
 let commands=get(Command_buffer.create queue())in
 let state_pass=get(Resource100.Resource_state_pass.create())in
 let copied_attachment=get(Resource100.Sample_attachment.create~start:(Index 1L)~finish:(Index 2L)())in
 get(Resource100.Resource_state_pass.set_sample_attachment state_pass~index:0(Some copied_attachment));
 get(Resource100.Sample_attachment.destroy copied_attachment);
 for _=1 to 10000 do match get(Resource100.Resource_state_pass.sample_attachment state_pass~index:0)with
   |Some copy when Resource100.Sample_attachment.range copy=(1L,2L)->get(Resource100.Sample_attachment.destroy copy)
   |_->failwith"sample attachment copy semantics"done;
 get(Resource100.Resource_state_pass.set_sample_attachment state_pass~index:0 None);
 (match get(Resource100.Resource_state_pass.sample_attachment state_pass~index:0)with
  |Some default->get(Resource100.Sample_attachment.destroy default)|None->());
 reject(Resource100.Resource_state_pass.sample_attachment state_pass~index:4);
 let state_encoder=get(Resource100.Resource_state_pass.create_encoder commands state_pass)in
 reject(Resource_state_encoder.move_texture_mappings state_encoder~source:texture
   ~source_slice:0~source_level:0
   ~source_region:{x=0;y=0;z=0;width=1;height=1;depth=1}
   ~destination:texture~destination_slice:0~destination_level:0
   ~destination_origin:(0,0,0));
 get(Resource_state_encoder.end_encoding state_encoder);get(Command_buffer.commit commands);
 get(Command_buffer.wait_until_completed commands);get(Command_buffer.destroy commands);
 get(Resource100.Resource_state_pass.destroy state_pass);get(Command_queue.destroy queue);
 (match Resource100.Texture_view_pool.create device desc with Ok pool->if Resource100.Texture_view_pool.count pool<>4L then failwith"pool count";if get(Resource100.Texture_view_pool.checked_device pool)!=device then failwith"pool device";ignore(get(Resource100.Texture_view_pool.base_resource_id pool));ignore(get(Resource100.Texture_view_pool.label pool));reject(Resource100.Texture_view_pool.set_from_buffer pool~index:0 backing_buffer~offset:(-1L)~bytes_per_row:256(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Shader_read]~format:Texture.Rgba8_unorm~width:4~height:1()));get(Resource100.Texture_view_pool.destroy pool)|Error _->());
 if get(Device.supports_sparse_textures device)then(match List.find_map(fun page->match Heap.sparse_tile_size_in_bytes~device page with Ok bytes->Some(page,bytes)|Error _->None)[Sparse_page_size.Page_64_kib;Sparse_page_size.Page_16_kib;Sparse_page_size.Page_256_kib]with None->failwith"sparse device has no page size"|Some(page,page_bytes)->let sparse_heap=get(Heap.create~device(Heap.make_descriptor~kind:Heap.Sparse~sparse_page_size:page~size:(Int64.mul 2L page_bytes)()))in let sparse_descriptor=Texture.descriptor_2d~storage:Buffer.Private~usage:[Texture.Shader_read]~format:Texture.R8_uint~width:1024~height:1024()in let source=get(Heap.create_texture sparse_heap sparse_descriptor)and destination=get(Heap.create_texture sparse_heap sparse_descriptor)in let queue=get(Command_queue.create device)in let commands=get(Command_buffer.create queue())in let encoder=get(Resource_state_encoder.create commands)in get(Resource_state_encoder.move_texture_mappings encoder~source~source_slice:0~source_level:0~source_region:{x=0;y=0;z=0;width=1;height=1;depth=1}~destination~destination_slice:0~destination_level:0~destination_origin:(0,0,0));get(Resource_state_encoder.end_encoding encoder);get(Command_buffer.commit commands);get(Command_buffer.wait_until_completed commands);get(Command_buffer.destroy commands);get(Command_queue.destroy queue);get(Texture.destroy destination);get(Texture.destroy source);get(Heap.destroy sparse_heap));
 get(Texture.destroy backed);get(Buffer.destroy backing_buffer);
 get(Texture.destroy texture);get(Heap.destroy heap);get(Resource100.View_pool_descriptor.destroy desc);get(Device.destroy device)
