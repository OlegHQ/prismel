let require condition message = if not condition then failwith message
let get = function
  | Ok value -> value
  | Error error -> failwith (Format.asprintf "%a" Prismel_next_execution.pp_error error)
let get_ir = function
  | Ok value -> value
  | Error _ -> failwith "scene2 coordinate IR"

let configuration ~logical_width ~logical_height ~drawable_width ~drawable_height =
  { Prismel_next_execution.default_configuration with
    logical_width; logical_height; drawable_width; drawable_height;
    title = "scene2-coordinates"; vsync = false;
    timing = Prismel_next_execution.Fixed (1. /. 60.) }

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

let render execution ir =
  let draws = get (Prismel_next_execution.lower_scene2 execution ~density:1
    ~resource:(fun _ -> None) ir) in
  ignore (get (Prismel_next_execution.step ~clear:(0., 0., 0., 1.) execution draws));
  get (Prismel_next_execution.capture execution)

let with_target ~logical_width ~logical_height ~drawable_width ~drawable_height f =
  match Prismel_next_execution.create_offscreen
    (configuration ~logical_width ~logical_height ~drawable_width ~drawable_height)
  with
  | Error _ -> print_endline "scene2 coordinates: skipped (no native Metal device)"
  | Ok execution ->
      Fun.protect
        ~finally:(fun () -> ignore (Prismel_next_execution.destroy execution))
        (fun () -> f execution)

let expect_square bytes ~width ~height ~x ~y ~size message =
  let bx, by, bw, bh = bbox bytes ~width ~height in
  require (bx = x && by = y && bw = size && bh = size)
    (Printf.sprintf
       "%s: expected square %dx%d at (%d,%d), got %dx%d at (%d,%d)"
       message size size x y bw bh bx by)

let () =
  let run ~logical_width ~logical_height ~drawable_width ~drawable_height ~scale =
    with_target ~logical_width ~logical_height ~drawable_width ~drawable_height
      (fun execution ->
        let facts = get (Prismel_next_execution.presentation_facts execution) in
        require (facts.logical_width = logical_width
          && facts.logical_height = logical_height
          && facts.drawable_width = drawable_width
          && facts.drawable_height = drawable_height)
          "offscreen logical/drawable facts";
        let open Scene_command.Render_ir in
        let square_ir = get_ir (create [| Geometry square_geometry |]) in
        let square = render execution square_ir in
        require (Bytes.length square = drawable_width * drawable_height * 4)
          "capture uses drawable pixels";
        expect_square square ~width:drawable_width ~height:drawable_height
          ~x:(8 * scale) ~y:(8 * scale) ~size:(16 * scale)
          (Printf.sprintf "%dx square" scale);
        let clipped_ir = get_ir (create [|
          Push_clip { x = 40.; y = 0.; width = 24.; height = 32. };
          Geometry square_geometry;
          Pop_clip |]) in
        (* Square at (8,8) sits outside the tall clip, so the clip must not
           remap window NDC into the panel or leftover fill would appear. *)
        let clipped = render execution clipped_ir in
        let _, _, bw, bh = try
          bbox clipped ~width:drawable_width ~height:drawable_height
        with Failure _ -> 0, 0, 0, 0 in
        require (bw = 0 && bh = 0)
          (Printf.sprintf "%dx clip used as viewport leaked out-of-clip fill" scale);
        let inside_ir = get_ir (create [|
          Push_clip { x = 40.; y = 0.; width = 24.; height = 32. };
          Geometry { vertices = [| 44.; 8.; 60.; 8.; 60.; 24.; 44.; 24. |];
            indices = [| 0; 1; 2; 0; 2; 3 |]; color = white };
          Pop_clip |]) in
        let inside = render execution inside_ir in
        expect_square inside ~width:drawable_width ~height:drawable_height
          ~x:(44 * scale) ~y:(8 * scale) ~size:(16 * scale)
          (Printf.sprintf "%dx clipped square" scale);
        let circle_ir = get_ir (create [| Geometry circle_geometry |]) in
        let circle = render execution circle_ir in
        let _, _, cw, ch = bbox circle ~width:drawable_width ~height:drawable_height in
        require (abs (cw - ch) <= 2)
          (Printf.sprintf "%dx circle bounding box was %dx%d" scale cw ch);
        require (abs (cw - 16 * scale) <= 2)
          (Printf.sprintf "%dx circle diameter was %d" scale cw))
  in
  run ~logical_width:64 ~logical_height:32 ~drawable_width:64 ~drawable_height:32 ~scale:1;
  run ~logical_width:64 ~logical_height:32 ~drawable_width:128 ~drawable_height:64 ~scale:2;
  print_endline
    "scene2 coordinates: 1x/2x headless square, clipped square, circle"
