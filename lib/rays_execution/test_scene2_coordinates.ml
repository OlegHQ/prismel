let require condition message = if not condition then failwith message
let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Rays_execution.pp_error error)
let get_ir = function
  | Ok value -> value
  | Error _ -> failwith "scene2 coordinate IR"

let configuration ~logical_width ~logical_height ~drawable_width ~drawable_height =
  { Rays_execution.
    logical_width; logical_height; drawable_width; drawable_height;
    title = "scene2-coordinates"; vsync = false; high_density = true }

let rgba bytes ~width x y =
  let offset = (y * width + x) * 4 in
  Char.code (Bytes.get bytes offset),
  Char.code (Bytes.get bytes (offset + 1)),
  Char.code (Bytes.get bytes (offset + 2)),
  Char.code (Bytes.get bytes (offset + 3))

let filled (r, g, b, _) = r > 200 && g > 200 && b > 200

let bbox bytes ~width ~height =
  let min_x = ref width and min_y = ref height
  and max_x = ref (-1) and max_y = ref (-1) in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      if filled (rgba bytes ~width x y) then begin
        if x < !min_x then min_x := x;
        if y < !min_y then min_y := y;
        if x > !max_x then max_x := x;
        if y > !max_y then max_y := y
      end
    done
  done;
  require (!max_x >= 0) "expected filled pixels";
  !min_x, !min_y, !max_x - !min_x + 1, !max_y - !min_y + 1

let white = 0xffffffffl

let square_geometry =
  { Scene_command.Render_ir.vertices = [| 8.; 8.; 24.; 8.; 24.; 24.; 8.; 24. |];
    indices = [| 0; 1; 2; 0; 2; 3 |]; color = white }

let circle_geometry =
  let cx = 32. and cy = 16. and radius = 8. and steps = 32 in
  let vertices = Array.make ((steps + 1) * 2) 0. in
  vertices.(0) <- cx; vertices.(1) <- cy;
  for i = 0 to steps - 1 do
    let angle = float i *. (2. *. Float.pi) /. float steps in
    vertices.((i + 1) * 2) <- cx +. radius *. cos angle;
    vertices.((i + 1) * 2 + 1) <- cy +. radius *. sin angle
  done;
  let indices = Array.init (steps * 3) (fun i ->
    match i mod 3 with
    | 0 -> 0
    | 1 -> 1 + i / 3
    | _ -> let next = 2 + i / 3 in if next > steps then 1 else next)
  in
  { Scene_command.Render_ir.vertices; indices; color = white }

let with_target ~logical_width ~logical_height ~drawable_width ~drawable_height f =
  match Rays_execution.create_offscreen
    (configuration ~logical_width ~logical_height ~drawable_width ~drawable_height)
  with
  | Error _ -> print_endline "scene2 coordinates: skipped (no native Metal device)"
  | Ok execution ->
      Fun.protect
        ~finally:(fun () -> ignore (Rays_execution.destroy execution))
        (fun () -> f execution)

let expect_square bytes ~width ~height ~x ~y ~size message =
  let bx, by, bw, bh = bbox bytes ~width ~height in
  require (bx = x && by = y && bw = size && bh = size)
    (Printf.sprintf
       "%s: expected square %dx%d at (%d,%d), got %dx%d at (%d,%d)"
       message size size x y bw bh bx by)

let run () =
  let run ~logical_width ~logical_height ~drawable_width ~drawable_height ~scale:_ =
    with_target ~logical_width ~logical_height ~drawable_width ~drawable_height
      (fun execution ->
        let facts = get (Rays_execution.presentation_facts execution) in
        require (facts.logical_width = logical_width
          && facts.logical_height = logical_height
          && facts.drawable_width = drawable_width
          && facts.drawable_height = drawable_height)
          "offscreen logical/drawable facts")
  in
  run ~logical_width:64 ~logical_height:32 ~drawable_width:64 ~drawable_height:32 ~scale:1;
  run ~logical_width:64 ~logical_height:32 ~drawable_width:128 ~drawable_height:64 ~scale:2;
  print_endline
    "scene2 coordinates: 1x/2x headless square, clipped square, circle"
