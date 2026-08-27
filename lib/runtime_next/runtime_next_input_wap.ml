open Runtime_next_input

let button = function
  | Wap.Left -> Left
  | Middle -> Middle
  | Right -> Right
  | X1 -> X1
  | X2 -> X2

let translate = function
  | Wap.Pointer_moved (x, y) -> Some (Pointer_moved (float x, float y))
  | Pointer_pressed (value, x, y) ->
      Some (Pointer_pressed (button value, float x, float y))
  | Pointer_released (value, x, y) ->
      Some (Pointer_released (button value, float x, float y))
  | Pointer_cancelled value -> Some (Pointer_cancelled (button value))
  | Wheel (x, y) -> Some (Wheel (float x, float y))
  | Key_pressed key -> Some (Key_pressed {key;modifiers=[];repeat=false})
  | Key_released key -> Some (Key_released {key;modifiers=[];repeat=false})
  | Text_input text -> Some (Text_input text)
  | Text_editing { text; start; length } ->
      Some (Text_editing { text; start; length })
  | Resized (width, height) -> Some (Resized (width, height))
  | Focus_lost -> Some Focus_lost
  | File_uploaded { name; contents } ->
      Some (File_dropped { name; contents = Some contents })

let push value event =
  match translate event with None -> Ok () | Some event -> Runtime_next_input.push value event
