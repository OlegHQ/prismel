let state : Scene_execution.state =
  { viewport=(0,0,16,16);scissor=(0,0,16,16);
    cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Less_equal;
    depth_write=true;depth_load=Ogpu.Render_pass.Clear;depth_clear=1.;
    transform_uniforms=Some(Bytes.make 208 '\000');stencil_state=None;
    stencil_load=Ogpu.Render_pass.Clear;stencil_clear=0 }

let mesh : Scene_execution.mesh =
  {key="scene3:test";vertices=Bytes.make(3*68)'\000';vertex_count=3;
   indices=Bytes.make 12 '\000';index_count=3}

let entry : Scene_execution.scene3_entry =
  {family=Scene3;blend=Ogpu.Pipeline.Replace;texture=None;auxiliary=None;
   samples=1;draw={mesh;state}}

let () =
  let source=[|entry|]in
  let prepared=Result.get_ok(Scene_execution.prepare_scene3
    ~clear:(0.,0.,0.,1.)~clear_depth:1.~clear_stencil:0 source)in
  if Array.length prepared.entries<>1||prepared.entries==source then
    failwith"prepared Scene3 entry array ownership";
  let textured={entry with family=Scene3_textured}in
  if Result.is_ok(Scene_execution.prepare_scene3~clear:(0.,0.,0.,1.)
    ~clear_depth:1.~clear_stencil:0[|textured|])then
    failwith"textured Scene3 accepted without texture";
  let invalid={entry with draw={entry.draw with state={state with viewport=(0,0,0,16)}}}in
  if Result.is_ok(Scene_execution.prepare_scene3~clear:(0.,0.,0.,1.)
    ~clear_depth:1.~clear_stencil:0[|invalid|])then
    failwith"Scene3 accepted empty viewport";
  if Result.is_ok(Scene_execution.prepare_scene3~clear:(0.,0.,0.,1.)
    ~clear_depth:nan~clear_stencil:0[|entry|])then
    failwith"Scene3 accepted non-finite clear";
  print_endline"prepared Scene3: exact native validation"
