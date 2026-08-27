type error = Unsupported_shader | Unsupported_mode | Unsupported_area_light |
  Unsupported_fog | Texture_error | Shadow_error | Invalid_mesh | Invalid_viewport |
  Lighting_error of Raster2.Scene3_lighting.error | Shader_error of string
type resources = {
  texture : Scene3.texture -> (Raster2.Triangle.texture, error) result;
  shadow : Shadow3.t -> (Raster2.Shadow_map.prepared, error) result;
}
type prepared = { draws : Raster2.Scene3_consumer.draw array; clear_depth : float; clear_stencil : int; samples : int }

let color (value:Color.t)={Raster2.Scene3_lighting.r=float value.r/.255.;g=float value.g/.255.;b=float value.b/.255.;a=float value.a/.255.}
let packed_color(value:Color.t)=Int32.of_int((value.r lsl 24)lor(value.g lsl 16)lor(value.b lsl 8)lor value.a)
let vec (value:Vec3.t)={Raster2.Scene3_lighting.x=value.x;y=value.y;z=value.z}
let attenuation (value:Light.attenuation)={Raster2.Scene3_lighting.constant=value.constant;linear=value.linear;quadratic=value.quadratic}
let blend=function Scene3.Replace->Raster2.Composite.Copy|Alpha->Source_over|Add->Add|Multiply->Multiply|Screen->Screen|Subtract->Subtract
let texture_filter=function Texture.Nearest->Raster2.Texture.Nearest|Bilinear->Bilinear|Trilinear->Trilinear
let texture_address=function Texture.Clamp->Raster2.Texture.Clamp|Repeat->Repeat|Mirror->Mirror
let cull=function Scene3.Cull_none->Raster2.Triangle.Cull_none|Cull_back->Back|Cull_front->Front
let mode=function Scene3.Faces->Raster2.Scene3_consumer.Faces|Wireframe->Wireframe|Vertices->Vertices
let comparison=function Scene3.Never->Raster2.Depth_stencil.Never|Less->Less|Equal->Equal|Less_equal->Less_equal|Greater->Greater|Not_equal->Not_equal|Greater_equal->Greater_equal|Always->Always
let stencil_op=function Scene3.Keep->Raster2.Depth_stencil.Keep|Zero->Zero|Replace->Replace|Increment->Increment_clamp|Decrement->Decrement_clamp|Increment_wrap->Increment_wrap|Decrement_wrap->Decrement_wrap|Invert->Invert
let depth_stencil (drawing:Scene3.Private.drawing)={Raster2.Depth_stencil.depth_compare=comparison drawing.depth.comparison;depth_write=drawing.depth.write;stencil=Some{compare=comparison drawing.stencil.comparison;fail=stencil_op drawing.stencil.on_stencil_fail;depth_fail=stencil_op drawing.stencil.on_depth_fail;pass=stencil_op drawing.stencil.on_pass;read_mask=drawing.stencil.read_mask;write_mask=drawing.stencil.write_mask;reference=drawing.stencil.reference}}
let shading=function Scene3.Smooth->Raster2.Scene3_consumer.Smooth|Flat->Flat
let lights values =
  let ar=ref 0. and ag=ref 0. and ab=ref 0. and failure=ref None and output=ref[]in
  List.iter(fun(value:Light.t)->match value.kind with
    | Ambient->ar:=!ar+.value.intensity*.float value.ambient.r/.255.;ag:=!ag+.value.intensity*.float value.ambient.g/.255.;ab:=!ab+.value.intensity*.float value.ambient.b/.255.
    | Directional{direction}->output:=Raster2.Scene3_lighting.Directional{direction=vec direction;color=color value.diffuse;intensity=value.intensity}::!output
    | Point{position;attenuation=a}->output:=Point{position=vec position;color=color value.diffuse;intensity=value.intensity;attenuation=attenuation a}::!output
    | Spot{position;direction;cutoff;concentration;attenuation=a}->
        output:=Spot{position=vec position;direction=vec direction;
          inner_cos=cos cutoff;outer_cos=cos cutoff;concentration;
          color=color value.diffuse;intensity=value.intensity;
          attenuation=attenuation a}::!output
    | Area{position;direction;width;height;samples;attenuation=a}->output:=Raster2.Scene3_lighting.Area{position=vec position;direction=vec direction;width;height;samples;color=color value.diffuse;intensity=value.intensity;attenuation=attenuation a}::!output)values;
  match !failure with Some error->Error error|None->Ok({Raster2.Scene3_lighting.r=min 1. !ar;g=min 1. !ag;b=min 1. !ab;a=1.},Array.of_list(List.rev !output))
