open Rays

let viewport_frame (x, y, width, height) (frame : Frame.t) =
  let _scale_x, _scale_y = frame.pixel_scale in
  { frame with
    width; height; size = width, height;

    mouse = (fst frame.mouse -. float x, snd frame.mouse -. float y) }
