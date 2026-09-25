let get = function Ok value -> value | Error message -> failwith message

let () =
  let root = Filename.temp_dir "prismel-store" "" in
  let directory = Filename.concat root "nested" in
  let path = Filename.concat directory "settings.json" in
  Fun.protect ~finally:(fun () ->
    Sys.remove path;
    Unix.rmdir directory;
    Unix.rmdir root) (fun () ->
    let values = Editor.Store.Settings.[
      "animate", Bool true; "density", Float 0.625;
      "label", Text "hello\nworld"; "range", Pair (0.2, 0.8)] in
    get (Editor.Store.Settings.save ~sketch:"test" path values);
    let json = Yojson.Safe.from_file path in
    assert (Yojson.Safe.Util.member "prismel" json = `Int 1);
    assert (Yojson.Safe.Util.member "kind" json = `String "settings");
    assert (Yojson.Safe.Util.member "sections" json <> `Null);
    assert (get (Editor.Store.Settings.load ~sketch:"test" path) = values);
    assert (Result.is_error (Editor.Store.Settings.load ~sketch:"other" path));
    let channel = open_out_bin path in
    output_string channel "PXUI1\nB\t616e696d617465\t1\nF\t64656e73697479\t0.625\n";
    close_out channel;
    let legacy = get (Editor.Store.Settings.load ~sketch:"test" path) in
    assert (Editor.Store.Settings.bool legacy "animate" = Some true);
    assert (Editor.Store.Settings.float legacy "density" = Some 0.625);
    assert (Result.is_error (Editor.Store.Settings.save ~sketch:"test" path
      ["bad", Float infinity]));
    assert (get (Editor.Store.Settings.load ~sketch:"test" path) = legacy));
  let open Prismel in
  let view2 = Easy_camera2.create ~center:(Vec2.create 2. 3.)
    ~zoom:1.5 ~rotation:0.25 () in
  let loaded2 = Editor.Store.Viewport.decode2 (Easy_camera2.create ())
    (Editor.Store.Viewport.encode2 view2) in
  assert (Easy_camera2.center loaded2 = Easy_camera2.center view2);
  assert (Easy_camera2.zoom loaded2 = Easy_camera2.zoom view2);
  assert (Easy_camera2.rotation loaded2 = Easy_camera2.rotation view2);
  let view3 = Easy_camera.create ~distance:9. ~fov_y:0.8 () in
  let loaded3, look = Editor.Store.Viewport.decode3 (Easy_camera.create ())
    (Editor.Store.Viewport.encode3 view3 ~look_through:true) in
  assert (look && abs_float (Easy_camera.distance loaded3 -. 9.) < 0.000001);
  assert (Easy_camera.fov_y loaded3 = Easy_camera.fov_y view3);
  print_endline "editor store: atomic JSON round-trip and PXUI1 read"
