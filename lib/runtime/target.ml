type t = Native

let of_string value =
  match String.lowercase_ascii (String.trim value) with
  | "native" -> Ok Native
  | value ->
      Error
        (Printf.sprintf
           "unknown render target %S (expected native)" value)

(* Target selection was a compatibility seam for the retired SDL2 renderer.
   The native Metal runtime has exactly one target; environment variables no
   longer influence initialization.  Retain the private-shaped helper only for
   callers that construct their runtime through the old facade. *)
let select_with _getenv = Ok Native

let selected () = select_with Sys.getenv_opt

let get () =
  match selected () with
  | Ok target -> target
  | Error message -> invalid_arg ("Prismel runtime target: " ^ message)

let is_displayless () = false

let configure_sdl_environment = function
  | Native -> ()
