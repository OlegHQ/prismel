open Prismel

type model = {
  notes : Audio.Sample.t array;
  active : int option;
  frames_left : int option;
}

let frequencies =
  [|261.63; 293.66; 329.63; 349.23; 392.; 440.; 493.88; 523.25|]

let make_note frequency =
  match Audio.Sample.synth ~waveform:Audio.Sample.Sine
      ~frequency ~duration:0.25 () with
  | Ok sample -> sample
  | Error message -> failwith message

let init _frame =
  let notes = Array.map make_note frequencies in
  if Sketch.is_headless () then
    ignore (Audio.Sample.play ~volume:0. notes.(0));
  {
    notes;
    active = None;
    frames_left = if Sketch.is_headless () then Some 3 else None;
  }

let pressed_note (frame : Frame.t) =
  List.find_map
    (function
      | Event.KeyPressed (Input.KeyChar key) when key >= '1' && key <= '8' ->
          Some (Char.code key - Char.code '1')
      | Event.MousePressed (Input.LeftButton, (x, y))
        when y >= 150 && y < 310 && x >= 40 && x < 600 ->
          Some (min 7 ((x - 40) / 70))
      | _ -> None)
    frame.events

let update model (frame : Frame.t) =
  let active = pressed_note frame in
  Option.iter (fun index ->
    ignore (Audio.Sample.play model.notes.(index))) active;
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  { model with active; frames_left }

let view model _frame =
  let keys =
    Array.to_list
      (Array.mapi (fun index _ ->
        let fill =
          if model.active = Some index then Color.hex_exn "#22d3ee"
          else Color.hex_exn "#f8fafc"
        in
        Scene.rect ~at:(40 + (index * 70), 150) ~w:64 ~h:160
          ~fill ~stroke:(Color.hex_exn "#0f172a") ())
        model.notes)
  in
  Scene.clear (Color.hex_exn "#111827")
  :: Scene.text ~at:(40, 60) "Press 1–8 or click a key"
  :: keys

let stop model = Array.iter Audio.Sample.destroy model.notes

let () =
  ignore
    (Sketch.run_state
      ~config:{ Sketch.default_config with
        width = 640;
        height = 360;
        title = "Prismel audio";
      }
      ~init ~update ~view ~on_stop:stop ())
