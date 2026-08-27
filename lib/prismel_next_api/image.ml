type t = Prismel_next_resources.Image.t
let message operation error=Format.asprintf"%s: %a"operation Prismel_next_resources.pp_error error
let map operation=function Ok value->Ok value|Error error->Error(message operation error)
let load path=map"Image.load"(Prismel_next_resources.Image.load_file path)
let load_exn path=match load path with Ok value->value|Error message->failwith message
let create ~width ~height ?(color=Color.transparent) () =
  let rgba=Bytes.create(max 0(width*height*4))in
  for index=0 to width*height-1 do let offset=index*4 in
    Bytes.set rgba offset(Char.chr color.Color.r);
    Bytes.set rgba(offset+1)(Char.chr color.g);
    Bytes.set rgba(offset+2)(Char.chr color.b);
    Bytes.set rgba(offset+3)(Char.chr color.a)done;
  match Prismel_next_resources.Image.create ~width ~height ~rgba with
  | Ok value->value|Error error->failwith(message"Image.create"error)
let destroy value=ignore(Prismel_next_resources.Image.destroy value)
let get_size value=match Prismel_next_resources.Image.size value with
  | Ok size->size|Error error->failwith(message"Image.get_size"error)
let get_width value=fst(get_size value)
let get_height value=snd(get_size value)
module Private=struct
  type renderer=int
  type texture=t
  let current_renderer:renderer option ref=ref None
  let set_renderer renderer=current_renderer:=Some renderer
  let get_renderer()=match!current_renderer with Some renderer->Ok renderer|None->Error"Image.Private.get_renderer: renderer unavailable"
  let get_texture image=image
  let from_texture image _width _height=image
  let load_memory contents=map"Image.Private.load_memory"(Prismel_next_resources.Image.load_bytes(Bytes.of_string contents))
  let replace target source=match Prismel_next_resources.Image.size source,Prismel_next_resources.Image.pixels source with
    |Ok(width,height),Ok rgba->begin match Prismel_next_resources.Image.replace target ~width ~height ~rgba with Ok()->destroy source|Error error->failwith(message"Image.Private.replace"error)end
    |Error error,_->failwith(message"Image.Private.replace"error)|_,Error error->failwith(message"Image.Private.replace"error)
  let identity=Prismel_next_resources.Image.identity
  let generation=Prismel_next_resources.Image.generation
  let reload value path=map"Image.reload"(Prismel_next_resources.Image.reload_file value path)
  let pixels value=map"Image.pixels"(Prismel_next_resources.Image.pixels value)
  let of_resource image=image
  let resource image=image
end
