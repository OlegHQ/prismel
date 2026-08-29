open Prismel

let require condition message=if not condition then failwith message
let channel canvas ~x ~y=
  match Canvas.pixel canvas~x~y with
  |Some color->Color.to_tuple color
  |None->failwith"Canvas native pixel is out of bounds"
let drain()=match Metal.Release_queue.drain()with
  |Ok _->()|Error error->failwith(Format.asprintf"%a"Metal.pp_error error)
let live_handles()=match Metal.Release_queue.stats()with
  |Ok stats->stats.live_handles
  |Error error->failwith(Format.asprintf"%a"Metal.pp_error error)
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

let ()=
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
    Image.destroy borrowed;Font.destroy font;
    require(!rendered=602)"Canvas native frame count";
    let stats=Canvas.Private.native_stats canvas in
    require(stats.frames=602L&&stats.logical_submissions=602L&&
      stats.logical_passes=602L)"Canvas native submission accounting";
    require(stats.logical_draws>=599L)"Canvas native draw accounting";
    require(stats.uploaded_bytes>0L)"Canvas native upload accounting";
    require(stats.cache_entries<=32)"Canvas native bounded execution cache";
    let image=Result.get_ok(Canvas.to_image canvas)in
    Fun.protect~finally:(fun()->Image.destroy image)(fun()->
      require(Image.get_size image=(64,64))"Canvas native to_image extent";
      let pixels=Result.get_ok(Image.Private.pixels image)in
      require(Bytes.sub pixels 0 4=Bytes.of_string"\009\017\031\255")
        "Canvas native to_image exact pixel");
    Canvas.destroy canvas;
    let after=Canvas.Private.native_stats canvas in
    require(after.cache_entries=0&&after.frames=0L&&
      after.logical_submissions=0L)"Canvas native cache teardown delta";
    Canvas.destroy canvas;drain();
    require(live_handles()=baseline)"Canvas native Metal live-handle delta";
    Printf.printf
      "Canvas native: exact released-scene reuse, %.1f promoted B/frame, frames1/2/60/600, bounded cache, zero delta\n"
      promoted_per_frame
  with exn->Canvas.destroy canvas;drain();raise exn
