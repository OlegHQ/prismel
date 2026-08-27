type vertex={position:Scene3_lighting.vec3;normal:Scene3_lighting.vec3;color:int32;u:float;v:float}
type shading=Flat|Smooth
type draw={matrix:float array;viewport:Scene3.viewport;scissor:Triangle.clip;topology:Scene3.topology;vertices:vertex array;indices:int array;lighting:Scene3_lighting.descriptor;shading:shading;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend}
type target={color:Surface.t;depth:Depth_stencil.t option;multisample:Multisample.t option}
type error=Invalid_target|Invalid_vertex|Lighting_error of Scene3_lighting.error|Geometry_error of Scene3.error
type prepared={geometry:Scene3.prepared;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend}
let finite x=Float.is_finite x
let render ~target ~clear ~clear_depth ~draws=
 let width=Surface.width target.color and height=Surface.height target.color in
 let valid_depth=match target.depth with None->true|Some d->Depth_stencil.width d=width&&Depth_stencil.height d=height in
 let valid_msaa=match target.multisample with None->true|Some m->Multisample.width m=width&&Multisample.height m=height in
 if not valid_depth||not valid_msaa||not(finite clear_depth)||clear_depth<0.||clear_depth>1. then Error Invalid_target else
 let failure=ref None and prepared=ref[]in let fail e=if !failure=None then failure:=Some e in
 Array.iter(fun draw->match Scene3_lighting.prepare draw.lighting with Error e->fail(Lighting_error e)|Ok lighting->
  if Array.exists(fun v->let p=v.position and n=v.normal in not(finite p.x&&finite p.y&&finite p.z&&finite n.x&&finite n.y&&finite n.z&&finite v.u&&finite v.v))draw.vertices then fail Invalid_vertex else
  let flat_normal ia ib ic=let a=draw.vertices.(ia).position and b=draw.vertices.(ib).position and c=draw.vertices.(ic).position in let ux=b.x-.a.x and uy=b.y-.a.y and uz=b.z-.a.z and vx=c.x-.a.x and vy=c.y-.a.y and vz=c.z-.a.z in let x=uy*.vz-.uz*.vy and y=uz*.vx-.ux*.vz and z=ux*.vy-.uy*.vx in let length=sqrt(x*.x+.y*.y+.z*.z)in if length=0. then {Scene3_lighting.x=0.;y=0.;z=1.}else{x=x/.length;y=y/.length;z=z/.length}in
  let normals=Array.map(fun v->v.normal)draw.vertices in(match draw.shading with Flat->let count=match draw.topology with Scene3.Triangle_list->Array.length draw.indices/3|Triangle_strip|Triangle_fan->max 0(Array.length draw.indices-2)in for i=0 to count-1 do let a,b,c=match draw.topology with Triangle_list->draw.indices.(3*i),draw.indices.(3*i+1),draw.indices.(3*i+2)|Triangle_strip->draw.indices.(i),draw.indices.(i+1),draw.indices.(i+2)|Triangle_fan->draw.indices.(0),draw.indices.(i+1),draw.indices.(i+2)in if a>=0&&b>=0&&c>=0&&a<Array.length normals&&b<Array.length normals&&c<Array.length normals then let n=flat_normal a b c in normals.(a)<-n;normals.(b)<-n;normals.(c)<-n done|Smooth->());
  let vertices=Array.mapi(fun i v->let color=Scene3_lighting.shade lighting~position:v.position~normal:normals.(i)~view:{Scene3_lighting.x=0.;y=0.;z=1.}~front_facing:true~texture:None~fog_distance:(abs_float v.position.z)in{Scene3.x=v.position.x;y=v.position.y;z=v.position.z;color;u=v.u;v=v.v})draw.vertices in
  match Scene3.prepare~matrix:draw.matrix~viewport:draw.viewport~scissor:draw.scissor~topology:draw.topology~vertices~indices:draw.indices with Error e->fail(Geometry_error e)|Ok geometry->prepared:={geometry;texture=draw.texture;cull=draw.cull;blend=draw.blend}::!prepared)draws;
 match !failure with Some e->Error e|None->
 let color_bytes=Bytes.copy(Surface.bytes target.color)in match Surface.of_bytes~width~height~pitch:(Surface.pitch target.color)color_bytes with Error _->Error Invalid_target|Ok color->
 let depth=match target.depth with None->None|Some source->let bytes=Bytes.copy(Depth_stencil.bytes source)in(match Depth_stencil.of_bytes~width~height~pitch:(Depth_stencil.pitch source)bytes with Ok value->Some(source,value)|Error _->None)in
 Surface.clear color clear;(match depth with None->()|Some(_,d)->ignore(Depth_stencil.clear d~depth:clear_depth~stencil:0));
 let depth_state={Depth_stencil.depth_compare=Less;depth_write=true;stencil=None}in
 List.iter(fun draw->Array.iter(fun(a,b,c)->Triangle.draw~color~depth:(Option.map snd depth)~depth_state~blend:draw.blend~cull:draw.cull~clip:draw.geometry.clip~texture:draw.texture a b c)draw.geometry.triangles)(List.rev !prepared);
 Bytes.blit color_bytes 0(Surface.bytes target.color)0(Bytes.length color_bytes);(match target.depth,depth with Some destination,Some(_,source)->Bytes.blit(Depth_stencil.bytes source)0(Depth_stencil.bytes destination)0(Bytes.length(Depth_stencil.bytes source))|_->());
 (match target.multisample with None->()|Some msaa->ignore(Multisample.clear msaa~color:clear~depth:clear_depth);for y=0 to height-1 do for x=0 to width-1 do match Surface.get_rgba color~x~y with Error _->()|Ok pixel->for sample=0 to Multisample.samples msaa-1 do ignore(Multisample.test_and_write msaa~compare:Always~depth_write:false~x~y~sample~depth:clear_depth~color:pixel)done done done;ignore(Multisample.resolve msaa target.color));Ok()
