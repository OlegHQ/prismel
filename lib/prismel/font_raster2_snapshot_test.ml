open Tsdl

let ok_sdl = function Ok value -> value | Error (`Msg message) -> failwith message
let ok = function Ok value -> value | Error _ -> failwith "font snapshot error"

let self_test () =
  ok_sdl (Sdl.init Sdl.Init.video);
  let window = ok_sdl (Sdl.create_window ~w:64 ~h:32 "font-snapshot"
      Sdl.Window.hidden) in
  let renderer = ok_sdl (Sdl.create_renderer window ~index:(-1)
      ~flags:Sdl.Renderer.software) in
  Image.Private.set_renderer renderer;
  let font = ok (Font.system ~size:12 ()) in
  let snapshot text =
    let image = ok (Font.Private.cached_text font text
      (Font.Blended Color.white)) in
    image, Option.get (Image_snapshot.find (Obj.repr image))
  in
  ok_sdl (Sdl.render_set_logical_size renderer 64 32);
  let image1, one = snapshot "AV" in
  if not (Bytes.exists (fun value -> value <> '\000') one.rgba) then
    failwith "text alpha missing";
  ok_sdl (Sdl.render_set_logical_size renderer 32 16);
  let image2, two = snapshot "AV" in
  if two.width <= one.width || Image.get_width image2 <> Image.get_width image1 then
    failwith "density-aware rasterization";
  let before_empty = Font.cache_count font in
  let callbacks = Scene_raster2_lowering.{
    image = (fun _ -> Error Resource_failure);
    font_text = (fun _ _ _ _ -> Error Resource_failure);
    system_text = (fun _ _ -> Error Resource_failure);
    debug_text = (fun _ -> Error Resource_failure);
  } in
  let scene3 = Scene3_raster2_lowering.{
    texture = (fun _ -> Error Texture_error);
    shadow = (fun _ -> Error Shadow_error);
  } in
  let target = ok (Raster2_renderer.create ~logical_width:64 ~logical_height:32
      ~drawable_width:64 ~drawable_height:32) in
  let scene = [Scene_description.Clear Color.black;
    Scene_description.Font_text (font, (2, 16), "AV", Some Color.white,
      None, None)] in
  let empty = [Scene_description.Clear Color.black;
    Scene_description.Font_text (font, (2, 16), "", Some Color.white,
      None, None)] in
  let resources = Raster2_renderer.{ scene2 = callbacks; scene3 } in
  let expected = (ok (Raster2_renderer.render target resources scene)).rgba in
  let empty_pixels = (ok (Raster2_renderer.render target resources empty)).rgba in
  if Font.cache_count font <> before_empty || expected = empty_pixels then
    failwith "empty text or baseline";
  for _ = 1 to 600 do
    if (ok (Raster2_renderer.render target resources scene)).rgba <> expected then
      failwith "text frame drift"
  done;
  for index = 0 to 256 do
    ignore (ok (Font.Private.cached_text font (Printf.sprintf "glyph-%03d" index)
      (Font.Blended Color.white)))
  done;
  if Font.cache_count font > 256 then failwith "font snapshot cache unbounded";
  let before_mutation = Image_snapshot.live_bytes () in
  Font.set_style font [Font.Bold];
  if Font.cache_count font <> 0 || Image_snapshot.live_bytes () >= before_mutation then
    failwith "font mutation did not invalidate snapshots";
  ok (Raster2_renderer.destroy target);
  Font.release_renderer renderer;
  Font.destroy font;
  Sdl.destroy_renderer renderer;
  Sdl.destroy_window window;
  Sdl.quit ()

let () =
  match Sys.getenv_opt "PRISMEL_TEST_FONT_RASTER2_SNAPSHOT" with
  | Some "1" -> self_test ()
  | _ -> ()
