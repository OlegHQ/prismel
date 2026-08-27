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
let auxiliary_lifecycle renderer control mesh state =
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"auxiliary-test";min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
  let texture key color:Scene_execution.sampled_texture={key;levels=[|{width=1;height=1;bytes=Bytes.of_string color}|];sampler}in
  let primary=texture"primary""\255\255\255\255"in
  let auxiliary key:Scene_execution.auxiliary_resource={key;buffer=Bytes.make 84 '\001';texture=texture("texture-"^key)"\128\128\128\255"}in
  let draw={Scene_execution.mesh;state}in
  Ogpu.Backend_mock.clear_trace control;
  let invalid={Scene_execution.key="invalid";buffer=Bytes.empty;texture=texture"never-created""\000\000\000\255"}in
  begin match Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some primary,Some invalid,draw]with Error e when e.Ogpu.Error.kind=Invalid_argument->()|_->failwith"auxiliary preflight was not atomic"end;
  if Ogpu.Backend_mock.trace control<>[]then failwith"failed preflight allocated or submitted resources";
  let first=auxiliary"light-a"and second=auxiliary"light-b"in
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw]));
  let uploaded=Scene_execution.upload_bytes renderer in
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw]));
  if Scene_execution.upload_bytes renderer<>uploaded then failwith"retained auxiliary resources reuploaded";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw;Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw]));
  let renders=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"render:")in
  if List.length renders<>1 then failwith"equal auxiliary resources did not batch";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw;Scene2,Ogpu.Pipeline.Replace,Some primary,Some second,draw]));
  let renders=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"render:")in
  if List.length renders<>2 then failwith"distinct auxiliary resources batched together"
let oversized_frame () =
  let driver,control=Ogpu.Backend_mock.create()in
  let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create driver configuration)in
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None}in
  let draws count=List.init count(fun index->{Scene_execution.mesh={key=Printf.sprintf"oversized-%05d"index;vertices;vertex_count=3;indices;index_count=3};state})in
  ignore(get(Scene_execution.render renderer(draws 65)));
  if Scene_execution.cache_entries renderer<>1 then failwith">64 frame was not coalesced";
  Ogpu.Backend_mock.clear_trace control;
  let before=Scene_execution.upload_bytes renderer in
  ignore(get(Scene_execution.render renderer(draws 18_278)));
  let uploaded=Int64.sub(Scene_execution.upload_bytes renderer)before in
  if uploaded<>Int64.of_int(18_278*60)then failwith"exact oversized upload cardinality";
  let renders=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"render:")in
  if List.length renders<>1 then failwith"exact oversized frame lost ordered batching";
  if Scene_execution.cache_entries renderer<>2 then failwith"exact frame escaped coalesced cache";
  let warm=Scene_execution.upload_bytes renderer in
  ignore(get(Scene_execution.render renderer(draws 18_278)));
  if Scene_execution.upload_bytes renderer<>warm then failwith"stable coalesced frame reuploaded";
  let sampled values=List.map(fun draw->Scene_execution.Scene2,Ogpu.Pipeline.Replace,None,None,1,draw)values in
  let stable=sampled(draws 18_278)in
  ignore(get(Scene_execution.render_prepared_sampled_resources~identity:"exact-18278"~version:1L renderer stable));
  let prepared_upload=Scene_execution.upload_bytes renderer in
  ignore(get(Scene_execution.render_prepared_sampled_resources~identity:"exact-18278"~version:1L renderer []));
  if Scene_execution.upload_bytes renderer<>prepared_upload then failwith"prepared identity hit reuploaded";
  Gc.full_major();
  let allocated_before=Gc.allocated_bytes()in
  for _=1 to 100 do ignore(get(Scene_execution.render_prepared_sampled_resources~identity:"exact-18278"~version:1L renderer []))done;
  let allocated_per_frame=(Gc.allocated_bytes()-.allocated_before)/.100. in
  if allocated_per_frame>100_000. then failwith(Printf.sprintf"prepared warm allocation %.0f bytes/frame"allocated_per_frame);
  let changed=match draws 18_278 with []->assert false|first::rest->{first with mesh={first.mesh with vertices=Bytes.make 48 '\001'}}::rest in
  ignore(get(Scene_execution.render_prepared_sampled_resources~identity:"exact-18278"~version:2L renderer(sampled changed)));
  if Scene_execution.upload_bytes renderer<=prepared_upload then failwith"prepared version change did not invalidate";
  Ogpu.Backend_mock.inject_device_loss control;
  begin match Scene_execution.render renderer(draws 65)with Error e when e.Ogpu.Error.kind=Device_lost->()|_->failwith"oversized device loss did not unwind"end;
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"oversized frame leaked objects"
let replacement_reuse () =
  let driver,control=Ogpu.Backend_mock.create()in
  let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create driver configuration)in
  let indices=Bytes.make 12 '\000'and state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None}in
  let make byte={Scene_execution.key="mutable";vertices=Bytes.make 48 byte;vertex_count=3;indices;index_count=3}in
  ignore(get(Scene_execution.render renderer[{mesh=make '\000';state}]));
  let before=Scene_execution.upload_bytes renderer in Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render renderer[{mesh=make '\001';state}]));
  if Scene_execution.upload_bytes renderer<>Int64.add before 60L then failwith"same-size replacement upload cardinality";
  if List.exists(String.starts_with~prefix:"create-buffer:")(Ogpu.Backend_mock.trace control)then failwith"same-size replacement allocated a buffer";
  Ogpu.Backend_mock.clear_trace control;
  let other={state with scissor=(1,1,7,7)}in
  ignore(get(Scene_execution.render renderer[{mesh=make '\001';state};{mesh=make '\002';state=other}]));
  let creates=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"create-buffer:")in
  if List.length creates<>1 then failwith"same-submission replacement aliased a reserved buffer";
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"replacement reuse leaked objects";
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create driver configuration)in
  ignore(get(Scene_execution.render renderer[{mesh=make '\000';state}]));
  let before=Scene_execution.upload_bytes renderer in Ogpu.Backend_mock.inject_device_loss control;
  begin match Scene_execution.render renderer[{mesh=make '\001';state}]with Error e when e.Ogpu.Error.kind=Device_lost->()|_->failwith"replacement device loss was not reported"end;
  if Scene_execution.upload_bytes renderer<>before then failwith"device loss mutated replacement cache";
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"replacement device loss leaked objects"
let coalesced_signature () =
  let driver,control=Ogpu.Backend_mock.create()in
  let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create driver configuration)in
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None}in
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  let draws=List.init 18_278(fun index->{Scene_execution.mesh={key=Printf.sprintf"domain-%05d"index;vertices;vertex_count=3;indices;index_count=3};state})in
  ignore(get(Scene_execution.render renderer draws));
  let renders=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"render:")in
  let signature=Scene_execution.upload_bytes renderer,Scene_execution.cache_entries renderer,List.length renders in
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"domain coalescing leaked objects";
  signature
