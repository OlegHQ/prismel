type mesh={key:string;vertices:bytes;vertex_count:int;indices:bytes;index_count:int}
type state={viewport:int*int*int*int;scissor:int*int*int*int}
type draw={mesh:mesh;state:state}
type cached={key:string;buffer:Ogpu.Backend.buffer;index_offset:int64;vertex_count:int;index_count:int}
type t={device:Ogpu.Backend.device;queue:Ogpu.Backend.queue;surface:Ogpu.Backend.surface;mutable target:Ogpu.Backend.texture;pipeline:Ogpu.Backend.pipeline;pipeline_key:string;mutable cache:cached list;mutable uploaded:int64;mutable dead:bool}
let error op kind text=Error(Ogpu.Error.make op kind text)
let get_cleanup result cleanup=match result with Ok value->Ok value|Error _ as e->cleanup();e
let shader stage name=Ogpu.Shader.create{backend="mock";label=Some name;bytes=Bytes.of_string name;entry_points=[{Ogpu.Shader.name;stage}];bindings=[]}
let pipeline device=let capabilities=Ogpu.Backend.capabilities device in let open Result in
  bind(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities[])(fun layout->
  bind(shader Ogpu.Shader.Vertex"scene_vertex")(fun vertex->bind(shader Fragment"scene_fragment")(fun fragment->
  bind(Ogpu.Pipeline.create_render capabilities{backend="mock";label=Some"scene-execution";layout;vertex;vertex_entry="scene_vertex";fragment=Some fragment;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format=No_depth;sample_count=1})(fun portable->
  map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable)))))
let texture_descriptor configuration:Ogpu.Types.texture_descriptor={label=Some"scene-execution-target";width=configuration.Ogpu.Surface.physical_width;height=configuration.physical_height;depth=1;mip_levels=1;sample_count=1;usage=[Render_attachment;Texture_copy_src]}
let create_common driver configuration supplied=match Ogpu.Backend.create_device driver with Error _ as e->e|Ok device->
  let cleanup()=ignore(Ogpu.Backend.destroy_device device)in
  get_cleanup(match Ogpu.Backend.create_queue device with Error _ as e->e|Ok queue->
    get_cleanup(match Ogpu.Backend.create_surface device configuration with Error _ as e->e|Ok surface->
      get_cleanup(match Ogpu.Backend.create_texture device(texture_descriptor configuration),(match supplied with None->pipeline device|Some make->Result.bind(make device)(fun portable->Result.map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable)))with
      |Ok target,Ok(pipeline,pipeline_key)->Ok{device;queue;surface;target;pipeline;pipeline_key;cache=[];uploaded=0L;dead=false}
      |Error e,_|_,Error e->Error e)(fun()->ignore(Ogpu.Backend.destroy_surface surface)))(fun()->ignore(Ogpu.Backend.destroy_queue queue)))cleanup
let create driver configuration=create_common driver configuration None
let create_with_pipeline driver configuration pipeline=create_common driver configuration(Some pipeline)
let prepare value (mesh:mesh)=match List.find_opt(fun x->x.key=mesh.key)value.cache with Some item->Ok item|None->
  let total=Bytes.length mesh.vertices+Bytes.length mesh.indices in
  if mesh.key=""||mesh.vertex_count<=0||mesh.index_count<=0||total=0 then error"Scene_execution.prepare"Ogpu.Error.Invalid_argument"mesh payload is empty"else
  let descriptor:Ogpu.Types.buffer_descriptor={label=Some("scene-mesh-"^mesh.key);size=Int64.of_int total;usage=[Vertex;Index;Copy_dst]}in
  match Ogpu.Backend.create_buffer value.device descriptor with Error _ as e->e|Ok buffer->
    let offset=Int64.of_int(Bytes.length mesh.vertices)in match Ogpu.Backend.write_buffer buffer~offset:0L mesh.vertices with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->match Ogpu.Backend.write_buffer buffer~offset mesh.indices with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->let item={key=mesh.key;buffer;index_offset=offset;vertex_count=mesh.vertex_count;index_count=mesh.index_count}in value.cache<-item::value.cache;value.uploaded<-Int64.add value.uploaded(Int64.of_int total);Ok item