let fog=function None->Ok Raster2.Scene3_lighting.No_fog|Some value->match value.Fog3.mode with
  | Linear{start;end_}->Ok(Linear{color=color value.color;near=start;far=end_})
  | Exponential{density}->Ok(Exponential{color=color value.color;density})
  | Exponential_squared{density}->Ok(Exponential_squared{color=color value.color;density})
let topology=function Mesh.Points->Ok Raster2.Scene3.Point_list|Lines->Ok Line_list|Line_strip->Ok Line_strip|Line_loop->Ok Line_loop|Triangles->Ok Triangle_list|Triangle_strip->Ok Triangle_strip|Triangle_fan->Ok Triangle_fan
let matrix_array value=Array.init 16(fun index->Mat4.get value~row:(index/4)~column:(index mod 4))
let depth_zero_to_one=Mat4.of_rows(1.,0.,0.,0.)(0.,1.,0.,0.)(0.,0.,0.5,0.5)(0.,0.,0.,1.)
let program_vec (value:Vec3.t):Raster2.Scene3_program.vec3={x=value.x;y=value.y;z=value.z}
let program_vec2 (value:Vec2.t):Raster2.Scene3_program.vec2={x=value.x;y=value.y}
let unpack_color value=Color.rgba
  Int32.(to_int(logand(shift_right_logical value 24)0xffl))
  Int32.(to_int(logand(shift_right_logical value 16)0xffl))
  Int32.(to_int(logand(shift_right_logical value 8)0xffl))
  Int32.(to_int(logand value 0xffl))
let program_vertex (value:Shader3.vertex_output):Raster2.Scene3_program.vertex=
  let clip_x,clip_y,clip_z,clip_w=value.clip_position in
  {clip_x;clip_y;clip_z;clip_w;world=program_vec value.world_position;
   normal=program_vec value.world_normal;color=packed_color value.color;
   tex_coord=program_vec2 value.tex_coord;varyings=Array.of_list value.varyings}
let program_primitive=function
  | Shader3.Point value->Raster2.Scene3_program.Point(program_vertex value)
  | Line(a,b)->Line(program_vertex a,program_vertex b)
  | Triangle(a,b,c)->Triangle(program_vertex a,program_vertex b,program_vertex c)
let program ~camera ~viewport ~drawing shader =
  let feedback=Transform_feedback3.capture~model:drawing.Scene3.Private.transform
    ~viewport~camera~shader drawing.mesh in
  let uniforms=Shader3.uniforms shader in
  let fragment(input:Raster2.Scene3_program.fragment_input)=
    Shader3.Private.fragment shader
      {screen_position=Vec2.create input.screen.x input.screen.y;depth=input.depth;
       front_facing=input.front_facing;
       world_position=Vec3.create input.world.x input.world.y input.world.z;
       world_normal=Vec3.create input.normal.x input.normal.y input.normal.z;
       color=unpack_color input.color;
       tex_coord=Vec2.create input.tex_coord.x input.tex_coord.y;
       varyings=Array.to_list input.varyings;uniforms}
    |>Option.map(fun(output:Shader3.fragment_output)->
      {Raster2.Scene3_program.color=packed_color output.color;depth=output.depth})
  in
  {Raster2.Scene3_program.primitives=
     Array.of_list(List.map program_primitive(Transform_feedback3.primitives feedback));
   varying_count=Shader3.varying_count shader;fragment}

