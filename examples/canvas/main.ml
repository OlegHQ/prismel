open Prismel

type model = {
  canvas : Canvas.t;
  texture : Image.t;
  frames_left : int option;
  status : string;
}

let leaf =
  Path.empty
  |> Path.move_to 128. 24.
  |> Path.cubic_to
       ~control1:(232., 54.) ~control2:(220., 196.) ~to_:(128., 232.)
  |> Path.cubic_to
       ~control1:(36., 196.) ~control2:(24., 54.) ~to_:(128., 24.)
  |> Path.close
  |> Path.move_to 128. 92.
  |> Path.line_to 158. 142.
  |> Path.line_to 98. 142.
  |> Path.close

let init _frame =
  let canvas = Canvas.create_exn ~width:256 ~height:256 in
  Canvas.render canvas Scene.[
    clear (Color.hex_exn "#111827");
    path ~fill:(Color.hex_exn "#34d399")
      ~stroke:(Color.hex_exn "#d1fae5") leaf;
    clip ~at:(64, 64) ~w:128 ~h:128 [
      rotate (Math.pi /. 4.) [
        rect ~at:(80, -30) ~w:18 ~h:300
          ~fill:(Color.rgba 255 255 255 70) ();
      ];
    ];
  ];
  let texture =
    match Canvas.to_image canvas with
    | Ok image -> image
    | Error message -> failwith message
  in
  {
    canvas;
    texture;
    frames_left = None;
    status = "Press S to save prismel-capture.png";
  }

let wants_capture (frame : Frame.t) =
  Frame.has_event
    (function Event.KeyPressed (Input.KeyChar 's') -> true | _ -> false)
    frame

let update model (frame : Frame.t) =
  let status =
    if wants_capture frame then
      match Canvas.save_screen_png "prismel-capture.png" with
      | Ok () -> "Saved prismel-capture.png"
      | Error message -> message
    else model.status
  in
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  { model with frames_left; status }

let view model (frame : Frame.t) =
  Scene.[
    clear (Color.hex_exn "#030712");
    image model.texture ~at:((frame.width - 256) / 2, 60) ();
    text ~at:(16, frame.height - 28) model.status;
  ]

let stop model =
  Image.destroy model.texture;
  Canvas.destroy model.canvas

let () =
  ignore
    (Sketch.run_state
      ~config:{ Sketch.default_config with
        width = 640;
        height = 400;
        title = "Prismel canvas and paths";
      }
      ~init ~update ~view ~on_stop:stop ())
