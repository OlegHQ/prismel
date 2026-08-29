type mesh={key:string;vertices:bytes;vertex_count:int;indices:bytes;index_count:int}
type state={viewport:int*int*int*int;scissor:int*int*int*int;cull:Ogpu.Render_pass.cull;depth_compare:Ogpu.Render_pass.comparison;depth_write:bool;depth_load:Ogpu.Render_pass.load;depth_clear:float;transform_uniforms:bytes option;stencil_state:Ogpu.Render_pass.stencil_state option;stencil_load:Ogpu.Render_pass.load;stencil_clear:int}
type draw={mesh:mesh;state:state}
type pipeline_family=Scene2|Scene2_textured|Scene3|Scene3_textured|Scene3_shadow|Scene3_stencil|Scene3_textured_stencil|Scene3_shadow_stencil
type texture_level={width:int;height:int;bytes:bytes}
type sampled_texture={key:string;levels:texture_level array;sampler:Ogpu.Types.sampler_descriptor}
type shadow_resource={texture:sampled_texture;parameters:bytes}
type shadow_kernel=Tap1|Tap4|Tap9|Tap25
type shadow_bias={constant:float;slope:float}
type shadow_snapshot={width:int;height:int;depths:float array;matrix:float array;
  bias:shadow_bias;kernel:shadow_kernel;strength:float}
module Scene2_command = struct
  type rect={x:float;y:float;width:float;height:float}
  type transform={xx:float;xy:float;yx:float;yy:float;tx:float;ty:float}
  type geometry={vertices:float array;indices:int array;color:int32}
  type debug_text={x:float;y:float;text:string;color:int32}
  type blend=Replace|Alpha|Add|Multiply|Screen|Subtract
  type t=Clear of int32|Set_blend of blend|Push_clip of rect|Pop_clip
    |Push_transform of transform|Pop_transform|Geometry of geometry
    |Debug_text of debug_text
end
type auxiliary_resource={key:string;buffer:bytes;texture:sampled_texture}
type scene3_entry={family:pipeline_family;blend:Ogpu.Pipeline.blend;
  texture:sampled_texture option;auxiliary:auxiliary_resource option;
  samples:int;draw:draw}
type prepared_scene3={clear:float*float*float*float;clear_depth:float;
  clear_stencil:int;entries:scene3_entry array}
type cached={mutable key:string;mutable payload_hash:string;uniform_bytes:bytes option;buffer:Ogpu.Backend.buffer;mutable index_offset:int64;mutable uniform_offset:int64 option;mutable vertex_count:int;mutable index_count:int;bytes:int}
type cached_auxiliary={auxiliary_key:string;auxiliary_hash:string;auxiliary_buffer:Ogpu.Backend.buffer}
type cached_texture={texture_key:string;texture_hash:string;texture_shape:string;
  texture:Ogpu.Backend.texture;texture_bytes:int}
type texture_upload_scratch={scratch_buffer:Ogpu.Backend.buffer;
  scratch_bytes:bytes;scratch_size:int}
type prepared_run={prepared_identity:string;prepared_version:int64;prepared_draws:(pipeline_family*Ogpu.Pipeline.blend*sampled_texture option*auxiliary_resource option*int*draw)list;prepared_bytes:int}
type prepared_submission={submission_identity:string;submission_version:int64;
  submission_clear:float*float*float*float;
  submission_draw_count:int;
  submission_commands:(Ogpu.Backend.command*
    [ `Buffer of Ogpu.Backend.buffer | `Texture of Ogpu.Backend.texture ] list*
    Ogpu.Backend.pipeline list)list}
type automatic_signature={signature_family:pipeline_family;
  signature_blend:Ogpu.Pipeline.blend;signature_samples:int;
  signature_state:state;signature_texture:(int64*Ogpu.Types.sampler_descriptor)option;
  signature_auxiliary:(int64*int64*Ogpu.Types.sampler_descriptor)option;
  signature_buffer:int64;signature_index_offset:int64;
  signature_uniform_buffer:int64 option;signature_vertex_count:int;
  signature_index_count:int}
type automatic_submission={automatic_clear:float*float*float*float;
  automatic_payloads:(automatic_signature*Ogpu.Render_pass.draw*Ogpu.Backend.pipeline)list;
  automatic_commands:(Ogpu.Backend.command*
    [ `Buffer of Ogpu.Backend.buffer | `Texture of Ogpu.Backend.texture ] list*
    Ogpu.Backend.pipeline list)list}
type automatic_candidate={candidate_clear:float*float*float*float;
  candidate_length:int;candidate_fingerprint:int}
type prepared_slot={mutable slot_family:pipeline_family;
  mutable slot_blend:Ogpu.Pipeline.blend;mutable slot_samples:int;
  mutable slot_state:state option;
  mutable slot_texture:(sampled_texture*cached_texture)option;
  mutable slot_auxiliary:(auxiliary_resource*cached_auxiliary*cached_texture)option;
  mutable slot_mesh:cached option;mutable slot_uniform:cached option}
type prepared_scratch={mutable scratch_slots:prepared_slot array;
  mutable scratch_length:int}
type pipeline_variant={family:pipeline_family;blend:Ogpu.Pipeline.blend;samples:int;pipeline:Ogpu.Backend.pipeline;key:string}
type t={device:Ogpu.Backend.device;queue:Ogpu.Backend.queue;
  surface:Ogpu.Backend.surface option;mutable target:Ogpu.Backend.texture;
  mutable configuration:Ogpu.Surface.configuration;
  mutable attachments:Scene_attachment_pool.t;pipelines:pipeline_variant list;
  canonical_scene2_argument:bool;mutable cache:cached list;
  mutable uniform_cache:cached list;mutable prepared_cache:prepared_run list;
  mutable prepared_submission:prepared_submission option;
  mutable automatic_submission:automatic_submission option;
  mutable automatic_candidate:automatic_candidate option;
  prepared_scratch:prepared_scratch;
  mutable auxiliary_cache:cached_auxiliary list;
  mutable texture_cache:cached_texture list;
  mutable texture_upload_scratch:texture_upload_scratch option;
  mutable uploaded:int64;
  mutable dead:bool;before_device_destroy:unit->(unit,Ogpu.Error.t)result}
let error op kind text=Error(Ogpu.Error.make op kind text)
let prepare_scene3 ~clear ~clear_depth ~clear_stencil entries =
  let finite=Float.is_finite in
  let r,g,b,a=clear in
  let valid_extent(_,_,width,height)=width>0&&height>0 in
  let valid_family (entry:scene3_entry)=match entry.family,entry.texture,entry.auxiliary with
    |Scene3,None,None|Scene3_stencil,None,None->true
    |Scene3_textured,Some _,None|Scene3_textured_stencil,Some _,None->true
    |Scene3_shadow,_,Some _|Scene3_shadow_stencil,_,Some _->true
    |_->false in
  let valid_entry (entry:scene3_entry)=
    entry.samples>0&&List.mem entry.samples[1;4;9;16]&&valid_family entry&&
    entry.draw.mesh.key<>""&&entry.draw.mesh.vertex_count>=0&&
    entry.draw.mesh.index_count>=0&&
    Bytes.length entry.draw.mesh.indices=entry.draw.mesh.index_count*4&&
    valid_extent entry.draw.state.viewport&&valid_extent entry.draw.state.scissor&&
    finite entry.draw.state.depth_clear in
  if not(List.for_all finite[r;g;b;a;clear_depth])||clear_depth<0.||clear_depth>1.
     ||clear_stencil<0||clear_stencil>255 then
    error"Scene_execution.prepare_scene3"Ogpu.Error.Invalid_argument
      "clear state is malformed"
  else if not(Array.for_all valid_entry entries)then
    error"Scene_execution.prepare_scene3"Ogpu.Error.Invalid_argument
      "draw family, resources, samples, mesh, or extent is malformed"
  else Ok{clear;clear_depth;clear_stencil;entries=Array.copy entries}
let set_u32_le bytes offset value =
  let open Int32 in
  Bytes.set bytes offset (Char.chr (to_int (logand value 0xffl)));
  Bytes.set bytes (offset + 1) (Char.chr (to_int (logand (shift_right_logical value 8) 0xffl)));
  Bytes.set bytes (offset + 2) (Char.chr (to_int (logand (shift_right_logical value 16) 0xffl)));
  Bytes.set bytes (offset + 3) (Char.chr (to_int (shift_right_logical value 24)))
