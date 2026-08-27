let require value message=if not value then failwith message
let ()=let open Prismel_next_api in
  let image=Image.create ~width:2 ~height:2 ~color:(Color.rgba 1 2 3 4)()in
  require(Image.get_size image=(2,2)&&Bytes.length(Result.get_ok(Image.pixels image))=16)"Image snapshot";
  let canvas=Canvas.create_exn ~width:3 ~height:2 in Canvas.clear canvas Color.black;
  Canvas.set_pixel canvas ~x:1 ~y:1(Color.rgba 9 8 7 6);
  require(Canvas.pixel canvas ~x:1 ~y:1=Some(Color.rgba 9 8 7 6))"Canvas pixel";
  let captured=Result.get_ok(Canvas.to_image canvas)in require(Image.get_size captured=(3,2))"Canvas capture";
  let assets=Assets.create()in require(Assets.image_count assets=0)"Assets baseline";
  begin match Audio.init()with Error message->failwith message|Ok()->()end;
  for _=1 to 100_000 do require(Image.identity image>0)"stable image identity"done;
  Assets.destroy assets;Image.destroy captured;Canvas.destroy canvas;Image.destroy image;Audio.shutdown();
  print_endline"Prismel_next_api batch E resource ownership passed"
