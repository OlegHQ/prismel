open Prismel

type point = int * int

type stroke = {
  color : Color.t;
  width : int;
  points : point list;
  point_count : int;
}

type model = {
  strokes : stroke list;
  active : stroke option;
  color_index : int;
  brush_width : int;
  status : string;
  frames_left : int option;
}

let palette = [|
  Color.hex_exn "#22d3ee";
  Color.hex_exn "#fb7185";
  Color.hex_exn "#fbbf24";
  Color.hex_exn "#a78bfa";
|]

let toolbar_height = 92
let maximum_strokes = 128
let maximum_points = 4_096

let rec take count values =
  match count, values with
  | 0, _ | _, [] -> []
  | count, value :: rest -> value :: take (count - 1) rest

let inside ~x ~y ~w ~h (px, py) =
  px >= x && px < x + w && py >= y && py < y + h

let add_point stroke ((x, y) as point) =
  match stroke.points with
  | (last_x, last_y) :: _
    when ((x - last_x) * (x - last_x)) + ((y - last_y) * (y - last_y)) < 4 ->
      stroke
  | _ when stroke.point_count >= maximum_points -> stroke
  | _ ->
      { stroke with
        points = point :: stroke.points;
        point_count = stroke.point_count + 1;
      }

let finish_stroke model point =
  match model.active with
  | None -> model
  | Some stroke ->
      let stroke = add_point stroke point in
      {
        model with
        strokes = take maximum_strokes (stroke :: model.strokes);
        active = None;
        status = "Drag to draw";
      }

let cancel_stroke model =
  match model.active with
  | None -> model
  | Some stroke ->
      {
        model with
        strokes = take maximum_strokes (stroke :: model.strokes);
        active = None;
        status = "Drag to draw";
      }

let choose_toolbar_action model point =
  if inside ~x:8 ~y:8 ~w:62 ~h:34 point then
    { model with strokes = []; active = None; status = "Canvas cleared" }
  else if inside ~x:76 ~y:8 ~w:62 ~h:34 point then
    { model with
      strokes = (match model.strokes with [] -> [] | _ :: rest -> rest);
      active = None;
      status = "Undid the latest stroke";
    }
  else if inside ~x:144 ~y:8 ~w:62 ~h:34 point then
    let status =
      match Canvas.save_screen_png "prismel-drawing.png" with
      | Ok () ->
          "Saved prismel-drawing.png"
      | Error message -> message
    in
    { model with active = None; status }
  else
    let rec select_color index =
      if index = Array.length palette then None
      else if inside ~x:(215 + (index * 38)) ~y:8 ~w:30 ~h:34 point then
        Some index
      else select_color (index + 1)
    in
    match select_color 0 with
    | Some color_index -> { model with color_index; active = None }
    | None when inside ~x:8 ~y:50 ~w:36 ~h:34 point ->
        { model with brush_width = max 2 (model.brush_width - 2); active = None }
    | None when inside ~x:52 ~y:50 ~w:36 ~h:34 point ->
        { model with brush_width = min 32 (model.brush_width + 2); active = None }
    | None -> { model with active = None }

let handle_key model key =
  match Char.lowercase_ascii key with
  | 'c' -> { model with strokes = []; active = None; status = "Canvas cleared" }
  | 'z' ->
      { model with
        strokes = (match model.strokes with [] -> [] | _ :: rest -> rest);
        active = None;
        status = "Undid the latest stroke";
      }
  | '[' -> { model with brush_width = max 2 (model.brush_width - 2) }
  | ']' -> { model with brush_width = min 32 (model.brush_width + 2) }
  | 's' ->
      let status =
        match Canvas.save_screen_png "prismel-drawing.png" with
        | Ok () ->
            "Saved prismel-drawing.png"
        | Error message -> message
      in
      { model with status }
  | _ -> model

let update_event model = function
  | Event.MousePressed (Input.LeftButton, ((_, y) as point)) ->
      if y < toolbar_height then choose_toolbar_action model point
      else
        {
          model with
          active = Some {
            color = palette.(model.color_index);
            width = model.brush_width;
            points = [point];
            point_count = 1;
          };
          status = "Drawing";
        }
  | Event.MouseMoved point ->
      { model with active = Option.map (fun stroke -> add_point stroke point) model.active }
  | Event.MouseReleased (Input.LeftButton, point) -> finish_stroke model point
  | Event.PointerCancelled Input.LeftButton | Event.WindowFocusLost ->
      cancel_stroke model
  | Event.KeyPressed (Input.KeyChar key) -> handle_key model key
  | _ -> model

let init _frame = {
  strokes = [];
  active = None;
  color_index = 0;
  brush_width = 10;
  status = "Drag to draw";
  frames_left = if Sketch.is_headless () then Some 3 else None;
}

let update model (frame : Frame.t) =
  let model = List.fold_left update_event model frame.events in
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  { model with frames_left }

let stroke_scene stroke =
  let points = List.rev stroke.points in
  match points with
  | [] -> Scene.empty
  | [position] ->
      Scene.[circle ~at:position ~radius:(max 1 (stroke.width / 2))
        ~fill:stroke.color ()]
  | first :: rest ->
      let rec segments previous = function
        | [] -> []
        | point :: remaining ->
            Scene.line ~from_:previous ~to_:point ~width:stroke.width
              ~color:stroke.color ()
            :: segments point remaining
      in
      Scene.circle ~at:first ~radius:(max 1 (stroke.width / 2))
        ~fill:stroke.color ()
      :: segments first rest

let button ~at:(x, y) ~w label =
  Scene.[
    rounded_rect ~at:(x, y) ~w ~h:34 ~radius:6
      ~fill:(Color.hex_exn "#1f2937") ~stroke:(Color.hex_exn "#475569") ();
    text ~at:(x + 12, y + 8) ~size:14 label;
  ]

let view model (frame : Frame.t) =
  let strokes =
    Option.fold ~none:model.strokes ~some:(fun active -> active :: model.strokes)
      model.active
  in
  let stroke_nodes =
    List.rev_map (fun stroke -> Scene.group (stroke_scene stroke)) strokes
  in
  let swatches =
    Array.to_list
      (Array.mapi (fun index color ->
        let x = 230 + (index * 38) in
        Scene.circle ~at:(x, 25) ~radius:(if index = model.color_index then 12 else 9)
          ~fill:color ~stroke:Color.white ()) palette)
  in
  Scene.(
    clear (Color.hex_exn "#0b1020")
    :: stroke_nodes
    @ [
      rect ~at:(0, 0) ~w:frame.width ~h:toolbar_height
        ~fill:(Color.rgba 9 14 25 245) ();
      group (button ~at:(8, 8) ~w:62 "Clear");
      group (button ~at:(76, 8) ~w:62 "Undo");
      group (button ~at:(144, 8) ~w:62 "Save");
      group swatches;
      group (button ~at:(8, 50) ~w:36 "−");
      group (button ~at:(52, 50) ~w:36 "+");
      circle ~at:(112, 67) ~radius:(max 1 (model.brush_width / 2))
        ~fill:palette.(model.color_index) ();
      text ~at:(136, 58) ~size:13
        (Printf.sprintf "%d px · draw · S save" model.brush_width);
      text ~at:(12, frame.height - 26) ~size:13
        ~color:(Color.rgba 226 232 240 190) model.status;
    ])

let () =
  ignore
    (Sketch.run_state
       ~config:{
         Sketch.default_config with
         width = 800;
         height = 500;
         title = "Prismel freehand drawing";
       }
       ~init ~update ~view ())
