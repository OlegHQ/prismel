open Raster2.Image
let ok=function Ok x->x|Error _->failwith"error"
let make ?pitch w h=ok(Raster2.Surface.create?pitch~width:w~height:h())
let ()=let dst=make~pitch:16 3 2 in let mask=Bytes.of_string"\000\255xx\128\255xx"in ignore(ok(alpha_mask~dst~dst_x:0~dst_y:0~width:2~height:2~pitch:4 mask~color:0xff000080l));if ok(Raster2.Surface.get_rgba dst~x:1~y:0)<>0xff000080l||ok(Raster2.Surface.get_rgba dst~x:0~y:1)<>0xff000040l then failwith"mask alpha";if Bytes.get(Raster2.Surface.bytes dst)12<>'\000'then failwith"padding";let src=make 2 2 in List.iter(fun(x,y,c)->ignore(Raster2.Surface.set_rgba src~x~y c))[(0,0,0x000000ffl);(1,0,0xff0000ffl);(0,1,0x00ff00ffl);(1,1,0x0000ffffl)];let render filter=let out=make 4 4 in ignore(ok(blit_scaled~src~src_rect:{x=0;y=0;width=2;height=2}~dst:out~dst_rect:{x=(-1);y=(-1);width=4;height=4}~filter));Raster2.Surface.bytes out in let nearest=render Nearest in ignore nearest;let expected=render Bilinear in let ws=Array.init 4(fun _->Domain.spawn(fun()->render Bilinear))in Array.iter(fun w->if Domain.join w<>expected then failwith"domain")ws;(match alpha_mask~dst~dst_x:0~dst_y:0~width:2~height:2~pitch:1 mask~color:0l with Error Invalid_pitch->()|_->failwith"pitch");
  let large_src=make 640 480 and large_dst=make 640 480 in
  for index=0 to Bytes.length(Raster2.Surface.bytes large_src)-1 do
    Bytes.unsafe_set(Raster2.Surface.bytes large_src)index(Char.chr(index land 255))done;
  let source={x=0;y=0;width=640;height=480}and destination={x=0;y=0;width=640;height=480}in
  ignore(ok(blit_affine_blend~blend:Raster2.Composite.Copy~src:large_src~src_rect:source
    ~dst:large_dst~dst_rect:destination~xx:1.~xy:0.~yx:0.~yy:1.~tx:0.~ty:0.~filter:Bilinear));
  Gc.compact();let before=Gc.allocated_bytes()in
  ignore(ok(blit_affine_blend~blend:Raster2.Composite.Copy~src:large_src~src_rect:source
    ~dst:large_dst~dst_rect:destination~xx:1.~xy:0.~yx:0.~yy:1.~tx:0.~ty:0.~filter:Bilinear));
  let allocated=Gc.allocated_bytes()-.before in
  if allocated>10_000. then failwith(Printf.sprintf"affine blit allocated %.0f bytes"allocated);
  if Raster2.Surface.bytes large_dst<>Raster2.Surface.bytes large_src then
    failwith"identity affine pixels drifted";
  Gc.compact();let transformed_before=Gc.allocated_bytes()in
  ignore(ok(blit_affine_blend~blend:Raster2.Composite.Copy~src:large_src~src_rect:source
    ~dst:large_dst~dst_rect:destination~xx:1.~xy:0.~yx:0.~yy:1.~tx:0.25~ty:0.25~filter:Bilinear));
  let transformed_allocated=Gc.allocated_bytes()-.transformed_before in
  if transformed_allocated>10_000. then
    failwith(Printf.sprintf"transformed affine blit allocated %.0f bytes"transformed_allocated);
  Printf.printf"Raster2 affine 640x480 allocation: %.0f bytes\n"allocated;
  print_endline"Raster2 mask and image sampling passed"
