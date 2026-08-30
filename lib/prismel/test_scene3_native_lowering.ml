open Prismel

let () =
  let camera=Camera.orthographic~height:2.~at:(Vec3.create 0. 0. 2.)
    ~target:Vec3.zero()in
  let prepare ~width ~height scene =
    match Scene.Private.stage_native ~width ~height [Scene.view3d~camera scene] with
    | Ok { scene3 = [ prepared ]; _ } -> prepared
    | Ok _ -> failwith "native Scene3 staging cardinality"
    | Error message -> failwith message
  in
  begin match Scene.Private.stage_native ~width:0 ~height:16
    [Scene.view3d~camera Scene3.empty] with
  |Error _->print_endline"native Scene3 lowering: typed viewport rejection"
  |_->failwith"native Scene3 accepted empty viewport" end;
  let mesh=Mesh.create_exn~indices:[0;1;2]
    ~normals:[Vec3.unit_z;Vec3.unit_z;Vec3.unit_z]
    ~colors:[Color.red;Color.green;Color.blue]
    [Vec3.create(-0.5)(-0.5)0.;Vec3.create 0.5(-0.5)0.;Vec3.create 0. 0.5 0.]in
  let scene=Scene3.create[Scene3.mesh~material:(Material.unlit Color.white)mesh]in
  let retained_frame=Scene.[clear Color.black;view3d~camera scene]in
  let retained_first=Result.get_ok(Scene.Private.stage_native~width:16~height:16
    retained_frame)in
  let retained_second=Result.get_ok(Scene.Private.stage_native~width:16~height:16
    retained_frame)in
  if retained_first != retained_second then
    failwith"resource-free retained frame did not reuse native staging";
  let reusable_view=Scene.[view3d~camera scene]in
  let before_release=Result.get_ok(Scene.Private.stage_native~width:16~height:16
    reusable_view)in
  Scene.Private.release reusable_view;
  let after_release=Result.get_ok(Scene.Private.stage_native~width:16~height:16
    reusable_view)in
  if before_release.scene3<>after_release.scene3 then
    failwith"released reusable View3d changed prepared native data";
  let prepared=prepare ~width:16 ~height:16 scene in
  if Array.length prepared.entries<>1 then failwith"native triangle draw count";
  let entry=prepared.entries.(0)and vertices=prepared.entries.(0).draw.mesh.vertices in
  if Bytes.length vertices<>204||entry.draw.mesh.index_count<>3 then failwith"native Scene3 ABI cardinality";
  if Int64.float_of_bits(Bytes.get_int64_le vertices 0)<>(-0.5)||Bytes.get_int32_le vertices 48<>0xff0000ffl then failwith"native Scene3 vertex ABI";
  (match entry.draw.state.transform_uniforms with Some bytes when Bytes.length bytes=5456&&Int32.float_of_bits(Bytes.get_int32_le bytes(64*4))=1.->()|_->failwith"native Scene3 uniform ABI");
  let staged=Result.get_ok(Scene.Private.stage_native~width:16~height:16
    [Scene.view3d~camera scene])in
  if List.length staged.scene3<>1||Array.length(List.hd staged.scene3).entries<>1 then
    failwith"View3d did not reach structured native staging";
  let texture=Texture.init~width:2~height:2(fun~x~y->if x=y then Color.red else Color.blue)|>Texture.generate_mipmaps in
  let textured=Scene3.create[Scene3.mesh~texture:(Scene3.textured~filter:Texture.Trilinear texture)mesh]in
  let textured_frame=Scene.[clear Color.black;view3d~camera textured]in
  if Result.get_ok(Scene.Private.stage_native~width:16~height:16 textured_frame)
      == Result.get_ok(Scene.Private.stage_native~width:16~height:16 textured_frame)
  then failwith"resource-bearing retained frame reused stale native staging";
  let textured_stage=Result.get_ok(Scene.Private.stage_native~width:16~height:16[Scene.view3d~camera textured])in
  let textured_entry=(List.hd textured_stage.scene3).entries.(0)in
  (match textured_entry.family,textured_entry.texture with Scene_execution.Scene3_textured,Some value when Array.length value.levels=2&&Bytes.length value.levels.(0).bytes=16->()|_->failwith"native texture mip/sampler staging");
  let light=Light.directional~direction:(Vec3.create 0. 0.(-1.))()in
  let shadow=Shadow3.create~light~camera~width:1~height:1~depths:[|0.5|]()in
  let shadowed=Scene3.create~lights:[light]~shadows:[shadow][Scene3.mesh mesh]in
  let shadow_stage=Result.get_ok(Scene.Private.stage_native~width:16~height:16[Scene.view3d~camera shadowed])in
  let shadow_entry=(List.hd shadow_stage.scene3).entries.(0)in
  (match shadow_entry.family,shadow_entry.auxiliary with Scene_execution.Scene3_shadow,Some value when Bytes.length value.buffer=84->()|_->failwith"native shadow staging");
  let strip=Mesh.create_exn~mode:Mesh.Triangle_strip~indices:[0;1;2;3]
    ~normals:[Vec3.unit_z;Vec3.unit_z;Vec3.unit_z;Vec3.unit_z]
    [Vec3.zero;Vec3.unit_x;Vec3.unit_y;Vec3.create 1. 1. 0.]in
  let strip_scene=Scene3.create[Scene3.mesh strip]in
  let strip_prepared=prepare ~width:16 ~height:16 strip_scene in
  let encoded=strip_prepared.entries.(0).draw.mesh.indices in
  let actual=Array.init 6(fun index->Int32.to_int(Bytes.get_int32_le encoded(index*4)))in
  if actual<>[|0;1;2;2;1;3|]then failwith"native triangle strip winding";
  let first=prepare ~width:16 ~height:16 scene in
  let second=prepare ~width:16 ~height:16 scene in
  if first != second then
    failwith"stable texture-free Scene3 did not reuse its prepared payload";
  if first.entries.(0).draw.mesh.vertices != second.entries.(0).draw.mesh.vertices
    || first.entries.(0).draw.mesh.key <> second.entries.(0).draw.mesh.key then
    failwith"stable Scene3 mesh was repacked for a camera-only prepare";
  ();
  let canvas=Canvas.create_exn~width:64~height:64 in
  Fun.protect~finally:(fun()->Canvas.destroy canvas)(fun()->
    let count=4096 in
    let points=List.init count(fun i->
      Vec3.create(float(i mod 64)/.32.-.1.)(float(i/64)/.32.-.1.)0.)in
    let normals=List.init count(fun _->Vec3.unit_z)in
    let indices=List.init((count-2)*3)(fun i->
      if i mod 3=0 then 0 else i/3+(i mod 3))in
    let heavy=Mesh.create_exn~indices~normals points in
    let world=Scene3.create[Scene3.mesh~material:(Material.unlit Color.red)heavy]in
    let cam_at position=
      Camera.orthographic~height:2.~at:position~target:Vec3.zero()in
    Canvas.render canvas Scene.[clear Color.black;
      view3d~viewport:(0,0,64,64)~camera:(cam_at(Vec3.create 0. 0. 2.))world];
    let after_first=(Canvas.Private.native_stats canvas).uploaded_bytes in
    Canvas.render canvas Scene.[clear Color.black;
      view3d~viewport:(0,0,64,64)~camera:(cam_at(Vec3.create 0.2 0. 2.))world];
    let delta=Int64.sub(Canvas.Private.native_stats canvas).uploaded_bytes after_first in
    if delta>32_768L then
      failwith(Printf.sprintf
        "camera orbit reuploaded Scene3 vertices (%Ld bytes)" delta));
  print_endline"native Scene3 lowering: exact released View3d reuse, geometry, uniforms, texture mips, shadow, stable orbit pack"
