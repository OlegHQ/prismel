open Prismel

let fail message = raise (Failure message)

let () =
  let filename = Filename.temp_file "prismel-render3-" ".png" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists filename then Sys.remove filename)
    (fun () ->
      let camera = Camera.perspective ~at:(Vec3.create 3. 2. 5.)
          ~target:Vec3.zero () in
      let scene = Scene3.create ~lights:[
        Light.directional ~direction:(Vec3.create (-1.) (-1.) (-1.)) ()
      ] [Scene3.box ~width:2. ~height:2. ~depth:2. ()] in
      (match Render3.save_png ~width:96 ~height:64
          ~background:(Color.hex_exn "#111827") ~camera scene filename with
       | Ok () -> ()
       | Error message -> fail message);
      let channel = open_in_bin filename in
      let signature = really_input_string channel 8 in
      close_in channel;
      if signature <> "\137PNG\r\n\026\n" then
        fail "Render3 did not save a PNG")