let set_f32_le bytes offset value = set_u32_le bytes offset (Int32.bits_of_float value)
let shadow_resource ~key (source:shadow_snapshot) =
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
let shader stage ~entry artifact=Ogpu.Shader.create{backend="mock";label=Some artifact;bytes=Bytes.of_string artifact;entry_points=[{Ogpu.Shader.name=entry;stage}];bindings=[]}
let pipeline device family blend samples=let capabilities=Ogpu.Backend.capabilities device in let open Result in
  bind(Ogpu.Binding.create_pipeline_layout~device:(Ogpu.Backend.device_handle device)~capabilities[])(fun layout->
  let suffix=match family with Scene2->"scene2"|Scene2_textured->"scene2-textured"|Scene3->"scene3"|Scene3_textured->"scene3-textured"|Scene3_shadow->"scene3-shadow"|Scene3_stencil->"scene3-stencil"|Scene3_textured_stencil->"scene3-textured-stencil"|Scene3_shadow_stencil->"scene3-shadow-stencil"in
  bind(shader Ogpu.Shader.Vertex~entry:"scene_vertex"("scene_vertex-"^suffix))(fun vertex->bind(shader Fragment~entry:"scene_fragment"("scene_fragment-"^suffix))(fun fragment->
  let depth_format=match family with Scene2|Scene2_textured->Ogpu.Pipeline.No_depth|Scene3|Scene3_textured|Scene3_shadow->Depth32_float|Scene3_stencil|Scene3_textured_stencil|Scene3_shadow_stencil->Depth32_float_stencil8 in
  bind(Ogpu.Pipeline.create_render~blend capabilities{backend="mock";label=Some"scene-execution";layout;vertex;vertex_entry="scene_vertex";fragment=Some fragment;fragment_entry=Some"scene_fragment";color_format=Rgba8_unorm;depth_format;sample_count=samples})(fun portable->
  map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable)))))
let texture_descriptor configuration:Ogpu.Types.texture_descriptor={label=Some"scene-execution-target";width=configuration.Ogpu.Surface.physical_width;height=configuration.physical_height;depth=1;mip_levels=1;sample_count=1;usage=[Texture_binding;Render_attachment;Texture_copy_src]}
let blends=[Ogpu.Pipeline.Replace;Alpha;Add;Multiply;Screen;Subtract]
let families=[Scene2;Scene2_textured;Scene3;Scene3_textured;Scene3_shadow;Scene3_stencil;Scene3_textured_stencil;Scene3_shadow_stencil]
let pipeline_variants_per_sample=List.length families*List.length blends
let sample_counts device=List.filter(fun samples->samples<=(Ogpu.Backend.capabilities device).Ogpu.Capabilities.limits.max_sample_count)[1;4;9;16]
let allocate_target device configuration=Ogpu.Backend.create_texture device(texture_descriptor configuration)
let create_common ?(canonical_scene2_argument=false) ?(offscreen=false) driver configuration before_device_destroy families_to_make variants_to_make samples_to_make supplied=match Ogpu.Backend.create_device driver with Error _ as e->e|Ok device->
  let cleanup()=ignore(Ogpu.Backend.destroy_device device)in
  match Ogpu.Backend.create_queue device with Error e->cleanup();Error e|Ok queue->
  let surface=if offscreen then Ok None else
    Result.map Option.some(Ogpu.Backend.create_surface device configuration)in
  match surface with Error e->ignore(Ogpu.Backend.destroy_queue queue);cleanup();Error e|Ok surface->
    let make family blend samples=match supplied with None->pipeline device family blend samples|Some make->Result.bind(make device family blend samples)(fun portable->Result.map(fun value->value,Ogpu.Pipeline.cache_key portable)(Ogpu.Backend.adopt_pipeline device portable))in
    let samples=samples_to_make device in
    let requested=List.concat_map(fun family->List.concat_map(fun blend->List.map(fun samples->family,blend,samples)samples)variants_to_make)families_to_make in
    let rec variants made=function []->Ok(List.rev made)|(family,blend,samples)::rest->match make family blend samples with Error e->List.iter(fun x->ignore(Ogpu.Backend.destroy_pipeline x.pipeline))made;Error e|Ok(pipeline,key)->variants({family;blend;samples;pipeline;key}::made)rest in
    let destroy_surface()=Option.iter(fun surface->ignore(Ogpu.Backend.destroy_surface surface))surface in
    match variants[]requested with Error e->destroy_surface();ignore(Ogpu.Backend.destroy_queue queue);cleanup();Error e|Ok pipelines->
    (match allocate_target device configuration with
      |Ok target->let attachments=Scene_attachment_pool.create~device~configuration~sample_counts:samples in Ok{device;queue;surface;target;configuration;attachments;pipelines;canonical_scene2_argument;cache=[];uniform_cache=[];prepared_cache=[];prepared_submission=None;automatic_submission=None;automatic_candidate=None;prepared_scratch={scratch_slots=[||];scratch_length=0};auxiliary_cache=[];texture_cache=[];texture_upload_scratch=None;uploaded=0L;dead=false;before_device_destroy}
      |Error e->List.iter(fun x->ignore(Ogpu.Backend.destroy_pipeline x.pipeline))pipelines;destroy_surface();ignore(Ogpu.Backend.destroy_queue queue);cleanup();Error e)
let one_sample _=[1]
let create driver configuration=create_common driver configuration(fun()->Ok())[Scene2]blends one_sample None
let create_variants ?(canonical_scene2_argument=false) driver configuration=create_common~canonical_scene2_argument driver configuration(fun()->Ok())families blends sample_counts None
let create_with_pipeline_variants driver configuration ?(before_device_destroy=fun()->Ok()) pipeline=create_common driver configuration before_device_destroy families blends one_sample(Some(fun device family blend _->pipeline device family blend))
let create_with_sampled_pipeline_variants driver configuration ?(before_device_destroy=fun()->Ok()) ?(canonical_scene2_argument=false) pipeline=create_common~canonical_scene2_argument driver configuration before_device_destroy families blends sample_counts(Some pipeline)
let create_offscreen_with_sampled_pipeline_variants driver configuration
    ?(before_device_destroy=fun()->Ok()) ?(canonical_scene2_argument=false) pipeline=
  create_common~canonical_scene2_argument~offscreen:true driver configuration
    before_device_destroy families blends sample_counts(Some pipeline)
let create_with_pipeline driver configuration ?(before_device_destroy=fun()->Ok()) make=
  create_common driver configuration before_device_destroy[Scene2][Ogpu.Pipeline.Replace]one_sample
    (Some(fun device _family _blend _samples->make device))
let create_offscreen_with_pipeline driver configuration
    ?(before_device_destroy=fun()->Ok()) make=
  create_common~offscreen:true driver configuration before_device_destroy
    [Scene2][Ogpu.Pipeline.Replace]one_sample
    (Some(fun device _family _blend _samples->make device))
let cache_byte_capacity=256*1024*1024
let mesh_cache_entry_capacity=256
let trim_cache cache =
  let rec loop entries bytes keep evict = function
    | [] -> List.rev keep, List.rev evict
    | item :: rest when entries < mesh_cache_entry_capacity && bytes <= cache_byte_capacity - item.bytes ->
        loop (entries + 1) (bytes + item.bytes) (item :: keep) evict rest
    | item :: rest -> loop entries bytes keep (item :: evict) rest
  in
  loop 0 0 [] [] cache
