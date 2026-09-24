open Prismel

type model = {
  noise : Noise.t;
  phase : float;
  frames_left : int option;
}

let palette =
  List.map Color.hex_exn
    ["#101426"; "#244a72"; "#3ca6a6"; "#f2d16b"; "#f26444"]

let init _frame =
  {
    noise = Noise.create 2026;
    phase = 0.;
    frames_left = None;
  }

let update model (frame : Frame.t) =
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  { model with phase = model.phase +. frame.dt *. 0.15; frames_left }

let view model (frame : Frame.t) =
  let cell = 10 in
  let columns = (frame.width + cell - 1) / cell in
  let rows = (frame.height + cell - 1) / cell in
  let make_row row =
    List.init columns (fun column ->
      let value =
        Noise.fbm3 ~octaves:5 model.noise
          ~x:(float column *. 0.045)
          ~y:(float row *. 0.045)
          ~z:model.phase
      in
      Scene.rect ~at:(column * cell, row * cell) ~w:cell ~h:cell
        ~fill:(Color.gradient palette value) ())
  in
  Scene.clear (List.hd palette)
  :: (Parallel.map ~grain:4 make_row (List.init rows Fun.id) |> List.concat)

let () =
  ignore
    (Sketch.run_state
      ~config:{ Sketch.default_config with
        width = 800;
        height = 450;
        title = "Prismel seeded noise";
      }
      ~init ~update ~view ())
