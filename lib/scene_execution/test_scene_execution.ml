let get=function Ok x->x|Error e->failwith(Ogpu.Error.to_string e)
let prepared_clear_cache_key () =
  let driver,_=Ogpu_raster2.create()in
  let configuration:Ogpu.Surface.configuration={logical_width=4;logical_height=4;physical_width=4;physical_height=4;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create driver configuration)in
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  List.iteri(fun index(x,y)->Bytes.set_int64_le vertices(index*16)(Int64.bits_of_float x);Bytes.set_int64_le vertices(index*16+8)(Int64.bits_of_float y))[1.,1.;2.,1.;1.,2.];
  Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  let mesh:Scene_execution.mesh={key="prepared-clear";vertices;vertex_count=3;indices;index_count=3}and state:Scene_execution.state={viewport=(0,0,4,4);scissor=(0,0,4,4);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
  let draws=[Scene_execution.Scene2,Ogpu.Pipeline.Replace,None,None,1,{Scene_execution.mesh;state}]in
  ignore(get(Scene_execution.render_prepared_sampled_resources~clear:(1.,0.,0.,1.)~identity:"clear-key"~version:1L renderer draws));
  let red=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in
  ignore(get(Scene_execution.render_prepared_sampled_resources~clear:(0.,0.,1.,1.)~identity:"clear-key"~version:1L renderer []));
  let blue=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in
  if red=blue||Char.code(Bytes.get red 0)<>255||Char.code(Bytes.get blue 2)<>255 then failwith"prepared clear-color cache key reused stale command";
  ignore(get(Scene_execution.render_sampled_resources~clear:(1.,0.,0.,1.) renderer draws));
  let automatic_red=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in
  ignore(get(Scene_execution.render_sampled_resources~clear:(0.,0.,1.,1.) renderer draws));
  let automatic_blue=get(Scene_execution.read_pixels renderer~bytes_per_row:16)in
  if automatic_red=automatic_blue||Char.code(Bytes.get automatic_red 0)<>255||
     Char.code(Bytes.get automatic_blue 2)<>255 then
    failwith"automatic submission reused a stale clear color";
  ignore(get(Scene_execution.render_sampled_resources~clear:(0.,0.,1.,1.) renderer draws));
  Gc.full_major();let allocated0=Gc.allocated_bytes()and gc0=Gc.quick_stat()in
  for _=1 to 1_000 do
    ignore(get(Scene_execution.render_sampled_resources~clear:(0.,0.,1.,1.) renderer draws))
  done;
  let gc1=Gc.quick_stat()in
  let allocated=(Gc.allocated_bytes()-.allocated0)/.1_000.
  and promoted=(gc1.promoted_words-.gc0.promoted_words)*.float(Sys.word_size/8)in
  if allocated>20_000. then
    failwith(Printf.sprintf"automatic stable submission allocated %.0f bytes/frame"allocated);
  if promoted>100_000. then
    failwith(Printf.sprintf"automatic stable submission promoted %.0f bytes"promoted);
  get(Scene_execution.destroy renderer)
let automatic_layout_invalidation () =
  let driver,control=Ogpu.Backend_mock.create()in
  let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;
    physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;
    max_acquired=2}in
  let renderer=get(Scene_execution.create driver configuration)in
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);
    cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;
    depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;
    transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;
    stencil_clear=0}in
  let indices count modulus=Bytes.init(count*4)(fun _->'\000')|>fun bytes->
    for index=0 to count-1 do
      Bytes.set_int32_le bytes(index*4)(Int32.of_int(index mod modulus))
    done;bytes in
  let draw vertices vertex_count index_count={Scene_execution.mesh={key="layout";
    vertices=Bytes.make vertices '\000';vertex_count;
    indices=indices index_count vertex_count;index_count};state}in
  let render draw=get(Scene_execution.render_sampled_resources renderer[
    Scene_execution.Scene2,Ogpu.Pipeline.Replace,None,None,1,draw])|>ignore in
  render(draw 48 3 3);Ogpu.Backend_mock.clear_trace control;
  render(draw 48 3 3);
  let stable=Ogpu.Backend_mock.trace control|>List.find(String.starts_with~prefix:"render:")in
  Ogpu.Backend_mock.clear_trace control;
  (* The packed byte total remains 60, forcing same-buffer replacement while
     changing the command's captured index count. *)
  render(draw 32 2 7);
  let changed=Ogpu.Backend_mock.trace control|>List.find(String.starts_with~prefix:"render:")in
  if stable=changed then failwith"automatic submission reused stale draw cardinality";
  let large={Scene_execution.mesh={key="large-stable";
    vertices=Bytes.make(65_535*16)'\000';vertex_count=65_535;
    indices=indices 3 65_535;index_count=3};state}in
  render large;render large;Gc.full_major();
  let allocated0=Gc.allocated_bytes()in
  for _=1 to 20 do render large done;
  let allocated=(Gc.allocated_bytes()-.allocated0)/.20. in
  if allocated>100_000. then
    failwith(Printf.sprintf"stable payload hashing copied %.0f bytes/frame"allocated);
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then
    failwith"automatic layout invalidation leaked objects"
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
  let primary=texture"canvas:test-primary""\255\255\255\255"in
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
  let changed=texture"canvas:test-primary""\000\255\000\255"in
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some changed,Some first,draw]));
  if Scene_execution.upload_bytes renderer<>Int64.add uploaded 256L then failwith"changed texture upload cardinality";
  let trace=Ogpu.Backend_mock.trace control in
  if List.exists(String.starts_with~prefix:"create-texture:")trace then failwith"same-shape texture replacement allocated texture";
  if List.exists(String.starts_with~prefix:"create-buffer:")trace then failwith"same-shape texture replacement allocated staging";
  let changed_uploaded=Scene_execution.upload_bytes renderer in
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some changed,Some first,draw]));
  if Scene_execution.upload_bytes renderer<>changed_uploaded then failwith"stable changed texture reuploaded";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw;Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw]));
  let renders=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"render:")in
  if List.length renders<>1 then failwith"equal auxiliary resources did not batch";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_resources renderer[Scene2,Ogpu.Pipeline.Replace,Some primary,Some first,draw;Scene2,Ogpu.Pipeline.Replace,Some primary,Some second,draw]));
  let renders=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"render:")in
  if List.length renders<>1 then failwith"distinct per-draw auxiliary resources split a compatible pass"
