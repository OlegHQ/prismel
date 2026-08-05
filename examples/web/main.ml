open Prismel

type model = {
  trail : (int * int) list;
  last_text : string;
  headless_frames : int;
}

let init _ = { trail = []; last_text = "type or drag"; headless_frames = 0 }

let update model (frame : Frame.t) =
  let trail =
    List.fold_left
      (fun trail -> function
        | Event.MouseMoved point -> point :: trail |> List.to_seq |> Seq.take 64
            |> List.of_seq
        | _ -> trail)
      model.trail frame.events
  and last_text =
    List.fold_left
      (fun text -> function Event.TextInput value -> value | _ -> text)
      model.last_text frame.events
  in
  let headless_frames = model.headless_frames + 1 in
  if Sketch.is_headless () && headless_frames >= 3 then Sketch.quit ();
  { trail; last_text; headless_frames }

let view model (frame : Frame.t) =
  let target = match Sketch.render_target () with
    | Sketch.Native -> "native"
    | Headless -> "headless"
    | Web -> "web" in
  Scene.[
    clear (Color.hex_exn "#080b12");
    group (List.rev_map (fun point -> circle ~at:point ~radius:5
      ~fill:(Color.rgba 58 210 190 110) ()) model.trail);
    circle ~at:frame.mouse ~radius:18 ~stroke:Color.cyan ();
    text ~at:(16, 16) ~size:18
      (Printf.sprintf "Prismel %s target · %d × %d" target frame.width frame.height);
    text ~at:(16, 44) ~size:15 ("input: " ^ model.last_text);
    text ~at:(16, frame.height - 28) ~size:13
      "Move/drag, type, resize, or drop a file into the browser canvas";
  ]

let () =
  ignore (Sketch.run_state
    ~config:{ Sketch.default_config with
      width = 800; height = 500; title = "Prismel web target";
      resizable = true;
    }
    ~init ~update ~view ())
