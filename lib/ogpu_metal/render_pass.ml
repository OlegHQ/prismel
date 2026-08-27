type stage=Vertex|Fragment
type primitive=Triangle_list|Triangle_strip
type index_type=Uint16|Uint32
type buffer_binding={stage:stage;index:int;buffer:Buffer.t;offset:int64}
type texture_binding={stage:stage;index:int;texture:Texture.t}
type sampler_binding={stage:stage;index:int;sampler:Sampler.t}
type draw={pipeline:Pipeline.t;buffers:buffer_binding list;textures:texture_binding list;samplers:sampler_binding list;primitive:primitive;vertex_start:int;vertex_count:int;index:(index_type*Buffer.t*int64*int)option}
type t={pass:Ogpu.Render_pass.t;color:Texture.t;depth:Texture.t option;draws:draw list;owned_samplers:Sampler.t list}
let error op kind message=Error(Ogpu.Error.make op kind message)
let format=function Texture.Rgba8_unorm->Some Ogpu.Render_pass.Rgba8|Bgra8_unorm->Some Bgra8|Depth32_float->Some Depth32|R8_unorm|Rgba16_float->None
let attachment device texture ~usage=let op="Ogpu_metal.Render_pass.attachment"in match Texture.descriptor device texture,Texture.format device texture with
  |Error e,_->Error e|_,Error e->Error e
  |Ok d,Ok f->match format f with None->error op Ogpu.Error.Unsupported"texture format is not a portable render attachment"|Some format->Ok({id=Texture.id texture;handle=Texture.Private.resource_handle texture;format;samples=d.sample_count;width=d.width;height=d.height;usage=[usage]}:Ogpu.Render_pass.texture)
let validate_slot op seen stage index=if index<0||index>30 then error op Ogpu.Error.Invalid_argument"binding index is outside [0,30]"else let key=stage,index in if Hashtbl.mem seen key then error op Ogpu.Error.Invalid_argument"binding stage/index is duplicated"else(Hashtbl.add seen key();Ok())
let create device pass ~attachments draw=let op="Ogpu_metal.Render_pass.create"in
  let descriptor=Ogpu.Render_pass.descriptor pass in
  let colors=Array.to_list descriptor.colors|>List.filter_map Fun.id in
  if List.length colors<>1 then error op Ogpu.Error.Unsupported"classic Metal execution requires exactly one color attachment"else
  let color=List.hd colors in
  if color.load<>Clear||color.store<>Store||Option.is_some color.resolve||color.texture.samples<>1 then error op Ogpu.Error.Unsupported"classic Metal execution supports single-sample clear/store color passes"else
  let find id texture = if Texture.id texture=id then Some texture else None in
  let candidates=List.map(fun(b:buffer_binding)->b.buffer)draw.buffers in ignore candidates;
  match List.find_map (find color.texture.id) attachments with
  |None->error op Ogpu.Error.Invalid_argument"color attachment texture is absent from the typed texture graph"
  |Some target->
    (match Texture.descriptor device target,Pipeline.validate device draw.pipeline with
    |Error e,_->Error e|_,Error e->Error e|Ok td,Ok()->
      if td.width<>color.texture.width||td.height<>color.texture.height||td.sample_count<>color.texture.samples then error op Ogpu.Error.Invalid_argument"native color attachment metadata differs from the portable pass"
      else match Pipeline.Private.native draw.pipeline with Pipeline.Private.Compute _->error op Ogpu.Error.Invalid_argument"compute pipeline cannot execute a render pass"|Render _->
      if draw.vertex_start<0||draw.vertex_count<=0 then error op Ogpu.Error.Invalid_argument"draw vertex range is invalid"else
      if draw.primitive=Triangle_strip&&Option.is_none draw.index then error op Ogpu.Error.Unsupported"classic non-indexed execution currently exposes triangle lists"else
      if draw.primitive=Triangle_list&&Option.is_none draw.index&&draw.vertex_count mod 3<>0 then error op Ogpu.Error.Invalid_argument"triangle-list vertex count is not divisible by three"else if draw.primitive=Triangle_strip&&draw.vertex_count<3 then error op Ogpu.Error.Invalid_argument"triangle strip requires at least three vertices"else
      let seen=Hashtbl.create 16 in
      let rec buffers=function []->Ok()|(b:buffer_binding)::xs->(match validate_slot op seen b.stage b.index,Buffer.descriptor device b.buffer with Error e,_->Error e|_,Error e->Error e|Ok(),Ok bd when b.offset<0L||b.offset>=bd.size->error op Ogpu.Error.Invalid_argument"buffer binding offset is outside the buffer"|Ok(),Ok _->buffers xs)in
      let rec texture_bindings=function []->Ok()|(b:texture_binding)::xs->(match validate_slot op seen b.stage b.index,Texture.descriptor device b.texture with Error e,_->Error e|_,Error e->Error e|Ok(),Ok _->texture_bindings xs)in
      let rec sampler_bindings=function []->Ok()|(b:sampler_binding)::xs->(match validate_slot op seen b.stage b.index,Sampler.descriptor device b.sampler with Error e,_->Error e|_,Error e->Error e|Ok(),Ok _->sampler_bindings xs)in
      match buffers draw.buffers with Error _ as e->e|Ok()->match texture_bindings draw.textures with Error _ as e->e|Ok()->match sampler_bindings draw.samplers with Error _ as e->e|Ok()->
      let depth=match descriptor.depth with None->Ok None|Some d when d.load<>Clear||d.store<>Store||d.clear<>1.->error op Ogpu.Error.Unsupported"classic depth execution requires clear-to-one/store semantics"|Some d->match List.find_map(find d.texture.id)attachments with None->error op Ogpu.Error.Invalid_argument"depth attachment texture is absent from the typed texture graph"|Some texture->Result.map(fun _->Some texture)(Texture.descriptor device texture)in
      match depth with Error _ as e->e|Ok _ when Option.is_some descriptor.stencil->error op Ogpu.Error.Unsupported"portable stencil execution is not available in this backend slice"|Ok depth->
      match draw.index with None->Ok{pass;color=target;depth;draws=[draw];owned_samplers=[]}|Some(kind,buffer,offset,count)->match Buffer.descriptor device buffer with Error _ as e->e|Ok bd->let stride=match kind with Uint16->2L|Uint32->4L in if count<=0||offset<0L||Int64.rem offset stride<>0L||Int64.of_int count>Int64.div(Int64.sub bd.size offset)stride then error op Ogpu.Error.Invalid_argument"index range is invalid"else Ok{pass;color=target;depth;draws=[draw];owned_samplers=[]})
