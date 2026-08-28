type t = Native

let enabled_value value =
  match String.lowercase_ascii (String.trim value) with
  | "1" | "true" | "yes" | "on" -> true
  | _ -> false

let of_string value =
  match String.lowercase_ascii (String.trim value) with
  | "native" | "desktop" | "sdl" | "opengl" -> Ok Native
  | "headless" | "software" -> Error "headless render target has been removed"
  | "web" | "browser" | "webgl" -> Error "web render target has been removed"
  | value ->
      Error
        (Printf.sprintf
           "unknown render target %S (expected native)" value)

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
       | Some (_, value) when enabled_value value -> Error "web render target has been removed"
       | _ ->
           match first_environment getenv
               ["PRISMEL_HEADLESS"; "PRISMAL_HEADLESS"; "HEADLESS"] with
           | Some (_, value) when enabled_value value ->
               Error "headless render target has been removed"
           | _ -> Ok Native)

let selected () = select_with Sys.getenv_opt

let get () =
  match selected () with
  | Ok target -> target
  | Error message -> invalid_arg ("Prismel runtime target: " ^ message)

let is_displayless () = false

let configure_sdl_environment = function
  | Native -> ()
