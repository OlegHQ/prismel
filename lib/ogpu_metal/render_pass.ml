type stage=Vertex|Fragment
type primitive=Triangle_list|Triangle_strip
type index_type=Uint16|Uint32
type buffer_binding={stage:stage;index:int;buffer:Buffer.t;offset:int64}
type texture_binding={stage:stage;index:int;texture:Texture.t}
type sampler_binding={stage:stage;index:int;sampler:Sampler.t}
type draw={pipeline:Pipeline.t;buffers:buffer_binding list;textures:texture_binding list;samplers:sampler_binding list;primitive:primitive;vertex_start:int;vertex_count:int;index:(index_type*Buffer.t*int64*int)option}
type indirect_resources={vertex_buffers:Metal.Buffer.t list;fragment_buffers:Metal.Buffer.t list;textures:Metal.Texture.t list}
type retention={retain:unit->(unit,Ogpu.Error.t)result;release:unit->unit}
type t={pass:Ogpu.Render_pass.t;color:Texture.t;resolve:Texture.t option;depth:Texture.t option;stencil:Texture.t option;draws:draw list;owned_samplers:Sampler.t list;indirect:(Metal.Indirect_command_buffer.t*indirect_resources)option;retention:retention array;releases:(unit->unit)list}
let error op kind message=Error(Ogpu.Error.make op kind message)
let metal_compare=function
  |Ogpu.Render_pass.Never->Metal.Depth_stencil.Never|Less->Less|Equal->Equal
  |Less_equal->Less_equal|Greater->Greater|Not_equal->Not_equal
  |Greater_equal->Greater_equal|Always->Always
let metal_cull=function
  |Ogpu.Render_pass.Cull_none->Metal.Render_encoder.No_cull
  |Cull_front->Cull_front|Cull_back->Cull_back
let metal_operation=function
  |Ogpu.Render_pass.Keep->Metal.Depth_stencil.Keep|Zero->Zero|Replace->Replace
  |Increment_clamp->Increment_clamp|Decrement_clamp->Decrement_clamp|Invert->Invert
  |Increment_wrap->Increment_wrap|Decrement_wrap->Decrement_wrap
let metal_face(face:Ogpu.Render_pass.stencil_face)=Metal.Depth_stencil.face~compare:(metal_compare face.compare)~stencil_fail:(metal_operation face.stencil_fail)~depth_fail:(metal_operation face.depth_fail)~pass:(metal_operation face.pass)~read_mask:face.read_mask~write_mask:face.write_mask()
let format=function Texture.Rgba8_unorm->Some Ogpu.Render_pass.Rgba8|Bgra8_unorm->Some Bgra8|Depth32_float->Some Depth32|Stencil8->Some Stencil8|R8_unorm|Rgba16_float->None
let attachment device texture ~usage=let op="Ogpu_metal.Render_pass.attachment"in match Texture.descriptor device texture,Texture.format device texture with
  |Error e,_->Error e|_,Error e->Error e
  |Ok d,Ok f->match format f with None->error op Ogpu.Error.Unsupported"texture format is not a portable render attachment"|Some format->Ok({id=Texture.id texture;handle=Texture.Private.resource_handle texture;format;samples=d.sample_count;width=d.width;height=d.height;usage=[usage]}:Ogpu.Render_pass.texture)
let validate_slot op seen stage index=if index<0||index>30 then error op Ogpu.Error.Invalid_argument"binding index is outside [0,30]"else let key=stage,index in if Hashtbl.mem seen key then error op Ogpu.Error.Invalid_argument"binding stage/index is duplicated"else(Hashtbl.add seen key();Ok())
let retention ~color ~resolve ~depth ~stencil draws =
  let seen=Hashtbl.create 32 and reversed=ref[]in
  let add key retain release=if not(Hashtbl.mem seen key)then(Hashtbl.add seen key();reversed:={retain;release}::!reversed)in
  let texture t=add("t:"^Int64.to_string(Texture.id t))(fun()->Texture.Private.retain_submission t)(fun()->Texture.Private.release_submission t)
  and buffer b=add("b:"^Int64.to_string(Buffer.id b))(fun()->Buffer.Private.retain_submission b)(fun()->Buffer.Private.release_submission b)
  and pipeline p=add("p:"^Pipeline.key p)(fun()->Pipeline.Private.retain_submission p)(fun()->Pipeline.Private.release_submission p)
  and sampler s=add("s:"^Int64.to_string(Sampler.id s))(fun()->Sampler.Private.retain_submission s)(fun()->Sampler.Private.release_submission s)in
  texture color;Option.iter texture resolve;Option.iter texture depth;Option.iter texture stencil;
  List.iter(fun draw->pipeline draw.pipeline;List.iter(fun(b:buffer_binding)->buffer b.buffer)draw.buffers;List.iter(fun(b:texture_binding)->texture b.texture)draw.textures;List.iter(fun(b:sampler_binding)->sampler b.sampler)draw.samplers;Option.iter(fun(_,b,_,_)->buffer b)draw.index)draws;
  let retention=Array.of_list(List.rev!reversed)in
  retention,Array.to_list(Array.map(fun item->item.release)retention)
