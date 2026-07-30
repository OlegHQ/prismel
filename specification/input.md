
## Input Module (Keyboard and Mouse Input)

The Input module deals with capturing and representing the state of input devices, primarily the keyboard and mouse. It defines types to represent keys and buttons in a way that is convenient for OCaml pattern matching, and provides functions to query input states outside of event handlers.

### Coordinate and frame semantics

Mouse positions are logical window points. They use exactly the same
top-left-origin coordinate space as `Frame.size`, `Scene`, and PXUI. SDL maps
native pointer coordinates through the renderer logical size, so `Input`,
`Event`, and UI code must not apply `Frame.pixel_scale` a second time.

At the start of each application frame, `Input.begin_frame` resets the motion
accumulator. Every mouse motion, press, and release updates the current logical
position and adds its displacement. `Input.mouse_delta` and
`Frame.mouse_delta` therefore report the aggregate displacement across all
pointer events polled in that frame. They report `(0, 0)` on a later frame with
no motion instead of repeating a stale delta.

`Event.WindowFocusLost` clears all held keys and mouse buttons. This prevents a
release delivered outside the application from leaving a key or button stuck.

**Keyboard Input:**

- We define a variant type `Input.key` to represent keyboard keys. This includes all alphanumeric keys and special keys. For example:

  ```ocaml
  type key =
    | KeyChar of char                (* for 'a'-'z', '0'-'9', etc. *)
    | ArrowUp | ArrowDown | ArrowLeft | ArrowRight
    | Space | Enter | Escape | Backspace | Tab
    | Shift | Ctrl | Alt
    | F1 | F2  (* function keys, etc., up to F12 perhaps *)
    | Home | End | PageUp | PageDown
    | Insert | Delete
    (* ... and so on for any other keys we want to support explicitly ... *)
    | Unknown of int
  ```

  This variant allows pattern matching on keys in a natural way. For instance, a user can write `match key with KeyChar 'q' -> quit_app () | ArrowLeft -> move_left () | _ -> ()`. We include `KeyChar` for printable characters to cover letter and number keys easily, and explicit constructors for common special keys. `Unknown of int` is a fallback for keys we didn’t enumerate (it might carry an SDL scancode or keycode for advanced users or for debugging).

  Note: SDL differentiates scancode (physical key position) vs keycode (meaning, taking into account keyboard layout). We likely use keycode (so that `KeyChar 'a'` means the 'A' key on whatever layout, whereas scancode would be the key in the QWERTY 'A' position regardless of layout). This detail will be handled in translating SDL events to our `Input.key`.

- **Modifier Keys:** We treat Shift, Ctrl, Alt as keys in the variant, which represent left or right indistinctly (if needed, we could separate left vs right shift, but most apps don’t need that granularity).

- **Mouse Input:**

  - We define `Input.mouse_button` as a variant: `LeftButton | RightButton | MiddleButton | MouseX1 | MouseX2` (the extra X1, X2 buttons some mice have on the side).
  - We capture mouse position as a pair of integers `(x, y)` in logical window
    points.
  - If needed, we also have `Input.mouse_wheel` event data (like (dx, dy) for scroll wheel motions), but that’s more an event than a state (we can’t “query” wheel position, only events).

- **Event Integration:** The Input module itself doesn’t generate events; the Event module will produce events like `Event.KeyPressed of Input.key` and `Event.KeyReleased of Input.key` when keys go down/up, and `Event.MouseMoved of (x,y)` when the mouse moves, etc. Input and Event are complementary: Event is push-based (tells you when something happens), Input is pull-based (lets you check current status of input at any time).

- **State Tracking:** We maintain some internal state, such as:

  - A set of currently pressed keys.
  - The current mouse position.
  - A set of currently pressed mouse buttons.
  - Possibly the last scroll wheel delta (though typically one handles that via events rather than state).

  These are updated each frame as events are processed. For example, when a `KeyPressed A` event occurs, we add the A key to the pressed set; on `KeyReleased A`, we remove it. The user’s update function can then query e.g. `Input.is_key_down Key.Space` to see if space is held, even if no new event occurred that frame. This is important for continuous actions (like moving a character while a key is held).

- **Functions:**

  - `Input.is_key_down : Input.key -> bool` – checks if the given key is currently pressed. This works for letter keys and special keys alike. For `KeyChar 'a'`, it returns true if 'A' is down. For `Shift`, true if either shift is down (we unify them).
  - `Input.is_key_up : Input.key -> bool` – simply the negation (or just use `not (is_key_down ...)`).
  - `Input.keys_down : unit -> Input.key list` – returns a list of all keys currently pressed. (This could be useful if one wanted to snapshot all pressed keys for debugging or combination inputs.)
  - `Input.mouse_pos : unit -> (int * int)` – returns the current mouse cursor position within the window.
  - `Input.mouse_delta : unit -> (int * int)` – returns the sum of logical
    pointer displacement received in the current application frame.
  - `Input.is_mouse_button_down : Input.mouse_button -> bool` – analogous to key, for mouse buttons.
  - Possibly `Input.mouse_buttons_down : unit -> mouse_button list`.

