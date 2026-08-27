open Prismel_next_execution
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a"pp_error e)
let check condition message=if not condition then failwith message
let geometry = Raster2.Render_ir.Geometry { vertices=[|2.;2.; 30.;2.; 2.;30.|]; indices=[|0;1;2|]; color=0x4080BFFFl }
let ir=Result.get_ok(Raster2.Render_ir.create[|Raster2.Render_ir.Clear 0x000000FFl;geometry|])
let configuration={default_configuration with logical_width=32;logical_height=32;drawable_width=32;drawable_height=32}
let () =
  let draws=get(scene2_ir ir)in
  let base=List.hd draws in
  let raw=match base with _->
    let vertices=Bytes.make(68*3)'\000'and indices=Bytes.make 12 '\000'in
    Bytes.set_int32_le indices 4 1l;Bytes.set_int32_le indices 8 2l;
    let points=[0.,0.;4.,0.;0.,4.]in
    List.iteri(fun i(x,y)->Bytes.set_int64_le vertices(i*16)(Int64.bits_of_float x);
      Bytes.set_int64_le vertices(i*16+8)(Int64.bits_of_float y))points;
    List.iteri(fun i(x,y)->let offset=i*68 in Bytes.set_int64_le vertices offset(Int64.bits_of_float x);
      Bytes.set_int64_le vertices(offset+8)(Int64.bits_of_float y);
      Bytes.set_int64_le vertices(offset+40)(Int64.bits_of_float 1.);
      Bytes.set_int32_le vertices(offset+48)0xffffffffl)points;
    let uniforms=Bytes.make 208 '\000'in
    for matrix=0 to 2 do for diagonal=0 to 3 do
      Bytes.set_int32_le uniforms((matrix*16+diagonal*5)*4)(Int32.bits_of_float 1.)
    done done;
    let mesh={Scene_execution.key="combined";vertices;vertex_count=3;indices;index_count=3}in
    let state={Scene_execution.viewport=(0,0,-1,-1);scissor=(0,0,-1,-1);cull=Ogpu.Render_pass.Cull_none;
      depth_compare=Ogpu.Render_pass.Always;depth_write=false;depth_load=Ogpu.Render_pass.Load;depth_clear=1.;
      transform_uniforms=Some uniforms;stencil_state=None;stencil_load=Ogpu.Render_pass.Load;stencil_clear=0}in
    {Scene_execution.mesh;state}in
  let sampler:Ogpu.Types.sampler_descriptor={label=Some"combined";min_filter=Nearest;mag_filter=Nearest;
    mip_filter=No_mip;address_u=Clamp_to_edge;address_v=Clamp_to_edge;lod_min=0.;lod_max=0.;max_anisotropy=1}in
  let texture:Scene_execution.sampled_texture={key="combined-texture";
    levels=[|{width=1;height=1;bytes=Bytes.of_string"\064\128\191\255"}|];sampler}in
  let auxiliary:Scene_execution.auxiliary_resource={key="combined-shadow";buffer=Bytes.make 84 '\000';texture}in
  let textured_draw=prepared_draw~family:Scene3_textured~texture raw
  and shadow_draw=prepared_draw~family:Scene3_shadow~auxiliary raw in
  let combined=draws@[prepared_draw~family:Scene3 raw;textured_draw;shadow_draw;
    prepared_draw~family:Scene3_stencil raw;
    prepared_draw~family:Scene3_textured_stencil~texture raw;
    prepared_draw~family:Scene3_shadow_stencil~auxiliary raw]in
  let coordinator=get(create configuration)in
  get(push_event coordinator(Pointer_moved(3.,4.)));
  let first=get(step coordinator draws)in
  check(first.frame=1L&&first.time=1./.60.)"fixed frame facts";
  check(first.events=[Pointer_moved(3.,4.)])"ordered one-frame input";
  let pixels=get(capture coordinator)in
  check(Bytes.length pixels=32*32*4)"capture extent";
  get(resize coordinator~logical_width:16~logical_height:12~drawable_width:32~drawable_height:24);
  let second=get(step coordinator(scene2_ir ir|>get))in
  check(second.frame=2L&&second.logical_width=16&&second.drawable_width=32)"resize facts";
  check(second.events=[Resized(16,12)])"resize event";
  for frame=3 to 600 do ignore(get(step coordinator(if List.mem frame[60;600]then combined else draws)))done;
  get(destroy coordinator);get(destroy coordinator);
  check(match step coordinator draws with Error e->e.kind=Destroyed|Ok _->false)"stale rejection";
  let resource_runtime=get(create configuration)in
  ignore(get(step resource_runtime[textured_draw]));
  ignore(get(step resource_runtime[shadow_draw]));
  let shadow_pixels=get(capture resource_runtime)in
  let green=ref 0 in for pixel=0 to Bytes.length shadow_pixels/4-1 do
    if Char.code(Bytes.get shadow_pixels(pixel*4+1))=128 then incr green done;
  check(!green>0)"headless shadow texture4/sampler5 pixels";
  get(destroy resource_runtime);
  let bounded=get(create{configuration with max_events=64})in
  for index=1 to 100_000 do get(push_event bounded(Pointer_moved(float index,0.)))done;
  let bounded_facts=get(step bounded draws)in
  check(List.length bounded_facts.events<=64&&bounded_facts.dropped_events>0)"100k bounded input";
  get(destroy bounded);
  let stopped=ref false in
  check(match run configuration(fun _->raise Exit)~on_stop:(fun _->stopped:=true;Ok())with Error _->true|Ok _->false)"exception mapped";
  check !stopped"exception cleanup on_stop"
  ;
  let exercise_target target frames =
    match create{configuration with target}with Error _ when target=Native->()
    |Error e->failwith(Format.asprintf"target create: %a"pp_error e)
    |Ok runtime->
        for frame=1 to frames do ignore(get(step runtime(if List.mem frame[1;2;60]then combined else draws)))done;
        if target=Web then ignore(get(step runtime[shadow_draw]));
        let pixels=get(capture runtime)in
        check(Bytes.length pixels=32*32*4)"target capture";
        if target=Web then(let green=ref 0 in for pixel=0 to Bytes.length pixels/4-1 do if Char.code(Bytes.get pixels(pixel*4+1))=128 then incr green done;check(!green>0)"web sampled/shadow pixels");
        get(destroy runtime)
  in
  exercise_target Web 60;
  exercise_target Native 2
