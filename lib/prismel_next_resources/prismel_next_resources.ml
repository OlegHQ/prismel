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
    mutable rgba:bytes;mutable dead:bool}
  let identity x=x.identity and generation x=x.generation and destroyed x=x.dead
  let live op x f=main op(fun()->if x.dead then error op Destroyed"image is destroyed"else f())
  let create ~width ~height ~rgba=main"Image.create"(fun()->
    if not(valid_storage width height rgba)then error"Image.create"Invalid_argument"invalid RGBA extent or storage"
    else Ok{identity=fresh_identity();generation=1;width;height;rgba=Bytes.copy rgba;dead=false})
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
  let replace x ~width ~height ~rgba=live"Image.replace"x(fun()->
    if not(valid_storage width height rgba)then error"Image.replace"Invalid_argument"invalid RGBA replacement"
    else(x.width<-width;x.height<-height;x.rgba<-Bytes.copy rgba;x.generation<-x.generation+1;Ok()))
  let rec reload_file x path=live"Image.reload_file"x(fun()->match load_file path with
    |Error _ as failure->failure
    |Ok replacement->let result=replace x~width:replacement.width~height:replacement.height~rgba:replacement.rgba in
      ignore(destroy replacement);result)
  and destroy x=main"Image.destroy"(fun()->if x.dead then Ok()else(x.dead<-true;x.rgba<-Bytes.empty;Ok()))
end

module Png=struct
  let add_u32 b x=for shift=3 downto 0 do Buffer.add_char b(Char.chr((x lsr(shift*8))land 255))done
  let crc bytes=let crc=ref 0xffffffffl in Bytes.iter(fun c->crc:=Int32.logxor !crc(Int32.of_int(Char.code c));for _=1 to 8 do crc:=Int32.logxor(Int32.shift_right_logical !crc 1)(if Int32.logand !crc 1l<>0l then 0xedb88320l else 0l)done)bytes;Int32.logxor !crc 0xffffffffl
  let adler bytes=let a=ref 1 and b=ref 0 in Bytes.iter(fun c->a:=(!a+Char.code c)mod 65521;b:=(!b+ !a)mod 65521)bytes;(!b lsl 16)lor !a
  let chunk out kind data=add_u32 out(Bytes.length data);Buffer.add_string out kind;Buffer.add_bytes out data;let all=Bytes.of_string(kind^Bytes.to_string data)in add_u32 out(Int32.to_int(crc all))
  let encode ~width ~height rgba=let raw=Bytes.create(height*(1+width*4))in for y=0 to height-1 do Bytes.blit rgba(y*width*4)raw(y*(1+width*4)+1)(width*4)done;let z=Buffer.create(Bytes.length raw+32)in Buffer.add_string z"\x78\x01";let p=ref 0 in while !p<Bytes.length raw do let n=min 65535(Bytes.length raw- !p)in Buffer.add_char z(Char.chr(if !p+n=Bytes.length raw then 1 else 0));Buffer.add_char z(Char.chr(n land 255));Buffer.add_char z(Char.chr(n lsr 8));let q=(lnot n)land 65535 in Buffer.add_char z(Char.chr(q land 255));Buffer.add_char z(Char.chr(q lsr 8));Buffer.add_subbytes z raw !p n;p:=!p+n done;add_u32 z(adler raw);let out=Buffer.create(Buffer.length z+64)in Buffer.add_string out"\x89PNG\r\n\x1a\n";let ihdr=Buffer.create 13 in add_u32 ihdr width;add_u32 ihdr height;Buffer.add_string ihdr"\x08\x06\x00\x00\x00";chunk out"IHDR"(Bytes.of_string(Buffer.contents ihdr));chunk out"IDAT"(Bytes.of_string(Buffer.contents z));chunk out"IEND"Bytes.empty;Bytes.of_string(Buffer.contents out)
end

module Canvas=struct
  type t={mutable generation:int;mutable surface:Raster2.Surface.t;mutable dead:bool}
  let generation x=x.generation and destroyed x=x.dead
  let live op x f=main op(fun()->if x.dead then error op Destroyed"canvas is destroyed"else f())
  let surface operation width height=match Raster2.Surface.create~width~height()with Ok x->Ok x|Error _->error operation Invalid_argument"invalid canvas extent"
  let create ~width ~height=main"Canvas.create"(fun()->Result.map(fun surface->{generation=1;surface;dead=false})(surface"Canvas.create"width height))
  let size x=live"Canvas.size"x(fun()->Ok(Raster2.Surface.width x.surface,Raster2.Surface.height x.surface))
  let clear x color=live"Canvas.clear"x(fun()->Raster2.Surface.clear x.surface color;Ok())
  let set_pixel x ~x:px ~y color=live"Canvas.set_pixel"x(fun()->match Raster2.Surface.set_rgba x.surface~x:px~y color with Ok()->Ok()|Error _->error"Canvas.set_pixel"Invalid_argument"pixel is out of bounds")
  let draw_image x image ~x:px ~y=live"Canvas.draw_image"x(fun()->match Image.size image,Image.pixels image with
    |Ok(w,h),Ok bytes->let src=Result.get_ok(Raster2.Surface.of_bytes~width:w~height:h~pitch:(w*4) bytes)in(match Raster2.Composite.blit~src~src_rect:{x=0;y=0;width=w;height=h}~dst:x.surface~dst_x:px~dst_y:y~blend:Raster2.Composite.Copy with Ok()->Ok()|Error _->error"Canvas.draw_image"Invalid_argument"invalid blit")
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

module Assets=struct
  type t={mutable hooks:(unit->(unit,error)result)list;mutable dead:bool}
  let create()={hooks=[];dead=false}
  let borrow x ~destroy value=main"Assets.borrow"(fun()->if x.dead then error"Assets.borrow"Destroyed"assets are destroyed"else(x.hooks<-destroy::x.hooks;Ok value))
  let count x=List.length x.hooks
  let destroy x=main"Assets.destroy"(fun()->if x.dead then Ok()else let first=ref None in List.iter(fun hook->match hook()with Ok()->()|Error e->if !first=None then first:=Some e)x.hooks;x.hooks<-[];x.dead<-true;match!first with None->Ok()|Some e->Error e)
end
