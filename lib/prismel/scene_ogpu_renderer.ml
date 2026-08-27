type error=Scene of Scene_raster2_lowering.error|Scene3 of Scene3_raster2_lowering.error|Backend of Ogpu.Error.t|Unsupported_resource|Unsupported_texture|Unsupported_shadow|Unsupported_samples of int|Destroyed
type draw_state={viewport:int*int*int*int;scissor:int*int*int*int;cull:Raster2.Triangle.cull;blend:Raster2.Composite.blend;textured:bool;depth_clear:float}
type t={execution:Scene_execution.t;mutable draw_states:draw_state array;mutable configuration:Ogpu.Surface.configuration;mutable destroyed:bool}
let backend=function Ok x->Ok x|Error e->Error(Backend e)
let create driver configuration=Result.map(fun execution->{execution;draw_states=[||];configuration;destroyed=false})(backend(Scene_execution.create driver configuration))
let float_bytes values=let out=Bytes.create(Array.length values*8)in Array.iteri(fun i x->Bytes.set_int64_le out(i*8)(Int64.bits_of_float x))values;out
let index_bytes values=let out=Bytes.create(Array.length values*4)in Array.iteri(fun i x->Bytes.set_int32_le out(i*4)(Int32.of_int x))values;out
let vertex3_bytes values=let stride=68 and out=Bytes.create(Array.length values*68)in let put o x=Bytes.set_int64_le out o(Int64.bits_of_float x)in Array.iteri(fun i(v:Raster2.Scene3_consumer.vertex)->let o=i*stride in put o v.position.x;put(o+8)v.position.y;put(o+16)v.position.z;put(o+24)v.normal.x;put(o+32)v.normal.y;put(o+40)v.normal.z;Bytes.set_int32_le out(o+48)v.color;put(o+52)v.u;put(o+60)v.v)values;out
let geometry_key(v:Raster2.Render_ir.geometry)=Digest.to_hex(Digest.string(Marshal.to_string(v.vertices,v.indices,v.color)[]))
let draw2 configuration(v:Raster2.Render_ir.geometry)=let mesh:Scene_execution.mesh={key=geometry_key v;vertices=float_bytes v.vertices;vertex_count=Array.length v.vertices/2;indices=index_bytes v.indices;index_count=Array.length v.indices}in let state:Scene_execution.state={viewport=(0,0,configuration.Ogpu.Surface.physical_width,configuration.physical_height);scissor=(0,0,configuration.physical_width,configuration.physical_height)}in{Scene_execution.mesh;state}
let default_scene3_resources={Scene3_raster2_lowering.texture=(fun _->Error Texture_error);shadow=(fun _->Error Shadow_error)}
let intersect(x,y,w,h)(a,b,c,d)=let l=max x a and t=max y b and r=min(x+w)(a+c)and q=min(y+h)(b+d)in l,t,max 0(r-l),max 0(q-t)
let split_scene value scene=let views=ref[]and bounds=(0,0,value.configuration.physical_width,value.configuration.physical_height)in let rec nodes clip xs=List.filter_map(node clip)xs and node clip=function
|Scene_description.View3d(camera,scene,viewport)->let viewport=Option.value viewport~default:bounds in let viewport=match clip with None->viewport|Some active->intersect active viewport in views:=Scene_description.View3d(camera,scene,Some viewport)::!views;None
|Group children->let children=nodes clip children in if children=[]then None else Some(Scene_description.Group children)
|Translate(x,y,children)->let children=nodes clip children in if children=[]then None else Some(Scene_description.Translate(x,y,children))
|Rotate(a,children)->let children=nodes clip children in if children=[]then None else Some(Scene_description.Rotate(a,children))
|Scale(x,y,children)->let children=nodes clip children in if children=[]then None else Some(Scene_description.Scale(x,y,children))
|Clip((x,y),w,h,children)->let own=x,y,w,h in let active=match clip with None->own|Some v->intersect v own in let children=nodes(Some active)children in if children=[]then None else Some(Scene_description.Clip((x,y),w,h,children))
|Blend(mode,children)->let children=nodes clip children in if children=[]then None else Some(Scene_description.Blend(mode,children))
|x->Some x in nodes None scene,List.rev!views
let draw3(draw:Raster2.Scene3_consumer.draw)=let key=Digest.to_hex(Digest.string(Marshal.to_string(Array.map(fun(v:Raster2.Scene3_consumer.vertex)->v.position,v.normal,v.color,v.u,v.v)draw.vertices,draw.indices)[]))in let mesh:Scene_execution.mesh={key;vertices=vertex3_bytes draw.vertices;vertex_count=Array.length draw.vertices;indices=index_bytes draw.indices;index_count=Array.length draw.indices}and state:Scene_execution.state={viewport=(int_of_float draw.viewport.x,int_of_float draw.viewport.y,int_of_float draw.viewport.width,int_of_float draw.viewport.height);scissor=(draw.scissor.x,draw.scissor.y,draw.scissor.width,draw.scissor.height)}in{Scene_execution.mesh;state},{viewport=state.viewport;scissor=state.scissor;cull=draw.cull;blend=draw.blend;textured=Option.is_some draw.texture;depth_clear=1.}
let render_with_scene3 value resources scene=if value.destroyed then Error Destroyed else let scene2,views=split_scene value scene in match Scene_raster2_lowering.lower scene2 with Error(Unsupported _)->Error Unsupported_resource|Error e->Error(Scene e)|Ok ir->let draws2=Raster2.Render_ir.commands ir|>Array.to_list|>List.filter_map(function Raster2.Render_ir.Geometry g->Some(draw2 value.configuration g)|_->None)in let rec lower ds ss=function []->Ok(List.rev ds,List.rev ss)|Scene_description.View3d(camera,scene,Some viewport)::rest->let node=Scene_description.View3d(camera,scene,Some viewport)in(match Scene3_raster2_lowering.lower_view3d~resources~default_viewport:viewport node with Error e->Error(Scene3 e)|Ok prepared when prepared.samples<>1->Error(Unsupported_samples prepared.samples)|Ok prepared when Array.exists(fun(draw:Raster2.Scene3_consumer.draw)->Array.exists Option.is_some draw.shadows)prepared.draws->Error Unsupported_shadow|Ok prepared when Array.exists(fun(draw:Raster2.Scene3_consumer.draw)->Option.is_some draw.texture)prepared.draws->Error Unsupported_texture|Ok prepared when Array.exists(fun(draw:Raster2.Scene3_consumer.draw)->Option.is_some draw.program)prepared.draws->Error Unsupported_resource|Ok prepared->let pairs=Array.to_list prepared.draws|>List.map draw3 in lower(List.rev_append(List.map fst pairs)ds)(List.rev_append(List.map(fun(_,s)->{s with depth_clear=prepared.clear_depth})pairs)ss)rest)|_::_->assert false in Result.bind(lower[][]views)(fun(draws3,states)->value.draw_states<-Array.of_list states;backend(Scene_execution.render value.execution(draws2@draws3)))
let render value scene=render_with_scene3 value default_scene3_resources scene
let resize value configuration=if value.destroyed then Error Destroyed else Result.map(fun()->value.configuration<-configuration)(backend(Scene_execution.resize value.execution configuration))
let upload_bytes value=Scene_execution.upload_bytes value.execution
let destroy value=if value.destroyed then Ok()else(value.destroyed<-true;backend(Scene_execution.destroy value.execution))
let self_test()=let get=function Ok x->x|Error _->failwith"OGPU renderer fixture"in let configuration:Ogpu.Surface.configuration={logical_width=16;logical_height=16;physical_width=16;physical_height=16;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in let driver,control=Ogpu.Backend_mock.create()in let renderer=get(create driver configuration)in let style:Scene_description.style={fill=Some Color.white;stroke=None}in let scene=[Scene_description.Clear Color.black;Triangle((1,1),(8,1),(4,8),style)]in for _=1 to 600 do ignore(get(render renderer scene))done;let first=upload_bytes renderer in if first<=0L then failwith"mesh not uploaded";ignore(get(render renderer scene));if upload_bytes renderer<>first then failwith"stable mesh reuploaded";
 let mesh=Mesh.create_exn~normals:[Vec3.unit_z;Vec3.unit_z;Vec3.unit_z]
   [Vec3.create(-0.5)(-0.5)0.;Vec3.create 0.5(-0.5)0.;Vec3.create 0. 0.5 0.]in
 let shader=Shader3.create~vertex:Shader3.default_vertex~fragment:Shader3.default_fragment()in
 let camera=Camera.orthographic~height:2.~at:(Vec3.create 0. 0. 2.)~target:Vec3.zero()in
 let shader_scene=[Scene_description.View3d(camera,Scene3.create[Scene3.mesh~material:(Material.unlit Color.white)~shader mesh],None)]in
 (match render renderer shader_scene with Error Unsupported_resource->()|_->failwith"native Shader3 was not explicitly rejected");
  if upload_bytes renderer<>first then failwith"rejected native Shader3 mutated uploads";
 let sampled_scene=[Scene_description.View3d(camera,Scene3.create~samples:4
   [Scene3.mesh~material:(Material.unlit Color.white)mesh],None)]in
 (match render renderer sampled_scene with Error(Unsupported_samples 4)->()|_->failwith"native unsupported sample count was not explicit");
 if upload_bytes renderer<>first then failwith"rejected native multisample mutated uploads";
 let owned=Scene3_raster2_resources.create()in let owned_callbacks=Scene3_raster2_resources.callbacks owned in
 let texture=Texture.create_exn~width:1~height:1[Color.white]in
 let textured=[Scene_description.View3d(camera,Scene3.create[Scene3.mesh
   ~material:(Material.unlit Color.white)~texture:(Scene3.textured texture)mesh],None)]in
 (match render_with_scene3 renderer owned_callbacks textured with Error Unsupported_texture->()|_->failwith"native texture fallback was silent");
 let light=Light.directional~direction:(Vec3.create 0. 0.(-1.))()in
 let shadow=Shadow3.create~filter:Shadow3.Pcf_5x5~light~camera~width:1~height:1~depths:[|0.5|]()in
 let shadowed=[Scene_description.View3d(camera,Scene3.create~lights:[light]~shadows:[shadow]
   [Scene3.mesh~material:(Material.matte Color.white)mesh],None)]in
 (match render_with_scene3 renderer owned_callbacks shadowed with Error Unsupported_shadow->()|_->failwith"native shadow fallback was silent");
 Scene3_raster2_resources.destroy owned;
 if upload_bytes renderer<>first then failwith"rejected native resources mutated uploads";
 get(destroy renderer);if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"renderer leaked"
let()=match Sys.getenv_opt"PRISMEL_TEST_SCENE_OGPU_RENDERER"with Some"1"->self_test()|_->()
