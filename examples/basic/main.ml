open Prismel

type model = {
  phase : float;
}

let init _frame =
  {
    phase = 0.;
  }

let update model (frame : Frame.t) =
  { phase = model.phase +. frame.dt }

let view model (frame : Frame.t) =
  let radius = 42 + int_of_float (10. *. sin (model.phase *. 2.)) in
  Scene.[
    clear (Color.rgb 20 22 28);
    circle ~at:(frame.width / 2, frame.height / 2) ~radius
      ~fill:(Color.rgb 90 170 240) ();
    text ~at:(12, 12)
      (Printf.sprintf "%d × %d  frame %d"
        frame.width frame.height frame.count);
  ]

let () =
  ignore
    (Sketch.run_state
      ~config:{ Sketch.default_config with
        width = 640;
        height = 360;
        title = "Prismel basic sketch";
      }
      ~init ~update ~view ())
