type t = Native | Headless | Web

let enabled_value value =
  match String.lowercase_ascii (String.trim value) with
  | "1" | "true" | "yes" | "on" -> true
  | _ -> false

let of_string value =
  match String.lowercase_ascii (String.trim value) with
  | "native" | "desktop" | "sdl" | "opengl" -> Ok Native
  | "headless" | "software" -> Ok Headless
  | "web" | "browser" | "webgl" -> Ok Web
  | value ->
      Error
        (Printf.sprintf
           "unknown render target %S (expected native, headless, or web)" value)

let first_environment getenv names =
  List.find_map (fun name -> Option.map (fun value -> name, value)
    (getenv name)) names

let select_with getenv =
  match first_environment getenv
      ["PRISMEL_RENDER_TARGET"; "PRISMAL_RENDER_TARGET"] with
  | Some (name, value) ->
      Result.map_error
        (fun message -> name ^ ": " ^ message)
        (of_string value)
  | None ->
      (match first_environment getenv ["PRISMEL_WEB"; "PRISMAL_WEB"] with
       | Some (_, value) when enabled_value value -> Ok Web
       | _ ->
           match first_environment getenv
               ["PRISMEL_HEADLESS"; "PRISMAL_HEADLESS"; "HEADLESS"] with
           | Some (_, value) when enabled_value value -> Ok Headless
           | _ -> Ok Native)

let selected () = select_with Sys.getenv_opt

let get () =
  match selected () with
  | Ok target -> target
  | Error message -> invalid_arg ("Prismel runtime target: " ^ message)

let is_headless () = get () = Headless
let is_web () = get () = Web
let is_displayless () = match get () with Native -> false | Headless | Web -> true

let configure_sdl_environment = function
  | Native -> ()
  | Headless | Web ->
      Unix.putenv "SDL_VIDEODRIVER" "dummy";
      Unix.putenv "SDL_RENDER_DRIVER" "software";
      Unix.putenv "SDL_AUDIODRIVER" "dummy"
