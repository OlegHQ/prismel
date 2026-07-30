open Tsdl

let open_ = ref false

let is_open () = !open_

let stop () =
  if !open_ then begin
    (try App.cleanup_graphics () with _ -> ());
    (try App.cleanup_sdl () with _ -> ());
    open_ := false;
    App.framework_running := false
  end

let start ?(width = 800) ?(height = 600) ?(title = "Prismel preview") () =
  if App.is_running () then
    invalid_arg "Preview.start: a Sketch/App loop is already running";
  if not !open_ then
    try
      App.init_sdl ();
      Time.init ();
      let config = {
        Window.default_config with
        width;
        height;
        title;
        resizable = true;
        vsync = true;
      } in
      ignore (Window.create ~config ());
      if not (Backend.is_headless ()) then Window.show ();
      let _, mouse = Sdl.get_mouse_state () in
      Input.reset ~mouse;
      let renderer = Window.get_renderer () in
      Graphics.init renderer;
      Image.Private.set_renderer renderer;
      open_ := true;
      App.framework_running := true
    with error ->
      (try App.cleanup_graphics () with _ -> ());
      (try App.cleanup_sdl () with _ -> ());
      open_ := false;
      App.framework_running := false;
      raise error

let step scene =
  if not !open_ then start ();
  Input.begin_frame ();
  let events = Event.poll_events () in
  if List.exists (function Event.WindowClosed -> true | _ -> false) events then
    stop ()
  else begin
    Time.update ();
    let renderer = Window.get_renderer () in
    (match Sdl.render_clear renderer with
     | Ok () -> ()
     | Error (`Msg message) ->
         failwith ("Preview clear failed: " ^ message));
    Scene.render scene;
    Sdl.render_present renderer
  end;
  events

let show scene = ignore (step scene)
