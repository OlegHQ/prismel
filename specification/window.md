## Windowing and Application Loop

The Windowing system and main application loop are the backbone of the framework, setting up the environment for everything else to run. This section describes how the framework initializes the window, enters the event-update-draw loop, and handles system events like closing or resizing the window. It also covers how the user configures the window and how the loop is managed (timing and termination).

### Current coordinate contract

Prismel creates high-DPI-capable SDL windows by default. Window configuration,
`Window.size`, `Frame.size`, scene geometry, and pointer events are expressed in
logical points. Immediately after creating the renderer, Prismel sets its
logical size to the actual SDL window size. On a Retina display, an `800 × 600`
logical window may therefore have a `1600 × 1200` renderer output without
changing application layout.

`Window.drawable_size` and `Frame.drawable_size` expose the physical renderer
output. `Window.pixel_scale` and `Frame.pixel_scale` expose the physical-pixel
to logical-point ratio per axis. These are query results, not constants; a
window can acquire a different backing density after moving between displays.
Rendering, input, and UI code should remain logical unless it is deliberately
reading native framebuffer pixels.

**Window Initialization:**
When the user calls `Framework.run` (or a similar entry point) to start their app, the framework will:

1. **Initialize SDL** – We call `Sdl.init` with appropriate flags. We include at least `Sdl.Init.video` and `Sdl.Init.audio` (and possibly `Sdl.Init.events` which is usually included with video). If initialization fails, we return an error or throw an exception (since nothing can proceed). We also initialize the subsystems:

   - Tsdl_image doesn’t require an explicit init for loading files, but we call `Img.init [Init.png; Init.jpg]` to ensure PNG/JPG support (checking the returned flags for success).
   - Tsdl_mixer: call `Mix.open_audio` with desired parameters (e.g., 44100 Hz, stereo, 2048 chunk size). Also `Mix.init` with proper flags (e.g., `Mix.Init.mp3 + Mix.Init.ogg` to enable those codecs) and check it returns those flags (if not, some codec might not be available, we could still proceed without that format).
   - Tsdl_ttf (if used for fonts): call `Ttf.init`.
     Any failure here is an error (e.g., audio device can’t open, or no video device, etc.).

2. **Create Window** – Use `Sdl.create_window ~w ~h ~title ~flags`. The `flags` are determined by user’s config:

   - If config.resizable = true, include `Window.resizable`.
   - If fullscreen = true, we could use `Window.fullscreen_desktop` (for modern borderless fullscreen at desktop res) or `Window.fullscreen` (for exclusive mode).
   - If we allow an OpenGL context for advanced, it could be a flag, but by default we use the renderer.
   - We likely use `Window.hidden` initially if we want to hide until fully set up (maybe not needed).
     If the window creation fails (rare, unless invalid dimensions or no video), we abort with error.

3. **Create Renderer** – We create an SDL_Renderer for the window. `Sdl.create_renderer window ~index (-1) ~flags:[ Renderer.accelerated; Renderer.presentvsync ]` by default (accelerated + vsync). If the user disabled vsync in config, we omit that flag. If creation fails (some older machines might not support accelerated context, though SDL will fallback to software automatically if accelerated not possible, unless one explicitly demands it), we try a fallback:

   - Try again without vsync or without accelerated (software).
   - If still fails, error out.
     The renderer is what we'll use for all Graphics operations.

4. **Set up Window Manager Info (Optional)**:

   - We might set a window icon if provided (like if user gave an icon file path in config, we can load a surface and call `Sdl.set_window_icon`).
   - Possibly set `Sdl.show_window window` if it was hidden.
   - Set the SDL renderer logical size to the window's current logical width and
     height. SDL then scales rendering to the native output and maps pointer
     events back to logical coordinates.
   - If config.x, config.y positions are given (or default centered), that can be passed to create_window or set afterward.

5. **Initialize Input/Events Systems**:

   - Perhaps call `Sdl.start_text_input` if needed (we can do that on demand when user wants to type text, not by default).
   - Ensure our Input module internal structures are empty (no keys down, etc.).
   - Possibly warp the mouse to some position or set relative mode if needed by config (if making a first-person camera, relative mouse mode could be toggled via an API).
   - We set up the event filter or simply ready to poll.

6. **Initialize Timing**:

   - Record the starting timestamp (for elapsed time reference).
   - Initialize the last_frame_time as now.

7. **User Initialization (`init` callback)**:

   - Call the user’s `init` function to get initial application state. Provide any needed parameters to it (maybe none, or maybe we allow user to capture config in closure).
   - If `init` is to return an initial state structure, we use that going forward.
   - If `init` can fail or do significant work, that's up to user; we just proceed after obtaining state.
   - Possibly call user’s custom window setup code if they provided (e.g., some frameworks let you do things like set up OpenGL here – not relevant unless we expose GL).

**Main Loop:**
Now we enter the loop of:

