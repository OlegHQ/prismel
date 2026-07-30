open Prismel

let update time (frame : Frame.t) =
  if Frame.has_event
      (function
        | Event.KeyPressed Input.Escape
        | Event.KeyPressed (Input.KeyChar 'q') -> true
        | _ -> false)
      frame
  then Sketch.quit ();
  if Sketch.is_headless () && frame.count >= 3 then Sketch.quit ();
  time +. frame.dt

let view time (frame : Frame.t) =
  let circles =
    List.init 501 (fun index ->
      let y = index in
      let phase = float_of_int index *. 4. in
      let radius =
        50. +. (40. *. sin (time +. (phase *. 0.0037)))
        |> int_of_float
      in
      let x =
        250. +. (200. *. sin (time +. (phase *. 0.01)))
        |> int_of_float
      in
      let color =
        Color.rgb
          (int_of_float (127. +. (127. *. sin (phase *. 0.01))))
          (int_of_float (127. +. (127. *. sin (phase *. 0.011))))
          (int_of_float (127. +. (127. *. sin (phase *. 0.012))))
      in
      Scene.circle ~at:(x, y) ~radius ~fill:color ())
  in
  let center_x, center_y = frame.width / 2, frame.height / 2 in
  Scene.([
    clear Color.black;
    translate center_x center_y [
      rotate (Float.pi /. 2.) [
        translate (-center_x) (-center_y) [
          scale 2. 2. circles;
        ];
      ];
    ];
  ])

let () =
  ignore
    (Sketch.run_state
       ~config:{ Sketch.default_config with
         width = 500;
         height = 500;
         title = "Prismel generative sketch";
       }
       ~init:(fun _ -> 0.)
       ~update ~view ())
