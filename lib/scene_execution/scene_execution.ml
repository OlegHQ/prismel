type mesh={key:string;vertices:bytes;vertex_count:int;indices:bytes;index_count:int}
type state={viewport:int*int*int*int;scissor:int*int*int*int}
type draw={mesh:mesh;state:state}
type pipeline_family=Scene2|Scene3|Scene3_textured
type texture_level={width:int;height:int;bytes:bytes}
type sampled_texture={key:string;levels:texture_level array;sampler:Ogpu.Types.sampler_descriptor}
type shadow_resource={texture:sampled_texture;parameters:bytes}
type cached={key:string;payload_hash:string;buffer:Ogpu.Backend.buffer;index_offset:int64;vertex_count:int;index_count:int}
type cached_texture={texture_key:string;texture_hash:string;texture:Ogpu.Backend.texture}
type pipeline_variant={family:pipeline_family;blend:Ogpu.Pipeline.blend;pipeline:Ogpu.Backend.pipeline;key:string}
type t={device:Ogpu.Backend.device;queue:Ogpu.Backend.queue;surface:Ogpu.Backend.surface;mutable target:Ogpu.Backend.texture;pipelines:pipeline_variant list;mutable cache:cached list;mutable texture_cache:cached_texture list;mutable uploaded:int64;mutable dead:bool;before_device_destroy:unit->(unit,Ogpu.Error.t)result}
let error op kind text=Error(Ogpu.Error.make op kind text)
let set_u32_le bytes offset value =
  let open Int32 in
  Bytes.set bytes offset (Char.chr (to_int (logand value 0xffl)));
  Bytes.set bytes (offset + 1) (Char.chr (to_int (logand (shift_right_logical value 8) 0xffl)));
  Bytes.set bytes (offset + 2) (Char.chr (to_int (logand (shift_right_logical value 16) 0xffl)));
  Bytes.set bytes (offset + 3) (Char.chr (to_int (shift_right_logical value 24)))
let set_f32_le bytes offset value = set_u32_le bytes offset (Int32.bits_of_float value)
let shadow_resource ~key (source:Raster2.Shadow_map.snapshot) =
  let finite=Float.is_finite in
  if key=""||source.width<=0||source.height<=0||Array.length source.depths<>source.width*source.height||Array.length source.matrix<>16 then
    error"Scene_execution.shadow_resource"Ogpu.Error.Invalid_argument"shadow extent or matrix is malformed"
  else if not(Array.for_all(fun depth->finite depth&&depth>=0.&&depth<=1.)source.depths&&Array.for_all finite source.matrix&&finite source.bias.constant&&finite source.bias.slope&&finite source.strength&&source.bias.constant>=0.&&source.bias.slope>=0.&&source.strength>=0.&&source.strength<=1.)then
    error"Scene_execution.shadow_resource"Ogpu.Error.Invalid_argument"shadow parameters are non-finite or out of range"
  else
    let pixels=Bytes.create(source.width*source.height*4)in
    Array.iteri(fun index depth->let value=int_of_float(floor(depth*.16777215.+.0.5))in let offset=index*4 in Bytes.set pixels offset(Char.chr((value lsr 16)land 255));Bytes.set pixels(offset+1)(Char.chr((value lsr 8)land 255));Bytes.set pixels(offset+2)(Char.chr(value land 255));Bytes.set pixels(offset+3)'\255')source.depths;
    let parameters=Bytes.create(21*4)in Array.iteri(fun index value->set_f32_le parameters(index*4)value)source.matrix;
    set_f32_le parameters 64 source.bias.constant;set_f32_le parameters 68 source.bias.slope;set_f32_le parameters 72 source.strength;
    let radius=match source.kernel with Tap1->0.|Tap4->1.|Tap9->1.|Tap25->2. in set_f32_le parameters 76 radius;set_f32_le parameters 80 1.;
    let sampler:Ogpu.Types.sampler_descriptor={label=Some("scene-shadow-"^key);min_filter=Nearest;mag_filter=Nearest;mip_filter=Nearest_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
    Ok{texture={key="shadow:"^key;levels=[|{width=source.width;height=source.height;bytes=pixels}|];sampler};parameters}
let get_cleanup result cleanup=match result with Ok value->Ok value|Error _ as e->cleanup();e
let shader stage ~entry artifact=Ogpu.Shader.create{backend="mock";label=Some artifact;bytes=Bytes.of_string artifact;entry_points=[{Ogpu.Shader.name=entry;stage}];bindings=[]}
let pipeline device family blend=let capabilities=Ogpu.Backend.capabilities device in let open Result in
  bind(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities[])(fun layout->
  let suffix=match family with Scene2->"scene2"|Scene3->"scene3"|Scene3_textured->"scene3-textured"in
  bind(shader Ogpu.Shader.Vertex~entry:"scene_vertex"("scene_vertex-"^suffix))(fun vertex->bind(shader Fragment~entry:"scene_fragment"("scene_fragment-"^suffix))(fun fragment->
  bind(Ogpu.Pipeline.create_render~blend capabilities{backend="mock";label=Some"scene-execution";layout;vertex;vertex_entry="scene_vertex";fragment=Some fragment;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1})(fun portable->
  map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable)))))
