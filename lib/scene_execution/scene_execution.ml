type mesh={key:string;vertices:bytes;vertex_count:int;indices:bytes;index_count:int}
type state={viewport:int*int*int*int;scissor:int*int*int*int}
type draw={mesh:mesh;state:state}
type cached={key:string;payload_hash:string;buffer:Ogpu.Backend.buffer;index_offset:int64;vertex_count:int;index_count:int}
type pipeline_variant={blend:Ogpu.Pipeline.blend;pipeline:Ogpu.Backend.pipeline;key:string}
type t={device:Ogpu.Backend.device;queue:Ogpu.Backend.queue;surface:Ogpu.Backend.surface;mutable target:Ogpu.Backend.texture;pipelines:pipeline_variant list;mutable cache:cached list;mutable uploaded:int64;mutable dead:bool;before_device_destroy:unit->(unit,Ogpu.Error.t)result}
let error op kind text=Error(Ogpu.Error.make op kind text)
let get_cleanup result cleanup=match result with Ok value->Ok value|Error _ as e->cleanup();e
let shader stage name=Ogpu.Shader.create{backend="mock";label=Some name;bytes=Bytes.of_string name;entry_points=[{Ogpu.Shader.name;stage}];bindings=[]}
let pipeline device blend=let capabilities=Ogpu.Backend.capabilities device in let open Result in
  bind(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities[])(fun layout->
  bind(shader Ogpu.Shader.Vertex"scene_vertex")(fun vertex->bind(shader Fragment"scene_fragment")(fun fragment->
  bind(Ogpu.Pipeline.create_render~blend capabilities{backend="mock";label=Some"scene-execution";layout;vertex;vertex_entry="scene_vertex";fragment=Some fragment;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1})(fun portable->
  map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable)))))
let texture_descriptor configuration:Ogpu.Types.texture_descriptor={label=Some"scene-execution-target";width=configuration.Ogpu.Surface.physical_width;height=configuration.physical_height;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}
let blends=[Ogpu.Pipeline.Replace;Alpha;Add;Multiply;Screen;Subtract]
let create_common driver configuration before_device_destroy variants_to_make supplied=match Ogpu.Backend.create_device driver with Error _ as e->e|Ok device->
  let cleanup()=ignore(Ogpu.Backend.destroy_device device)in
  get_cleanup(match Ogpu.Backend.create_queue device with Error _ as e->e|Ok queue->
    get_cleanup(match Ogpu.Backend.create_surface device configuration with Error _ as e->e|Ok surface->
    let make blend=match supplied with None->pipeline device blend|Some make->Result.bind(make device blend)(fun portable->Result.map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable))in
    let rec variants made=function []->Ok(List.rev made)|blend::rest->match make blend with Error e->List.iter(fun x->ignore(Ogpu.Backend.destroy_pipeline x.pipeline))made;Error e|Ok(pipeline,key)->variants({blend;pipeline;key}::made)rest in
    get_cleanup(match Ogpu.Backend.create_texture device(texture_descriptor configuration),variants[]variants_to_make with
      |Ok target,Ok pipelines->Ok{device;queue;surface;target;pipelines;cache=[];uploaded=0L;dead=false;before_device_destroy}
      |Error e,_|_,Error e->Error e)(fun()->ignore(Ogpu.Backend.destroy_surface surface)))(fun()->ignore(Ogpu.Backend.destroy_queue queue)))cleanup
let create driver configuration=create_common driver configuration(fun()->Ok())blends None
let create_with_pipeline_variants driver configuration ?(before_device_destroy=fun()->Ok()) pipeline=create_common driver configuration before_device_destroy blends(Some pipeline)
let create_with_pipeline driver configuration ?(before_device_destroy=fun()->Ok()) make=
  create_common driver configuration before_device_destroy[Ogpu.Pipeline.Replace]
    (Some(fun device _blend->make device))
let prepare value (mesh:mesh)=let payload_hash=Digest.to_hex(Digest.string(Bytes.to_string mesh.vertices^Bytes.to_string mesh.indices))in match List.find_opt(fun(x:cached)->x.key=mesh.key&&x.payload_hash=payload_hash)value.cache with Some item->Ok item|None->
  let total=Bytes.length mesh.vertices+Bytes.length mesh.indices in
  if mesh.key=""||mesh.vertex_count<=0||mesh.index_count<=0||total=0 then error"Scene_execution.prepare"Ogpu.Error.Invalid_argument"mesh payload is empty"else
  let descriptor:Ogpu.Types.buffer_descriptor={label=Some("scene-mesh-"^mesh.key);size=Int64.of_int total;usage=[Vertex;Index;Copy_dst]}in
  match Ogpu.Backend.create_buffer value.device descriptor with Error _ as e->e|Ok buffer->
    let offset=Int64.of_int(Bytes.length mesh.vertices)in match Ogpu.Backend.write_buffer buffer~offset:0L mesh.vertices with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->match Ogpu.Backend.write_buffer buffer~offset mesh.indices with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->let item={key=mesh.key;payload_hash;buffer;index_offset=offset;vertex_count=mesh.vertex_count;index_count=mesh.index_count}in let replaced,others=List.partition(fun(x:cached)->x.key=mesh.key)value.cache in List.iter(fun x->ignore(Ogpu.Backend.destroy_buffer x.buffer))replaced;let cache=item::others in let keep,evict=List.mapi(fun i x->i,x)cache|>List.partition(fun(i,_)->i<64)in List.iter(fun(_,x)->ignore(Ogpu.Backend.destroy_buffer x.buffer))evict;value.cache<-List.map snd keep;value.uploaded<-Int64.add value.uploaded(Int64.of_int total);Ok item
