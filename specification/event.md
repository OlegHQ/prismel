# Event stream

`Event.t` is Prismel's owned, typed representation of native application
events. Runtime polls SDL3 on the initial OCaml domain, translates every
supported event in queue order, updates `Input`, and exposes the resulting list
through `Frame.events`.

## Public events

```ocaml
type t =
  | KeyPressed of Input.key
  | KeyReleased of Input.key
  | MouseMoved of int * int
  | MousePressed of Input.mouse_button * (int * int)
  | MouseReleased of Input.mouse_button * (int * int)
  | PointerCancelled of Input.mouse_button
  | MouseScrolled of int * int
  | TextInput of string
  | TextEditing of { text : string; start : int; length : int }
  | FileDropped of string
  | WindowResized of int * int
  | WindowFocusLost
  | WindowClosed
```

All strings are copied into OCaml ownership before SDL3 releases the native
event payload.

## Translation rules

- SDL3 key-down/up events map through the checked `Input.key` table. Printable
  key meaning and text entry remain separate; committed text comes from the
  text-input event.
- Pointer motion, button, and wheel events preserve poll order. Positions are
  logical points and motion contributes to the current frame's aggregate
  delta.
- The authoritative SDL3 pixel-size/window transition updates logical and
  drawable runtime facts coherently and emits one logical `WindowResized` fact.
- Focus loss clears held `Input` state before user update and emits
  `WindowFocusLost`.
- A requested native window close maps to `WindowClosed`; user code may request
  the same orderly stop through `Sketch.quit`.
- Pointer cancellation remains distinct from full focus loss.

Runtime does not collapse intermediate motion events. Applications that need
only the latest position use the `Input` snapshot; freehand drawing and gesture
code may consume every ordered motion.

## Processing

`Event.poll_events` obtains all pending events and updates Input state.
`process_events` applies an optional handler in order. `handle_events` combines
the two steps and returns the updated model plus the exact list.

`Sketch.run_state` normally handles this plumbing and supplies the immutable
event list in `Frame.t`. An update may fold it explicitly:

```ocaml
let update model (frame : Frame.t) =
  List.fold_left
    (fun model -> function
      | Event.KeyPressed Input.Space -> { model with paused = not model.paused }
      | Event.WindowClosed -> Sketch.quit (); model
      | _ -> model)
    model frame.events
```

## Ownership and domain contract

Event polling/waiting, window state changes, text-input activation, and input
snapshot mutation occur on the initial OCaml domain. Blocking waits may release
the OCaml runtime only inside the audited SDL3 binding and reacquire it before
constructing an OCaml value.

No user handler receives native pointers. File-drop and text values survive
after the poll iteration because they are owned copies.

## Regression requirements

1. queue order across mixed key, pointer, text, resize, drop, and close input;
2. mapping of known and unknown keys/buttons;
3. logical coordinates and exact aggregate motion delta;
4. focus-loss state clearing and pointer-cancellation separation;
5. UTF-8 and IME composition ranges;
6. copied file-drop lifetime after native payload release;
7. resize/drawable synchronization;
8. wrong-domain rejection;
9. finite multi-frame native integration and orderly teardown.
