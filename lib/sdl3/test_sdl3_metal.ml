module System_thread = Thread

open Sdl3

let fail message = failwith ("SDL3 Metal test: " ^ message)
let get = function Ok value -> value | Error error -> fail (Format.asprintf "%a" pp_error error)
let rec drain_events () = match get (Event.poll_coalesced ()) with
  | [] -> () | _ :: _ -> drain_events ()

let run () =
  if Sys.os_type <> "Unix" || not (Sys.file_exists "/System/Library/Frameworks/Metal.framework")
  then Printf.printf "SDL3 Metal bridge skipped on this platform\n%!"
  else begin
    get (Init.init [Init.Video; Init.Events]);
    let window = get (Window.create ~title:"SDL3 Metal bridge test"
        ~width:64 ~height:48
        ~flags:[Window.Hidden; Window.High_pixel_density; Window.Metal] ()) in
    let logical_width, logical_height = get (Window.size window) in
    let pixel_width, pixel_height = get (Window.size_in_pixels window) in
    let facts = get (Window.presentation_facts window ~vsync:true) in
    let density = facts.pixel_density in
    if abs_float ((float_of_int pixel_width /. float_of_int logical_width)
        -. density) > 0.01
        || abs_float ((float_of_int pixel_height /. float_of_int logical_height)
          -. density) > 0.01 then
      fail "logical/drawable sizes disagree with the reported pixel density";
    get (Window.set_size window ~width:80 ~height:60);
    get (Window.sync window);
    if get (Window.size window) <> (80, 60) then
      fail "native synchronized resize changed logical dimensions";
    let resized_pixel_width, resized_pixel_height =
      get (Window.size_in_pixels window)
    in
    if abs_float ((float_of_int resized_pixel_width /. 80.) -. density) > 0.01
        || abs_float ((float_of_int resized_pixel_height /. 60.) -. density)
          > 0.01 then
      fail "native resize double-scaled logical dimensions";
    let facts = get (Window.presentation_facts window ~vsync:true) in
    if facts.logical_width <> 80 || facts.logical_height <> 60
        || facts.drawable_width <> resized_pixel_width
        || facts.drawable_height <> resized_pixel_height
        || facts.refresh_rate = None || not facts.vsync then
      fail "native presentation facts are incomplete";
    get (Window.set_resizable window false);
    get (Window.set_resizable window true);
    get (Window.center window);
    List.iter (fun shape ->
      let cursor = get (Cursor.create shape) in
      get (Cursor.set cursor);
      get (Cursor.destroy cursor))
      Cursor.[Default; Text; Ew_resize; Ns_resize];
    let await_hidden ~label expected =
      let deadline = Unix.gettimeofday () +. 30. in
      let rec loop () =
        drain_events ();
        if (get (Window.state window)).hidden = expected then ()
        else if Unix.gettimeofday () >= deadline then
          fail (label ^ " did not reach the requested native window state")
        else begin
          System_thread.delay 0.01;
          loop ()
        end
      in
      loop ()
    in
    await_hidden ~label:"initially hidden" true;
    get (Window.show window);
    get (Window.sync window);
    await_hidden ~label:"show" false;
    get (Window.hide window);
    get (Window.sync window);
    await_hidden ~label:"hide" true;
    let view = get (Metal_view.create window) in
    ignore (get (Metal_view.layer view));
    (match Domain.spawn (fun () -> Metal_view.layer view) |> Domain.join with
     | Error { kind = Wrong_domain; _ } -> ()
     | Ok _ | Error _ -> fail "wrong-domain Metal view access was not rejected");
    (match Window.destroy window with
     | Error { kind = Parent_has_dependents; _ } -> ()
     | Ok () | Error _ -> fail "parent teardown ignored a live Metal view");
    get (Metal_view.destroy view);
    get (Metal_view.destroy view);
    (match Metal_view.layer view with
     | Error { kind = Destroyed; _ } -> ()
     | Ok _ | Error _ -> fail "destroyed Metal view remained usable");
    get (Window.destroy window);
    get (Init.quit_subsystems [Init.Video; Init.Events]);
    Printf.printf "SDL3 CAMetalLayer ownership bridge passed\n%!"
  end
