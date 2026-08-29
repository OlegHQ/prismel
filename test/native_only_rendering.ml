let read path =
  let input = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr input) (fun () ->
    really_input_string input (in_channel_length input))

let contains text needle =
  let text_length = String.length text and needle_length = String.length needle in
  let rec search index =
    index + needle_length <= text_length
    && (String.sub text index needle_length = needle || search (index + 1))
  in
  search 0

let forbidden_rendering =
  [ "Rgba_presenter"; "create_rgba_presenter";
    "SDL_CreateRenderer"; "SDL_CreateSoftwareRenderer";
    "SDL_CreateWindowAndRenderer"; "SDL_RenderPresent";
    "SDL_RenderTexture"; "SDL_RenderGeometry"; "SDL_GL_";
    "SDL_WINDOW_OPENGL"; "SDL_WINDOW_VULKAN" ]

let forbidden_selectors =
  [ "PRISMEL_RENDER_TARGET"; "PRISMAL_RENDER_TARGET";
    "PRISMEL_HEADLESS"; "PRISMAL_HEADLESS";
    "PRISMEL_WEB"; "PRISMAL_WEB";
    "PRISMEL_TEST_RASTER2_RENDERER";
    "PRISMEL_TEST_SCENE_OGPU_RENDERER";
    "PRISMEL_RENDERER"; "PRISMEL_BACKEND"; "PRISMEL_OPENGL";
    "--renderer"; "--backend"; ("--head" ^ "less");
    ("--open" ^ "gl"); "Dynlink" ]

let source_violations path source needles =
  List.filter_map (fun needle ->
    if contains source needle then Some (path ^ ": " ^ needle) else None)
    needles

let violations paths needles =
  List.concat_map (fun path -> source_violations path (read path) needles) paths

let require path source needle =
  if not (contains source needle) then
    failwith (Printf.sprintf "%s omitted required native anchor %s" path needle)

let verify_negative_fixture () =
  match source_violations "injected-selector.ml"
      "let _ = SDL_CreateRenderer\n" forbidden_rendering with
  | [_] -> ()
  | _ -> failwith "injected renderer selector was not rejected"

let () = match Array.to_list Sys.argv with
  | [_; raw_path; api_path; interface_path; stubs_path; runtime_path;
      orchestrator_path; execution_path] ->
      let core_paths = [raw_path; api_path; interface_path; stubs_path;
        runtime_path; orchestrator_path; execution_path] in
      let found = violations core_paths
          (forbidden_rendering @ forbidden_selectors) in
      if found <> [] then
        failwith ("native-only rendering gate rejected:\n" ^
          String.concat "\n" found);
      require stubs_path (read stubs_path) "SDL_Metal_CreateView";
      require runtime_path (read runtime_path) "Ogpu_metal.Backend.create";
      require orchestrator_path (read orchestrator_path) "Runtime_next.create";
      require execution_path (read execution_path)
        "Runtime_next_orchestrator.create";
      verify_negative_fixture ();
      print_endline
        "native-only rendering gate passed (SDL3 Metal -> OGPU Metal runtime; no alternate selector)"
  | _ -> invalid_arg
      "native_only_rendering: expected SDL3 and native runtime source files"
