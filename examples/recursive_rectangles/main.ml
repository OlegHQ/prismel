open Prismel

type model = {
  noise : Noise.t;
  frames_left : int option;
}

type box = {
  x : int;
  y : int;
  w : int;
  h : int;
}

let clamp low high value = max low (min high value)

let cosine_palette t =
  let channel frequency phase =
    127.5 +. (127.5 *. cos (2. *. Float.pi *. ((frequency *. t) +. phase)))
    |> int_of_float
  in
  Color.rgb (channel 1.00 0.00) (channel 0.72 0.12) (channel 0.44 0.22)

let init _frame =
  {
    noise = Noise.create 451;
    frames_left = if Sketch.is_headless () then Some 3 else None;
  }

let update model (frame : Frame.t) =
  if Frame.has_event
      (function
        | Event.KeyPressed Input.Escape
        | Event.KeyPressed (Input.KeyChar 'q') -> true
        | _ -> false)
      frame
  then Sketch.quit ();
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  { model with frames_left }

let view model (frame : Frame.t) =
  let mouse_x, mouse_y = frame.mouse in
  let x_control =
    float (clamp 0 frame.width mouse_x) /. float (max 1 frame.width)
  and y_control =
    float (clamp 0 frame.height mouse_y) /. float (max 1 frame.height)
  in
  let iterations = 2 + int_of_float (y_control *. 6.) in
  let field_offset = x_control *. 8. in
  let rec split depth box =
    if depth = iterations || box.w < 24 || box.h < 24 then [box, depth]
    else
      let px = float box.x +. (float box.w *. 0.5)
      and py = float box.y +. (float box.h *. 0.5) in
      let decision =
        Noise.sample2 model.noise
          ~x:((px *. 0.018) +. field_offset +. (float depth *. 0.37))
          ~y:((py *. 0.018) -. field_offset +. (float depth *. 0.61))
      in
      let ratio = 0.3 +. (0.4 *. decision) in
      if (decision > 0.5 && box.w > 28) || box.h < 29 then
        let first = clamp 12 (box.w - 12) (int_of_float (float box.w *. ratio)) in
        split (depth + 1) { box with w = first }
        @ split (depth + 1)
            { box with x = box.x + first; w = box.w - first }
      else
        let first = clamp 12 (box.h - 12) (int_of_float (float box.h *. ratio)) in
        split (depth + 1) { box with h = first }
        @ split (depth + 1)
            { box with y = box.y + first; h = box.h - first }
  in
  let side =
    int_of_float
      (float (max 80 (min frame.width frame.height - 96)) /. sqrt 2.)
  in
  let leaves = split 0 { x = 0; y = 0; w = side; h = side } in
  let tiles =
    List.map
      (fun (box, depth) ->
        let cx = float box.x +. (float box.w *. 0.5)
        and cy = float box.y +. (float box.h *. 0.5) in
        let value =
          Noise.sample2 model.noise
            ~x:((cx *. 0.025) +. field_offset)
            ~y:((cy *. 0.025) +. (float depth *. 0.29))
        in
        let color =
          if value > 0.78 then Color.black
          else cosine_palette (value +. (x_control *. 0.35))
        in
        let gap = 3 in
        Scene.rect ~at:(box.x + gap, box.y + gap)
          ~w:(max 1 (box.w - (2 * gap))) ~h:(max 1 (box.h - (2 * gap)))
          ~fill:color ())
      leaves
  in
  let center_x = frame.width / 2 and center_y = frame.height / 2 in
  Scene.[
    clear (Color.hex_exn "#eee9df");
    translate center_x center_y [
      rotate (Float.pi /. 4.) [
        translate (-side / 2) (-side / 2) tiles;
      ];
    ];
  ]

let () =
  ignore
    (Sketch.run_state
       ~config:{ Sketch.default_config with
         width = 720;
         height = 720;
         title = "Recursive rectangles";
       }
       ~init ~update ~view ())
