open Prismel

type model = {
  phase : float;
  frames_left : int option;
}

let init _frame =
  {
    phase = 0.;
    frames_left = if Sketch.is_headless () then Some 3 else None;
  }

let update model (frame : Frame.t) =
  let frames_left =
    match model.frames_left with
    | Some 1 ->
        Sketch.quit ();
        Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  { phase = model.phase +. frame.dt; frames_left }

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