let create device pass ~attachments draw=let op="Ogpu_metal.Render_pass.create"in
  let descriptor=Ogpu.Render_pass.descriptor pass in
  let colors=Array.to_list descriptor.colors|>List.filter_map Fun.id in
  if List.length colors<>1 then error op Ogpu.Error.Unsupported"classic Metal execution requires exactly one color attachment"else
  let color=List.hd colors in
  if (color.texture.samples=1&&(color.store<>Store||Option.is_some color.resolve))||(color.texture.samples>1&&(color.store<>Resolve||Option.is_none color.resolve))then error op Ogpu.Error.Invalid_argument"color store/resolve state differs from its sample count"else
  let find id texture = if Texture.id texture=id then Some texture else None in
  let candidates=List.map(fun(b:buffer_binding)->b.buffer)draw.buffers in ignore candidates;
  match List.find_map (find color.texture.id) attachments with
  |None->error op Ogpu.Error.Invalid_argument"color attachment texture is absent from the typed texture graph"
  |Some target->
    let resolve=match color.resolve with None->Ok None|Some portable->match List.find_map(find portable.id)attachments with None->error op Ogpu.Error.Invalid_argument"resolve attachment texture is absent from the typed texture graph"|Some texture->Result.map(fun _->Some texture)(Texture.descriptor device texture)in
    (match Texture.descriptor device target,resolve,Pipeline.validate device draw.pipeline with
    |Error e,_,_->Error e|_,Error e,_->Error e|_,_,Error e->Error e|Ok td,Ok resolve,Ok()->
      if td.width<>color.texture.width||td.height<>color.texture.height||td.sample_count<>color.texture.samples then error op Ogpu.Error.Invalid_argument"native color attachment metadata differs from the portable pass"
      else match Pipeline.Private.native draw.pipeline with Pipeline.Private.Compute _->error op Ogpu.Error.Invalid_argument"compute pipeline cannot execute a render pass"|Render _->
      let pipeline_samples=match Pipeline.Private.native draw.pipeline with Render pipeline->Metal.Render_pipeline.raster_sample_count pipeline|Compute _->assert false in
      if pipeline_samples<>td.sample_count then error op Ogpu.Error.Invalid_argument"pipeline and color attachment sample counts differ"else
      if draw.vertex_start<0||draw.vertex_count<=0 then error op Ogpu.Error.Invalid_argument"draw vertex range is invalid"else
      if draw.primitive=Triangle_strip&&Option.is_none draw.index then error op Ogpu.Error.Unsupported"classic non-indexed execution currently exposes triangle lists"else
      if draw.primitive=Triangle_list&&Option.is_none draw.index&&draw.vertex_count mod 3<>0 then error op Ogpu.Error.Invalid_argument"triangle-list vertex count is not divisible by three"else if draw.primitive=Triangle_strip&&draw.vertex_count<3 then error op Ogpu.Error.Invalid_argument"triangle strip requires at least three vertices"else
      let buffer_slots=Hashtbl.create 16 and texture_slots=Hashtbl.create 16 and sampler_slots=Hashtbl.create 16 in
      let rec buffers=function []->Ok()|(b:buffer_binding)::xs->(match validate_slot op buffer_slots b.stage b.index,Buffer.descriptor device b.buffer with Error e,_->Error e|_,Error e->Error e|Ok(),Ok bd when b.offset<0L||b.offset>=bd.size->error op Ogpu.Error.Invalid_argument"buffer binding offset is outside the buffer"|Ok(),Ok _->buffers xs)in
      let rec texture_bindings=function []->Ok()|(b:texture_binding)::xs->(match validate_slot op texture_slots b.stage b.index,Texture.descriptor device b.texture with Error e,_->Error e|_,Error e->Error e|Ok(),Ok _->texture_bindings xs)in
      let rec sampler_bindings=function []->Ok()|(b:sampler_binding)::xs->(match validate_slot op sampler_slots b.stage b.index,Sampler.descriptor device b.sampler with Error e,_->Error e|_,Error e->Error e|Ok(),Ok _->sampler_bindings xs)in
      match buffers draw.buffers with Error _ as e->e|Ok()->match texture_bindings draw.textures with Error _ as e->e|Ok()->match sampler_bindings draw.samplers with Error _ as e->e|Ok()->
      let depth=match descriptor.depth with None->Ok None|Some d when d.store=Resolve->error op Ogpu.Error.Invalid_argument"depth attachments cannot resolve"|Some d->match List.find_map(find d.texture.id)attachments with None->error op Ogpu.Error.Invalid_argument"depth attachment texture is absent from the typed texture graph"|Some texture->Result.map(fun _->Some texture)(Texture.descriptor device texture)in
      let stencil=match descriptor.stencil with None->Ok None|Some s when s.store=Resolve->error op Ogpu.Error.Invalid_argument"stencil attachments cannot resolve"|Some s->match List.find_map(find s.texture.id)attachments with None->error op Ogpu.Error.Invalid_argument"stencil attachment texture is absent from the typed texture graph"|Some texture->Result.map(fun _->Some texture)(Texture.descriptor device texture)in
      match depth,stencil with Error e,_->Error e|_,Error e->Error e|Ok depth,Ok stencil->
      let finish()=let retention,releases=retention~color:target~resolve~depth~stencil[draw]in Ok{pass;color=target;resolve;depth;stencil;draws=[draw];owned_samplers=[];indirect=None;retention;releases}in
      match draw.index with None->finish()|Some(kind,buffer,offset,count)->match Buffer.descriptor device buffer with Error _ as e->e|Ok bd->let stride=match kind with Uint16->2L|Uint32->4L in if count<=0||offset<0L||Int64.rem offset stride<>0L||Int64.of_int count>Int64.div(Int64.sub bd.size offset)stride then error op Ogpu.Error.Invalid_argument"index range is invalid"else finish())
