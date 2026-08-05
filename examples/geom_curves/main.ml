open Prismel
open Geom

type model = {
  phase : float;
  frames_left : int option;
}

let palette =
  List.map Color.hex_exn
    ["#67e8f9"; "#818cf8"; "#c084fc"; "#f472b6"; "#fb7185"; "#fbbf24"]

let init _frame =
  {
    phase = 0.;
    frames_left = if Sketch.is_headless () then Some 3 else None;
  }

let update model (frame : Frame.t) =
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  {
    phase = model.phase +. frame.dt *. 0.35;
    frames_left;
  }

let control_curve phase center =
  List.init 16 (fun index ->
    let amount = float_of_int index /. 16. in
    let angle = (amount *. 2. *. Float.pi) +. (phase *. 0.3) in
    let radius =
      154.
      +. (42. *. sin ((amount *. 6. *. Float.pi) +. phase))
      +. (18. *. cos ((amount *. 14. *. Float.pi) -. phase))
    in
    Vec2.add center
      (Vec2.create (radius *. cos angle) (radius *. sin angle)))
  |> Curve2.create_exn ~closed:true

let formula_ring phase center index =
  let amount = float_of_int index /. 8. in
  Curve2.superformula
    ~rotation:(phase *. (0.12 +. (amount *. 0.08)))
    ~center ~radius:(72. +. (amount *. 250.))
    ~m:(5. +. float_of_int (index mod 4))
    ~n1:(0.35 +. (amount *. 1.4))
    ~n2:(0.8 +. (0.4 *. sin (phase +. amount)))
    ~n3:(0.8 +. (0.4 *. cos (phase -. amount)))
    ~resolution:(180 + (index * 14)) ()

let view model (frame : Frame.t) =
  let center =
    Vec2.create (float_of_int frame.width /. 2.)
      (float_of_int frame.height /. 2. +. 12.)
  in
  let control = control_curve model.phase center in
  let smoothed =
    List.init 4 (fun index ->
      let curve = Curve2.chaikin ~iterations:(index + 1) control in
      let color =
        Color.gradient palette (float_of_int index /. 3.)
        |> Fun.flip Color.with_alpha (80 + (index * 38))
      in
      Render2.curve ~width:(index + 1) ~color curve)
  in
  let formulae =
    List.init 8 (fun index ->
      let color =
        Color.gradient palette (float_of_int index /. 7.)
        |> Fun.flip Color.with_alpha 108
      in
      Render2.curve ~color (formula_ring model.phase center index))
  in
  let rose =
    Curve2.rose ~rotation:(-.model.phase *. 0.18)
      ~center ~radius:262. ~petals:7 ~resolution:720 ()
  in
  Scene.(
    [
      clear (Color.hex_exn "#050816");
      blend Add formulae;
      Render2.curve ~width:2
        ~color:(Color.rgba 255 255 255 28) control;
      blend Alpha smoothed;
      Render2.curve ~color:(Color.rgba 255 255 255 72) rose;
      Render2.points ~radius:3
        ~color:(Color.hex_exn "#f8fafc") (Curve2.points control);
      text ~at:(22, 18) ~size:17 "Geom · subdivision / superformula";
      text ~at:(22, 44) ~size:12
        "immutable curves · Chaikin smoothing · rose curves";
    ])

let config = {
  Sketch.default_config with
  width = 900;
  height = 600;
  title = "Prismel Geom curves";
  clock = Sketch.Fixed (1. /. 60.);
}

let () =
  match Sys.getenv_opt "PRISMEL_EXPORT_DIR" with
  | Some directory ->
      ignore
        (Sketch.export_state ~config ~directory ~prefix:"geom-curves"
           ~frames:1 ~init ~update ~view ())
  | None ->
      ignore (Sketch.run_state ~config ~init ~update ~view ())
