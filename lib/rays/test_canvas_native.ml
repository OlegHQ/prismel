open Rays

let require condition message=if not condition then failwith message
let channel canvas ~x ~y=
  match Canvas.pixel canvas~x~y with
  |Some color->Color.to_tuple color
  |None->failwith"Canvas native pixel is out of bounds"
let live_handles=snd(Ogpu.Impl.create_driver())
let snapshot canvas=
  let image=Result.get_ok(Canvas.to_image canvas)in
  Fun.protect~finally:(fun()->Image.destroy image)(fun()->
    Result.get_ok(Image.Private.pixels image))
let region_has_pixel_other_than canvas ~x0 ~y0 ~x1 ~y1 expected=
  let found=ref false in
  for y=y0 to y1 do
    for x=x0 to x1 do
      if channel canvas~x~y<>expected then found:=true
    done
  done;
  !found

let camera_depth ()=
  let baseline=live_handles()in
  let canvas=Canvas.create_exn ~width:32 ~height:32 in
  Fun.protect ~finally:(fun()->Canvas.destroy canvas)(fun()->
    let mesh=Mesh.plane ~width:1. ~height:1.()in
    let cameras=[Camera.orthographic ~height:2. ~at:(Vec3.create 0. 0. 2.) ~target:Vec3.zero();
      Camera.perspective ~at:(Vec3.create 0. 0. 0.15) ~target:Vec3.zero()]in
    List.iter(fun camera->
      let far=Scene3.translate(Vec3.create 0. 0.(-0.02))
        [Scene3.mesh ~material:(Material.unlit Color.red) ~cull:Cull_none mesh]in
      let near=Scene3.mesh ~material:(Material.unlit Color.green) ~cull:Cull_none mesh in
      let scene=Scene.[clear Color.black;view3d ~camera(Scene3.create[near;far])]in
      Canvas.render canvas scene;
      require(channel canvas ~x:16 ~y:16=(0,255,0,255)) "camera native near/far clipping or depth order";
      let first=snapshot canvas in Canvas.render canvas scene;
      require(snapshot canvas=first) "camera depth retained replay pixels";
      let transforms=[|Mat4.identity;Mat4.translation(Vec3.create 0. 0.(-0.02))|]in
      let instances=Scene3.instances_array ~material:(Material.unlit Color.blue)
        ~cull:Cull_none mesh transforms in
      let scene=Scene.[clear Color.black;view3d ~camera(Scene3.create[instances])]in
      Canvas.render canvas scene;
      require(channel canvas ~x:16 ~y:16=(0,0,255,255)) "camera native instance clipping";
      let first=snapshot canvas in Canvas.render canvas scene;
      require(snapshot canvas=first) "camera instance retained replay pixels")cameras);
  require(live_handles()=baseline) "camera native live-handle delta";
  print_endline "camera native depth: default orthographic, close perspective, depth order, instances and retained replay pass"

