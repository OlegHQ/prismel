let () =
  let driver, control = Ogpu.Backend_mock.create () in
  Ogpu_conformance.Conformance.run driver;
  if Ogpu.Backend_mock.live_counts control <> (0, 0, 0, 0, 0) then
    failwith "mock backend leaked handles";
  print_endline "OGPU conformance (mock): capabilities, buffer round trip, submission, lifetime, zero handles"
