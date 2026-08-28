type texture = { levels : Raster2.Surface.t array; depth : Raster2.Depth_stencil.t }
type buffer = { bytes:bytes; mutable version:int }
type storage = Buffer of buffer | Texture of texture * Ogpu.Types.texture_descriptor
type decoded_key = int64 * int * int64 * int * bool * int64 * int
type decoded_entry = decoded_key * Raster2.Triangle.vertex array
type index_key = int64 * int * int * int64 * int
type index_entry = index_key * int array
type sampled_key = int64 * int * Raster2.Texture.filter * Raster2.Texture.address * Raster2.Texture.address
type sampled_entry = sampled_key * Raster2.Triangle.texture
type control = {
  mutable next : int64; mutable epoch : int64; mutable complete : int64;
  mutable lost : bool; log : string Queue.t; mutable dropped_log_entries:int;
  objects : (int64, storage) Hashtbl.t;
  mutable decoded:decoded_entry list; mutable decoded_indices:index_entry list;
  mutable sampled:sampled_entry list;
  mutable decode_misses:int;
  mutable fast_rectangles:int; mutable triangle_fallbacks:int;
  mutable buffers : int; mutable textures : int; mutable pipelines : int;
  mutable queues : int; mutable surfaces : int;
}

let error operation kind message = Error (Ogpu.Error.make operation kind message)
let next control = let value=control.next in control.next<-Int64.succ value; value
let log_capacity=256
let decode_cache_capacity=256
let decode_cache_byte_capacity=64*1024*1024
let trim_decode_cache weight entries =
  let rec loop count bytes kept=function
    |[]->List.rev kept
    |entry::rest->
        let size=weight entry in
        if count<decode_cache_capacity&&size<=decode_cache_byte_capacity-bytes
        then loop(count+1)(bytes+size)(entry::kept)rest
        else loop count bytes kept rest in
  loop 0 0[]entries
let record control text =
  Queue.add text control.log;
  if Queue.length control.log>log_capacity then(Queue.take control.log|>ignore;control.dropped_log_entries<-control.dropped_log_entries+1)
let valid_range bytes offset length =
  offset >= 0L && length >= 0 && length <= Bytes.length bytes
  && offset <= Int64.of_int (Bytes.length bytes - length)
let mip_extent value level=let rec loop value n=if n=0 then value else loop(max 1((value+1)/2))(n-1)in loop value level
let rgba (r,g,b,a) =
  let byte x=Int32.of_int(max 0(min 255(int_of_float(x *. 255. +. 0.5))))in
  Int32.logor(Int32.shift_left(byte r)24)
    (Int32.logor(Int32.shift_left(byte g)16)
      (Int32.logor(Int32.shift_left(byte b)8)(byte a)))

