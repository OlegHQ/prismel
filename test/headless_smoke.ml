open Prismel
open Tsdl

let sdl_exn context = function
  | Ok value -> value
  | Error (`Msg message) -> failwith (context ^ ": " ^ message)

let push_mouse_motion x y =
  let event = Sdl.Event.create () in
  Sdl.Event.set event Sdl.Event.typ Sdl.Event.mouse_motion;
  Sdl.Event.set event Sdl.Event.mouse_motion_x x;
  Sdl.Event.set event Sdl.Event.mouse_motion_y y;
  if not (sdl_exn "push mouse motion" (Sdl.push_event event)) then
    failwith "SDL rejected a synthetic mouse motion"

let push_mouse_button ?(button = 1) event_type x y =
  let event = Sdl.Event.create () in
  Sdl.Event.set event Sdl.Event.typ event_type;
  Sdl.Event.set event Sdl.Event.mouse_button_button button;
  Sdl.Event.set event Sdl.Event.mouse_button_x x;
  Sdl.Event.set event Sdl.Event.mouse_button_y y;
  if not (sdl_exn "push mouse button" (Sdl.push_event event)) then
    failwith "SDL rejected a synthetic mouse button event"

let verify_two_x_renderer () =
  let surface =
    sdl_exn "2x probe surface"
      (Sdl.create_rgb_surface_with_format ~w:128 ~h:96 ~depth:32
         Sdl.Pixel.format_rgba32)
  in
  let renderer =
    match Sdl.create_software_renderer surface with
    | Ok renderer -> renderer
    | Error (`Msg message) ->
        Sdl.free_surface surface;
        failwith ("2x probe renderer: " ^ message)
  in
  let previous_renderer = !Image.Private.current_renderer in
  Fun.protect
    ~finally:(fun () ->
      Font.release_renderer renderer;
      Image.Private.current_renderer := previous_renderer;
      Sdl.destroy_renderer renderer;
      Sdl.free_surface surface)
    (fun () ->
      sdl_exn "2x logical size"
        (Sdl.render_set_logical_size renderer 64 48);
      ignore (Sdl.set_render_draw_color renderer 0 0 0 255);
      sdl_exn "2x clear" (Sdl.render_clear renderer);
      ignore (Sdl.set_render_draw_color renderer 255 0 0 255);
      let full = Sdl.Rect.create ~x:0 ~y:0 ~w:64 ~h:48 in
      sdl_exn "2x logical rectangle"
        (Sdl.render_fill_rect renderer (Some full));
      Sdl.render_present renderer;
      sdl_exn "2x surface lock" (Sdl.lock_surface surface);
      Fun.protect
        ~finally:(fun () -> Sdl.unlock_surface surface)
        (fun () ->
          let values = Sdl.get_surface_pixels surface Bigarray.int32 in
          let stride = Sdl.get_surface_pitch surface / 4 in
          let format =
            sdl_exn "2x pixel format"
              (Sdl.alloc_format Sdl.Pixel.format_rgba32)
          in
          Fun.protect ~finally:(fun () -> Sdl.free_format format) (fun () ->
            match Sdl.get_rgba format values.{(95 * stride) + 127} with
            | 255, 0, 0, 255 -> ()
            | _ ->
                failwith
                  "logical rectangle did not reach the physical bottom-right pixel"));
      Image.Private.set_renderer renderer;
      match Font.system ~size:14 () with
      | Error (`Msg message) -> failwith message
      | Ok font ->
          let image =
            sdl_exn "2x system text"
              (Font.cached_text font "Retina" (Font.Blended Color.white))
          in
          let logical_width, logical_height = Image.get_size image in
          let physical_width, physical_height =
            match Sdl.query_texture (Image.Private.get_texture image) with
            | Ok (_, _, dimensions) -> dimensions
            | Error (`Msg message) ->
                failwith ("2x text texture query: " ^ message)
          in
          if abs (physical_width - (2 * logical_width)) > 2
             || abs (physical_height - (2 * logical_height)) > 2
          then
            failwith
              "system text was not rasterized at backing-pixel density")

let output_u16 channel value =
  output_byte channel (value land 0xff);
  output_byte channel ((value lsr 8) land 0xff)

