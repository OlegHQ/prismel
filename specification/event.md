## Event Handling Architecture

Event handling is a crucial piece of the framework, connecting the low-level input from SDL to the user’s high-level game or application logic. The framework uses an event-polling model each frame: it retrieves all pending events (like key presses, mouse movement, window close requests, etc.) and then dispatches them to the user’s code (and updates Input state accordingly).

**Event Type:** We define a variant type `Event.t` that encapsulates all events our framework will handle. This makes event handling in user code convenient (with pattern matching) and strongly typed. The definition looks like:

```ocaml
type Event.t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of (int * int)            (* logical mouse position *)
  | MousePressed of Input.mouse_button * (int * int)
  | MouseReleased of Input.mouse_button * (int * int)
  | MouseScrolled of (int * int)
  | TextInput of string
  | TextEditing of { text : string; start : int; length : int }
  | FileDropped of string
  | WindowResized of (int * int)         (* new logical width and height *)
  | WindowFocusLost
  | WindowClosed
```

This covers the basics:

- Key press/release events carry our `Input.key`.
- Mouse move gives logical coordinates in the same space as `Scene` and
  `Frame.mouse`. SDL's renderer mapping performs high-DPI conversion.
- Mouse press/release includes which button and where it happened. (One could infer position from a prior MouseMoved, but including it is often useful for immediate context – e.g. on MouseReleased, knowing where the click was released).
- MouseScrolled gives scroll wheel motion; SDL typically provides an amount in “ticks” for horizontal and vertical scroll (e.g., (0,1) for one notch up). We wrap that.
- `TextInput` carries committed UTF-8 and `TextEditing` carries in-progress IME
  composition.
- `FileDropped` owns a copied path after the SDL allocation is released.
- `WindowResized` provides the new logical size after Prismel synchronizes the
  renderer.
- `WindowFocusLost` tells stateful consumers to cancel transient interaction;
  the Input module also clears held keys and buttons.
- `WindowClosed` indicates the user clicked the close button or requested an
  application quit. It is delivered in order, then the current loop stops.

**Event Polling Loop:** Each iteration of the main loop (in Core) will:

1. Call SDL_PollEvent repeatedly to gather all events from the SDL queue. We store them (perhaps in a list or directly process them).
2. For each SDL event, translate it to our `Event.t`:

   - SDL_KEYDOWN -> if it’s not a repeat (we likely ignore repeats), produce `Event.KeyPressed key`.
   - SDL_KEYUP -> `Event.KeyReleased key`.
   - SDL_MOUSEMOTION -> `Event.MouseMoved (x,y)`. Because the renderer has a
     logical size, SDL supplies logical positions even on Retina displays.
   - SDL_MOUSEBUTTONDOWN -> `Event.MousePressed (button, (x,y))`.
   - SDL_MOUSEBUTTONUP -> `Event.MouseReleased (button, (x,y))`.
   - SDL_MOUSEWHEEL -> interpret and produce `Event.MouseScrolled (dx, dy)`.
   - SDL_WINDOWEVENT_SIZE_CHANGED -> update the window and renderer logical
     dimensions, then produce `Event.WindowResized (new_w, new_h)`.
     `SDL_WINDOWEVENT_RESIZED` is ignored because SDL may emit it alongside the
     authoritative size-changed event.
   - SDL_WINDOWEVENT_FOCUS_LOST -> clear held Input state and produce
     `Event.WindowFocusLost`.
   - SDL_WINDOWEVENT_CLOSE or SDL_QUIT -> `Event.WindowClosed`.
   - (If we had joystick or others, handle them similarly.)

3. As we translate, we also update Input module’s state accordingly (e.g., on KeyPressed, mark key down, etc.).
4. We then have a list of Event.t for that frame.

**Dispatch to User Code:** We have a few design options:

- **Immediate callback per event:** If the user provided an `on_event` function (of type `state -> Event.t -> state`), we can apply that in sequence for each event. For example:

  ```ocaml
  List.fold_left (fun st ev -> user_on_event st ev) state events
  ```

  This means each event is handled in the order they occurred, potentially updating the state. By the time all events are processed, we have a state that accounts for all inputs this frame. Then we call `update` and `draw`.

- **Batch events and pass to update:** Alternatively, we could skip an explicit event callback and just pass the entire list of events to the `update` function: `update state events dt -> new_state`. The user can iterate through them or ignore if not needed. This approach is a bit less direct for simpler cases, but it avoids needing separate event vs update handling logic. However, it burdens `update` with two concerns (processing input and updating game logic).
- **Hybrid:** We allow both: if user gave an on_event, we do that, otherwise, we accumulate events for update.

In our specification, we lean towards the first (explicit event handler). It’s more structured and matches how openFrameworks does it (calls event methods immediately as events happen, before the next update) and many game engines separate input handling from game update.

Thus, the typical frame sequence is:

- Poll events -> update Input state and reduce state via `on_event` handler -> then call `update` with dt -> then call `draw`.

This ensures that events are handled as soon as they come in, and `update` sees a state that already incorporates immediate responses to those events. For example, if the user presses "P" to pause, the on_event might set `state.paused = true` right away. Then in `update`, you can respect that flag and skip updating game logic.

Alternatively, one could do events after update, but that tends to add a frame of latency to input handling, so we do it before.

