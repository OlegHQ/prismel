open Tsdl

let ok_sdl = function Ok value -> value | Error (`Msg message) -> failwith message
let ok = function Ok value -> value | Error message -> failwith message
let ok_renderer = function Ok value -> value | Error _ -> failwith "renderer"

let self_test () =
  ok_sdl (Sdl.init Sdl.Init.video);
  let window = ok_sdl (Sdl.create_window ~w:12 ~h:10 "canvas-snapshot"
      Sdl.Window.hidden) in
  let renderer = ok_sdl (Sdl.create_renderer window ~index:(-1)
      ~flags:Sdl.Renderer.software) in
  Image.Private.set_renderer renderer;
  let canvas = ok (Canvas.create ~width:7 ~height:5) in
  Canvas.render canvas [Scene.group [
    Scene.rect ~at:(0, 0) ~w:7 ~h:5 ~fill:(Color.rgba 10 20 30 40) ();
    Scene.point ~at:(3, 2) ~color:(Color.rgba 200 100 50 128) ()]];
  let first_image = ok (Canvas.to_image canvas) in
  let first = Option.get (Image_snapshot.find (Obj.repr first_image)) in
  if first.width <> 7 || first.height <> 5 || Bytes.length first.rgba <> 140 ||
      Char.code (Bytes.get first.rgba (3 * 4 + 2 * 28 + 3)) <> 147 then
    failwith "canvas alpha/pitch snapshot";
  let saved = Filename.temp_file "prismel-canvas" ".png" in
  ok (Canvas.save_png canvas saved);
  if (Unix.stat saved).st_size <= 0 then failwith "canvas save";
  Sys.remove saved;
  Canvas.set_pixel canvas ~x:0 ~y:0 (Color.rgba 1 2 3 4);
  let second_image = ok (Canvas.to_image canvas) in
  let second = Option.get (Image_snapshot.find (Obj.repr second_image)) in
  if second.generation <= first.generation ||
      Bytes.sub second.rgba 0 4 <> Bytes.of_string "\001\002\003\004" then
    failwith "canvas mutation generation";
  let rejecting = Scene_raster2_lowering.{
    image = (fun _ -> Error Resource_failure);
    font_text = (fun _ _ _ _ -> Error Resource_failure);
    system_text = (fun _ _ -> Error Resource_failure);
    debug_text = (fun _ -> Error Resource_failure);
  } in
  let scene3 = Scene3_raster2_lowering.{
    texture = (fun _ -> Error Texture_error);
    shadow = (fun _ -> Error Shadow_error) } in
  let target = ok_renderer (Raster2_renderer.create ~logical_width:12
      ~logical_height:10 ~drawable_width:12 ~drawable_height:10) in
  let scene = [Scene_description.Clear Color.black;
    Scene_description.Image (second_image, (2, 2), None, None, None, None)] in
  let callbacks = Raster2_renderer.{ scene2 = rejecting; scene3 } in
  let expected = (ok_renderer (Raster2_renderer.render target callbacks scene)).rgba in
  for _ = 1 to 600 do
    if (ok_renderer (Raster2_renderer.render target callbacks scene)).rgba <>
        expected then failwith "canvas frame drift"
  done;
  ok_renderer (Raster2_renderer.destroy target);
  Image.destroy first_image;
  Image.destroy second_image;
  Canvas.destroy canvas;
  let baseline = Image_snapshot.live_bytes () in
  for _ = 1 to 100_000 do
    let value = ok (Canvas.create ~width:1 ~height:1) in
    Canvas.destroy value
  done;
  if Image_snapshot.live_bytes () <> baseline then failwith "canvas plateau";
  Font.release_renderer renderer;
  Sdl.destroy_renderer renderer;
  Sdl.destroy_window window;
  Sdl.quit ()

let () =
  match Sys.getenv_opt "PRISMEL_TEST_CANVAS_RASTER2_SNAPSHOT" with
  | Some "1" -> self_test ()
  | _ -> ()
