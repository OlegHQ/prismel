open Raster2
let ok=function Ok x->x|Error _->failwith"texture error"
let make frame=let surface=ok(Surface.create~width:3~height:5~pitch:16())in Bytes.fill(Surface.bytes surface)0(Bytes.length(Surface.bytes surface))'\x7f';for y=0 to 4 do for x=0 to 2 do ignore(Surface.set_rgba surface~x~y(Int32.of_int((((frame+x*40)land 255)lsl 24)lor(y*40 lsl 16)lor 0x00ff)))done done;ok(Texture.create~color_space:Texture.Linear~hard_capacity:1024 surface)
let render frame=let texture=make frame in assert(Texture.levels texture=4&&Texture.storage_bytes texture=96);let level1=ok(Texture.level texture 1)and level2=ok(Texture.level texture 2)in if Surface.width level1<>2||Surface.height level1<>3||Surface.width level2<>1||Surface.height level2<>2 then failwith"odd mip extent";let values=[Texture.sample texture~address_u:Clamp~address_v:Clamp~filter:Nearest~u:(-1.)~v:2.~lod:0.;Texture.sample texture~address_u:Repeat~address_v:Mirror~filter:Bilinear~u:1.2~v:(-0.3)~lod:1.;Texture.sample texture~address_u:Mirror~address_v:Repeat~filter:Trilinear~u:2.4~v:1.7~lod:1.5]in Marshal.to_bytes(List.map ok values)[]
let render_triangle frame filter address_u address_v =
  let texture = make frame in
  let color = ok (Surface.create ~width:8 ~height:8 ()) in
  Surface.clear color 0x000000ffl;
  let vertex x y u v = { Triangle.x; y; depth=0.5; color=0xffffffffl; u; v } in
  Triangle.draw ~color ~depth:None
    ~depth_state:{Depth_stencil.depth_compare=Always;depth_write=false;stencil=None}
    ~blend:Composite.Copy ~cull:Triangle.Cull_none
    ~clip:{Triangle.x=0;y=0;width=8;height=8}
    ~texture:(Some{Triangle.texture;filter;address_u;address_v})
    (vertex 2. 2. (-1.25) (-0.75)) (vertex 5. 2. 2.25 (-0.75))
    (vertex 2. 5. (-1.25) 2.5);
  Bytes.copy (Surface.bytes color)
