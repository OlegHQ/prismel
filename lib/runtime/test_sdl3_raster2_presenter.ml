let get_sdl = function Ok value -> value | Error error -> failwith error.Sdl3.message
let get = function Ok value -> value | Error _ -> failwith "presenter error"

module Presenter = Runtime_sdl3_raster2_presenter.Sdl3_raster2_presenter

let pixels width height seed =
  Bytes.init (width * height * 4) (fun index ->
    Char.chr ((index * 17 + seed * 29) land 255))

let frame ~logical_width ~logical_height ~drawable_width ~drawable_height seed =
  let pitch = drawable_width * 4 in
  Presenter.{
    rgba = pixels drawable_width drawable_height seed;
    pitch; logical_width; logical_height; drawable_width; drawable_height;
  }

let () =
  get_sdl (Sdl3.Init.init ~release:false [Video]);
  let window = get_sdl (Sdl3.Window.create ~title:"raster2-presenter"
      ~width:7 ~height:5 ~flags:[Hidden] ()) in
  let presenter = get (Presenter.create window) in
  let check number =
    let value = frame ~logical_width:7 ~logical_height:5
        ~drawable_width:7 ~drawable_height:5 number in
    get (Presenter.present presenter value);
    let actual = get (Presenter.copy_rgba presenter) in
    if actual <> value.rgba then begin
      let rec first index =
        if index = min (Bytes.length actual) (Bytes.length value.rgba) then index
        else if Bytes.get actual index <> Bytes.get value.rgba index then index
        else first (index + 1)
      in
      failwith (Printf.sprintf "SDL3 renderer readback differs: %d/%d first=%d"
        (Bytes.length actual) (Bytes.length value.rgba) (first 0))
    end
  in
  List.iter check [1; 2; 60; 600];
  get_sdl (Sdl3.Window.set_size window ~width:9 ~height:3);
  get_sdl (Sdl3.Window.sync window);
  let resized = frame ~logical_width:9 ~logical_height:3
      ~drawable_width:9 ~drawable_height:3 601 in
  get (Presenter.present presenter resized);
  if get (Presenter.copy_rgba presenter) <> resized.rgba then
    failwith "post-resize readback differs";
  for index = 1 to 100_000 do
    get (Presenter.present presenter
      (frame ~logical_width:9 ~logical_height:3
        ~drawable_width:9 ~drawable_height:3 index))
  done;
  let stats = Presenter.stats presenter in
  if stats.live_presenters <> 1 || stats.live_textures <> 1 ||
      stats.texture_recreations <> 2 || stats.presented_frames <> 100_005 then
    failwith "presenter lifecycle counters are not bounded";
  get (Presenter.destroy presenter);
  let stats = Presenter.stats presenter in
  if stats.live_presenters <> 0 || stats.live_textures <> 0 then
    failwith "destroy retained presenter resources";
  get_sdl (Sdl3.Window.destroy window);
  get_sdl (Sdl3.Init.quit_subsystems [Video]);
  print_endline "SDL3 Raster2 presenter fixture passed"