let output_u32 channel value =
  output_u16 channel (value land 0xffff);
  output_u16 channel ((value lsr 16) land 0xffff)

let write_silent_wav filename =
  let samples = 80 in
  let channel = open_out_bin filename in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
    output_string channel "RIFF";
    output_u32 channel (36 + (samples * 2));
    output_string channel "WAVEfmt ";
    output_u32 channel 16;
    output_u16 channel 1;
    output_u16 channel 1;
    output_u32 channel 8_000;
    output_u32 channel 16_000;
    output_u16 channel 2;
    output_u16 channel 16;
    output_string channel "data";
    output_u32 channel (samples * 2);
    for _ = 1 to samples do output_u16 channel 0 done)

let find_test_font () =
  [
    "/System/Library/Fonts/Supplemental/Arial.ttf";
    "/System/Library/Fonts/Supplemental/Courier New.ttf";
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
    "/usr/share/fonts/TTF/DejaVuSans.ttf";
  ]
  |> List.find_opt Sys.file_exists

let init (frame : Frame.t) =
  if frame.size <> (32, 32) then failwith "incorrect initial frame size";
  let window_renderer = Low.Window.get_renderer () in
  if Sdl.render_get_logical_size window_renderer <> frame.size then
    failwith "renderer logical size diverged from the sketch coordinate space";
  let output_size =
    sdl_exn "window drawable size"
      (Sdl.get_renderer_output_size window_renderer)
  in
  if frame.drawable_size <> output_size
     || frame.drawable_width <> fst output_size
     || frame.drawable_height <> snd output_size
  then failwith "frame drawable facts did not match the native render target";
  if frame.pixel_scale <> (1., 1.) then
    failwith "dummy renderer unexpectedly changed the backing scale";
  verify_two_x_renderer ();
  let empty_ui =
    Pxui.create ~x:0 ~y:0 ~width:240 ()
    |> Pxui.text_field ~name:"empty" ~label:"Empty" ~value:""
  in
  let empty_ui_canvas = Canvas.create_exn ~width:240 ~height:40 in
  Canvas.render empty_ui_canvas (Pxui.scene empty_ui);
  Canvas.destroy empty_ui_canvas;
  let canvas = Canvas.create_exn ~width:8 ~height:8 in
  Canvas.render canvas Scene.[
    clear Color.black;
    clip ~at:(2, 2) ~w:4 ~h:4 [
      rect ~at:(0, 0) ~w:8 ~h:8 ~fill:Color.red ();
    ];
  ];
  (match Canvas.pixel canvas ~x:3 ~y:3, Canvas.pixel canvas ~x:0 ~y:0 with
   | Some inside, Some outside
     when Color.equal inside Color.red && Color.equal outside Color.black -> ()
   | _ -> failwith "offscreen clipping or pixel readback failed");
  Canvas.map_pixels canvas (fun ~x:_ ~y:_ -> Color.invert);
  (match Canvas.pixel canvas ~x:0 ~y:0 with
   | Some color when Color.equal color Color.white -> ()
   | _ -> failwith "canvas pixel mapping failed");
  let nested_squares =
    Path.empty
    |> Path.move_to 0. 0.
    |> Path.line_to 7. 0.
    |> Path.line_to 7. 7.
    |> Path.line_to 0. 7.
    |> Path.close
    |> Path.move_to 2. 2.
    |> Path.line_to 5. 2.
    |> Path.line_to 5. 5.
    |> Path.line_to 2. 5.
    |> Path.close
  in
  Canvas.render canvas Scene.[
    clear Color.black;
    path ~fill:Color.red nested_squares;
  ];
  (match Canvas.pixel canvas ~x:1 ~y:1, Canvas.pixel canvas ~x:3 ~y:3 with
   | Some outer, Some hole
     when Color.equal outer Color.red && Color.equal hole Color.black -> ()
   | _ -> failwith "even-odd multi-contour path did not preserve its hole");
  Canvas.render canvas Scene.[
    clear Color.black;
    path ~fill_rule:Path.Non_zero ~fill:Color.red nested_squares;
  ];
  (match Canvas.pixel canvas ~x:3 ~y:3 with
   | Some color when Color.equal color Color.red -> ()
   | _ -> failwith "non-zero path fill did not honor contour winding");
  let source = Canvas.create_exn ~width:4 ~height:4 in
  let mask = Canvas.create_exn ~width:4 ~height:4 in
  Canvas.render source Scene.[clear Color.red];
  Canvas.render mask Scene.[
    clear Color.transparent;
    rect ~at:(0, 0) ~w:2 ~h:4 ~fill:Color.white ();
  ];
  Canvas.apply_mask ~source ~mask;
  (match Canvas.pixel source ~x:0 ~y:1, Canvas.pixel source ~x:3 ~y:1 with
   | Some visible, Some hidden when visible.a = 255 && hidden.a = 0 -> ()
   | _ -> failwith "canvas alpha mask did not compose source pixels");
  Canvas.destroy source;
  Canvas.destroy mask;
  let transformed = Canvas.create_exn ~width:16 ~height:16 in
  Canvas.render transformed Scene.[
    clear Color.black;
    translate 8 8 [
      rotate (Float.pi /. 4.) [
        rect ~at:(-4, -1) ~w:8 ~h:2 ~fill:Color.red ();
      ];
    ];
  ];
  (match
     Canvas.pixel transformed ~x:8 ~y:8,
     Canvas.pixel transformed ~x:6 ~y:10
   with
   | Some center, Some outside
     when Color.equal center Color.red && Color.equal outside Color.black -> ()
   | _ -> failwith "rotated rectangle did not transform its full geometry");
  Canvas.render transformed Scene.[
    clear Color.black;
    translate 8 8 [
      scale 2. 0.5 [
        circle ~at:(0, 0) ~radius:3 ~fill:Color.cyan ();
      ];
    ];
  ];
  (match
     Canvas.pixel transformed ~x:12 ~y:8,
     Canvas.pixel transformed ~x:8 ~y:11
   with
   | Some wide, Some outside
     when Color.equal wide Color.cyan && Color.equal outside Color.black -> ()
   | _ -> failwith "scaled circle did not transform into an ellipse");
  Canvas.destroy transformed;
  let filename = Filename.temp_file "prismel-canvas-" ".png" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists filename then Sys.remove filename)
    (fun () ->
      match Canvas.save_png canvas filename with
      | Ok () ->
          if (Unix.stat filename).st_size = 0 then
            failwith "canvas PNG was empty";
          let assets = Assets.create ~watch:true () in
          let first = Assets.image_exn assets filename in
          let second = Assets.image_exn assets filename in
          if first != second || Assets.image_count assets <> 1 then
            failwith "asset cache duplicated an image resource";
          let replacement = Canvas.create_exn ~width:4 ~height:4 in
          Canvas.render replacement Scene.[clear Color.blue];
          (match Canvas.save_png replacement filename with
           | Ok () -> ()
           | Error message -> failwith message);
          Canvas.destroy replacement;
          let now = Unix.gettimeofday () +. 2. in
          Unix.utimes filename now now;
          (match Assets.refresh assets with
           | Ok [_] -> ()
           | Ok _ -> failwith "hot asset refresh missed a changed image"
           | Error errors -> failwith (String.concat "; " errors));
          if Assets.image_exn assets filename != first
             || Image.get_size first <> (4, 4)
          then failwith "hot image reload did not preserve borrowed identity";
          (match Assets.preload assets
             [Assets.Image_file filename; Assets.Image_file "missing.png"] with
           | Error [_] -> ()
           | _ -> failwith "asset preload did not aggregate errors");
          Assets.destroy assets;
          let parallel_assets = Assets.create () in
          (match Assets.preload_parallel parallel_assets
             [Assets.Image_file filename; Assets.Image_file "missing.png"] with
           | Error [_] when Assets.image_count parallel_assets = 1 -> ()
           | _ ->
               failwith
                 "parallel preload did not join decoding or aggregate errors");
          Assets.destroy parallel_assets
      | Error message -> failwith message);
  let wav = Filename.temp_file "prismel-audio-" ".wav" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists wav then Sys.remove wav)
    (fun () ->
      write_silent_wav wav;
      let assets = Assets.create () in
      let sample = Assets.sample_exn assets wav in
      let same_sample = Assets.sample_exn assets wav in
      if sample != same_sample || Assets.sample_count assets <> 1 then
        failwith "asset cache duplicated an audio sample";
      (match Audio.Sample.play ~volume:0. sample with
       | Ok channel -> Audio.Sample.stop channel
       | Error message -> failwith message);
      Assets.destroy assets;
      let tone =
        match Audio.Sample.synth ~sample_rate:8_000 ~volume:0.
            ~waveform:Audio.Sample.Sine ~frequency:440. ~duration:0.01 () with
        | Ok sample -> sample
        | Error message -> failwith message
      in
      Audio.Sample.destroy tone);
  (match find_test_font () with
   | None -> ()
   | Some path ->
       let font =
         match Font.load path 12 with
         | Ok font -> font
         | Error (`Msg message) -> failwith message
       in
       let render () =
         match
           Font.cached_text ~wrap:120 ~align:Font.Center font
             "cached text\nstays borrowed" (Font.Blended Color.white)
         with
         | Ok image -> image
         | Error (`Msg message) -> failwith message
       in
       let first = render () in
       let second = render () in
       if first != second || Font.cache_count font <> 1 then
         failwith "font cache duplicated a rendered text texture";
       Canvas.render canvas Scene.[
         clear Color.black;
         font_text font ~at:(0, 0) ~wrap:8 ~align:Font.Center "A";
       ];
       if Font.cache_count font <> 2 then
         failwith "font cache did not distinguish offscreen renderers";
       Font.set_style font [Font.Bold];
       if Font.cache_count font <> 0 then
         failwith "font style change did not invalidate rendered text";
       let empty_image =
         match Font.render_text font "" (Font.Blended Color.white) with
         | Ok image -> image
         | Error (`Msg message) -> failwith message
       in
       Image.destroy empty_image;
       List.iter
         (fun mode ->
           match Font.render_wrapped font "" mode 24 with
           | Ok [image] -> Image.destroy image
           | Ok images ->
               List.iter Image.destroy images;
               failwith "empty wrapped text returned an unexpected image count"
           | Error (`Msg message) -> failwith message)
         [ Font.Solid Color.white;
           Font.Shaded (Color.white, Color.black);
           Font.Blended Color.white ];
       for index = 0 to 269 do
         match
           Font.Private.cached_text font (string_of_int index)
             (Font.Blended Color.white)
         with
         | Ok _ -> ()
         | Error (`Msg message) -> failwith message
       done;
       if Font.cache_count font <> 256 then
         failwith "dynamic labels escaped the renderer-local font cache bound";
       Font.destroy font;
       (match Font.load_dpi path 12 144 96 with
        | Error _ -> ()
        | Ok font ->
            Font.destroy font;
            failwith "non-uniform DPI silently ignored an unsupported axis");
       let dpi_font =
         match Font.load_dpi path 12 144 144 with
         | Ok font -> font
         | Error (`Msg message) -> failwith message
       in
       let dpi_image =
         match Font.cached_text dpi_font "DPI" (Font.Blended Color.white) with
         | Ok image -> image
         | Error (`Msg message) -> failwith message
       in
       let logical_width, logical_height = Image.get_size dpi_image in
       let physical_width, physical_height =
         match Sdl.query_texture (Image.Private.get_texture dpi_image) with
         | Ok (_, _, dimensions) -> dimensions
         | Error (`Msg message) -> failwith message
       in
       if abs (physical_width - (2 * logical_width)) > 2
          || abs (physical_height - (2 * logical_height)) > 2
       then failwith "Font.load_dpi did not honor its explicit uniform DPI";
       Font.destroy dpi_font);
  Canvas.destroy canvas;
  Low.Window.set_size 40 30;
  Input.reset ~mouse:(10, 10);
  push_mouse_motion 13 14;
  push_mouse_motion 20 25;
  push_mouse_button Sdl.Event.mouse_button_down 20 25;
  push_mouse_button Sdl.Event.mouse_button_up 20 25;
  push_mouse_button ~button:9 Sdl.Event.mouse_button_down 20 25;
  push_mouse_button ~button:9 Sdl.Event.mouse_button_up 20 25;
  0

