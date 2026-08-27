type error=Invalid_frame of string|Transport of string|Destroyed
type frame={rgba:bytes;pitch:int;logical_width:int;logical_height:int;drawable_width:int;drawable_height:int}
type t={server:Wap.t;mutable destroyed:bool;mutable regions:Wap.text_input_region list}
let create ?config ()=match Wap.start ?config()with Error message->Error(Transport message)|Ok server->Ok{server;destroyed=false;regions=[]}
let validate frame=
  if frame.logical_width<=0||frame.logical_height<=0||frame.drawable_width<=0||frame.drawable_height<=0 then Error(Invalid_frame"dimensions must be positive")
  else if frame.drawable_width>max_int/4 then Error(Invalid_frame"row size overflows")
  else let row=frame.drawable_width*4 in
    if frame.pitch<row then Error(Invalid_frame"pitch is shorter than RGBA row")
    else if frame.drawable_height>max_int/frame.pitch||Bytes.length frame.rgba<frame.pitch*frame.drawable_height then Error(Invalid_frame"storage is shorter than pitch multiplied by height")
    else if frame.drawable_height>max_int/row then Error(Invalid_frame"packed frame size overflows")else Ok row
let present value frame=if value.destroyed then Error Destroyed else match validate frame with Error _ as error->error|Ok row->
  let length=row*frame.drawable_height in let packed=Wap.acquire_frame value.server~length in
  for y=0 to frame.drawable_height-1 do for x=0 to row-1 do Bigarray.Array1.unsafe_set packed(y*row+x)(Char.code(Bytes.unsafe_get frame.rgba(y*frame.pitch+x)))done done;
  Wap.publish_frame value.server~drawable_width:frame.drawable_width~drawable_height:frame.drawable_height~logical_width:frame.logical_width~logical_height:frame.logical_height packed;Ok()
let stats value=Wap.stats value.server
let port value=Wap.port value.server
let set_text_input_regions value regions=if value.destroyed then Error Destroyed else
  try Wap.set_text_input_regions value.server regions;value.regions<-regions;Ok()with Invalid_argument message->Error(Invalid_frame message)
let text_input_regions value=value.regions
let register_bytes value ?content_type bytes =
  if value.destroyed then None else Wap.register_bytes value.server ?content_type bytes
let remove_asset value id = if not value.destroyed then Wap.remove_asset value.server id
let drain_events value = if value.destroyed then [] else Wap.drain_events value.server
let destroy value=if not value.destroyed then(value.destroyed<-true;Wap.stop value.server)
