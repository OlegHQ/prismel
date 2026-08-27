let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let shadow=function Ok x->x|Error _->failwith"shadow map error"
let shadow_payload () =
  let open Raster2.Shadow_map in
  let map=shadow(create~width:2~height:2)in shadow(clear map~depth:1.);shadow(write map~x:1~y:0~depth:0.25);
  let prepared=shadow(prepare map~light_kind:Directional~matrix:[|1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.;0.;0.;0.;0.;1.|]~bias:{constant=0.01;slope=0.02}~kernel:Tap9)in
  let resource=get(Scene_execution.shadow_resource~key:"light-0"(snapshot prepared))in
  let pixels=resource.texture.levels.(0).bytes in
  if Bytes.length pixels<>16||Char.code(Bytes.get pixels 4)<>64||Char.code(Bytes.get pixels 5)<>0||Char.code(Bytes.get pixels 6)<>0 then failwith"shadow depth packing";
  if Bytes.length resource.parameters<>84 then failwith"shadow parameter block";
  let malformed=snapshot prepared in malformed.depths.(0)<-nan;
  begin match Scene_execution.shadow_resource~key:"invalid"malformed with Error _->()|Ok _->failwith"non-finite shadow accepted"end
let ()=let driver,control=Ogpu.Backend_mock.create()in let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in let renderer=get(Scene_execution.create driver configuration)in let mesh:Scene_execution.mesh={key="triangle";vertices=Bytes.make 48 '\000';vertex_count=3;indices=Bytes.make 12 '\000';index_count=3}and state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8)}in for _=1 to 1000 do ignore(get(Scene_execution.render renderer[{mesh;state}]))done;
  shadow_payload();
  List.iter(fun blend->List.iter(fun _frame->ignore(get(Scene_execution.render_blended renderer[blend,{mesh;state}])))[1;2;60;600])
    [Ogpu.Pipeline.Replace;Alpha;Add;Multiply;Screen;Subtract];
  let pipelines=Ogpu.Backend_mock.trace control|>List.filter(fun value->String.starts_with~prefix:"pipeline:"value)in
  if List.length pipelines<>6||List.length(List.sort_uniq String.compare pipelines)<>6 then failwith"blend pipeline variants/cache";
  if Scene_execution.upload_bytes renderer<>60L then failwith"stable mesh reuploaded";get(Scene_execution.destroy renderer);if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"scene execution leaked";print_endline"scene execution: neutral cache/upload/pass, blend variants, 1000 frames, zero delta"