```ocaml
while running do
  poll_events;
  handle_events (update state via on_event);
  update state via user_update(dt);
  draw state via user_draw;
  present renderer;
  regulate_frame_timing;
done
```

- We maintain a `running` boolean. `Event.WindowClosed` or `Sketch.quit ()`
  requests an orderly stop.
- **Event Polling:** (Using our Event module as described) gather all SDL events available. If none, fine. For each event:

  - A window close request or SDL quit is queued as `Event.WindowClosed`.
  - Translate events to `Event.t` and update Input state.
  - If user provided `on_event`, fold it over state (let new_state = on_event(old_state, ev) for each).
  - After events, we have a possibly updated state reflecting immediate reactions.

- **Update:** Compute `dt` = time since last frame (in seconds). Possibly clamp if too large (say if >0.1, clamp to 0.1 to avoid big jumps).

  - Call `user_update state dt -> new_state`. This should produce the next state of the application based on time and any internal logic.
  - We catch any exceptions from user code here (to avoid crashing out of loop if e.g. a division by zero happened in user code). Possibly print error and break, or attempt to continue. For a creative coding tool, maybe just propagate and crash so the user sees the stack trace for debugging. But for an installation, one might want to catch and continue or shut down gracefully. We can keep it simple: don’t catch exceptions (let them propagate, which likely ends program with error).

- **Draw:** Call `user_draw state`. This should issue Graphics calls to render the frame. We ensure at start of draw, we maybe set render target to window (if we had offscreen targets at some point).

  - Surround draw with any needed setup: e.g., clear background if not done in user code (some frameworks auto-clear if user didn’t; we probably won't – we'll expect user to call Graphics.clear or have full control).
  - After user_draw returns, all drawing commands have been queued in the SDL renderer.
  - We call `Sdl.render_present renderer` to display the frame.

- **Frame timing:** We then compute how long frame took, and either sleep to cap frame rate or just immediately continue:

  - If vsync is on, render_present blocked to sync, so the frame likely took \~16ms, dt reflects that.
  - If vsync off and target_fps set, we do `delay = (1/fps - frame_time)` if positive, call `Sdl.delay (ms)`.
  - Update last_frame_time for next dt.
  - Optionally, accumulate time or frame count to compute an average FPS if needed (not necessary but could for stats).

- The loop repeats until `running` becomes false.

**Handling Quit/Close:**

- A close button or SDL quit becomes `Event.WindowClosed`. User event handlers
  receive it in order, then the application loop stops. Close cancellation is
  not part of the current contract.
- User code calls `Sketch.quit ()` for a programmatic graceful stop. The loop
  still runs registered cleanup while SDL resources are valid; user code should
  not call `exit`.

**Resizing:**

- SDL can emit both `SDL_WINDOWEVENT_RESIZED` and
  `SDL_WINDOWEVENT_SIZE_CHANGED` for one operation. Prismel treats
  `SIZE_CHANGED` as authoritative and ignores the duplicate `RESIZED`
  notification.
- The event boundary updates `Window.width`/`height`, resets the renderer
  logical size to the new logical dimensions, and emits exactly one
  `Event.WindowResized (w, h)`.
- The current event, subsequent pointer events, and the next `Frame.t` all use
  that same logical size. The native `drawable_size` is queried separately.
- `Window.set_size` performs the same logical-size synchronization for a
  programmatic resize.

**FullScreen:**

- If fullscreen toggled (by user pressing ALT+Enter usually or by code):

  - `Window.set_fullscreen true` delegates to SDL's desktop-fullscreen mode.
    Any resulting authoritative size-change event resynchronizes logical
    dimensions and the renderer.
  - If user has an event to toggle fullscreen, they'd call that function.
  - If the window is resized as part of fullscreen, SDL will send a resize event which we handle as above.

**High-DPI considerations:**

- `Window.allow_highdpi` is enabled by default. Prismel queries
  `SDL_GetRendererOutputSize`, not a reported monitor DPI, because the actual
  drawable-to-window ratio is authoritative.
- `SDL_RenderSetLogicalSize` owns both output scaling and absolute pointer-event
  mapping. Do not apply an additional scale in `Event`, `Input`, PXUI, or user
  sketches.
- TTF fonts lazily rasterize at the renderer's current native density but draw
  with logical dimensions. This avoids blurred 1× glyph textures on a 2×
  framebuffer.
- `Canvas.capture` and `Canvas.save_screen_png` read the full native renderer
  output. A Retina capture is intentionally larger than `Window.size`.

**Closing the app:**
After breaking out of loop:

