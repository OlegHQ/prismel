let require value message=if not value then failwith message
let ()=let open Prismel in
  let image=Image.create ~width:2 ~height:2 ~color:(Color.rgba 1 2 3 4)()in
  require(Image.get_size image=(2,2)&&Bytes.length(Result.get_ok(Image.Private.pixels image))=16)"Image snapshot";
  let canvas=Canvas.create_exn ~width:3 ~height:2 in
  Canvas.map_pixels canvas(fun ~x:_ ~y:_ _->Color.black);
  Canvas.set_pixel canvas ~x:1 ~y:1(Color.rgba 9 8 7 6);
  require(Canvas.pixel canvas ~x:1 ~y:1=Some(Color.rgba 9 8 7 6))"Canvas pixel";
  let captured=Result.get_ok(Canvas.to_image canvas)in require(Image.get_size captured=(3,2))"Canvas capture";
  let captured_identity=Image.Private.identity captured in
  Canvas.set_pixel canvas~x:0~y:0(Color.rgba 9 8 7 255);
  Result.get_ok(Canvas.Private.copy_to_image canvas captured);
  require(Image.Private.identity captured=captured_identity)"Canvas copy preserves image identity";
  require(Image.Private.pixels captured|>Result.get_ok|>fun bytes->Bytes.sub bytes 0 4=Bytes.of_string"\009\008\007\255")"Canvas copy updates existing image pixels";
  let alternating=Canvas.create_exn~width:640~height:480 in
  let published=ref(Result.get_ok(Canvas.to_image alternating))in
  let publish frame=
    Canvas.set_pixel alternating~x:(frame mod 640)~y:(frame mod 480)
      (Color.rgba(frame land 255)17 31 255);
    let next=Result.get_ok(Canvas.to_image alternating)in
    Image.destroy!published;
    published:=next in
  publish 0;publish 1;
  let before=Gc.allocated_bytes()in
  for frame=2 to 601 do publish frame done;
  let allocated=Gc.allocated_bytes()-.before in
  require(allocated<float(640*480*4))
    (Printf.sprintf
      "Canvas public alternating to_image/destroy allocated %.0f bytes"
      allocated);
  Image.destroy!published;Canvas.destroy alternating;
  let assets=Assets.create()in require(Assets.image_count assets=0)"Assets baseline";
  begin match Audio.init()with Error message->failwith message|Ok()->()end;
  for _=1 to 100_000 do require(Image.Private.identity image>0)"stable image identity"done;
  Assets.destroy assets;Image.destroy captured;Canvas.destroy canvas;Image.destroy image;Audio.shutdown();
  print_endline"Prismel_next_api batch E resource ownership passed"
