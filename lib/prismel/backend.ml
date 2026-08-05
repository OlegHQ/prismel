let current : Runtime.t option ref = ref None
let pending_text_input_regions = ref []

let is_headless = Runtime.is_headless
let is_web = Runtime.is_web
let is_displayless = Runtime.is_displayless

let start ~width ~height ~title ~resizable =
  match !current with
  | Some _ -> Error "Prismel runtime is already initialized"
  | None ->
      Result.map
        (fun runtime -> current := Some runtime; runtime)
        (Runtime.start ~width ~height ~title ~resizable)

let get () =
  match !current with
  | Some runtime -> runtime
  | None -> invalid_arg "Prismel runtime is not initialized"

let stop () =
  match !current with
  | None -> ()
  | Some runtime ->
      current := None;
      pending_text_input_regions := [];
      Runtime.stop runtime

let present renderer ~logical_width ~logical_height =
  let runtime = get () in
  let regions =
    List.rev !pending_text_input_regions
    |> List.map (fun (x, y, width, height, focused) ->
      { Runtime.x; y; width; height; focused })
  in
  pending_text_input_regions := [];
  Runtime.set_web_text_input_regions runtime regions;
  Runtime.present runtime renderer ~logical_width ~logical_height

let drain_web_events () =
  match !current with
  | None -> []
  | Some runtime -> Runtime.drain_web_events runtime

let web_url () =
  match !current with
  | None -> None
  | Some runtime -> Runtime.web_url runtime

let web_drawable_size ~logical_width ~logical_height =
  match !current with
  | None -> logical_width, logical_height
  | Some runtime ->
      Runtime.web_drawable_size runtime ~logical_width ~logical_height

let register_web_file ?content_type path =
  match !current with
  | None -> None
  | Some runtime -> Runtime.register_web_file runtime ?content_type path

let register_web_bytes ?content_type bytes =
  match !current with
  | None -> None
  | Some runtime -> Runtime.register_web_bytes runtime ?content_type bytes

let remove_web_asset id =
  Option.iter (fun runtime -> Runtime.remove_web_asset runtime id) !current

let send_web_audio command =
  Option.iter (fun runtime -> Runtime.send_web_audio runtime command) !current

let download_web_frame ~filename =
  match !current with
  | None -> Error "Prismel runtime is not initialized"
  | Some runtime -> Runtime.download_web_frame runtime ~filename

let add_web_text_input_region ~x ~y ~width ~height ~focused =
  if is_web () && width > 0 && height > 0 then
    pending_text_input_regions :=
      (x, y, width, height, focused) :: !pending_text_input_regions
