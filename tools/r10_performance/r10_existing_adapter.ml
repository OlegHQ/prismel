let fail message = prerr_endline ("R10 adapter: " ^ message); exit 2

let lines command arguments =
  let input = Unix.open_process_args_in command (Array.of_list (command :: arguments)) in
  let rec read result =
    match input_line input with line -> read (String.trim line :: result)
    | exception End_of_file -> List.rev result
  in
  let result = read [] in
  match Unix.close_process_in input with
  | Unix.WEXITED 0 -> result
  | _ -> fail (command ^ " failed while inspecting legacy linkage")

let library_path line =
  match String.index_opt line ' ' with
  | None -> line
  | Some index -> String.sub line 0 index

let prepare_legacy_linkage executable =
  if Sys.os_type = "Unix" && Sys.file_exists "/usr/bin/otool" then begin
    let libraries = lines "/usr/bin/otool" [ "-L"; executable ] in
    let has_sdl3 = List.exists (fun line -> String.contains line '3'
      && String.ends_with ~suffix:"libSDL3.0.dylib" (library_path line)) libraries in
    let sdl2 = List.find_map (fun line ->
      let path = library_path line in
      if String.contains path '2'
         && String.ends_with ~suffix:"libSDL2-2.0.0.dylib" path
      then Some path else None) libraries in
    match has_sdl3, sdl2 with
    | true, Some path ->
        (* The staging Prismel archive also contains dormant SDL3 bindings.
           Darwin otherwise resolves SDL2-compatible names from SDL3 first.
           Preloading the already-linked SDL2 compatibility dylib restores the
           legacy process boundary without changing either implementation. *)
        let value = match Sys.getenv_opt "DYLD_INSERT_LIBRARIES" with
          | None | Some "" -> path
          | Some existing -> path ^ ":" ^ existing
        in
        Unix.putenv "DYLD_INSERT_LIBRARIES" value
    | false, _ -> ()
    | true, None -> fail "legacy executable co-links SDL3 without a linked SDL2 compatibility dylib"
  end

let () =
  let kind = ref "" and executable = ref "" and scenario = ref ""
  and target = ref "native" and profile = ref "release" and width = ref 64
  and height = ref 64 and warmup = ref 3. and seconds = ref 30.
  and visibility = ref "visible" in
  Arg.parse [
    "--kind", Arg.Symbol (["native-next"; "legacy"], fun x -> kind := x), "adapter kind";
    "--executable", Arg.Set_string executable, "existing benchmark executable";
    "--scenario", Arg.Set_string scenario, "basic, pxui, canvas, or scene3";
    "--target", Arg.Symbol (["native"; "headless"; "web"], fun x -> target := x), "legacy target";
    "--profile", Arg.Set_string profile, "build profile recorded by child";
    "--width", Arg.Set_int width, "logical width";
    "--height", Arg.Set_int height, "logical height";
    "--warmup", Arg.Set_float warmup, "warmup seconds";
    "--seconds", Arg.Set_float seconds, "measurement seconds";
    "--visibility", Arg.Symbol (["visible"; "hidden"], fun value -> visibility := value),
      "native-next window visibility" ]
    (fun value -> fail ("unexpected argument " ^ value)) "R10 existing benchmark adapter";
  if !executable = "" || !scenario = "" || !warmup <= 0. || !seconds <= 0.
     || !width <= 0 || !height <= 0 then fail "invalid or missing arguments";
  let argv = match !kind with
    | "native-next" ->
        [| !executable; !scenario; "--visibility"; !visibility; "--warmup-seconds"; string_of_float !warmup;
           "--sample-seconds"; string_of_float !seconds;
           "--width";string_of_int!width;"--height";string_of_int!height |]
    | "legacy" ->
        prepare_legacy_linkage !executable;
        Unix.putenv "PRISMEL_RENDER_TARGET" !target;
        Unix.putenv "PRISMEL_BENCH_PROFILE" !profile;
        Unix.putenv "PRISMEL_RENDERER_BENCH_WIDTH" (string_of_int !width);
        Unix.putenv "PRISMEL_RENDERER_BENCH_HEIGHT" (string_of_int !height);
        Unix.putenv "PRISMEL_RENDERER_BENCH_WARMUP" (string_of_float !warmup);
        Unix.putenv "PRISMEL_RENDERER_BENCH_SECONDS" (string_of_float !seconds);
        if !target = "web" then Unix.putenv "PRISMEL_WEB_PORT" "0";
        [| !executable; !scenario |]
    | _ -> fail "--kind is required" in
  Unix.execv !executable argv
