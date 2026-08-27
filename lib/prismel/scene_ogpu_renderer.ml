type error=Scene of Scene_raster2_lowering.error|Scene3 of Scene3_raster2_lowering.error|Backend of Ogpu.Error.t|Unsupported_resource|Unsupported_texture|Unsupported_samples of int|Destroyed
type draw_state={viewport:int*int*int*int;scissor:int*int*int*int;cull:Raster2.Triangle.cull;blend:Raster2.Composite.blend;texture:Raster2.Triangle.texture option;depth_clear:float}
type resource_draw=Scene_execution.pipeline_family*Ogpu.Pipeline.blend*Scene_execution.sampled_texture option*Scene_execution.auxiliary_resource option*int*Scene_execution.draw
type prepared_scene={source:Scene_description.t;resources:Scene3_raster2_lowering.resources;draws:resource_draw list;states:draw_state array;identity:string;version:int64}
type t={execution:Scene_execution.t;mutable draw_states:draw_state array;mutable configuration:Ogpu.Surface.configuration;mutable prepared_scene:prepared_scene option;mutable next_version:int64;mutable destroyed:bool}
let backend=function Ok x->Ok x|Error e->Error(Backend e)
let create driver configuration=Result.map(fun execution->{execution;draw_states=[||];configuration;prepared_scene=None;next_version=0L;destroyed=false})(backend(Scene_execution.create_variants driver configuration))
let float_bytes values=let out=Bytes.create(Array.length values*8)in Array.iteri(fun i x->Bytes.set_int64_le out(i*8)(Int64.bits_of_float x))values;out
let transform_uniforms (draw:Raster2.Scene3_consumer.draw)=
  let matrix values=Mat4.of_rows(values.(0),values.(1),values.(2),values.(3))(values.(4),values.(5),values.(6),values.(7))(values.(8),values.(9),values.(10),values.(11))(values.(12),values.(13),values.(14),values.(15))in
  let normal=match Mat4.inverse(matrix draw.model_matrix)with None->Mat4.identity|Some inverse->Mat4.transpose inverse in
  let normal=Array.init 16(fun index->Mat4.get normal~row:(index/4)~column:(index mod 4))in
  let values=Array.make 1364 0. in
  Array.blit draw.matrix 0 values 0 16;Array.blit draw.model_matrix 0 values 16 16;Array.blit normal 0 values 32 16;
  values.(48)<-draw.camera_position.x;values.(49)<-draw.camera_position.y;values.(50)<-draw.camera_position.z;
  let color offset(c:Raster2.Scene3_lighting.color)=values.(offset)<-c.r;values.(offset+1)<-c.g;values.(offset+2)<-c.b;values.(offset+3)<-c.a in
  let lighting=draw.lighting and material=draw.lighting.material in color 52 material.ambient;color 56 material.diffuse;color 60 material.specular;color 64 material.emissive;values.(68)<-material.shininess;color 69 lighting.ambient;values.(73)<-float(Array.length lighting.lights);values.(74)<-(if lighting.two_sided then 1. else 0.);values.(75)<-(if lighting.separate_specular then 1. else 0.);
  (match lighting.fog with No_fog->()|Linear fog->values.(76)<-1.;color 77 fog.color;values.(81)<-fog.near;values.(82)<-fog.far|Exponential fog->values.(76)<-2.;color 77 fog.color;values.(81)<-fog.density|Exponential_squared fog->values.(76)<-3.;color 77 fog.color;values.(81)<-fog.density);
  Array.iteri(fun index light->let offset=84+index*20 in match light with
    |Raster2.Scene3_lighting.Directional light->values.(offset)<-0.;values.(offset+1)<-light.direction.x;values.(offset+2)<-light.direction.y;values.(offset+3)<-light.direction.z;color(offset+4)light.color;values.(offset+8)<-light.intensity
    |Point light->values.(offset)<-1.;values.(offset+1)<-light.position.x;values.(offset+2)<-light.position.y;values.(offset+3)<-light.position.z;color(offset+4)light.color;values.(offset+8)<-light.intensity;values.(offset+9)<-light.attenuation.constant;values.(offset+10)<-light.attenuation.linear;values.(offset+11)<-light.attenuation.quadratic
    |Spot light->values.(offset)<-2.;values.(offset+1)<-light.position.x;values.(offset+2)<-light.position.y;values.(offset+3)<-light.position.z;color(offset+4)light.color;values.(offset+8)<-light.intensity;values.(offset+9)<-light.direction.x;values.(offset+10)<-light.direction.y;values.(offset+11)<-light.direction.z;values.(offset+12)<-light.inner_cos;values.(offset+13)<-light.outer_cos;values.(offset+14)<-light.concentration;values.(offset+15)<-light.attenuation.constant;values.(offset+16)<-light.attenuation.linear;values.(offset+17)<-light.attenuation.quadratic
    |Area light->values.(offset)<-3.;values.(offset+1)<-light.position.x;values.(offset+2)<-light.position.y;values.(offset+3)<-light.position.z;color(offset+4)light.color;values.(offset+8)<-light.intensity;values.(offset+9)<-light.direction.x;values.(offset+10)<-light.direction.y;values.(offset+11)<-light.direction.z;values.(offset+12)<-light.width;values.(offset+13)<-light.height;values.(offset+14)<-float light.samples;values.(offset+15)<-light.attenuation.constant;values.(offset+16)<-light.attenuation.linear;values.(offset+17)<-light.attenuation.quadratic)lighting.lights;
  let bytes=Bytes.create 5456 in Array.iteri(fun index value->Bytes.set_int32_le bytes(index*4)(Int32.bits_of_float value))values;bytes
