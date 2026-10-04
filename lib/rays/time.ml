(* Private: the realtime clock and frame pacing behind [Sketch]'s loop. *)

let origin = ref (Unix.gettimeofday ())
let last_frame_time = ref 0.0
let delta_time = ref 0.0
let target_fps = ref None
let vsync_enabled = ref true

let init () =
  origin := Unix.gettimeofday ();
  last_frame_time := 0.0;
  delta_time := 0.0
let now () = Unix.gettimeofday () -. !origin
let delta () = !delta_time
let set_frame_rate fps = target_fps := if fps > 0 then Some fps else None
let set_vsync enabled = vsync_enabled := enabled
let update () =
  let current_time = now () in
  delta_time := Float.min (current_time -. !last_frame_time) 0.1;
  last_frame_time := current_time
let limit_frame_rate () = match !target_fps with
  | None -> ()
  | Some _ when !vsync_enabled -> ()
  | Some fps ->
      let delay = 1.0 /. float_of_int fps -. !delta_time in
      if delay > 0. then Unix.sleepf delay
