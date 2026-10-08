let append path line =
  let fd = Unix.openfile path [Unix.O_CREAT; Unix.O_WRONLY; Unix.O_APPEND] 0o600 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
    let line = line ^ "\n" in
    assert (Unix.write_substring fd line 0 (String.length line) = String.length line))

let rec remove path =
  if Sys.is_directory path then begin
    Array.iter (fun name -> remove (Filename.concat path name)) (Sys.readdir path);
    Unix.rmdir path
  end else Sys.remove path

let () =
  match Filename.basename Sys.argv.(0) with
  | "dune" | "git" as program ->
      let log = Sys.getenv "RAYS_CHECK_TEST_LOG" in
      let arguments = Array.to_list Sys.argv |> List.tl |> String.concat " " in
      append log (program ^ " start " ^ arguments);
      Unix.sleepf 0.1;
      append log (program ^ " end " ^ arguments);
      exit (if Array.mem "--fail" Sys.argv then 23 else 0)
  | _ ->
      let checker = Unix.realpath Sys.argv.(1)
      and executable = Unix.realpath Sys.executable_name in
      let root = Filename.temp_dir "rays-check-test" "" in
      Fun.protect ~finally:(fun () -> Sys.chdir "/"; remove root) (fun () ->
        Out_channel.with_open_text (Filename.concat root "dune-project") (fun _ -> ());
        let bin = Filename.concat root "bin" in
        Unix.mkdir bin 0o700;
        List.iter (fun name -> Unix.symlink executable (Filename.concat bin name))
          ["dune"; "git"];
        let log = Filename.concat root "log" in
        Unix.putenv "PATH" bin;
        Unix.putenv "RAYS_CHECK_TEST_LOG" log;
        Sys.chdir bin; (* requests from a subdirectory share the workspace lock *)
        let launch arguments = Unix.create_process checker
            (Array.of_list (checker :: arguments)) Unix.stdin Unix.stdout Unix.stderr in
        let success pid = assert (snd (Unix.waitpid [] pid) = Unix.WEXITED 0) in
        let one = launch [] in
        let two = launch [] in
        success one; success two;
        let lines () = In_channel.with_open_text log In_channel.input_lines in
        assert (lines () = ["dune start build --root . @runtest"; "dune end build --root . @runtest";
          "dune start build --root . @runtest"; "dune end build --root . @runtest"]);
        let failure = launch ["@check"; "--fail"] in
        assert (snd (Unix.waitpid [] failure) = Unix.WEXITED 23);
        success (launch ["--ship"]);
        assert (List.rev (lines ()) |> List.take 4
          = ["git end diff --check"; "git start diff --check";
             "dune end build --root . @all @runtest @smoke";
             "dune start build --root . @all @runtest @smoke"]);
        print_endline "check: concurrent requests queue; arguments and failures propagate; shipping checks run")
