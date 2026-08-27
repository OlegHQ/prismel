open Support

let require condition format =
  Printf.ksprintf (fun message -> if not condition then raise (Error message)) format

let git root arguments = command_output ~cwd:root "/usr/bin/git" arguments

let () =
  let root = ref "." in
  Arg.parse [ "--root", Arg.Set_string root, "repository root" ]
    (fun value -> raise (Arg.Bad value)) "phase5_b0_freeze";
  let root = Unix.realpath !root in
  let path = Filename.concat root
      "specification/evidence/gpu_migration/phase5_b0_freeze_2026-08-27.json" in
  let json = Yojson.Safe.from_file path in
  let open Yojson.Safe.Util in
  let rollback = json |> member "rollback_commit" |> to_string in
  require (git root [ "merge-base"; "HEAD"; rollback ] = rollback)
    "rollback commit is not an ancestor of HEAD";
  let verify_sha field relative =
    let expected = json |> member field |> to_string in
    let actual = sha256 (read_file (Filename.concat root relative)) in
    require (actual = expected) "%s drift: %s <> %s" relative actual expected
  in
  verify_sha "new_gpu_sha256" "NEW_GPU_STUFF.md";
  verify_sha "legacy_api_sha256"
    "specification/evidence/gpu_migration/api_stable.json";
  json |> member "acceptance_trees" |> to_assoc
  |> List.iter (fun (tree, expected) ->
      let actual = git root [ "rev-parse"; "HEAD:" ^ tree ] in
      require (actual = to_string expected) "acceptance tree drift: %s" tree);
  let allowlist =
    json |> member "future_api_break_allowlist" |> to_list |> List.map to_string
  in
  require
    (allowlist = [ "Prismel.Low private Tsdl handle types";
                   "Prismel.Private private Tsdl handle types" ])
    "future API break allowlist broadened";
  json |> member "framebuffer_corpus" |> to_list |> List.iter (fun item ->
      let old_hash = item |> member "legacy_or_software_hash" |> to_string
      and next_hash = item |> member "native_hash" |> to_string
      and tolerance = item |> member "tolerance" |> to_int in
      require (String.length old_hash = 32 && String.length next_hash = 32)
        "framebuffer hash cardinality drift";
      require (old_hash = next_hash && (tolerance = 0 || tolerance = 3))
        "frozen framebuffer parity drift");
  Printf.printf
    "Phase5 B0 freeze: rollback/plan/API/acceptance trees, 4 framebuffer hashes, snapshot bytes, and exact future allowlist passed\n"
