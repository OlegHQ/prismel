(* Launch the built executable directly: bootstrapping through [dune exec]
   would acquire Dune's lock before we can queue behind another agent. *)
let rec workspace path =
  if Sys.file_exists (Filename.concat path "dune-project") then path
  else
    let parent = Filename.dirname path in
    if parent = path then failwith "check: run inside the Rays workspace"
    else workspace parent

let run program arguments =
  let pid = Unix.create_process program (Array.of_list (program :: arguments))
      Unix.stdin Unix.stdout Unix.stderr in
  let rec wait () =
    try snd (Unix.waitpid [] pid)
    with Unix.Unix_error (Unix.EINTR, _, _) -> wait () in
  match wait () with
  | Unix.WEXITED code -> code
  | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> 1

let () =
  Sys.chdir (workspace (Sys.getcwd ()));
  let arguments = Array.to_list Sys.argv |> List.tl in
  let ship = arguments = ["--ship"] in
  let arguments = if ship then ["@all"; "@runtest"; "@smoke"]
    else if arguments = [] then ["@runtest"] else arguments in
  (* Keep this inode outside _build and never unlink it: queued processes
     must keep locking the same file even across [dune clean]. *)
  let lock = Unix.openfile ".rays-check.lock"
      [Unix.O_CREAT; Unix.O_RDWR; Unix.O_CLOEXEC] 0o600 in
  let code = Fun.protect ~finally:(fun () -> Unix.close lock) (fun () ->
    (try Unix.lockf lock Unix.F_TLOCK 0 with
     | Unix.Unix_error ((Unix.EACCES | Unix.EAGAIN), _, _) ->
         prerr_endline "check: waiting for another agent's validation";
         Unix.lockf lock Unix.F_LOCK 0);
    let code = run "dune" ("build" :: arguments) in
    if code = 0 && ship then run "git" ["diff"; "--check"] else code) in
  exit code
