type texture = { color : Raster2.Surface.t; depth : Raster2.Depth_stencil.t }
type storage = Buffer of bytes | Texture of texture * Ogpu.Types.texture_descriptor
type control = {
  mutable next : int64; mutable epoch : int64; mutable complete : int64;
  mutable lost : bool; log : string Queue.t; mutable dropped_log_entries:int;
  objects : (int64, storage) Hashtbl.t;
  mutable buffers : int; mutable textures : int; mutable pipelines : int;
  mutable queues : int; mutable surfaces : int;
}

let error operation kind message = Error (Ogpu.Error.make operation kind message)
let next control = let value=control.next in control.next<-Int64.succ value; value
let log_capacity=256
let record control text =
  Queue.add text control.log;
  if Queue.length control.log>log_capacity then(Queue.take control.log|>ignore;control.dropped_log_entries<-control.dropped_log_entries+1)
let valid_range bytes offset length =
  offset >= 0L && length >= 0 && length <= Bytes.length bytes
  && offset <= Int64.of_int (Bytes.length bytes - length)
let rgba (r,g,b,a) =
  let byte x=Int32.of_int(max 0(min 255(int_of_float(x *. 255. +. 0.5))))in
  Int32.logor(Int32.shift_left(byte r)24)
    (Int32.logor(Int32.shift_left(byte g)16)
      (Int32.logor(Int32.shift_left(byte b)8)(byte a)))

