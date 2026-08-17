open Prismel

let fail message = raise (Failure message)

let input_u32 channel =
  let a = input_byte channel and b = input_byte channel
  and c = input_byte channel and d = input_byte channel in
  (((a lsl 8) lor b) lsl 16) lor ((c lsl 8) lor d)

let png_size filename =
  let channel = open_in_bin filename in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
    let signature = really_input_string channel 8 in
    if signature <> "\137PNG\r\n\026\n" then fail "Render2 did not save a PNG";
    ignore (input_u32 channel);
    if really_input_string channel 4 <> "IHDR" then
      fail "Render2 PNG has no IHDR header";
    let width = input_u32 channel in
    let height = input_u32 channel in
    width, height)

let () =
  let filename = Filename.temp_file "prismel-render2-" ".png" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists filename then Sys.remove filename)
    (fun () ->
      let config = { Sketch.default_config with width = 32; height = 24;
        title = "render2 smoke"; fps = None } in
      ignore (Sketch.run_state ~config
        ~init:(fun _frame ->
          let camera = Easy_camera2.create () in
          let world = Scene.[
            rect ~at:(-8, -6) ~w:16 ~h:12 ~fill:Color.red ()
          ] in
          (match Render2.save_png ~logical_width:32 ~logical_height:24
              ~factor:2 ~background:Color.black ~camera world filename with
           | Ok () -> ()
           | Error message -> fail message);
          Sketch.quit ();
          ())
        ~update:(fun () _frame -> ())
        ~view:(fun () _frame -> Scene.[clear Color.black]) ());
      let width, height = png_size filename in
      if (width, height) <> (64, 48) then
        fail (Printf.sprintf
          "Render2 factor produced %dx%d instead of 64x48" width height))
