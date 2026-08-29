# Input and events

Runtime translates SDL3 input into Prismel's typed, ordered `Event.t` stream
and updates the public `Input` snapshot. Native event values never expose an
SDL3 pointer or structure.

## Keys and buttons

`Input.key` represents printable characters, arrows, navigation/editing keys,
modifiers, F1–F12, and `Unknown of int` for an unmapped native code.
`Input.mouse_button` covers left, right, middle, and the two common auxiliary
buttons.

The public snapshot supports:

- `is_key_down`, `is_key_up`, and `keys_down`;
- `mouse_pos` and the current-frame aggregate `mouse_delta`;
- `is_mouse_button_down` and `mouse_buttons_down`.

Pressed collections are state facts, not a replacement for ordered events.
Use events for edges and text, and snapshot queries for continuous actions.

## Event order

`Frame.events` preserves poll order for:

- key press and release;
- pointer motion, press, release, cancellation, and wheel motion;
- committed UTF-8 and IME composition;
- file drops;
- logical window resize and focus loss;
- a requested window close.

Runtime updates the `Input` snapshot in the same pass. `Frame.mouse_delta` is
the sum of all logical pointer displacement observed during that application
frame and resets before polling the next frame.

## Logical coordinates

Pointer positions and resize dimensions use the same logical-point coordinate
system as `Scene`, `Frame.width`, `Frame.height`, and PXUI. Runtime obtains
SDL3 logical coordinates directly; application code must not multiply them by
`Frame.pixel_scale`. Physical drawable dimensions are a separate render
boundary.

`SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED` is authoritative for backing-size
changes. Runtime updates logical and drawable facts coherently before the next
frame is presented.

## Focus and cancellation

`WindowFocusLost` clears held keys and buttons so a missing release cannot
leave application state stuck. It also gives higher-level interaction systems
a hard boundary for pointer capture and text composition.

`PointerCancelled` releases the affected pointer capture without pretending
that the whole window lost focus. PXUI and camera controls must consume this
distinction consistently.

## Text and file-drop lifetime

`TextInput` carries committed UTF-8. `TextEditing` carries composition text and
its range. Pure `Scene.text_input_region` metadata tells Runtime where native
text entry is intended; Runtime owns SDL3 text-input activation and event
translation.

`FileDropped` owns a copied OCaml path. The native event payload is released at
the runtime boundary and cannot escape into user code.

## Domain and reset rules

Polling, state mutation, and every SDL3 operation run on the initial OCaml
domain. `Input.begin_frame` resets only per-frame facts. Runtime setup/reset and
focus loss use the private state-update boundary to establish a coherent
snapshot.

## Regression requirements

Input changes require tests for:

1. key/button press-release ordering and simultaneous held state;
2. multi-motion delta aggregation and next-frame reset;
3. logical coordinates at multiple drawable scales;
4. focus-loss clearing;
5. pointer cancellation distinct from focus loss;
6. committed UTF-8 and IME composition ordering;
7. resize and pixel-size transitions;
8. copied file-drop lifetime;
9. explicit finite native integration termination;
10. initial-domain enforcement and zero native-handle delta after teardown.
