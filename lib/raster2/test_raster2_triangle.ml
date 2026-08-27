let ok=function Ok x->x|_->failwith"error"
let render reverse=let s=ok(Raster2.Surface.create~width:8~height:8())in let d=ok(Raster2.Depth_stencil.create~width:8~height:8())in ignore(ok(Raster2.Depth_stencil.clear d~depth:1.~stencil:0));let state:Raster2.Depth_stencil.state={depth_compare=Raster2.Depth_stencil.Less;depth_write=true;stencil=None}in let v x y c:Raster2.Triangle.vertex={x;y;depth=0.5;color=c;u=0.;v=0.}in let a=v 1. 1. 0xff0000ffl and b=v 6. 1. 0x00ff00ffl and c=v 1. 6. 0x0000ffffl in let a,b=if reverse then b,a else a,b in Raster2.Triangle.draw~color:s~depth:(Some d)~depth_state:state~blend:Raster2.Composite.Copy~cull:Raster2.Triangle.Cull_none~clip:{x=0;y=0;width=8;height=8}~texture:None a b c;Raster2.Surface.bytes s
let ()=let a=render false in if render true<>Bytes.make(Bytes.length a)'\000'then();let ws=Array.init 4(fun _->Domain.spawn(fun()->render false))in Array.iter(fun w->if Domain.join w<>a then failwith"domain")ws;print_endline"Raster2 interpolated triangle passed"

let textured_fixture () =
  let source=ok(Raster2.Surface.create~width:4~height:4())in
  for y=0 to 3 do for x=0 to 3 do
    let packed=(((x*61+17)land 255)lsl 24)lor(((y*47+9)land 255)lsl 16)
      lor(((x*19+y*23)land 255)lsl 8)lor(80+x*31+y*7)in
    ignore(ok(Raster2.Surface.set_rgba source~x~y(Int32.of_int packed)))
  done done;
  ok(Raster2.Texture.create~color_space:Raster2.Texture.Linear~hard_capacity:128 source)

let render_textured ~general ~filter ~address_u ~address_v ~blend =
  let texture=textured_fixture()and surface=ok(Raster2.Surface.create~width:32~height:24())in
  Raster2.Surface.clear surface 0x19324b9fl;
  let depth=if general then Some(ok(Raster2.Depth_stencil.create~width:32~height:24()))else None in
  let state={Raster2.Depth_stencil.depth_compare=Raster2.Depth_stencil.Always;depth_write=false;stencil=None}in
  let v x y u v={Raster2.Triangle.x=x;y;depth=0.25;color=0xb0d090c3l;u;v}in
  let texture=Some{Raster2.Triangle.texture;filter;address_u;address_v}in
  let clip={Raster2.Triangle.x=2;y=1;width=27;height=21}in
  Raster2.Triangle.draw~color:surface~depth~depth_state:state~blend~cull:Raster2.Triangle.Cull_none~clip~texture
    (v 1.3 2.7 (-0.4) 0.2)(v 29.1 3.2 1.7 (-0.3))(v 4.4 22.8 0.1 1.8);
  Bytes.copy(Raster2.Surface.bytes surface)

let () =
  let filters=[Raster2.Texture.Nearest;Bilinear;Trilinear]
  and addresses=[Raster2.Texture.Clamp;Repeat;Mirror]
  and blends=[Raster2.Composite.Copy;Source_over;Add;Multiply;Screen;Subtract]in
  List.iter(fun filter->List.iter(fun address_u->List.iter(fun address_v->List.iter(fun blend->
    let optimized=render_textured~general:false~filter~address_u~address_v~blend
    and reference=render_textured~general:true~filter~address_u~address_v~blend in
    if optimized<>reference then failwith"textured solid specialization pixel drift")blends)addresses)addresses)filters;
  let texture=textured_fixture()and surface=ok(Raster2.Surface.create~width:32~height:24())in
  let state={Raster2.Depth_stencil.depth_compare=Raster2.Depth_stencil.Always;depth_write=false;stencil=None}
  and clip={Raster2.Triangle.x=0;y=0;width=32;height=24}in
  let v x y u v={Raster2.Triangle.x=x;y;depth=0.;color=0xffffffffl;u;v}in
  let a=v 1. 1. 0. 0. and b=v 31. 1. 1. 0. and c=v 1. 23. 0. 1. in
  let texture=Some{Raster2.Triangle.texture;filter=Raster2.Texture.Nearest;address_u=Clamp;address_v=Clamp}in
  let measure depth=
  Gc.full_major();let before=Gc.allocated_bytes()in
  for _=1 to 100 do Raster2.Triangle.draw~color:surface~depth~depth_state:state
    ~blend:Raster2.Composite.Copy~cull:Raster2.Triangle.Cull_none~clip~texture a b c done;
  (Gc.allocated_bytes()-.before)/.100. in
  let optimized=measure None in
  let depth=ok(Raster2.Depth_stencil.create~width:32~height:24())in
  let reference=measure(Some depth)in
  Printf.printf"Raster2 textured allocation: general %.0f, solid %.0f bytes/draw\n"reference optimized;
  if optimized>256.||optimized*.100.>=reference then failwith"textured solid allocation regression"
