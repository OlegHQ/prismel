type t={resource:Runtime_resources.Canvas.t;
  mutable execution:Rays_execution.t option;mutable destroyed:bool;
  mutable epoch:int;mutable completed:bool}
let message operation error=Format.asprintf"%s: %a"operation Runtime_resources.pp_error error
let create ~width ~height=match Runtime_resources.Canvas.create ~width ~height with
  |Ok resource->Ok{resource;execution=None;destroyed=false;epoch=0;completed=false}
  |Error error->Error(message"Canvas.create"error)
let create_exn ~width ~height=match create ~width ~height with Ok value->value|Error value->failwith value
let size value=match Runtime_resources.Canvas.size value.resource with Ok value->value|Error error->failwith(message"Canvas.size"error)
let execution_message operation error=
  Format.asprintf"%s: %a"operation Rays_execution.pp_error error
let execution?(density=1) value=
  if value.destroyed then invalid_arg"Canvas.render: canvas is destroyed";
  match value.execution with
  |Some execution->execution
  |None->
      let width,height=size value in
      let configuration={Rays_execution.
        logical_width=width/density;logical_height=height/density;drawable_width=width;
        drawable_height=height;title="Rays Canvas";
        vsync=false;high_density=true}in
      match Rays_execution.create_offscreen configuration with
      |Error error->failwith(execution_message"Canvas.render"error)
      |Ok execution->value.execution<-Some execution;execution
let invalidate value=
  ignore(size value);
  value.epoch<-value.epoch+1;value.completed<-false
let render ?(density=1) value scene=
  invalidate value;
  if density<1 then invalid_arg"Canvas.render: density must be positive";
  let execution=execution~density value and width,height=size value in
  (match Native_scene_lowering.render~execution~density~width:(width/density)~height:(height/density) scene with
  |Ok _->()
  |Error error->
      failwith(Format.asprintf"Canvas.render: %a"Native_scene_lowering.pp_error error));
    match Rays_execution.offscreen_target execution with
    |Error error->failwith(execution_message"Canvas.render"error)
    |Ok texture->
      match Runtime_resources.Canvas.Private.publish_gpu value.resource texture with
      |Ok()->value.completed<-true|Error error->failwith(message"Canvas.render"error)
let snapshot value=match Runtime_resources.Canvas.capture value.resource with
  |Error error->failwith(message"Canvas.capture"error)|Ok image->
    let bytes=match Runtime_resources.Image.pixels image with Ok value->value|Error error->failwith(message"Canvas.pixels"error)in
    ignore(Runtime_resources.Image.destroy image);bytes
let pixel value ~x ~y=let w,h=size value in if x<0||y<0||x>=w||y>=h then None else
  let bytes=snapshot value and offset=(y*w+x)*4 in Some(Color.rgba(Char.code(Bytes.get bytes offset))
    (Char.code(Bytes.get bytes(offset+1)))(Char.code(Bytes.get bytes(offset+2)))(Char.code(Bytes.get bytes(offset+3))))
let pixels value=let w,h=size value and bytes=snapshot value in Array.init(w*h)(fun index->let offset=index*4 in
  Color.rgba(Char.code(Bytes.get bytes offset))(Char.code(Bytes.get bytes(offset+1)))
    (Char.code(Bytes.get bytes(offset+2)))(Char.code(Bytes.get bytes(offset+3))))
let to_image value=match Runtime_resources.Canvas.capture value.resource with
  |Ok image->Ok(Image.Private.of_resource image)
  |Error error->Error(message"Canvas.to_image"error)
module Private=struct
  let invalidate=invalidate
  let pixel_stats value=Runtime_resources.Canvas.Private.pixel_stats value.resource
  let gpu_source value=
    match Runtime_resources.Canvas.size value.resource with
    |Error error->Error(message "Canvas.gpu_source" error)
    |Ok _ when value.destroyed || not value.completed->Error "Canvas.gpu_source: no completed GPU frame"
    |Ok _->
    match Runtime_resources.Canvas.Private.gpu_snapshot value.resource with
    |None->Error "Canvas.gpu_source: no completed GPU frame"
    |Some(width,height,generation,texture)->
        let epoch=value.epoch in
        Ok(width,height,fun()->
          if value.destroyed || not value.completed || value.epoch<>epoch then None else
          match Runtime_resources.Canvas.Private.gpu_snapshot value.resource with
          |Some(_,_,current,source)when current=generation && source==texture->Some texture
          |_->None)
  type native_stats=Rays_execution.stats
  let native_stats value=match value.execution with
    |None->Runtime.zero_stats
    |Some execution->match Rays_execution.stats execution with
      |Error error->failwith(execution_message"Canvas.Private.native_stats"error)
      |Ok stats->stats
end
let save_png value path=match Runtime_resources.Canvas.save_png value.resource path with Ok()->Ok()|Error error->Error(message"Canvas.save_png"error)
let save_screen_png=Canvas_runtime.save
let destroy value=if not value.destroyed then(
  invalidate value;
  value.destroyed<-true;
  ignore(Runtime_resources.Canvas.destroy value.resource);
  Option.iter(fun execution->
    ignore(Rays_execution.destroy execution))
    value.execution;
  value.execution<-None;
  ())