let create_empty device pass ~attachments =
  let op="Ogpu_metal.Render_pass.create_empty"in
  let descriptor=Ogpu.Render_pass.descriptor pass in
  let colors=Array.to_list descriptor.colors|>List.filter_map Fun.id in
  if List.length colors<>1 then
    error op Ogpu.Error.Unsupported
      "classic Metal execution requires exactly one color attachment"
  else
    let color=List.hd colors in
    if (color.texture.samples=1&&(color.store<>Store||Option.is_some color.resolve))||
       (color.texture.samples>1&&(color.store<>Resolve||Option.is_none color.resolve))
    then error op Ogpu.Error.Invalid_argument
      "color store/resolve state differs from its sample count"
    else
      let find id texture=if Texture.id texture=id then Some texture else None in
      match List.find_map(find color.texture.id)attachments with
      |None->error op Ogpu.Error.Invalid_argument
          "color attachment texture is absent from the typed texture graph"
      |Some target->
          let optional role (portable:Ogpu.Render_pass.texture option)=match portable with
            |None->Ok None
            |Some portable->match List.find_map(find portable.id)attachments with
              |None->error op Ogpu.Error.Invalid_argument
                  (role^" attachment texture is absent from the typed texture graph")
              |Some texture->Result.map(fun _->Some texture)
                  (Texture.descriptor device texture)in
          let resolve=optional"resolve"color.resolve
          and depth=optional"depth"(Option.map(fun(value:Ogpu.Render_pass.depth)->value.texture)
            descriptor.depth)
          and stencil=optional"stencil"(Option.map(fun(value:Ogpu.Render_pass.stencil)->value.texture)
            descriptor.stencil)in
          match Texture.descriptor device target,resolve,depth,stencil with
          |Error e,_,_,_->Error e|_,Error e,_,_->Error e
          |_,_,Error e,_->Error e|_,_,_,Error e->Error e
          |Ok target_descriptor,Ok resolve,Ok depth,Ok stencil->
              if target_descriptor.width<>color.texture.width||
                 target_descriptor.height<>color.texture.height||
                 target_descriptor.sample_count<>color.texture.samples
              then error op Ogpu.Error.Invalid_argument
                "native color attachment metadata differs from the portable pass"
              else
                let retention,releases=retention~color:target~resolve~depth~stencil[]in
                Ok{pass;color=target;resolve;depth;stencil;draws=[];
                  owned_samplers=[];indirect=None;retention;releases}
