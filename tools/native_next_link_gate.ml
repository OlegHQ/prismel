let fail fmt = Printf.ksprintf (fun text -> prerr_endline text; exit 1) fmt

let read path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      really_input_string channel (in_channel_length channel))

let contains text needle =
  let text_length = String.length text and needle_length = String.length needle in
  let rec loop index =
    index + needle_length <= text_length
    && (String.sub text index needle_length = needle || loop (index + 1))
  in
  needle_length = 0 || loop 0

let require path text needle =
  if not (contains text needle) then fail "%s: required boundary %S is absent" path needle

let legacy =
  [ "tsdl"; "sdl2"; "raster2"; "ogpu_raster2"; "wap"; "opengl" ]

let reject_legacy path text =
  List.iter
    (fun token ->
      if contains text token then
        fail "%s: native dependency boundary still mentions %s" path token)
    legacy

let () =
  match Array.to_list Sys.argv with
  | [_; prismel_path; runtime_path; metal_path; scene_path] ->
      let prismel = read prismel_path
      and runtime = read runtime_path
      and metal = read metal_path
      and scene = read scene_path in
      reject_legacy prismel_path prismel;
      reject_legacy runtime_path runtime;
      require prismel_path prismel "runtime_next_orchestrator";
      require runtime_path runtime "(libraries sdl3 metal ogpu ogpu_metal scene_execution)";
      require runtime_path runtime "(libraries runtime_next)";
      require metal_path metal "(libraries ogpu metal)";
      require scene_path scene "(libraries ogpu)";
      List.iter (fun forbidden -> if contains scene forbidden then
        fail "%s: neutral scene execution acquired forbidden dependency %s"
          scene_path forbidden) ["sdl3"; "runtime"; "metal"];
      List.iter (fun forbidden -> if contains metal forbidden then
        fail "%s: ogpu_metal acquired a platform dependency %s" metal_path forbidden)
        ["sdl3"; "runtime"];
      print_endline
        "native link gate: Prismel facade, SDL3/Metal runtime, and neutral OGPU boundaries passed"
  | _ -> fail "usage: native_next_link_gate PRISMEL_DUNE RUNTIME_DUNE OGPU_METAL_DUNE SCENE_EXECUTION_DUNE"
