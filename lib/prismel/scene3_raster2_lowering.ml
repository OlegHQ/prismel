type error = Unsupported_shader | Unsupported_mode | Unsupported_area_light |
  Unsupported_fog | Texture_error | Shadow_error | Invalid_mesh | Invalid_viewport |
  Lighting_error of Raster2.Scene3_lighting.error
type resources = {
  texture : Scene3.texture -> (Raster2.Triangle.texture, error) result;
  shadow : Shadow3.t -> (Raster2.Shadow_map.prepared, error) result;
}
type prepared = { draws : Raster2.Scene3_consumer.draw array; clear_depth : float; samples : int }

let color (value:Color.t)={Raster2.Scene3_lighting.r=float value.r/.255.;g=float value.g/.255.;b=float value.b/.255.;a=float value.a/.255.}
let vec (value:Vec3.t)={Raster2.Scene3_lighting.x=value.x;y=value.y;z=value.z}
let attenuation (value:Light.attenuation)={Raster2.Scene3_lighting.constant=value.constant;linear=value.linear;quadratic=value.quadratic}
let blend=function Scene3.Replace->Raster2.Composite.Copy|Alpha->Source_over|Add->Add|Multiply->Multiply|Screen->Screen|Subtract->Subtract
let cull=function Scene3.Cull_none->Raster2.Triangle.Cull_none|Cull_back->Back|Cull_front->Front
let shading=function Scene3.Smooth->Raster2.Scene3_consumer.Smooth|Flat->Flat
let lights values =
  let ar=ref 0. and ag=ref 0. and ab=ref 0. and failure=ref None and output=ref[]in
  List.iter(fun(value:Light.t)->match value.kind with
    | Ambient->ar:=!ar+.value.intensity*.float value.ambient.r/.255.;ag:=!ag+.value.intensity*.float value.ambient.g/.255.;ab:=!ab+.value.intensity*.float value.ambient.b/.255.
    | Directional{direction}->output:=Raster2.Scene3_lighting.Directional{direction=vec direction;color=color value.diffuse;intensity=value.intensity}::!output
    | Point{position;attenuation=a}->output:=Point{position=vec position;color=color value.diffuse;intensity=value.intensity;attenuation=attenuation a}::!output
    | Spot{position;direction;cutoff;attenuation=a;_}->output:=Spot{position=vec position;direction=vec direction;inner_cos=cos(cutoff*.0.8);outer_cos=cos cutoff;color=color value.diffuse;intensity=value.intensity;attenuation=attenuation a}::!output
    | Area _->failure:=Some Unsupported_area_light)values;
  match !failure with Some error->Error error|None->Ok({Raster2.Scene3_lighting.r=min 1. !ar;g=min 1. !ag;b=min 1. !ab;a=1.},Array.of_list(List.rev !output))
let fog=function None->Ok Raster2.Scene3_lighting.No_fog|Some value->match value.Fog3.mode with
  | Linear{start;end_}->Ok(Linear{color=color value.color;near=start;far=end_})
  | Exponential _|Exponential_squared _->Error Unsupported_fog
let topology=function Mesh.Triangles->Ok Raster2.Scene3.Triangle_list|Triangle_strip->Ok Triangle_strip|Triangle_fan->Ok Triangle_fan|_->Error Unsupported_mode
let matrix_array value=Array.init 16(fun index->Mat4.get value~row:(index/4)~column:(index mod 4))
let depth_zero_to_one=Mat4.of_rows(1.,0.,0.,0.)(0.,1.,0.,0.)(0.,0.,0.5,0.5)(0.,0.,0.,1.)

