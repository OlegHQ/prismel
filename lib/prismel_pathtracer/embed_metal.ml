let () =
  let channel = open_in_bin Sys.argv.(1) in
  let source =
    Fun.protect
      ~finally:(fun () -> close_in channel)
      (fun () -> really_input_string channel (in_channel_length channel))
  in
  Printf.printf "let source = %S\n" source
