open Rays

let camera=Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.) ~target:Vec3.zero ()
let stage mesh=
  let scene=Scene3.create [Scene3.mesh ~material:(Material.unlit Color.white) mesh]in
  let staged=Result.get_ok(Scene.Private.stage_native ~width:128 ~height:128 [Scene.view3d ~camera scene])in
  (List.hd staged.scene3).entries.(0)
let attributes (entry:Scene_execution.scene3_entry)=Option.get entry.vertex_attributes|>snd
let float bytes offset=Int32.float_of_bits(Bytes.get_int32_le bytes offset)
let make colors=
  let vertices:Mesh.Private.vec3_view={
    x=[|-.0.70000001;0.60000001;0.10000001|];
    y=[|-.0.60000001;-.0.50000001;0.80000001|];z=[|0.;0.;0.|]}in
  let normals:Mesh.Private.vec3_view={x=[|0.;0.;0.|];y=[|0.;0.;0.|];z=[|1.;1.;1.|]}in
  vertices,normals,[|0;1;2|],colors
let mesh (vertices,normals,indices,colors)=
  Result.get_ok(Mesh.Private.create_packed_shared ~normals ~indices ~colors vertices)

(* Preserve the original f64 renderer ABI as an independent native oracle. *)
let legacy source (entry:Scene_execution.scene3_entry)=
  let view=Mesh.Private.view source in
  let bytes=Bytes.make(Array.length view.vertices*68)'\000'in
  Array.iteri(fun i(position:Vec3.t)->
    let normal=(Option.get view.normals).(i)in
    let put at value=Bytes.set_int64_le bytes(i*68+at)(Int64.bits_of_float value)in
    put 0 position.x;put 8 position.y;put 16 position.z;
    put 24 normal.x;put 32 normal.y;put 40 normal.z;
    let color=(Option.get view.colors).(i)in
    Bytes.set_int32_le bytes(i*68+48)(Int32.of_int((color.r lsl 24)lor(color.g lsl 16)lor(color.b lsl 8)lor color.a)))view.vertices;
  let uniforms=Bytes.copy(Option.get entry.draw.state.transform_uniforms)in
  Bytes.set_int32_le uniforms(82*4)0l;
  {entry with vertex_attributes=None;draw={
    mesh={entry.draw.mesh with key=entry.draw.mesh.key^":legacy:"^
      Digest.to_hex(Digest.bytes bytes);vertices=bytes};
    state={entry.draw.state with transform_uniforms=Some uniforms}}}

let native source second_source first second=
  match Runtime.create_offscreen ~logical_width:128 ~logical_height:128 ~width:128 ~height:128 ()with
  |Error error->failwith(Ogpu.Error.to_string error)
  |Ok runtime->Fun.protect ~finally:(fun()->ignore(Runtime.destroy runtime))(fun()->
      let get=function Ok value->value|Error error->failwith(Ogpu.Error.to_string error)in
      let render entry=
        ignore(get(Runtime.render_sampled_resources ~clear:(0.,0.,0.,1.) runtime [entry]));
        get(Runtime.read_pixels runtime ~bytes_per_row:512)in
      let old=render(legacy source first)and current=render first in
      let maximum=ref 0 in
      for i=0 to Bytes.length current-1 do
        maximum:=max !maximum(abs(Char.code(Bytes.get old i)-Char.code(Bytes.get current i)))
      done;
      Printf.printf "Scene3 f64/f32 triangle maximum channel difference: %d\n%!"!maximum;
      if !maximum>1 then failwith "float32 triangle exceeds one-channel tolerance";
      let before=(Runtime.stats runtime).uploaded_bytes in
      let changed=render second in
      let uploaded=Int64.sub(Runtime.stats runtime).uploaded_bytes before in
      if changed=current then failwith "recolour did not change visible triangle pixels";
      (* Compare the recoloured mesh with its own independent f64 oracle. *)
      let oracle=render(legacy second_source second)in
      let maximum=ref 0 in
      for i=0 to Bytes.length changed-1 do
        maximum:=max !maximum(abs(Char.code(Bytes.get oracle i)-Char.code(Bytes.get changed i)))
      done;
      if !maximum>1 then failwith "recoloured float32 triangle exceeds one-channel tolerance";
      if uploaded<>36L then failwith(Printf.sprintf "color edit reuploaded geometry (%Ld bytes)"uploaded);
      ignore(get(Runtime.render_sampled_resources ~clear:(0.,0.,0.,1.) runtime
        (List.init 65(fun _->second))));
      let combined=get(Runtime.read_pixels runtime ~bytes_per_row:512)in
      if combined<>changed then failwith "coalescing lost the float32 attribute stream")

let run ()=
  let vertices,normals,indices,colors=make[|Color.red;Color.green;Color.blue|]in
  let source=mesh(vertices,normals,indices,colors)in
  let first=stage source in
  assert(Bytes.length first.draw.mesh.vertices=72&&Bytes.length(attributes first)=36);
  assert(float first.draw.mesh.vertices 0=Int32.float_of_bits(Int32.bits_of_float vertices.x.(0)));
  assert(Bytes.get_int32_le(attributes first)0=0xff0000ffl);
  let same=stage(mesh(vertices,normals,indices,colors))in
  assert(first.draw.mesh.vertices==same.draw.mesh.vertices&&first.vertex_attributes=same.vertex_attributes);
  let second=stage(mesh(vertices,normals,indices,[|Color.blue;Color.red;Color.green|]))in
  assert(first.draw.mesh.key=second.draw.mesh.key&&first.draw.mesh.vertices==second.draw.mesh.vertices);
  assert(first.draw.mesh.indices==second.draw.mesh.indices&&attributes first<>attributes second);
  let with_uv values=Result.get_ok(Mesh.Private.create_packed_shared
    ~normals ~indices ~colors ~tex_coords:values vertices)in
  let uv=stage(with_uv[|Vec2.create 0.25 0.5;Vec2.zero;Vec2.zero|])in
  assert(uv.draw.mesh.vertices==first.draw.mesh.vertices);
  assert(float(attributes uv)4=0.25&&float(attributes uv)8=0.5);
  let different_normals={normals with Mesh.Private.x=[|1.;1.;1.|]}in
  let normal_edit=stage(mesh(vertices,different_normals,indices,colors))in
  assert(normal_edit.draw.mesh.key<>first.draw.mesh.key);
  let invalid_uv=Scene3.create[Scene3.mesh(with_uv[|Vec2.create 1e100 0.;Vec2.zero;Vec2.zero|])]in
  assert(Result.is_error(Scene.Private.stage_native ~width:128 ~height:128
    [Scene.view3d ~camera invalid_uv]));
  let overflow={vertices with Mesh.Private.x=[|1e100;0.;0.|]}in
  let scene=Scene3.create[Scene3.mesh(mesh(overflow,normals,indices,colors))]in
  assert(Result.is_error(Scene.Private.stage_native ~width:128 ~height:128 [Scene.view3d ~camera scene]));
  print_endline "Scene3 float32: 36-byte split mirror, immutable component reuse, color invalidation, finite narrowing"

let run_native ()=
  let vertices,normals,indices,colors=make[|Color.red;Color.green;Color.blue|]in
  let source=mesh(vertices,normals,indices,colors)in
  let first=stage source in
  let second_source=mesh(vertices,normals,indices,[|Color.blue;Color.red;Color.green|])in
  let second=stage second_source in
  native source second_source first second