let create_batch ?(owned_samplers=[]) device pass ~attachments draws =
  let op="Ogpu_metal.Render_pass.create_batch" in
  let count=List.length draws in
  if count=0 then error op Ogpu.Error.Invalid_argument "render batch is empty"
  else if count>4096 then error op Ogpu.Error.Invalid_argument "render batch exceeds 4096 draws"
  else
    let rec validate first rev=function
      |[]->(match first with None->assert false|Some value->Ok{value with draws=List.rev rev;owned_samplers})
      |draw::rest->(match create device pass ~attachments draw with
        |Error _ as e->e
        |Ok value->
          (match first with
          |None->validate(Some value)(draw::rev)rest
          |Some base when Texture.id base.color<>Texture.id value.color->error op Ogpu.Error.Invalid_argument "render batch attachment identity changed"
          |Some _->validate first(draw::rev)rest))
    in validate None [] draws
let retain_one retained retain release=match retain()with Error _ as e->e|Ok()->retained:=release::!retained;Ok()
module Private=struct
  let encode_portable value command=Ogpu.Render_pass.encode value.pass command
  let retain value=let retained=ref[]and seen=Hashtbl.create 32 in let keep retain release=retain_one retained retain release in let once key f=if Hashtbl.mem seen key then(fun()->Ok())else(Hashtbl.add seen key();f)in
    let texture t=once("t:"^Int64.to_string(Texture.id t))(fun()->keep(fun()->Texture.Private.retain_submission t)(fun()->Texture.Private.release_submission t))and buffer b=once("b:"^Int64.to_string(Buffer.id b))(fun()->keep(fun()->Buffer.Private.retain_submission b)(fun()->Buffer.Private.release_submission b))and pipeline p=once("p:"^Pipeline.key p)(fun()->keep(fun()->Pipeline.Private.retain_submission p)(fun()->Pipeline.Private.release_submission p))in
    let sampler s=once("s:"^Int64.to_string(Sampler.id s))(fun()->keep(fun()->Sampler.Private.retain_submission s)(fun()->Sampler.Private.release_submission s))in
    let draw_resources draw=pipeline draw.pipeline::List.map(fun(b:buffer_binding)->buffer b.buffer)draw.buffers@List.map(fun(b:texture_binding)->texture b.texture)draw.textures@List.map(fun(b:sampler_binding)->sampler b.sampler)draw.samplers@(match draw.index with None->[]|Some(_,b,_,_)->[buffer b])in
    let resources=texture value.color::(match value.depth with None->[]|Some t->[texture t])@List.concat_map draw_resources value.draws in
    let rec loop=function []->Ok(List.rev!retained)|f::fs->match f()with Ok()->loop fs|Error _ as e->List.iter(fun release->release())!retained;e in loop resources
  let encode command value=let op="Ogpu_metal.Render_pass.encode"in let descriptor=Ogpu.Render_pass.descriptor value.pass in let color=List.hd(Array.to_list descriptor.colors|>List.filter_map Fun.id)in
    match Metal.Render_encoder.create command ~target:(Texture.Private.metal value.color) ~clear:color.clear ?depth:(Option.map Texture.Private.metal value.depth) () with Error e->Error(Adapter.error~operation:op e)|Ok encoder->
    let bind_buffer (b:buffer_binding)=match b.stage with Vertex->Metal.Render_encoder.set_vertex_buffer encoder~index:b.index~offset:b.offset(Buffer.Private.metal b.buffer)|Fragment->Metal.Render_encoder.set_fragment_buffer encoder~index:b.index~offset:b.offset(Buffer.Private.metal b.buffer)in
    let bind_texture (b:texture_binding)=match b.stage with Vertex->Metal.Render_encoder.set_vertex_texture encoder~index:b.index(Texture.Private.metal b.texture)|Fragment->Metal.Render_encoder.set_fragment_texture encoder~index:b.index(Texture.Private.metal b.texture)in
    let bind_sampler (b:sampler_binding)=match b.stage with Vertex->Metal.Render_encoder.set_vertex_sampler encoder~index:b.index(Sampler.Private.metal b.sampler)|Fragment->Metal.Render_encoder.set_fragment_sampler encoder~index:b.index(Sampler.Private.metal b.sampler)in
    let rec all f=function []->Ok()|x::xs->match f x with Error e->Error(Adapter.error~operation:op e)|Ok()->all f xs in
    let encode_draw draw=let native=match Pipeline.Private.native draw.pipeline with Render p->p|Compute _->assert false in let primitive=match draw.primitive with Triangle_list->Metal.Render_encoder.Triangle|Triangle_strip->Triangle_strip in let issue()=match draw.index with None->Metal.Render_encoder.draw_triangles encoder~first:draw.vertex_start~count:draw.vertex_count()|Some(kind,buffer,offset,count)->Metal.Render_encoder.draw_indexed encoder~primitive~index_type:(match kind with Uint16->Metal.Render_encoder.Uint16|Uint32->Uint32)~index_buffer:(Buffer.Private.metal buffer)~index_offset:offset~index_count:(Int64.of_int count)()in match Metal.Render_encoder.set_pipeline encoder native with Error e->Error(Adapter.error~operation:op e)|Ok()->match all bind_buffer draw.buffers with Error _ as e->e|Ok()->match all bind_texture draw.textures with Error _ as e->e|Ok()->match all bind_sampler draw.samplers with Error _ as e->e|Ok()->Result.map_error(Adapter.error~operation:op)(issue())in
    let rec all_draws=function []->Ok()|draw::draws->match encode_draw draw with Error _ as e->e|Ok()->all_draws draws in
    (match Metal.Render_encoder.set_viewport encoder{x=float descriptor.viewport.x;y=float descriptor.viewport.y;width=float descriptor.viewport.width;height=float descriptor.viewport.height;znear=0.;zfar=1.}with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Render_encoder.set_scissor encoder{x=descriptor.scissor.x;y=descriptor.scissor.y;width=descriptor.scissor.width;height=descriptor.scissor.height}with Error e->Error(Adapter.error~operation:op e)|Ok()->match all_draws value.draws with Error _ as e->e|Ok()->match Metal.Render_encoder.end_encoding encoder with Error e->Error(Adapter.error~operation:op e)|Ok()->Ok(List.map(fun sampler->fun()->ignore(Sampler.destroy sampler))value.owned_samplers))
end
