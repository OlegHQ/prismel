type render_mode=Solid of Color.t|Shaded of Color.t*Color.t|Blended of Color.t
type style=Normal|Bold|Italic|Underline|Strikethrough
type hinting=Normal_hinting|Light_hinting|Mono_hinting|None_hinting
type alignment=Left|Center|Right
type t={resource:Prismel_next_resources.Font.t;size:int;source:string option;mutable styles:style list;
  mutable hinting:hinting;mutable kerning:bool;mutable generation:int;
  cache:(string,Image.t)Hashtbl.t;order:string Queue.t}
let message operation error=`Msg(Format.asprintf"%s: %a"operation Prismel_next_resources.pp_error error)
let fonts:t list ref=ref[]
let make ?source size=function Ok resource->let value={resource;size;source;styles=[];hinting=Normal_hinting;kerning=true;generation=1;cache=Hashtbl.create 256;order=Queue.create()}in fonts:=value::!fonts;Ok value|Error error->Error(message"Font.load"error)
let load path size=make ~source:path size(Prismel_next_resources.Font.open_file ~path ~size:(float size))
let system_path()=match Sys.getenv_opt"PRISMEL_UI_FONT"with Some path when Sys.file_exists path->Some path|_->List.find_opt Sys.file_exists["/System/Library/Fonts/SFNS.ttf";"/Library/Fonts/Arial.ttf";"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
let system ?(size=16)()=make size(Prismel_next_resources.Font.open_system ~size:(float size))
let load_dpi path size hdpi vdpi=if hdpi<>vdpi then Error(`Msg"Font.load_dpi: non-uniform DPI")else load path size
let resize font size=match font.source with Some path->load path size|None->system ~size()
let rgba=function Solid c|Blended c|Shaded(c,_)->c.Color.r,c.g,c.b,c.a
let image_of_text text=match Prismel_next_resources.Text.size text,Prismel_next_resources.Text.pixels text with
  |Ok(width,height),Ok rgba->begin match Prismel_next_resources.Image.create ~width ~height ~rgba with Ok image->Ok(Image.Private.of_resource image)|Error error->Error(message"Font.image"error)end
  |Error error,_->Error(message"Font.size"error)|_,Error error->Error(message"Font.pixels"error)
let paint ?(density=1) ?wrap font text mode=match Prismel_next_resources.Font.render font.resource ?wrap_width:wrap ~density ~color:(rgba mode)text with
  |Error error->Error(message"Font.render_text"error)|Ok None->Ok(Image.create ~width:1 ~height:1())
  |Ok(Some value)->let result=image_of_text value in ignore(Prismel_next_resources.Text.destroy value);result
let render_text ?(density=1) font text mode=paint ~density font text mode
let key ?wrap ?(align=Left) ?(density=1) text mode=Marshal.to_string(density,text,wrap,align,rgba mode)[]
let cached_text ?wrap ?(align=Left) ?(density=1) font text mode=let key=key ?wrap ~align ~density text mode in match Hashtbl.find_opt font.cache key with Some image->Ok image|None->
  match paint ~density ?wrap font text mode with Error _ as error->error|Ok image->
    if Hashtbl.length font.cache=256 then begin
      let oldest=Queue.pop font.order in
      match Hashtbl.find_opt font.cache oldest with
      |Some old->Image.destroy old;Hashtbl.remove font.cache oldest
      |None->()
    end;
    Hashtbl.replace font.cache key image;Queue.push key font.order;Ok image
let cache_count font=Hashtbl.length font.cache
let clear_cache font=Hashtbl.iter(fun _ image->Image.destroy image)font.cache;Hashtbl.clear font.cache;Queue.clear font.order
let resource_styles styles=List.map(function
  |Normal->Prismel_next_resources.Font.Normal
  |Bold->Prismel_next_resources.Font.Bold
  |Italic->Prismel_next_resources.Font.Italic
  |Underline->Prismel_next_resources.Font.Underline
  |Strikethrough->Prismel_next_resources.Font.Strikethrough)styles
let set_style font styles=match Prismel_next_resources.Font.set_style font.resource(resource_styles styles)with Ok()->clear_cache font;font.styles<-styles;font.generation<-font.generation+1|Error _->()
let get_style font=font.styles
let resource_hinting=function
  |Normal_hinting->Prismel_next_resources.Font.Normal_hinting
  |Light_hinting->Prismel_next_resources.Font.Light_hinting
  |Mono_hinting->Prismel_next_resources.Font.Mono_hinting
  |None_hinting->Prismel_next_resources.Font.None_hinting
let set_hinting font value=match Prismel_next_resources.Font.set_hinting font.resource(resource_hinting value)with Ok()->clear_cache font;font.hinting<-value;font.generation<-font.generation+1|Error _->()
let get_hinting font=font.hinting
let set_kerning font value=match Prismel_next_resources.Font.set_kerning font.resource value with Ok()->clear_cache font;font.kerning<-value;font.generation<-font.generation+1|Error _->()
let get_kerning font=font.kerning
let get_size font=font.size
let destroy font=
  fonts:=List.filter(fun candidate->candidate!=font)!fonts;
  clear_cache font;ignore(Prismel_next_resources.Font.destroy font.resource)
