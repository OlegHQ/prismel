open Prismel_next_execution
let get=function Ok x->x|Error e->failwith(Format.asprintf "%a"pp_error e)
let get_resource=function Ok x->x|Error e->failwith(Format.asprintf"%a"Prismel_next_resources.pp_error e)
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
  let batched_ir=Result.get_ok(Raster2.Render_ir.create[|geometry;geometry|])in
  let batched=get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)batched_ir)in
  check(List.length batched=2)
    "small Scene2 run lost independent stable mesh identities";
  let owned_vertices=[|3.;3.;27.;3.;3.;27.|]and owned_indices=[|0;1;2|]in
  let owned_ir=Result.get_ok(Raster2.Render_ir.Private.create_owned[|Geometry{vertices=owned_vertices;indices=owned_indices;color=0x4080BFFFl}|])in
  let cached0,candidates0=scene2_geometry_cache_entries resource_runtime in
  ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)owned_ir));
  check(scene2_geometry_cache_entries resource_runtime=(cached0,candidates0+1))"first-seen geometry was retained strongly";
  ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)owned_ir));
  check(scene2_geometry_cache_entries resource_runtime=(cached0+1,candidates0))"stable geometry was not admitted on second sight";
  let equivalent_ir()=Result.get_ok(Raster2.Render_ir.Private.create_owned[|
    Geometry{vertices=Array.copy owned_vertices;indices=Array.copy owned_indices;
      color=0x4080BFFFl}|])in
  let upload0=(get(stats resource_runtime)).uploaded_bytes in
  for _=1 to 100 do
    let equivalent=get(lower_scene2 resource_runtime~density:1
      ~resource:(fun _->None)(equivalent_ir()))in
    ignore(get(step resource_runtime equivalent))
  done;
  let upload1=(get(stats resource_runtime)).uploaded_bytes in
  check(upload1=Int64.add upload0 84L)
    "content-identical fresh Scene2 geometry was repeatedly uploaded";
  let transform tx={Raster2.Render_ir.xx=1.;xy=0.;yx=0.;yy=1.;tx;ty=0.}in
  let transformed_ir tx=Result.get_ok(Raster2.Render_ir.Private.create_owned[|
    Push_transform(transform tx);Geometry{vertices=Array.copy owned_vertices;
      indices=Array.copy owned_indices;color=0x4080BFFFl};Pop_transform;
    Push_transform(transform(tx+.7.));Geometry{vertices=Array.copy owned_vertices;
      indices=Array.copy owned_indices;color=0x4080BFFFl};Pop_transform|])in
  ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)(transformed_ir 4.)));
  let transformed=get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)(transformed_ir 4.))in
  check(List.length transformed=2)"two transformed draws were not preserved";
  ignore(get(step resource_runtime transformed));let affine_upload=(get(stats resource_runtime)).uploaded_bytes in
  ignore(get(step resource_runtime transformed));
  check((get(stats resource_runtime)).uploaded_bytes=affine_upload)
    "stable affine draws re-uploaded geometry or uniforms";
  let changed=Result.get_ok(Raster2.Render_ir.Private.create_owned[|
    Geometry{vertices=[|3.;3.;26.;3.;3.;27.|];indices=Array.copy owned_indices;
      color=0x4080BFFFl}|])in
  let changed_draws=get(lower_scene2 resource_runtime~density:1
    ~resource:(fun _->None)changed)in
  ignore(get(step resource_runtime changed_draws));
  check((get(stats resource_runtime)).uploaded_bytes>upload1)
    "changed Scene2 geometry incorrectly reused a content-cache entry";
  Gc.full_major();let geometry_allocated0=Gc.allocated_bytes()and geometry_gc0=Gc.quick_stat()in
  for _=1 to 1_000 do ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)owned_ir))done;
  let geometry_gc1=Gc.quick_stat()in
  let geometry_allocated=(Gc.allocated_bytes()-.geometry_allocated0)/.1_000.
  and geometry_promoted=(geometry_gc1.promoted_words-.geometry_gc0.promoted_words)*.float(Sys.word_size/8)in
  check(geometry_allocated<10_000.)"stable owned geometry allocation regression";
  check(geometry_promoted<100_000.)"stable owned geometry promotion regression";
  (* One-hit transformed geometry must not retain full source arrays.  This is
     the common animated-Scene2 shape and used to promote every large source
     snapshot while filling the admission cache. *)
  let transient_vertices=Array.init 65_536(fun index->float(index land 255))
  and transient_indices=Array.init 32_766(fun index->index land 32_767)in
  Gc.full_major();let transient_gc0=Gc.quick_stat()in
  for frame=1 to 300 do
    let transient_ir=Result.get_ok(Raster2.Render_ir.Private.create_owned[|
      Push_transform{xx=1.;xy=0.;yx=0.;yy=1.;tx=float frame;ty=0.};
      Geometry{vertices=transient_vertices;indices=transient_indices;
        color=0x102030ffl};Pop_transform|])in
    ignore(get(lower_scene2 resource_runtime~density:1
      ~resource:(fun _->None)transient_ir))
  done;
  Gc.full_major();let transient_gc1=Gc.quick_stat()in
  let transient_promoted=(transient_gc1.promoted_words-.transient_gc0.promoted_words)
    *.float(Sys.word_size/8)in
  check(transient_promoted<2_000_000.)
    "one-hit transformed geometry retained source snapshots";
  (* Cache validation owns its comparison snapshots.  A caller changing an
     array after a prior lowering must produce new prepared bytes, never make
     the retained snapshot compare equal to itself. *)
  let mutable_vertices=[|4.;4.;20.;4.;4.;20.|] in
  let mutable_ir=Result.get_ok(Raster2.Render_ir.Private.create_owned[|
    Geometry{vertices=mutable_vertices;indices=Array.copy owned_indices;
      color=0x102030ffl}|])in
  let before_mutation=get(lower_scene2 resource_runtime~density:1
    ~resource:(fun _->None)mutable_ir)in
  ignore(get(step resource_runtime before_mutation));
  let before_mutation_pixels=get(capture resource_runtime)in
  mutable_vertices.(0)<-9.;
  let after_mutation=get(lower_scene2 resource_runtime~density:1
    ~resource:(fun _->None)mutable_ir)in
  ignore(get(step resource_runtime after_mutation));
  let after_mutation_pixels=get(capture resource_runtime)in
  check(before_mutation_pixels<>after_mutation_pixels)
    "mutated fresh Scene2 array reused stale prepared bytes";
  let batch_commands=Array.init 65(fun index->
    let x=float(index mod 8)in Raster2.Render_ir.Geometry{vertices=[|x;0.;x+.1.;0.;x;1.|];
      indices=[|0;1;2|];color=0x506070ffl})in
  let batch_ir=Result.get_ok(Raster2.Render_ir.Private.create_owned batch_commands)in
  ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)batch_ir));
  ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)batch_ir));
  ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)batch_ir));
  Gc.full_major();let batch_allocated0=Gc.allocated_bytes()in
  for _=1 to 100 do
    ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)batch_ir))
  done;
  let batch_allocated=(Gc.allocated_bytes()-.batch_allocated0)/.100. in
  check(batch_allocated<100_000.)
    "stable large Scene2 batch rebuilt merged buffers";
  for index=1 to 300 do
    let transient=Result.get_ok(Raster2.Render_ir.Private.create_owned[|Geometry{vertices=[|float index;0.;1.;0.;0.;1.|];indices=[|0;1;2|];color=Int32.of_int index}|])in
    ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)transient))
  done;
  let cached,candidates=scene2_geometry_cache_entries resource_runtime in
  check(cached<=256&&candidates<=64)"owned geometry caches exceeded capacity";
  ignore(get(step resource_runtime batched));
  check(Bytes.exists((<>)'\000')(get(capture resource_runtime)))
    "batched Scene2 topology produced no pixels";
  ignore(get(step resource_runtime[textured_draw]));
  ignore(get(step resource_runtime[shadow_draw]));
  let shadow_pixels=get(capture resource_runtime)in
  let green=ref 0 in for pixel=0 to Bytes.length shadow_pixels/4-1 do
    if Char.code(Bytes.get shadow_pixels(pixel*4+1))=128 then incr green done;
  check(!green>0)"headless shadow texture4/sampler5 pixels";
  let image=get_resource(Prismel_next_resources.Image.create~width:2~height:2~rgba:(Bytes.init 16(fun i->match i mod 4 with 0|3->'\255'|_->'\000')))in
  let image_ir=Result.get_ok(Raster2.Render_ir.create[|Image{resource_id=1;
    source={x=0.;y=0.;width=2.;height=2.};destination={x=0.;y=0.;width=4.;height=4.}}|])in
  let image_draws=get(lower_scene2 resource_runtime~density:1~resource:(function 1->Some(Image image)|_->None)image_ir)in
  ignore(get(step resource_runtime image_draws));let image_pixels=get(capture resource_runtime)in
  check(Char.code(Bytes.get image_pixels 0)=255)"image snapshot pixel";
  let leased_image=get_resource(Prismel_next_resources.Image.create~width:2~height:2
    ~rgba:(Bytes.init 16(fun i->match i mod 4 with 0|3->'\255'|_->'\000')))in
  let leased_draws=get(lower_scene2 resource_runtime~density:1
    ~resource:(function 1->Some(Image leased_image)|_->None)image_ir)in
  ignore(Prismel_next_resources.Image.replace leased_image~width:2~height:2
    ~rgba:(Bytes.init 16(fun i->match i mod 4 with 2|3->'\255'|_->'\000')));
  ignore(get(step resource_runtime leased_draws));
  let staged_pixels=get(capture resource_runtime)in
  check(Char.code(Bytes.get staged_pixels 0)=255&&Char.code(Bytes.get staged_pixels 2)=0)
    "image mutation after lowering changed leased pixels";
  ignore(get(step resource_runtime(get(lower_scene2 resource_runtime~density:1
    ~resource:(function 1->Some(Image leased_image)|_->None)image_ir))));
  let mutated_pixels=get(capture resource_runtime)in
  check(Char.code(Bytes.get mutated_pixels 0)=0&&Char.code(Bytes.get mutated_pixels 2)=255)
    "image generation invalidation missed replacement";
  Gc.full_major();
  let leased_allocated_before=Gc.allocated_bytes()in
  for frame=1 to 600 do
    let red=frame land 255 in
    ignore(Prismel_next_resources.Image.replace leased_image~width:2~height:2
      ~rgba:(Bytes.init 16(fun i->match i mod 4 with 0->Char.chr red|3->'\255'|_->'\000')));
    let frame_draws=get(lower_scene2 resource_runtime~density:1
      ~resource:(function 1->Some(Image leased_image)|_->None)image_ir)in
    ignore(get(step resource_runtime frame_draws))
  done;
  let leased_allocated=(Gc.allocated_bytes()-.leased_allocated_before)/.600. in
  check(leased_allocated<250_000.)"600-frame leased image allocation bound";
  check(snapshot_cache_entries resource_runtime<=256)
    "600-frame leased image grew retained snapshot cache";
  check(Result.is_error(Prismel_next_resources.Image.replace image~width:0~height:2~rgba:Bytes.empty))"malformed replacement accepted";
  ignore(get(step resource_runtime(get(lower_scene2 resource_runtime~density:1~resource:(function 1->Some(Image image)|_->None)image_ir))));
  check(Char.code(Bytes.get(get(capture resource_runtime))0)=255)"failed reload retention";
  let canvas=get_resource(Prismel_next_resources.Canvas.create~width:2~height:2)in
  ignore(Prismel_next_resources.Canvas.clear canvas 0x00ff00ffl);
  let canvas_draws=get(lower_scene2 resource_runtime~density:2~resource:(function 1->Some(Canvas canvas)|_->None)image_ir)in
  ignore(get(step resource_runtime canvas_draws));let canvas_pixels=get(capture resource_runtime)in
  check(Char.code(Bytes.get canvas_pixels 1)=255)"canvas dependency pixel";
  let canvas_before=get(stats resource_runtime)and cache_before=snapshot_cache_entries resource_runtime in
  ignore(Prismel_next_resources.Canvas.clear canvas 0xff0000ffl);
  let changed_canvas_draws=get(lower_scene2 resource_runtime~density:2~resource:(function 1->Some(Canvas canvas)|_->None)image_ir)in
  ignore(get(step resource_runtime changed_canvas_draws));
  let changed_canvas_pixels=get(capture resource_runtime)and canvas_after=get(stats resource_runtime)in
  check(Char.code(Bytes.get changed_canvas_pixels 0)=255&&Char.code(Bytes.get changed_canvas_pixels 1)=0)"changed canvas exact pixel";
  check(canvas_after.uploaded_bytes=Int64.add canvas_before.uploaded_bytes 512L)"changed canvas truthful upload";
  check(snapshot_cache_entries resource_runtime=cache_before)"changed canvas grew snapshot cache";
  let stable_canvas_upload=canvas_after.uploaded_bytes in
  ignore(get(step resource_runtime changed_canvas_draws));
  check((get(stats resource_runtime)).uploaded_bytes=stable_canvas_upload)"stable canvas mesh/texture reuploaded";
  Gc.full_major();
  let allocated_before=Gc.allocated_bytes()in
  for _=1 to 100 do ignore(get(step resource_runtime changed_canvas_draws))done;
  let allocated_per_step=(Gc.allocated_bytes()-.allocated_before)/.100. in
  check(allocated_per_step<100_000.)"stable canvas outer-step allocation bound";
  let empty=Result.get_ok(Raster2.Render_ir.create[|Glyphs{resource_id=999;color=Int32.minus_one;glyphs=[||]}|])in
  check(get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)empty)=[])"empty glyph no-op";
  let font=get_resource(Prismel_next_resources.Font.open_system~size:12.)in
  let text=match get_resource(Prismel_next_resources.Font.render font~density:1~color:(255,255,255,255)"A")with Some value->value|None->failwith"non-empty text returned no snapshot"in
  let glyph_ir=Result.get_ok(Raster2.Render_ir.create[|Glyphs{resource_id=2;color=Int32.minus_one;glyphs=[|{glyph_id=65;x=0.;y=0.}|]}|])in
  let glyph_draws=get(lower_scene2 resource_runtime~density:1~resource:(function 2->Some(Text text)|_->None)glyph_ir)in
  ignore(get(step resource_runtime glyph_draws));
  check(Bytes.exists((<>)'\000')(get(capture resource_runtime)))"text snapshot pixels";
  ignore(Prismel_next_resources.Text.destroy text);ignore(Prismel_next_resources.Font.destroy font);
  for index=1 to 300 do let temporary=Result.get_ok(Prismel_next_resources.Image.create~width:1~height:1~rgba:(Bytes.make 4(Char.chr(index land 255))))in
    ignore(get(lower_scene2 resource_runtime~density:1~resource:(fun _->Some(Image temporary))image_ir));ignore(Prismel_next_resources.Image.destroy temporary)done;
  check(snapshot_cache_entries resource_runtime<=256)"snapshot LRU bound";
  let outside=Result.get_ok(Raster2.Render_ir.create[|
    Push_clip{x=100.;y=100.;width=20.;height=20.};geometry;Pop_clip|])in
  let outside_draws=get(lower_scene2 resource_runtime~density:1~resource:(fun _->None)outside)in
  check(outside_draws=[])"fully clipped Scene2 draw must be elided";
  ignore(get(step resource_runtime outside_draws));
  ignore(get(step resource_runtime draws));
  let before=get(stats resource_runtime)in
  ignore(get(step resource_runtime draws));
  let after=get(stats resource_runtime)in
  check(after.frames=Int64.succ before.frames&&after.logical_draws=Int64.add before.logical_draws(Int64.of_int(List.length draws)))"execution stats accounting";
  check(after.uploaded_bytes=before.uploaded_bytes)"stable draws must not re-upload";
  ignore(Prismel_next_resources.Image.destroy leased_image);
  ignore(Prismel_next_resources.Image.destroy image);ignore(Prismel_next_resources.Canvas.destroy canvas);
  get(destroy resource_runtime);
  let teardown=diagnostics resource_runtime in
  check(not teardown.active&&teardown.resource_count=0&&teardown.cache_entries=0)
    "authoritative execution teardown diagnostics";
  check(Result.is_error(stats resource_runtime))"destroyed stats stale";
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