let prepare ~resources ~camera ~viewport scene =
  let vx,vy,vw,vh=viewport in if vw<=0||vh<=0 then Error Invalid_viewport else
  match lights(Scene3.Private.lights scene),fog(Scene3.Private.fog scene)with
  | Error error,_|_,Error error->Error error
  | Ok(light_ambient,lights),Ok fog->
    let scene_ambient=color(Scene3.Private.ambient scene)in
    let global_ambient={Raster2.Scene3_lighting.r=min 1.(scene_ambient.r+.light_ambient.r);g=min 1.(scene_ambient.g+.light_ambient.g);b=min 1.(scene_ambient.b+.light_ambient.b);a=1.}in
    let descriptions=Scene3.Private.drawings scene in
    let preflight=List.find_map(fun(drawing:Scene3.Private.drawing)->
      if drawing.shader<>None then Some Unsupported_shader else
      match drawing.mode,Mesh.mode drawing.mesh with
      | (Wireframe|Vertices),_|_,(Mesh.Points|Lines|Line_strip|Line_loop)->Some Unsupported_mode
      | Faces,(Triangles|Triangle_strip|Triangle_fan)->
          let mesh=Mesh.Private.view drawing.mesh in
          if mesh.colors<>None then Some Invalid_mesh else None)descriptions in
    match preflight with Some error->Error error|None->
    let shadows=Scene3.Private.shadows scene in
    let shadow_values=Array.make(Array.length lights)None and shadow_failure=ref None in
    List.iter(fun shadow->match resources.shadow shadow with Error error->shadow_failure:=Some error|Ok prepared->
      let rec assign output_index=function[]->()|light::rest->
        let next=match light.Light.kind with Ambient->output_index|_->output_index+1 in
        if Shadow3.Private.affects shadow light&&output_index<Array.length shadow_values then shadow_values.(output_index)<-Some prepared;
        assign next rest in assign 0(Scene3.Private.lights scene))shadows;
    match !shadow_failure with Some error->Error error|None->
    let failure=ref None and draws=ref[]in
    List.iter(fun(drawing:Scene3.Private.drawing)->if !failure=None then
      match topology(Mesh.mode drawing.mesh)with
      | Error _->failure:=Some Unsupported_mode
      | Ok topology->
        let mesh=Mesh.Private.view drawing.mesh in
        if mesh.colors<>None then failure:=Some Invalid_mesh else
        let normals=match mesh.normals with Some values->values|None->(Mesh.Private.view(Mesh.recalculate_normals drawing.mesh)).normals|>Option.value~default:[||]in
        if Array.length normals<>Array.length mesh.vertices then failure:=Some Invalid_mesh else
        let texture=match drawing.texture with None->Ok None|Some value->Result.map Option.some(resources.texture value)in
        match texture with Error error->failure:=Some error|Ok texture->
        let vertices=Array.mapi(fun i(position:Vec3.t)->let normal=normals.(i)and uv=match mesh.tex_coords with Some values when i<Array.length values->values.(i)|_->Vec2.zero in
          {Raster2.Scene3_consumer.position=vec position;normal=vec normal;color=0xffffffffl;u=uv.x;v=uv.y})mesh.vertices in
        let material=drawing.material in
        let lighting={Raster2.Scene3_lighting.ambient=global_ambient;lights;material={ambient=color material.ambient;diffuse=color material.diffuse;specular=color material.specular;emissive=color material.emissive;shininess=material.shininess};fog;separate_specular=Scene3.Private.separate_specular scene;two_sided=drawing.cull=Scene3.Cull_none}in
        begin match Raster2.Scene3_lighting.prepare_with_shadows lighting shadow_values with Error error->failure:=Some(Lighting_error error)|Ok _->
          let camera_matrix=Mat4.mul depth_zero_to_one(Camera.view_projection_matrix~viewport camera)in
          let matrix=matrix_array(Mat4.mul camera_matrix drawing.transform)in
          draws:={Raster2.Scene3_consumer.matrix;viewport={x=float vx;y=float vy;width=float vw;height=float vh;min_depth=0.;max_depth=1.};scissor={x=vx;y=vy;width=vw;height=vh};topology;vertices;indices=mesh.indices;lighting;shadows=Array.copy shadow_values;shading=shading drawing.shading;texture;cull=cull drawing.cull;blend=blend drawing.blend}::!draws
        end)descriptions;
    match !failure with Some error->Error error|None->Ok{draws=Array.of_list(List.rev !draws);clear_depth=Scene3.Private.depth_clear scene;samples=Scene3.Private.samples scene}

let lower_view3d ~resources ~default_viewport = function
  | Scene_description.View3d(camera,scene,None)->prepare~resources~camera~viewport:default_viewport scene
  | View3d(camera,scene,Some viewport)->prepare~resources~camera~viewport scene
  | _->Error Invalid_viewport