let prepare value ~defer ~trusted_key ~reserved ~uniforms ~nonindexed ~canonical_plain (mesh:mesh)=
  let uniform_bytes=Option.value uniforms~default:Bytes.empty in
  let valid_uniforms=Option.fold~none:true~some:(fun bytes->
    if Bytes.length bytes=48 then
      let valid=ref true in for index=0 to 5 do
        if not(Float.is_finite(Int64.float_of_bits(Bytes.get_int64_le bytes(index*8))))then valid:=false
      done;!valid
    else (Bytes.length bytes=24||Bytes.length bytes=208||Bytes.length bytes=5456)&&let valid=ref true in for index=0 to Bytes.length bytes/4-1 do if not(Float.is_finite(Int32.float_of_bits(Bytes.get_int32_le bytes(index*4))))then valid:=false done;let lights=if Bytes.length bytes=5456 then Int32.float_of_bits(Bytes.get_int32_le bytes(73*4))else 0. in !valid&&lights>=0.&&lights<=64.&&Float.is_integer lights)uniforms in
  let key=mesh.key^(if canonical_plain then ":canonical-scene2" else if nonindexed then ":nonindexed" else "")^(if Bytes.length uniform_bytes=0 then""else":"^Digest.to_hex(Digest.bytes uniform_bytes))in
  let trusted=if trusted_key then List.find_opt(fun(x:cached)->x.key=key)value.cache else None in
  match trusted with Some item->Ok item|None->
  let payload_hash=String.concat":"[
    Digest.to_hex(Digest.bytes mesh.vertices);
    Digest.to_hex(Digest.bytes mesh.indices);
    Digest.to_hex(Digest.bytes uniform_bytes)]in
  match List.find_opt(fun(x:cached)->x.key=key&&x.payload_hash=payload_hash)value.cache with Some item->Ok item|None->
  let vertex_stride=if mesh.vertex_count=0 then 0 else Bytes.length mesh.vertices/mesh.vertex_count in
  let index_at index=Int32.to_int(Bytes.get_int32_le mesh.indices(index*4))in
  let valid_indices=ref(Bytes.length mesh.indices=mesh.index_count*4)in
  if nonindexed&&vertex_stride>0&& !valid_indices then for index=0 to mesh.index_count-1 do let source=index_at index in if source<0||source>=mesh.vertex_count then valid_indices:=false done;
  let vertices,indices,vertex_count,index_count=
    if not nonindexed then mesh.vertices,mesh.indices,mesh.vertex_count,mesh.index_count
    else if vertex_stride<=0||Bytes.length mesh.vertices<>mesh.vertex_count*vertex_stride||not !valid_indices then Bytes.empty,Bytes.empty,0,0
    else if canonical_plain then
      let expanded=Bytes.create(mesh.index_count*68)in
      for index=0 to mesh.index_count-1 do
        let source=index_at index and target=index*68 in
        if vertex_stride>=24 then begin
          Bytes.set_int64_le expanded target
            (Bytes.get_int64_le mesh.vertices(source*vertex_stride));
          Bytes.set_int64_le expanded(target+8)
            (Bytes.get_int64_le mesh.vertices(source*vertex_stride+8))
        end else begin
          Bytes.set_int64_le expanded target
            (Int64.bits_of_float(Int32.float_of_bits
              (Bytes.get_int32_le mesh.vertices(source*vertex_stride))));
          Bytes.set_int64_le expanded(target+8)
            (Int64.bits_of_float(Int32.float_of_bits
              (Bytes.get_int32_le mesh.vertices(source*vertex_stride+4))))
        end;
        Bytes.set_int32_le expanded(target+48)
          (if vertex_stride>=24 then
             Bytes.get_int32_le mesh.vertices(source*vertex_stride+16)
           else Bytes.get_int32_le mesh.vertices(source*vertex_stride+8));
        Bytes.set_int64_le expanded(target+52)(Int64.bits_of_float 0.5);
        Bytes.set_int64_le expanded(target+60)(Int64.bits_of_float 0.5)
      done;
      expanded,Bytes.empty,mesh.index_count,0
    else let expanded=Bytes.create(mesh.index_count*vertex_stride)in for index=0 to mesh.index_count-1 do let source=index_at index in Bytes.blit mesh.vertices(source*vertex_stride)expanded(index*vertex_stride)vertex_stride done;expanded,Bytes.empty,mesh.index_count,0 in
  let total=Bytes.length vertices+Bytes.length indices+Bytes.length uniform_bytes in
  if mesh.key=""||vertex_count<=0||(not nonindexed&&index_count<=0)||total=0||not valid_uniforms then error"Scene_execution.prepare"Ogpu.Error.Invalid_argument"mesh payload or transform uniforms are malformed"else
  let at_capacity=List.length value.cache>=mesh_cache_entry_capacity in
  match List.find_opt(fun(x:cached)->x.bytes=total&&not(reserved x)&&(x.key=key||at_capacity))value.cache with
  |Some item->
    let packed=Bytes.concat Bytes.empty[vertices;indices;uniform_bytes]in
    (match Ogpu.Backend.write_buffer item.buffer~offset:0L packed with Error _ as e->e|Ok()->item.key<-key;item.payload_hash<-payload_hash;item.index_offset<-Int64.of_int(Bytes.length vertices);item.uniform_offset<-(if uniforms=None then None else Some(Int64.of_int(Bytes.length vertices+Bytes.length indices)));item.vertex_count<-vertex_count;item.index_count<-index_count;value.cache<-item::List.filter(fun old->old!=item)value.cache;value.uploaded<-Int64.add value.uploaded(Int64.of_int total);Ok item)
  |None->
  let descriptor:Ogpu.Types.buffer_descriptor={label=Some("scene-mesh-"^mesh.key);size=Int64.of_int total;usage=[Vertex;Index;Storage;Copy_dst]}in
  match Ogpu.Backend.create_buffer value.device descriptor with Error _ as e->e|Ok buffer->
    let offset=Int64.of_int(Bytes.length vertices)and uniform_offset=Int64.of_int(Bytes.length vertices+Bytes.length indices)in let packed=Bytes.concat Bytes.empty[indices;uniform_bytes]in match Ogpu.Backend.write_buffer buffer~offset:0L vertices with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->match Ogpu.Backend.write_buffer buffer~offset packed with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->let item={key;payload_hash;uniform_bytes=None;buffer;index_offset=offset;uniform_offset=(if uniforms=None then None else Some uniform_offset);vertex_count;index_count;bytes=total}in
    let replaced,others=List.partition(fun(x:cached)->
      x.key=key&&not(reserved x))value.cache in
    List.iter(fun x->defer(fun()->ignore(Ogpu.Backend.destroy_buffer x.buffer)))replaced;
    let keep,evict=trim_cache(item::others)in List.iter(fun x->defer(fun()->ignore(Ogpu.Backend.destroy_buffer x.buffer)))evict;value.cache<-keep;value.uploaded<-Int64.add value.uploaded(Int64.of_int total);Ok item
(* A render batch is already bounded to 65,536 draws.  Uniform storage shares
   byte-identical affine values and reserves distinct mutable slots only for
   differing values in the same submission, so this is a hard finite upper
   bound without rejecting an otherwise valid batch. *)
let uniform_cache_capacity=65_536
let scene2_identity_affine=let bytes=Bytes.make 24 '\000'in
  Bytes.set_int32_le bytes 0(Int32.bits_of_float 1.);
  Bytes.set_int32_le bytes 16(Int32.bits_of_float 1.);bytes
let scene2_native_affine bytes=
  if Bytes.length bytes=24 then bytes else
  let native=Bytes.make 24 '\000'in
  for index=0 to 5 do
    Bytes.set_int32_le native(index*4)
      (Int32.bits_of_float(Int64.float_of_bits(Bytes.get_int64_le bytes(index*8))))
  done;native
let prepare_uniform value ~defer:_ ~reserved ?preferred bytes=
  let available item=
    item.bytes=Bytes.length bytes&&not(reserved item)in
  let same item=Option.fold~none:false~some:(Bytes.equal bytes)item.uniform_bytes in
  let update item=
    match item.uniform_bytes with
    |None->assert false
    |Some retained when Bytes.equal bytes retained->Ok item
    |Some retained->Result.map(fun()->Bytes.blit bytes 0 retained 0(Bytes.length bytes);
        value.uniform_cache<-item::List.filter(fun old->old!=item)value.uniform_cache;
        value.uploaded<-Int64.add value.uploaded(Int64.of_int(Bytes.length bytes));item)
        (Ogpu.Backend.write_buffer item.buffer~offset:0L bytes)in
  match preferred with
  |Some item when item.bytes=Bytes.length bytes&&same item->Ok item
  |Some item when available item->update item
  |_->match List.find_opt(fun(item:cached)->same item)value.uniform_cache with
  |Some item->Ok item
  |None->
      let reusable=List.find_opt(fun item->item.bytes=Bytes.length bytes&&
          not(reserved item))
          (List.rev value.uniform_cache)in
      (match reusable with
      |Some item->update item
      |None when List.length value.uniform_cache>=uniform_cache_capacity->
          error"Scene_execution.prepare_uniform"Ogpu.Error.Invalid_state
            "one submission exceeds the bounded transform-uniform capacity"
      |None->
          let descriptor:Ogpu.Types.buffer_descriptor={label=Some"scene-transform-uniform";
            size=Int64.of_int(Bytes.length bytes);usage=[Storage;Copy_dst]}in
          match Ogpu.Backend.create_buffer value.device descriptor with Error _ as e->e
          |Ok buffer->match Ogpu.Backend.write_buffer buffer~offset:0L bytes with
            |Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e
            |Ok()->let item={key="uniform";payload_hash="";uniform_bytes=Some(Bytes.copy bytes);buffer;index_offset=0L;
                uniform_offset=None;vertex_count=0;index_count=0;bytes=Bytes.length bytes}in
              value.uniform_cache<-item::value.uniform_cache;
              value.uploaded<-Int64.add value.uploaded(Int64.of_int(Bytes.length bytes));
              Ok item)
let align256 value=(value+255)land(lnot 255)
let texture_cache_entry_capacity=256
let texture_cache_byte_capacity=256*1024*1024
let trim_texture_cache cache =
  let rec loop entries bytes keep evict=function
    |[]->List.rev keep,List.rev evict
    |item::rest when entries<texture_cache_entry_capacity&&
      item.texture_bytes<=texture_cache_byte_capacity-bytes->
        loop(entries+1)(bytes+item.texture_bytes)(item::keep)evict rest
    |item::rest->loop entries bytes keep(item::evict)rest in
  loop 0 0 [] [] cache
let valid_texture(source:sampled_texture)=
  source.key<>""&&Array.length source.levels>0&&
  (match Ogpu.Types.validate_sampler source.sampler with Error _->false|Ok()->true)&&
  (Array.mapi(fun index (level:texture_level)->level.width=max 1(source.levels.(0).width lsr index)&&level.height=max 1(source.levels.(0).height lsr index)&&Bytes.length level.bytes=level.width*level.height*4)source.levels|>Array.for_all Fun.id)
let scene2_white_texture:sampled_texture={
  key="scene2:canonical-white";
  levels=[|{width=1;height=1;bytes=Bytes.of_string "\255\255\255\255"}|];
  sampler={label=Some"scene2-canonical-white";min_filter=Nearest;mag_filter=Nearest;
    mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;
    lod_min=0.;lod_max=0.;max_anisotropy=1}}
let texture_upload_scratch value total =
  match value.texture_upload_scratch with
  |Some scratch when scratch.scratch_size=total->Ok scratch
  |previous->
      let descriptor:Ogpu.Types.buffer_descriptor={label=Some"scene-texture-staging";
        size=Int64.of_int total;usage=[Copy_src]}in
      match Ogpu.Backend.create_buffer value.device descriptor with
      |Error _ as error->error
      |Ok scratch_buffer->
          let scratch={scratch_buffer;scratch_bytes=Bytes.make total '\000';
            scratch_size=total}in
          value.texture_upload_scratch<-Some scratch;
          Option.iter(fun old->ignore(Ogpu.Backend.destroy_buffer old.scratch_buffer))
            previous;
          Ok scratch