let texture_descriptor configuration:Ogpu.Types.texture_descriptor={label=Some"scene-execution-target";width=configuration.Ogpu.Surface.physical_width;height=configuration.physical_height;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}
let blends=[Ogpu.Pipeline.Replace;Alpha;Add;Multiply;Screen;Subtract]
let families=[Scene2;Scene3;Scene3_textured]
let create_common driver configuration before_device_destroy families_to_make variants_to_make supplied=match Ogpu.Backend.create_device driver with Error _ as e->e|Ok device->
  let cleanup()=ignore(Ogpu.Backend.destroy_device device)in
  get_cleanup(match Ogpu.Backend.create_queue device with Error _ as e->e|Ok queue->
    get_cleanup(match Ogpu.Backend.create_surface device configuration with Error _ as e->e|Ok surface->
    let make family blend=match supplied with None->pipeline device family blend|Some make->Result.bind(make device family blend)(fun portable->Result.map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable))in
    let requested=List.concat_map(fun family->List.map(fun blend->family,blend)variants_to_make)families_to_make in
    let rec variants made=function []->Ok(List.rev made)|(family,blend)::rest->match make family blend with Error e->List.iter(fun x->ignore(Ogpu.Backend.destroy_pipeline x.pipeline))made;Error e|Ok(pipeline,key)->variants({family;blend;pipeline;key}::made)rest in
    get_cleanup(match Ogpu.Backend.create_texture device(texture_descriptor configuration),variants[]requested with
      |Ok target,Ok pipelines->Ok{device;queue;surface;target;pipelines;cache=[];texture_cache=[];uploaded=0L;dead=false;before_device_destroy}
      |Error e,_|_,Error e->Error e)(fun()->ignore(Ogpu.Backend.destroy_surface surface)))(fun()->ignore(Ogpu.Backend.destroy_queue queue)))cleanup
let create driver configuration=create_common driver configuration(fun()->Ok())[Scene2]blends None
let create_variants driver configuration=create_common driver configuration(fun()->Ok())families blends None
let create_with_pipeline_variants driver configuration ?(before_device_destroy=fun()->Ok()) pipeline=create_common driver configuration before_device_destroy families blends(Some pipeline)
let create_with_pipeline driver configuration ?(before_device_destroy=fun()->Ok()) make=
  create_common driver configuration before_device_destroy[Scene2][Ogpu.Pipeline.Replace]
    (Some(fun device _family _blend->make device))
let prepare value (mesh:mesh)=let payload_hash=Digest.to_hex(Digest.string(Bytes.to_string mesh.vertices^Bytes.to_string mesh.indices))in match List.find_opt(fun(x:cached)->x.key=mesh.key&&x.payload_hash=payload_hash)value.cache with Some item->Ok item|None->
  let total=Bytes.length mesh.vertices+Bytes.length mesh.indices in
  if mesh.key=""||mesh.vertex_count<=0||mesh.index_count<=0||total=0 then error"Scene_execution.prepare"Ogpu.Error.Invalid_argument"mesh payload is empty"else
  let descriptor:Ogpu.Types.buffer_descriptor={label=Some("scene-mesh-"^mesh.key);size=Int64.of_int total;usage=[Vertex;Index;Copy_dst]}in
  match Ogpu.Backend.create_buffer value.device descriptor with Error _ as e->e|Ok buffer->
    let offset=Int64.of_int(Bytes.length mesh.vertices)in match Ogpu.Backend.write_buffer buffer~offset:0L mesh.vertices with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->match Ogpu.Backend.write_buffer buffer~offset mesh.indices with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->let item={key=mesh.key;payload_hash;buffer;index_offset=offset;vertex_count=mesh.vertex_count;index_count=mesh.index_count}in let replaced,others=List.partition(fun(x:cached)->x.key=mesh.key)value.cache in List.iter(fun x->ignore(Ogpu.Backend.destroy_buffer x.buffer))replaced;let cache=item::others in let keep,evict=List.mapi(fun i x->i,x)cache|>List.partition(fun(i,_)->i<64)in List.iter(fun(_,x)->ignore(Ogpu.Backend.destroy_buffer x.buffer))evict;value.cache<-List.map snd keep;value.uploaded<-Int64.add value.uploaded(Int64.of_int total);Ok item
