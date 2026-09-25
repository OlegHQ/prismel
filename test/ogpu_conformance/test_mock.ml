let () =
  let metallib = if Array.length Sys.argv < 2 then Bytes.of_string "compiled fixture" else
    let channel = open_in_bin Sys.argv.(1) in
    Fun.protect ~finally:(fun () -> close_in channel)
      (fun () -> Bytes.of_string (really_input_string channel (in_channel_length channel))) in
  let driver, live_handles = Ogpu.Impl.create_driver () in
  Ogpu_conformance.Conformance.run ~metallib driver;
  if live_handles () <> 0 then
    failwith "mock backend leaked handles";
  print_endline "OGPU conformance (mock): capabilities, buffer/texture round trip, typed source/compiled compute rejection, lifetime, zero handles"
