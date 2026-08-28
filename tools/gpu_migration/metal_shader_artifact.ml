let fail format = Printf.ksprintf (fun text -> prerr_endline text; exit 2) format
let output program arguments =
  let input = Unix.open_process_args_in program (Array.of_list (program :: arguments)) in
  let buffer = Buffer.create 128 in
  (try while true do Buffer.add_string buffer (input_line input); Buffer.add_char buffer '\n' done with End_of_file -> ());
  match Unix.close_process_in input with Unix.WEXITED 0 -> String.trim (Buffer.contents buffer) | _ -> fail "command failed: %s" program
let run program arguments =
  let pid = Unix.create_process program (Array.of_list (program :: arguments)) Unix.stdin Unix.stdout Unix.stderr in
  match snd (Unix.waitpid [] pid) with Unix.WEXITED 0 -> () | _ -> fail "command failed: %s" program
let xcrun arguments = output "xcrun" arguments
let required name = function Some value -> value | None -> fail "missing %s" name
let verify_provenance ~source ~library ~metadata =
  let fields =
    In_channel.with_open_bin metadata (fun channel ->
      In_channel.input_lines channel
      |> List.filter_map (fun line ->
        match String.split_on_char '=' line with
        | [ key; value ] -> Some (key, value)
        | _ -> None))
  in
  let require_field name value =
    match List.assoc_opt name fields with
    | Some actual when actual = value -> ()
    | _ -> fail "offline artifact provenance mismatch: %s" name
  in
  require_field "version" "1";
  require_field "source_hash" (Digest.to_hex (Digest.file source));
  require_field "artifact_hash" (Digest.to_hex (Digest.file library));
  require_field "target" "air64-apple-macosx";
  if (Unix.stat library).Unix.st_size = 0 then
    fail "offline artifact provenance mismatch: empty metallib"
let () =
  let source = ref None and air = ref None and library = ref None and metadata = ref None
  and deployment = ref "13.0" and temporary = ref false in
  Arg.parse
    [ "--source", Arg.String (fun x -> source := Some x), "MSL source";
      "--air", Arg.String (fun x -> air := Some x), "AIR output";
      "--metallib", Arg.String (fun x -> library := Some x), "metallib output";
      "--metadata", Arg.String (fun x -> metadata := Some x), "metadata output";
      "--deployment", Arg.Set_string deployment, "macOS deployment floor";
      "--temporary", Arg.Set temporary,
        "compile and validate a temporary offline artifact" ]
    ignore "metal_shader_artifact";
  let source = required "--source" !source in
  let air, library, metadata, cleanup =
    if !temporary then begin
      if Option.is_some !air || Option.is_some !library || Option.is_some !metadata
      then fail "--temporary cannot be combined with output paths";
      let air = Filename.temp_file "prismel-offline-" ".air"
      and library = Filename.temp_file "prismel-offline-" ".metallib"
      and metadata = Filename.temp_file "prismel-offline-" ".metadata" in
      air, library, metadata,
      (fun () -> List.iter (fun path -> try Sys.remove path with Sys_error _ -> ())
        [ air; library; metadata ])
    end else
      required "--air" !air, required "--metallib" !library,
      required "--metadata" !metadata, Fun.id
  in
  Fun.protect ~finally:cleanup (fun () ->
    let metal = xcrun [ "-f"; "metal" ]
    and metallib = xcrun [ "-f"; "metallib" ]
    and sdk = xcrun [ "--sdk"; "macosx"; "--show-sdk-version" ] in
    let compiler = output metal [ "--version" ] in
    let flags = [ "-c"; source; "-o"; air; "-target"; "air64-apple-macosx";
                  "-mmacosx-version-min=" ^ !deployment ] in
    run metal flags;
    run metallib [ air; "-o"; library ];
    let channel = open_out_bin metadata in
    Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
      Printf.fprintf channel
        "version=1\nsource_hash=%s\nartifact_hash=%s\ncompiler=%s\nsdk=%s\ntarget=air64-apple-macosx\ndeployment=%s\nflags=%s\n"
        (Digest.to_hex (Digest.file source)) (Digest.to_hex (Digest.file library))
        (String.map (fun c -> if c = '\n' || c = '\r' then ' ' else c) compiler)
        sdk !deployment (String.concat " " flags));
    verify_provenance ~source ~library ~metadata)
