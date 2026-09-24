let fail format = Printf.ksprintf failwith format

let replace name value = function
  | `Assoc fields -> `Assoc ((name, value) :: List.remove_assoc name fields)
  | _ -> fail "expected evidence object"

let run ~validator ~root evidence =
  let path = Filename.temp_file "metal-ffi-evidence-" ".json" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () ->
      Yojson.Safe.to_file path evidence;
      let validator = Unix.realpath validator in
      let arguments =
        [| validator; "--root"; root; "--evidence"; path |]
      in
      let process = Unix.create_process validator arguments Unix.stdin Unix.stdout Unix.stderr in
      match snd (Unix.waitpid [] process) with
      | Unix.WEXITED code -> code
      | Unix.WSIGNALED signal -> 128 + signal
      | Unix.WSTOPPED signal -> 128 + signal)

let () =
  if Array.length Sys.argv <> 4 then
    fail "usage: test_validate_ffi_evidence VALIDATOR ROOT BASELINE";
  let validator = Sys.argv.(1) in
  let root = Sys.argv.(2) in
  let baseline = Yojson.Safe.from_file Sys.argv.(3) in
  let commit = Yojson.Safe.Util.(baseline |> member "source_commit" |> to_string) in
  let valid =
    baseline
    |> replace "schema" (`Int 2)
    |> replace "source_dirty" (`Bool false)
    |> replace "source_commit_after" (`String commit)
    |> replace "source_dirty_after" (`Bool false)
  in
  if run ~validator ~root valid <> 0 then fail "valid schema-2 evidence failed";
  let changed = replace "source_commit_after" (`String (String.make 40 '0')) valid in
  if run ~validator ~root changed = 0 then fail "changed commit was accepted";
  let dirty = replace "source_dirty_after" (`Bool true) valid in
  if run ~validator ~root dirty = 0 then fail "dirty postflight was accepted"