let self_test () =
  let mesh=Mesh.create_exn~normals:[Vec3.unit_z;Vec3.unit_z;Vec3.unit_z][Vec3.create(-0.5)(-0.5)0.;Vec3.create 0.5(-0.5)0.;Vec3.create 0. 0.5 0.]in
  let camera=Camera.orthographic~height:2.~at:(Vec3.create 0. 0. 2.)~target:Vec3.zero()in
  let material=Material.unlit Color.red in
  let node=Scene3.mesh~material~cull:Scene3.Cull_none mesh in
  let scene=Scene3.create~lights:[Light.directional~direction:(Vec3.create 0. 0.(-1.))()][node]in
  let surface=match Raster2.Surface.create~width:1~height:1()with Ok value->value|Error _->failwith"surface"in
  let resources={texture=(fun _->Ok{Raster2.Triangle.surface;filter=Raster2.Image.Nearest});shadow=(fun _->Error Shadow_error)}in
  let prepare _frame=lower_view3d~resources~default_viewport:(0,0,16,16)(Scene_description.View3d(camera,scene,Some(0,0,16,16)))|>function Ok value->Marshal.to_bytes value[]|Error _->Bytes.empty in
  let expected=prepare 1 in if expected=Bytes.empty then failwith"colored Scene3 lowering";
  for frame=1 to 600 do if prepare frame<>expected then failwith"Scene3 frame drift"done;
  let workers=Array.init 4(fun _->Domain.spawn(fun()->prepare 1))in Array.iter(fun worker->if Domain.join worker<>expected then failwith"Scene3 domain drift")workers;
  let prepared=match lower_view3d~resources~default_viewport:(0,0,16,16)(View3d(camera,scene,None))with Ok value->value|Error _->failwith"prepared Scene3"in
  if prepared.draws.(0).vertices.(0).normal.z<>1. then failwith"authored normal lost";
  let draw=prepared.draws.(0)in
  begin match Raster2.Scene3.prepare~matrix:draw.matrix~viewport:draw.viewport~scissor:draw.scissor~topology:draw.topology~vertices:(Array.map(fun(v:Raster2.Scene3_consumer.vertex)->{Raster2.Scene3.x=v.position.x;y=v.position.y;z=v.position.z;color=v.color;u=v.u;v=v.v})draw.vertices)~indices:draw.indices with Ok value when Array.length value.triangles>0->()|_->failwith"Scene3 projection produced no triangles"end;
  let target=match Raster2.Surface.create~width:16~height:16()with Ok value->value|Error _->failwith"target"in
  begin match Raster2.Scene3_consumer.render~target:{color=target;depth=None;multisample=None}~clear:0x000000ffl~clear_depth:prepared.clear_depth~draws:prepared.draws with Ok()->()|Error _->failwith"Scene3 consumer callback"end;
  let changed=ref false in for y=0 to 15 do for x=0 to 15 do match Raster2.Surface.get_rgba target~x~y with Ok value when value<>0x000000ffl->changed:=true|_->()done done;
  if not !changed then failwith"Scene3 framebuffer unchanged";
  let textured=Scene3.create[Scene3.mesh~material~cull:Scene3.Cull_none~texture:(Scene3.textured(Obj.magic 0))mesh]in
  begin match lower_view3d~resources~default_viewport:(0,0,16,16)(View3d(camera,textured,None))with Ok value when Array.length value.draws=1&&value.draws.(0).texture<>None->()|_->failwith"textured Scene3 callback"end;
  let rejecting={resources with texture=(fun _->Error Texture_error)}in
  begin match lower_view3d~resources:rejecting~default_viewport:(0,0,16,16)(View3d(camera,textured,None))with Error Texture_error->()|_->failwith"SDL texture not rejected atomically"end;
  let shader=Scene3.create[Scene3.mesh~material~cull:Scene3.Cull_none~shader:(Obj.magic 0)mesh]in
  match lower_view3d~resources~default_viewport:(0,0,16,16)(View3d(camera,shader,None))with Error Unsupported_shader->()|_->failwith"functional shader not rejected"

let ()=match Sys.getenv_opt"PRISMEL_TEST_SCENE_RASTER2_LOWERING"with Some"1"->self_test()|_->()