let domain_coalescing () =
  let expected=coalesced_signature()in
  let workers=Array.init 4(fun _->Domain.spawn coalesced_signature)in
  Array.iter(fun worker->if Domain.join worker<>expected then failwith"coalesced payload changed across domains")workers
let depth_target_lifecycle () =
  let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let mesh:Scene_execution.mesh={key="depth-lifecycle";vertices=Bytes.make 48 '\000';vertex_count=3;indices=Bytes.make 12 '\000';index_count=3}in
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None}in
  let draw={Scene_execution.mesh;state}in
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create_variants driver configuration)in
  let creations=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"create-depth-texture:")in
  let max_samples=Ogpu.Capabilities.minimum_m1.Ogpu.Capabilities.limits.max_sample_count in
  let expected=List.filter(fun samples->samples<=max_samples)[1;4;9;16]|>List.length in
  if List.length creations<>expected then failwith"depth target count did not match provisioned sample variants";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_family renderer[Scene2,Ogpu.Pipeline.Replace,draw]));
  if not(List.exists(String.starts_with~prefix:"render:nodepth:")(Ogpu.Backend_mock.trace control))then failwith"Scene2 acquired a depth attachment";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_family renderer[Scene3,Ogpu.Pipeline.Replace,draw]));
  if not(List.exists(String.starts_with~prefix:"render:depth:")(Ogpu.Backend_mock.trace control))then failwith"Scene3 omitted its depth attachment";
  let before=Ogpu.Backend_mock.live_counts control in
  Ogpu.Backend_mock.fail_depth_allocation_after control 0;
  begin match Scene_execution.resize renderer{configuration with physical_width=16;physical_height=12}with Error _->()|Ok()->failwith"depth allocation failure did not roll back resize"end;
  if Ogpu.Backend_mock.live_counts control<>before then failwith"failed depth resize changed live targets";
  Ogpu.Backend_mock.fail_next_configure control;
  begin match Scene_execution.resize renderer{configuration with physical_width=16;physical_height=12}with Error _->()|Ok()->failwith"configure failure did not roll back resize"end;
  if Ogpu.Backend_mock.live_counts control<>before then failwith"configure rollback changed live targets";
  ignore(get(Scene_execution.render_family renderer[Scene3,Ogpu.Pipeline.Replace,draw]));
  Ogpu.Backend_mock.inject_device_loss control;
  begin match Scene_execution.render_family renderer[Scene3,Ogpu.Pipeline.Replace,draw]with Error e when e.Ogpu.Error.kind=Device_lost->()|_->failwith"depth renderer device loss was not reported"end;
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"depth targets survived device-loss destruction";
  let driver,control=Ogpu.Backend_mock.create()in
  Ogpu.Backend_mock.fail_depth_allocation_after control 1;
  begin match Scene_execution.create_variants driver configuration with Error _->()|Ok renderer->ignore(Scene_execution.destroy renderer);failwith"partial depth allocation unexpectedly succeeded"end;
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"partial depth allocation leaked objects"
let ()=let driver,control=Ogpu.Backend_mock.create()in let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in let renderer=get(Scene_execution.create driver configuration)in let mesh:Scene_execution.mesh={key="triangle";vertices=Bytes.make 48 '\000';vertex_count=3;indices=Bytes.make 12 '\000';index_count=3}and state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None}in for _=1 to 1000 do ignore(get(Scene_execution.render renderer[{mesh;state}]))done;
  shadow_payload();
  List.iter(fun blend->List.iter(fun _frame->ignore(get(Scene_execution.render_blended renderer[blend,{mesh;state}])))[1;2;60;600])
    [Ogpu.Pipeline.Replace;Alpha;Add;Multiply;Screen;Subtract];
  let pipelines=Ogpu.Backend_mock.trace control|>List.filter(fun value->String.starts_with~prefix:"pipeline:"value)in
  if List.length pipelines<>6||List.length(List.sort_uniq String.compare pipelines)<>6 then failwith"blend pipeline variants/cache";
  if Scene_execution.upload_bytes renderer<>60L then failwith"stable mesh reuploaded";
  auxiliary_lifecycle renderer control mesh state;
  oversized_frame();
  replacement_reuse();
  domain_coalescing();
  depth_target_lifecycle();
  get(Scene_execution.destroy renderer);if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"scene execution leaked";print_endline"scene execution: neutral cache/upload/pass, auxiliary resources, blend variants, 1000 frames, zero delta"
