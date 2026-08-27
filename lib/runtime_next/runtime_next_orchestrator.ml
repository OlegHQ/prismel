type target = Native | Headless | Web

type implementation =
  | Native_runtime of Runtime_next.t
  | Headless_runtime of Runtime_next_headless.t
  | Web_runtime of Runtime_next_web.t

type t = { target : target; implementation : implementation }

type configuration = {
  target : target;
  logical_width : int;
  logical_height : int;
  drawable_width : int;
  drawable_height : int;
  wap_config : Wap.config option;
}

let target_of_string value =
  match String.lowercase_ascii (String.trim value) with
  | "native" -> Ok Native
  | "headless" -> Ok Headless
  | "web" -> Ok Web
  | invalid ->
      Error
        (Printf.sprintf
           "unknown render target %S (expected native, headless, or web)" invalid)

let enabled value =
  match String.lowercase_ascii (String.trim value) with
  | "1" | "true" | "yes" | "on" -> true
  | _ -> false

let select_with getenv =
  let explicit =
    match getenv "PRISMEL_RENDER_TARGET" with
    | Some value -> Some ("PRISMEL_RENDER_TARGET", value)
    | None ->
        Option.map
          (fun value -> "PRISMAL_RENDER_TARGET", value)
          (getenv "PRISMAL_RENDER_TARGET")
  in
  match explicit with
  | Some (name, value) ->
      Result.map_error (fun message -> name ^ ": " ^ message)
        (target_of_string value)
  | None ->
      begin
        match getenv "HEADLESS" with
        | Some value when enabled value -> Ok Headless
        | _ -> Ok Native
      end

let selected () = select_with Sys.getenv_opt

let invalid operation message =
  Error (Ogpu.Error.make operation Ogpu.Error.Invalid_argument message)

let create configuration =
  let open Result in
  let positive =
    configuration.logical_width > 0 && configuration.logical_height > 0
    && configuration.drawable_width > 0 && configuration.drawable_height > 0
  in
  if not positive then invalid "Runtime_next_orchestrator.create"
      "dimensions must be positive"
  else
    match configuration.target with
    | Native ->
          Runtime_next.create ~width:configuration.logical_width
            ~height:configuration.logical_height
          |> map (fun runtime ->
                 { target = Native; implementation = Native_runtime runtime })
    | Headless ->
        Runtime_next_headless.create
          ~logical_width:configuration.logical_width
          ~logical_height:configuration.logical_height
          ~drawable_width:configuration.drawable_width
          ~drawable_height:configuration.drawable_height
        |> map (fun runtime ->
               { target = Headless; implementation = Headless_runtime runtime })
    | Web ->
        Runtime_next_web.create ?wap_config:configuration.wap_config
          ~logical_width:configuration.logical_width
          ~logical_height:configuration.logical_height
          ~drawable_width:configuration.drawable_width
          ~drawable_height:configuration.drawable_height ()
        |> map (fun runtime ->
               { target = Web; implementation = Web_runtime runtime })

let target (value : t) = value.target

let render value draws =
  match value.implementation with
  | Native_runtime runtime -> Runtime_next.render runtime draws
  | Headless_runtime runtime -> Runtime_next_headless.render runtime draws
  | Web_runtime runtime -> Runtime_next_web.render runtime draws

let resize value ~logical_width ~logical_height ~drawable_width
    ~drawable_height =
  match value.implementation with
  | Native_runtime runtime ->
      let _ = drawable_width,drawable_height in
      Runtime_next.resize runtime ~width:logical_width ~height:logical_height
  | Headless_runtime runtime ->
      Runtime_next_headless.resize runtime ~logical_width ~logical_height
        ~drawable_width ~drawable_height
  | Web_runtime runtime ->
      Runtime_next_web.resize runtime ~logical_width ~logical_height
        ~drawable_width ~drawable_height

let capture value ~bytes_per_row =
  match value.implementation with
  | Native_runtime runtime -> Runtime_next.read_pixels runtime ~bytes_per_row
  | Headless_runtime runtime ->
      Runtime_next_headless.read_pixels runtime ~bytes_per_row
  | Web_runtime runtime -> Runtime_next_web.read_pixels runtime ~bytes_per_row

let set_text_input_regions value regions =
  match value.implementation with
  | Web_runtime runtime -> Runtime_next_web.set_text_input_regions runtime regions
  | Native_runtime _ | Headless_runtime _ -> Ok ()

let destroy value =
  match value.implementation with
  | Native_runtime runtime -> Runtime_next.destroy runtime
  | Headless_runtime runtime -> Runtime_next_headless.destroy runtime
  | Web_runtime runtime -> Runtime_next_web.destroy runtime