let align256 value=(value+255)land(lnot 255)
let prepare_texture value(source:sampled_texture)=
  let hash=Digest.to_hex(Digest.string(Array.to_list source.levels|>List.map(fun level->string_of_int level.width^"x"^string_of_int level.height^Bytes.to_string level.bytes)|>String.concat"|"))in
  match List.find_opt(fun item->item.texture_key=source.key&&item.texture_hash=hash)value.texture_cache with
  |Some item->Ok item
  |None->
    let valid=source.key<>""&&Array.length source.levels>0&&Array.mapi(fun index level->level.width=max 1(source.levels.(0).width lsr index)&&level.height=max 1(source.levels.(0).height lsr index)&&Bytes.length level.bytes=level.width*level.height*4)source.levels|>Array.for_all Fun.id in
    if not valid then error"Scene_execution.prepare_texture"Ogpu.Error.Invalid_argument"mip chain is malformed"else
    let descriptor:Ogpu.Types.texture_descriptor={label=Some("scene-texture-"^source.key);width=source.levels.(0).width;height=source.levels.(0).height;depth=1;mip_levels=Array.length source.levels;sample_count=1;usage=[Texture_binding;Texture_copy_dst]}in
    match Ogpu.Backend.create_texture value.device descriptor with Error _ as e->e|Ok texture->
    let rows=Array.map(fun level->align256(level.width*4))source.levels in
    let offsets=Array.make(Array.length source.levels)0 in
    for index=1 to Array.length offsets-1 do offsets.(index)<-offsets.(index-1)+rows.(index-1)*source.levels.(index-1).height done;
    let total=offsets.(Array.length offsets-1)+rows.(Array.length rows-1)*source.levels.(Array.length rows-1).height in
    let staging_descriptor:Ogpu.Types.buffer_descriptor={label=Some"scene-texture-staging";size=Int64.of_int total;usage=[Copy_src]}in
    match Ogpu.Backend.create_buffer value.device staging_descriptor with Error e->ignore(Ogpu.Backend.destroy_texture texture);Error e|Ok staging->
    let packed=Bytes.make total '\000'in Array.iteri(fun level_index level->for row=0 to level.height-1 do Bytes.blit level.bytes(row*level.width*4)packed(offsets.(level_index)+row*rows.(level_index))(level.width*4)done)source.levels;
    match Ogpu.Backend.write_buffer staging~offset:0L packed with Error e->ignore(Ogpu.Backend.destroy_buffer staging);ignore(Ogpu.Backend.destroy_texture texture);Error e|Ok()->
    let pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle value.device)in
    let src=Ogpu.Backend.transfer_buffer staging and dst=Ogpu.Backend.transfer_texture texture in
    let failure=ref None in Array.iteri(fun index level->if !failure=None then match Ogpu.Transfer_pass.buffer_to_texture pass~src~offset:(Int64.of_int offsets.(index))~bytes_per_row:(Int64.of_int rows.(index))~bytes_per_image:(Int64.of_int(rows.(index)*level.height))~dst~mip:index~origin:{x=0;y=0;z=0}~extent:{width=level.width;height=level.height;depth=1}with Ok()->()|Error e->failure:=Some e)source.levels;
    let finish result=ignore(Ogpu.Backend.destroy_buffer staging);match result with Error e->ignore(Ogpu.Backend.destroy_texture texture);Error e|Ok()->let item={texture_key=source.key;texture_hash=hash;texture}in let replaced,others=List.partition(fun old->old.texture_key=source.key)value.texture_cache in List.iter(fun old->ignore(Ogpu.Backend.destroy_texture old.texture))replaced;value.texture_cache<-item::others;value.uploaded<-Int64.add value.uploaded(Int64.of_int total);Ok item in
    match !failure with Some e->finish(Error e)|None->match Ogpu.Backend.transfer pass with Error e->finish(Error e)|Ok command->match Ogpu.Backend.submit value.queue command~resources:[`Buffer staging;`Texture texture]~pipelines:[]with Error e->finish(Error e)|Ok receipt->finish(Ogpu.Backend.complete_through value.queue receipt.epoch)