let prepare ~resources ~camera ~viewport scene =
  let vx,vy,vw,vh=viewport in if vw<=0||vh<=0 then Error Invalid_viewport else
  match lights(Scene3.Private.lights scene),fog(Scene3.Private.fog scene)with
  | Error error,_|_,Error error->Error error
  | Ok(light_ambient,lights),Ok fog->
    let scene_ambient=color(Scene3.Private.ambient scene)in
    let global_ambient={Raster2.Scene3_lighting.r=min 1.(scene_ambient.r+.light_ambient.r);g=min 1.(scene_ambient.g+.light_ambient.g);b=min 1.(scene_ambient.b+.light_ambient.b);a=1.}in
    let descriptions=Scene3.Private.drawings scene in
    let preflight=List.find_map(fun(drawing:Scene3.Private.drawing)->
      match Mesh.mode drawing.mesh with
      | Mesh.Points|Lines|Line_strip|Line_loop|Triangles|Triangle_strip|Triangle_fan->
          let mesh=Mesh.Private.view drawing.mesh in
          match mesh.colors with Some colors when Array.length colors<>Array.length mesh.vertices->Some Invalid_mesh|Some _|None->None)descriptions in
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
        if(match mesh.colors with Some colors->Array.length colors<>Array.length mesh.vertices|None->false)then failure:=Some Invalid_mesh else
        let normals=match mesh.normals with Some values->values|None->(Mesh.Private.view(Mesh.recalculate_normals drawing.mesh)).normals|>Option.value~default:[||]in
        if Array.length normals<>Array.length mesh.vertices then failure:=Some Invalid_mesh else
        let texture=match drawing.texture with None->Ok None|Some value->Result.map(fun resolved->Some{resolved with Raster2.Triangle.filter=texture_filter value.filter;address_u=texture_address value.wrap_u;address_v=texture_address value.wrap_v})(resources.texture value)in
        match texture with Error error->failure:=Some error|Ok texture->
        let vertices=Array.mapi(fun i(position:Vec3.t)->let normal=normals.(i)and uv=match mesh.tex_coords with Some values when i<Array.length values->values.(i)|_->Vec2.zero and vertex_color=match mesh.colors with Some values->packed_color values.(i)|None->0xffffffffl in
          {Raster2.Scene3_consumer.position=vec position;normal=vec normal;color=vertex_color;u=uv.x;v=uv.y})mesh.vertices in
        let material=drawing.material in
        let lighting={Raster2.Scene3_lighting.ambient=global_ambient;lights;material={ambient=color material.ambient;diffuse=color material.diffuse;specular=color material.specular;emissive=color material.emissive;shininess=material.shininess};fog;separate_specular=Scene3.Private.separate_specular scene;two_sided=drawing.cull=Scene3.Cull_none}in
        begin match Raster2.Scene3_lighting.prepare_with_shadows lighting shadow_values with Error error->failure:=Some(Lighting_error error)|Ok _->
          let camera_matrix=Mat4.mul depth_zero_to_one(Camera.view_projection_matrix~viewport camera)in
          let matrix=matrix_array(Mat4.mul camera_matrix drawing.transform)in
          let model_matrix=matrix_array drawing.transform in
          let camera_position=vec(Camera.position camera)in
          let program_result=match drawing.shader with None->Ok None|Some shader->
            try Ok(Some(program~camera~viewport~drawing shader))
            with Invalid_argument message->Error(Shader_error message)|exn->Error(Shader_error(Printexc.to_string exn))in
          begin match program_result with Error error->failure:=Some error|Ok program->
            draws:={Raster2.Scene3_consumer.matrix;model_matrix;camera_position;viewport={x=float vx;y=float vy;width=float vw;height=float vh;min_depth=0.;max_depth=1.};scissor={x=vx;y=vy;width=vw;height=vh};topology;vertices;indices=mesh.indices;lighting;shadows=Array.copy shadow_values;shading=shading drawing.shading;texture;cull=cull drawing.cull;blend=blend drawing.blend;depth_stencil=depth_stencil drawing;mode=mode drawing.mode;line_width=drawing.raster.line_width;point_size=drawing.raster.point_size;program}::!draws
          end
        end)descriptions;
    match !failure with Some error->Error error|None->Ok{draws=Array.of_list(List.rev !draws);clear_depth=Scene3.Private.depth_clear scene;clear_stencil=Scene3.Private.stencil_clear scene;samples=Scene3.Private.samples scene}
