open Runtime_next_input

let button = function
  | 1 -> Some Left
  | 2 -> Some Middle
  | 3 -> Some Right
  | 4 -> Some X1
  | 5 -> Some X2
  | _ -> None

let key_name ~scancode keycode =
  if keycode>=32 && keycode<=126 then
    String.make 1(Char.lowercase_ascii(Char.chr keycode))
  else match scancode with
    |40->"Enter"|41->"Escape"|42->"Backspace"|43->"Tab"|44->"Space"
    |58->"F1"|59->"F2"|60->"F3"|61->"F4"|62->"F5"|63->"F6"
    |64->"F7"|65->"F8"|66->"F9"|67->"F10"|68->"F11"|69->"F12"
    |73->"Insert"|74->"Home"|75->"PageUp"|76->"Delete"|77->"End"
    |78->"PageDown"|79->"ArrowRight"|80->"ArrowLeft"|81->"ArrowDown"
    |82->"ArrowUp"|224|228->"Control"|225|229->"Shift"
    |226|230->"Alt"|227|231->"Meta"
    |_->Printf.sprintf"Unknown(%d)"keycode

let modifiers bits =
  let add mask value values=if bits land mask<>0 then value::values else values in
  []|>add 0x8000 Scroll_lock|>add 0x2000 Caps_lock|>add 0x1000 Num_lock
  |>add 0x0c00 Meta|>add 0x0300 Alt|>add 0x00c0 Control|>add 0x0003 Shift

let translate = function
  | Sdl3.Event.Mouse_motion { x; y; _ } -> Some (Pointer_moved (x, y))
  | Mouse_button { button = raw_button; down; x; y; _ } ->
      Option.map (fun value ->
          if down then Pointer_pressed (value, x, y)
          else Pointer_released (value, x, y)) (button raw_button)
  | Mouse_wheel { x; y; direction; _ } ->
      let sign = match direction with Sdl3.Event.Flipped -> -1. | _ -> 1. in
      Some (Wheel (sign *. x, sign *. y))
  | Key { scancode;keycode;modifiers=mods;down;repeat;_ } ->
      let event={key=key_name~scancode keycode;modifiers=modifiers mods;repeat}in
      Some(if down then Key_pressed event else Key_released event)
  | Text_input { text; _ } -> Some (Text_input text)
  | Text_editing { text; start; length; _ } ->
      Some (Text_editing { text; start; length })
  | Window { change = Resized (width, height); _ } ->
      Some (Runtime_next_input.Resized (width, height))
  | Window { change = Focus_lost; _ } -> Some Runtime_next_input.Focus_lost
  | Window { change = Focus_gained; _ } -> Some Runtime_next_input.Focus_gained
  | Window { change = Shown; _ } -> Some(Visibility_changed true)
  | Window { change = Hidden; _ } -> Some(Visibility_changed false)
  | Sdl3.Event.Quit _ -> Some Runtime_next_input.Quit
  | Drop { change = File _; _ } -> None
  | _ -> None

let push value event =
  match event with
  |Sdl3.Event.Drop{change=File path;_}->Runtime_next_input.push_file_path value path
  |_->match translate event with None -> Ok () | Some event -> Runtime_next_input.push value event