let pass value state load clear=let texture=Ogpu.Backend.render_texture value.target~format:Ogpu.Render_pass.Rgba8~usage:Render_target in let x,y,width,height=state.viewport and sx,sy,sw,sh=state.scissor in Ogpu.Render_pass.create(Ogpu.Backend.device_handle value.device){colors=[|Some{texture;resolve=None;load;store=Store;clear}|];depth=None;stencil=None;viewport={x;y;width;height};scissor={x=sx;y=sy;width=sw;height=sh}}
let render_blended ?(clear=(0.,0.,0.,0.)) value draws=if value.dead then error"Scene_execution.render"Ogpu.Error.Stale_handle"renderer is destroyed"else
  let rec prepare_all acc=function []->Ok(List.rev acc)|(blend,(draw:draw))::rest->match prepare value draw.mesh with Error _ as e->e|Ok mesh->prepare_all((blend,draw.state,mesh)::acc)rest in
  match prepare_all[]draws with Error _ as e->e|Ok prepared->match Ogpu.Backend.acquire value.surface with Error _ as e->e|Ok(`Timeout|`Occluded)->Ok false|Ok`Device_lost->error"Scene_execution.render"Device_lost"device lost"|Ok(`Acquired frame)->
    let resources=`Texture value.target::List.map(fun(_,_,x)->`Buffer x.buffer)prepared in
    let rec take blend state acc=function (next_blend,next,item)::rest when next_blend=blend&&next=state->take blend state((next_blend,next,item)::acc)rest|rest->List.rev acc,rest in
    let rec batches first=function []->Ok()|(blend,state,item)::rest->let same,rest=take blend state[(blend,state,item)]rest in match List.find_opt(fun value->value.blend=blend)value.pipelines with None->error"Scene_execution.render"Ogpu.Error.Unsupported"blend pipeline variant is unavailable"|Some variant->match pass value state(if first then Ogpu.Render_pass.Clear else Load)clear with Error _ as e->e|Ok pass->let payload=List.map(fun(_,_,item)->{Ogpu.Render_pass.pipeline_key=variant.key;buffers=[{stage=Ogpu.Command.Vertex;index=0;buffer_id=Ogpu.Backend.buffer_id item.buffer;offset=0L}];textures=[];samplers=[];primitive=Triangle_list;vertex_start=0;vertex_count=item.vertex_count;index=Some(Uint32,Ogpu.Backend.buffer_id item.buffer,item.index_offset,item.index_count)})same in match Ogpu.Backend.render pass payload with Error _ as e->e|Ok command->match Ogpu.Backend.submit value.queue command~resources~pipelines:[variant.pipeline]with Error _ as e->e|Ok receipt->match Ogpu.Backend.complete_through value.queue receipt.epoch with Error _ as e->e|Ok()->batches false rest in
    (match batches true prepared with Error e->ignore(Ogpu.Backend.discard frame);Error e|Ok()->Result.map(fun()->true)(Ogpu.Backend.present frame))
let render ?clear value draws=render_blended ?clear value(List.map(fun draw->Ogpu.Pipeline.Replace,draw)draws)
let resize value configuration=match Ogpu.Backend.create_texture value.device(texture_descriptor configuration)with Error _ as e->e|Ok target->match Ogpu.Backend.configure value.surface configuration with Error e->ignore(Ogpu.Backend.destroy_texture target);Error e|Ok()->let old=value.target in value.target<-target;Ogpu.Backend.destroy_texture old
let upload_bytes value=value.uploaded
let cache_entries value=List.length value.cache
let read_pixels value ~bytes_per_row=Ogpu.Backend.read_texture value.target~bytes_per_row
let destroy value=if value.dead then Ok()else(value.dead<-true;List.iter(fun item->ignore(Ogpu.Backend.destroy_buffer item.buffer))value.cache;value.cache<-[];ignore(Ogpu.Backend.destroy_texture value.target);List.iter(fun variant->ignore(Ogpu.Backend.destroy_pipeline variant.pipeline))value.pipelines;ignore(Ogpu.Backend.destroy_surface value.surface);ignore(Ogpu.Backend.destroy_queue value.queue);match value.before_device_destroy()with Error _ as e->e|Ok()->Ogpu.Backend.destroy_device value.device)