- We call user’s optional `cleanup` if they provided (some frameworks have a onExit callback). We could just rely on normal OCaml finalizers or let OS reclaim memory, but if user wants to save something or free large arrays, they might want a callback.
- We then free resources:

  - Destroy all `Image.t` and `Sound.t` that are still loaded, if we track them globally (we likely do not track automatically, it's user’s job to destroy).
  - But we definitely call:

    - `Sdl.destroy_renderer renderer`
    - `Sdl.destroy_window window`
    - `Mix.close_audio` and `Mix.quit`
    - `Img.quit` (if needed, to deinitialize SDL_image)
    - `Ttf.quit` (if we used TTF).
    - `Sdl.quit ()` to shut down SDL.

  - These calls ensure all underlying subsystems exit cleanly (and sound stops, etc.).

- Then `Framework.run` returns. We may allow it to return the final state (if user needs that for some reason, maybe not necessary).
- The program then can terminate (if main ends) or continue if they had more code (rare in interactive context, usually run is last call).

**Error Handling in Loop:**
We should handle scenario if user’s draw or update raises an exception (like from a bug). Perhaps we let it propagate (so program crashes, which is fine for developer to see error). In a robust deployment, one might catch exceptions per frame to avoid whole app closing on one frame’s glitch, but typically, an unhandled exception should not be silently eaten or the app might go on in a bad state. So we won't catch, except maybe around event handling or initializations where we want to convert to result.

**Frame Rate and Vsync:**

- By default, with vsync on, the loop is naturally capped.
- If user sets target_fps lower than monitor (say 30), with vsync on at 60, we can't easily lower it except to skip every other frame’s drawing (we could implement logic to only render on alternate frames to achieve 30 fps while still syncing to monitor). But easier: if user wants 30, they should turn vsync off and use our cap (but then can get tearing).
- We might not fully resolve that – just note to user that if vsync is on, their `set_frame_rate` below refresh might not be honored precisely.

**Main Loop Example pseudo-code integrated:**

```ocaml
let config = { width=800; height=600; title="My App"; resizable=true; fullscreen=false; target_fps=60; vsync=true } in
Framework.run ~config ~init:initialize ~update:on_update ~draw:on_draw ~on_event:handle_event

(* Inside Framework.run: *)
init_sdl_and_subsystems();
let window = Sdl.create_window ... in
let renderer = Sdl.create_renderer ... in
audio_init();  (* Mix.open_audio *)
let state = initialize () in
let running = ref true in
while !running do
  let events = Event.poll_all () in   (* gather SDL events *)
  let state = List.fold_left handle_event state events in  (* user event handling *)
  (* Check quit flag from events: *)
  if List.exists (function WindowClosed -> true | _ -> false) events then running := false;
  (* Could also check if user state has quit flag, etc. *)
  let now = Time.now() in
  let dt = now - last_time in
  last_time := now;
  let state = on_update state dt in   (* user update *)
  Sdl.render_clear renderer;  (* or user does explicit clear in draw *)
  on_draw state;   (* user drawing commands *)
  Sdl.render_present renderer;
  regulate_timing_if_needed(dt);
done;
cleanup_subsystems();
```

We left out some complexities (like vsync means no need to delay).
But that’s the structure.

**Configuration & Customization:**
The user can adjust in config:

- width, height
- title
- resizable
- fullscreen
- maybe an option for borderless window, etc. We could expose those as flags in config if needed.
- target_fps
- vsync
- audio frequency and channels (maybe we don't expose audio format config unless advanced user; we can go with defaults).

We provide sensible defaults (e.g., 800x600, vsync on, 60 fps target).

**Maintaining Idiomatic OCaml style:**
Our run function likely takes labeled arguments or a record:
We might define:

```ocaml
type Framework.config = { width:int; height:int; title:string; resizable:bool; fullscreen:bool; target_fps: int option; vsync: bool }
val Framework.run : ?config:config -> init:(unit -> 's) -> update:('s -> float -> 's) -> draw:('s -> unit) -> ?on_event:('s -> Event.t -> 's) -> unit -> unit
```

(This type signature shows run doesn't return state; if needed, user’s state can be returned, but not usually needed as program ends.)
We allow on_event optional; if not given, we just don't do event-driven state changes except Input updates.

We separate update and draw so user logically splits simulation and rendering (which openFrameworks encourages). This separation is nice for clarity (and potential debug toggling draw off to test logic or skip update to freeze physics for debugging).

**Example user usage:**

```ocaml
let init () = { player = init_player(); paused=false }
let update state dt =
  if not state.paused then { state with player = move_player state.player dt } else state
let draw state =
  Graphics.clear Color.black;
  draw_player state.player;
  if state.paused then Graphics.text ~pos:(300,300) "Paused" ~color:Color.white
let on_event state ev =
  match ev with
  | Event.KeyPressed Input.Space -> { state with paused = not state.paused }
  | _ -> state

let () =
  Framework.run ~config:{width=1024; height=768; title="Game"; resizable=false; fullscreen=false; target_fps=60; vsync=true}
    ~init ~update ~draw ~on_event
```

This outlines how a simple game might use the loop and handle pausing via events.

By following this structure, the user doesn’t have to manage the boilerplate of SDL setup or timing. They write pure-ish functions for logic and can rely on our loop calling them appropriately at a stable rate. This final piece of the framework is what turns it from a collection of utilities into a running application.