let index_bytes values=let out=Bytes.create(Array.length values*4)in Array.iteri(fun i x->Bytes.set_int32_le out(i*4)(Int32.of_int x))values;out
let vertex3_bytes values=let stride=68 and out=Bytes.create(Array.length values*68)in let put o x=Bytes.set_int64_le out o(Int64.bits_of_float x)in Array.iteri(fun i(v:Raster2.Scene3_consumer.vertex)->let o=i*stride in put o v.position.x;put(o+8)v.position.y;put(o+16)v.position.z;put(o+24)v.normal.x;put(o+32)v.normal.y;put(o+40)v.normal.z;Bytes.set_int32_le out(o+48)v.color;put(o+52)v.u;put(o+60)v.v)values;out
let geometry_key(v:Raster2.Render_ir.geometry)=Digest.to_hex(Digest.string(Marshal.to_string(v.vertices,v.indices,v.color)[]))
let pipeline_blend=function Raster2.Composite.Copy|Replace->Ogpu.Pipeline.Replace|Source_over|Alpha->Alpha|Add->Add|Multiply->Multiply|Screen->Screen|Subtract->Subtract
let pipeline_cull=function Raster2.Triangle.Cull_none->Ogpu.Render_pass.Cull_none|Front->Cull_front|Back->Cull_back
let pipeline_comparison=function Raster2.Depth_stencil.Never->Ogpu.Render_pass.Never|Less->Less|Equal->Equal|Less_equal->Less_equal|Greater->Greater|Not_equal->Not_equal|Greater_equal->Greater_equal|Always->Always
let pipeline_stencil_operation=function Raster2.Depth_stencil.Keep->Ogpu.Render_pass.Keep|Zero->Zero|Replace->Replace|Increment_clamp->Increment_clamp|Decrement_clamp->Decrement_clamp|Invert->Invert|Increment_wrap->Increment_wrap|Decrement_wrap->Decrement_wrap
let pipeline_stencil=function None->None|Some(state:Raster2.Depth_stencil.stencil)when state.compare=Always&&state.fail=Keep&&state.depth_fail=Keep&&state.pass=Keep->None|Some state->let face:Ogpu.Render_pass.stencil_face={compare=pipeline_comparison state.compare;stencil_fail=pipeline_stencil_operation state.fail;depth_fail=pipeline_stencil_operation state.depth_fail;pass=pipeline_stencil_operation state.pass;read_mask=Int32.of_int state.read_mask;write_mask=Int32.of_int state.write_mask}in Some{Ogpu.Render_pass.front=face;back=face;front_reference=Int32.of_int state.reference;back_reference=Int32.of_int state.reference}
let sampled_texture (value:Raster2.Triangle.texture)=
  let texture=value.texture in
  let levels=Array.init(Raster2.Texture.levels texture)(fun index->match Raster2.Texture.level texture index with Error _->assert false|Ok surface->{Scene_execution.width=Raster2.Surface.width surface;height=Raster2.Surface.height surface;bytes=Bytes.copy(Raster2.Surface.bytes surface)})in
  let address=function Raster2.Texture.Clamp->Ogpu.Types.Clamp_to_edge|Repeat->Ogpu.Types.Repeat|Mirror->Ogpu.Types.Mirror_repeat in
  let min_filter,mag_filter,mip_filter=match value.filter with Raster2.Texture.Nearest->Ogpu.Types.Nearest,Ogpu.Types.Nearest,Ogpu.Types.No_mip|Bilinear->Ogpu.Types.Linear,Ogpu.Types.Linear,Ogpu.Types.No_mip|Trilinear->Ogpu.Types.Linear,Ogpu.Types.Linear,Ogpu.Types.Linear_mip in
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene3-texture";min_filter;mag_filter;mip_filter;address_u=address value.address_u;address_v=address value.address_v;lod_min=0.;lod_max=float(Array.length levels-1);max_anisotropy=1}in
  let key=Digest.to_hex(Digest.string(Array.to_list levels|>List.map(fun level->Bytes.to_string level.Scene_execution.bytes)|>String.concat""))in
  {Scene_execution.key;levels;sampler}
