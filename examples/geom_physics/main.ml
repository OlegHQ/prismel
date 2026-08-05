open Prismel
open Geom

type model = { world : Verlet2.t; frames_left : int option }

let columns = 26
let rows = 15
let index column row = (row * columns) + column

let init _frame =
  let particles = List.init (columns * rows) (fun flat ->
    let column = flat mod columns and row = flat / columns in
    let wave =
      24. *. sin (float_of_int column *. 0.42)
      *. sin (float_of_int row /. float_of_int (rows - 1) *. Float.pi)
    in
    Verlet2.particle ~locked:(row = 0 && column mod 5 = 0)
      (Vec2.create (130. +. (float_of_int column *. 25.))
         (74. +. (float_of_int row *. 25.) +. wave))) in
  let springs = ref [] in
  for row = 0 to rows - 1 do
    for column = 0 to columns - 1 do
      let add dc dr rest strength =
        if column + dc < columns && row + dr < rows then
          springs := Verlet2.spring ~rest_length:rest ~strength
              (index column row) (index (column + dc) (row + dr)) :: !springs in
      add 1 0 25. 0.78; add 0 1 25. 0.78;
      add 1 1 (25. *. sqrt 2.) 0.28;
      if column > 0 && row + 1 < rows then
        springs := Verlet2.spring ~rest_length:(25. *. sqrt 2.) ~strength:0.28
            (index column row) (index (column - 1) (row + 1)) :: !springs
    done
  done;
  let bounds = Bounds2.make ~min:(Vec2.create 30. 50.) ~max:(Vec2.create 870. 535.) in
  let world = Verlet2.create ~drag:0.015 ~iterations:5
      ~behaviors:[Verlet2.gravity (Vec2.create 0. 650.)]
      ~constraints:[Verlet2.inside_bounds bounds]
      particles !springs |> function Ok value -> value | Error message -> failwith message in
  { world; frames_left = if Sketch.is_headless () then Some 3 else None }

let update model (frame : Frame.t) =
  let frames_left = match model.frames_left with
    | Some 1 -> Sketch.quit (); Some 0 | Some count -> Some (count - 1) | None -> None in
  { world = Verlet2.step ~dt:frame.dt model.world; frames_left }

let view model _frame =
  let particles = Array.of_list (Verlet2.particles model.world) in
  let strands = Verlet2.springs model.world
      |> List.map (fun (spring : Verlet2.spring) ->
    let a = Verlet2.position particles.(spring.a)
    and b = Verlet2.position particles.(spring.b) in
    Scene.line ~from_:(Vec2.to_pair a) ~to_:(Vec2.to_pair b)
      ~color:(Color.rgba 103 232 249 72) ()) in
  let pins = Verlet2.particles model.world |> List.filter Verlet2.locked
      |> List.map (fun particle -> Scene.circle ~at:(Vec2.to_pair (Verlet2.position particle))
          ~radius:4 ~fill:(Color.hex_exn "#fbbf24") ()) in
  Scene.clear (Color.hex_exn "#050816")
  :: Scene.text ~at:(18, 16) ~size:17 "Geom · immutable Verlet cloth"
  :: Scene.text ~at:(18, 43) ~size:12 "390 particles · weighted springs · constraints"
  :: strands @ pins

let config = { Sketch.default_config with width = 900; height = 580;
  title = "Prismel Geom physics"; clock = Sketch.Fixed (1. /. 60.) }

let () = match Sys.getenv_opt "PRISMEL_EXPORT_DIR" with
  | Some directory -> ignore (Sketch.export_state ~config ~directory
      ~prefix:"geom-physics" ~frames:1 ~init ~update ~view ())
  | None -> ignore (Sketch.run_state ~config ~init ~update ~view ())