module Private=struct
 let cached_text=cached_text
 type automatic_entry={image:Image.t;mutable references:int;mutable stamp:int;mutable cached:bool}
 type automatic={entry:automatic_entry;mutable released:bool}
 let capacity=256 and font_capacity=32
 let automatic_cache:(string,automatic_entry)Hashtbl.t=Hashtbl.create capacity
 let automatic_fonts:(int,t*int)Hashtbl.t=Hashtbl.create font_capacity
 let automatic_references=ref 0
 let clock=ref 0
 let next_stamp()=incr clock;!clock
 let automatic_key ?wrap ?(align=Left) ?(density=1) ~size text mode=
   Marshal.to_string(density,size,text,wrap,align,rgba mode)[]
 let evict_entry()=
   let oldest=ref None in
   Hashtbl.iter(fun key entry->if entry.references=0 then match!oldest with
    |None->oldest:=Some(key,entry)|Some(_,candidate)when entry.stamp<candidate.stamp->oldest:=Some(key,entry)|Some _->())automatic_cache;
   match!oldest with None->false|Some(key,entry)->Hashtbl.remove automatic_cache key;entry.cached<-false;Image.destroy entry.image;true
 let font size=
   match Hashtbl.find_opt automatic_fonts size with
   |Some(value,_)->Hashtbl.replace automatic_fonts size(value,next_stamp());Ok value
   |None->
     if Hashtbl.length automatic_fonts>=font_capacity then begin
      let oldest=ref None in Hashtbl.iter(fun key(value,stamp)->match!oldest with None->oldest:=Some(key,value,stamp)|Some(_,_,candidate)when stamp<candidate->oldest:=Some(key,value,stamp)|Some _->())automatic_fonts;
      Option.iter(fun(key,value,_)->Hashtbl.remove automatic_fonts key;destroy value)!oldest
     end;
     match system~size()with Error _ as error->error|Ok value->Hashtbl.add automatic_fonts size(value,next_stamp());Ok value
 let borrow_automatic ?wrap ?(align=Left) ?(density=1) ~size text mode=
   let key=automatic_key?wrap~align~density~size text mode in
   match Hashtbl.find_opt automatic_cache key with
   |Some entry->
     entry.references<-entry.references+1;incr automatic_references;
     entry.stamp<-next_stamp();Ok{entry;released=false}
   |None->match font size with Error _ as error->error|Ok font->
     match paint ~density ?wrap font text mode with Error _ as error->error|Ok image->
      let can_cache=Hashtbl.length automatic_cache<capacity||evict_entry()in
      let entry={image;references=1;stamp=next_stamp();cached=can_cache}in
      if can_cache then Hashtbl.add automatic_cache key entry;
      incr automatic_references;
      Ok{entry;released=false}
 let automatic_image handle=handle.entry.image
 let release_automatic handle=if not handle.released then begin
   handle.released<-true;handle.entry.references<-handle.entry.references-1;
   decr automatic_references;
   if handle.entry.references=0&&not handle.entry.cached then Image.destroy handle.entry.image
  end
 let clear_automatic()=
  Hashtbl.iter(fun _ entry->entry.cached<-false;if entry.references=0 then Image.destroy entry.image)automatic_cache;
  Hashtbl.clear automatic_cache;
  let owned=Hashtbl.fold(fun _ (font,_) acc->font::acc)automatic_fonts[]in
  Hashtbl.clear automatic_fonts;List.iter destroy owned
 let automatic_counts()=
  Hashtbl.length automatic_cache,Hashtbl.length automatic_fonts,
    !automatic_references
 type retained_text=Owned_text of Image.t|Automatic_text of automatic
 let retain_text ?font ?(density=1) ~size text mode=match font with
  |Some font->Result.map(fun image->Owned_text image)
      (render_text~density font text mode)
  |None->Result.map(fun handle->Automatic_text handle)
      (borrow_automatic~density~size text mode)
 let retained_image=function
  |Owned_text image->image
  |Automatic_text handle->automatic_image handle
 let release_retained=function
  |Owned_text image->Image.destroy image
  |Automatic_text handle->release_automatic handle
 let generation font=font.generation
end
let release_renderer _renderer=List.iter clear_cache!fonts;Private.clear_automatic()
let shutdown()=Private.clear_automatic();let owned= !fonts in fonts:=[];List.iter destroy owned
let text_size font text=match render_text font text(Blended Color.white)with Error _ as e->e|Ok image->let size=Image.get_size image in Image.destroy image;Ok size
let render_wrapped font text mode width=
  let words=String.split_on_char ' ' text in
  let rec build line acc=function []->List.rev(line::acc)|word::rest->let candidate=if line=""then word else line^" "^word in if fst(Result.value(text_size font candidate)~default:(0,0))<=width then build candidate acc rest else build word(line::acc)rest in
  let lines=if text=""then[""]else build""[]words in
  let rec render acc=function []->Ok(List.rev acc)|line::rest->match render_text font line mode with Error _ as e->e|Ok image->render(image::acc)rest in render[]lines
let render_multiline font text mode align=cached_text ~align font text mode
let text_width font text=Result.map fst(text_size font text)
let text_height font text=Result.map snd(text_size font text)
let get_height font=font.size
let get_ascent font=font.size
let get_descent _font=0
let get_line_skip font=font.size
let get_family_name _=None
let get_style_name _=None
let is_fixed_width _=false
let glyph_metrics font code=match Prismel_next_resources.Font.glyph_metrics font.resource code with Ok m->Ok(m.min_x,m.max_x,m.min_y,m.max_y,m.advance)|Error e->Error(message"Font.glyph_metrics"e)
let glyph_provided font code=Result.is_ok(glyph_metrics font code)