- **Text Input:** SDL text input is exposed as `Event.TextInput` for committed
  UTF-8 and `Event.TextEditing` for in-progress IME composition. It remains
  event-based rather than persistent `Input` state.

- **Usage Patterns:** There are two ways to use the Input info:

  1. **Event-driven:** Use the events in your `on_event` callback to react immediately (e.g., `Event.KeyPressed ArrowLeft -> move left`). This is suitable for discrete actions or immediate responses.
  2. **State query in update:** Use the `is_key_down` in the `update` function to handle continuous input (e.g., keep moving left while left arrow is held). This pattern is common in games. For example:

     ```ocaml
     let update state dt =
       let vx = (if Input.is_key_down ArrowRight then 100.0 else 0.0)
                -. (if Input.is_key_down ArrowLeft then 100.0 else 0.0) in
       { state with player_x = state.player_x +. vx *. dt }
     ```

     This moves player right or left based on arrow keys continuously.

  The framework supports both: it captures events to update the internal pressed sets (so is_key_down works), and also passes events out to the user for one-off handling.

- **Edge Cases:**

  - If multiple keys are pressed at once, all will be reported in `keys_down`. The user can check combinations by checking multiple is_key_downs. We might later add a convenience like `Input.any_key_down [K1; K2]` but it’s trivial to do with `||`.
  - If the window loses focus, `WindowFocusLost` explicitly clears the tracked
    key and mouse-button sets. If it regains focus, no input is considered held
    until a new press arrives.
  - For mouse, if the cursor leaves the window, we might consider the buttons up (SDL gives a WindowLeave event; we could treat that as releasing all buttons, or at least updating that we don’t know position outside).
  - We should handle repeated key events. By default, SDL can generate multiple KeyPressed events if a key is held (key repeat). We might disable key repeat at SDL level, and treat a hold as one KeyPressed until release. That is usually what games do (so you don’t get spurious multiple events for one long press). If key repeat is needed for text input (like holding a letter to type multiple), that would be handled in text input mode rather than raw key events.

**Implementation with SDL:** Using Tsdl:

- SDL’s event structure gives key events: we get `Sdl.Event.key_scancode` or `key_sym` for the key pressed/released. We map those to our `Input.key`. For example, if `key_sym` corresponds to SDL’s SDLK_LEFT, we produce `ArrowLeft`. If it’s an ASCII letter, we produce `KeyChar 'a'` or capital as needed (maybe we normalize to lowercase for simplicity, treating 'A' and 'a' the same since shift is separate). If an unmapped key, we produce `Unknown code`.
- Mouse events give x,y and button. We map SDL’s `SDL_BUTTON_LEFT` to `LeftButton`, etc.
- We update the pressed sets: e.g., on KeyDown, do `keys_pressed.add key`; on KeyUp, `keys_pressed.remove key`. Similar for mouse.
- `Input.is_key_down k` then just checks membership in that set.
- The Input module might hide this state behind its functions; Core/Event will be the one calling Input’s internal update functions as events come in. (Alternatively, Core might manage the set itself and Input.is_key_down is just reading a global reference).
- We must be careful with performance: sets or lists of keys are at most maybe a few keys at once, so performance is trivial. We can use an array\[256] of bool for keys by scancode or something for O(1) checks, but clarity is more important here given the small scale. A simple `bool array` indexed by SDL scancode could be easiest (size 512 for all possible scancodes).
- Mouse position is updated by motion, press, and release events. Each update
  contributes to the current frame's aggregate logical delta.
- Mouse button pressed events update a bitmask or set of pressed buttons.

**Example of usage in user code:**

The user can choose events or polling:

```ocaml
(* Using events *)
let handle_event state = function
  | Event.KeyPressed Input.Space -> { state with jumping = true }
  | Event.KeyReleased Input.Space -> { state with jumping = false }
  | Event.MousePressed (LeftButton, (x,y)) -> { state with clicked_point = Some (x,y) }
  | _ -> state

(* Using polling in update *)
let update state dt =
  let dx = (if Input.is_key_down ArrowRight then 1 else 0) - (if Input.is_key_down ArrowLeft then 1 else 0) in
  let dy = (if Input.is_key_down ArrowDown then 1 else 0) - (if Input.is_key_down ArrowUp then 1 else 0) in
  let speed = 200.0 in
  { state with player_x = state.player_x +. float(dx) *. speed *. dt;
               player_y = state.player_y +. float(dy) *. speed *. dt }
```

In this combined approach, pressing space toggles a jumping state via event. Arrow keys continuously move the player by checking state in update (which works even if the keys are held for multiple frames). This shows how Input’s conveniences relieve the user from manually tracking key state across frames—our framework does that for them.

**Extensibility:** If later we add Gamepad support, we might extend `Input` with a `gamepad` sub-state, e.g., functions like `Input.gamepad_axis player_index axis` or events for gamepad buttons. The design is such that it wouldn’t interfere with keyboard/mouse logic. Similarly, multi-touch or other input can be added in their own domain.

The Input module ensures that at any point in the update loop, the program can query “what is the input state right now?” without having to buffer events manually. This fits well with typical game loops where physics or movement are computed from the current input state each tick.