let prepare_texture value ~defer(source:sampled_texture)=
  let hash=Digest.to_hex(Digest.string(Array.to_list source.levels|>List.map(fun (level:texture_level)->Printf.sprintf"%dx%d:%s"level.width level.height(Digest.to_hex(Digest.string(Bytes.unsafe_to_string level.bytes))))|>String.concat"|"))in
  match List.find_opt(fun item->item.texture_key=source.key&&item.texture_hash=hash)value.texture_cache with
  |Some item->Ok item
  |None->
    if not(valid_texture source)then error"Scene_execution.prepare_texture"Ogpu.Error.Invalid_argument"texture or sampler is malformed"else
    let shape=Array.to_list source.levels|>List.map(fun (level:texture_level)->Printf.sprintf"%dx%d"level.width level.height)|>String.concat"/"in
    (* Canvas and managed-image identities are unique and lower to one
       authoritative generation per staged frame, so their same-shape storage
       can be updated safely between completed submissions.
       General sampled keys may occur with multiple payloads in one submission
       (for example shadow fixtures) and must retain distinct textures. *)
    let reusable=if String.starts_with~prefix:"canvas:"source.key||
      String.starts_with~prefix:"image:"source.key then
      List.find_opt(fun item->item.texture_key=source.key&&item.texture_shape=shape)value.texture_cache
      else None in
    let descriptor:Ogpu.Types.texture_descriptor={label=Some("scene-texture-"^source.key);width=source.levels.(0).width;height=source.levels.(0).height;depth=1;mip_levels=Array.length source.levels;sample_count=1;usage=[Texture_binding;Texture_copy_dst]}in
    let rows=Array.map(fun (level:texture_level)->align256(level.width*4))source.levels in
    let offsets=Array.make(Array.length source.levels)0 in
    for index=1 to Array.length offsets-1 do offsets.(index)<-offsets.(index-1)+rows.(index-1)*source.levels.(index-1).height done;
    let total=offsets.(Array.length offsets-1)+rows.(Array.length rows-1)*source.levels.(Array.length rows-1).height in
    let cacheable=total<=texture_cache_byte_capacity in
    let texture=match reusable with Some item when cacheable->Ok(item.texture,false)
      |_->Result.map(fun texture->texture,true)
        (Ogpu.Backend.create_texture value.device descriptor)in
    match texture with Error _ as error->error|Ok(texture,created)->
    match texture_upload_scratch value total with
    |Error error->if created then ignore(Ogpu.Backend.destroy_texture texture);Error error
    |Ok scratch->let staging=scratch.scratch_buffer
      and packed=scratch.scratch_bytes in
    Array.iteri(fun level_index (level:texture_level)->for row=0 to level.height-1 do Bytes.blit level.bytes(row*level.width*4)packed(offsets.(level_index)+row*rows.(level_index))(level.width*4)done)source.levels;
    match Ogpu.Backend.write_buffer staging~offset:0L packed with Error e->if created then ignore(Ogpu.Backend.destroy_texture texture);Error e|Ok()->
    let pass=Ogpu.Transfer_pass.create(Ogpu.Backend.device_handle value.device)in
    let src=Ogpu.Backend.transfer_buffer staging and dst=Ogpu.Backend.transfer_texture texture in
    let failure=ref None in Array.iteri(fun index (level:texture_level)->if !failure=None then match Ogpu.Transfer_pass.buffer_to_texture pass~src~offset:(Int64.of_int offsets.(index))~bytes_per_row:(Int64.of_int rows.(index))~bytes_per_image:(Int64.of_int(rows.(index)*level.height))~dst~mip:index~origin:{x=0;y=0;z=0}~extent:{width=level.width;height=level.height;depth=1}with Ok()->()|Error e->failure:=Some e)source.levels;
    let finish result=match result with Error e->if created then ignore(Ogpu.Backend.destroy_texture texture);Error e|Ok()->let item={texture_key=source.key;texture_hash=hash;texture_shape=shape;texture;texture_bytes=total}in value.uploaded<-Int64.add value.uploaded(Int64.of_int total);if not cacheable then begin defer(fun()->ignore(Ogpu.Backend.destroy_texture texture));Ok item end else let replaced,others=List.partition(fun old->old.texture_key=source.key)value.texture_cache in List.iter(fun old->if old.texture!=texture then defer(fun()->ignore(Ogpu.Backend.destroy_texture old.texture)))replaced;let keep,evict=trim_texture_cache(item::others)in value.texture_cache<-keep;List.iter(fun old->defer(fun()->ignore(Ogpu.Backend.destroy_texture old.texture)))evict;Ok item in
    match !failure with Some e->finish(Error e)|None->match Ogpu.Backend.transfer pass with Error e->finish(Error e)|Ok command->match Ogpu.Backend.submit value.queue command~resources:[`Buffer staging;`Texture texture]~pipelines:[]with Error e->finish(Error e)|Ok receipt->finish(Ogpu.Backend.complete_through value.queue receipt.epoch)
let prepare_auxiliary value ~defer(source:auxiliary_resource)=
  let hash=Digest.to_hex(Digest.bytes source.buffer)in
  match List.find_opt(fun item->item.auxiliary_key=source.key&&item.auxiliary_hash=hash)value.auxiliary_cache with
  |Some item->Ok item
  |None->
    let descriptor:Ogpu.Types.buffer_descriptor={label=Some("scene-auxiliary-"^source.key);size=Int64.of_int(Bytes.length source.buffer);usage=[Storage;Copy_dst]}in
    match Ogpu.Backend.create_buffer value.device descriptor with Error _ as e->e|Ok buffer->
    match Ogpu.Backend.write_buffer buffer~offset:0L source.buffer with Error e->ignore(Ogpu.Backend.destroy_buffer buffer);Error e|Ok()->
    let item={auxiliary_key=source.key;auxiliary_hash=hash;auxiliary_buffer=buffer}in
    let replaced,others=List.partition(fun old->old.auxiliary_key=source.key)value.auxiliary_cache in
    List.iter(fun old->defer(fun()->ignore(Ogpu.Backend.destroy_buffer old.auxiliary_buffer)))replaced;
    let cache=item::others in let keep,evict=List.mapi(fun i x->i,x)cache|>List.partition(fun(i,_)->i<64)in
    List.iter(fun(_,old)->defer(fun()->ignore(Ogpu.Backend.destroy_buffer old.auxiliary_buffer)))evict;
    value.auxiliary_cache<-List.map snd keep;value.uploaded<-Int64.add value.uploaded(Int64.of_int(Bytes.length source.buffer));Ok item
let u32_le bytes offset =
  Int32.logor (Int32.of_int (Char.code (Bytes.get bytes offset)))
    (Int32.logor
       (Int32.shift_left (Int32.of_int (Char.code (Bytes.get bytes (offset + 1)))) 8)
       (Int32.logor
          (Int32.shift_left (Int32.of_int (Char.code (Bytes.get bytes (offset + 2)))) 16)
          (Int32.shift_left (Int32.of_int (Char.code (Bytes.get bytes (offset + 3)))) 24)))
let mesh_identity (mesh : mesh) =
  mesh.key ^ ":" ^ Digest.to_hex (Digest.bytes mesh.vertices) ^ ":" ^
  Digest.to_hex (Digest.bytes mesh.indices)
let combine_meshes meshes =
  let operation = "Scene_execution.combine_meshes" in
  let valid_indices (mesh : mesh) =
    let valid = ref true in
    for index = 0 to mesh.index_count - 1 do
      let value = Int32.to_int (u32_le mesh.indices (index * 4)) in
      if value < 0 || value >= mesh.vertex_count then valid := false
    done;
    !valid
  in
  let rec plan vertex_bytes vertex_count index_count identities = function
    | [] -> Ok (vertex_bytes, vertex_count, index_count, List.rev identities)
    | (mesh : mesh) :: rest ->
        if mesh.vertex_count <= 0 || Bytes.length mesh.vertices mod mesh.vertex_count <> 0 ||
           Bytes.length mesh.indices <> mesh.index_count * 4 || not (valid_indices mesh) then
          error operation Ogpu.Error.Invalid_argument "packed mesh cardinality is inconsistent"
        else if vertex_bytes > Sys.max_string_length - Bytes.length mesh.vertices ||
                vertex_count > Int32.to_int Int32.max_int - mesh.vertex_count ||
                index_count > (Sys.max_string_length / 4) - mesh.index_count then
          error operation Ogpu.Error.Capacity "combined mesh exceeds packed representation limits"
        else
          plan (vertex_bytes + Bytes.length mesh.vertices)
            (vertex_count + mesh.vertex_count) (index_count + mesh.index_count)
            (mesh_identity mesh :: identities) rest
  in
  match plan 0 0 0 [] meshes with
  | Error _ as result -> result
  | Ok (vertex_bytes, vertex_count, index_count, identities) ->
      let vertices = Bytes.create vertex_bytes in
      let indices = Bytes.create (index_count * 4) in
      let rec copy vertex_offset vertex_base index_offset = function
        | [] -> ()
        | (mesh : mesh) :: rest ->
            Bytes.blit mesh.vertices 0 vertices vertex_offset (Bytes.length mesh.vertices);
            for index = 0 to mesh.index_count - 1 do
              let source = Int32.to_int (u32_le mesh.indices (index * 4)) in
              set_u32_le indices (index_offset + (index * 4))
                (Int32.of_int (source + vertex_base))
            done;
            copy (vertex_offset + Bytes.length mesh.vertices)
              (vertex_base + mesh.vertex_count) (index_offset + (mesh.index_count * 4)) rest
      in
      copy 0 0 0 meshes;
      let identity = Digest.to_hex (Digest.string (String.concat "|" identities)) in
      Ok { key = "batch:" ^ identity; vertices; vertex_count; indices; index_count }
