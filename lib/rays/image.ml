type t = Runtime_resources.Image.t
let message operation error=Format.asprintf"%s: %a"operation Runtime_resources.pp_error error
let map operation=function Ok value->Ok value|Error error->Error(message operation error)
let load path=map"Image.load"(Runtime_resources.Image.load_file path)
let load_exn path=match load path with Ok value->value|Error message->failwith message
let create ~width ~height ?(color=Color.transparent) () =
  let rgba=Bytes.create(max 0(width*height*4))in
  for index=0 to width*height-1 do let offset=index*4 in
    Bytes.set rgba offset(Char.chr color.Color.r);
    Bytes.set rgba(offset+1)(Char.chr color.g);
    Bytes.set rgba(offset+2)(Char.chr color.b);
    Bytes.set rgba(offset+3)(Char.chr color.a)done;
  match Runtime_resources.Image.create ~width ~height ~rgba with
  | Ok value->value|Error error->failwith(message"Image.create"error)
let upload_rgba ?into ~width ~height ~rgba () = match into with
  | None -> map "Image.upload_rgba" (Runtime_resources.Image.create ~width ~height ~rgba)
  | Some image ->
      Result.map (fun () -> image)
        (map "Image.upload_rgba" (Runtime_resources.Image.replace image ~width ~height ~rgba))
let destroy value=ignore(Runtime_resources.Image.destroy value)
let get_size value=match Runtime_resources.Image.size value with
  | Ok size->size|Error error->failwith(message"Image.get_size"error)
let get_width value=fst(get_size value)
let get_height value=snd(get_size value)
module Private=struct
  let replace target source=
    match Runtime_resources.Image.replace_owned target source with
    |Ok()->()
    |Error error->failwith(message"Image.Private.replace"error)
  let identity=Runtime_resources.Image.identity
  let pixels value=map"Image.pixels"(Runtime_resources.Image.pixels value)
  let of_resource image=image
  let resource image=image
end