**Threading Note:** All event polling and dispatch happens on the main thread (where SDL is initialized). We do not offload event handling to another thread (SDL requires events polled on main thread on some platforms, and GUI frameworks generally expect that). This is fine since event polling is quick (just pulling from an internal queue).

**Default Handling:** Some events might be handled by the framework by default:

- `WindowClosed` is delivered to the user handler and then ends the loop
  cleanly. `Sketch.quit` is the programmatic equivalent.
- `WindowResized` has already updated `Window.width`/`height` and the renderer
  logical size before user code sees it.
- `WindowFocusLost` clears held Input state. PXUI additionally cancels pointer
  capture, text focus, and IME composition when it consumes this event.
- Mouse events don’t have default actions (other than updating Input state).
- Key events: we might decide that pressing Escape triggers WindowClosed by default for convenience (some frameworks do that), but it’s better to leave it to user.

If the user doesn’t provide an `on_event` at all, we could simply skip calling it (no state change from events aside from Input’s own tracking). Then the user’s update might still check Input state. This is an acceptable mode of operation (maybe the user only cares about continuous state, not discrete events). We should ensure that works.

**Preventing Event Flood**: We will typically process all events every frame. If, e.g., 1000 mouse moves events accumulated because the CPU was busy, we’ll process all – which might be a lot of work, but dropping them could lead to lost input. It’s rare to accumulate huge event backlogs unless the program is stalling. We can assume normal event volumes (dozens per frame at most).

**Example Flow:**

Imagine the user is moving the mouse and clicking:

- In one frame, suppose they moved (generating MouseMoved events) and then clicked left button (MousePressed, maybe a Released too if within same frame).
- SDL might have multiple MouseMoved events if the mouse moved fast. We will poll them all. Potentially, we might condense them for efficiency (e.g., only last position matters in some cases) – but we won’t by default, we deliver all because maybe the user wants the intermediate steps (e.g., drawing a smooth curve).
- So events list might be: `[MouseMoved (100,100); MouseMoved (105,102); MousePressed (LeftButton, (105,102))]`.
- We fold through these:

  - state0 -> MouseMoved -> state1 (user might not change state on move, usually)
  - state1 -> MouseMoved -> state2 (likely still the same)
  - state2 -> MousePressed -> state3 (user’s on_event might, for example, set state.clicked = Some (105,102))

- Then call update on state3. In update, maybe they use the fact `clicked` was set to trigger some action once.
- Then draw state4.

Alternatively, if they didn’t provide on_event, state remains unchanged through event processing (but Input module updated the internal cursor pos and button down status). Then in update, they could query `Input.is_mouse_button_down LeftButton` and maybe see it’s true, and `Input.mouse_pos()` to get (105,102) to act on the click.

Both approaches reach similar ends; our framework supports either.

**FRP Integration:** We mention for advanced usage, events could be fed into functional reactive streams (like with OCaml’s React library). In fact, Daniel Bünzli’s **Useri** library (mentioned in research) does exactly that, packaging events as signals. While our core doesn’t require FRP, our event system is implemented in a way that could be adapted: one could easily feed `Event.t` values into a reactive signal or stream if they prefer that style, without changing how we produce them.

**Multiple Windows:** If we were to support multiple windows, events would carry a window identifier. For now, we assume one window (so we ignore the event’s windowID or treat events as for the main window).

**Maintainability:** The events are defined in one place, making it easy to add a new event type or deprecate one. For example, adding `Event.KeyTyped of char` if needed, or gamepad events, would be straightforward. Contributors should ensure to update the event polling logic and the `Event.t` variant simultaneously.

**Performance:** Pattern matching on variants is very fast in OCaml (compiled to integers jump). The number of events per frame is usually small (<< 100), so overhead is negligible. The main loop fold is O(n events). Our Input state updates are O(1) per event (just set an array or so). So event handling will not be a bottleneck.

**Example (User side):**

In user’s code:

```ocaml
let on_event state ev =
  match ev with
  | Event.KeyPressed (KeyChar 'p') ->
      { state with paused = not state.paused }
  | Event.KeyPressed ArrowUp ->
      { state with player = { state.player with jump = true } }
  | Event.KeyReleased ArrowUp ->
      { state with player = { state.player with jump = false } }
  | Event.MousePressed (LeftButton, (x,y)) ->
      { state with last_click = Some (x,y) }
  | Event.WindowClosed ->
      (* maybe prompt or set a flag to confirm quit *)
      { state with should_close = true }
  | _ ->
      state
```

This demonstrates how concise and clear event handling can be with our variant. The user can ignore events they don't care about (`_ -> state` passes through any event unhandled).

Our Core will, after processing events, check `state.should_close` or the like, and break if needed (or we break automatically on WindowClosed if user didn't handle it).

**Conclusion:** The Event architecture ensures that:

- The app stays responsive to input (handling is done every frame).
- The user can intercept and respond to input easily.
- The framework can manage its internal state (Input, etc.) concurrently.
- There’s flexibility to either handle things immediately or via polling in update, depending on user preference.

This design keeps input handling deterministic (all events processed in a known order each frame) and keeps separation of concerns (event logic vs game logic vs rendering), which is a hallmark of game loop architecture. It also sets the stage for potential cross-platform adaptation, since only the Event module and Input module are really platform-dependent (SDL vs, say, browser events). By abstracting SDL events into our own Event.t, we decouple the rest of the code from SDL specifics.