let validate_batch_draw device draw =
  let op="Ogpu_metal.Render_pass.create_batch"in
  match Pipeline.validate device draw.pipeline with Error _ as e->e|Ok()->
  if draw.vertex_start<0||draw.vertex_count<=0 then error op Ogpu.Error.Invalid_argument"draw vertex range is invalid"
  else if draw.primitive=Triangle_strip&&Option.is_none draw.index then error op Ogpu.Error.Unsupported"classic non-indexed execution currently exposes triangle lists"
  else if draw.primitive=Triangle_list&&Option.is_none draw.index&&draw.vertex_count mod 3<>0 then error op Ogpu.Error.Invalid_argument"triangle-list vertex count is not divisible by three"
  else if draw.primitive=Triangle_strip&&draw.vertex_count<3 then error op Ogpu.Error.Invalid_argument"triangle strip requires at least three vertices"
  else
    let slots=Array.make 3 0L in
    let slot kind stage index=
      if index<0||index>30 then error op Ogpu.Error.Invalid_argument"binding index is outside [0,30]"
      else let offset=match stage with Vertex->0|Fragment->31 in let bit=Int64.shift_left 1L(offset+index)in
        if Int64.logand slots.(kind)bit<>0L then error op Ogpu.Error.Invalid_argument"binding stage/index is duplicated"
        else(slots.(kind)<-Int64.logor slots.(kind)bit;Ok())in
    let rec buffers=function []->Ok()|(b:buffer_binding)::rest->
      (match slot 0 b.stage b.index,Buffer.descriptor device b.buffer with Error e,_->Error e|_,Error e->Error e|Ok(),Ok descriptor when b.offset<0L||b.offset>=descriptor.size->error op Ogpu.Error.Invalid_argument"buffer binding offset is outside the buffer"|Ok(),Ok _->buffers rest)
    and textures=function []->Ok()|(b:texture_binding)::rest->
      (match slot 1 b.stage b.index,Texture.descriptor device b.texture with Error e,_->Error e|_,Error e->Error e|Ok(),Ok _->textures rest)
    and samplers=function []->Ok()|(b:sampler_binding)::rest->
      (match slot 2 b.stage b.index,Sampler.descriptor device b.sampler with Error e,_->Error e|_,Error e->Error e|Ok(),Ok _->samplers rest)in
    match buffers draw.buffers with Error _ as e->e|Ok()->match textures draw.textures with Error _ as e->e|Ok()->match samplers draw.samplers with Error _ as e->e|Ok()->
    match draw.index with None->Ok()|Some(kind,buffer,offset,count)->match Buffer.descriptor device buffer with Error _ as e->e|Ok descriptor->let stride=match kind with Uint16->2L|Uint32->4L in if count<=0||offset<0L||Int64.rem offset stride<>0L||Int64.of_int count>Int64.div(Int64.sub descriptor.size offset)stride then error op Ogpu.Error.Invalid_argument"index range is invalid"else Ok()
let create_batch ?(owned_samplers=[]) device pass ~attachments draws =
  let op="Ogpu_metal.Render_pass.create_batch" in
  let count=List.length draws in
  if count=0 then error op Ogpu.Error.Invalid_argument "render batch is empty"
  else if count>65_536 then error op Ogpu.Error.Invalid_argument "render batch exceeds 65536 draws"
  else
    match draws with
    |[]->assert false
    |first_draw::rest->match create device pass~attachments first_draw with Error _ as e->e|Ok first->
      let rec validate rev=function
        |[]->let draws=List.rev rev in let retention,releases=retention~color:first.color~resolve:first.resolve~depth:first.depth~stencil:first.stencil draws in Ok{first with draws;owned_samplers;retention;releases}
        |draw::rest->match validate_batch_draw device draw with Error _ as e->e|Ok()->validate(draw::rev)rest in
      validate[first_draw]rest
