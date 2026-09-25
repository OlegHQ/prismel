let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)

let () =
  let before = get (Metal.Release_queue.stats ()) in
  let driver, live_handles = Ogpu.Impl.create_driver () in
  (match driver.Ogpu.Backend.create_device () with
   | Error { Ogpu.Error.kind = No_adapter; _ } ->
       print_endline "OGPU conformance (Metal): skipped (no device)"
   | Error error -> failwith (Ogpu.Error.to_string error)
   | Ok raw ->
       (* The probe owns a device; release it before the shared run. *)
       (match raw.destroy_device () with
        | Ok () -> ()
        | Error error -> failwith (Ogpu.Error.to_string error));
       Ogpu_conformance.Conformance.run driver;
       if live_handles () <> before.live_handles then
         failwith "Metal backend leaked handles";
       print_endline "OGPU conformance (Metal): capabilities, buffer/texture round trip, submission, lifetime, zero handles")
