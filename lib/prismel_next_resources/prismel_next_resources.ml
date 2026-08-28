type error_kind = Wrong_domain | Destroyed | Invalid_argument | Decode | Io
type error={operation:string;kind:error_kind;message:string}
let pp_error f e=Format.fprintf f "%s: %s" e.operation e.message
let error operation kind message=Error{operation;kind;message}
let main operation callback=
  if not(Sdl3.Thread.is_initial_domain())||not(Sdl3.Thread.is_sdl_main_thread())then
    error operation Wrong_domain "resource operation requires the initial SDL domain"
  else callback()
let next=Atomic.make 1
let fresh_identity()=Atomic.fetch_and_add next 1
let valid_storage width height bytes=
  width>0&&height>0&&width<=max_int/4&&height<=max_int/(width*4)
  &&Bytes.length bytes=width*height*4

module Image=struct
  type t={identity:int;mutable generation:int;mutable width:int;mutable height:int;
    mutable rgba:bytes;mutable spare:bytes option;mutable leases:(bytes*int)list;
    mutable dead:bool}
  type lease={owner:t;bytes:bytes;mutable released:bool}
  let identity x=x.identity and generation x=x.generation and destroyed x=x.dead
  let live op x f=main op(fun()->if x.dead then error op Destroyed"image is destroyed"else f())
  let create ~width ~height ~rgba=main"Image.create"(fun()->
    if not(valid_storage width height rgba)then error"Image.create"Invalid_argument"invalid RGBA extent or storage"
    else Ok{identity=fresh_identity();generation=1;width;height;rgba=Bytes.copy rgba;
      spare=None;leases=[];dead=false})
  let of_surface operation surface=
    match Sdl3.Surface.copy_rgba surface with
    |Error e->error operation Decode(Format.asprintf"%a"Sdl3.pp_error e)
    |Ok snapshot->create~width:snapshot.width~height:snapshot.height~rgba:snapshot.pixels
  let load_file path=main"Image.load_file"(fun()->match Sdl3_image.load_file path with
    |Error e->error"Image.load_file"Decode(Format.asprintf"%a"Sdl3_image.pp_error e)
    |Ok surface->Fun.protect~finally:(fun()->ignore(Sdl3.Surface.destroy surface))
      (fun()->of_surface"Image.load_file"surface))
  let load_bytes ?kind bytes=main"Image.load_bytes"(fun()->match Sdl3_image.load_bytes ?kind (Bytes.copy bytes)with
    |Error e->error"Image.load_bytes"Decode(Format.asprintf"%a"Sdl3_image.pp_error e)
    |Ok surface->Fun.protect~finally:(fun()->ignore(Sdl3.Surface.destroy surface))
      (fun()->of_surface"Image.load_bytes"surface))
  let size x=live"Image.size"x(fun()->Ok(x.width,x.height))
  let pixels x=live"Image.pixels"x(fun()->Ok(Bytes.copy x.rgba))
  let snapshot x=live"Image.snapshot"x(fun()->
    Ok(x.width,x.height,x.generation,Bytes.copy x.rgba))
  let leased x bytes=List.memq bytes(List.map fst x.leases)
  let writable x length=
    if Bytes.length x.rgba=length&&not(leased x x.rgba)then Ok x.rgba else
    match x.spare with
    |Some bytes when Bytes.length bytes=length&&not(leased x bytes)->x.spare<-None;Ok bytes
    |_->if List.length x.leases<2 then Ok(Bytes.create length)
        else error"Image.borrow_snapshot"Invalid_argument"both bounded image snapshot buffers are leased"
  let install x bytes=
    let old=x.rgba in x.rgba<-bytes;
    if old!=bytes&&not(leased x old)then x.spare<-Some old
  let borrow_snapshot x=live"Image.borrow_snapshot"x(fun()->
    let count=Option.value(List.assq_opt x.rgba x.leases)~default:0 in
    x.leases<-(x.rgba,count+1)::List.remove_assq x.rgba x.leases;
    Ok(x.width,x.height,x.generation,x.rgba,{owner=x;bytes=x.rgba;released=false}))
  let release_snapshot lease=if not lease.released then begin
    lease.released<-true;
    let x=lease.owner and count=Option.value(List.assq_opt lease.bytes lease.owner.leases)~default:0 in
    x.leases<-List.remove_assq lease.bytes x.leases;
    if count>1 then x.leases<-(lease.bytes,count-1)::x.leases
    else if lease.bytes!=x.rgba then x.spare<-Some lease.bytes
  end
  let replace x ~width ~height ~rgba=live"Image.replace"x(fun()->
    if not(valid_storage width height rgba)then error"Image.replace"Invalid_argument"invalid RGBA replacement"
    else match writable x(Bytes.length rgba)with Error _ as e->e|Ok bytes->
      Bytes.blit rgba 0 bytes 0(Bytes.length rgba);install x bytes;
      x.width<-width;x.height<-height;x.generation<-x.generation+1;Ok())
  let replace_owned target source=main"Image.replace_owned"(fun()->
    if target.dead then error"Image.replace_owned"Destroyed"target image is destroyed"
    else if source.dead then error"Image.replace_owned"Destroyed"source image is destroyed"
    else if target==source then error"Image.replace_owned"Invalid_argument"source and target images must differ"
    else if leased source source.rgba then
      error"Image.replace_owned"Invalid_argument"source image storage is leased"
    else begin
      (* Both values and the complete replacement have been validated before
         mutation.  Moving the byte storage makes replacement transactional
         without another full-frame copy. *)
      target.width<-source.width;
      target.height<-source.height;
      install target source.rgba;
      target.generation<-target.generation+1;
      source.rgba<-Bytes.empty;
      source.dead<-true;
      Ok()
    end)
  let rec reload_file x path=live"Image.reload_file"x(fun()->match load_file path with
    |Error _ as failure->failure
    |Ok replacement->let result=replace x~width:replacement.width~height:replacement.height~rgba:replacement.rgba in
      ignore(destroy replacement);result)
  and destroy x=main"Image.destroy"(fun()->if x.dead then Ok()else(x.dead<-true;x.rgba<-Bytes.empty;x.spare<-None;Ok()))
  module Private=struct
    type nonrec lease=lease
    let borrow_snapshot=borrow_snapshot
    let release_snapshot=release_snapshot
  end