let completed_source ()=
  let baseline=live_handles()in
  let canvas=Canvas.create_exn ~width:65 ~height:3
  and destination=Canvas.create_exn ~width:65 ~height:3 in
  let images=ref[]in
  Fun.protect ~finally:(fun()->
    List.iter Image.destroy !images;Canvas.destroy canvas;Canvas.destroy destination)(fun()->
    require(Result.is_error(Canvas.Private.gpu_source canvas))"fresh Canvas allowed a GPU borrow";
    let render color=Canvas.render canvas Scene.[clear color]in
    let borrow()=
      let width,height,source=Result.get_ok(Canvas.Private.gpu_source canvas)in
      require((width,height)=(65,3))"Canvas borrow extent";
      let resource=Result.get_ok(Runtime_resources.Image.Private.of_gpu ~width ~height ~source)in
      let image=Image.Private.of_resource resource in images:=image:: !images;
      source,image in
    let expires source image=
      require(Option.is_none(source()))"old Canvas source remains current";
      match Runtime_resources.Image.Private.gpu_snapshot(Image.Private.resource image)with
      |Error{kind=Runtime_resources.Destroyed;_}->()
      |_->failwith"expired Canvas image did not report Destroyed"in
    render Color.red;
    let source,image=borrow()in
    let generation=Runtime_resources.Image.generation(Image.Private.resource image)in
    let published=image in
    let scene=Scene.[clear Color.black;image published ~at:(0,0)()]in
    Canvas.render destination scene;
    require(channel destination ~x:64 ~y:2=(255,0,0,255))"borrowed Canvas native consumer pixel";
    require(Canvas.Private.pixel_stats canvas=(0,0))"Canvas borrowing captured or read source pixels";
    let wrong_context()=
      require(Option.is_none(source()))"Canvas callback accepted wrong execution context";
      require(Result.is_error(Canvas.Private.gpu_source canvas))"Canvas borrow accepted wrong execution context";
      let rejected=try render Color.green;false with Failure _->true in
      require rejected "Canvas render accepted wrong execution context"in
    Domain.join(Domain.spawn wrong_context);
    let thread_result=ref(Ok())in
    let thread=Thread.create(fun()->
      try
        require(Domain.is_main_domain())"thread fixture did not run on the initial domain";
        wrong_context()
      with exn->thread_result:=Error exn)()in
    Thread.join thread;(match !thread_result with Ok()->()|Error exn->raise exn);
    require(Option.is_some(source()))"rejected wrong-context operations invalidated Canvas";
    render Color.blue;expires source image;
    require(Runtime_resources.Image.generation(Image.Private.resource image)=generation)
      "source expiry mutated published Image generation";
    let replay_failed=try Canvas.render destination scene;false with Failure _->true in
    require replay_failed "retained Scene replay accepted an expired Canvas source";
    let source,image=borrow()in
    let failed=try Canvas.render canvas Scene.[rect ~at:(0,0) ~w:1 ~h:1();clear Color.red];false
      with Failure _->true in
    require failed "Canvas late Clear fixture succeeded";expires source image;
    require(Result.is_error(Canvas.Private.gpu_source canvas))"failed render left a completed Canvas source";
    require(Canvas.Private.pixel_stats canvas=(0,0))"failed Canvas render read or captured pixels";
    render Color.green;
    let source,image=borrow()in
    let failed=try Canvas.render ~density:0 canvas Scene.[clear Color.blue];false
      with Invalid_argument _->true in
    require failed "Canvas accepted zero density";expires source image;
    require(Result.is_error(Canvas.Private.gpu_source canvas))"invalid density left a completed source";
    render Color.green;
    let source,image=borrow()in
    Canvas.Private.invalidate canvas;expires source image;
    render Color.red;
    let source,image=borrow()in
    Canvas.set_pixel canvas ~x:0 ~y:0 Color.blue;expires source image;
    require(Canvas.Private.pixel_stats canvas=(0,1))"CPU mutation actual Canvas readback count";
    render Color.green;
    let captured=Result.get_ok(Canvas.to_image canvas)in images:=captured:: !images;
    let _,_,_,bytes,lease=Result.get_ok(Runtime_resources.Image.Private.borrow_snapshot
      (Image.Private.resource captured))in
    Fun.protect ~finally:(fun()->Runtime_resources.Image.Private.release_snapshot lease)(fun()->
      let saved=Bytes.copy bytes in
      require(Bytes.sub saved 0 4=Bytes.of_string "\x00\xff\x00\xff")"Canvas CPU snapshot pixel";
      require(Canvas.Private.pixel_stats canvas=(1,2))"Canvas capture actual readback count";
      render Color.blue;
      let source,image=borrow()in
      Canvas.destroy canvas;expires source image;
      require(Canvas.Private.pixel_stats canvas=(1,2))"Canvas destruction read discarded GPU pixels";
      require(bytes=saved && Result.get_ok(Image.Private.pixels captured)=saved)
        "Canvas updates or destruction changed retained CPU bytes";
      Canvas.destroy canvas));
  require(live_handles()=baseline)"Canvas borrowed-source live-handle delta";
  print_endline "Canvas completed source: native consumer, domain/thread guards, attempt/CPU/destroy expiry, retained CPU lease, no teardown readback, zero delta"

