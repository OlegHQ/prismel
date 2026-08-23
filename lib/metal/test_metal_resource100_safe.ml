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
 let a=get(Resource100.Sample_attachment.create())in get(Resource100.Sample_attachment.set_sample_buffer a None);get(Resource100.Sample_attachment.destroy a);
 for i=1 to 10000 do let x=get(Resource100.View_pool_descriptor.create~label:(string_of_int i)~count:4L())in if Resource100.View_pool_descriptor.count x<>4L then failwith"descriptor count";get(Resource100.View_pool_descriptor.destroy x)done;
 let device=get(Device.system_default())in let desc=get(Resource100.View_pool_descriptor.create~count:4L())in
 (match Resource100.Texture_view_pool.create device desc with Ok pool->if Resource100.Texture_view_pool.count pool<>4L then failwith"pool count";get(Resource100.Texture_view_pool.destroy pool)|Error _->());
 get(Resource100.View_pool_descriptor.destroy desc);get(Device.destroy device)
