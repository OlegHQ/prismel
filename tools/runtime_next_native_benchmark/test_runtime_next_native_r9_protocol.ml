open Yojson.Safe

let fail format = Printf.ksprintf failwith format

let replace name value = function
  | `Assoc fields -> `Assoc ((name, value) :: List.remove_assoc name fields)
  | _ -> fail "expected object"

let run validator value =
  let path = Filename.temp_file "runtime-next-r9-" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      Yojson.Safe.to_file path value;
      let validator = Unix.realpath validator in
      let arguments = [| validator; "--validate"; path |] in
      let pid = Unix.create_process validator arguments Unix.stdin Unix.stdout Unix.stderr in
      match snd (Unix.waitpid [] pid) with Unix.WEXITED code -> code | _ -> 255)

let () =
  if Array.length Sys.argv <> 2 then fail "validator executable required";
  let commit = String.make 40 'a' in
  let source = `Assoc [ "commit", `String commit; "clean", `Bool true ] in
  let valid = `Assoc
    [ "backend", `String "real-m1-runtime-next-metal"; "profile", `String "release"
    ; "protocol_r9_requested", `Bool true; "camera_only_changes", `Bool true
    ; "sample_frames", `Int 600; "source_before", source; "source_after", source
    ; "source_stable_clean", `Bool true; "prepared_upload_bytes", `String "4096"
    ; "measurement_upload_bytes", `String "0"; "native_buffer_creates", `Int 0
    ; "native_buffer_create_bytes", `String "0"; "native_buffer_writes", `Int 0
    ; "native_buffer_write_bytes", `String "0"; "native_mesh_buffer_creates", `Int 0
    ; "native_mesh_buffer_create_bytes", `String "0"; "native_mesh_buffer_writes", `Int 0
    ; "native_mesh_buffer_write_bytes", `String "0"; "pieces", `Int 12
    ; "draws", `Int 7200; "passes", `Int 600; "backend_calls", `Int 600
    ; "cache_entries", `Int 12 ] in
  let validator = Sys.argv.(1) in
  if run validator valid <> 0 then fail "valid R9 report was rejected";
  [ replace "measurement_upload_bytes" (`String "1") valid
  ; replace "native_mesh_buffer_write_bytes" (`String "208") valid
  ; replace "draws" (`Int 7199) valid
  ; replace "passes" (`Int 599) valid
  ; replace "cache_entries" (`Int 65) valid
  ; replace "source_stable_clean" (`Bool false) valid ]
  |> List.iteri (fun index invalid ->
    if run validator invalid = 0 then fail "invalid R9 report %d was accepted" index)