let same_optional_resource a b =
  match a, b with None, None -> true | Some a, Some b -> a == b | _ -> false
let coalesce_draws draws =
  let stride (mesh : mesh) =
    if mesh.vertex_count = 0 then 0 else Bytes.length mesh.vertices / mesh.vertex_count
  in
  let compatible (family, blend, texture, auxiliary, (draw : draw))
      (next_family, next_blend, next_texture, next_auxiliary, (next_draw : draw)) =
    family = next_family && blend = next_blend && draw.state = next_draw.state &&
    stride draw.mesh = stride next_draw.mesh &&
    same_optional_resource texture next_texture &&
    same_optional_resource auxiliary next_auxiliary
  in
  let rec take first packed_bytes entries = function
    | next :: rest when compatible first next ->
        let _, _, _, _, (draw : draw) = next in
        let bytes=Bytes.length draw.mesh.vertices+Bytes.length draw.mesh.indices in
        if packed_bytes <= cache_byte_capacity - bytes then
          take first (packed_bytes + bytes) (next :: entries) rest
        else List.rev entries, next :: rest
    | rest -> List.rev entries, rest
  in
  let rec loop result = function
    | [] -> Ok (List.rev result)
    | ((family, blend, texture, auxiliary, (draw : draw)) as first) :: rest ->
        let first_bytes=Bytes.length draw.mesh.vertices+Bytes.length draw.mesh.indices in
        if first_bytes > cache_byte_capacity then
          error "Scene_execution.coalesce" Ogpu.Error.Capacity "one mesh exceeds the batch byte capacity"
        else
        let entries, rest = take first first_bytes [first] rest in
        match entries with
        | [_] -> loop (first :: result) rest
        (* Small runs retain their independent stable identities. Coalescing a
           changing member into a shared buffer otherwise reuploads every
           unchanged neighbour. Large runs still coalesce to bound caches and
           draw payloads. *)
        | _ when List.length entries<=64->loop(List.rev_append entries result)rest
        | _ -> let meshes=List.map(fun(_,_,_,_,(entry:draw))->entry.mesh)entries in match combine_meshes meshes with
          | Error _ as result -> result
          | Ok mesh -> loop ((family, blend, texture, auxiliary, {draw with mesh}) :: result) rest
  in
  loop [] draws
let coalesce_sampled draws =
  let rec take samples acc=function (family,blend,texture,auxiliary,next_samples,draw)::rest when next_samples=samples->take samples((family,blend,texture,auxiliary,draw)::acc)rest|rest->List.rev acc,rest in
  let rec loop acc=function []->Ok(List.rev acc)|(family,blend,texture,auxiliary,samples,draw)::rest->let chunk,rest=take samples[family,blend,texture,auxiliary,draw]rest in match coalesce_draws chunk with Error _ as e->e|Ok values->loop(List.rev_append(List.map(fun(family,blend,texture,auxiliary,draw)->family,blend,texture,auxiliary,samples,draw)values)acc)rest in loop[]draws
let prepared_bytes draws=List.fold_left(fun total(_,_,_,_,_,(draw:draw))->total+Bytes.length draw.mesh.vertices+Bytes.length draw.mesh.indices)0 draws
let trim_prepared cache =
  let rec loop entries bytes keep = function
    | [] -> List.rev keep
    | item :: rest when entries < 64 && bytes <= cache_byte_capacity - item.prepared_bytes ->
        loop (entries + 1) (bytes + item.prepared_bytes) (item :: keep) rest
    | _ :: rest -> loop entries bytes keep rest
  in loop 0 0 [] cache
let resolve_prepared value prepared draws =
  match prepared with
  | Some(identity,_version) when identity=""->error"Scene_execution.prepare_run"Ogpu.Error.Invalid_argument"prepared identity is empty"
  | Some(identity,version)->
      (match List.find_opt(fun item->item.prepared_identity=identity&&item.prepared_version=version)value.prepared_cache with
      |Some item->Ok(item.prepared_draws,true)
      |None->Result.map(fun prepared_draws->let item={prepared_identity=identity;prepared_version=version;prepared_draws;prepared_bytes=prepared_bytes prepared_draws}in let others=List.filter(fun old->old.prepared_identity<>identity)value.prepared_cache in value.prepared_cache<-trim_prepared(item::others);prepared_draws,false)(coalesce_sampled draws))
  |None->Result.map(fun draws->draws,false)(coalesce_sampled draws)
let pass value family samples state load clear=
  let keys=(if samples=1 then[]else[Scene_attachment_pool.Color,samples])@(match family with Scene2|Scene2_textured->[]|Scene3|Scene3_textured|Scene3_shadow->[Depth,samples]|Scene3_stencil|Scene3_textured_stencil|Scene3_shadow_stencil->[Depth,samples;Stencil,samples])in
  match Scene_attachment_pool.acquire_many value.attachments keys with Error _ as e->e|Ok pooled->
  let attachments=ref pooled in
  let take()=match!attachments with texture::rest->attachments:=rest;texture|[]->assert false in
  let target=if samples=1 then value.target else take()in
  let texture=Ogpu.Backend.render_texture target~format:Ogpu.Render_pass.Rgba8~usage:Render_target in
  let resolve=if samples=1 then None else Some(Ogpu.Backend.render_texture value.target~format:Ogpu.Render_pass.Rgba8~usage:Resolve_target)in
  let depth=match family with Scene2|Scene2_textured->None|Scene3|Scene3_textured|Scene3_shadow|Scene3_stencil|Scene3_textured_stencil|Scene3_shadow_stencil->let texture=Ogpu.Backend.render_texture(take())~format:Ogpu.Render_pass.Depth32~usage:Render_target in Some({Ogpu.Render_pass.texture;load=state.depth_load;store=Store;clear=state.depth_clear}:Ogpu.Render_pass.depth)in
  let stencil=match family with Scene3_stencil|Scene3_textured_stencil|Scene3_shadow_stencil->let texture=Ogpu.Backend.render_texture(take())~format:Ogpu.Render_pass.Stencil8~usage:Render_target in Some({Ogpu.Render_pass.texture;load=state.stencil_load;store=Store;clear=state.stencil_clear}:Ogpu.Render_pass.stencil)|Scene2|Scene2_textured|Scene3|Scene3_textured|Scene3_shadow->None in
  let x,y,width,height=state.viewport and sx,sy,sw,sh=state.scissor in
  Result.map(fun pass->pass,pooled)(Ogpu.Render_pass.create~raster_state:{cull=state.cull;depth_compare=state.depth_compare;depth_write=state.depth_write}?stencil_state:state.stencil_state(Ogpu.Backend.device_handle value.device){colors=[|Some{texture;resolve;load;store=(if samples=1 then Store else Resolve);clear}|];depth;stencil;viewport={x;y;width;height};scissor={x=sx;y=sy;width=sw;height=sh}})
let automatic_signature
    (family,blend,samples,state,texture,auxiliary,item,uniform) =
  (* Submission signatures own affine bytes.  Scene values are immutable by
     contract, but callers may reuse their input buffer after [render] returns;
     retaining it here would turn later mutation into a false cache hit. *)
  (* Transform bytes are buffer contents, not encoded command identity.  Once
     [prepare_uniform] has selected a reserved native buffer, replaying the
     command that binds that exact buffer observes its newly uploaded bytes.
     Different transforms in one submission cannot alias because preparation
     reserves every selected slot until the complete draw graph is built. *)
  let state={state with transform_uniforms=match uniform with
    |Some _->None|None->Option.map Bytes.copy state.transform_uniforms}in
  let texture=Option.map(fun(source,cached)->
    Ogpu.Backend.texture_id cached.texture,source.sampler)texture in
  let auxiliary=Option.map(fun((source:auxiliary_resource),buffer,texture)->
    (Ogpu.Backend.buffer_id buffer.auxiliary_buffer,
     Ogpu.Backend.texture_id texture.texture,source.texture.sampler))auxiliary in
  {signature_family=family;signature_blend=blend;signature_samples=samples;
   signature_state=state;signature_texture=texture;signature_auxiliary=auxiliary;
   signature_buffer=Ogpu.Backend.buffer_id item.buffer;
   signature_index_offset=item.index_offset;
   signature_uniform_buffer=Option.map(fun item->Ogpu.Backend.buffer_id item.buffer)uniform;
   signature_vertex_count=item.vertex_count;signature_index_count=item.index_count}
let prepared_scratch_capacity=65_536
let make_prepared_slot()={slot_family=Scene2;slot_blend=Ogpu.Pipeline.Replace;
  slot_samples=1;slot_state=None;slot_texture=None;slot_auxiliary=None;
  slot_mesh=None;slot_uniform=None}
