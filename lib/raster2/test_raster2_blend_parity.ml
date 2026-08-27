open Raster2
let ok=function Ok x->x|Error _->failwith"blend error"
let rgba c a=Int32.(logor(shift_left(of_int c)24)(logor(shift_left(of_int c)16)(logor(shift_left(of_int c)8)(of_int a))))
let channel c=Int32.(to_int(logand(shift_right_logical c 24)0xffl))
let alpha c=Int32.(to_int(logand c 0xffl))
let expected mode source destination=
 let s=channel source and d=channel destination and sa=alpha source and da=alpha destination in
 let amount value=(value*sa+127)/255 in
 match mode with
 |Composite.Replace->source
 |Alpha->let oa=sa+((da*(255-sa)+127)/255)in let value=if oa=0 then 0 else let prem=(s*sa)+((d*da*(255-sa)+127)/255)in min 255((prem+(oa/2))/oa)in rgba value oa
 |Add|Multiply|Screen|Subtract->let value=match mode with Add->min 255(d+amount s)|Multiply->(d*((s*sa)+(255*(255-sa)))+32512)/65025|Screen->255-(((255-d)*(255-amount s)+127)/255)|Subtract->max 0(d-amount s)|_->assert false in rgba value(sa+((da*(255-sa)+127)/255))
 |_->assert false
let modes=[Composite.Replace;Alpha;Add;Multiply;Screen;Subtract]
let values=[0;1;127;128;254;255]
let ()=
 List.iter(fun mode->List.iter(fun source_channel->List.iter(fun source_alpha->List.iter(fun destination_channel->List.iter(fun destination_alpha->let surface=ok(Surface.create~width:1~height:1())in let source=rgba source_channel source_alpha and destination=rgba destination_channel destination_alpha in ignore(Surface.set_rgba surface~x:0~y:0 destination);Composite.pixel surface~blend:mode~x:0~y:0 source;let actual=ok(Surface.get_rgba surface~x:0~y:0)and wanted=expected mode source destination in if actual<>wanted then failwith(Printf.sprintf"blend mismatch mode=%d s=%d/%d d=%d/%d actual=%lx expected=%lx"(Obj.magic mode : int)source_channel source_alpha destination_channel destination_alpha actual wanted))values)values)values)values)modes;
 let surface=ok(Surface.create~width:1~height:1())and image=ok(Surface.create~width:1~height:1())in Surface.clear surface(rgba 20 255);Surface.clear image(rgba 100 128);let rect={Render_ir.x=0.;y=0.;width=1.;height=1.}in let ir=ok(Render_ir.create[|Set_blend Add;Image{resource_id=1;source=rect;destination=rect}|])in ok(Consumer.execute~lookup:(function 1->Some(Consumer.Image image)|_->None)~target:surface ir);assert(ok(Surface.get_rgba surface~x:0~y:0)=expected Add(rgba 100 128)(rgba 20 255));
 List.iter(fun frame->let render()=let surface=ok(Surface.create~width:1~height:1())in Surface.clear surface(rgba(frame land 255)127);List.iter(fun mode->Composite.pixel surface~blend:mode~x:0~y:0(rgba 91 128))modes;Surface.bytes surface in let expected=render()in let workers=Array.init 4(fun _->Domain.spawn render)in Array.iter(fun worker->assert(Domain.join worker=expected))workers)[1;600];
 print_endline"Raster2 exhaustive Scene blend parity passed"
