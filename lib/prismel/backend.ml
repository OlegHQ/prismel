let enabled_value value =
  match String.lowercase_ascii (String.trim value) with
  | "1" | "true" | "yes" | "on" -> true
  | _ -> false

let is_headless () =
  match Sys.getenv_opt "HEADLESS" with
  | Some value -> enabled_value value
  | None -> false

let configure_environment () =
  if is_headless () then begin
    Unix.putenv "SDL_VIDEODRIVER" "dummy";
    Unix.putenv "SDL_RENDER_DRIVER" "software";
    Unix.putenv "SDL_AUDIODRIVER" "dummy"
  end
