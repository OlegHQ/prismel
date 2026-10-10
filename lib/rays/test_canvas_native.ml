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

let run () =
  let baseline=live_handles()in
  let canvas=Canvas.create_exn~width:64~height:64 in
  let rendered=ref 0 in
  let render scene=Canvas.render canvas scene;incr rendered in
  try
    render Scene.[clear(Color.rgba 7 11 13 17)];
    require(channel canvas~x:0~y:0=(7,11,13,17))
      "Canvas native clear-only pixel";
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
    let first=snapshot canvas in
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
    let second=snapshot canvas in
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
    require(stats.logical_draws>=599L)"Canvas native draw accounting";
    require(stats.uploaded_bytes>0L)"Canvas native upload accounting";
    let image=Result.get_ok(Canvas.to_image canvas)in
    Fun.protect~finally:(fun()->Image.destroy image)(fun()->
      require(Image.get_size image=(64,64))"Canvas native to_image extent";
      let pixels=Result.get_ok(Image.Private.pixels image)in
      require(Bytes.sub pixels 0 4=Bytes.of_string"\009\017\031\255")
        "Canvas native to_image exact pixel");
    Canvas.destroy canvas;
    Canvas.destroy canvas;
    require(live_handles()=baseline)"Canvas native Metal live-handle delta";
    Printf.printf
      "Canvas native: exact released-scene reuse, %.1f promoted B/frame, frames1/2/60/600, bounded cache, zero delta\n"
      promoted_per_frame
  with exn->Canvas.destroy canvas;raise exn
