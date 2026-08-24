let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected MTL4CommandQueue rejection"

let () =
  let open Binding_metal4_command_queue_safe_package in
  validate_handoff ();
  error (create ~available:false ~device:7);
  let queue = ok (create ~available:true ~device:7) in
  let resource token = { token; device = 7; destroyed = false } in
  let source = { resource = resource 1; length = 128 } in
  let destination = { resource = resource 2; length = 64 } in
  ignore (ok (copy_buffer_mappings queue ~source ~destination
    [ { source_offset = 16; destination_offset = 0; length = 32 } ]));
  error (copy_buffer_mappings queue ~source ~destination
    [ { source_offset = 100; destination_offset = 0; length = 32 } ]);
  let texture token = { resource = resource token; width = 64; height = 32; levels = 4; slices = 2 } in
  ignore (ok (copy_texture_mappings queue ~source:(texture 3) ~destination:(texture 4)
    [ { source_level = 1; source_slice = 0; x = 0; y = 0; width = 16; height = 8
      ; destination_level = 1; destination_slice = 1 } ]));
  error (copy_texture_mappings queue ~source:(texture 3) ~destination:(texture 4)
    [ { source_level = 4; source_slice = 0; x = 0; y = 0; width = 1; height = 1
      ; destination_level = 0; destination_slice = 0 } ]);
  ignore (ok (add_residency_set queue (resource 5)));
  ignore (ok (signal_drawable queue (resource 6)));
  ignore (ok (wait_for_drawable queue (resource 7)));
  ignore (ok (wait_for_event queue (resource 8) ~value:Int64.min_int));
  error (wait_for_event queue { (resource 8) with device = 9 } ~value:9L);
  if List.length (retained_tokens queue) <> 8 then failwith "MTL4 queue retained graph";
  complete queue;
  if retained_tokens queue <> [ 5 ] then failwith "completion did not release synchronization graph";
  destroy queue; destroy queue;
  error (signal_drawable queue (resource 6));
  Printf.printf
    "MTL4CommandQueue safe package: callable6 metadata2 excluded; availability/sparse/sync/residency lifetime passed\n%!"
