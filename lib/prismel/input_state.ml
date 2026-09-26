(* Private: the running sketch's native event source and the held-input state
   it folds into each [Frame.t]. Only [Sketch] touches it. *)

module KeySet = Set.Make (struct type t = Input.key let compare = compare end)
module ButtonSet = Set.Make (struct type t = Input.mouse_button let compare = compare end)

let pressed_keys = ref KeySet.empty
let pressed_buttons = ref ButtonSet.empty
let mouse = ref (0., 0.)
let delta = ref (0., 0.)

let move x y =
  let cx, cy = !mouse and dx, dy = !delta in
  delta := (dx +. x -. cx, dy +. y -. cy);
  mouse := (x, y)

let apply : Event.t -> unit = function
  | KeyPressed k -> pressed_keys := KeySet.add k !pressed_keys
  | KeyReleased k -> pressed_keys := KeySet.remove k !pressed_keys
  | MouseMoved (x, y) -> move x y
  | MousePressed (b, (x, y)) -> move x y; pressed_buttons := ButtonSet.add b !pressed_buttons
  | MouseReleased (b, (x, y)) -> move x y; pressed_buttons := ButtonSet.remove b !pressed_buttons
  | PointerCancelled b -> pressed_buttons := ButtonSet.remove b !pressed_buttons
  | WindowFocusLost -> pressed_keys := KeySet.empty; pressed_buttons := ButtonSet.empty
  | _ -> ()

let source = match Runtime_input.create ~max_events:4096 ~logical_width:1 ~logical_height:1 with
  | Ok x -> x | Error e -> failwith e

let button = function
  | Runtime_input.Left -> Input.LeftButton | Right -> RightButton | Middle -> MiddleButton
  | X1 -> MouseX1 | X2 -> MouseX2

let convert : Runtime_input.event -> Event.t option = function
  | Pointer_moved (x, y) -> Some (MouseMoved (x, y))
  | Pointer_pressed (b, x, y) -> Some (MousePressed (button b, (x, y)))
  | Pointer_released (b, x, y) -> Some (MouseReleased (button b, (x, y)))
  | Pointer_cancelled b -> Some (PointerCancelled (button b))
  | Wheel (x, y) -> Some (MouseScrolled (x, y))
  | Key_pressed e -> Some (KeyPressed (Event.Private.key_of_name e.key))
  | Key_released e -> Some (KeyReleased (Event.Private.key_of_name e.key))
  | Text_input s -> Some (TextInput s)
  | Text_editing { text; start; length } -> Some (TextEditing { text; start; length })
  | File_dropped path -> Some (FileDropped path)
  | Resized (w, h) -> Some (WindowResized (w, h))
  | Focus_lost -> Some WindowFocusLost
  | Quit -> Some WindowClosed
  | Focus_gained | Visibility_changed _ -> None

let configure ~logical_width ~logical_height =
  match Runtime_input.set_extent source ~logical_width ~logical_height with
  | Ok () -> ()
  | Error message -> invalid_arg ("Sketch: input extent: " ^ message)

let set_relative enabled = Runtime_input.set_relative source enabled

(* In relative mode the frame's [mouse_delta] is the summed device motion
   rather than absolute differences, which stop at the window edge. *)
let poll () =
  delta := (0., 0.);
  Runtime_input.begin_frame source;
  (match Runtime_input_sdl3.pump source with Ok () -> () | Error _ -> ());
  let events = Runtime_input.drain source |> List.filter_map convert in
  List.iter apply events;
  if Runtime_input.relative source then delta := (Runtime_input.snapshot source).mouse_delta;
  events

let mouse () = !mouse
let mouse_delta () = !delta
let keys () = KeySet.elements !pressed_keys
let buttons () = ButtonSet.elements !pressed_buttons
