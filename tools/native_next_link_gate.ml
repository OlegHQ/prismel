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

let reject_composition libraries =
  let has name = List.mem name libraries in
  if has "prismel" && has "sdl3" then
    Error "legacy prismel archive and SDL3 presenter would co-link SDL2 and SDL3"
  else Ok ()

let expect_rejected libraries =
  match reject_composition libraries with Error _ -> () | Ok () -> fail "unsafe co-link was accepted"

let expect_accepted libraries =
  match reject_composition libraries with Ok () -> () | Error text -> fail "%s" text

let () =
  match Array.to_list Sys.argv with
  | [_; prismel_path; runtime_path; metal_path; scene_path] ->
      let prismel = read prismel_path
      and runtime = read runtime_path
      and metal = read metal_path
      and scene = read scene_path in
      require prismel_path prismel "tsdl";
      require prismel_path prismel "runtime";
      if contains runtime "sdl3" then
        fail "%s: legacy runtime acquired an SDL3 dependency" runtime_path;
      require metal_path metal "(libraries ogpu metal)";
      require scene_path scene "(libraries ogpu)";
      List.iter (fun forbidden -> if contains scene forbidden then
        fail "%s: neutral scene execution acquired forbidden dependency %s"
          scene_path forbidden) ["tsdl"; "sdl3"; "runtime"; "metal"];
      if contains metal "sdl3" || contains metal "tsdl" then
        fail "%s: ogpu_metal acquired an SDL dependency" metal_path;
      expect_rejected ["prismel"; "sdl3"];
      expect_accepted ["ogpu"; "ogpu_metal"; "metal"];
      print_endline
        "native-next link gate: unsafe Prismel(SDL2)+SDL3 composition rejected; isolated foundations accepted"
  | _ -> fail "usage: native_next_link_gate PRISMEL_DUNE RUNTIME_DUNE OGPU_METAL_DUNE SCENE_EXECUTION_DUNE"
