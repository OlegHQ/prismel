type render_mode=Solid of Color.t|Shaded of Color.t*Color.t|Blended of Color.t
type style=Normal|Bold|Italic|Underline|Strikethrough
type hinting=Normal_hinting|Light_hinting|Mono_hinting|None_hinting
type alignment=Left|Center|Right
type t={resource:Prismel_next_resources.Font.t;size:int;mutable styles:style list;
  mutable hinting:hinting;mutable kerning:bool;cache:(string,Image.t)Hashtbl.t;order:string Queue.t}
let message operation error=`Msg(Format.asprintf"%s: %a"operation Prismel_next_resources.pp_error error)
let make size=function Ok resource->Ok{resource;size;styles=[];hinting=Normal_hinting;kerning=true;cache=Hashtbl.create 256;order=Queue.create()}|Error error->Error(message"Font.load"error)
let load path size=make size(Prismel_next_resources.Font.open_file ~path ~size:(float size))
let system ?(size=16)()=make size(Prismel_next_resources.Font.open_system ~size:(float size))
let rgba=function Solid c|Blended c|Shaded(c,_)->c.Color.r,c.g,c.b,c.a
let image_of_text text=match Prismel_next_resources.Text.size text,Prismel_next_resources.Text.pixels text with
  |Ok(width,height),Ok rgba->begin match Prismel_next_resources.Image.create ~width ~height ~rgba with Ok image->Ok image|Error error->Error(message"Font.image"error)end
  |Error error,_->Error(message"Font.size"error)|_,Error error->Error(message"Font.pixels"error)
let render_text font text mode=match Prismel_next_resources.Font.render font.resource ~density:1 ~color:(rgba mode)text with
  |Error error->Error(message"Font.render_text"error)|Ok None->Ok(Image.create ~width:1 ~height:1())
  |Ok(Some value)->let result=image_of_text value in ignore(Prismel_next_resources.Text.destroy value);result
let key ?wrap ?(align=Left) text mode=Marshal.to_string(text,wrap,align,rgba mode)[]
let cached_text ?wrap ?(align=Left) font text mode=let key=key ?wrap ~align text mode in match Hashtbl.find_opt font.cache key with Some image->Ok image|None->
  match render_text font text mode with Error _ as error->error|Ok image->
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
let set_style font styles=match Prismel_next_resources.Font.set_style font.resource(resource_styles styles)with Ok()->font.styles<-styles|Error _->()
let get_style font=font.styles
let resource_hinting=function
  |Normal_hinting->Prismel_next_resources.Font.Normal_hinting
  |Light_hinting->Prismel_next_resources.Font.Light_hinting
  |Mono_hinting->Prismel_next_resources.Font.Mono_hinting
  |None_hinting->Prismel_next_resources.Font.None_hinting
let set_hinting font value=match Prismel_next_resources.Font.set_hinting font.resource(resource_hinting value)with Ok()->font.hinting<-value|Error _->()
let get_hinting font=font.hinting
let set_kerning font value=match Prismel_next_resources.Font.set_kerning font.resource value with Ok()->font.kerning<-value|Error _->()
let get_kerning font=font.kerning
let get_size font=font.size
let destroy font=clear_cache font;ignore(Prismel_next_resources.Font.destroy font.resource)