let with_indirect value indirect ~vertex_buffers ~fragment_buffers ~textures={value with indirect=Some(indirect,{vertex_buffers;fragment_buffers;textures})}
module Private=struct
  let requires_command4 value=
    let descriptor=Ogpu.Render_pass.descriptor value.pass in
    Option.is_none value.indirect&&
    (Array.exists(fun color->Option.fold~none:false~some:(fun(color:Ogpu.Render_pass.color)->color.load<>Clear)color)descriptor.colors||Option.is_some descriptor.stencil||
    Option.fold~none:false~some:(fun(d:Ogpu.Render_pass.depth)->d.load<>Clear||d.store<>Store||d.clear<>1.)descriptor.depth)
  let encode_portable value command=Ogpu.Render_pass.encode value.pass command
  let retain value=
    let rec loop index=
      if index=Array.length value.retention then Ok value.releases
      else match value.retention.(index).retain()with
      |Ok()->loop(index+1)
      |Error _ as failure->for release=0 to index-1 do value.retention.(release).release()done;failure
    in loop 0
  let encode command value=let op="Ogpu_metal.Render_pass.encode"in let descriptor=Ogpu.Render_pass.descriptor value.pass in let color=List.hd(Array.to_list descriptor.colors|>List.filter_map Fun.id)in
    let native_pass=Metal.Render_pass_descriptor.create~width:color.texture.width~height:color.texture.height~sample_count:color.texture.samples()in
    match native_pass with Error e->Error(Adapter.error~operation:op e)|Ok native_pass->
    let configured=match Metal.Render_pass_descriptor.set_attachments native_pass~color:(Texture.Private.metal value.color)~clear:color.clear?depth:(Option.map Texture.Private.metal value.depth)?stencil:(Option.map Texture.Private.metal value.stencil)()with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Render_pass_descriptor.set_color_load_action native_pass(match color.load with Ogpu.Render_pass.Dont_care->Load_dont_care|Load->Load|Clear->Clear)with Error e->Error(Adapter.error~operation:op e)|Ok()->match value.resolve with None->Result.map_error(Adapter.error~operation:op)(Metal.Render_pass_descriptor.set_color_store_action native_pass~resolve:false)|Some resolve->(match Metal.Render_pass_descriptor.set_resolve_texture native_pass(Some(Texture.Private.metal resolve))with Error e->Error(Adapter.error~operation:op e)|Ok()->Result.map_error(Adapter.error~operation:op)(Metal.Render_pass_descriptor.set_color_store_action native_pass~resolve:true))in
    let encoder=match configured with Error e->Error e|Ok()->Result.map_error(Adapter.error~operation:op)(Metal.Render_encoder.create_from_pass command native_pass)in
    match encoder with Error _ as e->ignore(Metal.Render_pass_descriptor.destroy native_pass);e|Ok encoder->
    let raster=Ogpu.Render_pass.raster_state value.pass in
    let stencil_state=Ogpu.Render_pass.stencil_state value.pass in
    let depth_state=match value.depth,value.stencil with None,None->Ok None|_->Result.map Option.some(Metal.Depth_stencil.create~label:"ogpu-metal-render-pass"~depth_compare:(metal_compare raster.depth_compare)~depth_write:raster.depth_write?front_face:(Option.map(fun s->metal_face s.Ogpu.Render_pass.front)stencil_state)?back_face:(Option.map(fun s->metal_face s.Ogpu.Render_pass.back)stencil_state)(Metal.Command_buffer.device command)())in
    let store=match depth_state with Error e->Error(Adapter.error~operation:op e)|Ok depth_state->match Metal.Render_encoder.set_cull_mode encoder(metal_cull raster.cull)with Error e->Option.iter(fun state->ignore(Metal.Depth_stencil.destroy state))depth_state;Error(Adapter.error~operation:op e)|Ok()->let depth_bound=match depth_state with None->Ok()|Some state->Metal.Render_encoder.set_depth_stencil_state encoder(Some state)in match depth_bound with Error e->Option.iter(fun state->ignore(Metal.Depth_stencil.destroy state))depth_state;Error(Adapter.error~operation:op e)|Ok()->Ok depth_state in
    match store with Error _ as e->ignore(Metal.Render_pass_descriptor.destroy native_pass);e|Ok depth_state->
    let references=match stencil_state with None->Ok()|Some state->Result.map_error(Adapter.error~operation:op)(Metal.Render_encoder.set_stencil_reference_values encoder~front:state.front_reference~back:state.back_reference)in
    let bind_buffer (b:buffer_binding)=match b.stage with Vertex->Metal.Render_encoder.set_vertex_buffer encoder~index:b.index~offset:b.offset(Buffer.Private.metal b.buffer)|Fragment->Metal.Render_encoder.set_fragment_buffer encoder~index:b.index~offset:b.offset(Buffer.Private.metal b.buffer)in
    let bind_texture (b:texture_binding)=match b.stage with Vertex->Metal.Render_encoder.set_vertex_texture encoder~index:b.index(Texture.Private.metal b.texture)|Fragment->Metal.Render_encoder.set_fragment_texture encoder~index:b.index(Texture.Private.metal b.texture)in
    let bind_sampler (b:sampler_binding)=match b.stage with Vertex->Metal.Render_encoder.set_vertex_sampler encoder~index:b.index(Sampler.Private.metal b.sampler)|Fragment->Metal.Render_encoder.set_fragment_sampler encoder~index:b.index(Sampler.Private.metal b.sampler)in
    let rec all f=function []->Ok()|x::xs->match f x with Error e->Error(Adapter.error~operation:op e)|Ok()->all f xs in
    let encode_draw draw=let native=match Pipeline.Private.native draw.pipeline with Render p->p|Compute _->assert false in let primitive=match draw.primitive with Triangle_list->Metal.Render_encoder.Triangle|Triangle_strip->Triangle_strip in let issue()=match draw.index with None->Metal.Render_encoder.draw_triangles encoder~first:draw.vertex_start~count:draw.vertex_count()|Some(kind,buffer,offset,count)->Metal.Render_encoder.draw_indexed encoder~primitive~index_type:(match kind with Uint16->Metal.Render_encoder.Uint16|Uint32->Uint32)~index_buffer:(Buffer.Private.metal buffer)~index_offset:offset~index_count:(Int64.of_int count)()in match Metal.Render_encoder.set_pipeline encoder native with Error e->Error(Adapter.error~operation:op e)|Ok()->match all bind_buffer draw.buffers with Error _ as e->e|Ok()->match all bind_texture draw.textures with Error _ as e->e|Ok()->match all bind_sampler draw.samplers with Error _ as e->e|Ok()->Result.map_error(Adapter.error~operation:op)(issue())in
    let rec all_draws=function []->Ok()|draw::draws->match encode_draw draw with Error _ as e->e|Ok()->all_draws draws in
    let encode_all()=match value.indirect,value.draws with Some(indirect,resources),first::_->let native=match Pipeline.Private.native first.pipeline with Render p->p|Compute _->assert false in let use values usage stages=Metal.Render_encoder.use_resources encoder values~usage~stages in(match use(List.map(fun b->Metal.Render_encoder.Buffer_resource b)resources.vertex_buffers)[Metal.Render_encoder.Read][Metal.Render_encoder.Vertex]with Error e->Error(Adapter.error~operation:op e)|Ok()->match use(List.map(fun b->Metal.Render_encoder.Buffer_resource b)resources.fragment_buffers)[Metal.Render_encoder.Read][Metal.Render_encoder.Fragment]with Error e->Error(Adapter.error~operation:op e)|Ok()->match use(List.map(fun t->Metal.Render_encoder.Texture_resource t)resources.textures)[Metal.Render_encoder.Sample][Metal.Render_encoder.Fragment]with Error e->Error(Adapter.error~operation:op e)|Ok()->match Metal.Render_encoder.set_pipeline encoder native with Error e->Error(Adapter.error~operation:op e)|Ok()->Result.map_error(Adapter.error~operation:op)(Metal.Render_encoder.execute_indirect_commands encoder indirect~location:0~length:(List.length value.draws)))|_->all_draws value.draws in
    match references with Error _ as e->ignore(Metal.Render_pass_descriptor.destroy native_pass);e|Ok()->match Metal.Render_encoder.set_viewport encoder{x=float descriptor.viewport.x;y=float descriptor.viewport.y;width=float descriptor.viewport.width;height=float descriptor.viewport.height;znear=0.;zfar=1.}with Error e->ignore(Metal.Render_pass_descriptor.destroy native_pass);Error(Adapter.error~operation:op e)|Ok()->match Metal.Render_encoder.set_scissor encoder{x=descriptor.scissor.x;y=descriptor.scissor.y;width=descriptor.scissor.width;height=descriptor.scissor.height}with Error e->ignore(Metal.Render_pass_descriptor.destroy native_pass);Error(Adapter.error~operation:op e)|Ok()->match encode_all()with Error _ as e->ignore(Metal.Render_pass_descriptor.destroy native_pass);e|Ok()->match Metal.Render_encoder.end_encoding encoder with Error e->ignore(Metal.Render_pass_descriptor.destroy native_pass);Error(Adapter.error~operation:op e)|Ok()->Ok((fun()->ignore(Metal.Render_pass_descriptor.destroy native_pass))::(match depth_state with None->[]|Some state->[fun()->ignore(Metal.Depth_stencil.destroy state)])@List.map(fun sampler->fun()->ignore(Sampler.destroy sampler))value.owned_samplers)

  let encode_command4 command value =
    let op="Ogpu_metal.Render_pass.encode_command4" in
    let descriptor=Ogpu.Render_pass.descriptor value.pass in
    let color=List.hd(Array.to_list descriptor.colors|>List.filter_map Fun.id)in
    let c=Metal.Command4.Render_encoder.color~red:(let r,_,_,_=color.clear in r)~green:(let _,g,_,_=color.clear in g)~blue:(let _,_,b,_=color.clear in b)~alpha:(let _,_,_,a=color.clear in a)in
    let load=match color.load with Ogpu.Render_pass.Clear->Metal.Command4.Render_encoder.Clear c|Load->Load|Dont_care->Load_dont_care
    and store=match color.store with Ogpu.Render_pass.Store->Metal.Command4.Render_encoder.Store|Discard->Store_dont_care|Resolve->Multisample_resolve in
    let resolve_texture=Option.map Texture.Private.metal value.resolve in
    let colors=[Metal.Command4.Render_encoder.color_attachment ~load_action:load
      ~store_action:store ?resolve_texture (Texture.Private.metal value.color)]in
    let depth_attachment=Option.map(fun texture->let d=Option.get descriptor.depth in Metal.Command4.Render_encoder.depth_attachment~load_action:(match d.load with Clear->Depth_clear|Load->Depth_load|Dont_care->Depth_load_dont_care)~store_action:(match d.store with Store->Store|Discard->Store_dont_care|Resolve->Store_deferred)~clear_depth:d.clear(Texture.Private.metal texture))value.depth in
    let stencil_attachment=Option.map(fun texture->let s=Option.get descriptor.stencil in Metal.Command4.Render_encoder.stencil_attachment~load_action:(match s.load with Clear->Stencil_clear|Load->Stencil_load|Dont_care->Stencil_load_dont_care)~store_action:(match s.store with Store->Store|Discard->Store_dont_care|Resolve->Store_deferred)~clear_stencil:(Int32.of_int s.clear)(Texture.Private.metal texture))value.stencil in
    match Metal.Command4.Render_encoder.create ?depth_attachment ?stencil_attachment command~color_attachments:colors with
    |Error e->Error(Adapter.error~operation:op e)
    |Ok encoder->
      let cleanup=ref[]in
      let sampler_cleanup =
        List.map
          (fun sampler () -> ignore (Sampler.destroy sampler))
          value.owned_samplers
      in
      let fail e=
        List.iter(fun f->f())!cleanup;
        List.iter(fun f->f())sampler_cleanup;
        Error(Adapter.error~operation:op e)
      in
      let raster=Ogpu.Render_pass.raster_state value.pass and stencil=Ogpu.Render_pass.stencil_state value.pass in
      (match Metal.Depth_stencil.create~label:"ogpu-metal-command4-pass"~depth_compare:(metal_compare raster.depth_compare)~depth_write:raster.depth_write?front_face:(Option.map(fun s->metal_face s.Ogpu.Render_pass.front)stencil)?back_face:(Option.map(fun s->metal_face s.Ogpu.Render_pass.back)stencil)(Metal.Command4.Command_buffer.device command)()with
      |Error e->fail e
      |Ok depth_state->cleanup:=(fun()->ignore(Metal.Depth_stencil.destroy depth_state))::!cleanup;
        let ( let* ) result f=match result with Ok value->f value|Error e->fail e in
        let* ()=Metal.Command4.Render_encoder.set_depth_stencil_state encoder(Some depth_state)in
        let* ()=match stencil with None->Ok()|Some s->Metal.Command4.Render_encoder.set_stencil_references encoder~front:s.front_reference~back:s.back_reference in
        let* ()=Metal.Command4.Render_encoder.set_cull_mode encoder(match raster.cull with Ogpu.Render_pass.Cull_none->Cull_none|Cull_front->Cull_front|Cull_back->Cull_back)in
        let* ()=Metal.Command4.Render_encoder.set_viewport encoder(Metal.Command4.Render_encoder.viewport~x:(float descriptor.viewport.x)~y:(float descriptor.viewport.y)~width:(float descriptor.viewport.width)~height:(float descriptor.viewport.height)~z_near:0.~z_far:1.)in
        let* ()=Metal.Command4.Render_encoder.set_scissor_rect encoder(Metal.Command4.Render_encoder.scissor_rect~x:descriptor.scissor.x~y:descriptor.scissor.y~width:descriptor.scissor.width~height:descriptor.scissor.height)in
        let bind_stage encoder stage draw=
          let buffers=List.filter(fun(b:buffer_binding)->b.stage=stage)draw.buffers
          and textures=List.filter(fun(b:texture_binding)->b.stage=stage)draw.textures
          and samplers=List.filter(fun(b:sampler_binding)->b.stage=stage)draw.samplers in
          if buffers=[]&&textures=[]&&samplers=[]then Metal.Command4.Render_encoder.set_argument_table encoder~stages:[(match stage with Vertex->Metal.Command4.Render_encoder.Vertex|Fragment->Fragment)]None else
          let capacity items index=List.fold_left(fun n item->max n(index item+1))0 items in
          match Metal.Command4.Argument_table.create~max_buffers:(capacity buffers(fun(b:buffer_binding)->b.index))~max_textures:(capacity textures(fun(b:texture_binding)->b.index))~max_samplers:(capacity samplers(fun(b:sampler_binding)->b.index))(Metal.Command4.Command_buffer.device command)()with
          |Error e->Error e
          |Ok table->cleanup:=(fun()->ignore(Metal.Command4.Argument_table.destroy table))::!cleanup;
            let rec set_buffers=function []->Ok()|(b:buffer_binding)::rest->(match Metal.Command4.Argument_table.set_buffer table~index:b.index~offset:b.offset(Buffer.Private.metal b.buffer)with Error _ as e->e|Ok()->set_buffers rest)
            and set_textures=function []->Ok()|(b:texture_binding)::rest->(match Metal.Command4.Argument_table.set_texture table~index:b.index(Texture.Private.metal b.texture)with Error _ as e->e|Ok()->set_textures rest)
            and set_samplers=function []->Ok()|(b:sampler_binding)::rest->(match Metal.Command4.Argument_table.set_sampler table~index:b.index(Sampler.Private.metal b.sampler)with Error _ as e->e|Ok()->set_samplers rest)in
            match set_buffers buffers with Error _ as e->e|Ok()->match set_textures textures with Error _ as e->e|Ok()->match set_samplers samplers with Error _ as e->e|Ok()->Metal.Command4.Render_encoder.set_argument_table encoder~stages:[(match stage with Vertex->Metal.Command4.Render_encoder.Vertex|Fragment->Fragment)](Some table)
        in
        let rec draws=function
          |[]->(match Metal.Command4.Render_encoder.end_encoding encoder with Error e->fail e|Ok()->Ok(List.rev!cleanup @ sampler_cleanup))
          |draw::rest->let native=match Pipeline.Private.native draw.pipeline with Render p->p|Compute _->assert false in
            let* ()=Metal.Command4.Render_encoder.set_pipeline encoder native in
            let* ()=bind_stage encoder Vertex draw in
            let* ()=bind_stage encoder Fragment draw in
            let primitive=match draw.primitive with Triangle_list->Metal.Command4.Render_encoder.Triangle|Triangle_strip->Triangle_strip in
            let issued=match draw.index with None->Metal.Command4.Render_encoder.draw_primitives encoder primitive~vertex_start:draw.vertex_start~vertex_count:draw.vertex_count|Some(kind,buffer,offset,count)->Metal.Command4.Render_encoder.draw_indexed_primitives encoder primitive(match kind with Uint16->Metal.Command4.Render_encoder.Uint16|Uint32->Uint32)~index_buffer:(Buffer.Private.metal buffer)~index_offset:offset~index_count:count in
            let* ()=issued in draws rest
        in draws value.draws)
end
