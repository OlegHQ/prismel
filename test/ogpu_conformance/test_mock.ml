let () =
  let driver, live_handles = Ogpu.Impl.create_driver () in
  Ogpu_conformance.Conformance.run driver;
  if live_handles () <> 0 then
    failwith "mock backend leaked handles";
  print_endline "OGPU conformance (mock): capabilities, buffer/texture round trip, typed compute rejection, lifetime, zero handles"