let update state (frame : Frame.t) =
  if frame.dt <> 0.125
     || frame.time <> (float_of_int frame.count *. 0.125)
     || frame.fps <> 8.
  then failwith "fixed sketch clock was not deterministic";
  if frame.count = 1 then begin
    if frame.size <> (40, 30)
       || Sdl.render_get_logical_size (Low.Window.get_renderer ()) <> (40, 30)
    then failwith "window resize did not update frame and renderer together";
    let resize_count =
      List.fold_left
        (fun count -> function
          | Event.WindowResized (40, 30) -> count + 1
          | _ -> count)
        0 frame.events
    in
    if resize_count <> 1 then
      failwith "one SDL resize produced duplicate or missing public events";
    if frame.mouse <> (20, 25) || frame.mouse_delta <> (10, 15) then
      failwith "SDL mouse events did not produce logical accumulated input";
    let pointer_events =
      List.filter
        (function
          | Event.MouseMoved _
          | Event.MousePressed _
          | Event.MouseReleased _ -> true
          | _ -> false)
        frame.events
    in
    match pointer_events with
    | [ Event.MouseMoved (13, 14);
        Event.MouseMoved (20, 25);
        Event.MousePressed (Input.LeftButton, (20, 25));
        Event.MouseReleased (Input.LeftButton, (20, 25)) ] -> ()
    | _ -> failwith "SDL pointer event order or coordinates changed"
  end;
  if frame.count = 2 && frame.mouse_delta <> (0, 0) then
    failwith "mouse delta was nonzero on the quiet frame";
  if frame.count = 2 then Sketch.quit ();
  state + 1

