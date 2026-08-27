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

module Assets=struct
  type t={mutable hooks:(unit->(unit,error)result)list;mutable dead:bool}
  let create()={hooks=[];dead=false}
  let borrow x ~destroy value=main"Assets.borrow"(fun()->if x.dead then error"Assets.borrow"Destroyed"assets are destroyed"else(x.hooks<-destroy::x.hooks;Ok value))
  let count x=List.length x.hooks
  let destroy x=main"Assets.destroy"(fun()->if x.dead then Ok()else let first=ref None in List.iter(fun hook->match hook()with Ok()->()|Error e->if !first=None then first:=Some e)x.hooks;x.hooks<-[];x.dead<-true;match!first with None->Ok()|Some e->Error e)
end
