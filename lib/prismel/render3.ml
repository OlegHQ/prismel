let save_png ~width ~height ?(background = Color.black) ~camera scene filename =
  match Renderer3d.capture ~width ~height ~background ~camera scene with
  | Error _ as error -> error
  | Ok colors ->
      (match Canvas.create ~width ~height with
       | Error _ as error -> error
       | Ok canvas ->
           Fun.protect ~finally:(fun () -> Canvas.destroy canvas) (fun () ->
             Canvas.map_pixels canvas (fun ~x ~y _ -> colors.((y * width) + x));
             Canvas.save_png canvas filename))
