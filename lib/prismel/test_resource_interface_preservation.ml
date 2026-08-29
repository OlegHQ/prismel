open Prismel

let require condition message = if not condition then failwith message

let () =
  let assets = Assets.create ~root:"." () in
  require (Assets.root assets = ".") "asset root";
  require (Assets.resolve assets "image.png" = "./image.png")
    "asset path resolution";
  Assets.destroy assets;

  require (Result.is_ok (Audio.init ())) "audio init";
  let sample = Result.get_ok
      (Audio.Sample.synth ~waveform:Sine ~frequency:440. ~duration:0.01 ()) in
  let channel = Result.get_ok (Audio.Sample.play sample) in
  require (Audio.Sample.is_playing channel) "sample playing";
  Audio.Sample.stop channel;
  require (not (Audio.Sample.is_playing channel)) "sample stopped";
  Audio.Sample.destroy sample;
  Audio.shutdown ();

  let image = Image.create ~width:2 ~height:3 () in
  require (Image.get_size image = (2, 3)) "image dimensions";
  let identity = Image.Private.identity image in
  let replacement = Image.create ~width:1 ~height:1 ~color:Color.red () in
  Image.Private.replace image replacement;
  require (Image.get_size image = (1, 1)
           && Image.Private.identity image = identity) "stable image replacement";
  Image.destroy image;

  let canvas = Canvas.create_exn ~width:2 ~height:2 in
  Canvas.set_pixel canvas ~x:1 ~y:1 (Color.rgba 9 8 7 6);
  require (Canvas.pixel canvas ~x:1 ~y:1 = Some (Color.rgba 9 8 7 6))
    "canvas pixel readback";
  let canvas_image = Result.get_ok (Canvas.to_image canvas) in
  require (Image.get_size canvas_image = (2, 2)) "canvas texture snapshot";
  Image.destroy canvas_image;
  Canvas.destroy canvas;
  print_endline "native resource interface: ok"