let ensure_prepared_scratch scratch needed=
  if needed>prepared_scratch_capacity then
    error"Scene_execution.render"Ogpu.Error.Capacity
      "one submission exceeds the bounded prepared-draw capacity"
  else if needed<=Array.length scratch.scratch_slots then Ok()
  else
    let rec capacity current=
      if current>=needed then current
      else capacity(min prepared_scratch_capacity(max 16(current*2)))in
    let old=scratch.scratch_slots in
    scratch.scratch_slots<-Array.init(capacity(Array.length old))(fun index->
      if index<Array.length old then Array.unsafe_get old index
      else make_prepared_slot());
    Ok()
let clear_prepared_scratch scratch=
  for index=0 to scratch.scratch_length-1 do
    let slot=Array.unsafe_get scratch.scratch_slots index in
    slot.slot_state<-None;slot.slot_texture<-None;slot.slot_auxiliary<-None;
    slot.slot_mesh<-None;slot.slot_uniform<-None
  done;
  scratch.scratch_length<-0
let scratch_mem_mesh scratch item=
  let index=ref 0 and found=ref false in
  while not!found&& !index<scratch.scratch_length do
    let slot=Array.unsafe_get scratch.scratch_slots !index in
    found:=(match slot.slot_mesh with Some candidate->candidate==item|None->false);
    incr index
  done;
  !found
let scratch_mem_uniform scratch item=
  let index=ref 0 and found=ref false in
  while not!found&& !index<scratch.scratch_length do
    let slot=Array.unsafe_get scratch.scratch_slots !index in
    found:=(match slot.slot_uniform with Some candidate->candidate==item|None->false);
    incr index
  done;
  !found
let same_automatic_slot signature slot=
  match slot.slot_state,slot.slot_mesh with
  |Some state,Some item->
      let same_state left right=
        left.viewport=right.viewport&&left.scissor=right.scissor&&
        left.cull=right.cull&&left.depth_compare=right.depth_compare&&
        left.depth_write=right.depth_write&&left.depth_load=right.depth_load&&
        left.depth_clear=right.depth_clear&&left.stencil_state=right.stencil_state&&
        left.stencil_load=right.stencil_load&&left.stencil_clear=right.stencil_clear&&
        (match slot.slot_uniform with
         |Some _->true|None->left.transform_uniforms=right.transform_uniforms)in
      let same_texture=match signature.signature_texture,slot.slot_texture with
        |None,None->true
        |Some(id,sampler),Some(source,cached)->
            id=Ogpu.Backend.texture_id cached.texture&&sampler=source.sampler
        |_->false in
      let same_auxiliary=
        match signature.signature_auxiliary,slot.slot_auxiliary with
        |None,None->true
        |Some(buffer_id,texture_id,sampler),Some(source,buffer,texture)->
            buffer_id=Ogpu.Backend.buffer_id buffer.auxiliary_buffer&&
            texture_id=Ogpu.Backend.texture_id texture.texture&&
            sampler=source.texture.sampler
        |_->false in
      signature.signature_family=slot.slot_family&&
      signature.signature_blend=slot.slot_blend&&
      signature.signature_samples=slot.slot_samples&&
      same_state signature.signature_state state&&same_texture&&same_auxiliary&&
      signature.signature_buffer=Ogpu.Backend.buffer_id item.buffer&&
      signature.signature_index_offset=item.index_offset&&
      signature.signature_uniform_buffer=
        Option.map(fun item->Ogpu.Backend.buffer_id item.buffer)slot.slot_uniform&&
      signature.signature_vertex_count=item.vertex_count&&
      signature.signature_index_count=item.index_count
  |_->false
let same_scratch_payloads payloads scratch=
  let rec loop index=function
    |[]->index=scratch.scratch_length
    |(signature,_,_)::rest when index<scratch.scratch_length->
        same_automatic_slot signature(Array.unsafe_get scratch.scratch_slots index)&&
        loop(index+1)rest
    |_->false in
  loop 0 payloads
let automatic_candidate_fingerprint scratch=
  let fingerprint=ref 0x41c64e6d in
  for index=0 to scratch.scratch_length-1 do
    let slot=Array.unsafe_get scratch.scratch_slots index in
    let state=match slot.slot_state with Some state->state|None->assert false
    and mesh=match slot.slot_mesh with Some mesh->mesh|None->assert false in
    let texture=Option.map(fun(source,cached)->
      Ogpu.Backend.texture_id cached.texture,source.sampler)slot.slot_texture
    and auxiliary=Option.map(fun((source:auxiliary_resource),buffer,texture)->
      Ogpu.Backend.buffer_id buffer.auxiliary_buffer,
      Ogpu.Backend.texture_id texture.texture,source.texture.sampler)
      slot.slot_auxiliary in
    (* This compact value is only an admission hint.  Replay still requires
       [same_scratch_payloads], so a hash collision cannot submit stale work. *)
    fingerprint:=Hashtbl.seeded_hash !fingerprint
      (slot.slot_family,slot.slot_blend,slot.slot_samples,state,texture,auxiliary,
       Ogpu.Backend.buffer_id mesh.buffer,mesh.index_offset,
       Option.map(fun uniform->Ogpu.Backend.buffer_id uniform.buffer)
         slot.slot_uniform,mesh.vertex_count,mesh.index_count)
  done;
  !fingerprint
type acquired=Offscreen|Presented of Ogpu.Backend.frame
let discard=function Offscreen->()|Presented frame->ignore(Ogpu.Backend.discard frame)
let finish_submission value=function
  |Offscreen->Ok()
  |Presented frame->Ogpu.Backend.present frame~queue:value.queue
      ~source:value.target
