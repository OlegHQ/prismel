open Metal
let fail f=Printf.ksprintf failwith f
let get=function Ok x->x|Error e->fail "%s"(Format.asprintf"%a"pp_error e)
let reject=function Error _->()|Ok _->failwith"expected rejection"
let ()=
 reject(Resource100.View_pool_descriptor.create~count:0L());
 let d=get(Resource100.Buffer_layout.create~stride:16L~step_rate:1L())in
 if Resource100.Buffer_layout.stride d<>16L||Resource100.Buffer_layout.step_rate d<>1L then failwith"layout snapshot";
 get(Resource100.Buffer_layout.set_stride d 32L);if Resource100.Buffer_layout.stride d<>32L then failwith"layout mutation";
 get(Resource100.Buffer_layout.destroy d);reject(Resource100.Buffer_layout.set_stride d 8L);
 let a=get(Resource100.Sample_attachment.create())in
 get(Resource100.Sample_attachment.set_range a ~start:(Index 2L) ~finish:(Index 5L));
 if Resource100.Sample_attachment.range a<>(2L,5L)then failwith"sample range";
 get(Resource100.Sample_attachment.destroy a);
 for i=1 to 10000 do let x=get(Resource100.View_pool_descriptor.create~label:(string_of_int i)~count:4L())in if Resource100.View_pool_descriptor.count x<>4L then failwith"descriptor count";get(Resource100.View_pool_descriptor.destroy x)done;
 let device=get(Device.system_default())in let desc=get(Resource100.View_pool_descriptor.create~count:4L())in
 let texture=get(Texture.create~device(Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Shader_read;Texture.Shader_write]~format:Texture.Rgba8_unorm~width:4~height:4()))in
 if get(Resource100.Resource_ops.device(Resource100.Resource_ops.Texture texture))!=device then failwith"resource device";
 (match get(Resource100.Resource_ops.heap(Resource100.Resource_ops.Texture texture))with None->()|Some _->failwith"device texture heap");
 (match get(Resource100.Texture_ops.buffer_backing texture)with None->()|Some _->failwith"standalone texture has a buffer parent");
 (match get(Resource100.Texture_ops.root_resource texture)with Resource100.Resource_ops.Texture root when root==texture->()|_->failwith"texture root");
 (match get(Resource100.Texture_ops.remote_view texture~device)with None->()|Some remote->get(Texture.destroy remote));
 (match get(Resource100.Texture_ops.remote_storage texture)with None->()|Some remote->get(Texture.destroy remote));
 let backing_buffer=get(Buffer.create~device~length:4096L~storage:Buffer.Shared())in
 if get(Resource100.Resource_ops.device(Resource100.Resource_ops.Buffer backing_buffer))!=device then failwith"buffer device";
 (match get(Resource100.Buffer_ops.remote_view backing_buffer~device)with
  |None->()|Some remote->if Buffer.length remote<>4096L then failwith"remote buffer length"else get(Buffer.destroy remote));
 (match get(Resource100.Buffer_ops.remote_storage backing_buffer)with
  |None->()|Some remote->if Buffer.length remote<>4096L then failwith"remote storage length"else get(Buffer.destroy remote));
 let backed=get(Texture.create_from_buffer~buffer:backing_buffer~offset:0L~bytes_per_row:256
   (Texture.descriptor_2d~storage:Buffer.Shared~usage:[Texture.Shader_read]
      ~format:Texture.Rgba8_unorm~width:4~height:4()))in
 (match get(Resource100.Texture_ops.root_resource backed)with Resource100.Resource_ops.Buffer root when root==backing_buffer->()|_->failwith"buffer texture root");
 for _=1 to 10000 do
   match get(Resource100.Texture_ops.buffer_backing backed)with
   |Some b when b.buffer==backing_buffer&&b.offset=0L&&b.bytes_per_row=256->()
   |_->failwith"buffer-backed texture graph"
 done;
 let bytes=Bytes.make 64 '\000'in
 reject(Resource100.Texture_ops.get_bytes texture~bytes~bytes_per_row:16~mip_level:0~region:{x=0;y=0;z=0;width=4;height=4;depth=2});
 reject(Resource100.Texture_ops.get_bytes texture~bytes~bytes_per_row:max_int~mip_level:0~region:{x=0;y=0;z=0;width=4;height=4;depth=1});
 reject(Resource100.Texture_ops.get_bytes texture~bytes:(Bytes.create 8)~bytes_per_row:16~mip_level:0~region:{x=0;y=0;z=0;width=4;height=1;depth=1});
 (match Resource100.Texture_view_pool.create device desc with Ok pool->if Resource100.Texture_view_pool.count pool<>4L then failwith"pool count";if get(Resource100.Texture_view_pool.checked_device pool)!=device then failwith"pool device";ignore(get(Resource100.Texture_view_pool.base_resource_id pool));ignore(get(Resource100.Texture_view_pool.label pool));get(Resource100.Texture_view_pool.destroy pool)|Error _->());
 get(Texture.destroy backed);get(Buffer.destroy backing_buffer);
 get(Texture.destroy texture);get(Resource100.View_pool_descriptor.destroy desc);get(Device.destroy device)
