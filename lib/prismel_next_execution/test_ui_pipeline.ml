(* The PXUI instance pipeline must light exactly the pixels the Scene2
   triangle path lights for the design kit's square fills, 1-point strokes,
   and axis-aligned marker lines, at 1x and 2x density. *)
let get = function
  | Ok value -> value
  | Error error ->
      failwith (Format.asprintf "%a" Prismel_next_execution.pp_error error)

let rgba r g b a =
  Int32.logor (Int32.shift_left (Int32.of_int r) 24)
    (Int32.logor (Int32.shift_left (Int32.of_int g) 16)
       (Int32.logor (Int32.shift_left (Int32.of_int b) 8) (Int32.of_int a)))

let fill = rgba 220 227 222 255
let stroke = rgba 34 43 43 180
let accent = rgba 40 95 119 175
let marker = rgba 34 43 43 255

(* x, y, w, h with fill and stroke, as Scene.rect ~fill ~stroke. *)
let shapes = [ 3, 4, 20, 9; 30, 2, 17, 15; 5, 20, 40, 11 ]

let old_ir () =
  let commands = ref [] in
  let add geometry = commands := Scene_command.Render_ir.Geometry geometry :: !commands in
  List.iter (fun (x, y, w, h) ->
    Array.iter add (Scene_command.Shape2.rect ~x ~y ~width:w ~height:h
      ~fill:(Some fill) ~stroke:(Some stroke))) shapes;
  Array.iter add (Scene_command.Shape2.rect ~x:5 ~y:24 ~width:17 ~height:3
    ~fill:(Some accent) ~stroke:None);
  add (Scene_command.Shape2.line ~from_:(22, 22) ~to_:(22, 29) ~width:2
    ~color:marker);
  add (Scene_command.Shape2.line ~from_:(52, 5) ~to_:(52, 30) ~width:1
    ~color:stroke);
  add (Scene_command.Shape2.line ~from_:(49, 18) ~to_:(60, 18) ~width:1
    ~color:stroke);
  match Scene_command.Render_ir.create (Array.of_list (List.rev !commands)) with
  | Ok ir -> ir
  | Error _ -> failwith "old IR"

let new_batch () =
  let builder = Scene_command.Ui_batch.Builder.create () in
  let rect = Scene_command.Ui_batch.Builder.rect builder in
  List.iter (fun (x, y, w, h) ->
    let x = float x and y = float y and width = float w and height = float h in
    rect ~x ~y ~width ~height ~color:fill ();
    rect ~x ~y ~width ~height ~border_color:stroke ~border:1. ()) shapes;
  rect ~x:5. ~y:24. ~width:17. ~height:3. ~color:accent ();
  (* A width-2 line is a 2-point rect centred on its axis. *)
  rect ~x:21. ~y:22. ~width:2. ~height:7. ~color:marker ();
  rect ~x:51.5 ~y:5. ~width:1. ~height:25. ~color:stroke ();
  rect ~x:49. ~y:17.5 ~width:11. ~height:1. ~color:stroke ();
  Scene_command.Ui_batch.Builder.publish builder

let capture execution lower =
  let submission = get (Prismel_next_execution.Private.begin_submission execution) in
  let batch = get (lower submission) in
  ignore (get (Prismel_next_execution.Private.step ~clear:(1., 1., 1., 1.)
    submission [ batch ]));
  get (Prismel_next_execution.capture execution)

(* The old stroke is four butt-capped segments without joins: it leaves each
   outer corner square of the 1-point band empty and blends each inner corner
   square twice (three times at 1x). The instance pipeline paints every band
   pixel exactly once. Those corner squares are the only permitted change. *)
let band_corner density (x, y) =
  let px = (float x +. 0.5) /. float density
  and py = (float y +. 0.5) /. float density in
  List.exists (fun (sx, sy, w, h) ->
    let near edge value = Float.abs (value -. float edge) <= 0.5 in
    (near sx px || near (sx + w) px) && (near sy py || near (sy + h) py)) shapes

let first_difference density width left right =
  let found = ref None in
  Bytes.iteri (fun index byte ->
    let pixel = index / 4 in
    let point = pixel mod width, pixel / width in
    if !found = None && byte <> Bytes.get right index
      && not (band_corner density point) then found := Some point)
    left;
  !found

let run () =
  List.iter (fun density ->
    let configuration = { Prismel_next_execution.
      logical_width = 64; logical_height = 40;
      drawable_width = 64 * density; drawable_height = 40 * density;
      title = "ui-pipeline"; vsync = false } in
    match Prismel_next_execution.create_offscreen configuration with
    | Error _ -> print_endline "UI pipeline: skipped (no native Metal device)"
    | Ok execution ->
        Fun.protect ~finally:(fun () ->
          ignore (Prismel_next_execution.destroy execution)) (fun () ->
          let resource _ = None in
          let expected = capture execution (fun submission ->
            Prismel_next_execution.Private.lower_scene2 submission ~density
              ~resource (old_ir ())) in
          let actual = capture execution (fun submission ->
            Prismel_next_execution.Private.lower_ui submission ~density
              ~resource (new_batch ())) in
          (match first_difference density (64 * density) expected actual with
           | None -> ()
           | Some (x, y) ->
               let offset = ((y * 64 * density) + x) * 4 in
               let show bytes = String.concat "," (List.init 4 (fun k ->
                 string_of_int (Char.code (Bytes.get bytes (offset + k))))) in
               failwith (Printf.sprintf
                 "density %d: UI pixel (%d,%d) is %s, Scene2 draws %s"
                 density x y (show actual) (show expected)));
          Printf.printf "UI pipeline matches Scene2 at %dx\n%!" density))
    [ 1; 2 ]