let acquire value=match value.surface with
  |None->Ok(`Acquired Offscreen)
  |Some surface->match Ogpu.Backend.acquire_sync surface with
    |Error _ as error->error
    |Ok(`Timeout|`Occluded)->Ok`Skipped
    |Ok`Device_lost->error"Scene_execution.render"Ogpu.Error.Device_lost"device lost"
    |Ok(`Acquired frame)->Ok(`Acquired(Presented frame))
let submit_acquired value frame commands =
  let submit_one(command,resources,pipelines)=
    match Ogpu.Backend.submit_sync value.queue command~resources~pipelines with
    |Error e->Error e|Ok admitted->Ok admitted.Ogpu.Backend.completion in
  let rec submit=function
    |[]->Result.map(fun()->Ok())(finish_submission value frame)
    |[command,resources,pipelines]->
        (match frame with
         |Offscreen->submit_one(command,resources,pipelines)
         |Presented surface_frame->
             (match Ogpu.Backend.submit_present_sync value.queue command~resources
                      ~pipelines~source:value.target surface_frame with
              |Ok admitted->Ok admitted.Ogpu.Backend.completion
              |Error e when e.Ogpu.Error.kind=Ogpu.Error.Unsupported->
                  (match submit_one(command,resources,pipelines)with
                   |Error _ as e->e
                   |Ok(Error _ as completion)->discard frame;Ok completion
                   |Ok(Ok())->Result.map(fun()->Ok())
                       (finish_submission value frame))
              |Error e->Error e))
    |entry::rest->
        (match submit_one entry with
         |Error _ as e->e
         |Ok(Error _ as completion)->discard frame;Ok completion
         |Ok(Ok())->submit rest)in
  match submit commands with
  |Ok completion->completion
  |Error error->discard frame;Error error
let replay_commands value commands =
  match acquire value with
  |Error _ as error->error|Ok`Skipped->Ok false
  |Ok(`Acquired frame)->Result.map(fun()->true)(submit_acquired value frame commands)
let render_sampled_resources_common ?prepared ?(after_prepare=Fun.id) ?(clear=(0.,0.,0.,0.)) value draws=if value.dead then(after_prepare();error"Scene_execution.render"Ogpu.Error.Stale_handle"renderer is destroyed")else if List.length draws>prepared_scratch_capacity then(after_prepare();error"Scene_execution.render"Ogpu.Error.Capacity"one submission exceeds the bounded prepared-draw capacity")else
  match prepared,value.prepared_submission with
  |Some(identity,version),Some cached when cached.submission_identity=identity&&cached.submission_version=version&&cached.submission_clear=clear->
    after_prepare();replay_commands value cached.submission_commands
  |_->value.prepared_submission<-None;
  let prepared_key=prepared in
  match resolve_prepared value prepared draws with Error _ as result ->after_prepare();result | Ok(draws,trusted_key) ->
  let valid_mesh(mesh:mesh)=mesh.key<>""&&mesh.vertex_count>0&&mesh.index_count>0&&Bytes.length mesh.vertices+Bytes.length mesh.indices>0 in
  let supported=List.for_all(fun(family,blend,_,_,samples,_)->List.exists(fun variant->variant.family=family&&variant.blend=blend&&variant.samples=samples)value.pipelines)draws in
  let valid=List.for_all(fun(_,_,texture,auxiliary,samples,(draw:draw))->List.mem samples[1;4;9;16]&&valid_mesh draw.mesh&&Option.fold~none:true~some:valid_texture texture&&Option.fold~none:true~some:(fun(source:auxiliary_resource)->source.key<>""&&Bytes.length source.buffer>0&&valid_texture source.texture)auxiliary)draws in
  if not supported then(after_prepare();error"Scene_execution.render"Ogpu.Error.Unsupported"pipeline family/blend variant is unavailable")else
  if not valid then(after_prepare();error"Scene_execution.render"Ogpu.Error.Invalid_argument"draw resource preflight failed")else
  let deferred=ref[]in let defer release=deferred:=release::!deferred in let finish result=List.iter(fun release->release())!deferred;result in
  let scratch=value.prepared_scratch in
  clear_prepared_scratch scratch;
  match ensure_prepared_scratch scratch(List.length draws)with
  |Error _ as result->after_prepare();finish result
  |Ok()->Fun.protect~finally:(fun()->clear_prepared_scratch scratch)(fun()->
  let previous=match value.automatic_submission with
    |None->[]|Some cached->cached.automatic_payloads in
  let append family blend samples state texture auxiliary mesh uniform=
    let slot=Array.unsafe_get scratch.scratch_slots scratch.scratch_length in
    slot.slot_family<-family;slot.slot_blend<-blend;slot.slot_samples<-samples;
    slot.slot_state<-Some state;slot.slot_texture<-texture;
    slot.slot_auxiliary<-auxiliary;slot.slot_mesh<-Some mesh;
    slot.slot_uniform<-uniform;scratch.scratch_length<-scratch.scratch_length+1 in
  let rec prepare_all previous=function
  |[]->Ok()
  |(family,blend,texture,auxiliary,samples,(draw:draw))::rest->
    let prior,previous=match previous with
      |(signature,_,_)::remaining->signature.signature_uniform_buffer,remaining
      |[]->None,[]in
    let preferred=match prior with None->None|Some id->
      List.find_opt(fun(item:cached)->Ogpu.Backend.buffer_id item.buffer=id)
        value.uniform_cache in
    let scene2=family=Scene2||family=Scene2_textured in
    let canonical_scene2=value.canonical_scene2_argument&&scene2 in
    let canonical_plain=value.canonical_scene2_argument&&family=Scene2 in
    let affine=scene2&&Option.fold~none:false~some:(fun bytes->
      Bytes.length bytes=24||Bytes.length bytes=48)draw.state.transform_uniforms in
    match prepare value~defer~trusted_key~reserved:(scratch_mem_mesh scratch)
      ~uniforms:(if canonical_scene2||affine then None else draw.state.transform_uniforms)
      ~nonindexed:(family=Scene2_textured||canonical_scene2)~canonical_plain draw.mesh with
    |Error _ as result->result
    |Ok mesh->
      let uniform_bytes=if canonical_scene2 then Some(match draw.state.transform_uniforms with
        |None->scene2_identity_affine|Some bytes->scene2_native_affine bytes)
        else if affine then draw.state.transform_uniforms else None in
      let uniform=match uniform_bytes with None->Ok None|Some bytes->
        Result.map Option.some(prepare_uniform value~defer
          ~reserved:(scratch_mem_uniform scratch)?preferred bytes)in
      match uniform with Error _ as result->result|Ok uniform->
      let texture=match family,texture with Scene2,None when canonical_scene2->
        Some scene2_white_texture|_->texture in
      match texture with
      |Some source->(match prepare_texture value~defer source with
        |Error _ as result->result
        |Ok texture->prepare_aux family blend auxiliary samples draw mesh uniform
          (Some(source,texture))previous rest)
      |None->prepare_aux family blend auxiliary samples draw mesh uniform None
        previous rest
  and prepare_aux family blend auxiliary samples draw mesh uniform texture
      previous rest=match auxiliary with
    |None->append family blend samples draw.state texture None mesh uniform;
      prepare_all previous rest
    |Some source->match prepare_auxiliary value~defer source with
      |Error _ as result->result
      |Ok buffer->match prepare_texture value~defer source.texture with
        |Error _ as result->result
        |Ok texture2->append family blend samples draw.state texture
          (Some(source,buffer,texture2))mesh uniform;prepare_all previous rest in
  match acquire value with Error _ as result->after_prepare();finish result
  |Ok`Skipped->after_prepare();finish(Ok false)
  |Ok(`Acquired frame)->match prepare_all previous draws with
    |Error _ as result->after_prepare();discard frame;finish result
    |Ok()->let candidate_fingerprint=automatic_candidate_fingerprint scratch in
      after_prepare();
      match value.automatic_submission with
      |Some cached when cached.automatic_clear=clear&&
        same_scratch_payloads cached.automatic_payloads scratch->
          value.automatic_candidate<-None;
          clear_prepared_scratch scratch;
          finish(Result.map(fun()->true)
            (submit_acquired value frame cached.automatic_commands))
      |_->
    let slot_state slot=match slot.slot_state with Some state->state|None->assert false
    and slot_mesh slot=match slot.slot_mesh with Some mesh->mesh|None->assert false in
    let resources=ref[]in
    let add resource=resources:=resource::!resources in
    add(`Texture value.target);
    for index=0 to scratch.scratch_length-1 do
      let slot=Array.unsafe_get scratch.scratch_slots index in
      add(`Buffer(slot_mesh slot).buffer);
      Option.iter(fun item->add(`Buffer item.buffer))slot.slot_uniform;
      Option.iter(fun(_,item)->add(`Texture item.texture))slot.slot_texture;
      Option.iter(fun(_,buffer,texture)->add(`Buffer buffer.auxiliary_buffer);
        add(`Texture texture.texture))slot.slot_auxiliary
    done;
    let seen_buffers=Hashtbl.create 32 and seen_textures=Hashtbl.create 16 in
    let resources=List.rev!resources|>List.filter(fun resource->
      let table,id=match resource with
      |`Buffer buffer->seen_buffers,Ogpu.Backend.buffer_id buffer
      |`Texture texture->seen_textures,Ogpu.Backend.texture_id texture in
      if Hashtbl.mem table id then false
      else(Hashtbl.add table id();true))in
    let attachment_class=function
      |Scene2|Scene2_textured->0
      |Scene3|Scene3_textured|Scene3_shadow->1
      |Scene3_stencil|Scene3_textured_stencil|Scene3_shadow_stencil->2 in
    let same_pass_state class_ (a:state) (b:state)=
      a.viewport=b.viewport&&a.scissor=b.scissor&&a.cull=b.cull&&
      (class_=0||(a.depth_compare=b.depth_compare&&a.depth_write=b.depth_write&&
        a.depth_load=b.depth_load&&a.depth_clear=b.depth_clear&&
        (class_=1||(a.stencil_state=b.stencil_state&&a.stencil_load=b.stencil_load&&
          a.stencil_clear=b.stencil_clear))))in
    let take class_ retained samples state start=
      let index=ref start in
      while !index<scratch.scratch_length&& !index-start<65_535&&
        let slot=Array.unsafe_get scratch.scratch_slots !index in
        attachment_class slot.slot_family=class_&&slot.slot_samples=samples&&
        (value.canonical_scene2_argument||class_<>0||
          (slot.slot_family=Scene2_textured)=retained)&&
        same_pass_state class_ state(slot_state slot)do incr index done;
      !index in
    let variant family blend samples=List.find_opt(fun value->
      value.family=family&&value.blend=blend&&value.samples=samples)value.pipelines in
    let payload_entry slot=
      let family=slot.slot_family and blend=slot.slot_blend
      and samples=slot.slot_samples and item=slot_mesh slot in
      let canonical_scene2=value.canonical_scene2_argument&&
        (family=Scene2||family=Scene2_textured)in
      let pipeline_family=if canonical_scene2&&family=Scene2 then Scene2_textured else family in
      let variant=Option.get(variant pipeline_family blend samples)in
      let texture_index,sampler_index=if canonical_scene2 then 0,1 else 1,2 in
      let textures,samplers=match slot.slot_texture with
        |None->[],[]
        |Some(source,cached)->
            [{Ogpu.Render_pass.stage=Fragment;index=texture_index;
              texture_id=Ogpu.Backend.texture_id cached.texture}],
            [{Ogpu.Render_pass.stage=Fragment;index=sampler_index;
              sampler=source.sampler}]in
      let buffers,textures,samplers=match slot.slot_auxiliary with
        |None->[{Ogpu.Render_pass.stage=Ogpu.Command.Vertex;index=0;
          buffer_id=Ogpu.Backend.buffer_id item.buffer;offset=0L}],textures,samplers
        |Some(source,buffer,texture)->
            [{Ogpu.Render_pass.stage=Ogpu.Command.Vertex;index=0;
              buffer_id=Ogpu.Backend.buffer_id item.buffer;offset=0L};
             {stage=Fragment;index=3;
              buffer_id=Ogpu.Backend.buffer_id buffer.auxiliary_buffer;offset=0L}],
            {Ogpu.Render_pass.stage=Fragment;index=4;
              texture_id=Ogpu.Backend.texture_id texture.texture}::textures,
            {Ogpu.Render_pass.stage=Fragment;index=5;
              sampler=source.texture.sampler}::samplers in
      let buffers=match slot.slot_uniform,item.uniform_offset with
        |Some uniform,_->{Ogpu.Render_pass.stage=Ogpu.Command.Vertex;index=6;
            buffer_id=Ogpu.Backend.buffer_id uniform.buffer;offset=0L}::buffers
        |None,Some offset->{Ogpu.Render_pass.stage=Ogpu.Command.Vertex;index=6;
            buffer_id=Ogpu.Backend.buffer_id item.buffer;offset}::
            {Ogpu.Render_pass.stage=Ogpu.Command.Fragment;index=6;
              buffer_id=Ogpu.Backend.buffer_id item.buffer;offset}::buffers
        |None,None->buffers in
      let index=if canonical_scene2||family=Scene2_textured then None
        else Some(Ogpu.Render_pass.Uint32,Ogpu.Backend.buffer_id item.buffer,
          item.index_offset,item.index_count)in
      ({Ogpu.Render_pass.pipeline_key=variant.key;buffers;textures;samplers;
        primitive=Triangle_list;vertex_start=0;vertex_count=item.vertex_count;index},
       variant.pipeline)in
    let made_commands=ref[]and made_payloads=ref[]in
    let previous_payloads=ref(match value.automatic_submission with
      |Some cached->cached.automatic_payloads|None->[])in
    let payloads first last=
      let rec loop index previous reversed=
        if index=last then List.rev reversed,previous else
        let slot=Array.unsafe_get scratch.scratch_slots index in
        match previous with
        |((signature,_,_)as payload)::old when same_automatic_slot signature slot->
            loop(index+1)old(payload::reversed)
        |_::old->let draw,pipeline=payload_entry slot in
            let signature=automatic_signature(slot.slot_family,slot.slot_blend,
              slot.slot_samples,slot_state slot,slot.slot_texture,
              slot.slot_auxiliary,slot_mesh slot,slot.slot_uniform)in
            loop(index+1)old((signature,draw,pipeline)::reversed)
        |[]->let draw,pipeline=payload_entry slot in
            let signature=automatic_signature(slot.slot_family,slot.slot_blend,
              slot.slot_samples,slot_state slot,slot.slot_texture,
              slot.slot_auxiliary,slot_mesh slot,slot.slot_uniform)in
            loop(index+1)[]((signature,draw,pipeline)::reversed)in
      loop first!previous_payloads[]in
    let rec batches first index=
      if index=scratch.scratch_length then if not first then Ok()else
        let width=value.configuration.Ogpu.Surface.physical_width
        and height=value.configuration.physical_height in
        let state={viewport=(0,0,width,height);scissor=(0,0,width,height);
          cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;
          depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;
          transform_uniforms=None;stencil_state=None;
          stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
        (match pass value Scene2 1 state Ogpu.Render_pass.Clear clear with
         |Error _ as result->result
         |Ok(pass,attachments)->
             let resources=List.map(fun texture->`Texture texture)attachments@resources in
             (match Ogpu.Backend.render pass[]with Error _ as result->result
              |Ok command->made_commands:=(command,resources,[])::!made_commands;Ok()))
      else
      let slot=Array.unsafe_get scratch.scratch_slots index in
      let family=slot.slot_family and samples=slot.slot_samples
      and state=slot_state slot in
      let class_=attachment_class family in
      let next=take class_(family=Scene2_textured)samples state(index+1)in
      match pass value family samples state
        (if first then Ogpu.Render_pass.Clear else Load)clear with
      |Error _ as result->result
      |Ok(pass,attachments)->
          let resources=List.map(fun texture->`Texture texture)attachments@resources in
          let automatic_payloads,remaining=payloads index next in
          previous_payloads:=remaining;
          let payload=List.map(fun(_,draw,_)->draw)automatic_payloads in
          let pipelines=List.map(fun(_,_,pipeline)->pipeline)automatic_payloads in
          made_payloads:=List.rev_append automatic_payloads!made_payloads;
          let pipelines=List.fold_left(fun unique pipeline->
            if List.exists((==)pipeline)unique then unique else pipeline::unique)[]pipelines in
          match Ogpu.Backend.render pass payload with
          |Error _ as result->result
          |Ok command->made_commands:=(command,resources,pipelines)::!made_commands;
              batches false next in
    match batches true 0 with
    |Error _ as result->discard frame;finish result
    |Ok()->
        let commands=List.rev!made_commands
        and automatic_payloads=List.rev!made_payloads in
        clear_prepared_scratch scratch;
        match submit_acquired value frame commands with
        |Error _ as result->finish result
        |Ok()->
            (match prepared_key with
             |Some(identity,version)->value.prepared_submission<-Some{
                 submission_identity=identity;submission_version=version;
                 submission_clear=clear;submission_draw_count=List.length draws;
                 submission_commands=commands}
             |None->());
            let admit=match value.automatic_candidate with
              |Some candidate->candidate.candidate_clear=clear&&
                candidate.candidate_length=List.length automatic_payloads&&
                candidate.candidate_fingerprint=candidate_fingerprint
              |None->false in
            if admit then(
              value.automatic_submission<-Some{automatic_clear=clear;
                automatic_payloads;automatic_commands=commands};
              value.automatic_candidate<-None)
            else(
              value.automatic_submission<-None;
              value.automatic_candidate<-Some{candidate_clear=clear;
                candidate_length=List.length automatic_payloads;
                candidate_fingerprint});
            finish(Ok true))
let render_sampled_resources ?after_prepare ?clear value draws=render_sampled_resources_common ?after_prepare ?clear value draws
let render_prepared_sampled_resources ?after_prepare ?clear ~identity ~version value draws=render_sampled_resources_common ?after_prepare ?clear~prepared:(identity,version)value draws
let replay_prepared_sampled_resources ?(clear=(0.,0.,0.,0.)) ~identity ~version value=
  if value.dead then error"Scene_execution.replay_prepared_sampled_resources"
      Ogpu.Error.Stale_handle"renderer is destroyed"
  else match value.prepared_submission with
  |Some cached when cached.submission_identity=identity&&
      cached.submission_version=version&&cached.submission_clear=clear->
      Result.map(fun presented->Some(presented,cached.submission_draw_count))
        (replay_commands value cached.submission_commands)
  |_->Ok None
let render_resources ?clear value draws=render_sampled_resources ?clear value(List.map(fun(family,blend,texture,auxiliary,draw)->family,blend,texture,auxiliary,1,draw)draws)
let render_textured ?clear value draws=render_resources ?clear value(List.map(fun(family,blend,texture,draw)->family,blend,texture,None,draw)draws)
let render_family ?clear value draws=render_textured ?clear value(List.map(fun(family,blend,draw)->family,blend,None,draw)draws)
let render_blended ?clear value draws=render_family ?clear value(List.map(fun(blend,draw)->Scene2,blend,draw)draws)
let render ?clear value draws=render_blended ?clear value(List.map(fun draw->Ogpu.Pipeline.Replace,draw)draws)
let resize value configuration=
  value.prepared_submission<-None;
  value.automatic_submission<-None;
  value.automatic_candidate<-None;
  let samples=List.sort_uniq Int.compare(List.map(fun variant->variant.samples)value.pipelines)in
  match allocate_target value.device configuration with Error _ as e->e|Ok target->
  let attachments=Scene_attachment_pool.create~device:value.device~configuration~sample_counts:samples in
  let rec restore=function []->Ok()|(kind,samples,_)::rest->match Scene_attachment_pool.acquire attachments kind~samples with Error _ as e->e|Ok _->restore rest in
  match restore(Scene_attachment_pool.allocated value.attachments)with Error e->ignore(Ogpu.Backend.destroy_texture target);Scene_attachment_pool.destroy attachments;Error e|Ok()->
  let configured=match value.surface with None->Ok()|Some surface->
    Ogpu.Backend.configure surface configuration in
  match configured with Error e->ignore(Ogpu.Backend.destroy_texture target);Scene_attachment_pool.destroy attachments;Error e|Ok()->let old=value.target and old_attachments=value.attachments in value.target<-target;value.configuration<-configuration;value.attachments<-attachments;Scene_attachment_pool.destroy old_attachments;Ogpu.Backend.destroy_texture old
let upload_bytes value=value.uploaded
let cache_entries value=List.length value.cache+List.length value.uniform_cache
let read_pixels value ~bytes_per_row=Ogpu.Backend.read_texture value.target~bytes_per_row
let read_pixels_into value ~bytes_per_row ~destination=
  Ogpu.Backend.read_texture_into value.target~bytes_per_row~destination
let destroy value=if value.dead then Ok()else(value.dead<-true;
  value.prepared_cache<-[];value.prepared_submission<-None;
  value.automatic_submission<-None;
  value.automatic_candidate<-None;
  clear_prepared_scratch value.prepared_scratch;
  value.prepared_scratch.scratch_slots<-[||];
  List.iter(fun item->ignore(Ogpu.Backend.destroy_buffer item.buffer))value.cache;value.cache<-[];List.iter(fun item->ignore(Ogpu.Backend.destroy_buffer item.buffer))value.uniform_cache;value.uniform_cache<-[];List.iter(fun item->ignore(Ogpu.Backend.destroy_buffer item.auxiliary_buffer))value.auxiliary_cache;value.auxiliary_cache<-[];List.iter(fun item->ignore(Ogpu.Backend.destroy_texture item.texture))value.texture_cache;value.texture_cache<-[];Option.iter(fun scratch->ignore(Ogpu.Backend.destroy_buffer scratch.scratch_buffer))value.texture_upload_scratch;value.texture_upload_scratch<-None;Scene_attachment_pool.destroy value.attachments;ignore(Ogpu.Backend.destroy_texture value.target);List.iter(fun variant->ignore(Ogpu.Backend.destroy_pipeline variant.pipeline))value.pipelines;Option.iter(fun surface->ignore(Ogpu.Backend.destroy_surface surface))value.surface;ignore(Ogpu.Backend.destroy_queue value.queue);match value.before_device_destroy()with Error _ as e->e|Ok()->Ogpu.Backend.destroy_device value.device)
