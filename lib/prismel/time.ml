(* Time and Animation Management Module *)

open Tsdl

(* Internal state *)
let start_time = ref None
let last_frame_time = ref 0.0
let delta_time = ref 0.0
let current_fps = ref 0.0
let target_fps = ref None
let vsync_enabled = ref true
let time_scale = ref 1.0

(* Initialize timing system *)
let init () =
  start_time := Some (Sdl.get_performance_counter ());
  last_frame_time := 0.0;
  delta_time := 0.0

(* Get current time in seconds since program start *)
let now () =
  match !start_time with
  | None -> 0.0
  | Some start ->
    let current = Sdl.get_performance_counter () in
    let freq = Sdl.get_performance_frequency () in
    Int64.to_float (Int64.sub current start) /. Int64.to_float freq

(* Get elapsed time since program start (alias for now) *)
let elapsed () = now ()

(* Get the delta time from the last frame *)
let get_delta_time () = !delta_time

(* Get current frame rate *)
let get_frame_rate () = !current_fps

(* Set target frame rate *)
let set_frame_rate fps =
  if fps > 0 then
    target_fps := Some fps
  else
    target_fps := None

(* Set vsync *)
let set_vsync enabled =
  vsync_enabled := enabled

(* Set time scale for slow motion or fast forward *)
let set_time_scale scale =
  time_scale := max 0.0 scale

(* Get current time scale *)
let get_time_scale () = !time_scale

(* Update timing - should be called each frame by the main loop *)
let update () =
  let current_time = now () in
  let raw_dt = current_time -. !last_frame_time in
  
  (* Clamp delta time to prevent huge jumps (max 0.1 seconds) *)
  let clamped_dt = min raw_dt 0.1 in
  
  (* Apply time scaling *)
  delta_time := clamped_dt *. !time_scale;
  
  (* Update FPS calculation *)
  if raw_dt > 0.0 then
    current_fps := 1.0 /. raw_dt
  else
    current_fps := 0.0;
  
  last_frame_time := current_time

(* Frame rate limiting - call after rendering *)
let limit_frame_rate () =
  match !target_fps with
  | None -> () (* No frame rate limit *)
  | Some _ when !vsync_enabled -> () (* Vsync handles limiting *)
  | Some fps ->
    let target_dt = 1.0 /. float_of_int fps in
    let current_dt = !delta_time /. !time_scale in (* Use unscaled dt for limiting *)
    if current_dt < target_dt then
      let delay_ms = int_of_float ((target_dt -. current_dt) *. 1000.0) in
      if delay_ms > 0 then
        Sdl.delay (Int32.of_int delay_ms)

(* Animation helper: calculate elapsed fraction between start_time and duration *)
let elapsed_fraction start_time duration =
  if duration <= 0.0 then 1.0
  else
    let elapsed = now () -. start_time in
    Math.clamp_float (elapsed /. duration) ~min:0.0 ~max:1.0

