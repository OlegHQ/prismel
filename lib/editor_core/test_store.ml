let get = function Ok value -> value | Error message -> failwith message

let () =
  let root = Filename.temp_dir "rays-store" "" in
  let directory = Filename.concat root "nested" in
  let path = Filename.concat directory "settings.rays" in
  Fun.protect ~finally:(fun () ->
    Sys.remove path;
    Unix.rmdir directory;
    Unix.rmdir root) (fun () ->
    let values = Editor_core.Store.Settings.[
      "animate", Bool true; "density", Float 0.625;
      "label", Text "hello\nworld"; "range", Pair (0.2, 0.8)] in
    get (Editor_core.Store.Settings.save ~sketch:"test" path values);
    assert (get (Editor_core.Store.Settings.load ~sketch:"test" path) = values);
    assert (Result.is_error (Editor_core.Store.Settings.load ~sketch:"other" path));
    let text = get (Editor_core.Store.read_text ~filename:path) in
    assert (String.starts_with ~prefix:"(settings :sketch \"test\"" text);
    assert (Result.is_error (Editor_core.Store.Settings.save ~sketch:"test" path
      ["bad", Float infinity]));
    assert (get (Editor_core.Store.Settings.load ~sketch:"test" path) = values));
  let open Rays in
  let view2 = Easy_camera2.create ~center:(Vec2.create 2. 3.)
    ~zoom:1.5 ~rotation:0.25 () in
  let loaded2 = Editor_core.Store.Viewport.decode2 (Easy_camera2.create ())
    (Editor_core.Store.Viewport.encode2 view2) in
  assert (Easy_camera2.center loaded2 = Easy_camera2.center view2);
  assert (Easy_camera2.zoom loaded2 = Easy_camera2.zoom view2);
  assert (Easy_camera2.rotation loaded2 = Easy_camera2.rotation view2);
  let view3 = Easy_camera.create ~distance:9. ~fov_y:0.8 () in
  let loaded3, look = Editor_core.Store.Viewport.decode3 (Easy_camera.create ())
    (Editor_core.Store.Viewport.encode3 view3 ~look_through:true) in
  assert (look && abs_float (Easy_camera.distance loaded3 -. 9.) < 0.000001);
  assert (Easy_camera.fov_y loaded3 = Easy_camera.fov_y view3);
  print_endline "editor store: atomic s-expression round-trip"
