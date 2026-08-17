let save_png ~logical_width ~logical_height ~factor
    ?(background = Color.black) ~camera scene filename =
  if logical_width <= 0 || logical_height <= 0 then
    invalid_arg "Render2.save_png: logical dimensions must be positive";
  if factor <= 0 then invalid_arg "Render2.save_png: factor must be positive";
  let width = logical_width * factor and height = logical_height * factor in
  match Canvas.create ~width ~height with
  | Error _ as error -> error
  | Ok canvas ->
      Fun.protect ~finally:(fun () -> Canvas.destroy canvas) (fun () ->
        let viewport = 0, 0, width, height in
        Canvas.render canvas Scene.(clear background
          :: Easy_camera2.scene ~viewport ~pixel_scale:(float_of_int factor)
               camera scene);
        Canvas.save_png canvas filename)
