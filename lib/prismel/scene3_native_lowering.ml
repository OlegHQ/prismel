type error =
  | Unsupported_shader
  | Unsupported_mode
  | Unsupported_texture
  | Unsupported_shadow
  | Invalid_mesh
  | Invalid_viewport

type resources = {
  texture : Scene3.texture -> (Scene_execution.sampled_texture, error) result;
  shadow : Shadow3.t -> (Scene_execution.auxiliary_resource, error) result;
}

type prepared = Scene_execution.prepared_scene3

let comparison = function
  | Scene3.Never -> Ogpu.Render_pass.Never | Less -> Less | Equal -> Equal
  | Less_equal -> Less_equal | Greater -> Greater | Not_equal -> Not_equal
  | Greater_equal -> Greater_equal | Always -> Always

let blend = function
  | Scene3.Replace -> Ogpu.Pipeline.Replace | Alpha -> Alpha | Add -> Add
  | Multiply -> Multiply | Screen -> Screen | Subtract -> Subtract

let packed_color(c:Color.t)=Int32.of_int((c.r lsl 24)lor(c.g lsl 16)lor(c.b lsl 8)lor c.a)
let put32 bytes index value=Bytes.set_int32_le bytes(index*4)(Int32.bits_of_float value)
let color bytes index(c:Color.t)=put32 bytes index(float c.r/.255.);put32 bytes(index+1)(float c.g/.255.);put32 bytes(index+2)(float c.b/.255.);put32 bytes(index+3)(float c.a/.255.)
let matrix bytes offset value=for index=0 to 15 do put32 bytes(offset+index)(Mat4.get value~row:(index/4)~column:(index mod 4))done
let uniforms ~camera ~viewport scene(drawing:Scene3.Private.drawing)=
  let bytes=Bytes.make 5456 '\000'and material=drawing.material in
  let projection=Camera.view_projection_matrix~viewport camera in
  matrix bytes 0(Mat4.mul projection drawing.transform);matrix bytes 16 drawing.transform;
  let normal=match Mat4.inverse drawing.transform with None->Mat4.identity|Some value->Mat4.transpose value in matrix bytes 32 normal;
  let eye=Camera.position camera in put32 bytes 48 eye.x;put32 bytes 49 eye.y;put32 bytes 50 eye.z;
  color bytes 52 material.ambient;color bytes 56 material.diffuse;color bytes 60 material.specular;color bytes 64 material.emissive;put32 bytes 68 material.shininess;
  let ambient=Scene3.Private.ambient scene in color bytes 69 ambient;
  let lights=Scene3.Private.lights scene|>List.filter(fun light->light.Light.kind<>Ambient)|>Array.of_list in
  put32 bytes 73(float(Array.length lights));put32 bytes 74(if drawing.cull=Cull_none then 1. else 0.);put32 bytes 75(if Scene3.Private.separate_specular scene then 1. else 0.);
  Array.iteri(fun index(light:Light.t)->let o=84+index*20 in let vector p=put32 bytes(o+1)p.Vec3.x;put32 bytes(o+2)p.y;put32 bytes(o+3)p.z in color bytes(o+4)light.diffuse;put32 bytes(o+8)light.intensity;match light.kind with
    |Ambient->()|Directional{direction}->put32 bytes o 0.;vector direction
    |Point{position;attenuation}->put32 bytes o 1.;vector position;put32 bytes(o+9)attenuation.constant;put32 bytes(o+10)attenuation.linear;put32 bytes(o+11)attenuation.quadratic
    |Spot{position;direction;cutoff;concentration;attenuation}->put32 bytes o 2.;vector position;put32 bytes(o+9)direction.x;put32 bytes(o+10)direction.y;put32 bytes(o+11)direction.z;put32 bytes(o+12)(cos cutoff);put32 bytes(o+13)(cos cutoff);put32 bytes(o+14)concentration;put32 bytes(o+15)attenuation.constant;put32 bytes(o+16)attenuation.linear;put32 bytes(o+17)attenuation.quadratic
    |Area{position;direction;width;height;samples;attenuation}->put32 bytes o 3.;vector position;put32 bytes(o+9)direction.x;put32 bytes(o+10)direction.y;put32 bytes(o+11)direction.z;put32 bytes(o+12)width;put32 bytes(o+13)height;put32 bytes(o+14)(float samples);put32 bytes(o+15)attenuation.constant;put32 bytes(o+16)attenuation.linear;put32 bytes(o+17)attenuation.quadratic)lights;bytes
