let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Metal.pp_error error)

let () =
  let metallib = if Array.length Sys.argv < 2 then None else
    let channel = open_in_bin Sys.argv.(1) in
    Some (Fun.protect ~finally:(fun () -> close_in channel)
      (fun () -> Bytes.of_string (really_input_string channel (in_channel_length channel)))) in
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
       Ogpu_conformance.Conformance.run ?metallib driver;
       if live_handles () <> before.live_handles then
         failwith "Metal backend leaked handles";
       print_endline "OGPU conformance (Metal): capabilities, buffer/texture round trip, exact compute, library constants, encoders, blit, ray-query hits, refit, bounding boxes with intersection tables, curves or their typed rejection, motion primitives and instances, user-id masks, compaction and copy, visible tables, aliasing heaps with fences, residency sets, timeline events, stage-boundary timestamps, mesh and tile pipelines, dynamic libraries, binary archives, sparse tile mapping, MetalFX upscaling, lifetime, zero handles")