let mixed_scene2_batching () =
  let driver,control=Ogpu.Backend_mock.create()in
  let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create_variants driver configuration)in
  let indices=Bytes.make 12 '\000'in Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
  let mesh key:Scene_execution.mesh={key;vertices=Bytes.make 48 '\000';vertex_count=3;indices;index_count=3}in
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"mixed-pass";min_filter=Nearest;mag_filter=Nearest;mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
  let texture key byte:Scene_execution.sampled_texture={key;levels=[|{width=1;height=1;bytes=Bytes.make 4 byte}|];sampler}in
  let first=texture"mixed-red"'\255'and second=texture"mixed-green"'\128'in
  let draw key={Scene_execution.mesh=mesh key;state}in
  let mixed=[
    Scene_execution.Scene2,Ogpu.Pipeline.Replace,None,None,draw"plain";
    Scene_execution.Scene2_textured,Ogpu.Pipeline.Alpha,Some first,None,draw"first";
    Scene_execution.Scene2_textured,Ogpu.Pipeline.Add,Some second,None,draw"second"]in
  ignore(get(Scene_execution.render_resources renderer mixed));
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_resources renderer mixed));
  let trace=Ogpu.Backend_mock.trace control in
  let renders=List.filter(String.starts_with~prefix:"render:")trace in
  if List.length renders<>2||List.length(List.filter(String.starts_with~prefix:"submit:")trace)<>2
     ||not(List.exists(fun render->String.contains render ';')renders)then
    failwith("classic/retained Scene2 boundary did not preserve retained batching: "^String.concat","trace);
  Ogpu.Backend_mock.clear_trace control;
  let clipped={state with scissor=(1,1,7,7)}in
  ignore(get(Scene_execution.render_resources renderer[
    Scene2,Ogpu.Pipeline.Replace,None,None,draw"clip-a";
    Scene2_textured,Ogpu.Pipeline.Alpha,Some first,None,{Scene_execution.mesh=mesh"clip-b";state=clipped}]));
  if List.length(List.filter(String.starts_with~prefix:"render:")(Ogpu.Backend_mock.trace control))<>2 then
    failwith"incompatible clip states shared a render pass";
  Ogpu.Backend_mock.clear_trace control;
  let malformed={first with key="stale";levels=[|{Scene_execution.width=1;height=1;bytes=Bytes.empty}|]}in
  begin match Scene_execution.render_resources renderer[
    Scene2,Ogpu.Pipeline.Replace,None,None,draw"atomic-a";
    Scene2_textured,Ogpu.Pipeline.Alpha,Some malformed,None,draw"atomic-b"]with
  |Error e when e.Ogpu.Error.kind=Invalid_argument->()
  |_->failwith"malformed second draw was not rejected"end;
  if Ogpu.Backend_mock.trace control<>[]then failwith"failed mixed pass submitted partial work";
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"mixed pass leaked objects";
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create_variants~canonical_scene2_argument:true driver configuration)in
  ignore(get(Scene_execution.render_resources renderer mixed));
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_resources renderer mixed));
  let trace=Ogpu.Backend_mock.trace control in
  if List.length(List.filter(String.starts_with~prefix:"render:")trace)<>1||
     List.length(List.filter(String.starts_with~prefix:"submit:")trace)<>1 then
    failwith("canonical Scene2 policy split a compatible plain/textured batch: "^String.concat","trace);
  get(Scene_execution.destroy renderer);
  if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"canonical mixed pass leaked objects"
