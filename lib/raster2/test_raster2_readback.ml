open Raster2
let ok=function Ok x->x|Error _->failwith"readback error"
let source frame width height=
 let surface=ok(Surface.create~width~height~pitch:(width*4+3)())in
 Bytes.fill(Surface.bytes surface)0(Bytes.length(Surface.bytes surface))'\x7f';
 for y=0 to height-1 do for x=0 to width-1 do
  let color=Int32.of_int(((((frame+x)land 255)lsl 24) lor ((y land 255)lsl 16) lor 0x55ff))in
  ok(Surface.set_rgba surface~x~y color)
 done done;surface
let render frame width height orientation format=let scratch=ok(Readback.create~initial_capacity:1~hard_capacity:4096)in let output=ok(Readback.read scratch~orientation~format(source frame width height))in assert(Readback.pitch output=width*4);Bytes.sub(Readback.bytes output)0(Readback.length output),Readback.hash output
let ()=let rgba,_=render 1 3 2 Readback.Top_down Rgba and flipped,_=render 1 3 2 Bottom_up Rgba and bgra,_=render 1 3 2 Top_down Bgra in assert(Bytes.length rgba=24);assert(Bytes.sub rgba 0 12=Bytes.sub flipped 12 12);assert(Bytes.get rgba 0=Bytes.get bgra 2&&Bytes.get rgba 2=Bytes.get bgra 0);List.iter(fun frame->let expected=render frame 7 5 Top_down Rgba in let workers=Array.init 4(fun _->Domain.spawn(fun()->render frame 7 5 Top_down Rgba))in Array.iter(fun worker->assert(Domain.join worker=expected))workers)[1;2;60;600];ignore(render 601 11 7 Bottom_up Bgra);let scratch=ok(Readback.create~initial_capacity:4~hard_capacity:64)and surface=source 3 2 2 in for _=1 to 100_000 do ignore(ok(Readback.read scratch~orientation:Top_down~format:Rgba surface))done;let metrics=Readback.metrics scratch in assert(metrics.growths=1&&metrics.capacity=16);(match Readback.create~initial_capacity:2~hard_capacity:1 with Error Readback.Invalid_capacity->()|_->failwith"invalid capacity");print_endline"Raster2 deterministic pitched readback passed"
