let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)

let () =
  let before = get (Metal.Release_queue.stats ()) in
  let driver, _control = Ogpu_metal.Backend.create () in
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
       ignore (get (Metal.Release_queue.drain ()));
       let after = get (Metal.Release_queue.stats ()) in
       if after.live_handles <> before.live_handles then
         failwith "Metal backend leaked handles";
       print_endline "OGPU conformance (Metal): capabilities, buffer round trip, submission, lifetime, zero handles")
