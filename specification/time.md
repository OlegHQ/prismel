## Time and Animation Management

The Time module and associated functionality deal with the passage of time in the application, which is critical for animation and regulating the main loop’s speed. The framework aims to make animations smooth and time-based rather than frame-dependent, meaning movement and changes should be tied to real elapsed time (e.g., seconds) instead of “per frame” steps, so that the app behaves consistently across different machines or under different loads.

**Frame Delta Time (dt):** Each frame, the Core computes the time elapsed since the last frame (in seconds, as a float). This value `dt` is passed to the user’s update function: `update(state, dt) -> new_state`. The user should use `dt` when updating motion or animations. For example, if an object should move at 100 pixels per second to the right, the update would do `x := x + 100 * dt`. If `dt` is 0.016 (approx 60 FPS), x increases \~1.6 px that frame; if the frame took longer, say dt=0.033 (30 FPS), x increases \~3.3 px that frame, resulting in \~100 px moved after 1 second regardless of frame rate. This practice ensures **frame rate independence**, so the speed of motion is consistent even if the FPS fluctuates.

We provide `Time.now ()` or `Time.timestamp ()` to get the current absolute time. We likely initialize a “start time” at program launch, and `Time.elapsed ()` returns seconds since start (a float). The main loop can do:

```ocaml
let current_time = Time.now () in
let dt = current_time -. prev_time in
prev_time := current_time;
user_state := user_update !user_state dt;
```

This yields `dt` in seconds. Alternatively, we might measure in milliseconds as an int and convert to float seconds.

**Fixed vs Variable Timestep:** Our default is variable timestepping (like above). Some might want a fixed physics tick (say 60 Hz) separate from rendering. We won’t enforce that, but advanced users could implement it inside their update if desired. For most, using dt is simpler.

**Frame Rate Control:** The framework allows controlling the target frame rate:

- `Time.set_frame_rate fps:int -> unit` – This function can be called (typically in init) to request a maximum frame rate. For example, `Time.set_frame_rate 60` will cap at 60 FPS. Internally, we will then, in the main loop, compute how long each frame took and if it finished sooner than 1/60 second, we delay the remainder. This uses SDL_Delay or a high-res sleep. Note that capping frame rate can reduce CPU usage but might introduce slight timing irregularities (sleep is not exact). It’s optional; many will rely on vsync instead.
- `Time.set_vsync enabled:bool -> unit` – Enables or disables vertical sync with the monitor. If vsync is on, SDL’s `render_present` will block until the monitor refresh, effectively capping the frame rate to the monitor’s refresh (often \~60 Hz). Vsync ensures no tearing and steady frame pacing, but if the program can’t keep up, it may drop to lower fractions (30, 20 fps, etc.). By default, we plan to start with vsync enabled (which is common and usually good for visual apps). The user can disable it via this function if they prefer uncapped or custom cap. Disabling vsync might allow very high FPS (which could be hundreds as noted in openFrameworks docs), useful for benchmarking or when one doesn’t care about tearing (maybe offscreen rendering).
- We also allow both vsync and a target FPS together; if vsync is on, the frame won’t run faster than monitor anyway, but user could cap lower than vsync rate if desired (though typically one would just not do that and use vsync or not exclusively).

Under the hood, if vsync is off and target FPS is set, we do:

```ocaml
let target_dt = 1.0 /. fps in
if dt < target_dt then
  Sdl.delay (Uint32 of ((target_dt - dt) * 1000.0))
```

This simple mechanism will sleep the main thread for the remaining time slice. The actual dt next frame might be a bit more or less than target due to OS scheduling, but on average it achieves the cap.

If vsync is on, Sdl.delay is not needed because Present waits.

We also provide:

