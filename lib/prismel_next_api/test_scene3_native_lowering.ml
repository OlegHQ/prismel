open Prismel_next_api

let () =
  let resources:Scene3_native_lowering.resources={
    texture=(fun _->Error Unsupported_texture);
    shadow=(fun _->Error Unsupported_shadow)}in
  let camera=Camera.orthographic~height:2.~at:(Vec3.create 0. 0. 2.)
    ~target:Vec3.zero()in
  begin match Scene3_native_lowering.prepare~resources~camera~viewport:(0,0,0,16)
    Scene3.empty with
  |Error Invalid_viewport->print_endline"native Scene3 lowering: typed viewport rejection"
  |_->failwith"native Scene3 accepted empty viewport" end;
  let mesh=Mesh.create_exn~indices:[0;1;2]
    ~normals:[Vec3.unit_z;Vec3.unit_z;Vec3.unit_z]
    ~colors:[Color.red;Color.green;Color.blue]
    [Vec3.create(-0.5)(-0.5)0.;Vec3.create 0.5(-0.5)0.;Vec3.create 0. 0.5 0.]in
  let scene=Scene3.create[Scene3.mesh~material:(Material.unlit Color.white)mesh]in
  let prepared=match Scene3_native_lowering.prepare~resources~camera
    ~viewport:(0,0,16,16)scene with Ok value->value|Error _->failwith"native triangle lowering"in
  if Array.length prepared.entries<>1 then failwith"native triangle draw count";
  let entry=prepared.entries.(0)and vertices=prepared.entries.(0).draw.mesh.vertices in
  if Bytes.length vertices<>204||entry.draw.mesh.index_count<>3 then failwith"native Scene3 ABI cardinality";
  if Int64.float_of_bits(Bytes.get_int64_le vertices 0)<>(-0.5)||Bytes.get_int32_le vertices 48<>0xff0000ffl then failwith"native Scene3 vertex ABI";
  (match entry.draw.state.transform_uniforms with Some bytes when Bytes.length bytes=5456&&Int32.float_of_bits(Bytes.get_int32_le bytes(64*4))=1.->()|_->failwith"native Scene3 uniform ABI");
  let staged=Result.get_ok(Scene.Private.stage_native~width:16~height:16
    [Scene.view3d~camera scene])in
  if List.length staged.scene3<>1||Array.length(List.hd staged.scene3).entries<>1 then
    failwith"View3d did not reach structured native staging";
  print_endline"native Scene3 lowering: 68-byte vertices, 5456-byte uniforms, staged View3d"