let oversized_frame () =
  let driver,control=Ogpu.Backend_mock.create()in
  let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in
  let renderer=get(Scene_execution.create driver configuration)in
  let vertices=Bytes.make 48 '\000'and indices=Bytes.make 12 '\000'in
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
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
  let indices=Bytes.make 12 '\000'and state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
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
  let small byte=List.init 8(fun index->{Scene_execution.mesh={key=Printf.sprintf"selective-%d"index;vertices=Bytes.make 48(if index=3 then byte else '\000');vertex_count=3;indices;index_count=3};state})in
  ignore(get(Scene_execution.render renderer(small '\000')));
  let selective=Scene_execution.upload_bytes renderer in
  ignore(get(Scene_execution.render renderer(small '\001')));
  if Scene_execution.upload_bytes renderer<>Int64.add selective 60L then failwith"small stable run reuploaded unchanged neighbours";
  let selective_changed=Scene_execution.upload_bytes renderer in
  ignore(get(Scene_execution.render renderer(small '\001')));
  if Scene_execution.upload_bytes renderer<>selective_changed then failwith"stable small run reuploaded";
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
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
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
  let state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
  let draw={Scene_execution.mesh;state}in
  let driver,control=Ogpu.Backend_mock.create()in
  let renderer=get(Scene_execution.create_variants driver configuration)in
  let creations=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"create-depth-texture:")in
  let stencil_creations=Ogpu.Backend_mock.trace control|>List.filter(String.starts_with~prefix:"create-stencil-texture:")in
  let max_samples=Ogpu.Capabilities.minimum_m1.Ogpu.Capabilities.limits.max_sample_count in
  let expected=List.filter(fun samples->samples<=max_samples)[1;4;9;16]|>List.length in
  if List.length creations<>expected then failwith"depth target count did not match provisioned sample variants";
  if List.length stencil_creations<>expected then failwith"stencil target count did not match provisioned sample variants";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_family renderer[Scene2,Ogpu.Pipeline.Replace,draw]));
  if not(List.exists(String.starts_with~prefix:"render:nodepth:none:always:false:")(Ogpu.Backend_mock.trace control))then failwith"Scene2 acquired depth or raster state";
  Ogpu.Backend_mock.clear_trace control;
  ignore(get(Scene_execution.render_family renderer[Scene3,Ogpu.Pipeline.Replace,draw]));
  if not(List.exists(String.starts_with~prefix:"render:depth:")(Ogpu.Backend_mock.trace control))then failwith"Scene3 omitted its depth attachment";
  Ogpu.Backend_mock.clear_trace control;
  let raster={state with cull=Ogpu.Render_pass.Cull_front;depth_compare=Greater_equal;depth_write=true;depth_load=Clear;depth_clear=0.25}in
  ignore(get(Scene_execution.render_family renderer[Scene3,Ogpu.Pipeline.Replace,{draw with state=raster}]));
  let traces=Ogpu.Backend_mock.trace control in
  if not(List.exists(fun value->match String.split_on_char ':' value with "render"::"depth"::_::"clear"::"0.25"::"front"::"ge"::"true"::_->true|_->false)traces)then failwith"Scene3 raster state was not forwarded";
  let malformed=Bytes.make 208 '\000'in Bytes.set_int32_le malformed 0(Int32.bits_of_float nan);
  let before_upload=Scene_execution.upload_bytes renderer and before_live=Ogpu.Backend_mock.live_counts control in
  begin match Scene_execution.render_family renderer[Scene3,Ogpu.Pipeline.Replace,{draw with state={raster with transform_uniforms=Some malformed}}]with Error e when e.Ogpu.Error.kind=Invalid_argument->()|_->failwith"malformed transform uniforms were not rejected"end;
  if Scene_execution.upload_bytes renderer<>before_upload||Ogpu.Backend_mock.live_counts control<>before_live then failwith"malformed transform rejection was not atomic";
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
let ()=let driver,control=Ogpu.Backend_mock.create()in let configuration:Ogpu.Surface.configuration={logical_width=8;logical_height=8;physical_width=8;physical_height=8;format=Rgba8_unorm;present_mode=Fifo;max_acquired=2}in let renderer=get(Scene_execution.create driver configuration)in let mesh:Scene_execution.mesh={key="triangle";vertices=Bytes.make 48 '\000';vertex_count=3;indices=Bytes.make 12 '\000';index_count=3}and state:Scene_execution.state={viewport=(0,0,8,8);scissor=(0,0,8,8);cull=Ogpu.Render_pass.Cull_none;depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;transform_uniforms=None;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in for _=1 to 1000 do ignore(get(Scene_execution.render renderer[{mesh;state}]))done;
  prepared_clear_cache_key();
  automatic_layout_invalidation();
  shadow_payload();
  List.iter(fun blend->List.iter(fun _frame->ignore(get(Scene_execution.render_blended renderer[blend,{mesh;state}])))[1;2;60;600])
    [Ogpu.Pipeline.Replace;Alpha;Add;Multiply;Screen;Subtract];
  let pipelines=Ogpu.Backend_mock.trace control|>List.filter(fun value->String.starts_with~prefix:"pipeline:"value)in
  if List.length pipelines<>6||List.length(List.sort_uniq String.compare pipelines)<>6 then failwith"blend pipeline variants/cache";
  if Scene_execution.upload_bytes renderer<>60L then failwith"stable mesh reuploaded";
  auxiliary_lifecycle renderer control mesh state;
  mixed_scene2_batching();
  oversized_frame();
  replacement_reuse();
  domain_coalescing();
  depth_target_lifecycle();
  get(Scene_execution.destroy renderer);if Ogpu.Backend_mock.live_counts control<>(0,0,0,0,0)then failwith"scene execution leaked";print_endline"scene execution: neutral cache/upload/pass, auxiliary resources, blend variants, 1000 frames, zero delta"
