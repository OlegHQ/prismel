open Prismel

type mode = Playing | Paused | Stopped

type shortcuts = {
  pause : Input.key;
  stop : Input.key;
  reset : Input.key;
}

type t = {
  mode : mode;
  time : float;
  frame : int64;
  shortcuts : shortcuts;
}

type change = Advanced | Paused_now | Resumed | Stopped_now | Reset_now

let default_shortcuts = {
  pause = Input.KeyChar 'p';
  stop = Input.KeyChar 's';
  reset = Input.KeyChar 'r';
}

let create ?(shortcuts = default_shortcuts) () = {
  mode = Playing; time = 0.; frame = 0L; shortcuts;
}

let mode value = value.mode
let time value = value.time
let frame value = value.frame

let press key events = List.exists (function
  | Event.KeyPressed candidate -> candidate = key
  | _ -> false) events

let update value runtime_frame =
  let value, changes =
    if press value.shortcuts.reset runtime_frame.Frame.events then
      { value with mode = Playing; time = 0.; frame = 0L }, [Reset_now]
    else if press value.shortcuts.stop runtime_frame.events then
      { value with mode = Stopped; time = 0.; frame = 0L }, [Stopped_now]
    else if press value.shortcuts.pause runtime_frame.events then
      match value.mode with
      | Playing -> { value with mode = Paused }, [Paused_now]
      | Paused | Stopped -> { value with mode = Playing }, [Resumed]
    else value, []
  in
  match value.mode with
  | Playing when Float.is_finite runtime_frame.dt && runtime_frame.dt > 0. ->
      { value with time = value.time +. runtime_frame.dt;
        frame = Int64.succ value.frame }, Advanced :: changes
  | Playing | Paused | Stopped -> value, changes

let changed_context = List.exists (function
  | Advanced | Stopped_now | Reset_now -> true
  | Paused_now | Resumed -> false)

let context ?(seed = 0L) ?domains ?grain ?cancel value =
  Procedural.Context.create ~frame:value.frame ~time:value.time ~seed
    ?domains ?grain ?cancel ()
