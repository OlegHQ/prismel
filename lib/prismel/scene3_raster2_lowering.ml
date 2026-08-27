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
          let program_result=match drawing.shader with None->Ok None|Some shader->
            try Ok(Some(program~camera~viewport~drawing shader))
            with Invalid_argument message->Error(Shader_error message)|exn->Error(Shader_error(Printexc.to_string exn))in
          begin match program_result with Error error->failure:=Some error|Ok program->
            draws:={Raster2.Scene3_consumer.matrix;viewport={x=float vx;y=float vy;width=float vw;height=float vh;min_depth=0.;max_depth=1.};scissor={x=vx;y=vy;width=vw;height=vh};topology;vertices;indices=mesh.indices;lighting;shadows=Array.copy shadow_values;shading=shading drawing.shading;texture;cull=cull drawing.cull;blend=blend drawing.blend;depth_stencil=depth_stencil drawing;mode=mode drawing.mode;line_width=drawing.raster.line_width;point_size=drawing.raster.point_size;program}::!draws
          end
        end)descriptions;
    match !failure with Some error->Error error|None->Ok{draws=Array.of_list(List.rev !draws);clear_depth=Scene3.Private.depth_clear scene;clear_stencil=Scene3.Private.stencil_clear scene;samples=Scene3.Private.samples scene}

let lower_view3d ~resources ~default_viewport = function
  | Scene_description.View3d(camera,scene,None)->prepare~resources~camera~viewport:default_viewport scene
  | View3d(camera,scene,Some viewport)->prepare~resources~camera~viewport scene
  | _->Error Invalid_viewport