let white_texture:Scene_execution.sampled_texture={key="scene-white";levels=[|{width=1;height=1;bytes=Bytes.make 4 '\255'}|];sampler={label=Some"scene-white";min_filter=Ogpu.Types.Nearest;mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}}
let draw2 configuration(v:Raster2.Render_ir.geometry)=let mesh:Scene_execution.mesh={key=geometry_key v;vertices=float_bytes v.vertices;vertex_count=Array.length v.vertices/2;indices=index_bytes v.indices;index_count=Array.length v.indices}in let state:Scene_execution.state={viewport=(0,0,configuration.Ogpu.Surface.physical_width,configuration.physical_height);scissor=(0,0,configuration.physical_width,configuration.physical_height);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in{Scene_execution.mesh;state}
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
let draw3(draw:Raster2.Scene3_consumer.draw)=let key=Digest.to_hex(Digest.string(Marshal.to_string(Array.map(fun(v:Raster2.Scene3_consumer.vertex)->v.position,v.normal,v.color,v.u,v.v)draw.vertices,draw.indices)[]))in let mesh:Scene_execution.mesh={key;vertices=vertex3_bytes draw.vertices;vertex_count=Array.length draw.vertices;indices=index_bytes draw.indices;index_count=Array.length draw.indices}and state:Scene_execution.state={viewport=(int_of_float draw.viewport.x,int_of_float draw.viewport.y,int_of_float draw.viewport.width,int_of_float draw.viewport.height);scissor=(draw.scissor.x,draw.scissor.y,draw.scissor.width,draw.scissor.height);cull=pipeline_cull draw.cull;depth_compare=pipeline_comparison draw.depth_stencil.depth_compare;depth_write=draw.depth_stencil.depth_write;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=Some(transform_uniforms draw);stencil_state=pipeline_stencil draw.depth_stencil.stencil;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in{Scene_execution.mesh;state},{viewport=state.viewport;scissor=state.scissor;cull=draw.cull;blend=draw.blend;texture=draw.texture;depth_clear=1.}
let auxiliary_shadow_atlas shadows =
  let indexed=Array.to_list shadows|>List.mapi(fun index value->Option.map(fun prepared->index,Raster2.Shadow_map.snapshot prepared)value)|>List.filter_map Fun.id in
  match indexed with []->Ok None|[_,snapshot]->Scene_execution.shadow_resource~key:(Digest.to_hex(Digest.string(Marshal.to_string snapshot[])))snapshot|>Result.map_error(fun error->Backend error)|>Result.map(fun(resource:Scene_execution.shadow_resource)->Some({Scene_execution.key=resource.texture.key;buffer=resource.parameters;texture=resource.texture}:Scene_execution.auxiliary_resource))|_->
  let width=List.fold_left(fun total(_,snapshot)->max total snapshot.Raster2.Shadow_map.width)1 indexed and height=List.fold_left(fun total(_,snapshot)->total+snapshot.Raster2.Shadow_map.height)0 indexed in
  if width<=0||height<=0||width>16384||height>16384||Int64.mul(Int64.of_int width)(Int64.of_int height)>16_777_216L then Error Unsupported_resource else
  let pixels=Bytes.make(width*height*4)'\255'and parameters=Bytes.make((4+64*25)*4)'\000'in
  let put index value=Bytes.set_int32_le parameters(index*4)(Int32.bits_of_float value)in put 0(float width);put 1(float height);put 2(float(List.length indexed));
  let row=ref 0 in List.iter(fun(light_index,(snapshot:Raster2.Shadow_map.snapshot))->let base=4+light_index*25 in put base 1.;put(base+1)0.;put(base+2)(float!row);put(base+3)(float snapshot.width);put(base+4)(float snapshot.height);Array.iteri(fun index value->put(base+5+index)value)snapshot.matrix;put(base+21)snapshot.bias.constant;put(base+22)snapshot.bias.slope;put(base+23)snapshot.strength;put(base+24)(match snapshot.kernel with Tap1->0.|Tap4->1.|Tap9->1.|Tap25->2.);Array.iteri(fun index depth->let value=int_of_float(floor(depth*.16777215.+.0.5))and x=index mod snapshot.width and y=index/snapshot.width+ !row in let offset=(y*width+x)*4 in Bytes.set pixels offset(Char.chr((value lsr 16)land 255));Bytes.set pixels(offset+1)(Char.chr((value lsr 8)land 255));Bytes.set pixels(offset+2)(Char.chr(value land 255)))snapshot.depths;row:=!row+snapshot.height)indexed;
  let key=Digest.to_hex(Digest.string(Bytes.to_string pixels^Bytes.to_string parameters))in
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"scene-shadow-atlas";min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
  Ok(Some({Scene_execution.key;buffer=parameters;texture={key="shadow-atlas:"^key;levels=[|{width;height;bytes=pixels}|];sampler}}:Scene_execution.auxiliary_resource))
let render_with_scene3 value resources scene=if value.destroyed then Error Destroyed else match value.prepared_scene with
|Some prepared when prepared.source==scene&&prepared.resources==resources->value.draw_states<-prepared.states;backend(Scene_execution.render_prepared_sampled_resources~identity:prepared.identity~version:prepared.version value.execution [])
|_->let scene2,views=split_scene value scene in match Scene_raster2_lowering.lower scene2 with Error(Unsupported _)->Error Unsupported_resource|Error e->Error(Scene e)|Ok ir->let _,draws2=Raster2.Render_ir.commands ir|>Array.fold_left(fun(active,out)->function Raster2.Render_ir.Set_blend blend->blend,out|Geometry g->active,(pipeline_blend active,draw2 value.configuration g)::out|_->active,out)(Raster2.Composite.Source_over,[])in let draws2=List.rev draws2 in let rec lower ds ss=function []->Ok(List.rev ds,List.rev ss)|Scene_description.View3d(camera,scene,Some viewport)::rest->let node=Scene_description.View3d(camera,scene,Some viewport)in(match Scene3_raster2_lowering.lower_view3d~resources~default_viewport:viewport node with Error e->Error(Scene3 e)|Ok prepared when Array.exists(fun(draw:Raster2.Scene3_consumer.draw)->Option.is_some draw.program)prepared.draws->Error Unsupported_resource|Ok prepared->let rec pairs acc=function []->Ok(List.rev acc)|(draw:Raster2.Scene3_consumer.draw)::tail->let auxiliary=auxiliary_shadow_atlas draw.shadows in Result.bind auxiliary(fun auxiliary->let rendered,state=draw3 draw in let texture=match auxiliary,state.texture with Some _,None->Some white_texture|_,texture->Option.map sampled_texture texture in pairs((pipeline_blend state.blend,texture,auxiliary,rendered,state)::acc)tail)in Result.bind(pairs[](Array.to_list prepared.draws))(fun pairs->let stencil_started=ref false in let pairs=List.mapi(fun index(blend,texture,auxiliary,draw,state)->let stencil_load=match draw.Scene_execution.state.stencil_state with None->Ogpu.Render_pass.Load|Some _ when not!stencil_started->stencil_started:=true;Clear|Some _->Load in let execution_state={draw.Scene_execution.state with depth_clear=prepared.clear_depth;depth_load=(if index=0 then Ogpu.Render_pass.Clear else Load);stencil_clear=prepared.clear_stencil;stencil_load}in blend,texture,auxiliary,{draw with state=execution_state},{state with depth_clear=prepared.clear_depth})pairs in lower(List.rev_append(List.map(fun(blend,texture,auxiliary,draw,_)->blend,texture,auxiliary,prepared.samples,draw)pairs)ds)(List.rev_append(List.map(fun(_,_,_,_,s)->{s with depth_clear=prepared.clear_depth})pairs)ss)rest))|_::_->assert false in Result.bind(lower[][]views)(fun(draws3,states)->let states=Array.of_list states in value.draw_states<-states;let draws=List.map(fun(blend,draw)->Scene_execution.Scene2,blend,None,None,1,draw)draws2@List.map(fun(blend,texture,auxiliary,samples,draw)->(let base=match auxiliary,texture with Some _,None->Scene_execution.Scene3_shadow|None,Some _->Scene3_textured|None,None->Scene3|Some _,Some _->Scene3_shadow in match draw.Scene_execution.state.stencil_state,base with None,base->base|Some _,Scene3->Scene3_stencil|Some _,Scene3_textured->Scene3_textured_stencil|Some _,Scene3_shadow->Scene3_shadow_stencil|Some _,_->assert false),blend,texture,auxiliary,samples,draw)draws3 in value.next_version<-Int64.succ value.next_version;let identity="scene:"^Int64.to_string value.next_version in if List.for_all(fun(_,_,texture,auxiliary,_,_)->texture=None&&auxiliary=None)draws then value.prepared_scene<-Some{source=scene;resources;draws;states;identity;version=value.next_version}else value.prepared_scene<-None;backend(Scene_execution.render_prepared_sampled_resources~identity~version:value.next_version value.execution draws))
let render value scene=render_with_scene3 value default_scene3_resources scene
let resize value configuration=if value.destroyed then Error Destroyed else Result.map(fun()->value.configuration<-configuration;value.prepared_scene<-None)(backend(Scene_execution.resize value.execution configuration))
let upload_bytes value=Scene_execution.upload_bytes value.execution
let destroy value=if value.destroyed then Ok()else(value.destroyed<-true;value.prepared_scene<-None;backend(Scene_execution.destroy value.execution))
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
 ignore(get(render renderer sampled_scene));
 let sampled_upload=upload_bytes renderer in
 List.iter(fun _frame->ignore(get(render renderer sampled_scene));if upload_bytes renderer<>sampled_upload then failwith"stable native multisample reuploaded")[1;2;60;600];
 let owned=Scene3_raster2_resources.create()in let owned_callbacks=Scene3_raster2_resources.callbacks owned in
 let texture=Texture.create_exn~width:1~height:1[Color.white]in
 let textured=[Scene_description.View3d(camera,Scene3.create[Scene3.mesh
   ~material:(Material.unlit Color.white)~texture:(Scene3.textured texture)mesh],None)]in
 ignore(get(render_with_scene3 renderer owned_callbacks textured));
 let textured_upload=upload_bytes renderer in
 List.iter(fun _frame->ignore(get(render_with_scene3 renderer owned_callbacks textured));if upload_bytes renderer<>textured_upload then failwith"stable native texture reuploaded")[1;2;60;600];
 let light=Light.directional~direction:(Vec3.create 0. 0.(-1.))()in
 let shadow=Shadow3.create~filter:Shadow3.Pcf_5x5~light~camera~width:1~height:1~depths:[|0.5|]()in
 let shadowed=[Scene_description.View3d(camera,Scene3.create~lights:[light]~shadows:[shadow]
   [Scene3.mesh~material:(Material.matte Color.white)mesh],None)]in
 ignore(get(render_with_scene3 renderer owned_callbacks shadowed));
 let shadow_upload=upload_bytes renderer in
 List.iter(fun _frame->ignore(get(render_with_scene3 renderer owned_callbacks shadowed));if upload_bytes renderer<>shadow_upload then failwith"stable native shadow reuploaded")[1;2;60;600];
 Scene3_raster2_resources.destroy owned;
 if upload_bytes renderer<shadow_upload then failwith"native shadow upload accounting regressed";
 List.iter(fun mode->
   let blended=[Scene_description.View3d(camera,Scene3.create
     [Scene3.with_blend mode[Scene3.mesh~material:(Material.unlit Color.white)mesh]],None)]in
   ignore(get(render renderer blended)))
   [Scene3.Replace;Add;Multiply;Screen;Subtract];
 ignore(get(render renderer[Scene_description.View3d(camera,Scene3.create
   [Scene3.with_blend Alpha[Scene3.mesh~material:(Material.unlit Color.white)mesh]],None)]));
 let reversed_mesh=Mesh.create_exn~normals:[Vec3.neg Vec3.unit_z;Vec3.neg Vec3.unit_z;Vec3.neg Vec3.unit_z]
   [Vec3.create(-0.5)(-0.5)0.;Vec3.create 0. 0.5 0.;Vec3.create 0.5(-0.5)0.]in
 let reversed_value=Scene3.create[Scene3.mesh~material:(Material.unlit Color.white)
   ~cull:Scene3.Cull_none reversed_mesh]in
 let reversed_node=Scene_description.View3d(camera,reversed_value,Some(0,0,16,16))in
 let reversed_prepared=match Scene3_raster2_lowering.lower_view3d
   ~resources:default_scene3_resources~default_viewport:(0,0,16,16)reversed_node with
   |Ok value->value|Error _->failwith"reversed normal lowering"in
 let packed=vertex3_bytes reversed_prepared.draws.(0).vertices in
 for vertex=0 to 2 do
   let offset=vertex*68 in
   if Int64.float_of_bits(Bytes.get_int64_le packed(offset+24))<>0.||
      Int64.float_of_bits(Bytes.get_int64_le packed(offset+32))<>0.||
      Int64.float_of_bits(Bytes.get_int64_le packed(offset+40))<>(-1.)then
     failwith"orientation-aware normal changed in OGPU vertex bytes"
 done;
 let before_reversed=upload_bytes renderer in
 ignore(get(render renderer[reversed_node]));let reversed_upload=upload_bytes renderer in
 if reversed_upload<=before_reversed then failwith"reversed terminal mesh was not uploaded";
 List.iter(fun _frame->ignore(get(render renderer[reversed_node]));
   if upload_bytes renderer<>reversed_upload then failwith"reversed mesh reuploaded")
   [1;2;60;600];
 get(destroy renderer);if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"renderer leaked"
let()=match Sys.getenv_opt"PRISMEL_TEST_SCENE_OGPU_RENDERER"with Some"1"->self_test()|_->()