end

module Png=struct
  let add_u32 b x=for shift=3 downto 0 do Buffer.add_char b(Char.chr((x lsr(shift*8))land 255))done
  let crc bytes=let crc=ref 0xffffffffl in Bytes.iter(fun c->crc:=Int32.logxor !crc(Int32.of_int(Char.code c));for _=1 to 8 do crc:=Int32.logxor(Int32.shift_right_logical !crc 1)(if Int32.logand !crc 1l<>0l then 0xedb88320l else 0l)done)bytes;Int32.logxor !crc 0xffffffffl
  let adler bytes=let a=ref 1 and b=ref 0 in Bytes.iter(fun c->a:=(!a+Char.code c)mod 65521;b:=(!b+ !a)mod 65521)bytes;(!b lsl 16)lor !a
  let chunk out kind data=add_u32 out(Bytes.length data);Buffer.add_string out kind;Buffer.add_bytes out data;let all=Bytes.of_string(kind^Bytes.to_string data)in add_u32 out(Int32.to_int(crc all))
  let encode ~width ~height rgba=let raw=Bytes.create(height*(1+width*4))in for y=0 to height-1 do Bytes.blit rgba(y*width*4)raw(y*(1+width*4)+1)(width*4)done;let z=Buffer.create(Bytes.length raw+32)in Buffer.add_string z"\x78\x01";let p=ref 0 in while !p<Bytes.length raw do let n=min 65535(Bytes.length raw- !p)in Buffer.add_char z(Char.chr(if !p+n=Bytes.length raw then 1 else 0));Buffer.add_char z(Char.chr(n land 255));Buffer.add_char z(Char.chr(n lsr 8));let q=(lnot n)land 65535 in Buffer.add_char z(Char.chr(q land 255));Buffer.add_char z(Char.chr(q lsr 8));Buffer.add_subbytes z raw !p n;p:=!p+n done;add_u32 z(adler raw);let out=Buffer.create(Buffer.length z+64)in Buffer.add_string out"\x89PNG\r\n\x1a\n";let ihdr=Buffer.create 13 in add_u32 ihdr width;add_u32 ihdr height;Buffer.add_string ihdr"\x08\x06\x00\x00\x00";chunk out"IHDR"(Bytes.of_string(Buffer.contents ihdr));chunk out"IDAT"(Bytes.of_string(Buffer.contents z));chunk out"IEND"Bytes.empty;Bytes.of_string(Buffer.contents out)
