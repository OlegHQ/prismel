open Prismel
open Procedural

let expanded_folders node =
  Node.parameter_fields node
  |> List.filter_map (fun field -> match field.Parameter.folder with
    | [] -> None
    | first :: _ -> Some first)
  |> List.sort_uniq String.compare

let initial_frame : Frame.t = {
  width = 1024; height = 720; size = 1024, 720;
  drawable_width = 1024; drawable_height = 720;
  drawable_size = 1024, 720; pixel_scale = 1., 1.;
  time = 0.; dt = 0.; fps = 0.; count = 0; mouse = 0., 0.;
  mouse_delta = 0., 0.; keys = []; mouse_buttons = []; events = [];
}

let viewport_frame (x, y, width, height) (frame : Frame.t) =
  let scale_x, scale_y = frame.pixel_scale in
  { frame with
    width; height; size = width, height;
    drawable_width = int_of_float (Float.round (float_of_int width *. scale_x));
    drawable_height = int_of_float (Float.round (float_of_int height *. scale_y));
    drawable_size =
      (int_of_float (Float.round (float_of_int width *. scale_x)),
       int_of_float (Float.round (float_of_int height *. scale_y)));
    mouse = (fst frame.mouse -. float x, snd frame.mouse -. float y) }