(* Easing functions *)
module Easing = struct
  (* Linear interpolation (no easing) *)
  let linear t = t
  
  (* Quadratic easing *)
  let ease_in_quad t = t *. t
  let ease_out_quad t = 1.0 -. (1.0 -. t) *. (1.0 -. t)
  let ease_in_out_quad t =
    if t < 0.5 then 2.0 *. t *. t
    else 1.0 -. 2.0 *. (1.0 -. t) *. (1.0 -. t)
  
  (* Cubic easing *)
  let ease_in_cubic t = t *. t *. t
  let ease_out_cubic t = 
    let u = 1.0 -. t in
    1.0 -. u *. u *. u
  let ease_in_out_cubic t =
    if t < 0.5 then 4.0 *. t *. t *. t
    else
      let u = 1.0 -. t in
      1.0 -. 4.0 *. u *. u *. u
  
  (* Quartic easing *)
  let ease_in_quart t = t *. t *. t *. t
  let ease_out_quart t =
    let u = 1.0 -. t in
    1.0 -. u *. u *. u *. u
  let ease_in_out_quart t =
    if t < 0.5 then 8.0 *. t *. t *. t *. t
    else
      let u = 1.0 -. t in
      1.0 -. 8.0 *. u *. u *. u *. u
  
  (* Quintic easing *)
  let ease_in_quint t = t *. t *. t *. t *. t
  let ease_out_quint t =
    let u = 1.0 -. t in
    1.0 -. u *. u *. u *. u *. u
  let ease_in_out_quint t =
    if t < 0.5 then 16.0 *. t *. t *. t *. t *. t
    else
      let u = 1.0 -. t in
      1.0 -. 16.0 *. u *. u *. u *. u *. u
  
  (* Sinusoidal easing *)
  let ease_in_sine t = 1.0 -. cos (t *. Math.half_pi)
  let ease_out_sine t = sin (t *. Math.half_pi)
  let ease_in_out_sine t = 0.5 *. (1.0 -. cos (t *. Math.pi))
  
  (* Exponential easing *)
  let ease_in_expo t = if t = 0.0 then 0.0 else 2.0 ** (10.0 *. (t -. 1.0))
  let ease_out_expo t = if t = 1.0 then 1.0 else 1.0 -. 2.0 ** (-10.0 *. t)
  let ease_in_out_expo t =
    if t = 0.0 then 0.0
    else if t = 1.0 then 1.0
    else if t < 0.5 then 0.5 *. 2.0 ** (20.0 *. t -. 10.0)
    else 0.5 *. (2.0 -. 2.0 ** (-20.0 *. t +. 10.0))
  
  (* Circular easing *)
  let ease_in_circ t = 1.0 -. sqrt (1.0 -. t *. t)
  let ease_out_circ t = sqrt (1.0 -. (t -. 1.0) *. (t -. 1.0))
  let ease_in_out_circ t =
    if t < 0.5 then 0.5 *. (1.0 -. sqrt (1.0 -. 4.0 *. t *. t))
    else 0.5 *. (sqrt (1.0 -. (2.0 *. t -. 2.0) *. (2.0 *. t -. 2.0)) +. 1.0)
  
  (* Back easing (overshoots) *)
  let ease_in_back t =
    let c1 = 1.70158 in
    let c3 = c1 +. 1.0 in
    c3 *. t *. t *. t -. c1 *. t *. t
  
  let ease_out_back t =
    let c1 = 1.70158 in
    let c3 = c1 +. 1.0 in
    1.0 +. c3 *. (t -. 1.0) *. (t -. 1.0) *. (t -. 1.0) +. c1 *. (t -. 1.0) *. (t -. 1.0)
  
  let ease_in_out_back t =
    let c1 = 1.70158 in
    let c2 = c1 *. 1.525 in
    if t < 0.5 then
      2.0 *. t *. t *. ((c2 +. 1.0) *. 2.0 *. t -. c2) /. 2.0
    else
      ((2.0 *. t -. 2.0) *. (2.0 *. t -. 2.0) *. ((c2 +. 1.0) *. (2.0 *. t -. 2.0) +. c2) +. 2.0) /. 2.0
  
  (* Elastic easing (bouncy) *)
  let ease_in_elastic t =
    let c4 = Math.two_pi /. 3.0 in
    if t = 0.0 then 0.0
    else if t = 1.0 then 1.0
    else -. (2.0 ** (10.0 *. t -. 10.0)) *. sin ((t *. 10.0 -. 10.75) *. c4)
  
  let ease_out_elastic t =
    let c4 = Math.two_pi /. 3.0 in
    if t = 0.0 then 0.0
    else if t = 1.0 then 1.0
    else (2.0 ** (-10.0 *. t)) *. sin ((t *. 10.0 -. 0.75) *. c4) +. 1.0
  
  let ease_in_out_elastic t =
    let c5 = Math.two_pi /. 4.5 in
    if t = 0.0 then 0.0
    else if t = 1.0 then 1.0
    else if t < 0.5 then
      -. (2.0 ** (20.0 *. t -. 10.0)) *. sin ((20.0 *. t -. 11.125) *. c5) /. 2.0
    else
      (2.0 ** (-20.0 *. t +. 10.0)) *. sin ((20.0 *. t -. 11.125) *. c5) /. 2.0 +. 1.0
  
  (* Bounce easing *)
  let ease_out_bounce t =
    let n1 = 7.5625 in
    let d1 = 2.75 in
    if t < 1.0 /. d1 then
      n1 *. t *. t
    else if t < 2.0 /. d1 then
      let t' = t -. (1.5 /. d1) in
      n1 *. t' *. t' +. 0.75
    else if t < 2.5 /. d1 then
      let t' = t -. (2.25 /. d1) in
      n1 *. t' *. t' +. 0.9375
    else
      let t' = t -. (2.625 /. d1) in
      n1 *. t' *. t' +. 0.984375
  
  let ease_in_bounce t = 1.0 -. ease_out_bounce (1.0 -. t)
  
  let ease_in_out_bounce t =
    if t < 0.5 then (1.0 -. ease_out_bounce (1.0 -. 2.0 *. t)) /. 2.0
    else (1.0 +. ease_out_bounce (2.0 *. t -. 1.0)) /. 2.0
end

(* Smoothstep function (ease in-out) *)
let smoothstep t = Math.smoothstep t

(* Convenience functions for common easing *)
let ease_in = Easing.ease_in_quad
let ease_out = Easing.ease_out_quad  
let ease_in_out = Easing.ease_in_out_quad

(* Animation scheduler - simple implementation *)
module Scheduler = struct
  type scheduled_event = {
    target_time: float;
    callback: unit -> unit;
  }
  
  let events = ref []
  
  let delay_call delay_seconds callback =
    let target_time = now () +. delay_seconds in
    events := { target_time; callback } :: !events
  
  let every interval callback =
    let rec schedule_next () =
      delay_call interval (fun () ->
        callback ();
        schedule_next ()
      )
    in
    schedule_next ()
  
  let update () =
    let current_time = now () in
    let (ready, waiting) = List.partition (fun event -> 
      current_time >= event.target_time
    ) !events in
    
    (* Execute ready events *)
    List.iter (fun event -> event.callback ()) ready;
    
    (* Keep waiting events *)
    events := waiting
end

(* Initialize the timing system *)
let () = init ()
