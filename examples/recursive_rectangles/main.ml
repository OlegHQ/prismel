open Prismel

type model = {
  noise : Noise.t;
  color_scheme : int;
  x_control : float;
}

type box = {
  x : int;
  y : int;
  w : int;
  h : int;
}

let clamp low high value = max low (min high value)

let scheme_hash scheme =
  ((scheme + 1) * 1_103_515_245 + 12_345) land max_int

let palette_color scheme tile_id =
  let tile_hash =
    ((tile_id * 73_856_093) lxor (tile_id * tile_id * 19_349_663)) land max_int
  in
  let seed = scheme_hash scheme and slot = tile_hash mod 8 in
  let base_hue = float (seed mod 360_000) /. 1_000. in
  let harmony = (seed / 360_000) mod 5 in
  let offset =
    match harmony, slot with
    | 0, _ -> float ((slot * 13) - 46)
    | 1, n when n < 4 -> float ((n * 8) - 12)
    | 1, n -> 180. +. float (((n - 4) * 8) - 12)
    | 2, n when n < 3 -> float ((n * 7) - 7)
    | 2, n when n < 6 -> 150. +. float (((n - 3) * 7) - 7)
    | 2, n -> 210. +. float (((n - 6) * 7) - 4)
    | 3, n -> float ((n mod 3) * 120) +. float ((n / 3) * 7)
    | _, n -> float ((n mod 4) * 90) +. float ((n / 4) * 9)
  in
  let jitter = float ((tile_hash / 97) mod 900) /. 100. -. 4.5 in
  let saturation = 0.56 +. (float ((seed / 31 + slot * 47) mod 260) /. 1_000.) in
  let lightness = 0.34 +. (float ((seed / 73 + slot * 83) mod 330) /. 1_000.) in
  Color.hsl (base_hue +. offset +. jitter) saturation lightness

let background scheme =
  let hue = float (scheme_hash scheme mod 360_000) /. 1_000. in
  Color.hsl hue 0.16 0.93

let init _frame =
  {
    noise = Noise.create 451;
    color_scheme = 0;
    x_control = 0.5;
  }

let update model (frame : Frame.t) =
  if Frame.has_event
      (function
        | Event.KeyPressed Input.Escape
        | Event.KeyPressed (Input.KeyChar 'q') -> true
        | _ -> false)
      frame
  then Sketch.quit ();
  let color_scheme =
    if Frame.has_event
        (function Event.MousePressed (Input.LeftButton, _) -> true | _ -> false)
        frame
    then model.color_scheme + 1
    else model.color_scheme
  in
  let mouse_x, _ = frame.mouse in
  let target_x =
    float (clamp 0 frame.width mouse_x) /. float (max 1 frame.width)
  in
  let damping = 1. -. exp (-.10. *. max 0. frame.dt) in
  let x_control = model.x_control +. ((target_x -. model.x_control) *. damping) in
  { model with color_scheme; x_control }

let view model (frame : Frame.t) =
  let _, mouse_y = frame.mouse in
  let x_control = model.x_control
  and y_control =
    float (clamp 0 frame.height mouse_y) /. float (max 1 frame.height)
  in
  let iterations = 4 + int_of_float (y_control *. 12.) in
  let field_offset = x_control *. 8. in
  let rec split depth tile_id box =
    let min_child = 3 in
    let can_split_x = box.w >= 2 * min_child
    and can_split_y = box.h >= 2 * min_child in
    if depth = iterations || (not can_split_x && not can_split_y) then
      [box, tile_id]
    else
      let px = float box.x +. (float box.w *. 0.5)
      and py = float box.y +. (float box.h *. 0.5) in
      let ratio_noise =
        Noise.sample2 model.noise
          ~x:((px *. 0.018) +. field_offset +. (float depth *. 0.37))
          ~y:((py *. 0.018) -. field_offset +. (float depth *. 0.61))
      in
      let orientation_noise =
        float ((tile_id * 1_103_515_245 + 12_345) land 0xffff) /. 65_535.
      in
      let ratio = 0.14 +. (0.72 *. ratio_noise) in
      if can_split_x && ((not can_split_y) || orientation_noise > 0.5) then
        let first =
          clamp min_child (box.w - min_child)
            (int_of_float (float box.w *. ratio))
        in
        split (depth + 1) (tile_id * 2) { box with w = first }
        @ split (depth + 1) ((tile_id * 2) + 1)
            { box with x = box.x + first; w = box.w - first }
      else
        let first =
          clamp min_child (box.h - min_child)
            (int_of_float (float box.h *. ratio))
        in
        split (depth + 1) (tile_id * 2) { box with h = first }
        @ split (depth + 1) ((tile_id * 2) + 1)
            { box with y = box.y + first; h = box.h - first }
  in
  let side =
    int_of_float
      (float (max 80 (min frame.width frame.height - 96)) /. sqrt 2.)
  in
  let leaves = split 0 1 { x = 0; y = 0; w = side; h = side } in
  let tiles =
    List.map
      (fun (box, tile_id) ->
        let color = palette_color model.color_scheme tile_id in
        let seam = 1 in
        Scene.rect ~at:(box.x, box.y)
          ~w:(max 1 (box.w - seam)) ~h:(max 1 (box.h - seam))
          ~fill:color ())
      leaves
  in
  let center_x = frame.width / 2 and center_y = frame.height / 2 in
  Scene.[
    clear (background model.color_scheme);
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
