open Tsdl

let ok = function Ok value -> value | Error _ -> failwith "snapshot test error"
let ok_sdl = function Ok value -> value | Error (`Msg message) -> failwith message

let self_test () =
  let baseline = Image_snapshot.live_bytes () in
  ok_sdl (Sdl.init Sdl.Init.video);
  let window = ok_sdl (Sdl.create_window ~w:8 ~h:8 "snapshot" Sdl.Window.hidden) in
  let renderer = ok_sdl (Sdl.create_renderer window ~index:(-1)
      ~flags:Sdl.Renderer.software) in
  Image.Private.set_renderer renderer;
  let original = Image.create ~width:3 ~height:2
      ~color:(Color.rgba 17 34 51 127) () in
  let first = Option.get (Image_snapshot.find (Obj.repr original)) in
  if first.width <> 3 || first.height <> 2 || Bytes.length first.rgba <> 24 ||
      Bytes.sub first.rgba 0 4 <> Bytes.of_string "\017\034\051\127" then
    failwith (Printf.sprintf "synthesized RGBA snapshot %d,%d,%d,%d"
      (Char.code (Bytes.get first.rgba 0)) (Char.code (Bytes.get first.rgba 1))
      (Char.code (Bytes.get first.rgba 2)) (Char.code (Bytes.get first.rgba 3)));
  let path = Filename.temp_file "prismel-image-snapshot" ".png" in
  let source = ok_sdl (Sdl.create_rgb_surface_with_format ~w:2 ~h:1 ~depth:32
      Sdl_compat.format_rgba32) in
  let format = ok_sdl (Sdl.alloc_format Sdl_compat.format_rgba32) in
  let pixel = Sdl.map_rgba format 9 8 7 33 in
  ok_sdl (Sdl.fill_rect source None pixel);
  Sdl.free_format format;
  if Tsdl_image.Image.save_png source path <> 0 then failwith "PNG fixture";
  Sdl.free_surface source;
  let loaded = ok (Image.load path) in
  Sys.remove path;
  let loaded_snapshot = Option.get (Image_snapshot.find (Obj.repr loaded)) in
  if loaded_snapshot.width <> 2 || loaded_snapshot.height <> 1 ||
      Bytes.sub loaded_snapshot.rgba 0 4 <> Bytes.of_string "\009\008\007\033"
  then failwith "loaded RGBA snapshot";
  Image.destroy loaded;
  let identity = original in
  begin match Image.load "/prismel/does/not/exist.png" with
  | Error _ -> ()
  | Ok _ -> failwith "missing image unexpectedly loaded"
  end;
  let unchanged = Option.get (Image_snapshot.find (Obj.repr original)) in
  if unchanged.generation <> first.generation || original != identity then
    failwith "failed reload changed identity";
  let replacement = Image.create ~width:5 ~height:4
      ~color:(Color.rgba 200 100 50 64) () in
  Image.Private.replace original replacement;
  let second = Option.get (Image_snapshot.find (Obj.repr original)) in
  if original != identity || second.generation <> Int64.succ first.generation ||
      second.width <> 5 || second.height <> 4 || Bytes.length second.rgba <> 80 ||
      Bytes.sub second.rgba 0 4 <> Bytes.of_string "\200\100\050\064" then
    failwith "successful reload snapshot";
  let rejecting = Scene_raster2_lowering.{
    image = (fun _ -> Error Resource_failure);
    font_text = (fun _ _ _ _ -> Error Resource_failure);
    system_text = (fun _ _ -> Error Resource_failure);
    debug_text = (fun _ -> Error Resource_failure);
  } in
  let scene3 = Scene3_raster2_lowering.{
    texture = (fun _ -> Error Texture_error);
    shadow = (fun _ -> Error Shadow_error);
  } in
  let target = ok (Raster2_renderer.create ~logical_width:8 ~logical_height:8
      ~drawable_width:8 ~drawable_height:8) in
  let scene = [Scene_description.Clear Color.black;
    Scene_description.Image (original, (1, 1), None, None, None, None)] in
  let callbacks = Raster2_renderer.{ scene2 = rejecting; scene3 } in
  let expected = (ok (Raster2_renderer.render target callbacks scene)).rgba in
  for _ = 1 to 600 do
    if (ok (Raster2_renderer.render target callbacks scene)).rgba <> expected then
      failwith "snapshot frame drift"
  done;
  ok (Raster2_renderer.destroy target);
  Image.destroy original;
  Sdl.destroy_renderer renderer;
  Sdl.destroy_window window;
  Sdl.quit ();
  if Image_snapshot.live_bytes () <> baseline then
    failwith "snapshot memory retained"

let () =
  match Sys.getenv_opt "PRISMEL_TEST_IMAGE_RASTER2_SNAPSHOT" with
  | Some "1" -> self_test ()
  | _ -> ()