let view state (frame : Frame.t) =
  Scene.[
    clear Color.black;
    rect ~at:(2, 2) ~w:12 ~h:10 ~fill:Color.red ();
    circle ~at:frame.mouse ~radius:(4 + state) ~fill:Color.blue ();
    translate 4 4 [
      line ~from_:(0, 0) ~to_:(10, 10) ~color:Color.white ();
    ];
  ]

let () =
  if not (Sketch.is_headless ()) then
    failwith "headless smoke test was not launched with HEADLESS enabled";
  let final_state =
    Sketch.run_state
      ~config:{ Sketch.default_config with
        width = 32;
        height = 32;
        title = "headless smoke";
        domains = Some 2;
        clock = Sketch.Fixed 0.125;
      }
      ~init ~update ~view ()
  in
  if final_state <> 2 then
    failwith "functional headless sketch did not complete two frames";
  let make_temp_dir () =
    let path = Filename.temp_file "prismel-frames-" "" in
    Sys.remove path;
    Unix.mkdir path 0o700;
    path
  in
  let first_dir = make_temp_dir () in
  let second_dir = make_temp_dir () in
  let filenames =
    List.init 3 (fun index -> Printf.sprintf "shot-%06d.png" index)
  in
  let cleanup directory =
    List.iter
      (fun name ->
        let path = Filename.concat directory name in
        if Sys.file_exists path then Sys.remove path)
      filenames;
    if Sys.file_exists directory then Unix.rmdir directory
  in
  Fun.protect
    ~finally:(fun () -> cleanup first_dir; cleanup second_dir)
    (fun () ->
      let render directory =
        Sketch.export
          ~config:{ Sketch.default_config with width = 16; height = 16 }
          ~fps:10 ~prefix:"shot" ~directory ~frames:3
          (fun frame ->
            if frame.dt <> 0.1
               || frame.time <> (float_of_int frame.count *. 0.1)
            then failwith "export did not use deterministic fixed timing";
            Scene.[
              clear Color.black;
              square ~at:(frame.count, 2) ~size:4 ~fill:Color.white ();
              text ~at:(1, 8) ~size:6 "R";
            ])
      in
      render first_dir;
      render second_dir;
      List.iter
        (fun name ->
          let first = Filename.concat first_dir name in
          let second = Filename.concat second_dir name in
          if not (Sys.file_exists first) || (Unix.stat first).st_size = 0 then
            failwith "frame export did not create a non-empty PNG";
          if Digest.file first <> Digest.file second then
            failwith "repeated deterministic exports produced different PNGs")
        filenames);
  Preview.show Scene.[
    clear Color.black;
    circle ~at:(8, 8) ~radius:4 ~fill:Color.cyan ();
  ];
  if not (Preview.is_open ()) then
    failwith "REPL preview did not open a persistent session";
  Preview.stop ();
  if Preview.is_open () then failwith "REPL preview did not stop"
