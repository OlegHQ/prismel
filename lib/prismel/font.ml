type render_mode=Blended of Color.t
type style=Normal|Bold|Italic|Underline|Strikethrough
type hinting=Normal_hinting|Light_hinting|Mono_hinting|None_hinting
type alignment=Left|Center|Right
(* density, size, text, wrap, align, rgba *)
module Text_key=struct
  type t=int*int*string*int option*alignment*(int*int*int*int)
  let equal=(=) let hash=Hashtbl.hash end
module Text_cache=Lru.Make(Text_key)
type t={resource:Runtime_resources.Font.t;size:int;source:string option;mutable styles:style list;
  mutable hinting:hinting;mutable kerning:bool;mutable generation:int;
  cache:Image.t Text_cache.t}
let text_cache_capacity=256
let text_cache()=Text_cache.create ~release:(fun _ image->Image.destroy image)text_cache_capacity
let message operation error=`Msg(Format.asprintf"%s: %a"operation Runtime_resources.pp_error error)
let fonts:t list ref=ref[]
let make ?source size=function Ok resource->let value={resource;size;source;styles=[];hinting=Normal_hinting;kerning=true;generation=1;cache=text_cache()}in fonts:=value::!fonts;Ok value|Error error->Error(message"Font.load"error)
let load path size=make ~source:path size(Runtime_resources.Font.open_file ~path ~size:(float size))
let system_path()=match Sys.getenv_opt"PRISMEL_UI_FONT"with Some path when Sys.file_exists path->Some path|_->List.find_opt Sys.file_exists["/System/Library/Fonts/SFNSMono.ttf";"/System/Library/Fonts/SFNS.ttf";"/Library/Fonts/Arial.ttf";"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"]
let system ?(size=16)()=make size(Runtime_resources.Font.open_system ~size:(float size))
let resize font size=match font.source with Some path->load path size|None->system ~size()
let rgba(Blended c)=c.Color.r,c.g,c.b,c.a
(* Invalid UTF-8 becomes U+FFFD rather than failing mid-frame. *)
let sanitize text=if String.is_valid_utf_8 text then text else begin
  let buffer=Buffer.create(String.length text)in
  let rec loop i=if i<String.length text then begin
    let d=String.get_utf_8_uchar text i in
    Buffer.add_utf_8_uchar buffer(Uchar.utf_decode_uchar d);loop(i+Uchar.utf_decode_length d)end in
  loop 0;Buffer.contents buffer end
let resource_align=function Left->Runtime_resources.Font.Left|Center->Center|Right->Right
let image_of_text text=match Runtime_resources.Text.Private.into_image text with
  |Ok image->Ok(Image.Private.of_resource image)
  |Error error->Error(message"Font.image"error)
let paint ?(density=1) ?wrap ?(align=Left) font text mode=match Runtime_resources.Font.render font.resource ?wrap_width:wrap ~align:(resource_align align) ~density ~color:(rgba mode)(sanitize text)with
  |Error error->Error(message"Font.render_text"error)|Ok None->Ok(Image.create ~width:1 ~height:1())
  |Ok(Some value)->let result=image_of_text value in ignore(Runtime_resources.Text.destroy value);result
let render_text ?(density=1) font text mode=paint ~density font text mode
let key ?wrap ?(align=Left) ?(density=1) ?(size=0) text mode:Text_key.t=density,size,text,wrap,align,rgba mode
let cached_text ?wrap ?(align=Left) ?(density=1) font text mode=let key=key ?wrap ~align ~density text mode in match Text_cache.find font.cache key with image->Ok image|exception Not_found->
  match paint ~density ?wrap ~align font text mode with Error _ as error->error|Ok image->
    Text_cache.add font.cache key image;Ok image
let clear_cache font=Text_cache.clear font.cache
let resource_styles styles=List.map(function
  |Normal->Runtime_resources.Font.Normal
  |Bold->Runtime_resources.Font.Bold
  |Italic->Runtime_resources.Font.Italic
  |Underline->Runtime_resources.Font.Underline
  |Strikethrough->Runtime_resources.Font.Strikethrough)styles
let set_style font styles=match Runtime_resources.Font.set_style font.resource(resource_styles styles)with Ok()->clear_cache font;font.styles<-styles;font.generation<-font.generation+1;Ok()|Error e->Error(message"Font.set_style"e)
let get_style font=font.styles
let resource_hinting=function
  |Normal_hinting->Runtime_resources.Font.Normal_hinting
  |Light_hinting->Runtime_resources.Font.Light_hinting
  |Mono_hinting->Runtime_resources.Font.Mono_hinting
  |None_hinting->Runtime_resources.Font.None_hinting
let set_hinting font value=match Runtime_resources.Font.set_hinting font.resource(resource_hinting value)with Ok()->clear_cache font;font.hinting<-value;font.generation<-font.generation+1;Ok()|Error e->Error(message"Font.set_hinting"e)
let get_hinting font=font.hinting
let set_kerning font value=match Runtime_resources.Font.set_kerning font.resource value with Ok()->clear_cache font;font.kerning<-value;font.generation<-font.generation+1;Ok()|Error e->Error(message"Font.set_kerning"e)
let get_kerning font=font.kerning
let get_size font=font.size
let destroy font=
  fonts:=List.filter(fun candidate->candidate!=font)!fonts;
  clear_cache font;ignore(Runtime_resources.Font.destroy font.resource)
module Private=struct
 let cached_text=cached_text
 type automatic_entry={image:Image.t;mutable references:int;mutable cached:bool}
 type automatic={entry:automatic_entry;mutable released:bool}
 let capacity=256 and font_capacity=32
 (* Borrowed entries are pinned: only unreferenced text can be evicted, so
    the table may hold more than [capacity] while every entry is in use. *)
 let automatic_cache=Text_cache.create capacity
   ~evictable:(fun _ entry->entry.references=0)
   ~release:(fun _ entry->entry.cached<-false;
     if entry.references=0 then Image.destroy entry.image)
 module Font_cache=Lru.Make(Int)
 let automatic_fonts=Font_cache.create font_capacity ~release:(fun _ font->destroy font)
 let automatic_references=ref 0
 let font size=
   match Font_cache.find automatic_fonts size with
   |value->Ok value
   |exception Not_found->
     match system~size()with Error _ as error->error|Ok value->Font_cache.add automatic_fonts size value;Ok value
 let borrow_automatic ?wrap ?(align=Left) ?(density=1) ~size text mode=
   let key=key?wrap~align~density~size text mode in
   match Text_cache.find automatic_cache key with
   |entry->
     entry.references<-entry.references+1;incr automatic_references;
     Ok{entry;released=false}
   |exception Not_found->match font size with Error _ as error->error|Ok font->
     match paint ~density ?wrap ~align font text mode with Error _ as error->error|Ok image->
      (* A full table of borrowed entries makes the new value transient
         instead of invalidating an image an active scene still holds. *)
      let can_cache=Text_cache.length automatic_cache<capacity||
        Option.is_some(Text_cache.find_first automatic_cache(fun _ entry->entry.references=0))in
      let entry={image;references=1;cached=can_cache}in
      if can_cache then Text_cache.add automatic_cache key entry;
      incr automatic_references;
      Ok{entry;released=false}
 let automatic_image handle=handle.entry.image
 let release_automatic handle=if not handle.released then begin
   handle.released<-true;handle.entry.references<-handle.entry.references-1;
   decr automatic_references;
   if handle.entry.references=0&&not handle.entry.cached then Image.destroy handle.entry.image
  end
 let clear_automatic()=
  Text_cache.clear automatic_cache;Font_cache.clear automatic_fonts
 let automatic_counts()=
  Text_cache.length automatic_cache,Font_cache.length automatic_fonts,
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
 type glyph={glyph_width:int;glyph_height:int;glyph_advance:int;glyph_alpha:bytes}
 (* One code point rendered exactly as [render_text] rasterizes it inside a
    string at [density], so glyph-by-glyph composition at pen advances
    reproduces whole-string pixels. *)
 let glyph ?(density=1) font code=
   if not(Uchar.is_valid code)then Error(`Msg"Font.glyph: invalid code point")else
   match Runtime_resources.Font.glyph_metrics_at font.resource~density code with
   |Error error->Error(message"Font.glyph"error)
   |Ok metrics->
     let text=let buffer=Buffer.create 4 in
       Buffer.add_utf_8_uchar buffer(Uchar.of_int code);Buffer.contents buffer in
     match Runtime_resources.Font.render font.resource~density
         ~color:(255,255,255,255)text with
     |Error error->Error(message"Font.glyph"error)
     |Ok None->Ok{glyph_width=0;glyph_height=0;glyph_advance=metrics.advance;
         glyph_alpha=Bytes.empty}
     |Ok(Some rendered)->
       Fun.protect~finally:(fun()->ignore(Runtime_resources.Text.destroy rendered))
         (fun()->match Runtime_resources.Text.size rendered,
             Runtime_resources.Text.pixels rendered with
           |Ok(width,height),Ok rgba->
               Ok{glyph_width=width;glyph_height=height;
                 glyph_advance=metrics.advance;
                 glyph_alpha=Bytes.init(width*height)(fun index->
                   Bytes.get rgba(index*4+3))}
           |Error error,_|_,Error error->Error(message"Font.glyph"error))
end
let shutdown()=Private.clear_automatic();let owned= !fonts in fonts:=[];List.iter destroy owned
let text_size ?wrap font text=match Runtime_resources.Font.size_text font.resource ?wrap_width:wrap(sanitize text)with Ok size->Ok size|Error e->Error(message"Font.text_size"e)
let text_width font text=Result.map fst(text_size font text)
let text_height font text=Result.map snd(text_size font text)
let metrics font=match Runtime_resources.Font.metrics font.resource with
  |Ok m->m|Error e->let `Msg text=message"Font.metrics"e in invalid_arg text
let get_height font=(metrics font).height
let get_ascent font=(metrics font).ascent
let get_descent font=(metrics font).descent
let get_line_skip font=(metrics font).line_skip
let get_family_name font=Result.value(Runtime_resources.Font.family_name font.resource)~default:None
let get_style_name font=Result.value(Runtime_resources.Font.style_name font.resource)~default:None
let glyph_metrics font code=match Runtime_resources.Font.glyph_metrics font.resource code with Ok m->Ok(m.min_x,m.max_x,m.min_y,m.max_y,m.advance)|Error e->Error(message"Font.glyph_metrics"e)