let create () =
  let control={next=1L;epoch=0L;complete=0L;lost=false;log=Queue.create();dropped_log_entries=0;
    objects=Hashtbl.create 64;decoded=[];decoded_indices=[];sampled=[];decode_misses=0;
    fast_rectangles=0;triangle_fallbacks=0;
    buffers=0;textures=0;pipelines=0;queues=0;surfaces=0}in
  let create_device () =
    let device_token=next control and device_handle=Ogpu.Handle.create_device()in
    let resource label storage =
      let token=next control in Hashtbl.add control.objects token storage;
      (match storage with Buffer _->control.buffers<-control.buffers+1
       |Texture _->control.textures<-control.textures+1);
      record control(label^":"^Int64.to_string token);
      let write offset source = match Hashtbl.find_opt control.objects token with
        |Some(Buffer buffer)when valid_range buffer.bytes offset(Bytes.length source)->
            Bytes.blit source 0 buffer.bytes(Int64.to_int offset)(Bytes.length source);
            buffer.version<-buffer.version+1;Ok()
        |Some(Texture({levels;_},_))when offset=0L&&Bytes.length source=Bytes.length(Raster2.Surface.bytes levels.(0))->
            Bytes.blit source 0(Raster2.Surface.bytes levels.(0))0(Bytes.length source);Ok()
        |_->error"Ogpu_raster2.write"Invalid_argument"range is invalid"in
      let read offset length = match Hashtbl.find_opt control.objects token with
        |Some(Buffer buffer)when valid_range buffer.bytes offset length->Ok(Bytes.sub buffer.bytes(Int64.to_int offset)length)
        |Some(Texture({levels;_},_))when offset=0L&&length<=Bytes.length(Raster2.Surface.bytes levels.(0))->Ok(Bytes.sub(Raster2.Surface.bytes levels.(0))0 length)
        |_->error"Ogpu_raster2.read"Invalid_argument"range is invalid"in
      let read_into offset destination destination_offset length =
        if destination_offset<0||length<0||length>Bytes.length destination-destination_offset
        then error"Ogpu_raster2.read_into"Invalid_argument"destination range is invalid"
        else match Hashtbl.find_opt control.objects token with
        |Some(Buffer buffer)when valid_range buffer.bytes offset length->
            Bytes.blit buffer.bytes(Int64.to_int offset)destination destination_offset length;Ok()
        |Some(Texture({levels;_},_))when offset=0L&&length<=Bytes.length(Raster2.Surface.bytes levels.(0))->
            Bytes.blit(Raster2.Surface.bytes levels.(0))0 destination destination_offset length;Ok()
        |_->error"Ogpu_raster2.read_into"Invalid_argument"range is invalid"in
      let destroy () = match Hashtbl.find_opt control.objects token with
        |None->Ok()|Some(Buffer _)->Hashtbl.remove control.objects token;
            control.decoded<-List.filter(fun((cached,_,uniform,_,_,_,_),_)->cached<>token&&uniform<>token)control.decoded;
            control.decoded_indices<-List.filter(fun((cached,_,_,_,_),_)->cached<>token)control.decoded_indices;
            control.buffers<-control.buffers-1;Ok()
        |Some(Texture _)->Hashtbl.remove control.objects token;
            control.sampled<-List.filter(fun((cached,_,_,_,_),_)->cached<>token)control.sampled;
            control.textures<-control.textures-1;Ok()in
      Ok{Ogpu.Backend.token;write;read;read_into;destroy}
    in
    let create_queue () =
      let queue_token=next control in control.queues<-control.queues+1;
      let submit command ~resources ~pipelines =
        if control.lost then error"Ogpu_raster2.submit"Device_lost"injected device loss"else
        let find id=Option.bind(List.assoc_opt id resources)(Hashtbl.find_opt control.objects)in
        let render submission =
          let descriptor=Ogpu.Render_pass.descriptor(Ogpu.Render_pass.submission_pass submission)
          and draws=Ogpu.Render_pass.submission_draws submission in
          let rec first_color index=
            if index=Array.length descriptor.colors then None else
            match descriptor.colors.(index)with
            |None->first_color(index+1)
            |Some color->Some color in
          let target=Option.bind(first_color 0)(fun(c:Ogpu.Render_pass.color)->find c.texture.id)in
          let sampled_pairs(d:Ogpu.Render_pass.draw)=
            let textures=List.filter(fun(t:Ogpu.Render_pass.texture_binding)->t.stage=Ogpu.Command.Fragment)d.textures|>List.sort(fun(a:Ogpu.Render_pass.texture_binding)b->Int.compare a.index b.index)
            and samplers=List.filter(fun(s:Ogpu.Render_pass.sampler_binding)->s.stage=Ogpu.Command.Fragment)d.samplers|>List.sort(fun(a:Ogpu.Render_pass.sampler_binding)b->Int.compare a.index b.index)in
            if List.length textures<>List.length d.textures||List.length samplers<>List.length d.samplers||List.length textures<>List.length samplers then None
            else Some(List.combine textures samplers)in
          let prepared_draws=List.map(fun draw->draw,sampled_pairs draw)draws in
          let complete((draw:Ogpu.Render_pass.draw),pairs)=
            Option.is_some pairs&&
            List.for_all(fun(b:Ogpu.Render_pass.buffer_binding)->Option.is_some(find b.buffer_id))draw.buffers&&
            List.for_all(fun(t:Ogpu.Render_pass.texture_binding)->Option.is_some(find t.texture_id))draw.textures&&
            match draw.index with None->true|Some(_,id,_,_)->Option.is_some(find id)in
          if draws=[]||pipelines=[]||not(List.for_all complete prepared_draws)then
            error"Ogpu_raster2.render"Invalid_argument"draw graph is incomplete"
          else match target with
          |Some(Texture({levels;depth},_))->let color=levels.(0)in
              Option.iter(fun(c:Ogpu.Render_pass.color)->if c.load=Clear then Raster2.Surface.clear color(rgba c.clear))(first_color 0);
              Option.iter(fun(d:Ogpu.Render_pass.depth)->if d.load=Clear then ignore(Raster2.Depth_stencil.clear depth~depth:d.clear~stencil:0))descriptor.depth;
              let clip={Raster2.Triangle.x=descriptor.scissor.x;y=descriptor.scissor.y;width=descriptor.scissor.width;height=descriptor.scissor.height}
              and depth_state={Raster2.Depth_stencil.depth_compare=Always;depth_write=false;stencil=None}in
              let draw((d:Ogpu.Render_pass.draw),
                  (sampled_pairs:(Ogpu.Render_pass.texture_binding*
                    Ogpu.Render_pass.sampler_binding)list option))=
                match List.find_opt(fun(b:Ogpu.Render_pass.buffer_binding)->b.stage=Ogpu.Command.Vertex&&b.index=0)d.buffers with
                |None->error"Ogpu_raster2.render"Invalid_argument"vertex buffer zero is absent"
                |Some binding->match find binding.buffer_id with
                  |Some(Buffer vertex_buffer)->(let vertices=vertex_buffer.bytes in let sampled=Option.bind sampled_pairs(function pair::_->Some pair|[]->None)in let texture()=match sampled with None->Ok None|Some((binding:Ogpu.Render_pass.texture_binding),sampler)->match find binding.texture_id,List.assoc_opt binding.texture_id resources with Some(Texture({levels;_},_)),Some token->let first=match sampler.sampler.mip_filter with No_mip->0|Nearest_mip|Linear_mip->min(Array.length levels-1)(int_of_float(floor sampler.sampler.lod_min))in let filter=match sampler.sampler.mip_filter,sampler.sampler.min_filter with Linear_mip,_->Raster2.Texture.Trilinear|_,Linear->Bilinear|_,Nearest->Nearest and address=function Ogpu.Types.Clamp_to_edge->Raster2.Texture.Clamp|Repeat->Repeat|Mirror_repeat->Mirror in let address_u=address sampler.sampler.address_u and address_v=address sampler.sampler.address_v in let key=token,first,filter,address_u,address_v in(match List.assoc_opt key control.sampled with Some texture->Ok(Some texture)|None->let sampled_levels=if first=0 then levels else Array.sub levels first(Array.length levels-first)in(match Raster2.Texture.Private.create_levels_borrowed~color_space:Raster2.Texture.Linear sampled_levels with Ok texture->let value={Raster2.Triangle.texture;filter;address_u;address_v}in control.sampled<-(key,value)::control.sampled;if List.length control.sampled>32 then control.sampled<-List.rev(List.tl(List.rev control.sampled));Ok(Some value)|Error _->error"Ogpu_raster2.render"Invalid_argument"fragment texture is invalid"))|_->error"Ogpu_raster2.render"Invalid_argument"fragment texture is absent"in let textured=Option.is_some sampled in let indices=match d.index with
                    |None->if d.vertex_count<0||d.vertex_start<0 then None else Some(Array.init d.vertex_count(fun i->d.vertex_start+i))
                    |Some(kind,id,offset,count)->match find id with
                      |Some(Buffer buffer)->let bytes=buffer.bytes and width=match kind with Uint16->2|Uint32->4 in
                          if count<0||count>max_int/width||not(valid_range bytes offset(count*width))then None
                          else let token=match List.assoc_opt id resources with Some token->token|None->assert false in
                            let key=(token,buffer.version,width,offset,count)in
                            (match List.assoc_opt key control.decoded_indices with
                             |Some indices->Some indices
                             |None->
                                 let indices=Array.init count(fun i->if width=2 then Bytes.get_uint16_le bytes(Int64.to_int offset+i*width)else Int32.to_int(Bytes.get_int32_le bytes(Int64.to_int offset+i*width)))in
                                 control.decode_misses<-control.decode_misses+1;
                                 control.decoded_indices<-(key,indices)::control.decoded_indices;
                                 control.decoded_indices<-trim_decode_cache
                                   (fun(_,indices)->Array.length indices*(Sys.word_size/8))
                                   control.decoded_indices;
                                 Some indices)
                      |_->None in
                    match indices with None->error"Ogpu_raster2.render"Invalid_argument"index range is invalid"|Some indices->
                    let maximum=Array.fold_left max(-1)indices and stride=if textured then 68 else 16 in
                    if maximum<0||Array.exists(fun index->index<0)indices||maximum>(max_int/stride)-1
                       ||not(valid_range vertices binding.offset((maximum+1)*stride))
                    then error"Ogpu_raster2.render"Invalid_argument"vertex or index range is invalid"
                    else
                      let buffer_token=match List.assoc_opt binding.buffer_id resources with
                        |Some token->token|None->assert false in
                      let affine=match List.find_opt(fun(b:Ogpu.Render_pass.buffer_binding)->b.stage=Ogpu.Command.Vertex&&b.index=6)d.buffers with
                        |Some uniform_binding->(match find uniform_binding.buffer_id,List.assoc_opt uniform_binding.buffer_id resources with
                          |Some(Buffer uniform_buffer),Some uniform_token when Bytes.length uniform_buffer.bytes=24&&valid_range uniform_buffer.bytes uniform_binding.offset 24->
                              let at index=Int32.float_of_bits(Bytes.get_int32_le uniform_buffer.bytes(Int64.to_int uniform_binding.offset+index*4))in
                              Some(uniform_token,uniform_buffer.version,at 0,at 1,at 2,at 3,at 4,at 5)
                          |_->None)
                        |None->None in
                      let uniform_token,uniform_version=match affine with Some(token,version,_,_,_,_,_,_)->token,version|None->0L,0 in
                      let key=(buffer_token,vertex_buffer.version,uniform_token,uniform_version,textured,binding.offset,maximum+1)in
                      let decoded=match List.assoc_opt key control.decoded with
                        |Some decoded->decoded
                        |None->
                            let base=Int64.to_int binding.offset in
                            let decoded=Array.init(maximum+1)(fun index->
                              let offset=base+index*stride in
                              let x=Int64.float_of_bits(Bytes.get_int64_le vertices offset)
                              and y=Int64.float_of_bits(Bytes.get_int64_le vertices(offset+8))in
                              let x,y=match affine with None->x,y|Some(_,_,xx,yx,tx,xy,yy,ty)->xx*.x+.yx*.y+.tx,xy*.x+.yy*.y+.ty in
                              {Raster2.Triangle.x=x;
                                y;
                                depth=(if textured then Int64.float_of_bits(Bytes.get_int64_le vertices(offset+16))else 0.);
                                color=(if textured then Bytes.get_int32_le vertices(offset+48)else 0x4080BFFFl);
                                u=(if textured then Int64.float_of_bits(Bytes.get_int64_le vertices(offset+52))else 0.);
                                v=(if textured then Int64.float_of_bits(Bytes.get_int64_le vertices(offset+60))else 0.)})in
                            control.decode_misses<-control.decode_misses+1;
                            control.decoded<-(key,decoded)::control.decoded;
                            control.decoded<-trim_decode_cache
                              (fun(_,vertices)->Array.length vertices*64)
                              control.decoded;
                            decoded in
                      let depth=Option.map(fun _->depth)descriptor.depth in
                      let fast_source=match sampled with
                        |Some(binding,sampler)->(match find binding.texture_id with
                            |Some(Texture({levels;_},_))->Some(levels.(0),sampler.sampler)
                            |_->None)
                        |None->None in
                      let fast_rectangle()=match fast_source with None->false|Some(source,sampler)->
                        let integral value=Float.is_finite value&&value=floor value in
                        let rectangle_vertices=
                          if Array.length indices=6&&Array.length decoded=4&&
                             indices.(0)=0&&indices.(1)=1&&indices.(2)=2&&
                             indices.(3)=0&&indices.(4)=2&&indices.(5)=3
                          then Some(decoded.(0),decoded.(1),decoded.(2),decoded.(3))
                          else if Array.length indices=6&&Array.length decoded=6&&
                            indices.(0)=0&&indices.(1)=1&&indices.(2)=2&&
                            indices.(3)=3&&indices.(4)=4&&indices.(5)=5&&
                            decoded.(0)=decoded.(3)&&decoded.(2)=decoded.(4)
                          then Some(decoded.(0),decoded.(1),decoded.(2),decoded.(5))
                          else None in
                        if descriptor.depth<>None||descriptor.stencil<>None||
                           (Ogpu.Render_pass.raster_state(Ogpu.Render_pass.submission_pass submission)).cull<>
                             Ogpu.Render_pass.Cull_none||
                           d.primitive<>Triangle_list||Option.is_none rectangle_vertices||
                           sampler.min_filter<>Linear||sampler.mag_filter<>Linear||sampler.mip_filter<>No_mip||
                           sampler.address_u<>Clamp_to_edge||sampler.address_v<>Clamp_to_edge||sampler.lod_min<>0.
                        then false else
                        let a,b,c,e=Option.get rectangle_vertices in
                        let white vertex=vertex.Raster2.Triangle.color=0xffffffffl in
                        let rectangle=a.y=b.y&&b.x=c.x&&c.y=e.y&&e.x=a.x&&b.x>a.x&&c.y>a.y
                          &&a.v=b.v&&b.u=c.u&&c.v=e.v&&e.u=a.u&&b.u>a.u&&c.v>a.v in
                        let source_width=float(Raster2.Surface.width source)
                        and source_height=float(Raster2.Surface.height source)in
                        let sx=a.u*.source_width and sy=a.v*.source_height
                        and sw=(b.u-.a.u)*.source_width and sh=(e.v-.a.v)*.source_height
                        and dw=b.x-.a.x and dh=e.y-.a.y in
                        if not(rectangle&&white a&&white b&&white c&&white e&&
                          integral a.x&&integral a.y&&integral dw&&integral dh&&
                          integral sx&&integral sy&&integral sw&&integral sh&&sw=dw&&sh=dh&&
                          sx>=0.&&sy>=0.&&sx+.sw<=source_width&&sy+.sh<=source_height&&
                          a.x>=float clip.x&&a.y>=float clip.y&&b.x<=float(clip.x+clip.width)&&
                          e.y<=float(clip.y+clip.height))then false else
                        let source_bytes=Raster2.Surface.bytes source
                        and destination_bytes=Raster2.Surface.bytes color
                        and source_pitch=Raster2.Surface.pitch source
                        and destination_pitch=Raster2.Surface.pitch color
                        and source_x=int_of_float sx and source_y=int_of_float sy
                        and destination_x=int_of_float a.x and destination_y=int_of_float a.y
                        and width=int_of_float sw and height=int_of_float sh in
                        let copy row=Bytes.blit source_bytes
                            ((source_y+row)*source_pitch+source_x*4)destination_bytes
                            ((destination_y+row)*destination_pitch+destination_x*4)(width*4)in
                        if source_bytes==destination_bytes&&destination_y>source_y
                        then for row=height-1 downto 0 do copy row done
                        else for row=0 to height-1 do copy row done;
                        true in
                      if fast_rectangle()then(control.fast_rectangles<-control.fast_rectangles+1;Ok())
                      else match texture()with Error _ as failure->failure|Ok texture->
                        control.triangle_fallbacks<-control.triangle_fallbacks+1;
                        let triangle a b c=Raster2.Triangle.draw~color~depth~depth_state
                            ~blend:Raster2.Composite.Copy~cull:Cull_none~clip~texture
                            decoded.(a)decoded.(b)decoded.(c)in
                        (match d.primitive with
                         |Triangle_list->for i=0 to Array.length indices/3-1 do triangle indices.(i*3)indices.(i*3+1)indices.(i*3+2)done
                         |Triangle_strip->for i=0 to Array.length indices-3 do if i land 1=0 then triangle indices.(i)indices.(i+1)indices.(i+2)else triangle indices.(i+1)indices.(i)indices.(i+2)done);
                        Ok())
                  |_->error"Ogpu_raster2.render"Invalid_argument"vertex buffer is absent"in
              let resolve()=
                Array.iter
                  (function
                    |Some(c:Ogpu.Render_pass.color)->
                        Option.iter(fun texture->match find texture.Ogpu.Render_pass.id with
                          |Some(Texture({levels;_},_))->
                              Bytes.blit(Raster2.Surface.bytes color)0
                                (Raster2.Surface.bytes levels.(0))0
                                (Bytes.length(Raster2.Surface.bytes color))
                          |_->())c.resolve
                    |None->())descriptor.colors
              in
              let rec all=function []->resolve();Ok()|x::xs->match draw x with Error _ as e->e|Ok()->all xs in all prepared_draws
          |_->error"Ogpu_raster2.render"Invalid_argument"color attachment is absent"in
        let transfer operations =
          let buffer id=match find id with Some(Buffer buffer)->Some buffer.bytes|_->None and texture id mip=match find id with Some(Texture({levels;_},_))when mip>=0&&mip<Array.length levels->Some levels.(mip)|_->None in
          let extent surface origin extent=
            origin.Ogpu.Transfer_pass.z=0&&extent.Ogpu.Transfer_pass.depth=1
            &&origin.x>=0&&origin.y>=0
            &&origin.x+extent.width<=Raster2.Surface.width surface
            &&origin.y+extent.height<=Raster2.Surface.height surface in
          let int64_length value=value>=0L&&value<=Int64.of_int max_int in
          let valid=function
            |Ogpu.Transfer_pass.Copy_buffer(src,so,dst,do_,length)->
                int64_length length&&(match buffer src,buffer dst with
                |Some a,Some b->valid_range a so(Int64.to_int length)&&valid_range b do_(Int64.to_int length)|_->false)
            |Fill_buffer(id,offset,length,_)->int64_length length&&(match buffer id with Some bytes->valid_range bytes offset(Int64.to_int length)|_->false)
            |Buffer_to_texture(src,offset,row,_,dst,mip,origin,size)->
                int64_length row&&size.height>=0&&Int64.to_int row<=max_int/max 1 size.height&&
                (match buffer src,texture dst mip with Some bytes,Some surface->extent surface origin size&&valid_range bytes offset(Int64.to_int row*size.height)|_->false)
            |Texture_to_buffer(src,mip,origin,size,dst,offset,row,_)->
                int64_length row&&size.height>=0&&Int64.to_int row<=max_int/max 1 size.height&&
                (match texture src mip,buffer dst with Some surface,Some bytes->extent surface origin size&&valid_range bytes offset(Int64.to_int row*size.height)|_->false)
            |Copy_texture(src,sm,so,dst,dm,do_,size)->
                (match texture src sm,texture dst dm with Some a,Some b->extent a so size&&extent b do_ size|_->false)in
          if not(Array.for_all valid operations)then
            error"Ogpu_raster2.transfer"Invalid_argument"transfer batch validation failed"
          else begin
          List.iter(fun(_,token)->match Hashtbl.find_opt control.objects token with
            |Some(Buffer buffer)->buffer.version<-buffer.version+1|_->())resources;
          let copy_rows ~src ~src_offset ~src_row ~dst ~dst_offset ~dst_row width height=for row=0 to height-1 do Bytes.blit src(src_offset+row*src_row)dst(dst_offset+row*dst_row)width done in
          let execute=function
            |Ogpu.Transfer_pass.Copy_buffer(src,so,dst,do_,length)->(match buffer src,buffer dst with Some a,Some b when valid_range a so(Int64.to_int length)&&valid_range b do_(Int64.to_int length)->Bytes.blit a(Int64.to_int so)b(Int64.to_int do_)(Int64.to_int length);Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"buffer copy range")
            |Fill_buffer(id,offset,length,value)->(match buffer id with Some bytes when valid_range bytes offset(Int64.to_int length)->Bytes.fill bytes(Int64.to_int offset)(Int64.to_int length)(Char.chr value);Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"buffer fill range")
            |Buffer_to_texture(src,offset,row,_,dst,mip,origin,extent)->(match buffer src,texture dst mip with Some bytes,Some surface when origin.z=0&&extent.depth=1&&origin.x>=0&&origin.y>=0&&origin.x+extent.width<=Raster2.Surface.width surface&&origin.y+extent.height<=Raster2.Surface.height surface&&valid_range bytes offset(Int64.to_int row*extent.height)->copy_rows~src:bytes~src_offset:(Int64.to_int offset)~src_row:(Int64.to_int row)~dst:(Raster2.Surface.bytes surface)~dst_offset:(origin.y*Raster2.Surface.pitch surface+origin.x*4)~dst_row:(Raster2.Surface.pitch surface)(extent.width*4)extent.height;Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"buffer texture upload")
            |Texture_to_buffer(src,mip,origin,extent,dst,offset,row,_)->(match texture src mip,buffer dst with Some surface,Some bytes when origin.z=0&&extent.depth=1&&origin.x>=0&&origin.y>=0&&origin.x+extent.width<=Raster2.Surface.width surface&&origin.y+extent.height<=Raster2.Surface.height surface&&valid_range bytes offset(Int64.to_int row*extent.height)->copy_rows~src:(Raster2.Surface.bytes surface)~src_offset:(origin.y*Raster2.Surface.pitch surface+origin.x*4)~src_row:(Raster2.Surface.pitch surface)~dst:bytes~dst_offset:(Int64.to_int offset)~dst_row:(Int64.to_int row)(extent.width*4)extent.height;Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"texture buffer download")
            |Copy_texture(src,sm,so,dst,dm,do_,extent)->(match texture src sm,texture dst dm with Some a,Some b when so.z=0&&do_.z=0&&extent.depth=1&&so.x>=0&&so.y>=0&&do_.x>=0&&do_.y>=0&&so.x+extent.width<=Raster2.Surface.width a&&so.y+extent.height<=Raster2.Surface.height a&&do_.x+extent.width<=Raster2.Surface.width b&&do_.y+extent.height<=Raster2.Surface.height b->let temporary=Bytes.create(extent.width*extent.height*4)in copy_rows~src:(Raster2.Surface.bytes a)~src_offset:(so.y*Raster2.Surface.pitch a+so.x*4)~src_row:(Raster2.Surface.pitch a)~dst:temporary~dst_offset:0~dst_row:(extent.width*4)(extent.width*4)extent.height;copy_rows~src:temporary~src_offset:0~src_row:(extent.width*4)~dst:(Raster2.Surface.bytes b)~dst_offset:(do_.y*Raster2.Surface.pitch b+do_.x*4)~dst_row:(Raster2.Surface.pitch b)(extent.width*4)extent.height;Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"texture copy range")in
          let rec loop index=if index=Array.length operations then Ok()else match execute operations.(index)with Ok()->loop(index+1)|Error _ as failure->failure in loop 0 end in
        let result=match command with Ogpu.Backend.Render submission->render submission|Compute _->error"Ogpu_raster2.compute"Unsupported"software compute is unsupported"|Transfer operations->transfer operations in
        match result with Error _ as e->e|Ok()->control.epoch<-Int64.succ control.epoch;record control("submit:"^Int64.to_string control.epoch);Ok{Ogpu.Backend.epoch=control.epoch}in
      Ok{Ogpu.Backend.queue_token;submit;complete_through=(fun epoch->if epoch<=control.complete||epoch>control.epoch then error"Ogpu_raster2.complete"Invalid_argument"epoch is invalid"else(control.complete<-epoch;Ok()));destroy_queue=(fun()->control.queues<-control.queues-1;Ok())}
    in
    Ok{Ogpu.Backend.device_token;device_handle;capabilities=Ogpu.Capabilities.minimum_m1;
      create_buffer=(fun d->resource"buffer"(Buffer{bytes=Bytes.make(Int64.to_int d.Ogpu.Types.size)'\000';version=0}));
      create_texture=(fun d->let levels=Array.init d.mip_levels(fun mip->Raster2.Surface.create~width:(mip_extent d.width mip)~height:(mip_extent d.height mip)())in if Array.exists Result.is_error levels then error"Ogpu_raster2.texture"Invalid_argument"texture mip extent is invalid"else match Raster2.Depth_stencil.create~width:d.width~height:d.height()with Ok depth->resource"texture"(Texture({levels=Array.map Result.get_ok levels;depth},d))|Error _->error"Ogpu_raster2.texture"Invalid_argument"texture extent is invalid");
      create_depth_texture=(fun d->match Raster2.Surface.create~width:d.width~height:d.height(),Raster2.Depth_stencil.create~width:d.width~height:d.height()with Ok surface,Ok depth->resource"texture"(Texture({levels=[|surface|];depth},d))|_->error"Ogpu_raster2.depth_texture"Invalid_argument"depth texture extent is invalid");
      create_stencil_texture=(fun d->match Raster2.Surface.create~width:d.width~height:d.height(),Raster2.Depth_stencil.create~width:d.width~height:d.height()with Ok surface,Ok depth->resource"texture"(Texture({levels=[|surface|];depth},d))|_->error"Ogpu_raster2.stencil_texture"Invalid_argument"stencil texture extent is invalid");
      create_pipeline=(fun _->let pipeline_token=next control in control.pipelines<-control.pipelines+1;Ok{Ogpu.Backend.pipeline_token;destroy_pipeline=(fun()->control.pipelines<-control.pipelines-1;Ok())});create_queue;
      create_surface=(fun _->let surface_token=next control and frame=ref 0L in control.surfaces<-control.surfaces+1;Ok{Ogpu.Backend.surface_token;configure=(fun _->Ok());acquire=(fun()->if control.lost then Ok`Device_lost else(frame:=Int64.succ!frame;Ok(`Acquired{Ogpu.Backend.frame_token= !frame})));present=(fun _->Ok());discard=(fun _->Ok());destroy_surface=(fun()->control.surfaces<-control.surfaces-1;Ok())});
      destroy_device=(fun()->Ogpu.Handle.destroy_device device_handle;Ok())}
  in {Ogpu.Backend.create_device},control
let inject_device_loss control=control.lost<-true;control.decoded<-[];
  control.decoded_indices<-[];control.sampled<-[]
let trace control=List.of_seq(Queue.to_seq control.log)
let trace_stats control=Queue.length control.log,control.dropped_log_entries
let decode_cache_stats control=
  List.length control.decoded+List.length control.decoded_indices,control.decode_misses
let decode_cache_bytes control=
  List.fold_left(fun total(_,vertices)->total+Array.length vertices*64)0 control.decoded+
  List.fold_left(fun total(_,indices)->total+Array.length indices*(Sys.word_size/8))0
    control.decoded_indices
let sampled_cache_entries control=List.length control.sampled
let rectangle_path_stats control=control.fast_rectangles,control.triangle_fallbacks
let live_counts control=control.buffers,control.textures,control.pipelines,control.queues,control.surfaces