end

module Canvas=struct
  type t={mutable generation:int;mutable surface:Raster2.Surface.t;
    workspace:Raster2.Consumer.Workspace.t;mutable dead:bool}
  let generation x=x.generation and destroyed x=x.dead
  let live op x f=main op(fun()->if x.dead then error op Destroyed"canvas is destroyed"else f())
  let surface operation width height=match Raster2.Surface.create~width~height()with Ok x->Ok x|Error _->error operation Invalid_argument"invalid canvas extent"
  let create ~width ~height=main"Canvas.create"(fun()->Result.map(fun surface->{generation=1;surface;workspace=Raster2.Consumer.Workspace.create();dead=false})(surface"Canvas.create"width height))
  let size x=live"Canvas.size"x(fun()->Ok(Raster2.Surface.width x.surface,Raster2.Surface.height x.surface))
  let clear x color=live"Canvas.clear"x(fun()->Raster2.Surface.clear x.surface color;x.generation<-x.generation+1;Ok())
  let set_pixel x ~x:px ~y color=live"Canvas.set_pixel"x(fun()->match Raster2.Surface.set_rgba x.surface~x:px~y color with
    |Ok()->x.generation<-x.generation+1;Ok()
    |Error _->error"Canvas.set_pixel"Invalid_argument"pixel is out of bounds")
  let replace_pixels x pixels=live"Canvas.replace_pixels"x(fun()->
    let expected=Raster2.Surface.height x.surface*Raster2.Surface.pitch x.surface in
    if Bytes.length pixels<>expected then error"Canvas.replace_pixels"Invalid_argument"pixel storage length does not match canvas"
    else(Bytes.blit pixels 0(Raster2.Surface.bytes x.surface)0 expected;x.generation<-x.generation+1;Ok()))
  let copy_to_image x image=main"Canvas.copy_to_image"(fun()->
    if x.dead then error"Canvas.copy_to_image"Destroyed"canvas is destroyed"
    else if image.Image.dead then error"Canvas.copy_to_image"Destroyed"image is destroyed"
    else
      let width=Raster2.Surface.width x.surface
      and height=Raster2.Surface.height x.surface
      and source=Raster2.Surface.bytes x.surface in
      match Image.writable image(Bytes.length source)with Error _ as e->e|Ok bytes->
      Bytes.blit source 0 bytes 0(Bytes.length source);Image.install image bytes;
      image.width<-width;image.height<-height;
      image.generation<-image.generation+1;Ok())
  let snapshot x=live"Canvas.snapshot"x(fun()->
    Ok(Raster2.Surface.width x.surface,Raster2.Surface.height x.surface,
      x.generation,Bytes.copy(Raster2.Surface.bytes x.surface)))
  let render_ir x ~lookup ir=live"Canvas.render_ir"x(fun()->
    match Raster2.Consumer.execute~workspace:x.workspace~lookup~target:x.surface ir with
    |Error _->error"Canvas.render_ir"Invalid_argument"invalid render command stream"
    |Ok()->x.generation<-x.generation+1;Ok())
  let draw_image x image ~x:px ~y=live"Canvas.draw_image"x(fun()->match Image.size image,Image.pixels image with
    |Ok(w,h),Ok bytes->let src=Result.get_ok(Raster2.Surface.of_bytes~width:w~height:h~pitch:(w*4) bytes)in(match Raster2.Composite.blit~src~src_rect:{x=0;y=0;width=w;height=h}~dst:x.surface~dst_x:px~dst_y:y~blend:Raster2.Composite.Copy with Ok()->x.generation<-x.generation+1;Ok()|Error _->error"Canvas.draw_image"Invalid_argument"invalid blit")
    |Error e,_|_,Error e->Error e)
  let resize x ~width ~height=live"Canvas.resize"x(fun()->match surface"Canvas.resize"width height with Error _ as e->e|Ok s->x.surface<-s;x.generation<-x.generation+1;Ok())
  let capture x=live"Canvas.capture"x(fun()->Image.create~width:(Raster2.Surface.width x.surface)~height:(Raster2.Surface.height x.surface)~rgba:(Raster2.Surface.bytes x.surface))
  let save_png x path=live"Canvas.save_png"x(fun()->try let bytes=Png.encode~width:(Raster2.Surface.width x.surface)~height:(Raster2.Surface.height x.surface)(Raster2.Surface.bytes x.surface)in let out=open_out_bin path in Fun.protect~finally:(fun()->close_out_noerr out)(fun()->output_bytes out bytes);Ok()with Sys_error m->error"Canvas.save_png"Io m)
  let destroy x=main"Canvas.destroy"(fun()->if x.dead then Ok()else(x.dead<-true;Ok()))
