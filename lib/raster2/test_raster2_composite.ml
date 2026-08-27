open Raster2.Composite
let ok=function Ok x->x|Error _->failwith"error"
let get s x y=ok(Raster2.Surface.get_rgba s~x~y)
let make()=ok(Raster2.Surface.create~pitch:20~width:4~height:2())
let ()=let s=make()in Raster2.Surface.clear s 0x000000ffl;pixel s~blend:Copy~x:1~y:0 0xff000080l;if get s 1 0<>0xff000080l then failwith"copy";pixel s~blend:Source_over~x:1~y:0 0x00ff0080l;if get s 1 0<>0x55aa00c0l then failwith"over";ignore(ok(rect s~blend:Copy{x=(-2);y=1;width=4;height=2}0x11223344l));if get s 0 1<>0x11223344l||Bytes.get(Raster2.Surface.bytes s)16<>'\000'then failwith"clip/padding";for x=0 to 3 do ignore(Raster2.Surface.set_rgba s~x~y:0(Int32.of_int((x+1)lsl 24 lor 255)))done;ignore(ok(blit~src:s~src_rect:{x=0;y=0;width=3;height=1}~dst:s~dst_x:1~dst_y:0~blend:Copy));if List.init 4(fun x->get s x 0)<>[0x010000ffl;0x010000ffl;0x020000ffl;0x030000ffl]then failwith"self blit";
let source=0xc8643280l and destination=0x28507840l in
let exact=[Copy,0xc8643280l;Source_over,0xa86040a0l;Add,0xb07058a0l;
  Multiply,0x86523ba0l;Screen,0xaa6a53a0l;Subtract,0x804c44a0l]in
List.iter(fun(blend,expected)->if color~blend~source~destination<>expected then
  failwith"exact straight-alpha blend")exact;
List.iter(fun blend->
  if color~blend~source~destination:0xabcdef00l<>source then
    failwith"transparent destination leaked rgb";
  if color~blend~source:0xabcdef00l~destination<>destination then
    failwith"transparent source leaked rgb")
  [Source_over;Alpha;Add;Multiply;Screen;Subtract];
if color~blend:Replace~source:0x12345600l~destination<>0x12345600l then
  failwith"replace alpha-zero semantics";
let depth=ok(Raster2.Depth_stencil.create~width:1~height:1())in
ignore(ok(Raster2.Depth_stencil.clear depth~depth:0.4~stencil:3));
let state compare stencil={Raster2.Depth_stencil.depth_compare=compare;depth_write=true;
  stencil=Some{compare=Raster2.Depth_stencil.Equal;fail=Keep;depth_fail=Keep;
    pass=Replace;read_mask=0xff;write_mask=0xff;reference=stencil}}in
let destination=0x204060ffl and source=0xc0804080l in
let apply depth_value state blend destination=if ok(Raster2.Depth_stencil.test_and_update
  depth state~x:0~y:0~depth:depth_value)then color~blend~source~destination else destination in
if apply 0.6(state Less 3)Screen destination<>destination then
  failwith"depth failure mutated blend target";
if apply 0.2(state Less 3)Screen destination<>0x747074ffl then
  failwith"depth/stencil passing blend pixel";
ignore(ok(Raster2.Depth_stencil.clear depth~depth:1.~stencil:2));
if apply 0.2(state Less 3)Subtract destination<>destination then
  failwith"stencil failure mutated blend target";
let render()=let x=make()in Raster2.Surface.clear x 0x10203040l;ignore(ok(rect x~blend:Add{x=0;y=0;width=4;height=2}0x01020304l));Raster2.Surface.bytes x in let expected=render()in let ws=Array.init 4(fun _->Domain.spawn render)in Array.iter(fun w->if Domain.join w<>expected then failwith"domain drift")ws;print_endline"Raster2 deterministic compositing passed"
