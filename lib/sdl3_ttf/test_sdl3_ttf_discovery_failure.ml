open Sdl3_ttf

let fail message = failwith ("SDL3_ttf discovery-failure test: " ^ message)

let () =
  match Font.system_path () with
  | Error { kind = Font_not_found; message; _ } when message <> "" ->
      print_endline "SDL3_ttf typed system-font discovery failure passed"
  | Ok path -> fail ("invalid PRISMEL_UI_FONT resolved to " ^ path)
  | Error _ -> fail "invalid PRISMEL_UI_FONT returned the wrong error"
