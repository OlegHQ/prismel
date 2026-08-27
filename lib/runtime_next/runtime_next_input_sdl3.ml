open Runtime_next_input

let button = function
  | 1 -> Some Left
  | 2 -> Some Middle
  | 3 -> Some Right
  | 4 -> Some X1
  | 5 -> Some X2
  | _ -> None

let translate = function
  | Sdl3.Event.Mouse_motion { x; y; _ } -> Some (Pointer_moved (x, y))
  | Mouse_button { button = raw_button; down; x; y; _ } ->
      Option.map (fun value ->
          if down then Pointer_pressed (value, x, y)
          else Pointer_released (value, x, y)) (button raw_button)
  | Mouse_wheel { x; y; direction; _ } ->
      let sign = match direction with Sdl3.Event.Flipped -> -1. | _ -> 1. in
      Some (Wheel (sign *. x, sign *. y))
  | Key { keycode; down; _ } ->
      let key = string_of_int keycode in
      Some (if down then Key_pressed key else Key_released key)
  | Text_input { text; _ } -> Some (Text_input text)
  | Text_editing { text; start; length; _ } ->
      Some (Text_editing { text; start; length })
  | Window { change = Resized (width, height); _ } ->
      Some (Runtime_next_input.Resized (width, height))
  | Window { change = Focus_lost; _ } -> Some Runtime_next_input.Focus_lost
  | Drop { change = File path; _ } ->
      Some (File_dropped { name = path; contents = None })
  | _ -> None

let push value event =
  match translate event with None -> Ok () | Some event -> Runtime_next_input.push value event