let vertices (view:Mesh.Private.view)=
  let count=Array.length view.vertices in
  let normals=match view.normals with Some values when Array.length values=count->Some values|_->None in
  match normals with None->Error Invalid_mesh|Some normals->
  let bytes=Bytes.make(count*68)'\000'in Array.iteri(fun index(position:Vec3.t)->let normal=normals.(index)and offset=index*68 in let put at value=Bytes.set_int64_le bytes(offset+at)(Int64.bits_of_float value)in put 0 position.x;put 8 position.y;put 16 position.z;put 24 normal.x;put 32 normal.y;put 40 normal.z;Bytes.set_int32_le bytes(offset+48)(match view.colors with Some colors when Array.length colors=count->packed_color colors.(index)|_->Int32.minus_one);let uv=match view.tex_coords with Some values when Array.length values=count->values.(index)|_->Vec2.zero in put 52 uv.x;put 60 uv.y)view.vertices;Ok bytes
let indices values=let bytes=Bytes.make(Array.length values*4)'\000'in Array.iteri(fun i value->Bytes.set_int32_le bytes(i*4)(Int32.of_int value))values;bytes
let cull=function Scene3.Cull_none->Ogpu.Render_pass.Cull_none|Cull_back->Cull_back|Cull_front->Cull_front
let triangle_indices mode source=match mode with
  |Mesh.Triangles when Array.length source mod 3=0->Some source
  |Triangle_strip when Array.length source>=3->Some(Array.init((Array.length source-2)*3)(fun index->let triangle=index/3 and corner=index mod 3 in if triangle land 1=0 then source.(triangle+corner)else source.(triangle+(match corner with 0->1|1->0|_->2))))
  |Triangle_fan when Array.length source>=3->Some(Array.init((Array.length source-2)*3)(fun index->let triangle=index/3 in match index mod 3 with 0->source.(0)|1->source.(triangle+1)|_->source.(triangle+2)))
  |_->None
let prepare ~resources ~camera ~viewport:(x,y,width,height as viewport) scene =
  if width<=0||height<=0 then Error Invalid_viewport
  else if List.exists(fun(d:Scene3.Private.drawing)->Option.is_some d.shader)
      (Scene3.Private.drawings scene)then Error Unsupported_shader
  else let failure=ref None and entries=ref[]in List.iteri(fun number(drawing:Scene3.Private.drawing)->if !failure=None then let view=Mesh.Private.view drawing.mesh in match drawing.mode,triangle_indices view.mode view.indices,vertices view with
    |Scene3.Faces,Some native_indices,Ok vertex_bytes->let texture=match drawing.texture with None->Ok None|Some value->Result.map Option.some(resources.texture value)in let shadow=match Scene3.Private.shadows scene with []->Ok None|value::_->Result.map Option.some(resources.shadow value)in(match texture,shadow with Error error,_|_,Error error->failure:=Some error|Ok texture,Ok auxiliary->let mesh:Scene_execution.mesh={key=Printf.sprintf"scene3:%d:%s"number(Digest.to_hex(Digest.bytes vertex_bytes));vertices=vertex_bytes;vertex_count=Array.length view.vertices;indices=indices native_indices;index_count=Array.length native_indices}in let state:Scene_execution.state={viewport=(x,y,width,height);scissor=(x,y,width,height);cull=cull drawing.cull;depth_compare=comparison drawing.depth.comparison;depth_write=drawing.depth.write;depth_load=Ogpu.Render_pass.Clear;depth_clear=Scene3.Private.depth_clear scene;transform_uniforms=Some(uniforms~camera~viewport scene drawing);stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=Scene3.Private.stencil_clear scene}in let family=match auxiliary,texture with Some _,_->Scene_execution.Scene3_shadow|None,Some _->Scene3_textured|None,None->Scene3 in entries:={Scene_execution.family;blend=blend drawing.blend;texture;auxiliary;samples=Scene3.Private.samples scene;draw={mesh;state}}::!entries)
    |_->failure:=Some Invalid_mesh)(Scene3.Private.drawings scene);
    match!failure with Some error->Error error|None->match Scene_execution.prepare_scene3 ~clear:(0.,0.,0.,0.)
      ~clear_depth:(Scene3.Private.depth_clear scene)
      ~clear_stencil:(Scene3.Private.stencil_clear scene)(Array.of_list(List.rev!entries))with
    |Ok value->Ok value|Error _->Error Invalid_mesh