let self_test () =
  let positions=[Vec3.create(-0.5)(-0.5)0.;Vec3.create 0.5(-0.5)0.;Vec3.create 0. 0.5 0.]in
  let mesh=Mesh.create_exn~normals:[Vec3.unit_z;Vec3.unit_z;Vec3.unit_z]~colors:[Color.red;Color.green;Color.blue]positions in
  let camera=Camera.orthographic~height:2.~at:(Vec3.create 0. 0. 2.)~target:Vec3.zero()in
  let material=Material.unlit Color.red in
  let node=Scene3.mesh~material~cull:Scene3.Cull_none mesh in
  let directional=Light.directional~direction:(Vec3.create 0. 0.(-1.))()in
  let spot=Light.spot~at:(Vec3.create 0. 0. 2.)
    ~direction:(Vec3.create 0. 0.(-1.))~cutoff:0.75~concentration:7.()in
  let area=Light.area~at:(Vec3.create 0. 0. 2.)~direction:(Vec3.create 0. 0.(-1.))~width:2.~height:2.~samples:4()in
  let scene=Scene3.create~lights:[directional;spot;area][node]in
  let surface=match Raster2.Surface.create~width:1~height:1()with Ok value->value|Error _->failwith"surface"in
  let raster_texture=match Raster2.Texture.create~color_space:Linear~hard_capacity:4 surface with Ok value->value|Error _->failwith"texture"in
  let resources={texture=(fun _->Ok{Raster2.Triangle.texture=raster_texture;filter=Raster2.Texture.Nearest;address_u=Clamp;address_v=Clamp});shadow=(fun _->Error Shadow_error)}in
  let prepare _frame=lower_view3d~resources~default_viewport:(0,0,16,16)(Scene_description.View3d(camera,scene,Some(0,0,16,16)))|>function Ok value->Marshal.to_bytes value[]|Error _->Bytes.empty in
  let expected=prepare 1 in if expected=Bytes.empty then failwith"colored Scene3 lowering";
  for frame=1 to 600 do if prepare frame<>expected then failwith"Scene3 frame drift"done;
  let workers=Array.init 4(fun _->Domain.spawn(fun()->prepare 1))in Array.iter(fun worker->if Domain.join worker<>expected then failwith"Scene3 domain drift")workers;
  let prepared=match lower_view3d~resources~default_viewport:(0,0,16,16)(View3d(camera,scene,None))with Ok value->value|Error _->failwith"prepared Scene3"in
  List.iter(fun samples->
    let sampled=Scene3.create~samples[node]in
    match lower_view3d~resources~default_viewport:(0,0,16,16)(View3d(camera,sampled,None))with
    | Ok value when value.samples=samples->()
    | _->failwith"Scene3 sample count lost during lowering")[1;4;9;16];
  (try ignore(Scene3.create~samples:2[node]);failwith"unsupported Scene3 sample count accepted"
   with Invalid_argument _->());
  let authored=Array.map(fun(v:Raster2.Scene3_consumer.vertex)->v.color)prepared.draws.(0).vertices in
  if authored<>[|packed_color Color.red;packed_color Color.green;packed_color Color.blue|]then failwith"Scene3 vertex colors lost during lowering";
  (match Mesh.Private.create_owned~normals:[|Vec3.unit_z;Vec3.unit_z;Vec3.unit_z|]~colors:[|Color.red|](Array.of_list positions)with Error _->()|Ok _->failwith"malformed color cardinality accepted");
  let render_colors()=let surface=match Raster2.Surface.create~width:16~height:16()with Ok value->value|Error _->failwith"color surface"in let target={Raster2.Scene3_consumer.color=surface;depth=None;multisample=None}in(match Raster2.Scene3_consumer.render~target~clear:0x000000ffl~clear_depth:prepared.clear_depth~clear_stencil:prepared.clear_stencil~draws:prepared.draws with Ok()->Bytes.copy(Raster2.Surface.bytes surface)|Error _->failwith"colored consumer render")in
  let colored=render_colors()and red_levels=Hashtbl.create 16 in for pixel=0 to Bytes.length colored/4-1 do let offset=pixel*4 in let red=Char.code(Bytes.get colored offset)and green=Char.code(Bytes.get colored(offset+1))and blue=Char.code(Bytes.get colored(offset+2))in if green<>0||blue<>0 then failwith"vertex color escaped red material modulation";if red>0 then Hashtbl.replace red_levels red()done;if Hashtbl.length red_levels<2 then failwith"per-vertex color interpolation was flattened";
  for frame=1 to 600 do if List.mem frame[1;2;60;600]&&render_colors()<>colored then failwith"colored Scene3 frame drift"done;
  let color_workers=Array.init 4(fun _->Domain.spawn render_colors)in Array.iter(fun worker->if Domain.join worker<>colored then failwith"colored Scene3 domain drift")color_workers;
  let fog_scenes =
    [
      ( Fog3.exponential ~color:Color.blue ~density:0.25,
        Raster2.Scene3_lighting.Exponential
          { color = color Color.blue; density = 0.25 } );
      ( Fog3.exponential_squared ~color:Color.green ~density:0.5,
        Raster2.Scene3_lighting.Exponential_squared
          { color = color Color.green; density = 0.5 } );
    ]
  in
  List.iter
    (fun (public_fog, expected_fog) ->
      let fog_scene = Scene3.create ~fog:public_fog [ node ] in
      match
        lower_view3d ~resources ~default_viewport:(0, 0, 16, 16)
          (View3d (camera, fog_scene, None))
      with
      | Ok value when value.draws.(0).lighting.fog = expected_fog -> ()
      | _ -> failwith "public exponential fog lowering")
    fog_scenes;
  if prepared.draws.(0).vertices.(0).normal.z<>1. then failwith"authored normal lost";
  let shared_vertices =
    [
      Vec3.create (-0.5) (-0.5) 0.;
      Vec3.create 0.5 (-0.5) 0.;
      Vec3.create (-0.5) 0.5 0.;
      Vec3.create 0.5 0.5 0.5;
    ]
  in
  let authored_normals =
    [ Vec3.unit_z; Vec3.unit_z; Vec3.create 0. 0.7 0.7; Vec3.create 0.7 0. 0.7 ]
  in
  let reversed_normals = List.map (fun value -> Vec3.scale value (-1.)) authored_normals in
  let shared_mesh normals =
    Mesh.create_exn ~indices:[ 0; 1; 2; 2; 1; 3 ] ~normals shared_vertices
  in
  let shading_scene =
    Scene3.create
      [
        Scene3.mesh ~material ~shading:Scene3.Smooth (shared_mesh authored_normals);
        Scene3.mesh ~material ~shading:Scene3.Flat (shared_mesh authored_normals);
        Scene3.mesh ~material ~shading:Scene3.Smooth (shared_mesh reversed_normals);
      ]
  in
  let shading_prepared =
    match
      lower_view3d ~resources ~default_viewport:(0, 0, 16, 16)
        (View3d (camera, shading_scene, None))
    with
    | Ok value -> value
    | Error _ -> failwith "public shading lowering"
  in
  begin
    match shading_prepared.draws.(0).shading, shading_prepared.draws.(1).shading,
      shading_prepared.draws.(2).shading with
    | Raster2.Scene3_consumer.Smooth, Flat, Smooth -> ()
    | _ -> failwith "public shading mode lost"
  end;
  List.iteri
    (fun index expected ->
      let actual = shading_prepared.draws.(0).vertices.(index).normal in
      if actual <> vec expected then failwith "authored per-vertex normal lost";
      let reversed = shading_prepared.draws.(2).vertices.(index).normal in
      if reversed <> vec (List.nth reversed_normals index) then
        failwith "orientation-reversed terminal normal lost")
    authored_normals;
  let draw=prepared.draws.(0)in
  begin match draw.lighting.lights.(1)with
  | Raster2.Scene3_lighting.Spot value when value.concentration=7.->()
  | _->failwith"spot concentration lost"
  end;
  let custom_depth=Scene3.depth_state~comparison:Greater_equal~write:false()in
  let custom_stencil=Scene3.stencil_state~comparison:Equal~reference:7
    ~read_mask:0x0f~write_mask:0xf0~on_stencil_fail:Replace
    ~on_depth_fail:Increment~on_pass:Invert()in
  let nested=Scene3.with_depth custom_depth[Scene3.with_stencil custom_stencil
    [Scene3.with_blend Add[Scene3.mesh~material~cull:Cull_front mesh]]]in
  let custom_raster=Scene3.raster_state~line_width:3.~point_size:5.()in
  let wire=Scene3.with_raster custom_raster
    [Scene3.mesh~material~mode:Wireframe mesh]in
  let points=Scene3.with_raster custom_raster
    [Scene3.mesh~material~mode:Vertices mesh]in
  let state_scene=Scene3.create~stencil_clear:11[nested;node;wire;points]in
  let state_prepared=match lower_view3d~resources~default_viewport:(0,0,16,16)
    (View3d(camera,state_scene,None))with Ok value->value|Error _->failwith"state lowering"in
  let first=state_prepared.draws.(0)and restored=state_prepared.draws.(1)in
  begin match first.depth_stencil with
  | {depth_compare=Raster2.Depth_stencil.Greater_equal;depth_write=false;
      stencil=Some{compare=Equal;fail=Replace;depth_fail=Increment_clamp;
        pass=Invert;read_mask=0x0f;write_mask=0xf0;reference=7}}->()
  | _->failwith"nested depth/stencil state lost"
  end;
  if first.cull<>Raster2.Triangle.Front||first.blend<>Raster2.Composite.Add||
    restored.depth_stencil.depth_compare<>Raster2.Depth_stencil.Less||
    not restored.depth_stencil.depth_write||state_prepared.clear_stencil<>11 then
    failwith"nested raster/blend state did not restore";
  let blend_cases =
    [Scene3.Replace, Raster2.Composite.Copy; Alpha, Source_over; Add, Add;
     Multiply, Multiply; Screen, Screen; Subtract, Subtract] in
  let blend_scene = Scene3.create
    (List.concat_map (fun (mode, _) ->
       [Scene3.with_blend mode [Scene3.mesh ~material mesh]; node]) blend_cases) in
  let blend_prepared = match lower_view3d ~resources ~default_viewport:(0,0,16,16)
      (View3d (camera, blend_scene, None)) with
    | Ok value -> value | Error _ -> failwith "blend state lowering" in
  List.iteri (fun index (_, expected) ->
    let nested = blend_prepared.draws.(index * 2)
    and restored = blend_prepared.draws.((index * 2) + 1) in
    if nested.blend <> expected || restored.blend <> Raster2.Composite.Source_over then
      failwith "Scene3 blend mapping/restoration") blend_cases;
  begin match state_prepared.draws.(2),state_prepared.draws.(3)with
  | {mode=Raster2.Scene3_consumer.Wireframe;line_width=3.;_},
    {mode=Vertices;point_size=5.;_}->()
  | _->failwith"polygon mode/raster size lost"
  end;
  let quad_vertices =
    [
      Vec3.create (-0.5) (-0.5) 0.;
      Vec3.create 0.5 (-0.5) 0.;
      Vec3.create (-0.5) 0.5 0.;
      Vec3.create 0.5 0.5 0.;
    ]
  in
  let quad_normals = List.map (fun _ -> Vec3.unit_z) quad_vertices in
  let strip =
    Mesh.create_exn ~mode:Mesh.Triangle_strip ~indices:[ 0; 1; 2; 3 ]
      ~normals:quad_normals quad_vertices
  in
  let fan =
    Mesh.create_exn ~mode:Mesh.Triangle_fan ~indices:[ 0; 1; 3; 2 ]
      ~normals:quad_normals quad_vertices
  in
  let topology_scene =
    Scene3.create
      [
        Scene3.with_raster custom_raster
          [ Scene3.mesh ~material ~mode:Wireframe strip ];
        Scene3.with_raster custom_raster
          [ Scene3.mesh ~material ~mode:Vertices fan ];
      ]
  in
  let topology_prepared =
    match
      lower_view3d ~resources ~default_viewport:(0, 0, 16, 16)
        (View3d (camera, topology_scene, None))
    with
    | Ok value -> value
    | Error _ -> failwith "strip/fan topology lowering"
  in
  begin
    match topology_prepared.draws.(0), topology_prepared.draws.(1) with
    | ( { topology = Raster2.Scene3.Triangle_strip; mode = Wireframe;
          line_width = 3.; _ },
        { topology = Raster2.Scene3.Triangle_fan; mode = Vertices;
          point_size = 5.; _ } ) -> ()
    | _ -> failwith "public strip/fan polygon mode lost"
  end;
  let topology_snapshot () = Marshal.to_bytes topology_prepared [] in
  let expected_topology = topology_snapshot () in
  for _frame = 1 to 600 do
    if topology_snapshot () <> expected_topology then
      failwith "strip/fan lowering frame drift"
  done;
  let topology_workers =
    Array.init 4 (fun _ -> Domain.spawn topology_snapshot)
  in
  Array.iter
    (fun worker ->
      if Domain.join worker <> expected_topology then
        failwith "strip/fan lowering domain drift")
    topology_workers;
  let source_mesh mode indices =
    Mesh.create_exn ~mode ~indices ~normals:quad_normals quad_vertices
  in
  let source_topologies =
    [
      (Mesh.Points, [ 0; 1; 2; 3 ], Raster2.Scene3.Point_list);
      (Mesh.Lines, [ 0; 1; 1; 3; 3; 2 ], Raster2.Scene3.Line_list);
      (Mesh.Line_strip, [ 0; 1; 3; 2 ], Raster2.Scene3.Line_strip);
      (Mesh.Line_loop, [ 0; 1; 3; 2 ], Raster2.Scene3.Line_loop);
    ]
  in
  let source_nodes =
    List.concat_map
      (fun (source_mode, indices, _) ->
        let source = source_mesh source_mode indices in
        [
          Scene3.with_raster custom_raster
            [ Scene3.mesh ~material ~mode:Faces source ];
          Scene3.with_raster custom_raster
            [ Scene3.mesh ~material ~mode:Wireframe source ];
          Scene3.with_raster custom_raster
            [ Scene3.mesh ~material ~mode:Vertices source ];
        ])
      source_topologies
  in
  let source_scene = Scene3.create source_nodes in
  let source_prepared =
    match
      lower_view3d ~resources ~default_viewport:(0, 0, 16, 16)
        (View3d (camera, source_scene, None))
    with
    | Ok value -> value
    | Error _ -> failwith "point/line topology lowering"
  in
  if Array.length source_prepared.draws <> 12 then
    failwith "point/line draw cardinality";
  List.iteri
    (fun source_index (_, _, expected_topology) ->
      List.iteri
        (fun mode_index expected_mode ->
          let draw = source_prepared.draws.((source_index * 3) + mode_index) in
          if draw.topology <> expected_topology || draw.mode <> expected_mode then
            failwith "public point/line mode lost";
          if draw.line_width <> 3. || draw.point_size <> 5. then
            failwith "public point/line raster size lost")
        [
          Raster2.Scene3_consumer.Faces;
          Raster2.Scene3_consumer.Wireframe;
          Raster2.Scene3_consumer.Vertices;
        ])
    source_topologies;
  let source_snapshot () = Marshal.to_bytes source_prepared [] in
  let expected_source = source_snapshot () in
  for _frame = 1 to 600 do
    if source_snapshot () <> expected_source then
      failwith "point/line lowering frame drift"
  done;
  let source_workers = Array.init 4 (fun _ -> Domain.spawn source_snapshot) in
  Array.iter
    (fun worker ->
      if Domain.join worker <> expected_source then
        failwith "point/line lowering domain drift")
    source_workers;
  let state_snapshot()=match lower_view3d~resources~default_viewport:(0,0,16,16)
    (View3d(camera,state_scene,None))with
    | Ok value->Marshal.to_bytes value[]|Error _->Bytes.empty in
  let expected_state=state_snapshot()in
  for _frame=1 to 600 do if state_snapshot()<>expected_state then
    failwith"nested state frame drift"done;
  let state_workers=Array.init 4(fun _->Domain.spawn state_snapshot)in
  Array.iter(fun worker->if Domain.join worker<>expected_state then
    failwith"nested state domain drift")state_workers;
  begin match Raster2.Scene3.prepare~matrix:draw.matrix~viewport:draw.viewport~scissor:draw.scissor~topology:draw.topology~vertices:(Array.map(fun(v:Raster2.Scene3_consumer.vertex)->{Raster2.Scene3.x=v.position.x;y=v.position.y;z=v.position.z;color=v.color;u=v.u;v=v.v})draw.vertices)~indices:draw.indices with Ok value when Array.length value.triangles>0->()|_->failwith"Scene3 projection produced no triangles"end;
  let target=match Raster2.Surface.create~width:16~height:16()with Ok value->value|Error _->failwith"target"in
  begin match Raster2.Scene3_consumer.render~target:{color=target;depth=None;multisample=None}~clear:0x000000ffl~clear_depth:prepared.clear_depth~clear_stencil:prepared.clear_stencil~draws:prepared.draws with Ok()->()|Error _->failwith"Scene3 consumer callback"end;
  let changed=ref false in for y=0 to 15 do for x=0 to 15 do match Raster2.Surface.get_rgba target~x~y with Ok value when value<>0x000000ffl->changed:=true|_->()done done;
  if not !changed then failwith"Scene3 framebuffer unchanged";
  let public_texture =
    Texture.init ~width:3 ~height:5 (fun ~x ~y ->
        Color.rgb (x * 80) (y * 40) 127)
    |> Texture.generate_mipmaps
  in
  let texture_states =
    [
      (Texture.Nearest, Texture.Clamp, Texture.Repeat);
      (Texture.Bilinear, Texture.Repeat, Texture.Mirror);
      (Texture.Trilinear, Texture.Mirror, Texture.Clamp);
    ]
  in
  let textured =
    Scene3.create
      (List.map
         (fun (filter, wrap_u, wrap_v) ->
           Scene3.mesh ~material ~cull:Scene3.Cull_none
             ~texture:(Scene3.textured ~filter ~wrap_u ~wrap_v public_texture)
             mesh)
         texture_states)
  in
  let textured_prepared =
    match
      lower_view3d ~resources ~default_viewport:(0, 0, 16, 16)
        (View3d (camera, textured, None))
    with
    | Ok value -> value
    | Error _ -> failwith "textured Scene3 callback"
  in
  let expected_texture_states =
    [
      (Raster2.Texture.Nearest, Raster2.Texture.Clamp, Raster2.Texture.Repeat);
      (Raster2.Texture.Bilinear, Raster2.Texture.Repeat, Raster2.Texture.Mirror);
      (Raster2.Texture.Trilinear, Raster2.Texture.Mirror, Raster2.Texture.Clamp);
    ]
  in
  List.iteri
    (fun index (filter, address_u, address_v) ->
      match textured_prepared.draws.(index).texture with
      | Some value
        when value.texture == raster_texture && value.filter = filter
             && value.address_u = address_u && value.address_v = address_v -> ()
      | _ -> failwith "texture sampling state/identity lost")
    expected_texture_states;
  let textured_snapshot () = Marshal.to_bytes textured_prepared [] in
  let expected_textured = textured_snapshot () in
  for _frame = 1 to 600 do
    if textured_snapshot () <> expected_textured then failwith "texture state frame drift"
  done;
  let texture_workers = Array.init 4 (fun _ -> Domain.spawn textured_snapshot) in
  Array.iter
    (fun worker ->
      if Domain.join worker <> expected_textured then failwith "texture state domain drift")
    texture_workers;
  let rejecting={resources with texture=(fun _->Error Texture_error)}in
  begin match lower_view3d~resources:rejecting~default_viewport:(0,0,16,16)(View3d(camera,textured,None))with Error Texture_error->()|_->failwith"SDL texture not rejected atomically"end;
  let convenience_material = Material.create ~diffuse:(Color.rgb 210 130 40)
      ~ambient:(Color.rgb 30 20 10) ~shininess:7. () in
  let conveniences =
    [
      ("box", Scene3.box ~material:convenience_material ~mode:Wireframe
          ~cull:Cull_none ~shading:Flat ~width:1. ~height:1.2 ~depth:0.8 (),
        Mesh.box ~width:1. ~height:1.2 ~depth:0.8 ());
      ("plane", Scene3.plane ~material:convenience_material ~mode:Wireframe
          ~cull:Cull_none ~shading:Flat ~width:1.4 ~height:1.1 (),
        Mesh.plane ~width:1.4 ~height:1.1 ());
      ("sphere", Scene3.sphere ~material:convenience_material ~mode:Wireframe
          ~cull:Cull_none ~shading:Flat ~radius:0.7 (), Mesh.sphere ~radius:0.7 ());
      ("icosphere", Scene3.icosphere ~material:convenience_material ~mode:Wireframe
          ~cull:Cull_none ~shading:Flat ~radius:0.7 (), Mesh.icosphere ~radius:0.7 ());
      ("cylinder", Scene3.cylinder ~material:convenience_material ~mode:Wireframe
          ~cull:Cull_none ~shading:Flat ~radius:0.6 ~height:1.2 (),
        Mesh.cylinder ~radius:0.6 ~height:1.2 ());
      ("cone", Scene3.cone ~material:convenience_material ~mode:Wireframe
          ~cull:Cull_none ~shading:Flat ~radius:0.6 ~height:1.2 (),
        Mesh.cone ~radius:0.6 ~height:1.2 ());
    ]
  in
  List.iter
    (fun (name,node,canonical) ->
      let value = match lower_view3d ~resources ~default_viewport:(0,0,32,32)
          (View3d(camera,Scene3.create[node],None)) with
        | Ok value -> value | Error _ -> failwith(name^" convenience lowering") in
      let draw=value.draws.(0)in
      if Array.length value.draws<>1||Array.length draw.vertices<>Mesh.vertex_count canonical||
        Array.length draw.indices<>Mesh.index_count canonical||draw.mode<>Raster2.Scene3_consumer.Wireframe||
        draw.shading<>Flat||draw.cull<>Raster2.Triangle.Cull_none then
        failwith(name^" convenience topology/state");
      let color_target=match Raster2.Surface.create~width:32~height:32()with
        Ok target->target|Error _->failwith(name^" target")in
      let depth_target=match Raster2.Depth_stencil.create~width:32~height:32()with
        Ok target->target|Error _->failwith(name^" depth")in
      begin match Raster2.Scene3_consumer.render
          ~target:{color=color_target;depth=Some depth_target;multisample=None}
          ~clear:0x000000ffl~clear_depth:value.clear_depth
          ~clear_stencil:value.clear_stencil~draws:value.draws with
      | Ok()->()|Error _->failwith(name^" consumer")end;
      let changed=ref false in
      for offset=0 to(32*32)-1 do if Bytes.get_int32_le
        (Raster2.Surface.bytes color_target)(offset*4)<>0xff000000l then
        changed:=true done;
      if not !changed then failwith(name^" empty framebuffer");
      let snapshot()=match lower_view3d~resources~default_viewport:(0,0,32,32)
          (View3d(camera,Scene3.create[node],None))with
        | Ok current->Marshal.to_bytes current[]|Error _->Bytes.empty in
      let expected=snapshot()in
      for _frame=1 to 600 do if snapshot()<>expected then
        failwith(name^" frame drift")done;
      let workers=Array.init 4(fun _->Domain.spawn snapshot)in
      Array.iter(fun worker->if Domain.join worker<>expected then
        failwith(name^" domain drift"))workers) conveniences;
  let instance_mesh=Mesh.plane~width:0.5~height:0.5()in
  let transforms=[Mat4.translation(Vec3.create(-1.)0. 0.);Mat4.identity;
    Mat4.translation(Vec3.create 1. 0. 0.)]in
  let instance_scene=Scene3.create[
    Scene3.instances~material:convenience_material~cull:Cull_none instance_mesh transforms;
    Scene3.instances_array~material:convenience_material~cull:Cull_none instance_mesh(Array.of_list transforms)]in
  let instance_prepared=match lower_view3d~resources~default_viewport:(0,0,32,32)
      (View3d(camera,instance_scene,None))with Ok value->value|Error _->failwith"instances lowering"in
  if Array.length instance_prepared.draws<>6 then failwith"instances cardinality";
  for index=0 to 2 do if instance_prepared.draws.(index).matrix<>
    instance_prepared.draws.(index+3).matrix then failwith"instances list/array order"done;
  if instance_prepared.draws.(0).matrix=instance_prepared.draws.(1).matrix||
    instance_prepared.draws.(1).matrix=instance_prepared.draws.(2).matrix then
    failwith"instance transform collapsed";
  let instance_snapshot()=Marshal.to_bytes instance_prepared[]in
  let expected_instances=instance_snapshot()in
  for _frame=1 to 600 do if instance_snapshot()<>expected_instances then
    failwith"instances frame drift"done;
  let instance_workers=Array.init 4(fun _->Domain.spawn instance_snapshot)in
  Array.iter(fun worker->if Domain.join worker<>expected_instances then
    failwith"instances domain drift")instance_workers;
  let shader_texture=Texture.create_exn~width:1~height:1[Color.blue]in
  let shader_uniforms=Shader3.empty_uniforms|>
    Shader3.set_uniform"offset"(Shader3.Float 0.)|>
    Shader3.set_uniform"texture"(Shader3.Texture shader_texture)in
  let functional_shader=Shader3.create~varying_count:1~uniforms:shader_uniforms
    ~vertex:(fun input->let output=Shader3.default_vertex input in
      let offset=Option.value(Shader3.float_uniform"offset"input.uniforms)~default:0. in
      {output with Shader3.varyings=[input.position.x+.offset]})
    ~geometry:(fun input->match input.Shader3.primitive with
      | Shader3.Triangle(a,_,_)->[input.primitive;Shader3.Point a]
      | primitive->[primitive])
    ~fragment:(fun input->if input.Shader3.screen_position.x>14. then Shader3.discard
      else let color=match Shader3.texture_uniform"texture"input.uniforms with
        | Some texture when List.hd input.varyings>0.->Texture.sample texture~u:input.tex_coord.x~v:input.tex_coord.y
        | _->input.color in Shader3.output~depth:0.25 color)()in
  let shader_scene=Scene3.create[Scene3.mesh~material:(Material.unlit Color.white)
    ~cull:Scene3.Cull_none~shader:functional_shader mesh]in
  let shader_prepared=match lower_view3d~resources~default_viewport:(0,0,16,16)
      (View3d(camera,shader_scene,None))with Ok value->value|Error _->failwith"functional shader lowering"in
  begin match shader_prepared.draws.(0).program with
  | Some value when Array.length value.primitives=2&&value.varying_count=1->()
  | _->failwith"vertex/geometry closure output lost"
  end;
  let render_shader()=let surface=match Raster2.Surface.create~width:16~height:16()with Ok value->value|Error _->failwith"shader surface"in
    let depth=match Raster2.Depth_stencil.create~width:16~height:16()with Ok value->value|Error _->failwith"shader depth"in
    match Raster2.Scene3_consumer.render~target:{color=surface;depth=Some depth;multisample=None}
      ~clear:0x000000ffl~clear_depth:1.~clear_stencil:0~draws:shader_prepared.draws with
    | Error _->failwith"functional shader render"|Ok()->Bytes.cat(Bytes.copy(Raster2.Surface.bytes surface))(Bytes.copy(Raster2.Depth_stencil.bytes depth))in
  let shader_pixels=render_shader()in
  let has_color expected=let found=ref false in
    for offset=0 to 255 do
      let index=offset*4 in
      let color=Int32.(logor(shift_left(of_int(Char.code(Bytes.get shader_pixels index)))24)
        (logor(shift_left(of_int(Char.code(Bytes.get shader_pixels(index+1))))16)
          (logor(shift_left(of_int(Char.code(Bytes.get shader_pixels(index+2))))8)
            (of_int(Char.code(Bytes.get shader_pixels(index+3)))))))in
      if color=expected then found:=true
    done;!found in
  let blue=has_color(packed_color Color.blue)and red=has_color(packed_color Color.red)
  and background=has_color 0x000000ffl in
  if not(blue&&red&&background)then
    failwith"functional shader texture/varying/discard pixels missing";
  List.iter(fun _frame->if render_shader()<>shader_pixels then failwith"functional shader frame drift")[1;2;60;600];
  let shader_workers=Array.init 4(fun _->Domain.spawn render_shader)in
  Array.iter(fun worker->if Domain.join worker<>shader_pixels then failwith"functional shader domain drift")shader_workers;
  let malformed=Shader3.create~varying_count:1~vertex:Shader3.default_vertex
    ~fragment:Shader3.default_fragment()in
  let malformed_scene=Scene3.create[Scene3.mesh~material~shader:malformed mesh]in
  (match lower_view3d~resources~default_viewport:(0,0,16,16)(View3d(camera,malformed_scene,None))with
  | Error(Shader_error _)->()|_->failwith"malformed shader varying cardinality accepted");
  let rejected_shader=Shader3.create~vertex:(fun input->let output=Shader3.default_vertex input in
      {output with Shader3.clip_position=(Float.nan,0.,0.,1.)})
    ~fragment:(fun _->failwith"fragment must not run")()in
  let rejected_scene=Scene3.create[Scene3.mesh~material~shader:rejected_shader mesh]in
  let rejected_prepared=match lower_view3d~resources~default_viewport:(0,0,16,16)
      (View3d(camera,rejected_scene,None))with Ok value->value|Error _->failwith"nonfinite preflight setup"in
  let rejected_surface=match Raster2.Surface.create~width:16~height:16()with Ok value->value|Error _->failwith"rejected surface"in
  Raster2.Surface.clear rejected_surface 0x12345678l;
  let rejected_before=Bytes.copy(Raster2.Surface.bytes rejected_surface)in
  begin match Raster2.Scene3_consumer.render~target:{color=rejected_surface;depth=None;multisample=None}
      ~clear:0x000000ffl~clear_depth:1.~clear_stencil:0~draws:rejected_prepared.draws with
  | Error(Raster2.Scene3_consumer.Program_error Raster2.Scene3_program.Non_finite)->()
  | _->failwith"nonfinite programmable output accepted"
  end;
  if Raster2.Surface.bytes rejected_surface<>rejected_before then
    failwith"rejected programmable output mutated framebuffer"

let ()=match Sys.getenv_opt"PRISMEL_TEST_SCENE_RASTER2_LOWERING"with Some"1"->self_test()|_->()
