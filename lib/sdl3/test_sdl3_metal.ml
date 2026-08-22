open Sdl3

let fail message = failwith ("SDL3 Metal test: " ^ message)
let get = function Ok value -> value | Error error -> fail (Format.asprintf "%a" pp_error error)

let () =
  if Sys.os_type <> "Unix" || not (Sys.file_exists "/System/Library/Frameworks/Metal.framework")
  then Printf.printf "SDL3 Metal bridge skipped on this platform\n%!"
  else begin
    get (Init.init [Init.Video; Init.Events]);
    let window = get (Window.create ~title:"SDL3 Metal bridge test"
        ~width:64 ~height:48
        ~flags:[Window.Hidden; Window.High_pixel_density; Window.Metal] ()) in
    let logical_width, logical_height = get (Window.size window) in
    let pixel_width, pixel_height = get (Window.size_in_pixels window) in
    let density = get (Window.pixel_density window) in
    if abs_float ((float_of_int pixel_width /. float_of_int logical_width)
        -. density) > 0.01
        || abs_float ((float_of_int pixel_height /. float_of_int logical_height)
          -. density) > 0.01 then
      fail "logical/drawable sizes disagree with the reported pixel density";
    ignore (get (Window.display_scale window));
    ignore (get (Display.name (get (Window.display window))));
    let view = get (Metal_view.create window) in
    ignore (get (Metal_view.layer view));
    (match Window.destroy window with
     | Error { kind = Parent_has_dependents; _ } -> ()
     | Ok () | Error _ -> fail "parent teardown ignored a live Metal view");
    get (Metal_view.destroy view);
    get (Metal_view.destroy view);
    (match Metal_view.layer view with
     | Error { kind = Destroyed; _ } -> ()
     | Ok _ | Error _ -> fail "destroyed Metal view remained usable");
    get (Window.destroy window);
    get (Init.quit ());
    Printf.printf "SDL3 CAMetalLayer ownership bridge passed\n%!"
  end
