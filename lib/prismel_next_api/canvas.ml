type t={resource:Prismel_next_resources.Canvas.t;mutable destroyed:bool}
let message operation error=Format.asprintf"%s: %a"operation Prismel_next_resources.pp_error error
let create ~width ~height=match Prismel_next_resources.Canvas.create ~width ~height with
  |Ok resource->Ok{resource;destroyed=false}|Error error->Error(message"Canvas.create"error)
let create_exn ~width ~height=match create ~width ~height with Ok value->value|Error value->failwith value
let size value=match Prismel_next_resources.Canvas.size value.resource with Ok value->value|Error error->failwith(message"Canvas.size"error)
let width value=fst(size value)
let height value=snd(size value)
let packed color=Int32.logor(Int32.shift_left(Int32.of_int color.Color.r)24)
  (Int32.logor(Int32.shift_left(Int32.of_int color.g)16)
    (Int32.logor(Int32.shift_left(Int32.of_int color.b)8)(Int32.of_int color.a)))
let clear value color=ignore(Prismel_next_resources.Canvas.clear value.resource(packed color))
let snapshot value=match Prismel_next_resources.Canvas.capture value.resource with
  |Error error->failwith(message"Canvas.capture"error)|Ok image->
    let bytes=match Prismel_next_resources.Image.pixels image with Ok value->value|Error error->failwith(message"Canvas.pixels"error)in
    ignore(Prismel_next_resources.Image.destroy image);bytes
let pixel value ~x ~y=let w,h=size value in if x<0||y<0||x>=w||y>=h then None else
  let bytes=snapshot value and offset=(y*w+x)*4 in Some(Color.rgba(Char.code(Bytes.get bytes offset))
    (Char.code(Bytes.get bytes(offset+1)))(Char.code(Bytes.get bytes(offset+2)))(Char.code(Bytes.get bytes(offset+3))))
let pixels value=let w,h=size value and bytes=snapshot value in Array.init(w*h)(fun index->let offset=index*4 in
  Color.rgba(Char.code(Bytes.get bytes offset))(Char.code(Bytes.get bytes(offset+1)))
    (Char.code(Bytes.get bytes(offset+2)))(Char.code(Bytes.get bytes(offset+3))))
let set_pixel value ~x ~y color=ignore(Prismel_next_resources.Canvas.set_pixel value.resource ~x ~y(packed color))
let map_pixels value operation=let w,h=size value in for y=0 to h-1 do for x=0 to w-1 do match pixel value ~x ~y with None->()|Some old->set_pixel value ~x ~y(operation ~x ~y old)done done
let apply_mask ~source ~mask=let sw,sh=size source and mw,mh=size mask in if(sw,sh)<>(mw,mh)then invalid_arg"Canvas.apply_mask";
  for y=0 to sh-1 do for x=0 to sw-1 do match pixel source ~x ~y,pixel mask ~x ~y with
  |Some src,Some m->set_pixel source ~x ~y(Color.with_alpha src(src.a*m.a/255))|_->()done done
let to_image value=match Prismel_next_resources.Canvas.capture value.resource with Ok image->Ok image|Error error->Error(message"Canvas.to_image"error)
let save_png value path=match Prismel_next_resources.Canvas.save_png value.resource path with Ok()->Ok()|Error error->Error(message"Canvas.save_png"error)
let destroy value=if not value.destroyed then(ignore(Prismel_next_resources.Canvas.destroy value.resource);value.destroyed<-true)
