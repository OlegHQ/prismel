open Prismel

type particle = {
  x : float;
  y : float;
  vx : float;
  vy : float;
}

type model = {
  particles : particle list;
  frames_left : int option;
}

let make_particle index =
  let angle = float index *. 0.1 in
  {
    x = 400.;
    y = 300.;
    vx = cos angle *. (30. +. float (index mod 70));
    vy = sin angle *. (30. +. float (index mod 70));
  }

let init _frame =
  {
    particles = List.init 10_000 make_particle;
    frames_left = None;
  }

let step frame particle =
  let x = particle.x +. (particle.vx *. frame.Frame.dt) in
  let y = particle.y +. (particle.vy *. frame.dt) in
  let vx = if x < 0. || x >= float frame.width then -.particle.vx else particle.vx in
  let vy = if y < 0. || y >= float frame.height then -.particle.vy else particle.vy in
  { x; y; vx; vy }

let update model frame =
  let frames_left =
    match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0
    | Some count -> Some (count - 1)
    | None -> None
  in
  {
    particles = Parallel.map ~grain:256 (step frame) model.particles;
    frames_left;
  }

let view model _frame =
  let particles =
    List.map
      (fun particle ->
        Scene.point
          ~at:(int_of_float particle.x, int_of_float particle.y)
          ~color:Color.cyan ())
      model.particles
  in
  Scene.clear (Color.rgb 8 10 16) :: particles

let () =
  ignore
    (Sketch.run_state
      ~config:{ Sketch.default_config with
        title = "Prismel multicore particles";
        width = 800;
        height = 600;
      }
      ~init ~update ~view ())