let run () =
  completed_source();
  camera_depth();
  let baseline=live_handles()in
  let canvas=Canvas.create_exn~width:64~height:64 in
  let rendered=ref 0 in
  let render scene=Canvas.render canvas scene;incr rendered in
  try
    render Scene.[clear(Color.rgba 7 11 13 17)];
    require(channel canvas~x:0~y:0=(7,11,13,17))
      "Canvas native clear-only pixel";
    render Scene.[clear Color.blue;
      rect~at:(2,2)~w:4~h:4~fill:Color.green();
      text~at:(12,2)~size:12"steady"];
    require(channel canvas~x:0~y:0=(0,0,255,255))
      "Canvas native drawn background";
    require(channel canvas~x:3~y:3=(0,255,0,255))
      "Canvas native drawn foreground";
    require(region_has_pixel_other_than canvas~x0:12~y0:2~x1:55~y1:18
      (0,0,255,255))"Canvas native automatic text was not visible";
    let _,_,references=Font.Private.automatic_counts()in
    require(references=0)"Canvas retained automatic text through capture";
    Gc.full_major();let gc_before=Gc.quick_stat()in
    for frame=3 to 600 do
      let clear_color=if frame land 1=0 then Color.red else Color.blue in
      render Scene.[clear clear_color;
        rect~at:(2,2)~w:4~h:4~fill:Color.green();
        text~at:(12,2)~size:12"steady"];
      if frame=60||frame=600 then begin
        require(channel canvas~x:0~y:0=(255,0,0,255))
          "Canvas native repeated-frame background";
        require(channel canvas~x:3~y:3=(0,255,0,255))
          "Canvas native repeated-frame foreground"
      end
    done;
    let gc_after=Gc.quick_stat()in
    let promoted_per_frame=(gc_after.promoted_words-.gc_before.promoted_words)*.
      float(Sys.word_size/8)/.598. in
    require(promoted_per_frame<4_096.)
      "Canvas native transient Scene promotion regression";
    let borrowed=Image.create~width:2~height:2~color:(Color.rgba 37 83 149 211)()in
    let stage_failed=try
      Canvas.render canvas Scene.[image borrowed~at:(3,3)();
        text~at:(12,2)~size:12"stage failure";clear Color.red];
      false
    with Failure _->true in
    require stage_failed"Canvas accepted a late native Clear";
    let _,_,references=Font.Private.automatic_counts()in
    require(references=0)"stage failure retained automatic text";
    require(Result.is_ok(Image.Private.pixels borrowed))
      "stage failure shortened explicit Image ownership";
    let font=Result.get_ok(Font.system~size:12())in
    let camera=Camera.orthographic~height:2.~at:(Vec3.create 0. 0. 2.)
      ~target:Vec3.zero()in
    let mesh=Mesh.create_exn~indices:[0;1;2]
      ~normals:[Vec3.unit_z;Vec3.unit_z;Vec3.unit_z]
      [Vec3.create(-0.8)(-0.8)0.;Vec3.create 0.8(-0.8)0.;Vec3.create 0. 0.8 0.]in
    let scene3=Scene3.create[Scene3.mesh~material:(Material.unlit Color.red)mesh]in
    let reusable=Scene.[clear(Color.rgba 9 17 31 255);
      image borrowed~at:(3,3)();text~at:(12,2)~size:12"reusable";
      font_text font~at:(12,18)"provided";
      view3d~viewport:(32,32,32,32)~camera scene3;
      rect~at:(46,46)~w:4~h:4~fill:Color.green()]in
    render reusable;let first=snapshot canvas in
    let _,_,references=Font.Private.automatic_counts()in
    require(references=0)"reusable Scene retained automatic text after lowering";
    require(Result.is_ok(Image.Private.pixels borrowed))
      "Scene release shortened explicit Image ownership";
    require(region_has_pixel_other_than canvas~x0:12~y0:2~x1:55~y1:30
      (9,17,31,255))"released mixed Scene did not render text";
    require(region_has_pixel_other_than canvas~x0:32~y0:32~x1:63~y1:63
      (9,17,31,255))"released mixed Scene did not render View3d";
    require(channel canvas~x:47~y:47=(0,255,0,255))
      "Scene2 overlay did not preserve mixed-layer order";
    render reusable;let second=snapshot canvas in
    require(first=second)"released reusable Scene changed exact native pixels";
    (* Replacing an image's pixels in place must reach the next render. *)
    let before_replacement=channel canvas~x:3~y:3 in
    (match Image.upload_rgba~into:borrowed~width:2~height:2
        ~rgba:(Bytes.of_string"\x11\x22\x33\xff\x11\x22\x33\xff\x11\x22\x33\xff\x11\x22\x33\xff")()with
     |Ok _->()|Error message->failwith message);
    (* A fresh Scene value, as a sketch's view builds each frame, sees the
       replacement; the released [reusable] value keeps its snapshot. *)
    render Scene.[clear(Color.rgba 9 17 31 255);image borrowed~at:(3,3)()];
    require(channel canvas~x:3~y:3<>before_replacement&&channel canvas~x:3~y:3=(0x11,0x22,0x33,0xff))
      "replaced image pixels did not reach the render";
    Image.destroy borrowed;Font.destroy font;
    require(!rendered=603)"Canvas native frame count";
    let stats=Canvas.Private.native_stats canvas in
    require(stats.frames=603L&&stats.logical_submissions=603L&&
      stats.logical_passes=603L)"Canvas native submission accounting";
    require(stats.logical_draws>=599L)"Canvas native draw accounting";
    require(stats.uploaded_bytes>0L)"Canvas native upload accounting";
    require(stats.mesh_cache_entries<=32)"Canvas native bounded execution cache";
    let image=Result.get_ok(Canvas.to_image canvas)in
    Fun.protect~finally:(fun()->Image.destroy image)(fun()->
      require(Image.get_size image=(64,64))"Canvas native to_image extent";
      let pixels=Result.get_ok(Image.Private.pixels image)in
      require(Bytes.sub pixels 0 4=Bytes.of_string"\009\017\031\255")
        "Canvas native to_image exact pixel");
    Canvas.destroy canvas;
    let after=Canvas.Private.native_stats canvas in
    require(after.mesh_cache_entries=0&&after.frames=0L&&
      after.logical_submissions=0L)"Canvas native cache teardown delta";
    Canvas.destroy canvas;
    require(live_handles()=baseline)"Canvas native Metal live-handle delta";
    Printf.printf
      "Canvas native: exact released-scene reuse, %.1f promoted B/frame, frames1/2/60/600, bounded cache, zero delta\n"
      promoted_per_frame
  with exn->Canvas.destroy canvas;raise exn
