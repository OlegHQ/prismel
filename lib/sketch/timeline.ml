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
  shortcuts : shortcuts option;
}

type change = Advanced | Paused_now | Resumed | Stopped_now | Reset_now | Seeked

let default_shortcuts = {
  pause = Input.KeyChar 'p';
  stop = Input.KeyChar 's';
  reset = Input.KeyChar 'r';
}

let create ?(shortcuts = Some default_shortcuts) () = {
  mode = Playing; time = 0.; frame = 0L; shortcuts;
}

let mode value = value.mode
let time value = value.time
let frame value = value.frame

let reset value = { value with mode = Playing; time = 0.; frame = 0L }, [Reset_now]
let stop value = { value with mode = Stopped; time = 0.; frame = 0L }, [Stopped_now]
let toggle_pause value = match value.mode with
  | Playing -> { value with mode = Paused }, [Paused_now]
  | Paused | Stopped -> { value with mode = Playing }, [Resumed]

(* Time follows the mean step observed so far (1/60 s before any), since the
   runtime clock may vary. Seeking pauses so playback does not fight a scrub. *)
let seek value ~frame =
  let frame = Int64.max 0L frame in
  let step = if value.frame > 0L then value.time /. Int64.to_float value.frame
    else 1. /. 60. in
  { value with mode = (if value.mode = Stopped then Stopped else Paused); frame;
    time = Int64.to_float frame *. step }, [Seeked]

let press key events = List.exists (function
  | Event.KeyPressed candidate -> candidate = key
  | _ -> false) events

let update value runtime_frame =
  let value, changes = match value.shortcuts with
    | Some keys when press keys.reset runtime_frame.Frame.events -> reset value
    | Some keys when press keys.stop runtime_frame.events -> stop value
    | Some keys when press keys.pause runtime_frame.events -> toggle_pause value
    | Some _ | None -> value, [] in
  match value.mode with
  | Playing when Float.is_finite runtime_frame.dt && runtime_frame.dt > 0. ->
      { value with time = value.time +. runtime_frame.dt;
        frame = Int64.succ value.frame }, Advanced :: changes
  | Playing | Paused | Stopped -> value, changes

let changed_context = List.exists (function
  | Advanced | Stopped_now | Reset_now | Seeked -> true
  | Paused_now | Resumed -> false)

let context ?(seed = 0L) ?domains ?grain ?cancel value =
  Procedural.Context.create ~frame:value.frame ~time:value.time ~seed
    ?domains ?grain ?cancel ()
