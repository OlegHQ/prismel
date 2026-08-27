type vertex={position:Scene3_lighting.vec3;normal:Scene3_lighting.vec3;color:int32;u:float;v:float}
type shading=Flat|Smooth
type mode=Faces|Wireframe|Vertices
type draw={matrix:float array;viewport:Scene3.viewport;scissor:Triangle.clip;topology:Scene3.topology;vertices:vertex array;indices:int array;lighting:Scene3_lighting.descriptor;shadows:Shadow_map.prepared option array;shading:shading;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend;depth_stencil:Depth_stencil.state;mode:mode;line_width:float;point_size:float}
type target={color:Surface.t;depth:Depth_stencil.t option;multisample:Multisample.t option}
type error=Invalid_target|Invalid_vertex|Lighting_error of Scene3_lighting.error|Geometry_error of Scene3.error
type prepared={geometry:Scene3.prepared;texture:Triangle.texture option;cull:Triangle.cull;blend:Composite.blend;depth_stencil:Depth_stencil.state;mode:mode;line_width:float;point_size:float}
let finite x=Float.is_finite x
let render ~target ~clear ~clear_depth ~clear_stencil ~draws=
 let width=Surface.width target.color and height=Surface.height target.color in
 let valid_depth=match target.depth with None->true|Some d->Depth_stencil.width d=width&&Depth_stencil.height d=height in
 let valid_msaa=match target.multisample with None->true|Some m->Multisample.width m=width&&Multisample.height m=height in
 if not valid_depth||not valid_msaa||not(finite clear_depth)||clear_depth<0.||clear_depth>1.||clear_stencil<0||clear_stencil>255 then Error Invalid_target else
 let failure=ref None and prepared=ref[]in let fail e=if !failure=None then failure:=Some e in
 Array.iter(fun draw->match Scene3_lighting.prepare_with_shadows draw.lighting draw.shadows with Error e->fail(Lighting_error e)|Ok lighting->
  if Array.exists(fun v->let p=v.position and n=v.normal in not(finite p.x&&finite p.y&&finite p.z&&finite n.x&&finite n.y&&finite n.z&&finite v.u&&finite v.v))draw.vertices then fail Invalid_vertex else
  let invalid_index=Array.find_opt(fun index->index<0||index>=Array.length draw.vertices)draw.indices in
  if invalid_index<>None then fail(Geometry_error(Scene3.Invalid_index(Option.get invalid_index)))else
  if draw.topology=Scene3.Triangle_list&&Array.length draw.indices mod 3<>0 then fail(Geometry_error Scene3.Invalid_cardinality)else
  let flat_normal a b c=let a=draw.vertices.(a).position and b=draw.vertices.(b).position and c=draw.vertices.(c).position in let ux=b.x-.a.x and uy=b.y-.a.y and uz=b.z-.a.z and vx=c.x-.a.x and vy=c.y-.a.y and vz=c.z-.a.z in let x=uy*.vz-.uz*.vy and y=uz*.vx-.ux*.vz and z=ux*.vy-.uy*.vx in let length=sqrt(x*.x+.y*.y+.z*.z)in if length=0. then {Scene3_lighting.x=0.;y=0.;z=1.}else{x=x/.length;y=y/.length;z=z/.length}in
  let source_vertices,source_indices,source_topology=match draw.shading,draw.topology with
  | Flat,(Scene3.Triangle_list|Triangle_strip|Triangle_fan as topology)->
    let count=match topology with Triangle_list->Array.length draw.indices/3|Triangle_strip|Triangle_fan->max 0(Array.length draw.indices-2)|_->assert false in
    let vertices=if count=0 then[||]else Array.make(count*3)draw.vertices.(0)in
    for i=0 to count-1 do let a,b,c=match topology with Triangle_list->draw.indices.(3*i),draw.indices.(3*i+1),draw.indices.(3*i+2)|Triangle_strip->if i land 1=0 then draw.indices.(i),draw.indices.(i+1),draw.indices.(i+2)else draw.indices.(i+1),draw.indices.(i),draw.indices.(i+2)|Triangle_fan->draw.indices.(0),draw.indices.(i+1),draw.indices.(i+2)|_->assert false in let normal=flat_normal a b c in vertices.(3*i)<-{draw.vertices.(a)with normal};vertices.(3*i+1)<-{draw.vertices.(b)with normal};vertices.(3*i+2)<-{draw.vertices.(c)with normal}done;
    vertices,Array.init(count*3)(fun i->i),Scene3.Triangle_list
  | _->draw.vertices,draw.indices,draw.topology in
  let vertices=Array.map(fun v->let color=Scene3_lighting.shade lighting~position:v.position~normal:v.normal~view:{Scene3_lighting.x=0.;y=0.;z=1.}~front_facing:true~texture:None~fog_distance:(abs_float v.position.z)in{Scene3.x=v.position.x;y=v.position.y;z=v.position.z;color;u=v.u;v=v.v})source_vertices in
  match Scene3.prepare~matrix:draw.matrix~viewport:draw.viewport~scissor:draw.scissor~topology:source_topology~vertices~indices:source_indices with Error e->fail(Geometry_error e)|Ok geometry->prepared:={geometry;texture=draw.texture;cull=draw.cull;blend=draw.blend;depth_stencil=draw.depth_stencil;mode=draw.mode;line_width=draw.line_width;point_size=draw.point_size}::!prepared)draws;
 match !failure with Some e->Error e|None->
 let color_bytes=Bytes.copy(Surface.bytes target.color)in match Surface.of_bytes~width~height~pitch:(Surface.pitch target.color)color_bytes with Error _->Error Invalid_target|Ok color->
 let depth=match target.depth with None->None|Some source->let bytes=Bytes.copy(Depth_stencil.bytes source)in(match Depth_stencil.of_bytes~width~height~pitch:(Depth_stencil.pitch source)bytes with Ok value->Some(source,value)|Error _->None)in
 Surface.clear color clear;(match depth with None->()|Some(_,d)->ignore(Depth_stencil.clear d~depth:clear_depth~stencil:clear_stencil));
 let raster_depth=Option.map snd depth in
 let vertex_key(v:Triangle.vertex)=Int64.bits_of_float v.x,Int64.bits_of_float v.y,Int64.bits_of_float v.depth in
 let draw_line draw a b=Triangle.draw_line~color~depth:raster_depth~depth_state:draw.depth_stencil~blend:draw.blend~clip:draw.geometry.clip~texture:draw.texture~width:draw.line_width a b in
 let draw_point draw v=Triangle.draw_point~color~depth:raster_depth~depth_state:draw.depth_stencil~blend:draw.blend~clip:draw.geometry.clip~texture:draw.texture~size:draw.point_size v in
 List.iter(fun draw->match draw.mode with
  | Faces->Array.iter(fun(a,b,c)->Triangle.draw~color~depth:raster_depth~depth_state:draw.depth_stencil~blend:draw.blend~cull:draw.cull~clip:draw.geometry.clip~texture:draw.texture a b c)draw.geometry.triangles;Array.iter(fun(a,b)->draw_line draw a b)draw.geometry.lines;Array.iter(draw_point draw)draw.geometry.points
  | Wireframe->let seen=Hashtbl.create(Array.length draw.geometry.triangles*3+Array.length draw.geometry.lines)in let unique_line u v=let a=vertex_key u and b=vertex_key v in let key=if compare a b<=0 then a,b else b,a in if not(Hashtbl.mem seen key)then(Hashtbl.add seen key();draw_line draw u v)in Array.iter(fun(a,b,c)->if Triangle.visible~cull:draw.cull a b c then List.iter(fun(u,v)->unique_line u v)[a,b;b,c;c,a])draw.geometry.triangles;Array.iter(fun(a,b)->unique_line a b)draw.geometry.lines;Array.iter(draw_point draw)draw.geometry.points
  | Vertices->let seen=Hashtbl.create(Array.length draw.geometry.triangles*3+Array.length draw.geometry.lines*2+Array.length draw.geometry.points)in let unique_point v=let key=vertex_key v in if not(Hashtbl.mem seen key)then(Hashtbl.add seen key();draw_point draw v)in Array.iter(fun(a,b,c)->if Triangle.visible~cull:draw.cull a b c then List.iter unique_point[a;b;c])draw.geometry.triangles;Array.iter(fun(a,b)->unique_point a;unique_point b)draw.geometry.lines;Array.iter unique_point draw.geometry.points)(List.rev !prepared);
 Bytes.blit color_bytes 0(Surface.bytes target.color)0(Bytes.length color_bytes);(match target.depth,depth with Some destination,Some(_,source)->Bytes.blit(Depth_stencil.bytes source)0(Depth_stencil.bytes destination)0(Bytes.length(Depth_stencil.bytes source))|_->());
 (match target.multisample with None->()|Some msaa->ignore(Multisample.clear msaa~color:clear~depth:clear_depth);for y=0 to height-1 do for x=0 to width-1 do match Surface.get_rgba color~x~y with Error _->()|Ok pixel->for sample=0 to Multisample.samples msaa-1 do ignore(Multisample.test_and_write msaa~compare:Always~depth_write:false~x~y~sample~depth:clear_depth~color:pixel)done done done;ignore(Multisample.resolve msaa target.color));Ok()
