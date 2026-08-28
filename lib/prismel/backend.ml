let current : Runtime.t option ref = ref None

let is_headless = Runtime.is_headless
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
      Runtime.stop runtime

let present renderer ~logical_width ~logical_height =
  let runtime = get () in
  Runtime.present runtime renderer ~logical_width ~logical_height