end

module Text=struct
  type t={generation:int;width:int;height:int;mutable rgba:bytes;mutable dead:bool}
  let generation x=x.generation and destroyed x=x.dead
  let live op x f=main op(fun()->if x.dead then error op Destroyed"text snapshot is destroyed"else f())
  let owned width height rgba={generation=fresh_identity();width;height;rgba=Bytes.copy rgba;dead=false}
  let size x=live"Text.size"x(fun()->Ok(x.width,x.height))
  let pixels x=live"Text.pixels"x(fun()->Ok(Bytes.copy x.rgba))
  let destroy x=main"Text.destroy"(fun()->if x.dead then Ok()else(x.dead<-true;x.rgba<-Bytes.empty;Ok()))
end

module Font=struct
  type style=Normal|Bold|Italic|Underline|Strikethrough
  type hinting=Normal_hinting|Light_hinting|Mono_hinting|None_hinting|Light_subpixel_hinting
  type glyph_metrics={min_x:int;max_x:int;min_y:int;max_y:int;advance:int}
  type cache_entry={key:string;text:Text.t option}
  type t={raw:Sdl3_ttf.Font.t;base_size:float;mutable generation:int;
    mutable density:int;mutable caches:(int*cache_entry list)list;mutable dead:bool}
  let users=ref 0
  let generation x=x.generation and destroyed x=x.dead
  let live op x f=main op(fun()->if x.dead then error op Destroyed"font is destroyed"else f())
  let ttf op result=match result with Ok x->Ok x|Error e->error op Decode(Format.asprintf"%a"Sdl3_ttf.pp_error e)
  let ensure_init op=match Sdl3_ttf.Init.initialized()with
    |Error e->error op Decode(Format.asprintf"%a"Sdl3_ttf.pp_error e)
    |Ok true->Ok()|Ok false->ttf op(Sdl3_ttf.Init.init())
  let open_file ~path ~size=main"Font.open_file"(fun()->
    if not(Float.is_finite size)||size<=0. then error"Font.open_file"Invalid_argument"font size must be finite and positive"
    else match ensure_init"Font.open_file"with Error _ as e->e|Ok()->match ttf"Font.open_file"(Sdl3_ttf.Font.open_file~path~size)with
      |Error _ as e->e|Ok raw->incr users;Ok{raw;base_size=size;generation=1;density=1;caches=[];dead=false})
  let open_system ~size=main"Font.open_system"(fun()->match ttf"Font.open_system"(Sdl3_ttf.Font.system_path())with Error _ as e->e|Ok path->open_file~path~size)
  let destroy_entries entries=List.iter(fun e->Option.iter(fun text->ignore(Text.destroy text))e.text)entries
  let invalidate x=List.iter(fun(_,entries)->destroy_entries entries)x.caches;x.caches<-[];x.generation<-x.generation+1
  let mutate op x call=live op x(fun()->match ttf op(call())with Error _ as e->e|Ok()->invalidate x;Ok())
  let style=function Normal->Sdl3_ttf.Font.Normal|Bold->Bold|Italic->Italic|Underline->Underline|Strikethrough->Strikethrough
  let hinting=function Normal_hinting->Sdl3_ttf.Font.Normal_hinting|Light_hinting->Light_hinting|Mono_hinting->Mono_hinting|None_hinting->None_hinting|Light_subpixel_hinting->Light_subpixel_hinting
  let set_style x values=mutate"Font.set_style"x(fun()->Sdl3_ttf.Font.set_style x.raw(List.map style values))
  let set_outline x value=mutate"Font.set_outline"x(fun()->Sdl3_ttf.Font.set_outline x.raw value)
  let set_hinting x value=mutate"Font.set_hinting"x(fun()->Sdl3_ttf.Font.set_hinting x.raw(hinting value))
  let set_kerning x value=mutate"Font.set_kerning"x(fun()->Sdl3_ttf.Font.set_kerning x.raw value)
  let glyph_metrics x glyph=live"Font.glyph_metrics"x(fun()->match ttf"Font.glyph_metrics"(Sdl3_ttf.Font.glyph_metrics x.raw glyph)with Error _ as e->e|Ok m->Ok{min_x=m.min_x;max_x=m.max_x;min_y=m.min_y;max_y=m.max_y;advance=m.advance})
  let valid_utf8 text=
    let n=String.length text in let rec loop i=if i=n then true else let c=Char.code text.[i]in
      let continuation j= j<n && Char.code text.[j]land 0xc0=0x80 in
      if c<0x80 then loop(i+1)else if c>=0xc2&&c<=0xdf&&continuation(i+1)then loop(i+2)
      else if c>=0xe0&&c<=0xef&&continuation(i+1)&&continuation(i+2)then let c1=Char.code text.[i+1]in if(c=0xe0&&c1<0xa0)||(c=0xed&&c1>=0xa0)then false else loop(i+3)
      else if c>=0xf0&&c<=0xf4&&continuation(i+1)&&continuation(i+2)&&continuation(i+3)then let c1=Char.code text.[i+1]in if(c=0xf0&&c1<0x90)||(c=0xf4&&c1>=0x90)then false else loop(i+4)else false in loop 0
  let set_density x density=
    if density=x.density then Ok()else match ttf"Font.render"(Sdl3_ttf.Font.set_size_dpi x.raw~size:x.base_size~horizontal:(72*density)~vertical:(72*density))with Error _ as e->e|Ok()->x.density<-density;Ok()
  let render x ?wrap_width ~density ~color text=live"Font.render"x(fun()->
    if density<=0||density>16 then error"Font.render"Invalid_argument"density must be in 1..16"
    else if not(valid_utf8 text)then error"Font.render"Invalid_argument"text is not strict UTF-8"
    else match wrap_width with Some width when width<=0->error"Font.render"Invalid_argument"wrap width must be positive"|_->
      match set_density x density with Error _ as e->e|Ok()->
      let rendered=match wrap_width with None->Sdl3_ttf.Font.render_blended x.raw~color text|Some width->Sdl3_ttf.Font.render_blended_wrapped x.raw~color~wrap_width:(width*density) text in
      match ttf"Font.render"rendered with Error _ as e->e|Ok None->Ok None|Ok(Some surface)->Fun.protect~finally:(fun()->ignore(Sdl3.Surface.destroy surface))(fun()->match Sdl3.Surface.copy_rgba surface with Error e->error"Font.render"Decode(Format.asprintf"%a"Sdl3.pp_error e)|Ok s->Ok(Some(Text.owned s.width s.height s.pixels))))
  let cached_text=render
  let cache_key x density wrap color text=Marshal.to_string(x.generation,density,wrap,color,text)[]
  let render_cached x ~renderer ?wrap_width ~density ~color text=live"Font.render_cached"x(fun()->
    let key=cache_key x density wrap_width color text in let entries=Option.value(List.assoc_opt renderer x.caches)~default:[]in
    match List.find_opt(fun e->e.key=key)entries with Some e->Ok e.text|None->match render x ?wrap_width~density~color text with Error _ as e->e|Ok text_snapshot->
      let entries={key;text=text_snapshot}::entries in let kept,evicted=if List.length entries<=256 then entries,[]else let rec split i acc=function []->List.rev acc,[]|rest when i=256->List.rev acc,rest|v::vs->split(i+1)(v::acc)vs in split 0[]entries in destroy_entries evicted;x.caches<-(renderer,kept)::List.remove_assoc renderer x.caches;Ok text_snapshot)
  let cache_entries x ~renderer=List.assoc_opt renderer x.caches|>Option.fold~none:0~some:List.length
  let release_renderer x ~renderer=live"Font.release_renderer"x(fun()->let entries=Option.value(List.assoc_opt renderer x.caches)~default:[]in destroy_entries entries;x.caches<-List.remove_assoc renderer x.caches;Ok())
  let destroy x=main"Font.destroy"(fun()->if x.dead then Ok()else(destroy_entries(List.concat_map snd x.caches);x.caches<-[];match ttf"Font.destroy"(Sdl3_ttf.Font.destroy x.raw)with Error _ as e->e|Ok()->x.dead<-true;decr users;if!users=0 then ignore(Sdl3_ttf.Init.quit());Ok()))
