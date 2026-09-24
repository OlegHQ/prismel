let ok = function Ok value -> value | Error error -> failwith error
let error = function Error _ -> () | Ok _ -> failwith "expected BinaryArchive rejection"

let () =
  let open Binding_binary_archive_safe_package in
  validate_handoff ();
  let archive = create ~device:7 in
  let owned token = { token; device = 7; destroyed = false } in
  let descriptor token kind = { owned = owned token; kind } in
  ignore (ok (add_function archive ~descriptor:(descriptor 1 Function) ~library:(owned 2) ~native_result:(Ok ())));
  ignore (ok (add_library archive ~descriptor:(descriptor 3 Stitched_library) ~native_result:(Ok ())));
  ignore (ok (add_mesh_pipeline archive ~descriptor:(descriptor 4 Mesh_pipeline) ~native_result:(Ok ())));
  ignore (ok (add_render_pipeline archive ~descriptor:(descriptor 5 Render_pipeline) ~native_result:(Ok ())));
  ignore (ok (add_tile_pipeline archive ~descriptor:(descriptor 6 Tile_pipeline) ~native_result:(Ok ())));
  if retained_tokens archive <> [ 1; 2; 3; 4; 5; 6 ] then failwith "binary archive retained graph";
  let before = retained_tokens archive in
  error (add_function archive ~descriptor:(descriptor 7 Render_pipeline) ~library:(owned 8) ~native_result:(Ok ()));
  error (add_function archive ~descriptor:(descriptor 7 Function) ~library:{ (owned 8) with device = 9 } ~native_result:(Ok ()));
  error (add_library archive ~descriptor:{ (descriptor 7 Stitched_library) with owned = { (owned 7) with destroyed = true } }
    ~native_result:(Ok ()));
  error (add_tile_pipeline archive ~descriptor:(descriptor 7 Tile_pipeline) ~native_result:(Error "native archive failure"));
  if retained_tokens archive <> before then failwith "binary archive error was not atomic";
  destroy archive; destroy archive;
  if retained_tokens archive <> [] then failwith "archive destroy release";
  error (add_render_pipeline archive ~descriptor:(descriptor 8 Render_pipeline) ~native_result:(Ok ()));
  Printf.printf
    "BinaryArchive5 reconciled: callable5 metadata0; descriptor/library/device/error/retention atomicity passed\n%!"
