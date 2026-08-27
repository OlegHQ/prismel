open Raster2
let ok=function Ok value->value|Error _->failwith"scene3 consumer"
let white={Scene3_lighting.r=1.;g=1.;b=1.;a=1.}
let black={Scene3_lighting.r=0.;g=0.;b=0.;a=1.}
let lighting={Scene3_lighting.ambient=black;lights=[|Directional{direction={x=0.;y=0.;z=(-1.)};color=white;intensity=1.}|];material={ambient=black;diffuse=white;specular=black;emissive=black;shininess=0.};fog=No_fog;separate_specular=false;two_sided=false}
let matrix=[|1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.|]
let depth_stencil={Depth_stencil.depth_compare=Less;depth_write=true;stencil=None}
let render mode ~line_width ~point_size frame=
  let color=ok(Surface.create~width:16~height:12())and depth=ok(Depth_stencil.create~width:16~height:12())in
  let normal={Scene3_lighting.x=0.;y=0.;z=1.}in
  let vertex x y depth={Scene3_consumer.position={Scene3_lighting.x=x;y;z=depth};normal;color=0xffffffffl;u=x+.float frame;v=y}in
  let draw={Scene3_consumer.matrix;viewport={Scene3.x=0.;y=0.;width=16.;height=12.;min_depth=0.;max_depth=1.};scissor={Triangle.x=1;y=1;width=14;height=10};topology=Scene3.Triangle_list;vertices=[|vertex(-0.8)(-0.8)0.4;vertex 0.8(-0.8)0.4;vertex 0.8 0.8 0.4;vertex(-0.8)0.8 0.4|];indices=[|0;1;2;0;2;3|];lighting;shadows=[|None|];shading=Smooth;texture=None;cull=Triangle.Cull_none;blend=Composite.Source_over;depth_stencil;mode;line_width;point_size}in
  ok(Scene3_consumer.render~target:{color;depth=Some depth;multisample=None}~clear:0x000000ffl~clear_depth:1.~clear_stencil:0~draws:[|draw|]);
  Bytes.cat(Surface.bytes color)(Depth_stencil.bytes depth)
let changed_pixels bytes=let count=ref 0 in for offset=0 to(16*12)-1 do let base=offset*4 in if Bytes.get_int32_le bytes base<>0xff000000l then incr count done;!count
let changed_depth bytes=let start=16*12*4 and changed=ref false in for offset=0 to(16*12)-1 do let bits=Bytes.get_int32_le bytes(start+offset*8)in if Int32.float_of_bits bits<1. then changed:=true done;!changed
let ()=
  List.iter(fun mode->List.iter(fun frame->let expected=render mode~line_width:2.~point_size:3. frame in let workers=Array.init 4(fun _->Domain.spawn(fun()->render mode~line_width:2.~point_size:3. frame))in Array.iter(fun worker->if Domain.join worker<>expected then failwith"Scene3 mode domain drift")workers)[1;2;60;600])[Scene3_consumer.Faces;Wireframe;Vertices];
  let wire1=render Wireframe~line_width:1.~point_size:1. 1 and wire3=render Wireframe~line_width:5.~point_size:1. 1 and point1=render Vertices~line_width:1.~point_size:1. 1 and point3=render Vertices~line_width:1.~point_size:5. 1 in
  if changed_pixels wire3<=changed_pixels wire1 then failwith(Printf.sprintf"wire width ignored: %d/%d"(changed_pixels wire1)(changed_pixels wire3));
  if changed_pixels point3<=changed_pixels point1 then failwith"point size ignored";
  if not(changed_depth wire1&&changed_depth point1)then failwith"polygon depth state ignored";
  let target=ok(Surface.create~width:2~height:2())in let before=Bytes.copy(Surface.bytes target)in ok(Scene3_consumer.render~target:{color=target;depth=None;multisample=None}~clear:0x01020304l~clear_depth:1.~clear_stencil:0~draws:[||]);if Surface.bytes target=before then failwith"empty clear missing";
  print_endline"Raster2 deterministic Scene3 consumer passed"