let pass value state load=let texture=Ogpu.Backend.render_texture value.target~format:Ogpu.Render_pass.Rgba8~usage:Render_target in let x,y,width,height=state.viewport and sx,sy,sw,sh=state.scissor in Ogpu.Render_pass.create(Ogpu.Backend.device_handle value.device){colors=[|Some{texture;resolve=None;load;store=Store;clear=(0.,0.,0.,0.)}|];depth=None;stencil=None;viewport={x;y;width;height};scissor={x=sx;y=sy;width=sw;height=sh}}
let render value draws=if value.dead then error"Scene_execution.render"Ogpu.Error.Stale_handle"renderer is destroyed"else
  let rec prepare_all acc=function []->Ok(List.rev acc)|(draw:draw)::rest->match prepare value draw.mesh with Error _ as e->e|Ok mesh->prepare_all((draw.state,mesh)::acc)rest in
  match prepare_all[]draws with Error _ as e->e|Ok prepared->match Ogpu.Backend.acquire value.surface with Error _ as e->e|Ok(`Timeout|`Occluded)->Ok false|Ok`Device_lost->error"Scene_execution.render"Device_lost"device lost"|Ok(`Acquired frame)->
    let resources=`Texture value.target::List.map(fun(_,x)->`Buffer x.buffer)prepared in
    let rec take state acc=function (next,item)::rest when next=state->take state((next,item)::acc)rest|rest->List.rev acc,rest in
    let rec batches first=function []->Ok()|(state,item)::rest->let same,rest=take state[(state,item)]rest in match pass value state(if first then Ogpu.Render_pass.Clear else Load)with Error _ as e->e|Ok pass->let payload=List.map(fun(_,item)->{Ogpu.Render_pass.pipeline_key=value.pipeline_key;buffers=[{stage=Ogpu.Command.Vertex;index=0;buffer_id=Ogpu.Backend.buffer_id item.buffer;offset=0L}];textures=[];primitive=Triangle_list;vertex_start=0;vertex_count=item.vertex_count;index=Some(Uint32,Ogpu.Backend.buffer_id item.buffer,item.index_offset,item.index_count)})same in match Ogpu.Backend.render pass payload with Error _ as e->e|Ok command->match Ogpu.Backend.submit value.queue command~resources~pipelines:[value.pipeline]with Error _ as e->e|Ok receipt->match Ogpu.Backend.complete_through value.queue receipt.epoch with Error _ as e->e|Ok()->batches false rest in
    (match batches true prepared with Error e->ignore(Ogpu.Backend.discard frame);Error e|Ok()->Result.map(fun()->true)(Ogpu.Backend.present frame))
let resize value configuration=match Ogpu.Backend.create_texture value.device(texture_descriptor configuration)with Error _ as e->e|Ok target->match Ogpu.Backend.configure value.surface configuration with Error e->ignore(Ogpu.Backend.destroy_texture target);Error e|Ok()->let old=value.target in value.target<-target;Ogpu.Backend.destroy_texture old
let upload_bytes value=value.uploaded
let read_pixels value ~bytes_per_row=Ogpu.Backend.read_texture value.target~bytes_per_row
let destroy value=if value.dead then Ok()else(value.dead<-true;List.iter(fun item->ignore(Ogpu.Backend.destroy_buffer item.buffer))value.cache;ignore(Ogpu.Backend.destroy_texture value.target);ignore(Ogpu.Backend.destroy_pipeline value.pipeline);ignore(Ogpu.Backend.destroy_surface value.surface);ignore(Ogpu.Backend.destroy_queue value.queue);Ogpu.Backend.destroy_device value.device)