- `Time.get_frame_rate () -> float` – maybe returns the instantaneous FPS (like 1/dt of last frame), or a smoothed average. This can be used for display or adaptive logic.
- `Time.get_delta_time () -> float` – returns the dt of the last frame, if the user needs it outside update (rarely needed, since it's passed in).
- Possibly `Time.framerate_timer_enabled:bool` or `Time.frame_delay:int` storing the desired frame ms to delay.

**Pausing and Stepping:** If the user sets a pause in state and doesn’t want the game to update, they could ignore dt or skip update. We could help by:

- `Time.pause ()` and `Time.resume ()` which internally freeze the dt (i.e., keep returning 0 for dt while paused). But that is tricky globally; easier is user’s update checks state.paused and early-returns state (no changes, effectively freezing game objects). So we may not add these functions in core.
- If doing a fixed step loop, the user could accumulate dt and run multiple smaller updates if dt is large (to avoid tunneling in physics). That’s up to them.

**Animation Helpers:** Besides raw time, we include some helpers to simplify common timing/animation tasks:

- `Time.delay_call t f` – Schedule a function `f` to be called after `t` seconds. This could be implemented by storing a list of (target_time, callback) and checking in update; or simpler, not included.
- `Time.every interval f` – like setInterval, call `f` every `interval` seconds.
- These are convenience and can be done by user (store an accumulator in state, etc.), but we might offer them for easy animations (like flash something for 5 seconds).
- At least, we should document how to do these with dt or provide examples.

**Easing and Interpolation:** Animations often require interpolation between values over time:

- `Math.lerp` (in Math module) already provides linear interpolation between two numbers.
- We could provide common easing functions (not strictly time module, but related to animation curves):

  - E.g., `Time.ease_in t`, `Time.ease_out t`, `Time.ease_in_out t` which take a 0-1 input and output a 0-1 adjusted (ease-in or ease-out curve). These can be used to modulate the parameter for `lerp` to get smooth acceleration/deceleration.
  - Or `Time.smoothstep t` which is a simple ease in-out (3t^2 - 2t^3).
  - These are lightweight and can save users time instead of writing their own.

- `Time.elapsed_fraction start_time duration` – returns a number 0 to 1 indicating how far current time is between start_time and start_time+duration, clamped. Useful for driving a progress of an animation.

**Use Case Example:** Suppose a user wants to fade out an image over 2 seconds:

```ocaml
if state.fade_start <> None then (
  let t = Time.elapsed () -. Option.get state.fade_start in
  if t >= 2.0 then (
    state.image_alpha <- 0;
    state.fade_start <- None;
  ) else (
    let pct = t /. 2.0 in
    state.image_alpha <- int_of_float (255. *. (1.0 -. pct))
  )
)
```

This uses `Time.elapsed ()` to see how much time passed since fade_start, then calculates a percentage and sets alpha accordingly. With ease functions, one could do `let pct = Time.ease_out_quad (t /. 2.0)` to use a non-linear fade.

**Real-time Clock vs Game Time:** We assume game time flows normally with real time (1 second real = 1 second game). If one wanted slow-motion or fast-forward, they could scale dt in update by a factor. The Time module could allow a global time scale:

- `Time.time_scale : float ref` – default 1.0. If set to 0.5, all dt delivered to update would be half the real value (making everything run in slow-mo). We could implement that by simply multiplying dt by time_scale when passing to user update.
- This is an advanced feature but easy to include. We should caution the user that physics and input might also be scaled (e.g., if time_scale=0, game paused effectively; if >1, game speed up).
- If not needed often, we might omit it to avoid confusion.

**Frame Timing Accuracy:**

- On most systems, using SDL_GetPerformanceCounter (high-res timer) yields sub-millisecond resolution, which is good for smooth animation and small dt differences.
- If vsync is on, dt will often be \~0.01666 or multiples (if frame missed).
- If we cap frame rate via delay, dt might be slightly more or less than target due to timer granularity.
- But these tiny variations are normal. If needed, user could measure smoothed FPS or clamp dt values to avoid extreme physics jumps (some games clamp dt to a max to avoid spiral of death if lag).
- We can mention: If dt is very large (e.g., when debugging with breakpoints or if the window was minimized for a while), your game might jump a lot. A pattern is to do `if dt > 0.1 then dt = 0.1` to cap the effect of a huge lag spike. We can either implement this in core (clamp dt to something like 0.1 s to avoid weird jumps) or mention to users as a tip.

**Time in Event Timestamps:** We likely won’t expose timestamps on events (like exactly when event happened). Not needed for our scale.

**Example demonstrating dt usage in user code:**

```ocaml
(* Suppose state.vx and state.vy are velocities (pixels per second) *)
let update state dt =
  if not state.paused then
    { state with
        x = state.x +. state.vx *. dt;
        y = state.y +. state.vy *. dt;
        animation_time = state.animation_time +. dt }
  else
    state
```

This moves an object by vx, vy scaled by dt (so it moves correctly per second). It also accumulates an `animation_time` which might be used to cycle through animation frames (like if each sprite frame lasts 0.1s, you could compute frame index from animation_time). The pause check illustrates using a pause flag to ignore advancing time (object doesn’t move or animation doesn’t progress when paused). Because we still accumulate dt but not use it, the game effectively freezes; since dt keeps accumulating, when unpausing, the object would jump if we suddenly apply the whole accumulated dt. So a better approach is to not accumulate dt at all when paused – e.g., in Core, if paused, skip calling update or call it with dt=0. We could integrate that concept with a Time.time_scale as mentioned (set to 0 if paused), to avoid such jumps.

**Scheduling events:** If the user wants to trigger something in the future (like a bomb explosion 3 seconds from now), they can store the current time + 3.0 in state and each update compare `Time.now () >= scheduled_time`. We could formalize this via a small scheduler as earlier, but it might be overkill for core.

In conclusion, the Time module and dt usage ensures the framework supports smooth animations and consistent behavior across varying performance. By default enabling vsync and advising the use of dt, we align with best practices to avoid speed doubling on fast machines or halving on slow machines. The provided utilities further ease the common tasks of interpolation and timing.
