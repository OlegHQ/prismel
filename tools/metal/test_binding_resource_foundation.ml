open Binding_resource_model
let () =
  if Binding_resource_manifest.count <> 100 then failwith "resource manifest drift";
  (match validate_range ~total:4096 ~alignment:256 {offset=256;length=1024} with Ok () -> () | Error e -> failwith e);
  (match validate_range ~total:4096 ~alignment:256 {offset=1;length=4} with Error _ -> () | Ok () -> failwith "alignment");
  (match validate_range ~total:max_int ~alignment:1 {offset=max_int;length=1} with Error _ -> () | Ok () -> failwith "overflow");
  (match validate_extent {width=4;height=4;depth=1} with Ok () -> () | Error e -> failwith e);
  Printf.printf "resource foundation: %d exact IDs, %d lifecycle invariants\n"
    Binding_resource_manifest.count (List.length lifecycle_invariants)