let create () =
  let control={next=1L;epoch=0L;complete=0L;lost=false;log=Queue.create();dropped_log_entries=0;
    objects=Hashtbl.create 64;buffers=0;textures=0;pipelines=0;queues=0;surfaces=0}in
  let create_device () =
    let device_token=next control and device_handle=Ogpu.Handle.create_device()in
    let resource label storage =
      let token=next control in Hashtbl.add control.objects token storage;
      (match storage with Buffer _->control.buffers<-control.buffers+1
       |Texture _->control.textures<-control.textures+1);
      record control(label^":"^Int64.to_string token);
      let write offset source = match Hashtbl.find_opt control.objects token with
        |Some(Buffer bytes)when valid_range bytes offset(Bytes.length source)->
            Bytes.blit source 0 bytes(Int64.to_int offset)(Bytes.length source);Ok()
        |Some(Texture({color;_},_))when offset=0L&&Bytes.length source=Bytes.length(Raster2.Surface.bytes color)->
            Bytes.blit source 0(Raster2.Surface.bytes color)0(Bytes.length source);Ok()
        |_->error"Ogpu_raster2.write"Invalid_argument"range is invalid"in
      let read offset length = match Hashtbl.find_opt control.objects token with
        |Some(Buffer bytes)when valid_range bytes offset length->Ok(Bytes.sub bytes(Int64.to_int offset)length)
        |Some(Texture({color;_},_))when offset=0L&&length<=Bytes.length(Raster2.Surface.bytes color)->Ok(Bytes.sub(Raster2.Surface.bytes color)0 length)
        |_->error"Ogpu_raster2.read"Invalid_argument"range is invalid"in
      let destroy () = match Hashtbl.find_opt control.objects token with
        |None->Ok()|Some(Buffer _)->Hashtbl.remove control.objects token;control.buffers<-control.buffers-1;Ok()
        |Some(Texture _)->Hashtbl.remove control.objects token;control.textures<-control.textures-1;Ok()in
      Ok{Ogpu.Backend.token;write;read;destroy}
    in
    let create_queue () =
      let queue_token=next control in control.queues<-control.queues+1;
      let submit command ~resources ~pipelines =
        if control.lost then error"Ogpu_raster2.submit"Device_lost"injected device loss"else
        let find id=Option.bind(List.assoc_opt id resources)(Hashtbl.find_opt control.objects)in
        let render submission =
          let descriptor=Ogpu.Render_pass.descriptor(Ogpu.Render_pass.submission_pass submission)
          and draws=Ogpu.Render_pass.submission_draws submission in
          let target=Array.to_list descriptor.colors|>List.find_map(function None->None|Some(c:Ogpu.Render_pass.color)->find c.texture.id)in
          let required=List.concat_map(fun(d:Ogpu.Render_pass.draw)->
            List.map(fun(b:Ogpu.Render_pass.buffer_binding)->b.buffer_id)d.buffers@
            List.map(fun(t:Ogpu.Render_pass.texture_binding)->t.texture_id)d.textures@
            match d.index with None->[]|Some(_,id,_,_)->[id])draws in
          if draws=[]||pipelines=[]||List.exists(fun id->Option.is_none(find id))required then
            error"Ogpu_raster2.render"Invalid_argument"draw graph is incomplete"
          else match target with
          |Some(Texture({color;depth},_))->
              Option.iter(fun(c:Ogpu.Render_pass.color)->if c.load=Clear then Raster2.Surface.clear color(rgba c.clear))(Array.to_list descriptor.colors|>List.find_map Fun.id);
              Option.iter(fun(d:Ogpu.Render_pass.depth)->if d.load=Clear then ignore(Raster2.Depth_stencil.clear depth~depth:d.clear~stencil:0))descriptor.depth;
              let clip={Raster2.Triangle.x=descriptor.scissor.x;y=descriptor.scissor.y;width=descriptor.scissor.width;height=descriptor.scissor.height}
              and depth_state={Raster2.Depth_stencil.depth_compare=Always;depth_write=false;stencil=None}in
              let vertex textured bytes offset index = let stride=if textured then 68 else 16 in let base=Int64.to_int offset+index*stride in
                {Raster2.Triangle.x=Int64.float_of_bits(Bytes.get_int64_le bytes base);y=Int64.float_of_bits(Bytes.get_int64_le bytes(base+8));depth=(if textured then Int64.float_of_bits(Bytes.get_int64_le bytes(base+16))else 0.);color=(if textured then Bytes.get_int32_le bytes(base+48)else 0x4080BFFFl);u=(if textured then Int64.float_of_bits(Bytes.get_int64_le bytes(base+52))else 0.);v=(if textured then Int64.float_of_bits(Bytes.get_int64_le bytes(base+60))else 0.)}in
              let draw(d:Ogpu.Render_pass.draw)=match List.find_opt(fun(b:Ogpu.Render_pass.buffer_binding)->b.stage=Ogpu.Command.Vertex&&b.index=0)d.buffers with
                |None->error"Ogpu_raster2.render"Invalid_argument"vertex buffer zero is absent"
                |Some binding->match find binding.buffer_id with
                  |Some(Buffer vertices)->(let sampled=List.find_opt(fun(t:Ogpu.Render_pass.texture_binding)->t.stage=Ogpu.Command.Fragment&&t.index=0)d.textures in let texture=match sampled with None->Ok None|Some binding->match find binding.texture_id with Some(Texture({color=surface;_},_))->(match Raster2.Texture.create~color_space:Raster2.Texture.Linear~hard_capacity:(Bytes.length(Raster2.Surface.bytes surface))surface with Ok texture->Ok(Some{Raster2.Triangle.texture;filter=Raster2.Texture.Nearest;address_u=Raster2.Texture.Clamp;address_v=Raster2.Texture.Clamp})|Error _->error"Ogpu_raster2.render"Invalid_argument"fragment texture is invalid")|_->error"Ogpu_raster2.render"Invalid_argument"fragment texture is absent"in match texture with Error _ as e->e|Ok texture->let textured=Option.is_some texture in let indices=match d.index with
                    |None->Array.init d.vertex_count(fun i->d.vertex_start+i)
                    |Some(kind,id,offset,count)->match find id with Some(Buffer bytes)->let stride=match kind with Uint16->2|Uint32->4 in Array.init count(fun i->if stride=2 then Bytes.get_uint16_le bytes(Int64.to_int offset+i*stride)else Int32.to_int(Bytes.get_int32_le bytes(Int64.to_int offset+i*stride)))|_->[||]in
                    let triangle a b c=Raster2.Triangle.draw~color~depth:(Option.map(fun _->depth)descriptor.depth)~depth_state~blend:Raster2.Composite.Copy~cull:Cull_none~clip~texture(vertex textured vertices binding.offset a)(vertex textured vertices binding.offset b)(vertex textured vertices binding.offset c)in
                    (match d.primitive with Triangle_list->for i=0 to Array.length indices/3-1 do triangle indices.(i*3)indices.(i*3+1)indices.(i*3+2)done|Triangle_strip->for i=0 to Array.length indices-3 do if i land 1=0 then triangle indices.(i)indices.(i+1)indices.(i+2)else triangle indices.(i+1)indices.(i)indices.(i+2)done);Ok())
                  |_->error"Ogpu_raster2.render"Invalid_argument"vertex buffer is absent"in
              let rec all=function []->Ok()|x::xs->match draw x with Error _ as e->e|Ok()->all xs in all draws
          |_->error"Ogpu_raster2.render"Invalid_argument"color attachment is absent"in
        let transfer operations =
          let snapshots=List.filter_map(fun(_,token)->match Hashtbl.find_opt control.objects token with Some(Buffer bytes)->Some(token,Bytes.copy bytes)|Some(Texture({color;_},_))->Some(token,Bytes.copy(Raster2.Surface.bytes color))|None->None)resources in
          let restore()=List.iter(fun(token,copy)->match Hashtbl.find_opt control.objects token with Some(Buffer bytes)->Bytes.blit copy 0 bytes 0(Bytes.length copy)|Some(Texture({color;_},_))->Bytes.blit copy 0(Raster2.Surface.bytes color)0(Bytes.length copy)|None->())snapshots in
          let buffer id=match find id with Some(Buffer bytes)->Some bytes|_->None and texture id=match find id with Some(Texture({color;_},_))->Some color|_->None in
          let copy_rows ~src ~src_offset ~src_row ~dst ~dst_offset ~dst_row width height=for row=0 to height-1 do Bytes.blit src(src_offset+row*src_row)dst(dst_offset+row*dst_row)width done in
          let execute=function
            |Ogpu.Transfer_pass.Copy_buffer(src,so,dst,do_,length)->(match buffer src,buffer dst with Some a,Some b when valid_range a so(Int64.to_int length)&&valid_range b do_(Int64.to_int length)->Bytes.blit a(Int64.to_int so)b(Int64.to_int do_)(Int64.to_int length);Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"buffer copy range")
            |Fill_buffer(id,offset,length,value)->(match buffer id with Some bytes when valid_range bytes offset(Int64.to_int length)->Bytes.fill bytes(Int64.to_int offset)(Int64.to_int length)(Char.chr value);Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"buffer fill range")
            |Buffer_to_texture(src,offset,row,_,dst,mip,origin,extent)->(match buffer src,texture dst with Some bytes,Some surface when mip=0&&origin.z=0&&extent.depth=1&&origin.x>=0&&origin.y>=0&&origin.x+extent.width<=Raster2.Surface.width surface&&origin.y+extent.height<=Raster2.Surface.height surface&&valid_range bytes offset(Int64.to_int row*extent.height)->copy_rows~src:bytes~src_offset:(Int64.to_int offset)~src_row:(Int64.to_int row)~dst:(Raster2.Surface.bytes surface)~dst_offset:(origin.y*Raster2.Surface.pitch surface+origin.x*4)~dst_row:(Raster2.Surface.pitch surface)(extent.width*4)extent.height;Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"buffer texture upload")
            |Texture_to_buffer(src,mip,origin,extent,dst,offset,row,_)->(match texture src,buffer dst with Some surface,Some bytes when mip=0&&origin.z=0&&extent.depth=1&&origin.x>=0&&origin.y>=0&&origin.x+extent.width<=Raster2.Surface.width surface&&origin.y+extent.height<=Raster2.Surface.height surface&&valid_range bytes offset(Int64.to_int row*extent.height)->copy_rows~src:(Raster2.Surface.bytes surface)~src_offset:(origin.y*Raster2.Surface.pitch surface+origin.x*4)~src_row:(Raster2.Surface.pitch surface)~dst:bytes~dst_offset:(Int64.to_int offset)~dst_row:(Int64.to_int row)(extent.width*4)extent.height;Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"texture buffer download")
            |Copy_texture(src,sm,so,dst,dm,do_,extent)->(match texture src,texture dst with Some a,Some b when sm=0&&dm=0&&so.z=0&&do_.z=0&&extent.depth=1&&so.x>=0&&so.y>=0&&do_.x>=0&&do_.y>=0&&so.x+extent.width<=Raster2.Surface.width a&&so.y+extent.height<=Raster2.Surface.height a&&do_.x+extent.width<=Raster2.Surface.width b&&do_.y+extent.height<=Raster2.Surface.height b->let temporary=Bytes.create(extent.width*extent.height*4)in copy_rows~src:(Raster2.Surface.bytes a)~src_offset:(so.y*Raster2.Surface.pitch a+so.x*4)~src_row:(Raster2.Surface.pitch a)~dst:temporary~dst_offset:0~dst_row:(extent.width*4)(extent.width*4)extent.height;copy_rows~src:temporary~src_offset:0~src_row:(extent.width*4)~dst:(Raster2.Surface.bytes b)~dst_offset:(do_.y*Raster2.Surface.pitch b+do_.x*4)~dst_row:(Raster2.Surface.pitch b)(extent.width*4)extent.height;Ok()|_->error"Ogpu_raster2.transfer"Invalid_argument"texture copy range")in
          let rec loop index=if index=Array.length operations then Ok()else match execute operations.(index)with Ok()->loop(index+1)|Error _ as failure->restore();failure in loop 0 in
        let result=match command with Ogpu.Backend.Render submission->render submission|Compute _->error"Ogpu_raster2.compute"Unsupported"software compute is unsupported"|Transfer operations->transfer operations in
        match result with Error _ as e->e|Ok()->control.epoch<-Int64.succ control.epoch;record control("submit:"^Int64.to_string control.epoch);Ok{Ogpu.Backend.epoch=control.epoch}in
      Ok{Ogpu.Backend.queue_token;submit;complete_through=(fun epoch->if epoch<=control.complete||epoch>control.epoch then error"Ogpu_raster2.complete"Invalid_argument"epoch is invalid"else(control.complete<-epoch;Ok()));destroy_queue=(fun()->control.queues<-control.queues-1;Ok())}
    in
    Ok{Ogpu.Backend.device_token;device_handle;capabilities=Ogpu.Capabilities.minimum_m1;
      create_buffer=(fun d->resource"buffer"(Buffer(Bytes.make(Int64.to_int d.Ogpu.Types.size)'\000')));
      create_texture=(fun d->match Raster2.Surface.create~width:d.width~height:d.height(),Raster2.Depth_stencil.create~width:d.width~height:d.height()with Ok color,Ok depth->resource"texture"(Texture({color;depth},d))|_->error"Ogpu_raster2.texture"Invalid_argument"texture extent is invalid");
      create_pipeline=(fun _->let pipeline_token=next control in control.pipelines<-control.pipelines+1;Ok{Ogpu.Backend.pipeline_token;destroy_pipeline=(fun()->control.pipelines<-control.pipelines-1;Ok())});create_queue;
      create_surface=(fun _->let surface_token=next control and frame=ref 0L in control.surfaces<-control.surfaces+1;Ok{Ogpu.Backend.surface_token;configure=(fun _->Ok());acquire=(fun()->if control.lost then Ok`Device_lost else(frame:=Int64.succ!frame;Ok(`Acquired{Ogpu.Backend.frame_token= !frame})));present=(fun _->Ok());discard=(fun _->Ok());destroy_surface=(fun()->control.surfaces<-control.surfaces-1;Ok())});
      destroy_device=(fun()->Ogpu.Handle.destroy_device device_handle;Ok())}
  in {Ogpu.Backend.create_device},control
let inject_device_loss control=control.lost<-true
let trace control=List.of_seq(Queue.to_seq control.log)
let trace_stats control=Queue.length control.log,control.dropped_log_entries
let live_counts control=control.buffers,control.textures,control.pipelines,control.queues,control.surfaces