let pass value state load clear=let texture=Ogpu.Backend.render_texture value.target~format:Ogpu.Render_pass.Rgba8~usage:Render_target in let x,y,width,height=state.viewport and sx,sy,sw,sh=state.scissor in Ogpu.Render_pass.create(Ogpu.Backend.device_handle value.device){colors=[|Some{texture;resolve=None;load;store=Store;clear}|];depth=None;stencil=None;viewport={x;y;width;height};scissor={x=sx;y=sy;width=sw;height=sh}}
let render_textured ?(clear=(0.,0.,0.,0.)) value draws=if value.dead then error"Scene_execution.render"Ogpu.Error.Stale_handle"renderer is destroyed"else
  let rec prepare_all acc=function []->Ok(List.rev acc)|(family,blend,texture,(draw:draw))::rest->match prepare value draw.mesh with Error _ as e->e|Ok mesh->match texture with None->prepare_all((family,blend,draw.state,None,mesh)::acc)rest|Some source->match prepare_texture value source with Error _ as e->e|Ok texture->prepare_all((family,blend,draw.state,Some(source,texture),mesh)::acc)rest in
  match prepare_all[]draws with Error _ as e->e|Ok prepared->match Ogpu.Backend.acquire value.surface with Error _ as e->e|Ok(`Timeout|`Occluded)->Ok false|Ok`Device_lost->error"Scene_execution.render"Device_lost"device lost"|Ok(`Acquired frame)->
    let resources=`Texture value.target::List.concat_map(fun(_,_,_,texture,item)->`Buffer item.buffer::match texture with None->[]|Some(_,cached)->[`Texture cached.texture])prepared in
    let same_texture a b=match a,b with None,None->true|Some(_,x),Some(_,y)->x==y|_->false in
    let rec take family blend state texture acc=function (next_family,next_blend,next,next_texture,item)::rest when next_family=family&&next_blend=blend&&next=state&&same_texture next_texture texture->take family blend state texture((next_family,next_blend,next,next_texture,item)::acc)rest|rest->List.rev acc,rest in
    let rec batches first=function []->Ok()|(family,blend,state,texture,item)::rest->let same,rest=take family blend state texture[(family,blend,state,texture,item)]rest in match List.find_opt(fun value->value.family=family&&value.blend=blend)value.pipelines with None->error"Scene_execution.render"Ogpu.Error.Unsupported"pipeline family/blend variant is unavailable"|Some variant->match pass value state(if first then Ogpu.Render_pass.Clear else Load)clear with Error _ as e->e|Ok pass->let payload=List.map(fun(_,_,_,texture,item)->let textures,samplers=match texture with None->[],[]|Some(source,cached)->[{Ogpu.Render_pass.stage=Fragment;index=1;texture_id=Ogpu.Backend.texture_id cached.texture}],[{Ogpu.Render_pass.stage=Fragment;index=2;sampler=source.sampler}]in{Ogpu.Render_pass.pipeline_key=variant.key;buffers=[{stage=Ogpu.Command.Vertex;index=0;buffer_id=Ogpu.Backend.buffer_id item.buffer;offset=0L}];textures;samplers;primitive=Triangle_list;vertex_start=0;vertex_count=item.vertex_count;index=Some(Uint32,Ogpu.Backend.buffer_id item.buffer,item.index_offset,item.index_count)})same in match Ogpu.Backend.render pass payload with Error _ as e->e|Ok command->match Ogpu.Backend.submit value.queue command~resources~pipelines:[variant.pipeline]with Error _ as e->e|Ok receipt->match Ogpu.Backend.complete_through value.queue receipt.epoch with Error _ as e->e|Ok()->batches false rest in
    (match batches true prepared with Error e->ignore(Ogpu.Backend.discard frame);Error e|Ok()->Result.map(fun()->true)(Ogpu.Backend.present frame))
let render_family ?clear value draws=render_textured ?clear value(List.map(fun(family,blend,draw)->family,blend,None,draw)draws)
let render_blended ?clear value draws=render_family ?clear value(List.map(fun(blend,draw)->Scene2,blend,draw)draws)
let render ?clear value draws=render_blended ?clear value(List.map(fun draw->Ogpu.Pipeline.Replace,draw)draws)
let resize value configuration=match Ogpu.Backend.create_texture value.device(texture_descriptor configuration)with Error _ as e->e|Ok target->match Ogpu.Backend.configure value.surface configuration with Error e->ignore(Ogpu.Backend.destroy_texture target);Error e|Ok()->let old=value.target in value.target<-target;Ogpu.Backend.destroy_texture old
let upload_bytes value=value.uploaded
let cache_entries value=List.length value.cache
let read_pixels value ~bytes_per_row=Ogpu.Backend.read_texture value.target~bytes_per_row
let destroy value=if value.dead then Ok()else(value.dead<-true;List.iter(fun item->ignore(Ogpu.Backend.destroy_buffer item.buffer))value.cache;value.cache<-[];List.iter(fun item->ignore(Ogpu.Backend.destroy_texture item.texture))value.texture_cache;value.texture_cache<-[];ignore(Ogpu.Backend.destroy_texture value.target);List.iter(fun variant->ignore(Ogpu.Backend.destroy_pipeline variant.pipeline))value.pipelines;ignore(Ogpu.Backend.destroy_surface value.surface);ignore(Ogpu.Backend.destroy_queue value.queue);match value.before_device_destroy()with Error _ as e->e|Ok()->Ogpu.Backend.destroy_device value.device)