end

module Audio=struct
  type intent=Master_volume of float|Stop_all
    |Sample_play of{asset:string;channel:int;loops:int;volume:float}
    |Sample_stop of int|Sample_pause of int|Sample_resume of int
    |Music_play of{asset:string;loops:int;fade_ms:int}|Music_volume of float
    |Music_pause|Music_resume|Music_stop of int|Asset_remove of string
  type generated={mixed_bytes:int;pcm_f32:bytes}
  type t={mixer:Sdl3_mixer.Mixer.t;channels:Sdl3_mixer.Channels.t;
    music:Sdl3_mixer.Music.t;intents:intent Queue.t;mutable dropped:int;
    mutable master:float;mutable music_volume:float;mutable dead:bool}
  and sample={owner:t;identity:string;mutable generation:int;
    mutable raw:Sdl3_mixer.Audio.t;mutable encoded:bytes;mutable dead:bool}
  let mix_error op e=error op Decode(Format.asprintf"%a"Sdl3_mixer.pp_error e)
  let result op=function Ok x->Ok x|Error e->mix_error op e
  let live op x f=main op(fun()->if x.dead then error op Destroyed"audio owner is destroyed"else f())
  let sample_live op x f=live op x.owner(fun()->if x.dead then error op Destroyed"audio sample is destroyed"else f())
  let enqueue x intent=if Queue.length x.intents=256 then(x.dropped<-x.dropped+1;ignore(Queue.take x.intents));Queue.add intent x.intents
  let create_memory ~sample_rate ~channels ~max_channels=main"Audio.create_memory"(fun()->
    match result"Audio.create_memory"(Sdl3_mixer.Init.init())with Error _ as e->e|Ok()->
    match result"Audio.create_memory"(Sdl3_mixer.Mixer.create_memory~sample_rate~channels)with Error _ as e->e|Ok mixer->
    match result"Audio.create_memory"(Sdl3_mixer.Channels.create mixer~count:max_channels)with Error e->ignore(Sdl3_mixer.Mixer.destroy mixer);Error e|Ok channel_bank->
    match result"Audio.create_memory"(Sdl3_mixer.Music.create mixer)with Error e->ignore(Sdl3_mixer.Channels.destroy channel_bank);ignore(Sdl3_mixer.Mixer.destroy mixer);Error e|Ok music->Ok{mixer;channels=channel_bank;music;intents=Queue.create();dropped=0;master=1.;music_volume=1.;dead=false})
  let load_sample_bytes x bytes=live"Audio.load_sample_bytes"x(fun()->match result"Audio.load_sample_bytes"(Sdl3_mixer.Audio.load_bytes x.mixer(Bytes.copy bytes))with Error _ as e->e|Ok raw->Ok{owner=x;identity=Printf.sprintf"sample-%x"(fresh_identity());generation=1;raw;encoded=Bytes.copy bytes;dead=false})
  let reload_sample_bytes x bytes=sample_live"Audio.reload_sample_bytes"x(fun()->match result"Audio.reload_sample_bytes"(Sdl3_mixer.Audio.reload_bytes x.raw(Bytes.copy bytes))with Error _ as e->e|Ok replacement->ignore(Sdl3_mixer.Audio.destroy x.raw);x.raw<-replacement;x.encoded<-Bytes.copy bytes;x.generation<-x.generation+1;Ok())
  let sample_identity(x:sample)=x.identity and sample_generation(x:sample)=x.generation and sample_destroyed(x:sample)=x.dead
  let sample_encoded x=sample_live"Audio.sample_encoded"x(fun()->Ok(Bytes.copy x.encoded))
  let valid_volume x=Float.is_finite x&&x>=0.&&x<=1.
  let play_sample x ?channel ?(loops=0)?(fade_in_ms=0)?(volume=1.) sample=sample_live"Audio.play_sample"sample(fun()->if not(valid_volume volume)then error"Audio.play_sample"Invalid_argument"volume must be in 0..1"else match result"Audio.play_sample"(Sdl3_mixer.Channels.play x.channels ?channel~loops~fade_in_ms sample.raw)with Error _ as e->e|Ok channel->match result"Audio.play_sample"(Sdl3_mixer.Channels.set_volume x.channels channel volume)with Error _ as e->e|Ok()->enqueue x(Sample_play{asset=sample.identity;channel;loops;volume});Ok channel)
  let stop_channel x channel ?(fade_out_ms=0)()=live"Audio.stop_channel"x(fun()->match result"Audio.stop_channel"(Sdl3_mixer.Channels.stop x.channels channel~fade_out_ms())with Error _ as e->e|Ok()->enqueue x(Sample_stop channel);Ok())
  let pause_channel x channel=live"Audio.pause_channel"x(fun()->match result"Audio.pause_channel"(Sdl3_mixer.Channels.pause x.channels channel)with Error _ as e->e|Ok()->enqueue x(Sample_pause channel);Ok())
  let resume_channel x channel=live"Audio.resume_channel"x(fun()->match result"Audio.resume_channel"(Sdl3_mixer.Channels.resume x.channels channel)with Error _ as e->e|Ok()->enqueue x(Sample_resume channel);Ok())
  let play_music x ?(loops=0)?(fade_in_ms=0) sample=sample_live"Audio.play_music"sample(fun()->match result"Audio.play_music"(Sdl3_mixer.Music.set_audio x.music sample.raw)with Error _ as e->e|Ok()->match result"Audio.play_music"(Sdl3_mixer.Music.play x.music~loops~fade_in_ms())with Error _ as e->e|Ok()->enqueue x(Music_play{asset=sample.identity;loops;fade_ms=fade_in_ms});Ok())
  let pause_music x=live"Audio.pause_music"x(fun()->match result"Audio.pause_music"(Sdl3_mixer.Music.pause x.music)with Error _ as e->e|Ok()->enqueue x Music_pause;Ok())
  let resume_music x=live"Audio.resume_music"x(fun()->match result"Audio.resume_music"(Sdl3_mixer.Music.resume x.music)with Error _ as e->e|Ok()->enqueue x Music_resume;Ok())
  let stop_music x ?(fade_out_ms=0)()=live"Audio.stop_music"x(fun()->match result"Audio.stop_music"(Sdl3_mixer.Music.stop x.music~fade_out_ms())with Error _ as e->e|Ok()->enqueue x(Music_stop fade_out_ms);Ok())
  let set_master_volume x volume=live"Audio.set_master_volume"x(fun()->if not(valid_volume volume)then error"Audio.set_master_volume"Invalid_argument"volume must be in 0..1"else match result"Audio.set_master_volume"(Sdl3_mixer.Mixer.set_gain x.mixer volume)with Error _ as e->e|Ok()->x.master<-volume;enqueue x(Master_volume volume);Ok())
  let set_music_volume x volume=live"Audio.set_music_volume"x(fun()->if not(valid_volume volume)then error"Audio.set_music_volume"Invalid_argument"volume must be in 0..1"else match result"Audio.set_music_volume"(Sdl3_mixer.Music.set_volume x.music volume)with Error _ as e->e|Ok()->x.music_volume<-volume;enqueue x(Music_volume volume);Ok())
  let master_volume x=live"Audio.master_volume"x(fun()->Ok x.master)
  let music_volume x=live"Audio.music_volume"x(fun()->Ok x.music_volume)
  let generate x ~frames=live"Audio.generate"x(fun()->match result"Audio.generate"(Sdl3_mixer.Mixer.generate x.mixer~frames)with Error _ as e->e|Ok generated->Ok{mixed_bytes=generated.mixed_bytes;pcm_f32=Bytes.copy generated.pcm_f32})
  let drain_web_intents x=if x.dead then[]else let values=List.of_seq(Queue.to_seq x.intents)in Queue.clear x.intents;values
  let dropped_web_intents x=x.dropped
  let destroy_sample (x:sample)=main"Audio.destroy_sample"(fun()->if x.dead then Ok()else match result"Audio.destroy_sample"(Sdl3_mixer.Audio.destroy x.raw)with Error _ as e->e|Ok()->x.dead<-true;x.encoded<-Bytes.empty;enqueue x.owner(Asset_remove x.identity);Ok())
  let destroy x=main"Audio.destroy"(fun()->if x.dead then Ok()else match result"Audio.destroy"(Sdl3_mixer.Music.destroy x.music)with Error _ as e->e|Ok()->match result"Audio.destroy"(Sdl3_mixer.Channels.destroy x.channels)with Error _ as e->e|Ok()->match result"Audio.destroy"(Sdl3_mixer.Mixer.destroy x.mixer)with Error _ as e->e|Ok()->x.dead<-true;Queue.clear x.intents;ignore(Sdl3_mixer.Init.quit());Ok())
end

module Assets=struct
  type t={mutable hooks:(unit->(unit,error)result)list;mutable dead:bool}
  let create()={hooks=[];dead=false}
  let borrow x ~destroy value=main"Assets.borrow"(fun()->if x.dead then error"Assets.borrow"Destroyed"assets are destroyed"else(x.hooks<-destroy::x.hooks;Ok value))
  let count x=List.length x.hooks
  let destroy x=main"Assets.destroy"(fun()->if x.dead then Ok()else let first=ref None in List.iter(fun hook->match hook()with Ok()->()|Error e->if !first=None then first:=Some e)x.hooks;x.hooks<-[];x.dead<-true;match!first with None->Ok()|Some e->Error e)
end