let ()=List.iter(fun frame->let expected=render frame in let workers=Array.init 4(fun _->Domain.spawn(fun()->render frame))in Array.iter(fun worker->assert(Domain.join worker=expected))workers)[1;600];
  let states=[Texture.Nearest,Texture.Clamp,Texture.Repeat;Texture.Bilinear,Texture.Repeat,Texture.Mirror;Texture.Trilinear,Texture.Mirror,Texture.Clamp]in
  List.iter(fun(filter,address_u,address_v)->List.iter(fun frame->let expected=render_triangle frame filter address_u address_v in let workers=Array.init 4(fun _->Domain.spawn(fun()->render_triangle frame filter address_u address_v))in Array.iter(fun worker->if Domain.join worker<>expected then failwith"triangle texture domain drift")workers)[1;600])states;
  let nearest=render_triangle 1 Texture.Nearest Texture.Clamp Texture.Clamp and trilinear=render_triangle 1 Texture.Trilinear Texture.Repeat Texture.Mirror in if nearest=trilinear then failwith"triangle sampling state ignored";
  let seam_surface=ok(Surface.create~width:2~height:1())in ignore(Surface.set_rgba seam_surface~x:0~y:0 0xff0000ffl);ignore(Surface.set_rgba seam_surface~x:1~y:0 0x0000ffffl);let seam=ok(Texture.create~color_space:Linear~hard_capacity:12 seam_surface)in let clamp=ok(Texture.sample seam~address_u:Clamp~address_v:Clamp~filter:Bilinear~u:0.~v:0.5~lod:0.)and repeat=ok(Texture.sample seam~address_u:Repeat~address_v:Clamp~filter:Bilinear~u:0.~v:0.5~lod:0.)in if clamp<>0xff0000ffl||repeat<>0x800080ffl then failwith"bilinear wrap seam";
  let dimensions=[|3,5;2,3;1,2;1,1|]and colors=[|0x000000ffl;0xff0000ffl;0x0000ffffl;0xffffffffl|]in let explicit=Array.mapi(fun i(w,h)->let level=ok(Surface.create~width:w~height:h())in Surface.clear level colors.(i);level)dimensions|>Texture.create_levels~color_space:Linear~hard_capacity:96|>ok in let level1=ok(Texture.sample explicit~address_u:Repeat~address_v:Mirror~filter:Nearest~u:2.25~v:(-0.25)~lod:1.)and blend=ok(Texture.sample explicit~address_u:Clamp~address_v:Clamp~filter:Trilinear~u:0.5~v:0.5~lod:1.5)in if level1<>0xff0000ffl||blend<>0x800080ffl then failwith"explicit odd mip identity";
  List.iter(fun filter->List.iter(fun address_u->List.iter(fun address_v->List.iter(fun(u,v,lod)->let checked=ok(Texture.sample explicit~address_u~address_v~filter~u~v~lod)and direct=Texture.Private.sample_int_unchecked explicit~address_u~address_v~filter[|u;v;lod;0.;0.;0.|]in if checked<>Int32.of_int direct then failwith"private sampler semantic drift")[-1.25,-0.75,0.;0.2,0.8,1.;2.4,1.7,1.5]) [Clamp;Repeat;Mirror]) [Clamp;Repeat;Mirror]) [Nearest;Bilinear;Trilinear];
  List.iter(fun address_u->List.iter(fun address_v->List.iter(fun(x,y)->let direct=Texture.Private.texel_int_unchecked explicit~level:1~address_u~address_v~x~y and w,h=2,3 in let expected=ok(Texture.sample explicit~address_u~address_v~filter:Nearest~u:((float x+.0.25)/.float w)~v:((float y+.0.25)/.float h)~lod:1.)in if expected<>Int32.of_int direct then failwith"private texel semantic drift")[-5,-4;0,0;1,2;4,6]) [Clamp;Repeat;Mirror]) [Clamp;Repeat;Mirror];
  Gc.full_major();let allocated=Gc.allocated_bytes()in for index=1 to 100_000 do ignore(Texture.Private.texel_int_unchecked explicit~level:1~address_u:Repeat~address_v:Mirror~x:index~y:(-index))done;let per_sample=(Gc.allocated_bytes()-.allocated)/.100_000. in if per_sample>1. then failwith(Printf.sprintf"private texel allocated %.2f bytes/sample"per_sample);
  let srgb_source=ok(Surface.create~width:3~height:5())in Bytes.blit(Surface.bytes(ok(Texture.level(make 37)0)))0(Surface.bytes srgb_source)0(Bytes.length(Surface.bytes srgb_source));
  let srgb_sample=ok(Texture.create~color_space:Srgb~hard_capacity:1024 srgb_source)in
  let maxima=Array.make 2 0. and coordinates=[|0.37;0.61;1.25;0.;0.;0.|]in
  List.iteri(fun space texture->List.iter(fun filter->List.iter(fun address_u->List.iter(fun address_v->
    Gc.full_major();let before=Gc.allocated_bytes()in
    for _=1 to 100_000 do
      ignore(Texture.Private.sample_int_unchecked texture~address_u~address_v~filter coordinates)done;
    maxima.(space)<-max maxima.(space)((Gc.allocated_bytes()-.before)/.100_000.)) [Clamp;Repeat;Mirror]) [Clamp;Repeat;Mirror]) [Nearest;Bilinear;Trilinear]) [explicit;srgb_sample];
  Printf.printf"Raster2 private sampler maximum allocation: Linear %.2f, sRGB %.2f bytes/sample\n"maxima.(0)maxima.(1);
  if maxima.(0)>64.1||maxima.(1)>400.1 then failwith(Printf.sprintf"private sampler allocated %.2f/%.2f bytes/sample"maxima.(0)maxima.(1));
  let source=ok(Surface.create~width:1~height:1())in(match Texture.create~color_space:Srgb~hard_capacity:3 source with Error Texture.Capacity_exceeded->()|_->failwith"capacity");let srgb=ok(Texture.create~color_space:Srgb~hard_capacity:4 source)in(match Texture.sample srgb~address_u:Clamp~address_v:Clamp~filter:Nearest~u:nan~v:0.~lod:0. with Error Texture.Invalid_coordinate->()|_->failwith"nan");print_endline"Raster2 deterministic texture mip sampling passed"
