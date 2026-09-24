type t={resource:Prismel_next_resources.Canvas.t;
  mutable execution:Prismel_next_execution.t option;mutable destroyed:bool}
let message operation error=Format.asprintf"%s: %a"operation Prismel_next_resources.pp_error error
let create ~width ~height=match Prismel_next_resources.Canvas.create ~width ~height with
  |Ok resource->Ok{resource;execution=None;destroyed=false}
  |Error error->Error(message"Canvas.create"error)
let create_exn ~width ~height=match create ~width ~height with Ok value->value|Error value->failwith value
let size value=match Prismel_next_resources.Canvas.size value.resource with Ok value->value|Error error->failwith(message"Canvas.size"error)
let width value=fst(size value)
let height value=snd(size value)
let execution_message operation error=
  Format.asprintf"%s: %a"operation Prismel_next_execution.pp_error error
let execution value=
  if value.destroyed then invalid_arg"Canvas.render: canvas is destroyed";
  match value.execution with
  |Some execution->execution
  |None->
      let width,height=size value in
      let configuration={Prismel_next_execution.default_configuration with
        logical_width=width;logical_height=height;drawable_width=width;
        drawable_height=height;title="Prismel Canvas";
        timing=Prismel_next_execution.Fixed(1./.60.);vsync=false}in
      match Prismel_next_execution.create_offscreen configuration with
      |Error error->failwith(execution_message"Canvas.render"error)
      |Ok execution->value.execution<-Some execution;execution
let render value scene=
  let execution=execution value and width,height=size value in
  (match Native_scene_lowering.render~execution~density:1~width~height scene with
  |Ok _->()
  |Error error->
      failwith(Format.asprintf"Canvas.render: %a"Native_scene_lowering.pp_error error));
    match Prismel_next_resources.Canvas.Private.prepare_write value.resource with
    |Error error->failwith(message"Canvas.render"error)
    |Ok(_,_,destination)->
      (match Prismel_next_execution.capture_into execution~destination with
       |Error error->failwith(execution_message"Canvas.render"error)
       |Ok()->match Prismel_next_resources.Canvas.Private.commit_write value.resource with
         |Ok()->()|Error error->failwith(message"Canvas.render"error))
let packed color=Int32.logor(Int32.shift_left(Int32.of_int color.Color.r)24)
  (Int32.logor(Int32.shift_left(Int32.of_int color.g)16)
    (Int32.logor(Int32.shift_left(Int32.of_int color.b)8)(Int32.of_int color.a)))
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
let to_image value=match Prismel_next_resources.Canvas.capture value.resource with
  |Ok image->Ok(Image.Private.of_resource image)
  |Error error->Error(message"Canvas.to_image"error)
module Private=struct
  type native_stats={frames:int64;logical_draws:int64;logical_passes:int64;
    logical_submissions:int64;uploaded_bytes:int64;cache_entries:int}
  let copy_to_image value image=
    match Prismel_next_resources.Canvas.copy_to_image value.resource(Image.Private.resource image)with
    |Ok()->Ok()|Error error->Error(message"Canvas.Private.copy_to_image"error)
  let native_stats value=match value.execution with
    |None->{frames=0L;logical_draws=0L;logical_passes=0L;
        logical_submissions=0L;uploaded_bytes=0L;cache_entries=0}
    |Some execution->match Prismel_next_execution.stats execution with
      |Error error->failwith(execution_message"Canvas.Private.native_stats"error)
      |Ok stats->{frames=stats.frames;logical_draws=stats.logical_draws;
          logical_passes=stats.logical_passes;
          logical_submissions=stats.logical_submissions;
          uploaded_bytes=stats.uploaded_bytes;cache_entries=stats.cache_entries}
end
let save_png value path=match Prismel_next_resources.Canvas.save_png value.resource path with Ok()->Ok()|Error error->Error(message"Canvas.save_png"error)
let write_bytes value bytes=match Prismel_next_resources.Canvas.replace_pixels value.resource bytes with
 |Ok()->()|Error error->invalid_arg(message"Canvas.write_bytes"error)
let capture()=match Canvas_runtime.capture()with Error _ as error->error|Ok(w,h,bytes)->let value=create_exn~width:w~height:h in(try write_bytes value bytes;Ok value with exn->ignore(Prismel_next_resources.Canvas.destroy value.resource);Error(Printexc.to_string exn))
let save_screen_png=Canvas_runtime.save
let destroy value=if not value.destroyed then(
  Option.iter(fun execution->ignore(Prismel_next_execution.destroy execution))
    value.execution;
  value.execution<-None;
  ignore(Prismel_next_resources.Canvas.destroy value.resource);
  value.destroyed<-true)
